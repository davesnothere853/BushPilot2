extends Node3D
## The sound of the place (DESIGN_NOTES 105), around wherever you are: wind
## (by the day's wind and the weather, in gusts), birds by day in the warm
## seasons (single calls from the trees round you, here and there), crickets
## on summer nights, running water near the creek and lapping at the pond,
## rain. Everything goes through the "Ambient" bus, which is muffled when
## you're inside a cab or the cockpit.

const RATE := 22050

var terrain: RefCounted
var inside := false               # set by main: in a cab / the cockpit
var in_air := false               # flying: the plane's own wind takes over

var _wind: AudioStreamPlayer
var _water: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _crickets: AudioStreamPlayer
var _birds: Array = []            # AudioStreamPlayer3D, placed round you per call
var _bird_streams: Array = []
var _bird_t := 2.0
var _gust := 0.0
var _gust_want := 0.0
var _gust_t := 0.0
var _rng := RandomNumberGenerator.new()
var _bus := -1
var _lp: AudioEffectLowPassFilter
var _t := 0.0
## Layers switched off from the console ("amb wind off"), for finding a sound.
var muted := {}


func _ready() -> void:
	_rng.seed = 777
	_bus = AudioServer.get_bus_index("Ambient")
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "Ambient")
		AudioServer.set_bus_send(_bus, "Master")
		_lp = AudioEffectLowPassFilter.new()
		_lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(_bus, _lp)
	else:
		_lp = AudioServer.get_bus_effect(_bus, 0) as AudioEffectLowPassFilter
	_wind = _loop2d(_noise(0.09, 0.006, 4.0))
	# the creek: made offline (bp2_audio/gen_amb.py) - a rush of water with
	# thousands of tiny bubbles in it; the old in-game one was loud separate blips
	# The creek's babble is gone: its bubbles came across as animals / frogs
	# croaking (Dave). A silent placeholder keeps the rest of the code simple.
	_water = _loop2d(_noise(0.09, 0.006, 0.5))
	_rain = _loop2d(_noise(0.45, 0.12, 2.0))
	_crickets = _loop2d(_noise(0.09, 0.006, 0.5))      # silent placeholder (crickets removed)
	for i in range(12):
		_bird_streams.append(_bird_call(i))
	for i in range(6):
		var b := AudioStreamPlayer3D.new()
		b.bus = "Ambient"
		b.unit_size = 6.0
		b.max_distance = 120.0
		b.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(b)
		_birds.append(b)


func _loop2d(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Ambient"
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or terrain == null:
		return
	_t += delta
	var p := cam.global_position
	var ground: float = terrain.height_at(p.x, p.z)
	var agl := p.y - ground
	var near_ground := clampf(1.0 - (agl - 10.0) / 80.0, 0.0, 1.0)
	var hour: float = Game.time_of_day
	var day := hour > 5.5 and hour < 20.5
	var warm: bool = Game.season != Game.WINTER
	var raining: bool = Game.weather == 2 and warm
	# muffled inside
	if _lp != null:
		_lp.cutoff_hz = lerpf(_lp.cutoff_hz, 900.0 if inside else 20000.0, clampf(6.0 * delta, 0.0, 1.0))
	# wind, in gusts
	_gust_t -= delta
	if _gust_t <= 0.0:
		_gust_t = _rng.randf_range(1.5, 5.0)
		_gust_want = _rng.randf_range(0.0, 1.0)
	_gust = lerpf(_gust, _gust_want, clampf(0.8 * delta, 0.0, 1.0))
	var wl: float = [0.04, 0.25, 0.5, 0.8][clampi(Game.wind_level, 0, 3)]
	if Game.weather == 2:
		wl += 0.15
	var wind := wl * (0.6 + 0.6 * _gust) * (0.4 if in_air else 1.0) * (0.6 + 0.4 * clampf(agl / 30.0, 0.0, 1.0))
	_wind.volume_db = _db(wind * 0.3)
	_wind.pitch_scale = 0.8 + 0.4 * _gust
	# running water: the creek, the pond's edge
	var wet := 0.0
	var cd: float = terrain.creek_dist(p.x, p.z, 60.0) if terrain.has_method("creek_dist") else 1.0e9
	if cd < 45.0:
		wet = maxf(wet, clampf(1.0 - cd / 45.0, 0.0, 1.0))
	for lk in terrain.lakes:
		var lp2: Vector2 = lk["pos"]
		var d := Vector2(p.x, p.z).distance_to(lp2) - float(lk["radius"])
		if d < 40.0:
			wet = maxf(wet, clampf(1.0 - absf(d) / 40.0, 0.0, 1.0) * 0.6)
	_water.volume_db = -80.0     # creek babble removed (Dave)
	# rain
	_rain.volume_db = _db((0.3 if raining else 0.0) * (1.3 if inside else 1.0))
	# crickets: warm nights, near the ground
	var night := hour > 21.0 or hour < 4.5
	_crickets.volume_db = -80.0     # night chorus removed: it sounded like frogs (Dave)
	for k in muted:
		var pl: AudioStreamPlayer = {"wind": _wind, "water": _water, "rain": _rain, "crickets": _crickets}.get(k)
		if pl != null:
			pl.volume_db = -80.0
	# birds: a call now and then from the trees round you, by day
	_bird_t -= delta
	if _bird_t <= 0.0:
		# busy at dawn and dusk, the odd lone call through the middle of the day
		var chorus := hour > 4.5 and hour < 9.5 or hour > 18.0 and hour < 21.0
		_bird_t = _rng.randf_range(0.6, 2.5) if chorus else _rng.randf_range(2.0, 9.0)
		# The synthesized bird calls are gone: off the strip they read as frogs
		# croaking (Dave). Real recorded birds can come back later.
		if false and day and warm and not raining and near_ground > 0.3 and not muted.has("birds"):
			# sometimes one bird answers another nearby a moment later
			var calls := 2 if _rng.randf() < 0.3 else 1
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(10.0, 70.0)
			var sp: int = _rng.randi() % _bird_streams.size()
			for c in range(calls):
				var b: AudioStreamPlayer3D = null
				for cand in _birds:
					if not (cand as AudioStreamPlayer3D).playing:
						b = cand
						break
				if b == null:
					break
				var aa := a + (0.0 if c == 0 else _rng.randf_range(-0.8, 0.8))
				var rr := r * (1.0 if c == 0 else _rng.randf_range(0.6, 1.4))
				b.global_position = Vector3(p.x + cos(aa) * rr, ground + _rng.randf_range(3.0, 14.0), p.z + sin(aa) * rr)
				b.stream = _bird_streams[sp]
				b.pitch_scale = _rng.randf_range(0.92, 1.1)
				b.volume_db = _db(_rng.randf_range(0.2, 0.55) * (1.0 if r < 40.0 else 0.6))
				if c == 0:
					b.play()
				else:
					get_tree().create_timer(_rng.randf_range(0.8, 2.2)).timeout.connect(b.play)


static func _db(x: float) -> float:
	return linear_to_db(clampf(x, 0.00001, 1.0))


# ------------------------------------------------------------------------------
#  Making the sounds
# ------------------------------------------------------------------------------
func _noise(lowpass: float, highpass: float, seconds: float) -> AudioStreamWAV:
	# three low-pass stages, not one: a single stage lets a hiss of high
	# "static" through; three leave a soft whoosh
	var n := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	var l3 := 0.0
	var hp := 0.0
	for i in range(n):
		l1 = lerpf(l1, _rng.randf_range(-1.0, 1.0), lowpass)
		l2 = lerpf(l2, l1, lowpass)
		l3 = lerpf(l3, l2, lowpass)
		hp = lerpf(hp, l3, highpass)
		out[i] = l3 - hp
	return _seam(out, 3000)


## A brook: a bed of soft noise with bubbles (short rising tones) through it.
func _file_loop(path: String) -> AudioStream:
	var st: AudioStreamWAV = null
	if ResourceLoader.exists(path):
		st = load(path) as AudioStreamWAV
	if st == null:
		st = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	if st == null:
		return null
	st = st.duplicate() as AudioStreamWAV
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = int(st.get_length() * float(st.mix_rate))
	return st


func _brook() -> AudioStreamWAV:
	var n := RATE * 3
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var hp := 0.0
	var l2 := 0.0
	var l3 := 0.0
	for i in range(n):
		# three stages: a gurgle, not a hiss of static
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.18)
		l2 = lerpf(l2, lp, 0.18)
		l3 = lerpf(l3, l2, 0.18)
		hp = lerpf(hp, l3, 0.03)
		out[i] = (l3 - hp) * 0.45
	for b in range(140):
		var at := _rng.randi_range(0, n - 1)
		var f0 := _rng.randf_range(500.0, 1400.0)
		var len_s := _rng.randf_range(0.01, 0.04)
		var m := int(len_s * RATE)
		var ph := 0.0
		for j in range(m):
			var t := float(j) / float(RATE)
			ph += TAU * f0 * (1.0 + 2.5 * t / len_s) / float(RATE)
			out[(at + j) % n] += sin(ph) * exp(-t * 90.0) * _rng.randf_range(0.15, 0.3)
	return _seam(out, 3000)


## Crickets: a 4.5 kHz trill in pulses, a few insects out of step.
func _cricket_loop() -> AudioStreamWAV:
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	for c in range(3):
		var f := _rng.randf_range(4200.0, 4800.0)
		var rate := float([2, 3, 4][c])          # chirps a second (whole, so it loops)
		var ph0 := _rng.randf()
		var gain := _rng.randf_range(0.4, 1.0)
		for i in range(n):
			var t := float(i) / float(RATE)
			var cyc := fposmod(t * rate + ph0, 1.0)
			if cyc < 0.18:
				var trill := 0.5 + 0.5 * sin(TAU * 45.0 * t)
				out[i] += sin(TAU * f * t) * trill * sin(PI * cyc / 0.18) * 0.25 * gain
	return _wav(out, true)


## One bird call. A few kinds, so the woods don't sound like one bird:
##   whistles   a few quick notes sweeping up or down
##   trill      a fast run of the same short note
##   two-note   a clear high note falling to a lower one
func _bird_call(v: int) -> AudioStreamWAV:
	var kind := v % 4
	if kind == 1:
		kind = 0          # the fast trill sounded like a frog: whistles instead
	var out := PackedFloat32Array()
	var ph := 0.0
	if kind == 1:                                       # trill
		var notes := _rng.randi_range(8, 16)
		var gap := _rng.randf_range(0.045, 0.07)
		var f0 := _rng.randf_range(3000.0, 5200.0)
		out.resize(int(RATE * (gap * notes + 0.1)))
		for k in range(notes):
			var start := int(RATE * gap * k)
			var len_n := int(RATE * gap * 0.7)
			for j in range(len_n):
				var t := float(j) / float(len_n)
				ph += TAU * f0 * (1.0 - 0.15 * t) / float(RATE)
				out[start + j] += sin(ph) * sin(PI * t) * 0.45 * (1.0 - 0.3 * float(k) / notes)
		return _wav(out, false)
	if kind == 2:                                       # two-note
		var hi := _rng.randf_range(3400.0, 4200.0)
		var lo := hi * _rng.randf_range(0.72, 0.84)
		out.resize(int(RATE * 0.75))
		for k in range(2):
			var start := int(RATE * (0.0 if k == 0 else 0.33))
			var len_n := int(RATE * 0.28)
			var f := hi if k == 0 else lo
			for j in range(len_n):
				var t := float(j) / float(len_n)
				ph += TAU * f * (1.0 + 0.01 * sin(TAU * 6.0 * t)) / float(RATE)
				out[start + j] += sin(ph) * sin(PI * t) * 0.5
		return _wav(out, false)
	var notes2 := _rng.randi_range(2, 6)
	out.resize(int(RATE * (0.12 * float(notes2) + 0.1)))
	var base := _rng.randf_range(2200.0, 4200.0)
	for k in range(notes2):
		var start := int(RATE * 0.12 * float(k))
		var len_n := int(RATE * _rng.randf_range(0.05, 0.1))
		var f0 := base * _rng.randf_range(0.85, 1.2)
		var sweep := _rng.randf_range(-0.4, 0.5) if kind == 0 else _rng.randf_range(0.2, 0.7)
		for j in range(len_n):
			var t := float(j) / float(len_n)
			ph += TAU * f0 * (1.0 + sweep * t) * (1.0 + 0.03 * sin(TAU * 30.0 * t)) / float(RATE)
			if start + j < out.size():
				out[start + j] += sin(ph) * sin(PI * t) * 0.5
	return _wav(out, false)


func _seam(out: PackedFloat32Array, fade: int) -> AudioStreamWAV:
	var n := out.size()
	for i in range(fade):
		var k := float(i) / float(fade)
		out[i] = out[i] * k + out[n - fade + i] * (1.0 - k)
	out.resize(n - fade)
	var peak := 0.001
	for v in out:
		peak = maxf(peak, absf(v))
	for i in range(out.size()):
		out[i] = out[i] / peak * 0.7
	return _wav(out, true)


static func _wav(buf: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in range(buf.size()):
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = buf.size()
	return wav
