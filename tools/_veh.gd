extends SceneTree
# headless 4-view sheet of a lab vehicle: args: script variant out_png [views "px,py,pz,tx,ty,tz,fov;..."]
func _init():
	await process_frame
	var a := OS.get_cmdline_user_args()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.74, 0.88)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.7, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.50, 0.42)
	g.material_override = gm
	root.add_child(g)
	var Lab = load("res://tools/model_lab.gd")
	var v = load(a[0]).new()
	if a[1] != "" and v.get("variant") != null:
		v.variant = a[1]
	if "terrain" in v:
		v.terrain = Lab.FlatGround.new()
	root.add_child(v)
	if v.has_method("build"):
		v.build()
	if v.has_method("park"):
		v.park(Transform3D.IDENTITY)
	v.set_physics_process(false)
	for i in range(5):
		await process_frame
	# optional 5th arg: "open" (doors and hood), "steer" (full lock): run the
	# animation until they're there
	if a.size() > 4:
		if a[4].contains("open"):
			if v.has_method("door_toggle"):
				v.door_toggle(-1)
			if v.has_method("hood_toggle"):
				v.hood_toggle()
		if a[4].contains("steer") and v.get("body") != null:
			v.body.steer = 0.6
		for i2 in range(150):
			if v.has_method("_animate"):
				v._animate()
			await process_frame
	var aabb := AABB()
	var first := true
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		if b.size.length() > 60.0:
			continue
		aabb = b if first else aabb.merge(b)
		first = false
	var c := aabb.get_center()
	var L := maxf(aabb.size.x, aabb.size.z)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	root.size = Vector2i(800, 500)
	var views: Array = [[c + Vector3(L * 0.75, L * 0.3, -L * 0.75), c, 42.0], [c + Vector3(L * 1.15, L * 0.05, 0), c, 42.0], [c + Vector3(-L * 0.75, L * 0.4, L * 0.75), c, 42.0], [c + Vector3(-L * 0.35, L * 0.25, -L * 1.0), c, 42.0]]
	if a.size() > 3:
		views = []
		for vv in a[3].split(";"):
			var f := vv.split_floats(",")
			views.append([Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), f[6]])
	var sheet := Image.create(1600, 500 * ((views.size() + 1) / 2), false, Image.FORMAT_RGBA8)
	for i in range(views.size()):
		cam.look_at_from_position(views[i][0], views[i][1])
		cam.fov = views[i][2]
		for k in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var im: Image = root.get_texture().get_image()
		im.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(im, Rect2i(0, 0, 800, 500), Vector2i((i % 2) * 800, (i / 2) * 500))
	sheet.save_png(a[2])
	quit()
