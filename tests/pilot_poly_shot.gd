extends Node3D
const PilotRig = preload("res://scripts/pilot_rig.gd")
const PilotModel = preload("res://scripts/pilot_model.gd")
const WorldLook = preload("res://scripts/world_look.gd")
var _out := "user://"
var _f := 0
var _rigs: Array = []
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	WorldLook.environment(self)
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.45, 0.18)
	pm.material = gm
	var g := MeshInstance3D.new()
	g.mesh = pm
	add_child(g)
	var modes := [PilotModel.IDLE, PilotModel.WALK, PilotModel.RUN]
	for i in range(3):
		var r := PilotRig.new()
		add_child(r)
		r.build()
		r.position = Vector3(-1.3 + 1.3 * i, 0, 0)
		r.rotation.y = 0.5 - 0.5 * i
		_rigs.append([r, modes[i]])
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -0.12, -1), Vector3.UP), Vector3(0, 1.3, 5.2))
	cam.make_current()
func _process(d: float) -> void:
	_f += 1
	for e in _rigs:
		(e[0] as Node3D).animate(d, e[1], 1.4 if e[1] == PilotModel.WALK else 4.0, 0.0)
	if _f == 45:
		get_viewport().get_texture().get_image().save_png(_out + "/pilot_poly.png")
		get_tree().quit()
