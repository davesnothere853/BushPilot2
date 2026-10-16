extends RefCounted
## Height data for the island, plus every "what is the ground like here?" query
## used by the flight model, the world builder and the map.
##
## World axes: +X is east, +Z is south, +Y is up. North is -Z.

const CELL: float = 40.0
const NO_WATER: float = -1.0e9
const Flora = preload("res://scripts/flora.gd")
const SEA_FLOOR: float = -45.0

const SURF_ROUGH := 0     # untended ground: tundra, brush, rock
const SURF_GRAVEL := 1
const SURF_GRASS := 2
const SURF_DIRT := 3
const SURF_SNOW := 4      # deep, unpacked snow
const SURF_PACKED := 5    # packed snow on a maintained strip
const SURF_ICE := 6
const SURF_WATER := 7

const SURFACE_NAMES: Array[String] = ["rough ground", "gravel", "grass", "dirt", "deep snow", "packed snow", "ice", "water"]

const TREE_CELL: float = 32.0

var n: int = 768                       # cells per side
var size: float = 0.0
var half: float = 0.0
var heights := PackedFloat32Array()    # (n+1) * (n+1)
var forest := PackedFloat32Array()     # forest density 0..1 per vertex
# Ecology, 0..1 per vertex (see _build_ecology): flora.gd reads these to decide
# what grows where, and the terrain shader paints the ground to match.
var creek := PackedFloat32Array()      # water gathering into a drainage: willow, cottonwood
var bog := PackedFloat32Array()        # flat, waterlogged ground: muskeg
var burn := PackedFloat32Array()       # old fire scars: snags, fireweed, young birch and aspen
var strips: Array[Dictionary] = []
var lakes: Array[Dictionary] = []
## Strips with a hangar: planes can be stored, swapped and bought there.
const HANGARS := ["Port Ashby", "Moose Lake Lodge", "Tern Harbor"]
## Seaplane docks: {name, lake (-1 for the sea), shore Vector2, water Vector2,
## level, heading (degrees, from the dock out over the water)}
var docks: Array[Dictionary] = []
var season: int = 0

var tree_n: int = 0
var tree_h := PackedByteArray()        # (old tree grid, unused now)
var clearings: Array[Vector3] = []     # (x, z, radius): kept clear of plants (buildings, yards)
## Buildings you can walk (and taxi) into: {xf, size (w, h, d), door (width),
## r (bounding radius)}. Their floor is a level slab; walls are solid but the
## front (local -Z) is open across the door.
var hollows: Array = []
var solids: Array = []                 # solid building boxes planes can hit: {xf, inv, size, r}
var has_trees := false                 # set when the vegetation is planted (flora.gd decides where)

var _segs: Array = []                  # valley network


# ------------------------------------------------------------------------------
#  Site definitions
# ------------------------------------------------------------------------------
func _define_sites() -> void:
	strips.clear()
	lakes.clear()
	_segs.clear()

	# Valley network. Each point is (x, floor elevation, z); the two numbers after
	# the list are how wide the flat floor is and how far out the hills reach full height.
	# Three corridors run north to south (west plain, central valley, east valley),
	# joined by the north coast lowland and by two passes across the ranges.
	var hub := Vector3(300, 40, -9000)
	_add_valley([
		Vector3(1500, -30, 11500), Vector3(1400, 3, 8300), Vector3(500, 4, 5600),
		Vector3(-300, 110, 3500), Vector3(-600, 150, 1200), Vector3(200, 230, -2500),
		Vector3(600, 180, -6000), hub, Vector3(0, -20, -12500)], 450.0, 2800.0)
	# West: a wide coastal plain between the sea and the West Range.
	_add_valley([
		Vector3(-3600, 5, 11200), Vector3(-5500, 15, 9000), Vector3(-8500, 30, 5000), Vector3(-9000, 60, 500),
		Vector3(-7800, 45, -4500), Vector3(-4500, 25, -8500), hub], 1300.0, 3600.0)
	_add_valley([
		Vector3(-9500, 5, 8000), Vector3(-12000, 5, 3000), Vector3(-12500, 5, -1500),
		Vector3(-11000, 5, -6000), Vector3(-7500, 5, -10000), Vector3(-3000, 8, -11500),
		Vector3(1400, 10, -10800), Vector3(5500, 10, -10500)], 1500.0, 3500.0)
	# East: a narrower valley from the south-east bay up to the north coast.
	_add_valley([
		Vector3(9000, -20, 8500), Vector3(8200, 60, 5500), Vector3(7600, 220, 2000),
		Vector3(7200, 330, -1500), Vector3(6800, 250, -5000), Vector3(4500, 60, -8200), hub], 300.0, 2000.0)
	# Granite Creek canyon, climbing west out of the east valley to the mine,
	# then on over Miner's Notch and down to Moose Lake.
	_add_valley([Vector3(7600, 220, 2000), Vector3(5600, 520, 1300), Vector3(4300, 700, 900)], 180.0, 1300.0)
	_add_valley([Vector3(4300, 700, 900), Vector3(3000, 980, 1100), Vector3(1600, 600, 1600), Vector3(-600, 150, 1200)], 120.0, 800.0)
	# Windy Pass, across the West Range from Moose Lake to the plain.
	_add_valley([
		Vector3(-600, 150, 1200), Vector3(-2600, 600, 300), Vector3(-4300, 1120, -600),
		Vector3(-6000, 600, -1200), Vector3(-7800, 100, -1500)], 140.0, 900.0)
	# The glacier bench high in the East Range.
	_add_valley([Vector3(200, 230, -2500), Vector3(1800, 900, -3000), Vector3(3500, 1650, -3500), Vector3(4300, 1750, -3750)], 200.0, 900.0)

	lakes.append({"name": "Moose Lake", "pos": Vector2(-1400, 1300), "radius": 650.0, "level": 146.0, "depth": 14.0, "seed": 1.3})
	lakes.append({"name": "Loon Lake", "pos": Vector2(-9300, -2600), "radius": 720.0, "level": 46.0, "depth": 10.0, "seed": 4.1})
	lakes.append({"name": "Mirror Lake", "pos": Vector2(7250, -1900), "radius": 420.0, "level": 322.0, "depth": 12.0, "seed": 2.2})

	_add_strip("Port Ashby", Vector3(2400, 14, 8400), 350.0, 900.0, 26.0, SURF_GRAVEL, 0.0, 1, true,
		"Home base. Long, wide and flat beside the inlet.")
	_add_strip("Salmon Bend", Vector3(800, 5, 5450), 20.0, 300.0, 14.0, SURF_GRAVEL, 0.0, 4, false,
		"A gravel bar at the head of the inlet. Short, with rising ground to the north.")
	_add_strip("Moose Lake Lodge", Vector3(-250, 151, 1050), 345.0, 520.0, 18.0, SURF_GRASS, 0.0, 2, true,
		"Grass strip beside the lake, where the two passes meet the central valley.")
	_add_strip("Tern Harbor", Vector3(1400, 12, -10200), 80.0, 700.0, 22.0, SURF_GRAVEL, 0.0, 1, true,
		"Fishing village on the north coast. Easy, but open to the sea wind.")
	_add_strip("Caribou Flats", Vector3(-8500, 62, 900), 10.0, 650.0, 24.0, SURF_DIRT, 0.0, 2, false,
		"Open tundra on the west plain. Plenty of room.")
	_add_strip("Cape Sorrow", Vector3(-6300, 4, 9700), 310.0, 360.0, 16.0, SURF_DIRT, 0.0, 3, false,
		"Hard sand near the south-west cape. Low, exposed and often gusty.")
	_add_strip("Otter Creek", Vector3(7650, 222, 2100), 350.0, 400.0, 16.0, SURF_GRASS, 0.0, 3, false,
		"Grass strip on the floor of the east valley, with steep walls either side.")
	_add_strip("Granite Creek Mine", Vector3(4700, 665, 1000), 287.0, 420.0, 16.0, SURF_GRAVEL, 0.05, 4, false,
		"One-way strip up a canyon. Land uphill to the west, take off downhill to the east.")
	_add_strip("Windy Pass", Vector3(-4300, 1125, -600), 294.0, 380.0, 16.0, SURF_DIRT, 0.015, 5, false,
		"A saddle in the West Range at 3,700 feet. Thin air and crosswinds.")
	_add_strip("Kestrel Glacier", Vector3(3500, 1650, -3500), 74.0, 420.0, 22.0, SURF_DIRT, 0.04, 5, false,
		"A snowfield at 5,400 feet. Land uphill to the east. Snow all year.")


func _add_valley(pts: Array, r_in: float, r_out: float) -> void:
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		_segs.append([a.x, a.z, a.y, b.x, b.z, b.y, r_in, r_out])


func _add_strip(name: String, pos: Vector3, heading: float, length: float, width: float,
		surface: int, slope: float, difficulty: int, fuel: bool, desc: String) -> void:
	var hr := deg_to_rad(heading)
	if difficulty <= 2:
		# Easy strips get open country off both ends.
		var d := Vector3(sin(hr), 0.0, -cos(hr))
		var reach := length * 0.5 + 2600.0
		_add_valley([pos - d * reach, pos, pos + d * reach], 320.0, 1900.0)
	strips.append({
		"name": name, "pos": pos, "heading": heading,
		"dir": Vector2(sin(hr), -cos(hr)),
		"length": length, "width": width, "surface": surface, "slope": slope,
		"difficulty": difficulty, "fuel": fuel, "desc": desc,
	})


# ------------------------------------------------------------------------------
#  Generation
# ------------------------------------------------------------------------------
func generate(seed_value: int = 1987, cells: int = 768) -> void:
	n = cells
	size = n * CELL
	half = size * 0.5
	_define_sites()

	var vn := n + 1
	heights.resize(vn * vn)
	forest.resize(vn * vn)

	# --- coarse macro fields: valley floor elevation and mountain mask ---------
	var step := 6
	var cn := n / step + 1
	var cfloor := PackedFloat32Array()
	var cmask := PackedFloat32Array()
	cfloor.resize(cn * cn)
	cmask.resize(cn * cn)
	var seg_count := _segs.size()
	for cj in range(cn):
		var z := -half + cj * step * CELL
		for ci in range(cn):
			var x := -half + ci * step * CELL
			var wsum := 0.0
			var fsum := 0.0
			var mask := 1.0
			for s in range(seg_count):
				var sg: Array = _segs[s]
				var ax: float = sg[0]
				var az: float = sg[1]
				var bx: float = sg[3]
				var bz: float = sg[4]
				var dx := bx - ax
				var dz := bz - az
				var t := clampf(((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz), 0.0, 1.0)
				var px := ax + dx * t - x
				var pz := az + dz * t - z
				var d := sqrt(px * px + pz * pz)
				var fl: float = lerpf(sg[2], sg[5], t)
				var r_out: float = sg[7]
				var w := 1.0 / pow(d / r_out + 0.04, 4.0)
				wsum += w
				fsum += w * fl
				var mk := smoothstep(sg[6], r_out, d)
				if mk < mask:
					mask = mk
			cfloor[cj * cn + ci] = fsum / wsum
			cmask[cj * cn + ci] = mask

	# --- noise layers ---------------------------------------------------------
	var ridge := FastNoiseLite.new()
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.seed = seed_value
	ridge.frequency = 1.0 / 5200.0
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 5
	ridge.fractal_lacunarity = 2.1
	ridge.fractal_gain = 0.5

	var hills := FastNoiseLite.new()
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.seed = seed_value + 11
	hills.frequency = 1.0 / 800.0
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 3

	var detail := FastNoiseLite.new()
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.seed = seed_value + 23
	detail.frequency = 1.0 / 170.0
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 2

	var coast := FastNoiseLite.new()
	coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	coast.seed = seed_value + 37
	coast.frequency = 1.0 / 2600.0
	coast.fractal_type = FastNoiseLite.FRACTAL_FBM
	coast.fractal_octaves = 3

	# --- fine pass ------------------------------------------------------------
	var inv_step := 1.0 / float(step)
	for j in range(vn):
		var z := -half + j * CELL
		var cjf := j * inv_step
		var cj0 := mini(int(cjf), cn - 2)
		var tz := cjf - cj0
		var row0 := cj0 * cn
		var row1 := row0 + cn
		for i in range(vn):
			var x := -half + i * CELL
			var cif := i * inv_step
			var ci0 := mini(int(cif), cn - 2)
			var tx := cif - ci0
			var f00 := cfloor[row0 + ci0]
			var f10 := cfloor[row0 + ci0 + 1]
			var f01 := cfloor[row1 + ci0]
			var f11 := cfloor[row1 + ci0 + 1]
			var fl := lerpf(lerpf(f00, f10, tx), lerpf(f01, f11, tx), tz)
			var m00 := cmask[row0 + ci0]
			var m10 := cmask[row0 + ci0 + 1]
			var m01 := cmask[row1 + ci0]
			var m11 := cmask[row1 + ci0 + 1]
			var m := lerpf(lerpf(m00, m10, tx), lerpf(m01, m11, tx), tz)

			var r := clampf(0.5 * (ridge.get_noise_2d(x, z) + 1.0), 0.0, 1.0)
			# High country gets lower peaks on top of it, so nothing towers out of scale.
			var cap := clampf((2500.0 - fl) / 2300.0, 0.25, 1.0)
			var h := fl + pow(m, 1.15) * (240.0 + 1900.0 * pow(r, 1.7)) * cap
			h += hills.get_noise_2d(x, z) * (2.0 + 45.0 * m)
			# Low country rolls gently instead of lying dead flat.
			h += hills.get_noise_2d(x * 0.37 + 900.0, z * 0.37 - 400.0) * 22.0 * smoothstep(6.0, 45.0, fl) * (1.0 - m)
			h += detail.get_noise_2d(x, z) * (0.5 + 9.0 * m)

			var rn := sqrt(x * x + z * z) / half * (1.0 + 0.08 * coast.get_noise_2d(x, z))
			var fall := smoothstep(0.80, 0.97, rn)
			h = lerpf(h, SEA_FLOOR, fall)
			heights[j * vn + i] = h

	_stamp_channel(Vector2(1500, 11500), Vector2(1400, 8300), -28.0, -14.0, 160.0, 110.0)
	_stamp_channel(Vector2(1400, 8300), Vector2(500, 5600), -14.0, -4.0, 110.0, 55.0)
	_stamp_channel(Vector2(9000, 8500), Vector2(8450, 6500), -20.0, -4.0, 180.0, 70.0)
	for lake in lakes:
		_stamp_lake(lake)
	for strip in strips:
		_stamp_strip(strip)
	_build_forest(seed_value)
	_build_ecology(seed_value)
	_place_docks()
	# Strips the player cut (builds.gd): not levelled, they lie on the ground as it is.
	for d in load("res://scripts/builds.gd").saved_strips():
		add_player_strip(d)

	tree_n = int(size / TREE_CELL)
	tree_h.resize(tree_n * tree_n)
	tree_h.fill(0)


func _index_range(lo: float, hi: float) -> Vector2i:
	var a := clampi(int(floor((lo + half) / CELL)), 0, n)
	var b := clampi(int(ceil((hi + half) / CELL)), 0, n)
	return Vector2i(a, b)


func _stamp_channel(a: Vector2, b: Vector2, bottom_a: float, bottom_b: float, hw_a: float, hw_b: float) -> void:
	var bank := 230.0
	var rx := _index_range(minf(a.x, b.x) - 400.0, maxf(a.x, b.x) + 400.0)
	var rz := _index_range(minf(a.y, b.y) - 400.0, maxf(a.y, b.y) + 400.0)
	var d := b - a
	var len2 := d.length_squared()
	var vn := n + 1
	for j in range(rz.x, rz.y + 1):
		var z := -half + j * CELL
		for i in range(rx.x, rx.y + 1):
			var x := -half + i * CELL
			var t := clampf(((x - a.x) * d.x + (z - a.y) * d.y) / len2, 0.0, 1.0)
			var px := a.x + d.x * t - x
			var pz := a.y + d.y * t - z
			var dist := sqrt(px * px + pz * pz)
			var hw := lerpf(hw_a, hw_b, t)
			if dist > hw + bank:
				continue
			var bottom := lerpf(bottom_a, bottom_b, t)
			var w := 1.0 - smoothstep(hw, hw + bank, dist)
			var idx := j * vn + i
			var h := heights[idx]
			heights[idx] = lerpf(h, minf(h, bottom), w)


func lake_radius(lake: Dictionary, angle: float) -> float:
	var s: float = lake["seed"]
	var r: float = lake["radius"]
	return r * (1.0 + 0.22 * sin(3.0 * angle + s) + 0.12 * sin(5.0 * angle + s * 2.3))


func _stamp_lake(lake: Dictionary) -> void:
	var c: Vector2 = lake["pos"]
	var level: float = lake["level"]
	var depth: float = lake["depth"]
	var rmax: float = lake["radius"] * 1.4 + 300.0
	var rx := _index_range(c.x - rmax, c.x + rmax)
	var rz := _index_range(c.y - rmax, c.y + rmax)
	var vn := n + 1
	for j in range(rz.x, rz.y + 1):
		var z := -half + j * CELL
		for i in range(rx.x, rx.y + 1):
			var x := -half + i * CELL
			var dx := x - c.x
			var dz := z - c.y
			var dist := sqrt(dx * dx + dz * dz)
			var rr := lake_radius(lake, atan2(dz, dx))
			var idx := j * vn + i
			var h := heights[idx]
			if dist < rr:
				var k := dist / rr
				var bed := level - 0.6 - depth * (1.0 - k * k)
				heights[idx] = minf(h, bed)
			elif dist < rr + 300.0:
				# Make sure the shore stands clear of the water and eases into the hills.
				var k2 := (dist - rr) / 300.0
				var shore := level + 0.5 + 2.5 * k2
				var w := 1.0 - smoothstep(0.0, 1.0, k2)
				heights[idx] = lerpf(h, maxf(shore, minf(h, shore + 30.0 * k2)), w)


func _stamp_strip(strip: Dictionary) -> void:
	var p: Vector3 = strip["pos"]
	var dir: Vector2 = strip["dir"]
	var hl: float = strip["length"] * 0.5 + 70.0
	var hw: float = strip["width"] * 0.5 + 38.0
	var slope: float = strip["slope"]
	var blend := 280.0
	var reach := hl + blend + 40.0
	var rx := _index_range(p.x - reach, p.x + reach)
	var rz := _index_range(p.z - reach, p.z + reach)
	var vn := n + 1
	for j in range(rz.x, rz.y + 1):
		var z := -half + j * CELL
		for i in range(rx.x, rx.y + 1):
			var x := -half + i * CELL
			var dx := x - p.x
			var dz := z - p.z
			var along := dx * dir.x + dz * dir.y
			var across := -dx * dir.y + dz * dir.x
			var ox := maxf(absf(along) - hl, 0.0)
			var oz := maxf(absf(across) - hw, 0.0)
			var dist := sqrt(ox * ox + oz * oz)
			if dist > blend:
				continue
			var w := 1.0 - smoothstep(0.0, blend, dist)
			var plane := p.y + slope * clampf(along, -hl, hl)
			var idx := j * vn + i
			heights[idx] = lerpf(heights[idx], plane, w)


func _build_forest(seed_value: int) -> void:
	var fnoise := FastNoiseLite.new()
	fnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnoise.seed = seed_value + 51
	fnoise.frequency = 1.0 / 950.0
	fnoise.fractal_type = FastNoiseLite.FRACTAL_FBM
	fnoise.fractal_octaves = 3
	var vn := n + 1
	for j in range(vn):
		var z := -half + j * CELL
		var jm := maxi(j - 1, 0)
		var jp := mini(j + 1, n)
		for i in range(vn):
			var x := -half + i * CELL
			var idx := j * vn + i
			var h := heights[idx]
			if h < 2.0 or h > 900.0:
				forest[idx] = 0.0
				continue
			var im := maxi(i - 1, 0)
			var ip := mini(i + 1, n)
			var sx := (heights[j * vn + ip] - heights[j * vn + im]) / (CELL * float(ip - im))
			var sz := (heights[jp * vn + i] - heights[jm * vn + i]) / (CELL * float(jp - jm))
			var steep := sqrt(sx * sx + sz * sz)
			var dens := smoothstep(0.38, 0.62, 0.5 + 0.5 * fnoise.get_noise_2d(x, z))
			# Trees climb higher on warm south-facing slopes than on cold north ones.
			var nz := -sz / sqrt(1.0 + sx * sx + sz * sz)
			var tl := Flora.treeline_from(x, z, nz)
			dens *= 1.0 - smoothstep(tl - 130.0, tl + 70.0, h)
			dens *= smoothstep(2.0, 7.0, h)
			dens *= 1.0 - smoothstep(0.45, 0.8, steep)
			forest[idx] = clampf(dens * 1.2, 0.0, 1.0)
	# Clearings: lakes, strips and the approach to each runway end.
	for lake in lakes:
		var c: Vector2 = lake["pos"]
		var level: float = lake["level"]
		var rmax: float = lake["radius"] * 1.4
		var rx := _index_range(c.x - rmax, c.x + rmax)
		var rz := _index_range(c.y - rmax, c.y + rmax)
		for j in range(rz.x, rz.y + 1):
			for i in range(rx.x, rx.y + 1):
				if heights[j * vn + i] < level + 0.4:
					forest[j * vn + i] = 0.0
	for strip in strips:
		var p: Vector3 = strip["pos"]
		var dir: Vector2 = strip["dir"]
		var hl: float = strip["length"] * 0.5
		var hw: float = strip["width"] * 0.5
		var reach := hl + 520.0
		var rx2 := _index_range(p.x - reach, p.x + reach)
		var rz2 := _index_range(p.z - reach, p.z + reach)
		for j in range(rz2.x, rz2.y + 1):
			var z := -half + j * CELL
			for i in range(rx2.x, rx2.y + 1):
				var x := -half + i * CELL
				var dx := x - p.x
				var dz := z - p.z
				var along := absf(dx * dir.x + dz * dir.y)
				var across := absf(-dx * dir.y + dz * dir.x)
				var idx := j * vn + i
				if along < hl + 90.0 and across < hw + 75.0:
					forest[idx] = 0.0
				elif along < hl + 480.0 and across < hw + 40.0 + (along - hl) * 0.12:
					forest[idx] = 0.0


## Ecology maps, worked out on a coarser 80 m grid and spread back over every
## vertex. Water runs downhill from each point to its steepest neighbour; where
## a lot of ground drains through one spot there is a creek. Flat ground that
## collects water but cannot shed it is muskeg. Old fires come in big patches,
## and skip the wet ground.
func _build_ecology(seed_value: int) -> void:
	var vn := n + 1
	creek.resize(vn * vn)
	bog.resize(vn * vn)
	burn.resize(vn * vn)
	var cn := n / 2 + 1
	var cc := cn * cn
	var hc := PackedFloat32Array()
	hc.resize(cc)
	for cj in range(cn):
		for ci in range(cn):
			hc[cj * cn + ci] = heights[(cj * 2) * vn + ci * 2]
	# Smooth away small dips in the noise so water keeps running.
	for _pass in range(3):
		var tmp := hc.duplicate()
		for cj in range(1, cn - 1):
			for ci in range(1, cn - 1):
				var k := cj * cn + ci
				hc[k] = (tmp[k] * 4.0 + tmp[k - 1] + tmp[k + 1] + tmp[k - cn] + tmp[k + cn]) / 8.0
	# Highest first, so each cell has gathered all its water before passing it on.
	var keys := PackedInt64Array()
	keys.resize(cc)
	for k in range(cc):
		keys[k] = (int(maxf(hc[k] + 200.0, 0.0) * 64.0) << 20) | k
	keys.sort()
	var acc := PackedFloat32Array()
	acc.resize(cc)
	acc.fill(1.0)
	var doff := PackedInt32Array([-cn - 1, -cn, -cn + 1, -1, 1, cn - 1, cn, cn + 1])
	var ddist := PackedFloat32Array([1.414, 1.0, 1.414, 1.0, 1.0, 1.414, 1.0, 1.414])
	for q in range(cc - 1, -1, -1):
		var k: int = keys[q] & 0xFFFFF
		var ci := k % cn
		var cj := k / cn
		if ci == 0 or cj == 0 or ci == cn - 1 or cj == cn - 1:
			continue
		var h := hc[k]
		if h < 0.5:
			continue
		var best := -1
		var best_s := 0.0
		for m in range(8):
			var nk := k + doff[m]
			var sl := (h - hc[nk]) / ddist[m]
			if sl > best_s:
				best_s = sl
				best = nk
		if best >= 0:
			acc[best] += acc[k]
	var bnoise := FastNoiseLite.new()
	bnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	bnoise.seed = seed_value + 71
	bnoise.frequency = 1.0 / 2100.0
	bnoise.fractal_type = FastNoiseLite.FRACTAL_FBM
	bnoise.fractal_octaves = 3
	var mnoise := FastNoiseLite.new()
	mnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mnoise.seed = seed_value + 83
	mnoise.frequency = 1.0 / 1300.0
	var cr := PackedFloat32Array()
	var bg := PackedFloat32Array()
	var bu := PackedFloat32Array()
	cr.resize(cc)
	bg.resize(cc)
	bu.resize(cc)
	var span := CELL * 2.0
	for cj in range(1, cn - 1):
		for ci in range(1, cn - 1):
			var k := cj * cn + ci
			var h := hc[k]
			var x := -half + ci * span
			var z := -half + cj * span
			if h < 1.0:
				continue
			var gx := (hc[k + 1] - hc[k - 1]) / (2.0 * span)
			var gz := (hc[k + cn] - hc[k - cn]) / (2.0 * span)
			var slope := sqrt(gx * gx + gz * gz)
			var la := log(acc[k])
			cr[k] = smoothstep(3.0, 5.8, la) * (1.0 - smoothstep(0.35, 0.7, slope))
			# Muskeg: flat lowland that gathers water. Patchy, never on slopes.
			var flat := 1.0 - smoothstep(0.012, 0.045, slope)
			var low := 1.0 - smoothstep(330.0, 520.0, h)
			var gather := smoothstep(0.5, 3.0, la + 1.5 * flat)
			var patchy := smoothstep(-0.25, 0.25, mnoise.get_noise_2d(x, z))
			bg[k] = clampf(flat * low * gather * (0.35 + 0.65 * patchy) * 1.3, 0.0, 1.0) * smoothstep(2.0, 6.0, h)
			# Old burns: big patches of dry forest country.
			var fire := smoothstep(0.30, 0.42, bnoise.get_noise_2d(x, z))
			bu[k] = fire * (1.0 - smoothstep(560.0, 720.0, h)) * (1.0 - 0.8 * bg[k]) * (1.0 - 0.6 * cr[k]) * smoothstep(4.0, 12.0, h)
	# Widen the creek lines a little so the willow and cottonwood make a band.
	var cr2 := cr.duplicate()
	for cj in range(1, cn - 1):
		for ci in range(1, cn - 1):
			var k := cj * cn + ci
			var nb := maxf(maxf(cr[k - 1], cr[k + 1]), maxf(cr[k - cn], cr[k + cn]))
			cr2[k] = maxf(cr[k], nb * 0.7)
	# Back to every vertex.
	for j in range(vn):
		var fj := float(j) * 0.5
		var cj0 := mini(int(fj), cn - 2)
		var tz := fj - float(cj0)
		for i in range(vn):
			var fi := float(i) * 0.5
			var ci0 := mini(int(fi), cn - 2)
			var tx := fi - float(ci0)
			var a := cj0 * cn + ci0
			var idx := j * vn + i
			creek[idx] = lerpf(lerpf(cr2[a], cr2[a + 1], tx), lerpf(cr2[a + cn], cr2[a + cn + 1], tx), tz)
			bog[idx] = lerpf(lerpf(bg[a], bg[a + 1], tx), lerpf(bg[a + cn], bg[a + cn + 1], tx), tz)
			burn[idx] = lerpf(lerpf(bu[a], bu[a + 1], tx), lerpf(bu[a + cn], bu[a + cn + 1], tx), tz)
			if forest[idx] > 0.0:
				# Muskeg carries only an open scatter of stunted spruce.
				forest[idx] *= 1.0 - 0.45 * bog[idx]


# ------------------------------------------------------------------------------
#  Queries
# ------------------------------------------------------------------------------
## Dig sites (dig_site.gd): fine diggable ground that replaces the island's
## surface inside their square.
var digs: Array = []


var dig_tiles := {}               # Vector2i(floor(x / 24), floor(z / 24)) -> dig site


func dig_at(x: float, z: float) -> Node:
	return dig_tiles.get(Vector2i(int(floor(x / 24.0)), int(floor(z / 24.0))))


func height_at(x: float, z: float) -> float:
	if not digs.is_empty():
		var d := dig_at(x, z)
		if d != null:
			return d.height(x, z)
	return height_at_base(x, z)


## The island's own ground, ignoring any digging.
func height_at_base(x: float, z: float) -> float:
	var fx := (x + half) / CELL
	var fz := (z + half) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= float(n) or fz >= float(n):
		return SEA_FLOOR
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var idx := j * (n + 1) + i
	var h00 := heights[idx]
	var h10 := heights[idx + 1]
	var h01 := heights[idx + n + 1]
	var h11 := heights[idx + n + 2]
	# Each cell is two triangles split along the h00-h11 diagonal, as in the mesh.
	if tx > tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


func normal_at(x: float, z: float) -> Vector3:
	if not digs.is_empty():
		var dg := dig_at(x, z)
		if dg != null:
			return dg.normal(x, z)
	var fx := (x + half) / CELL
	var fz := (z + half) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= float(n) or fz >= float(n):
		return Vector3.UP
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var idx := j * (n + 1) + i
	var h00 := heights[idx]
	var h10 := heights[idx + 1]
	var h01 := heights[idx + n + 1]
	var h11 := heights[idx + n + 2]
	var gx: float
	var gz: float
	if tx > tz:
		gx = (h10 - h00) / CELL
		gz = (h11 - h10) / CELL
	else:
		gx = (h11 - h01) / CELL
		gz = (h01 - h00) / CELL
	return Vector3(-gx, 1.0, -gz).normalized()


func forest_at(x: float, z: float) -> float:
	var i := clampi(int(round((x + half) / CELL)), 0, n)
	var j := clampi(int(round((z + half) / CELL)), 0, n)
	return forest[j * (n + 1) + i]


## Height of the water surface here, or NO_WATER when the ground is dry.
func water_level_at(x: float, z: float) -> float:
	return _water_level(x, z, height_at(x, z))


func _water_level(x: float, z: float, h: float) -> float:
	for lake in lakes:
		var c: Vector2 = lake["pos"]
		var dx := x - c.x
		var dz := z - c.y
		var reach: float = lake["radius"] * 1.6 + 40.0
		if dx * dx + dz * dz < reach * reach:
			var level: float = lake["level"]
			# Water only inside the shoreline that is drawn (world.gd _build_water),
			# so there is never water you cannot see.
			if h < level:
				var shore: float = lake_radius(lake, atan2(dz, dx)) * 1.12 + 40.0
				if dx * dx + dz * dz < shore * shore:
					return level
	if h < 0.0:
		return 0.0
	return NO_WATER


func snow_line() -> float:
	match season:
		0:
			return 1350.0
		1:
			return 850.0
		2:
			return -1000.0
		_:
			return 700.0


func lakes_frozen() -> bool:
	return season == 2


## Index of the strip whose runway contains this point, or -1.
## A bush strip the player laid out. Returns its index.
func add_player_strip(d: Dictionary) -> int:
	var hr := deg_to_rad(float(d["heading"]))
	var pos: Vector3 = d["pos"]
	strips.append({
		"name": String(d["name"]), "pos": pos, "heading": float(d["heading"]),
		"dir": Vector2(sin(hr), -cos(hr)),
		"length": float(d["length"]), "width": 14.0, "surface": SURF_GRASS, "slope": float(d.get("slope", 0.0)),
		"difficulty": 3, "fuel": false, "player": true,
		"desc": "Your own bush strip: rough grass, cut out of the bush.",
	})
	return strips.size() - 1


## The index of the n-th player strip, or -1.
func player_strip_index(nth: int) -> int:
	var c := 0
	for k in range(strips.size()):
		if bool(strips[k].get("player", false)):
			if c == nth:
				return k
			c += 1
	return -1


func strip_index_at(x: float, z: float, margin: float = 0.0) -> int:
	for k in range(strips.size()):
		var s: Dictionary = strips[k]
		var p: Vector3 = s["pos"]
		var dir: Vector2 = s["dir"]
		var dx := x - p.x
		var dz := z - p.z
		var hl: float = s["length"] * 0.5 + margin
		var hw: float = s["width"] * 0.5 + margin
		if absf(dx * dir.x + dz * dir.y) <= hl and absf(-dx * dir.y + dz * dir.x) <= hw:
			return k
	return -1


## Inside the cleared ground round a runway and under its approaches.
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
		if along < hl + 90.0 and across < hw + 75.0:
			return true
		if along < hl + 480.0 and across < hw + 40.0 + (along - hl) * 0.12:
			return true
	return false


## Mark a round patch (a building and its yard) where nothing may grow.
func clear_spot(x: float, z: float, radius: float) -> void:
	clearings.append(Vector3(x, z, radius))


## True on a runway (plus `margin` metres round it) or in a building's yard.
func is_cleared(x: float, z: float, margin: float = 0.0) -> bool:
	if strip_index_at(x, z, margin) >= 0:
		return true
	for c in clearings:
		var r := c.z + margin * 0.5
		if (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y) < r * r:
			return true
	return false


## (distance along the runway from its centre, distance right of the centreline)
func strip_local(k: int, x: float, z: float) -> Vector2:
	var s: Dictionary = strips[k]
	var p: Vector3 = s["pos"]
	var dir: Vector2 = s["dir"]
	var dx := x - p.x
	var dz := z - p.z
	return Vector2(dx * dir.x + dz * dir.y, -dx * dir.y + dz * dir.x)


## World position on the centreline, `along` metres from the centre toward the heading.
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


func surface_at(x: float, z: float) -> int:
	var h := height_at(x, z)
	var wl := _water_level(x, z, h)
	if wl > -1.0e8:
		if lakes_frozen() and wl > 1.0:
			return SURF_ICE
		return SURF_WATER
	var snowy := h > snow_line()
	var si := strip_index_at(x, z)
	if si >= 0:
		if snowy:
			return SURF_PACKED
		return int(strips[si]["surface"])
	if snowy:
		return SURF_SNOW
	return SURF_ROUGH


## Height of whatever a wheel would rest on: the ground, or the ice on a frozen lake.
## A solid box of building (a house, cabin or shed) the airframe can't pass.
func add_solid(xf: Transform3D, size: Vector3) -> void:
	solids.append({"xf": xf, "inv": xf.affine_inverse(), "size": size,
		"r": Vector2(size.x, size.z).length() * 0.5 + 1.0})


func add_hollow(xf: Transform3D, size: Vector3, door_w: float) -> void:
	hollows.append({"xf": xf, "inv": xf.affine_inverse(), "size": size, "door": door_w,
		"r": Vector2(size.x, size.z).length() * 0.5 + 1.0})


## Would a ground vehicle of girth `r` standing at `p` be inside a wall or a
## solid building? (The hollows' doorways are open; their insides are fine.)
func blocked_by_building(p: Vector3, r: float = 0.6) -> bool:
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


## The hollow building whose floor is under (x, z), or {}.
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


# ------------------------------------------------------------------------------
#  Trees (positions are derived from a hash so nothing but heights is stored)
# ------------------------------------------------------------------------------
static func hash01(i: int, j: int, k: int) -> float:
	var h: int = (i * 374761393 + j * 668265263 + k * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


func tree_position(ti: int, tj: int) -> Vector2:
	var jx := 0.15 + 0.7 * hash01(ti, tj, 1)
	var jz := 0.15 + 0.7 * hash01(ti, tj, 2)
	return Vector2(-half + (ti + jx) * TREE_CELL, -half + (tj + jz) * TREE_CELL)


## True when the point is inside a tree's crown.
func hits_tree(p: Vector3) -> bool:
	var t := tree_near(p)
	return not t.is_empty() and float(t["dist"]) < float(t["crown_r"])


## The tree whose trunk or crown is closest to `p` (see flora.gd), or {}.
func tree_near(p: Vector3) -> Dictionary:
	if not has_trees:
		return {}
	return Flora.tree_near(self, p)


# ------------------------------------------------------------------------------
#  Chart image for the map screen
# ------------------------------------------------------------------------------
func make_map_image() -> Image:
	var vn := n + 1
	var img := Image.create(vn, vn, false, Image.FORMAT_RGB8)
	var sl := snow_line()
	var frozen := lakes_frozen()
	for j in range(vn):
		var z := -half + j * CELL
		for i in range(vn):
			var x := -half + i * CELL
			var idx := j * vn + i
			var h := heights[idx]
			var col: Color
			var wl := _water_level(x, z, h)
			if wl > -1.0e8:
				if frozen and wl > 1.0:
					col = Color(0.86, 0.92, 0.96)
				else:
					col = Color(0.55, 0.70, 0.82).lerp(Color(0.40, 0.56, 0.74), clampf((wl - h) / 30.0, 0.0, 1.0))
			else:
				if h > sl:
					col = Color(0.95, 0.95, 0.93)
				elif h < 250.0:
					col = Color(0.80, 0.84, 0.66).lerp(Color(0.88, 0.84, 0.64), h / 250.0)
				elif h < 700.0:
					col = Color(0.88, 0.84, 0.64).lerp(Color(0.80, 0.68, 0.50), (h - 250.0) / 450.0)
				else:
					col = Color(0.80, 0.68, 0.50).lerp(Color(0.62, 0.52, 0.44), clampf((h - 700.0) / 900.0, 0.0, 1.0))
				col = col.lerp(Color(0.56, 0.70, 0.50), forest[idx] * 0.55)
				# Hill shading from the west-east slope.
				if i > 0 and i < n:
					var shade := clampf((heights[idx - 1] - heights[idx + 1]) / (CELL * 2.0), -0.6, 0.6)
					col = col.lightened(maxf(shade, 0.0) * 0.35).darkened(maxf(-shade, 0.0) * 0.45)
				# Contour lines every 150 m.
				if i < n and j < n:
					var band := floorf(h / 150.0)
					if floorf(heights[idx + 1] / 150.0) != band or floorf(heights[idx + vn] / 150.0) != band:
						col = col.darkened(0.22)
			img.set_pixel(i, j, col)
	return img


# ------------------------------------------------------------------------------
#  Seaplane docks
# ------------------------------------------------------------------------------
func _place_docks() -> void:
	docks.clear()
	# On a lake: the shore facing a given point (a lodge, a strip).
	_lake_dock("Moose Lake Dock", 0, Vector2(-250, 1050))
	_lake_dock("Loon Lake Dock", 1, Vector2(-8500, 900))
	# On the coast: the nearest open water to a village.
	_sea_dock("Tern Harbor Float Dock", Vector2(1400, -10200))
	_sea_dock("Port Ashby Float Dock", Vector2(2400, 8400))


func _lake_dock(name: String, li: int, toward: Vector2) -> void:
	var lake: Dictionary = lakes[li]
	var c: Vector2 = lake["pos"]
	var a := atan2(toward.y - c.y, toward.x - c.x)
	var dir := Vector2(cos(a), sin(a))
	var level: float = lake["level"]
	# Walk out from the middle until the ground comes up out of the water.
	var shore := c + dir * float(lake["radius"])
	for k in range(400):
		var p := c + dir * (float(k) * 4.0)
		if height_at(p.x, p.y) > level + 0.3:
			shore = p
			break
	_add_dock(name, li, shore, shore - dir * 26.0, level, -dir)


func _sea_dock(name: String, near: Vector2) -> void:
	var best := Vector2.INF
	var best_d := INF
	for k in range(72):
		var a := TAU * float(k) / 72.0
		var dir := Vector2(cos(a), sin(a))
		for r in range(10, 260):
			var p := near + dir * (float(r) * 6.0)
			if height_at(p.x, p.y) < -1.2:
				if float(r) * 6.0 < best_d:
					best_d = float(r) * 6.0
					best = p
				break
	if best == Vector2.INF:
		return
	var out := (best - near).normalized()
	# Back up to the water's edge.
	var shore := best
	for k in range(200):
		var p := best - out * float(k) * 2.0
		if height_at(p.x, p.y) > 0.3:
			shore = p
			break
	_add_dock(name, -1, shore, shore + out * 26.0, 0.0, out)


func _add_dock(name: String, li: int, shore: Vector2, water: Vector2, level: float, out: Vector2) -> void:
	docks.append({"name": name, "lake": li, "shore": shore, "water": water, "level": level,
		"heading": fposmod(rad_to_deg(atan2(out.x, -out.y)), 360.0), "out": out})
	clear_spot(shore.x - out.x * 10.0, shore.y - out.y * 10.0, 14.0)


