extends RefCounted
## The DC-3's skin as one shape, shared by the outside (dc3_visual.gd) and the
## flight deck inside (dc3_cockpit.gd) so the glass is in exactly the same place
## from both sides.
##
## The body is round sections (ST); the nose is then cut by the two flat
## windscreen panes, set in a shallow V and raked back, like the real one.
## A point is given by its angle round the section (0 = right side, PI/2 =
## top) and its station z; `inset` moves it inward (the inside of the skin).

## z, half width, half height, centre y
const ST := [
	[-7.70, 0.03, 0.03, -0.42], [-7.64, 0.24, 0.22, -0.40], [-7.52, 0.44, 0.42, -0.36],
	[-7.32, 0.66, 0.66, -0.28], [-7.05, 0.88, 0.92, -0.17], [-6.70, 1.08, 1.15, -0.06], [-6.20, 1.30, 1.38, 0.03],
	[-5.60, 1.40, 1.48, 0.07], [-5.00, 1.43, 1.51, 0.08], [-4.00, 1.44, 1.52, 0.08],
	[-1.0, 1.44, 1.52, 0.08], [3.0, 1.42, 1.48, 0.10], [5.6, 1.22, 1.26, 0.25],
	[7.8, 0.92, 0.94, 0.45], [9.7, 0.56, 0.60, 0.70], [11.4, 0.22, 0.28, 0.92], [12.0, 0.06, 0.08, 1.0],
]

## Windscreen: sill and top of the centre post, and the outer corners of each pane.
const SILL_C := Vector3(0.0, 0.56, -7.00)
const TOP_C := Vector3(0.0, 1.12, -6.56)
const SILL_O := Vector3(0.72, 0.60, -6.64)
const TOP_O := Vector3(0.63, 1.10, -6.30)

## Sliding side windows (on the round skin): z from, z to, y from, y to.
const SIDE_WIN := [-6.28, -5.45, 0.50, 1.02]


static func section(z: float) -> Array:
	if z <= float(ST[0][0]):
		return ST[0]
	for i in range(ST.size() - 1):
		var a: Array = ST[i]
		var b: Array = ST[i + 1]
		if z <= float(b[0]):
			var f := (z - float(a[0])) / (float(b[0]) - float(a[0]))
			return [z, lerpf(a[1], b[1], f), lerpf(a[2], b[2], f), lerpf(a[3], b[3], f)]
	return ST[ST.size() - 1]


## Outward normal and a point of the windscreen pane on side s (+1 right).
static func pane_plane(s: float) -> Array:
	var c0 := SILL_C
	var c1 := TOP_C
	var o0 := Vector3(SILL_O.x * s, SILL_O.y, SILL_O.z)
	var n := (c1 - c0).cross(o0 - c0).normalized()
	if n.z > 0.0:
		n = -n
	return [n, c0]


static func point(a: float, z: float, inset: float = 0.0) -> Vector3:
	var s := section(z)
	var hw: float = maxf(float(s[1]) - inset, 0.01)
	var hh: float = maxf(float(s[2]) - inset, 0.01)
	var p := Vector3(cos(a) * hw, float(s[3]) + sin(a) * hh, z)
	# Flatten the nose onto each windscreen pane where the round skin would
	# bulge out past it, from a little below the sill upward.
	for side in [-1.0, 1.0]:
		if p.x * side < -0.02:
			continue
		var pl := pane_plane(side)
		var n: Vector3 = pl[0]
		var o: Vector3 = pl[1] - n * inset
		var d := (p - o).dot(n)
		if d > 0.0:
			var w := smoothstep(SILL_C.y - 0.30, SILL_C.y - 0.02, p.y)
			p -= n * d * w
	return p


## Is the skin here windscreen or side-window glass (frame bars excluded)?
static func is_glass(p: Vector3) -> bool:
	var ax := absf(p.x)
	# On a windscreen pane, between the sill and the top, inside the posts.
	if p.z < -6.25 and ax > 0.03 and ax < SILL_O.x - 0.03:
		var f := ax / SILL_O.x
		var sill_y := lerpf(SILL_C.y, SILL_O.y, f) + 0.02
		var top_y := lerpf(TOP_C.y, TOP_O.y, f) - 0.02
		if p.y > sill_y and p.y < top_y:
			var pl := pane_plane(signf(p.x))
			if absf((p - pl[1]).dot(pl[0])) < 0.12:
				return true
	if p.z > SIDE_WIN[0] and p.z < SIDE_WIN[1] and p.y > SIDE_WIN[2] and p.y < SIDE_WIN[3]:
		return true
	return false


## The four corners of windscreen pane `side` (+1 right): sill centre, sill
## outer, top outer, top centre.
static func pane_corners(side: float) -> Array:
	return [SILL_C, Vector3(SILL_O.x * side, SILL_O.y, SILL_O.z), Vector3(TOP_O.x * side, TOP_O.y, TOP_O.z), TOP_C]


## A flat frame round a windscreen pane, lying on the pane's plane (moved by
## `push` along its outward normal): covers the edge of the cut-out skin.
static func pane_frame(kit: RefCounted, side: float, push: float, width: float, col: Color, facing_out: bool) -> void:
	var pl := pane_plane(side)
	var n: Vector3 = pl[0]
	var cs := pane_corners(side)
	var ctr: Vector3 = (cs[0] + cs[1] + cs[2] + cs[3]) * 0.25
	for i in range(4):
		var a: Vector3 = cs[i]
		var b: Vector3 = cs[(i + 1) % 4]
		var ao: Vector3 = a + (a - ctr).normalized() * width
		var bo: Vector3 = b + (b - ctr).normalized() * width
		var ai: Vector3 = a + (ctr - a).normalized() * 0.05
		var bi: Vector3 = b + (ctr - b).normalized() * 0.05
		var o := n * push
		kit.quad(ai + o, bi + o, bo + o, ao + o, col, n if facing_out else -n)


## Sectors round a section, so the side windows' top and bottom edges are
## exact lines of vertices instead of a staircase: [count, kind], kind is
## "skin" or "win" (side window band).
const SECTORS := [[22, "skin"], [6, "win"], [34, "skin"], [6, "win"], [22, "skin"]]


## The angles of a section's ring at station z: right side bottom, up through
## the window band, over the top, down the left window band, back underneath.
static func ring_angles(z: float, inset: float = 0.0) -> PackedFloat32Array:
	var s := section(z)
	var hh: float = maxf(float(s[2]) - inset, 0.01)
	var cy: float = s[3]
	var ab := asin(clampf((float(SIDE_WIN[2]) - cy) / hh, -0.99, 0.99))
	var at := asin(clampf((float(SIDE_WIN[3]) - cy) / hh, -0.99, 0.99))
	var keys := [-PI * 0.5, ab, at, PI - at, PI - ab, PI * 1.5]
	var out := PackedFloat32Array()
	for si in range(SECTORS.size()):
		var n: int = SECTORS[si][0]
		for k in range(n):
			out.append(lerpf(keys[si], keys[si + 1], float(k) / float(n)))
	return out


## Which sector the k-th quad of a ring belongs to.
static func sector_of(k: int) -> String:
	var acc := 0
	for sc in SECTORS:
		acc += int(sc[0])
		if k < acc:
			return sc[1]
	return "skin"


static func ring_size() -> int:
	var n := 0
	for sc in SECTORS:
		n += int(sc[0])
	return n


static func in_side_window_z(z: float) -> bool:
	return z > float(SIDE_WIN[0]) and z < float(SIDE_WIN[1])


# ------------------------------------------------------------------------------
#  Inside: the floor you walk on and how wide the cabin is (shared by the
#  walker, the cargo spots and the cabin model).
# ------------------------------------------------------------------------------
const BULKHEAD_Z := -4.80        # cockpit / cabin bulkhead (doorway in the middle)
const AFT_Z := 6.10              # aft cabin wall
const FRONT_Z := -6.15           # as far forward as you can stand (pedestal)
const DOOR_Z := [1.95, 4.45]     # cargo door, left side
const DOORWAY_HALF := 0.32       # half width of the bulkhead doorway


## Floor height inside at station z (flight deck is a step up; aft it rises
## with the tail cone).
static func cabin_floor(z: float) -> float:
	if z < BULKHEAD_Z:
		return -0.55
	if z < BULKHEAD_Z + 0.31:
		return -0.78     # the step up to the flight deck
	if z < 4.5:
		return -1.0
	return lerpf(-1.0, -0.6, clampf((z - 4.5) / 1.6, 0.0, 1.0))


## Half width of the inside of the skin at height y, station z.
static func inner_half_width(z: float, y: float) -> float:
	var s := section(z)
	var hw: float = float(s[1]) - 0.06
	var hh: float = float(s[2]) - 0.06
	var d := (y - float(s[3])) / hh
	if absf(d) >= 1.0:
		return 0.0
	return hw * sqrt(1.0 - d * d)


# ------------------------------------------------------------------------------
#  Holes in the cabin skin: the cargo door and the cabin windows. Angles are
#  round the section on that side (0 = level with the centre, + up), as in
#  dc3_visual._skin_patch. The skin, inside and out, is built round them so
#  the edges are exact.
# ------------------------------------------------------------------------------
const DOOR_A := [-0.72, 0.52]      # sill just above the cabin floor
const WIN_A := [0.20, 0.47]
const WIN_HALF := 0.19


## Cabin window stations on one side (the left side has the cargo door aft).
static func window_zs(side: float) -> Array:
	var out: Array = []
	for w in range(7):
		var wz := -3.35 + 0.95 * float(w)
		if side < 0.0 and wz > 1.7 and wz < 4.6:
			continue
		out.append(wz)
	return out


## [side, z0, z1, a0, a1, kind]
static func cabin_holes() -> Array:
	var out: Array = [[-1.0, DOOR_Z[0], DOOR_Z[1], DOOR_A[0], DOOR_A[1], "door"]]
	for side in [-1.0, 1.0]:
		for wz in window_zs(side):
			out.append([side, wz - WIN_HALF, wz + WIN_HALF, WIN_A[0], WIN_A[1], "win"])
	return out


## Stations where a hole starts or ends (add them to a skin's rows).
static func hole_breaks() -> Array:
	var out: Array = []
	for h in cabin_holes():
		out.append(h[1])
		out.append(h[2])
	return out


## A hole's range in ring angles (-PI/2 .. 3PI/2, as ring_angles gives).
static func hole_ring_range(h: Array) -> Vector2:
	if float(h[0]) > 0.0:
		return Vector2(h[3], h[4])
	return Vector2(PI - float(h[4]), PI - float(h[3]))


## The parts of a ring span [lo, hi] at station z that are not in a hole.
static func keep_spans(lo: float, hi: float, z: float) -> Array:
	var spans: Array = [Vector2(lo, hi)]
	for h in cabin_holes():
		if z <= float(h[1]) or z >= float(h[2]):
			continue
		var r := hole_ring_range(h)
		var next: Array = []
		for s in spans:
			var sv: Vector2 = s
			if sv.y <= r.x or sv.x >= r.y:
				next.append(sv)
				continue
			if sv.x < r.x:
				next.append(Vector2(sv.x, r.x))
			if sv.y > r.y:
				next.append(Vector2(r.y, sv.y))
		spans = next
	return spans


## One ring quad of skin between stations z0 and z1 (ring angles lo..hi at
## each), with holes cut out exactly. `out` true faces it outward.
static func skin_quad(kit: RefCounted, z0: float, z1: float, lo0: float, hi0: float, lo1: float, hi1: float, inset: float, col: Color, out: bool) -> void:
	var zm := (z0 + z1) * 0.5
	var k0 := keep_spans(lo0, hi0, zm)
	var k1 := keep_spans(lo1, hi1, zm)
	if k0.size() != k1.size():
		k1 = k0
	for i in range(k0.size()):
		var a: Vector2 = k0[i]
		var b: Vector2 = k1[i]
		var p00 := point(a.x, z0, inset)
		var p01 := point(a.y, z0, inset)
		var p10 := point(b.x, z1, inset)
		var p11 := point(b.y, z1, inset)
		var mid := (p00 + p11) * 0.5
		var axis := Vector3(0, float(section(mid.z)[3]), mid.z)
		var n := (mid - axis) if out else (axis - mid)
		kit.quad(p00, p01, p11, p10, col, n)
