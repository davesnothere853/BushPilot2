extends Node3D
## A pole barn (DESIGN_NOTES 229, Dave: "think a pole barn with thin sheet
## steel and wood framing... drive my truck into or through it with realistic
## damage"). Built the way post-frame buildings are: 30 x 40 ft (9.14 x 12.19 m),
## 6x6 treated posts every 8 ft (2.44 m) set 4 ft in the ground, a 12 ft
## (3.66 m) eave; 2x6 girts flat on the posts every 24 in; a treated 2x8 skirt
## board; double 2x10 headers bolted to the posts carrying a truss on every
## post (4:12 pitch); 2x4 purlins on edge every 24 in; 29 ga ribbed steel
## panels (3 ft cover) screwed to girts and purlins; a 10 x 10 ft sliding door
## on the front gable end, a man door, a window.
## Every member is its own piece (Kits.piece) with its material and size and
## what it's fastened to, so structure.gd can break it, drop it, and bring
## down whatever it was holding. Base at the floor centre, the door toward -Z.
## Lab: "pole_barn".

const Kits = preload("res://scripts/assets/kits.gd")

const W := 9.14            # across the gable (x)
const L := 12.19           # along the side (z)
const EAVE := 3.66
const BAY := 2.438
const PITCH := 4.0 / 12.0
const POST := 0.14         # a 6x6 (5.5 in)
const GIRT := Vector2(0.038, 0.14)
const PURLIN := Vector2(0.038, 0.089)
const SHEET_T := 0.00036   # 29 ga
const RED := Color(0.55, 0.12, 0.09)        # barn red siding
const TRIM := Color(0.92, 0.92, 0.88)
const ROOF := Color(0.55, 0.56, 0.57)       # galvalume roof
const WOOD := Color(0.78, 0.68, 0.52)
const TREATED := Color(0.62, 0.62, 0.48)    # treated lumber's green-grey


func _ready() -> void:
	if get_child_count() == 0:
		add_child(make())


## A sheet of steel as a fine grid (so it can bend and wrap round what hits it,
## structure.gd dents it vertex by vertex): corners a b c d (a-b along the
## bottom), about 0.3 m squares.
static func _sheet(kit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, n: Vector3) -> void:
	var nu := maxi(int(ceil(a.distance_to(b) / 0.3)), 1)
	var nv := maxi(int(ceil(a.distance_to(d) / 0.3)), 1)
	for i in range(nu):
		for j in range(nv):
			var u0 := float(i) / nu
			var u1 := float(i + 1) / nu
			var v0 := float(j) / nv
			var v1 := float(j + 1) / nv
			var p00 := a.lerp(b, u0).lerp(d.lerp(c, u0), v0)
			var p10 := a.lerp(b, u1).lerp(d.lerp(c, u1), v0)
			var p11 := a.lerp(b, u1).lerp(d.lerp(c, u1), v1)
			var p01 := a.lerp(b, u0).lerp(d.lerp(c, u0), v1)
			kit.quad(p00, p10, p11, p01, col, n)


static func make() -> Node3D:
	var K := Kits.new()
	var hx := W * 0.5
	var hz := L * 0.5
	var nb := int(round(L / BAY))                 # 5 bays along
	var rise := hx * PITCH
	# --- posts: two rows of nb+1, and the end-wall posts between the corners
	var posts := {}
	for side in [-1, 1]:
		for i in range(nb + 1):
			var z := -hz + BAY * float(i)
			var id := "post_%s%d" % ["w" if side < 0 else "e", i]
			posts[id] = Vector3(side * (hx - POST * 0.5), 0, z)
	for e in [0, nb]:
		for k in [-1, 1]:
			var id2 := "post_%s%d" % ["f" if e == 0 else "b", 0 if k < 0 else 1]
			posts[id2] = Vector3(k * hx / 3.0, 0, -hz + BAY * float(e))
	for id in posts.keys():
		var p: Vector3 = posts[id]
		var top := EAVE if not String(id).begins_with("post_f") and not String(id).begins_with("post_b") else EAVE + rise * (1.0 - absf(p.x) / hx)
		K.piece(id, {"mat": "timber", "kind": "member", "a": p + Vector3(0, -1.2, 0), "b": p + Vector3(0, top, 0), "sec": Vector2(POST, POST), "ground": true, "links": [], "mkey": "timber", "col": TREATED})
		Kits.beam(K.k("timber"), p + Vector3(0, -0.2, 0), p + Vector3(0, top, 0), POST, TREATED)
	# --- side-wall girts (between posts, on the outside face) and the skirt board
	var girt_ys := [0.6, 1.2, 1.8, 2.4, 3.0, 3.5]
	for side2 in [-1, 1]:
		var s := "w" if side2 < 0 else "e"
		var fx: float = side2 * (hx + GIRT.x * 0.5)
		for i2 in range(nb):
			var z0 := -hz + BAY * float(i2)
			var z1 := z0 + BAY
			var pa := "post_%s%d" % [s, i2]
			var pb := "post_%s%d" % [s, i2 + 1]
			for gy in girt_ys:
				var gid := "girt_%s%d_%d" % [s, i2, int(gy * 10)]
				K.piece(gid, {"mat": "timber", "kind": "member", "a": Vector3(fx, gy, z0), "b": Vector3(fx, gy, z1), "sec": Vector2(GIRT.y, GIRT.x), "links": [pa, pb]})
				Kits.box(K.k("wood"), Vector3(fx, gy, (z0 + z1) * 0.5), Vector3(GIRT.x, GIRT.y, BAY + 0.02), WOOD)
			var sk := "skirt_%s%d" % [s, i2]
			K.piece(sk, {"mat": "timber", "kind": "member", "a": Vector3(fx, 0.1, z0), "b": Vector3(fx, 0.1, z1), "sec": Vector2(0.184, 0.038), "links": [pa, pb], "mkey": "timber", "col": TREATED})
			Kits.box(K.k("timber"), Vector3(fx, 0.1, (z0 + z1) * 0.5), Vector3(0.04, 0.184, BAY + 0.02), TREATED)
	# --- headers (double 2x10 both sides of the posts), trusses on every post
	for side3 in [-1, 1]:
		var s3 := "w" if side3 < 0 else "e"
		for i3 in range(nb):
			var z0b := -hz + BAY * float(i3)
			var hid := "header_%s%d" % [s3, i3]
			K.piece(hid, {"mat": "timber", "kind": "member", "a": Vector3(side3 * (hx - POST * 0.5), EAVE - 0.12, z0b), "b": Vector3(side3 * (hx - POST * 0.5), EAVE - 0.12, z0b + BAY),
				"sec": Vector2(0.076, 0.235), "beam": true, "w": 2600.0, "links": ["post_%s%d" % [s3, i3], "post_%s%d" % [s3, i3 + 1]]})
			for off in [-1.0, 1.0]:
				Kits.box(K.k("wood"), Vector3(side3 * (hx - POST * 0.5) + off * (POST * 0.5 + 0.02), EAVE - 0.12, z0b + BAY * 0.5), Vector3(0.038, 0.235, BAY + 0.1), WOOD)
	for i4 in range(nb + 1):
		var z := -hz + BAY * float(i4)
		var tid := "truss_%d" % i4
		var sup: Array = ["post_w%d" % i4, "post_e%d" % i4]
		# on the end walls the truss sits on the end posts too
		if i4 == 0:
			sup += ["post_f0", "post_f1"]
		if i4 == nb:
			sup += ["post_b0", "post_b1"]
		# headers either side carry it as well
		for s4 in ["w", "e"]:
			if i4 > 0:
				sup.append("header_%s%d" % [s4, i4 - 1])
			if i4 < nb:
				sup.append("header_%s%d" % [s4, i4])
		K.piece(tid, {"mat": "timber", "kind": "member", "a": Vector3(-hx - 0.3, EAVE, z), "b": Vector3(hx + 0.3, EAVE, z), "sec": Vector2(0.076, 0.6), "fill": 0.25, "beam": true, "w": 1300.0, "links": sup})
		var tk := K.k("wood")
		var apex := Vector3(0, EAVE + rise, z)
		var le := Vector3(-hx - 0.3, EAVE - 0.3 * PITCH, z)
		var re := Vector3(hx + 0.3, EAVE - 0.3 * PITCH, z)
		Kits.beam(tk, le, apex, 0.05, WOOD)
		Kits.beam(tk, re, apex, 0.05, WOOD)
		Kits.beam(tk, Vector3(-hx, EAVE, z), Vector3(hx, EAVE, z), 0.05, WOOD)
		# W webs
		for wx in [-hx * 0.5, hx * 0.5]:
			var top2 := Vector3(wx, EAVE + rise * (1.0 - absf(wx) / hx), z)
			Kits.beam(tk, Vector3(wx * 0.33, EAVE, z), top2, 0.035, WOOD)
			Kits.beam(tk, Vector3(wx * 1.6 if absf(wx * 1.6) < hx else wx, EAVE, z), top2, 0.035, WOOD)
		Kits.beam(tk, Vector3(-hx * 0.33 * 0.5, EAVE, z), apex, 0.035, WOOD)
		Kits.beam(tk, Vector3(hx * 0.33 * 0.5, EAVE, z), apex, 0.035, WOOD)
	# --- purlins on edge across the trusses, every 24 in up each slope
	var slope_len := sqrt(hx * hx + rise * rise) + 0.3
	var npur := int(slope_len / 0.61)
	for side5 in [-1, 1]:
		var s5 := "w" if side5 < 0 else "e"
		for k5 in range(npur + 1):
			var t := float(k5) / npur
			var x: float = side5 * (hx + 0.3) * (1.0 - t)
			var y := EAVE + rise * t - 0.3 * PITCH * (1.0 - t) + 0.07
			for i5 in range(nb):
				var pid := "purlin_%s%d_%d" % [s5, i5, k5]
				var za := -hz + BAY * float(i5) - (0.3 if i5 == 0 else 0.0)
				var zb := -hz + BAY * float(i5 + 1) + (0.3 if i5 == nb - 1 else 0.0)
				K.piece(pid, {"mat": "timber", "kind": "member", "a": Vector3(x, y, za), "b": Vector3(x, y, zb), "sec": Vector2(PURLIN.x, PURLIN.y), "links": ["truss_%d" % i5, "truss_%d" % (i5 + 1)]})
				Kits.box(K.k("wood"), Vector3(x, y, (za + zb) * 0.5), Vector3(PURLIN.x, PURLIN.y, zb - za), WOOD)
	# --- the steel: side panels (3 ft cover), each screwed to the girts it crosses
	var corr := K.k("corr")
	var pw := 0.914
	for side6 in [-1, 1]:
		var s6 := "w" if side6 < 0 else "e"
		var fx6: float = side6 * (hx + GIRT.x + 0.005)
		var np := int(ceil(L / pw))
		for k6 in range(np):
			var za6 := -hz + pw * float(k6)
			var zb6 := minf(za6 + pw, hz)
			var bay := clampi(int((za6 + zb6) * 0.5 + hz) / int(BAY * 1000) if false else int(((za6 + zb6) * 0.5 + hz) / BAY), 0, nb - 1)
			var links6: Array = []
			for gy2 in girt_ys:
				links6.append("girt_%s%d_%d" % [s6, bay, int(gy2 * 10)])
			links6.append("skirt_%s%d" % [s6, bay])
			var sid := "sheet_%s%d" % [s6, k6]
			K.piece(sid, {"mat": "steel_sheet", "kind": "panel", "t": SHEET_T, "size": Vector2(zb6 - za6, EAVE), "normal": Vector3(side6, 0, 0), "links": links6})
			var a := Vector3(fx6, 0.05, za6)
			var b := Vector3(fx6, 0.05, zb6)
			_sheet(K.k("corr"), a, b, b + Vector3(0, EAVE - 0.05, 0), a + Vector3(0, EAVE - 0.05, 0), RED, Vector3(side6, 0, 0))
	# the roof steel: panels running down each slope, screwed to the purlins
	for side7 in [-1, 1]:
		var s7 := "w" if side7 < 0 else "e"
		var np7 := int(ceil((L + 0.6) / pw))
		for k7 in range(np7):
			var za7 := -hz - 0.3 + pw * float(k7)
			var zb7 := minf(za7 + pw, hz + 0.3)
			var bay7 := clampi(int(((za7 + zb7) * 0.5 + hz) / BAY), 0, nb - 1)
			var links7: Array = []
			for k5b in range(npur + 1):
				links7.append("purlin_%s%d_%d" % [s7, bay7, k5b])
			var rid := "roof_%s%d" % [s7, k7]
			var nrm := Vector3(side7 * PITCH, 1, 0).normalized()
			K.piece(rid, {"mat": "steel_sheet", "kind": "panel", "t": SHEET_T, "size": Vector2(zb7 - za7, slope_len), "normal": nrm, "links": links7})
			var eave_x: float = side7 * (hx + 0.35)
			var ey := EAVE - 0.35 * PITCH + 0.13
			var ry := EAVE + rise + 0.13
			_sheet(K.k("corr"), Vector3(eave_x, ey, za7), Vector3(eave_x, ey, zb7), Vector3(0, ry, zb7), Vector3(0, ry, za7), ROOF, nrm)
	# the gable ends: end-wall girts between the end posts, the steel, the door
	for e2 in [0, 1]:
		var z2 := -hz - GIRT.x if e2 == 0 else hz + GIRT.x
		var face := -1.0 if e2 == 0 else 1.0
		var tag := "f" if e2 == 0 else "b"
		var xs := [-hx, -hx / 3.0, hx / 3.0, hx]
		var pids := ["post_w%d" % (0 if e2 == 0 else nb), "post_%s0" % tag, "post_%s1" % tag, "post_e%d" % (0 if e2 == 0 else nb)]
		for g2 in range(3):
			if e2 == 0 and g2 == 1:
				continue          # the big door bay: no girts across it
			for gy3 in girt_ys:
				var gid2 := "egirt_%s%d_%d" % [tag, g2, int(gy3 * 10)]
				K.piece(gid2, {"mat": "timber", "kind": "member", "a": Vector3(xs[g2], gy3, z2), "b": Vector3(xs[g2 + 1], gy3, z2), "sec": Vector2(GIRT.y, GIRT.x), "links": [pids[g2], pids[g2 + 1]]})
				Kits.box(K.k("wood"), Vector3((xs[g2] + xs[g2 + 1]) * 0.5, gy3, z2), Vector3(xs[g2 + 1] - xs[g2], GIRT.y, GIRT.x), WOOD)
		# end-wall steel, panel by panel up to the rake
		var npe := int(ceil(W / pw))
		for k8 in range(npe):
			var xa := -hx + pw * float(k8)
			var xb := minf(xa + pw, hx)
			var xm := (xa + xb) * 0.5
			var bottom := 0.05
			if e2 == 0 and absf(xm) < 1.55:
				bottom = 3.25         # over the door opening (10 ft): steel from the door header up to the rake
			var g3 := 0 if xm < -hx / 3.0 else (2 if xm > hx / 3.0 else 1)
			var links8: Array = ["door_header"] if bottom > 1.0 else []
			for gy4 in girt_ys:
				links8.append("egirt_%s%d_%d" % [tag, g3, int(gy4 * 10)])
			var eid := "endsheet_%s%d" % [tag, k8]
			var ha := EAVE + rise * (1.0 - absf(xa) / hx)
			var hb := EAVE + rise * (1.0 - absf(xb) / hx)
			K.piece(eid, {"mat": "steel_sheet", "kind": "panel", "t": SHEET_T, "size": Vector2(xb - xa, (ha + hb) * 0.5), "normal": Vector3(0, 0, face), "links": links8})
			var zz := z2 + face * 0.02
			_sheet(K.k("corr"), Vector3(xa, bottom, zz), Vector3(xb, bottom, zz), Vector3(xb, hb, zz), Vector3(xa, ha, zz), RED, Vector3(0, 0, face))
	# the door header: a double 2x12 across the opening between the door posts
	K.piece("door_header", {"mat": "timber", "kind": "member", "a": Vector3(-hx / 3.0, 3.2, -hz - GIRT.x), "b": Vector3(hx / 3.0, 3.2, -hz - GIRT.x), "sec": Vector2(0.076, 0.286), "beam": true, "w": 900.0, "links": ["post_f0", "post_f1"]})
	Kits.box(K.k("wood"), Vector3(0, 3.2, -hz - GIRT.x), Vector3(W / 3.0 * 2.0, 0.286, 0.076), WOOD)
	# the sliding door (on its track)
	K.piece("door", {"mat": "steel_sheet", "kind": "panel", "t": SHEET_T * 2.0, "size": Vector2(3.05, 3.05), "normal": Vector3(0, 0, -1), "links": ["post_f0", "post_f1"]})
	K.k("corr").box(Transform3D(Basis.IDENTITY, Vector3(0.6, 1.55, -hz - 0.12)), Vector3(3.05, 3.05, 0.04), RED.darkened(0.08))
	for dx in [-0.9, 0.6, 2.1]:
		Kits.box(K.k("paint"), Vector3(dx, 1.55, -hz - 0.145), Vector3(0.1, 3.0, 0.01), TRIM)
	Kits.box(K.k("paint"), Vector3(0.6, 1.55, -hz - 0.145), Vector3(3.0, 0.1, 0.01), TRIM)
	K.piece("")
	Kits.box(K.k("galv"), Vector3(0.5, 3.18, -hz - 0.1), Vector3(6.4, 0.1, 0.08), Color(0.5, 0.5, 0.5))      # the track
	# trim: corners, eaves, ridge cap
	for cx in [-hx, hx]:
		for cz in [-hz, hz]:
			Kits.box(K.k("paint"), Vector3(cx, EAVE * 0.5, cz), Vector3(0.12, EAVE, 0.12), TRIM)
	Kits.box(K.k("paint"), Vector3(0, EAVE + rise + 0.16, 0), Vector3(0.3, 0.06, L + 0.7), TRIM)
	# the floor: gravel inside
	K.k("gravel").quad(Vector3(-hx, 0.01, -hz), Vector3(hx, 0.01, -hz), Vector3(hx, 0.01, hz), Vector3(-hx, 0.01, hz), Color(0.75, 0.72, 0.68), Vector3.UP)
	return K.node("pole_barn")
