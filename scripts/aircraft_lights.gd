extends Node3D
## The aeroplane's outside lights, each on its own switch (plane.lights):
## red and green navigation lights on the wingtips and white on the tail, a
## flashing red beacon, white wingtip strobes (double flash), and landing and
## taxi lights that light up the ground. They need the battery master on and
## draw current from it. Placed for whichever type is flown (setup()).

var plane: Node3D
var _parts := {}          # name -> [glow MeshInstance3D, light (or null)]
var _t := 0.0
var _type := ""

const NAV_R := Color(1.0, 0.08, 0.05)
const NAV_G := Color(0.1, 1.0, 0.3)
const WHITE := Color(1.0, 0.98, 0.95)
const BEACON := Color(1.0, 0.12, 0.05)

## Amps each light draws.
const AMPS := {"nav": 3.0, "beacon": 4.0, "strobe": 5.0, "landing": 8.0, "taxi": 6.0}


static func positions(t: String) -> Dictionary:
	if t == "dc3":
		var tip_y := -1.05 + 9.6 * tan(deg_to_rad(5.0))
		return {"nav_l": Vector3(-14.55, tip_y, 0.7), "nav_r": Vector3(14.55, tip_y, 0.7), "nav_tail": Vector3(0, 1.0, 12.08),
			"beacon": Vector3(0, 1.62, 1.5), "beacon2": Vector3(0, -1.46, 1.0),
			"strobe_l": Vector3(-14.5, tip_y, 1.1), "strobe_r": Vector3(14.5, tip_y, 1.1),
			"landing_l": Vector3(-5.6, -0.86, -1.15), "landing_r": Vector3(5.6, -0.86, -1.15), "taxi": Vector3(0, -0.95, -7.3)}
	if t == "biplane":
		return {"nav_l": Vector3(-4.97, 1.25, -0.30), "nav_r": Vector3(4.97, 1.25, -0.30), "nav_tail": Vector3(0, 0.62, 5.52),
			"strobe_l": Vector3(-4.95, 1.25, 0.05), "strobe_r": Vector3(4.95, 1.25, 0.05),
			"landing_l": Vector3(-2.3, -0.47, -0.20), "taxi": Vector3(2.3, -0.47, -0.20)}
	return {"nav_l": Vector3(-5.52, 1.10, -0.25), "nav_r": Vector3(5.52, 1.10, -0.25), "nav_tail": Vector3(0, 0.31, 5.13),
		"beacon": Vector3(0, 1.66, 4.95), "strobe_l": Vector3(-5.5, 1.10, 0.15), "strobe_r": Vector3(5.5, 1.10, 0.15),
		"landing_l": Vector3(-2.6, 0.86, -0.78), "taxi": Vector3(2.6, 0.86, -0.78)}


func setup(t: String) -> void:
	if t == _type:
		return
	_type = t
	for c in get_children():
		c.queue_free()
	_parts.clear()
	var pos := positions(t)
	var big := 2.4 if t == "dc3" else 1.0
	for k in pos.keys():
		var p: Vector3 = pos[k]
		var col := WHITE
		if k == "nav_l" or k.begins_with("beacon"):
			col = NAV_R if k == "nav_l" else BEACON
		elif k == "nav_r":
			col = NAV_G
		var light: Light3D = null
		if k.begins_with("landing") or k == "taxi":
			var sp := SpotLight3D.new()
			sp.rotation = Vector3(deg_to_rad(-6.0 if k != "taxi" else -12.0), 0.0, 0.0)
			sp.spot_range = 320.0 if k != "taxi" else 90.0
			sp.spot_angle = 14.0 if k != "taxi" else 32.0
			sp.light_color = Color(1.0, 0.93, 0.82)
			sp.shadow_enabled = k != "taxi"
			light = sp
		else:
			var om := OmniLight3D.new()
			om.light_color = col
			om.omni_range = (2.5 if k.begins_with("nav") else 7.0) * big
			om.shadow_enabled = false
			light = om
		light.position = p
		light.light_energy = 0.0
		add_child(light)
		# The lens: a little glowing bead (always drawn, bright when on).
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = (0.035 if not (k.begins_with("landing") or k == "taxi") else 0.06) * (1.6 if t == "dc3" else 1.0)
		sm.height = sm.radius * 2.0
		sm.radial_segments = 8
		sm.rings = 4
		var m := StandardMaterial3D.new()
		m.albedo_color = col.darkened(0.6)
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.0
		sm.material = m
		mi.mesh = sm
		mi.position = p
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_parts[k] = [mi, light, m]


## Current drawn by the lights that are on (for the electrical system).
static func load_amps(lights: Dictionary) -> float:
	var a := 0.0
	for k in lights.keys():
		if bool(lights[k]):
			a += float(AMPS.get(k, 0.0))
	return a


func _light(k: String, on: float, energy: float) -> void:
	if not _parts.has(k):
		return
	var p: Array = _parts[k]
	(p[1] as Light3D).light_energy = energy * on
	(p[1] as Light3D).visible = on > 0.0
	(p[2] as StandardMaterial3D).emission_energy_multiplier = 4.0 * on


func _process(delta: float) -> void:
	if plane == null:
		return
	_t += delta
	var e = plane.engine
	var power: bool = e.master and e.battery > 0.02 and not plane.is_crashed
	var L: Dictionary = plane.lights
	var nav := 1.0 if power and bool(L.get("nav", false)) else 0.0
	for k in ["nav_l", "nav_r", "nav_tail"]:
		_light(k, nav, 0.8)
	# Beacon: a rotating red flash about once a second.
	var bc := 0.0
	if power and bool(L.get("beacon", false)):
		bc = pow(maxf(sin(_t * TAU * 0.9), 0.0), 6.0)
	_light("beacon", bc, 3.0)
	_light("beacon2", bc, 3.0)
	# Strobes: double flash every 1.2 seconds.
	var st := 0.0
	if power and bool(L.get("strobe", false)):
		var ph := fmod(_t, 1.2)
		st = 1.0 if ph < 0.05 or (ph > 0.15 and ph < 0.2) else 0.0
	_light("strobe_l", st, 6.0)
	_light("strobe_r", st, 6.0)
	var ld := 1.0 if power and bool(L.get("landing", false)) else 0.0
	_light("landing_l", ld, 7.0)
	_light("landing_r", ld, 7.0)
	_light("taxi", 1.0 if power and bool(L.get("taxi", false)) else 0.0, 4.0)
