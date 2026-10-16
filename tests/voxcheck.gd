extends SceneTree
func _initialize() -> void:
	for c in ["VoxelTerrain", "VoxelLodTerrain", "VoxelMesherTransvoxel", "VoxelGeneratorScript", "VoxelGeneratorGraph", "VoxelTool", "VoxelViewer", "VoxelBuffer", "VoxelStreamMemory", "VoxelBlockyModelFluid"]:
		print(c, " ", ClassDB.class_exists(c))
	quit()
