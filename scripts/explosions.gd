extends Node3D
## Things blowing up (DESIGN_NOTES 142): a burning plane or truck that isn't
## put out in time, its tanks going up. One shared blast:
##  - the fireball, smoke and dust ring (fx.gd), a flash, the boom;
##  - parts flung out (debris.gd: they fly, tumble and come to rest);
##  - burning fuel and burning bits thrown round it: each one lands, burns a
##    while wherever it falls, and lights the grass and brush it lands in
##    (fire.gd) - a burning bit landing on a machine or a plane sets it alight;
##  - the blast: hurts what's close, and shakes the ground and the view -
##    the nearer you are, the harder.
## Big tanks make big bangs: strength from the fuel aboard.

const Fx = preload("res://scripts/fx.gd")

var terrain: RefCounted
var fire: Node                    # fire.gd
var debris: Node                  # debris.gd
var on_shake: Callable            # func(amount) - camera / ground shake
var listener: Callable            # func() -> Vector3: where the player is
var hurt_near: Callable           # func(at, radius, strength) - blast damage to people and machines
var ignite_obj: Callable          # func(at, r) - a burning bit landing on a machine or plane: set it alight
var boom: Callable                # func(strength) - the sound

var _brands: Array = []           # flying burning bits: {node, vel, life}
var _ground_fires: Array = []     # burning where they fell: {node, life}
static var _chunk_meshes: Array = []


## The blast at `at`, strength 0.5 (a pickup's tank) .. 3 (a full fuel truck).
func blow(at: Vector3, strength: float, body_col: Color = Color(0.25, 0.25, 0.25), full: bool = true) -> void:
	strength = clampf(strength, 0.4, 3.0)
	if not full:
		# the fireball and parts are drawn by whoever called (a plane crash):
		# just the burning fuel thrown about and the shake
		for j0 in range(int(6 + 8 * strength)):
			var d0 := Vector3(randf_range(-1, 1), randf_range(0.5, 1.3), randf_range(-1, 1)).normalized()
			_brand(at + Vector3(0, 1.2, 0), d0 * randf_range(5.0, 14.0) * sqrt(strength))
		if on_shake.is_valid() and listener.is_valid():
			var dd: float = (listener.call() as Vector3).distance_to(at)
			on_shake.call(pow(clampf(1.0 - dd / (40.0 + 45.0 * strength), 0.0, 1.0), 2.0) * strength)
		return
	var ex := Fx.make_explosion(strength)
	add_child(ex)
	ex.global_position = at
	_free_later(ex, 12.0)
	# a flash that lights the ground round it for a moment
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.7, 0.35)
	fl.light_energy = 14.0 * strength
	fl.omni_range = 30.0 * strength
	add_child(fl)
	fl.global_position = at + Vector3(0, 2.0, 0)
	var tw := create_tween()
	tw.tween_property(fl, "light_energy", 0.0, 0.9)
	tw.tween_callback(fl.queue_free)
	_boom_at(at, strength)
	# parts flung out
	if debris != null:
		for i in range(int(6 + 6 * strength)):
			var dir := Vector3(randf_range(-1, 1), randf_range(0.4, 1.4), randf_range(-1, 1)).normalized()
			var sp := randf_range(6.0, 16.0) * sqrt(strength)
			var m: Mesh = _chunk(i, body_col)
			debris.spawn(m, Transform3D(Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, 0)), at + Vector3(0, 1.0, 0)),
				dir * sp, Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8)), randf_range(0.3, 0.9))
	# burning fuel and burning bits, thrown out to land and burn
	for j in range(int(8 + 10 * strength)):
		var d2 := Vector3(randf_range(-1, 1), randf_range(0.5, 1.3), randf_range(-1, 1)).normalized()
		_brand(at + Vector3(0, 1.2, 0), d2 * randf_range(5.0, 14.0) * sqrt(strength))
	# the ground right under it
	if fire != null:
		fire.ignite(at, 3.0 + 2.0 * strength)
	# the blast itself
	if hurt_near.is_valid():
		hurt_near.call(at, 7.0 * strength, strength)
	if on_shake.is_valid() and listener.is_valid():
		var d: float = (listener.call() as Vector3).distance_to(at)
		var reach := 40.0 + 45.0 * strength
		var k := pow(clampf(1.0 - d / reach, 0.0, 1.0), 2.0) * strength
		if k > 0.01:
			on_shake.call(k)


## A rock blast (dynamite, DESIGN_NOTES 176): a sharp flash, the bang, a
## column of dust and grit, rock and dirt flung out - no burning fuel.
func rock_blast(at: Vector3, strength: float) -> void:
	var ex := Fx.make_explosion(strength * 0.55)
	add_child(ex)
	ex.global_position = at
	_free_later(ex, 10.0)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.92, 0.75)
	fl.light_energy = 10.0 * strength
	fl.omni_range = 22.0 * strength
	add_child(fl)
	fl.global_position = at + Vector3(0, 1.0, 0)
	var tw := create_tween()
	tw.tween_property(fl, "light_energy", 0.0, 0.35)
	tw.tween_callback(fl.queue_free)
	_boom_at(at, strength * 1.2)
	if debris != null:
		var cols := [Color(0.42, 0.38, 0.33), Color(0.36, 0.30, 0.24), Color(0.50, 0.47, 0.43)]
		for i in range(14):
			var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.8), randf_range(-1, 1)).normalized()
			var sp := randf_range(5.0, 15.0) * sqrt(strength)
			debris.spawn(_chunk(i, cols[i % 3]), Transform3D(Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, 0)), at + Vector3(0, 0.4, 0)),
				dir * sp, Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10)), randf_range(0.15, 0.45))
	if hurt_near.is_valid():
		hurt_near.call(at, 9.0 * strength, strength * 1.3)
	if on_shake.is_valid() and listener.is_valid():
		var d: float = (listener.call() as Vector3).distance_to(at)
		var k := pow(clampf(1.0 - d / (35.0 + 40.0 * strength), 0.0, 1.0), 2.0) * strength
		if k > 0.01:
			on_shake.call(k)


## The bang, heard from where it went off (bp2_audio/gen_fx.py explosion.wav):
## the crack, the deep boom, the rumble rolling away.
static var _boom_st: AudioStream
func _boom_at(at: Vector3, strength: float) -> void:
	if _boom_st == null:
		_boom_st = load("res://scripts/audio.gd")._file("res://assets/sounds/fx/explosion.wav", false)
	if _boom_st == null:
		if boom.is_valid():
			boom.call(strength)
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _boom_st
	p.unit_size = 25.0 * strength
	p.max_distance = 3000.0
	p.max_db = 6.0
	p.volume_db = linear_to_db(clampf(0.6 + 0.2 * strength, 0.1, 1.0))
	p.pitch_scale = clampf(1.15 - 0.12 * strength, 0.75, 1.15)     # bigger, deeper
	p.attenuation_filter_cutoff_hz = 9000.0
	p.attenuation_filter_db = -12.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(p)
	p.global_position = at
	p.play()
	_free_later(p, 8.0)


func _free_later(n: Node, s: float) -> void:
	get_tree().create_timer(s).timeout.connect(func(): if is_instance_valid(n): n.queue_free())


func _chunk(i: int, col: Color) -> Mesh:
	if _chunk_meshes.size() < 6:
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.3, 1.0), randf_range(0.05, 0.25), randf_range(0.3, 0.9))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col.darkened(randf_range(0.0, 0.5)) if i % 3 != 0 else Color(0.08, 0.07, 0.06)
		mat.roughness = 0.9
		bm.material = mat
		_chunk_meshes.append(bm)
	return _chunk_meshes[i % _chunk_meshes.size()]


func _brand(from: Vector3, vel: Vector3) -> void:
	var n := Fx.particles(Fx.flame_material(), 10, 0.5, 0.5,
		Fx.gradient([[0.0, Color(1.0, 0.9, 0.5, 0.9)], [0.5, Color(1.0, 0.45, 0.1, 0.7)], [1.0, Color(0.3, 0.1, 0.05, 0.0)]]), 1.2)
	n.direction = Vector3.UP
	n.spread = 30.0
	n.initial_velocity_min = 0.5
	n.initial_velocity_max = 1.5
	add_child(n)
	n.global_position = from
	_brands.append({"node": n, "vel": vel, "life": 6.0})


func _physics_process(delta: float) -> void:
	for i in range(_brands.size() - 1, -1, -1):
		var b: Dictionary = _brands[i]
		var n: Node3D = b["node"]
		var v: Vector3 = b["vel"]
		v.y -= 9.81 * delta
		b["vel"] = v
		var p := n.global_position + v * delta
		var g: float = terrain.ground_level_at(p.x, p.z) if terrain != null else 0.0
		b["life"] = float(b["life"]) - delta
		if p.y <= g + 0.1 or float(b["life"]) <= 0.0:
			p.y = g + 0.1
			_land(p, n)
			_brands.remove_at(i)
			continue
		n.global_position = p
	for k in range(_ground_fires.size() - 1, -1, -1):
		var gf: Dictionary = _ground_fires[k]
		gf["life"] = float(gf["life"]) - delta
		var gn: CPUParticles3D = gf["node"]
		if float(gf["life"]) < 2.0 and gn.emitting:
			gn.emitting = false             # it dies down; the last flames burn out
		if float(gf["life"]) <= 0.0:
			gn.queue_free()
			_ground_fires.remove_at(k)


## A burning bit comes down: it burns where it lies for a while (on gravel or
## rock as well - it's fuel), lights the grass if there's grass, and sets a
## machine or plane it lands on alight.
func _land(p: Vector3, n: CPUParticles3D) -> void:
	n.global_position = p
	n.amount = 16
	n.scale_amount_min = 1.6
	n.scale_amount_max = 2.4
	_ground_fires.append({"node": n, "life": randf_range(14.0, 35.0)})
	while _ground_fires.size() > 60:
		(_ground_fires.pop_front()["node"] as Node).queue_free()
	if fire != null:
		fire.ignite(p, 1.5)
	if ignite_obj.is_valid():
		ignite_obj.call(p, 2.0)


func burning_spots() -> int:
	return _ground_fires.size() + _brands.size()
