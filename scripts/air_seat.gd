extends Node3D
## An air-suspension seat (Dave): the cushion and back on a scissor linkage
## over a rubber air bag, a shock beside it, and the air valve lever on the
## side - flick it and the bag fills (the seat rises) or dumps (it drops),
## hissing, to one of four heights. The seat floats a little on the bag as
## the machine works. Built from its base at the node's origin (+Y up, the
## seat facing -Z).

const MeshKit = preload("res://scripts/meshkit.gd")

var target := 0.5                  # 0 dumped .. 1 full up
var h := 0.5
var col := Color(0.13, 0.13, 0.14)
var _top: Node3D
var _arms: Array = []              # [MeshInstance3D, side, which]
var _bag: MeshInstance3D
var _lever: Node3D
var _t := 0.0
const LOW := 0.12                  # base to cushion bottom, dumped
const HIGH := 0.24                 # full up
const STEPS := [0.0, 0.35, 0.7, 1.0]


func build(c: Color = Color(0.13, 0.13, 0.14)) -> void:
	col = c
	var steel := Color(0.25, 0.25, 0.26)
	var base := MeshKit.new()
	base.box_at(Vector3(0, 0.02, 0), Vector3(0.42, 0.04, 0.42), steel)            # the floor plate
	base.box_at(Vector3(0, 0.04, 0.0), Vector3(0.36, 0.02, 0.38), Color(0.1, 0.1, 0.1))   # the rubber boot's foot
	add_child(base.instance("SeatBase"))
	# the air bag between the scissors, a rubber bellows
	var bk := MeshKit.new()
	for k in range(4):
		var y := float(k) * 0.25
		bk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), 0.075 if k % 2 == 0 else 0.065, 0.065 if k % 2 == 0 else 0.075, 0.25, 14, Color(0.07, 0.07, 0.07), k == 3)
	_bag = bk.instance("AirBag")
	_bag.position = Vector3(0, 0.05, 0)
	add_child(_bag)
	# the scissor arms each side: two bars crossing, re-laid with the height
	for sd in [-1.0, 1.0]:
		for which in [0, 1]:
			var ak := MeshKit.new()
			ak.box_at(Vector3(0, 0.5, 0), Vector3(0.025, 1.0, 0.04), steel)
			var mi := ak.instance("Scissor")
			add_child(mi)
			_arms.append([mi, float(sd), which])
	# the seat itself rides on the top
	_top = Node3D.new()
	_top.name = "SeatTop"
	add_child(_top)
	var sk := MeshKit.new()
	sk.box_at(Vector3(0, 0.0, 0), Vector3(0.42, 0.03, 0.42), steel)                # the top frame
	sk.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.07, 0.0)), Vector3(0.5, 0.12, 0.48), col, 0.05)
	sk.rbox(Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, 0.42, 0.24)), Vector3(0.48, 0.6, 0.12), col, 0.05)
	for sx in [-1.0, 1.0]:
		sk.rbox(Transform3D(Basis.IDENTITY, Vector3(float(sx) * 0.29, 0.24, 0.02)), Vector3(0.07, 0.07, 0.4), col.lightened(0.05), 0.03)   # arm rests
		sk.box_at(Vector3(float(sx) * 0.29, 0.13, 0.15), Vector3(0.03, 0.18, 0.03), steel)
	# stitching lines across the cushion and the back
	for k2 in range(3):
		sk.box_at(Vector3(0, 0.131, -0.15 + float(k2) * 0.15), Vector3(0.44, 0.004, 0.006), col.darkened(0.4))
	_top.add_child(sk.instance("Cushion"))
	# the air valve lever on the right of the seat: the control
	_lever = Node3D.new()
	_lever.name = "AirValve"
	_lever.set_meta("control", "seat_air")
	_lever.position = Vector3(0.26, 0.02, -0.12)
	var lk := MeshKit.new()
	lk.box_at(Vector3(0, 0.0, 0), Vector3(0.04, 0.04, 0.05), Color(0.2, 0.2, 0.2))
	lk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0)), 0.008, 0.008, 0.12, 6, Color(0.6, 0.6, 0.6), true)
	lk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0)), 0.018, 0.018, 0.03, 10, Color(0.1, 0.25, 0.7), true)    # blue knob: air
	_lever.add_child(lk.instance("Lever"))
	_top.add_child(_lever)
	_lay()


## Flick the air valve: up a notch, or dump to the bottom from the top.
func air() -> String:
	var i := 0
	for k in range(STEPS.size()):
		if absf(float(STEPS[k]) - target) < 0.05:
			i = k
	target = float(STEPS[(i + 1) % STEPS.size()])
	return "seat air: %s" % ("dumped (low)" if target < 0.05 else ("up %d of 3" % int(round(target / 0.333))))


func _process(dt: float) -> void:
	_t += dt
	var was := h
	h = move_toward(h, target, dt * (0.35 if target > h else 0.8))       # fills slowly, dumps fast
	if absf(was - h) > 0.0001 or true:
		_lay()
	if _lever != null:
		_lever.rotation.z = -0.5 if absf(target - h) > 0.01 else 0.0     # held over while the air moves


func _lay() -> void:
	var top := lerpf(LOW, HIGH, h) + sin(_t * 2.3) * 0.004               # it floats a hair on the bag
	_top.position = Vector3(0, top, 0)
	_bag.scale = Vector3(1, top / 0.25 * 0.8, 1)
	# scissors: from the base's front/back pins to the top's back/front pins
	for a in _arms:
		var mi: MeshInstance3D = a[0]
		var sx: float = a[1] * 0.19
		var z0 := -0.16 if int(a[2]) == 0 else 0.16
		var p0 := Vector3(sx, 0.04, z0)
		var p1 := Vector3(sx, top, -z0)
		var d := p1 - p0
		var y := d.normalized()
		var x := Vector3.RIGHT
		mi.transform = Transform3D(Basis(x, y * d.length(), x.cross(y)), p0)
