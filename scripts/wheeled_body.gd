extends RefCounted
## A wheeled vehicle as a rigid body (DESIGN_NOTES 70): sprung wheels as
## spring-damper contacts on the deformable ground, steering on the front
## axle, drive on the rear axles, tyre grip that saturates (it slides when you
## ask too much), brakes, engine power, and the load it carries (a water tank
## that fills changes its weight and handling).
##
## Body frame: origin on the ground under the middle of the wheelbase,
## -Z forward, +X right, +Y up.

var mass_empty := 9000.0
var load_kg := 0.0
var load_com := Vector3(0, 1.6, 0.8)    # where the load sits (tank centre)
var com := Vector3(0, 0.95, 0.0)        # empty chassis centre of mass
var size := Vector3(2.5, 3.0, 8.5)      # for inertia
var wheel_r := 0.52
var wheels: Array = []                  # [Vector3 hub (body), steer bool, drive bool]
var travel := 0.25                      # suspension stroke
var spring_mul := 1.0                   # stiffer (>1) or softer springs than the load needs
var power := 180000.0                   # W
var top_speed := 22.0                   # m/s
var brake_force := 60000.0              # N total
var mu := 0.9
var max_steer := 0.6                    # rad

var pos := Vector3.ZERO
var basis := Basis.IDENTITY
var vel := Vector3.ZERO
var angvel := Vector3.ZERO
var steer := 0.0
var wheel_spin: Array[float] = []       # wheel roll angles for the visuals
var compress: Array[float] = []         # suspension compression 0..1 per wheel
var on_ground := 0
var tilt_deg := 0.0
var speed := 0.0

var ground_y: Callable                  # func(x, z) -> float
## Outside pulls (DESIGN_NOTES 203: winch cables, tow straps): forces (N) at
## world points, summed into the next step with the wheels' own; cleared after.
var ext_pulls: Array = []                # [[force: Vector3, at_world: Vector3], ...]
var blocked: Callable                   # optional func(p: Vector3) -> bool

var _k := 0.0
var _c := 0.0
var _hull: Array = []
var last_hit := 0.0          # m/s the body last struck the ground at
## Mud (DESIGN_NOTES 109). `mud_fn` (x, z) -> 0..1 and `rut_fn` (point, radius,
## depth) are set once for every wheeled thing (main.gd -> ground.gd).
static var mud_fn: Callable
static var rut_fn: Callable
static var tyre_fn: Callable    # func(at, fwd, width, strength) - tyre marks (wear.gd, DESIGN_NOTES 150)
var tyre_w := 0.3               # tread width for the marks
var _mark_d: Array[float] = []
var sink: Array[float] = []          # how far each wheel has sunk in, m
var wheel_mud: Array[float] = []     # the mud under each wheel, 0..1
var slipping: Array[bool] = []       # spinning in the mud
var mud_now := 0.0                   # mean mud under the wheels (for sound, spray, muck)
var spin_now := 0.0                  # 0..1 how hard the wheels are spinning
var _rut_dist: Array[float] = []
var _dir := 0.0                      # which way it's been going (+1 fwd, -1 back)
var _dir_dist := 0.0                 # how far, recently: rocking back over your own packed ruts is easier
var _own_track := false
const Hull = preload("res://scripts/hull.gd")
## Differentials (DESIGN_NOTES 115). An open diff sends the same push to both
## wheels on an axle, so the wheel with the least grip (in the air, on slick
## mud) sets what the pair can do: it spins and the other barely pulls. A
## locked axle drives both wheels whatever. Between the axles: `lock_inter`
## (a part-time 4WD transfer case is locked; a 6x6's inter-axle diff isn't
## until you lock it). An auto locker is locked going straight and lets go to
## turn on firm ground.
var lock_front := false
var lock_rear := false
var auto_front := false
var auto_rear := false
var lock_inter := true
static var force_lock := false        # tests: every diff locked
## An open diff isn't perfectly open: its own friction lets the wheel with
## grip take about this many times what the spinning one gets.
const DIFF_BIAS := 1.5
## Grip left in the worst mud (x the dry grip).
const MUD_GRIP := 0.45
## Tandem axles on walking beams: [wheel, wheel] pairs on the same side that
## share their load. How far a bogie tyre can droop into a hole and still touch.
var bogies: Array = []
const BOGIE_DROOP := 0.2


func _on_bogie(wi: int) -> bool:
	for bp in bogies:
		if (bp as Array).has(wi):
			return true
	return false
var _gcap: Array[float] = []
static var debug := false            # tests: record every wheel for dump()
var _dbg: Array = []                 # per wheel, last substep (tests)         # each wheel's grip lately, N (smoothed)


func setup() -> void:
	var clear := wheel_r + 0.15
	_hull = Hull.box_points(Vector3(0, (clear + size.y) * 0.5, 0), Vector3(size.x * 0.5, (size.y - clear) * 0.5, size.z * 0.5))
	if not hull_shape.is_empty():
		_hull = _shaped_hull(clear)
	wheel_spin.resize(wheels.size())
	compress.resize(wheels.size())
	_gcap.resize(wheels.size())
	_gcap.fill(mass() * 9.81 / maxf(float(wheels.size()), 1.0) * mu)
	_recompute_springs()


## The body's real outline in sections along its length (DESIGN_NOTES 206):
## [z0, z1, half width low, top y, half width at the top]. A pickup is a low
## hood, a tall cab and a low bed - rolled over it lands on the cab roof and
## the bed rails, not on a box as tall as the cab all the way back.
var hull_shape: Array = []


func _shaped_hull(clear: float) -> Array:
	var out: Array = []
	for sec in hull_shape:
		var z0: float = sec[0]
		var z1: float = sec[1]
		var hw: float = sec[2]
		var top: float = sec[3]
		var hwt: float = sec[4]
		var zs := [z0, z1]
		if z1 - z0 > 1.2:
			zs.append((z0 + z1) * 0.5)
		for z in zs:
			for x in [-1.0, 1.0]:
				out.append(Vector3(x * hw, clear, z))
				out.append(Vector3(x * hw, (clear + top) * 0.5, z))
				out.append(Vector3(x * hwt, top, z))
			out.append(Vector3(0, top, z))
	return out


func _recompute_springs() -> void:
	var m := mass()
	var n := float(wheels.size())
	_k = m * 9.81 / n / (travel * 0.45) * spring_mul      # sits a little under half its stroke
	_c = 2.0 * sqrt(_k * m / n) * 0.45


func mass() -> float:
	return mass_empty + load_kg


func centre() -> Vector3:
	var m := mass()
	return (com * mass_empty + load_com * load_kg) / m


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


## What every wheel is doing (tests and tuning).
func dump() -> String:
	var out := "speed %.2f tilt %.1f pitch %.1f mass %.0f\n" % [speed, tilt_deg, rad_to_deg(asin(clampf(-basis.z.y, -1.0, 1.0))), mass()]
	for wi in range(_dbg.size()):
		var d = _dbg[wi]
		if d == null:
			out += "  w%d in the air\n" % wi
			continue
		var tt: Vector3 = d[9]
		out += "  w%d fn %6.0f grip %6.0f push %6.0f fl %6.0f drag %6.0f slopeF %6.0f mud %.2f sink %.2f vt %.2f\n" % [wi, d[0], d[1], d[2], d[3], d[4], -9.81 * mass() / float(wheels.size()) * tt.y, d[6], d[7], d[8]]
	var lo := 9.0
	for lc in _hull:
		var p: Vector3 = pos + basis * (lc as Vector3)
		lo = minf(lo, p.y - float(ground_y.call(p.x, p.z)))
	out += "  hull clearance %.2f m" % lo
	return out


## How the engine's push is shared out between the driven wheels, through
## the diffs. Returns a push per wheel (N).
func _split_drive(total: float, n_drive: int, steer_in: float) -> Array:
	var out: Array = []
	out.resize(wheels.size())
	out.fill(0.0)
	if n_drive <= 0 or total == 0.0:
		return out
	var per := total / float(n_drive)
	var sg := signf(total)
	# the driven wheels, by axle
	var axles := {}
	for wi in range(wheels.size()):
		var wv: Array = wheels[wi]
		if bool(wv[2]):
			var key := int(round(float((wv[0] as Vector3).z) * 10.0))
			if not axles.has(key):
				axles[key] = []
			(axles[key] as Array).append(wi)
	var turning := absf(steer_in) > 0.25
	var cap_of := func(wi: int) -> float: return _gcap[wi] if wi < _gcap.size() else 1.0e9
	# what each axle can put down, per wheel
	var axle_per := {}
	var weakest := 1.0e12
	for key in axles.keys():
		var ws: Array = axles[key]
		var front: bool = bool(wheels[ws[0]][1])
		var locked: bool = lock_front if front else lock_rear
		var auto: bool = auto_front if front else auto_rear
		var firm := true
		for wi in ws:
			if wi < wheel_mud.size() and wheel_mud[wi] > 0.3:
				firm = false
		if auto and not (turning and firm):
			locked = true
		if force_lock:
			locked = true
		var lo := 1.0e12
		var sum := 0.0
		for wi in ws:
			lo = minf(lo, cap_of.call(wi))
			sum += cap_of.call(wi)
		var can := (sum if locked or ws.size() < 2 else lo * ws.size()) / float(ws.size())
		axle_per[key] = [can, locked, lo]
		weakest = minf(weakest, can)
	for key in axles.keys():
		var ws: Array = axles[key]
		var info: Array = axle_per[key]
		# an open inter-axle diff: every axle gets the same push, so the
		# weakest one sets it for all of them
		var lim: float = weakest if not (lock_inter or force_lock) else float(info[0])
		for wi in ws:
			if bool(info[1]) or ws.size() < 2:
				out[wi] = per if (lock_inter or force_lock) else sg * minf(absf(per), maxf(lim * 1.05, 0.0))
			else:
				# open: the one with least grip spins; the other gets only that much
				var mine: float = cap_of.call(wi)
				if mine <= float(info[2]) * 1.0001:
					out[wi] = per
				else:
					out[wi] = sg * minf(absf(per), minf(float(info[2]) * DIFF_BIAS, lim))
	return out


## throttle -1..1 (negative: brake, then reverse once stopped), steer_in -1..1.
func step(dt: float, throttle: float, steer_in: float, handbrake: bool = false) -> void:
	_recompute_springs()
	_mud_step(dt, throttle)
	var sub := 4
	for _i in range(sub):
		_substep(dt / float(sub), throttle, steer_in, handbrake)
	ext_pulls.clear()


## A pull on the body this step (winch, strap): force N at a world point.
func pull(force: Vector3, at_world: Vector3) -> void:
	ext_pulls.append([force, at_world])


func _substep(dt: float, throttle: float, steer_in: float, handbrake: bool) -> void:
	var m := mass()
	# steering eases in, and less of it at speed
	var lim := max_steer / (1.0 + absf(speed) * 0.08)
	steer = move_toward(steer, -steer_in * lim, 1.6 * dt)
	var cw := pos + basis * centre()
	var force := Vector3(0, -9.81 * m, 0)
	var torque := Vector3.ZERO
	for pl in ext_pulls:
		force += pl[0]
		torque += ((pl[1] as Vector3) - cw).cross(pl[0])
	var fwd := -basis.z
	speed = vel.dot(fwd)
	on_ground = 0
	var n_drive := 0
	for wv in wheels:
		if bool(wv[2]):
			n_drive += 1
	# what the engine can give at this speed (or the brakes)
	var drive_total := 0.0
	var braking := 0.0
	if throttle > 0.05:
		if speed < -0.3:
			braking = throttle
		else:
			drive_total = throttle * minf(power / maxf(absf(speed), 2.0), m * 6.0)
			if speed > top_speed:
				drive_total = 0.0
	elif throttle < -0.05:
		if speed > 0.3:
			braking = -throttle
		else:
			drive_total = throttle * minf(power * 0.4 / maxf(absf(speed), 2.0), m * 3.0)   # reverse gear
			if speed < -4.0:
				drive_total = 0.0
	if handbrake:
		braking = 1.0
	var push := _split_drive(drive_total, n_drive, steer_in)
	# Pass 1: where each tyre meets the ground and how hard it's pressed.
	# The truck settles into mud as a whole (the mean sink), with only a part
	# of each tyre's own sink on top - so a tyre that's dug in still carries
	# its share of the weight, as a real one does.
	var mean_sink := 0.0
	for wi in range(mini(sink.size(), wheels.size())):
		mean_sink += sink[wi]
	mean_sink /= maxf(float(wheels.size()), 1.0)
	var con: Array = []
	con.resize(wheels.size())
	for wi in range(wheels.size()):
		var wv: Array = wheels[wi]
		var hub: Vector3 = wv[0]
		var top := pos + basis * (hub + Vector3(0, travel * 0.5, 0))
		var down := -basis.y
		var gy: float = ground_y.call(top.x, top.z)
		var wsink: float = sink[wi] if wi < sink.size() else 0.0
		gy -= lerpf(mean_sink, wsink, 0.3)      # the tyre is down in the mud
		var reach := travel + wheel_r + (BOGIE_DROOP if _on_bogie(wi) else 0.0)
		var dist := (top.y - gy) / maxf(-down.y, 0.3)
		var comp := clampf((travel + wheel_r - dist) / travel, 0.0, 1.6)
		compress[wi] = comp
		if dist > reach:
			continue
		var cp := top + down * dist             # contact patch
		var r := cp - cw
		var vp := vel + angvel.cross(r)
		var e := 0.4
		var n := Vector3(float(ground_y.call(cp.x - e, cp.z)) - float(ground_y.call(cp.x + e, cp.z)), 2.0 * e,
			float(ground_y.call(cp.x, cp.z - e)) - float(ground_y.call(cp.x, cp.z + e))).normalized()
		var fn := maxf(_k * comp * travel - _c * vp.dot(basis.y), 0.0)
		con[wi] = {"cp": cp, "r": r, "vp": vp, "n": n, "fn": minf(fn, m * 9.81 * 3.0), "sink": wsink}
	# A tandem on a walking beam (bogies): the two tyres on a side share
	# the load between them, so neither lifts off over a hump or a rut.
	for bp in bogies:
		var a0: int = bp[0]
		var a1: int = bp[1]
		if con[a0] == null and con[a1] == null:
			continue
		var tot := 0.0
		var nc := 0
		for k in [a0, a1]:
			if con[k] != null:
				tot += float(con[k]["fn"])
				nc += 1
		if nc == 2:
			con[a0]["fn"] = tot * 0.5
			con[a1]["fn"] = tot * 0.5
	# Pass 2: the forces at each tyre.
	for wi in range(wheels.size()):
		var wv: Array = wheels[wi]
		if con[wi] == null:
			if wi < _gcap.size():
				_gcap[wi] = lerpf(_gcap[wi], 0.0, clampf(dt / 0.12, 0.0, 1.0))
			if _dbg.size() == wheels.size():
				_dbg[wi] = null
			continue
		on_ground += 1
		var c: Dictionary = con[wi]
		if tyre_fn.is_valid():
			if _mark_d.size() != wheels.size():
				_mark_d.resize(wheels.size())
				_mark_d.fill(0.0)
			_mark_d[wi] += (c["vp"] as Vector3).length() * dt
			if _mark_d[wi] > 0.15:
				_mark_d[wi] = 0.0
				tyre_fn.call(c["cp"], -basis.z, tyre_w, clampf(mass_empty / 6000.0, 0.4, 1.5) * (1.0 + 2.0 * (wheel_mud[wi] if wi < wheel_mud.size() else 0.0)))
		var r: Vector3 = c["r"]
		var vp: Vector3 = c["vp"]
		var n: Vector3 = c["n"]
		var fn: float = c["fn"]
		var wsink: float = c["sink"]
		var wm: float = wheel_mud[wi] if wi < wheel_mud.size() else 0.0
		# wheel axes: steered on the front
		var wb := basis
		if bool(wv[1]):
			wb = basis * Basis(Vector3.UP, steer)
		var t := (-wb.z - n * (-wb.z).dot(n)).normalized()
		var s := (wb.x - n * wb.x.dot(n)).normalized()
		var vt := vp.dot(t)
		var vs := vp.dot(s)
		# Mud: slick (less grip), and it drags - more the deeper the tyre is in.
		var grip := mu * fn * lerpf(1.0, MUD_GRIP, wm)
		# longitudinal: drive or brake, then rolling resistance
		var fl := 0.0
		if wi < _gcap.size():
			_gcap[wi] = lerpf(_gcap[wi], grip, clampf(dt / 0.12, 0.0, 1.0))
		if bool(wv[2]) and n_drive > 0:
			fl += float(push[wi])
		if braking > 0.0:
			fl -= signf(vt) * minf(brake_force * braking / float(wheels.size()), absf(vt) * m / float(wheels.size()) / dt * 0.5)
		fl -= vt * 40.0
		# The mud's drag pushes on the truck (the bow wave against the tyres and
		# axles), not through the tyre's grip: so the tyre still gets the full
		# push from the engine, and spins when it's more than the mud can hold.
		var mud_drag := 0.0
		if wm > 0.05:
			# Pushing a bow wave of mud: up to ~18% of the weight on the wheel
			# when it's sunk right in (deep mud wants 4WD; a locker helps).
			var drag := fn * (0.02 + 0.12 * wm * wm + 0.06 * maxf(wm - 0.5, 0.0)) * clampf(0.7 + wsink / 0.2, 0.7, 1.6)
			if _own_track:
				drag *= 0.5                            # back along the ruts you just packed
			drag += fn * wm * 0.07 * absf(vt)          # and the faster you go, the harder it pushes back
			mud_drag = -signf(vt) * minf(drag, absf(vt) * m / float(wheels.size()) / dt * 0.5)
		# lateral: a tyre resists sliding sideways, up to its grip
		var flat := -vs * m / float(wheels.size()) * 6.0
		# friction circle
		var fv := Vector2(fl, flat)
		if fv.length() > grip:
			fv = fv.normalized() * grip
			if wi < slipping.size() and bool(wv[2]) and drive_total != 0.0:
				slipping[wi] = true
		var f := n * fn + t * (fv.x + mud_drag) + s * fv.y
		if debug and _dbg.size() != wheels.size():
			_dbg.resize(wheels.size())
		if debug:
			_dbg[wi] = [fn, grip, float(push[wi]) if bool(wv[2]) else 0.0, fv.x, mud_drag, n, wm, wsink, vt, t]
		force += f
		torque += r.cross(f)
		var spin_v := vt
		if wi < slipping.size() and slipping[wi]:
			spin_v = signf(drive_total) * maxf(absf(vt), 6.0)     # spinning in place
		wheel_spin[wi] += spin_v / wheel_r * dt
	# integrate
	var ixx := m * (size.y * size.y + size.z * size.z) / 12.0
	var iyy := m * (size.x * size.x + size.z * size.z) / 12.0
	var izz := m * (size.x * size.x + size.y * size.y) / 12.0
	var tb := basis.inverse() * torque
	angvel += (basis * Vector3(tb.x / ixx, tb.y / iyy, tb.z / izz)) * dt
	angvel *= 1.0 - 0.5 * dt
	vel += force / m * dt
	var np := pos + vel * dt
	if blocked.is_valid() and absf(speed) > 0.05 and blocked.call(np + fwd * signf(speed) * (size.z * 0.5 + 0.3) + Vector3(0, 1.0, 0)):
		vel = Vector3(0, vel.y, 0)
		np = pos + vel * dt
	pos = np
	if angvel.length() > 1e-6:
		basis = Basis(angvel.normalized(), angvel.length() * dt) * basis
	basis = basis.orthonormalized()
	var res: Array = Hull.resolve(pos, basis, vel, angvel, _hull, ground_y, dt)
	pos = res[0]
	basis = res[1]
	vel = res[2]
	angvel = res[3]
	if float(res[4]) > 0.0:
		last_hit = float(res[4])
	tilt_deg = rad_to_deg(acos(clampf(basis.y.y, -1.0, 1.0)))


func settle() -> void:
	for i in range(300):
		step(1.0 / 120.0, 0.0, 0.0, true)
	vel = Vector3.ZERO
	angvel = Vector3.ZERO


## Mud, once a frame: what each wheel is in, how far it's sunk, spinning,
## and the ruts it leaves.
## Sinking: a tyre settles into soft ground under its load; spinning digs it
## deeper fast (so flooring it buries you); rolling along it rides up a bit.
## Rocking back and forth or a tow gets you out.
func _mud_step(dt: float, throttle: float) -> void:
	var nw := wheels.size()
	if sink.size() != nw:
		sink.resize(nw)
		sink.fill(0.0)
		wheel_mud.resize(nw)
		wheel_mud.fill(0.0)
		slipping.resize(nw)
		_rut_dist.resize(nw)
		_rut_dist.fill(0.0)
	var total := 0.0
	var spins := 0
	var per_wheel_t := mass() / maxf(float(nw), 1.0) / 1000.0     # tonnes on each wheel
	for wi in range(nw):
		var wv: Array = wheels[wi]
		var p := pos + basis * (wv[0] as Vector3)
		var m: float = mud_fn.call(p.x, p.z) if mud_fn.is_valid() else 0.0
		wheel_mud[wi] = m
		total += m
		var rolling := absf(speed)
		var spinning := slipping[wi]
		if spinning:
			spins += 1
		slipping[wi] = false
		# how deep it would settle standing still: heavier on each wheel, deeper
		var settle := m * m * (0.13 + 0.08 * clampf(per_wheel_t, 0.0, 3.0))
		var want := settle * (1.0 - 0.45 * clampf(rolling / 8.0, 0.0, 1.0))
		var s := sink[wi]
		if m < 0.05:
			s = move_toward(s, 0.0, 0.6 * dt)
		elif spinning and absf(throttle) > 0.2 and m > 0.3:
			s += (0.03 + 0.18 * (m - 0.3)) * dt          # digging itself in
		elif s > want:
			s = move_toward(s, want, (0.06 + 0.12 * clampf(rolling / 3.0, 0.0, 1.0)) * dt)   # climbing out as it rolls
		else:
			s = move_toward(s, want, 0.25 * dt)
		sink[wi] = clampf(s, 0.0, wheel_r * (0.45 + 0.3 * m))
		# ruts: every metre or so of travel through soft ground (or spinning)
		if m > 0.2 and rut_fn.is_valid():
			_rut_dist[wi] += maxf(rolling, 0.8 if spinning else 0.0) * dt
			if _rut_dist[wi] > 1.1:
				_rut_dist[wi] = 0.0
				var gy: float = ground_y.call(p.x, p.z)
				rut_fn.call(Vector3(p.x, gy, p.z), wheel_r * 0.75, (0.012 + 0.025 * m) * clampf(per_wheel_t, 0.4, 2.5) * (1.3 if spinning else 1.0))
	# Rocking: going back the way you came runs in your own packed ruts.
	var sv := signf(speed) if absf(speed) > 0.15 else 0.0
	if sv != 0.0:
		if sv == _dir:
			_dir_dist = minf(_dir_dist + absf(speed) * dt, 6.0)
		else:
			_own_track = _dir_dist > 0.2
			_dir = sv
			_dir_dist = 0.0
	if absf(throttle) > 0.1 and signf(throttle) != _dir and _dir != 0.0:
		_own_track = true                      # pushing back the other way
	elif _dir_dist > 3.0:
		_own_track = false                     # off your old track now
	if _own_track:
		for wi in range(nw):
			sink[wi] = move_toward(sink[wi], 0.0, 0.05 * dt)
	mud_now = total / maxf(float(nw), 1.0)
	spin_now = lerpf(spin_now, float(spins) / maxf(float(nw), 1.0), clampf(6.0 * dt, 0.0, 1.0))
