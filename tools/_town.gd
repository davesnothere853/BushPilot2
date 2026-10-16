extends SceneTree
# headless views of the town block: args[0] out prefix
func _init():
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.52, 0.56, 0.60)
	sm.sky_horizon_color = Color(0.70, 0.72, 0.74)
	sm.ground_horizon_color = Color(0.5, 0.52, 0.45)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.tonemap_exposure = 0.9
	e.tonemap_white = 6.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.fog_enabled = true
	e.fog_density = 0.0035
	e.volumetric_fog_enabled = false
	e.fog_light_color = Color(0.7, 0.76, 0.82)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.75, 0.9, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	sun.light_energy = 0.7
	sun.light_color = Color(1.0, 0.95, 0.86)
	root.add_child(sun)
	var t0 := Time.get_ticks_msec()
	var small := "small" in OS.get_cmdline_user_args()
	var town = load("res://scripts/small_town.gd" if small else "res://scripts/town_block.gd").new()
	root.add_child(town)
	await process_frame
	print("built in ", Time.get_ticks_msec() - t0, " ms")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("hide="):
			for nm in a.substr(5).split(","):
				var n = town.get_node_or_null(nm)
				if n != null:
					n.visible = false
	var cam0 := Camera3D.new()
	if small:
		e.fog_density = 0.00012
		e.fog_aerial_perspective = 0.15
		root.add_child(cam0)
		cam0.current = true
		cam0.far = 9000.0
		root.size = Vector2i(1280, 720)
		var vs: Array = [[Vector3(-150, 1.7, 4), Vector3(0, 3, 0), 60.0], [Vector3(0, 120, 170), Vector3(0, 0, -10), 55.0],
			[Vector3(-600, 60, 420), Vector3(0, 20, 0), 55.0], [Vector3(16, 1.7, -12), Vector3(-30, 2, 25), 65.0]]
		for a in OS.get_cmdline_user_args():
			if a.begins_with("views="):
				vs = []
				for v in a.substr(6).split(";"):
					var f := v.split_floats(",")
					vs.append([Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), f[6]])
		var ii := 0
		for v in vs:
			cam0.look_at_from_position(v[0], v[1])
			cam0.fov = v[2]
			for k in range(4):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s_%02d.png" % [out, ii])
			ii += 1
		quit()
		return
	var wal: PackedVector2Array
	for r in town._roads:
		if String(r["name"]) == "Wallace Street" and (r["pts"] as PackedVector2Array).size() > 2:
			wal = r["pts"]
			break
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.far = 2000.0
	root.size = Vector2i(1280, 720)
	var views: Array = []
	# along Wallace at eye height, both ways, from the main corner
	var dir := (wal[wal.size() - 1] - wal[0]).normalized()
	var o := Vector2.ZERO
	var nside := Vector2(-dir.y, dir.x)
	views.append([Vector3(o.x, 1.7, o.y) + Vector3(-dir.x, 0, -dir.y) * 45.0 + Vector3(nside.x, 0, nside.y) * 5.5, Vector3(o.x, 3.0, o.y) + Vector3(dir.x, 0, dir.y) * 30.0, 60.0])
	views.append([Vector3(o.x, 1.7, o.y) + Vector3(dir.x, 0, dir.y) * 40.0 - Vector3(nside.x, 0, nside.y) * 5.5, Vector3(o.x, 3.0, o.y) - Vector3(dir.x, 0, dir.y) * 30.0, 60.0])
	views.append([Vector3(-35, 22, 50), Vector3(0, 0, 0), 55.0])
	views.append([Vector3(0, 160, 120), Vector3(0, 0, -10), 55.0])
	views.append([Vector3(-40, 6, 35), Vector3(-70, 4, 15), 50.0])
	if OS.get_cmdline_user_args().size() > 1:
		views = [[Vector3(-30, 4, 52), Vector3(-38, 0.5, 62), 40.0], [Vector3(-48, 2.5, 66), Vector3(-38, 0.5, 60), 45.0]]
	var i := 0
	for v in views:
		cam.look_at_from_position(v[0], v[1])
		cam.fov = v[2]
		for k in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s_%02d.png" % [out, i])
		i += 1
	quit()
