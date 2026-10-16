extends Node3D
## Renders the near (3D) trees and shrubs with the game's own materials, for
## comparing against reference pictures. godot --path . res://tools/tree_view.tscn -- out=DIR [season=0..3]

const Meshes = preload("res://scripts/veg_meshes.gd")
const Flora = preload("res://scripts/flora.gd")

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := String(args.get("out", "user://"))
	if args.has("season"):
		Game.season = int(args["season"])
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.72, 0.84)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.76, 0.82)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.40, 0.24)
	g.material_override = gm
	add_child(g)
	Meshes.lite = args.has("lite")
	var veg = load("res://scripts/vegetation.gd").new()
	veg._radius = [5000.0, 0.0, 5000.0, 5000.0, 5000.0]
	# white spruce, black spruce, birch, aspen at their real heights, then the shrubs
	var row := [[Flora.WHITE_SPRUCE, 16.0, false], [Flora.BLACK_SPRUCE, 9.0, false], [Flora.BIRCH, 14.0, false], [Flora.ASPEN, 15.0, false]]
	var x := -15.0
	for r in row:
		var m: ArrayMesh = Meshes.tree(int(r[0]), int(args.get("lod", "0")), bool(r[2])) if args.has("solid") else Meshes.tree_cards(int(r[0]), int(args.get("lod", "0")), bool(r[2]))
		for si in range(m.get_surface_count()):
			var mat: ShaderMaterial = veg._material(0, int(r[0]), 0, si == 1)
			mat.set_shader_parameter("wind_strength", 0.0)
			m.surface_set_material(si, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.scale = Vector3.ONE * float(r[1])
		mi.position = Vector3(x, 0, 0)
		add_child(mi)
		x += 10.0
	var sx := -9.0
	for sk in [Flora.ALDER, Flora.WILLOW]:
		var sm: ArrayMesh = Meshes.shrub_cards(sk, false)
		for si in range(sm.get_surface_count()):
			var smat: ShaderMaterial = veg._material(2, sk, 0, si == 1)
			sm.surface_set_material(si, smat)
		var smi := MeshInstance3D.new()
		smi.mesh = sm
		smi.scale = Vector3.ONE * 3.0
		smi.position = Vector3(sx, 0, 9.0)
		add_child(smi)
		sx += 6.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var views := {
		"all": [Vector3(0, 7, 36), Vector3(0, 6, 0), 50.0],
		"spruce": [Vector3(-10, 6, 16), Vector3(-10, 6, 0), 50.0],
		"leafy": [Vector3(10, 6, 16), Vector3(10, 7, 0), 50.0],
		"shrubs": [Vector3(-6, 3, 18), Vector3(-6, 1.5, 9), 40.0],
	}
	for vn in String(args.get("views", "all,spruce,leafy,shrubs")).split(","):
		var v: Array = views[vn]
		cam.position = v[0]
		cam.fov = v[2]
		cam.look_at(v[1], Vector3.UP)
		for i in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/trees_%s.png" % [out, vn])
	get_tree().quit()
