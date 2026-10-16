extends Node3D
## A mountain-town house (DESIGN_NOTES 234, Silverton's side streets,
## reference/towns/silverton): a narrow gable-front frame house of the 1880s-
## 1900s still lived in in the '80s - painted clapboard, white trim, tall two-
## over-two windows, a front porch on turned posts, a tin or shingle roof, a
## brick chimney, sometimes a side wing; a picket fence along the front of
## the lot with a gate, a woodshed and the old outhouse back by the alley.
## Built of pieces for structure.gd. Origin: the lot's front middle at the
## street, the street toward -Z; the lot runs back +Z. Lab: "house_victorian".

const Kits = preload("res://scripts/assets/kits.gd")

const PAINT := [Color(0.90, 0.88, 0.80), Color(0.55, 0.65, 0.58), Color(0.70, 0.30, 0.22), Color(0.85, 0.78, 0.55), Color(0.50, 0.58, 0.70),
	Color(0.92, 0.92, 0.90), Color(0.40, 0.48, 0.38), Color(0.78, 0.62, 0.62), Color(0.62, 0.55, 0.45)]
const LOT := Vector2(15.2, 38.0)        # two 25 ft lots wide, 125 ft deep


func _ready() -> void:
	if get_child_count() > 0:
		return
	for v in range(6):
		var n: Node3D = make_variant(v)
		n.position = Vector3(float(v) * LOT.x, 0, 0)
		add_child(n)


static func make() -> Node3D:
	return make_variant(0)


static func make_variant(v: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729 * v + 7
	var K := Kits.new()
	var w := rng.randf_range(6.0, 7.6)          # across the gable
	var d := rng.randf_range(9.0, 12.0)
	var storeys := 2 if rng.randf() < 0.55 else 1
	var wall_h := 2.9 * float(storeys) + (0.9 if storeys == 1 else 0.3)   # a storey and a half: the upstairs in the roof
	var pitch := rng.randf_range(0.85, 1.15)     # steep: snow
	var rise := w * 0.5 * pitch
	var paint: Color = PAINT[rng.randi_range(0, PAINT.size() - 1)]
	var trim := Color(0.94, 0.93, 0.88) if paint.get_luminance() < 0.75 else Color(0.30, 0.38, 0.32)
	var setback := rng.randf_range(4.5, 7.0)
	var ox := rng.randf_range(-2.0, 2.0)
	var c := Vector3(ox, 0.6, setback + d * 0.5)  # on a low stone foundation
	var hw := w * 0.5
	var hd := d * 0.5
	var tin := rng.randf() < 0.55
	# --- the foundation, walls (four pieces), floor
	K.piece("found", {"mat": "stone", "kind": "block", "ground": true, "links": []})
	Kits.box(K.k("cutstone"), Vector3(c.x, 0.3, c.z), Vector3(w + 0.1, 0.6, d + 0.1), Color(0.8, 0.78, 0.74))
	var gl := K.k_mat("glass", load("res://scripts/assets/lookout_cab.gd")._glass())
	for s in range(4):
		var yaw := PI * 0.5 * float(s)
		var b := Basis(Vector3.UP, yaw)
		var L := w if s % 2 == 0 else d
		var off := hd if s % 2 == 0 else hw
		var id: String = ["front", "left", "back", "right"][s]
		K.piece(id, {"mat": "timber", "kind": "panel", "t": 0.14, "size": Vector2(L, wall_h), "normal": b * Vector3(0, 0, -1), "links": ["found"]})
		var wk := K.k("clapboard")
		wk.box(Transform3D(b, c + b * Vector3(0, wall_h * 0.5, -off)), Vector3(L, wall_h, 0.14), paint)
		# corner boards
		Kits.box(K.k("paint_wood"), c + b * Vector3(L * 0.5 - 0.05, wall_h * 0.5, -off - 0.02), Vector3(0.14, wall_h, 0.16), trim, yaw)
		# windows: tall, two over two, trim round
		var nw := 2 if L < 8.0 else 3
		for f in range(storeys):
			for k in range(nw):
				var wx := -L * 0.5 + L * (float(k) + 0.5) / nw
				if s == 0 and f == 0 and k == 0:
					continue                                         # the door's there
				var wy := 0.9 + 2.9 * float(f)
				gl.box(Transform3D(b, c + b * Vector3(wx, wy + 0.8, -off - 0.075)), Vector3(0.8, 1.6, 0.03), Color(0.09, 0.11, 0.13))
				for tb in [[0.0, 1.62, 1.0, 0.1], [0.0, -0.02, 1.0, 0.08], [-0.45, 0.8, 0.1, 1.7], [0.45, 0.8, 0.1, 1.7], [0.0, 0.8, 0.8, 0.04]]:
					Kits.box(K.k("paint_wood"), c + b * Vector3(wx + float(tb[0]), wy + float(tb[1]), -off - 0.09), Vector3(float(tb[2]), float(tb[3]), 0.05), trim, yaw)
	# the gable ends (front and back triangles above the walls)
	for gz in [-hd, hd]:
		var gk := K.k("clapboard")
		var nrm := Vector3(0, 0, -1 if gz < 0.0 else 1)
		gk.tri(c + Vector3(-hw, wall_h, gz), c + Vector3(hw, wall_h, gz), c + Vector3(0, wall_h + rise, gz), paint, nrm)
		# a little window up in the front gable
		if gz < 0.0:
			gl.box(Transform3D(Basis.IDENTITY, c + Vector3(0, wall_h + rise * 0.35, gz - 0.02)), Vector3(0.6, 0.9, 0.03), Color(0.09, 0.11, 0.13))
	# --- the roof: steep, overhanging, tin (ribbed) or shingles; fascia trim
	K.piece("roof", {"mat": "steel_sheet" if tin else "timber", "kind": "panel", "t": 0.0005 if tin else 0.02, "size": Vector2(d + 0.8, sqrt(hw * hw + rise * rise) + 0.4), "normal": Vector3.UP, "links": ["front", "back", "left", "right"]})
	var rk := K.k("corr" if tin else "shingle")
	var rcol := Color(0.62, 0.63, 0.64) if tin else Color(0.55, 0.52, 0.50)
	if tin and rng.randf() < 0.4:
		rcol = Color(0.45, 0.20, 0.14)                    # painted red tin
	var ov := 0.4
	for side in [-1.0, 1.0]:
		var e0 := c + Vector3(side * (hw + ov), wall_h - ov * pitch, -hd - ov)
		var e1 := c + Vector3(side * (hw + ov), wall_h - ov * pitch, hd + ov)
		var r0 := c + Vector3(0, wall_h + rise + 0.05, -hd - ov)
		var r1 := c + Vector3(0, wall_h + rise + 0.05, hd + ov)
		rk.quad(e0, e1, r1, r0, rcol, Vector3(side * pitch, 1, 0).normalized())
		rk.quad(e0 + Vector3(0, -0.04, 0), r0 + Vector3(0, -0.04, 0), r1 + Vector3(0, -0.04, 0), e1 + Vector3(0, -0.04, 0), rcol.darkened(0.4), Vector3(-side * pitch, -1, 0).normalized())
		Kits.beam(K.k("paint_wood"), e0 + Vector3(0, 0, 0), r0, 0.12, trim)
	# the chimney (brick, through the ridge toward the back)
	K.piece("chimney", {"mat": "brick", "kind": "block", "links": ["roof"]})
	Kits.box(K.k("brick"), c + Vector3(rng.randf_range(-0.6, 0.6), wall_h + rise * 0.7, hd * 0.4), Vector3(0.6, rise * 1.0 + 0.8, 0.6), Color.WHITE)
	# --- the porch: floor, steps, turned posts, a shed roof
	var pd := 2.0
	var pw := w if rng.randf() < 0.6 else w * 0.6
	var px := c.x - (w - pw) * 0.5
	K.piece("porch", {"mat": "timber", "kind": "panel", "t": 0.05, "size": Vector2(pw, pd), "normal": Vector3.UP, "links": ["front"]})
	Kits.box(K.k("boards"), Vector3(px, 0.55, c.z - hd - pd * 0.5), Vector3(pw, 0.08, pd), Color.WHITE)
	for st in range(3):
		Kits.box(K.k("boards"), Vector3(c.x - hw + 0.9, 0.12 + 0.17 * float(st), c.z - hd - pd - 0.3 + 0.28 * float(st)), Vector3(1.3, 0.05, 0.3), Color.WHITE)
	var npost := 3 if pw > 5.0 else 2
	for p in range(npost):
		var ppx := px - pw * 0.5 + 0.12 + (pw - 0.24) * float(p) / float(npost - 1)
		Kits.box(K.k("paint_wood"), Vector3(ppx, 1.75, c.z - hd - pd + 0.1), Vector3(0.12, 2.4, 0.12), trim)
	K.k("corr" if tin else "shingle").box(Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(px, 3.05, c.z - hd - pd * 0.5)), Vector3(pw + 0.3, 0.05, pd + 0.4), rcol)
	# the door (in the front wall, by the steps), a railing
	K.k("paint_wood").box(Transform3D(Basis.IDENTITY, Vector3(c.x - hw + 0.9, 1.65, c.z - hd - 0.08)), Vector3(0.9, 2.1, 0.05), paint.darkened(0.35))
	Kits.box(K.k("paint_wood"), Vector3(px + 0.6, 1.4, c.z - hd - pd + 0.1), Vector3(pw - 1.8, 0.06, 0.06), trim)
	# --- the picket fence along the front of the lot, a gate; the shed and outhouse
	K.piece("fence", {"mat": "timber", "kind": "panel", "t": 0.02, "size": Vector2(LOT.x, 1.0), "normal": Vector3(0, 0, -1), "links": []})
	var fk := K.k("paint_wood")
	var fcol := Color(0.92, 0.91, 0.86) if rng.randf() < 0.7 else Color(0.45, 0.38, 0.30)
	var gate_x := c.x - hw + 0.9
	var nx := int(LOT.x / 0.12)
	for i in range(nx):
		var x := -LOT.x * 0.5 + 0.06 + 0.12 * float(i)
		if absf(x - gate_x) < 0.55:
			continue
		if i % 2 == 0:
			fk.box(Transform3D(Basis.IDENTITY, Vector3(x, 0.5, 0.3)), Vector3(0.07, 1.0, 0.02), fcol)
	for ry in [0.25, 0.8]:
		fk.box(Transform3D(Basis.IDENTITY, Vector3(0, ry, 0.32)), Vector3(LOT.x, 0.08, 0.03), fcol)
	if rng.randf() < 0.85:
		K.piece("shed", {"mat": "timber", "kind": "block", "ground": true, "links": []})
		var sx := rng.randf_range(-4.0, 4.0)
		Kits.box(K.k("boards"), Vector3(sx, 1.2, LOT.y - 3.0), Vector3(3.0, 2.4, 2.4), Color(0.85, 0.8, 0.74))
		K.k("corr_rust").box(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(sx, 2.55, LOT.y - 3.0)), Vector3(3.3, 0.04, 2.9), Color.WHITE)
	if rng.randf() < 0.6:
		K.piece("outhouse", {"mat": "timber", "kind": "block", "ground": true, "links": []})
		var ox2 := rng.randf_range(4.5, 6.5) * (1.0 if rng.randf() < 0.5 else -1.0)
		Kits.box(K.k("boards"), Vector3(ox2, 1.1, LOT.y - 1.5), Vector3(1.2, 2.2, 1.2), Color(0.8, 0.75, 0.68))
	return K.node("house_victorian")
