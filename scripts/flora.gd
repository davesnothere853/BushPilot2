extends RefCounted
## Where every plant grows. Plants are not stored: each one is worked out from
## its grid cell with a hash and the ecology of the spot, so the same tree is
## always in the same place, it can be drawn near or far at different detail,
## and the flight model can bump into it.
##
## Each spot is given a habitat from the lie of the land and the ecology maps
## in terrain.gd (drainage, muskeg, old burns), and each habitat grows what it
## would in south-central and interior Alaska:
##
##   upland        white spruce and paper birch; moss, low-bush cranberry, fern
##   south slope   aspen stands, birch, white spruce; bluejoint grass
##   north slope   black spruce, a little white spruce; Labrador tea, moss
##   creek side    balsam poplar (cottonwood), tall white spruce; willow and
##                 alder thickets; bluejoint, ferns
##   muskeg        open, stunted black spruce; dwarf birch; sedge tussocks,
##                 cotton grass, Labrador tea
##   old burn      grey snags, thickets of young birch and aspen; fireweed
##   subalpine     scattered stunted white spruce; alder on the steep slopes,
##                 willow in the gullies; bluejoint meadows
##   alpine tundra dwarf birch, crowberry and blueberry heath, sedge, rock
##   sea shore     alder, beach rye grass, white spruce behind

const G := 7.0                 # tree grid, metres
const SHRUB_G := 4.5           # shrub grid
const GROUND_G := 2.2          # grass, flowers and small plants
const ROCK_G := 40.0           # cliff and outcrop grid
const CELL := 40.0             # terrain grid (terrain.gd CELL)

enum { WHITE_SPRUCE, BLACK_SPRUCE, BIRCH, ASPEN, POPLAR, SNAG }
enum { ALDER, WILLOW, DWARF_BIRCH }
enum { GRASS, FIREWEED, TUSSOCK, COTTON, LOWSHRUB, FERN }
const TREE_KINDS := 6
const SHRUB_KINDS := 3
const GROUND_KINDS := 6

enum { UPLAND, SOUTH, NORTH, CREEK, MUSKEG, BURN, SUBALPINE, ALPINE, SHORE }
const HABITAT_NAMES := ["upland forest", "south slope", "north slope", "creek side", "muskeg", "old burn", "subalpine", "alpine tundra", "shore"]

## The Outback map (DESIGN_NOTES 108): same kinds, different plants. Set by
## world.gd before anything grows. Trees: WHITE_SPRUCE = a gum (eucalypt),
## BLACK_SPRUCE = mallee, BIRCH = ghost gum, ASPEN = desert oak, POPLAR =
## river red gum, SNAG = a dead grey tree. Shrubs: ALDER = saltbush, WILLOW =
## mulga (acacia), DWARF_BIRCH = bluebush. Ground: GRASS = dry tussock grass,
## FIREWEED = spinifex, TUSSOCK = a big spinifex ring, COTTON = dry grass in
## seed, LOWSHRUB = low saltbush, FERN = dry grass.
static var outback := false

## Trees knocked down: cell key -> horizontal direction they fell.
## y < -0.5: it burnt (charred black); y > 0.5: bucked up and hauled off
## (only the stump's left, nothing drawn).
static var felled := {}


static func cleared(k: int) -> bool:
	return felled.has(k) and (felled[k] as Vector3).y > 0.5


## The nearest tree lying on the ground within `reach` of p (anywhere along
## its trunk): {ti, tj, pos, dir, height, charred, dist}, or {}.
static func down_near(t: RefCounted, p: Vector3, reach: float = 1.4) -> Dictionary:
	var ci := int(floor((p.x + t.half) / G))
	var cj := int(floor((p.z + t.half) / G))
	var best := {}
	var best_d := reach
	for j in range(cj - 3, cj + 4):
		for i in range(ci - 3, ci + 4):
			var k := key(i, j)
			if not felled.has(k) or cleared(k):
				continue
			var tr := tree_at(t, i, j)
			if tr.is_empty():
				continue
			var dir: Vector3 = felled[k]
			var charred := dir.y < -0.5
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
			var base: Vector3 = tr["pos"]
			var hgt: float = tr["height"]
			# closest point on the lying trunk (base to about 80 % of its height)
			var a := Vector2(base.x, base.z)
			var b := a + Vector2(dir.x, dir.z) * hgt * 0.8
			var q := Vector2(p.x, p.z)
			var ab := b - a
			var tt := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			var d := q.distance_to(a + ab * tt)
			if d < best_d and absf(p.y - base.y) < 2.5:
				best_d = d
				best = {"ti": i, "tj": j, "pos": base, "dir": dir, "height": hgt, "charred": charred, "dist": d}
	return best


static func h01(i: int, j: int, k: int) -> float:
	var h: int = (i * 374761393 + j * 668265263 + k * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


## Smooth value noise, 0..1, with features about `scale` metres across.
static func vnoise(x: float, z: float, scale: float, seed: int) -> float:
	var fx := x / scale
	var fz := z / scale
	var i := int(floor(fx))
	var j := int(floor(fz))
	var tx := fx - float(i)
	var tz := fz - float(j)
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	return lerpf(lerpf(h01(i, j, seed), h01(i + 1, j, seed), tx),
		lerpf(h01(i, j + 1, seed), h01(i + 1, j + 1, seed), tx), tz)


static func key(i: int, j: int) -> int:
	return (i + 40000) * 80000 + (j + 40000)


## Treeline elevation: higher on warm south-facing slopes (`nz` > 0 faces south).
## The treeline's mean height: the island's 600 m; the mountain region sets its own (~1420 m).
static var treeline_base := 600.0


static func treeline_from(x: float, z: float, nz: float) -> float:
	return treeline_base + 110.0 * clampf(nz * 5.0, -1.0, 1.0) + (vnoise(x, z, 700.0, 9) - 0.5) * 120.0


## One of terrain.gd's per-vertex fields, smoothly interpolated.
static func field(t: RefCounted, f: PackedFloat32Array, x: float, z: float) -> float:
	var n: int = t.n
	var fx: float = (x + t.half) / CELL
	var fz: float = (z + t.half) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= float(n) or fz >= float(n) or f.is_empty():
		return 0.0
	var i := int(fx)
	var j := int(fz)
	var tx: float = fx - float(i)
	var tz: float = fz - float(j)
	var vn := n + 1
	var a := f[j * vn + i]
	var b := f[j * vn + i + 1]
	var c := f[(j + 1) * vn + i]
	var d := f[(j + 1) * vn + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


static func forest(t: RefCounted, x: float, z: float) -> float:
	return field(t, t.forest, x, z)


## The habitat at a spot. Edges between habitats are ragged, not ruled lines.
static func habitat(t: RefCounted, x: float, z: float, h: float, nrm: Vector3) -> int:
	var wob := vnoise(x, z, 55.0, 5) - 0.5
	var tl := treeline_from(x, z, nrm.z)
	if h > tl + 70.0 + wob * 90.0:
		return ALPINE
	if h < 3.5 + wob * 2.0 and not _near_lake(t, x, z, 1.0, 0.0):
		return SHORE
	if h > tl - 110.0 + wob * 90.0:
		return SUBALPINE
	if field(t, t.burn, x, z) + wob * 0.15 > 0.45:
		return BURN
	if field(t, t.bog, x, z) + wob * 0.35 > 0.5:
		return MUSKEG
	if field(t, t.creek, x, z) + wob * 0.35 > 0.55 or _near_lake(t, x, z, 1.08, 35.0):
		return CREEK
	if nrm.y < 0.992:
		if nrm.z < -0.06 + wob * 0.08:
			return NORTH
		if nrm.z > 0.06 + wob * 0.08:
			return SOUTH
	return UPLAND


## Under (or right at the edge of) lake water: nothing grows there.
static func _wet(t: RefCounted, x: float, z: float, h: float, margin: float) -> bool:
	return t._water_level(x, z, h - margin) > -1.0e8


static func _near_lake(t: RefCounted, x: float, z: float, scale: float, pad: float) -> bool:
	for lake in t.lakes:
		var c: Vector2 = lake["pos"]
		var r: float = lake["radius"] * scale + pad
		if (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y) < r * r:
			return true
	return false


## The tree in grid cell (i, j), or an empty dictionary.
## {pos: Vector3 base, height, kind, radius (crown), yaw, tint, habitat}
static func tree_at(t: RefCounted, i: int, j: int) -> Dictionary:
	var x: float = -t.half + (float(i) + 0.15 + 0.7 * h01(i, j, 11)) * G
	var z: float = -t.half + (float(j) + 0.15 + 0.7 * h01(i, j, 12)) * G
	var d := forest(t, x, z)
	# Muskeg grows its own open scatter of spruce even outside the forest.
	var boggy := field(t, t.bog, x, z) > 0.35
	if d < 0.03 and not boggy:
		return {}
	if t.is_cleared(x, z, 30.0):
		return {}
	var h: float = t.height_at(x, z)
	if h < 1.6 or _wet(t, x, z, h, 0.3):
		return {}
	var nrm: Vector3 = t.normal_at(x, z)
	if nrm.y < 0.62:
		return {}
	var hab := habitat(t, x, z, h, nrm)
	if d < 0.03 and hab != MUSKEG:
		return {}
	var dens := d
	match hab:
		ALPINE:
			return {}
		MUSKEG:
			if t.in_strip_clearing(x, z) or t.water_level_at(x, z) > h - 0.3:
				return {}
			dens = 0.16 + 0.45 * d
		SUBALPINE:
			dens *= 0.5 * (0.4 + vnoise(x, z, 70.0, 14))   # clumps with meadows between
		SHORE:
			dens *= 0.45
		BURN:
			dens = minf(dens * 1.2, 1.0)
	# Patchy: dense stands, thinner glades, scattered loners at the edges.
	if h01(i, j, 1) > dens * 0.72 + 0.02:      # about a quarter fewer trees than a full stand
		return {}
	# Neighbours share a stand: one species and age over a patch of ground,
	# with a few strays mixed in.
	var stand := vnoise(x, z, 85.0, 3)
	var r := clampf(stand + (h01(i, j, 2) - 0.5) * 0.45, 0.0, 1.0)
	var age := 0.65 + 0.5 * vnoise(x, z, 140.0, 4)
	var kind := WHITE_SPRUCE
	var young := false
	match hab:
		MUSKEG:
			kind = BLACK_SPRUCE if r < 0.93 else BIRCH
		BURN:
			var s6 := h01(i, j, 6)
			if s6 < 0.2:
				kind = SNAG
			elif s6 > 0.93:
				kind = WHITE_SPRUCE          # a survivor
			else:
				kind = ASPEN if r < 0.42 else BIRCH
				young = true
		CREEK:
			kind = POPLAR if r < 0.45 else (WHITE_SPRUCE if r < 0.86 else BIRCH)
		NORTH:
			kind = BLACK_SPRUCE if r < 0.68 else (WHITE_SPRUCE if r < 0.92 else BIRCH)
		SOUTH:
			kind = ASPEN if r < 0.38 else (BIRCH if r < 0.62 else WHITE_SPRUCE)
		SUBALPINE:
			kind = WHITE_SPRUCE if r < 0.85 else BLACK_SPRUCE
		SHORE:
			kind = WHITE_SPRUCE if r < 0.75 else POPLAR
		_:
			if r < 0.5:
				kind = WHITE_SPRUCE
			elif r < 0.8:
				kind = BIRCH
			elif r < 0.9:
				kind = ASPEN
			else:
				kind = BLACK_SPRUCE
	if outback:
		return _outback_tree(t, i, j, x, z, h, hab, r)
	var s := h01(i, j, 3)
	var height := 15.0
	match kind:
		WHITE_SPRUCE:
			height = lerpf(12.0, 26.0, s)
		BLACK_SPRUCE:
			height = lerpf(4.0, 10.5, s)
		BIRCH:
			height = lerpf(10.0, 18.0, s)
		ASPEN:
			height = lerpf(9.0, 16.0, s)
		POPLAR:
			height = lerpf(16.0, 27.0, s)
		SNAG:
			height = lerpf(5.0, 15.0, s)
	if kind != SNAG:
		height *= age
	if young:
		height *= 0.3 + 0.25 * vnoise(x, z, 60.0, 15)
	match hab:
		MUSKEG:
			height *= 0.55 + 0.25 * s     # stunted on cold, wet ground
		SUBALPINE:
			var tl := treeline_from(x, z, nrm.z)
			height *= lerpf(0.75, 0.3, smoothstep(tl - 110.0, tl + 70.0, h))
		CREEK:
			height *= 1.1
	# Thinner, shorter trees at the forest edge.
	height *= 0.7 + 0.3 * smoothstep(0.1, 0.6, d)
	# No scrubby little saplings outside the muskeg: they pop in close and add little.
	if height < 4.0 and hab != MUSKEG:
		return {}
	height = maxf(height, 1.8)
	var radius := height * (0.20 if kind == WHITE_SPRUCE else (0.10 if kind == BLACK_SPRUCE else (0.04 if kind == SNAG else 0.28)))
	return {"pos": Vector3(x, h, z), "height": height, "kind": kind, "radius": radius,
		"yaw": TAU * h01(i, j, 4), "tint": h01(i, j, 5), "i": i, "j": j, "habitat": hab}


## Shrub thickets: willow and alder along creeks, alder on steep slopes near
## treeline, dwarf birch on the tundra and in the muskeg.
static func shrub_at(t: RefCounted, i: int, j: int) -> Dictionary:
	var x: float = -t.half + (float(i) + 0.1 + 0.8 * h01(i, j, 21)) * SHRUB_G
	var z: float = -t.half + (float(j) + 0.1 + 0.8 * h01(i, j, 22)) * SHRUB_G
	if outback and h01(i, j, 91) > 0.45:
		return {}
	if t.is_cleared(x, z, 14.0):
		return {}
	var h: float = t.height_at(x, z)
	if h < 1.4 or _wet(t, x, z, h, 0.2):
		return {}
	var nrm: Vector3 = t.normal_at(x, z)
	if nrm.y < 0.55:
		return {}
	var hab := habitat(t, x, z, h, nrm)
	var d := forest(t, x, z)
	var edge := smoothstep(0.02, 0.25, d) * (1.0 - smoothstep(0.5, 0.9, d))
	var shade := smoothstep(0.45, 0.9, d)
	var steep := 1.0 - smoothstep(0.72, 0.95, nrm.y)
	var p := 0.0
	match hab:
		CREEK:
			p = 0.6 - 0.35 * shade
		MUSKEG:
			p = 0.22
		BURN:
			p = 0.22
		SUBALPINE:
			p = 0.3 + 0.45 * steep
		ALPINE:
			var tl := treeline_from(x, z, nrm.z)
			p = 0.35 * (1.0 - smoothstep(tl + 250.0, tl + 450.0, h))
		SHORE:
			p = 0.3
		_:
			p = 0.03 + 0.45 * edge - 0.02 * shade
	# Thickets come in patches, not dotted evenly about (and fewer of them).
	p *= 1.0 * smoothstep(0.3, 0.75, vnoise(x, z, 40.0, 23))
	if h01(i, j, 23) > p:
		return {}
	var r := clampf(vnoise(x, z, 30.0, 24) + (h01(i, j, 24) - 0.5) * 0.4, 0.0, 1.0)
	var kind := ALDER
	match hab:
		CREEK:
			kind = WILLOW if r < 0.62 else ALDER
		MUSKEG:
			kind = DWARF_BIRCH if r < 0.72 else WILLOW
		BURN:
			kind = WILLOW if r < 0.7 else ALDER
		SUBALPINE:
			kind = ALDER if (steep > 0.3 or r < 0.6) else WILLOW
		ALPINE:
			kind = DWARF_BIRCH if r < 0.85 else WILLOW
		SHORE:
			kind = ALDER
		_:
			kind = ALDER if r < 0.65 else WILLOW
	var s := h01(i, j, 25)
	var size := 1.0
	match kind:
		ALDER:
			size = lerpf(1.8, 4.0, s)
		WILLOW:
			size = lerpf(1.3, 3.2, s) * (1.3 if hab == CREEK else 1.0)
		DWARF_BIRCH:
			size = lerpf(0.4, 0.9, s)
	if hab == ALPINE or hab == MUSKEG:
		size *= 0.65
	return {"pos": Vector3(x, h, z), "size": size, "kind": kind, "yaw": TAU * h01(i, j, 26), "tint": h01(i, j, 27)}


## Ground plants: bluejoint grass, fireweed, sedge tussocks, cotton grass,
## low heath shrubs (Labrador tea, crowberry, blueberry) and ferns.
static func ground_at(t: RefCounted, i: int, j: int) -> Dictionary:
	var x: float = -t.half + (float(i) + 0.1 + 0.8 * h01(i, j, 31)) * GROUND_G
	var z: float = -t.half + (float(j) + 0.1 + 0.8 * h01(i, j, 32)) * GROUND_G
	if t.is_cleared(x, z, 1.5):
		return {}
	var h: float = t.height_at(x, z)
	if h < 1.2 or _wet(t, x, z, h, 0.05):
		return {}
	var nrm: Vector3 = t.normal_at(x, z)
	if nrm.y < 0.68:
		return {}
	var hab := habitat(t, x, z, h, nrm)
	var d := forest(t, x, z)
	var shade := smoothstep(0.45, 0.9, d)
	var cover := lerpf(0.78, 0.3, shade)
	if hab == MUSKEG or hab == CREEK or hab == BURN:
		cover = lerpf(0.92, 0.4, shade)
	if hab == ALPINE:
		var tl := treeline_from(x, z, nrm.z)
		cover = 0.5 * (1.0 - smoothstep(tl + 350.0, tl + 600.0, h))
	if h01(i, j, 33) > cover:
		return {}
	# Kinds grow in drifts: neighbours mostly match.
	var drift := vnoise(x, z, 14.0, 34)
	var r := clampf(drift + (h01(i, j, 34) - 0.5) * 0.5, 0.0, 1.0)
	var kind := GRASS
	# Disturbed ground beside a runway: grass and fireweed.
	if t.is_cleared(x, z, 30.0):
		kind = GRASS if r < 0.8 else FIREWEED
	else:
		match hab:
			BURN:
				kind = FIREWEED if r < 0.68 else GRASS
			MUSKEG:
				if r < 0.32:
					kind = TUSSOCK
				elif r < 0.48:
					kind = COTTON
				elif r < 0.9:
					kind = LOWSHRUB
				else:
					kind = GRASS
			CREEK:
				if shade > 0.4:
					kind = FERN if r < 0.6 else (LOWSHRUB if r < 0.8 else GRASS)
				else:
					kind = GRASS if r < 0.62 else (TUSSOCK if r < 0.8 else FERN)
			NORTH:
				kind = LOWSHRUB if r < 0.6 else (FERN if r < 0.78 else (TUSSOCK if r < 0.88 else GRASS))
			SOUTH:
				kind = GRASS if r < 0.68 else LOWSHRUB
			SUBALPINE:
				kind = GRASS if r < 0.6 else LOWSHRUB
			ALPINE:
				kind = LOWSHRUB if r < 0.62 else (TUSSOCK if r < 0.82 else GRASS)
			SHORE:
				kind = GRASS
			_:
				if shade > 0.4:
					kind = LOWSHRUB if r < 0.5 else (FERN if r < 0.8 else GRASS)
				else:
					kind = GRASS if r < 0.66 else LOWSHRUB
	if outback:
		# Open red ground between clumps: spinifex hummocks, dry tussocks, saltbush.
		if h01(i, j, 92) > 0.62:
			return {}
		kind = GRASS if r < 0.42 else (FIREWEED if r < 0.72 else (TUSSOCK if r < 0.84 else (LOWSHRUB if r < 0.94 else COTTON)))
	var s := h01(i, j, 35)
	var size := lerpf(0.6, 1.25, s)
	match kind:
		FIREWEED:
			size = lerpf(0.8, 1.5, s) * (1.15 if hab == BURN else 1.0)
		LOWSHRUB:
			size = lerpf(0.5, 1.0, s) * (0.7 if hab == ALPINE else 1.0)
		FERN:
			size = lerpf(0.7, 1.2, s)
		TUSSOCK, COTTON:
			size = lerpf(0.55, 0.95, s)
		GRASS:
			if hab == ALPINE:
				size *= 0.6
			elif hab == SHORE or hab == CREEK:
				size *= 1.2
	return {"pos": Vector3(x, h, z), "size": size, "kind": kind, "yaw": TAU * h01(i, j, 36), "tint": h01(i, j, 37)}


## Rock outcrops and cliff bands on steep mountain ground (no scattered
## boulders): big stepped slabs set into the slope, facing out of it. On a
## 40 m grid. {pos, size, yaw, tint, nrm}
const CLIFF_G := 40.0


static func rock_at(t: RefCounted, i: int, j: int) -> Dictionary:
	var x: float = -t.half + (float(i) + 0.15 + 0.7 * h01(i, j, 41)) * CLIFF_G
	var z: float = -t.half + (float(j) + 0.15 + 0.7 * h01(i, j, 42)) * CLIFF_G
	var h: float = t.height_at(x, z)
	if outback:
		return _outback_rock(t, i, j, x, z, h)
	if h < 220.0 or t.is_cleared(x, z, 60.0) or t.in_strip_clearing(x, z):
		return {}
	var nrm: Vector3 = t.normal_at(x, z)
	# Only where it is steep: the steeper, the likelier a cliff shows through.
	var steep := 1.0 - smoothstep(0.6, 0.8, nrm.y)
	var p := steep * (0.55 + 0.45 * vnoise(x, z, 300.0, 47)) * smoothstep(220.0, 500.0, h)
	if h01(i, j, 43) > p:
		return {}
	var s := h01(i, j, 44)
	var size := lerpf(16.0, 52.0, s * s) * (0.7 + 0.6 * steep)
	# Face downhill: the slab's front (local -Z) looks out of the slope.
	var down := Vector3(nrm.x, 0.0, nrm.z)
	var yaw := atan2(-down.x, -down.z) + (h01(i, j, 45) - 0.5) * 0.5 if down.length() > 0.01 else TAU * h01(i, j, 45)
	return {"pos": Vector3(x, h, z), "size": size, "yaw": yaw, "tint": h01(i, j, 46), "nrm": nrm}


## The standing tree whose trunk or crown is nearest to `p` (for collisions).
## tree_at is a lot of noise and terrain sampling, and the aeroplane asks
## about the same few cells for every body point, twice a physics tick. Keep
## the answers for a couple of seconds (so clearings and digs still show up).
static var _near_cache := {}
static var _near_cache_t := 0


static func _tree_cached(t: RefCounted, i: int, j: int) -> Dictionary:
	var now := Time.get_ticks_msec()
	if now - _near_cache_t > 2000 or _near_cache.size() > 4096:
		_near_cache.clear()
		_near_cache_t = now
	var k := key(i, j)
	var tr = _near_cache.get(k)
	if tr == null:
		tr = tree_at(t, i, j)
		_near_cache[k] = tr
	return tr


static func tree_near(t: RefCounted, p: Vector3) -> Dictionary:
	var ci := int(floor((p.x + t.half) / G))
	var cj := int(floor((p.z + t.half) / G))
	var best := {}
	var best_d := 1.0e9
	for j in range(cj - 1, cj + 2):
		for i in range(ci - 1, ci + 2):
			if felled.has(key(i, j)):
				continue
			var tr := _tree_cached(t, i, j)
			if tr.is_empty():
				continue
			var base: Vector3 = tr["pos"]
			var dx := p.x - base.x
			var dz := p.z - base.z
			var dist := sqrt(dx * dx + dz * dz)
			var hgt: float = tr["height"]
			if dist > float(tr["radius"]) + 0.6 or dist >= best_d:
				continue
			if p.y < base.y - 0.5 or p.y > base.y + hgt:
				continue
			var k := clampf((p.y - base.y) / hgt, 0.0, 1.0)
			var crown: float = tr["radius"]
			if tr["kind"] == WHITE_SPRUCE or tr["kind"] == BLACK_SPRUCE:
				crown *= 1.0 - k * 0.85
			best_d = dist
			best = {"ti": i, "tj": j, "base": base, "height": hgt, "trunk_r": 0.12 + hgt * 0.012, "dist": dist, "crown_r": crown + 0.3}
	return best


## Outback trees: sparse, except the red gums along the creek.
static func _outback_tree(t: RefCounted, i: int, j: int, x: float, z: float, h: float, hab: int, r: float) -> Dictionary:
	var creek := hab == CREEK
	if h01(i, j, 90) > (0.5 if creek else 0.13):
		return {}
	var kind := WHITE_SPRUCE
	var k := h01(i, j, 93)
	if creek:
		kind = POPLAR if k < 0.75 else WHITE_SPRUCE
	elif k < 0.05:
		kind = SNAG
	elif r < 0.36:
		kind = WHITE_SPRUCE
	elif r < 0.56:
		kind = BLACK_SPRUCE
	elif r < 0.78:
		kind = BIRCH
	else:
		kind = ASPEN
	var s := h01(i, j, 3)
	var height: float = {WHITE_SPRUCE: lerpf(8.0, 16.0, s), BLACK_SPRUCE: lerpf(4.5, 8.0, s), BIRCH: lerpf(8.0, 14.0, s),
		ASPEN: lerpf(6.0, 11.0, s), POPLAR: lerpf(14.0, 24.0, s), SNAG: lerpf(5.0, 12.0, s)}[kind]
	var radius := height * (0.05 if kind == SNAG else (0.18 if kind == BLACK_SPRUCE else 0.3))
	return {"pos": Vector3(x, h, z), "height": height, "kind": kind, "radius": radius,
		"yaw": TAU * h01(i, j, 4), "tint": h01(i, j, 5), "i": i, "j": j, "habitat": hab}


## Outback rock: low red outcrops scattered out on the plain (not in the
## square you drive and dig in, where they would only be in the way).
static func _outback_rock(t: RefCounted, i: int, j: int, x: float, z: float, h: float) -> Dictionary:
	var sq := 200.0
	if absf(x) < sq and absf(z) < sq:
		return {}
	if t.is_cleared(x, z, 60.0) or t.in_strip_clearing(x, z):
		return {}
	var p := 0.22 * smoothstep(0.5, 0.8, vnoise(x, z, 320.0, 48))
	if h01(i, j, 43) > p:
		return {}
	var s := h01(i, j, 44)
	return {"pos": Vector3(x, h, z), "size": lerpf(5.0, 16.0, s * s), "yaw": TAU * h01(i, j, 45), "tint": h01(i, j, 46), "nrm": Vector3.UP}
