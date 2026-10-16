extends RefCounted
## A vehicle's engine and drivetrain built from its fitted parts (DESIGN_NOTES
## 111), run as a small mean-value engine model every physics tick:
##
##   air in    displacement x rpm x volumetric efficiency (heads, exhaust
##             back-pressure, the rpm curve) x charge density; density from
##             manifold pressure (throttle, intake/carb restriction, turbo
##             boost) and charge temperature (compressor heat, intercooler)
##   turbo     spool follows exhaust energy with lag; the wastegate holds
##             it at the turbo's boost (a worn one creeps over)
##   fuel      what the mixture wants (rich at full throttle), what the pump
##             and filter can deliver: starve it and it goes lean
##   power     from the air and fuel actually burnt, scaled so a healthy
##             stock engine makes its rated horsepower; lean or rich loses
##             power; lean under boost knocks
##   heat      a share of the fuel's energy into the coolant; the radiator
##             takes it out (worse when it's worn, slower when standing)
##   oil       pressure from rpm and engine condition
##   electrics battery charge; the alternator charges it; the starter draws it
##   wear      parts wear with use, faster hot, lean, knocking or over-boosted;
##             a part at 0% has failed
##
## Missing parts matter: no heads, intake, fuel system or pump and it won't
## run; no exhaust manifold and it's deafening and weak; no starter or a
## flat battery and it won't turn over; no transmission or driveshaft and the
## wheels aren't driven.

const Parts = preload("res://scripts/parts.gd")

var key := "pickup"              # Parts.fitted key
var tags: Array = ["pickup", "v8"]
var base_kg := 1650.0            # chassis and body without the drivetrain parts

# state
var running := false
var rpm := 0.0
var map_kpa := 101.0             # manifold pressure
var boost_psi := 0.0
var spool := 0.0                 # 0..1 turbo speed
var afr := 14.7                  # air:fuel actually burning
var knock := 0.0
var power_w := 0.0               # at the flywheel now
var max_power_w := 0.0           # what it would make flat out at this rpm and boost
var coolant_f := 60.0
var oil_psi := 0.0
var battery := 0.9               # state of charge
var volts := 12.5
var fuel_flow := 0.0             # kg/s burnt
var fuel_use_k := 1.0            # how thirsty the carb or injection is (fuel used per fuel burnt)
var air_flow := 0.0              # kg/s
var misfire := 0.0               # 0 smooth .. 1 barely running
var last_fail := ""
var no_wear := false             # a what-if run (the workshop's numbers)
var _air_ref := 1.0
var _mis_t := 0.0

const AMB_KPA := 101.3
const AMB_K := 288.0


func slots() -> Dictionary:
	if not Parts.fitted.has(key):
		Parts.fitted[key] = {}
	return Parts.fitted[key]


func part(slot: String) -> int:
	return int(slots().get(slot, 0))


func pdef(slot: String) -> Dictionary:
	var u := part(slot)
	return Parts.def_of(u) if u > 0 else {}


func pcond(slot: String) -> float:
	var u := part(slot)
	return Parts.cond(u) if u > 0 else 0.0


## Fresh stock parts (a new game), each a little used.
func fit_stock(stock: Dictionary, wear: float = 0.15) -> void:
	var s := slots()
	s.clear()
	for sl in stock.keys():
		var d := String(stock[sl])
		if d != "":
			s[sl] = Parts.make(d, 1.0 - wear * randf_range(0.5, 1.5))
	Parts._dirty = true


func mass_kg() -> float:
	var kg := base_kg
	for sl in slots().keys():
		var d := Parts.def_of(int(slots()[sl]))
		kg += float(d.get("kg", 0.0))
	return kg


## What it's missing that it needs to run, or "".
func cant_run() -> String:
	for sl in ["engine", "heads", "intake", "fuel", "fuel_pump"]:
		if part(sl) <= 0:
			return "no %s" % Parts.SLOT_NAMES[sl]
		if pcond(sl) <= 0.0:
			return "the %s has failed" % Parts.SLOT_NAMES[sl]
	return ""


## Turn the key. Returns what happens.
func try_start(fuel_left: float) -> String:
	if part("battery") <= 0:
		return "Nothing: there's no battery in it."
	if battery < 0.12 or pcond("battery") < 0.05:
		return "Click... click. The battery's flat."
	if part("starter") <= 0:
		return "Nothing turns: there's no starter on it."
	battery -= 0.02
	if randf() > 0.35 + 0.65 * pcond("starter"):
		return "The starter just clicks (it's worn): try again."
	var why := cant_run()
	if why != "":
		return "It cranks and cranks but won't fire: %s." % why
	if fuel_left <= 0.05:
		return "It cranks but won't catch: out of fuel."
	running = true
	rpm = idle_rpm()
	return "Engine running." + ("" if part("exhaust") > 0 else " Deafening - there's no exhaust manifold on it.")


func stop() -> void:
	running = false


func idle_rpm() -> float:
	return float(pdef("engine").get("idle", 800.0))


func redline() -> float:
	return float(pdef("engine").get("redline", 4500.0))


## Which wheels the drivetrain turns: [front, rear].
func driven() -> Array:
	var box := part("transmission") > 0 and pcond("transmission") > 0.0
	var rear := box and part("driveshaft_r") > 0 and part("diff_r") > 0 and pcond("diff_r") > 0.0
	var front := box and part("transfer") > 0 and part("driveshaft_f") > 0 and part("diff_f") > 0 and pcond("diff_f") > 0.0
	return [front, rear]


func top_speed_k() -> float:
	var t := float(pdef("transmission").get("top", 1.0))
	var ratio := float(pdef("diff_r").get("ratio", 4.10))
	return t * 4.10 / ratio


func pull_k() -> float:
	return float(pdef("transmission").get("pull", 1.0)) * float(pdef("diff_r").get("ratio", 4.10)) / 4.10


## One tick. throttle 0..1, rpm from the gearbox, speed m/s (airflow over the
## radiator), lights_amps extra electrical load.
func step(dt: float, throttle: float, rpm_in: float, speed: float, lights_amps: float = 0.0) -> void:
	var eng := pdef("engine")
	if running and cant_run() != "":
		running = false
		last_fail = "The engine dies: %s." % cant_run()
	rpm = rpm_in if running else move_toward(rpm, 0.0, 1500.0 * dt)
	if eng.is_empty():
		power_w = 0.0
		max_power_w = 0.0
		_elec(dt, lights_amps)
		coolant_f = move_toward(coolant_f, 60.0, 0.05 * dt)
		oil_psi = 0.0
		return
	var disp := 5.74 * float(eng["nm"]) / 380.0          # litres, near enough from the torque
	var red := redline()
	var heads := pdef("heads")
	var ex := pdef("exhaust")
	var fuel := pdef("fuel")
	var turbo := pdef("turbo")
	var ic := pdef("intercooler")
	# --- intake: the carb or throttle body restricts flow at high demand -----
	var fuel_cap_hp := float(fuel.get("max_hp", 200.0))
	var demand := rpm / red                                  # rough share of max airflow wanted
	var cap_k := clampf(fuel_cap_hp / maxf(float(eng["hp"]) * 1.15, 1.0), 0.4, 2.5)
	var restrict := clampf(1.0 - 0.35 * pow(demand / cap_k, 2.0), 0.4, 1.0)
	var resp := float(fuel.get("response", 1.0))
	var thr_eff := clampf(pow(throttle, 1.0 / maxf(resp, 0.3)), 0.0, 1.0)
	var map_na := lerpf(32.0, AMB_KPA * restrict, thr_eff)   # idle vacuum .. wide open
	# --- turbo -----------------------------------------------------------------
	boost_psi = 0.0
	var charge_k := AMB_K
	if not turbo.is_empty() and running:
		var tc := pcond("turbo")
		var size := float(turbo.get("size", 1.0))
		# exhaust energy: last tick's fuel flow, against what this turbo needs to light up
		var exh := fuel_flow / maxf(0.006 * size * float(eng["hp"]) / 165.0, 1e-4)
		var want := clampf((exh - 0.35) / 0.65, 0.0, 1.0) * clampf(thr_eff * 1.3, 0.0, 1.0)
		var tau := float(turbo.get("spool", 1.6)) * (1.4 - 0.4 * tc)
		spool = move_toward(spool, want, dt / maxf(tau if want > spool else tau * 0.35, 0.05))
		# a tired wastegate lets it creep over
		var gate := float(turbo.get("psi", 7.0)) * (1.0 + 0.5 * maxf(0.4 - tc, 0.0))
		boost_psi = gate * spool * (0.5 + 0.5 * tc)
		var pr := (map_na + boost_psi * 6.895) / map_na
		charge_k = AMB_K * (1.0 + (pow(pr, 0.286) - 1.0) / 0.7)          # the compressor heats the air it squeezes
		charge_k = lerpf(charge_k, AMB_K + 15.0, float(ic.get("eff", 0.0)) * pcond("intercooler")) if not ic.is_empty() else charge_k
	else:
		spool = move_toward(spool, 0.0, dt / 0.6)
	map_kpa = map_na + boost_psi * 6.895
	# --- air ---------------------------------------------------------------------
	var x := rpm / maxf(red, 1.0)
	var ve_curve := clampf(0.62 + 0.55 * x - 0.45 * x * x, 0.3, 0.9)     # peaks around 60% of redline
	var ve := ve_curve * float(heads.get("flow", 0.8)) * (0.75 + 0.25 * pcond("heads"))
	ve *= float(ex.get("flow", 0.85)) if not ex.is_empty() else 0.85
	if not turbo.is_empty():
		ve *= 1.0 - 0.04 * float(turbo.get("size", 1.0))       # the turbine's back-pressure
	var density := (map_kpa * 1000.0) / (287.0 * charge_k)
	air_flow = disp / 1000.0 * rpm / 120.0 * ve * density if running else 0.0
	# --- fuel ------------------------------------------------------------------
	var want_afr := lerpf(14.7, 12.5, clampf((thr_eff - 0.6) / 0.4, 0.0, 1.0))   # rich for full power (economy: fuel_use_k)
	var need := air_flow / want_afr
	var pump := pdef("fuel_pump")
	var filt := pcond("fuel_filter") if part("fuel_filter") > 0 else 0.6      # no filter: crud gets through, the jets clog
	var cap := float(pump.get("kg_s", 0.0)) * pcond("fuel_pump") * (0.35 + 0.65 * filt)
	fuel_flow = minf(need, cap) if running else 0.0
	fuel_use_k = float(fuel.get("economy", 1.0))
	afr = air_flow / maxf(fuel_flow, 1e-6) if running else 14.7
	# --- combustion --------------------------------------------------------------
	var comb := clampf(1.0 - 0.12 * absf(afr - 12.8) - 0.12 * maxf(afr - 15.0, 0.0), 0.0, 1.05)
	knock = clampf((map_kpa - 120.0) / 60.0, 0.0, 1.0) * clampf((afr - 12.6) / 2.0, 0.0, 1.0)
	knock = maxf(knock, clampf((coolant_f - 235.0) / 30.0, 0.0, 1.0) * clampf((map_kpa - 90.0) / 40.0, 0.0, 1.0))
	var ec := pcond("engine")
	_air_ref = _ref_air(eng, disp)
	var rated := float(eng["hp"]) * 745.7
	var p := rated * (air_flow / maxf(_air_ref, 1e-6)) * comb * (0.55 + 0.45 * ec) * (1.0 - 0.3 * knock)
	var friction := rated * 0.08 * x * x
	# misfire: worn engine, worn heads, very lean, failing pump
	misfire = clampf((0.3 - ec) * 2.0 + maxf(afr - 16.0, 0.0) * 0.3 + (0.25 - pcond("heads")) * 2.0, 0.0, 1.0)
	if misfire > 0.0 and running:
		_mis_t += dt * rpm / 60.0
		p *= 1.0 - misfire * 0.5 * (0.5 + 0.5 * sin(_mis_t * 1.7) * sin(_mis_t * 0.6))
	power_w = maxf(p - friction, 0.0) if running else 0.0
	max_power_w = power_w / maxf(thr_eff, 0.08)
	if running and afr > 18.5 and thr_eff > 0.3:
		running = false
		last_fail = "The engine starves and dies: not enough fuel getting to it (pump, filter?)."
	# --- heat --------------------------------------------------------------------
	var heat_in := fuel_flow * 43.0e6 * 0.30 * (1.0 + 0.4 * knock)                      # W into the coolant
	var rad := pdef("radiator")
	var airflow_k := clampf(0.45 + speed / 15.0, 0.45, 1.6)                              # the fan at a standstill
	var cool := float(rad.get("cooling", 0.0)) * pcond("radiator") * 1500.0 * airflow_k * maxf(coolant_f - 70.0, 0.0)
	var thermostat := clampf((coolant_f - 185.0) / 15.0, 0.03, 1.0)     # opens from 185 F, wide by 200
	coolant_f += (heat_in - cool * thermostat - 40.0 * (coolant_f - 60.0)) / 70000.0 * dt
	coolant_f = clampf(coolant_f, -20.0, 300.0)
	# --- oil -------------------------------------------------------------------
	oil_psi = (8.0 + 45.0 * clampf(rpm / 3000.0, 0.0, 1.2)) * (0.4 + 0.6 * ec) * clampf(1.0 - (coolant_f - 230.0) / 80.0, 0.4, 1.0) if running else move_toward(oil_psi, 0.0, 40.0 * dt)
	_elec(dt, lights_amps)
	_wear(dt, throttle)


func _ref_air(eng: Dictionary, disp: float) -> float:
	# what a healthy stock engine breathes flat out at its power peak
	var red := float(eng.get("redline", 4500.0))
	var r := red * 0.85
	var x := r / red
	var ve := clampf(0.62 + 0.55 * x - 0.45 * x * x, 0.3, 0.9) * 0.85
	return disp / 1000.0 * r / 120.0 * ve * (AMB_KPA * 0.93 * 1000.0) / (287.0 * AMB_K)


func _elec(dt: float, lights_amps: float) -> void:
	var cap := float(pdef("battery").get("ah", 0.0)) * pcond("battery")
	var charge_a := 0.0
	if running and part("alternator") > 0 and rpm > 700.0:
		charge_a = float(pdef("alternator").get("amps", 0.0)) * pcond("alternator")
	var net := charge_a - 12.0 - lights_amps
	if cap > 0.1:
		battery = clampf(battery + net * dt / 3600.0 / cap * (1.0 if net < 0.0 else 0.3), 0.0, 1.0)
	else:
		battery = 0.0
	volts = (11.6 + 1.2 * battery) + (2.1 if charge_a > 15.0 + lights_amps else 0.0) if part("battery") > 0 else 0.0


func _wear(dt: float, throttle: float) -> void:
	if not running or no_wear:
		return
	var load := clampf(power_w / maxf(float(pdef("engine").get("hp", 165.0)) * 745.7, 1.0), 0.0, 2.0)
	var hot := clampf((coolant_f - 235.0) / 25.0, 0.0, 3.0)
	var starved := clampf((10.0 - oil_psi) / 10.0, 0.0, 1.0) * clampf(rpm / 2500.0, 0.0, 1.0)
	var rel := float(pdef("engine").get("rel", 0.85))
	var base := 1.0e-6 * dt * (0.3 + load) * (2.0 - rel)
	Parts.wear(part("engine"), base * (1.0 + 40.0 * hot + 120.0 * knock + 200.0 * starved))
	Parts.wear(part("heads"), base * (0.6 + 30.0 * hot + 60.0 * knock))
	if part("turbo") > 0:
		var over := maxf(boost_psi - float(pdef("turbo").get("psi", 7.0)), 0.0)
		Parts.wear(part("turbo"), base * (2.0 + 20.0 * spool + 80.0 * over))
		if pcond("turbo") <= 0.0 and last_fail == "":
			last_fail = "BANG - the turbo's let go. Smoke and no boost."
	if hot > 1.0 and pcond("engine") <= 0.0:
		running = false
		last_fail = "The engine seizes: it cooked itself."
	Parts.wear(part("radiator"), base * 0.2 * (1.0 + 5.0 * hot))
	Parts.wear(part("fuel_filter"), base * 0.8)
	Parts.wear(part("fuel_pump"), base * 0.3)
	Parts.wear(part("alternator"), base * 0.2)
	Parts.wear(part("transmission"), base * 0.3 * (0.5 + throttle))


## What a set of parts would do, flat out, warmed up (the workshop's bars):
## {hp, nm_k, boost, kg, temp_f (flat out at 50 km/h), ok (why not, or "")}
static func estimate(fitted: Dictionary, tags: Array) -> Dictionary:
	var sim = load("res://scripts/engine_sim.gd").new()
	sim.key = "_estimate"
	sim.tags = tags
	sim.no_wear = true
	Parts.fitted["_estimate"] = fitted.duplicate()
	var out := {"hp": 0.0, "boost": 0.0, "kg": sim.mass_kg(), "temp_f": 0.0, "ok": sim.cant_run(), "top_k": sim.top_speed_k()}
	if out["ok"] == "":
		sim.running = true
		sim.battery = 1.0
		var r: float = sim.redline() * 0.82
		sim.coolant_f = 195.0
		for i in range(240):
			sim.step(0.05, 1.0, r, 14.0)
			if not sim.running:
				out["ok"] = sim.last_fail
				break
		out["hp"] = sim.power_w / 745.7
		out["boost"] = sim.boost_psi
		# where the temperature settles, working this hard at 50 km/h
		var heat_in: float = sim.fuel_flow * 43.0e6 * 0.30 * (1.0 + 0.4 * sim.knock)
		var c: float = float(sim.pdef("radiator").get("cooling", 0.0)) * sim.pcond("radiator") * 1500.0 * 1.38
		out["temp_f"] = maxf((heat_in + c * 70.0 + 40.0 * 60.0) / (c + 40.0), 190.0)     # the thermostat holds it at 190 if it can
		out["afr"] = sim.afr
	Parts.fitted.erase("_estimate")
	return out
