extends CanvasLayer
## Admin console: press ` (the key left of 1) or F1 to open, type a command,
## Enter to run it, ` or Esc to close. "help" lists the commands.

var main: Node
var _box: PanelContainer
var _out: Label
var _line: LineEdit
var _lines: Array[String] = []
var _history: Array[String] = []
var _hist_i := 0


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.03, 0.88)
	sb.border_color = Color(0.82, 0.36, 0.10)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	_box.add_theme_stylebox_override("panel", sb)
	_box.anchor_right = 1.0
	_box.offset_bottom = 300
	add_child(_box)
	var v := VBoxContainer.new()
	_box.add_child(v)
	_out = Label.new()
	_out.custom_minimum_size = Vector2(0, 240)
	_out.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_out.clip_text = true
	_out.add_theme_font_size_override("font_size", 15)
	_out.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	v.add_child(_out)
	_line = LineEdit.new()
	_line.placeholder_text = "Command (help for a list)"
	_line.text_submitted.connect(_run)
	v.add_child(_line)
	_box.visible = false
	_say("Admin console. Type help for the commands.")


func is_open() -> bool:
	return _box.visible


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_QUOTELEFT or k == KEY_F1:
			_toggle()
			get_viewport().set_input_as_handled()
		elif _box.visible and k == KEY_ESCAPE:
			_toggle()
			get_viewport().set_input_as_handled()
		elif _box.visible and (k == KEY_UP or k == KEY_DOWN) and not _history.is_empty():
			_hist_i = clampi(_hist_i + (-1 if k == KEY_UP else 1), 0, _history.size())
			_line.text = _history[_hist_i] if _hist_i < _history.size() else ""
			_line.caret_column = _line.text.length()
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	_box.visible = not _box.visible
	if _box.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_line.grab_focus()
		_line.clear()
		get_tree().paused = true
	else:
		_line.release_focus()
		if not main.menu.is_open:
			get_tree().paused = false


func _say(t: String) -> void:
	_lines.append(t)
	while _lines.size() > 14:
		_lines.pop_front()
	_out.text = "\n".join(_lines)


func _run(text: String) -> void:
	_line.clear()
	var t := text.strip_edges()
	if t == "":
		return
	_history.append(t)
	_hist_i = _history.size()
	_say("> " + t)
	var parts := t.split(" ", false)
	var cmd := parts[0].to_lower()
	var arg := " ".join(parts.slice(1)) if parts.size() > 1 else ""
	var plane: Node3D = main.plane
	var jobs: Node = main.jobs
	match cmd:
		"help", "?":
			_say("money N | sandbox on/off | plane dc3 / wolverine | floats on/off | skis on/off | repair | fuel [gallons] | tp <strip name or number>")
			_say("strips | time H | weather clear/overcast/rain/fog | season summer/autumn/winter/spring | wind 0-3 | logs N")
			_say("fail left/right | restart | feather | engine | free on/off (no bills) | fire (start one in front of you) | newworld [seed] (new layout) | clear (this screen) | perf (frame-time readout) | look cold/classic")
			_say("ITEMS: give <item> [n] (no item: the list; what won't fit goes at your feet) | logs N (stock) | log N (logs at your feet to carry) | rock N | gold G (grams) | part <name> (part list: part) | bring tug/trailer/pickup/water/fuel/loader | lineup (every machine in a row)")
			_say("GO: goto creek / pond / knoll / bog / pad / strip / vein / forest (on foot)")
			_say("CO-OP: buddy (a stand-in second player) | buddy fly / land / ask / come / stay / fight / peace / off")
			_say("SOUND: rec [seconds] (records the game's sound to _rec/ in the project folder)")
			_say("DAMAGE: damage [0-1] (what you're driving) | burn (set it alight) | repair (what you're in, free) | repair all")
		"clear":
			_lines.clear()
			_out.text = ""
		"perf":
			main.perf_overlay(arg != "off")
			_say("Performance readout %s." % ("off" if arg == "off" else "on (perf off hides it)"))
		"money":
			var n := int(arg) if arg.is_valid_int() else 100000
			jobs.money += n
			jobs.save_career()
			_say("Money: $%d" % jobs.money)
		"sandbox":
			Game.sandbox = arg != "off"
			Game.notify_changed()
			_say("Sandbox %s: %s" % ["ON" if Game.sandbox else "OFF", "money doesn't run out, no bills, planes sold at any strip" if Game.sandbox else "career rules"])
		"handcheck":
			# a close camera on his hands: handcheck [item|back|off]
			if arg == "aim":
				main.force_aim = not main.force_aim
				_say("Aim held: %s" % main.force_aim)
				return
			if arg == "off":
				main.handcam = 0
				main.force_aim = false
				_say("Hand camera off.")
				return
			if not main.on_foot:
				main._toggle_foot()
			main.handcam = 2 if arg == "back" else (3 if arg == "side" else 1)
			if arg == "info":
				var md: Node3D = main.walker.model
				var sk: Skeleton3D = md.get("skeleton")
				var held: Node3D = md.get("_held")
				var me: Transform3D = md.global_transform.affine_inverse()
				var rh: Vector3 = me * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig1_RightHand")).origin)
				var lh: Vector3 = me * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig1_LeftHand")).origin)
				_say("hands (his frame) R %s  L %s" % [str(rh.snapped(Vector3.ONE * 0.01)), str(lh.snapped(Vector3.ONE * 0.01))])
				if held != null:
					var hx: Transform3D = me * held.global_transform
					_say("held at %s fwd(-Z) %s up %s vis %s" % [str(hx.origin.snapped(Vector3.ONE * 0.01)), str((-hx.basis.z).normalized().snapped(Vector3.ONE * 0.01)), str(hx.basis.y.normalized().snapped(Vector3.ONE * 0.01)), held.is_visible_in_tree()])
				return
			if arg != "" and arg != "back" and arg != "side":
				if not main.inv.has(arg):
					main.inv.add(arg, 1)
				for i in range(8):
					var sl: Dictionary = main.inv.slots[i]
					if not sl.is_empty() and String(sl["id"]) == arg:
						main.inv.select(i)
			_say("Hand camera on (handcheck off). In hand: %s" % main.inv.in_hand())
		"buddy":
			# A stand-in second player for trying co-op alone: buddy [on|off|fly|land|ask|come|stay]
			_say(main.net.buddy_cmd(arg))
		"goretest":
			# A body in front of you (nobody dies): goretest [thrown|crushed|seat]
			_say(main.gore_test(arg if arg != "" else "thrown"))
		"rumble":
			# Test the controller: a second of full rumble on every pad, and what the game sees.
			var pads := Input.get_connected_joypads()
			var names: Array = []
			for d in pads:
				names.append("%d %s" % [d, Input.get_joy_name(d)])
				Input.start_joy_vibration(d, 1.0, 1.0, 1.0)
			_say("Rumble option %s, strength %.2f, engine %.2f. Pads: %s" % ["ON" if Game.rumble else "OFF", Game.rumble_strength, Game.rumble_engine, ", ".join(names) if not names.is_empty() else "none found"])
		"spill":
			# Test the fuel-on-the-ground look: a fuel pool beside you (or N kg).
			var kg := float(arg) if arg.is_valid_float() else 15.0
			var h: Node = main.hazards
			var cam3 := get_viewport().get_camera_3d()
			var at: Vector3 = cam3.global_position
			var fwd: Vector3 = -cam3.global_transform.basis.z
			fwd.y = 0.0
			var p: Vector3 = at + fwd.normalized() * 4.0
			p.y = plane.terrain.ground_level_at(p.x, p.z)
			h._new_pool(p, kg)
			_say("Spilled %d kg of fuel on the ground." % int(kg))
		"sounds", "whatsound":
			# Every sound playing right now, loudest first (for hunting a noise).
			var cam := get_viewport().get_camera_3d()
			var found: Array = []
			var stack: Array = [get_tree().root]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				for c in n.get_children():
					stack.append(c)
				if (n is AudioStreamPlayer or n is AudioStreamPlayer3D) and n.has_stream_playback() and n.volume_db > -60.0:
					var d := 0.0
					if n is AudioStreamPlayer3D and cam != null:
						d = (n as AudioStreamPlayer3D).global_position.distance_to(cam.global_position)
					var sn: String = n.stream.resource_path.get_file() if n.stream != null and n.stream.resource_path != "" else (n.stream.get_class() if n.stream != null else "-")
					found.append([n.volume_db - (20.0 * log(maxf(d, 1.0)) / log(10.0) if n is AudioStreamPlayer3D else 0.0), "%s/%s  %s  %.0f dB  %.0f m" % [n.get_parent().name, n.name, sn, n.volume_db, d]])
			found.sort_custom(func(x, y): return x[0] > y[0])
			_say("Playing now (loudest first):")
			for k in range(mini(found.size(), 12)):
				_say("  " + String(found[k][1]))
		"free":
			Game.free_repairs = arg != "off"
			Game.notify_changed()
			_say("Bills %s." % ("off" if Game.free_repairs else "on"))
		"plane":
			var tp := arg.to_lower() if arg != "" else "dc3"
			if tp.begins_with("dc"):
				tp = "dc3"
			elif tp.begins_with("wol") or tp.begins_with("ces"):
				tp = "wolverine"
			elif tp.begins_with("bi") or tp.begins_with("mea"):
				tp = "biplane"
			elif tp.begins_with("sup") or tp.begins_with("cub"):
				tp = "supercub"
			if not plane.PlaneTypes.TYPES.has(tp):
				_say("Planes: supercub, wolverine, biplane, dc3")
				return
			plane.apply_type(tp)
			main._apply_plane_type()
			main._reset_to_last_strip()
			_say("Now flying a %s." % plane.type_name)
		"floats", "skis":
			if plane.plane_type != "wolverine":
				_say("Only the Wolverine takes floats or skis.")
				return
			if cmd == "floats":
				plane.leg_kind = "amphib" if arg != "off" else "spring"
				Game.leg_kind = plane.leg_kind
			else:
				plane.tyre_kind = "wskis" if arg != "off" else "850"
				Game.tyre_kind = plane.tyre_kind
			plane.apply_gear()
			Game.save_settings()
			if plane.on_ground:
				plane.settle_here()
			_say("%s %s." % [cmd.capitalize(), "fitted" if arg != "off" else "off"])
		"repair":
			# what you're driving, or the plane; "repair all": every machine and the plane
			var vd0: Node = main.vdamage
			if vd0 != null and arg == "all":
				for e0 in main._all_vehicles():
					vd0.repair(String(e0[0]))
				plane.repair_all()
				_say("Every machine and the plane fixed.")
				return
			if vd0 != null and main.driving != null:
				var vk0: String = main._veh_key(main.driving)
				vd0.repair(vk0)
				_say("Fixed: %s." % vd0.status(vk0))
				return
			plane.repair_all()
			_say("Repaired." if not plane.is_crashed else "Repaired, but it's a wreck: tp to a strip to start again.")
		"fuel":
			var gal := float(arg) if arg.is_valid_float() else 9999.0
			plane.set_load(minf(gal * 2.72, plane.fuel_capacity), plane.cargo_front, plane.cargo_rear)
			_say("Fuel: %d gal." % int(plane.fuel / 2.72))
		"tp", "teleport", "go":
			var k := _find_strip(arg)
			if k < 0:
				_say("No strip like that. Type strips for the list.")
				return
			main._on_start_requested(k, false)
			_say("At %s." % main.world.terrain.strips[k]["name"])
		"at":
			# on foot at world x z (the square is -180..180)
			var xz := arg.split(" ", false)
			if xz.size() < 2 or not xz[0].is_valid_float() or not xz[1].is_valid_float():
				_say("at x z   e.g. at -40 -80 (the hangar)")
				return
			if not main.on_foot:
				main._toggle_foot()
			main.walker.place(Vector3(float(xz[0]), 0, float(xz[1])), main.walker.yaw)
			_say("On foot at %s %s." % [xz[0], xz[1]])
		"cam":
			# a look-around camera for checking the map: cam x y z tx ty tz | cam off
			var old_cam = main.get_node_or_null("LookCam")
			if arg == "off" or arg == "":
				if old_cam != null:
					old_cam.queue_free()
				_say("Camera back.")
				return
			var v := arg.split(" ", false)
			if v.size() < 6:
				_say("cam x y z tx ty tz   (or cam off)")
				return
			var lc: Camera3D = old_cam if old_cam != null else Camera3D.new()
			if old_cam == null:
				lc.name = "LookCam"
				lc.far = 40000.0
				lc.fov = 70.0
				main.add_child(lc)
			lc.look_at_from_position(Vector3(float(v[0]), float(v[1]), float(v[2])), Vector3(float(v[3]), float(v[4]), float(v[5])))
			lc.make_current()
			_say("Camera at %s %s %s." % [v[0], v[1], v[2]])
		"here":
			var wp: Vector3 = main.walker.global_position if main.on_foot else main.plane.global_position
			_say("x %.0f  y %.1f  z %.0f  facing %.0f" % [wp.x, wp.y, wp.z, fposmod(rad_to_deg(-main.walker.look.x), 360.0)])
		"face":
			if arg.is_valid_float():
				main.walker.look.x = -deg_to_rad(float(arg))
				main.walker.look.y = -0.15
				_say("Facing %s." % arg)
		"give":
			var gv := arg.split(" ", false)
			if gv.is_empty() or not main.inv.ITEMS.has(gv[0]):
				_say("give <%s> [n]" % "|".join(main.inv.ITEMS.keys()))
				return
			var want := int(gv[1]) if gv.size() > 1 and gv[1].is_valid_int() else 1
			var got: int = main.inv.add(gv[0], want, true)
			if got < want:
				# too heavy to carry it all: the rest goes on the ground at his feet
				var wp: Vector3 = main.walker.global_position
				main.inv.place_in_world(gv[0], want - got, wp + Vector3(0.8, 0, 0.8), 0.0)
			_say("Gave %d %s%s." % [want, gv[0], "" if got >= want else " (%d on you, %d at your feet)" % [got, want - got]])
		"strips":
			var names: Array[String] = []
			var ss: Array = main.world.terrain.strips
			for i in range(ss.size()):
				names.append("%d %s" % [i, ss[i]["name"]])
			_say(", ".join(names))
		"amb":
			# "amb wind off", "amb all on": switch background layers to find a sound
			var words := arg.to_lower().split(" ", false)
			var layers := ["wind", "water", "rain", "crickets", "birds"]
			var which: Array = layers if words.size() == 0 or words[0] == "all" else [words[0]]
			var off := words.size() < 2 or words[1] == "off"
			for l in which:
				if off:
					main.ambience.muted[l] = true
				else:
					main.ambience.muted.erase(l)
			_say("Ambience off: %s" % (", ".join(PackedStringArray(main.ambience.muted.keys())) if not main.ambience.muted.is_empty() else "none"))
		"squeal":
			if main.noises != null:
				main.noises.squeal()
				_say("Fan belt squeal (%.1f s)" % main.noises.SQUEAL_SECONDS)
		"look":
			Game.cold_look = arg.to_lower() != "classic"
			Game.notify_changed()
			_say("Look: %s" % ("Alaska cold light" if Game.cold_look else "classic (the old light)"))
		"time":
			if arg.is_valid_float():
				Game.time_of_day = clampf(float(arg), 0.0, 23.99)
				Game.notify_changed()
			_say("Time %.1f" % Game.time_of_day)
		"story":
			main.start_story()
			_toggle()
			_say("THE FIRE: started.")
		"lightning":
			var stm = main.world.get("storm")
			_say(stm.strike_now() if stm != null else "No storm here.")
		"weather":
			var w := ["clear", "overcast", "rain", "fog"].find(arg.to_lower())
			if arg.is_valid_int():
				w = clampi(int(arg), 0, 3)
			if w < 0:
				_say("weather clear / overcast / rain / fog")
				return
			Game.weather = w
			Game.notify_changed()
			_say("Weather: %s" % ["clear", "overcast", "rain or snow", "fog"][w])
		"season":
			var si := ["summer", "autumn", "winter", "spring"].find(arg.to_lower())
			if si < 0:
				si = ["summer", "fall", "winter", "spring"].find(arg.to_lower())
			if si < 0:
				_say("season summer / autumn / winter / spring")
				return
			Game.season = si
			Game.notify_changed()
			_say("Season: %s" % arg)
		"wind":
			if arg.is_valid_int():
				Game.wind_level = clampi(int(arg), 0, 3)
				Game.notify_changed()
			_say("Wind level %d" % Game.wind_level)
		"logs":
			main.builds.add_logs(int(arg) if arg.is_valid_int() else 20)
			_say("Logs in stock: %d" % main.builds.logs)
		"log", "rock":
			var n := clampi(int(arg) if arg.is_valid_int() else (4 if cmd == "log" else 3), 1, 40)
			var w0: Vector3 = main.walker.global_position
			var fwd := Basis(Vector3.UP, main.walker.yaw) * Vector3(0, 0, -1)
			var side := Vector3(-fwd.z, 0, fwd.x)
			var pts: Array = []
			for i in range(n):
				var q: Vector3 = w0 + fwd * (2.0 + float(i / 4) * 0.8) + side * (float(i % 4) - 1.5) * (0.5 if cmd == "log" else 0.7)
				q.y = main.world.terrain.ground_level_at(q.x, q.z)
				pts.append(q)
			if cmd == "log":
				main.cargo.add_own_logs(pts)
			else:
				for q2 in pts:
					main.cargo.add_rock(q2, randf_range(20.0, 70.0))
			_say("%d %s in front of you: E to pick one up." % [n, "logs" if cmd == "log" else "rocks"])
		"gold":
			main.prospect.gold_g += float(arg) if arg.is_valid_float() else 100.0
			main.prospect._dirty = true
			_say("Gold carried: %.1f g" % main.prospect.gold_g)
		"part":
			var P = load("res://scripts/parts.gd")
			var all := {}
			all.merge(P.CATALOG)
			all.merge(P.CHASSIS)
			if arg == "" or not all.has(arg):
				var ks: Array = all.keys().filter(func(k2): return arg == "" or String(k2).contains(arg))
				if ks.is_empty():
					ks = all.keys()
					_say("No part called '%s'." % arg)
				_say("part <name>: %s" % ", ".join(PackedStringArray(ks)))
				return
			var u: int = P.make(arg, 1.0)
			P.save_all()
			var gotp: int = main.inv.add(P.item_id(u), 1, true)
			if gotp <= 0:
				main.inv.place_in_world(P.item_id(u), 1, main.walker.global_position + Vector3(0.8, 0, 0.8), 0.0)
			_say("%s %s." % [String(all[arg]["name"]), "in your hands" if gotp > 0 else "at your feet (too heavy to carry: a loader's forks will lift it)"])
		"in":
			# sit straight in a machine (testing): in pickup / water / fuel / loader / tug /
			# miner / excavator / dozer (delivered in front of you if you haven't one)
			var mv: Node3D = {"tug": main.tug, "pickup": main.pickup, "water": main.water_truck,
				"fuel": main.fuel_truck, "loader": main.loader}.get(arg, null)
			if arg in ["miner", "excavator", "dozer"]:
				# a machine of that kind: the one you have, or one delivered here
				var pr: Node = main.prospect
				var lst: Array = {"miner": pr.tunnelers, "excavator": pr.excavators, "dozer": pr.dozers}[arg]
				if lst.is_empty():
					var wpm: Vector3 = main.walker.global_position
					var fwm := Basis(Vector3.UP, main.walker.yaw) * Vector3(0, 0, -7.0)
					var xfm := Transform3D(Basis(Vector3.UP, main.walker.yaw), wpm + fwm)
					match arg:
						"miner":
							pr._spawn_tunneler(xfm)
						"excavator":
							pr._spawn_excavator(xfm)
						"dozer":
							pr._spawn_dozer(xfm)
					pr._dirty = true
				mv = lst[lst.size() - 1]
			if mv == null:
				_say("in pickup / water / fuel / loader / tug / miner / excavator / dozer")
				return
			if main.driving != null:
				main._get_off_forklift()
			if not main.on_foot:
				main._toggle_foot()
			main._get_on_forklift(mv)
			_say("In the %s." % arg)
		"goto":
			# walk-in teleport round the claim (testing): goto creek / pond / knoll /
			# bog / pad / strip / vein / forest
			var G = load("res://scripts/ground.gd")
			var lay_: Dictionary = G.lay()
			var at2 := Vector2.INF
			match arg:
				"creek":
					var cr: Array = lay_["creek"]
					at2 = cr[cr.size() / 2]
				"pond":
					at2 = (lay_["pond"][0] as Vector2) + Vector2(float(lay_["pond"][1]) + 3.0, 0)
				"knoll":
					at2 = lay_["knoll"][0]
				"bog":
					at2 = G.mudbog()
				"pad":
					at2 = lay_["pad"]
				"strip":
					at2 = Vector2(main.plane.global_position.x + 8.0, main.plane.global_position.z)
				"door":
					# at the pilot's door, ready to get in
					var dp: Vector3 = main.plane.global_transform * Vector3(-1.7, 0.0, -0.15)
					at2 = Vector2(dp.x, dp.z)
				"vein":
					var V = load("res://scripts/veins.gd")
					V.make(int(Game.world_seed))
					var wp: Vector3 = main.walker.global_position
					var best := 1e9
					for v in V.list:
						var d := Vector2(float(v[0]) - wp.x, float(v[1]) - wp.z).length()
						if d < best:
							best = d
							at2 = Vector2(float(v[0]), float(v[1]))
				"forest":
					at2 = (lay_["knoll"][0] as Vector2) + Vector2(float(lay_["knoll"][1]) + 25.0, 0)
			if at2 == Vector2.INF:
				_say("goto creek / pond / knoll / bog / pad / strip / door / vein / forest")
				return
			if main.driving != null:
				main._get_off_forklift()
			if not main.on_foot:
				main._toggle_foot()
			var y: float = main.world.terrain.height_at(at2.x, at2.y)
			main.walker.place(Vector3(at2.x, y, at2.y), main.walker.yaw)
			_say("At the %s." % arg)
		"rec":
			# record what the game sounds like (master bus) to a wav in the
			# project folder: rec [seconds] (DESIGN_NOTES 143)
			var secs := clampf(float(arg) if arg.is_valid_float() else 10.0, 1.0, 60.0)
			var bus := AudioServer.get_bus_index("Master")
			var rec: AudioEffectRecord = null
			for ei in range(AudioServer.get_bus_effect_count(bus)):
				if AudioServer.get_bus_effect(bus, ei) is AudioEffectRecord:
					rec = AudioServer.get_bus_effect(bus, ei)
			if rec == null:
				rec = AudioEffectRecord.new()
				AudioServer.add_bus_effect(bus, rec)
			rec.set_recording_active(true)
			_say("Recording the sound for %.0f s..." % secs)
			get_tree().create_timer(secs).timeout.connect(func():
				rec.set_recording_active(false)
				var wav: AudioStreamWAV = rec.get_recording()
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_rec"))
				var path := "res://_rec/rec_%d.wav" % int(Time.get_unix_time_from_system())
				if wav != null:
					wav.save_to_wav(ProjectSettings.globalize_path(path))
					_say("Saved %s" % path)
				else:
					_say("Nothing recorded."))
		"damage", "burn":
			var vd: Node = main.vdamage
			if vd == null:
				return
			var vk: String = main._veh_key(main.driving) if main.driving != null else ""
			var sts: Node = main.world.structures
			if cmd == "burn" and sts != null and (arg != "" or vk == ""):
				# a building: by name, or the one you're standing in / next to
				var bid := arg
				if bid == "" or not sts.items.has(bid):
					var wp0: Vector3 = main.walker.global_position
					var bd0 := 1.0e9
					for id in sts.items:
						var dd0: float = sts._dist_to(sts.items[id], wp0)
						if dd0 < bd0:
							bd0 = dd0
							bid = id
				if sts.items.has(bid):
					sts.set_on_fire(bid, 0.3)
					_say("The %s is on fire." % bid)
				else:
					_say("burn <building>: %s" % ", ".join(PackedStringArray(sts.items.keys())))
				return
			if vk == "":
				_say("Get in a machine first.")
				return
			if cmd == "burn":
				# set what you're driving alight (testing fires and explosions)
				vd.set_on_fire(vk, vk.replace("_", " "), 0.6)
				_say("It's on fire: put it out with the water truck, or get clear.")
			else:
				var amt := clampf(float(arg) if arg.is_valid_float() else 0.5, 0.0, 1.0)
				vd.hurt(vk, amt, amt, amt)
				_say("Damaged: %s." % vd.status(vk))
		"bring":
			var veh: Node3D = {"tug": main.tug, "trailer": main.log_trailer, "pickup": main.pickup, "water": main.water_truck,
				"fuel": main.fuel_truck, "loader": main.loader}.get(arg, null)
			if veh == null:
				_say("bring tug / trailer / pickup / water / fuel / loader")
				return
			var wp2: Vector3 = main.walker.global_position
			var fw := Basis(Vector3.UP, main.walker.yaw) * Vector3(0, 0, -1)
			var vlen := 6.0
			var vb = veh.get("body")
			if vb != null and vb.get("size") is Vector3:
				vlen = 3.5 + float((vb.size as Vector3).z) * 0.5
			var at := wp2 + fw * vlen
			at.y = main.world.terrain.ground_level_at(at.x, at.z)
			var xf := Transform3D(Basis(Vector3.UP, main.walker.yaw), at)
			if veh.has_method("park"):
				veh.park(xf)
			else:
				veh.global_transform = xf
				if veh.has_method("settle"):
					veh.settle()
			_say("The %s is in front of you." % {"trailer": "log trailer", "water": "water truck", "fuel": "fuel truck"}.get(arg, arg))
		"lineup":
			# every machine parked side by side in front of you, noses toward you
			# (Dave: see all the new vehicles on the airport map)
			var pr2: Node = main.prospect
			var wp3: Vector3 = main.walker.global_position
			var yaw3: float = main.walker.yaw
			if pr2.dozers.is_empty():
				pr2._spawn_dozer(Transform3D(Basis.IDENTITY, wp3 + Vector3(0, 0, -200)))
			if pr2.excavators.is_empty():
				pr2._spawn_excavator(Transform3D(Basis.IDENTITY, wp3 + Vector3(0, 0, -220)))
			pr2._dirty = true
			var row: Array = [["pickup", main.pickup, 2.4], ["water truck", main.water_truck, 2.8], ["fuel truck", main.fuel_truck, 2.8],
				["loader", main.loader, 3.0], ["dozer", pr2.dozers[0], 3.6], ["excavator", pr2.excavators[0], 3.6],
				["tug", main.tug, 1.8], ["log trailer", main.log_trailer, 2.8]]
			if not main.forklifts.is_empty():
				row.append(["forklift", main.forklifts[0], 1.6])
			var fwd := Basis(Vector3.UP, yaw3) * Vector3(0, 0, -1)
			var side := Basis(Vector3.UP, yaw3) * Vector3(1, 0, 0)
			var total := 0.0
			for e in row:
				total += float(e[2]) * 2.0 + 1.5
			var off := -total * 0.5
			var names: Array = []
			for e in row:
				var vh: Node3D = e[1]
				if vh == null:
					continue
				off += float(e[2]) + 0.75
				var at3: Vector3 = wp3 + fwd * 14.0 + side * off
				at3.y = main.world.terrain.ground_level_at(at3.x, at3.z)
				var xf3 := Transform3D(Basis(Vector3.UP, yaw3 + PI), at3)
				if vh.has_method("park"):
					vh.park(xf3)
				else:
					vh.global_transform = xf3
					if vh.has_method("settle"):
						vh.settle()
				off += float(e[2]) + 0.75
				names.append(e[0])
			# and one of every item laid out on the ground between you and them
			var items: Array = main.inv.ITEMS.keys()
			var ioff := -float(items.size() - 1) * 0.6
			for it in items:
				var ip: Vector3 = wp3 + fwd * 5.0 + side * ioff
				ip.y = main.world.terrain.ground_level_at(ip.x, ip.z)
				main.inv.place_in_world(it, 1, ip, yaw3)
				ioff += 1.2
			_say("Lined up in front of you: " + ", ".join(names) + ", and one of every item (%d) on the ground. 'in <name>' to drive one." % items.size())
		"newworld", "seed":
			var sd := int(arg) if arg.is_valid_int() else randi() % 100000
			Game.world_seed = sd
			Game.save_settings()
			_say("World seed %d: the knoll, creek, pond and gold are laid out afresh. Reloading (digs and fires on the old map are cleared)." % sd)
			load("res://scripts/ground.gd").use_seed(sd)
			main.get_tree().reload_current_scene()
		"fire":
			var fp: Vector3 = main.walker.global_transform * Vector3(0, 0, -8.0) if main.on_foot else main.plane.global_position
			_say("Fire started." if main.fire != null and main.fire.ignite(fp, 4.0) else "Nothing to burn there.")
		"fail":
			plane.fail_engine(1 if arg.begins_with("r") else 0, "Admin failure.")
			_say("Engine failed.")
		"restart":
			for i in range(plane.engines().size()):
				plane.restart_engine(i)
			_say("Engines restarted.")
		"feather":
			_say(plane.feather())
		"engine":
			for e in plane.engines():
				e.set_running(plane.oat_c)
			_say("Engine(s) running.")
		_:
			_say("Unknown command. Type help.")


func _find_strip(arg: String) -> int:
	var ss: Array = main.world.terrain.strips
	if arg.is_valid_int():
		var i := int(arg)
		return i if i >= 0 and i < ss.size() else -1
	var a := arg.to_lower()
	for i in range(ss.size()):
		if String(ss[i]["name"]).to_lower().begins_with(a) or String(ss[i]["name"]).to_lower().contains(a):
			return i
	return -1
