extends Node
## Co-op over the network (Godot's ENet). One player hosts, the others join by
## address. Everyone flies their own plane in the same world and sees the
## others' planes and pilots; you can climb into someone else's plane as a
## passenger (to ride along, or to be rescued after a crash), and the pilot can
## hand you the controls. Each plane is simulated by its owner; everyone else
## sees it from the owner's updates, smoothed.
##
## Jobs and money stay each player's own for now.

const PlaneScript = preload("res://scripts/plane.gd")
const PlaneVisual = preload("res://scripts/plane_visual.gd")
const PilotModel = preload("res://scripts/pilot_model.gd")
const PilotRig = preload("res://scripts/pilot_rig.gd")
const PORT := 24680
const SEND_HZ := 15.0
## Passenger seats (eye positions in the plane): front right, rear left, rear right.
const SEATS := [Vector3(0.24, 0.80, -0.30), Vector3(-0.22, 0.76, 0.72), Vector3(0.22, 0.76, 0.72)]

signal status_changed(text: String)
signal note(text: String)

var main: Node                      # main.gd
var player_name := "Pilot"
var remotes := {}                   # peer id -> {name, node (plane), pilot, walker, snaps: [[t, state]], last}
var riding := 0                     # peer id of the plane we sit in as a passenger (0 = our own)
var seat := 0
var handed_to := 0                  # our plane: which peer has the controls (0 = us)
var have_control := false           # riding: we have the other plane's controls
var remote_input := {}              # inputs from whoever we handed the controls to
var _send_t := 0.0
var _clock := 0.0
var _asked_by := 0                  # a passenger asking for the controls
var _world_t := 0.0                 # host: when to send the world (season, time, weather) next
var _moved_apart := false           # guest: our plane moved off the host's spawn
var swings := 0                     # tool swings at other players (they play the motion when it ticks)


func is_online() -> bool:
	return _live() or not buddy.is_empty()


## Joined someone else's game (not hosting): the host's world rules.
func is_guest() -> bool:
	return _live() and not multiplayer.is_server()


## A real network connection (the stand-in buddy doesn't count).
func _live() -> bool:
	var mp = multiplayer.multiplayer_peer
	return mp != null and mp.get_class() != "OfflineMultiplayerPeer" \
		and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## ENet, made by name so builds without networking still run the rest of the game.
static func _enet() -> Object:
	if not ClassDB.class_exists("ENetMultiplayerPeer"):
		return null
	return ClassDB.instantiate("ENetMultiplayerPeer")


func host(port: int = PORT) -> String:
	leave()
	var peer = _enet()
	if peer == null:
		return "Networking isn't available in this build."
	var err: int = peer.create_server(port, 8)
	if err != OK:
		return "Could not open port %d (error %d)." % [port, err]
	multiplayer.multiplayer_peer = peer
	_hook()
	status_changed.emit("Hosting on port %d. Opening the port on your router..." % port)
	_open_port(port)
	return ""


# ------------------------------------------------------------------------------
#  Over the internet (DESIGN_NOTES 174): ask the router to open the port
#  (UPnP), off the main thread, and tell the host the address friends type.
# ------------------------------------------------------------------------------
var _upnp: Object                   # UPNP, made by name (like ENet) so builds without it still run
var _upnp_thread: Thread
func _open_port(port: int) -> void:
	if not ClassDB.class_exists("UPNP"):
		_upnp_done(null, "", port)
		return
	_upnp_thread = Thread.new()
	_upnp_thread.start(func() -> void:
		var u = ClassDB.instantiate("UPNP")
		var ok := false
		var ext := ""
		# 0 = UPNP_RESULT_SUCCESS
		if int(u.discover(2000, 2)) == 0 and u.get_gateway() != null and u.get_gateway().is_valid_gateway():
			if int(u.add_port_mapping(port, port, "Bush Pilot 2", "UDP")) == 0:
				ok = true
				ext = String(u.query_external_address())
		_upnp_done.call_deferred(u if ok else null, ext, port))


func _upnp_done(u: Object, ext: String, port: int) -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	_upnp = u
	var lan := local_address()
	if u != null and ext != "":
		status_changed.emit("Hosting. Over the internet friends join with %s  (port %d opened on your router). On your own network: %s" % [ext, port, lan])
	else:
		status_changed.emit("Hosting. On your own network friends join with %s. Your router wouldn't open the port by itself: for the internet, forward UDP port %d to this PC (%s) in the router's settings, or both use a virtual-LAN app." % [lan, port, lan])


## This PC's address on the home network.
static func local_address() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and a.count(".") == 3):
			return a
	return "this PC's address"


## Host: tell a new pilot which claim layout this world is (DESIGN_NOTES 174).
@rpc("authority", "reliable")
func _world_is(seed_v: int) -> void:
	if seed_v == int(Game.world_seed):
		return
	# (DESIGN_NOTES 175) take the host's world and come straight back in:
	# the claim, the creek and the gold laid out the same for both of you
	note.emit("Matching the host's world - reloading, then joining again...")
	Game.world_seed = seed_v
	Game.pending_join = _last_address
	Game.save_settings()
	load("res://scripts/ground.gd").use_seed(seed_v)
	leave()
	get_tree().reload_current_scene.call_deferred()


var _last_address := ""


func join(address: String, port: int = PORT) -> String:
	leave()
	_last_address = address
	var peer = _enet()
	if peer == null:
		return "Networking isn't available in this build."
	var err: int = peer.create_client(address, port)
	if err != OK:
		return "Could not reach %s (error %d)." % [address, err]
	multiplayer.multiplayer_peer = peer
	_hook()
	status_changed.emit("Joining %s..." % address)
	return ""


func leave() -> void:
	if _upnp != null:
		_upnp.delete_port_mapping(PORT, "UDP")
		_upnp = null
	if riding != 0:
		stop_riding(true)
	for id in remotes.keys():
		_drop(id)
	handed_to = 0
	multiplayer.multiplayer_peer = null
	status_changed.emit("Not connected.")


func _hook() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer):
		multiplayer.peer_connected.connect(_on_peer)
		multiplayer.peer_disconnected.connect(_on_gone)
		multiplayer.connected_to_server.connect(func(): status_changed.emit("Connected."))
		multiplayer.connection_failed.connect(func(): status_changed.emit("Could not connect."))
		multiplayer.server_disconnected.connect(func():
			status_changed.emit("The host left.")
			leave())


func _on_peer(id: int) -> void:
	print("net: peer ", id, " connected (server %s)" % multiplayer.is_server())
	note.emit("A pilot joined.")
	if multiplayer.is_server():
		_world_is.rpc_id(id, int(Game.world_seed))


func _on_gone(id: int) -> void:
	if remotes.has(id):
		note.emit("%s left." % remotes[id]["name"])
	if riding == id:
		stop_riding(true)
	if handed_to == id:
		handed_to = 0
	_drop(id)


func _drop(id: int) -> void:
	var r: Dictionary = remotes.get(id, {})
	for k in ["node", "walker"]:
		if r.get(k) != null and is_instance_valid(r[k]):
			(r[k] as Node).queue_free()
	remotes.erase(id)


# ------------------------------------------------------------------------------
#  Sending our state
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_clock += delta
	if not is_online() or main == null or main.plane == null:
		return
	if not buddy.is_empty():
		_buddy_tick(delta)
	_send_t -= delta
	if _live() and multiplayer.is_server():
		_world_t -= delta
		if _world_t <= 0.0:
			_world_t = 3.0
			_world_now.rpc({"map": Game.map, "season": Game.season, "time": Game.time_of_day, "weather": Game.weather,
				"wind": Game.wind_level, "wind_dir": Game.wind_dir_deg})
	if _send_t <= 0.0 and _live():
		_send_t = 1.0 / SEND_HZ
		_state.rpc(_my_state())
		if have_control and riding != 0:
			_ctl_input.rpc_id(riding, _my_input())
	_update_remotes()


func _my_state() -> Dictionary:
	var p: Node3D = main.plane
	var xf: Transform3D = p.global_transform
	var w: Node3D = main.walker
	return {
		"name": player_name, "reg": p.reg, "t": _clock,
		"o": xf.origin, "q": Quaternion(xf.basis.orthonormalized()), "v": p.vel,
		"ail": p.aileron, "ele": p.elevator, "rud": p.rudder, "flap": p.flaps, "rpm": p.rpm,
		"gear": p.gear_pos, "leg": p.leg_kind, "tyre": p.tyre_kind, "trim": p.trim,
		"comp": [p.wheel_comp[0], p.wheel_comp[1], p.wheel_comp[2]], "crashed": p.is_crashed,
		"doors": p.door_open, "foot": main.on_foot,
		"wo": w.global_position, "wy": w.yaw, "wv": Vector2(w.vel.x, w.vel.z).length(), "wg": w.grounded,
		"ride": riding, "seat": seat, "ctl": handed_to,
		"hand": main._hand_id if main.on_foot and main.inv != null and main._hand_id != "-" else "", "sw": swings, "dead": bool(main._foot_down),
		"lost": main.gore.lost_live(main.walker.model) if main.gore != null else [],
		"aim": bool(main.walker.aiming), "hr": int(main.hits_taken),
	}


func _my_input() -> Dictionary:
	var hz: Node = Game.hotas
	var pitch := clampf(Input.get_axis("pitch_down", "pitch_up") + hz.value("pitch"), -1.0, 1.0)
	var roll := clampf(Input.get_axis("roll_left", "roll_right") + hz.value("roll"), -1.0, 1.0)
	var yaw := clampf(Input.get_axis("yaw_left", "yaw_right") + hz.value("yaw"), -1.0, 1.0)
	var thr := Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down")
	return {"pitch": pitch, "roll": roll, "yaw": yaw, "thr": thr, "brake": Input.get_action_strength("brake"),
		"lever": hz.value("throttle") if hz.has_axis("throttle") else -1.0}


## From the host, every few seconds: the world as it is there. A guest's
## menu can't change these (DESIGN_NOTES 181).
@rpc("authority", "reliable")
func _world_now(w: Dictionary) -> void:
	if String(w.get("map", Game.map)) != Game.map:
		# the host is on the other map: go there and come straight back in
		note.emit("Matching the host's map - reloading, then joining again...")
		Game.map = String(w["map"])
		Game.pending_join = _last_address
		Game.save_settings()
		leave()
		get_tree().paused = false
		get_tree().reload_current_scene.call_deferred()
		return
	var changed := false
	if int(w.get("season", Game.season)) != Game.season:
		Game.season = int(w["season"])
		changed = true
	if int(w.get("weather", Game.weather)) != Game.weather:
		Game.weather = int(w["weather"])
		changed = true
	if int(w.get("wind", Game.wind_level)) != Game.wind_level:
		Game.wind_level = int(w["wind"])
		changed = true
	if absf(float(w.get("wind_dir", Game.wind_dir_deg)) - Game.wind_dir_deg) > 1.0:
		Game.wind_dir_deg = float(w["wind_dir"])
		changed = true
	var t := float(w.get("time", Game.time_of_day))
	var dt := absf(t - Game.time_of_day)
	if minf(dt, 24.0 - dt) > 0.1:
		Game.time_of_day = t
		changed = true
	if changed:
		Game.settings_changed.emit()


@rpc("any_peer", "unreliable_ordered")
func _state(s: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	var r: Dictionary = remotes.get(id, {})
	if r.is_empty():
		r = {"name": s.get("name", "Pilot"), "snaps": [], "node": null, "walker": null}
		remotes[id] = r
		note.emit("%s is here, flying %s." % [r["name"], s.get("reg", "")])
	r["name"] = s.get("name", r["name"])
	var snaps: Array = r["snaps"]
	snaps.append([_clock, s])
	while snaps.size() > 4:
		snaps.pop_front()
	r["last"] = s


@rpc("any_peer", "unreliable_ordered")
func _ctl_input(i: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() == handed_to:
		remote_input = i


# ------------------------------------------------------------------------------
#  Showing the others
# ------------------------------------------------------------------------------
func _update_remotes() -> void:
	for id in remotes.keys():
		var r: Dictionary = remotes[id]
		var snaps: Array = r["snaps"]
		if snaps.is_empty():
			continue
		var s: Dictionary = r["last"]
		if r["node"] == null:
			var pn: Node3D = PlaneScript.new()
			pn.name = "Remote_%d" % id
			pn.terrain = main.world.terrain
			main.add_child(pn)
			pn.frozen = true
			var vis: Node3D = PlaneVisual.new()
			vis.plane = pn
			pn.add_child(vis)
			var pilot: Node3D = PilotRig.new() if PilotRig.available() else PilotModel.new()
			vis.add_child(pilot)
			pilot.build()
			var wk: Node3D = PilotRig.new() if PilotRig.available() else PilotModel.new()
			main.add_child(wk)
			wk.build()
			r["node"] = pn
			r["vis"] = vis
			_apart_from(s)
			r["pilot"] = pilot
			r["walker"] = wk
		var pn2: Node3D = r["node"]
		if pn2.reg != String(s.get("reg", "")):
			pn2.reg = String(s.get("reg", ""))
		if pn2.leg_kind != String(s.get("leg", "spring")) or pn2.tyre_kind != String(s.get("tyre", "850")):
			pn2.leg_kind = String(s.get("leg", "spring"))
			pn2.tyre_kind = String(s.get("tyre", "850"))
			pn2.apply_gear()
		# Smooth: show them a tenth of a second behind, between the two updates around then.
		var xf := _sample(snaps, _clock - 0.12)
		pn2.global_transform = xf
		pn2.set("_cur_xf", xf)
		pn2.set("_prev_xf", xf)
		pn2.aileron = float(s.get("ail", 0.0))
		pn2.elevator = float(s.get("ele", 0.0))
		pn2.rudder = float(s.get("rud", 0.0))
		pn2.flaps = float(s.get("flap", 0.0))
		pn2.trim = float(s.get("trim", 0.0))
		pn2.gear_pos = float(s.get("gear", 1.0))
		pn2.gear_down = pn2.gear_pos > 0.5
		pn2.door_open = s.get("doors", pn2.door_open)
		var comp: Array = s.get("comp", [0.0, 0.0, 0.0])
		for i in range(3):
			pn2.wheel_comp[i] = float(comp[i])
		pn2.engine.rpm = float(s.get("rpm", 0.0))
		pn2.engine.running = pn2.engine.rpm > 300.0
		# Their pilot: in the seat, walking about, or riding in someone's plane.
		var pilot2: Node3D = r["pilot"]
		var wk2: Node3D = r["walker"]
		var foot: bool = s.get("foot", false)
		var ride: int = int(s.get("ride", 0))
		pilot2.visible = not foot and ride == 0
		if pilot2.visible:
			pilot2.position = Vector3(-0.24, 0.80, -0.32) - pilot2.eye_local()
			pilot2.animate(get_process_delta_time(), PilotModel.SIT, 0.0, _clock)
		wk2.visible = foot or ride != 0
		_remote_extras(r, s, wk2, foot)
		if bool(s.get("dead", false)):
			wk2.visible = false
			continue
		if foot:
			var wo: Vector3 = s.get("wo", Vector3.ZERO)
			wk2.global_transform = Transform3D(Basis(Vector3.UP, float(s.get("wy", 0.0))), wo)
			var v := float(s.get("wv", 0.0))
			var gait: int = PilotModel.IDLE if v < 0.25 else (PilotModel.WALK if v < 2.6 else PilotModel.RUN)
			if not bool(s.get("wg", true)):
				gait = PilotModel.AIR
			wk2.animate(get_process_delta_time(), gait, v, _clock)
		elif ride != 0:
			# Riding as a passenger: sit them in that plane.
			var host_xf: Transform3D
			if ride == multiplayer.get_unique_id():
				host_xf = main.plane.global_transform
			elif remotes.has(ride) and remotes[ride]["node"] != null:
				host_xf = (remotes[ride]["node"] as Node3D).global_transform
			else:
				wk2.visible = false
				continue
			var eye: Vector3 = SEATS[clampi(int(s.get("seat", 0)), 0, SEATS.size() - 1)]
			wk2.global_transform = host_xf * Transform3D(Basis.IDENTITY, eye - wk2.eye_local())
			wk2.animate(get_process_delta_time(), PilotModel.SIT, 0.0, _clock)


## Their figure: the tool in their hand, a swing when they make one, and a
## body on the ground when they're done for.
func _remote_extras(r: Dictionary, s: Dictionary, wk: Node3D, foot: bool) -> void:
	var hand: String = String(s.get("hand", "")) if foot else ""
	if hand != String(r.get("hand", "")) and wk.has_method("hold_tool") and main.inv != null:
		r["hand"] = hand
		var old_t: Node3D = r.get("tool_node")
		wk.hold_tool(null)
		if old_t != null and is_instance_valid(old_t):
			old_t.queue_free()
		r["tool_node"] = null
		if hand != "":
			var tn: Node3D = main.inv.build_mesh(hand)
			r["tool_node"] = tn
			wk.hold_tool(tn)
	var sw := int(s.get("sw", 0))
	if sw != int(r.get("sw", sw)):
		if hand == "pistol" or hand == "pistol_holster":
			main.pistol_fx(wk.global_position + Vector3(0, 1.2, 0) + wk.global_transform.basis * Vector3(0.25, 0, -0.5))
			if not bool(s.get("aim", false)) and wk.has_method("one_shot"):
				wk.one_shot("pistol_shoot", 1.6)
		elif not (wk.has_method("one_shot") and wk.one_shot("swing", 1.5)) and wk.has_method("work_motion"):
			wk.work_motion("dig" if hand == "shovel" else "pick")
	r["sw"] = sw
	if "aim" in wk:
		wk.aim = bool(s.get("aim", false)) and foot
	var hr := int(s.get("hr", 0))
	if hr != int(r.get("hr", hr)) and wk.has_method("one_shot"):
		wk.one_shot("hit_react", 1.6)
	r["hr"] = hr
	# parts they've lost (alive): off their figure here too; whole again after
	if main.gore != null:
		var lost: Array = s.get("lost", [])
		var rng0 := RandomNumberGenerator.new()
		rng0.randomize()
		for part in lost:
			if part != "head" and not wk.has_meta("lost_" + String(part)):
				main.gore.sever_live(wk, String(part), Vector3(0, 2.0, 0), rng0)
		if lost.is_empty() and not main.gore.lost_live(wk).is_empty():
			main.gore.restore_live(wk)
	var dead := bool(s.get("dead", false))
	if dead and not bool(r.get("dead", false)) and foot and main.gore != null and Game.gore:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var parts: Array = main.gore.pick_parts(0.55, rng)
		for p2 in s.get("lost", []):
			if not parts.has(p2):
				parts.append(p2)
		main.gore.scatter(Transform3D(Basis(Vector3.UP, float(s.get("wy", 0.0))), s.get("wo", Vector3.ZERO) as Vector3), "sprawl",
			parts, Vector3(0, 1.5, 0), rng, true)
	r["dead"] = dead


## Another player standing within a tool's reach in front of you, or 0.
func player_in_reach(p: Vector3, fwd: Vector3) -> int:
	var best := 0
	var bd := 2.4
	for id in remotes.keys():
		var s: Dictionary = remotes[id].get("last", {})
		if not bool(s.get("foot", false)) or bool(s.get("dead", false)):
			continue
		var to: Vector3 = (s.get("wo", Vector3.INF) as Vector3) - p
		if absf(to.y) > 1.5:
			continue
		to.y = 0.0
		var d := to.length()
		if d < bd and (d < 0.6 or fwd.dot(to / d) > 0.35):
			bd = d
			best = id
	return best


func player_pos(id: int) -> Vector3:
	return (remotes.get(id, {}).get("last", {}) as Dictionary).get("wo", Vector3.ZERO)


## Hit them: over the network, or the buddy here. Returns a line for you.
func hit_player(id: int, dmg: float, tool: String, from: Vector3, cut: String = "") -> String:
	var nm: String = remotes.get(id, {}).get("name", "them")
	if id == BUDDY:
		return _buddy_hurt(dmg, tool, cut, from)
	if _live():
		_hit.rpc_id(id, dmg, tool, from, player_name, cut)
	if cut == "head":
		return "Head shot: %s is down." % nm
	return "You %s %s%s." % ["shot" if tool == "pistol" else "hit", nm, "" if tool == "pistol" else " with the " + tool]


@rpc("any_peer", "reliable")
func _hit(dmg: float, tool: String, from: Vector3, who: String, cut: String = "") -> void:
	if main != null:
		main.take_hit(clampf(dmg, 0.0, 1.5), tool, from, who, cut)


## The player a shot along `dir` from `from` hits before `wall` metres:
## [id, head?, point] or []. A little forgiveness round the body.
func shot_target(from: Vector3, dir: Vector3, wall: float) -> Array:
	var best: Array = []
	var bt := wall
	for id in remotes.keys():
		var s: Dictionary = remotes[id].get("last", {})
		if not bool(s.get("foot", false)) or bool(s.get("dead", false)):
			continue
		var feet: Vector3 = s.get("wo", Vector3.INF)
		for zone in [["head", 1.62, 0.16], ["body", 1.15, 0.32], ["legs", 0.55, 0.26]]:
			var c: Vector3 = feet + Vector3(0, float(zone[1]), 0)
			var t := (c - from).dot(dir)
			if t <= 0.5 or t >= bt:
				continue
			var miss := (from + dir * t).distance_to(c)
			if miss < float(zone[2]) + t * 0.004:
				bt = t
				best = [id, zone[0] == "head", from + dir * t]
				break
	return best


## You shot someone's plane: the owner's game takes the damage.
func shoot_plane(id: int, part: String) -> void:
	if _live():
		_plane_shot.rpc_id(id, part)


@rpc("any_peer", "reliable")
func _plane_shot(part: String) -> void:
	if main != null and main.plane != null and main.plane.parts.has(part):
		main.plane.hurt(part, 0.06)


## You lit a stick: everyone else gets the same one, burning the same fuse.
func dynamite_lit(at: Vector3, vel: Vector3, fuse: float) -> void:
	if _live():
		_dyn.rpc(at, vel, fuse)


@rpc("any_peer", "reliable")
func _dyn(at: Vector3, vel: Vector3, fuse: float) -> void:
	if main != null and main.dynamite != null:
		main.dynamite.light(at, vel, fuse)


## A blast near the buddy (the network players get their own blast).
func blast_near(at: Vector3) -> void:
	if buddy.is_empty() or bool(buddy["dead"]) or not bool(buddy["foot"]):
		return
	var d: float = (buddy["pos"] as Vector3).distance_to(at)
	if d > 9.0:
		return
	var dmg := (1.0 - d / 9.0) * 1.3
	_buddy_hurt(dmg, "dynamite", "limb" if d < 5.0 and randf() < 0.75 else "", at)
	if bool(buddy["dead"]):
		note.emit("Buddy caught the blast.")


## Joining, both planes start on the same spot: a guest's plane (stopped,
## on the ground) moves over a wingspan and a half, beside the host's.
func _apart_from(s: Dictionary) -> void:
	if _moved_apart or multiplayer.is_server() or main.plane == null:
		return
	_moved_apart = true
	var p: Node3D = main.plane
	print("net: apart? my plane %s, theirs %s, speed %.1f" % [str(p.global_position.round()), str(s.get("o")), p.vel.length()])
	var theirs: Vector3 = s.get("o", Vector3.INF)
	if p.vel.length() > 1.0 or p.global_position.distance_to(theirs) > 14.0:
		return
	var t = main.world.terrain
	var from: Vector3 = p.global_position
	var to: Vector3 = from + p.global_transform.basis.x.normalized() * 18.0
	to.y = from.y + float(t.ground_level_at(to.x, to.z)) - float(t.ground_level_at(from.x, from.z))
	p.pos = p.pos + (to - from)          # the flight model's own position, then show it there
	p._snap_transform()
	if main.on_foot and main.walker != null and main.walker.global_position.distance_to(from) < 6.0:
		main.walker.place(main.walker.global_position + (to - from), main.walker.yaw)
	note.emit("Your plane is parked beside the host's.")


func _sample(snaps: Array, t: float) -> Transform3D:
	var a: Array = snaps[0]
	var b: Array = snaps[snaps.size() - 1]
	for i in range(snaps.size() - 1):
		if float(snaps[i][0]) <= t and float(snaps[i + 1][0]) >= t:
			a = snaps[i]
			b = snaps[i + 1]
	var sa: Dictionary = a[1]
	var sb: Dictionary = b[1]
	var span := float(b[0]) - float(a[0])
	var f := clampf((t - float(a[0])) / span, 0.0, 1.0) if span > 0.0001 else 1.0
	var o: Vector3 = (sa["o"] as Vector3).lerp(sb["o"], f)
	var q: Quaternion = (sa["q"] as Quaternion).slerp(sb["q"], f)
	return Transform3D(Basis(q), o)


# ------------------------------------------------------------------------------
#  Riding along, and handing over the controls
# ------------------------------------------------------------------------------
## A remote plane whose door we are standing at (stopped), or 0.
func plane_at_door(p: Vector3) -> int:
	for id in remotes.keys():
		var r: Dictionary = remotes[id]
		var pn: Node3D = r.get("node")
		if pn == null:
			continue
		var s: Dictionary = r["last"]
		if (s.get("v", Vector3.ZERO) as Vector3).length() > 1.0:
			continue
		var lp: Vector3 = pn.global_transform.affine_inverse() * p
		if absf(lp.x) > 0.4 and absf(lp.x) < 2.6 and lp.z > -1.6 and lp.z < 1.4:
			return id
	return 0


func start_riding(id: int) -> void:
	riding = id
	# Take the first seat nobody else has.
	var taken := {}
	for oid in remotes.keys():
		var s: Dictionary = remotes[oid].get("last", {})
		if int(s.get("ride", 0)) == id:
			taken[int(s.get("seat", 0))] = true
	seat = 0
	while taken.has(seat) and seat < SEATS.size() - 1:
		seat += 1
	have_control = false
	note.emit("You're riding with %s. %s asks for the controls, %s gets out." % [remotes[id]["name"], Game.hint("controls"), Game.hint("get_out")])


func stop_riding(_quiet: bool = false) -> void:
	if riding != 0 and have_control:
		_send(riding, "_give_back")
	riding = 0
	have_control = false


## The pilot's view while riding: the plane we sit in.
func ride_transform() -> Transform3D:
	if riding != 0 and remotes.has(riding) and remotes[riding]["node"] != null:
		return (remotes[riding]["node"] as Node3D).global_transform
	return main.plane.global_transform


## The controls key: a passenger asks (or gives them back); the pilot hands
## them over to whoever asked (or takes them back).
func controls_key() -> void:
	if riding != 0:
		if have_control:
			_send(riding, "_give_back")
			have_control = false
			note.emit("You've given the controls back.")
		else:
			_send(riding, "_ask")
			note.emit("You asked for the controls.")
	elif handed_to != 0:
		handed_to = 0
		remote_input = {}
		note.emit("You have the controls.")
	elif _asked_by != 0:
		handed_to = _asked_by
		_asked_by = 0
		_send(handed_to, "_granted")
		note.emit("%s has the controls. %s to take them back." % [remotes.get(handed_to, {}).get("name", "Your passenger"), Game.hint("controls")])


## A reliable message to one player: over the network, or straight to the buddy.
func _send(id: int, what: String) -> void:
	if id == BUDDY:
		_buddy_hears(what)
	elif _live():
		rpc_id(id, what)


@rpc("any_peer", "reliable")
func _ask() -> void:
	_asked_by = multiplayer.get_remote_sender_id()
	note.emit("%s asks for the controls. %s to hand them over." % [remotes.get(_asked_by, {}).get("name", "Your passenger"), Game.hint("controls")])
	if main != null and main._test.has("autohand"):
		controls_key()


@rpc("any_peer", "reliable")
func _granted() -> void:
	have_control = true
	note.emit("You have the controls.")


@rpc("any_peer", "reliable")
func _give_back() -> void:
	if multiplayer.get_remote_sender_id() == handed_to or handed_to == BUDDY:
		handed_to = 0
		remote_input = {}
		note.emit("You have the controls back.")



# ------------------------------------------------------------------------------
#  The buddy: a stand-in second player, run right here, for trying co-op
#  without a second computer (console: buddy). It looks and behaves to the
#  game exactly like someone joined over the network: their own plane parked
#  beside yours, a pilot who walks over to you, climbs into your plane when
#  you sit in it (and out again when you get out), takes and gives back the
#  controls, and flies their own plane round you when told to.
# ------------------------------------------------------------------------------
const BUDDY := 990001
const BUDDY_DOOR := Vector3(-1.3, 0.0, -0.1)       # plane space, where a passenger climbs in
var buddy := {}                                   # mode, pos, yaw, speed, plane xf, flight, timers


func buddy_cmd(arg: String) -> String:
	if main == null or main.plane == null:
		return "No game running."
	match arg:
		"", "on", "spawn":
			if not buddy.is_empty():
				return "Your buddy is already here (buddy off to send them home)."
			if _live():
				return "You're online already: no stand-in needed."
			_buddy_spawn()
			return "Your buddy is here. buddy fly / land / ask / come / stay / off"
		"off":
			if buddy.is_empty():
				return "No buddy."
			if riding == BUDDY:
				main._stop_riding()
			if handed_to == BUDDY:
				handed_to = 0
				remote_input = {}
			_drop(BUDDY)
			buddy = {}
			return "Your buddy went home."
	if buddy.is_empty():
		return "No buddy yet: type buddy first."
	match arg:
		"fly":
			if buddy["mode"] == "ride":
				return "They're riding with you."
			buddy["mode"] = "board_own"
			return "Your buddy is heading for their plane."
		"land":
			buddy["mode"] = "land"
			return "Your buddy is coming back in to land."
		"ask":
			if riding == BUDDY:
				return "You're in their plane: they have the controls."
			if buddy["mode"] != "ride":
				return "They'd have to be riding with you."
			_asked_by = BUDDY
			note.emit("Buddy asks for the controls. %s to hand them over." % Game.hint("controls"))
			return "Asked."
		"come":
			buddy["mode"] = "follow"
			return "Your buddy follows you."
		"stay":
			buddy["mode"] = "stay"
			return "Your buddy waits here."
		"fight":
			if buddy["mode"] in ["ride", "takeoff", "orbit", "land", "yours"]:
				return "Not while he's flying."
			buddy["mode"] = "fight"
			buddy["hand"] = "pick"
			return "Buddy picked up a pick and is coming for you."
		"peace":
			buddy["mode"] = "follow"
			buddy["hand"] = ""
			return "Buddy put the pick down."
	return "buddy [on|off|fly|land|ask|come|stay|fight|peace]"


func _buddy_spawn() -> void:
	var pxf: Transform3D = main.plane.global_transform
	var t = main.world.terrain
	var flat := Basis(Vector3.UP, atan2(-pxf.basis.z.x, -pxf.basis.z.z))
	var on_ground: bool = main.plane.vel.length() < 1.0 and pxf.origin.y - float(t.ground_level_at(pxf.origin.x, pxf.origin.z)) < 4.0
	var park_h: float = pxf.origin.y - float(t.ground_level_at(pxf.origin.x, pxf.origin.z)) if on_ground else 1.4
	# Their plane: 24 m off your right wing, same heading (yours if it's on the ground).
	var o: Vector3 = (main.walker.global_position if not on_ground else pxf.origin) + flat * Vector3(24.0, 0, 0)
	o.y = float(t.ground_level_at(o.x, o.z)) + park_h
	var pb: Basis = pxf.basis if on_ground else flat
	var wp: Vector3 = Transform3D(pb, o) * BUDDY_DOOR
	wp.y = float(t.ground_level_at(wp.x, wp.z))
	buddy = {"mode": "follow", "pos": wp, "yaw": 0.0, "speed": 0.0, "air": false,
		"pxf": Transform3D(pb, o), "park": Transform3D(pb, o), "park_h": park_h, "v": Vector3.ZERO,
		"rpm": 0.0, "ride": 0, "seat": 0, "foot": true, "t": 0.0, "wait": 0.0, "ang": 0.0, "fly_t": 0.0,
		"hp": 1.0, "dead": false, "hand": "", "sw": 0, "swing_t": 0.0, "lost": []}
	remotes[BUDDY] = {"name": "Buddy", "snaps": [], "node": null, "walker": null}
	note.emit("Buddy is here, flying C-FBDY.")


## A message from you to the buddy (what the network would have carried).
func _buddy_hears(what: String) -> void:
	match what:
		"_ask":                       # you're in their plane, asking for the controls
			buddy["wait"] = 1.2
			buddy["grant"] = true
		"_give_back":
			note.emit("Buddy has the controls back.")
		"_granted":
			note.emit("Buddy has the controls. %s to take them back." % Game.hint("controls"))


## You hit the buddy with something.
func _buddy_hurt(dmg: float, tool: String, cut: String = "", from: Vector3 = Vector3.INF) -> String:
	var b := buddy
	if bool(b["dead"]):
		return ""
	if from == Vector3.INF:
		from = main.walker.global_position
	var away: Vector3 = (b["pos"] as Vector3) - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	var wk: Node3D = remotes.get(BUDDY, {}).get("walker")
	if cut == "head":
		dmg = 9.0
		b["lost"] = (b.get("lost", []) as Array) + ["head"]
	elif cut == "limb" and wk != null and main.gore != null:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var part: String = ["arm_l", "arm_r", "leg_l", "leg_r"].pick_random()
		if main.gore.sever_live(wk, part, away * 3.0 + Vector3(0, 2.0, 0), rng):
			b["lost"] = (b.get("lost", []) as Array) + [part]
	b["hp"] = maxf(float(b["hp"]) - dmg, 0.0)
	b["hr"] = int(b.get("hr", 0)) + 1
	if tool != "pistol":
		b["pos"] = (b["pos"] as Vector3) + away * 0.6
	if float(b["hp"]) <= 0.0:
		b["dead"] = true
		b["dead_t"] = 0.0
		b["mode"] = "dead"
		if cut == "head":
			return "Head shot. Buddy's down. He'll be back in a bit."
		return "You did Buddy in with the %s. He'll be back in a bit." % tool
	if b["mode"] in ["follow", "stay"] and randf() < 0.5:
		b["mode"] = "fight"
		b["hand"] = "pick"
		return "You hit Buddy with the %s. Now he's mad." % tool
	if tool == "pistol":
		return "You shot Buddy. (%d%% left)" % int(float(b["hp"]) * 100.0)
	return "You hit Buddy with the %s. (%d%% left)" % [tool, int(float(b["hp"]) * 100.0)]


func _buddy_tick(delta: float) -> void:
	var b := buddy
	b["t"] = float(b["t"]) + delta
	var t = main.world.terrain
	var me_foot: bool = main.on_foot
	var me: Vector3 = main.walker.global_position
	var pl: Node3D = main.plane
	var pxf: Transform3D = pl.global_transform
	var mode: String = b["mode"]
	if b.has("grant"):
		b["wait"] = float(b["wait"]) - delta
		if float(b["wait"]) <= 0.0:
			b.erase("grant")
			have_control = true
			note.emit("Buddy hands you the controls.")
	# You climbed into their plane: they're in the left seat, and off you go.
	var aboard := riding == BUDDY
	if aboard and not bool(b.get("aboard", false)) and mode in ["follow", "stay", "board_own", "parked"]:
		b["mode"] = "parked"
		b["go"] = true
		b["fly_t"] = 0.0
		mode = "parked"
	b["aboard"] = aboard
	var goal := Vector3.INF
	var run := false
	match mode:
		"follow":
			b["foot"] = true
			b["ride"] = 0
			if me_foot or riding == BUDDY:
				var to_me: Vector3 = me - (b["pos"] as Vector3)
				to_me.y = 0.0
				if to_me.length() > 3.0:
					goal = me - to_me.normalized() * 2.5
					run = to_me.length() > 12.0
			elif pl.vel.length() < 1.0 and riding == 0:
				# You're in your plane and it's stopped: over to the door and in.
				goal = pxf * BUDDY_DOOR
				run = true
				if Vector2(goal.x - b["pos"].x, goal.z - b["pos"].z).length() < 0.6:
					b["mode"] = "ride"
					note.emit("Buddy climbed in with you.")
		"ride":
			b["foot"] = false
			b["ride"] = multiplayer.get_unique_id()
			b["pos"] = pxf * BUDDY_DOOR
			if me_foot:
				# You got out: so do they, at their door.
				var out: Vector3 = pxf * (BUDDY_DOOR + Vector3(-0.8, 0, 0))
				out.y = float(t.ground_level_at(out.x, out.z))
				b["pos"] = out
				b["mode"] = "follow"
				if handed_to == BUDDY:
					handed_to = 0
					remote_input = {}
				note.emit("Buddy got out.")
		"board_own":
			b["foot"] = true
			b["ride"] = 0
			goal = (b["pxf"] as Transform3D) * BUDDY_DOOR
			run = true
			if Vector2(goal.x - b["pos"].x, goal.z - b["pos"].z).length() < 0.6:
				b["mode"] = "takeoff"
				b["fly_t"] = 0.0
				note.emit("Buddy is starting up.")
		"takeoff", "orbit", "land", "parked":
			b["foot"] = false
			b["ride"] = 0
			_buddy_fly(delta, mode)
		"stay":
			b["foot"] = true
		"fight":
			b["foot"] = true
			b["ride"] = 0
			if not me_foot or main._foot_down:
				b["mode"] = "follow"
				b["hand"] = ""
			else:
				var to_me2: Vector3 = me - (b["pos"] as Vector3)
				to_me2.y = 0.0
				if to_me2.length() > 1.5:
					goal = me - to_me2.normalized() * 1.2
					run = to_me2.length() > 4.0
				b["swing_t"] = float(b["swing_t"]) - delta
				if to_me2.length() < 2.0 and float(b["swing_t"]) <= 0.0:
					b["swing_t"] = 1.6
					b["yaw"] = atan2(-to_me2.x, -to_me2.z)
					b["sw"] = int(b["sw"]) + 1
					main.take_hit(0.18, "miner's pick", b["pos"], "Buddy", "limb" if randf() < 0.12 else "")
		"dead":
			b["foot"] = true
			b["dead_t"] = float(b["dead_t"]) + delta
			if float(b["dead_t"]) > 10.0:
				# Back on his feet at his plane.
				b["pos"] = (b["pxf"] as Transform3D) * BUDDY_DOOR
				b["hp"] = 1.0
				b["dead"] = false
				b["hand"] = ""
				b["lost"] = []
				b["mode"] = "follow"
				note.emit("Buddy is back, and he's forgiven you. Mostly.")
	# Walking.
	if goal != Vector3.INF:
		var p: Vector3 = b["pos"]
		var to := goal - p
		to.y = 0.0
		var sp := 4.6 if run else 1.5
		var step := minf(sp * delta, to.length())
		if to.length() > 0.05:
			p += to.normalized() * step
			b["yaw"] = atan2(-to.x, -to.z)
		p.y = float(t.ground_level_at(p.x, p.z))
		b["pos"] = p
		b["speed"] = step / maxf(delta, 0.001)
	else:
		b["speed"] = 0.0
		if bool(b["foot"]) and not bool(b["dead"]):
			var face: Vector3 = me - (b["pos"] as Vector3)
			if face.length() > 0.5:
				b["yaw"] = lerp_angle(float(b["yaw"]), atan2(-face.x, -face.z), minf(1.0, 3.0 * delta))
	# When they ride with you and hold the controls: gentle straight and level.
	if handed_to == BUDDY:
		var bank: float = pxf.basis.x.y
		remote_input = {"roll": clampf(bank * 3.0, -0.6, 0.6), "pitch": clampf(-pl.vel.y * 0.06, -0.4, 0.4),
			"yaw": 0.0, "thr": 0.0, "brake": 0.0, "lever": pl.throttle}
	# You flying their plane (riding with them, holding the controls).
	if riding == BUDDY and have_control and b["mode"] in ["takeoff", "orbit", "land"]:
		b["mode"] = "yours"
	if b["mode"] == "yours":
		if riding != BUDDY or not have_control:
			b["mode"] = "orbit"
			b["ang"] = _orbit_angle()
		else:
			_buddy_you_fly(delta)
	_buddy_snap()


## Where on the circle round you the plane is now.
func _orbit_angle() -> float:
	var c: Vector3 = (buddy["park"] as Transform3D).origin
	var o: Vector3 = (buddy["pxf"] as Transform3D).origin
	return atan2(o.z - c.z, o.x - c.x)


## Their own plane: a scripted circuit. Take off along their heading, circle
## round where they parked (500 m out, 250 m up), and come back in to land.
func _buddy_fly(delta: float, mode: String) -> void:
	var b := buddy
	var t = main.world.terrain
	var park: Transform3D = b["park"]
	var xf: Transform3D = b["pxf"]
	b["fly_t"] = float(b["fly_t"]) + delta
	var ft: float = b["fly_t"]
	# You climbing into their plane: they wait on the ground for you to get in.
	if riding == BUDDY and mode == "parked" and b.has("go"):
		b["rpm"] = 900.0
		b["v"] = Vector3.ZERO
		if ft > 3.0:
			b.erase("go")
			b["mode"] = "takeoff"
			b["fly_t"] = 0.0
			note.emit("Buddy: \"Hang on.\"")
		return
	match mode:
		"parked":
			b["rpm"] = move_toward(float(b["rpm"]), 0.0, 400.0 * delta)
			b["v"] = Vector3.ZERO
			if riding == 0 and ft > 4.0:
				# Parked and you're not aboard: out they get, and over to you.
				b["pos"] = (b["pxf"] as Transform3D) * BUDDY_DOOR
				b["mode"] = "follow"
			return
		"takeoff":
			b["rpm"] = 2500.0
			var fwd: Vector3 = -park.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var spd := minf(5.0 + ft * 4.0, 50.0)
			var o: Vector3 = xf.origin + fwd * spd * delta
			var gy := float(t.ground_level_at(o.x, o.z)) + float(b["park_h"])
			var climb := maxf(0.0, ft - 9.0) * 1.2
			o.y = maxf(gy, o.y + climb * delta) if ft > 9.0 else gy
			var pitch := clampf(climb * 0.012, 0.0, 0.18)
			var yb := Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)) * Basis(Vector3.RIGHT, pitch)
			b["v"] = fwd * spd + Vector3.UP * (climb if ft > 9.0 else 0.0)
			b["pxf"] = Transform3D(yb, o)
			if o.y - gy > 120.0:
				b["mode"] = "orbit"
				b["ang"] = _orbit_angle()
		"orbit", "land":
			b["rpm"] = 2350.0 if mode == "orbit" else 1700.0
			var c: Vector3 = park.origin
			var r := 500.0
			var ang: float = float(b["ang"]) + 50.0 / r * delta
			b["ang"] = ang
			var want := Vector3(c.x + cos(ang) * r, 0, c.z + sin(ang) * r)
			var gy2 := float(t.ground_level_at(want.x, want.z))
			var alt_goal := maxf(c.y + 250.0, gy2 + 150.0)
			var o2: Vector3 = xf.origin
			if mode == "land":
				# Down to circuit height, then straight in to where they parked.
				var to_park := c - o2
				to_park.y = 0.0
				if float(b.get("final", 0.0)) > 0.0:
					var d := to_park.length()
					var dir := to_park.normalized() if d > 0.1 else -park.basis.z
					var spd2 := clampf(d * 0.25, 0.0, 38.0)
					o2 += dir * spd2 * delta
					var gy3 := float(t.ground_level_at(o2.x, o2.z)) + float(b["park_h"])
					o2.y = move_toward(o2.y, maxf(gy3, c.y + d * 0.08), 6.0 * delta)
					o2.y = maxf(o2.y, gy3)
					b["pxf"] = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), o2)
					b["v"] = dir * spd2
					if d < 3.0:
						b["pxf"] = Transform3D(park.basis, Vector3(c.x, gy3, c.z))
						b["mode"] = "parked"
						b["fly_t"] = 0.0
						b["final"] = 0.0
						b["v"] = Vector3.ZERO
						note.emit("Buddy is down.")
					return
				alt_goal = c.y + 120.0
				# Line up: when the circle points them home, turn in.
				var tang := Vector3(-sin(ang), 0, cos(ang))
				var home := c - o2
				home.y = 0.0
				if absf(o2.y - alt_goal) < 30.0 and tang.dot(home.normalized()) > 0.9:
					b["final"] = 1.0
			var to2 := want - o2
			to2.y = 0.0
			var dir2 := to2.normalized() if to2.length() > 0.1 else -xf.basis.z
			var o3 := o2 + dir2 * minf(55.0 * delta, to2.length() + 50.0 * delta)
			o3.y = move_toward(o2.y, alt_goal, 8.0 * delta)
			var yaw := atan2(-dir2.x, -dir2.z)
			b["pxf"] = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, -0.35), o3)
			b["v"] = (o3 - o2) / maxf(delta, 0.001)


## You at the controls of their plane: a simple handling model on your stick.
func _buddy_you_fly(delta: float) -> void:
	var b := buddy
	var xf: Transform3D = b["pxf"]
	var i := _my_input()
	var yaw := atan2(-xf.basis.z.x, -xf.basis.z.z)
	var bank: float = b.get("bank", 0.0)
	var pit: float = b.get("pit", 0.0)
	bank = move_toward(bank, -i["roll"] * 0.7, 1.2 * delta)
	pit = move_toward(pit, i["pitch"] * 0.25, 0.6 * delta)
	yaw += bank * 0.6 * delta
	b["bank"] = bank
	b["pit"] = pit
	var spd := 50.0
	var o: Vector3 = xf.origin
	var gy := float(main.world.terrain.ground_level_at(o.x, o.z)) + 30.0
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	o += fwd * spd * delta + Vector3.UP * pit * spd * delta
	o.y = maxf(o.y, gy)
	b["pxf"] = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pit) * Basis(Vector3.FORWARD, bank), o)
	b["v"] = fwd * spd
	b["rpm"] = 2300.0


## What the network would carry from them, every frame.
func _buddy_snap() -> void:
	var b := buddy
	var r: Dictionary = remotes.get(BUDDY, {})
	if r.is_empty():
		return
	var xf: Transform3D = b["pxf"]
	var p: Node3D = main.plane
	var s := {
		"name": "Buddy", "reg": "C-FBDY", "t": _clock,
		"o": xf.origin, "q": Quaternion(xf.basis.orthonormalized()), "v": b["v"],
		"ail": 0.0, "ele": 0.0, "rud": 0.0, "flap": 0.0, "rpm": b["rpm"],
		"gear": 1.0, "leg": p.leg_kind, "tyre": p.tyre_kind, "trim": 0.0,
		"comp": [0.3, 0.3, 0.3], "crashed": false, "doors": {},
		"foot": b["foot"], "wo": b["pos"], "wy": b["yaw"], "wv": b["speed"], "wg": true,
		"ride": b["ride"], "seat": b["seat"], "ctl": 0,
		"hand": b["hand"], "sw": b["sw"], "dead": b["dead"], "lost": b.get("lost", []), "hr": b.get("hr", 0),
	}
	var snaps: Array = r["snaps"]
	snaps.append([_clock, s])
	while snaps.size() > 4:
		snaps.pop_front()
	r["last"] = s
