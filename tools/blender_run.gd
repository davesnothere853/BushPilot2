extends Node
## Lab tool: run Dave's Blender in the background (no window) on a build script.
## res://_rec/blender_job.txt: line 1 the script (res:// path), line 2 the output
## folder (res:// path). Blender writes <out>/blender_log.txt as it goes.
## "run res://tools/blender_run.gd"
const BLENDER := "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe"
var status := "starting"


func _ready() -> void:
	var job := FileAccess.get_file_as_string("res://_rec/blender_job.txt").strip_edges().split("\n", false)
	if job.size() < 2:
		status = "no job"
		return
	var script := ProjectSettings.globalize_path(String(job[0]).strip_edges())
	var out := ProjectSettings.globalize_path(String(job[1]).strip_edges())
	DirAccess.make_dir_recursive_absolute(out)
	var args := PackedStringArray(["-b", "--factory-startup", "--python", script, "--", out])
	for i in range(2, job.size()):
		args.append(String(job[i]).strip_edges())
	var pid := OS.create_process(BLENDER, args)
	status = "blender pid %d" % pid
	var f := FileAccess.open("res://_rec/blender_run.txt", FileAccess.WRITE)
	f.store_string("%s\n%s %s\n" % [status, BLENDER, " ".join(args)])
	f.close()
