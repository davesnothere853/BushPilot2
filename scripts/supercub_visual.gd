extends "res://scripts/plane_visual.gd"
## The Super Cub as a flyable plane (Dave: "I want to fly in that with the new
## plane"). The model is plane_body.gd - the one built from the 3-view and the
## bush photos in the Model Lab - hung on the flight model. plane_visual's own
## parts (the generic body, panels, wheels, prop) are still built so all the
## damage, gear and door code keeps working, but they're hidden; every frame
## the Cub's own ailerons, flaps, elevator, rudder, sticks, pedals, wheels and
## prop are set from the flight model.

const CubBody = preload("res://scripts/plane_body.gd")
var cub: Node3D
var _hidden_base: Array = []
var _prop_spin := 0.0


func _build_body() -> void:
	super._build_body()
	_hide_base()
	cub = CubBody.new()
	cub.name = "CubModel"
	add_child(cub)
	cub.build()
	# plane_body sits its plane frame GROUND_OFF up (the wheels on y 0); here
	# the flight model's frame is the plane frame itself
	var root: Node3D = cub.get("_root")
	if root != null:
		root.position = Vector3.ZERO
	# the game's engine sound plays for the flight model; the model's own goes quiet
	var es = cub.get("_es")
	if es != null and is_instance_valid(es):
		es.queue_free()
		cub.set("_es", null)


func _build_moving_parts() -> void:
	super._build_moving_parts()
	_hide_base()


func _build_cockpit() -> void:
	cockpit = null          # the Cub's own cabin is in the model (sticks and pedals move)


func _hide_base() -> void:
	for c in get_children():
		if c == cub or c in _hidden_base:
			continue
		if c is Node3D and not (c is CPUParticles3D):
			(c as Node3D).visible = false
			_hidden_base.append(c)
	for ln in _legs:
		if ln is MeshInstance3D:
			(ln as MeshInstance3D).mesh = null      # plane_visual shows the legs again each frame


func _process(delta: float) -> void:
	super._process(delta)
	if plane == null or cub == null:
		return
	for n in _hidden_base:
		if is_instance_valid(n):
			(n as Node3D).visible = false
	var ail: float = clampf(plane.aileron, -1.0, 1.0)
	var ele: float = clampf(plane.elevator + plane.trim * 0.45, -1.0, 1.0)
	var rud: float = clampf(plane.rudder, -1.0, 1.0)
	cub.call("_surf", "AileronL", ail * deg_to_rad(18.0))
	cub.call("_surf", "AileronR", -ail * deg_to_rad(18.0))
	cub.call("_surf", "Elevator", ele * deg_to_rad(26.0))
	cub.call("_surf", "Rudder", rud * deg_to_rad(24.0))
	var flp: float = float(plane.flaps) * deg_to_rad(40.0)
	cub.call("_surf", "FlapL", flp)
	cub.call("_surf", "FlapR", flp)
	cub.call("_stick", ail, ele, rud)
	# the prop: the flight model's rpm
	var rpm := 0.0
	var engs: Array = plane.engines() if plane.has_method("engines") else []
	if not engs.is_empty() and engs[0].get("rpm") != null:
		rpm = float(engs[0].rpm)
	_prop_spin = fmod(_prop_spin + rpm / 60.0 * TAU * delta, TAU)
	var hub = cub.get("_prop")
	if hub != null and is_instance_valid(hub):
		(hub as Node3D).rotation = Vector3(0, 0, _prop_spin)
	# wheels: spin with the ground roll, the tailwheel castors with the rudder
	var root: Node3D = cub.get("_root")
	if root == null:
		return
	var names := ["WheelL", "WheelR", "TailWheel"]
	for i in range(3):
		var wn := root.get_node_or_null(names[i]) as Node3D
		if wn == null:
			continue
		var hubp: Vector3 = Vector3(-CubBody.AXLE.x, CubBody.AXLE.y, CubBody.AXLE.z) if i == 0 else (CubBody.AXLE if i == 1 else CubBody.TAIL_HUB)
		var b := Basis(Vector3.RIGHT, -_wheel_spin[i])
		if i == 2:
			b = Basis(Vector3.UP, _caster_angle) * b
		wn.transform = Transform3D(b, hubp + Vector3(0, float(plane.wheel_comp[i]), 0))
