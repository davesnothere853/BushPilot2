extends RefCounted
## The region's geology (DESIGN_NOTES 230, Dave: "set ore deposits where they
## would naturally occur"). Laid out the way real deposits form, so you can
## read the ground the way a prospector does:
##
##  - Gold belts: a few fault zones striking north-east across the ranges
##    (like the gold belts of the Alaskan and BC coast ranges). Quartz-gold
##    veins lie along them, steep, in shoots; richest where two cross, near the
##    mine town. Where they weather out the rock rusts orange (gossan).
##  - Placer gold: worn out of those veins and carried down the creeks. Rich
##    where a river crosses a belt and for some km downstream, fading
##    (heavy gold drops out fast); richest in the channel and on bedrock, in
##    the gorge where bedrock traps it, on inside bends. Hillsides: none.
##  - Copper: one big porphyry body by the glacier (the McCarthy kind),
##    malachite-green stain on its cliffs, chalcopyrite at depth.
##  - Coal: seams in the soft sedimentary basin toward the coast and the east
##    lakes, black bands in the cut banks and creek walls.
##  - Gravel: the river bars and the glacier's outwash (the aggregate pits).
##
## ore_at(x, z) -> what's under a spot; tint(x, y, z, slope, base) colours the
## ground's map with the clues.

var R: Node                       # region.gd: px(), _unwarp(), VALLEYS
var belts: Array = []             # [a: Vector2, b: Vector2, half_width m, strength 0..1]
var copper := [Vector2.ZERO, 1800.0]       # centre, radius
var coal_basin := [Vector2.ZERO, 7000.0]   # centre, radius
var _placer: Array = []           # [point: Vector2, g/m3] along the valley centre lines
var _noise := FastNoiseLite.new()


func plan(region: Node) -> void:
	R = region
	_noise.seed = 1896
	_noise.frequency = 1.0 / 60.0
	var P := func(x: float, y: float) -> Vector2: return R.px(Vector2(x, y))
	# the gold belts (sketch px): through the mine town, across the gorge, a
	# third over the north-east pass
	belts = [
		[P.call(40.0, 535.0), P.call(340.0, 205.0), 300.0, 1.0],          # through the mine town
		[P.call(300.0, 760.0), P.call(620.0, 460.0), 170.0, 0.7],
		[P.call(520.0, 360.0), P.call(860.0, 120.0), 150.0, 0.55],
	]
	copper = [P.call(735.0, 95.0), 600.0]
	coal_basin = [P.call(880.0, 560.0), 2300.0]
	_build_placers()


## How much the gold belts are under a point, 0..1.
func belt(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 0.0
	for b in belts:
		var q := Geometry2D.get_closest_point_to_segment(p, b[0], b[1])
		var d := p.distance_to(q)
		var w: float = b[2]
		best = maxf(best, float(b[3]) * (1.0 - smoothstep(w * 0.3, w, d)))
	return best


## Gold down each valley: sample the centre line every 150 m, from the head
## (higher end) down; gold picked up where it crosses a belt, carried on and
## dropping out (half gone every ~3 km), a lot more of it in the gorge.
func _build_placers() -> void:
	_placer.clear()
	for v in R.VALLEYS:
		var pts: Array = v[0]
		var hs: Array = v[1]
		var down := float(hs[0]) > float(hs[hs.size() - 1])          # flows from the first point?
		var line: Array = []
		for i in range(pts.size() - 1):
			var a: Vector2 = R.px(pts[i])
			var b: Vector2 = R.px(pts[i + 1])
			var n := maxi(int(a.distance_to(b) / 50.0), 1)
			for j in range(n):
				line.append(R._unwarp(a.lerp(b, float(j) / n)))
		line.append(R._unwarp(R.px(pts[pts.size() - 1])))
		if not down:
			line.reverse()
		var load := 0.0
		var gorge := String(v[3]) == "gorge"
		for k in range(line.size()):
			var q: Vector2 = line[k]
			load += belt(q.x, q.y) * 0.35
			load *= 0.965                                              # per 150 m: half in ~3 km
			var g := load * (2.6 if gorge else 1.0)
			_placer.append([q, g])


## Under a spot: placer gold in the pay gravel (g/m3), the vein (if any),
## copper (% Cu), coal (seam thickness m), gravel (0..1).
func ore_at(x: float, z: float) -> Dictionary:
	var p := Vector2(x, z)
	var out := {"placer_g_m3": 0.0, "vein_g_t": 0.0, "copper_pct": 0.0, "coal_m": 0.0}
	# placer: the nearest centre-line sample, richest in the channel
	var best := 1e9
	var g := 0.0
	for s in _placer:
		var d := p.distance_squared_to(s[0])
		if d < best:
			best = d
			g = s[1]
	var dc := sqrt(best)
	out["placer_g_m3"] = g * (1.0 - smoothstep(15.0, 90.0, dc)) * (0.6 + 0.8 * (_noise.get_noise_2d(x, z) * 0.5 + 0.5))
	# veins: thin steep sheets along the belt's strike, in shoots
	var bt := belt(x, z)
	if bt > 0.05:
		var ax: Vector2 = (belts[0][1] - belts[0][0]).normalized()
		var across := p.dot(Vector2(-ax.y, ax.x))
		var sheet := 1.0 - smoothstep(0.4, 1.2, absf(fposmod(across, 50.0) - 25.0))     # a vein every ~140 m across strike
		var shoot := smoothstep(0.2, 0.7, _noise.get_noise_2d(x * 0.2, z * 0.2) * 0.5 + 0.5)
		out["vein_g_t"] = 30.0 * bt * sheet * shoot
	var cd := p.distance_to(copper[0])
	out["copper_pct"] = 0.9 * (1.0 - smoothstep(float(copper[1]) * 0.3, float(copper[1]), cd))
	var kd := p.distance_to(coal_basin[0])
	if kd < float(coal_basin[1]):
		out["coal_m"] = 1.8 * (1.0 - smoothstep(float(coal_basin[1]) * 0.4, float(coal_basin[1]), kd))
	return out


## Colour the ground with the clues: gossan (rusty orange) where the belts
## weather on bare rock, malachite green on the copper cliffs, black coal
## bands in the basin's cut banks.
func tint(x: float, y: float, z: float, slope: float, c: Color) -> Color:
	var rocky := smoothstep(0.55, 1.0, slope)
	if rocky <= 0.0:
		return c
	var bt := belt(x, z)
	if bt > 0.0:
		var n := _noise.get_noise_2d(x * 0.15, z * 0.15) * 0.5 + 0.5
		c = c.lerp(Color(0.52, 0.30, 0.16), rocky * bt * smoothstep(0.45, 0.8, n) * 0.75)
	var cd := Vector2(x, z).distance_to(copper[0])
	if cd < float(copper[1]):
		var n2 := _noise.get_noise_2d(x * 0.1 + 300.0, z * 0.1) * 0.5 + 0.5
		c = c.lerp(Color(0.22, 0.45, 0.36), rocky * (1.0 - smoothstep(float(copper[1]) * 0.4, float(copper[1]), cd)) * smoothstep(0.5, 0.8, n2) * 0.7)
	var kd := Vector2(x, z).distance_to(coal_basin[0])
	if kd < float(coal_basin[1]) and y < 700.0:
		var band := 1.0 - smoothstep(0.5, 2.5, absf(fposmod(y, 38.0) - 19.0))         # seams every ~38 m of height
		c = c.lerp(Color(0.08, 0.08, 0.08), rocky * band * 0.85 * (1.0 - smoothstep(float(coal_basin[1]) * 0.5, float(coal_basin[1]), kd)))
	return c
