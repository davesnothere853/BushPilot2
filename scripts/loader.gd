extends Node3D
## A wheel loader (DESIGN_NOTES 89), from Dave's photo of a mid-size
## articulated loader with forks: about 10 t, 1.8 m3 bucket, 3.9 m to the
## hinge pin, ~3 m dump clearance. The frame bends in the middle to steer;
## the lift arms keep the bucket level as they rise (parallel lift), the tilt
## curls it back or dumps it. A quick coupler swaps the bucket for forks.
##
## Drive into a heap with the bucket flat on the ground and it fills; tilt it
## forward to dump - into a trommel's hopper if you're over it and high
## enough, otherwise in a pile. Real loaders only clear about 3 m, so a tall
## hopper needs a dirt ramp (build one with the dozer).
##
## Body frame: origin on the ground under the middle of the wheelbase,
## -Z forward, +X right, +Y up. The front frame pivots at the origin.

const MeshKit = preload("res://scripts/meshkit.gd")
const WheeledBody = preload("res://scripts/wheeled_body.gd")
const TyreMesh = preload("res://scripts/tyre_mesh.gd")
const EK = preload("res://scripts/equip_kit.gd")
const SAVE := "user://loader.cfg"

const YEL := Color(0.93, 0.74, 0.14)          # the early-80s loaders in the reference
const YEL_D := Color(0.78, 0.56, 0.05)
const DARK := Color(0.12, 0.12, 0.13)
const STEEL := Color(0.42, 0.43, 0.45)
const RUBBER := Color(0.09, 0.09, 0.09)
const GLASS := Color(0.45, 0.58, 0.66, 0.38)

const WB := 3.0                    # wheelbase
const TRACK := 2.0                 # wheel centres
const WHEEL_R := 0.75              # 20.5-25 tyres, 1.5 m across
const ARM_PIVOT := Vector3(0, 2.1, -0.6)    # on the front frame's tower
const STEER_Y := 0.62                  # the steering rams run under the frames, either side of the hinge
const STEER_X0 := 0.45                 # base pin on the rear frame (under its rails)
const STEER_Z0 := 0.5
const STEER_X1 := 0.5                  # rod pin on the front frame (on its side plate)
const STEER_Z1 := -0.5
const ARM_X := 0.62                  # the arms' line: inside the front tyres (Dave: they clipped the front end)
const LIFT_X := 0.5                  # the lift rams' line: between the frame's side plates (0.42) and the arms
const LIFT_BASE := Vector3(0.55, 1.1, -0.35)   # base pin on the front frame
const LIFT_EAR := Vector3(0.55, -0.2, -1.4)    # rod eye on the arm (arm frame)
const STACK_Z := 2.35                # the exhaust stack, halfway back along the hood
const STEP_Z := 0.48                 # the steps up to the door, clear ahead of the rear tyre (front edge ~0.75)
const ARM_L := 2.85
# The Z-bar, solved so it racks back on the ground and dumps at full height
# with a real cylinder (1.14 m closed, 1.98 m open):
const ZB_G := Vector3(0, 0.3, 0.25)            # tilt cylinder's base pin, from the arm pivot (front frame)
const ZB_E := Vector3(0, 0.45, 0.25)           # lever's top (the cylinder's rod eye), from its pivot
const ZB_H := Vector3(0, -0.5, -0.15)          # lever's foot (the link), from its pivot
const ZB_C := Vector3(0, 0.35, 0.1)            # the link's ear on the bucket's back (bucket frame)
const ZB_RAM_MIN := 1.14
const ZB_RAM_MAX := 1.98
var ZB_F := Vector3.ZERO                       # the lever's pivot on the cross tube (arm frame)
var _crank: Node3D
var _zlink: Node3D
var _zlink_len := 1.17
var _tilt_ram: Node3D                # pivot to bucket hinge pin
const A_DOWN := -0.575             # arms down: hinge pin 0.55 m up, bucket flat on the ground
const A_UP := 0.68                 # arms up: hinge pin ~3.9 m
const TILT_RACK := 0.70            # curled back (carrying)
const TILT_DUMP := -0.90           # tipped forward (dumping)
const BUCKET_BACK := 0.22                     # the bucket body moved back onto its ears
const LIP := Vector3(0, -0.55, -1.25 + BUCKET_BACK)        # cutting edge in the tool frame
const BUCKET_M3 := 1.8
const DIRT_KG := 1800.0            # a cubic metre of gravel

var terrain: RefCounted
var body: RefCounted
var driven := false
var yaw := 0.0
var lift := 0.0                    # 0 arms down .. 1 arms up
var tilt := 0.0                    # bucket angle to level ground (+ curled)
var attach := "bucket"             # "bucket" or "forks"
var bucket_load := {}              # {over, pay, g}
var on_dig: Callable               # func(point, radius, m3) -> Dictionary
var on_dump: Callable              # func(point, load) -> String
var hopper_at: Callable            # func(point) -> Vector3 hopper top, or INF
var _front: Node3D
var _arms: Node3D
var _tool: Node3D
var _bucket: Node3D
var _forks: Node3D
var _dirt: MeshInstance3D
var _wheel_nodes: Array = []       # [node, front]
var _cut_acc := 0.0
var _told_high := false
var _save_t := 0.0


## The model (DESIGN_NOTES 149), rebuilt to a real mid-size loader's
## proportions: 3.0 m wheelbase on 1.5 m (20.5-25) tyres, the cab over the
## rear frame right behind the hinge, its roof 3.35 m up; the engine under
## a long hood behind it sloping down to the radiator grille and a heavy
## curved counterweight; the front frame a pair of deep side plates with the
## loader tower at the back; two cranked lift arms, the lift cylinders from
## low on the frame up to the arms, and the single-cylinder Z-bar linkage
## (tilt cylinder, bellcrank, link) that tips the bucket; a 2.55 m general
## purpose bucket with a bolt-on edge, teeth and a spill guard.
var _seat_at := Vector3.ZERO
var seat: Node3D
var engine: Node3D


## The lab and the cab: click the seat's air valve (and whatever else gets a control).
func control_click(nm: String) -> String:
	if nm == "seat_air" and seat != null:
		return seat.air()
	return ""


const TowPoints = preload("res://scripts/tow_points.gd")
## Winch / tow points (DESIGN_NOTES 225): two shackles under the nose plate
## (on the front frame: they steer with it), the tow pin in the counterweight.
const WINCH_POINTS_FRONT := [
	["front left shackle", Vector3(-0.32, 0.70, -2.26), Vector3(0, 0, -1)],
	["front right shackle", Vector3(0.32, 0.70, -2.26), Vector3(0, 0, -1)],
]
const WINCH_POINTS_REAR := [
	["rear tow pin", Vector3(0, 0.55, 3.62), Vector3(0, 0, 1)],
]

func build() -> void:
	var k := MeshKit.new()
	# --- rear frame ------------------------------------------------------------
	k.box_at(Vector3(0, 0.95, 1.7), Vector3(1.05, 0.5, 3.4), DARK)              # frame rails
	k.box_at(Vector3(0, 0.62, 0.35), Vector3(0.5, 0.3, 0.7), DARK)              # hitch boss under the joint
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0.0)), 0.12, 0.12, 0.75, 12, STEEL)     # the articulation pin
	_vear(k, Vector3(0, 1.2, 0), Vector3(0, 0, 1), 0.3, 0.27, 0.06, DARK)       # the rear frame's top ear (the hitch boss is the bottom one)
	_vear(k, Vector3(0, 0.66, 0), Vector3(0, 0, 1), 0.3, 0.27, 0.06, DARK)
	for ssr in [-1.0, 1.0]:                     # the steering rams' base ears, hung under the rails
		for ey in [0.07, -0.07]:
			_vear(k, Vector3(ssr * STEER_X0, STEER_Y + ey, STEER_Z0), Vector3(0, 0, 1), 0.08, 0.06, 0.025, DARK)
		k.box_at(Vector3(ssr * STEER_X0, (STEER_Y + 0.7) * 0.5 + 0.04, STEER_Z0 + 0.06), Vector3(0.12, 0.7 - STEER_Y, 0.04), DARK)   # the hanger down from the rail
		k.cylinder(Transform3D(Basis.IDENTITY, Vector3(ssr * STEER_X0, STEER_Y - 0.1, STEER_Z0)), 0.02, 0.02, 0.2, 8, STEEL)          # its vertical pin
	for sx in [-1.0, 1.0]:
		# (the steering rams across the joint are working rams: below)
		# fuel and hydraulic tanks low between the axles, steps on the left
		k.box_at(Vector3(sx * 0.72, 1.0, 0.55), Vector3(0.4, 0.62, 0.95), YEL)
		k.box_at(Vector3(sx * 0.93, 1.0, 0.55), Vector3(0.02, 0.5, 0.8), YEL_D)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.72, 1.31, 0.3)), 0.07, 0.07, 0.06, 8, DARK)   # fuel cap
	# the engine hood: long, rounded at the top corners, sloping a little to the back
	var hood: Array = []
	for z in [1.45, 3.15]:
		var top := 2.32 if z < 2.0 else 2.12
		hood.append(_hood_ring(z, 0.78, 1.18, top, 0.16))
	k.loft(hood, YEL, true, true)
	# service doors with louvres near the back, a seam down each side
	for sx2 in [-1.0, 1.0]:
		k.box_at(Vector3(sx2 * 0.785, 1.72, 2.1), Vector3(0.01, 0.95, 0.02), YEL_D)
		for lz in range(7):
			k.box_at(Vector3(sx2 * 0.787, 1.75, 2.35 + 0.1 * float(lz)), Vector3(0.012, 0.6, 0.04), DARK)
		k.box_at(Vector3(sx2 * 0.787, 1.32, 1.8), Vector3(0.012, 0.06, 0.3), DARK)      # door latch
	# radiator grille on the back and the counterweight under it
	k.box_at(Vector3(0, 1.66, 3.18), Vector3(1.4, 0.9, 0.05), DARK)
	for gy in range(9):
		k.box_at(Vector3(0, 1.26 + 0.1 * float(gy), 3.215), Vector3(1.32, 0.03, 0.02), STEEL.darkened(0.2))
	var cw: Array = []
	for i in range(7):
		var a := -PI * 0.5 + PI * float(i) / 6.0
		cw.append(Vector3(sin(a) * 1.0, 0.0, 0.0) + Vector3(0, 0, 3.2 + cos(a) * 0.32))
	for i in range(6):
		var p0: Vector3 = cw[i]
		var p1: Vector3 = cw[i + 1]
		k.quad(p0 + Vector3(0, 0.55, 0), p1 + Vector3(0, 0.55, 0), p1 + Vector3(0, 1.25, 0), p0 + Vector3(0, 1.25, 0), YEL_D, (p0 + p1) * 0.5 - Vector3(0, 0, 3.2))
		k.tri(Vector3(0, 1.25, 3.2), p0 + Vector3(0, 1.25, 0), p1 + Vector3(0, 1.25, 0), YEL_D, Vector3.UP)
		k.tri(Vector3(0, 0.55, 3.2), p1 + Vector3(0, 0.55, 0), p0 + Vector3(0, 0.55, 0), YEL_D, Vector3.DOWN)
	k.box_at(Vector3(0, 0.9, 2.95), Vector3(1.98, 0.7, 0.5), YEL_D)
	k.box_at(Vector3(0, 0.62, 3.5), Vector3(0.3, 0.16, 0.12), DARK)              # drawbar
	# exhaust stack and air pre-cleaner up through the hood
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.4, 2.1, STACK_Z)), 0.075, 0.07, 0.85, 10, DARK)      # back along the hood, clear of the cab (Dave)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.4, 2.95, STACK_Z)), 0.08, 0.08, 0.04, 10, STEEL)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.4, 2.2, 1.7)), 0.07, 0.07, 0.4, 10, DARK)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.4, 2.6, 1.7)), 0.17, 0.17, 0.22, 12, DARK)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.4, 2.82, 1.7)), 0.19, 0.19, 0.04, 12, STEEL)
	# (the rear fenders are the flat-topped decks in _detail, off the hood's sides)
	# --- the cab --------------------------------------------------------------
	var cz := 0.78                       # cab centre
	k.box_at(Vector3(0, 1.48, cz), Vector3(1.5, 0.14, 1.5), DARK)                # floor plate
	for px in [-0.7, 0.7]:
		for pz in [cz - 0.68, cz + 0.68]:
			k.box_at(Vector3(px, 2.42, pz), Vector3(0.09, 1.8, 0.09), DARK)      # ROPS posts
	k.box_at(Vector3(0, 3.33, cz), Vector3(1.6, 0.12, 1.62), YEL)                # roof
	k.box_at(Vector3(0, 3.26, cz - 0.8), Vector3(1.6, 0.06, 0.06), DARK)         # visor edge
	for sx4 in [-1.0, 1.0]:
		k.box_at(Vector3(sx4 * 0.72, 1.9, cz), Vector3(0.04, 0.06, 1.3), DARK)   # window sills
		EK.mirror(k, Vector3(sx4 * 0.72, 2.85, cz - 0.62), Vector3(sx4 * 0.92, 2.8, cz - 0.62))
	# inside: the suspension seat, console, steering wheel, joystick
	_seat_at = Vector3(0, 1.75, cz + 0.25)
	k.box_at(Vector3(0, 1.95, cz - 0.5), Vector3(0.5, 0.75, 0.2), DARK)         # steering pedestal
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, -0.75), Vector3(0, 2.35, cz - 0.38)), 0.19, 0.19, 0.03, 14, DARK, false)
	k.box_at(Vector3(0.42, 2.05, cz + 0.15), Vector3(0.14, 0.3, 0.45), DARK)    # right console
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.42, 2.2, cz)), 0.025, 0.02, 0.18, 6, DARK)
	# the ladder up to the left door, grab rail
	# (the steps are in _detail; their side stringers here, ahead of the rear tyre)
	for lz2 in [STEP_Z - 0.14, STEP_Z + 0.14]:
		k.box_at(Vector3(-1.13, 0.85, lz2), Vector3(0.03, 0.95, 0.03), STEEL)
	_rod(k, Vector3(-0.76, 1.6, cz - 0.55), Vector3(-0.76, 2.9, cz - 0.55), 0.02, STEEL)
	add_child(k.instance("RearFrame"))
	var gk := MeshKit.new()
	var seal := MeshKit.new()
	var fz := cz - 0.7
	var rz := cz + 0.7
	EK.pane(gk, seal, Vector3(-0.66, 1.95, fz), Vector3(0.66, 1.95, fz), Vector3(0.66, 3.25, fz), Vector3(-0.66, 3.25, fz), Vector3(0, 0, -1))     # windscreen
	EK.pane(gk, seal, Vector3(-0.66, 1.58, fz), Vector3(0.66, 1.58, fz), Vector3(0.66, 1.88, fz), Vector3(-0.66, 1.88, fz), Vector3(0, 0, -1))     # low front glass
	EK.pane(gk, seal, Vector3(0.66, 2.0, rz), Vector3(-0.66, 2.0, rz), Vector3(-0.66, 3.25, rz), Vector3(0.66, 3.25, rz), Vector3(0, 0, 1))        # rear
	for gx in [-0.71, 0.71]:
		var o := Vector3(signf(gx), 0, 0)
		EK.pane(gk, seal, Vector3(gx, 1.98, cz + 0.62 * signf(gx)), Vector3(gx, 1.98, cz - 0.62 * signf(gx)), Vector3(gx, 3.25, cz - 0.62 * signf(gx)), Vector3(gx, 3.25, cz + 0.62 * signf(gx)), o)
	add_child(seal.instance("Seals"))
	var gm := gk.instance("Glass")
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = GLASS
	gmat.roughness = 0.1
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.material_override = gmat
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gm)
	for sx5 in [-1.0, 1.0]:
		_wheel(self, Vector3(sx5 * TRACK * 0.5, WHEEL_R, WB * 0.5), sx5, false)
	# --- front frame: bends at the joint to steer --------------------------------
	_front = Node3D.new()
	_front.name = "FrontFrame"
	add_child(_front)
	var f := MeshKit.new()
	for sx6 in [-0.42, 0.42]:
		# deep side plates from the joint to the front axle and on to the nose
		f.quad(Vector3(sx6, 0.55, -0.15), Vector3(sx6, 1.2, -0.15), Vector3(sx6, 1.3, -2.15), Vector3(sx6, 0.6, -2.15), DARK, Vector3(signf(sx6), 0, 0))
		f.quad(Vector3(sx6, 0.55, -0.15), Vector3(sx6, 0.6, -2.15), Vector3(sx6, 1.3, -2.15), Vector3(sx6, 1.2, -0.15), DARK, Vector3(-signf(sx6), 0, 0))
		# the loader tower plates, up to the arm pivot
		f.quad(Vector3(sx6, 1.15, -0.15), Vector3(sx6, 2.3, -0.4), Vector3(sx6, 2.3, -0.85), Vector3(sx6, 1.2, -1.35), YEL, Vector3(signf(sx6), 0, 0))
		f.quad(Vector3(sx6, 1.15, -0.15), Vector3(sx6, 1.2, -1.35), Vector3(sx6, 2.3, -0.85), Vector3(sx6, 2.3, -0.4), YEL, Vector3(-signf(sx6), 0, 0))
		# the arm's pivot clevis, hung under the tower's wide crossmember: a plate
		# each side of the arm's boss, rounded round the pin
		EK.lug(f, Vector3(signf(sx6) * ARM_X, ARM_PIVOT.y, ARM_PIVOT.z), 0.11, 0.04, 0.17, Vector3(0, 1, 0), 0.17, YEL_D, 0.06)
		# the lift cylinders' base clevis, low on the front frame just ahead of the
		# hinge (as on the real 80s loaders): the side plate is the inner cheek,
		# an outer cheek plate and a web under the eye, the pin through
		var lb := Vector3(signf(sx6) * LIFT_X, LIFT_BASE.y, LIFT_BASE.z)
		f.box_at(Vector3(signf(sx6) * 0.5, lb.y - 0.16, lb.z), Vector3(0.18, 0.04, 0.3), DARK)       # a shelf welded to the side plate
		EK.lug(f, lb, 0.045, 0.03, 0.085, Vector3(0, -1, 0), 0.15, DARK)
	f.box_at(Vector3(0, 1.25, -0.6), Vector3(0.86, 0.15, 0.6), YEL_D)            # tower top web
	# the tower's top: a crossmember each side out over the arms' pivots, and a
	# bridge behind carrying the tilt cylinder's base - the middle left open so
	# the tilt cylinder runs through clear (Dave: it clipped through the bar)
	for cxs in [-1.0, 1.0]:
		f.box_at(Vector3(cxs * 0.56, 2.3, -0.62), Vector3(0.62, 0.1, 0.5), YEL_D)
	f.box_at(Vector3(0, 2.3, -0.2), Vector3(0.86, 0.1, 0.2), YEL_D)
	f.box_at(Vector3(0, 0.9, -1.5), Vector3(0.9, 0.4, 0.5), DARK)                # front axle housing
	f.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.95, WHEEL_R, -WB * 0.5)), 0.2, 0.2, 1.9, 10, DARK)
	f.box_at(Vector3(0, 0.9, -2.2), Vector3(0.95, 0.5, 0.12), YEL_D)             # nose plate
	for sx7 in [-1.0, 1.0]:
		_fender(f, Vector3(sx7 * 1.06, WHEEL_R, -WB * 0.5), 0.5, -1.5, 0.15, YEL)       # outboard of the arms (they swing down inside it)
	# the centre hinge: the front frame's two ears between the rear frame's, the
	# vertical pin through all of them (Dave: real pivots)
	for hy in [0.8, 1.04]:
		_vear(f, Vector3(0, hy, 0), Vector3(0, 0, -1), 0.3, 0.27, 0.05, DARK)
	# the steering rams' rod ears on the front side plates
	for ssx in [-1.0, 1.0]:
		_vear(f, Vector3(ssx * STEER_X1, STEER_Y + 0.07, STEER_Z1), Vector3(-ssx, 0, 0), 0.09, 0.06, 0.025, DARK)
		_vear(f, Vector3(ssx * STEER_X1, STEER_Y - 0.07, STEER_Z1), Vector3(-ssx, 0, 0), 0.09, 0.06, 0.025, DARK)
	_front.add_child(f.instance("Front"))
	var rk := MeshKit.new()
	rk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.95, WHEEL_R, WB * 0.5)), 0.2, 0.2, 1.9, 10, DARK)   # rear axle
	add_child(rk.instance("RearAxle"))
	for sx8 in [-1.0, 1.0]:
		_wheel(_front, Vector3(sx8 * TRACK * 0.5, WHEEL_R, -WB * 0.5), sx8, true)
	# --- lift arms: two cranked plates and a cross tube, on the tower pivots --------
	_arms = Node3D.new()
	_arms.position = ARM_PIVOT
	_front.add_child(_arms)
	var a := MeshKit.new()
	var mid := Vector3(0, -0.22, -ARM_L * 0.52)
	for ax in [-ARM_X, ARM_X]:
		_plate(a, Vector3(ax, 0, 0), Vector3(ax, mid.y, mid.z), 0.13, 0.5, 0.42, YEL)
		_plate(a, Vector3(ax, mid.y, mid.z), Vector3(ax, 0, -ARM_L), 0.13, 0.42, 0.32, YEL)
		a.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(ax + 0.1, 0, 0)), 0.14, 0.14, 0.2, 12, YEL_D)       # pivot boss
		a.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(ax + 0.1, 0, -ARM_L)), 0.12, 0.12, 0.2, 12, YEL_D)  # bucket pin boss
		# the lift cylinder's rod-end ears on the arm's inner face: the arm is the
		# outer cheek, an inner ear plate, a web joining them, the pin through
		var le := Vector3(signf(ax) * LIFT_X, LIFT_EAR.y, LIFT_EAR.z)
		EK.lug(a, le, 0.045, 0.03, 0.085, Vector3(0, 1, 0), 0.19, YEL_D)                               # outer plate welded to the arm's inner face
		a.box_at(Vector3(signf(ax) * (LIFT_X + 0.03), -0.015, le.z), Vector3(0.14, 0.03, 0.2), YEL_D)            # and a top web onto the arm
	a.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(ARM_X, mid.y, mid.z - 0.1)), 0.13, 0.13, ARM_X * 2.0, 12, YEL_D)   # cross tube
	# the Z-bar (from the real linkage drawings): the lever swings on its pin on
	# the cross tube, the tilt cylinder pushes its top, its foot pulls the link
	# to the ear high on the bucket's back - it works (_zbar_pose)
	var bc_pivot := Vector3(0, mid.y + 0.15, mid.z - 0.1)
	ZB_F = bc_pivot
	EK.lug(a, bc_pivot, 0.1, 0.04, 0.12, Vector3(0, -0.6, 1), 0.16, YEL_D, 0.05)      # the lever's pin bracket on the cross tube
	_arms.add_child(a.instance("Arms"))
	_crank = Node3D.new()
	_crank.name = "ZbarLever"
	_crank.position = bc_pivot
	_arms.add_child(_crank)
	var ck := MeshKit.new()
	for lx in [-0.075, 0.075]:                  # two plates, the cylinder's eye and the link between them at each end
		_plate(ck, Vector3(lx, ZB_E.y, ZB_E.z), Vector3(lx, 0, 0), 0.04, 0.2, 0.26, YEL)
		_plate(ck, Vector3(lx, 0, 0), Vector3(lx, ZB_H.y, ZB_H.z), 0.04, 0.26, 0.2, YEL)
		for pp in [ZB_E, Vector3.ZERO, ZB_H]:
			ck.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(lx + 0.02, (pp as Vector3).y, (pp as Vector3).z)), 0.1 if pp == Vector3.ZERO else 0.08, 0.1 if pp == Vector3.ZERO else 0.08, 0.04, 14, YEL_D, true)
	for pp2 in [ZB_E, Vector3.ZERO, ZB_H]:
		ck.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.12, (pp2 as Vector3).y, (pp2 as Vector3).z)), 0.035, 0.035, 0.24, 8, STEEL, true)      # the pins
	_crank.add_child(ck.instance("Lever"))
	_zlink = Node3D.new()
	_zlink.name = "ZbarLink"
	_arms.add_child(_zlink)
	# lift cylinders: working rams from the frame anchors to the arms (hyd_ram.gd, below)
	_lift_cyl.clear()
	_tool = Node3D.new()
	_tool.position = Vector3(0, 0, -ARM_L)
	_arms.add_child(_tool)
	_bucket = _build_bucket()
	_tool.add_child(_bucket)
	_forks = _build_forks()
	_tool.add_child(_forks)
	# the link, as long as the lever's foot is from the bucket's ear at rest
	var c0 := Vector3(0, 0, -ARM_L) + Basis(Vector3.RIGHT, -A_DOWN) * ZB_C
	_zlink_len = (ZB_F + ZB_H).distance_to(c0)
	var lk := MeshKit.new()
	_plate(lk, Vector3.ZERO, Vector3(0, 0, -_zlink_len), 0.1, 0.16, 0.16, YEL_D)
	_zlink.add_child(lk.instance("Link"))
	_detail(cz)
	EK.dust_all(self, 0.45, 1.25)
	seat = EK.air_seat(self, _seat_at, 0.0)
	engine = EK.engine(self, Vector3(0.4, 2.99, STACK_Z), null, 0.08)
	var brk := MeshKit.new()
	# the tilt ram's base clevis, standing up off the tower's crossmember
	EK.lug(brk, ARM_PIVOT + ZB_G, 0.07, 0.04, 0.13, Vector3(0, -0.6, 1), 0.16, YEL_D, 0.05)     # on the bridge behind it
	_front.add_child(brk.instance("TiltBracket"))
	var Ram = ResourceLoader.load("res://scripts/hyd_ram.gd", "", ResourceLoader.CACHE_MODE_REPLACE)
	var tr = Ram.new()
	_front.add_child(tr)
	tr.setup(_front, ARM_PIVOT + ZB_G, _crank, ZB_E, 0.11, YEL_D, ZB_RAM_MIN)
	_tilt_ram = tr
	# hard lines from the valve bank on the front frame, up the tower to the tilt ram
	EK.add_collision(self)
	tr.plumb(self, _front, Vector3(0.12, 1.28, -0.5), 0.018, [Vector3(0.12, 2.0, -0.45), Vector3(0.12, 2.45, -0.3)])
	# the two steering rams across the hinge: rear frame to front frame, they
	# push and pull to bend the machine (they work as the frame articulates)
	for ss in [-1.0, 1.0]:
		var st = Ram.new()
		add_child(st)
		st.pin_axis = Vector3.UP          # the steering pins stand vertical: the eyes too
		st.setup(self, Vector3(ss * STEER_X0, STEER_Y, STEER_Z0), _front, Vector3(ss * STEER_X1, STEER_Y, STEER_Z1), 0.06, YEL_D, 0.72)
		st.plumb(self, self, Vector3(ss * 0.2, 0.72, 0.9), 0.014, [Vector3(ss * 0.32, 0.68, 0.75)])
	_rams_lift = []
	# (laid out by its range of motion: 1.32 m closed, 2.26 m open, open/closed
	# 1.72 like a real cylinder, through the arms' whole swing)
	for sx9 in [-1.0, 1.0]:
		var lr = Ram.new()
		_front.add_child(lr)
		lr.setup(_front, Vector3(sx9 * LIFT_X, LIFT_BASE.y, LIFT_BASE.z), _arms, Vector3(sx9 * LIFT_X, LIFT_EAR.y, LIFT_EAR.z), 0.085, YEL_D)
		lr.plumb(self, _front, Vector3(sx9 * 0.3, 1.25, -0.6), 0.018, [Vector3(sx9 * 0.44, 1.3, -0.5), Vector3(sx9 * 0.5, 1.22, -0.42)])
		_rams_lift.append(lr)
	_pose()
	TowPoints.build(_front, WINCH_POINTS_FRONT, YEL_D)


## The truck treatment (DESIGN_NOTES 215), from the early-80s loaders in the
## reference: lamps like the truck's, the heavy rear grille guard, the cab's
## drip rail, door, wiper and dash, chrome rods and hoses, grated steps and
## rails, bolts, hazard stripes, decals, mud flaps.
func _detail(cz: float) -> void:
	var p := MeshKit.new()           # painted
	var d := MeshKit.new()           # dark / rubber
	var m := MeshKit.new()           # bright metal
	# --- cab: drip rail round the roof, the door on the left, wiper, dash pod
	for sz in [-1.0, 1.0]:
		p.box_at(Vector3(0, 3.27, cz + sz * 0.82), Vector3(1.64, 0.05, 0.04), YEL_D)
	for sx in [-1.0, 1.0]:
		p.box_at(Vector3(sx * 0.81, 3.27, cz), Vector3(0.04, 0.05, 1.64), YEL_D)
	d.box_at(Vector3(-0.735, 2.6, cz + 0.1), Vector3(0.02, 1.35, 0.03), DARK)                    # the door's back edge
	d.box_at(Vector3(-0.74, 2.3, cz + 0.02), Vector3(0.04, 0.03, 0.14), EK.STEEL)                # handle
	for hy in [2.1, 3.0]:
		d.box_at(Vector3(-0.735, hy, cz - 0.6), Vector3(0.04, 0.12, 0.05), DARK)                 # hinges
	EK.rod(d, Vector3(0.45, 3.2, cz - 0.72), Vector3(-0.05, 2.15, cz - 0.72), 0.008, DARK)        # wiper arm
	EK.rod(d, Vector3(0.05, 2.25, cz - 0.725), Vector3(-0.25, 2.95, cz - 0.725), 0.01, Color(0.03, 0.03, 0.03))  # blade
	d.rbox(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 2.35, cz - 0.55)), Vector3(0.6, 0.22, 0.12), DARK, 0.03)   # dash pod
	for gi in range(4):
		m.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + 0.5), Vector3(-0.21 + float(gi) * 0.14, 2.38, cz - 0.6)), 0.04, 0.04, 0.01, 12, Color(0.85, 0.85, 0.8), true)
	for lv in range(3):
		EK.rod(d, Vector3(0.38 + float(lv) * 0.06, 2.0, cz - 0.05), Vector3(0.38 + float(lv) * 0.06, 2.3, cz - 0.1), 0.012, DARK)
		m.box_at(Vector3(0.38 + float(lv) * 0.06, 2.31, cz - 0.1), Vector3(0.04, 0.05, 0.04), [Color(0.8, 0.1, 0.05), Color(0.1, 0.1, 0.1), Color(0.95, 0.7, 0.1)][lv])
	# cab lamps: two working lamps front and back on the roof, square, like the truck's
	for sx2 in [-0.55, 0.55]:
		EK.lamp(d, m, self, Vector3(sx2, 3.47, cz - 0.86), Vector3(0, -0.1, -1), 0.17, 0.12, Color(1, 0.97, 0.85))
		EK.lamp(d, m, self, Vector3(sx2, 3.47, cz + 0.86), Vector3(0, -0.1, 1), 0.17, 0.12, Color(1, 0.97, 0.85))
		d.box_at(Vector3(sx2, 3.41, cz - 0.8), Vector3(0.05, 0.08, 0.1), DARK)
		d.box_at(Vector3(sx2, 3.41, cz + 0.8), Vector3(0.05, 0.08, 0.1), DARK)
	EK.beacon(d, self, Vector3(0.0, 3.39, cz + 0.2))
	# --- the heavy rear grille guard round the radiator: tubes, the lamps in it
	var gz := 3.56
	for gx in [-0.98, 0.98]:
		EK.rod(p, Vector3(gx, 1.25, 3.25), Vector3(gx, 2.15, 3.25), 0.05, YEL_D)
		EK.rod(p, Vector3(gx, 1.25, 3.25), Vector3(gx, 1.25, gz), 0.05, YEL_D)
		EK.rod(p, Vector3(gx, 2.15, 3.25), Vector3(gx * 0.9, 2.1, gz - 0.05), 0.05, YEL_D)
		EK.rod(p, Vector3(gx, 1.25, gz), Vector3(gx * 0.9, 2.1, gz - 0.05), 0.05, YEL_D)
		EK.lamp(d, m, self, Vector3(gx * 0.82, 1.42, gz + 0.02), Vector3(0, 0, 1), 0.13, 0.13, Color(0.85, 0.08, 0.05), true)    # tail / stop
		EK.lamp(d, m, self, Vector3(gx * 0.6, 1.42, gz + 0.02), Vector3(0, 0, 1), 0.11, 0.11, Color(1.0, 0.6, 0.1), true)       # turn
		EK.lamp(d, m, self, Vector3(gx * 0.82, 2.0, gz - 0.02), Vector3(0, 0, 1), 0.15, 0.15, Color(1, 0.97, 0.85), true)        # rear flood
	for gy in [1.25, 1.6, 2.1]:
		EK.rod(p, Vector3(-0.9, gy, gz - (0.05 if gy > 2.0 else 0.0)), Vector3(0.9, gy, gz - (0.05 if gy > 2.0 else 0.0)), 0.045, YEL_D)
	for bx in [-0.3, 0.3]:
		EK.rod(p, Vector3(bx, 1.25, gz), Vector3(bx, 2.1, gz - 0.05), 0.035, YEL_D)
	# hazard stripes on the counterweight's back, the tow pin, the plate
	EK.hazard(p, Vector3(-0.95, 0.6, 3.53), Vector3(0.95, 0.6, 3.53), Vector3(0.95, 0.95, 3.53), Vector3(-0.95, 0.95, 3.53), Vector3(0, 0, 1), 14)
	m.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 3.55)), 0.04, 0.04, 0.25, 10, EK.STEEL, true)
	# --- headlamps up on the front of the cab's guard posts and on the fenders
	# (built in the front frame's own kits: they swing with the front end - Dave)
	var fd := MeshKit.new()
	var fm := MeshKit.new()
	for sx3 in [-1.0, 1.0]:
		EK.lamp(fd, fm, _front, Vector3(sx3 * 0.62, 1.62, -1.62), Vector3(0, -0.05, -1), 0.18, 0.18, Color(1, 0.97, 0.85), true)
		fd.box_at(Vector3(sx3 * 0.62, 1.5, -1.52), Vector3(0.06, 0.18, 0.16), DARK)
	_front.add_child(fd.instance("FrontLampsDark"))
	var fmi := fm.instance("FrontLampsMetal")
	fmi.material_override = EK.metal_mat()
	_front.add_child(fmi)
	# --- hood: louvre slots, hinges along the door tops, bolts, the decals
	for sx4 in [-1.0, 1.0]:
		for hz in [1.7, 2.5]:
			m.box_at(Vector3(sx4 * 0.79, 2.18, hz), Vector3(0.03, 0.04, 0.16), EK.STEEL)
		EK.bolts(m, Vector3(sx4 * 0.79, 1.22, 1.5), Vector3(sx4 * 0.79, 1.22, 3.1), 8, Vector3(sx4, 0, 0), 0.016)
		EK.decal(self, "L-95", Vector3(sx4 * 0.792, 1.85, 1.9), Vector3(sx4, 0, 0), 0.006, Color(0.08, 0.08, 0.08))
		EK.decal(self, "DANGER\nKEEP CLEAR\nOF HINGE AREA", Vector3(sx4 * 0.53, 0.98, 0.5), Vector3(sx4, 0, 0), 0.0009, Color(0.95, 0.95, 0.95), Color(0.75, 0.08, 0.05), d, 0.22, 0.14)
		# mud flaps behind the rear fenders
		d.box(Transform3D(Basis.IDENTITY, Vector3(sx4 * TRACK * 0.5, 0.9, WB * 0.5 + 0.78)), Vector3(0.6, 0.9, 0.015), DARK)       # hangs off the fender lip
	# exhaust rain cap, the pre-cleaner bowl
	EK.rod(d, Vector3(-0.4, 2.84, 1.7), Vector3(-0.4, 2.95, 1.7), 0.12, Color(0.75, 0.75, 0.72))
	# --- grated steps up to the door, the rail
	for st in range(4):
		EK.grate_step(m, Vector3(-0.98, 0.44 + 0.3 * float(st), STEP_Z), 0.34, 0.24)      # ahead of the rear tyre (it ran into it)
	EK.rail(p, [Vector3(-0.78, 1.65, cz - 0.6), Vector3(-0.78, 2.9, cz - 0.6)], YEL_D, 0.022)
	EK.rail(p, [Vector3(-1.14, 0.55, STEP_Z - 0.2), Vector3(-1.14, 1.45, STEP_Z - 0.2), Vector3(-0.8, 1.6, STEP_Z - 0.2)], YEL_D, 0.022)
	# --- hoses along the arms to the bucket linkage, and to the lift cylinders
	for sx5 in [-0.57, 0.57]:
		pass       # (the lift rams' lines are routed by plumb(), with a purpose)
	# --- the engine side doors: their seams, piano hinges along the top, latches
	for sx6 in [-1.0, 1.0]:
		var xx: float = float(sx6) * 0.787
		for dz in [1.5, 2.3, 3.1]:
			d.box_at(Vector3(xx, 1.68, dz), Vector3(0.012, 0.95, 0.015), DARK)
		d.box_at(Vector3(xx, 2.16, 2.3), Vector3(0.014, 0.015, 1.6), DARK)
		m.box_at(Vector3(xx + sx6 * 0.006, 2.12, 2.3), Vector3(0.012, 0.03, 1.56), EK.STEEL)
		for lz3 in [1.9, 2.7]:
			m.box_at(Vector3(xx + sx6 * 0.01, 1.5, lz3), Vector3(0.02, 0.05, 0.12), EK.STEEL)
		# the big rear fender over the tyre, with its step and the rear work lamp under it
		# the rear fender: a flat deck over the tyre from the hood's side out past the
		# tread, a lip turned down at the front, a skirt sloping down behind the tyre,
		# a stiffening edge along the outside (Dave: fix the rear fender)
		var fx: float = float(sx6) * 1.075
		p.box(Transform3D(Basis.IDENTITY, Vector3(fx, 1.63, WB * 0.5 - 0.05)), Vector3(0.58, 0.05, 1.5), YEL)
		p.box(Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(fx, 1.5, WB * 0.5 - 0.85)), Vector3(0.58, 0.05, 0.3), YEL)        # front lip
		p.box(Transform3D(Basis(Vector3.RIGHT, 0.75), Vector3(fx, 1.4, WB * 0.5 + 0.84)), Vector3(0.58, 0.05, 0.42), YEL)         # rear skirt
		p.box_at(Vector3(float(sx6) * 1.36, 1.6, WB * 0.5 - 0.05), Vector3(0.03, 0.1, 1.5), YEL_D)                              # outer edge
		EK.grate_step(m, Vector3(fx, 1.67, WB * 0.5 - 0.4), 0.46, 0.3)
		EK.lamp(d, m, self, Vector3(sx6 * 1.1, 1.5, WB * 0.5 + 0.86), Vector3(0, -0.1, 1), 0.12, 0.12, Color(0.85, 0.08, 0.05), true)
		# cab corner posts: heavy ROPS sections at the back, a visor over the windscreen
		d.box_at(Vector3(sx6 * 0.72, 2.6, cz + 0.72), Vector3(0.12, 1.4, 0.12), DARK)
	p.box(Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0, 3.28, cz - 0.95)), Vector3(1.55, 0.03, 0.3), YEL_D)    # sun visor
	# the muffler under the stack, the articulation's grease lines and stop
	m.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.6, 2.05, STACK_Z)), 0.13, 0.13, 0.4, 14, Color(0.35, 0.33, 0.3), true)
	EK.rod(m, Vector3(-0.15, 0.62, 0.25), Vector3(-0.15, 0.95, -0.25), 0.008, EK.STEEL)
	d.box_at(Vector3(0, 0.95, -0.12), Vector3(0.6, 0.12, 0.12), DARK)
	add_child(p.instance("Detail"))
	add_child(d.instance("DetailDark"))
	var mm := m.instance("DetailMetal")
	mm.material_override = EK.metal_mat()
	add_child(mm)


var _rams_lift: Array = []
var hyd: RefCounted
var _joints: Array = []
var _pump_label: Label3D
var _lift_cyl: Array = []          # [MeshInstance3D, anchor in the front frame, end in the arm frame]


## A hood section across X at z: straight sides from y0 up, the top corners
## rounded off by `r`.
func _hood_ring(z: float, hw: float, y0: float, top: float, r: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.append(Vector3(-hw, y0, z))
	pts.append(Vector3(hw, y0, z))
	pts.append(Vector3(hw, top - r, z))
	pts.append(Vector3(hw - r * 0.3, top - r * 0.3, z))
	pts.append(Vector3(hw - r, top, z))
	pts.append(Vector3(-hw + r, top, z))
	pts.append(Vector3(-hw + r * 0.3, top - r * 0.3, z))
	pts.append(Vector3(-hw, top - r, z))
	return pts


## A fender: an arc of plates over a wheel at `c`, from angle a0 to a1 (0 is
## straight up, + toward +Z).
static func _fender(kit: RefCounted, c: Vector3, wdt: float, a0: float, a1: float, col: Color) -> void:
	var r := WHEEL_R + 0.12
	var n := 8
	for i in range(n):
		var t0 := lerpf(a0, a1, float(i) / float(n))
		var t1 := lerpf(a0, a1, float(i + 1) / float(n))
		var p0 := c + Vector3(0, cos(t0) * r, sin(t0) * r)
		var p1 := c + Vector3(0, cos(t1) * r, sin(t1) * r)
		var mid := (p0 + p1) * 0.5
		var d := p1 - p0
		var bz := d.normalized()
		var by := (mid - c).normalized()
		var bx := by.cross(bz).normalized()
		kit.box(Transform3D(Basis(bx, by, bz), mid), Vector3(wdt, 0.05, d.length() + 0.02), col)


## A horizontal ear: a plate rounded round a vertical pin at `c`, running
## `len` along `dir` (x-z) to where it's welded on, `t` thick.
func _vear(k: MeshKit, c: Vector3, dir: Vector3, len: float, r: float, t: float, col: Color) -> void:
	k.cylinder(Transform3D(Basis.IDENTITY, c - Vector3(0, t * 0.5, 0)), r, r, t, 18, col, true)
	var d := Vector3(dir.x, 0, dir.z).normalized()
	var mid := c + d * len * 0.5
	k.box(Transform3D(Basis.looking_at(d, Vector3.UP), mid), Vector3(r * 2.0, t, len), col)


## A plate (a lift arm or a bellcrank): from a to b, `t` thick, tapering from
## height h0 to h1, lying in the YZ plane.
static func _plate(kit: RefCounted, a: Vector3, b: Vector3, t: float, h0: float, h1: float, col: Color) -> void:
	var d := b - a
	var up := Vector3(0, -d.z, d.y).normalized() if absf(d.z) + absf(d.y) > 0.001 else Vector3.UP
	if up.y < 0.0:
		up = -up
	var rings: Array = []
	for e in [[a, h0], [b, h1]]:
		var p: Vector3 = e[0]
		var h: float = e[1]
		var ring := PackedVector3Array()
		ring.append(p + up * h * 0.5 + Vector3(-t * 0.5, 0, 0))
		ring.append(p + up * h * 0.5 + Vector3(t * 0.5, 0, 0))
		ring.append(p - up * h * 0.5 + Vector3(t * 0.5, 0, 0))
		ring.append(p - up * h * 0.5 + Vector3(-t * 0.5, 0, 0))
		rings.append(ring)
	kit.loft(rings, col, true, true)


static func _rod(kit: RefCounted, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	kit.cylinder(Transform3D(Basis(x, y, x.cross(y)), a), r, r, d.length(), 8, col, true)


func _wheel(parent: Node3D, at: Vector3, side: float, front: bool) -> void:
	# 20.5-25 loader tyres, L3 chevron lugs, on yellow disc wheels (tyre_mesh.gd)
	var wn := Node3D.new()
	wn.position = at
	var wmi := MeshInstance3D.new()
	wmi.mesh = TyreMesh.wheel(WHEEL_R, 0.52, 0.32, "lug", "disc", side, [0.0], "", YEL)
	wmi.material_override = MeshKit.material()
	wn.add_child(wmi)
	# the planetary final drive in the hub: a domed cap with its bolt ring and the
	# drain plug (the reference loaders' big hubs)
	var hk := MeshKit.new()
	var hb := Basis(Vector3.BACK, -PI * 0.5 * side)
	hk.cylinder(Transform3D(hb, Vector3(side * 0.2, 0, 0)), 0.3, 0.26, 0.12, 20, DARK, true)
	hk.cylinder(Transform3D(hb, Vector3(side * 0.32, 0, 0)), 0.2, 0.12, 0.06, 18, DARK, true)
	for b in range(10):
		var a := TAU * float(b) / 10.0
		hk.cylinder(Transform3D(hb, Vector3(side * 0.32, cos(a) * 0.23, sin(a) * 0.23)), 0.022, 0.022, 0.03, 6, Color(0.5, 0.5, 0.5), true)
	hk.cylinder(Transform3D(hb, Vector3(side * 0.38, 0.06, 0)), 0.025, 0.025, 0.02, 6, Color(0.6, 0.6, 0.6), true)
	wn.add_child(hk.instance("Hub"))
	parent.add_child(wn)
	_wheel_nodes.append([wn, front])


## A general-purpose bucket, 2.55 m wide, ~1.9 m3: the back curves round
## from the spill guard to a flat floor, a bolt-on edge with teeth; the hinge
## pins at the lower back and the link pin above (tool origin = hinge pin).
func _build_bucket() -> Node3D:
	var n := Node3D.new()
	n.name = "Bucket"
	var k := MeshKit.new()
	var bw := 2.55
	# profile (y, z) round the inside, from the top of the back to the cutting edge
	var shell := [Vector2(0.78, 0.0), Vector2(0.72, -0.18), Vector2(0.5, -0.3), Vector2(0.18, -0.36),
		Vector2(-0.18, -0.38), Vector2(-0.42, -0.5), Vector2(-0.53, -0.75), Vector2(-0.55, -1.32)]
	var inside := Color(0.50, 0.44, 0.36)            # worn steel, rust in the corners
	for i in range(shell.size() - 1):
		var p: Vector2 = shell[i]
		var q: Vector2 = shell[i + 1]
		var nrm := Vector3(0, -(q.y - p.y), (q.x - p.x)).normalized()
		if nrm.dot(Vector3(0, (p.x + q.x) * 0.5 + 0.1, (p.y + q.y) * 0.5 + 0.8)) < 0.0:
			nrm = -nrm
		k.quad(Vector3(-bw * 0.5, p.x, p.y), Vector3(bw * 0.5, p.x, p.y), Vector3(bw * 0.5, q.x, q.y), Vector3(-bw * 0.5, q.x, q.y), YEL, nrm)
		k.quad(Vector3(bw * 0.5, p.x, p.y), Vector3(-bw * 0.5, p.x, p.y), Vector3(-bw * 0.5, q.x, q.y), Vector3(bw * 0.5, q.x, q.y), inside, -nrm)
		# wear strips across the back
		if i == 3 or i == 5:
			k.box_at(Vector3(0, (p.x + q.x) * 0.5, (p.y + q.y) * 0.5) - nrm * 0.02, Vector3(bw - 0.1, 0.06, 0.06), YEL_D)
	# side plates: the profile closed off to a straight top edge raked forward
	for sx in [-bw * 0.5, bw * 0.5]:
		var c := Vector3(sx, 0.05, -0.75)
		var pts := shell + [Vector2(0.05, -1.25), Vector2(0.6, -0.25)]
		for j in range(pts.size()):
			var a: Vector2 = pts[j]
			var b: Vector2 = pts[(j + 1) % pts.size()]
			k.tri(c, Vector3(sx, a.x, a.y), Vector3(sx, b.x, b.y), YEL_D, Vector3(signf(sx), 0, 0))
			k.tri(c, Vector3(sx, b.x, b.y), Vector3(sx, a.x, a.y), inside, Vector3(-signf(sx), 0, 0))
		k.box_at(Vector3(sx, -0.25, -1.0), Vector3(0.06, 0.6, 0.55), STEEL.darkened(0.2))     # side cutters
	k.box_at(Vector3(0, -0.56, -1.3), Vector3(bw, 0.06, 0.16), STEEL.darkened(0.3))       # bolt-on edge
	for t in range(9):
		var tx := -1.12 + 0.28 * float(t)
		k.box(Transform3D(Basis(Vector3.RIGHT, 0.06), Vector3(tx, -0.55, -1.44)), Vector3(0.09, 0.08, 0.22), STEEL)       # tooth adapters
		k.box(Transform3D(Basis(Vector3.RIGHT, 0.06), Vector3(tx, -0.56, -1.58)), Vector3(0.07, 0.05, 0.14), Color(0.58, 0.58, 0.60))
	k.box_at(Vector3(0, 0.95, 0.0), Vector3(1.9, 0.34, 0.06), YEL_D)                     # spill guard
	for gx in [-0.6, 0.0, 0.6]:
		k.box_at(Vector3(gx, 0.95, 0.04), Vector3(0.06, 0.34, 0.06), YEL)
	# the bucket's body sits forward of its pins by the back plate's own depth:
	# moved back BUCKET_BACK so the back plate is right up against the ears (Dave:
	# the bucket wasn't attached - it hung 0.36 m off thin plates)
	var body := k.instance("BucketMesh")
	body.position = Vector3(0, 0, BUCKET_BACK)
	n.add_child(body)
	var ek := MeshKit.new()
	for ex in [-ARM_X, ARM_X]:
		EK.lug(ek, Vector3(ex, 0.0, 0.0), 0.075, 0.035, 0.12, Vector3(0, 0.3, -1), 0.2, YEL_D, 0.05)     # hinge ears welded on the back plate, the arm's end between them
	EK.lug(ek, ZB_C, 0.08, 0.035, 0.1, Vector3(0, -0.1, -1), 0.14, YEL_D, 0.045)          # the link's ear, high on the back plate
	n.add_child(ek.instance("BucketEars"))
	_dirt = MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(2.35, 0.6, 1.0)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.48, 0.37, 0.24)
	dm.material = dmat
	_dirt.mesh = dm
	_dirt.position = Vector3(0, -0.15, -0.75)
	_dirt.visible = false
	_dirt.position.z += BUCKET_BACK
	n.add_child(_dirt)
	return n


func _build_forks() -> Node3D:
	var n := Node3D.new()
	n.name = "Forks"
	var k := MeshKit.new()
	k.box_at(Vector3(0, -0.05, -0.12), Vector3(1.7, 0.1, 0.1), YEL_D)            # carriage bars
	k.box_at(Vector3(0, 0.55, -0.12), Vector3(1.7, 0.1, 0.1), YEL_D)
	for bx in [-0.8, -0.27, 0.27, 0.8]:
		k.box_at(Vector3(bx, 0.25, -0.12), Vector3(0.08, 0.7, 0.08), YEL_D)
	for tx in [-0.5, 0.5]:
		k.box_at(Vector3(tx, -0.15, -0.16), Vector3(0.14, 0.8, 0.08), DARK)       # tine shanks
		k.box_at(Vector3(tx, -0.53, -0.85), Vector3(0.14, 0.06, 1.4), DARK)       # tines
	n.add_child(k.instance("ForksMesh"))
	n.visible = false
	return n


func park(xf: Transform3D) -> void:
	body = WheeledBody.new()
	body.mass_empty = 10500.0
	body.com = Vector3(0, 1.1, 0.5)
	body.load_com = Vector3(0, 1.2, -3.2)
	body.size = Vector3(2.5, 3.3, 7.2)
	body.wheel_r = WHEEL_R
	body.travel = 0.12
	body.power = 140000.0          # ~190 hp: a 10 t loader's diesel (Dave: more power)
	body.top_speed = 9.0
	body.brake_force = 80000.0
	body.mu = 0.85
	body.max_steer = 0.6
	# Lockers front and rear, as loaders have for digging and mud (Dave):
	# both wheels on each axle pull, whatever one of them is sitting in.
	body.lock_front = true
	body.lock_rear = true
	for wz in [-WB * 0.5, WB * 0.5]:
		for wx in [-TRACK * 0.5, TRACK * 0.5]:
			body.wheels.append([Vector3(wx, WHEEL_R, wz), wz < 0.0, true])
	body.ground_y = func(x: float, z: float) -> float: return terrain.wheel_ground(x, z) if terrain.has_method("wheel_ground") else terrain.height_at(x, z)
	body.blocked = func(p: Vector3) -> bool: return terrain.blocked_by_building(p, 1.3, self)
	body.setup()
	var o := xf.origin
	o.y = terrain.height_at(o.x, o.z) + 0.05
	body.place(Transform3D(xf.basis, o))
	body.settle()
	global_transform = body.transform()
	yaw = body.yaw()
	_pose()


func eye_xf() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 2.8, 0.95))


func step_out_point() -> Vector3:
	return global_transform * Vector3(-1.7, 0, 0.7)


func fill() -> float:
	return clampf(_load_m3() / BUCKET_M3, 0.0, 1.0)


func _load_m3() -> float:
	return float(bucket_load.get("over", 0.0)) + float(bucket_load.get("pay", 0.0)) + float(bucket_load.get("rock", 0.0))


## The cutting edge (or fork tips) in the world.
func lip() -> Vector3:
	return _tool.global_transform * (LIP if attach == "bucket" else Vector3(0, -0.53, -1.55))


## E: swap bucket and forks on the quick coupler (bucket empty, arms low).
func swap_attachment() -> String:
	if attach == "bucket" and not bucket_load.is_empty():
		return "Dump the bucket before you swap it."
	if lift > 0.35:
		return "Lower the arms to swap attachments."
	attach = "forks" if attach == "bucket" else "bucket"
	_bucket.visible = attach == "bucket"
	_forks.visible = attach == "forks"
	tilt = 0.0
	return "Forks on." if attach == "forks" else "Bucket on."


## One physics step while driven. move: x steer, y throttle (back brakes,
## then reverses). lift_in / tilt_in -1..1.
func drive(delta: float, move: Vector2, lift_in: float, tilt_in: float, handbrake: bool) -> String:
	var msg := ""
	lift = clampf(lift + lift_in * 0.33 * delta, 0.0, 1.0)
	var tilt_was := tilt
	tilt = clampf(tilt + tilt_in * 0.9 * delta, TILT_DUMP, TILT_RACK)
	_pose()
	if zbar_overstroke() > 0.0 and tilt_in != 0.0:
		tilt = tilt_was                  # the tilt cylinder is at the end of its stroke
	_pose()
	# The bucket can't go into the ground: the arms float on it.
	var lp := lip()
	var gy: float = terrain.height_at(lp.x, lp.z)
	var guard := 0
	while lp.y < gy - 0.12 and lift < 1.0 and guard < 40:
		lift = minf(lift + 0.01, 1.0)
		_pose()
		lp = lip()
		guard += 1
	body.load_kg = _load_m3() * DIRT_KG
	var digging := attach == "bucket" and lp.y < gy + 0.18 and tilt > -0.3 and tilt < 0.4 and fill() < 0.999
	body.step(delta, move.y, move.x, handbrake)
	global_transform = body.transform()
	yaw = body.yaw()
	var sp: float = body.speed
	if engine != null:
		engine.drive_strain = engine.travel_strain(move.y, 4.0, sp)     # (a working gear's few m/s)
	if digging and sp > 0.25:
		_cut_acc += sp * delta
		if _cut_acc > 0.35 and on_dig.is_valid():
			_cut_acc = 0.0
			var room := BUCKET_M3 - _load_m3()
			# a heap (loose, above the natural ground) loads easily; firm
			# ground the bucket only scrapes a skin off
			var loose: bool = gy > terrain.natural_at(lp.x, lp.z) + 0.1
			var got: Dictionary = on_dig.call(Vector3(lp.x, gy, lp.z), 1.1, minf(room, 0.4 if loose else 0.06))
			var vol := float(got.get("over", 0.0)) + float(got.get("pay", 0.0)) + float(got.get("rock", 0.0))
			if vol > 0.0:
				for kk in ["over", "pay", "g", "rock"]:
					bucket_load[kk] = float(bucket_load.get(kk, 0.0)) + float(got.get(kk, 0.0))
				# filling the bucket takes push
				body.vel -= -global_transform.basis.z * minf(sp, 0.25)
			elif bool(got.get("bedrock", false)):
				msg = "The bucket skates on bedrock."
			if fill() >= 0.999:
				msg = "Bucket full: curl it back and lift."
	# Tipped forward with something in it: it pours out.
	if not bucket_load.is_empty() and tilt < -0.55:
		msg = _dump_now()
	_animate()
	return msg


func _dump_now() -> String:
	var lp := lip()
	var hop: Vector3 = hopper_at.call(lp) if hopper_at.is_valid() else Vector3.INF
	if hop != Vector3.INF and lp.y < hop.y + 0.1:
		# Into the side of the hopper: it won't go in. Keep it in the bucket.
		if not _told_high:
			_told_high = true
			var base := global_position.y
			return "The hopper's lip is %.1f m above you and the bucket only gets to %.1f m: build a dirt ramp up to it (the dozer), or feed it with the excavator." % [hop.y - base, lp.y - base]
		return ""
	_told_high = false
	var at := Vector3(lp.x, terrain.height_at(lp.x, lp.z), lp.z)
	var l := bucket_load
	bucket_load = {}
	_dirt.visible = false
	return on_dump.call(at, l) if on_dump.is_valid() else ""


func _pose() -> void:
	if _arms == null:
		return
	var a := lerpf(A_DOWN, A_UP, lift)
	_arms.rotation = Vector3(a, 0, 0)
	_tool.rotation = Vector3(-a + tilt, 0, 0)       # parallel lift: tilt is to the ground
	_zbar_pose()
	for lc in _lift_cyl:
		var anchor: Vector3 = lc[1]
		var end: Vector3 = _front.global_transform.affine_inverse() * (_arms.global_transform * (lc[2] as Vector3)) if is_inside_tree() else ARM_PIVOT + Basis(Vector3.RIGHT, a) * (lc[2] as Vector3)
		var d: Vector3 = end - anchor
		var y := d.normalized()
		var x := y.cross(Vector3.FORWARD).normalized()
		(lc[0] as MeshInstance3D).transform = Transform3D(Basis(x, y * d.length(), x.cross(y)), anchor)
	_dirt.visible = attach == "bucket" and not bucket_load.is_empty() and tilt > -0.4
	if _dirt.visible:
		_dirt.scale = Vector3(1, clampf(fill(), 0.25, 1.0), 1)


## Lay the Z-bar for the bucket's angle: the link's ear on the bucket is where
## it is; the lever's foot is where a circle round the lever's pin meets a
## circle round that ear; the lever turns to put its foot there.
var _zb_ang := 0.0
func _zbar_pose() -> void:
	if _crank == null:
		return
	var c := Vector3(0, 0, -ARM_L) + _tool.transform.basis * ZB_C
	var f := ZB_F
	var r1 := Vector2(ZB_H.y, ZB_H.z).length()
	var p1 := Vector2(f.y, f.z)
	var p2 := Vector2(c.y, c.z)
	var d := clampf(p1.distance_to(p2), absf(r1 - _zlink_len) + 0.001, r1 + _zlink_len - 0.001)
	var aa := (r1 * r1 - _zlink_len * _zlink_len + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, r1 * r1 - aa * aa))
	var u := (p2 - p1).normalized()
	var m := p1 + u * aa
	var perp := Vector2(u.y, -u.x)
	var q1 := m + perp * h
	var q2 := m - perp * h
	var want := atan2(ZB_H.z, ZB_H.y) + _zb_ang
	var hprev := p1 + Vector2(cos(want), sin(want)) * r1
	var q := q1 if q1.distance_to(hprev) < q2.distance_to(hprev) else q2
	_zb_ang = atan2(q.y - p1.y, q.x - p1.x) - atan2(ZB_H.z, ZB_H.y)
	_crank.rotation.x = _zb_ang
	_zlink.position = Vector3(0, q.x, q.y)
	_zlink.rotation.x = atan2(p2.x - q.x, -(p2.y - q.y))


## The tilt cylinder past the end of its stroke (the bucket can't tilt further there).
## The test bed's damage buttons (Dave: a damaged line leaks, the load sinks).
func damage_line() -> String:
	if hyd == null:
		_hyd_setup()
	return EK.damage_line(self)


func repair_lines() -> String:
	return EK.repair_lines(self)


func zbar_overstroke() -> float:
	if _tilt_ram == null:
		return 0.0
	var L := _ram_len(_tilt_ram)
	return maxf(0.0, L - ZB_RAM_MAX) + maxf(0.0, ZB_RAM_MIN - L)


func _animate() -> void:
	if body == null:
		return
	_front.rotation = Vector3(0, body.steer, 0)
	for i in range(_wheel_nodes.size()):
		var wn: Node3D = _wheel_nodes[i][0]
		var spin: float = float(body.wheel_spin[i]) if i < body.wheel_spin.size() else 0.0
		wn.rotation = Vector3(-spin, 0, 0)


func status() -> String:
	if attach == "forks":
		return "Loader, forks on: arms %d%%   %s swap to the bucket" % [int(lift * 100.0), Game.hint("interact")]
	return "Loader: bucket %.1f / %.1f m3, arms %d%%, %s   %s swap to forks" % [_load_m3(), BUCKET_M3, int(lift * 100.0),
		"dumping" if tilt < -0.55 else ("curled" if tilt > 0.35 else "level"), Game.hint("interact")]


func controls_hint() -> String:
	return "In the loader. %s drive (back on %s brakes, then reverses), %s / %s raise / lower the arms, %s / %s curl / dump the bucket, %s swap bucket and forks, %s get out. Drive into dirt with the bucket flat on the ground to fill it." % [
		"W A S D", "S", Game.lever_hint(true), Game.lever_hint(false), Game.hint("flaps_up"), Game.hint("flaps_down"), Game.hint("interact"), Game.hint("get_out")]


var _demo_t := 0.0


func _process(delta: float) -> void:
	if not driven and EK.in_lab(self):     # in the lab: works the levers herself; the hydraulics move her
		_demo_t += delta
		if hyd == null:
			_hyd_setup()
		if engine.state == "off" and _demo_t < 1.0:
			engine.ambient = -12.0               # a winter morning in the lab: the hard start
			engine.temp = -12.0
			engine.start()
		var run: bool = engine.state == "running" and fmod(_demo_t, 14.0) < 9.0   # work, then hands off: auto-idle
		hyd.rpm = engine.rpm
		hyd.rams[0].spool = sin(_demo_t * 0.4) if run else 0.0
		hyd.rams[1].spool = sin(_demo_t * 0.7 + 1.0) if run else 0.0
		engine.load = clampf(hyd.pressure / hyd.relief, 0.0, 1.0)
		engine.strain = hyd.strain()          # revs only when the oil can't move the load
		engine.hyd_power_max = 75000.0
		hyd.power_avail = engine.hyd_power()      # the pump gets only what the engine can give at these revs
		# the operator opens the throttle while working the levers (Dave: throttle up to lift), back to idle when hands off
		var lever := 0.0
		for r_ in hyd.rams:
			lever = maxf(lever, absf(r_.spool))
		engine.throttle = move_toward(engine.throttle, 0.85 if lever > 0.25 else 0.0, (0.8 if lever > 0.25 else 0.5) * delta)
		engine.drive_strain = 0.0
		hyd.depth = func() -> float: return maxf(0.0, -0.05 - (global_transform.affine_inverse() * (_tool.global_transform * LIP)).y) + zbar_overstroke() * 10.0
		hyd.drive(delta, _joints, _potential, _pose)
		if body != null:          # steering: the frame bends on its hinge, the steering rams stroke (through body.steer: the test bed lays the frame from it)
			body.steer = sin(_demo_t * 0.3) * 0.45 * (1.0 if engine.state == "running" else 0.0)
		_pump_label.text = hyd.summary() + "\nENGINE " + engine.status()
		# and gets washed and dirty again, slowly, to show it (Dave: wash her clean,
		# the damage and scratches stay)
		var want := snappedf(0.5 + 0.5 * cos(_demo_t * 0.25), 0.1)
		if absf(want - float(get_meta("ek_dirt", 1.0))) > 0.05:
			EK.set_dirt(self, want)
	if not driven:
		_animate()
	_save_t += delta
	if _save_t > 10.0:
		_save_t = 0.0
		save()


## The hydraulics (Dave): a 160 L/min pump at 2100 rpm, 280 bar relief; the two
## 120 mm lift rams (as one 170), the 140 mm tilt ram.
func _hyd_setup() -> void:
	var HS = ResourceLoader.load("res://scripts/hyd_system.gd", "", ResourceLoader.CACHE_MODE_REPLACE)
	hyd = HS.new()
	hyd.displacement = 0.076
	hyd.rpm = 2100.0
	hyd.relief = 280.0
	var rl = hyd.add_ram("LIFT", 170.0, 120.0)
	var rt = hyd.add_ram("TILT", 140.0, 90.0)
	var lr0: Node3D = _rams_lift[0]
	var trm: Node3D = _tilt_ram
	for lrv in _rams_lift:
		lrv.sim_ram = rl
	trm.sim_ram = rt
	_joints = [
		{"ram": rl, "get": func(): return lift, "set": func(v): lift = v, "length": func(): return _ram_len(lr0), "lo": 0.0, "hi": 1.0,
			"label": HS.make_label(self), "at": func(): return lr0.mid_global() + Vector3(-0.9, 0.6, 0)},
		{"ram": rt, "get": func(): return tilt, "set": func(v): tilt = v, "length": func(): return _ram_len(trm), "lo": TILT_DUMP, "hi": TILT_RACK,
			"label": HS.make_label(self), "at": func(): return trm.mid_global() + Vector3(0, 0.7, 0)}]
	_pump_label = HS.make_label(self)
	_pump_label.position = Vector3(0, 4.2, 1.0)


func _ram_len(r: Node3D) -> float:
	var e: Array = r._ends()
	return (e[0] as Vector3).distance_to(e[1] as Vector3)


## The arms, the tool and what's in it, weight x height.
func _potential() -> float:
	return 9.81 * (1500.0 * (_arms.global_transform * Vector3(0, -0.2, -ARM_L * 0.5)).y
		+ (1200.0 + fill() * BUCKET_M3 * DIRT_KG) * (_tool.global_transform * Vector3(0, 0, -0.7)).y)



func lights_toggle() -> String:
	return EK.lights_toggle(self)


## Wash her: the dirt and dust come off, the scratches and dents stay.
func wash() -> void:
	EK.set_dirt(self, 0.0)


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("l", "xf", global_transform)
	cf.set_value("l", "attach", attach)
	cf.set_value("l", "load", bucket_load)
	cf.set_value("l", "lift", lift)
	cf.save(SAVE)


## The saved loader, or a new one parked by the mining pad.
func load_or_default() -> void:
	var cf := ConfigFile.new()
	var pad: Vector3 = terrain.clearings[1] if terrain.clearings.size() > 1 else Vector3(62, 0, 48)
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(pad.x - 13.0, 0, pad.y - 12.0))   # clearings are (x, z, radius)
	if cf.load(SAVE) == OK:
		xf = cf.get_value("l", "xf", xf)
		attach = String(cf.get_value("l", "attach", "bucket"))
		bucket_load = cf.get_value("l", "load", {})
		lift = float(cf.get_value("l", "lift", 0.0))
	park(xf)
	_bucket.visible = attach == "bucket"
	_forks.visible = attach == "forks"
	_pose()


## Where a winch hook or tow strap can go: [[name, world point], ...].
func winch_points() -> Array:
	return TowPoints.world(_front, WINCH_POINTS_FRONT) + TowPoints.world(self, WINCH_POINTS_REAR)
