extends Node
## The air: steady wind, gusts, slope lift over terrain and turbulence.

var terrain: RefCounted
var time: float = 0.0
var base_speed: float = 0.0           # metres per second
var base_dir := Vector3(1, 0, 0)      # unit vector the air is moving toward
var gustiness: float = 0.2
var turbulence_scale: float = 1.0
var gust_boost := 1.0                 # storm.gd: a passing gust or squall (1 = none)


func _ready() -> void:
	configure()
	Game.settings_changed.connect(configure)


func configure() -> void:
	base_speed = Game.WIND_SPEEDS[Game.wind_level]
	# Fall and winter blow harder.
	if Game.season == Game.FALL or Game.season == Game.WINTER:
		base_speed *= 1.2
	var to_heading := deg_to_rad(Game.wind_dir_deg + 180.0)
	base_dir = Vector3(sin(to_heading), 0.0, -cos(to_heading))
	gustiness = 0.12 + 0.07 * float(Game.wind_level)
	turbulence_scale = 1.0 if Game.is_realistic() else 0.55


func _physics_process(delta: float) -> void:
	time += delta


## Direction the wind comes from, in degrees true, and its speed in knots near the ground.
func report() -> Vector2:
	return Vector2(fposmod(Game.wind_dir_deg, 360.0), base_speed * 1.94384)


## Wind velocity at a point: steady flow, gusts, and lift or sink over slopes.
func sample(p: Vector3) -> Vector3:
	if base_speed < 0.05:
		return Vector3.ZERO
	var gh := 0.0
	if terrain != null:
		gh = maxf(terrain.height_at(p.x, p.z), 0.0)
	var agl := maxf(p.y - gh, 0.0)
	# Slower near the surface, stronger aloft.
	var grad := (0.55 + 0.45 * clampf(agl / 250.0, 0.0, 1.0)) * (1.0 + 0.25 * clampf(p.y / 2000.0, 0.0, 1.0))
	var gust := 1.0 + gustiness * (0.6 * sin(0.11 * time + p.x * 0.0021) + 0.4 * sin(0.37 * time + 1.7 + p.z * 0.0034))
	var swing := 0.14 * sin(0.07 * time + 0.5) + 0.07 * sin(0.23 * time + p.x * 0.001)
	var dir := base_dir.rotated(Vector3.UP, swing)
	var speed := base_speed * grad * gust * gust_boost
	var w := dir * speed
	if terrain != null:
		# Air climbing a slope rises, air spilling down the far side sinks.
		var ahead: float = terrain.height_at(p.x + dir.x * 140.0, p.z + dir.z * 140.0)
		var behind: float = terrain.height_at(p.x - dir.x * 140.0, p.z - dir.z * 140.0)
		var slope := (maxf(ahead, 0.0) - maxf(behind, 0.0)) / 280.0
		var lift := speed * clampf(slope, -0.6, 0.6) * exp(-agl / 380.0)
		w.y = lift
	return w


# ------------------------------------------------------------------------------
#  Turbulence you fly through (DESIGN_NOTES 154)
#
#  A frozen field of gusts drifting with the wind, sampled at several points
#  on the aeroplane (each wingtip, the tail) so a gust under one wing lifts
#  that wing and one at the tail pitches the nose: the bumps, rolls and
#  porpoising come out of the flight model's own sums, sized to the
#  aeroplane (a DC-3's long wings average small gusts out, a light plane
#  gets kicked about). Intensities and length scales follow the Dryden
#  low-altitude model (MIL-F-8785C): sigma_w = 0.1 W20, sigma_u = sigma_v =
#  sigma_w / (0.177 + 0.000823 h)^0.4, L_w = h, L_u = h / (0.177 +
#  0.000823 h)^1.2 (h in feet), isotropic above 2,000 ft. On top: rough
#  air over the forest and in the lee of hills (rotor), and on sunny
#  afternoons thermals - columns of rising air with sink round them - and
#  the convective chop that comes with them, none in winter or rain.
# ------------------------------------------------------------------------------
var _nu: FastNoiseLite
var _nv: FastNoiseLite
var _nw: FastNoiseLite


func _field() -> void:
	if _nu != null:
		return
	var seeds := [101, 202, 303]
	var arr: Array = []
	for sd in seeds:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.seed = sd
		n.frequency = 1.0
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		n.fractal_lacunarity = 2.7
		n.fractal_gain = 0.45        # the smaller eddies weaker, about as the -5/3 spectrum
		arr.append(n)
	_nu = arr[0]
	_nv = arr[1]
	_nw = arr[2]


## How convective the day is, 0..1: summer afternoons in sun, none in winter
## or rain, nothing at night.
func convection() -> float:
	var s := 1.0
	match Game.season:
		Game.SUMMER:
			s = 1.0
		Game.WINTER:
			s = 0.08
		_:
			s = 0.55
	if Game.weather == 2:
		return 0.0
	if Game.weather == 1:
		s *= 0.45
	var h: float = Game.time_of_day
	var day := clampf(sin(PI * (h - 9.0) / 10.0), 0.0, 1.0)     # 9:00 to 19:00, strongest mid-afternoon
	return s * day


## The gust (m/s, world axes) at point p: everything but the steady wind.
func gust_at(p: Vector3) -> Vector3:
	_field()
	var gh := 0.0
	if terrain != null:
		gh = maxf(terrain.height_at(p.x, p.z), 0.0)
	var agl := maxf(p.y - gh, 1.0)
	var h_ft := clampf(agl * 3.28084, 10.0, 2000.0)
	var den := 0.177 + 0.000823 * minf(h_ft, 1000.0)
	# W20: the wind 20 ft up (sample() is slower near the ground)
	var w20 := base_speed * 0.6
	var conv := convection()
	var sig_w := 0.1 * w20 + 0.55 * conv            # thermals stir the boundary layer even with no wind
	var sig_uv := sig_w / pow(den, 0.4)
	if h_ft > 1000.0:
		# up toward 2,000 ft the gusts even out (isotropic), and calm down above
		var k := clampf((h_ft - 1000.0) / 1000.0, 0.0, 1.0)
		sig_uv = lerpf(sig_uv, sig_w, k)
	var above := clampf((agl - 600.0) / 900.0, 0.0, 1.0)
	var calm_aloft := lerpf(1.0, 0.45 + 0.4 * conv, above)
	# rough ground: the forest and the lee of hills (rotor)
	var rough := 1.0
	if terrain != null and agl < 250.0:
		var f: float = terrain.forest_at(p.x, p.z) if terrain.has_method("forest_at") else 0.0
		rough += 0.35 * f * clampf(1.0 - agl / 250.0, 0.0, 1.0)
		if base_speed > 2.0:
			var up_h: float = terrain.height_at(p.x - base_dir.x * 120.0, p.z - base_dir.z * 120.0)
			var lee := clampf((up_h - gh) / 40.0, 0.0, 1.0)      # higher ground upwind: you're in its lee
			rough += 0.9 * lee * clampf(1.0 - agl / 300.0, 0.0, 1.0) * clampf(base_speed / 8.0, 0.0, 1.5)
	var amp := turbulence_scale * calm_aloft * rough * (1.0 + (gust_boost - 1.0) * 1.5)
	# length scales (metres): small near the ground, growing with height
	var lw := clampf(agl, 8.0, 600.0)
	var lu := clampf((h_ft / pow(den, 1.2)) / 3.28084, 20.0, 600.0)
	# the field drifts with the wind (frozen turbulence)
	var q := p - base_dir * base_speed * time
	var gu := _nu.get_noise_3d(q.x / lu, q.y / lw, q.z / lu) / 0.26
	var gv := _nv.get_noise_3d(q.x / lu + 50.0, q.y / lw, q.z / lu) / 0.26
	var gw := _nw.get_noise_3d(q.x / lw, q.y / lw + 50.0, q.z / lw) / 0.26
	# u along the wind, v across it, w up
	var along := base_dir if base_speed > 0.5 else Vector3(1, 0, 0)
	var across := Vector3(-along.z, 0.0, along.x)
	var g := (along * gu + across * gv) * sig_uv * amp + Vector3.UP * gw * sig_w * amp
	# near the ground the vertical gusts die out (the ground stops them)
	g.y *= clampf(agl / 12.0, 0.15, 1.0)
	g.y += thermal_at(p, agl, conv)
	return g


## Rising air in thermals and the sink between them (m/s, up +).
## A thermal every 700 m cell or so, 60-150 m across, drifting with the
## wind and coming and going over 8-15 minutes; a ring of sink round each.
func thermal_at(p: Vector3, agl: float, conv: float) -> float:
	if conv < 0.03 or agl < 5.0:
		return 0.0
	var cell := 700.0
	var drift := base_dir * base_speed * time * 0.9
	var q := p - drift
	var ci := int(floor(q.x / cell))
	var cj := int(floor(q.z / cell))
	var zi := 1100.0 + 700.0 * conv          # top of the convective layer
	var hk := clampf(agl / 120.0, 0.0, 1.0) * clampf((zi - agl) / 300.0, 0.0, 1.0)
	if hk <= 0.0:
		return 0.0
	var w := 0.0
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var i := ci + di
			var j := cj + dj
			var h1 := _hash2(i, j, 1)
			if h1 > 0.65:
				continue                      # no thermal in this cell
			var cx := (float(i) + 0.2 + 0.6 * _hash2(i, j, 2)) * cell
			var cz := (float(j) + 0.2 + 0.6 * _hash2(i, j, 3)) * cell
			var r := Vector2(q.x - cx, q.z - cz).length()
			var rad := (60.0 + 90.0 * _hash2(i, j, 4)) * (0.7 + 0.3 * clampf(agl / 400.0, 0.0, 1.0))
			if r > rad * 3.0:
				continue
			var period := 480.0 + 420.0 * _hash2(i, j, 5)
			var life := clampf(sin(TAU * time / period + 6.28 * _hash2(i, j, 6)) * 1.4, 0.0, 1.0)
			var w0 := (1.4 + 2.4 * _hash2(i, j, 7)) * conv * life
			var x := r / rad
			w += w0 * (1.0 / (1.0 + pow(x, 4.0)) - 0.32 * exp(-pow((x - 1.8) / 0.7, 2.0)))
	return w * hk


static func _hash2(i: int, j: int, k: int) -> float:
	var h := (i * 374761393 + j * 668265263 + k * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 100000) / 100000.0


## Fast, small-scale velocity jitter (metres per second) to add on top of sample().
## (Old: sums of sines. The flight model now uses gust_at(); kept for the
## odd caller.)
func turbulence(p: Vector3) -> Vector3:
	if base_speed < 0.05:
		return Vector3.ZERO
	var gh := 0.0
	if terrain != null:
		gh = maxf(terrain.height_at(p.x, p.z), 0.0)
	var agl := maxf(p.y - gh, 0.0)
	var amp := base_speed * 0.11 * turbulence_scale * (0.35 + 0.65 * exp(-agl / 450.0))
	var t := time
	var tx := sin(1.7 * t + p.x * 0.013) + 0.6 * sin(4.3 * t + p.z * 0.021 + 1.0) + 0.3 * sin(9.1 * t + 2.0)
	var ty := sin(1.3 * t + p.z * 0.011 + 0.7) + 0.6 * sin(3.7 * t + p.x * 0.017 + 2.1) + 0.3 * sin(8.3 * t + 0.4)
	var tz := sin(1.9 * t + p.x * 0.009 + 1.9) + 0.6 * sin(5.1 * t + p.z * 0.015 + 0.3) + 0.3 * sin(10.3 * t + 1.2)
	return Vector3(tx, ty * 0.8, tz) * amp * 0.55


## Unitless rolling and yawing upsets in the range of about -1 to 1.
func upset() -> Vector3:
	if base_speed < 0.05:
		return Vector3.ZERO
	var t := time
	var k := clampf(base_speed / 12.0, 0.0, 1.2) * turbulence_scale
	return Vector3(
		sin(2.3 * t + 0.4) * 0.6 + sin(5.9 * t + 1.1) * 0.4,
		sin(1.6 * t + 2.2) * 0.6 + sin(4.4 * t + 0.6) * 0.4,
		sin(2.9 * t + 1.5) * 0.6 + sin(7.1 * t + 2.7) * 0.4) * k
