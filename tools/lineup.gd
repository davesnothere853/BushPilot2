extends Node3D
## Every machine parked side by side (Dave: they must look right next to each
## other), with a 1.8 m person at the end for scale and a 1 m grid on the ground.
## Lab: type "lineup".

const ROW := [["res://scripts/pickup_truck.gd", ""], ["res://scripts/pickup_truck.gd", "blazer"], ["res://scripts/water_truck.gd", ""],
	["res://scripts/loader.gd", ""], ["res://scripts/dozer.gd", ""], ["res://scripts/excavator.gd", ""], ["res://scripts/tug.gd", ""],
	["res://scripts/forklift.gd", ""], ["res://scripts/plane_body.gd", ""]]
const GAP := 1.6


func _ready() -> void:
	var Lab = load("res://tools/model_lab.gd")
	var x := 0.0
	var widths := [5.8, 4.9, 9.4, 8.3, 5.0, 8.6, 3.2, 3.7, 7.2]      # their lengths: parked side-on
	for i in range(ROW.size()):
		var e: Array = ROW[i]
		var v = load(e[0]).new()
		if e[1] != "" and v.get("variant") != null:
			v.variant = e[1]
		if v.get("terrain") != null or "terrain" in v:
			v.terrain = Lab.FlatGround.new()
		add_child(v)
		if v.has_method("build"):
			v.build()
		x += float(widths[i]) * 0.5
		if v.has_method("park"):
			v.park(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, 0, 0)))
		else:
			v.position = Vector3(x, 0, 0)
			v.rotation.y = PI * 0.5
		v.set_physics_process(false)
		v.set_process(false)
		var l := Label3D.new()
		l.text = String(e[1]) if e[1] != "" else String(e[0]).get_file().get_basename()
		l.font_size = 64
		l.pixel_size = 0.006
		l.position = Vector3(x, 0.05, 4.8)
		l.rotation = Vector3(-PI * 0.5, 0, 0)
		add_child(l)
		x += float(widths[i]) * 0.5 + GAP
	# a person for scale
	var man := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.25
	cm.height = 1.8
	man.mesh = cm
	man.position = Vector3(-1.5, 0.9, 0)
	add_child(man)
	# 1 m grid lines
	var k = preload("res://scripts/meshkit.gd").new()
	for gx in range(-4, int(x) + 4):
		k.box_at(Vector3(gx, 0.005, 0), Vector3(0.02, 0.01, 14.0), Color(0.3, 0.3, 0.3) if gx % 5 != 0 else Color(0.1, 0.1, 0.1))
	for gz in range(-7, 8):
		k.box_at(Vector3(x * 0.5, 0.005, gz), Vector3(x + 8.0, 0.01, 0.02), Color(0.3, 0.3, 0.3) if gz % 5 != 0 else Color(0.1, 0.1, 0.1))
	add_child(k.instance("Grid"))
	set_meta("frame_aabb", AABB(Vector3(-2, 0, -5), Vector3(x + 2, 4, 10)))
