extends RefCounted
## The gold gear on wheels, rebuilt after real ones (DESIGN_NOTES 83):
##  - a portable wash plant on a tandem-axle trailer: feed hopper with a
##    grizzly over it at the back (the excavator feeds it from behind),
##    a sloped vibrating screen deck on springs with a spray bar, the
##    undersize going to two sluice runs that fold out either side, the
##    oversize chute off the front corner, a diesel power pack and water
##    pump on the front of the deck, jack stands at the corners.
##  - a highbanker on a little single-axle utility trailer: hopper box with
##    a classifier screen, the sluice run that swings down to working angle,
##    fold-down legs, a 2" pump on the tongue.
## Both: tongue to -Z, origin on the ground under the axle(s). Parts that
## fold are their own nodes; the builders return [node, working, folded].

const MeshKit = preload("res://scripts/meshkit.gd")

const ORANGE := Color(0.90, 0.42, 0.08)
const ORANGE_D := Color(0.70, 0.30, 0.05)
const FRAME := Color(0.22, 0.23, 0.24)
const STEEL := Color(0.52, 0.54, 0.56)
const GALV := Color(0.70, 0.72, 0.72)
const RUBBER := Color(0.08, 0.08, 0.09)
const MAT := Color(0.12, 0.25, 0.45)
const ENGINE := Color(0.85, 0.72, 0.12)
const PUMP := Color(0.15, 0.32, 0.62)


# ==============================================================================
#  Portable wash plant
# ==============================================================================
## Local hopper top centre (where the excavator dumps): keep in step with
## prospect.hopper_near().


# ==============================================================================
#  Highbanker on a utility trailer
# ==============================================================================
static func sluice_trailer(t: Node3D) -> void:
	t.axle_local = Vector3(0, 0.3, 0.25)
	t.wheel_r = 0.3
	t.track = 1.5
	t.axles = 1
	t.tongue_local = Vector3(0, 0.52, -2.2)
	t.mass = 260.0
	var k := MeshKit.new()
	var dy := 0.6
	var wood := Color(0.55, 0.42, 0.27)
	# utility trailer: a box frame, plank bed, low sides, tongue
	for sx in [-0.62, 0.62]:
		k.box_at(Vector3(sx, dy - 0.06, 0.3), Vector3(0.07, 0.1, 2.2), FRAME)
	for z in [-0.75, 0.0, 0.7, 1.35]:
		k.box_at(Vector3(0, dy - 0.06, z), Vector3(1.3, 0.07, 0.07), FRAME)
	for pl in range(6):
		k.box_at(Vector3(-0.55 + 0.22 * float(pl), dy + 0.01, 0.3), Vector3(0.2, 0.04, 2.15), wood.darkened(0.05 * float(pl % 2)))
	for sx2 in [-1.0, 1.0]:
		k.box_at(Vector3(sx2 * 0.64, dy + 0.18, 0.3), Vector3(0.04, 0.3, 2.2), ORANGE)
		_beam(k, Vector3(sx2 * 0.62, dy - 0.06, -0.75), t.tongue_local + Vector3(0, -0.02, 0.15), Vector2(0.07, 0.08), FRAME)
	k.box_at(Vector3(0, dy + 0.18, -0.8), Vector3(1.3, 0.3, 0.04), ORANGE)
	k.box_at(t.tongue_local, Vector3(0.12, 0.1, 0.24), STEEL)
	# the highbanker's hopper box and classifier screen, at the front of the bed
	var hb := Vector3(0, dy + 0.75, -0.35)
	k.box_at(hb + Vector3(0, -0.15, 0), Vector3(0.62, 0.4, 0.62), GALV)
	k.box_at(hb + Vector3(0, 0.08, 0), Vector3(0.6, 0.03, 0.6), Color(0.25, 0.25, 0.27))      # classifier
	for gx in range(6):
		k.box_at(hb + Vector3(-0.25 + 0.1 * float(gx), 0.1, 0), Vector3(0.02, 0.02, 0.58), STEEL)
	for lx in [-0.28, 0.28]:
		for lz in [-0.28, 0.28]:
			k.box_at(hb + Vector3(lx, -0.5, lz), Vector3(0.04, 0.6, 0.04), GALV)
	k.box_at(hb + Vector3(0, 0.25, -0.31), Vector3(0.6, 0.05, 0.05), PUMP)                    # spray bar
	# 2" pump on the tongue, hose up to the spray bar
	k.box_at(Vector3(0, dy - 0.02, -1.45), Vector3(0.42, 0.04, 0.35), FRAME)
	k.box_at(Vector3(0, dy + 0.2, -1.45), Vector3(0.38, 0.36, 0.32), Color(0.75, 0.12, 0.08))
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.28, dy + 0.12, -1.45)), 0.1, 0.1, 0.16, 8, RUBBER)
	_beam(k, Vector3(0.1, dy + 0.2, -1.3), hb + Vector3(0.25, 0.25, -0.32), Vector2(0.04, 0.04), RUBBER)
	t.add_running_gear(k, FRAME, false)
	t.add_child(k.instance("SluiceTrailer"))
	# the sluice run: hinged under the hopper, it lies on the bed to travel and
	# tips down over the tailgate to work (about 8 degrees)
	var sk := MeshKit.new()
	var run := 1.8
	sk.box_at(Vector3(0, 0, run * 0.5), Vector3(0.32, 0.03, run), GALV)
	for e in [-1.0, 1.0]:
		sk.box_at(Vector3(e * 0.16, 0.08, run * 0.5), Vector3(0.02, 0.16, run), GALV)
	sk.box_at(Vector3(0, 0.02, run * 0.5), Vector3(0.3, 0.008, run - 0.05), MAT)
	for r in range(9):
		sk.box_at(Vector3(0, 0.04, 0.15 + 0.18 * float(r)), Vector3(0.3, 0.04, 0.025), Color(0.25, 0.25, 0.27))
	var n := sk.instance("Sluice")
	t.add_child(n)
	var hinge := Vector3(0, dy + 0.42, -0.05)
	t.fold_parts.append([n, Transform3D(Basis(Vector3.RIGHT, 0.14), hinge), Transform3D(Basis(Vector3.RIGHT, 0.0), hinge + Vector3(0, -0.3, 0))])
	# two fold-down legs at the back corners (a stable stand off the wheels)
	for sx3 in [-1.0, 1.0]:
		var lk := MeshKit.new()
		lk.box_at(Vector3(0, -dy * 0.5, 0), Vector3(0.06, dy, 0.06), ORANGE_D)
		lk.box_at(Vector3(0, -dy + 0.02, 0), Vector3(0.18, 0.03, 0.18), STEEL)
		var ln := lk.instance("Leg")
		t.add_child(ln)
		var at := Vector3(sx3 * 0.6, dy - 0.05, 1.35)
		t.fold_parts.append([ln, Transform3D(Basis.IDENTITY, at), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at)])
	t._pose_folds()


static func _beam(kit, a: Vector3, b: Vector3, sec: Vector2, col: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var y := d / l
	var x := Vector3.UP.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	kit.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(sec.x, l, sec.y), col)


# ==============================================================================
#  Skid-mounted trommel wash plant (from Dave's photo, DESIGN_NOTES 85)
# ==============================================================================
## All yellow, on two heavy skids with fork pockets (a loader on forks lifts
## it onto a trailer to move it). An elevated feed hopper with a steep
## grizzly on a tall frame at the back and a ladder up to its platform; the
## trommel drum in its frame running forward and down from it; the oversize
## rock coming out the front end down a chute onto a pile; the fines falling
## into the sump under the drum and out over a wide main sluice and a
## narrow one beside it; the engine and water pump on the deck with a fuel
## drum and the big red suction hose.
const TROMMEL_HOPPER := Vector3(0, 3.9, 3.55)
## The engine (stand here and E to start / stop) and the top of its exhaust.
const TROMMEL_ENGINE := Vector3(0.6, 0.9, 1.2)
const TROMMEL_EXHAUST := Vector3(0.75, 1.72, 1.5)
## The fuel drum beside it (pour a gas can in here).
const TROMMEL_FUEL := Vector3(-0.6, 0.85, 1.4)
const YEL := Color(0.93, 0.72, 0.10)
const YEL_D := Color(0.72, 0.53, 0.06)

static func skid_trommel(root: Node3D) -> void:
	var k := MeshKit.new()
	var deck := 0.42
	# --- skids, fork pockets, deck frame ---------------------------------
	for sx in [-0.95, 0.95]:
		k.box_at(Vector3(sx, 0.17, 0), Vector3(0.22, 0.34, 9.2), YEL_D)                 # runner
		k.box_at(Vector3(sx, 0.32, 0), Vector3(0.3, 0.04, 9.2), YEL_D)                  # top flange
		k.box_at(Vector3(sx, 0.03, 0), Vector3(0.3, 0.04, 9.2), YEL_D)
		for e in [-1.0, 1.0]:
			k.box(Transform3D(Basis(Vector3.RIGHT, e * 0.5), Vector3(sx, 0.32, e * 4.75)), Vector3(0.22, 0.3, 0.5), YEL_D)   # upturned ends
	for pz in [-1.5, 1.5]:
		k.box_at(Vector3(0, 0.2, pz), Vector3(2.5, 0.2, 0.32), FRAME)                   # fork pockets
		for e2 in [-1.0, 1.0]:
			k.box_at(Vector3(e2 * 1.25, 0.2, pz), Vector3(0.02, 0.14, 0.24), RUBBER)    # their open ends
	for z in [-4.2, -2.8, -1.4, 0.0, 1.4, 2.8, 4.2]:
		k.box_at(Vector3(0, deck - 0.04, z), Vector3(2.1, 0.08, 0.12), YEL_D)
	k.box_at(Vector3(0, deck, 0), Vector3(2.3, 0.03, 9.0), Color(0.32, 0.32, 0.30))     # deck plate
	# --- hopper tower at the back -------------------------------------------
	var hz0 := 2.4
	var hz1 := 4.6
	var plat := 2.9
	for lx in [-1.05, 1.05]:
		for lz in [hz0 + 0.1, hz1 - 0.1]:
			k.box_at(Vector3(lx, (deck + plat) * 0.5, lz), Vector3(0.16, plat - deck, 0.16), YEL)
		_beam(k, Vector3(lx, deck, hz0 + 0.1), Vector3(lx, plat - 0.2, hz1 - 0.1), Vector2(0.08, 0.08), YEL_D)   # side brace
	k.box_at(Vector3(0, plat, (hz0 + hz1) * 0.5), Vector3(2.5, 0.1, hz1 - hz0), YEL_D)  # hopper floor frame
	# the hopper box: sides up from the platform, sloping in to the feed throat
	var top := 4.0
	var hx := 1.3
	k.quad(Vector3(-hx, top, hz0), Vector3(hx, top, hz0), Vector3(0.45, plat + 0.1, hz0 + 0.3), Vector3(-0.45, plat + 0.1, hz0 + 0.3), YEL, Vector3(0, 0.2, -1))
	k.quad(Vector3(hx, top, hz1), Vector3(-hx, top, hz1), Vector3(-0.45, plat + 0.1, hz1 - 0.6), Vector3(0.45, plat + 0.1, hz1 - 0.6), YEL, Vector3(0, 0.2, 1))
	for sx2 in [-1.0, 1.0]:
		k.quad(Vector3(sx2 * hx, top, hz0), Vector3(sx2 * hx, top, hz1), Vector3(sx2 * 0.45, plat + 0.1, hz1 - 0.6), Vector3(sx2 * 0.45, plat + 0.1, hz0 + 0.3), YEL_D, Vector3(sx2, 0.2, 0))
		k.box_at(Vector3(sx2 * hx, top - 0.35, (hz0 + hz1) * 0.5), Vector3(0.06, 0.7, hz1 - hz0), YEL)   # side boards
	# the grizzly: steep bars over the top, boulders roll off the back
	var gb := Basis(Vector3.RIGHT, 0.65)
	var gc := Vector3(0, top + 0.45, (hz0 + hz1) * 0.5 + 0.2)
	k.box(Transform3D(gb, gc + Vector3(0, 0, -1.25) * 0.0 + gb.z * -1.3), Vector3(2.6, 0.12, 0.12), YEL_D)
	k.box(Transform3D(gb, gc + gb.z * 1.3), Vector3(2.6, 0.12, 0.12), YEL_D)
	for gx in range(13):
		var x := -1.2 + 0.2 * float(gx)
		k.box(Transform3D(gb, gc + Vector3(x, 0, 0)), Vector3(0.05, 0.09, 2.7), STEEL)
	for sx3 in [-1.0, 1.0]:
		k.box(Transform3D(gb, gc + Vector3(sx3 * 1.3, 0.25, 0)), Vector3(0.08, 0.5, 2.7), YEL)    # grizzly cheek plates
		k.box_at(Vector3(sx3 * 1.25, (top + gc.y) * 0.5 + 0.2, hz1 + 0.2), Vector3(0.1, 1.2, 0.1), YEL_D)   # grizzly back legs
	# platform walkway and handrail on the left, ladder up to it
	k.box_at(Vector3(-1.55, plat, 2.9), Vector3(0.7, 0.06, 1.6), Color(0.3, 0.3, 0.3))
	for pz2 in [2.15, 3.65]:
		k.box_at(Vector3(-1.85, plat + 0.55, pz2), Vector3(0.04, 1.1, 0.04), YEL)
	k.box_at(Vector3(-1.85, plat + 1.1, 2.9), Vector3(0.04, 0.04, 1.55), YEL)
	for rx in [-1.42, -1.78]:
		_beam(k, Vector3(rx, 0.0, 1.55), Vector3(rx, plat, 2.15), Vector2(0.05, 0.05), YEL)        # ladder rails
	for r in range(10):
		var f := float(r + 1) / 11.0
		k.box_at(Vector3(-1.6, plat * f, lerpf(1.55, 2.15, f)), Vector3(0.36, 0.035, 0.035), YEL)
	# feed chute from the hopper throat into the drum
	k.box(Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0, plat - 0.2, hz0 - 0.05)), Vector3(0.9, 0.06, 0.9), STEEL)
	# --- the trommel ----------------------------------------------------------
	var a := Vector3(0, 2.35, 2.2)          # feed end (high)
	var b := Vector3(0, 1.85, -3.0)         # discharge end (low)
	var axis := (b - a)
	var len := axis.length()
	var db := Basis(Vector3.RIGHT, -atan2(a.y - b.y, a.z - b.z)) * Basis(Vector3.RIGHT, -PI * 0.5)
	var dr := 0.68
	# The drum is its own node so it turns (prospect spins it while the plant
	# runs): a solid scrubber section at the feed end with lifter bars inside,
	# then the screen section - a real perforated tube you can see through,
	# rings and longitudinal bars holding the mesh.
	var drum := Node3D.new()
	drum.name = "Drum"
	drum.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	drum.transform = Transform3D(db, a)
	root.add_child(drum)
	var dk := MeshKit.new()
	var scrub := 1.3
	dk.cylinder(Transform3D.IDENTITY, dr, dr, scrub, 18, Color(0.30, 0.31, 0.32), false)       # scrubber shell
	dk.cylinder(Transform3D.IDENTITY, dr - 0.03, dr - 0.03, scrub, 18, Color(0.20, 0.20, 0.21), false)
	for li in range(6):
		var la := TAU * float(li) / 6.0
		dk.box_at(Vector3(cos(la) * (dr - 0.12), scrub * 0.5, sin(la) * (dr - 0.12)), Vector3(0.06, scrub, 0.06), STEEL)   # lifters
	dk.cylinder(Transform3D.IDENTITY, dr + 0.02, dr + 0.02, 0.06, 18, STEEL, false)             # feed-end lip
	for rz in [0.15, 0.85]:
		dk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, len * rz - 0.08, 0)), dr + 0.07, dr + 0.07, 0.16, 18, STEEL, false)   # riding rings
	for ring in range(6):
		var ry := scrub + (len - scrub) * float(ring) / 5.0
		dk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, ry - 0.03, 0)), dr + 0.02, dr + 0.02, 0.06, 18, Color(0.35, 0.36, 0.37), false)
	for lb in range(10):
		var ba := TAU * float(lb) / 10.0
		dk.box_at(Vector3(cos(ba) * (dr + 0.01), scrub + (len - scrub) * 0.5, sin(ba) * (dr + 0.01)), Vector3(0.05, len - scrub, 0.05), Color(0.35, 0.36, 0.37))
	dk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, len - 0.05, 0)), dr + 0.03, dr + 0.03, 0.05, 18, STEEL, false)   # discharge lip
	drum.add_child(dk.instance("DrumFrame"))
	# the screen: a see-through punched-plate / mesh tube
	var scr := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = dr
	cm.bottom_radius = dr
	cm.height = len - scrub
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	scr.mesh = cm
	scr.material_override = screen_material()
	scr.position = Vector3(0, scrub + (len - scrub) * 0.5, 0)
	drum.add_child(scr)
	# its frame: long side walls up to the axle line, cross members, rollers
	var mid := (a + b) * 0.5
	var fb := Basis(Vector3.RIGHT, atan2(a.y - b.y, a.z - b.z))
	for sx4 in [-1.0, 1.0]:
		k.box(Transform3D(fb, mid + Vector3(sx4 * 0.92, -0.35, 0)), Vector3(0.08, 1.0, len + 0.4), YEL)
		k.box(Transform3D(fb, mid + Vector3(sx4 * 0.92, 0.17, 0)), Vector3(0.18, 0.06, len + 0.4), YEL_D)
		for rz2 in [0.12, 0.88]:
			var rp: Vector3 = a + axis * rz2 + Vector3(sx4 * 0.62, -0.62, 0)
			k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), rp + Vector3(0.1, 0, 0)), 0.14, 0.14, 0.2, 10, RUBBER)
	for lz2 in [2.0, 0.0, -2.0, -3.0]:
		var ty: float = lerpf(b.y, a.y, (lz2 - b.z) / (a.z - b.z)) - 0.85
		for sx5 in [-1.0, 1.0]:
			k.box_at(Vector3(sx5 * 0.92, (deck + ty) * 0.5, lz2), Vector3(0.14, ty - deck, 0.14), YEL)
	# a short spray hood over the scrubber end only - the screen stays open to see
	k.box(Transform3D(fb, a + axis * 0.12 + Vector3(0, dr + 0.08, 0)), Vector3(1.6, 0.04, 1.4), Color(0.10, 0.10, 0.11))
	# spray pipe in at the feed end, fed by the red hose from the pump
	k.cylinder(Transform3D(db, a - axis.normalized() * 0.4 + Vector3(0, 0.25, 0)), 0.05, 0.05, len * 0.7, 8, Color(0.75, 0.15, 0.1))
	# --- undersize sump under the drum, and the sluices out the right side -----
	k.box_at(Vector3(0, 1.0, -0.6), Vector3(1.7, 0.7, 3.4), YEL_D)
	# wide main sluice, out to the right and down, riffled, with legs
	var s0 := Vector3(0.85, 1.25, -1.2)
	var sl := 4.6
	var sb := Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, -0.16)
	var sc := s0 + sb * Vector3(0, 0, -sl * 0.5)
	k.box(Transform3D(sb, sc), Vector3(0.95, 0.04, sl), GALV)
	for e3 in [-1.0, 1.0]:
		k.box(Transform3D(sb, sc + sb * Vector3(e3 * 0.48, 0.16, 0)), Vector3(0.04, 0.32, sl), YEL)
	for r2 in range(18):
		k.box(Transform3D(sb, sc + sb * Vector3(0, 0.05, -sl * 0.5 + 0.2 + 0.24 * float(r2))), Vector3(0.9, 0.06, 0.03), Color(0.62, 0.55, 0.40))
	k.box(Transform3D(sb, sc + sb * Vector3(0, 0.025, 0)), Vector3(0.9, 0.01, sl - 0.1), MAT)
	for f2 in [0.45, 0.95]:
		var lp: Vector3 = s0 + sb * Vector3(0, 0, -sl * f2)
		k.box_at(Vector3(lp.x, lp.y * 0.5, lp.z), Vector3(0.08, lp.y, 0.08), YEL_D)
	# the narrow chute beside it
	var s1 := Vector3(0.85, 1.2, 0.2)
	var nb := Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, -0.24)
	var nc := s1 + nb * Vector3(0, 0, -1.4)
	k.box(Transform3D(nb, nc), Vector3(0.45, 0.04, 2.8), GALV)
	for e4 in [-1.0, 1.0]:
		k.box(Transform3D(nb, nc + nb * Vector3(e4 * 0.23, 0.12, 0)), Vector3(0.03, 0.24, 2.8), YEL)
	# --- oversize: chute off the low end, down to the left ---------------------
	# It starts just under the drum's lip (the drum is 0.68 m in radius) and
	# runs DOWN and out, so the rock slides off the far end onto the pile;
	# it used to tilt the wrong way, its far end up in the air.
	var ob := Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, -0.45)
	var oc := b + Vector3(-0.43, -1.15, -0.85)
	k.box(Transform3D(ob, oc), Vector3(1.1, 0.05, 2.0), STEEL)
	for e5 in [-1.0, 1.0]:
		k.box(Transform3D(ob, oc + ob * Vector3(e5 * 0.55, 0.15, 0)), Vector3(0.05, 0.3, 2.0), YEL)
	# two legs under the low end
	for e6 in [-1.0, 1.0]:
		var foot := oc + ob * Vector3(e6 * 0.45, 0, -0.85)
		_beam(k, foot, Vector3(foot.x, 0.0, foot.z), Vector2(0.06, 0.06), YEL_D)
	# --- engine, pump, fuel drum, the red hose -------------------------------
	k.box_at(Vector3(0.6, deck + 0.5, 1.2), Vector3(0.9, 0.95, 1.2), YEL_D)
	k.box_at(Vector3(0.6, deck + 1.0, 1.2), Vector3(0.85, 0.06, 1.15), YEL)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.75, deck + 1.0, 1.5)), 0.05, 0.05, 0.55, 8, RUBBER)       # exhaust
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(1.4, deck + 0.35, 1.2)), 0.22, 0.22, 0.4, 10, PUMP)   # pump
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.6, deck, 1.4)), 0.29, 0.29, 0.88, 12, Color(0.15, 0.32, 0.62))  # fuel drum
	k.box_at(Vector3(-0.6, deck + 0.89, 1.4), Vector3(0.3, 0.02, 0.06), Color(0.9, 0.9, 0.9))
	var hose := Color(0.85, 0.30, 0.22)
	_beam(k, Vector3(1.4, deck + 0.35, 1.4), Vector3(1.9, 0.1, 2.6), Vector2(0.16, 0.16), hose)                # suction hose off toward the pond
	_beam(k, Vector3(1.9, 0.1, 2.6), Vector3(3.2, 0.08, 6.5), Vector2(0.16, 0.16), hose)
	_beam(k, Vector3(1.3, deck + 0.55, 1.0), a + Vector3(0.3, 0.4, 0.3), Vector2(0.11, 0.11), hose)             # up to the spray pipe
	root.add_child(k.instance("TrommelPlant"))


## Punched screen plate: steel with square holes, alpha-tested so you see
## the gravel tumbling inside. Shared by every trommel.
static var _screen_mat: StandardMaterial3D = null
static func screen_material() -> StandardMaterial3D:
	if _screen_mat != null:
		return _screen_mat
	var n := 64
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.40, 0.41, 0.42, 1.0))
	var hole := 9
	var pitch := 16
	for y in range(n):
		for x in range(n):
			if (x % pitch) >= 3 and (x % pitch) < 3 + hole and (y % pitch) >= 3 and (y % pitch) < 3 + hole:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.uv1_scale = Vector3(14, 6, 1)
	m.metallic = 0.4
	m.roughness = 0.55
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_screen_mat = m
	return m


# ------------------------------------------------------------------------------
#  Trommel at work (DESIGN_NOTES 96): spray in the drum, gravel tumbling
#  through it, oversize clattering down its chute, water running down the
#  sluices (brown while there's gravel going through) and off their tails.
#  Returns the pieces for prospect.gd to switch on and off.
# ------------------------------------------------------------------------------
const FLOW_SHADER = preload("res://shaders/sluice_flow.gdshader")

static func trommel_fx(root: Node3D) -> Dictionary:
	var a := Vector3(0, 2.35, 2.2)          # drum feed end (high)
	var b := Vector3(0, 1.85, -3.0)         # discharge end (low)
	var axis := (b - a).normalized()
	var fx := {}
	# spray bar firing down into the drum at the feed end
	fx["spray"] = _drops(root, a + axis * 1.2 + Vector3(0, 0.45, 0), Vector3(0, -1, 0), Vector3(0.1, 0.05, 1.1), 60, 0.5, 3.5, Color(0.8, 0.9, 1.0, 0.55), 0.03, 0.06, 30.0)
	# gravel rolling through the drum, low in it
	fx["gravel"] = _drops(root, (a + b) * 0.5 + Vector3(0, -0.4, 0), axis, Vector3(0.35, 0.05, 2.3), 50, 2.2, 1.0, Color(0.45, 0.36, 0.25, 1.0), 0.05, 0.11, 25.0)
	(fx["gravel"] as CPUParticles3D).gravity = Vector3(0, -1.5, 0)
	# oversize out of the low end and down its chute to the left
	var od := (Basis(Vector3.UP, 0.5) * Vector3(0, -0.5, -1)).normalized()
	fx["oversize"] = _drops(root, b + Vector3(-0.05, -0.6, -0.15), od, Vector3(0.25, 0.1, 0.1), 14, 1.6, 2.2, Color(0.5, 0.47, 0.43, 1.0), 0.09, 0.17, 18.0, true)
	# water on the sluices: a flowing sheet on the bed of each
	var mats: Array = []
	var s0 := Vector3(0.85, 1.25, -1.2)
	var sl := 4.6
	var sb := Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, -0.16)
	mats.append(_sheet(root, Transform3D(sb, s0 + sb * Vector3(0, 0.075, -sl * 0.5)), Vector2(0.86, sl - 0.1), 18.0))
	var s1 := Vector3(0.85, 1.2, 0.2)
	var nb := Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, -0.24)
	mats.append(_sheet(root, Transform3D(nb, s1 + nb * Vector3(0, 0.06, -1.4)), Vector2(0.4, 2.7), 0.0))
	fx["sheets"] = mats
	# water pouring off each tail onto the ground
	var tail1 := s0 + sb * Vector3(0, 0.05, -sl)
	var tail2 := s1 + nb * Vector3(0, 0.05, -2.8)
	fx["tail"] = _drops(root, tail1, Vector3(1, -0.4, 0).normalized(), Vector3(0.05, 0.02, 0.4), 50, 0.7, 1.8, Color(0.55, 0.62, 0.66, 0.6), 0.05, 0.1, 12.0)
	fx["tail2"] = _drops(root, tail2, Vector3(1, -0.5, 0).normalized(), Vector3(0.05, 0.02, 0.18), 30, 0.7, 1.8, Color(0.55, 0.62, 0.66, 0.6), 0.04, 0.08, 12.0)
	# a burst of dirt for each bucket dumped in the hopper
	fx["dump"] = _drops(root, TROMMEL_HOPPER + Vector3(0, 0.8, 0), Vector3(0, -1, 0), Vector3(0.7, 0.2, 0.7), 60, 1.0, 1.5, Color(0.45, 0.35, 0.24, 1.0), 0.06, 0.16, 35.0, true)
	(fx["dump"] as CPUParticles3D).one_shot = true
	(fx["dump"] as CPUParticles3D).explosiveness = 0.85
	return fx


static func _drops(root: Node3D, at: Vector3, dir: Vector3, box: Vector3, amount: int, life: float, speed: float, col: Color, s0: float, s1: float, spread: float, rocks: bool = false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = at
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = s0
	p.scale_amount_max = s1
	if rocks:
		p.angular_velocity_min = -360.0
		p.angular_velocity_max = 360.0
		p.particle_flag_rotate_y = true
	var m: Mesh
	if rocks:
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 0.8, 0.9)
		m = bm
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 5
		sm.rings = 3
		m = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	if col.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if m is PrimitiveMesh:
		(m as PrimitiveMesh).material = mat
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	return p


## A flowing water sheet: a quad laid along a sluice bed (its -Z is downhill).
static func _sheet(root: Node3D, xf: Transform3D, size: Vector2, bands: float) -> ShaderMaterial:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	# a QuadMesh stands in XY: lay it flat (its +Y along the bed, downhill)
	mi.transform = xf * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO)
	var m := ShaderMaterial.new()
	m.shader = FLOW_SHADER
	m.set_shader_parameter("bands", bands if bands > 0.0 else 8.0)
	m.set_shader_parameter("speed", 1.0)
	m.set_shader_parameter("mud", 0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	root.add_child(mi)
	m.set_meta("node", mi)
	return m
