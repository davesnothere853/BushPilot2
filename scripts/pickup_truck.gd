extends Node3D
## A 3/4-ton pickup (DESIGN_NOTES 79): a long bed that takes cargo pieces
## (carry them up and drop them in, or salvage them from a wreck and drive
## them to the destination or another plane), and a receiver hitch on the
## back that pulls anything with a tongue - the sluice trailer, the wash
## plant, later flatbeds and dump trailers. Back up to a tongue and press
## the attach key in the cab (Farming Simulator style).
## Real wheeled physics (wheeled_body.gd), 4x4.

const MeshKit = preload("res://scripts/meshkit.gd")
const TyreMesh = preload("res://scripts/tyre_mesh.gd")
const Wiring = preload("res://scripts/gauge_wiring.gd")
const Dash = preload("res://scripts/truck_dash.gd")
const WheeledBody = preload("res://scripts/wheeled_body.gd")
const EngineSim = preload("res://scripts/engine_sim.gd")
const Parts = preload("res://scripts/parts.gd")
const SAVE := "user://pickup.cfg"
const BED_MAX_KG := 1400.0
var HITCH := Vector3(0, 0.60, 2.86)      # the ball, truck frame (square body, DESIGN_NOTES 192)
const BED_Y := 0.93
## Logs (cargo.gd "sawlog") lie lengthways in the bed: four across, two high.
const LOG_CAP := 8
## Spots in the bed (truck frame), front to back, left to right.
const BED_SPOTS := [
	Vector3(-0.5, BED_Y, 0.9), Vector3(0.0, BED_Y, 0.9), Vector3(0.5, BED_Y, 0.9),
	Vector3(-0.5, BED_Y, 1.45), Vector3(0.0, BED_Y, 1.45), Vector3(0.5, BED_Y, 1.45),
	Vector3(-0.5, BED_Y, 2.0), Vector3(0.0, BED_Y, 2.0), Vector3(0.5, BED_Y, 2.0),
	Vector3(-0.5, BED_Y, 2.55), Vector3(0.0, BED_Y, 2.55), Vector3(0.5, BED_Y, 2.55),
]

const PAINT := Color(0.20, 0.33, 0.27)       # forest green
const DARK := Color(0.09, 0.09, 0.10)
const STEEL := Color(0.62, 0.63, 0.64)
const GLASS := Color(0.75, 0.85, 0.9, 0.12)

var terrain: RefCounted
var body: RefCounted
var driven := false
var yaw := 0.0
var towing: Node3D = null              # towable.gd hitched to the ball
var towables: Callable                 # func() -> Array of towable nodes (main)
var bed_load: Callable                 # func() -> float kg of cargo in the bed (main)
var _wheel_nodes: Array = []
# the engine: start it (I) to drive; gauges read these
var engine_on := false
var rpm := 0.0
var coolant_f := 60.0
var oil_psi := 0.0
var fuel_gal := 16.0
var volts := 12.5
var _told_off := 0.0
var _save_t := 0.0


func display_name() -> String:
	return variant if variant != "" else "pickup"


func build() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_load_body()
	_build_shafts()
	_build_dash()
	_build_lamps()
	_build_wheels()
	_build_winch()


## The bumper winch (DESIGN_NOTES 203): winch.gd on the fairlead.
const WinchScript = preload("res://scripts/winch.gd")
var winch: Node3D


func _build_winch() -> void:
	if winch != null:
		winch.queue_free()
	winch = WinchScript.new()
	winch.name = "Winch"
	add_child(winch)
	var nz: float = float(TruckBody.P.get("nose_z", -2.47))
	winch.setup(self, Vector3(0, 0.66 + _wr - MODEL_TYRE_R, nz - 0.29))
	winch.ground = func(x: float, z: float) -> float: return terrain.height_at(x, z) if terrain != null else 0.0


## A physics step for the winch, and for the truck itself when a cable is
## pulling it and nobody's driving (it gets dragged, or drags what it's hooked to).
func winch_step(dt: float, driven_now: bool) -> void:
	if winch == null or body == null:
		return
	winch.step(dt)
	if not driven_now and (winch.tension > 0.0 or not body.ext_pulls.is_empty()):
		# the winching truck sits on its brakes; the one being pulled rolls free -
		# unless it's bogged: then the mud holds it (suction and the ruts it has
		# to climb out of) and its wheels are locked in the muck
		# the winching truck: brakes on, in gear, dug in - it holds about as hard
		# as a bogged truck does, so the stuck one comes to it, not the reverse
		var hold_n: float = stuck_drag if stuck_drag > 0.0 else (46000.0 if winch.tension > 0.0 else 0.0)
		var bogged := hold_n > 0.0
		if bogged:
			var v: Vector3 = body.vel
			var sp := v.length()
			var hold := hold_n * clampf(0.35 + sp * 4.0, 0.0, 1.0)
			body.pull((-v / sp if sp > 0.01 else Vector3.ZERO) * hold, global_position + Vector3(0, 0.6, 0))
			if sp <= 0.01 and not body.ext_pulls.is_empty():
				# at rest: it only moves once the pull beats the mud's grip
				var f := Vector3.ZERO
				for pr in body.ext_pulls:
					f += pr[0]
				if f.length() < hold_n * 0.6:
					body.ext_pulls.clear()
		body.step(dt, 0.0, 0.0, winch.tension > 0.0 or bogged)
		global_transform = body.transform()
		yaw = body.yaw()


## The pickup (DESIGN_NOTES 106): a generic late-'80s three-quarter-ton
## extended cab with the 8 ft bed - modelled in Blender over a side / front /
## rear drawing (tools: bp2_truck/build_pickup.py), no maker's names or
## badges. 155 in wheelbase, 230 in long, 79 in wide, 76 in to the roof.
## The body is one mesh; the hood, tailgate, steering wheel and every bulb
## are their own nodes so they open, turn and light. The model was built
## on 33 in tyres (radius 0.4175 m): it rides up or down with the tyres on it.
const BODY_GLB := "res://assets/vehicles/pickup_body.glb"
const MODEL_TYRE_R := 0.4175
const WARM_HEAD := Color(1.0, 0.80, 0.52)   # ~3000 K halogen headlamp
const TYRE_SQUASH := preload("res://shaders/tyre_squash.gdshader")
## (DESIGN_NOTES 192) a '73-'87-style square body, regular cab, 8 ft bed:
## 131.5 in wheelbase. The cab (seat, wheel, gauges, eye point) is where it was.
const WB := 3.34                  # 131.5 in
const FZ := -1.72
var RZ := 1.62                    # set from the body style (truck_body.RZ)
var variant := ""                 # "" / "pickup", "blazer", "suburban" (DESIGN_NOTES 202)
const TW := 0.82                  # half track
const CHROME := Color(0.80, 0.81, 0.82)
var HOOD_HINGE := Vector3(0, 1.39, -1.317)       # at the cowl (model frame)
var GATE_HINGE := Vector3(0, 0.80, 2.64)         # bottom of the tailgate
var WHEEL_C := Vector3(-0.42, 1.28, -0.72)       # steering wheel centre
const WHEEL_AXIS := Vector3(0, 0.469, 0.883)       # its column axis, up and back toward the driver
var CLUSTER := Vector3(-0.45, 1.30, -0.889)      # the gauge cluster face (raised pod, over the rim)
var _wr := 0.40                   # tyre radius now (TYRES)
var tyre_kind := "at33"           # all-terrains, like the reference photo (DESIGN_NOTES 192)
var _model: Node3D                # the body, riding at the tyres' height
var _shafts: Array = []           # drive shafts that turn with the wheels
var _axle_f: Node3D               # the axle housings (their own parts in the model)
var _axle_r: Node3D
var _lamps: Array = []            # SpotLight3D headlamps
var _bulbs := {}                  # bulb name -> MeshInstance3D
var _bulb_mats := {}              # bulb name -> [off material, on material]
var _lights3d := {}               # "tail_l" etc -> OmniLight3D / SpotLight3D
var lights_on := false
var blink := 0                    # -1 left, 1 right, 0 off
var hood_open := false
var gate_open := false
var _hood_pivot: Node3D
var _gate_pivot: Node3D
var stuck_drag := 0.0            # N: a truck bogged in mud resists being pulled (test bed / game mud)
var _fuel_pivot: Node3D          # the fuel door, hinged at its front edge
var fuel_open := false
var _fuel_a := 0.0
var _cap_pivot: Node3D            # the fuel cap: unscrews, then hangs on its tether
var _cap_center := Vector3.ZERO
var _cap_tether := Vector3.ZERO
var _cap_t := 0.0                 # 0 screwed in .. 0.6 unscrewed .. 1 hanging
var _cap_hang := 0.0              # time hanging (for the swing)
var _tether: MeshInstance3D
var _wheel_pivot: Node3D
var _hood_a := 0.0
var _gate_a := 0.0
var _cab_dz := 0.0                # cab moved back (truck_body.cab_dz)
var _drv_dz := 0.0                # the driver's seat, wheel and gauges moved back (driver_dz)
var _eng_dz := 0.0                # engine moved (truck_body.engine_z - its first place)
## The doors (DESIGN_NOTES 195): [left, right], hinged at the A pillars.
var doors_open := []
var _door_pivots: Array = []
var _door_a := []
var _links: Array = []            # suspension parts that ride with the axles (truck_body links)
var test_drive := false           # the Model Lab's test bed drives the visuals itself
var gear := 0                     # 0 neutral, 1-4
## The engine and drivetrain, from the parts bolted in (DESIGN_NOTES 111).
var esim := EngineSim.new()
var _turbo_node: Node3D
var _tags_node: Node3D
var _parts_seen := ""
## Where each part sits (truck frame) and whether you need the hood up.
const PART_SPOTS := {
	"engine": [Vector3(0, 0.95, -1.80), true], "heads": [Vector3(0.30, 1.12, -1.80), true],
	"intake": [Vector3(0, 1.22, -1.85), true], "fuel": [Vector3(0, 1.34, -1.70), true],
	"fuel_pump": [Vector3(-0.26, 0.80, -2.12), true], "fuel_filter": [Vector3(-0.18, 1.18, -2.18), true],
	"turbo": [Vector3(0.50, 1.02, -1.62), true], "intercooler": [Vector3(0, 0.80, -2.62), true],
	"exhaust": [Vector3(-0.36, 0.98, -1.80), true], "radiator": [Vector3(0, 1.05, -2.45), true],
	"alternator": [Vector3(0.30, 1.16, -2.18), true], "battery": [Vector3(-0.62, 1.16, -2.20), true],
	"starter": [Vector3(-0.32, 0.62, -1.42), false], "transmission": [Vector3(0, 0.62, -0.90), false],
	"transfer": [Vector3(-0.15, 0.56, -0.40), false], "driveshaft_f": [Vector3(-0.17, 0.48, -1.20), false],
	"driveshaft_r": [Vector3(0, 0.52, 0.70), false], "diff_f": [Vector3(-0.19, 0.42, -1.72), false],
	"diff_r": [Vector3(0, 0.42, 1.62), false],
}
## vehicle_breakage.gd tore something off (or a lamp bust): stop driving it.
func part_detached(nm: String) -> void:
	if nm == "HoodPivot":
		_hood_pivot = null
	elif nm == "TailgatePivot":
		_gate_pivot = null
	elif nm == "FuelDoorPivot":
		_fuel_pivot = null
	elif nm == "FuelCapPivot":
		_cap_pivot = null
	for i in range(_door_pivots.size()):
		if _door_pivots[i] != null and String((_door_pivots[i] as Node).name) == nm:
			_door_pivots[i] = null
	for bn in _bulbs.keys():
		var mi = _bulbs[bn]
		if not is_instance_valid(mi) or not (mi as Node3D).is_visible_in_tree() or String(bn) == nm:
			_bulbs.erase(bn)
	_links = _links.filter(func(l): return is_instance_valid(l) and _model.is_ancestor_of(l))


## Where a part sits now: the engine-bay ones move with the engine.
func _spot(slot: String) -> Vector3:
	var v: Vector3 = PART_SPOTS[slot][0]
	if v.z < -0.3:
		v.z += _eng_dz
	return v


## What has to come off before a part can (and so goes back on after it).
const PART_BEFORE := {
	"engine": ["heads", "exhaust", "starter", "fuel_pump"], "heads": ["intake", "exhaust"], "intake": ["fuel"],
	"exhaust": ["turbo"], "turbo": ["intercooler"], "transmission": ["transfer", "driveshaft_r"],
	"transfer": ["driveshaft_f"],
}
var _in := Vector2.ZERO           # last drive input
var _braking := false
var _reversing := false
var _blink_t := 0.0

## Tyres you can put on it (E at a wheel, truck stopped): radius and width
## in metres, grip on dirt and on the strip, and what the shop charges.
const TYRES := {
	"lt235": {"name": "LT235/85R16 highway", "r": 0.40, "w": 0.235, "tread": "highway", "mu_dirt": 0.85, "mu_hard": 1.0, "price": 0},
	"at31":  {"name": "31x10.50R15 all-terrain", "r": 0.395, "w": 0.27, "tread": "at", "mu_dirt": 0.95, "mu_hard": 0.97, "price": 650},
	"mud33": {"name": "33x12.50R15 mud", "r": 0.42, "w": 0.32, "tread": "mud", "mu_dirt": 1.08, "mu_hard": 0.88, "price": 900},
	"at33": {"name": "33x10.50R15 all-terrain", "r": 0.42, "w": 0.265, "tread": "at", "mu_dirt": 0.98, "mu_hard": 0.96, "price": 850},
	"at35": {"name": "35x12.50R15 all-terrain", "r": 0.445, "w": 0.32, "tread": "at", "mu_dirt": 1.0, "mu_hard": 0.95, "price": 1100},
	"mud35": {"name": "35x12.50R15 mud", "r": 0.445, "w": 0.32, "tread": "mud", "mu_dirt": 1.12, "mu_hard": 0.85, "price": 1200},
}


## (DESIGN_NOTES 191) the body is built in code now (truck_body.gd: smooth,
## real-proportioned, live-tunable); the old Blender body is the fallback.
const CODE_BODY := true
const TruckBody = preload("res://scripts/truck_body.gd")


## The body from the .glb (read at run time, so it needs no import step).
func _load_body() -> void:
	var scene: Node
	if CODE_BODY:
		scene = TruckBody.build(variant)
		RZ = TruckBody.RZ
	else:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		var path := ProjectSettings.globalize_path(BODY_GLB)
		var err := doc.append_from_file(path, st)
		if err != OK:
			push_warning("pickup: couldn't read %s (%d)" % [BODY_GLB, err])
			return
		scene = doc.generate_scene(st)
	scene.name = "Body"
	_model.add_child(scene)
	if CODE_BODY:
		# the cab, hinges and hitch where this build of the body put them (DESIGN_NOTES 198)
		var P: Dictionary = TruckBody.P
		_cab_dz = TruckBody.cab_dz()
		_eng_dz = TruckBody.engine_z() + 1.80
		HOOD_HINGE = Vector3(0, float(P["cowl_y"]) + 0.05, float(P["cowl_z"]) + 0.003)
		GATE_HINGE = Vector3(0, 0.735, float(P["tail_z"]))
		HITCH = Vector3(0, 0.60, float(P["tail_z"]) + 0.22)
		_drv_dz = TruckBody.driver_dz()
		WHEEL_C = Vector3(-0.42, 1.28, -0.72 + _drv_dz)
		CLUSTER = Vector3(-0.45, 1.30, -0.889 + _drv_dz)
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		if nm.ends_with("Bulb"):
			_bulbs[nm] = mi
	# hinged and turning parts: put each on a pivot at its hinge / column
	_hood_pivot = _pivot(scene, "Hood", HOOD_HINGE, Basis.IDENTITY)
	_gate_pivot = _pivot(scene, "Tailgate", GATE_HINGE, Basis.IDENTITY)
	var fdn := scene.find_child("FuelDoor", true, false) as Node3D
	_fuel_pivot = null
	if fdn != null and fdn.has_meta("hinge"):
		_fuel_pivot = _pivot(scene, "FuelDoor", fdn.get_meta("hinge"), Basis.IDENTITY)
	var fcn := scene.find_child("FuelCap", true, false) as Node3D
	_cap_pivot = null
	if fcn != null and fcn.has_meta("center"):
		_cap_center = fcn.get_meta("center")
		_cap_tether = fcn.get_meta("tether")
		_cap_pivot = _pivot(scene, "FuelCap", _cap_center, Basis.IDENTITY)
		if _tether == null or not is_instance_valid(_tether):
			_tether = MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(0.004, 0.004, 1.0)
			_tether.mesh = tm
			var tmat := StandardMaterial3D.new()
			tmat.albedo_color = Color(0.06, 0.06, 0.06)
			tmat.roughness = 0.7
			_tether.material_override = tmat
			_model.add_child(_tether)
		_tether.visible = false
	_door_pivots = []
	doors_open = []
	_door_a = []
	for nm in ["DoorL", "DoorR", "DoorBackL", "DoorBackR"]:
		var dn := scene.find_child(nm, true, false) as Node3D
		if dn != null:
			var pv := _pivot(scene, nm, dn.get_meta("hinge", Vector3.ZERO), Basis.IDENTITY)
			pv.set_meta("side", dn.get_meta("side", -1.0))
			_door_pivots.append(pv)
			doors_open.append(false)
			_door_a.append(0.0)
	_links = []
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		if (n as Node).has_meta("ends"):
			_links.append(n)
	var ax := WHEEL_AXIS.normalized()
	_wheel_pivot = _pivot(scene, "SteeringWheel", WHEEL_C, Basis(Vector3.RIGHT, ax, Vector3.RIGHT.cross(ax)).orthonormalized())
	# the axles ride with the wheels, not the body (a lift kit raises the body)
	_axle_f = scene.find_child("AxleF", true, false) as Node3D
	_axle_r = scene.find_child("AxleR", true, false) as Node3D
	for axn in [_axle_f, _axle_r]:
		if axn != null:
			axn.set_meta("rest_y", axn.position.y)


func _pivot(scene: Node, part: String, at: Vector3, basis: Basis) -> Node3D:
	var n := scene.find_child(part, true, false) as Node3D
	if n == null:
		return null
	var pv := Node3D.new()
	pv.name = part + "Pivot"
	pv.transform = Transform3D(basis, at)
	_model.add_child(pv)
	var keep := n.global_transform if n.is_inside_tree() else n.transform
	n.get_parent().remove_child(n)
	pv.add_child(n)
	n.transform = pv.transform.affine_inverse() * keep
	pv.set_meta("rest", pv.transform.basis)
	return pv


## Drive shafts: from the transfer case to each axle; they turn.
func _build_shafts() -> void:
	for old in _shafts:
		(old as Node).queue_free()
	_shafts.clear()
	# the axle ends drop with a lift kit: the shafts angle down to them
	for sh in [[Vector3(-0.15, 0.55, -0.80 + _eng_dz), Vector3(-0.19, 0.42, FZ + 0.1), 0], [Vector3(0.0, 0.56, -0.57 + _eng_dz), Vector3(0.0, 0.42, RZ - 0.14), 1]]:
		var a: Vector3 = sh[0]
		var b: Vector3 = sh[1]
		var node := Node3D.new()
		var d := b - a
		# a link (truck_body.place_link): it angles and slides to its axle as it moves
		node.set_meta("ends", [a, b, -1, int(sh[2])])
		node.set_meta("rest_len", d.length())
		node.set_meta("stretch", true)
		var sk := MeshKit.new()
		sk.cylinder(Transform3D.IDENTITY, 0.04, 0.04, d.length(), 10, STEEL.darkened(0.15))
		for uj in [0.0, d.length()]:
			sk.box_at(Vector3(0, uj, 0), Vector3(0.1, 0.05, 0.03), DARK)
			sk.box_at(Vector3(0, uj, 0), Vector3(0.03, 0.05, 0.1), DARK)
		sk.box_at(Vector3(0, d.length() * 0.5, 0.045), Vector3(0.02, 0.12, 0.01), Color(0.9, 0.9, 0.85))
		node.add_child(sk.instance("Shaft"))
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_model.add_child(node)
		TruckBody.place_link(node, a, b + Vector3(0, -_lift, 0))
		_shafts.append(node)


## The working gauges in the dash cluster: speed in the middle, the tach,
## fuel and temperature, oil pressure and the ammeter; the warning lamps.
func _build_dash() -> void:
	var dash := Dash.new()
	dash.name = "Dash"
	_model.add_child(dash)
	dash.transform = Transform3D(Basis(Vector3.RIGHT, -0.62), CLUSTER + Vector3(0, 0, 0.012))
	dash.gauge(Vector2(-0.02, 0.0), 0.06, {"title": "MPH", "lo": 0, "hi": 85, "major": 10, "minor": 5, "a0": 225, "a1": -45},
		func() -> float: return absf(body.speed) * 2.237 if body != null else 0.0)
	dash.gauge(Vector2(-0.17, 0.0), 0.045, {"title": "RPM", "unit": "x1000", "lo": 0, "hi": 6, "major": 1, "minor": 0.5, "a0": 225, "a1": -45,
		"bands": [[5, 6, Color(0.8, 0.12, 0.08)]]}, func() -> float: return rpm / 1000.0)
	dash.gauge(Vector2(0.12, 0.04), 0.027, {"title": "FUEL", "lo": 0, "hi": 1, "major": 0.5, "minor": 0.25, "a0": 210, "a1": -30, "numbers": false,
		"labels": [["E", 0.0], ["F", 1.0]], "bands": [[0, 0.12, Color(0.8, 0.12, 0.08)]]}, func() -> float: return fuel_gal / 19.0)
	dash.gauge(Vector2(0.12, -0.04), 0.027, {"title": "TEMP", "lo": 100, "hi": 260, "major": 80, "minor": 40, "a0": 210, "a1": -30,
		"bands": [[230, 260, Color(0.8, 0.12, 0.08)]]}, func() -> float: return coolant_f)
	dash.gauge(Vector2(0.2, 0.04), 0.027, {"title": "OIL", "lo": 0, "hi": 80, "major": 40, "minor": 20, "a0": 210, "a1": -30}, func() -> float: return oil_psi)
	dash.gauge(Vector2(0.2, -0.04), 0.027, {"title": "AMP", "lo": -40, "hi": 40, "major": 40, "minor": 20, "a0": 210, "a1": -30},
		func() -> float: return (volts - 13.0) * 20.0 if engine_on else -3.0)
	dash.lamp(Vector2(-0.1, -0.075), Color(0.2, 0.9, 0.3), func() -> bool: return blink < 0 and _blink_on())
	dash.lamp(Vector2(0.06, -0.075), Color(0.2, 0.9, 0.3), func() -> bool: return blink > 0 and _blink_on())
	dash.lamp(Vector2(-0.02, -0.075), Color(0.3, 0.5, 1.0), func() -> bool: return lights_on)
	dash.lamp(Vector2(0.14, -0.08), Color(1, 0.75, 0.1), func() -> bool: return towing != null)
	_build_pod()


## The aftermarket gauge pod under the dash, right of the column (DESIGN_NOTES
## 121): three gauges, each wired to a reading in the workshop.
var pod_wiring: Array = Wiring.DEFAULT.duplicate()
var _pod: Node3D
const POD_AT := Vector3(-0.04, 1.15, -0.80)       # truck model frame, under the dash lip


func _build_pod() -> void:
	if _model == null:
		return
	if _pod != null:
		_pod.queue_free()
	var pod := Dash.new()
	pod.name = "DashPod"
	_model.add_child(pod)
	pod.transform = Transform3D(Basis(Vector3.RIGHT, -0.35), POD_AT)
	_pod = pod
	# the bracket: a black steel strip the gauges sit in
	var k := MeshKit.new()
	k.box_at(Vector3(0, 0, -0.035), Vector3(0.22, 0.075, 0.03), Color(0.05, 0.05, 0.055))
	pod.add_child(k.instance("PodBracket"))
	for i in range(3):
		var sig: String = pod_wiring[i] if i < pod_wiring.size() else "none"
		var spec: Dictionary = (Wiring.SIGNALS.get(sig, Wiring.SIGNALS["none"]) as Array)[1]
		var s2 := sig
		pod.gauge(Vector2(-0.07 + 0.07 * float(i), 0.0), 0.026, spec, func() -> float: return Wiring.read(s2, esim))


## Send a reading to pod gauge i (the workshop menu).
func wire_gauge(i: int, sig: String) -> void:
	while pod_wiring.size() < 3:
		pod_wiring.append("none")
	pod_wiring[i] = sig
	_build_pod()
	save()


## Real lamps: the bulbs light (an emissive material), and the headlamps,
## tail / brake, reverse lamps throw light.
func _build_lamps() -> void:
	for nm in _bulbs.keys():
		var col := Color(1.0, 0.95, 0.85)
		if nm.begins_with("Head"):
			col = WARM_HEAD                      # halogen sealed beams: warm, a little yellow
		if nm.begins_with("Tail") or nm.begins_with("RearMarker"):
			col = Color(1.0, 0.12, 0.05)
		elif nm.begins_with("Park") or nm.begins_with("FrontMarker"):
			col = Color(1.0, 0.55, 0.08)
		var off := StandardMaterial3D.new()
		# unlit, a lamp still reads as its lens: clear and bright for the head
		# lamps, coloured glass for the rest (DESIGN_NOTES 197)
		off.albedo_color = Color(0.86, 0.87, 0.88) if nm.begins_with("Head") or nm.begins_with("Reverse") or nm.begins_with("Plate") or nm.begins_with("Park") else col.darkened(0.25)
		off.roughness = 0.08
		off.metallic = 0.6 if nm.begins_with("Head") else 0.1
		var on := StandardMaterial3D.new()
		on.albedo_color = col
		on.emission_enabled = true
		on.emission = col
		on.emission_energy_multiplier = 6.0
		on.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bulb_mats[nm] = [off, on]
		(_bulbs[nm] as MeshInstance3D).material_override = off
	for s8 in [-1.0, 1.0]:
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(s8 * 0.735, 1.05, float(TruckBody.P.get("nose_z", -2.58)) - 0.05)
		lamp.rotation = Vector3(deg_to_rad(-5.0), 0, 0)
		lamp.light_color = WARM_HEAD
		lamp.light_energy = 0.0
		lamp.spot_range = 50.0
		lamp.spot_angle = 30.0
		lamp.spot_attenuation = 0.7
		lamp.shadow_enabled = false
		_model.add_child(lamp)
		_lamps.append(lamp)
		var tail := OmniLight3D.new()
		tail.position = Vector3(s8 * 0.93, 1.10, float(TruckBody.P.get("tail_z", 2.64)) + 0.15)
		tail.light_color = Color(1.0, 0.1, 0.05)
		tail.light_energy = 0.0
		tail.omni_range = 2.5
		_model.add_child(tail)
		_lights3d["tail%d" % int(s8)] = tail
		var rev := SpotLight3D.new()
		rev.position = Vector3(s8 * 0.93, 0.98, float(TruckBody.P.get("tail_z", 2.64)) + 0.15)
		rev.rotation = Vector3(deg_to_rad(-20.0), PI, 0)
		rev.light_color = Color(1.0, 0.97, 0.9)
		rev.light_energy = 0.0
		rev.spot_range = 8.0
		rev.spot_angle = 45.0
		_model.add_child(rev)
		_lights3d["rev%d" % int(s8)] = rev


func _blink_on() -> bool:
	return fmod(_blink_t, 0.8) < 0.4


func _set_bulb(prefix: String, on: bool) -> void:
	for nm in _bulbs.keys():
		if String(nm).begins_with(prefix):
			(_bulbs[nm] as MeshInstance3D).material_override = _bulb_mats[nm][1 if on else 0]


func _update_lamps(delta: float) -> void:
	_blink_t += delta
	var bl := _blink_on()
	var lit := lights_on
	_set_bulb("HeadLamp", lit)
	_set_bulb("PlateLamp", lit)
	_set_bulb("ParkLamp-1", lit or (blink < 0 and bl))
	_set_bulb("ParkLamp1", lit or (blink > 0 and bl))
	_set_bulb("FrontMarker", lit)
	_set_bulb("RearMarker", lit)
	var tail_l := lit or _braking or (blink < 0 and bl)
	var tail_r := lit or _braking or (blink > 0 and bl)
	_set_bulb("TailLamp-1", tail_l)
	_set_bulb("TailLamp1", tail_r)
	_set_bulb("ReverseLamp", _reversing)
	for l in _lamps:
		(l as SpotLight3D).light_energy = 2.5 if lit else 0.0
	for s8 in [-1, 1]:
		var tl: OmniLight3D = _lights3d["tail%d" % s8]
		var on_t: bool = tail_l if s8 < 0 else tail_r
		tl.light_energy = (1.6 if _braking else 0.6) if on_t else 0.0
		(_lights3d["rev%d" % s8] as SpotLight3D).light_energy = 1.2 if _reversing else 0.0


## V: lights; Z / X: left / right blinker (again to cancel).
func blinker(dir: int) -> String:
	blink = 0 if blink == dir else dir
	return "Blinker %s." % ("off" if blink == 0 else ("left" if blink < 0 else "right"))


## Y at the front: the hood; Y at the back: the tailgate.
func hood_toggle() -> String:
	hood_open = not hood_open
	return "Hood %s." % ("up" if hood_open else "down")


func fuel_door_toggle() -> String:
	fuel_open = not fuel_open
	return "Fuel door %s." % ("open" if fuel_open else "shut")


func tailgate_toggle() -> String:
	gate_open = not gate_open
	return "Tailgate %s." % ("down" if gate_open else "up")


## A door: 0 driver's (left), 1 passenger's; -1 both.
func door_toggle(which: int = 0) -> String:
	if doors_open.is_empty():
		return ""
	if which < 0:
		var to: bool = not doors_open.all(func(d): return d)
		for i in range(doors_open.size()):
			doors_open[i] = to
		return "Doors %s." % ("open" if to else "shut")
	which = clampi(which, 0, doors_open.size() - 1)
	doors_open[which] = not doors_open[which]
	return "%s door %s." % ["Driver's" if which == 0 else "Passenger's", "open" if doors_open[which] else "shut"]


## How far an axle has moved up at x (truck frame) from the springs: from
## its two wheels' compression, minus a lift kit.
func _axle_dy(ai: int, x: float) -> float:
	if body == null or body.compress.size() < ai * 2 + 2:
		return -_lift
	var l: float = (float(body.compress[ai * 2]) - 0.45) * body.travel
	var r: float = (float(body.compress[ai * 2 + 1]) - 0.45) * body.travel
	return (l + r) * 0.5 + (r - l) * 0.5 * clampf(x / TW, -1.5, 1.5) - _lift


## A small moving part: built in its own node at `at`.
func _part(at: Vector3, build: Callable) -> Node3D:
	var n := Node3D.new()
	n.position = at
	var kk := MeshKit.new()
	build.call(kk)
	n.add_child(kk.instance("Part"))
	add_child(n)
	return n


## The wheels: built for the tyres on it now (set_tyres rebuilds them).
func _build_wheels() -> void:
	for w in _wheel_nodes:
		(w[0] as Node).queue_free()
	_wheel_nodes.clear()
	var t: Dictionary = TYRES[tyre_kind]
	_wr = float(t["r"])
	var width: float = t["w"]
	var tread: String = t["tread"]
	for wz in [FZ, RZ]:
		for wx in [-TW, TW]:
			var wn := Node3D.new()
			wn.position = Vector3(wx, _wr - _lift, wz)
			var sx := signf(wx)
			var rim := 0.203 if tread == "highway" else 0.19          # 16 in / 15 in rims
			# a real-looking wheel (DESIGN_NOTES 116): white 8-slot steel, locking hubs up front
			var wmi := MeshInstance3D.new()
			wmi.name = "Wheel"
			wmi.mesh = TyreMesh.wheel(_wr, width, rim, tread, "slot", sx, [0.0], "lock" if wz == FZ else "", Color(0.78, 0.79, 0.80))
			# the tyre squashes on the ground and bulges at the sidewall (shader)
			var tm := ShaderMaterial.new()
			tm.shader = TYRE_SQUASH
			tm.set_shader_parameter("radius", _wr)
			tm.set_shader_parameter("rim_r", rim)
			wmi.material_override = tm
			wn.add_child(wmi)
			add_child(wn)
			_wheel_nodes.append([wn, wz < 0.0])


## Put a set of tyres on (the body sits higher on bigger ones, grips as
## they do). Returns what it says.
func set_tyres(kind: String) -> void:
	if not TYRES.has(kind):
		return
	tyre_kind = kind
	_build_wheels()
	if _model != null:
		_model.position.y = _wr - MODEL_TYRE_R
	if body != null:
		body.wheel_r = _wr
		for i in range(body.wheels.size()):
			(body.wheels[i] as Array)[0] = Vector3((body.wheels[i] as Array)[0].x, _wr - _lift, (body.wheels[i] as Array)[0].z)
		_apply_grip()
		body.setup()


## Grip for the tyres on it, on what it's standing on now.
func _apply_grip() -> void:
	if body == null or terrain == null:
		return
	var t: Dictionary = TYRES[tyre_kind]
	var on_strip: bool = terrain.strip_index_at(global_position.x, global_position.z, 2.0) >= 0
	body.mu = 0.9 * float(t["mu_hard"] if on_strip else t["mu_dirt"])


## V in the cab: the headlights.
func lights_toggle() -> String:
	lights_on = not lights_on
	return "Headlights %s." % ("on" if lights_on else "off")


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


func park(xf: Transform3D) -> void:
	body = WheeledBody.new()
	body.mass_empty = 2900.0
	body.load_com = Vector3(0, 1.1, 1.8)
	body.com = Vector3(0, 0.78, -0.3)
	body.size = Vector3(2.0, 1.93, 5.85)
	body.hull_shape = _hull_shape()
	body.wheel_r = _wr
	body.travel = 0.22
	body.power = 220000.0
	body.top_speed = 30.0
	body.brake_force = 30000.0
	body.max_steer = 0.62
	for wz in [FZ, RZ]:
		for wx in [-TW, TW]:
			body.wheels.append([Vector3(wx, _wr - _lift, wz), wz < 0.0, true])
	body.ground_y = func(x: float, z: float) -> float: return terrain.wheel_ground(x, z) if terrain.has_method("wheel_ground") else terrain.height_at(x, z)
	body.blocked = func(p: Vector3) -> bool: return terrain.blocked_by_building(p, 1.0, self)
	body.setup()
	var o := xf.origin
	o.y = terrain.height_at(o.x, o.z) + 0.05
	body.place(Transform3D(xf.basis, o))
	body.settle()
	global_transform = body.transform()
	yaw = body.yaw()
	_apply_grip()


## The body's outline for the hull (ground contact when it's rolled or
## nosed in): bumper, hood, cab, bed / SUV top, rear bumper.
func _hull_shape() -> Array:
	var P: Dictionary = TruckBody.P
	if P.is_empty():
		return []
	var up := _wr - MODEL_TYRE_R + _lift
	var nz: float = P["nose_z"]
	var cw: float = P["cowl_z"]
	var cb: float = float(P["cab_back_z"])
	var tz: float = P["tail_z"]
	var roof: float = float(P["roof_y"]) + up
	var belt: float = float(P["rail_y"]) + up
	var hood: float = float(P["hood_y"]) + up
	var sh := [
		[nz - 0.22, nz, 0.98, 0.72 + up, 0.98],        # bumper
		[nz, cw, 1.0, hood, 0.92],           # hood and fenders
	]
	if TruckBody.suv():
		sh.append([cw, tz, 1.0, roof, 0.74])     # cab and top to the tail
	else:
		sh.append([cw, cb, 1.0, roof, 0.74])     # cab
		sh.append([cb + 0.03, tz, 1.0, belt, 0.98])        # bed rails
	sh.append([tz, tz + 0.18, 0.98, 0.70 + up, 0.98])  # rear bumper
	return sh


func eye_xf() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(-0.42, 1.73 + _wr - MODEL_TYRE_R, -0.3 + _drv_dz))


func step_out_point() -> Vector3:
	return global_transform * Vector3(-1.6, 0, -0.7 + _cab_dz)


func hitch_point() -> Vector3:
	return global_transform * HITCH


## One physics step while driven. Pulls whatever is on the hitch.
func drive(delta: float, move: Vector2, handbrake: bool = false) -> String:
	var msg := ""
	if not engine_on:
		if absf(move.y) > 0.1 and _told_off <= 0.0:
			_told_off = 4.0
			msg = "The engine's off: %s to start it." % Game.hint("engine_auto")
		move.y = 0.0
	_told_off -= delta
	var tow_all := 0.0
	if towing != null:
		tow_all = float(towing.total_mass()) if towing.has_method("total_mass") else float(towing.mass)
	var tow_kg := tow_all * 0.25
	# the bed, the trailer's share on the hitch, and the gas in the tank (2.8 kg a gallon)
	body.load_kg = (float(bed_load.call()) if bed_load.is_valid() else 0.0) + tow_kg + fuel_gal * 2.8
	# the trailer drags: more rolling resistance the heavier it is
	var thr := move.y
	if towing != null and absf(body.speed) > 0.2:
		thr -= signf(body.speed) * clampf(tow_all / 20000.0, 0.0, 0.25)
	_in = move
	body.step(delta, thr, move.x, handbrake)
	var fwd_v: float = body.vel.dot(-body.basis.z)
	_reversing = engine_on and fwd_v < -0.3
	_braking = engine_on and (handbrake or (move.y < -0.1 and fwd_v > 0.3))
	# off the gas: engine braking slows it, instead of coasting for ever
	if absf(move.y) < 0.05 and not handbrake:
		var sp: float = body.vel.dot(-body.basis.z)
		var dv := minf(absf(sp), 1.8 * delta)
		body.vel -= (-body.basis.z) * signf(sp) * dv
	global_transform = body.transform()
	yaw = body.yaw()
	if towing != null:
		towing.follow(hitch_point())
	var w := work(delta)
	return msg if msg != "" else w


## I in the cab: start or stop the engine.
func engine_toggle() -> String:
	if engine_on:
		engine_on = false
		esim.stop()
		return "Engine off."
	var said := esim.try_start(fuel_gal)
	engine_on = esim.running
	return said


func work(delta: float) -> String:
	var spd: float = absf(body.speed) if body != null else 0.0
	var msg := ""
	var thr: float = clampf(_in.y, 0.0, 1.0) if driven else 0.0
	if engine_on:
		# revs climb through each gear of whatever box is in and drop at the shift
		var idle := esim.idle_rpm()
		var red := esim.redline()
		var want := idle
		gear = 0
		var box: Dictionary = esim.pdef("transmission")
		var gears: Array = [0.0] + (box.get("gears", []) as Array)
		var drives: Array = esim.driven()
		if spd > 0.3 and gears.size() > 1 and (bool(drives[0]) or bool(drives[1])):
			var tk := esim.top_speed_k()
			var g := 1
			while g < gears.size() - 1 and spd > float(gears[g]) * tk:
				g += 1
			gear = g
			var lo: float = float(gears[g - 1]) * tk
			var hi: float = float(gears[g]) * tk
			want = lerpf(idle + 300.0, red * 0.82, clampf((spd - lo) / maxf(hi - lo, 0.1), 0.0, 1.0))
		else:
			want = idle + thr * (red * 0.75 - idle)          # in neutral (or nothing to drive) it just revs
		rpm = move_toward(rpm, want, 3000.0 * delta)
	esim.step(delta, thr if engine_on else 0.0, rpm, spd, 30.0 if lights_on else 0.0)
	if engine_on and not esim.running:
		engine_on = false
		msg = esim.last_fail
		esim.last_fail = ""
	elif esim.last_fail != "":
		msg = esim.last_fail
		esim.last_fail = ""
	rpm = esim.rpm if not engine_on else rpm
	coolant_f = esim.coolant_f
	oil_psi = esim.oil_psi
	volts = esim.volts
	if engine_on:
		fuel_gal = maxf(fuel_gal - esim.fuel_flow * esim.fuel_use_k / 2.84 * delta, 0.0)
		if fuel_gal <= 0.0:
			engine_on = false
			esim.stop()
			msg = "Out of gas: the engine dies."
	_apply_parts(delta)
	if body != null and driven:
		_apply_grip()
	_animate()
	_save_t += delta
	if _save_t > 10.0:
		_save_t = 0.0
		save()
		Parts.save_if_dirty()
	return msg


## The nearest tongue the ball could take, or null.
func tongue_near(r: float = 3.0) -> Node3D:
	if not towables.is_valid():
		return null
	var h := hitch_point()
	var best: Node3D = null
	var bd := r
	for t in towables.call():
		if t == null or not is_instance_valid(t) or t.towed_by != null:
			continue
		var tp: Vector3 = t.tongue_point()
		var d := Vector2(tp.x - h.x, tp.z - h.z).length()
		if d < bd and absf(tp.y - h.y) < 1.2:
			bd = d
			best = t
	return best


## The attach key in the cab: hitch what's behind you, or let it go.
func truck_action() -> String:
	if towing != null:
		if absf(body.speed) > 0.6:
			return "Stop before you unhitch."
		var t := towing
		towing = null
		t.towed_by = null
		t.settle()
		if t.has_method("set_folded"):
			t.set_folded(false)            # set up: legs down, sluices out
		save()
		if t.kind == "logtrailer":
			return "Unhitched the log trailer."
		return "Unhitched the %s: it sets up (legs down, sluices out) and is ready to work." % t.display_name()
	var tn := tongue_near()
	if tn == null:
		return "Nothing to hitch. Back up so the ball is within a few metres of a tongue (log trailer, sluice trailer, wash plant)."
	if absf(body.speed) > 0.6:
		return "Stop to hitch up."
	towing = tn
	tn.towed_by = self
	if tn.has_method("set_folded"):
		tn.set_folded(true)                # folds up for the road
	tn.follow(hitch_point())
	save()
	var tm: float = float(tn.total_mass()) if tn.has_method("total_mass") else float(tn.mass)
	if tn.kind == "logtrailer":
		return "Hitched the log trailer: %d kg behind you." % int(tm)
	return "Hitched the %s: it folds up for the road. Drive gently: %d kg behind you." % [tn.display_name(), int(tm)]


func prompt() -> String:
	if towing != null:
		return "%s  Unhitch the %s" % [Game.hint("interact"), towing.display_name()]
	var tn := tongue_near()
	if tn != null:
		return "%s  Hitch the %s" % [Game.hint("interact"), tn.display_name()]
	# Backing up to one: say where its tongue is from the ball (a reversing guide).
	var far := tongue_near(30.0)
	if far != null:
		var l: Vector3 = global_transform.affine_inverse() * far.tongue_point() - HITCH
		var d := Vector2(l.x, l.z).length()
		var fb := "behind" if l.z > 0.0 else "ahead"
		var side := ""
		if absf(l.x) > 0.4:
			side = ", %.1f m to the %s" % [absf(l.x), "right" if l.x > 0.0 else "left"]
		return "%s tongue %.1f m %s%s  (back the ball to it, then %s)" % [far.display_name().capitalize(), d, fb, side, Game.hint("interact")]
	return ""


func _animate() -> void:
	if body == null:
		return
	if _model != null:
		_model.position.y = _wr - MODEL_TYRE_R      # bigger tyres lift the whole truck
	for i in range(_wheel_nodes.size()):
		var wn: Node3D = _wheel_nodes[i][0]
		var front: bool = _wheel_nodes[i][1]
		var comp: float = body.compress[i] if i < body.compress.size() else 0.5
		wn.position.y = _wr - _lift + (comp - 0.45) * body.travel
		wn.rotation = Vector3(-float(body.wheel_spin[i]) if i < body.wheel_spin.size() else 0.0, body.steer if front else 0.0, 0)
		var wmi2 := wn.get_node_or_null("Wheel") as MeshInstance3D
		if wmi2 != null:
			# the tyre's flat spot: a couple of cm sat still, more as the spring loads up
			var sq := 0.016 + maxf(comp - 0.30, 0.0) * 0.06
			wmi2.set_instance_shader_parameter("squash", sq)
			wmi2.set_instance_shader_parameter("down_dir", -global_transform.basis.y)
	# the axles follow their wheels (down by the lift, and with the springs)
	for ai in range(2):
		var axn: Node3D = _axle_f if ai == 0 else _axle_r
		if axn == null:
			continue
		# up and down with both wheels, and rolled when one side is higher (articulation)
		var dl := _axle_dy(ai, -TW)
		var dr := _axle_dy(ai, TW)
		var piv := Vector3(0, TruckBody.AXLE_Y, FZ if ai == 0 else RZ)
		var rb := Basis(Vector3.BACK, asin(clampf((dr - dl) / (2.0 * TW), -0.5, 0.5)))
		axn.transform = Transform3D(rb, piv + Vector3(0, float(axn.get_meta("rest_y", 0.0)) + (dl + dr) * 0.5, 0) - rb * piv)
	# springs, shocks and the drag link follow the axle ends
	for ln in _links:
		var e: Array = (ln as Node).get_meta("ends")
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		if int(e[2]) >= 0:
			a.y += _axle_dy(int(e[2]), a.x)
		if int(e[3]) >= 0:
			b.y += _axle_dy(int(e[3]), b.x)
		TruckBody.place_link(ln, a, b)
	# the drive shafts turn 4.1 times for every turn of the wheels, and angle to
	# wherever their axle is now
	var spin: float = float(body.wheel_spin[2]) if body.wheel_spin.size() > 2 else 0.0
	for sh in _shafts:
		var e2: Array = (sh as Node).get_meta("ends")
		var b2: Vector3 = e2[1]
		b2.y += _axle_dy(int(e2[3]), b2.x)
		TruckBody.place_link(sh, e2[0], b2, spin * 4.1)
	# the steering wheel: about 3.5 turns lock to lock
	if _wheel_pivot != null:
		var rb: Basis = _wheel_pivot.get_meta("rest")
		_wheel_pivot.transform.basis = rb * Basis(Vector3.UP, body.steer / maxf(body.max_steer, 0.01) * PI * 3.5)
	# hood and tailgate swing on their hinges
	var dt := get_process_delta_time()
	_hood_a = move_toward(_hood_a, 1.05 if hood_open else 0.0, dt * 1.5)
	_gate_a = move_toward(_gate_a, PI * 0.5 if gate_open else 0.0, dt * 2.5)
	if _hood_pivot != null:
		_hood_pivot.transform.basis = (_hood_pivot.get_meta("rest") as Basis) * Basis(Vector3.RIGHT, _hood_a)
	if _gate_pivot != null:
		_gate_pivot.transform.basis = (_gate_pivot.get_meta("rest") as Basis) * Basis(Vector3.RIGHT, _gate_a)
	# fuel door: open it, then the cap unscrews (two turns, backing out) and
	# drops to hang on its tether, swinging; shut: the cap goes back first
	var door_want := fuel_open or _cap_t > 0.001
	_fuel_a = move_toward(_fuel_a, 1.7 if door_want else 0.0, dt * 4.0)
	if _fuel_pivot != null and is_instance_valid(_fuel_pivot):
		_fuel_pivot.transform.basis = (_fuel_pivot.get_meta("rest") as Basis) * Basis(Vector3.UP, -_fuel_a)
	if _cap_pivot != null and is_instance_valid(_cap_pivot):
		var cap_want := 1.0 if (fuel_open and _fuel_a > 1.3) else 0.0
		_cap_t = move_toward(_cap_t, cap_want, dt * 0.8)
		_cap_hang = _cap_hang + dt if _cap_t >= 0.999 else 0.0
		var out := Vector3(-1, 0, 0)                     # straight out of the left bed side
		var k1 := clampf(_cap_t / 0.6, 0.0, 1.0)
		var pos := _cap_center + out * (0.034 * k1)
		var bas := Basis(Vector3.RIGHT, -k1 * TAU * 2.0)  # unscrewing: anticlockwise, two turns
		if _cap_t > 0.6:
			var k2 := smoothstep(0.0, 1.0, (_cap_t - 0.6) / 0.4)
			var hang := _cap_tether + out * 0.035 + Vector3(0, -0.115, 0.01)
			var sway := sin(_cap_hang * 6.0) * exp(-_cap_hang * 1.2) * 0.35
			hang += Vector3(0, 0, sin(sway) * 0.10)
			pos = pos.lerp(hang, k2)
			bas = bas.slerp(Basis(Vector3.BACK, -1.2 * k2) * Basis(Vector3.RIGHT, sway), k2)
		_cap_pivot.transform = Transform3D((_cap_pivot.get_meta("rest") as Basis) * bas, pos)
		if _tether != null and is_instance_valid(_tether):
			_tether.visible = _cap_t > 0.05
			if _tether.visible:
				var a := _cap_tether
				var b := pos + out * 0.006 + Vector3(0, 0.02, 0)
				var mid := (a + b) * 0.5
				var d := b - a
				if d.length() > 0.002:
					_tether.transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT) * Basis.from_scale(Vector3(1, 1, d.length())), mid)
	# doors swing out on their front hinges, to about 65 degrees
	for di in range(_door_pivots.size()):
		var dp: Node3D = _door_pivots[di]
		if dp == null or not is_instance_valid(dp):
			continue
		_door_a[di] = move_toward(float(_door_a[di]), 1.13 if doors_open[di] else 0.0, dt * 2.2)
		var side: float = float(dp.get_meta("side", -1.0))
		dp.transform.basis = (dp.get_meta("rest") as Basis) * Basis(Vector3.UP, side * float(_door_a[di]))
	_update_lamps(dt)


## Where log `i` lies in the bed (world).
func log_xf(i: int) -> Transform3D:
	var tier := clampi(i / 4, 0, 1)
	var x := (float(i % 4) - 1.5) * 0.36
	return get_global_transform_interpolated() * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, BED_Y + float(tier) * 0.31, 1.75))


## Where a cargo piece sits in the bed (world).
func bed_xf(spot: int) -> Transform3D:
	var sp: Vector3 = BED_SPOTS[clampi(spot, 0, BED_SPOTS.size() - 1)]
	return get_global_transform_interpolated() * Transform3D(Basis.IDENTITY, sp)


## Standing at the tailgate or beside the bed?
func at_bed(p: Vector3) -> bool:
	var l := global_transform.affine_inverse() * p
	if absf(l.x) < 1.3 and l.z > 3.1 and l.z < 4.5:
		return true
	return absf(l.x) > 0.9 and absf(l.x) < 1.9 and l.z > 0.6 and l.z < 3.1


func status() -> String:
	return "Pickup %s: engine %s%s   %s   %s engine  %s lights  %s 4WD" % [DRIVE_NAMES[drive_mode], "on" if engine_on else "OFF", ("  towing the " + towing.display_name()) if towing != null else "", TYRES[tyre_kind]["name"], Game.hint("engine_auto"), Game.hint("lights"), Game.hint("four_wd")]


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("t", "xf", global_transform)
	cf.set_value("t", "towing", [towing.kind, towing.idx] if towing != null else [])
	cf.set_value("t", "fuel", fuel_gal)
	cf.set_value("t", "tyres", tyre_kind)
	cf.set_value("t", "pod", pod_wiring)
	cf.save(SAVE)


## Load the saved truck or park a new one by the hangar.
func load_or_default() -> Array:
	var cf := ConfigFile.new()
	var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(31.0, 0, -96.0))   # beside the water truck
	var tow: Array = []
	if cf.load(SAVE) == OK:
		xf = cf.get_value("t", "xf", xf)
		tow = cf.get_value("t", "towing", [])
		fuel_gal = float(cf.get_value("t", "fuel", 16.0))
		var pw: Array = cf.get_value("t", "pod", pod_wiring)
		if pw.size() == 3 and pw != pod_wiring:
			pod_wiring = pw
			_build_pod()
		var tk := String(cf.get_value("t", "tyres", tyre_kind))
		if TYRES.has(tk) and tk != tyre_kind:
			tyre_kind = tk
			_build_wheels()
	park(xf)
	return tow


# ------------------------------------------------------------------------------
#  Parts (DESIGN_NOTES 111)
# ------------------------------------------------------------------------------
## The physics gets what the parts make: power (scaled so the stock 350 drives
## as the truck always has), top speed from the gearing, which wheels are
## driven, and the weight of what's bolted in.
const STOCK_POWER_W := 220000.0
const STOCK_HP := 165.0
var _top_s := 30.0
## 0 = 2H (rear wheels), 1 = 4H, 2 = 4L (all four, low range: crawls, pulls hard)
var drive_mode := 0
var _lift := 0.0                 # suspension lift, m (parts)
const DRIVE_NAMES := ["2H", "4H", "4L"]


## 9 (right stick click): the selectable lockers in or out.
var lockers_on := false


func diff_lock_toggle() -> String:
	var lf := String(esim.pdef("locker_f").get("lock", ""))
	var lr := String(esim.pdef("locker_r").get("lock", ""))
	if lf != "select" and lr != "select":
		if lf == "auto" or lr == "auto":
			return "Automatic lockers: they lock by themselves, nothing to switch."
		return "Open diffs: no lockers fitted (the workshop sells them)."
	lockers_on = not lockers_on
	var which := "front and rear" if lf == "select" and lr == "select" else ("front" if lf == "select" else "rear")
	return "Lockers %s (%s)%s." % ["IN" if lockers_on else "out", which, ": both wheels on the axle pull together - hard to turn on firm ground" if lockers_on else ""]


## G (D-pad up): 2H -> 4H -> 4L. Needs the transfer case and the front shaft and axle.
func four_wd_toggle() -> String:
	var dr: Array = esim.driven()
	if not bool(dr[0]):
		drive_mode = 0
		return "No four-wheel drive: the transfer case, front driveshaft or front axle is missing."
	if drive_mode == 1 and absf(body.speed) > 2.0:
		return "Stop before you shift into 4L."
	drive_mode = (drive_mode + 1) % 3
	return {0: "2H: rear-wheel drive.", 1: "4H: all four wheels pulling.", 2: "4L: low range - slow, and it'll climb a wall."}[drive_mode]


func _apply_parts(delta: float) -> void:
	if body == null:
		return
	var k := STOCK_POWER_W / (STOCK_HP * 745.7)
	var low := 1.9 if drive_mode == 2 else 1.0
	body.power = maxf(esim.max_power_w * k * esim.pull_k() * low, 1000.0) if engine_on else 0.0
	var pot := maxf(esim.max_power_w, 1.0) / (STOCK_HP * 745.7)
	_top_s = lerpf(_top_s, 30.0 * esim.top_speed_k() * clampf(pow(pot, 0.33), 0.4, 1.6), clampf(0.5 * delta, 0.0, 1.0))
	body.top_speed = _top_s * (0.45 if drive_mode == 2 else 1.0)
	var dr: Array = esim.driven()
	for wi in range(body.wheels.size()):
		var w: Array = body.wheels[wi]
		w[2] = (bool(dr[0]) and drive_mode > 0) if (w[0] as Vector3).z < 0.0 else bool(dr[1])
	body.mass_empty = esim.mass_kg()
	# the diffs (DESIGN_NOTES 115): open unless there's a locker in, and a
	# selectable one only when it's switched on; the transfer case locks the axles together
	var lf := String(esim.pdef("locker_f").get("lock", ""))
	var lr := String(esim.pdef("locker_r").get("lock", ""))
	body.lock_inter = true
	body.lock_front = lf == "select" and lockers_on
	body.lock_rear = lr == "select" and lockers_on
	body.auto_front = lf == "auto"
	body.auto_rear = lr == "auto"
	# tyres and lift from the parts (DESIGN_NOTES 111)
	var td := esim.pdef("tyres")
	var want_tyre := String(td.get("tyre", tyre_kind))
	var want_lift := float(esim.pdef("lift").get("inches", 0)) * 0.0254
	if absf(want_lift - _lift) > 0.001:
		_lift = want_lift
		set_tyres(want_tyre)
		if _model != null:
			_build_shafts()
	elif want_tyre != tyre_kind:
		set_tyres(want_tyre)
	if td.is_empty():
		for w2 in body.wheels:
			(w2 as Array)[2] = false          # up on blocks: no tyres on it
	_update_part_visuals()


## New game, or a save from before the parts: the stock drivetrain.
func setup_parts() -> void:
	esim.key = "pickup"
	esim.tags = ["pickup", "v8"]
	if not Parts.fitted.has("pickup") or (Parts.fitted["pickup"] as Dictionary).is_empty():
		esim.fit_stock(Parts.PICKUP_STOCK)
	var f: Dictionary = Parts.fitted["pickup"]
	if not f.has("lift"):
		f["lift"] = Parts.make("lift_0", 1.0)
	if not f.has("tyres"):
		f["tyres"] = Parts.make("tyres_" + tyre_kind if Parts.CHASSIS.has("tyres_" + tyre_kind) else "tyres_lt235", 0.8)


## How big each part is to aim at (m): you're looking at it if your line of
## sight passes within this of its middle.
const PART_R := {"engine": 0.32, "heads": 0.16, "intake": 0.17, "fuel": 0.13, "fuel_pump": 0.12, "fuel_filter": 0.1,
	"turbo": 0.15, "intercooler": 0.2, "exhaust": 0.16, "radiator": 0.3, "alternator": 0.13, "battery": 0.18,
	"starter": 0.14, "transmission": 0.28, "transfer": 0.2, "driveshaft_f": 0.15, "driveshaft_r": 0.18, "diff_f": 0.26, "diff_r": 0.26}
var aimed_slot := ""              # the part you're looking at (its tag lights up)


## What you could do at the part you're looking at: [slot, prompt] or [].
## eye/dir: the camera ray; hand: the item id in your hand.
func part_target(eye: Vector3, dir: Vector3, hand: String, key: String) -> Array:
	var best := ""
	if body == null or absf(body.speed) <= 0.3:
		var best_s := 1.0
		for sl in PART_SPOTS.keys():
			var spot: Array = PART_SPOTS[sl]
			if bool(spot[1]) and not hood_open:
				continue
			var wp: Vector3 = global_transform * _spot(sl)
			var t := (wp - eye).dot(dir)
			if t < 0.15 or t > 2.8:
				continue
			# how near your line of sight passes to the part, for its size
			var sc := (eye + dir * t - wp).length() / float(PART_R.get(sl, 0.15))
			if sc < best_s:
				best_s = sc
				best = sl
	if best != aimed_slot:
		aimed_slot = best
		_parts_seen = ""
	if best == "":
		return []
	var have := esim.part(best)
	var hand_uid := Parts.uid_of_item(hand)
	var nm: String = Parts.SLOT_NAMES[best]
	var hand_slot := String(Parts.def_of(hand_uid).get("slot", "")) if hand_uid > 0 else ""
	if have > 0:
		if hand_uid > 0 and hand_slot == best:
			return [best, "%s  Swap the %s: %s  ->  %s" % [key, nm, Parts.label(have), Parts.label(hand_uid)]]
		if hand_uid > 0:
			return [best, "%s: %s (that's a %s in your hands)" % [nm.capitalize(), Parts.label(have), Parts.SLOT_NAMES.get(hand_slot, "part")]]
		return [best, "%s  Take off the %s: %s" % [key, nm, Parts.label(have)]]
	if hand_uid > 0:
		return [best, "%s  Fit the %s  (empty: %s)" % [key, Parts.def_of(hand_uid)["name"], nm]]
	return [best, "(No %s fitted)" % nm]


## Take off, fit or swap the part at `slot`. inv: the inventory (hand in/out).
## Heavy parts (over what you can carry) go on the ground beside the truck.
## Holding a part for a slot that's full swaps them: the new one goes in,
## the old one into your hands (or onto the ground if it's heavy).
func part_act(slot: String, inv: Node) -> String:
	if engine_on:
		engine_on = false                 # switch it off to work on it
	var have := esim.part(slot)
	var hand: String = inv.in_hand()
	var hand_uid := Parts.uid_of_item(hand)
	var s := esim.slots()
	if have > 0 and hand_uid > 0 and String(Parts.def_of(hand_uid).get("slot", "")) == slot:
		var trial := s.duplicate()
		trial.erase(slot)
		var why0 := Parts.fits(hand_uid, slot, esim.tags, trial)
		if why0 != "":
			return why0
		inv.remove(hand, 1)
		s[slot] = hand_uid
		Parts._dirty = true
		var oid := Parts.item_id(have)
		var okg := float(Parts.def_of(have)["kg"])
		var where := ""
		if okg <= inv.MAX_KG and inv.add(oid, 1, true) > 0:
			where = "the old one's in your hands"
		else:
			inv.place_in_world(oid, 1, global_transform * Vector3(-1.9, 0, _spot(slot).z), yaw)
			where = "the old one's on the ground beside the truck"
		Parts.save_all()
		parts_changed()
		return "Swapped in: %s (%s)." % [Parts.label(hand_uid), where]
	if have > 0:
		if hand_uid > 0 or (hand != "" and not hand.begins_with("part:")):
			return "Your hands are full (%s)." % inv.item_name(hand)
		for b in PART_BEFORE.get(slot, []):
			if esim.part(String(b)) > 0:
				return "The %s has to come off first." % Parts.SLOT_NAMES[b]
		s.erase(slot)
		Parts._dirty = true
		parts_changed()
		var id := Parts.item_id(have)
		var kg := float(Parts.def_of(have)["kg"])
		if kg <= inv.MAX_KG and inv.add(id, 1, true) > 0:
			return "Took off the %s. %s" % [Parts.SLOT_NAMES[slot], Parts.label(have)]
		var side := global_transform * Vector3(-1.9, 0, _spot(slot).z)
		inv.place_in_world(id, 1, side, yaw)
		return "Took off the %s (%.0f kg): it's on the ground beside the truck." % [Parts.SLOT_NAMES[slot], kg]
	var from_ground := {}
	if hand_uid <= 0:
		# heavy parts (an engine, an axle) are lifted in off the ground
		var spot_w: Vector3 = global_transform * _spot(slot)
		for e in inv.world_items:
			var u0 := Parts.uid_of_item(String(e["id"]))
			if u0 > 0 and String(Parts.def_of(u0).get("slot", "")) == slot and (e["xf"] as Transform3D).origin.distance_to(spot_w) < 4.5:
				from_ground = e
				hand_uid = u0
				break
	if hand_uid <= 0:
		return "Nothing to fit: hold the part in your hand (heavy parts: set them down beside the truck)."
	var why := Parts.fits(hand_uid, slot, esim.tags, s)
	if why != "":
		return why
	# what it bolts on to has to be there
	for b in PART_BEFORE.keys():
		if (PART_BEFORE[b] as Array).has(slot) and esim.part(String(b)) <= 0:
			return "Fit the %s first." % Parts.SLOT_NAMES[b]
	if from_ground.is_empty():
		inv.remove(hand, 1)
	else:
		if from_ground["node"] != null:
			(from_ground["node"] as Node).queue_free()
		inv.world_items.erase(from_ground)
		inv._dirty = true
	s[slot] = hand_uid
	Parts._dirty = true
	Parts.save_all()
	parts_changed()
	return "Fitted: %s." % Parts.label(hand_uid)


## The turbo where you can see it, and part tags under the open hood.
func _update_part_visuals() -> void:
	var t := esim.part("turbo")
	var key := "%d:%s:%s" % [t, str(hood_open), aimed_slot]
	if key == _parts_seen:
		return
	_parts_seen = key
	if _turbo_node != null:
		_turbo_node.queue_free()
		_turbo_node = null
	if t > 0 and _model != null:
		_turbo_node = Parts.build_mesh(t)
		_turbo_node.scale = Vector3.ONE * 1.2
		_model.add_child(_turbo_node)
		_turbo_node.position = _spot("turbo") + Vector3(0, -0.12, 0)
	if _tags_node != null:
		_tags_node.queue_free()
		_tags_node = null
	if hood_open and _model != null:
		_tags_node = Node3D.new()
		_model.add_child(_tags_node)
		for sl in PART_SPOTS.keys():
			if not bool(PART_SPOTS[sl][1]):
				continue
			var u := esim.part(sl)
			var lb := Label3D.new()
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.pixel_size = 0.0016
			lb.font_size = 22
			lb.outline_size = 6
			lb.no_depth_test = true
			var c := Parts.cond(u) if u > 0 else 0.0
			lb.text = ("%s %d%%" % [String(Parts.SLOT_NAMES[sl]).get_slice(" ", 0), int(round(c * 100.0))]) if u > 0 else "%s: empty" % String(Parts.SLOT_NAMES[sl]).get_slice(" ", 0)
			lb.modulate = Color(0.4, 0.95, 0.4) if c > 0.6 else (Color(1.0, 0.85, 0.3) if c > 0.25 else Color(1.0, 0.35, 0.3))
			if u <= 0:
				lb.modulate = Color(0.7, 0.7, 0.7)
			lb.position = _spot(sl)
			if sl == aimed_slot:
				lb.font_size = 34
				lb.modulate = Color(1, 1, 1)
				lb.outline_modulate = Color(0.9, 0.5, 0.1)
				lb.text = "> " + lb.text + " <"
			else:
				lb.modulate.a = 0.55
			_tags_node.add_child(lb)


## Refresh the tags (a part's condition changed, something swapped).
func parts_changed() -> void:
	_parts_seen = ""


## Where a winch hook or tow strap can go (DESIGN_NOTES 225): the two J hooks
## on the front bumper, the hitch ball at the back.
func winch_points() -> Array:
	if not is_inside_tree():
		return []
	var nz: float = float(TruckBody.P.get("nose_z", -2.47))
	var dy: float = _wr - MODEL_TYRE_R
	return [
		["front left tow hook", global_transform * Vector3(-0.42, 0.49 + dy, nz - 0.06)],
		["front right tow hook", global_transform * Vector3(0.42, 0.49 + dy, nz - 0.06)],
		["hitch ball", hitch_point()],
	]
