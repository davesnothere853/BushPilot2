extends Node
## Lab tool: close the lab (the game it started keeps running).
var status := "closing"


func _ready() -> void:
	get_tree().quit()
