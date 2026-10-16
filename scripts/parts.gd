extends RefCounted
## Engine and drivetrain parts (DESIGN_NOTES 111): what each kind of part is
## (CATALOG) and every real one in the world (registry), each with its own
## condition. A part in your hands or on the ground is an inventory item
## "part:<uid>"; one bolted into a vehicle is held by that vehicle's
## drivetrain (drivetrain.gd). Add a part by adding a CATALOG entry.
##
## CATALOG entry:
##   name, slot, kg, price
##   fits:      what it bolts to (an engine family, "pickup", "truck" ...)
##   and stats by slot:
##     engine:       family, hp, nm (torque), redline, idle, sound, rel (reliability 0..1)
##     heads:        family, flow (x power)
##     intake:       family, ports ("2v" / "4v")
##     fuel:         ports it needs, max_hp (what it can feed), response (throttle), economy (x fuel)
##     turbo:        psi (boost), spool (s to full), needs exhaust flange "turbo"
##     exhaust:      family, flow (x power), flange ("" or "turbo"), loud
##     radiator:     cooling
##     alternator:   amps
##     battery:      ah
##     starter:      -
##     transmission: top (x top speed), pull (x low-gear grunt), gears
##     transfer:     -
##     driveshaft:   end ("front" / "rear")
##     diff:         end, ratio

const SAVE := "user://parts.cfg"

const SLOTS := ["engine", "heads", "intake", "fuel", "fuel_pump", "fuel_filter", "turbo", "intercooler", "exhaust", "radiator", "alternator", "battery", "starter",
	"transmission", "transfer", "driveshaft_f", "driveshaft_r", "diff_f", "diff_r", "locker_f", "locker_r", "lift", "tyres"]
const SLOT_NAMES := {"engine": "engine (long block)", "heads": "cylinder heads", "intake": "intake manifold", "fuel": "carburettor / injection",
	"turbo": "turbocharger", "intercooler": "intercooler", "fuel_pump": "fuel pump", "fuel_filter": "fuel filter", "exhaust": "exhaust manifolds", "radiator": "radiator", "alternator": "alternator", "battery": "battery",
	"starter": "starter", "transmission": "transmission", "transfer": "transfer case", "driveshaft_f": "front driveshaft",
	"driveshaft_r": "rear driveshaft", "diff_f": "front axle / diff", "diff_r": "rear axle / diff",
	"locker_f": "front locker", "locker_r": "rear locker", "lift": "suspension lift", "tyres": "tyres", "susp": "suspension"}

const CATALOG := {
	# --- small-block V8s (the pickup) ---
	"sb350": {"name": "350 V8 long block", "slot": "engine", "kg": 250.0, "price": 1400, "fits": ["v8"],
		"family": "sb", "hp": 165.0, "nm": 380.0, "redline": 4600.0, "idle": 900.0, "sound": "v8cam", "rel": 0.85},
	"sb400": {"name": "400 V8 long block (stroker)", "slot": "engine", "kg": 262.0, "price": 2100, "fits": ["v8"],
		"family": "sb", "hp": 190.0, "nm": 445.0, "redline": 4400.0, "idle": 850.0, "sound": "v8cam", "rel": 0.8},
	"bb460": {"name": "460 big-block V8 long block", "slot": "engine", "kg": 325.0, "price": 2600, "fits": ["v8"],
		"family": "bb", "hp": 225.0, "nm": 530.0, "redline": 4300.0, "idle": 800.0, "sound": "v8cam", "rel": 0.82},
	"i6d78": {"name": "7.8 L inline-six diesel long block", "slot": "engine", "kg": 640.0, "price": 5200, "fits": ["truck"],
		"family": "i6d", "hp": 210.0, "nm": 820.0, "redline": 2300.0, "idle": 650.0, "sound": "diesel", "rel": 0.95},
	"i6d10": {"name": "10 L inline-six diesel long block", "slot": "engine", "kg": 820.0, "price": 8900, "fits": ["truck"],
		"family": "i6d", "hp": 280.0, "nm": 1150.0, "redline": 2200.0, "idle": 620.0, "sound": "diesel", "rel": 0.93},
	"i6d14": {"name": "14 L inline-six diesel long block (big cam)", "slot": "engine", "kg": 1150.0, "price": 14500, "fits": ["truck"],
		"family": "i6d", "hp": 400.0, "nm": 1750.0, "redline": 2100.0, "idle": 600.0, "sound": "diesel", "rel": 0.92},
	# --- the trucks' diesel (DESIGN_NOTES 125) ---
	"inj_stock": {"name": "Injection pump (inline, stock)", "slot": "fuel", "kg": 22.0, "price": 1800, "fits": ["i6d"],
		"max_hp": 260.0, "response": 0.9, "economy": 1.0},
	"inj_hd": {"name": "Injection pump (high output)", "slot": "fuel", "kg": 24.0, "price": 3400, "fits": ["i6d"],
		"max_hp": 450.0, "response": 1.05, "economy": 1.08},
	"i6d_manifold": {"name": "Diesel exhaust manifold (turbo flange)", "slot": "exhaust", "kg": 30.0, "price": 300, "fits": ["i6d"], "flow": 1.0, "flange": "turbo", "loud": 0.0},
	"i6d_pulse": {"name": "Diesel pulse manifold and straight pipe", "slot": "exhaust", "kg": 26.0, "price": 900, "fits": ["i6d"], "flow": 1.07, "flange": "turbo", "loud": 0.5},
	"turbo_d1": {"name": "Diesel turbo (stock, 18 psi)", "slot": "turbo", "kg": 28.0, "price": 1600, "fits": ["i6d"], "psi": 18.0, "spool": 1.8, "size": 1.3},
	"turbo_d2": {"name": "Diesel turbo (big, 28 psi)", "slot": "turbo", "kg": 34.0, "price": 2900, "fits": ["i6d"], "psi": 28.0, "spool": 2.6, "size": 1.7},
	"ic_d": {"name": "Charge-air cooler (truck)", "slot": "intercooler", "kg": 30.0, "price": 1100, "fits": ["i6d"], "eff": 0.7},
	"rad_truck": {"name": "Truck radiator", "slot": "radiator", "kg": 45.0, "price": 900, "fits": ["truck"], "cooling": 1.0},
	"rad_truck_hd": {"name": "Truck radiator (heavy duty, big fan)", "slot": "radiator", "kg": 60.0, "price": 1700, "fits": ["truck"], "cooling": 1.5},
	"t_truck5": {"name": "5-speed truck transmission", "slot": "transmission", "kg": 230.0, "price": 2400, "fits": ["truck"],
		"top": 1.0, "pull": 1.0, "gears": [3.0, 5.5, 9.0, 14.0, 22.0]},
	"t_truck10": {"name": "10-speed range transmission", "slot": "transmission", "kg": 280.0, "price": 4800, "fits": ["truck"],
		"top": 1.15, "pull": 1.2, "gears": [2.0, 3.0, 4.2, 5.8, 7.8, 10.0, 13.0, 16.5, 20.5, 25.0]},
	"diff_truck_529": {"name": "Tandem rear axles (5.29 gears)", "slot": "diff_r", "kg": 1100.0, "price": 6000, "fits": ["truck"], "end": "rear", "ratio": 5.29},
	"diff_truck_617": {"name": "Tandem rear axles (6.17 gears, low)", "slot": "diff_r", "kg": 1100.0, "price": 6400, "fits": ["truck"], "end": "rear", "ratio": 6.17},
	"diff_truck_456": {"name": "Tandem rear axles (4.56 gears, highway)", "slot": "diff_r", "kg": 1080.0, "price": 6200, "fits": ["truck"], "end": "rear", "ratio": 4.56},
	"sb_heads": {"name": "Small-block heads (stock)", "slot": "heads", "kg": 36.0, "price": 300, "fits": ["sb"], "flow": 1.0},
	"sb_heads_ported": {"name": "Small-block heads (ported, big valves)", "slot": "heads", "kg": 34.0, "price": 750, "fits": ["sb"], "flow": 1.09},
	"bb_heads": {"name": "Big-block heads", "slot": "heads", "kg": 48.0, "price": 600, "fits": ["bb"], "flow": 1.0},
	"sb_intake_2v": {"name": "Small-block intake (2-barrel)", "slot": "intake", "kg": 14.0, "price": 120, "fits": ["sb"], "ports": "2v"},
	"sb_intake_4v": {"name": "Small-block intake (4-barrel, dual plane)", "slot": "intake", "kg": 15.0, "price": 260, "fits": ["sb"], "ports": "4v"},
	"bb_intake_4v": {"name": "Big-block intake (4-barrel)", "slot": "intake", "kg": 20.0, "price": 300, "fits": ["bb"], "ports": "4v"},
	"carb_2bbl": {"name": "2-barrel carburettor", "slot": "fuel", "kg": 4.0, "price": 140, "fits": ["2v"],
		"max_hp": 190.0, "response": 0.85, "economy": 1.0},
	"carb_4bbl": {"name": "4-barrel carburettor (650 cfm)", "slot": "fuel", "kg": 5.5, "price": 320, "fits": ["4v"],
		"max_hp": 290.0, "response": 1.0, "economy": 1.12},
	"tbi": {"name": "Throttle-body injection", "slot": "fuel", "kg": 6.0, "price": 650, "fits": ["4v"],
		"max_hp": 260.0, "response": 1.2, "economy": 0.85},
	"turbo_t3": {"name": "Turbocharger (T3, 7 psi)", "slot": "turbo", "kg": 11.0, "price": 900, "fits": ["sb", "bb", "radial"],
		"psi": 7.0, "spool": 1.6, "size": 1.0},
	"turbo_t4": {"name": "Turbocharger (T4, 11 psi, big)", "slot": "turbo", "kg": 16.0, "price": 1300, "fits": ["sb", "bb", "radial"],
		"psi": 11.0, "spool": 2.6, "size": 1.45},
	"ic_air": {"name": "Intercooler (air to air)", "slot": "intercooler", "kg": 9.0, "price": 450, "fits": ["sb", "bb"], "eff": 0.65},
	"fpump_mech": {"name": "Fuel pump (mechanical, 6 psi)", "slot": "fuel_pump", "kg": 1.2, "price": 60, "fits": ["sb", "bb"], "kg_s": 0.020},
	"fpump_hp": {"name": "Fuel pump (electric, high flow)", "slot": "fuel_pump", "kg": 1.6, "price": 220, "fits": ["sb", "bb"], "kg_s": 0.034},
	"ffilter": {"name": "Fuel filter", "slot": "fuel_filter", "kg": 0.3, "price": 12, "fits": ["sb", "bb", "i6d"]},
	"fpump_lift": {"name": "Diesel lift pump", "slot": "fuel_pump", "kg": 2.0, "price": 140, "fits": ["i6d"], "kg_s": 0.05},
	# --- the aeroplane's radial: its own carburettors (not shared with the trucks) ---
	"acarb_float": {"name": "Aircraft float carburettor", "slot": "fuel", "kg": 5.0, "price": 600, "fits": ["aircraft"],
		"max_hp": 400.0, "response": 1.0, "economy": 1.0, "ice": 1.0},
	"acarb_pressure": {"name": "Aircraft pressure carburettor (injection type)", "slot": "fuel", "kg": 7.0, "price": 1500, "fits": ["aircraft"],
		"max_hp": 500.0, "response": 1.15, "economy": 0.94, "ice": 0.15},
	"sb_manifolds": {"name": "Small-block exhaust manifolds", "slot": "exhaust", "kg": 18.0, "price": 90, "fits": ["sb"], "flow": 1.0, "flange": "", "loud": 0.0},
	"sb_headers": {"name": "Small-block tube headers", "slot": "exhaust", "kg": 12.0, "price": 380, "fits": ["sb"], "flow": 1.06, "flange": "", "loud": 0.3},
	"sb_turbo_manifold": {"name": "Small-block turbo manifold (flanged)", "slot": "exhaust", "kg": 16.0, "price": 420, "fits": ["sb"], "flow": 0.97, "flange": "turbo", "loud": 0.1},
	"bb_manifolds": {"name": "Big-block exhaust manifolds", "slot": "exhaust", "kg": 24.0, "price": 110, "fits": ["bb"], "flow": 1.0, "flange": "", "loud": 0.0},
	"rad_stock": {"name": "Radiator (2-row)", "slot": "radiator", "kg": 11.0, "price": 180, "fits": ["v8"], "cooling": 1.0},
	"rad_hd": {"name": "Radiator (4-row, heavy duty)", "slot": "radiator", "kg": 15.0, "price": 420, "fits": ["v8"], "cooling": 1.45},
	"alt_60": {"name": "Alternator (60 A)", "slot": "alternator", "kg": 5.5, "price": 110, "fits": ["v8"], "amps": 60.0},
	"alt_100": {"name": "Alternator (100 A)", "slot": "alternator", "kg": 6.5, "price": 190, "fits": ["v8"], "amps": 100.0},
	"bat_65": {"name": "Battery (group 65)", "slot": "battery", "kg": 19.0, "price": 90, "fits": ["v8", "truck"], "ah": 75.0},
	"starter_v8": {"name": "Starter motor", "slot": "starter", "kg": 7.0, "price": 120, "fits": ["v8"]},
	"t_4spd": {"name": "4-speed manual (granny low)", "slot": "transmission", "kg": 58.0, "price": 600, "fits": ["pickup"],
		"top": 1.0, "pull": 1.0, "gears": [4.0, 8.5, 14.0, 40.0]},
	"t_5spd_od": {"name": "5-speed overdrive manual", "slot": "transmission", "kg": 52.0, "price": 950, "fits": ["pickup"],
		"top": 1.18, "pull": 0.9, "gears": [4.5, 9.0, 14.5, 21.0, 45.0]},
	"tc_205": {"name": "Transfer case (gear drive)", "slot": "transfer", "kg": 41.0, "price": 400, "fits": ["pickup"]},
	"ds_front": {"name": "Front driveshaft", "slot": "driveshaft_f", "kg": 9.0, "price": 90, "fits": ["pickup"], "end": "front"},
	"ds_rear": {"name": "Rear driveshaft", "slot": "driveshaft_r", "kg": 14.0, "price": 110, "fits": ["pickup"], "end": "rear"},
	"diff_f_410": {"name": "Front axle (4.10 gears)", "slot": "diff_f", "kg": 110.0, "price": 700, "fits": ["pickup"], "end": "front", "ratio": 4.10},
	"diff_r_410": {"name": "Rear axle (4.10 gears)", "slot": "diff_r", "kg": 135.0, "price": 800, "fits": ["pickup"], "end": "rear", "ratio": 4.10},
	"diff_f_373": {"name": "Front axle (3.73 gears)", "slot": "diff_f", "kg": 110.0, "price": 650, "fits": ["pickup"], "end": "front", "ratio": 3.73},
	"diff_r_373": {"name": "Rear axle (3.73 gears)", "slot": "diff_r", "kg": 135.0, "price": 750, "fits": ["pickup"], "end": "rear", "ratio": 3.73},
}

## --- the pickup's suspension and tyres (shared tyres come next) ---
const CHASSIS := {
	"lift_0": {"name": "Stock suspension", "slot": "lift", "kg": 0.0, "price": 0, "fits": ["pickup"], "inches": 0},
	"lift_2": {"name": "2-inch lift (springs and blocks)", "slot": "lift", "kg": 12.0, "price": 350, "fits": ["pickup"], "inches": 2},
	"lift_4": {"name": "4-inch lift (springs, shocks, long arms)", "slot": "lift", "kg": 28.0, "price": 900, "fits": ["pickup"], "inches": 4},
	"lift_6": {"name": "6-inch lift (full kit)", "slot": "lift", "kg": 45.0, "price": 1600, "fits": ["pickup"], "inches": 6},
	# lockers (DESIGN_NOTES 115): in the diff, so the axle drives both wheels.
	# Selectable: switched in and out (9 / right stick click). Automatic: always
	# locked going straight, lets go to turn on firm ground.
	"locker_f_sel": {"name": "Selectable locker, front (air)", "slot": "locker_f", "kg": 4.0, "price": 950, "fits": ["pickup"], "lock": "select"},
	"locker_r_sel": {"name": "Selectable locker, rear (air)", "slot": "locker_r", "kg": 4.0, "price": 900, "fits": ["pickup"], "lock": "select"},
	"locker_f_auto": {"name": "Automatic locker, front", "slot": "locker_f", "kg": 3.5, "price": 450, "fits": ["pickup"], "lock": "auto"},
	"locker_r_auto": {"name": "Automatic locker, rear", "slot": "locker_r", "kg": 3.5, "price": 420, "fits": ["pickup"], "lock": "auto"},
	"tyres_lt235": {"name": "LT235/85R16 highway tyres (x4)", "slot": "tyres", "kg": 88.0, "price": 0, "fits": ["pickup"], "tyre": "lt235", "need_lift": 0},
	"tyres_at31": {"name": "31-inch all-terrain tyres (x4)", "slot": "tyres", "kg": 100.0, "price": 520, "fits": ["pickup"], "tyre": "at31", "need_lift": 0},
	"tyres_mud33": {"name": "33-inch mud tyres (x4)", "slot": "tyres", "kg": 118.0, "price": 780, "fits": ["pickup"], "tyre": "mud33", "need_lift": 2},
	"tyres_mud35": {"name": "35-inch mud tyres (x4)", "slot": "tyres", "kg": 136.0, "price": 1150, "fits": ["pickup"], "tyre": "mud35", "need_lift": 4},
	# the trucks (DESIGN_NOTES 125): a set is all ten
	"tyres_hwy225": {"name": "11R22.5 highway tyres (x10)", "slot": "tyres", "kg": 540.0, "price": 0, "fits": ["truck"], "tyre": "hwy225"},
	"tyres_lug225": {"name": "11R22.5 drive lugs (x10)", "slot": "tyres", "kg": 580.0, "price": 3200, "fits": ["truck"], "tyre": "lug225"},
	"tyres_lug245": {"name": "11R24.5 deep lugs (x10)", "slot": "tyres", "kg": 640.0, "price": 4600, "fits": ["truck"], "tyre": "lug245"},
	"tyres_flot": {"name": "Flotation singles (x6)", "slot": "tyres", "kg": 600.0, "price": 6800, "fits": ["truck"], "tyre": "flot"},
	"susp_truck": {"name": "Multi-leaf springs (stock)", "slot": "susp", "kg": 0.0, "price": 0, "fits": ["truck"], "stiff": 1.0, "travel": 1.0, "load": 1.0},
	"susp_truck_hd": {"name": "Heavy-duty springs (more leaves)", "slot": "susp", "kg": 120.0, "price": 2200, "fits": ["truck"], "stiff": 1.35, "travel": 0.85, "load": 1.3},
	"susp_truck_air": {"name": "Air ride (bags and leveling valves)", "slot": "susp", "kg": 90.0, "price": 4800, "fits": ["truck"], "stiff": 0.8, "travel": 1.25, "load": 1.15},
	"susp_truck_walk": {"name": "Walking-beam rear (off-road)", "slot": "susp", "kg": 260.0, "price": 6200, "fits": ["truck"], "stiff": 1.1, "travel": 1.5, "load": 1.2},
}

## The pickup as it left the factory (and as an old one is now).
const PICKUP_STOCK := {"engine": "sb350", "heads": "sb_heads", "intake": "sb_intake_4v", "fuel": "carb_4bbl", "fuel_pump": "fpump_mech",
	"fuel_filter": "ffilter", "turbo": "", "intercooler": "",
	"exhaust": "sb_manifolds", "radiator": "rad_stock", "alternator": "alt_60", "battery": "bat_65", "starter": "starter_v8",
	"transmission": "t_4spd", "transfer": "tc_205", "driveshaft_f": "ds_front", "driveshaft_r": "ds_rear",
	"diff_f": "diff_f_410", "diff_r": "diff_r_410", "locker_f": "", "locker_r": "", "lift": "lift_0", "tyres": "tyres_lt235"}

## The water and fuel trucks as they came: a turbo diesel, a 5-speed, tandem
## rears, highway tyres.
const TRUCK_SLOTS := ["engine", "fuel", "fuel_pump", "fuel_filter", "exhaust", "turbo", "intercooler", "radiator", "battery",
	"transmission", "diff_r", "susp", "tyres"]
const TRUCK_STOCK := {"engine": "i6d78", "fuel": "inj_stock", "fuel_pump": "fpump_lift", "fuel_filter": "ffilter", "exhaust": "i6d_manifold",
	"turbo": "turbo_d1", "intercooler": "", "radiator": "rad_truck", "battery": "bat_65", "transmission": "t_truck5",
	"diff_r": "diff_truck_529", "susp": "susp_truck", "tyres": "tyres_hwy225"}

## The aeroplane: its radial engine stays; the carb and a turbo are its parts.
const PLANE_STOCK := {"fuel": "acarb_float", "turbo": ""}
const PLANE_SLOTS := ["fuel", "turbo"]
## Shared between vehicles: the turbo (and tyres, next). Everything else
## belongs to its own kind of vehicle.

## The spares on the shelf in the tool yard at the start.
const SHELF := ["turbo_t3", "ic_air", "fpump_hp", "ffilter", "acarb_pressure", "sb_turbo_manifold", "sb_headers", "sb_heads_ported", "rad_hd", "alt_100", "tbi", "carb_2bbl",
	"sb_intake_2v", "t_5spd_od", "diff_r_373", "diff_f_373", "bat_65", "starter_v8", "sb400", "turbo_t4",
	"ic_d", "tyres_lug225", "susp_truck_hd", "i6d_pulse"]

static var inst := {}          # uid -> {"def": String, "cond": float}
static var fitted := {}        # vehicle key ("pickup", "plane:C-GKBP") -> {slot: uid}
static var storage: Array = [] # uids on the workshop shelves (any vehicle can use them)
static var _next := 1
static var _dirty := false


static func make(def: String, cond: float = 1.0) -> int:
	var uid := _next
	_next += 1
	inst[uid] = {"def": def, "cond": clampf(cond, 0.0, 1.0)}
	_dirty = true
	return uid


static func def_of(uid: int) -> Dictionary:
	if not inst.has(uid):
		return {}
	var did := String(inst[uid]["def"])
	return CATALOG.get(did, CHASSIS.get(did, {}))


static func cond(uid: int) -> float:
	return float(inst[uid]["cond"]) if inst.has(uid) else 0.0


static func set_cond(uid: int, c: float) -> void:
	if inst.has(uid):
		inst[uid]["cond"] = clampf(c, 0.0, 1.0)
		_dirty = true


static func wear(uid: int, amount: float) -> void:
	set_cond(uid, cond(uid) - amount)


## "part:12" -> 12, anything else -> 0
static func uid_of_item(id: String) -> int:
	return int(id.substr(5)) if id.begins_with("part:") else 0


static func item_id(uid: int) -> String:
	return "part:%d" % uid


static func cond_word(c: float) -> String:
	if c <= 0.01:
		return "broken"
	if c < 0.3:
		return "badly worn"
	if c < 0.6:
		return "worn"
	if c < 0.85:
		return "used"
	return "good"


static func label(uid: int) -> String:
	var d := def_of(uid)
	if d.is_empty():
		return "?"
	return "%s (%d%%, %s)" % [d["name"], int(round(cond(uid) * 100.0)), cond_word(cond(uid))]


## The inventory's description of a part item: [name, kg, stack, one-line use].
static func item_spec(id: String) -> Array:
	var uid := uid_of_item(id)
	var d := def_of(uid)
	if d.is_empty():
		return ["Part", 1.0, 1, ""]
	return [label(uid), float(d["kg"]), 1, "In hand: open the hood (or get under it), look at the empty spot and %s to fit it." % Game.hint("interact")]


## Does part `uid` go in slot `slot` of a vehicle with these tags and these
## parts already in? "" if it fits, else why not.
static func fits(uid: int, slot: String, tags: Array, fitted: Dictionary) -> String:
	var d := def_of(uid)
	if d.is_empty():
		return "That's not a part."
	if String(d["slot"]) != slot:
		return "That's a %s, not a %s." % [SLOT_NAMES.get(String(d["slot"]), d["slot"]), SLOT_NAMES.get(slot, slot)]
	var fam: String = _fitted_def(fitted, "engine").get("family", "")
	if tags.has("aircraft"):
		fam = "radial"               # the aeroplane's engine isn't a swappable part
	var need: Array = d["fits"]
	match slot:
		"engine":
			for t in need:
				if tags.has(t):
					return ""
			return "That engine won't go in this chassis (it's for a %s)." % ", ".join(need)
		"heads", "intake", "exhaust", "turbo":
			if fam == "":
				return "Put an engine in first."
			if not need.has(fam):
				return "Wrong engine family: that's for a %s block." % ", ".join(need)
			if slot == "turbo" and not tags.has("aircraft"):
				var ex := _fitted_def(fitted, "exhaust")
				if String(ex.get("flange", "")) != "turbo":
					return "Nowhere to bolt a turbo: it needs the flanged turbo manifold on first."
			return ""
		"tyres":
			if tags.has("truck"):
				return "" if need.has("truck") else "Those are pickup tyres: they won't go on a truck's wheels."
			if not tags.has("pickup") or not need.has("pickup"):
				return "Those tyres are for the %s." % ("trucks" if need.has("truck") else "pickup")
			var lift_in := int(_fitted_def(fitted, "lift").get("inches", 0))
			var need_l := int(d.get("need_lift", 0))
			if lift_in < need_l:
				return "They won't clear the fenders: they need a %d-inch lift (it has %d)." % [need_l, lift_in]
			return ""
		"locker_f", "locker_r":
			if not tags.has("pickup"):
				return "That locker's for the pickup."
			if int(fitted.get("diff_f" if slot == "locker_f" else "diff_r", 0)) <= 0:
				return "There's no axle for it to go in."
			return ""
		"intercooler":
			if int(fitted.get("turbo", 0)) <= 0:
				return "An intercooler's no use without a turbo feeding it."
			return ""
		"fuel_pump", "fuel_filter":
			if fam == "":
				return "Put an engine in first."
			if not need.has(fam):
				return "That won't plumb into this engine."
			return ""
		"fuel":
			if fam == "i6d" or need.has("i6d"):
				return "" if (fam == "i6d" and need.has("i6d")) else ("That injection pump's for a diesel." if need.has("i6d") else "A diesel needs an injection pump, not a carburettor.")
			if tags.has("aircraft") or need.has("aircraft"):
				return "" if (tags.has("aircraft") and need.has("aircraft")) else "That carburettor's for %s." % ("an aeroplane" if need.has("aircraft") else "a car engine")
			var intake := _fitted_def(fitted, "intake")
			if intake.is_empty():
				return "Put an intake manifold on first."
			if not need.has(String(intake.get("ports", ""))):
				return "Wrong bolt pattern: that needs a %s intake." % ("4-barrel" if need.has("4v") else "2-barrel")
			return ""
		_:
			for t in need:
				if tags.has(t):
					return ""
			return "That doesn't fit this vehicle (it's for a %s)." % ", ".join(need)


## Swapping a part in one go (the workshop menu): put `uid` in `slot`, and
## sort out everything that goes with it -
##   what was there comes off onto the shelves
##   a part it needs first goes on too (the flanged manifold for a turbo, a
##   lift for big tyres, the right intake for a carb), from the shelves if
##   there's one, else bought new
##   anything that no longer fits comes off (a new engine family's heads,
##   intake, exhaust ...) and the right one goes on, from the shelves or new
## Returns {"why": "" or why it can't, "fitted": the result, "off": uids that
## come off, "new": uids made for parts bought (discard_plan if not used),
## "cost": what the new ones cost, "notes": [what else happens]}.
const _CHECK_ORDER := ["engine", "heads", "intake", "fuel", "fuel_pump", "fuel_filter", "exhaust", "turbo", "intercooler", "radiator", "alternator", "battery", "starter",
	"transmission", "transfer", "driveshaft_f", "driveshaft_r", "diff_f", "diff_r", "locker_f", "locker_r", "lift", "susp", "tyres"]
const _OPTIONAL := ["turbo", "intercooler", "locker_f", "locker_r"]


static func plan_swap(uid: int, slot: String, tags: Array, fitted0: Dictionary) -> Dictionary:
	var pl := {"why": "", "fitted": fitted0.duplicate(), "off": [], "new": [], "cost": 0, "notes": [], "used": []}
	var f: Dictionary = pl["fitted"]
	# what it needs first
	var d := def_of(uid)
	if slot == "turbo" and not tags.has("aircraft") and String(_fitted_def(f, "exhaust").get("flange", "")) != "turbo":
		_provide(pl, "exhaust", tags, func(dd: Dictionary) -> bool: return String(dd.get("flange", "")) == "turbo")
	elif slot == "tyres" and int(_fitted_def(f, "lift").get("inches", 0)) < int(d.get("need_lift", 0)):
		var need := int(d.get("need_lift", 0))
		_provide(pl, "lift", tags, func(dd: Dictionary) -> bool: return int(dd.get("inches", 0)) >= need)
	elif slot == "fuel" and not tags.has("aircraft") and not (d["fits"] as Array).has(String(_fitted_def(f, "intake").get("ports", ""))):
		var ports: Array = d["fits"]
		_provide(pl, "intake", tags, func(dd: Dictionary) -> bool: return ports.has(String(dd.get("ports", ""))))
	_put(pl, slot, uid)
	var why := fits(uid, slot, tags, f)
	if why != "":
		discard_plan(pl)
		pl["why"] = why
		return pl
	# everything else still has to fit (twice: one change can lead to another)
	for pass_i in range(2):
		for sl in _CHECK_ORDER:
			if sl == slot or int(f.get(sl, 0)) <= 0:
				continue
			if fits(int(f[sl]), sl, tags, f) == "":
				continue
			(pl["off"] as Array).append(int(f[sl]))
			f.erase(sl)
			if not _OPTIONAL.has(sl):
				_provide(pl, sl, tags, func(_dd: Dictionary) -> bool: return true)
	return pl


## Fit something in `slot` matching `want`: off the shelves if there is one,
## else the cheapest new one that fits.
static func _provide(pl: Dictionary, slot: String, tags: Array, want: Callable) -> void:
	var f: Dictionary = pl["fitted"]
	for u in storage:
		var uu := int(u)
		if (pl["used"] as Array).has(uu) or (pl["off"] as Array).has(uu):
			continue
		var dd := def_of(uu)
		if String(dd.get("slot", "")) == slot and want.call(dd) and fits(uu, slot, tags, f) == "":
			_put(pl, slot, uu)
			(pl["used"] as Array).append(uu)
			(pl["notes"] as Array).append("fits the %s off the shelf" % String(dd["name"]).to_lower())
			return
	var best := ""
	var best_p := 1 << 30
	var all := CATALOG.duplicate()
	all.merge(CHASSIS)
	for did in all.keys():
		var dd2: Dictionary = all[did]
		if String(dd2["slot"]) != slot or not want.call(dd2) or int(dd2["price"]) >= best_p:
			continue
		var tmp := make(String(did), 1.0)
		var ok := fits(tmp, slot, tags, f) == ""
		inst.erase(tmp)
		if ok:
			best = String(did)
			best_p = int(dd2["price"])
	if best == "":
		return
	var nu := make(best, 1.0)
	(pl["new"] as Array).append(nu)
	pl["cost"] = int(pl["cost"]) + best_p
	_put(pl, slot, nu)
	(pl["notes"] as Array).append("buys a new %s ($%d)" % [String(all[best]["name"]).to_lower(), best_p])


static func _put(pl: Dictionary, slot: String, u: int) -> void:
	var f: Dictionary = pl["fitted"]
	if int(f.get(slot, 0)) > 0 and int(f[slot]) != u:
		(pl["off"] as Array).append(int(f[slot]))
	f[slot] = u


## Forget a plan that wasn't used (the parts it would have bought).
static func discard_plan(pl: Dictionary) -> void:
	for u in pl["new"]:
		inst.erase(int(u))
	(pl["new"] as Array).clear()


## Do it: the vehicle gets the plan's parts, what came off goes on the shelves.
static func apply_plan(key: String, pl: Dictionary) -> void:
	var f: Dictionary = pl["fitted"]
	for u in f.values():
		storage.erase(int(u))
	for u in pl["off"]:
		if not f.values().has(int(u)) and not storage.has(int(u)):
			storage.append(int(u))
	fitted[key] = f
	save_all()


static func _fitted_def(fitted: Dictionary, slot: String) -> Dictionary:
	var u := int(fitted.get(slot, 0))
	return def_of(u) if u > 0 else {}


static func save_all() -> void:
	var cf := ConfigFile.new()
	var data := {}
	for k in inst.keys():
		data[str(k)] = inst[k]
	cf.set_value("p", "inst", data)
	cf.set_value("p", "next", _next)
	cf.set_value("p", "fitted", fitted)
	cf.set_value("p", "storage", storage)
	cf.save(SAVE)
	_dirty = false


static func load_all() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return false
	inst.clear()
	var data: Dictionary = cf.get_value("p", "inst", {})
	for k in data.keys():
		inst[int(k)] = data[k]
	_next = int(cf.get_value("p", "next", 1))
	fitted = cf.get_value("p", "fitted", {})
	storage = cf.get_value("p", "storage", [])
	return true


static func save_if_dirty() -> void:
	if _dirty:
		save_all()


## A low-poly model of a part, for your hands and the ground.
static func build_mesh(uid: int) -> Node3D:
	const MeshKit = preload("res://scripts/meshkit.gd")
	var d := def_of(uid)
	var root := Node3D.new()
	root.name = "Part"
	var k := MeshKit.new()
	var c := cond(uid)
	var steel := Color(0.36, 0.38, 0.40).lerp(Color(0.45, 0.28, 0.18), 1.0 - c)    # rusty when it's worn
	var paint := Color(0.18, 0.30, 0.55).lerp(Color(0.40, 0.30, 0.22), 1.0 - c)
	var alu := Color(0.68, 0.68, 0.66)
	match String(d.get("slot", "")):
		"engine":
			k.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0)), Vector3(0.62, 0.55, 0.75), paint)
			k.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0)), Vector3(0.45, 0.24, 0.7), steel)
			for s in [-1.0, 1.0]:
				k.box(Transform3D(Basis(Vector3.FORWARD, s * 0.5), Vector3(s * 0.26, 0.66, 0)), Vector3(0.2, 0.16, 0.72), paint)
		"heads":
			k.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.07, 0)), Vector3(0.2, 0.14, 0.6), steel)
			k.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.07, 0.25)), Vector3(0.2, 0.14, 0.6), steel)
		"turbo":
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.12, -0.08)), 0.12, 0.12, 0.12, 10, steel)
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.12, 0.06)), 0.11, 0.11, 0.1, 10, alu)
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.12, 0.16)), 0.05, 0.05, 0.12, 8, alu)
		"radiator":
			k.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.33, 0)), Vector3(0.72, 0.62, 0.07), Color(0.12, 0.12, 0.12).lerp(Color(0.40, 0.26, 0.16), 1.0 - c))
		"transmission", "transfer":
			k.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.18, 0)), Vector3(0.36, 0.34, 0.62 if String(d["slot"]) == "transmission" else 0.4), alu.darkened(0.25))
		"driveshaft_f", "driveshaft_r":
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.05, -0.55)), 0.04, 0.04, 1.1, 8, steel)
		"diff_f", "diff_r":
			k.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.8, 0.12, 0)), 0.05, 0.05, 1.6, 8, steel)
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.15, -0.1)), 0.17, 0.17, 0.22, 12, steel)
		"battery":
			k.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), Vector3(0.3, 0.2, 0.18), Color(0.12, 0.12, 0.13))
		"fuel":
			k.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.07, 0)), Vector3(0.18, 0.14, 0.2), alu)
			k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.14, 0)), 0.17, 0.17, 0.06, 12, Color(0.1, 0.1, 0.1))
		_:
			k.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.08, 0)), Vector3(0.26, 0.16, 0.36), steel)
	var mi := k.instance("PartMesh")
	root.add_child(mi)
	return root


## A new game: the spares on the workshop shelves.
## Forget every part (a new game).
static func clear() -> void:
	inst.clear()
	fitted.clear()
	storage.clear()
	_next = 1
	_dirty = false


static func stock_shelves() -> void:
	storage.clear()
	for d in SHELF:
		storage.append(make(String(d), randf_range(0.55, 1.0)))
	_dirty = true


## Every slot something else depends on: take this off and these come off too.
static func dependents(slot: String) -> Array:
	match slot:
		"engine":
			return ["heads", "intake", "fuel", "turbo", "intercooler", "exhaust", "fuel_pump", "fuel_filter"]
		"heads":
			return ["intake", "fuel", "exhaust", "turbo", "intercooler"]
		"intake":
			return ["fuel"]
		"exhaust":
			return ["turbo", "intercooler"]
		"turbo":
			return ["intercooler"]
		"transmission":
			return ["transfer", "driveshaft_f", "driveshaft_r"]
		"transfer":
			return ["driveshaft_f"]
		"lift":
			return ["tyres"]
		"diff_f":
			return ["locker_f"]
		"diff_r":
			return ["locker_r"]
	return []
