extends Node
## Lab tool: start the real game (main.tscn, the airport map) in its own window.
## "run res://tools/launch_game.gd"
var status := "starting"


func _ready() -> void:
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray(["--path", ProjectSettings.globalize_path("res://")]))
	status = "game pid %d" % pid
