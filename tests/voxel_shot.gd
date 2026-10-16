extends Node3D
## Renders the smooth voxel ground: overview, a dug pit, and a drift into the knoll.
const GroundScript = preload("res://scripts/ground.gd")
const VoxelGround = preload("res://scripts/voxel_ground.gd")
const WorldLook = preload("res://scripts/world_look.gd")
var _out := "user://"
var _f := 0
var g: RefCounted
var vg: Node3D
var cam: Camera3D
var t0 := 0
var shots := [
	["vox_pit", Vector3(60, 9, 80), Vector3(75, 0.5, 60), 200],
	["vox_drift", Vector3(79, 2.6, 41), Vector3(92, -1.2, 40), 120],
	["vox_overview", Vector3(-40, 55, 140), Vector3(60, 0, 0), 150],
]
var _si := 0
var _wait := 0
var _dug := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	t0 = Time.get_ticks_msec()
	WorldLook.environment(self)
	g = GroundScript.new()
	cam = Camera3D.new()
	cam.fov = 60
	cam.far = 6000
	add_child(cam)
	vg = VoxelGround.new()
	add_child(vg)
	vg.setup(g, cam)
	WorldLook.mountains(self, g.PLAIN_Y)
	_place(0)
	cam.make_current()

func _place(i: int) -> void:
	var a: Vector3 = shots[i][1]
	var b: Vector3 = shots[i][2]
	if shots[i][0] == "vox_drift":   # relative to the ground there
		a.y += g.height_at(a.x, a.z)
		b.y += g.height_at(b.x, b.z)
	cam.global_position = a
	cam.look_at(b, Vector3.UP)

func _process(_d: float) -> void:
	_f += 1
	if _f % 50 == 0:
		print("f", _f, " ", Time.get_ticks_msec() - t0, " ms")
	if not _dug and _f > 20:
		_dug = true
		# a stepped pit in the pay with the gameplay dig, then a drift beside the pad
		for k in range(220):
			var a := k * 0.55
			var r := 1.0 + k * 0.045
			g.dig(Vector3(75 + cos(a) * r, 0, 60 + sin(a) * r), 2.2, 3.0)
		var p := Vector3(90, g.height_at(90, 40) - 0.6, 40)
		vg.drift([p + Vector3(-4, 0.8, 0), p, p + Vector3(10, -2, 0), p + Vector3(20, -4, -6)], 1.7)
	_wait += 1
	if _wait >= shots[_si][3]:
		get_viewport().get_texture().get_image().save_png(_out + "/" + shots[_si][0] + ".png")
		print("shot ", shots[_si][0], " at ", Time.get_ticks_msec() - t0, " ms")
		_si += 1
		_wait = 0
		if _si >= shots.size():
			get_tree().quit()
			return
		_place(_si)
