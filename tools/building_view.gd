extends Node3D
## Renders the building models in a row for checking against references.
## godot --path . res://tools/building_view.tscn -- out=DIR [views=a,b]

const Models = preload("res://scripts/building_models.gd")
const MeshKit = preload("res://scripts/meshkit.gd")

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := String(args.get("out", "user://"))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-35), 0)
	sun.shadow_enabled = true
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.34, 0.20)
	g.material_override = gm
	add_child(g)
	var items: Array = String(args.get("kinds", "cabin,loghouse,polebarn,poleshed,hangar")).split(",")
	var x := 0.0
	var centres := {}
	for k in items:
		var kit := MeshKit.new()
		var w := 10.0
		match k:
			"cabin":
				Models.log_building(kit, 7.0, 6.0, 9, 1.8, {"front": [[0.0, 1.3, 0, 6], [-2.0, 1.0, 3, 6]], "back": [[1.6, 1.0, 3, 6]], "left": [[0.0, 1.0, 3, 5]], "right": [[-1.4, 0.8, 3, 5]]}, 11, false)
				Models.cabin_furniture(kit, 7.0, 6.0, 2.68, 4.9, true)
				w = 8.0
			"loghouse":
				Models.log_building(kit, 10.0, 8.0, 10, 2.4, {"front": [[0.0, 1.3, 0, 6], [-2.6, 1.3, 3, 7], [2.6, 1.3, 3, 7]], "back": [[-2.5, 1.1, 3, 7], [2.5, 1.1, 3, 7]], "left": [[-1.5, 1.1, 3, 6], [1.8, 1.1, 3, 6]], "right": [[2.0, 0.9, 3, 6]]}, 23, true)
				Models.cabin_furniture(kit, 10.0, 8.0, 2.96, 5.96, false)
				w = 11.0
			"office":
				Models.log_building(kit, 10.0, 8.0, 10, 2.4, {"front": [[0.0, 1.3, 0, 6], [-2.6, 1.3, 3, 7], [2.6, 1.3, 3, 7]], "back": [[-2.5, 1.1, 3, 7], [2.5, 1.1, 3, 7]], "left": [[-1.5, 1.1, 3, 6], [1.8, 1.1, 3, 6]], "right": [[2.0, 0.9, 3, 6]]}, 23, true)
				Models.cabin_furniture(kit, 10.0, 8.0, 2.96, 5.96, false, true)
				w = 11.0
			"polebarn":
				Models.pole_barn(kit, 12.0, 18.0, 4.8, 6.0, 4.2, {"wall": Color(0.90, 0.90, 0.87), "wainscot": Color(0.20, 0.34, 0.24), "trim": Color(0.20, 0.34, 0.24), "roof": Color(0.66, 0.68, 0.69)})
				w = 13.0
			"poleshed":
				Models.pole_shed(kit, 12.0, 8.0, 4.4, 3.4, {"wall": Color(0.70, 0.72, 0.72), "wainscot": Color(0.24, 0.36, 0.27), "trim": Color(0.24, 0.36, 0.27), "roof": Color(0.66, 0.68, 0.69)})
				w = 13.0
			"hangar":
				Models.bush_hangar(kit, 22.0, 18.0, 6.5, 20.0, 5.4, {"wall": Color(0.92, 0.92, 0.89), "wainscot": Color(0.20, 0.34, 0.24), "trim": Color(0.95, 0.95, 0.93), "roof": Color(0.66, 0.68, 0.69)})
				w = 23.0
			_:
				var extra = load("res://scripts/site_models.gd") if ResourceLoader.exists("res://scripts/site_models.gd") else null
				if extra != null:
					w = float(extra.call("view", k, kit))
		var mi := kit.instance(k)
		x += w * 0.5
		mi.position = Vector3(x, 0, 0)
		centres[k] = [x, w]
		x += w * 0.5 + 6.0
		add_child(mi)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 45.0
	var shots: Array = []
	shots.append(["row", Vector3(x * 0.5, 14.0, -x * 0.75 - 10.0), Vector3(x * 0.5, 2.0, 0.0)])
	for k in centres.keys():
		var c: float = centres[k][0]
		var w2: float = centres[k][1]
		shots.append([k, Vector3(c - w2 * 0.9, w2 * 0.45 + 1.5, -w2 * 1.3 - 3.0), Vector3(c, w2 * 0.15 + 1.0, 0.0)])
	for k in ["cabin", "office", "loghouse"]:
		if centres.has(k):
			var c2: float = centres[k][0]
			var hw := 3.2 if k == "cabin" else 4.6
			shots.append([k + "_in", Vector3(c2 - hw * 0.7, 1.6, -hw * 0.55), Vector3(c2 + hw * 0.4, 0.9, hw * 0.6)])
			shots.append([k + "_in2", Vector3(c2 + hw * 0.6, 1.6, hw * 0.45), Vector3(c2 - hw * 0.5, 0.9, -hw * 0.5)])
	var want := String(args.get("views", ""))
	for s in shots:
		if want != "" and not String(s[0]) in want.split(","):
			continue
		cam.position = s[1]
		cam.look_at(s[2], Vector3.UP)
		for i in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/b_%s.png" % [out, s[0]])
	get_tree().quit()
