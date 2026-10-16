extends RefCounted
## The fire lookout cab (DESIGN_NOTES 228): the standard 14 x 14 ft (4.27 m)
## wood-frame cab of the western lookouts (the "L-4"): a wainscot of shiplap
## to the sill, windows all round (each side four sashes of six lights), the
## shutters hinged at the top and propped out on poles as awnings, a low hip
## roof, a lightning rod with its ball; the fire finder on its stand in the
## middle, the bed on glass-footed insulators, a table, the woodstove.
## Painted white, green trim and shutters (Forest Service colours, still the
## way in the '80s). Floor centre at the origin, front (door) toward -Z.

const Kits = preload("res://scripts/assets/kits.gd")

const W := 4.27
const WHITE := Color(0.90, 0.89, 0.84)
const GREEN := Color(0.20, 0.34, 0.24)
const ROOF := Color(0.30, 0.30, 0.30)


static func build(K: Kits, c: Vector3, catwalk: float) -> void:
	var hw := W * 0.5
	var pw := K.k("paint_wood")
	var wood := K.k("wood")
	var glass := K.k_mat("glass", _glass())
	# the floor (and the catwalk round it, planks)
	Kits.box(wood, c + Vector3(0, -0.06, 0), Vector3(W + catwalk * 2.0, 0.12, W + catwalk * 2.0), Color(0.75, 0.72, 0.66))
	for s in range(4):
		var yaw := PI * 0.5 * float(s)
		var b := Basis(Vector3.UP, yaw)
		# wainscot to the sill (1.0 m), the sill, the window band to 2.2 m, the plate
		pw.box(Transform3D(b, c + b * Vector3(0, 0.5, -hw)), Vector3(W, 1.0, 0.1), WHITE)
		pw.box(Transform3D(b, c + b * Vector3(0, 1.02, -hw - 0.04)), Vector3(W + 0.1, 0.05, 0.16), GREEN)
		pw.box(Transform3D(b, c + b * Vector3(0, 2.3, -hw)), Vector3(W, 0.2, 0.1), WHITE)
		# four sashes, each two lights wide and three high, mullions in green
		for m in range(4):
			var sx := -hw + W * (float(m) + 0.5) / 4.0
			glass.box(Transform3D(b, c + b * Vector3(sx, 1.62, -hw)), Vector3(W / 4.0 - 0.08, 1.16, 0.01), Color(0.16, 0.20, 0.22))
			pw.box(Transform3D(b, c + b * Vector3(sx - W / 8.0, 1.62, -hw - 0.02)), Vector3(0.07, 1.2, 0.06), GREEN)
			pw.box(Transform3D(b, c + b * Vector3(sx, 1.62, -hw - 0.02)), Vector3(0.025, 1.16, 0.03), GREEN)
			for r in [1.24, 1.62, 2.0]:
				pw.box(Transform3D(b, c + b * Vector3(sx, r, -hw - 0.02)), Vector3(W / 4.0 - 0.06, 0.025 if r == 1.62 else 0.05, 0.03), GREEN)
		pw.box(Transform3D(b, c + b * Vector3(hw, 1.62, -hw - 0.02)), Vector3(0.08, 1.2, 0.06), GREEN)
		# the shutter: boards on battens, hinged at the plate, propped out ~55 deg
		var hinge := c + b * Vector3(0, 2.38, -hw - 0.06)
		var sb := b * Basis(Vector3.RIGHT, 1.15)
		pw.box(Transform3D(sb, hinge + sb * Vector3(0, -0.62, -0.03)), Vector3(W + 0.2, 1.24, 0.04), GREEN)
		for bt in [-1.6, 0.0, 1.6]:
			pw.box(Transform3D(sb, hinge + sb * Vector3(bt, -0.62, 0.0)), Vector3(0.1, 1.2, 0.03), GREEN.darkened(0.15))
		var tip := hinge + sb * Vector3(0, -1.2, 0)
		for px in [-1.8, 1.8]:
			Kits.rod(wood, c + b * Vector3(px, 1.0, -hw - 0.08), tip + b * Vector3(px, 0, 0), 0.025, Color(0.6, 0.55, 0.45), 5)
	# the door in the front wainscot band (a ledge-and-brace door, a white knob)
	pw.box(Transform3D(Basis.IDENTITY, c + Vector3(1.2, 1.0, -hw - 0.055)), Vector3(0.82, 2.0, 0.04), WHITE.darkened(0.05))
	pw.box(Transform3D(Basis(Vector3.FORWARD, 0.9), c + Vector3(1.2, 1.0, -hw - 0.08)), Vector3(0.06, 1.1, 0.02), GREEN)
	# the hip roof: four slopes to the peak, a fascia, the lightning rod
	var eave := hw + 0.45
	var peak := c + Vector3(0, 3.45, 0)
	var rk := K.k("rust")
	for s2 in range(4):
		var b2 := Basis(Vector3.UP, PI * 0.5 * float(s2))
		var e0 := c + b2 * Vector3(-eave, 2.4, -eave)
		var e1 := c + b2 * Vector3(eave, 2.4, -eave)
		rk.tri(e0, e1, peak, ROOF, b2 * Vector3(0, 0.6, -1))
		rk.tri(e0, peak, e1, Color(0.55, 0.53, 0.5), b2 * Vector3(0, -0.6, 1))
		pw.box(Transform3D(b2, c + b2 * Vector3(0, 2.36, -eave)), Vector3(eave * 2.0, 0.12, 0.04), WHITE)
	var pl := K.k("plain")
	Kits.rod(pl, peak, peak + Vector3(0, 1.1, 0), 0.012, Color(0.72, 0.48, 0.25), 4)
	pl.cylinder(Transform3D(Basis.IDENTITY, peak + Vector3(0, 0.55, 0)), 0.07, 0.07, 0.12, 10, Color(0.15, 0.25, 0.55))
	# inside: the fire finder on its pedestal, the bed on its insulators, the stove
	Kits.box(wood, c + Vector3(0, 0.6, 0), Vector3(0.5, 1.2, 0.5), Color(0.6, 0.56, 0.48))
	pl.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, 1.2, 0)), 0.42, 0.42, 0.05, 20, Color(0.55, 0.45, 0.25))
	Kits.box(wood, c + Vector3(-1.3, 0.45, 1.4), Vector3(0.9, 0.12, 1.95), Color(0.5, 0.42, 0.32))
	Kits.box(K.k("plain"), c + Vector3(-1.3, 0.55, 1.4), Vector3(0.86, 0.1, 1.9), Color(0.45, 0.20, 0.15))
	for ix in [-0.4, 0.4]:
		for iz in [-0.9, 0.9]:
			glass.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(-1.3 + ix, 0, 1.4 + iz)), 0.05, 0.04, 0.1, 8, Color(0.3, 0.55, 0.45))
			Kits.rod(wood, c + Vector3(-1.3 + ix, 0.1, 1.4 + iz), c + Vector3(-1.3 + ix, 0.4, 1.4 + iz), 0.03, Color(0.5, 0.42, 0.32), 4)
	Kits.box(K.k("galv"), c + Vector3(1.4, 0.35, 1.4), Vector3(0.5, 0.7, 0.4), Color(0.18, 0.18, 0.18))
	Kits.rod(K.k("galv"), c + Vector3(1.4, 0.7, 1.4), c + Vector3(1.4, 3.6, 1.4), 0.07, Color(0.25, 0.25, 0.25), 8)
	if catwalk > 0.0:
		var cw := hw + catwalk
		var gk := K.k("galv")
		for s3 in range(4):
			var b3 := Basis(Vector3.UP, PI * 0.5 * float(s3))
			Kits.beam(gk, c + b3 * Vector3(-cw, 1.05, -cw), c + b3 * Vector3(cw, 1.05, -cw), 0.05, Color.WHITE)
			Kits.beam(gk, c + b3 * Vector3(-cw, 0.55, -cw), c + b3 * Vector3(cw, 0.55, -cw), 0.035, Color.WHITE)
			for pp in range(5):
				var q := c + b3 * Vector3(-cw + 2.0 * cw * float(pp) / 5.0, 0, -cw)
				Kits.beam(gk, q, q + Vector3(0, 1.05, 0), 0.05, Color.WHITE)


static var _gm: StandardMaterial3D


static func _glass() -> StandardMaterial3D:
	if _gm == null:
		_gm = StandardMaterial3D.new()
		_gm.vertex_color_use_as_albedo = true
		_gm.vertex_color_is_srgb = true
		_gm.roughness = 0.04
		_gm.metallic = 0.5
		_gm.metallic_specular = 1.0
	return _gm
