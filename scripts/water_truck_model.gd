extends RefCounted
## The water / fuel truck, built new from ONE reference truck (DESIGN_NOTES 221,
## reference/water_truck/REFERENCE.txt): an early-90s L-series single-axle water
## truck, measured off the straight side photo (11R22.5 tyre = 1.05 m).
## Frame: -Z forward, +Y up, origin on the ground under the middle.
## Moving parts first: doors on their hinges, the tilt hood on its front pivots,
## steering knuckles and tie rod / drag link, both axles riding on their leaf
## springs (each spring half pinned to its hanger and to the axle seat), shocks,
## the PTO pump. Then the panels, then the details.

const MeshKit = preload("res://scripts/meshkit.gd")
const EK = preload("res://scripts/equip_kit.gd")
const TyreMesh = preload("res://scripts/tyre_mesh.gd")
const Dash = preload("res://scripts/truck_dash.gd")

# --- stations (m), from the side photo -----------------------------------------
const FZ := -2.2                 # front axle
const RZ := 1.38                 # rear axle (wheelbase 3.58)
const WR := 0.527                # tyre radius
const BUMP_Z := FZ - 0.83        # bumper face
const GRILLE_Z := FZ - 0.66      # hood / grille face
const COWL_Z := FZ + 0.61        # firewall, windscreen base
const CAB_BACK := FZ + 1.61
const DOOR_Z0 := FZ + 0.64       # hinge line
const DOOR_Z1 := FZ + 1.54
const SILL_Y := 1.04
const BELT_Y := 1.86
const ROOF_Y := 2.44
const CAB_HW := 1.0
const HOOD_HW := 0.76
const FEND_HW := 1.18
const HOOD_TOP0 := 1.70          # at the grille
const HOOD_TOP1 := 1.78          # at the cowl
const HOOD_BOT := 0.84
const HOOD_PIVOT := Vector3(0, 0.86, BUMP_Z + 0.24)
const FIREWALL_Z := COWL_Z - 0.30
const FLOOR_Y := 1.09
const RAIL_X := 0.43
const RAIL_TOP := 1.02
const RAIL_H := 0.26
const FRAME_Z0 := BUMP_Z + 0.14
const FRAME_Z1 := FZ + 4.33
const TANK_Z0 := CAB_BACK + 0.05
const TANK_Z1 := FZ + 4.28
const TANK_TOP := 2.40
const TANK_BOT := 1.16
const TANK_HW := 1.15            # at the top; 1.06 at the bottom
const SKIRT_Y0 := 1.05
const SKIRT_Y1 := 1.38
const FRONT_TRACK := 1.02        # wheel centre x
const REAR_TRACK := 0.91
const DUAL := 0.155
const SEAT_Z := CAB_BACK - 0.34
const EYE := Vector3(-0.50, 2.17, -0.88)
const WHEEL_C := Vector3(-0.47, 1.86, -1.08)     # where the seated driver's hands are (driving clip)
const COL_TILT := 0.55           # steering column, rad above horizontal
const STEER_R := 0.23

# colours
const WHITE := Color(0.90, 0.90, 0.88)
const WHITE_D := Color(0.78, 0.78, 0.76)
const BLACK := Color(0.07, 0.07, 0.075)
const FRAME := Color(0.10, 0.10, 0.11)
const STEEL := Color(0.42, 0.43, 0.45)
const CHROME := Color(0.86, 0.87, 0.89)
const RUBBER := Color(0.05, 0.05, 0.055)
const TAN := Color(0.62, 0.50, 0.36)
const TAN_D := Color(0.50, 0.40, 0.28)
const CLOTH := Color(0.48, 0.40, 0.32)
const CLOTH_D := Color(0.36, 0.30, 0.24)
const BRUSHED := Color(0.70, 0.70, 0.68)
const RED := Color(0.72, 0.10, 0.08)
const AMBER := Color(0.95, 0.55, 0.08)
const PUMP_RED := Color(0.62, 0.12, 0.08)
const ALU := Color(0.78, 0.79, 0.80)

# what the truck gets back: the moving parts
var hood: Node3D
var doors: Array = []            # [Node3D, side]
var knuckles: Array = []         # [Node3D, side] (steer, don't spin)
var front_axle: Node3D
var rear_axle: Node3D
var springs: Array = []          # [Node3D half, pin (frame point), axle seat node point (Node3D), axle]
var shocks: Array = []           # [barrel Node3D, rod Node3D, frame pt, axle Node3D, axle pt]
var tie_rod: Node3D
var drag_link: Node3D
var pitman: Node3D
var shaft2: Node3D               # driveshaft carrier -> pinion (moves with the axle)
var wheel_nodes: Array = []      # [Node3D, front, spin child]
var steer_wheel: Node3D
var shifter: Node3D
var park_knob: Node3D
var cab_switches: Dictionary = {}    # name -> Node3D (toggle levers in the spray box)
var pump_shaft: Node3D
var dash: Node3D
var box_dash: Node3D
var tailpipe_tip := Vector3.ZERO
var tank_mat_col := WHITE
var reel_drum: Node3D             # turns as the hose pays out
var pump_valve: Node3D            # the butterfly valve's lever (turns 90 degrees)
var wound_layers: Array = []      # the hose wound on the drum, inner and outer layer


# ------------------------------------------------------------------------------
#  shape helpers
# ------------------------------------------------------------------------------
## A tube along a polyline, with ball joints at the bends.
static func tube(k: MeshKit, pts: Array, r: float, col: Color, sides: int = 10) -> void:
	for i in range(pts.size() - 1):
		EK.rod(k, pts[i], pts[i + 1], r, col, sides)
	for i in range(1, pts.size() - 1):
		_ball(k, pts[i], r, col)


## One smooth hose along a path: rings carried along the bend (no twist), soft
## normals, no joints or caps between lengths (the turns on the drum and the
## lead to the guide look the same as the hose hanging out, hose_line.gd).
static func hose_sweep(k: MeshKit, pts: Array, r: float, col: Color, sides: int = 8, from: int = 0, to: int = -1) -> void:
	var n := pts.size()
	if n < 2:
		return
	var rings: Array = []
	var up := Vector3.UP
	for i in range(n):
		var t: Vector3 = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		if absf(up.dot(t)) > 0.95:
			up = Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD
		var x := t.cross(up).normalized()
		var y := x.cross(t).normalized()
		up = y
		var ring: Array = []
		for s in range(sides):
			var a := TAU * float(s) / float(sides)
			var nrm := x * cos(a) + y * sin(a)
			ring.append([(pts[i] as Vector3) + nrm * r, nrm])
		rings.append(ring)
	# only lengths from..to (pieces of one hose share the same rings, so they meet exactly)
	for i in range(maxi(from, 0), (n - 1) if to < 0 else mini(to, n - 1)):
		for s in range(sides):
			var s2 := (s + 1) % sides
			for tr in [[rings[i][s], rings[i][s2], rings[i + 1][s]], [rings[i][s2], rings[i + 1][s2], rings[i + 1][s]]]:
				var a0: Array = tr[0]
				var b0: Array = tr[1]
				var c0: Array = tr[2]
				var out: Vector3 = a0[1] + b0[1] + c0[1]
				if ((c0[0] as Vector3) - a0[0]).cross((b0[0] as Vector3) - a0[0]).dot(out) < 0.0:
					var tmp := b0
					b0 = c0
					c0 = tmp
				k.tri_c(a0[0], b0[0], c0[0], col, col, col, a0[1], b0[1], c0[1])


static func _ball(k: MeshKit, c: Vector3, r: float, col: Color) -> void:
	k.cylinder(Transform3D(Basis.IDENTITY, c - Vector3(0, r, 0)), r * 0.7, r * 0.7, r * 2.0, 8, col)
	k.cylinder(Transform3D(Basis.IDENTITY, c - Vector3(0, r * 0.7, 0)), r, r, r * 1.4, 8, col)


## A rounded rectangle ring in the XY plane at z (n points a corner).
static func rr_ring(cx: float, cy: float, hw: float, hh: float, r: float, z: float, n: int = 4) -> PackedVector3Array:
	var ring := PackedVector3Array()
	var cs := [[1.0, 1.0, 0.0], [-1.0, 1.0, PI * 0.5], [-1.0, -1.0, PI], [1.0, -1.0, PI * 1.5]]
	for c in cs:
		var ox: float = cx + float(c[0]) * (hw - r)
		var oy: float = cy + float(c[1]) * (hh - r)
		for i in range(n + 1):
			var a: float = float(c[2]) + PI * 0.5 * float(i) / float(n)
			ring.append(Vector3(ox + cos(a) * r, oy + sin(a) * r, z))
	return ring


## Skin over rings that are OPEN (a U section): quads between neighbours only,
## outward away from `core` (a point inside the shape for each ring).
static func sweep_open(k: MeshKit, rings: Array, cores: Array, col: Color, inward: bool = false) -> void:
	for r in range(rings.size() - 1):
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		var core: Vector3 = (cores[r] as Vector3 + cores[r + 1] as Vector3) * 0.5
		for i in range(a.size() - 1):
			var mid := (a[i] + a[i + 1] + b[i] + b[i + 1]) * 0.25
			var out := mid - core
			k.quad(a[i], a[i + 1], b[i + 1], b[i], col, -out if inward else out)


## The truck's wheel (tyre + rim) spun by its own child, and a hub that doesn't spin.
static func lens_lamp(kh: MeshKit, km: MeshKit, root: Node3D, c: Vector3, facing: Vector3, w: float, h: float, col: Color, round_: bool) -> void:
	EK.lamp(kh, km, root, c, facing, w, h, col, round_)


# ------------------------------------------------------------------------------
func build(t: Node3D, fuel: bool) -> void:
	tank_mat_col = ALU if fuel else WHITE
	_frame(t)
	_front_axle(t)
	_rear_axle(t)
	_engine(t)
	_hood(t)
	_cab(t)
	for s in [-1.0, 1.0]:
		_door(t, s)
	_interior(t)
	_tank(t, fuel)
	_plumbing(t, fuel)
	_under(t)
	_rear(t, fuel)
	_reel(t, fuel)
	_collide(t)
	pose(t, null, WR, 0.0, [], [], 0.25)        # lay the springs, shocks, links and shaft before the first frame


## Collision on the solid parts only (each its own convex hull, riding with
## its part): the cab, tank, skirts, hood and fenders, frame and bumper, the
## boxes under the cab. Pipes, trim, the engine and the inside don't block.
const SOLID := ["Cab", "Tank", "Skirt", "HoodShell", "Fenders", "Frame", "Under", "Panel", "Rear", "ReelDeck", "Drum", "Engine"]

func _collide(t: Node3D) -> void:
	for mi in t.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not SOLID.has(String(m.name)) or m.mesh == null:
			continue
		var shape := m.mesh.create_convex_shape(true, true)
		if shape == null:
			continue
		var body := AnimatableBody3D.new()
		body.name = String(m.name) + "_col"
		body.collision_layer = 1
		body.collision_mask = 0
		body.sync_to_physics = false
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		m.add_child(body)


# ------------------------------------------------------------------------------
#  Frame: two C-channel rails, crossmembers, the front bumper on its horns
# ------------------------------------------------------------------------------
func _frame(t: Node3D) -> void:
	var k := MeshKit.new()
	var ln := FRAME_Z1 - FRAME_Z0
	var zc := (FRAME_Z0 + FRAME_Z1) * 0.5
	var yc := RAIL_TOP - RAIL_H * 0.5
	for s in [-1.0, 1.0]:
		var sx: float = s
		# web on the outside, flanges turned in
		k.box_at(Vector3(sx * (RAIL_X - 0.004), yc, zc), Vector3(0.008, RAIL_H, ln), FRAME)
		for fy in [RAIL_TOP - 0.004, RAIL_TOP - RAIL_H + 0.004]:
			k.box_at(Vector3(sx * (RAIL_X - 0.04), fy, zc), Vector3(0.075, 0.008, ln), FRAME)
		# rivet rows along the web
		for i in range(int(ln / 0.35)):
			var rz: float = FRAME_Z0 + 0.2 + float(i) * 0.35
			for ry in [RAIL_TOP - 0.05, RAIL_TOP - RAIL_H + 0.05]:
				k.cylinder(Transform3D(Basis(Vector3.BACK, -sx * PI * 0.5), Vector3(sx * RAIL_X, ry, rz)), 0.009, 0.007, 0.006, 6, FRAME.lightened(0.1))
	# crossmembers: channels across the top half of the rails (the shafts and
	# lines pass under them), gusseted to the webs
	var cy := RAIL_TOP - 0.06
	for cz in [FRAME_Z0 + 0.05, COWL_Z + 0.95, TANK_Z0 + 0.95, RZ - 0.75, FRAME_Z1 - 0.05]:
		var czf: float = cz
		k.box_at(Vector3(0, cy, czf), Vector3(RAIL_X * 2.0 - 0.02, 0.12, 0.008), FRAME)
		for fz in [-0.035, 0.035]:
			k.box_at(Vector3(0, cy + 0.056, czf + float(fz)), Vector3(RAIL_X * 2.0 - 0.02, 0.008, 0.07), FRAME)
			k.box_at(Vector3(0, cy - 0.056, czf + float(fz)), Vector3(RAIL_X * 2.0 - 0.02, 0.008, 0.07), FRAME)
		for gs in [-1.0, 1.0]:
			k.box_at(Vector3(float(gs) * (RAIL_X - 0.03), cy - 0.04, czf), Vector3(0.05, 0.2, 0.09), FRAME)
	# front bumper: a black channel, face + top and bottom flanges, the ends
	# kicked back; bolted to brackets on the frame horns
	var by0 := 0.52
	var by1 := 0.82
	var bz := BUMP_Z
	var hw := 1.08
	k.box_at(Vector3(0, (by0 + by1) * 0.5, bz + 0.005), Vector3(hw * 2.0, by1 - by0, 0.01), BLACK)
	for fy2 in [by0 + 0.005, by1 - 0.005]:
		k.box_at(Vector3(0, fy2, bz + 0.075), Vector3(hw * 2.0, 0.01, 0.15), BLACK)
	for s2 in [-1.0, 1.0]:
		var ex: float = s2
		var b := Basis(Vector3.UP, -ex * 0.75)
		var c := Vector3(ex * (hw + 0.075), (by0 + by1) * 0.5, bz + 0.07)
		k.box(Transform3D(b, c), Vector3(0.21, by1 - by0, 0.01), BLACK)
		k.box(Transform3D(b, c + Vector3(0, (by1 - by0) * 0.5 - 0.005, 0.05)), Vector3(0.21, 0.01, 0.1), BLACK)
		k.box(Transform3D(b, c - Vector3(0, (by1 - by0) * 0.5 - 0.005, -0.05)), Vector3(0.21, 0.01, 0.1), BLACK)
		# bracket from the bumper top into the rail end (inside the channel)
		k.box_at(Vector3(ex * (RAIL_X - 0.04), 0.83, BUMP_Z + 0.135), Vector3(0.06, 0.1, 0.07), FRAME)
		EK.bolts(k, Vector3(ex * 0.7, 0.74, bz - 0.001), Vector3(ex * 0.7, 0.62, bz - 0.001), 2, Vector3(0, 0, -1), 0.012, BLACK.lightened(0.15))
		# tow hook under the bumper (a winch point): plate bolted on, the open hook
		var hp := Vector3(ex * 0.36, 0.47, bz + 0.07)
		k.box_at(hp + Vector3(0, 0.04, 0.0), Vector3(0.06, 0.03, 0.1), RED)
		for ha in range(7):
			var a0 := PI * 0.15 + PI * 1.3 * float(ha) / 7.0
			var a1 := PI * 0.15 + PI * 1.3 * float(ha + 1) / 7.0
			EK.rod(k, hp + Vector3(0, -cos(a0) * 0.04, -sin(a0) * 0.04), hp + Vector3(0, -cos(a1) * 0.04, -sin(a1) * 0.04), 0.012, RED, 6)
	t.add_child(k.instance("Frame"))


# ------------------------------------------------------------------------------
#  Front axle: a dropped I-beam on two leaf springs, knuckles on king pins,
#  the tie rod behind, the drag link from the steering box's pitman arm
# ------------------------------------------------------------------------------
func _front_axle(t: Node3D) -> void:
	front_axle = Node3D.new()
	front_axle.name = "FrontAxle"
	front_axle.position = Vector3(0, WR, FZ)
	t.add_child(front_axle)
	var k := MeshKit.new()
	var kp := 0.90
	# the I-beam: ends up at the king pins, dropped in the middle under the engine
	var pts := [Vector3(-kp, 0.0, 0), Vector3(-0.62, -0.02, 0), Vector3(-0.30, -0.10, 0), Vector3(0.30, -0.10, 0), Vector3(0.62, -0.02, 0), Vector3(kp, 0.0, 0)]
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := b - a
		k.box(Transform3D(Basis(Vector3.BACK, atan2(d.y, d.x)), (a + b) * 0.5), Vector3(d.length() + 0.02, 0.12, 0.016), FRAME)       # web
		for fz in [-0.045, 0.045]:
			k.box(Transform3D(Basis(Vector3.BACK, atan2(d.y, d.x)), (a + b) * 0.5 + Vector3(0, 0, float(fz))), Vector3(d.length() + 0.02, 0.12, 0.012), FRAME)
		k.box(Transform3D(Basis(Vector3.BACK, atan2(d.y, d.x)), (a + b) * 0.5 + Vector3(0, 0.055, 0)), Vector3(d.length() + 0.02, 0.012, 0.1), FRAME)
		k.box(Transform3D(Basis(Vector3.BACK, atan2(d.y, d.x)), (a + b) * 0.5 - Vector3(0, 0.055, 0)), Vector3(d.length() + 0.02, 0.012, 0.1), FRAME)
	# king pin bosses and the spring pads with their U-bolts
	for s in [-1.0, 1.0]:
		var sx: float = s
		k.cylinder(Transform3D(Basis.IDENTITY, Vector3(sx * kp, -0.08, 0)), 0.055, 0.055, 0.16, 12, FRAME)
		k.box_at(Vector3(sx * RAIL_X, 0.07, 0), Vector3(0.12, 0.02, 0.2), FRAME)
		for uz in [-0.06, 0.06]:
			for ux in [-0.05, 0.05]:
				k.cylinder(Transform3D(Basis.IDENTITY, Vector3(sx * RAIL_X + float(ux), -0.06, float(uz))), 0.011, 0.011, 0.26, 6, STEEL)
			k.box_at(Vector3(sx * RAIL_X, -0.07, float(uz)), Vector3(0.13, 0.025, 0.03), STEEL)
		# shock bracket on the beam
		k.box_at(Vector3(sx * (RAIL_X + 0.1), -0.02, 0.09), Vector3(0.04, 0.06, 0.04), FRAME)
	front_axle.add_child(k.instance("Beam"))
	# knuckles: steer about the king pin, carry the spindle, drum backing plate,
	# the steering arm (left, up to the drag link) and the tie rod arms (back)
	for s3 in [-1.0, 1.0]:
		var sx3: float = s3
		var kn := Node3D.new()
		kn.name = "Knuckle"
		kn.position = Vector3(sx3 * kp, 0, 0)
		front_axle.add_child(kn)
		var kk := MeshKit.new()
		kk.rbox(Transform3D(Basis.IDENTITY, Vector3(sx3 * 0.03, 0, 0)), Vector3(0.09, 0.22, 0.11), FRAME, 0.03)
		kk.cylinder(Transform3D(Basis(Vector3.BACK, -sx3 * PI * 0.5), Vector3(sx3 * 0.05, 0, 0)), 0.05, 0.04, 0.12, 10, STEEL)        # spindle
		kk.cylinder(Transform3D(Basis(Vector3.BACK, -sx3 * PI * 0.5), Vector3(sx3 * 0.03, 0, 0)), 0.2, 0.2, 0.02, 18, FRAME)          # backing plate
		kk.box_at(Vector3(-sx3 * 0.06, -0.05, 0.16), Vector3(0.04, 0.04, 0.26), FRAME)                                               # tie rod arm (inboard of the tyre)
		kk.box_at(Vector3(-sx3 * 0.03, -0.05, 0.04), Vector3(0.07, 0.04, 0.05), FRAME)
		if sx3 < 0.0:
			kk.box_at(Vector3(0.06, 0.10, -0.02), Vector3(0.04, 0.14, 0.04), FRAME)
			kk.box_at(Vector3(0.08, 0.17, 0.08), Vector3(0.04, 0.04, 0.22), FRAME)                                                   # steering arm up and back
		kn.add_child(kk.instance("Knuckle"))
		knuckles.append([kn, sx3])
	# tie rod and drag link: rods re-laid each frame between their ball joints
	tie_rod = _link_rod(front_axle, 0.022, "TieRod")
	pitman = Node3D.new()
	pitman.name = "Pitman"
	pitman.position = Vector3(-RAIL_X - 0.12, RAIL_TOP - 0.2, FZ - 0.45)
	t.add_child(pitman)
	var pk := MeshKit.new()
	pk.rbox(Transform3D(Basis.IDENTITY, Vector3(0.04, 0.06, 0)), Vector3(0.14, 0.18, 0.2), FRAME, 0.03)     # steering box on the rail
	pk.box_at(Vector3(-0.04, -0.1, 0), Vector3(0.03, 0.2, 0.05), FRAME.lightened(0.1))                      # pitman arm (moves)
	pitman.add_child(pk.instance("SteeringBox"))
	drag_link = _link_rod(t, 0.02, "DragLink")
	# leaf springs: a front and a rear half for each side, each pinned at its
	# hanger (front hanger / shackle) and laid to the axle seat each frame
	_spring_pair(t, front_axle, FZ, 0.60, 6)
	_shock_pair(t, front_axle, FZ + 0.09, 0.10)
	# frame hangers
	var hk := MeshKit.new()
	for s4 in [-1.0, 1.0]:
		var sx4: float = s4
		for hz in [FZ - 0.60, FZ + 0.60]:
			EK.lug(hk, Vector3(sx4 * RAIL_X, WR + 0.17, float(hz)), 0.05, 0.012, 0.045, Vector3(0, 1, 0), RAIL_TOP - RAIL_H - WR - 0.17 + 0.02, FRAME, 0.02, 0.07)
	t.add_child(hk.instance("FrontHangers"))


func _link_rod(parent: Node3D, r: float, nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	parent.add_child(n)
	var k := MeshKit.new()
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), r, r, 1.0, 8, FRAME)    # along +Z, length 1, scaled
	var mi := k.instance(nm)
	n.add_child(mi)
	return n


## Lay a unit rod node (along +Z) from a to b (in its parent's space).
static func lay(n: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var z := d.normalized()
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	n.transform = Transform3D(Basis(x, y, z * d.length()), a)


const LEAF := 0.014

func _spring_pair(t: Node3D, axle: Node3D, az: float, half: float, leaves: int) -> void:
	for s in [-1.0, 1.0]:
		var sx: float = s
		for e in [-1.0, 1.0]:
			var ez: float = e
			var n := Node3D.new()
			n.name = "SpringHalf"
			t.add_child(n)
			var k := MeshKit.new()
			# leaves along +Z from the eye (0) to the seat (1): each shorter one
			# lies under the one above; the main leaf rolls into an eye
			for i in range(leaves):
				var l0: float = 0.0 if i == 0 else 0.08 + 0.13 * float(i)
				var th := LEAF
				k.box_at(Vector3(0, -th * float(i) - th * 0.5, (l0 + 1.0) * 0.5), Vector3(0.075, th - 0.002, 1.0 - l0), STEEL.darkened(0.25 + 0.04 * float(i)))
			k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.04, 0, 0)), 0.026, 0.026, 0.08, 10, STEEL.darkened(0.3))
			var mi := k.instance("Leaves")
			n.add_child(mi)
			var pin := Vector3(sx * RAIL_X, WR + 0.17, az + ez * half)
			springs.append([n, pin, Vector3(sx * RAIL_X, 0.085 + LEAF * float(leaves), 0), axle, half])


func _shock_pair(t: Node3D, axle: Node3D, z: float, xo: float) -> void:
	for s in [-1.0, 1.0]:
		var sx: float = s
		var top := Vector3(sx * (RAIL_X + xo), RAIL_TOP - 0.05, z + 0.12)
		var bk := MeshKit.new()
		bk.box_at(top + Vector3(-sx * 0.04, 0, 0), Vector3(0.08, 0.06, 0.05), FRAME)
		t.add_child(bk.instance("ShockBracket"))
		var barrel := Node3D.new()
		var k := MeshKit.new()
		k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.03, 0.03, 0.26, 10, BLACK)
		barrel.add_child(k.instance("Barrel"))
		t.add_child(barrel)
		var rod := Node3D.new()
		var k2 := MeshKit.new()
		k2.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.011, 0.011, 0.3, 8, CHROME)
		rod.add_child(k2.instance("Rod"))
		t.add_child(rod)
		var bot := Vector3(sx * (RAIL_X + xo), -0.02, z - axle.position.z)
		shocks.append([barrel, rod, top, axle, bot])


# ------------------------------------------------------------------------------
#  Rear axle: banjo housing, spring seats and U-bolts, brake chambers;
#  main springs with the overload leaf above that meets its pads on the frame
# ------------------------------------------------------------------------------
func _rear_axle(t: Node3D) -> void:
	rear_axle = Node3D.new()
	rear_axle.name = "RearAxle"
	rear_axle.position = Vector3(0, WR, RZ)
	t.add_child(rear_axle)
	var k := MeshKit.new()
	# the pumpkin: a lathe-round centre with the carrier poking forward
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.12)), 0.24, 0.24, 0.24, 18, FRAME)
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.12)), 0.24, 0.16, 0.08, 18, FRAME)       # cover
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.03, -0.12)), 0.17, 0.12, 0.2, 14, FRAME)     # carrier
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.03, -0.32)), 0.06, 0.06, 0.06, 10, STEEL)    # pinion yoke
	for s in [-1.0, 1.0]:
		var sx: float = s
		k.cylinder(Transform3D(Basis(Vector3.BACK, -sx * PI * 0.5), Vector3(sx * 0.2, 0, 0)), 0.085, 0.07, 0.62, 12, FRAME)
		k.cylinder(Transform3D(Basis(Vector3.BACK, -sx * PI * 0.5), Vector3(sx * 0.78, 0, 0)), 0.2, 0.2, 0.02, 18, FRAME)    # backing plate
		# spring seat, U-bolts
		k.box_at(Vector3(sx * RAIL_X, 0.085, 0), Vector3(0.13, 0.02, 0.22), FRAME)
		for uz in [-0.065, 0.065]:
			for ux in [-0.05, 0.05]:
				k.cylinder(Transform3D(Basis.IDENTITY, Vector3(sx * RAIL_X + float(ux), -0.1, float(uz))), 0.012, 0.012, 0.34, 6, STEEL)
			k.box_at(Vector3(sx * RAIL_X, -0.1, float(uz)), Vector3(0.14, 0.03, 0.035), STEEL)
		# spring brake chamber (double can) on its bracket, push rod, slack adjuster
		var bc := Vector3(sx * 0.29, 0.12, -0.16)
		k.box_at(Vector3(sx * 0.29, 0.05, -0.1), Vector3(0.05, 0.12, 0.1), FRAME)
		k.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), bc), 0.09, 0.09, 0.1, 14, FRAME)
		k.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), bc + Vector3(0, 0, -0.1)), 0.09, 0.08, 0.1, 14, FRAME)
		k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), bc + Vector3(0, 0, 0.0)), 0.012, 0.012, 0.12, 6, STEEL)
		k.box_at(Vector3(sx * 0.29, 0.06, -0.05), Vector3(0.03, 0.12, 0.04), STEEL)
		# shock bracket
		k.box_at(Vector3(sx * (RAIL_X + 0.14), 0.0, 0.1), Vector3(0.04, 0.06, 0.04), FRAME)
	rear_axle.add_child(k.instance("Housing"))
	_spring_pair(t, rear_axle, RZ, 0.70, 7)
	_shock_pair(t, rear_axle, RZ + 0.1, 0.14)
	# frame hangers and the overload pads
	var hk := MeshKit.new()
	for s2 in [-1.0, 1.0]:
		var sx2: float = s2
		for hz in [RZ - 0.70, RZ + 0.70]:
			EK.lug(hk, Vector3(sx2 * RAIL_X, WR + 0.17, float(hz)), 0.05, 0.012, 0.045, Vector3(0, 1, 0), RAIL_TOP - RAIL_H - WR - 0.17 + 0.02, FRAME, 0.02, 0.07)
		for pz in [RZ - 0.42, RZ + 0.42]:
			hk.box_at(Vector3(sx2 * RAIL_X, RAIL_TOP - RAIL_H - 0.02, float(pz)), Vector3(0.1, 0.04, 0.1), FRAME)
	t.add_child(hk.instance("RearHangers"))
	# overload leaf, on the axle: short, flatter, its ends reach the pads
	var ok := MeshKit.new()
	for s3 in [-1.0, 1.0]:
		var sx3: float = s3
		for i in range(2):
			ok.box_at(Vector3(sx3 * RAIL_X, 0.085 + LEAF * 7.0 + LEAF * (float(i) + 0.5), 0), Vector3(0.075, LEAF - 0.002, 0.84 - 0.24 * float(i)), STEEL.darkened(0.3))
	rear_axle.add_child(ok.instance("Overload"))
	# driveshaft: the front shaft is fixed (transmission to the carrier
	# bearing), the rear one swings with the axle
	var dk := MeshKit.new()
	var trans_out := Vector3(0, 0.80, COWL_Z + 0.95)
	var carrier := Vector3(0, 0.74, TANK_Z0 + 0.95)
	EK.rod(dk, trans_out, carrier, 0.045, STEEL.darkened(0.2), 12)
	dk.box_at(carrier, Vector3(0.18, 0.1, 0.08), FRAME)                       # carrier bearing on its crossmember
	dk.box_at(carrier + Vector3(0, 0.1, 0), Vector3(0.12, 0.12, 0.04), FRAME)
	t.add_child(dk.instance("Driveshaft1"))
	shaft2 = _link_rod(t, 0.05, "Driveshaft2")


# ------------------------------------------------------------------------------
#  Engine bay: inline six, radiator and fan, turbo, air compressor, the
#  air cleaner behind the round intake in the right hood side, transmission
#  with the PTO on its right side
# ------------------------------------------------------------------------------
func _engine(t: Node3D) -> void:
	var k := MeshKit.new()
	var ez0 := FZ - 0.30
	var ez1 := COWL_Z + 0.04
	var ec := (ez0 + ez1) * 0.5
	var el := ez1 - ez0
	var grey := Color(0.30, 0.31, 0.30)
	var blue := Color(0.20, 0.24, 0.30)
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 1.10, ec)), Vector3(0.46, 0.44, el), blue, 0.04)            # block
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 1.40, ec)), Vector3(0.40, 0.16, el - 0.04), blue, 0.03)     # head
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 1.52, ec)), Vector3(0.32, 0.08, el - 0.1), grey, 0.035)     # valve cover
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.84, ec + 0.18)), Vector3(0.36, 0.12, el - 0.4), blue, 0.03)   # oil pan, deep at the back
	for i in range(6):
		var cz: float = ez0 + 0.1 + float(i) * (el - 0.2) / 5.0
		k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 1.56, cz)), 0.012, 0.012, 0.02, 6, STEEL)            # cover bolts
		k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.24, 1.32, cz)), 0.045, 0.045, 0.08, 10, Color(0.35, 0.3, 0.26))   # exhaust ports
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(-0.27, 1.34, ec)), Vector3(0.08, 0.12, el - 0.1), grey, 0.03)  # intake manifold
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0.30, 1.32, ec)), Vector3(0.07, 0.1, el - 0.1), Color(0.35, 0.3, 0.26), 0.03)    # exhaust manifold
	# turbo at the back right, its down pipe to the exhaust under the cab
	var tb := Vector3(0.36, 1.36, ez1 - 0.12)
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), tb + Vector3(-0.06, 0, 0)), 0.11, 0.11, 0.12, 14, Color(0.4, 0.36, 0.3))
	tube(k, [tb + Vector3(0.0, -0.06, 0.04), Vector3(0.42, 1.0, ez1), Vector3(0.48, 0.72, ez1 + 0.2)], 0.055, Color(0.35, 0.3, 0.26))
	# front: timing cover, crank pulley, belts, fan hub, alternator, compressor
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 1.12, ez0 - 0.03)), Vector3(0.42, 0.42, 0.06), blue, 0.04)
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.98, ez0 - 0.06)), 0.11, 0.11, 0.05, 16, BLACK)
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 1.35, ez0 - 0.06)), 0.09, 0.09, 0.08, 16, BLACK)       # fan hub
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.24, 1.24, ez0 + 0.02)), 0.08, 0.08, 0.18, 14, STEEL)   # alternator
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(-0.27, 0.98, ez0 + 0.2)), 0.08, 0.08, 0.24, 14, grey)     # air compressor
	for bl in [[Vector3(0, 0.98, 0), Vector3(0, 1.35, 0)], [Vector3(0, 1.35, 0), Vector3(0.24, 1.24, 0)]]:
		EK.rod(k, (bl[0] as Vector3) + Vector3(0, 0, ez0 - 0.07), (bl[1] as Vector3) + Vector3(0, 0, ez0 - 0.07), 0.012, RUBBER, 6)
	# engine mounts on the rails
	for s in [-1.0, 1.0]:
		var sx: float = s
		for mz in [ez0 + 0.15, ez1 - 0.12]:
			k.box_at(Vector3(sx * 0.33, 0.95, float(mz)), Vector3(0.2, 0.06, 0.1), FRAME)
	# radiator: core, tanks, shroud and the fan inside it; hoses to the engine
	var rz := GRILLE_Z + 0.14
	k.box_at(Vector3(0, 1.35, rz), Vector3(1.04, 0.48, 0.07), Color(0.12, 0.12, 0.12))
	for ry in [1.07, 1.62]:
		k.rbox(Transform3D(Basis.IDENTITY, Vector3(0, float(ry), rz)), Vector3(1.08, 0.08, 0.1), FRAME, 0.02)
	for fx in [-0.56, 0.56]:
		k.box_at(Vector3(float(fx), 1.345, rz), Vector3(0.04, 0.6, 0.1), FRAME)
		k.box_at(Vector3(float(fx) * 0.75, 1.025, rz + 0.03), Vector3(0.08, 0.01, 0.08), FRAME)                      # pads on the rails
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.35, rz + 0.04)), 0.31, 0.29, 0.12, 20, BLACK, false)     # shroud
	for b in range(6):
		var a := TAU * float(b) / 6.0
		k.box(Transform3D(Basis(Vector3.BACK, a) * Basis(Vector3.UP, 0.4), Vector3(0, 1.35, rz + 0.12) + Vector3(cos(a), sin(a), 0) * 0.15), Vector3(0.25, 0.08, 0.008), Color(0.16, 0.16, 0.14))
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.3, 1.655, rz)), 0.03, 0.03, 0.015, 10, CHROME)                         # filler cap
	tube(k, [Vector3(-0.38, 1.58, rz + 0.05), Vector3(-0.3, 1.5, rz + 0.2), Vector3(-0.15, 1.46, ez0 - 0.02)], 0.04, RUBBER)
	tube(k, [Vector3(0.38, 1.12, rz + 0.05), Vector3(0.3, 1.0, rz + 0.25), Vector3(0.18, 0.95, ez0 + 0.02)], 0.04, RUBBER)
	# air cleaner behind the round intake in the right side of the hood
	var ac := Vector3(0.55, 1.36, COWL_Z - 0.32)
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), ac + Vector3(0.14, 0, 0)), 0.17, 0.17, 0.3, 18, BLACK)
	tube(k, [ac + Vector3(-0.16, 0, 0), Vector3(0.38, 1.42, ez1 - 0.12)], 0.06, RUBBER)
	# transmission: bell housing, case, shift tower up into the cab, PTO
	var tz0 := ez1
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.98, tz0)), 0.26, 0.2, 0.2, 16, Color(0.55, 0.55, 0.52))
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.88, tz0 + 0.5)), Vector3(0.34, 0.24, 0.62), Color(0.55, 0.55, 0.52), 0.04)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.05, 0.98, COWL_Z + 0.58)), 0.05, 0.04, 0.12, 10, Color(0.55, 0.55, 0.52))
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0.24, 0.80, tz0 + 0.42)), Vector3(0.14, 0.14, 0.2), Color(0.5, 0.5, 0.48), 0.02)   # PTO
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.80, tz0 + 0.8)), 0.06, 0.06, 0.05, 10, STEEL)              # output yoke
	t.add_child(k.instance("Engine"))


# ------------------------------------------------------------------------------
#  Tilt hood: one piece with the fenders and the grille, on two pivots at the
#  front of the frame. The lamps ride on it.
# ------------------------------------------------------------------------------
func _fender_top(z: float) -> float:
	# 1.40 at the nose, up to 1.46, the back edge curling down to the cab step
	var f := clampf((z - GRILLE_Z) / (COWL_Z - GRILLE_Z), 0.0, 1.0)
	var y := 1.40 + 0.06 * f
	var back := COWL_Z - 0.01
	if z > back - 0.16:
		var u := clampf((z - (back - 0.16)) / 0.16, 0.0, 1.0)
		y -= 0.42 * (1.0 - sqrt(maxf(1.0 - u * u, 0.0)))
	return y


const ARCH_HW := 0.52            # wheel arch: half width, height over the axle
const ARCH_H := 0.65

static func arch_y(dz: float) -> float:
	var u := clampf(dz / ARCH_HW, -1.0, 1.0)
	return WR + ARCH_H * sqrt(maxf(1.0 - u * u, 0.0))


func _fender_bot(z: float) -> float:
	var dz := z - FZ
	if absf(dz) < ARCH_HW:
		return maxf(arch_y(dz), HOOD_BOT)
	return HOOD_BOT if dz < 0.0 else 0.94


func _hood(t: Node3D) -> void:
	hood = Node3D.new()
	hood.name = "Hood"
	hood.position = HOOD_PIVOT
	t.add_child(hood)
	var o := -HOOD_PIVOT                  # build in truck space, shift into the pivot's
	var k := MeshKit.new()
	var inner := MeshKit.new()
	# the hood: rounded top edge, flat top rising to the cowl, sides down
	# inside the fenders; open underneath (skinned inside too, dark)
	var rings: Array = []
	var irings: Array = []
	var cores: Array = []
	var zs := [GRILLE_Z, GRILLE_Z + 0.025, GRILLE_Z + 0.07, GRILLE_Z + 0.4, COWL_Z - 0.4, COWL_Z - 0.01]
	for zi in range(zs.size()):
		var zz: float = zs[zi]
		var f := (zz - GRILLE_Z) / (COWL_Z - GRILLE_Z)
		var top := lerpf(HOOD_TOP0, HOOD_TOP1, f)
		var inset := 0.0
		if zi == 0:
			inset = 0.06
		elif zi == 1:
			inset = 0.018
		var ring := PackedVector3Array()
		var iring := PackedVector3Array()
		var hw := HOOD_HW - inset
		var rr := 0.07
		ring.append(Vector3(-hw, 1.30, zz))
		for i in range(5):
			var a := PI - PI * 0.5 * float(i) / 4.0
			ring.append(Vector3(-hw + rr + cos(a) * rr, top - inset - rr + sin(a) * rr, zz))
		for i in range(5):
			var a2 := PI * 0.5 - PI * 0.5 * float(i) / 4.0
			ring.append(Vector3(hw - rr + cos(a2) * rr, top - inset - rr + sin(a2) * rr, zz))
		ring.append(Vector3(hw, 1.30, zz))
		for p in ring:
			iring.append(Vector3(p.x * 0.985, p.y - 0.02, p.z))
		rings.append(ring)
		irings.append(iring)
		cores.append(Vector3(0, 1.3, zz))
	for i in range(rings.size()):
		var rg: PackedVector3Array = rings[i]
		for j in range(rg.size()):
			rg[j] += o
		rings[i] = rg
		var ig: PackedVector3Array = irings[i]
		for j2 in range(ig.size()):
			ig[j2] += o
		irings[i] = ig
		cores[i] = (cores[i] as Vector3) + o
	sweep_open(k, rings, cores, WHITE)
	sweep_open(inner, irings, cores, Color(0.2, 0.2, 0.2), true)
	# the nose face: grille surround panel round the grille opening
	var gy0 := 0.90
	var gy1 := 1.60
	var gw := 0.65
	var face := func(x0: float, x1: float, y0: float, y1: float) -> void:
		k.quad(Vector3(x0, y0, GRILLE_Z) + o, Vector3(x1, y0, GRILLE_Z) + o, Vector3(x1, y1, GRILLE_Z) + o, Vector3(x0, y1, GRILLE_Z) + o, WHITE, Vector3(0, 0, -1))
		inner.quad(Vector3(x0, y0, GRILLE_Z + 0.02) + o, Vector3(x1, y0, GRILLE_Z + 0.02) + o, Vector3(x1, y1, GRILLE_Z + 0.02) + o, Vector3(x0, y1, GRILLE_Z + 0.02) + o, Color(0.2, 0.2, 0.2), Vector3(0, 0, 1))
	face.call(-HOOD_HW + 0.06, -gw, HOOD_BOT, HOOD_TOP0 - 0.06)
	face.call(gw, HOOD_HW - 0.06, HOOD_BOT, HOOD_TOP0 - 0.06)
	face.call(-gw, gw, gy1, HOOD_TOP0 - 0.06)
	face.call(-gw, gw, HOOD_BOT, gy0)
	face.call(-HOOD_HW + 0.02, -HOOD_HW + 0.06, HOOD_BOT, 1.30)
	face.call(HOOD_HW - 0.06, HOOD_HW - 0.02, HOOD_BOT, 1.30)
	# the grille: chrome surround, eleven bars split by the wide centre bar,
	# a blank oval badge; dark behind
	var gk := MeshKit.new()
	var gc := Vector3(0, (gy0 + gy1) * 0.5, GRILLE_Z - 0.01) + o
	gk.box_at(gc + Vector3(0, 0, 0.06), Vector3(gw * 2.0, gy1 - gy0, 0.01), Color(0.03, 0.03, 0.03))
	for side in [[Vector3(0, (gy1 - gy0) * 0.5, 0), Vector3(gw * 2.0 + 0.04, 0.04, 0.05)], [Vector3(0, -(gy1 - gy0) * 0.5, 0), Vector3(gw * 2.0 + 0.04, 0.04, 0.05)],
			[Vector3(gw, 0, 0), Vector3(0.04, gy1 - gy0, 0.05)], [Vector3(-gw, 0, 0), Vector3(0.04, gy1 - gy0, 0.05)]]:
		gk.rbox(Transform3D(Basis.IDENTITY, gc + (side[0] as Vector3)), side[1], CHROME, 0.012)
	for bi in range(11):
		var by := gy0 + 0.04 + (gy1 - gy0 - 0.08) * float(bi) / 10.0
		var thick := 0.045 if bi == 5 else 0.018
		gk.box(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, by, GRILLE_Z + 0.01) + o), Vector3(gw * 2.0 - 0.02, thick, 0.035), CHROME.darkened(0.08))
	gk.rbox(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, gy0 + (gy1 - gy0) * 0.5, GRILLE_Z - 0.025) + o), Vector3(0.16, 0.012, 0.07), Color(0.2, 0.3, 0.6), 0.03)
	# fenders: solid slices round the wheel, flat front face with the lamp
	var fk := MeshKit.new()
	var frings: Array = []
	var nz := 30
	for i in range(nz + 1):
		frings.append(GRILLE_Z + 0.005 + (COWL_Z - 0.012 - GRILLE_Z) * float(i) / float(nz))
	for s2 in [-1.0, 1.0]:
		var sx: float = s2
		var rs: Array = []
		for zq in frings:
			var zz3: float = zq
			var top3 := _fender_top(zz3)
			var bot3 := minf(_fender_bot(zz3), top3 - 0.03)
			var ring2 := PackedVector3Array()
			var xin := HOOD_HW - 0.02
			var xout := FEND_HW
			var rr2 := minf(0.08, (top3 - bot3) * 0.45)
			# inner bottom, inner top, rounded outer top, outer bottom (lip turned under)
			ring2.append(Vector3(sx * xin, bot3, zz3) + o)
			ring2.append(Vector3(sx * xin, top3, zz3) + o)
			for a3 in range(4):
				var aa := PI * 0.5 * float(a3) / 3.0
				ring2.append(Vector3(sx * (xout - rr2 + sin(aa) * rr2), top3 - rr2 + cos(aa) * rr2, zz3) + o)
			ring2.append(Vector3(sx * xout, bot3 + 0.02, zz3) + o)
			ring2.append(Vector3(sx * (xout - 0.03), bot3, zz3) + o)
			if sx < 0.0:
				ring2.reverse()
			rs.append(ring2)
		fk.loft(rs, WHITE, true, true)
		# arch liner (black) under the fender over the tyre
		for ai in range(14):
			var z0 := FZ - ARCH_HW * 0.93 + ARCH_HW * 1.86 * float(ai) / 14.0
			var z1 := FZ - ARCH_HW * 0.93 + ARCH_HW * 1.86 * float(ai + 1) / 14.0
			var p0 := Vector3(sx * (HOOD_HW - 0.02), arch_y(z0 - FZ) - 0.005, z0) + o
			var p1 := Vector3(sx * (HOOD_HW - 0.02), arch_y(z1 - FZ) - 0.005, z1) + o
			var q0 := Vector3(sx * (FEND_HW - 0.03), p0.y - o.y, p0.z - o.z) + o
			var q1 := Vector3(sx * (FEND_HW - 0.03), p1.y - o.y, p1.z - o.z) + o
			fk.quad(p0, p1, q1, q0, BLACK, Vector3(0, -1, 0))
		# square sealed-beam headlamp in the fender face, its chrome bezel;
		# the amber turn lamp in its box on the fender top corner
		var hc := Vector3(sx * 0.97, 1.09, GRILLE_Z + 0.004)
		fk.rbox(Transform3D(Basis.IDENTITY, hc + o), Vector3(0.27, 0.2, 0.02), CHROME, 0.02)
		EK.lamp(fk, gk, hood, hc + o + Vector3(0, 0, -0.012), Vector3(0, 0, -1), 0.22, 0.155, Color(1.0, 0.97, 0.88), false)
		var tc := Vector3(sx * 1.06, _fender_top(GRILLE_Z + 0.08) + 0.05, GRILLE_Z + 0.08)
		fk.rbox(Transform3D(Basis.IDENTITY, tc + o + Vector3(0, 0, 0.02)), Vector3(0.12, 0.1, 0.1), BLACK, 0.015)
		EK.lamp(fk, gk, hood, tc + o + Vector3(0, 0, -0.035), Vector3(0, 0, -1), 0.1, 0.075, AMBER, false)
		EK.lamp(fk, gk, hood, tc + o + Vector3(sx * 0.062, 0, 0.02), Vector3(sx, 0, 0), 0.08, 0.06, AMBER, false)
		var sm := Vector3(sx * (FEND_HW + 0.002), 1.0, GRILLE_Z + 0.09)
		fk.rbox(Transform3D(Basis.IDENTITY, sm + o), Vector3(0.016, 0.07, 0.05), BLACK, 0.006)
		EK.lamp(fk, gk, hood, sm + o + Vector3(sx * 0.012, 0, 0), Vector3(sx, 0, 0), 0.04, 0.055, AMBER, false)     # side marker
	# right side of the hood: the round air intake (a louvred disc in a ring)
	var ic := Vector3(HOOD_HW + 0.004, 1.58, COWL_Z - 0.32) + o
	gk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), ic + Vector3(0.01, 0, 0)), 0.12, 0.12, 0.012, 20, WHITE_D)
	for li in range(5):
		gk.box(Transform3D(Basis(Vector3.BACK, PI * 0.5), ic + Vector3(0.014, -0.08 + 0.04 * float(li), 0)), Vector3(0.02, 0.006, 0.2 - absf(float(li) - 2.0) * 0.045), Color(0.25, 0.25, 0.25))
	# model badge on each hood side (no brand)
	for s5 in [-1.0, 1.0]:
		EK.decal(hood, "HD-80", Vector3(float(s5) * (HOOD_HW + 0.003), 1.58, GRILLE_Z + 0.45) + o, Vector3(float(s5), 0, 0), 0.0016, Color(0.75, 0.76, 0.78))
	# the pivots: a bracket on each frame horn, the hood's ear round its pin
	# the pivots: a boss on the outside of each frame horn with its pin, the
	# hood's ear plate round the pin and up to the hood's front edge
	var pk := MeshKit.new()
	for s6 in [-1.0, 1.0]:
		var sx6: float = s6
		pk.cylinder(Transform3D(Basis(Vector3.BACK, -sx6 * PI * 0.5), Vector3(sx6 * RAIL_X, HOOD_PIVOT.y, HOOD_PIVOT.z)), 0.035, 0.035, 0.02, 14, FRAME)
		pk.cylinder(Transform3D(Basis(Vector3.BACK, -sx6 * PI * 0.5), Vector3(sx6 * RAIL_X, HOOD_PIVOT.y, HOOD_PIVOT.z)), 0.014, 0.014, 0.075, 8, STEEL)
		var ex := sx6 * (RAIL_X + 0.03)
		k.cylinder(Transform3D(Basis(Vector3.BACK, -sx6 * PI * 0.5), Vector3(ex - sx6 * 0.006, HOOD_PIVOT.y, HOOD_PIVOT.z) + o), 0.03, 0.03, 0.012, 12, FRAME)
		k.box_at(Vector3(ex, (HOOD_PIVOT.y + HOOD_BOT) * 0.5 + 0.01, (HOOD_PIVOT.z + GRILLE_Z) * 0.5 + 0.01) + o, Vector3(0.012, 0.06, absf(HOOD_PIVOT.z - GRILLE_Z) + 0.02), FRAME)
	t.add_child(pk.instance("HoodPivots"))
	var mi := k.instance("HoodShell")
	hood.add_child(mi)
	hood.add_child(inner.instance("HoodInner"))
	hood.add_child(fk.instance("Fenders"))
	hood.add_child(gk.instance("Grille"))


# ------------------------------------------------------------------------------
#  Cab shell (the doors are separate): cowl, windscreen frame, roof with drip
#  rails and the five marker lamps, back wall with its window, B posts, floor
# ------------------------------------------------------------------------------
func _cab(t: Node3D) -> void:
	var k := MeshKit.new()
	var tr := MeshKit.new()             # trim inside, tan
	var gl := MeshKit.new()
	var seal := MeshKit.new()
	var ws0 := Vector3(0, BELT_Y, COWL_Z + 0.02)       # windscreen base
	var ws1 := Vector3(0, ROOF_Y - 0.14, COWL_Z + 0.10) # top
	var cl := CAB_BACK - FIREWALL_Z
	var cz := (FIREWALL_Z + CAB_BACK) * 0.5
	# floor pan and the sills under the doors
	k.box_at(Vector3(0, FLOOR_Y - 0.03, cz), Vector3(CAB_HW * 2.0 - 0.02, 0.06, cl), WHITE_D)
	for s in [-1.0, 1.0]:
		var sx: float = s
		k.rbox(Transform3D(Basis.IDENTITY, Vector3(sx * (CAB_HW - 0.035), SILL_Y - 0.03, cz)), Vector3(0.07, 0.09, cl), WHITE, 0.02)
		# cowl sides: from the firewall to the door, behind the fender
		k.box_at(Vector3(sx * (CAB_HW - 0.01), (SILL_Y + BELT_Y) * 0.5, (FIREWALL_Z + DOOR_Z0) * 0.5 - 0.004), Vector3(0.02, BELT_Y - SILL_Y, DOOR_Z0 - FIREWALL_Z - 0.008), WHITE)
	# firewall (dark: it shows with the hood up), the cowl top under the hood's
	# back edge, the cowl face up to the windscreen
	k.box_at(Vector3(0, (FLOOR_Y + 1.70) * 0.5, FIREWALL_Z), Vector3(CAB_HW * 2.0 - 0.04, 1.70 - FLOOR_Y, 0.01), Color(0.15, 0.15, 0.15))
	k.box_at(Vector3(0, 1.67, (FIREWALL_Z + COWL_Z) * 0.5), Vector3(CAB_HW * 2.0 - 0.04, 0.06, COWL_Z - FIREWALL_Z), Color(0.2, 0.2, 0.2))
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0, (1.70 + BELT_Y) * 0.5 + 0.005, COWL_Z + 0.012)), Vector3(CAB_HW * 2.0 - 0.04, BELT_Y - 1.70 + 0.01, 0.04), WHITE, 0.012)
	# A pillars (rounded posts, raked like the glass) and the header
	for s3 in [-1.0, 1.0]:
		var sx3: float = s3
		var a := Vector3(sx3 * (CAB_HW - 0.05), BELT_Y - 0.04, COWL_Z + 0.0)
		var b := Vector3(sx3 * (CAB_HW - 0.05), ROOF_Y - 0.12, COWL_Z + 0.09)
		var d := b - a
		var bas := Basis(Vector3.RIGHT, atan2(d.z, d.y))
		k.rbox(Transform3D(bas, (a + b) * 0.5), Vector3(0.10, d.length() + 0.04, 0.06), WHITE, 0.025)
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0, ROOF_Y - 0.14, COWL_Z + 0.12)), Vector3(CAB_HW * 2.0 - 0.04, 0.07, 0.08), WHITE, 0.025)
	# windscreen: one piece, black rubber round it
	var wx := CAB_HW - 0.10
	EK.pane(gl, seal, Vector3(-wx, ws0.y + 0.01, ws0.z + 0.004), Vector3(wx, ws0.y + 0.01, ws0.z + 0.004), Vector3(wx, ws1.y - 0.01, ws1.z - 0.004), Vector3(-wx, ws1.y - 0.01, ws1.z - 0.004), Vector3(0, 0.18, -1))
	# roof: rounded slab, crowned, drip rails along the sides, markers in front
	var rz0 := COWL_Z + 0.10
	var rl := CAB_BACK - rz0
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0, ROOF_Y - 0.06, rz0 + rl * 0.5)), Vector3(CAB_HW * 2.0, 0.12, rl), WHITE, 0.05)
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0, ROOF_Y - 0.005, rz0 + rl * 0.5)), Vector3(CAB_HW * 1.7, 0.02, rl - 0.1), WHITE, 0.01)
	for s4 in [-1.0, 1.0]:
		k.box_at(Vector3(float(s4) * (CAB_HW + 0.012), ROOF_Y - 0.11, rz0 + rl * 0.5), Vector3(0.02, 0.025, rl - 0.04), WHITE_D)    # drip rail
	var lk := MeshKit.new()
	for mi in range(5):
		var mc := Vector3(-0.44 + 0.22 * float(mi), ROOF_Y + 0.018, rz0 + 0.07)
		k.rbox(Transform3D(Basis.IDENTITY, mc + Vector3(0, -0.004, 0.01)), Vector3(0.1, 0.035, 0.07), BLACK, 0.01)
		EK.lamp(k, lk, t, mc + Vector3(0, 0.008, -0.03), Vector3(0, 0.25, -1), 0.08, 0.025, AMBER, false)
	# back wall: around the rear window, rounded corner posts (the B posts
	# behind the doors), grab handles
	var by := (SILL_Y + ROOF_Y - 0.06) * 0.5
	var bh := ROOF_Y - 0.06 - SILL_Y
	var rw := 0.44
	var rw0 := 1.88
	var rw1 := 2.20
	k.box_at(Vector3(0, (SILL_Y + rw0) * 0.5, CAB_BACK - 0.02), Vector3(CAB_HW * 2.0 - 0.1, rw0 - SILL_Y, 0.04), WHITE)
	k.box_at(Vector3(0, (rw1 + ROOF_Y - 0.06) * 0.5, CAB_BACK - 0.02), Vector3(CAB_HW * 2.0 - 0.1, ROOF_Y - 0.06 - rw1, 0.04), WHITE)
	for s5 in [-1.0, 1.0]:
		var sx5: float = s5
		k.box_at(Vector3(sx5 * (rw + (CAB_HW - 0.05 - rw) * 0.5), (rw0 + rw1) * 0.5, CAB_BACK - 0.02), Vector3(CAB_HW - 0.05 - rw, rw1 - rw0, 0.04), WHITE)
		k.rbox(Transform3D(Basis.IDENTITY, Vector3(sx5 * (CAB_HW - 0.035), by, CAB_BACK - (CAB_BACK - DOOR_Z1) * 0.5 + 0.005)), Vector3(0.07, bh, CAB_BACK - DOOR_Z1 + 0.01), WHITE, 0.03)
		# grab handle on the B post
		tube(k, [Vector3(sx5 * (CAB_HW + 0.01), 1.32, CAB_BACK - 0.03), Vector3(sx5 * (CAB_HW + 0.05), 1.34, CAB_BACK - 0.03), Vector3(sx5 * (CAB_HW + 0.05), 1.98, CAB_BACK - 0.03), Vector3(sx5 * (CAB_HW + 0.01), 2.0, CAB_BACK - 0.03)], 0.014, CHROME, 8)
		# door striker
		k.box_at(Vector3(sx5 * (CAB_HW - 0.02), 1.5, DOOR_Z1 + 0.012), Vector3(0.03, 0.06, 0.02), CHROME.darkened(0.2))
		# hinges on the A side
		for hy in [1.25, 1.95]:
			k.rbox(Transform3D(Basis.IDENTITY, Vector3(sx5 * (CAB_HW + 0.01), float(hy), DOOR_Z0 - 0.005)), Vector3(0.03, 0.09, 0.05), WHITE_D, 0.01)
	EK.pane(gl, seal, Vector3(rw, rw0, CAB_BACK + 0.002), Vector3(-rw, rw0, CAB_BACK + 0.002), Vector3(-rw, rw1, CAB_BACK + 0.002), Vector3(rw, rw1, CAB_BACK + 0.002), Vector3(0, 0, 1))
	# wipers: two arms from the cowl lying on the glass
	for wx2 in [-0.55, 0.15]:
		var p0 := Vector3(float(wx2), BELT_Y + 0.0, COWL_Z + 0.05)
		k.cylinder(Transform3D(Basis.IDENTITY, p0 - Vector3(0, 0.01, 0)), 0.02, 0.02, 0.03, 8, BLACK)
		EK.rod(k, p0 + Vector3(0, 0.015, -0.01), p0 + Vector3(0.42, 0.06, 0.0), 0.008, BLACK, 6)
		k.box(Transform3D(Basis(Vector3.BACK, 0.14) * Basis(Vector3.RIGHT, -0.2), p0 + Vector3(0.36, 0.07, -0.01)), Vector3(0.48, 0.012, 0.012), BLACK)
	# inside trim: tan back wall, headliner with its ribs, A post covers
	tr.box_at(Vector3(0, (SILL_Y + rw0) * 0.5, CAB_BACK - 0.045), Vector3(CAB_HW * 2.0 - 0.14, rw0 - SILL_Y, 0.01), TAN)
	tr.box_at(Vector3(0, ROOF_Y - 0.125, rz0 + rl * 0.5), Vector3(CAB_HW * 2.0 - 0.12, 0.01, rl - 0.04), TAN)
	for ri in range(8):
		tr.box_at(Vector3(0, ROOF_Y - 0.133, rz0 + 0.1 + float(ri) * (rl - 0.2) / 7.0), Vector3(CAB_HW * 2.0 - 0.16, 0.008, 0.025), TAN_D)
	t.add_child(k.instance("Cab"))
	t.add_child(lk.instance("CabLamps"))
	t.add_child(tr.instance("CabTrim"))
	t.add_child(seal.instance("CabSeals"))
	_glass(t, gl, "CabGlass")


static func _glass(parent: Node3D, gl: MeshKit, nm: String) -> void:
	var gm := gl.instance(nm)
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.45, 0.58, 0.66, 0.3)
	gmat.roughness = 0.05
	gmat.metallic_specular = 0.9
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.material_override = gmat
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(gm)


# ------------------------------------------------------------------------------
#  Doors: hinged at the front, the west-coast mirror rides on the door.
#  Built in the door's own frame: x out (+side), y up from the sill, z back
#  from the hinge.
# ------------------------------------------------------------------------------
func _door(t: Node3D, s: float) -> void:
	var d := Node3D.new()
	d.name = "Door" + ("L" if s < 0.0 else "R")
	d.position = Vector3(s * CAB_HW, SILL_Y, DOOR_Z0)
	t.add_child(d)
	var k := MeshKit.new()
	var tr := MeshKit.new()
	var gl := MeshKit.new()
	var seal := MeshKit.new()
	var L := DOOR_Z1 - DOOR_Z0 - 0.006
	var H := ROOF_Y - 0.125 - SILL_Y          # under the roof's edge
	var belt := BELT_Y - SILL_Y
	var th := 0.09
	var rake := 0.095                         # the front of the window follows the A pillar
	# outer panel up to the belt (rounded edges), the window frame above:
	# slanted front post, top rail, rear post
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(-s * th * 0.5, belt * 0.5 + 0.005, L * 0.5 + 0.003)), Vector3(th, belt, L), WHITE, 0.025)
	var fw := 0.05
	var top0 := rake + 0.006
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(-s * 0.025, H - 0.025, (top0 + L) * 0.5 + 0.003)), Vector3(0.05, 0.05, L - top0), WHITE, 0.015)
	var fa := Vector3(-s * 0.025, belt, 0.006 + fw * 0.5)
	var fb := Vector3(-s * 0.025, H, top0 + fw * 0.5)
	k.rbox(Transform3D(Basis(Vector3.RIGHT, atan2(fb.z - fa.z, fb.y - fa.y)), (fa + fb) * 0.5), Vector3(0.05, fa.distance_to(fb), fw), WHITE, 0.015)
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(-s * 0.025, (belt + H) * 0.5, L - fw * 0.5 + 0.003)), Vector3(0.05, H - belt, fw), WHITE, 0.015)
	EK.pane(gl, seal, Vector3(-s * 0.025, belt + 0.01, 0.006 + fw), Vector3(-s * 0.025, belt + 0.01, L - fw), Vector3(-s * 0.025, H - fw, L - fw), Vector3(-s * 0.025, H - fw, top0 + fw), Vector3(s, 0, 0))
	# outside: paddle handle in its chrome cup, the lock under it, belt moulding
	var hz := (FZ + 1.35) - DOOR_Z0
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(s * 0.004, 1.49 - SILL_Y, hz)), Vector3(0.012, 0.06, 0.16), CHROME, 0.01)
	k.box_at(Vector3(s * 0.008, 1.49 - SILL_Y - 0.008, hz), Vector3(0.006, 0.025, 0.12), BLACK)
	k.cylinder(Transform3D(Basis(Vector3.BACK, -s * PI * 0.5), Vector3(s * 0.002, 1.49 - SILL_Y - 0.08, hz - 0.03)), 0.014, 0.014, 0.01, 10, CHROME)
	k.box_at(Vector3(s * 0.003, belt - 0.01, L * 0.5), Vector3(0.006, 0.012, L - 0.02), CHROME.darkened(0.1))
	# inside: the tan door card (from the photo): arm rest, chrome pull bar,
	# window crank, lock knob, map pocket with the speaker grille
	var cx := -s * (th + 0.006)
	tr.box_at(Vector3(cx, belt * 0.5 + 0.03, L * 0.5), Vector3(0.01, belt - 0.06, L - 0.06), TAN)
	for sy in [0.18, 0.46]:
		tr.box_at(Vector3(cx - s * 0.004, float(sy), L * 0.5), Vector3(0.006, 0.012, L - 0.1), CHROME.darkened(0.25))
	tr.rbox(Transform3D(Basis.IDENTITY, Vector3(cx - s * 0.04, 0.58, L * 0.62)), Vector3(0.08, 0.06, 0.32), TAN_D, 0.02)
	tube(tr, [Vector3(cx - s * 0.03, 0.42, L * 0.82), Vector3(cx - s * 0.035, 0.66, L * 0.42)], 0.012, CHROME, 8)
	tr.cylinder(Transform3D(Basis(Vector3.BACK, s * PI * 0.5), Vector3(cx, 0.36, L * 0.38)), 0.02, 0.02, 0.03, 8, CHROME)
	tr.box_at(Vector3(cx - s * 0.04, 0.36, L * 0.38 + 0.05), Vector3(0.02, 0.02, 0.1), BLACK)
	tr.cylinder(Transform3D(Basis.IDENTITY, Vector3(cx - s * 0.02, belt - 0.005, L - 0.1)), 0.008, 0.006, 0.05, 6, BLACK)   # lock knob
	tr.rbox(Transform3D(Basis.IDENTITY, Vector3(cx - s * 0.03, 0.12, L * 0.6)), Vector3(0.05, 0.12, 0.34), TAN_D, 0.02)
	tr.box_at(Vector3(cx - s * 0.005, 0.12, L * 0.18), Vector3(0.006, 0.09, 0.1), BLACK)
	# west-coast mirror: tube frame from the door front, the big glass and
	# the round spot mirror under it
	var mk := MeshKit.new()
	var mo := Vector3(s * 0.34, 0, -0.06)
	var top := Vector3(s * 0.02, H - 0.05, rake + 0.03)
	var low := Vector3(s * 0.02, belt + 0.03, 0.03)
	tube(mk, [top, top + Vector3(s * 0.25, 0.0, -0.04), mo + Vector3(0, H - 0.05, 0)], 0.012, CHROME, 8)
	tube(mk, [low, low + Vector3(s * 0.25, 0.0, -0.04), mo + Vector3(0, belt + 0.03, 0)], 0.012, CHROME, 8)
	EK.rod(mk, mo + Vector3(0, belt + 0.03, 0), mo + Vector3(0, H - 0.05, 0), 0.012, CHROME, 8)
	var mc := mo + Vector3(s * 0.02, (belt + H) * 0.5 + 0.02, 0.0)
	mk.rbox(Transform3D(Basis.IDENTITY, mc), Vector3(0.04, 0.38, 0.18), BLACK, 0.015)
	mk.box_at(mc + Vector3(0, 0, 0.022), Vector3(0.03, 0.34, 0.006), Color(0.62, 0.68, 0.74))
	var sc := mo + Vector3(s * 0.0, belt - 0.1, 0.0)
	EK.rod(mk, mo + Vector3(0, belt + 0.03, 0), sc, 0.01, CHROME, 6)
	mk.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), sc + Vector3(0, 0, -0.02)), 0.075, 0.075, 0.035, 16, BLACK)
	mk.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), sc + Vector3(0, 0, 0.012)), 0.065, 0.065, 0.006, 16, Color(0.62, 0.68, 0.74))
	d.add_child(k.instance("Panel"))
	d.add_child(tr.instance("Card"))
	d.add_child(mk.instance("Mirror"))
	d.add_child(seal.instance("Seal"))
	_glass(d, gl, "Glass")
	doors.append([d, s])


# ------------------------------------------------------------------------------
#  Interior, from the photos: tan wrap-round dash, brushed cluster, the big
#  black two-spoke wheel, engine cover, high-back seats, tall shifter, the spray
#  control box on the floor between the seats, overhead box, visors
# ------------------------------------------------------------------------------
const FACE_TILT := 0.365          # the dash face leans in at the bottom

static func face_z(y: float) -> float:
	return COWL_Z + 0.02 + (y - 1.42) / 0.34 * 0.13


func _interior(t: Node3D) -> void:
	var k := MeshKit.new()
	var fy := FLOOR_Y
	k.box_at(Vector3(0, fy + 0.005, (FIREWALL_Z + CAB_BACK) * 0.5), Vector3(CAB_HW * 2.0 - 0.1, 0.01, CAB_BACK - FIREWALL_Z - 0.02), RUBBER)     # mat
	# engine cover (doghouse), tan, rounded, from the firewall back between the seats
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0.0, fy + 0.2, FIREWALL_Z + 0.3)), Vector3(0.66, 0.46, 0.62), TAN, 0.13)
	# the dash: a section along X - padded top behind the windscreen base,
	# the face leaning in toward the bottom, its underside forward to the firewall
	var rings: Array = []
	for xi in range(2):
		var x: float = -0.88 if xi == 0 else 0.88
		rings.append(PackedVector3Array([
			Vector3(x, 1.42, FIREWALL_Z + 0.01), Vector3(x, 1.42, face_z(1.42)), Vector3(x, 1.76, face_z(1.76)),
			Vector3(x, 1.81, COWL_Z + 0.14), Vector3(x, 1.84, COWL_Z + 0.10), Vector3(x, 1.85, COWL_Z + 0.03),
			Vector3(x, 1.69, COWL_Z - 0.01), Vector3(x, 1.66, FIREWALL_Z + 0.01)]))
	k.loft(rings, TAN, true, true)
	var fb := Basis(Vector3.RIGHT, FACE_TILT)
	var on_face := func(x: float, y: float, out: float = 0.004) -> Vector3: return Vector3(x, y, face_z(y)) + fb * Vector3(0, 0, out)
	# right side: two square louvred vents, the lower black panel
	for vx in [0.25, 0.70]:
		k.box(Transform3D(fb, on_face.call(float(vx), 1.66)), Vector3(0.16, 0.07, 0.01), BLACK)
		for vl in range(4):
			k.box(Transform3D(fb, on_face.call(float(vx), 1.635 + 0.017 * float(vl), 0.01)), Vector3(0.15, 0.004, 0.01), Color(0.2, 0.2, 0.2))
	k.box(Transform3D(fb, on_face.call(0.55, 1.50)), Vector3(0.6, 0.12, 0.01), Color(0.1, 0.1, 0.1))
	# the cluster pod in front of the driver: brushed panel tipped back to face
	# him (gauges are the Dash node), two warning windows and a round vent on top
	var tilt := 0.72
	var pb := Basis(Vector3.RIGHT, -tilt)
	var pod_c := Vector3(-0.50, 1.80, COWL_Z + 0.20)
	k.rbox(Transform3D(pb, pod_c + pb * Vector3(0, 0, -0.06)), Vector3(0.70, 0.32, 0.12), TAN, 0.03)
	k.box(Transform3D(pb, pod_c + pb * Vector3(0, 0, 0.002)), Vector3(0.64, 0.27, 0.01), BRUSHED)
	k.rbox(Transform3D(pb, pod_c + pb * Vector3(0, 0.165, -0.02)), Vector3(0.72, 0.035, 0.1), TAN_D, 0.015)   # brow
	for wx in [-0.13, 0.13]:
		k.box(Transform3D(pb, pod_c + pb * Vector3(float(wx), 0.095, 0.009)), Vector3(0.15, 0.045, 0.006), Color(0.06, 0.06, 0.06))
		k.box(Transform3D(pb, pod_c + pb * Vector3(float(wx), 0.095, 0.007)), Vector3(0.17, 0.06, 0.004), CHROME)
	k.cylinder(Transform3D(pb * Basis(Vector3.RIGHT, PI * 0.5), pod_c + pb * Vector3(0, 0.095, 0.002)), 0.03, 0.03, 0.012, 14, BLACK)
	# left knob panel: park brake (yellow diamond, push-pull), hand throttle, key
	var kp: Vector3 = on_face.call(-0.90, 1.60)
	k.box(Transform3D(fb, kp), Vector3(0.13, 0.22, 0.006), BRUSHED.darkened(0.2))
	park_knob = Node3D.new()
	park_knob.name = "ParkBrake"
	park_knob.transform = Transform3D(fb, kp + fb * Vector3(0, 0.06, 0.004))
	var pk := MeshKit.new()
	pk.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.008, 0.008, 0.05, 8, CHROME)
	pk.box(Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0, 0, 0.055)), Vector3(0.045, 0.045, 0.03), Color(0.95, 0.8, 0.1))
	park_knob.add_child(pk.instance("Knob"))
	park_knob.set_meta("control", "park")
	t.add_child(park_knob)
	k.cylinder(Transform3D(fb * Basis(Vector3.RIGHT, PI * 0.5), kp + fb * Vector3(0, -0.02, 0.0)), 0.006, 0.006, 0.05, 6, CHROME)
	k.box(Transform3D(fb, kp + fb * Vector3(0, -0.02, 0.05)), Vector3(0.05, 0.016, 0.016), BLACK)      # hand throttle T
	k.cylinder(Transform3D(fb * Basis(Vector3.RIGHT, PI * 0.5), kp + fb * Vector3(0, -0.08, 0.0)), 0.018, 0.018, 0.01, 10, CHROME)    # key
	k.box(Transform3D(fb, kp + fb * Vector3(0, -0.08, 0.02)), Vector3(0.008, 0.02, 0.03), Color(0.7, 0.65, 0.4))
	# right of the pod: switch panel with the heater levers
	var sp: Vector3 = on_face.call(-0.07, 1.62)
	k.box(Transform3D(fb, sp), Vector3(0.14, 0.2, 0.006), BRUSHED.darkened(0.2))
	for hl in range(3):
		k.box(Transform3D(fb, sp + fb * Vector3(-0.04 + 0.04 * float(hl), -0.03, 0.012)), Vector3(0.012, 0.02, 0.02), BLACK)
		k.box(Transform3D(fb, sp + fb * Vector3(-0.04 + 0.04 * float(hl), -0.03, 0.005)), Vector3(0.006, 0.09, 0.004), Color(0.1, 0.1, 0.1))
	# steering column into the dash and on down to the floor (the box on the
	# frame) and the big black two-spoke wheel, nearly flat
	var up := Vector3(0, sin(COL_TILT), cos(COL_TILT))         # along the column, up toward the driver
	var cbase := WHEEL_C - up * 0.95
	EK.rod(k, WHEEL_C - up * 0.03, cbase, 0.035, BLACK, 10)
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - COL_TILT), WHEEL_C - up * 0.2), 0.05, 0.045, 0.16, 12, BLACK)    # column shroud
	steer_wheel = Node3D.new()
	steer_wheel.name = "SteeringWheel"
	steer_wheel.position = WHEEL_C
	steer_wheel.basis = Basis(Vector3.RIGHT, PI * 0.5 - COL_TILT)      # local Y along the column, the rim in local XZ
	var wk := MeshKit.new()
	for sg in range(24):
		var a0 := TAU * float(sg) / 24.0
		var a1 := TAU * float(sg + 1) / 24.0
		EK.rod(wk, Vector3(cos(a0) * STEER_R, 0, sin(a0) * STEER_R), Vector3(cos(a1) * STEER_R, 0, sin(a1) * STEER_R), 0.017, BLACK, 8)
	# two spokes from the hub out to the far side (the V seen from the seat)
	for sa in [PI * 1.5 - 1.05, PI * 1.5 + 1.05]:
		EK.rod(wk, Vector3(0, 0.01, 0), Vector3(cos(float(sa)) * STEER_R, 0, sin(float(sa)) * STEER_R), 0.012, CHROME.darkened(0.3), 8)
	wk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0)), 0.065, 0.06, 0.05, 16, BLACK)
	wk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.025, 0)), 0.035, 0.035, 0.006, 16, Color(0.2, 0.3, 0.6))
	steer_wheel.add_child(wk.instance("Wheel"))
	t.add_child(steer_wheel)
	# pedals: clutch, brake, throttle, hung from under the dash
	for pd in [[-0.78, 0.07, 0.1], [-0.58, 0.07, 0.1], [-0.40, 0.06, 0.2]]:
		var pc := Vector3(float(pd[0]), fy + 0.14, FIREWALL_Z + 0.20)
		k.box(Transform3D(Basis(Vector3.RIGHT, -0.9), pc), Vector3(float(pd[1]), 0.012, float(pd[2])), BLACK)
		EK.rod(k, pc + Vector3(0, 0.03, -0.04), Vector3(float(pd[0]), 1.43, FIREWALL_Z + 0.12), 0.008, BLACK, 6)
	# shifter: up out of the floor behind the engine cover, tall, black knob;
	# a control (it moves)
	shifter = Node3D.new()
	shifter.name = "Shifter"
	shifter.position = Vector3(-0.05, fy + 0.01, FIREWALL_Z + 0.65)
	var sk := MeshKit.new()
	EK.rod(sk, Vector3.ZERO, Vector3(-0.04, 0.64, 0.12), 0.012, CHROME.darkened(0.3), 8)
	sk.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.04, 0.62, 0.12)), 0.034, 0.03, 0.08, 12, BLACK)
	sk.box_at(Vector3(-0.04, 0.69, 0.12), Vector3(0.02, 0.012, 0.04), Color(0.7, 0.7, 0.7))
	sk.cylinder(Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.07, 0.03, 0.1, 12, RUBBER)       # boot
	shifter.add_child(sk.instance("Lever"))
	shifter.set_meta("control", "shifter")
	t.add_child(shifter)
	# seats: high-back cloth buckets, two-tone with the tan band, on pedestals
	for sx in [-0.50, 0.52]:
		var sc := Vector3(float(sx), fy, SEAT_Z)
		k.box_at(sc + Vector3(0, 0.12, 0.02), Vector3(0.34, 0.24, 0.34), BLACK)                        # pedestal
		k.rbox(Transform3D(Basis.IDENTITY, sc + Vector3(0, 0.31, -0.04)), Vector3(0.52, 0.13, 0.50), CLOTH, 0.05)
		k.rbox(Transform3D(Basis.IDENTITY, sc + Vector3(0, 0.34, -0.04)), Vector3(0.36, 0.09, 0.42), CLOTH_D, 0.04)
		var bb := Basis(Vector3.RIGHT, 0.12)
		k.rbox(Transform3D(bb, sc + Vector3(0, 0.71, 0.17)), Vector3(0.52, 0.70, 0.13), CLOTH, 0.05)
		k.rbox(Transform3D(bb, sc + Vector3(0, 0.67, 0.12)), Vector3(0.36, 0.52, 0.06), CLOTH_D, 0.03)
		k.rbox(Transform3D(bb, sc + Vector3(0, 0.89, 0.135)), Vector3(0.53, 0.02, 0.13), TAN_D, 0.01)   # the tan band
	# spray control box on the floor between the seats: the PTO switch under
	# its red guard and a toggle for each spray head; the pump gauge
	var bc := Vector3(0, fy, SEAT_Z - 0.05)
	var bxb := Basis(Vector3.RIGHT, 0.5)
	var top_c := bc + Vector3(0, 0.27, -0.02)
	var slope := tan(0.5)
	var ty := func(z: float) -> float: return top_c.y - slope * (z - top_c.z)
	var z0 := bc.z - 0.17
	var z1 := bc.z + 0.17
	var wr: Array = []
	for bx in [-0.12, 0.12]:
		var x: float = bx
		wr.append(PackedVector3Array([Vector3(x, fy, z0), Vector3(x, ty.call(z0), z0), Vector3(x, ty.call(z1), z1), Vector3(x, fy, z1)]))
	k.loft(wr, BLACK, true, true)
	k.box(Transform3D(bxb, top_c + bxb * Vector3(0, 0.002, 0)), Vector3(0.22, 0.004, 0.3), Color(0.2, 0.2, 0.21))
	# top row: PTO, the hose reel's valve, the front sprays; bottom: side and rear
	var names := ["pto", "reel_valve", "valve_0", "valve_1", "valve_2", "valve_3", "valve_4"]
	var labels := ["PTO", "REEL", "FR L", "FR R", "SIDE", "RR L", "RR R"]
	for i in range(names.size()):
		var at: Vector3 = top_c + bxb * Vector3(-0.075 + 0.05 * float(i % 4), 0.004, 0.0 + 0.08 * float(i / 4))
		var sw := Node3D.new()
		sw.name = "Switch_" + String(names[i])
		sw.transform = Transform3D(bxb, at)
		var swk := MeshKit.new()
		swk.cylinder(Transform3D.IDENTITY, 0.012, 0.012, 0.008, 8, CHROME)
		var lev := Node3D.new()
		lev.name = "Lever"
		var lk := MeshKit.new()
		lk.cylinder(Transform3D.IDENTITY, 0.004, 0.003, 0.035, 6, CHROME)
		lev.add_child(lk.instance("Bat"))
		sw.add_child(lev)
		if i == 0:
			swk.box_at(Vector3(0, 0.02, -0.022), Vector3(0.03, 0.04, 0.006), RED)       # guard
		sw.add_child(swk.instance("Base"))
		sw.set_meta("control", String(names[i]))
		t.add_child(sw)
		cab_switches[String(names[i])] = lev
		EK.decal(t, labels[i], at + bxb * Vector3(0, 0.002, 0.028), bxb * Vector3.UP, 0.0006, Color(0.9, 0.9, 0.85))
	box_dash = Dash.new()
	box_dash.name = "BoxGauge"
	box_dash.transform = Transform3D(bxb * Basis(Vector3.RIGHT, -PI * 0.5), top_c + bxb * Vector3(0, 0.018, -0.1))      # face clear of the top plate
	t.add_child(box_dash)
	# overhead box at the right, dome lamp, sun visors
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0.45, ROOF_Y - 0.19, COWL_Z + 0.32)), Vector3(0.6, 0.1, 0.28), TAN, 0.03)
	k.box_at(Vector3(0.45, ROOF_Y - 0.19, COWL_Z + 0.465), Vector3(0.5, 0.06, 0.01), BLACK)
	k.box_at(Vector3(0, ROOF_Y - 0.14, CAB_BACK - 0.35), Vector3(0.2, 0.025, 0.1), Color(0.95, 0.93, 0.85))
	for vx2 in [-0.5, 0.05]:
		k.rbox(Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(float(vx2), ROOF_Y - 0.2, COWL_Z + 0.2)), Vector3(0.5, 0.16, 0.025), TAN, 0.01)
	t.add_child(k.instance("Interior"))
	# gauges: tach left, speedo right, two small each side (from the photo)
	dash = Dash.new()
	dash.name = "Dash"
	t.add_child(dash)
	dash.transform = Transform3D(pb, pod_c + pb * Vector3(0, -0.02, 0.022))      # faces sit 0.012 behind the dash plane: out in front of the brushed plate (0.007)


# ------------------------------------------------------------------------------
#  The tank: modified ellipse (narrower at the bottom), flat heads with a
#  knuckle radius, girth seams, manway on top; side skirts on outriggers
# ------------------------------------------------------------------------------
static func tank_ring(z: float, inset: float, n: int = 40) -> PackedVector3Array:
	var ring := PackedVector3Array()
	var cy := (TANK_TOP + TANK_BOT) * 0.5
	var hh := (TANK_TOP - TANK_BOT) * 0.5 - inset
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var c := cos(a)
		var s := sin(a)
		var e := 2.0 / 2.6
		var y := hh * signf(s) * pow(absf(s), e)
		var hw := lerpf(1.06, TANK_HW, (y / maxf(hh, 0.01)) * 0.5 + 0.5) - inset
		ring.append(Vector3(hw * signf(c) * pow(absf(c), e), cy + y, z))
	return ring


func _tank(t: Node3D, fuel: bool) -> void:
	var k := MeshKit.new()
	var col := tank_mat_col
	var kr := 0.09
	var rings: Array = []
	var steps := [[0.0, 1.0], [0.012, 0.6], [0.035, 0.3], [kr, 0.0]]
	for st in steps:
		rings.append(tank_ring(TANK_Z0 + float(st[0]), kr * float(st[1])))
	for i in range(steps.size() - 1, -1, -1):
		rings.append(tank_ring(TANK_Z1 - float(steps[i][0]), kr * float(steps[i][1])))
	k.loft(rings, col, true, true)
	k.smooth(30.0)
	t.add_child(k.instance("Tank"))
	var d := MeshKit.new()
	# girth seams
	for sz in [TANK_Z0 + 0.92, TANK_Z0 + 1.80]:
		var r0 := tank_ring(float(sz) - 0.012, -0.004)
		var r1 := tank_ring(float(sz) + 0.012, -0.004)
		d.loft([r0, r1], col.darkened(0.06), false, false)
	# rear head seam (vertical, the photo)
	d.box_at(Vector3(0, (TANK_TOP + TANK_BOT) * 0.5, TANK_Z1 + 0.004), Vector3(0.02, TANK_TOP - TANK_BOT - 0.15, 0.006), col.darkened(0.06))
	# manway on top: raised rim, the lid with its hinge and two latches
	var mz := FZ + 2.81
	d.rbox(Transform3D(Basis.IDENTITY, Vector3(0, TANK_TOP + 0.02, mz)), Vector3(0.62, 0.1, 0.67), col, 0.03)
	d.rbox(Transform3D(Basis.IDENTITY, Vector3(0, TANK_TOP + 0.08, mz)), Vector3(0.56, 0.03, 0.6), col.darkened(0.05), 0.02)
	d.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.3, TANK_TOP + 0.08, mz - 0.25)), 0.015, 0.015, 0.6, 8, STEEL)
	for lx in [-0.2, 0.2]:
		d.box_at(Vector3(float(lx), TANK_TOP + 0.08, mz + 0.31), Vector3(0.05, 0.03, 0.04), STEEL)
	# subframe sills on the rails, saddle pads under the tank, outriggers to
	# the skirts
	for s in [-1.0, 1.0]:
		var sx: float = s
		d.box_at(Vector3(sx * RAIL_X - sx * 0.04, RAIL_TOP + 0.06, (TANK_Z0 + FRAME_Z1) * 0.5), Vector3(0.09, 0.12, FRAME_Z1 - TANK_Z0), FRAME)
		for oz in [TANK_Z0 + 0.1, TANK_Z0 + 1.0, RZ - 0.72, FRAME_Z1 - 0.1]:
			d.box_at(Vector3(sx * (RAIL_X + 0.32), RAIL_TOP + 0.10, float(oz)), Vector3(0.66, 0.1, 0.08), FRAME)
			d.box_at(Vector3(sx * (RAIL_X + 0.1), RAIL_TOP + 0.15, float(oz)), Vector3(0.3, 0.06, 0.1), FRAME)     # saddle pad up to the shell
		# skirt: white box sill from the cab to the back, its bottom edge
		# arched over the duals, amber lamp at the front, red at the back
		var sk := MeshKit.new()
		var zs: Array = []
		var n := 30
		for i in range(n + 1):
			zs.append(TANK_Z0 + 0.04 + (FRAME_Z1 - 0.08 - TANK_Z0 - 0.04) * float(i) / float(n))
		var rs: Array = []
		for zq in zs:
			var z: float = zq
			var dz := z - RZ
			var bot := SKIRT_Y0
			if absf(dz) < 0.66:
				bot = maxf(bot, WR + sqrt(0.66 * 0.66 - dz * dz) + 0.0)
			bot = minf(bot, SKIRT_Y1 - 0.05)
			var ring := PackedVector3Array([Vector3(sx * 1.03, bot, z), Vector3(sx * 1.03, SKIRT_Y1, z), Vector3(sx * 1.155, SKIRT_Y1, z), Vector3(sx * 1.165, SKIRT_Y1 - 0.02, z), Vector3(sx * 1.165, bot, z)])
			if sx < 0.0:
				ring.reverse()
			rs.append(ring)
		sk.loft(rs, col, true, true)
		t.add_child(sk.instance("Skirt"))
		var lk := MeshKit.new()
		EK.lamp(d, lk, t, Vector3(sx * 1.12, SKIRT_Y1 - 0.09, TANK_Z0 + 0.03), Vector3(0, 0, -1), 0.06, 0.05, AMBER, false)
		EK.lamp(d, lk, t, Vector3(sx * 1.17, SKIRT_Y1 - 0.09, TANK_Z0 + 0.15), Vector3(sx, 0, 0), 0.06, 0.05, AMBER, true)
		EK.lamp(d, lk, t, Vector3(sx * 1.17, SKIRT_Y1 - 0.09, FRAME_Z1 - 0.2), Vector3(sx, 0, 0), 0.06, 0.05, RED, true)
		t.add_child(lk.instance("SkirtLamps"))
	t.add_child(d.instance("TankFittings"))


# ------------------------------------------------------------------------------
#  Water: the PTO shaft back to the pump under the front of the tank, the
#  suction from the sump, the discharge manifold, lines along the right rail
#  to the front bar and the rear bar, air-operated valves at the heads
# ------------------------------------------------------------------------------
const PUMP := Vector3(0.20, 0.86, TANK_Z0 + 0.26)
const HEAD_FL := Vector3(-1.12, 0.50, BUMP_Z - 0.06)
const HEAD_FR := Vector3(1.12, 0.50, BUMP_Z - 0.06)
const HEAD_SIDE := Vector3(1.10, 0.92, 0.40)
const HEAD_RL := Vector3(-0.98, 0.92, FRAME_Z1 + 0.12)
const HEAD_RR := Vector3(0.98, 0.92, FRAME_Z1 + 0.12)


func _plumbing(t: Node3D, fuel: bool) -> void:
	var k := MeshKit.new()
	var pipe := Color(0.12, 0.12, 0.13)
	# PTO shaft (it turns while the pump's in): PTO output to the pump's drive
	var pto_out := Vector3(0.24, 0.80, COWL_Z + 0.04 + 0.52)
	pump_shaft = _link_rod(t, 0.022, "PumpShaft")
	lay(pump_shaft, pto_out, PUMP + Vector3(0, 0, -0.12))
	# the pump: volute, eye, mounting bracket to the crossmember
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), PUMP + Vector3(0, 0, -0.08)), 0.14, 0.14, 0.13, 20, PUMP_RED)
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), PUMP + Vector3(0, 0, -0.14)), 0.07, 0.07, 0.06, 12, PUMP_RED)
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), PUMP + Vector3(0, 0, 0.05)), 0.08, 0.08, 0.06, 12, PUMP_RED)       # suction eye
	k.box_at(Vector3(0.30, 1.005, PUMP.z - 0.02), Vector3(0.2, 0.03, 0.1), FRAME)                                             # bracket to the rail
	k.box_at(Vector3(0.39, 0.98, PUMP.z - 0.02), Vector3(0.04, 0.06, 0.1), FRAME)
	# suction: from the sump under the tank down into the pump's eye
	var sump := Vector3(0, TANK_BOT + 0.02, PUMP.z + 0.3)
	k.cylinder(Transform3D(Basis.IDENTITY, sump - Vector3(0, 0.06, 0)), 0.11, 0.11, 0.08, 14, col_dark())
	tube(k, [sump - Vector3(0, 0.06, 0), Vector3(0, 1.0, sump.z), Vector3(0.2, 0.95, sump.z - 0.05), Vector3(0.2, 0.88, PUMP.z + 0.2), PUMP + Vector3(0, 0, 0.11)], 0.06, pipe)
	# discharge: out of the volute at the top right to the manifold by the rail
	var man := Vector3(0.36, 0.70, PUMP.z - 0.08)
	tube(k, [PUMP + Vector3(0.1, -0.1, -0.08), Vector3(0.3, 0.70, PUMP.z - 0.08), man], 0.045, pipe)
	k.rbox(Transform3D(Basis.IDENTITY, man), Vector3(0.12, 0.12, 0.16), pipe, 0.02)
	# front line: along the inside of the right rail, down past the engine to
	# the riser behind the bumper, the bar across the bumper face
	var fx := 0.30
	tube(k, [man + Vector3(0, 0, -0.08), Vector3(fx, 0.68, man.z - 0.3), Vector3(fx, 0.68, FZ + 0.5), Vector3(fx, 0.68, BUMP_Z + 0.10), Vector3(0.6, 0.66, BUMP_Z + 0.06), Vector3(0.6, 0.62, BUMP_Z - 0.05)], 0.035, pipe)
	tube(k, [Vector3(HEAD_FL.x + 0.03, 0.62, BUMP_Z - 0.05), Vector3(HEAD_FR.x - 0.03, 0.62, BUMP_Z - 0.05)], 0.038, pipe)
	for hx in [HEAD_FL, HEAD_FR]:
		var h: Vector3 = hx
		tube(k, [Vector3(h.x - signf(h.x) * 0.03, 0.62, BUMP_Z - 0.05), Vector3(h.x, 0.62, BUMP_Z - 0.05), h + Vector3(0, 0.05, 0)], 0.038, pipe)
	# side head: a tee off the rear line out under the right skirt
	var rx := RAIL_X + 0.06
	tube(k, [man + Vector3(0, 0, 0.08), Vector3(rx, 0.70, man.z + 0.2), Vector3(rx, 0.86, man.z + 0.45), Vector3(rx, 0.86, FRAME_Z1 - 0.05), Vector3(rx, 0.90, FRAME_Z1 + 0.12)], 0.04, pipe)
	tube(k, [Vector3(rx, 0.86, HEAD_SIDE.z), Vector3(rx + 0.2, 0.90, HEAD_SIDE.z), HEAD_SIDE + Vector3(-0.05, 0, 0)], 0.03, pipe)
	# rear bar across under the tank
	tube(k, [Vector3(HEAD_RL.x + 0.05, 0.90, FRAME_Z1 + 0.12), Vector3(HEAD_RR.x - 0.05, 0.90, FRAME_Z1 + 0.12)], 0.04, pipe)
	# the heads: valve body, its air cylinder, the fan nozzle (water truck only)
	if not fuel:
		for hd in [[HEAD_FL, Vector3(-0.4, -1, -0.6)], [HEAD_FR, Vector3(0.4, -1, -0.6)], [HEAD_SIDE, Vector3(1, -0.7, 0)], [HEAD_RL, Vector3(-0.4, -1, 0.6)], [HEAD_RR, Vector3(0.4, -1, 0.6)]]:
			var p: Vector3 = hd[0]
			var dir: Vector3 = (hd[1] as Vector3).normalized()
			k.rbox(Transform3D(Basis.IDENTITY, p), Vector3(0.09, 0.08, 0.09), STEEL, 0.02)
			k.cylinder(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.04, 0)), 0.03, 0.03, 0.07, 10, PUMP_RED)
			EK.rod(k, p, p + dir * 0.09, 0.025, STEEL, 8)
			k.box(Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD), p + dir * 0.11), Vector3(0.1, 0.02, 0.03), BLACK)
	t.add_child(k.instance("Plumbing"))


static func col_dark() -> Color:
	return Color(0.15, 0.15, 0.16)


# ------------------------------------------------------------------------------
#  Under the cab: the fuel tank (left) with its step, battery box (right)
#  with its step, the muffler and tail pipe, air tanks
# ------------------------------------------------------------------------------
func _under(t: Node3D) -> void:
	var k := MeshKit.new()
	# fuel tank: rounded box on two straps hung from the rail, cap on top,
	# tread plate on top as the upper step, a grate step under it
	var fz0 := FZ + 1.10
	var fz1 := FZ + 2.05
	var fc := Vector3(-0.85, 0.70, (fz0 + fz1) * 0.5)
	k.rbox(Transform3D(Basis.IDENTITY, fc), Vector3(0.62, 0.48, fz1 - fz0), BLACK.lightened(0.04), 0.08)
	for sz in [fz0 + 0.18, fz1 - 0.18]:
		var szf: float = sz
		k.rbox(Transform3D(Basis.IDENTITY, Vector3(fc.x, fc.y, szf)), Vector3(0.635, 0.495, 0.04), STEEL.darkened(0.3), 0.08)
		k.box_at(Vector3(-RAIL_X - 0.05, fc.y + 0.08, szf), Vector3(0.1, 0.36, 0.06), FRAME)     # hanger off the rail
	k.box_at(Vector3(fc.x, 0.95, fz0 + 0.28), Vector3(0.6, 0.012, 0.48), STEEL)                    # tread plate
	for tp in range(8):
		k.box(Transform3D(Basis(Vector3.UP, 0.6), Vector3(fc.x - 0.24 + 0.065 * float(tp), 0.958, fz0 + 0.28)), Vector3(0.05, 0.006, 0.012), STEEL.lightened(0.1))
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(fc.x - 0.05, 0.94, fz1 - 0.15)), 0.05, 0.05, 0.04, 12, CHROME.darkened(0.2))
	EK.grate_step(k, Vector3(-1.02, 0.40, fz0 + 0.30), 0.28, 0.5, 0.0)
	for gz in [fz0 + 0.1, fz0 + 0.5]:
		k.box_at(Vector3(-0.9, 0.42, float(gz)), Vector3(0.24, 0.03, 0.04), FRAME)                   # step hangers under the tank
		k.box_at(Vector3(-0.78, 0.47, float(gz)), Vector3(0.03, 0.1, 0.04), FRAME)
	# battery box, right, with its lid as the upper step and a grate step under
	var bz0 := FZ + 1.05
	var bz1 := FZ + 1.60
	var bc := Vector3(0.84, 0.72, (bz0 + bz1) * 0.5)
	k.rbox(Transform3D(Basis.IDENTITY, bc), Vector3(0.58, 0.42, bz1 - bz0), BLACK, 0.03)
	k.rbox(Transform3D(Basis.IDENTITY, bc + Vector3(0, 0.22, 0)), Vector3(0.6, 0.03, bz1 - bz0 + 0.02), STEEL, 0.01)
	for bl in [bz0 + 0.12, bz1 - 0.12]:
		k.box_at(Vector3(1.135, 0.82, float(bl)), Vector3(0.012, 0.05, 0.06), STEEL)                  # latches
	k.box_at(Vector3(RAIL_X + 0.06, 0.78, bc.z), Vector3(0.12, 0.3, 0.4), FRAME)
	EK.grate_step(k, Vector3(1.0, 0.40, bc.z), 0.28, 0.45, 0.0)
	k.box_at(Vector3(0.88, 0.45, bc.z), Vector3(0.24, 0.03, 0.05), FRAME)
	# muffler and tail pipe, right, behind the battery box: out to the side
	var mz0 := bz1 + 0.06
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.75, 0.70, mz0)), 0.14, 0.14, 0.75, 16, Color(0.3, 0.28, 0.26))
	for mb in [mz0 + 0.12, mz0 + 0.62]:
		k.box_at(Vector3(0.6, 0.78, float(mb)), Vector3(0.2, 0.04, 0.04), FRAME)
	tube(k, [Vector3(0.48, 0.72, COWL_Z + 0.24), Vector3(0.62, 0.70, mz0 - 0.1), Vector3(0.75, 0.70, mz0)], 0.05, Color(0.3, 0.28, 0.26))
	tailpipe_tip = Vector3(1.06, 0.50, mz0 + 0.95)
	tube(k, [Vector3(0.75, 0.70, mz0 + 0.75), Vector3(0.75, 0.68, mz0 + 0.85), tailpipe_tip], 0.045, Color(0.3, 0.28, 0.26))
	# air tanks on the left, behind the fuel tank, on their straps
	for ay in [0.84, 0.58]:
		var y: float = ay
		k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.72, y, fz1 + 0.1)), 0.12, 0.12, 0.6, 14, STEEL)
		for st in [fz1 + 0.2, fz1 + 0.6]:
			k.box_at(Vector3(-0.72, y + 0.125, float(st)), Vector3(0.18, 0.01, 0.03), FRAME)
	for st2 in [fz1 + 0.2, fz1 + 0.6]:
		k.box_at(Vector3(-0.61, 0.83, float(st2)), Vector3(0.02, 0.44, 0.03), FRAME)               # hanger strap off the rail
		k.box_at(Vector3(-0.52, 1.0, float(st2)), Vector3(0.18, 0.02, 0.03), FRAME)
	t.add_child(k.instance("Under"))


# ------------------------------------------------------------------------------
#  Rear: ladder up the head with its hoops, the three ID lamps, the fill pipe
#  over the top with the black hose looped down to the rear bar, light boxes,
#  centre bumper box, mud flaps, the pump control box
# ------------------------------------------------------------------------------
const PUMP_BOX := Vector3(1.02, 0.95, FRAME_Z1 - 0.01)
const HOSE_HANG := Vector3(0.62, 1.30, FRAME_Z1 + 0.16)

func _rear(t: Node3D, fuel: bool) -> void:
	var k := MeshKit.new()
	var lk := MeshKit.new()
	var col := tank_mat_col
	var hz := TANK_Z1 + 0.10
	# ladder: two rails standing off the head, hoops over the top edge, flat rungs
	for lx in [-0.20, 0.24]:
		var x: float = lx
		tube(k, [Vector3(x, 1.68, TANK_Z1 + 0.01), Vector3(x, 1.70, hz), Vector3(x, TANK_TOP + 0.02, hz), Vector3(x, TANK_TOP + 0.30, hz - 0.02), Vector3(x, TANK_TOP + 0.32, hz - 0.14), Vector3(x, TANK_TOP + 0.02, hz - 0.3)], 0.021, col, 8)
		for by in [1.95, 2.25]:
			k.box_at(Vector3(x, float(by), (TANK_Z1 + hz) * 0.5), Vector3(0.03, 0.03, hz - TANK_Z1), col)     # standoffs
	for ry in [1.76, 2.02, 2.28]:
		EK.grate_step(k, Vector3(0.02, float(ry), hz - 0.06), 0.42, 0.13, 0.0)
	# ID lamps: three red on a bar at the top of the head
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0.02, TANK_TOP - 0.06, TANK_Z1 + 0.02)), Vector3(0.36, 0.09, 0.04), col, 0.01)
	for ix in [-0.1, 0.02, 0.14]:
		EK.lamp(k, lk, t, Vector3(float(ix), TANK_TOP - 0.06, TANK_Z1 + 0.05), Vector3(0, 0, 1), 0.06, 0.06, RED, true)
	if not fuel:
		# fill pipe up out of the top at the right, over the edge, down the
		# head to its cam-lock coupling; the black hose looped to the rear bar
		var fx := 0.56
		tube(k, [Vector3(fx, TANK_TOP - 0.02, TANK_Z1 - 0.25), Vector3(fx, TANK_TOP + 0.12, TANK_Z1 - 0.2), Vector3(fx, TANK_TOP + 0.12, TANK_Z1 + 0.06), Vector3(fx, TANK_TOP - 0.05, TANK_Z1 + 0.09), Vector3(fx, 1.86, TANK_Z1 + 0.09)], 0.05, col, 12)
		k.cylinder(Transform3D(Basis.IDENTITY, Vector3(fx, 1.78, TANK_Z1 + 0.09)), 0.065, 0.065, 0.09, 12, BLACK)
		for cb in [-0.08, 0.08]:
			k.box_at(Vector3(fx, 1.86, TANK_Z1 + 0.04), Vector3(0.03, 0.03, 0.08), col)      # pipe clamps to the head
		tube(k, [Vector3(fx, 1.78, TANK_Z1 + 0.09), Vector3(fx + 0.02, 1.55, TANK_Z1 + 0.16), HOSE_HANG, Vector3(0.70, 1.05, FRAME_Z1 + 0.17), Vector3(0.80, 0.94, FRAME_Z1 + 0.13), Vector3(HEAD_RR.x - 0.05, 0.92, FRAME_Z1 + 0.12)], 0.045, RUBBER, 10)
	# light boxes each side (red tail / stop, white back-up) and the centre
	# bumper box with its tread plate top, on brackets off the rails
	for s in [-1.0, 1.0]:
		var sx: float = s
		var lc := Vector3(sx * 0.66, 0.73, FRAME_Z1 + 0.13)
		k.rbox(Transform3D(Basis.IDENTITY, lc), Vector3(0.42, 0.22, 0.16), BLACK, 0.015)
		k.box_at(Vector3(sx * (RAIL_X + 0.02), 0.80, FRAME_Z1 + 0.04), Vector3(0.06, 0.12, 0.12), FRAME)
		EK.lamp(k, lk, t, lc + Vector3(sx * 0.10, 0, 0.082), Vector3(0, 0, 1), 0.1, 0.1, RED, true)
		EK.lamp(k, lk, t, lc + Vector3(-sx * 0.08, 0, 0.082), Vector3(0, 0, 1), 0.075, 0.075, Color(1, 1, 0.95), true)
		# mud flap behind the duals on its bar
		var mz := RZ + 0.62
		k.box_at(Vector3(sx * 0.93, 0.62, mz), Vector3(0.6, 0.66, 0.012), RUBBER)
		k.box_at(Vector3(sx * 0.93, 0.97, mz), Vector3(0.62, 0.05, 0.05), STEEL)
		k.box_at(Vector3(sx * (RAIL_X + 0.08), 0.97, mz), Vector3(0.16, 0.06, 0.06), FRAME)
	# D-rings on brackets under the frame ends (winch points)
	for sd in [-1.0, 1.0]:
		var dp := Vector3(float(sd) * 0.49, 0.66, FRAME_Z1 - 0.03)
		k.box_at(Vector3(float(sd) * 0.46, 0.735, dp.z), Vector3(0.06, 0.05, 0.07), RED)        # bracket on the rail's web
		for da in range(8):
			var b0 := PI * float(da) / 8.0
			var b1 := PI * float(da + 1) / 8.0
			EK.rod(k, dp + Vector3(0, -sin(b0) * 0.05 + 0.04, cos(b0) * 0.045), dp + Vector3(0, -sin(b1) * 0.05 + 0.04, cos(b1) * 0.045), 0.011, RED.darkened(0.1), 6)
	k.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.58, FRAME_Z1 + 0.11)), Vector3(0.84, 0.36, 0.30), BLACK, 0.02)
	k.box_at(Vector3(0, 0.765, FRAME_Z1 + 0.11), Vector3(0.84, 0.012, 0.3), STEEL)
	# the pump control box on the right, under the back of the skirt
	k.rbox(Transform3D(Basis.IDENTITY, PUMP_BOX), Vector3(0.12, 0.2, 0.16), BLACK, 0.015)
	t.add_child(k.instance("Rear"))
	t.add_child(lk.instance("RearLamps"))


# ------------------------------------------------------------------------------
#  Wheels: hub-piloted discs, singles in front (on the knuckles), duals behind
# ------------------------------------------------------------------------------
func wheels(t: Node3D, r: float, w: float, tread: String) -> void:
	for wn in wheel_nodes:
		(wn[0] as Node).queue_free()
	wheel_nodes.clear()
	for wz in [FZ, RZ]:
		for wx in [-1.0, 1.0]:
			var front: bool = wz == FZ
			var n := Node3D.new()
			n.name = "WheelSteer" if front else "WheelRear"
			n.position = Vector3(float(wx) * (FRONT_TRACK if front else REAR_TRACK), r, float(wz))
			t.add_child(n)
			var spin := Node3D.new()
			spin.name = "Spin"
			n.add_child(spin)
			var duals: Array = [0.0] if (front or tread == "flot") else [-DUAL, DUAL]
			var mi := MeshInstance3D.new()
			mi.name = "Wheel"
			mi.mesh = TyreMesh.wheel(r, w, 0.286 if r < 0.545 else 0.31, tread, "disc", float(wx), duals, "", ALU if front else Color(0.82, 0.82, 0.8))
			spin.add_child(mi)
			wheel_nodes.append([n, front, spin])


# ------------------------------------------------------------------------------
#  Each frame: wheels, axles riding the springs, the steering linkage, the
#  steering wheel, the shafts
# ------------------------------------------------------------------------------
func pose(t: Node3D, body, r: float, steer: float, spins: Array, comps: Array, travel: float) -> void:
	var lift := [0.0, 0.0, 0.0, 0.0]
	for i in range(wheel_nodes.size()):
		var comp: float = float(comps[i]) if i < comps.size() else 0.45
		var wn: Node3D = wheel_nodes[i][0]
		var front: bool = wheel_nodes[i][1]
		# up as far as the springs go before they meet the rails (the bump stops)
		lift[i] = clampf((comp - 0.45) * travel, -0.10, 0.055 if front else 0.015)
		wn.position.y = r + float(lift[i])
		wn.rotation = Vector3(0, steer if front else 0.0, 0)
		(wheel_nodes[i][2] as Node3D).rotation.x = -float(spins[i]) if i < spins.size() else 0.0
	# axles: up and down with their wheels, rolled by the difference
	var fl: float = (float(lift[0]) + float(lift[1])) * 0.5
	var rl: float = (float(lift[2]) + float(lift[3])) * 0.5
	front_axle.position = Vector3(0, r + fl, FZ)
	front_axle.rotation = Vector3(0, 0, atan2(float(lift[1]) - float(lift[0]), FRONT_TRACK * 2.0))
	rear_axle.position = Vector3(0, r + rl, RZ)
	rear_axle.rotation = Vector3(0, 0, atan2(float(lift[3]) - float(lift[2]), REAR_TRACK * 2.0))
	for kn in knuckles:
		(kn[0] as Node3D).rotation = Vector3(0, steer, 0)
	# spring halves: from the hanger pin to the seat on the axle
	for sp in springs:
		var n: Node3D = sp[0]
		var pin: Vector3 = sp[1]
		var ax: Node3D = sp[3]
		var seat: Vector3 = ax.transform * (sp[2] as Vector3)
		seat.z = ax.position.z + (0.11 if pin.z > ax.position.z else -0.11)
		lay(n, pin, seat)
		n.basis = Basis(n.basis.x, n.basis.y, n.basis.z)
	# shocks: barrel hangs from the frame, rod from the axle, each aimed at the other
	for sh in shocks:
		var top: Vector3 = sh[2]
		var ax2: Node3D = sh[3]
		var bot: Vector3 = ax2.transform * (sh[4] as Vector3)
		_aim(sh[0], top, bot)
		_aim(sh[1], bot, top)
	# steering: tie rod between the arm ends, drag link from the pitman arm
	var arm := func(side: int) -> Vector3:
		var kn2: Node3D = knuckles[side][0]
		return front_axle.transform * (kn2.transform * Vector3(-float(knuckles[side][1]) * 0.02, -0.05, 0.28))
	lay(tie_rod, front_axle.transform.affine_inverse() * arm.call(0), front_axle.transform.affine_inverse() * arm.call(1))
	pitman.rotation = Vector3(steer * 0.8, 0, 0)
	var pit := pitman.transform * Vector3(-0.04, -0.19, 0)
	var top_arm: Vector3 = front_axle.transform * ((knuckles[0][0] as Node3D).transform * Vector3(-0.02, 0.17, 0.18))
	lay(drag_link, pit, top_arm)
	steer_wheel.basis = Basis(Vector3.RIGHT, -(PI * 0.5 - COL_TILT)) * Basis(Vector3.UP, -steer * 6.0)
	# rear driveshaft: carrier to the pinion
	lay(shaft2, Vector3(0, 0.74, TANK_Z0 + 0.95), rear_axle.transform * Vector3(0, 0.03, -0.35))


static func _aim(n: Node3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	if d.length() < 0.001:
		return
	var z := d.normalized()
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	n.transform = Transform3D(Basis(x, z.cross(x), z), from)


# ------------------------------------------------------------------------------
#  Hose reel and the pump valve (Dave; from photos of water-truck rear decks):
#  a tread-plate deck on two channels off the frame ends, the hand-crank reel
#  (spoked flanges, drum, red 1-1/2" hose, crank with its wooden grip, swivel
#  inlet), the hose out through a roller guide at the back edge. The feed rises
#  from the rear line through the deck to the butterfly valve (round body,
#  notched plate, lever: up = open), then over to the reel's swivel.
# ------------------------------------------------------------------------------
## Winch points (Dave: every vehicle gets them): somewhere a winch hook or a
## tow strap goes. [name, point in the truck's frame]
const WINCH_POINTS := [
	["front left tow hook", Vector3(-0.36, 0.45, BUMP_Z + 0.03)],
	["front right tow hook", Vector3(0.36, 0.45, BUMP_Z + 0.03)],
	["rear left D-ring", Vector3(-0.49, 0.64, FRAME_Z1 - 0.03)],
	["rear right D-ring", Vector3(0.49, 0.64, FRAME_Z1 - 0.03)],
]

const DECK_Y := 1.015
const DECK_Z0 := FRAME_Z1 + 0.01
const DECK_Z1 := FRAME_Z1 + 0.53
const REEL_C := Vector3(0, 1.31, FRAME_Z1 + 0.27)
const REEL_OUT := Vector3(0, 1.12, DECK_Z1 + 0.08)     # the roller guide, out past the deck's toe rail on its side plates
const WOUND_STEPS := 528                 # the hose on the drum: 2 layers x 11 turns x 24 steps, in the order it winds on
const WOUND_PIECE := 12                  # drawn in half turns


## A point on the hose wound on the drum (drum frame), u = 0..WOUND_STEPS along
## it in the order it winds on: inner layer across, outer layer back.
static func wound_local(u: float) -> Vector3:
	var layer := 0 if u < 264.0 else 1
	var i := u - 264.0 * float(layer)
	var lr := 0.115 + 0.022 + 0.044 * float(layer)
	var a := TAU * u / 24.0
	var x := -0.22 + 0.44 * i / 264.0 if layer == 0 else 0.22 - 0.44 * i / 264.0
	return Vector3(x, sin(a) * lr, cos(a) * lr)
const VALVE_C := Vector3(0.49, 1.09, FRAME_Z1 + 0.17)

func _reel(t: Node3D, fuel: bool) -> void:
	var k := MeshKit.new()
	var red := Color(0.20, 0.21, 0.23)        # the reel: charcoal powder coat (the hose is red, so it reads apart from it)
	var hose_col := Color(0.62, 0.10, 0.08) if not fuel else Color(0.08, 0.08, 0.08)
	var pipe := Color(0.12, 0.12, 0.13)
	# deck: tread plate, toe rail at the back, two channels, diagonal braces
	k.box_at(Vector3(0, DECK_Y - 0.01, (DECK_Z0 + DECK_Z1) * 0.5), Vector3(1.1, 0.012, DECK_Z1 - DECK_Z0), STEEL)
	for tp in range(9):
		for tq in range(5):
			k.box(Transform3D(Basis(Vector3.UP, 0.6 if (tp + tq) % 2 == 0 else -0.6), Vector3(-0.48 + 0.12 * float(tp), DECK_Y - 0.002, DECK_Z0 + 0.06 + 0.1 * float(tq))), Vector3(0.05, 0.005, 0.012), STEEL.lightened(0.12))
	k.box_at(Vector3(0, DECK_Y + 0.03, DECK_Z1 - 0.01), Vector3(1.1, 0.06, 0.012), STEEL)
	for sx in [-1.0, 1.0]:
		var cx: float = sx * 0.38
		k.box_at(Vector3(cx, DECK_Y - 0.04, (FRAME_Z1 - 0.03 + DECK_Z1) * 0.5), Vector3(0.06, 0.05, DECK_Z1 - FRAME_Z1 + 0.03), FRAME)
		EK.rod(k, Vector3(cx, 0.80, FRAME_Z1 - 0.01), Vector3(cx, DECK_Y - 0.06, DECK_Z1 - 0.12), 0.018, FRAME, 8)
		k.box_at(Vector3(cx, 0.80, FRAME_Z1 - 0.02), Vector3(0.06, 0.06, 0.04), FRAME)
	# the reel's frame: base rails bolted to the deck, an upright each side up
	# to the axle bearing
	var rc := REEL_C
	for sx2 in [-1.0, 1.0]:
		var fx: float = sx2 * 0.31
		k.box_at(Vector3(fx, DECK_Y + 0.02, rc.z), Vector3(0.04, 0.04, 0.5), red)
		EK.rod(k, Vector3(fx, DECK_Y + 0.03, rc.z - 0.2), Vector3(fx, rc.y, rc.z), 0.018, red, 8)
		EK.rod(k, Vector3(fx, DECK_Y + 0.03, rc.z + 0.2), Vector3(fx, rc.y, rc.z), 0.018, red, 8)
		k.cylinder(Transform3D(Basis(Vector3.BACK, -sx2 * PI * 0.5), Vector3(fx - sx2 * 0.02, rc.y, rc.z)), 0.04, 0.04, 0.04, 12, red)    # bearing
		for bz in [rc.z - 0.2, rc.z + 0.2]:
			k.cylinder(Transform3D(Basis.IDENTITY, Vector3(fx, DECK_Y + 0.04, float(bz))), 0.01, 0.01, 0.012, 6, STEEL)
	# crank on the left with its wooden grip; swivel inlet on the right
	k.box_at(Vector3(-0.36, rc.y - 0.07, rc.z), Vector3(0.02, 0.18, 0.03), red)
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.37, rc.y - 0.15, rc.z)), 0.016, 0.016, 0.11, 8, Color(0.55, 0.40, 0.22))
	k.cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(0.33, rc.y, rc.z)), 0.035, 0.035, 0.07, 12, Color(0.6, 0.6, 0.62))
	tube(k, [Vector3(0.40, rc.y, rc.z), Vector3(0.49, rc.y, rc.z), Vector3(0.49, rc.y, VALVE_C.z), Vector3(0.49, VALVE_C.y + 0.06, VALVE_C.z)], 0.03, pipe)
	# the feed: up from the rear line, through the deck, into the valve
	tube(k, [Vector3(RAIL_X + 0.06, 0.90, FRAME_Z1 + 0.12), Vector3(0.49, 0.95, VALVE_C.z), Vector3(0.49, VALVE_C.y - 0.06, VALVE_C.z)], 0.035, pipe)
	# butterfly valve: round body with grooved ends, neck out to the back, the
	# notched plate (lever up = open, flat = shut)
	k.cylinder(Transform3D(Basis.IDENTITY, VALVE_C - Vector3(0, 0.035, 0)), 0.06, 0.06, 0.07, 16, Color(0.15, 0.28, 0.55))
	for gy in [-0.04, 0.04]:
		k.cylinder(Transform3D(Basis.IDENTITY, VALVE_C + Vector3(0, float(gy) - 0.006, 0)), 0.045, 0.045, 0.012, 14, pipe)
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), VALVE_C), 0.018, 0.018, 0.09, 10, Color(0.15, 0.28, 0.55))
	var plate_c := VALVE_C - Vector3(0, 0, 0.09)
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), plate_c), 0.07, 0.07, 0.008, 18, Color(0.75, 0.66, 0.30))
	for nt in range(10):
		var na := -PI * 0.5 + PI * 0.5 * float(nt) / 9.0
		k.box(Transform3D(Basis(Vector3.BACK, na), plate_c + Vector3(cos(na), sin(na), 0) * 0.068 - Vector3(0, 0, 0.002)), Vector3(0.008, 0.012, 0.01), Color(0.6, 0.52, 0.22))
	pump_valve = Node3D.new()
	pump_valve.name = "PumpValve"
	pump_valve.position = plate_c - Vector3(0, 0, 0.012)
	var vk := MeshKit.new()
	vk.box_at(Vector3(0.11, 0, 0), Vector3(0.24, 0.025, 0.012), Color(0.15, 0.28, 0.55))
	vk.box_at(Vector3(0.20, 0, -0.012), Vector3(0.09, 0.03, 0.014), Color(0.65, 0.55, 0.3))     # the squeeze grip
	pump_valve.add_child(vk.instance("Lever"))
	pump_valve.set_meta("control", "pump_valve")
	t.add_child(pump_valve)
	# the drum: flanges (rim, six spokes, hub), core, the hose wound on it
	reel_drum = Node3D.new()
	reel_drum.name = "ReelDrum"
	reel_drum.position = rc
	var dk := MeshKit.new()
	# each flange: a solid steel disc (closed both faces, no see-through ring),
	# a rolled edge round it, six pressed ribs on the outside, the hub
	for fl in [-0.255, 0.255]:
		var flx: float = fl
		var sgn := signf(flx)
		dk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(flx + 0.004, 0, 0)), 0.262, 0.262, 0.008, 36, red)
		var rim: Array = []
		for ri in range(41):
			var ra := TAU * float(ri) / 40.0
			rim.append(Vector3(flx, sin(ra) * 0.262, cos(ra) * 0.262))
		hose_sweep(dk, rim, 0.009, red, 6)
		for sp in range(6):
			var sa := TAU * float(sp) / 6.0 + PI / 6.0
			var dir := Vector3(0, sin(sa), cos(sa))
			dk.box(Transform3D(Basis(Vector3.RIGHT, -sa), Vector3(flx + sgn * 0.009, 0, 0) + dir * 0.155), Vector3(0.010, 0.022, 0.20), red.darkened(0.12))
		dk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(flx + sgn * 0.03 + 0.015, 0, 0)), 0.05, 0.05, 0.03, 16, red.darkened(0.1))
	dk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.25, 0, 0)), 0.11, 0.11, 0.5, 18, red.darkened(0.3))
	# the hose wound on the drum: real turns, two layers (50 ft), each a helix
	# of tube across the drum; the outer layer goes as the hose pays out
	wound_layers.clear()
	# in half turns, in the order they were wound on (inner layer across, outer
	# layer back): they come off one at a time from the last, so the drum
	# empties steadily as the hose pays out
	var helix: Array = []
	for i in range(WOUND_STEPS + 1):
		helix.append(wound_local(float(i)))
	for h in range(WOUND_STEPS / WOUND_PIECE):
		var wk := MeshKit.new()
		hose_sweep(wk, helix, 0.022, hose_col, 8, h * WOUND_PIECE, (h + 1) * WOUND_PIECE)
		var wmi := wk.instance("WoundHose%d" % h)
		reel_drum.add_child(wmi)
		wound_layers.append(wmi)
	dk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.34, 0, 0)), 0.015, 0.015, 0.68, 8, STEEL)                           # axle
	reel_drum.add_child(dk.instance("Drum"))
	t.add_child(reel_drum)
	t.add_child(k.instance("ReelDeck"))
	# roller guide at the back edge (the hose itself is hose_line.gd: it comes
	# off the bottom of the drum, through the guide)
	var gk := MeshKit.new()
	for gy2 in [REEL_OUT.y - 0.035, REEL_OUT.y + 0.035]:
		gk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.12, float(gy2), REEL_OUT.z)), 0.018, 0.018, 0.24, 10, STEEL)
	for gx in [-0.12, 0.12]:
		# side plate: bolted to the back of the deck, out to the rollers
		var z0 := DECK_Z1 - 0.03
		var z1 := REEL_OUT.z + 0.03
		var y0 := DECK_Y - 0.03
		var y1 := REEL_OUT.y + 0.06
		gk.box_at(Vector3(float(gx), (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3(0.012, y1 - y0, z1 - z0), STEEL)
		for bz in [DECK_Z1 - 0.015]:
			gk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(float(gx) + 0.012, DECK_Y + 0.02, float(bz))), 0.008, 0.008, 0.024, 6, STEEL.darkened(0.3))
	# (the length from the drum to the guide is part of the one hose, hose_line.gd)
	t.add_child(gk.instance("ReelGuide"))
