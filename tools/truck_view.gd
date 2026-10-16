extends Node3D
## Renders one vehicle on flat ground from fixed angles and saves PNGs, then
## quits. godot --path . res://tools/truck_view.tscn -- veh=pickup out=DIR

class FlatGround extends RefCounted:
	func height_at(_x: float, _z: float) -> float: return 0.0
	func ground_level_at(_x: float, _z: float) -> float: return 0.0
	func strip_index_at(_x: float, _z: float, _m: float = 0.0) -> int: return 0
	func blocked_by_building(_p: Vector3, _r: float = 0.0, _skip = null) -> bool: return false
	func normal_at(_x: float, _z: float) -> Vector3: return Vector3.UP
	func ground_normal_at(_x: float, _z: float) -> Vector3: return Vector3.UP
	func mud_at(_x: float, _z: float) -> float: return 0.0
	var lakes: Array = []

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := String(args.get("out", "user://"))
	var veh := String(args.get("veh", "pickup"))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.72, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.82)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.43, 0.38)
	g.material_override = gm
	add_child(g)
	if veh == "trommel":
		# the skid trommel plant on its own (equipment_models.gd)
		var tp := Node3D.new()
		add_child(tp)
		load("res://scripts/equipment_models.gd").skid_trommel(tp)
		var camt := Camera3D.new()
		add_child(camt)
		camt.current = true
		for vv in [["side", Vector3(-11, 2.5, -0.5), Vector3(0, 1.4, -0.5)], ["front34", Vector3(-6.5, 3.0, -9.0), Vector3(0, 1.0, -3.0)]]:
			camt.position = vv[1]
			camt.fov = 40.0
			camt.look_at(vv[2], Vector3.UP)
			for i in range(4):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/trommel_%s.png" % [out, vv[0]])
		get_tree().quit()
		return
	var scr := "pickup_truck" if veh == "pickup" else ("tug" if veh == "tug" else ("loader" if veh == "loader" else ("tunneler" if veh == "miner" else "water_truck")))
	if veh in ["excavator", "dozer", "forklift", "log_trailer"]:
		scr = veh
	var t = load("res://scripts/%s.gd" % scr).new()
	if veh == "fuel":
		t.variant = "fuel"
	t.terrain = FlatGround.new()
	add_child(t)
	t.build()
	t.park(Transform3D.IDENTITY)
	if veh == "tug" and args.has("withplane"):
		# the Wolverine sitting on its wheels, tail toward the tug, the bar on
		var sit := Basis(Vector3.RIGHT, deg_to_rad(11.2))
		var wp := [Vector3(-1.15, -1.53, -0.55), Vector3(0.0, -0.32, 5.0)]
		var lowest := minf((sit * (wp[0] as Vector3)).y, (sit * (wp[1] as Vector3)).y)
		var pv = load("res://scripts/plane_visual.gd").new()
		add_child(pv)
		pv.set_process(false)
		pv.set_physics_process(false)
		var tail: Vector3 = sit * (wp[1] as Vector3)
		pv.transform = Transform3D(sit, Vector3(0, -lowest, 0))
		tail.y -= lowest
		var hz: float = tail.z + float(t.BAR) + float(t.HITCH.z)
		t.park(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, hz)))
		var h: Vector3 = t.hitch_point()
		var d: Vector3 = tail - h
		var y := d.normalized()
		var x := y.cross(Vector3.UP).normalized()
		t._bar.visible = true
		t._bar.global_transform = Transform3D(Basis(x, y * d.length(), x.cross(y)), h)
	if args.has("tyres") and t.has_method("set_tyres"):
		t.set_tyres(String(args["tyres"]))
	if args.has("lift") and t.get("_lift") != null:
		t._lift = float(args["lift"]) * 0.0254
		t.set_tyres(t.tyre_kind)
		t._build_shafts()
		t.park(Transform3D.IDENTITY)
	if args.has("hood") and t.has_method("hood_toggle"):
		t.hood_toggle()
	if args.has("gate") and t.has_method("tailgate_toggle"):
		t.tailgate_toggle()
	if args.has("driver") and t.has_method("eye_xf"):
		# the character in the seat, posed as in the game (main._seat_driver)
		var PR = load("res://scripts/pilot_rig.gd")
		var dm: Node3D = PR.new() if PR.available() else load("res://scripts/pilot_model.gd").new()
		add_child(dm)
		for i2 in range(90):
			dm.animate(0.016, 5, 0.0, float(i2) * 0.016)
			await get_tree().process_frame
		var ex: Transform3D = t.eye_xf()
		var dy: float = t.cab_yaw() if t.has_method("cab_yaw") else float(t.yaw)
		dm.rotation = Vector3(0, dy, 0)
		dm.global_position = ex.origin - Basis(Vector3.UP, dy) * (dm.eye_local() as Vector3)
		print("driver: veh y %.2f eye %s eye_local %s -> feet %s" % [t.global_position.y, str(ex.origin), str(dm.eye_local()), str(dm.global_position)])
	for i in range(30):
		if t.has_method("_animate"):
			t._animate()
		await get_tree().process_frame
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var big := veh != "pickup" and veh != "tug"
	var k := 1.6 if big else 1.0
	var views := {
		"side": [Vector3(-9.5, 1.1, 0.2) * k, Vector3(0, 1.0 * k, 0.2), 32.0],
		"front34": [Vector3(-5.5, 1.5, -6.5) * k, Vector3(0, 0.9 * k, -0.6), 40.0],
		"rear34": [Vector3(5.0, 2.2, 6.5) * k, Vector3(0, 0.9 * k, 1.0), 40.0],
		"under": [Vector3(-6.0, 0.25, 0.0) * k, Vector3(0, 0.55, 0.0), 40.0],
		"front": [Vector3(0, 1.2, -9.0) * k, Vector3(0, 1.0 * k, 0), 30.0],
		"rearlow": [Vector3(0.0, 0.35, 7.0) * k, Vector3(0, 0.5, 0), 34.0],
		"towing": [Vector3(-9.0, 3.0, 12.5), Vector3(0, 0.8, 4.0), 45.0],
	}
	var only := String(args.get("views", "side,front34,rear34,under"))
	if t.get("_wheel_nodes") != null and not (t._wheel_nodes as Array).is_empty():
		# a close look at a front wheel and a back one
		var wf: Vector3 = ((t._wheel_nodes as Array)[0][0] as Node3D).global_position
		var wr: Vector3 = ((t._wheel_nodes as Array)[(t._wheel_nodes as Array).size() - 2][0] as Node3D).global_position
		views["wheel"] = [wf + Vector3(-2.0, 0.35, -1.1) * k, wf, 34.0]
		views["wheelr"] = [wr + Vector3(-2.0, 0.6, 1.0) * k, wr, 34.0]
	for vn in only.split(","):
		var v: Array = views[vn]
		cam.position = v[0]
		cam.fov = v[2]
		cam.look_at(v[1], Vector3.UP)
		for i in range(3):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, veh, vn])
	if args.has("dash"):
		var ex: Transform3D = t.eye_xf()
		cam.global_transform = ex
		cam.rotate_object_local(Vector3.RIGHT, -0.32)
		cam.fov = 74.0
		cam.near = 0.05
		for i in range(3):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_dash.png" % [out, veh])
	get_tree().quit()
