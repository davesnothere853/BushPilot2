extends Node3D
## The region (DESIGN_NOTES 227, Dave): a big mountain country, "just like"
## his two photos (reference/region/dave_alps_haze.png, dave_canyon_fog.png) -
## ridge after ridge of steep forested mountains in every direction, fading
## blue into the haze; narrow flat valley floors with fields, small towns,
## winding roads and rivers; a deep gorge with a river of fog in it; a fjord
## down to the sea with a harbor fishing town. A web of valleys joined by
## passes, so you can fly through the mountains any way, not down one valley.
## Same mountain heights as the town's valley, the map much bigger (~32 km).
##
## Terrain first (this file): mountains (ridged noise), the valleys carved in
## (U-shaped floors, the gorge with sheer walls), lakes, the sea, rivers; the
## haze and the valley fog. Towns, yards and fences, roads (dirt outside town,
## one main paved road), the railway with its trestles and bridges, Harry's
## strip and the bush strips come next.
## Local metres: x east, z south, y up; the home town at the origin.

const MeshKit = preload("res://scripts/meshkit.gd")

const SIZE := 10000.0         # metres a side (Dave 13 Oct: a smaller, dense world - was 32 km)
const STEP := 40.0            # the whole-map mesh
const NEAR := Rect2(-5000.0, -5000.0, 10000.0, 10000.0)    # finer ground round home
const NEAR_STEP := 12.0       # the whole playable map now
const PX := 10.0              # metres per pixel of the layout sketch (region2.png); was 30

var _ridge := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _fine := FastNoiseLite.new()
var _hash := FastNoiseLite.new()
var _jag := FastNoiseLite.new()        # serrated crests and gullies

## The valleys: [points (sketch px), floor heights at each point (m), floor
## half-width (m), kind]. Sketch px -> metres: (p - (470, 470)) * PX.
const VALLEYS := [
	# west main valley: home -> the mine town -> over the west pass
	[[Vector2(20, 420), Vector2(180, 400), Vector2(330, 430), Vector2(470, 470)], [208.0, 120.0, 80.0, 56.0], 114.0, "valley"],
	# north-east up to the glacier, past the pass strip
	[[Vector2(470, 470), Vector2(560, 400), Vector2(640, 300), Vector2(700, 170), Vector2(720, 70)], [56.0, 132.0, 192.0, 304.0, 420.0], 90.0, "valley"],
	# south-east: the big valley down to the fjord and the sea
	[[Vector2(470, 470), Vector2(560, 560), Vector2(700, 600), Vector2(860, 620), Vector2(960, 650), Vector2(1100, 700)], [56.0, 44.0, 28.0, 12.0, 1.6, -16.0], 156.0, "valley"],
	# south: the gorge (sheer walls, the river of fog), then the lake
	[[Vector2(470, 470), Vector2(450, 540), Vector2(420, 610), Vector2(395, 680)], [56.0, 46.0, 38.0, 32.0], 30.0, "gorge"],
	[[Vector2(395, 680), Vector2(380, 720), Vector2(340, 860)], [32.0, 31.2, 64.0], 90.0, "valley"],
	# north-west from the mine town to the glacier ski strip, through a gorge
	[[Vector2(180, 400), Vector2(160, 280)], [120.0, 208.0], 78.0, "valley"],
	[[Vector2(160, 280), Vector2(175, 220), Vector2(200, 160)], [208.0, 250.0, 328.0], 34.0, "gorge"],
	[[Vector2(200, 160), Vector2(260, 60)], [328.0, 460.0], 78.0, "valley"],
	# the east lakes valley up to the lake town and on
	[[Vector2(700, 600), Vector2(760, 480), Vector2(880, 380), Vector2(1000, 300), Vector2(1100, 250)], [28.0, 76.0, 112.0, 120.0, 168.0], 102.0, "valley"],
	# the high cross valley: a slot canyon over the high pass (fly it)
	[[Vector2(640, 300), Vector2(720, 280), Vector2(800, 270), Vector2(880, 380)], [192.0, 260.0, 300.0, 112.0], 28.0, "gorge"],
	# the south-west loop: a winding gorge stepping down to the lake (waterfalls)
	[[Vector2(330, 430), Vector2(310, 500), Vector2(300, 560), Vector2(340, 650), Vector2(380, 720)], [80.0, 150.0, 190.0, 110.0, 31.2], 32.0, "gorge"],
]
## Lakes: [centre (px), radius (m), level (m)].
const LAKES := [[Vector2(1000, 300), 300.0, 120.0], [Vector2(880, 380), 175.0, 112.0], [Vector2(380, 722), 200.0, 31.2]]
## The sea: south-east of this line (px), the coast.
const COAST := [Vector2(840, 860), Vector2(950, 700), Vector2(1040, 660), Vector2(1100, 600)]

var _segs: Array = []         # [a, b, ha, hb, w, kind, along0] in metres
var _lakes: Array = []
var _flats: Array = []        # [centre, radius, falloff, level]: levelled sites (summits for lookouts, the mast...)
## The home town's shelf (DESIGN_NOTES 234, Silverton): a flat fan north of
## the river at the junction, rising gently to the north; its north streets
## run on up the mountain's toe. [x0, z0, x1, z1] and the fan's height.
const BUILD_TOWN := true
static var probe_only := false
static var no_cards := false
## In the game (world.gd): the region round the home airport. Empty in the lab.
##   center  Vector2  where the airport square's middle sits (region metres)
##   angle   float    the square's turn in the region (radians; the runway runs along the square's x)
##   half    float    the square's half size (m)
##   near    Rect2    the fine ground and the forest (the playable piece)
##   level   float    (set here) the ground's height under the square
static var game := {}
var landmarks := {}
var geology: RefCounted
var town: Node3D          # region_geology.gd: ore_at(x, z)           # name -> world position (region_landmarks.gd)        # [centre m, r, level]


static func px(p: Vector2) -> Vector2:
	return (p - Vector2(470, 470)) * PX


func _ready() -> void:
	_ridge.seed = 1982
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 5
	_ridge.fractal_gain = 0.5
	_ridge.frequency = 1.0 / 1700.0
	_warp.seed = 7
	_warp.frequency = 1.0 / 3000.0
	_warp.fractal_octaves = 2
	_fine.seed = 33
	_fine.frequency = 1.0 / 240.0
	_fine.fractal_octaves = 3
	_jag.seed = 23
	_jag.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_jag.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_jag.fractal_octaves = 3
	_jag.frequency = 1.0 / 150.0
	_hash.seed = 5
	_hash.noise_type = FastNoiseLite.TYPE_CELLULAR
	_hash.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	_hash.frequency = 1.0 / 50.0
	for v in VALLEYS:
		var pts: Array = v[0]
		var hs: Array = v[1]
		for i in range(pts.size() - 1):
			var a := px(pts[i])
			var b := px(pts[i + 1])
			var bb := Rect2(a, Vector2.ZERO).expand(b).grow(float(v[2]) + 1200.0)
			_segs.append([a, b, float(hs[i]), float(hs[i + 1]), float(v[2]), String(v[3]), bb])
	for l in LAKES:
		_lakes.append([px(l[0]), float(l[1]), float(l[2])])
	if not game.is_empty() and not game.has("cliff") and not game.get("bench", false):
		_plan_cliff_strip()
	if probe_only:
		return                                  # tools: just the natural ground, nothing built
	# the rocks under it all: gold belts, placers, copper, coal (region_geology.gd)
	geology = load("res://scripts/region_geology.gd").new()
	geology.plan(self)
	# the home town lays out its streets on the hillside and cuts them in
	town = load("res://scripts/region_town.gd").new()
	town.name = "HomeTown"
	if BUILD_TOWN:
		town.plan(self)
	_road_index()
	# the landmarks pick their spots first, levelling their sites into the ground
	var lm = load("res://scripts/region_landmarks.gd").new()
	lm.name = "Landmarks"
	lm.plan(self)
	_build_ground()
	_road_ground()
	ground_t = load("res://scripts/region_terrain.gd").new()
	ground_t.setup(self)                     # the drawn ground, for the rivers and trees
	if not game.is_empty():
		var gc: Vector2 = game["center"]
		ground_t.clear_spot(gc.x, gc.y, float(game["half"]) * 1.45 + 30.0)   # no forest on the airport square
	# the home town's buildings, and no forest in it
	add_child(town)
	if BUILD_TOWN:
		town.build(self)
		for c in town.clearings:
			ground_t.clear_spot(c.x, c.y, c.z)
	_build_water()
	_atmosphere()
	_forest()
	add_child(lm)
	lm.build()
	landmarks = lm.spots
	set_meta("frame_aabb", AABB(Vector3(-6000, 0, -6000), Vector3(12000, 1500, 12000)))


# ------------------------------------------------------------------------------
#  Height
# ------------------------------------------------------------------------------
## The mountains before the valleys: ridged, sharp-topped, steep forested sides.
func _mountain(x: float, z: float) -> float:
	var wx := x + _warp.get_noise_2d(x, z) * 600.0
	var wz := z + _warp.get_noise_2d(x + 1700.0, z - 1000.0) * 600.0
	var r := _ridge.get_noise_2d(wx, wz) * 0.5 + 0.5          # 0..1, ridges high
	var h := 120.0 + 700.0 * pow(r, 1.4)               # peaks ~500-800 m over the towns (was 380 + 1250)
	h += _fine.get_noise_2d(x, z) * 25.0
	return h


## Jagged, not soft (Dave: "more jagged and not so soft", the scale kept):
## gullies and couloirs ~400 m apart down every face, rock steps and ribs
## ~150 m, more of it the higher you go. Centred on zero so the heights stay;
## nothing on the valley floors (the caller fades it out there).
func _jagged(x: float, z: float, h: float) -> float:
	var hi := smoothstep(120.0, 600.0, h)
	var g1 := 1.0 - (_jag.get_noise_2d(x, z) * 0.5 + 0.5)
	var g2 := 1.0 - (_jag.get_noise_2d(x * 2.7 + 900.0, z * 2.7) * 0.5 + 0.5)
	return -((g1 - 0.45) * (16.0 + 55.0 * hi) + (g2 - 0.45) * (6.0 + 20.0 * hi))


## The valley floor carve: (height of the carved shape, how deep in the floor
## 0..1, gorge), the lowest of all valleys at this point.
## The warp the valleys are measured through (see _carve).
func _vwarp(x: float, z: float) -> Vector2:
	return Vector2(_warp.get_noise_2d(x * 4.0, z * 4.0) * 140.0, _warp.get_noise_2d(x * 4.0 + 300.0, z * 4.0 - 130.0) * 140.0)


## Where on the ground a point of a valley's centre line actually lies (the
## valley meanders): q with q + warp(q) = c.
func _unwarp(c: Vector2) -> Vector2:
	var q := c
	for i in range(4):
		q = c - _vwarp(q.x, q.y)
	return q


func _carve(x: float, z: float) -> Vector4:
	# the valleys wander: measure from a warped point so the floors meander
	var p := Vector2(x, z) + _vwarp(x, z)
	var wv := 0.7 + 0.6 * (_fine.get_noise_2d(x * 0.25, z * 0.25) * 0.5 + 0.5)       # floors widen and pinch
	var best := 1e9
	var floor_in := 0.0
	var gorge := 0.0
	var chan := 0.0
	for s in _segs:
		var bb: Rect2 = s[6]
		if not bb.has_point(p):
			continue
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		var w: float = float(s[4]) * wv
		if d > w + 1200.0:
			continue
		var f: float = lerpf(float(s[2]), float(s[3]), t)
		var wall: float
		if String(s[5]) == "gorge":
			# sheer rock walls straight up from a narrow floor, then the slope
			var e2 := maxf(d - w, 0.0)
			wall = f + e2 * 6.0 + sin(e2 * 0.22) * 6.0 + _jag.get_noise_2d(x * 3.0, z * 3.0) * 8.0 * minf(e2 / 10.0, 1.0)   # ledges, buttresses
		else:
			# a U-shaped glacial valley: flat floor, walls steepening up the sides
			var e := maxf(d - w, 0.0)
			wall = f + e * 0.55 + e * e * 0.0009
		# a gentle cross-slope on the floor and a channel down the middle
		wall += minf(d, w) / w * 3.0
		wall -= 2.5 * (1.0 - smoothstep(0.0, 14.0, d))
		if wall < best:
			best = wall
			floor_in = 1.0 - smoothstep(w * 0.8, w + 20.0, d)
			gorge = 1.0 if String(s[5]) == "gorge" else 0.0
			chan = 1.0 - smoothstep(10.0, 30.0, d)          # the river's gravel bars
	return Vector4(best, floor_in, gorge, chan)


## The hillside town's cuts (DESIGN_NOTES 234): each street a bench cut into
## the slope (flat across, its own grade along), banks back to the natural
## ground at about 1:1 (cut) or 1:1.5 (fill); each building on its own pad.
## benches: [pts PackedVector3Array (x, road y, z), half width, Rect2 bb];
## pads: [centre, half size Vector2, yaw, level].
var _benches: Array = []
var _pads: Array = []
var _town_box := Rect2()
var _road_box := Rect2()


func add_bench(pts: PackedVector3Array, hw: float, gentle: bool = false) -> void:
	var bb := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
	for p in pts:
		bb = bb.expand(Vector2(p.x, p.z))
	bb = bb.grow(hw + (250.0 if gentle else 45.0))
	_benches.append([pts, hw, bb, gentle])
	if gentle:
		# the mountain road: its own box (the town's fine 4 m ground isn't
		# laid all the way up the mountain)
		_road_box = bb if _road_box.size == Vector2.ZERO else _road_box.merge(bb)
		return
	_town_box = bb if _town_box.size == Vector2.ZERO else _town_box.merge(bb)


func add_pad(c: Vector2, half: Vector2, yaw: float, level: float, in_town: bool = true) -> void:
	_pads.append([c, half, yaw, level])
	var bb := Rect2(c - Vector2.ONE * (half.length() + 20.0), Vector2.ONE * (half.length() + 20.0) * 2.0)
	if not in_town:
		_road_box = bb if _road_box.size == Vector2.ZERO else _road_box.merge(bb)
		return
	_town_box = bb if _town_box.size == Vector2.ZERO else _town_box.merge(bb)


## The natural ground h at x, z with the town's cuts and fills applied.
func _town_ground(x: float, z: float, h: float) -> float:
	var p := Vector2(x, z)
	for bn in _benches:
		if not (bn[2] as Rect2).has_point(p):
			continue
		var pts: PackedVector3Array = bn[0]
		var hw: float = bn[1]
		var best := 1e9
		var by := 0.0
		for i in range(pts.size() - 1):
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < best:
				best = d
				by = lerpf(pts[i].y, pts[i + 1].y, t)
		var dh := absf(h - by)
		var bank := dh * (1.0 if h > by else 1.5) + 0.5        # how far out the cut or fill reaches
		if bn.size() > 3 and bn[3] and h > by:
			# a mountain road's deep cuts lie back (a draw, not a trench)
			bank = minf(dh * (1.0 + 2.2 * smoothstep(3.0, 18.0, dh)) + 0.5, 240.0)
		if best < hw + bank:
			h = lerpf(by, h, smoothstep(hw, hw + bank, best))
	for pd in _pads:
		var rel: Vector2 = (p - (pd[0] as Vector2)).rotated(-float(pd[2]))
		var half: Vector2 = pd[1]
		var out := maxf(absf(rel.x) - half.x, absf(rel.y) - half.y)
		var lv: float = pd[3]
		var reach := absf(h - lv) * (1.0 if h > lv else 1.5) + 0.3
		if out < reach:
			h = lerpf(lv, h, smoothstep(0.0, reach, out))
	return h


## A levelled site: flat at `level` out to r, blending back to the ground by r + fall.
func add_flat(c: Vector2, r: float, fall: float, level: float) -> void:
	_flats.append([c, r, fall, level])


func height(x: float, z: float) -> float:
	var h := _post(x, z, _height_c(x, z, _carve(x, z)))
	# the bridge decks: what a wheel rolls on (the drawn ground under them
	# stays the river's; the bridge itself is drawn by its asset)
	for d in _decks:
		var a: Vector2 = d[0]
		var ab: Vector2 = (d[1] as Vector2) - a
		var p := Vector2(x, z)
		var t := (p - a).dot(ab) / maxf(ab.length_squared(), 0.0001)
		if t < -0.02 or t > 1.02:
			continue
		if p.distance_to(a + ab * clampf(t, 0.0, 1.0)) < float(d[2]):
			h = maxf(h, float(d[3]))
	return h


var _decks: Array = []         # [a Vector2, b Vector2, half width, deck y]

func add_deck(a: Vector2, b: Vector2, hw: float, y: float) -> void:
	_decks.append([a, b, hw, y])


## The game's own shaping on top of the land: the cliff strip, the airport's
## square and its bench (the ground the game drives on AND the drawn ground).
func _post(x: float, z: float, h: float) -> float:
	if not game.is_empty():
		h = _cliff_strip(x, z, h)
		h = _square_blend(x, z, h)
	return h


# ------------------------------------------------------------------------------
#  The cliff strip (Dave: "the airport on top of a mountain right off a steep
#  cliff at the end of the runway - if you don't gain enough speed you drop
#  off the cliff"). A shelf levelled on a mountain looking over the home
#  valley: 300 m of gravel, the far end runs straight out to a sheer drop of a
#  couple of hundred metres. You take off toward the valley (off the edge) and
#  land the other way, uphill, toward the mountain.
# ------------------------------------------------------------------------------
const CLIFF_LEN := 300.0
const CLIFF_HW := 15.0


## Pick the spot: up the valley side 500-1300 m from the home airport,
## 180-380 m above it, the runway pointing at the valley so the drop is over
## it; the one needing the least cut and fill.
func _plan_cliff_strip() -> void:
	var c: Vector2 = game["center"]
	var lv := _height_c(c.x, c.y, _carve(c.x, c.y))
	var best := {}
	var best_score := 1e12
	var step := 60.0
	var r := -1300.0
	while r <= 1300.0:
		var q := -1300.0
		while q <= 1300.0:
			var p := c + Vector2(r, q)
			var dist := p.distance_to(c)
			if dist >= 500.0 and dist <= 1300.0:
				var hp := _height_c(p.x, p.y, _carve(p.x, p.y))
				if hp > lv + 180.0 and hp < lv + 380.0:
					var dir := (c - p).normalized()          # toward the valley: the drop end
					var start := p - dir * CLIFF_LEN
					var hs: Array = []
					for i in range(7):
						var a := start.lerp(p, float(i) / 6.0)
						for sd in [-1.0, 0.0, 1.0]:
							var w: Vector2 = a + Vector2(-dir.y, dir.x) * CLIFF_HW * float(sd)
							hs.append(_height_c(w.x, w.y, _carve(w.x, w.y)))
					var mean := 0.0
					for v in hs:
						mean += float(v)
					mean /= float(hs.size())
					var cut := 0.0
					for v in hs:
						cut += absf(float(v) - mean)
					# beyond the end it must fall away (that's the cliff)
					var beyond := p + dir * 120.0
					var drop := mean - _height_c(beyond.x, beyond.y, _carve(beyond.x, beyond.y))
					var score := cut - drop * 0.5
					if drop > 40.0 and score < best_score:
						best_score = score
						best = {"a": start, "b": p, "level": mean + 1.0}
			q += step
		r += step
	if best.is_empty():
		print("region: no spot for the cliff strip")
		return
	game["cliff"] = best
	print("region: cliff strip at %s, %.0f m up (home %.0f)" % [str((best["b"] as Vector2).round()), float(best["level"]), lv])


func _cliff_strip(x: float, z: float, h: float) -> float:
	if not game.has("cliff"):
		return h
	var cs: Dictionary = game["cliff"]
	var a: Vector2 = cs["a"]
	var b: Vector2 = cs["b"]
	var lvl: float = cs["level"]
	var ab := b - a
	var L := ab.length()
	var dir := ab / L
	var d := Vector2(x, z) - a
	var along := d.dot(dir)
	var across := absf(d.x * -dir.y + d.y * dir.x)
	if along < -160.0 or along > L + 420.0 or across > CLIFF_HW + 160.0:
		return h
	if along <= L:
		# the shelf: flat on the strip, banked back to the mountain (cut or fill ~1:1.2)
		var off := maxf(across - CLIFF_HW - 6.0, 0.0) + maxf(-along - 10.0, 0.0)
		var bank := lvl + (h - lvl) * smoothstep(0.0, 1.0, off / maxf(absf(h - lvl) * 1.2 + 4.0, 4.0))
		h = bank if off > 0.0 else lvl
		# a lip of rock and the end markers right at the edge
		return h
	# past the end: the cliff - a sheer face straight down, ragged at the top,
	# then the mountain's own slope far below
	var past := along - L
	var fall := lvl - 230.0 - past * 0.6
	var face := lerpf(lvl, fall, smoothstep(0.0, 7.0 + 4.0 * _jag.get_noise_2d(x * 4.0, z * 4.0), past))
	var side := smoothstep(CLIFF_HW + 150.0, CLIFF_HW + 40.0, across)       # the face wraps round the end
	return minf(h, lerpf(h, face, side))


## Round the mountain airport the rock spires and gullies are eased off
## (Dave: "remove the rocks, make it approachable and usable"): 0 far away,
## up to 0.85 near the bench.
func _calm(x: float, z: float) -> float:
	if game.is_empty() or not game.get("bench", false):
		return 0.0
	var d := Vector2(x, z).distance_to(game["center"])
	return 0.6 * smoothstep(800.0, 350.0, d)


static var _gs: GDScript
static func _ground_script() -> GDScript:
	if _gs == null:
		_gs = load("res://scripts/ground.gd")
	return _gs


## The home airport's square sits in the valley: the ground eases to its level
## round it (and dips just under its edge, so the square's own ground shows).
func _square_blend(x: float, z: float, h: float) -> float:
	var c: Vector2 = game["center"]
	if not game.has("level"):
		game["level"] = _height_c(c.x, c.y, _carve(c.x, c.y))
	var lv: float = game["level"]
	var a: float = game["angle"]
	var d := Vector2(x, z) - c
	var lx := d.x * cos(a) + d.y * sin(a)
	var lz := -d.x * sin(a) + d.y * cos(a)
	var edge := maxf(absf(lx), absf(lz))
	var half: float = game["half"]
	if edge < half + 0.5:
		return lv - lerpf(8.0, 0.25, smoothstep(half - 2.0, half + 0.5, edge))
	# the square's own ground at its nearest edge point (the local frame IS the
	# game's frame): the land eases out from exactly that, no step at the edge
	var lve := lv
	if edge < half + 132.0:
		var G = _ground_script()
		var gx := clampf(lx, -half + 0.5, half - 0.5)
		var gz := clampf(lz, -half + 0.5, half - 0.5)
		lve = lv + float(G.natural_height(gx, gz)) - float(G.PLAIN_Y)
	# (a shoulder of two 12 m mesh cells at the square's own level before the
	# land falls away: the drawn ground always covers the dig block's sides)
	var out := h if edge > half + 130.0 else lerpf(lve, h, smoothstep(half + 26.0, half + 130.0, edge))
	if game.get("bench", false):
		out = _bench_mold(lx, lz, half, lv, out)
		out = _bench_cliff(lx, lz, half, lv, out)
	return out


## The bench made usable: the ground off the runway's west end held under a
## 12% climb (the approach and go-around over the mountain's shoulder), the
## sides held under 40% so the airport isn't walled in. Only ever lowers the
## ground, rounded (smooth minimum) so it reads as a saddle, not a cut.
func _bench_mold(lx: float, lz: float, half: float, lv: float, h: float) -> float:
	var cap := 1e9
	var a: float = game["angle"]
	var c: Vector2 = game["center"]
	var wx := c.x + lx * cos(a) - lz * sin(a)
	var wz := c.y + lx * sin(a) + lz * cos(a)
	# the caps aren't planes: lumpy like the ground they're cut from
	var lump := 22.0 * _fine.get_noise_2d(wx * 1.6, wz * 1.6) + 9.0 * _jag.get_noise_2d(wx * 2.0, wz * 2.0)
	# the approach corridor off the west end, widening out
	var along := -lx - half
	if along > -60.0 and along < 1700.0:
		var aw := maxf(along, 0.0)
		var cw := 120.0 + 0.18 * aw
		var lat := maxf(absf(lz) - cw, 0.0)
		# (the flanks of the saddle gentle, ~20 deg: the road climbs them)
		var c1 := lv + 4.0 + 0.12 * aw + lat * 0.36 + lump * smoothstep(0.0, 200.0, aw) + 600.0 * smoothstep(1200.0, 1700.0, along) + 600.0 * smoothstep(-20.0, -60.0, along)
		cap = minf(cap, c1)
	# the climb-out over the cliff: room either side of the centre line
	var out_d := lx - half
	if out_d > 80.0 and out_d < 1500.0:
		var ow := 90.0 + 0.15 * out_d
		var olat := maxf(absf(lz) - ow, 0.0)
		var c3 := lv - 10.0 + 0.09 * out_d + olat * 0.9 + lump + 600.0 * smoothstep(1000.0, 1500.0, out_d) + 600.0 * smoothstep(130.0, 80.0, out_d)
		cap = minf(cap, c3)
	# the sides: not walled in
	var sd := absf(lz) - half
	if sd > -10.0 and lx > -half - 250.0 and lx < half + 60.0:
		# (faded in from the edge of the square and out at both ends: no steps)
		var c2 := lv + 3.0 + 0.6 * maxf(sd, 0.0) + lump * smoothstep(0.0, 120.0, sd) + 400.0 * smoothstep(-half - 150.0, -half - 250.0, lx) + 400.0 * smoothstep(half + 10.0, half + 60.0, lx)
		cap = minf(cap, c2)
	if cap > 1e8:
		return h
	var k := 18.0
	var hh := clampf(0.5 + 0.5 * (cap - h) / k, 0.0, 1.0)
	return lerpf(cap, h, hh) - k * hh * (1.0 - hh)


## The home airport on its bench, 3/4 up the mountain (Dave: "the airport 3/4
## up a mountain, cliff at the end of the runway, great views ... like it was
## meant to be there"). Past the square's east edge (the runway's east end,
## local +x) the bench breaks off in a sheer, ragged rock face a couple of
## hundred metres down to the mountain's own slope; the face curls back round
## the corners and dies into the hillside along the sides.
func _bench_cliff(lx: float, lz: float, half: float, lv: float, h: float) -> float:
	var past := lx - half
	if past < -2.0 or past > 520.0:
		return h
	var a: float = game["angle"]
	# region axes for the noise (so it doesn't repeat with the square)
	var wx := lx * cos(a) - lz * sin(a)
	var wz := lx * sin(a) + lz * cos(a)
	# Not a wall the width of the square (Dave: "not just a big square off the
	# cliff"): a prow of rock the runway runs out onto. The sheer face is
	# centred on the runway's line (local z -130), ~150 m either side, the lip
	# curving back off the line; beyond, the mountain's own slope; two rock
	# shoulders frame the end of the runway.
	var d_r := absf(lz + 130.0)
	var lip := 30.0 + 22.0 * _fine.get_noise_1d(lz * 0.35 + 40.0) + 10.0 * _jag.get_noise_2d(lz * 1.3, 7.0)
	lip = maxf(lip, 27.0) + d_r * d_r / 420.0
	var side := smoothstep(170.0, 80.0, d_r)
	var s := past - lip
	# the shoulders: rock knuckles either side of the runway's end, 8-20 m
	var sh_n := 0.5 + 0.5 * _jag.get_noise_2d(wx * 1.7, wz * 1.7)
	var shoulder := (8.0 + 12.0 * sh_n) * smoothstep(55.0, 85.0, d_r) * smoothstep(175.0, 125.0, d_r) * smoothstep(0.0, 14.0, past) * (1.0 - smoothstep(-6.0, 4.0, s))
	if s < 0.0:
		# the ledge between the square and the lip: level with the airport on
		# the runway's line, the shoulders standing up either side
		var side0 := side * smoothstep(0.0, 6.0, past)
		var g := minf(h, lerpf(h, lv - 0.5, side0 * (1.0 - smoothstep(40.0, 70.0, d_r))))
		return maxf(g, lv - 0.5 + shoulder) if shoulder > 0.5 else g
	# depth below the lip: a sheer top band (6-18 m wide in plan) dropping
	# ~150-260 m, a ledge part way, buttresses and gullies running down the
	# face (noise across the edge and with depth), then a talus slope
	var drop := 135.0 + 40.0 * _fine.get_noise_2d(lz * 0.6, 3.0)
	var gully := 9.0 * _jag.get_noise_2d(lz * 2.2, s * 0.6)
	var w := 7.0 + 11.0 * absf(_fine.get_noise_2d(lz * 0.9, 11.0))
	var t := clampf((s + gully) / w, 0.0, 1.0)
	var steps := 0.18 * smoothstep(0.30, 0.42, t) - 0.18 * smoothstep(0.42, 0.60, t)     # a ledge
	var depth := drop * clampf(t + steps, 0.0, 1.0)
	depth += maxf(s - w, 0.0) * 0.55                                                  # the talus below
	depth += 6.0 * _jag.get_noise_2d(wx * 2.5, wz * 2.5)                              # rough rock
	var face := lv - 0.5 - maxf(depth, 0.0)
	# never carved more than ~170 m into the mountain's own slope, tapering
	# out below: the talus meets the natural slope (no pit at the foot)
	face = maxf(face, h - 120.0 * smoothstep(380.0, 120.0, s))
	side *= smoothstep(520.0, 300.0, past)
	return minf(h, lerpf(h, face, side))


## Inside the airport square (region metres)?
func in_square(x: float, z: float, margin: float = 0.0) -> bool:
	if game.is_empty():
		return false
	var c: Vector2 = game["center"]
	var a: float = game["angle"]
	var d := Vector2(x, z) - c
	var half: float = float(game["half"]) + margin
	return absf(d.x * cos(a) + d.y * sin(a)) < half and absf(-d.x * sin(a) + d.y * cos(a)) < half


func _height_c(x: float, z: float, c: Vector4) -> float:
	var m := _mountain(x, z)
	# smooth minimum: the valley shape eats into the mountain
	var k := 40.0
	var hh := clampf(0.5 + 0.5 * (c.x - m) / k, 0.0, 1.0)
	var h := lerpf(c.x, m, hh) - k * hh * (1.0 - hh)
	h += _jagged(x, z, h) * (1.0 - c.y) * (1.0 - _calm(x, z))
	# the hillside town: streets benched into the slope, house pads levelled
	if _town_box.has_point(Vector2(x, z)) or _road_box.has_point(Vector2(x, z)):
		h = _town_ground(x, z, h)
	for f in _flats:
		var fd := Vector2(x, z).distance_to(f[0])
		if fd < float(f[1]) + float(f[2]):
			h = lerpf(float(f[3]), h, smoothstep(float(f[1]), float(f[1]) + float(f[2]), fd))
	# lakes: a bowl below the water
	for l in _lakes:
		var d := Vector2(x, z).distance_to(l[0])
		var r: float = l[1]
		if d < r * 1.3:
			var bowl: float = float(l[2]) - 18.0 * (1.0 - pow(minf(d / r, 1.0), 2.0)) + maxf(d - r, 0.0) * 0.08
			h = minf(h, bowl)
	# the sea
	var cd := _coast_side(x, z)
	if cd > 0.0:
		h = minf(h, lerpf(h, -60.0, smoothstep(0.0, 1500.0, cd)))
	return h


## Metres on the sea side of the coast (negative inland).
func _coast_side(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1e9
	var side := -1.0
	for i in range(COAST.size() - 1):
		var a := px(COAST[i])
		var b := px(COAST[i + 1])
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(q)
		if d < best:
			best = d
			var ab := b - a
			side = signf(ab.x * (p.y - a.y) - ab.y * (p.x - a.x))
	return best * side


# ------------------------------------------------------------------------------
#  Ground mesh: the whole map, and finer round home
# ------------------------------------------------------------------------------
func _build_ground() -> void:
	# beyond the map: the mountains carry on to the horizon, coarse
	_grid("Beyond", -SIZE * 1.5, -SIZE * 1.5, 121, 121, SIZE * 3.0 / 120.0, Rect2(-SIZE * 0.5 + 800.0, -SIZE * 0.5 + 800.0, SIZE - 1600.0, SIZE - 1600.0), 60.0)
	var near := NEAR if game.is_empty() else (game["near"] as Rect2)
	_grid("Ground", -SIZE * 0.5, -SIZE * 0.5, int(SIZE / STEP) + 1, int(SIZE / STEP) + 1, STEP, near.grow(-STEP * 2.0), 12.0)
	var tb := Rect2()
	if _town_box.size != Vector2.ZERO:
		tb = Rect2((_town_box.position / 4.0).floor() * 4.0, (_town_box.size / 4.0).ceil() * 4.0)
	_grid("GroundNear", near.position.x, near.position.y, int(near.size.x / NEAR_STEP) + 1, int(near.size.y / NEAR_STEP) + 1, NEAR_STEP, tb.grow(-NEAR_STEP * 1.5), 6.0)
	if tb.size != Vector2.ZERO:
		# the town: 4 m, so the street cuts, banks and house pads show
		_grid("GroundTown", tb.position.x, tb.position.y, int(tb.size.x / 4.0) + 1, int(tb.size.y / 4.0) + 1, 4.0, Rect2(), 0.0)


# ------------------------------------------------------------------------------
#  The mountain road's own ground: the 12 m ground can't hold an 8 m road bench
#  on a hillside (it would float or sink), so a fine strip of ground follows
#  the road (3-4 m), the coarse ground tucked a little under it.
# ------------------------------------------------------------------------------
var _rh := {}            # Vector2i(40 m cell) -> Array of [a, b] road segments (Vector2)

func _road_index() -> void:
	_rh.clear()
	if town == null or town.mountain_road.size() < 2:
		return
	var line: PackedVector3Array = town.mountain_road
	for i in range(line.size() - 1):
		var a := Vector2(line[i].x, line[i].z)
		var b := Vector2(line[i + 1].x, line[i + 1].z)
		var bb := Rect2(a, Vector2.ZERO).expand(b).grow(30.0)
		for cx in range(int(floor(bb.position.x / 40.0)), int(floor(bb.end.x / 40.0)) + 1):
			for cz in range(int(floor(bb.position.y / 40.0)), int(floor(bb.end.y / 40.0)) + 1):
				var key := Vector2i(cx, cz)
				if not _rh.has(key):
					_rh[key] = []
				_rh[key].append([a, b])


func _near_road(x: float, z: float, r: float) -> bool:
	if _rh.is_empty():
		return false
	var key := Vector2i(int(floor(x / 40.0)), int(floor(z / 40.0)))
	if not _rh.has(key):
		return false
	var p := Vector2(x, z)
	for sg in _rh[key]:
		var a: Vector2 = sg[0]
		var ab: Vector2 = (sg[1] as Vector2) - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(a + ab * t) < r:
			return true
	return false


func _road_ground() -> void:
	if town == null or town.mountain_road.size() < 2:
		return
	var src: PackedVector3Array = town.mountain_road
	# resampled every ~4 m along, mitred normals
	var pts: Array = []
	for i in range(src.size() - 1):
		var a := Vector2(src[i].x, src[i].z)
		var b := Vector2(src[i + 1].x, src[i + 1].z)
		var n := maxi(int(ceil(a.distance_to(b) / 4.0)), 1)
		for k in range(n):
			pts.append(a.lerp(b, float(k) / n))
	pts.append(Vector2(src[src.size() - 1].x, src[src.size() - 1].z))
	var offs := [-24.0, -17.0, -12.0, -8.0, -5.5, -3.5, 0.0, 3.5, 5.5, 8.0, 12.0, 17.0, 24.0]
	var nw := offs.size()
	var np := pts.size()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(np * nw)
	cols.resize(np * nw)
	uvs.resize(np * nw)
	for i in range(np):
		var p: Vector2 = pts[i]
		var d: Vector2 = ((pts[mini(i + 1, np - 1)] as Vector2) - (pts[maxi(i - 1, 0)] as Vector2)).normalized()
		var nrm := Vector2(-d.y, d.x)
		for j in range(nw):
			var q: Vector2 = p + nrm * float(offs[j])
			var cv := _carve(q.x, q.y)
			var y := _post(q.x, q.y, _height_c(q.x, q.y, cv))
			# the outer edge tucks under the coarse ground
			if j == 0 or j == nw - 1:
				y -= 0.6
			verts[i * nw + j] = Vector3(q.x, y, q.y)
			var slope := 0.0
			cols[i * nw + j] = _col(q.x, y, q.y, slope, Vector2(cv.y, cv.z))
			var meadow := smoothstep(0.5, 0.85, cv.y) * (1.0 if y > 2.0 else 0.0)
			uvs[i * nw + j] = Vector2(meadow, cv.w if y > 1.0 else 1.0)
	var norms := PackedVector3Array()
	norms.resize(np * nw)
	for i in range(np):
		for j in range(nw):
			var a2 := verts[i * nw + maxi(j - 1, 0)]
			var b2 := verts[i * nw + mini(j + 1, nw - 1)]
			var c2 := verts[maxi(i - 1, 0) * nw + j]
			var d2 := verts[mini(i + 1, np - 1) * nw + j]
			var nn := (b2 - a2).cross(d2 - c2).normalized()
			if nn.y < 0.0:
				nn = -nn
			norms[i * nw + j] = nn
			# the colour by the real slope (rock on the cut banks)
			var sl := sqrt(maxf(1.0 - nn.y * nn.y, 0.0)) / maxf(nn.y, 0.05)
			var q3 := verts[i * nw + j]
			var cv2 := _carve(q3.x, q3.z)
			cols[i * nw + j] = _col(q3.x, q3.y, q3.z, sl, Vector2(cv2.y, cv2.z))
	var idx := PackedInt32Array()
	for i in range(np - 1):
		for j in range(nw - 1):
			var a3 := i * nw + j
			idx.append_array([a3, a3 + nw, a3 + 1, a3 + 1, a3 + nw, a3 + nw + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "RoadGround"
	mi.mesh = am
	mi.material_override = ground_material()
	add_child(mi)


var grids := {}               # name -> [x0, z0, nx, nz, step, heights, fields]: the drawn ground, for the trees (region_terrain.gd)


func _grid(nm: String, x0: float, z0: float, nx: int, nz: int, step: float, sink: Rect2, sink_by: float) -> void:
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	var fl := PackedVector3Array()
	fl.resize(nx * nz)
	for j in range(nz):
		for i in range(nx):
			var cx := x0 + i * step
			var cz := z0 + j * step
			var cv := _carve(cx, cz)
			hs[j * nx + i] = _post(cx, cz, _height_c(cx, cz, cv))
			fl[j * nx + i] = Vector3(cv.y, cv.z, cv.w)
	grids[nm] = [x0, z0, nx, nz, step, hs, fl]
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	uvs.resize(nx * nz)
	verts.resize(nx * nz)
	cols.resize(nx * nz)
	norms.resize(nx * nz)
	for j in range(nz):
		for i in range(nx):
			var x := x0 + i * step
			var z := z0 + j * step
			var y := hs[j * nx + i]
			var yl := hs[j * nx + maxi(i - 1, 0)]
			var yr := hs[j * nx + mini(i + 1, nx - 1)]
			var yd := hs[maxi(j - 1, 0) * nx + i]
			var yu := hs[mini(j + 1, nz - 1) * nx + i]
			var nrm := Vector3(yl - yr, 2.0 * step, yd - yu).normalized()
			var slope := Vector2(yr - yl, yu - yd).length() / (2.0 * step)
			var fv: Vector3 = fl[j * nx + i]
			var c := _col(x, y, z, slope, Vector2(fv.x, fv.y))
			# masks for the ground shader: meadow/fields, gravel bars
			var meadow := smoothstep(0.5, 0.85, fv.x) * (1.0 if y > 2.0 else 0.0)
			meadow = maxf(meadow, smoothstep(1380.0, 1520.0, y))
			uvs[j * nx + i] = Vector2(meadow, fv.z * (1.0 - fv.y * 0.0) if y > 1.0 else 1.0)
			if sink.has_point(Vector2(x, z)):
				y -= sink_by
			elif step <= 12.0 and _near_road(x, z, 16.0):
				y -= 2.5                    # under the road's own fine ground (_road_ground)
			verts[j * nx + i] = Vector3(x, y, z)
			cols[j * nx + i] = c
			norms[j * nx + i] = nrm
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var k := 0
	for j in range(nz - 1):
		for i in range(nx - 1):
			var a := j * nx + i
			idx[k] = a
			idx[k + 1] = a + 1
			idx[k + 2] = a + nx
			idx[k + 3] = a + 1
			idx[k + 4] = a + nx + 1
			idx[k + 5] = a + nx
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = am
	mi.material_override = ground_material()
	add_child(mi)


static var _gmat: ShaderMaterial


## The ground: photo scans at true size (shaders/region_ground.gdshader).
static func ground_material() -> ShaderMaterial:
	if _gmat != null:
		return _gmat
	var Tex = load("res://scripts/tex.gd")
	_gmat = ShaderMaterial.new()
	_gmat.shader = load("res://shaders/region_ground.gdshader")
	for pair in [["grass", "sparse_grass"], ["forest", "forest_ground_04"], ["rock", "rock_face"], ["snow", "snow_02"], ["gravel", "river_small_rocks"]]:
		var id: String = pair[1]
		_gmat.set_shader_parameter(pair[0] + "_c", Tex._load("res://textures/ph/%s/%s_diff_2k.jpg" % [id, id]))
		_gmat.set_shader_parameter(pair[0] + "_n", Tex._load("res://textures/ph/%s/%s_nor_gl_2k.jpg" % [id, id], true))
	_gmat.set_shader_parameter("use_detail", Tex.has("sparse_grass") and Tex.has("rock_face"))
	return _gmat


## Ground colour: fields and meadows on the valley floors, dark conifer forest
## on the slopes, grey rock where it's steep, alpine meadow and rock up high,
## snow on the tops; gravel along the river channels.
func _col(x: float, y: float, z: float, slope: float, cv: Vector2) -> Color:
	var n := _fine.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5
	var c := Color(0.06, 0.13, 0.10).lerp(Color(0.10, 0.18, 0.13), n)          # dark conifer forest
	if cv.x > 0.5 and y > 2.0 and cv.y < 0.5:
		# fields: a patchwork of greens and a few hay-yellows, hedges between
		var cell := _hash.get_noise_2d(x, z) * 0.5 + 0.5
		var field: Color = [Color(0.38, 0.52, 0.24), Color(0.44, 0.58, 0.27), Color(0.33, 0.47, 0.22), Color(0.56, 0.58, 0.30), Color(0.30, 0.42, 0.20), Color(0.14, 0.26, 0.15)][int(cell * 5.99)]
		var woods := smoothstep(0.62, 0.7, _fine.get_noise_2d(x * 2.0, z * 2.0) * 0.5 + 0.5)       # woodlots on the floor
		c = c.lerp(field.lerp(Color(0.12, 0.22, 0.14), woods), smoothstep(0.5, 0.85, cv.x))
	if y > 1380.0:                                                                # alpine meadow above the trees
		c = c.lerp(Color(0.30, 0.36, 0.22).lerp(Color(0.40, 0.42, 0.28), n), smoothstep(1380.0, 1520.0, y + n * 90.0))
	var tl := smoothstep(520.0, 640.0, y)                                       # the treeline (~580 m)
	var rs := slope + 0.45 * tl - 0.25 * (1.0 - tl)
	if rs > 0.85 + n * 0.3:                                                     # rock: cliffs low down, most of it above the trees
		c = c.lerp(Color(0.26, 0.28, 0.29).lerp(Color(0.36, 0.37, 0.38), n), smoothstep(0.85, 1.2, rs))
	if geology != null:
		c = geology.tint(x, y, z, slope, c)                                     # gossan, malachite, coal seams
	if y > 640.0:                                                                 # snow
		c = c.lerp(Color(0.92, 0.93, 0.96), smoothstep(640.0, 700.0, y + n * 30.0) * (1.0 - smoothstep(1.0, 1.6, slope)))
	if y < 3.0 and y > -1.0:
		c = Color(0.62, 0.60, 0.54)                                               # beach and river gravel
	return c


# ------------------------------------------------------------------------------
#  Water: the sea, the lakes, the rivers down the valleys
# ------------------------------------------------------------------------------
func _build_water() -> void:
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.13, 0.22, 0.26)
	wm.roughness = 0.08
	wm.metallic = 0.2
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE * 1.5, SIZE * 1.5)
	sea.mesh = pm
	sea.material_override = wm
	add_child(sea)
	for l in _lakes:
		var lk := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(l[1]) * 1.25
		cm.bottom_radius = float(l[1]) * 1.25
		cm.height = 0.2
		cm.radial_segments = 40
		lk.mesh = cm
		lk.position = Vector3((l[0] as Vector2).x, float(l[2]), (l[0] as Vector2).y)
		var lm := wm.duplicate() as StandardMaterial3D
		lm.albedo_color = Color(0.14, 0.26, 0.30)
		lk.material_override = lm
		add_child(lk)
	# rivers: a ribbon down each valley's channel (not the gorge's: fog hides it)
	var k := MeshKit.new()
	for s in _segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var n := maxi(int(a.distance_to(b) / 20.0), 1)
		var half := 9.0 if String(s[5]) != "gorge" else 6.0
		for i in range(n):
			var p0 := _unwarp(a.lerp(b, float(i) / n))
			var p1 := _unwarp(a.lerp(b, float(i + 1) / n))
			if in_square(p0.x, p0.y, 25.0) or in_square(p1.x, p1.y, 25.0):
				continue                          # the airport square has its own creek
			var dir := (p1 - p0).normalized()
			var sd := Vector2(-dir.y, dir.x) * half
			var y0: float = ground_t.height_at(p0.x, p0.y) + 0.35       # on the drawn ground, not floating
			var y1: float = ground_t.height_at(p1.x, p1.y) + 0.35
			k.quad(Vector3(p0.x + sd.x, y0, p0.y + sd.y), Vector3(p1.x + sd.x, y1, p1.y + sd.y), Vector3(p1.x - sd.x, y1, p1.y - sd.y), Vector3(p0.x - sd.x, y0, p0.y - sd.y), Color(0.22, 0.36, 0.40), Vector3.UP)
	var rm := wm.duplicate() as StandardMaterial3D
	rm.vertex_color_use_as_albedo = true
	var rmi := k.instance("Rivers")
	rmi.material_override = rm
	add_child(rmi)


# ------------------------------------------------------------------------------
#  Atmosphere: blue haze layering the ridges, fog pooled in the valleys
# ------------------------------------------------------------------------------
var _env: Environment
static var _saved := {}     # the lab's own look, from before the first region came up
static var _live := 0


func _atmosphere() -> void:
	var we: WorldEnvironment = null
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		we = n
		break
	if we == null:
		we = WorldEnvironment.new()
		we.environment = Environment.new()
		add_child(we)
	_env = we.environment
	if not game.is_empty():
		_env = null                   # the game's world.gd owns the look
		_fog_volumes()
		return
	if _live == 0:
		_saved.clear()
		for key in LOOK.keys():
			_saved[key] = _env.get(key)
		var sm := _sky_mat()
		if sm != null:
			for k2 in SKY_LOOK.keys():
				_saved["sky:" + k2] = sm.get(k2)
	_live += 1
	_apply_look()
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.0
	_env.volumetric_fog_albedo = Color(0.92, 0.94, 0.96)
	_env.volumetric_fog_length = 3000.0
	_fog_volumes()


## The river of fog in the gorge and a morning fog bank in the west valley:
## real fog volumes (volumetric) lying on the valley floors.
func _fog_volumes() -> void:
	for f in [[Vector2(450, 560), Vector3(900, 60, 300), 0.6], [Vector2(330, 430), Vector3(1400, 25, 380), 0.06], [Vector2(780, 610), Vector3(1700, 25, 440), 0.06]]:
		var fv := FogVolume.new()
		var c := px(f[0])
		var sz: Vector3 = f[1]
		fv.size = sz
		var fm := FogMaterial.new()
		fm.density = float(f[2])
		fm.albedo = Color(0.95, 0.96, 0.98)
		fm.height_falloff = 0.03
		fm.edge_fade = 0.4
		fv.material = fm
		fv.position = Vector3(c.x, height(c.x, c.y) + sz.y * 0.5 - 10.0, c.y)
		add_child(fv)


## Dave's Alps photo: near ridges dark navy, each ridge further back paler and
## bluer, the far ones pale blue-grey into a hazy sky; the haze a little
## thicker low down so the valleys hold it, the sun glowing through it.
const LOOK := {
	"fog_enabled": true,
	"fog_light_color": Color(0.46, 0.57, 0.68),
	"fog_density": 0.00008,             # ~20% at 3 km, ~55% at 10 km, ~85% at 25 km
	"fog_aerial_perspective": 0.5,
	"fog_sky_affect": 0.6,
	"fog_sun_scatter": 0.12,
	"fog_height": 260.0,
	"fog_height_density": 0.00012,
	"volumetric_fog_enabled": true,
}
const SKY_LOOK := {
	"sky_top_color": Color(0.36, 0.52, 0.72),
	"sky_horizon_color": Color(0.68, 0.76, 0.84),
	"ground_horizon_color": Color(0.52, 0.62, 0.71),       # the land under the haze past the map's edge
	"ground_bottom_color": Color(0.30, 0.38, 0.46),
}


func _sky_mat() -> ProceduralSkyMaterial:
	if _env != null and _env.sky != null:
		return _env.sky.sky_material as ProceduralSkyMaterial
	return null


func _apply_look() -> void:
	for key in LOOK.keys():
		_env.set(key, LOOK[key])
	var sm := _sky_mat()
	if sm != null:
		for k2 in SKY_LOOK.keys():
			sm.set(k2, SKY_LOOK[k2])


func _exit_tree() -> void:
	if not game.is_empty():
		return
	_live = maxi(_live - 1, 0)
	if _env != null and _live == 0:
		var sm := _sky_mat()
		for key in _saved.keys():
			if String(key).begins_with("sky:"):
				if sm != null:
					sm.set(String(key).substr(4), _saved[key])
			else:
				_env.set(key, _saved[key])


func _process(_dt: float) -> void:
	# (a reload frees the old copy after this one is up, and it puts the lab's
	# look back: keep ours)
	if _env != null and absf(_env.fog_density - float(LOOK["fog_density"])) > 1e-7:
		_apply_look()
	var cam := get_viewport().get_camera_3d()
	if veg != null and cam != null and veg.get("camera") != cam:
		veg.camera = cam                          # the forest streams round whatever camera is looking
	if cam != null and cam.far < 40000.0:
		cam.far = 60000.0


# ------------------------------------------------------------------------------
#  The forest: the game's own streamed vegetation (vegetation.gd: near trees in
#  3D, far ones as picture cards, chunks round the camera on worker threads)
#  growing on this ground through region_terrain.gd.
# ------------------------------------------------------------------------------
var veg: Node3D
var ground_t: RefCounted


func _forest() -> void:
	var fl = load("res://scripts/flora.gd")
	fl.set("treeline_base", 570.0)
	var vm = load("res://scripts/veg_meshes.gd")
	if "eztree" in vm:
		vm.set("eztree", true)                    # the real (EZ-Tree) trees
	veg = load("res://scripts/vegetation.gd").new()
	veg.name = "Forest"
	add_child(veg)
	veg.setup(ground_t)
	# the boulder layer is sized for the island's knolls: off here until it's
	# scaled for these mountains (they came out house-sized, everywhere)
	veg._radius[4] = 0.0
	# 3D trees close (450 m), the picture-card forest from there out: the 3D
	# forest to 1.5 km was ~180 M triangles (5 fps)
	veg._radius[0] = 450.0
	veg._radius[1] = 0.0 if no_cards else 2600.0    # (headless shots: the cards draw white there)
