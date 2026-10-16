extends Node
## Lab tool: are the add-ons usable in this Godot? (Terrain3D is a compiled
## extension; the others are scripts). Writes res://_rec/addon_check.txt.
var status := "checking"


func _ready() -> void:
	var out := "Godot %s\n" % Engine.get_version_info().string
	out += "Terrain3D class: %s\n" % ClassDB.class_exists("Terrain3D")
	if ClassDB.class_exists("Terrain3D"):
		var t: Node = ClassDB.instantiate("Terrain3D")
		out += "Terrain3D version: %s\n" % str(t.get("version"))
		t.free()
	for p in ["res://addons/sky_3d/src/Sky3D.gd", "res://addons/proton_scatter/src/scatter.gd", "res://addons/road-generator/nodes/road_manager.gd"]:
		out += "%s: %s\n" % [p, FileAccess.file_exists(p)]
	for d in ["res://addons/sky_3d/src", "res://addons/proton_scatter/src", "res://addons/road-generator/nodes", "res://addons/terrain_3d"]:
		var da := DirAccess.open(d)
		if da != null:
			out += d + ": " + ", ".join(da.get_files().slice(0, 25)) + "\n"
	var f := FileAccess.open("res://_rec/addon_check.txt", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	status = "done"
