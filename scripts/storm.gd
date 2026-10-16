extends Node3D
## The main menu's wet night, out in the real world (Dave: "can you make the
## map look like the main menu" / "the weather looks great"). Works on top of
## world.gd's sky and fog, every frame:
##  - wet: rain soaks everything over a couple of minutes (bp_rain in the ground
##    shader: darker, glossy, puddles that mirror the lights) and it dries
##    slowly after;
##  - the light: at night and in rain the glow and haze go toward the menu's -
##    lights bloom, a volumetric haze that eats the far ones;
##  - runway halos: the runway lights nearest you throw real light into the
##    haze and streaks on the wet strip;
##  - lightning in rain: a double flash, thunder a few seconds after.

const VoxelGroundLib = preload("res://scripts/voxel_ground.gd")
const RATE := 22050
const POOL := 12

var world: Node
var wet := 0.0
var _pool: Array[OmniLight3D] = []
var _pick_t := 0.0
var _next_flash := 25.0
var _flash := 0.0
var _flash_age := 9.0
var _flash_light: DirectionalLight3D
var _thunder: AudioStreamPlayer
var _thunder_in := -1.0
var _rng := RandomNumberGenerator.new()
var _bolt: MeshInstance3D
var _bolt_mat: StandardMaterial3D
var _bolt_light: OmniLight3D
var _bolt_age := 9.0
var _gust := 1.0
var _gust_goal := 1.0
var _gust_t := 6.0
var _gust_hold := 0.0
var _whoosh: AudioStreamPlayer


func _ready() -> void:
	_rng.randomize()
	for i in range(POOL):
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.85, 0.62)
		ol.omni_range = 10.0
		ol.omni_attenuation = 1.6
		ol.light_energy = 0.0
		ol.light_volumetric_fog_energy = 2.5
		ol.shadow_enabled = false
		ol.visible = false
		add_child(ol)
		_pool.append(ol)
	_flash_light = DirectionalLight3D.new()
	_flash_light.light_color = Color(0.74, 0.80, 1.0)
	_flash_light.light_energy = 0.0
	_flash_light.rotation_degrees = Vector3(-55, 35, 0)
	_flash_light.shadow_enabled = false
	_flash_light.light_volumetric_fog_energy = 1.5
	add_child(_flash_light)
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.albedo_color = Color(0.85, 0.88, 1.0)
	_bolt_mat.emission_enabled = true
	_bolt_mat.emission = Color(0.8, 0.85, 1.0)
	_bolt_mat.emission_energy_multiplier = 12.0
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt = MeshInstance3D.new()
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)
	_bolt_light = OmniLight3D.new()
	_bolt_light.light_color = Color(0.78, 0.84, 1.0)
	_bolt_light.omni_range = 900.0
	_bolt_light.light_energy = 0.0
	_bolt_light.shadow_enabled = false
	add_child(_bolt_light)
	_whoosh = AudioStreamPlayer.new()
	_whoosh.stream = _gust_shot()
	_whoosh.volume_db = -14.0
	add_child(_whoosh)
	_thunder = AudioStreamPlayer.new()
	_thunder.stream = _thunder_shot()
	_thunder.volume_db = -6.0
	add_child(_thunder)


func _process(dt: float) -> void:
	if world == null:
		return
	var raining: bool = Game.weather == 2 and Game.season != Game.WINTER
	wet = move_toward(wet, 1.0 if raining else 0.0, dt / (90.0 if raining else 480.0))
	VoxelGroundLib.set_global("bp_rain", wet)
	var env: Environment = world.get("_env")
	var n: float = float(world.night)
	var k := clampf(maxf(n, wet * 0.7), 0.0, 1.0)
	if env != null and k > 0.01:
		# the menu's light: bloom off every lamp, a haze that swallows the far ones
		env.glow_intensity = lerpf(env.glow_intensity, 0.9, k)
		env.glow_bloom = lerpf(0.03, 0.04, k)
		env.glow_hdr_threshold = lerpf(env.glow_hdr_threshold, 0.9, k)
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.002 + 0.010 * wet + 0.004 * n
		env.volumetric_fog_albedo = Color(0.75, 0.78, 0.82)
		env.volumetric_fog_anisotropy = 0.55
		env.volumetric_fog_length = 160.0
		env.volumetric_fog_emission_energy = 0.0
		if wet > 0.2 and not env.ssr_enabled:
			env.ssr_enabled = true      # the light streaks on the wet strip
			env.ssr_max_steps = 48
	elif env != null and env.volumetric_fog_enabled:
		env.volumetric_fog_enabled = false
		env.ssr_enabled = Game.gfx_ssr
	_lightning(dt, raining)
	# a rainy night is BLACK, as on the menu: only the runway lights show, and
	# the lightning lights the whole place up for a moment
	var dark := n * smoothstep(0.2, 0.8, wet)
	var sun: DirectionalLight3D = world.get("_sun")
	if env != null and dark > 0.01:
		var f: float = _flash_light.light_energy / 3.5
		env.ambient_light_energy = lerpf(0.34, 0.07, dark) + f * 0.5 * dark
		env.background_energy_multiplier = lerpf(1.0, 0.14, dark) + f * 1.2 * dark
		env.fog_light_color = env.fog_light_color.lerp(Color(0.02, 0.025, 0.03), dark)
		if sun != null:
			sun.light_energy = maxf(sun.light_energy * (1.0 - 0.85 * dark), 0.02)
	elif env != null:
		env.background_energy_multiplier = 1.0
	# any night: a touch more light to see by (Dave: "brighter, not bright")
	if env != null and n > 0.3 and dark <= 0.01:
		env.ambient_light_energy = maxf(env.ambient_light_energy, lerpf(0.25, 0.36, smoothstep(0.3, 0.9, n)))
	_gusts(dt, raining)
	_bolts(dt)
	_runway_halos(dt, n)
	_rain_cover()


## The nearest runway lights get a real light each (a pool, moved every half
## second), so they glow in the haze and shine on the wet ground.
func _runway_halos(dt: float, n: float) -> void:
	var on := smoothstep(0.4, 0.9, n)
	_pick_t -= dt
	var cam := get_viewport().get_camera_3d()
	if on <= 0.01 or cam == null:
		for ol in _pool:
			ol.visible = false
		return
	if _pick_t <= 0.0:
		_pick_t = 0.5
		var pts: Array = world.get("runway_pts")
		var cp := cam.global_position
		var near: Array = []
		for e in pts:
			var d: float = ((e[0] as Vector3) - cp).length_squared()
			if d < 500.0 * 500.0:
				near.append([d, e])
		near.sort_custom(func(a, b): return a[0] < b[0])
		for i in range(POOL):
			var ol := _pool[i]
			if i < near.size():
				var e: Array = near[i][1]
				ol.global_position = (e[0] as Vector3) + Vector3(0, 0.4, 0)
				ol.light_color = (e[1] as Color)
				ol.visible = true
			else:
				ol.visible = false
	for ol in _pool:
		ol.light_energy = 1.4 * on


func _lightning(dt: float, raining: bool) -> void:
	_flash_age += dt
	var dry_storm: bool = Game.weather == 1 and Game.wind_level >= 2 and Game.season != Game.WINTER
	if (raining and wet > 0.3) or dry_storm:
		_next_flash -= dt
		if _next_flash <= 0.0:
			_next_flash = _rng.randf_range(18.0, 55.0)
			_flash_age = 0.0
			_thunder_in = _strike()                      # sound comes after the light: how far off it struck
			_flash_light.rotation_degrees = Vector3(-_rng.randf_range(30.0, 65.0), _rng.randf_range(0.0, 360.0), 0)
	# a double flash: bright, a flicker, a second one
	var a := _flash_age
	var f := 0.0
	if a < 0.08:
		f = 1.0
	elif a < 0.16:
		f = 0.25
	elif a < 0.30:
		f = 0.8
	elif a < 0.6:
		f = 0.8 * (1.0 - (a - 0.30) / 0.30)
	_flash_light.light_energy = f * 3.5
	_flash_light.visible = f > 0.0
	if _thunder_in > 0.0:
		_thunder_in -= dt
		if _thunder_in <= 0.0:
			_thunder.volume_db = -2.0 - 3.0 * _rng.randf()
			_thunder.play()


## Thunder made from noise (as the menu's): a crack, then rolling rumble.
func _thunder_shot() -> AudioStreamWAV:
	var n := RATE * 6
	var data := PackedByteArray()
	data.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 23
	var a := 0.0
	var b2 := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var w := r.randf_range(-1.0, 1.0)
		a += (w - a) * 0.008
		b2 += (w - b2) * 0.05
		var env := (1.0 - exp(-t * 8.0)) * exp(-t * 0.55) * (0.6 + 0.4 * sin(TAU * 0.7 * t + sin(t * 2.3)))
		var v := clampf((a * 9.0 + b2 * 0.6 * exp(-t * 2.0)) * env, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


## No rain indoors, and none inside a cab or cockpit: the streaks are cut away
## round the camera there (you see it out the windshield), hidden in buildings.
func _rain_cover() -> void:
	var pr: CPUParticles3D = world.get("_precip")
	var cam := get_viewport().get_camera_3d()
	if pr == null or cam == null:
		return
	var main := world.get_parent()
	var inside := false
	var cp := cam.global_position
	var terr = world.get("terrain")
	if terr != null and terr.has_method("hollow_at"):
		var h: Dictionary = terr.hollow_at(cp.x, cp.z)
		inside = not h.is_empty()
	var in_cab := false
	if main != null and main.get("on_foot") != null:
		var walker = main.get("walker")
		var fp: bool = walker != null and bool(walker.get("first_person"))
		in_cab = fp and (not bool(main.get("on_foot")) or main.get("driving") != null)
	pr.visible = not inside
	var q := pr.mesh as QuadMesh
	if q != null and q.material is ShaderMaterial:
		(q.material as ShaderMaterial).set_shader_parameter("near_cut", 2.6 if in_cab else 0.0)


## A bolt to the ground somewhere round you (0.6-4 km off): a jagged channel
## from the cloud with a few forks, bright for a moment, lighting the ground
## round it. Returns how long the thunder takes to get here (s).
func _strike() -> float:
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam != null else Vector3.ZERO
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(600.0, 4000.0)
	var gx := cp.x + cos(ang) * dist
	var gz := cp.z + sin(ang) * dist
	var terr = world.get("terrain")
	# a third of the strikes come down on the claim (when you're within a few
	# km of it): on the tallest thing about - a tree or a building's roof
	var hit := Vector3.INF
	if _target != Vector3.INF:
		hit = _target
		_target = Vector3.INF
		gx = hit.x
		gz = hit.z
		dist = cp.distance_to(hit)
	elif force_near or (Vector2(cp.x, cp.z).length() < 3000.0 and _rng.randf() < 0.33):
		hit = _strike_target(terr)
		if hit != Vector3.INF:
			gx = hit.x
			gz = hit.z
			dist = cp.distance_to(hit)
	force_near = false
	var gy: float = terr.height_at(gx, gz) if terr != null else 0.0
	if hit != Vector3.INF:
		gy = hit.y
	var top := gy + _rng.randf_range(700.0, 1000.0)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _bolt_mat)
	var forks: Array = [[Vector3(gx + _rng.randf_range(-150, 150), top, gz + _rng.randf_range(-150, 150)), Vector3(gx, gy, gz), 2.2]]
	var k := 0
	while k < forks.size() and k < 6:
		var a: Vector3 = forks[k][0]
		var b: Vector3 = forks[k][1]
		var w: float = forks[k][2]
		var n := 26
		var prev := a
		for i in range(1, n + 1):
			var t := float(i) / float(n)
			var q := a.lerp(b, t)
			if i < n:
				q += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1, 1)) * 38.0 * sin(t * PI)
			_bolt_seg(im, prev, q, w * (1.0 - t * 0.5), cp)
			if k == 0 and i < n - 4 and _rng.randf() < 0.12:
				var fb := q + Vector3(_rng.randf_range(-260, 260), -_rng.randf_range(120, 380), _rng.randf_range(-260, 260))
				forks.append([q, fb, w * 0.45])
			prev = q
		k += 1
	im.surface_end()
	_bolt.mesh = im
	_bolt_light.global_position = Vector3(gx, gy + 60.0, gz)
	_bolt_age = 0.0
	if hit != Vector3.INF:
		_ignite(hit)
	return dist / 343.0


var force_near := false            # console "lightning": the next strike hits the claim


## A strike right on `p` (story_mission.gd: the tree across the runway):
## the bolt, the light, thunder almost at once.
func strike_at(p: Vector3) -> void:
	_target = p
	_flash_age = 0.0
	_thunder_in = _strike()
	_thunder_in = minf(_thunder_in, 0.25)


var _target := Vector3.INF


## Strike now (console: lightning).
func strike_now() -> String:
	force_near = true
	_next_flash = 0.0
	_flash_age = 0.0
	_thunder_in = _strike()
	return "Lightning."


## The tallest thing near a random spot on the claim: a building's roof
## sometimes, otherwise a tree (it's the trees that take it most).
func _strike_target(terr) -> Vector3:
	var sts = world.get("structures")
	if sts != null and _rng.randf() < 0.3:
		var ids: Array = (sts.get("items") as Dictionary).keys()
		ids.shuffle()
		for id in ids:
			var it: Dictionary = sts.items[id]
			if not bool(it.get("burnt", false)) and it.has("xf"):
				var o: Vector3 = (it["xf"] as Transform3D).origin
				return o + Vector3(0, 5.0, 0)
	for k in range(80):
		var half: float = float(terr.SQ) - 10.0
		var q := Vector3(_rng.randf_range(-half, half), 0, _rng.randf_range(-half, half))
		var t: Dictionary = terr.tree_near(q) if terr.has_method("tree_near") else {}
		if not t.is_empty() and t.has("base"):
			var tp: Vector3 = t["base"]
			return Vector3(tp.x, terr.height_at(tp.x, tp.z) + float(t.get("height", 12.0)), tp.z)
	return Vector3.INF


## Where it struck: the tree or the roof catches. Dry ground and a wind
## behind it and it runs (fire.gd spreads downwind, faster in the gusts);
## in steady rain a strike mostly just scorches.
func _ignite(at: Vector3) -> void:
	var main := world.get_parent()
	var fire = main.get("fire") if main != null else null
	var ground := Vector3(at.x, float(world.terrain.height_at(at.x, at.z)), at.z)
	var catch_chance := 0.85 if Game.weather != 2 else 0.3
	if _rng.randf() < catch_chance:
		if fire != null:
			fire.ignite(ground, 5.0)
		var sts = world.get("structures")
		if sts != null and sts.has_method("ignite_near"):
			sts.ignite_near(at, 8.0)
		var hud = main.get("hud")
		if hud != null and Vector2(ground.x, ground.z).length() < 400.0:
			hud.push_message("Lightning strike on the claim - fire!", 5.0)


func _bolt_seg(im: ImmediateMesh, a: Vector3, b: Vector3, w: float, cp: Vector3) -> void:
	var along := (b - a).normalized()
	var side := along.cross((a - cp).normalized()).normalized() * w
	im.surface_add_vertex(a - side)
	im.surface_add_vertex(a + side)
	im.surface_add_vertex(b + side)
	im.surface_add_vertex(a - side)
	im.surface_add_vertex(b + side)
	im.surface_add_vertex(b - side)


func _bolts(dt: float) -> void:
	_bolt_age += dt
	var a := _bolt_age
	var on := a < 0.07 or (a > 0.12 and a < 0.2) or (a > 0.26 and a < 0.34)
	_bolt.visible = on
	_bolt_light.light_energy = (40.0 if on else 0.0)


## Gusts (Dave: "random lightning strikes and gusts of wind"): every so
## often the wind picks up hard for a few seconds and dies back - more often
## and harder in rain and on windy days. The flight model and everything that
## reads the wind feel it (wind.gd gust_boost); a rush of air you hear.
func _gusts(dt: float, raining: bool) -> void:
	var wind = world.get("wind")
	if wind == null:
		return
	var lvl := float(Game.wind_level)
	_gust_t -= dt
	if _gust_t <= 0.0 and _gust_goal <= 1.0:
		var strength := _rng.randf_range(0.25, 0.6) + 0.18 * lvl + (0.45 if raining else 0.0)
		_gust_goal = 1.0 + strength
		_gust_hold = _rng.randf_range(1.5, 4.5)
		_gust_t = _rng.randf_range(6.0, 22.0) / (1.0 + 0.4 * lvl + (0.8 if raining else 0.0))
		if lvl > 0.0 or raining:
			_whoosh.volume_db = -20.0 + 10.0 * clampf(strength / 1.2, 0.0, 1.0)
			_whoosh.play()
	if _gust_goal > 1.0:
		_gust = move_toward(_gust, _gust_goal, dt * 0.9)
		if absf(_gust - _gust_goal) < 0.01:
			_gust_hold -= dt
			if _gust_hold <= 0.0:
				_gust_goal = 1.0
	else:
		_gust = move_toward(_gust, 1.0, dt * 0.35)
	wind.set("gust_boost", _gust)


## A rush of wind made from noise: swells up, roars, falls away (5 s).
func _gust_shot() -> AudioStreamWAV:
	var n := RATE * 5
	var data := PackedByteArray()
	data.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var lp := 0.0
	var lp2 := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var w := r.randf_range(-1.0, 1.0)
		lp += (w - lp) * (0.02 + 0.05 * sin(t * 1.3) * sin(t * 1.3))
		lp2 += (lp - lp2) * 0.3
		var env := smoothstep(0.0, 1.4, t) * (1.0 - smoothstep(2.6, 5.0, t)) * (0.8 + 0.2 * sin(t * 7.0))
		data.encode_s16(i * 2, int(clampf(lp2 * 5.0 * env, -1.0, 1.0) * 30000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.data = data
	return st
