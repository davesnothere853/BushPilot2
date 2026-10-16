extends Node3D
## Headless: image generator at a given voxel size, scaled terrain node. Timing + accuracy + physics hit.
const GroundScript = preload("res://scripts/ground.gd")
var VOX := 0.5
var g: RefCounted
var t: VoxelTerrain
var tool: VoxelTool
var t0 := 0
var _f := 0
var gen_ms := 0
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("vox="):
			VOX = float(a.substr(4))
	g = GroundScript.new()
	t0 = Time.get_ticks_msec()
	var SQ: float = g.SQ
	var n := int(2.0 * SQ / VOX) + 1
	var lo := 1.0e9
	var hi := -1.0e9
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in range(n):
		for i in range(n):
			var h: float = g.height_at(-SQ + i * VOX, -SQ + j * VOX)
			hs[j * n + i] = h
			lo = minf(lo, h); hi = maxf(hi, h)
	lo -= 2.0; hi += 2.0
	var img := Image.create(n, n, false, Image.FORMAT_RF)
	for j in range(n):
		for i in range(n):
			img.set_pixel(i, j, Color((hs[j * n + i] - lo) / (hi - lo), 0, 0))
	print("image ", n, "x", n, " built ", Time.get_ticks_msec() - t0, " ms")
	var gen := VoxelGeneratorImage.new()
	gen.image = img
	gen.height_start = lo / VOX
	gen.height_range = (hi - lo) / VOX
	gen.channel = VoxelBuffer.CHANNEL_SDF
	t = VoxelTerrain.new()
	t.generator = gen
	t.mesher = VoxelMesherTransvoxel.new()
	t.stream = VoxelStreamMemory.new()
	t.bounds = AABB(Vector3(0, int(lo / VOX) - 64, 0), Vector3(n, int((hi - lo) / VOX) + 128, n))
	t.max_view_distance = 512
	t.mesh_block_size = 32
	t.scale = Vector3.ONE * VOX
	t.position = Vector3(-SQ, 0, -SQ)
	add_child(t)
	tool = t.get_voxel_tool()
	var v := VoxelViewer.new()
	v.view_distance = int(200.0 / VOX)
	add_child(v)
	v.global_position = Vector3(75, 2, 60)
	t0 = Time.get_ticks_msec()
func _physics_process(_d: float) -> void:
	_f += 1
	if _f % 20 != 0:
		return
	var st := t.get_statistics()
	var vp := Vector3((75 + g.SQ) / VOX, 0, (60 + g.SQ) / VOX)
	var ok := tool.is_area_editable(AABB(vp - Vector3(40, 40, 40), Vector3(80, 80, 80)))
	print("f", _f, " ", Time.get_ticks_msec() - t0, "ms editable=", ok)
	if ok and _f > 200:
		var err := 0.0
		var perr := 0.0
		var space := get_world_3d().direct_space_state
		for k in range(40):
			var x := 60.0 + (k * 7) % 30
			var z := 45.0 + (k * 13) % 30
			var h: float = g.height_at(x, z)
			var vx := int(round((x + g.SQ) / VOX)); var vz := int(round((z + g.SQ) / VOX))
			var y := int(floor(h / VOX)) + 4
			while vx >= 0 and tool.get_voxel_f(Vector3i(vx, y, vz)) > 0.0 and y > h / VOX - 10:
				y -= 1
			var a := tool.get_voxel_f(Vector3i(vx, y + 1, vz))
			var b := tool.get_voxel_f(Vector3i(vx, y, vz))
			err = maxf(err, absf((y + b / (b - a)) * VOX - g.height_at(vx * VOX - g.SQ, vz * VOX - g.SQ)))
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -60, z))
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				perr = 999.0
			else:
				perr = maxf(perr, absf(hit.position.y - h))
		print("VOX ", VOX, " sdf err ", err, " m, physics err ", perr, " m, ", st)
		get_tree().quit()
	if _f > 4000:
		get_tree().quit()
