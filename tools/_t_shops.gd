extends Node3D
# headless test lineup: the weathered main-street shops (300+)
func _ready() -> void:
	var CB = load("res://scripts/assets/commercial_block.gd")
	var i := 0
	for s in [21, 2, 3, 1, 5, 0]:
		var n: Node3D = CB.make_variant(300 + s)
		n.position = Vector3(float(i) * 7.8, 0, 0)
		add_child(n)
		i += 1
