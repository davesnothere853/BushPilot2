extends Node3D
## Renders the DC-3 model on flat ground from the front and a front
## three-quarter, then quits. godot --path . res://tools/dc3_view.tscn -- out=DIR

func _ready() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.72, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.82)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	sun.shadow_enabled = true
	add_child(sun)
	var vtype := ""
	for a5 in OS.get_cmdline_user_args():
		if a5.begins_with("type="):
			vtype = a5.substr(5)
	var d = load("res://scripts/plane_visual.gd" if vtype == "" else "res://scripts/%s_visual.gd" % vtype).new()
	if vtype != "":
		var row: Array = load("res://scripts/liveries.gd").row(vtype, 0)
		d.CREAM = row[1]
		d.ORANGE = row[2]
		d.BROWN = row[3] if row.size() > 3 else row[2]
	var door := false
	for a3 in OS.get_cmdline_user_args():
		if a3.begins_with("livery="):
			pass
		if a3 == "door=1":
			door = true
	add_child(d)
	d.set_process(false)
	d.set_physics_process(false)
	d.position = Vector3(0, 1.0, 0)
	if door:
		await get_tree().process_frame
		if d._doors.has("cabin"):
			(d._doors["cabin"][0] as Node3D).rotation = Vector3(0, -1.3, 0)
			(d._doors["cabin"][1] as Node3D).visible = true
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var only := ""
	for a2 in OS.get_cmdline_user_args():
		if a2.begins_with("views="):
			only = a2.substr(6)
	var views := [["front", Vector3(0, 2.4, -16.0), Vector3(0, 2.4, 0), 40.0], ["prop34", Vector3(-7.5, 3.2, -9.0), Vector3(-2.0, 2.5, -3.5), 45.0],
		["front_flat", Vector3(0, 2.5, -60.0), Vector3(0, 2.5, 0), 14.0],
		["left", Vector3(-12.0, 1.4, 1.0), Vector3(0, 1.0, 1.0), 45.0],
		["bi_side", Vector3(-13.0, 0.6, 1.4), Vector3(0, 0.4, 1.4), 40.0],
		["bi_front34", Vector3(-7.0, 2.2, -7.5), Vector3(0, 0.3, 0.6), 45.0],
		["bi_rear34", Vector3(6.5, 3.2, 8.5), Vector3(0, 0.4, 1.2), 45.0],
		["bi_engine", Vector3(-1.6, 0.5, -3.6), Vector3(0, 0.0, -1.8), 45.0],
		["bi_cockpit", Vector3(0.0, 0.62, 1.42), Vector3(0, 0.15, 0.6), 70.0],
		["bi_top", Vector3(0.0, 14.0, 0.8), Vector3(0, 0, 0.8), 45.0],
		["doorl", Vector3(-4.5, 1.8, -2.2), Vector3(0, 1.3, 0.0), 45.0],
		["tail34l", Vector3(-3.5, 1.6, -0.5), Vector3(0, 1.0, 3.2), 45.0],
		["tail34r", Vector3(3.5, 1.3, 0.5), Vector3(0, 1.0, 3.2), 45.0],
		["tailback", Vector3(-2.5, 1.5, 8.0), Vector3(0, 1.0, 3.0), 45.0]]
	var tag := ""
	for a4 in OS.get_cmdline_user_args():
		if a4.begins_with("tag="):
			tag = a4.substr(4)
	for v in views:
		if only != "" and not (only.split(",") as PackedStringArray).has(String(v[0])):
			continue
		cam.position = v[1]
		cam.fov = v[3]
		cam.look_at(v[2], Vector3.UP)
		for i in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/plane_%s%s.png" % [out, v[0], tag])
	get_tree().quit()
