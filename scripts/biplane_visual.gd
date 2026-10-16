extends "res://scripts/plane_visual.gd"
## The Meadowlark: a two-seat open-cockpit trainer biplane, modelled on the
## Stearman 75 / PT-17 (DESIGN_NOTES 153). Real numbers: 9.8 m span both
## wings, 7.5 m long, 2.8 m high, 27.6 m^2 of wing, upper wing staggered
## ahead of the lower, a 220 hp 7-cylinder radial with its cylinders out in
## the air, ailerons on the lower wings only, the fuel tank in the upper
## wing's centre section, a split-axle main gear on oleo legs, a steerable
## tailwheel. Steel tube and fabric: metal panels round the nose, fabric aft
## with the stringers showing through, rib tapes on the wings, flying and
## landing wires between the wings, the tail braced with struts and wires.
## Student in front, pilot (you) in the back.
##
## Paint slots (liveries.gd BIPLANE): CREAM the fuselage, ORANGE the wings
## and tail, BROWN the trim.

const BiCockpit = preload("res://scripts/biplane_cockpit.gd")

# Wing geometry (aircraft coordinates: -Z forward, Y up, thrust line y = 0).
const UP_Y := 1.18          # upper wing chord line at the root
const UP_LE := -0.78        # upper wing leading edge (staggered forward)
const UP_C := 1.45
const UP_DIH := 0.5         # degrees
const LO_Y := -0.52         # lower wing at the fuselage's lower longerons
const LO_LE := -0.24
const LO_C := 1.40
const LO_DIH := 1.6
const HALF_SPAN := 4.9
const ROOT_LO := 0.42       # lower wing root (the fuselage side)
const STRUT_X := 3.25       # interplane struts
const AIL_X0 := 2.55        # lower-wing aileron span
const AIL_X1 := 4.55
const AIL_C := 0.36
const ENG_Z := -1.86        # plane of the cylinders
const CYL_N := 7

const WIRE := Color(0.22, 0.22, 0.23)
const STEEL := Color(0.52, 0.53, 0.55)
const LEATHER := Color(0.30, 0.17, 0.09)
const ALU := Color(0.70, 0.71, 0.72)
const CYL_C := Color(0.16, 0.16, 0.17)          # black-painted cylinder barrels
const HEAD_C := Color(0.55, 0.56, 0.57)         # bare aluminium heads
const CASE_C := Color(0.32, 0.34, 0.36)

var _ail_lo: Array[Node3D] = []
var _axle_struts: Array[MeshInstance3D] = []


static func up_y(ax: float) -> float:
	return UP_Y + ax * tan(deg_to_rad(UP_DIH))


static func lo_y(ax: float) -> float:
	return LO_Y + maxf(ax - ROOT_LO, 0.0) * tan(deg_to_rad(LO_DIH))


## Fuselage stations: [z, half width, top, bottom, corner bevel]. Round-ish
## at the firewall behind the engine, deepest at the cockpits, a rounded
## turtledeck tapering to the sternpost.
const SECTIONS := [
	[-1.52, 0.36, 0.40, -0.44, 0.26],
	[-1.30, 0.41, 0.45, -0.56, 0.22],
	[-0.75, 0.42, 0.47, -0.62, 0.19],
	[-0.20, 0.42, 0.48, -0.64, 0.18],
	[0.48, 0.42, 0.48, -0.64, 0.18],
	[0.90, 0.415, 0.48, -0.63, 0.18],
	[1.66, 0.40, 0.48, -0.60, 0.18],
	[2.40, 0.34, 0.45, -0.48, 0.16],
	[3.30, 0.26, 0.39, -0.34, 0.12],
	[4.20, 0.16, 0.32, -0.16, 0.08],
	[5.08, 0.05, 0.27, 0.04, 0.025],
]
const COCKPITS := [[-0.20, 0.48], [0.90, 1.66]]     # front (student), rear (pilot) openings


func repaint() -> void:
	_axle_struts.clear()
	super.repaint()


func _build_body() -> void:
	TAIL_BREAK = Vector3(0.0, 0.1, 2.05)     # behind the rear cockpit
	NOSE_FROM = -1.4
	NOSE_TO = -2.2
	var kit := MeshKit.new()
	_fuselage(kit)
	_cockpits(kit)
	_upper_wing(kit)
	_lower_wings(kit)
	_struts_and_wires(kit)
	_tail(kit)
	_gear_fixed(kit)
	var dm := DentMesh.new()
	dm.name = "Body"
	dm.bend = _wing_bend
	dm.setup(kit, 0.26)
	_body = dm
	add_child(_body)
	# windscreens: their own see-through mesh
	var gk := MeshKit.new()
	for wz in [-0.30, 0.80]:
		_windscreen_glass(gk, wz)
	_glass = gk.instance("Glass")
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.albedo_color = Color(0.62, 0.68, 0.66, 0.18)
	gm.roughness = 0.05
	gm.metallic_specular = 0.9
	_glass.material_override = gm
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glass)
	# registration on the fuselage sides behind the rear cockpit
	for side in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = plane.reg if plane != null else "N-4021"
		_reg_labels.append(label)
		label.font_size = 96
		label.pixel_size = 0.0024
		label.modulate = BROWN
		label.outline_size = 0
		label.double_sided = false
		var hw := _half_w(2.75)
		label.position = Vector3(side * (hw + 0.006), -0.17, 2.75)
		label.rotation = Vector3(0, side * (PI * 0.5 - atan2(0.08, 0.9)), 0)
		add_child(label)


## Half-width of the fuselage at station z (the flat side).
static func _half_w(z: float) -> float:
	for k in range(SECTIONS.size() - 1):
		var a: Array = SECTIONS[k]
		var b: Array = SECTIONS[k + 1]
		if z >= float(a[0]) and z <= float(b[0]):
			return lerpf(a[1], b[1], (z - float(a[0])) / (float(b[0]) - float(a[0])))
	return 0.05


static func _sec_at(z: float) -> Array:
	for k in range(SECTIONS.size() - 1):
		var a: Array = SECTIONS[k]
		var b: Array = SECTIONS[k + 1]
		if z >= float(a[0]) - 0.0001 and z <= float(b[0]) + 0.0001:
			var t := (z - float(a[0])) / (float(b[0]) - float(a[0]))
			return [z, lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(a[3], b[3], t), lerpf(a[4], b[4], t)]
	return SECTIONS[SECTIONS.size() - 1]


func _fuselage(kit: MeshKit) -> void:
	var rings: Array = []
	for s in SECTIONS:
		rings.append(_ring(s[0], s[1], s[2], s[3], s[4]))
	var metal_to := 2        # the nose (to just ahead of the front cockpit) is aluminium panels
	for r in range(rings.size() - 1):
		var ra: PackedVector3Array = rings[r]
		var rb: PackedVector3Array = rings[r + 1]
		var za: float = SECTIONS[r][0]
		var zb: float = SECTIONS[r + 1][0]
		var mid := (_centroid(ra) + _centroid(rb)) * 0.5
		var open_top := false
		for c in COCKPITS:
			if za >= float(c[0]) - 0.001 and zb <= float(c[1]) + 0.001:
				open_top = true
		for i in range(ra.size()):
			var j := (i + 1) % ra.size()
			if open_top and i == 15:
				continue
			var fm := (ra[i] + ra[j] + rb[i] + rb[j]) * 0.25
			var col := CREAM if r >= metal_to else CREAM.lightened(0.04)
			kit.quad(ra[i], ra[j], rb[j], rb[i], col, fm - mid)
	# the firewall face behind the engine, and the sternpost
	var first: PackedVector3Array = rings[0]
	var last: PackedVector3Array = rings[rings.size() - 1]
	for i in range(first.size()):
		kit.tri(_centroid(first), first[i], first[(i + 1) % first.size()], CASE_C, Vector3.FORWARD)
		kit.tri(_centroid(last), last[i], last[(i + 1) % last.size()], CREAM, Vector3.BACK)
	# Nose panels: the seams and the rows of fasteners on the metal cowl panels.
	for pz in [-1.30, -0.75, -0.20]:
		var s: Array = _sec_at(pz)
		var hw: float = s[1]
		for side in [-1.0, 1.0]:
			kit.box_at(Vector3(side * (hw + 0.002), (float(s[2]) + float(s[3])) * 0.5 - 0.02, pz), Vector3(0.004, (float(s[2]) - float(s[3])) * 0.72, 0.012), CREAM.darkened(0.25))
	for side in [-1.0, 1.0]:
		# louvres on the accessory-section side panels
		for k in range(6):
			var lz := -1.18 + 0.075 * float(k)
			kit.box(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(side * (_half_w(lz) + 0.008), -0.12, lz)), Vector3(0.012, 0.16, 0.02), CREAM.darkened(0.35))
		# the hand-hold and the step on the left side for climbing up
		if side < 0.0:
			kit.box_at(Vector3(-(_half_w(1.95) + 0.03), 0.30, 1.95), Vector3(0.03, 0.03, 0.18), STEEL)
			kit.box_at(Vector3(-(_half_w(0.75) + 0.1), -0.45, 0.75), Vector3(0.16, 0.025, 0.12), STEEL)
			_beam(kit, Vector3(-(_half_w(0.75)), -0.40, 0.75), Vector3(-(_half_w(0.75) + 0.1), -0.45, 0.75), 0.012, STEEL, 5)
	# Fabric aft: the stringers show through as ridges on the turtledeck, and
	# a trim stripe runs the length of the side.
	for k in range(5):
		var u := (float(k) - 2.0) * 0.07
		var p0 := Vector3(u, 0.485, 1.70)
		var p1 := Vector3(u * 0.35, 0.275, 5.00)
		_beam(kit, p0, p1, 0.007, CREAM.darkened(0.06), 4)
	for side in [-1.0, 1.0]:
		var pts: Array = []
		for z in [-1.30, -0.75, -0.20, 0.48, 0.90, 1.66, 2.40, 3.30, 4.20, 4.95]:
			var s2: Array = _sec_at(z)
			pts.append(Vector3(side * (float(s2[1]) + 0.004), lerpf(float(s2[3]), float(s2[2]), 0.62), z))
		for k in range(pts.size() - 1):
			var a: Vector3 = pts[k]
			var b: Vector3 = pts[k + 1]
			kit.quad(a + Vector3(0, 0.035, 0), b + Vector3(0, 0.035, 0), b - Vector3(0, 0.035, 0), a - Vector3(0, 0.035, 0), BROWN, Vector3(side, 0, 0))
	# Fuel filler on top of the upper wing's centre section and the gauge
	# sight tube under it (a float gauge you read from the rear cockpit).
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, up_y(0.0) + 0.12, -0.38)), 0.05, 0.045, 0.03, 10, STEEL)
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, up_y(0.0) - 0.07, 0.10)), 0.025, 0.025, 0.05, 8, Color(0.85, 0.85, 0.8))


## Two open cockpits: a padded leather coaming round each, the tub inside
## (floor, sides, seat), and a small windscreen ahead of each.
func _cockpits(kit: MeshKit) -> void:
	var interior := Color(0.36, 0.40, 0.34)       # zinc-chromate green
	var floor_c := Color(0.20, 0.17, 0.12)
	for ci in range(COCKPITS.size()):
		var z0: float = COCKPITS[ci][0]
		var z1: float = COCKPITS[ci][1]
		var s0: Array = _sec_at(z0)
		var top: float = s0[2]
		var hw: float = float(s0[1]) - float(s0[4])      # the opening is the flat top's width
		var fl := -0.42
		# The tub: the opening is the flat top's width, but below the coaming
		# it opens out to the full fuselage (the panel spans it). Sloped
		# panels under the deck follow the skin's rounded upper corners down
		# to the inner walls; the front cockpit's floor runs forward under the
		# deck to its little panel, the rear one's to the main panel.
		var zs := z0 - (0.12 if ci == 0 else 0.13)
		var tw := 0.39
		var wall_top := top - 0.15
		for side in [-1.0, 1.0]:
			kit.quad(Vector3(side * tw, wall_top, zs), Vector3(side * tw, wall_top, z1), Vector3(side * tw, fl, z1), Vector3(side * tw, fl, zs), interior, Vector3(-side, 0, 0))
			kit.quad(Vector3(side * hw, top - 0.004, zs), Vector3(side * hw, top - 0.004, z1), Vector3(side * tw, wall_top, z1), Vector3(side * tw, wall_top, zs), interior.darkened(0.25), Vector3(-side, -1, 0))
			# the opening's edge: a lip from the deck down to the sloped panel
			kit.quad(Vector3(side * hw, top + 0.004, z0), Vector3(side * hw, top + 0.004, z1), Vector3(side * hw, top - 0.004, z1), Vector3(side * hw, top - 0.004, z0), interior.darkened(0.3), Vector3(-side, 0, 0))
		# under the deck ahead of the opening
		kit.quad(Vector3(-hw, top - 0.004, zs), Vector3(hw, top - 0.004, zs), Vector3(hw, top - 0.004, z0), Vector3(-hw, top - 0.004, z0), interior.darkened(0.25), Vector3.DOWN)
		kit.quad(Vector3(-tw, fl, zs), Vector3(tw, fl, zs), Vector3(tw, fl, z1), Vector3(-tw, fl, z1), floor_c, Vector3.UP)
		# back of the tub (the seat bulkhead) and, for the front one, its
		# forward wall below the little panel
		kit.quad(Vector3(-tw, wall_top, z1), Vector3(tw, wall_top, z1), Vector3(tw, fl, z1), Vector3(-tw, fl, z1), interior.darkened(0.15), Vector3.FORWARD)
		kit.quad(Vector3(-hw, top, z1), Vector3(hw, top, z1), Vector3(tw, wall_top, z1), Vector3(-tw, wall_top, z1), interior.darkened(0.15), Vector3.FORWARD)
		kit.quad(Vector3(-tw, wall_top, zs), Vector3(-tw, fl, zs), Vector3(tw, fl, zs), Vector3(tw, wall_top, zs), interior.darkened(0.1), Vector3.BACK)
		kit.quad(Vector3(-hw, top, zs), Vector3(-tw, wall_top, zs), Vector3(tw, wall_top, zs), Vector3(hw, top, zs), interior.darkened(0.1), Vector3.BACK)
		# the steel-tube frame showing inside: longerons and a diagonal each side
		for side in [-1.0, 1.0]:
			_beam(kit, Vector3(side * (tw - 0.012), wall_top - 0.02, zs), Vector3(side * (tw - 0.012), wall_top - 0.02, z1), 0.012, Color(0.25, 0.28, 0.24), 5)
			_beam(kit, Vector3(side * (tw - 0.012), fl + 0.03, zs), Vector3(side * (tw - 0.012), wall_top - 0.04, z1 - 0.05), 0.010, Color(0.25, 0.28, 0.24), 5)
		# padded leather coaming round the opening
		var r := 0.032
		var cy := top + 0.012
		_beam(kit, Vector3(-hw - 0.01, cy, z0), Vector3(-hw - 0.01, cy, z1), r, LEATHER, 8)
		_beam(kit, Vector3(hw + 0.01, cy, z0), Vector3(hw + 0.01, cy, z1), r, LEATHER, 8)
		_beam(kit, Vector3(-hw - 0.01, cy, z1), Vector3(hw + 0.01, cy, z1), r, LEATHER, 8)
		_beam(kit, Vector3(-hw - 0.01, cy, z0), Vector3(hw + 0.01, cy, z0), r * 0.8, LEATHER, 8)
		# the bucket seat: an aluminium shell with a parachute-pack cushion
		var sz := z1 - 0.22
		kit.box_at(Vector3(0, -0.30, sz - 0.04), Vector3(0.40, 0.05, 0.38), ALU.darkened(0.1))
		kit.box(Transform3D(Basis(Vector3.RIGHT, 0.18), Vector3(0, -0.02, sz + 0.16)), Vector3(0.40, 0.52, 0.04), ALU.darkened(0.1))
		for sx in [-0.21, 0.21]:
			kit.box(Transform3D(Basis(Vector3.RIGHT, 0.18), Vector3(sx, -0.10, sz + 0.06)), Vector3(0.025, 0.36, 0.30), ALU.darkened(0.15))
		kit.box_at(Vector3(0, -0.23, sz - 0.04), Vector3(0.36, 0.09, 0.34), Color(0.42, 0.40, 0.30))     # cushion
		# harness straps over the shoulders
		for sx2 in [-0.08, 0.08]:
			kit.box(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(sx2, 0.12, sz + 0.12)), Vector3(0.045, 0.32, 0.006), Color(0.55, 0.50, 0.36))
		if ci == 0:
			# the student's cockpit: its own stick, rudder bar and three gauges
			_beam(kit, Vector3(0, fl, z0 + 0.28), Vector3(0, -0.02, z0 + 0.24), 0.014, Color(0.12, 0.12, 0.12), 6)
			kit.box_at(Vector3(0, -0.02, z0 + 0.24), Vector3(0.035, 0.09, 0.035), Color(0.08, 0.07, 0.06))
			kit.box_at(Vector3(0, fl + 0.06, z0 + 0.08), Vector3(0.46, 0.03, 0.06), STEEL)
			var pz := z0 - 0.10
			kit.box_at(Vector3(0, top - 0.17, pz), Vector3(tw * 2.0 - 0.04, 0.22, 0.02), Color(0.07, 0.07, 0.065))
			for gx in [-0.15, 0.0, 0.15]:
				kit.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(gx, top - 0.17, pz + 0.012)), 0.040, 0.040, 0.004, 14, Color(0.85, 0.84, 0.80))
				kit.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(gx, top - 0.17, pz + 0.010)), 0.047, 0.047, 0.008, 14, Color(0.10, 0.10, 0.10))
				kit.box_at(Vector3(gx, top - 0.16, pz + 0.018), Vector3(0.004, 0.032, 0.002), Color(0.05, 0.05, 0.05))
		# the speaking tube (the instructor's voice tube) up the right side
		_beam(kit, Vector3(hw - 0.03, top - 0.05, z0 + 0.1), Vector3(hw - 0.03, fl + 0.1, z0 + 0.3), 0.012, Color(0.12, 0.12, 0.12), 5)
	# windscreen frames (the glass is its own mesh)
	for wz in [-0.30, 0.80]:
		_windscreen_frame(kit, wz)


## A three-pane windscreen: a centre pane leaning back and two side panes.
func _ws_points(wz: float) -> Array:
	var s: Array = _sec_at(wz)
	var y0: float = float(s[2]) + 0.02
	var h := 0.24
	var lean := 0.14
	var w := 0.19
	var c0 := Vector3(-w, y0, wz)
	var c1 := Vector3(w, y0, wz)
	var c2 := Vector3(w * 0.85, y0 + h, wz + lean)
	var c3 := Vector3(-w * 0.85, y0 + h, wz + lean)
	var sl0 := Vector3(-w - 0.09, y0, wz + 0.17)
	var sl1 := Vector3(-w * 0.85 - 0.07, y0 + h * 0.92, wz + lean + 0.13)
	var sr0 := Vector3(w + 0.09, y0, wz + 0.17)
	var sr1 := Vector3(w * 0.85 + 0.07, y0 + h * 0.92, wz + lean + 0.13)
	return [c0, c1, c2, c3, sl0, sl1, sr0, sr1]


func _windscreen_glass(gk: MeshKit, wz: float) -> void:
	var p: Array = _ws_points(wz)
	gk.quad(p[0], p[1], p[2], p[3], GLASS, Vector3(0, 0.4, -1))
	gk.quad(p[4], p[0], p[3], p[5], GLASS, Vector3(-1, 0, -0.5))
	gk.quad(p[1], p[6], p[7], p[2], GLASS, Vector3(1, 0, -0.5))


func _windscreen_frame(kit: MeshKit, wz: float) -> void:
	var p: Array = _ws_points(wz)
	var fc := Color(0.75, 0.76, 0.78)
	for e in [[0, 1], [1, 2], [2, 3], [3, 0], [0, 4], [4, 5], [5, 3], [1, 6], [6, 7], [7, 2]]:
		_beam(kit, p[e[0]], p[e[1]], 0.007, fc, 5)


## An airfoil-section wing panel run from x0 to x1 (both ends on the same
## side), with rib tapes on top. `le` and `ch` are functions of |x|.
func _wing_run(kit: MeshKit, xs: Array, yf: Callable, le_f: Callable, ch_f: Callable, side: float, col: Color) -> void:
	var secs: Array = []
	for ax in xs:
		var a: float = ax
		secs.append(_airfoil(side * a, yf.call(a), le_f.call(a), ch_f.call(a)))
	if side < 0.0:
		secs.reverse()
	kit.loft(secs, col, false, false)


func _upper_wing(kit: MeshKit) -> void:
	var col := ORANGE
	var yf := func(a: float) -> float: return up_y(a)
	# centre section: the trailing edge cut back over the front cockpit
	var le_c := func(_a: float) -> float: return UP_LE
	var ch_c := func(a: float) -> float: return lerpf(1.02, UP_C, clampf(absf(a) / 0.62, 0.0, 1.0))
	for side in [-1.0, 1.0]:
		_wing_run(kit, [0.0, 0.2, 0.42, 0.62], yf, le_c, ch_c, side, col)
		var le_f := func(_a: float) -> float: return UP_LE
		var ch_f := func(_a: float) -> float: return UP_C
		_wing_run(kit, [0.62, 1.6, 2.6, 3.6, 4.6], yf, le_f, ch_f, side, col)
		# rounded tip
		var tips: Array = [_airfoil(side * 4.6, up_y(4.6), UP_LE, UP_C),
			_airfoil(side * 4.78, up_y(4.78), UP_LE + 0.05, UP_C - 0.12, 0.85),
			_airfoil(side * 4.88, up_y(4.88), UP_LE + 0.16, UP_C - 0.36, 0.55),
			_airfoil(side * 4.92, up_y(4.92), UP_LE + 0.32, UP_C - 0.70, 0.25)]
		if side < 0.0:
			tips.reverse()
		kit.loft(tips, col, side < 0.0, side > 0.0)
		# rib tapes across the top, every 30 cm
		var x := 0.75
		while x < 4.6:
			_rib_tape(kit, side * x, up_y(x), UP_LE, UP_C, col)
			x += 0.30
		# hand-hole cover and the inspection rings under the wing (dark dots)
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(side * 1.4, up_y(1.4) - 0.045, UP_LE + 0.5)), 0.05, 0.05, 0.004, 10, col.darkened(0.2))
	# leading-edge stripe of the trim colour across the centre section
	kit.box_at(Vector3(0, up_y(0.0) + 0.07, UP_LE + 0.35), Vector3(1.2, 0.005, 0.08), BROWN)


func _lower_wings(kit: MeshKit) -> void:
	var col := ORANGE
	var yf := func(a: float) -> float: return lo_y(a)
	for side in [-1.0, 1.0]:
		var le_f := func(_a: float) -> float: return LO_LE
		# the outboard trailing edge is the aileron: the fixed wing ends at its hinge
		var ch_f := func(a: float) -> float: return LO_C - (AIL_C if a > AIL_X0 - 0.01 and a < AIL_X1 + 0.01 else 0.0)
		_wing_run(kit, [ROOT_LO, 1.4, 2.53], yf, le_f, func(_a: float) -> float: return LO_C, side, col)
		_wing_run(kit, [2.53, 2.57], yf, le_f, func(a: float) -> float: return LO_C if a < 2.55 else LO_C - AIL_C, side, col)
		_wing_run(kit, [2.57, 3.6, 4.53], yf, le_f, ch_f, side, col)
		_wing_run(kit, [4.53, 4.6], yf, le_f, func(a: float) -> float: return LO_C - AIL_C if a < 4.55 else LO_C, side, col)
		var tips: Array = [_airfoil(side * 4.6, lo_y(4.6), LO_LE, LO_C),
			_airfoil(side * 4.78, lo_y(4.78), LO_LE + 0.05, LO_C - 0.12, 0.85),
			_airfoil(side * 4.88, lo_y(4.88), LO_LE + 0.16, LO_C - 0.36, 0.55),
			_airfoil(side * 4.92, lo_y(4.92), LO_LE + 0.32, LO_C - 0.70, 0.25)]
		if side < 0.0:
			tips.reverse()
		kit.loft(tips, col, side < 0.0, side > 0.0)
		# root fairing into the fuselage side, and the walkway (black non-slip)
		# on the left lower wing root where you climb up
		var root_cap: PackedVector3Array = _airfoil(side * ROOT_LO, lo_y(ROOT_LO), LO_LE, LO_C)
		for i in range(root_cap.size()):
			kit.tri(_centroid(root_cap), root_cap[i], root_cap[(i + 1) % root_cap.size()], col.darkened(0.1), Vector3(-side, 0, 0))
		if side < 0.0:
			kit.box(Transform3D(Basis(Vector3.BACK, deg_to_rad(LO_DIH)), Vector3(-0.85, lo_y(0.85) + 0.085, LO_LE + 0.62)), Vector3(0.75, 0.006, 0.62), Color(0.08, 0.08, 0.08))
		var x := 0.7
		while x < 4.6:
			_rib_tape(kit, side * x, lo_y(x), LO_LE, LO_C - (AIL_C if x > AIL_X0 and x < AIL_X1 else 0.0), col)
			x += 0.30


## A rib tape: a thin strip over the top of the wing along one rib.
func _rib_tape(kit: MeshKit, x: float, y: float, le: float, ch: float, col: Color) -> void:
	var prof: PackedVector3Array = _airfoil(x, y, le, ch)
	var n := prof.size()
	var half := (n + 1) / 2          # the upper surface runs TE -> LE in the first half
	for k in range(half - 1):
		var a: Vector3 = prof[k] + Vector3(0, 0.0025, 0)
		var b: Vector3 = prof[k + 1] + Vector3(0, 0.0025, 0)
		kit.quad(a + Vector3(-0.012, 0, 0), b + Vector3(-0.012, 0, 0), b + Vector3(0.012, 0, 0), a + Vector3(0.012, 0, 0), col.lightened(0.06), Vector3.UP)


## Spar points: front spar 25 % chord, rear spar 65 %.
static func _spar(upper: bool, ax: float, rear: bool) -> Vector3:
	if upper:
		return Vector3(ax, up_y(ax) + 0.03, UP_LE + UP_C * (0.65 if rear else 0.25))
	return Vector3(ax, lo_y(ax) + 0.03, LO_LE + LO_C * (0.65 if rear else 0.25))


func _struts_and_wires(kit: MeshKit) -> void:
	var strut_c := ORANGE.darkened(0.12)
	for side in [-1.0, 1.0]:
		var sx: float = side
		# interplane I-struts (front and rear spar) with the N-brace between
		var lf := _spar(false, STRUT_X, false) * Vector3(sx, 1, 1)
		var lr := _spar(false, STRUT_X, true) * Vector3(sx, 1, 1)
		var uf := _spar(true, STRUT_X - 0.08, false) * Vector3(sx, 1, 1)
		var ur := _spar(true, STRUT_X - 0.08, true) * Vector3(sx, 1, 1)
		_streamline(kit, lf, uf, 0.035, strut_c)
		_streamline(kit, lr, ur, 0.035, strut_c)
		_beam(kit, (lf + uf) * 0.5 + Vector3(0, -0.2, 0), (lr + ur) * 0.5 + Vector3(0, 0.2, 0), 0.012, strut_c, 5)
		# cabane struts: from the upper longerons up to the centre section, an N
		var cf := Vector3(sx * 0.36, 0.42, -0.70)
		var cr := Vector3(sx * 0.36, 0.42, -0.05)
		var tf := _spar(true, 0.52, false) * Vector3(sx, 1, 1)
		var tr := _spar(true, 0.52, true) * Vector3(sx, 1, 1)
		_streamline(kit, cf, tf, 0.024, strut_c)
		_streamline(kit, cr, tr, 0.024, strut_c)
		_beam(kit, cf, tr, 0.013, strut_c, 5)
		# flying wires (carry the lift: lower wing root up to the upper wing at
		# the struts) and landing wires (cabane top down to the lower wing at
		# the struts), doubled, streamline tie-rods
		for dz in [-0.03, 0.03]:
			var off := Vector3(0, 0, dz)
			_beam(kit, _spar(false, ROOT_LO + 0.08, false) * Vector3(sx, 1, 1) + off, uf + Vector3(-sx * 0.04, -0.03, 0) + off, 0.0045, WIRE, 4)
			_beam(kit, _spar(false, ROOT_LO + 0.08, true) * Vector3(sx, 1, 1) + off, ur + Vector3(-sx * 0.04, -0.03, 0) + off, 0.0045, WIRE, 4)
			_beam(kit, tf + Vector3(0, -0.03, 0) + off, lf + Vector3(-sx * 0.05, 0.02, 0) + off, 0.0045, WIRE, 4)
			_beam(kit, tr + Vector3(0, -0.03, 0) + off, lr + Vector3(-sx * 0.05, 0.02, 0) + off, 0.0045, WIRE, 4)
		# drag/anti-drag wire across the bay between the struts
		_beam(kit, uf + Vector3(-sx * 0.02, -0.02, 0), lr + Vector3(-sx * 0.02, 0.02, 0), 0.0035, WIRE, 4)
		# strut fittings
		for p in [lf, lr, uf, ur, tf, tr]:
			kit.box_at(p, Vector3(0.05, 0.03, 0.06), STEEL)
		# the aileron push-pull tube and bellcrank fairing on the lower wing
		kit.box_at(Vector3(sx * 2.4, lo_y(2.4) - 0.04, LO_LE + LO_C - AIL_C - 0.05), Vector3(0.09, 0.03, 0.12), STEEL)


## A streamlined strut: a teardrop section run from a to b.
func _streamline(kit: MeshKit, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := (b - a).normalized()
	var fwd := Vector3.FORWARD
	var x := d.cross(fwd).normalized()
	var z := x.cross(d).normalized()       # roughly aft
	var rings: Array = []
	for p in [a, b]:
		var ring := PackedVector3Array()
		for q in [Vector2(0, -w * 1.2), Vector2(w * 0.5, -w * 0.6), Vector2(w * 0.5, w * 0.6), Vector2(0, w * 2.2), Vector2(-w * 0.5, w * 0.6), Vector2(-w * 0.5, -w * 0.6)]:
			ring.append(p + x * q.x + z * q.y)
		rings.append(ring)
	kit.loft(rings, col, true, true)


## Fixed tail: the stabiliser (rounded, with struts under it and wires over),
## the fin, and the tailwheel spring.
func _tail(kit: MeshKit) -> void:
	var col := ORANGE
	var ty := 0.27
	var hinge_z := 4.86
	# stabiliser outline per side: (span x, z)
	var stab := [Vector2(0.06, 4.28), Vector2(0.6, 4.30), Vector2(1.05, 4.36), Vector2(1.38, 4.48), Vector2(1.52, 4.65), Vector2(1.55, hinge_z), Vector2(0.06, hinge_z)]
	for side in [-1.0, 1.0]:
		var pts: Array = []
		for q in stab:
			pts.append(Vector2(side * q.x, q.y))
		_flat_plate(kit, pts, ty, 0.055, col, false)
		# struts under the stabiliser to the fuselage bottom, wires over to the fin
		_beam(kit, Vector3(side * 0.75, ty - 0.02, 4.62), Vector3(side * 0.12, -0.05, 4.55), 0.014, col.darkened(0.15), 5)
		_beam(kit, Vector3(side * 0.75, ty + 0.03, 4.62), Vector3(0.02 * side, 0.95, 4.80), 0.004, WIRE, 4)
		_beam(kit, Vector3(side * 0.75, ty + 0.03, 4.80), Vector3(0.02 * side, 0.95, 4.98), 0.004, WIRE, 4)
	# fin: curved leading edge up to a rounded top
	var fin := [Vector2(ty + 0.02, 4.32), Vector2(0.48, 4.52), Vector2(0.72, 4.70), Vector2(0.95, 4.86), Vector2(1.10, 4.98), Vector2(1.17, 5.08), Vector2(1.18, 5.10), Vector2(ty, 5.10)]
	_flat_plate(kit, fin, 0.0, 0.05, col, true)
	# the rudder and elevator hinge posts / sternpost fitting
	kit.box_at(Vector3(0, ty, 5.10), Vector3(0.06, 0.06, 0.05), STEEL)
	# tailwheel spring: a leaf from the sternpost down to the fork
	_beam(kit, Vector3(0, -0.02, 4.75), Vector3(0, -0.20, 5.0), 0.022, STEEL, 5)


## A flat surface from an outline. Horizontal: points are (x, z) at height
## y; vertical: points are (y, z) in the centreline plane. Thickness `t`
## at the root edge, thinning toward the far edge, with a rounded rim.
func _flat_plate(kit: MeshKit, pts: Array, y: float, t: float, col: Color, vertical: bool) -> void:
	var top := PackedVector3Array()
	var bot := PackedVector3Array()
	var c := Vector2.ZERO
	for q in pts:
		c += q
	c /= float(pts.size())
	for q in pts:
		var qq: Vector2 = q
		var th := t * 0.5 * (0.45 + 0.55 * clampf(1.0 - absf(qq.x - (pts[0] as Vector2).x) / 1.6, 0.0, 1.0))
		if vertical:
			top.append(Vector3(th, qq.x, qq.y))
			bot.append(Vector3(-th, qq.x, qq.y))
		else:
			top.append(Vector3(qq.x, y + th, qq.y))
			bot.append(Vector3(qq.x, y - th, qq.y))
	var ct := Vector3(0, 0, 0)
	var cb := Vector3(0, 0, 0)
	for v in top:
		ct += v
	for v in bot:
		cb += v
	ct /= float(top.size())
	cb /= float(bot.size())
	var up := Vector3(1, 0, 0) if vertical else Vector3.UP
	for i in range(top.size()):
		var j := (i + 1) % top.size()
		kit.tri(ct, top[i], top[j], col, up)
		kit.tri(cb, bot[j], bot[i], col, -up)
		var mid := (top[i] + top[j]) * 0.5
		var out := mid - ct
		if vertical:
			out.x = 0.0
		else:
			out.y = 0.0
		kit.quad(top[i], top[j], bot[j], bot[i], col.darkened(0.05), out)


## The parts of the main gear that don't move: the fairing at the top of
## each oleo leg where it meets the lower wing root.
func _gear_fixed(kit: MeshKit) -> void:
	for side in [-1.0, 1.0]:
		kit.box_at(Vector3(side * 0.46, -0.60, -0.34), Vector3(0.10, 0.10, 0.16), STEEL)
		# split-axle hinge fittings under the fuselage centre line
		kit.box_at(Vector3(side * 0.06, -0.66, -0.55), Vector3(0.05, 0.05, 0.10), STEEL)
		kit.box_at(Vector3(side * 0.2, -0.65, 0.05), Vector3(0.05, 0.05, 0.08), STEEL)


# ------------------------------------------------------------------------------
#  Moving parts
# ------------------------------------------------------------------------------
func _build_moving_parts() -> void:
	# Oleo legs: drawn each frame from the wing-root fitting to the wheel
	# (plane_visual's _process); a streamlined leg with the chrome piston.
	_leg_tops = [Vector3(-0.46, -0.60, -0.34), Vector3(0.46, -0.60, -0.34)]
	for side in [-1.0, 1.0]:
		var lk := MeshKit.new()
		lk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.62, 0)), 0.045, 0.05, 0.62, 10, ORANGE.darkened(0.15), true)
		lk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -1.0, 0)), 0.03, 0.03, 0.40, 10, Color(0.85, 0.86, 0.88), true)
		lk.box_at(Vector3(0, -0.98, 0), Vector3(0.07, 0.04, 0.09), STEEL)
		var leg := lk.instance("Leg")
		add_child(leg)
		_legs.append(leg)
		# the axle strut to the centre-line hinge and the drag strut aft
		for k in range(2):
			var ak := MeshKit.new()
			ak.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -1.0, 0)), 0.022, 0.022, 1.0, 8, ORANGE.darkened(0.25), true)
			var am := ak.instance("AxleStrut")
			add_child(am)
			_axle_struts.append(am)
	var tilt_l := Basis(Vector3.BACK, deg_to_rad(-1.6))
	var tilt_r := Basis(Vector3.BACK, deg_to_rad(1.6))
	# No flaps on this one: the plane code still works the lever, it just has
	# nothing to move (flap_dcl 0).
	_flap_l = _hinged_panel("FlapL", Vector3(-1.0, -5.0, 0.0), Vector3(0.01, 0.01, 0.01), ORANGE)
	_flap_r = _hinged_panel("FlapR", Vector3(1.0, -5.0, 0.0), Vector3(0.01, 0.01, 0.01), ORANGE)
	_flap_l.visible = false
	_flap_r.visible = false
	# Ailerons on the lower wings, hinged at the fixed trailing edge.
	var ac := (AIL_X0 + AIL_X1) * 0.5
	var hz := LO_LE + LO_C - AIL_C
	_ail_l = _hinged_panel("AileronL", Vector3(-ac, lo_y(ac) + 0.035, hz), Vector3(AIL_X1 - AIL_X0 - 0.02, 0.08, AIL_C), ORANGE, tilt_l)
	_ail_r = _hinged_panel("AileronR", Vector3(ac, lo_y(ac) + 0.035, hz), Vector3(AIL_X1 - AIL_X0 - 0.02, 0.08, AIL_C), ORANGE, tilt_r)
	# Elevator (one piece across, cut out round the rudder) and rudder.
	_elevator = _outline_panel("Elevator", Vector3(0, 0.27, 4.86), [Vector2(-1.55, 0.0), Vector2(-1.52, 0.18), Vector2(-1.35, 0.36), Vector2(-1.0, 0.44),
		Vector2(-0.30, 0.45), Vector2(-0.10, 0.30), Vector2(-0.05, 0.10), Vector2(0.05, 0.10), Vector2(0.10, 0.30), Vector2(0.30, 0.45),
		Vector2(1.0, 0.44), Vector2(1.35, 0.36), Vector2(1.52, 0.18), Vector2(1.55, 0.0)], false, 0.05, ORANGE)
	_rudder = _outline_panel("Rudder", Vector3(0, 0.0, 5.10), [Vector2(1.18, 0.0), Vector2(1.17, 0.14), Vector2(1.08, 0.30), Vector2(0.90, 0.40),
		Vector2(0.55, 0.44), Vector2(0.18, 0.42), Vector2(-0.02, 0.32), Vector2(-0.06, 0.12), Vector2(-0.05, 0.0)], true, 0.05, ORANGE)
	# trim tab on the elevator and the rudder's red-white-blue stripes? No:
	# a plain trim-colour band across the rudder.
	var band := MeshKit.new()
	band.box_at(Vector3(0, 0.72, 0.22), Vector3(0.056, 0.10, 0.42), BROWN)
	_rudder.add_child(band.instance("RudderBand"))

	# Wheels (as plane_visual): the mains get the biplane tyres.
	for i in range(3):
		var pivot := Node3D.new()
		pivot.name = "Wheel%d" % i
		pivot.position = plane.hub_rest[i] if plane != null else (load("res://scripts/plane_types.gd").TYPES["biplane"]["hubs"][i] as Vector3)
		var squash := Node3D.new()
		squash.name = "Squash"
		var spinner := Node3D.new()
		spinner.name = "Spin"
		squash.add_child(spinner)
		pivot.add_child(squash)
		_tyres.append(squash)
		add_child(pivot)
		_wheels.append(pivot)
		_wheel_rest.append(pivot.position)
	_set_tyre_mesh(2, 0.11, 0.07)
	if plane != null:
		_fit_tyres()
	else:
		_set_tyre_mesh(0, 0.36, 0.19)
		_set_tyre_mesh(1, 0.36, 0.19)
	_build_cowl()

	# Propeller: a two-blade metal prop, no spinner, the hub's bolts showing.
	_prop = Node3D.new()
	_prop.name = "Prop"
	_prop.position = Vector3(0, 0, -2.28)
	add_child(_prop)
	var hk := MeshKit.new()
	hk.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 0.06)), 0.11, 0.11, 0.12, 14, STEEL)
	hk.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.06)), 0.09, 0.05, 0.08, 14, STEEL.lightened(0.1))
	for k in range(6):
		var a := TAU * float(k) / 6.0
		hk.box_at(Vector3(cos(a) * 0.085, sin(a) * 0.085, 0.0), Vector3(0.02, 0.02, 0.02), Color(0.3, 0.3, 0.3))
	hk.smooth(50.0)
	_prop.add_child(hk.instance("Hub"))
	_prop_blades = MeshInstance3D.new()
	_prop_blades.name = "Blades"
	_prop.add_child(_prop_blades)
	_build_blades(0)
	_prop_disc = MeshInstance3D.new()
	_prop_disc.name = "Disc"
	var disc := CylinderMesh.new()
	disc.top_radius = 1.25
	disc.bottom_radius = 1.25
	disc.height = 0.01
	disc.radial_segments = 28
	disc.rings = 1
	_prop_disc.mesh = disc
	_prop_disc.rotation = Vector3(PI * 0.5, 0, 0)
	_prop_disc.position = Vector3(0, 0, -0.02)
	var dm := StandardMaterial3D.new()
	_disc_mat = dm
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.15, 0.15, 0.15, 0.16)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_prop_disc.material_override = dm
	_prop_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop.add_child(_prop_disc)


## A control surface with a drawn outline: points are (span, distance aft
## of the hinge line). Built round its hinge so it swings about it.
func _outline_panel(node_name: String, hinge: Vector3, pts: Array, vertical: bool, t: float, col: Color) -> Node3D:
	var pivot := Node3D.new()
	_surface_rest[node_name] = hinge
	pivot.name = node_name
	pivot.position = hinge
	var kit := MeshKit.new()
	var top := PackedVector3Array()
	var bot := PackedVector3Array()
	var maxd := 0.01
	for q in pts:
		maxd = maxf(maxd, (q as Vector2).y)
	for q in pts:
		var qq: Vector2 = q
		var th := t * 0.5 * clampf(1.0 - qq.y / (maxd * 1.15), 0.12, 1.0)
		if vertical:
			top.append(Vector3(th, qq.x, qq.y))
			bot.append(Vector3(-th, qq.x, qq.y))
		else:
			top.append(Vector3(qq.x, th, qq.y))
			bot.append(Vector3(qq.x, -th, qq.y))
	# close along the hinge line with a rounded nose
	var c := Vector3.ZERO
	for v in top:
		c += v
	c /= float(top.size())
	var cb := Vector3(-c.x, c.y, c.z) if vertical else Vector3(c.x, -c.y, c.z)
	var up := Vector3(1, 0, 0) if vertical else Vector3.UP
	for i in range(top.size()):
		var j := (i + 1) % top.size()
		kit.tri(c, top[i], top[j], col, up)
		kit.tri(cb, bot[j], bot[i], col, -up)
		var out := (top[i] + top[j]) * 0.5 - c
		if vertical:
			out.x = 0.0
		else:
			out.y = 0.0
		kit.quad(top[i], top[j], bot[j], bot[i], col.darkened(0.05), out)
	# rib tapes on the fabric
	pivot.add_child(kit.instance("Panel"))
	add_child(pivot)
	return pivot


## Two metal blades, about 2.5 m across, yellow tips; bent the same way as
## plane_visual's when damaged.
func _build_blades(state: int) -> void:
	_prop_state = state
	var curls := [[0.0, 0.0], [0.22, 0.0], [0.95, 0.35], [1.45, 1.15]]
	var tips := [[0.62, 0.62], [0.52, 0.62], [0.58, 0.62], [0.36, 0.46]]
	var kit := MeshKit.new()
	var blade := Color(0.62, 0.63, 0.64)
	for k in range(2):
		var spin := Basis(Vector3.BACK, PI * float(k))
		var root := Transform3D(spin * Basis(Vector3.UP, 0.30), Vector3.ZERO)
		# root to mid: a tapered blade, widest a third of the way out
		kit.box(root * Transform3D(Basis.IDENTITY, Vector3(0, 0.36, -0.05)), Vector3(0.17, 0.56, 0.022), blade)
		var joint := root * Transform3D(Basis(Vector3.RIGHT, curls[state][k]), Vector3(0, 0.64, -0.05))
		var tl: float = tips[state][k]
		kit.box(joint * Transform3D(Basis.IDENTITY, Vector3(0, tl * 0.5, 0)), Vector3(0.15, tl, 0.02), blade)
		if tl > 0.6:
			kit.box(joint * Transform3D(Basis.IDENTITY, Vector3(0, tl - 0.06, 0)), Vector3(0.152, 0.12, 0.024), Color(0.95, 0.80, 0.12))
	_prop_blades.mesh = kit.commit()


# ------------------------------------------------------------------------------
#  The radial: 7 cylinders out in the air, pushrods in front, intake pipes
#  behind, exhaust stubs into a collector ring, the ignition harness
# ------------------------------------------------------------------------------
func _build_cowl() -> void:
	if plane != null:
		plane.set_meta("visual", self)
	engine_parts = null
	var ek := MeshKit.new()
	var z := ENG_Z
	# crankcase, nose case and the rear (intake) section
	ek.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, z + 0.10)), 0.22, 0.22, 0.20, 14, CASE_C, true)
	ek.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, z - 0.10)), 0.19, 0.10, 0.22, 14, CASE_C.lightened(0.05), true)
	ek.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, z + 0.36)), 0.25, 0.24, 0.26, 14, CASE_C.darkened(0.1), true)
	ek.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, z - 0.32)), 0.05, 0.05, 0.12, 10, STEEL)
	# the engine mount: a steel-tube ring and struts back to the firewall
	for k in range(4):
		var a := TAU * (float(k) + 0.5) / 4.0
		var rp := Vector3(sin(a) * 0.26, cos(a) * 0.26, z + 0.30)
		var fp := Vector3(sin(a) * 0.34, cos(a) * 0.34, -1.52)
		_beam(ek, rp, fp, 0.016, Color(0.15, 0.15, 0.16), 5)
	# magnetos and the carburettor under the rear section
	for mx in [-0.12, 0.12]:
		ek.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(mx, 0.14, z + 0.48)), 0.05, 0.05, 0.12, 10, Color(0.12, 0.12, 0.13), true)
	ek.box_at(Vector3(0, -0.30, z + 0.42), Vector3(0.14, 0.14, 0.12), STEEL)
	ek.box_at(Vector3(0, -0.40, z + 0.40), Vector3(0.18, 0.06, 0.20), Color(0.2, 0.2, 0.2))       # air scoop
	for k in range(CYL_N):
		var a := TAU * float(k) / float(CYL_N)
		var d := Vector3(sin(a), cos(a), 0)
		var tng := Vector3(cos(a), -sin(a), 0)
		var cb := Basis(tng, d, Vector3(0, 0, 1))
		# barrel with fins
		ek.cylinder(Transform3D(cb, d * 0.20 + Vector3(0, 0, z)), 0.066, 0.066, 0.22, 10, CYL_C, true)
		var r := 0.235
		while r < 0.40:
			ek.cylinder(Transform3D(cb, d * r + Vector3(0, 0, z)), 0.090, 0.090, 0.006, 12, CYL_C, true)
			r += 0.018
		# head: bigger, bare aluminium, deep fins, rocker boxes on top
		ek.cylinder(Transform3D(cb, d * 0.40 + Vector3(0, 0, z)), 0.078, 0.07, 0.12, 10, HEAD_C, true)
		r = 0.405
		while r < 0.50:
			var fr := lerpf(0.105, 0.075, (r - 0.405) / 0.1)
			ek.cylinder(Transform3D(cb, d * r + Vector3(0, 0, z)), fr, fr, 0.005, 12, HEAD_C, true)
			r += 0.016
		for side2 in [-1.0, 1.0]:
			var rb: Vector3 = d * 0.50 + tng * float(side2) * 0.045 + Vector3(0, 0, z - 0.03)
			ek.box(Transform3D(cb, rb), Vector3(0.05, 0.05, 0.08), HEAD_C.lightened(0.08))
			# pushrod tube from the crankcase front up to the rocker box
			_beam(ek, d * 0.21 + tng * side2 * 0.03 + Vector3(0, 0, z - 0.09), rb + Vector3(0, 0, -0.03), 0.010, STEEL.lightened(0.2), 5)
		# spark plug lead from the ignition ring to the front of the head
		_beam(ek, d * 0.26 + Vector3(0, 0, z - 0.12), d * 0.45 + Vector3(0, 0, z - 0.07), 0.006, Color(0.75, 0.70, 0.55), 4)
		# intake pipe from the rear section to the back of the cylinder
		_beam(ek, d * 0.24 + Vector3(0, 0, z + 0.26), d * 0.38 + Vector3(0, 0, z + 0.05), 0.020, STEEL, 6)
		# exhaust stub from the head's back into the collector ring
		_beam(ek, d * 0.47 + tng * 0.03 + Vector3(0, 0, z + 0.05), d * 0.50 + Vector3(0, 0, z + 0.24), 0.024, Color(0.36, 0.26, 0.20), 6)
	# ignition harness ring on the nose case
	_ring_tube(ek, Vector3(0, 0, z - 0.12), 0.26, 0.012, Color(0.80, 0.72, 0.45), 21)
	# collector ring behind the cylinders, and its outlet down the right side
	_ring_tube(ek, Vector3(0, 0, z + 0.24), 0.50, 0.04, Color(0.36, 0.26, 0.20), 21)
	var out0 := Vector3(sin(TAU * 0.40) * 0.50, cos(TAU * 0.40) * 0.50, z + 0.24)
	_beam(ek, out0, Vector3(0.36, -0.60, -1.05), 0.055, Color(0.30, 0.22, 0.17), 8)
	_beam(ek, Vector3(0.36, -0.60, -1.05), Vector3(0.40, -0.66, -0.55), 0.055, Color(0.30, 0.22, 0.17), 8)
	ek.smooth(30.0)
	var em := ek.instance("Engine")
	add_child(em)


## A ring of tube (a polygon of short beams) round the thrust axis.
func _ring_tube(kit: MeshKit, c: Vector3, r: float, tube: float, col: Color, n: int) -> void:
	for k in range(n):
		var a0 := TAU * float(k) / float(n)
		var a1 := TAU * float(k + 1) / float(n)
		_beam(kit, c + Vector3(sin(a0) * r, cos(a0) * r, 0), c + Vector3(sin(a1) * r, cos(a1) * r, 0), tube, col, 6)


func _build_doors() -> void:
	pass       # open cockpits: you climb in over the side


func _build_cockpit() -> void:
	cockpit = BiCockpit.new()
	cockpit.name = "Cockpit"
	add_child(cockpit)
	_fill_cockpit.call_deferred(cockpit)


func _build_effects() -> void:
	super._build_effects()
	_smoke.position = Vector3(0.40, -0.66, -0.55)
	_smoke.direction = Vector3(0.1, -0.3, 1.0)
	for k in range(_mist.size()):
		_mist[k].position = Vector3((-1.0 if k == 0 else 1.0) * 0.35, up_y(0.35) - 0.05, -0.35)


# ------------------------------------------------------------------------------
#  Damage shapes: both wings sag together (they're braced to each other)
# ------------------------------------------------------------------------------
func _wing_bend(p: Vector3) -> Vector3:
	return _bi_flex(p) + _crash_deform(p)


func _bi_flex(p: Vector3) -> Vector3:
	var ax := absf(p.x)
	if ax < 0.6:
		return Vector3.ZERO
	var side_i := 0 if p.x < 0.0 else 1
	if plane != null and plane.wing_off[side_i]:
		var cut := 2.2 + 0.4 * DentMesh._hash(Vector3(0, snappedf(p.y, 0.05), snappedf(p.z, 0.08)))
		if ax > cut and (p.y > 0.9 or p.y < -0.2):
			var sgn := -1.0 if p.x < 0.0 else 1.0
			var torn := DentMesh._hash(p)
			return Vector3(sgn * (cut - ax) + sgn * torn * 0.12, (torn - 0.5) * 0.18, (DentMesh._hash(p * 1.7) - 0.5) * 0.1)
	var amt := _droop.x if p.x < 0.0 else _droop.y
	if absf(amt) < 0.002:
		return Vector3.ZERO
	var t := (ax - 0.6) / 4.3
	return Vector3(0.0, -amt * t * t, 0.0)


func _droop_at(x: float) -> float:
	var amt := _droop.x if x < 0.0 else _droop.y
	var t := (absf(x) - 0.6) / 4.3
	return amt * t * t


func _wing_piece(side: float) -> Array:
	var c := Vector3(side * 3.6, 0.35, 0.0)
	var kit := MeshKit.new()
	for upper in [true, false]:
		var secs: Array = []
		for ax in [2.4, 3.6, 4.7]:
			var sec := _airfoil(side * ax, up_y(ax) if upper else lo_y(ax), UP_LE if upper else LO_LE, UP_C if upper else LO_C)
			var moved := PackedVector3Array()
			for q in sec:
				moved.append(q - c)
			secs.append(moved)
		if side < 0.0:
			secs.reverse()
		kit.loft(secs, ORANGE, true, true)
	var lf := _spar(false, STRUT_X, false) * Vector3(side, 1, 1) - c
	var uf := _spar(true, STRUT_X - 0.08, false) * Vector3(side, 1, 1) - c
	_beam(kit, lf, uf, 0.035, ORANGE.darkened(0.12), 6)
	kit.smooth(35.0)
	return [kit.commit(), c]


func _process(delta: float) -> void:
	super._process(delta)
	if plane == null or _axle_struts.size() < 4:
		return
	# the split axle: from each hub in to the centre-line hinge, and a drag
	# strut back to the fuselage, both following the wheel up and down
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var hub: Vector3 = _wheels[i].position + Vector3(-side * 0.13, 0, 0)
		_strut_between(_axle_struts[i * 2], Vector3(side * 0.06, -0.66, -0.55), hub)
		_strut_between(_axle_struts[i * 2 + 1], Vector3(side * 0.20, -0.65, 0.05), hub)


func _strut_between(m: MeshInstance3D, top: Vector3, bottom: Vector3) -> void:
	var d := top - bottom
	var length := d.length()
	if length < 0.01:
		return
	var y := d / length
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.001:
		x = Vector3.RIGHT
	var z := x.cross(y)
	m.transform = Transform3D(Basis(x, y * length, z), top)
