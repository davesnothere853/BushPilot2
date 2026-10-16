extends Node
## Lab tool: unpack the add-ons fetched into res://_downloads/*.zip - every
## entry under an "addons/" folder lands in res://addons/ (the demo scenes and
## the rest are skipped). "run res://tools/unzip_addons.gd"
var status := "starting"


func _ready() -> void:
	var n := 0
	var zips := 0
	var dir := DirAccess.open("res://_downloads")
	if dir == null:
		status = "no res://_downloads"
		return
	for f in dir.get_files():
		if not f.ends_with(".zip"):
			continue
		var zr := ZIPReader.new()
		if zr.open("res://_downloads/" + f) != OK:
			print("[unzip] can't open ", f)
			continue
		zips += 1
		for e in zr.get_files():
			var i := e.find("addons/")
			if i < 0 or e.ends_with("/"):
				continue
			var dest := "res://" + e.substr(i)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest.get_base_dir()))
			var fa := FileAccess.open(dest, FileAccess.WRITE)
			if fa == null:
				print("[unzip] can't write ", dest)
				continue
			fa.store_buffer(zr.read_file(e))
			fa.close()
			n += 1
		zr.close()
	status = "done: %d files from %d zips" % [n, zips]
	print("[unzip] ", status)
	var lst := FileAccess.open("res://_rec/unzip_report.txt", FileAccess.WRITE)
	lst.store_string(status + "\n")
	var ad := DirAccess.open("res://addons")
	if ad != null:
		for d in ad.get_directories():
			lst.store_string(d + "\n")
	lst.close()
