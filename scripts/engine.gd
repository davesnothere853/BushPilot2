extends RefCounted
## Piston engine and the systems around it: ignition, starter and battery,
## fuel tanks and selector, mixture, carburettor icing, constant-speed propeller,
## temperatures, oil, and wear.
##
## Every switch and lever a pilot can touch is a plain variable here, so the
## keyboard, the 3D cockpit (and later VR hands) all drive the same thing.
## update() advances it by one physics tick.

signal event(text: String)

const MAGS_OFF := 0
const MAGS_R := 1
const MAGS_L := 2
const MAGS_BOTH := 3
const MAGS_START := 4
const MAG_NAMES: Array[String] = ["OFF", "R", "L", "BOTH", "START"]

const FUEL_OFF := 0
const FUEL_LEFT := 1
const FUEL_RIGHT := 2
const FUEL_BOTH := 3
const FUEL_NAMES: Array[String] = ["OFF", "LEFT", "RIGHT", "BOTH"]

# --- this engine: a tired 230 hp flat-six with a constant-speed propeller ------
var rated_power := 172000.0       # watts at sea level, full throttle, 2,600 rpm
var rated_rpm := 2600.0
var redline_rpm := 2700.0
var cht_red := 238.0              # cylinder head temperature limit, deg C (460 F)
var oil_temp_red := 116.0         # 240 F
var oil_capacity := 12.0          # US quarts
var tank_capacity := 75.0         # kg per wing tank

# --- pilot controls -------------------------------------------------------------------
var master := true
var alternator := true
var mags := MAGS_BOTH
var fuel_selector := FUEL_BOTH
var mixture := 1.0                # 1 = full rich, 0 = idle cut-off
var prop_lever := 1.0             # 1 = high rpm (fine pitch)
var carb_heat := false
var cowl_flaps := 0.5             # 0 closed, 1 open
var throttle := 0.0               # set by the aeroplane every tick

# --- what the engine is doing ------------------------------------------------------
var running := false
var rpm := 0.0
var map_inhg := 29.9              # manifold pressure
var power := 0.0                  # watts delivered to the propeller
var cht := 15.0                   # deg C
var _shock_time := 0.0            # seconds of hard cooling in a row
var egt := 15.0
var oil_temp := 15.0
var oil_press := 0.0              # psi
var carb_temp := 15.0
var fuel_flow := 0.0              # kg per second
var carb_ice := 0.0               # 0..1
var prime := 0.0                  # primer strokes of fuel sitting in the intake
var line_fuel := 1.0              # 1 = lines full; falls when the tanks run dry
var battery := 0.9                # state of charge 0..1
var volts := 12.4
var amps := 0.0
var cranking := false
var flooded := false
var roughness := 0.0              # 0 smooth .. 1 shaking itself apart
var best_mixture := 1.0           # lever position that gives best power at this altitude

# --- fuel ------------------------------------------------------------------------------
var tank_left := 55.0             # kg
var tank_right := 55.0

# --- wear ------------------------------------------------------------------------------
var hours := 1840.0               # hours since overhaul
var health := 0.85                # 1 = fresh overhaul, 0 = seized
var plug_fouling := 0.0           # 0..1
var oil_qts := 10.0
var water_in_fuel := 0.0          # litres of water sitting in the tanks (sumped on preflight)

# --- the parts, one by one (looked at and serviced with the cowling open) ----
var cylinders := 6
var comp: Array = []               # compression per cylinder, out of 80 psi
var plug_foul: Array = []          # two plugs a cylinder: top, bottom, top, bottom...
var plug_wear: Array = []          # electrode wear 0 new .. 1 worn out
var mag_cond := [0.9, 0.88]        # left, right magneto: 1 new, under 0.3 misfiring
var oil_life := 0.7                # 1 fresh oil .. 0 black sludge
var oil_hours := 15.0              # hours since the last oil change
var oil_filter := 0.7              # 1 new .. 0 clogged (bypassing)
var air_filter := 0.25             # dirt: 0 clean .. 1 choked
var belt := 0.8                    # alternator belt: 1 new .. 0 snapped
var exhaust := 0.9                 # exhaust and muffler: low means cracks
var extra_amps := 0.0              # lights and radios, set by the plane
## Parts (DESIGN_NOTES 111): the radial is the aeroplane's own; its carburettor
## and a turbo (yes, off the pickup) come from parts.gd under this key.
var parts_key := ""
var boost_psi := 0.0
var spool := 0.0
var detonation := 0.0
var dusty := false                 # set by the plane: running on a dirt or gravel strip
var _mag_flicker := 0.0
var _crank_time := 0.0
var _cht_prev := 15.0
var _rough_phase := 0.0
var _warned := {}


## Make sure there is an entry per cylinder and plug (a new engine, or an old save).
const Parts = preload("res://scripts/parts.gd")


func _part_uid(slot: String) -> int:
	if parts_key == "" or not Parts.fitted.has(parts_key):
		return 0
	return int((Parts.fitted[parts_key] as Dictionary).get(slot, 0))


func _part_def(slot: String) -> Dictionary:
	var u := _part_uid(slot)
	return Parts.def_of(u) if u > 0 else {}


func _part_cond(slot: String) -> float:
	var u := _part_uid(slot)
	return Parts.cond(u) if u > 0 else 0.0


func ensure_parts() -> void:
	while comp.size() < cylinders:
		comp.append(randf_range(72.0, 78.0))
	while plug_foul.size() < cylinders * 2:
		plug_foul.append(clampf(plug_fouling + randf_range(-0.05, 0.1), 0.0, 1.0))
	while plug_wear.size() < cylinders * 2:
		plug_wear.append(randf_range(0.2, 0.45))
	comp.resize(cylinders)
	plug_foul.resize(cylinders * 2)
	plug_wear.resize(cylinders * 2)


## How well one magneto fires: 1 fine; a worn one starts to miss.
func mag_eff(i: int) -> float:
	var c: float = mag_cond[i]
	if c > 0.35:
		return 1.0
	if c <= 0.0:
		return 0.0
	# Misses come and go.
	return 1.0 if sin(_mag_flicker * (3.1 + i)) > (0.35 - c) * 4.0 - 1.0 else 0.0


func avg_comp() -> float:
	var t := 0.0
	for c in comp:
		t += float(c)
	return t / maxf(float(comp.size()), 1.0)


func parts_to_dict() -> Dictionary:
	return {"comp": comp, "plug_foul": plug_foul, "plug_wear": plug_wear, "mag": mag_cond, "oil_life": oil_life,
		"oil_hours": oil_hours, "oil_filter": oil_filter, "air_filter": air_filter, "belt": belt, "exhaust": exhaust}


func parts_from_dict(d: Dictionary) -> void:
	comp = (d.get("comp", comp) as Array).duplicate()
	plug_foul = (d.get("plug_foul", plug_foul) as Array).duplicate()
	plug_wear = (d.get("plug_wear", plug_wear) as Array).duplicate()
	mag_cond = (d.get("mag", mag_cond) as Array).duplicate()
	oil_life = float(d.get("oil_life", oil_life))
	oil_hours = float(d.get("oil_hours", oil_hours))
	oil_filter = float(d.get("oil_filter", oil_filter))
	air_filter = float(d.get("air_filter", air_filter))
	belt = float(d.get("belt", belt))
	exhaust = float(d.get("exhaust", exhaust))
	ensure_parts()


## Wear a random cylinder (heat, detonation, oil starvation hit one hardest).
func _hurt_cylinder(amount: float) -> void:
	if comp.is_empty():
		return
	var i := randi() % comp.size()
	comp[i] = maxf(float(comp[i]) - amount, 5.0)


func total_fuel() -> float:
	return tank_left + tank_right


func set_fuel(kg: float) -> void:
	var each := clampf(kg * 0.5, 0.0, tank_capacity)
	tank_left = each
	tank_right = each


## Hot and running, ready to go.
func set_running(oat_c: float) -> void:
	master = true
	alternator = true
	mags = MAGS_BOTH
	fuel_selector = FUEL_BOTH
	mixture = 1.0
	prop_lever = 1.0
	carb_heat = false
	cowl_flaps = 1.0
	running = true
	rpm = 650.0
	cht = oat_c + 60.0
	egt = oat_c + 350.0
	oil_temp = oat_c + 45.0
	oil_press = 60.0
	carb_ice = 0.0
	prime = 0.0
	line_fuel = 1.0
	flooded = false
	cranking = false
	_cht_prev = cht
	_warned.clear()


## Parked and shut down, everything off, engine at outside air temperature.
func set_cold_and_dark(oat_c: float) -> void:
	master = false
	alternator = false
	mags = MAGS_OFF
	fuel_selector = FUEL_BOTH
	mixture = 0.0
	prop_lever = 1.0
	carb_heat = false
	cowl_flaps = 1.0
	running = false
	rpm = 0.0
	power = 0.0
	fuel_flow = 0.0
	map_inhg = 29.9
	cht = oat_c
	egt = oat_c
	oil_temp = oat_c
	oil_press = 0.0
	carb_ice = 0.0
	prime = 0.0
	line_fuel = 1.0
	flooded = false
	cranking = false
	_cht_prev = cht
	_warned.clear()


func stop(reason: String = "") -> void:
	if running and reason != "":
		event.emit(reason)
	running = false
	cranking = false


func _warn(key: String, text: String) -> void:
	if not _warned.get(key, false):
		_warned[key] = true
		event.emit(text)


func _clear_warning(key: String) -> void:
	_warned.erase(key)


## Mixture lever position that gives best power for this air density.
static func best_mixture_for(sigma: float) -> float:
	return clampf(0.40 + 0.60 * sigma, 0.45, 1.0)


# ------------------------------------------------------------------------------
#  One tick
#  sigma: air density relative to standard sea level
#  airspeed: forward speed through the air, m/s
#  humidity: 0..1, drives carburettor icing
#  automatic: the game handles mixture, propeller, carb heat and cowl flaps
#  realism: 0 sim-lite, 1 realistic (how hard icing and abuse bite)
# ------------------------------------------------------------------------------
func update(dt: float, sigma: float, pressure_pa: float, oat_c: float, airspeed: float,
		humidity: float, automatic: bool, realism: int) -> void:
	var amb_inhg := pressure_pa / 3386.39
	best_mixture = best_mixture_for(sigma)
	var power_frac := power / rated_power

	if automatic:
		_auto_manage(power_frac)

	# --- electrics ------------------------------------------------------------------
	var bus_on := master and battery > 0.01
	cranking = mags == MAGS_START and bus_on and battery > 0.06
	var load_amps := 6.0 + extra_amps if bus_on else 0.0
	var charge_amps := 0.0
	if bus_on and alternator and running and rpm > 900.0 and belt > 0.0:
		charge_amps = clampf((1.0 - battery) * 120.0, 4.0, 60.0)
	var starter_amps := 160.0 if cranking else 0.0
	amps = charge_amps - load_amps - starter_amps if bus_on else 0.0
	battery = clampf(battery + amps * dt / (35.0 * 3600.0), 0.0, 1.0)
	if bus_on:
		volts = 14.1 if charge_amps > 0.0 else (11.4 + 1.2 * battery - (1.6 if cranking else 0.0))
	else:
		volts = 0.0
	if mags == MAGS_START and master and battery <= 0.06:
		_warn("battery", "The starter just clicks. The battery is flat.")

	# --- fuel to the engine -------------------------------------------------------------
	var feed_ok := false
	match fuel_selector:
		FUEL_LEFT:
			feed_ok = tank_left > 0.05
		FUEL_RIGHT:
			feed_ok = tank_right > 0.05
		FUEL_BOTH:
			feed_ok = tank_left > 0.05 or tank_right > 0.05
	if feed_ok:
		line_fuel = move_toward(line_fuel, 1.0, dt * 0.5)
	elif running:
		line_fuel = move_toward(line_fuel, 0.0, dt / 10.0)   # about ten seconds left in the lines

	# --- ignition ----------------------------------------------------------------------
	ensure_parts()
	_mag_flicker += dt * 7.0
	# Plugs: the average fouling and wear decide how well they fire.
	var pf := 0.0
	var pw := 0.0
	for k in range(plug_foul.size()):
		pf += float(plug_foul[k])
		pw += float(plug_wear[k])
	pf /= maxf(float(plug_foul.size()), 1.0)
	pw /= maxf(float(plug_wear.size()), 1.0)
	plug_fouling = clampf(pf + 0.35 * maxf(pw - 0.6, 0.0), 0.0, 1.0)
	var ml := mag_eff(0)
	var mr := mag_eff(1)
	var ign := 0.0
	match mags:
		MAGS_L:
			ign = (0.955 - 0.12 * plug_fouling) * ml
		MAGS_R:
			ign = (0.955 - 0.12 * plug_fouling) * mr
		MAGS_BOTH, MAGS_START:
			ign = maxf(ml, mr) * (1.0 - 0.04 * plug_fouling) - 0.045 * (1.0 - minf(ml, mr))

	# --- mixture -----------------------------------------------------------------------
	var r := 0.0
	if mixture > 0.04:
		r = mixture / best_mixture
	var mix_factor := 0.0
	if r >= 0.55:
		if r < 1.0:
			mix_factor = 1.0 - 2.2 * (1.0 - r) * (1.0 - r)
		else:
			mix_factor = maxf(1.0 - 0.6 * (r - 1.0) * (r - 1.0), 0.0)
	# Water in the fuel makes it cough and stumble.
	if water_in_fuel > 0.05 and running:
		mix_factor *= 1.0 - clampf(water_in_fuel, 0.0, 0.8) * (0.5 + 0.5 * sin(_rough_phase * 1.7))

	# --- carburettor ice ---------------------------------------------------------------
	carb_temp = oat_c - 9.0 * (1.0 - throttle) - 3.0 + (38.0 if carb_heat else 0.0)
	if running and not carb_heat and carb_temp > -12.0 and carb_temp < 16.0:
		var band := 1.0 - absf(carb_temp - 2.0) / 14.0
		var rate := humidity * band * 0.0035 * (1.0 if realism == 1 else 0.5) * float(_part_def("fuel").get("ice", 1.0))
		carb_ice = clampf(carb_ice + rate * dt, 0.0, 1.0)
	if carb_heat or not running:
		carb_ice = move_toward(carb_ice, 0.0, dt * (0.03 if carb_heat else 0.01))
	if carb_ice > 0.35:
		_warn("ice", "The engine is losing power and running rough. Carburettor ice? Try carb heat.")
	elif carb_ice < 0.1:
		_clear_warning("ice")

	# --- manifold pressure ------------------------------------------------------------
	if running:
		var opening := pow(clampf(throttle, 0.0, 1.0), 0.75 / float(_part_def("fuel").get("response", 1.0)))
		map_inhg = lerpf(9.5 * amb_inhg / 29.92, amb_inhg - 0.7, opening) * (1.0 - 0.5 * carb_ice)
		# A turbo: spools on the exhaust (lags behind the throttle), packs the
		# manifold above outside air - and keeps doing it up high.
		var tdef := _part_def("turbo")
		if not tdef.is_empty():
			var tc := _part_cond("turbo")
			var want := clampf((power_frac - 0.25) / 0.5, 0.0, 1.0) * clampf(throttle * 1.3, 0.0, 1.0)
			var tau := float(tdef.get("spool", 1.6)) * (1.4 - 0.4 * tc)
			spool = move_toward(spool, want, dt / maxf(tau if want > spool else tau * 0.35, 0.05))
			var gate := float(tdef.get("psi", 7.0)) * (1.0 + 0.5 * maxf(0.4 - tc, 0.0))
			boost_psi = gate * spool * (0.5 + 0.5 * tc)
			map_inhg += boost_psi * 2.036
		else:
			spool = move_toward(spool, 0.0, dt / 0.6)
			boost_psi = 0.0
	elif cranking:
		map_inhg = lerpf(amb_inhg - 2.0, amb_inhg, throttle)
	else:
		map_inhg = move_toward(map_inhg, amb_inhg, dt * 8.0)

	# --- power -----------------------------------------------------------------------
	_rough_phase += dt * (rpm / 60.0) * 0.37
	roughness = 0.0
	if running:
		var volumetric := clampf((map_inhg - 8.0) / (29.92 - 8.0), 0.0, 1.9) * (1.0 - 0.14 * air_filter * air_filter)
		if boost_psi > 0.1:
			# the compressor heats the charge it squeezes: denser, but hotter
			volumetric *= 1.0 - 0.012 * boost_psi
		# detonation: high boost, hot heads, or lean
		detonation = clampf((map_inhg - 36.0) / 10.0, 0.0, 1.0) * clampf((cht - 190.0) / 40.0 + maxf(0.95 - r, 0.0) * 3.0, 0.0, 1.0)
		if detonation > 0.05:
			_warn("detonation", "The engine's pinging under boost: detonation! Richen it, cool it, or pull the power back.")
			health -= 4.0e-5 * detonation * dt
			if parts_key != "" and _part_uid("turbo") > 0:
				Parts.wear(_part_uid("turbo"), 2.0e-5 * dt)
		else:
			_clear_warning("detonation")
		var wear_factor := (0.86 + 0.14 * health) * clampf(avg_comp() / 76.0, 0.5, 1.03)
		var heat_loss := 0.91 if carb_heat else 1.0
		var indicated := rated_power * 1.06 * volumetric * (rpm / rated_rpm) * mix_factor * ign * wear_factor * heat_loss * (1.0 - 0.25 * plug_fouling)
		var friction := rated_power * 0.06 * pow(rpm / rated_rpm, 2.0)
		var weak_cyl := 0.0
		for c in comp:
			weak_cyl = maxf(weak_cyl, (62.0 - float(c)) / 40.0)
		roughness = clampf(0.5 * carb_ice + 0.6 * plug_fouling + (1.0 - mix_factor) * 1.2 + (0.25 if ign < 0.99 else 0.0) + (0.4 if health < 0.2 else 0.0) + water_in_fuel + maxf(weak_cyl, 0.0), 0.0, 1.0)
		# A rough engine stumbles: power dips in and out.
		var stumble := 1.0 - roughness * 0.35 * (0.5 + 0.5 * sin(_rough_phase) * sin(_rough_phase * 2.3 + 1.0))
		power = maxf(indicated * stumble - friction, 0.0)
	else:
		power = 0.0
	power_frac = power / rated_power

	# --- propeller and rpm --------------------------------------------------------------
	# scaled to the engine's own rated rpm (the numbers were the Wolverine's
	# 2600: the biplane's 2100 rpm radial oversped on them)
	var rk := rated_rpm / 2600.0
	var governed := lerpf(1700.0, 2600.0, prop_lever) * rk
	var target := 0.0
	if running:
		# Below the governor's range the blades sit on the fine-pitch stop.
		var fine := (2450.0 * pow(maxf(power_frac, 0.0), 0.4) + maxf(airspeed, 0.0) * 13.0) * rk
		target = minf(governed, fine)
		target = maxf(target, 420.0 if mix_factor > 0.0 else 0.0)
	elif cranking:
		target = 230.0 if battery > 0.15 else 120.0
	else:
		target = clampf(airspeed * 14.0 - 250.0, 0.0, 1100.0) if health > 0.0 else 0.0
	rpm = lerpf(rpm, target, clampf((2.0 if running else 1.2) * dt, 0.0, 1.0))
	if running and rpm > redline_rpm + 60.0:
		_warn("overspeed", "Overspeed! Pull the power back.")
		health -= 2.0e-5 * dt
	elif rpm < redline_rpm:
		_clear_warning("overspeed")

	# --- starting --------------------------------------------------------------------
	if not running:
		if cranking:
			_crank_time += dt
			var need := clampf((25.0 - cht) / 40.0, 0.0, 1.3) * 3.0     # strokes a cold engine wants
			var wet := prime + (0.6 if throttle > 0.04 and throttle < 0.4 else 0.15)
			if prime > need + 4.0:
				flooded = true
			if flooded:
				# Clearing a flooded engine: throttle wide open, mixture cut off, keep cranking.
				if throttle > 0.85 and mixture < 0.05:
					prime = maxf(prime - 0.6 * dt, 0.0)
				if prime < need + 2.0:
					flooded = false
					event.emit("The flood has cleared. Set the mixture rich, throttle cracked, and try again.")
			elif ign > 0.0 and line_fuel > 0.05 and mixture > 0.05 and wet >= need * 0.8 and _crank_time > 1.0 + 0.5 * need:
				running = true
				rpm = 520.0
				prime = 0.0
				_crank_time = 0.0
				_warned.clear()
				event.emit("The engine catches and settles to idle.")
			prime = maxf(prime - 0.15 * dt, 0.0)
			if _crank_time > 12.0 and not flooded:
				_warn("nostart", _no_start_hint(ign, need, wet))
		else:
			_crank_time = 0.0
			_clear_warning("nostart")
	else:
		_crank_time = 0.0
		if ign <= 0.0:
			stop("The engine stops: magnetos off.")
		elif mixture <= 0.04:
			stop("The engine stops: mixture at idle cut-off.")
		elif line_fuel <= 0.0:
			stop("The engine quits: no fuel is reaching it. Check the fuel selector and tanks.")
		elif mix_factor <= 0.0:
			stop("The engine quits: the mixture is far too lean.")
		elif carb_ice > 0.97:
			stop("The engine quits: the carburettor has iced up.")
		elif parts_key != "" and _part_uid("fuel") <= 0:
			stop("The engine quits: there's no carburettor on it.")
		elif health <= 0.0:
			stop("The engine seizes with a bang.")
		elif rpm < 300.0:
			stop("The engine stalls.")

	# --- fuel burn ---------------------------------------------------------------------
	fuel_flow = 0.0
	if running:
		var air := rated_power * clampf((map_inhg - 8.0) / 21.92, 0.0, 1.2) * (rpm / rated_rpm)
		fuel_flow = maxf(air * clampf(r, 0.5, 1.6) * 8.2e-8, 9.0e-4) * float(_part_def("fuel").get("economy", 1.0))
		var burn := fuel_flow * dt
		match fuel_selector:
			FUEL_LEFT:
				tank_left = maxf(tank_left - burn, 0.0)
			FUEL_RIGHT:
				tank_right = maxf(tank_right - burn, 0.0)
			_:
				if tank_left > 0.05 and tank_right > 0.05:
					tank_left -= burn * 0.5
					tank_right -= burn * 0.5
				elif tank_left > 0.05:
					tank_left = maxf(tank_left - burn, 0.0)
				else:
					tank_right = maxf(tank_right - burn, 0.0)
		var low := (tank_left + tank_right) < 20.0
		if low:
			_warn("lowfuel", "Fuel is getting low: about %d gallons left." % int((tank_left + tank_right) / 2.72))

	# --- temperatures -----------------------------------------------------------------
	var cool := clampf(airspeed / 45.0, 0.25, 1.4) + 0.35 * cowl_flaps
	if running:
		cool += 0.3 * clampf(power_frac, 0.0, 1.0) * clampf(1.0 - airspeed / 30.0, 0.0, 1.0)   # prop blast on the ground
	var lean_heat := 1.0 + 0.22 * exp(-pow((r - 0.9) / 0.14, 2.0)) - 0.35 * maxf(r - 1.05, 0.0)
	var cht_target := oat_c
	var egt_target := oat_c
	var oil_target := oat_c
	if running:
		cht_target = oat_c + 250.0 * pow(maxf(power_frac, 0.0), 0.8) * lean_heat / cool + 25.0 + 2.2 * boost_psi
		egt_target = oat_c + (380.0 + 330.0 * pow(maxf(power_frac, 0.01), 0.3)) * (1.0 - 0.9 * pow(clampf(r - 0.87, -1.0, 1.0), 2.0))
		oil_target = oat_c + (55.0 + 45.0 * power_frac) / (0.7 + 0.3 * minf(cool, 1.4)) + 8.0 * (1.0 - oil_life) + 6.0 * (1.0 - oil_filter)
	cht += (cht_target - cht) * clampf(dt / 110.0, 0.0, 1.0)
	egt += (egt_target - egt) * clampf(dt / 6.0, 0.0, 1.0)
	oil_temp += (oil_target - oil_temp) * clampf(dt / 150.0, 0.0, 1.0)
	var cooling_rate := (cht - _cht_prev) / maxf(dt, 0.0001)
	_cht_prev = cht

	var visc := clampf(1.6 - oil_temp / 100.0, 0.85, 1.9)
	var qty := clampf((oil_qts / oil_capacity - 0.33) / 0.33, 0.0, 1.0)
	if running or cranking:
		oil_press = clampf(64.0 * (1.0 - exp(-rpm / 700.0)) * visc * qty * (0.8 + 0.2 * health), 0.0, 115.0)   # the relief valve caps it above idle
	else:
		oil_press = move_toward(oil_press, 0.0, dt * 30.0)

	# --- wear and abuse ----------------------------------------------------------------
	var abuse := 1.0 if realism == 1 else 0.4
	if running:
		hours += dt / 3600.0
		var h := dt / 3600.0
		oil_hours += h
		oil_life = maxf(oil_life - h / 50.0 * (1.5 if oil_temp > oil_temp_red - 10.0 else 1.0), 0.0)
		oil_filter = maxf(oil_filter - h / 60.0, 0.0)
		air_filter = minf(air_filter + h / (25.0 if dusty else 120.0), 1.0)
		var was_belt := belt
		belt = maxf(belt - h / 500.0, 0.0)
		if was_belt > 0.0 and belt <= 0.0:
			event.emit("The ammeter drops to discharge: the alternator belt has gone.")
		exhaust = maxf(exhaust - h / 900.0, 0.0)
		for mi in range(2):
			mag_cond[mi] = maxf(float(mag_cond[mi]) - h / 700.0, 0.0)
		for k in range(plug_wear.size()):
			plug_wear[k] = minf(float(plug_wear[k]) + h / 400.0, 1.0)
		for c in range(comp.size()):
			comp[c] = maxf(float(comp[c]) - h * 0.006, 5.0)
		# Old oil and a clogged filter wear the bearings.
		health -= h * 0.02 * (1.0 - oil_life) * (1.5 - 0.5 * oil_filter) * abuse
		oil_qts = maxf(oil_qts - (0.08 + 0.3 * (1.0 - health)) / 3600.0 * dt, 0.0)
		if cht > cht_red:
			health -= (cht - cht_red) * 3.0e-6 * dt * abuse
			_hurt_cylinder((cht - cht_red) * 2.0e-3 * dt * abuse)
			_warn("cht", "Cylinder head temperature is in the red. Open the cowl flaps, enrich, or ease the power.")
		elif cht < cht_red - 15.0:
			_clear_warning("cht")
		if power_frac > 0.72 and r < 0.82:
			health -= 4.0e-5 * dt * abuse
			_hurt_cylinder(0.02 * dt * abuse)
			_warn("detonation", "Detonation! The mixture is too lean for this much power. Enrich it.")
		elif r > 0.9:
			_clear_warning("detonation")
		# Shock cooling only bites in the extreme case: a hot engine chopped to idle
		# in a fast descent through cold air, kept up for a while. Normal power
		# reductions never trigger it, and only Realistic mode does any harm.
		if cooling_rate < -1.5 and airspeed > 45.0 and oat_c < 5.0:
			_shock_time += dt
		else:
			_shock_time = maxf(_shock_time - dt * 2.0, 0.0)
		if _shock_time > 12.0 and realism == 1:
			health -= 4.0e-6 * dt
			_warn("shock", "Engine cooling fast in the cold descent. Leave a little power on.")
		elif _shock_time < 2.0:
			_clear_warning("shock")
		if oil_press < 15.0 and rpm > 900.0:
			health -= 1.2e-4 * dt * abuse
			_warn("oil", "Oil pressure is low!")
		elif oil_press > 25.0:
			_clear_warning("oil")
		if oil_temp > oil_temp_red:
			health -= 1.0e-5 * dt * abuse
		# Long rich idling fouls the plugs; running lean at power burns them clean.
		if r > 1.2 and power_frac < 0.2:
			for k in range(plug_foul.size()):
				plug_foul[k] = clampf(float(plug_foul[k]) + 6.0e-4 * dt * (1.3 if k % 2 == 1 else 0.8), 0.0, 1.0)
		elif r < 1.08 and power_frac > 0.45:
			for k in range(plug_foul.size()):
				plug_foul[k] = clampf(float(plug_foul[k]) - 2.0e-3 * dt, 0.0, 1.0)
		if oil_temp < oat_c + 15.0 and power_frac > 0.8:
			health -= 4.0e-6 * dt * abuse     # full power on cold, thick oil
	health = clampf(health, 0.0, 1.0)


func _auto_manage(power_frac: float) -> void:
	master = true
	alternator = true
	if mags != MAGS_START:
		mags = MAGS_BOTH
	if fuel_selector == FUEL_OFF:
		fuel_selector = FUEL_BOTH
	if running:
		mixture = best_mixture if power_frac > 0.25 else minf(1.0, best_mixture + 0.15)
	prop_lever = 1.0 if throttle > 0.75 else 0.85
	if carb_ice > 0.2:
		carb_heat = true
	elif carb_ice < 0.02:
		carb_heat = false
	cowl_flaps = clampf((cht - 160.0) / 50.0, 0.0, 1.0)
	if throttle > 0.8 and power_frac > 0.6:
		cowl_flaps = maxf(cowl_flaps, 0.6)


func _no_start_hint(ign: float, need: float, wet: float) -> String:
	if ign <= 0.0:
		return "Still not firing. The magnetos need to be on."
	if line_fuel <= 0.05:
		return "Still not firing. No fuel is reaching the engine: check the fuel selector."
	if mixture <= 0.05:
		return "Still not firing. The mixture is at idle cut-off: push it to rich."
	if wet < need * 0.8:
		return "Still not firing. A cold engine needs priming first (about %d strokes)." % int(ceil(need))
	return "Still not firing. Keep cranking, or check the throttle is cracked open a little."
