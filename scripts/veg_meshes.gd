extends RefCounted
## Plant and rock models, built from simple shapes at unit size (height 1).
## Vertex colour RGB is the base colour; alpha is 1 for leaves, needles, blades
## and flowers (tinted by season in the shader) and 0 for bark, stems and dead
## thatch. Trees come in three levels of detail: 0 near, 1 middle, 2 far.
##
## The palette is deliberately muted (dark blue-green spruce, olive birch,
## straw-tipped grass) to sit with the painted, overcast look of the game.

const MeshKit = preload("res://scripts/meshkit.gd")
const Flora = preload("res://scripts/flora.gd")

const BARK_SPRUCE := Color(0.30, 0.25, 0.21, 0.0)
const BARK_BIRCH := Color(0.82, 0.80, 0.75, 0.0)
const BARK_ASPEN := Color(0.66, 0.68, 0.60, 0.0)
const BARK_POPLAR := Color(0.38, 0.36, 0.33, 0.0)
const BARK_SNAG := Color(0.56, 0.54, 0.51, 0.0)
const CHAR := Color(0.11, 0.10, 0.09, 0.0)
const NEEDLE_W := Color(0.16, 0.23, 0.18, 1.0)
const NEEDLE_B := Color(0.17, 0.21, 0.17, 1.0)
const LEAF_BIRCH := Color(0.40, 0.47, 0.24, 1.0)
const LEAF_ASPEN := Color(0.45, 0.51, 0.28, 1.0)
const LEAF_POPLAR := Color(0.30, 0.37, 0.22, 1.0)
const LEAF_ALDER := Color(0.27, 0.33, 0.19, 1.0)
const LEAF_WILLOW := Color(0.42, 0.46, 0.33, 1.0)
const LEAF_DBIRCH := Color(0.36, 0.38, 0.21, 1.0)
const GRASS_ROOT := Color(0.20, 0.21, 0.13, 1.0)
const GRASS_MID := Color(0.40, 0.40, 0.24, 1.0)
const GRASS_TIP := Color(0.60, 0.56, 0.37, 1.0)
const STRAW := Color(0.64, 0.58, 0.42, 1.0)
const THATCH := Color(0.36, 0.31, 0.22, 0.0)


static func _h(i: int, k: int) -> float:
	return Flora.h01(i, k, 77)


## An irregular cone of needles: a ring of jittered points under an apex.
static func _tier(kit: RefCounted, y: float, r: float, hgt: float, sides: int, col: Color, seed: int, off := Vector3.ZERO) -> void:
	var under := PackedVector3Array()
	var outer := PackedVector3Array()
	var apex := PackedVector3Array()
	for k in range(sides):
		var a := TAU * (float(k) + 0.3 * _h(seed, k)) / float(sides)
		var rr := r * (0.78 + 0.4 * _h(seed + 7, k))
		var d := Vector3(cos(a), 0.0, sin(a))
		under.append(off + d * rr * 0.35 + Vector3(0, y + hgt * 0.12, 0))
		outer.append(off + d * rr + Vector3(0, y - hgt * 0.10 * _h(seed + 3, k), 0))
		apex.append(off * 0.5 + d * 0.004 + Vector3(0, y + hgt, 0))
	kit.loft([under, outer, apex], col, true, false)


## A lumpy round blob of leaves (a jittered, subdivided octahedron).
static func _blob(kit: RefCounted, c: Vector3, r: Vector3, col: Color, seed: int, detail: int = 1) -> void:
	var verts := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var faces := [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [0, 4, 3], [4, 1, 3], [1, 5, 3], [5, 0, 3]]
	var tris: Array = []
	for f in faces:
		tris.append([verts[f[0]], verts[f[1]], verts[f[2]]])
	for _d in range(detail):
		var nt: Array = []
		for t in tris:
			var a: Vector3 = t[0]
			var b: Vector3 = t[1]
			var cc: Vector3 = t[2]
			var ab := ((a + b) * 0.5).normalized()
			var bc := ((b + cc) * 0.5).normalized()
			var ca := ((cc + a) * 0.5).normalized()
			nt.append([a, ab, ca])
			nt.append([ab, b, bc])
			nt.append([ca, bc, cc])
			nt.append([ab, bc, ca])
		tris = nt
	var jit := func(p: Vector3) -> Vector3:
		var q := (p * 100.0).round()
		var hh := Flora.h01(int(q.x) + seed * 13, int(q.y) * 7 + int(q.z), seed)
		return c + Vector3(p.x * r.x, p.y * r.y, p.z * r.z) * (0.78 + 0.38 * hh)
	for t in tris:
		var a2: Vector3 = jit.call(t[0])
		var b2: Vector3 = jit.call(t[1])
		var c2: Vector3 = jit.call(t[2])
		kit.tri(a2, b2, c2, col, (a2 + b2 + c2) / 3.0 - c)


static func _trunk(kit: RefCounted, h: float, r0: float, r1: float, col: Color, sides: int) -> void:
	kit.cylinder(Transform3D.IDENTITY, r0, r1, h, sides, col, false)


static func _branch(kit: RefCounted, from: Vector3, to: Vector3, r: float, col: Color, sides: int = 4) -> void:
	var d := to - from
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	kit.cylinder(Transform3D(Basis(x, y, z), from), r, r * 0.4, d.length(), sides, col, false)


## Soft, mostly-upward normal for thin plant parts, so they light like foliage
## instead of flashing light and dark as they turn.
static func _soft(n: Vector3) -> Vector3:
	return (n.normalized() * 0.4 + Vector3.UP * 0.75).normalized()


## One grass or sedge blade: a tapering strip that rises and arches outward.
static func _blade(kit: RefCounted, base: Vector3, ang: float, height: float, lean: float, width: float,
		c0: Color, c1: Color, c2: Color, segs: int = 3) -> void:
	var out := Vector3(cos(ang), 0.0, sin(ang))
	var side := Vector3(-sin(ang), 0.0, cos(ang))
	var nrm := _soft(out * 0.6 + Vector3.UP * 0.4)
	var prev_p := base
	var prev_w := width
	var prev_c := c0
	for s in range(1, segs + 1):
		var t := float(s) / float(segs)
		var p := base + out * (lean * t * t) + Vector3.UP * (height * (t - 0.18 * lean / maxf(height, 0.01) * t * t * t))
		var w := width * (1.0 - t * 0.92)
		var c := c0.lerp(c1, minf(t * 2.0, 1.0)) if t <= 0.5 else c1.lerp(c2, (t - 0.5) * 2.0)
		var a := prev_p - side * prev_w
		var b := prev_p + side * prev_w
		var cc := p + side * w
		var d := p - side * w
		kit.tri_c(a, b, cc, prev_c, prev_c, c, nrm, nrm, nrm)
		kit.tri_c(a, cc, d, prev_c, c, c, nrm, nrm, nrm)
		prev_p = p
		prev_w = w
		prev_c = c


## A flat leaf: a diamond from `base` along `dir`, facing roughly `up`.
static func _leaf(kit: RefCounted, base: Vector3, dir: Vector3, length: float, width: float, c0: Color, c1: Color) -> void:
	var d := dir.normalized()
	var side := d.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var nrm := _soft(side.cross(d))
	var tip := base + d * length
	var mid := base + d * (length * 0.42)
	var l := mid - side * width
	var r := mid + side * width
	var cm := c0.lerp(c1, 0.45)
	kit.tri_c(base, l, tip, c0, cm, c1, nrm, nrm, nrm)
	kit.tri_c(base, tip, r, c0, c1, cm, nrm, nrm, nrm)


## A handful of small leaves scattered over a crown blob, to break its outline.
static func _fringe(kit: RefCounted, c: Vector3, r: Vector3, col: Color, count: int, size: float, seed: int) -> void:
	for k in range(count):
		var u := _h(seed + k, 1) * 2.0 - 1.0
		var a := _h(seed + k, 2) * TAU
		var s := sqrt(1.0 - u * u)
		var n := Vector3(s * cos(a), u * 0.8 + 0.2, s * sin(a)).normalized()
		var p := c + Vector3(n.x * r.x, n.y * r.y, n.z * r.z) * 0.95
		var along := (n + Vector3(0.4 * (_h(seed + k, 3) - 0.5), -0.3, 0.4 * (_h(seed + k, 4) - 0.5))).normalized()
		var shade := col.lightened(0.12 * _h(seed + k, 5) - 0.04)
		_leaf(kit, p, along, size, size * 0.42, shade.darkened(0.12), shade)


static func _merge(into: RefCounted, other: RefCounted) -> void:
	into.verts.append_array(other.verts)
	into.norms.append_array(other.norms)
	into.cols.append_array(other.cols)


# ------------------------------------------------------------------------------
#  Trees
# ------------------------------------------------------------------------------
## Card geometry: quads carrying a picture (veg_textures.gd), with UVs.
class Cards:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, col: Color, n: Vector3) -> void:
		for v in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]:
			verts.append(v[0])
			uvs.append(v[1])
			norms.append(n)
			cols.append(col)

	## A frond along a drooping path from `root`: two bent segments, `width` wide,
	## the flat of it turned `tilt` radians about its own length.
	func frond(root: Vector3, dir: Vector3, length: float, width: float, droop: float, tilt: float, col: Color) -> void:
		var flat := Vector3(dir.x, 0.0, dir.z).normalized()
		var side := flat.cross(Vector3.UP).normalized()
		side = side.rotated(flat, tilt)
		var p0 := root
		var p1 := root + flat * length * 0.5 + Vector3(0.0, dir.y * length * 0.5 - droop * 0.25, 0.0)
		var p2 := root + flat * length + Vector3(0.0, dir.y * length - droop, 0.0)
		var p2b := p2 + Vector3(0.0, droop * 0.25, 0.0)      # the tip lifts again
		var hw := width * 0.5
		var n := side.cross((p2 - p0).normalized()).normalized()
		if n.y < 0.0:
			n = -n
		# Soft normals that lean outward so the crown shades as a whole.
		var nn := (n + flat * 0.6 + Vector3.UP * 0.3).normalized()
		quad(p0 - side * hw * 0.35, p0 + side * hw * 0.35, p1 + side * hw, p1 - side * hw,
			Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.5), Vector2(0.0, 0.5), col, nn)
		quad(p1 - side * hw, p1 + side * hw, p2b + side * hw * 0.7, p2b - side * hw * 0.7,
			Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(1.0, 0.0), Vector2(0.0, 0.0), col, nn)

	## A leaf sprig: a square card facing roughly outward and up.
	func sprig(c: Vector3, size: float, facing: Vector3, spin: float, col: Color) -> void:
		var f := facing.normalized()
		var a := f.cross(Vector3.UP)
		if a.length_squared() < 0.001:
			a = Vector3.RIGHT
		a = a.normalized().rotated(f, spin)
		var b := f.cross(a).normalized()
		var h := size * 0.5
		var nn := (f + Vector3.UP * 0.4).normalized()
		quad(c - a * h - b * h, c + a * h - b * h, c + a * h + b * h, c - a * h + b * h,
			Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), col, nn)

	func commit_to(mesh: ArrayMesh) -> void:
		if verts.is_empty():
			return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func tree(kind: int, lod: int, bare: bool) -> ArrayMesh:
	if Flora.outback:
		return _outback_tree(kind, lod)
	var kit := MeshKit.new()
	var cards := MeshKit.new()
	match kind:
		Flora.WHITE_SPRUCE:
			_trunk(kit, 0.5 if lod > 0 else 0.95, 0.016, 0.004, BARK_SPRUCE, 6 if lod == 0 else 3)
			# Same outline at every distance, just fewer tiers and sides further off.
			var tiers: int = [7, 4, 3][lod]
			for k in range(tiers):
				var f := float(k) / float(tiers)
				var y := 0.07 + f * 0.80
				var r := 0.215 * pow(1.0 - f * 0.92, 0.85) + 0.012
				var col := NEEDLE_W.lightened(0.06 * _h(k, 1) - 0.03)
				_tier(kit, y, r, 0.95 / float(tiers) * 1.9 if lod > 0 else 0.28, [9, 6, 4][lod], col, k + 5)
			if lod == 0:
				_tier(kit, 0.86, 0.035, 0.15, 6, NEEDLE_W, 31)
		Flora.BLACK_SPRUCE:
			_trunk(kit, 0.98, 0.012, 0.003, BARK_SPRUCE, 5 if lod == 0 else 3)
			var tufts: int = [10, 3, 1][lod]
			for k in range(tufts):
				var f := float(k) / float(maxi(tufts - 1, 1))
				var y := 0.18 + f * 0.62
				# Short, uneven, drooping branches: a ragged spire, not a stack of plates.
				var r := lerpf(0.075, 0.04, f) * (0.45 + 1.0 * _h(k, 2))
				var off := Vector3(_h(k, 3) - 0.5, 0.0, _h(k, 4) - 0.5) * 0.03
				if lod == 2:
					_tier(kit, 0.15, 0.08, 0.85, 5, NEEDLE_B, 3)
				else:
					_tier(kit, y, r, 0.16, 5, NEEDLE_B.lightened(0.05 * _h(k, 5)), k + 11, off)
			if lod < 2:
				# The club-shaped top black spruce are known for.
				_blob(kit, Vector3(0, 0.9, 0), Vector3(0.07, 0.11, 0.07), NEEDLE_B, 9, 1 if lod == 0 else 0)
		Flora.SNAG:
			# A fire-killed spruce: grey, weathered, charred at the foot, top snapped off.
			_trunk(kit, 0.93, 0.02, 0.006, BARK_SNAG, 6 if lod == 0 else 4)
			kit.cylinder(Transform3D.IDENTITY, 0.0215, 0.019, 0.14 + 0.06 * _h(1, 30), 6 if lod == 0 else 4, CHAR, false)
			if lod < 2:
				var stubs: int = [7, 4, 0][lod]
				for k in range(stubs):
					var a := TAU * _h(k, 31)
					var y := 0.3 + 0.6 * float(k) / float(maxi(stubs, 1))
					var sl := 0.05 + 0.07 * _h(k, 32) * (1.0 - y * 0.6)
					_branch(kit, Vector3(0, y, 0), Vector3(cos(a) * sl, y - 0.02 + 0.04 * _h(k, 33), sin(a) * sl), 0.005, BARK_SNAG.darkened(0.15), 3)
		Flora.BIRCH, Flora.ASPEN, Flora.POPLAR:
			var bark := BARK_BIRCH if kind == Flora.BIRCH else (BARK_ASPEN if kind == Flora.ASPEN else BARK_POPLAR)
			var leaf := LEAF_BIRCH if kind == Flora.BIRCH else (LEAF_ASPEN if kind == Flora.ASPEN else LEAF_POPLAR)
			var tr := 0.022 if kind != Flora.POPLAR else 0.034
			_trunk(kit, 0.72, tr, tr * 0.5, bark, 6 if lod == 0 else 3)
			if kind == Flora.BIRCH and lod == 0:
				# Black marks on white bark
				for k in range(6):
					var y := 0.06 + 0.1 * float(k) + 0.04 * _h(k, 4)
					kit.cylinder(Transform3D(Basis(Vector3.UP, _h(k, 5) * TAU), Vector3(0, y, 0)), tr * 1.04, tr * 1.03, 0.012, 6, Color(0.12, 0.11, 0.10, 0.0), false)
			if bare:
				var n: int = [6, 4, 3][lod]
				for k in range(n):
					var a := TAU * (float(k) + _h(k, 6) * 0.5) / float(n)
					var from := Vector3(0, 0.4 + 0.25 * _h(k, 7), 0)
					var to := from + Vector3(cos(a) * 0.22, 0.32 + 0.1 * _h(k, 8), sin(a) * 0.22)
					_branch(kit, from, to, tr * 0.5, bark.darkened(0.2))
					if lod == 0:
						_branch(kit, to * 0.6 + from * 0.4, to + Vector3(cos(a + 0.8) * 0.1, 0.12, sin(a + 0.8) * 0.1), tr * 0.25, bark.darkened(0.3))
				_branch(kit, Vector3(0, 0.7, 0), Vector3(0.02, 1.0, 0.0), tr * 0.4, bark.darkened(0.2))
			else:
				var blobs: int = [7, 4, 3][lod]
				var detail := 1 if lod == 0 else 0
				var wide := 0.17 if kind == Flora.BIRCH else (0.13 if kind == Flora.ASPEN else 0.23)
				for k in range(blobs):
					var a := TAU * float(k) / float(maxi(blobs, 1)) + _h(k, 9)
					var off := 0.0 if blobs == 1 else wide * (0.5 + 0.35 * _h(k, 10))
					var c := Vector3(cos(a) * off, 0.58 + 0.3 * _h(k, 11) + (0.08 if blobs == 1 else 0.0), sin(a) * off)
					var rr := wide * (0.7 + 0.35 * _h(k, 12)) * (1.6 if blobs == 1 else 1.0)
					var lc := leaf.lightened(0.08 * _h(k, 13) - 0.04)
					_blob(kit, c, Vector3(rr, rr * 1.1, rr), lc, k + 17, detail)
					if lod == 0 and k < blobs - 1:
						_branch(kit, Vector3(0, 0.45 + 0.1 * _h(k, 14), 0), c, tr * 0.45, bark.darkened(0.15), 3)
				if blobs > 1:
					_blob(kit, Vector3(0, 0.9, 0), Vector3(wide * 0.8, wide, wide * 0.8), leaf, 41, 1 if lod == 0 else 0)
	kit.smooth(55.0)
	_merge(kit, cards)
	return kit.commit()


## The near trees (DESIGN_NOTES 144): solid polyart in the look of the
## reference pictures (reference/target_look_polyart_*.png) - not wispy
## picture cards. Each species built the way it grows:
##  - white spruce: a full cone to the ground of layered, drooping boughs with
##    jagged needle edges and upturned tips; a dark core so you can't see
##    through it; a leader spike on top;
##  - black spruce: a narrow, ragged, slightly bent spire of short drooping
##    clumps with gaps, dead stubs low down and the club-shaped top;
##  - paper birch: two stems from one root, white bark with black dashes and a
##    dark base, forked limbs and an open, lumpy crown of leaf clusters;
##  - aspen: one tall, straight, pale trunk with dark eye-scars, bare for the
##    lower half, a narrow oval crown;
##  - poplar: a heavier dark trunk and a broad crown.
## The far forest is baked from these same meshes, so near and far match.
## Foliage carries alpha 1 (season tint and wind sway in veg.gdshader).
const NEEDLE_W_ROOT := Color(0.12, 0.19, 0.13, 1.0)
const NEEDLE_W_TIP := Color(0.30, 0.40, 0.23, 1.0)
const NEEDLE_B_ROOT := Color(0.11, 0.16, 0.11, 1.0)
const NEEDLE_B_TIP := Color(0.24, 0.31, 0.18, 1.0)
const BARK_MARK := Color(0.10, 0.09, 0.08, 0.0)


## One spruce bough: a drooping, tapering spray along a curved path, folded
## along its midrib so it catches the light on two facets, with jagged needle
## teeth down both edges and the tip turned up again. Shades darker at the
## trunk and lighter at the new growth on the tip.
static func _bough(kit: RefCounted, root: Vector3, ang: float, length: float, width: float, slope: float,
		droop: float, lift: float, c0: Color, c1: Color, segs: int, teeth: bool) -> void:
	var flat := Vector3(cos(ang), 0.0, sin(ang))
	var side := Vector3(-sin(ang), 0.0, cos(ang))
	var shade_n := (flat * 0.55 + Vector3.UP * 0.8).normalized()
	var pts: Array = []
	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var up := slope * length * t - droop * t * t + lift * pow(maxf(t - 0.55, 0.0) / 0.45, 2.0)
		var p := root + flat * (length * t) + Vector3.UP * up
		var w := width * (0.22 + 0.78 * sin(PI * minf(t * 0.95 + 0.05, 1.0))) * (1.0 - 0.85 * t * t)
		var col := c0.lerp(c1, t * t)
		pts.append([p, w, col])
	for i in range(segs):
		var p0: Vector3 = pts[i][0]
		var p1: Vector3 = pts[i + 1][0]
		var w0: float = pts[i][1]
		var w1: float = pts[i + 1][1]
		var k0: Color = pts[i][2]
		var k1: Color = pts[i + 1][2]
		var m0 := p0 + Vector3.UP * w0 * 0.22
		var m1 := p1 + Vector3.UP * w1 * 0.22
		var l0 := p0 - side * w0 - Vector3.UP * w0 * 0.12
		var l1 := p1 - side * w1 - Vector3.UP * w1 * 0.12
		var r0 := p0 + side * w0 - Vector3.UP * w0 * 0.12
		var r1 := p1 + side * w1 - Vector3.UP * w1 * 0.12
		var nl := (shade_n - side * 0.35).normalized()
		var nr := (shade_n + side * 0.35).normalized()
		kit.tri_c(m0, l0, l1, k0, k0.darkened(0.12), k1.darkened(0.12), nl, nl, nl)
		kit.tri_c(m0, l1, m1, k0, k1.darkened(0.12), k1, nl, nl, nl)
		kit.tri_c(m0, r1, r0, k0, k1.darkened(0.06), k0.darkened(0.06), nr, nr, nr)
		kit.tri_c(m0, m1, r1, k0, k1, k1.darkened(0.06), nr, nr, nr)
		if teeth and i > 0:
			# needle tufts sticking out of the edges, swept toward the tip
			var dl := (l1 - l0)
			var tl := l0 + dl * 0.5 - side * w0 * 0.55 + flat * length * 0.06 - Vector3.UP * w0 * 0.2
			kit.tri_c(l0, tl, l1, k0.darkened(0.12), k1, k1.darkened(0.12), nl, nl, nl)
			var dr := (r1 - r0)
			var tr := r0 + dr * 0.5 + side * w0 * 0.55 + flat * length * 0.06 - Vector3.UP * w0 * 0.2
			kit.tri_c(r0, r1, tr, k0.darkened(0.06), k1.darkened(0.06), k1, nr, nr, nr)
	# the tip: a last point
	var pl: Vector3 = pts[segs][0]
	var wl: float = pts[segs][1]
	var tip := pl + flat * length * 0.12 + Vector3.UP * lift * 0.15
	var kl: Color = pts[segs][2]
	kit.tri_c(pl - side * wl, tip, pl + side * wl, kl, c1.lightened(0.05), kl, shade_n, shade_n, shade_n)


## A cluster of leaves: a little lumpy core with leaves standing out all over
## it, lit as one mass (lighter on top, darker beneath). The polyart leaf
## clump of the reference pictures.
static func _clump(kit: RefCounted, c: Vector3, r: float, col: Color, leaves: int, seed: int) -> void:
	_blob(kit, c, Vector3(r * 0.85, r * 0.7, r * 0.85), col.darkened(0.18), seed, 0)
	for k in range(leaves):
		var u := _h(seed + k, 61) * 1.6 - 0.6
		var a := _h(seed + k, 62) * TAU
		var s := sqrt(maxf(1.0 - u * u, 0.0))
		var n := Vector3(s * cos(a), u, s * sin(a)).normalized()
		var p := c + n * r * 0.55
		var along := (n + Vector3(0, 0.25, 0)).normalized()
		var shade := col.lightened(0.16 * (n.y * 0.5 + 0.5) - 0.06 + 0.06 * _h(seed + k, 63))
		_leaf(kit, p, along, r * (0.75 + 0.35 * _h(seed + k, 64)), r * 0.32, shade.darkened(0.15), shade)


## A trunk that bends: a chain of tapered pieces through `pts`.
static func _stem(kit: RefCounted, pts: Array, r0: float, r1: float, col: Color, sides: int) -> void:
	var n := pts.size() - 1
	for i in range(n):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var ra := lerpf(r0, r1, float(i) / float(n))
		var rb := lerpf(r0, r1, float(i + 1) / float(n))
		var d := b - a
		var y := d.normalized()
		var x := y.cross(Vector3.FORWARD)
		if x.length_squared() < 0.001:
			x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		var z := x.cross(y)
		kit.cylinder(Transform3D(Basis(x, y, z), a), ra, rb, d.length() * 1.02, sides, col, false)


## A patch of bark marking wrapped part way round a stem at height y.
static func _mark(kit: RefCounted, base: Vector3, axis: Vector3, r: float, y: float, a0: float, arc: float, h: float, col: Color) -> void:
	var up := axis.normalized()
	var x := up.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = up.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(up)
	var steps := 3
	for i in range(steps):
		var t0 := a0 + arc * float(i) / float(steps)
		var t1 := a0 + arc * float(i + 1) / float(steps)
		var d0 := (x * cos(t0) + z * sin(t0)) * r * 1.06
		var d1 := (x * cos(t1) + z * sin(t1)) * r * 1.06
		var c := base + up * y
		kit.quad(c + d0, c + d1, c + d1 + up * h, c + d0 + up * h, col, d0 + d1)


## EZ-Tree trees (DESIGN_NOTES 231, scripts/assets/trees.gd) in place of the
## polyart ones: the mountain region turns this on.
static var eztree := false


static func tree_cards(kind: int, lod: int, bare: bool) -> ArrayMesh:
	if eztree and not Flora.outback:
		return load("res://scripts/assets/trees.gd").veg_mesh(kind, lod, bare)
	if Flora.outback:
		return _outback_tree(kind, 0)
	var kit := MeshKit.new()
	var cards := Cards.new()
	var fine := not lite
	match kind:
		Flora.WHITE_SPRUCE:
			_trunk(kit, 0.97, 0.017, 0.003, BARK_SPRUCE, 6)
			# the dark inside of the crown, so it reads solid
			kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)), 0.09, 0.0, 0.86, 6, NEEDLE_W_ROOT.darkened(0.25), false)
			var whorls := 26 if fine else 18
			for k in range(whorls):
				var f := float(k) / float(whorls)
				var y := 0.035 + f * 0.86
				var reach := (0.205 * pow(1.0 - f * 0.97, 0.85) + 0.018) * (0.85 if f < 0.05 else 1.0)
				var per := (7 if f < 0.6 else (6 if f < 0.85 else 4)) if fine else (5 if f < 0.7 else 4)
				for m in range(per):
					var hh := _h(k * 11 + m, 1)
					var a := TAU * (float(m) + hh * 0.55) / float(per) + float(k) * 2.39996
					var l := reach * (0.82 + 0.3 * _h(k * 11 + m, 2))
					var slope := lerpf(-0.22, 0.32, f)
					var tint := 0.06 * _h(k * 11 + m, 3) - 0.03
					_bough(kit, Vector3(0, y, 0), a, l, l * 0.42, slope, l * lerpf(0.42, 0.12, f), l * 0.18,
						NEEDLE_W_ROOT.lightened(tint), NEEDLE_W_TIP.lightened(tint), 3 if fine else 2, f < 0.9)
			# the leader and the last little whorl round it
			_branch(kit, Vector3(0, 0.88, 0), Vector3(0, 1.0, 0), 0.006, NEEDLE_W_TIP.darkened(0.2), 4)
			for m in range(4):
				_bough(kit, Vector3(0, 0.93, 0), TAU * float(m) / 4.0 + 0.4, 0.035, 0.016, 0.9, 0.0, 0.0,
					NEEDLE_W_ROOT, NEEDLE_W_TIP, 2, false)
		Flora.BLACK_SPRUCE:
			# a thin stem with a bit of a lean and a kink - they grow on soggy ground
			var pts: Array = []
			for i in range(6):
				var t := float(i) / 5.0
				pts.append(Vector3(0.025 * t * t + 0.006 * sin(t * 7.0), t * 0.98, 0.012 * t))
			_stem(kit, pts, 0.012, 0.003, BARK_SPRUCE, 5)
			var at := func(y: float) -> Vector3:
				var t := y / 0.98
				return Vector3(0.025 * t * t + 0.006 * sin(t * 7.0), y, 0.012 * t)
			# dead stubs low down
			for k in range(6):
				var y0 := 0.06 + 0.16 * float(k) / 6.0
				var a0 := TAU * _h(k, 70)
				var r0: Vector3 = at.call(y0)
				_branch(kit, r0, r0 + Vector3(cos(a0) * 0.05, -0.01, sin(a0) * 0.05), 0.004, BARK_SNAG.darkened(0.25), 3)
			# short, drooping clumps, ragged, with gaps
			var n := 34 if fine else 22
			for k in range(n):
				var f := float(k) / float(n)
				if _h(k, 71) < 0.22:
					continue
				var y := 0.2 + f * 0.62
				var reach := lerpf(0.075, 0.035, f) * (0.45 + 0.9 * _h(k, 72))
				var cnt := 3 if _h(k, 73) < 0.6 else 4
				for m in range(cnt):
					var a := TAU * (float(m) / float(cnt) + 0.3 * _h(k * 5 + m, 74)) + float(k) * 2.1
					var tint := 0.05 * _h(k * 5 + m, 75) - 0.025
					_bough(kit, at.call(y), a, reach, reach * 0.55, -0.35, reach * 0.45, reach * 0.12,
						NEEDLE_B_ROOT.lightened(tint), NEEDLE_B_TIP.lightened(tint), 2, true)
			# the club on top: a dense knot of short boughs
			for k in range(14 if fine else 9):
				var y2 := 0.80 + 0.14 * _h(k, 76)
				var a2 := TAU * _h(k, 77)
				var l2 := 0.04 + 0.025 * _h(k, 78)
				_bough(kit, at.call(y2), a2, l2, l2 * 0.7, -0.2 + 0.6 * _h(k, 79), l2 * 0.2, 0.0,
					NEEDLE_B_ROOT, NEEDLE_B_TIP, 2, false)
			_blob(kit, at.call(0.88), Vector3(0.045, 0.08, 0.045), NEEDLE_B_ROOT, 9, 0)
			_branch(kit, at.call(0.9), at.call(1.0), 0.004, NEEDLE_B_TIP.darkened(0.2), 3)
		Flora.SNAG:
			_trunk(kit, 0.93, 0.02, 0.006, BARK_SNAG, 6)
			kit.cylinder(Transform3D.IDENTITY, 0.0215, 0.019, 0.14 + 0.06 * _h(1, 30), 6, CHAR, false)
			for k in range(7):
				var a := TAU * _h(k, 31)
				var y := 0.3 + 0.6 * float(k) / 7.0
				var sl := 0.05 + 0.07 * _h(k, 32) * (1.0 - y * 0.6)
				_branch(kit, Vector3(0, y, 0), Vector3(cos(a) * sl, y - 0.02 + 0.04 * _h(k, 33), sin(a) * sl), 0.005, BARK_SNAG.darkened(0.15), 3)
		Flora.BIRCH:
			_birch(kit, bare, fine)
		Flora.ASPEN, Flora.POPLAR:
			_aspen(kit, kind == Flora.POPLAR, bare, fine)
	kit.smooth(55.0)
	var mesh := kit.commit()
	cards.commit_to(mesh)
	return mesh


## Paper birch: two stems from one root, leaning apart.
static func _birch(kit: RefCounted, bare: bool, fine: bool) -> void:
	var stems := [[0.3, 0.11, 0.95, 0.017], [3.5, 0.08, 0.86, 0.014]]
	var ci := 0
	for st in stems:
		var a: float = st[0]
		var lean: float = st[1]
		var top: float = st[2]
		var r: float = st[3]
		var out := Vector3(cos(a), 0, sin(a))
		var pts: Array = []
		for i in range(5):
			var t := float(i) / 4.0
			pts.append(out * (0.012 + lean * t * (0.6 + 0.4 * t)) + Vector3(0.01 * sin(t * 5.0 + a), top * t, 0))
		_stem(kit, pts, r, r * 0.35, BARK_BIRCH, 6)
		# the dark, rough base, then black dashes and patches up the white bark
		var b0: Vector3 = pts[0]
		var b1: Vector3 = pts[1]
		_mark(kit, b0, b1 - b0, r * 1.02, 0.0, 0.0, TAU, 0.05 + 0.02 * _h(ci, 80), Color(0.20, 0.18, 0.16, 0.0))
		for k in range(14 if fine else 8):
			var t := 0.08 + 0.5 * _h(ci * 31 + k, 81)
			var seg := mini(int(t * 4.0), 3)
			var pa: Vector3 = pts[seg]
			var pb: Vector3 = pts[seg + 1]
			var lt := t * 4.0 - float(seg)
			var rr := lerpf(r, r * 0.35, t)
			_mark(kit, pa, pb - pa, rr, (pb - pa).length() * lt, TAU * _h(ci * 31 + k, 82), 0.6 + 1.6 * _h(ci * 31 + k, 83),
				0.004 + 0.008 * _h(ci * 31 + k, 84), BARK_MARK)
		# limbs angled up out of the upper stem, each forking once
		var limbs := 9 if fine else 6
		for k in range(limbs):
			var t2 := 0.38 + 0.55 * float(k) / float(limbs)
			var seg2 := mini(int(t2 * 4.0), 3)
			var pa2: Vector3 = pts[seg2]
			var pb2: Vector3 = pts[seg2 + 1]
			var from: Vector3 = pa2.lerp(pb2, t2 * 4.0 - float(seg2))
			var la := a + TAU * (float(k) * 0.382 + 0.2 * _h(ci * 17 + k, 85))
			var reach := (0.16 - 0.1 * (t2 - 0.38)) * (0.8 + 0.4 * _h(ci * 17 + k, 86))
			var dir := Vector3(cos(la), 0.0, sin(la)) + out * 0.5
			var to := from + dir.normalized() * reach + Vector3(0, reach * (0.7 + 0.4 * _h(ci * 17 + k, 87)), 0)
			_branch(kit, from, to, r * 0.32, BARK_BIRCH.darkened(0.35), 4)
			var fk := to + Vector3(cos(la + 0.9) * reach * 0.4, reach * 0.35, sin(la + 0.9) * reach * 0.4)
			_branch(kit, from.lerp(to, 0.6), fk, r * 0.18, BARK_BIRCH.darkened(0.45), 3)
			if not bare:
				var lc := LEAF_BIRCH.lightened(0.08 * _h(ci * 17 + k, 88) - 0.04)
				_clump(kit, to, 0.075 + 0.03 * _h(ci * 17 + k, 89), lc, 9 if fine else 6, ci * 100 + k * 7)
				_clump(kit, fk, 0.06 + 0.025 * _h(ci * 17 + k, 90), lc.lightened(0.03), 7 if fine else 5, ci * 100 + k * 7 + 3)
				if fine:
					_clump(kit, from.lerp(to, 0.5) + Vector3(0, 0.03, 0), 0.05, lc.darkened(0.05), 5, ci * 100 + k * 7 + 5)
		if not bare:
			var tp: Vector3 = pts[4]
			_clump(kit, tp + Vector3(0, 0.02, 0), 0.08, LEAF_BIRCH.lightened(0.04), 9 if fine else 6, ci * 100 + 90)
		ci += 1


## Aspen (and the balsam poplar, heavier and darker): one straight trunk,
## bare low down, a narrow crown of small clumps.
static func _aspen(kit: RefCounted, poplar: bool, bare: bool, fine: bool) -> void:
	var bark := BARK_POPLAR if poplar else BARK_ASPEN
	var leaf := LEAF_POPLAR if poplar else LEAF_ASPEN
	var r := 0.03 if poplar else 0.018
	var wide := 0.2 if poplar else 0.11
	var crown0 := 0.42 if poplar else 0.55
	var pts: Array = []
	for i in range(5):
		var t := float(i) / 4.0
		pts.append(Vector3(0.008 * sin(t * 4.0), 0.98 * t, 0.006 * sin(t * 3.0 + 1.0)))
	_stem(kit, pts, r, r * 0.3, bark, 6)
	var b0: Vector3 = pts[0]
	var b1: Vector3 = pts[1]
	_mark(kit, b0, b1 - b0, r * 1.02, 0.0, 0.0, TAU, 0.07, bark.darkened(0.55))
	if not poplar:
		# the dark eye-scars where old branches dropped off
		for k in range(10 if fine else 6):
			var t := 0.1 + 0.45 * _h(k, 91)
			var seg := mini(int(t * 4.0), 3)
			var pa: Vector3 = pts[seg]
			var pb: Vector3 = pts[seg + 1]
			_mark(kit, pa, pb - pa, lerpf(r, r * 0.3, t), (pb - pa).length() * (t * 4.0 - float(seg)), TAU * _h(k, 92), 0.7, 0.008, BARK_MARK)
	var limbs := 12 if fine else 8
	for k in range(limbs):
		var t2 := crown0 + (0.93 - crown0) * float(k) / float(limbs)
		var from := Vector3(0, 0.98 * t2, 0)
		var la := TAU * (float(k) * 0.382 + 0.15 * _h(k, 93))
		var reach := wide * (1.0 - 0.6 * pow((t2 - crown0) / (1.0 - crown0), 1.5)) * (0.75 + 0.4 * _h(k, 94))
		var to := from + Vector3(cos(la) * reach, reach * (0.9 + 0.5 * _h(k, 95)), sin(la) * reach)
		_branch(kit, from, to, r * 0.3, bark.darkened(0.25), 4)
		if not bare:
			var lc := leaf.lightened(0.08 * _h(k, 96) - 0.04)
			_clump(kit, to, wide * (0.42 + 0.15 * _h(k, 97)), lc, 9 if fine else 6, k * 13 + 400)
			_clump(kit, from.lerp(to, 0.5) + Vector3(0, wide * 0.15, 0), wide * 0.33, lc.darkened(0.04), 6 if fine else 4, k * 13 + 405)
	if not bare:
		_clump(kit, Vector3(0, 1.0, 0), wide * 0.45, leaf.lightened(0.05), 9 if fine else 6, 470)
		_clump(kit, Vector3(0, 0.9, 0), wide * 0.5, leaf, 8 if fine else 5, 471)


# ------------------------------------------------------------------------------
#  Shrubs
# ------------------------------------------------------------------------------
## Lighter plants for slower computers: fewer blades, leaves and fronds
## (set from the graphics settings before any plant is built).
static var lite := true


static func _n(full: int, light: int) -> int:
	return light if lite else full


static func shrub(kind: int, bare: bool) -> ArrayMesh:
	if Flora.outback:
		return _outback_shrub(kind)
	var kit := MeshKit.new()
	var cards := MeshKit.new()
	match kind:
		Flora.ALDER:
			# Many grey stems from one root, leaning out; a lumpy crown of leaves.
			var stem := Color(0.45, 0.44, 0.40, 0.0)
			var ns := _n(7, 4)
			for k in range(ns):
				var a := TAU * (float(k) + 0.4 * _h(k, 101)) / float(ns)
				var lean := 0.25 + 0.2 * _h(k, 102)
				var top := Vector3(cos(a) * lean, 0.8 + 0.2 * _h(k, 103), sin(a) * lean)
				_branch(kit, Vector3(cos(a) * 0.05, 0, sin(a) * 0.05), top, 0.022, stem)
				if not bare:
					for m in range(_n(2, 1)):
						var c := top * (0.75 + 0.25 * float(m)) + Vector3(0, 0.05 * float(m), 0)
						var rr := 0.13 + 0.07 * _h(k * 2 + m, 104)
						var lc := LEAF_ALDER.lightened(0.07 * _h(k * 2 + m, 105) - 0.03)
						_blob(kit, c, Vector3(rr * 1.2, rr, rr * 1.2), lc, k * 2 + m + 3, 1)
						_fringe(cards, c, Vector3(rr * 1.2, rr, rr * 1.2), lc, _n(6, 2), 0.03, k * 7 + m)
		Flora.WILLOW:
			# Slender reddish stems, more upright; narrow grey-green leaves.
			var stem := Color(0.42, 0.30, 0.22, 0.0)
			var nw := _n(9, 5)
			for k in range(nw):
				var a := TAU * (float(k) + 0.5 * _h(k, 111)) / float(nw)
				var lean := 0.12 + 0.2 * _h(k, 112)
				var top := Vector3(cos(a) * lean, 0.75 + 0.25 * _h(k, 113), sin(a) * lean)
				_branch(kit, Vector3(cos(a) * 0.04, 0, sin(a) * 0.04), top, 0.014, stem)
				if not bare and k % 3 != 2:
					var c := top * 0.82
					var rr := 0.09 + 0.05 * _h(k, 114)
					var lc := LEAF_WILLOW.lightened(0.08 * _h(k, 115) - 0.04)
					_blob(kit, c, Vector3(rr, rr * 1.7, rr), lc, k + 13, 1)
					_fringe(cards, c, Vector3(rr, rr * 1.7, rr), lc, _n(7, 2), 0.035, k * 11 + 5)
		_:
			# Dwarf birch: a low, twiggy mat of small round leaves.
			var twig := Color(0.30, 0.22, 0.17, 0.0)
			var nb := _n(9, 5)
			for k in range(nb):
				var a := TAU * (float(k) + 0.5 * _h(k, 121)) / float(nb)
				var reach := 0.35 + 0.25 * _h(k, 122)
				var top := Vector3(cos(a) * reach, 0.35 + 0.35 * _h(k, 123), sin(a) * reach)
				_branch(kit, Vector3.ZERO, top, 0.012, twig, 3)
				if not bare:
					var rr := 0.13 + 0.06 * _h(k, 124)
					var lc := LEAF_DBIRCH.lightened(0.08 * _h(k, 125) - 0.04)
					_blob(kit, top * 0.85, Vector3(rr * 1.3, rr * 0.8, rr * 1.3), lc, k + 21, 1)
					_fringe(cards, top * 0.85, Vector3(rr * 1.3, rr * 0.8, rr * 1.3), lc, _n(6, 2), 0.04, k * 13 + 7)
	kit.smooth(55.0)
	_merge(kit, cards)
	return kit.commit()


## The remade shrubs: real stems with textured leaf-card foliage, no solid
## blobs. Same silhouettes nature grows: alder fans out, willow stands up,
## dwarf birch mats low.
static func shrub_cards(kind: int, bare: bool) -> ArrayMesh:
	if Flora.outback:
		return _outback_shrub(kind)
	var kit := MeshKit.new()
	var cards := Cards.new()
	match kind:
		Flora.ALDER:
			var stem := Color(0.45, 0.44, 0.40, 0.0)
			for k in range(8):
				var a := TAU * (float(k) + 0.4 * _h(k, 101)) / 8.0
				var lean := 0.28 + 0.22 * _h(k, 102)
				var top := Vector3(cos(a) * lean, 0.75 + 0.25 * _h(k, 103), sin(a) * lean)
				_branch(kit, Vector3(cos(a) * 0.05, 0, sin(a) * 0.05), top, 0.022, stem)
				if not bare:
					for m in range(4):
						var f := 0.55 + 0.15 * float(m)
						var c := top * f + Vector3((_h(k * 5 + m, 104) - 0.5) * 0.14, 0.03 * float(m), (_h(k * 5 + m, 105) - 0.5) * 0.14)
						var out := Vector3(cos(a), 0.45 + 0.3 * _h(k * 5 + m, 106), sin(a))
						cards.sprig(c, 0.20 + 0.12 * _h(k * 5 + m, 107), out, _h(k * 5 + m, 108) * TAU,
							LEAF_ALDER.lightened(0.09 * _h(k * 5 + m, 109) - 0.04))
		Flora.WILLOW:
			var stem := Color(0.42, 0.30, 0.22, 0.0)
			for k in range(10):
				var a := TAU * (float(k) + 0.5 * _h(k, 111)) / 10.0
				var lean := 0.10 + 0.18 * _h(k, 112)
				var top := Vector3(cos(a) * lean, 0.72 + 0.28 * _h(k, 113), sin(a) * lean)
				_branch(kit, Vector3(cos(a) * 0.04, 0, sin(a) * 0.04), top, 0.014, stem)
				if not bare:
					for m in range(3):
						var f := 0.6 + 0.18 * float(m)
						var c := top * f + Vector3((_h(k * 4 + m, 114) - 0.5) * 0.08, 0.0, (_h(k * 4 + m, 115) - 0.5) * 0.08)
						var out := Vector3(cos(a) * 0.6, 0.9, sin(a) * 0.6)
						cards.sprig(c, 0.13 + 0.09 * _h(k * 4 + m, 116), out, _h(k * 4 + m, 117) * TAU,
							LEAF_WILLOW.lightened(0.1 * _h(k * 4 + m, 118) - 0.05))
		_:
			var twig := Color(0.30, 0.22, 0.17, 0.0)
			for k in range(9):
				var a := TAU * (float(k) + 0.5 * _h(k, 121)) / 9.0
				var reach := 0.35 + 0.25 * _h(k, 122)
				var top := Vector3(cos(a) * reach, 0.30 + 0.30 * _h(k, 123), sin(a) * reach)
				_branch(kit, Vector3.ZERO, top, 0.012, twig, 3)
				if not bare:
					for m in range(3):
						var c := top * (0.6 + 0.2 * float(m))
						cards.sprig(c, 0.10 + 0.07 * _h(k * 4 + m, 124), Vector3(cos(a), 0.8, sin(a)),
							_h(k * 4 + m, 125) * TAU, LEAF_DBIRCH.lightened(0.09 * _h(k * 4 + m, 126) - 0.04))
	kit.smooth(55.0)
	var mesh := kit.commit()
	cards.commit_to(mesh)
	return mesh


# ------------------------------------------------------------------------------
#  Ground plants
# ------------------------------------------------------------------------------
## A ground plant instance is a small clump of several plants, so the ground
## fills in without needing a huge number of instances.
const CLUMPS := {0: [3, 0.7], 1: [2, 0.4], 2: [3, 0.6], 3: [2, 0.5], 4: [4, 0.6], 5: [2, 0.45]}


static func ground(kind: int) -> ArrayMesh:
	var one := _ground_one(kind)
	var kit := MeshKit.new()
	var spec: Array = CLUMPS[kind]
	var count: int = spec[0] if not lite else maxi(1, int(spec[0]) - 1)
	var spread: float = spec[1]
	for k in range(count):
		var a := TAU * (float(k) / float(count) + 0.3 * _h(k, 201))
		var r := 0.0 if k == 0 else spread * (0.45 + 0.55 * _h(k, 202))
		var sc := 1.0 if k == 0 else 0.6 + 0.4 * _h(k, 203)
		var xf := Transform3D(Basis(Vector3.UP, TAU * _h(k, 204)).scaled(Vector3(sc, sc * (0.85 + 0.3 * _h(k, 205)), sc)),
			Vector3(cos(a) * r, 0.0, sin(a) * r))
		for i in range(one.verts.size()):
			kit.verts.append(xf * one.verts[i])
			kit.norms.append((xf.basis * one.norms[i]).normalized())
			kit.cols.append(one.cols[i])
	return kit.commit()


static func _ground_one(kind: int) -> RefCounted:
	if Flora.outback:
		return _outback_ground(kind)
	var kit := MeshKit.new()
	var solid := MeshKit.new()
	match kind:
		Flora.GRASS:
			# Bluejoint: a loose tuft of arching blades, dark at the root and
			# straw at the tips, a few dry ones and some purple-brown seed heads.
			for k in range(_n(18, 7)):
				var a := TAU * _h(k, 51)
				var rr := 0.08 * sqrt(_h(k, 52))
				var base := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
				var hgt := 0.35 + 0.5 * _h(k, 53)
				var tip := STRAW if _h(k, 54) < 0.15 else GRASS_TIP.lerp(GRASS_MID, 0.6 * _h(k, 55))
				_blade(kit, base, a + 0.3 * (_h(k, 56) - 0.5), hgt, 0.1 + 0.32 * _h(k, 57), 0.042, GRASS_ROOT, GRASS_MID, tip, 2)
			for k in range(_n(3, 1)):
				var a2 := TAU * _h(k, 58)
				var b := Vector3(cos(a2) * 0.03, 0, sin(a2) * 0.03)
				var hh := 0.95 + 0.25 * _h(k, 59)
				_blade(kit, b, a2, hh, 0.12, 0.006, GRASS_MID, GRASS_MID, Color(0.50, 0.45, 0.32, 1.0), 2)
				var head := b + Vector3(cos(a2) * 0.12, hh * 0.97, sin(a2) * 0.12)
				for m in range(2):
					var ang := a2 + PI * 0.5 * float(m)
					_leaf(kit, head - Vector3(0, 0.14, 0), Vector3(cos(ang) * 0.15, 1.0, sin(ang) * 0.15), 0.17, 0.018,
						Color(0.40, 0.33, 0.30, 1.0), Color(0.50, 0.42, 0.36, 1.0))
		Flora.FIREWEED:
			# A small stand of stems: narrow leaves up the stalk and a spike of
			# magenta flowers at the top, buds at the very tip.
			var leaf_c := Color(0.30, 0.36, 0.21, 1.0)
			var petal := Color(0.66, 0.32, 0.50, 1.0)
			for st in range(_n(3, 2)):
				var a := TAU * _h(st, 61)
				var base := Vector3(cos(a), 0, sin(a)) * (0.05 + 0.1 * _h(st, 62))
				var hh := 0.75 + 0.3 * _h(st, 63)
				var bend := Vector3(cos(a) * 0.04, 0, sin(a) * 0.04)
				_branch(solid, base, base + bend + Vector3(0, hh, 0), 0.007, Color(0.40, 0.25, 0.22, 0.0), 3)
				var n := _n(9, 4)
				for k in range(n):
					var t := 0.1 + 0.55 * float(k) / float(n)
					var ang := float(k) * 2.4 + a
					var p := base + bend * t + Vector3(0, hh * t, 0)
					var ll := 0.15 * (1.0 - t * 0.6)
					_leaf(kit, p, Vector3(cos(ang), 0.55, sin(ang)), ll, 0.022, leaf_c.darkened(0.1), leaf_c)
				for k in range(_n(8, 4)):
					var t2 := 0.68 + 0.27 * float(k) / 8.0
					var ang2 := float(k) * 2.2 + a
					var p2 := base + bend * t2 + Vector3(0, hh * t2, 0)
					var out := Vector3(cos(ang2), 0.15, sin(ang2)) * 0.035
					var col := petal.lerp(Color(0.48, 0.26, 0.36, 1.0), clampf((t2 - 0.85) * 6.0, 0.0, 1.0))
					_leaf(kit, p2, out + Vector3(0, 0.02, 0), 0.045, 0.022, col.darkened(0.1), col)
					_leaf(kit, p2, Vector3(-out.z, 0.02, out.x), 0.04, 0.02, col.darkened(0.1), col)
		Flora.TUSSOCK, Flora.COTTON:
			# Sedge tussock: a mound of old dead thatch with fine blades fanning out.
			var big := kind == Flora.TUSSOCK
			_blob(solid, Vector3(0, 0.04, 0), Vector3(0.13, 0.09, 0.13) * (1.0 if big else 0.8), Color(0.30, 0.29, 0.19, 0.0), 131, 1)
			var blades := _n(26, 9) if big else _n(18, 7)
			for k in range(blades):
				var a := TAU * _h(k, 141)
				var base := Vector3(cos(a) * 0.07 * _h(k, 145), 0.05, sin(a) * 0.07 * _h(k, 145))
				var dry := _h(k, 142) < 0.2
				_blade(kit, base, a, 0.22 + 0.25 * _h(k, 143), 0.2 + 0.18 * _h(k, 144), 0.02,
					THATCH if dry else Color(0.30, 0.31, 0.19, 1.0), STRAW if dry else Color(0.42, 0.42, 0.26, 1.0),
					STRAW.lightened(0.05) if dry else Color(0.54, 0.51, 0.33, 1.0), 2)
			if not big:
				# Cotton grass: thin stems with white tufts.
				for k in range(_n(6, 3)):
					var a2 := TAU * _h(k, 151)
					var b := Vector3(cos(a2) * 0.05, 0.1, sin(a2) * 0.05)
					var top := b + Vector3(cos(a2) * 0.06, 0.32 + 0.18 * _h(k, 152), sin(a2) * 0.06)
					_branch(solid, b, top, 0.004, Color(0.34, 0.32, 0.22, 0.0), 3)
					_blob(solid, top + Vector3(0, 0.025, 0), Vector3(0.028, 0.034, 0.028), Color(0.93, 0.92, 0.88, 0.0), k + 160, 1)
		Flora.LOWSHRUB:
			# Labrador tea, crowberry and blueberry: a low, leafy mat of woody
			# stems, the leaves dark green with some bronze ones.
			var stem := Color(0.28, 0.22, 0.17, 0.0)
			_blob(solid, Vector3(0, 0.1, 0), Vector3(0.2, 0.1, 0.2), Color(0.20, 0.24, 0.14, 1.0), 170, 1)
			var ns := _n(8, 5)
			for k in range(ns):
				var a := TAU * (float(k) + 0.5 * _h(k, 171)) / float(ns)
				var reach := 0.14 + 0.16 * _h(k, 172)
				var top := Vector3(cos(a) * reach, 0.16 + 0.12 * _h(k, 173), sin(a) * reach)
				_branch(solid, Vector3.ZERO, top, 0.007, stem, 3)
				for m in range(_n(9, 3)):
					var t := 0.25 + 0.75 * float(m) / float(_n(9, 3))
					var ang := a + float(m) * 2.4
					var p := top * t + Vector3(cos(ang), 0, sin(ang)) * 0.02
					var bronze := _h(k * 12 + m, 174) < 0.18
					var c1 := Color(0.38, 0.27, 0.18, 1.0) if bronze else Color(0.25, 0.30, 0.17, 1.0).lightened(0.08 * _h(k * 12 + m, 175))
					_leaf(kit, p, Vector3(cos(ang), 0.55, sin(ang)), 0.075, 0.03, c1.darkened(0.15), c1)
		_:
			# Fern: arching fronds of leaflets that shrink toward the tip.
			var c0 := Color(0.26, 0.34, 0.18, 1.0)
			var c1 := Color(0.40, 0.49, 0.26, 1.0)
			var nf := _n(6, 4)
			for k in range(nf):
				var a := TAU * (float(k) + 0.4 * _h(k, 181)) / float(nf)
				var out := Vector3(cos(a), 0, sin(a))
				var side := Vector3(-sin(a), 0, cos(a))
				var length := 0.6 + 0.25 * _h(k, 182)
				var steps := _n(7, 4)
				for m in range(1, steps + 1):
					var t := float(m) / float(steps + 1)
					var p := out * (length * 0.75 * t) + Vector3.UP * (length * (0.95 * t - 0.62 * t * t))
					var ll := 0.13 * pow(1.0 - t, 0.7) + 0.02
					var fwd := out * 0.35
					var col := c0.lerp(c1, t)
					_leaf(kit, p, side + fwd + Vector3(0, -0.15, 0), ll, ll * 0.3, col.darkened(0.1), col)
					_leaf(kit, p, -side + fwd + Vector3(0, -0.15, 0), ll, ll * 0.3, col.darkened(0.1), col)
	solid.smooth(50.0)
	_merge(kit, solid)
	return kit


static func rock(variant: int) -> ArrayMesh:
	# A crag: a broken, lumpy outcrop wider than it is tall, with jutting
	# shoulders and a ragged top. One unit across, buried at the foot.
	var kit := MeshKit.new()
	var base_tone: Color = [Color(0.55, 0.50, 0.44, 0.0), Color(0.50, 0.47, 0.42, 0.0), Color(0.60, 0.55, 0.48, 0.0)][variant % 3]
	if Flora.outback:
		# Red ironstone and weathered sandstone.
		base_tone = [Color(0.62, 0.32, 0.20, 0.0), Color(0.54, 0.27, 0.17, 0.0), Color(0.70, 0.42, 0.27, 0.0)][variant % 3]
	var sides := 11
	var rings := 6
	var lumps := PackedFloat32Array()
	for k in range(sides):
		lumps.append(0.62 + 0.55 * _h(k, 70 + variant))
	var all_rings: Array = []
	for L in range(rings):
		var f := float(L) / float(rings - 1)
		var y := lerpf(-0.35, 0.62 + 0.18 * _h(variant, 61), f)
		var prof := sqrt(maxf(1.0 - f * f * 0.92, 0.0)) * 0.55
		var lean := Vector3(0.08 * (_h(L, 62 + variant) - 0.5), 0.0, -0.12 * f)   # leans out of the slope
		var ring := PackedVector3Array()
		for k in range(sides):
			var a := TAU * float(k) / float(sides)
			var jr := lumps[k] * (0.8 + 0.4 * _h(L * 13 + k, 75 + variant))
			ring.append(Vector3(cos(a) * prof * jr, y + 0.06 * (_h(k + L * 7, 81 + variant) - 0.5), sin(a) * prof * jr * 0.8) + lean)
		all_rings.append(ring)
	# The top closes on a ragged point rather than a dome.
	var top := PackedVector3Array()
	var peak: Vector3 = (all_rings[rings - 1][0] as Vector3) * 0.0 + Vector3(0.05 * (_h(variant, 90) - 0.5), 0.7 + 0.2 * _h(variant, 91), -0.14)
	for k in range(sides):
		top.append(peak)
	all_rings.append(top)
	kit.loft(all_rings, base_tone, true, false)
	return kit.commit()


# ------------------------------------------------------------------------------
#  The Outback (DESIGN_NOTES 108): eucalypts and desert plants, same kinds
# ------------------------------------------------------------------------------
const GUM_BARK := Color(0.66, 0.60, 0.52, 0.0)
const GUM_LEAF := Color(0.40, 0.46, 0.30, 1.0)
const GHOST_BARK := Color(0.94, 0.93, 0.89, 0.0)
const GHOST_LEAF := Color(0.46, 0.55, 0.30, 1.0)
const REDGUM_BARK := Color(0.72, 0.66, 0.58, 0.0)
const REDGUM_LEAF := Color(0.35, 0.42, 0.27, 1.0)
const MALLEE_BARK := Color(0.62, 0.50, 0.40, 0.0)
const MALLEE_LEAF := Color(0.46, 0.50, 0.31, 1.0)
const OAK_BARK := Color(0.30, 0.24, 0.20, 0.0)
const OAK_LEAF := Color(0.27, 0.31, 0.23, 1.0)
const DEAD_BARK := Color(0.74, 0.72, 0.68, 0.0)


## A eucalypt limb ending in a few flat, open clumps of leaves (gum crowns
## are clumpy with sky showing through, not one round ball).
static func _gum_limb(kit: RefCounted, from: Vector3, to: Vector3, r: float, bark: Color, leaf: Color, clump: float, seed: int, detail: int) -> void:
	_branch(kit, from, to, r, bark, 5)
	var out := Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
	for m in range(3):
		var a := float(m) * 2.1 + _h(seed, m + 1) * 1.5
		var side := Vector3(cos(a), 0.0, sin(a))
		var c := to + side * clump * 0.7 + out * clump * 0.3 + Vector3(0, clump * (0.2 + 0.35 * _h(seed, m + 5)), 0)
		_branch(kit, to, c, r * 0.5, bark.darkened(0.1), 3)
		var rr := clump * (0.75 + 0.4 * _h(seed, m + 9))
		_blob(kit, c, Vector3(rr, rr * 0.55, rr), leaf.lightened(0.10 * _h(seed, m + 13) - 0.05), seed * 7 + m, detail)


static func _outback_tree(kind: int, lod: int) -> ArrayMesh:
	var kit := MeshKit.new()
	var detail := 1 if lod == 0 else 0
	match kind:
		Flora.WHITE_SPRUCE, Flora.POPLAR:
			# A gum / river red gum: a stout trunk that forks low into a few
			# big leaning limbs, a broad, open, clumpy crown.
			var red := kind == Flora.POPLAR
			var bark := REDGUM_BARK if red else GUM_BARK
			var leaf := REDGUM_LEAF if red else GUM_LEAF
			var tr := 0.05 if red else 0.035
			var fork := 0.30 if red else 0.38
			var lean := Vector3(0.05, 0, 0.02)
			kit.cylinder(Transform3D.IDENTITY, tr, tr * 0.8, fork, 7, bark, false)
			# Mottled bark: paler patches where the old bark has shed.
			for k in range(4):
				kit.cylinder(Transform3D(Basis(Vector3.UP, _h(k, 301) * TAU), Vector3(0, 0.05 + 0.06 * float(k), 0)), tr * 1.02, tr * 0.98, 0.03, 7, bark.lightened(0.18), false)
			var limbs := 4 if red else 3
			var spread := 0.36 if red else 0.27
			for k in range(limbs):
				var a := TAU * (float(k) + 0.35 * _h(k, 302)) / float(limbs)
				var from := Vector3(0, fork, 0) + lean * 0.5
				var mid := from + Vector3(cos(a) * spread * 0.55, 0.18 + 0.08 * _h(k, 303), sin(a) * spread * 0.55)
				_branch(kit, from, mid, tr * 0.6, bark, 5)
				var to := mid + Vector3(cos(a + 0.4) * spread * 0.5, 0.17 + 0.12 * _h(k, 304), sin(a + 0.4) * spread * 0.5)
				_gum_limb(kit, mid, to, tr * 0.4, bark, leaf, 0.13 if red else 0.11, k + (40 if red else 20), detail)
			# A leader up the middle with its own clumps.
			_gum_limb(kit, Vector3(0, fork, 0), Vector3(0.03, 0.82, 0.02), tr * 0.4, bark, leaf, 0.1, 60 if red else 61, detail)
		Flora.BIRCH:
			# Ghost gum: smooth chalk-white trunk and limbs sweeping up, a light
			# airy crown of bright leaves high up.
			kit.cylinder(Transform3D.IDENTITY, 0.024, 0.016, 0.5, 7, GHOST_BARK, false)
			for k in range(4):
				var a := TAU * (float(k) + 0.4 * _h(k, 311)) / 4.0
				var from := Vector3(0, 0.42 + 0.08 * _h(k, 312), 0)
				var to := from + Vector3(cos(a) * 0.17, 0.3 + 0.12 * _h(k, 313), sin(a) * 0.17)
				_gum_limb(kit, from, to, 0.011, GHOST_BARK, GHOST_LEAF, 0.08, k + 70, detail)
			_gum_limb(kit, Vector3(0, 0.5, 0), Vector3(0.02, 0.88, 0.0), 0.01, GHOST_BARK, GHOST_LEAF, 0.08, 75, detail)
		Flora.BLACK_SPRUCE:
			# Mallee: many thin stems from one root, fanning out, an umbrella of
			# small leaf clumps on top.
			var n := 6
			for k in range(n):
				var a := TAU * (float(k) + 0.4 * _h(k, 321)) / float(n)
				var top := Vector3(cos(a) * (0.16 + 0.1 * _h(k, 322)), 0.62 + 0.18 * _h(k, 323), sin(a) * (0.16 + 0.1 * _h(k, 322)))
				_branch(kit, Vector3(cos(a) * 0.02, 0.0, sin(a) * 0.02), top, 0.012, MALLEE_BARK, 4)
				var rr := 0.1 + 0.04 * _h(k, 324)
				_blob(kit, top + Vector3(0, 0.05, 0), Vector3(rr, rr * 0.55, rr), MALLEE_LEAF.lightened(0.08 * _h(k, 325) - 0.04), k + 80, detail)
		Flora.ASPEN:
			# Desert oak: a straight dark trunk and a tall, drooping crown of
			# fine grey-green needles.
			kit.cylinder(Transform3D.IDENTITY, 0.03, 0.018, 0.55, 6, OAK_BARK, false)
			for k in range(7):
				var a := TAU * (float(k) + 0.3 * _h(k, 331)) / 7.0
				var y := 0.45 + 0.4 * _h(k, 332)
				var c := Vector3(cos(a) * 0.1, y, sin(a) * 0.1)
				_blob(kit, c, Vector3(0.09, 0.16, 0.09), OAK_LEAF.lightened(0.06 * _h(k, 333) - 0.03), k + 90, detail)
			_blob(kit, Vector3(0, 0.88, 0), Vector3(0.07, 0.12, 0.07), OAK_LEAF, 99, detail)
		_:
			# A dead tree: bleached grey, forked bare limbs.
			kit.cylinder(Transform3D.IDENTITY, 0.03, 0.02, 0.45, 6, DEAD_BARK, false)
			for k in range(4):
				var a := TAU * (float(k) + 0.3 * _h(k, 341)) / 4.0
				var from := Vector3(0, 0.4, 0)
				var to := from + Vector3(cos(a) * 0.2, 0.3 + 0.2 * _h(k, 342), sin(a) * 0.2)
				_branch(kit, from, to, 0.012, DEAD_BARK, 4)
				_branch(kit, to, to + Vector3(cos(a + 0.9) * 0.08, 0.12, sin(a + 0.9) * 0.08), 0.006, DEAD_BARK.darkened(0.1), 3)
	kit.smooth(55.0)
	return kit.commit()


static func _outback_shrub(kind: int) -> ArrayMesh:
	var kit := MeshKit.new()
	match kind:
		Flora.ALDER, Flora.DWARF_BIRCH:
			# Saltbush / bluebush: a low, rounded, silvery mound.
			var col := Color(0.55, 0.60, 0.50, 1.0) if kind == Flora.ALDER else Color(0.52, 0.58, 0.60, 1.0)
			for k in range(5):
				var a := TAU * float(k) / 5.0 + _h(k, 351)
				var off := 0.0 if k == 0 else 0.22
				var rr := 0.28 if k == 0 else 0.2 + 0.06 * _h(k, 352)
				_blob(kit, Vector3(cos(a) * off, rr * 0.7, sin(a) * off), Vector3(rr, rr * 0.8, rr), col.lightened(0.08 * _h(k, 353) - 0.04), k + 360, 1)
		_:
			# Mulga: a few dark stems up to a flat, grey-green, open top.
			var stem := Color(0.28, 0.22, 0.18, 0.0)
			for k in range(5):
				var a := TAU * (float(k) + 0.4 * _h(k, 371)) / 5.0
				var top := Vector3(cos(a) * 0.25, 0.7 + 0.2 * _h(k, 372), sin(a) * 0.25)
				_branch(kit, Vector3.ZERO, top, 0.018, stem, 4)
				_blob(kit, top + Vector3(0, 0.04, 0), Vector3(0.2, 0.09, 0.2), Color(0.44, 0.47, 0.34, 1.0).lightened(0.06 * _h(k, 373) - 0.03), k + 380, 1)
	kit.smooth(55.0)
	return kit.commit()


const DRY_ROOT := Color(0.55, 0.44, 0.27, 1.0)
const DRY_MID := Color(0.78, 0.66, 0.40, 1.0)
const DRY_TIP := Color(0.90, 0.80, 0.55, 1.0)
const SPIN_ROOT := Color(0.45, 0.44, 0.28, 1.0)
const SPIN_MID := Color(0.62, 0.63, 0.40, 1.0)
const SPIN_TIP := Color(0.80, 0.76, 0.50, 1.0)


static func _outback_ground(kind: int) -> RefCounted:
	var kit := MeshKit.new()
	var solid := MeshKit.new()
	match kind:
		Flora.FIREWEED, Flora.TUSSOCK:
			# Spinifex: a dome of stiff, needle-sharp blades; the big ones grow
			# out into a ring with a dead middle.
			var ring := kind == Flora.TUSSOCK
			var n := _n(34, 16)
			if not ring:
				_blob(solid, Vector3(0, 0.05, 0), Vector3(0.22, 0.12, 0.22), Color(0.48, 0.46, 0.30, 1.0), 391, 1)
			for k in range(n):
				var a := TAU * _h(k, 392)
				var rr := (0.28 + 0.1 * _h(k, 393)) if ring else 0.12 * sqrt(_h(k, 394))
				var base := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
				var out := a + (_h(k, 395) - 0.5) * 1.2
				_blade(kit, base, out, 0.28 + 0.2 * _h(k, 396), 0.18 + 0.15 * _h(k, 397), 0.014, SPIN_ROOT, SPIN_MID, SPIN_TIP, 2)
		Flora.LOWSHRUB:
			# Low saltbush.
			_blob(solid, Vector3(0, 0.12, 0), Vector3(0.22, 0.14, 0.22), Color(0.55, 0.60, 0.50, 1.0), 401, 1)
			_blob(solid, Vector3(0.14, 0.09, 0.05), Vector3(0.14, 0.1, 0.14), Color(0.58, 0.62, 0.52, 1.0), 402, 1)
		_:
			# Dry tussock grass: a loose tuft of straw blades; some in seed.
			var seed_heads := kind == Flora.COTTON
			for k in range(_n(18, 8)):
				var a := TAU * _h(k, 411)
				var rr := 0.08 * sqrt(_h(k, 412))
				var base := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
				var tip := DRY_TIP.lerp(DRY_MID, 0.5 * _h(k, 413))
				_blade(kit, base, a + 0.3 * (_h(k, 414) - 0.5), 0.3 + 0.4 * _h(k, 415), 0.12 + 0.3 * _h(k, 416), 0.035, DRY_ROOT, DRY_MID, tip, 2)
			if seed_heads or kind == Flora.FERN:
				for k in range(_n(5, 2)):
					var a2 := TAU * _h(k, 417)
					var b := Vector3(cos(a2) * 0.03, 0, sin(a2) * 0.03)
					var hh := 0.7 + 0.25 * _h(k, 418)
					_blade(kit, b, a2, hh, 0.1, 0.006, DRY_MID, DRY_MID, DRY_TIP, 2)
					_leaf(kit, b + Vector3(cos(a2) * 0.1, hh * 0.86, sin(a2) * 0.1), Vector3(cos(a2) * 0.2, 1.0, sin(a2) * 0.2), 0.14, 0.02, DRY_MID, DRY_TIP)
	solid.smooth(50.0)
	_merge(kit, solid)
	return kit
