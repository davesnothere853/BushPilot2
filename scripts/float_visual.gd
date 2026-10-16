extends Node3D
## Amphibious floats: two aluminium floats on struts, a main wheel in each just
## behind the step and a nose wheel in each bow. The wheels fold up into the
## floats (nose wheels flip up onto the deck), and water rudders hang off the
## sterns. Shapes follow plane.gd FLOAT_ST so what you see is what floats.

const MeshKit = preload("res://scripts/meshkit.gd")
const ALU := Color(0.70, 0.71, 0.70)
const KEEL := Color(0.16, 0.17, 0.18)
const STRUT := Color(0.88, 0.88, 0.86)
const TIRE := Color(0.07, 0.07, 0.07)
const HUB := Color(0.55, 0.56, 0.57)

var plane: Node3D
var _wheels: Array[Node3D] = []     # left main, right main, left nose, right nose
var _rudders: Array[Node3D] = []
var _spin := 0.0


func build() -> void:
	var kit := MeshKit.new()
	var st: Array = plane.FLOAT_ST
	for sx in [-plane.FLOAT_X, plane.FLOAT_X]:
		# Hull: a V bottom up to the chine, straight sides, a rounded deck.
		var rings: Array = []
		for row in st:
			var z: float = row[0]
			var keel: float = row[1]
			var hb: float = row[2]
			var deck: float = row[3]
			var chine: float = keel + minf(0.16, (deck - keel) * 0.4)
			var r := PackedVector3Array()
			r.append(Vector3(sx, keel, z))
			r.append(Vector3(sx + hb, chine, z))
			r.append(Vector3(sx + hb, deck - 0.05, z))
			r.append(Vector3(sx + hb * 0.7, deck, z))
			r.append(Vector3(sx - hb * 0.7, deck, z))
			r.append(Vector3(sx - hb, deck - 0.05, z))
			r.append(Vector3(sx - hb, chine, z))
			rings.append(r)
		kit.loft(rings, ALU, true, true)
		# A dark keel strip and the step.
		for k in range(st.size() - 1):
			var a: Array = st[k]
			var b: Array = st[k + 1]
			kit.quad(Vector3(sx - 0.03, a[1] - 0.005, a[0]), Vector3(sx + 0.03, a[1] - 0.005, a[0]),
				Vector3(sx + 0.03, b[1] - 0.005, b[0]), Vector3(sx - 0.03, b[1] - 0.005, b[0]), KEEL, Vector3.DOWN)
		# Struts up to the fuselage, and a spreader bar between the floats.
		var inner: float = sx * 0.36
		for zz in [-1.15, 0.55]:
			_bar(kit, Vector3(sx, -1.36, zz), Vector3(inner, -0.58, zz - 0.05), 0.035, STRUT)
			_bar(kit, Vector3(sx, -1.36, zz + 0.2), Vector3(inner, -0.58, zz - 0.35), 0.02, STRUT)
		# Cleats and a bumper at the bow.
		kit.box_at(Vector3(sx, -1.38, -3.30), Vector3(0.10, 0.05, 0.10), KEEL)
		kit.box_at(Vector3(sx, -1.33, 2.9), Vector3(0.08, 0.04, 0.12), KEEL)
	for zz in [-1.15, 0.55]:
		_bar(kit, Vector3(-plane.FLOAT_X, -1.36, zz), Vector3(plane.FLOAT_X, -1.36, zz), 0.025, STRUT)
	kit.smooth(32.0)
	var body := kit.instance("Floats")
	add_child(body)

	# Wheels on pivots so they can fold.
	for i in range(4):
		var main := i < 2
		var r := 0.20 if main else 0.14
		var w := 0.13 if main else 0.10
		var wk := MeshKit.new()
		wk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-w * 0.5, 0, 0)), r, r, w, 16, TIRE, true)
		wk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-w * 0.55, 0, 0)), r * 0.45, r * 0.45, w * 1.1, 10, HUB, true)
		wk.smooth(50.0)
		var pivot := Node3D.new()
		var spinner := wk.instance("Tyre")
		pivot.add_child(spinner)
		var leg := MeshKit.new()
		leg.box_at(Vector3(0, r * 0.5 + 0.12, 0), Vector3(0.05, r + 0.24, 0.07), STRUT)
		pivot.add_child(leg.instance("Leg"))
		add_child(pivot)
		_wheels.append(pivot)
	# Water rudders at the sterns.
	for sx in [-plane.FLOAT_X, plane.FLOAT_X]:
		var rk := MeshKit.new()
		rk.box_at(Vector3(0, -0.18, 0.12), Vector3(0.02, 0.36, 0.24), KEEL)
		var rp := Node3D.new()
		rp.position = Vector3(sx, -1.5, 3.12)
		rp.add_child(rk.instance("WaterRudder"))
		add_child(rp)
		_rudders.append(rp)


static func _bar(kit: RefCounted, a: Vector3, b: Vector3, radius: float, col: Color) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	kit.cylinder(Transform3D(Basis(x, y, z), a), radius, radius, d.length(), 6, col, true)


func update(delta: float) -> void:
	var g: float = plane.gear_pos
	_spin = fmod(_spin + float(plane.wheel_spin_rate[0]) * delta, TAU)
	var hubs: Array = plane.AMPHIB_HUBS
	for i in range(4):
		var main := i < 2
		var sx: float = -plane.FLOAT_X if i % 2 == 0 else plane.FLOAT_X
		var w: Node3D = _wheels[i]
		if main:
			var hub: Vector3 = hubs[i]
			var comp: float = plane.wheel_comp[i]
			# Down: below the keel. Up: swung back and up into the float.
			w.position = Vector3(sx, lerpf(-1.70, hub.y + comp, g), lerpf(1.15, hub.z, g))
			w.rotation = Vector3(lerpf(-1.2, 0.0, g), 0, 0)
		else:
			var hubn: Vector3 = hubs[2]
			var compn: float = plane.wheel_comp[2]
			# Nose wheels flip up and back onto the deck.
			w.position = Vector3(sx, lerpf(-1.25, hubn.y + compn, g), lerpf(-2.55, hubn.z, g))
			w.rotation = Vector3(lerpf(-2.6, 0.0, g), (-plane.rudder * 0.3) * g, 0)
		w.get_child(0).rotation.x = -_spin
	# Water rudders: down and steering on the water, up in flight.
	var down: bool = plane.water_rudders and g < 0.5
	for rp in _rudders:
		rp.rotation = Vector3(0.0 if down else -1.3, plane.rudder * 0.5 if down else 0.0, 0)
