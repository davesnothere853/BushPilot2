extends Node3D
## A machine's diesel, felt from outside (Dave: lights, noises, exhaust, and
## start-up effects, especially cold): the starter grinds, it catches with a
## black puff, coughs and runs rough with white smoke while it's cold, then
## settles as it warms. The stack smokes with the load - a dark cloud when the
## hydraulics dig in, a faint haze at idle - and the rain cap flaps. The sound
## is the game's EngineSound ("machine": deep diesel + hydraulic whine).
## Sits on the machine at the top of its exhaust stack.

const EngineSound = preload("res://scripts/engine_sound.gd")
const MeshKit = preload("res://scripts/meshkit.gd")

var idle_rpm := 750.0
var rated_rpm := 2000.0
var load := 0.0                    # 0..1, set by the machine (hydraulic pressure / relief)
var throttle := 0.0                # a hand-throttle floor, 0 = idle (normally left at idle)
var strain := 0.0                  # 0..1, set by the machine: the hydraulics can't move their load
var drive_strain := 0.0            # 0..1, set by the machine: the tracks/wheels can't make the speed asked
var _thr := 0.0
var _soot := 0.0                   # black from a rev-up: the fuel arrives before the turbo's air
var temp := 5.0                    # coolant, C: a cold morning
var ambient := 5.0
var rpm := 0.0
var state := "off"                 # off, cranking, running
var stack_dir := Vector3.UP
var cap: Node3D                    # the rain cap to flap (optional)
var _t := 0.0
var _crank_t := 0.0
var _smoke: CPUParticles3D

var _sound: Node3D
var _fails := 0                    # winter: cranks that don't catch before it fires
var _pause_t := 0.0
var _cold := false                 # a frozen-morning start, run to the real recording's timeline
var _cold_t := 0.0
const COLD_FIRE := 14.3            # in that recording: grinding, coughs 8.0-12.1 s, grinds again, fires at 14.3 s
var _coughs := 0                   # failed tries so far (the sound plays a cough on each)
var _puff_t := 0.0
var _puff_gap := 0.0               # time till another puff may come
var _after_t := 0.0                # after it catches: random puffs while it settles                 # the puff shows only while its burst is in the air
var _rich_t := 0.0                 # after a hard start: rich and black for a while


func _ready() -> void:
	# no particle emitter on the machine at all (one drew a black disc on the
	# stack): the old smoke settings live on a node that's never in the scene,
	# the start-up smoke is _smoke_puff's hand-moved blobs
	_smoke = CPUParticles3D.new()
	_smoke.color_ramp = Gradient.new()
	# (no separate puff emitter: a parked one-shot drew a black disc on the stack.
	# A puff is the main smoke going thick and black for a moment: _soot.)
	_sound = EngineSound.new()
	_sound.name = "EngineSound"
	_sound.kind = "machine"
	_sound.state = func() -> Dictionary: return {"rpm": rpm, "running": state == "running", "cranking": state == "cranking" and not _cold, "cold_start": _cold, "coughs": _coughs, "load": load}   # the real recordings: starter, coughs, catch, idle
	add_child(_sound)


func _make_smoke(n: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 18.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0.6, 0.5, 0.2)          # rises, drifts off downwind
	p.damping_min = 0.8
	p.damping_max = 1.2
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.25))           # small at the stack's mouth
	curve.add_point(Vector2(1, 3.0))            # spreads as it rises
	p.scale_amount_curve = curve
	# soft round puffs that always face the camera (not hard balls)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# a soft round puff: full in the middle, fading smoothly to nothing at the edge
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for py in range(64):
		for px in range(64):
			var r := Vector2(px - 31.5, py - 31.5).length() / 31.5
			var al := clampf(1.0 - r, 0.0, 1.0)
			img.set_pixel(px, py, Color(1, 1, 1, al * al * (3.0 - 2.0 * al) * 0.8))
	var soft := ImageTexture.create_from_image(img)
	m.albedo_texture = soft
	qm.material = m
	p.mesh = qm
	p.angle_min = 0.0
	p.angle_max = 360.0
	var g := Gradient.new()
	g.set_color(0, Color(0.15, 0.15, 0.15, 0.5))
	g.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	p.color_ramp = g
	add_child(p)
	return p


## Turn the key: the starter grinds (longer when it's cold), then it catches.
func start() -> String:
	if state != "off":
		return "running"
	state = "cranking"
	_crank_t = 1.2 + clampf((20.0 - temp) / 20.0, 0.0, 1.0) * 1.6
	# a hard start in the winter (Dave): below freezing it takes a few tries
	_fails = 0 if temp > 5.0 else (2 if temp > -10.0 else 3)
	if temp <= 5.0:
		# frozen: follow the real cold start (the sound plays it in one piece)
		_cold = true
		_cold_t = 0.0
		_fails = 0
		_crank_t = COLD_FIRE
	return "cranking"


func stop() -> void:
	state = "off"


func _process(dt: float) -> void:
	_t += dt
	_blobs_step(dt)
	_puff_gap -= dt
	if _after_t > 0.0:
		_after_t -= dt
		if _puff_gap <= 0.0 and randf() < dt * 5.0:
			var k := clampf(_after_t / 8.0, 0.0, 1.0)
			_smoke_puff(randf_range(0.5, 1.0) * (0.35 + 0.65 * k), 0.25 * k)
			_puff_gap = 0.18
	var cold := clampf((60.0 - temp) / 55.0, 0.0, 1.0)        # 1 stone cold .. 0 warm
	match state:
		"off":
			rpm = move_toward(rpm, 0.0, dt * 900.0)
			temp = move_toward(temp, ambient, dt * 0.05)
			_smoke.emitting = false
		"cranking":
			_crank_t -= dt
			rpm = 180.0 + sin(_t * 40.0) * 30.0
			if _cold:
				_cold_t += dt
				if _puff_gap <= 0.0 and _cold_t > 1.0:
					_smoke_puff(randf_range(0.25, 0.45), 0.85)            # cranking, not burning: raw fuel fog out the stack
					_puff_gap = 0.28
				if _cold_t > 8.0 and _cold_t < 12.1:
					rpm = 180.0 + maxf(0.0, sin(_cold_t * 6.0)) * 380.0      # the coughs: a cylinder or two fire and it dies back
					if sin(_cold_t * 6.0) > 0.85 and _puff_gap <= 0.0 and randf() < 0.6:
						_smoke_puff(randf_range(0.6, 0.9), 0.35)                 # a cough: half burnt, a thick grey puff
						_puff_gap = 0.6
			_smoke.emitting = false          # unburnt fuel: wisps of white as it tries
			_tint(Color(0.55, 0.56, 0.58, 0.35), cold)
			if _crank_t <= 0.0 and _fails > 0:
				# it fires on a cylinder or two and dies: a grey-black cough, rest the starter
				_fails -= 1
				_coughs += 1
				state = "pause"
				_pause_t = 1.6
				_smoke_puff(0.8, 0.4)                # it fired on a cylinder or two: a thick puff
			elif _crank_t <= 0.0:
				state = "running"
				_cold = false
				_rich_t = 6.0 * clampf((10.0 - temp) / 25.0, 0.2, 1.0) if temp < 10.0 else 0.0
				rpm = idle_rpm * 1.6                                    # catches and flares
				_smoke_puff(1.0, 0.15)               # it catches: a huge rolling cloud
				_smoke_puff(1.0, 0.45)
				_after_t = 8.0                 # and heavy puffs while it runs rough, thinning as it settles
		"pause":
			rpm = move_toward(rpm, 0.0, dt * 600.0)
			_smoke.emitting = false
			_pause_t -= dt
			if _pause_t <= 0.0:
				state = "cranking"
				_crank_t = 1.4
		"running":
			# Dave: the rpm only comes up when it can't move the load. It idles while
			# the work goes easily; when a ram is straining near the relief or
			# stalled, or the tracks can't make the speed asked (a heavy push, a
			# climb), the governor brings it up - and it blows black doing it - then
			# settles back to idle once the load moves or the lever comes back.
			var was_thr := _thr
			var thr_want := clampf(maxf(throttle, 0.25 * maxf(strain, drive_strain)), 0.0, 1.0)   # the operator's throttle does it; the governor only helps a little
			_thr = move_toward(_thr, thr_want, dt * (0.9 if thr_want > _thr else 0.45))
			if thr_want > 0.5 and was_thr < 0.08 and _thr >= 0.08:
				_soot = 1.0                    # a black puff out of the stack
			var want := lerpf(idle_rpm * (1.0 + cold * 0.15), rated_rpm, _thr)
			want -= rated_rpm * 0.05 * load                              # governor droop under load
			want += sin(_t * 5.0) * 12.0 * cold                          # just a little uneven while cold
			var accel := want - rpm
			rpm = lerpf(rpm, want, clampf(dt * (1.5 if accel > 0.0 else 1.0), 0.0, 1.0))
			# a diesel blows black while it's climbing (more fuel than air) and while it's lugging
			_soot = maxf(_soot - dt * 0.8, clampf(accel / rated_rpm * 4.0, 0.0, 1.0))
			temp = minf(temp + dt * (0.35 + load * 0.6), 85.0)       # warms (quicker under load); the lab speeds it up
			_smoke.emitting = false
			# the smoke: white and thick while cold, dark under load, a haze when warm and idle
			var dark := maxf(clampf(load * 1.2, 0.0, 1.0), _soot)
			if _rich_t > 0.0:                                      # just caught on a frozen morning: a black cloud
				_rich_t -= dt
				dark = maxf(dark, clampf(_rich_t / 3.0, 0.0, 1.0))
				cold = minf(cold, 0.3)
			# an old diesel (Dave: black smoke): a sooty grey at idle, grey-blue and
			# heavier while cold, thick black under load and when the throttle opens
			var col := Color(0.12, 0.12, 0.13, 0.4 + cold * 0.2).lerp(Color(0.02, 0.02, 0.02, 0.9), clampf(dark * 1.3, 0.0, 1.0))
			# (the amount never changes while it runs: changing it restarts the emitter
			# and every particle drops back onto the stack at once - the black circle)
			_tint(col, cold)
			_smoke.initial_velocity_min = 1.2 + rpm / rated_rpm * 2.5
			_smoke.initial_velocity_max = 2.0 + rpm / rated_rpm * 3.5
	_flap_step(dt)


## One puff of smoke out of the stack (Dave: only on the start, while it's
## firing). A fresh burst every time that frees itself when it's blown away, so
## nothing is ever left parked on the stack (that was the black circle).
func _smoke_puff(strength: float, raw: float = 0.0) -> void:
	_flap_v += 6.0 + 10.0 * strength * (1.0 - raw * 0.6)      # each cough/catch kicks the rain cap up
	# raw: 0 half-burnt (dark grey) .. 1 unburnt fuel (whitish grey). Plain soft
	# blobs moved by hand (no particle emitter - an emitter drew a black disc on
	# the stack). From the real cold starts: a dense cloud that rolls out,
	# spreads wide, hangs low and drifts off slowly.
	var c0 := Color(0.30, 0.30, 0.31).lerp(Color(0.74, 0.74, 0.75), raw)
	var n := int(3 + 6 * strength)
	for i in range(n):
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE
		qm.material = _blob_mat()
		q.mesh = qm
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.top_level = true
		add_child(q)
		q.global_position = global_position + Vector3(randf_range(-0.05, 0.05), randf_range(0.0, 0.1), randf_range(-0.05, 0.05))
		var v := Vector3(randf_range(-0.5, 0.5), randf_range(0.8, 1.6) * (0.6 + strength), randf_range(-0.5, 0.5))
		var life := randf_range(3.0, 5.0) * (0.7 + strength * 0.5)
		var col := Color(c0.r + randf_range(-0.04, 0.04), c0.g, c0.b, 0.0)
		_blobs.append({"n": q, "v": v, "age": 0.0, "life": life, "s0": 0.3 + 0.3 * strength, "s1": 2.5 + 3.0 * strength, "a": 0.45 + 0.35 * strength, "c": col})


var _blobs: Array = []
static var _blob_tex: ImageTexture


## The soft round blob's material (each blob gets its own for its colour and fade).
func _blob_mat() -> StandardMaterial3D:
	if _blob_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for py in range(64):
			for px in range(64):
				var r := Vector2(px - 31.5, py - 31.5).length() / 31.5
				var al := clampf(1.0 - r, 0.0, 1.0)
				img.set_pixel(px, py, Color(1, 1, 1, al * al * (3.0 - 2.0 * al)))
		_blob_tex = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _blob_tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = Color(0, 0, 0, 0)          # invisible until its first update
	return m


## Move, grow and fade the smoke blobs; free the ones that have drifted away.
func _blobs_step(dt: float) -> void:
	var i := 0
	while i < _blobs.size():
		var b: Dictionary = _blobs[i]
		var q: MeshInstance3D = b["n"]
		b["age"] = float(b["age"]) + dt
		var t: float = float(b["age"]) / float(b["life"])
		if t >= 1.0 or not is_instance_valid(q):
			if is_instance_valid(q):
				q.queue_free()
			_blobs.remove_at(i)
			continue
		var v: Vector3 = b["v"]
		v = v * (1.0 - clampf(dt * 1.3, 0.0, 1.0)) + Vector3(0.35, 0.12, 0.15) * dt     # slows, hangs, drifts downwind
		b["v"] = v
		q.global_position += v * dt
		var sc := lerpf(float(b["s0"]), float(b["s1"]), sqrt(t))
		q.scale = Vector3.ONE * sc
		var c: Color = b["c"]
		c.a = float(b["a"]) * clampf(t * 8.0, 0.0, 1.0) * (1.0 - t) * (1.0 - t)
		((q.mesh as QuadMesh).material as StandardMaterial3D).albedo_color = c
		i += 1

## The stack's rain cap (Dave: a working tractor flap): a round lid on a hinge
## at the back of the stack. Off, it lies shut; the exhaust blows it open - a
## flutter at idle with the firing pulses, wide open as the revs come up - each
## cough and the catch kick it up, and it slaps shut when the engine stops.
var _flap: Node3D
var _flap_a := 0.0                 # how far open (rad)
var _flap_v := 0.0
func make_cap(r: float) -> void:
	var lug := MeshKit.new()
	for sx in [-1.0, 1.0]:
		lug.box_at(Vector3(float(sx) * r * 0.45, -0.012, r + 0.008), Vector3(0.008, 0.03, 0.02), Color(0.12, 0.11, 0.1))   # hinge ears on the stack
	add_child(lug.instance("CapHinge"))
	_flap = Node3D.new()
	_flap.name = "RainCap"
	_flap.position = Vector3(0, 0.004, r + 0.008)             # the hinge pin, at the back edge
	var k := MeshKit.new()
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.003, -r - 0.008)), r * 1.15, r * 1.15, 0.006, 16, Color(0.16, 0.14, 0.12), true)   # the lid
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(r * 0.4, 0, 0)), 0.007, 0.007, r * 0.8, 6, Color(0.2, 0.2, 0.2), true)     # its knuckle round the pin
	k.box_at(Vector3(0, 0.006, -0.01), Vector3(r * 0.5, 0.008, 0.02), Color(0.16, 0.14, 0.12))      # the strap from the knuckle onto the lid
	_flap.add_child(k.instance("Lid"))
	add_child(_flap)


func _flap_step(dt: float) -> void:
	if _flap == null:
		return
	var want := 0.0
	if state == "running":
		var f := clampf((rpm - idle_rpm * 0.8) / (rated_rpm - idle_rpm), 0.0, 1.0)
		want = 0.45 + 0.75 * f + 0.25 * load
		want += sin(_t * rpm / 60.0 * 3.0 * TAU * 0.25) * 0.06 * (1.0 - f * 0.6)     # the firing pulses make it chatter
	elif state == "cranking":
		want = 0.06 + maxf(0.0, sin(_t * 9.0)) * 0.05                           # just the starter's pumping air
	# a light lid on a hinge: pushed toward the exhaust's angle, gravity drops it
	var acc := (want - _flap_a) * 140.0 - _flap_v * 14.0
	_flap_v += acc * dt
	_flap_a += _flap_v * dt
	if _flap_a < 0.0:                       # slaps shut on the stack's rim
		_flap_a = 0.0
		_flap_v = -_flap_v * 0.25
	_flap_a = minf(_flap_a, 1.45)
	_flap.rotation.x = _flap_a


func _tint(c: Color, _cold: float) -> void:
	var g: Gradient = _smoke.color_ramp
	g.set_color(0, c)
	g.set_color(1, Color(c.r + 0.08, c.g + 0.08, c.b + 0.08, 0.0))



## What the engine can give the hydraulic pump at its revs now, W: a diesel's
## torque is flat-ish, so its power climbs with rpm - little at idle (Dave:
## throttle up to lift the bucket), full near the rated revs.
var hyd_power_max := 70000.0
func hyd_power() -> float:
	if state != "running":
		return 0.001
	var f := clampf(rpm / rated_rpm, 0.0, 1.1)
	var torque := clampf(0.7 + 0.5 * f - 0.25 * f * f, 0.0, 1.0)
	return hyd_power_max * f * torque


func status() -> String:
	return "%s  %d rpm  %d C%s%s" % [state.to_upper(), int(rpm), int(temp), "  (cold)" if temp < 40.0 else "", "  LUGGING" if maxf(strain, drive_strain) > 0.3 else ""]


## How much the travel is failing: the operator asks for cmd (0..1) of the top
## speed and she only makes `actual` m/s.
static func travel_strain(cmd: float, top: float, actual: float) -> float:
	var want := absf(cmd) * top
	if want < 0.05:
		return 0.0
	return clampf((want - absf(actual)) / want * 1.4 - 0.2, 0.0, 1.0)
