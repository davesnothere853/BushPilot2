extends "res://scripts/town_block.gd"
## The game's small town, 1982: designed, not traced. One main intersection on
## the valley floor with the real mountains round it (reference/hope terrain).
## Main Street runs east-west (z = 0), Cross Street north-south (x = 0); the
## light hangs over the corner. Local metres: x east, z south, y up.
## Every lot is its own function, built in the town kit (town_block.gd).

const FLAT_IN := 230.0          # flat valley floor round the town (x squeezed by FLAT_X)
const FLAT_OUT := 560.0         # back to the real ground by here
const FLAT_X := 1.6

var k_terrain := MeshKit.new()


func _ready() -> void:
	_rng.seed = 1982
	radius = 600.0
	main_names = ["Main Street", "Highway"]
	_terrain()
	_ground()
	_lay_roads()
	for r in _roads:
		_road(r)
	_lots()
	_home_strip()
	_street_furniture()
	_finish()
	_terrain_finish()
	set_meta("frame_aabb", AABB(Vector3(-140, 0, -90), Vector3(280, 20, 180)))


# ------------------------------------------------------------------------------
#  The valley, hand-made (Dave: not the real heights - those read too big and
#  plain). A flat floor running east-west with the town on it, a river winding
#  south of town, and steep forested mountains both sides: sharp ridges and
#  gullies (ridged noise), rock faces where it's steep, snow on the tops, and a
#  big peak standing at the south end of Cross Street (FILM_NOTES: the peak at
#  the end of the main street).
# ------------------------------------------------------------------------------
const TN := 220                  # grid points a side
const TSTEP := 90.0              # metres between them (~20 km square: the bigger map)
## Dave: same mountain heights, the map a lot bigger - every horizontal size of
## the mountains is stretched by MAP_S, so the slopes are gentler (a logging
## truck can climb the roads) and there's room for far more places.
const MAP_S := 2.5
const PEAKS := [[Vector2(150, 1850), 900.0, 900.0], [Vector2(-1500, 1400), 700.0, 800.0], [Vector2(-900, -1500), 760.0, 900.0],
	[Vector2(1300, -1350), 650.0, 800.0], [Vector2(2400, 900), 750.0, 900.0], [Vector2(-2600, -500), 600.0, 800.0]]

var _noise := FastNoiseLite.new()
var _noise2 := FastNoiseLite.new()
var _noise3 := FastNoiseLite.new()
## Creeks: down the gullies to the river (the north one under the highway, west of town).
const CREEKS := [[Vector2(-520, -1500), Vector2(-470, -900), Vector2(-390, -420), Vector2(-345, -120), Vector2(-330, 120), Vector2(-360, 300)],
	[Vector2(380, 1500), Vector2(300, 1100), Vector2(250, 700), Vector2(190, 420), Vector2(170, 290)],
	[Vector2(-1050, 1250), Vector2(-850, 900), Vector2(-720, 560), Vector2(-680, 330)],
	[Vector2(900, -1400), Vector2(820, -900), Vector2(700, -450), Vector2(620, -80), Vector2(600, 200), Vector2(560, 280)]]


func _terrain() -> void:
	_noise.seed = 1982
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise.fractal_octaves = 5
	_noise.frequency = 0.0009
	_noise2.seed = 7
	_noise2.frequency = 0.0004
	_noise2.fractal_octaves = 3
	_noise3.seed = 33
	_noise3.frequency = 0.006
	_noise3.fractal_octaves = 4


## The river's line (z at x): winding along the valley south of town.
static func river_z(x: float) -> float:
	return 330.0 + 90.0 * sin(x / 650.0) + 30.0 * sin(x / 240.0 + 1.0)


## Ground height at (x, z): the valley, then Harry's strip graded into it.
func terrain_y(x: float, z: float) -> float:
	var h := _natural_y(x, z)
	var lp := to_strip(x, z)
	var so := strip_out_l(lp.x, lp.y)
	if so < 25.0:
		h = lerpf(strip_y(lp.x), h, smoothstep(1.5, 25.0, so))
	return h


static func _rect_out(x: float, z: float, rr: Rect2) -> float:
	var dx := maxf(maxf(rr.position.x - x, x - rr.end.x), 0.0)
	var dz := maxf(maxf(rr.position.y - z, z - rr.end.y), 0.0)
	return Vector2(dx, dz).length()


## The valley as it lies (DESIGN_NOTES 226, Dave: a mountain town - no big
## flat plains, steep forested walls close behind town, knolls and benches).
func _natural_y(x: float, z: float) -> float:
	# the valley: a narrow floor bending a little, rounded forested walls
	# rising close beyond (Dave preferred these to the big Silverton peaks)
	var bend := 60.0 * MAP_S * sin(x / (900.0 * MAP_S))
	var dz := absf(z - bend - 170.0) / MAP_S       # (in mountain units) the floor holds the town and the river
	var wall := smoothstep(240.0, 1000.0, dz)
	var r := (_noise.get_noise_2d(x / MAP_S, z / MAP_S) * 0.5 + 0.5)          # ridges and gullies
	var big := _noise2.get_noise_2d(x / MAP_S, z / MAP_S) * 0.5 + 0.5
	var h := wall * (180.0 + 420.0 * big) + wall * wall * r * 220.0
	# the named peaks
	for pk in PEAKS:
		var c: Vector2 = pk[0]
		var d := Vector2(x / MAP_S, z / MAP_S).distance_to(c)
		var ph: float = pk[1]
		var pr: float = pk[2]
		h = maxf(h, ph * exp(-pow(d / pr, 1.6)) * (0.8 + 0.4 * r) * smoothstep(300.0, 800.0, dz))   # kept off the valley floor
	# the side valley up the creek north-west of town (like Silverton's
	# Mineral Creek): a U-shaped floor climbing ~7%, walls straight up beside
	var sv := _side_valley(x, z)
	if sv.x < 330.0:
		var floor_y: float = 4.0 + SV_GRADE * sv.y + 0.06 * maxf(sv.x - 20.0, 0.0)
		h = minf(h, lerpf(floor_y, h, smoothstep(SV_HALF, SV_HALF + 230.0, sv.x)))
	# low benches and bumps on the floor, kept off the town
	var floor_bump := 11.0 * big * smoothstep(FLAT_IN + 20.0, FLAT_IN + 200.0, Vector2(x / FLAT_X, z).length())
	h += floor_bump
	# the town floor: dead flat
	var d2 := Vector2(x / FLAT_X, z).length()
	h = lerpf(town_h(x, z) - 0.06, h, smoothstep(FLAT_IN, FLAT_IN + 150.0, d2))
	# rolling ground off the town floor: knolls, old channels, benches
	var fine := _noise3.get_noise_2d(x, z)
	h += fine * 9.0 * smoothstep(FLAT_IN + 30.0, FLAT_IN + 200.0, d2) * (1.0 - wall * 0.5)
	# the river: a wide braided gravel bed, shallow channels, sand and gravel bars
	var rd := absf(z - river_z(x))
	# a big river, ~300 m bank to bank; bars on the inside of the bends and mid-channel
	var inside := 0.5 + 0.5 * sin(x / 650.0) * signf(z - river_z(x))
	var bed := -3.6 + 2.6 * clampf(_noise3.get_noise_2d(x * 1.2, z * 2.5) + 0.05 + 0.35 * inside * smoothstep(60.0, 140.0, rd), 0.0, 1.0)
	h = minf(h, lerpf(bed, h, smoothstep(140.0, 190.0, rd)))
	# the long gravel bar the bush planes land on: flat, firm, clear of rocks
	var gb := _on_bar(x, z)
	if gb < 1.0:
		h = lerpf(-1.25 + 0.15 * sin(x * 0.01), h, smoothstep(0.75, 1.0, gb))
	# the creeks off the mountains, each in its gully
	for cr in CREEKS:
		var cd := _dist_poly(Vector2(x, z), cr)
		if cd < 40.0:
			h = minf(h, lerpf(h - 2.2, h, smoothstep(3.5, 30.0, cd)))
	return h


## The landing bar: 0 on its centreline .. 1 at its edge (beyond 1 is off it).
const BAR_X := Vector2(480.0, 980.0)
const BAR_HALF := 24.0


func _on_bar(x: float, z: float) -> float:
	if x < BAR_X.x - 40.0 or x > BAR_X.y + 40.0:
		return 9.0
	var along := maxf(BAR_X.x - x, x - BAR_X.y)
	var across := absf(z - river_z(x) - 8.0) / BAR_HALF
	return maxf(across, 1.0 + along / 40.0 if along > 0.0 else across)


func _dist_poly(p: Vector2, pts: Array) -> float:
	var best := 1e9
	for i in range(pts.size() - 1):
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return best


const NEAR := Rect2(-1100, -420, 1860, 1100)     # the fine ground round town (creeks, bars, banks)
const NEAR_STEP := 5.0
const SV_NEAR := Rect2(-640.0, -940.0, 380.0, 524.0)


func _terrain_finish() -> void:
	var x0 := -TSTEP * (TN - 1) * 0.5
	var z0 := -TSTEP * (TN - 1) * 0.5 + 300.0
	_grid_mesh("Valley", x0, z0, TN, TN, TSTEP, true)
	var nx := int(NEAR.size.x / NEAR_STEP) + 1
	var nz := int(NEAR.size.y / NEAR_STEP) + 1
	_grid_mesh("ValleyNear", NEAR.position.x, NEAR.position.y, nx, nz, NEAR_STEP, false)
	# the side valley up to Harry's strip, fine enough for the runway and road
	_grid_mesh("SideValleyNear", SV_NEAR.position.x, SV_NEAR.position.y, int(SV_NEAR.size.x / 4.0) + 1, int(SV_NEAR.size.y / 4.0) + 1, 4.0, false)
	var w := MeshInstance3D.new()
	w.name = "River"
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	w.mesh = pm
	w.position = Vector3(0, -2.0, 300)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.20, 0.27, 0.27)
	wm.roughness = 0.05
	wm.metallic = 0.3
	w.material_override = wm
	add_child(w)
	_creek_water()
	_rocks()
	_forest()
	_autumn_trees()


## A height grid as one mesh; the far one sinks a little under the fine near one.
func _grid_mesh(nm: String, x0: float, z0: float, nx: int, nz: int, step: float, far: bool) -> void:
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	for j in range(nz):
		for i in range(nx):
			hs[j * nx + i] = terrain_y(x0 + i * step, z0 + j * step)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := NEAR.grow(-TSTEP * 1.5)
	var inner2 := SV_NEAR.grow(-TSTEP * 1.5)
	for j in range(nz):
		for i in range(nx):
			var x := x0 + i * step
			var z := z0 + j * step
			var y := hs[j * nx + i]
			var yx := hs[j * nx + mini(i + 1, nx - 1)]
			var yz := hs[mini(j + 1, nz - 1) * nx + i]
			var slope := Vector2(yx - y, yz - y).length() / step
			st.set_color(_ground_col(x, y, z, slope))
			if far and (inner.has_point(Vector2(x, z)) or inner2.has_point(Vector2(x, z))):
				y -= 6.0
			st.set_uv(Vector2(x, z) * 0.05)
			st.add_vertex(Vector3(x, y, z))
	for j in range(nz - 1):
		for i in range(nx - 1):
			var a := j * nx + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + nx)
			st.add_index(a + 1)
			st.add_index(a + nx + 1)
			st.add_index(a + nx)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = st.commit()
	mi.material_override = _mat("grass", 0.08 if far else 0.25, 1.0)
	add_child(mi)


func _ground_col(x: float, y: float, z: float, slope: float) -> Color:
	var n := _noise.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5
	var c := Color(0.34, 0.40, 0.21).lerp(Color(0.42, 0.42, 0.25), n)
	if y > 3.0 and Vector2(x / FLAT_X, z).length() > FLAT_IN + 30.0:
		c = Color(0.09, 0.17, 0.10).lerp(Color(0.16, 0.25, 0.13), n)
	if y > 680.0:      # above timberline: tundra, then rock stained red and orange (San Juan iron)
		var tun := Color(0.42, 0.40, 0.26).lerp(Color(0.50, 0.44, 0.30), n)
		c = c.lerp(tun, clampf((y - 680.0) / 80.0, 0.0, 1.0))
		var iron := clampf(_noise2.get_noise_2d(x * 4.0, z * 4.0) * 1.6, 0.0, 1.0) * clampf((y - 760.0) / 120.0, 0.0, 1.0)
		c = c.lerp(Color(0.55, 0.30, 0.18).lerp(Color(0.66, 0.46, 0.24), n), iron * 0.8)
	var rocky := _noise3.get_noise_2d(x * 0.7, z * 0.7) * 0.35
	if slope > 1.15 + rocky or (y > 900.0 and slope > 0.7 + rocky):
		c = c.lerp(Color(0.30, 0.29, 0.27).lerp(Color(0.19, 0.19, 0.18), n), clampf((slope - 0.9 - rocky) * 3.0, 0.4, 1.0))
	if y > 1000.0:
		var snow := clampf((y - 1000.0 - n * 150.0) / 120.0, 0.0, 1.0) * (1.0 - clampf((slope - 1.1) * 2.0, 0.0, 0.7))
		c = c.lerp(Color(0.93, 0.94, 0.96), snow)
	if absf(z - river_z(x)) < 195.0 and y < 1.5:
		c = Color(0.80, 0.75, 0.62).lerp(Color(0.66, 0.62, 0.53), clampf(n * 1.4 - 0.2, 0.0, 1.0))   # pale sand bars
	elif slope > 0.25 and y < 3.0 and y > -1.5:
		c = c.lerp(Color(0.36, 0.30, 0.22), 0.5)                  # cut banks
	if _on_bar(x, z) < 1.0:
		c = Color(0.55, 0.53, 0.49).lerp(Color(0.50, 0.48, 0.44), n)    # the landing bar: packed gravel
	for cr in CREEKS:
		if _dist_poly(Vector2(x, z), cr) < 6.0:
			c = Color(0.42, 0.40, 0.36)                            # creek gravel
	return c


## Water running down each creek: a ribbon just above its bed, in short steps.
func _creek_water() -> void:
	var k := MeshKit.new()
	for cr in CREEKS:
		for i in range(cr.size() - 1):
			var a: Vector2 = cr[i]
			var b: Vector2 = cr[i + 1]
			var L := a.distance_to(b)
			var t := (b - a) / L
			var nrm := Vector2(-t.y, t.x)
			var steps := int(L / 4.0)
			for sgi in range(steps):
				var p0 := a + t * (L * sgi / steps)
				var p1 := a + t * (L * (sgi + 1) / steps)
				var w0 := 2.2 + 0.6 * sin(float(sgi) * 0.7)
				var w1 := 2.2 + 0.6 * sin(float(sgi + 1) * 0.7)
				var y0 := terrain_y(p0.x, p0.y) + 0.35
				var y1 := terrain_y(p1.x, p1.y) + 0.35
				if y0 < -2.2 and y1 < -2.2:
					continue
				k.quad(Vector3(p0.x + nrm.x * w0, y0, p0.y + nrm.y * w0), Vector3(p1.x + nrm.x * w1, y1, p1.y + nrm.y * w1),
					Vector3(p1.x - nrm.x * w1, y1, p1.y - nrm.y * w1), Vector3(p0.x - nrm.x * w0, y0, p0.y - nrm.y * w0), Color(0.55, 0.62, 0.62), Vector3.UP)
	var wm := StandardMaterial3D.new()
	wm.vertex_color_use_as_albedo = true
	wm.albedo_color = Color(0.45, 0.55, 0.55)
	wm.roughness = 0.04
	wm.metallic = 0.3
	_add(k, "Creeks", wm, false)


## Rocks: boulders down the creeks and on the river banks, outcrops and cliffs
## on the steep ground, a scatter through the forest and round the town's edge.
func _rocks() -> void:
	var meshes: Array = []
	for v in range(4):
		meshes.append(_rock_mesh(v))
	var lists: Array = [[], [], [], []]
	var add := func(p: Vector3, size: float) -> void:
		if strip_out(p.x, p.z) < 6.0 or _dist_poly(Vector2(p.x, p.z), STRIP_ROAD) < 4.0:
			return                     # Harry keeps his strip and road picked clear
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.3, 0.3))
		var sc := Vector3(size * _rng.randf_range(0.8, 1.3), size * _rng.randf_range(0.45, 0.85), size * _rng.randf_range(0.8, 1.2))
		lists[_rng.randi() % 4].append(Transform3D(b.scaled(sc), p - Vector3(0, size * 0.18, 0)))
	# creeks: boulders in and beside the water
	for cr in CREEKS:
		for i in range(cr.size() - 1):
			var a: Vector2 = cr[i]
			var b2: Vector2 = cr[i + 1]
			var L := a.distance_to(b2)
			for k in range(int(L / 5.0)):
				var p := a.lerp(b2, _rng.randf()) + Vector2(_rng.randf_range(-9, 9), _rng.randf_range(-9, 9))
				add.call(Vector3(p.x, terrain_y(p.x, p.y), p.y), _rng.randf_range(0.6, 3.5))
	# river banks and bars
	for k2 in range(700):
		var x := _rng.randf_range(-2000, 2000)
		var z := river_z(x) + _rng.randf_range(-200, 200)
		var y := terrain_y(x, z)
		if y > -2.6 and _on_bar(x, z) > 1.2:
			add.call(Vector3(x, y, z), _rng.randf_range(0.3, 2.0) * (2.0 if _rng.randf() < 0.08 else 1.0))
	# the slopes: outcrops on steep ground, boulders in the forest
	var tries := 0
	var n_out := 0
	while n_out < 2600 and tries < 40000:
		tries += 1
		var x2 := _rng.randf_range(-3500, 3500) * MAP_S
		var z2 := _rng.randf_range(-3300, 3900) * MAP_S
		if Vector2(x2 / FLAT_X, z2).length() < FLAT_IN + 30.0:
			continue
		var y2 := terrain_y(x2, z2)
		if y2 < 0.0:
			continue
		var sl := Vector2(terrain_y(x2 + 10, z2) - y2, terrain_y(x2, z2 + 10) - y2).length() / 10.0
		if sl > 0.9:
			add.call(Vector3(x2, y2, z2), _rng.randf_range(8.0, 30.0))          # an outcrop / cliff band
		elif _rng.randf() < 0.5:
			add.call(Vector3(x2, y2, z2), _rng.randf_range(0.6, 3.5))
		else:
			continue
		n_out += 1
	# the town's edge: a few big glacial erratics and field stones
	for k3 in range(500):
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(FLAT_IN * 0.9, FLAT_IN + 200.0)
		var x3 := cos(ang) * r * FLAT_X
		var z3 := sin(ang) * r
		if _road_clear(Vector2(x3, z3), -1) < 6.0:
			continue
		add.call(Vector3(x3, terrain_y(x3, z3), z3), _rng.randf_range(0.6, 5.0) * (2.0 if _rng.randf() < 0.1 else 1.0))
	var rm := _mat("concrete", 0.35, 0.95)
	for v2 in range(4):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[v2]
		var l: Array = lists[v2]
		mm.instance_count = l.size()
		for i2 in range(l.size()):
			mm.set_instance_transform(i2, l[i2])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Rocks%d" % v2
		mmi.multimesh = mm
		mmi.material_override = rm
		add_child(mmi)


## One rock: a lumpy, faceted ball with flattish faces and a mossy top.
func _rock_mesh(v: int) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 7
	var arr := sm.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nz := FastNoiseLite.new()
	nz.seed = 100 + v
	nz.frequency = 1.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var moved := PackedVector3Array()
	moved.resize(vs.size())
	for i in range(vs.size()):
		var p := vs[i]
		var d := p.normalized()
		var r := 0.5 * (1.0 + 0.35 * nz.get_noise_3dv(d * 2.0) + 0.12 * nz.get_noise_3dv(d * 6.0))
		# planed facets: snap the radius in steps on some sides
		r = lerpf(r, snappedf(r, 0.07), 0.6)
		var q := d * r
		if q.y < -0.1:
			q.y = -0.1 + (q.y + 0.1) * 0.3              # a flat-ish bottom bedded in the ground
		moved[i] = q
	for i in range(0, idx.size(), 3):
		for k in [0, 2, 1]:
			var q2: Vector3 = moved[idx[i + k]]
			var top := clampf(q2.normalized().y, 0.0, 1.0)
			var g := 0.42 + 0.12 * nz.get_noise_3dv(q2 * 9.0)
			var c := Color(g, g * 0.98, g * 0.94).lerp(Color(0.24, 0.32, 0.14), smoothstep(0.55, 0.9, top) * 0.75)
			st.set_color(c)
			st.add_vertex(q2)
	st.generate_normals()
	return st.commit()


## Firs and cedars up the valley sides: a MultiMesh of simple trees for now.
## Fall colour through the dark firs: cottonwoods and maples in gold and orange,
## thick along the river and the creeks, scattered up the lower slopes.
func _autumn_trees() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sph := SphereMesh.new()
	sph.radius = 3.2
	sph.height = 6.0
	sph.radial_segments = 8
	sph.rings = 4
	mm.mesh = sph
	var pts: Array = []
	var tries := 0
	while pts.size() < 9000 and tries < 90000:
		tries += 1
		var x := _rng.randf_range(-3800, 3800) * MAP_S
		var z := _rng.randf_range(-3300, 4100) * MAP_S
		if Vector2(x / FLAT_X, z).length() < FLAT_IN + 50.0:
			continue
		var y := terrain_y(x, z)
		var rd := absf(z - river_z(x))
		var near_water := rd > 185.0 and rd < 320.0
		for cr in CREEKS:
			if _dist_poly(Vector2(x, z), cr) < 45.0 and _dist_poly(Vector2(x, z), cr) > 6.0:
				near_water = true
		if y < 0.3 or y > 450.0:
			continue
		if strip_out(x, z) < 9.0 or _dist_poly(Vector2(x, z), STRIP_ROAD) < 5.0:
			continue
		if not near_water and _rng.randf() < 0.75 + y / 600.0:
			continue
		pts.append(Vector3(x, y, z))
	mm.instance_count = pts.size()
	var cols := [Color(0.85, 0.66, 0.12), Color(0.92, 0.75, 0.16), Color(0.78, 0.48, 0.10), Color(0.62, 0.58, 0.16), Color(0.40, 0.42, 0.14), Color(0.75, 0.30, 0.08)]
	for i in range(pts.size()):
		var p: Vector3 = pts[i]
		var s := _rng.randf_range(0.7, 1.5)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(1.0, 1.6), s)), p + Vector3(0, 5.5 * s, 0)))
		mm.set_instance_color(i, cols[_rng.randi() % cols.size()].darkened(_rng.randf() * 0.2))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "FallTrees"
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mmi.material_override = m
	add_child(mmi)


func _forest() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 3.0
	cone.height = 19.0
	cone.radial_segments = 7
	cone.rings = 2
	mm.mesh = cone
	var pts: Array = []
	var tries := 0
	while pts.size() < 90000 and tries < 300000:
		tries += 1
		var x := _rng.randf_range(-3800, 3800) * MAP_S
		var z := _rng.randf_range(-3500, 4100) * MAP_S
		if Vector2(x / FLAT_X, z).length() < FLAT_IN + 60.0:
			continue
		var y := terrain_y(x, z)
		if y < 0.5 or y > 690.0 + 40.0 * _rng.randf():      # timberline
			continue
		var sl := Vector2(terrain_y(x + 15, z) - y, terrain_y(x, z + 15) - y).length() / 15.0
		if sl > 1.25:
			continue
		if absf(z - river_z(x)) < 200.0:
			continue
		if strip_out(x, z) < 9.0 or _dist_poly(Vector2(x, z), STRIP_ROAD) < 5.0:
			continue                      # the strip's cleared to the edges, the road's cut through
		if y < 4.0 and _rng.randf() < 0.85:
			continue
		pts.append(Vector3(x, y, z))
	mm.instance_count = pts.size()
	for i in range(pts.size()):
		var p: Vector3 = pts[i]
		var s := _rng.randf_range(0.7, 1.5)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s * _rng.randf_range(0.9, 1.4), s)), p + Vector3(0, 7.0 * s, 0)))
		mm.set_instance_color(i, Color(0.08, 0.17, 0.10).lerp(Color(0.15, 0.25, 0.13), _rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Forest"
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mmi.material_override = m
	add_child(mmi)


func _ground() -> void:
	# the town's lawns and lots: grass over the town's ground (it rolls: town_h)
	var n := 60
	for i in range(n):
		for j in range(n):
			var x0 := -300.0 + 600.0 * i / n
			var x1 := -300.0 + 600.0 * (i + 1) / n
			var z0 := -190.0 + 380.0 * j / n
			var z1 := -190.0 + 380.0 * (j + 1) / n
			var g := Color(0.34, 0.40, 0.21).lerp(Color(0.42, 0.42, 0.26), _rng.randf())
			k_grass.quad(Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1), g, Vector3.UP)


# ------------------------------------------------------------------------------
#  Roads: Main Street, the highway each way, Cross Street, two back roads
# ------------------------------------------------------------------------------
func _lay_roads() -> void:
	_add_road([Vector2(-170, 0), Vector2(170, 0)], 14.0, "primary", "Main Street", true)
	_add_road([Vector2(-420, 0), Vector2(-170, 0)], 9.0, "primary", "Highway", false)
	_add_road([Vector2(170, 0), Vector2(420, 0)], 9.0, "primary", "Highway", false)
	_add_road([Vector2(0, -116), Vector2(0, 116)], 10.0, "tertiary", "Cross Street", true)
	_add_road([Vector2(-100, -116), Vector2(100, -116)], 8.0, "residential", "Park Road", true)
	_add_road([Vector2(-100, 116), Vector2(100, 116)], 8.0, "residential", "River Road", true)


func _add_road(pts: Array, w: float, kind: String, nm: String, walks: bool) -> void:
	var pa := PackedVector2Array()
	for p in pts:
		pa.append(p)
	_roads.append({"pts": pa, "w": w, "kind": kind, "name": nm, "walks": walks})


# ------------------------------------------------------------------------------
#  The town on its hillside (Dave: a town in the mountains, not flat): the
#  ground climbs toward the mountain to the north, rolls, a knoll east of
#  Cross Street. Everything built flat is set onto it at the end: each
#  building on its own level base (its foundation run down to the ground on
#  the low side, the high side cut into the hill), roads, walks, lawns and
#  street things following the ground.
# ------------------------------------------------------------------------------
func town_h(x: float, z: float) -> float:
	var north := clampf((120.0 - z) / 270.0, 0.0, 1.0)            # 0 by the river .. 1 at the back of town
	var h := 12.0 * north * north * (3.0 - 2.0 * north)
	h += 1.0 * sin(x / 70.0 + 0.6) * cos(z / 90.0)                  # small rolls (Silverton: a gentle fan sloping up to the mountain)
	h += 3.0 * exp(-(pow(x - 115.0, 2.0) + pow(z + 60.0, 2.0)) / (2.0 * 45.0 * 45.0))   # the knoll east of Cross Street
	h -= 2.5 * exp(-(pow(x + 120.0, 2.0) + pow(z - 70.0, 2.0)) / (2.0 * 60.0 * 60.0))   # a dip toward the river, west
	return h


var _hg := PackedFloat32Array()
const HG0 := Vector2(-470.0, -330.0)
const HG_STEP := 2.0
const HG_N := Vector2i(471, 296)


func _ground_at(x: float, z: float) -> float:
	var fx := (x - HG0.x) / HG_STEP
	var fz := (z - HG0.y) / HG_STEP
	if fx < 0.0 or fz < 0.0 or fx >= HG_N.x - 1 or fz >= HG_N.y - 1:
		return terrain_y(x, z)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var a := _hg[j * HG_N.x + i]
	var b := _hg[j * HG_N.x + i + 1]
	var c := _hg[(j + 1) * HG_N.x + i]
	var d := _hg[(j + 1) * HG_N.x + i + 1]
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


var _bpolys: Array = []
var _bbase: PackedFloat32Array = PackedFloat32Array()
var _bgrid := {}            # Vector2i(10 m cell) -> [building indices]


func _setup_slope() -> void:
	_hg.resize(HG_N.x * HG_N.y)
	for j in range(HG_N.y):
		for i in range(HG_N.x):
			_hg[j * HG_N.x + i] = terrain_y(HG0.x + i * HG_STEP, HG0.y + j * HG_STEP) + 0.06
	_bpolys = get_meta("_bldg_real", [])
	_bbase.resize(_bpolys.size())
	for bi in range(_bpolys.size()):
		var poly: PackedVector2Array = _bpolys[bi]
		var cen := Vector2.ZERO
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for q in poly:
			cen += q
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		cen /= float(poly.size())
		_bbase[bi] = _ground_at(cen.x, cen.y)
		for cx in range(int(floor((lo.x - 2.0) / 10.0)), int(floor((hi.x + 2.0) / 10.0)) + 1):
			for cz in range(int(floor((lo.y - 2.0) / 10.0)), int(floor((hi.y + 2.0) / 10.0)) + 1):
				var key := Vector2i(cx, cz)
				if not _bgrid.has(key):
					_bgrid[key] = []
				(_bgrid[key] as Array).append(bi)


## The building this point belongs to (inside its footprint or within 1.6 m
## of a wall: its trim, sign, awning, steps), or -1.
func _bldg_at(x: float, z: float) -> int:
	var key := Vector2i(int(floor(x / 10.0)), int(floor(z / 10.0)))
	if not _bgrid.has(key):
		return -1
	var p := Vector2(x, z)
	for bi in _bgrid[key]:
		var poly: PackedVector2Array = _bpolys[bi]
		if Geometry2D.is_point_in_polygon(p, poly):
			return bi
		for k in range(poly.size()):
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[k], poly[(k + 1) % poly.size()])) < 1.6:
				return bi
	return -1


## Set a kit's flat-built triangles onto the town's ground.
func _slope_kit(k: MeshKit) -> void:
	if k.is_empty():
		return
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nc := PackedColorArray()
	var vs := k.verts
	var ns := k.norms
	var cs := k.cols
	for t in range(0, vs.size(), 3):
		var a := vs[t]
		var b := vs[t + 1]
		var c := vs[t + 2]
		var cen := (a + b + c) / 3.0
		var bi := _bldg_at(cen.x, cen.z)
		if bi >= 0:
			var base: float = _bbase[bi]
			for q in [[a, ns[t], cs[t]], [b, ns[t + 1], cs[t + 1]], [c, ns[t + 2], cs[t + 2]]]:
				var v: Vector3 = q[0]
				if v.y <= 0.02:
					v.y = minf(_ground_at(v.x, v.z) - 0.25, base)      # the foundation down to the ground
				else:
					v.y += base
				nv.append(v)
				nn.append(q[1])
				nc.append(q[2])
		else:
			_slope_tri(a, b, c, ns[t], ns[t + 1], ns[t + 2], cs[t], cs[t + 1], cs[t + 2], nv, nn, nc, 0)
	k.verts = nv
	k.norms = nn
	k.cols = nc


func _slope_tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc_: Vector3, ca: Color, cb: Color, cc: Color, nv: PackedVector3Array, nn: PackedVector3Array, ncs: PackedColorArray, depth: int) -> void:
	var lab := Vector2(a.x - b.x, a.z - b.z).length()
	var lbc := Vector2(b.x - c.x, b.z - c.z).length()
	var lca := Vector2(c.x - a.x, c.z - a.z).length()
	if maxf(lab, maxf(lbc, lca)) > 7.0 and depth < 9:
		# split the longest edge (keeps long strips from going thin and wavy)
		if lab >= lbc and lab >= lca:
			var m := (a + b) * 0.5
			var nm := (na + nb).normalized()
			var cm := ca.lerp(cb, 0.5)
			_slope_tri(a, m, c, na, nm, nc_, ca, cm, cc, nv, nn, ncs, depth + 1)
			_slope_tri(m, b, c, nm, nb, nc_, cm, cb, cc, nv, nn, ncs, depth + 1)
		elif lbc >= lca:
			var m2 := (b + c) * 0.5
			var nm2 := (nb + nc_).normalized()
			var cm2 := cb.lerp(cc, 0.5)
			_slope_tri(a, b, m2, na, nb, nm2, ca, cb, cm2, nv, nn, ncs, depth + 1)
			_slope_tri(a, m2, c, na, nm2, nc_, ca, cm2, cc, nv, nn, ncs, depth + 1)
		else:
			var m3 := (c + a) * 0.5
			var nm3 := (nc_ + na).normalized()
			var cm3 := cc.lerp(ca, 0.5)
			_slope_tri(a, b, m3, na, nb, nm3, ca, cb, cm3, nv, nn, ncs, depth + 1)
			_slope_tri(m3, b, c, nm3, nb, nc_, cm3, cb, cc, nv, nn, ncs, depth + 1)
		return
	for q in [[a, na, ca], [b, nb, cb], [c, nc_, cc]]:
		var v: Vector3 = q[0]
		v.y += _ground_at(v.x, v.z)
		nv.append(v)
		nn.append(q[1])
		ncs.append(q[2])


func _finish() -> void:
	_setup_slope()
	for k in [k_grass, k_asphalt, k_concrete, k_paint, k_siding, k_brick, k_trim, k_roof, k_metal, k_wood, k_glass, k_leaf]:
		_slope_kit(k)
	# loose nodes built flat (labels, lights, signs...): up onto the ground or their building
	for ch in get_children():
		if ch is Node3D and ch.name != "HarrysBushAir":
			var n3 := ch as Node3D
			var bi := _bldg_at(n3.position.x, n3.position.z)
			n3.position.y += _bbase[bi] if bi >= 0 else _ground_at(n3.position.x, n3.position.z)
	super._finish()


# ------------------------------------------------------------------------------
#  Harry's Bush Air (DESIGN_NOTES 226): his strip just west of town, north of
#  the highway; the ground's flattened under it (terrain_y)
# ------------------------------------------------------------------------------
## The side valley: up the creek from where it leaves the park (world x, z).
const SIDE_VALLEY := [Vector2(-345, -120), Vector2(-390, -420), Vector2(-470, -900), Vector2(-520, -1500)]
const SV_GRADE := 0.07
const SV_HALF := 95.0


## (distance across from the creek, distance along it from the mouth).
func _side_valley(x: float, z: float) -> Vector2:
	var p := Vector2(x, z)
	var best := 1e9
	var along := 0.0
	var acc := 0.0
	for i in range(SIDE_VALLEY.size() - 1):
		var a: Vector2 = SIDE_VALLEY[i]
		var b: Vector2 = SIDE_VALLEY[i + 1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(q)
		if d < best:
			best = d
			along = acc + a.distance_to(q)
		acc += a.distance_to(b)
	return Vector2(best, along)


## Harry's strip up the side valley: the hangar at the low end on the west
## side of the floor, the runway up-valley beside the creek (local -x points
## up the valley; the hangar door faces the runway, local -z = east).
const STRIP_AT := Vector3(-454.0, 0.0, -440.0)     # the hangar door's middle
const STRIP_YAW := -1.406                           # local +x = down the valley (south)
const STRIP_RWY_X := -210.0                         # the runway: 20 .. 400 m up-valley from the hangar
const STRIP_RWY_Z := -30.0                          # its centreline, 30 m east of the hangar
## The road up: off the west end of the highway, switchbacks up the mountain
## to the bench (world x, z), staying west of the creek.
const STRIP_ROAD := [Vector2(-418, -3), Vector2(-392, -60), Vector2(-382, -140), Vector2(-388, -220), Vector2(-404, -300), Vector2(-428, -372), Vector2(-440, -418), Vector2(-437, -440)]
const STRIP_RWY_L := 380.0
const STRIP_GRADE := 0.07                           # it climbs up-valley: land uphill, take off down
## The graded ground in the strip's own frame (local x, z).
const STRIP_FLAT := [Rect2(-412.0, -41.0, 404.0, 22.0), Rect2(-16.0, -22.0, 32.0, 34.0), Rect2(-10.0, -31.0, 20.0, 12.0)]
var _strip_base := INF


## World (x, z) -> the strip's local (x, z).
static func to_strip(x: float, z: float) -> Vector2:
	var d := Vector2(x - STRIP_AT.x, z - STRIP_AT.z)
	var ax := Vector2(cos(STRIP_YAW), -sin(STRIP_YAW))       # local +x in the world
	var az := Vector2(sin(STRIP_YAW), cos(STRIP_YAW))        # local +z in the world
	return Vector2(d.dot(ax), d.dot(az))


static func from_strip(lx: float, lz: float) -> Vector2:
	var ax := Vector2(cos(STRIP_YAW), -sin(STRIP_YAW))
	var az := Vector2(sin(STRIP_YAW), cos(STRIP_YAW))
	return Vector2(STRIP_AT.x, STRIP_AT.z) + ax * lx + az * lz


## The graded surface of the strip and the hangar pad: one plane, climbing
## up-valley (local -x).
func strip_y(lx: float) -> float:
	if _strip_base == INF:
		var acc := 0.0
		for i in range(9):
			var sx := STRIP_RWY_X - STRIP_RWY_L * 0.5 + STRIP_RWY_L * float(i) / 8.0
			var w := from_strip(sx, STRIP_RWY_Z)
			acc += _natural_y(w.x, w.y) - STRIP_GRADE * (-sx)
		_strip_base = acc / 9.0 + 0.5
	return _strip_base + STRIP_GRADE * (-lx)


func _home_strip() -> void:
	var hs: Node3D = load("res://scripts/home_strip.gd").new()
	hs.name = "HarrysBushAir"
	hs.in_town = true
	hs.rwy_x = STRIP_RWY_X
	hs.rwy_z = STRIP_RWY_Z
	hs.rwy_l = STRIP_RWY_L
	var base := strip_y(STRIP_AT.x)
	hs.position = Vector3(STRIP_AT.x, base - 0.04, STRIP_AT.z)
	hs.ground = func(lx: float, lz: float) -> float: return terrain_y(STRIP_AT.x + lx, STRIP_AT.z + lz) - base + 0.04
	var rp: Array = []
	for q in STRIP_ROAD:
		rp.append(Vector2(q.x - STRIP_AT.x, q.y - STRIP_AT.z))
	hs.road_pts = rp
	add_child(hs)
	for r in STRIP_FLAT:
		_keep(rect(r.position.x, r.end.x, r.position.y, r.end.y))


## 0 inside the strip's flat ground, metres outside it beyond (world x, z).
static func strip_out(x: float, z: float) -> float:
	var l := to_strip(x, z)
	return strip_out_l(l.x, l.y)


static func strip_out_l(x: float, z: float) -> float:
	var best := 1e9
	for r in STRIP_FLAT:
		var rr: Rect2 = r
		var dx := maxf(maxf(rr.position.x - x, x - rr.end.x), 0.0)
		var dz := maxf(maxf(rr.position.y - z, z - rr.end.y), 0.0)
		best = minf(best, Vector2(dx, dz).length())
	return best


# ------------------------------------------------------------------------------
#  Lots
# ------------------------------------------------------------------------------
## A rectangle footprint, wound so its edges are 0 north, 1 east, 2 south, 3 west.
static func rect(x0: float, x1: float, z0: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


const N := 0
const E := 1
const S := 2
const W := 3


## Keep trees and litter off an open lot (a parking lot, an apron).
func _keep(poly: PackedVector2Array) -> void:
	var bp: Array = get_meta("_bldg_polys", [])
	bp.append(poly)
	set_meta("_bldg_polys", bp)


## Driveways across the sidewalk: [centre, half-width along the street]
var _drives: Array = [[Vector2(-45, 8.0), 5.0], [Vector2(-19, 8.0), 5.0], [Vector2(-5.9, 24.0), 4.5], [Vector2(-82, -8.0), 5.0], [Vector2(69, -8.0), 4.0], [Vector2(110, -8.0), 8.0], [Vector2(-139, -8.0), 5.0], [Vector2(115, 8.0), 4.0]]


func _no_walk(p: Vector2) -> bool:
	for dv in _drives:
		var c: Vector2 = dv[0]
		var hw: float = dv[1]
		var along_x := absf(c.y) < 10.0 and absf(c.x) > 10.0
		if absf(p.x - c.x) < (hw if along_x else 1.5) and absf(p.y - c.y) < (1.5 if along_x else hw):
			return true
	return false


func _drive_aprons() -> void:
	for dv in _drives:
		var c: Vector2 = dv[0]
		var hw: float = dv[1]
		var along_x := absf(c.y) < 10.0 and absf(c.x) > 10.0
		var r := rect(c.x - hw, c.x + hw, c.y - 1.2, c.y + 1.2) if along_x else rect(c.x - 1.2, c.x + 1.2, c.y - hw, c.y + hw)
		_patch(k_asphalt, r, 0.028, Color(0.24, 0.24, 0.25))


func _lots() -> void:
	_drive_aprons()
	_gas_station_80s()
	_nw_block()
	_ne_block()
	_se_block()
	_edges()
	_houses()


# ------------------------------------------------------------------------------
#  North-west of the corner: the corner store, the pharmacy, the little
#  restaurant, and the grocery set back behind its parking lot
# ------------------------------------------------------------------------------
func _nw_block() -> void:
	# the corner store: old brick, two storeys (a flat over the shop), awning
	_building_poly(rect(-24.0, -8.5, -27.0, -9.5), {"shop": true, "building:levels": "2", "wall": "brick", "wall_col": BRICK[0],
		"sign": "CORNER STORE", "sign_col": Color(0.12, 0.30, 0.18), "awning": 1, "painted": 0, "front": S, "roof": "flat"})
	var cs := Vector2(-16.0, -8.6)
	_paper_box(cs + Vector2(6.5, 0.6), Vector2(1, 0))
	_paper_box(cs + Vector2(5.8, 0.6), Vector2(1, 0))
	_payphone(Vector2(-7.3, -12.0), Vector2(1, 0))
	_bin(cs + Vector2(-6.0, 0.8))
	for k in range(4):
		_bx(k_paint, Vector3(cs.x - 4.2, CURB_H + 0.15 + float(k % 2) * 0.3, cs.y + 0.5 + float(k / 2) * 0.05), Vector3(0.45, 0.28, 0.32), Color(0.75, 0.12, 0.10) if k % 2 == 0 else Color(0.85, 0.70, 0.12))
	_sandwich_board(cs + Vector2(-2.0, 1.0), "MILK  BREAD  SMOKES")
	_bike_rack(cs + Vector2(2.5, 1.1))
	# the pharmacy: cream stucco, the big painted holiday windows (FILM_NOTES 4)
	_building_poly(rect(-44.5, -25.0, -29.0, -9.5), {"shop": true, "building:levels": "1", "wall": "stucco", "wall_col": Color(0.88, 0.84, 0.72),
		"sign": "PHARMACY", "sign_col": Color(0.92, 0.90, 0.82), "awning": 0, "painted": 1, "front": S, "roof": "flat"})
	_hang_sign(Vector2(-27.5, -9.6), Vector2(0, 1), "Rx", Color(0.15, 0.40, 0.25))
	_bench(Vector2(-36.0, -9.8), Vector2(0, 1))
	_bin(Vector2(-33.8, -9.6))
	_hydrant(Vector2(-30.0, -7.6))
	# the little restaurant: white, red awning, a pole sign, its back-door clutter
	_building_poly(rect(-59.0, -45.5, -24.0, -9.5), {"shop": true, "building:levels": "1", "wall": "stucco", "wall_col": Color(0.95, 0.94, 0.90),
		"sign": "RESTAURANT", "sign_col": Color(0.70, 0.10, 0.08), "awning": 1, "painted": 0, "front": S, "roof": "flat"})
	_pole_sign(Vector2(-57.5, -7.6), 7.0, "EATS - COFFEE")
	_sandwich_board(Vector2(-50.0, -9.0), "TODAY: CHILI  1.95")
	_dumpster(Vector2(-52.0, -27.5), PI)
	k_paint.box_at(Vector3(-48.5, 0.55, -26.0), Vector3(1.0, 1.1, 0.8), Color(0.35, 0.35, 0.33))
	for k2 in range(3):
		_bx(k_wood, Vector3(-56.0 + float(k2) * 0.5, 0.25, -25.5), Vector3(0.45, 0.5, 0.35), Color(0.62, 0.50, 0.34), _rng.randf() * 0.4)
	# the grocery, set back behind its lot
	_building_poly(rect(-104.0, -66.0, -52.0, -27.0), {"shop": true, "building:levels": "1", "wall": "stucco", "wall_col": Color(0.82, 0.78, 0.68),
		"sign": "GROCERY  -  FOODS", "sign_col": Color(0.15, 0.30, 0.55), "awning": 0, "painted": 0, "front": S, "roof": "flat"})
	var lot := rect(-104.0, -62.0, -27.0, -9.5)
	_keep(lot)
	_patch(k_asphalt, lot, 0.02, Color(0.23, 0.23, 0.24))
	for k3 in range(12):
		var x := -101.0 + float(k3) * 3.0
		_flat_strip(k_paint, Vector2(x, -20.5), Vector2(x, -14.5), 0.1, 0.03, Color(0.92, 0.92, 0.88))
	for k4 in range(7):
		var cx := -100.0 + float(k4) * 5.5 + _rng.randf_range(-0.3, 0.3)
		if _rng.randf() < 0.65:
			_car(Vector2(cx, -17.5), Vector2(0, 1 if _rng.randf() < 0.5 else -1))
	for k5 in range(6):
		_cart(Vector2(-75.0 - float(k5) * 0.25, -25.6), 0.0)
	_cart(Vector2(-90.0, -22.0), 0.7)
	_cart(Vector2(-70.5, -12.0), 2.1)
	k_paint.box_at(Vector3(-80.0, 0.6, -26.4), Vector3(1.6, 1.2, 0.8), Color(0.93, 0.93, 0.95))
	_lbl("ICE", Vector3(-80.0, 0.85, -25.99), Vector2(0, 1), 0.006, Color(0.15, 0.35, 0.70))
	_lbl("SPECIALS  THIS WEEK", Vector3(-92.0, 1.8, -26.94), Vector2(0, 1), 0.006, Color(0.85, 0.12, 0.08))
	_dumpster(Vector2(-96.0, -54.5), 0.0)
	_dumpster(Vector2(-92.5, -54.5), 0.05, Color(0.20, 0.30, 0.55))
	for k6 in range(5):
		_bx(k_wood, Vector3(-86.0, 0.07 + float(k6) * 0.15, -54.0), Vector3(1.2, 0.12, 1.0), Color(0.58, 0.46, 0.30))
	_box_truck(Vector2(-75.0, -58.0), Vector2(1, 0), "FRESH FOODS")


# ------------------------------------------------------------------------------
#  North-east of the corner: the town hall on its lawn, the police station
#  with its cruisers, the post office, the fire hall
# ------------------------------------------------------------------------------
func _ne_block() -> void:
	_building_poly(rect(12.0, 42.0, -48.0, -24.0), {"shop": false, "building:levels": "2", "wall": "brick", "wall_col": BRICK[2],
		"trim_col": Color(0.93, 0.92, 0.88), "front": S, "front_kind": "townhall", "roof": "flat"})
	_patch(k_concrete, rect(24.5, 29.5, -24.0, -9.0), 0.04, Color(0.70, 0.70, 0.67))     # the walk up to the steps
	_flag_pole(Vector2(19.0, -14.0), 10.0)
	_flag_pole(Vector2(35.0, -14.0), 10.0)
	for k in range(2):
		_bench(Vector2(21.5 + float(k) * 11.0, -19.0), Vector2(0, 1))
	_lbl("TOWN HALL", Vector3(27.0, 0.75, -11.2), Vector2(0, 1), 0.007, Color(0.95, 0.95, 0.9))
	k_brick.box_at(Vector3(27.0, 0.45, -11.4), Vector3(3.4, 0.9, 0.3), BRICK[2])                           # the lawn sign's brick base
	for hx in range(12):
		_bx(k_leaf, Vector3(13.5 + float(hx) * 1.0 if hx < 6 else 30.5 + float(hx - 6) * 1.0, 0.45, -24.8), Vector3(0.95, 0.9, 0.9), Color(0.16, 0.30, 0.14))   # hedge along the front
	# the police station: plain stucco, the blue sign, the cruisers in its lot
	_building_poly(rect(46.0, 64.0, -30.0, -9.5), {"shop": true, "building:levels": "1", "wall": "stucco", "wall_col": Color(0.80, 0.82, 0.82),
		"sign": "POLICE", "sign_col": Color(0.12, 0.22, 0.48), "awning": 0, "painted": 0, "front": S, "roof": "flat"})
	var pl := rect(64.5, 76.0, -30.0, -9.5)
	_keep(pl)
	_patch(k_asphalt, pl, 0.02, Color(0.23, 0.23, 0.24))
	_cruiser(Vector2(67.5, -18.0), Vector2(0, 1))
	_cruiser(Vector2(72.5, -22.0), Vector2(0, -1))
	_flag_pole(Vector2(47.0, -8.0), 8.0)
	_post_sign(Vector2(75.2, -10.0), "POLICE
VEHICLES
ONLY", Vector2(0, 1))
	# the post office: brick, the red mailbox at the curb, its flag
	_building_poly(rect(79.0, 94.0, -26.0, -9.5), {"shop": true, "building:levels": "1", "wall": "brick", "wall_col": BRICK[1],
		"sign": "POST OFFICE", "sign_col": Color(0.92, 0.90, 0.82), "awning": 0, "painted": 0, "front": S, "roof": "flat"})
	_mailbox(Vector2(86.0, -7.6), Vector2(0, 1))
	_flag_pole(Vector2(80.0, -8.2), 8.0)
	# the fire hall: red brick, two tall doors, the hose tower, its engine on the apron
	_building_poly(rect(100.0, 121.0, -32.0, -9.5), {"shop": false, "building:levels": "2", "wall": "brick", "wall_col": Color(0.60, 0.20, 0.14),
		"trim_col": Color(0.93, 0.92, 0.88), "front": S, "front_kind": "fire", "roof": "flat"})
	k_brick.box_at(Vector3(117.0, 6.5, -29.0), Vector3(3.0, 13.0, 3.0), Color(0.58, 0.20, 0.14))        # the hose-drying tower
	k_roof.box_at(Vector3(117.0, 13.1, -29.0), Vector3(3.4, 0.2, 3.4), Color(0.3, 0.3, 0.3))
	_patch(k_concrete, rect(101.0, 120.0, -9.4, -6.9), 0.035, Color(0.66, 0.66, 0.63))
	_fire_engine(Vector2(105.5, -13.0), Vector2(0, 1))
	_hydrant(Vector2(122.5, -7.6))


func _flag_pole(p: Vector2, hgt: float) -> void:
	k_concrete.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)), 0.35, 0.3, 0.3, 10, Color(0.7, 0.7, 0.68), true)
	k_metal.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)), 0.07, 0.04, hgt, 10, Color(0.85, 0.86, 0.86), true)
	k_metal.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, hgt, p.y)), 0.08, 0.08, 0.1, 10, Color(0.8, 0.7, 0.3), true)
	# the flag: red-white-red bands, a slight wave (generic, no emblem)
	var fw := 1.8
	var fh := 0.9
	for band in range(3):
		var x0 := fw * float(band) / 3.0
		var x1 := fw * float(band + 1) / 3.0
		var w0 := sin(x0 * 2.0) * 0.12
		var w1 := sin(x1 * 2.0) * 0.12
		var col := Color(0.80, 0.10, 0.08) if band != 1 else Color(0.95, 0.95, 0.93)
		k_paint.quad(Vector3(p.x + x0, hgt - 0.1, p.y + w0), Vector3(p.x + x1, hgt - 0.1, p.y + w1), Vector3(p.x + x1, hgt - 0.1 - fh, p.y + w1), Vector3(p.x + x0, hgt - 0.1 - fh, p.y + w0), col, Vector3(0, 0, 1))
		k_paint.quad(Vector3(p.x + x1, hgt - 0.1, p.y + w1), Vector3(p.x + x0, hgt - 0.1, p.y + w0), Vector3(p.x + x0, hgt - 0.1 - fh, p.y + w0), Vector3(p.x + x1, hgt - 0.1 - fh, p.y + w1), col, Vector3(0, 0, -1))
	_tube3(Vector3(p.x + 0.06, 0.5, p.y), Vector3(p.x + 0.06, hgt, p.y), 0.005, Color(0.9, 0.9, 0.9))   # the halyard


func _post_sign(p: Vector2, text: String, facing: Vector2) -> void:
	k_metal.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)), 0.03, 0.03, 2.2, 8, Color(0.6, 0.6, 0.6), true)
	_bx(k_paint, Vector3(p.x, 1.9, p.y) - Vector3(facing.x, 0, facing.y) * 0.02, Vector3(0.6, 0.6, 0.02) if absf(facing.y) > 0.5 else Vector3(0.02, 0.6, 0.6), Color(0.95, 0.95, 0.93))
	_lbl(text, Vector3(p.x, 1.9, p.y) + Vector3(facing.x, 0, facing.y) * 0.005, facing, 0.0016, Color(0.1, 0.1, 0.1), 48)


func _mailbox(p: Vector2, facing: Vector2) -> void:
	var o := Vector3(p.x, CURB_H, p.y)
	k_paint.box_at(o + Vector3(0, 0.15, 0), Vector3(0.45, 0.3, 0.45), Color(0.1, 0.1, 0.1))
	k_paint.box_at(o + Vector3(0, 0.75, 0), Vector3(0.55, 0.9, 0.5), Color(0.78, 0.10, 0.08))
	k_paint.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), o + Vector3(0, 1.2, -0.25)), 0.275, 0.275, 0.5, 12, Color(0.78, 0.10, 0.08), false)
	k_metal.box_at(o + Vector3(0, 1.0, facing.y * 0.26), Vector3(0.35, 0.06, 0.02), Color(0.2, 0.2, 0.2))
	_lbl("MAIL", o + Vector3(0, 0.7, facing.y * 0.26), facing, 0.003, Color(1, 1, 1))


## The cruiser of the time (FILM_NOTES 5): a big two-door, white with dark blue
## doors and hood, one red beacon and the light bar, a push bar on the front.
func _cruiser(p: Vector2, fwd: Vector2) -> void:
	_car(p, fwd, "sedan", Color(0.95, 0.95, 0.93))
	var b := Basis.looking_at(Vector3(fwd.x, 0, fwd.y), Vector3.UP)
	var o := Vector3(p.x, 0, p.y)
	var blue := Color(0.10, 0.16, 0.36)
	for sd in [-1.0, 1.0]:
		k_paint.box(Transform3D(b, o + b * Vector3(float(sd) * 0.99, 0.62, -0.3)), Vector3(0.02, 0.5, 1.4), blue)    # the door
	k_paint.box(Transform3D(b, o + b * Vector3(0, 0.96, -1.9)), Vector3(1.7, 0.02, 1.5), blue)                       # the hood
	k_paint.box(Transform3D(b, o + b * Vector3(0, 1.58, 0.4)), Vector3(1.2, 0.1, 0.25), Color(0.1, 0.1, 0.1))        # light bar
	for lx in [-0.4, 0.4]:
		k_glass.box(Transform3D(b, o + b * Vector3(float(lx), 1.68, 0.4)), Vector3(0.3, 0.12, 0.2), Color(0.9, 0.1, 0.08) if float(lx) < 0.0 else Color(0.15, 0.3, 0.9))
	k_glass.cylinder(Transform3D(Basis.IDENTITY, o + b * Vector3(0, 1.63, 0.4)), 0.1, 0.09, 0.2, 10, Color(0.9, 0.1, 0.08), true)
	k_metal.box(Transform3D(b, o + b * Vector3(0, 0.6, -2.85)), Vector3(1.2, 0.45, 0.08), Color(0.1, 0.1, 0.1))     # push bar
	for sd2 in [-1.0, 1.0]:
		var side := b.x * float(sd2)
		_lbl("POLICE", o + b * Vector3(float(sd2) * 1.01, 0.62, -0.3), Vector2(side.x, side.z), 0.0035, Color(1, 1, 1))


## The town's pumper: a tall red cab-forward engine with the hose bed and ladders.
func _fire_engine(p: Vector2, fwd: Vector2) -> void:
	var b := Basis.looking_at(Vector3(fwd.x, 0, fwd.y), Vector3.UP)
	var o := Vector3(p.x, 0, p.y)
	var red := Color(0.75, 0.08, 0.06)
	k_paint.rbox(Transform3D(b, o + b * Vector3(0, 1.55, -2.9)), Vector3(2.4, 1.9, 2.0), red, 0.1)                 # the cab
	k_glass.box(Transform3D(b, o + b * Vector3(0, 2.0, -3.92)), Vector3(2.1, 0.75, 0.04), Color(0.12, 0.15, 0.18))
	k_paint.box(Transform3D(b, o + b * Vector3(0, 1.4, 1.0)), Vector3(2.45, 1.8, 5.6), red)                         # the body
	for sd in [-1.0, 1.0]:
		for cpt in range(3):
			k_metal.box(Transform3D(b, o + b * Vector3(float(sd) * 1.23, 1.4, -1.0 + float(cpt) * 1.6)), Vector3(0.02, 1.2, 1.4), Color(0.78, 0.78, 0.76))   # locker doors
	for lx in [-0.7, 0.7]:
		k_metal.box(Transform3D(b, o + b * Vector3(float(lx), 2.55, 0.8)), Vector3(0.35, 0.08, 6.0), Color(0.78, 0.78, 0.76))   # ladders on top
	k_metal.box(Transform3D(b, o + b * Vector3(0, 0.75, -4.0)), Vector3(2.5, 0.25, 0.2), Color(0.85, 0.85, 0.85))       # bumper
	k_glass.box(Transform3D(b, o + b * Vector3(0, 2.6, -3.4)), Vector3(1.6, 0.15, 0.25), Color(0.9, 0.1, 0.08))      # the bar
	for wz in [-2.9, 2.2]:
		for wx in [-1.0, 1.0]:
			var wb := b * Basis(Vector3.BACK, PI * 0.5)
			k_trim.cylinder(Transform3D(wb, o + b * Vector3(float(wx) * 1.0, 0.52, float(wz)) - wb.y * 0.17), 0.52, 0.52, 0.34, 16, Color(0.06, 0.06, 0.06), true)


func _townhall_front(a: Vector2, b: Vector2, out: Vector2, h: float) -> void:
	var t := (b - a).normalized()
	var m := (a + b) * 0.5
	var oh := Vector3(out.x, 0, out.y)
	var cream := Color(0.93, 0.92, 0.88)
	# two rows of tall windows either side of the portico
	for sd in [-1.0, 1.0]:
		var e0 := m + t * float(sd) * 4.2
		var e1 := (b if float(sd) > 0.0 else a) - t * float(sd) * 0.6
		var lo := e0 if float(sd) > 0.0 else e1
		var hi := e1 if float(sd) > 0.0 else e0
		_window_row(lo, hi, out, 1.0, cream, 2.4)
		_window_row(lo, hi, out, 3.9, cream, 2.4)
	# the portico: steps, four columns, the beam and pediment, double doors
	for st in range(4):
		_board(m - t * (3.6 - float(st) * 0.1), m + t * (3.6 - float(st) * 0.1), out, float(st) * 0.15, float(st + 1) * 0.15, 2.4 - float(st) * 0.4, Color(0.72, 0.72, 0.70))
	for ci in range(4):
		var cp := m + t * (-2.7 + float(ci) * 1.8) + out * 1.9
		k_concrete.cylinder(Transform3D(Basis.IDENTITY, _v3(cp, 0.6)), 0.24, 0.2, 4.2, 14, cream, true)
		k_concrete.box_at(_v3(cp, 0.68), Vector3(0.55, 0.16, 0.55), cream)
		k_concrete.box_at(_v3(cp, 4.8), Vector3(0.55, 0.16, 0.55), cream)
	var p0 := m - t * 3.4
	var p1 := m + t * 3.4
	_board(p0, p1, out, 4.88, 5.5, 2.3, cream)                                          # the beam / porch roof
	k_concrete.tri(_v3(p0 + out * 2.3, 5.5), _v3(p1 + out * 2.3, 5.5), _v3(m + out * 2.3, 6.9), cream, oh)   # pediment face
	k_roof.quad(_v3(p0 + out * 2.4, 5.45), _v3(m + out * 2.4, 6.95), _v3(m, 6.95), _v3(p0, 5.45), Color(0.30, 0.30, 0.32), Vector3(-t.x, 1.0, -t.y) )
	k_roof.quad(_v3(m + out * 2.4, 6.95), _v3(p1 + out * 2.4, 5.45), _v3(p1, 5.45), _v3(m, 6.95), Color(0.30, 0.30, 0.32), Vector3(t.x, 1.0, t.y))
	_board(m - t * 1.0, m + t * 1.0, out, 0.6, 3.4, 0.05, cream)
	_board(m - t * 0.9, m + t * 0.9, out, 0.6, 3.2, 0.09, Color(0.35, 0.22, 0.12))
	_board(m - t * 0.03, m + t * 0.03, out, 0.6, 3.2, 0.11, Color(0.2, 0.13, 0.07))
	_lbl("TOWN HALL", _v3(m + out * 2.32, 5.2), out, 0.0055, Color(0.25, 0.22, 0.2))
	_lbl("1 9 0 8", _v3(m + out * 2.32, 6.0), out, 0.0035, Color(0.35, 0.3, 0.28))
	_board(a, b, out, h - 0.5, h - 0.3, 0.12, cream)                                    # cornice


func _firehall_front(a: Vector2, b: Vector2, out: Vector2, h: float) -> void:
	var t := (b - a).normalized()
	var L := a.distance_to(b)
	var cream := Color(0.93, 0.92, 0.88)
	for bi in range(2):
		var b0 := a + t * (1.2 + float(bi) * (L - 2.4) * 0.5 + 0.4)
		var b1 := a + t * (1.2 + float(bi + 1) * (L - 2.4) * 0.5 - 0.4)
		_board(b0 - t * 0.2, b1 + t * 0.2, out, 0.0, 4.6, 0.04, cream)
		for pnl in range(7):
			var y0 := 0.05 + float(pnl) * 0.62
			_board(b0, b1, out, y0, y0 + 0.58, 0.07, Color(0.78, 0.10, 0.08) if pnl != 4 else Color(0.20, 0.24, 0.28))
		_lbl(str(bi + 1), _v3((b0 + b1) * 0.5 + out * 0.08, 4.9), out, 0.005, Color(0.95, 0.95, 0.9))
	_window_row(a + t * 0.6, b - t * 0.6, out, 5.9, cream, 2.6)
	_board(a, b, out, 5.0, 5.6, 0.1, cream)
	_lbl("FIRE HALL", _v3((a + b) * 0.5 + out * 0.11, 5.3), out, 0.007, Color(0.6, 0.1, 0.08))


# ------------------------------------------------------------------------------
#  South-east of the corner: the bank, the hardware store, the barber, the old
#  hotel's tavern, the little park, the burger stand
# ------------------------------------------------------------------------------
func _se_block() -> void:
	_building_poly(rect(8.5, 22.0, 9.5, 27.0), {"shop": true, "building:levels": "1", "wall": "brick", "wall_col": BRICK[1],
		"sign": "SAVINGS", "sign_col": Color(0.62, 0.10, 0.08), "awning": 0, "painted": 0, "front": N, "roof": "flat"})
	_lbl("TIME  10:42    TEMP  6 C", Vector3(15.0, 4.6, 9.38), Vector2(0, -1), 0.005, Color(1.0, 0.75, 0.3))
	k_paint.box_at(Vector3(15.0, 4.6, 9.45), Vector3(3.6, 0.4, 0.1), Color(0.08, 0.08, 0.08))
	# the hardware store: two-storey, gable to the street, a little shed porch (FILM_NOTES 6)
	_building_poly(rect(23.5, 37.0, 9.5, 29.0), {"shop": true, "building:levels": "2", "wall": "stucco", "wall_col": Color(0.82, 0.74, 0.58),
		"sign": "HARDWARE", "sign_col": Color(0.15, 0.25, 0.45), "awning": 0, "painted": 0, "front": N, "roof": "gable"})
	for k in range(3):                       # wheelbarrows, bags, a rake rack out front
		var wb := Vector3(25.0 + float(k) * 1.1, CURB_H, 8.4)
		k_paint.box(Transform3D(Basis(Vector3.RIGHT, 0.12), wb + Vector3(0, 0.45, 0)), Vector3(0.6, 0.25, 1.1), [Color(0.2, 0.4, 0.2), Color(0.7, 0.1, 0.08), Color(0.6, 0.6, 0.6)][k])
		k_trim.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), wb + Vector3(0.1, 0.2, -0.55)), 0.18, 0.18, 0.12, 10, Color(0.06, 0.06, 0.06), true)
	for k2 in range(6):
		_bx(k_paint, Vector3(30.5 + float(k2 % 3) * 0.55, CURB_H + 0.1 + float(k2 / 3) * 0.2, 8.6), Vector3(0.5, 0.18, 0.35), Color(0.85, 0.82, 0.70))
	k_wood.box_at(Vector3(34.5, CURB_H + 0.8, 8.8), Vector3(1.0, 1.6, 0.1), Color(0.5, 0.36, 0.22))
	for k3 in range(5):
		_tube3(Vector3(34.1 + float(k3) * 0.2, CURB_H, 8.7), Vector3(34.1 + float(k3) * 0.2, CURB_H + 1.7, 8.65), 0.015, Color(0.62, 0.48, 0.30))
	# the barber with his pole
	_building_poly(rect(38.5, 46.5, 9.5, 23.0), {"shop": true, "building:levels": "1", "wall": "siding", "wall_col": Color(0.62, 0.68, 0.56),
		"sign": "BARBER", "sign_col": Color(0.92, 0.90, 0.82), "awning": 0, "painted": 0, "front": N, "roof": "flat"})
	_barber_pole(Vector2(45.6, 9.2))
	# the old hotel with its tavern downstairs
	_building_poly(rect(48.0, 65.0, 9.5, 29.0), {"shop": true, "building:levels": "2", "wall": "brick", "wall_col": BRICK[0],
		"sign": "HOTEL  -  TAVERN", "sign_col": Color(0.12, 0.12, 0.12), "awning": 1, "painted": 0, "front": N, "roof": "flat"})
	_lbl("BEER", Vector3(62.0, 2.0, 9.42), Vector2(0, -1), 0.007, Color(1.0, 0.3, 0.2))
	_booth(Vector2(66.5, 9.8), Vector2(0, -1))
	_dumpster(Vector2(56.0, 31.0), 0.0)
	for k4 in range(6):
		_bx(k_paint, Vector3(60.0 + float(k4 % 3) * 0.42, 0.14 + float(k4 / 3) * 0.28, 30.5), Vector3(0.4, 0.26, 0.3), Color(0.40, 0.25, 0.12))   # empties crates
	_park(Rect2(68.5, 10.0, 36.0, 38.0))
	_burger_stand(Vector2(115.0, 18.0))


func _barber_pole(p: Vector2) -> void:
	var o := Vector3(p.x, 2.0, p.y)
	k_metal.box_at(o + Vector3(0, 0, 0.12), Vector3(0.1, 0.1, 0.25), Color(0.7, 0.7, 0.7))
	k_glass.cylinder(Transform3D(Basis.IDENTITY, o + Vector3(0, -0.4, -0.05)), 0.1, 0.1, 0.8, 12, Color(0.95, 0.95, 0.95), true)
	for k in range(5):
		var y := -0.35 + float(k) * 0.16
		k_paint.box(Transform3D(Basis(Vector3.BACK, 0.6), o + Vector3(0, y, -0.05)), Vector3(0.21, 0.05, 0.21), Color(0.8, 0.1, 0.08) if k % 2 == 0 else Color(0.15, 0.25, 0.6))
	k_metal.box_at(o + Vector3(0, 0.45, -0.05), Vector3(0.22, 0.1, 0.22), Color(0.8, 0.8, 0.8))


## The little park: paths, the bandstand, the war memorial, benches, a picnic table, trees.
func _park(r: Rect2) -> void:
	var c := r.get_center()
	_keep(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
	_flat_strip(k_concrete, Vector2(c.x, r.position.y), Vector2(c.x, r.end.y), 2.0, 0.03, Color(0.68, 0.66, 0.62))
	_flat_strip(k_concrete, Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), 2.0, 0.03, Color(0.68, 0.66, 0.62))
	# the bandstand: an octagon on a low base, posts, a rail, the roof to a point
	var g := Vector3(c.x, 0.0, c.y + 9.0)
	var n := 8
	var rr := 3.6
	for i in range(n):
		var a0 := TAU * float(i) / n
		var a1 := TAU * float(i + 1) / n
		var p0 := g + Vector3(cos(a0), 0, sin(a0)) * rr
		var p1 := g + Vector3(cos(a1), 0, sin(a1)) * rr
		k_wood.tri(g + Vector3(0, 0.6, 0), p1 + Vector3(0, 0.6, 0), p0 + Vector3(0, 0.6, 0), Color(0.62, 0.55, 0.45), Vector3.UP)
		k_concrete.quad(p0, p1, p1 + Vector3(0, 0.6, 0), p0 + Vector3(0, 0.6, 0), Color(0.75, 0.74, 0.70), (p0 + p1) * 0.5 - g)
		k_wood.box_at(p0 + Vector3(0, 1.95, 0), Vector3(0.14, 2.7, 0.14), Color(0.95, 0.95, 0.93))
		if i != 0:
			_tube3(p0 + Vector3(0, 1.5, 0), p1 + Vector3(0, 1.5, 0), 0.04, Color(0.95, 0.95, 0.93))
		var e0 := g + Vector3(cos(a0), 0, sin(a0)) * (rr + 0.5) + Vector3(0, 3.3, 0)
		var e1 := g + Vector3(cos(a1), 0, sin(a1)) * (rr + 0.5) + Vector3(0, 3.3, 0)
		k_roof.tri(e0, e1, g + Vector3(0, 5.2, 0), Color(0.55, 0.15, 0.10), (e0 + e1) * 0.5 - g + Vector3(0, 2, 0))
		k_trim.tri(e1, e0, g + Vector3(0, 5.1, 0), Color(0.9, 0.9, 0.88), Vector3.DOWN)
	# the memorial: a granite block on steps, a wreath
	var mp := Vector3(c.x, 0.0, c.y - 8.0)
	k_concrete.box_at(mp + Vector3(0, 0.15, 0), Vector3(3.0, 0.3, 3.0), Color(0.62, 0.62, 0.60))
	k_concrete.box_at(mp + Vector3(0, 0.4, 0), Vector3(2.2, 0.2, 2.2), Color(0.58, 0.58, 0.56))
	k_concrete.box_at(mp + Vector3(0, 2.0, 0), Vector3(1.0, 3.0, 1.0), Color(0.50, 0.50, 0.50))
	k_concrete.box_at(mp + Vector3(0, 3.7, 0), Vector3(1.3, 0.4, 1.3), Color(0.52, 0.52, 0.52))
	_lbl("LEST WE FORGET", mp + Vector3(0, 2.4, -0.52), Vector2(0, -1), 0.003, Color(0.85, 0.80, 0.6))
	k_leaf.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), mp + Vector3(0, 1.3, -0.62)), 0.32, 0.32, 0.1, 12, Color(0.16, 0.32, 0.14), true)
	for k in range(4):
		var bp := c + Vector2([-6, 6, -6, 6][k], [-3, -3, 3, 3][k])
		_bench(bp, Vector2(0, -1 if k < 2 else 1))
		_bin(bp + Vector2(1.4, 0))
	_picnic_table(Vector2(r.position.x + 5.0, r.end.y - 6.0), 0.3)
	_picnic_table(Vector2(r.end.x - 5.0, r.end.y - 5.0), -0.2)
	for k2 in range(9):
		var tp := Vector2(_rng.randf_range(r.position.x + 2, r.end.x - 2), _rng.randf_range(r.position.y + 2, r.end.y - 2))
		if absf(tp.x - c.x) < 3.0 or absf(tp.y - c.y) < 3.0 or tp.distance_to(Vector2(g.x, g.z)) < 6.0 or tp.distance_to(Vector2(mp.x, mp.z)) < 4.0:
			continue
		_tree_at(tp, false)


func _picnic_table(p: Vector2, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var o := Vector3(p.x, 0.0, p.y)
	var wc := Color(0.55, 0.42, 0.28)
	for k in range(4):
		k_wood.box(Transform3D(b, o + b * Vector3(0, 0.75, -0.36 + float(k) * 0.24)), Vector3(1.9, 0.05, 0.2), wc)
	for sd in [-1.0, 1.0]:
		k_wood.box(Transform3D(b, o + b * Vector3(0, 0.45, float(sd) * 0.75)), Vector3(1.9, 0.05, 0.28), wc)
		for lx in [-0.75, 0.75]:
			k_wood.box(Transform3D(b * Basis(Vector3.RIGHT, float(sd) * 0.45), o + b * Vector3(float(lx), 0.38, float(sd) * 0.3)), Vector3(0.08, 0.85, 0.08), wc.darkened(0.2))


## A street / yard tree from the simple kit (the leafy fall trees come later).
func _tree_at(p: Vector2, conifer: bool) -> void:
	if conifer:
		var h := _rng.randf_range(9.0, 18.0)
		k_wood.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)), 0.25, 0.18, 2.5, 8, Color(0.30, 0.22, 0.16), true)
		for k in range(5):
			var f := float(k) / 5.0
			k_leaf.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 1.5 + h * f * 0.7, p.y)), h * 0.22 * (1.0 - f * 0.75), 0.05, h * 0.32, 10, Color(0.12, 0.24, 0.14).lerp(Color(0.16, 0.30, 0.16), _rng.randf()), true)
		return
	var h2 := _rng.randf_range(7.0, 12.0)
	k_wood.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)), 0.22, 0.15, h2 * 0.65, 8, Color(0.34, 0.28, 0.22), true)
	var fall := [Color(0.85, 0.62, 0.12), Color(0.88, 0.42, 0.08), Color(0.70, 0.14, 0.08), Color(0.60, 0.58, 0.16)]
	var base: Color = fall[_rng.randi() % fall.size()]
	for k2 in range(5):
		var off := Vector3(_rng.randf_range(-1.4, 1.4), _rng.randf_range(-0.6, 0.9), _rng.randf_range(-1.4, 1.4))
		var r := _rng.randf_range(1.6, 2.5)
		k_leaf.rbox(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(p.x, h2 * 0.72, p.y) + off), Vector3(r * 1.6, r * 1.3, r * 1.6), base.lerp(fall[_rng.randi() % fall.size()], 0.3).darkened(_rng.randf() * 0.15), r * 0.5)
	# fallen leaves round its foot
	for k3 in range(14):
		var lp := p + Vector2(_rng.randf_range(-3.5, 3.5), _rng.randf_range(-3.5, 3.5))
		_disc(k_paint, lp, _rng.randf_range(0.25, 0.6), 0.012, base.darkened(_rng.randf_range(0.0, 0.3)))


## The burger stand (FILM_NOTES 9): low, white, a red standing-seam roof, the
## order windows, picnic tables, its sign; a rental truck parked by it.
func _burger_stand(c: Vector2) -> void:
	var w := 11.0
	var d := 7.0
	var poly := rect(c.x - w * 0.5, c.x + w * 0.5, c.y - d * 0.5, c.y + d * 0.5)
	_keep(rect(c.x - 9.0, c.x + 9.0, c.y - 9.0, c.y + 9.0))
	_patch(k_concrete, rect(c.x - 8.0, c.x + 8.0, 9.2, c.y - d * 0.5), 0.03, Color(0.66, 0.66, 0.63))
	_building_poly(poly, {"shop": false, "building:levels": "1", "wall": "stucco", "wall_col": Color(0.95, 0.95, 0.93),
		"trim_col": Color(0.78, 0.12, 0.08), "front": N, "front_kind": "burger", "roof": "none"})
	# the red standing-seam roof: low gable, the seams as thin ribs
	var h := 3.0
	var rise := 1.2
	var x0 := c.x - w * 0.5 - 0.5
	var x1 := c.x + w * 0.5 + 0.5
	var z0 := c.y - d * 0.5 - 0.6
	var z1 := c.y + d * 0.5 + 0.6
	var red := Color(0.70, 0.12, 0.08)
	k_paint.quad(Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h + rise, c.y), Vector3(x0, h + rise, c.y), red, Vector3(0, 1, -0.6))
	k_paint.quad(Vector3(x1, h, z1), Vector3(x0, h, z1), Vector3(x0, h + rise, c.y), Vector3(x1, h + rise, c.y), red, Vector3(0, 1, 0.6))
	var nseam := int((x1 - x0) / 0.45)
	for k in range(nseam + 1):
		var x := x0 + float(k) * (x1 - x0) / nseam
		_tube3(Vector3(x, h + 0.03, z0), Vector3(x, h + rise + 0.03, c.y), 0.015, red.darkened(0.2))
		_tube3(Vector3(x, h + 0.03, z1), Vector3(x, h + rise + 0.03, c.y), 0.015, red.darkened(0.2))
	k_siding.tri(Vector3(x0 + 0.5, h, c.y - d * 0.5), Vector3(x0 + 0.5, h, c.y + d * 0.5), Vector3(x0 + 0.5, h + rise, c.y), Color(0.95, 0.95, 0.93), Vector3.LEFT)
	k_siding.tri(Vector3(x1 - 0.5, h, c.y + d * 0.5), Vector3(x1 - 0.5, h, c.y - d * 0.5), Vector3(x1 - 0.5, h + rise, c.y), Color(0.95, 0.95, 0.93), Vector3.RIGHT)
	for k2 in range(3):
		_picnic_table(Vector2(c.x - 5.5 + float(k2) * 5.5, c.y - d * 0.5 - 3.5), 0.0)
	_bin(Vector2(c.x + 7.0, c.y - d * 0.5 - 1.5))
	_pole_sign(Vector2(c.x - 7.0, 9.6), 6.5, "BURGERS - ICE CREAM")
	_post_sign(Vector2(c.x + 8.5, 9.8), "TRUCK\nRENTAL", Vector2(0, -1))
	_box_truck(Vector2(c.x + 12.0, c.y + 4.0), Vector2(0, -1), "MOVING VANS")


func _burger_front(a: Vector2, b: Vector2, out: Vector2) -> void:
	var t := (b - a).normalized()
	var oh := Vector3(out.x, 0, out.y)
	for k in range(2):
		var c := a.lerp(b, 0.3 + float(k) * 0.4)
		k_glass.quad(_v3(c - t * 1.1 + out * 0.02, 1.0), _v3(c + t * 1.1 + out * 0.02, 1.0), _v3(c + t * 1.1 + out * 0.02, 2.3), _v3(c - t * 1.1 + out * 0.02, 2.3), Color(0.15, 0.17, 0.18), oh)
		_board(c - t * 1.3, c + t * 1.3, out, 0.95, 1.05, 0.45, Color(0.85, 0.85, 0.83))      # the counter shelf
		_board(c - t * 1.2, c + t * 1.2, out, 2.3, 2.5, 0.06, Color(0.78, 0.12, 0.08))
		_lbl("ORDER HERE" if k == 0 else "PICK UP", _v3(c + out * 0.07, 2.4), out, 0.0028, Color(1, 1, 1))
	var mb := a.lerp(b, 0.5)
	k_paint.quad(_v3(mb - t * 0.9 + out * 0.03, 1.2), _v3(mb + t * 0.9 + out * 0.03, 1.2), _v3(mb + t * 0.9 + out * 0.03, 2.3), _v3(mb - t * 0.9 + out * 0.03, 2.3), Color(0.12, 0.12, 0.12), oh)
	_lbl("BURGER  .95\nCHEESE  1.10\nFRIES  .55\nCONE  .40", _v3(mb + out * 0.04, 1.75), out, 0.0022, Color(1, 1, 0.85), 48)


# ------------------------------------------------------------------------------
#  The edges of town: the motel, the church, the welcome arch, the rail crossing
# ------------------------------------------------------------------------------
func _edges() -> void:
	# the motel on the way in from the west (FILM_NOTES 7), its lawn and hedge
	_building_poly(rect(-162.0, -118.0, -34.0, -20.0), {"style": "motel", "front": S})
	_patch(k_asphalt, rect(-162.0, -118.0, -19.5, -11.0), 0.02, Color(0.23, 0.23, 0.24))
	_keep(rect(-162.0, -118.0, -19.5, -9.0))
	for k in range(4):
		_car(Vector2(-155.0 + float(k) * 9.0, -16.0), Vector2(0, -1))
	for hx in range(20):
		_bx(k_leaf, Vector3(-161.5 + float(hx) * 1.0, 0.4, -10.0), Vector3(0.95, 0.8, 0.8), Color(0.16, 0.30, 0.14))
	_post_sign(Vector2(-121.0, -9.6), "VACANCY", Vector2(0, 1))
	# the church on Cross Street: white clapboard, the steeple at the street end
	_building_poly(rect(-30.0, -10.0, -96.0, -82.0), {"shop": false, "building:levels": "1", "wall": "siding", "wall_col": Color(0.95, 0.95, 0.93),
		"trim_col": Color(0.30, 0.30, 0.32), "front": E, "front_kind": "church", "roof": "gable"})
	var sp := Vector3(-11.0, 0.0, -89.0)
	k_siding.box_at(sp + Vector3(0, 6.0, 0), Vector3(3.2, 12.0, 3.2), Color(0.95, 0.95, 0.93))
	k_trim.box_at(sp + Vector3(0, 10.0, 0), Vector3(3.3, 2.0, 3.3), Color(0.25, 0.25, 0.28))         # the belfry louvres
	k_roof.cylinder(Transform3D(Basis.IDENTITY, sp + Vector3(0, 12.0, 0)), 2.1, 0.0, 7.0, 8, Color(0.30, 0.30, 0.34), true)
	k_metal.box_at(sp + Vector3(0, 19.6, 0), Vector3(0.08, 1.2, 0.08), Color(0.8, 0.7, 0.3))
	k_metal.box_at(sp + Vector3(0, 19.8, 0), Vector3(0.6, 0.08, 0.08), Color(0.8, 0.7, 0.3))
	_post_sign(Vector2(-7.6, -80.0), "SUNDAY\nSERVICE\n11 AM", Vector2(1, 0))
	# the welcome arch on the highway west (FILM_NOTES 2): log uprights, the board
	_welcome_arch(Vector2(-250.0, 0.0))
	# the rail crossing east of town (FILM_NOTES 10)
	_railway(260.0)


func _church_front(a: Vector2, b: Vector2, out: Vector2) -> void:
	var t := (b - a).normalized()
	var m := (a + b) * 0.5
	_board(m - t * 0.9, m + t * 0.9, out, 0.35, 3.0, 0.06, Color(0.40, 0.22, 0.12))
	_board(m - t * 0.03, m + t * 0.03, out, 0.35, 3.0, 0.08, Color(0.25, 0.14, 0.08))
	for st in range(3):
		_board(m - t * (1.6 - float(st) * 0.2), m + t * (1.6 - float(st) * 0.2), out, float(st) * 0.12, float(st + 1) * 0.12, 1.4 - float(st) * 0.4, Color(0.70, 0.70, 0.68))


func _welcome_arch(p: Vector2) -> void:
	var wood := Color(0.48, 0.34, 0.20)
	for sd in [-1.0, 1.0]:
		var lp := Vector3(p.x, 0.0, p.y + float(sd) * 7.5)
		k_wood.cylinder(Transform3D(Basis.IDENTITY, lp), 0.45, 0.4, 7.5, 12, wood, true)
		k_concrete.box_at(lp + Vector3(0, 0.3, 0), Vector3(1.4, 0.6, 1.4), Color(0.6, 0.6, 0.58))
		for k in range(4):                    # years carved down the log
			_lbl(["1", "8", "5", "8"][k], lp + Vector3(-0.44, 5.5 - float(k) * 0.7, 0), Vector2(-1, 0), 0.006, Color(0.25, 0.16, 0.08))
	var beam := Basis(Vector3.RIGHT, PI * 0.5)
	k_wood.cylinder(Transform3D(beam, Vector3(p.x, 7.2, p.y - 8.3)), 0.4, 0.4, 16.6, 12, wood, true)
	k_paint.box_at(Vector3(p.x, 6.2, p.y), Vector3(0.12, 1.2, 9.0), Color(0.70, 0.12, 0.08))
	for sd2 in [-1.0, 1.0]:
		_lbl("WELCOME", Vector3(p.x + float(sd2) * 0.07, 6.2, p.y), Vector2(float(sd2), 0), 0.014, Color(1, 0.95, 0.85))


func _railway(x: float) -> void:
	var z0 := -500.0
	var z1 := 600.0
	_flat_strip(k_concrete, Vector2(x, z0), Vector2(x, z1), 3.6, 0.08, Color(0.45, 0.43, 0.40))      # the ballast
	var n := int((z1 - z0) / 0.65)
	for k in range(n):
		var z := z0 + float(k) * 0.65
		if absf(z) < 6.0:
			continue
		k_wood.box_at(Vector3(x, 0.14, z), Vector3(2.5, 0.12, 0.22), Color(0.28, 0.22, 0.16))
	for sx in [-0.72, 0.72]:
		k_metal.box_at(Vector3(x + float(sx), 0.27, (z0 + z1) * 0.5), Vector3(0.08, 0.14, z1 - z0), Color(0.45, 0.42, 0.40))
	# the crossing: planks between the rails, the crossbucks with their lights
	k_wood.box_at(Vector3(x, 0.2, 0), Vector3(2.2, 0.1, 9.0), Color(0.35, 0.30, 0.24))
	for sd in [-1.0, 1.0]:
		var sp := Vector3(x + float(sd) * 4.0, 0.0, -float(sd) * 6.5)
		k_metal.cylinder(Transform3D(Basis.IDENTITY, sp), 0.08, 0.08, 4.4, 10, Color(0.85, 0.85, 0.85), true)
		for xb in [0.6, -0.6]:
			k_paint.box(Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.FORWARD, float(xb)), sp + Vector3(0, 3.9, 0)), Vector3(1.6, 0.25, 0.03), Color(0.95, 0.95, 0.93))
		k_paint.box_at(sp + Vector3(0, 2.9, 0), Vector3(0.15, 0.1, 1.2), Color(0.1, 0.1, 0.1))
		for lz in [-0.45, 0.45]:
			k_glass.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), sp + Vector3(0.05, 2.85, float(lz))), 0.13, 0.13, 0.05, 12, Color(0.6, 0.08, 0.06), true)
		k_metal.box_at(sp + Vector3(float(sd) * 0.8, 0.7, 0), Vector3(0.6, 1.4, 0.6), Color(0.62, 0.64, 0.62))   # the relay box
		_lbl("RAILWAY\nCROSSING", sp + Vector3(0, 3.9, 0.03 * float(sd)), Vector2(0, -float(sd)) * -1.0, 0.0022, Color(0.05, 0.05, 0.05), 48)


# ------------------------------------------------------------------------------
#  A few houses on the back roads: wood frame, gables, porches; picket fences,
#  mailboxes, cans at the curb, a car in the drive, a clothesline, maples
# ------------------------------------------------------------------------------
func _houses() -> void:
	var spots := [[-80.0, -1], [-52.0, -1], [-26.0, -1], [26.0, -1], [52.0, -1], [80.0, -1], [-80.0, 1], [-50.0, 1], [34.0, 1], [64.0, 1]]
	for sp in spots:
		var x: float = sp[0]
		var side: int = sp[1]                  # -1 north of Park Road, 1 south of River Road
		var road_z := -116.0 if side < 0 else 116.0
		var fz := road_z + float(side) * 12.0     # the house's front wall
		var w := _rng.randf_range(9.0, 11.0)
		var d := _rng.randf_range(8.0, 9.5)
		var poly := rect(x - w * 0.5, x + w * 0.5, fz, fz + float(side) * d) if side > 0 else rect(x - w * 0.5, x + w * 0.5, fz - d, fz)
		var two := _rng.randf() < 0.35
		_building_poly(poly, {"shop": false, "building:levels": "2" if two else "1", "wall": "siding", "front": N if side > 0 else S, "roof": "gable"})
		var out := Vector2(0, -float(side))
		var yard_edge := road_z + float(side) * 6.3
		# the picket fence along the front, a gap at the walk
		_fence(Vector2(x - w * 0.5 - 2.0, yard_edge), Vector2(x - 1.0, yard_edge))
		_fence(Vector2(x + 1.0, yard_edge), Vector2(x + w * 0.5 + 0.5, yard_edge))
		_patch(k_concrete, rect(x - 0.6, x + 0.6, minf(yard_edge, fz), maxf(yard_edge, fz)), 0.03, Color(0.66, 0.66, 0.63))
		# the drive and the car in it
		var dx := x + w * 0.5 + 2.2
		_patch(k_concrete, rect(dx - 1.6, dx + 1.6, minf(road_z + float(side) * 4.0, fz + float(side) * d), maxf(road_z + float(side) * 4.0, fz + float(side) * d)), 0.025, Color(0.50, 0.48, 0.44))
		_drives.append([Vector2(dx, road_z + float(side) * 4.9), 1.7])
		if _rng.randf() < 0.75:
			_car(Vector2(dx, fz + float(side) * 2.5), out * -1.0 if _rng.randf() < 0.5 else out)
		_house_mailbox(Vector2(x - 2.0, road_z + float(side) * 5.6))
		_garbage_cans(Vector2(dx + 2.2, road_z + float(side) * 5.8))
		if _rng.randf() < 0.6:
			_clothesline(Vector2(x - 2.0, fz + float(side) * (d + 3.0)), Vector2(x + 4.0, fz + float(side) * (d + 3.0)))
		_tree_at(Vector2(x - w * 0.5 - 3.5, fz - float(side) * 2.5), false)
		if _rng.randf() < 0.5:
			_tree_at(Vector2(x + _rng.randf_range(-3, 3), fz + float(side) * (d + 8.0)), _rng.randf() < 0.6)


func _fence(a: Vector2, b: Vector2) -> void:
	var L := a.distance_to(b)
	var t := (b - a) / L
	var white := Color(0.95, 0.95, 0.93)
	var n := int(L / 0.14)
	for k in range(n):
		var p := a + t * (float(k) * 0.14)
		k_wood.box_at(Vector3(p.x, 0.5, p.y), Vector3(0.08 if absf(t.x) > 0.5 else 0.02, 1.0, 0.02 if absf(t.x) > 0.5 else 0.08), white)
		k_wood.tri(Vector3(p.x - t.x * 0.04, 1.0, p.y - t.y * 0.04), Vector3(p.x + t.x * 0.04, 1.0, p.y + t.y * 0.04), Vector3(p.x, 1.08, p.y), white, Vector3(t.y, 0, -t.x))
	for ry in [0.3, 0.8]:
		_tube3(Vector3(a.x, float(ry), a.y), Vector3(b.x, float(ry), b.y), 0.025, white.darkened(0.1))


func _house_mailbox(p: Vector2) -> void:
	k_wood.box_at(Vector3(p.x, 0.5, p.y), Vector3(0.09, 1.0, 0.09), Color(0.45, 0.36, 0.25))
	k_metal.box_at(Vector3(p.x, 1.08, p.y), Vector3(0.22, 0.2, 0.45), Color(0.15, 0.15, 0.15))
	k_paint.box_at(Vector3(p.x + 0.12, 1.15, p.y + 0.1), Vector3(0.02, 0.15, 0.05), Color(0.8, 0.1, 0.08))   # the little flag


func _garbage_cans(p: Vector2) -> void:
	for k in range(_rng.randi_range(1, 3)):
		var c := Vector3(p.x + float(k) * 0.62, 0.0, p.y)
		k_metal.cylinder(Transform3D(Basis.IDENTITY, c), 0.27, 0.29, 0.75, 12, Color(0.62, 0.63, 0.62), true)
		k_metal.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.75, 0)), 0.31, 0.29, 0.06, 12, Color(0.58, 0.59, 0.58), true)
		for ry in [0.2, 0.5]:
			k_metal.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, float(ry), 0)), 0.29, 0.29, 0.03, 12, Color(0.5, 0.5, 0.5), false)
	if _rng.randf() < 0.5:
		k_trim.rbox(Transform3D(Basis(Vector3.UP, _rng.randf()), Vector3(p.x - 0.7, 0.25, p.y)), Vector3(0.5, 0.5, 0.45), Color(0.06, 0.06, 0.07), 0.15)


func _clothesline(a: Vector2, b: Vector2) -> void:
	for p in [a, b]:
		var q: Vector2 = p
		k_wood.box_at(Vector3(q.x, 1.1, q.y), Vector3(0.1, 2.2, 0.1), Color(0.45, 0.36, 0.25))
		k_wood.box_at(Vector3(q.x, 2.1, q.y), Vector3(0.1, 0.08, 1.0), Color(0.45, 0.36, 0.25))
	for lz in [-0.4, 0.4]:
		_tube3(Vector3(a.x, 2.08, a.y + float(lz)), Vector3(b.x, 2.08, b.y + float(lz)), 0.006, Color(0.85, 0.85, 0.85))
	var cols := [Color(0.9, 0.9, 0.88), Color(0.3, 0.45, 0.7), Color(0.75, 0.2, 0.15), Color(0.85, 0.80, 0.5)]
	for k in range(_rng.randi_range(2, 5)):
		var f := _rng.randf_range(0.1, 0.9)
		var p2 := a.lerp(b, f)
		_bx(k_paint, Vector3(p2.x, 1.75, p2.y + (0.4 if k % 2 == 0 else -0.4)), Vector3(_rng.randf_range(0.4, 0.9), _rng.randf_range(0.5, 0.7), 0.02), cols[k % 4])


func _sandwich_board(p: Vector2, text: String) -> void:
	var o := Vector3(p.x, CURB_H, p.y)
	for sd in [-1.0, 1.0]:
		k_wood.box(Transform3D(Basis(Vector3.RIGHT, float(sd) * 0.2), o + Vector3(0, 0.45, float(sd) * 0.09)), Vector3(0.6, 0.9, 0.03), Color(0.15, 0.15, 0.15))
		var l := _lbl(text.replace("  ", "\n"), o + Vector3(0, 0.5, float(sd) * 0.19), Vector2(0, float(sd)), 0.0018, Color(0.95, 0.95, 0.9), 48)
		l.rotate_object_local(Vector3.RIGHT, -float(sd) * 0.2)


func _bike_rack(p: Vector2) -> void:
	for k in range(5):
		var x := p.x - 0.8 + float(k) * 0.4
		_tube3(Vector3(x, CURB_H, p.y - 0.3), Vector3(x, CURB_H + 0.7, p.y - 0.3), 0.02, Color(0.6, 0.6, 0.6))
		_tube3(Vector3(x, CURB_H + 0.7, p.y - 0.3), Vector3(x, CURB_H + 0.7, p.y + 0.3), 0.02, Color(0.6, 0.6, 0.6))
		_tube3(Vector3(x, CURB_H + 0.7, p.y + 0.3), Vector3(x, CURB_H, p.y + 0.3), 0.02, Color(0.6, 0.6, 0.6))


## A sign hung out over the sidewalk on a bracket.
func _hang_sign(p: Vector2, out: Vector2, text: String, col: Color) -> void:
	var o := Vector3(p.x, 3.4, p.y)
	_tube3(o, o + Vector3(out.x, 0, out.y) * 1.2, 0.025, Color(0.15, 0.15, 0.15))
	var c := o + Vector3(out.x, 0, out.y) * 0.75 + Vector3(0, -0.45, 0)
	var side := Vector2(out.y, -out.x)
	_bx(k_paint, c, Vector3(0.06, 0.7, 0.8) if absf(out.x) > 0.5 else Vector3(0.8, 0.7, 0.06), col)
	for sd in [-1.0, 1.0]:
		_lbl(text, c + Vector3(side.x, 0, side.y) * 0.04 * float(sd), side * float(sd), 0.006, Color(1, 1, 1))


func _cart(p: Vector2, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var o := Vector3(p.x, 0.02, p.y)
	var col := Color(0.72, 0.72, 0.70)
	k_metal.box(Transform3D(b, o + Vector3(0, 0.75, 0)), Vector3(0.5, 0.4, 0.8), col.darkened(0.3))
	for sx in [-0.22, 0.22]:
		for sz in [-0.35, 0.35]:
			_tube3(o + b * Vector3(float(sx), 0.08, float(sz)), o + b * Vector3(float(sx), 0.55, float(sz)), 0.012, col)
			k_trim.box(Transform3D(b, o + b * Vector3(float(sx), 0.05, float(sz))), Vector3(0.03, 0.08, 0.08), Color(0.1, 0.1, 0.1))
	_tube3(o + b * Vector3(-0.28, 1.0, 0.48), o + b * Vector3(0.28, 1.0, 0.48), 0.018, Color(0.75, 0.12, 0.10))


## A delivery box truck backed up to a loading door.
func _box_truck(p: Vector2, fwd: Vector2, words: String) -> void:
	var b := Basis.looking_at(Vector3(fwd.x, 0, fwd.y), Vector3.UP)
	var o := Vector3(p.x, 0, p.y)
	k_paint.rbox(Transform3D(b, o + b * Vector3(0, 1.1, -2.6)), Vector3(2.2, 1.6, 2.0), Color(0.15, 0.30, 0.55), 0.08)
	k_glass.box(Transform3D(b, o + b * Vector3(0, 1.55, -3.58)), Vector3(1.9, 0.6, 0.04), Color(0.12, 0.15, 0.18))
	k_paint.box(Transform3D(b, o + b * Vector3(0, 1.85, 1.2)), Vector3(2.4, 2.6, 5.4), Color(0.92, 0.92, 0.90))
	for sd in [-1.0, 1.0]:
		var side := b.x * float(sd)
		_lbl(words, o + b * Vector3(float(sd) * 1.21, 2.0, 1.2), Vector2(side.x, side.z), 0.01, Color(0.15, 0.30, 0.55))
	for wz in [-2.6, 0.2, 2.8]:
		for wx in [-1.0, 1.0]:
			var wb := b * Basis(Vector3.BACK, PI * 0.5)
			k_trim.cylinder(Transform3D(wb, o + b * Vector3(float(wx) * 0.95, 0.45, float(wz)) - wb.y * 0.15), 0.45, 0.45, 0.3, 14, Color(0.06, 0.06, 0.06), true)
	k_metal.box(Transform3D(b, o + b * Vector3(0, 0.5, 3.95)), Vector3(2.3, 0.18, 0.15), Color(0.2, 0.2, 0.2))


# ------------------------------------------------------------------------------
#  Little helpers for props
# ------------------------------------------------------------------------------
func _lbl(text: String, pos: Vector3, facing: Vector2, px: float, col: Color, fs: int = 96) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = fs
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = pos
	l.basis = Basis.looking_at(Vector3(-facing.x, 0, -facing.y), Vector3.UP)
	add_child(l)
	return l


## A box at `c` (its centre) turned `yaw` about up.
func _bx(k: MeshKit, c: Vector3, size: Vector3, col: Color, yaw: float = 0.0) -> void:
	k.box(Transform3D(Basis(Vector3.UP, yaw), c), size, col)


## A flat patch (asphalt, concrete, a stain) over a footprint.
func _patch(k: MeshKit, poly: PackedVector2Array, y: float, col: Color) -> void:
	var tri := Geometry2D.triangulate_polygon(poly)
	for i in range(0, tri.size(), 3):
		k.tri(_v3(poly[tri[i]], y), _v3(poly[tri[i + 1]], y), _v3(poly[tri[i + 2]], y), col, Vector3.UP)


func _disc(k: MeshKit, c: Vector2, r: float, y: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var a := TAU * float(i) / 10.0
		pts.append(c + Vector2(cos(a) * r * _rng.randf_range(0.7, 1.2), sin(a) * r * _rng.randf_range(0.7, 1.2)))
	if _area(pts) < 0.0:
		pts.reverse()
	_patch(k, pts, y, col)


func _dumpster(p: Vector2, yaw: float, col: Color = Color(0.20, 0.35, 0.22)) -> void:
	var b := Basis(Vector3.UP, yaw)
	var o := Vector3(p.x, 0.0, p.y)
	k_paint.box(Transform3D(b, o + Vector3(0, 0.72, 0)), Vector3(1.9, 1.1, 1.2), col)
	k_paint.box(Transform3D(b * Basis(Vector3.RIGHT, 0.12), o + Vector3(0, 1.33, -0.02)), Vector3(1.94, 0.06, 1.28), col.darkened(0.25))   # the lid, sloped
	k_metal.box(Transform3D(b, o + Vector3(0, 0.95, 0.63)), Vector3(1.7, 0.08, 0.06), Color(0.3, 0.3, 0.3))     # the lifting bar
	for sx in [-0.8, 0.8]:
		for sz in [-0.45, 0.45]:
			k_trim.cylinder(Transform3D(b * Basis(Vector3.BACK, PI * 0.5), o + b * Vector3(float(sx) + 0.04, 0.09, float(sz))), 0.09, 0.09, 0.08, 8, Color(0.08, 0.08, 0.08), true)
	# rust streaks, a bag or two beside it, a flattened box
	k_paint.box(Transform3D(b, o + Vector3(-0.5, 0.6, 0.605)), Vector3(0.2, 0.7, 0.01), Color(0.40, 0.24, 0.12))
	for k in range(_rng.randi_range(1, 3)):
		var bp := o + b * Vector3(_rng.randf_range(-1.0, 1.0), 0.25, _rng.randf_range(0.8, 1.2))
		k_trim.rbox(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), bp), Vector3(0.5, 0.5, 0.45), Color(0.06, 0.06, 0.07), 0.15)
	k_wood.box(Transform3D(b * Basis(Vector3.RIGHT, -1.35), o + b * Vector3(1.2, 0.4, 0.3)), Vector3(0.7, 0.9, 0.03), Color(0.62, 0.50, 0.34))


func _drum(p: Vector2, col: Color, lying: bool = false) -> void:
	if lying:
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.BACK, PI * 0.5)
		k_paint.cylinder(Transform3D(b, Vector3(p.x, 0.29, p.y) - b.y * 0.44), 0.29, 0.29, 0.88, 14, col, true)
		return
	k_paint.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)), 0.29, 0.29, 0.88, 14, col, true)
	for ry in [0.3, 0.6]:
		k_metal.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, float(ry), p.y)), 0.30, 0.30, 0.03, 14, col.darkened(0.3), false)
	k_metal.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x + 0.12, 0.88, p.y)), 0.03, 0.03, 0.02, 6, Color(0.3, 0.3, 0.3), true)   # the bung


func _tyre(c: Vector3, b: Basis) -> void:
	k_trim.cylinder(Transform3D(b, c - b.y * 0.11), 0.36, 0.36, 0.22, 14, Color(0.07, 0.07, 0.07), false)
	k_trim.cylinder(Transform3D(b, c - b.y * 0.112), 0.2, 0.2, 0.224, 10, Color(0.03, 0.03, 0.03), true)


# ------------------------------------------------------------------------------
#  The gas station, about 1980, on the south-west corner (FILM_NOTES 8):
#  a full-service station - office and two service bays, the canopy over two
#  pump islands, the tall price sign on the corner, and all its clutter: tyre
#  racks, oil cans, the air post, pop machine and ice box, drums, the dumpster,
#  the tow truck. Behind it the cream two-storey block with its fire escape.
# ------------------------------------------------------------------------------
func _gas_station_80s() -> void:
	var lot := rect(-64.0, -7.0, 9.0, 56.0)
	_keep(lot)
	_patch(k_asphalt, lot, 0.02, Color(0.22, 0.22, 0.23))
	# oil stains on the apron, darker by the pumps and the bays
	for k in range(26):
		var sp := Vector2(_rng.randf_range(-50, -14), _rng.randf_range(13, 30))
		_disc(k_paint, sp, _rng.randf_range(0.3, 1.1), 0.026, Color(0.10, 0.10, 0.10, 1.0))
	# --- the station building: office (west) and two bays, front to Main Street
	var trim := Color(0.80, 0.14, 0.10)
	_building_poly(rect(-60.0, -34.0, 32.0, 45.0), {"shop": true, "building:levels": "1", "wall": "stucco", "wall_col": Color(0.93, 0.92, 0.88),
		"trim_col": trim, "front": N, "front_kind": "station", "roof": "flat"})
	# --- the canopy: four columns, a deep fascia in the company stripes, lights under
	var cc := Vector3(-30.0, 0.0, 20.5)
	var cw := 17.0
	var cd := 9.0
	var ch := 4.6
	for cx in [-cw * 0.5 + 1.0, cw * 0.5 - 1.0]:
		for cz in [-cd * 0.5 + 1.2, cd * 0.5 - 1.2]:
			var cp := cc + Vector3(float(cx), 0, float(cz))
			k_metal.box_at(cp + Vector3(0, ch * 0.5, 0), Vector3(0.32, ch, 0.32), Color(0.92, 0.92, 0.90))
			k_paint.box_at(cp + Vector3(0, 0.45, 0), Vector3(0.36, 0.9, 0.36), Color(0.95, 0.78, 0.10))        # the yellow guard sleeve
	k_trim.box_at(cc + Vector3(0, ch + 0.05, 0), Vector3(cw, 0.1, cd), Color(0.88, 0.88, 0.86))                 # the soffit
	k_paint.box_at(cc + Vector3(0, ch + 0.45, 0), Vector3(cw + 0.1, 0.8, cd + 0.1), Color(0.95, 0.95, 0.93))   # fascia
	k_paint.box_at(cc + Vector3(0, ch + 0.25, 0), Vector3(cw + 0.14, 0.22, cd + 0.14), trim)                    # the red band
	k_paint.box_at(cc + Vector3(0, ch + 0.65, 0), Vector3(cw + 0.14, 0.07, cd + 0.14), Color(0.15, 0.25, 0.55))  # blue pinstripe
	k_roof.box_at(cc + Vector3(0, ch + 0.86, 0), Vector3(cw, 0.04, cd), Color(0.3, 0.3, 0.3))
	for fz in [-1.0, 1.0]:
		_lbl("GAS  -  SERVICE", cc + Vector3(0, ch + 0.5, float(fz) * (cd * 0.5 + 0.08)), Vector2(0, float(fz)), 0.006, Color(0.75, 0.10, 0.08))
	for lx in range(-3, 4):
		for lz in [-2.0, 2.0]:
			k_glass.box_at(cc + Vector3(float(lx) * 2.2, ch - 0.01, float(lz)), Vector3(0.9, 0.04, 0.35), Color(0.98, 0.97, 0.90))   # light panels
	# --- the pump islands: a raised curb, painted ends, two pumps each, the bits on it
	for ix in [-34.5, -25.5]:
		var ic := Vector3(float(ix), 0.0, cc.z)
		k_concrete.box_at(ic + Vector3(0, 0.1, 0), Vector3(1.3, 0.2, 6.2), Color(0.72, 0.72, 0.70))
		for ez in [-1.0, 1.0]:
			k_paint.box_at(ic + Vector3(0, 0.11, float(ez) * 3.05), Vector3(1.32, 0.21, 0.14), Color(0.95, 0.80, 0.10))
			k_metal.cylinder(Transform3D(Basis.IDENTITY, ic + Vector3(0, 0.2, float(ez) * 2.75)), 0.1, 0.1, 0.9, 10, Color(0.95, 0.80, 0.10), true)   # bollard
		for pz in [-1.3, 1.3]:
			_pump(ic + Vector3(0, 0.2, float(pz)), "REGULAR" if float(pz) < 0.0 else "UNLEADED")
		# the bucket with the squeegee, the towel box on its post, a bin
		k_paint.cylinder(Transform3D(Basis.IDENTITY, ic + Vector3(0.35, 0.2, 0.0)), 0.16, 0.14, 0.3, 10, Color(0.15, 0.30, 0.55), true)
		k_metal.box_at(ic + Vector3(0.35, 0.65, 0.05), Vector3(0.03, 0.6, 0.03), Color(0.2, 0.2, 0.2))
		k_metal.box_at(ic + Vector3(0.35, 0.95, 0.05), Vector3(0.05, 0.08, 0.28), Color(0.1, 0.1, 0.1))
		k_metal.box_at(ic + Vector3(-0.3, 0.75, 0.0), Vector3(0.05, 1.1, 0.05), Color(0.6, 0.6, 0.6))
		k_paint.box_at(ic + Vector3(-0.3, 1.35, 0.0), Vector3(0.18, 0.28, 0.3), Color(0.92, 0.92, 0.90))
		k_paint.cylinder(Transform3D(Basis.IDENTITY, ic + Vector3(-0.35, 0.2, -2.2)), 0.25, 0.25, 0.75, 12, Color(0.20, 0.32, 0.22), true)
	# --- the price sign on the corner: a tall pole, the lit box, three price boards
	var ps := Vector3(-12.0, 0.0, 13.5)
	k_metal.cylinder(Transform3D(Basis.IDENTITY, ps), 0.16, 0.16, 8.6, 12, Color(0.55, 0.56, 0.56), true)
	k_concrete.cylinder(Transform3D(Basis.IDENTITY, ps), 0.5, 0.45, 0.5, 12, Color(0.75, 0.75, 0.72), true)
	var face := Vector2(1, -1).normalized()
	var yaw := atan2(face.x, face.y)
	_bx(k_paint, ps + Vector3(0, 7.8, 0), Vector3(3.2, 1.6, 0.45), Color(0.95, 0.95, 0.93), yaw)
	_bx(k_paint, ps + Vector3(0, 7.25, 0), Vector3(3.24, 0.3, 0.48), trim, yaw)
	_bx(k_paint, ps + Vector3(0, 5.9, 0), Vector3(2.6, 2.0, 0.3), Color(0.12, 0.12, 0.13), yaw)
	for sd in [-1.0, 1.0]:
		var f2 := face * float(sd)
		var off := Vector3(f2.x, 0, f2.y)
		_lbl("GAS", ps + Vector3(0, 8.0, 0) + off * 0.24, f2, 0.012, trim)
		var rows := [["REG", "38.9"], ["UNL", "41.9"], ["DSL", "36.9"]]
		for ri in range(3):
			var y := 6.6 - float(ri) * 0.62
			var side := Vector3(f2.y, 0, -f2.x)
			_lbl(rows[ri][0], ps + Vector3(0, y, 0) + off * 0.16 + side * 0.65, f2, 0.0045, Color(0.95, 0.95, 0.9))
			_lbl(rows[ri][1], ps + Vector3(0, y, 0) + off * 0.16 - side * 0.55, f2, 0.0055, Color(1.0, 0.85, 0.3))
	# --- the air and water post, by the bays
	var ap := Vector3(-33.0, 0.0, 29.0)
	k_concrete.box_at(ap + Vector3(0, 0.08, 0), Vector3(0.6, 0.16, 0.6), Color(0.7, 0.7, 0.68))
	k_paint.box_at(ap + Vector3(0, 0.9, 0), Vector3(0.3, 1.5, 0.25), Color(0.80, 0.12, 0.10))
	k_paint.box_at(ap + Vector3(0, 1.75, 0), Vector3(0.36, 0.3, 0.3), Color(0.95, 0.95, 0.92))
	_lbl("AIR", ap + Vector3(0, 1.75, -0.16), Vector2(0, -1), 0.0025, Color(0.75, 0.1, 0.08))
	_tube3(ap + Vector3(0.15, 1.2, 0), ap + Vector3(0.5, 0.05, -0.3), 0.015, Color(0.06, 0.06, 0.06))
	_tube3(ap + Vector3(0.5, 0.05, -0.3), ap + Vector3(0.9, 0.05, 0.4), 0.015, Color(0.06, 0.06, 0.06))
	# --- by the office door: oil-can rack, the pop machine, the ice box, a bench, the tyre rack
	var od := Vector3(-55.0, 0.0, 31.4)
	k_metal.box_at(od + Vector3(2.4, 0.5, -0.25), Vector3(1.2, 1.0, 0.4), Color(0.35, 0.36, 0.38))       # the can rack
	for row in range(3):
		for col in range(6):
			var cp2 := od + Vector3(1.9 + float(col) * 0.19, 0.2 + float(row) * 0.33, -0.3)
			k_paint.cylinder(Transform3D(Basis.IDENTITY, cp2), 0.05, 0.05, 0.15, 8, [Color(0.85, 0.75, 0.10), Color(0.15, 0.30, 0.65), Color(0.70, 0.10, 0.08)][(row + col) % 3], true)
	k_paint.box_at(od + Vector3(-1.8, 0.92, -0.45), Vector3(0.95, 1.84, 0.8), Color(0.78, 0.10, 0.08))   # pop machine
	k_glass.box_at(od + Vector3(-1.95, 1.2, -0.86), Vector3(0.45, 0.9, 0.02), Color(0.9, 0.9, 0.85))
	_lbl("COLD POP", od + Vector3(-1.8, 1.72, -0.87), Vector2(0, -1), 0.0028, Color(1, 1, 1))
	k_paint.box_at(od + Vector3(-3.3, 0.6, -0.5), Vector3(1.4, 1.2, 0.75), Color(0.93, 0.93, 0.95))      # ice box
	_lbl("ICE", od + Vector3(-3.3, 0.8, -0.88), Vector2(0, -1), 0.006, Color(0.15, 0.35, 0.70))
	k_metal.box_at(od + Vector3(-3.3, 0.25, -0.88), Vector3(1.3, 0.05, 0.02), Color(0.6, 0.6, 0.6))
	_bench(Vector2(od.x + 4.5, od.z - 0.6), Vector2(0, -1))
	var tr := Vector3(-36.0, 0.0, 30.6)          # the tyre display: a rack, tyres stood in it
	k_metal.box_at(tr + Vector3(0, 0.45, 0), Vector3(2.6, 0.06, 0.6), Color(0.25, 0.25, 0.25))
	for t in range(6):
		_tyre(tr + Vector3(-1.1 + float(t) * 0.44, 0.38, 0), Basis(Vector3.BACK, PI * 0.5))
	_lbl("TIRES - BATTERIES", tr + Vector3(0, 1.1, -0.32), Vector2(0, -1), 0.0035, Color(0.1, 0.1, 0.1))
	k_paint.box_at(tr + Vector3(0, 1.1, -0.3), Vector3(2.4, 0.3, 0.02), Color(0.95, 0.85, 0.20))
	# --- round the back: the dumpster, drums, the waste-oil tank, old tyres, pallets
	_dumpster(Vector2(-58.0, 49.0), 0.1)
	var drum_cols := [Color(0.20, 0.30, 0.55), Color(0.55, 0.12, 0.10), Color(0.35, 0.30, 0.22), Color(0.45, 0.28, 0.14)]
	for d in range(5):
		_drum(Vector2(-54.0 + float(d % 3) * 0.65, 47.5 + float(d / 3) * 0.65), drum_cols[d % 4])
	_drum(Vector2(-51.0, 48.5), drum_cols[3], true)
	k_paint.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-46.0, 0.75, 48.5)), 0.7, 0.7, 2.6, 16, Color(0.40, 0.40, 0.36), true)   # waste-oil tank
	for sx2 in [-47.0, -45.0]:
		k_metal.box_at(Vector3(float(sx2) - 1.3, 0.25, 48.5), Vector3(0.15, 0.5, 1.2), Color(0.3, 0.3, 0.3))
	for t2 in range(9):
		_tyre(Vector3(-41.5 + float(t2 % 3) * 0.1, 0.11 + float(t2) * 0.23, 49.0 + float(t2 % 2) * 0.08), Basis.IDENTITY)
		if t2 == 4:
			break
	for t3 in range(4):
		_tyre(Vector3(-39.6, 0.11 + float(t3) * 0.23, 48.6), Basis.IDENTITY)
	for pl in range(4):
		k_wood.box_at(Vector3(-37.0, 0.07 + float(pl) * 0.15, 49.0), Vector3(1.2, 0.12, 1.0), Color(0.58, 0.46, 0.30))
	# --- the cars: one at the pump, the tow truck by the bays, one waiting for work
	_car(Vector2(-31.5, 18.6), Vector2(-1, 0), "sedan", Color(0.55, 0.68, 0.80))
	_car(Vector2(-41.0, 26.5), Vector2(1, 0), "wagon", Color(0.45, 0.30, 0.16))
	_tow_truck(Vector2(-20.0, 38.0), Vector2(0, -1))
	_payphone(Vector2(-61.5, 30.0), Vector2(0, -1))
	_paper_box(Vector2(-14.0, 10.6), Vector2(1, 0))
	# --- behind: the cream two-storey block with the fire escape
	_building_poly(rect(-32.0, -14.0, 40.0, 54.0), {"shop": false, "building:levels": "2", "wall": "stucco", "wall_col": Color(0.90, 0.84, 0.58),
		"trim_col": Color(0.40, 0.28, 0.18), "front": N, "roof": "flat"})
	_fire_escape(Vector2(-14.0, 43.0), Vector2(-14.0, 51.0), Vector2(1, 0), 6.2)


## A pump of about 1980: a tall cabinet, the spinning-number face behind glass,
## the lit grade panel on top, the hose and nozzle in its boot.
func _pump(c: Vector3, grade: String) -> void:
	k_paint.rbox(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.82, 0)), Vector3(0.62, 1.64, 0.9), Color(0.94, 0.94, 0.92), 0.05)
	k_paint.box_at(c + Vector3(0, 0.3, 0), Vector3(0.64, 0.12, 0.92), Color(0.80, 0.14, 0.10))
	k_paint.box_at(c + Vector3(0, 1.82, 0), Vector3(0.5, 0.36, 0.8), Color(0.95, 0.95, 0.92))
	for sd in [-1.0, 1.0]:
		var fx := float(sd) * 0.315
		k_glass.box_at(c + Vector3(fx, 1.18, 0), Vector3(0.01, 0.5, 0.62), Color(0.12, 0.12, 0.12))           # the face
		for r in range(2):
			_lbl(["12.40", "14.2"][r], c + Vector3(fx + float(sd) * 0.01, 1.32 - float(r) * 0.2, 0.05), Vector2(float(sd), 0), 0.0022, Color(1.0, 0.95, 0.85), 48)
		_lbl(grade, c + Vector3(fx * 0.8 + float(sd) * 0.006, 1.82, 0), Vector2(float(sd), 0), 0.0024, Color(0.75, 0.1, 0.08), 48)
		k_metal.box_at(c + Vector3(fx + float(sd) * 0.04, 0.95, 0.3), Vector3(0.08, 0.22, 0.12), Color(0.2, 0.2, 0.2))   # the boot
		k_metal.box_at(c + Vector3(fx + float(sd) * 0.1, 1.0, 0.3), Vector3(0.05, 0.05, 0.22), Color(0.70, 0.70, 0.68))  # the nozzle
		_tube3(c + Vector3(fx, 1.5, 0.35), c + Vector3(fx + float(sd) * 0.18, 0.35, 0.42), 0.02, Color(0.05, 0.05, 0.05))
		_tube3(c + Vector3(fx + float(sd) * 0.18, 0.35, 0.42), c + Vector3(fx + float(sd) * 0.06, 0.95, 0.32), 0.02, Color(0.05, 0.05, 0.05))


func _fire_escape(a: Vector2, b: Vector2, out: Vector2, top: float) -> void:
	var t := (b - a).normalized()
	var col := Color(0.18, 0.18, 0.18)
	var lp := a.lerp(b, 0.5) + out * 0.7
	for fl in [3.1]:
		var y := float(fl)
		k_metal.box_at(Vector3(lp.x, y, lp.y), Vector3(1.4 if absf(out.x) > 0.5 else 4.0, 0.06, 4.0 if absf(out.x) > 0.5 else 1.4), col)
		for k in range(9):
			var rp := a.lerp(b, 0.25 + float(k) * 0.0625) + out * 1.35
			k_metal.box_at(Vector3(rp.x, y + 0.5, rp.y), Vector3(0.03, 1.0, 0.03), col)
		var r0 := a.lerp(b, 0.25) + out * 1.35
		var r1 := a.lerp(b, 0.75) + out * 1.35
		_tube3(Vector3(r0.x, y + 1.0, r0.y), Vector3(r1.x, y + 1.0, r1.y), 0.025, col)
		# the drop ladder
		var lad := a.lerp(b, 0.72) + out * 1.2
		for sd in [-0.22, 0.22]:
			var lq := lad + t * float(sd)
			_tube3(Vector3(lq.x, 0.9, lq.y), Vector3(lq.x, y, lq.y), 0.02, col)
		for rung in range(7):
			var ry := 1.0 + float(rung) * 0.3
			_tube3(Vector3(lad.x - t.x * 0.22, ry, lad.y - t.y * 0.22), Vector3(lad.x + t.x * 0.22, ry, lad.y + t.y * 0.22), 0.012, col)
	# the door out onto it
	var dp := a.lerp(b, 0.4)
	_board(dp - t * 0.45, dp + t * 0.45, out, 3.1, 5.2, 0.05, Color(0.40, 0.28, 0.18))


## The station's own tow truck: a pickup with the boom and hook on the back.
func _tow_truck(p: Vector2, fwd: Vector2) -> void:
	_car(p, fwd, "pickup", Color(0.92, 0.75, 0.15))
	var b := Basis.looking_at(Vector3(fwd.x, 0, fwd.y), Vector3.UP)
	var o := Vector3(p.x, 0, p.y)
	k_metal.box(Transform3D(b, o + b * Vector3(0, 1.4, 1.6)), Vector3(0.5, 0.9, 0.3), Color(0.25, 0.25, 0.25))          # the mast
	k_metal.box(Transform3D(b * Basis(Vector3.RIGHT, 0.5), o + b * Vector3(0, 1.75, 2.3)), Vector3(0.18, 0.18, 1.6), Color(0.85, 0.65, 0.12))   # the boom
	_tube3(o + b * Vector3(0, 1.4, 3.0), o + b * Vector3(0, 0.6, 3.0), 0.015, Color(0.1, 0.1, 0.1))
	k_metal.box(Transform3D(b, o + b * Vector3(0, 0.55, 3.0)), Vector3(0.12, 0.12, 0.08), Color(0.2, 0.2, 0.2))
	k_paint.cylinder(Transform3D(Basis.IDENTITY, o + b * Vector3(0, 1.62, -0.2)), 0.1, 0.1, 0.14, 10, Color(0.95, 0.55, 0.05), true)   # amber beacon


## Fronts the kit doesn't do: the gas station's office and two bays.
func _front_custom(a: Vector2, b: Vector2, out: Vector2, t: Dictionary, h: float, trim: Color) -> bool:
	match String(t.get("front_kind", "")):
		"burger":
			_burger_front(a, b, out)
			return true
		"church":
			_church_front(a, b, out)
			return true
		"townhall":
			_townhall_front(a, b, out, h)
			return true
		"fire":
			_firehall_front(a, b, out, h)
			return true
		"station":
			var d := b - a
			var tt := d.normalized()
			var L := d.length()
			var split := a + tt * L * 0.34                  # office | bays
			# the office: big windows, the glass door, OPEN in the window
			_storefront_plain(a + tt * 0.3, split - tt * 0.3, out, trim)
			# the bays: two roll-up doors with a row of windows, the frames between
			for bi in range(2):
				var b0 := split + tt * (float(bi) * L * 0.33 + 0.4)
				var b1 := split + tt * (float(bi + 1) * L * 0.33 - 0.4)
				_board(b0 - tt * 0.15, b1 + tt * 0.15, out, 0.0, 3.85, 0.03, Color(0.30, 0.30, 0.30))
				for pnl in range(6):
					var y0 := 0.05 + float(pnl) * 0.62
					var col := Color(0.88, 0.88, 0.86) if pnl != 3 else Color(0.20, 0.24, 0.28)
					_board(b0, b1, out, y0, y0 + 0.58, 0.06, col)
				k_trim.quad(_v3(b0 + out * 0.07, 2.0), _v3(b1 + out * 0.07, 2.0), _v3(b1 + out * 0.07, 2.04), _v3(b0 + out * 0.07, 2.04), Color(0.4, 0.4, 0.4), Vector3(out.x, 0, out.y))
				_lbl(str(bi + 1), _v3((b0 + b1) * 0.5 + out * 0.08, 3.55), out, 0.004, Color(0.1, 0.1, 0.1))
			# the sign band right along the front
			_board(a, b, out, h - 1.0, h - 0.2, 0.1, trim)
			_lbl("SERVICE  -  REPAIRS  -  TOWING", _v3((a + b) * 0.5 + out * 0.115, h - 0.6), out, 0.0052, Color(1, 1, 1))
			return true
	return false


## A plain office front: window wall, a glass door, an OPEN sign.
func _storefront_plain(a: Vector2, b: Vector2, out: Vector2, trim: Color) -> void:
	var t := (b - a).normalized()
	var L := a.distance_to(b)
	var oh := Vector3(out.x, 0, out.y)
	_board(a, b, out, 0.0, 0.7, 0.04, Color(0.55, 0.53, 0.50))
	k_glass.quad(_v3(a + out * 0.02, 0.7), _v3(b + out * 0.02, 0.7), _v3(b + out * 0.02, 2.6), _v3(a + out * 0.02, 2.6), Color(0.10, 0.13, 0.16), oh)
	for k in range(4):
		var c := a.lerp(b, float(k) / 3.0)
		_board(c - t * 0.04, c + t * 0.04, out, 0.7, 2.6, 0.06, Color(0.6, 0.6, 0.58))
	_board(a, b, out, 2.6, 2.7, 0.06, Color(0.6, 0.6, 0.58))
	var dc := a + t * (L - 0.7)
	_board(dc - t * 0.45, dc + t * 0.45, out, 0.0, 2.2, 0.05, Color(0.5, 0.5, 0.48))
	k_glass.quad(_v3(dc - t * 0.38 + out * 0.06, 0.1), _v3(dc + t * 0.38 + out * 0.06, 0.1), _v3(dc + t * 0.38 + out * 0.06, 2.1), _v3(dc - t * 0.38 + out * 0.06, 2.1), Color(0.10, 0.12, 0.14), oh)
	var sc := a + t * 1.2 + out * 0.04
	k_paint.quad(_v3(sc, 1.7), _v3(sc + t * 0.7, 1.7), _v3(sc + t * 0.7, 2.0), _v3(sc, 2.0), Color(0.85, 0.12, 0.08), oh)
	_lbl("OPEN", _v3(sc + t * 0.35 + out * 0.01, 1.85), out, 0.0025, Color(1, 1, 1))


func _street_furniture() -> void:
	_poles_and_stops()
	_traffic_lights(Vector2.ZERO)
	# cars parked along Main Street, nose to tail, gaps at the corner and the driveways
	for sd in [-1.0, 1.0]:
		var x := -160.0
		while x < 160.0:
			x += _rng.randf_range(5.8, 7.5)
			if absf(x) < 16.0 or _no_walk(Vector2(x, float(sd) * 8.0)) or _rng.randf() < 0.35:
				continue
			_car(Vector2(x, float(sd) * 5.6), Vector2(float(sd), 0) * -1.0)
		# benches, bins, and the odd newspaper box down the main block
		var bx := -100.0
		while bx < 100.0:
			bx += _rng.randf_range(16.0, 26.0)
			var bp := Vector2(bx, float(sd) * 8.2)
			if absf(bx) < 10.0 or _no_walk(bp):
				continue
			var r := _rng.randf()
			if r < 0.4:
				_bin(bp)
			elif r < 0.7:
				_bench(bp + Vector2(0, float(sd) * 0.3), Vector2(0, -float(sd)))
			else:
				_paper_box(bp, Vector2(1, 0))
	_payphone(Vector2(8.2, 8.4), Vector2(-1, 0))
	_litter()
	# the paper, leaves and the odd bag the wind pushes round town
	var wl = load("res://scripts/wind_litter.gd").new()
	wl.name = "WindLitter"
	wl.ground_y = Callable(self, "_litter_ground")
	wl.blocked = Callable(self, "_litter_blocked")
	wl.area = 120.0
	add_child(wl)


## The ground under a bit of litter: up on the sidewalk, down on the road, the lots.
func _litter_ground(p: Vector2) -> float:
	for r in _roads:
		if not bool(r["walks"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		var w: float = r["w"]
		for j in range(pts.size() - 1):
			var dd := p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1]))
			if dd < w * 0.5:
				return 0.03
			if dd < w * 0.5 + WALK_W and not _no_walk(p):
				return CURB_H
	return 0.02


func _litter_blocked(p: Vector2) -> bool:
	return _in_building(p, 0.0)


## Trash where trash ends up: along the curbs, in the corners of the lots, by the bins.
func _litter() -> void:
	var cols := [Color(0.93, 0.92, 0.86), Color(0.78, 0.77, 0.72), Color(0.75, 0.12, 0.10), Color(0.85, 0.75, 0.15), Color(0.20, 0.35, 0.65), Color(0.35, 0.25, 0.15)]
	for k in range(420):
		var p := Vector2.ZERO
		var y := 0.0
		var where := _rng.randf()
		if where < 0.55:                     # the gutters along Main and Cross
			if _rng.randf() < 0.7:
				p = Vector2(_rng.randf_range(-165, 165), (7.0 - 0.25) * (1.0 if _rng.randf() < 0.5 else -1.0))
			else:
				p = Vector2((5.0 - 0.25) * (1.0 if _rng.randf() < 0.5 else -1.0), _rng.randf_range(-110, 110))
			y = 0.035
		elif where < 0.8:                   # the sidewalks
			if _rng.randf() < 0.7:
				p = Vector2(_rng.randf_range(-165, 165), _rng.randf_range(7.2, 8.7) * (1.0 if _rng.randf() < 0.5 else -1.0))
			else:
				p = Vector2(_rng.randf_range(5.2, 6.7) * (1.0 if _rng.randf() < 0.5 else -1.0), _rng.randf_range(-110, 110))
			y = CURB_H + 0.005
		else:                               # the lots and the back alleys
			p = Vector2(_rng.randf_range(-105, 120), _rng.randf_range(-58, 56))
			if _in_building(p, 0.5) or _road_clear(p, -1) < 2.5:
				continue
			y = 0.03
		if _in_building(p, 0.0):
			continue
		var kind := _rng.randi() % 6
		var yaw := _rng.randf() * TAU
		match kind:
			0, 1:   # paper: a flat scrap
				var sz := Vector2(_rng.randf_range(0.08, 0.3), _rng.randf_range(0.08, 0.25))
				_bx(k_paint, Vector3(p.x, y + 0.003, p.y), Vector3(sz.x, 0.004, sz.y), cols[_rng.randi() % 2], yaw)
			2:      # a crushed can on its side
				k_metal.cylinder(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, PI * 0.5), Vector3(p.x, y + 0.032, p.y)), 0.032, 0.03, 0.11, 8, cols[2 + _rng.randi() % 3], true)
			3:      # a bottle
				k_glass.cylinder(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, PI * 0.5), Vector3(p.x, y + 0.035, p.y)), 0.035, 0.015, 0.24, 8, Color(0.30, 0.22, 0.08), true)
			4:      # a coffee cup
				k_paint.cylinder(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, PI * 0.5), Vector3(p.x, y + 0.04, p.y)), 0.04, 0.03, 0.1, 8, Color(0.92, 0.90, 0.85), true)
			5:      # a wrapper / a cigarette pack
				_bx(k_paint, Vector3(p.x, y + 0.01, p.y), Vector3(0.09, 0.02, 0.055), cols[_rng.randi() % cols.size()], yaw)
	# dead leaves blown into the corners along the curbs
	for k2 in range(600):
		var lp := Vector2(_rng.randf_range(-165, 165), (7.0 - _rng.randf_range(0.05, 0.6)) * (1.0 if _rng.randf() < 0.5 else -1.0))
		_bx(k_paint, Vector3(lp.x, 0.034, lp.y), Vector3(0.09, 0.003, 0.07), [Color(0.62, 0.36, 0.10), Color(0.70, 0.52, 0.12), Color(0.45, 0.22, 0.08), Color(0.55, 0.15, 0.06)][_rng.randi() % 4], _rng.randf() * TAU)


func _trees() -> void:
	pass
