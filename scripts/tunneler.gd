extends Node3D
## The drift miner (DESIGN_NOTES 148): a compact boom-type tunnelling machine
## - a roadheader - for driving drifts through frozen gravel and rock far
## faster than a shovel and pick. Modelled on the small cantilever
## roadheaders used in mines and tunnels (and the kind of machine used to
## cut the permafrost research tunnel north of Fairbanks): a low tracked
## chassis; a boom on a slewing turret at the front with a spinning cutter
## head studded with picks; a sloping gathering apron under it with two
## spinning gathering arms that rake the cut muck onto a chain conveyor
## running back down the middle; the operator's seat under a steel canopy
## on the left; lights for underground; and here a muck tub on the tail the
## conveyor fills.
##
## Working it: drive up to a bank or a drift face, start the cutter (E)
## and drive into it. The boom sweeps the face - side to side, top to
## bottom - and cuts a square heading 3.0 m wide and 2.7 m high, about
## 0.3 m a bite: a couple of metres a minute through frozen gravel, a third
## of that in rock. Raise / lower the boom (the throttle keys, Shift / Ctrl) to drive the heading up
## or down a grade (a decline into the ground from the surface, a raise up
## into the pay). Barren muck goes back down the
## conveyor as gob (stowed behind, the old drift miners' way); PAY gravel
## goes into the tub, up to 3 m3 - drive out and dump it (E with the cutter
## off) in the wash plant's hopper or on a stockpile. Unsupported gravel
## roofs still need timber sets in time (the roof checks go on every 1.7 m).

const MeshKit = preload("res://scripts/meshkit.gd")
const TrackLoop = preload("res://scripts/track_loop.gd")
const TrackedBody = preload("res://scripts/tracked_body.gd")

const BODY := Color(0.86, 0.52, 0.10)      # mine orange
const DARK := Color(0.12, 0.12, 0.12)
const STEEL := Color(0.42, 0.42, 0.44)
const BRIGHT := Color(0.70, 0.70, 0.72)
const CUT_W := 3.0
const CUT_H := 2.7
const BITE := 0.3                 # metres cut ahead per bite
const RATE_SOFT := 0.45           # m/s of face advance cutting gravel, dirt, frozen muck
const RATE_ROCK := 0.15           # through bedrock
const TUB_M3 := 3.0
const FRONT := 2.9                # chassis front (apron lip) ahead of the origin
const REACH := 0.55               # the cutter cuts this far ahead of the apron lip
const TRAM_SPEED := 1.3           # m/s on the move
const CUT_SPEED := 0.5            # m/s at most while cutting

var terrain: RefCounted
var vox: Node                     # voxel_ground.gd (tunnels), or null
var prospect: Node                # for geology, roofs, dumping, strip/building checks
var yaw := 0.0
var driven := false
var engine_on := true
var home := Transform3D.IDENTITY
var body: RefCounted
var cutter_on := false
var grade := 0.0                  # rise per metre of the heading being cut
var tub := {}                     # {pay, g}
var speed := 0.0                  # m/s along the tracks (machine_sound reads it)
var _bite := 0.0                  # metres of face cut ahead of the lip not yet driven into
var _acc := 0.0                   # cutting progress toward the next bite
var _roof_d := 0.0
var _resist := 0.0
var _t := 0.0
var _msg_t := 0.0
var _tracks: Node3D
var _track_l: Node3D
var _track_r: Node3D
var _turret: Node3D
var _boom: Node3D
var _head: Node3D
var _stars: Array = []
var _dust: CPUParticles3D
var _lights: Array = []
var _muck: MeshInstance3D


# ==============================================================================
#  The model
# ==============================================================================
func build() -> void:
	# The model (DESIGN_NOTES 148), after the small cantilever roadheaders:
	# 7.6 m long, 2.0 m wide, 1.6 m to the top of the housings.
	var k := MeshKit.new()
	var orange := BODY
	var od := BODY.darkened(0.18)
	# --- the crawlers: track frames, sprocket, idler, rollers, guards -------------
	var zc := 1.55
	for sx in [-0.85, 0.85]:
		var sg := signf(sx)
		k.box_at(Vector3(sx, 0.42, 0.0), Vector3(0.3, 0.34, 2.9), od)
		k.box(Transform3D(Basis(Vector3.RIGHT, 0.55), Vector3(sx, 0.4, -1.42)), Vector3(0.28, 0.24, 0.36), od)
		k.box(Transform3D(Basis(Vector3.RIGHT, -0.55), Vector3(sx, 0.4, 1.42)), Vector3(0.28, 0.24, 0.36), od)
		k.box_at(Vector3(sx + sg * 0.17, 0.3, 0.0), Vector3(0.025, 0.2, 2.7), od.darkened(0.15))       # guard plate
		k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.17, 0.33, -zc)), 0.29, 0.29, 0.34, 16, STEEL.darkened(0.15))   # idler
		k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.18, 0.33, zc)), 0.31, 0.31, 0.36, 16, STEEL.darkened(0.3))     # sprocket
		for tooth in range(12):
			var ta := TAU * float(tooth) / 12.0
			k.box_at(Vector3(sx, 0.33 + sin(ta) * 0.33, zc + cos(ta) * 0.33), Vector3(0.12, 0.07, 0.07), STEEL.darkened(0.45))
		k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx - sg * 0.2 + 0.12, 0.33, zc)), 0.2, 0.2, 0.24, 12, DARK)   # travel gearbox
		for rz in [-1.0, -0.6, -0.2, 0.2, 0.6, 1.0]:
			k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.15, 0.14, rz)), 0.11, 0.11, 0.3, 10, STEEL)
		for cz in [-0.6, 0.6]:
			k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.1, 0.63, cz)), 0.07, 0.07, 0.2, 8, STEEL)
	# --- the frame between the crawlers, the housings either side of the conveyor --
	k.box_at(Vector3(0, 0.64, 0.2), Vector3(1.5, 0.16, 3.3), DARK)
	# left housing: the electrical control box (flameproof, bolted lid) up front
	_housing(k, Vector3(-0.66, 0.72, -0.95), Vector3(0.58, 0.62, 0.9), orange, 0.06)
	k.box_at(Vector3(-0.955, 1.03, -0.95), Vector3(0.02, 0.44, 0.7), od)
	for bz in range(6):
		for by in [0.8, 1.28]:
			k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.97, by, -1.25 + 0.12 * float(bz))), 0.016, 0.016, 0.02, 6, STEEL)
	k.box_at(Vector3(-0.66, 1.36, -0.95), Vector3(0.3, 0.04, 0.3), STEEL.darkened(0.2))
	# right housing: the hydraulic tank up front (filler, sight glass)
	_housing(k, Vector3(0.66, 0.72, -0.85), Vector3(0.58, 0.78, 1.1), orange, 0.07)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.7, 1.5, -1.05)), 0.07, 0.07, 0.08, 10, DARK)
	k.box_at(Vector3(0.955, 1.1, -0.85), Vector3(0.02, 0.3, 0.05), Color(0.6, 0.55, 0.2))
	# right rear: the electric motor driving the pump pack, its cooler on top
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.62, 1.08, 0.25)), 0.3, 0.3, 1.0, 18, od)
	for fin in range(12):
		k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.62, 1.08, 0.3 + 0.08 * float(fin))), 0.33, 0.33, 0.025, 18, od.darkened(0.1))
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.62, 1.08, -0.05)), 0.26, 0.2, 0.3, 14, STEEL)    # pump bell
	_housing(k, Vector3(0.66, 0.72, 1.6), Vector3(0.58, 0.85, 0.7), orange, 0.06)                         # oil cooler
	for gy in range(6):
		k.box_at(Vector3(0.66, 0.85 + 0.1 * float(gy), 1.96), Vector3(0.48, 0.03, 0.02), DARK)
	for hz in [-0.15, 0.0, 0.15]:
		_pipe(k, Vector3(0.45, 1.25 + hz * 0.3, -0.35), Vector3(0.25, 1.15, -1.35), 0.025, Color(0.07, 0.07, 0.07))   # hoses to the boom
	# --- the chain conveyor down the middle and out over the tail ----------------
	var cpts := [Vector3(0, 0.36, -2.25), Vector3(0, 0.86, -1.1), Vector3(0, 0.98, 2.0), Vector3(0, 1.95, 3.6)]
	for i in range(cpts.size() - 1):
		var c0: Vector3 = cpts[i]
		var c1: Vector3 = cpts[i + 1]
		var cd := c1 - c0
		var cb := Basis(Vector3.RIGHT, atan2(cd.y, -cd.z))
		var mid := (c0 + c1) * 0.5
		var ln := cd.length()
		k.box(Transform3D(cb, mid), Vector3(0.64, 0.05, ln), STEEL.darkened(0.25))                    # trough floor
		for sx2 in [-0.34, 0.34]:
			k.box(Transform3D(cb, mid + Vector3(sx2, 0.0, 0.0) + cb.y * 0.12), Vector3(0.04, 0.26, ln), od)  # side boards
		var nfl := int(ln / 0.28)
		for f in range(nfl):
			var fp: Vector3 = c0.lerp(c1, (float(f) + 0.5) / float(nfl))
			k.box(Transform3D(cb, fp + cb.y * 0.05), Vector3(0.56, 0.035, 0.05), BRIGHT.darkened(0.3))    # flight bars
		for sx3 in [-0.24, 0.24]:
			_pipe(k, c0 + Vector3(sx3, 0.07, 0), c1 + Vector3(sx3, 0.07, 0), 0.02, STEEL.darkened(0.4))    # the chains
	# tail: the rear conveyor on its frame, the drive sprocket, the discharge chute
	for sx4 in [-0.3, 0.3]:
		_pipe(k, Vector3(sx4, 0.72, 2.0), Vector3(sx4, 1.75, 3.35), 0.05, od)
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.38, 1.95, 3.6)), 0.14, 0.14, 0.76, 12, DARK)
	k.box(Transform3D(Basis(Vector3.RIGHT, 0.7), Vector3(0, 1.75, 3.82)), Vector3(0.6, 0.04, 0.45), STEEL.darkened(0.2))
	# --- operator's station, left middle: seat, console, levers, canopy ----------
	var op := Vector3(-0.62, 1.07, 0.55)
	_housing(k, Vector3(-0.66, 0.72, 0.55), Vector3(0.6, 0.35, 1.6), od, 0.04)           # the deck he sits on
	k.box_at(op + Vector3(0, 0.26, 0.15), Vector3(0.48, 0.1, 0.48), Color(0.14, 0.14, 0.15))
	k.box(Transform3D(Basis(Vector3.RIGHT, -0.15), op + Vector3(0, 0.62, 0.42)), Vector3(0.48, 0.6, 0.1), Color(0.14, 0.14, 0.15))
	k.box_at(op + Vector3(0, 0.62, -0.45), Vector3(0.6, 0.55, 0.32), DARK)               # console
	k.box(Transform3D(Basis(Vector3.RIGHT, 0.5), op + Vector3(0, 0.93, -0.38)), Vector3(0.56, 0.02, 0.22), Color(0.08, 0.1, 0.09))   # gauge panel
	for gi in range(4):
		k.cylinder(Transform3D(Basis(Vector3.RIGHT, -1.07), op + Vector3(-0.2 + 0.13 * float(gi), 0.95, -0.37)), 0.04, 0.04, 0.012, 10, Color(0.85, 0.85, 0.8))
	for lv in range(5):
		var lx := -0.22 + 0.11 * float(lv)
		_pipe(k, op + Vector3(lx, 0.88, -0.28), op + Vector3(lx, 1.06, -0.2), 0.012, BRIGHT)
		k.box_at(op + Vector3(lx, 1.08, -0.2), Vector3(0.035, 0.05, 0.035), [Color(0.8, 0.1, 0.1), DARK, DARK, DARK, Color(0.9, 0.75, 0.1)][lv])
	for px in [-0.32, 0.32]:
		for pz in [-0.68, 0.62]:
			k.box_at(op + Vector3(px, 0.82, pz), Vector3(0.07, 1.64, 0.07), od.darkened(0.1))
	k.box_at(op + Vector3(0, 1.66, -0.03), Vector3(0.82, 0.07, 1.42), od)                 # canopy: steel plate
	for mz in range(5):
		k.box_at(op + Vector3(0, 1.61, -0.6 + 0.29 * float(mz)), Vector3(0.78, 0.05, 0.05), DARK)
	for lx in [-0.24, 0.24]:
		k.box_at(op + Vector3(lx, 1.58, -0.74), Vector3(0.15, 0.13, 0.1), DARK)
		k.box_at(op + Vector3(lx, 1.58, -0.795), Vector3(0.11, 0.09, 0.01), Color(0.95, 0.92, 0.75))
	# the cable reel at the back left, its cable trailing off
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.32, 1.25, 1.75)), 0.42, 0.42, 0.62, 18, DARK)
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.3, 1.25, 1.75)), 0.3, 0.3, 0.6, 18, Color(0.15, 0.13, 0.08))
	for sxr in [-0.95, -0.33]:
		k.box_at(Vector3(sxr, 0.95, 1.75), Vector3(0.05, 0.6, 0.1), od)
	_pipe(k, Vector3(-0.6, 0.85, 1.75), Vector3(-0.7, 0.05, 3.2), 0.035, Color(0.12, 0.10, 0.06))
	for lx2 in [-0.7, 0.7]:
		k.box_at(Vector3(lx2, 0.95, 2.08), Vector3(0.12, 0.08, 0.02), Color(0.8, 0.1, 0.06))   # tail lamps
	# --- the muck tub, hung under the end of the tail conveyor ------------------
	var tz := 3.75
	var tub_c := od
	k.box_at(Vector3(0, 0.62, tz - 0.9), Vector3(0.24, 0.12, 0.6), DARK)                   # the tow tongue
	k.box_at(Vector3(0, 0.62, tz), Vector3(1.5, 0.08, 1.1), tub_c.darkened(0.2))
	for sx5 in [-0.72, 0.72]:
		k.box(Transform3D(Basis(Vector3.FORWARD, sign(sx5) * 0.18), Vector3(sx5 * 1.05, 1.0, tz)), Vector3(0.06, 0.8, 1.1), tub_c)
		k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx5 + signf(sx5) * 0.05 + 0.05, 0.22, tz)), 0.22, 0.22, 0.12, 12, STEEL.darkened(0.3))
	k.box_at(Vector3(0, 1.0, tz + 0.55), Vector3(1.66, 0.8, 0.06), tub_c)
	k.box_at(Vector3(0, 1.0, tz - 0.55), Vector3(1.66, 0.8, 0.06), tub_c)
	k.box_at(Vector3(0, 1.42, tz), Vector3(1.85, 0.05, 1.18), STEEL.darkened(0.2))
	# --- the turret the boom slews on, and the slew rams -------------------------
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.95, -1.55)), 0.66, 0.64, 0.24, 20, DARK)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 1.17, -1.55)), 0.6, 0.55, 0.2, 20, od)
	for sx6 in [-1.0, 1.0]:
		_pipe(k, Vector3(sx6 * 0.36, 1.12, -0.7), Vector3(sx6 * 0.48, 1.18, -1.35), 0.07, od.darkened(0.1))
		_pipe(k, Vector3(sx6 * 0.48, 1.18, -1.35), Vector3(sx6 * 0.5, 1.2, -1.55), 0.04, BRIGHT)
	# --- the shovel plate (gathering apron): a wedge, flared side walls -----------
	var lip := -2.9
	k.quad(Vector3(-1.4, 0.08, lip), Vector3(1.4, 0.08, lip), Vector3(1.0, 0.46, -2.05), Vector3(-1.0, 0.46, -2.05), od, Vector3(0, 1, -0.4))
	k.quad(Vector3(1.4, 0.04, lip), Vector3(-1.4, 0.04, lip), Vector3(-1.0, 0.36, -2.05), Vector3(1.0, 0.36, -2.05), DARK, Vector3(0, -1, 0.4))
	k.box_at(Vector3(0, 0.08, lip - 0.03), Vector3(2.85, 0.05, 0.08), STEEL.darkened(0.3))           # wear edge
	for sx7 in [-1.0, 1.0]:
		var e0 := Vector3(sx7 * 1.4, 0.08, lip)
		var e1 := Vector3(sx7 * 1.0, 0.46, -2.05)
		k.quad(e0, e1, e1 + Vector3(0, 0.3, 0), e0 + Vector3(0, 0.22, 0), od.darkened(0.1), Vector3(sx7, 0, 0))
		k.quad(e0, e0 + Vector3(0, 0.22, 0), e1 + Vector3(0, 0.3, 0), e1, od.darkened(0.25), Vector3(-sx7, 0, 0))
		_pipe(k, Vector3(sx7 * 0.6, 0.35, -1.0), Vector3(sx7 * 0.75, 0.32, -2.1), 0.065, od.darkened(0.1))   # apron rams
		_pipe(k, Vector3(sx7 * 0.75, 0.32, -2.1), Vector3(sx7 * 0.78, 0.3, -2.35), 0.04, BRIGHT)
	add_child(k.instance("Chassis"))
	# the muck in the tub, shown as it fills
	var mk := MeshKit.new()
	mk.box_at(Vector3(0, 0.0, 0), Vector3(1.4, 0.1, 1.0), Color(0.36, 0.30, 0.22))
	for i in range(7):
		mk.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.55 + 0.18 * float(i), 0.05, -0.25 + 0.1 * float(i % 3))), 0.3, 0.0, 0.25, 7, Color(0.40, 0.34, 0.25).darkened(0.1 * float(i % 3)), false)
	_muck = mk.instance("Muck")
	_muck.position = Vector3(0, 0.7, tz)
	_muck.visible = false
	add_child(_muck)
	# tracks
	_tracks = Node3D.new()
	add_child(_tracks)
	_track_l = TrackLoop.new()
	_track_l.setup(-0.85, zc, 0.04, 0.66, 74, Vector3(0.46, 0.04, 0.11), Color(0.18, 0.18, 0.18))
	_tracks.add_child(_track_l)
	_track_r = TrackLoop.new()
	_track_r.setup(0.85, zc, 0.04, 0.66, 74, Vector3(0.46, 0.04, 0.11), Color(0.18, 0.18, 0.18))
	_tracks.add_child(_track_r)
	# gathering star wheels: four curved arms each, turning in opposite ways
	for sx8 in [-0.62, 0.62]:
		var st := Node3D.new()
		st.position = Vector3(sx8, 0.38, -2.45)
		st.rotation = Vector3(0.38, 0, 0)
		var sk := MeshKit.new()
		sk.cylinder(Transform3D.IDENTITY, 0.2, 0.2, 0.12, 14, STEEL)
		sk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0)), 0.1, 0.06, 0.06, 10, DARK)
		for a in range(4):
			var ang := TAU * float(a) / 4.0
			# each arm curves back: three short segments swept round
			var prev := Vector3(cos(ang) * 0.16, 0.07, -sin(ang) * 0.16)
			for seg in range(3):
				var aa := ang + 0.32 * float(seg + 1) * signf(sx8)
				var rr := 0.16 + 0.15 * float(seg + 1)
				var nxt := Vector3(cos(aa) * rr, 0.07, -sin(aa) * rr)
				var dd := nxt - prev
				sk.box(Transform3D(Basis(Vector3.UP, atan2(-dd.z, dd.x)), (prev + nxt) * 0.5), Vector3(dd.length() + 0.03, 0.09, 0.08), od.darkened(0.2))
				prev = nxt
		st.add_child(sk.instance("Star"))
		add_child(st)
		_stars.append(st)
	# --- the boom: slews on the turret, lifts at its pivot; telescopic; twin rams ----
	_turret = Node3D.new()
	_turret.position = Vector3(0, 1.37, -1.55)
	add_child(_turret)
	_boom = Node3D.new()
	_turret.add_child(_boom)
	var bk := MeshKit.new()
	_housing(bk, Vector3(0, -0.32, 0.35), Vector3(0.9, 0.6, 0.7), BODY.darkened(0.1), 0.08)        # the pivot block
	for sxp in [-0.48, 0.48]:
		bk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sxp + 0.06, 0.0, 0.2)), 0.12, 0.12, 0.12, 12, STEEL)
	_housing(bk, Vector3(0, -0.32, -0.75), Vector3(0.62, 0.62, 1.55), BODY, 0.08)                  # outer boom
	_housing(bk, Vector3(0, -0.27, -1.85), Vector3(0.5, 0.52, 0.75), BODY.darkened(0.06), 0.06)   # inner (telescoping) boom
	bk.box_at(Vector3(0, -0.02, -1.5), Vector3(0.52, 0.04, 0.06), DARK)                             # the joint
	_housing(bk, Vector3(0, -0.37, -2.45), Vector3(0.7, 0.72, 0.45), BODY.darkened(0.2), 0.1)      # cutter gearbox
	for sx9 in [-1.0, 1.0]:
		# lift rams: barrel off the turret below, rod up into the boom's belly
		_pipe(bk, Vector3(sx9 * 0.42, -0.7, 0.25), Vector3(sx9 * 0.36, -0.5, -0.65), 0.085, BODY.darkened(0.15))
		_pipe(bk, Vector3(sx9 * 0.36, -0.5, -0.65), Vector3(sx9 * 0.33, -0.38, -1.05), 0.05, BRIGHT)
		bk.box_at(Vector3(sx9 * 0.33, -0.36, -1.05), Vector3(0.1, 0.12, 0.14), DARK)
		# telescope ram along the side
		_pipe(bk, Vector3(sx9 * 0.34, -0.18, -0.6), Vector3(sx9 * 0.3, -0.18, -1.4), 0.045, BODY.darkened(0.15))
		_pipe(bk, Vector3(sx9 * 0.3, -0.18, -1.4), Vector3(sx9 * 0.28, -0.18, -2.05), 0.028, BRIGHT)
	for hx in [-0.1, 0.0, 0.1]:
		_pipe(bk, Vector3(hx, 0.02, 0.3), Vector3(hx, 0.0, -2.2), 0.018, Color(0.07, 0.07, 0.07))      # hoses and the water line
	_boom.add_child(bk.instance("Boom"))
	_head = Node3D.new()
	_head.position = Vector3(0, -0.37, -2.7)
	_boom.add_child(_head)
	var hk := MeshKit.new()
	# the cutter head: a tapered drum, three spiral rows of picks in holders,
	# a water spray ring behind
	var hb := Basis(Vector3.RIGHT, -PI * 0.5)
	hk.cylinder(Transform3D(hb, Vector3.ZERO), 0.44, 0.3, 0.8, 20, STEEL.darkened(0.2))
	hk.cylinder(Transform3D(hb, Vector3(0, 0, -0.8)), 0.3, 0.12, 0.18, 20, STEEL.darkened(0.2))
	hk.cylinder(Transform3D(hb, Vector3(0, 0, 0.06)), 0.47, 0.47, 0.06, 20, DARK)
	for nz in range(10):
		var na := TAU * float(nz) / 10.0
		hk.box_at(Vector3(cos(na) * 0.47, sin(na) * 0.47, 0.1), Vector3(0.04, 0.04, 0.06), BRIGHT)
	for start in range(3):
		for i in range(18):
			var t := float(i) / 18.0
			var ang2 := t * TAU * 1.6 + TAU * float(start) / 3.0
			var r := lerpf(0.45, 0.24, t)
			var z := -t * 0.92 - 0.02
			var outv := Vector3(cos(ang2), sin(ang2), 0)
			var tang := Vector3(-sin(ang2), cos(ang2), 0)
			var pb := Basis(tang, outv, tang.cross(outv))
			hk.box(Transform3D(pb, outv * (r + 0.03) + Vector3(0, 0, z)), Vector3(0.06, 0.07, 0.06), STEEL.darkened(0.45))     # holder
			var pick := Basis(tang, (outv + Vector3(0, 0, -0.45)).normalized(), tang.cross((outv + Vector3(0, 0, -0.45)).normalized()))
			hk.cylinder(Transform3D(pick, outv * (r + 0.06) + Vector3(0, 0, z)), 0.028, 0.004, 0.11, 6, Color(0.62, 0.62, 0.65))
	_head.add_child(hk.instance("Head"))
	# dust where the head bites, the lights
	_dust = CPUParticles3D.new()
	var dm := QuadMesh.new()
	dm.size = Vector2(0.6, 0.6)
	var dmat := StandardMaterial3D.new()
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dmat.vertex_color_use_as_albedo = true
	dmat.albedo_texture = load("res://scripts/fx.gd").puff_texture()
	dm.material = dmat
	_dust.mesh = dm
	_dust.amount = 40
	_dust.lifetime = 2.5
	_dust.local_coords = false
	_dust.emitting = false
	_dust.direction = Vector3(0, 0.5, 1)
	_dust.spread = 60.0
	_dust.initial_velocity_min = 0.3
	_dust.initial_velocity_max = 1.0
	_dust.gravity = Vector3(0, -0.2, 0)
	_dust.color = Color(0.55, 0.48, 0.38, 0.35)
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.5))
	cv.add_point(Vector2(1, 3.0))
	_dust.scale_amount_curve = cv
	_head.add_child(_dust)
	for lx3 in [-0.25, 0.25]:
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.95, 0.82)
		sl.light_energy = 3.0
		sl.spot_range = 28.0
		sl.spot_angle = 38.0
		sl.shadow_enabled = lx3 < 0.0
		sl.position = op + Vector3(lx3, 1.58, -0.82)
		sl.rotation = Vector3(-0.12, 0, 0)
		sl.visible = false
		add_child(sl)
		_lights.append(sl)


## A housing: a box with its edges chamfered by `c` (base-centred at p).
static func _housing(kit: RefCounted, p: Vector3, sz: Vector3, col: Color, c: float) -> void:
	var hw := sz.x * 0.5
	var y0 := p.y
	var y1 := p.y + sz.y
	var rings: Array = []
	for z in [p.z - sz.z * 0.5, p.z + sz.z * 0.5]:
		var ring := PackedVector3Array()
		for q in [Vector2(-hw + c, y1), Vector2(hw - c, y1), Vector2(hw, y1 - c), Vector2(hw, y0 + c * 0.5), Vector2(hw - c * 0.5, y0), Vector2(-hw + c * 0.5, y0), Vector2(-hw, y0 + c * 0.5), Vector2(-hw, y1 - c)]:
			ring.append(Vector3(p.x + q.x, q.y, z))
		rings.append(ring)
	kit.loft(rings, col, true, true)


static func _pipe(kit: RefCounted, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	kit.cylinder(Transform3D(Basis(x, y, x.cross(y)), a), r, r, d.length(), 6, col, true)


# ==============================================================================
#  Driving
# ==============================================================================
func park(xf: Transform3D) -> void:
	home = xf
	var f := -xf.basis.z
	yaw = atan2(-f.x, -f.z)
	global_position = xf.origin
	_place(xf.origin)


## Sit on the floor under the track ends, pitched and rolled to it.
func _place(p: Vector3) -> void:
	var b := Basis(Vector3.UP, yaw)
	var pts := [Vector3(-0.78, 0, -1.4), Vector3(0.78, 0, -1.4), Vector3(-0.78, 0, 1.4), Vector3(0.78, 0, 1.4)]
	var hs: Array = []
	for q in pts:
		var w: Vector3 = p + b * (q as Vector3)
		hs.append(_floor(w.x, w.z))
	var front := (float(hs[0]) + float(hs[1])) * 0.5
	var back := (float(hs[2]) + float(hs[3])) * 0.5
	var left := (float(hs[0]) + float(hs[2])) * 0.5
	var right := (float(hs[1]) + float(hs[3])) * 0.5
	var pitch := atan2(front - back, 2.8)
	var roll := atan2(left - right, 1.56)
	var y := (front + back) * 0.5
	global_transform = Transform3D(b * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, roll), Vector3(p.x, y, p.z))


## The floor under the tracks: the drift floor in a tunnel, the ground outside.
func _floor(x: float, z: float) -> float:
	var g: float = terrain.wheel_ground(x, z) if terrain.has_method("wheel_ground") else terrain.height_at(x, z)
	if vox != null and vox.ready_at(Vector3(x, global_position.y, z)):
		var f: float = vox.floor_below(Vector3(x, global_position.y + 0.6, z), 6.0)
		if f != -INF and f < g - 0.3:
			return f
	return g


func _blocked(p: Vector3) -> bool:
	if terrain.blocked_by_building(p, 1.0, self):
		return true
	if vox == null:
		return false
	var y0 := global_position.y
	for h in [1.0, 1.8]:
		var q := Vector3(p.x, y0 + h, p.z)
		if vox.ready_at(q) and vox.sdf_at(q) < -0.1:
			return true
	return false


func eye_xf() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(-0.62, 2.42, 0.62))


func step_out_point() -> Vector3:
	return global_transform * Vector3(-1.6, 0, 0.6)


func cab_yaw() -> float:
	return yaw


## Drive the tracks; `lift_in` (the throttle keys, Shift / Ctrl) raises or lowers
## the boom: the grade the heading is cut to.
func drive(delta: float, move: Vector2, lift_in: float = 0.0) -> String:
	var msg := ""
	grade = clampf(grade + lift_in * 0.15 * delta, -0.3, 0.3)
	if absf(lift_in) > 0.05:
		msg = ""
	# Kinematic on its tracks: it creeps, it pivots, it sits on the drift
	# floor (or the ground) under its track ends, and a solid face or a wall
	# stops it dead. (A full physics body caught on every lip of the cut.)
	var want := move.y * (TRAM_SPEED if not cutter_on else CUT_SPEED)
	speed = move_toward(speed, want, 1.2 * delta)
	yaw -= move.x * 0.45 * delta * (1.0 if absf(speed) > 0.05 or absf(move.x) > 0.0 else 0.0)
	var fl := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var p := global_position + fl * speed * delta
	var probe := p + fl * signf(speed) * (FRONT if speed > 0.0 else 4.3)
	if absf(speed) > 0.001 and (_blocked(probe) or (speed > 0.0 and cutter_on and _bite < 0.02)):
		speed = 0.0
		p = global_position
	_place(p)
	_track_l.advance((speed + move.x * 0.4) * delta)
	_track_r.advance((speed - move.x * 0.4) * delta)
	# how far into the cut we drove this step
	var fwd := -global_transform.basis.z
	var adv := maxf(speed * delta, 0.0)
	_bite = maxf(_bite - adv, 0.0)
	_roof_d += adv
	if cutter_on:
		msg = _cut(delta)
	_animate(delta)
	return msg


## The cutter at work: sweep the face, a bite at a time ahead of the apron.
func _cut(delta: float) -> String:
	if vox == null and prospect != null:
		vox = prospect._vox()          # the voxel ground wasn't up yet when it was parked
	if not engine_on:
		cutter_on = false
		return ""
	if _bite > REACH + BITE:
		_resist = 0.15
		return ""                  # cut ahead already: drive up into it
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var lip := global_position + fwd * (FRONT + _bite)
	var face := lip + fwd * (BITE * 0.5)
	face.y = global_position.y + grade * (FRONT + _bite)
	var mid := face + Vector3(0, CUT_H * 0.5, 0)
	if prospect != null and prospect.strip_or_building(mid):
		cutter_on = false
		return "Not under the runway or the buildings."
	if not terrain.inside(mid.x, mid.z):
		cutter_on = false
		return "That's off the claim."
	# how much of the bite is ground (sampled through the box)
	var solid := 0
	var n := 0
	var side := Vector3(-fwd.z, 0, fwd.x)
	for sx in [-0.4, 0.0, 0.4]:
		for sy in [0.2, 0.5, 0.85]:
			var q: Vector3 = face + side * float(sx) * CUT_W + Vector3(0, float(sy) * CUT_H, 0)
			n += 1
			if vox != null and vox.ready_at(q):
				if vox.sdf_at(q) < 0.0:
					solid += 1
			elif q.y < terrain.height_at(q.x, q.z):
				solid += 1
	var frac := float(solid) / float(n)
	var layer: String = prospect.layer_at3(mid) if prospect != null else "over"
	var rate := RATE_ROCK if layer == "rock" else RATE_SOFT
	if frac < 0.05:
		# nothing there: the cut is open air - just move the face on
		_acc = 0.0
		_bite += BITE
		_resist = 0.0
		if grade > -0.04 and _msg_t <= 0.0:
			_msg_t = 8.0
			return "Nothing ahead to cut. Lower the boom (%s) to cut down into the ground, or drive up to a bank or a drift face." % Game.lever_hint(false)
		return ""
	if layer == "pay" and float(tub.get("pay", 0.0)) >= TUB_M3 - 0.01:
		_resist = 0.0
		if _msg_t <= 0.0:
			_msg_t = 6.0
			return "The tub's full of pay. Stop the cutter, back out and dump it (E) in the wash plant's hopper or on a pile."
		return ""
	_resist = clampf(0.4 + frac * 0.6, 0.0, 1.0) * (1.3 if layer == "rock" else 1.0)
	_acc += rate * delta
	if _acc < BITE:
		return ""
	_acc -= BITE
	var by := atan2(-fwd.x, -fwd.z)
	if vox != null:
		vox.cut_box(face - fwd * 0.15, by, CUT_W, CUT_H, BITE + 0.3)
	_bite += BITE
	var vol := CUT_W * CUT_H * BITE * frac
	if layer == "pay" and prospect != null:
		var g: Array = prospect.geology(mid.x, mid.z)
		var room := TUB_M3 - float(tub.get("pay", 0.0))
		var put := minf(vol, room)
		tub["pay"] = float(tub.get("pay", 0.0)) + put
		tub["g"] = float(tub.get("g", 0.0)) + float(g[0]) * put
	if prospect != null:
		prospect._dirty = true
		# unsupported roof over gravel: the roof checks run on as for a hand drift
		if layer != "rock" and _roof_d > 1.7:
			_roof_d = 0.0
			var roof := mid + Vector3(0, CUT_H * 0.5, 0)
			if terrain.height_at(roof.x, roof.z) - roof.y > 0.5:
				prospect.roofs.append([roof, 0.0, 0])
	if layer == "rock" and _msg_t <= 0.0:
		_msg_t = 12.0
		return "Bedrock: the picks grind and spark. Slow going."
	return ""


func _animate(delta: float = 0.016) -> void:
	_t += delta
	_msg_t -= delta
	var on := cutter_on and engine_on
	var working := on and _resist > 0.05
	# the boom sweeps the face: side to side, stepping down, while it cuts
	var sweep := sin(_t * 1.3) * 0.32 if working else 0.0
	var lift := (0.12 + 0.18 * sin(_t * 0.37)) if working else 0.05 - grade * 0.6
	_turret.rotation.y = lerpf(_turret.rotation.y, sweep, clampf(delta * 3.0, 0.0, 1.0))
	_boom.rotation.x = lerpf(_boom.rotation.x, lift - 0.12, clampf(delta * 2.0, 0.0, 1.0))
	if on:
		_head.rotation.z += delta * 9.0
		for st in _stars:
			(st as Node3D).rotate_object_local(Vector3.UP, delta * (4.0 if st == _stars[0] else -4.0))
	_dust.emitting = working
	for l in _lights:
		(l as SpotLight3D).visible = driven or on
	var fill := clampf(float(tub.get("pay", 0.0)) / TUB_M3, 0.0, 1.0)
	_muck.visible = fill > 0.02
	_muck.scale = Vector3(1, 0.4 + 6.0 * fill, 1)


func _physics_process(delta: float) -> void:
	if not driven:
		cutter_on = false
		_animate(delta)
		speed = 0.0


# ==============================================================================
#  The E key and the HUD line
# ==============================================================================
func machine_action() -> String:
	if not cutter_on and float(tub.get("pay", 0.0)) > 0.05 and _can_dump():
		var at := global_transform * Vector3(0, 0, 4.6)
		at.y = terrain.height_at(at.x, at.z)
		var hop: Vector3 = prospect.hopper_near(at) if prospect != null else Vector3.INF
		if hop != Vector3.INF:
			at = hop
		var ld := {"pay": float(tub["pay"]), "g": float(tub.get("g", 0.0)), "over": 0.0}
		tub = {}
		return prospect._dump(at, ld) if prospect != null else "Dumped."
	cutter_on = not cutter_on
	_bite = minf(_bite, REACH)
	if cutter_on:
		return "Cutter running. Drive into a bank or a drift face. On flat ground, lower the boom (%s) first to cut down into it; %s raises it." % [Game.lever_hint(false), Game.lever_hint(true)]
	return "Cutter stopped."


## Out in the open (not under the ground): the tub can tip.
func _can_dump() -> bool:
	var p := global_position
	return p.y > terrain.height_at(p.x, p.z) - 1.0


func status() -> String:
	var hint: String = Game.hint("interact")
	var pay := float(tub.get("pay", 0.0))
	var g := "%+.0f%%" % (grade * 100.0)
	var tubs := "tub %.1f / %.0f m3 pay" % [pay, TUB_M3]
	if cutter_on:
		return "Cutter ON (%s stop)   boom %s (%s up, %s down)   %s" % [hint, g, Game.lever_hint(true), Game.lever_hint(false), tubs]
	if pay > 0.05 and _can_dump():
		return "%s  Tip the tub (%.1f m3 of pay)%s   grade %s" % [hint, pay, "  into the hopper" if prospect != null and prospect.hopper_near(global_transform * Vector3(0, 0, 4.6)) != Vector3.INF else "", g]
	return "%s  Start the cutter   boom %s (%s up, %s down)   %s   %s get off" % [hint, g, Game.lever_hint(true), Game.lever_hint(false), tubs, Game.hint("get_out")]


func save_state() -> Dictionary:
	return {"xf": global_transform, "tub": tub, "grade": grade}
