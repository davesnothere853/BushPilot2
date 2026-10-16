extends RefCounted
## Fire, smoke and explosion effects, plus the soft puff texture they share.

static var _puff: Texture2D
static var _flame_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D


## A soft, slightly lumpy round puff: white with alpha falling to nothing at the edge.
static func puff_texture() -> Texture2D:
	if _puff != null:
		return _puff
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.07
	noise.fractal_octaves = 3
	for y in range(size):
		for x in range(size):
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var lump := 0.75 + 0.25 * noise.get_noise_2d(x, y)
			var a := clampf(1.0 - smoothstep(0.25 * lump, 1.0 * lump, d), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	img.generate_mipmaps()
	_puff = ImageTexture.create_from_image(img)
	return _puff


static func flame_material() -> StandardMaterial3D:
	if _flame_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = puff_texture()
		m.albedo_color = Color(2.2, 2.0, 1.8, 1.0)
		_flame_mat = m
	return _flame_mat


static func smoke_material() -> StandardMaterial3D:
	if _smoke_mat == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = puff_texture()
		m.roughness = 1.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_smoke_mat = m
	return _smoke_mat


static func particles(mat: Material, count: int, life: float, size: float, ramp: Gradient, grow: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	p.mesh = quad
	p.amount = count
	p.lifetime = life
	p.local_coords = false
	p.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, grow))
	p.scale_amount_curve = curve
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func gradient(stops: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for st in stops:
		offsets.append(st[0])
		colors.append(st[1])
	g.offsets = offsets
	g.colors = colors
	return g


## A burning wreck: flames, embers, a column of smoke drifting downwind and a
## flickering light. Call set_strength() as the fire grows or dies.
static func make_fire() -> Node3D:
	var root := Node3D.new()
	root.name = "Fire"
	var flames := particles(flame_material(), 110, 0.9, 1.6,
		gradient([[0.0, Color(1.0, 0.95, 0.7, 0.0)], [0.08, Color(1.0, 0.85, 0.45, 0.9)], [0.4, Color(1.0, 0.45, 0.12, 0.7)], [0.75, Color(0.6, 0.15, 0.05, 0.35)], [1.0, Color(0.2, 0.05, 0.02, 0.0)]]), 1.6)
	flames.name = "Flames"
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 1.1
	flames.direction = Vector3.UP
	flames.spread = 20.0
	flames.initial_velocity_min = 1.5
	flames.initial_velocity_max = 4.0
	flames.gravity = Vector3(0, 4.0, 0)
	flames.damping_min = 0.5
	flames.damping_max = 1.5
	root.add_child(flames)
	var smoke := particles(smoke_material(), 90, 11.0, 4.0,
		gradient([[0.0, Color(0.12, 0.11, 0.10, 0.0)], [0.06, Color(0.10, 0.09, 0.08, 0.75)], [0.5, Color(0.22, 0.21, 0.20, 0.5)], [1.0, Color(0.45, 0.45, 0.45, 0.0)]]), 7.0)
	smoke.name = "Smoke"
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 1.0
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.initial_velocity_min = 3.0
	smoke.initial_velocity_max = 5.5
	smoke.gravity = Vector3(0, 1.0, 0)
	smoke.damping_min = 0.2
	smoke.damping_max = 0.4
	smoke.position = Vector3(0, 1.5, 0)
	root.add_child(smoke)
	var embers := particles(flame_material(), 40, 2.0, 0.12,
		gradient([[0.0, Color(1.0, 0.8, 0.4, 1.0)], [1.0, Color(1.0, 0.3, 0.05, 0.0)]]), 0.6)
	embers.name = "Embers"
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 1.2
	embers.direction = Vector3.UP
	embers.spread = 35.0
	embers.initial_velocity_min = 3.0
	embers.initial_velocity_max = 7.0
	embers.gravity = Vector3(0, -1.5, 0)
	root.add_child(embers)
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 28.0
	light.light_energy = 4.0
	light.shadow_enabled = false
	light.position = Vector3(0, 1.2, 0)
	root.add_child(light)
	# the roar and crackle of it (bp2_audio/gen_fx.py fire.wav)
	var st: AudioStream = load("res://scripts/audio.gd")._file("res://assets/sounds/fx/fire.wav", true)
	if st != null:
		var snd := AudioStreamPlayer3D.new()
		snd.name = "Sound"
		snd.stream = st
		snd.unit_size = 6.0
		snd.max_distance = 300.0
		snd.volume_db = -12.0
		snd.pitch_scale = randf_range(0.9, 1.1)
		snd.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		snd.autoplay = true
		root.add_child(snd)
	return root


static func set_fire_strength(fire: Node3D, strength: float, wind: Vector3, t: float) -> void:
	var flames: CPUParticles3D = fire.get_node("Flames")
	var smoke: CPUParticles3D = fire.get_node("Smoke")
	var embers: CPUParticles3D = fire.get_node("Embers")
	var light: OmniLight3D = fire.get_node("Glow")
	var burning := strength > 0.18
	var snd := fire.get_node_or_null("Sound") as AudioStreamPlayer3D
	if snd != null:
		snd.volume_db = linear_to_db(clampf(0.15 + 0.85 * strength, 0.001, 1.0)) - 4.0 if strength > 0.05 else -80.0
	flames.emitting = burning
	embers.emitting = burning
	smoke.emitting = strength > 0.01
	flames.scale_amount_min = 0.5 + strength
	flames.scale_amount_max = 1.0 + 1.6 * strength
	smoke.scale_amount_min = 0.6 + 0.6 * strength
	smoke.scale_amount_max = 1.0 + 1.2 * strength
	# Smoke leans downwind; a smouldering wreck gives thin pale smoke.
	smoke.gravity = Vector3(wind.x * 0.35, 0.8 + 1.4 * strength, wind.z * 0.35)
	smoke.color_ramp.set_color(1, Color(0.10, 0.09, 0.08, 0.75) if burning else Color(0.45, 0.45, 0.44, 0.35))
	var flicker := 0.75 + 0.25 * sin(t * 23.0) * sin(t * 7.3 + 1.0)
	light.light_energy = (1.0 + 6.0 * strength) * flicker if burning else 0.0


## A one-shot explosion: fireball, flash, dust and smoke. Frees itself.
static func make_explosion(strength: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Explosion"
	var ball := particles(flame_material(), 70, 1.4, 3.5 * strength,
		gradient([[0.0, Color(1.0, 1.0, 0.9, 1.0)], [0.15, Color(1.0, 0.8, 0.4, 1.0)], [0.45, Color(1.0, 0.4, 0.1, 0.8)], [0.8, Color(0.3, 0.1, 0.05, 0.4)], [1.0, Color(0.05, 0.05, 0.05, 0.0)]]), 2.4)
	ball.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ball.emission_sphere_radius = 1.5
	ball.direction = Vector3.UP
	ball.spread = 180.0
	ball.initial_velocity_min = 6.0 * strength
	ball.initial_velocity_max = 16.0 * strength
	ball.damping_min = 6.0
	ball.damping_max = 9.0
	ball.gravity = Vector3(0, 3.0, 0)
	ball.explosiveness = 1.0
	ball.one_shot = true
	root.add_child(ball)
	var dark := particles(smoke_material(), 40, 6.0, 5.0 * strength,
		gradient([[0.0, Color(0.05, 0.05, 0.05, 0.0)], [0.1, Color(0.06, 0.05, 0.05, 0.85)], [1.0, Color(0.3, 0.3, 0.3, 0.0)]]), 3.5)
	dark.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dark.emission_sphere_radius = 2.0
	dark.direction = Vector3.UP
	dark.spread = 70.0
	dark.initial_velocity_min = 4.0
	dark.initial_velocity_max = 9.0
	dark.damping_min = 1.5
	dark.damping_max = 2.5
	dark.gravity = Vector3(0, 1.5, 0)
	dark.explosiveness = 0.9
	dark.one_shot = true
	root.add_child(dark)
	var dust := particles(smoke_material(), 36, 3.5, 3.0,
		gradient([[0.0, Color(0.45, 0.40, 0.33, 0.0)], [0.1, Color(0.45, 0.40, 0.33, 0.6)], [1.0, Color(0.5, 0.46, 0.4, 0.0)]]), 4.0)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_radius = 2.0
	dust.emission_ring_inner_radius = 1.0
	dust.emission_ring_height = 0.2
	dust.emission_ring_axis = Vector3.UP
	dust.direction = Vector3(1, 0, 0)
	dust.spread = 180.0
	dust.flatness = 1.0
	dust.initial_velocity_min = 10.0
	dust.initial_velocity_max = 18.0
	dust.damping_min = 5.0
	dust.damping_max = 7.0
	dust.explosiveness = 1.0
	dust.one_shot = true
	root.add_child(dust)
	var flash := OmniLight3D.new()
	flash.name = "Flash"
	flash.light_color = Color(1.0, 0.7, 0.35)
	flash.omni_range = 70.0
	flash.light_energy = 30.0 * strength
	root.add_child(flash)
	for c in root.get_children():
		if c is CPUParticles3D:
			(c as CPUParticles3D).emitting = true
	var tw := root.create_tween() if root.is_inside_tree() else null
	if tw == null:
		root.tree_entered.connect(func():
			var tw2 := root.create_tween()
			tw2.tween_property(flash, "light_energy", 0.0, 0.6)
			tw2.tween_interval(7.0)
			tw2.tween_callback(root.queue_free), CONNECT_ONE_SHOT)
	return root
