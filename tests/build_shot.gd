extends Node3D
## Views of the log cabin, log house, pole barn and pole shed models.
const Models = preload("res://scripts/building_models.gd")
const MeshKit = preload("res://scripts/meshkit.gd")
var _out := "user://"
var _f := 0
var cam: Camera3D
var shots := [
	["hangar_out", Vector3(-38, 5, -30), Vector3(-45, 3, 0)],
	["hangar_in", Vector3(-45, 1.8, -12), Vector3(-45, 2.2, 8)],
	["hangar_back", Vector3(-38, 2.2, 0), Vector3(-48, 1.2, 8)],
	["build_all", Vector3(-6, 22, -42), Vector3(4, 0, 6)],
	["build_cabins", Vector3(-12, 3.5, -14), Vector3(-10, 2, 4)],
	["build_barns", Vector3(24, 4, -18), Vector3(18, 2.5, 6)],
	["build_cabin_in", Vector3(-16.5, 1.7, -0.8), Vector3(-17, 1.2, 4)],
	["build_barn_in", Vector3(14, 1.8, -6), Vector3(14, 2.6, 8)],
]
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.72, 0.82)
	e.ambient_light_color = Color(0.75, 0.75, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.75, 2.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	var g := MeshInstance3D.new()
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.42, 0.24)
	g.material_override = gm
	add_child(g)
	_place(func(k): 
		Models.log_building(k, 7.0, 6.0, 9, 1.8, {"front": [[0.0, 1.3, 0, 6], [-2.0, 1.0, 3, 6]], "back": [[1.6, 1.0, 3, 6]], "left": [[0.0, 1.0, 3, 5]], "right": [[-1.4, 0.8, 3, 5]]}, 11, false)
		var _f = Models.cabin_furniture(k, 7.0, 6.0, 2.68, 4.9, true), Vector3(-17, 0, 4))
	_place(func(k):
		Models.log_building(k, 10.0, 8.0, 10, 2.4, {"front": [[0.0, 1.3, 0, 6], [-2.6, 1.3, 3, 7], [2.6, 1.3, 3, 7]], "back": [[-2.5, 1.1, 3, 7], [2.5, 1.1, 3, 7]], "left": [[-1.5, 1.1, 3, 6], [1.8, 1.1, 3, 6]], "right": [[2.0, 0.9, 3, 6]]}, 23, true)
		var _f = Models.cabin_furniture(k, 10.0, 8.0, 2.96, 5.96, false), Vector3(-3, 0, 4))
	_place(func(k): Models.pole_barn(k, 12.0, 18.0, 4.8, 6.0, 4.2, {"wall": Color(0.90, 0.90, 0.87), "wainscot": Color(0.20, 0.34, 0.24), "trim": Color(0.20, 0.34, 0.24), "roof": Color(0.66, 0.68, 0.69)}), Vector3(14, 0, 8))
	_place(func(k): Models.pole_shed(k, 12.0, 8.0, 4.4, 3.4, {"wall": Color(0.70, 0.72, 0.72), "wainscot": Color(0.24, 0.36, 0.27), "trim": Color(0.24, 0.36, 0.27), "roof": Color(0.66, 0.68, 0.69)}), Vector3(30, 0, 4))
	_place(func(k): print(Models.bush_hangar(k, 22.0, 18.0, 7.0, 20.0, 5.6, {"wall": Color(0.92, 0.92, 0.89), "wainscot": Color(0.20, 0.34, 0.24), "trim": Color(0.95, 0.95, 0.93), "roof": Color(0.66, 0.68, 0.69)})["solids"]), Vector3(-45, 0, 0))
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	_aim(0)
func _place(fn: Callable, at: Vector3) -> void:
	var k := MeshKit.new()
	fn.call(k)
	var mi := k.instance("B")
	mi.position = at
	add_child(mi)
	print("tris ", k.verts.size() / 3)
func _aim(i: int) -> void:
	cam.global_position = shots[i][1]
	cam.look_at(shots[i][2])
func _process(_d: float) -> void:
	_f += 1
	if _f % 6 == 0:
		var i := _f / 6 - 1
		get_viewport().get_texture().get_image().save_png(_out + "/" + String(shots[i][0]) + ".png")
		if i + 1 >= shots.size():
			get_tree().quit()
		else:
			_aim(i + 1)
