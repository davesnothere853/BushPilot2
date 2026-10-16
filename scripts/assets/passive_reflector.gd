extends Node3D
## Passive microwave reflector (DESIGN_NOTES 228): a flat steel "billboard",
## 12 x 9 m, on a ridge where a beam had to be bent round a mountain; no power,
## no building. Twelve flat galvanised panels on a steel frame, the A-legs
## behind on concrete footings, tilted a little. Flashes in the sun from miles.
## Base at the origin, face toward -Z. Lab: "passive_reflector".

const Kits = preload("res://scripts/assets/kits.gd")

const W := 12.0
const HH := 9.0
const LIFT := 2.5
const TILT := 0.12


func _ready() -> void:
	if get_child_count() == 0:
		add_child(make())


static func make() -> Node3D:
	var K := Kits.new()
	var g := K.k("galv")
	var face := Basis(Vector3.RIGHT, -TILT)
	var o := Vector3(0, LIFT, 0)
	var fp := func(u: float, v: float) -> Vector3: return o + face * Vector3(u, v, 0)
	# the panels (bright, smooth, metallic: its own material)
	var pm := ORMMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.metallic = 0.85
	pm.roughness = 0.22
	var pk := K.k_mat("panel", pm)
	for i in range(4):
		for j in range(3):
			var c: Vector3 = fp.call(-W * 0.5 + W * (float(i) + 0.5) / 4.0, HH * (float(j) + 0.5) / 3.0)
			pk.box(Transform3D(face, c), Vector3(W / 4.0 - 0.05, HH / 3.0 - 0.05, 0.06), Color(0.82, 0.84, 0.85))
	# the frame behind: horizontals, verticals
	for j2 in range(4):
		Kits.beam(g, fp.call(-W * 0.5, HH * float(j2) / 3.0) + face * Vector3(0, 0, 0.2), fp.call(W * 0.5, HH * float(j2) / 3.0) + face * Vector3(0, 0, 0.2), 0.16, Color.WHITE)
	for i2 in range(5):
		var u := -W * 0.5 + W * float(i2) / 4.0
		Kits.beam(g, fp.call(u, 0.0) + face * Vector3(0, 0, 0.3), fp.call(u, HH) + face * Vector3(0, 0, 0.3), 0.18, Color.WHITE)
		# the legs: front post down, the rake back
		var top: Vector3 = fp.call(u, 0.0) + face * Vector3(0, 0, 0.3)
		Kits.beam(g, Vector3(top.x, 0, top.z), top, 0.18, Color.WHITE)
		var hi: Vector3 = fp.call(u, HH * 0.75) + face * Vector3(0, 0, 0.3)
		var foot := Vector3(u, 0, 6.0)
		Kits.beam(g, foot, hi, 0.16, Color.WHITE)
		Kits.beam(g, Vector3(top.x, 0.3, top.z), foot + Vector3(0, 0.3, 0), 0.1, Color.WHITE)
		for f in [Vector3(top.x, 0, top.z), foot]:
			K.k("concrete").box(Transform3D(Basis.IDENTITY, f + Vector3(0, 0.15, 0)), Vector3(0.8, 0.6, 0.8), Color.WHITE)
	return K.node("passive_reflector")
