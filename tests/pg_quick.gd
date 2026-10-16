extends Node3D
## First look at the Bush Pilot 2 proving ground: the whole 360 m square built
## analytically (the real deformable ground.gd will replace QuickGround with
## the same zone plan), real trees from veg_meshes, the Wolverine on the apron,
## a hangar, the dozer at the pay cut, under the proven overcast recipe.
## godot --path . res://tests/pg_quick.tscn -- out=<dir>

const PlaneScript = preload("res://scripts/plane.gd")
const PlaneVisual = preload("res://scripts/plane_visual.gd")
const MeshKit = preload("res://scripts/meshkit.gd")
const Flora = preload("res://scripts/flora.gd")
const Meshes = preload("res://scripts/veg_meshes.gd")
const DozerScript = preload("res://scripts/dozer.gd")
const Ground = preload("res://scripts/ground.gd")
const ExcavatorScript = preload("res://scripts/excavator.gd")
const Water = preload("res://scripts/water.gd")
const GroundView = preload("res://scripts/ground_view.gd")
const VEG_SHADER = preload("res://shaders/veg.gdshader")
const GROUND_SHADER = preload("res://shaders/ground.gdshader")

var _out := "user://"
var _cam: Camera3D
var _frames := 0
var _views: Array = []
var ground: RefCounted
var view: Node3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	ground = Ground.new()
	view = GroundView.new()
	add_child(view)
	view.setup(ground)
	_earthworks()
	_flush_chunks()
	_weather()
	_build_water()
	_build_hangar()
	_plants()
	_machines()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	var gh := func(x: float, z: float) -> float: return ground.height_at(x, z)
	_views = [
		["pg_apron", Vector3(-20.0, gh.call(-20.0, -62.0) + 3.6, -62.0), Vector3(8.0, 6.5, -98.0)],
		["pg_runway", Vector3(-146.0, gh.call(-146.0, -128.0) + 1.7, -128.0), Vector3(140.0, 8.0, -131.0)],
		["pg_cut", Vector3(52.0, gh.call(52.0, 42.0) + 3.2, 42.0), Vector3(80.0, 4.5, 64.0)],
		["pg_pond", Vector3(-58.0, gh.call(-58.0, 66.0) + 6.5, 66.0), Vector3(-105.0, 3.0, 105.0)],
		["pg_void", Vector3(-215.0, 72.0, 215.0), Vector3(40.0, 0.0, -40.0)],
	]
	_apply(0)


func _weather() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.42, 0.47, 0.52)
	sm.sky_horizon_color = Color(0.66, 0.68, 0.68)
	sm.sky_curve = 0.18
	sm.ground_bottom_color = Color(0.32, 0.34, 0.33)
	sm.ground_horizon_color = Color(0.64, 0.66, 0.66)
	sm.sun_angle_max = 28.0
	sm.sun_curve = 0.08
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.58, 0.63, 0.65)
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.12
	env.fog_height = 1.0
	env.fog_height_density = 0.03
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.04
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.07
	env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-16.0), deg_to_rad(-118.0), 0)
	sun.light_color = Color(1.0, 0.86, 0.72)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.directional_shadow_max_distance = 320.0
	add_child(sun)


## The demo earthworks, done with the real tools' maths: a bladed road from
## the apron to the pad, the pay cut, and its spoil heap.
func _earthworks() -> void:
	# The road: grade a 3 m lane, each pass pulling toward a gentle running
	# target like the dozer does (8% max ramp).
	var from := Vector2(32.0, -68.0)
	var to := Vector2(60.0, 40.0)
	var steps := int(from.distance_to(to) / 1.2)
	var tgt: float = ground.height_at(from.x, from.y)
	for k in range(steps + 1):
		var p := from.lerp(to, float(k) / float(steps))
		var here: float = ground.height_at(p.x, p.y)
		tgt = clampf(here, tgt - 0.096, tgt + 0.096)
		ground.level(Vector3(p.x, 0, p.y), 2.1, tgt, 0.9, 0.9)
	# The pay cut: a bench of bucket bites, spoil piled to the west.
	var spoil := Vector3(57.0, 0.0, 49.0)
	for k in range(140):
		var a := float(k % 20) / 20.0 * TAU
		var r := 1.0 + 4.5 * (float(k % 20) / 20.0)
		var c := Vector3(78.0 + cos(a) * r * 0.9, 0.0, 63.0 + sin(a) * r * 0.65)
		var out: Dictionary = ground.dig(c, 1.7, 0.45)
		var vol: float = float(out["over"]) + float(out["pay"])
		if vol > 0.01:
			ground.deposit(spoil + Vector3(randf() * 3.0 - 1.5, 0, randf() * 3.0 - 1.5), vol * 0.5)


func _flush_chunks() -> void:
	var keys: Array = ground.dirty_chunks.keys()
	for key in keys:
		view._build_chunk(key)
	ground.dirty_chunks.clear()


func _build_water() -> void:
	var water := Water.new()
	add_child(water)
	water.setup(Vector3(-105.0, 0, 105.0), 31.0, 3.2, 0.3)


func _build_hangar() -> void:
	# A bush hangar: faded green steel, gable roof, open to the apron (+x).
	var kit := MeshKit.new()
	var wall := Color(0.23, 0.30, 0.24)
	var trim := Color(0.16, 0.20, 0.17)
	var roof := Color(0.36, 0.34, 0.31)
	var cx := -36.0
	var cz := -86.0
	var y0 := 6.15
	var hw := 8.0      # half width (z)
	var hd := 6.5      # half depth (x)
	var wh := 4.4      # wall height
	var ph := 2.8      # gable peak above walls
	kit.box_at(Vector3(cx - hd + 0.15, y0 + wh * 0.5, cz), Vector3(0.3, wh, hw * 2.0), wall)
	kit.box_at(Vector3(cx, y0 + wh * 0.5, cz - hw + 0.15), Vector3(hd * 2.0, wh, 0.3), wall)
	kit.box_at(Vector3(cx, y0 + wh * 0.5, cz + hw - 0.15), Vector3(hd * 2.0, wh, 0.3), wall)
	# Gable triangles above the back wall and over the door.
	for xx in [cx - hd + 0.15, cx + hd - 0.15]:
		kit.tri(Vector3(xx, y0 + wh, cz - hw), Vector3(xx, y0 + wh, cz + hw),
			Vector3(xx, y0 + wh + ph, cz), wall, Vector3(1, 0, 0) if xx > cx else Vector3(-1, 0, 0))
	# Roof slopes, with a little overhang.
	var oe := 0.5
	kit.quad(Vector3(cx - hd - oe, y0 + wh - 0.1, cz - hw - oe), Vector3(cx + hd + oe, y0 + wh - 0.1, cz - hw - oe),
		Vector3(cx + hd + oe, y0 + wh + ph, cz), Vector3(cx - hd - oe, y0 + wh + ph, cz), roof, Vector3.UP)
	kit.quad(Vector3(cx - hd - oe, y0 + wh + ph, cz), Vector3(cx + hd + oe, y0 + wh + ph, cz),
		Vector3(cx + hd + oe, y0 + wh - 0.1, cz + hw + oe), Vector3(cx - hd - oe, y0 + wh - 0.1, cz + hw + oe), roof, Vector3.UP)
	# Door frame posts on the open side.
	kit.box_at(Vector3(cx + hd - 0.2, y0 + wh * 0.5, cz - hw + 0.4), Vector3(0.4, wh, 0.8), trim)
	kit.box_at(Vector3(cx + hd - 0.2, y0 + wh * 0.5, cz + hw - 0.4), Vector3(0.4, wh, 0.8), trim)
	kit.box_at(Vector3(cx + hd - 0.2, y0 + wh - 0.3, cz), Vector3(0.4, 0.6, hw * 2.0), trim)
	# A drum and some timber by the wall for life.
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(cx + 2.0, y0 + 0.45, cz - hw - 1.2)), 0.3, 0.3, 0.9, 10, Color(0.45, 0.25, 0.12))
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(cx + 2.8, y0 + 0.45, cz - hw - 1.4)), 0.3, 0.3, 0.9, 10, Color(0.3, 0.33, 0.35))
	kit.box_at(Vector3(cx - 2.0, y0 + 0.2, cz - hw - 1.5), Vector3(3.6, 0.4, 0.8), Color(0.35, 0.27, 0.18))
	add_child(kit.instance("Hangar"))
	ground.add_hollow(Transform3D(Basis.IDENTITY, Vector3(cx, y0, cz)), Vector3(hd * 2.0, wh + ph, hw * 2.0), hw * 2.0 - 1.0)


const CARD_SHADER = preload("res://shaders/veg_cards.gdshader")
const Tex = preload("res://scripts/veg_textures.gd")
var _veg_mats := {}
var _mesh_cache := {}


func _veg_mat(kind: int = -1, cards: bool = false, layer: int = 0) -> ShaderMaterial:
	var k := "%d:%s:%d" % [kind if cards else -1, str(cards), layer]
	if not _veg_mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = CARD_SHADER if cards else VEG_SHADER
		if cards:
			var needly := layer == 0 and (kind == Flora.WHITE_SPRUCE or kind == Flora.BLACK_SPRUCE)
			m.set_shader_parameter("tex", Tex.frond() if needly else Tex.leaves())
		m.set_shader_parameter("sway", 0.6 if layer == 2 else 1.0)
		_veg_mats[k] = m
	return _veg_mats[k]


## A mesh with its proper materials: surface 0 solid parts, surface 1 the
## textured needle/leaf cards (this is what makes the trees look real).
func _veg_mesh(layer: int, kind: int, lod: int, bare: bool) -> ArrayMesh:
	var k := "%d:%d:%d:%s" % [layer, kind, lod, str(bare)]
	if not _mesh_cache.has(k):
		var m: ArrayMesh
		match layer:
			0: m = Meshes.tree_cards(kind, lod, bare)
			1: m = Meshes.shrub_cards(kind, bare)
			_: m = Meshes.ground(kind)
		m.surface_set_material(0, _veg_mat(kind, false, layer))
		if m.get_surface_count() > 1:
			m.surface_set_material(1, _veg_mat(kind, true, layer))
		_mesh_cache[k] = m
	return _mesh_cache[k]


func _plants() -> void:
	var focus := Vector2(0.0, -90.0)
	var buckets := {}        # "kind:lod:bare" -> [xforms, tints]
	var tn := int(ceil(ground.size / Flora.G))
	for j in range(tn):
		for i in range(tn):
			var tr := Flora.tree_at(ground, i, j)
			if tr.is_empty():
				continue
			var pos: Vector3 = tr["pos"]
			var hgt: float = tr["height"]
			var tint: float = tr["tint"]
			var girth := hgt * (0.9 + 0.25 * tint)
			var basis := Basis(Vector3.UP, float(tr["yaw"])).scaled(Vector3(girth, hgt, girth))
			var d := Vector2(pos.x, pos.z).distance_to(focus)
			var lod := 0 if d < 120.0 else (1 if d < 230.0 else 2)
			var bare: bool = int(tr["kind"]) == Flora.SNAG
			var key := "%d:%d:%s" % [int(tr["kind"]), lod, str(bare)]
			if not buckets.has(key):
				buckets[key] = [[], []]
			buckets[key][0].append(Transform3D(basis, pos - Vector3(0, 0.25, 0)))
			buckets[key][1].append(tint)
	for key in buckets:
		var parts: PackedStringArray = key.split(":")
		_scatter(_veg_mesh(0, int(parts[0]), int(parts[1]), parts[2] == "true"), buckets[key][0], buckets[key][1])
	# Shrubs.
	buckets = {}
	var sn := int(ceil(ground.size / Flora.SHRUB_G))
	for j in range(sn):
		for i in range(sn):
			var sh := Flora.shrub_at(ground, i, j)
			if sh.is_empty():
				continue
			var sz: float = sh["size"]
			var basis := Basis(Vector3.UP, float(sh["yaw"])).scaled(Vector3(sz, sz, sz))
			var key := str(int(sh["kind"]))
			if not buckets.has(key):
				buckets[key] = [[], []]
			buckets[key][0].append(Transform3D(basis, (sh["pos"] as Vector3) - Vector3(0, 0.1, 0)))
			buckets[key][1].append(float(sh["tint"]))
	for key in buckets:
		_scatter(_veg_mesh(1, int(key), 0, false), buckets[key][0], buckets[key][1])
	# Ground plants round the apron, strip and the cut.
	buckets = {}
	for reg in [[-120.0, 120.0, -180.0, -40.0], [20.0, 120.0, 20.0, 100.0]]:
		var i0 := int((reg[0] + ground.half) / Flora.GROUND_G)
		var i1 := int((reg[1] + ground.half) / Flora.GROUND_G)
		var j0 := int((reg[2] + ground.half) / Flora.GROUND_G)
		var j1 := int((reg[3] + ground.half) / Flora.GROUND_G)
		for j in range(j0, j1):
			for i in range(i0, i1):
				var gp := Flora.ground_at(ground, i, j)
				if gp.is_empty():
					continue
				var gs: float = gp["size"]
				var basis := Basis(Vector3.UP, float(gp["yaw"])).scaled(Vector3(gs, gs, gs))
				var key := str(int(gp["kind"]))
				if not buckets.has(key):
					buckets[key] = [[], []]
				buckets[key][0].append(Transform3D(basis, (gp["pos"] as Vector3) - Vector3(0, 0.05, 0)))
				buckets[key][1].append(float(gp["tint"]))
	for key in buckets:
		_scatter(_veg_mesh(2, int(key), 0, false), buckets[key][0], buckets[key][1])


func _scatter(mesh: Mesh, xforms: Array, tints: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in range(xforms.size()):
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_custom_data(k, Color(tints[k], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _machines() -> void:
	var pl := PlaneScript.new()
	add_child(pl)
	pl.apply_type("wolverine")
	var vis := PlaneVisual.new()
	vis.plane = pl
	pl.add_child(vis)
	pl.place_parked(Vector3(12.0, 6.15 + 1.66, -92.0),
		Quaternion(Basis(Vector3.UP, -1.1) * Basis(Vector3.RIGHT, deg_to_rad(11.0))))
	pl.frozen = true
	var dz := DozerScript.new()
	dz.terrain = ground
	add_child(dz)
	dz.build()
	dz.park(Transform3D(Basis(Vector3.UP, 2.3), Vector3(66.0, ground.height_at(66.0, 55.0), 55.0)))
	var ex := ExcavatorScript.new()
	ex.terrain = ground
	add_child(ex)
	ex.build()
	ex.park(Transform3D(Basis(Vector3.UP, -0.8), Vector3(88.0, ground.height_at(88.0, 52.0), 52.0)))


func _apply(i: int) -> void:
	var from: Vector3 = _views[i][1]
	var at: Vector3 = _views[i][2]
	_cam.transform = Transform3D(Basis.looking_at((at - from).normalized(), Vector3.UP), from)
	_cam.make_current()


func _process(_d: float) -> void:
	_frames += 1
	if _frames % 12 == 0:
		var vi := _frames / 12 - 1
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, _views[vi][0]])
		print("saved ", _views[vi][0])
		if vi + 1 >= _views.size():
			get_tree().quit()
			return
		_apply(vi + 1)
