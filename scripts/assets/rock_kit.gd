extends Node3D
## The Blender-built rock and cliff kit (DESIGN_NOTES 235; tools/blender/rocks.py
## writes assets/rocks/*.glb on Dave's PC): boulders, big rocks, scree stones,
## cliff faces. Loaded at run time (glTF), given the triplanar rock + moss
## material (shaders/rock_moss.gdshader) and a collision shape.
##   get("cliff_1"), get("boulder_3")... ; variant ints for AssetLib:
##   0-5 boulders, 10-12 big rocks, 20-23 scree, 30-33 cliffs.
## Lab: "rocks" (the whole kit laid out, a person for scale). (v2 cliffs)

const Tex = preload("res://scripts/tex.gd")
const DIR := "res://assets/rocks/"

static var _mats := {}
static var _meshes := {}


func _ready() -> void:
	if get_child_count() > 0:
		return
	var x := 0.0
	for v in [0, 1, 2, 3, 4, 5, 20, 21, 22, 23]:
		var n := make_variant(v)
		n.position = Vector3(x, 0, 0)
		add_child(n)
		x += 5.0
	x = 0.0
	for v in [10, 11, 12]:
		var n2 := make_variant(v)
		n2.position = Vector3(x, 0, 14)
		add_child(n2)
		x += 12.0
	x = -10.0
	for v in [30, 31, 32, 33]:
		var n3 := make_variant(v)
		n3.position = Vector3(x, 0, 40)
		add_child(n3)
		x += 30.0


static func make() -> Node3D:
	return make_variant(0)


static func name_of(v: int) -> String:
	if v >= 30:
		return "cliff_%d" % (v - 30)
	if v >= 20:
		return "scree_%d" % (v - 20)
	if v >= 10:
		return "rock_big_%d" % (v - 10)
	return "boulder_%d" % v


static func make_variant(v: int) -> Node3D:
	var nm := name_of(v)
	var root := Node3D.new()
	root.name = nm
	var mesh := _mesh(nm)
	if mesh == null:
		return root
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material(v >= 30)
	root.add_child(mi)
	# collision: the mesh itself for cliffs and big rocks (you fly and drive into them)
	if v >= 10 and v < 20 or v >= 30 or v <= 5:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		sb.add_child(cs)
		root.add_child(sb)
	return root


static func _mesh(nm: String) -> Mesh:
	if _meshes.has(nm):
		return _meshes[nm]
	var m: Mesh = null
	var path := ProjectSettings.globalize_path(DIR + nm + ".glb")
	if FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(path, st) == OK:
			var scene := doc.generate_scene(st)
			for c in scene.find_children("*", "MeshInstance3D", true, false):
				m = (c as MeshInstance3D).mesh
				break
			scene.free()
	_meshes[nm] = m
	return m


static func material(cliff: bool) -> ShaderMaterial:
	var key := "cliff" if cliff else "rock"
	if _mats.has(key):
		return _mats[key]
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/rock_moss.gdshader")
	sm.set_shader_parameter("rock_c", Tex._load("res://textures/ph/rock_face/rock_face_diff_2k.jpg"))
	sm.set_shader_parameter("rock_n", Tex._load("res://textures/ph/rock_face/rock_face_nor_gl_2k.jpg", true))
	sm.set_shader_parameter("moss_c", Tex._load("res://textures/ph/forest_ground_04/forest_ground_04_diff_2k.jpg"))
	sm.set_shader_parameter("moss_n", Tex._load("res://textures/ph/forest_ground_04/forest_ground_04_nor_gl_2k.jpg", true))
	sm.set_shader_parameter("rock_m", 6.0 if cliff else 3.0)
	sm.set_shader_parameter("moss_amount", 0.5 if cliff else 0.65)
	_mats[key] = sm
	return sm
