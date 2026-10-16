extends CanvasLayer
## THE FIRE - the story opening as a ~15 minute mission (DESIGN_NOTES 237).
##  1 You step out of the cabin door: lightning strikes a tree across the
##    runway - the flash, you stagger, the screen shakes, the thunder.
##  2 The wind gets up, the fire runs; embers carry it across the runway at
##    the hangar and the houses.
##  3 Get to the plane by the hangar and go. The avgas tanks blow as you roll.
##  4 Out of the smoke for Pine Ridge - the engine quits short of it (fuel):
##    glide it in.
##  5 "Two days later": drive home through the burnt forest. Gone - all but
##    the old shed, and the wreck of the Cub you'd been restoring.
##  6 Starting over: a delivery to Pine Ridge in the truck. "Weeks later..."
##  7 The Cub restored, Eagle Rock at sunset: off the edge, the drop, the
##    pull-out - she climbs into the sunset. BUSH PILOT.
## It plays on a copy of the save: every save file is put aside at the start
## and put back at the end (or at the next start if the game was quit).

const BACKUP := "user://story_backup/"
const Fx = preload("res://scripts/fx.gd")
const RATE := 22050

var main: Node
var step := -1
var _t := 0.0                   # seconds in this step
var _total := 0.0
var _hud: Control
var _overlay: ColorRect
var _title: Label
var _sub: Label
var _boom: AudioStreamPlayer
var _shake := 0.0
var _tree := Vector3.INF
var _home := 0
var _pine := -1
var _eagle := -1
var _tank := Vector3.INF
var _tank_blown := false
var _fueled := false
var _truck_blown := false
var _hangar_down := false
var _fuel_cut := false
var _shed := Vector3.INF
var _wreck: Node3D
var _cine: Camera3D
var _saved_weather_changes := true
var _fade_to := 0.0
var _fade := 0.0
var _done_cb: Callable


# ------------------------------------------------------------------------------
#  Save copy: put aside, put back
# ------------------------------------------------------------------------------
static func _save_files() -> Array:
	var out: Array = []
	var d := DirAccess.open("user://")
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".cfg") or f.ends_with(".save") or f.ends_with(".json") or f.ends_with(".res"):
			out.append(f)
	return out


static func _backup() -> void:
	if FileAccess.file_exists(BACKUP + "ACTIVE"):
		return                  # already put aside (a retry): keep the player's own copy
	DirAccess.make_dir_recursive_absolute(BACKUP)
	for f in _save_files():
		DirAccess.copy_absolute("user://" + f, BACKUP + f)
	var mk := FileAccess.open(BACKUP + "ACTIVE", FileAccess.WRITE)
	mk.store_string("story mission running")
	mk.close()


## Put the player's own game back (called at the end, and on every start in
## case the game was quit in the middle of the mission). True if it did.
static func restore_if_needed() -> bool:
	if not FileAccess.file_exists(BACKUP + "ACTIVE"):
		return false
	var d := DirAccess.open(BACKUP)
	if d == null:
		return false
	# files the mission made that the player's game didn't have go
	var had := {}
	for f in d.get_files():
		had[f] = true
	for f in _save_files():
		if not had.has(f):
			DirAccess.remove_absolute("user://" + f)
	for f in d.get_files():
		if f == "ACTIVE":
			continue
		DirAccess.copy_absolute(BACKUP + f, "user://" + f)
	DirAccess.remove_absolute(BACKUP + "ACTIVE")
	print("story: your own game put back")
	return true


# ------------------------------------------------------------------------------
#  Start
# ------------------------------------------------------------------------------
func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_title = Label.new()
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.position = Vector2(-500, -60)
	_title.size = Vector2(1000, 80)
	_title.add_theme_font_size_override("font_size", 54)
	_title.add_theme_color_override("font_color", Color(0.94, 0.52, 0.16))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("shadow_offset_y", 3)
	_title.modulate.a = 0.0
	add_child(_title)
	_sub = Label.new()
	_sub.set_anchors_preset(Control.PRESET_CENTER)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.position = Vector2(-500, 20)
	_sub.size = Vector2(1000, 40)
	_sub.add_theme_font_size_override("font_size", 24)
	_sub.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	_sub.modulate.a = 0.0
	add_child(_sub)
	_boom = AudioStreamPlayer.new()
	_boom.stream = _boom_shot()
	_boom.volume_db = 2.0
	add_child(_boom)


func start() -> void:
	_backup()
	_hud = main.hud
	var terr = main.world.terrain
	for k in range(terr.strips.size()):
		match String(terr.strips[k]["name"]):
			"Proving Ground":
				_home = k
			"Pine Ridge":
				_pine = k
			"Eagle Rock":
				_eagle = k
	if main.menu.is_open:
		main.menu.close()
	# a hot, dry summer afternoon; a storm building, the wind from across the
	# runway toward the hangar and the houses
	_saved_weather_changes = Game.weather_changes
	Game.weather_changes = false
	Game.season = Game.SUMMER
	Game.time_of_day = 16.0
	Game.weather = 1
	Game.wind_level = 1
	var hangar: Vector3 = (main.world._strip_xf(_home, -62.0, 45.0) as Transform3D).origin
	_tank = (main.world._strip_xf(_home, 34.0, 49.0) as Transform3D).origin
	_tree = _find_tree(terr, hangar)
	var from := _tree - hangar
	Game.wind_dir_deg = fposmod(rad_to_deg(atan2(from.x, -from.z)), 360.0)    # it blows FROM the tree's side
	Game.notify_changed()
	if main.world.wind != null:
		main.world.wind.configure()
	# your plane by the hangar door, nose to the runway, low on fuel
	var p: Node3D = main.plane
	if main.driving != null:
		main._get_off_forklift()
	var at: Vector3 = (main.world._strip_xf(_home, -62.0, 24.0) as Transform3D).origin
	at.y = terr.height_at(at.x, at.z)
	var to_rwy: Vector3 = (main.world._strip_xf(_home, -62.0, 0.0) as Transform3D).origin - at
	var yaw := atan2(-to_rwy.x, -to_rwy.z)
	# the new plane, the Cub - and her tanks are dry
	if p.plane_type != "supercub":
		p.apply_type("supercub")
		main._apply_plane_type()
	p.repair_all()
	p.place_parked(at + Vector3(0, _gear_lift(p), 0), Quaternion(Vector3.UP, yaw))
	p.repair_all()
	p.fuel = 0.0
	_fueled = false
	# the fuel truck across the apron, avgas aboard
	var ft: Node3D = main.fuel_truck
	if ft != null:
		var fx: Vector3 = (main.world._strip_xf(_home, -20.0, 30.0) as Transform3D).origin
		ft.park(Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(fx.x, terr.height_at(fx.x, fx.z), fx.z)))
		ft.avgas_gal = maxf(float(ft.avgas_gal), 120.0)
		ft.engine_on = false
	main.fire.spread_mult = 3.0
	# you: in the office, the stove going
	Game.last_strip = _home
	if not main.on_foot:
		p.is_crashed = false
	main._start_indoors()
	_hud.target_strip = -1
	_go(0)
	print("story: started; tree %s, tank %s, wind from %d" % [str(_tree.round()), str(_tank.round()), int(Game.wind_dir_deg)])


## How high the plane's frame sits over the ground standing on its wheels.
func _gear_lift(p: Node3D) -> float:
	var hub: Vector3 = p.hub_rest[0] if p.get("hub_rest") != null else Vector3(0, -1.2, 0)
	var r := 0.4
	if p.has_method("tyre_spec"):
		r = float(p.tyre_spec().get("radius", 0.4))
	return -hub.y + r + 0.03


## A tree across the runway from the hangar, the tallest near the middle.
func _find_tree(terr, hangar: Vector3) -> Vector3:
	var s: Dictionary = terr.strips[_home]
	var pos: Vector3 = s["pos"]
	var away := pos - hangar
	away.y = 0.0
	away = away.normalized()
	var best := Vector3.INF
	var best_h := 0.0
	for i in range(-6, 7):
		for j in range(1, 8):
			var q: Vector3 = pos + away * (25.0 + float(j) * 9.0) + Vector3(away.z, 0, -away.x) * float(i) * 12.0
			var t: Dictionary = terr.tree_near(q) if terr.has_method("tree_near") else {}
			if not t.is_empty() and float(t["height"]) > best_h:
				best_h = float(t["height"])
				var b: Vector3 = t["base"]
				best = Vector3(b.x, terr.height_at(b.x, b.z), b.z)
	if best == Vector3.INF:
		best = pos + away * 55.0
		best.y = terr.height_at(best.x, best.z)
	return best


# ------------------------------------------------------------------------------
#  The steps
# ------------------------------------------------------------------------------
func _go(n: int) -> void:
	step = n
	_t = 0.0
	match n:
		0:
			_say("Another hot one. Step outside and have a look at the sky.")
		1:
			_say("THE FIRE'S RUNNING WITH THE WIND - and the Cub's tanks are dry. Get the fuel truck over to her, pull the hose off the reel, nozzle in the wing-root filler, and fill her up!")
		2:
			_say("Climb out of the smoke and head for Pine Ridge (the marker). Don't hang about over the fire.")
			_hud.target_strip = _pine
		3:
			_say("The engine's out - no fuel. Glide it in: best glide speed, pick your field, flaps late.")
		4:
			_say("")
		5:
			_say("Drive home and see what's left. Follow the valley east (the marker).")
			_hud.target_strip = _home
		6:
			_say("Check the old shed.")
		7:
			_say("You've a truck and a shed. Earn the money for the Cub's parts: run the store's supplies to Pine Ridge.")
			_hud.target_strip = _pine
		8:
			_say("")
		9:
			_say("She's ready. Eagle Rock, sunset. Full power, keep her straight - and whatever happens at the edge, don't stop flying.")
		10:
			_say("")


func _say(t: String) -> void:
	_hud.tutorial_text = t


func _process(dt: float) -> void:
	if step < 0 or main == null:
		return
	_t += dt
	_total += dt
	_do_shake(dt)
	_fade = move_toward(_fade, _fade_to, dt * 1.2)
	_overlay.color.a = _fade
	var p: Node3D = main.plane
	var terr = main.world.terrain
	match step:
		0:
			# out of the door: the strike
			var w: Vector3 = main.walker.global_position
			if main.on_foot and terr.hollow_at(w.x, w.z).is_empty() and _t > 1.0:
				_strike()
				_go(1)
		1:
			# the fire runs at the airport; the deadline is the tanks
			if _t > 6.0 and Game.wind_level < 3:
				Game.wind_level = 3
				Game.notify_changed()
				main.world.wind.configure()
			if _t > 55.0 and fmod(_t, 9.0) < dt:
				# the embers are falling round the hangar now
				main.fire.ignite(_tank + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30)), 4.0)
			if not _tank_blown and (_t > 170.0 or main.fire.burning_at(_tank) or (not main.on_foot and p.ground_speed > 12.0 and _t > 20.0)):
				_blow_tanks()
			if not _fueled and float(p.fuel) >= 20.0:
				_fueled = true
				_say("That'll do! Reel the hose in, get in the Cub ({get_in}) and GO - before the fire gets to the hangar.".replace("{get_in}", Game.hint("get_out")))
				_hud.push_message("That'll get you out of here.", 3.0)
			# the fire closes in: once you're rolling (or when it reaches them) the
			# hangar goes up and the fuel truck blows
			var rolling: bool = not main.on_foot and float(p.ground_speed) > 8.0
			if _fueled and not _truck_blown and (rolling or _t > 200.0 or main.fire.burning_at(main.fuel_truck.global_position)):
				_blow_truck()
			if _truck_blown and not _hangar_down and (_t > 0.0):
				_hangar_down = true
				_burn_hangar()
			if bool(p.airborne) and float(p.agl) > 25.0:
				_go(2)
			if bool(p.is_crashed):
				_retry("The fire got you. Try again: get to the plane faster.")
		2:
			if not _tank_blown and _t > 3.0:
				_blow_tanks()
			# out of fuel short of Pine Ridge: enough height to glide it in
			var pr: Vector3 = terr.strips[_pine]["pos"]
			var d := Vector2(p.global_position.x - pr.x, p.global_position.z - pr.z).length()
			if not _fuel_cut and _t > 35.0 and d < 1600.0 and float(p.agl) > 110.0:
				_fuel_cut = true
				p.fuel = 0.0
				_hud.push_message("The engine coughs... and quits. Out of fuel!", 5.0)
				_go(3)
			_check_landed_pine(p, terr)
		3:
			_check_landed_pine(p, terr)
		4:
			# fade, two days later
			if _t < 0.1:
				_fade_to = 1.0
			if _t > 1.6 and _t < 1.7:
				_card("TWO DAYS LATER", "The fire's out. The smoke's still hanging in the valley.")
				_aftermath()
			if _t > 6.0:
				_card("", "")
				_fade_to = 0.0
				_go(5)
		5:
			if Vector2(main.pickup.global_position.x - _shed.x, main.pickup.global_position.z - _shed.z).length() < 90.0:
				_hud.push_message("The office. The bunkhouse. The house. All of it.", 6.0)
				_go(6)
		6:
			var w2: Vector3 = main.walker.global_position
			if main.on_foot and Vector2(w2.x - _shed.x, w2.z - _shed.z).length() < 9.0:
				_hud.push_message("The old shed made it. And the Cub you've been putting back together. A cot, the stove... it's a start.", 9.0)
				main.jobs.money = maxi(int(main.jobs.money), 0)
				_go(7)
		7:
			var pr2: Vector3 = terr.strips[_pine]["pos"]
			if main.driving == main.pickup and Vector2(main.pickup.global_position.x - pr2.x, main.pickup.global_position.z - pr2.z).length() < 120.0:
				main.jobs.money += 450
				main.jobs.save_career()
				_hud.push_message("Delivered. $450 - a start on the parts.", 5.0)
				_go(8)
		8:
			if _t < 0.1:
				_fade_to = 1.0
			if _t > 1.6 and _t < 1.7:
				_card("WEEKS LATER", "Every run, every dollar, into the Cub.")
				_finale_setup()
			if _t > 6.5:
				_card("", "")
				_fade_to = 0.0
				_go(9)
		9:
			_finale_watch(p, terr)
		10:
			_finale_cine(dt, p)


func _check_landed_pine(p: Node3D, terr) -> void:
	if bool(p.is_crashed):
		_retry("She's down hard. Try the glide again.", true)
		return
	if bool(p.on_ground) and float(p.ground_speed) < 2.0 and _t > 3.0:
		if terr.strip_index_at(p.global_position.x, p.global_position.z, 40.0) == _pine or step == 3:
			_hud.push_message("Down. Charred, out of gas - but down, and alive.", 6.0)
			_go(4)


## Something went wrong: back to where it went wrong.
func _retry(msg: String, glide: bool = false) -> void:
	_hud.push_message(msg, 6.0)
	var p: Node3D = main.plane
	p.repair_all()
	if glide:
		p.place_on_approach(_pine, 1500.0, 130.0)
		p.fuel = 0.0
		_fuel_cut = true
		_go(3)
	else:
		main.fire.burn_out(0.0)
		start()


# ------------------------------------------------------------------------------
#  The strike, the tanks
# ------------------------------------------------------------------------------
func _strike() -> void:
	var storm = main.world.get("storm")
	var top := _tree + Vector3(0, 14.0, 0)
	if storm != null:
		storm.force_near = true
		storm.call("strike_at", top)
	main.fire.ignite(_tree, 6.0)
	_flash(1.0)
	_shake = 1.0
	main.jolt(1.0)
	_boom.pitch_scale = 0.8
	_boom.play()
	# you stagger back from it, an arm up against the light
	var w: Node3D = main.walker
	var away := w.global_position - _tree
	away.y = 0.0
	away = away.normalized()
	w.place(w.global_position + away * 0.9, w.yaw)
	if w.get("model") != null and w.model.has_method("one_shot"):
		w.model.one_shot("hit_react", 1.2)
	_hud.push_message("LIGHTNING - across the runway! The tree's going up!", 5.0)


func _blow_tanks() -> void:
	_tank_blown = true
	var ex: Node3D = Fx.make_explosion(3.0)
	main.world.add_child(ex)
	ex.global_position = _tank + Vector3(0, 2.0, 0)
	var ex2: Node3D = Fx.make_explosion(2.2)
	main.world.add_child(ex2)
	ex2.global_position = _tank + Vector3(6.0, 1.5, 3.0)
	main.fire.ignite(_tank, 14.0)
	var sts = main.world.get("structures")
	if sts != null:
		sts.ignite_near(_tank, 30.0)
	var d: float = main.cam.global_position.distance_to(_tank) if main.cam != null else 50.0
	var k := clampf(1.2 - d / 250.0, 0.3, 1.0)
	_shake = maxf(_shake, k)
	main.jolt(k)
	_flash(0.6 * k)
	_boom.pitch_scale = 0.65
	_boom.volume_db = 4.0
	_boom.play()
	# the blast rocks the plane if it's close
	var p: Node3D = main.plane
	var dp := p.global_position.distance_to(_tank)
	if dp < 120.0 and "omega" in p:
		p.omega += Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3), randf_range(-0.9, 0.9)) * (1.0 - dp / 120.0)
	_hud.push_message("THE AVGAS TANKS!", 3.0)


## The fuel truck: the fire under it, then the avgas compartment goes.
func _blow_truck() -> void:
	_truck_blown = true
	var ft: Node3D = main.fuel_truck
	if ft == null:
		return
	if ft.hose_out:
		ft.delivering = {}
		ft.reel_in()
	var at := ft.global_position + Vector3(0, 1.8, 0)
	var ex: Node3D = Fx.make_explosion(3.4)
	main.world.add_child(ex)
	ex.global_position = at
	main.fire.ignite(ft.global_position, 16.0)
	if main.vdamage != null and main.vdamage.has_method("set_on_fire"):
		main.vdamage.set_on_fire("fuel_truck", "fuel truck", 1.0)
	var d: float = main.cam.global_position.distance_to(at) if main.cam != null else 60.0
	var k := clampf(1.3 - d / 220.0, 0.35, 1.0)
	_shake = maxf(_shake, k)
	main.jolt(k)
	_flash(0.7 * k)
	_boom.pitch_scale = 0.6
	_boom.volume_db = 6.0
	_boom.play()
	var p: Node3D = main.plane
	var dp := p.global_position.distance_to(at)
	if dp < 140.0 and "omega" in p:
		p.omega += Vector3(randf_range(-0.7, 0.7), randf_range(-0.3, 0.3), randf_range(-1.0, 1.0)) * (1.0 - dp / 140.0)
	_hud.push_message("THE FUEL TRUCK - IT'S GONE UP! KEEP GOING!", 3.0)


## The hangar's engulfed: fire through it, the roof falls in (the shell goes,
## smoke and flame where it stood).
func _burn_hangar() -> void:
	var hg := main.world.get_node_or_null("BushHangar") as Node3D
	var hp: Vector3 = (main.world._strip_xf(_home, -62.0, 45.0) as Transform3D).origin
	main.fire.ignite(hp, 22.0)
	var sts = main.world.get("structures")
	if sts != null:
		sts.ignite_near(hp, 40.0)
	var tw := create_tween()
	tw.tween_interval(6.0)
	tw.tween_callback(func() -> void:
		if hg != null and is_instance_valid(hg):
			var ex: Node3D = Fx.make_explosion(1.8)
			main.world.add_child(ex)
			ex.global_position = hp + Vector3(0, 4.0, 0)
			hg.visible = false
			_boom.pitch_scale = 0.9
			_boom.volume_db = -2.0
			_boom.play()
			_hud.push_message("The hangar's roof falls in.", 3.0))


func _flash(a: float) -> void:
	_overlay.color = Color(1, 0.97, 0.9, a)
	_fade = a
	_fade_to = 0.0


func _do_shake(dt: float) -> void:
	var c := get_viewport().get_camera_3d()
	if c == null:
		return
	if _shake > 0.001:
		_shake = move_toward(_shake, 0.0, dt * 0.7)
		var amp := _shake * _shake * 0.06
		c.h_offset = randf_range(-amp, amp)
		c.v_offset = randf_range(-amp, amp)
	elif c.h_offset != 0.0 or c.v_offset != 0.0:
		c.h_offset = 0.0
		c.v_offset = 0.0


## A boom with real weight: a sub-bass drop (about 30-60 Hz) under a crack and
## a long rumble - big low end for the strike and the tanks.
func _boom_shot() -> AudioStreamWAV:
	var n := RATE * 5
	var data := PackedByteArray()
	data.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var lp := 0.0
	var ph := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var f := lerpf(62.0, 26.0, clampf(t / 1.6, 0.0, 1.0))
		ph += TAU * f / RATE
		var sub := sin(ph) * exp(-t * 0.9)
		var w := r.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.04
		var crack := w * exp(-t * 18.0) * 0.7
		var rumble := lp * 4.0 * exp(-t * 0.7) * (0.7 + 0.3 * sin(t * 5.0))
		var v := clampf(sub * 0.95 + crack + rumble, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.data = data
	return st


func _card(title: String, sub: String) -> void:
	_title.text = title
	_sub.text = sub
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 1.0 if title != "" else 0.0, 0.8)
	tw.parallel().tween_property(_sub, "modulate:a", 1.0 if sub != "" else 0.0, 0.8)


# ------------------------------------------------------------------------------
#  After the fire
# ------------------------------------------------------------------------------
func _aftermath() -> void:
	var terr = main.world.terrain
	# the shed that made it: out past the apron's far corner
	var sx: Transform3D = main.world._strip_xf(_home, 70.0, 62.0, PI * 0.5)
	_shed = sx.origin
	_shed.y = terr.height_at(_shed.x, _shed.z)
	main.fire.burn_out(0.9, [[_shed, 26.0]])
	var sts = main.world.get("structures")
	if sts != null:
		for id in (sts.items as Dictionary).keys():
			var it: Dictionary = sts.items[id]
			if not bool(it["burnt"]):
				sts._collapse(id, it, false)
	Game.time_of_day = 10.0
	Game.weather = 0
	Game.wind_level = 1
	Game.notify_changed()
	main.world.wind.configure()
	# the old shed, the cot, the stove, and the Cub's wreck inside
	var AL = load("res://scripts/assets/asset_lib.gd")
	var shed: Node3D = AL.get_asset("pole_barn")
	shed.transform = Transform3D(Basis(Vector3.UP, sx.basis.get_euler().y), _shed)
	main.world.add_child(shed)
	terr.add_hollow(Transform3D(shed.transform.basis, _shed + Vector3(0, 2.0, 0)), Vector3(9.0, 4.0, 12.0), 3.0)
	_wreck = load("res://scripts/plane_body.gd").new()
	_wreck.name = "CubWreck"
	main.world.add_child(_wreck)
	_wreck.build()
	_wreck.global_transform = Transform3D(Basis(Vector3.UP, sx.basis.get_euler().y + PI * 0.5) * Basis(Vector3.RIGHT, 0.0), _shed + Vector3(0, 0.0, 0))
	for nm in ["WingR", "Prop", "PropHub", "Cowl", "AileronR", "FlapR", "WheelL"]:
		var part := _wreck.find_child(nm, true, false) as Node3D
		if part != null:
			part.visible = false
	var kit = load("res://scripts/meshkit.gd").new()
	kit.box(Transform3D(shed.transform.basis, _shed + shed.transform.basis * Vector3(-3.4, 0.35, 3.8)), Vector3(0.8, 0.12, 2.0), Color(0.30, 0.34, 0.24))
	kit.cylinder(Transform3D(shed.transform.basis, _shed + shed.transform.basis * Vector3(3.3, 0.45, 4.6)), 0.3, 0.3, 0.9, 10, Color(0.12, 0.12, 0.12), true)
	main.world.add_child(kit.instance("ShedCampsite"))
	# you're at Pine Ridge with the pickup; the plane stays there, scorched
	var p: Node3D = main.plane
	for part2 in ["fuselage", "wing_l", "wing_r", "elevator", "rudder"]:
		p.hurt(part2, 0.3)
	if not main.on_foot:
		main._get_out()
	var pr: Vector3 = terr.strips[_pine]["pos"]
	var pk: Node3D = main.pickup
	var px: Vector3 = (main.world._strip_xf(_pine, 0.0, 30.0) as Transform3D).origin
	var dir := Vector3(-1, 0, 0) if pr.x > 0.0 else Vector3(1, 0, 0)
	pk.park(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), Vector3(px.x, terr.height_at(px.x, px.z), px.z)))
	main._get_on_forklift(pk)


# ------------------------------------------------------------------------------
#  The finale
# ------------------------------------------------------------------------------
func _finale_setup() -> void:
	if main.driving != null:
		main._get_off_forklift()
	Game.time_of_day = 21.85             # the sun just over the ridges
	Game.weather = 0
	Game.wind_level = 0
	Game.notify_changed()
	main.world.wind.configure()
	var p: Node3D = main.plane
	p.apply_type("supercub")
	main._apply_plane_type()
	p.repair_all()
	var terr = main.world.terrain
	var s: Dictionary = terr.strips[_eagle]
	var a: Vector3 = terr.strip_point(_eagle, -float(s["length"]) * 0.5 + 12.0, 0.0)
	a.y = terr.height_at(a.x, a.z)
	var d: Vector2 = s["dir"]
	var yaw := atan2(-d.x, -d.y)
	p.place_parked(a + Vector3(0, _gear_lift(p), 0), Quaternion(Vector3.UP, yaw))
	p.repair_all()
	p.fuel = 60.0
	if main.on_foot:
		main._get_in(true)
	for e in p.engines():
		e.set_running(p.oat_c)
		e.rpm = 900.0


func _finale_watch(p: Node3D, terr) -> void:
	var s: Dictionary = terr.strips[_eagle]
	var pos: Vector3 = s["pos"]
	var d: Vector2 = s["dir"]
	var along := Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).dot(d)
	if along > float(s["length"]) * 0.5 + 5.0:
		# off the edge: the camera out past the cliff, low, looking back up at it
		var edge: Vector3 = terr.strip_point(_eagle, float(s["length"]) * 0.5, 0.0)
		edge.y = terr.height_at(edge.x, edge.z)
		var dir := Vector3(d.x, 0, d.y)
		_cine = Camera3D.new()
		_cine.fov = 50.0
		_cine.far = 40000.0
		main.world.add_child(_cine)
		_cine.global_position = edge + dir * 170.0 + Vector3(dir.z, 0, -dir.x) * 70.0 + Vector3(0, -55.0, 0)
		_cine.look_at(p.global_position, Vector3.UP)
		_cine.make_current()
		_go(10)
	elif bool(p.is_crashed):
		_retry("She didn't make it off. Again - full power, and fly it off the edge.")
		_finale_setup()
		_go(9)


func _finale_cine(dt: float, p: Node3D) -> void:
	if _cine == null:
		return
	var tgt := p.global_position
	var cur := -_cine.global_transform.basis.z
	var want := (tgt - _cine.global_position).normalized()
	_cine.look_at(_cine.global_position + cur.lerp(want, clampf(dt * 3.0, 0.0, 1.0)), Vector3.UP)
	if _t > 4.5 and _t < 4.6:
		_card("BUSH PILOT", "North of sixty - 1988")
	if _t > 6.0:
		_cine.fov = lerpf(_cine.fov, 38.0, dt * 0.3)
	if bool(p.is_crashed):
		_retry("Not this time. Again.")
		_finale_setup()
		_go(9)
		return
	if _t > 13.0:
		_card("", "")
		_fade_to = 1.0
	if _t > 15.0:
		_finish()


func _finish() -> void:
	step = -1
	_hud.tutorial_text = ""
	Game.weather_changes = _saved_weather_changes
	if main.fire != null:
		main.fire.spread_mult = 1.0
	restore_if_needed()
	_title.text = ""
	# back to your own game, as you left it
	get_tree().paused = false
	get_tree().reload_current_scene()
