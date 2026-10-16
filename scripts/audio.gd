extends Node
## Sound made from scratch at start-up, so the project needs no audio files:
## engine drone that follows the RPM, wind noise, tyre rumble, the stall horn
## and a thump on touchdown.

const RATE := 22050

var plane: Node3D
var _engine
var _catch                  # the start one-shot
var _was_running := false
var _since_catch := 99.0
var _wind
var _rumble
var _horn
var _gear_horn      # gear not down with the throttles back (DC-3)
var _thump
var _starter
var _skid
var _click
var _boom
var _fire
var _crunch
var _was_down := true
var _quiet := 4.0             # seconds after the world appears: the plane settling onto its spot is not a landing
var _crunch2
var _crunch3
var _gravel
var _splash
var _spray
var _turbo
var _was_wet := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 4242
	# Sounds the plane makes come from the plane (heard less as you walk or
	# drive away); the wind past your ears and the warning horns are only for
	# the pilot sitting in it.
	_engine = _player(_engine_loop(), true, 14.0, Vector3(0, 0, -1.6))
	_wind = _player(_noise_loop(0.22, 0.02, 2.0), true, 0.0)
	_rumble = _player(_noise_loop(0.035, 0.0, 2.0), true, 5.0)
	_horn = _player(_horn_loop(), false, 0.0)
	_gear_horn = _player(_horn_loop(), false, 0.0)
	_gear_horn.pitch_scale = 0.62
	_thump = _player(_thump_shot(), false, 8.0)
	# the starter: made offline (bp2_audio/gen_fx.py starter_loop) - a geared
	# motor growling and bogging on each compression, the stacks chuffing;
	# the in-game synth whine is only the fallback (DESIGN_NOTES 155)
	var st_file: AudioStream = _file("res://assets/sounds/plane/starter.wav", true)
	_starter = _player(st_file if st_file != null else _starter_loop(), true, 4.0, Vector3(0, 0, -1.4))
	_skid = _player(_noise_loop(0.55, 0.25, 1.5), true, 4.0)
	_click = _player(_click_shot(), false, 0.0)
	_boom = _player(_boom_shot(), false, 60.0)
	var fire_st: AudioStream = _file("res://assets/sounds/fx/fire.wav", true)
	_fire = _player(fire_st if fire_st != null else _fire_loop(), true, 6.0)
	# the engine catching (bp2_audio/gen_fx.py): coughs, catch, flare, settle;
	# the running loop fades in under its tail
	_catch = _player(_file("res://assets/sounds/plane/start.wav", false), false, 14.0, Vector3(0, 0, -1.6))
	_crunch = _player(_crunch_shot(0), false, 10.0)
	_crunch2 = _player(_crunch_shot(1), false, 10.0)
	_crunch3 = _player(_crunch_shot(2), false, 10.0)
	_gravel = _player(_gravel_shot(), false, 5.0)
	_splash = _player(_splash_shot(), false, 8.0)
	_spray = _player(_noise_loop(0.5, 0.12, 1.5), true, 5.0)
	_spray.volume_db = -80.0
	# a fitted turbo whistles as it spools (DESIGN_NOTES 121)
	var tw: AudioStream = load("res://scripts/engine_sound.gd")._dsl("turbo.wav", true)
	if tw != null:
		_turbo = _player(tw, true, 10.0, Vector3(0, 0, -1.2))
	if plane != null:
		plane.exploded.connect(func(_s): explode())
		plane.dented.connect(func(_p, _d, sev): crunch(sev))
	_apply_volume()
	Game.settings_changed.connect(_apply_volume)


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(Game.volume, 0.0001)))
	AudioServer.set_bus_mute(0, Game.volume <= 0.001)


## `unit` > 0: placed on the plane at `at`, heard at full strength within
## `unit` metres and less further off. 0: in your ears (cockpit only).
func _player(stream: AudioStream, autoplay: bool, unit: float = 0.0, at: Vector3 = Vector3.ZERO) -> Node:
	var p: Node
	if unit > 0.0 and plane != null:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = unit
		p3.max_distance = 2500.0 if unit >= 10.0 else 600.0
		p3.max_db = 3.0
		p3.attenuation_filter_cutoff_hz = 7000.0
		p3.attenuation_filter_db = -18.0
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p3.position = at
		p = p3
		plane.add_child(p3)
	else:
		p = AudioStreamPlayer.new()
		add_child(p)
	p.stream = stream
	p.volume_db = -80.0
	if autoplay:
		p.play()
		_gated.append(p)      # looping: stopped while turned right down (engine_sound.gate_loops)
	return p
var _gated: Array = []
const EngineSoundScript = preload("res://scripts/engine_sound.gd")


var in_plane := true            # main.gd: is the player sitting in this plane?


static func _to_wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


## One second of a flat-six at 2,400 RPM: every partial is a whole number of
## cycles long, so the loop joins without a click.
func _engine_loop() -> AudioStreamWAV:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var base := 20.0   # half engine order, gives the uneven "lope"
	var partials := [[1, 0.10], [2, 0.20], [3, 0.10], [4, 0.42], [6, 0.55], [8, 0.16], [10, 0.10], [12, 0.30], [18, 0.14], [24, 0.08], [30, 0.05]]
	var phases: Array[float] = []
	for p in partials:
		phases.append(_rng.randf() * TAU)
	var lp := 0.0
	for i in range(n):
		var t := float(i) / float(RATE)
		var v := 0.0
		for k in range(partials.size()):
			v += partials[k][1] * sin(TAU * base * float(partials[k][0]) * t + phases[k])
		# Exhaust crackle, pulsing at the firing rate.
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.25)
		v += lp * 0.22 * (0.5 + 0.5 * sin(TAU * 120.0 * t))
		out[i] = tanh(v * 1.1) * 0.55
	return _to_wav(out, true)


## Filtered noise loop. `lowpass` near 0 is a deep rumble, near 1 is a hiss.
func _noise_loop(lowpass: float, highpass: float, seconds: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var hp := 0.0
	for i in range(n):
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), lowpass)
		hp = lerpf(hp, lp, highpass)
		out[i] = (lp - hp) if highpass > 0.0 else lp
	# Cross-fade the tail into the head so the loop point is silent.
	var fade := 2000
	for i in range(fade):
		var k := float(i) / float(fade)
		out[i] = out[i] * k + out[n - fade + i] * (1.0 - k)
	out.resize(n - fade)
	var peak := 0.001
	for v in out:
		peak = maxf(peak, absf(v))
	for i in range(out.size()):
		out[i] = out[i] / peak * 0.7
	return _to_wav(out, true)


func _horn_loop() -> AudioStreamWAV:
	var n := RATE / 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / float(RATE)
		var reed := signf(sin(TAU * 1640.0 * t)) * 0.5 + sin(TAU * 1640.0 * t) * 0.5
		out[i] = reed * 0.22 * (0.8 + 0.2 * sin(TAU * 24.0 * t))
	return _to_wav(out, true)


## Electric starter grinding the engine over: a geared whine with a lumpy beat.
## Ear muffs on (the item, J; the lab's M): everything quieter and dull, the
## highs cut, as through real hearing protection. On the Master bus.
static func set_muffled(on: bool) -> void:
	var bus := AudioServer.get_bus_index("Master")
	for ei in range(AudioServer.get_bus_effect_count(bus) - 1, -1, -1):
		if AudioServer.get_bus_effect(bus, ei).has_meta("ear_muffs"):
			AudioServer.remove_bus_effect(bus, ei)
	if on:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 900.0
		lp.resonance = 0.3
		lp.set_meta("ear_muffs", true)
		AudioServer.add_bus_effect(bus, lp)
		var amp := AudioEffectAmplify.new()
		amp.volume_db = -14.0
		amp.set_meta("ear_muffs", true)
		AudioServer.add_bus_effect(bus, amp)


## A sound made offline (assets/sounds), or null if it isn't there.
static func _file(path: String, loop: bool) -> AudioStream:
	var st: AudioStreamWAV = null
	if ResourceLoader.exists(path):
		st = load(path) as AudioStreamWAV
	if st == null:
		st = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	if st == null:
		return null
	st = st.duplicate() as AudioStreamWAV
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * float(st.mix_rate))
	else:
		st.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return st


func _starter_loop() -> AudioStreamWAV:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / float(RATE)
		var whine := sin(TAU * 180.0 * t) * 0.35 + sin(TAU * 360.0 * t) * 0.2 + signf(sin(TAU * 90.0 * t)) * 0.12
		var lump := 0.6 + 0.4 * sin(TAU * 4.0 * t)     # compression strokes
		out[i] = whine * lump * 0.55
	return _to_wav(out, true)


## A switch or knob clicking into place.
func _click_shot() -> AudioStreamWAV:
	var n := int(RATE * 0.05)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / float(RATE)
		out[i] = (sin(TAU * 2400.0 * t) * 0.5 + _rng.randf_range(-1.0, 1.0) * 0.5) * exp(-t * 160.0) * 0.8
	return _to_wav(out, false)


## A deep explosion: a sharp crack, then a long rolling rumble.
func _boom_shot() -> AudioStreamWAV:
	var n := int(RATE * 3.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in range(n):
		var t := float(i) / float(RATE)
		var w := _rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, w, 0.08)
		lp2 = lerpf(lp2, w, 0.5)
		out[i] = lp * 2.6 * exp(-t * 1.4) + lp2 * 0.9 * exp(-t * 18.0) + sin(TAU * 38.0 * t) * 0.6 * exp(-t * 2.5)
		out[i] = tanh(out[i])
	return _to_wav(out, false)


## Crackling flames: a soft roar with random pops.
func _fire_loop() -> AudioStreamWAV:
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var pop := 0.0
	for i in range(n):
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.05)
		if _rng.randf() < 0.0009:
			pop = _rng.randf_range(0.4, 1.0)
		pop *= 0.985
		out[i] = lp * 0.9 + _rng.randf_range(-1.0, 1.0) * pop * 0.6
	var fade := 1500
	for i in range(fade):
		var k := float(i) / float(fade)
		out[i] = out[i] * k + out[n - fade + i] * (1.0 - k)
	out.resize(n - fade)
	return _to_wav(out, true)


## Metal crunching on a hit.
## A crash hit: a deep thud, bent metal (a few clashing tones that wobble and
## die), and loose bits rattling on after it. `v` varies the mix.
func _crunch_shot(v: int = 0) -> AudioStreamWAV:
	var n := int(RATE * 1.1)
	var out := PackedFloat32Array()
	out.resize(n)
	_rng.seed = 900 + v * 17
	var partials: Array = []
	for k in range(5):
		partials.append([_rng.randf_range(180.0, 1500.0), _rng.randf_range(4.0, 12.0), _rng.randf_range(0.0, TAU)])
	var lp := 0.0
	var lp2 := 0.0
	var rattle := 0.0
	for i in range(n):
		var t := float(i) / float(RATE)
		# Impact: a heavy, low thump.
		var thud := sin(TAU * (62.0 - 20.0 * t) * t) * exp(-t * 9.0) * 0.9
		# Crumpling sheet metal.
		var metal := 0.0
		for pp in partials:
			var f: float = pp[0]
			var wob := 1.0 + 0.04 * sin(TAU * 23.0 * t + float(pp[2]))
			metal += sin(TAU * f * wob * t + float(pp[2])) * exp(-t * float(pp[1]))
		metal *= 0.13 * (0.6 + 0.4 * _rng.randf())
		# Grit and debris: noise that comes in little bursts.
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.45)
		lp2 = lerpf(lp2, lp, 0.2)
		if _rng.randf() < 0.0009:
			rattle = _rng.randf_range(0.3, 0.8)
		rattle *= 0.9993
		var grit := (lp - lp2) * (exp(-t * 5.0) * 1.2 + rattle * 0.6)
		out[i] = clampf(thud + metal + grit, -1.0, 1.0) * 0.9
	return _to_wav(out, false)


## Tyres arriving on gravel: a short crunch of stones.
func _gravel_shot() -> AudioStreamWAV:
	var n := int(RATE * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in range(n):
		var t := float(i) / float(RATE)
		var x := _rng.randf_range(-1.0, 1.0) * (1.0 if _rng.randf() < 0.25 else 0.3)
		lp = lerpf(lp, x, 0.6)
		out[i] = (x - lp) * exp(-t * 12.0) * 0.9 + sin(TAU * 70.0 * t) * exp(-t * 18.0) * 0.4
	return _to_wav(out, false)


## Hitting the water: a slap and a long hissing fall of spray.
func _splash_shot() -> AudioStreamWAV:
	var n := int(RATE * 1.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in range(n):
		var t := float(i) / float(RATE)
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.3)
		lp2 = lerpf(lp2, lp, 0.08)
		var slap := sin(TAU * 110.0 * t) * exp(-t * 25.0) * 0.6
		out[i] = slap + (lp - lp2) * (0.4 * exp(-t * 2.5) + 0.6 * exp(-t * 14.0))
	return _to_wav(out, false)


func explode() -> void:
	_boom.volume_db = _db(1.0)
	_boom.play()


func crunch(sev: float) -> void:
	if sev < 0.25:
		return
	var p = [_crunch, _crunch2, _crunch3][_rng.randi() % 3]
	p.volume_db = _db(clampf(0.3 + sev * 0.4, 0.0, 1.0))
	p.pitch_scale = _rng.randf_range(0.85, 1.1) * (0.9 if sev > 1.0 else 1.0)
	p.play()


func click() -> void:
	_click.volume_db = _db(0.5)
	_click.pitch_scale = _rng.randf_range(0.9, 1.1)
	_click.play()


func _thump_shot() -> AudioStreamWAV:
	var n := int(RATE * 0.4)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in range(n):
		var t := float(i) / float(RATE)
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.12)
		out[i] = sin(TAU * 58.0 * t) * exp(-11.0 * t) * 0.8 + lp * exp(-22.0 * t) * 0.6
	return _to_wav(out, false)


var _miss_t := 0.0                  # a misfire's hole in the engine sound, seconds left


func _db(linear: float) -> float:
	return linear_to_db(clampf(linear, 0.00001, 1.0))


func _process(_delta: float) -> void:
	_quiet = maxf(_quiet - _delta, 0.0)
	EngineSoundScript.gate_loops(_gated)
	if plane == null:
		return
	# Engine
	var e = plane.engine
	var rpm: float = plane.rpm
	var running_now: bool = plane.engine_running
	if running_now and not _was_running and _catch != null and _catch.stream != null:
		_since_catch = 0.0
		_catch.pitch_scale = 1.0
		_catch.volume_db = _db(0.9)
		_catch.play()
	_was_running = running_now
	_since_catch += _delta
	# during the catch the one-shot carries it; the loop comes in under its tail
	var catch_k := smoothstep(0.7, 1.5, _since_catch) if _since_catch < 1.5 else 1.0
	if rpm > 80.0:
		_engine.pitch_scale = clampf(rpm / 2400.0, 0.12, 1.5)
		var load_level: float = 0.30 + 0.70 * clampf(plane.power_frac, 0.0, 1.0)
		if not plane.engine_running:
			load_level = 0.12
		# A rough engine surges and sags, and misses: a firing or two drops
		# out (a hole in the sound and a hitch in the pitch), and a really
		# sick one coughs (DESIGN_NOTES 167).
		var rough: float = float(e.roughness)
		load_level *= 1.0 - 0.45 * rough * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.011))
		if _miss_t > 0.0:
			_miss_t -= _delta
			load_level *= 0.22
			_engine.pitch_scale *= 0.96
		elif plane.engine_running and rough > 0.06 and randf() < rough * _delta * 7.0:
			_miss_t = randf_range(0.05, 0.11) * clampf(900.0 / maxf(rpm, 300.0), 0.4, 1.5)
			if rough > 0.45 and randf() < 0.3 and _catch != null:
				_catch.pitch_scale = randf_range(1.2, 1.5)
				_catch.volume_db = _db(0.25 + 0.3 * rough)      # a cough through the exhaust
				_catch.play()
		_engine.volume_db = _db(load_level * 0.8 * catch_k)
	else:
		_engine.volume_db = -80.0
	_starter.volume_db = _db(0.35) if e.cranking else -80.0
	if _turbo != null:
		var sp: float = float(e.get("spool")) if e.get("spool") != null else 0.0
		var bp: float = float(e.get("boost_psi")) if e.get("boost_psi") != null else 0.0
		_turbo.volume_db = _db(pow(clampf(sp, 0.0, 1.0), 1.3) * 0.32) if (bp > 0.2 or sp > 0.05) and rpm > 300.0 else -80.0
		_turbo.pitch_scale = 0.55 + 0.75 * clampf(sp, 0.0, 1.0)
	_starter.pitch_scale = 0.85 + 0.2 * clampf(float(e.battery), 0.0, 1.0)
	# Wind
	var v: float = clampf(plane.airspeed / 70.0, 0.0, 1.3)
	_wind.volume_db = _db(v * v * 0.42) if in_plane else -80.0
	_wind.pitch_scale = 0.7 + 0.5 * v
	# Tyres
	var roll := 0.0
	if plane.on_ground:
		roll = clampf(plane.ground_speed / 28.0, 0.0, 1.0)
	_rumble.volume_db = _db(roll * 0.6)
	_rumble.pitch_scale = 0.7 + 0.6 * roll
	# Tyres scrubbing: a locked wheel or a sideways skid
	var sk: float = plane.skid_level * clampf(plane.ground_speed / 10.0, 0.0, 1.0)
	_skid.volume_db = _db(sk * 0.5)
	_skid.pitch_scale = 0.8 + 0.4 * sk
	# A burning wreck
	_fire.volume_db = _db(float(plane.fire_strength) * 0.7) if plane.on_fire else -80.0
	# Stall horn: a quiet beep now, and it can be switched off (Season,
	# weather and realism page). The buffet and the panel lamp still warn.
	if Game.stall_horn and plane.stall_warning and not plane.is_crashed and in_plane:
		if not _horn.playing:
			_horn.volume_db = _db(0.10)
			_horn.play()
	elif _horn.playing:
		_horn.stop()
	# Gear warning horn: pulsing, gear not down, throttles back, low.
	var gear_warn: bool = in_plane and plane.is_retractable() and not plane.on_ground and plane.gear_pos < 0.99 and plane.throttle < 0.25 and plane.agl < 300.0 and not plane.is_crashed
	if gear_warn and int(Time.get_ticks_msec() / 400) % 2 == 0:
		if not _gear_horn.playing:
			_gear_horn.volume_db = _db(0.5)
			_gear_horn.play()
	elif _gear_horn.playing:
		_gear_horn.stop()
	# Touchdown
	var down: bool = plane.on_ground
	# a real touchdown only: coming down onto the wheels, not a parked plane
	# appearing at load or a respawn putting it on the strip
	if down and not _was_down and plane.vel.y < -0.4 and _quiet <= 0.0:
		var sink: float = clampf(-plane.vel.y / 3.0, 0.15, 1.0)
		_thump.volume_db = _db(sink)
		_thump.play()
		var surf: int = plane.surface_now
		if surf == 1 or surf == 3:      # gravel, dirt: stones and grit
			_gravel.volume_db = _db(sink * (1.0 if surf == 1 else 0.6))
			_gravel.pitch_scale = _rng.randf_range(0.9, 1.1)
			_gravel.play()
	_was_down = down
	# Water: a splash as anything first touches it, then the hiss of spray.
	var wet := 0.0
	for i in range(3):
		wet = maxf(wet, float(plane.wheel_water[i]))
	var spd: float = Vector2(plane.vel.x, plane.vel.z).length()
	if wet > 0.0 and not _was_wet and spd > 3.0:
		_splash.volume_db = _db(clampf(0.3 + spd / 30.0, 0.0, 1.0))
		_splash.play()
	_was_wet = wet > 0.0
	_spray.volume_db = _db(clampf(wet * 6.0, 0.0, 1.0) * clampf(spd / 20.0, 0.0, 1.0) * 0.6) if wet > 0.0 else -80.0
	# Rolling: louder and grittier on gravel, softer on grass.
	if plane.on_ground:
		var sf: int = plane.surface_now
		var k := 1.0
		if sf == 2:
			k = 0.55
		elif sf == 1:
			k = 1.25
		elif sf == 4 or sf == 5:
			k = 0.7
		_rumble.volume_db = _db(roll * 0.6 * k)
