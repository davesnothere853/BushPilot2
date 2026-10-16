extends RefCounted
## The region's ground as the vegetation sees it (DESIGN_NOTES 231): the same
## interface as terrain.gd (heights, normals, the forest / creek / bog / burn
## fields on a 40 m grid, lakes, clearings, water) read off the meshes the
## region actually draws, so every tree stands on the ground you see.

const CELL := 40.0
const NO_WATER := -1.0e9

var n := 800
var size := 32000.0
var half := 16000.0
var heights := PackedFloat32Array()
var forest := PackedFloat32Array()
var creek := PackedFloat32Array()
var bog := PackedFloat32Array()
var burn := PackedFloat32Array()
var lakes: Array[Dictionary] = []
var strips: Array = []
var clearings: Array = []        # Vector3(x, z, r)
var digs: Array = []
var R: Node
var _near: Array
var _far: Array
var _near_rect: Rect2
var _town: Array
var _town_rect: Rect2
var _noise := FastNoiseLite.new()


func setup(region: Node) -> void:
	R = region
	size = float(region.SIZE)
	half = size * 0.5
	n = int(size / CELL)
	_near = region.grids.get("GroundNear", [])
	_far = region.grids.get("Ground", [])
	_town = region.grids.get("GroundTown", [])
	if not _town.is_empty():
		_town_rect = Rect2(float(_town[0]), float(_town[1]), float(_town[2] - 1) * float(_town[4]), float(_town[3] - 1) * float(_town[4])).grow(-8.0)
	if not _near.is_empty():
		_near_rect = Rect2(float(_near[0]), float(_near[1]), float(_near[2] - 1) * float(_near[4]), float(_near[3] - 1) * float(_near[4])).grow(-float(_near[4]) * 2.0)
	for l in region._lakes:
		lakes.append({"pos": l[0], "radius": float(l[1]), "level": float(l[2])})
	for f in region._flats:
		clearings.append(Vector3((f[0] as Vector2).x, (f[0] as Vector2).y, float(f[1]) + 10.0))
	_noise.seed = 77
	_noise.frequency = 1.0 / 900.0
	var vn := n + 1
	heights.resize(vn * vn)
	forest.resize(vn * vn)
	creek.resize(vn * vn)
	bog.resize(vn * vn)
	burn.resize(vn * vn)
	for j in range(vn):
		for i in range(vn):
			var x := -half + float(i) * CELL
			var z := -half + float(j) * CELL
			var idx := j * vn + i
			heights[idx] = height_at(x, z)
			var fv := _fields(x, z)            # floor_in, gorge, channel
			var h := heights[idx]
			# fields and meadows on the valley floors (woodlots in them), forest
			# everywhere else up to the treeline (flora.gd keeps it off cliffs)
			var wood := smoothstep(0.55, 0.7, _noise.get_noise_2d(x * 4.0, z * 4.0) * 0.5 + 0.5)
			var open_floor := smoothstep(0.5, 0.85, fv.x) * (1.0 - wood)
			forest[idx] = clampf(1.0 - open_floor, 0.0, 1.0) if h > 1.0 else 0.0
			creek[idx] = fv.z
			var flat := fv.x * (1.0 - fv.z)
			bog[idx] = flat * smoothstep(0.6, 0.85, _noise.get_noise_2d(x * 2.0 + 500.0, z * 2.0) * 0.5 + 0.5)
			burn[idx] = smoothstep(0.78, 0.9, _noise.get_noise_2d(x * 0.7 - 900.0, z * 0.7 + 300.0) * 0.5 + 0.5)


func _sample(g: Array, k: int, x: float, z: float) -> Variant:
	var step: float = g[4]
	var nx: int = g[2]
	var nz: int = g[3]
	var fx := clampf((x - float(g[0])) / step, 0.0, float(nx) - 1.001)
	var fz := clampf((z - float(g[1])) / step, 0.0, float(nz) - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var arr = g[k]
	var a = arr[j * nx + i]
	var b = arr[j * nx + i + 1]
	var c = arr[(j + 1) * nx + i]
	var d = arr[(j + 1) * nx + i + 1]
	# the same two triangles the mesh draws (split corner a -> d)
	if tx + tz <= 1.0 and k == 5:
		return a + (b - a) * tx + (c - a) * tz
	if k == 5:
		return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)
	return lerp(lerp(a, b, tx), lerp(c, d, tx), tz)


func _grid_at(x: float, z: float) -> Array:
	if not _town.is_empty() and _town_rect.has_point(Vector2(x, z)):
		return _town
	return _near if (not _near.is_empty() and _near_rect.has_point(Vector2(x, z))) else _far


func _fields(x: float, z: float) -> Vector3:
	var g := _grid_at(x, z)
	if g.is_empty():
		return Vector3.ZERO
	return _sample(g, 6, x, z)


func height_at(x: float, z: float) -> float:
	var g := _grid_at(x, z)
	if g.is_empty():
		return 0.0
	return float(_sample(g, 5, x, z))


func height_at_base(x: float, z: float) -> float:
	return height_at(x, z)


func ground_level_at(x: float, z: float) -> float:
	return height_at(x, z)


func normal_at(x: float, z: float) -> Vector3:
	var e := 4.0
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func forest_at(x: float, z: float) -> float:
	var i := clampi(int(round((x + half) / CELL)), 0, n)
	var j := clampi(int(round((z + half) / CELL)), 0, n)
	return forest[j * (n + 1) + i]


func water_level_at(x: float, z: float) -> float:
	return _water_level(x, z, height_at(x, z))


func _water_level(x: float, z: float, h: float) -> float:
	for lake in lakes:
		var c: Vector2 = lake["pos"]
		var r: float = float(lake["radius"]) * 1.25
		if (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y) < r * r and h < float(lake["level"]):
			return float(lake["level"])
	if h < 0.5 and R._coast_side(x, z) > 0.0:
		return 0.0
	if _fields(x, z).z > 0.88:
		return h + 0.5          # in the river
	return NO_WATER


func in_strip_clearing(_x: float, _z: float) -> bool:
	return false


func strip_index_at(_x: float, _z: float, _m: float = 0.0) -> int:
	return -1


func clear_spot(x: float, z: float, radius: float) -> void:
	clearings.append(Vector3(x, z, radius))


func is_cleared(x: float, z: float, margin: float = 0.0) -> bool:
	for c in clearings:
		var r: float = c.z + margin * 0.5
		if (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y) < r * r:
			return true
	return false


func blocked_by_building(_p: Vector3, _r: float = 0.0, _skip = null) -> bool:
	return false


func mud_at(_x: float, _z: float) -> float:
	return 0.0
