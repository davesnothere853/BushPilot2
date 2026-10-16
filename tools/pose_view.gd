extends Node3D
## Renders the pilot's tool clips at their key times (side and front), with
## the tool in his hand, then quits.
## godot --path . res://tools/pose_view.tscn -- out=DIR clip=dig

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := String(args.get("out", "user://"))
	var clip := String(args.get("clip", "dig"))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.72, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.82)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(-30), 0)
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	g.mesh = pm
	add_child(g)
	var rig = load("res://scripts/pilot_rig.gd").new()
	add_child(rig)
	rig.build()
	if args.has("items"):
		await _items(rig, String(args["items"]).split(","), out)
		get_tree().quit()
		return
	if clip.begins_with("phone"):
		rig.phone(true)
	if clip == "dig" or clip == "pick":
		var tool: Node3D = load("res://scripts/inventory.gd").build_mesh("shovel" if clip == "dig" else "pick")
		rig.hold_tool(tool)
	rig._working = clip
	var ap: AnimationPlayer = rig._player
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var times: Array = [0.0, 0.45, 0.9, 1.2] if clip == "dig" else ([0.0, 1.5] if clip.begins_with("phone") else [0.0, 0.4, 0.62, 0.8])
	for i in range(times.size()):
		ap.play(clip)
		ap.seek(float(times[i]), true)
		ap.pause()
		rig._process(0.0)
		for side in ([["side", Vector3(3.0, 1.5, 0.0)], ["front", Vector3(0.0, 1.5, -3.0)]] if clip.begins_with("phone") else [["side", Vector3(-4.2, 1.1, 0.0)], ["front", Vector3(0.0, 1.1, -4.2)]]):
			cam.position = side[1]
			cam.look_at(Vector3(0, 1.3 if clip.begins_with("phone") else 0.9, 0), Vector3.UP)
			for f in range(3):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%d_%s.png" % [out, clip, i, side[0]])
	get_tree().quit()


## Each item in his hand, standing (idle), seen from the front three-quarter
## and the side.
func _items(rig, ids: PackedStringArray, out: String) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 38.0
	var ap: AnimationPlayer = rig._player
	for id in ids:
		if ap.has_animation("idle"):
			ap.play("idle")
			ap.seek(0.5, true)
			ap.pause()
		var tool: Node3D = load("res://scripts/inventory.gd").build_mesh(id)
		rig.hold_tool(tool)
		for f0 in range(3):
			await get_tree().process_frame
		rig._process(0.0)
		rig._process(0.0)
		for side in [["f34", Vector3(-2.2, 1.4, 2.6)], ["side", Vector3(-3.2, 1.2, 0.0)]]:
			cam.position = side[1]
			cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
			for f in range(3):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/item_%s_%s.png" % [out, id, side[0]])
		rig.hold_tool(null)
		tool.queue_free()
