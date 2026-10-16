extends Node3D
## Renders a stretch of timbered drift (and a portal set) on its own, lit by
## a headlamp, to check the sets against the reference pictures.
## godot --path . res://tools/timber_view.tscn -- out=DIR

const MeshKit = preload("res://scripts/meshkit.gd")

func _ready() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 0.12
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var P = load("res://scripts/prospect.gd").new()
	# the drift: rough rock walls, a wet floor, 1.8 m wide, 2.2 m high, 16 m long
	var k := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rock := Color(0.30, 0.31, 0.28)
	for zi in range(32):
		var z0 := -float(zi) * 0.5
		var z1 := z0 - 0.5
		for yi in range(5):
			var y0 := float(yi) * 0.44
			var y1 := y0 + 0.44
			for sx in [-1.0, 1.0]:
				var j := func() -> float: return rng.randf_range(-0.08, 0.08)
				var c := rock.lerp(Color(0.42, 0.33, 0.24), rng.randf() * 0.6).darkened(rng.randf() * 0.3)
				k.quad(Vector3(sx * (0.92 + j.call()), y0, z0), Vector3(sx * (0.92 + j.call()), y0, z1), Vector3(sx * (0.92 + j.call()), y1, z1), Vector3(sx * (0.92 + j.call()), y1, z0), c, Vector3(-sx, 0, 0))
		for xi in range(4):
			var x0 := -0.92 + xi * 0.46
			var cf := Color(0.30, 0.24, 0.17).lerp(Color(0.55, 0.36, 0.10), rng.randf() * rng.randf()).darkened(rng.randf() * 0.2)
			k.quad(Vector3(x0, 0, z0), Vector3(x0 + 0.46, 0, z0), Vector3(x0 + 0.46, 0, z1), Vector3(x0, 0, z1), cf, Vector3.UP)
			var cr := rock.darkened(rng.randf() * 0.3)
			k.quad(Vector3(x0, 2.35, z0), Vector3(x0, 2.35, z1), Vector3(x0 + 0.46, 2.35, z1), Vector3(x0 + 0.46, 2.35, z0), cr, Vector3.DOWN)
	# timber: a portal set at the mouth, then log sets every metre or so
	P._portal_set(k, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.3)), 2.3, rng)
	var z := -1.4
	while z > -15.0:
		P._log_set(k, Transform3D(Basis.IDENTITY, Vector3(0, 0, z)), 2.32, rng)
		z -= rng.randf_range(0.9, 1.15)
	add_child(k.instance("Drift"))
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	var lamp := SpotLight3D.new()
	lamp.spot_range = 25.0
	lamp.spot_angle = 40.0
	lamp.light_energy = 6.0
	lamp.light_color = Color(1.0, 0.92, 0.78)
	lamp.shadow_enabled = true
	cam.add_child(lamp)
	for v in [["timber_inside", Vector3(0.15, 1.55, -1.0), Vector3(0, 1.1, -12.0)], ["timber_portal", Vector3(0.6, 1.5, 3.2), Vector3(0, 1.1, -1.0)]]:
		cam.position = v[1]
		cam.look_at(v[2], Vector3.UP)
		if v[0] == "timber_portal":
			e.ambient_light_energy = 0.9
			e.background_color = Color(0.55, 0.65, 0.75)
		for i in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, v[0]])
	get_tree().quit()
