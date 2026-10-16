extends Node
## Lab tool: make the folder for the Unreal rebuild (Documents/BushPilotUE).
var status := "starting"
func _ready() -> void:
	var p := ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir() + "/BushPilotUE"
	var e := DirAccess.make_dir_recursive_absolute(p)
	status = "made %s (%d)" % [p, e]
