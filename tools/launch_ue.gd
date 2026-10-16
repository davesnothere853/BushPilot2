extends Node
## Lab tool: open the Unreal rebuild (Unreal/BushPilot.uproject) in Unreal 5.7.
var status := "starting"
const UE := ["C:/Program Files/Epic Games/UE_5.7/Engine/Binaries/Win64/UnrealEditor.exe", "D:/Program Files/Epic Games/UE_5.7/Engine/Binaries/Win64/UnrealEditor.exe", "D:/Epic Games/UE_5.7/Engine/Binaries/Win64/UnrealEditor.exe"]
func _ready() -> void:
	var proj := ProjectSettings.globalize_path("res://Unreal/BushPilot.uproject")
	for exe in UE:
		if FileAccess.file_exists(exe):
			var pid := OS.create_process(exe, PackedStringArray([proj]))
			status = "unreal pid %d" % pid
			_say(status + " " + exe)
			return
	status = "UnrealEditor.exe not found"
	_say(status)
func _say(s: String) -> void:
	var f := FileAccess.open("res://_rec/launch_ue.txt", FileAccess.WRITE)
	f.store_string(s + "\n")
	f.close()
