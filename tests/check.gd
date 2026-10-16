extends SceneTree
# Loads every script and shader so parse errors show up in one pass.
func _initialize() -> void:
	var bad := 0
	for dir in ["res://scripts", "res://shaders"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd") or f.ends_with(".gdshader"):
				var res = load(dir + "/" + f)
				if res == null:
					bad += 1
					print("FAILED: ", f)
				elif res is GDScript and not res.can_instantiate():
					bad += 1
					print("NOT INSTANTIABLE: ", f)
	print("check done, failures: ", bad)
	quit()
