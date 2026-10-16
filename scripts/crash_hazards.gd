extends Node3D
## What a wreck does after it stops (DESIGN_NOTES 155).
##
## Wiring: a hard crash cuts and chafes the wiring in a few places (the
## firewall, the wing roots where the light wires run, under the panel).
## While the battery master is on and the battery has charge, those spots
## spit sparks now and then: a crackle, a shower of hot specks, a flash.
## Switch the master off (in the seat, or reach in through the door on foot)
## and they stop.
##
## Fuel: a split tank pours fuel out of the wreck, faster than in the air,
## and it pools on the ground under the wing. A spark near the pool lights
## it: the ground burns, and the plane with it.
##
## The pilot: a crash hurts, by how hard it was (see main._on_crashed), and
## sitting in a burning wreck hurts more.

const Fx = preload("res://scripts/fx.gd")

var plane: Node3D
var fire: Node                       # fire.gd (grass fires)
var wind: Node
var on_notice: Callable              # func(text)

var _spots: Array = []               # local points on the airframe with cut wires
var _spark_t := 1.0
var _sparks: CPUParticles3D
var _flash: OmniLight3D
var _zap: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _pool := 0.0                     # fuel on the ground, kg
var _t := 0.0
var _armed := false                  # the wreck has cut wiring
var _told_master := false


func _ready() -> void:
	_rng.randomize()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_sparks = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.025)
	q.material = mat
	_sparks.mesh = q
	_sparks.amount = 40
	_sparks.lifetime = 0.55
	_sparks.one_shot = true
	_sparks.explosiveness = 0.92
	_sparks.emitting = false
	_sparks.local_coords = false
	_sparks.direction = Vector3(0, 1, 0)
	_sparks.spread = 75.0
	_sparks.initial_velocity_min = 1.5
	_sparks.initial_velocity_max = 4.5
	_sparks.gravity = Vector3(0, -9.8, 0)
	_sparks.damping_min = 0.5
	_sparks.damping_max = 1.5
	_sparks.scale_amount_min = 0.6
	_sparks.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.75, 1.0))
	ramp.add_point(0.35, Color(1.0, 0.65, 0.2, 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.9, 0.25, 0.05, 0.0))
	_sparks.color_ramp = ramp
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparks)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(0.75, 0.82, 1.0)
	_flash.omni_range = 4.0
	_flash.light_energy = 0.0
	add_child(_flash)
	_drip = _liquid_particles(24, 0.7, 0.025, false)
	_drip.direction = Vector3.DOWN
	_drip.spread = 4.0
	_drip.initial_velocity_min = 0.2
	_drip.initial_velocity_max = 0.6
	_spray = _liquid_particles(140, 1.4, 0.06, true)
	_spray.spread = 35.0
	_zap = AudioStreamPlayer3D.new()
	_zap.stream = _crackle()
	_zap.unit_size = 3.0
	_zap.max_distance = 40.0
	_zap.volume_db = -14.0
	add_child(_zap)


## A short electrical crackle: a few sharp snaps over a buzzing arc.
func _crackle() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.35)
	var data := PackedByteArray()
	data.resize(n * 2)
	var arc_end := int(rate * _rng.randf_range(0.12, 0.22))
	for i in range(n):
		var t := float(i) / float(rate)
		var v := 0.0
		if i < arc_end:
			# the arc: a harsh buzz at mains-ish frequency with noise
			v += (randf() * 2.0 - 1.0) * 0.55 * (0.6 + 0.4 * sin(TAU * 120.0 * t))
		# snaps
		if randf() < 0.004:
			v += (1.0 if randf() < 0.5 else -1.0) * 0.95
		v *= exp(-t * 6.0)
		var s := int(clampf(v, -1.0, 1.0) * 30000.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Called when the plane crashes (and on bad damage): cut some wires.
func on_crash(impact: float) -> void:
	if impact < 9.0 and plane.part("fuselage") > 0.6:
		return
	_armed = true
	_told_master = false
	_spots.clear()
	var cand: Array = [Vector3(0.0, -0.1, -1.05), Vector3(-0.2, 0.25, -0.9), Vector3(0.25, -0.35, -1.2)]
	var span: float = plane.wing_span * 0.5
	cand.append(Vector3(-span * 0.25, 0.9 if plane.plane_type == "wolverine" else -0.3, 0.1))
	cand.append(Vector3(span * 0.25, 0.9 if plane.plane_type == "wolverine" else -0.3, 0.1))
	cand.append(Vector3(0.0, -0.2, 1.8))
	cand.shuffle()
	var n := clampi(2 + int(impact / 12.0), 2, cand.size())
	for k in range(n):
		_spots.append(cand[k])


func reset() -> void:
	_armed = false
	_spots.clear()
	for pl in _pools:
		(pl["decal"] as Node).queue_free()
		(pl["sheen"] as Node).queue_free()
		var f: Node = pl.get("fire")
		if f != null:
			f.queue_free()
	_pools.clear()


func sparking() -> bool:
	return _armed and plane.engine.master and plane.engine.battery > 0.02 and not plane.get("_in_water")


func _process(delta: float) -> void:
	if plane == null:
		return
	_t += delta
	_flash.light_energy = maxf(_flash.light_energy - delta * 30.0, 0.0)
	if not plane.is_crashed and _armed:
		_armed = false
		_spots.clear()
	# --- sparks --------------------------------------------------------------
	if plane.is_crashed and sparking() and not _spots.is_empty():
		_spark_t -= delta
		if _spark_t <= 0.0:
			_spark_t = _rng.randf_range(0.5, 3.0)
			var lp: Vector3 = _spots[_rng.randi() % _spots.size()]
			var at: Vector3 = plane.global_transform * lp
			_sparks.global_position = at
			_sparks.amount = _rng.randi_range(14, 40)
			_sparks.restart()
			_sparks.emitting = true
			_flash.global_position = at
			_flash.light_energy = _rng.randf_range(1.5, 4.0)
			_zap.global_position = at
			_zap.pitch_scale = _rng.randf_range(0.85, 1.2)
			_zap.play()
			plane.engine.battery = maxf(float(plane.engine.battery) - 0.002, 0.0)
			if not _told_master and on_notice.is_valid():
				_told_master = true
				on_notice.call("Sparks: cut wiring is shorting. Switch the battery master OFF - from the seat, or reach in through the door.")
			# a spark near spilled fuel lights it
			for pl in _pools:
				if float(pl["burn"]) > 0.0 or float(pl["vol"]) < 1.0:
					continue
				var d := Vector2(at.x - (pl["at"] as Vector3).x, at.z - (pl["at"] as Vector3).z).length()
				if d < _radius(pl) + 2.5 and _rng.randf() < clampf(0.15 + float(pl["vol"]) / 40.0, 0.15, 0.7):
					_ignite(pl)
					break
	# --- fuel coming out of split tanks ----------------------------------------
	# A wreck's tanks pour (and the main pool forms under the worse wing); a
	# parked plane with a split tank drips into a slowly growing puddle.
	var e = plane.engine
	var leak := 0.0
	var drip_side := 0.0
	var crashed: bool = plane.is_crashed
	var stopped: bool = plane.on_ground and float(plane.ground_speed) < 1.0
	for side in ["tank_l", "tank_r"]:
		var h: float = plane.part(side)
		if h < 0.85 and (crashed or stopped):
			var rate := (0.85 - h) * (0.6 if crashed else 0.03) * delta
			if side == "tank_l":
				var take: float = minf(rate, e.tank_left)
				if crashed:
					e.tank_left -= take
				leak += take
				if take > 0.0:
					drip_side = -1.0
			else:
				var take2: float = minf(rate, e.tank_right)
				if crashed:
					e.tank_right -= take2
				leak += take2
				if take2 > 0.0 and drip_side == 0.0:
					drip_side = 1.0
	if leak > 0.0:
		var wing: Vector3 = plane.global_transform * Vector3(drip_side * 1.4, 0.8, 0.3)
		var gy: float = plane.terrain.ground_level_at(wing.x, wing.z)
		var ground_pt := Vector3(wing.x, gy, wing.z)
		var main_pool: Dictionary = {}
		for pl in _pools:
			if (pl["at"] as Vector3).distance_to(ground_pt) < maxf(_radius(pl), 1.0):
				main_pool = pl
				break
		if main_pool.is_empty():
			main_pool = _new_pool(ground_pt, 0.0)
		main_pool["vol"] = float(main_pool["vol"]) + leak
		_drip.global_position = wing
		_drip.emitting = true
	else:
		_drip.emitting = false
	# --- pools: spread, soak in and evaporate, burn ------------------------------
	for k in range(_pools.size() - 1, -1, -1):
		var pl: Dictionary = _pools[k]
		var vol: float = pl["vol"]
		if float(pl["burn"]) > 0.0:
			var burn := (0.25 + 0.04 * vol) * delta
			vol = maxf(vol - burn, 0.0)
			pl["burn"] = clampf(vol / 12.0 + 0.25, 0.0, 1.0) if vol > 0.0 else maxf(float(pl["burn"]) - delta * 0.05, 0.0)
			var fnode: Node3D = pl.get("fire")
			if fnode != null:
				var w: Vector3 = wind.sample(pl["at"]) if wind != null else Vector3.ZERO
				Fx.set_fire_strength(fnode, float(pl["burn"]), w, _t)
				fnode.scale = Vector3.ONE * clampf(0.6 + _radius(pl) * 0.5, 0.6, 2.5)
			if crashed and not bool(plane.on_fire) and (pl["at"] as Vector3).distance_to(plane.global_position) < 8.0:
				plane._start_fire(0.55)
			if fire != null and _rng.randf() < delta * 0.5:
				fire.ignite(pl["at"], _radius(pl) + 1.0)
			# a burning pool lights the fuel next to it
			for other in _pools:
				if other != pl and float(other["burn"]) <= 0.0 and float(other["vol"]) > 0.5 \
						and (other["at"] as Vector3).distance_to(pl["at"]) < _radius(pl) + _radius(other) + 0.8 and _rng.randf() < delta * 0.8:
					_ignite(other)
			if float(pl["burn"]) <= 0.0 and fnode != null:
				fnode.queue_free()
				pl.erase("fire")
		else:
			vol = maxf(vol - (0.004 * vol + 0.002) * delta, 0.0)     # soaks in, evaporates
		pl["vol"] = vol
		_draw_pool(pl, delta)
		if vol <= 0.0 and float(pl["burn"]) <= 0.0:
			(pl["decal"] as Node).queue_free()
			(pl["sheen"] as Node).queue_free()
			_pools.remove_at(k)
	# compatibility for anything reading the old single-pool numbers
	_pool = 0.0
	for pl2 in _pools:
		_pool += float(pl2["vol"])


# ------------------------------------------------------------------------------
#  Spilled fuel on the ground (DESIGN_NOTES 156): projected onto the terrain
#  (Decals, so it lies over bumps and ruts), dark and glossy like soaked
#  ground with a faint blue tint (100LL is dyed blue) and the oily rainbow
#  sheen of a fuel film; the edge is irregular and creeps outward as more
#  runs in.
# ------------------------------------------------------------------------------
var _pools: Array = []          # {at, vol, burn, decal, sheen, grow, rot, fire}
var _drip: CPUParticles3D
static var _tex_wet: Texture2D
static var _tex_orm: Texture2D
static var _tex_sheen: Texture2D


func _radius(pl: Dictionary) -> float:
	return clampf(sqrt(float(pl["vol"])) * 0.55, 0.25, 5.0)


func _new_pool(at: Vector3, vol: float) -> Dictionary:
	_make_textures()
	var d := Decal.new()
	d.texture_albedo = _tex_wet
	d.texture_orm = _tex_orm
	d.modulate = Color(0.55, 0.6, 0.72, 1.0)
	d.albedo_mix = 1.0
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.cull_mask = 1
	var sh := Decal.new()
	sh.texture_albedo = _tex_sheen
	sh.modulate = Color(1, 1, 1, 0.28)
	sh.albedo_mix = 0.35
	sh.upper_fade = 0.2
	sh.lower_fade = 0.2
	var root := get_tree().current_scene
	root.add_child(d)
	root.add_child(sh)
	var rot := _rng.randf() * TAU
	var pl := {"at": at, "vol": vol, "burn": 0.0, "decal": d, "sheen": sh, "grow": 0.0, "rot": rot}
	_pools.append(pl)
	_draw_pool(pl, 0.0)
	return pl


func _draw_pool(pl: Dictionary, delta: float) -> void:
	# the edge creeps out toward its size rather than jumping
	var want := _radius(pl)
	pl["grow"] = move_toward(float(pl["grow"]), want, maxf(delta * 0.35, 0.0)) if delta > 0.0 else want
	var r: float = pl["grow"]
	var at: Vector3 = pl["at"]
	var burnt: bool = float(pl["burn"]) > 0.0
	for key in ["decal", "sheen"]:
		var d: Decal = pl[key]
		d.global_transform = Transform3D(Basis(Vector3.UP, float(pl["rot"])), at + Vector3(0, 0.15, 0))
		d.size = Vector3(r * 2.0, 0.9, r * 2.0 * 0.82)
	(pl["sheen"] as Decal).visible = not burnt and float(pl["vol"]) > 0.3
	# burnt ground is black and dull
	(pl["decal"] as Decal).modulate = Color(0.25, 0.22, 0.2, 1.0) if burnt else Color(0.55, 0.6, 0.72, 1.0)


## Wet ground, a glossy ORM, and the rainbow film - made once, in code.
func _make_textures() -> void:
	if _tex_wet != null:
		return
	var n := 128
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var wet := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var orm := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var sheen := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			# a lobed, ragged outline: fuel runs along the low spots
			var edge := 0.78 + 0.18 * noise.get_noise_2d(float(x), float(y)) + 0.08 * sin(atan2(v, u) * 3.0 + 1.0)
			var a := clampf((edge - r) / 0.10, 0.0, 1.0)
			var core := clampf((edge - r) / 0.35, 0.0, 1.0)
			# soaked ground: dark, a little blue
			wet.set_pixel(x, y, Color(0.10, 0.11, 0.14, a * (0.55 + 0.4 * core)))
			# occlusion 1, roughness low in the middle (standing fuel), metallic 0
			orm.set_pixel(x, y, Color(1.0, lerpf(0.55, 0.06, core), 0.0, 1.0))
			# the film: hue bands following the thickness, strongest near the edge
			var band := fposmod(r * 3.2 + 0.4 * noise.get_noise_2d(float(x) * 1.7 + 40.0, float(y) * 1.7), 1.0)
			var c := Color.from_hsv(band, 0.55, 1.0)
			sheen.set_pixel(x, y, Color(c.r, c.g, c.b, a * (0.25 + 0.6 * (1.0 - core)) * 0.8))
	_tex_wet = ImageTexture.create_from_image(wet)
	_tex_orm = ImageTexture.create_from_image(orm)
	_tex_sheen = ImageTexture.create_from_image(sheen)


func _ignite(pl: Dictionary) -> void:
	pl["burn"] = 0.6
	var f := Fx.make_fire()
	get_tree().current_scene.add_child(f)
	f.global_position = pl["at"]
	pl["fire"] = f
	if on_notice.is_valid() and _rng.randf() < 0.5:
		on_notice.call("The spilled fuel's caught! Get clear!")


## The crash throws fuel out of the split tanks: a spray of droplets ahead
## along the slide, and splashes soaking the ground where it lands.
func spray_fuel(vel: Vector3) -> void:
	var e = plane.engine
	var have: float = float(e.tank_left) + float(e.tank_right)
	if have < 2.0 or (plane.part("tank_l") > 0.85 and plane.part("tank_r") > 0.85):
		return
	var dir := Vector3(vel.x, 0.0, vel.z)
	var spd := dir.length()
	dir = dir.normalized() if spd > 0.5 else Vector3(0, 0, -1)
	var side := Vector3(-dir.z, 0.0, dir.x)
	var spilled := minf(have * 0.25, 30.0)
	e.tank_left = maxf(float(e.tank_left) - spilled * 0.5, 0.0)
	e.tank_right = maxf(float(e.tank_right) - spilled * 0.5, 0.0)
	var n := 3 + int(spilled / 6.0)
	for k in range(n):
		var dist := _rng.randf_range(1.0, 4.0 + spd * 0.25)
		var p: Vector3 = plane.global_position + dir * dist + side * _rng.randf_range(-3.0, 3.0)
		p.y = plane.terrain.ground_level_at(p.x, p.z)
		_new_pool(p, spilled / float(n) * _rng.randf_range(0.6, 1.3))
	# the spray itself
	_spray.global_position = plane.global_position + Vector3(0, 0.8, 0)
	_spray.direction = (dir + Vector3(0, 0.6, 0)).normalized()
	_spray.initial_velocity_min = 3.0 + spd * 0.15
	_spray.initial_velocity_max = 7.0 + spd * 0.3
	_spray.restart()
	_spray.emitting = true


var _spray: CPUParticles3D


func _liquid_particles(count: int, life: float, size: float, one_shot: bool) -> CPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.05
	mat.metallic_specular = 1.0
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size * 1.8)
	q.material = mat
	p.mesh = q
	p.amount = count
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.85 if one_shot else 0.0
	p.local_coords = false
	p.emitting = false
	p.gravity = Vector3(0, -9.8, 0)
	p.color = Color(0.70, 0.78, 0.95, 0.55)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


## Main asks: switch the master off from outside (reaching in through the door).
func reach_in_master_off() -> String:
	if not plane.engine.master:
		return "The master's already off."
	plane.engine.master = false
	return "You reach in and snap the battery master OFF. The sparking stops."
