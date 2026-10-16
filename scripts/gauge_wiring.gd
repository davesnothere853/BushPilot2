extends RefCounted
## Gauge wiring (DESIGN_NOTES 121): readings you can send to any gauge in an
## aftermarket pod. Each signal has a name, a dial (range, ticks, bands) and
## reads a value off the engine model. The workshop menu routes a signal to
## each gauge; the pod is rebuilt with the new faces.

## id -> [menu name, dial spec, reader key]
const SIGNALS := {
	"boost":   ["Boost / vacuum (psi)", {"title": "BOOST", "unit": "PSI", "lo": -20, "hi": 15, "major": 5, "minor": 2.5, "a0": 225, "a1": -45,
		"bands": [[12, 15, Color(0.8, 0.12, 0.08)]]}],
	"fuel_psi": ["Fuel pressure (psi)", {"title": "FUEL", "unit": "PSI", "lo": 0, "hi": 15, "major": 5, "minor": 1, "a0": 225, "a1": -45,
		"bands": [[0, 3, Color(0.8, 0.12, 0.08)]]}],
	"afr":     ["Air / fuel ratio", {"title": "AFR", "lo": 10, "hi": 18, "major": 2, "minor": 1, "a0": 225, "a1": -45,
		"bands": [[15.5, 18, Color(0.8, 0.12, 0.08)], [10, 11, Color(0.9, 0.6, 0.1)]]}],
	"rpm":     ["Tachometer (rpm)", {"title": "RPM", "unit": "x1000", "lo": 0, "hi": 6, "major": 1, "minor": 0.5, "a0": 225, "a1": -45,
		"bands": [[5, 6, Color(0.8, 0.12, 0.08)]]}],
	"oil":     ["Oil pressure (psi)", {"title": "OIL", "unit": "PSI", "lo": 0, "hi": 80, "major": 20, "minor": 10, "a0": 225, "a1": -45,
		"bands": [[0, 10, Color(0.8, 0.12, 0.08)]]}],
	"temp":    ["Water temperature (F)", {"title": "WATER", "unit": "F", "lo": 100, "hi": 260, "major": 40, "minor": 20, "a0": 225, "a1": -45,
		"bands": [[230, 260, Color(0.8, 0.12, 0.08)]]}],
	"volts":   ["Voltmeter", {"title": "VOLTS", "lo": 8, "hi": 16, "major": 2, "minor": 1, "a0": 225, "a1": -45,
		"bands": [[8, 11.5, Color(0.8, 0.12, 0.08)]]}],
	"map":     ["Manifold pressure (kPa)", {"title": "MAP", "unit": "kPa", "lo": 0, "hi": 200, "major": 50, "minor": 25, "a0": 225, "a1": -45}],
	"hp":      ["Power (hp)", {"title": "POWER", "unit": "HP", "lo": 0, "hi": 400, "major": 100, "minor": 50, "a0": 225, "a1": -45}],
	"knock":   ["Knock", {"title": "KNOCK", "lo": 0, "hi": 1, "major": 0.5, "minor": 0.25, "a0": 225, "a1": -45, "numbers": false,
		"labels": [["0", 0.0], ["!", 1.0]], "bands": [[0.5, 1, Color(0.8, 0.12, 0.08)]]}],
	"fuel_flow": ["Fuel flow (gal/h)", {"title": "FLOW", "unit": "GPH", "lo": 0, "hi": 40, "major": 10, "minor": 5, "a0": 225, "a1": -45}],
	"none":    ["- nothing (blank) -", {"title": "", "lo": 0, "hi": 1, "major": 1, "minor": 1, "a0": 225, "a1": -45, "numbers": false}],
}
const ORDER := ["boost", "fuel_psi", "afr", "rpm", "oil", "temp", "volts", "map", "hp", "knock", "fuel_flow", "none"]
const DEFAULT := ["boost", "fuel_psi", "afr"]


## The value of a signal off an engine model (engine_sim.gd).
static func read(sig: String, esim: RefCounted) -> float:
	match sig:
		"boost":
			return (float(esim.map_kpa) - 101.3) * 0.145
		"fuel_psi":
			return fuel_psi(esim)
		"afr":
			return float(esim.afr) if bool(esim.running) else 14.7
		"rpm":
			return float(esim.rpm) / 1000.0
		"oil":
			return float(esim.oil_psi)
		"temp":
			return float(esim.coolant_f)
		"volts":
			return float(esim.volts)
		"map":
			return float(esim.map_kpa)
		"hp":
			return float(esim.power_w) / 745.7
		"knock":
			return float(esim.knock)
		"fuel_flow":
			return float(esim.fuel_flow) * 3600.0 / 2.84       # kg/s -> US gal/h
	return 0.0


## The pump pushes its rated pressure until the engine wants more than it can
## move; then it sags. A carb pump runs ~6 psi, an injection pump ~13.
static func fuel_psi(esim: RefCounted) -> float:
	if not bool(esim.running) and float(esim.rpm) < 100.0:
		return 0.0
	var pump: Dictionary = esim.pdef("fuel_pump")
	if pump.is_empty():
		return 0.0
	var cap: float = float(pump.get("kg_s", 0.02))
	var filt: Dictionary = esim.pdef("fuel_filter")
	if filt.is_empty():
		cap *= 1.1
	var injected: bool = String(esim.pdef("fuel").get("name", "")).to_lower().contains("injection")
	var rated := 13.0 if injected else 6.5
	if cap > 0.03:
		rated += 2.0                 # the high-flow pump
	var use := float(esim.fuel_flow) / maxf(cap, 0.001)
	return rated * clampf(1.25 - use, 0.0, 1.0)


# ------------------------------------------------------------------------------
#  The aeroplane's pod (two gauges under the panel)
# ------------------------------------------------------------------------------
const PLANE_SIGNALS := {
	"boost":   ["Turbo boost (psi)", {"title": "BOOST", "unit": "PSI", "lo": 0, "hi": 15, "major": 5, "minor": 1, "a0": 225, "a1": -45,
		"bands": [[12, 15, Color(0.8, 0.12, 0.08)]]}],
	"fuel_psi": ["Fuel pressure (psi)", {"title": "FUEL", "unit": "PSI", "lo": 0, "hi": 10, "major": 2, "minor": 1, "a0": 225, "a1": -45,
		"bands": [[0, 0.5, Color(0.8, 0.12, 0.08)], [8, 10, Color(0.8, 0.12, 0.08)]]}],
	"rpm":     ["Tachometer (rpm)", {"title": "RPM", "unit": "x100", "lo": 0, "hi": 30, "major": 5, "minor": 1, "a0": 225, "a1": -45,
		"bands": [[27, 30, Color(0.8, 0.12, 0.08)]]}],
	"map":     ["Manifold pressure (inHg)", {"title": "MAP", "unit": "inHg", "lo": 10, "hi": 50, "major": 10, "minor": 5, "a0": 225, "a1": -45}],
	"cht":     ["Cylinder head temp (F)", {"title": "CHT", "unit": "F", "lo": 100, "hi": 500, "major": 100, "minor": 50, "a0": 225, "a1": -45,
		"bands": [[460, 500, Color(0.8, 0.12, 0.08)]]}],
	"egt":     ["Exhaust gas temp (F)", {"title": "EGT", "unit": "F", "lo": 800, "hi": 1700, "major": 300, "minor": 100, "a0": 225, "a1": -45}],
	"oil_t":   ["Oil temperature (F)", {"title": "OIL T", "unit": "F", "lo": 50, "hi": 250, "major": 50, "minor": 25, "a0": 225, "a1": -45,
		"bands": [[240, 250, Color(0.8, 0.12, 0.08)]]}],
	"carb":    ["Carb air temperature (C)", {"title": "CARB", "unit": "C", "lo": -30, "hi": 30, "major": 10, "minor": 5, "a0": 225, "a1": -45,
		"bands": [[-15, 5, Color(0.9, 0.75, 0.1)]]}],
	"flow":    ["Fuel flow (gal/h)", {"title": "FLOW", "unit": "GPH", "lo": 0, "hi": 30, "major": 10, "minor": 5, "a0": 225, "a1": -45}],
	"none":    ["- nothing (blank) -", {"title": "", "lo": 0, "hi": 1, "major": 1, "minor": 1, "a0": 225, "a1": -45, "numbers": false}],
}
const PLANE_ORDER := ["boost", "fuel_psi", "rpm", "map", "cht", "egt", "oil_t", "carb", "flow", "none"]
const PLANE_DEFAULT := ["boost", "fuel_psi"]


static func read_plane(sig: String, e: Object) -> float:
	match sig:
		"boost":
			return float(e.get("boost_psi")) if e.get("boost_psi") != null else 0.0
		"fuel_psi":
			# the engine-driven pump: about 5.5 psi running, a little from the
			# boost pump on the ground, nothing when the lines run dry
			var lf: float = float(e.get("line_fuel"))
			return (5.5 if bool(e.get("running")) else (1.5 if float(e.get("rpm")) > 50.0 else 0.0)) * clampf(lf * 1.2, 0.0, 1.0)
		"rpm":
			return float(e.get("rpm")) / 100.0
		"map":
			return float(e.get("map_inhg"))
		"cht":
			return float(e.get("cht")) * 1.8 + 32.0
		"egt":
			return float(e.get("egt")) * 1.8 + 32.0
		"oil_t":
			return float(e.get("oil_temp")) * 1.8 + 32.0
		"carb":
			return float(e.get("carb_temp"))
		"flow":
			return float(e.get("fuel_flow")) * 3600.0 / 2.72        # kg/s -> US gal/h of avgas
	return 0.0


## Wiring kept per vehicle (user://wiring.cfg), for the planes.
const SAVE := "user://wiring.cfg"


static func load_wiring(key: String, default: Array) -> Array:
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		var w: Array = cf.get_value("w", key, default)
		if w.size() == default.size():
			return w.duplicate()
	return default.duplicate()


static func save_wiring(key: String, w: Array) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE)
	cf.set_value("w", key, w)
	cf.save(SAVE)
