extends Node3D
## Draws ground.gd: the square in 24 m chunk meshes at the full half-metre
## resolution, one shader for everything. When the ground is dug or graded,
## only the chunks it marked dirty are rebuilt - no tiles, no popping.
## Also builds the dark cut edge where the square falls away into the void.

const MeshKit = preload("res://scripts/meshkit.gd")
const GROUND_SHADER = preload("res://shaders/ground.gdshader")

var ground: RefCounted
var _mat: ShaderMaterial
var _chunks := {}                  # Vector2i -> MeshInstance3D
var _zone_cache := PackedColorArray()   # per-vertex zone weights (static)
var _wet_cache := PackedFloat32Array()  # per-vertex natural wetness (static)
var budget_ms := 6.0               # rebuild time allowed a frame


func setup(g: RefCounted) -> void:
	ground = g
	_mat = ShaderMaterial.new()
	_mat.shader = GROUND_SHADER
	var vn: int = g.FN + 1
	_zone_cache.resize(vn * vn)
	_wet_cache.resize(vn * vn)
	for j in range(vn):
		var z: float = -g.SQ + j * g.FRES
		for i in range(vn):
			var x: float = -g.SQ + i * g.FRES
			_zone_cache[j * vn + i] = g.zone4(x, z)
			_wet_cache[j * vn + i] = g.wet_at(x, z)
	for cj in range(g.CHUNKS):
		for ci in range(g.CHUNKS):
			_build_chunk(Vector2i(ci, cj))
	pass   # BP2 demo: open plain past the edge (world_look.plain)


func _build_chunk(key: Vector2i) -> void:
	var g: RefCounted = ground
	var vn: int = g.FN + 1
	var cc: int = g.CHUNK_CELLS
	var i0: int = key.x * cc
	var j0: int = key.y * cc
	var cvn := cc + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(cvn * cvn)
	norms.resize(cvn * cvn)
	cols.resize(cvn * cvn)
	uvs.resize(cvn * cvn)
	var heights: PackedFloat32Array = g.fh
	var orig: PackedFloat32Array = g.orig
	var fres: float = g.FRES
	var sq: float = g.SQ
	var fn: int = g.FN
	for j in range(cvn):
		var gj := j0 + j
		var z := -sq + gj * fres
		for i in range(cvn):
			var gi := i0 + i
			var gidx := gj * vn + gi
			var idx := j * cvn + i
			verts[idx] = Vector3(-sq + gi * fres, heights[gidx], z)
			# Normals from the global grid, so chunk borders never seam.
			var im := maxi(gi - 1, 0)
			var ip := mini(gi + 1, fn)
			var jm := maxi(gj - 1, 0)
			var jp := mini(gj + 1, fn)
			var sx := (heights[gj * vn + ip] - heights[gj * vn + im]) / (fres * float(ip - im))
			var sz := (heights[jp * vn + gi] - heights[jm * vn + gi]) / (fres * float(jp - jm))
			norms[idx] = Vector3(-sx, 1.0, -sz).normalized()
			cols[idx] = _zone_cache[gidx]
			uvs[idx] = Vector2(_wet_cache[gidx], orig[gidx] - heights[gidx])
	var indices := PackedInt32Array()
	indices.resize(cc * cc * 6)
	var w := 0
	for j in range(cc):
		for i in range(cc):
			var a := j * cvn + i
			indices[w] = a; indices[w + 1] = a + 1; indices[w + 2] = a + cvn + 1
			indices[w + 3] = a; indices[w + 4] = a + cvn + 1; indices[w + 5] = a + cvn
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _mat)
	var mi: MeshInstance3D = _chunks.get(key)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [key.x, key.y]
		add_child(mi)
		_chunks[key] = mi
	mi.mesh = mesh


func _process(_d: float) -> void:
	if ground == null or ground.dirty_chunks.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var done: Array = []
	for key in ground.dirty_chunks:
		_build_chunk(key)
		done.append(key)
		if (Time.get_ticks_usec() - t0) / 1000.0 > budget_ms:
			break
	for key in done:
		ground.dirty_chunks.erase(key)
