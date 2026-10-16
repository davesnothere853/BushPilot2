extends Node
## Lab tool: zip the whole project (not the .godot cache, _rec or _downloads) to
## Documents/BushPilot2_builds/<name>.zip. res://_rec/backup_name.txt = the name.
## "run res://tools/backup_zip.gd"
var status := "starting"
var _files: Array = []


func _ready() -> void:
	var nm := FileAccess.get_file_as_string("res://_rec/backup_name.txt").strip_edges()
	if nm == "":
		nm = "BushPilot2_backup"
	var root := ProjectSettings.globalize_path("res://")
	var out := root.get_base_dir().get_base_dir() + "/BushPilot2_builds/" + nm + ".zip"
	_walk("res://")
	var zp := ZIPPacker.new()
	if zp.open(out) != OK:
		status = "can't write " + out
		_report()
		return
	var n := 0
	for f in _files:
		var rel: String = String(f).trim_prefix("res://")
		zp.start_file(rel)
		zp.write_file(FileAccess.get_file_as_bytes(f))
		zp.close_file()
		n += 1
	zp.close()
	status = "done: %d files -> %s" % [n, out]
	_report()


func _walk(d: String) -> void:
	for sub in DirAccess.get_directories_at(d):
		if sub in [".godot", "_rec", "_downloads", ".git"]:
			continue
		_walk(d.path_join(sub))
	for f in DirAccess.get_files_at(d):
		_files.append(d.path_join(f))


func _report() -> void:
	var fa := FileAccess.open("res://_rec/backup_report.txt", FileAccess.WRITE)
	fa.store_string(status + "\n")
	fa.close()
