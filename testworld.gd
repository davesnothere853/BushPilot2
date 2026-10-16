extends Node3D
## Bush Pilot 2 proving ground - the playable test world.
## Walk the apron, fly the plane off 09/27 (and out over the void), climb on
## the D8 and cut dirt anywhere: the whole square is one deformable ground.
##
## Keys (same scheme as before, registered by game.gd):
##   on foot   WASD walk, mouse look, Shift run, E interact (board/blade),
##             G get out / board
##   flying    WASD stick, Q/E rudder, Shift/Ctrl throttle, Space brakes,
##             F/R flaps, I auto engine start/stop, G climb out (stopped)
##   dozer     W/S drive, A/D steer, E blade up/down, G climb off

const Ground = preload("res://scripts/ground.gd")
const GroundView = preload("res://scripts/ground_view.gd")
const PlaneScript = preload("res://scripts/plane.gd")
const PlaneVisual = preload("res://scripts/plane_visual.gd")
const OnFoot = preload("res://scripts/on_foot.gd")
const DozerScript = preload("res://scripts/dozer.gd")
const Vegetation = preload("res://scripts/vegetation.gd")
const ExcavatorScript = preload("res://scripts/excavator.gd")
const WindScript = preload("res://scripts/wind.gd")
const MeshKit = preload("res://scripts/meshkit.gd")
const Flora = preload("res://scripts/flora.gd")
const Debris = preload("res://scripts/debris.gd")
const Water = preload("res://scripts/water.gd")

enum { WALK, FLY, DOZE }
var mode := WALK
var ground: RefCounted
var view: Node3D
var plane: Node3D
var visual: Node3D
var walker: Node3D
var dozer: Node3D
var excavator: Node3D
var machine: Node3D
var veg: Node3D
var wind: Node
var cam: Camera3D
var debris: Node3D
var _msg: Label
var _info: Label
var _msg_t := 0.0
var _chase_look := Vector2.ZERO
var _mouse := Vector2.ZERO


func _ready() -> void:
	ground = Ground.new()
	view = GroundView.new()
	add_child(view)
	view.setup(ground)
	wind = WindScript.new()
	add_child(wind)
	debris = Debris.new()
	add_child(debris)
	_weather()
	_water()
	_hangar()
	_spawn_plane()
	_spawn_walker()
	_spawn_dozer()
	_spawn_excavator()
	cam = Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	cam.make_current()
	veg = Vegetation.new()
	add_child(veg)
	veg.setup(ground)
	veg.camera = cam
	veg.wind = wind
	_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_say("Proving ground. %s to board the plane or the dozer, %s to interact." %
		[Game.hint("get_out"), Game.hint("interact")], 8.0)


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
	sun.shadow_blur = 1.6
	sun.directional_shadow_max_distance = 320.0
	add_child(sun)


var water: Node3D


func _water() -> void:
	water = Water.new()
	add_child(water)
	water.setup(Vector3(-105.0, 0, 105.0), 31.0, 3.2, 0.3)
	if wind != null and wind.has_method("now"):
		pass
	# Waves run with the game wind so the sock and the pond agree.
	var wv: Vector2 = Vector2(cos(deg_to_rad(Game.wind_dir_deg + 180.0)), sin(deg_to_rad(Game.wind_dir_deg + 180.0)))
	water.set_wind(wv, 0.25 + 0.15 * float(Game.wind_level))


func _hangar() -> void:
	var kit := MeshKit.new()
	var wall := Color(0.23, 0.30, 0.24)
	var trim := Color(0.16, 0.20, 0.17)
	var roof := Color(0.36, 0.34, 0.31)
	var cx := -36.0
	var cz := -86.0
	var y0 := 6.15
	var hw := 8.0
	var hd := 6.5
	var wh := 4.4
	var ph := 2.8
	kit.box_at(Vector3(cx - hd + 0.15, y0 + wh * 0.5, cz), Vector3(0.3, wh, hw * 2.0), wall)
	kit.box_at(Vector3(cx, y0 + wh * 0.5, cz - hw + 0.15), Vector3(hd * 2.0, wh, 0.3), wall)
	kit.box_at(Vector3(cx, y0 + wh * 0.5, cz + hw - 0.15), Vector3(hd * 2.0, wh, 0.3), wall)
	for xx in [cx - hd + 0.15, cx + hd - 0.15]:
		kit.tri(Vector3(xx, y0 + wh, cz - hw), Vector3(xx, y0 + wh, cz + hw),
			Vector3(xx, y0 + wh + ph, cz), wall, Vector3(1, 0, 0) if xx > cx else Vector3(-1, 0, 0))
	var oe := 0.5
	kit.quad(Vector3(cx - hd - oe, y0 + wh - 0.1, cz - hw - oe), Vector3(cx + hd + oe, y0 + wh - 0.1, cz - hw - oe),
		Vector3(cx + hd + oe, y0 + wh + ph, cz), Vector3(cx - hd - oe, y0 + wh + ph, cz), roof, Vector3.UP)
	kit.quad(Vector3(cx - hd - oe, y0 + wh + ph, cz), Vector3(cx + hd + oe, y0 + wh + ph, cz),
		Vector3(cx + hd + oe, y0 + wh - 0.1, cz + hw + oe), Vector3(cx - hd - oe, y0 + wh - 0.1, cz + hw + oe), roof, Vector3.UP)
	kit.box_at(Vector3(cx + hd - 0.2, y0 + wh * 0.5, cz - hw + 0.4), Vector3(0.4, wh, 0.8), trim)
	kit.box_at(Vector3(cx + hd - 0.2, y0 + wh * 0.5, cz + hw - 0.4), Vector3(0.4, wh, 0.8), trim)
	kit.box_at(Vector3(cx + hd - 0.2, y0 + wh - 0.3, cz), Vector3(0.4, 0.6, hw * 2.0), trim)
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(cx + 2.0, y0 + 0.45, cz - hw - 1.2)), 0.3, 0.3, 0.9, 10, Color(0.45, 0.25, 0.12))
	add_child(kit.instance("Hangar"))
	ground.add_hollow(Transform3D(Basis.IDENTITY, Vector3(cx, y0, cz)), Vector3(hd * 2.0, wh + ph, hw * 2.0), hw * 2.0 - 1.0)
	# A windsock by the strip.
	var wk := MeshKit.new()
	wk.cylinder(Transform3D(Basis.IDENTITY, Vector3(-20.0, 6.2 + 2.5, -118.0)), 0.05, 0.04, 5.0, 6, Color(0.7, 0.7, 0.7))
	wk.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-20.0, 6.2 + 4.8, -118.6)), 0.22, 0.1, 1.2, 8, Color(0.85, 0.35, 0.1), false)
	add_child(wk.instance("Windsock"))


func _spawn_plane() -> void:
	plane = PlaneScript.new()
	add_child(plane)
	plane.apply_type("wolverine")
	plane.terrain = ground
	plane.wind = wind
	visual = PlaneVisual.new()
	visual.plane = plane
	visual.debris = debris
	visual.wind = wind
	plane.add_child(visual)
	plane.place_parked(Vector3(12.0, 6.15 + 1.66, -92.0), Quaternion(Basis(Vector3.UP, -1.1)))


func _spawn_walker() -> void:
	walker = OnFoot.new()
	walker.terrain = ground
	walker.extra_planes = func() -> Array: return []
	walker.notice = func(t: String) -> void: _say(t, 4.0)
	add_child(walker)
	walker.place(Vector3(6.0, 6.3, -88.0), 2.4)


func _spawn_dozer() -> void:
	dozer = DozerScript.new()
	dozer.terrain = ground
	add_child(dozer)
	dozer.build()
	dozer.park(Transform3D(Basis(Vector3.UP, 2.3), Vector3(66.0, ground.height_at(66.0, 55.0), 55.0)))
	dozer.on_grade = func(p: Vector3, radius: float, target: float, fill_m3: float, cut_m3: float) -> Dictionary:
		return ground.level(p, radius, target, fill_m3, cut_m3)
	dozer.on_spill = func(p: Vector3, vol: float) -> void:
		ground.deposit(p, vol)
	dozer.on_tree = func(tr: Dictionary, impulse: Vector3) -> void:
		if tr.has("i"):
			veg.fell(int(tr["i"]), int(tr["j"]), impulse)
			_say("Pushed a tree over.", 2.0)


func _spawn_excavator() -> void:
	excavator = ExcavatorScript.new()
	excavator.terrain = ground
	add_child(excavator)
	excavator.build()
	excavator.park(Transform3D(Basis(Vector3.UP, -0.8), Vector3(88.0, ground.height_at(88.0, 52.0), 52.0)))
	excavator.on_dig = func(p: Vector3, m3: float) -> Dictionary:
		return ground.dig(p, 0.9, m3)
	excavator.on_dump = func(p: Vector3, load: Dictionary) -> String:
		var vol: float = float(load.get("over", 0.0)) + float(load.get("pay", 0.0))
		ground.deposit(p, vol)
		if float(load.get("pay", 0.0)) > 0.05:
			return "Dumped %.1f m3 (some of it pay gravel)." % vol
		return "Dumped %.1f m3." % vol


func _ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	_msg = Label.new()
	_msg.position = Vector2(24, 18)
	_msg.add_theme_font_size_override("font_size", 20)
	_msg.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	_msg.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_msg.add_theme_constant_override("outline_size", 6)
	cl.add_child(_msg)
	_info = Label.new()
	_info.position = Vector2(24, 54)
	_info.add_theme_font_size_override("font_size", 16)
	_info.add_theme_color_override("font_color", Color(0.85, 0.88, 0.85))
	_info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_info.add_theme_constant_override("outline_size", 5)
	cl.add_child(_info)


func _say(t: String, dur: float = 4.0) -> void:
	_msg.text = t
	_msg_t = dur


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative * 0.0022 * Game.look_speed
		if mode == WALK:
			walker.look.x -= rel.x
			walker.look.y = clampf(walker.look.y - rel.y, -1.35, 1.25)
		else:
			_chase_look.x -= rel.x
			_chase_look.y = clampf(_chase_look.y - rel.y, -0.9, 0.9)
		return
	if event.is_action_pressed("menu"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed("fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		return
	if event.is_action_pressed("get_out"):
		_toggle_mounts()
		return
	match mode:
		FLY:
			_fly_keys(event)
		WALK:
			if event.is_action_pressed("interact"):
				_walk_interact()
		DOZE:
			if event.is_action_pressed("interact"):
				if machine == dozer:
					_say(dozer.blade_toggle(), 3.0)
				else:
					excavator.dig_or_dump()


func _toggle_mounts() -> void:
	match mode:
		FLY:
			if plane.airborne or plane.vel.length() > 2.0:
				_say("Stop first.", 2.0)
				return
			plane.throttle = 0.0
			mode = WALK
			var door: Vector3 = plane.global_position + plane.global_transform.basis * Vector3(-1.4, -1.2, 0.2)
			walker.place(Vector3(door.x, ground.ground_level_at(door.x, door.z) + 0.1, door.z), _chase_look.x)
			walker.visible = true
			_say("Out. %s near the door to board again." % Game.hint("get_out"), 4.0)
		WALK:
			var pp: Vector3 = plane.global_position
			var wp: Vector3 = walker.global_position
			if Vector2(pp.x - wp.x, pp.z - wp.z).length() < 4.5:
				mode = FLY
				walker.visible = false
				_say(plane.engine_hint() if plane.has_method("engine_hint") else
					"Press %s for an automatic engine start." % Game.hint("engine_auto"), 5.0)
				return
			for m in [dozer, excavator]:
				var dp: Vector3 = m.global_position
				if Vector2(dp.x - wp.x, dp.z - wp.z).length() < 4.0:
					machine = m
					mode = DOZE
					walker.visible = false
					if m == dozer:
						_say("%s blade up/down, %s climb off." % [Game.hint("interact"), Game.hint("get_out")], 4.0)
					else:
						_say("Look where to dig; %s dig / dump, %s climb off." % [Game.hint("interact"), Game.hint("get_out")], 5.0)
					return
			_say("Nothing here to board. The plane is on the apron, the machines at the cut.", 3.0)
		DOZE:
			mode = WALK
			var off: Vector3 = machine.global_position + machine.global_transform.basis * Vector3(1.8, 0, 0)
			walker.place(Vector3(off.x, ground.ground_level_at(off.x, off.z) + 0.1, off.z), _chase_look.x)
			walker.visible = true


func _walk_interact() -> void:
	var wp: Vector3 = walker.global_position
	var l: String = ground.layer_at(wp.x, wp.z)
	_say("Ground here: %s.  Pay runs %.1f-%.1f m down." %
		[l, ground.pay_top[_cell(wp)], ground.bedrock[_cell(wp)]], 4.0)


func _cell(p: Vector3) -> int:
	var i := clampi(int((p.x + ground.SQ) / ground.FRES), 0, ground.FN)
	var j := clampi(int((p.z + ground.SQ) / ground.FRES), 0, ground.FN)
	return j * (ground.FN + 1) + i


func _fly_keys(event: InputEvent) -> void:
	if event.is_action_pressed("engine_auto"):
		plane.toggle_auto_sequence()
	elif event.is_action_pressed("flaps_down"):
		if plane.flap_notch < 4:
			plane.flap_notch += 1
			_say("Flaps %d°" % plane.flap_degrees(), 2.0)
	elif event.is_action_pressed("flaps_up"):
		if plane.flap_notch > 0:
			plane.flap_notch -= 1
			_say(("Flaps %d°" % plane.flap_degrees()) if plane.flap_notch > 0 else "Flaps up", 2.0)


func _physics_process(delta: float) -> void:
	match mode:
		WALK:
			plane.in_pitch = 0.0
			plane.in_roll = 0.0
			plane.in_yaw = 0.0
			plane.brake = 1.0
			var move := Vector2(Input.get_axis("roll_left", "roll_right"), Input.get_axis("pitch_up", "pitch_down"))
			walker.step(delta, move, Input.is_action_pressed("throttle_up"), Input.is_action_just_pressed("brake"))
		DOZE:
			plane.brake = 1.0
			var move := Vector2(Input.get_axis("roll_left", "roll_right"), Input.get_axis("pitch_down", "pitch_up"))
			if machine == dozer:
				var m: String = dozer.drive(delta, move)
				if m != "":
					_say(m, 2.5)
			else:
				excavator.drive(delta, move)
				excavator.aim_from(cam.global_position, -cam.global_transform.basis.z)
				var m2: String = excavator.work(delta)
				if m2 != "":
					_say(m2, 3.0)
		FLY:
			var pitch := Input.get_axis("pitch_down", "pitch_up")
			if Game.invert_pitch:
				pitch = -pitch
			var roll := Input.get_axis("roll_left", "roll_right")
			var yaw := Input.get_axis("yaw_left", "yaw_right")
			if Game.using_gamepad:
				var expo := clampf(2.6 - Game.stick_sensitivity, 1.0, 2.2)
				pitch = signf(pitch) * pow(absf(pitch), expo)
				roll = signf(roll) * pow(absf(roll), expo)
				yaw = signf(yaw) * pow(absf(yaw), maxf(expo - 0.2, 1.0))
			plane.direct_controls = Game.using_gamepad
			plane.in_pitch = clampf(pitch, -1.0, 1.0)
			plane.in_roll = clampf(roll, -1.0, 1.0)
			plane.in_yaw = clampf(yaw, -1.0, 1.0)
			var thr := Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down")
			plane.throttle = clampf(plane.throttle + thr * 0.55 * delta, 0.0, 1.0)
			plane.brake = Input.get_action_strength("brake")
			plane.brake_left = Input.get_action_strength("brake_left")
			plane.brake_right = Input.get_action_strength("brake_right")
			var trim := Input.get_action_strength("trim_up") - Input.get_action_strength("trim_down")
			plane.trim = clampf(plane.trim + trim * 0.28 * delta, -1.0, 1.0)


func _process(delta: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			_msg.text = ""
	match mode:
		WALK:
			cam.global_transform = walker.camera_transform()
			_info.text = ""
		DOZE:
			var eye: Transform3D = machine.eye_xf()
			var look := Basis(Vector3.UP, _chase_look.x) * Basis(Vector3.RIGHT, _chase_look.y)
			cam.global_transform = Transform3D(machine.global_transform.basis * look, eye.origin)
			if machine == dozer:
				_info.text = "blade %.1f m3" % dozer.load_m3
			else:
				_info.text = "bucket: %s" % ("loaded" if not excavator.bucket_load.is_empty() else "empty")
		FLY:
			var yaw := Basis(Vector3.UP, _plane_yaw() + PI + _chase_look.x)
			var tilt := Basis(Vector3.RIGHT, -0.12 + _chase_look.y)
			var back: Vector3 = (yaw * tilt) * Vector3(0, 0, 11.0) + Vector3(0, 2.6, 0)
			var pos: Vector3 = plane.global_position + back
			var gy: float = ground.ground_level_at(pos.x, pos.z) + 0.4
			pos.y = maxf(pos.y, gy)
			cam.global_transform = Transform3D(Basis.looking_at((plane.global_position + Vector3(0, 1.2, 0) - pos).normalized(), Vector3.UP), pos)
			_info.text = "%3.0f kt   %4.0f ft   rpm %4.0f   flaps %d°   %s" % [
				plane.vel.length() * 1.94384, plane.global_position.y * 3.28084,
				plane.engine.rpm, plane.flap_degrees(),
				"ENGINE RUNNING" if plane.engine_running else "engine off (%s to start)" % Game.hint("engine_auto")]


func _plane_yaw() -> float:
	var f: Vector3 = plane.global_transform.basis * Vector3.FORWARD
	return atan2(-f.x, -f.z)
