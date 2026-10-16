extends Node3D
## A small yard forklift (about 2.5 t), parked at the hangar towns and the
## mines. Get on it (interact), drive it with the walk keys, raise and lower
## the forks (run / throttle-down keys, or the mouse wheel), pick pallets up off
## the ground, set them down, and load them in and out of the DC-3's cargo door:
## lift the forks to the door sill, nose up to the door, interact.

const MeshKit = preload("res://scripts/meshkit.gd")
const EK = preload("res://scripts/equip_kit.gd")
const Shape = preload("res://scripts/dc3_shape.gd")

const YELLOW := Color(0.92, 0.68, 0.08)
const BLACK := Color(0.08, 0.08, 0.08)
const STEEL := Color(0.45, 0.46, 0.48)
const MAX_SPEED := 4.2         # m/s forward, about 15 km/h
const MAX_LIFT := 3.0          # fork height, m
const WHEELBASE := 1.6
const FORK_Z := -1.55          # middle of the forks, ahead of the machine

var terrain: RefCounted
var jobs: Node
var plane: Node3D
var yaw := 0.0
var speed := 0.0
var mud_now := 0.0           # mud under it (vehicle_dust.gd: spray and muck)
var spin_now := 0.0
var steer := 0.0
var lift := 0.08
var carrying: Dictionary = {}    # the piece on the forks
var carrying_job: Dictionary = {}
var driven := false
var home := Transform3D.IDENTITY
var _carriage: Node3D
var _mast: Node3D
var _mast_off: Node3D
var mast_tilt := 0.0                # + leans the mast back (load toward the machine), - forward
const TILT_BACK := 0.14
const TILT_FWD := -0.09
const MAST_PIVOT := Vector3(0, 0.32, -0.78)    # the mast's foot pins on the drive axle
const TILT_BASE := Vector3(0, 0.62, -0.42)     # tilt rams' base pins under the floor (x each side)
const TILT_ROD := Vector3(0, 1.0, -0.8)        # their rod pins on the mast rails
const LIFT_BASE_Y := 0.24                      # lift cylinders' foot on the outer mast's bottom tie
const LIFT_TOP_Y := 2.0                        # their rods' clevis under the inner mast's top tie
var _inner_mast: Node3D
var _wheels: Array = []
var _roll := 0.0


## A 2.5 t counterbalance yard truck, built from pictures of the real ones
## (DESIGN_NOTES 152): 1.6 m wheelbase, big front drive tyres under fenders,
## small steer tyres tucked in under a rounded counterweight casting, the
## engine hood as the seat base, a slanted overhead guard, a propane bottle
## across the back, a two-stage mast with tilt rams, lift rams and chains,
## and a carriage with a load backrest and two L-forks.
var _seat_at := Vector3.ZERO
var seat: Node3D


## The lab and the cab: click the seat's air valve (and whatever else gets a control).
func control_click(nm: String) -> String:
	if nm == "seat_air" and seat != null:
		return seat.air()
	return ""


func build() -> void:
	var body := MeshKit.new()
	var dark := Color(0.16, 0.16, 0.17)
	var cwc := YELLOW.darkened(0.06)
	# chassis between the front tyres
	body.box_at(Vector3(0, 0.42, 0.05), Vector3(0.74, 0.4, 1.6), YELLOW.darkened(0.25))
	# hood over the engine (the seat sits on it), rounded at the top edges
	_side_loft(body, [Vector2(-0.2, 0.6), Vector2(0.86, 0.6), Vector2(0.86, 1.02), Vector2(0.8, 1.07), Vector2(-0.14, 1.07), Vector2(-0.2, 1.02)], 0.55, YELLOW)
	body.box_at(Vector3(0, 1.075, 0.32), Vector3(0.8, 0.012, 0.9), YELLOW.darkened(0.15))     # hood seam
	for vx in [-0.556, 0.556]:
		for vi in range(4):
			body.box_at(Vector3(vx, 0.82, 0.25 + 0.12 * float(vi)), Vector3(0.01, 0.05, 0.08), dark)   # side vents
	# counterweight casting, rounded at the back, over the steer tyres
	_side_loft(body, [Vector2(0.8, 0.56), Vector2(1.5, 0.56), Vector2(1.6, 0.66), Vector2(1.62, 0.9), Vector2(1.55, 1.1), Vector2(1.42, 1.2), Vector2(1.2, 1.24), Vector2(0.8, 1.24)], 0.57, cwc)
	_side_loft(body, [Vector2(1.44, 0.28), Vector2(1.58, 0.3), Vector2(1.6, 0.56), Vector2(1.44, 0.56)], 0.57, cwc)   # back skirt
	body.box_at(Vector3(0, 0.42, 1.6), Vector3(0.16, 0.12, 0.06), dark)        # tow pin pocket
	body.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.36, 1.6)), 0.025, 0.025, 0.22, 6, STEEL)
	var lm := MeshKit.new()
	for lx in [-0.42, 0.42]:
		EK.lamp(body, lm, self, Vector3(lx, 0.98, 1.615), Vector3(0, 0, 1), 0.1, 0.1, Color(0.85, 0.08, 0.05), true)   # tail lamps
		EK.lamp(body, lm, self, Vector3(lx * 0.7, 0.98, 1.615), Vector3(0, 0, 1), 0.07, 0.07, Color(1.0, 0.6, 0.1), true)
	EK.hazard(body, Vector3(-0.5, 0.62, 1.605), Vector3(0.5, 0.62, 1.605), Vector3(0.5, 0.78, 1.605), Vector3(-0.5, 0.78, 1.605), Vector3(0, 0, 1), 10)
	for dx in [-1.0, 1.0]:
		EK.decal(self, "F-50", Vector3(dx * 0.575, 1.05, 1.2), Vector3(dx, 0, 0), 0.0022, Color(0.08, 0.08, 0.08))
		EK.decal(self, "CAPACITY\n5000 LB\n24 IN LOAD CTR", Vector3(dx * 0.557, 0.86, 0.12), Vector3(dx, 0, 0), 0.0007, Color(0.05, 0.05, 0.05), Color(0.92, 0.92, 0.88), body, 0.16, 0.1)
		EK.bolts(lm, Vector3(dx * 0.576, 0.6, 0.85), Vector3(dx * 0.576, 0.6, 1.45), 5, Vector3(dx, 0, 0), 0.014)
	EK.mirror(body, Vector3(-0.53, 1.6, -0.75), Vector3(-0.68, 1.7, -0.8))
	# front fenders: an arch of plate over each drive tyre
	for fx in [-1.0, 1.0]:
		for k in range(7):
			var a0 := PI * float(k) / 7.0
			var a1 := PI * float(k + 1) / 7.0
			var c0 := Vector3(fx * 0.5, 0.34 + 0.4 * sin(a0), -0.45 - 0.4 * cos(a0))
			var c1 := Vector3(fx * 0.5, 0.34 + 0.4 * sin(a1), -0.45 - 0.4 * cos(a1))
			_plate(body, c0, c1, 0.27, 0.03, YELLOW)
	# floor plate, side step, the dash cowl
	body.box_at(Vector3(0, 0.62, -0.47), Vector3(0.74, 0.04, 0.6), dark)
	body.box_at(Vector3(-0.47, 0.38, -0.02), Vector3(0.2, 0.03, 0.26), dark)
	_side_loft(body, [Vector2(-0.82, 0.6), Vector2(-0.6, 0.6), Vector2(-0.56, 1.06), Vector2(-0.66, 1.14), Vector2(-0.82, 1.08)], 0.42, YELLOW)
	body.box_at(Vector3(0, 1.1, -0.6), Vector3(0.5, 0.05, 0.1), dark)              # gauge strip
	body.box_at(Vector3(-0.12, 1.12, -0.59), Vector3(0.09, 0.05, 0.02), Color(0.3, 0.55, 0.35))
	# steering column, wheel and spinner knob
	body.cylinder(Transform3D(Basis(Vector3.RIGHT, 0.75), Vector3(0, 1.02, -0.58)), 0.035, 0.03, 0.34, 8, dark)
	var wb := Basis(Vector3.RIGHT, 0.75)
	for k in range(14):
		var t0 := TAU * float(k) / 14.0
		var t1 := TAU * float(k + 1) / 14.0
		var wc := Vector3(0, 1.27, -0.34)
		_plate(body, wc + wb * Vector3(cos(t0) * 0.18, 0, sin(t0) * 0.18), wc + wb * Vector3(cos(t1) * 0.18, 0, sin(t1) * 0.18), 0.025, 0.025, BLACK)
	body.cylinder(Transform3D(wb, Vector3(0, 1.26, -0.35)), 0.04, 0.04, 0.03, 8, BLACK)
	body.cylinder(Transform3D(wb, Vector3(0.13, 1.28, -0.33)), 0.018, 0.018, 0.08, 6, Color(0.75, 0.12, 0.08))
	# the hydraulic levers by the right hand: lift, tilt, side shift
	for li in range(3):
		var lx2 := 0.22 + 0.07 * float(li)
		body.cylinder(Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(lx2, 1.08, -0.6)), 0.01, 0.01, 0.24, 6, dark)
		body.box_at(Vector3(lx2, 1.31, -0.66), Vector3(0.035, 0.06, 0.035), Color(0.1, 0.1, 0.1) if li > 0 else Color(0.75, 0.12, 0.08))
	# the seat with hip wings
	_seat_at = Vector3(0, 1.08, 0.36)
	# overhead guard: front posts lean forward, rear posts stand on the counterweight
	for gx in [-0.53, 0.53]:
		_plate(body, Vector3(gx, 0.98, -0.62), Vector3(gx, 2.09, -0.5), 0.06, 0.06, BLACK)   # (behind the mast, so it can tilt back clear)
		_plate(body, Vector3(gx, 1.22, 1.0), Vector3(gx, 2.09, 1.0), 0.06, 0.06, BLACK)
		body.box_at(Vector3(gx, 2.1, 0.25), Vector3(0.07, 0.07, 1.56), BLACK)
	for cz in [-0.5, 1.0]:
		body.box_at(Vector3(0, 2.1, cz), Vector3(1.12, 0.07, 0.07), BLACK)
	for sx2 in range(6):
		body.box_at(Vector3(-0.375 + 0.15 * float(sx2), 2.11, 0.25), Vector3(0.05, 0.03, 1.5), BLACK)
	for lx3 in [-0.5, 0.5]:
		EK.lamp(body, lm, self, Vector3(lx3, 2.02, -0.58), Vector3(0, -0.15, -1), 0.12, 0.09, Color(1, 0.97, 0.85))   # work lamps, on the guard's front bar
	EK.beacon(body, self, Vector3(0.3, 2.14, 0.9))
	# propane bottle across the back, on its bracket
	var tb := Basis(Vector3.FORWARD, PI * 0.5)
	body.cylinder(Transform3D(tb, Vector3(-0.38, 1.42, 1.22)), 0.16, 0.16, 0.76, 14, Color(0.82, 0.83, 0.8))
	body.cylinder(Transform3D(tb, Vector3(-0.42, 1.42, 1.22)), 0.12, 0.155, 0.04, 14, Color(0.82, 0.83, 0.8))
	body.cylinder(Transform3D(tb, Vector3(0.38, 1.42, 1.22)), 0.155, 0.12, 0.04, 14, Color(0.82, 0.83, 0.8))
	body.cylinder(Transform3D(tb, Vector3(0.42, 1.42, 1.22)), 0.04, 0.04, 0.06, 8, STEEL)
	for bx in [-0.25, 0.25]:
		body.box_at(Vector3(bx, 1.38, 1.22), Vector3(0.04, 0.3, 0.36), dark)
		body.box_at(Vector3(bx, 1.585, 1.22), Vector3(0.03, 0.02, 0.3), dark)
	# the tilt rams' base clevises under the front of the floor plate
	for tx in [-0.3, 0.3]:
		EK.lug(body, Vector3(tx, TILT_BASE.y, TILT_BASE.z), 0.035, 0.025, 0.06, Vector3(0, 0.2, 1), 0.12, YELLOW.darkened(0.3))
	# the mast's pivot brackets on the drive axle housing
	for px in [-0.33, 0.33]:
		EK.lug(body, Vector3(px, MAST_PIVOT.y, MAST_PIVOT.z), 0.05, 0.03, 0.09, Vector3(0, 0, 1), 0.16, dark)
	var bm := body.instance("Forklift")
	add_child(bm)
	var lmi := lm.instance("ForkliftMetal")
	lmi.material_override = EK.metal_mat()
	add_child(lmi)
	# The mast tilts on its pins at the bottom (Dave: every cylinder works): the
	# outer mast, the inner mast and the carriage all ride on _mast_off, which
	# tilts about MAST_PIVOT; the tilt rams push it from the frame.
	_mast = Node3D.new()
	_mast.name = "Mast"
	_mast.position = MAST_PIVOT
	add_child(_mast)
	_mast_off = Node3D.new()
	_mast_off.position = -MAST_PIVOT
	_mast.add_child(_mast_off)
	var om := MeshKit.new()
	for mx in [-0.37, 0.37]:
		om.box_at(Vector3(mx, 1.1, -0.88), Vector3(0.09, 2.0, 0.14), STEEL.darkened(0.25))
		om.box_at(Vector3(mx - signf(mx) * 0.04, 1.1, -0.88), Vector3(0.01, 2.0, 0.13), dark)
		EK.pin(om, Vector3(signf(mx) * 0.33, MAST_PIVOT.y, MAST_PIVOT.z), 0.025, 0.05, dark)            # the mast's foot boss on its pin
		EK.lug(om, Vector3(signf(mx) * 0.3, TILT_ROD.y, TILT_ROD.z), 0.035, 0.025, 0.06, Vector3(0, 0, -1), 0.06, STEEL.darkened(0.25))   # tilt ram's rod clevis on the rail
		EK.lug(om, Vector3(mx * 0.62, LIFT_BASE_Y, -0.8), 0.04, 0.025, 0.065, Vector3(0, -1, 0), 0.05, STEEL.darkened(0.25))           # lift cylinder's foot on the bottom tie
	for my in [0.18, 1.1, 2.06]:
		om.box_at(Vector3(0, my, -0.86), Vector3(0.82, 0.07, 0.07), STEEL.darkened(0.25))
	_mast_off.add_child(om.instance("OuterMast"))
	# Inner mast rises half as far as the forks (the chains over its sheaves
	# double it): rails, top tie, chain sheaves.
	_inner_mast = Node3D.new()
	var im := MeshKit.new()
	for mx in [-0.29, 0.29]:
		im.box_at(Vector3(mx, 1.06, -0.93), Vector3(0.07, 1.96, 0.1), STEEL.darkened(0.1))
		im.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(mx * 0.62 - 0.03, 2.0, -0.95)), 0.06, 0.06, 0.05, 10, dark)
		im.box_at(Vector3(mx * 0.62, 1.42, -0.97), Vector3(0.03, 1.2, 0.02), Color(0.12, 0.12, 0.12))   # chain
	im.box_at(Vector3(0, 2.02, -0.93), Vector3(0.66, 0.06, 0.08), STEEL.darkened(0.1))
	im.box_at(Vector3(0, 0.12, -0.93), Vector3(0.66, 0.06, 0.08), STEEL.darkened(0.1))
	for mx2 in [-0.37, 0.37]:
		EK.lug(im, Vector3(mx2 * 0.62, LIFT_TOP_Y, -0.8), 0.035, 0.025, 0.05, Vector3(0, 1, 0), 0.05, STEEL.darkened(0.1))   # lift rod's clevis under the top tie
	_inner_mast.add_child(im.instance("InnerMast"))
	_mast_off.add_child(_inner_mast)
	# Carriage: fork bars, load backrest, two L-forks with tapered tips.
	_carriage = Node3D.new()
	var ck := MeshKit.new()
	ck.box_at(Vector3(0, 0.12, -1.0), Vector3(1.0, 0.1, 0.06), dark)
	ck.box_at(Vector3(0, 0.46, -1.0), Vector3(1.0, 0.1, 0.06), dark)
	for px2 in [-0.2, 0.2]:
		ck.box_at(Vector3(px2, 0.3, -0.97), Vector3(0.06, 0.4, 0.04), dark)
	ck.box_at(Vector3(0, 1.22, -1.0), Vector3(1.0, 0.05, 0.04), BLACK)
	for gx2 in range(7):
		ck.box_at(Vector3(-0.45 + 0.15 * float(gx2), 0.86, -1.0), Vector3(0.035, 0.72, 0.035), BLACK)
	for sx3 in [-0.5, 0.5]:
		ck.box_at(Vector3(sx3, 0.86, -1.0), Vector3(0.05, 0.72, 0.05), BLACK)
	for fx2 in [-0.3, 0.3]:
		var fk := STEEL.darkened(0.35)
		ck.box_at(Vector3(fx2, 0.3, -1.055), Vector3(0.1, 0.56, 0.045), fk)        # shank
		ck.box_at(Vector3(fx2, 0.52, -1.02), Vector3(0.11, 0.06, 0.06), fk)        # hook on the top bar
		ck.loft([
			PackedVector3Array([Vector3(fx2 - 0.05, 0.0, -1.03), Vector3(fx2 + 0.05, 0.0, -1.03), Vector3(fx2 + 0.05, 0.045, -1.03), Vector3(fx2 - 0.05, 0.045, -1.03)]),
			PackedVector3Array([Vector3(fx2 - 0.05, 0.0, -1.95), Vector3(fx2 + 0.05, 0.0, -1.95), Vector3(fx2 + 0.05, 0.04, -1.95), Vector3(fx2 - 0.05, 0.04, -1.95)]),
			PackedVector3Array([Vector3(fx2 - 0.045, 0.0, -2.1), Vector3(fx2 + 0.045, 0.0, -2.1), Vector3(fx2 + 0.045, 0.012, -2.1), Vector3(fx2 - 0.045, 0.012, -2.1)]),
		], fk)
	_carriage.add_child(ck.instance("Forks"))
	_mast_off.add_child(_carriage)
	# the cylinders, working: two tilt rams frame to mast, two lift cylinders
	# from the outer mast's foot to the inner mast's top
	var Ram = ResourceLoader.load("res://scripts/hyd_ram.gd", "", ResourceLoader.CACHE_MODE_REPLACE)
	for tx2 in [-0.3, 0.3]:
		var tr = Ram.new()
		add_child(tr)
		tr.setup(self, Vector3(tx2, TILT_BASE.y, TILT_BASE.z), _mast_off, Vector3(tx2, TILT_ROD.y, TILT_ROD.z), 0.045, YELLOW.darkened(0.3), 0.3)
		tr.plumb(self, self, Vector3(tx2 * 0.5, 0.62, -0.2), 0.012, [Vector3(tx2, 0.62, -0.3)])
	for lx2 in [-0.37, 0.37]:
		var lr = Ram.new()
		_mast_off.add_child(lr)
		lr.setup(_mast_off, Vector3(lx2 * 0.62, LIFT_BASE_Y, -0.8), _inner_mast, Vector3(lx2 * 0.62, LIFT_TOP_Y, -0.8), 0.05, STEEL.darkened(0.3), LIFT_TOP_Y - LIFT_BASE_Y)
	_apply_pose()
	# Wheels: big pneumatic drive tyres in front, small steer tyres under the counterweight.
	for w in [[-0.5, -0.45, 0.34, 0.24], [0.5, -0.45, 0.34, 0.24], [-0.42, 1.15, 0.27, 0.18], [0.42, 1.15, 0.27, 0.18]]:
		var wn := Node3D.new()
		var wmi := MeshInstance3D.new()
		wmi.mesh = load("res://scripts/tyre_mesh.gd").wheel(float(w[2]), float(w[3]), float(w[2]) * 0.55, "lug", "disc", signf(float(w[0])), [0.0], "", YELLOW.darkened(0.2))
		wmi.material_override = MeshKit.material()
		wn.add_child(wmi)
		wn.position = Vector3(float(w[0]), float(w[2]), float(w[1]))
		add_child(wn)
		_wheels.append([wn, float(w[2]), float(w[1]) > 0.0])
	EK.dust_all(self, 0.4, 0.6)
	seat = EK.air_seat(self, _seat_at, 0.0)
	EK.add_collision(self)
	_apply_pose()


## A profile in the side plane (z, y) pushed out to +-hw across.
static func _side_loft(kit: RefCounted, pts: Array, hw: float, col: Color) -> void:
	var ra := PackedVector3Array()
	var rb := PackedVector3Array()
	for q in pts:
		var v: Vector2 = q
		ra.append(Vector3(-hw, v.y, v.x))
		rb.append(Vector3(hw, v.y, v.x))
	kit.loft([ra, rb], col, true, true)


## A flat bar from a to b, `w` wide (across x or the side), `t` thick.
static func _plate(kit: RefCounted, a: Vector3, b: Vector3, w: float, t: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var z := d.normalized()
	var x := Vector3.RIGHT if absf(z.x) < 0.9 else Vector3.UP
	var y := z.cross(x).normalized()
	x = y.cross(z).normalized()
	kit.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, t, d.length()), col)


func park(xf: Transform3D) -> void:
	home = xf
	var f := -xf.basis.z
	yaw = atan2(-f.x, -f.z)
	global_position = xf.origin
	speed = 0.0
	_settle()


## Back where it was parked (a new flight, or it was left somewhere silly).
func go_home() -> void:
	if carrying.is_empty():
		park(home)


func _settle() -> void:
	var p := global_position
	p.y = terrain.ground_level_at(p.x, p.z)
	var n: Vector3 = terrain.ground_normal_at(p.x, p.z)
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var right := fwd.cross(n).normalized()
	global_transform = Transform3D(Basis(right, n, -fwd), p)


var _demo_t := 0.0
func _process(delta: float) -> void:
	if driven or not EK.in_lab(self):
		return
	# in the lab: works the lift and tilt levers so the mast and its cylinders can be watched
	_demo_t += delta
	lift = 0.05 + (MAX_LIFT - 0.1) * (0.5 - 0.5 * cos(_demo_t * 0.35))
	mast_tilt = 0.11 * sin(_demo_t * 0.5) + 0.03         # 8 deg back .. 5 deg forward
	_apply_pose()


func _apply_pose() -> void:
	if _mast == null:
		return
	_mast.rotation.x = mast_tilt
	_carriage.position = Vector3(0, lift, 0)
	_inner_mast.position = Vector3(0, lift * 0.5, 0)      # the chains: the forks go twice as far as the inner mast
	for w in _wheels:
		var wn: Node3D = w[0]
		wn.rotation = Vector3(_roll / float(w[1]), (-steer * 0.6) if bool(w[2]) else 0.0, 0)


## Where the driver's eyes are.
func eye_xf() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.98, 0.42))


## Where a carried pallet sits: on the forks.
func load_xf() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0, lift + 0.045, FORK_Z))


## Middle of the forks in the world.
func fork_point() -> Vector3:
	return global_transform * Vector3(0, lift, FORK_Z)


## One step of driving: move.y forward (+) / back, move.x steer right (+), lift_in up (+) / down.
func drive(delta: float, move: Vector2, lift_in: float) -> void:
	var want := move.y * MAX_SPEED * (0.6 if move.y < 0.0 else 1.0)
	if not carrying.is_empty():
		want *= 0.7
	# Mud (DESIGN_NOTES 109): little solid tyres made for a hangar floor - it
	# bogs in anything soft and won't get out of the deep stuff on its own.
	var gp := global_position
	mud_now = float(terrain.mud_at(gp.x, gp.z)) if terrain.has_method("mud_at") else 0.0
	# (It used to stop dead from mud 0.75: after rain the whole yard was that
	# wet and it wouldn't move at all. Now it crawls, it never sticks fast.)
	want *= lerpf(1.0, 0.3, smoothstep(0.25, 0.9, mud_now))
	spin_now = smoothstep(0.5, 0.9, mud_now) * clampf(absf(move.y), 0.0, 1.0)
	speed = move_toward(speed, want, (2.2 if absf(want) > absf(speed) else 4.0) * delta)
	steer = move_toward(steer, move.x, 2.5 * delta)
	lift = clampf(lift + lift_in * 0.45 * delta, 0.03, MAX_LIFT)
	# Rear-wheel steering: it swings its tail round.
	yaw -= speed * tan(steer * 0.7) / WHEELBASE * delta
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var p := global_position + fwd * speed * delta
	# Keep out of the plane's way: the fuselage and the wings are solid enough.
	if plane != null and _hits_plane(p):
		speed = 0.0
		p = global_position
	# And out of the walls (the hangar doorway is open).
	var fwd2 := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var probe := fwd2 * (1.6 if speed >= 0.0 else -1.6) + Vector3(0, 0.6, 0)
	# already nosed into something (parked against it, or a building put up
	# round it): let it drive out rather than pinning it there for good
	if terrain.blocked_by_building(p + probe, 0.7, self) and not terrain.blocked_by_building(global_position + probe, 0.7, self):
		speed = 0.0
		p = global_position
	global_position = p
	_roll += speed * delta
	_settle()
	_apply_pose()


func _hits_plane(p: Vector3) -> bool:
	var inv: Transform3D = plane.global_transform.affine_inverse()
	for off in [Vector3(0, 0.5, -0.9), Vector3(0, 0.5, 1.2), Vector3(0, lift + 0.3, FORK_Z - 0.5)]:
		var w: Vector3 = Transform3D(Basis(Vector3.UP, yaw), p) * (off as Vector3)
		var l: Vector3 = inv * w
		if plane.plane_type == "dc3":
			if l.z > -7.5 and l.z < 11.5:
				var hw := Shape.inner_half_width(l.z, l.y) + 0.06
				if hw > 0.05 and absf(l.x) < hw:
					# The open cargo door lets the forks in a little way.
					var at_door: bool = plane.door_open.get("bay", false) and l.x < 0.0 and l.z > Shape.DOOR_Z[0] + 0.1 and l.z < Shape.DOOR_Z[1] - 0.1 and l.y > -0.95 and l.y < 0.84 and absf(l.x) > hw - 0.5
					if not at_door:
						return true
		else:
			if l.z > -2.2 and l.z < 5.0 and absf(l.x) < 0.65 and l.y > -0.9 and l.y < 1.0:
				return true
	return false


# ------------------------------------------------------------------------------
#  The forks: pick up, set down, in and out of the DC-3
# ------------------------------------------------------------------------------
## What interact would do now: [action, text] or [].
func fork_target() -> Array:
	var fp := fork_point()
	if carrying.is_empty():
		# Out of the DC-3's door?
		if _at_door(fp):
			var rp: Array = jobs.pallet_rearmost()
			if not rp.is_empty():
				return ["unload", "Pull the pallet out of the door (%d kg)" % int((rp[1] as Dictionary)["kg"])]
		var pc := _pallet_near(fp)
		if not pc.is_empty():
			if lift > 0.3:
				return ["", "Lower the forks to get under the pallet"]
			return ["lift", "Lift the pallet (%d kg)" % int((pc[1] as Dictionary)["kg"])]
		return []
	if _at_door(fp):
		var slot: int = jobs.pallet_free_slot()
		if slot < 0:
			return ["", "No room: the cabin floor is full of pallets"]
		if not jobs.fits(jobs.pallet_compartment(slot), float(carrying["kg"])):
			return ["", "Too heavy for the DC-3 with what's aboard"]
		return ["load", "Push the pallet in through the cargo door"]
	if plane != null and plane.plane_type == "dc3" and _near_door_low(fp):
		return ["", "Raise the forks to the door sill (%.1f m)" % _sill_height()]
	if lift > 0.6:
		return ["", "Lower the forks to set it down"]
	return ["drop", "Set the pallet down here"]


func fork_action() -> String:
	var t := fork_target()
	if t.is_empty() or t[0] == "":
		return ""
	var fp := fork_point()
	match String(t[0]):
		"lift":
			var pc := _pallet_near(fp)
			carrying_job = pc[0]
			carrying = pc[1]
			jobs.move_piece(carrying_job, carrying, "forks")
			lift = maxf(lift, 0.15)
			return "Pallet on the forks."
		"drop":
			var g := fp
			g.y = terrain.ground_level_at(g.x, g.z)
			var st: int = terrain.strip_index_at(g.x, g.z, 90.0)
			var job := carrying_job
			var pc2 := carrying
			carrying = {}
			carrying_job = {}
			jobs.move_piece(job, pc2, "dropped", g, st)
			return "Set down." if int(job.get("to", -1)) != st else "Set down at its destination."
		"load":
			var slot: int = jobs.pallet_free_slot()
			carrying["slot"] = slot
			var job2 := carrying_job
			var pc3 := carrying
			carrying = {}
			carrying_job = {}
			jobs.move_piece(job2, pc3, jobs.pallet_compartment(slot))
			return "In it goes, and rolls forward on the floor rollers to station %d." % (slot + 1)
		"unload":
			var rp: Array = jobs.pallet_rearmost()
			carrying_job = rp[0]
			carrying = rp[1]
			carrying.erase("slot")
			jobs.move_piece(carrying_job, carrying, "forks")
			return "Pallet out on the forks."
	return ""


func _pallet_near(fp: Vector3) -> Array:
	var best := 0.75
	var out: Array = []
	for j in jobs.carried:
		if String(j.get("kind", "")) != "pallet":
			continue
		for pc in j.get("pieces", []):
			if pc["at"] != "ramp" and pc["at"] != "dropped":
				continue
			var q: Vector3 = (pc["pos"] as Vector3) + Vector3(0, 0, 0)
			var d := Vector2(q.x - fp.x, q.z - fp.z).length()
			if d < best:
				best = d
				out = [j, pc]
	return out


func _sill_height() -> float:
	var sill: Vector3 = plane.global_transform * Vector3(-1.3, Shape.cabin_floor(3.2), 3.2)
	return sill.y - terrain.ground_level_at(sill.x, sill.z)


## Forks up at the door sill and in the doorway of the DC-3 (door open, stopped).
func _at_door(fp: Vector3) -> bool:
	if plane == null or plane.plane_type != "dc3" or not plane.door_open.get("bay", false):
		return false
	if plane.ground_speed > 0.5:
		return false
	var l: Vector3 = plane.global_transform.affine_inverse() * fp
	return l.x < -0.6 and l.x > -2.6 and l.z > Shape.DOOR_Z[0] + 0.3 and l.z < Shape.DOOR_Z[1] - 0.3 and l.y > Shape.cabin_floor(l.z) - 0.25 and l.y < Shape.cabin_floor(l.z) + 0.45


func _near_door_low(fp: Vector3) -> bool:
	var l: Vector3 = plane.global_transform.affine_inverse() * fp
	return l.x < -0.6 and l.x > -3.5 and l.z > Shape.DOOR_Z[0] and l.z < Shape.DOOR_Z[1] and l.y < Shape.cabin_floor(l.z) - 0.25
