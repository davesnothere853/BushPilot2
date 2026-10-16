extends Node
## VEHICLE TEST BED (DESIGN_NOTES 195): the Model Lab's panel for checking a
## machine's moving parts without starting the game.
##
## - Buttons (right side) or lab_cmd.txt "test <what>":
##     door_l, door_r, doors, hood, gate, lights, blink   - open / shut, switch
##     spin    - the wheels roll (and the drive shafts turn with them)
##     steer   - the front wheels sweep lock to lock (the steering wheel turns)
##     bounce / twist / roll / pitch - the suspension cycles: all four up and
##               down, diagonal articulation, side to side, front to back
##     chassis - hide the body panels and glass to see the frame and running gear
##     ground  - hide the ground (look from underneath)
##     drive   - drive it on the test course: W/S throttle and brake, A/D steer,
##               Space handbrake (bumps, whoops and offset mounds ahead of it)
##     stop    - everything back at rest
##     run     - the whole check in order, a picture of each state, and
##               _rec/test_sheet.png with all of them
## Works for any vehicle the lab shows: a button does nothing on a machine
## that hasn't got that part.

var lab: Node
var veh: Node3D
var _panel: PanelContainer
var _info: Label
var _btns := {}
var spin_on := false
var steer_on := false
var susp := ""
var drive_on := false
var chassis := false
var _t := 0.0
var _spin := 0.0
var _freeze := false
var water_on := false            # the water truck's systems running (engine, pump, sprays)
var _seq: Array = []
var _seq_wait := 0.0
var _shots: Array = []            # [label, Image] from the last run
var _shot_after := -1.0
var _shot_label := ""
var _ground_nodes: Array = []
var brk: RefCounted                # vehicle_breakage.gd on the vehicle now

const HIDE_FOR_CHASSIS := ["BodyPaint", "BodyChrome", "Glass", "Interior", "HoodPivot", "TailgatePivot", "DoorLPivot", "DoorRPivot",
	"Cab", "CabGlass", "CabTrim", "CabSeals", "CabLamps", "Hood", "DoorL", "DoorR", "Tank", "Skirt", "TankFittings", "SkirtLamps", "Under"]


func _ready() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 60
	add_child(ui)
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -190
	_panel.offset_right = -10
	_panel.offset_top = 10
	_panel.anchor_bottom = 1.0
	_panel.offset_bottom = -10
	ui.add_child(_panel)
	# the list scrolls (mouse wheel or drag the bar) - it's taller than the screen
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var title := Label.new()
	title.text = "TEST BED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	# drop-down sections (Dave): click a heading to open or fold it
	var sections := [
		["Doors and parts", true, [["door_l", "Driver door"], ["door_r", "Passenger door"], ["door_low", "Lower door"], ["hood", "Hood"], ["gate", "Tailgate"], ["fuel", "Fuel door"],
			["lights", "Lights"], ["blink", "Blinker"]]],
		["Plane", true, [["prop", "Run engine (prop)"], ["prop_type", "Prop: next type"], ["filter", "Air filter: off / new"], ["filter_kind", "Air filter: white / red / yellow"], ["filter_dirt", "Air filter: add dirt"], ["flaps", "Flaps up / down"], ["ctl", "Control sweep"], ["measure", "Measure vs real"],
			["clip", "Clip check"], ["bp_side", "Blueprint: side"], ["bp_front", "Blueprint: front"], ["bp_off", "Blueprint off"], ["markers", "Reference markers"]]],
		["Wheels and suspension", false, [["psi_up", "Tyre pressure +2 psi"], ["psi_down", "Tyre pressure -2 psi"], ["spin", "Spin wheels"], ["steer", "Steer sweep"], ["bounce", "Suspension: bounce"], ["twist", "Suspension: twist"],
			["roll", "Suspension: roll"], ["pitch", "Suspension: pitch"]]],
		["View", false, [["chassis", "Chassis view"], ["ground", "Hide ground"], ["drive", "Drive (WASD)"], ["v_side", "Side view (flat)"],
			["v_front", "Front view (flat)"], ["v_top", "Top view (flat)"], ["v_cockpit", "Cockpit view"]]],
		["Winch", false, [["w_tree", "Winch: hook tree"], ["w_truck", "Winch: stuck truck"], ["w_in", "Winch IN"], ["w_hold", "Winch HOLD"], ["w_out", "Winch OUT"], ["w_stow", "Winch: stow"]]],
		["Damage", false, [["line_leak", "Hydraulic line: leak"], ["line_fix", "Hydraulic lines: fix"], ["crash_front", "Crash: front"], ["crash_side", "Crash: side"], ["rollover", "ROLL OVER"], ["shoot", "Hit windshield"], ["explode", "EXPLODE"],
			["prop_strike", "Prop strike"], ["wing_tree", "Wing into tree"], ["hard_landing", "Hard landing"], ["tail_strike", "Tail strike"], ["noseover", "Nose over"]]],
		["Test run", true, [["showcase", "SHOWCASE: all vehicles"], ["run", "RUN FULL TEST"], ["water", "Water: pump + sprays"], ["hose", "Hose: pull out + reel in"], ["stop", "Stop / reset"], ["rebuild", "Rebuild (repair)"]]],
	]
	for sec in sections:
		var head := Button.new()
		head.text = ("v  " if sec[1] else ">  ") + String(sec[0])
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.add_theme_font_size_override("font_size", 13)
		head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		head.focus_mode = Control.FOCUS_NONE
		box.add_child(head)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 2)
		body.visible = sec[1]
		box.add_child(body)
		var title_txt: String = sec[0]
		head.pressed.connect(func():
			body.visible = not body.visible
			head.text = ("v  " if body.visible else ">  ") + title_txt)
		for row in sec[2]:
			var b := Button.new()
			b.text = row[1]
			b.add_theme_font_size_override("font_size", 13)
			b.focus_mode = Control.FOCUS_NONE
			var what: String = row[0]
			b.pressed.connect(func(): command(what))
			body.add_child(b)
			_btns[what] = b
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.custom_minimum_size = Vector2(170, 0)
	_info.add_theme_font_size_override("font_size", 12)
	box.add_child(_info)
	_panel.visible = false


func set_ui(on: bool) -> void:
	_panel.get_parent().visible = on


## A new vehicle in the lab (or null for a non-vehicle model).
func attach(v: Node3D, ground: Array) -> void:
	veh = v
	_ground_nodes = ground
	_panel.visible = v != null
	if v == null:
		return
	if v.get("test_drive") != null:
		v.test_drive = true
	brk = load("res://scripts/vehicle_breakage.gd").new(v)
	if chassis:
		_set_chassis(true)
	for k in _btns.keys():
		var bt := _btns[k] as Button
		if not bt.has_meta("label"):
			bt.set_meta("label", bt.text)
		bt.text = String(bt.get_meta("label"))
		bt.disabled = not _can(String(k))
	# a plane names its own parts (split door, cowl, baggage door...)
	if v.has_method("test_labels"):
		var labels: Dictionary = v.test_labels()
		for k2 in labels.keys():
			if _btns.has(k2):
				(_btns[k2] as Button).text = String(labels[k2])
	_say("")


func _can(what: String) -> bool:
	if veh == null:
		return false
	match what:
		"door_l", "door_r": return veh.has_method("door_toggle")
		"door_low": return veh.has_method("test_labels") and veh.has_method("door_toggle")
		"hood": return veh.has_method("hood_toggle")
		"gate": return veh.has_method("tailgate_toggle")
		"fuel": return veh.has_method("fuel_door_toggle")
		"lights": return veh.has_method("lights_toggle")
		"blink": return veh.has_method("blinker")
		"spin", "steer", "bounce", "twist", "roll", "pitch", "drive": return veh.get("body") != null
		"prop": return veh.has_method("prop_toggle")
		"psi_up", "psi_down": return veh.has_method("tyre_pressure")
		"filter", "filter_kind", "filter_dirt": return veh.has_method("filter_service")
		"prop_type": return veh.has_method("prop_next")
		"flaps": return veh.has_method("flaps_toggle")
		"ctl": return veh.has_method("blinker") and veh.has_method("test_labels")
		"measure": return veh.has_method("measure")
		"clip": return veh.has_method("clip_check")
		"bp_side", "bp_front", "bp_off": return veh.has_method("blueprint")
		"markers": return veh.has_method("markers_toggle")
		"line_leak", "line_fix": return veh.has_method("damage_line")
		"prop_strike", "wing_tree", "hard_landing", "tail_strike": return veh.has_method("damage_test")
		"noseover": return veh.get("body") != null and veh.has_method("damage_test")
		"water": return veh.has_method("water_test")
		"hose": return veh.has_method("hose_demo")
	return true


func _say(m: String) -> void:
	var on: Array = []
	if spin_on: on.append("spin")
	if steer_on: on.append("steer")
	if susp != "": on.append(susp)
	if drive_on: on.append("DRIVING")
	if chassis: on.append("chassis")
	_info.text = m + ("\n" if m != "" else "") + ("on: " + ", ".join(on) if not on.is_empty() else "")
	if lab != null and m != "":
		lab.call("say", m)


## A button or a "test <what>" line. True if it knew the word.
func command(what: String) -> bool:
	if what == "showcase":
		# every vehicle in turn: cold start and range of motion (tools/showcase.gd)
		if lab != null:
			lab.call("_run_cmd", "run res://tools/showcase.gd")
		return true
	if veh == null or not is_instance_valid(veh):
		return false
	var m := ""
	match what:
		"door_l": m = veh.door_toggle(0)
		"door_r": m = veh.door_toggle(1)
		"door_low": m = veh.door_toggle(2)
		"doors": m = veh.door_toggle(-1)
		"hood": m = veh.hood_toggle() if veh.has_method("hood_toggle") else ""
		"hose":
			m = veh.hose_demo(true)
		"water":
			water_on = not water_on
			m = veh.water_test(water_on) if veh.has_method("water_test") else ""
		"gate", "tailgate": m = veh.tailgate_toggle() if veh.has_method("tailgate_toggle") else ""
		"fuel": m = veh.fuel_door_toggle() if veh.has_method("fuel_door_toggle") else ""
		"lights": m = veh.lights_toggle() if veh.has_method("lights_toggle") else ""
		"blink": m = veh.blinker(-1) if veh.has_method("blinker") else ""
		"prop": m = veh.prop_toggle()
		"prop_type": m = veh.prop_next()
		"filter": m = veh.filter_service()
		"filter_kind": m = veh.filter_swap_kind()
		"filter_dirt": m = veh.filter_add_dirt()
		"psi_up": m = veh.tyre_pressure(2.0)
		"psi_down": m = veh.tyre_pressure(-2.0)
		"flaps": m = veh.flaps_toggle()
		"ctl": m = veh.blinker(-1)
		"measure": m = veh.measure()
		"clip": m = veh.clip_check()
		"bp_side": m = veh.blueprint("side")
		"bp_front": m = veh.blueprint("front")
		"bp_off": m = veh.blueprint("off")
		"markers": m = veh.markers_toggle()
		"line_leak": m = veh.damage_line()
		"line_fix": m = veh.repair_lines()
		"v_side", "v_front", "v_top", "v_cockpit":
			m = _flat_view(what)
		"spin":
			spin_on = not spin_on
			m = "Wheels %s." % ("rolling" if spin_on else "stopped")
		"steer":
			steer_on = not steer_on
			m = "Steering sweep %s." % ("on" if steer_on else "off")
		"bounce", "twist", "roll", "pitch":
			susp = "" if susp == what else what
			_freeze = false
			m = "Suspension %s." % (susp if susp != "" else "at rest")
		"chassis":
			chassis = not chassis
			_set_chassis(chassis)
			m = "Chassis view %s." % ("on" if chassis else "off")
		"ground":
			for g in _ground_nodes:
				if is_instance_valid(g):
					(g as Node3D).visible = not (g as Node3D).visible
			m = "Ground toggled."
		"drive":
			drive_on = not drive_on
			spin_on = false
			steer_on = false
			susp = ""
			m = "Drive: W/S, A/D, Space. Course is ahead." if drive_on else "Drive off."
		"stop":
			_reset()
			m = "All at rest."
		"run":
			_start_run()
			m = "Running the full test..."
		"crash_front", "crash_side", "shoot", "explode", "prop_strike", "wing_tree", "hard_landing", "tail_strike":
			m = veh.damage_test(what, brk) if veh.has_method("damage_test") else _smash(what)
		"noseover":
			# tipped onto its nose (a taildragger braking too hard on soft ground)
			var b2 = veh.get("body")
			if b2 != null:
				drive_on = true
				b2.vel = -b2.basis.z * 5.0 + Vector3(0, 1.0, 0)
				b2.angvel = b2.basis.x * -3.2
				if brk != null and veh.has_method("damage_test"):
					veh.damage_test("prop_strike", brk)
				m = "Nose over! Drive on: W/S, A/D."
		"rollover":
			# a rollover: thrown sideways and spun onto its roof, then it plays out (drive on)
			var b = veh.get("body")
			if b != null:
				drive_on = true
				b.pos += Vector3(0, 0.6, 0)
				b.vel = b.basis.x * 7.0 + Vector3(0, 3.0, 0)
				b.angvel = -b.basis.z * 5.5
				m = "Rolling it over. Drive on: W/S, A/D."
		"w_tree", "w_truck", "w_in", "w_hold", "w_out", "w_stow":
			m = _winch(what)
		"rebuild":
			if lab != null:
				lab.call("_rebuild")
			m = "Rebuilt."
		_:
			return false
	_say(m)
	return true


# ------------------------------------------------------------------------------
#  Winch tests (DESIGN_NOTES 203): a tree 14 m ahead, or a second truck stuck in
#  a mud hole ahead; hook it, winch in. Both trucks are stepped here.
# ------------------------------------------------------------------------------
var _tree: Node3D
var _stuck: Node3D
var _mud_on := false


func _winch(what: String) -> String:
	var w = veh.get("winch")
	if w == null:
		return "No winch on this one."
	var xf := veh.global_transform
	match what:
		"w_tree":
			_clear_targets()
			_tree = Node3D.new()
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.16
			cm.bottom_radius = 0.22
			cm.height = 6.0
			mi.mesh = cm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.30, 0.22, 0.15)
			mi.material_override = mat
			mi.position.y = 3.0
			_tree.add_child(mi)
			veh.get_parent().add_child(_tree)
			_tree.global_position = xf * Vector3(0.6, 0, -16.0)
			w.state = "stowed"
			w.take(w.fair_world())
			return w.hook_to(_tree, _tree.global_position + Vector3(0, 0.6, 0), "tree") + " (tree 14 m ahead)"
		"w_truck":
			_clear_targets()
			var scr = load("res://scripts/pickup_truck.gd")
			_stuck = scr.new()
			_stuck.terrain = veh.terrain
			veh.get_parent().add_child(_stuck)
			_stuck.build()
			_stuck.park(Transform3D(Basis(Vector3.UP, PI), xf * Vector3(0, 0, -15.0)))
			# a mud hole under it: it sinks in and can't drive out on its own
			var WB = load("res://scripts/wheeled_body.gd")
			var mc: Vector3 = _stuck.global_position
			WB.mud_fn = func(x: float, z: float) -> float: return 1.0 if Vector2(x - mc.x, z - mc.z).length() < 4.0 else 0.0
			_mud_on = true
			_stuck.stuck_drag = 26000.0      # bogged: it takes a real pull (the cable goes bar-tight)
			for i in range(240):
				_stuck.body.step(1.0 / 120.0, 0.0, 0.0, false)
			_stuck.global_transform = _stuck.body.transform()
			w.state = "stowed"
			w.take(w.fair_world())
			# hooked to its nearest winch point (DESIGN_NOTES 225)
			var TP = load("res://scripts/tow_points.gd")
			var near: Array = TP.nearest(_stuck.winch_points(), w.fair_world(), 100.0)
			return w.hook_to(_stuck, near[1], "vehicle") + " (a truck stuck in mud 15 m ahead, hooked on its %s)" % near[0]
		"w_in":
			w.set_reel(-1)
			return "Winch reeling in."
		"w_hold":
			w.set_reel(0)
			return "Winch holding."
		"w_out":
			w.set_reel(1)
			return "Winch paying out." 
		"w_stow":
			w.set_reel(0)
			_clear_targets()
			return w.stow()
	return ""


func _clear_targets() -> void:
	for n in [_tree, _stuck]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_tree = null
	_stuck = null
	if _mud_on:
		load("res://scripts/wheeled_body.gd").mud_fn = Callable()
		_mud_on = false


## Flat (orthographic) views for checking against drawings, and the cockpit.
func _flat_view(what: String) -> String:
	if lab == null:
		return ""
	var c: Vector3 = veh.global_transform * Vector3(0, 1.4, 0.8)
	var line := ""
	match what:
		"v_side": line = "%s cam %.2f %.2f %.2f %.2f %.2f %.2f -5.2" % [lab.get("_current"), c.x + 15.0, c.y, c.z, c.x, c.y, c.z]
		"v_front": line = "%s cam %.2f %.2f %.2f %.2f %.2f %.2f -6.5" % [lab.get("_current"), c.x, c.y, c.z - 15.0, c.x, c.y, c.z]
		"v_top": line = "%s cam %.2f %.2f %.2f %.2f %.2f %.2f -8.0" % [lab.get("_current"), c.x, c.y + 15.0, c.z + 0.01, c.x, c.y, c.z]
		"v_cockpit":
			if not veh.has_method("eye_xf"):
				return "No cockpit."
			var ex: Transform3D = veh.eye_xf()
			var at: Vector3 = ex.origin + ex.basis * Vector3(0, -0.15, -1.0)
			var from: Vector3 = ex.origin + ex.basis * Vector3(0.0, 0.0, -0.09)   # just in front of the face (behind it, the head and hat filled the view)
			line = "%s cam %.2f %.2f %.2f %.2f %.2f %.2f 75" % [lab.get("_current"), from.x, from.y, from.z, at.x, at.y, at.z]
	lab.call("_run_cmd", line)
	return what.substr(2).capitalize() + " view."


## Break things (vehicle_breakage.gd): hits in the truck's own frame.
func _smash(what: String) -> String:
	if brk == null:
		return ""
	var xf := veh.global_transform
	var nz := -2.5
	var cz := -1.0
	var tb = load("res://scripts/truck_body.gd")
	if tb != null and not (tb.P as Dictionary).is_empty():
		nz = float(tb.P["nose_z"])
		cz = float(tb.P["cowl_z"])
	match what:
		"crash_front":
			brk.hit(xf * Vector3(0.25, 0.75, nz - 0.1), xf.basis * Vector3(0, 0, 1) * 16000.0, 0.75)
			return "Front-end crash."
		"crash_side":
			brk.hit(xf * Vector3(-1.05, 0.95, cz + 0.5), xf.basis * Vector3(1, 0, 0) * 12000.0, 0.7)
			return "Side hit at the driver's door."
		"shoot":
			brk.hit(xf * Vector3(randf_range(-0.5, 0.5), 1.62, cz + 0.12), xf.basis * Vector3(0, -0.3, 1) * 260.0, 0.15)
			return "Something hit the windshield."
		"explode":
			brk.explode(xf * Vector3(0, 0.5, -1.2), 45000.0)
			return "BOOM."
	return ""


func _reset() -> void:
	if water_on and veh != null and veh.has_method("water_test"):
		veh.water_test(false)
	water_on = false
	spin_on = false
	steer_on = false
	susp = ""
	drive_on = false
	_freeze = false
	if chassis:
		chassis = false
		_set_chassis(false)
	if veh != null:
		if veh.get("doors_open") != null:
			for i in range(veh.doors_open.size()):
				veh.doors_open[i] = false
		if veh.get("hood_open") != null:
			veh.hood_open = false
		if veh.get("gate_open") != null:
			veh.gate_open = false
		var b = veh.get("body")
		if b != null:
			b.steer = 0.0
			for i in range(b.compress.size()):
				b.compress[i] = 0.45
			if veh.has_method("park"):
				veh.park(Transform3D.IDENTITY)


func _set_chassis(on: bool) -> void:
	if veh == null:
		return
	# the running gear stays (parts marked "chassis", axles, suspension, wheels);
	# every body panel, glass, lamp and the opening parts go
	var keep := ["AxleF", "AxleR", "Suspension"]
	for body in veh.find_children("Body", "Node3D", true, false):
		for c in (body as Node).get_children():
			if c is Node3D and not keep.has(String(c.name)) and not bool((c as Node).get_meta("chassis", false)):
				(c as Node3D).visible = not on
	for nm in HIDE_FOR_CHASSIS:
		var n := veh.find_child(nm, true, false) as Node3D
		if n != null:
			n.visible = not on

func _process(delta: float) -> void:
	if veh == null or not is_instance_valid(veh):
		return
	_run_step(delta)
	if veh.has_method("hose_demo_step"):
		veh.hose_demo_step(delta)
	if water_on and veh.has_method("work") and veh.get("body") != null:
		var wm: String = veh.work(delta)
		_info.text = (wm + "\n" if wm != "" else "") + (veh.status() if veh.has_method("status") else "")
	if drive_on:
		return                      # _physics_process moves it
	var b = veh.get("body")
	if b != null:
		if not _freeze:
			_t += delta
		if spin_on:
			_spin += delta * 5.0
		for i in range(b.wheel_spin.size()):
			b.wheel_spin[i] = _spin
		if steer_on:
			b.steer = sin(_t * 0.9) * float(b.max_steer)
		if susp != "":
			var k := sin(_t * 1.4)
			for i in range(b.compress.size()):
				var left := i % 2 == 0
				var front := i < 2
				var sgn := 1.0
				match susp:
					"twist": sgn = 1.0 if left == front else -1.0
					"roll": sgn = 1.0 if left else -1.0
					"pitch": sgn = 1.0 if front else -1.0
				b.compress[i] = clampf(0.45 + 0.5 * k * sgn, 0.0, 1.0)
	if veh.has_method("_animate"):
		veh._animate()


func _physics_process(delta: float) -> void:
	if veh != null and is_instance_valid(veh) and veh.has_method("winch_step"):
		veh.winch_step(delta, drive_on)
		if lab != null and lab.has_method("_place_driver"):
			lab.call("_place_driver")      # the driver rides along when the winch drags the truck
		if _stuck != null and is_instance_valid(_stuck):
			_stuck.winch_step(delta, false)
			_stuck._animate()
		var w = veh.get("winch")
		if w != null and w.state != "stowed":
			_info.text = w.status()
	if not drive_on or veh == null or not is_instance_valid(veh):
		return
	var b = veh.get("body")
	if b == null:
		return
	var thr := Input.get_action_strength("ui_up") - Input.get_action_strength("ui_down")
	var st := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	if Input.is_physical_key_pressed(KEY_W): thr = 1.0
	if Input.is_physical_key_pressed(KEY_S): thr = -1.0
	if Input.is_physical_key_pressed(KEY_D): st = 1.0
	if Input.is_physical_key_pressed(KEY_A): st = -1.0
	var hb := Input.is_physical_key_pressed(KEY_SPACE)
	b.step(delta, thr, st, hb)
	if absf(thr) < 0.05 and not hb:
		var fwd: Vector3 = -b.basis.z
		var sp: float = b.vel.dot(fwd)
		b.vel -= fwd * signf(sp) * minf(absf(sp), 1.8 * delta)
	veh.global_transform = b.transform()
	if veh.get("yaw") != null:
		veh.yaw = b.yaw()
	if veh.has_method("_animate"):
		veh._animate()
	if lab != null:
		lab.call("follow", veh.global_position + Vector3(0, 1.0, 0))
	_info.text = "DRIVING  %.0f km/h\nwheels %s" % [absf(float(b.speed)) * 3.6, " ".join(Array(b.compress).map(func(c): return "%.2f" % c))]


# ------------------------------------------------------------------------------
#  The full test: each state held, then photographed (lab camera), one sheet
# ------------------------------------------------------------------------------
func _start_run() -> void:
	_reset()
	_shots.clear()
	# [what to do, camera yaw pitch dist (or empty), seconds to settle, label]
	var front := [2.5, -0.18, 7.5]
	var lf := [-0.9, -0.15, 7.5]
	var rear := [0.5, -0.2, 8.0]
	var low := [2.4, -0.04, 7.0]
	_seq = [
		[func(): pass, lf, 1.0, "at rest"],
		[func(): command("door_l"), lf, 1.4, "driver door open"],
		[func(): command("door_r"), [0.9, -0.15, 7.5], 1.4, "passenger door open"],
		[func(): command("doors"), front, 0.1, ""],
		[func(): command("hood"), front, 1.6, "hood up"],
		[func(): command("hood"); command("gate"), rear, 1.4, "tailgate down"],
		[func(): command("gate"), lf, 1.0, ""],
		[func(): _pose("steer", 1.0), [2.7, -0.10, 6.0], 0.8, "full lock right"],
		[func(): _pose("steer", -1.0), [2.7, -0.10, 6.0], 0.8, "full lock left"],
		[func(): _pose("steer", 0.0); chassis = true; _set_chassis(true); _pose("twist", 1.0), low, 0.6, "articulation (FL+RR up)"],
		[func(): _pose("twist", -1.0), low, 0.6, "articulation (FR+RL up)"],
		[func(): _pose("bounce", 1.0), [-1.57, -0.05, 7.0], 0.6, "full bump"],
		[func(): _pose("bounce", -1.0), [-1.57, -0.05, 7.0], 0.6, "full droop"],
		[func(): _reset(); _pose("roll", 1.0), [2.5, -0.06, 7.5], 0.6, "body roll"],
		[func(): _reset(); _pose("pitch", 1.0), [-1.57, -0.05, 7.5], 0.6, "pitch (front up)"],
		[func(): _reset(); if veh.has_method("water_test"): command("water"), [2.2, -0.1, 9.0], 4.0, "pump + front sprays"],
		[func(): pass, [0.6, -0.12, 9.0], 1.5, "rear and side sprays"],
		[func(): _reset(); if veh.has_method("hose_demo"): command("hose"), [0.9, -0.35, 16.0], 9.0, "hose paid out"],
		[func(): pass, [0.9, -0.35, 16.0], 6.0, "hose reeled back in"],
		[func(): _reset(), lf, 0.5, ""],
	]
	_seq_wait = 0.0


## Hold a pose: steer -1..1 of full lock, or a suspension mode at -1..1.
func _pose(mode: String, k: float) -> void:
	var b = veh.get("body") if veh != null else null
	if b == null:
		return
	if mode == "steer":
		b.steer = k * float(b.max_steer)
		steer_on = false
		return
	susp = mode
	_freeze = true
	_t = asin(clampf(k, -1.0, 1.0)) / 1.4


func _run_step(delta: float) -> void:
	if _shot_after > 0.0:
		_shot_after -= delta
		if _shot_after <= 0.0:
			var img := get_viewport().get_texture().get_image()
			if img != null:
				img.convert(Image.FORMAT_RGB8)
				img.resize(640, 360)
				_shots.append([_shot_label, img])
				img.save_png(ProjectSettings.globalize_path("res://_rec/test_%02d.png" % _shots.size()))
			_shot_label = ""
		return
	if _seq.is_empty():
		return
	_seq_wait -= delta
	if _seq_wait > 0.0:
		return
	var step: Array = _seq.pop_front()
	(step[0] as Callable).call()
	var cam: Array = step[1]
	if not cam.is_empty() and lab != null:
		lab.call("orbit", float(cam[0]), float(cam[1]), float(cam[2]))
	_seq_wait = float(step[2])
	if String(step[3]) != "":
		_shot_label = String(step[3])
		_shot_after = float(step[2]) - 0.05
		_seq_wait += 0.1
	if _seq.is_empty():
		_seq_wait = 0.0
		get_tree().create_timer(0.3).timeout.connect(_save_sheet)


func _save_sheet() -> void:
	if _shots.is_empty():
		return
	var cols := 3
	var rows := int(ceil(_shots.size() / float(cols)))
	var out := Image.create(640 * cols, 360 * rows, false, Image.FORMAT_RGB8)
	out.fill(Color(0.1, 0.1, 0.1))
	for i in range(_shots.size()):
		var img: Image = _shots[i][1]
		out.blit_rect(img, Rect2i(0, 0, 640, 360), Vector2i((i % cols) * 640, (i / cols) * 360))
	out.save_png(ProjectSettings.globalize_path("res://_rec/test_sheet.png"))
	var names: Array = _shots.map(func(s): return String(s[0]))
	FileAccess.open("res://_rec/test_sheet.txt", FileAccess.WRITE).store_string("\n".join(names))
	_say("Test done: _rec/test_sheet.png (%d pictures)." % _shots.size())
