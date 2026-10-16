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
	var d = load("res://scripts/dc3_visual.gd").new()
	var door := false
	for a3 in OS.get_cmdline_user_args():
		if a3.begins_with("livery="):
			var lv: Array = load("res://scripts/liveries.gd").row("dc3", int(a3.substr(7)))
			d.METAL = lv[1]
			d.METAL_DK = (lv[1] as Color).darkened(0.21)
			d.STRIPE = lv[2]
		if a3 == "door=1":
			door = true
	add_child(d)
	if door:
		d.update_door(10.0, true)
	d.position = Vector3(0, 2.6, 0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var only := ""
	for a2 in OS.get_cmdline_user_args():
		if a2.begins_with("views="):
			only = a2.substr(6)
	var views := [["front", Vector3(0, 2.4, -16.0), Vector3(0, 2.4, 0), 40.0], ["prop34", Vector3(-7.5, 3.2, -9.0), Vector3(-2.0, 2.5, -3.5), 45.0],
		["front_flat", Vector3(0, 2.5, -60.0), Vector3(0, 2.5, 0), 14.0],
		["left", Vector3(-24.0, 3.0, 1.0), Vector3(0, 2.6, 1.0), 45.0],
		["door34", Vector3(-9.0, 3.4, -3.0), Vector3(-1.0, 2.5, 3.2), 50.0]]
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
		get_viewport().get_texture().get_image().save_png("%s/dc3_%s%s.png" % [out, v[0], tag])
	get_tree().quit()
