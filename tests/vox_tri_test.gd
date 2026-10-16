extends SceneTree
## Triangle count + mesh time per voxel size, on a 32 m patch of dug ground.
const GroundScript = preload("res://scripts/ground.gd")
func _init() -> void:
	var g = GroundScript.new()
	for k in range(140):
		var a := k * 0.7
		g.dig(Vector3(75 + cos(a) * (k * 0.06), 0, 60 + sin(a) * (k * 0.06)), 2.5, 3.0)
	for vox_v in [1.0, 0.5, 0.25]:
		var vox: float = vox_v
		for opt_v in [false, true]:
			var opt: bool = opt_v
			var nn := int(32.0 / vox)
			var sz := Vector3i(nn + 3, int(16.0 / vox) + 3, nn + 3)
			var buf := VoxelBuffer.new()
			buf.create(sz.x, sz.y, sz.z)
			buf.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_16_BIT)
			for z in range(sz.z):
				for x in range(sz.x):
					var wx := 59.0 + (x - 1) * vox
					var wz := 44.0 + (z - 1) * vox
					var h: float = g.height_at(wx, wz)
					for y in range(sz.y):
						var wy := -8.0 + (y - 1) * vox
						buf.set_voxel_f(clampf((wy - h) / vox, -8.0, 8.0), x, y, z, VoxelBuffer.CHANNEL_SDF)
			var m := VoxelMesherTransvoxel.new()
			m.mesh_optimization_enabled = opt
			if opt:
				m.mesh_optimization_error_threshold = 0.02
				m.mesh_optimization_target_ratio = 0.25
			var t0 := Time.get_ticks_usec()
			var mesh: Mesh = m.build_mesh(buf, [])
			var us := Time.get_ticks_usec() - t0
			var tris := 0
			if mesh:
				for s in range(mesh.get_surface_count()):
					var arr := mesh.surface_get_arrays(s)
					var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
					tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var whole := tris * (360.0 * 360.0) / (32.0 * 32.0)
			print("vox ", vox, " opt ", opt, ": ", tris, " tris / 32m patch, mesh ", us / 1000.0, " ms  -> whole square ~", int(whole / 1000.0), "k tris")
	quit()
