extends Node
## What an old machine sounds like from the inside (DESIGN_NOTES 114):
##   clunks   the suspension bottoming out, the gear on a rough strip, the
##            load shifting: off the jolts the vehicle actually takes
##   squeaks  dry springs and the seat, more the rougher the going
##   rattles  a loose panel or the tool box chattering on rough ground
##   creaks   the airframe flexing in rough air
##   belt     now and then a slipping fan belt squeals at start-up, louder
##            the more you rev it, for a few seconds (SQUEAL_SECONDS)
## main sets `host` and `kind` each frame to whatever you're driving or flying.

## How long the belt squeals after a cold start. Tune here.
const SQUEAL_SECONDS := 4.0
## Chance a start squeals: warm weather, and the cold of winter.
const SQUEAL_CHANCE := 0.08
const SQUEAL_CHANCE_COLD := 0.25
const DIR := "res://assets/sounds/rattle/"
## How loud the clunks, squeaks, rattles and creaks are (dB). Tune here.
const NOISE_DB := -12.0

var host: Node3D = null              # what you're in, or null on foot
var kind := ""                       # "truck", "machine" or "plane"

var _cache := {}
var _players: Array = []             # one-shots inside the cab
var _belt: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _last_host: Node3D = null
var _prev_pos := Vector3.ZERO
var _vy := 0.0                       # smoothed vertical speed
var _vy_prev := 0.0
var _basis_prev := Basis()
var _rough := 0.0                    # how rough the going is lately, 0..1
var _clunk_cool := 0.0
var _settle := 0.0             # seconds of quiet after a vehicle appears or is moved: it drops onto its spot
var _squeak_t := 1.0
var _rattle_t := 2.0
var _creak_t := 2.0
var _was_running := {}               # host id -> bool
var _squeal_t := 0.0
## Last jolt measured, m/s² (for tests and tuning).
var jolt := 0.0
## How many of each have played (tests).
var counts := {}


func _ready() -> void:
	_rng.randomize()
	for i in range(3):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_belt = AudioStreamPlayer.new()
	_belt.stream = _load("belt.wav", true)
	_belt.bus = "Engines" if AudioServer.get_bus_index("Engines") >= 0 else "Master"
	_belt.volume_db = -80.0
	add_child(_belt)


func _load(name: String, loop: bool = false) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var st: AudioStreamWAV = null
	if ResourceLoader.exists(DIR + name):
		st = load(DIR + name) as AudioStreamWAV
	if st == null:
		st = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(DIR + name))
	if st != null and loop:
		st = st.duplicate() as AudioStreamWAV
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_end = st.data.size() / 2
	_cache[name] = st
	return st


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	_clunk_cool = maxf(_clunk_cool - delta, 0.0)
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		_last_host = null
		_belt_step(delta, false, 0.0)
		return
	var xf := host.global_transform
	if host != _last_host:
		_last_host = host
		_prev_pos = xf.origin
		_vy = 0.0
		_vy_prev = 0.0
		_basis_prev = xf.basis
		_rough = 0.0
		_was_running[host.get_instance_id()] = _running()
		_settle = 2.5
		return
	var v := (xf.origin - _prev_pos) / delta
	_prev_pos = xf.origin
	if v.length() > 150.0:
		_settle = 2.5
		return                          # teleported
	if _settle > 0.0:
		# loading in, a respawn, a park: the drop onto the ground isn't a bump
		_settle -= delta
		_vy = v.y
		_vy_prev = v.y
		_basis_prev = xf.basis
		_rough = 0.0
		_was_running[host.get_instance_id()] = _running()
		return
	_vy = lerpf(_vy, v.y, clampf(delta / 0.03, 0.0, 1.0))
	var ay := (_vy - _vy_prev) / delta
	_vy_prev = _vy
	# how fast it's pitching and rolling about
	var dq := (_basis_prev.inverse() * xf.basis).get_euler()
	_basis_prev = xf.basis
	var turn := Vector2(dq.x, dq.z).length() / delta
	var speed := Vector2(v.x, v.z).length()
	var air: bool = kind == "plane" and host.get("on_ground") == false
	# expected: a plane in the air rides the bumps with smaller jolts
	jolt = absf(ay)
	var rough_now := clampf((jolt - 1.5) / 10.0 + turn * 0.4, 0.0, 1.0)
	_rough = lerpf(_rough, rough_now, clampf(delta * 1.5, 0.0, 1.0))
	var moving := clampf(speed / 6.0, 0.0, 1.0)
	if air:
		_air_noises(delta, jolt)
	else:
		# a hard knock: a clunk sized to it
		var knock := 7.0 if kind != "plane" else 6.0
		if jolt > knock and _clunk_cool <= 0.0 and speed > 0.8:
			_clunk_cool = 0.22
			_play("clunk_%d.wav" % (_rng.randi() % 4), clampf((jolt - knock) / 18.0, 0.15, 1.0) * 0.8, _rng.randf_range(0.85, 1.1))
		# squeaks: springs working over rough ground
		_squeak_t -= delta * (0.2 + 3.0 * _rough) * moving
		if _squeak_t <= 0.0:
			_squeak_t = _rng.randf_range(0.6, 2.2)
			if _rough > 0.08 and kind != "plane":
				_play("squeak_%d.wav" % (_rng.randi() % 4), clampf(0.08 + _rough * 0.3, 0.0, 0.3), _rng.randf_range(0.85, 1.2))
		# rattles: something loose in the back
		_rattle_t -= delta * (0.15 + 2.0 * _rough) * moving
		if _rattle_t <= 0.0:
			_rattle_t = _rng.randf_range(2.0, 6.0)
			if _rough > 0.12:
				pass   # rattles removed: the chatter sounded like frogs / animals (Dave)
	# the fan belt at start-up
	var id := host.get_instance_id()
	var run := _running()
	if run and not bool(_was_running.get(id, run)) and kind != "plane":
		var cold: bool = Game.season == Game.WINTER or Game.time_of_day < 7.0
		if _rng.randf() < (SQUEAL_CHANCE_COLD if cold else SQUEAL_CHANCE):
			_squeal_t = SQUEAL_SECONDS
	_was_running[id] = run
	_belt_step(delta, run, _throttle())


## Creaks and the odd bang in rough air.
func _air_noises(delta: float, j: float) -> void:
	_creak_t -= delta * (0.15 + 3.0 * _rough)
	if _creak_t <= 0.0:
		_creak_t = _rng.randf_range(1.0, 4.0)
		pass   # the airframe creak is gone: in rough air it croaked like a frog (Dave)
	# (No bang in rough air any more: with the new gusts it knocked in a
	# rhythm - Dave. The bumps are felt in the seat, the view and the pad.)


## Force a squeal now (console / tests).
func squeal() -> void:
	_squeal_t = SQUEAL_SECONDS


func squealing() -> bool:
	return _squeal_t > 0.0


func _belt_step(delta: float, run: bool, thr: float) -> void:
	if _squeal_t <= 0.0 or not run:
		_squeal_t = 0.0
		if _belt.playing:
			_belt.stop()
		return
	var elapsed := SQUEAL_SECONDS - _squeal_t
	_squeal_t -= delta
	if not _belt.playing:
		_belt.play()
	var attack := clampf(elapsed / 0.15, 0.0, 1.0)
	var fade := clampf(_squeal_t / minf(1.2, SQUEAL_SECONDS * 0.4), 0.0, 1.0)
	# more throttle: the belt slips harder and the pulley spins faster
	var amt := (0.25 + 0.75 * thr) * attack * fade
	_belt.volume_db = linear_to_db(maxf(amt * 0.45, 0.00001))
	_belt.pitch_scale = 0.88 + 0.3 * thr + 0.03 * sin(elapsed * 9.0)


func _running() -> bool:
	if host == null:
		return false
	var e = host.get("engine_on")
	if e != null:
		return bool(e)
	e = host.get("engine_running")
	if e != null:
		return bool(e)
	return true


func _throttle() -> float:
	var t = host.get("throttle_in")
	if t != null:
		return clampf(float(t), 0.0, 1.0)
	t = host.get("_in")
	if t is Vector2:
		return clampf((t as Vector2).y, 0.0, 1.0)
	t = host.get("throttle")
	if t != null:
		return clampf(float(t), 0.0, 1.0)
	return 0.0


func _play(name: String, vol: float, pitch: float) -> void:
	var s := _load(name)
	if s == null:
		return
	var k := name.get_slice("_", 0)
	counts[k] = int(counts.get(k, 0)) + 1
	var p: AudioStreamPlayer = null
	for c in _players:
		if not (c as AudioStreamPlayer).playing:
			p = c
			break
	if p == null:
		return
	p.stream = s
	p.volume_db = linear_to_db(maxf(vol, 0.00001)) + NOISE_DB
	p.pitch_scale = pitch
	p.play()
