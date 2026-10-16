extends Node3D
## A tile of diggable ground, Out of Ore style: the island's
## terrain is cut out here and replaced by a fine heightmap (half-metre
## cells) you can dig into and pile up. Underneath the turf is overburden
## (gravel and silt with no gold), then the pay streak (gold-bearing gravel,
## richer in places), then bedrock, which a bucket won't bite.
##
## Its edges start on the island's ground so it joins exactly; dug right up to
## an edge, the neighbouring tile is made too and the shared edge kept in step
## (prospect.gd).

const Flora = preload("res://scripts/flora.gd")
const TerrainScript = preload("res://scripts/terrain.gd")
const DIG_SHADER = preload("res://shaders/dig.gdshader")
## One material for every tile, so the seasons (snow uniforms) reach them all.
static var shared_mat: ShaderMaterial

const RES := 0.5                 # metres a cell
const N := 48                    # cells a side (24 m): the world is tiled in these
const SWELL := 1.25              # dug ground bulks up this much in a pile

var claim := ""                  # claim name
var x0 := 0.0                    # world corner
var z0 := 0.0
var heights := PackedFloat32Array()
var orig := PackedFloat32Array()
var grade := PackedFloat32Array()   # grams of gold in a cubic metre of pay gravel, per vertex
var ground4 := PackedFloat32Array() # forest, vary, bog, burn per vertex (the island's look)
var creek_v := PackedFloat32Array() # creek field per vertex
var pay_top := PackedFloat32Array() # depth the gold-bearing gravel starts, per vertex
var bedrock := PackedFloat32Array() # depth of bedrock (gold sits just above it), per vertex
var _mi: MeshInstance3D
var _mat: StandardMaterial3D
var dirty := false
var modified := false            # ground actually moved here: worth saving


## Lay out a patch centred on `c`, sampling the island's ground for the start.
## A tile whose corner is (cx0, cz0). `geo` answers, for a spot, what's in the
## ground there: [grams of gold a cubic metre in the pay gravel, depth the pay
## starts, depth of bedrock].
func setup(tile_name: String, cx0: float, cz0: float, terrain: RefCounted, geo: Callable) -> void:
	claim = tile_name
	x0 = cx0
	z0 = cz0
	var vn := N + 1
	heights.resize(vn * vn)
	orig.resize(vn * vn)
	grade.resize(vn * vn)
	pay_top.resize(vn * vn)
	bedrock.resize(vn * vn)
	ground4.resize(vn * vn * 4)
	creek_v.resize(vn * vn)
	for j in range(vn):
		for i in range(vn):
			var x := x0 + i * RES
			var z := z0 + j * RES
			var h: float = terrain.height_at_base(x, z)
			var idx := j * vn + i
			heights[idx] = h
			orig[idx] = h
			var g: Array = geo.call(x, z)
			grade[idx] = g[0]
			pay_top[idx] = g[1]
			bedrock[idx] = g[2]
			# The island's own ground colours carry straight across the tile
			# (a bare test ground has none of these fields).
			var full := "forest" in terrain
			ground4[idx * 4] = Flora.field(terrain, terrain.forest, x, z) if full else 0.0
			ground4[idx * 4 + 1] = TerrainScript.hash01(int((x + float(terrain.half if full else 0.0)) / 40.0), int((z + float(terrain.half if full else 0.0)) / 40.0), 9)
			ground4[idx * 4 + 2] = Flora.field(terrain, terrain.bog, x, z) if full else 0.0
			ground4[idx * 4 + 3] = Flora.field(terrain, terrain.burn, x, z) if full else 0.0
			creek_v[idx] = Flora.field(terrain, terrain.creek, x, z) if full else 0.0





func contains(x: float, z: float) -> bool:
	return x > x0 and z > z0 and x < x0 + N * RES and z < z0 + N * RES


func rect() -> Vector4:
	return Vector4(x0, z0, x0 + N * RES, z0 + N * RES)


func height(x: float, z: float) -> float:
	var fx := clampf((x - x0) / RES, 0.0, float(N) - 0.001)
	var fz := clampf((z - z0) / RES, 0.0, float(N) - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var vn := N + 1
	var idx := j * vn + i
	var h00 := heights[idx]
	var h10 := heights[idx + 1]
	var h01 := heights[idx + vn]
	var h11 := heights[idx + vn + 1]
	if tx > tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


func normal(x: float, z: float) -> Vector3:
	var e := RES
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)).normalized()


## What's at this depth here: "turf", "overburden", "pay", "bedrock".
func layer_at(i: int, j: int, h: float) -> String:
	var d: float = orig[j * (N + 1) + i] - h
	if d < 0.25:
		return "turf"
	var idx2 := j * (N + 1) + i
	if d < pay_top[idx2]:
		return "overburden"
	if d < bedrock[idx2]:
		return "pay"
	return "bedrock"


## Dig out about `want` cubic metres round `c` (a bucket's bite). Returns
## {"over": m3, "pay": m3, "g": grams of gold in it, "bedrock": bool}.
func dig(c: Vector3, radius: float, want: float) -> Dictionary:
	var out := {"over": 0.0, "pay": 0.0, "g": 0.0, "bedrock": false}
	var vn := N + 1
	var cells: Array = []
	var ci := int(round((c.x - x0) / RES))
	var cj := int(round((c.z - z0) / RES))
	var rc := int(ceil(radius / RES))
	var wsum := 0.0
	for j in range(maxi(cj - rc, 0), mini(cj + rc, N) + 1):
		for i in range(maxi(ci - rc, 0), mini(ci + rc, N) + 1):
			var d := Vector2(x0 + i * RES - c.x, z0 + j * RES - c.z).length()
			if d > radius:
				continue
			var w := 1.0 - (d / radius) * (d / radius)
			cells.append([i, j, w])
			wsum += w
	if cells.is_empty():
		return out
	var cell_area := RES * RES
	var depth := want / (wsum * cell_area)
	for cw in cells:
		var i: int = cw[0]
		var j: int = cw[1]
		var idx := j * vn + i
		var h := heights[idx]
		var floor_h: float = orig[idx] - bedrock[idx]
		var take := minf(depth * float(cw[2]), maxf(h - floor_h, 0.0))
		if take < depth * float(cw[2]) - 0.001:
			out["bedrock"] = true
		if take <= 0.0:
			continue
		# Split what came out between the layers it went through.
		var top_d: float = orig[idx] - h
		var bot_d := top_d + take
		var pay := maxf(minf(bot_d, bedrock[idx]) - maxf(top_d, pay_top[idx]), 0.0)
		var over := take - pay
		out["over"] = float(out["over"]) + over * cell_area
		out["pay"] = float(out["pay"]) + pay * cell_area
		out["g"] = float(out["g"]) + pay * cell_area * grade[idx]
		heights[idx] = h - take
	_slump(ci, cj, rc + 3)
	modified = true
	dirty = true
	return out


## Grade toward one level (a dozer blade): inside the disc, ground above
## `target` is cut (if `allow_cut`) and ground below is filled from
## `fill_m3`. The edge feathers into the ground around, so overlapping
## passes leave a smooth bench. Returns what came out and what went in.
func level(c: Vector3, radius: float, target: float, fill_m3: float, cut_m3: float = 1.0e9) -> Dictionary:
	var out := {"over": 0.0, "pay": 0.0, "g": 0.0, "filled": 0.0, "bedrock": false}
	var vn := N + 1
	var ci := int(round((c.x - x0) / RES))
	var cj := int(round((c.z - z0) / RES))
	var rc := int(ceil(radius / RES))
	var cell_area := RES * RES
	# First find what every cell wants, then scale it all to the budgets,
	# so a short budget thins the whole pass instead of starving one side.
	var cuts: Array = []
	var fills: Array = []
	var cut_want := 0.0
	var fill_want := 0.0
	for j in range(maxi(cj - rc, 0), mini(cj + rc, N) + 1):
		for i in range(maxi(ci - rc, 0), mini(ci + rc, N) + 1):
			var d := Vector2(x0 + i * RES - c.x, z0 + j * RES - c.z).length()
			if d > radius:
				continue
			var w := clampf(1.6 * (1.0 - (d / radius) * (d / radius)), 0.0, 1.0)
			var idx := j * vn + i
			var h := heights[idx]
			var want := lerpf(h, target, w)
			if want < h:
				var floor_h: float = orig[idx] - bedrock[idx]
				var take := minf(minf(h - want, 0.30 * w), maxf(h - floor_h, 0.0))
				if take <= 0.0 and h - want > 0.02:
					out["bedrock"] = true
				if take > 0.0:
					cuts.append([idx, take])
					cut_want += take * cell_area
			elif want > h:
				var put := minf(want - h, 0.30 * w)
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
		var h2 := heights[idx2]
		var top_d: float = orig[idx2] - h2
		var bot_d := top_d + take2
		var pay := maxf(minf(bot_d, bedrock[idx2]) - maxf(top_d, pay_top[idx2]), 0.0)
		out["pay"] = float(out["pay"]) + pay * cell_area
		out["over"] = float(out["over"]) + (take2 - pay) * cell_area
		out["g"] = float(out["g"]) + pay * cell_area * grade[idx2]
		heights[idx2] = h2 - take2
	for fw2 in fills:
		var put2 := float(fw2[1]) * fill_k
		if put2 > 0.0:
			heights[fw2[0]] += put2
			out["filled"] = float(out["filled"]) + put2 * cell_area
	_slump(ci, cj, rc + 2)
	modified = true
	dirty = true
	return out


## Pile `vol` cubic metres (as dug, it bulks up) round `c`, as a cone.
func deposit(c: Vector3, vol: float) -> void:
	var vn := N + 1
	var radius := 1.4
	var ci := int(round((c.x - x0) / RES))
	var cj := int(round((c.z - z0) / RES))
	var rc := int(ceil(radius / RES))
	var cells: Array = []
	var wsum := 0.0
	for j in range(maxi(cj - rc, 0), mini(cj + rc, N) + 1):
		for i in range(maxi(ci - rc, 0), mini(ci + rc, N) + 1):
			var d := Vector2(x0 + i * RES - c.x, z0 + j * RES - c.z).length()
			if d > radius:
				continue
			var w := 1.0 - d / radius
			cells.append([i, j, w])
			wsum += w
	if cells.is_empty():
		return
	var add := vol * SWELL / (wsum * RES * RES)
	for cw in cells:
		var idx: int = int(cw[1]) * vn + int(cw[0])
		heights[idx] += add * float(cw[2])
	_slump(ci, cj, rc + 6)
	modified = true
	dirty = true


## Loose ground won't stand steeper than about 38 degrees: let it slide down.
func _slump(ci: int, cj: int, r: int) -> void:
	var vn := N + 1
	var max_step := RES * 1.15        # fresh-dug banks stand steep (about 50 degrees)
	for _pass in range(6):
		var moved := false
		for j in range(maxi(cj - r, 0), mini(cj + r, N) + 1):
			for i in range(maxi(ci - r, 0), mini(ci + r, N) + 1):
				var idx := j * vn + i
				for nb in [idx + 1, idx - 1, idx + vn, idx - vn]:
					var ni: int = nb
					var nx := ni % vn
					var nz := ni / vn
					if ni < 0 or ni >= vn * vn or absi(nx - (idx % vn)) > 1:
						continue
					var diff := heights[idx] - heights[ni]
					if diff > max_step:
						var floor_n: float = orig[ni] - bedrock[ni]
						var mv := (diff - max_step) * 0.5
						heights[idx] -= mv
						heights[ni] = maxf(heights[ni] + mv, floor_n)
						moved = true
		if not moved:
			break


# ------------------------------------------------------------------------------
#  The ground you see (shaders/dig.gdshader draws it)
# ------------------------------------------------------------------------------
func build_mesh() -> void:
	if shared_mat == null:
		shared_mat = ShaderMaterial.new()
		shared_mat.shader = DIG_SHADER
	var vn := N + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom := PackedFloat32Array()
	verts.resize(vn * vn)
	norms.resize(vn * vn)
	cols.resize(vn * vn)
	uvs.resize(vn * vn)
	custom.resize(vn * vn * 4)
	for j in range(vn):
		for i in range(vn):
			var idx := j * vn + i
			verts[idx] = Vector3(x0 + i * RES, heights[idx], z0 + j * RES) - position
			var im := maxi(i - 1, 0)
			var ip := mini(i + 1, N)
			var jm := maxi(j - 1, 0)
			var jp := mini(j + 1, N)
			var sx := (heights[j * vn + ip] - heights[j * vn + im]) / (RES * float(ip - im))
			var sz := (heights[jp * vn + i] - heights[jm * vn + i]) / (RES * float(jp - jm))
			norms[idx] = Vector3(-sx, 1.0, -sz).normalized()
			cols[idx] = Color(ground4[idx * 4], ground4[idx * 4 + 1], ground4[idx * 4 + 2], ground4[idx * 4 + 3])
			uvs[idx] = Vector2(creek_v[idx], orig[idx] - heights[idx])
			custom[idx * 4] = pay_top[idx]
			custom[idx * 4 + 1] = bedrock[idx]
			custom[idx * 4 + 2] = grade[idx]
			custom[idx * 4 + 3] = 0.0
	var indices := PackedInt32Array()
	indices.resize(N * N * 6)
	var w := 0
	for j in range(N):
		for i in range(N):
			var a := j * vn + i
			indices[w] = a
			indices[w + 1] = a + 1
			indices[w + 2] = a + vn + 1
			indices[w + 3] = a
			indices[w + 4] = a + vn + 1
			indices[w + 5] = a + vn
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.surface_set_material(0, shared_mat)
	if _mi == null:
		_mi = MeshInstance3D.new()
		_mi.name = "DigGround"
		add_child(_mi)
	_mi.mesh = mesh
	dirty = false


func _process(_delta: float) -> void:
	if dirty:
		build_mesh()
