extends Node3D
## Wildfire (DESIGN_NOTES 80): the square as a grid of 4 m patches, each
## with fuel from what grows there - spruce forest burns hot, grass fast, the
## bog hardly at all, gravel, strips, water and dug ground not at all. Fire
## creeps patch to patch, faster downwind and uphill, drier in summer, not
## at all in winter. Trees it reaches burn down, the ground goes black, and
## the water truck's spray puts it out. Smoke rises where it's burning.

const Flora = preload("res://scripts/flora.gd")
const SAVE := "user://fire.cfg"
const CELL := 4.0
const TICK := 0.25
const BURN_RATE := 0.012           # fuel a second: forest burns about a minute a patch
const SPREAD := 0.045              # base chance a second to catch a neighbour: with a
                                   # breeze behind it the front makes ~0.4 m/s
const MAX_FLAMES := 48
const MAX_SMOKE := 10

var terrain: RefCounted
var world: Node3D
var wind: Node
var hud: Control
var n := 0
var half := 0.0
var fuel := PackedFloat32Array()
var heat := PackedFloat32Array()   # 0 not burning, >0 burning (how fiercely)
var burnt := PackedByteArray()
var wet := PackedFloat32Array()    # seconds left that a doused patch won't catch
## Snow melted off a patch by the heat next to it, 0..1 (DESIGN_NOTES 117).
## In winter a patch can only catch once it's thawed; the ground shader shows
## the melt. It snows back over slowly once the fire's out.
var melt := PackedFloat32Array()
const MELT_RATE := 0.04            # a second, beside a patch burning flat out: ~25 s to thaw
const REFREEZE := 1.0 / 600.0      # a second: ten minutes to snow back over
const WINTER_DRY := 0.35           # thawed brush and resinous spruce, once the snow's off
var _melting: Array[int] = []      # patches with some melt (to refreeze)
var _melt_img: Image
var _melt_tex: ImageTexture
var _melt_dirty := false
var active: Array[int] = []        # burning patches
var _wet_list: Array[int] = []     # doused patches drying out
var _t := 0.0
var _vis_t := 0.0
var _char_t := 0.0
var _char_count := -1
var _flames: Array = []
var _smokes: Array = []
var _glow: OmniLight3D
var _char: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
var spread_mult := 1.0             # story_mission.gd: a wind-driven fire runs faster
var embers := true                 # in a strong wind burning patches throw embers downwind
var _told := 0.0
var _dirty := false
var _save_t := 0.0


func setup() -> void:
	_rng.randomize()
	half = float(terrain.SQ)
	n = int(half * 2.0 / CELL)
	fuel.resize(n * n)
	heat.resize(n * n)
	burnt.resize(n * n)
	wet.resize(n * n)
	melt.resize(n * n)
	_melt_img = Image.create(n, n, false, Image.FORMAT_R8)
	_melt_tex = ImageTexture.create_from_image(_melt_img)
	_hook_melt()
	for j in range(n):
		for i in range(n):
			fuel[j * n + i] = _fuel_at(_centre(i, j))
	for k in range(MAX_FLAMES):
		_flames.append(_flame_emitter())
	for k in range(MAX_SMOKE):
		_smokes.append(_smoke_emitter())
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.55, 0.2)
	_glow.light_energy = 0.0
	_glow.omni_range = 40.0
	_glow.shadow_enabled = false
	add_child(_glow)
	_char = MultiMeshInstance3D.new()
	_char.name = "Burnt"
	_char.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := PlaneMesh.new()
	q.size = Vector2(CELL + 0.3, CELL + 0.3)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.09, 0.08, 0.07)
	cm.roughness = 1.0
	q.material = cm
	mm.mesh = q
	_char.multimesh = mm
	add_child(_char)
	_load()


## Give the ground its melt map (the voxel ground's shader draws it).
func _hook_melt() -> void:
	load("res://scripts/voxel_ground.gd").set_global("bp_melt", _melt_tex)


func _update_melt_tex() -> void:
	if not _melt_dirty or _melt_img == null:
		return
	_melt_dirty = false
	var data := PackedByteArray()
	data.resize(n * n)
	for k in range(n * n):
		data[k] = int(clampf(melt[k], 0.0, 1.0) * 255.0)
	_melt_img.set_data(n, n, false, Image.FORMAT_R8, data)
	_melt_tex.update(_melt_img)


func _centre(i: int, j: int) -> Vector3:
	var x := -half + (float(i) + 0.5) * CELL
	var z := -half + (float(j) + 0.5) * CELL
	return Vector3(x, terrain.height_at(x, z), z)


func _index(p: Vector3) -> int:
	var i := int(floor((p.x + half) / CELL))
	var j := int(floor((p.z + half) / CELL))
	if i < 0 or j < 0 or i >= n or j >= n:
		return -1
	return j * n + i


## What a patch has to burn, 0..1.
func _fuel_at(c: Vector3) -> float:
	if terrain.strip_index_at(c.x, c.z, 3.0) >= 0:
		return 0.0
	var wl: float = terrain.water_level_at(c.x, c.z)
	if wl > -1.0e8 and wl > c.y - 0.2:
		return 0.0
	if absf(c.y - terrain.natural_at(c.x, c.z)) > 0.3:
		return 0.0                     # dug, or a spoil heap: bare dirt
	if not terrain.hollow_at(c.x, c.z).is_empty():
		return 0.0
	var zw: Vector2 = terrain.zone_at(c.x, c.z) if terrain.has_method("zone_at") else Vector2(0.5, 0.0)
	var f := clampf((0.3 + 0.7 * zw.x) * (1.0 - 0.85 * zw.y), 0.0, 1.0)
	if terrain.has_method("zone4"):
		var z4: Color = terrain.zone4(c.x, c.z)
		f *= (1.0 - z4.r) * (1.0 - 0.9 * z4.b)      # gravel apron and pad, creek and shore sand
	if terrain.has_method("mud_base_at"):
		f *= clampf(1.0 - 1.6 * float(terrain.mud_base_at(c.x, c.z)), 0.0, 1.0)     # soft wet ground
	return f if f >= 0.05 else 0.0


## Whether a patch will take fire right now. The ground changes under the
## fire's map: mud comes and goes with the season, rain and driving, and
## dug or spoil ground is bare dirt. Sampled at the middle and four points
## round it; most of the patch has to be dry vegetation.
func _burnable_now(k: int) -> bool:
	var c := _centre(k % n, k / n)
	var good := 0
	for o in [Vector2.ZERO, Vector2(1.2, 1.2), Vector2(-1.2, 1.2), Vector2(1.2, -1.2), Vector2(-1.2, -1.2)]:
		var x := c.x + (o as Vector2).x
		var z := c.z + (o as Vector2).y
		if terrain.has_method("mud_at") and float(terrain.mud_at(x, z)) > 0.3:
			continue
		if terrain.has_method("orig_depth_at") and float(terrain.orig_depth_at(x, z)) > 0.08:
			continue
		if absf(float(terrain.height_at(x, z)) - float(terrain.natural_at(x, z))) > 0.3:
			continue
		if terrain.has_method("wet_at") and float(terrain.wet_at(x, z)) > 0.45:
			continue
		good += 1
	return good >= 3


## How dry it is: summer burns hardest, then the dead grass and brush of
## fall and spring; winter not at all; rain damps it right down.
func _dryness() -> float:
	var d := 0.45
	match int(Game.season):
		Game.SUMMER:
			d = 1.0
		Game.FALL:
			d = 0.8
		Game.SPRING:
			d = 0.65
		Game.WINTER:
			return 0.0
	if int(Game.weather) == 2:
		d *= 0.25
	return d


## Light a fire at p (a crash, a spark). r: metres round it.
func ignite(p: Vector3, r: float = 2.0) -> bool:
	var lit := false
	var steps := int(ceil(r / CELL))
	for dj in range(-steps, steps + 1):
		for di in range(-steps, steps + 1):
			var q := p + Vector3(float(di) * CELL, 0, float(dj) * CELL)
			if q.distance_to(p) > r + CELL * 0.5:
				continue
			var k := _index(q)
			if k >= 0 and _catch(k):
				lit = true
	return lit


func _catch(k: int) -> bool:
	if heat[k] > 0.0 or burnt[k] == 1 or fuel[k] < 0.05 or wet[k] > 0.0:
		return false
	if not _burnable_now(k):
		return false
	heat[k] = 0.15
	if melt[k] < 1.0:
		if melt[k] <= 0.0:
			_melting.append(k)
		melt[k] = 1.0
		_melt_dirty = true
	active.append(k)
	_burn_trees(k)
	_dirty = true
	return true


## Trees standing in the patch go up: they come down burnt.
func _burn_trees(k: int) -> void:
	if world == null or not world.has_method("fell_tree"):
		return
	var c := _centre(k % n, k / n)
	var g := Flora.G
	var i0 := int(floor((c.x - CELL * 0.5 + terrain.half) / g))
	var i1 := int(floor((c.x + CELL * 0.5 + terrain.half) / g))
	var j0 := int(floor((c.z - CELL * 0.5 + terrain.half) / g))
	var j1 := int(floor((c.z + CELL * 0.5 + terrain.half) / g))
	for tj in range(j0, j1 + 1):
		for ti in range(i0, i1 + 1):
			if Flora.felled.has(Flora.key(ti, tj)):
				continue
			var tr := Flora.tree_at(terrain, ti, tj)
			if tr.is_empty():
				continue
			var tp: Vector3 = tr["pos"]
			if absf(tp.x - c.x) <= CELL * 0.5 and absf(tp.z - c.z) <= CELL * 0.5:
				var ang := _rng.randf() * TAU
				world.fell_tree(ti, tj, Vector3(cos(ang) * 2.0, -1.0, sin(ang) * 2.0))     # y -1: it burnt (charred black)


## Water on the fire: puts out what's within r and wets it for a while.
func douse(p: Vector3, r: float = 3.0) -> int:
	var out := 0
	var steps := int(ceil(r / CELL))
	for dj in range(-steps, steps + 1):
		for di in range(-steps, steps + 1):
			var q := p + Vector3(float(di) * CELL, 0, float(dj) * CELL)
			var k := _index(q)
			if k < 0:
				continue
			if wet[k] <= 0.0:
				_wet_list.append(k)
			wet[k] = 40.0
			if heat[k] > 0.0:
				heat[k] = 0.0
				active.erase(k)
				out += 1
				_dirty = true
	return out


func burning_at(p: Vector3) -> bool:
	var k := _index(p)
	return k >= 0 and heat[k] > 0.0


func burning_count() -> int:
	return active.size()


func _process(delta: float) -> void:
	_t += delta
	while _t >= TICK:
		_t -= TICK
		_tick(TICK)
	_vis_t += delta
	if _vis_t > 0.4:
		_vis_t = 0.0
		_visuals()
		_update_melt_tex()
	_char_t += delta
	if _char_t > 2.0:
		_char_t = 0.0
		_update_char()
	_told -= delta
	_save_t += delta
	if _dirty and _save_t > 10.0:
		_save_t = 0.0
		_dirty = false
		save()


func _tick(dt: float) -> void:
	var dry := _dryness()
	var wv := Vector3.ZERO
	if wind != null and wind.has_method("sample") and not active.is_empty():
		wv = wind.sample(_centre(active[0] % n, active[0] / n) + Vector3(0, 2, 0))
	var ws := Vector2(wv.x, wv.z)
	var wspeed := ws.length()
	var wdir := ws / wspeed if wspeed > 0.1 else Vector2.ZERO
	var newly: Array[int] = []
	var done: Array[int] = []
	for k in active:
		var i := k % n
		var j := k / n
		heat[k] = minf(heat[k] + dt * 0.5, 1.0)
		fuel[k] = maxf(fuel[k] - BURN_RATE * dt * (0.5 + heat[k]), 0.0)
		if fuel[k] <= 0.02:
			done.append(k)
			continue
		var winter: bool = int(Game.season) == Game.WINTER
		if dry <= 0.0 and not winter:
			continue
		var hk: float = _centre(i, j).y
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var ni: int = i + di
				var nj: int = j + dj
				if ni < 0 or nj < 0 or ni >= n or nj >= n:
					continue
				var nk := nj * n + ni
				# the heat thaws the snow round it, a little at a time
				if melt[nk] < 1.0:
					if melt[nk] <= 0.0:
						_melting.append(nk)
					melt[nk] = minf(melt[nk] + MELT_RATE * heat[k] * dt * (0.7 if (di != 0 and dj != 0) else 1.0), 1.0)
					_melt_dirty = true
				if heat[nk] > 0.0 or burnt[nk] == 1 or fuel[nk] < 0.05 or wet[nk] > 0.0:
					continue
				var dry_here := dry
				if winter:
					if melt[nk] < 0.99:
						continue          # still under snow
					dry_here = WINTER_DRY * (0.25 if int(Game.weather) == 2 else 1.0)
				var to := Vector2(float(di), float(dj)).normalized()
				var with_wind := wdir.dot(to)
				var wf := 1.0 + clampf(wspeed / 8.0, 0.0, 1.5) * (2.5 * maxf(with_wind, 0.0) - 0.7 * maxf(-with_wind, 0.0))
				var up: float = (_centre(ni, nj).y - hk) / CELL
				var sf := 1.0 + 3.0 * maxf(up, 0.0) - 0.5 * maxf(-up, 0.0)
				var chance := SPREAD * spread_mult * fuel[nk] * heat[k] * dry_here * maxf(wf, 0.1) * maxf(sf, 0.2) * dt
				if (di != 0 and dj != 0):
					chance *= 0.7
				if _rng.randf() < chance:
					newly.append(nk)
	# embers: in a strong wind a fierce patch throws burning bits 8-45 m
	# downwind (a fire jumps roads, the runway, the creek)
	if embers and wspeed > 5.0 and dry > 0.0:
		for k in active:
			if heat[k] > 0.6 and _rng.randf() < 0.02 * spread_mult * dt / TICK * clampf((wspeed - 5.0) / 6.0, 0.0, 1.5):
				var c := _centre(k % n, k / n)
				var far := _rng.randf_range(8.0, 45.0)
				var dv := Vector2(wdir.x, wdir.y).rotated(_rng.randf_range(-0.35, 0.35)) * far
				var nk2 := _index(c + Vector3(dv.x, 0, dv.y))
				if nk2 >= 0 and heat[nk2] <= 0.0 and burnt[nk2] == 0 and fuel[nk2] >= 0.05:
					newly.append(nk2)
	for k2 in done:
		heat[k2] = 0.0
		burnt[k2] = 1
		active.erase(k2)
		_dirty = true
	for k3 in newly:
		_catch(k3)
	# thawed ground snows back over, slowly, once nothing's burning by it
	if not _melting.is_empty():
		var snowing: bool = int(Game.season) == Game.WINTER
		for mk in _melting.duplicate():
			if heat[mk] > 0.0:
				continue
			melt[mk] = maxf(melt[mk] - REFREEZE * dt * (1.0 if snowing else 6.0), 0.0)
			_melt_dirty = true
			if melt[mk] <= 0.0:
				_melting.erase(mk)
	# wet patches dry out again (only the few that have been doused)
	if not _wet_list.is_empty():
		for wk in _wet_list.duplicate():
			wet[wk] = maxf(wet[wk] - dt, 0.0)
			if wet[wk] <= 0.0:
				_wet_list.erase(wk)
	if not newly.is_empty() and _told <= 0.0 and hud != null:
		_told = 30.0
		hud.push_message("Fire! It's spreading%s." % ("" if wspeed < 2.0 else " with the wind"), 5.0)


# ------------------------------------------------------------------------------
#  Looks: flames on the nearest burning patches, smoke over the fire, a glow,
#  and black ground where it's been.
# ------------------------------------------------------------------------------
var _snds: Array = []          # AudioStreamPlayer3D: the fire's sound at the nearest patches


func _visuals() -> void:
	var cam := get_viewport().get_camera_3d()
	var cp: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	var order: Array = []
	for k in active:
		var c := _centre(k % n, k / n)
		order.append([cp.distance_squared_to(c), c, heat[k]])
	order.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	# the sound of it: the nearest few burning patches roar and crackle
	if _snds.is_empty():
		var st: AudioStream = load("res://scripts/audio.gd")._file("res://assets/sounds/fx/fire.wav", true)
		for si in range(3):
			var sp := AudioStreamPlayer3D.new()
			sp.stream = st
			sp.unit_size = 9.0
			sp.max_distance = 400.0
			sp.volume_db = -80.0
			sp.pitch_scale = 0.9 + 0.1 * float(si)
			sp.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
			add_child(sp)
			if st != null:
				sp.play(float(si) * 1.7)
			_snds.append(sp)
	for si2 in range(_snds.size()):
		var sp2: AudioStreamPlayer3D = _snds[si2]
		if si2 < order.size():
			sp2.global_position = order[si2][1]
			sp2.volume_db = linear_to_db(clampf(0.3 + 0.7 * float(order[si2][2]), 0.01, 1.0)) - 3.0
		else:
			sp2.volume_db = -80.0
	for f in range(MAX_FLAMES):
		var e: CPUParticles3D = _flames[f]
		if f < order.size():
			e.global_position = order[f][1]
			e.emitting = true
			e.scale_amount_max = 0.6 + 0.8 * float(order[f][2])
		else:
			e.emitting = false
	# smoke: spread over the fire, every so many burning patches
	var stride := maxi(order.size() / MAX_SMOKE, 1)
	for s in range(MAX_SMOKE):
		var e2: CPUParticles3D = _smokes[s]
		var idx := s * stride
		if idx < order.size():
			e2.global_position = order[idx][1] + Vector3(0, 2.0, 0)
			e2.emitting = true
		else:
			e2.emitting = false
	if order.is_empty():
		_glow.light_energy = 0.0
	else:
		var mid := Vector3.ZERO
		for o in order:
			mid += o[1]
		_glow.global_position = mid / float(order.size()) + Vector3(0, 4, 0)
		_glow.light_energy = clampf(0.6 + float(order.size()) * 0.05, 0.6, 4.0)


func _update_char() -> void:
	var cnt := 0
	for b in burnt:
		cnt += b
	if cnt == _char_count:
		return
	_char_count = cnt
	var mm := _char.multimesh
	mm.instance_count = cnt
	var w := 0
	for k in range(burnt.size()):
		if burnt[k] == 1:
			var c := _centre(k % n, k / n)
			var nrm: Vector3 = terrain.normal_at(c.x, c.z)
			var x := nrm.cross(Vector3.FORWARD).normalized()
			var z := x.cross(nrm).normalized()
			mm.set_instance_transform(w, Transform3D(Basis(x, nrm, z), c + nrm * 0.05))
			w += 1


func _flame_emitter() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = 18
	e.lifetime = 0.9
	e.emitting = false
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	e.emission_box_extents = Vector3(CELL * 0.45, 0.2, CELL * 0.45)
	e.direction = Vector3.UP
	e.spread = 10.0
	e.initial_velocity_min = 1.5
	e.initial_velocity_max = 3.2
	e.gravity = Vector3(0, 1.0, 0)
	e.scale_amount_min = 0.5
	e.scale_amount_max = 1.2
	var c := Curve.new()
	c.add_point(Vector2(0, 1.0))
	c.add_point(Vector2(1, 0.1))
	e.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
	g.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	e.color_ramp = g
	var m := QuadMesh.new()
	m.size = Vector2(0.9, 1.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = load("res://scripts/fx.gd").puff_texture()     # soft-edged, not a square
	m.material = mat
	e.mesh = m
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(e)
	return e


func _smoke_emitter() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.amount = 30
	e.lifetime = 9.0
	e.emitting = false
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 2.0
	e.direction = Vector3.UP
	e.spread = 15.0
	e.initial_velocity_min = 2.0
	e.initial_velocity_max = 3.5
	e.gravity = Vector3(0.8, 0.4, 0.3)
	e.scale_amount_min = 2.0
	e.scale_amount_max = 4.0
	var c := Curve.new()
	c.add_point(Vector2(0, 0.6))
	c.add_point(Vector2(1, 2.5))
	e.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(0.25, 0.24, 0.23, 0.55))
	g.set_color(1, Color(0.55, 0.55, 0.55, 0.0))
	e.color_ramp = g
	var m := QuadMesh.new()
	m.size = Vector2(1.6, 1.6)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = load("res://scripts/fx.gd").puff_texture()     # a soft puff, not a grey square
	m.material = mat
	e.mesh = m
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(e)
	return e


# ------------------------------------------------------------------------------
#  Saving: what's burnt, what's burning, what's left to burn.
# ------------------------------------------------------------------------------
func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("f", "n", n)
	cf.set_value("f", "burnt", burnt)
	cf.set_value("f", "fuel", fuel)
	cf.set_value("f", "active", active)
	cf.save(SAVE)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK or int(cf.get_value("f", "n", 0)) != n:
		return
	burnt = cf.get_value("f", "burnt", burnt)
	fuel = cf.get_value("f", "fuel", fuel)
	for k in cf.get_value("f", "active", []):
		heat[int(k)] = 0.5
		active.append(int(k))
	_update_char()


## After a big fire (story_mission.gd): most of what could burn has, the trees
## down and black, the ground char; `keep` spots (centre, radius) survive.
func burn_out(frac: float, keep: Array = []) -> void:
	for k in range(n * n):
		if fuel[k] < 0.05 or burnt[k] == 1:
			continue
		var c := _centre(k % n, k / n)
		var spared := false
		for kp in keep:
			if Vector2(c.x - (kp[0] as Vector3).x, c.z - (kp[0] as Vector3).z).length() < float(kp[1]):
				spared = true
		if spared or _rng.randf() > frac:
			continue
		heat[k] = 0.0
		burnt[k] = 1
		fuel[k] = 0.0
		_burn_trees(k)
	active.clear()
	_dirty = true
	_update_char()
