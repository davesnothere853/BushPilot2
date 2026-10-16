extends Node
## Lab tool: free space on the project's drive (and D:/E: if there), to _rec/disk.txt.
var status := "checking"
func _ready() -> void:
	var out := ""
	for root in ["C:/", "D:/", "E:/", "F:/"]:
		var d := DirAccess.open(root)
		if d != null:
			out += "%s %.1f GB free\n" % [root, float(d.get_space_left()) / 1.0e9]
	status = out.replace("\n", "  ")
	var f := FileAccess.open("res://_rec/disk.txt", FileAccess.WRITE)
	f.store_string(out)
	f.close()
