extends Node3D
## Crash test (DESIGN_NOTES 229): a pickup's worth of mass (2600 kg, a box the
## size of the cab and bed) driven into the side of the pole barn at 10, 25,
## 40 and 60 km/h in turn. Its front face meets the barn's pieces with its real
## energy (structure.gd): sheets dent or tear off, girts snap, posts break, the
## roof follows if its supports go. Each run 10 s, then the barn is rebuilt.
## Lab: "crash_test".

const AssetLib = preload("res://scripts/assets/asset_lib.gd")
const Structure = preload("res://scripts/structure.gd")

const SPEEDS := [10.0, 25.0, 40.0, 60.0]       # km/h
const MASS := 2600.0
const SIZE := Vector3(2.0, 1.9, 5.6)

var _barn: Node3D
var _st: Node3D
var _truck: AnimatableBody3D
var _vel := Vector3.ZERO
var _run := -1
var _t := 0.0
var _label: Label3D
var _spent := 0.0
var _stopped := false


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	fcs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(fcs)
	add_child(floor_body)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	g.mesh = pm
	g.material_override = load("res://scripts/tex.gd").mat("gravel_floor", 2.5, Color(0.7, 0.68, 0.64), false)
	add_child(g)
	_label = Label3D.new()
	_label.pixel_size = 0.01
	_label.font_size = 64
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 9, 0)
	add_child(_label)
	_next_run()


func _next_run() -> void:
	_run = (_run + 1) % SPEEDS.size()
	if _barn != null:
		_barn.queue_free()
	if _st != null:
		for rb in _st.debris:
			if is_instance_valid(rb):
				rb.queue_free()
		_st.queue_free()
	if _truck != null:
		_truck.queue_free()
	_barn = load("res://scripts/assets/pole_barn.gd").make()
	add_child(_barn)
	_st = Structure.new()
	_st.name = "Structure"
	add_child(_st)
	_st.setup(_barn)
	_truck = AnimatableBody3D.new()
	_truck.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = SIZE
	cs.shape = bs
	_truck.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = SIZE
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.3, 0.55)
	mi.material_override = m
	_truck.add_child(mi)
	add_child(_truck)
	# side-on into the west wall, a little off the middle of a bay
	_truck.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-16.0, SIZE.y * 0.5 + 0.35, 1.1))
	_vel = Vector3(SPEEDS[_run] / 3.6, 0, 0)
	_t = 0.0
	_spent = 0.0
	_stopped = false


func _physics_process(dt: float) -> void:
	_t += dt
	if _t > 10.0:
		_next_run()
		return
	if _stopped or _vel.length() < 0.05:
		_vel = Vector3.ZERO
	else:
		# the whole nose, swept through this step
		var fwd := _vel.normalized()
		var c := _truck.global_position + fwd * (SIZE.z * 0.5 + _vel.length() * dt * 0.5)
		var half := Vector3(absf(fwd.x) * _vel.length() * dt * 0.5 + absf(fwd.z) * SIZE.x * 0.5, SIZE.y * 0.5, absf(fwd.z) * _vel.length() * dt * 0.5 + absf(fwd.x) * SIZE.x * 0.5)
		var box := AABB(c - half, half * 2.0)
		var res: Dictionary = _st.push(box, _vel, MASS)
		var a := float(res["absorbed"])
		if a > 0.0:
			_spent += a
			var ek := 0.5 * MASS * _vel.length_squared()
			_vel *= sqrt(maxf(0.0, 1.0 - a / maxf(ek, 1.0)))
		if res["held"]:
			_stopped = true
			_vel = Vector3.ZERO
		_vel *= 1.0 - 0.15 * dt          # rolling and engine braking
		_truck.global_position += _vel * dt
	var broke := 0
	for id in _st.pieces.keys():
		if _st.pieces[id]["broken"]:
			broke += 1
	_label.text = "%d km/h in   %.0f km/h now\n%.0f kJ into the barn   %d of %d pieces broken" % [SPEEDS[_run], _vel.length() * 3.6, _spent / 1000.0, broke, _st.pieces.size()]
