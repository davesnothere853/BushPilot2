extends Node3D
## An engine you can hear where it is (DESIGN_NOTES 105). Made from scratch
## like the rest of the game's sound: a loop of real firing pulses at a base
## rpm, played faster or slower with the engine, two loops (idle, high)
## blended as the revs climb so neither is stretched too far. A starter
## grinds before it catches; it dies away when the engine stops.
##
## Kinds:
##   "v8cam"   an old small-block 350 with a big cam: crossplane V8 firing
##             (uneven per bank, the burble) and a lumpy, loping idle.
##   "diesel"  a big inline six: deep exhaust, injector
##             clatter on every firing, the turbo whistle with load.
##   "machine" the same diesel, deeper, with a hydraulic whine under load
##             (dozer, excavator, loader).
##   "small"   a single-cylinder engine (generator, trommel, pump).
##
## `state` is a Callable returning {"rpm", "running", "load" (optional 0-1)}.

const RATE := 22050
const KINDS := {
	"v8cam":   {"idle": 960.0, "high": 2880.0, "fade": [1300.0, 2400.0], "unit": 5.0, "vol": 0.85},
	"diesel":  {"idle": 720.0, "high": 1800.0, "fade": [950.0, 1500.0], "unit": 7.0, "vol": 0.9},
	"machine": {"idle": 720.0, "high": 1800.0, "fade": [950.0, 1500.0], "unit": 8.0, "vol": 0.9},
	"small":   {"idle": 3600.0, "high": 3600.0, "fade": [9000.0, 9001.0], "unit": 2.5, "vol": 0.6},
	# the Cub's flat-four (O-320 type, open short stacks): an even, hard
	# bark two firings a rev, plus the prop's beat on its own layer
	"lyc4":    {"idle": 700.0, "high": 2400.0, "fade": [1000.0, 1800.0], "unit": 14.0, "vol": 1.0},
}

static var _cache := {}             # kind -> [idle stream, high stream, starter, whine]

var kind := "v8cam"
var state: Callable
var _lo: AudioStreamPlayer3D
var _hi: AudioStreamPlayer3D
var _crank: AudioStreamPlayer3D
var _whine: AudioStreamPlayer3D
var _was_running := false
var _turbo_p: AudioStreamPlayer3D     # a turbo bolted on (parts, DESIGN_NOTES 111)
var _prop_p: AudioStreamPlayer3D      # the prop's beat and tip roar (lyc4)
var _catch: AudioStreamPlayer3D       # the coughs and catch as it fires up (lyc4)
var _start_t := 0.0
var _last_rpm := 0.0
var _load := 0.0


func _ready() -> void:
	if LAYERS.has(kind):
		_ready_diesel()
		return
	var st: Array = streams(kind)
	var k: Dictionary = KINDS[kind]
	_lo = _player(st[0], float(k["unit"]))
	_hi = _player(st[1], float(k["unit"]))
	var crank_st: AudioStream = _dsl("crank_v8.wav", true) if kind == "v8cam" else (_dsl("starter.wav", true, "res://assets/sounds/plane/") if kind == "lyc4" else null)
	if kind == "lyc4":
		_prop_p = _player(_prop_loop(), 16.0)
		_catch = AudioStreamPlayer3D.new()
		_catch.stream = _dsl("start.wav", false, "res://assets/sounds/plane/")
		_catch.bus = engines_bus()
		_catch.unit_size = 14.0
		_catch.max_distance = 450.0
		add_child(_catch)
	_crank = _player(crank_st if crank_st != null else st[2], float(k["unit"]) * 0.7)
	_whine = _player(st[3], float(k["unit"]) * 0.6)
	_turbo_p = _player(_dsl("turbo.wav", true), 4.0)


func _player(stream: AudioStream, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = engines_bus()          # every engine is muffled when you're in a cab
	p.unit_size = unit
	p.max_distance = 450.0
	p.attenuation_filter_cutoff_hz = 6000.0
	p.attenuation_filter_db = -18.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.volume_db = -80.0
	add_child(p)
	p.play()
	_gated.append(p)
	return p


## (DESIGN_NOTES 186) Looping players held at -80 dB were still decoded, resampled
## and mixed every frame: 9 per diesel/V8, 5 per synth engine, 8+ on the plane.
## A loop turned right down stops, and starts again the frame it's turned up.
const GATE_DB := -60.0
var _gated: Array = []
static func gate_loops(players: Array) -> void:
	for p in players:
		if p == null or not is_instance_valid(p) or p.stream == null:
			continue
		var want: bool = p.volume_db > GATE_DB
		if want and not p.playing:
			p.play()
		elif not want and p.playing:
			p.stop()


func _process(delta: float) -> void:
	if not state.is_valid():
		return
	gate_loops(_gated)
	_cab_effect(delta)
	if LAYERS.has(kind):
		_process_diesel(delta)
		return
	var s: Dictionary = state.call()
	var rpm: float = float(s.get("rpm", 0.0))
	var running: bool = bool(s.get("running", false))
	var k: Dictionary = KINDS[kind]
	# The starter: on the turn of the key it grinds for a moment before the
	# engine catches and comes up.
	if running and not _was_running:
		_start_t = 1.15 if kind == "v8cam" else (1.3 if kind == "lyc4" else 0.75)
		if _catch != null and _catch.stream != null:
			_catch.volume_db = _db(0.85)
			_catch.play()
	_was_running = running
	if _start_t > 0.0:
		_start_t -= delta
	_crank.volume_db = _db(0.6) if _start_t > 0.15 else -80.0
	# How hard it's working: what we're told, or the revs climbing.
	var climb := clampf((rpm - _last_rpm) / maxf(delta, 0.001) / 1500.0, 0.0, 1.0)
	_last_rpm = rpm
	var want_load: float = maxf(float(s.get("load", 0.0)), climb)
	_load = lerpf(_load, want_load, clampf(4.0 * delta, 0.0, 1.0))
	var idle: float = k["idle"]
	var high: float = k["high"]
	var heard := clampf(rpm / (idle * 0.5), 0.0, 1.0)       # dies away as it spins down
	if _start_t > 0.3:
		heard = 0.0
	var f: Array = k["fade"]
	var w := smoothstep(float(f[0]), float(f[1]), rpm)
	var vol: float = float(k["vol"]) * heard * (0.55 + 0.45 * _load)
	_lo.pitch_scale = clampf(rpm / idle, 0.35, 2.6)
	_hi.pitch_scale = clampf(rpm / high, 0.35, 2.6)
	_lo.volume_db = _db(vol * (1.0 - w))
	_hi.volume_db = _db(vol * w)
	# turbo whistle (diesels) / hydraulic whine (machines): with boost
	if _turbo_p != null:
		var tb: float = clampf(float(s.get("boost", 0.0)), 0.0, 1.0)
		_turbo_p.pitch_scale = 0.5 + 0.65 * tb
		_turbo_p.volume_db = _db(pow(tb, 1.3) * 0.5 * heard) if tb > 0.01 else -80.0
	if _prop_p != null:
		# the prop: its blade-pass beat follows rpm x blades, louder as it
		# winds up (it's most of what you hear from outside a Cub at full power)
		var blades: float = float(s.get("blades", 2.0))
		var pr := clampf(rpm / 2300.0, 0.0, 1.3)
		_prop_p.pitch_scale = clampf(pr * blades / 2.0, 0.2, 2.5)
		_prop_p.volume_db = _db(pow(pr, 1.6) * 0.8) if rpm > 150.0 else -80.0
	if kind == "diesel" or kind == "machine":
		var boost := clampf((rpm - idle) / (high - idle), 0.0, 1.0) * (0.4 + 0.6 * _load)
		_whine.pitch_scale = 0.7 + 0.8 * boost
		_whine.volume_db = _db(boost * (0.12 if kind == "diesel" else 0.18) * heard)
	else:
		_whine.volume_db = -80.0


static func _db(x: float) -> float:
	return linear_to_db(clampf(x, 0.00001, 1.0))


# ------------------------------------------------------------------------------
#  Making the sounds
# ------------------------------------------------------------------------------
static func streams(k: String) -> Array:
	if _cache.has(k):
		return _cache[k]
	var spec: Dictionary = KINDS[k]
	var out: Array = [
		_engine_loop(k, float(spec["idle"]), true),
		_engine_loop(k, float(spec["high"]), false),
		_starter_loop(k),
		_whine_loop(k),
	]
	_cache[k] = out
	return out


## One second of the engine at `rpm`: every firing is a pulse, placed and
## sized by cylinder so the loop has the engine's own rhythm; the cycle and
## any lope are whole numbers per second, so the loop joins without a seam.
static func _engine_loop(k: String, rpm: float, idle: bool) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k) + int(rpm)
	var n := RATE
	var buf := PackedFloat32Array()
	buf.resize(n)
	var cyl := 8
	var per_rev := 4.0
	match k:
		"diesel", "machine":
			cyl = 6
			per_rev = 3.0
		"small":
			cyl = 1
			per_rev = 0.5
		"lyc4":
			cyl = 4
			per_rev = 2.0
	var fire_hz := rpm / 60.0 * per_rev
	var firings := int(round(fire_hz))           # in one second
	# Per-cylinder strength and timing: a crossplane V8 fires unevenly along
	# each bank (the burble); a diesel six is even but each pot's a bit off.
	var amp: Array[float] = []
	var lag: Array[float] = []
	for c in range(cyl):
		if k == "v8cam":
			amp.append([1.0, 0.62, 0.92, 0.7, 1.0, 0.58, 0.86, 0.74][c])
			lag.append([0.0, 0.11, -0.04, 0.09, 0.02, 0.13, -0.06, 0.07][c])
		else:
			amp.append(rng.randf_range(0.85, 1.0))
			lag.append(rng.randf_range(-0.03, 0.03))
	var cycle_hz := fire_hz / float(cyl)
	for i in range(firings):
		var c := i % cyl
		var t0 := (float(i) + lag[c]) / fire_hz
		var a: float = amp[c]
		if k == "v8cam" and idle:
			# The cam's lope: overlap lets one cylinder in each cycle stumble,
			# and the whole idle rolls twice a second.
			var roll := 0.5 + 0.5 * sin(TAU * 2.0 * t0)
			a *= 0.55 + 0.6 * roll
			if c == 3:
				a *= 0.35
			t0 += 0.02 * sin(TAU * 2.0 * t0) / fire_hz
		_add_pulse(buf, k, t0, a, rng)
	# a little steady mechanical noise under it all
	var lp := 0.0
	for j in range(n):
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.15)
		buf[j] += lp * (0.05 if k != "small" else 0.08)
	# smooth, saturate, normalise
	var peak := 0.001
	var y := 0.0
	var cut := 0.55 if k == "v8cam" else (0.7 if k == "small" else (0.65 if k == "lyc4" else (0.35 if k == "machine" else 0.6)))   # the machine: rounder, the highs rolled off
	for j in range(n):
		y = lerpf(y, buf[j], cut)
		buf[j] = tanh(y * 1.4)
	var y2 := buf[n - 1]
	for j in range(n):        # run once more round the loop so the start matches the end
		y2 = lerpf(y2, buf[j], 0.9)
		buf[j] = y2
		peak = maxf(peak, absf(y2))
	for j in range(n):
		buf[j] = buf[j] / peak * 0.8
	return _wav(buf)


## One firing: what comes out of the pipe, wrapped round the loop.
static func _add_pulse(buf: PackedFloat32Array, k: String, t0: float, a: float, rng: RandomNumberGenerator) -> void:
	var n := buf.size()
	var start := int(t0 * RATE)
	var length := int(RATE * (0.03 if k == "small" else (0.09 if k == "machine" else 0.05)))
	var res := 85.0          # the pipe's thump
	var dec := 55.0
	var body := 0.9
	var grit := 0.35
	match k:
		"diesel":
			res = 52.0
			dec = 40.0
		"machine":
			res = 28.0           # Dave: deeper, more bass - a big slow thump from a big six
			dec = 18.0
			body = 1.2
			grit = 0.18
		"small":
			res = 140.0
			dec = 70.0
			grit = 0.5
		"lyc4":
			res = 64.0           # short open stacks: a hard, dry bark
			dec = 36.0
			grit = 0.7
	var hp := 0.0
	var prev := 0.0
	for j in range(length):
		var t := float(j) / float(RATE)
		var thump := sin(TAU * res * t) * exp(-t * dec) * body
		var w := rng.randf_range(-1.0, 1.0)
		hp = w - prev
		prev = w
		var bark := hp * exp(-t * 180.0) * grit
		var v := thump + bark
		if k == "diesel" or k == "machine":
			# injector clatter: a hard metallic tick on every firing
			v += (sin(TAU * 2900.0 * t) * 0.5 + hp * 0.6) * exp(-t * 900.0) * (0.2 if k == "machine" else 0.55)
		buf[(start + j) % n] += v * a


## The prop at 2300 rpm, two blades (pitch-scaled for the rest): each blade
## passing gives a low "whup" and a burst of tip roar; the loop is a whole
## number of passes long.
static func _prop_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2300
	var n := RATE
	var buf := PackedFloat32Array()
	buf.resize(n)
	var bp := 2300.0 / 60.0 * 2.0          # blade passes a second (~77)
	var passes := int(round(bp))
	bp = float(passes)
	var lp := 0.0
	var lp2 := 0.0
	for i in range(n):
		var t := float(i) / float(RATE)
		var ph := fposmod(t * bp, 1.0)
		var whup := sin(TAU * bp * t) * 0.55 + sin(TAU * bp * 2.0 * t) * 0.22 + sin(TAU * bp * 3.0 * t) * 0.08
		var env := 0.35 + 0.65 * exp(-ph * 5.0)               # the tip roar comes in a burst each pass
		var w := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, w, 0.35)
		lp2 = lerpf(lp2, lp, 0.35)
		buf[i] = whup * 0.6 + (lp - lp2) * 2.2 * env * 0.5
	var peak := 0.001
	for j in range(n):
		peak = maxf(peak, absf(buf[j]))
	for j in range(n):
		buf[j] = buf[j] / peak * 0.8
	return _wav(buf)


## Electric starter grinding: a geared whine with the compression lumps.
static func _starter_loop(k: String) -> AudioStreamWAV:
	var n := RATE
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f := 160.0 if k == "v8cam" else (120.0 if k != "small" else 220.0)
	var lumps := 5.0 if k == "v8cam" else 4.0
	for i in range(n):
		var t := float(i) / float(RATE)
		var whine := sin(TAU * f * t) * 0.35 + sin(TAU * f * 2.0 * t) * 0.2 + signf(sin(TAU * f * 0.5 * t)) * 0.12
		var lump := 0.55 + 0.45 * sin(TAU * lumps * t)
		buf[i] = whine * lump * 0.6
	return _wav(buf)


## The turbo's whistle (or the hydraulic pump's whine): a few close tones.
static func _whine_loop(k: String) -> AudioStreamWAV:
	var n := RATE
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f := 2400.0 if k == "diesel" else 1100.0
	for i in range(n):
		var t := float(i) / float(RATE)
		buf[i] = (sin(TAU * f * t) * 0.5 + sin(TAU * (f + 7.0) * t) * 0.3 + sin(TAU * f * 1.5 * t) * 0.15) * 0.6
	return _wav(buf)


static func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in range(buf.size()):
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = buf.size()
	return wav


# ------------------------------------------------------------------------------
#  The heavy diesel (DESIGN_NOTES 110): recorded-style layers made offline
#  (bp2_audio/gen_diesel.py) and blended here by rpm, load and throttle.
# ------------------------------------------------------------------------------
const DSL := "res://assets/sounds/diesel/"
## Engines built from offline layers (bp2_audio/gen_*.py): folder, the rpm of
## the idle and the three running loops, how long the start sound carries it,
## and whether it has a turbo and an engine brake of its own.
const LAYERS := {
	"diesel": {"dir": "res://assets/sounds/diesel/", "rpm": [650.0, 1000.0, 1450.0, 1900.0], "start": 2.3, "turbo": true, "jake": true, "unit": 7.0},
	# the machines (loader, dozer, excavator...): a real old front loader's cold
	# start (freesound 561724, CC0) - its starter, coughs, catch and rough idle
	# (assets/sounds/machine/) - and above idle the truck's diesel recordings
	# played slower so they're deeper (Dave: real, more bass)
	"machine": {"dir": "res://assets/sounds/diesel/", "rpm": [720.0, 1300.0, 1800.0, 2400.0], "files": [1000, 1450, 1900], "start": 6.0, "turbo": false, "jake": false, "unit": 9.0, "own": "res://assets/sounds/machine/"},
	"v8cam": {"dir": "res://assets/sounds/v8/", "rpm": [900.0, 1600.0, 2600.0, 3600.0], "start": 1.9, "turbo": false, "jake": false, "unit": 5.0},
}
var DSL_RPM: Array = [650.0, 1000.0, 1450.0, 1900.0]
var _ldir := DSL
## The cab's doors and firewall between you and it (main sets this each frame).
static var cab_muffle := false
static var _bus_lp: AudioEffectLowPassFilter
static var _dsl_cache := {}

var _d_idle: AudioStreamPlayer3D
var _d_load: Array = []        # per rpm point above idle
var _d_coast: Array = []
var _d_turbo: AudioStreamPlayer3D
var _d_jake: AudioStreamPlayer3D
var _d_start: AudioStreamPlayer3D
var _d_stop: AudioStreamPlayer3D
var _d_heard := 0.0            # the loops fade in as it catches, out as it dies
var _d_since_start := 99.0
var _d_load_s := 0.0
var _d_boost := 0.0
var _d_jake_v := 0.0
var _d_rpm := 0.0


static func _dsl(name: String, loop: bool, dir: String = DSL) -> AudioStream:
	var key := dir + name + str(loop)
	if _dsl_cache.has(key):
		return _dsl_cache[key]
	var st: AudioStreamWAV = null
	if ResourceLoader.exists(dir + name):
		st = load(dir + name) as AudioStreamWAV
	if st == null:
		# not imported yet (new file): read the .wav straight off the disk
		st = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(dir + name))
	if st == null:
		return null
	if loop:
		st = st.duplicate() as AudioStreamWAV
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * float(st.mix_rate))
	_dsl_cache[key] = st
	return st


## The "Engines" bus: engine sounds go through a low-pass that closes down
## when you're in a cab (DESIGN_NOTES 110).
static func engines_bus() -> String:
	var bi := AudioServer.get_bus_index("Engines")
	if bi < 0:
		AudioServer.add_bus()
		bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "Engines")
		AudioServer.set_bus_send(bi, "Master")
		_bus_lp = AudioEffectLowPassFilter.new()
		_bus_lp.cutoff_hz = 20000.0
		_bus_lp.resonance = 0.6
		AudioServer.add_bus_effect(bi, _bus_lp)
	elif _bus_lp == null:
		_bus_lp = AudioServer.get_bus_effect(bi, 0) as AudioEffectLowPassFilter
	return "Engines"


func _dplayer(stream: AudioStream, unit: float, autoplay: bool) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = engines_bus()
	p.unit_size = unit
	p.max_distance = 500.0
	p.attenuation_filter_cutoff_hz = 5000.0
	p.attenuation_filter_db = -14.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.volume_db = -80.0
	add_child(p)
	if autoplay and stream != null:
		p.play()
		_gated.append(p)
	return p


var _d_crank: AudioStreamPlayer3D     # the starter grinding (machines)
var _d_cough: AudioStreamPlayer3D     # a try that fires and dies (machines)
var _d_coughs := 0
var _d_cold: AudioStreamPlayer3D      # the whole real cold start in one piece (machines, frozen mornings)


func _ready_diesel() -> void:
	var ly: Dictionary = LAYERS[kind]
	_ldir = String(ly["dir"])
	DSL_RPM = ly["rpm"]
	var u := float(ly["unit"])
	var own := String(ly.get("own", ""))
	_d_idle = _dplayer(_dsl("idle.wav", true, own if own != "" else _ldir), u, true)
	if own != "":
		_d_crank = _dplayer(_dsl("crank.wav", true, own), u, false)
		_d_cough = _dplayer(_dsl("cough.wav", false, own), u, false)
		_d_cold = _dplayer(_dsl("cold_start.wav", false, own), u, false)
	# the recordings' own rpm names the files; "rpm" is where they play (the
	# machines play the truck's 1000/1450/1900 recordings slower, deeper)
	var files: Array = ly.get("files", [DSL_RPM[1], DSL_RPM[2], DSL_RPM[3]])
	for r in files:
		_d_load.append(_dplayer(_dsl("%d_load.wav" % int(r), true, _ldir), u + 1.0, true))
		_d_coast.append(_dplayer(_dsl("%d_coast.wav" % int(r), true, _ldir), u, true))
	# a turbo: the diesel's own, or one bolted onto the V8 (parts); the boost says how much
	_d_turbo = _dplayer(_dsl("turbo.wav", true), 4.0, true)
	_d_jake = _dplayer(_dsl("jake.wav", true), 10.0, true) if bool(ly["jake"]) else null
	_d_start = _dplayer(_dsl("catch.wav" if own != "" else "start.wav", false, own if own != "" else _ldir), u, false)
	_d_stop = _dplayer(_dsl("stop.wav", false, _ldir), u, false)
	_d_start.volume_db = 0.0
	_d_stop.volume_db = -2.0


## state: rpm, running, load 0..1 (how hard it's pulling), throttle 0..1,
## speed m/s (for the engine brake).
func _process_diesel(delta: float) -> void:
	var s: Dictionary = state.call()
	var rpm: float = float(s.get("rpm", 0.0))
	var running: bool = bool(s.get("running", false))
	var thr: float = clampf(float(s.get("throttle", 0.0)), 0.0, 1.0)
	var spd: float = absf(float(s.get("speed", 0.0)))
	var want_load: float = clampf(float(s.get("load", 0.0)), 0.0, 1.0)
	_cab_effect(delta)
	# the machines: the starter grinds while it cranks, a cough on each try that dies
	if _d_cold != null and bool(s.get("cold_start", false)) and not _d_cold.playing and _d_since_start > 3.0 and not running:
		_d_cold.volume_db = _db(0.95)
		_d_cold.play()
	if _d_crank != null:
		var cranking := bool(s.get("cranking", false))
		if cranking and not _d_crank.playing:
			_d_crank.play()
		elif not cranking and _d_crank.playing:
			_d_crank.stop()
		_d_crank.volume_db = _db(0.75) if cranking else -80.0
		var cn := int(s.get("coughs", 0))
		if cn != _d_coughs:
			_d_coughs = cn
			_d_cough.volume_db = _db(0.9)
			_d_cough.play()
	# starting and stopping are their own sounds
	if running and not _was_running:
		_d_since_start = 0.0
		if _d_cold != null and _d_cold.playing:
			# the cold-start recording carries its own catch and rev: the loops come
			# in as it ends
			var left: float = _d_cold.stream.get_length() - _d_cold.get_playback_position()
			_d_since_start = float(LAYERS[kind]["start"]) - left
		else:
			_d_start.play()
		_d_stop.stop()
	elif not running and _was_running:
		if _d_rpm > 300.0:
			_d_stop.play()
	_was_running = running
	_d_since_start += delta
	var heard_want := 0.0
	if running:
		heard_want = 0.0 if _d_since_start < float(LAYERS[kind]["start"]) else 1.0          # the start sound carries it till it settles
	_d_heard = move_toward(_d_heard, heard_want, (1.6 if heard_want > _d_heard else 4.0) * delta)
	_d_rpm = rpm if running else move_toward(_d_rpm, 0.0, 600.0 * delta)
	var r := maxf(rpm, 1.0)
	# load: quick to come on with the throttle, a little slower to fall
	_d_load_s = lerpf(_d_load_s, want_load, clampf((6.0 if want_load > _d_load_s else 3.0) * delta, 0.0, 1.0))
	var L := _d_load_s
	# rpm crossfade (equal power) between the recorded points
	var w := [0.0, 0.0, 0.0, 0.0]
	if r <= DSL_RPM[0]:
		w[0] = 1.0
	elif r >= DSL_RPM[3]:
		w[3] = 1.0
	else:
		for i in range(3):
			if r >= DSL_RPM[i] and r <= DSL_RPM[i + 1]:
				var f: float = (r - float(DSL_RPM[i])) / (float(DSL_RPM[i + 1]) - float(DSL_RPM[i]))
				w[i] = cos(f * PI * 0.5)
				w[i + 1] = sin(f * PI * 0.5)
	var base := _d_heard * (0.62 + 0.38 * L)
	_d_idle.pitch_scale = clampf(r / DSL_RPM[0], 0.5, 1.9)
	_d_idle.volume_db = _db(base * float(w[0]) * 0.95)
	for i in range(3):
		var pr: float = DSL_RPM[i + 1]
		var lp: AudioStreamPlayer3D = _d_load[i]
		var cp: AudioStreamPlayer3D = _d_coast[i]
		lp.pitch_scale = clampf(r / pr, 0.5, 1.8)
		cp.pitch_scale = lp.pitch_scale
		lp.volume_db = _db(base * float(w[i + 1]) * sqrt(L))
		cp.volume_db = _db(base * float(w[i + 1]) * sqrt(1.0 - L) * 0.8)
	# turbo: spools up with revs under load (and lags behind them), whistles
	# down when you lift
	var boost_want := clampf((r - 850.0) / 1150.0, 0.0, 1.0) * (0.2 + 0.8 * L) if running else 0.0
	if not bool(LAYERS[kind]["turbo"]):
		boost_want = clampf(float(s.get("boost", 0.0)), 0.0, 1.0) if running else 0.0     # only a fitted turbo
	_d_boost = move_toward(_d_boost, boost_want, (0.55 if boost_want > _d_boost else 0.9) * delta)
	_d_turbo.pitch_scale = 0.5 + 0.6 * _d_boost
	_d_turbo.volume_db = _db(pow(_d_boost, 1.4) * 0.42 * maxf(_d_heard, 0.0 if running else 0.0) + (pow(_d_boost, 1.4) * 0.3 if not running else 0.0))
	# compression-release engine brake: foot off at speed with the revs up
	var jake_on := _d_jake != null and running and thr < 0.05 and spd > 3.0 and r > 1150.0 and _d_heard > 0.9
	_d_jake_v = move_toward(_d_jake_v, 1.0 if jake_on else 0.0, (6.0 if jake_on else 9.0) * delta)
	if _d_jake != null:
		_d_jake.pitch_scale = clampf(r / 1800.0, 0.55, 1.4)
		_d_jake.volume_db = _db(_d_jake_v * 0.55)
	if jake_on:
		# the brake's bark replaces most of the coasting sound
		for i in range(3):
			var cp2: AudioStreamPlayer3D = _d_coast[i]
			cp2.volume_db -= 6.0 * _d_jake_v


## In a cab you hear the engine through the firewall and the doors: dull and
## a good deal quieter. Out on foot it opens right up again.
static var _cab_t := 0
static func _cab_effect(delta: float) -> void:
	var f := Engine.get_process_frames()
	if f == _cab_t:
		return                      # once a frame, however many engines there are
	_cab_t = f
	engines_bus()
	var bi := AudioServer.get_bus_index("Engines")
	var k := clampf(6.0 * delta, 0.0, 1.0)
	if _bus_lp != null:
		_bus_lp.cutoff_hz = lerpf(_bus_lp.cutoff_hz, 850.0 if cab_muffle else 20000.0, k)
	if bi >= 0:
		AudioServer.set_bus_volume_db(bi, lerpf(AudioServer.get_bus_volume_db(bi), -8.0 if cab_muffle else 0.0, k))
