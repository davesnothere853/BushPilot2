extends RefCounted
## Polyart models for the buildings you can put up (DESIGN_NOTES 78):
##   - log buildings: saddle-notched round logs with chinking, log gables,
##     purlin and ridge logs poking out, a metal roof, windows, a porch;
##   - steel pole barns: wood posts, ribbed steel siding with a wainscot,
##     trim, trusses, a galvalume roof, big sliding doors you can drive a
##     machine through, and an open-front pole shed.
## Every model sits on the ground at its origin with its door on -Z.

const MeshKit = preload("res://scripts/meshkit.gd")

const LOG_R := 0.16
const LOG_H := 0.28        # rise per course (logs overlap a little)
const LOG_EXT := 0.38      # how far the log ends stick out past the corners


# ==============================================================================
#  Log buildings
# ==============================================================================
## w along X (front/back walls), d along Z (gable walls). Ridge runs along X,
## so the roof slopes down to the front (porch) and the back.
## openings: {"front"|"back"|"left"|"right": [[centre, width, row_from, row_to], ...]}
static func log_building(kit, w: float, d: float, rows: int, porch: float, openings: Dictionary, seed_v: int, chimney: bool) -> Dictionary:
	var solids: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var log_a := Color(0.47, 0.33, 0.20)
	var log_b := Color(0.38, 0.26, 0.16)
	var chink := Color(0.80, 0.76, 0.66)
	var end_c := Color(0.66, 0.52, 0.34)
	var trim := Color(0.30, 0.20, 0.12)
	var base := 0.16
	var eave := base + float(rows) * LOG_H
	var pitch := 0.75                       # rise per run (9/12)
	var rise := d * 0.5 * pitch
	# Sill on a few stone piers, and the floor.
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.box_at(Vector3(sx * (w * 0.5 - 0.2), 0.05, sz * (d * 0.5 - 0.2)), Vector3(0.5, 0.22, 0.5), Color(0.45, 0.45, 0.43))
	kit.box_at(Vector3(0, 0.07, 0), Vector3(w - 0.1, 0.1, d - 0.1), Color(0.52, 0.40, 0.26))
	for i in range(int(w / 0.3)):
		kit.box_at(Vector3(-w * 0.5 + 0.15 + float(i) * 0.3, 0.121, 0), Vector3(0.012, 0.004, d - 0.2), Color(0.40, 0.30, 0.19))
	# Courses. Front/back logs on whole rows, gable-wall logs half a row up.
	for row in range(rows):
		for wall in ["front", "back", "left", "right"]:
			var along_x: bool = wall == "front" or wall == "back"
			var y := base + float(row) * LOG_H + (0.0 if along_x else LOG_H * 0.5)
			if not along_x and row == rows - 1:
				continue
			var span := (w if along_x else d) * 0.5
			var off := (d if along_x else w) * 0.5
			var sgn := -1.0 if (wall == "front" or wall == "left") else 1.0
			var segs := _cut([-span - LOG_EXT, span + LOG_EXT], openings.get(wall, []), row)
			for sg in segs:
				var a: float = sg[0]
				var b: float = sg[1]
				if b - a < 0.15:
					continue
				var c := log_a.lerp(log_b, rng.randf())
				var mid := (a + b) * 0.5
				var ctr := Vector3(mid, y, sgn * off) if along_x else Vector3(sgn * off, y, mid)
				_log(kit, ctr, along_x, b - a, LOG_R * rng.randf_range(0.94, 1.06), c, end_c)
				# chinking between this course and the one under it
				if row > 0 or not along_x:
					var cl := minf(b, span) - maxf(a, -span)
					var cm := (minf(b, span) + maxf(a, -span)) * 0.5
					if cl > 0.05:
						var cc := Vector3(cm, y - LOG_H * 0.5, sgn * off) if along_x else Vector3(sgn * off, y - LOG_H * 0.5, cm)
						kit.box_at(cc, Vector3(cl, LOG_H * 0.55, 0.24) if along_x else Vector3(0.24, LOG_H * 0.55, cl), chink)
	# Log gables on the left and right walls, shortening up to the ridge.
	var k := 0
	while true:
		var gy := float(k) * LOG_H + LOG_H * 0.5
		if gy > rise - 0.12:
			break
		var half := (d * 0.5) * (1.0 - gy / rise) + 0.05
		for sx in [-1.0, 1.0]:
			var c2 := log_a.lerp(log_b, rng.randf())
			_log(kit, Vector3(sx * w * 0.5, eave + gy - LOG_H * 0.5, 0), false, half * 2.0, LOG_R, c2, end_c)
			kit.box_at(Vector3(sx * w * 0.5, eave + gy - LOG_H, 0), Vector3(0.24, LOG_H * 0.55, half * 2.0), chink)
		k += 1
	# Ridge log and two purlins each side, sticking out past the gables.
	var over := 0.55
	_log(kit, Vector3(0, eave + rise - 0.14, 0), true, w + over * 2.0 + 0.3, 0.17, log_b, end_c)
	for f in [0.36, 0.7]:
		for sz in [-1.0, 1.0]:
			_log(kit, Vector3(0, eave + rise * (1.0 - f) - 0.16, sz * d * 0.5 * f), true, w + over * 2.0 + 0.2, 0.13, log_a, end_c)
	# Metal roof (forest green), with ribs down the slope and a ridge cap.
	var roof_c := Color(0.20, 0.33, 0.24)
	var rib_c := Color(0.16, 0.27, 0.20)
	var eave_over := 0.6
	var slope_len := sqrt(pow(d * 0.5 + eave_over, 2.0) + pow((d * 0.5 + eave_over) * pitch, 2.0))
	var ang := atan(pitch)
	for sz in [-1.0, 1.0]:
		var rb := Basis(Vector3.RIGHT, sz * ang)
		var ctr2 := Vector3(0, eave + rise - (d * 0.5 + eave_over) * pitch * 0.5 + 0.06, sz * (d * 0.5 + eave_over) * 0.5)
		kit.box(Transform3D(rb, ctr2), Vector3(w + over * 2.0, 0.05, slope_len), roof_c)
		var nr := int((w + over * 2.0) / 0.4)
		for i in range(nr + 1):
			var x := -(w * 0.5 + over) + float(i) * (w + over * 2.0) / float(nr)
			kit.box(Transform3D(rb, ctr2 + rb.y * 0.035 + Vector3(x - ctr2.x, 0, 0)), Vector3(0.04, 0.03, slope_len), rib_c)
		# fascia board along the eave
		kit.box_at(Vector3(0, eave - (eave_over) * pitch + 0.0, sz * (d * 0.5 + eave_over)), Vector3(w + over * 2.0, 0.18, 0.05), trim)
	kit.box_at(Vector3(0, eave + rise + 0.09, 0), Vector3(w + over * 2.0, 0.07, 0.36), rib_c)
	# Porch on the front: deck, log posts, rails, and a shed roof.
	if porch > 0.0:
		var deck := Color(0.55, 0.42, 0.27)
		var pz := -d * 0.5 - porch * 0.5
		kit.box_at(Vector3(0, 0.08, pz), Vector3(w + 0.4, 0.12, porch), deck)
		for i in range(int(w / 0.18)):
			kit.box_at(Vector3(-w * 0.5 - 0.1 + 0.09 + float(i) * 0.18, 0.141, pz), Vector3(0.01, 0.004, porch - 0.05), Color(0.42, 0.31, 0.19))
		var post_h := 2.3
		var posts := [-w * 0.5 + 0.1, -1.0, 1.0, w * 0.5 - 0.1] if w > 6.0 else [-w * 0.5 + 0.1, w * 0.5 - 0.1]
		for px in posts:
			kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(px, 0.14, -d * 0.5 - porch + 0.15)), 0.12, 0.11, post_h, 7, log_a)
		# rails either side of the steps
		for side in [-1.0, 1.0]:
			var x0: float = 0.75 * side
			var x1: float = (w * 0.5 - 0.1) * side
			solids.append([Vector3((x0 + x1) * 0.5, 0, -d * 0.5 - porch + 0.15), Vector3(absf(x1 - x0) + 0.25, 1.05, 0.25)])
			solids.append([Vector3(x1, 0, -d * 0.5 - porch * 0.5 + 0.05), Vector3(0.25, 1.05, porch)])
			for ry in [0.55, 0.95]:
				_log(kit, Vector3((x0 + x1) * 0.5, ry, -d * 0.5 - porch + 0.15), true, absf(x1 - x0), 0.05, log_a, end_c)
			for ry2 in [0.55, 0.95]:
				_log(kit, Vector3(side * (w * 0.5 - 0.1), ry2, -d * 0.5 - porch * 0.5 + 0.05), false, porch - 0.25, 0.05, log_a, end_c)
		# beam on the posts, then the porch roof down from under the main eave
		_log(kit, Vector3(0, post_h + 0.2, -d * 0.5 - porch + 0.15), true, w + 0.6, 0.13, log_b, end_c)
		var top_y := eave - 0.1
		var low_y := post_h + 0.3
		var run := porch + 0.45
		var plen := sqrt(run * run + pow(top_y - low_y, 2.0))
		var pang := atan2(top_y - low_y, run)
		var pb := Basis(Vector3.RIGHT, -pang)
		var pc := Vector3(0, (top_y + low_y) * 0.5 + 0.04, -d * 0.5 - run * 0.5 + 0.1)
		kit.box(Transform3D(pb, pc), Vector3(w + 0.8, 0.05, plen), roof_c)
		var nr2 := int((w + 0.8) / 0.4)
		for i in range(nr2 + 1):
			var x2 := -(w * 0.5 + 0.4) + float(i) * (w + 0.8) / float(nr2)
			kit.box(Transform3D(pb, pc + pb.y * 0.035 + Vector3(x2, 0, 0)), Vector3(0.04, 0.03, plen), rib_c)
		# steps
		kit.box_at(Vector3(0, 0.04, -d * 0.5 - porch - 0.2), Vector3(1.3, 0.08, 0.35), deck.darkened(0.1))
	# Door and window frames, glass, a door standing open.
	for wall in openings.keys():
		for op in openings[wall]:
			_frame(kit, wall, w, d, base, op, trim)
	# A stone chimney up the right gable, or a stove pipe.
	if chimney:
		var stone := [Color(0.50, 0.49, 0.46), Color(0.42, 0.41, 0.39), Color(0.58, 0.56, 0.52)]
		var cx := w * 0.5 + 0.55
		var ch := eave + rise + 0.9
		var y2 := 0.0
		var lay := 0
		while y2 < ch:
			var wide := 1.3 if y2 < eave * 0.7 else 0.8
			var hh := rng.randf_range(0.22, 0.32)
			for j in range(3):
				var sw := wide / 3.0
				kit.box_at(Vector3(cx + rng.randf_range(-0.03, 0.03), y2 + hh * 0.5, -wide * 0.5 + sw * (float(j) + 0.5) + (0.08 if lay % 2 == 1 else 0.0) - 0.04),
					Vector3(0.75 if y2 < eave * 0.7 else 0.6, hh - 0.02, sw - 0.03), stone[rng.randi() % 3])
			y2 += hh
			lay += 1
		kit.box_at(Vector3(cx, ch + 0.05, 0), Vector3(0.7, 0.1, 0.9), Color(0.35, 0.34, 0.32))
		solids.append([Vector3(cx, 0, 0), Vector3(0.8, ch, 1.4)])
	return {"eave": eave, "ridge": eave + rise, "solids": solids}


## One round log along X (or Z), centred at c, with pale sawn ends.
static func _log(kit, c: Vector3, along_x: bool, length: float, r: float, col: Color, end_c: Color) -> void:
	var b := Basis(Vector3.FORWARD, PI * 0.5) if along_x else Basis(Vector3.RIGHT, PI * 0.5)
	var xf := Transform3D(b, c) * Transform3D(Basis.IDENTITY, Vector3(0, -length * 0.5, 0))
	kit.cylinder(xf, r, r, length, 7, col, false)
	for e in [0.0, length]:
		var ex := Transform3D(b, c) * Transform3D(Basis.IDENTITY, Vector3(0, -length * 0.5 + e + (-0.005 if e == 0.0 else 0.005), 0))
		kit.cylinder(ex, r * 0.96, r * 0.96, 0.0001, 7, end_c, true)


## Split [a, b] around the openings that cut this course.
static func _cut(span: Array, ops: Array, row: int) -> Array:
	var segs: Array = [span]
	for op in ops:
		if row < int(op[2]) or row > int(op[3]):
			continue
		var lo: float = float(op[0]) - float(op[1]) * 0.5
		var hi: float = float(op[0]) + float(op[1]) * 0.5
		var nxt: Array = []
		for s in segs:
			if hi <= s[0] or lo >= s[1]:
				nxt.append(s)
				continue
			if lo > s[0]:
				nxt.append([s[0], lo])
			if hi < s[1]:
				nxt.append([hi, s[1]])
		segs = nxt
	return segs


static func _frame(kit, wall: String, w: float, d: float, base: float, op: Array, trim: Color) -> void:
	var along_x: bool = wall == "front" or wall == "back"
	var sgn := -1.0 if (wall == "front" or wall == "left") else 1.0
	var off := (d if along_x else w) * 0.5
	var y0 := base + float(op[2]) * LOG_H - LOG_H * 0.5 + (0.0 if along_x else LOG_H * 0.5)
	var y1 := base + float(op[3]) * LOG_H + LOG_H * 0.5 + (0.0 if along_x else LOG_H * 0.5)
	if int(op[2]) == 0:
		y0 = 0.12
	var c: float = op[0]
	var wd: float = op[1]
	var is_door: bool = int(op[2]) == 0
	var t := 0.09
	var th := 0.36
	var pts := []
	# jambs, head and sill
	for s in [-1.0, 1.0]:
		pts.append([c + s * (wd * 0.5 - t * 0.5), (y0 + y1) * 0.5, t, y1 - y0])
	pts.append([c, y1 - t * 0.5, wd, t])
	if not is_door:
		pts.append([c, y0 + t * 0.5, wd + 0.12, t])
	for p in pts:
		var ctr := Vector3(p[0], p[1], sgn * off) if along_x else Vector3(sgn * off, p[1], p[0])
		kit.box_at(ctr, Vector3(p[2], p[3], th) if along_x else Vector3(th, p[3], p[2]), trim)
	if is_door:
		# plank door swung open inside, against the wall
		var hinge := c - wd * 0.5 + t
		var dw := wd - t * 2.0
		var dz := sgn * off - sgn * (dw * 0.5 + 0.2)
		var dc := Vector3(hinge + 0.04, (y0 + y1 - t) * 0.5, dz) if along_x else Vector3(sgn * off - sgn * (dw * 0.5 + 0.2), (y0 + y1 - t) * 0.5, hinge + 0.04)
		kit.box_at(dc, Vector3(0.05, y1 - y0 - t - 0.02, dw) if along_x else Vector3(dw, y1 - y0 - t - 0.02, 0.05), Color(0.36, 0.25, 0.15))
	else:
		var glass := Color(0.22, 0.30, 0.36)
		var gc := Vector3(c, (y0 + y1) * 0.5, sgn * off) if along_x else Vector3(sgn * off, (y0 + y1) * 0.5, c)
		kit.box_at(gc, Vector3(wd - t, y1 - y0 - t, 0.03) if along_x else Vector3(0.03, y1 - y0 - t, wd - t), glass)
		# muntins: a cross
		kit.box_at(gc, Vector3(0.04, y1 - y0 - t, 0.06) if along_x else Vector3(0.06, y1 - y0 - t, 0.04), trim)
		kit.box_at(gc, Vector3(wd - t, 0.04, 0.06) if along_x else Vector3(0.06, 0.04, wd - t), trim)


## Where the wood stove stands in a w x d log building (back right corner,
## on its hearth), and the top of its pipe out through the roof.
static func stove_spot(w: float, d: float) -> Vector3:
	return Vector3(w * 0.5 - 0.95, 0.0, d * 0.5 - 0.95)


## The top of the stove pipe, 0.9 m clear of the roof where it comes through
## (the roof pitches 9/12 down from the ridge to the back eave).
static func pipe_top(w: float, d: float, eave: float) -> Vector3:
	var s := stove_spot(w, d) + Vector3(0.12, 0, 0.18)
	return Vector3(s.x, eave + (d * 0.5 - s.z) * 0.75 + 0.95, s.z)


## A box wood stove (DESIGN_NOTES 147): a steel firebox on legs, standing on
## a stone hearth with a sheet-steel heat shield on the wall behind; a door
## with a little window and a latch, an ash lip, a kettle on the top, the
## pipe with its damper up through the roof and a rain cap on top, and the
## wood box beside it. `top` is the pipe's top (stove-local, the stove
## standing at the origin facing -Z).
static func wood_stove(kit, at: Vector3, top_y: float, wood: bool = true) -> void:
	var iron := Color(0.10, 0.10, 0.10)
	var iron2 := Color(0.17, 0.17, 0.17)
	var stone := [Color(0.52, 0.50, 0.47), Color(0.44, 0.42, 0.40), Color(0.60, 0.57, 0.53)]
	# hearth: flat stones
	for i in range(4):
		for j in range(4):
			kit.box_at(at + Vector3(-0.55 + 0.37 * float(i), 0.13, -0.55 + 0.37 * float(j)), Vector3(0.35, 0.04, 0.35), stone[(i * 3 + j * 5) % 3])
	# heat shield on the wall behind, stood off on spacers
	kit.box_at(at + Vector3(0, 1.0, 0.62), Vector3(1.2, 1.6, 0.02), Color(0.62, 0.63, 0.64))
	for sx in [-0.5, 0.5]:
		for sy in [0.3, 1.7]:
			kit.box_at(at + Vector3(sx, sy, 0.6), Vector3(0.04, 0.04, 0.04), iron2)
	# firebox and legs
	var fb := at + Vector3(0, 0.55, 0.0)
	kit.box_at(fb, Vector3(0.62, 0.52, 0.78), iron)
	kit.box_at(fb + Vector3(0, 0.28, 0), Vector3(0.66, 0.04, 0.82), iron2)
	for lx in [-0.26, 0.26]:
		for lz in [-0.34, 0.34]:
			kit.box_at(at + Vector3(lx, 0.22, lz), Vector3(0.05, 0.2, 0.05), iron)
	# door on the front, its window, hinges and latch; the ash lip
	kit.box_at(fb + Vector3(0, -0.02, -0.4), Vector3(0.44, 0.36, 0.03), iron2)
	kit.box_at(fb + Vector3(0, 0.02, -0.418), Vector3(0.26, 0.14, 0.01), Color(0.30, 0.12, 0.05))
	kit.box_at(fb + Vector3(0.24, -0.02, -0.43), Vector3(0.03, 0.08, 0.03), Color(0.55, 0.55, 0.5))
	for hy in [-0.12, 0.1]:
		kit.box_at(fb + Vector3(-0.23, hy, -0.42), Vector3(0.03, 0.05, 0.03), iron2)
	kit.box_at(fb + Vector3(0, -0.27, -0.44), Vector3(0.5, 0.03, 0.1), iron2)
	# kettle on the top
	kit.cylinder(Transform3D(Basis.IDENTITY, fb + Vector3(-0.15, 0.3, -0.15)), 0.11, 0.08, 0.14, 8, Color(0.42, 0.40, 0.36))
	kit.box_at(fb + Vector3(-0.15, 0.5, -0.15), Vector3(0.14, 0.015, 0.015), Color(0.2, 0.2, 0.2))
	kit.box(Transform3D(Basis(Vector3.FORWARD, 0.7), fb + Vector3(-0.03, 0.38, -0.15)), Vector3(0.12, 0.02, 0.02), Color(0.42, 0.40, 0.36))
	# the pipe, its damper handle, and the rain cap above the roof
	var py := fb.y + 0.3
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(at.x + 0.12, py, at.z + 0.18)), 0.08, 0.08, top_y - py, 8, iron)
	kit.box_at(Vector3(at.x + 0.12, py + 0.55, at.z + 0.08), Vector3(0.03, 0.03, 0.12), Color(0.5, 0.5, 0.48))
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(at.x + 0.12, top_y + 0.06, at.z + 0.18)), 0.17, 0.0, 0.12, 8, iron)
	for k in range(3):
		var a := TAU * float(k) / 3.0
		kit.box_at(Vector3(at.x + 0.12 + cos(a) * 0.08, top_y + 0.03, at.z + 0.18 + sin(a) * 0.08), Vector3(0.015, 0.08, 0.015), iron)
	if wood:
		# the wood box beside it, full of split wood
		var wb := at + Vector3(-0.85, 0.0, 0.1)
		var bx := Color(0.42, 0.30, 0.18)
		kit.box_at(wb + Vector3(0, 0.3, 0.27), Vector3(0.7, 0.6, 0.04), bx)
		kit.box_at(wb + Vector3(0, 0.3, -0.27), Vector3(0.7, 0.6, 0.04), bx)
		kit.box_at(wb + Vector3(0.33, 0.3, 0), Vector3(0.04, 0.6, 0.5), bx)
		kit.box_at(wb + Vector3(-0.33, 0.3, 0), Vector3(0.04, 0.6, 0.5), bx)
		kit.box_at(wb + Vector3(0, 0.05, 0), Vector3(0.66, 0.04, 0.5), bx)
		split_wood(kit, wb + Vector3(0, 0.1, 0), 0.62, 0.42, 3, 5, 17)


## Split firewood stacked in rows: `len` along X, `deep` along Z, `rows` high.
static func split_wood(kit, at: Vector3, len: float, deep: float, rows: int, per: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bark := [Color(0.36, 0.30, 0.24), Color(0.44, 0.38, 0.30), Color(0.30, 0.25, 0.20)]
	var face := [Color(0.80, 0.66, 0.45), Color(0.74, 0.60, 0.40), Color(0.84, 0.72, 0.52)]
	var dia := len / float(per)
	for r in range(rows):
		for i in range(per):
			var c := at + Vector3(-len * 0.5 + dia * (float(i) + 0.5) + (dia * 0.5 if r % 2 == 1 else 0.0) * 0.0, dia * 0.42 + dia * 0.84 * float(r), 0)
			if c.x > at.x + len * 0.5:
				continue
			var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, rng.randf() * TAU), c + Vector3(0, 0, -deep * 0.5))
			# a split round: three-sided, pale split faces, bark on the round
			kit.cylinder(xf, dia * 0.5, dia * 0.48, deep * rng.randf_range(0.9, 1.0), 3, bark[rng.randi() % 3], false)
			kit.cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.002, 0)), dia * 0.45, dia * 0.45, 0.001, 3, face[rng.randi() % 3], true)


## A stacked woodpile outside: split wood between end posts under a strip of
## steel roofing, on two skids.
static func woodpile(kit, at: Vector3, yaw: float, len: float, seed: int) -> Array:
	var sub := MeshKit.new()
	var post := Color(0.40, 0.31, 0.21)
	for sx in [-1.0, 1.0]:
		sub.box_at(Vector3(sx * (len * 0.5 + 0.06), 0.7, 0), Vector3(0.1, 1.4, 0.1), post)
		sub.box_at(Vector3(sx * (len * 0.5 + 0.06), 0.06, 0), Vector3(0.12, 0.12, 0.7), post.darkened(0.2))
	sub.box_at(Vector3(0, 0.06, -0.22), Vector3(len + 0.3, 0.1, 0.1), post.darkened(0.2))
	sub.box_at(Vector3(0, 0.06, 0.22), Vector3(len + 0.3, 0.1, 0.1), post.darkened(0.2))
	split_wood(sub, Vector3(0, 0.1, 0), len, 0.42, 7, int(len / 0.17), seed)
	sub.box(Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 1.48, 0)), Vector3(len + 0.5, 0.03, 0.75), Color(0.55, 0.57, 0.58))
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	_merge_xf(kit, sub, xf)
	return [[at, Vector3(len + 0.3, 1.5, 0.6), yaw]]


## A plank outhouse with a shed roof, a vent moon cut in the door.
static func outhouse(kit, at: Vector3, yaw: float) -> Array:
	var sub := MeshKit.new()
	var plank := [Color(0.50, 0.38, 0.25), Color(0.44, 0.33, 0.21), Color(0.55, 0.42, 0.28)]
	for i in range(7):
		var x := -0.6 + 0.2 * float(i) + 0.1
		sub.box_at(Vector3(x, 1.05, 0.6), Vector3(0.19, 2.1, 0.03), plank[i % 3])
		sub.box_at(Vector3(x, 1.0, -0.6), Vector3(0.19, 2.0, 0.03), plank[(i + 1) % 3])
	for sx in [-0.6, 0.6]:
		for i in range(6):
			var z := -0.5 + 0.2 * float(i) + 0.0
			sub.box_at(Vector3(sx, 1.02, z), Vector3(0.03, 2.05, 0.19), plank[(i + 2) % 3])
	# door: battens, Z brace, the moon, a handle
	var dc := Color(0.42, 0.31, 0.20)
	sub.box_at(Vector3(0, 0.95, -0.63), Vector3(0.75, 1.75, 0.03), dc)
	for y in [0.25, 1.6]:
		sub.box_at(Vector3(0, y, -0.655), Vector3(0.7, 0.1, 0.02), dc.darkened(0.15))
	sub.box(Transform3D(Basis(Vector3.FORWARD, -1.05), Vector3(0, 0.93, -0.655)), Vector3(0.1, 1.5, 0.02), dc.darkened(0.15))
	sub.box_at(Vector3(0, 1.72, -0.66), Vector3(0.12, 0.12, 0.02), Color(0.05, 0.05, 0.05))
	sub.box_at(Vector3(0.28, 1.0, -0.67), Vector3(0.03, 0.1, 0.03), Color(0.3, 0.3, 0.3))
	# shed roof, steel
	sub.box(Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, 2.13, 0)), Vector3(1.5, 0.03, 1.6), Color(0.56, 0.58, 0.59))
	for i in range(5):
		sub.box(Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(-0.6 + 0.3 * float(i), 2.155, 0)), Vector3(0.03, 0.025, 1.6), Color(0.48, 0.50, 0.51))
	_merge_xf(kit, sub, Transform3D(Basis(Vector3.UP, yaw), at))
	return [[at, Vector3(1.3, 2.2, 1.3), yaw]]


## A log cache on four poles, the poles wrapped in tin to stop martens and
## bears climbing them, a ladder leaning against it.
static func cache(kit, at: Vector3, yaw: float) -> Array:
	var sub := MeshKit.new()
	var log_c := Color(0.45, 0.34, 0.22)
	var end_c := Color(0.66, 0.52, 0.34)
	var tin := Color(0.72, 0.74, 0.75)
	for sx in [-0.85, 0.85]:
		for sz in [-0.85, 0.85]:
			sub.cylinder(Transform3D(Basis.IDENTITY, Vector3(sx, -0.3, sz)), 0.13, 0.11, 3.3, 7, log_c, false)
			sub.cylinder(Transform3D(Basis.IDENTITY, Vector3(sx, 1.6, sz)), 0.145, 0.14, 0.8, 7, tin, false)
	# deck and a little log house on it
	sub.box_at(Vector3(0, 3.05, 0), Vector3(2.3, 0.12, 2.3), log_c.darkened(0.1))
	for r in range(5):
		var y := 3.2 + 0.24 * float(r)
		for sz in [-0.8, 0.8]:
			_log(sub, Vector3(0, y, sz), true, 2.0, 0.11, log_c.lerp(log_c.darkened(0.2), float(r % 2)), end_c)
		for sx in [-0.8, 0.8]:
			_log(sub, Vector3(sx, y + 0.12, 0), false, 2.0, 0.11, log_c, end_c)
	sub.box_at(Vector3(0, 3.75, -0.86), Vector3(0.6, 0.8, 0.04), Color(0.38, 0.27, 0.17))
	for sz in [-1.0, 1.0]:
		sub.box(Transform3D(Basis(Vector3.RIGHT, sz * 0.62), Vector3(0, 4.62, sz * 0.62)), Vector3(2.3, 0.04, 1.55), Color(0.56, 0.58, 0.59))
	for sx in [-0.8, 0.8]:
		sub.tri(Vector3(sx, 4.3, -0.8), Vector3(sx, 4.3, 0.8), Vector3(sx, 5.1, 0), log_c.darkened(0.1), Vector3(sx, 0, 0))
	# the ladder, leaning on the front
	for sx in [-0.22, 0.22]:
		sub.box(Transform3D(Basis(Vector3.RIGHT, -0.28), Vector3(sx, 1.55, -1.85)), Vector3(0.07, 3.3, 0.07), log_c.lightened(0.1))
	for i in range(8):
		var t := (float(i) + 0.5) / 8.0
		sub.box_at(Vector3(0, 0.1 + t * 3.0, -2.3 + t * 0.9), Vector3(0.5, 0.05, 0.05), log_c.lightened(0.1))
	_merge_xf(kit, sub, Transform3D(Basis(Vector3.UP, yaw), at))
	return [[at, Vector3(2.0, 3.0, 2.0), yaw]]


## Fuel drums: n of them standing, colours cycling.
static func drums(kit, at: Vector3, yaw: float, n: int, seed: int) -> Array:
	var sub := MeshKit.new()
	var cols := [Color(0.62, 0.14, 0.10), Color(0.16, 0.30, 0.52), Color(0.22, 0.34, 0.22), Color(0.72, 0.62, 0.20)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(n):
		var p := Vector3(float(i % 3) * 0.62 - 0.62, 0, float(i / 3) * 0.62)
		var c: Color = cols[(i + seed) % 4]
		if rng.randf() < 0.25 and i == n - 1:
			# one on its side
			sub.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), p + Vector3(0.45, 0.29, 0.9)), 0.29, 0.29, 0.88, 10, c)
			continue
		sub.cylinder(Transform3D(Basis.IDENTITY, p), 0.29, 0.29, 0.88, 10, c)
		for ry in [0.29, 0.59]:
			sub.cylinder(Transform3D(Basis.IDENTITY, p + Vector3(0, ry, 0)), 0.30, 0.30, 0.025, 10, c.darkened(0.25), false)
		sub.cylinder(Transform3D(Basis.IDENTITY, p + Vector3(0.12, 0.88, 0.08)), 0.03, 0.03, 0.02, 6, Color(0.6, 0.6, 0.6))
	_merge_xf(kit, sub, Transform3D(Basis(Vector3.UP, yaw), at))
	return [[at + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.3), Vector3(2.0, 0.9, 1.4), yaw]]


## A chopping block with the axe stuck in it, chips round it.
static func chopping_block(kit, at: Vector3) -> void:
	kit.cylinder(Transform3D(Basis.IDENTITY, at), 0.3, 0.28, 0.5, 9, Color(0.42, 0.33, 0.22))
	kit.cylinder(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.5, 0)), 0.27, 0.27, 0.001, 9, Color(0.76, 0.62, 0.42))
	kit.box(Transform3D(Basis(Vector3.FORWARD, 0.5), at + Vector3(0.18, 0.78, 0)), Vector3(0.04, 0.7, 0.04), Color(0.62, 0.48, 0.30))
	kit.box(Transform3D(Basis(Vector3.FORWARD, 0.5), at + Vector3(0.02, 0.52, 0)), Vector3(0.16, 0.1, 0.03), Color(0.25, 0.25, 0.27))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x * 13.0 + at.z * 7.0)
	for i in range(12):
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.35, 1.1)
		kit.box(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at + Vector3(cos(a) * r, 0.01, sin(a) * r)), Vector3(0.12, 0.015, 0.05), Color(0.78, 0.64, 0.44))


## A propane tank on its pad.
static func propane(kit, at: Vector3, yaw: float) -> Array:
	var sub := MeshKit.new()
	sub.box_at(Vector3(0, 0.05, 0), Vector3(1.9, 0.1, 0.9), Color(0.55, 0.55, 0.53))
	for sx in [-0.5, 0.5]:
		sub.box_at(Vector3(sx, 0.25, 0), Vector3(0.12, 0.3, 0.55), Color(0.85, 0.85, 0.83))
	sub.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.75, 0.68, 0)), 0.38, 0.38, 1.5, 12, Color(0.90, 0.90, 0.88))
	for e in [-0.78, 0.78]:
		sub.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5 * signf(e)), Vector3(e, 0.68, 0)), 0.38, 0.0, 0.16, 12, Color(0.90, 0.90, 0.88), false)
	sub.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)), 0.14, 0.14, 0.16, 8, Color(0.85, 0.85, 0.83), false)
	sub.box_at(Vector3(0, 1.17, 0), Vector3(0.3, 0.03, 0.3), Color(0.85, 0.85, 0.83))
	_merge_xf(kit, sub, Transform3D(Basis(Vector3.UP, yaw), at))
	return [[at, Vector3(1.9, 1.1, 0.9), yaw]]


## Transformed copy of another kit's triangles.
static func _merge_xf(kit, sub, xf: Transform3D) -> void:
	for i in range(sub.verts.size()):
		kit.verts.append(xf * sub.verts[i])
		kit.norms.append((xf.basis * sub.norms[i]).normalized())
		kit.cols.append(sub.cols[i])


## Inside a log cabin (DESIGN_NOTES 147): the wood stove on its hearth in the
## back corner with the wood box, a kitchen counter with a wash basin, water
## jug and shelves of cans and jars, a table and two chairs with a lantern on
## it, a bunk with a wool blanket, coat hooks with a jacket and a rifle over
## the door, a braided rug. `office`: the home base office instead - a desk
## with the radio and the log book, a chart of the area on the wall, a filing
## cabinet, a couch, the first-aid kit and an extinguisher.
static func cabin_furniture(kit, w: float, d: float, eave: float, ridge: float, stove_pipe: bool, office: bool = false) -> Array:
	var wood := Color(0.50, 0.37, 0.23)
	var dark := Color(0.36, 0.26, 0.16)
	var solids: Array = []
	var st := stove_spot(w, d)
	wood_stove(kit, st, pipe_top(w, d, eave).y)
	solids.append([st, Vector3(0.8, 1.0, 1.0)])
	solids.append([st + Vector3(-0.85, 0, 0.1), Vector3(0.75, 0.65, 0.55)])
	# braided rug in the middle of the floor
	for r in range(4):
		var rc: Color = [Color(0.55, 0.20, 0.15), Color(0.30, 0.36, 0.50), Color(0.70, 0.62, 0.45), Color(0.32, 0.40, 0.28)][r]
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.125 + 0.001 * float(r), -0.2)), 1.2 - 0.25 * float(r), 1.2 - 0.25 * float(r), 0.004, 14, rc, true)
	if not office:
		# table, two chairs, a lantern and a mug on it
		var tx := -w * 0.5 + 1.25
		kit.box_at(Vector3(tx, 0.76, 0.0), Vector3(0.9, 0.06, 1.4), wood)
		for lx in [-0.35, 0.35]:
			for lz in [-0.6, 0.6]:
				kit.box_at(Vector3(tx + lx, 0.4, lz), Vector3(0.07, 0.7, 0.07), dark)
		for cz in [-0.95, 0.95]:
			_chair(kit, Vector3(tx, 0, cz), 0.0 if cz < 0 else PI, wood)
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(tx + 0.1, 0.79, 0.3)), 0.05, 0.05, 0.1, 8, Color(0.30, 0.42, 0.55))
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(tx - 0.15, 0.79, -0.2)), 0.07, 0.06, 0.04, 8, Color(0.6, 0.12, 0.08))
		kit.box_at(Vector3(tx - 0.15, 0.89, -0.2), Vector3(0.08, 0.16, 0.08), Color(0.85, 0.80, 0.6))
		solids.append([Vector3(tx, 0, 0.0), Vector3(1.0, 0.8, 2.2)])
		# bunk along the back wall: frame, mattress, wool blanket with stripes, pillow
		var bx := -0.7
		var bz := d * 0.5 - 0.6
		kit.box_at(Vector3(bx, 0.42, bz), Vector3(2.0, 0.1, 0.85), wood)
		for lx2 in [-0.95, 0.95]:
			kit.box_at(Vector3(bx + lx2, 0.3, bz), Vector3(0.08, 0.6, 0.85), dark)
		kit.box_at(Vector3(bx, 0.53, bz), Vector3(1.9, 0.12, 0.78), Color(0.80, 0.77, 0.70))
		kit.box_at(Vector3(bx + 0.15, 0.6, bz - 0.02), Vector3(1.55, 0.04, 0.82), Color(0.55, 0.20, 0.16))
		for sx2 in [-0.45, 0.6]:
			kit.box_at(Vector3(bx + sx2, 0.625, bz - 0.02), Vector3(0.12, 0.012, 0.83), Color(0.12, 0.12, 0.12))
		kit.box_at(Vector3(bx - 0.78, 0.65, bz), Vector3(0.32, 0.1, 0.55), Color(0.88, 0.86, 0.80))
		solids.append([Vector3(bx, 0, bz), Vector3(2.0, 0.65, 0.9)])
	else:
		# the desk under the front window: the HF radio, a mic, the log book, a mug
		var dx := -w * 0.5 + 1.6
		var dz := -d * 0.5 + 0.6
		kit.box_at(Vector3(dx, 0.76, dz), Vector3(1.8, 0.05, 0.7), wood)
		for lx3 in [-0.85, 0.85]:
			kit.box_at(Vector3(dx + lx3, 0.38, dz), Vector3(0.05, 0.76, 0.62), dark)
		kit.box_at(Vector3(dx + 0.55, 0.4, dz), Vector3(0.5, 0.7, 0.6), dark.lightened(0.05))
		for k in range(3):
			kit.box_at(Vector3(dx + 0.55, 0.2 + 0.22 * float(k), dz - 0.31), Vector3(0.12, 0.02, 0.02), Color(0.7, 0.7, 0.65))
		kit.box_at(Vector3(dx - 0.45, 0.9, dz + 0.15), Vector3(0.5, 0.22, 0.32), Color(0.20, 0.21, 0.22))
		kit.box_at(Vector3(dx - 0.45, 0.93, dz - 0.015), Vector3(0.36, 0.08, 0.01), Color(0.15, 0.30, 0.18))
		for k2 in range(4):
			kit.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(dx - 0.6 + 0.1 * float(k2), 0.84, dz - 0.01)), 0.015, 0.015, 0.02, 6, Color(0.7, 0.7, 0.7))
		kit.box_at(Vector3(dx - 0.1, 0.8, dz - 0.05), Vector3(0.07, 0.04, 0.1), Color(0.1, 0.1, 0.1))
		kit.box_at(Vector3(dx + 0.15, 0.795, dz - 0.05), Vector3(0.32, 0.03, 0.24), Color(0.25, 0.30, 0.42))
		kit.box_at(Vector3(dx + 0.15, 0.812, dz - 0.05), Vector3(0.3, 0.005, 0.22), Color(0.92, 0.90, 0.84))
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(dx + 0.55, 0.785, dz + 0.1)), 0.045, 0.045, 0.1, 8, Color(0.85, 0.85, 0.82))
		_chair(kit, Vector3(dx, 0, dz + 0.7), PI, wood)
		solids.append([Vector3(dx, 0, dz), Vector3(1.85, 0.8, 0.75)])
		# the chart of the area pinned up on the side wall, and a notice board
		var cx := -w * 0.5 + 0.2
		kit.box_at(Vector3(cx, 1.6, 0.15), Vector3(0.02, 1.0, 1.2), Color(0.86, 0.84, 0.74))
		var rngm := RandomNumberGenerator.new()
		rngm.seed = 5
		for k3 in range(14):
			var mc: Color = [Color(0.55, 0.68, 0.45), Color(0.62, 0.72, 0.52), Color(0.50, 0.62, 0.78), Color(0.78, 0.70, 0.52)][rngm.randi() % 4]
			kit.box_at(Vector3(cx + 0.012, 1.6 + rngm.randf_range(-0.4, 0.4), 0.15 + rngm.randf_range(-0.5, 0.5)), Vector3(0.005, rngm.randf_range(0.08, 0.3), rngm.randf_range(0.1, 0.4)), mc)
		kit.box_at(Vector3(cx + 0.02, 1.6, 0.15), Vector3(0.004, 0.012, 1.0), Color(0.70, 0.15, 0.55))
		var nb := d * 0.5 - 0.2
		kit.box_at(Vector3(-0.8, 1.65, nb), Vector3(0.9, 0.7, 0.03), Color(0.62, 0.48, 0.32))
		for k4 in range(5):
			kit.box_at(Vector3(-1.1 + 0.15 * float(k4), 1.6 + 0.18 * float(k4 % 3) - 0.1, nb - 0.02), Vector3(0.13, 0.2, 0.005), Color(0.95, 0.94, 0.88))
		# filing cabinet, couch, first aid box, extinguisher
		kit.box_at(Vector3(w * 0.5 - 0.5, 0.65, -d * 0.5 + 0.55), Vector3(0.5, 1.3, 0.6), Color(0.40, 0.44, 0.40))
		for k5 in range(3):
			kit.box_at(Vector3(w * 0.5 - 0.5, 0.3 + 0.4 * float(k5), -d * 0.5 + 0.24), Vector3(0.14, 0.03, 0.02), Color(0.75, 0.75, 0.72))
		solids.append([Vector3(w * 0.5 - 0.5, 0, -d * 0.5 + 0.55), Vector3(0.55, 1.3, 0.65)])
		var cz2 := d * 0.5 - 0.55
		var sofa := Color(0.36, 0.30, 0.22)
		kit.box_at(Vector3(-0.8, 0.3, cz2), Vector3(2.0, 0.3, 0.8), sofa)
		kit.box_at(Vector3(-0.8, 0.65, cz2 + 0.32), Vector3(2.0, 0.6, 0.16), sofa)
		for sx3 in [-1.0, 1.0]:
			kit.box_at(Vector3(-0.8 + sx3 * 0.95, 0.5, cz2), Vector3(0.14, 0.4, 0.8), sofa.darkened(0.1))
		kit.box_at(Vector3(-1.2, 0.5, cz2 - 0.05), Vector3(0.75, 0.1, 0.65), sofa.lightened(0.06))
		kit.box_at(Vector3(-0.4, 0.5, cz2 - 0.05), Vector3(0.75, 0.1, 0.65), sofa.lightened(0.06))
		solids.append([Vector3(-0.8, 0, cz2), Vector3(2.1, 0.7, 0.9)])
		kit.box_at(Vector3(w * 0.5 - 0.2, 1.5, -0.6), Vector3(0.1, 0.3, 0.4), Color(0.9, 0.9, 0.88))
		kit.box_at(Vector3(w * 0.5 - 0.26, 1.5, -0.6), Vector3(0.01, 0.12, 0.04), Color(0.75, 0.1, 0.1))
		kit.box_at(Vector3(w * 0.5 - 0.26, 1.5, -0.6), Vector3(0.01, 0.04, 0.12), Color(0.75, 0.1, 0.1))
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 + 0.35, 0.15, -d * 0.5 + 1.3)), 0.08, 0.08, 0.5, 8, Color(0.78, 0.08, 0.06))
	# kitchen counter on the right wall: a basin, a water jug, shelves of cans and jars
	var kx := w * 0.5 - 0.4
	var kz := 0.0 if not office else 0.6
	kit.box_at(Vector3(kx, 0.45, kz), Vector3(0.6, 0.9, 1.4), dark)
	kit.box_at(Vector3(kx, 0.92, kz), Vector3(0.66, 0.05, 1.46), wood)
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(kx, 0.945, kz - 0.3)), 0.22, 0.18, 0.12, 10, Color(0.80, 0.82, 0.84))
	kit.box_at(Vector3(kx, 1.12, kz + 0.4), Vector3(0.25, 0.35, 0.25), Color(0.30, 0.50, 0.62))
	for sh in [1.45, 1.85]:
		kit.box_at(Vector3(w * 0.5 - 0.3, sh, kz), Vector3(0.28, 0.03, 1.4), wood)
		var rngs := RandomNumberGenerator.new()
		rngs.seed = int(sh * 10.0)
		for k6 in range(7):
			var cc: Color = [Color(0.75, 0.15, 0.12), Color(0.85, 0.75, 0.25), Color(0.2, 0.4, 0.25), Color(0.8, 0.8, 0.78), Color(0.55, 0.35, 0.2)][rngs.randi() % 5]
			kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(w * 0.5 - 0.3, sh + 0.015, kz - 0.6 + 0.19 * float(k6))), 0.05, 0.05, rngs.randf_range(0.1, 0.18), 8, cc)
	solids.append([Vector3(kx, 0, kz), Vector3(0.65, 0.95, 1.5)])
	# coat hooks by the door: a jacket and a cap; a rifle on pegs over the door
	var hz := -d * 0.5 + 0.2
	kit.box_at(Vector3(1.4, 1.75, hz), Vector3(1.0, 0.08, 0.04), wood)
	kit.box_at(Vector3(1.2, 1.4, hz + 0.08), Vector3(0.45, 0.65, 0.12), Color(0.55, 0.30, 0.12))
	kit.box_at(Vector3(1.65, 1.62, hz + 0.08), Vector3(0.2, 0.1, 0.2), Color(0.20, 0.30, 0.20))
	if not office:
		kit.box_at(Vector3(0, 2.25, hz + 0.05), Vector3(1.1, 0.05, 0.04), Color(0.25, 0.18, 0.12))
		kit.box_at(Vector3(0.3, 2.25, hz + 0.05), Vector3(0.4, 0.09, 0.05), Color(0.38, 0.24, 0.14))
	# boots on a mat by the door
	for bxx in [-1.0, -0.82]:
		kit.box_at(Vector3(bxx, 0.2, hz + 0.25), Vector3(0.12, 0.18, 0.28), Color(0.15, 0.13, 0.11))
	# the lantern hanging from the ridge log
	var ly := eave - 0.63
	kit.box_at(Vector3(0, ly, 0.3), Vector3(0.12, 0.16, 0.12), Color(0.15, 0.15, 0.13))
	kit.box_at(Vector3(0, (ly + ridge) * 0.5, 0.3), Vector3(0.01, ridge - ly - 0.3, 0.01), Color(0.15, 0.15, 0.13))
	return solids


static func _chair(kit, at: Vector3, yaw: float, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	kit.box(Transform3D(b, at + b * Vector3(0, 0.45, 0)), Vector3(0.42, 0.04, 0.4), col)
	for lx in [-0.18, 0.18]:
		for lz in [-0.17, 0.17]:
			kit.box(Transform3D(b, at + b * Vector3(lx, 0.22, lz)), Vector3(0.04, 0.45, 0.04), col.darkened(0.2))
	kit.box(Transform3D(b, at + b * Vector3(0, 0.75, -0.18)), Vector3(0.42, 0.5, 0.04), col)


# ==============================================================================
#  Steel pole barns
# ==============================================================================
## A gable-entry machine shed: w along X, d along Z, the big sliding doors in
## the front (-Z) gable, a walk-in door and windows down the sides.
static func pole_barn(kit, w: float, d: float, eave: float, door_w: float, door_h: float, palette: Dictionary) -> Dictionary:
	var wall_c: Color = palette["wall"]
	var wains: Color = palette["wainscot"]
	var trim: Color = palette["trim"]
	var roof_c: Color = palette["roof"]
	var post_c := Color(0.42, 0.40, 0.28)       # treated wood, a bit green
	var pitch := 4.0 / 12.0
	var rise := w * 0.5 * pitch
	var over := 0.4
	# Concrete slab and an apron at the doors.
	kit.box_at(Vector3(0, 0.06, 0), Vector3(w, 0.12, d), Color(0.62, 0.62, 0.60))
	kit.box_at(Vector3(0, 0.05, -d * 0.5 - 1.2), Vector3(door_w + 1.0, 0.1, 2.4), Color(0.58, 0.58, 0.56))
	# Posts every 3 m down the sides, girts between them.
	var bays := int(round(d / 3.0))
	for i in range(bays + 1):
		var z := -d * 0.5 + d * float(i) / float(bays)
		for sx in [-1.0, 1.0]:
			kit.box_at(Vector3(sx * (w * 0.5 - 0.12), eave * 0.5, clampf(z, -d * 0.5 + 0.1, d * 0.5 - 0.1)), Vector3(0.15, eave, 0.15), post_c)
	for gy in [0.9, 2.1, 3.3]:
		if gy > eave - 0.4:
			continue
		for sx in [-1.0, 1.0]:
			kit.box_at(Vector3(sx * (w * 0.5 - 0.06), gy, 0), Vector3(0.04, 0.09, d - 0.1), Color(0.62, 0.52, 0.36))
	# Ribbed steel walls: sides, back, and the front either side of the door.
	_steel_wall(kit, Vector3(-w * 0.5, 0, 0), Vector3(0, 0, 1), d, eave, -1.0, wall_c, wains)
	_steel_wall(kit, Vector3(w * 0.5, 0, 0), Vector3(0, 0, 1), d, eave, 1.0, wall_c, wains)
	_steel_wall(kit, Vector3(0, 0, d * 0.5), Vector3(1, 0, 0), w, eave, 1.0, wall_c, wains)
	var side_w := (w - door_w) * 0.5
	for s in [-1.0, 1.0]:
		_steel_wall(kit, Vector3(s * (door_w * 0.5 + side_w * 0.5), 0, -d * 0.5), Vector3(1, 0, 0), side_w, eave, -1.0, wall_c, wains)
	# Header over the door, up to the eave.
	_steel_wall(kit, Vector3(0, door_h, -d * 0.5), Vector3(1, 0, 0), door_w, eave - door_h, -1.0, wall_c, wall_c)
	# Gables front and back.
	for sz in [-1.0, 1.0]:
		_steel_gable(kit, sz * d * 0.5, w, eave, rise, sz, wall_c)
	# Trim: corners, eave and rake, door.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.box_at(Vector3(sx * (w * 0.5 + 0.03), eave * 0.5, sz * (d * 0.5 + 0.03)), Vector3(0.14, eave, 0.14), trim)
		kit.box_at(Vector3(sx * (w * 0.5 + 0.05), 0.92, 0), Vector3(0.03, 0.05, d + 0.1), trim)
	kit.box_at(Vector3(0, 0.92, d * 0.5 + 0.05), Vector3(w + 0.1, 0.05, 0.03), trim)
	for s0 in [-1.0, 1.0]:
		kit.box_at(Vector3(s0 * (door_w * 0.5 + side_w * 0.5), 0.92, -d * 0.5 - 0.05), Vector3(side_w + 0.05, 0.05, 0.03), trim)
	kit.box_at(Vector3(0, door_h + 0.06, -d * 0.5 - 0.06), Vector3(door_w + 0.3, 0.12, 0.08), trim)
	for s in [-1.0, 1.0]:
		kit.box_at(Vector3(s * (door_w * 0.5 + 0.05), door_h * 0.5, -d * 0.5 - 0.06), Vector3(0.1, door_h, 0.08), trim)
	# Sliding doors, rolled open to the sides on their track.
	kit.box_at(Vector3(0, door_h + 0.22, -d * 0.5 - 0.14), Vector3(door_w * 2.0 + 0.4, 0.12, 0.1), Color(0.35, 0.35, 0.36))
	for s in [-1.0, 1.0]:
		var leaf := door_w * 0.5
		var cx: float = s * (door_w * 0.5 + leaf * 0.5 + 0.05)
		var lc := Vector3(cx, door_h * 0.5 + 0.05, -d * 0.5 - 0.2)
		kit.box_at(lc, Vector3(leaf, door_h - 0.05, 0.05), wall_c)
		var nr := int(leaf / 0.3)
		for i in range(nr + 1):
			kit.box_at(Vector3(cx - leaf * 0.5 + float(i) * leaf / float(nr), lc.y, lc.z - 0.035), Vector3(0.035, door_h - 0.05, 0.03), wall_c.darkened(0.12))
		# white frame and an X brace
		for e in [-1.0, 1.0]:
			kit.box_at(Vector3(cx + e * (leaf * 0.5 - 0.06), lc.y, lc.z - 0.06), Vector3(0.12, door_h - 0.05, 0.03), trim)
			kit.box_at(Vector3(cx, lc.y + e * (door_h * 0.5 - 0.08), lc.z - 0.06), Vector3(leaf, 0.12, 0.03), trim)
		var diag := Vector2(leaf - 0.2, door_h - 0.2)
		for e2 in [-1.0, 1.0]:
			var b := Basis(Vector3.FORWARD, e2 * atan2(diag.x, diag.y))
			kit.box(Transform3D(b, Vector3(cx, lc.y, lc.z - 0.06)), Vector3(0.1, diag.length(), 0.03), trim)
		# rollers
		for e3 in [-1.0, 1.0]:
			kit.box_at(Vector3(cx + e3 * leaf * 0.35, door_h + 0.12, -d * 0.5 - 0.17), Vector3(0.12, 0.12, 0.06), Color(0.2, 0.2, 0.2))
	# Walk-in door on the right side near the front, and windows down both sides.
	var wd_z := -d * 0.5 + 2.0
	kit.box_at(Vector3(w * 0.5 + 0.04, 1.05, wd_z), Vector3(0.05, 2.05, 0.95), trim)
	kit.box_at(Vector3(w * 0.5 + 0.07, 1.0, wd_z), Vector3(0.04, 1.95, 0.85), wall_c.lightened(0.1))
	kit.box_at(Vector3(w * 0.5 + 0.1, 1.0, wd_z - 0.32), Vector3(0.05, 0.05, 0.12), Color(0.2, 0.2, 0.2))
	for sx in [-1.0, 1.0]:
		var zs := [-d * 0.25, d * 0.15, d * 0.38] if d > 14.0 else [0.0]
		for wz in zs:
			if sx > 0.0 and absf(wz - wd_z) < 1.5:
				continue
			kit.box_at(Vector3(sx * (w * 0.5 + 0.04), 2.2, wz), Vector3(0.05, 1.0, 1.5), trim)
			kit.box_at(Vector3(sx * (w * 0.5 + 0.065), 2.2, wz), Vector3(0.04, 0.84, 1.34), Color(0.24, 0.32, 0.38))
			kit.box_at(Vector3(sx * (w * 0.5 + 0.08), 2.2, wz), Vector3(0.03, 0.84, 0.05), trim)
	# Trusses every bay.
	var tc := Color(0.66, 0.55, 0.38)
	for i in range(bays + 1):
		var z := clampf(-d * 0.5 + d * float(i) / float(bays), -d * 0.5 + 0.3, d * 0.5 - 0.3)
		kit.box_at(Vector3(0, eave - 0.05, z), Vector3(w - 0.2, 0.15, 0.05), tc)
		for sx in [-1.0, 1.0]:
			var a := Vector3(sx * (w * 0.5 - 0.1), eave + 0.05, z)
			var b2 := Vector3(0, eave + rise - 0.05, z)
			_beam(kit, a, b2, Vector2(0.05, 0.15), tc)
			_beam(kit, Vector3(sx * w * 0.25, eave, z), Vector3(0, eave + rise - 0.1, z), Vector2(0.05, 0.09), tc)
			_beam(kit, Vector3(sx * w * 0.25, eave, z), Vector3(sx * w * 0.25, eave + rise * 0.5, z), Vector2(0.05, 0.09), tc)
		kit.box_at(Vector3(0, eave + rise * 0.5, z), Vector3(0.05, rise, 0.09), tc)
	# Roof: galvalume panels with ribs down the slope, ridge cap.
	_steel_roof(kit, w, d, eave, rise, over, roof_c, trim)
	# A little vented cupola on the ridge.
	var cu := Vector3(0, eave + rise, 0)
	kit.box_at(cu + Vector3(0, 0.35, 0), Vector3(0.9, 0.7, 0.9), wall_c)
	for s2 in [-1.0, 1.0]:
		for e4 in range(3):
			kit.box_at(cu + Vector3(s2 * 0.46, 0.22 + 0.14 * float(e4), 0), Vector3(0.03, 0.05, 0.7), trim)
	kit.quad(cu + Vector3(-0.6, 0.7, -0.6), cu + Vector3(0.6, 0.7, -0.6), cu + Vector3(0.6, 1.05, 0), cu + Vector3(-0.6, 1.05, 0), roof_c, Vector3(0, 1, -1))
	kit.quad(cu + Vector3(0.6, 0.7, 0.6), cu + Vector3(-0.6, 0.7, 0.6), cu + Vector3(-0.6, 1.05, 0), cu + Vector3(0.6, 1.05, 0), roof_c, Vector3(0, 1, 1))
	for s3 in [-1.0, 1.0]:
		kit.tri(cu + Vector3(s3 * 0.6, 0.7, -0.6), cu + Vector3(s3 * 0.6, 0.7, 0.6), cu + Vector3(s3 * 0.6, 1.05, 0), roof_c, Vector3(s3, 0, 0))
	return {"eave": eave, "ridge": eave + rise, "solids": []}


## Open-front pole shed: a single slope roof high at the front, closed on the
## back and the two ends, posts across the open front.
static func pole_shed(kit, w: float, d: float, front_h: float, back_h: float, palette: Dictionary) -> Dictionary:
	var wall_c: Color = palette["wall"]
	var wains: Color = palette["wainscot"]
	var trim: Color = palette["trim"]
	var roof_c: Color = palette["roof"]
	var post_c := Color(0.42, 0.40, 0.28)
	kit.box_at(Vector3(0, 0.04, 0), Vector3(w, 0.08, d), Color(0.50, 0.46, 0.40))     # packed gravel floor
	var bays := int(round(w / 4.0))
	for i in range(bays + 1):
		var x := clampf(-w * 0.5 + w * float(i) / float(bays), -w * 0.5 + 0.1, w * 0.5 - 0.1)
		kit.box_at(Vector3(x, front_h * 0.5, -d * 0.5 + 0.1), Vector3(0.18, front_h, 0.18), post_c)
		kit.box_at(Vector3(x, back_h * 0.5, d * 0.5 - 0.1), Vector3(0.15, back_h, 0.15), post_c)
		# rafter
		_beam(kit, Vector3(x, front_h + 0.05, -d * 0.5 - 0.3), Vector3(x, back_h + 0.05, d * 0.5 + 0.3), Vector2(0.05, 0.2), Color(0.66, 0.55, 0.38))
	kit.box_at(Vector3(0, front_h - 0.12, -d * 0.5 + 0.1), Vector3(w, 0.25, 0.2), Color(0.62, 0.52, 0.36))     # header
	var solids: Array = []
	for i in range(1, bays):
		solids.append([Vector3(-w * 0.5 + w * float(i) / float(bays), 0, -d * 0.5 + 0.1), Vector3(0.3, front_h, 0.3)])
	_steel_wall(kit, Vector3(0, 0, d * 0.5), Vector3(1, 0, 0), w, back_h, 1.0, wall_c, wains)
	for sx in [-1.0, 1.0]:
		# end walls, sloped on top
		var nr := int(d / 0.3)
		var ex: float = sx * w * 0.5
		for i in range(nr):
			var z0 := -d * 0.5 + float(i) * d / float(nr)
			var z1 := z0 + d / float(nr)
			var h0 := lerpf(front_h, back_h, (z0 + d * 0.5) / d)
			var h1 := lerpf(front_h, back_h, (z1 + d * 0.5) / d)
			var hm := (h0 + h1) * 0.5
			kit.box_at(Vector3(ex, 0.45, (z0 + z1) * 0.5), Vector3(0.04, 0.9, z1 - z0), wains)
			kit.box_at(Vector3(ex, 0.9 + (hm - 0.9) * 0.5, (z0 + z1) * 0.5), Vector3(0.04, hm - 0.9, z1 - z0), wall_c if i % 2 == 0 else wall_c.darkened(0.08))
		kit.box_at(Vector3(ex + sx * 0.03, 0.92, 0), Vector3(0.03, 0.05, d), trim)
		for sz in [-1.0, 1.0]:
			var hh := front_h if sz < 0.0 else back_h
			kit.box_at(Vector3(ex + sx * 0.03, hh * 0.5, sz * (d * 0.5 + 0.03)), Vector3(0.12, hh, 0.12), trim)
	# single-slope roof
	var run := d + 0.8
	var drop := front_h - back_h
	var ang := atan2(drop, d)
	var rb := Basis(Vector3.RIGHT, ang)
	var len := sqrt(run * run + pow(drop * run / d, 2.0))
	var rc := Vector3(0, (front_h + back_h) * 0.5 + 0.2, 0)
	kit.box(Transform3D(rb, rc), Vector3(w + 0.8, 0.05, len), roof_c)
	var nr2 := int((w + 0.8) / 0.3)
	for i in range(nr2 + 1):
		var x2 := -(w * 0.5 + 0.4) + float(i) * (w + 0.8) / float(nr2)
		kit.box(Transform3D(rb, rc + rb.y * 0.035 + Vector3(x2, 0, 0)), Vector3(0.035, 0.03, len), roof_c.darkened(0.15))
	kit.box(Transform3D(rb, rc + rb.z * (-len * 0.5) + Vector3(0, -0.05, 0)), Vector3(w + 0.85, 0.16, 0.05), trim)
	return {"eave": back_h, "ridge": front_h, "solids": solids}


## Ribbed steel sheet: centre-bottom at `at`, running along `axis` for `length`,
## `h` tall, ribs on the side facing `face` (along the wall's normal).
static func _steel_wall(kit, at: Vector3, axis: Vector3, length: float, h: float, face: float, col: Color, wains: Color) -> void:
	var n := Vector3(axis.z, 0, axis.x) * face          # outward normal
	if absf(axis.x) > 0.5:
		n = Vector3(0, 0, face)
	else:
		n = Vector3(face, 0, 0)
	var thick := Vector3(0.04, 0, 0.04) - axis.abs() * 0.04
	var wb := minf(0.9, h) if wains != col else 0.0
	if wb > 0.0:
		kit.box_at(at + Vector3(0, wb * 0.5, 0), axis.abs() * length + Vector3(0, wb, 0) + thick, wains)
	kit.box_at(at + Vector3(0, wb + (h - wb) * 0.5, 0), axis.abs() * length + Vector3(0, h - wb, 0) + thick, col)
	var nr := int(length / 0.3)
	for i in range(nr + 1):
		var p := at + axis * (-length * 0.5 + float(i) * length / float(nr)) + n * 0.03
		var rib := axis.abs() * 0.035 + Vector3(0, 0, 0) + (Vector3(0.025, 0, 0) if absf(axis.x) < 0.5 else Vector3(0, 0, 0.025))
		if wb > 0.0:
			kit.box_at(p + Vector3(0, wb * 0.5, 0), rib + Vector3(0, wb, 0), wains.darkened(0.15))
		kit.box_at(p + Vector3(0, wb + (h - wb) * 0.5, 0), rib + Vector3(0, h - wb, 0), col.darkened(0.12))


## Gable triangle (front or back) above the eave, ribbed.
static func _steel_gable(kit, z: float, w: float, eave: float, rise: float, sz: float, col: Color) -> void:
	var a := Vector3(-w * 0.5, eave, z)
	var b := Vector3(w * 0.5, eave, z)
	var c := Vector3(0, eave + rise, z)
	kit.tri(a, b, c, col, Vector3(0, 0, sz))
	kit.tri(a, b, c, col.darkened(0.1), Vector3(0, 0, -sz))
	var nr := int(w / 0.3)
	for i in range(1, nr):
		var x := -w * 0.5 + float(i) * w / float(nr)
		var hh := rise * (1.0 - absf(x) / (w * 0.5))
		if hh < 0.05:
			continue
		kit.box_at(Vector3(x, eave + hh * 0.5, z + sz * 0.025), Vector3(0.035, hh, 0.03), col.darkened(0.12))


static func _steel_roof(kit, w: float, d: float, eave: float, rise: float, over: float, roof_c: Color, trim: Color) -> void:
	var half := w * 0.5 + over
	var drop := half * rise / (w * 0.5)
	var ang := atan2(rise, w * 0.5)
	var slope_len := sqrt(half * half + drop * drop)
	for sx in [-1.0, 1.0]:
		var rb := Basis(Vector3.FORWARD, sx * ang)
		var ctr := Vector3(sx * half * 0.5, eave + rise - drop * 0.5 + 0.08, 0)
		kit.box(Transform3D(rb, ctr), Vector3(slope_len, 0.05, d + over * 2.0), roof_c)
		var nr := int((d + over * 2.0) / 0.3)
		for i in range(nr + 1):
			var z := -(d * 0.5 + over) + float(i) * (d + over * 2.0) / float(nr)
			kit.box(Transform3D(rb, ctr + rb.y * 0.035 + Vector3(0, 0, z)), Vector3(slope_len, 0.03, 0.035), roof_c.darkened(0.14))
		# eave trim and rake trim
		kit.box(Transform3D(rb, ctr + rb.x * (sx * slope_len * 0.5) + Vector3(0, -0.06, 0)), Vector3(0.05, 0.18, d + over * 2.0 + 0.05), trim)
		for sz in [-1.0, 1.0]:
			kit.box(Transform3D(rb, ctr + Vector3(0, -0.04, sz * (d * 0.5 + over))), Vector3(slope_len, 0.16, 0.05), trim)
	kit.box_at(Vector3(0, eave + rise + 0.12, 0), Vector3(0.45, 0.06, d + over * 2.0), roof_c.darkened(0.05))


## A rectangular beam from a to b, cross-section (width, depth) with depth in the vertical plane.
static func _beam(kit, a: Vector3, b: Vector3, sec: Vector2, col: Color) -> void:
	var dir := b - a
	var l := dir.length()
	if l < 0.01:
		return
	var y := dir / l
	var x := Vector3.UP.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	var bs := Basis(x, y, z)
	kit.box(Transform3D(bs, (a + b) * 0.5), Vector3(sec.x, l, sec.y), col)


# ==============================================================================
#  Bush hangar (Alaska style)
# ==============================================================================
## White steel hangar with a bifold lift-strap door in the front gable, shown
## folded up open. Inside, from a reference photo (a light taildragger's hangar): bare
## galvanised sheet inside, dark steel frames and purlins, rusty batten lights,
## the back, skis, floats and tundra tyres stored on the walls, avgas drums
## with a hand pump, an engine pre-heater, a pilot room with a loft above.
## Returns local light positions: {"switch", "lamps", "fixtures"}.
static func bush_hangar(kit, w: float, d: float, eave: float, door_w: float, door_h: float, palette: Dictionary, seed_v: int = 7) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var wall_c: Color = palette["wall"]
	var wains: Color = palette["wainscot"]
	var trim: Color = palette["trim"]
	var roof_c: Color = palette["roof"]
	var pitch := 3.0 / 12.0
	var rise := w * 0.5 * pitch
	var hx := w * 0.5
	var hz := d * 0.5
	var over := 0.45
	# Slab: deep enough to hide a slope underneath, an apron out front.
	kit.box_at(Vector3(0, -0.35, 0), Vector3(w, 0.82, d), Color(0.60, 0.60, 0.58))
	kit.box_at(Vector3(0, -0.36, -hz - 2.0), Vector3(door_w + 1.0, 0.8, 4.0), Color(0.56, 0.56, 0.54))
	# painted taxi line in, and tie-down rings
	kit.box_at(Vector3(0, 0.062, -hz * 0.25), Vector3(0.12, 0.004, d * 0.7), Color(0.92, 0.75, 0.10))
	for tz in [-1.0, 3.0]:
		for tx in [-5.5, 5.5]:
			kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(tx, 0.06, tz)), 0.09, 0.09, 0.02, 8, Color(0.3, 0.3, 0.3))
	# Outside walls: ribbed white steel with a green wainscot.
	_steel_wall(kit, Vector3(-hx, 0, 0), Vector3(0, 0, 1), d, eave, -1.0, wall_c, wains)
	_steel_wall(kit, Vector3(hx, 0, 0), Vector3(0, 0, 1), d, eave, 1.0, wall_c, wains)
	_steel_wall(kit, Vector3(0, 0, hz), Vector3(1, 0, 0), w, eave, 1.0, wall_c, wains)
	var side_w := (w - door_w) * 0.5
	for s in [-1.0, 1.0]:
		_steel_wall(kit, Vector3(s * (door_w * 0.5 + side_w * 0.5), 0, -hz), Vector3(1, 0, 0), side_w, eave, -1.0, wall_c, wains)
	_steel_wall(kit, Vector3(0, door_h, -hz), Vector3(1, 0, 0), door_w, eave - door_h, -1.0, wall_c, wall_c)
	for sz in [-1.0, 1.0]:
		_steel_gable(kit, sz * hz, w, eave, rise, sz, wall_c)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.box_at(Vector3(sx * (hx + 0.03), eave * 0.5, sz * (hz + 0.03)), Vector3(0.14, eave, 0.14), trim)
	# Inside, as in the reference photo: no liner - the bare galvanised
	# corrugated sheet shows on the walls and under the roof, dark steel
	# girts and purlins, dark steel frames.
	var galv := Color(0.70, 0.71, 0.70)
	var galv_rib := Color(0.56, 0.57, 0.57)
	var dark_steel := Color(0.24, 0.25, 0.26)
	var li := 0.07
	for sx in [-1.0, 1.0]:
		_inner_sheet(kit, Vector3(sx * (hx - li), 0, 0), Vector3(0, 0, 1), d - 0.2, eave, -sx, galv, galv_rib)
	_inner_sheet(kit, Vector3(0, 0, hz - li), Vector3(1, 0, 0), w - 0.2, eave, -1.0, galv, galv_rib)
	for s in [-1.0, 1.0]:
		_inner_sheet(kit, Vector3(s * (door_w * 0.5 + side_w * 0.5), 0, -hz + li), Vector3(1, 0, 0), side_w - 0.1, eave, 1.0, galv, galv_rib)
	for sz in [-1.0, 1.0]:
		kit.tri(Vector3(-hx, eave, sz * (hz - li)), Vector3(hx, eave, sz * (hz - li)), Vector3(0, eave + rise, sz * (hz - li)), galv, Vector3(0, 0, -sz))
	# girts: dark C-channels round the walls
	for gy in [1.4, 3.2, 5.0]:
		if gy > eave - 0.5:
			continue
		for sx in [-1.0, 1.0]:
			kit.box_at(Vector3(sx * (hx - li - 0.06), gy, 0), Vector3(0.1, 0.16, d - 0.3), dark_steel)
		kit.box_at(Vector3(0, gy, hz - li - 0.06), Vector3(w - 0.3, 0.16, 0.1), dark_steel)
	# Steel frames every 6 m: columns and rafters, dark.
	var nf := maxi(int(round(d / 6.0)), 1)
	for i in range(nf + 1):
		var z := clampf(-hz + d * float(i) / float(nf), -hz + 0.25, hz - 0.25)
		for sx in [-1.0, 1.0]:
			kit.box_at(Vector3(sx * (hx - 0.3), eave * 0.5, z), Vector3(0.36, eave, 0.22), dark_steel)
			kit.box_at(Vector3(sx * (hx - 0.3), eave * 0.5, z), Vector3(0.12, eave, 0.3), dark_steel.darkened(0.15))
			_beam(kit, Vector3(sx * (hx - 0.1), eave - 0.2, z), Vector3(0, eave + rise - 0.3, z), Vector2(0.22, 0.45), dark_steel)
	# Underside of the roof: corrugated sheet running down the slope, dark
	# purlins across it every 1.2 m.
	var ang := atan2(rise, hx)
	var slope_in := sqrt(hx * hx + rise * rise)
	for sx in [-1.0, 1.0]:
		var rb := Basis(Vector3.FORWARD, sx * ang)
		var cc := Vector3(sx * hx * 0.5, eave + rise * 0.5 + 0.03, 0)
		kit.box(Transform3D(rb, cc), Vector3(slope_in, 0.02, d - 0.1), galv)
		var nr := int(d / 0.25)
		for k in range(nr + 1):
			var rz := -hz + 0.05 + float(k) * (d - 0.1) / float(nr)
			kit.box(Transform3D(rb, cc - rb.y * 0.02 + Vector3(0, 0, rz)), Vector3(slope_in, 0.02, 0.06), galv_rib)
		var np := int(slope_in / 1.2)
		for p in range(1, np + 1):
			var u := float(p) / float(np + 1)
			kit.box_at(Vector3(sx * hx * u, eave + rise * (1.0 - u) - 0.06, 0), Vector3(0.08, 0.18, d - 0.2), dark_steel)
	# Roof.
	_steel_roof(kit, w, d, eave, rise, over, roof_c, trim)
	# Windows down the sides (south light), both faces.
	for sx in [-1.0, 1.0]:
		for wz in [-hz * 0.45, 0.0, hz * 0.45]:
			kit.box_at(Vector3(sx * (hx + 0.04), 2.4, wz), Vector3(0.05, 1.35, 0.75), trim)
			kit.box_at(Vector3(sx * (hx + 0.065), 2.4, wz), Vector3(0.04, 1.2, 0.6), Color(0.24, 0.32, 0.38))
			kit.box_at(Vector3(sx * (hx - li - 0.02), 2.4, wz), Vector3(0.03, 1.2, 0.6), Color(0.62, 0.72, 0.80))
	# Walk-in door on the right wall near the front.
	kit.box_at(Vector3(hx + 0.05, 1.05, -hz + 1.6), Vector3(0.05, 2.1, 1.0), trim)
	kit.box_at(Vector3(hx + 0.08, 1.0, -hz + 1.6), Vector3(0.04, 1.98, 0.88), wall_c.darkened(0.05))
	kit.box_at(Vector3(hx + 0.11, 1.0, -hz + 1.25), Vector3(0.05, 0.05, 0.12), Color(0.2, 0.2, 0.2))
	# --- the bifold door, folded up open ---------------------------------------
	_bifold_open(kit, door_w, door_h, hz, wall_c, trim)
	# --- inside: Alaska bush flying ------------------------------------------
	var bz := hz - 0.75
	var wood := Color(0.52, 0.38, 0.24)
	var red := Color(0.70, 0.11, 0.09)
	# The workbench along the back (also the crafting bench, DESIGN_NOTES 152).
	workbench(kit, Vector3(-4.5, 0, bz), 4.0, hz - li - 0.03, rng)
	# Red rolling tool chest with a top box.
	kit.box_at(Vector3(-1.6, 0.55, bz), Vector3(1.1, 1.0, 0.55), red)
	kit.box_at(Vector3(-1.6, 1.3, bz + 0.05), Vector3(1.05, 0.5, 0.45), red.darkened(0.1))
	for k in range(6):
		kit.box_at(Vector3(-1.6, 0.18 + 0.16 * float(k), bz - 0.29), Vector3(1.0, 0.02, 0.02), Color(0.78, 0.78, 0.78))
	# Steel parts shelves: oil cases, filters, boxes.
	for sy in [0.35, 1.05, 1.75, 2.45]:
		kit.box_at(Vector3(1.6, sy, bz), Vector3(2.4, 0.04, 0.6), Color(0.30, 0.42, 0.62))
		for i in range(7):
			if rng.randf() < 0.2:
				continue
			var pc: Color = [Color(0.85, 0.65, 0.15), Color(0.6, 0.1, 0.1), Color(0.78, 0.72, 0.56), Color(0.2, 0.35, 0.6), Color(0.15, 0.15, 0.15)][rng.randi() % 5]
			var hh := rng.randf_range(0.16, 0.3)
			kit.box_at(Vector3(0.6 + 0.32 * float(i), sy + 0.02 + hh * 0.5, bz + rng.randf_range(-0.08, 0.08)), Vector3(0.24, hh, 0.32), pc)
	for sx2 in [0.4, 2.8]:
		kit.box_at(Vector3(sx2, 1.35, bz), Vector3(0.05, 2.7, 0.6), Color(0.30, 0.42, 0.62))
	# Pilot room in the back right corner, out of the wings' way, a loft on
	# top, stairs up the right wall to it.
	var ow := 2.8
	var od := 4.0
	var oh := 2.7
	var ox := hx - ow * 0.5 - 0.1
	var oz := hz - od * 0.5 - 0.1
	var room := Color(0.80, 0.76, 0.66)
	var oz0 := oz - od * 0.5
	kit.box_at(Vector3(ox, oh * 0.5, oz0), Vector3(ow, oh, 0.12), room)                # front wall
	kit.box_at(Vector3(ox - ow * 0.5, oh * 0.5, oz), Vector3(0.12, oh, od), room)       # left wall
	kit.box_at(Vector3(ox, oh + 0.08, oz), Vector3(ow + 0.1, 0.16, od + 0.1), wood)     # loft floor
	kit.box_at(Vector3(ox - ow * 0.5 - 0.06, 1.02, oz + 0.6), Vector3(0.03, 2.04, 0.9), wood.darkened(0.15))
	kit.box_at(Vector3(ox - ow * 0.5 - 0.09, 1.0, oz + 0.25), Vector3(0.05, 0.06, 0.06), Color(0.8, 0.75, 0.3))
	kit.box_at(Vector3(ox - 0.5, 1.5, oz0 - 0.06), Vector3(1.2, 0.9, 0.04), Color(0.25, 0.33, 0.40))
	kit.box_at(Vector3(ox - 0.5, 1.5, oz0 - 0.08), Vector3(1.3, 0.06, 0.04), trim)
	kit.box_at(Vector3(ox - ow * 0.5 - 0.06, 1.5, oz - 0.9), Vector3(0.04, 0.9, 1.2), Color(0.25, 0.33, 0.40))
	# loft railing: the left side, and the front up to the stair head
	var rail := Color(0.25, 0.25, 0.27)
	var stair_x := hx - 1.15       # clear of the frame columns on the wall
	var fr0 := ox - ow * 0.5
	var fr1 := stair_x - 0.5
	for e in range(6):
		kit.box_at(Vector3(lerpf(fr0, fr1, float(e) / 5.0), oh + 0.62, oz0), Vector3(0.05, 0.9, 0.05), rail)
	kit.box_at(Vector3((fr0 + fr1) * 0.5, oh + 1.07, oz0), Vector3(fr1 - fr0, 0.06, 0.06), rail)
	for e2 in range(7):
		kit.box_at(Vector3(fr0, oh + 0.62, lerpf(oz0, hz - 0.15, float(e2) / 6.0)), Vector3(0.05, 0.9, 0.05), rail)
	kit.box_at(Vector3(fr0, oh + 1.07, (oz0 + hz) * 0.5), Vector3(0.06, 0.06, hz - oz0), rail)
	for i in range(3):
		kit.box_at(Vector3(ox + 0.6, oh + 0.45, oz + 0.9 - 0.65 * float(i)), Vector3(0.6, 0.55, 0.55), [Color(0.62, 0.50, 0.32), Color(0.28, 0.36, 0.22), Color(0.55, 0.20, 0.15)][i])
	var steps := 13
	var run := 0.28
	var st0 := oz0 - float(steps) * run
	for i in range(steps):
		var y := (float(i) + 1.0) * (oh + 0.16) / float(steps)
		kit.box_at(Vector3(stair_x, y - 0.03, st0 + (float(i) + 0.5) * run), Vector3(0.9, 0.05, 0.3), wood)
	_beam(kit, Vector3(stair_x - 0.47, 0.0, st0), Vector3(stair_x - 0.47, oh + 0.16, oz0), Vector2(0.05, 0.25), wood.darkened(0.2))
	_beam(kit, Vector3(stair_x - 0.5, 0.9, st0), Vector3(stair_x - 0.5, oh + 1.07, oz0), Vector2(0.04, 0.05), rail)
	# Hanging gas unit heater (orange-brown box with louvres) and its flue.
	var hp := Vector3(-hx + 2.0, eave - 1.2, hz - 3.0)
	kit.box_at(hp, Vector3(0.9, 0.7, 0.6), Color(0.58, 0.42, 0.26))
	for k in range(4):
		kit.box_at(hp + Vector3(0, -0.24 + 0.16 * float(k), -0.31), Vector3(0.8, 0.03, 0.03), Color(0.25, 0.2, 0.15))
	kit.cylinder(Transform3D(Basis.IDENTITY, hp + Vector3(0, 0.35, 0.1)), 0.09, 0.09, rise + 1.5, 8, Color(0.6, 0.6, 0.6))
	for sx3 in [-0.35, 0.35]:
		kit.box_at(hp + Vector3(sx3, 0.65, 0), Vector3(0.02, 0.6, 0.02), Color(0.2, 0.2, 0.2))
	# Skis on the left wall rack, floats on cradles, tundra tyres stacked.
	for i in range(2):
		var sk := Vector3(-hx + li + 0.12 + 0.1 * float(i), 2.9 + 0.5 * float(i), -hz + 4.0)
		kit.box(Transform3D(Basis.IDENTITY, sk), Vector3(0.08, 0.12, 2.4), Color(0.85, 0.85, 0.82))
		kit.box(Transform3D(Basis(Vector3.RIGHT, -0.5), sk + Vector3(0, 0.15, -1.25)), Vector3(0.08, 0.1, 0.4), Color(0.85, 0.85, 0.82))
	for zb in [-hz + 3.0, -hz + 5.0]:
		kit.box_at(Vector3(-hx + li + 0.15, 2.85, zb), Vector3(0.3, 0.05, 0.05), Color(0.3, 0.3, 0.3))
	for i in range(2):
		var fx := -hx + 1.0 + 0.95 * float(i)
		var floatc := Color(0.80, 0.80, 0.78)
		_beam(kit, Vector3(fx, 0.55, -1.0), Vector3(fx, 0.55, 5.0), Vector2(0.6, 0.55), floatc)
		kit.box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(fx, 0.75, -1.25)), Vector3(0.58, 0.3, 0.6), floatc)
		kit.box_at(Vector3(fx, 0.87, 2.0), Vector3(0.2, 0.06, 5.6), floatc.darkened(0.1))
		for cz in [0.0, 4.0]:
			kit.box_at(Vector3(fx, 0.14, cz), Vector3(0.7, 0.28, 0.25), wood)
	for i in range(3):
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(-hx + 1.1, 0.065 + 0.42 * float(i), hz - 1.4)), 0.55, 0.55, 0.4, 12, Color(0.10, 0.10, 0.11))
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(-hx + 1.1, 0.07 + 0.42 * float(i), hz - 1.4)), 0.18, 0.18, 0.405, 8, Color(0.75, 0.75, 0.75))
	# Spare prop on the right wall, a wing cover bag, an old snowshoe pair.
	kit.box(Transform3D(Basis(Vector3.RIGHT, 0.0) * Basis(Vector3.BACK, 0.0), Vector3(hx - li - 0.06, 2.8, -1.0)), Vector3(0.05, 0.18, 2.2), Color(0.18, 0.18, 0.18))
	kit.box_at(Vector3(hx - li - 0.06, 2.8, 0.06), Vector3(0.06, 0.22, 0.12), Color(0.85, 0.75, 0.2))
	kit.box_at(Vector3(hx - li - 0.06, 2.8, -2.06), Vector3(0.06, 0.22, 0.12), Color(0.85, 0.75, 0.2))
	kit.box_at(Vector3(hx - li - 0.2, 1.4, -1.0), Vector3(0.3, 1.1, 1.6), Color(0.15, 0.25, 0.42))
	for i in range(2):
		kit.box(Transform3D(Basis(Vector3.RIGHT, 0.08), Vector3(hx - li - 0.05, 1.9, -3.2 + 0.4 * float(i))), Vector3(0.04, 1.0, 0.3), Color(0.5, 0.36, 0.22))
	# Avgas drums with a hand pump, jerry cans, an engine pre-heater cart.
	for i in range(4):
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(hx - 1.0 - 0.65 * float(i % 2), 0.06, -hz + 3.5 + 0.65 * float(i / 2))), 0.29, 0.29, 0.88, 10, [Color(0.15, 0.30, 0.60), red][i % 2])
	kit.box_at(Vector3(hx - 1.0, 1.15, -hz + 3.5), Vector3(0.12, 0.35, 0.12), Color(0.85, 0.7, 0.1))
	kit.box_at(Vector3(hx - 1.0, 1.0, -hz + 3.5), Vector3(0.04, 0.6, 0.04), Color(0.2, 0.2, 0.2))
	for i in range(3):
		kit.box(Transform3D(Basis(Vector3.UP, 0.2 * float(i)), Vector3(hx - 0.4, 0.28, -hz + 4.6 + 0.4 * float(i))), Vector3(0.18, 0.46, 0.34), [Color(0.6, 0.1, 0.1), Color(0.25, 0.35, 0.2), Color(0.6, 0.1, 0.1)][i])
	var heat := Vector3(hx - 1.0, 0, -1.6)
	kit.box_at(heat + Vector3(0, 0.45, 0), Vector3(0.6, 0.5, 0.9), Color(0.75, 0.15, 0.10))
	kit.cylinder(Transform3D(Basis(Vector3.RIGHT, -1.2), heat + Vector3(0, 0.55, -0.45)), 0.1, 0.1, 1.4, 8, Color(0.6, 0.6, 0.58))
	for wz2 in [-0.35, 0.35]:
		kit.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), heat + Vector3(-0.32, 0.12, wz2)), 0.12, 0.12, 0.64, 8, Color(0.1, 0.1, 0.1))
	# Wood plank chocks waiting for the tundra tyres, either side of the line.
	for cxw in [-1.4, 1.4]:
		kit.box_at(Vector3(cxw, 0.1, 0.5), Vector3(0.7, 0.08, 0.18), Color(0.55, 0.38, 0.22))
		kit.box_at(Vector3(cxw, 0.1, 1.5), Vector3(0.7, 0.08, 0.18), Color(0.52, 0.36, 0.21))
	# A coil of rope on the door post, a white jerry can by it.
	kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-door_w * 0.5 - 0.35, 1.6, -hz + li + 0.05)), 0.22, 0.22, 0.08, 10, Color(0.85, 0.83, 0.78))
	kit.box_at(Vector3(-door_w * 0.5 - 0.4, 0.22, -hz + 0.5), Vector3(0.3, 0.42, 0.22), Color(0.92, 0.92, 0.9))
	# A tug by the door, wheel chocks, a fire extinguisher, an air hose reel.
	var tug := Vector3(-hx + 1.0, 0, -hz + 2.6)
	kit.box_at(tug + Vector3(0, 0.35, 0), Vector3(0.7, 0.45, 1.1), Color(0.85, 0.70, 0.10))
	kit.box(Transform3D(Basis(Vector3.RIGHT, -0.7), tug + Vector3(0, 0.9, 0.6)), Vector3(0.06, 0.06, 1.0), Color(0.2, 0.2, 0.2))
	for cz2 in [0.0, 0.3]:
		kit.box_at(Vector3(-hx + 0.4, 0.1, -hz + 4.2 + cz2), Vector3(0.25, 0.14, 0.18), Color(0.85, 0.7, 0.1))
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(-door_w * 0.5 - 0.6, 0.9, -hz + li + 0.15)), 0.08, 0.08, 0.5, 8, red)
	kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-hx + li, 1.9, 2.5)), 0.3, 0.3, 0.2, 10, Color(0.25, 0.25, 0.27))
	kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-hx + li + 0.01, 1.9, 2.5)), 0.24, 0.24, 0.205, 10, Color(0.85, 0.15, 0.1))
	# Oil stains on the slab.
	for st in [[Vector3(-1.2, 0.062, -2.0), 0.7], [Vector3(1.5, 0.062, 1.4), 0.45], [Vector3(0.4, 0.062, bz - 3.0), 0.3]]:   # flat, nothing to hit
		kit.cylinder(Transform3D(Basis.IDENTITY, st[0] as Vector3), float(st[1]), float(st[1]) * 0.8, 0.004, 9, Color(0.40, 0.40, 0.38))
	# Long fluorescent battens in rusty housings, hung on rods from the purlins
	# (like the photo), in two rows down the hangar.
	var fixtures: Array = []
	var lamps: Array = []
	var rust := Color(0.62, 0.42, 0.24)
	for lz in [-hz * 0.55, -hz * 0.1, hz * 0.35]:
		for lx in [-hx * 0.42, hx * 0.42]:
			var ly := eave + rise * (1.0 - absf(lx) / hx) - 0.9
			kit.box_at(Vector3(lx, ly, lz), Vector3(0.28, 0.1, 1.6), rust)
			kit.box_at(Vector3(lx, ly - 0.06, lz), Vector3(0.18, 0.04, 1.5), Color(0.92, 0.90, 0.84))
			for e in [-0.6, 0.6]:
				kit.box_at(Vector3(lx, ly + 0.45, lz + e), Vector3(0.015, 0.8, 0.015), Color(0.2, 0.2, 0.2))
			fixtures.append([Transform3D(Basis.IDENTITY, Vector3(lx, ly - 0.085, lz)), Vector3(0.16, 0.02, 1.45)])
		lamps.append(Vector3(0, eave - 0.6, lz))
	var sw := Vector3(-door_w * 0.5 - 0.7, 1.35, -hz + li + 0.03)
	kit.box_at(sw, Vector3(0.10, 0.14, 0.03), Color(0.75, 0.75, 0.72))
	kit.box_at(sw + Vector3(0, 0.6, 0), Vector3(0.03, 1.2, 0.03), Color(0.4, 0.4, 0.42))
	return {"switch": sw + Vector3(0, 0, 0.1), "lamps": lamps, "fixtures": fixtures, "bench": Vector3(-4.5, 0, bz),
		"solids": [
			[Vector3(ox, 0, oz), Vector3(ow, oh - 0.45, od)],                        # pilot room (low enough to step off the stairs onto the loft)
			[Vector3(-4.5, 0, bz), Vector3(4.0, 1.0, 0.85)],                         # workbench
			[Vector3(-1.6, 0, bz), Vector3(1.15, 1.6, 0.6)],                         # tool chest
			[Vector3(1.6, 0, bz), Vector3(2.5, 2.7, 0.65)],                          # shelves
			[Vector3(-hx + 1.5, 0, 2.0), Vector3(1.7, 1.0, 6.6)],                    # floats on cradles
			[Vector3(-hx + 1.1, 0, hz - 1.4), Vector3(1.15, 1.3, 1.15)],             # tyre stack
			[Vector3(hx - 1.3, 0, -hz + 3.8), Vector3(1.35, 1.0, 1.35)],             # avgas drums
			[Vector3(hx - 0.4, 0, -hz + 5.0), Vector3(0.35, 0.5, 1.2)],              # jerry cans
			[heat, Vector3(0.75, 0.75, 1.1)],                                        # pre-heater cart
			[tug, Vector3(0.75, 0.8, 1.2)],                                          # tug
		] + _frame_solids(hx, hz, d, eave),
		# things you walk up onto: the stairs (a ramp) and the loft floor
		"platforms": [
			[Vector3(stair_x, 0, (st0 + oz0) * 0.5), Vector3(1.0, 0, oz0 - st0), 0.0, oh + 0.16],
			[Vector3(ox, 0, oz), Vector3(ow, 0, od), oh + 0.16, oh + 0.16],
		],
		"door_switch": Vector3(door_w * 0.5 + 0.6, 1.3, -hz + li + 0.05)}


## The rigid-frame columns stand just inside the walls.
static func _frame_solids(hx: float, hz: float, d: float, eave: float) -> Array:
	var out: Array = []
	var nf := maxi(int(round(d / 6.0)), 1)
	for i in range(nf + 1):
		var z := clampf(-hz + d * float(i) / float(nf), -hz + 0.25, hz - 0.25)
		for sx in [-1.0, 1.0]:
			out.append([Vector3(sx * (hx - 0.3), 0, z), Vector3(0.4, eave, 0.35)])
	return out


## A bifold lift-strap door, open: the top leaf swung up and out from the
## header into a canopy, the bottom leaf folded back under it, the straps
## running from the winch drum over the header down to the bottom edge.
static func _bifold_open(kit, door_w: float, door_h: float, hz: float, skin: Color, trim: Color) -> void:
	# The leaves and straps move (bifold_door.gd); here the fixed parts:
	# the header beam, the winch drum on top of it and its motor.
	var steel := Color(0.40, 0.42, 0.44)
	kit.box_at(Vector3(0, door_h + 0.25, -hz - 0.05), Vector3(door_w + 0.8, 0.5, 0.3), steel)
	kit.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-door_w * 0.5, door_h + 0.75, -hz - 0.15)), 0.12, 0.12, door_w, 10, steel.darkened(0.2))
	kit.box_at(Vector3(door_w * 0.5 - 0.4, door_h + 0.75, -hz - 0.15), Vector3(0.5, 0.4, 0.4), Color(0.2, 0.3, 0.55))
	for s2 in [-1.0, 1.0]:
		kit.box_at(Vector3(s2 * (door_w * 0.5 + 0.08), door_h * 0.5, -hz - 0.1), Vector3(0.16, door_h, 0.2), steel)   # jambs



## Bare corrugated sheet seen from inside: a sheet with ribs every 0.2 m on
## the face toward `face` (the inside).
static func _inner_sheet(kit, at: Vector3, axis: Vector3, length: float, h: float, face: float, col: Color, rib: Color) -> void:
	var n := Vector3(face, 0, 0) if absf(axis.z) > 0.5 else Vector3(0, 0, face)
	var thick := Vector3(0.02, 0, 0) if absf(axis.z) > 0.5 else Vector3(0, 0, 0.02)
	kit.box_at(at + Vector3(0, h * 0.5, 0), axis.abs() * length + Vector3(0, h, 0) + thick, col)
	var nr := int(length / 0.2)
	for i in range(nr + 1):
		var p := at + axis * (-length * 0.5 + float(i) * length / float(nr)) + n * 0.02
		kit.box_at(p + Vector3(0, h * 0.5, 0), axis.abs() * 0.05 + Vector3(0, h, 0) + thick, rib)


## A shop workbench, built from pictures of real hangar benches: a thick
## laminated top with a steel nosing, 4x4 legs with rails and a lower shelf,
## a bank of drawers, a machinist's vise bolted over the front right leg, a
## bench grinder on the left end, a pegboard on the wall behind with the
## tools hung on it, a shelf of jars and cans above, and a fluorescent shop
## light on chains. `c` is the floor point under the middle of the front
## edge's line (the bench runs along x, its back to +z); `wall_z` is the wall face.
static func workbench(kit, c: Vector3, length: float, wall_z: float, rng: RandomNumberGenerator) -> void:
	var top_c := Color(0.62, 0.47, 0.30)
	var leg_c := Color(0.48, 0.35, 0.22)
	var steel := Color(0.36, 0.37, 0.39)
	var dark := Color(0.13, 0.13, 0.14)
	var vblue := Color(0.20, 0.33, 0.52)
	var red := Color(0.70, 0.11, 0.09)
	var hl := length * 0.5
	var d := 0.8
	var x0 := c.x
	var z0 := c.z
	var ty := 0.92
	# top: laminated strips, a steel nosing on the front edge
	for i in range(8):
		var sz := z0 - d * 0.5 + d * (float(i) + 0.5) / 8.0
		kit.box_at(Vector3(x0, ty - 0.03, sz), Vector3(length, 0.06, d / 8.0 - 0.004), top_c.darkened(0.04 * float(i % 3)))
	kit.box_at(Vector3(x0, ty - 0.035, z0 - d * 0.5 - 0.006), Vector3(length + 0.02, 0.075, 0.012), steel)
	# legs, rails, lower shelf
	for lx in [-hl + 0.12, -0.15, hl - 0.12]:
		for lz in [z0 - d * 0.5 + 0.08, z0 + d * 0.5 - 0.08]:
			kit.box_at(Vector3(x0 + lx, (ty - 0.06) * 0.5, lz), Vector3(0.09, ty - 0.06, 0.09), leg_c)
		kit.box_at(Vector3(x0 + lx, 0.22, z0), Vector3(0.06, 0.08, d - 0.1), leg_c.darkened(0.1))
	for rz in [z0 - d * 0.5 + 0.08, z0 + d * 0.5 - 0.08]:
		kit.box_at(Vector3(x0, ty - 0.13, rz), Vector3(length - 0.2, 0.1, 0.05), leg_c.darkened(0.08))
	kit.box_at(Vector3(x0, 0.27, z0), Vector3(length - 0.24, 0.03, d - 0.16), top_c.darkened(0.2))
	# a bank of four drawers under the right half
	var dx := x0 + hl * 0.5
	kit.box_at(Vector3(dx, ty - 0.33, z0 + 0.02), Vector3(hl * 0.8, 0.5, d - 0.14), steel.darkened(0.15))
	for k in range(4):
		var dy := ty - 0.17 - 0.115 * float(k)
		kit.box_at(Vector3(dx, dy, z0 - d * 0.5 + 0.06), Vector3(hl * 0.78, 0.1, 0.02), Color(0.42, 0.44, 0.47))
		kit.box_at(Vector3(dx, dy, z0 - d * 0.5 + 0.045), Vector3(0.16, 0.02, 0.02), dark)
	# junk on the lower shelf: a parts bin, a coffee can of bolts, an oil case
	kit.box_at(Vector3(x0 - hl + 0.5, 0.36, z0), Vector3(0.45, 0.16, 0.32), Color(0.85, 0.62, 0.15))
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(x0 - hl + 0.95, 0.285, z0 - 0.05)), 0.08, 0.08, 0.16, 10, Color(0.6, 0.15, 0.1))
	kit.box_at(Vector3(x0 - 0.7, 0.4, z0 + 0.05), Vector3(0.5, 0.24, 0.3), Color(0.78, 0.72, 0.56))
	# machinist's vise over the right front leg: base, body, jaws, screw, handle
	var vx := x0 + hl - 0.28
	var vz := z0 - d * 0.5 + 0.12
	kit.box_at(Vector3(vx, ty + 0.03, vz + 0.06), Vector3(0.2, 0.06, 0.24), vblue.darkened(0.2))
	kit.box_at(Vector3(vx, ty + 0.11, vz + 0.1), Vector3(0.16, 0.12, 0.16), vblue)
	kit.box_at(Vector3(vx, ty + 0.11, vz - 0.04), Vector3(0.15, 0.11, 0.07), vblue)
	for jz in [vz + 0.015, vz - 0.0]:
		kit.box_at(Vector3(vx, ty + 0.15, jz), Vector3(0.16, 0.05, 0.012), dark)
	kit.box_at(Vector3(vx, ty + 0.1, vz - 0.04), Vector3(0.06, 0.06, 0.18), steel)
	kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(vx, ty + 0.09, vz - 0.17)), 0.016, 0.016, 0.06, 6, steel)
	kit.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(vx - 0.12, ty + 0.09, vz - 0.14)), 0.009, 0.009, 0.24, 6, Color(0.78, 0.78, 0.8))
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(vx, ty + 0.17, vz + 0.12)), 0.035, 0.035, 0.03, 8, vblue.darkened(0.3))   # anvil horn pad
	# bench grinder on the left end: motor, two wheels in guards, tool rests
	var gx := x0 - hl + 0.32
	var gz := z0 - 0.05
	kit.box_at(Vector3(gx, ty + 0.02, gz), Vector3(0.16, 0.04, 0.16), Color(0.25, 0.4, 0.3))
	kit.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(gx - 0.1, ty + 0.13, gz)), 0.075, 0.075, 0.2, 12, Color(0.3, 0.46, 0.34))
	for sxg in [-1.0, 1.0]:
		var wx: float = gx + float(sxg) * 0.17
		kit.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(wx - 0.025, ty + 0.13, gz)), 0.085, 0.085, 0.05, 14, Color(0.55, 0.55, 0.52))
		kit.box_at(Vector3(wx, ty + 0.2, gz + 0.02), Vector3(0.07, 0.04, 0.17), Color(0.3, 0.46, 0.34))
		kit.box_at(Vector3(wx, ty + 0.1, gz - 0.1), Vector3(0.06, 0.012, 0.05), steel)
	# pegboard on the wall, the tools hung on it
	var pb_z := wall_z - 0.02
	var pb_w := length - 0.3
	kit.box_at(Vector3(x0, 1.75, pb_z), Vector3(pb_w, 1.1, 0.02), Color(0.66, 0.54, 0.36))
	kit.box_at(Vector3(x0, 1.75, pb_z + 0.004), Vector3(pb_w + 0.06, 1.16, 0.012), leg_c)
	var tz := pb_z - 0.025
	# combination wrenches, small to big
	for i in range(8):
		var wl := 0.14 + 0.025 * float(i)
		var wx2 := x0 - pb_w * 0.5 + 0.18 + 0.075 * float(i)
		kit.box_at(Vector3(wx2, 2.05 - wl * 0.5, tz), Vector3(0.018, wl, 0.008), Color(0.8, 0.8, 0.82))
		kit.box_at(Vector3(wx2, 2.05 - wl, tz), Vector3(0.035, 0.03, 0.008), Color(0.8, 0.8, 0.82))
	# screwdrivers in a rack
	kit.box_at(Vector3(x0 - 0.35, 1.62, tz), Vector3(0.6, 0.03, 0.05), leg_c.darkened(0.2))
	for i in range(7):
		var sx := x0 - 0.6 + 0.08 * float(i)
		kit.box_at(Vector3(sx, 1.68, tz - 0.02), Vector3(0.026, 0.09, 0.026), [red, Color(0.95, 0.75, 0.1), Color(0.15, 0.3, 0.6)][i % 3])
		kit.box_at(Vector3(sx, 1.53, tz - 0.02), Vector3(0.008, 0.16, 0.008), Color(0.75, 0.75, 0.78))
	# hammers, pliers, a hacksaw, a coil of safety wire
	for i in range(3):
		var hx2 := x0 + 0.15 + 0.2 * float(i)
		kit.box_at(Vector3(hx2, 1.82, tz), Vector3(0.025, 0.3, 0.02), Color(0.62, 0.45, 0.25))
		kit.box_at(Vector3(hx2, 1.98, tz - 0.01), Vector3(0.11 - 0.015 * float(i), 0.035, 0.035), dark)
	for i in range(3):
		var px := x0 + 0.8 + 0.13 * float(i)
		kit.box_at(Vector3(px - 0.015, 1.86, tz), Vector3(0.012, 0.2, 0.01), red)
		kit.box_at(Vector3(px + 0.015, 1.86, tz), Vector3(0.012, 0.2, 0.01), red)
		kit.box_at(Vector3(px, 2.0, tz), Vector3(0.04, 0.07, 0.012), steel)
	kit.box_at(Vector3(x0 + 0.5, 1.45, tz), Vector3(0.5, 0.012, 0.01), Color(0.8, 0.8, 0.82))
	kit.box_at(Vector3(x0 + 0.5, 1.5, tz), Vector3(0.52, 0.1, 0.012), Color(0.15, 0.3, 0.6))
	kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x0 + 1.4, 1.55, tz + 0.01)), 0.07, 0.07, 0.03, 12, Color(0.72, 0.72, 0.68))
	# shelf of jars, cans and spray bottles above the pegboard
	kit.box_at(Vector3(x0, 2.42, wall_z - 0.13), Vector3(pb_w, 0.03, 0.24), top_c.darkened(0.1))
	for bxs in [-pb_w * 0.5 + 0.1, pb_w * 0.5 - 0.1]:
		kit.box(Transform3D(Basis(Vector3.RIGHT, 0.7), Vector3(x0 + bxs, 2.33, wall_z - 0.07)), Vector3(0.03, 0.18, 0.03), steel)
	var cx := x0 - pb_w * 0.5 + 0.15
	while cx < x0 + pb_w * 0.5 - 0.15:
		var ch := rng.randf_range(0.1, 0.24)
		var cr := rng.randf_range(0.035, 0.06)
		var cc: Color = [Color(0.85, 0.65, 0.15), red, Color(0.78, 0.8, 0.82), Color(0.2, 0.35, 0.6), Color(0.3, 0.5, 0.3), Color(0.92, 0.9, 0.85)][rng.randi() % 6]
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(cx, 2.435, wall_z - 0.13 + rng.randf_range(-0.04, 0.04))), cr, cr, ch, 8, cc)
		cx += cr * 2.0 + rng.randf_range(0.02, 0.1)
	# on the bench: a rag, a coffee can, a socket set case, a part being worked on
	kit.box_at(Vector3(x0 - 0.2, ty + 0.01, z0 - 0.1), Vector3(0.28, 0.02, 0.22), Color(0.75, 0.25, 0.2))
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(x0 + 0.35, ty, z0 + 0.22)), 0.07, 0.07, 0.15, 10, Color(0.2, 0.35, 0.25))
	kit.box_at(Vector3(x0 - 0.9, ty + 0.05, z0 + 0.15), Vector3(0.45, 0.1, 0.28), red)
	kit.box_at(Vector3(x0 - 0.9, ty + 0.105, z0 + 0.15), Vector3(0.12, 0.012, 0.04), steel)
	kit.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x0 + 0.05, ty + 0.06, z0)), 0.06, 0.05, 0.22, 10, Color(0.62, 0.63, 0.6))   # a cylinder off an engine
	# fluorescent shop light on chains over it
	kit.box_at(Vector3(x0, 2.75, z0 + 0.05), Vector3(1.25, 0.05, 0.2), Color(0.9, 0.9, 0.86))
	kit.box_at(Vector3(x0, 2.72, z0 + 0.05), Vector3(1.2, 0.02, 0.12), Color(0.98, 0.98, 0.94))
	for cxs in [-0.5, 0.5]:
		kit.box_at(Vector3(x0 + cxs, 2.95, z0 + 0.05), Vector3(0.012, 0.4, 0.012), dark)
	# a power strip along the back edge, its cord down the leg
	kit.box_at(Vector3(x0 + 0.3, ty + 0.025, z0 + d * 0.5 - 0.05), Vector3(0.4, 0.05, 0.06), Color(0.85, 0.85, 0.82))
	kit.box_at(Vector3(x0 + hl - 0.12, ty * 0.5, z0 + d * 0.5 - 0.02), Vector3(0.012, ty, 0.012), dark)
