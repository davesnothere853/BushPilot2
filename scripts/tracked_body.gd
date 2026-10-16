extends RefCounted
## A tracked machine as a real rigid body (DESIGN_NOTES 70): mass and inertia,
## road wheels along each track as spring-damper contacts on the ground, track
## drive with traction and slip, side friction (so pivot turns scrub like the
## real thing), weight transfer, pitching over a crest, and tipping over on a
## side-slope that's too steep. Our own physics (like plane.gd), reading the
## deformable ground through `ground_y(x, z)`.
##
## Body frame: origin at the bottom of the tracks, centre; -Z forward, +X right.

var mass := 8000.0
var length := 2.6            # track contact length
var width := 1.9             # track centres
var height := 2.2            # for inertia
var com := Vector3(0, 0.75, 0.1)   # centre of mass in the body frame
var wheels := 6              # contacts per track
var top_speed := 2.4         # m/s with full track speed
var mu := 0.75               # track grip (dirt/gravel); muskeg and mud lower it
var mu_side := 0.55          # sideways scrub
var drag := 0.0              # N resisting forward motion (a loaded blade)
var power := 60000.0         # W at the tracks: climbs and heavy pushes slow her down

var pos := Vector3.ZERO
var basis := Basis.IDENTITY
var vel := Vector3.ZERO
var angvel := Vector3.ZERO
var belt_l := 0.0            # track belt speeds now (m/s), for the track visuals
var belt_r := 0.0
var on_ground := 0           # contacts touching
var tilt_deg := 0.0          # how far over she is (roll or pitch, worst)

var ground_y: Callable       # func(x, z) -> float
var grip_at: Callable        # optional func(x, z) -> float multiplier on mu
var blocked: Callable        # optional func(p: Vector3) -> bool (buildings etc.)

var _k := 0.0
var _c := 0.0
var _contacts: Array[Vector3] = []
var _hull: Array = []
var last_hit := 0.0          # m/s the hull last struck the ground at
## Mud (DESIGN_NOTES 109): set once for every tracked machine (main.gd).
## Tracks spread the weight, so they float far better than tyres - but a
## heavy machine still sinks in the muskeg and can belly out.
static var mud_fn: Callable
static var rut_fn: Callable
static var wear_fn: Callable   # func(key, xf, gauge, shoe, length, turning, mass) - track marks (wear.gd)
var shoe := 0.5               # track shoe width, m
## A push on the machine from outside (DESIGN_NOTES 150): an excavator's
## bucket planted in the ground, levering it up or dragging it along; another
## machine's pull. World point and force (N); the owner sets it each frame.
var ext_point := Vector3.ZERO
var ext_force := Vector3.ZERO
var sink := 0.0                # how far the tracks are down in it, m
var mud_now := 0.0             # mean mud under the tracks 0..1
var spin_now := 0.0            # tracks slipping
var _cmud: Array[float] = []
var _rut_d := 0.0
var _stall_t := 0.0
const Hull = preload("res://scripts/hull.gd")


func setup() -> void:
	_hull = Hull.box_points(Vector3(0, height * 0.5 + 0.15, 0), Vector3(width * 0.5 + 0.1, height * 0.5 - 0.05, length * 0.5 + 0.45))
	_contacts.clear()
	for side in [-1.0, 1.0]:
		for i in range(wheels):
			var z := lerpf(-length * 0.5, length * 0.5, float(i) / float(wheels - 1))
			_contacts.append(Vector3(side * width * 0.5, 0.0, z))
	var n := float(_contacts.size())
	# springs: ~4 cm static sag, damped a bit under critical
	_k = mass * 9.81 / n / 0.04
	_c = 2.0 * sqrt(_k * mass / n) * 0.6


func place(xf: Transform3D) -> void:
	basis = xf.basis.orthonormalized()
	pos = xf.origin
	vel = Vector3.ZERO
	angvel = Vector3.ZERO


func transform() -> Transform3D:
	return Transform3D(basis, pos)


func yaw() -> float:
	var f := -basis.z
	return atan2(-f.x, -f.z)


## One physics step. `left` / `right`: track commands -1..1.
func step(dt: float, left: float, right: float) -> void:
	_mud_step(dt, left, right)
	var sub := 3
	var h := dt / float(sub)
	for _i in range(sub):
		_substep(h, left, right)
	if wear_fn.is_valid() and on_ground > 0 and (vel.length() > 0.05 or absf(left - right) > 0.3):
		wear_fn.call(str(get_instance_id()), transform(), width, shoe, length, clampf(absf(left - right) * 0.5, 0.0, 1.0), mass)


func _substep(dt: float, left: float, right: float) -> void:
	var c_world := pos + basis * com
	var force := Vector3(0, -9.81 * mass, 0)
	var torque := Vector3.ZERO
	var fwd := -basis.z
	var side := basis.x
	on_ground = 0
	# commanded belt speeds ease toward the levers (hydrostatic drive)
	belt_l = move_toward(belt_l, left * top_speed, 3.0 * dt)
	belt_r = move_toward(belt_r, right * top_speed, 3.0 * dt)
	var per_wheel_m := mass / float(_contacts.size())
	var pts: Array = []          # [r, normal force vec, traction vec, side vec]
	var trac_power := 0.0
	for ci in range(_contacts.size()):
		var lc: Vector3 = _contacts[ci]
		var p := pos + basis * lc
		var cm: float = _cmud[ci] if ci < _cmud.size() else 0.0
		var gy: float = ground_y.call(p.x, p.z) - sink * clampf(cm * 1.5, 0.0, 1.0)
		var pen := gy - p.y
		if pen <= 0.0:
			continue
		on_ground += 1
		var r := p - c_world
		var vp := vel + angvel.cross(r)
		# the ground's own slope under this wheel
		var e := 0.3
		var n := Vector3(float(ground_y.call(p.x - e, p.z)) - float(ground_y.call(p.x + e, p.z)), 2.0 * e,
			float(ground_y.call(p.x, p.z - e)) - float(ground_y.call(p.x, p.z + e))).normalized()
		var depth := pen * n.y
		var fn := maxf(_k * minf(depth, 0.25) - _c * vp.dot(n), 0.0)   # capped: a buried wheel can't launch her
		var g := mu * (float(grip_at.call(p.x, p.z)) if grip_at.is_valid() else 1.0)
		g *= lerpf(1.0, 0.5, cm)
		# track along the ground: drive / brake toward the belt speed
		var t := (fwd - n * fwd.dot(n)).normalized()
		var s := (side - n * side.dot(n)).normalized()
		var belt := belt_l if lc.x < 0.0 else belt_r
		var vt := vp.dot(t)
		var slip := belt - vt
		var ft := clampf(slip * per_wheel_m * 6.0, -g * fn, g * fn)
		var fl := clampf(-vp.dot(s) * per_wheel_m * 8.0, -mu_side * fn, mu_side * fn)
		if ft * vt > 0.0:
			trac_power += ft * vt
		if cm > 0.05:
			# the mud piles up in front of the grousers
			var dragm := fn * (0.03 + 0.15 * cm) * clampf(0.6 + sink / 0.3, 0.6, 1.5)
			ft -= signf(vt) * minf(dragm, absf(vt) * per_wheel_m / dt * 0.5)
		pts.append([r, n * fn, t * ft, s * fl])
	# The engine only has so much: pulling power over the limit scales drive back.
	var pk := 1.0
	if trac_power > power:
		pk = power / trac_power
	for e in pts:
		var f: Vector3 = e[1] + (e[2] as Vector3) * pk + e[3]
		force += f
		torque += (e[0] as Vector3).cross(f)
	if ext_force != Vector3.ZERO:
		force += ext_force
		torque += (ext_point - c_world).cross(ext_force)
	if drag > 0.0 and on_ground > 0:
		var vf := vel.dot(fwd)
		force -= fwd * clampf(vf * 4.0, -1.0, 1.0) * drag
	# integrate (inertia of a box about the centre of mass, in the body frame)
	var ixx := mass * (height * height + length * length) / 12.0
	var iyy := mass * (width * width + length * length) / 12.0
	var izz := mass * (width * width + height * height) / 12.0
	var tb := basis.inverse() * torque
	var ab := Vector3(tb.x / ixx, tb.y / iyy, tb.z / izz)
	angvel += (basis * ab) * dt
	angvel *= 1.0 - 0.6 * dt
	vel += force / mass * dt
	var new_pos := pos + vel * dt
	if blocked.is_valid() and blocked.call(new_pos + fwd * signf(vel.dot(fwd)) * (length * 0.5 + 0.4) + Vector3(0, 0.6, 0)):
		vel = Vector3(0, vel.y, 0)       # hit a wall: stop dead
		new_pos = pos + vel * dt
	pos = new_pos
	if angvel.length() > 1.0e-5:
		basis = Basis(angvel.normalized(), angvel.length() * dt) * basis
	basis = basis.orthonormalized()
	var res: Array = Hull.resolve(pos, basis, vel, angvel, _hull, ground_y)
	pos = res[0]
	basis = res[1]
	vel = res[2]
	angvel = res[3]
	if float(res[4]) > 0.0:
		last_hit = float(res[4])
	var up := basis.y
	tilt_deg = rad_to_deg(acos(clampf(up.y, -1.0, 1.0)))


## Settle onto the ground before the first step (no drop-in bounce).
func settle() -> void:
	for i in range(240):
		step(1.0 / 120.0, 0.0, 0.0)
	vel = Vector3.ZERO
	angvel = Vector3.ZERO


func _mud_step(dt: float, left: float, right: float) -> void:
	var nc := _contacts.size()
	if _cmud.size() != nc:
		_cmud.resize(nc)
		_cmud.fill(0.0)
	var tot := 0.0
	for ci in range(nc):
		var p := pos + basis * _contacts[ci]
		var m: float = mud_fn.call(p.x, p.z) if mud_fn.is_valid() else 0.0
		_cmud[ci] = m
		tot += m
	mud_now = tot / maxf(float(nc), 1.0)
	var fwdv := vel.dot(-basis.z)
	var cmd := maxf(absf(left), absf(right)) * top_speed
	var stalled := cmd > 0.5 and absf(fwdv) < cmd * 0.25 and mud_now > 0.15
	_stall_t = _stall_t + dt if stalled else 0.0
	var slipping := _stall_t > 1.0
	spin_now = lerpf(spin_now, 1.0 if slipping else 0.0, clampf(5.0 * dt, 0.0, 1.0))
	var want := mud_now * mud_now * (0.10 + 0.03 * clampf(mass / 10000.0, 0.0, 4.0))
	if slipping:
		sink += (0.04 + 0.1 * mud_now) * dt
	elif sink > want:
		sink = move_toward(sink, want, (0.02 + 0.05 * clampf(absf(fwdv) / 1.5, 0.0, 1.0)) * dt)
	else:
		sink = move_toward(sink, want, 0.15 * dt)
	sink = clampf(sink, 0.0, 0.5)
	if mud_now > 0.2 and rut_fn.is_valid():
		_rut_d += maxf(absf(fwdv), 1.5 if slipping else 0.0) * dt
		if _rut_d > 1.0:
			_rut_d = 0.0
			for sd in [-1.0, 1.0]:
				var tp := pos + basis * Vector3(sd * width * 0.5, 0.0, 0.0)
				rut_fn.call(Vector3(tp.x, float(ground_y.call(tp.x, tp.z)), tp.z), 0.55, (0.012 + 0.025 * mud_now) * clampf(mass / 12000.0, 0.5, 2.5))
