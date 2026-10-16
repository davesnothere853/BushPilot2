extends Node3D
## Flight model for the bush plane.
##
## The aeroplane is a rigid body moved by this script (no physics engine). Each
## wing panel, the tailplane, the fin and the fuselage make their own lift and
## drag from the air actually flowing past them, so stalls, spins, slips,
## propwash, ground effect and the effect of where the load sits all fall out of
## the same sums. Wheels are springs against the terrain.
##
## Body axes: +X right wing, +Y up, -Z out the nose.
## Rotation rates (omega): x = nose up, y = nose left, z = left wing down.

const Terrain = preload("res://scripts/terrain.gd")
const EngineScript = preload("res://scripts/engine.gd")
const GearScript = preload("res://scripts/gear.gd")

signal crashed(reason: String)
signal landed(info: Dictionary)
signal notice(text: String)
## The airframe hit something at `point` (aircraft coordinates); `push` is the
## direction the skin is shoved, `sev` how hard. Used to dent the model.
signal dented(point: Vector3, push: Vector3, sev: float)
## Something is grinding along the ground at `point`, scratching the paint.
signal scraped(point: Vector3, amount: float)
signal repaired
## A tree was hit hard enough to snap; `push` is the horizontal direction it was shoved.
signal tree_felled(ti: int, tj: int, push: Vector3)
## A part tore off: its name, where (aircraft coordinates) and the plane's velocity.
signal part_broken(part: String)
## A crash started a fire, or set off an explosion.
signal fire_started(strength: float)
signal exploded(strength: float)

const GRAVITY := 9.81
const KT := 1.94384
const FT := 3.28084
const FWD := Vector3(0, 0, -1)

var terrain: RefCounted
var wind: Node

# --- airframe: the "Wolverine 180", a tired 230 hp taildragger -----------------
const AircraftLights = preload("res://scripts/aircraft_lights.gd")
const PlaneTypes = preload("res://scripts/plane_types.gd")
var plane_type := "wolverine"
var type_name := "Wolverine 180"
var reg := "C-GKBP"                 # registration painted on the tail
var empty_mass := 760.0
var empty_cg := Vector3(0.0, -0.05, 0.08)       # metres from the datum (wing quarter-chord)
var empty_inertia := Vector3(1750.0, 2500.0, 1250.0)   # pitch, yaw, roll about the empty CG
var max_mass := 1270.0
var rated_power := 172000.0                     # watts (230 hp)
var prop_radius := 1.0
var fuel_capacity := 150.0                      # kg, about 55 US gallons
var pilot_mass := 85.0
var cargo_front_max := 220.0
var cargo_rear_max := 90.0
var STATION_PILOT := Vector3(0.0, -0.10, 0.05)
var STATION_FUEL := Vector3(0.0, 0.85, 0.15)
const OIL_KG_PER_QT := 0.83
var STATION_FRONT := Vector3(0.0, -0.25, 0.90)
var STATION_REAR := Vector3(0.0, -0.20, 1.90)
var CG_FWD_LIMIT := 0.05
var CG_AFT_LIMIT := 0.30

var wing_area := 16.2
var wing_span := 11.0
var chord := 1.5
var aspect := 7.47
var cl0 := 0.30
var cl_slope := 4.95
var stall_alpha := 0.232
var stall_blend := 0.25
var flap_dcl := 1.0
var cd0_wing := 0.010
var cm0 := -0.04
var cm_flap := -0.10
var parasite_area := 0.43                       # drag area of fuselage, struts and gear, m^2
const AIL_DCL := 0.44
const ELEV_DCL := 0.84
const RUD_DCL := 0.66

# wing panels: left outer, left inner, right inner, right outer
var w_pos: Array[Vector3] = []
var w_normal: Array[Vector3] = []
var w_area: Array[float] = []
var w_twist: Array[float] = []
var w_flap: Array[float] = []
var w_ail: Array[float] = []
var w_blow: Array[float] = []

var TAIL_POS := Vector3(0.0, 0.10, 4.70)
var TAIL_AREA := 3.2
var TAIL_SLOPE := 3.8
var TAIL_ASPECT := 4.0
var tail_incidence := 0.012
var FIN_POS := Vector3(0.0, 0.70, 4.90)
var FIN_AREA := 1.7
var FIN_SLOPE := 2.6
var SIDE_POS := Vector3(0.0, -0.10, 0.75)
var SIDE_AREA := 5.5
var SIDE_SLOPE := 0.9
var PROP_POS := Vector3(0.0, 0.05, -2.20)
var DRAG_POS := Vector3(0.0, -0.30, 0.20)

# --- landing gear: left main, right main, tailwheel ------------------------------
# Each wheel is a tyre (a stiff, lightly damped spring) on a leg (a softer spring
# with a damper), so a hard arrival squashes the tyre first and then the leg, and
# the energy comes back out as a bounce unless the leg soaks it up.
var tyre_kind := "850"
var leg_kind := "spring"
## Axle positions with the leg fully extended (aircraft coordinates).
var hub_rest: Array[Vector3] = [Vector3(-1.15, -1.27, -0.55), Vector3(1.15, -1.27, -0.55), Vector3(0.0, -0.21, 5.00)]
## Bottom of each unloaded tyre; used to look up the surface under each wheel.
var wheel_pos: Array[Vector3] = [Vector3(-1.15, -1.53, -0.55), Vector3(1.15, -1.53, -0.55), Vector3(0.0, -0.32, 5.00)]
var brake_force := 2900.0      # most a brake can hold back per wheel, N
var HUB_STD: Array[Vector3] = [Vector3(-1.15, -1.27, -0.55), Vector3(1.15, -1.27, -0.55), Vector3(0.0, -0.21, 5.00)]

# --- amphibious floats ------------------------------------------------------------
# Two floats with wheels that retract into them: mains just behind the step, a
# nose wheel in each bow (one centre wheel in the physics). Gear down for land,
# up for water. Landing on water with the wheels down flips you over.
const AMPHIB_HUBS: Array[Vector3] = [Vector3(-1.25, -2.13, 0.75), Vector3(1.25, -2.13, 0.75), Vector3(0.0, -2.05, -2.90)]
const FLOAT_X := 1.25
## Stations along each float: z, keel y, half beam, deck y (aircraft coordinates).
const FLOAT_ST: Array = [
	[-3.45, -1.62, 0.12, -1.42], [-2.95, -1.86, 0.24, -1.38], [-2.25, -1.99, 0.31, -1.36],
	[-1.50, -2.04, 0.33, -1.35], [-0.75, -2.05, 0.33, -1.35], [0.00, -2.05, 0.32, -1.35],
	[0.30, -2.05, 0.31, -1.36], [1.00, -1.94, 0.28, -1.37], [1.75, -1.84, 0.24, -1.39],
	[2.50, -1.74, 0.19, -1.41], [3.10, -1.67, 0.13, -1.43],
]
const FLOAT_STEP := 6                  # index of the step
var gear_down := true                  # amphibious floats: wheels commanded down
var gear_pos := 1.0                    # 1 down and locked, 0 up in the floats
var float_water: Array[float] = [0.0, 0.0]   # deepest a float sits in the water, m
var water_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]   # where spray comes off (aircraft coords)
var waves: Node                        # waves.gd, so floats ride on the wakes
var water_rudders := false
var door_open := {"cabin": false, "bay": false}   # the cabin and baggage doors
var lights := {"nav": false, "beacon": false, "strobe": false, "landing": false, "taxi": false}
var panel_light := 0.0                 # instrument lighting dimmer 0..1
var dbg_aero_yaw := 0.0
var dbg_contact_yaw := 0.0
var hard_landing_sink := 2.5
var collapse_sink := 4.4

# other points that can touch the ground: name, position
var BODY_POINTS: Array = [
	["propeller", Vector3(0.0, -0.93, -2.20)],
	["nose", Vector3(0.0, -0.45, -2.00)],
	["left wingtip", Vector3(-5.5, 0.92, 0.30)],
	["right wingtip", Vector3(5.5, 0.92, 0.30)],
	["belly", Vector3(0.0, -0.66, 0.60)],
	["tail", Vector3(0.0, -0.12, 4.60)],
	["fin", Vector3(0.0, 1.75, 5.10)],
	["cabin roof", Vector3(0.0, 1.08, 0.20)],
	["left wing mid", Vector3(-2.7, 0.97, 0.10)],
	["right wing mid", Vector3(2.7, 0.97, 0.10)],
	["left wing root", Vector3(-1.2, 1.00, 0.10)],
	["right wing root", Vector3(1.2, 1.00, 0.10)],
	["left tailplane", Vector3(-1.6, 0.12, 4.50)],
	["right tailplane", Vector3(1.6, 0.12, 4.50)],
]

# --- load ---------------------------------------------------------------------------
var fuel: float:
	get:
		return engine.total_fuel() + (engine2.total_fuel() if engine2 != null else 0.0)
	set(v):
		if engine2 != null:
			engine.set_fuel(v * 0.5)
			engine2.set_fuel(v * 0.5)
		else:
			engine.set_fuel(v)
var cargo_front := 0.0
var cargo_rear := 0.0
var job_front := 0.0               # loads carried for jobs (jobs.gd), on top of the above
var job_rear := 0.0
var mass := 1000.0
var cg := Vector3.ZERO
var inertia := Vector3(1800.0, 2600.0, 1300.0)

# --- state --------------------------------------------------------------------------
var pos := Vector3.ZERO            # world position of the centre of gravity
var vel := Vector3.ZERO
var b := Basis.IDENTITY
var omega := Vector3.ZERO          # body-frame rotation rate

# --- controls: what the pilot is asking for (-1..1, throttle and brake 0..1) -------
var in_pitch := 0.0                # +1 = stick back, nose up
var in_roll := 0.0                 # +1 = roll right
var in_yaw := 0.0                  # +1 = nose right
var throttle := 0.0
var brake := 0.0                  # both brakes together
var brake_left := 0.0             # toe brakes, one per main wheel
var brake_right := 0.0
var park_brake := false
var _brake_wheel: Array[float] = [0.0, 0.0]
var flap_notch := 0                # 0..4, ten degrees each
var trim := 0.0
var direct_controls := false       # true = skip the keyboard smoothing (gamepad, autopilot)

# --- control surfaces as they actually are ----------------------------------------
var elevator := 0.0
var aileron := 0.0
var rudder := 0.0
var flaps := 0.0                   # 0..1

# --- engine (see engine.gd) -----------------------------------------------------------
var engine = EngineScript.new()
## Twins: the right engine (engine is the left). null on a single.
var engine2 = null
var props: Array[Vector3] = [Vector3(0.0, 0.05, -2.20)]
var sit_pitch := 11.2
var vne_kt := 175.0                  # never-exceed speed: past it the controls start to flutter
var vfe_kt := 95.0                   # fastest the flaps may be out
var prop_inertia := 5.0              # spinning prop's moment of inertia, kg m^2 (gyroscopic)
var approach_speed := 33.5
var gear_mass_pos := Vector3(0.0, -1.2, -0.55)
var control_rate := 1.0
var feathered: Array[bool] = [false, false]
var engine_thrust: Array[float] = [0.0, 0.0]     # each engine's thrust now, N (for the HUD)


func engines() -> Array:
	return [engine] if engine2 == null else [engine, engine2]


## Ground and body contact springs were tuned for the Wolverine (about 1 t);
## bigger aeroplanes need them stiffer in proportion.
func _mscale() -> float:
	return maxf(empty_mass / 760.0, 1.0)


func is_twin() -> bool:
	return engine2 != null


## Become a type of aeroplane (plane_types.gd): weights, sizes, engines, wing,
## tail, gear and the points that can hit the ground.
func apply_type(t: String) -> void:
	var sp: Dictionary = PlaneTypes.spec(t)
	plane_type = t if PlaneTypes.TYPES.has(t) else "wolverine"
	type_name = sp["name"]
	empty_mass = sp["empty_mass"]
	empty_cg = sp["empty_cg"]
	empty_inertia = sp["empty_inertia"]
	max_mass = sp["max_mass"]
	rated_power = sp["rated_power"]
	prop_radius = sp["prop_radius"]
	fuel_capacity = sp["fuel_capacity"]
	pilot_mass = sp["crew_mass"]
	cargo_front_max = sp["cargo_front_max"]
	cargo_rear_max = sp["cargo_rear_max"]
	STATION_PILOT = sp["station_pilot"]
	STATION_FUEL = sp["station_fuel"]
	STATION_FRONT = sp["station_front"]
	STATION_REAR = sp["station_rear"]
	CG_FWD_LIMIT = sp["cg_fwd"]
	CG_AFT_LIMIT = sp["cg_aft"]
	wing_area = sp["wing_area"]
	wing_span = sp["wing_span"]
	chord = sp["chord"]
	aspect = wing_span * wing_span / wing_area
	cl0 = sp["cl0"]
	cl_slope = sp["cl_slope"]
	stall_alpha = sp["stall_alpha"]
	flap_dcl = sp["flap_dcl"]
	cd0_wing = sp["cd0_wing"]
	cm0 = sp["cm0"]
	cm_flap = sp["cm_flap"]
	parasite_area = sp["parasite_area"]
	TAIL_POS = sp["tail_pos"]
	TAIL_AREA = sp["tail_area"]
	TAIL_SLOPE = sp["tail_slope"]
	TAIL_ASPECT = sp["tail_aspect"]
	FIN_POS = sp["fin_pos"]
	FIN_AREA = sp["fin_area"]
	FIN_SLOPE = sp["fin_slope"]
	SIDE_POS = sp["side_pos"]
	SIDE_AREA = sp["side_area"]
	SIDE_SLOPE = sp["side_slope"]
	DRAG_POS = sp["drag_pos"]
	props.clear()
	for pp in sp["props"]:
		props.append(pp)
	PROP_POS = props[0]
	HUB_STD.clear()
	for h in sp["hubs"]:
		HUB_STD.append(h)
	brake_force = sp["brake_force"]
	sit_pitch = sp["sit_pitch"]
	approach_speed = sp["approach_speed"]
	gear_mass_pos = sp["gear_mass_pos"]
	control_rate = sp["control_rate"]
	vne_kt = float(sp.get("vne", 175.0))
	tail_incidence = float(sp.get("tail_incidence", 0.012))
	vfe_kt = float(sp.get("vfe", 95.0))
	prop_inertia = float(sp.get("prop_inertia", 5.0))
	BODY_POINTS = (sp["body"] as Array).duplicate(true)
	var fuel_was: float = fuel
	engine.cylinders = int(sp.get("cylinders", 14 if plane_type == "dc3" else 6))
	engine.oil_capacity = float(sp.get("oil_capacity", 25.0 * 4.0 if plane_type == "dc3" else 12.0))
	engine.oil_qts = minf(engine.oil_qts, engine.oil_capacity) if plane_type != "dc3" else engine.oil_capacity * 0.85
	for e in [engine]:
		e.rated_power = rated_power
		e.rated_rpm = float(sp["rated_rpm"])
		e.redline_rpm = float(sp["rated_rpm"]) + 100.0
	if int(sp["engines"]) >= 2:
		if engine2 == null:
			engine2 = EngineScript.new()
			engine2.event.connect(func(text: String): notice.emit("Right engine: " + text))
		engine2.cylinders = 14
		engine2.oil_capacity = engine.oil_capacity
		engine2.oil_qts = engine2.oil_capacity * 0.85
		engine2.rated_power = rated_power
		engine2.rated_rpm = float(sp["rated_rpm"])
		engine2.redline_rpm = float(sp["rated_rpm"]) + 100.0
		engine.tank_capacity = fuel_capacity * 0.25
		engine2.tank_capacity = fuel_capacity * 0.25
	else:
		engine2 = null
		engine.tank_capacity = fuel_capacity * 0.5
	feathered = [false, false]
	_build_wing()
	if String(sp["tyres"]) != "":
		tyre_kind = sp["tyres"]
		leg_kind = sp["legs"]
	elif GearScript.TYRES.get(tyre_kind, {}).get("only", "") != "" or GearScript.LEGS.get(leg_kind, {}).get("only", "") != "":
		tyre_kind = "850"
		leg_kind = "spring"
	apply_gear()
	fuel = minf(fuel_was, fuel_capacity)
	recompute_mass()
var engine_running: bool:
	get:
		return engine.running
	set(v):
		if v:
			engine.running = true
		else:
			engine.stop()
var rpm: float:
	get:
		return engine.rpm
	set(v):
		engine.rpm = v
var fuel_flow: float:
	get:
		return engine.fuel_flow
var power_frac := 0.0
var thrust_now := 0.0
var _pressure_pa := 101325.0
var _seq := ""                      # automatic start or shut-down in progress
var _seq_step := 0
var _seq_t := 0.0

# --- readouts for the panel, camera and sound --------------------------------------
var airspeed := 0.0                # true airspeed, m/s
var ias_kt := 0.0
var alpha := 0.0
var beta := 0.0
var agl := 0.0
var ground_speed := 0.0
var g_load := 1.0
var slip_ball := 0.0
var stall_warning := false
var wing_alpha := 0.0
var stalled := false
var on_ground := true
var wheels_down := 0
var wheel_comp: Array[float] = [0.0, 0.0, 0.0]     # leg stroke, m (0 = fully extended)
var tyre_defl: Array[float] = [0.0, 0.0, 0.0]      # how far each tyre is squashed, m
var wheel_load: Array[float] = [0.0, 0.0, 0.0]     # N
var wheel_sink: Array[float] = [0.0, 0.0, 0.0]     # how deep each tyre has sunk into soft ground, m
var wheel_spin_rate: Array[float] = [0.0, 0.0, 0.0]  # rad/s, for the wheels you see
var wheel_locked: Array[bool] = [false, false, false]
var wheel_water: Array[float] = [0.0, 0.0, 0.0]     # how deep each tyre is in water, m
var skid_level := 0.0                # 0..1, how hard the tyres are scrubbing (for sound)
var tail_castering := false          # the tailwheel has broken out of its steering springs
var tail_lock := false               # DC-3: the tailwheel lock is in (runs dead straight)
var livery := 0                      # paint scheme index (liveries.gd)
var paint: Array = []                # your own colours from the paint shop (overrides the scheme), or []
var _tyre: Array = []                # spec of the tyre on each wheel
var _leg: Array = []                 # spec of each leg
var _lat_def: Array[float] = [0.0, 0.0, 0.0]   # sideways twist in each tyre, m
var _rim_hit: Array[bool] = [false, false, false]
var _hard_cool := 0.0                # seconds before another hard arrival can do damage
var wing_off: Array[bool] = [false, false]   # outer wing torn away (left, right)
var on_fire := false
var fire_strength := 0.0             # 0..1, how hard the wreck is burning
var _fire_fuel := 0.0                # kg left to burn
var _tree_touch := {}                # tree contacts from the last step
var last_impact := 0.0               # speed of the last violent hit, m/s
var _sp: Array = [{}, {}, {}]        # surface properties under each wheel
var _gear_mass := 0.0
var _gear_drag := 0.0
var surface_now := Terrain.SURF_ROUGH
var air_density_now := 1.225
var oat_c := 15.0

# --- flight bookkeeping -------------------------------------------------------------
var is_crashed := false            # wrecked: will not fly again until recovered
# Health of each part, 1 = perfect, 0 = destroyed.
const PART_NAMES := {
	"gear_l": "Left main gear", "gear_r": "Right main gear", "tailwheel": "Tailwheel",
	"tire_l": "Left tyre", "tire_r": "Right tyre", "prop": "Propeller",
	"wing_l": "Left wing", "wing_r": "Right wing", "aileron_l": "Left aileron", "aileron_r": "Right aileron",
	"flaps": "Flaps", "elevator": "Elevator", "rudder": "Rudder", "fuselage": "Fuselage",
	"tank_l": "Left fuel tank", "tank_r": "Right fuel tank",
}
var parts := {}
var _touching := {}                 # body points in contact last step
var _gear_over: Array[bool] = [false, false, false]
var _overstress_t := 0.0
var _flap_over_t := 0.0
var crash_reason := ""
var frozen := false
var airborne := false
var air_time := 0.0
var _ground_time := 0.0
var _landing := false
var _td_sink := 0.0
var _td_speed := 0.0
var _td_pos := Vector3.ZERO
var _td_strip := -1
var _bounces := 0
var _hop_time := 0.0
var _was_down := true
var _in_water := false
var _flooded := 0.0                    # how full of water a ditched airframe is
var _mass_timer := 0.0
var _oob_warned := false

# per-tick caches
var _wind_now := Vector3.ZERO
# Gusts across the airframe (DESIGN_NOTES 154): sampled at the wingtips and
# the tail, in body axes relative to the gust at the CG, so each panel feels
# its own air.
var _gust_l := Vector3.ZERO
var _gust_r := Vector3.ZERO
var _gust_t := Vector3.ZERO
## What you feel in the seat: the specific force (everything but gravity)
## in body axes, m/s^2 - at rest on the ground about (0, 9.8, 0).
var seat_force := Vector3(0.0, 9.81, 0.0)
var turb_jolt := 0.0                 # how hard the air is kicking right now (for rumble / camera), 0..
var _surf: Array[int] = [0, 0, 0]
var _water_level := Terrain.NO_WATER
var _near_ground := true

# realism-dependent settings
var _torque_scale := 0.3
var _auto_rudder := true
var auto_trim := true
var _ground_assist := true
var _crash_speed := 9.0
var _hold_heading := 0.0
var _assist_rudder := 0.0
var _assist_aileron := 0.0
var _rudder_eff := 0.0

# scratch results from the coefficient helpers
var _cl := 0.0
var _cd := 0.0
var _s := 0.0

var _prev_xf := Transform3D.IDENTITY
var _cur_xf := Transform3D.IDENTITY


func _init() -> void:
	repair_all()
	engine.set_fuel(110.0)
	engine.event.connect(func(text: String): notice.emit(text))
	_build_wing()
	apply_gear()


## Fit the chosen tyres and legs.
func apply_gear() -> void:
	if not GearScript.TYRES.has(tyre_kind):
		tyre_kind = "850"
	if not GearScript.LEGS.has(leg_kind):
		leg_kind = "spring"
	var only_t := String(GearScript.TYRES[tyre_kind].get("only", ""))
	var only_l := String(GearScript.LEGS[leg_kind].get("only", ""))
	var sp: Dictionary = PlaneTypes.spec(plane_type)
	if String(sp.get("tyres", "")) != "":
		# a type with its own wheels and legs (DC-3, biplane)
		tyre_kind = String(sp["tyres"])
		leg_kind = String(sp.get("legs", "spring"))
	elif only_t != "" or only_l != "":
		tyre_kind = "850"
		leg_kind = "spring"
	var t: Dictionary = GearScript.TYRES[tyre_kind]
	var l: Dictionary = GearScript.LEGS[leg_kind]
	if is_amphib():
		_tyre = [GearScript.AMPHIB_MAIN, GearScript.AMPHIB_MAIN, GearScript.AMPHIB_NOSE]
		_leg = [l, l, GearScript.AMPHIB_NOSE_LEG]
		for i in range(3):
			hub_rest[i] = AMPHIB_HUBS[i]
		_gear_mass = float(l["mass"])
		_gear_drag = float(l["drag"])
	else:
		_tyre = [t, t, GearScript.TAIL_TYRE]
		_leg = [l, l, GearScript.TAIL_LEG]
		if plane_type == "dc3":
			_tyre[2] = GearScript.DC3_TAIL_TYRE
			_leg[2] = GearScript.DC3_TAIL_LEG
		for i in range(3):
			hub_rest[i] = HUB_STD[i]
		_gear_mass = float(t["mass"]) + float(l["mass"])
		_gear_drag = float(t["drag"])
		gear_down = true
		gear_pos = 1.0
	for i in range(3):
		wheel_pos[i] = hub_rest[i] - Vector3(0.0, float(_tyre[i]["radius"]), 0.0)
		water_pos[i] = wheel_pos[i]
	recompute_mass()


func is_amphib() -> bool:
	return leg_kind == "amphib"


## Wheels up or down (amphibious floats). Returns false if there are no wheels to move.
func has_skis() -> bool:
	return bool(GearScript.TYRES.get(tyre_kind, {}).get("ski", false))


## Skis down (wheel-skis fitted and lowered).
func skis_down() -> bool:
	return has_skis() and gear_down


func set_gear(down: bool) -> bool:
	if is_retractable():
		# The squat switch: with weight on the wheels the lever won't go up.
		if not down and on_ground:
			return false
		gear_down = down
		return true
	if not is_amphib() and not has_skis():
		return false
	gear_down = down
	return true


## The DC-3's main wheels fold forward and up into the nacelles (a third of
## each tyre still hangs out below); the tailwheel stays down.
func has_tail_lock() -> bool:
	return plane_type == "dc3"


func is_retractable() -> bool:
	return plane_type == "dc3"


const RETRACT_LIFT := 1.05      # metres the main wheels go up (dc3_visual swings them 85 degrees)
const RETRACT_FWD := 1.15       # and forward


## Gear moving: the engine-driven hydraulic pump does it in about 10 s;
## with both engines stopped, the hand pump takes much longer.
func _update_gear(delta: float) -> void:
	var was := gear_pos
	var pump := false
	for e in engines():
		if e.running:
			pump = true
	var t := 10.0 if pump else 45.0
	gear_pos = move_toward(gear_pos, 1.0 if gear_down else 0.0, delta / t)
	# Down on the tyres with the gear up: the propeller tips reach the ground.
	if on_ground and gear_pos < 0.45 and ground_speed > 1.0 and not is_crashed:
		for e in engines():
			if e.rpm > 250.0:
				hurt("prop", 0.5)
				e.stop("Prop strike! With the gear up the blades hit the ground.")
		if ground_speed > 8.0:
			hurt("fuselage", 0.004 * ground_speed * delta)
	if was < 1.0 and gear_pos >= 1.0:
		notice.emit("Gear down and locked: three green.")
	elif was > 0.0 and gear_pos <= 0.0:
		notice.emit("Gear up.")


func tyre_spec() -> Dictionary:
	return GearScript.TYRES[tyre_kind]


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF    # it smooths itself (render_xf)
	apply_realism()
	Game.settings_changed.connect(apply_realism)


func _build_wing() -> void:
	var sp: Dictionary = PlaneTypes.spec(plane_type)
	var dihedral := deg_to_rad(float(sp["dihedral"]))
	var xs: Array = sp["wing_x"]
	var areas: Array = sp["wing_panel_area"]
	var wy: float = sp["wing_y"]
	var half_span: float = wing_span * 0.5
	w_pos.clear()
	w_normal.clear()
	w_area.clear()
	w_twist.clear()
	w_flap.clear()
	w_ail.clear()
	w_blow.clear()
	for i in range(4):
		var x: float = xs[i]
		w_pos.append(Vector3(x, wy, 0.0))
		var side := 1.0 if x > 0.0 else -1.0
		w_normal.append(Vector3(-side * sin(dihedral), cos(dihedral), 0.0))
		w_area.append(areas[i])
		var outer := absf(x) > half_span * 0.45
		w_twist.append(-0.045 if outer else 0.0)
		w_flap.append(0.0 if outer else 1.0)
		w_ail.append((-side) if outer else 0.0)
		w_blow.append(0.0 if outer else 0.3)


func apply_realism() -> void:
	if Game.is_realistic():
		stall_blend = 0.14
		_torque_scale = 1.0
		_auto_rudder = false
		auto_trim = false
		_ground_assist = false
		hard_landing_sink = 2.0
		collapse_sink = 3.4
		_crash_speed = 6.5
		w_twist[0] = -0.03
		w_twist[3] = -0.03
	else:
		stall_blend = 0.25
		_torque_scale = 0.3
		_auto_rudder = true
		auto_trim = Game.auto_trim
		_ground_assist = true
		hard_landing_sink = 2.6
		collapse_sink = 4.6
		_crash_speed = 9.0
		w_twist[0] = -0.05
		w_twist[3] = -0.05


# ------------------------------------------------------------------------------
#  Weight and balance
# ------------------------------------------------------------------------------
func recompute_mass() -> void:
	# Fuel sits out along the wings, each side its own weight: run one tank dry
	# and the other wing is heavy (the balance point moves out, and every force
	# is taken about it, so she wants to roll that way).
	var tank_arm := wing_span * 0.145
	var fl: float = engine.total_fuel() if engine2 != null else engine.tank_left
	var fr: float = engine2.total_fuel() if engine2 != null else engine.tank_right
	var items: Array = [
		[empty_mass, empty_cg], [pilot_mass, STATION_PILOT],
		[fl, STATION_FUEL + Vector3(-tank_arm, 0, 0)], [fr, STATION_FUEL + Vector3(tank_arm, 0, 0)],
		[cargo_front + job_front, STATION_FRONT], [cargo_rear + job_rear, STATION_REAR],
		[maxf(_gear_mass, 0.001), Vector3(0.0, -1.7, 0.05) if is_amphib() else gear_mass_pos]]
	# engine oil, in the engine (a quart of oil is about 0.83 kg)
	var eng: Array = engines()
	for ei in range(eng.size()):
		items.append([float(eng[ei].oil_qts) * OIL_KG_PER_QT, props[mini(ei, props.size() - 1)] + Vector3(0, 0, 0.6)])
	var m := 0.0
	var moment := Vector3.ZERO
	for it in items:
		var im: float = it[0]
		var ip: Vector3 = it[1]
		m += im
		moment += ip * im
	mass = m
	cg = moment / m
	# Inertia about the new centre of gravity (parallel-axis for each lump).
	var ine := empty_inertia
	for it in items:
		var im: float = it[0]
		var d: Vector3 = it[1] - cg
		ine.x += im * (d.y * d.y + d.z * d.z)
		ine.y += im * (d.x * d.x + d.z * d.z)
		ine.z += im * (d.x * d.x + d.y * d.y)
	inertia = ine


func gross_mass() -> float:
	return mass


## Where the balance point sits between the forward (0) and aft (1) limits.
func cg_fraction() -> float:
	return (cg.z - CG_FWD_LIMIT) / (CG_AFT_LIMIT - CG_FWD_LIMIT)


func set_load(fuel_kg: float, front_kg: float, rear_kg: float) -> void:
	# Keep the world position of the airframe fixed while the balance point moves.
	var origin := pos - b * cg
	fuel = clampf(fuel_kg, 0.0, fuel_capacity)
	cargo_front = clampf(front_kg, 0.0, cargo_front_max)
	cargo_rear = clampf(rear_kg, 0.0, cargo_rear_max)
	recompute_mass()
	pos = origin + b * cg


## Job loads (passengers and cargo for jobs), kept apart from the Load menu's own.
func set_job_load(front_kg: float, rear_kg: float) -> void:
	var origin := pos - b * cg
	job_front = maxf(front_kg, 0.0)
	job_rear = maxf(rear_kg, 0.0)
	recompute_mass()
	pos = origin + b * cg


# ------------------------------------------------------------------------------
#  Atmosphere
# ------------------------------------------------------------------------------
func air_density(alt: float) -> float:
	var t0: float = Game.sea_level_temp_k()
	var temp := t0 - 0.0065 * alt
	var pressure := 101325.0 * pow(maxf(1.0 - 2.25577e-5 * alt, 0.1), 5.25588)
	oat_c = temp - 273.15
	_pressure_pa = pressure
	return pressure / (287.05 * temp)


# ------------------------------------------------------------------------------
#  Placement
# ------------------------------------------------------------------------------
func _reset_flags() -> void:
	brake_left = 0.0
	brake_right = 0.0
	is_crashed = false
	crash_reason = ""
	frozen = false
	omega = Vector3.ZERO
	elevator = 0.0
	aileron = 0.0
	rudder = 0.0
	in_pitch = 0.0
	in_roll = 0.0
	in_yaw = 0.0
	airborne = false
	air_time = 0.0
	_landing = false
	_bounces = 0
	_was_down = true
	_in_water = false
	_flooded = 0.0
	_oob_warned = false
	_seq = ""
	_lat_def = [0.0, 0.0, 0.0]
	wheel_locked = [false, false, false]
	wheel_sink = [0.0, 0.0, 0.0]
	tail_castering = false
	skid_level = 0.0
	# Being put back on a strip from the menu stands in for a recovery crew and a
	# mechanic until those exist in the game.
	repair_all()
	engine.water_in_fuel = 0.0
	recompute_mass()


## Park on a runway. `from_far_end` starts at the other end, facing back along it.
func place_on_strip(k: int, from_far_end: bool = false, along_offset: float = 0.0) -> void:
	_reset_flags()
	var s: Dictionary = terrain.strips[k]
	var hl: float = s["length"] * 0.5
	var heading: float = s["heading"]
	var along := -hl + 22.0 + along_offset
	if from_far_end:
		along = hl - 22.0 - along_offset
		heading += 180.0
	var p: Vector3 = terrain.strip_point(k, along)
	var yaw := -deg_to_rad(heading)
	var up: Vector3 = terrain.ground_normal_at(p.x, p.z)
	# Three-point attitude: nose about eleven degrees above the ground line.
	var flat := Basis(Vector3.UP, yaw)
	var fwd := (flat * FWD)
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var right := fwd.cross(up).normalized()
	var ground_basis := Basis(right, up, -fwd)
	var sit := Basis(Vector3.RIGHT, deg_to_rad(sit_pitch))
	b = (ground_basis * sit).orthonormalized()
	# Sit the wheels just above the surface and let the plane settle.
	var lowest := minf((sit * wheel_pos[0]).y, (sit * wheel_pos[2]).y)
	pos = p + up * (-lowest + 0.01) + b * cg
	if is_amphib():
		# On its float wheels: nearly level.
		gear_down = true
		gear_pos = 1.0
		b = (ground_basis * Basis(Vector3.RIGHT, deg_to_rad(2.7))).orthonormalized()
		pos = p + up * 2.36 + b * cg
	vel = Vector3.ZERO
	wheel_comp = [0.09, 0.09, 0.05]
	throttle = 0.0
	air_density(p.y)
	for e in engines():
		if Game.engine_auto:
			e.set_running(oat_c)
		else:
			e.set_cold_and_dark(oat_c)
	feathered = [false, false]
	power_frac = 0.0
	flap_notch = 0
	flaps = 0.0
	trim = 0.0
	brake = 1.0
	on_ground = true
	_hold_heading = heading_deg()
	_snap_transform()


## After the gear is changed on the ground (floats fitted, legs swapped), sit
## the plane back down on its new wheels where it stands, facing the same way.
func settle_here() -> void:
	if not on_ground:
		return
	var heading := heading_deg()
	_reset_flags()
	var datum := pos - b * cg
	var p := Vector3(datum.x, terrain.ground_level_at(datum.x, datum.z), datum.z)
	var yaw := -deg_to_rad(heading)
	var up: Vector3 = terrain.ground_normal_at(p.x, p.z)
	var fwd := Basis(Vector3.UP, yaw) * FWD
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var right := fwd.cross(up).normalized()
	var ground_basis := Basis(right, up, -fwd)
	if is_amphib():
		gear_down = true
		gear_pos = 1.0
		b = (ground_basis * Basis(Vector3.RIGHT, deg_to_rad(2.7))).orthonormalized()
		pos = p + up * 2.36 + b * cg
	else:
		var sit := Basis(Vector3.RIGHT, deg_to_rad(sit_pitch))
		b = (ground_basis * sit).orthonormalized()
		var lowest := minf((sit * wheel_pos[0]).y, (sit * wheel_pos[2]).y)
		pos = p + up * (-lowest + 0.01) + b * cg
	vel = Vector3.ZERO
	omega = Vector3.ZERO
	on_ground = true
	brake = 1.0
	_snap_transform()


## Start in the air on final approach to a runway, already settled into a
## steady descent at about 65 knots with 20 degrees of flap.
func place_on_approach(k: int, distance: float = 2400.0, height: float = 170.0) -> void:
	_reset_flags()
	var s: Dictionary = terrain.strips[k]
	var hl: float = s["length"] * 0.5
	var heading: float = s["heading"]
	var p: Vector3 = terrain.strip_point(k, -hl - distance)
	var threshold: Vector3 = terrain.strip_point(k, -hl)
	var yaw := -deg_to_rad(heading)
	b = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-1.0))
	pos = Vector3(p.x, threshold.y + height, p.z)
	# Do not start inside a hillside.
	var gh: float = terrain.height_at(p.x, p.z)
	pos.y = maxf(pos.y, gh + 120.0)
	var path := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-4.3))
	vel = (path * FWD) * approach_speed + _current_wind(pos)
	throttle = 0.2 if not is_twin() else 0.3
	air_density(pos.y)
	feathered = [false, false]
	for e in engines():
		e.set_running(oat_c)
		e.cht = oat_c + 85.0
		e.oil_temp = oat_c + 60.0
		e.prop_lever = 0.85
		e.mixture = EngineScript.best_mixture_for(air_density(pos.y) / 1.225)
		e.rpm = 1900.0
	power_frac = 0.2
	flap_notch = 2
	flaps = 0.5
	trim = -0.15
	brake = 0.0
	on_ground = false
	airborne = true
	air_time = 10.0
	_was_down = false
	_snap_transform()


## Start in the air at a given spot, heading and true airspeed.
func place_in_air(where: Vector3, heading: float, speed: float = 50.0) -> void:
	_reset_flags()
	var yaw := -deg_to_rad(heading)
	b = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(2.0))
	pos = where
	vel = (Basis(Vector3.UP, yaw) * FWD) * speed + _current_wind(pos)
	throttle = 0.6
	air_density(pos.y)
	feathered = [false, false]
	for e in engines():
		e.set_running(oat_c)
		e.cht = oat_c + 140.0
		e.oil_temp = oat_c + 72.0
		e.rpm = 2300.0
		e.mixture = EngineScript.best_mixture_for(air_density(pos.y) / 1.225)
	power_frac = 0.6
	flap_notch = 0
	flaps = 0.0
	trim = 0.0
	brake = 0.0
	on_ground = false
	airborne = true
	air_time = 10.0
	_was_down = false
	_snap_transform()


func _snap_transform() -> void:
	# A teleport, not flight: don't let the renderer smear across it.
	if is_inside_tree():
		reset_physics_interpolation.call_deferred()
	_cur_xf = Transform3D(b, pos - b * cg)
	_prev_xf = _cur_xf
	global_transform = _cur_xf


func _current_wind(p: Vector3) -> Vector3:
	if wind == null:
		return Vector3.ZERO
	return wind.sample(p)


# ------------------------------------------------------------------------------
#  Per-frame and per-tick driving
# ------------------------------------------------------------------------------
func _process(_delta: float) -> void:
	global_transform = render_xf()


## Where the plane is drawn this frame: between the last two flight ticks.
## The plane does its own smoothing, so the engine's physics interpolation is
## off for it (two interpolations on top of each other made it judder), and
## the camera asks for this rather than reading global_transform, which may
## not have been updated yet this frame.
func render_xf() -> Transform3D:
	var f := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	return _prev_xf.interpolate_with(_cur_xf, f)


func _physics_process(delta: float) -> void:
	if frozen or terrain == null:
		return
	# A plane standing still far from anyone dozes: nothing can move it out
	# there, so it isn't worth a flight step every tick. It wakes as you come.
	if on_ground and vel.length_squared() < 0.01 and throttle <= 0.0:
		var cam := get_viewport().get_camera_3d()
		if cam != null and cam.global_position.distance_squared_to(pos) > 700.0 * 700.0:
			return
		# (DESIGN_NOTES 186) a parked fleet plane dozes near you too, once it has
		# sat still for 2 s with the engine off: two flight sub-steps a tick for
		# every plane on the apron was the biggest cost at the home strip. It
		# wakes the moment something changes (fire, a crash, water, the engine).
		if may_doze and not engine_running and not on_fire and not is_crashed and not _in_water:
			_still_t += delta
			if _still_t > 2.0:
				return
	else:
		_still_t = 0.0
	simulate(delta)


var may_doze := false        # fleet.gd sets it on planes parked where you left them
var _still_t := 0.0


## Advance the flight by `delta` seconds. Split into small steps for stability.
var perf_ms := 0.0          # what the last flight step cost (perf readout)


func simulate(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_simulate_inner(delta)
	perf_ms = lerpf(perf_ms, float(Time.get_ticks_usec() - _t0) / 1000.0, 0.1)


func _simulate_inner(delta: float) -> void:
	_prev_xf = _cur_xf
	if is_amphib():
		gear_pos = move_toward(gear_pos, 1.0 if gear_down else 0.0, delta / 7.0)
	elif is_retractable():
		_update_gear(delta)
	_update_controls(delta)
	_update_ground_assist()
	_update_tick_cache()
	var steps := 2
	var dt := delta / float(steps)
	for i in range(steps):
		_step(dt)
	b = b.orthonormalized()
	_update_systems(delta)
	_cur_xf = Transform3D(b, pos - b * cg)


func _update_controls(delta: float) -> void:
	if is_crashed:
		in_pitch = 0.0
		in_roll = 0.0
		in_yaw = 0.0
		throttle = 0.0
	# Heavier stick forces at speed: full deflection is only available when slow.
	var q := 0.5 * air_density_now * airspeed * airspeed
	var q_ref := 0.5 * 1.225 * approach_speed * approach_speed
	var authority := clampf(q_ref / maxf(q, 1.0), 0.25, 1.0)
	var tp := clampf(in_pitch, -1.0, 1.0) * authority
	if not direct_controls:
		# A key is all-or-nothing, so give it less throw once the plane is flying fast.
		tp *= lerpf(1.0, 0.6, clampf((ias_kt - 50.0) / 30.0, 0.0, 1.0))
		if tp < 0.0:
			tp *= 0.7
	# Sim-lite: as the wing nears the stall the stick stops coming back, so holding
	# the nose up gives a slow mush with the horn sounding rather than a wing drop.
	var stall_room := 1.0
	if _ground_assist and not on_ground and not is_crashed and airspeed > 12.0:
		var limit := stall_alpha - 0.035 * flaps - 0.03
		stall_room = clampf((limit - wing_alpha) / 0.07, -0.35, 1.0)
		# The same goes for hauling the nose far above the horizon.
		var pitch_room := clampf((deg_to_rad(24.0) - pitch_rad()) / deg_to_rad(9.0), -0.35, 1.0)
		stall_room = minf(stall_room, pitch_room)
		tp = minf(tp, stall_room - trim * 0.45)
	var tr := clampf(in_roll, -1.0, 1.0) * lerpf(authority, 1.0, 0.35)
	var ty := clampf(in_yaw, -1.0, 1.0) * lerpf(authority, 1.0, 0.25)
	# Big aeroplanes have heavy, slow controls (control_rate below 1).
	var cr := control_rate
	if direct_controls:
		elevator = move_toward(elevator, tp, 6.0 * cr * delta)
		aileron = move_toward(aileron, tr, 7.0 * cr * delta)
		rudder = move_toward(rudder, ty, 6.0 * cr * delta)
	else:
		# Keyboard: ease toward the pressed direction, spring back when released.
		elevator = move_toward(elevator, tp, (1.5 if absf(tp) > absf(elevator) or signf(tp) != signf(elevator) else 3.0) * cr * delta)
		aileron = move_toward(aileron, tr, (3.0 if absf(tr) > absf(aileron) or signf(tr) != signf(aileron) else 4.2) * cr * delta)
		rudder = move_toward(rudder, ty, (2.6 if absf(ty) > absf(rudder) or signf(ty) != signf(rudder) else 4.0) * cr * delta)
	# Toe brakes. The "both brakes" control is split by the rudder, like pressing
	# harder on one pedal, so a rudder-plus-brakes turn tightens toward that side.
	var steer := clampf(in_yaw, -1.0, 1.0)
	_brake_wheel[0] = clampf(maxf(brake_left, brake * (1.0 - 0.85 * maxf(steer, 0.0))), 0.0, 1.0)
	_brake_wheel[1] = clampf(maxf(brake_right, brake * (1.0 + 0.85 * minf(steer, 0.0))), 0.0, 1.0)
	if parts["flaps"] >= 0.5:
		flaps = move_toward(flaps, float(flap_notch) / 4.0, 0.22 * delta)
	# Sim-lite: holding the stick slowly re-trims, so the plane keeps the attitude
	# you settled on when you let go. Realistic leaves trim to the pilot.
	if auto_trim and not on_ground and absf(in_pitch) > 0.1 and not is_crashed:
		# Trim takes over whatever the stick is currently holding, so letting go changes nothing.
		trim += elevator * 0.6 * delta
	trim = clampf(trim, -1.0, 1.0)
	throttle = clampf(throttle, 0.0, 1.0)


## Sim-lite only: with your feet off the rudder, the plane holds the heading it
## was last pointed at while rolling on the ground.
func _update_ground_assist() -> void:
	_assist_rudder = 0.0
	_assist_aileron = 0.0
	# In the air, with the stick centred, the wings ease back toward level.
	if _ground_assist and not on_ground and not is_crashed and absf(in_roll) < 0.05:
		_assist_aileron = clampf(-0.8 * roll_rad() + 0.3 * omega.z, -0.35, 0.35)
	if not _ground_assist or not on_ground or is_crashed:
		return
	var hdg := heading_deg()
	if absf(in_yaw) > 0.08 or ground_speed < 1.5 or absf(_brake_wheel[0] - _brake_wheel[1]) > 0.1:
		_hold_heading = hdg
		return
	var err := wrapf(hdg - _hold_heading, -180.0, 180.0)
	_assist_rudder = clampf(-0.07 * err + 0.9 * omega.y, -0.7, 0.7)


func _update_tick_cache() -> void:
	air_density_now = air_density(pos.y)
	_wind_now = Vector3.ZERO
	_gust_l = Vector3.ZERO
	_gust_r = Vector3.ZERO
	_gust_t = Vector3.ZERO
	if wind != null:
		if wind.has_method("gust_at"):
			var gc: Vector3 = wind.gust_at(pos)
			_wind_now = wind.sample(pos) + gc
			var half := wing_span * 0.42
			var bi := b.inverse()
			_gust_l = bi * (wind.gust_at(pos + b * Vector3(-half, 0.0, 0.0)) - gc)
			_gust_r = bi * (wind.gust_at(pos + b * Vector3(half, 0.0, 0.0)) - gc)
			_gust_t = bi * (wind.gust_at(pos + b * (TAIL_POS - cg)) - gc)
		else:
			_wind_now = wind.sample(pos) + wind.turbulence(pos)
	var gy: float = terrain.ground_level_at(pos.x, pos.z)
	agl = pos.y - maxf(gy, 0.0)
	_near_ground = agl < 25.0
	_water_level = Terrain.NO_WATER
	if _near_ground:
		var wl: float = terrain.water_level_at(pos.x, pos.z)
		if wl > -1.0e8 and not (terrain.lakes_frozen() and wl > 1.0):
			_water_level = wl
		for i in range(3):
			var pw := pos + b * (wheel_pos[i] - cg)
			var s: int = terrain.surface_at(pw.x, pw.z)
			_surf[i] = s
			_set_surface_props(i, s)
		surface_now = _surf[0]


func _set_surface_props(i: int, kind: int) -> void:
	_sp[i] = GearScript.surface(kind, Game.season)


# ------------------------------------------------------------------------------
#  Aerodynamic coefficients
# ------------------------------------------------------------------------------
func _wing_coeffs(a: float, fl: float, dctrl: float, ge: float) -> void:
	var a_pos := stall_alpha - 0.035 * fl
	var a_neg := -(stall_alpha - 0.07)
	var s := 0.0
	if a > a_pos:
		s = smoothstep(0.0, stall_blend, a - a_pos)
	elif a < a_neg:
		s = smoothstep(0.0, stall_blend, a_neg - a)
	var flap_lift := flap_dcl * fl * (1.25 - 0.25 * fl)
	var cl_lin := cl0 + flap_lift + cl_slope * clampf(a, a_neg, a_pos) + dctrl * (1.0 - 0.6 * s)
	var sa := sin(a)
	var ca := cos(a)
	_cl = lerpf(cl_lin, 2.1 * sa * ca, s)
	var cdi := _cl * _cl / (PI * 0.75 * aspect) * ge
	_cd = cd0_wing + 0.006 * fl + 0.085 * fl * fl + lerpf(cdi, 1.9 * sa * sa, s)
	_s = s


func _sym_coeffs(a: float, slope: float, a_stall: float, dctrl: float, ar: float) -> void:
	var s := 0.0
	var aa := absf(a)
	if aa > a_stall:
		s = smoothstep(0.0, 0.22, aa - a_stall)
	var cl_lin := slope * clampf(a, -a_stall, a_stall) + dctrl * (1.0 - 0.5 * s)
	var sa := sin(a)
	var ca := cos(a)
	_cl = lerpf(cl_lin, 2.0 * sa * ca, s)
	_cd = 0.012 + lerpf(_cl * _cl / (PI * 0.8 * ar), 1.8 * sa * sa, s)
	_s = s


# ------------------------------------------------------------------------------
#  One integration step
# ------------------------------------------------------------------------------
func _step(dt: float) -> void:
	var rho := air_density_now
	var vb := (vel - _wind_now) * b          # air-relative velocity in body axes
	var u := -vb.z
	var speed := vb.length()
	airspeed = speed
	alpha = atan2(-vb.y, maxf(absf(u), 0.5) * signf(u) if absf(u) > 0.01 else 0.5)
	beta = asin(clampf(vb.x / maxf(speed, 1.0), -1.0, 1.0))

	var fb := Vector3.ZERO      # force in body axes
	var tb := Vector3.ZERO      # torque about the CG in body axes

	# --- engines and propellers ----------------------------------------------------
	# Each engine pulls along its own thrust line, so on a twin a dead engine
	# swings the nose toward it; its windmilling prop drags until feathered.
	var disc := PI * prop_radius * prop_radius
	var ufwd := maxf(u, 0.0)
	var slip_dv := 0.0
	var slip_side: Array[float] = [0.0, 0.0]
	var thrust_total := 0.0
	var eng_list := engines()
	for ei in range(eng_list.size()):
		var e = eng_list[ei]
		var power: float = e.power if e.running else 0.0
		var thrust := 0.0
		if power > 1.0:
			var t_static := 0.60 * pow(2.0 * rho * disc * power * power, 1.0 / 3.0)
			var t_speed := 0.80 * power / maxf(ufwd, 1.0)
			thrust = t_static * t_speed / pow(pow(t_static, 3.0) + pow(t_speed, 3.0), 1.0 / 3.0)
			thrust *= 0.35 + 0.65 * parts["prop"] if parts["prop"] > 0.05 else 0.0
		# A slow-turning or stopped prop is an airbrake; a feathered one is not.
		var pf: float = e.power / maxf(e.rated_power, 1.0)
		var windmill := 0.25 if not e.running else 0.14 * (1.0 - pf)
		if is_twin():
			windmill *= 4.5        # a big three-blade prop windmilling is a barn door
			if feathered[ei] and not e.running:
				windmill = 0.04
		thrust -= 0.5 * rho * ufwd * ufwd * windmill
		engine_thrust[ei] = thrust
		thrust_total += thrust
		if thrust > 0.0:
			var sdv := sqrt(ufwd * ufwd + 2.0 * thrust / (rho * disc)) - ufwd
			slip_dv = maxf(slip_dv, sdv)
			slip_side[mini(ei, 1)] = sdv
		var f_thrust := Vector3(0.0, 0.0, -thrust)
		fb += f_thrust
		tb += (props[mini(ei, props.size() - 1)] - cg).cross(f_thrust)
		# Gyroscopic precession: the spinning prop is a flywheel, so pitching
		# swings the nose sideways and yawing pitches it (tail up on the
		# take-off roll = nose swinging left with these right-hand props).
		if e.running or e.rpm > 300.0:
			var hprop: float = prop_inertia * e.rpm * TAU / 60.0
			tb += omega.cross(Vector3(0.0, 0.0, hprop))
		if power > 1.0 and not is_twin():
			var shaft_torque := power / (maxf(rpm, 500.0) * TAU / 60.0)
			# The airframe is rigged to fly level at cruise, so only the difference from
			# cruise torque is felt: a pull to the left at full power, a little right in a glide.
			var q_ratio := clampf(rho * speed * speed / (1.225 * 52.0 * 52.0), 0.0, 1.2)
			var rigged := 0.75 * (0.6 * rated_power / 251.0) * q_ratio
			tb.z += _torque_scale * (shaft_torque - rigged)
			tb.y += _torque_scale * maxf(thrust, 0.0) * (0.045 + 0.55 * clampf(alpha, 0.0, 0.35))
	thrust_now = thrust_total
	# On a twin the props sit out on the wings: the tail is not in the
	# slipstream, and each inner wing panel is blown only by its own engine.
	var tail_slip := 0.0 if is_twin() else slip_dv

	# --- wing ------------------------------------------------------------------
	var wing_height := maxf(agl + 0.9, 0.3) / wing_span
	var gx := 16.0 * wing_height
	var ge := gx * gx / (1.0 + gx * gx)
	var inner_cl := 0.0
	var inner_s := 0.0
	var inner_a := 0.0
	for i in range(4):
		var r := w_pos[i] - cg
		var nrm := w_normal[i]
		var gx2 := clampf(r.x / maxf(wing_span * 0.42, 0.5), -1.0, 1.0)
		var dg := _gust_l * -gx2 if gx2 < 0.0 else _gust_r * gx2
		var ve := vb + omega.cross(r) - dg
		var blow := slip_dv
		if is_twin():
			blow = slip_side[0] if i < 2 else slip_side[1]
		var vc := -ve.z + w_blow[i] * blow
		var vn := ve.dot(nrm)
		var v2 := vc * vc + vn * vn
		if v2 < 0.04:
			continue
		var q := 0.5 * rho * v2
		var a := atan2(-vn, vc) + w_twist[i]
		var fl := flaps * w_flap[i]
		var left_side := i < 2
		if (i == 0 and wing_off[0]) or (i == 3 and wing_off[1]):
			continue
		var ail_h: float = parts["aileron_l"] if left_side else parts["aileron_r"]
		_wing_coeffs(a, fl, w_ail[i] * clampf(aileron + _assist_aileron, -1.0, 1.0) * AIL_DCL * ail_h, ge)
		var wing_h: float = parts["wing_l"] if left_side else parts["wing_r"]
		if is_crashed:
			# a wreck doesn't fly: the wings are bent, torn and crumpled
			# (it used to bounce back into the air on its own lift - Dave)
			_cl *= 0.12
			_cd += 0.3
		if wing_h < 0.98:
			_cl *= 0.7 + 0.3 * wing_h
			_cd += (1.0 - wing_h) * 0.05
		var vm := sqrt(v2)
		var area := w_area[i]
		var lift_dir := (nrm * vc - FWD * vn) / vm
		var drag_dir := -(FWD * vc + nrm * vn) / vm
		var f := lift_dir * (q * area * _cl) + drag_dir * (q * area * _cd)
		fb += f
		tb += r.cross(f)
		tb.x += q * area * chord * (cm0 + cm_flap * fl) * (1.0 - _s)
		if w_flap[i] > 0.5:
			inner_cl += _cl * 0.5
			inner_s = maxf(inner_s, _s)
			inner_a = maxf(inner_a, a)
	wing_alpha = inner_a
	stalled = inner_s > 0.35
	stall_warning = inner_a > (stall_alpha - 0.035 * flaps) - 0.075 and speed > 8.0 and not on_ground

	# --- tailplane ---------------------------------------------------------------
	var rt := TAIL_POS - cg
	var vt := vb + omega.cross(rt) - _gust_t
	var tvc := -vt.z + 0.55 * tail_slip
	var tvn := vt.y
	var tv2 := tvc * tvc + tvn * tvn
	if tv2 > 0.04:
		var downwash := 2.0 * inner_cl / (PI * aspect) * (1.0 - 0.6 * inner_s)
		var at := atan2(-tvn, tvc) - downwash + tail_incidence
		var elev_cmd := clampf(elevator + trim * 0.45, -1.15, 1.15)
		_sym_coeffs(at, TAIL_SLOPE, 0.27, -ELEV_DCL * elev_cmd * (0.4 + 0.6 * parts["elevator"]), TAIL_ASPECT)
		if is_crashed:
			_cl *= 0.2
		var tq := 0.5 * rho * tv2
		var tvm := sqrt(tv2)
		var tl := (Vector3.UP * tvc - FWD * tvn) / tvm
		var td := -(FWD * tvc + Vector3.UP * tvn) / tvm
		var ft := tl * (tq * TAIL_AREA * _cl) + td * (tq * TAIL_AREA * _cd)
		fb += ft
		tb += rt.cross(ft)

	# --- fin and rudder ------------------------------------------------------------
	var rudder_eff := clampf(rudder + _assist_rudder, -1.0, 1.0)
	if _auto_rudder and not on_ground and speed > 15.0 and absf(in_yaw) < 0.08:
		rudder_eff = clampf(rudder + 2.2 * beta, -0.6, 0.6)
	_rudder_eff = rudder_eff
	var rf := FIN_POS - cg
	var vf := vb + omega.cross(rf) - _gust_t
	var fvc := -vf.z + 0.75 * tail_slip
	var fvn := vf.x
	var fv2 := fvc * fvc + fvn * fvn
	if fv2 > 0.04:
		_sym_coeffs(atan2(-fvn, fvc), FIN_SLOPE, 0.30, -RUD_DCL * rudder_eff * (0.4 + 0.6 * parts["rudder"]), 1.6)
		var fq := 0.5 * rho * fv2
		var fvm := sqrt(fv2)
		var fl2 := (Vector3.RIGHT * fvc - FWD * fvn) / fvm
		var fd2 := -(FWD * fvc + Vector3.RIGHT * fvn) / fvm
		var ff := fl2 * (fq * FIN_AREA * _cl) + fd2 * (fq * FIN_AREA * _cd)
		fb += ff
		tb += rf.cross(ff)

	# --- fuselage side area ----------------------------------------------------------
	var rs := SIDE_POS - cg
	var vs := vb + omega.cross(rs)
	var svc := -vs.z
	var svn := vs.x
	var sv2 := svc * svc + svn * svn
	if sv2 > 0.04:
		_sym_coeffs(atan2(-svn, svc), SIDE_SLOPE, 0.45, 0.0, 0.4)
		var sq := 0.5 * rho * sv2
		var svm := sqrt(sv2)
		var sl := (Vector3.RIGHT * svc - FWD * svn) / svm
		var fs := sl * (sq * SIDE_AREA * _cl) - (FWD * svc + Vector3.RIGHT * svn) / svm * (sq * SIDE_AREA * (_cd - 0.012))
		fb += fs
		tb += rs.cross(fs)

	# --- everything else that drags ---------------------------------------------------
	var door_drag := (0.12 if door_open["cabin"] else 0.0) + (0.06 if door_open["bay"] else 0.0) + (0.2 if door_open.get("cowl", false) else 0.0) \
		+ (0.25 if door_open.get("cowl0", false) else 0.0) + (0.25 if door_open.get("cowl1", false) else 0.0)
	var gear_up_saving := 0.38 * (1.0 - gear_pos) if is_retractable() else 0.0
	var f_par: Vector3 = -vb * (0.5 * rho * speed * (parasite_area - gear_up_saving + _gear_drag + door_drag) * (1.0 + 0.4 * (1.0 - float(parts["fuselage"]))))
	f_par.y -= 0.5 * rho * absf(vb.y) * vb.y * 2.5
	fb += f_par
	tb += (DRAG_POS - cg).cross(f_par)

	# --- rough air rocking the wings ----------------------------------------------------
	if wind != null and speed > 5.0 and not wind.has_method("gust_at"):
		var up: Vector3 = wind.upset()
		var qbar := 0.5 * rho * speed * speed
		tb.z += up.x * qbar * wing_area * wing_span * 0.006
		tb.x += up.y * qbar * wing_area * chord * 0.012
		tb.y += up.z * qbar * wing_area * wing_span * 0.0025

	g_load = fb.y / (mass * GRAVITY)
	slip_ball = clampf(-(fb.x / mass) / GRAVITY * 5.0, -1.0, 1.0)

	# --- ground and water --------------------------------------------------------------
	var fw := b * fb
	fw.y -= mass * GRAVITY
	var tw := Vector3.ZERO
	wheels_down = 0
	if _near_ground:
		var res := _contacts(dt)
		fw += res[0]
		tw = res[1]
	else:
		wheel_comp[0] = 0.0
		wheel_comp[1] = 0.0
		wheel_comp[2] = 0.0
	on_ground = wheels_down > 0
	dbg_aero_yaw = tb.y
	dbg_contact_yaw = (tw * b).y
	tb += tw * b
	if _ground_assist and on_ground and not is_crashed and absf(_brake_wheel[0] - _brake_wheel[1]) < 0.1:
		tb.y -= omega.y * 5500.0 * _mscale() * clampf(float(wheels_down) / 3.0, 0.0, 1.0)

	# --- what the pilot feels -----------------------------------------------------------
	var sf: Vector3 = ((fw + Vector3(0.0, mass * GRAVITY, 0.0)) / mass) * b
	turb_jolt = lerpf(turb_jolt, (sf - seat_force).length() / maxf(dt, 0.001) * 0.002, 0.2)
	seat_force = sf

	# --- integrate --------------------------------------------------------------------
	vel += fw / mass * dt
	var io := Vector3(inertia.x * omega.x, inertia.y * omega.y, inertia.z * omega.z)
	var net := tb - omega.cross(io)
	omega += Vector3(net.x / inertia.x, net.y / inertia.y, net.z / inertia.z) * dt
	# Keep a wreck or a glitch from spinning up without limit.
	var wl := omega.length()
	if wl > 12.0:
		omega *= 12.0 / wl
	pos += vel * dt
	var ang := omega.length() * dt
	if ang > 1.0e-9:
		b = b * Basis(omega.normalized(), ang)


## Sim-lite still lets rocks bite, but only at speed.
func _ground_assist_free_rocks() -> bool:
	return _ground_assist and ground_speed < 9.0


## Tyre force for a squash of `d` metres: a stiff spring until the rim hits.
static func _tyre_force(t: Dictionary, d: float, flat: bool) -> float:
	if d <= 0.0:
		return 0.0
	var k: float = t["k"]
	var travel: float = t["travel"]
	if flat:
		k *= 0.22
		travel *= 1.5
	var f := k * d
	if d > travel:
		f += k * 9.0 * (d - travel)
	return f


static func _tyre_slope(t: Dictionary, d: float, flat: bool) -> float:
	if d <= 0.0:
		return 0.0
	var k: float = t["k"] * (0.22 if flat else 1.0)
	return k * (10.0 if d > float(t["travel"]) * (1.5 if flat else 1.0) else 1.0)


## Leg spring force at stroke `x`, and its slope.
static func _leg_force(l: Dictionary, x: float) -> float:
	var tr: float = l["travel"]
	var q := x / tr
	return float(l["preload"]) + float(l["k"]) * x * (1.0 + float(l["prog"]) * q * q)


static func _leg_slope(l: Dictionary, x: float) -> float:
	var q := x / float(l["travel"])
	return float(l["k"]) * (1.0 + 3.0 * float(l["prog"]) * q * q)


## One wheel: leg, tyre, grip, brakes. Returns [force, torque, skid 0..1, submerged]
## in world axes, or [] when the wheel is off the ground.
func _wheel(i: int, dt: float, plane_fwd: Vector3) -> Array:
	var t: Dictionary = _tyre[i]
	var l: Dictionary = _leg[i]
	var radius: float = t["radius"]
	if skis_down():
		radius += 0.05        # the ski sits a little below the tyre
	var gear_name: String = ["gear_l", "gear_r", "tailwheel"][i]
	var gh: float = parts[gear_name]
	# A collapsed leg no longer holds anything up.
	if gh < 0.25 or (is_amphib() and gear_pos < 0.98):
		wheel_water[i] = 0.0
		wheel_comp[i] = 0.0
		tyre_defl[i] = 0.0
		wheel_load[i] = 0.0
		return []
	var tyre_h: float = parts["tire_l"] if i == 0 else (parts["tire_r"] if i == 1 else 1.0)
	var flat := tyre_h < 0.4
	# A bent leg sits lower and toes out.
	var sag := (1.0 - gh) * 0.25 * float(gh < 0.75)
	var s: float = wheel_comp[i]
	var hub := hub_rest[i] + Vector3(0.0, s + sag, 0.0)
	if is_retractable() and i < 2 and gear_pos < 1.0:
		var up_by := 1.0 - gear_pos
		hub += Vector3(0.0, RETRACT_LIFT * up_by, -RETRACT_FWD * up_by)
	var rw := hub - cg
	var arm := b * rw
	var ph := pos + arm
	var vp := vel + b * omega.cross(rw)
	var up := b.y
	var submerged := false
	var force := Vector3.ZERO
	var torque := Vector3.ZERO
	var sp: Dictionary = _sp[i]
	if sp.is_empty():
		sp = GearScript.surface(Terrain.SURF_ROUGH, Game.season)

	# Water. A tyre driven through it at speed rides up on it like a water ski
	# (fat tundra tyres skim along; skinny ones dig in), drags hard and throws
	# spray. Slow down and it sinks, and the drag down below the centre of gravity
	# tips the nose over.
	wheel_water[i] = 0.0
	if _surf[i] == Terrain.SURF_WATER and _water_level > -1.0e8:
		var bottom := ph - up * radius
		var d_w := _water_level - bottom.y
		if d_w > 0.0:
			var tw: float = float(t.get("width", 0.12))
			var dd := minf(d_w, 2.0 * radius)
			var half := sqrt(maxf(2.0 * radius * dd - dd * dd, 0.0))   # half the wetted length
			if skis_down():
				# A ski is a long flat board: lots of planing area, little to dig in.
				tw = 0.32
				half = minf(0.9, 0.25 + dd * 8.0)
			var vh := Vector3(vp.x, 0.0, vp.z)
			var u := vh.length()
			var q := 500.0 * u * u
			# Air-filled tyre: it floats. At speed the wetted front of the tyre is a
			# ramp the water hits, steeper the deeper it rides: lift and drag from
			# that, so a light touch skims and a deep one trips.
			var vdown := maxf(-vp.y, 0.0)
			var lift := 9810.0 * tw * 1.33 * half * dd
			var ramp := atan2(dd, maxf(half, 0.01))
			var n_force := q * tw * half * 0.45 * sin(ramp)
			# Deeper than about a third of the tyre the water starts pouring over
			# the top instead of holding it up: lift fades and drag takes over.
			var holds := clampf(1.0 - (dd - radius * 0.2) / (radius * 0.3), 0.0, 1.0)
			lift += n_force * cos(ramp) * holds
			lift += (150.0 * vdown * vdown + 500.0 * vdown) * tw * 2.0 * half
			# Drag: the ramp, skin friction, and ploughing once the hub goes under.
			var drag := n_force * sin(ramp) + q * 0.02 * tw * 2.0 * half
			drag += q * 1.3 * tw * maxf(dd - radius * 0.4, 0.0)
			if skis_down():
				# A ski is a flat board at the plane's own trim angle: it planes
				# well and only digs in when driven deep or nose-down.
				var trim := clampf((b * FWD).y + 0.05, 0.02, 0.35)
				var wet_len := clampf(0.3 + dd / maxf(sin(trim), 0.05), 0.3, 1.6)
				var nf := q * tw * wet_len * 0.9 * sin(trim)
				lift = 9810.0 * tw * wet_len * dd * 0.5 + nf * cos(trim)
				lift += (150.0 * vdown * vdown + 500.0 * vdown) * tw * wet_len
				drag = nf * sin(trim) + q * 0.006 * tw * wet_len + q * 1.0 * tw * maxf(dd - 0.22, 0.0)
			# Forced in hard at speed, the leg cannot take it.
			if drag > mass * GRAVITY * 0.9 and not is_crashed:
				hurt(gear_name, (drag / (mass * GRAVITY) - 0.9) * 0.08)
			var fwater := Vector3(0.0, lift, 0.0)
			if u > 0.05:
				fwater -= vh / u * drag
			force += fwater
			torque += (bottom - pos).cross(fwater)
			wheel_water[i] = dd
			wheel_spin_rate[i] = lerpf(wheel_spin_rate[i], u / radius, 0.2)
			submerged = dd > radius * 1.3

	# The ground under the axle, with the strip's own bumps and ruts. Big soft
	# tyres roll over the small ones.
	var gy: float = terrain.ground_level_at(ph.x, ph.z)
	var bump_h: float = float(sp["bump"]) * float(t["rough"])
	if bump_h > 0.0:
		var sc: float = sp["scale"]
		var u := ph.x / sc
		var w := ph.z / sc
		gy += bump_h * (0.6 * sin(u * 2.1 + w * 0.7) * sin(w * 1.9 - u * 0.4) + 0.4 * sin(u * 5.3 + 1.3) * sin(w * 4.7 + 0.4))
	var nrm: Vector3 = terrain.ground_normal_at(ph.x, ph.z)
	var dist := (ph.y - gy) * nrm.y
	# Soft ground: the tyre settles in, more under a heavy load, less with a wide soft tyre.
	var sink_target: float = float(sp["soft"]) * clampf(wheel_load[i] / (5000.0 * _mscale()), 0.0, 1.6) / float(t["float"])
	wheel_sink[i] = lerpf(wheel_sink[i], sink_target, clampf(dt * 3.0, 0.0, 1.0))
	var d0 := radius - dist - wheel_sink[i]
	var a := maxf(up.dot(nrm), 0.2)

	# Leg: settle the stroke where the tyre and the leg spring balance, held back
	# by the damper. Solved implicitly so a stiff tyre cannot make it shake.
	var ft0 := _tyre_force(t, d0, flat)
	var f0 := ft0 - _leg_force(l, s)
	var c: float = l["comp"] if f0 > 0.0 else l["reb"]
	if _ground_assist and f0 <= 0.0:
		c = c * 4.0 + 3000.0     # sim-lite: legs that extend slowly, so a firm arrival does not bounce
	var k_e := _tyre_slope(t, d0, flat) * a + _leg_slope(l, s)
	var tr: float = l["travel"]
	var s_new := clampf(s + dt * f0 / (c + dt * k_e), 0.0, tr)
	var s_rate := (s_new - s) / dt
	wheel_comp[i] = s_new
	var d := d0 - (s_new - s) * a
	tyre_defl[i] = maxf(d, 0.0)
	if d <= 0.0:
		wheel_load[i] = 0.0
		_lat_def[i] = 0.0
		wheel_locked[i] = false
		wheel_spin_rate[i] *= 0.995
		if _rim_hit[i] and s_new < tr * 0.5:
			_rim_hit[i] = false
		_gear_over[i] = false
		return [force, torque, 0.0, submerged] if force != Vector3.ZERO else []
	# Tyre force plus the little damping inside the tyre itself.
	var vn := vp.dot(nrm)
	var m_corner := mass * 0.4
	var c_t: float = float(t["damp"]) * 2.0 * sqrt(float(t["k"]) * m_corner)
	var fn := maxf(_tyre_force(t, d, flat) + c_t * (-vn - s_rate * a), 0.0)
	if fn <= 0.0:
		wheel_load[i] = 0.0
		return [force, torque, 0.0, submerged] if force != Vector3.ZERO else []
	wheel_load[i] = fn
	wheels_down += 1

	# Overload: a leg bottomed out hard, or a tyre squashed onto its rim.
	var strength: float = float(l.get("strength", 1.0)) * (1.25 if _ground_assist else 1.0)
	var limit := mass * GRAVITY * (2.6 if i < 2 else 1.1) * strength
	if fn > limit and s_new >= tr * 0.97:
		if not _gear_over[i]:
			_gear_over[i] = true
			hurt(gear_name, 0.35 + 0.5 * (fn / limit - 1.0))
	elif fn < limit * 0.6:
		_gear_over[i] = false
	var t_travel: float = float(t["travel"]) * (1.5 if flat else 1.0)
	if d > t_travel + 0.02 and i < 2:
		if not _rim_hit[i]:
			_rim_hit[i] = true
			hurt("tire_l" if i == 0 else "tire_r", 0.12 + 4.0 * (d - t_travel))
	elif d < t_travel * 0.5:
		_rim_hit[i] = false

	# Rocks and holes on untended ground: small hard tyres pay for it.
	if i < 2 and _surf[i] == Terrain.SURF_ROUGH and not _ground_assist_free_rocks():
		var spd := absf(vp.dot(plane_fwd))
		var rough: float = t["rough"]
		if spd > 4.0 and randf() < dt * spd / 30.0 * 0.12 * rough * rough:
			hurt("tire_l" if i == 0 else "tire_r", randf_range(0.08, 0.3) * rough)
			if randf() < 0.3 * rough:
				hurt(gear_name, randf_range(0.05, 0.2))

	# Which way the wheel rolls. The tailwheel steers with the rudder through
	# springs, until a hard sideways load or one brake makes it break out and
	# swivel freely. A bent main leg toes the wheel out.
	var roll_dir := plane_fwd
	var vflat := vp - nrm * vn
	if i == 2 and is_amphib():
		# Nose wheels steer with the rudder pedals (the other way to a tailwheel).
		roll_dir = (b * Basis(Vector3.UP, -_rudder_eff * deg_to_rad(18.0))) * FWD
		tail_castering = false
	elif i == 2 and has_tail_lock() and _ground_assist and not tail_lock and ground_speed > 15.0 and absf(omega.y) < 0.06:
		# Sim-lite locks it for you once you're rolling straight.
		tail_lock = true
		roll_dir = plane_fwd
	elif i == 2 and tail_lock and has_tail_lock():
		# Locked straight ahead for the take-off or landing roll. A hard
		# sideways shove shears the lock pin's grip and it breaks out.
		roll_dir = plane_fwd
		tail_castering = false
		if absf((vp - nrm * vn).dot(plane_fwd.cross(nrm))) > 9.0:
			tail_lock = false
			notice.emit("The tailwheel lock has kicked out.")
	elif i == 2:
		var diff_brake := absf(_brake_wheel[0] - _brake_wheel[1]) > 0.5
		if tail_castering:
			# Swings round to trail behind its pivot; locks back in once it lines up.
			var vdir := vflat.normalized() if vflat.length() > 0.3 else plane_fwd
			var steer_dir := (b * Basis(Vector3.UP, _rudder_eff * deg_to_rad(22.0))) * FWD
			if not diff_brake and vdir.dot(steer_dir) > 0.985:
				tail_castering = false
			else:
				roll_dir = vdir
		if _ground_assist and tail_lock and ground_speed < 8.0:
			tail_lock = false        # sim-lite frees it again for taxi turns
		if not tail_castering:
			var steer := _rudder_eff * deg_to_rad(26.0 if _ground_assist else 20.0)
			roll_dir = (b * Basis(Vector3.UP, steer)) * FWD
			if diff_brake:
				tail_castering = true
	elif gh < 0.75:
		var toe := (0.75 - gh) * 0.35 * (1.0 if i == 0 else -1.0)
		roll_dir = (b * Basis(Vector3.UP, toe)) * FWD
	roll_dir = roll_dir - nrm * roll_dir.dot(nrm)
	if roll_dir.length_squared() < 1.0e-6:
		return [force, torque, 0.0, submerged]
	roll_dir = roll_dir.normalized()
	var side_dir := roll_dir.cross(nrm)
	var vlong := vp.dot(roll_dir)
	var vlat := vp.dot(side_dir)
	var grip: float = sp["grip"]
	var slide: float = sp["slide"]
	if flat:
		grip *= 0.6
		slide *= 0.6
	var grip_f := grip * fn

	# Rolling drag: the surface, how deep the tyre has sunk (it is pushing a bow
	# wave of mud or snow), and a flat.
	var rr: float = float(sp["roll"]) * sqrt(0.26 / radius) + 0.9 * wheel_sink[i] / radius
	var on_skis := skis_down() and i < 2 or (skis_down() and i == 2)
	if on_skis:
		# Skis slide on snow and ice and drag on bare ground.
		var sf: int = _surf[i]
		rr = 0.025 if sf >= 4 and sf <= 6 else (0.32 if sf == 2 else 0.45)
	if flat:
		rr += 0.18

	# Brakes. Too much and the wheel locks and skids, and a skidding tyre has no
	# sideways grip left. Sim-lite stops just short of a lock.
	var brake_now := 0.0
	if i < 2:
		brake_now = maxf(_brake_wheel[i], 1.0 if park_brake else 0.0)
		if _ground_assist:
			var nose_down := (b * FWD).y
			brake_now *= clampf(1.0 + (nose_down + 0.02) * 9.0, 0.15, 1.0)
	var brake_f := brake_force * brake_now
	if on_skis:
		brake_f = 0.0          # no brakes on skis
	if _ground_assist:
		brake_f = minf(brake_f, grip_f * 0.92)
	if i < 2:
		if not wheel_locked[i] and brake_f > grip_f and absf(vlong) > 1.0:
			wheel_locked[i] = true
		elif wheel_locked[i] and (brake_f < grip_f * 0.7 or absf(vlong) < 0.3):
			wheel_locked[i] = false

	var flong := 0.0
	var flat_f := 0.0
	var skid := 0.0
	if i == 2 and tail_castering:
		# Swivelling freely: it only drags a little, whichever way it is pushed.
		var vc := Vector2(vlong, vlat)
		var vcl := vc.length()
		var fs := (rr + 0.03) * fn * clampf(vcl / 0.05, 0.0, 1.0)
		if vcl > 0.001:
			flong = -vlong / vcl * fs
			flat_f = -vlat / vcl * fs
		_lat_def[i] = 0.0
		wheel_spin_rate[i] = vcl / radius
	elif wheel_locked[i]:
		var vc := Vector2(vlong, vlat)
		var vcl := vc.length()
		var fs := slide * fn
		if vcl > 0.05:
			flong = -vlong / vcl * fs
			flat_f = -vlat / vcl * fs
		_lat_def[i] = 0.0
		wheel_spin_rate[i] = 0.0
		skid = clampf(vcl / 6.0, 0.3, 1.0)
	else:
		var lim := minf(rr * fn + brake_f, grip_f)
		flong = -clampf(vlong * 40000.0 * _mscale(), -lim, lim)
		wheel_spin_rate[i] = vlong / radius
		# Sideways: the tyre's contact patch twists before it slides. The twist
		# relaxes as the wheel rolls, which gives a slip-angle force at speed and
		# a gentle hold when parked.
		var sigma := radius * 1.6
		var c_alpha: float = float(t["corner"]) * fn * (0.35 if on_skis else 1.0)
		var k_y := c_alpha / sigma
		_lat_def[i] += (vlat - absf(vlong) * _lat_def[i] / sigma) * dt
		var c_y := 0.25 * sqrt(k_y * m_corner) / (1.0 + absf(vlong))
		var fy := -k_y * _lat_def[i] - c_y * vlat
		var fy_max := sqrt(maxf(grip_f * grip_f - flong * flong, 0.0))
		if absf(fy) > fy_max:
			# Sliding sideways: grip falls off toward the sliding value.
			var over := absf(fy) / maxf(fy_max, 1.0) - 1.0
			var mu_now := lerpf(1.0, slide / maxf(grip, 0.01), clampf(over * 1.5, 0.0, 1.0))
			fy = signf(fy) * fy_max * mu_now
			_lat_def[i] = -(fy + c_y * vlat) / k_y
			skid = clampf(absf(vlat) / 5.0, 0.0, 1.0)
		flat_f = fy
		# Too much sideways load breaks the tailwheel out of its steering.
		if i == 2 and not tail_castering and absf(fy) > fn * 0.5 and absf(vlat) > 0.8:
			tail_castering = true

	var f := nrm * fn + roll_dir * flong + side_dir * flat_f
	var contact := arm - b.y * (radius - d)
	force += f
	torque += contact.cross(f)
	return [force, torque, skid, submerged]


## Float plane only: sit on the water at `where` (x, z), pointing `heading`.
func place_on_water(where: Vector3, heading: float) -> void:
	place_in_air(where, heading, 0.0)
	gear_down = false
	gear_pos = 0.0
	var wl: float = terrain.water_level_at(where.x, where.z)
	b = Basis(Vector3.UP, -deg_to_rad(heading)) * Basis(Vector3.RIGHT, deg_to_rad(3.0))
	pos = Vector3(where.x, wl + 1.75, where.z) + b * cg
	vel = Vector3.ZERO
	omega = Vector3.ZERO
	throttle = 0.0
	on_ground = true
	airborne = false
	air_time = 0.0
	_was_down = true
	_snap_transform()


## Floats: buoyancy along each one, the water pushing up on the bottom as it
## planes (more the faster and the more nose-up), skin drag, the bow wave at
## low speed, the keel holding against sideslip, water rudders at the sterns,
## and the keel sliding on land, a beach or ice. Returns [force, torque].
var float_ground_n := 0.0          # debug: how hard the float keels press on land

func _floats(_dt: float) -> Array:
	float_ground_n = 0.0
	var force := Vector3.ZERO
	var torque := Vector3.ZERO
	var up_b := b.y
	var side_b := b.x
	var fwd_b := b * FWD
	var frozen_lakes: bool = terrain.lakes_frozen()
	var n := FLOAT_ST.size()
	var u_fwd := vel.dot(fwd_b)
	water_rudders = absf(u_fwd) < 8.0
	for fi in range(2):
		var sx := -FLOAT_X if fi == 0 else FLOAT_X
		var deepest := 0.0
		var bow_k := -1
		var disp := 0.0
		var disp_at := Vector3.ZERO
		for k in range(n):
			var st: Array = FLOAT_ST[k]
			var z: float = st[0]
			var keel: float = st[1]
			var hb: float = st[2]
			var deck: float = st[3]
			var z0: float = FLOAT_ST[maxi(k - 1, 0)][0]
			var z1: float = FLOAT_ST[mini(k + 1, n - 1)][0]
			var dz := (z1 - z0) * 0.5
			var rp := Vector3(sx, keel, z) - cg
			var arm := b * rp
			var pw := pos + arm
			var vp := vel + b * omega.cross(rp)
			# Water
			var wl: float = terrain.water_level_at(pw.x, pw.z)
			if wl > -1.0e8 and not (frozen_lakes and wl > 1.0):
				if waves != null:
					wl += waves.height_at(pw.x, pw.z)
				var sub := wl - pw.y
				if sub > 0.0:
					var hgt := deck - keel
					var sc := minf(sub, hgt)
					var area := 2.0 * hb * sc * 0.78
					var fb := 9810.0 * area * dz
					var a_wet := 2.0 * hb * minf(sub / 0.12, 1.0) * dz
					var vn := -vp.dot(up_b)
					var sp := vp.length()
					# Planing and slamming on the bottom, plus a little heave damping.
					var fn := 500.0 * a_wet * (1.6 * sp * maxf(vn, 0.0) + 2.0 * maxf(vn, 0.0) * maxf(vn, 0.0))
					fn += 2600.0 * a_wet * vn
					fn = maxf(fn, -0.4 * fb)
					var vt := vp - up_b * vp.dot(up_b)
					var vtl := vt.length()
					var f := Vector3(0.0, fb, 0.0) + up_b * fn
					if vtl > 0.01:
						f -= vt * (500.0 * vtl * 0.008 * a_wet)
					# The keel resists slipping sideways through the water.
					var vl := vp.dot(side_b)
					f -= side_b * (500.0 * vl * absf(vl) * 1.1 * sc * dz + 400.0 * vl * sc * dz)
					force += f
					torque += arm.cross(f)
					deepest = maxf(deepest, sub)
					if bow_k < 0:
						bow_k = k
					disp += area * dz
					disp_at += pw * (area * dz)
			# Land, a beach or ice under the keel: it slides, and a hard arrival hurts.
			var gy: float = terrain.ground_level_at(pw.x, pw.z)
			var pen := gy - pw.y
			if pen > 0.0:
				var nrm: Vector3 = terrain.ground_normal_at(pw.x, pw.z)
				var vn2 := vp.dot(nrm)
				var fn2 := maxf(160000.0 * pen - 9000.0 * vn2, 0.0) * dz
				var vt2 := vp - nrm * vn2
				var vt2l := vt2.length()
				var mu := 0.08 if (frozen_lakes or terrain.surface_at(pw.x, pw.z) >= 4) else 0.42
				var f2 := nrm * fn2
				float_ground_n += fn2
				if vt2l > 0.02:
					f2 -= vt2 / vt2l * minf(mu * fn2, vt2l * 20000.0 * dz)
				force += f2
				torque += arm.cross(f2)
				if -vn2 > 3.2 and not is_crashed:
					hurt("gear_l" if fi == 0 else "gear_r", (-vn2 - 3.2) * 0.12)
		# The bow wave: drag that builds to a hump at low speed and fades once
		# the floats climb up on the step and displace less.
		if disp > 0.0:
			var at := disp_at / disp
			var vh := Vector3(vel.x, 0.0, vel.z)
			var u := vh.length()
			if u > 0.05:
				var hump := 0.06 * exp(-pow((u - 6.0) / 3.5, 2.0)) + 0.015 * clampf(u / 4.0, 0.0, 1.0)
				var fw := -vh / u * (9810.0 * disp * hump)
				force += fw
				torque += (at - pos).cross(fw)
		# Water rudders at the stern, down while taxiing.
		if water_rudders and deepest > 0.02:
			var st_last: Array = FLOAT_ST[n - 1]
			var rp2 := Vector3(sx, float(st_last[1]), float(st_last[0])) - cg
			var fr := -side_b * (500.0 * u_fwd * absf(u_fwd) * 0.07 * _rudder_eff)
			force += fr
			torque += (b * rp2).cross(fr)
		if deepest > 0.0:
			wheels_down += 1
			# Two long keels in the water hold a heading well: damp any swing.
			var wet_len := clampf(deepest / 0.25, 0.2, 1.0)
			torque -= up_b * (omega.dot(Vector3.UP) * 7000.0 * wet_len)
		float_water[fi] = deepest
		var sk: int = bow_k if bow_k >= 0 else FLOAT_STEP
		water_pos[fi] = Vector3(sx, float(FLOAT_ST[sk][1]), float(FLOAT_ST[sk][0]))
		wheel_water[fi] = maxf(wheel_water[fi], deepest) if deepest > 0.0 else wheel_water[fi]
	return [force, torque]


## Trees: trunks are solid, branches drag and scratch, small trees snap.
## Returns [force, torque] in world axes.
func _tree_contacts(dt: float) -> Array:
	var force := Vector3.ZERO
	var torque := Vector3.ZERO
	if agl > 40.0 or terrain == null or not terrain.has_trees:
		_tree_touch.clear()
		return [force, torque]
	var now := {}
	var pts: Array = BODY_POINTS.duplicate()
	pts.append(["left wheel", hub_rest[0]])
	pts.append(["right wheel", hub_rest[1]])
	for bp in pts:
		var pname: String = bp[0]
		var rp: Vector3 = bp[1] - cg
		var arm := b * rp
		var pw := pos + arm
		var tr: Dictionary = terrain.tree_near(pw)
		if tr.is_empty():
			continue
		var vp := vel + b * omega.cross(rp)
		var key := "%s:%d:%d" % [pname, tr["ti"], tr["tj"]]
		var base: Vector3 = tr["base"]
		var d: float = tr["dist"]
		var reach: float = tr["trunk_r"] + 0.2
		var hgt: float = tr["height"]
		if d < reach:
			var n := Vector3(pw.x - base.x, 0.0, pw.z - base.z)
			n = n / maxf(d, 0.01) if d > 0.01 else -Vector3(vp.x, 0.0, vp.z).normalized()
			var vn := vp.dot(n)
			var speed := maxf(-vn, 0.0)
			var snapped := false
			if not _tree_touch.has(key):
				# First moment of contact: decide what gives, the tree or the aeroplane.
				var hspeed := Vector2(vp.x, vp.z).length()
				var thin := hgt < 9.0 or (hgt < 14.0 and hspeed > 16.0)
				if thin and hspeed > 4.0:
					snapped = true
					tree_felled.emit(tr["ti"], tr["tj"], Vector3(vp.x, 0.0, vp.z))
					vel -= vp * 0.12
					_impact(pname, (hspeed - 4.0) / 18.0, bp[1].x)
					dented.emit(bp[1], (b.transposed() * n).normalized(), clampf((hspeed - 4.0) / 10.0, 0.2, 1.6))
					notice.emit("You hit a tree and snapped it off.")
				else:
					_tree_strike(pname, bp[1], speed, n)
			if not snapped:
				now[key] = true
				var pen := reach - d
				var fn := maxf((350000.0 * pen - 45000.0 * vn) * _mscale(), 0.0)
				var f := n * fn
				var vt := vp - n * vn
				var vtl := vt.length()
				if vtl > 0.05:
					f -= vt / vtl * minf(0.6 * fn, vtl * 6000.0 * _mscale())
				force += f
				torque += arm.cross(f)
		elif d < float(tr["crown_r"]) and vp.length() > 2.0:
			# Pushing through the branches: drag, scratches, and a little damage at speed.
			var k := 1.0 - d / float(tr["crown_r"])
			var fd := -vp * (90.0 * k)
			force += fd
			torque += arm.cross(fd)
			_impact(pname, vp.length() * dt * 0.0015 * k, bp[1].x)
			scraped.emit(bp[1], vp.length() * dt * 0.05)
	_tree_touch = now
	return [force, torque]


## A solid hit on a tree trunk.
func _tree_strike(pname: String, local: Vector3, speed: float, n: Vector3) -> void:
	if speed < 1.0:
		return
	var sev := (speed - 1.5) / 7.0
	var push := (b.transposed() * n).normalized()
	dented.emit(local, push, clampf(sev * 1.4, 0.3, 3.0))
	last_impact = maxf(last_impact, speed)
	if pname.contains("wing"):
		var side := 0 if pname.begins_with("left") else 1
		var wname := "wing_l" if side == 0 else "wing_r"
		if speed > 11.0 and not wing_off[side] and pname.contains("mid"):
			# The outer wing folds and tears away at the strut.
			hurt(wname, 1.0)
			hurt("aileron_l" if side == 0 else "aileron_r", 1.0)
			wing_off[side] = true
			part_broken.emit(wname)
			notice.emit("The %s wing has torn off against a tree!" % ("left" if side == 0 else "right"))
		else:
			_impact(pname, sev, local.x)
	else:
		_impact(pname, sev, local.x)
	if speed > 22.0 and (pname in ["nose", "propeller", "cabin roof", "belly"]):
		_wreck("You flew into a tree at %d knots." % int(speed * KT), speed)
	elif speed > 3.0:
		notice.emit("You hit a tree!")


## Wheels, airframe scrape points and water. Returns [force, torque] in world axes.
## Walls of the walk-in buildings (hangars): the airframe can't pass through
## them. Taxi a wingtip into the tin and it crumples; fly into one and that's
## that. The doorway is open, so a careful pilot can roll straight in.
func _building_contacts(_dt: float) -> Array:
	var force := Vector3.ZERO
	var torque := Vector3.ZERO
	if terrain == null or agl > 30.0:
		return [force, torque]
	var hollows: Array = terrain.hollows
	if hollows.is_empty():
		return [force, torque]
	const WALL := 0.35
	for hb in hollows:
		var o: Vector3 = (hb["xf"] as Transform3D).origin
		var rr: float = float(hb["r"]) + wing_span * 0.5 + 4.0
		if Vector2(pos.x - o.x, pos.z - o.z).length_squared() > rr * rr:
			continue
		var inv: Transform3D = hb["inv"]
		var sz: Vector3 = hb["size"]
		var hx := sz.x * 0.5
		var hz := sz.z * 0.5
		var dh: float = float(hb["door"]) * 0.5
		for bp in BODY_POINTS:
			var rp: Vector3 = bp[1] - cg
			var arm := b * rp
			var pp := pos + arm
			var l: Vector3 = inv * pp
			if l.y < -0.3 or l.y > sz.y + 0.2 or absf(l.x) > hx + WALL or absf(l.z) > hz + WALL:
				continue
			# How deep into each wall slab, and the way out of it.
			var push := Vector3.ZERO
			var pen := 0.0
			var dxw := WALL - absf(absf(l.x) - hx)          # side walls
			if dxw > 0.0 and absf(l.z) < hz + WALL:
				pen = dxw
				push = (hb["xf"] as Transform3D).basis * Vector3(signf(l.x) * (1.0 if absf(l.x) > hx else -1.0), 0.0, 0.0)
			var dzb := WALL - absf(l.z - hz)                # back wall
			if dzb > 0.0 and absf(l.x) < hx + WALL and (pen <= 0.0 or dzb < pen):
				pen = dzb
				push = (hb["xf"] as Transform3D).basis * Vector3(0.0, 0.0, 1.0 if l.z > hz else -1.0)
			var dzf := WALL - absf(l.z + hz)                # front wall, beside the door
			if dzf > 0.0 and absf(l.x) > dh and absf(l.x) < hx + WALL and (pen <= 0.0 or dzf < pen):
				pen = dzf
				push = (hb["xf"] as Transform3D).basis * Vector3(0.0, 0.0, -1.0 if l.z < -hz else 1.0)
			var dry := WALL - absf(l.y - sz.y)              # the roof (and the ceiling inside)
			if dry > 0.0 and absf(l.x) < hx + WALL and absf(l.z) < hz + WALL and (pen <= 0.0 or dry < pen):
				pen = dry
				push = Vector3.UP if l.y > sz.y - WALL * 0.5 else -(Vector3.UP)
			var pname := "bld " + String(bp[0])
			if pen <= 0.0 or push == Vector3.ZERO:
				_touching[pname] = false
				continue
			var vpp := vel + b * omega.cross(rp)
			var vn := vpp.dot(push)
			var fn := maxf((60000.0 * pen - 8000.0 * minf(vn, 0.0)) * _mscale(), 0.0)
			var f := push * fn - (vpp - push * vn) * 900.0 * _mscale()
			force += f
			torque += arm.cross(f)
			if is_crashed:
				continue
			if not _touching.get(pname, false):
				_touching[pname] = true
				var into := maxf(-vn, 0.0)
				var push_b: Vector3 = (b.transposed() * push).normalized()
				if into > 9.0:
					dented.emit(bp[1], push_b, 3.0)
					last_impact = maxf(last_impact, vpp.length())
					_wreck("You flew into a building at %d knots." % int(vpp.length() * KT))
				elif into > 0.6:
					_impact(bp[0], (into - 0.5) / 4.0, rp.x)
					dented.emit(bp[1], push_b, clampf((into - 0.5) / 4.0, 0.3, 2.0))
					notice.emit("You've hit the building!")
			elif vpp.length() > 1.0:
				scraped.emit(bp[1], vpp.length() * _dt * 0.1)
	# The solid buildings: houses, cabins, sheds. A box you cannot enter;
	# the airframe is pushed out the nearest way.
	for sb in terrain.solids:
		var o2: Vector3 = (sb["xf"] as Transform3D).origin
		var rr2: float = float(sb["r"]) + wing_span * 0.5 + 4.0
		if Vector2(pos.x - o2.x, pos.z - o2.z).length_squared() > rr2 * rr2:
			continue
		var inv2: Transform3D = sb["inv"]
		var sz2: Vector3 = sb["size"]
		for bp in BODY_POINTS:
			var rp: Vector3 = bp[1] - cg
			var arm := b * rp
			var pp := pos + arm
			var l: Vector3 = inv2 * pp
			var dx := sz2.x * 0.5 + 0.1 - absf(l.x)
			var dy := sz2.y + 0.1 - l.y
			var dz := sz2.z * 0.5 + 0.1 - absf(l.z)
			if dx <= 0.0 or dz <= 0.0 or dy <= 0.0 or l.y < -0.5:
				_touching["sld " + String(bp[0])] = false
				continue
			# Out the nearest face.
			var push: Vector3
			var pen: float
			if dy <= dx and dy <= dz:
				pen = dy
				push = Vector3.UP
			elif dx <= dz:
				pen = dx
				push = Vector3(signf(l.x), 0.0, 0.0)
			else:
				pen = dz
				push = Vector3(0.0, 0.0, signf(l.z))
			push = (sb["xf"] as Transform3D).basis * push
			var pname := "sld " + String(bp[0])
			var vpp := vel + b * omega.cross(rp)
			var vn := vpp.dot(push)
			var fn := maxf((60000.0 * minf(pen, 0.5) - 8000.0 * minf(vn, 0.0)) * _mscale(), 0.0)
			var f := push * fn - (vpp - push * vn) * 900.0 * _mscale()
			force += f
			torque += arm.cross(f)
			if is_crashed:
				continue
			if not _touching.get(pname, false):
				_touching[pname] = true
				var into := maxf(-vn, 0.0)
				var push_b: Vector3 = (b.transposed() * push).normalized()
				if into > 9.0:
					dented.emit(bp[1], push_b, 3.0)
					last_impact = maxf(last_impact, vpp.length())
					_wreck("You flew into a building at %d knots." % int(vpp.length() * KT))
				elif into > 0.6:
					_impact(bp[0], (into - 0.5) / 4.0, rp.x)
					dented.emit(bp[1], push_b, clampf((into - 0.5) / 4.0, 0.3, 2.0))
					notice.emit("You've hit the building!")
			elif vpp.length() > 1.0:
				scraped.emit(bp[1], vpp.length() * _dt * 0.1)
	return [force, torque]


func _contacts(_dt: float) -> Array:
	var force := Vector3.ZERO
	var torque := Vector3.ZERO
	var plane_fwd := b * FWD
	var submerged := 0

	var skid := 0.0
	for i in range(3):
		var r := _wheel(i, _dt, plane_fwd)
		if r.is_empty():
			continue
		force += r[0]
		torque += r[1]
		skid = maxf(skid, float(r[2]))
		if r[3]:
			submerged += 1
	skid_level = skid
	if is_amphib():
		var fr := _floats(_dt)
		force += fr[0]
		torque += fr[1]

	# Anything else touching the ground is damage.
	for bp in BODY_POINTS:
		var rp: Vector3 = bp[1] - cg
		var arm2 := b * rp
		var pp := pos + arm2
		var vpp := vel + b * omega.cross(rp)
		if _water_level > -1.0e8 and pp.y < _water_level:
			# The airframe in the water: it floats low and awash, fills up over a
			# minute or two, and goes down (the wing tanks hold out longest).
			var depth2 := minf(_water_level - pp.y, 1.0)
			var keep := 1.0 - 0.92 * _flooded
			if String(bp[0]).contains("wing"):
				keep = 1.0 - 0.7 * _flooded
			var spd2 := vpp.length()
			var fw2 := Vector3(0.0, depth2 * 5500.0 * keep, 0.0) - vpp * (depth2 * (500.0 + 120.0 * spd2))
			force += fw2
			torque += arm2.cross(fw2)
			submerged += 2
			# Driven into the water at speed: it digs in and goes over.
			if not is_crashed and spd2 > 14.0 and depth2 > 0.12 and String(bp[0]) in ["nose", "propeller", "cabin roof", "belly"]:
				last_impact = maxf(last_impact, spd2)
				dented.emit(bp[1], Vector3(0, 0.3, 1).normalized(), 1.5)
				_wreck("You dug into the water at %d knots and flipped over. You swim out." % int(spd2 * KT))
			if String(bp[0]) == "propeller" and rpm > 400.0 and not is_crashed:
				hurt("prop", 0.6 * _dt * 4.0)
				if not _touching.get("prop_water", false):
					_touching["prop_water"] = true
					notice.emit("Prop strike! The propeller hit the water.")
			if terrain.height_at(pp.x, pp.z) < pp.y:
				continue
		var gy2: float = terrain.ground_level_at(pp.x, pp.z)
		var pen2 := gy2 - pp.y
		var pname: String = bp[0]
		if pen2 <= 0.0:
			_touching[pname] = false
			continue
		var nrm2: Vector3 = terrain.ground_normal_at(pp.x, pp.z)
		var vn2 := vpp.dot(nrm2)
		# Metal folding up soaks a crash up: a wreck's contact points are
		# heavily damped (no bouncing back up), and it digs in and grinds to
		# a stop rather than skating (DESIGN_NOTES 155).
		var cdamp := 18000.0 if is_crashed else 7000.0
		var fn2 := maxf((70000.0 * pen2 - cdamp * vn2) * _mscale(), 0.0)
		var vt := vpp - nrm2 * vn2
		var f2 := nrm2 * fn2
		var vtl := vt.length()
		if vtl > 0.05:
			f2 -= vt / vtl * minf((0.75 if is_crashed else 0.55) * fn2, vtl * 9000.0 * _mscale())
		force += f2
		torque += arm2.cross(f2)
		if not is_crashed:
			if not _touching.get(pname, false):
				# First moment of contact: the size of the hit decides the damage.
				_touching[pname] = true
				var hit := maxf(-vn2, 0.0) + 0.15 * vtl
				var into := maxf(-vn2, 0.0)
				var push_dir: Vector3 = (b.transposed() * nrm2).normalized()
				if into > 11.0 or (vpp.length() > 40.0 and into > 4.0):
					dented.emit(bp[1], push_dir, 3.0)
					last_impact = vpp.length()
					_wreck("You hit the ground at %d knots. The aircraft is destroyed, but you climb out unhurt." % int(vpp.length() * KT))
				else:
					_impact(pname, (hit - 0.8) / 5.0, rp.x)
					if hit > 1.2 and pname != "propeller":
						dented.emit(bp[1], push_dir, (hit - 0.8) / 5.0)
			elif vtl > 1.0:
				# Scraping along: slow, steady damage.
				_impact(pname, vtl * _dt * 0.004, rp.x)
			if vtl > 1.0 and pname != "propeller":
				scraped.emit(bp[1], vtl * _dt * 0.1)
			if pen2 > 1.5:
				dented.emit(bp[1], (b.transposed() * nrm2).normalized(), 2.5)
				last_impact = maxf(last_impact, vpp.length())
				_wreck("The aircraft ploughed into the ground. It's destroyed, but you climb out unhurt.")

	var tc := _tree_contacts(_dt)
	force += tc[0]
	torque += tc[1]
	var bc := _building_contacts(_dt)
	force += bc[0]
	torque += bc[1]

	if submerged >= 4:
		_flooded = minf(_flooded + _dt / 100.0, 1.0)
	if submerged >= 2 and not _in_water:
		_in_water = true
		if engine.running:
			engine.water_in_fuel = 1.0
			engine.stop("You're in the water. The engine has swallowed water and stopped.")
		else:
			notice.emit("You're in the water.")
	elif submerged == 0 and not on_ground:
		_in_water = false
	return [force, torque]


## Twins: an engine can quit on its own now and then (Settings > Engine
## failures), more often the more worn it is.
var _fail_check := 0.0

func _random_failures(delta: float) -> void:
	if Game.engine_failures == 0 or on_ground:
		return
	_fail_check += delta
	if _fail_check < 10.0:
		return
	_fail_check = 0.0
	# "Rare": about one failure in five hours aloft; "Often": one an hour.
	var per_hour := 0.2 if Game.engine_failures == 1 else 1.0
	for ei in range(2):
		var e = engines()[ei]
		if e.running and randf() < per_hour * (1.6 - e.health) * 10.0 / 3600.0:
			fail_engine(ei, ["It coughs, bangs and quits: a broken valve.", "Oil pressure drops to nothing. You shut it down before it seizes.",
				"A magneto fails and the engine dies."][randi() % 3])


## Stop one engine (0 left, 1 right) as a failure: practice or for real.
func fail_engine(ei: int, why: String = "") -> void:
	var e = engines()[mini(ei, engines().size() - 1)]
	if not e.running:
		return
	e.stop(why if why != "" else "Engine failure.")
	notice.emit("%s engine failure! %s" % ["Left" if ei == 0 else "Right", why])


## Feather the dead engine's prop (or both dead ones): the blades turn edge-on
## and stop windmilling, so the drag and the swing toward it drop away.
func feather() -> String:
	if engine2 == null:
		return ""
	var done := []
	for ei in range(2):
		if not engines()[ei].running and not feathered[ei]:
			feathered[ei] = true
			done.append("left" if ei == 0 else "right")
	if done.is_empty():
		return "Nothing to feather: both engines are running."
	return "Feathered the %s prop." % " and ".join(done)


## Restart a stopped engine in the air (unfeather, start).
func restart_engine(ei: int) -> void:
	var e = engines()[mini(ei, engines().size() - 1)]
	if e.running:
		return
	feathered[ei] = false
	e.set_running(oat_c)
	e.rpm = 1200.0


func _crash(reason: String) -> void:
	_wreck(reason)


# ------------------------------------------------------------------------------
#  Slower systems: engine, fuel, landing judgement
# ------------------------------------------------------------------------------
func _update_systems(delta: float) -> void:
	# Engine and its systems
	if _seq != "":
		_run_sequence(delta)
	var dusty := false
	if on_ground:
		var sf: int = terrain.surface_at(pos.x, pos.z)
		dusty = sf == 0 or sf == 1 or sf == 3
	var lamp_amps := AircraftLights.load_amps(lights) + 1.5 * panel_light
	for e in engines():
		e.throttle = throttle
		e.dusty = dusty
		e.extra_amps = lamp_amps / float(engines().size())
		e.update(delta, air_density_now / 1.225, _pressure_pa, oat_c, maxf(-((vel - _wind_now) * b).z, 0.0),
			_humidity(), Game.engine_auto, Game.realism)
	power_frac = engine.power / engine.rated_power
	if engine2 != null:
		power_frac = (engine.power + engine2.power) / (2.0 * engine.rated_power)
		_random_failures(delta)
		# A feathered prop stays feathered until the engine is restarted.
		for ei in range(2):
			if engines()[ei].running:
				feathered[ei] = false
	# Leaking tanks
	if parts["tank_l"] < 0.85:
		engine.tank_left = maxf(engine.tank_left - (0.85 - parts["tank_l"]) * 0.03 * delta, 0.0)
	if parts["tank_r"] < 0.85:
		var re = engine2 if engine2 != null else engine
		re.tank_right = maxf(re.tank_right - (0.85 - parts["tank_r"]) * 0.03 * delta, 0.0)
	# A bent prop shakes the engine.
	engine.roughness = maxf(engine.roughness, (1.0 - parts["prop"]) * 0.8 if engine.running else 0.0)
	# Overstress and overspeed
	var touching_anything := false
	for v in _touching.values():
		if v:
			touching_anything = true
	if not on_ground and not is_crashed and not touching_anything and agl > 3.0:
		var g_limit := 4.4 if Game.is_realistic() else 5.5
		var g := g_load
		if g > g_limit or g < -1.8:
			var excess := (g - g_limit) if g > g_limit else (-1.8 - g)
			if excess > 2.6:
				_wreck("The wings failed under %.1f g." % g)
			else:
				_overstress_t += delta
				if _overstress_t > 0.15:
					notice.emit("Overstress! %.1f g. Something bent." % g)
					_overstress_t = -3.0
				hurt("wing_l", excess * 0.06 * delta * 10.0)
				hurt("wing_r", excess * 0.06 * delta * 10.0)
		if ias_kt > vne_kt:
			hurt("elevator", 0.02 * delta * (ias_kt - vne_kt) / 5.0)
			hurt("aileron_l", 0.02 * delta * (ias_kt - vne_kt) / 5.0)
			hurt("aileron_r", 0.02 * delta * (ias_kt - vne_kt) / 5.0)
		# Flaps out past their speed get bent back up.
		if flaps > 0.1 and ias_kt > vfe_kt:
			hurt("flaps", 0.03 * delta * flaps * (ias_kt - vfe_kt) / 10.0)
			_flap_over_t += delta
			if _flap_over_t > 1.0:
				_flap_over_t = -8.0
				notice.emit("The flaps are out past %d knots! They're taking a beating." % int(vfe_kt))
		else:
			_flap_over_t = minf(_flap_over_t + delta, 0.0) if _flap_over_t < 0.0 else 0.0
	if _overstress_t < 0.0:
		_overstress_t = minf(_overstress_t + delta, 0.0)
	_mass_timer += delta
	if _mass_timer > 2.0:
		_mass_timer = 0.0
		var origin := pos - b * cg
		recompute_mass()
		pos = origin + b * cg

	ias_kt = airspeed * sqrt(air_density_now / 1.225) * KT
	ground_speed = Vector2(vel.x, vel.z).length()

	# Hold still when parked with the engine at idle.
	park_brake = on_ground and throttle < 0.02 and ground_speed < 1.0 and not is_crashed

	_track_landing(delta)
	_update_fire(delta)

	# Edge of the map
	var edge := maxf(absf(pos.x), absf(pos.z))
	if edge > 5200.0 and not _oob_warned:
		_oob_warned = true
		notice.emit("The charted country runs out ahead. Turn back toward the claim.")
	elif edge < 4800.0:
		_oob_warned = false


func _track_landing(delta: float) -> void:
	_hard_cool -= delta
	var mains_down := wheel_comp[0] > 0.0 or wheel_comp[1] > 0.0
	if on_ground:
		_ground_time += delta
		if not _was_down and (airborne or _landing):
			# Touchdown, or the next arrival after a bounce.
			var sink := maxf(-vel.y, 0.0)
			if ground_speed > 5.0:
				_hold_heading = fposmod(rad_to_deg(atan2(vel.x, -vel.z)), 360.0)
			if not _landing:
				_landing = true
				_bounces = 0
				_td_sink = sink
				_td_speed = ground_speed
				_td_pos = pos
				_td_strip = terrain.strip_index_at(pos.x, pos.z, 12.0)
			else:
				if _hop_time > 0.3:
					_bounces += 1
				_td_sink = maxf(_td_sink, sink)
			if not is_crashed and (_bounces == 0 or _hop_time > 0.3) and _hard_cool <= 0.0:
				# Big soft tyres and oleo legs take a harder arrival before anything gives.
				var tough := (1.0 + (float(_tyre[0]["travel"]) - 0.14) * 2.0) * sqrt(float(_leg[0].get("strength", 1.0)))
				if sink > hard_landing_sink * tough:
					_hard_cool = 0.6
					# The harder the arrival, the more the gear and tyres take.
					var d := (sink - hard_landing_sink * tough) / ((collapse_sink - hard_landing_sink) * tough)
					notice.emit("Hard landing: %d feet per minute." % int(sink * 196.85))
					var left_load := wheel_comp[0] >= wheel_comp[1]
					hurt("gear_l", d * (0.55 if left_load else 0.4))
					hurt("gear_r", d * (0.4 if left_load else 0.55))
					hurt("tire_l", d * 0.25)
					hurt("tire_r", d * 0.25)
					hurt("tailwheel", d * 0.2)
		if _ground_time > 0.4:
			airborne = false
			air_time = 0.0
		if _landing and ground_speed < 1.2 and mains_down and not is_crashed:
			_landing = false
			var roll := Vector2(pos.x - _td_pos.x, pos.z - _td_pos.z).length()
			var stop_strip: int = terrain.strip_index_at(pos.x, pos.z, 12.0)
			landed.emit({
				"sink": _td_sink, "speed": _td_speed, "roll": roll, "bounces": _bounces,
				"touchdown_strip": _td_strip, "strip": stop_strip,
			})
	else:
		if _was_down:
			_hop_time = 0.0
		_hop_time += delta
		_ground_time = 0.0
		air_time += delta
		if air_time > 0.6:
			if not airborne:
				_landing = false
			airborne = true
	_was_down = on_ground


# ------------------------------------------------------------------------------
#  Attitude helpers for the panel and cameras
# ------------------------------------------------------------------------------
func heading_deg() -> float:
	var f := b * FWD
	return fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)


func pitch_rad() -> float:
	return asin(clampf((b * FWD).y, -1.0, 1.0))


func roll_rad() -> float:
	return atan2(-b.x.y, b.y.y)


func vertical_speed_fpm() -> float:
	return vel.y * 196.85


func altitude_ft() -> float:
	return pos.y * FT


func fuel_gallons() -> float:
	return fuel / 2.72


func flap_degrees() -> int:
	return flap_notch * 10


## How hard each main wheel is braking, for the panel (left, right).
func wheel_brakes() -> Vector2:
	var p := 1.0 if park_brake else 0.0
	return Vector2(maxf(_brake_wheel[0], p), maxf(_brake_wheel[1], p))


func _humidity() -> float:
	match Game.season:
		Game.SUMMER:
			return 0.6
		Game.FALL:
			return 0.85
		Game.WINTER:
			return 0.45
		_:
			return 0.8


# ------------------------------------------------------------------------------
#  Automatic start-up and shut-down, done step by step like a pilot would,
#  so you can watch (and learn) the sequence.
# ------------------------------------------------------------------------------
func toggle_auto_sequence() -> void:
	if is_crashed:
		return
	if _seq != "":
		_seq = ""
		notice.emit("Sequence cancelled.")
		return
	_seq = "stop" if engine.running else "start"
	_seq_step = 0
	_seq_t = 0.0


func _run_sequence(delta: float) -> void:
	_seq_t -= delta
	if _seq_t > 0.0:
		return
	_seq_t = 0.6
	if _seq == "start":
		match _seq_step:
			0:
				engine.master = true
				notice.emit("Start-up: battery master on.")
			1:
				engine.alternator = true
				engine.fuel_selector = EngineScript.FUEL_BOTH
				notice.emit("Fuel selector BOTH, alternator on.")
			2:
				engine.mixture = 1.0
				engine.prop_lever = 1.0
				engine.carb_heat = false
				throttle = 0.12
				notice.emit("Mixture rich, prop forward, throttle cracked open.")
			3:
				var strokes := int(ceil(clampf((25.0 - engine.cht) / 40.0, 0.0, 1.3) * 3.0))
				engine.prime += float(strokes)
				if strokes > 0:
					notice.emit("Primed %d strokes for a cold engine." % strokes)
			4:
				engine.mags = EngineScript.MAGS_START
				notice.emit("Clear prop! Starter engaged.")
			_:
				if engine.running:
					engine.mags = EngineScript.MAGS_BOTH
					throttle = 0.06
					notice.emit("Engine running. Magnetos BOTH. Watch the oil pressure come up.")
					_seq = ""
				elif _seq_step > 22 or engine.battery <= 0.06:
					engine.mags = EngineScript.MAGS_BOTH
					notice.emit("It won't start. Check the battery, fuel and mixture.")
					_seq = ""
	else:
		match _seq_step:
			0:
				throttle = 0.0
				notice.emit("Shut-down: throttle idle.")
			1:
				engine.mixture = 0.0
				notice.emit("Mixture to idle cut-off.")
			2, 3, 4:
				pass
			5:
				engine.mags = EngineScript.MAGS_OFF
				engine.alternator = false
				notice.emit("Magnetos off, alternator off.")
			_:
				engine.master = false
				notice.emit("Master off. Shut down.")
				_seq = ""
	_seq_step += 1


func engine_hint() -> String:
	if engine.running or is_crashed:
		return ""
	return "Engine off. Press %s for an automatic start, or start it by hand." % Game.hint("engine_auto")


# ------------------------------------------------------------------------------
#  Damage. Parts get hurt one by one and the plane flies (or rolls) worse for it.
#  Only a truly violent impact wrecks it outright.
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
#  Saving a plane (the fleet keeps one of these per plane you own)
# ------------------------------------------------------------------------------
func _paint_html() -> Array:
	var out: Array = []
	for c in paint:
		out.append((c as Color).to_html(false))
	return out


func to_dict() -> Dictionary:
	return {
		"type": plane_type, "reg": reg, "tyre": tyre_kind, "leg": leg_kind, "parts": parts.duplicate(),
		"tank2_l": engine2.tank_left if engine2 != null else 0.0, "tank2_r": engine2.tank_right if engine2 != null else 0.0,
		"wing_off": [wing_off[0], wing_off[1]],
		"tank_l": engine.tank_left, "tank_r": engine.tank_right, "oil": engine.oil_qts,
		"health": engine.health, "hours": engine.hours, "water": engine.water_in_fuel,
		"eparts": engine.parts_to_dict(), "eparts2": engine2.parts_to_dict() if engine2 != null else {},
		"oil2": engine2.oil_qts if engine2 != null else 0.0, "health2": engine2.health if engine2 != null else 1.0,
		"cargo_front": cargo_front, "cargo_rear": cargo_rear,
		"gear_down": gear_down, "tlock": tail_lock, "livery": livery, "paint": _paint_html(), "doors": door_open.duplicate(), "lights": lights.duplicate(), "panel_light": panel_light,
		"pos": pos - b * cg, "basis": Quaternion(b), "crashed": is_crashed,
	}


## Take on a saved plane's condition and fit. Its position is applied by
## place_parked() (or the caller places it at a strip).
func from_dict(d: Dictionary) -> void:
	if String(d.get("type", "wolverine")) != plane_type:
		apply_type(String(d.get("type", "wolverine")))
	reg = String(d.get("reg", reg))
	tyre_kind = String(d.get("tyre", tyre_kind))
	leg_kind = String(d.get("leg", leg_kind))
	var pd: Dictionary = d.get("parts", {})
	for k in PART_NAMES.keys():
		parts[k] = float(pd.get(k, 1.0))
	var wo: Array = d.get("wing_off", [false, false])
	wing_off = [bool(wo[0]), bool(wo[1])]
	engine.tank_left = float(d.get("tank_l", engine.tank_left))
	engine.tank_right = float(d.get("tank_r", engine.tank_right))
	if engine2 != null:
		engine2.tank_left = float(d.get("tank2_l", engine2.tank_left))
		engine2.tank_right = float(d.get("tank2_r", engine2.tank_right))
	engine.oil_qts = float(d.get("oil", engine.oil_qts))
	engine.health = float(d.get("health", engine.health))
	engine.hours = float(d.get("hours", engine.hours))
	engine.water_in_fuel = float(d.get("water", 0.0))
	if d.has("eparts"):
		engine.parts_from_dict(d["eparts"])
	if engine2 != null:
		if not (d.get("eparts2", {}) as Dictionary).is_empty():
			engine2.parts_from_dict(d["eparts2"])
		engine2.oil_qts = float(d.get("oil2", engine2.oil_qts))
		engine2.health = float(d.get("health2", engine2.health))
	cargo_front = float(d.get("cargo_front", 0.0))
	cargo_rear = float(d.get("cargo_rear", 0.0))
	door_open = (d.get("doors", {"cabin": false, "bay": false}) as Dictionary).duplicate()
	lights.merge(d.get("lights", {}), true)
	panel_light = float(d.get("panel_light", 0.0))
	apply_gear()
	gear_down = bool(d.get("gear_down", true)) or not (is_amphib() or is_retractable())
	tail_lock = bool(d.get("tlock", false))
	livery = int(d.get("livery", 0))
	paint.clear()
	for h in d.get("paint", []):
		paint.append(Color.html(String(h)))
	gear_pos = 1.0 if gear_down else 0.0


## Put the plane exactly where it was left, at rest.
func place_parked(origin: Vector3, q: Quaternion) -> void:
	_reset_flags()
	b = Basis(q).orthonormalized()
	pos = origin + b * cg
	vel = Vector3.ZERO
	omega = Vector3.ZERO
	throttle = 0.0
	brake = 1.0
	on_ground = true
	_snap_transform()


## What the shop charges to put right every part, and to fetch the plane home
## if it is lying wrecked somewhere ($).
const PART_COST := {
	"gear_l": 1800, "gear_r": 1800, "tailwheel": 600, "tire_l": 350, "tire_r": 350, "prop": 4200,
	"wing_l": 6500, "wing_r": 6500, "aileron_l": 900, "aileron_r": 900, "flaps": 1400, "elevator": 1100,
	"rudder": 900, "fuselage": 7500, "tank_l": 1200, "tank_r": 1200,
}
const RECOVERY_COST := 2500


func repair_cost() -> int:
	var c := 0.0
	for k in PART_NAMES.keys():
		c += (1.0 - clampf(float(parts.get(k, 1.0)), 0.0, 1.0)) * float(PART_COST.get(k, 800))
	for i in range(2):
		if wing_off[i]:
			c += 4000.0
	if engine != null and engine.health < 0.6:
		c += (0.85 - engine.health) * 9000.0
	if is_crashed:
		c += RECOVERY_COST
	if Game.sandbox:
		return 0
	return int(roundf(c / 10.0) * 10.0)


func repair_all() -> void:
	for k in PART_NAMES.keys():
		parts[k] = 1.0
	_touching.clear()
	_gear_over = [false, false, false]
	if engine != null and engine.health < 0.6:
		engine.health = 0.85
	wing_off = [false, false]
	on_fire = false
	fire_strength = 0.0
	_fire_fuel = 0.0
	last_impact = 0.0
	_tree_touch.clear()
	repaired.emit()


func part(name: String) -> float:
	return parts.get(name, 1.0)


func hurt(name: String, amount: float) -> void:
	if amount <= 0.0 or not parts.has(name):
		return
	var before: float = parts[name]
	var after := clampf(before - amount, 0.0, 1.0)
	parts[name] = after
	var was := part_condition(name, before)
	var now := part_condition(name, after)
	if now != was and now != "":
		notice.emit("%s: %s." % [PART_NAMES[name], now])


## Short description of a part's state, or "" when it is fine.
func part_condition(name: String, h: float) -> String:
	if h > 0.92:
		return ""
	match name:
		"gear_l", "gear_r", "tailwheel":
			if h < 0.25:
				return "collapsed"
			if h < 0.75:
				return "bent, it will pull to one side" if name != "tailwheel" else "bent"
			return "scuffed"
		"tire_l", "tire_r":
			return "flat" if h < 0.4 else "cut"
		"prop":
			if h < 0.05:
				return "destroyed"
			return "badly bent, heavy vibration" if h < 0.4 else "nicked, some vibration"
		"wing_l", "wing_r":
			return "badly damaged" if h < 0.4 else "dented"
		"aileron_l", "aileron_r":
			return "jammed" if h < 0.2 else "damaged, less roll control"
		"flaps":
			return "stuck where they are" if h < 0.5 else "bent"
		"elevator", "rudder":
			return "badly damaged" if h < 0.4 else "damaged"
		"fuselage":
			return "crumpled" if h < 0.4 else "dented"
		"tank_l", "tank_r":
			return "leaking fuel" if h < 0.85 else "scraped"
	return "damaged"


## Every damaged part, worst first, as [text, health].
func damage_report() -> Array:
	var out: Array = []
	for k in PART_NAMES.keys():
		var h: float = parts[k]
		var c := part_condition(k, h)
		if c != "":
			out.append(["%s: %s" % [PART_NAMES[k], c], h])
	if engine.health < 0.6:
		out.append(["Engine: %s" % ("barely running" if engine.health < 0.2 else "worn and weak"), engine.health])
	out.sort_custom(func(a, b2): return a[1] < b2[1])
	return out


func is_damaged() -> bool:
	for k in parts.keys():
		if parts[k] < 0.92:
			return true
	return false


func _wreck(reason: String, impact: float = -1.0) -> void:
	if is_crashed:
		return
	is_crashed = true
	crash_reason = reason
	engine.stop()
	throttle = 0.0
	if impact < 0.0:
		impact = maxf(last_impact, vel.length())
	# The wings bend and fold in a crash; only a really violent one tears
	# one off (DESIGN_NOTES 155 - Dave: stay together more, bend).
	if impact > 10.0:
		for si in range(2):
			var wn := "wing_l" if si == 0 else "wing_r"
			hurt(wn, clampf((impact - 10.0) / 22.0, 0.0, 0.85) * randf_range(0.7, 1.0))
			if not wing_off[0] and not wing_off[1] and impact > 30.0 and randf() < clampf((impact - 30.0) / 25.0, 0.0, 0.5):
				wing_off[si] = true
				hurt(wn, 1.0)
				part_broken.emit(wn)
	crashed.emit(reason)
	# Fuel aboard and a violent stop: it may burn, or go up all at once.
	var f: float = fuel
	if f > 4.0 and not _in_water:
		# Light planes rarely blow up: the tanks split and it burns. Only a
		# very fast impact goes up all at once.
		if impact > 45.0 and randf() < 0.6:
			_start_fire(1.0)
			exploded.emit(clampf(impact / 60.0, 0.6, 1.5))
		elif impact > 30.0:
			_start_fire(0.8)
		elif impact > 15.0 and randf() < 0.35 + (impact - 15.0) / 25.0:
			_start_fire(clampf((impact - 10.0) / 25.0, 0.3, 1.0))
		elif part("tank_l") < 0.85 or part("tank_r") < 0.85:
			if engine.cht > 120.0 and randf() < 0.4:
				_start_fire(0.35)


func _start_fire(strength: float) -> void:
	if on_fire:
		return
	on_fire = true
	fire_strength = strength
	_fire_fuel = fuel
	fire_started.emit(strength)
	notice.emit("Fire! Get clear of the aircraft.")


## A burning wreck eats its fuel, then smoulders.
func _update_fire(delta: float) -> void:
	if not on_fire:
		return
	if _fire_fuel > 0.0:
		var burn := (0.3 + 0.9 * fire_strength) * delta
		_fire_fuel = maxf(_fire_fuel - burn, 0.0)
		engine.set_fuel(_fire_fuel)
		fire_strength = clampf(lerpf(fire_strength, 0.25 + 0.75 * clampf(_fire_fuel / 60.0, 0.0, 1.0), delta * 0.2), 0.0, 1.0)
		hurt("fuselage", 0.004 * delta * fire_strength)
		hurt("wing_l", 0.003 * delta * fire_strength)
		hurt("wing_r", 0.003 * delta * fire_strength)
		hurt("tank_l", 0.01 * delta)
		hurt("tank_r", 0.01 * delta)
	else:
		fire_strength = maxf(fire_strength - delta * 0.004, 0.0)
		if fire_strength <= 0.0:
			on_fire = false


## Impact on one of the airframe's contact points. `sev` is roughly 0..1+.
func _impact(point: String, sev: float, x_side: float) -> void:
	if sev <= 0.0:
		return
	match point:
		"propeller":
			hurt("prop", 0.35 + 0.6 * sev)
			engine.health -= 0.08 * sev
			if engine.running and engine.rpm > 700.0:
				engine.stop("Prop strike! The propeller hit the ground and the engine has stopped.")
		"nose":
			hurt("prop", 0.3 * sev)
			hurt("fuselage", 0.3 * sev)
			engine.health -= 0.12 * sev
		"left wingtip":
			hurt("wing_l", 0.3 * sev)
			hurt("aileron_l", 0.45 * sev)
		"right wingtip":
			hurt("wing_r", 0.3 * sev)
			hurt("aileron_r", 0.45 * sev)
		"belly":
			hurt("fuselage", 0.3 * sev)
			hurt("tank_l", 0.12 * sev)
			hurt("tank_r", 0.12 * sev)
			hurt("flaps", 0.2 * sev)
		"tail":
			hurt("tailwheel", 0.4 * sev)
			hurt("elevator", 0.25 * sev)
			hurt("fuselage", 0.15 * sev)
		"fin":
			hurt("rudder", 0.5 * sev)
			hurt("fuselage", 0.2 * sev)
		"cabin roof":
			hurt("fuselage", 0.5 * sev)
			hurt("wing_l" if x_side < 0.0 else "wing_r", 0.3 * sev)
		"left wing mid", "left wing root":
			hurt("wing_l", 0.35 * sev)
			hurt("aileron_l", 0.3 * sev)
			hurt("tank_l", 0.15 * sev)
		"right wing mid", "right wing root":
			hurt("wing_r", 0.35 * sev)
			hurt("aileron_r", 0.3 * sev)
			hurt("tank_r", 0.15 * sev)
		"left tailplane", "right tailplane":
			hurt("elevator", 0.45 * sev)
			hurt("fuselage", 0.1 * sev)
		"left wheel":
			hurt("gear_l", 0.4 * sev)
			hurt("tire_l", 0.4 * sev)
		"right wheel":
			hurt("gear_r", 0.4 * sev)
			hurt("tire_r", 0.4 * sev)
	if part("fuselage") < 0.05 or (part("wing_l") < 0.05 and part("wing_r") < 0.05):
		_wreck("The airframe is too badly damaged to fly.", maxf(last_impact, 12.0))
