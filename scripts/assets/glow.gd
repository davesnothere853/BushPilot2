extends RefCounted
## Shared glowing materials that blink (DESIGN_NOTES 228): the obstruction
## beacons on masts and towers, the steady red side lights, the lighthouse
## lamp. One material each for the whole map; tick(t) flashes them.

static var beacon: StandardMaterial3D
static var steady: StandardMaterial3D
static var lamp: StandardMaterial3D


static func _m(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


static func get_beacon() -> StandardMaterial3D:
	if beacon == null:
		beacon = _m(Color(1.0, 0.12, 0.05), 8.0)
	return beacon


static func get_steady() -> StandardMaterial3D:
	if steady == null:
		steady = _m(Color(1.0, 0.1, 0.05), 3.0)
	return steady


static func get_lamp() -> StandardMaterial3D:
	if lamp == null:
		lamp = _m(Color(1.0, 0.93, 0.75), 2.0)
	return lamp


## Flash: the beacons ~30 a minute (on 1 s of 2), the lighthouse a 1 s flash every 6 s.
static func tick(t: float) -> void:
	if beacon != null:
		var on := fmod(t, 2.0) < 1.0
		beacon.emission_energy_multiplier = 8.0 if on else 0.0
		beacon.albedo_color = Color(1.0, 0.12, 0.05) if on else Color(0.3, 0.05, 0.03)
	if lamp != null:
		lamp.emission_energy_multiplier = 14.0 if fmod(t, 6.0) < 1.0 else 1.0
