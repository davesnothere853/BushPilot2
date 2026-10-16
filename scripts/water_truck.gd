extends Node3D
## The water truck (DESIGN_NOTES 75, 95, 221): rebuilt from ONE reference truck,
## an early-90s L-series single-axle water truck (reference/water_truck/REFERENCE.txt);
## the body is water_truck_model.gd. A 1,600-gallon modified-elliptical tank,
## PTO pump under its front, spray heads on the front bumper, one side head,
## two on the rear bar, the fill pipe with its black hose at the back.
##
## Systems: the engine has to run to drive (air has to build to release the
## brakes) and to turn the PTO pump. Each spray valve opens on its own (in
## the cab 1-5, or the switches in the box between the seats). The hose pulls
## off the back and sprays where you point it.

const MeshKit = preload("res://scripts/meshkit.gd")
const EK = preload("res://scripts/equip_kit.gd")
const TyreMesh = preload("res://scripts/tyre_mesh.gd")
const Parts = preload("res://scripts/parts.gd")
const WheeledBody = preload("res://scripts/wheeled_body.gd")
const Dash = preload("res://scripts/truck_dash.gd")
const RopeScript = preload("res://scripts/rope.gd")
const HoseLine = preload("res://scripts/hose_line.gd")
const Model = preload("res://scripts/water_truck_model.gd")
const CAPACITY := 6.06           # m3 (1,600 US gal: the reference truck's tank, measured)
const GAL := 264.17
const FILL_RATE := 0.12          # m3/s through the 3" suction (game-quick)
const NOZZLE_RATE := 0.025       # m3/s a spray head
const HOSE_RATE := 0.012         # m3/s the 1-1/2" hose nozzle
const HOSE_LEN := 15.2           # 50 ft
const SAVE := "user://truck.cfg"

const PAINT := Color(0.88, 0.88, 0.86)      # white cab
const PAINT_D := Color(0.72, 0.72, 0.70)
const TANK := Color(0.16, 0.17, 0.18)       # black tank
const DARK := Color(0.07, 0.07, 0.075)
const RUBBER := Color(0.06, 0.06, 0.06)
const STEEL := Color(0.45, 0.46, 0.48)
const CHROME := Color(0.78, 0.79, 0.80)
const RED := Color(0.72, 0.1, 0.08)
const AMBER := Color(0.95, 0.6, 0.1)
const GLASS := Color(0.45, 0.58, 0.66, 0.35)
const VINYL := Color(0.22, 0.20, 0.18)
const CLOTH := Color(0.35, 0.30, 0.25)

# axles (body frame, -Z forward): front under the middle of the hood, tandem
const FRONT_Z := Model.FZ
const REAR_Z := [Model.RZ]
# spray heads in the body frame, with their valve: 0 front L, 1 front R,
# 2 side (right), 3 rear L, 4 rear R
const HEADS := [
	[Model.HEAD_FL, 0], [Model.HEAD_FR, 1],
	[Model.HEAD_SIDE, 2],
	[Model.HEAD_RL, 3], [Model.HEAD_RR, 4],
]
const VALVE_NAMES := ["front left", "front right", "side", "rear left", "rear right"]
const MANIFOLD := Model.PUMP_BOX                  # the pump switch box at the back
const REEL := Model.REEL_OUT                      # the hose reel's roller guide at the back of the deck
const PUMP_VALVE := Model.VALVE_C                 # the butterfly valve that feeds the reel
const SUCTION := Vector3(1.6, 0, 2.4)             # where the hose reaches the water

## "water" or "fuel" (DESIGN_NOTES 118): the fuel truck is the same truck
## with an aluminium tank in two compartments - diesel and avgas - filled at
## a fuel pump and pumped into anything parked by it through the hose.
var variant := "water"
const DIESEL_CAP := 1000.0       # gal (front compartment)
const AVGAS_CAP := 600.0         # gal (rear compartment)
const LOAD_GPS := 15.0           # gal/s from a fuel pump (game-quick)
const DELIVER_GPS := 2.5         # gal/s through the delivery hose
const DIESEL_PRICE := 4          # $ a gallon at the pump
const AVGAS_PRICE := 6
var diesel_gal := 0.0
var avgas_gal := 0.0
var loading := false             # taking on fuel at a pump
var delivering: Dictionary = {}  # the refuel under way: {name, kind, pos, need, add}
var fuel_points: Callable        # main: () -> Array of fuel pump positions
var refuel_targets: Callable     # main: () -> Array of {name, kind ("diesel"/"avgas"), pos, need (gal), add: Callable(gal)}
var charge: Callable             # main: (dollars) -> bool, false if you can't pay
var home_xf := Transform3D(Basis(Vector3.UP, PI), Vector3(40.0, 0, -96.0))    # out on the open apron

var terrain: RefCounted
var water: Node                  # water_sim.gd
var body: RefCounted
var driven := false
var yaw := 0.0
var tank_m3 := 0.0
var filling := false
var on_spray: Callable           # func(point): water landing there (puts fires out)

# the truck's own workings
var engine_on := false
var rpm := 0.0
var _rpm_prev := 0.0
var awd := false                 # front axle driven too (6x6), G / D-pad up
var diff_lock := false           # every diff locked (9 / right stick click)
var low := false                 # low range (6x6 Low): a crawler gear, lots of pull, slow
const LOW_PULL := 2.0            # x pulling power in low
const LOW_TOP := 4.2             # m/s top speed in low (15 km/h)
var _base_power := 0.0
var _base_top := 0.0
var throttle_in := 0.0           # what your foot's doing (engine sound, DESIGN_NOTES 110)
var load_now := 0.0              # how hard the engine's working 0..1
var pto := false                # power take-off engaged: the engine drives the pump
var air_psi := 0.0
var coolant_f := 60.0
var oil_psi := 0.0
var fuel_gal := 80.0
var volts := 12.4
var pump_psi := 0.0
var valves := [false, false, false, false, false]
var hose_valve := false          # the reel's valve on the manifold
var hose_out := false            # the nozzle's off the reel, in his hand
var nozzle_open := false
var hose_hand := Vector3.ZERO    # where the nozzle is (world)
var hose_aim := Vector3.FORWARD
var _hose: MeshInstance3D        # hose_line.gd: the real hose off the reel
var _hose_jet: CPUParticles3D
var _wheel_nodes: Array = []     # [Node3D, is_front]
var _jets: Array = []            # [CPUParticles3D, valve]
var _valve_levers: Array = []    # the rear pump switch
var _pump_lamp: MeshInstance3D
var _lamp_was := -1
var _smoke: CPUParticles3D
var _save_t := 0.0
var _land_t := 0.0


func is_fuel() -> bool:
	return variant == "fuel"


func _save_path() -> String:
	return "user://fuel_truck.cfg" if is_fuel() else SAVE


var model: RefCounted            # water_truck_model.gd: the body and its moving parts
var doors_open := [false, false]
var hood_open := false
var _door_ang := [0.0, 0.0]
var _hood_ang := 0.0
var park_brake := true
var gear_fwd := 0.0              # the shifter's lean (just for the look)


func build() -> void:
	model = Model.new()
	model.build(self, is_fuel())
	_build_gauges()
	_build_wheels()
	_build_pump_box()
	if is_fuel():
		_build_fuel_marks()
	else:
		_build_jets()
	_build_smoke()
	call_deferred("_lab_extras")


## In the Model Lab (not in the game, which adds its own): the diesel's sound.
func _lab_extras() -> void:
	if not EK.in_lab(self) or get_node_or_null("EngineSound") != null:
		return
	var es: Node3D = load("res://scripts/engine_sound.gd").new()
	es.name = "EngineSound"
	es.kind = "diesel"
	es.position = Vector3(0, 1.2, Model.FZ)
	es.state = func() -> Dictionary:
		return {"rpm": rpm, "running": engine_on, "load": load_now, "throttle": throttle_in, "speed": body.speed if body != null else 0.0}
	add_child(es)


func _valve_toggle() -> String:
	hose_valve = not hose_valve
	return "Pump valve %s: %s" % ["open" if hose_valve else "shut", "water to the hose reel." if hose_valve else "the hose is dry."]


## The test bed's water test: tank full, engine running with the air up, the
## PTO in and every spray open (off: all shut, engine off).
func water_test(on: bool) -> String:
	if on:
		tank_m3 = CAPACITY
		if not engine_on:
			engine_toggle()
		air_psi = 120.0
		pto = true
		for i in range(5):
			valves[i] = not is_fuel()
		hose_valve = true
		return "Water test: engine running, PTO in, all five sprays open (%.0f gal)." % (tank_m3 * GAL)
	for i2 in range(5):
		valves[i2] = false
	hose_valve = false
	pto = false
	if engine_on:
		engine_toggle()
	for j in _jets:
		(j[0] as CPUParticles3D).emitting = false
	return "Water test off."


## The gauges on the cluster (from the photo: tach left, speedo right, two
## small each side) and the pump gauge on the spray box between the seats.
func _build_gauges() -> void:
	var dash: Node3D = model.dash
	var u := func(x: float, y: float) -> Vector2: return Vector2(x, y)
	dash.gauge(u.call(-0.085, -0.01), 0.058, {"title": "RPM", "unit": "x100", "lo": 0, "hi": 30, "major": 5, "minor": 1, "a0": 225, "a1": -45,
		"bands": [[21, 30, Color(0.8, 0.12, 0.08)]]}, func() -> float: return rpm / 100.0)
	dash.gauge(u.call(0.085, -0.01), 0.058, {"title": "MPH", "lo": 0, "hi": 85, "major": 10, "minor": 5, "a0": 225, "a1": -45},
		func() -> float: return absf(body.speed) * 2.237 if body != null else 0.0)
	dash.gauge(u.call(-0.235, 0.025), 0.03, {"title": "OIL", "unit": "PSI", "lo": 0, "hi": 100, "major": 50, "minor": 25, "a0": 210, "a1": -30,
		"bands": [[0, 15, Color(0.8, 0.12, 0.08)]]}, func() -> float: return oil_psi)
	dash.gauge(u.call(-0.235, -0.055), 0.03, {"title": "WATER", "unit": "F", "lo": 100, "hi": 250, "major": 50, "minor": 25, "a0": 210, "a1": -30,
		"bands": [[220, 250, Color(0.8, 0.12, 0.08)]]}, func() -> float: return coolant_f)
	dash.gauge(u.call(0.235, 0.025), 0.03, {"title": "FUEL", "lo": 0, "hi": 1, "major": 0.5, "minor": 0.25, "a0": 210, "a1": -30, "numbers": false,
		"labels": [["E", 0.0], ["1/2", 0.5], ["F", 1.0]], "bands": [[0, 0.12, Color(0.8, 0.12, 0.08)]]}, func() -> float: return fuel_gal / 80.0)
	dash.gauge(u.call(0.235, -0.055), 0.03, {"title": "AIR", "unit": "PSI", "lo": 0, "hi": 150, "major": 50, "minor": 25, "a0": 210, "a1": -30,
		"bands": [[0, 60, Color(0.8, 0.12, 0.08)]], "orange": true}, func() -> float: return air_psi)
	# the warning windows: low air / charge (red), filling (amber), pump running (green)
	dash.lamp(u.call(-0.17, 0.115), Color(1, 0.1, 0.05), func() -> bool: return engine_on and air_psi < 60.0 or (not engine_on and volts > 12.0 and driven))
	dash.lamp(u.call(-0.09, 0.115), Color(1, 0.75, 0.1), func() -> bool: return filling or park_brake)
	dash.lamp(u.call(0.13, 0.115), Color(0.2, 0.9, 0.3), func() -> bool: return engine_on and pto)
	# turn arrows (flash with the blinker) and the lights-on lamp
	dash.lamp(u.call(-0.13, 0.115), Color(0.2, 0.95, 0.3), func() -> bool: return blink < 0 and _blink_ph)
	dash.lamp(u.call(0.167, 0.115), Color(0.2, 0.95, 0.3), func() -> bool: return blink > 0 and _blink_ph)
	dash.lamp(u.call(0.205, 0.115), Color(0.25, 0.45, 1.0), func() -> bool: return bool(get_meta("ek_lights", false)))
	var bd: Node3D = model.box_dash
	if not is_fuel():
		bd.gauge(u.call(0.0, 0.0), 0.04, {"title": "PUMP", "unit": "PSI", "lo": 0, "hi": 120, "major": 20, "minor": 10, "a0": 225, "a1": -45, "orange": true},
			func() -> float: return pump_psi)
	else:
		bd.gauge(u.call(0.0, 0.0), 0.04, {"title": "METER", "unit": "GAL x100", "lo": 0, "hi": 16, "major": 4, "minor": 1, "a0": 225, "a1": -45},
			func() -> float: return (diesel_gal + avgas_gal) / 100.0)


## The pump box at the back (right, under the end of the skirt): one switch
## for the pump and the lamp that shows it's running.
func _build_pump_box() -> void:
	var lv := Node3D.new()
	lv.position = MANIFOLD + Vector3(0.065, 0.03, -0.03)
	var lk := MeshKit.new()
	lk.cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3.ZERO), 0.02, 0.02, 0.02, 10, Color(0.35, 0.35, 0.37))
	lk.box_at(Vector3(0.025, 0.04, 0), Vector3(0.015, 0.08, 0.02), RED)
	lv.add_child(lk.instance("Lever"))
	add_child(lv)
	_valve_levers = [lv]
	_pump_lamp = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.02, 0.035, 0.035)
	_pump_lamp.mesh = lm
	_pump_lamp.position = MANIFOLD + Vector3(0.065, 0.03, 0.04)
	add_child(_pump_lamp)
	var lab := Label3D.new()
	lab.text = "PUMP"
	lab.font_size = 28
	lab.pixel_size = 0.0011
	lab.position = MANIFOLD + Vector3(0.062, -0.06, 0.0)
	lab.rotation = Vector3(0, PI * 0.5, 0)
	add_child(lab)


## Exhaust out of the tail pipe (DESIGN_NOTES 110): a thin grey haze at idle,
## black and thick when you lean on it.
func _build_smoke() -> void:
	var fxl = load("res://scripts/fx.gd")
	var ramp: Gradient = fxl.gradient([[0.0, Color(1, 1, 1, 0.0)], [0.08, Color(1, 1, 1, 0.9)], [0.5, Color(1, 1, 1, 0.45)], [1.0, Color(1, 1, 1, 0.0)]])
	_smoke = fxl.particles(fxl.smoke_material(), 70, 2.8, 0.7, ramp, 4.5)
	_smoke.position = model.tailpipe_tip
	_smoke.emitting = false
	_smoke.direction = Vector3(0.7, -0.3, 0.3)
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 1.0
	_smoke.initial_velocity_max = 2.0
	_smoke.gravity = Vector3(0, 0.6, 0)
	_smoke.damping_min = 0.4
	_smoke.damping_max = 0.9
	_smoke.color = Color(0.3, 0.3, 0.3, 0.25)
	add_child(_smoke)


func _build_fuel_marks() -> void:
	var k := MeshKit.new()
	var cy := (Model.TANK_TOP + Model.TANK_BOT) * 0.5
	var zf := (Model.TANK_Z0 + 1.0) * 0.5              # diesel compartment (front)
	var zr := (1.0 + Model.TANK_Z1) * 0.5              # avgas compartment (rear)
	for sd: float in [-1.0, 1.0]:
		for pl in [[zf, "1202"], [zr, "1203"]]:
			var z: float = pl[0]
			var px := _tank_x(cy - 0.3) + 0.006
			k.box(Transform3D(Basis(Vector3.RIGHT, PI * 0.25), Vector3(sd * px, cy - 0.3, z)), Vector3(0.01, 0.26, 0.26), Color(0.78, 0.1, 0.08))
			_mark(String(pl[1]), Vector3(sd * (px + 0.008), cy - 0.3, z), sd, 40, Color(0, 0, 0))
		_mark("DIESEL", Vector3(sd * (_tank_x(cy + 0.22) + 0.01), cy + 0.22, zf), sd, 64, Color(0.08, 0.1, 0.35))
		_mark("AVGAS 100LL", Vector3(sd * (_tank_x(cy + 0.22) + 0.01), cy + 0.22, zr), sd, 56, Color(0.08, 0.1, 0.35))
		_mark("FLAMMABLE", Vector3(sd * (_tank_x(cy) + 0.01), cy, 1.0), sd, 52, Color(0.7, 0.08, 0.06))
	# the compartment wall shows as a seam
	k.loft([Model.tank_ring(0.99, -0.004), Model.tank_ring(1.01, -0.004)], Color(0.62, 0.63, 0.64), false, false)
	# the back: FLAMMABLE and a placard, beside the ladder
	var bz := Model.TANK_Z1 + 0.006
	k.box(Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(-0.6, cy + 0.1, bz)), Vector3(0.24, 0.24, 0.01), Color(0.78, 0.1, 0.08))
	var back := Label3D.new()
	back.text = "1203"
	back.font_size = 40
	back.pixel_size = 0.002
	back.modulate = Color(0, 0, 0)
	back.position = Vector3(-0.6, cy + 0.1, bz + 0.01)
	add_child(back)
	var fl := Label3D.new()
	fl.text = "FLAMMABLE"
	fl.font_size = 52
	fl.pixel_size = 0.003
	fl.modulate = Color(0.7, 0.08, 0.06)
	fl.position = Vector3(-0.55, cy - 0.25, bz + 0.002)
	add_child(fl)
	add_child(k.instance("FuelMarks"))


## The tank's half width at height y (its section, water_truck_model.tank_ring).
func _tank_x(y: float) -> float:
	var cy := (Model.TANK_TOP + Model.TANK_BOT) * 0.5
	var hh := (Model.TANK_TOP - Model.TANK_BOT) * 0.5
	var v := clampf((y - cy) / hh, -0.999, 0.999)
	var hw := lerpf(1.06, Model.TANK_HW, v * 0.5 + 0.5)
	return hw * pow(maxf(1.0 - pow(absf(v), 2.6), 0.0), 1.0 / 2.6)


## Lettering on the side of the tank, facing out.
func _mark(text: String, at: Vector3, side: float, size: int, col: Color) -> void:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = size
	lb.pixel_size = 0.0035
	lb.modulate = col
	lb.outline_size = 0
	lb.double_sided = false
	lb.position = at
	lb.rotation = Vector3(0, PI * 0.5 * side, 0)      # facing out of that side
	add_child(lb)


## Tyres for the truck (E at a wheel, stopped, engine off): radius and
## width, grip on dirt and on the strip, the shop's price for the set of ten.
const TYRES := {
	"hwy225": {"name": "11R22.5 highway rib", "r": 0.527, "w": 0.28, "tread": "rib", "mu_dirt": 0.8, "mu_hard": 1.0, "price": 0},
	"lug225": {"name": "11R22.5 drive lug", "r": 0.527, "w": 0.28, "tread": "lug", "mu_dirt": 0.95, "mu_hard": 0.92, "price": 3200},
	"lug245": {"name": "11R24.5 drive lug (tall)", "r": 0.55, "w": 0.28, "tread": "lug", "mu_dirt": 0.97, "mu_hard": 0.92, "price": 3800},
	"flot":   {"name": "445/65R22.5 flotation", "r": 0.54, "w": 0.44, "tread": "flot", "mu_dirt": 1.05, "mu_hard": 0.85, "price": 5200},
}
const TYRE_ORDER := ["hwy225", "lug225", "lug245", "flot"]
var tyre_kind := "hwy225"
var _wr := 0.527


func _build_wheels() -> void:
	var t: Dictionary = TYRES[tyre_kind]
	_wr = float(t["r"])
	model.wheels(self, _wr, float(t["w"]), String(t["tread"]))
	_wheel_nodes = model.wheel_nodes


func set_tyres(kind: String) -> void:
	if not TYRES.has(kind):
		return
	tyre_kind = kind
	_build_wheels()
	if body != null:
		body.wheel_r = _wr
		for i in range(body.wheels.size()):
			(body.wheels[i] as Array)[0] = Vector3((body.wheels[i] as Array)[0].x, _wr, (body.wheels[i] as Array)[0].z)
		_apply_grip()
		body.setup()


func _apply_grip() -> void:
	if body == null or terrain == null:
		return
	var t: Dictionary = TYRES[tyre_kind]
	var on_strip: bool = terrain.strip_index_at(global_position.x, global_position.z, 2.0) >= 0
	body.mu = 0.9 * float(t["mu_hard"] if on_strip else t["mu_dirt"])


# ------------------------------------------------------------------------------
#  Parts (DESIGN_NOTES 125): engine, injection pump, turbo, cooling, gearbox,
#  axles, suspension and tyres, swapped in the workshop like the pickup's.
# ------------------------------------------------------------------------------
const BASE_KG := 8200.0
const STOCK_HP := 210.0
const STOCK_KW := 180.0
const STOCK_TOP := 22.0
var parts_fail := ""             # what's missing that it needs to run


func parts_key() -> String:
	return "fuel_truck" if is_fuel() else "water_truck"


## First time (or an old save): bolt the stock parts in, keeping the tyres
## it had on.
func setup_parts() -> void:
	var key := parts_key()
	if not Parts.fitted.has(key) or (Parts.fitted[key] as Dictionary).is_empty():
		var f := {}
		for sl in Parts.TRUCK_STOCK.keys():
			var did: String = Parts.TRUCK_STOCK[sl]
			if sl == "tyres":
				did = "tyres_" + tyre_kind
			if did != "":
				f[sl] = Parts.make(did, randf_range(0.85, 1.0))
		Parts.fitted[key] = f
		Parts.save_all()
	apply_parts()


## What these parts make: {ok, hp, boost, kg, temp_f, top_k, pull_k}.
static func truck_estimate(f: Dictionary) -> Dictionary:
	var d := func(sl: String) -> Dictionary: return Parts.def_of(int(f.get(sl, 0))) if int(f.get(sl, 0)) > 0 else {}
	var c := func(sl: String) -> float: return Parts.cond(int(f.get(sl, 0))) if int(f.get(sl, 0)) > 0 else 0.0
	var kg := 0.0
	var stock_kg := 0.0
	for sl in f.keys():
		kg += float(Parts.def_of(int(f[sl])).get("kg", 0.0))
	for sl2 in Parts.TRUCK_STOCK.keys():
		var sd: String = Parts.TRUCK_STOCK[sl2]
		if sd != "":
			stock_kg += float(Parts.CATALOG.get(sd, Parts.CHASSIS.get(sd, {})).get("kg", 0.0))
	var tr: Dictionary = d.call("transmission")
	var ax: Dictionary = d.call("diff_r")
	var out := {"ok": "", "hp": 0.0, "boost": 0.0, "kg": kg - stock_kg, "temp_f": 190.0,
		"top_k": float(tr.get("top", 1.0)) * 5.29 / float(ax.get("ratio", 5.29)),
		"pull_k": float(tr.get("pull", 1.0)) * float(ax.get("ratio", 5.29)) / 5.29}
	for sl3 in ["engine", "fuel", "fuel_pump", "transmission", "diff_r", "tyres", "battery"]:
		if int(f.get(sl3, 0)) <= 0:
			out["ok"] = "no %s" % Parts.SLOT_NAMES.get(sl3, sl3)
			return out
		if float(c.call(sl3)) <= 0.0:
			out["ok"] = "the %s has failed" % Parts.SLOT_NAMES.get(sl3, sl3)
			return out
	var eng: Dictionary = d.call("engine")
	var hp := float(eng.get("hp", STOCK_HP)) * (0.75 + 0.25 * float(c.call("engine")))
	# rated with its turbo: without one a diesel makes about 60 %
	var tu: Dictionary = d.call("turbo")
	var boost := 0.0
	if tu.is_empty():
		hp *= 0.6
	else:
		boost = float(tu.get("psi", 18.0)) * (0.6 + 0.4 * float(c.call("turbo")))
		hp *= 1.0 + (boost - 18.0) / 18.0 * 0.35
		if not d.call("intercooler").is_empty():
			hp *= 1.0 + 0.1 * float(d.call("intercooler").get("eff", 0.7))
	hp *= float(d.call("exhaust").get("flow", 0.85)) if not d.call("exhaust").is_empty() else 0.8
	hp *= 0.9 if int(f.get("fuel_filter", 0)) <= 0 else 1.0
	hp = minf(hp, float(d.call("fuel").get("max_hp", 260.0)) * (0.7 + 0.3 * float(c.call("fuel"))))
	out["hp"] = hp
	out["boost"] = boost
	var cool := float(d.call("radiator").get("cooling", 0.0)) * float(c.call("radiator")) if not d.call("radiator").is_empty() else 0.0
	out["temp_f"] = 190.0 + maxf(hp / maxf(cool * 290.0, 1.0) - 1.0, 0.0) * 90.0
	return out


## Put the fitted parts to work: power, top speed, weight, tyres, springs.
func apply_parts() -> void:
	var f: Dictionary = Parts.fitted.get(parts_key(), {})
	var e := truck_estimate(f)
	parts_fail = String(e["ok"])
	if parts_fail != "" and engine_on:
		engine_on = false
		pto = false
	var ty: Dictionary = Parts.def_of(int(f.get("tyres", 0)))
	if not ty.is_empty() and TYRES.has(String(ty.get("tyre", ""))) and String(ty["tyre"]) != tyre_kind:
		set_tyres(String(ty["tyre"]))
	if body == null:
		return
	var su: Dictionary = Parts.def_of(int(f.get("susp", 0)))
	body.travel = 0.25 * float(su.get("travel", 1.0))
	body.spring_mul = float(su.get("stiff", 1.0))
	body.mass_empty = BASE_KG + float(e["kg"])
	body._recompute_springs()
	body.power = STOCK_KW * 1000.0 * maxf(float(e["hp"]), 1.0) / STOCK_HP * float(e["pull_k"])
	body.top_speed = clampf(STOCK_TOP * float(e["top_k"]) * clampf(pow(maxf(float(e["hp"]), 1.0) / STOCK_HP, 0.25), 0.7, 1.3), 8.0, 32.0)
	_base_power = 0.0
	_apply_range()


func parts_changed() -> void:
	Parts.save_all()
	apply_parts()
	save()


func _build_jets() -> void:
	for hd in HEADS:
		_jets.append([_jet(hd[0], Vector3(signf((hd[0] as Vector3).x) * 0.5, -0.5, signf((hd[0] as Vector3).z) * 0.7).normalized(), 70, 5.0), int(hd[1])])
	_hose_jet = _jet(Vector3.ZERO, Vector3.FORWARD, 40, 9.0)
	_hose_jet.top_level = true
	_hose_jet.spread = 6.0


func _jet(at: Vector3, dir: Vector3, amount: int, speed: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.0
	p.emitting = false
	p.position = at
	p.direction = dir
	p.spread = 22.0
	p.initial_velocity_min = speed * 0.8
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.11
	var qm := SphereMesh.new()
	qm.radius = 0.5
	qm.height = 1.0
	qm.radial_segments = 4
	qm.rings = 2
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.85, 0.92, 1.0, 0.5)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.material = wmat
	p.mesh = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


static func _bar(kit: RefCounted, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	kit.cylinder(Transform3D(Basis(x, y, x.cross(y)), a), r, r, d.length(), 8, col, true)


# ------------------------------------------------------------------------------
#  Driving
# ------------------------------------------------------------------------------
func park(xf: Transform3D) -> void:
	body = WheeledBody.new()
	body.mass_empty = BASE_KG
	body.load_com = Vector3(0, (Model.TANK_TOP + Model.TANK_BOT) * 0.5, (Model.TANK_Z0 + Model.TANK_Z1) * 0.5)
	body.com = Vector3(0, 1.0, -1.1)
	body.size = Vector3(2.45, 2.5, 5.4)
	body.wheel_r = _wr
	for wz in [FRONT_Z] + REAR_Z:
		for wx in [-1.0, 1.0]:
			body.wheels.append([Vector3(wx, _wr, wz), wz == FRONT_Z, wz != FRONT_Z])
	body.bogies = []
	body.ground_y = func(x: float, z: float) -> float: return terrain.wheel_ground(x, z) if terrain.has_method("wheel_ground") else terrain.height_at(x, z)
	body.blocked = func(p: Vector3) -> bool: return terrain.blocked_by_building(p, 1.2, self)
	body.setup()
	var o := xf.origin
	o.y = terrain.height_at(o.x, o.z) + 0.05
	body.place(Transform3D(xf.basis, o))
	body.load_kg = fluid_kg()
	body.settle()
	global_transform = body.transform()
	yaw = body.yaw()
	_apply_grip()
	_base_power = 0.0
	awd = false
	low = false
	diff_lock = false
	_apply_locks()
	if Parts.fitted.has(parts_key()):
		apply_parts()


func eye_xf() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Model.EYE)


func step_out_point() -> Vector3:
	return global_transform * Vector3(-1.8, 0, -1.1)


## Everything liquid on board, kg: the water in the tank (or the fuel truck's
## diesel and avgas compartments) and the diesel in its own saddle tank.
const KG_PER_GAL_DIESEL := 3.18      # 0.84 kg/L
const KG_PER_GAL_AVGAS := 2.72       # 0.72 kg/L
func fluid_kg() -> float:
	return tank_m3 * 1000.0 + diesel_gal * KG_PER_GAL_DIESEL + avgas_gal * KG_PER_GAL_AVGAS + fuel_gal * KG_PER_GAL_DIESEL


## One physics step while driven. move.y throttle (+ forward / - brake, then
## reverse), move.x steer. No engine, no go; no air, the brakes stay on.
func drive(delta: float, move: Vector2, handbrake: bool = false) -> String:
	body.load_kg = fluid_kg()
	var msg := ""
	var thr := move.y
	if not engine_on:
		if absf(move.y) > 0.1 and _told_off <= 0.0:
			_told_off = 4.0
			msg = "The engine's off: %s to start it." % Game.hint("engine_auto")
		thr = 0.0
		handbrake = true
	elif air_psi < 60.0:
		if absf(move.y) > 0.1 and _told_off <= 0.0:
			_told_off = 4.0
			msg = "Air's building (%d psi): the spring brakes release at 60." % int(air_psi)
		thr = 0.0
		handbrake = true
	_told_off -= delta
	throttle_in = maxf(thr, 0.0) if body.speed > -0.3 else maxf(-thr, 0.0)
	body.step(delta, thr, move.x, handbrake)
	var fwd_v: float = body.vel.dot(-body.basis.z)
	_reversing = engine_on and fwd_v < -0.3
	_braking = engine_on and (handbrake or (move.y < -0.1 and fwd_v > 0.3))
	global_transform = body.transform()
	yaw = body.yaw()
	var w := work(delta)
	return msg if msg != "" else w


var _told_off := 0.0


# ------------------------------------------------------------------------------
#  Lamps: turn signals, stop, back-up (DESIGN_NOTES 224j)
# ------------------------------------------------------------------------------
var blink := 0                     # -1 left, 1 right, 0 off (Z / X, again to cancel)
var hazards := false
var _braking := false
var _reversing := false
var _blink_ph := false             # the flasher's on half
var _lamp_roles: Array = []        # [lens material, bulb material or null, role, side]
var _lamp_lit := {}


## Z / X: left / right blinker (again to cancel). 0 = hazards on / off.
func blinker(dir: int) -> String:
	if dir == 0:
		hazards = not hazards
		return "Hazards %s." % ("on" if hazards else "off")
	blink = 0 if blink == dir else dir
	return "Blinker %s." % ("off" if blink == 0 else ("left" if blink < 0 else "right"))


## Sort the lamps the model built by what they do, from their colour and where
## they are: amber on the hood (the fender turn lamps and side markers) flash;
## the red lamps in the back light boxes are stop / tail / turn; the white ones
## beside them back-up. Clearance and ID lamps stay with the lights switch.
func _sort_lamps() -> void:
	_lamp_roles.clear()
	var inv := global_transform.affine_inverse()
	var bulbs: Array = []
	for b in find_children("*", "MeshInstance3D", true, false):
		if (b as MeshInstance3D).mesh is SphereMesh and (b as MeshInstance3D).material_override is StandardMaterial3D:
			bulbs.append(b)
	for n in find_children("*", "MeshInstance3D", true, false):
		if not (n as Node).has_meta("lamp_lens"):
			continue
		var lm := (n as MeshInstance3D).material_override as StandardMaterial3D
		if lm == null:
			continue
		var at: Vector3 = inv * (n as Node3D).global_position
		var c := lm.emission
		var amber := c.r > 0.9 and c.g > 0.4 and c.g < 0.85 and c.b < 0.3
		var red := c.r > 0.6 and c.g < 0.3 and c.b < 0.3
		var white := c.r > 0.9 and c.g > 0.9 and c.b > 0.8
		var faces: Vector3 = (inv.basis * (n as Node3D).global_transform.basis.z).normalized()
		var rear := at.z > Model.FRAME_Z1 - 0.45 and at.y < 1.3 and faces.z > 0.7      # in the back light boxes, facing back
		var role := ""
		if amber and model.hood != null and model.hood.is_ancestor_of(n):
			role = "turn"
		elif red and rear:
			role = "stop"
		elif white and rear:
			role = "back"
		if role == "":
			continue
		var bm: StandardMaterial3D = null
		var best := 0.08
		for b in bulbs:
			var d: float = (b as Node3D).global_position.distance_to((n as Node3D).global_position)
			if d < best:
				best = d
				bm = (b as MeshInstance3D).material_override as StandardMaterial3D
		_lamp_roles.append([lm, bm, role, signf(at.x)])


func _lamps(dt: float) -> void:
	if _lamp_roles.is_empty():
		if not is_inside_tree():
			return
		_sort_lamps()
	var t := Time.get_ticks_msec() * 0.001
	_blink_ph = fmod(t, 0.72) < 0.36                    # about 83 flashes a minute
	var lights_on := bool(get_meta("ek_lights", false))
	var flash_l := (blink < 0 or hazards) and _blink_ph
	var flash_r := (blink > 0 or hazards) and _blink_ph
	for r in _lamp_roles:
		var side: float = r[3]
		var signalling: bool = (blink != 0 and signf(float(blink)) == side) or hazards
		var flash: bool = flash_l if side < 0 else flash_r
		var e := 0.15
		match String(r[2]):
			"turn":
				e = 4.0 if flash else (0.9 if lights_on and not signalling else 0.15)
			"stop":
				if signalling:
					e = 4.0 if flash else (0.9 if lights_on else 0.15)
				elif _braking:
					e = 4.0
				else:
					e = 0.9 if lights_on else 0.15
			"back":
				e = 3.0 if _reversing else 0.15
		var lm: StandardMaterial3D = r[0]
		if absf(lm.emission_energy_multiplier - e) > 0.01:
			lm.emission_energy_multiplier = e
			if r[1] != null:
				(r[1] as StandardMaterial3D).emission_energy_multiplier = e * 2.0


## I in the cab: start or stop the engine.
func engine_toggle() -> String:
	if engine_on:
		engine_on = false
		pto = false
		return "Engine off."
	if fuel_gal <= 0.1:
		return "Out of diesel."
	if parts_fail != "":
		return "It cranks but won't fire: %s." % parts_fail
	engine_on = true
	return "Engine running. Let the air build to 60 psi before you move off. 6 puts the PTO in to run the pump."


## 6 in the cab: the power take-off. In, the engine kicks up to a fast idle
## and turns the water pump; out, the pump stops.
func toggle_pto() -> String:
	if not engine_on:
		return "Start the engine first: the PTO runs off it."
	pto = not pto
	if not pto:
		filling = false
	return "PTO in: the engine kicks up to drive the pump." if pto else "PTO out: the pump's stopped."


## 1-5 in the cab: a spray valve.
func toggle_valve(i: int) -> String:
	if is_fuel():
		return "No sprays on the fuel truck."
	valves[i] = not valves[i]
	return "%s spray %s." % [String(VALVE_NAMES[i]).capitalize(), "open" if valves[i] else "closed"]


## The fuel truck's E: stop what it's doing; at a fuel pump, take on fuel;
## otherwise fill up whatever's parked nearest that needs it.
func _fuel_action() -> String:
	if loading or not delivering.is_empty():
		var was := "Loading stopped." if loading else "Stopped fuelling the %s." % String(delivering.get("name", ""))
		loading = false
		delivering = {}
		return was
	if body != null and absf(body.speed) > 0.5:
		return "Stop the truck first."
	if not engine_on:
		return "The fuel pump runs off the engine: %s to start it." % Game.hint("engine_auto")
	pto = true
	if _at_pump() and (diesel_gal < DIESEL_CAP - 1.0 or avgas_gal < AVGAS_CAP - 1.0):
		loading = true
		return "At the pump: loading diesel and avgas (%.0f / %.0f gal)." % [diesel_gal, avgas_gal]
	var t := _nearest_thirsty()
	if t.is_empty():
		return "Nothing parked close by needs fuel (within 15 m)." if not _at_pump() else "Both compartments are full."
	var have := diesel_gal if String(t["kind"]) == "diesel" else avgas_gal
	if have <= 0.5:
		return "The %s compartment's empty: fill up at a fuel pump." % String(t["kind"])
	delivering = t
	return "Hose out to the %s: pumping %s." % [String(t["name"]), String(t["kind"])]


func _at_pump() -> bool:
	if not fuel_points.is_valid():
		return false
	for fp in fuel_points.call():
		if (fp as Vector3).distance_to(global_position) < 14.0:
			return true
	return false


func _nearest_thirsty() -> Dictionary:
	if not refuel_targets.is_valid():
		return {}
	var best := {}
	var bd := 15.0
	for t in refuel_targets.call():
		var d: float = (t["pos"] as Vector3).distance_to(global_position)
		if d < bd and float(t["need"]) > 0.5:
			bd = d
			best = t
	return best


## Loading at the pump and fuelling up whatever's parked by it (in work()).
func _fuel_work(delta: float) -> String:
	var msg := ""
	var running: bool = engine_on and pto and (body == null or absf(body.speed) < 0.5)
	if loading:
		if not running or not _at_pump():
			loading = false
			return "Loading stopped."
		var dg := minf(LOAD_GPS * delta, DIESEL_CAP - diesel_gal)
		var ag := minf(LOAD_GPS * delta, AVGAS_CAP - avgas_gal)
		var cost := dg * DIESEL_PRICE + ag * AVGAS_PRICE
		if charge.is_valid() and cost > 0.0 and not charge.call(cost):
			loading = false
			return "Out of money: loading stopped."
		diesel_gal += dg
		avgas_gal += ag
		if dg <= 0.0 and ag <= 0.0:
			loading = false
			msg = "Full: %.0f gal diesel, %.0f gal avgas." % [diesel_gal, avgas_gal]
	elif not delivering.is_empty():
		var t := delivering
		if hose_out and nozzle_open and _fill_point_near(hose_hand, 2.6).is_empty():
			delivering = {}
			nozzle_open = false
			return "The nozzle came out of the filler: shut it."
		# it may have moved off
		if not running or (t["pos"] as Vector3).distance_to(global_position) > (HOSE_LEN + 6.0 if hose_out else 18.0):
			delivering = {}
			return "Fuelling stopped."
		var kind := String(t["kind"])
		var g := minf(DELIVER_GPS * delta, float(t["need"]))
		g = minf(g, diesel_gal if kind == "diesel" else avgas_gal)
		if kind == "diesel":
			diesel_gal -= g
		else:
			avgas_gal -= g
		(t["add"] as Callable).call(g)
		t["need"] = float(t["need"]) - g
		if float(t["need"]) <= 0.05:
			delivering = {}
			msg = "The %s is full." % String(t["name"])
		elif g <= 0.0:
			delivering = {}
			msg = "The %s compartment's run dry." % kind
	# the truck runs off its own diesel load when its tank gets low
	if fuel_gal < 60.0 and diesel_gal > 0.0:
		var top := minf(80.0 - fuel_gal, diesel_gal)
		fuel_gal += top
		diesel_gal -= top
	pump_psi = move_toward(pump_psi, (45.0 if (loading or not delivering.is_empty()) else 15.0) if (engine_on and pto) else 0.0, 60.0 * delta)
	return msg


## E in the cab: fill when the suction hose is in water, otherwise all the
## sprays on or off together.
func truck_action() -> String:
	if is_fuel():
		return _fuel_action()
	var suction := global_transform * SUCTION
	var wet: bool = _pond_near(suction) or _water_within(suction, 5.0)
	if filling:
		filling = false
		return "Filling stopped: %.0f of %.0f gal." % [tank_m3 * GAL, CAPACITY * GAL]
	if wet and tank_m3 < CAPACITY - 0.05 and absf(body.speed) < 0.5:
		if not engine_on:
			return "The pump runs off the engine: %s to start it, then %s to fill." % [Game.hint("engine_auto"), Game.hint("interact")]
		var kicked := not pto
		pto = true
		filling = true
		return ("PTO in. " if kicked else "") + "Suction hose in the water: filling (%.0f of %.0f gal)." % [tank_m3 * GAL, CAPACITY * GAL]
	var any := false
	for v in valves:
		any = any or v
	for i in range(5):
		valves[i] = not any
	return ("All sprays open." if not any else "All sprays closed.") + ("" if (engine_on and pto) else " (the pump needs the engine running and the PTO in: 6)")


## The truck's systems: engine, air, temperatures, the pump, the sprays, the
## hose. Runs whether or not anyone's in the cab.
func work(delta: float) -> String:
	var msg := ""
	# engine
	var spd: float = absf(body.speed) if body != null else 0.0
	if engine_on:
		# A ten-speed range box: each gear pulls from ~1150 to ~1900 and the next
		# one drops it back about 750 rpm. Off the throttle it's held by the
		# gear (engine braking); stuck or spinning in mud it just revs.
		var mph := spd * 2.237
		var th: float = throttle_in if driven else 0.0
		var mud: float = float(body.mud_now) if body != null else 0.0
		var spin: float = float(body.spin_now) if body != null else 0.0
		var want := 650.0
		if low:
			# the crawler gear: revs climb with road speed all the way to the governor
			want = 650.0 + clampf(mph / (LOW_TOP * 2.237), 0.0, 1.0) * 1250.0 + th * 250.0
		elif mph < 3.0:
			want = 650.0 + mph / 3.0 * 450.0 + th * 700.0
		else:
			want = 1150.0 + 750.0 * fposmod(mph - 3.0, 7.0) / 7.0
			if th < 0.05:
				want = maxf(want - 120.0, 900.0)
		want = maxf(want, 650.0 + th * 1250.0 * clampf(spin * 1.5, 0.0, 1.0))
		if pto:
			want = maxf(want, 1500.0 if (filling or _pumping() or loading or not delivering.is_empty()) else 1300.0)     # pump in: the throttle kicks up to a high idle
		rpm = move_toward(rpm, want, (1400.0 if want > rpm else 1100.0) * delta)
		# load: the throttle, harder in mud, up a hill or pushing the pump
		var climb := clampf(-(body.transform().basis.z).y * 4.0, 0.0, 1.0) if body != null else 0.0
		var ld := th * (0.5 + 0.5 * clampf(mud * 1.4 + spin + climb, 0.0, 1.0))
		if pto and (filling or _pumping()):
			ld = maxf(ld, 0.55)
		elif pto:
			ld = maxf(ld, 0.25)
		load_now = clampf(ld, 0.0, 1.0)
		air_psi = minf(air_psi + 9.0 * delta, 120.0)
		coolant_f = move_toward(coolant_f, 185.0, 1.5 * delta)
		oil_psi = move_toward(oil_psi, 35.0 + rpm / 60.0, 30.0 * delta)
		volts = move_toward(volts, 14.1, 2.0 * delta)
		fuel_gal = maxf(fuel_gal - (0.0004 + rpm * 0.0000004) * delta, 0.0)
		if fuel_gal <= 0.0:
			engine_on = false
			msg = "Out of diesel: the engine's stopped."
	else:
		rpm = move_toward(rpm, 0.0, 900.0 * delta)
		oil_psi = move_toward(oil_psi, 0.0, 40.0 * delta)
		coolant_f = move_toward(coolant_f, 60.0, 0.05 * delta)
		volts = move_toward(volts, 12.4 if driven else 12.6, 1.0 * delta)
		air_psi = maxf(air_psi - 0.3 * delta, 0.0)
	_smoke.emitting = engine_on
	if engine_on:
		# blacker and thicker with the throttle and the load; a black puff as the revs climb
		var climb_k := clampf((rpm - _rpm_prev) / maxf(delta, 0.001) / 900.0, 0.0, 1.0)
		var soot := clampf(load_now * 0.9 + climb_k * 0.8, 0.0, 1.0)
		_smoke.color = Color(0.32, 0.32, 0.31).lerp(Color(0.04, 0.04, 0.04), soot)
		_smoke.color.a = 0.18 + 0.75 * soot
		_smoke.initial_velocity_max = 2.5 + 4.0 * soot + rpm / 800.0
		_smoke.scale_amount_min = 0.6 + 0.8 * soot
		_smoke.scale_amount_max = 1.0 + 1.6 * soot
	_rpm_prev = rpm
	if is_fuel():
		var fm := _fuel_work(delta)
		if fm != "":
			msg = fm
		if driven:
			_apply_grip()
		_animate()
		_save_t += delta
		if _save_t > 10.0:
			_save_t = 0.0
			save()
		return msg
	# filling through the suction hose
	if filling:
		var got := 0.0
		var want2 := minf(FILL_RATE * delta, CAPACITY - tank_m3)
		var suction := global_transform * SUCTION
		if not engine_on or not pto:
			filling = false
			msg = "The pump's stopped: it's quit filling."
		elif _pond_near(suction):
			got = want2
		elif water != null:
			got = water.take_water(suction, want2, 5.0)
		tank_m3 += got
		if tank_m3 >= CAPACITY - 0.001:
			filling = false
			msg = "Tank full: %.0f gallons." % (CAPACITY * GAL)
		elif filling and got < want2 * 0.2:
			filling = false
			msg = "The suction's sucking air: no more water within reach of the hose."
	# the sprays: engine running (PTO pump), valve open, water in the tank
	var live_any := false
	for j in _jets:
		var vi: int = j[1]
		var live: bool = engine_on and pto and valves[vi] and tank_m3 > 0.0 and not filling
		(j[0] as CPUParticles3D).emitting = live
		if live:
			live_any = true
			var out: float = minf(NOZZLE_RATE * delta, tank_m3)
			tank_m3 -= out
			var hp: Vector3 = (j[0] as Node3D).global_position
			var land := hp + (global_transform.basis * Vector3(signf(((j[0] as Node3D).position).x) * 1.2, 0, signf(((j[0] as Node3D).position).z) * 2.0))
			if water != null:
				water.add_water(land, out)
			if on_spray.is_valid():
				on_spray.call(land)
	# the hose: off the reel, valve open, nozzle open, pump running
	var hose_live: bool = hose_out and nozzle_open and hose_valve and engine_on and pto and tank_m3 > 0.0
	if _hose_jet != null:
		_hose_jet.emitting = hose_live
		if hose_live:
			_hose_jet.global_position = hose_hand
			_hose_jet.direction = hose_aim
			var out2 := minf(HOSE_RATE * delta, tank_m3)
			tank_m3 -= out2
			_land_t += delta
			if _land_t > 0.15:
				_land_t = 0.0
				var land2 := _hose_landing()
				if water != null:
					water.add_water(land2, out2 * 6.0)
				if on_spray.is_valid():
					on_spray.call(land2)
	pump_psi = move_toward(pump_psi, (80.0 if (live_any or hose_live) else (60.0 if filling else 25.0)) if (engine_on and pto) else 0.0, 60.0 * delta)
	if tank_m3 <= 0.0 and (live_any or hose_live):
		msg = "Tank's empty."
	if driven:
		_apply_grip()
	_animate()
	_save_t += delta
	if _save_t > 10.0:
		_save_t = 0.0
		save()
	return msg


func _pumping() -> bool:
	for v in valves:
		if v:
			return true
	return hose_out and nozzle_open


## Where the hose's stream comes down: a thrown arc from the nozzle.
func _hose_landing() -> Vector3:
	var p := hose_hand
	var v := hose_aim * 12.0
	for i in range(60):
		v.y -= 9.81 * 0.05
		p += v * 0.05
		if p.y <= terrain.height_at(p.x, p.z):
			break
	return p


func _pond_near(p: Vector3) -> bool:
	for lake in terrain.lakes:
		if Vector2(p.x, p.z).distance_to(lake["pos"]) < float(lake["radius"]) + 6.0:
			return true
	return false


func _water_within(p: Vector3, r: float) -> bool:
	if water == null:
		return false
	var step := 1.0
	var x := -r
	while x <= r:
		var z := -r
		while z <= r:
			if water.depth_at(p.x + x, p.z + z) > 0.15:
				return true
			z += step
		x += step
	return false


# ------------------------------------------------------------------------------
#  On foot: the rear valve levers and the hose
# ------------------------------------------------------------------------------
## What E does for someone standing at p with `tool` in hand.
func foot_target(p: Vector3, key: String) -> Array:
	if is_fuel():
		# (Dave: "unreel the hose and have to attach it to the plane")
		if hose_out:
			var at := _fill_point_near(hose_hand, 2.4)
			var tgt := ("  - at the %s's filler" % String(at["name"])) if not at.is_empty() else "  - get it to a filler"
			return ["fuel_nozzle", "%s  %s the nozzle%s   %s reel the hose back in   (avgas %.0f gal)" % [key, "Close" if nozzle_open else "Open", tgt, Game.hint("door"), avgas_gal]]
		var box0 := global_transform * MANIFOLD
		var reel0 := global_transform * REEL
		if p.distance_to(reel0) < 1.6 and not _at_pump():
			return ["fuel_hose_out", "%s  Pull the fuel hose off the reel (50 ft)   (avgas %.0f / diesel %.0f gal)" % [key, avgas_gal, diesel_gal]]
		if p.distance_to(box0) < 1.6 or p.distance_to(reel0) < 1.6:
			var what := "Stop the pump" if (loading or not delivering.is_empty()) else ("Load fuel here" if _at_pump() else "Fuel up whatever's parked close by")
			return ["truck_fuel", "%s  %s   (diesel %.0f / avgas %.0f gal)" % [key, what, diesel_gal, avgas_gal]]
		return []
	var valve := global_transform * PUMP_VALVE
	if p.distance_to(valve) < 0.9 and (not hose_out or p.distance_to(valve) < 0.6):
		return ["truck_valve", "%s  %s the pump valve (to the hose reel)" % [key, "Close" if hose_valve else "Open"]]
	if hose_out:
		return ["truck_nozzle", "%s  %s the nozzle   %s reel the hose back in" % [key, "Close" if nozzle_open else "Open", Game.hint("door")]]
	var box := global_transform * MANIFOLD
	var reel := global_transform * REEL
	if p.distance_to(box) < 1.3 and p.distance_to(box) <= p.distance_to(reel):
		return ["truck_pump", "%s  Pump %s%s" % [key, "off" if pto else "on", "" if engine_on else "  (start the truck first)"]]
	if p.distance_to(reel) < 1.6:
		return ["truck_hose", "%s  Take the hose off the reel (50 ft)" % key]
	return []


func foot_act(a: String, p: Vector3) -> String:
	match a:
		"truck_valve":
			return _valve_toggle()
		"truck_fuel":
			return _fuel_action()
		"truck_pump":
			return toggle_pto()
		"fuel_hose_out":
			hose_out = true
			nozzle_open = false
			hose_valve = false
			hose_hand = p + Vector3(0, 1.2, 0)
			if _hose != null:
				_hose.reeling = false
			return "Fuel hose off the reel. Walk it to the plane's filler (on top of the wing root) and %s opens the nozzle." % Game.hint("interact")
		"fuel_nozzle":
			if nozzle_open:
				nozzle_open = false
				delivering = {}
				return "Nozzle shut."
			var at := _fill_point_near(hose_hand, 2.4)
			if at.is_empty():
				return "Not here - get the nozzle into a filler first (you'd be spraying avgas everywhere)."
			if not engine_on:
				return "The fuel pump runs off the engine: start the truck."
			var have := diesel_gal if String(at["kind"]) == "diesel" else avgas_gal
			if have <= 0.5:
				return "The %s compartment's empty: fill up at a fuel pump." % String(at["kind"])
			pto = true
			nozzle_open = true
			delivering = at
			return "Nozzle in the %s's filler: pumping %s." % [String(at["name"]), String(at["kind"])]
		"truck_hose":
			hose_out = true
			nozzle_open = false
			hose_hand = p + Vector3(0, 1.2, 0)
			if _hose != null:
				_hose.reeling = false
			return "Hose off the reel. %s opens the nozzle." % Game.hint("interact")
		"truck_nozzle":
			nozzle_open = not nozzle_open
			if nozzle_open and not engine_on:
				return "Nothing: the pump runs off the engine. Start the truck."
			if nozzle_open and not pto:
				pto = true
				return "Pump on, nozzle open."
			return "Nozzle %s." % ("open" if nozzle_open else "closed")
	return ""


func reel_in() -> String:
	if not hose_out:
		return ""
	hose_out = false
	nozzle_open = false
	if _hose != null:
		_hose.reeling = true
	return "Reeling the hose back in."


## Where the hand holding the nozzle can be: on the end of 50 ft of hose.
## Returns the allowed position for a walker wanting to be at `want`.
func hose_leash(want: Vector3) -> Vector3:
	var reel := global_transform * REEL
	var flat := Vector2(want.x - reel.x, want.z - reel.z)
	if flat.length() <= HOSE_LEN - 0.5:
		return want
	var f := flat.normalized() * (HOSE_LEN - 0.5)
	return Vector3(reel.x + f.x, want.y, reel.z + f.y)


func _animate() -> void:
	var dt := get_process_delta_time()
	_lamps(dt)
	# doors and hood swing to where they're wanted
	for i in range(2):
		_door_ang[i] = move_toward(float(_door_ang[i]), 1.15 if doors_open[i] else 0.0, dt * 2.2)
		var dn: Node3D = model.doors[i][0]
		dn.rotation.y = float(model.doors[i][1]) * float(_door_ang[i])
	_hood_ang = move_toward(_hood_ang, 1.2 if hood_open else 0.0, dt * 1.2)
	model.hood.rotation.x = -_hood_ang
	# the controls in the cab
	((model.park_knob as Node3D).get_child(0) as Node3D).position.z = 0.035 if park_brake else 0.0
	gear_fwd = move_toward(gear_fwd, clampf(body.speed * 0.05, -0.25, 0.25) if (body != null and engine_on) else 0.0, dt)
	(model.shifter as Node3D).rotation.x = -gear_fwd
	var sw: Dictionary = model.cab_switches
	if sw.has("pto"):
		(sw["pto"] as Node3D).rotation.x = -0.45 if pto else 0.45
	if sw.has("reel_valve"):
		(sw["reel_valve"] as Node3D).rotation.x = -0.45 if hose_valve else 0.45     # the reel's valve, worked from the cab too
	for vi in range(5):
		var key := "valve_%d" % vi
		if sw.has(key):
			(sw[key] as Node3D).rotation.x = -0.45 if valves[vi] else 0.45
	if body == null:
		model.pose(self, null, _wr, 0.0, [], [], 0.25)
	else:
		model.pose(self, body, _wr, body.steer, body.wheel_spin, body.compress, body.travel)
	if not _valve_levers.is_empty():
		(_valve_levers[0] as Node3D).rotation.z = 0.0 if pto else PI * 0.5      # switch up = pump on
	if model.pump_valve != null:
		var vz: float = model.pump_valve.rotation.z
		model.pump_valve.rotation.z = move_toward(vz, PI * 0.5 if hose_valve else 0.0, dt * 4.0)     # lever up = open
	if is_inside_tree():
		if _hose == null:
			_hose = HoseLine.new()
			_hose.name = "Hose"
			_hose.max_len = HOSE_LEN
			if is_fuel():
				_hose.colour = Color(0.08, 0.08, 0.08)
			_hose.ground = func(x: float, z: float) -> float: return terrain.height_at(x, z) if terrain != null else 0.0
			add_child(_hose)
			_hose.setup(global_transform * REEL, global_transform.basis * Vector3(0, -1, 0.3).normalized())
		var fr := Engine.get_process_frames()
		if fr != _hose_frame:
			_hose_frame = fr
			if model.reel_drum != null:
				# one hose: the turns still on the drum, the length from the drum
				# down to the guide, then the free hose (physics) out of the guide
				var u: float = float(Model.WOUND_STEPS) * _hose.on_drum()          # how far along the wound hose its end is
				var take := -PI * 0.5 + 0.25                                          # it comes off the bottom of the drum, toward the guide
				model.reel_drum.rotation.x = TAU * u / 24.0 - take                     # the drum turns as it pays out / winds in
				var keep := int(floor(u / float(Model.WOUND_PIECE)))                   # whole half turns still on
				for wi in range(model.wound_layers.size()):
					(model.wound_layers[wi] as Node3D).visible = wi < keep
				var dxf: Transform3D = model.reel_drum.global_transform
				var pre := PackedVector3Array()
				var su := float(keep * Model.WOUND_PIECE)
				while su < u:
					pre.append(dxf * Model.wound_local(su))
					su += 1.0
				var off: Vector3 = dxf * Model.wound_local(u)
				pre.append(off)
				var guide: Vector3 = global_transform * REEL
				for li in range(1, 5):
					pre.append(off.lerp(guide, float(li) / 5.0))                       # tight from the drum to the rollers
				_hose.pre = pre
			_hose.anchor = global_transform * REEL
			_hose.anchor_dir = (global_transform.basis * Vector3(0, -1, 0.3)).normalized()
			_hose.held = hose_out
			_hose.hand = hose_hand
			_hose.pressure = 1.0 if (hose_valve and engine_on and pto and tank_m3 > 0.0) else 0.0     # charged only with the pump on and the reel valve open
			_hose.step(dt)
	if _pump_lamp != null:
		var on := engine_on and pto
		if _lamp_was != int(on):
			_lamp_was = int(on)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.2, 0.9, 0.3) if on else Color(0.1, 0.15, 0.1)
			m.emission_enabled = on
			m.emission = Color(0.2, 0.9, 0.3)
			m.emission_energy_multiplier = 2.0
			_pump_lamp.material_override = m


## Where a winch hook or tow strap can go: [[name, world point], ...]
func winch_points() -> Array:
	var out: Array = []
	for wp in Model.WINCH_POINTS:
		out.append([String(wp[0]), global_transform * (wp[1] as Vector3)])
	return out


## The hose test (test bed): someone takes the nozzle and walks it out round
## the back of the truck to the full 50 ft, then it's reeled back in.
var _hose_demo := -1.0
var _hose_frame := -1
func hose_demo(on: bool) -> String:
	if on:
		_hose_demo = 0.0
		hose_out = true
		nozzle_open = false
		if _hose != null:
			_hose.reeling = false
		return "Hose test: taking the nozzle off the reel and walking it out."
	_hose_demo = -1.0
	return reel_in()


func hose_demo_step(dt: float) -> void:
	if _hose_demo < 0.0:
		return
	_hose_demo += dt
	var t := _hose_demo
	var back := global_transform * (REEL + Vector3(0, 0, 0.6))
	if t < 12.0:
		# out behind, round to the side, along past the cab
		var a := clampf(t / 12.0, 0.0, 1.0)
		var r := lerpf(1.0, 13.5, a)
		var ang := lerpf(0.0, PI * 0.55, a)
		var flat := global_transform.basis * Vector3(sin(ang) * r, 0, cos(ang) * r)
		var g: float = terrain.height_at(back.x + flat.x, back.z + flat.z) if terrain != null else 0.0
		hose_hand = Vector3(back.x + flat.x, g + 1.0, back.z + flat.z)
	elif t < 13.0:
		pass
	elif t < 13.1:
		reel_in()
	elif _hose != null and not _hose.reeling:
		_hose_demo = -1.0


func door_toggle(which: int = 0) -> String:
	if which < 0:
		var to: bool = not (doors_open[0] and doors_open[1])
		doors_open = [to, to]
		return "Doors %s." % ("open" if to else "shut")
	which = clampi(which, 0, 1)
	doors_open[which] = not doors_open[which]
	return "%s door %s." % ["Driver's" if which == 0 else "Passenger", "open" if doors_open[which] else "shut"]


func hood_toggle() -> String:
	hood_open = not hood_open
	return "Hood %s." % ("tilted forward" if hood_open else "down")


func lights_toggle() -> String:
	return EK.lights_toggle(self)


## A click on a control in the cab (the lab's left click, or in the seat).
func control_click(nm: String) -> String:
	match nm:
		"park":
			park_brake = not park_brake
			return "Park brake %s." % ("set" if park_brake else "off")
		"shifter":
			return "Ten-speed: drive it with the throttle (the shifter rocks with the gears)."
		"pto":
			return toggle_pto()
		"pump_valve", "reel_valve":
			return _valve_toggle()
	if nm.begins_with("valve_"):
		return toggle_valve(int(nm.substr(6)))
	return ""


func status() -> String:
	if is_fuel():
		var doing := "  LOADING" if loading else ("  FUELLING THE " + String(delivering.get("name", "")).to_upper() if not delivering.is_empty() else "")
		return "Fuel truck: diesel %.0f / %.0f gal, avgas %.0f / %.0f gal%s   engine %s, air %d psi   %s engine  %s load at a pump / fuel up what's parked by you" % [
			diesel_gal, DIESEL_CAP, avgas_gal, AVGAS_CAP, doing, "on" if engine_on else "OFF", int(air_psi), Game.hint("engine_auto"), Game.hint("interact")]
	return "Water truck: %.0f gal%s   engine %s, air %d psi   pump %s   sprays %s   %s engine  6 pump  %s fill / sprays" % [tank_m3 * GAL, "  FILLING" if filling else "",
		"on" if engine_on else "OFF", int(air_psi), "ON" if pto else "off", "on" if _pumping() and not hose_out else "off",
		Game.hint("engine_auto"), Game.hint("interact")]


func save() -> void:
	if EK.in_lab(self):
		return                      # the lab mustn't touch the game's save
	var cf := ConfigFile.new()
	cf.set_value("t", "xf", global_transform)
	cf.set_value("t", "water", tank_m3)
	cf.set_value("t", "fuel", fuel_gal)
	cf.set_value("t", "tyres", tyre_kind)
	cf.set_value("t", "valves", valves)
	cf.set_value("t", "hose_valve", hose_valve)
	cf.set_value("t", "diesel", diesel_gal)
	cf.set_value("t", "avgas", avgas_gal)
	cf.save(_save_path())


## Load the saved truck or put a new one on the apron.
func load_or_default() -> void:
	var cf := ConfigFile.new()
	var home := home_xf
	var xf := home
	if is_fuel():
		diesel_gal = DIESEL_CAP
		avgas_gal = AVGAS_CAP
	if cf.load(_save_path()) == OK:
		diesel_gal = float(cf.get_value("t", "diesel", diesel_gal))
		avgas_gal = float(cf.get_value("t", "avgas", avgas_gal))
		xf = cf.get_value("t", "xf", xf)
		tank_m3 = float(cf.get_value("t", "water", 0.0))
		fuel_gal = float(cf.get_value("t", "fuel", 80.0))
		var vs: Array = cf.get_value("t", "valves", [])
		for i in range(mini(vs.size(), 5)):
			valves[i] = bool(vs[i])
		var tk := String(cf.get_value("t", "tyres", tyre_kind))
		if TYRES.has(tk) and tk != tyre_kind:
			tyre_kind = tk
			_build_wheels()
		if xf.origin.distance_to(Vector3(-8.0, xf.origin.y, -80.0)) < 4.0:
			xf = home              # first spot was inside the bunkhouse
	park(xf)


## G (D-pad up): put the front axle in (6x6) or take it out (6x4).
func four_wd_toggle() -> String:
	# G: 6x4 -> 6x6 -> 6x6 Low -> 6x4
	if body == null:
		return ""
	var msg := ""
	if not awd:
		awd = true
		msg = "6x6: front axle in, all six wheels driven."
	elif not low:
		if absf(body.speed) > 2.0:
			return "Slow right down before you shift into low range."
		low = true
		msg = "6x6 LOW: crawler gear - slow, and it pulls like a tractor."
	else:
		awd = false
		low = false
		msg = "6x4: front axle out, the two back axles drive."
	for w in body.wheels:
		if bool((w as Array)[1]):
			(w as Array)[2] = awd
	_apply_range()
	return msg


## 9 (right stick click): the diff lock - the cross-axle diffs and the
## inter-axle diff all locked, so every driven wheel pulls whatever its grip.
func diff_lock_toggle() -> String:
	diff_lock = not diff_lock
	_apply_locks()
	return "DIFF LOCK %s%s" % ["ON" if diff_lock else "off", ": every driven wheel pulls - steering's heavy on firm ground" if diff_lock else ": open diffs, a spinning wheel takes the power"]


func _apply_locks() -> void:
	if body == null:
		return
	body.lock_inter = diff_lock
	body.lock_front = diff_lock
	body.lock_rear = diff_lock


## Low range: more pull at the wheels, a much lower top speed.
func _apply_range() -> void:
	if body == null:
		return
	if _base_power <= 0.0:
		_base_power = body.power
		_base_top = body.top_speed
	body.power = _base_power * (LOW_PULL if low else 1.0)
	body.top_speed = minf(_base_top, LOW_TOP) if low else _base_top


## A filler cap within r of the nozzle: the target (from refuel_targets) or {}.
## Targets may give "fills" (world points: the plane's wing-root tank caps).
func _fill_point_near(at: Vector3, r: float) -> Dictionary:
	if not refuel_targets.is_valid():
		return {}
	var best := {}
	var bd := r
	for t in refuel_targets.call():
		var pts: Array = t.get("fills", [t["pos"]])
		for q in pts:
			var d := (q as Vector3).distance_to(at)
			if d < bd and float(t["need"]) > 0.05:
				bd = d
				best = t
	return best
