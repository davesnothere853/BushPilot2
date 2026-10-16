extends Node3D
const Ground = preload("res://scripts/ground.gd")
const DozerScript = preload("res://scripts/dozer.gd")
var _frames := 0
var _out := "user://"
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.58, 0.60)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.85)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(-120.0), 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	var floor_m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.4, 0.37, 0.3)
	pm.material = fm
	floor_m.mesh = pm
	add_child(floor_m)
	# Stub ground so dozer settles flat.
	var stub := FlatStub.new()
	var dz := DozerScript.new()
	dz.terrain = stub
	add_child(dz)
	dz.build()
	dz.park(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	dz.blade_down = true
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at((Vector3(0,1,-1.2) - Vector3(-5.2, 2.6, -6.0)).normalized(), Vector3.UP), Vector3(-5.2, 2.6, -6.0))
	cam.make_current()
class FlatStub:
	extends RefCounted
	func height_at(_x: float, _z: float) -> float: return 0.0
	func normal_at(_x: float, _z: float) -> Vector3: return Vector3.UP
	func blocked_by_building(_p: Vector3, _r: float = 0.6) -> bool: return false
func _process(_d: float) -> void:
	_frames += 1
	if _frames == 10:
		get_viewport().get_texture().get_image().save_png(_out + "/doz_front.png")
		var cam := get_viewport().get_camera_3d()
		cam.global_transform = Transform3D(Basis.looking_at((Vector3(0,0.9,-1.4) - Vector3(4.6, 1.6, -5.4)).normalized(), Vector3.UP), Vector3(4.6, 1.6, -5.4))
	elif _frames == 20:
		get_viewport().get_texture().get_image().save_png(_out + "/doz_side.png")
		get_tree().quit()
