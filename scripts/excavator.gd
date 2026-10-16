extends Node3D
## A mid-size tracked excavator (about 14 t, the size that feeds a wash
## plant's hopper) for the claims. Modelled at 5 t scale and drawn x SCALE. Get in (interact),
## drive on its tracks with the walk keys, and work the arm by looking: the
## cab swings and the boom reaches to where you look on the ground. Interact
## digs a bucketful there; interact again dumps it where you're looking: into
## the wash plant's hopper to wash the gold out of it, or anywhere else as a
## pile of spoil. The ground really changes (dig_site.gd).

const MeshKit = preload("res://scripts/meshkit.gd")
const TrackLoop = preload("res://scripts/track_loop.gd")
const TrackedBody = preload("res://scripts/tracked_body.gd")
const EK = preload("res://scripts/equip_kit.gd")

const YELLOW := Color(0.92, 0.70, 0.14)          # the early-80s excavators in the reference
const DARK := Color(0.12, 0.12, 0.12)
const STEEL := Color(0.40, 0.40, 0.42)
const GLASS := Color(0.15, 0.2, 0.25)
const BRIGHT := Color(0.80, 0.81, 0.83)        # chromed ram rods
const SCALE := 1.45               # the whole machine; the arm maths runs in model units
const BUCKET_M3 := 0.85
const L1 := 3.17                  # boom, foot pin to stick pin (4.6 m)
const L2 := 1.72                  # stick (2.5 m)
const PIVOT := Vector3(0.18, 0.62, -0.95)   # boom foot on the house (cab space)
# The cylinder mounts and the bucket linkage (Dave: real clevises at every pin,
# laid out from the real linkage - stick, idler link, power link, bucket ram):
const BOOM_RAM_X := 0.21                        # the boom rams either side of the boom
const BOOM_RAM_BASE := Vector3(0, -0.34, -0.2)  # their base pins on the house, from PIVOT
const BOOM_RAM_ROD := Vector3(0, 0.02, -L1 * 0.45)   # the cross pin under the boom (boom frame)
const STICK_RAM_BASE := Vector3(0, 0.26, 0.45)  # stick ram base on the boom's back, from the knee
const STICK_RAM_ROD := Vector3(0, 0.44, 0.38)   # its rod eye on the stick's tail
const BKT_RAM_BASE := Vector3(0, 0.40, 0.02)    # bucket ram base on top of the stick
const LINK_P7 := Vector3(0, 0.17, -1.50)        # idler links' pin through the stick
const LINK_P10 := Vector3(0, 0.22, -0.05)       # power link's pin on the bucket (bucket frame)
const LINK_IDLER := 0.30                        # idler link, pin to pin
const LINK_POWER := 0.35                        # power link, pin to pin
const REACH_MIN := 2.0 * SCALE
const REACH_MAX := 5.4 * SCALE

var terrain: RefCounted
var yaw := 0.0                    # tracks
var swing := 0.0                  # cab relative to tracks
var driven := false
var home := Transform3D.IDENTITY
var aim := Vector3.ZERO           # where the arm reaches (world)
var bucket_load := {}                    # what's in the bucket: {over, pay, kg}
var state := ""                   # "", "dig", "dump"
var _t := 0.0
var _did := false
var _tip := Vector3.ZERO          # bucket tip now (world)
var _curl := 0.0                  # bucket angle: 0 open, 1 curled (full)
var _tracks: Node3D
var _track_l: MultiMeshInstance3D
var _track_r: MultiMeshInstance3D
var _cab: Node3D
var _boom: Node3D
var _stick: Node3D
var _bucket: Node3D
var _dirt: MeshInstance3D
var on_dig: Callable              # func(point, m3) -> Dictionary (does the digging)
var on_dump: Callable             # func(point, load) -> String (pile or wash)
var on_cut: Callable              # func(point, floor_y, m3) -> Dictionary (teeth dragged through ground)
var hopper_at: Callable           # func(point) -> Vector3 hopper top near there, or INF
var on_message: Callable          # func(text) - a line for the HUD

# Arm joints (radians). Easy mode drives them by IK; lever mode drives them direct.
const TEETH := Vector3(0, -0.46, -0.58)       # bucket teeth tips in the bucket's frame
const BOOM_MIN := -0.95
const BOOM_MAX := 1.15
const KNEE_MIN := 0.25
const KNEE_MAX := 2.7
const BKT_MIN := -1.0             # wide open: dumping
const BKT_MAX := 1.35             # curled shut: carrying
var boom_a := 0.4
var knee := 1.2
var bucket_a := 0.0
## Control modes (DESIGN_NOTES 152): 0 auto (look where to dig, the arm
## follows), 1 boom (auto, but the triggers / Shift-Ctrl raise and lower the
## bucket yourself: push it down on a bank to lever her out of a hole),
## 2 levers (every joint by hand).
var mode := 0
var levers: bool:
	get:
		return mode == 2
	set(v):
		mode = 2 if v else 0
var boom_off := 0.0              # boom mode: how far above / below the auto height the bucket is held (m)
var boom_in := 0.0               # boom mode: this frame's trigger input, -1..1
var _move := Vector2.ZERO
var _push_f := Vector3.ZERO      # the planted bucket's push on the machine (applied next step)
var _push_pt := Vector3.ZERO
const MODE_NAMES := ["Auto", "Boom", "Levers"]
var body: RefCounted              # tracked_body.gd: the real physics
var kinematic := false
var _cut_acc := 0.0
var _resist := 0.0                # 0..1 how hard the ground is pushing back (for sound / shake)


## The model (DESIGN_NOTES 149), rebuilt to a real 14 t excavator's
## proportions (drawn in model units x SCALE): 3.65 m crawlers on a 2 m
## gauge with 600 mm shoes - an X-frame between the track frames, the drive
## sprocket and its motor at the back, the idler and the track adjuster at
## the front, rollers under, carrier rollers on top; the upper on its swing
## bearing ~0.9 m up, 2.5 m wide: the cab front left with its ROPS-shaped
## glass, the boom foot in the middle front, the engine hood and the
## hydraulic tank behind on the right, a heavy rounded counterweight; the
## curved ("banana") boom with its twin lift rams, the stick with its ram
## on the boom, the bucket ram and the H-link and dogbone to the bucket.
var seat: Node3D
var engine: Node3D


func control_click(nm: String) -> String:
	if nm == "seat_air" and seat != null:
		return seat.air()
	return ""



func lights_toggle() -> String:
	return EK.lights_toggle(self)


const TowPoints = preload("res://scripts/tow_points.gd")
## Winch / tow points (DESIGN_NOTES 225): a shackle front and back on the
## undercarriage's centre frame, between the tracks (model units: the
## undercarriage is drawn x SCALE).
const WINCH_POINTS := [
	["front tow shackle", Vector3(0, 0.30, -0.45), Vector3(0, 0, -1)],
	["rear tow shackle", Vector3(0, 0.30, 0.45), Vector3(0, 0, 1)],
]

func build() -> void:
	_tracks = Node3D.new()
	var tk := MeshKit.new()
	var zc := 1.26                         # sprocket / idler centres from the middle
	for sx in [-0.69, 0.69]:
		var sgn := signf(sx)
		# track frame: a box beam the length of the crawler, sloped ends
		tk.box_at(Vector3(sx, 0.32, 0), Vector3(0.24, 0.26, 2.2), YELLOW.darkened(0.3))
		tk.box(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(sx, 0.3, -1.08)), Vector3(0.22, 0.2, 0.3), YELLOW.darkened(0.3))
		tk.box(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(sx, 0.3, 1.08)), Vector3(0.22, 0.2, 0.3), YELLOW.darkened(0.3))
		# (the idler, the sprocket and the final drive are built below, from the
		# photos: they turn with the chain - _track_wheels)
		# the idler's yoke guides: the front of the frame is a slot the yoke slides in
		for gy in [0.42, 0.18]:
			tk.box_at(Vector3(sx, gy, -zc + 0.36), Vector3(0.24, 0.04, 0.42), YELLOW.darkened(0.3))
		# the tensioner's grease valve, behind a cover plate on the frame's outside
		tk.box_at(Vector3(sx + sgn * 0.123, 0.32, -0.62), Vector3(0.008, 0.16, 0.2), YELLOW.darkened(0.38))
		for bz in [-0.70, -0.54]:
			for by in [0.26, 0.38]:
				tk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5) if sgn < 0.0 else Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx + sgn * 0.127, by, bz)), 0.008, 0.008, 0.01, 6, STEEL.darkened(0.3))
		# bottom rollers and two carrier rollers on top
		for rz in [-0.8, -0.4, 0.0, 0.4, 0.8]:
			tk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.12, 0.13, rz)), 0.09, 0.09, 0.24, 8, STEEL)
		for cz in [-0.45, 0.45]:
			tk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.08, 0.5, cz)), 0.06, 0.06, 0.16, 8, STEEL)
		# track guard plates on the outside of the frame
		tk.box_at(Vector3(sx + sgn * 0.13, 0.2, 0), Vector3(0.02, 0.1, 1.8), YELLOW.darkened(0.35))
	# the X-frame centre and the swing bearing
	tk.box_at(Vector3(0, 0.36, 0), Vector3(1.2, 0.24, 0.9), YELLOW.darkened(0.25))
	for d in [-1.0, 1.0]:
		tk.box(Transform3D(Basis(Vector3.UP, d * 0.6), Vector3(0, 0.34, 0)), Vector3(1.6, 0.18, 0.3), YELLOW.darkened(0.25))
	tk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.48, 0)), 0.5, 0.5, 0.14, 18, DARK)
	_tracks.add_child(tk.instance("Tracks"))
	_track_l = TrackLoop.new()
	_track_l.setup(-0.69, zc, 0.045, 0.6, 62, Vector3(0.41, 0.035, 0.1), Color(0.19, 0.19, 0.19))
	_tracks.add_child(_track_l)
	_track_r = TrackLoop.new()
	_track_r.setup(0.69, zc, 0.045, 0.6, 62, Vector3(0.41, 0.035, 0.1), Color(0.19, 0.19, 0.19))
	_tracks.add_child(_track_r)
	_track_wheels(zc)
	_tracks.scale = Vector3.ONE * SCALE
	add_child(_tracks)
	# --- the upper (swings) ----------------------------------------------------
	_cab = Node3D.new()
	_cab.position = Vector3(0, 0.62, 0)
	var ck := MeshKit.new()
	# the deck: a slab 1.72 wide from the boom foot back to the counterweight
	ck.box_at(Vector3(0, 0.08, 0.05), Vector3(1.72, 0.16, 2.0), YELLOW.darkened(0.25))
	# boom foot: a raised casting in the middle front, between two cheek plates
	# the boom foot clevis: two deep cheek plates rounded round the pin, the boom between
	EK.lug(ck, PIVOT, 0.16, 0.06, 0.2, Vector3(0, -1, 0.35), 0.5, YELLOW.darkened(0.1), 0.085)
	ck.box_at(Vector3(PIVOT.x, 0.28, -0.62), Vector3(0.34, 0.36, 0.6), YELLOW.darkened(0.15))
	for rx in [-BOOM_RAM_X, BOOM_RAM_X]:
		EK.lug(ck, PIVOT + Vector3(rx, BOOM_RAM_BASE.y, BOOM_RAM_BASE.z), 0.045, 0.03, 0.085, Vector3(0, -1, 0.2), 0.12, YELLOW.darkened(0.2))   # boom ram base clevis, off the deck
	# the cab: front left, glass on three sides, a roof that overhangs a little
	var cx := -0.48
	ck.box_at(Vector3(cx, 0.21, -0.25), Vector3(0.66, 0.1, 1.15), DARK)                    # cab floor
	for px in [cx - 0.32, cx + 0.32]:
		for pz in [-0.8, 0.3]:
			ck.box_at(Vector3(px, 0.82, pz), Vector3(0.05, 1.22, 0.05), DARK)
	ck.box_at(Vector3(cx, 1.45, -0.25), Vector3(0.72, 0.06, 1.2), YELLOW)                  # roof
	ck.box_at(Vector3(cx, 1.41, -0.86), Vector3(0.7, 0.05, 0.05), DARK)
	ck.box_at(Vector3(cx + 0.32, 0.55, -0.25), Vector3(0.04, 0.6, 1.1), YELLOW.darkened(0.05))   # right lower panel
	for jx in [cx - 0.18, cx + 0.18]:
		ck.box_at(Vector3(jx, 0.6, -0.42), Vector3(0.1, 0.18, 0.28), DARK)                # armrest consoles
		ck.cylinder(Transform3D(Basis.IDENTITY, Vector3(jx, 0.69, -0.48)), 0.02, 0.018, 0.12, 6, DARK)    # joysticks
	_bar(ck, Vector3(cx - 0.36, 0.3, -0.75), Vector3(cx - 0.36, 1.25, -0.75), 0.014, STEEL)   # grab rail
	# the right-hand side: a tool box up front, the hydraulic tank, the fuel tank
	ck.box_at(Vector3(0.6, 0.38, -0.55), Vector3(0.48, 0.42, 0.55), YELLOW)
	ck.box_at(Vector3(0.6, 0.5, 0.05), Vector3(0.5, 0.66, 0.6), YELLOW.darkened(0.04))
	ck.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.65, 0.83, 0.05)), 0.05, 0.05, 0.04, 8, DARK)
	# engine hood across the back, louvred, the exhaust and the air cleaner
	ck.box_at(Vector3(0, 0.52, 0.6), Vector3(1.66, 0.72, 0.5), YELLOW)
	ck.box_at(Vector3(0, 0.9, 0.6), Vector3(1.5, 0.05, 0.45), YELLOW.darkened(0.1))
	for lz in range(5):
		ck.box_at(Vector3(0.835, 0.55, 0.42 + 0.09 * float(lz)), Vector3(0.012, 0.4, 0.04), DARK)
		ck.box_at(Vector3(-0.835, 0.55, 0.42 + 0.09 * float(lz)), Vector3(0.012, 0.4, 0.04), DARK)
	ck.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.35, 0.92, 0.55)), 0.04, 0.035, 0.28, 8, DARK)
	ck.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.2, 0.92, 0.65)), 0.09, 0.09, 0.12, 10, DARK)
	# the counterweight: a heavy rounded slab at the very back
	var cw: Array = []
	for i in range(9):
		var ang := -PI * 0.5 + PI * float(i) / 8.0
		cw.append(Vector3(sin(ang) * 0.86, 0, 0.85 + cos(ang) * 0.38))
	for i in range(8):
		var p0: Vector3 = cw[i]
		var p1: Vector3 = cw[i + 1]
		ck.quad(p0 + Vector3(0, 0.0, 0), p1 + Vector3(0, 0.0, 0), p1 + Vector3(0, 0.68, 0), p0 + Vector3(0, 0.68, 0), YELLOW.darkened(0.12), (p0 + p1) * 0.5 - Vector3(0, 0, 0.85))
		ck.tri(Vector3(0, 0.68, 0.85), p0 + Vector3(0, 0.68, 0), p1 + Vector3(0, 0.68, 0), YELLOW.darkened(0.12), Vector3.UP)
		ck.tri(Vector3(0, 0.0, 0.85), p1, p0, YELLOW.darkened(0.12), Vector3.DOWN)
	ck.box_at(Vector3(0, 0.3, 1.24), Vector3(1.2, 0.08, 0.02), DARK)                       # the lifting eyes' line
	for hx in [-0.55, 0.55]:
		ck.box_at(Vector3(hx, 0.4, 1.235), Vector3(0.2, 0.36, 0.015), Color(0.16, 0.16, 0.16))
		ck.box_at(Vector3(hx, 0.4, 1.24), Vector3(0.2, 0.08, 0.02), YELLOW)
	# handrails along the top of the right side
	_bar(ck, Vector3(0.82, 0.92, -0.75), Vector3(0.82, 0.92, 0.3), 0.012, STEEL)
	_cab.add_child(ck.instance("Cab"))
	# The glazing: windscreen, left side and door, the rear and right quarter.
	var gk := MeshKit.new()
	var fr := MeshKit.new()
	var seal := MeshKit.new()
	var fz := -0.82
	EK.pane(gk, seal, Vector3(cx - 0.29, 0.27, fz), Vector3(cx + 0.29, 0.27, fz), Vector3(cx + 0.29, 1.38, fz), Vector3(cx - 0.29, 1.38, fz), Vector3(0, 0, -1))
	EK.pane(gk, seal, Vector3(cx - 0.33, 0.32, 0.27), Vector3(cx - 0.33, 0.32, -0.77), Vector3(cx - 0.33, 1.38, -0.77), Vector3(cx - 0.33, 1.38, 0.27), Vector3(-1, 0, 0))
	EK.pane(gk, seal, Vector3(cx + 0.29, 0.72, 0.31), Vector3(cx - 0.29, 0.72, 0.31), Vector3(cx - 0.29, 1.38, 0.31), Vector3(cx + 0.29, 1.38, 0.31), Vector3(0, 0, 1))
	EK.pane(gk, seal, Vector3(cx + 0.33, 0.9, -0.77), Vector3(cx + 0.33, 0.9, 0.27), Vector3(cx + 0.33, 1.38, 0.27), Vector3(cx + 0.33, 1.38, -0.77), Vector3(1, 0, 0))
	_cab.add_child(seal.instance("Seals"))
	fr.box_at(Vector3(cx - 0.33, 0.85, -0.2), Vector3(0.025, 1.12, 0.03), DARK)     # door split
	fr.box_at(Vector3(cx - 0.345, 0.66, 0.0), Vector3(0.03, 0.04, 0.15), STEEL)     # door handle
	fr.box_at(Vector3(cx, 0.55, -0.83), Vector3(0.62, 0.03, 0.02), DARK)            # screen rail
	var gmesh := gk.instance("Glass")
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.50, 0.62, 0.68, 0.38)
	gmat.roughness = 0.08
	gmat.metallic = 0.2
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gmesh.material_override = gmat
	gmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cab.add_child(gmesh)
	_cab.add_child(fr.instance("CabTrim"))
	_tracks.add_child(_cab)
	# --- the boom: a curved box section, two lift rams under it ------------------
	_boom = Node3D.new()
	_boom.position = PIVOT
	var bk := MeshKit.new()
	var knee := Vector3(0, 0.42, -L1 * 0.48)          # the bend, above the straight line
	_box_beam(bk, Vector3(0, 0, 0), knee, 0.3, 0.36, 0.42, YELLOW)
	_box_beam(bk, knee, Vector3(0, 0, -L1), 0.3, 0.42, 0.26, YELLOW)
	bk.box(Transform3D(Basis.IDENTITY, knee), Vector3(0.32, 0.46, 0.4), YELLOW.darkened(0.05))
	var bmk := MeshKit.new()
	# (the boom, stick and bucket rams are working rams: _rams(), after the parts exist)
	# a work lamp on the boom's left side, aimed at the bucket
	EK.lamp(bk, bmk, _boom, knee + Vector3(-0.2, 0.05, 0.2), Vector3(0, -0.35, -1), 0.13, 0.13, Color(1, 0.97, 0.85), true)
	var bmi := bmk.instance("BoomMetal")
	bmi.material_override = EK.metal_mat()
	_boom.add_child(bmi)
	# hard lines: steel tubes up the boom in their clamps (flexible hoses only
	# across the joints and to the rams - hyd_hose.gd)
	for hx2 in [-0.06, 0.06]:
		_bar(bk, Vector3(hx2, 0.22, -0.1), knee + Vector3(hx2, 0.24, 0), 0.012, Color(0.58, 0.59, 0.61))
		_bar(bk, knee + Vector3(hx2, 0.24, 0), Vector3(hx2, 0.16, -L1 + 0.15), 0.012, Color(0.58, 0.59, 0.61))
	for cf in [0.25, 0.7]:
		bk.box_at(Vector3(0, 0.22, -0.1).lerp(knee + Vector3(0, 0.24, 0), cf), Vector3(0.2, 0.04, 0.05), Color(0.15, 0.15, 0.15))
		bk.box_at((knee + Vector3(0, 0.24, 0)).lerp(Vector3(0, 0.16, -L1 + 0.15), cf), Vector3(0.2, 0.04, 0.05), Color(0.15, 0.15, 0.15))
	EK.pin(bk, Vector3(0, 0, 0), 0.15, 0.11, YELLOW.darkened(0.2))            # the boom foot boss (the house's cheeks outside it)
	# the lugs the boom rams' rod eyes pin into, welded to the boom's sides
	# (one bracket under the boom, its long cross pin out to both rams' rod eyes)
	EK.lug(bk, BOOM_RAM_ROD, 0.09, 0.04, 0.1, Vector3(0, 1, 0), 0.2, YELLOW.darkened(0.15), 0.04, BOOM_RAM_X + 0.06)
	# and the stick ram's base clevis on the boom's back
	EK.lug(bk, knee + STICK_RAM_BASE, 0.045, 0.03, 0.085, Vector3(0, -1, 0), 0.19, YELLOW.darkened(0.15))
	EK.pin(bk, Vector3(0, 0, -L1), 0.15, 0.09, YELLOW.darkened(0.2))          # the stick pin
	_boom.add_child(bk.instance("Boom"))
	_cab.add_child(_boom)
	# --- the stick: a tapered box with the bucket ram and the link on top --------
	_stick = Node3D.new()
	_stick.position = Vector3(0, 0, -L1)
	var sk := MeshKit.new()
	_box_beam(sk, Vector3(0, 0.12, 0.35), Vector3(0, 0, -L2), 0.22, 0.42, 0.22, YELLOW)    # with the tail above the pin
	EK.lug(sk, STICK_RAM_ROD, 0.045, 0.03, 0.085, Vector3(0, -1, 0), 0.12, YELLOW.darkened(0.1))   # stick ram's rod clevis on the tail
	EK.lug(sk, BKT_RAM_BASE, 0.04, 0.03, 0.075, Vector3(0, -1, 0), 0.12, YELLOW.darkened(0.1))     # bucket ram's base clevis
	var smk := MeshKit.new()
	var smi := smk.instance("StickMetal")
	smi.material_override = EK.metal_mat()
	_stick.add_child(smi)
	for hx4 in [-0.05, 0.05]:
		_bar(sk, Vector3(hx4, 0.25, 0.05), Vector3(hx4, 0.3, 0.25), 0.01, Color(0.58, 0.59, 0.61))     # stick hard lines
		sk.box_at(Vector3(0, 0.27, 0.15), Vector3(0.16, 0.03, 0.04), Color(0.15, 0.15, 0.15))
	EK.pin(sk, Vector3(0, 0, -L2), 0.1, 0.07, YELLOW.darkened(0.2))           # the bucket pin's boss (the bucket's ears outside it)
	EK.pin(sk, LINK_P7, 0.11, 0.05, YELLOW.darkened(0.2))                      # the idler links' pin, through the stick
	_stick.add_child(sk.instance("Stick"))
	_boom.add_child(_stick)
	_bucket = Node3D.new()
	_bucket.position = Vector3(0, 0, -L2)
	# A backhoe bucket. Bucket frame: origin at the pin on the stick end,
	# -Z carries on down the stick, -Y faces back toward the machine. The
	# curved shell is on the far (+Y) side and the bottom; the mouth and the
	# teeth face the cab, so it digs by pulling in and curls up toward you.
	var uk := MeshKit.new()
	var bw := 0.62
	# shell profile (y, z) from the pin round the back to the cutting edge
	var shell := [Vector2(0.06, 0.04), Vector2(0.24, -0.12), Vector2(0.31, -0.36),
		Vector2(0.24, -0.58), Vector2(0.04, -0.70), Vector2(-0.22, -0.70), Vector2(-0.34, -0.64)]
	for k in range(shell.size() - 1):
		var a: Vector2 = shell[k]
		var b: Vector2 = shell[k + 1]
		var n := Vector3(0, b.y - a.y, -(b.x - a.x)).normalized()     # outward
		if n.dot(Vector3(0, (a.x + b.x) * 0.5 + 0.02, (a.y + b.y) * 0.5 + 0.33)) < 0.0:
			n = -n
		uk.quad(Vector3(-bw * 0.5, a.x, a.y), Vector3(bw * 0.5, a.x, a.y), Vector3(bw * 0.5, b.x, b.y), Vector3(-bw * 0.5, b.x, b.y), YELLOW.darkened(0.05), n)
		uk.quad(Vector3(bw * 0.5, a.x, a.y), Vector3(-bw * 0.5, a.x, a.y), Vector3(-bw * 0.5, b.x, b.y), Vector3(bw * 0.5, b.x, b.y), Color(0.34, 0.32, 0.29), -n)
	# side plates: the profile filled in, both sides
	for sx in [-bw * 0.5, bw * 0.5]:
		var c := Vector3(sx, -0.02, -0.33)
		for k2 in range(shell.size() - 1):
			var a3: Vector2 = shell[k2]
			var b3: Vector2 = shell[k2 + 1]
			uk.tri(c, Vector3(sx, a3.x, a3.y), Vector3(sx, b3.x, b3.y), YELLOW.darkened(0.18), Vector3(signf(sx), 0, 0))
			uk.tri(c, Vector3(sx, b3.x, b3.y), Vector3(sx, a3.x, a3.y), Color(0.30, 0.29, 0.27), Vector3(-signf(sx), 0, 0))
		uk.tri(c, Vector3(sx, shell.back().x, shell.back().y), Vector3(sx, shell[0].x, shell[0].y), YELLOW.darkened(0.18), Vector3(signf(sx), 0, 0))
	# pin bosses and the link ears
	# the hinge ears either side of the stick's tip, welded down onto the shell
	EK.lug(uk, Vector3.ZERO, 0.115, 0.035, 0.09, Vector3(0, 1, -0.3), 0.1, YELLOW.darkened(0.12), 0.045)
	# the power link's ears, behind the hinge
	EK.lug(uk, LINK_P10, 0.085, 0.03, 0.07, Vector3(0, -1, -0.2), 0.08, YELLOW.darkened(0.12), 0.035)
	# hardened lip and five teeth pointing at the cab
	uk.box_at(Vector3(0, -0.30, -0.66), Vector3(bw, 0.06, 0.07), STEEL.darkened(0.3))
	for i in range(5):
		var tx := -0.24 + 0.12 * float(i)
		uk.box(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(tx, -0.40, -0.62)), Vector3(0.05, 0.16, 0.05), STEEL)
	for scx in [-bw * 0.5 - 0.012, bw * 0.5 + 0.012]:
		uk.box(Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3(scx, -0.28, -0.62)), Vector3(0.025, 0.16, 0.14), STEEL.darkened(0.35))    # side cutters
	for i2 in range(5):
		var tx2 := -0.24 + 0.12 * float(i2)
		uk.box(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(tx2, -0.33, -0.64)), Vector3(0.07, 0.07, 0.08), STEEL.darkened(0.2))      # adapters
	for wy in [0.12, -0.05]:
		uk.box_at(Vector3(0, 0.3, -0.36 + wy), Vector3(bw - 0.06, 0.02, 0.04), STEEL.darkened(0.25))                                    # wear strips on the back
	_bucket.add_child(uk.instance("Bucket"))
	_dirt = MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.52, 0.32, 0.4)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.5, 0.38, 0.24)
	dm.material = dmat
	_dirt.mesh = dm
	_dirt.position = Vector3(0, 0.04, -0.36)
	_dirt.visible = false
	_bucket.add_child(_dirt)
	_stick.add_child(_bucket)
	_build_links()
	_detail(cx)
	EK.dust_all(self, 0.45, 0.9)
	seat = EK.air_seat(_cab, Vector3(-0.48, 0.26, -0.24), 0.0)
	engine = EK.engine(_cab, Vector3(0.35, 1.20, 0.55), null, 0.04)
	seat.scale = Vector3.ONE / SCALE * 1.0
	_rams()
	EK.add_collision(self)
	TowPoints.build(_tracks, WINCH_POINTS, YELLOW.darkened(0.25), 1.0 / SCALE * 1.2)


## The working rams (Dave): pinned part to part, they stroke as the arm moves.
func _rams() -> void:
	var Ram = ResourceLoader.load("res://scripts/hyd_ram.gd", "", ResourceLoader.CACHE_MODE_REPLACE)
	var col := YELLOW.darkened(0.15)
	var knee := Vector3(0, 0.42, -L1 * 0.48)
	for sx in [-BOOM_RAM_X, BOOM_RAM_X]:
		var r = Ram.new()
		_cab.add_child(r)
		r.setup(_cab, PIVOT + Vector3(sx, BOOM_RAM_BASE.y, BOOM_RAM_BASE.z), _boom, BOOM_RAM_ROD + Vector3(sx, 0, 0), 0.07, col)
	var r2 = Ram.new()
	_cab.add_child(r2)
	r2.setup(_boom, knee + STICK_RAM_BASE, _stick, STICK_RAM_ROD, 0.065, col)
	# the bucket ram: its rod eye on the pin the idler and power links share
	var r3 = Ram.new()
	_cab.add_child(r3)
	r3.setup(_stick, BKT_RAM_BASE, _p9, Vector3.ZERO, 0.055, col)
	# the hoses (Dave: simulate the hydraulic lines): from the valve block at the
	# boom foot to each ram, across the boom foot and the stick pin; they hang,
	# swing and follow as the arm works (hyd_hose.gd)
	var rams := _cab.get_children().filter(func(n): return n.has_method("plumb"))
	if rams.size() >= 4:
		# boom rams: from the valve bank on the deck, down the boom foot, to each ram
		rams[0].plumb(self, _cab, PIVOT + Vector3(-0.36, -0.42, 0.42), 0.016, [PIVOT + Vector3(-0.36, -0.42, 0.05), PIVOT + Vector3(-BOOM_RAM_X - 0.1, -0.36, -0.12)])
		rams[1].plumb(self, _cab, PIVOT + Vector3(0.36, -0.42, 0.42), 0.016, [PIVOT + Vector3(0.36, -0.42, 0.05), PIVOT + Vector3(BOOM_RAM_X + 0.1, -0.36, -0.12)])
		# stick ram: off the ends of the boom's hard lines at the knee
		rams[2].plumb(self, _boom, knee + Vector3(0.06, 0.24, 0.0), 0.014, [knee + Vector3(0.06, 0.27, 0.25)])
		# bucket ram: off the stick's hard lines just past the stick pin
		rams[3].plumb(self, _stick, Vector3(0.05, 0.3, 0.25), 0.013, [Vector3(0.07, 0.34, 0.15)])
	var Hose = ResourceLoader.load("res://scripts/hyd_hose.gd", "", ResourceLoader.CACHE_MODE_REPLACE)
	for hx in [-0.06, 0.06]:
		var h = Hose.new()
		add_child(h)
		h.setup(_cab, PIVOT + Vector3(hx, 0.2, 0.25), _boom, Vector3(hx, 0.24, -0.15), 0.018, 1.3)     # over the boom foot
		var h2 = Hose.new()
		add_child(h2)
		h2.setup(_boom, Vector3(hx, 0.16, -L1 + 0.15), _stick, Vector3(hx, 0.25, 0.05), 0.016, 1.35)    # round the stick pin


## The drive and the idler (Dave, from the photos of real undercarriages):
## at the back the sprocket - a ring of rounded teeth (16 here, to match this chain's pitch) that sit up between
## the chain's link rails and bite on the bushings - bolted to the final
## drive's drum, which is bolted to the track frame on the inboard side; at the
## front the idler - two treads the link rails roll on and a centre flange
## running between them - its axle in a yoke that slides in the frame's slot,
## pushed forward by the grease cylinder and the recoil spring inside the
## frame. Both turn with the chain.
func _track_wheels(zc: float) -> void:
	var yc := 0.3225                                  # the loop's centre height (track_loop: (0.6 + 0.045) / 2)
	for loop in [_track_l, _track_r]:
		var sx: float = -0.69 if loop == _track_l else 0.69
		var sgn := signf(sx)
		# --- the sprocket
		var sp := Node3D.new()
		sp.name = "Sprocket"
		sp.position = Vector3(sx, yc, zc)
		_tracks.add_child(sp)
		var k := MeshKit.new()
		var n := 16                                    # the chain's pitch round this loop: 16 links to a turn, so each tooth meets a bushing
		var pts: Array = []
		for i in range(n * 8):
			var th := TAU * float(i) / float(n * 8)
			var c := cos(th * float(n))
			var r := 0.175 + 0.06 * pow(clampf((c + 0.15) / 1.15, 0.0, 1.0), 0.7)    # rounded teeth on the root circle
			pts.append(Vector2(sin(th) * r, cos(th) * r))
		for sd in [-1.0, 1.0]:
			var xx: float = float(sd) * 0.03
			for i2 in range(pts.size()):
				var a: Vector2 = pts[i2]
				var b: Vector2 = pts[(i2 + 1) % pts.size()]
				k.tri(Vector3(xx, 0, 0), Vector3(xx, a.x, a.y), Vector3(xx, b.x, b.y), STEEL.darkened(0.45), Vector3(float(sd), 0, 0))
		for i3 in range(pts.size()):
			var a3: Vector2 = pts[i3]
			var b3: Vector2 = pts[(i3 + 1) % pts.size()]
			k.quad(Vector3(-0.03, a3.x, a3.y), Vector3(-0.03, b3.x, b3.y), Vector3(0.03, b3.x, b3.y), Vector3(0.03, a3.x, a3.y), STEEL.darkened(0.4), Vector3(0, a3.x + b3.x, a3.y + b3.y))
		# the bolt ring holding it to the drum's flange
		for bi in range(12):
			var ba := TAU * float(bi) / 12.0
			k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5) if sgn < 0.0 else Basis(Vector3.FORWARD, PI * 0.5), Vector3(-sgn * 0.03, sin(ba) * 0.13, cos(ba) * 0.13)), 0.014, 0.014, 0.012, 6, STEEL.darkened(0.2))
		sp.add_child(k.instance("SprocketRing"))
		loop.add_wheel(sp, 0.2785)          # turns one tooth per link
		# --- the final drive drum: fixed to the frame, inboard, its bolt circle on the face
		var fk := MeshKit.new()
		var inb := -sgn                                # toward the middle of the machine
		var drum_x := sx + inb * 0.03
		fk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5) if inb < 0.0 else Basis(Vector3.FORWARD, PI * 0.5), Vector3(drum_x, yc, zc)), 0.17, 0.17, 0.2, 18, DARK)
		var face := drum_x + inb * 0.2
		fk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5) if inb < 0.0 else Basis(Vector3.FORWARD, PI * 0.5), Vector3(face, yc, zc)), 0.13, 0.11, 0.03, 18, DARK.lightened(0.05))
		for bj in range(10):
			var bb := TAU * float(bj) / 10.0
			fk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5) if inb < 0.0 else Basis(Vector3.FORWARD, PI * 0.5), Vector3(face, yc + sin(bb) * 0.145, zc + cos(bb) * 0.145)), 0.012, 0.012, 0.015, 6, STEEL.darkened(0.2))
		# the travel motor on the drum's face, and its hard lines up into the frame
		fk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5) if inb < 0.0 else Basis(Vector3.FORWARD, PI * 0.5), Vector3(face + inb * 0.03, yc + 0.02, zc - 0.02)), 0.07, 0.07, 0.08, 12, DARK.lightened(0.08))
		# --- the idler, in its yoke
		var idl := Node3D.new()
		idl.name = "Idler"
		idl.position = Vector3(sx, yc, -zc)
		_tracks.add_child(idl)
		var ik := MeshKit.new()
		for tx in [-0.115, 0.115]:                     # the treads the link rails roll on
			ik.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(tx + 0.04, 0, 0)), 0.16, 0.16, 0.08, 20, STEEL.darkened(0.3))
		ik.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.04, 0, 0)), 0.205, 0.205, 0.08, 20, STEEL.darkened(0.35))   # centre flange between the rails
		for sp2 in range(6):                           # lightening holes' bosses on the web, so it reads as turning
			var sa := TAU * float(sp2) / 6.0
			for sd2 in [-1.0, 1.0]:
				ik.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5) if float(sd2) < 0.0 else Basis(Vector3.FORWARD, PI * 0.5), Vector3(float(sd2) * 0.155, sin(sa) * 0.09, cos(sa) * 0.09)), 0.025, 0.025, 0.006, 8, DARK)
		idl.add_child(ik.instance("IdlerWheel"))
		loop.add_wheel(idl, 0.2785)
		# the yoke: bearing blocks either side on the axle, sliding in the frame's
		# slot, and its push rod back to the grease cylinder in the frame
		var yk := MeshKit.new()
		yk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.2, yc, -zc)), 0.04, 0.04, 0.4, 10, STEEL)        # the axle
		for yx in [-0.17, 0.17]:
			yk.box_at(Vector3(sx + yx, yc, -zc + 0.05), Vector3(0.05, 0.2, 0.2), YELLOW.darkened(0.32))
			yk.box_at(Vector3(sx + yx, yc, -zc + 0.25), Vector3(0.05, 0.16, 0.3), YELLOW.darkened(0.32))      # the yoke's arms back into the slot
		yk.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx, yc, -zc + 0.25)), 0.05, 0.05, 0.3, 10, STEEL.darkened(0.1))   # push rod into the frame
		_tracks.add_child(yk.instance("IdlerYoke"))
		_tracks.add_child(fk.instance("FinalDrive"))


var _p9: Node3D                    # the pin the bucket ram, idler links and power link share
var _idler: Node3D
var _power: Node3D


## The bucket linkage (Dave, from the real one): two idler links from a pin
## through the stick, the power link (an H) from the bucket's ears, and the
## bucket ram's rod eye on the pin where they meet. The ram pushes that pin;
## the links swing the bucket on its hinge.
func _build_links() -> void:
	_p9 = Node3D.new()
	_p9.name = "LinkPin"
	_stick.add_child(_p9)
	var pk := MeshKit.new()
	pk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.155, 0, 0)), 0.03, 0.03, 0.31, 10, STEEL, true)
	for sx in [-1.0, 1.0]:
		pk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5) if sx < 0.0 else Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * 0.155, 0, 0)), 0.042, 0.042, 0.012, 10, STEEL.darkened(0.2), true)
	_p9.add_child(pk.instance("Pin"))
	# idler links: a plate each side of the stick, rounded round both pins
	_idler = Node3D.new()
	_idler.name = "IdlerLinks"
	_idler.position = LINK_P7
	_stick.add_child(_idler)
	var ik := MeshKit.new()
	for sx2 in [-1.0, 1.0]:
		_link_plate(ik, sx2 * 0.13, LINK_IDLER, 0.06, 0.025, YELLOW.darkened(0.2))
	_idler.add_child(ik.instance("Idler"))
	# the power link: two plates joined by a cross tube, between the bucket ears
	_power = Node3D.new()
	_power.name = "PowerLink"
	_stick.add_child(_power)
	var wk := MeshKit.new()
	for sx3 in [-1.0, 1.0]:
		_link_plate(wk, sx3 * 0.07, LINK_POWER, 0.065, 0.025, YELLOW.darkened(0.2))
	wk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.07, 0, -LINK_POWER * 0.5)), 0.035, 0.035, 0.14, 10, YELLOW.darkened(0.25), true)
	_power.add_child(wk.instance("Power"))


## One link plate along -Z from 0 to -L, at x, rounded ends round each pin.
func _link_plate(k: MeshKit, x: float, L: float, r: float, t: float, col: Color) -> void:
	var outline: Array = []
	for i in range(9):
		var a := PI * float(i) / 8.0
		outline.append(Vector2(r * cos(a), -L - r * sin(a)))    # far end
	for i2 in range(9):
		var a2 := PI + PI * float(i2) / 8.0
		outline.append(Vector2(r * cos(a2), -r * sin(a2)))      # near end
	var n := outline.size()
	for i3 in range(n):
		var a3: Vector2 = outline[i3]
		var b3: Vector2 = outline[(i3 + 1) % n]
		for sd in [-1.0, 1.0]:
			var xx: float = x + float(sd) * t * 0.5
			k.tri(Vector3(xx, 0, -L * 0.5), Vector3(xx, a3.x, a3.y), Vector3(xx, b3.x, b3.y), col, Vector3(float(sd), 0, 0))
		k.quad(Vector3(x - t * 0.5, a3.x, a3.y), Vector3(x - t * 0.5, b3.x, b3.y), Vector3(x + t * 0.5, b3.x, b3.y), Vector3(x + t * 0.5, a3.x, a3.y), col, Vector3(0, (a3.x + b3.x) * 0.5, (a3.y + b3.y) * 0.5 + L * 0.5))


## Lay the linkage for the bucket's angle: the shared pin where a circle round
## the idler pin meets a circle round the power link's bucket pin.
func _link_pose() -> void:
	if _p9 == null:
		return
	var p10 := _bucket.transform * LINK_P10
	var c1 := Vector2(LINK_P7.y, LINK_P7.z)
	var c2 := Vector2(p10.y, p10.z)
	var d := c1.distance_to(c2)
	var r1 := LINK_IDLER
	var r2 := LINK_POWER
	d = clampf(d, absf(r1 - r2) + 0.001, r1 + r2 - 0.001)
	var a := (r1 * r1 - r2 * r2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, r1 * r1 - a * a))
	var u := (c2 - c1).normalized()
	var m := c1 + u * a
	var perp := Vector2(u.y, -u.x)
	var q := m + perp * h
	var q2 := m - perp * h
	# the branch the real linkage runs on: the pin out on the far side of the line
	var cr := (c2.x - c1.x) * (q.y - c1.y) - (c2.y - c1.y) * (q.x - c1.x)
	if cr < 0.0:
		q = q2
	_p9.position = Vector3(0, q.x, q.y)
	_idler.rotation = Vector3(atan2(q.x - c1.x, -(q.y - c1.y)), 0, 0)
	_power.position = _p9.position
	_power.rotation = Vector3(atan2(c2.x - q.x, -(c2.y - q.y)), 0, 0)


## The truck treatment (DESIGN_NOTES 215), from early-80s excavators: the
## cab's door, drip rail, wiper, lamps like the truck's, the grille and
## handrails, steps, mirror, beacon, bolts, hazard stripes and decals.
func _detail(cx: float) -> void:
	var p := MeshKit.new()
	var d := MeshKit.new()
	var m := MeshKit.new()
	for sz in [-1.0, 1.0]:
		p.box_at(Vector3(cx, 1.41, -0.25 + sz * 0.6), Vector3(0.74, 0.04, 0.03), YELLOW.darkened(0.2))
	d.box_at(Vector3(cx - 0.335, 0.82, -0.18), Vector3(0.02, 1.1, 0.03), DARK)             # the door's front edge
	EK.rod(d, Vector3(cx + 0.2, 1.33, -0.835), Vector3(cx - 0.05, 0.62, -0.835), 0.006, DARK)  # wiper
	EK.rod(d, Vector3(cx - 0.02, 0.68, -0.84), Vector3(cx - 0.17, 1.15, -0.84), 0.008, Color(0.03, 0.03, 0.03))
	# lamps: two on the cab roof front, one on the tool box, one rear on the hood
	for lx in [cx - 0.2, cx + 0.2]:
		EK.lamp(d, m, _cab, Vector3(lx, 1.53, -0.83), Vector3(0, -0.15, -1), 0.12, 0.09, Color(1, 0.97, 0.85))
		d.box_at(Vector3(lx, 1.49, -0.79), Vector3(0.04, 0.06, 0.08), DARK)
	EK.lamp(d, m, _cab, Vector3(0.6, 0.66, -0.84), Vector3(0, -0.1, -1), 0.12, 0.12, Color(1, 0.97, 0.85), true)
	EK.lamp(d, m, _cab, Vector3(0.45, 0.8, 0.86), Vector3(0, -0.2, 1), 0.12, 0.09, Color(1, 0.97, 0.85))     # on the hood's back face
	EK.beacon(d, _cab, Vector3(cx + 0.2, 1.48, 0.1))
	EK.mirror(d, Vector3(0.82, 0.9, -0.82), Vector3(0.9, 1.15, -0.9))
	# engine hood: a radiator grille on the left end, handrails, the exhaust cap
	EK.grille(d, d, Vector3(-0.84, 0.55, 0.6), Vector3(-1, 0, 0), 0.4, 0.5, 8, false)
	EK.rail(p, [Vector3(0.82, 0.62, -0.75), Vector3(0.82, 0.95, -0.75), Vector3(0.82, 0.95, 0.3), Vector3(0.82, 0.62, 0.3)], YELLOW.darkened(0.2), 0.014)
	EK.rail(p, [Vector3(-0.2, 0.92, 0.4), Vector3(-0.2, 1.05, 0.4), Vector3(0.7, 1.05, 0.4), Vector3(0.7, 0.92, 0.4)], YELLOW.darkened(0.2), 0.012)
	EK.grate_step(m, Vector3(0.62, 0.1, -0.86), 0.36, 0.2)
	# bolts round the counterweight, hazard stripes across its back, the decals
	EK.hazard(p, Vector3(-0.6, 0.12, 1.235), Vector3(0.6, 0.12, 1.235), Vector3(0.6, 0.24, 1.235), Vector3(-0.6, 0.24, 1.235), Vector3(0, 0, 1), 12)
	EK.bolts(m, Vector3(-0.8, 0.66, 0.55), Vector3(0.8, 0.66, 0.55), 10, Vector3(0, 1, 0), 0.012)
	for sx in [-1.0, 1.0]:
		EK.decal(_cab, "E-225", Vector3(sx * 0.86, 0.5, 0.95), Vector3(sx, 0, 0), 0.0025, Color(0.08, 0.08, 0.08))
	EK.decal(_cab, "DANGER\nSTAY CLEAR\nOF SWING", Vector3(0.0, 0.42, 1.24), Vector3(0, 0, 1), 0.0007, Color(1, 1, 1), Color(0.75, 0.08, 0.05), d, 0.18, 0.11)
	# the engine hood's lift-up doors: seams, hinges, latches; the fuel cap; the
	# swing ring's bolts showing under the deck; lifting eyes on the counterweight
	for dx in [-0.42, 0.42]:
		d.box_at(Vector3(dx, 0.9, 0.6), Vector3(0.012, 0.012, 0.46), DARK)
	d.box_at(Vector3(0, 0.9, 0.36), Vector3(1.5, 0.012, 0.012), DARK)
	m.box_at(Vector3(0, 0.905, 0.84), Vector3(1.3, 0.02, 0.03), EK.STEEL)
	for lx in [-0.6, 0.0, 0.6]:
		m.box_at(Vector3(lx, 0.88, 0.37), Vector3(0.1, 0.03, 0.03), EK.STEEL)
	m.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.68, 0.83, 0.15)), 0.045, 0.045, 0.04, 12, EK.STEEL, true)
	for bi in range(16):
		var ba := TAU * float(bi) / 16.0
		m.cylinder(Transform3D(Basis.IDENTITY, Vector3(cos(ba) * 0.46, -0.02, sin(ba) * 0.46)), 0.015, 0.015, 0.02, 6, EK.STEEL, true)
	for ex in [-0.5, 0.5]:
		m.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(ex, 0.72, 1.0)), 0.05, 0.05, 0.03, 10, EK.STEEL, false)
	# cab: the roof hatch, a visor, the door handle and its lock
	p.box_at(Vector3(cx, 1.49, -0.3), Vector3(0.4, 0.03, 0.45), YELLOW.darkened(0.1))
	p.box(Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(cx, 1.44, -0.92)), Vector3(0.68, 0.02, 0.18), YELLOW.darkened(0.2))
	m.box_at(Vector3(cx - 0.345, 0.85, 0.15), Vector3(0.03, 0.03, 0.12), EK.STEEL)
	_cab.add_child(p.instance("Detail"))
	_cab.add_child(d.instance("DetailDark"))
	var mm := m.instance("DetailMetal")
	mm.material_override = EK.metal_mat()
	_cab.add_child(mm)
	# the crawler: bolt heads along the track guards
	var tm := MeshKit.new()
	for sx2 in [-0.69, 0.69]:
		EK.bolts(tm, Vector3(sx2 + signf(sx2) * 0.145, 0.2, -0.85), Vector3(sx2 + signf(sx2) * 0.145, 0.2, 0.85), 9, Vector3(signf(sx2), 0, 0), 0.014)
	for sx3 in [-0.69, 0.69]:
		var sg := signf(sx3)
		tm.cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5 * sg), Vector3(sx3 + sg * 0.27, 0.3, 1.26)), 0.17, 0.14, 0.08, 16, DARK, true)
		for bb in range(10):
			var ba2 := TAU * float(bb) / 10.0
			tm.cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5 * sg), Vector3(sx3 + sg * 0.35, 0.3 + cos(ba2) * 0.12, 1.26 + sin(ba2) * 0.12)), 0.012, 0.012, 0.015, 6, EK.STEEL, true)
		tm.box_at(Vector3(sx3, 0.34, -0.95), Vector3(0.16, 0.14, 0.32), DARK)
	var tmi := tm.instance("TrackMetal")
	tmi.material_override = EK.metal_mat()
	_tracks.add_child(tmi)


func park(xf: Transform3D) -> void:
	home = xf
	var f := -xf.basis.z
	yaw = atan2(-f.x, -f.z)
	swing = 0.0
	global_position = xf.origin
	_settle()
	body = TrackedBody.new()
	body.mass = 14000.0
	body.shoe = 0.6 * SCALE / 1.45 * 1.0
	body.length = 2.5 * SCALE
	body.width = 1.38 * SCALE
	body.height = 2.5 * SCALE
	body.com = Vector3(0, 0.9, 0.15) * SCALE
	body.top_speed = 1.5
	body.power = 75000.0
	body.ground_y = func(x: float, z: float) -> float: return terrain.wheel_ground(x, z) if terrain.has_method("wheel_ground") else terrain.height_at(x, z)
	body.blocked = func(p: Vector3) -> bool: return terrain.blocked_by_building(p, 0.9 * SCALE, self)
	body.setup()
	body.place(global_transform)
	body.settle()
	global_transform = body.transform()
	aim = global_transform * Vector3(0, 0, -3.5 * SCALE)
	aim.y = terrain.height_at(aim.x, aim.z)
	_pose_arm(aim + Vector3(0, 0.8, 0), 0.2)


func eye_xf() -> Transform3D:
	return _cab.global_transform * Transform3D(Basis.IDENTITY, Vector3(-0.48, 1.22, -0.3))


func cab_yaw() -> float:
	return yaw + swing


func _settle() -> void:
	var p := global_position
	p.y = terrain.height_at(p.x, p.z)
	var n: Vector3 = terrain.normal_at(p.x, p.z)
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var right := fwd.cross(n).normalized()
	global_transform = Transform3D(Basis(right, n, -fwd), p)


## Where you're looking on the ground, within the arm's reach, or the old aim.
func aim_from(eye: Vector3, dir: Vector3) -> void:
	var hit := Vector3.INF
	var t := 0.5
	while t < 12.0:
		var q := eye + dir * t
		if q.y <= terrain.height_at(q.x, q.z):
			hit = q
			break
		t += 0.15
	if hit == Vector3.INF:
		hit = eye + dir * 6.0
	var base := global_position
	var flat := Vector2(hit.x - base.x, hit.z - base.z)
	var d := clampf(flat.length(), REACH_MIN, REACH_MAX)
	flat = flat.normalized() * d if flat.length() > 0.01 else Vector2(0, -d)
	aim = Vector3(base.x + flat.x, 0.0, base.z + flat.y)
	aim.y = terrain.height_at(aim.x, aim.z)


## Next control mode (Auto -> Boom -> Levers -> Auto).
func cycle_mode() -> int:
	mode = (mode + 1) % 3
	boom_off = 0.0
	state = ""
	return mode


## Boom mode, one frame: the triggers move the bucket up and down from where
## the auto arm would hold it. Pushed down into the ground (or onto a bank)
## it plants, and holding it down lifts the machine on it; drive with it
## planted and the arm drags her along: out of a hole, up a bank, off a bog.
func _boom_mode(delta: float, hover: Vector3) -> Vector3:
	var floor_y: float = terrain.height_at(aim.x, aim.z) - 0.35 * SCALE
	boom_off = clampf(boom_off + boom_in * 1.6 * delta, -6.0, 5.0)
	var want := hover + Vector3(0, boom_off, 0)
	if want.y < floor_y - 0.25:
		boom_off += (floor_y - 0.25) - want.y     # no wind-up below the ground
		want.y = floor_y - 0.25
	var held := want
	held.y = maxf(want.y, floor_y)
	_resist = 0.0
	if body != null and not kinematic and boom_in < -0.1 and want.y < floor_y + 0.05:
		var tp := teeth()
		var g := 9.81 * float(body.mass)
		var f := Vector3.UP * 0.75 * g * clampf(-boom_in, 0.0, 1.0)
		if absf(_move.y) > 0.3:
			var fw := -global_transform.basis.z
			fw.y = 0.0
			f += fw.normalized() * 0.45 * g * signf(_move.y)
		_push_f = f
		_push_pt = tp
		_resist = 1.0
	return held


func busy() -> bool:
	return state != ""


func dig_or_dump() -> String:
	if busy():
		return ""
	boom_off = 0.0
	if bucket_load.is_empty():
		state = "dig"
	else:
		state = "dump"
	_t = 0.0
	_did = false
	return ""


## Stuck (DESIGN_NOTES 150): drive and she won't go - in a hole, bogged, nosed
## into a bank - and after a second the bucket goes down ahead (or behind,
## reversing), bites in, and the arm levers the front up and drags her along
## while the tracks drive: how an operator walks a machine out.
var _stuck_t := 0.0
var _rescue := false
var _rescue_told := false


func drive(delta: float, move: Vector2) -> void:
	if body != null and not kinematic:
		var l := clampf(move.y + move.x * 0.75, -1.0, 1.0)
		var r := clampf(move.y - move.x * 0.75, -1.0, 1.0)
		var fwd0 := -global_transform.basis.z
		var sp := (body.vel as Vector3).dot(fwd0)
		if absf(move.y) > 0.5 and absf(sp) < 0.15 and state == "":
			_stuck_t += delta
		else:
			_stuck_t = maxf(_stuck_t - delta * 2.0, 0.0)
		_rescue = _stuck_t > 1.0 and absf(move.y) > 0.5 and mode == 0
		_move = move
		body.ext_force = Vector3.ZERO
		if _push_f != Vector3.ZERO:
			body.ext_point = _push_pt
			body.ext_force = _push_f
			body.sink = maxf(float(body.sink) - 0.05 * delta, 0.0)
			_push_f = Vector3.ZERO
		if _rescue:
			var dir := fwd0 * signf(move.y)
			dir.y = 0.0
			dir = dir.normalized()
			var plant := global_position + dir * 3.4 * SCALE
			plant.y = terrain.height_at(plant.x, plant.z) - 0.25
			aim = plant
			# swing the cab round to it and put the teeth in
			var to := plant - global_position
			swing = lerp_angle(swing, atan2(-to.x, -to.z) - yaw, clampf(delta * 1.5, 0.0, 1.0))
			_pose_arm(plant, 0.6)
			var tp := teeth()
			var g := 9.81 * float(body.mass)
			var bite := clampf((_stuck_t - 1.0) / 1.0, 0.0, 1.0)
			body.ext_point = tp
			body.ext_force = (Vector3.UP * 0.55 * g + dir * 0.45 * g) * bite
			body.sink = maxf(float(body.sink) - 0.05 * delta, 0.0)
			_resist = 1.0
			if not _rescue_told and on_message.is_valid():
				_rescue_told = true
				on_message.call("She's stuck: the bucket goes down %s, bites in, and the arm hauls her out while the tracks drive." % ("ahead" if move.y > 0.0 else "behind"))
		else:
			_rescue_told = _stuck_t > 0.5 and _rescue_told
		body.step(delta, l, r)
		global_transform = body.transform()
		yaw = body.yaw()
		if engine != null:
			engine.drive_strain = engine.travel_strain(maxf(absf(l), absf(r)), body.top_speed, body.vel.length())
		if _track_l != null:
			_track_l.advance(body.belt_l * delta / SCALE)
			_track_r.advance(body.belt_r * delta / SCALE)
		return
	var sp := move.y * 1.3
	yaw -= move.x * 0.6 * delta
	if _track_l != null:
		_track_l.advance((sp + move.x * 0.75 * 0.6) * delta / SCALE)
		_track_r.advance((sp - move.x * 0.75 * 0.6) * delta / SCALE)
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var p := global_position + fwd * sp * delta
	if terrain.blocked_by_building(p + fwd * (1.8 if sp >= 0.0 else -1.8) * SCALE + Vector3(0, 0.6, 0), 0.9 * SCALE, self):
		p = global_position
	global_position = p
	_settle()


## Swing the cab toward the aim and move the arm (every frame while driven).
func work(delta: float) -> String:
	var msg := ""
	var to := aim - global_position
	var want_swing := atan2(-to.x, -to.z) - yaw
	var diff := wrapf(want_swing - swing, -PI, PI)
	swing += clampf(diff, -1.3 * delta, 1.3 * delta)
	var hover := aim + Vector3(0, 0.9 * SCALE, 0)
	if mode == 1 and state == "":
		hover = _boom_mode(delta, hover)
	# Over a wash plant's hopper the bucket swings up clear of the grizzly.
	if hopper_at.is_valid():
		var hop: Vector3 = hopper_at.call(aim)
		if hop != Vector3.INF:
			hover = Vector3(aim.x, maxf(hover.y, hop.y + 1.1), aim.z)
	# The cab swings round first: dig and dump wait until it's facing the
	# spot (they used to fire half-way round, wherever the bucket was).
	var swung := absf(diff) < 0.06
	if state != "" and not swung and _t < 0.05:
		_pose_arm(hover, 0.25 if bucket_load.is_empty() else 1.0)
		_dirt.visible = not bucket_load.is_empty() and _curl > 0.5
		return ""
	match state:
		"":
			_pose_arm(hover, 0.25 if bucket_load.is_empty() else 1.0)
		"dig":
			_t += delta
			var down := aim + Vector3(0, -0.25, 0)
			if _t < 0.7:
				_pose_arm(hover.lerp(down, _t / 0.7), 0.0)
			elif _t < 1.3:
				if not _did:
					_did = true
					var got: Dictionary = on_dig.call(aim, BUCKET_M3) if on_dig.is_valid() else {}
					if float(got.get("over", 0.0)) + float(got.get("pay", 0.0)) > 0.01:
						bucket_load = got
					elif bool(got.get("bedrock", false)):
						msg = "The bucket scrapes on bedrock."
					else:
						msg = "Nothing to dig here."
				_pose_arm(down, (_t - 0.7) / 0.6)
			elif _t < 2.0:
				_pose_arm(down.lerp(hover, (_t - 1.3) / 0.7), 1.0)
			else:
				state = ""
		"dump":
			_t += delta
			if _t < 0.4:
				_pose_arm(hover, 1.0 - _t / 0.4)
			else:
				if not _did:
					_did = true
					# It pours where the bucket really is.
					var tp := teeth()
					var want_hop: Vector3 = hopper_at.call(aim) if hopper_at.is_valid() else Vector3.INF
					if want_hop != Vector3.INF:
						var got_hop: Vector3 = hopper_at.call(tp)
						if got_hop == Vector3.INF or tp.y < want_hop.y:
							msg = "The bucket can't get over the hopper from here: drive closer."
							state = ""
							return msg
					var at := Vector3(tp.x, terrain.height_at(tp.x, tp.z), tp.z)
					msg = on_dump.call(at, bucket_load) if on_dump.is_valid() else ""
					bucket_load = {}
				_pose_arm(hover, 0.0)
				if _t > 1.0:
					state = ""
	_dirt.visible = not bucket_load.is_empty() and _curl > 0.5
	return msg


## A box beam from a to b (lying along it, in the YZ plane), `w` wide,
## tapering from height h0 to h1.
static func _box_beam(kit: RefCounted, a: Vector3, b: Vector3, w: float, h0: float, h1: float, col: Color) -> void:
	var d := b - a
	var up := Vector3(0, -d.z, d.y).normalized()
	if up.y < 0.0:
		up = -up
	var rings: Array = []
	for e in [[a, h0], [b, h1]]:
		var p: Vector3 = e[0]
		var h: float = e[1]
		var ring := PackedVector3Array()
		ring.append(p + up * h * 0.5 + Vector3(-w * 0.5, 0, 0))
		ring.append(p + up * h * 0.5 + Vector3(w * 0.5, 0, 0))
		ring.append(p - up * h * 0.5 + Vector3(w * 0.5, 0, 0))
		ring.append(p - up * h * 0.5 + Vector3(-w * 0.5, 0, 0))
		rings.append(ring)
	kit.loft(rings, col, true, true)


static func _bar(kit: RefCounted, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	kit.cylinder(Transform3D(Basis(x, y, x.cross(y)), a), r, r, d.length(), 6, col, true)


## Two-link arm: put the bucket's teeth at `tip` (world), bucket curled by `curl`.
func _pose_arm(tip: Vector3, curl: float) -> void:
	_cab.rotation = Vector3(0, swing, 0)
	var local: Vector3 = _cab.global_transform.affine_inverse() * tip
	var p: Vector3 = PIVOT
	var fwd := -(local.z - p.z)          # forward of the boom foot
	var up := local.y - p.y + 0.35        # aim the stick end a little above the teeth
	var d := clampf(sqrt(fwd * fwd + up * up), 0.6, L1 + L2 - 0.05)
	var a := atan2(up, fwd)
	var cos_b := clampf((L1 * L1 + d * d - L2 * L2) / (2.0 * L1 * d), -1.0, 1.0)
	var boom_a_ik := a + acos(cos_b)      # boom raised above the line to the tip
	var cos_k := clampf((L1 * L1 + L2 * L2 - d * d) / (2.0 * L1 * L2), -1.0, 1.0)
	var knee_ik := PI - acos(cos_k)       # how far the stick folds down from the boom line
	boom_a = clampf(boom_a_ik, BOOM_MIN, BOOM_MAX)
	knee = clampf(knee_ik, KNEE_MIN, KNEE_MAX)
	bucket_a = clampf(-0.6 + 1.6 * curl, BKT_MIN, BKT_MAX)
	_apply_pose()


var _demo_t := 0.0
var hyd: RefCounted                  # hyd_system.gd: pump, valve, rams, pressures
var _hrams: Array = []               # [sim ram, joint name, the visible ram node]
var _plabels: Array = []
var _pump_label: Label3D


## The hydraulic system (Dave): a 180 L/min pump at 2000 rpm, 330 bar relief;
## the boom (two 120 mm rams, as one), the stick (125 mm), the bucket (110 mm).
func _hyd_setup() -> void:
	hyd = ResourceLoader.load("res://scripts/hyd_system.gd", "", ResourceLoader.CACHE_MODE_REPLACE).new()
	var vis := _cab.get_children().filter(func(n): return n.has_method("plumb"))
	_hrams = [[hyd.add_ram("BOOM", 170.0, 120.0), "boom", vis[0] if vis.size() > 0 else null],
		[hyd.add_ram("STICK", 125.0, 90.0), "stick", vis[2] if vis.size() > 2 else null],
		[hyd.add_ram("BUCKET", 110.0, 75.0), "bucket", vis[3] if vis.size() > 3 else null]]
	for hi in range(_hrams.size()):
		var hv = _hrams[hi][2]
		if hv != null:
			hv.sim_ram = _hrams[hi][0]
	if vis.size() > 1:
		vis[1].sim_ram = _hrams[0][0]          # the second boom ram
	for h in _hrams:
		var l := Label3D.new()
		l.font_size = 40
		l.pixel_size = 0.004
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.outline_size = 8
		if h[2] != null:
			(h[2] as Node3D).add_child(l)
		else:
			add_child(l)
		_plabels.append(l)
	_pump_label = Label3D.new()
	_pump_label.font_size = 40
	_pump_label.pixel_size = 0.004
	_pump_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_pump_label.no_depth_test = true
	_pump_label.outline_size = 8
	_pump_label.position = Vector3(0, 2.6, 0.8) / SCALE
	_cab.add_child(_pump_label)


## How far the arm is into something: the teeth into the ground, the bucket or
## the stick into the cab, the tracks or the deck (0 when it's clear).
func _clip_depth() -> float:
	var inv := global_transform.affine_inverse()
	var t := inv * teeth()
	var depth := maxf(0.0, -0.25 - t.y)
	var cab_box := AABB(Vector3(-1.4, 0.0, -1.6), Vector3(2.8, 3.2, 3.6))       # the upper and the crawler, roughly
	for p in [_bucket.global_transform * Vector3(0, 0, -0.35), _bucket.global_transform * TEETH, _stick.global_transform * Vector3(0, 0, -L2)]:
		var q: Vector3 = inv * (p as Vector3)
		if cab_box.has_point(q):
			depth += minf(q.z - cab_box.position.z, cab_box.end.y - q.y)
	return depth


func damage_line() -> String:
	if hyd == null:
		_hyd_setup()
	return EK.damage_line(self)


func repair_lines() -> String:
	return EK.repair_lines(self)


func _joint_get(j: String) -> float:
	return boom_a if j == "boom" else (knee if j == "stick" else bucket_a)


func _joint_set(j: String, v: float) -> void:
	if j == "boom":
		boom_a = v
	elif j == "stick":
		knee = v
	else:
		bucket_a = v


## The arm's weight as height: boom 1.6 t, stick 0.9 t, bucket 0.7 t and what's in it.
func _potential() -> float:
	var g := 9.81
	var dirt := fill() * BUCKET_M3 * 1800.0
	return g * (1600.0 * (_boom.global_transform * Vector3(0, 0.2, -L1 * 0.5)).y
		+ 900.0 * (_stick.global_transform * Vector3(0, 0.1, -L2 * 0.5)).y
		+ (700.0 + dirt) * (_bucket.global_transform * Vector3(0, 0, -0.35)).y)


func _ram_len(vis: Node3D) -> float:
	var e: Array = vis._ends()
	return (e[0] as Vector3).distance_to(e[1] as Vector3)


## One step of the sim: the spools in, the arm moves as the oil lets it.
func _hyd_step(dt: float, spools: Array) -> void:
	var lims := {"boom": [BOOM_MIN, BOOM_MAX], "stick": [KNEE_MIN, KNEE_MAX], "bucket": [BKT_MIN, BKT_MAX]}
	var rates := []
	for i in range(_hrams.size()):
		var r = _hrams[i][0]
		var j: String = _hrams[i][1]
		var vis: Node3D = _hrams[i][2]
		r.spool = float(spools[i])
		if vis == null:
			rates.append(0.0)
			continue
		var v0 := _joint_get(j)
		var eps := 0.01
		var L0 := _ram_len(vis)
		var U0 := _potential()
		_joint_set(j, v0 + eps)
		_apply_pose()
		var L1_ := _ram_len(vis)
		var U1 := _potential()
		_joint_set(j, v0)
		_apply_pose()
		var dL: float = (L1_ - L0) / eps
		if absf(dL) < 0.001:
			dL = 0.001 * signf(dL + 0.0000001)
		var force: float = ((U1 - U0) / eps) / dL       # + resists extending
		# at the end of its stroke the ram can't go further: it's up against the stop
		var lim: Array = lims[j]
		var going_up: bool = r.spool * signf(dL) > 0.0
		if (going_up and v0 >= float(lim[1]) - 0.005) or (not going_up and v0 <= float(lim[0]) + 0.005):
			force = 1.0e7 * signf(r.spool)
		r.force = force
		rates.append(dL)
	hyd.step(dt)
	for i2 in range(_hrams.size()):
		var r2 = _hrams[i2][0]
		var j2: String = _hrams[i2][1]
		if absf(float(rates[i2])) > 0.0:
			var lim2: Array = lims[j2]
			var old := _joint_get(j2)
			var before := _clip_depth()
			_joint_set(j2, clampf(old + r2.speed / float(rates[i2]) * dt, float(lim2[0]), float(lim2[1])))
			_apply_pose()
			if _clip_depth() > before + 0.0001:   # Dave: nothing through anything - refuse a move that goes in deeper; the ram stalls
				_joint_set(j2, old)
				_apply_pose()
				r2.stalled = true
				r2.speed = 0.0
	_apply_pose()
	for i3 in range(_hrams.size()):
		var r3 = _hrams[i3][0]
		var l: Label3D = _plabels[i3]
		var p: float = maxf(r3.p_cap, r3.p_rod)
		l.text = "%s  %d bar\n%d L/min%s" % [r3.name, int(p), int(r3.flow), "  STALL" if r3.stalled else ""]
		l.modulate = Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.2, 0.1), clampf(p / hyd.relief, 0.0, 1.0))
		var vis2: Node3D = _hrams[i3][2]
		if vis2 != null:
			var e: Array = vis2._ends()
			l.global_position = vis2.get_parent().global_transform * (((e[0] as Vector3) + (e[1] as Vector3)) * 0.5) + Vector3(0, 0.5, 0)
	_pump_label.text = hyd.summary() + "\nENGINE " + engine.status()


## In the lab, with no one in the seat, she works the levers by herself and the
## hydraulics do the rest: the arm moves as fast as the oil lets it, slows under
## load, stalls on the relief at the end of a stroke.
func _process(delta: float) -> void:
	if driven or not EK.in_lab(self):
		return
	if hyd == null:
		_hyd_setup()
	_demo_t += delta
	if engine.state == "off" and _demo_t < 1.0:
		engine.ambient = -12.0
		engine.temp = -12.0
		engine.start()
	hyd.rpm = engine.rpm
	var k: float = (1.0 if engine.state == "running" else 0.0) * (1.0 if fmod(_demo_t, 14.0) < 9.0 else 0.0)   # work, then hands off: it drops to idle
	var spools := [sin(_demo_t * 0.45) * k, sin(_demo_t * 0.6 + 1.0) * k, sin(_demo_t * 0.8 + 2.0) * k]
	engine.load = clampf(hyd.pressure / hyd.relief, 0.0, 1.0)
	engine.strain = hyd.strain()          # revs only when the oil can't move the load
	engine.hyd_power_max = 90000.0
	hyd.power_avail = engine.hyd_power()      # the pump gets only what the engine can give at these revs
	# the operator opens the throttle while working the levers (Dave: throttle up to lift), back to idle when hands off
	var lever := 0.0
	for r_ in hyd.rams:
		lever = maxf(lever, absf(r_.spool))
	engine.throttle = move_toward(engine.throttle, 0.85 if lever > 0.25 else 0.0, (0.8 if lever > 0.25 else 0.5) * delta)
	engine.drive_strain = 0.0
	# the upper swings on its ring too (swing motor, ~6 rpm flat out), slowly
	# side to side over the tracks while it works
	if k > 0.0:
		swing = move_toward(swing, sin(_demo_t * 0.16) * 1.6, delta * 0.5)
	# and the tracks creep, so the sprocket, the idler and the chain are seen turning together
	if engine.state == "running":
		_track_l.advance(0.25 * delta)
		_track_r.advance(0.25 * delta)
	_hyd_step(delta, spools)


func _apply_pose() -> void:
	_cab.rotation = Vector3(0, swing, 0)
	_boom.rotation = Vector3(boom_a, 0, 0)
	_stick.rotation = Vector3(-knee, 0, 0)
	_bucket.rotation = Vector3(-bucket_a, 0, 0)     # backhoe: + curls in toward the cab
	_link_pose()
	_curl = clampf((bucket_a + 0.6) / 1.6, 0.0, 1.0)
	_tip = teeth()


## The bucket's teeth, in the world.
func teeth() -> Vector3:
	return _bucket.global_transform * TEETH


## How full the bucket is, 0..1.
func fill() -> float:
	return clampf((float(bucket_load.get("over", 0.0)) + float(bucket_load.get("pay", 0.0)) + float(bucket_load.get("rock", 0.0))) / BUCKET_M3, 0.0, 1.0)


## Lever mode, one frame. Inputs -1..1: swing (right +), stick (out +),
## boom (up +), bucket (curl +). The ground pushes back: the teeth can bite
## in a hand's depth, and drag or curl through it to fill the bucket; open
## the bucket over a spot (or the wash plant hopper) to dump it there.
func levers_step(delta: float, swing_in: float, stick_in: float, boom_in: float, bkt_in: float) -> String:
	var msg := ""
	state = ""
	var prev := [swing, boom_a, knee, bucket_a]
	var t0 := teeth()
	var full := fill() >= 0.999
	# Too deep, or a full bucket shoved into the bank: the ground wins - but
	# only against the lever that's pushing the teeth in. Each joint moves on
	# its own and is stopped alone, so boom-up always lifts you out.
	var limit := 0.05 if full else 0.42 * SCALE
	var moves := [
		["boom", boom_in * 0.55 * delta],
		["knee", -stick_in * 0.75 * delta],
		["swing", -swing_in * 0.85 * delta],
		["bucket", bkt_in * 1.3 * delta],
	]
	_resist = 0.0
	for mv in moves:
		var amt: float = mv[1]
		if absf(amt) < 0.000001:
			continue
		var before := teeth()
		var pen0: float = terrain.height_at(before.x, before.z) - before.y
		var keep: Array = [swing, boom_a, knee, bucket_a]
		match String(mv[0]):
			"boom":
				boom_a = clampf(boom_a + amt, BOOM_MIN, BOOM_MAX)
			"knee":
				knee = clampf(knee + amt, KNEE_MIN, KNEE_MAX)
			"swing":
				swing += amt
			"bucket":
				bucket_a = clampf(bucket_a + amt, BKT_MIN, BKT_MAX)
		_apply_pose()
		var after := teeth()
		var pen1: float = terrain.height_at(after.x, after.z) - after.y
		if pen1 > limit and pen1 > pen0 + 0.002:
			# the bucket rides up the cut: lift the boom just enough to hold the bite
			var lifted := 0.0
			while pen1 > maxf(limit, pen0) and lifted < 0.12 and boom_a < BOOM_MAX:
				boom_a = minf(boom_a + 0.006, BOOM_MAX)
				lifted += 0.006
				_apply_pose()
				var a2 := teeth()
				pen1 = terrain.height_at(a2.x, a2.z) - a2.y
			_resist = 1.0
			if pen1 > maxf(limit, pen0) + 0.002:
				swing = keep[0]; boom_a = keep[1]; knee = keep[2]; bucket_a = keep[3]
				_apply_pose()
	var tp := teeth()
	var pen: float = terrain.height_at(tp.x, tp.z) - tp.y
	# The bucket planted (DESIGN_NOTES 150): boom down into the ground lifts
	# the machine on it; the stick pulled in drags her toward the bucket (out
	# pushes her back). The tracks turn with it so she walks.
	if body != null and not kinematic:
		var g := 9.81 * float(body.mass)
		var f := Vector3.ZERO
		var planted := pen > 0.15 * SCALE
		if planted and boom_in < -0.1:
			f += Vector3.UP * 0.75 * g * clampf(-boom_in, 0.0, 1.0)
		var walk := 0.0
		if planted and absf(stick_in) > 0.1:
			var to := tp - global_position
			to.y = 0.0
			to = to.normalized()
			f += to * 0.4 * g * -stick_in
			var fwd1 := -global_transform.basis.z
			walk = clampf(to.dot(fwd1) * -stick_in, -1.0, 1.0) * 0.7
		body.ext_point = tp
		body.ext_force = f
		if f != Vector3.ZERO:
			body.sink = maxf(float(body.sink) - 0.05 * delta, 0.0)
		body.step(delta, walk, walk)
		global_transform = body.transform()
		yaw = body.yaw()
		tp = teeth()
		pen = terrain.height_at(tp.x, tp.z) - tp.y
	# Teeth in the ground and moving: that's a cut.
	if pen > 0.02 and not full:
		var moved := Vector2(tp.x - t0.x, tp.z - t0.z).length() + absf(tp.y - t0.y) * 0.5
		var curling := maxf(bucket_a - float(prev[3]), 0.0)
		var vol := (0.55 * minf(pen, 0.42 * SCALE) * moved + 0.22 * curling * minf(pen, 0.42 * SCALE)) * SCALE
		_cut_acc += vol
		_resist = maxf(_resist, clampf(pen / (0.42 * SCALE), 0.2, 0.9))
		if _cut_acc > 0.01 and on_cut.is_valid():
			var room := BUCKET_M3 * (1.0 - fill())
			var got: Dictionary = on_cut.call(tp, tp.y, minf(_cut_acc, room))
			_cut_acc = 0.0
			if got.is_empty():
				pass
			elif float(got.get("over", 0.0)) + float(got.get("pay", 0.0)) + float(got.get("rock", 0.0)) > 0.0:
				for k in ["over", "pay", "g", "rock"]:
					bucket_load[k] = float(bucket_load.get(k, 0.0)) + float(got.get(k, 0.0))
			elif bool(got.get("bedrock", false)):
				msg = "The teeth skate on bedrock."
	# Bucket opened with something in it: it pours out under the teeth.
	if not bucket_load.is_empty() and bucket_a < -0.35:
		var at := tp
		at.y = terrain.height_at(at.x, at.z)
		msg = on_dump.call(at, bucket_load) if on_dump.is_valid() else ""
		bucket_load = {}
	_dirt.visible = not bucket_load.is_empty() and bucket_a > -0.2
	if _dirt.visible:
		_dirt.scale = Vector3(1, clampf(fill(), 0.3, 1.0), 1)
	return msg


## Where a winch hook or tow strap can go: [[name, world point], ...].
func winch_points() -> Array:
	return TowPoints.world(_tracks, WINCH_POINTS)
