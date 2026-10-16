extends Node3D
## A main-street commercial building (DESIGN_NOTES 234, Silverton's Greene
## Street, reference/towns/silverton): one 25 ft (7.62 m) lot, 2 or 3
## storeys, brick (red, buff or dark) or a painted wood false front; the
## storefront - two big display windows on a low kick panel, a recessed door
## with a transom, cast-iron pilasters; tall narrow upper windows with stone
## or brick hoods; a bracketed cornice and a parapet; a wood canopy on posts
## over the boardwalk or a striped awning; the shop's painted sign. Flat tar
## roof behind the parapet. Built of pieces (front, sides, back, floors, roof)
## for structure.gd. Origin: the lot's front middle at the boardwalk, the
## street toward -Z. Lab: "commercial_block" (a row of variants).

const Kits = preload("res://scripts/assets/kits.gd")

const W := 7.62
const SIGNS := ["MERCANTILE", "HARDWARE", "CAFE", "BAR", "DRUG STORE", "HOTEL", "BAKERY", "ASSAY OFFICE", "LAUNDROMAT", "VIDEO RENTAL", "BANK",
	"BOOKS", "GROCERY", "SPORTING GOODS", "BARBER", "SALOON", "MINING SUPPLY", "GIFTS", "PHARMACY", "NEWS", "FIVE AND DIME", "GENERAL STORE", "CLOTHING", "TV REPAIR"]
const SKAGWAY := [Color(0.80, 0.42, 0.40), Color(0.93, 0.80, 0.42), Color(0.92, 0.88, 0.76), Color(0.42, 0.58, 0.46), Color(0.85, 0.55, 0.45), Color(0.62, 0.75, 0.80), Color(0.96, 0.94, 0.88)]
## weathered bare wood, dark brown to grey-brown (Dave's town pictures)
const OLD_WOOD := [Color(0.62, 0.48, 0.36), Color(0.55, 0.42, 0.32), Color(0.70, 0.58, 0.46), Color(0.50, 0.40, 0.33), Color(0.66, 0.60, 0.54)]
const PAINT := [Color(0.90, 0.86, 0.74), Color(0.30, 0.42, 0.33), Color(0.62, 0.20, 0.15), Color(0.78, 0.70, 0.50), Color(0.35, 0.40, 0.52), Color(0.92, 0.92, 0.90)]


func _ready() -> void:
	if get_child_count() > 0:
		return
	for v in range(6):
		var n: Node3D = make_variant(v)
		n.position = Vector3(float(v) * W, 0, 0)
		add_child(n)


static func make() -> Node3D:
	return make_variant(0)


## variants 200+i: the Skagway look (Dave's photo) with sign i - painted
## wooden false fronts, ornate trim, some with a balcony over the boardwalk.
static func make_variant(v: int) -> Node3D:
	var sk := v >= 200
	var sign_i := (v - 200) if sk else -1
	# 300+: the weathered look of Dave's town pictures (reference/towns/dave_town_*):
	# bare dark-brown plank false fronts, wood all round, rusty tin
	var old := v >= 300
	if old:
		sign_i = v - 300
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * v + 13
	var K := Kits.new()
	var storeys := 2 if rng.randf() < 0.7 else 3
	if v >= 300:
		storeys = 2 if rng.randf() < 0.55 else 1          # small-town: one or two storeys
	var g_h := 4.3                         # the storefront storey
	var u_h := 3.7
	var H := g_h + u_h * float(storeys - 1)
	var D := rng.randf_range(18.0, 26.0)
	var hw := W * 0.5
	var kind := rng.randi_range(0, 3)       # 0 red brick, 1 buff brick, 2 dark brick, 3 wood false front
	if sk:
		kind = 3 if rng.randf() < 0.8 else 0
	if old:
		kind = 3
	var wall_key: String = ["brick", "brick_buff", "brick_dark", "clapboard"][kind]
	if old:
		wall_key = "wood"
	var paint: Color = PAINT[rng.randi_range(0, PAINT.size() - 1)] if not sk else SKAGWAY[(sign_i * 3 + 1) % SKAGWAY.size()]
	var trim: Color = Color(0.92, 0.90, 0.84) if rng.randf() < 0.6 else Color(0.25, 0.30, 0.25)
	if old:
		paint = OLD_WOOD[(sign_i * 5 + 2) % OLD_WOOD.size()]
		trim = paint.darkened(0.35)
	var wall_col: Color = paint if kind == 3 else Color.WHITE
	var side_key := "wood" if old else ("brick" if kind != 2 else "brick_dark")
	var parapet := 1.0 if kind != 3 else rng.randf_range(1.5, 2.6)
	if old:
		parapet = rng.randf_range(2.6, 3.4)                # the false front hides the pitched roof        # a false front rises well above the roof
	# --- the side and back walls (brick party walls even on wood fronts), floors, roof
	K.piece("side_l", {"mat": "brick", "kind": "panel", "t": 0.3, "size": Vector2(D, H), "normal": Vector3(-1, 0, 0), "ground": true, "links": []})
	Kits.box(K.k(side_key), Vector3(-hw + 0.15, H * 0.5, D * 0.5), Vector3(0.3, H, D), paint if old else Color.WHITE)
	K.piece("side_r", {"mat": "brick", "kind": "panel", "t": 0.3, "size": Vector2(D, H), "normal": Vector3(1, 0, 0), "ground": true, "links": []})
	Kits.box(K.k(side_key), Vector3(hw - 0.15, H * 0.5, D * 0.5), Vector3(0.3, H, D), paint if old else Color.WHITE)
	K.piece("back", {"mat": "brick", "kind": "panel", "t": 0.3, "size": Vector2(W, H), "normal": Vector3(0, 0, 1), "ground": true, "links": ["side_l", "side_r"]})
	Kits.box(K.k("wood" if old else "brick"), Vector3(0, H * 0.5, D - 0.15), Vector3(W, H, 0.3), paint if old else Color.WHITE)
	K.k("glass_b")
	for f in range(storeys - 1):
		var fy := g_h + u_h * float(f)
		K.piece("floor_%d" % f, {"mat": "timber", "kind": "panel", "t": 0.3, "size": Vector2(W, D), "normal": Vector3.UP, "links": ["side_l", "side_r"]})
		Kits.box(K.k("boards"), Vector3(0, fy, D * 0.5), Vector3(W - 0.6, 0.3, D - 0.3), Color.WHITE)
	K.piece("roof", {"mat": "timber", "kind": "panel", "t": 0.3, "size": Vector2(W, D), "normal": Vector3.UP, "links": ["side_l", "side_r", "back"]})
	if old:
		# a pitched tin roof running back from behind the false front, a gable at the back
		var rise := hw * 0.65
		var rk := K.k("corr" if sign_i % 3 != 1 else "shingle")       # weathered grey tin, or old shingles
		for sd in [-1.0, 1.0]:
			var e0 := Vector3(sd * (hw + 0.35), H - 0.25, 0.4)
			var e1 := Vector3(sd * (hw + 0.35), H - 0.25, D + 0.4)
			var r0 := Vector3(0, H + rise, 0.4)
			var r1 := Vector3(0, H + rise, D + 0.4)
			rk.quad(e0, e1, r1, r0, Color(0.58, 0.56, 0.53), Vector3(sd * 0.65, 1, 0).normalized())
		K.k("wood").tri(Vector3(-hw, H, D), Vector3(hw, H, D), Vector3(0, H + rise, D), paint, Vector3(0, 0, 1))
	else:
		Kits.box(K.k("plain"), Vector3(0, H + 0.05, D * 0.5), Vector3(W - 0.3, 0.12, D - 0.3), Color(0.12, 0.12, 0.12))
	# --- the front: storefront below, the upper facade, cornice, parapet
	K.piece("front", {"mat": "timber" if kind == 3 else "brick", "kind": "panel", "t": 0.3, "size": Vector2(W, H + parapet), "normal": Vector3(0, 0, -1), "ground": true, "links": ["side_l", "side_r"]})
	var fk := K.k(wall_key)
	var z0 := 0.0
	# upper facade (full width, above the storefront), the parapet
	Kits.box(fk, Vector3(0, (g_h + H + parapet) * 0.5, z0 + 0.15), Vector3(W, H + parapet - g_h, 0.3), wall_col)
	# the storefront: pilasters at the ends and between, the kick panels, glass
	var trimk := K.k("paint_wood")
	var tk := trimk
	for px in [-hw + 0.2, hw - 0.2]:
		Kits.box(K.k("paint"), Vector3(px, g_h * 0.5, z0 + 0.1), Vector3(0.4, g_h, 0.35), trim.darkened(0.15))     # cast-iron pilasters
	var door_w := 1.1
	var recess := 1.2
	var door_x := rng.randf_range(-0.6, 0.6)
	var gl := K.k_mat("glass", load("res://scripts/assets/lookout_cab.gd")._glass())
	for side in [-1.0, 1.0]:
		var x0: float = -hw + 0.4 if side < 0.0 else door_x + door_w * 0.5 + 0.3
		var x1: float = door_x - door_w * 0.5 - 0.3 if side < 0.0 else hw - 0.4
		var cx := (x0 + x1) * 0.5
		var ww := x1 - x0
		if ww < 0.5:
			continue
		Kits.box(tk, Vector3(cx, 0.35, z0 + 0.2), Vector3(ww, 0.7, 0.2), trim)                # kick panel
		gl.box(Transform3D(Basis.IDENTITY, Vector3(cx, 0.7 + 1.45, z0 + 0.22)), Vector3(ww - 0.1, 2.9, 0.03), Color(0.10, 0.13, 0.15))
		Kits.box(tk, Vector3(cx, 0.7 + 2.95, z0 + 0.2), Vector3(ww, 0.12, 0.22), trim)       # head
		Kits.box(tk, Vector3(cx, 0.7, z0 + 0.2), Vector3(ww, 0.08, 0.24), trim)
		for m in range(2):
			Kits.box(tk, Vector3(lerpf(x0, x1, (float(m) + 1.0) / 3.0), 0.7 + 1.45, z0 + 0.23), Vector3(0.05, 2.9, 0.04), trim)
		# the transom band above the display window
		gl.box(Transform3D(Basis.IDENTITY, Vector3(cx, 3.95, z0 + 0.22)), Vector3(ww - 0.1, 0.55, 0.03), Color(0.2, 0.22, 0.2))
	# the recessed door: the angled side glass, the door, the transom
	Kits.box(tk, Vector3(door_x, g_h - 0.35, z0 + 0.2), Vector3(door_w + 0.6, 0.7, 0.2), trim)
	K.k("paint_wood").box(Transform3D(Basis.IDENTITY, Vector3(door_x, 1.15, z0 + recess)), Vector3(door_w, 2.3, 0.06), paint.darkened(0.3))
	gl.box(Transform3D(Basis.IDENTITY, Vector3(door_x, 1.4, z0 + recess - 0.035)), Vector3(door_w * 0.6, 1.2, 0.02), Color(0.10, 0.13, 0.15))
	Kits.box(K.k("boards"), Vector3(door_x, 0.02, z0 + recess * 0.5), Vector3(door_w + 0.3, 0.04, recess), Color.WHITE)
	# the storefront cornice (a sign band) with the shop's name painted on it
	Kits.box(tk, Vector3(0, g_h - 0.1, z0 + 0.05), Vector3(W, 0.55, 0.35), paint.darkened(0.1))
	var sign := Label3D.new()
	sign.text = SIGNS[(v * 7 + 3) % SIGNS.size()] if sign_i < 0 else SIGNS[sign_i % SIGNS.size()]
	sign.font_size = 96
	sign.pixel_size = 0.0042
	sign.modulate = Color(0.95, 0.92, 0.80) if paint.get_luminance() < 0.5 else Color(0.15, 0.12, 0.10)
	sign.position = Vector3(0, g_h - 0.1, z0 - 0.13)
	sign.rotation.y = PI
	sign.shaded = true
	# --- the upper windows: tall, two over two, with hoods and sills
	var nwin := 3 if W < 9.0 else 4
	for f2 in range(storeys - 1):
		var wy := g_h + u_h * float(f2) + 0.9
		for k in range(nwin):
			var wx := -hw + W * (float(k) + 0.5) / nwin
			gl.box(Transform3D(Basis.IDENTITY, Vector3(wx, wy + 1.05, z0 - 0.005)), Vector3(0.85, 2.1, 0.03), Color(0.10, 0.12, 0.14))
			Kits.box(tk, Vector3(wx, wy + 1.05, z0 - 0.015), Vector3(0.06, 2.1, 0.04), trim if old else Color.WHITE.darkened(0.1))
			Kits.box(tk, Vector3(wx, wy + 1.05, z0 - 0.015), Vector3(0.85, 0.06, 0.04), trim if old else Color.WHITE.darkened(0.1))
			Kits.box(K.k("cutstone" if kind != 3 else "paint_wood"), Vector3(wx, wy + 2.25, z0 - 0.05), Vector3(1.15, 0.3, 0.16), Color(0.85, 0.82, 0.76) if kind != 3 else trim)   # hood
			Kits.box(K.k("cutstone" if kind != 3 else "paint_wood"), Vector3(wx, wy - 0.05, z0 - 0.06), Vector3(1.05, 0.1, 0.18), Color(0.85, 0.82, 0.76) if kind != 3 else trim)   # sill
	# --- the cornice: a deep bracketed box at the top, the parapet cap
	var ctop := H + (0.0 if kind != 3 else parapet - 0.6)
	Kits.box(tk, Vector3(0, ctop + 0.35, z0 - 0.25), Vector3(W + 0.1, 0.5, 0.6), trim)
	for b in range(6):
		var bx := -hw + 0.3 + (W - 0.6) * float(b) / 5.0
		Kits.box(tk, Vector3(bx, ctop - 0.05, z0 - 0.15), Vector3(0.18, 0.45, 0.4), trim)
	if kind == 3:
		# the false front's stepped top
		Kits.box(fk, Vector3(0, H + parapet + 0.25, z0 + 0.15), Vector3(W * 0.5, 0.5, 0.3), wall_col)
	# --- the canopy over the boardwalk (wood on posts) or an awning
	K.piece("canopy", {"mat": "timber", "kind": "panel", "t": 0.05, "size": Vector2(W, 3.0), "normal": Vector3.UP, "links": ["front"]})
	if old or rng.randf() < 0.55:
		Kits.box(K.k("corr_rust" if old else "corr"), Vector3(0, 3.6, -1.5), Vector3(W, 0.06, 3.0), Color(0.75, 0.68, 0.62) if old else Color(0.7, 0.7, 0.7))
		for pz in [-hw + 0.25, hw - 0.25]:
			Kits.box(K.k("paint_wood"), Vector3(pz, 1.8, -2.85), Vector3(0.15, 3.6, 0.15), trim)
	else:
		var stripe: Color = [Color(0.62, 0.15, 0.12), Color(0.18, 0.35, 0.22), Color(0.2, 0.25, 0.45)][rng.randi_range(0, 2)]
		for st in range(8):
			var sx := -hw + W * (float(st) + 0.5) / 8.0
			K.k("plain").box(Transform3D(Basis(Vector3.RIGHT, -0.45), Vector3(sx, 3.45, -0.75)), Vector3(W / 8.0, 0.03, 1.7), stripe if st % 2 == 0 else Color(0.92, 0.9, 0.85))
	if sk and not old and storeys >= 2 and (sign_i == 5 or rng.randf() < 0.3):
		K.piece("balcony", {"mat": "timber", "kind": "panel", "t": 0.1, "size": Vector2(W - 1.0, 1.4), "normal": Vector3.UP, "links": ["front"]})
		var by := g_h + 0.1
		Kits.box(K.k("paint_wood"), Vector3(0, by, -0.75), Vector3(W - 1.0, 0.12, 1.5), trim)
		for bp in range(int(W / 0.25)):
			var bx2 := -hw + 0.6 + 0.25 * float(bp)
			if bx2 > hw - 0.6:
				break
			Kits.box(K.k("paint_wood"), Vector3(bx2, by + 0.5, -1.45), Vector3(0.06, 0.9, 0.06), trim)
		Kits.box(K.k("paint_wood"), Vector3(0, by + 0.98, -1.45), Vector3(W - 1.0, 0.08, 0.12), trim)
	var n := K.node("commercial_block")
	n.add_child(sign)
	if old and sign_i == 3:
		# the bar's neon (Dave's dusk picture): pink tube letters on a dark board over the canopy
		var nb := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(3.4, 1.0, 0.08)
		nb.mesh = bm
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.08, 0.07, 0.07)
		nb.material_override = dm
		nb.position = Vector3(0, g_h + 0.9, -0.12)
		n.add_child(nb)
		var neon := Label3D.new()
		neon.text = "BAR"
		neon.font_size = 128
		neon.pixel_size = 0.006
		neon.outline_size = 10
		neon.modulate = Color(2.2, 0.55, 1.6)          # over 1: it glows
		neon.outline_modulate = Color(0.9, 0.2, 0.7, 0.6)
		neon.shaded = false
		neon.position = Vector3(0, g_h + 0.9, -0.18)
		neon.rotation.y = PI
		n.add_child(neon)
	return n
