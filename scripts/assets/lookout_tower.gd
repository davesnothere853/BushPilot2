extends Node3D
## Fire lookout on a steel tower (DESIGN_NOTES 228). A 60 ft (18.3 m) four-leg
## galvanised angle-iron tower of the kind the Forest Service bought from the
## windmill makers: legs splayed from 6.1 m at the footings to the 4.27 m cab,
## five sections each X-braced with flat bar and girted at the top, the stairs
## inside in flights with landings to the catwalk; the 14 ft cab on top
## (lookout_cab.gd). Concrete footings, the outhouse and the woodpile below.
## Base centre at the origin. Lab: "lookout_tower".

const Kits = preload("res://scripts/assets/kits.gd")
const Cab = preload("res://scripts/assets/lookout_cab.gd")

const H := 18.3
const B0 := 3.05          # half the base
const B1 := 2.2           # half the top (the cab's floor frame)
const SECTIONS := 5


func _ready() -> void:
	if get_child_count() == 0:
		add_child(make())


static func leg(i: int, t: float) -> Vector3:
	var sx := -1.0 if (i == 0 or i == 3) else 1.0
	var sz := -1.0 if i < 2 else 1.0
	var hw := lerpf(B0, B1, t)
	return Vector3(sx * hw, H * t, sz * hw)


static func make() -> Node3D:
	var K := Kits.new()
	var g := K.k("galv")
	var W := Color.WHITE
	for i in range(4):
		Kits.beam(g, leg(i, 0.0), leg(i, 1.0), 0.1, W)
		# concrete footing, the anchor bolts
		K.k("concrete").box(Transform3D(Basis.IDENTITY, leg(i, 0.0) + Vector3(0, 0.15, 0)), Vector3(0.8, 0.6, 0.8), Color.WHITE)
	for s in range(SECTIONS):
		var t0 := float(s) / SECTIONS
		var t1 := float(s + 1) / SECTIONS
		for e in range(4):
			var i0 := e
			var i1 := (e + 1) % 4
			Kits.beam(g, leg(i0, t0) + Vector3(0, 0.1, 0), leg(i1, t1) - Vector3(0, 0.1, 0), 0.045, W)
			Kits.beam(g, leg(i1, t0) + Vector3(0, 0.1, 0), leg(i0, t1) - Vector3(0, 0.1, 0), 0.045, W)
			Kits.beam(g, leg(i0, t1), leg(i1, t1), 0.07, W)          # the girt
	# the stairs: one flight a section, switching back, a landing at each girt
	var wood := K.k("wood")
	for s2 in range(SECTIONS):
		var ya := H * float(s2) / SECTIONS
		var yb := H * float(s2 + 1) / SECTIONS
		var dir := 1.0 if s2 % 2 == 0 else -1.0
		var zl := 0.45 * dir
		var hw := lerpf(B0, B1, float(s2) / SECTIONS) - 0.5
		var a := Vector3(-hw * dir * 0.7, ya, zl)
		var b := Vector3(hw * dir * 0.7, yb - 0.05, zl)
		for side in [-0.38, 0.38]:
			Kits.beam(g, a + Vector3(0, 0, side), b + Vector3(0, 0, side), 0.06, W)
			Kits.beam(g, a + Vector3(0, 0.9, side), b + Vector3(0, 0.9, side), 0.035, W)      # the handrail
		var nst := int((yb - ya) / 0.2)
		for st in range(nst):
			var q := a.lerp(b, (float(st) + 0.5) / nst)
			Kits.box(wood, q, Vector3(0.24, 0.04, 0.72), Color(0.82, 0.78, 0.70))
		Kits.box(wood, Vector3(b.x + dir * 0.45, yb - 0.04, 0), Vector3(0.9, 0.06, 1.7), Color(0.82, 0.78, 0.70))
	Cab.build(K, Vector3(0, H, 0), 0.9)
	# below: the outhouse (board and batten, a crescent) and a woodpile
	var oh := Vector3(9.0, 0, 5.0)
	Kits.box(K.k("wood"), oh + Vector3(0, 1.1, 0), Vector3(1.2, 2.2, 1.2), Color(0.8, 0.75, 0.68), 0.4)
	K.k("rust").box(Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.15), oh + Vector3(0, 2.3, 0)), Vector3(1.4, 0.05, 1.5), Color.WHITE)
	var wp := Vector3(-7.0, 0, 6.0)
	for w in range(5):
		for l in range(6 - w):
			Kits.rod(K.k("timber"), wp + Vector3(-1.2, 0.15 + 0.26 * float(w), -0.6 + 0.27 * float(l) + 0.13 * float(w)), wp + Vector3(1.2, 0.15 + 0.26 * float(w), -0.6 + 0.27 * float(l) + 0.13 * float(w)), 0.13, Color(0.8, 0.7, 0.6), 7, true)
	return K.node("lookout_tower")
