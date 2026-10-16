extends Node3D
## The home town (DESIGN_NOTES 234). Layout from Dave's Grok pictures
## (reference/towns/dave_town_aerial.png, dave_town_aerial2.png, entrance_v1-4):
## a small 1980s Alaskan town on the flat bench north of the west river, just
## upstream of the junction, the mountain rising behind it; realistic, in the
## pictures' colours - weathered brown wood, grey tin, white church.
##  - the highway comes in from the west (the mine town) and becomes one
##    straight paved main street, ~500 m, nearly level (drivable, ~1%);
##  - the entrance: the welcome sign on the left, the gas station on the right,
##    the water tower behind the sign;
##  - the north side: a row of weathered false-front shops on a boardwalk
##    (general store, cafe, bar, hardware, hotel), the white church at the end;
##  - the south side: town hall, police station, volunteer fire station;
##  - a dirt lane climbs behind the shops to a few houses on the hillside;
##  - power poles and lines down the south side, street lamps on the north;
##  - the road runs on east to the bush airport on the flat at the junction:
##    a gravel strip, the Quonset hangar, the fuel tank, the windsock.
## plan() runs before the ground is built (it levels the streets and pads in),
## build() after (it draws the streets and puts the buildings up).

const AssetLib = preload("res://scripts/assets/asset_lib.gd")
const Kits = preload("res://scripts/assets/kits.gd")
const Props = preload("res://scripts/assets/town_props.gd")

## main street: along z = STREET_Z from x0 to x1 (metres, region frame)
const STREET_Z := -316.0      # the floor north of the west river (river ~z -240 here)
const STREET_X0 := -1060.0
const STREET_X1 := -700.0
const STREET_HW := 11.0          # levelled half width: asphalt 4.2 + gravel parking to 8.5 + boardwalk
const ASPHALT_HW := 4.2
const LOT_GAP := 11.5            # from the street's centre line to the front of a lot
## the shops on the north side, west to east: [x, commercial_block sign index]
const SHOPS := [[-880.0, 21], [-866.0, 2], [-853.0, 3], [-840.0, 1], [-826.0, 5]]
## the airstrip on the flat at the junction (gravel, ~620 m)
const STRIP_A := Vector2(180, 40)       # on the south-east valley floor, north-east of the river
const STRIP_B := Vector2(560, 400)
const STRIP_HW := 12.0
## the road bridge over the north-east river just above the junction
const BRIDGE_A := Vector2(50, -121)       # square across the river (it runs (44,-63)->(77,-137))
const BRIDGE_B := Vector2(86, -105)

var R: Node
var streets: Array = []          # [PackedVector3Array, half width, kind]
var lots: Array = []             # [asset, Vector3 pos, yaw]
var poles: Array = []            # Vector3 foot of each power pole (in order down the line)
var clearings: Array = []        # Vector3(x, z, r): no forest here
var bridge_y := 0.0
var road_bridges: Array = []     # [centre Vector3, yaw, span m] - the mountain road's bridges
var mountain_road := PackedVector3Array()   # the road up to the airport bench (the whole line)
var _on_bridge := {}             # segment index -> true: drawn by the bridge, not as dirt
var _main_y0 := 0.0
var _main_y1 := 0.0


func plan(region: Node) -> void:
	R = region
	# --- main street: straight and level-ish, at the natural ground's mean
	_main_y0 = _ground_mean(Vector2(STREET_X0, STREET_Z), 25.0)
	_main_y1 = _ground_mean(Vector2(STREET_X1, STREET_Z), 25.0)
	var main := _line([Vector2(STREET_X0, STREET_Z), Vector2(STREET_X1, STREET_Z)], [_main_y0, _main_y1])
	_street(main, STREET_HW, "main")
	# the highway's approach from the west, eased onto the street's level
	# (it swings in from north of the river, then runs straight on into main street)
	var hw_a := Vector2(STREET_X0 - 200.0, STREET_Z - 20.0)
	var hw_b := Vector2(STREET_X0 - 90.0, STREET_Z - 4.0)
	_street(_line([hw_a, hw_b, Vector2(STREET_X0, STREET_Z)], [_ground_mean(hw_a, 15.0), lerpf(_ground_mean(hw_b, 15.0), _main_y0, 0.6), _main_y0]), 5.5, "highway")
	# --- the road on east to the airport
	# along the floor north of the river to the junction, over the north-east
	# river on a bridge, across to the airstrip
	var road_a := [Vector2(STREET_X1, STREET_Z), Vector2(-560, -282), Vector2(-400, -150), Vector2(-200, -128), Vector2(-60, -126), Vector2(BRIDGE_A.x, BRIDGE_A.y)]
	var road_b := [Vector2(BRIDGE_B.x, BRIDGE_B.y), Vector2(130, -60), Vector2(165, 0), Vector2(195, 30)]
	var ya: Array = [_main_y1]
	for i in range(1, road_a.size()):
		ya.append(_ground_mean(road_a[i], 12.0))
	bridge_y = maxf(float(ya[ya.size() - 1]), _ground_mean(BRIDGE_B, 6.0)) + 1.0
	ya[ya.size() - 1] = bridge_y
	var yb: Array = [bridge_y]
	for i in range(1, road_b.size()):
		yb.append(_ground_mean(road_b[i], 12.0))
	_street(_line(road_a, ya), 4.0, "road")
	_street(_line(road_b, yb), 4.0, "road")
	R.add_deck(BRIDGE_A, BRIDGE_B, 3.6, bridge_y)
	# --- the airstrip
	var sa := _ground_mean(STRIP_A, 20.0)
	var sb := _ground_mean(STRIP_B, 20.0)
	var strip := _line([STRIP_A, STRIP_B], [sa, sb])
	_street(strip, STRIP_HW, "strip")
	# --- the north side: the shops shoulder to shoulder-ish, then the church
	for s in SHOPS:
		_lot("commercial_block:%d" % (300 + int(s[1])), float(s[0]), -1.0, Vector2(4.3, 13.0))
	_lot("civic:0", -797.0, -1.0, Vector2(6.0, 12.0), 3.0)                       # the church, set back
	# --- the entrance: welcome sign (facing the traffic coming in), water tower behind
	_place("town_props:3", Vector2(STREET_X0 - 12.0, STREET_Z - 14.0), PI * 0.5, Vector2(5.0, 2.0))
	_place("town_props:4", Vector2(STREET_X0 + 8.0, STREET_Z - 40.0), 0.0, Vector2(4.0, 4.0))
	# --- the south side: the gas station at the entrance, the civic buildings
	_lot("civic:4", -1018.0, 1.0, Vector2(9.5, 12.0))
	_lot("civic:1", -870.0, 1.0, Vector2(6.5, 8.5))
	_lot("civic:2", -846.0, 1.0, Vector2(6.0, 7.0))
	_lot("civic:3", -822.0, 1.0, Vector2(9.5, 9.5))
	# --- a few houses at the west end, north side, set back behind fences
	var hv := [2, 5, 7]
	var hxs := [-990.0, -966.0, -942.0]
	for i in range(hxs.size()):
		_lot("house_victorian:%d" % (100 + hv[i]), hxs[i], -1.0, Vector2(7.5, 8.0), 0.0)
	# --- the airport: the hangar facing the strip, the fuel tank, the windsock
	var d := (STRIP_B - STRIP_A).normalized()
	var north := Vector2(d.y, -d.x)            # away from the river
	if north.y > 0.0:
		north = -north
	var yaw_n := atan2(north.x, north.y)
	var hp := STRIP_A + d * 60.0 + north * (STRIP_HW + 26.0)
	_place("town_props:0", hp, yaw_n, Vector2(7.0, 14.0), true)
	_place("town_props:2", hp + d * 22.0 + north * 6.0, yaw_n, Vector2(4.0, 2.0), true)
	_place("town_props:1", STRIP_A + d * 300.0 + north * (STRIP_HW + 10.0), 0.0, Vector2(1.0, 1.0), true)
	R.add_pad(STRIP_A + d * 70.0 + north * (STRIP_HW + 9.0), Vector2(14.0, 10.0), yaw_n, _ground_mean(hp, 10.0) + 0.2)
	# --- the power poles down the south side of main street, then the road
	var px := STREET_X0 + 10.0
	while px <= STREET_X1:
		poles.append(Vector3(px, lerpf(_main_y0, _main_y1, (px - STREET_X0) / (STREET_X1 - STREET_X0)), STREET_Z + 9.0))
		px += 42.0
	# --- the dirt road up the mountain to the home airport
	_mountain_road()
	# --- no forest in town, along the roads or on the strip
	for st in streets:
		var r: float = float(st[1]) + 14.0          # the forest comes close, like the pictures
		for q in (st[0] as PackedVector3Array):
			clearings.append(Vector3(q.x, q.z, r))
	for l in lots:
		clearings.append(Vector3((l[1] as Vector3).x, (l[1] as Vector3).z, 26.0))


## A lot on main street: its front at the boardwalk, running back away from the
## street (side -1 north, +1 south), levelled to the street's height.
func _lot(asset: String, x: float, side: float, half: Vector2, setback: float = 0.0) -> void:
	var y := lerpf(_main_y0, _main_y1, (x - STREET_X0) / (STREET_X1 - STREET_X0))
	var front := Vector2(x, STREET_Z + side * (LOT_GAP + setback))
	var yaw := atan2(0.0, side)
	R.add_pad(front + Vector2(0, side * half.y), half + Vector2(0.5, 0.5), yaw, y + 0.15)
	lots.append([asset, Vector3(front.x, y + 0.15, front.y), yaw])


## Something standing on its own levelled spot.
func _place(asset: String, at: Vector2, yaw: float, half: Vector2, centred: bool = false) -> void:
	var y := _ground_mean(at, maxf(half.x, half.y))
	var c := at if centred else at
	R.add_pad(c, half + Vector2(1.0, 1.0), yaw, y)
	lots.append([asset, Vector3(at.x, y, at.y), yaw])


func _street(line: PackedVector3Array, hw: float, kind: String) -> void:
	R.add_bench(line, hw)
	streets.append([line, hw, kind])


## A polyline through pts, densified every ~20 m, its height eased between the
## given heights at each corner (so the road never steps).
func _line(pts: Array, ys: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / 20.0)))
		for k in range(n):
			var t := float(k) / float(n)
			var p := a.lerp(b, t)
			out.append(Vector3(p.x, lerpf(float(ys[i]), float(ys[i + 1]), t), p.y))
	var e: Vector2 = pts[pts.size() - 1]
	out.append(Vector3(e.x, float(ys[ys.size() - 1]), e.y))
	return out


## The natural ground's average round a point (a few samples).
func _ground_mean(c: Vector2, r: float) -> float:
	var s := 0.0
	var n := 0
	for o in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		s += float(R.height(c.x + o.x, c.y + o.y))
		n += 1
	return s / float(n)


## The point on a polyline at a given x (the first segment spanning it).
func _on_poly(line: PackedVector3Array, x: float) -> Vector3:
	for i in range(line.size() - 1):
		var a := line[i]
		var b := line[i + 1]
		if (a.x - x) * (b.x - x) <= 0.0 and absf(b.x - a.x) > 0.01:
			return a.lerp(b, (x - a.x) / (b.x - a.x))
	return Vector3.INF


func build(region: Node) -> void:
	R = region
	_draw_streets()
	# the road bridge over the north-east river
	var br := AssetLib.get_asset("bridge:%d" % int(BRIDGE_A.distance_to(BRIDGE_B)))
	br.position = Vector3((BRIDGE_A.x + BRIDGE_B.x) * 0.5, bridge_y, (BRIDGE_A.y + BRIDGE_B.y) * 0.5)
	br.rotation.y = -atan2(BRIDGE_B.y - BRIDGE_A.y, BRIDGE_B.x - BRIDGE_A.x)
	add_child(br)
	for rb in road_bridges:
		var rbn := AssetLib.get_asset("bridge:%d" % int(rb[2]))
		rbn.position = rb[0]
		rbn.rotation.y = rb[1]
		add_child(rbn)
	for l in lots:
		var b := AssetLib.get_asset(l[0])
		b.position = l[1]
		b.rotation.y = l[2]
		add_child(b)
	# the boardwalk along the shops (north side), raised a step
	var K := Kits.new()
	var bx0: float = float(SHOPS[0][0]) - 6.0
	var bx1: float = float(SHOPS[SHOPS.size() - 1][0]) + 6.0
	var y0 := lerpf(_main_y0, _main_y1, (bx0 - STREET_X0) / (STREET_X1 - STREET_X0)) + 0.35
	var y1 := lerpf(_main_y0, _main_y1, (bx1 - STREET_X0) / (STREET_X1 - STREET_X0)) + 0.35
	var zb0 := STREET_Z - LOT_GAP
	var zb1 := STREET_Z - 8.6
	K.k("boards").quad(Vector3(bx0, y0, zb1), Vector3(bx0, y0, zb0), Vector3(bx1, y1, zb0), Vector3(bx1, y1, zb1), Color.WHITE, Vector3.UP)
	K.k("timber").quad(Vector3(bx0, y0 - 0.35, zb1), Vector3(bx0, y0, zb1), Vector3(bx1, y1, zb1), Vector3(bx1, y1 - 0.35, zb1), Color(0.6, 0.5, 0.4), Vector3(0, 0, 1))
	add_child(K.node("boardwalks"))
	# street lamps along the north side
	var lx := STREET_X0 + 30.0
	while lx < STREET_X1:
		var ly := lerpf(_main_y0, _main_y1, (lx - STREET_X0) / (STREET_X1 - STREET_X0))
		var lamp := AssetLib.get_asset("town_props:6")
		lamp.position = Vector3(lx, ly, STREET_Z - 8.3)
		lamp.rotation.y = PI
		add_child(lamp)
		lx += 70.0
	# the power poles and their sagging lines
	var W := Kits.new()
	for i in range(poles.size()):
		var pole := AssetLib.get_asset("town_props:5")
		pole.position = poles[i]
		add_child(pole)
		if i == 0:
			continue
		var a: Vector3 = poles[i - 1]
		var b: Vector3 = poles[i]
		for x in Props.ARM:
			var pa := a + Vector3(0, Props.POLE_H + 0.15, float(x) * 0.0) + Vector3(0, 0, 0) + _arm(float(x))
			var pb := b + Vector3(0, Props.POLE_H + 0.15, 0) + _arm(float(x))
			var prev := pa
			for s in range(1, 9):
				var t := float(s) / 8.0
				var q := pa.lerp(pb, t) - Vector3(0, 0.9 * 4.0 * t * (1.0 - t), 0)     # the sag
				Kits.rod(W.k("plain"), prev, q, 0.012, Color(0.08, 0.08, 0.08), 3)
				prev = q
	add_child(W.node("power_lines"))


## The mountain road's dirt: one continuous strip, mitred at the bends, two
## wheel tracks worn a shade darker down it.
func _draw_mtn(K, line: PackedVector3Array, hw: float) -> void:
	var n := line.size()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var tl := PackedVector3Array()
	var tr := PackedVector3Array()
	for i in range(n):
		var a := line[maxi(i - 1, 0)]
		var b := line[mini(i + 1, n - 1)]
		var d := Vector2(b.x - a.x, b.z - a.z).normalized()
		var nv := Vector3(-d.y, 0, d.x)
		var lift := Vector3(0, 0.12, 0)
		left.append(line[i] + nv * hw + lift)
		right.append(line[i] - nv * hw + lift)
		tl.append(line[i] + nv * 1.15 + lift + Vector3(0, 0.03, 0))
		tr.append(line[i] - nv * 1.15 + lift + Vector3(0, 0.03, 0))
	for i in range(n - 1):
		if line == mountain_road and _on_bridge.has(i):
			continue
		K.k("dirt").quad(left[i], left[i + 1], right[i + 1], right[i], Color.WHITE, Vector3.UP)
		# the wheel tracks (0.5 m wide each)
		for side in [tl, tr]:
			var s0: Vector3 = side[i]
			var s1: Vector3 = side[i + 1]
			var w := (left[i] - right[i]).normalized() * 0.25
			var w1 := (left[i + 1] - right[i + 1]).normalized() * 0.25
			K.k("dirt").quad(s0 + w, s1 + w1, s1 - w1, s0 - w, Color(0.72, 0.68, 0.62), Vector3.UP)


func _arm(x: float) -> Vector3:
	return Vector3(x, 0, 0)


## The streets on their benches: main street paved (gravel parking each side,
## a double yellow centre line), the highway paved, the road and the strip
## gravel, the lane dirt - each drawn at its own road height.
func _draw_streets() -> void:
	var K := Kits.new()
	for st in streets:
		var line: PackedVector3Array = st[0]
		var kind: String = st[2]
		if kind == "mtn":
			_draw_mtn(K, line, float(st[1]))
			continue
		var layers: Array = []          # [key, half width, lift]
		match kind:
			"main":
				layers = [["gravel", 8.5, 0.04], ["asphalt", ASPHALT_HW, 0.07]]
			"highway":
				layers = [["gravel", 4.8, 0.06], ["asphalt", ASPHALT_HW - 0.6, 0.09]]
			"road":
				layers = [["gravel", 3.3, 0.06]]
			"strip":
				layers = [["gravel", STRIP_HW - 1.0, 0.06]]
			_:
				layers = [["dirt", 3.0, 0.05]]
		for ly in layers:
			for i in range(line.size() - 1):
				var a := line[i]
				var b := line[i + 1]
				var d := Vector2(b.x - a.x, b.z - a.z).normalized()
				var n := Vector3(-d.y, 0, d.x) * float(ly[1])
				var lift := Vector3(0, float(ly[2]), 0)
				K.k(ly[0]).quad(a + n + lift, b + n + lift, b - n + lift, a - n + lift, Color.WHITE, Vector3.UP)
		if kind == "main" or kind == "highway":
			for i in range(line.size() - 1):
				var a2 := line[i]
				var b2 := line[i + 1]
				var d2 := Vector2(b2.x - a2.x, b2.z - a2.z).normalized()
				var side := Vector3(-d2.y, 0, d2.x)
				for off in [-0.12, 0.12]:
					var o: Vector3 = side * float(off)
					var m := side * 0.05
					var p0 := a2 + o + Vector3(0, 0.085, 0)
					var p1 := b2 + o + Vector3(0, 0.085, 0)
					K.k("plain").quad(p0 + m, p1 + m, p1 - m, p0 - m, Color(0.80, 0.66, 0.18), Vector3.UP)
	add_child(K.node("streets"))


# ------------------------------------------------------------------------------
#  The mountain road (Dave: "give it a dirt road that goes up there, drivable
#  in a regular truck"). From the highway at the west end of town, over the
#  west river on a truss bridge, up the mountain in switchbacks to the home
#  airport's bench: found on the ground by a search that keeps the grade
#  under ~9% where it can (a logging-road grade a pickup takes in 2nd), then
#  smoothed, its profile held to 10% at most and benched into the hillside
#  (cut ~1:1, fill 1:1.5), 8 m of bench with a 6 m dirt track on it. The last
#  stretch runs in level onto the airport's square at its back (west) end.
# ------------------------------------------------------------------------------
const ROAD_CELL := 12.0
const ROAD_GRADE := 0.12
const ROAD_HW := 4.0
var ROAD_STEP_MAX := 5.0

func _mountain_road() -> void:
	var g: Dictionary = R.game
	if g.is_empty() or not g.get("bench", false):
		return
	var t0 := Time.get_ticks_msec()
	var c: Vector2 = g["center"]
	var a: float = g["angle"]
	var half: float = g["half"]
	R.height(c.x, c.y)
	var lv: float = g["level"]
	var u := Vector2(cos(a), sin(a))
	var v := Vector2(-u.y, u.x)
	# the square's back (west) edge, away from the runway (local z -130) side
	var e_in := c - u * (half + 1.0) + v * 70.0
	var e_out := c - u * (half + 130.0) + v * 70.0
	# off main street's south side (a T at the west end of the shops), over
	# the river on one truss bridge, then up the mountain
	var start := Vector2(STREET_X0 + 70.0, STREET_Z + STREET_HW + 1.0)
	var y_start := lerpf(_main_y0, _main_y1, (start.x - STREET_X0) / (STREET_X1 - STREET_X0))
	# the grid
	var box := Rect2(start, Vector2.ZERO).expand(e_out).expand(c).grow(1700.0)
	var nx := int(box.size.x / ROAD_CELL) + 1
	var nz := int(box.size.y / ROAD_CELL) + 1
	var hg := PackedFloat32Array()
	hg.resize(nx * nz)
	var wet := PackedByteArray()
	wet.resize(nx * nz)
	var rivers := _river_lines(box)
	# the line is found once (tools/_hmap.gd town=1 bake=1) and kept in
	# data/mountain_road.json: the search takes seconds, the boot shouldn't
	var baked := _baked_road(c, a)
	if not baked.is_empty() and not OS.get_cmdline_user_args().has("bake=1"):
		_lay_road(baked, start, y_start, lv, c, u, v, half, rivers, t0)
		return
	for j in range(nz):
		for i in range(nx):
			var p := box.position + Vector2(i, j) * ROAD_CELL
			hg[j * nx + i] = R.height(p.x, p.y)
			var w := 0
			# the square and the band round it (where the ground eases to the
			# airport's level) are off limits; the road ends just outside the
			# band, near the airport's level, and runs in level from there
			var lq0 := p - c
			var lx0 := lq0.dot(u)
			var lz0 := lq0.dot(v)
			if R.in_square(p.x, p.y, 132.0):
				w = 2
			elif lx0 > half - 10.0 and lx0 < half + 560.0 and absf(lz0 + 130.0) < 230.0:
				w = 2                    # the cliff and the talus under it
			elif R.in_square(p.x, p.y, 180.0) and absf(hg[j * nx + i] - lv) < 10.0:
				# the edge of the airport: any of these will do for the end
				var lq := (p - c)
				var lxq := lq.dot(u)
				if lxq < half - 20.0:
					w = 3
			else:
				for rl in rivers:
					if _dist_poly(p, rl) < 16.0:
						w = 1
						break
			wet[j * nx + i] = w
	var cell := func(p: Vector2) -> Vector2i: return Vector2i(clampi(int(round((p.x - box.position.x) / ROAD_CELL)), 0, nx - 1), clampi(int(round((p.y - box.position.y) / ROAD_CELL)), 0, nz - 1))
	var sc: Vector2i = cell.call(start)
	var gc: Vector2i = cell.call(e_out)
	_goal_dir = Vector2.ZERO
	# the search reads the ground blurred a little (a road's bench cuts
	# through the small ribs and gullies; it's the big shape that matters)
	var hs := hg
	for bp in range(3):
		var hb := hs.duplicate()
		for j in range(1, nz - 1):
			for i in range(1, nx - 1):
				var acc := 0.0
				for dj in [-1, 0, 1]:
					for di in [-1, 0, 1]:
						acc += hs[(j + dj) * nx + i + di]
				hb[j * nx + i] = acc / 9.0
		hs = hb
	_hraw = hg
	_h_center = (c - box.position) / ROAD_CELL
	_h_radius = (half + 180.0) * 1.42
	var path := _astar(hs, wet, nx, nz, sc, gc)
	if path.is_empty():
		var ng := 0
		for w3 in wet:
			if w3 == 3:
				ng += 1
		print("region: no road up to the airport (%d goal cells, start wet %d, goal wet %d)" % [ng, wet[sc.y * nx + sc.x], wet[gc.y * nx + gc.x]])
		return
	# to world points, the ends exact, then rounded off (Chaikin) and resampled
	if OS.get_cmdline_user_args().has("bake=1"):
		var L := 0.0
		var gmax := 0.0
		for k in range(1, path.size()):
			var a2: Vector2i = path[k - 1]
			var b2: Vector2i = path[k]
			var dd := Vector2(b2 - a2).length() * ROAD_CELL
			var dh := absf(hs[b2.y * nx + b2.x] - hs[a2.y * nx + a2.x])
			L += dd
			gmax = maxf(gmax, dh / dd)
			if dh / dd > 0.13:
				var wp: Vector2 = box.position + Vector2(b2) * ROAD_CELL
				print("ASTAR steep %.0f%% at k %d %s h %.0f (local %s)" % [dh / dd * 100.0, k, str(wp.round()), hg[b2.y * nx + b2.x], str(Vector2((wp - c).dot(u), (wp - c).dot(v)).round())])
			if k % 10 == 0:
				print("ASTAR k %d L %.0f h %.0f" % [k, L, hg[b2.y * nx + b2.x]])
		var n10 := 0
		for k2 in range(1, path.size()):
			var a4: Vector2i = path[k2 - 1]
			var b4: Vector2i = path[k2]
			if absf(hs[b4.y * nx + b4.x] - hs[a4.y * nx + a4.x]) / (Vector2(b4 - a4).length() * ROAD_CELL) > 0.10:
				n10 += 1
		print("ASTAR steps %d len %.0f steepest step %.1f%%, %d steps over 10%%" % [path.size(), L, gmax * 100.0, n10])
	# where it reached the airport: the run-in goes square onto the nearest edge
	e_out = box.position + Vector2(path[path.size() - 1]) * ROAD_CELL
	var lo2 := e_out - c
	var lxo := lo2.dot(u)
	var lzo := lo2.dot(v)
	if absf(lxo) - half > absf(lzo) - half:
		lxo = signf(lxo) * (half + 1.0)
	else:
		lzo = signf(lzo) * (half + 1.0)
	lxo = clampf(lxo, -half - 1.0, half - 40.0)
	lzo = clampf(lzo, -half - 1.0, half + 1.0)
	e_in = c + u * lxo + v * lzo
	var pts: Array = [start]
	for k in range(1, path.size()):
		var q: Vector2 = box.position + Vector2(path[k]) * ROAD_CELL
		if q.distance_to(start) < 30.0:
			continue
		pts.append(q)
	for it in range(2):
		pts = _chaikin(pts)
	pts.append(e_in)
	if OS.get_cmdline_user_args().has("bake=1"):
		var arr: Array = []
		for q in pts:
			arr.append([snappedf(q.x, 0.01), snappedf(q.y, 0.01)])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data"))
		var f := FileAccess.open("res://data/mountain_road.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"center": [c.x, c.y], "angle": a, "pts": arr}))
		f.close()
		print("region: mountain road baked")
	_lay_road(pts, start, y_start, lv, c, u, v, half, rivers, t0)


func _baked_road(c: Vector2, a: float) -> Array:
	var f := FileAccess.open("res://data/mountain_road.json", FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary) or Vector2(d["center"][0], d["center"][1]).distance_to(c) > 0.5 or absf(float(d["angle"]) - a) > 0.001:
		return []
	var out: Array = []
	for q in d["pts"]:
		out.append(Vector2(q[0], q[1]))
	return out


## The road laid on the ground along its line (planned or baked): profile,
## bridges, benches, drawing.
func _lay_road(pts: Array, start: Vector2, y_start: float, lv: float, c: Vector2, u: Vector2, v: Vector2, half: float, rivers: Array, t0: int) -> void:
	var e_in: Vector2 = pts[pts.size() - 1]
	var e_out: Vector2 = pts[pts.size() - 2]
	pts = _resample(pts, 12.0)
	# the river crossings: spans where the line is over a channel
	var on_wet: Array = []
	for p in pts:
		var w2 := false
		for rl in rivers:
			if _dist_poly(p, rl) < 15.0:
				w2 = true
				break
		on_wet.append(w2)
	# the profile: the ground smoothed, held to the grade, the ends pinned
	var ys: Array = []
	for p in pts:
		ys.append(R.height(p.x, p.y))
	ys = _smooth(ys, 3)
	var n := pts.size()
	# the level the airport's ground has right at the edge where the road comes on
	lv = float(R.height(e_in.x, e_in.y))
	ys[0] = y_start
	ys[n - 1] = lv
	# the run-in is level
	for k in range(n):
		if (pts[k] as Vector2).distance_to(e_in) <= e_out.distance_to(e_in) + 1.0:
			ys[k] = lv
	# bridges: the deck level with the higher bank + 1.5 m, flat across
	var spans: Array = []
	var k0 := -1
	for k in range(n):
		if on_wet[k] and k0 < 0:
			k0 = maxi(k - 2, 1)
		elif not on_wet[k] and k0 >= 0:
			var k1 := mini(k + 1, n - 2)
			# a bridge only where the road really crosses (the two ends on
			# opposite banks); along a bank it just runs on the bank
			if _crosses(pts[k0], pts[k1], rivers):
				spans.append([k0, k1])
			k0 = -1
	for sp in spans:
		var deck := maxf(float(ys[sp[0]]), float(ys[sp[1]])) + 1.5
		for k in range(sp[0], sp[1] + 1):
			ys[k] = deck
	var fixed := {}
	for sp in spans:
		for k in range(sp[0], sp[1] + 1):
			fixed[k] = true
	for k in range(n):
		if (pts[k] as Vector2).distance_to(e_in) <= e_out.distance_to(e_in) + 1.0:
			fixed[k] = true
	fixed[0] = true
	var ys0 := ys.duplicate()
	ys = _hold_grade(pts, ys, fixed, ROAD_GRADE)
	if OS.get_cmdline_user_args().has("bake=1"):
		for k in range(0, n, 15):
			print("PROF %d nat %.0f road %.0f" % [k, float(ys0[k]), float(ys[k])])
	var line := PackedVector3Array()
	for k in range(n):
		line.append(Vector3(pts[k].x, ys[k], pts[k].y))
	mountain_road = line
	streets.append([line, 3.2, "mtn"])
	for sp in spans:
		for k in range(int(sp[0]), int(sp[1])):
			_on_bridge[k] = true
	# benched in, in short pieces (each with its own box, so the ground
	# queries stay quick), never under a bridge
	var piece := PackedVector3Array()
	for k in range(n):
		var under := false
		for sp in spans:
			if k > sp[0] and k < sp[1]:
				under = true
		if under:
			if piece.size() > 1:
				R.add_bench(piece, ROAD_HW, true)
				_draw_piece(piece)
			piece = PackedVector3Array()
			continue
		piece.append(line[k])
		if piece.size() >= 12:
			R.add_bench(piece, ROAD_HW, true)
			_draw_piece(piece)
			piece = PackedVector3Array([line[k]])
	if piece.size() > 1:
		R.add_bench(piece, ROAD_HW, true)
		_draw_piece(piece)
	for sp in spans:
		var pa: Vector3 = line[sp[0]]
		var pb: Vector3 = line[sp[1]]
		var span := Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z))
		road_bridges.append([(pa + pb) * 0.5, -atan2(pb.z - pa.z, pb.x - pa.x), clampf(span, 20.0, 120.0)])
		R.add_deck(Vector2(pa.x, pa.z), Vector2(pb.x, pb.z), 3.6, pa.y)
		print("region: road bridge at %s, %.0f m" % [str(((pa + pb) * 0.5).round()), span])
	var length := 0.0
	var steep := 0.0
	for k in range(1, n):
		var dd := Vector2(line[k].x - line[k - 1].x, line[k].z - line[k - 1].z).length()
		length += dd
		steep = maxf(steep, absf(line[k].y - line[k - 1].y) / maxf(dd, 0.1))
	print("region: mountain road %.1f km, %d bridges, rises %.0f m, steepest %.1f%%, %d ms" % [length / 1000.0, spans.size(), lv - y_start, steep * 100.0, Time.get_ticks_msec() - t0])


func _draw_piece(_piece: PackedVector3Array) -> void:
	pass                     # drawn whole (one continuous strip), see _lay_road


## The valleys' river centre lines (not the gorge's) near the box.
func _river_lines(box: Rect2) -> Array:
	var out: Array = []
	for s in R._segs:
		if String(s[5]) == "gorge":
			continue
		if not (s[6] as Rect2).intersects(box):
			continue
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var n := maxi(int(a.distance_to(b) / 20.0), 1)
		var l := PackedVector2Array()
		for i in range(n + 1):
			l.append(R._unwarp(a.lerp(b, float(i) / n)))
		out.append(l)
	return out


## Do a and b lie on opposite sides of a river (any segment of it crossed)?
func _crosses(a: Vector2, b: Vector2, rivers: Array) -> bool:
	for l in rivers:
		for i in range((l as PackedVector2Array).size() - 1):
			if Geometry2D.segment_intersects_segment(a, b, l[i], l[i + 1]) != null:
				return true
	return false


func _dist_poly(p: Vector2, l: PackedVector2Array) -> float:
	var best := 1e9
	for i in range(l.size() - 1):
		var a := l[i]
		var ab := l[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## A* over the height grid: the cost of a step is its length, more where the
## grade is over ~8.5% (steeply more past 12%), more across a steep hillside
## (a big cut), a lot for each cell of river (cross it short and square).
var _goal_dir := Vector2.ZERO
var _h_center := Vector2.ZERO     # the airport's middle in grid cells (A* heuristic)
var _h_radius := 0.0              # metres: past this from the middle, a goal could be
var _hraw := PackedFloat32Array()     # the unblurred grid: what's possible at all

func _astar(hg: PackedFloat32Array, wet: PackedByteArray, nx: int, nz: int, s: Vector2i, gl: Vector2i) -> Array:
	# 16 headings in order round the compass; the state is (cell, heading) so
	# turning costs: long legs and few, wide switchbacks, not a staircase
	var dirs: Array = []
	for k in range(16):
		var ang := TAU * k / 16.0
		dirs.append(Vector2(cos(ang), sin(ang)))
	var steps: Array = []
	for d in dirs:
		var best := Vector2i.ZERO
		var bd := 1e9
		for cand in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(0, 1), Vector2i(-1, 2), Vector2i(-2, 1), Vector2i(-1, 1),
				Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(-2, -1), Vector2i(-1, -2), Vector2i(0, -1), Vector2i(1, -2), Vector2i(2, -1), Vector2i(1, -1)]:
			var e := (d as Vector2).angle_to(Vector2(cand))
			if absf(e) < bd:
				bd = absf(e)
				best = cand
		steps.append(best)
	var N := nx * nz * 16
	var gs := PackedFloat32Array()
	gs.resize(N)
	gs.fill(1e30)
	var came := PackedInt32Array()
	came.resize(N)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(N)
	var heap: Array = []
	var s0 := s.y * nx + s.x
	for hd in range(16):
		gs[s0 * 16 + hd] = 0.0
		_hpush(heap, [0.0, s0 * 16 + hd])
	var goal_state := -1
	var pops := 0
	while not heap.is_empty():
		pops += 1
		if pops % 20000 == 0 and OS.get_cmdline_user_args().has("astar_debug=1"):
			print("ASTAR pops %d heap %d" % [pops, heap.size()])
		var top: Array = _hpop(heap)
		var st: int = top[1]
		if closed[st] == 1:
			continue
		closed[st] = 1
		var ci := st / 16
		var hd0 := st % 16
		if wet[ci] == 3 or ci == gl.y * nx + gl.x:
			goal_state = st
			break
		var cx := ci % nx
		var cz := ci / nx
		var ch := hg[ci]
		for dt in [-4, -3, -2, -1, 0, 1, 2, 3, 4]:
			var hd: int = (hd0 + dt + 16) % 16
			if dt == 8 and false:
				continue
			var d: Vector2i = steps[hd]
			var x2: int = cx + d.x
			var z2: int = cz + d.y
			if x2 < 0 or z2 < 0 or x2 >= nx or z2 >= nz:
				continue
			var ni := z2 * nx + x2
			var ns := ni * 16 + hd
			if closed[ns] == 1 or wet[ni] == 2:
				continue
			# the cells stepped over count too (no jumping a river)
			var mid := Vector2i(cx + int(round(d.x * 0.5)), cz + int(round(d.y * 0.5)))
			if wet[mid.y * nx + mid.x] == 2:
				continue
			var dist := Vector2(d).length() * ROAD_CELL
			var gr := absf(hg[ni] - ch) / dist
			if absf(_hraw[ni] - _hraw[ci]) / dist > ROAD_STEP_MAX:
				continue
			# (the line is smoothed after, corners cut: aim under 7%, 9.5% is the most)
			var over := maxf(gr - 0.06, 0.0)
			var cost := dist * (1.0 + 300.0 * over + 80000.0 * maxf(gr - 0.085, 0.0) * maxf(gr - 0.085, 0.0))
			var sx := absf(hg[z2 * nx + mini(x2 + 1, nx - 1)] - hg[z2 * nx + maxi(x2 - 1, 0)]) / (2.0 * ROAD_CELL)
			var sz := absf(hg[mini(z2 + 1, nz - 1) * nx + x2] - hg[maxi(z2 - 1, 0) * nx + x2]) / (2.0 * ROAD_CELL)
			cost += dist * 0.6 * maxf(Vector2(sx, sz).length() - 0.6, 0.0)
			if wet[ni] == 1 or wet[mid.y * nx + mid.x] == 1:
				cost += 4000.0          # one bridge, not two: cross once, short and square
			# turning: a hairpin (the 8) is a switchback: allowed, at a price
			var tc := absf(float(dt))
			cost += 2.0 * tc * tc
			var ng := gs[st] + cost
			if ng < gs[ns]:
				gs[ns] = ng
				came[ns] = st
				# the heuristic: straight-line distance to the ring of goal cells
				# round the airport (never more than the truth, or the search
				# turns greedy and takes the steep way)
				var hx := float(x2 - _h_center.x)
				var hz := float(z2 - _h_center.y)
				_hpush(heap, [ng + maxf(sqrt(hx * hx + hz * hz) * ROAD_CELL - _h_radius, 0.0), ns])
	if goal_state < 0:
		return []
	var out: Array = []
	var k := goal_state
	while k >= 0:
		var c := k / 16
		out.push_front(Vector2i(c % nx, c / nx))
		k = came[k]
	return out


func _hpush(h: Array, e: Array) -> void:
	h.append(e)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if float(h[p][0]) <= float(h[i][0]):
			break
		var t = h[p]
		h[p] = h[i]
		h[i] = t
		i = p


func _hpop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	h[0] = last
	var i := 0
	var n := h.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and float(h[l][0]) < float(h[m][0]):
			m = l
		if r < n and float(h[r][0]) < float(h[m][0]):
			m = r
		if m == i:
			break
		var t = h[m]
		h[m] = h[i]
		h[i] = t
		i = m
	return top


## String pulling: from each point, straight on to the farthest point ahead
## the road can reach in a straight line (ground grade on the way never past
## 12%, the whole leg within 10%, clear of rivers and the square): the grid's
## staircase and its little hooks become long legs and clean switchbacks.
func _pull(pts: Array, rivers: Array) -> Array:
	var out: Array = [pts[0]]
	var i := 0
	var n := pts.size()
	while i < n - 1:
		var best := i + 1
		for j in range(mini(n - 1, i + 40), i + 1, -1):
			if _leg_ok(pts[i], pts[j], rivers):
				best = j
				break
		out.append(pts[best])
		i = best
	return out


func _leg_ok(a: Vector2, b: Vector2, rivers: Array) -> bool:
	var L := a.distance_to(b)
	var n := maxi(int(L / 10.0), 1)
	var ha: float = R.height(a.x, a.y)
	var hb: float = R.height(b.x, b.y)
	if absf(hb - ha) / maxf(L, 1.0) > 0.10:
		return false
	var prev := ha
	for k in range(1, n + 1):
		var q := a.lerp(b, float(k) / n)
		var h: float = R.height(q.x, q.y)
		if absf(h - prev) / (L / n) > 0.13:
			return false
		# stay near the straight grade line (cut/fill under ~6 m)
		if absf(h - lerpf(ha, hb, float(k) / n)) > 6.0:
			return false
		if R.in_square(q.x, q.y, 20.0):
			return false
		prev = h
	return true


func _chaikin(pts: Array) -> Array:
	var out: Array = [pts[0]]
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	out.append(pts[pts.size() - 1])
	return out


func _resample(pts: Array, step: float) -> Array:
	var out: Array = [pts[0]]
	var carry := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var L := a.distance_to(b)
		var t := step - carry
		while t < L:
			out.append(a.lerp(b, t / L))
			t += step
		carry = L - (t - step)
	if (out[out.size() - 1] as Vector2).distance_to(pts[pts.size() - 1]) > 2.0:
		out.append(pts[pts.size() - 1])
	else:
		out[out.size() - 1] = pts[pts.size() - 1]
	return out


func _smooth(ys: Array, r: int) -> Array:
	var out: Array = []
	for i in range(ys.size()):
		var s := 0.0
		var n := 0
		for k in range(maxi(i - r, 0), mini(i + r, ys.size() - 1) + 1):
			s += float(ys[k])
			n += 1
		out.append(s / float(n))
	return out


## The profile held to the grade: the free points pulled within grade of
## their neighbours, back and forth till it settles (the fixed ones stay).
func _hold_grade(pts: Array, ys: Array, fixed: Dictionary, gmax: float) -> Array:
	var y := ys.duplicate()
	var n := y.size()
	for it in range(200):
		var moved := 0.0
		for k in range(1, n):
			if fixed.has(k):
				continue
			var d := (pts[k] as Vector2).distance_to(pts[k - 1]) * gmax
			var c := clampf(float(y[k]), float(y[k - 1]) - d, float(y[k - 1]) + d)
			moved += absf(c - float(y[k]))
			y[k] = c
		for k in range(n - 2, -1, -1):
			if fixed.has(k):
				continue
			var d2 := (pts[k] as Vector2).distance_to(pts[k + 1]) * gmax
			var c2 := clampf(float(y[k]), float(y[k + 1]) - d2, float(y[k + 1]) + d2)
			moved += absf(c2 - float(y[k]))
			y[k] = c2
		if moved < 0.01:
			break
	return y
