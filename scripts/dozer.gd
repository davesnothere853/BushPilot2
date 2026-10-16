extends Node3D
## A crawler bulldozer (D8 class) for roadwork and camp pads. Get in and
## drive on the tracks; drop the blade and push forward, and the ground is
## graded to the machine's own level: high ground is cut into the blade,
## hollows are filled from it, and a packed dirt cut is left behind - the
## way to make roads, pads and ramps anywhere (the dig system does the
## earthmoving, so it all persists). The blade holds about a metre and a
## half cubed; carry the surplus to a low spot and spread it.

const MeshKit = preload("res://scripts/meshkit.gd")
const Flora = preload("res://scripts/flora.gd")
const TrackLoop = preload("res://scripts/track_loop.gd")
const TrackedBody = preload("res://scripts/tracked_body.gd")
const EK = preload("res://scripts/equip_kit.gd")

const YELLOW := Color(0.88, 0.68, 0.16)          # the weathered early-80s yellow of the reference machines
const DARK := Color(0.12, 0.12, 0.12)
const STEEL := Color(0.42, 0.42, 0.44)
const GLASS := Color(0.50, 0.62, 0.68, 0.38)
const BLADE_W := 3.1                # semi-U on a D5-size machine (was 3.4: wider than the real one)
const LOAD_MAX := 3.6              # m3: a semi-U blade on a D5-size machine

var terrain: RefCounted
var yaw := 0.0
var driven := false
var blade_down := false
var load_m3 := 0.0
var home := Transform3D.IDENTITY
var on_grade: Callable            # func(point, radius, target, fill_m3, cut_m3) -> Dictionary
var on_spill: Callable            # func(point, m3): surplus cast off the blade's sides
var on_tree: Callable             # func(tree, push): a trunk pushed over by the blade

var _blade: Node3D
var _blade_pos := 0.0             # 0 carried high, 1 on the ground
var blade_h := 0.55               # blade edge above the track bottoms (m); below 0 = cutting down
var _blade_goal := 0.55           # where the button sends it
const BLADE_CARRY := 0.55
const BLADE_LOW := -0.45          # deepest cut a pass
const BLADE_HIGH := 1.0
var _grade_acc := 0.0
var body: RefCounted              # tracked_body.gd: the real physics
var kinematic := false            # true: the old slide-along driving (tests, fallback)
var _full_told := false
var _tip_told := false
var _pay_told := false
var _dirt: MeshInstance3D
var _track_l: MultiMeshInstance3D
var _track_r: MultiMeshInstance3D


var _seat_at := Vector3.ZERO
var seat: Node3D
var engine: Node3D


## The lab and the cab: click the seat's air valve (and whatever else gets a control).
func control_click(nm: String) -> String:
	if nm == "seat_air" and seat != null:
		return seat.air()
	return ""



func lights_toggle() -> String:
	return EK.lights_toggle(self)


const TowPoints = preload("res://scripts/tow_points.gd")
## Winch / tow points (DESIGN_NOTES 225): a shackle on the front of the main
## frame under the radiator guard, one on each ripper bracket at the back.
const WINCH_POINTS := [
	["front tow shackle", Vector3(0, 0.55, -1.70), Vector3(0, 0, -1)],
	["rear left shackle", Vector3(-0.80, 0.62, 1.88), Vector3(0, 0, 1)],
	["rear right shackle", Vector3(0.80, 0.62, 1.88), Vector3(0, 0, 1)],
]

func build() -> void:
	var kit := MeshKit.new()
	# Track frames: long, with idler, drive sprocket, rollers and shoes.
	for sx in [-0.95, 0.95]:
		# the track frame: a box beam inside the loop with the rollers under it,
		# two carrier rollers on top, a guard plate along the outside
		kit.box_at(Vector3(sx, 0.42, 0), Vector3(0.34, 0.3, 2.5), YELLOW.darkened(0.35))
		kit.box_at(Vector3(sx + signf(sx) * 0.18, 0.3, 0), Vector3(0.02, 0.16, 2.2), YELLOW.darkened(0.4))
		# the push arm's trunnion: a stub out of the track frame between the track's
		# runs, the arm's cap turning on it (the blade's pivot)
		var tsx := signf(sx)
		kit.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5) if tsx < 0.0 else Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx + tsx * 0.17, 0.55 + TRUNNION.y, TRUNNION.z)), 0.075, 0.075, 0.2, 12, STEEL.darkened(0.1))
		kit.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5) if tsx < 0.0 else Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx + tsx * 0.17, 0.55 + TRUNNION.y, TRUNNION.z)), 0.12, 0.12, 0.03, 14, YELLOW.darkened(0.4))   # its flange on the frame
		for cz in [-0.5, 0.5]:
			kit.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.1, 0.66, cz)), 0.07, 0.07, 0.2, 8, STEEL)
		# idler and sprocket sized to run inside the chain's rails (they cut through the track)
		kit.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.2, 0.40, -1.38)), 0.22, 0.22, 0.4, 16, STEEL)
		kit.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.2, 0.40, 1.38)), 0.21, 0.21, 0.4, 16, STEEL.darkened(0.2))
		kit.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.2 - signf(sx) * 0.3, 0.40, 1.38)), 0.2, 0.2, 0.2, 10, DARK)   # final drive
		for tooth in range(8):
			var ta := TAU * float(tooth) / 8.0
			kit.box(Transform3D(Basis(Vector3.RIGHT, -ta), Vector3(sx, 0.40 + sin(ta) * 0.235, 1.38 + cos(ta) * 0.235)), Vector3(0.1, 0.06, 0.06), STEEL.darkened(0.3))   # teeth between the link pins
		for rz in [-0.95, -0.48, 0.0, 0.48, 0.95]:
			kit.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.17, 0.16, rz)), 0.12, 0.12, 0.34, 10, STEEL)
	# Belly and engine bay: a long hood sloping down to the radiator.
	kit.box_at(Vector3(0, 0.62, 0.1), Vector3(1.3, 0.5, 2.9), YELLOW.darkened(0.25))
	# (the hood stands 1.85 m, head height on a man, as on the real machine;
	# it used to be 1.44, chest height, which made the whole dozer look toy-sized)
	# the hood: high at the cab, sloping down to the nose so you can see the
	# blade (as the real medium dozers do), rounded top corners
	var hood: Array = []
	for e in [[0.32, 1.92], [-1.4, 1.8]]:          # nearly level, as on the D6-size machines in the photos
		var z: float = e[0]
		var top: float = e[1]
		var ring := PackedVector3Array()
		for q in [Vector2(-0.56, 0.86), Vector2(0.56, 0.86), Vector2(0.56, top - 0.12), Vector2(0.44, top), Vector2(-0.44, top), Vector2(-0.56, top - 0.12)]:
			ring.append(Vector3(q.x, q.y, z))
		hood.append(ring)
	kit.loft(hood, YELLOW, true, true)
	# side doors with louvres, the radiator guard at the nose (a perforated grille)
	for sx3 in [-1.0, 1.0]:
		for lz2 in range(8):
			kit.box_at(Vector3(sx3 * 0.565, 1.3, -0.9 + 0.12 * float(lz2)), Vector3(0.012, 0.5, 0.05), DARK)
		kit.box_at(Vector3(sx3 * 0.565, 1.6, -0.35), Vector3(0.012, 0.04, 1.4), YELLOW.darkened(0.2))
	kit.box_at(Vector3(0, 1.22, -1.43), Vector3(1.14, 0.74, 0.08), YELLOW.darkened(0.2))   # radiator guard
	for gy in range(6):
		for gx in range(7):
			kit.box_at(Vector3(-0.42 + 0.14 * float(gx), 0.98 + 0.1 * float(gy), -1.475), Vector3(0.07, 0.05, 0.01), DARK)
	kit.box_at(Vector3(0, 0.8, -1.55), Vector3(1.0, 0.28, 0.25), DARK)                     # front pull hook / guard
	# fenders over the tracks: flat steel walkways from the nose to the cab, and the rails
	for sx4 in [-0.95, 0.95]:
		kit.box_at(Vector3(sx4, 0.86, -0.1), Vector3(0.62, 0.05, 2.7), YELLOW.darkened(0.12))
		kit.box_at(Vector3(sx4 + signf(sx4) * 0.3, 0.8, -0.1), Vector3(0.03, 0.12, 2.7), YELLOW.darkened(0.3))
		_beam_d(kit, Vector3(sx4 * 0.62, 1.95, 0.35), Vector3(sx4 * 0.62, 1.95, -0.6), 0.02, STEEL)
	# Exhaust stack with its rain cap, and the pre-cleaner bowl.
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.22, 1.88, -0.75)), 0.06, 0.055, 0.75, 8, DARK)
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.25, 1.88, -0.75)), 0.05, 0.05, 0.4, 8, STEEL)
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.25, 2.28, -0.75)), 0.1, 0.07, 0.16, 8, STEEL.darkened(0.15))
	# Cab: ROPS posts, roof, floor, seat and levers (glass comes separate).
	kit.box_at(Vector3(0, 1.15, 0.95), Vector3(1.25, 0.56, 1.3), YELLOW.darkened(0.15))   # cab deck at 1.43 m
	for px in [-0.58, 0.58]:
		for pz in [0.42, 1.52]:
			kit.box_at(Vector3(px, 2.2, pz), Vector3(0.08, 1.55, 0.08), DARK)
	kit.box_at(Vector3(0, 2.99, 0.97), Vector3(1.4, 0.07, 1.4), YELLOW)          # ROPS roof at 3.0 m
	_seat_at = Vector3(0, 1.45, 1.05)
	kit.box_at(Vector3(0.3, 1.75, 0.62), Vector3(0.04, 0.3, 0.04), STEEL)          # blade lever
	kit.box_at(Vector3(0.3, 1.9, 0.6), Vector3(0.06, 0.06, 0.06), DARK)
	# Drawbar and ripper at the back: frame, three shanks with teeth.
	kit.box_at(Vector3(0, 0.75, 1.85), Vector3(1.1, 0.25, 0.35), YELLOW.darkened(0.2))
	# (the ripper's shanks: curved, with their tips and pins - in _detail())
	add_child(kit.instance("Body"))
	# The shoes run round the real loop (track_loop.gd) and move when driven.
	_track_l = TrackLoop.new()
	_track_l.setup(-0.95, 1.35, 0.05, 0.72, 66, Vector3(0.52, 0.035, 0.1), Color(0.19, 0.19, 0.19))
	add_child(_track_l)
	_track_r = TrackLoop.new()
	_track_r.setup(0.95, 1.35, 0.05, 0.72, 66, Vector3(0.52, 0.035, 0.1), Color(0.19, 0.19, 0.19))
	add_child(_track_r)
	# Glass all round the cab, see-through.
	var gk := MeshKit.new()
	var seal := MeshKit.new()
	EK.pane(gk, seal, Vector3(-0.52, 1.5, 0.42), Vector3(0.52, 1.5, 0.42), Vector3(0.52, 2.9, 0.42), Vector3(-0.52, 2.9, 0.42), Vector3(0, 0, -1))
	EK.pane(gk, seal, Vector3(0.52, 1.55, 1.52), Vector3(-0.52, 1.55, 1.52), Vector3(-0.52, 2.9, 1.52), Vector3(0.52, 2.9, 1.52), Vector3(0, 0, 1))
	for gx in [-0.58, 0.58]:
		var sg := signf(gx)
		EK.pane(gk, seal, Vector3(gx, 1.5, 0.97 + 0.5 * sg), Vector3(gx, 1.5, 0.97 - 0.5 * sg), Vector3(gx, 2.9, 0.97 - 0.5 * sg), Vector3(gx, 2.9, 0.97 + 0.5 * sg), Vector3(sg, 0, 0))
	add_child(seal.instance("Seals"))
	var gmesh := gk.instance("Glass")
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = GLASS
	gmat.roughness = 0.08
	gmat.metallic = 0.2
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gmesh.material_override = gmat
	gmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gmesh)
	# The blade on its push arms, lifted and dropped as one.
	_blade = Node3D.new()
	_blade.name = "Blade"
	var bk := MeshKit.new()
	# C-frame push arms: heavy box-section beams running outside the track
	# frames to the blade's back, with diagonal braces - as on a D8's semi-U.
	for ax in [-1.28, 1.28]:
		# the C-frame arms run low, outside the tracks, under the fenders (as on the
		# reference machines) from the trunnions back by the sprockets to the blade
		bk.box(Transform3D(Basis(Vector3.UP, 0.04 * signf(ax)), Vector3(ax * 1.04, -0.08, -0.85)), Vector3(0.16, 0.24, 2.3), YELLOW.darkened(0.3))
		bk.box(Transform3D(Basis(Vector3.UP, -0.42 * signf(ax)), Vector3(ax * 0.74, 0.1, -1.6)), Vector3(0.1, 0.14, 0.9), YELLOW.darkened(0.35))
		# Trunnion where the arm meets the track frame: the ball in its cap, bolted.
		bk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(ax * 1.0 + (0.08 if ax > 0.0 else -0.0), -0.1, 0.25)), 0.13, 0.13, 0.16, 14, STEEL.darkened(0.2))
	# Lift cylinders from the nose down to the blade's top edge: painted barrels,
	# chrome rods, their hoses back along the hood.
	var bm := MeshKit.new()
	# the tilt cylinder on the right push arm
	# (no tilt ram: this blade is set by the screw brace - Dave: nothing without a job)
	var bmi := bm.instance("BladeMetal")
	bmi.material_override = EK.metal_mat()
	_blade.add_child(bmi)
	# The moldboard: one curved sheet, rolled back at the top so dirt curls,
	# built as lofted strips along a real blade profile.
	# (height, z): cutting edge forward at the bottom, the face dished back
	# toward the machine in the middle, the top lip rolled forward again -
	# concave to the front, so the dirt rolls up and over ahead of it.
	var prof := [Vector2(0.03, -2.12), Vector2(0.16, -2.02), Vector2(0.38, -1.94),
		Vector2(0.66, -1.92), Vector2(0.92, -1.98), Vector2(1.10, -2.12)]
	var wsegs := 8
	for k in range(prof.size() - 1):
		var a: Vector2 = prof[k]
		var b: Vector2 = prof[k + 1]
		for m in range(wsegs):
			var x0 := -BLADE_W * 0.5 + BLADE_W * float(m) / float(wsegs)
			var x1 := x0 + BLADE_W / float(wsegs)
			var nrm := Vector3(0, b.y - a.y, -(b.x - a.x)).normalized()
			if nrm.z > 0.0:
				nrm = -nrm
			bk.quad(Vector3(x0, a.x, a.y), Vector3(x1, a.x, a.y),
				Vector3(x1, b.x, b.y), Vector3(x0, b.x, b.y), YELLOW, nrm)
			bk.quad(Vector3(x0, a.x, a.y), Vector3(x1, a.x, a.y),
				Vector3(x1, b.x, b.y), Vector3(x0, b.x, b.y), YELLOW, -nrm)      # both faces: the face read see-through from the front
			# And the back of the sheet, so it reads solid from behind.
			bk.quad(Vector3(x1, a.x, a.y + 0.05), Vector3(x0, a.x, a.y + 0.05),
				Vector3(x0, b.x, b.y + 0.05), Vector3(x1, b.x, b.y + 0.05), YELLOW.darkened(0.25), -nrm)
	# Side end-bits sweeping forward: the semi-U's wings.
	for wx in [-BLADE_W * 0.5, BLADE_W * 0.5]:
		var sgn := signf(wx)
		for k in range(prof.size() - 1):
			var a2: Vector2 = prof[k]
			var b2: Vector2 = prof[k + 1]
			bk.quad(Vector3(wx, a2.x, a2.y), Vector3(wx + sgn * 0.22, a2.x, a2.y - 0.34),
				Vector3(wx + sgn * 0.22, b2.x, b2.y - 0.30), Vector3(wx, b2.x, b2.y), YELLOW.darkened(0.08), Vector3(sgn, 0, 0.4))
	# the lift rams' ears, low on the blade's back between the tracks (as on the
	# real D6-size machines): a pair of plates each side of the rod eye, welded
	# to the back sheet, with the pin through
	for lcx in [-LIFT_X, LIFT_X]:
		for side in [-1.0, 1.0]:
			bk.box_at(Vector3(lcx + side * 0.075, LIFT_EAR.y, -1.76), Vector3(0.03, 0.2, 0.16), YELLOW.darkened(0.3))
		EK.pin(bk, Vector3(lcx, LIFT_EAR.y, LIFT_EAR.z), 0.1, 0.03, STEEL.darkened(0.2))
	# Stiffener ribs down the back, the way the real sheet is braced.
	for rx in [-1.1, -0.37, 0.37, 1.1]:
		bk.box(Transform3D(Basis.IDENTITY, Vector3(rx, 0.56, -1.76)), Vector3(0.07, 0.95, 0.12), YELLOW.darkened(0.3))
	# The face worn bare and rusty where the dirt rolls (the reference blades).
	for k2 in range(2):
		var a3: Vector2 = prof[k2]
		var b3: Vector2 = prof[k2 + 1]
		var nrm3 := Vector3(0, b3.y - a3.y, -(b3.x - a3.x)).normalized()
		if nrm3.z > 0.0:
			nrm3 = -nrm3
		bk.quad(Vector3(-BLADE_W * 0.5, a3.x, a3.y) + nrm3 * 0.004, Vector3(BLADE_W * 0.5, a3.x, a3.y) + nrm3 * 0.004,
			Vector3(BLADE_W * 0.5, b3.x, b3.y) + nrm3 * 0.004, Vector3(-BLADE_W * 0.5, b3.x, b3.y) + nrm3 * 0.004, Color(0.45, 0.32, 0.20) if k2 == 0 else Color(0.58, 0.45, 0.25), nrm3)
	# Hardened cutting edge with bolt-on corner bits, scarred steel.
	bk.box(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 0.05, -2.14)), Vector3(BLADE_W - 0.5, 0.14, 0.09), STEEL.darkened(0.35))
	for cbx in [-BLADE_W * 0.5 + 0.17, BLADE_W * 0.5 - 0.17]:
		bk.box(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(cbx, 0.06, -2.14)), Vector3(0.34, 0.17, 0.11), STEEL.darkened(0.45))
	# Top spill guard rolled back over the curl.
	bk.box(Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 1.14, -2.06)), Vector3(BLADE_W, 0.05, 0.22), YELLOW.darkened(0.12))
	_blade.add_child(bk.instance("BladeKit"))
	# Spoil heaped in front of the blade when it's carrying.
	_dirt = MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(BLADE_W * 0.8, 0.5, 0.7)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.45, 0.35, 0.22)
	dm.material = dmat
	_dirt.mesh = dm
	_dirt.position = Vector3(0, 0.35, -2.45)
	_dirt.visible = false
	_blade.add_child(_dirt)
	add_child(_blade)
	_blade.position = Vector3(0, 0.55, 0)
	_detail()
	_build_ripper()
	EK.add_collision(self)
	EK.dust_all(self, 0.5, 1.0)
	seat = EK.air_seat(self, _seat_at, 0.0)
	engine = EK.engine(self, Vector3(0.22, 2.63, -0.75), null, 0.055)
	# the lift rams (Dave: reference photos, real range of motion): as on the
	# real D6-size dozers, each hangs from a trunnion bracket high on the hood
	# side and leans forward down to ears low on the blade's back, inboard of
	# the tracks. Laid out so the stroke is a real cylinder's: 1.3 m closed,
	# 2.25 m open (open/closed 1.73) over the blade's whole 1.45 m travel.
	var Ram = ResourceLoader.load("res://scripts/hyd_ram.gd", "", ResourceLoader.CACHE_MODE_REPLACE)
	var tb := MeshKit.new()
	for sx in [-1.0, 1.0]:
		var top := Vector3(sx * LIFT_X, LIFT_TOP.y, LIFT_TOP.z)
		# the trunnion bracket: a plate bolted to the hood side, a boss each side of the barrel
		tb.box_at(Vector3(sx * 0.57, LIFT_TOP.y - 0.05, LIFT_TOP.z), Vector3(0.025, 0.3, 0.34), YELLOW.darkened(0.25))
		EK.pin(tb, top, 0.09, 0.035, STEEL.darkened(0.2))
		var r = Ram.new()
		add_child(r)
		r.setup(self, top, _blade, Vector3(sx * LIFT_X, LIFT_EAR.y, LIFT_EAR.z), 0.06, YELLOW.darkened(0.15), 0.85)
		# hard lines from the valve under the hood, out through the hood side, to the ram's ports
		r.plumb(self, self, Vector3(sx * 0.57, 1.45, -0.15), 0.014, [Vector3(sx * 0.6, 1.55, -0.25)])
		_lift_rams.append(r)
	add_child(tb.instance("LiftTrunnions"))
	TowPoints.build(self, WINCH_POINTS, YELLOW.darkened(0.2))


## The ripper (Dave: every cylinder works): a parallelogram on the back - two
## links each side from the ripper bracket on the frame to the beam, so the
## beam and its three shanks rise and drop staying upright - lifted and dropped
## by two cylinders from the bracket's crossmember to the beam's front face.
const RIP_L := 0.45                              # link, pin to pin
const RIP_PU := Vector3(0.62, 1.02, 1.85)         # upper links' frame pins (x each side)
const RIP_PL := Vector3(0.62, 0.62, 1.85)         # lower
const RIP_RAM_BASE := Vector3(0.35, 0.98, 1.6)    # the cylinders. base pins on the crossmember
const RIP_RAM_ROD := Vector3(0.35, -0.38, -0.14)  # their rod pins on the beam (beam frame), low on its face
const RIP_UP := 0.35
const RIP_DOWN := -0.55
var rip := 0.15                                   # the links' angle: + up, - down into the ground
var _ripper: Node3D
var _rip_links: Array = []
var _rip_rams: Array = []


func _rip_pos(a: float) -> Vector3:
	return Vector3(0, RIP_PU.y + sin(a) * RIP_L, RIP_PU.z + cos(a) * RIP_L)


func _rip_pose() -> void:
	if _ripper == null:
		return
	_ripper.position = _rip_pos(rip)
	for l in _rip_links:
		(l as Node3D).rotation.x = -rip


func _build_ripper() -> void:
	var bk := MeshKit.new()
	# the ripper bracket bolted to the back of the frame: an upright each side
	# carrying the links' clevises, a crossmember for the cylinders
	for sx in [-1.0, 1.0]:
		bk.box_at(Vector3(sx * RIP_PU.x, 0.82, 1.74), Vector3(0.2, 0.62, 0.14), YELLOW.darkened(0.25))
		for py in [RIP_PU.y, RIP_PL.y]:
			EK.lug(bk, Vector3(sx * RIP_PU.x, py, RIP_PU.z), 0.05, 0.03, 0.08, Vector3(0, 0, -1), 0.1, YELLOW.darkened(0.25))
		EK.lug(bk, Vector3(sx * RIP_RAM_BASE.x, RIP_RAM_BASE.y, RIP_RAM_BASE.z), 0.045, 0.03, 0.08, Vector3(0, 0, 1), 0.08, YELLOW.darkened(0.25))
	bk.box_at(Vector3(0, 1.0, 1.7), Vector3(1.38, 0.16, 0.1), YELLOW.darkened(0.25))       # the crossmember
	add_child(bk.instance("RipperBracket"))
	# the links: a plate each, rounded round both pins, swinging on the bracket
	for sx2 in [-1.0, 1.0]:
		for py2 in [RIP_PU.y, RIP_PL.y]:
			var ln := Node3D.new()
			ln.position = Vector3(0, py2, RIP_PU.z)
			add_child(ln)
			var lk := MeshKit.new()
			lk.box_at(Vector3(sx2 * RIP_PU.x, 0, RIP_L * 0.5), Vector3(0.05, 0.1, RIP_L), YELLOW.darkened(0.2))
			for ez in [0.0, RIP_L]:
				lk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx2 * RIP_PU.x + 0.025, 0, ez)), 0.06, 0.06, 0.05, 12, YELLOW.darkened(0.2), true)
			ln.add_child(lk.instance("RipperLink"))
			_rip_links.append(ln)
	# the beam and the shanks, in the beam's frame (origin at the upper rear pins)
	_ripper = Node3D.new()
	_ripper.name = "Ripper"
	add_child(_ripper)
	var rk := MeshKit.new()
	var mk := MeshKit.new()
	rk.box_at(Vector3(0, -0.17, -0.02), Vector3(1.45, 0.5, 0.18), YELLOW.darkened(0.1))          # the beam
	for ex in [-1.0, 1.0]:
		EK.pin(mk, Vector3(ex * RIP_PU.x, 0, 0), 0.06, 0.035, YELLOW.darkened(0.2))
		EK.pin(mk, Vector3(ex * RIP_PU.x, RIP_PL.y - RIP_PU.y, 0), 0.06, 0.035, YELLOW.darkened(0.2))
		EK.lug(rk, Vector3(ex * RIP_RAM_ROD.x, RIP_RAM_ROD.y, RIP_RAM_ROD.z), 0.045, 0.03, 0.08, Vector3(0, 0, 1), 0.05, YELLOW.darkened(0.15))
	for rx in [-0.5, 0.0, 0.5]:
		var shank: Array = []
		for k in range(6):
			var f := float(k) / 5.0
			var y := 0.95 - f * 0.85 - RIP_PU.y - 0.0
			var z := 2.36 + sin(f * 1.4) * 0.28 - (RIP_PU.z + RIP_L)
			var ring := PackedVector3Array()
			var w := 0.045
			var dpt := lerpf(0.13, 0.09, f)
			for q in [Vector2(-w, -dpt), Vector2(w, -dpt), Vector2(w, dpt), Vector2(-w, dpt)]:
				ring.append(Vector3(rx + q.x, y, z + q.y))
			shank.append(ring)
		mk.loft(shank, Color(0.30, 0.29, 0.28), true, true)
		mk.box(Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(rx, 0.08 - RIP_PU.y, 2.72 - RIP_PU.z - RIP_L)), Vector3(0.07, 0.06, 0.24), Color(0.55, 0.53, 0.5))   # the tip
		mk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(rx + 0.06, 0.92 - RIP_PU.y, 2.36 - RIP_PU.z - RIP_L)), 0.03, 0.03, 0.12, 8, EK.STEEL, true)
	_ripper.add_child(rk.instance("RipperBeam"))
	var mi := mk.instance("RipperSteel")
	mi.material_override = EK.metal_mat()
	_ripper.add_child(mi)
	_rip_pose()
	# the cylinders, working: crossmember to the beam
	var Ram = ResourceLoader.load("res://scripts/hyd_ram.gd", "", ResourceLoader.CACHE_MODE_REPLACE)
	for sx3 in [-1.0, 1.0]:
		var r = Ram.new()
		add_child(r)
		r.setup(self, Vector3(sx3 * RIP_RAM_BASE.x, RIP_RAM_BASE.y, RIP_RAM_BASE.z), _ripper, Vector3(sx3 * RIP_RAM_ROD.x, RIP_RAM_ROD.y, RIP_RAM_ROD.z), 0.06, YELLOW.darkened(0.15), 0.55)
		r.plumb(self, self, Vector3(sx3 * 0.2, 1.2, 1.4), 0.014, [Vector3(sx3 * 0.3, 1.1, 1.6)])
		_rip_rams.append(r)


## The truck treatment (DESIGN_NOTES 215), from early-80s medium dozers: the
## cab's door, drip rail, wiper and levers, lamps like the truck's on the ROPS
## and the radiator guard, grab rails and steps, the fuel tank, the ripper's
## cylinders, bolts and decals.
func _detail() -> void:
	var p := MeshKit.new()
	var d := MeshKit.new()
	var m := MeshKit.new()
	var cz := 0.97
	for sz in [-1.0, 1.0]:
		p.box_at(Vector3(0, 2.93, cz + sz * 0.7), Vector3(1.42, 0.05, 0.04), YELLOW.darkened(0.2))
	for sx in [-1.0, 1.0]:
		p.box_at(Vector3(sx * 0.7, 2.93, cz), Vector3(0.04, 0.05, 1.42), YELLOW.darkened(0.2))
		# the door each side: its rear edge, handle, hinges
		d.box_at(Vector3(sx * 0.595, 2.2, cz + 0.35), Vector3(0.02, 1.35, 0.03), DARK)
		d.box_at(Vector3(sx * 0.6, 1.95, cz + 0.28), Vector3(0.04, 0.03, 0.12), EK.STEEL)
		for hy in [1.7, 2.6]:
			d.box_at(Vector3(sx * 0.6, hy, cz - 0.5), Vector3(0.04, 0.1, 0.05), DARK)
		# lamps: two on the ROPS front corners, one back on each rear post, on the radiator guard
		EK.lamp(d, m, self, Vector3(sx * 0.5, 3.1, 0.3), Vector3(0, -0.12, -1), 0.17, 0.12, Color(1, 0.97, 0.85))
		d.box_at(Vector3(sx * 0.5, 3.03, 0.38), Vector3(0.05, 0.08, 0.1), DARK)
		EK.lamp(d, m, self, Vector3(sx * 0.5, 3.1, 1.64), Vector3(0, -0.12, 1), 0.17, 0.12, Color(1, 0.97, 0.85))
		d.box_at(Vector3(sx * 0.5, 3.03, 1.56), Vector3(0.05, 0.08, 0.1), DARK)
		EK.lamp(d, m, self, Vector3(sx * 0.48, 1.72, -1.5), Vector3(0, -0.05, -1), 0.15, 0.15, Color(1, 0.97, 0.85), true)
		# grab rails along the hood sides, steps up the track frame
		EK.rail(p, [Vector3(sx * 0.6, 1.75, -0.95), Vector3(sx * 0.6, 1.95, -0.8), Vector3(sx * 0.6, 1.95, 0.3)], YELLOW.darkened(0.2), 0.02)
		EK.grate_step(m, Vector3(sx * 1.3, 0.62, 0.6), 0.3, 0.26)
		# warning decals on the cab deck sides, the model on the hood
		EK.decal(self, "D-6", Vector3(sx * 0.567, 1.45, -0.5), Vector3(sx, 0, 0), 0.0035, Color(0.08, 0.08, 0.08))
		EK.decal(self, "WARNING\nNO RIDERS", Vector3(sx * 0.63, 1.15, 0.95), Vector3(sx, 0, 0), 0.0009, Color(0.05, 0.05, 0.05), Color(0.95, 0.75, 0.1), d, 0.2, 0.12)
		EK.bolts(m, Vector3(sx * 0.567, 0.92, -1.3), Vector3(sx * 0.567, 0.92, 0.3), 9, Vector3(sx, 0, 0), 0.016)
		# track guards: bolt heads along the outer guard plate
		EK.bolts(m, Vector3(sx * 1.14, 0.3, -1.0), Vector3(sx * 1.14, 0.3, 1.0), 12, Vector3(sx, 0, 0), 0.02)
	EK.rod(d, Vector3(0.35, 2.85, 0.4), Vector3(-0.05, 1.7, 0.4), 0.008, DARK)          # wiper
	EK.rod(d, Vector3(0.0, 1.8, 0.395), Vector3(-0.2, 2.5, 0.395), 0.01, Color(0.03, 0.03, 0.03))
	EK.beacon(d, self, Vector3(0.3, 3.03, 1.2))
	# the levers: steering clutches, the blade joystick with their knobs, a dash
	for lv in range(2):
		EK.rod(d, Vector3(-0.15 + float(lv) * 0.3, 1.45, 0.65), Vector3(-0.15 + float(lv) * 0.3, 1.95, 0.6), 0.015, DARK)
		m.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.15 + float(lv) * 0.3, 1.95, 0.6)), 0.03, 0.03, 0.08, 10, Color(0.1, 0.1, 0.1), true)
	d.rbox(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 1.75, 0.5)), Vector3(0.7, 0.2, 0.1), DARK, 0.03)
	for gi in range(4):
		m.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + 0.5), Vector3(-0.24 + float(gi) * 0.16, 1.78, 0.45)), 0.035, 0.035, 0.01, 12, Color(0.85, 0.85, 0.8), true)
	# the fuel tank behind the cab, its cap; the ripper's two cylinders
	p.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 1.32, 1.72)), Vector3(1.2, 0.55, 0.3), YELLOW, 0.05)
	m.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.4, 1.6, 1.72)), 0.06, 0.06, 0.05, 12, EK.STEEL, true)
	# radiator guard: a proper perforated grille in its frame, the pull hook
	EK.grille(d, d, Vector3(0, 1.22, -1.48), Vector3(0, 0, -1), 1.0, 0.62, 9, false)
	m.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.15, 0.82, -1.69)), 0.06, 0.06, 0.3, 10, EK.STEEL, true)
	# exhaust rain cap and the pre-cleaner's bowl
	# (the ripper is a working parallelogram: _build_ripper())
	# --- fenders: drop plates front and back, a tool box and the battery box on top
	for sx7 in [-1.0, 1.0]:
		p.box_at(Vector3(sx7 * 1.25, 0.72, -1.42), Vector3(0.04, 0.3, 0.06), YELLOW.darkened(0.12))
		p.box(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(sx7 * 0.95, 0.78, 1.32)), Vector3(0.62, 0.04, 0.3), YELLOW.darkened(0.12))
		# final drive housing on the sprocket hub: a big bolted bell
		m.cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5 * sx7), Vector3(sx7 * 1.17, 0.40, 1.38)), 0.24, 0.2, 0.12, 18, DARK, true)
		for bb in range(12):
			var ba := TAU * float(bb) / 12.0
			m.cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5 * sx7), Vector3(sx7 * 1.28, 0.40 + cos(ba) * 0.18, 1.38 + sin(ba) * 0.18)), 0.016, 0.016, 0.02, 6, EK.STEEL, true)
		# idler recoil housing ahead of the track frame
		d.box_at(Vector3(sx7 * 0.95, 0.42, -1.05), Vector3(0.22, 0.2, 0.45), DARK)
	p.rbox(Transform3D(Basis.IDENTITY, Vector3(-0.95, 1.04, -0.6)), Vector3(0.5, 0.32, 0.7), YELLOW.darkened(0.08), 0.03)    # tool box
	m.box_at(Vector3(-0.95, 1.21, -0.6), Vector3(0.12, 0.03, 0.05), EK.STEEL)
	p.rbox(Transform3D(Basis.IDENTITY, Vector3(0.95, 1.02, -0.75)), Vector3(0.45, 0.28, 0.5), YELLOW.darkened(0.08), 0.03)     # battery box
	# --- hood: the engine side doors' seams, their hinges and latches
	for sx8 in [-1.0, 1.0]:
		var hx: float = float(sx8) * 0.567
		for dz in [-1.32, -0.55, 0.25]:
			d.box_at(Vector3(hx, 1.33, dz), Vector3(0.012, 0.85, 0.015), DARK)
		d.box_at(Vector3(hx, 1.76, -0.55), Vector3(0.013, 0.015, 1.55), DARK)
		for lz3 in [-0.9, -0.1]:
			m.box_at(Vector3(hx + float(sx8) * 0.01, 1.1, lz3), Vector3(0.02, 0.05, 0.12), EK.STEEL)
	# --- blade: the tilt brace (a screw tube) from the left push arm up to the blade
	var tb := MeshKit.new()           # on the blade itself (it rides up and down with it)
	EK.rod(tb, Vector3(-1.32, 0.05, -1.3), Vector3(-1.2, 0.9, -1.76), 0.045, YELLOW.darkened(0.25))   # from the push arm's top to the blade's back
	EK.rod(tb, Vector3(-1.29, 0.3, -1.44), Vector3(-1.26, 0.45, -1.52), 0.03, EK.STEEL)
	for e in [Vector3(-1.32, 0.05, -1.3), Vector3(-1.2, 0.9, -1.76)]:
		tb.box_at(e, Vector3(0.12, 0.1, 0.1), YELLOW.darkened(0.3))             # its clevises
	var tbi := tb.instance("TiltBrace")
	tbi.material_override = EK.metal_mat()
	_blade.add_child(tbi)
	add_child(p.instance("Detail"))
	add_child(d.instance("DetailDark"))
	var mm := m.instance("DetailMetal")
	mm.material_override = EK.metal_mat()
	add_child(mm)


static func _beam_d(kit: RefCounted, a: Vector3, b: Vector3, radius: float, col: Color) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	kit.cylinder(Transform3D(Basis(x, y, z), a), radius, radius, d.length(), 6, col, true)


func park(xf: Transform3D) -> void:
	home = xf
	var f := -xf.basis.z
	yaw = atan2(-f.x, -f.z)
	global_position = xf.origin
	_settle()
	body = TrackedBody.new()
	body.mass = 13500.0
	body.shoe = 0.56                # D5-size (DESIGN_NOTES 71: Dave - "more power, pull")
	body.power = 120000.0
	body.mu = 0.9
	body.length = 2.7
	body.width = 1.95
	body.height = 3.0
	body.com = Vector3(0, 0.8, -0.15)
	body.top_speed = 2.7
	body.ground_y = func(x: float, z: float) -> float: return terrain.wheel_ground(x, z) if terrain.has_method("wheel_ground") else terrain.height_at(x, z)
	body.blocked = func(p: Vector3) -> bool: return terrain.blocked_by_building(p, 1.1, self)
	body.setup()
	body.place(global_transform)
	body.settle()
	global_transform = body.transform()


func eye_xf() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 2.38, 1.0))


func _settle() -> void:
	var p := global_position
	p.y = terrain.height_at(p.x, p.z)
	var n: Vector3 = terrain.normal_at(p.x, p.z)
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var right := fwd.cross(n).normalized()
	global_transform = Transform3D(Basis(right, n, -fwd), p)


## Raise (+) / lower (-) the blade by hand, -1..1. Below the tracks it cuts
## down a little every pass (a ramp into the ground); a touch above it
## spreads what it carries at that height.
func blade_adjust(delta: float, v: float) -> void:
	if absf(v) < 0.05:
		return
	_blade_goal = clampf(_blade_goal + v * 0.45 * delta, BLADE_LOW, BLADE_HIGH)
	var was := blade_down
	blade_down = _blade_goal < 0.15
	if was and not blade_down:
		_drop_load()


func _drop_load() -> void:
	if load_m3 > 0.1 and on_spill.is_valid():
		on_spill.call(global_position - global_transform.basis.z * 3.0, load_m3)
	load_m3 = 0.0


func blade_toggle() -> String:
	blade_down = not blade_down
	_blade_goal = 0.0 if blade_down else BLADE_CARRY
	_pay_told = false
	if blade_down:
		return "Blade down: push forward to cut and fill."
	# Lifting the blade leaves whatever it was carrying in a heap in front.
	if load_m3 > 0.1:
		var dumped := load_m3
		if on_spill.is_valid():
			on_spill.call(global_position - global_transform.basis.z * 3.0, dumped)
		load_m3 = 0.0
		return "Blade up: %.1f m3 left in a heap in front of you." % dumped
	return "Blade up."


## Tracks. Pushing with the blade down also grades the ground as it goes.
func drive(delta: float, move: Vector2) -> String:
	if body != null and not kinematic:
		return _drive_physics(delta, move)
	var msg := ""
	var sp := move.y * (1.05 if blade_down else 1.7)
	yaw -= move.x * 0.5 * delta
	# Each track rolls at its own speed: forward speed plus the turn.
	if _track_l != null:
		_track_l.advance((sp + move.x * 0.95 * 0.5) * delta)
		_track_r.advance((sp - move.x * 0.95 * 0.5) * delta)
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var p := global_position + fwd * sp * delta
	if terrain.blocked_by_building(p + fwd * (2.4 if sp >= 0.0 else -2.4) + Vector3(0, 0.6, 0), 1.1, self):
		p = global_position
	global_position = p
	_settle()
	if blade_down and sp > 0.05:
		_grade_acc += sp * delta
		if _grade_acc >= 0.4:
			_grade_acc = 0.0
			msg = _grade()
			_push_trees(fwd)
	return msg


## Real tracks: left/right belt commands from stick, body physics, grading as
## the blade moves forward through the ground.
func _drive_physics(delta: float, move: Vector2) -> String:
	var msg := ""
	var l := clampf(move.y + move.x * 0.7, -1.0, 1.0)
	var r := clampf(move.y - move.x * 0.7, -1.0, 1.0)
	# a loaded blade drags; a full one pushing a heap drags a lot
	body.drag = (4000.0 + load_m3 * 8000.0) if blade_down else 0.0
	body.step(delta, l, r)
	global_transform = body.transform()
	yaw = body.yaw()
	if engine != null:
		engine.drive_strain = engine.travel_strain(maxf(absf(l), absf(r)), body.top_speed, body.vel.length())
	if _track_l != null:
		_track_l.advance(body.belt_l * delta)
		_track_r.advance(body.belt_r * delta)
	var sp: float = body.vel.dot(-global_transform.basis.z)
	if blade_down and sp > 0.05:
		_grade_acc += sp * delta
		if _grade_acc >= 0.4:
			_grade_acc = 0.0
			msg = _grade()
			_push_trees(-global_transform.basis.z)
	if body.tilt_deg > 38.0 and not _tip_told:
		_tip_told = true
		msg = "She's going over! Ease off and back down."
	elif body.tilt_deg < 25.0:
		_tip_told = false
	return msg


## Anything wooden in front of the blade goes over.
func _push_trees(fwd: Vector3) -> void:
	if not on_tree.is_valid():
		return
	var right := global_transform.basis.x
	for lat in [-1.1, 0.0, 1.1]:
		var s: Vector3 = global_position + fwd * 2.7 + right * float(lat) + Vector3(0, 1.0, 0)
		var tr: Dictionary = Flora.tree_near(terrain, s)
		if not tr.is_empty():
			on_tree.call(tr, fwd * 5.0)


## One pass of the blade: level the disc ahead to the machine's own height.
## Overlapping passes as it rolls forward leave a smooth bench - a road.
func _grade() -> String:
	var msg := ""
	var base := global_position
	var fwd := -global_transform.basis.z
	# the blade works off the ground the tracks have come along, not the top
	# of whatever it's shoving
	var rear := base - fwd * 1.2
	var here: float = minf(terrain.height_at(base.x, base.z), terrain.height_at(rear.x, rear.z) + 0.1)
	var front := base + fwd * 2.4
	if not on_grade.is_valid():
		return ""
	# Grade toward a ramp from under the machine, never steeper than about
	# 8% - so a hillside becomes a climbing road cut, not a staircase.
	var h_nat: float = terrain.height_at(front.x, front.z)
	# loose spoil (a pile, above the original ground) shoves easily: a big
	# bite a pass; cutting native ground is slower
	var loose: bool = h_nat > terrain.natural_at(front.x, front.z) + 0.15
	# Into native ground the blade ramps (a climbing road cut, ~8%). A heap of
	# spoil it doesn't climb: the blade stays at track level and shoves it.
	var rise := clampf(h_nat - here, -0.2, 0.2)
	if loose and rise > 0.0:
		rise = 0.0
	# Never more than ~0.3 m under the tracks: the blade is 2.4 m ahead, so
	# that's a ramp she can drive down. Cutting deeper each step dug a cliff
	# she nosed into and flipped (2026-10-10).
	var target := here + clampf(rise + minf(_blade_goal, 0.15), -0.3, 0.2)
	# Loose material standing above the blade goes onto the blade whole: the
	# blade face is a wall, the dozer doesn't ride up over the heap.
	# At track level (or below) it carries what it cuts, dropping it only into
	# holes; a blade lifted a touch spreads its load out as a layer.
	var spreading := _blade_goal > 0.05
	var got: Dictionary = on_grade.call(front, BLADE_W * 0.55, target, load_m3, 9.0 if loose else 1.8, 3.0 if loose else 0.4, not spreading)
	if got.is_empty():
		return ""
	if OS.has_environment("DOZDEBUG"):
		print("  grade: here %.2f front %.2f target %.2f loose %s over %.2f pay %.2f filled %.2f load %.2f" % [here, h_nat, target, loose, float(got.get("over", 0.0)), float(got.get("pay", 0.0)), float(got.get("filled", 0.0)), load_m3])
	load_m3 = maxf(load_m3 + float(got.get("over", 0.0)) + float(got.get("pay", 0.0)) - float(got.get("filled", 0.0)), 0.0)
	# A full blade rolls its surplus out AHEAD, so the dirt travels with you
	# and gets pushed forward pass after pass; only a little dribbles off
	# the ends as windrow.
	if load_m3 > LOAD_MAX:
		var spill := load_m3 - LOAD_MAX * 0.85
		var right := global_transform.basis.x
		if on_spill.is_valid():
			on_spill.call(front + fwd * 1.7, spill * 0.7)
			on_spill.call(front + right * (BLADE_W * 0.5 + 0.9), spill * 0.15)
			on_spill.call(front - right * (BLADE_W * 0.5 + 0.9), spill * 0.15)
		load_m3 = LOAD_MAX * 0.85
		if not _full_told:
			_full_told = true
			msg = "Blade's full: it's rolling the spoil ahead of you."
	elif load_m3 < LOAD_MAX * 0.4:
		_full_told = false
	# A warning the first time the blade bites into the good ground.
	if float(got.get("pay", 0.0)) > 0.04 and not _pay_told:
		_pay_told = true
		msg = "You're cutting into the pay layer: gold is going into the spoil. Strip the top with the dozer, dig the pay with the excavator."
	return msg


var _demo_t := 0.0
var hyd: RefCounted
var _joints: Array = []
var _pump_label: Label3D
var _lift_rams: Array = []


## The hydraulics (Dave): 150 L/min at 1900 rpm, 210 bar relief; two 100 mm
## lift rams (as one 140).
func _hyd_setup() -> void:
	var HS = ResourceLoader.load("res://scripts/hyd_system.gd", "", ResourceLoader.CACHE_MODE_REPLACE)
	hyd = HS.new()
	hyd.displacement = 0.079
	hyd.rpm = 1900.0
	hyd.relief = 210.0
	var rl = hyd.add_ram("BLADE LIFT", 140.0, 70.0)
	var r0: Node3D = _lift_rams[0]
	_joints = [{"ram": rl, "get": func(): return blade_h, "set": func(v): blade_h = v,
		"length": func(): var e: Array = r0._ends(); return (e[0] as Vector3).distance_to(e[1] as Vector3),
		"lo": BLADE_LOW, "hi": BLADE_HIGH, "label": HS.make_label(self), "at": func(): return r0.mid_global() + Vector3(0, 0.7, 0)}]
	# the ripper's two cylinders (as one), lifting the beam on its links
	var rr = hyd.add_ram("RIPPER", 2.0 * 90.0, 2.0 * 55.0)
	var q0: Node3D = _rip_rams[0]
	for lv in _lift_rams:
		lv.sim_ram = rl
	for rv in _rip_rams:
		rv.sim_ram = rr
	_joints.append({"ram": rr, "get": func(): return rip, "set": func(v): rip = v,
		"length": func(): var e2: Array = q0._ends(); return (e2[0] as Vector3).distance_to(e2[1] as Vector3),
		"lo": RIP_DOWN, "hi": RIP_UP, "label": HS.make_label(self), "at": func(): return q0.mid_global() + Vector3(0, 0.6, 0)})
	_pump_label = HS.make_label(self)
	_pump_label.position = Vector3(0, 3.8, 1.0)


## The blade on its C-frame swings about the trunnions on the track frames, as
## the real one does (it used to slide straight up, pulling the push arms off
## their trunnions): the height wanted at the edge sets the swing.
const LIFT_X := 0.63                            # the lift rams' line, between the hood side and the tracks
const LIFT_TOP := Vector3(0.63, 1.8, -0.4)      # barrel trunnion on the hood side
const LIFT_EAR := Vector3(0.63, 0.27, -1.72)    # rod eye on the blade's back (blade frame)
const TRUNNION := Vector3(0, -0.10, 0.25)       # in the blade's own frame (low on the track frames)
const ARM_LEN := 2.2                            # trunnion to cutting edge


func _blade_swing() -> void:
	var dh := (0.02 + blade_h) - 0.55
	var th := asin(clampf(dh / ARM_LEN, -0.9, 0.9))
	var r := Basis(Vector3.RIGHT, th)
	_blade.transform = Transform3D(r, Vector3(0, 0.55, 0) + TRUNNION - r * TRUNNION)


func _blade_pose() -> void:
	_blade_pos = clampf(1.0 - blade_h / BLADE_CARRY, 0.0, 1.0)
	_blade_swing()


## The blade's weight x height (2.2 t) and what it's pushing up.
func _potential() -> float:
	var u := 9.81 * (2200.0 + load_m3 * 1800.0) * (_blade.global_transform * Vector3(0, 0.5, -1.9)).y
	if _ripper != null:
		u += 9.81 * 1100.0 * _ripper.global_position.y          # the ripper beam and shanks, 1.1 t
	return u


func damage_line() -> String:
	if hyd == null:
		_hyd_setup()
	return EK.damage_line(self)


func repair_lines() -> String:
	return EK.repair_lines(self)


func _pose_all() -> void:
	_blade_pose()
	_rip_pose()


func _process(delta: float) -> void:
	if EK.in_lab(self):                # in the lab: works the blade lever; the hydraulics move it
		_demo_t += delta
		if hyd == null:
			_hyd_setup()
		if engine.state == "off" and _demo_t < 1.0:
			engine.ambient = -12.0
			engine.temp = -12.0
			engine.start()
		hyd.rpm = engine.rpm
		hyd.rams[0].spool = sin(_demo_t * 0.5) if engine.state == "running" and fmod(_demo_t, 14.0) < 9.0 else 0.0   # work, then hands off: auto-idle
		engine.load = clampf(hyd.pressure / hyd.relief, 0.0, 1.0)
		engine.strain = hyd.strain()          # revs only when the oil can't move the load
		engine.hyd_power_max = 70000.0
		hyd.power_avail = engine.hyd_power()      # the pump gets only what the engine can give at these revs
		# the operator opens the throttle while working the levers (Dave: throttle up to lift), back to idle when hands off
		var lever := 0.0
		for r_ in hyd.rams:
			lever = maxf(lever, absf(r_.spool))
		engine.throttle = move_toward(engine.throttle, 0.85 if lever > 0.25 else 0.0, (0.8 if lever > 0.25 else 0.5) * delta)
		engine.drive_strain = 0.0
		if hyd.rams.size() > 1:
			hyd.rams[1].spool = sin(_demo_t * 0.35 + 2.0) if engine.state == "running" and fmod(_demo_t, 14.0) < 9.0 else 0.0
		hyd.drive(delta, _joints, _potential, _pose_all)
		_pump_label.text = hyd.summary() + "\nENGINE " + engine.status()
		_blade_goal = blade_h
	blade_h = move_toward(blade_h, _blade_goal, delta * 1.2)
	_blade_pos = clampf(1.0 - blade_h / BLADE_CARRY, 0.0, 1.0)
	_blade_swing()
	_dirt.visible = load_m3 > 0.15
	if _dirt.visible:
		_dirt.scale = Vector3(1, clampf(load_m3 / LOAD_MAX, 0.25, 1.0), 1)


## Where a winch hook or tow strap can go: [[name, world point], ...].
func winch_points() -> Array:
	return TowPoints.world(self, WINCH_POINTS)
