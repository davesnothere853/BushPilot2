extends "res://scripts/cockpit.gd"
## The Meadowlark's rear (pilot's) cockpit (DESIGN_NOTES 153). The same live
## panel, switches and levers as the Wolverine (cockpit.gd), built in its own
## frame and then set into the biplane at 70 % size, under the forward
## coaming: an open cockpit's panel is a narrow board across the fuselage.
## No cabin around it (biplane_visual.gd builds the tub, seat and coaming),
## and a control stick between the knees instead of yokes.

const SCALE := 0.70
const OFFSET := Vector3(0.0, 0.07, 1.36)     # the Wolverine panel face (z -0.80) lands at z 0.80


func build(p: Node3D, terrain: RefCounted) -> void:
	transform = Transform3D(Basis().scaled(Vector3.ONE * SCALE), OFFSET)
	super.build(p, terrain)
	# no flaps on a biplane: the flap lever goes
	for i in range(controls.size() - 1, -1, -1):
		var c: Dictionary = controls[i]
		if String(c["id"]) == "flaps":
			(c["node"] as Node3D).visible = false
			controls.remove_at(i)


## Local (cockpit-frame) point for a point in the aeroplane's frame.
static func _loc(v: Vector3) -> Vector3:
	return (v - OFFSET) / SCALE


func _build_shell() -> void:
	var kit := MeshKit.new()
	# the panel's backing board, a crash pad along its top edge, and the
	# compass in its bowl on top of the panel
	kit.box_at(_loc(Vector3(0, 0.225, 0.785)) , Vector3(1.12, 0.56, 0.03), PANEL_DARK)
	kit.box_at(_loc(Vector3(0, 0.435, 0.80)), Vector3(1.14, 0.06, 0.10), Color(0.25, 0.14, 0.08))
	kit.box_at(_loc(Vector3(0, 0.47, 0.82)), Vector3(0.10, 0.07, 0.10), BLACK)
	var shell := kit.instance("Cabin")
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	_compass = Label3D.new()
	_compass.font_size = 24
	_compass.pixel_size = 0.0005
	_compass.modulate = Color(0.95, 0.92, 0.80)
	_compass.outline_size = 0
	_compass.position = _loc(Vector3(0, 0.47, 0.875))
	add_child(_compass)
	# Daylight under the coaming: an open cockpit's panel sits in the shade
	# of the deck and the top wing, but the sky lights it from behind you.
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.90, 1.0)
	fill.light_energy = 0.55
	fill.omni_range = 0.9 / SCALE
	fill.shadow_enabled = false
	fill.position = _loc(Vector3(0, 0.45, 1.25))
	add_child(fill)


func _build_yokes_and_pedals() -> void:
	# The stick: a steel tube from the floor, a black grip, rocking fore-aft
	# for pitch and side to side for roll.
	var base := _loc(Vector3(0, -0.40, 1.18))
	var kit := MeshKit.new()
	var len := 0.44 / SCALE
	kit.cylinder(Transform3D.IDENTITY, 0.012 / SCALE, 0.011 / SCALE, len, 10, Color(0.30, 0.30, 0.31), true)
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, len - 0.02, 0)), 0.018 / SCALE, 0.018 / SCALE, 0.12 / SCALE, 10, GRIP, true)
	kit.box_at(Vector3(0, len + 0.10 / SCALE, 0.008 / SCALE), Vector3(0.01, 0.01, 0.01) / SCALE, KNOB_RED)
	kit.box_at(Vector3(0, 0.0, 0), Vector3(0.08, 0.03, 0.08) / SCALE, Color(0.2, 0.2, 0.2))      # the boot
	var node := _part(kit, "yoke", base)
	_yokes.append(node)
	var stick_pose := func(n: Node3D, _v: float) -> void:
		var pitch_in: float = clampf(plane.elevator, -1.0, 1.0)
		var roll_in: float = clampf(plane.aileron, -1.0, 1.0)
		n.rotation = Vector3(-pitch_in * 0.30, 0, -roll_in * 0.28)
	_add("yoke", "yoke", node, Vector3(0, len + 0.04 / SCALE, 0), 0.08 / SCALE,
		func() -> float: return 0.0,
		func(_v: float) -> void: pass,
		stick_pose,
		func(_v: float) -> String: return "Stick: hold and drag to fly (drag down = pull back)")
	# Rudder pedals, heel brakes
	for ps in [-1.0, 1.0]:
		var pk := MeshKit.new()
		pk.box(Transform3D(Basis(Vector3.RIGHT, -0.45), Vector3(0, 0.06, 0) / SCALE), Vector3(0.08, 0.14, 0.02) / SCALE, Color(0.22, 0.22, 0.23))
		pk.box_at(Vector3(0, -0.02, 0.06) / SCALE, Vector3(0.02, 0.02, 0.14) / SCALE, CHROME)
		var pat := _loc(Vector3(ps * 0.13, -0.38, 0.90))
		var pn := _part(pk, "pedal", pat)
		_pedals.append([pn, pat, ps, -1.0])
