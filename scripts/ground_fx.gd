extends Node3D
## What the wheels and the propeller throw up from the ground: a dust trail
## behind each rolling wheel, a burst when a wheel touches down, and prop wash
## blasting loose ground behind the plane at high power. Dirt and gravel give
## dust, snow gives white plumes, grass very little, water gives spray.

const Fx = preload("res://scripts/fx.gd")
const Wake = preload("res://scripts/wake.gd")

var plane: Node3D
var terrain: RefCounted
var waves: Node             # waves.gd: wakes on the water

## surface -> [colour, how much it throws up]
const SURF := {
	0: [Color(0.56, 0.51, 0.41), 0.35],    # rough ground
	1: [Color(0.66, 0.62, 0.54), 0.8],     # gravel
	2: [Color(0.46, 0.47, 0.32), 0.15],    # grass
	3: [Color(0.63, 0.53, 0.41), 1.0],     # dirt
	4: [Color(0.93, 0.95, 0.98), 1.0],     # deep snow
	5: [Color(0.92, 0.94, 0.97), 0.65],    # packed snow
	6: [Color(0.90, 0.93, 0.97), 0.1],     # ice
	7: [Color(0.86, 0.91, 0.95), 0.9],     # water
}

var _trail: Array[CPUParticles3D] = []
var _burst: Array[CPUParticles3D] = []
var _wash: CPUParticles3D
var _loaded := [true, true, true]
var _splash: Array[CPUParticles3D] = []
var _wet := [false, false, false]
var _wave_from := Vector3.INF
var _wave_clock := 0.0
var _spray: Array[CPUParticles3D] = []
var _mist: Array[CPUParticles3D] = []
var _last_drop: Array[Vector3] = [Vector3.INF, Vector3.INF, Vector3.INF]
var wake: MultiMeshInstance3D       # foam on the water, shared with anything else that splashes


func _ready() -> void:
	var ramp := Fx.gradient([[0.0, Color(1, 1, 1, 0.0)], [0.12, Color(1, 1, 1, 0.55)], [0.5, Color(1, 1, 1, 0.3)], [1.0, Color(1, 1, 1, 0.0)]])
	for i in range(3):
		var t := Fx.particles(Fx.smoke_material(), 48, 2.4, 1.1, ramp, 3.2)
		t.direction = Vector3(0, 1, 0)
		t.spread = 55.0
		t.initial_velocity_min = 0.6
		t.initial_velocity_max = 2.2
		t.gravity = Vector3(0, -0.3, 0)
		t.damping_min = 0.6
		t.damping_max = 1.2
		t.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		t.emission_sphere_radius = 0.25
		t.emitting = false
		add_child(t)
		_trail.append(t)
		var b := Fx.particles(Fx.smoke_material(), 22, 1.8, 1.2, ramp, 3.0)
		b.one_shot = true
		b.explosiveness = 0.95
		b.direction = Vector3(0, 1, 0)
		b.spread = 80.0
		b.initial_velocity_min = 1.5
		b.initial_velocity_max = 4.0
		b.gravity = Vector3(0, -0.6, 0)
		b.damping_min = 1.5
		b.damping_max = 2.5
		b.emitting = false
		add_child(b)
		_burst.append(b)
	# Water: a sheet of spray off each tyre that skims it, plus a fine mist.
	var wet := Fx.gradient([[0.0, Color(1, 1, 1, 0.0)], [0.06, Color(1, 1, 1, 0.85)], [0.5, Color(1, 1, 1, 0.45)], [1.0, Color(1, 1, 1, 0.0)]])
	for i in range(3):
		var sp := Fx.particles(Fx.smoke_material(), 320, 0.75, 0.2, wet, 3.0)
		sp.spread = 12.0
		sp.gravity = Vector3(0, -9.8, 0)
		sp.damping_min = 0.5
		sp.damping_max = 1.5
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sp.emission_sphere_radius = 0.12
		sp.emitting = false
		add_child(sp)
		_spray.append(sp)
		var mi := Fx.particles(Fx.smoke_material(), 70, 2.0, 1.0, ramp, 4.0)
		mi.spread = 40.0
		mi.gravity = Vector3(0, -0.4, 0)
		mi.damping_min = 1.5
		mi.damping_max = 3.0
		mi.emitting = false
		add_child(mi)
		_mist.append(mi)
	wake = Wake.new()
	wake.name = "Wake"
	add_child(wake)
	# A splash when something first hits the water.
	var sramp := Fx.gradient([[0.0, Color(1, 1, 1, 0.0)], [0.06, Color(1, 1, 1, 0.75)], [0.45, Color(1, 1, 1, 0.4)], [1.0, Color(1, 1, 1, 0.0)]])
	for i in range(3):
		var sh := Fx.particles(Fx.smoke_material(), 40, 1.3, 0.7, sramp, 3.0)
		sh.one_shot = true
		sh.explosiveness = 0.9
		sh.direction = Vector3(0, 1, 0)
		sh.spread = 70.0
		sh.initial_velocity_min = 2.0
		sh.initial_velocity_max = 6.0
		sh.gravity = Vector3(0, -9.8, 0)
		sh.color = Color(0.93, 0.96, 0.98, 0.85)
		sh.emitting = false
		add_child(sh)
		_splash.append(sh)
	_wash = Fx.particles(Fx.smoke_material(), 70, 2.2, 2.0, ramp, 3.5)
	_wash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_wash.emission_box_extents = Vector3(2.0, 0.2, 1.0)
	_wash.spread = 25.0
	_wash.gravity = Vector3(0, 0.2, 0)
	_wash.damping_min = 1.0
	_wash.damping_max = 2.0
	_wash.emitting = false
	add_child(_wash)


func _surface(p: Vector3) -> Array:
	var k: int = terrain.surface_at(p.x, p.z)
	var spec: Array = SURF.get(k, SURF[0])
	var amount: float = spec[1]
	var col: Color = spec[0]
	if Game.outback() and k <= 3:
		# Bone-dry red dirt: red-orange dust, and plenty of it.
		col = [Color(0.76, 0.46, 0.30), Color(0.80, 0.54, 0.38), Color(0.74, 0.56, 0.38), Color(0.78, 0.44, 0.27)][k]
		amount = minf(amount * 1.6 + 0.2, 1.0)
	# Damp ground in spring and autumn raises less dust (snow is still snow).
	elif k <= 3 and (Game.season == Game.SPRING or Game.season == Game.FALL):
		amount *= 0.6
	return [col, amount, k]


func _process(_delta: float) -> void:
	if plane == null or terrain == null:
		return
	var xf: Transform3D = plane.global_transform
	var speed: float = plane.ground_speed
	var dead: bool = plane.is_crashed
	for i in range(3):
		var wp: Vector3 = plane.wheel_pos[i]
		var p := xf * wp
		var g: float = terrain.ground_level_at(p.x, p.z)
		var loaded: bool = float(plane.wheel_load[i]) > 60.0 and not dead
		var t := _trail[i]
		if loaded:
			var s := _surface(p)
			var col: Color = s[0]
			var amt: float = s[1] * clampf((speed - 1.0) / 22.0, 0.0, 1.0)
			if i == 2:
				amt *= 0.5          # the little tailwheel
			t.global_position = Vector3(p.x, g + 0.15, p.z)
			t.emitting = amt > 0.04
			t.color = Color(col.r, col.g, col.b, clampf(amt, 0.0, 1.0))
			var spray: bool = int(s[2]) == 7
			t.initial_velocity_max = 2.2 + (3.0 if spray else 0.0) * amt
			# Touchdown: a puff from each wheel as it meets the ground.
			if not _loaded[i]:
				var sink: float = clampf(-float(plane.vel.y) / 3.0, 0.0, 1.0)
				var hit := s[1] as float * clampf(0.35 + sink + speed / 40.0, 0.0, 1.0)
				if hit > 0.08:
					var b := _burst[i]
					b.global_position = Vector3(p.x, g + 0.1, p.z)
					b.color = Color(col.r, col.g, col.b, clampf(hit, 0.0, 1.0))
					b.restart()
		else:
			t.emitting = false
		_loaded[i] = loaded
		_water(i, xf * plane.water_pos[i], xf, dead)
	_water_fx(xf, dead)
	# Prop wash: full power on loose ground blows it back under the tail.
	var power: float = plane.power_frac if plane.engine_running else 0.0
	if plane.on_ground and not dead and power > 0.35:
		var behind := xf * Vector3(0.0, 0.0, 3.5)
		var g2: float = terrain.ground_level_at(behind.x, behind.z)
		var s2 := _surface(behind)
		var amt2: float = float(s2[1]) * clampf((power - 0.35) / 0.5, 0.0, 1.0) * (1.0 - clampf(speed / 30.0, 0.0, 0.8))
		if int(s2[2]) == 2:
			amt2 *= 0.3
		_wash.emitting = amt2 > 0.05
		_wash.global_transform = Transform3D(xf.basis.orthonormalized(), Vector3(behind.x, g2 + 0.3, behind.z))
		var back := (xf.basis * Vector3(0, 0, 1)).normalized()
		_wash.direction = (_wash.global_transform.basis.inverse() * (back + Vector3(0, 0.25, 0))).normalized()
		_wash.initial_velocity_min = 4.0 * power
		_wash.initial_velocity_max = 9.0 * power
		var c2: Color = s2[0]
		_wash.color = Color(c2.r, c2.g, c2.b, clampf(amt2, 0.0, 0.9))
	else:
		_wash.emitting = false


## Spray and a foam trail from a tyre running through water.
func _water(i: int, p: Vector3, xf: Transform3D, dead: bool) -> void:
	var dip: float = float(plane.wheel_water[i]) if "wheel_water" in plane else 0.0
	var sp := _spray[i]
	var mi := _mist[i]
	if dip <= 0.0 or dead:
		sp.emitting = false
		mi.emitting = false
		_last_drop[i] = Vector3.INF
		return
	var level: float = terrain.water_level_at(p.x, p.z)
	var v: Vector3 = plane.vel
	var vh := Vector3(v.x, 0.0, v.z)
	var speed := vh.length()
	var amt := clampf(dip / 0.05, 0.15, 1.0) * clampf((speed - 2.0) / 18.0, 0.0, 1.0)
	if i == 2:
		amt *= 0.4
	var back := -vh.normalized() if speed > 0.5 else (xf.basis * Vector3(0, 0, 1)).normalized()
	var at := Vector3(p.x, level + 0.05, p.z)
	sp.global_position = at
	mi.global_position = at
	sp.emitting = amt > 0.05
	mi.emitting = amt > 0.2
	# Thrown back and up in a sheet, off to the side the wheel is on.
	var side := (xf.basis * Vector3(1, 0, 0)).normalized() * (-1.0 if i == 0 else (1.0 if i == 1 else 0.0))
	sp.direction = (back * 1.0 + Vector3.UP * 0.55 + side * 0.35).normalized()
	sp.initial_velocity_min = speed * 0.25
	sp.initial_velocity_max = speed * 0.5
	sp.color = Color(1, 1, 1, clampf(amt, 0.0, 1.0))
	mi.direction = (back + Vector3.UP * 0.3).normalized()
	mi.initial_velocity_min = speed * 0.1
	mi.initial_velocity_max = speed * 0.25
	mi.color = Color(1, 1, 1, clampf(amt * 0.5, 0.0, 1.0))
	# Foam: a patch every metre or so of travel.
	if _last_drop[i] == Vector3.INF or _last_drop[i].distance_to(at) > 0.9:
		var w: float = 0.35 if i < 2 else 0.15
		wake.drop(at, -back, w, 1.6, 0.4 + 0.6 * amt, 0.25 + speed * 0.02)
		_last_drop[i] = at


## A splash as something first hits the water, and the waves it leaves
## behind (waves.gd spreads them across the lake). The spray sheets and the
## foam trail are in _water().
func _water_fx(xf: Transform3D, dead: bool) -> void:
	var vh := Vector3(plane.vel.x, 0.0, plane.vel.z)
	var u := vh.length()
	var wet_sum := 0.0
	var wet_at := Vector3.ZERO
	var n_wet := 0
	var wl: float = terrain.water_level_at(xf.origin.x, xf.origin.z)
	for i in range(3):
		var wd: float = float(plane.wheel_water[i]) if not dead else 0.0
		var wet := wd > 0.002
		if wet:
			var p: Vector3 = xf * plane.water_pos[i]
			var at := Vector3(p.x, wl + 0.02, p.z)
			n_wet += 1
			wet_sum += wd
			wet_at += at
			if not _wet[i] and u > 4.0:
				var sh := _splash[i]
				sh.global_position = at
				sh.initial_velocity_max = 3.0 + u * 0.2
				sh.restart()
		_wet[i] = wet
	# Waves: one ring every few metres while something is in the water.
	_wave_clock += get_process_delta_time()
	if waves != null and n_wet > 0 and u > 0.4:
		var at2 := wet_at / float(n_wet)
		if _wave_from == Vector3.INF or at2.distance_to(_wave_from) > 4.0 or _wave_clock > 0.6:
			var h := clampf(minf(wet_sum, 0.15) * 1.5 + 0.03, 0.0, 0.3) * clampf(u / 10.0, 0.15, 1.0)
			waves.add(at2, h)
			_wave_from = at2
			_wave_clock = 0.0
	elif n_wet == 0:
		_wave_from = Vector3.INF
