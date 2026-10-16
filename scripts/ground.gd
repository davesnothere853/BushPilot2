extends RefCounted
## The proving ground's one unified, deformable ground - Out of Ore style.
## The WHOLE 360 m square is a single fine heightfield (half-metre cells) you
## can dig into, grade and pile up anywhere: no dig tiles, no seams, no pop.
## Under the turf everywhere is overburden, then (where the geology says so)
## the pay streak, then bedrock a bucket won't bite.
##
## It also duck-types the old island terrain API, so plane.gd, flora.gd,
## vegetation.gd, dozer.gd and excavator.gd all work against it unchanged.
##
## ground_view.gd draws it in 24 m chunks and rebuilds the chunks this class
## marks dirty.

const Flora = preload("res://scripts/flora.gd")
const MapGen = preload("res://scripts/map_gen.gd")

## The square's layout from the world seed (map_gen.gd): knoll, muskeg side,
## pond, creek, buried channels, bench, mining pad. Static so the static
## height functions can read it.
static var L: Dictionary = {}


static func use_seed(seed_value: int) -> void:
	L = MapGen.make(seed_value)


static func lay() -> Dictionary:
	if L.is_empty():
		L = MapGen.make(int(Game.world_seed) if Game != null else 1987)
	return L

const NO_WATER := -1.0e9
const SQ := 180.0               # half size of the diggable square
const PLAIN_Y := 5.5            # the open plain round it (storyboard PG-01)
const CELL: float = 40.0        # ecology / map grid (flora.gd, map screens)
const TREE_CELL: float = 32.0
const SEA_FLOOR: float = -45.0
const SURFACE_NAMES: Array[String] = ["rough ground", "gravel", "grass", "dirt", "deep snow", "packed snow", "ice", "water"]
const HANGARS := ["Proving Ground"]
const FRES := 0.5               # metres a cell
const FN := 720                 # cells a side (721 vertices)
const CHUNK_CELLS := 48         # 24 m chunks
const CHUNKS := 15              # chunks a side
const SWELL := 1.25             # dug ground bulks up in a pile


# --- ecology / compatibility fields (flora.gd reads these) -------------------
var n := 150                    # 40 m ecology grid cells a side (6 km map)
var half := 3000.0
var size := 6000.0
var heights := PackedFloat32Array()   # coarse 40 m heights for the map screens
var docks: Array = []
var digs: Array = []                  # (old dig tiles: none - the ground is one piece)
var dig_tiles := {}
var forest := PackedFloat32Array()
var bog := PackedFloat32Array()
var creek := PackedFloat32Array()
var burn := PackedFloat32Array()
var lakes: Array = []
var strips: Array = []
var clearings: Array = []
var track := PackedVector2Array()      # the gravel track in from the mountain road (world.gd)
var solids: Array = []
var hollows: Array = []
var has_trees := true
var season := 0

# --- the fine grid ------------------------------------------------------------
var fh := PackedFloat32Array()
var orig := PackedFloat32Array()      # natural surface (dug depth = orig - h)
var pay_top := PackedFloat32Array()   # depth the pay gravel starts
var bedrock := PackedFloat32Array()   # depth of bedrock
var grade := PackedFloat32Array()     # g of gold per m3 of pay gravel
var dirty_chunks := {}                # Vector2i -> true (ground_view rebuilds)
var wat_dirty := {}                   # same, for water_sim.gd (ground heights it flows over)
var water: Node                       # water_sim.gd once it exists: pits, the creek, pumped water
var vox_dirty := {}                   # Vector2i chunk -> Rect2i of changed fine cells (voxel_ground re-stamps)
var modified := false


func _init() -> void:
	_add_strip("Proving Ground", Vector3(0, 6.2, -130.0), 90.0, 300.0, 18.0, 1, 1, true,
		"Gravel 09/27: home base, hangar, fuel and the mining claim.")
	# The demo is the square alone: one strip, no far mountains (DESIGN_NOTES 74).
	var lay_ := lay()
	var pond: Array = lay_["pond"]
	lakes.append({"name": "Claim Pond", "pos": pond[0], "radius": float(pond[1]), "level": 3.2, "depth": 1.2, "seed": 0.0})
	clearings.append(Vector3(-25.0, -94.0, 78.0))   # apron and hangar
	var pad: Vector2 = lay_["pad"]
	clearings.append(Vector3(pad.x, pad.y, 26.0))   # mining pad
	var mb := mudbog()
	clearings.append(Vector3(mb.x, mb.y, 26.0))     # the mud bog: nothing grows in it
	_fill_ecology()
	_fill_grid()
	_build_mud()


func _add_strip(sname: String, pos: Vector3, heading: float, length: float, width: float,
		surface: int, difficulty: int, fuel: bool, desc: String) -> void:
	var hr := deg_to_rad(heading)
	strips.append({"name": sname, "pos": pos, "heading": heading,
		"dir": Vector2(sin(hr), -cos(hr)), "length": length, "width": width,
		"surface": surface, "slope": 0.0, "difficulty": difficulty, "fuel": fuel, "desc": desc})


## Compatibility with the old island generator: the map is fixed.
func generate(_seed_value: int = 0, _cells: int = 0) -> void:
	pass


func _fill_ecology() -> void:
	var vn := n + 1
	forest.resize(vn * vn); bog.resize(vn * vn)
	creek.resize(vn * vn); burn.resize(vn * vn)
	for gj in range(vn):
		for gi in range(vn):
			var x := -half + gi * 40.0
			var z := -half + gj * 40.0
			var idx := gj * vn + gi
			var inside := absf(x) < SQ and absf(z) < SQ
			# Ecology carries on past the square and fades out over the plain,
			# rather than stopping dead at the edge (the bog and the tree line
			# used to end in a straight line there).
			var past := maxf(absf(x), absf(z)) - SQ
			var fade := 1.0 - smoothstep(0.0, 120.0, past)
			var b := MapGen.bog_weight(lay(), x, z) * fade
			var ck := clampf(1.0 - absf(Vector2(x, z).distance_to(lay()["pond"][0]) - 40.0) / 25.0, 0.0, 0.75)
			if inside:
				ck = maxf(ck, 0.85 * smoothstep(34.0, 8.0, creek_dist(x, z)))
			var f := 0.8 * (1.0 - smoothstep(0.0, 70.0, past))
			# Willow scrub round the outlying strips.
			for st in strips:
				var sp: Vector3 = st["pos"]
				if sp.x != 0.0 and Vector2(x - sp.x, z - sp.z).length() < 420.0 and Vector2(x - sp.x, z - sp.z).length() > 180.0:
					ck = maxf(ck, 0.45)
			f *= 1.0 - 0.55 * b
			forest[idx] = f
			bog[idx] = b
			creek[idx] = ck
			burn[idx] = 0.0
	heights.resize(vn * vn)
	for gj in range(vn):
		for gi in range(vn):
			heights[gj * vn + gi] = natural_height(-half + gi * CELL, -half + gj * CELL)


## Forest and bog weights at any spot (bilinear on the 40 m ecology grid),
## so things drawn outside the square use the same ground types as inside.
func zone_at(x: float, z: float) -> Vector2:
	var vn := n + 1
	var fx := clampf((x + half) / CELL, 0.0, float(vn - 1) - 0.001)
	var fz := clampf((z + half) / CELL, 0.0, float(vn - 1) - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var a := j * vn + i
	var f := lerpf(lerpf(forest[a], forest[a + 1], tx), lerpf(forest[a + vn], forest[a + vn + 1], tx), tz)
	var b := lerpf(lerpf(bog[a], bog[a + 1], tx), lerpf(bog[a + vn], bog[a + vn + 1], tx), tz)
	return Vector2(f, b)


## The mountain region round the square (region.gd, set by world.gd): its
## ground in game metres. region_xf takes a game point to region metres;
## region_dy is how far the region is lowered to the square's level.
static var region: Object = null
static var region_xf := Transform3D.IDENTITY
static var region_dy := 0.0


## The plain past the square: the region's mountains and valleys when there
## is one, else the flat plain.
static func outside_height(x: float, z: float) -> float:
	if region != null:
		var q: Vector3 = region_xf * Vector3(x, 0.0, z)
		return float(region.height(q.x, q.z)) - region_dy
	return PLAIN_Y + 0.6 * sin(x * 0.0021 + 1.0) * cos(z * 0.0017)


## The land as nature left it: rolling tundra, the knoll, the bog, the pond
## basin, with the runway, apron and pad bladed flat years ago.
static func natural_height(x: float, z: float) -> float:
	var edge := maxf(absf(x), absf(z))
	if edge > SQ + 90.0 or (edge > SQ and region != null):
		# (with the region the land past the square is the region's, which
		# eases out from the square's own edge itself: what you see is what
		# you drive on)
		return outside_height(x, z)
	var lay_ := lay()
	var h := MapGen.base_height(lay_, x, z)
	if edge < SQ + 1.0:
		var cd := creek_dist(x, z, 8.0)
		h -= 0.9 * smoothstep(6.0, 0.6, cd)
	var pond: Array = lay_["pond"]
	var dp := Vector2(x, z).distance_to(pond[0])
	var pr := float(pond[1])
	h = lerpf(h, 2.0, smoothstep(pr + 7.0, pr - 9.0, dp))
	h = lerpf(h, 6.2 + x * 0.004, _rect_w(x, z, 0.0, -130.0, 150.0, 9.0, 22.0))
	h = lerpf(h, 6.15, _rect_w(x, z, -25.0, -94.0, 72.0, 19.0, 14.0))
	# the mud bog (DESIGN_NOTES 112): a sunken pit with ramps at each end
	var bog_w := mudbog_weight(x, z)
	if bog_w > 0.0:
		h -= MUDBOG_DEPTH * bog_w
	var pad: Vector2 = lay_["pad"]
	if absf(x - pad.x) < 34.0 and absf(z - pad.y) < 32.0:
		if not lay_.has("pad_y"):
			lay_["pad_y"] = MapGen.base_height(lay_, pad.x, pad.y)
		h = lerpf(h, float(lay_["pad_y"]), _rect_w(x, z, pad.x, pad.y, 14.0, 12.0, 10.0))
	if edge > SQ:
		# Past the square the land eases down onto the open plain.
		# (a cliff past the edge - the mountain bench - breaks off sharp instead)
		var o := outside_height(x, z)
		var band := lerpf(90.0, 4.0, smoothstep(6.0, 30.0, h - o))
		h = lerpf(h, o, smoothstep(SQ, SQ + band, edge))
	return h


## Distance from a spot to the creek's centreline (anything past `reach`
## comes back as at least `reach`: segments that far off are skipped).
static func creek_dist(x: float, z: float, reach: float = 1.0e8) -> float:
	var p := Vector2(x, z)
	var best := 1.0e9
	var cr: Array = lay()["creek"]
	for i in range(cr.size() - 1):
		var a: Vector2 = cr[i]
		var b: Vector2 = cr[i + 1]
		if p.x < minf(a.x, b.x) - reach or p.x > maxf(a.x, b.x) + reach or p.y < minf(a.y, b.y) - reach or p.y > maxf(a.y, b.y) + reach:
			continue
		var ab := b - a
		var l2 := ab.length_squared()
		var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Running water in the creek bed here (pan and sluice work).
func creek_at(x: float, z: float) -> bool:
	return absf(x) < SQ and absf(z) < SQ and creek_dist(x, z) < 1.4


static func _rect_w(x: float, z: float, cx: float, cz: float, hx: float, hz: float, feather: float) -> float:
	var d := maxf(absf(x - cx) - hx, absf(z - cz) - hz)
	return smoothstep(1.0, 0.0, maxf(d, 0.0) / feather)


## What's in the ground: [grade g/m3, pay-top depth, bedrock depth]. In the
## square it's read off the grid (painted from the layout at start); outside
## it's the country rock with no pay.
func geology(x: float, z: float) -> Array:
	if absf(x) < SQ and absf(z) < SQ and grade.size() > 0:
		var vn := FN + 1
		var i := clampi(int(round((x + SQ) / FRES)), 0, FN)
		var j := clampi(int(round((z + SQ) / FRES)), 0, FN)
		var k := j * vn + i
		return [grade[k], pay_top[k], bedrock[k]]
	return _country(x, z)


## The country without any pay: overburden over bedrock, thicker in the
## muskeg, thin on the knoll.
static func _country(x: float, z: float) -> Array:
	var lay_ := lay()
	var kn: Array = lay_["knoll"]
	var k := maxf(0.0, 1.0 - Vector2(x, z).distance_to(kn[0]) / float(kn[1]))
	var w2 := sin(x * 0.043 - z * 0.051 + 2.0) * 0.5 + 0.5
	var bed := 3.0 + MapGen.bog_weight(lay_, x, z) * 1.6 + w2 * 0.6 - k * 2.5 * smoothstep(0.2, 0.8, k)
	bed = maxf(bed, 0.35)
	return [0.0, bed, bed]


## Paint the pay into the grid: buried channels (pay on bedrock, richest on
## the inside of bends, bedrock cut deeper under them), the bench terrace,
## and a thin modern streak in the creek gravels. Each line only touches the
## cells near it, so this stays quick.
func _paint_geology() -> void:
	var vn := FN + 1
	var lay_ := lay()
	var kn: Array = lay_["knoll"]
	var kc: Vector2 = kn[0]
	var kr := float(kn[1])
	for j in range(vn):
		var z := -SQ + j * FRES
		for i in range(vn):
			var x := -SQ + i * FRES
			var k := maxf(0.0, 1.0 - Vector2(x, z).distance_to(kc) / kr)
			var w2 := sin(x * 0.043 - z * 0.051 + 2.0) * 0.5 + 0.5
			var bed := maxf(3.0 + MapGen.bog_weight(lay_, x, z) * 1.6 + w2 * 0.6 - k * 2.5 * smoothstep(0.2, 0.8, k), 0.35)
			var idx := j * vn + i
			grade[idx] = 0.0
			pay_top[idx] = bed
			bedrock[idx] = bed
	# modern creek: a thin streak near the surface
	_paint_line(lay_["creek"], 22.0, func(d: float, _s: float, _bend: float, idx: int, x: float, z: float) -> void:
		var pay := 0.45 * smoothstep(22.0, 3.0, d)
		if pay < 0.05:
			return
		var w1 := sin(x * 0.11 + z * 0.07) * 0.5 + 0.5
		var g := pay * (0.3 + 1.6 * w1)
		if g > grade[idx]:
			grade[idx] = g
			pay_top[idx] = lerpf(bedrock[idx], 0.6 + 0.8 * w1, pay)
	)
	# the bench terrace: shallow gravel left high when the creek cut down
	_paint_line(lay_["bench"], 9.0, func(d: float, _s: float, _bend: float, idx: int, x: float, z: float) -> void:
		var pb := smoothstep(9.0, 2.0, d)
		if pb < 0.05:
			return
		var w1 := sin(x * 0.09 - z * 0.06) * 0.5 + 0.5
		var g := pb * 0.5 * (0.6 + 1.4 * w1)
		if g > grade[idx]:
			grade[idx] = g
			pay_top[idx] = 0.5 + 0.4 * w1
			bedrock[idx] = maxf(minf(bedrock[idx], pay_top[idx] + 0.7), pay_top[idx] + 0.4)
	)
	# the buried channels: the real pay
	for ch in lay_["channels"]:
		var w := float(ch["w"])
		_paint_line(ch["pts"], w * 1.7, func(d: float, s: float, bend: float, idx: int, x: float, z: float) -> void:
			var prof := smoothstep(w * 1.6, w * 0.25, d)
			if prof < 0.02:
				return
			var g := prof * MapGen.richness(ch, s) * bend
			var bed2: float = bedrock[idx] + 1.4 * prof
			if g > grade[idx]:
				grade[idx] = g
				bedrock[idx] = bed2
				pay_top[idx] = bed2 - (0.4 + 1.1 * prof)
			else:
				bedrock[idx] = maxf(bedrock[idx], bed2)
		)


## Call `f(dist, arc_length, bend_factor, idx, x, z)` for every fine cell
## within `reach` of the polyline, with its closest segment's numbers.
func _paint_line(pts: Array, reach: float, f: Callable) -> void:
	if pts.size() < 2:
		return
	var vn := FN + 1
	var bd := PackedFloat32Array()        # closest distance so far per cell (touched ones)
	bd.resize(vn * vn)
	bd.fill(1.0e9)
	var bs := PackedFloat32Array()
	bs.resize(vn * vn)
	var bb := PackedFloat32Array()
	bb.resize(vn * vn)
	var touched := PackedInt32Array()
	var s := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var seg := sqrt(l2)
		# how hard the line turns here (+ left) for the inside-of-bend bonus
		var curv := 0.0
		if i > 0 and i < pts.size() - 2:
			var d0: Vector2 = a - (pts[i - 1] as Vector2)
			var d1: Vector2 = (pts[i + 2] as Vector2) - b
			curv = d0.normalized().cross(d1.normalized())
		var i0 := clampi(int((minf(a.x, b.x) - reach + SQ) / FRES), 0, FN)
		var i1 := clampi(int((maxf(a.x, b.x) + reach + SQ) / FRES) + 1, 0, FN)
		var j0 := clampi(int((minf(a.y, b.y) - reach + SQ) / FRES), 0, FN)
		var j1 := clampi(int((maxf(a.y, b.y) + reach + SQ) / FRES) + 1, 0, FN)
		for j in range(j0, j1 + 1):
			var z := -SQ + j * FRES
			for ii in range(i0, i1 + 1):
				var x := -SQ + ii * FRES
				var p := Vector2(x, z)
				var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
				var d := p.distance_to(a + ab * t)
				if d > reach:
					continue
				var idx := j * vn + ii
				if bd[idx] <= d:
					continue
				var side := signf(ab.cross(p - a))
				var bend := 1.0
				if absf(curv) > 0.02:
					var k := clampf(absf(curv) * 4.0, 0.0, 1.0)
					bend = (1.0 + 1.6 * k) if side == signf(curv) else (1.0 - 0.45 * k)   # inside bends collect, outside bends scour
				if bd[idx] > 1.0e8:
					touched.append(idx)
				bd[idx] = d
				bs[idx] = s + seg * t
				bb[idx] = bend
		s += seg
	for idx in touched:
		f.call(bd[idx], bs[idx], bb[idx], idx, -SQ + (idx % vn) * FRES, -SQ + (idx / vn) * FRES)


func _fill_grid() -> void:
	var vn := FN + 1
	fh.resize(vn * vn)
	orig.resize(vn * vn)
	pay_top.resize(vn * vn)
	bedrock.resize(vn * vn)
	grade.resize(vn * vn)
	for j in range(vn):
		var z := -SQ + j * FRES
		for i in range(vn):
			var x := -SQ + i * FRES
			var idx := j * vn + i
			var h := natural_height(x, z)
			fh[idx] = h
			orig[idx] = h
	_paint_geology()


# ------------------------------------------------------------------------------
#  Height and normal queries (the fine grid inside the square, void outside)
# ------------------------------------------------------------------------------
func inside(x: float, z: float) -> bool:
	return absf(x) < SQ - 0.6 and absf(z) < SQ - 0.6


func height_at(x: float, z: float) -> float:
	if absf(x) >= SQ or absf(z) >= SQ:
		return natural_height(x, z)
	var fx := (x + SQ) / FRES
	var fz := (z + SQ) / FRES
	var i := mini(int(fx), FN - 1)
	var j := mini(int(fz), FN - 1)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var vn := FN + 1
	var idx := j * vn + i
	var h00 := fh[idx]
	var h10 := fh[idx + 1]
	var h01 := fh[idx + vn]
	var h11 := fh[idx + vn + 1]
	if tx > tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


## The ground as nature left it (before any digging).
func height_at_base(x: float, z: float) -> float:
	return natural_at(x, z)


func natural_at(x: float, z: float) -> float:
	if absf(x) >= SQ or absf(z) >= SQ:
		return natural_height(x, z)
	var fx := (x + SQ) / FRES
	var fz := (z + SQ) / FRES
	var i := mini(int(fx), FN - 1)
	var j := mini(int(fz), FN - 1)
	var vn := FN + 1
	return orig[j * vn + i]


func normal_at(x: float, z: float) -> Vector3:
	var e := FRES
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)).normalized()


# ------------------------------------------------------------------------------
#  Water (the pond; groundwater sim comes later - DESIGN_NOTES 62)
# ------------------------------------------------------------------------------
func _water_level(x: float, z: float, h: float) -> float:
	var pond: Array = lay()["pond"]
	if Vector2(x, z).distance_to(pond[0]) < float(pond[1]) + 7.0 and h < 3.2:
		return 3.2
	return NO_WATER


func water_level_at(x: float, z: float) -> float:
	var h := height_at(x, z)
	if water != null:
		var w: float = water.depth_at(x, z)
		if w > 0.03:
			return maxf(h + w, _water_level(x, z, h))
	return _water_level(x, z, h)


## Where the groundwater stands (DESIGN_NOTES 62): close under wet ground -
## the creek flats, the muskeg, round the pond - and deeper under dry ground
## and the knoll. Dig below it and water seeps into the hole.
func water_table_at(x: float, z: float) -> float:
	var cd := creek_dist(x, z)
	var nat := natural_at(x, z) + 0.9 * smoothstep(6.0, 0.6, cd)    # the banks, not the cut bed
	var wet := wet_at(x, z)
	var knl: Array = lay()["knoll"]
	var kn := maxf(0.0, 1.0 - Vector2(x, z).distance_to(knl[0]) / float(knl[1]))
	var depth := lerpf(2.6, 0.55, clampf(wet * 1.4, 0.0, 1.0)) + kn * 6.0
	# the creek runs because its bed is cut a little below the table
	depth = lerpf(0.55, depth, smoothstep(1.5, 9.0, cd))
	var t := nat - depth
	var pond: Array = lay()["pond"]
	var dp := Vector2(x, z).distance_to(pond[0])
	return lerpf(3.2, t, smoothstep(float(pond[1]) + 3.0, float(pond[1]) + 33.0, dp))      # the pond holds it up near its shore


func lakes_frozen() -> bool:
	return season == 2


func snow_line() -> float:
	return 1350.0 if season != 2 else -1000.0


# ------------------------------------------------------------------------------
#  Strips, clearings, buildings (same shapes as the old terrain API)
# ------------------------------------------------------------------------------
func strip_index_at(x: float, z: float, margin: float = 0.0) -> int:
	for k in range(strips.size()):
		var s: Dictionary = strips[k]
		var p: Vector3 = s["pos"]
		var dir: Vector2 = s["dir"]
		var dx := x - p.x
		var dz := z - p.z
		if absf(dx * dir.x + dz * dir.y) <= float(s["length"]) * 0.5 + margin \
				and absf(-dx * dir.y + dz * dir.x) <= float(s["width"]) * 0.5 + margin:
			return k
	return -1


func strip_local(k: int, x: float, z: float) -> Vector2:
	var s: Dictionary = strips[k]
	var p: Vector3 = s["pos"]
	var dir: Vector2 = s["dir"]
	var dx := x - p.x
	var dz := z - p.z
	return Vector2(dx * dir.x + dz * dir.y, -dx * dir.y + dz * dir.x)


func strip_point(k: int, along: float, across: float = 0.0) -> Vector3:
	var s: Dictionary = strips[k]
	var p: Vector3 = s["pos"]
	var dir: Vector2 = s["dir"]
	var x := p.x + dir.x * along - dir.y * across
	var z := p.z + dir.y * along + dir.x * across
	return Vector3(x, ground_level_at(x, z), z)


func nearest_strip(x: float, z: float) -> int:
	var best := -1
	var best_d := 1.0e18
	for k in range(strips.size()):
		var p: Vector3 = strips[k]["pos"]
		var d := (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z)
		if d < best_d:
			best_d = d
			best = k
	return best


func add_player_strip(d: Dictionary) -> int:
	var hr := deg_to_rad(float(d["heading"]))
	strips.append({"name": String(d["name"]), "pos": d["pos"], "heading": float(d["heading"]),
		"dir": Vector2(sin(hr), -cos(hr)), "length": float(d["length"]), "width": 14.0,
		"surface": 2, "slope": float(d.get("slope", 0.0)), "difficulty": 3, "fuel": false,
		"player": true, "desc": "Your own bush strip: rough grass, cut out of the bush."})
	return strips.size() - 1


func player_strip_index(nth: int) -> int:
	var c := 0
	for k in range(strips.size()):
		if bool(strips[k].get("player", false)):
			if c == nth:
				return k
			c += 1
	return -1


func lake_radius(lake: Dictionary, _angle: float) -> float:
	return float(lake["radius"])


static func hash01(i: int, j: int, k: int) -> float:
	var h: int = (i * 374761393 + j * 668265263 + k * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


## The chart: the whole 6 km map, one pixel per 40 m cell.
func make_map_image() -> Image:
	var vn := n + 1
	var img := Image.create(vn, vn, false, Image.FORMAT_RGB8)
	for j in range(vn):
		var z := -half + j * CELL
		for i in range(vn):
			var x := -half + i * CELL
			var h := height_at(x, z)
			var col := Color(0.80, 0.84, 0.66).lerp(Color(0.86, 0.82, 0.62), clampf(h / 20.0, 0.0, 1.0))
			if _water_level(x, z, h) > -1.0e8:
				col = Color(0.55, 0.70, 0.82)
			elif absf(x) < SQ and absf(z) < SQ:
				col = col.lerp(Color(0.56, 0.70, 0.50), Flora.field(self, forest, x, z) * 0.55)
			if strip_index_at(x, z, 15.0) >= 0:
				col = Color(0.55, 0.50, 0.45)
			img.set_pixel(i, j, col)
	return img


func in_strip_clearing(x: float, z: float) -> bool:
	for strip in strips:
		var p: Vector3 = strip["pos"]
		var dir: Vector2 = strip["dir"]
		var hl: float = strip["length"] * 0.5
		var hw: float = strip["width"] * 0.5
		var dx := x - p.x
		var dz := z - p.z
		var along := absf(dx * dir.x + dz * dir.y)
		var across := absf(-dx * dir.y + dz * dir.x)
		if along < hl + 90.0 and across < hw + 60.0:
			return true
		if along < hl + 480.0 and across < hw + 40.0 + (along - hl) * 0.12:
			return true
	return false


func clear_spot(x: float, z: float, radius: float) -> void:
	clearings.append(Vector3(x, z, radius))


## Level a building's site (DESIGN_NOTES 152): the footprint `sx` x `sz`
## (in the building's frame `xf`) plus `margin` all round goes flat at the
## building's base height, and round it the ground eases back to what was
## there on a gentle grade (about 1 in 3, never shorter than `min_grade` m),
## cut on the uphill side and filled on the downhill one, so no corner
## floats and no wall is buried. It is the natural ground from then on
## (orig too), not a dig.
func pad(xf: Transform3D, sx: float, sz: float, margin: float = 1.0, min_grade: float = 2.5) -> void:
	var target := xf.origin.y
	var hx := sx * 0.5 + margin
	var hz := sz * 0.5 + margin
	var reach := 16.0
	var inv := xf.affine_inverse()
	var vn := FN + 1
	var rad := Vector2(hx, hz).length() + reach
	var ci := int(round((xf.origin.x + SQ) / FRES))
	var cj := int(round((xf.origin.z + SQ) / FRES))
	var rc := int(ceil(rad / FRES))
	for j in range(maxi(cj - rc, 0), mini(cj + rc, FN) + 1):
		for i in range(maxi(ci - rc, 0), mini(ci + rc, FN) + 1):
			var wx := -SQ + i * FRES
			var wz := -SQ + j * FRES
			var l: Vector3 = inv * Vector3(wx, target, wz)
			var dx := maxf(absf(l.x) - hx, 0.0)
			var dz := maxf(absf(l.z) - hz, 0.0)
			var d := sqrt(dx * dx + dz * dz)
			var idx := j * vn + i
			var h := orig[idx]
			var g := clampf(absf(h - target) * 3.0, min_grade, reach)
			if d >= g:
				continue
			var w := 1.0 - smoothstep(0.0, g, d)
			var nh := lerpf(h, target, w)
			var dug := orig[idx] - fh[idx]
			orig[idx] = nh
			fh[idx] = nh - dug
	_mark_dirty(ci, cj, rc + 2)


func is_cleared(x: float, z: float, margin: float = 0.0) -> bool:
	if strip_index_at(x, z, margin) >= 0:
		return true
	for c in clearings:
		var r: float = c.z + margin * 0.5
		if (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y) < r * r:
			return true
	return false


func add_solid(xf: Transform3D, sz: Vector3) -> void:
	solids.append({"xf": xf, "inv": xf.affine_inverse(), "size": sz,
		"r": Vector2(sz.x, sz.z).length() * 0.5 + 1.0})


func add_hollow(xf: Transform3D, sz: Vector3, door_w: float) -> void:
	hollows.append({"xf": xf, "inv": xf.affine_inverse(), "size": sz, "door": door_w,
		"r": Vector2(sz.x, sz.z).length() * 0.5 + 1.0})


## Floors you walk up onto inside buildings (stairs, lofts): a box footprint
## with its height running from h0 at -Z to h1 at +Z (DESIGN_NOTES 78).
var platforms: Array = []
func add_platform(xf: Transform3D, sz: Vector3, h0: float, h1: float) -> void:
	platforms.append({"xf": xf, "inv": xf.affine_inverse(), "size": sz, "h0": h0, "h1": h1,
		"r": Vector2(sz.x, sz.z).length() * 0.5 + 0.5})


## Things in the world that come and go or move (DESIGN_NOTES 141): keyed
## so they can be moved or taken away. A solid blocks walkers, vehicles and
## planes (equipment, crates, a parked truck); a platform is something low
## you step up onto and wheels roll over (a rock, a log, a dropped tool).
func set_solid(key: String, xf: Transform3D, sz: Vector3) -> void:
	clear_solid(key)
	solids.append({"xf": xf, "inv": xf.affine_inverse(), "size": sz, "key": key,
		"r": Vector2(sz.x, sz.z).length() * 0.5 + 1.0})


func clear_solid(key: String) -> void:
	for i in range(solids.size() - 1, -1, -1):
		if String((solids[i] as Dictionary).get("key", "")) == key:
			solids.remove_at(i)


func set_platform(key: String, xf: Transform3D, sz: Vector3) -> void:
	clear_platform(key)
	platforms.append({"xf": xf, "inv": xf.affine_inverse(), "size": sz, "h0": sz.y, "h1": sz.y, "key": key,
		"r": Vector2(sz.x, sz.z).length() * 0.5 + 0.5})


func clear_platform(key: String) -> void:
	for i in range(platforms.size() - 1, -1, -1):
		if String((platforms[i] as Dictionary).get("key", "")) == key:
			platforms.remove_at(i)


## Vehicles as boxes (DESIGN_NOTES 141): a walker can't walk through a
## truck, and machines can't drive through each other. Kept apart from
## `solids` so a machine never hits its own box and the plane on the tug's
## bar doesn't hit the tug.
var movers := {}                 # key -> {node, xf, inv, size, r}
func set_mover(key: String, node: Node3D, xf: Transform3D, sz: Vector3) -> void:
	movers[key] = {"node": node, "xf": xf, "inv": xf.affine_inverse(), "size": sz, "r": Vector2(sz.x, sz.z).length() * 0.5 + 0.5}


## The machine box p (with girth r) is inside, other than `skip`'s own: {} or the mover.
func mover_at(p: Vector3, r: float, skip: Node = null) -> Dictionary:
	for k in movers:
		var mv: Dictionary = movers[k]
		if mv["node"] == skip:
			continue
		# a trailer on its hitch and the truck pulling it don't block each other
		if skip != null:
			var tw_a = skip.get("towing")
			var tw_b = (mv["node"] as Node).get("towing")
			if (tw_a is Node and tw_a == mv["node"]) or (tw_b is Node and tw_b == skip):
				continue
		var o: Vector3 = (mv["xf"] as Transform3D).origin
		if absf(p.x - o.x) > float(mv["r"]) + r or absf(p.z - o.z) > float(mv["r"]) + r:
			continue
		var l: Vector3 = (mv["inv"] as Transform3D) * p
		var sz: Vector3 = mv["size"]
		if absf(l.x) < sz.x * 0.5 + r and absf(l.z) < sz.z * 0.5 + r and l.y > -1.0 and l.y < sz.y:
			return mv
	return {}


## What a wheel rests on: the ground, or a log or rock lying on it.
func wheel_ground(x: float, z: float) -> float:
	var g := height_at(x, z)
	if platforms.is_empty():
		return g
	var pf := platform_y(Vector3(x, g, z), 0.6)
	return maxf(g, pf)


## The platform floor under p a walker can step onto (within `step` of his
## feet), or -INF.
func platform_y(p: Vector3, step: float = 0.45) -> float:
	var best := -INF
	for pf in platforms:
		var o: Vector3 = (pf["xf"] as Transform3D).origin
		if absf(p.x - o.x) > float(pf["r"]) or absf(p.z - o.z) > float(pf["r"]):
			continue
		var l: Vector3 = (pf["inv"] as Transform3D) * p
		var sz: Vector3 = pf["size"]
		if absf(l.x) > sz.x * 0.5 or absf(l.z) > sz.z * 0.5:
			continue
		var h: float = o.y + lerpf(float(pf["h0"]), float(pf["h1"]), (l.z + sz.z * 0.5) / sz.z)
		if h <= p.y + step and h > best:
			best = h
	return best


func blocked_by_building(p: Vector3, r: float = 0.6, skip: Node = null) -> bool:
	if skip != null and not mover_at(p, r * 0.6, skip).is_empty():
		return true
	for hb in hollows:
		var o: Vector3 = (hb["xf"] as Transform3D).origin
		if absf(p.x - o.x) > float(hb["r"]) + r or absf(p.z - o.z) > float(hb["r"]) + r:
			continue
		var l: Vector3 = (hb["inv"] as Transform3D) * p
		var sz: Vector3 = hb["size"]
		if l.y > sz.y or l.y < -1.0:
			continue
		var hx := sz.x * 0.5
		var hz := sz.z * 0.5
		var dh: float = float(hb["door"]) * 0.5
		if absf(l.z) < hz + r and absf(absf(l.x) - hx) < r + 0.2:
			return true
		if absf(l.x) < hx + r and absf(l.z - hz) < r + 0.2:
			return true
		if absf(l.x) > dh - r and absf(l.x) < hx + r and absf(l.z + hz) < r + 0.2:
			return true
	for sb in solids:
		var o2: Vector3 = (sb["xf"] as Transform3D).origin
		if absf(p.x - o2.x) > float(sb["r"]) + r or absf(p.z - o2.z) > float(sb["r"]) + r:
			continue
		var l2: Vector3 = (sb["inv"] as Transform3D) * p
		var s2: Vector3 = sb["size"]
		if absf(l2.x) < s2.x * 0.5 + r and absf(l2.z) < s2.z * 0.5 + r and l2.y > -1.0 and l2.y < s2.y:
			return true
	return false


func hollow_at(x: float, z: float) -> Dictionary:
	for hb in hollows:
		var o: Vector3 = (hb["xf"] as Transform3D).origin
		if absf(x - o.x) > float(hb["r"]) or absf(z - o.z) > float(hb["r"]):
			continue
		var l: Vector3 = (hb["inv"] as Transform3D) * Vector3(x, o.y, z)
		var sz: Vector3 = hb["size"]
		if absf(l.x) < sz.x * 0.5 and absf(l.z) < sz.z * 0.5 + 0.6:
			return hb
	return {}


func ground_level_at(x: float, z: float) -> float:
	if not hollows.is_empty():
		var hb := hollow_at(x, z)
		if not hb.is_empty():
			return (hb["xf"] as Transform3D).origin.y + 0.06
	var h := height_at(x, z)
	if lakes_frozen():
		var wl := _water_level(x, z, h)
		if wl > 1.0:
			return wl
	return h


func ground_normal_at(x: float, z: float) -> Vector3:
	if not hollows.is_empty() and not hollow_at(x, z).is_empty():
		return Vector3.UP
	if lakes_frozen():
		var wl := _water_level(x, z, height_at(x, z))
		if wl > 1.0:
			return Vector3.UP
	return normal_at(x, z)


func surface_at(x: float, z: float) -> int:
	var h := height_at(x, z)
	var wl := _water_level(x, z, h)
	if wl > -1.0e8:
		if lakes_frozen() and wl > 1.0:
			return 6    # SURF_ICE
		return 7        # SURF_WATER
	if orig_depth_at(x, z) > 0.15:
		return 3        # SURF_DIRT: torn-up ground
	var si := strip_index_at(x, z)
	if si >= 0:
		return int(strips[si]["surface"])
	if zone4(x, z).r > 0.5:
		return 1        # SURF_GRAVEL (apron, pad)
	return 0            # SURF_ROUGH


## How deep below the natural surface this spot has been dug.
func orig_depth_at(x: float, z: float) -> float:
	if absf(x) >= SQ or absf(z) >= SQ:
		return 0.0
	var vn := FN + 1
	var i := mini(int((x + SQ) / FRES), FN)
	var j := mini(int((z + SQ) / FRES), FN)
	var idx := j * vn + i
	return maxf(orig[idx] - fh[idx], 0.0)


# ------------------------------------------------------------------------------
#  Trees (flora.gd decides where everything grows)
# ------------------------------------------------------------------------------
func forest_at(x: float, z: float) -> float:
	return Flora.field(self, forest, x, z)


func tree_near(p: Vector3) -> Dictionary:
	if not has_trees:
		return {}
	return Flora.tree_near(self, p)


func hits_tree(p: Vector3) -> bool:
	var t := tree_near(p)
	return not t.is_empty() and float(t["dist"]) < float(t["crown_r"])


# ------------------------------------------------------------------------------
#  Zone weights for the ground shader (natural look; digging shows through
#  via the dug depth the view writes per vertex)
# ------------------------------------------------------------------------------
func zone4(x: float, z: float) -> Color:
	var lay_ := lay()
	var pad: Vector2 = lay_["pad"]
	var grav := maxf(_rect_w(x, z, 0.0, -130.0, 150.0, 9.0, 8.0),
		maxf(_rect_w(x, z, -25.0, -94.0, 72.0, 19.0, 7.0),
		_rect_w(x, z, pad.x, pad.y, 14.0, 12.0, 6.0)))
	var b := MapGen.bog_weight(lay_, x, z) * (1.0 - grav)
	var pond: Array = lay_["pond"]
	var dp := Vector2(x, z).distance_to(pond[0])
	var sand := clampf(1.0 - absf(dp - float(pond[1])) / 9.0, 0.0, 1.0) * (1.0 - grav)
	var knl: Array = lay_["knoll"]
	var k := maxf(0.0, 1.0 - Vector2(x, z).distance_to(knl[0]) / float(knl[1]))
	sand = maxf(sand, 0.8 * smoothstep(2.6, 0.8, creek_dist(x, z, 3.0)))     # creek gravel and silt
	return Color(grav, b, sand, clampf(k * 1.6 - 0.25, 0.0, 1.0))


func wet_at(x: float, z: float) -> float:
	var lay_ := lay()
	var b := MapGen.bog_weight(lay_, x, z) + 0.9 * smoothstep(3.5, 0.5, creek_dist(x, z, 4.0))
	var pond: Array = lay_["pond"]
	var dp := Vector2(x, z).distance_to(pond[0])
	return clampf(0.38 * b + 0.5 * smoothstep(float(pond[1]) + 7.0, float(pond[1]) - 3.0, dp), 0.0, 1.0)


# ------------------------------------------------------------------------------
#  Deformation: dig, grade, pile - anywhere on the square
# ------------------------------------------------------------------------------
func _mark_dirty(ci: int, cj: int, rc: int) -> void:
	var c0i := maxi((ci - rc) / CHUNK_CELLS, 0)
	var c1i := mini((ci + rc) / CHUNK_CELLS, CHUNKS - 1)
	var c0j := maxi((cj - rc) / CHUNK_CELLS, 0)
	var c1j := mini((cj + rc) / CHUNK_CELLS, CHUNKS - 1)
	for cj2 in range(c0j, c1j + 1):
		for ci2 in range(c0i, c1i + 1):
			dirty_chunks[Vector2i(ci2, cj2)] = true
	var r := Rect2i(maxi(ci - rc, 0), maxi(cj - rc, 0), 0, 0)
	r.end = Vector2i(mini(ci + rc, FN), mini(cj + rc, FN))
	var key := Vector2i(ci / CHUNK_CELLS, cj / CHUNK_CELLS)
	vox_dirty[key] = (vox_dirty[key] as Rect2i).merge(r) if vox_dirty.has(key) else r
	wat_dirty[key] = (wat_dirty[key] as Rect2i).merge(r) if wat_dirty.has(key) else r


## Dig out about `want` cubic metres round `c` (a bucket's bite). Returns
## {"over": m3, "pay": m3, "g": grams of gold, "bedrock": bool}.
## `rock`: how well this tool breaks rock below the bedrock line, 0 (it's a
## floor) .. 1 (like gravel). A pick ~0.6, a shovel or bucket ~0.15.
func dig(c: Vector3, radius: float, want: float, rock: float = 0.0) -> Dictionary:
	var out := {"over": 0.0, "pay": 0.0, "g": 0.0, "bedrock": false, "rock": 0.0}
	var vn := FN + 1
	var ci := int(round((c.x + SQ) / FRES))
	var cj := int(round((c.z + SQ) / FRES))
	var rc := int(ceil(radius / FRES))
	var cells: Array = []
	var wsum := 0.0
	for j in range(maxi(cj - rc, 0), mini(cj + rc, FN) + 1):
		for i in range(maxi(ci - rc, 0), mini(ci + rc, FN) + 1):
			var d := Vector2(-SQ + i * FRES - c.x, -SQ + j * FRES - c.z).length()
			if d > radius:
				continue
			var w := 1.0 - (d / radius) * (d / radius)
			cells.append([i, j, w])
			wsum += w
	if cells.is_empty():
		return out
	var cell_area := FRES * FRES
	var depth := want / (wsum * cell_area)
	for cw in cells:
		var i: int = cw[0]
		var j: int = cw[1]
		var idx := j * vn + i
		var h := fh[idx]
		var floor_h: float = orig[idx] - bedrock[idx]
		var wantc := depth * float(cw[2])
		var take := minf(wantc, maxf(h - floor_h, 0.0))
		if take < wantc - 0.001:
			out["bedrock"] = true
			if rock > 0.0:
				var rk := (wantc - take) * rock
				out["rock"] = float(out["rock"]) + rk * FRES * FRES
				fh[idx] = h - take - rk
				h = fh[idx] + take
		if take <= 0.0:
			continue
		var top_d: float = orig[idx] - h
		var bot_d := top_d + take
		var pay := maxf(minf(bot_d, bedrock[idx]) - maxf(top_d, pay_top[idx]), 0.0)
		var over := take - pay
		out["over"] = float(out["over"]) + over * cell_area
		out["pay"] = float(out["pay"]) + pay * cell_area
		out["g"] = float(out["g"]) + pay * cell_area * grade[idx]
		fh[idx] = h - take
	_slump(ci, cj, rc + 3)
	_mark_dirty(ci, cj, rc + 10)
	modified = true
	return out


## A bucket's teeth dragged through the ground: take up to `want` m3 of what
## stands above `floor_y` within `radius` of `c` - never deeper than the teeth
## went, never through bedrock. Same result dictionary as dig().
func cut_to(c: Vector3, radius: float, floor_y: float, want: float, rock: float = 0.0) -> Dictionary:
	var out := {"over": 0.0, "pay": 0.0, "g": 0.0, "bedrock": false, "rock": 0.0}
	if want <= 0.0:
		return out
	var vn := FN + 1
	var ci := int(round((c.x + SQ) / FRES))
	var cj := int(round((c.z + SQ) / FRES))
	var rc := int(ceil(radius / FRES))
	var cell_area := FRES * FRES
	var cells: Array = []
	var avail := 0.0
	for j in range(maxi(cj - rc, 0), mini(cj + rc, FN) + 1):
		for i in range(maxi(ci - rc, 0), mini(ci + rc, FN) + 1):
			var d := Vector2(-SQ + i * FRES - c.x, -SQ + j * FRES - c.z).length()
			if d > radius:
				continue
			var idx := j * vn + i
			var rock_y: float = orig[idx] - bedrock[idx]
			var want_lo := floor_y + 0.25 * (d / radius) * (d / radius)
			var lo := maxf(want_lo, rock_y)
			if floor_y < rock_y - 0.02:
				out["bedrock"] = true
				if rock > 0.0 and fh[idx] - 0.001 <= rock_y + 0.001:
					# already down on rock here: scrape a little of it off
					var rk := minf((fh[idx] - want_lo) * rock * 0.25, 0.08)
					if rk > 0.0:
						fh[idx] -= rk
						out["rock"] = float(out["rock"]) + rk * cell_area
			var take := fh[idx] - lo
			if take > 0.0:
				cells.append([idx, take])
				avail += take * cell_area
	if avail <= 0.0:
		return out
	var k := minf(want / avail, 1.0)
	for cw in cells:
		var idx2: int = cw[0]
		var take2 := float(cw[1]) * k
		var h := fh[idx2]
		var top_d: float = orig[idx2] - h
		var pay := maxf(minf(top_d + take2, bedrock[idx2]) - maxf(top_d, pay_top[idx2]), 0.0)
		out["over"] = float(out["over"]) + (take2 - pay) * cell_area
		out["pay"] = float(out["pay"]) + pay * cell_area
		out["g"] = float(out["g"]) + pay * cell_area * grade[idx2]
		fh[idx2] = h - take2
	_slump(ci, cj, rc + 3)
	_mark_dirty(ci, cj, rc + 8)
	modified = true
	return out


## Grade toward one level (a dozer blade): cut above `target` (within the
## cut budget), fill below it from `fill_m3`. Two passes - wants, then scale
## to the budgets - so a short budget thins the whole pass evenly.
func level(c: Vector3, radius: float, target: float, fill_m3: float, cut_m3: float = 1.0e9, max_step: float = 0.30, holes_only: bool = false) -> Dictionary:
	var out := {"over": 0.0, "pay": 0.0, "g": 0.0, "filled": 0.0, "bedrock": false}
	var vn := FN + 1
	var ci := int(round((c.x + SQ) / FRES))
	var cj := int(round((c.z + SQ) / FRES))
	var rc := int(ceil(radius / FRES))
	var cell_area := FRES * FRES
	var cuts: Array = []
	var fills: Array = []
	var cut_want := 0.0
	var fill_want := 0.0
	for j in range(maxi(cj - rc, 0), mini(cj + rc, FN) + 1):
		for i in range(maxi(ci - rc, 0), mini(ci + rc, FN) + 1):
			var d := Vector2(-SQ + i * FRES - c.x, -SQ + j * FRES - c.z).length()
			if d > radius:
				continue
			var w := clampf(1.6 * (1.0 - (d / radius) * (d / radius)), 0.0, 1.0)
			var idx := j * vn + i
			var h := fh[idx]
			var want := lerpf(h, target, w)
			if want < h:
				var floor_h: float = orig[idx] - bedrock[idx]
				var take := minf(minf(h - want, max_step * w), maxf(h - floor_h, 0.0))
				if take <= 0.0 and h - want > 0.02:
					out["bedrock"] = true
				if take > 0.0:
					cuts.append([idx, take])
					cut_want += take * cell_area
			elif want > h and (not holes_only or h < orig[idx] - 0.03):
				if holes_only:
					want = minf(want, orig[idx])      # a blade at track level fills holes, not the open ground
				var put := minf(want - h, max_step * w)
				if put > 0.0:
					fills.append([idx, put])
					fill_want += put * cell_area
	var cut_k := minf(cut_m3 / cut_want, 1.0) if cut_want > 0.0 else 0.0
	var fill_k := minf(fill_m3 / fill_want, 1.0) if fill_want > 0.0 else 0.0
	for cw2 in cuts:
		var idx2: int = cw2[0]
		var take2 := float(cw2[1]) * cut_k
		if take2 <= 0.0:
			continue
		var h2 := fh[idx2]
		var top_d: float = orig[idx2] - h2
		var bot_d := top_d + take2
		var pay := maxf(minf(bot_d, bedrock[idx2]) - maxf(top_d, pay_top[idx2]), 0.0)
		out["pay"] = float(out["pay"]) + pay * cell_area
		out["over"] = float(out["over"]) + (take2 - pay) * cell_area
		out["g"] = float(out["g"]) + pay * cell_area * grade[idx2]
		fh[idx2] = h2 - take2
	for fw2 in fills:
		var put2 := float(fw2[1]) * fill_k
		if put2 > 0.0:
			fh[fw2[0]] += put2
			out["filled"] = float(out["filled"]) + put2 * cell_area
	_slump(ci, cj, rc + 2)
	_mark_dirty(ci, cj, rc + 8)
	modified = true
	return out


## Pile `vol` cubic metres (as dug, it bulks up) round `c`, as a cone.
func deposit(c: Vector3, vol: float) -> void:
	var vn := FN + 1
	var radius := 1.4
	var ci := int(round((c.x + SQ) / FRES))
	var cj := int(round((c.z + SQ) / FRES))
	var rc := int(ceil(radius / FRES))
	var cells: Array = []
	var wsum := 0.0
	for j in range(maxi(cj - rc, 0), mini(cj + rc, FN) + 1):
		for i in range(maxi(ci - rc, 0), mini(ci + rc, FN) + 1):
			var d := Vector2(-SQ + i * FRES - c.x, -SQ + j * FRES - c.z).length()
			if d > radius:
				continue
			cells.append([i, j, 1.0 - d / radius])
			wsum += 1.0 - d / radius
	if cells.is_empty():
		return
	var add := vol * SWELL / (wsum * FRES * FRES)
	for cw in cells:
		fh[int(cw[1]) * vn + int(cw[0])] += add * float(cw[2])
	_slump(ci, cj, rc + 6)
	_mark_dirty(ci, cj, rc + 12)
	modified = true


## Loose ground won't stand steeper than fresh-dug banks allow: let it slide.
func _slump(ci: int, cj: int, r: int) -> void:
	var vn := FN + 1
	var max_step := FRES * 1.15
	for _pass in range(6):
		var moved := false
		for j in range(maxi(cj - r, 0), mini(cj + r, FN) + 1):
			for i in range(maxi(ci - r, 0), mini(ci + r, FN) + 1):
				var idx := j * vn + i
				for nb in [idx + 1, idx - 1, idx + vn, idx - vn]:
					var ni: int = nb
					var nx := ni % vn
					if ni < 0 or ni >= vn * vn or absi(nx - (idx % vn)) > 1:
						continue
					var diff := fh[idx] - fh[ni]
					if diff > max_step:
						# only loose ground above the rock line slides; rock walls stand
						var loose := fh[idx] - (orig[idx] - bedrock[idx])
						var mv := minf((diff - max_step) * 0.5, maxf(loose, 0.0))
						if mv <= 0.0001:
							continue
						fh[idx] -= mv
						fh[ni] += mv
						moved = true
		if not moved:
			break


## What layer the surface shows at a spot (for messages: "into the pay now").
func layer_at(x: float, z: float) -> String:
	var d := orig_depth_at(x, z)
	if d < 0.25:
		return "turf"
	var vn := FN + 1
	var i := mini(int((x + SQ) / FRES), FN)
	var j := mini(int((z + SQ) / FRES), FN)
	var idx := j * vn + i
	if d < pay_top[idx]:
		return "overburden"
	if d < bedrock[idx]:
		return "pay"
	return "bedrock"


# ------------------------------------------------------------------------------
#  Save / load (only what moved; the rest regenerates)
# ------------------------------------------------------------------------------
func save_to(cf: ConfigFile) -> void:
	if not modified:
		return
	var vn := FN + 1
	var idxs := PackedInt32Array()
	var vals := PackedFloat32Array()
	for k in range(vn * vn):
		if absf(fh[k] - orig[k]) > 0.005:
			idxs.append(k)
			vals.append(fh[k])
	cf.set_value("ground", "idxs", idxs)
	cf.set_value("ground", "vals", vals)


func load_from(cf: ConfigFile) -> void:
	var idxs: PackedInt32Array = cf.get_value("ground", "idxs", PackedInt32Array())
	var vals: PackedFloat32Array = cf.get_value("ground", "vals", PackedFloat32Array())
	for k in range(idxs.size()):
		fh[idxs[k]] = vals[k]
	if idxs.size() > 0:
		modified = true
		for cj in range(CHUNKS):
			for ci in range(CHUNKS):
				dirty_chunks[Vector2i(ci, cj)] = true
				vox_dirty[Vector2i(ci, cj)] = Rect2i(ci * CHUNK_CELLS, cj * CHUNK_CELLS, CHUNK_CELLS, CHUNK_CELLS)


# ------------------------------------------------------------------------------
#  Mud (DESIGN_NOTES 109): how soft and wet the ground is, for the wheels and
#  tracks (wheeled_body.gd, tracked_body.gd) and the ground shader.
# ------------------------------------------------------------------------------
const MUD_RES := 1.0
const MUD_N := 361                     # 1 m grid over the square
var mud_base := PackedFloat32Array()   # 0 firm .. 1 bottomless, as nature made it
var churn := PackedFloat32Array()      # how much it's been chewed up by driving


## Wet ground is soft: the muskeg, the creek's edges, round the pond, and the
## odd wet hollow in the open; never the gravel strip, apron or pad, or the
## rock of the knoll.
func _build_mud() -> void:
	mud_base.resize(MUD_N * MUD_N)
	churn.resize(MUD_N * MUD_N)
	churn.fill(0.0)
	var lay_ := lay()
	var pond: Array = lay_["pond"]
	for j in range(MUD_N):
		var z := -SQ + float(j) * MUD_RES
		for i in range(MUD_N):
			var x := -SQ + float(i) * MUD_RES
			var zc := zone4(x, z)
			var bogw := MapGen.bog_weight(lay_, x, z)
			var cd := creek_dist(x, z, 9.0)
			var dp := Vector2(x, z).distance_to(pond[0]) - float(pond[1])
			# Mud is where water sits (DESIGN_NOTES 109): the creek's banks and
			# bed, the pond's shore, and low dips that drain nowhere. The
			# muskeg is soft, not a bog to the axles everywhere.
			var m := 0.85 * smoothstep(7.0, 1.0, cd)                    # creek banks
			m = maxf(m, 0.85 * smoothstep(8.0, -1.0, dp))               # pond shore and shallows
			# low dips: lower than the ground 15 m around
			var vn := FN + 1
			var ci := clampi(int((x + SQ) / FRES), 0, FN)
			var cj := clampi(int((z + SQ) / FRES), 0, FN)
			var hh: float = orig[cj * vn + ci]
			var around := 0.0
			for o in [Vector2i(30, 0), Vector2i(-30, 0), Vector2i(0, 30), Vector2i(0, -30), Vector2i(21, 21), Vector2i(-21, 21), Vector2i(21, -21), Vector2i(-21, -21)]:
				around += orig[clampi(cj + o.y, 0, FN) * vn + clampi(ci + o.x, 0, FN)]
			var dip := around / 8.0 - hh
			m = maxf(m, 0.75 * smoothstep(0.25, 0.9, dip))
			m = maxf(m, 0.45 * smoothstep(0.3, 0.8, bogw) * (0.5 + 0.5 * smoothstep(0.0, 0.5, dip)))   # the muskeg: soft, worse in its low spots
			var bw := mudbog_weight(x, z)
			if bw > 0.0:
				mud_base[j * MUD_N + i] = clampf(maxf(m, 0.55 + 0.45 * bw), 0.0, 1.0)
				continue
			m *= 1.0 - clampf(zc.r * 1.3, 0.0, 1.0)                     # gravel strip, apron, pad
			m *= 1.0 - clampf(zc.a, 0.0, 1.0)                          # rock
			for cl in clearings:                                          # the apron and the mining pad: worked, drained ground
				var dcl := Vector2(x - cl.x, z - cl.y).length()
				m *= smoothstep(cl.z * 0.75, cl.z * 1.05, dcl)
			mud_base[j * MUD_N + i] = clampf(m, 0.0, 1.0)


## The natural softness, before season, rain and driving (for the shader).
func mud_base_at(x: float, z: float) -> float:
	var k := _mud_idx(x, z)
	return mud_base[k] if k >= 0 else 0.0


func _mud_idx(x: float, z: float) -> int:
	if absf(x) >= SQ or absf(z) >= SQ or mud_base.is_empty():
		return -1
	var i := clampi(int((x + SQ) / MUD_RES + 0.5), 0, MUD_N - 1)
	var j := clampi(int((z + SQ) / MUD_RES + 0.5), 0, MUD_N - 1)
	return j * MUD_N + i


## How muddy this spot is right now, 0 firm .. 1 deep enough to bury a truck
## to the axles. Frozen solid in winter, at its worst in spring break-up and
## after rain; churned ground and fresh cuts get worse the more you drive them.
func mud_at(x: float, z: float) -> float:
	if Flora.outback:
		return 0.0
	var k := _mud_idx(x, z)
	if k < 0:
		return 0.0
	if season == 2:       # winter: frozen hard
		return 0.0
	var wet_k: float = [0.8, 1.0, 0.0, 1.3][clampi(season, 0, 3)]
	var base := mud_base[k]
	var m := base * wet_k + churn[k]
	if Game.weather == 2:
		m += 0.15 + 0.3 * base                     # rain soaks it
	var dug := orig_depth_at(x, z)
	if dug > 0.08:
		m += 0.2 + 0.3 * base                      # torn-up ground with no mat on it
	return clampf(m, 0.0, 1.0)


## Ruts: a wheel or track that sinks in presses the ground down where it goes
## and churns it up so it's worse next time. Only soft ground ruts, and never
## deeper than 35 cm below how it was (the pay gravel is far deeper).
func rut(c: Vector3, radius: float, depth: float) -> void:
	if absf(c.x) >= SQ - 1.0 or absf(c.z) >= SQ - 1.0:
		return
	var vn := FN + 1
	var ci := int(round((c.x + SQ) / FRES))
	var cj := int(round((c.z + SQ) / FRES))
	var rc := int(ceil(radius / FRES))
	var changed := false
	for j in range(maxi(cj - rc, 0), mini(cj + rc, FN) + 1):
		for i in range(maxi(ci - rc, 0), mini(ci + rc, FN) + 1):
			var d := Vector2(-SQ + i * FRES - c.x, -SQ + j * FRES - c.z).length()
			if d > radius:
				continue
			var idx := j * vn + i
			var floor_h: float = orig[idx] - 0.35
			var want := depth * (1.0 - d / radius)
			var h := fh[idx]
			if h - want < floor_h:
				want = maxf(h - floor_h, 0.0)
			if want > 0.002:
				fh[idx] = h - want
				changed = true
	var mk := _mud_idx(c.x, c.z)
	if mk >= 0:
		churn[mk] = minf(churn[mk] + 0.04, 0.45)
	if changed:
		_mark_dirty(ci, cj, rc + 2)
		modified = true


# ------------------------------------------------------------------------------
#  The mud bog (DESIGN_NOTES 112): somewhere to bury a truck for fun
# ------------------------------------------------------------------------------
const MUDBOG_L := 20.0         # half length (m), along x
const MUDBOG_W := 12.0         # half width
const MUDBOG_RAMP := 7.0       # the ramps in and out at each end
const MUDBOG_DEPTH := 1.0


## Where the bog goes: flat open ground near the hangar, clear of the strip,
## the apron, the pad, the creek, the pond and the knoll.
static func mudbog() -> Vector2:
	var lay_ := lay()
	if lay_.has("mudbog"):
		return lay_["mudbog"]
	var pond: Array = lay_["pond"]
	var knl: Array = lay_["knoll"]
	var pad: Vector2 = lay_["pad"]
	var apron := Vector2(-25.0, -94.0)
	var best := Vector2(80.0, -60.0)
	var best_d := 1.0e9
	for z in range(-140, 141, 8):
		for x in range(-140, 141, 8):
			var p := Vector2(x, z)
			if absf(z + 130.0) < 40.0:
				continue                                     # the strip
			if p.distance_to(apron) < 95.0 or p.distance_to(pad) < 55.0:
				continue
			if p.distance_to(pond[0]) < float(pond[1]) + 40.0 or p.distance_to(knl[0]) < float(knl[1]) + 20.0:
				continue
			if creek_dist(p.x, p.y, 40.0) < 38.0:
				continue
			if MapGen.bog_weight(lay_, p.x, p.y) > 0.05:
				continue
			# flat enough: the ends within 1.5 m of each other
			var h0 := MapGen.base_height(lay_, p.x - MUDBOG_L, p.y)
			var h1 := MapGen.base_height(lay_, p.x + MUDBOG_L, p.y)
			if absf(h1 - h0) > 1.5:
				continue
			var d := p.distance_to(apron)
			if d < best_d:
				best_d = d
				best = p
	lay_["mudbog"] = best
	return best


## 1 in the bottom of the pit, easing to 0 up the ramps and the sides.
static func mudbog_weight(x: float, z: float) -> float:
	if absf(x) >= SQ or absf(z) >= SQ:
		return 0.0
	var c := mudbog()
	var dx := absf(x - c.x)
	var dz := absf(z - c.y)
	if dx > MUDBOG_L + MUDBOG_RAMP or dz > MUDBOG_W + 2.0:
		return 0.0
	var along := 1.0 - smoothstep(MUDBOG_L - 1.0, MUDBOG_L + MUDBOG_RAMP, dx)
	var across := 1.0 - smoothstep(MUDBOG_W - 3.0, MUDBOG_W + 2.0, dz)
	return along * across
