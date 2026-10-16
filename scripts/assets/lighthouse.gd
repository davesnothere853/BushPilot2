extends Node3D
## The harbor light (DESIGN_NOTES 228): an Alaskan light station of the 1930s
## kind - a square reinforced-concrete tower rising out of the corner of the
## keeper's building, white, the gallery with its pipe rail, the lantern
## (polygonal glazing, a red dome roof, the vent ball); the building flat-roofed
## concrete with tall windows, a boathouse ramp. Automated by the '80s, still
## flashing (white, every 6 s). Base at the origin, the sea toward -Z.
## Lab: "lighthouse".

const Kits = preload("res://scripts/assets/kits.gd")
const Glow = preload("res://scripts/assets/glow.gd")

const RED := Color(0.72, 0.13, 0.10)
const WHITE := Color(0.95, 0.95, 0.93)


func _ready() -> void:
	if get_child_count() == 0:
		add_child(make())


static func make() -> Node3D:
	var K := Kits.new()
	var c := K.k("concrete")
	var p := K.k("paint_conc")
	var pm := K.k("paint")
	# the keeper's building: 12 x 9, two storeys, a parapet, windows
	var b := Vector3(0, 0, 4.0)
	p.box(Transform3D(Basis.IDENTITY, b + Vector3(0, 3.3, 0)), Vector3(12.0, 6.6, 9.0), WHITE)
	p.box(Transform3D(Basis.IDENTITY, b + Vector3(0, 6.75, 0)), Vector3(12.3, 0.3, 9.3), WHITE.darkened(0.08))
	c.box(Transform3D(Basis.IDENTITY, b + Vector3(0, 0.3, 0)), Vector3(12.4, 0.6, 9.4), Color.WHITE)
	var gl := K.k_mat("glass", load("res://scripts/assets/lookout_cab.gd")._glass())
	for fl in [1.6, 4.6]:
		for i in range(4):
			var x := -4.5 + 3.0 * float(i)
			gl.box(Transform3D(Basis.IDENTITY, b + Vector3(x, fl, -4.52)), Vector3(1.0, 1.6, 0.04), Color(0.14, 0.17, 0.19))
			gl.box(Transform3D(Basis.IDENTITY, b + Vector3(x, fl, 4.52)), Vector3(1.0, 1.6, 0.04), Color(0.14, 0.17, 0.19))
			p.box(Transform3D(Basis.IDENTITY, b + Vector3(x, fl - 0.85, -4.56)), Vector3(1.2, 0.1, 0.1), RED)
		for j in range(2):
			gl.box(Transform3D(Basis.IDENTITY, b + Vector3(6.02, fl, -1.5 + 3.0 * float(j))), Vector3(0.04, 1.6, 1.0), Color(0.14, 0.17, 0.19))
	p.box(Transform3D(Basis.IDENTITY, b + Vector3(-6.03, 1.2, 1.5)), Vector3(0.05, 2.3, 1.1), RED)
	# the light on the roof (as at the 1930s Alaskan stations, HAER photos in
	# reference/landmarks/lighthouse): a short square concrete base in the
	# middle of the flat roof, a door in it, the lantern on top. The roof round
	# it is the helipad they painted when the lights were automated.
	var t := b + Vector3(0, 6.6, 0)
	var th := 3.4
	p.box(Transform3D(Basis.IDENTITY, t + Vector3(0, th * 0.5, 0)), Vector3(3.2, th, 3.2), WHITE)
	pm.box(Transform3D(Basis.IDENTITY, t + Vector3(0, 1.0, -1.62)), Vector3(0.8, 2.0, 0.04), Color(0.55, 0.42, 0.30))
	t.y -= 0.0
	th = th + 0.0
	# the helipad: a big painted H in a circle on the roof
	var hp := K.k("paint")
	for side in [-1.0, 1.0]:
		hp.box(Transform3D(Basis.IDENTITY, b + Vector3(side * 1.6 + 3.2, 6.92, 0)), Vector3(0.45, 0.01, 3.4), Color(0.95, 0.95, 0.9))
	hp.box(Transform3D(Basis.IDENTITY, b + Vector3(3.2, 6.92, 0)), Vector3(3.2, 0.01, 0.45), Color(0.95, 0.95, 0.9))
	# the gallery: a deck wider than the tower, the pipe rail
	p.box(Transform3D(Basis.IDENTITY, t + Vector3(0, th + 0.12, 0)), Vector3(5.0, 0.24, 5.0), WHITE.darkened(0.1))
	var g := K.k("galv")
	for s in range(4):
		var bb := Basis(Vector3.UP, PI * 0.5 * float(s))
		Kits.rod(g, t + bb * Vector3(-2.4, th + 1.2, -2.4), t + bb * Vector3(2.4, th + 1.2, -2.4), 0.03, Color(0.2, 0.2, 0.2), 6)
		for k2 in range(5):
			var q := t + bb * Vector3(-2.4 + 1.2 * float(k2), th + 0.24, -2.4)
			Kits.rod(g, q, q + Vector3(0, 0.96, 0), 0.025, Color(0.2, 0.2, 0.2), 5)
	# the lantern: a ten-sided glazed room on a short base, the lamp, the dome
	var lc := t + Vector3(0, th + 0.24, 0)
	# (the gallery deck above sits on the base)
	p.cylinder(Transform3D(Basis.IDENTITY, lc), 1.3, 1.3, 0.8, 10, RED)
	K.k_mat("lglass", load("res://scripts/tex.gd").clear(Color(0.75, 0.82, 0.85, 0.35), 0.05)).cylinder(Transform3D(Basis.IDENTITY, lc + Vector3(0, 0.8, 0)), 1.25, 1.25, 1.8, 10, Color.WHITE, false)
	for m in range(10):
		var a := TAU * float(m) / 10.0
		Kits.rod(pm, lc + Vector3(cos(a) * 1.27, 0.8, sin(a) * 1.27), lc + Vector3(cos(a) * 1.27, 2.6, sin(a) * 1.27), 0.035, RED, 4)
	K.k_mat("lamp", Glow.get_lamp()).cylinder(Transform3D(Basis.IDENTITY, lc + Vector3(0, 1.2, 0)), 0.4, 0.4, 0.9, 12, Color.WHITE)
	p.cylinder(Transform3D(Basis.IDENTITY, lc + Vector3(0, 2.6, 0)), 1.45, 0.25, 1.0, 16, RED)
	p.cylinder(Transform3D(Basis.IDENTITY, lc + Vector3(0, 3.6, 0)), 0.22, 0.22, 0.4, 10, RED.darkened(0.3))
	# the boat ramp down to the water, the derrick
	K.k("wood").box(Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(5.0, -1.2, -10.0)), Vector3(2.6, 0.2, 12.0), Color(0.8, 0.75, 0.7))
	Kits.rod(K.k("rust"), Vector3(3.5, 0, -4.5), Vector3(3.5, 7.0, -4.5), 0.12, Color.WHITE, 8)
	Kits.rod(K.k("rust"), Vector3(3.5, 1.0, -4.5), Vector3(5.0, 6.0, -9.0), 0.08, Color.WHITE, 6)
	return K.node("lighthouse")
