extends Node3D
## THE SUPER CUB (DESIGN_NOTES 210): a rough bush PA-18 type, built to scale
## from the 3-view (reference/supercub/00_3view.jpg) and the bush photos
## (01, 02): 10.73 m span, 6.88 m long, 1.60 m chord, fabric over a steel
## tube frame, V-struts with jury struts, split door on the right, skylight,
## a four-cylinder flat engine under a nose bowl with two round inlets, a
## two-blade metal prop, tundra tyres on the bungee gear, a sprung tailwheel.
## Measured off the side view at 162.8 px per metre (enlarged crop):
##   z = (x - 285) / 162.8 - 0.40, y = (300 - y_px) / 162.8 (thrust line = 0)
## Everything the truck taught: one-piece lofted skins, the paint shader,
## every component its own breakable part, real glass lamps, tyre squash.
## -Z forward, Y up, origin at the wing's quarter chord on the centreline.

const MeshKit = preload("res://scripts/meshkit.gd")
const TyreMesh = preload("res://scripts/tyre_mesh.gd")
const PAINT := preload("res://shaders/truck_paint.gdshader")
const TYRE_SQUASH := preload("res://shaders/tyre_squash.gdshader")

const SPAN_HALF := 5.365                # 35 ft 2.5 in
const CHORD := 1.60                     # 5 ft 3 in, constant
const LE_Z := -0.40
const WING_Y := 0.685                   # chord line (the wing's flat bottom meets the cabin top at 0.645)
const DIHEDRAL := 0.0175                # 1 deg
const ROOT_X := 0.36                    # where the wing meets the cabin
const PROP_AT := Vector3(0.0, 0.0, -1.86)
const PROP_R := 0.98                    # a long bush prop
const AXLE := Vector3(1.00, -1.21, -0.36)   # 3-view axle, gear extended 2 in, wider track for the big tyres (ref 03)
const TAIL_HUB := Vector3(0.0, -0.14, 4.80)
const TYRE_R := 0.39                    # 31 in tundra tyres
const TYRE_W := 0.34
const TAILTYRE_R := 0.10
const STRUT_X := 3.25                   # strut fittings on the wing
const SPAR_F := 0.20                    # spar positions (fraction of chord)
const SPAR_R := 0.66
const JURY_X := 1.78
const WheeledBody = preload("res://scripts/wheeled_body.gd")
const GROUND_OFF := 1.60                # plane frame -> body frame (the mains' contact patch at y 0)

var terrain: Object
var yaw := 0.0
var base := Color(0.87, 0.86, 0.80)     # old white dope, gone a bit cream (photos 01/02)
var stripe := Color(0.62, 0.07, 0.05)   # faded red
var wing_top := Color(0.66, 0.09, 0.06)
var _root: Node3D
var body: WheeledBody                   # ground handling: taxi, bounce on the bungees, tyres squash under load
var test_drive := false
var tyre_psi := 10.0                    # tundra tyres run soft: 6-15 psi (Dave: variable air pressure)
var _prop: Node3D
var _wheels: Array = []


func display_name() -> String:
	return "Super Cub"


func build() -> void:
	if _root != null:
		_root.queue_free()
	_anims = []
	_caps = []
	_root = Node3D.new()
	_root.name = "Body"            # vehicle_breakage finds its parts under "Body"
	_root.position = Vector3(0, GROUND_OFF, 0)
	add_child(_root)
	MeshKit.detail = 1.0
	_fuselage()
	_cowl()
	_prop_hub()
	_windows_and_doors()
	_center_section()
	for s: float in [-1.0, 1.0]:
		_wing(s)
		_struts(s)
		_main_gear(s)
	_tail()
	_tail_gear()
	_lights()
	_cabin()
	_details()
	_baggage_door()
	_join_components()
	_sounds()
	var ll := SpotLight3D.new()
	ll.name = "LandingLight"
	ll.position = Vector3(-2.4, _wing_y(2.4), LE_Z - 0.05)
	ll.rotation = Vector3(-0.12, 0, 0)       # down a touch: it lights the strip ahead when the tail's down
	ll.spot_range = 90.0
	ll.spot_angle = 16.0
	ll.spot_attenuation = 0.6
	ll.light_energy = 10.0
	ll.shadow_enabled = true
	ll.light_color = Color(1.0, 0.92, 0.78)
	ll.visible = false
	_root.add_child(ll)
	var tl := SpotLight3D.new()           # the taxi light: wider, shorter, aimed lower
	tl.name = "TaxiLight"
	tl.position = Vector3(2.4, _wing_y(2.4), LE_Z - 0.05)
	tl.rotation = Vector3(-0.22, 0, 0)
	tl.spot_range = 40.0
	tl.spot_angle = 30.0
	tl.light_energy = 6.0
	tl.light_color = Color(1.0, 0.92, 0.78)
	tl.visible = false
	_root.add_child(tl)
	var pl := OmniLight3D.new()           # the panel light under the glareshield: lights the dash at night
	pl.name = "PanelLight"
	pl.position = Vector3(0, 0.33, PANEL_Z + 0.08)
	pl.omni_range = 0.55
	pl.light_energy = 0.7
	pl.light_color = Color(1.0, 0.82, 0.62)
	pl.shadow_enabled = false
	pl.light_specular = 0.0                # (no hot spot of it mirrored in the windshield - Dave saw two bright dots)
	pl.visible = false
	_root.add_child(pl)
	for lj in [["LandingLight", "WingL"], ["TaxiLight", "WingR"], ["PanelLight", "Cockpit"]]:
		var ln := _root.get_node_or_null(String(lj[0])) as Node3D
		var lt := _root.get_node_or_null(String(lj[1])) as Node3D
		if ln != null and lt != null:
			ln.reparent(lt, true)


## On the ground: a WheeledBody on the two mains and the tailwheel (the
## tailwheel's contact is matched with a virtual wheel the mains' size), the
## bungees as the springs, the prop's pull as the "drive" on the mains for
## taxiing, the tailwheel steers. It settles tail-down by itself.
func park(xf: Transform3D) -> void:
	body = WheeledBody.new()
	body.mass_empty = 640.0                 # empty + pilot + some fuel
	body.com = Vector3(0, GROUND_OFF + 0.15, 0.12)
	body.size = Vector3(3.5, 2.2, 6.9)
	body.wheel_r = TYRE_R
	body.travel = 0.16                       # the bungee gear's stroke
	body.spring_mul = 1.6
	body.power = 60000.0
	body.top_speed = 14.0
	body.brake_force = 5000.0
	body.max_steer = 0.45
	body.mu = 0.85
	for sx: float in [-1.0, 1.0]:
		body.wheels.append([Vector3(sx * AXLE.x, AXLE.y + GROUND_OFF, AXLE.z), false, true])
	body.wheels.append([Vector3(0, TAIL_HUB.y - TAILTYRE_R + TYRE_R + GROUND_OFF, TAIL_HUB.z), true, false])
	body.ground_y = func(x: float, z: float) -> float: return terrain.height_at(x, z) if terrain != null and terrain.has_method("height_at") else 0.0
	body.setup()
	body._hull = _hull_points()
	var o := xf.origin
	o.y = (terrain.height_at(o.x, o.z) if terrain != null and terrain.has_method("height_at") else 0.0) + 0.6
	body.place(Transform3D(xf.basis, o))
	body.settle()
	global_transform = body.transform()
	yaw = body.yaw()
	_animate()


## Where it hits the ground if it goes over: the belly, the cowl, the tail,
## the wing tips and the fin (body frame).
func _hull_points() -> Array:
	var out: Array = []
	for z: float in [-1.7, -1.0, -0.4, 0.4, 1.2, 2.4, 3.6, 4.6]:
		var sec := _sec_at(z)
		for sx: float in [-1.0, 1.0]:
			out.append(Vector3(sx * float(sec[0]), float(sec[1]) + GROUND_OFF, z))
			out.append(Vector3(sx * float(sec[0]) * 0.8, float(sec[2]) + GROUND_OFF, z))
	for sx2: float in [-1.0, 1.0]:
		for zz: float in [LE_Z, LE_Z + CHORD]:
			out.append(Vector3(sx2 * SPAN_HALF * 0.98, _wing_y(SPAN_HALF) + GROUND_OFF, zz))
			out.append(Vector3(sx2 * 2.5, _wtop(2.5, zz) + GROUND_OFF, zz))
	out.append(Vector3(0, 1.62 + GROUND_OFF, 4.5))
	out.append(Vector3(0, PROP_AT.y - PROP_R + GROUND_OFF, PROP_AT.z))
	return out


## The wheels follow the body: they ride up on the bungees, turn as it rolls,
## the tailwheel swivels, and the tyres flatten under their share of the weight.
var _sq := [0.045, 0.045]


func _animate() -> void:
	if body == null:
		return
	var names := ["WheelL", "WheelR", "TailWheel"]
	for i in range(3):
		var wn := _root.get_node_or_null(names[i]) as Node3D
		if wn == null:
			continue
		var c: float = body.compress[i] if i < body.compress.size() else 0.0
		var hub: Vector3 = Vector3(-AXLE.x, AXLE.y, AXLE.z) if i == 0 else (Vector3(AXLE.x, AXLE.y, AXLE.z) if i == 1 else TAIL_HUB)
		var up := 0.0          # the wheel stays on its axle (the gear legs are rigid; the bungees are inside)
		var spin: float = body.wheel_spin[i] if i < body.wheel_spin.size() else 0.0
		var b := Basis(Vector3.RIGHT, spin)
		if i == 2:
			b = Basis(Vector3.UP, -body.steer) * b
		wn.transform = Transform3D(b, hub + Vector3(0, up, 0))
		var mi := wn.get_child(0) as MeshInstance3D
		if mi != null and i < 2:
			# softer tyres flatten more: the flat spot grows as the pressure drops
			var soft := clampf(10.0 / maxf(tyre_psi, 2.0), 0.35, 3.0)
			# clamped and eased: a jolt on the first roll spiked the compression and
			# the shader flung the rubber out into a black cloud round the wheel (Dave)
			var want := clampf((0.015 + clampf(c, 0.0, 1.2) * 0.06) * soft, 0.0, 0.10)
			_sq[i] = lerpf(_sq[i], want, 0.25)
			mi.set_instance_shader_parameter("squash", _sq[i])
			mi.set_instance_shader_parameter("down_dir", Vector3.DOWN)    # the ground's down, not the plane's (it sits 14 deg nose up)


func eye_xf() -> Transform3D:
	return _root.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.47, -0.02))   # front seat: sat down on the cushion (the head had been up in the wing root), feet on the pedals


func seat_clip() -> String:
	return "cub_seat"


func cab_yaw() -> float:
	return yaw


# ------------------------------------------------------------------------------
#  Parts and materials
# ------------------------------------------------------------------------------
class Part:
	var node: Node3D
	var paint := MeshKit.new()
	var dark := MeshKit.new()
	var metal := MeshKit.new()
	var glass := MeshKit.new()


func _part(nm: String, parent: Node3D = null) -> Part:
	var p := Part.new()
	p.node = Node3D.new()
	p.node.name = nm
	p.node.set_meta("part", true)
	(parent if parent != null else _root).add_child(p.node)
	return p


func _done(p: Part) -> void:
	p.paint.smooth(36.0)
	p.dark.smooth(40.0)
	p.metal.smooth(50.0)
	_add(p.node, p.paint, "Paint", _paint_mat())
	_add(p.node, p.dark, "Trim", _mat(Color.WHITE, 0.7, 0.0))
	_add(p.node, p.metal, "Metal", _mat(Color.WHITE, 0.3, 0.85))
	var gm := _mat(Color(0.12, 0.15, 0.18, 0.45), 0.03, 0.0)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.metallic_specular = 1.0
	_add(p.node, p.glass, "Glass", gm)


func _add(n: Node3D, k: RefCounted, nm: String, m: Material) -> void:
	if k.is_empty():
		return
	var mi: MeshInstance3D = k.instance(nm)
	mi.material_override = m
	n.add_child(mi)


func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	return m


var _pm: ShaderMaterial
func _paint_mat() -> ShaderMaterial:
	if _pm != null:
		return _pm
	var m := ShaderMaterial.new()
	m.shader = PAINT
	m.set_shader_parameter("paint_a", base)
	m.set_shader_parameter("paint_b", stripe)
	m.set_shader_parameter("two_tone", true)
	m.set_shader_parameter("tone_lo", -0.05)        # the red band down the fuselage side (photo 02)
	m.set_shader_parameter("tone_hi", 0.05)
	m.set_shader_parameter("dust", 0.30)
	m.set_shader_parameter("dust_top", -0.30)        # mud and oil only on the belly
	m.set_shader_parameter("rough", 0.62)           # doped fabric: satin, not gloss
	m.set_shader_parameter("ripple_k", 0.0)
	_pm = m
	return m


const BANDED := Color(1, 1, 1, 0)


func _fix(c: Color) -> Color:          # a fixed colour through the paint shader (alpha 1)
	return Color(c.r, c.g, c.b, 1.0)


# ------------------------------------------------------------------------------
#  Fuselage: fabric over the tube frame - flat sides and belly, the stringered
#  turtledeck on top; the long straight top line and the belly sweeping up
#  to the tail post (3-view side)
# ------------------------------------------------------------------------------
## [z, half width, bottom y, top y, squareness]
const SECTIONS := [
	[-1.01, 0.385, -0.53, 0.235, 4.0],   # firewall (cowl covers ahead of this)
	[-0.80, 0.385, -0.62, 0.36, 4.5],    # windshield foot rising
	[-0.40, 0.380, -0.645, 0.645, 5.0],  # wing leading edge: cabin full height
	[0.40, 0.380, -0.645, 0.645, 5.0],
	[1.20, 0.360, -0.51, 0.625, 4.4],    # wing trailing edge, belly sweeping up
	[1.54, 0.340, -0.46, 0.61, 3.8],
	[2.40, 0.290, -0.33, 0.58, 3.2],
	[3.62, 0.190, -0.15, 0.54, 2.8],     # fin leading edge
	[4.45, 0.075, -0.02, 0.53, 2.6],
	[4.62, 0.035, 0.00, 0.52, 2.4],      # tail post
]


static func _section(hw: float, yb: float, yt: float, n: float, z: float, pts: int = 28) -> PackedVector3Array:
	# flat sides and belly; the top half rounder (stringers over the turtledeck),
	# the sides drawn in a little toward the top (tumblehome)
	var ring := PackedVector3Array()
	var cy := (yb + yt) * 0.5
	var hh := (yt - yb) * 0.5
	for i in range(pts):
		var a := TAU * float(i) / float(pts)
		var c := cos(a)
		var s := sin(a)
		var e := n if s < 0.0 else maxf(n * 0.55, 2.0)
		var y := signf(s) * pow(absf(s), 2.0 / e) * hh
		var tumble := 1.0 - 0.10 * clampf(y / maxf(hh, 0.01), 0.0, 1.0)
		var x := signf(c) * pow(absf(c), 2.0 / e) * hw * tumble
		ring.append(Vector3(x, cy + y, z))
	return ring


func _sec_at(z: float) -> Array:
	for i in range(SECTIONS.size() - 1):
		var a: Array = SECTIONS[i]
		var b: Array = SECTIONS[i + 1]
		if z >= float(a[0]) and z <= float(b[0]):
			var f := (z - float(a[0])) / (float(b[0]) - float(a[0]))
			return [lerpf(a[1], b[1], f), lerpf(a[2], b[2], f), lerpf(a[3], b[3], f), lerpf(a[4], b[4], f)]
	var l: Array = SECTIONS[SECTIONS.size() - 1]
	return [l[1], l[2], l[3], l[4]]


func _fuselage() -> void:
	var p := _part("Fuselage")
	var rings: Array = []
	var z := -1.01
	while z < 4.62:
		var sec := _sec_at(z)
		rings.append(_section(sec[0], sec[1], sec[2], sec[3], z))
		z += 0.12
	var l := _sec_at(4.62)
	rings.append(_section(l[0], l[1], l[2], l[3], 4.62))
	p.paint.loft(rings, BANDED, false, true)      # no cap at the firewall end: from the cockpit it showed as a white band round the panel
	# fabric over tubes: the stringers show through on the turtledeck, the
	# longerons and the diagonal tubes press faint lines in the side fabric;
	# the rib-stitch tapes run along the lower longeron
	for s: float in [-1.0, 1.0]:
		for frac: float in [0.08, 0.92]:
			var line: Array = []
			for zz: float in [-0.95, -0.4, 0.4, 1.2, 1.54, 2.4, 3.62, 4.45]:
				var sec2 := _sec_at(zz)
				var yy: float = lerpf(sec2[1], sec2[2], frac)
				line.append(Vector3(s * (sec2[0] * (1.0 - 0.10 * clampf((frac - 0.5) * 2.0, 0.0, 1.0)) + 0.002), yy, zz))
			_tube(p.paint, line, 0.0025, _fix(base.darkened(0.03)))
	# the dark pinstripes along the red band (photo 01)
	for s4: float in [-1.0, 1.0]:
		for yy4: float in [-0.068, 0.068]:
			var ps: Array = []
			var zz4 := -1.0
			while zz4 < 4.5:
				ps.append(Vector3(s4 * (_side_x(zz4, yy4) + 0.0025), yy4, zz4))
				zz4 += 0.25
			_tube(p.paint, ps, 0.0035, _fix(Color(0.08, 0.08, 0.08)))
	# inspection rings (the plastic rings stuck on the fabric), tie-down at the tail
	for ins in [Vector3(-1, 0.10, 2.9), Vector3(1, 0.10, 2.9), Vector3(-1, 0.05, 4.05), Vector3(1, 0.05, 4.05)]:
		var sz := _sec_at(ins.z)
		p.dark.cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5 * ins.x), Vector3(ins.x * (float(sz[0]) + 0.001), ins.y, ins.z)), 0.045, 0.045, 0.004, 16, Color(0.75, 0.74, 0.70), true)
	_tie_ring(p.metal, Vector3(0, float(_sec_at(4.40)[1]), 4.40))      # under the tail post
	# the belly: stringer lines and the antenna
	_tube(p.dark, [Vector3(0, -0.66, 0.6), Vector3(0, -0.84, 0.82)], 0.004, Color(0.08, 0.08, 0.08))
	_done(p)
	var fm := _paint_mat().duplicate() as ShaderMaterial
	var cmin := PackedVector3Array([Vector3(-0.47, SILL + 0.012, -0.60), Vector3(0.20, SILL + 0.012, -0.60), Vector3(0.25, DOOR_BOT_Y - 0.004, DOOR_BOT_Z + 0.002),
		Vector3(-0.47, -0.275, 1.225), Vector3(-0.47, 0.262, -0.98), Vector3(-0.30, 0.55, -0.15)])
	var cmax := PackedVector3Array([Vector3(-0.20, WIN_TOP - 0.004, 1.49), Vector3(0.47, WIN_TOP - 0.004, 1.49), Vector3(0.47, SILL + 0.012, DOOR_REAR_Z + 0.004),
		Vector3(-0.15, SILL - 0.039, 1.575), Vector3(0.47, 0.70, -0.36), Vector3(0.30, 0.72, 0.58)])     # last: up through the roof to the skylight
	fm.set_shader_parameter("cut_n", cmin.size())
	fm.set_shader_parameter("cut_min", cmin)
	fm.set_shader_parameter("cut_max", cmax)
	(p.node.get_node("Paint") as MeshInstance3D).material_override = fm
	# the inside of the fabric round the cabin and baggage bay (Dave: you could
	# see through the plane from inside - the skin is one-sided): a lining
	# facing inward, with the same window and door cut-outs
	var sh := _part("CabinShell")
	var zz := -0.86
	var prev := PackedVector3Array()
	while zz <= 1.62:
		var sc := _sec_at(zz)
		var ring := _section(float(sc[0]) - 0.008, float(sc[1]) + 0.008, float(sc[2]) - 0.008, sc[3], zz, 96)    # fine, so it hugs the skin (40 cut the roof corners: dark slabs over the windows)
		if not prev.is_empty():
			var ctr := Vector3(0, (float(sc[1]) + float(sc[2])) * 0.5, zz - 0.03)
			for i in range(ring.size()):
				var j := (i + 1) % ring.size()
				var fmid := (prev[i] + prev[j] + ring[i] + ring[j]) * 0.25
				if fmid.y > 0.56 and fmid.z < 1.22:
					continue          # the roof under the wing: the centre section's underside is the headliner there (this hung down like a black sheet)
				sh.paint.quad(prev[i], prev[j], ring[j], ring[i], _fix(Color(0.20, 0.20, 0.20).lerp(Color(0.40, 0.38, 0.35), smoothstep(0.40, 0.62, fmid.y))), ctr - fmid)   # the headliner fades lighter toward the roof
		prev = ring
		zz += 0.06
	# the bulkhead behind the baggage bay
	var bs := _sec_at(1.62)
	var bring := _section(float(bs[0]) - 0.008, float(bs[1]) + 0.008, float(bs[2]) - 0.008, bs[3], 1.62, 96)
	var bc := Vector3(0, (float(bs[1]) + float(bs[2])) * 0.5, 1.62)
	for i2 in range(bring.size()):
		sh.paint.tri(bc, bring[i2], bring[(i2 + 1) % bring.size()], _fix(Color(0.18, 0.18, 0.18)), Vector3(0, 0, -1))
	_done(sh)
	var shm := fm.duplicate() as ShaderMaterial
	shm.set_shader_parameter("dust", 0.0)
	shm.set_shader_parameter("rough", 0.9)
	(sh.node.get_node("Paint") as MeshInstance3D).material_override = shm


# ------------------------------------------------------------------------------
#  Cowl: the four-cylinder's cowl - two side panels, the nose bowl with the
#  two round inlets either side of the crankshaft, the carb air box under
#  the chin, the exhaust stacks out the bottom (3-view front and side)
# ------------------------------------------------------------------------------
func _cowl() -> void:
	# the two side panels: each hinged along the top centre, they lift up
	# like gull wings to get at the engine (Dave: "I want it all to open up")
	# one smooth shell (Dave: the cowl one piece, the inlets running back into
	# the bumps): the panels' rings carry the cheek humps in their own surface
	# (_cheek), the same field the nose bowl uses, so the seam lines up
	var rings: Array = []
	var cents: Array = []
	for zr: float in [-1.70, -1.685, -1.665, -1.64, -1.60, -1.55, -1.50, -1.45, -1.40, -1.34, -1.28, -1.22, -1.16, -1.10, -1.05, -1.01]:
		var rg := _cowl_ring(zr, 56)
		rings.append(rg)
		cents.append(Vector3(0, (rg[14].y + rg[42].y) * 0.5, zr))
	for side: float in [-1.0, 1.0]:
		var cp := _part("CowlPanel" + ("L" if side < 0.0 else "R"))
		_anim_reg(cp.node, Vector3(0, 0.244, -1.35), Vector3(0, 0, 1), 1.55 * side)
		var idx: Array = []
		if side > 0.0:
			for i in range(42, 57):
				idx.append(i % 56)
			for i in range(1, 15):
				idx.append(i)
		else:
			for i in range(14, 43):
				idx.append(i)
		for r in range(rings.size() - 1):
			var ra: PackedVector3Array = rings[r]
			var rb: PackedVector3Array = rings[r + 1]
			var cm: Vector3 = (cents[r] + cents[r + 1]) * 0.5
			for j in range(idx.size() - 1):
				var a0: Vector3 = ra[idx[j]]
				var a1: Vector3 = ra[idx[j + 1]]
				var b0: Vector3 = rb[idx[j]]
				var b1: Vector3 = rb[idx[j + 1]]
				var fm := (a0 + a1 + b0 + b1) * 0.25
				cp.paint.quad(a0, a1, b1, b0, BANDED, Vector3(fm.x, fm.y - cm.y, 0))
				cp.dark.quad(a0, a1, b1, b0, Color(0.10, 0.10, 0.10), -Vector3(fm.x, fm.y - cm.y, 0))   # the inside, unpainted
		# the access door lower on the side: an outline and two fasteners
		var ad: Array = []
		for q in [Vector2(-1.52, -0.30), Vector2(-1.30, -0.30), Vector2(-1.30, -0.12), Vector2(-1.52, -0.12), Vector2(-1.52, -0.30)]:
			ad.append(Vector3(side * (_cowl_x((q as Vector2).x, (q as Vector2).y) + 0.002), (q as Vector2).y, (q as Vector2).x))
		_tube(cp.dark, ad, 0.0025, Color(0.25, 0.25, 0.25))
		for fz: float in [-1.50, -1.32]:
			cp.metal.cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5 * side), Vector3(side * (_cowl_x(fz, -0.14) + 0.002), -0.14, fz)), 0.007, 0.007, 0.003, 8, Color(0.75, 0.75, 0.75), true)
		# the latches along the bottom edge
		for zf: float in [-1.55, -1.30, -1.10]:
			cp.metal.box_at(Vector3(side * 0.10, -0.535, zf), Vector3(0.03, 0.008, 0.02), Color(0.7, 0.7, 0.7))
		_done(cp)
	var p := _part("NoseBowl")
	# the nose bowl: rolls in from the cowl's front to the face
	var surf: Array = []                                   # the nose's outer triangles (the snouts' collars find the skin with these)
	var bowl: Array = []
	for st2 in [[0.0, 1.0], [-0.015, 0.965], [-0.03, 0.93], [-0.042, 0.87], [-0.05, 0.80]]:
		var f: float = st2[1]
		var cy := -0.12
		var br := _section(0.334 * f, cy + (-0.444 - cy) * f, cy + (0.194 - cy) * f, 3.2, -1.70 + float(st2[0]), 56)
		for bi in range(br.size()):
			br[bi] = _nostril(_cheek(br[bi]))
		bowl.append(br)
	for bri in range(bowl.size() - 1):                      # the nose bowl white (ref 03 / 04), the inlets left open
		var ba: PackedVector3Array = bowl[bri]
		var bb: PackedVector3Array = bowl[bri + 1]
		for bj in range(ba.size()):
			var bk := (bj + 1) % ba.size()
			var bm := (ba[bj] + ba[bk] + bb[bj] + bb[bk]) * 0.25
			surf.append([ba[bj], ba[bk], bb[bk]])
			surf.append([ba[bj], bb[bk], bb[bj]])
			if pow((absf(bm.x) - SNOUT_X) / 0.075, 2.0) + pow((bm.y - SNOUT_Y) / 0.068, 2.0) < 1.0:
				continue
			p.paint.quad(ba[bj], ba[bk], bb[bk], bb[bj], _fix(base), Vector3(bm.x, bm.y + 0.12, -0.3))
	var face: PackedVector3Array = bowl[bowl.size() - 1]
	var fz := -1.75
	# the face: one smooth dome from the bowl's edge to the middle (a polar
	# mesh so it shades smooth), the two inlets cut right through it - big
	# round nostrils, like a snout (Dave)
	var fcy := -0.12 + (((-0.444 - -0.12) * 0.80) + ((0.194 - -0.12) * 0.80)) * 0.5
	var edge := face                                  # the bowl's last ring, humps and all
	var holes := [[Vector2(-SNOUT_X, SNOUT_Y), Vector2(0.075, 0.068)], [Vector2(SNOUT_X, SNOUT_Y), Vector2(0.075, 0.068)], [Vector2(0.0, -0.01), Vector2(0.07, 0.07)]]
	var nr := 28
	var prev_ring: Array = []
	for ri in range(nr + 1):
		var f := float(ri) / float(nr)
		var ring_pts: Array = []
		for e in edge:
			var x := (e as Vector3).x * (1.0 - f)
			var y := fcy + ((e as Vector3).y - fcy) * (1.0 - f)
			ring_pts.append(_nostril(_dome(x, y, fz, fcy)))
		if not prev_ring.is_empty():
			for k in range(ring_pts.size()):
				var k2 := (k + 1) % ring_pts.size()
				var a0: Vector3 = prev_ring[k]
				var a1: Vector3 = prev_ring[k2]
				var b1: Vector3 = ring_pts[k2]
				var b0: Vector3 = ring_pts[k]
				var cm := (a0 + a1 + b0 + b1) * 0.25
				var skip := false
				for h in holes:
					var hc: Vector2 = h[0]
					var hr: Vector2 = h[1]
					if pow((cm.x - hc.x) / hr.x, 2.0) + pow((cm.y - hc.y) / hr.y, 2.0) < 1.0:
						skip = true
				if not skip:
					p.paint.quad(a0, a1, b1, b0, _fix(base), Vector3(0, 0, -1))
		prev_ring = ring_pts
	# the two inlets as snouts (Dave): round nostrils standing proud of the
	# face at its upper corners, a thick rolled lip, the throat running back
	# into the cowl's cheek humps behind them (they feed the cylinder banks)
	for s: float in [-1.0, 1.0]:
		var c := Vector2(s * SNOUT_X, SNOUT_Y)
		var zf := _nostril(_dome(c.x, c.y, fz, fcy)).z
		var prof := [[zf + 0.02, 1.00], [zf - 0.004, 1.03], [zf - 0.016, 1.01], [zf - 0.018, 0.94], [zf - 0.010, 0.88], [zf + 0.01, 0.86]]
		var srings: Array = []
		for pr in prof:
			var ring := PackedVector3Array()
			for i in range(28):
				var a := TAU * float(i) / 28.0
				ring.append(Vector3(c.x + cos(a) * 0.088 * float(pr[1]), c.y + sin(a) * 0.080 * float(pr[1]), float(pr[0])))
			srings.append(ring)
		for r in range(srings.size() - 1):
			var ra: PackedVector3Array = srings[r]
			var rb: PackedVector3Array = srings[r + 1]
			for i in range(28):
				var j := (i + 1) % 28
				var cc := Vector3(c.x, c.y, (ra[i].z + rb[i].z) * 0.5)
				var fm := (ra[i] + ra[j] + rb[i] + rb[j]) * 0.25
				var outward := (fm - cc) if r < 3 else (cc - fm)          # the outside of the snout, then the inside of the lip
				p.paint.quad(ra[i], ra[j], rb[j], rb[i], _fix(base), outward)
		# the throat: dark, running back into the hump
		var t0: PackedVector3Array = srings[srings.size() - 1]
		var t1 := PackedVector3Array()
		for i2 in range(28):
			var a2 := TAU * float(i2) / 28.0
			t1.append(Vector3(c.x + cos(a2) * 0.08, c.y + sin(a2) * 0.07, fz + 0.30))
		for i3 in range(28):
			var j3 := (i3 + 1) % 28
			var cc2 := Vector3(c.x, c.y, (t0[i3].z + t1[i3].z) * 0.5)
			p.dark.quad(t0[i3], t0[j3], t1[j3], t1[i3], Color(0.05, 0.05, 0.05), cc2 - (t0[i3] + t1[i3]) * 0.5)
	# the collars (Dave: connect them): each snout's outer wall carried straight
	# back until it meets the nose skin, so the inlet grows out of the cowl
	# with no gap or step round it
	for s5: float in [-1.0, 1.0]:
		var c5 := Vector2(s5 * SNOUT_X, SNOUT_Y)
		var zf5 := _nostril(_dome(c5.x, c5.y, fz, fcy)).z
		var outer := PackedVector3Array()
		var back := PackedVector3Array()
		for i5 in range(28):
			var a5 := TAU * float(i5) / 28.0
			var xy := Vector2(c5.x + cos(a5) * 0.088, c5.y + sin(a5) * 0.080)
			outer.append(Vector3(xy.x, xy.y, zf5 + 0.02))
			var zs := _z_on(surf, xy)
			back.append(Vector3(xy.x, xy.y, maxf(zs + 0.006, zf5 + 0.02)))
		for i6 in range(28):
			var j6 := (i6 + 1) % 28
			var mid := (outer[i6] + back[j6]) * 0.5
			p.paint.quad(outer[i6], outer[j6], back[j6], back[i6], _fix(base), Vector3(mid.x - c5.x, mid.y - c5.y, 0.0))
	# the shaft hole round the prop flange: a short dark sleeve, open
	var sh: Array = []
	for z2: float in [_dome(0.0, -0.01, fz, fcy).z - 0.001, fz + 0.05]:
		var ring := PackedVector3Array()
		for i3 in range(20):
			var a3 := TAU * float(i3) / 20.0
			ring.append(Vector3(cos(a3) * 0.072, -0.01 + sin(a3) * 0.072, z2))
		sh.append(ring)
	for i4 in range(20):
		var j4 := (i4 + 1) % 20
		var ra: PackedVector3Array = sh[0]
		var rb: PackedVector3Array = sh[1]
		p.dark.quad(ra[i4], ra[j4], rb[j4], rb[i4], Color(0.04, 0.04, 0.04), -(ra[i4] + rb[i4]) * 0.5 + Vector3(0, 0, fz))
	# the carb air filter at the front under the nose (Dave: a nice air filter,
	# not the black cone): an aluminium air box with a rubber seal, the
	# pleated filter element behind a wire-mesh grille, clamp bolts round
	# the frame, the duct back to the carb under the engine
	# (the air filter itself is its own part - see _air_filter(): it comes off and is replaced in the game)
	# the duct back from the box to the carb under the sump

	# exhaust stacks out the bottom
	for s2: float in [-1.0, 1.0]:
		_tube(p.metal, [Vector3(s2 * 0.20, -0.48, -1.30), Vector3(s2 * 0.22, -0.60, -1.18), Vector3(s2 * 0.22, -0.64, -1.02)], 0.026, Color(0.30, 0.24, 0.18))
	# the hinge line down each side (the side panels lift) and the cowl's
	# fasteners, the oil door on top
	_done(p)
	# the piano hinge down the top centre
	_air_filter()
	_intake_tube()
	var hg := _part("CowlHinge")
	_tube(hg.metal, [Vector3(0, 0.246, -1.66), Vector3(0, 0.246, -1.02)], 0.006, Color(0.65, 0.65, 0.65))
	_done(hg)
	_engine()


## The prop: a two-blade fixed-pitch metal prop, bare hub (no spinner on the
## 3-view), polished face, black back, yellow-red-yellow... just yellow tips.
## Prop options (Dave): the stock metal 2-blade; the long "bush" 2-blade with
## the wide tips for climb; a short 3-blade composite; a black paddle
## 2-blade for skis / floats. Each its own size and finish.
const PROPS := {
	"stock": {"blades": 2, "r": 0.94, "chord": 0.125, "plan": "taper", "metal": true, "col": Color(0.72, 0.72, 0.70), "tip": Color(0.95, 0.78, 0.10), "name": "stock metal 2-blade, 74 in"},
	"bush": {"blades": 2, "r": 1.04, "chord": 0.15, "plan": "wide_tip", "metal": true, "col": Color(0.78, 0.78, 0.76), "tip": Color(0.92, 0.10, 0.06), "name": "bush 2-blade, 82 in, wide tips"},
	"composite3": {"blades": 3, "r": 0.88, "chord": 0.14, "plan": "scimitar", "metal": false, "col": Color(0.06, 0.06, 0.06), "tip": Color(0.92, 0.92, 0.88), "name": "composite 3-blade, 70 in"},
	"paddle": {"blades": 2, "r": 0.96, "chord": 0.20, "plan": "paddle", "metal": false, "col": Color(0.05, 0.05, 0.05), "tip": Color(0.95, 0.78, 0.10), "name": "black paddle 2-blade, 76 in"},
}
var prop_kind := "bush"


static func _blade_chord(plan: String, t: float) -> float:
	match plan:
		"wide_tip":
			return lerpf(0.75, 1.0, smoothstep(0.0, 0.7, t)) * (1.0 - 0.45 * pow(t, 10.0))
		"scimitar":
			return lerpf(0.9, 0.6, t) * (1.0 - 0.6 * pow(t, 6.0))
		"paddle":
			return (0.85 + 0.15 * sin(PI * t)) * (1.0 - 0.35 * pow(t, 12.0))
	return lerpf(0.8, 1.0, sin(t * PI * 0.8)) * (1.0 - 0.55 * pow(t, 8.0))


func prop_next() -> String:
	var keys := PROPS.keys()
	prop_kind = keys[(keys.find(prop_kind) + 1) % keys.size()]
	var spin_was := spin
	if _prop != null and is_instance_valid(_prop):
		_prop.queue_free()
	_prop_hub()
	spin = spin_was
	return "Prop: %s." % String(PROPS[prop_kind]["name"])


func _prop_hub() -> void:
	_prop = Node3D.new()
	_prop.name = "PropHub"
	_prop.set_meta("part", true)   # the whole prop comes off in a prop strike
	_prop.position = PROP_AT
	_root.add_child(_prop)
	var p := _part("Prop", _prop)
	p.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 0.14)), 0.10, 0.10, 0.05, 20, Color(0.55, 0.55, 0.55), true)   # crank flange
	p.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 0.09)), 0.09, 0.07, 0.08, 20, Color(0.75, 0.75, 0.76), true)   # hub
	for k in range(6):
		var a := TAU * float(k) / 6.0
		p.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(cos(a) * 0.065, sin(a) * 0.065, 0.02)), 0.008, 0.008, 0.02, 6, Color(0.6, 0.6, 0.6), true)
	var sr: Array = []
	for k2 in range(7):
		var t2 := float(k2) / 6.0
		var r2 := 0.085 * sqrt(maxf(1.0 - t2 * t2, 0.0))
		var ring2 := PackedVector3Array()
		for i2 in range(16):
			var a2 := TAU * float(i2) / 16.0
			ring2.append(Vector3(cos(a2) * maxf(r2, 0.002), sin(a2) * maxf(r2, 0.002), 0.06 - t2 * 0.20))
		sr.append(ring2)
	p.paint.loft(sr, _fix(Color(0.05, 0.05, 0.05)), true, true)     # black spinner (ref 03 / 04)
	# the blades: the prop type picks the count, length, planform, finish
	var spec: Dictionary = PROPS[prop_kind]
	var nb: int = spec["blades"]
	var R: float = spec["r"]
	for bi in range(nb):
		var brot := Basis(Vector3.BACK, TAU * float(bi) / float(nb))
		var brings: Array = []
		for k in range(12):
			var t := float(k) / 11.0
			var r := lerpf(0.07, R, t)
			var ch: float = _blade_chord(String(spec["plan"]), t) * float(spec["chord"])
			var tw := lerpf(0.70, 0.18, t)
			var th := lerpf(0.045, 0.008, t)
			var ring := PackedVector3Array()
			for q in [Vector2(-0.5, 0), Vector2(-0.2, 0.6), Vector2(0.3, 0.4), Vector2(0.5, 0), Vector2(0.2, -0.3), Vector2(-0.3, -0.25)]:
				var u: float = float(q.x) * ch
				var v: float = float(q.y) * th
				ring.append(brot * Vector3(u * cos(tw) - v * sin(tw), r, u * sin(tw) + v * cos(tw)))
			brings.append(ring)
		for k in range(brings.size() - 1):
			var col: Color = spec["col"] if k < 10 else spec["tip"]
			if spec["metal"]:
				p.metal.loft([brings[k], brings[k + 1]], col, k == 0, k == brings.size() - 2)
			else:
				p.dark.loft([brings[k], brings[k + 1]], col, k == 0, k == brings.size() - 2)
	_done(p)


# ------------------------------------------------------------------------------
#  Windows and doors (3-view side: frames at z -0.58, -0.185, 0.64, 1.17,
#  sill at y 0.09, the wing's underside on top). Right side: the split door -
#  the top half (window) swings up under the wing, the bottom half drops.
# ------------------------------------------------------------------------------
## Window layout off the 3-view (reference/supercub/00, side, enlarged):
## a slanted front post parallel to the windshield, posts at -0.17, 0.214 and
## 0.629, and the big rear window whose back edge slopes down and aft to the
## sill at 1.47. Sill 0.12, top 0.61 (the wing's underside).
const WIN_Z := [-0.17, 0.214, 0.629]
const SILL := 0.12
const WIN_FRAME := Color(0.07, 0.07, 0.075)   # window and door frames: black (ref 01 / 03 / 04)
const WIN_TOP := 0.61
const POST_F := [Vector2(-0.615, 0.12), Vector2(-0.345, 0.61)]     # (z, y) bottom -> top
const POST_R := [Vector2(0.835, 0.61), Vector2(1.47, 0.18)]        # the rear window's back edge
## The right-side door (reference/supercub/04, the close-up): a trapezoid,
## not a box. Top half: from the slanted front post back to the post behind
## the front seat (0.214). Bottom half: its front edge drops near-straight
## to the floor, its back edge slants forward to the floor - the bottom is
## narrower than the top.
const DOOR_REAR_Z := 0.624           # the top half's back edge (the rear window post - the opening spans both seats, ref 03)
const DOOR_BOT_Y := -0.50            # the lower door's hinge line, down at the lower longeron (ref 03: the door reaches nearly to the belly)
const DOOR_BOT_Z := -0.603           # the lower door's front edge: straight down from the top half's front corner (they meet - Dave)
const DOOR_BOT_REAR_Z := 0.17        # the lower door's back corner at the floor: at the strut fitting, over the gear (ref 03)


## The skin's half width at (z, y), from the real section (floors and
## linings follow the fuselage's shape instead of poking through it).
## The nose bowl's face, domed: it bulges forward toward the middle (ref 03).
func _dome(x: float, y: float, fz: float, fcy: float) -> Vector3:
	var u := x / 0.267
	var v := (y - fcy) / 0.258
	var k := clampf(1.0 - u * u - v * v, 0.0, 1.0)
	return Vector3(x, y, fz - 0.07 * sqrt(k))


static func _in_ring(ring: PackedVector3Array, p: Vector2) -> bool:
	var inside := false
	var n := ring.size()
	for i in range(n):
		var a := ring[i]
		var b := ring[(i + n - 1) % n]
		if ((a.y > p.y) != (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
	return inside


func _skin_x(z: float, y: float) -> float:
	var sec := _sec_at(z)
	var ring := _section(sec[0], sec[1], sec[2], sec[3], z, 56)
	var best := 0.0
	for i in range(ring.size()):
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % ring.size()]
		if (a.y - y) * (b.y - y) <= 0.0 and absf(b.y - a.y) > 1e-6:
			var f := (y - a.y) / (b.y - a.y)
			best = maxf(best, absf(lerpf(a.x, b.x, f)))
	return best


## The cheek humps (Dave: the snouts connect to the bumps): a bulge pushed
## out from the cowl's middle round the line through each inlet, starting at
## the face, fattest just behind the nose, fading out before the firewall.
## Every cowl surface (nose bowl, face, side panels) goes through this, so
## they meet in one smooth skin.
func _cheek(q: Vector3) -> Vector3:
	var cy := -0.12
	var d := Vector2(q.x, q.y - cy)
	var r := d.length()
	if r < 1e-4:
		return q
	var a0 := atan2(SNOUT_Y - cy, SNOUT_X)
	var ang := atan2(d.y, absf(d.x))
	# a round hump: its section a circle of radius R standing h proud of the
	# skin, filleted into it (soft max), so it reads as a tube under the skin
	var t := clampf((q.z + 1.76) / 0.68, 0.0, 1.0)
	var h := 0.068 * (0.75 + 0.25 * smoothstep(0.0, 0.18, t)) * (1.0 - smoothstep(0.35, 1.0, t))
	var R := 0.095
	var sarc := r * (ang - a0)
	var base := sqrt(maxf(R * R - sarc * sarc, 0.0)) - (R - h)
	if R * R - sarc * sarc <= 0.0:
		base = -(absf(sarc) - R) - (R - h)
	var k := 0.035
	var off := 0.5 * (base + sqrt(base * base + k * k)) - 0.5 * (-(R - h) + sqrt((R - h) * (R - h) + k * k)) * 0.0
	off = maxf(off, 0.0) * smoothstep(0.0, 0.02, h)
	return q + Vector3(d.x / r, d.y / r, 0.0) * off


## The nostrils: round the two inlets the face is drawn forward, so each
## inlet stands out as a short snout that runs straight back into its hump.
func _nostril(q: Vector3) -> Vector3:
	var d := Vector2(absf(q.x) - SNOUT_X, q.y - SNOUT_Y).length()
	var pull := 0.055 * exp(-pow(d / 0.13, 2.0)) * (1.0 - smoothstep(-1.745, -1.70, q.z))
	return q + Vector3(0.0, 0.0, -pull)


## The frontmost z of a triangle soup at (x, y), looking straight back.
static func _z_on(tris: Array, xy: Vector2) -> float:
	var best := 0.0
	var hit := false
	for t in tris:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(den) < 1e-9:
			continue
		var l1 := ((b.y - c.y) * (xy.x - c.x) + (c.x - b.x) * (xy.y - c.y)) / den
		var l2 := ((c.y - a.y) * (xy.x - c.x) + (a.x - c.x) * (xy.y - c.y)) / den
		var l3 := 1.0 - l1 - l2
		if l1 >= -1e-4 and l2 >= -1e-4 and l3 >= -1e-4:
			var z := l1 * a.z + l2 * b.z + l3 * c.z
			if not hit or z < best:
				best = z
				hit = true
	return best if hit else -1.70


## One ring of the cowl's side skin at z, humps included.
func _cowl_ring(z: float, pts: int) -> PackedVector3Array:
	var st := [[-1.70, 0.33, -0.44, 0.19, 3.2], [-1.66, 0.37, -0.50, 0.215, 3.6], [-1.55, 0.395, -0.525, 0.23, 4.0], [-1.25, 0.40, -0.53, 0.235, 4.0], [-1.01, 0.392, -0.535, 0.24, 4.0]]
	var a: Array = st[0]
	var b: Array = st[st.size() - 1]
	for i in range(st.size() - 1):
		if z >= float(st[i][0]) and z <= float(st[i + 1][0]):
			a = st[i]
			b = st[i + 1]
	var f := clampf((z - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
	var ring := _section(lerpf(a[1], b[1], f) + 0.004, lerpf(a[2], b[2], f) - 0.004, lerpf(a[3], b[3], f) + 0.004, lerpf(a[4], b[4], f), z, pts)
	for i2 in range(ring.size()):
		ring[i2] = _cheek(ring[i2])
	return ring


## The fuselage's top at (z, x): the skin's height over that point.
func _skin_top(z: float, x: float) -> float:
	var sec := _sec_at(z)
	var ring := _section(sec[0], sec[1], sec[2], sec[3], z, 56)
	var best := float(sec[1])
	for i in range(ring.size()):
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % ring.size()]
		if (a.x - x) * (b.x - x) <= 0.0 and absf(b.x - a.x) > 1e-6:
			var f := (x - a.x) / (b.x - a.x)
			best = maxf(best, lerpf(a.y, b.y, f))
	return best


## The cowl's half width at (z, y) (its own sections, not the fuselage's).
func _cowl_x(z: float, y: float) -> float:
	var st := [[-1.70, 0.33, -0.44, 0.19, 3.2], [-1.66, 0.37, -0.50, 0.215, 3.6], [-1.55, 0.395, -0.525, 0.23, 4.0], [-1.25, 0.40, -0.53, 0.235, 4.0], [-1.01, 0.392, -0.535, 0.24, 4.0]]
	var a: Array = st[0]
	var b: Array = st[st.size() - 1]
	for i in range(st.size() - 1):
		if z >= float(st[i][0]) and z <= float(st[i + 1][0]):
			a = st[i]
			b = st[i + 1]
	var f := clampf((z - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
	var ring := _section(lerpf(a[1], b[1], f) + 0.004, lerpf(a[2], b[2], f) - 0.004, lerpf(a[3], b[3], f) + 0.004, lerpf(a[4], b[4], f), z, 56)
	var best := 0.0
	for i2 in range(ring.size()):
		var p: Vector3 = ring[i2]
		var q: Vector3 = ring[(i2 + 1) % ring.size()]
		if (p.y - y) * (q.y - y) <= 0.0 and absf(q.y - p.y) > 1e-6:
			best = maxf(best, absf(lerpf(p.x, q.x, (y - p.y) / (q.y - p.y))))
	return best


func _side_x(z: float, y: float) -> float:
	var sec := _sec_at(z)
	var hh: float = (float(sec[2]) - float(sec[1])) * 0.5
	var cy: float = (float(sec[2]) + float(sec[1])) * 0.5
	var tumble := 1.0 - 0.10 * clampf((y - cy) / maxf(hh, 0.01), 0.0, 1.0)
	return float(sec[0]) * tumble


## The rear window's back edge, top to bottom (z, y): along under the wing,
## a big rounded corner into the sloping back edge (the 3-view's slant),
## a rounded corner into the sill (ref 04: the window's corners are round).
func _rear_outline() -> Array:
	var a := Vector2(0.835, WIN_TOP - 0.005)          # top corner
	var b := Vector2(1.40, 0.175)                     # bottom corner
	var dsl := (b - a).normalized()
	var out: Array = []
	var a0 := a + Vector2(-0.16, 0.0)
	var a1 := a + dsl * 0.16
	for k in range(7):
		var t := float(k) / 6.0
		out.append(a0.lerp(a, t).lerp(a.lerp(a1, t), t))
	var b0 := b - dsl * 0.12
	var b1 := b + Vector2(-0.14, -0.04)
	for k2 in range(7):
		var t2 := float(k2) / 6.0
		out.append(b0.lerp(b, t2).lerp(b.lerp(b1, t2), t2))
	return out


var _flat_ok := true      # off while laying fabric fillers: those follow the real (rounded) skin


func _on_side(s: float, z: float, y: float, out: float) -> Vector3:
	# the windows are flat panes (Dave: the frames bent in at the top): in the
	# window band the side is the flat side plane, not the rounding roof
	if _flat_ok and y > SILL - 0.05 and z > -0.70 and z < 0.60:     # (only the front windows and door: the rear window follows the turtledeck's curve, or it stood off it - Dave, from behind)
		return Vector3(s * (_side_x(z, y) + out), y, z)
	return Vector3(s * (_skin_x(z, y) + out), y, z)


## A flat strip on the cabin side along (z, y) points, width w (the window
## frames: flush trim, not tubes standing off the skin).
func _strip(k: MeshKit, s: float, pts: Array, w: float, col: Color, out: float = 0.003) -> void:
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var d := (b - a)
		if d.length() < 1e-5:
			continue
		var nrm := Vector2(-d.y, d.x).normalized() * (w * 0.5)
		var steps := maxi(1, int(d.length() / 0.08))
		for k2 in range(steps):
			var p0 := a.lerp(b, float(k2) / float(steps))
			var p1 := a.lerp(b, float(k2 + 1) / float(steps))
			var q := [p0 - nrm, p1 - nrm, p1 + nrm, p0 + nrm]
			var v: Array = []
			for qq in q:
				v.append(_on_side(s, (qq as Vector2).x, (qq as Vector2).y, out))
			k.quad(v[0], v[1], v[2], v[3], col, Vector3(s, 0, 0))


## The black rubber seal round a pane (ref 01 / 02: every window's edge reads
## as a thin dark line): a closed loop of (z, y) points, a hair proud.
func _seal(k: MeshKit, s: float, pts: Array, out: float = 0.004) -> void:
	var v: Array = []
	for q in pts:
		v.append(_on_side(s, (q as Vector2).x, (q as Vector2).y, out))
	v.append(v[0])
	_tube(k, v, 0.0035, Color(0.04, 0.04, 0.04))


## A flat polygon on the cabin side, given as (z, y) points (fanned).
func _poly(k: MeshKit, s: float, pts: Array, col: Color, out: float, facing: float = 1.0) -> void:
	var v: Array = []
	_flat_ok = col.a > 0.5      # fabric (banded paint) follows the skin; glass and linings stay flat
	for q in pts:
		v.append(_on_side(s, (q as Vector2).x, (q as Vector2).y, out))
	_flat_ok = true
	for i in range(1, v.size() - 1):
		k.tri(v[0], v[i], v[i + 1], col, Vector3(s * facing, 0, 0))


func _pane(k: MeshKit, frame: MeshKit, s: float, z0: float, z1: float, y0: float, y1: float, out: float = 0.003) -> void:
	var a := _on_side(s, z0, y0, out)
	var b := _on_side(s, z1, y0, out)
	var c := _on_side(s, z1, y1, out)
	var d := _on_side(s, z0, y1, out)
	k.quad(a, b, c, d, Color.WHITE, Vector3(s, 0, 0))
	_tube(frame, [a, b, c, d, a], 0.0045, Color(0.06, 0.06, 0.06))


func _windows_and_doors() -> void:
	# the windshield: one curved sheet from the cowl's top to the wing,
	# wrapping round each side right back to the front post (ref 02 / 04):
	# each row runs from the front line round the corner to the post at that
	# height, so windshield, post and side window meet on one line
	var g := _part("Windshield")
	var wp0: Vector2 = POST_F[0]
	var wp1: Vector2 = POST_F[1]
	var rows: Array = []
	var nr := 9
	var nc := 17
	for k in range(nr):
		var u := float(k) / float(nr - 1)
		var y := lerpf(0.245, 0.668, u)                                      # up under the wing's centre-section leading edge
		var zc := lerpf(-1.00, -0.375, u) - 0.03 * sin(PI * u)                 # the front line, bowed forward a touch
		var zp := wp0.x + (y - wp0.y) / (wp1.y - wp0.y) * (wp1.x - wp0.x)    # the front post at this height
		var ring := PackedVector3Array()
		for j in range(nc):
			var v := lerpf(-1.0, 1.0, float(j) / float(nc - 1))
			var th := v * PI * 0.5
			var zz := zc + (zp - zc) * (1.0 - cos(th))
			var hw := _side_x(zz, y) + 0.002
			ring.append(Vector3(hw * sin(th) * (1.0 + 0.0 * v), y, zz))
		rows.append(ring)
	for k in range(rows.size() - 1):
		var a: PackedVector3Array = rows[k]
		var b: PackedVector3Array = rows[k + 1]
		for j in range(a.size() - 1):
			var fm := (a[j] + a[j + 1] + b[j] + b[j + 1]) * 0.25
			g.glass.quad(a[j], a[j + 1], b[j + 1], b[j], Color.WHITE, Vector3(fm.x, 0.5, fm.z + 0.2))
	var first: PackedVector3Array = rows[0]
	var last: PackedVector3Array = rows[rows.size() - 1]
	_tube(g.dark, Array(first), 0.006, Color(0.06, 0.06, 0.06))          # the rubber seal on the deck
	_tube(g.dark, Array(last), 0.007, Color(0.06, 0.06, 0.06))           # the top bow, up under the wing
	_done(g)
	for s: float in [-1.0, 1.0]:
		var side := "L" if s < 0.0 else "R"
		var w := _part("SideWindows" + side)
		var pf0: Vector2 = POST_F[0]
		var pf1: Vector2 = POST_F[1]
		var pr0: Vector2 = POST_R[0]
		var pr1: Vector2 = POST_R[1]
		# the frame (ref 01 / 04): flat painted fabric strips flush on the skin
		# round each pane - the tube structure is under the fabric, not outside it
		var fw := 0.024                      # slim posts (ref 01 / 02)
		_strip(w.paint, s, [pf0, pf1], fw, _fix(WIN_FRAME))
		for zp: float in WIN_Z:
			if s > 0.0 and zp < 0.6:
				continue                     # the door's side: one wide opening, then the rear window
			if s < 0.0 and absf(zp - 0.214) < 0.01:
				continue                     # the middle post is the opening window's own (it lifts with it)
			_strip(w.paint, s, [Vector2(zp, SILL), Vector2(zp, WIN_TOP)], fw, _fix(WIN_FRAME))
		var top0: float = pf1.x if s < 0.0 else DOOR_REAR_Z         # the door's own frame covers the top of the opening
		_strip(w.paint, s, [Vector2(top0, WIN_TOP - 0.01), Vector2(pr0.x, WIN_TOP - 0.01)], 0.03, _fix(WIN_FRAME))
		var sill0: float = pf0.x if s < 0.0 else DOOR_REAR_Z
		var rear := _rear_outline()
		var rend: Vector2 = rear[rear.size() - 1]
		_strip(w.paint, s, [Vector2(sill0, SILL), Vector2(rend.x, SILL)], 0.03, _fix(WIN_FRAME))      # the sill: ends where the rear window's corner meets it
		_strip(w.paint, s, rear, fw, _fix(WIN_FRAME))
		if s > 0.0:
			# the opening's edges below the sill: front nearly straight down, back slanting forward to the floor
			_strip(w.paint, s, [Vector2(DOOR_BOT_Z, SILL), Vector2(DOOR_BOT_Z, DOOR_BOT_Y)], 0.02, _fix(WIN_FRAME))
			_strip(w.paint, s, [Vector2(DOOR_REAR_Z, SILL), Vector2(DOOR_BOT_REAR_Z, DOOR_BOT_Y)], 0.02, _fix(WIN_FRAME))
			_poly(w.paint, s, [Vector2(-0.70, DOOR_BOT_Y - 0.008), Vector2(DOOR_BOT_Z, DOOR_BOT_Y - 0.008), Vector2(DOOR_BOT_Z, SILL + 0.01), Vector2(-0.70, SILL + 0.01)], BANDED, 0.001)
			_poly(w.paint, s, [Vector2(DOOR_BOT_REAR_Z, DOOR_BOT_Y - 0.008), Vector2(DOOR_REAR_Z + 0.005, DOOR_BOT_Y - 0.008), Vector2(DOOR_REAR_Z + 0.005, SILL + 0.01), Vector2(DOOR_REAR_Z, SILL + 0.01)], BANDED, 0.001)
		# fabric filling in the band's corners the windows don't use (the skin is cut for the whole band)
		var pz_lo := pf0.x + (0.262 - pf0.y) / (pf1.y - pf0.y) * (pf1.x - pf0.x)     # the front post where the glass's foot crosses it
		_poly(w.paint, s, [Vector2(-0.60, SILL + 0.01), Vector2(-0.60, 0.265), Vector2(pz_lo, 0.265)], BANDED, 0.001)
		# fabric behind the rear window's rounded back edge: strips from the edge back to the end of the cut
		for ri in range(rear.size() - 1):
			var ra: Vector2 = rear[ri]
			var rb: Vector2 = rear[ri + 1]
			_poly(w.paint, s, [ra, rb, Vector2(1.49, rb.y), Vector2(1.49, ra.y)], BANDED, 0.001)
		var rl: Vector2 = rear[rear.size() - 1]
		_poly(w.paint, s, [Vector2(rl.x - 0.3, SILL + 0.005), Vector2(1.49, SILL + 0.005), Vector2(1.49, rl.y), Vector2(rl.x, rl.y)], BANDED, 0.001)
		_poly(w.paint, s, [Vector2(pf0.x, SILL), Vector2(1.49, pr1.y - 0.002), Vector2(1.49, SILL - 0.01), Vector2(pf0.x, SILL - 0.01)], BANDED, 0.001)
		# the wing-root fairing (Dave: the wing didn't touch the glass): a fabric
		# band along the whole root, from the window frame / cabin top up to the
		# wing's underside, closing the slit you could see the sky through
		var fz := LE_Z + 0.01
		var fprev: Array = []
		while fz <= LE_Z + CHORD + 0.001:
			var ylo := WIN_TOP - 0.012
			var yhi := _wbot(ROOT_X, fz) + 0.012
			var lo := Vector3(s * (minf(_side_x(fz, ylo), maxf(_skin_x(fz, ylo), 0.25)) + 0.003), ylo, fz)
			var hi := Vector3(s * (ROOT_X + 0.004), yhi, fz)
			if not fprev.is_empty():
				w.paint.quad(fprev[0], lo, hi, fprev[1], BANDED, Vector3(s, 0.2, 0))
			fprev = [lo, hi]
			fz += 0.08
		# glass: the front window (slanted front edge) and the big rear one
		if s < 0.0:
			_poly(w.glass, s, [Vector2(pf0.x + 0.01, SILL + 0.005), Vector2(-0.175, SILL + 0.005), Vector2(-0.175, WIN_TOP - 0.005), Vector2(pf1.x + 0.005, WIN_TOP - 0.005)], Color.WHITE, -0.002)
			_seal(w.dark, s, [Vector2(pf0.x + 0.014, SILL + 0.008), Vector2(-0.178, SILL + 0.008), Vector2(-0.178, WIN_TOP - 0.008), Vector2(pf1.x + 0.008, WIN_TOP - 0.008)])
		var rw0: float = 0.635
		var gp: Array = [Vector2(rw0, SILL + 0.008)]
		for ri2 in range(rear.size() - 1, -1, -1):
			var rp: Vector2 = rear[ri2]
			gp.append(rp + Vector2(-0.01, 0.0))
		gp.append(Vector2(rw0, WIN_TOP - 0.006))
		_poly(w.glass, s, gp, Color.WHITE, -0.002)
		_seal(w.dark, s, gp)
		_done(w)
		if s < 0.0:
			var lw := _part("WindowL")
			_anim_reg(lw.node, Vector3(-0.38, WIN_TOP, 0.22), Vector3(0, 0, 1), -1.2)
			_poly(lw.glass, s, [Vector2(-0.165, SILL + 0.01), Vector2(0.624, SILL + 0.01), Vector2(0.624, WIN_TOP - 0.01), Vector2(-0.165, WIN_TOP - 0.01)], Color.WHITE, -0.001)
			_seal(lw.dark, s, [Vector2(-0.158, SILL + 0.022), Vector2(0.205, SILL + 0.022), Vector2(0.205, WIN_TOP - 0.022), Vector2(-0.158, WIN_TOP - 0.022)], 0.006)
			_seal(lw.dark, s, [Vector2(0.223, SILL + 0.022), Vector2(0.617, SILL + 0.022), Vector2(0.617, WIN_TOP - 0.022), Vector2(0.223, WIN_TOP - 0.022)], 0.006)
			_strip(lw.paint, s, [Vector2(0.214, SILL + 0.012), Vector2(0.214, WIN_TOP - 0.012)], 0.024, _fix(WIN_FRAME), 0.004)
			lw.metal.box_at(Vector3(-(_side_x(0.55, 0.15) + 0.02), 0.16, 0.55), Vector3(0.02, 0.02, 0.07), Color(0.7, 0.7, 0.7))
			_done(lw)
	# the right side's split door (the Cub's clamshell): one big opening from
	# the slanted front post back to the rear window post, full height. The
	# top half is nearly all window in a light aluminium frame - it swings up
	# and latches flat under the wing; the bottom half is a fabric-covered
	# panel hinged along its bottom edge - it folds down against the side.
	var pf0: Vector2 = POST_F[0]
	var pf1: Vector2 = POST_F[1]
	var dzb := DOOR_BOT_Z
	var up := _part("DoorUpper")
	_anim_reg(up.node, Vector3(_skin_x(0.15, WIN_TOP - 0.004) + 0.007, WIN_TOP - 0.004, 0.15), Vector3(0, 0, 1), 1.38)     # up flat against the wing's underside
	var uo := [Vector2(pf0.x + 0.012, SILL), Vector2(DOOR_REAR_Z, SILL), Vector2(DOOR_REAR_Z, WIN_TOP - 0.004), Vector2(pf1.x + 0.012, WIN_TOP - 0.004)]
	var fr: Array = []
	for q in uo:
		fr.append(_on_side(1.0, (q as Vector2).x, (q as Vector2).y, 0.007))
	fr.append(fr[0])
	_strip(up.paint, 1.0, uo, 0.03, _fix(WIN_FRAME), 0.006)                 # the door's frame (its front edge closes on the post)
	# the same posts as the left side's windows (Dave: make it look like the
	# left) - the glass in three panes, frames at -0.17 and 0.214
	for zp2: float in [-0.17, 0.214]:
		_strip(up.paint, 1.0, [Vector2(zp2, SILL + 0.01), Vector2(zp2, WIN_TOP - 0.008)], 0.024, _fix(WIN_FRAME), 0.007)
	_strip(up.paint, 1.0, [Vector2(pf0.x + 0.012, SILL + 0.012), Vector2(DOOR_REAR_Z, SILL + 0.012)], 0.024, _fix(WIN_FRAME), 0.007)       # its bottom rail
	_poly(up.glass, 1.0, [Vector2(pf0.x + 0.02, SILL + 0.01), Vector2(DOOR_REAR_Z - 0.01, SILL + 0.01), Vector2(DOOR_REAR_Z - 0.01, WIN_TOP - 0.014), Vector2(pf1.x + 0.02, WIN_TOP - 0.014)], Color.WHITE, 0.003)
	_seal(up.dark, 1.0, [Vector2(pf0.x + 0.028, SILL + 0.018), Vector2(DOOR_REAR_Z - 0.018, SILL + 0.018), Vector2(DOOR_REAR_Z - 0.018, WIN_TOP - 0.02), Vector2(pf1.x + 0.028, WIN_TOP - 0.02)], 0.008)
	up.metal.box_at(_on_side(1.0, DOOR_REAR_Z - 0.06, SILL + 0.03, 0.02), Vector3(0.015, 0.02, 0.07), Color(0.75, 0.75, 0.75))   # the latch
	_done(up)
	var lo := _part("DoorLower")
	_anim_reg(lo.node, Vector3(_skin_x(-0.2, DOOR_BOT_Y), DOOR_BOT_Y, -0.2), Vector3(0, 0, 1), -2.80)   # folds down and rests open on its stop cable (ref 04)
	var lo_pts := [Vector2(dzb, DOOR_BOT_Y), Vector2(DOOR_BOT_REAR_Z, DOOR_BOT_Y), Vector2(DOOR_REAR_Z, SILL - 0.004), Vector2(dzb, SILL - 0.004)]
	# a grid over the trapezoid that follows the skin's curve (one flat fan cut
	# across the cabin inside as a dark slab - Dave: "bottom right of dash is wonky")
	var lgrid: Array = []
	for iy in range(9):
		var fy := float(iy) / 8.0
		var yy := lerpf(DOOR_BOT_Y, SILL - 0.004, fy)
		var zf := dzb                                    # the front edge straight up and down, on the skin's cut (a slanted edge left a black slot - Dave)
		var zr := lerpf(DOOR_BOT_REAR_Z, DOOR_REAR_Z, fy)
		var row: Array = []
		for iz in range(9):
			var zz := lerpf(zf, zr, float(iz) / 8.0)
			row.append(Vector2(zz, yy))
		lgrid.append(row)
	for iy2 in range(8):
		for iz2 in range(8):
			var cell := [lgrid[iy2][iz2], lgrid[iy2][iz2 + 1], lgrid[iy2 + 1][iz2 + 1], lgrid[iy2 + 1][iz2]]
			_poly(lo.paint, 1.0, cell, BANDED, 0.005)
			_poly(lo.dark, 1.0, cell, LINING, 0.001, -1.0)                           # its inside (seen when it hangs down)
	_poly(lo.dark, 1.0, [Vector2(0.05, -0.20), Vector2(0.40, -0.20), Vector2(0.40, -0.12), Vector2(0.05, -0.12)], Color(0.85, 0.84, 0.80), -0.003, -1.0)   # the placard (ref 04)
	var lf: Array = []
	for q2 in lo_pts:
		lf.append(_on_side(1.0, (q2 as Vector2).x, (q2 as Vector2).y, 0.006))
	lf.append(lf[0])
	_tube(lo.dark, lf, 0.0035, Color(0.04, 0.04, 0.04))                        # the gap round it
	lo.metal.box_at(_on_side(1.0, 0.40, 0.02, 0.018), Vector3(0.014, 0.025, 0.09), Color(0.72, 0.72, 0.72))   # handle
	lo.metal.box_at(_on_side(1.0, (dzb + DOOR_BOT_REAR_Z) * 0.5, DOOR_BOT_Y + 0.04, 0.008), Vector3(0.004, 0.06, 0.5), Color(0.6, 0.6, 0.58))   # kick plate
	_done(lo)


# ------------------------------------------------------------------------------
#  Wing: a USA 35B type section (flat-ish bottom), constant chord, round tips;
#  the top red and the bottom white (photo 02); fabric sags a touch between
#  the ribs and the rib-stitch tapes show
# ------------------------------------------------------------------------------
const FOIL_TOP := [Vector2(0.0, 0.010), Vector2(0.0125, 0.034), Vector2(0.025, 0.046), Vector2(0.05, 0.064), Vector2(0.10, 0.088),
	Vector2(0.15, 0.102), Vector2(0.20, 0.111), Vector2(0.30, 0.117), Vector2(0.40, 0.112), Vector2(0.50, 0.101), Vector2(0.60, 0.086),
	Vector2(0.70, 0.067), Vector2(0.80, 0.047), Vector2(0.90, 0.025), Vector2(1.0, 0.003)]
const FOIL_BOT := [Vector2(0.0, 0.010), Vector2(0.0125, -0.008), Vector2(0.025, -0.014), Vector2(0.05, -0.020), Vector2(0.10, -0.024),
	Vector2(0.15, -0.025), Vector2(0.20, -0.025), Vector2(0.30, -0.024), Vector2(0.40, -0.021), Vector2(0.50, -0.018), Vector2(0.60, -0.014),
	Vector2(0.70, -0.010), Vector2(0.80, -0.007), Vector2(0.90, -0.004), Vector2(1.0, -0.003)]


static func _foil(tbl: Array, u: float) -> float:
	for i in range(tbl.size() - 1):
		var a: Vector2 = tbl[i]
		var b: Vector2 = tbl[i + 1]
		if u >= a.x and u <= b.x:
			return lerpf(a.y, b.y, (u - a.x) / maxf(b.x - a.x, 1e-5))
	return (tbl[tbl.size() - 1] as Vector2).y


func _wing_y(ax: float) -> float:
	return WING_Y + maxf(ax - ROOT_X, 0.0) * DIHEDRAL


## The top / bottom of the wing at (|x|, z).
func _wtop(ax: float, z: float) -> float:
	return _wing_y(ax) + _foil(FOIL_TOP, clampf((z - LE_Z) / CHORD, 0.0, 1.0)) * CHORD


func _wbot(ax: float, z: float) -> float:
	return _wing_y(ax) + _foil(FOIL_BOT, clampf((z - LE_Z) / CHORD, 0.0, 1.0)) * CHORD


const US := [0.0, 0.0125, 0.025, 0.05, 0.10, 0.15, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.0]


## Half a foil as a closed ring (top curve + the chord line back), between u0
## and u1 of the chord; z_le / ch let the tip shrink in plan.
func _half(ax: float, s: float, z_le: float, ch: float, top: bool, u0: float, u1: float, sag: float = 0.0, thick: float = 1.0) -> PackedVector3Array:
	var ring := PackedVector3Array()
	var y0 := _wing_y(ax)
	var us: Array = []
	for i in range(14):
		var f := float(i) / 13.0
		us.append(u0 + (u1 - u0) * (f * f * 0.5 + (1.0 - cos(PI * f)) * 0.25))   # bunched at the nose
	for u: float in us:
		var fy: float = _foil(FOIL_TOP if top else FOIL_BOT, u) * thick
		var dip := sag * sin(PI * clampf((u - 0.12) / 0.75, 0.0, 1.0)) if top else 0.0
		ring.append(Vector3(s * ax, y0 + (fy - dip) * ch, z_le + u * ch))
	for i in range(us.size() - 2, 0, -1):
		var u2: float = us[i]
		var mid: float = (_foil(FOIL_TOP, u2) + _foil(FOIL_BOT, u2)) * 0.5 * thick
		ring.append(Vector3(s * ax, y0 + mid * ch, z_le + u2 * ch))
	return ring


## The outer curve of each half-ring (the first 14 points) skinned with
## explicit winding: each face points away from the chord line under it -
## no centroid guessing (the thin half-foils fooled it: the dark underside).
func _skin(k: MeshKit, rings: Array, col: Color, caps: bool = false) -> void:
	for r in range(rings.size() - 1):
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		var n := 14
		var m := a.size()
		for i in range(n - 1):
			# the chord-line points under this segment (the ring's return path)
			var ca: Vector3 = (a[0] if i == 0 else a[m - i]) + (b[0] if i == 0 else b[m - i])
			var cb: Vector3 = (a[n - 1] if i + 1 == n - 1 else a[m - i - 1]) + (b[n - 1] if i + 1 == n - 1 else b[m - i - 1])
			var ch_mid: Vector3 = (ca + cb) * 0.25
			var face_mid: Vector3 = (a[i] + a[i + 1] + b[i] + b[i + 1]) * 0.25
			var hint := face_mid - ch_mid
			if hint.length() < 1e-5:
				hint = Vector3(0, 0, 1)
			k.quad(a[i], a[i + 1], b[i + 1], b[i], col, hint)
	if caps:
		for ring in [rings[0], rings[rings.size() - 1]]:
			var rr: PackedVector3Array = ring
			var c := Vector3.ZERO
			for v in rr:
				c += v
			c /= float(rr.size())
			var other: PackedVector3Array = rings[1] if ring == rings[0] else rings[rings.size() - 2]
			var oc := Vector3.ZERO
			for v2 in other:
				oc += v2
			oc /= float(other.size())
			for i2 in range(rr.size()):
				k.tri(c, rr[i2], rr[(i2 + 1) % rr.size()], col, c - oc)


## Where the windshield is at (x, y): the same wrap as _windows_and_doors()
## builds (front line round the corner to the front post).
func _windshield_z(x: float, y: float) -> float:
	var p0: Vector2 = POST_F[0]
	var p1: Vector2 = POST_F[1]
	var u := clampf((y - 0.245) / (0.668 - 0.245), 0.0, 1.0)
	var zc := lerpf(-1.00, -0.375, u) - 0.03 * sin(PI * u)
	var zp := p0.x + (y - p0.y) / (p1.y - p0.y) * (p1.x - p0.x)
	var best := zc
	var bd := 1e9
	for j in range(41):
		var th := lerpf(0.0, PI * 0.5, float(j) / 40.0)
		var zz := zc + (zp - zc) * (1.0 - cos(th))
		var xx := (_side_x(zz, y) + 0.002) * sin(th)
		if absf(xx - absf(x)) < bd:
			bd = absf(xx - absf(x))
			best = zz
	return best


## Join (Blender's Ctrl+J, Dave): pieces that are really one component go
## under it - they move, break off and come off with it, and a breakable
## part is never left behind floating. Moving parts (doors, surfaces, the
## prop, wheels) stay their own; fixed trim joins what it's fastened to.
const JOINS := {
	"Fuselage": ["CabinShell", "SideWindowsL", "SideWindowsR", "CenterSection", "Details", "BaggageBay", "StrutFittingL", "StrutFittingR", "CowlHinge"],
	"WingL": ["LightsL"], "WingR": ["LightsR"],
	"Fin": ["LightsTail"],
	"StrutRearL": ["JuryL"], "StrutRearR": ["JuryR"],
	"Engine": ["IntakeTube"],
}


func _join_components() -> void:
	for into: String in JOINS.keys():
		var t := _root.get_node_or_null(into) as Node3D
		if t == null:
			continue
		for nm: String in JOINS[into]:
			var n := _root.get_node_or_null(nm) as Node3D
			if n == null:
				continue
			n.remove_meta("part")
			n.reparent(t, true)


## A rib-shaped face closing the wing at station ax, from u0 to u1 of the
## chord, facing `facing` along x.
func _wing_rib(k: MeshKit, s: float, ax: float, u0: float, u1: float, facing: float) -> void:
	var pts: Array = []
	for i in range(15):
		var u := lerpf(u0, u1, float(i) / 14.0)
		var z := LE_Z + u * CHORD
		pts.append(Vector3(s * ax, _wtop(ax, z), z))
	for i2 in range(14, -1, -1):
		var u2 := lerpf(u0, u1, float(i2) / 14.0)
		var z2 := LE_Z + u2 * CHORD
		pts.append(Vector3(s * ax, _wbot(ax, z2), z2))
	var c := Vector3.ZERO
	for v in pts:
		c += v
	c /= float(pts.size())
	for j in range(pts.size()):
		k.tri(c, pts[j], pts[(j + 1) % pts.size()], _fix(base), Vector3(facing, 0, 0))


func _plan(ax: float) -> Array:
	# the round tip: the last 0.80 m is a half-round in plan (3-view top)
	var tr := 0.80
	var k := clampf((ax - (SPAN_HALF - tr)) / tr, 0.0, 1.0)
	var h := sqrt(maxf(1.0 - k * k, 0.0))
	var ch := CHORD * maxf(h, 0.04)
	var zc := LE_Z + CHORD * 0.5
	return [zc - ch * 0.5, ch, lerpf(1.0, 0.55, k)]


func _wing(s: float) -> void:
	var side := "L" if s < 0.0 else "R"
	var p := _part("Wing" + side)
	var aileron0 := SPAN_HALF - 0.80 - 2.45
	var flap0 := ROOT_X + 0.03
	# stations: every rib (0.36 m apart) plus mid-bay points for the sag
	var stations: Array = [ROOT_X, flap0 - 0.002]
	var ax := flap0
	while ax < SPAN_HALF - 0.80:
		stations.append(ax)
		ax += 0.36
	stations.append(SPAN_HALF - 0.80)
	stations.append(SPAN_HALF - 0.80 + 0.002)
	for k in range(9):
		stations.append(SPAN_HALF - 0.80 + 0.80 * (1.0 - cos(PI * 0.5 * float(k + 1) / 9.0)))
	var ribs: Array = []
	var r0 := ROOT_X + 0.02
	while r0 < SPAN_HALF - 0.6:
		ribs.append(r0)
		r0 += 0.36
	for top: bool in [true, false]:
		var rings: Array = []
		for st: float in stations:
			var pl := _plan(st)
			var bay := fposmod(st - ROOT_X - 0.02, 0.36) / 0.36
			var sag := 0.0
			# the moving surfaces are cut out of the back 28% where they are
			var u1 := 1.0
			if st >= flap0 - 0.0005 and st <= SPAN_HALF - 0.80 + 0.0005:
				u1 = 0.72
			rings.append(_half(st, s, pl[0], pl[1], top, 0.0, u1, sag, pl[2]))
		_skin(p.paint, rings, _fix(wing_top if top else base))
	# closing faces (the reversed-face check: the wing was open at its root,
	# behind the false spar where the flaps and ailerons are cut out, and at the
	# ends of those cut-outs - you could see into it, or through it)
	var tip0 := SPAN_HALF - 0.80
	_wing_rib(p.paint, s, ROOT_X, 0.0, 1.0, -s)                           # the root rib, facing the cabin
	_wing_rib(p.paint, s, flap0 - 0.002, 0.72, 1.0, s)                    # the cut-out's inboard end
	_wing_rib(p.paint, s, tip0 + 0.002, 0.72, 1.0, -s)                    # ... and outboard end
	var sp_x: Array = []
	for st2: float in stations:
		if st2 >= flap0 - 0.0005 and st2 <= tip0 + 0.0005:
			sp_x.append(st2)
	for i5 in range(sp_x.size() - 1):
		var xa: float = sp_x[i5]
		var xb: float = sp_x[i5 + 1]
		var zs := LE_Z + 0.72 * CHORD
		p.paint.quad(Vector3(s * xa, _wtop(xa, zs), zs), Vector3(s * xb, _wtop(xb, zs), zs), Vector3(s * xb, _wbot(xb, zs), zs), Vector3(s * xa, _wbot(xa, zs), zs), _fix(base), Vector3(0, 0, 1))   # the false spar
	# rib-stitch tapes on top and bottom
	for rx: float in ribs:
		var tape: Array = []
		var tape2: Array = []
		for k in range(12):
			var u := float(k) / 11.0 * 0.72
			var z := LE_Z + u * CHORD
			tape.append(Vector3(s * rx, _wtop(rx, z) + 0.002, z))
			tape2.append(Vector3(s * rx, _wbot(rx, z) - 0.002, z))
		_tube(p.paint, tape, 0.0025, _fix(wing_top.darkened(0.05)))
		_tube(p.paint, tape2, 0.0025, _fix(base.darkened(0.05)))
	# leading-edge metal shows as a faint line at 15% chord on top
	var le: Array = []
	for rx2: float in [ROOT_X, 2.0, 4.0, SPAN_HALF - 0.8]:
		le.append(Vector3(s * rx2, _wtop(rx2, LE_Z + 0.15 * CHORD) + 0.002, LE_Z + 0.15 * CHORD))
	_tube(p.paint, le, 0.003, _fix(wing_top.darkened(0.08)))
	# fuel cap in the root of each wing, a vent, the stall-warning vane (left)
	var cap_at := Vector3(s * 0.75, _wtop(0.75, -0.05), -0.05)
	p.dark.cylinder(Transform3D(Basis.IDENTITY, cap_at + Vector3(0, -0.03, 0)), 0.035, 0.035, 0.03, 16, Color(0.03, 0.03, 0.03), true)   # the filler neck (dark when open)
	p.metal.cylinder(Transform3D(Basis.IDENTITY, cap_at + Vector3(0, -0.004, 0)), 0.05, 0.05, 0.006, 16, Color(0.6, 0.6, 0.6), true)
	var fc := _part("FuelCap" + side)
	fc.metal.cylinder(Transform3D(Basis.IDENTITY, cap_at + Vector3(0, -0.002, 0)), 0.042, 0.042, 0.016, 16, Color(0.78, 0.78, 0.78), true)
	fc.metal.box_at(cap_at + Vector3(0, 0.020, 0), Vector3(0.07, 0.012, 0.012), Color(0.6, 0.6, 0.6))
	_done(fc)
	_caps.append([fc.node, cap_at])
	_tube(p.dark, [Vector3(s * 0.90, _wbot(0.9, -0.1), -0.1), Vector3(s * 0.90, _wbot(0.9, -0.1) - 0.06, -0.16)], 0.005, Color(0.1, 0.1, 0.1))
	if s < 0.0:
		p.metal.box_at(Vector3(-2.3, _wing_y(2.3) + 0.005, LE_Z - 0.006), Vector3(0.04, 0.012, 0.012), Color(0.7, 0.7, 0.7))
		_tube(p.metal, [Vector3(-3.9, _wbot(3.9, LE_Z + 0.3), LE_Z + 0.3), Vector3(-3.9, _wbot(3.9, LE_Z + 0.3) - 0.10, LE_Z + 0.25), Vector3(-3.9, _wbot(3.9, LE_Z + 0.3) - 0.10, LE_Z - 0.15)], 0.008, Color(0.8, 0.8, 0.8))
	# strut fittings under the wing
	for sp: float in [SPAR_F, SPAR_R]:
		p.metal.box_at(Vector3(s * STRUT_X, _wbot(STRUT_X, LE_Z + sp * CHORD) - 0.02, LE_Z + sp * CHORD), Vector3(0.04, 0.05, 0.06), Color(0.5, 0.5, 0.5))
	_done(p)
	# flap (inboard) and aileron (outboard): the back 28%, hinged at the top
	for cs in [["Flap", flap0, aileron0 - 0.02], ["Aileron", aileron0, SPAN_HALF - 0.80]]:
		var q := _part(String(cs[0]) + side)
		var a0: float = cs[1]
		var a1: float = cs[2]
		var hz := LE_Z + 0.72 * CHORD
		q.node.set_meta("hinge", Vector3(s * (a0 + a1) * 0.5, _wtop((a0 + a1) * 0.5, hz), hz))
		for top2: bool in [true, false]:
			var r2: Array = []
			var a := a0
			while a < a1 + 0.001:
				r2.append(_half(a, s, LE_Z, CHORD, top2, 0.725, 1.0))
				a += minf(0.36, a1 - a) if a1 - a > 0.01 else 1.0
			_skin(q.paint, r2, _fix(wing_top if top2 else base), true)
		var zf2 := LE_Z + 0.725 * CHORD
		var xs2: Array = []
		var a2 := a0
		while a2 < a1 + 0.001:
			xs2.append(a2)
			a2 += minf(0.36, a1 - a2) if a1 - a2 > 0.01 else 1.0
		for i6 in range(xs2.size() - 1):
			var xa2: float = xs2[i6]
			var xb2: float = xs2[i6 + 1]
			q.paint.quad(Vector3(s * xa2, _wtop(xa2, zf2), zf2), Vector3(s * xb2, _wtop(xb2, zf2), zf2), Vector3(s * xb2, _wbot(xb2, zf2), zf2), Vector3(s * xa2, _wbot(xa2, zf2), zf2), _fix(base), Vector3(0, 0, -1))   # its nose, closed
		var rx3 := a0 + 0.18
		while rx3 < a1:
			var t3: Array = []
			for k in range(4):
				var z3 := LE_Z + (0.725 + 0.275 * float(k) / 3.0) * CHORD
				t3.append(Vector3(s * rx3, _wtop(rx3, z3) + 0.002, z3))
			_tube(q.paint, t3, 0.0025, _fix(wing_top.darkened(0.05)))
			rx3 += 0.36
		# hinges and the control horn
		for hx: float in [a0 + 0.15, (a0 + a1) * 0.5, a1 - 0.15]:
			q.metal.box_at(Vector3(s * hx, _wbot(hx, hz) - 0.012, hz), Vector3(0.025, 0.03, 0.04), Color(0.55, 0.55, 0.55))
		q.metal.box_at(Vector3(s * (a0 + 0.4), _wbot(a0 + 0.4, hz + 0.08) - 0.04, hz + 0.08), Vector3(0.006, 0.07, 0.05), Color(0.6, 0.6, 0.6))
		_done(q)


## Between the wing roots over the cabin: the skylight (3-view top: the
## clear panel), the roots' fairing strips fore and aft of it.
func _center_section() -> void:
	var p := _part("CenterSection")
	var x := ROOT_X
	for top: bool in [true, false]:
		var rings: Array = []
		for xx: float in [-x, 0.0, x]:
			rings.append(_half(absf(xx), signf(xx) if xx != 0.0 else 1.0, LE_Z, CHORD, top, 0.0, 0.14))
		# explicit winding (_skin): the plain loft's centroid guess flipped the
		# thin underside - from the cabin it hung down as a jagged black sheet
		_skin(p.paint, [_half(x, -1.0, LE_Z, CHORD, top, 0.0, 0.14), _half(0.0, 1.0, LE_Z, CHORD, top, 0.0, 0.14), _half(x, 1.0, LE_Z, CHORD, top, 0.0, 0.14)], _fix(wing_top if top else base))
		_skin(p.paint, [_half(x, -1.0, LE_Z, CHORD, top, 0.62, 1.0), _half(0.0, 1.0, LE_Z, CHORD, top, 0.62, 1.0), _half(x, 1.0, LE_Z, CHORD, top, 0.62, 1.0)], _fix(wing_top if top else base))
	# the skylight's front and back walls (the fairings' faces into the opening)
	for ue: Array in [[0.14, 1.0], [0.62, -1.0]]:
		var ze := LE_Z + float(ue[0]) * CHORD
		p.paint.quad(Vector3(-x, _wtop(x, ze), ze), Vector3(x, _wtop(x, ze), ze), Vector3(x, _wbot(x, ze), ze), Vector3(-x, _wbot(x, ze), ze), _fix(base.darkened(0.2)), Vector3(0, 0, float(ue[1])))
	# the skylight glass between, curved with the wing's top
	var z0 := LE_Z + 0.14 * CHORD
	var z1 := LE_Z + 0.62 * CHORD
	for k in range(6):
		var za := lerpf(z0, z1, float(k) / 6.0)
		var zb := lerpf(z0, z1, float(k + 1) / 6.0)
		p.glass.quad(Vector3(-x, _wtop(x, za), za), Vector3(x, _wtop(x, za), za), Vector3(x, _wtop(x, zb), zb), Vector3(-x, _wtop(x, zb), zb), Color.WHITE, Vector3(0, 1, 0))
	_tube(p.dark, [Vector3(-x, _wtop(x, z0), z0), Vector3(x, _wtop(x, z0), z0)], 0.008, Color(0.05, 0.05, 0.05))
	_tube(p.dark, [Vector3(-x, _wtop(x, z1), z1), Vector3(x, _wtop(x, z1), z1)], 0.008, Color(0.05, 0.05, 0.05))
	# the aft root fairing (Dave, from behind: a dark slot between the cabin
	# top and the wing): fabric from the wing's trailing edge across the
	# whole root, sloping down onto the turtledeck behind it
	# (Dave: smooth it all out) one curved sheet: across, a rounded crown that
	# comes down onto the skin at its edges (no side walls); along, it eases
	# from the wing's trailing edge down onto the turtledeck (tangent at the deck)
	var zt := LE_Z + CHORD - 0.03
	var zd := zt + 0.42
	var nrw := 12
	var ncl := 33
	var grid: Array = []
	for r in range(nrw):
		var t := float(r) / float(nrw - 1)
		var z := lerpf(zt, zd, t)
		var drop := 1.0 - (t * t * (3.0 - 2.0 * t))                # 1 at the wing, 0 on the deck
		var W := lerpf(0.31, 0.24, t)          # on the top only, clear of the windows
		var row: Array = []
		for c in range(ncl):
			var u := lerpf(-1.0, 1.0, float(c) / float(ncl - 1))
			var fx := u * W
			var ys := _skin_top(z, fx)
			var crown := 1.0 - pow(absf(u), 5.0)
			var y := ys + maxf(_wbot(ROOT_X, z) + 0.004 - ys, 0.0) * drop * crown + 0.003
			row.append(Vector3(fx, y, z))
		grid.append(row)
	for r in range(nrw - 1):
		var ra: Array = grid[r]
		var rb: Array = grid[r + 1]
		for c in range(ncl - 1):
			var fm: Vector3 = (ra[c] + ra[c + 1] + rb[c] + rb[c + 1]) * 0.25
			p.paint.quad(ra[c], ra[c + 1], rb[c + 1], rb[c], BANDED, Vector3(fm.x * 2.0, 1.0, 0.5))
	# the cabin's headliner under it (so you look into the cabin, not at paint)
	# (the cabin roof is cut open under it: you look up through the skylight)
	_done(p)


# ------------------------------------------------------------------------------
#  Struts: the V struts from one fitting on the lower longeron out to the
#  front and rear spars, the jury struts part way out (3-view front/top)
# ------------------------------------------------------------------------------
func _streamline(k: MeshKit, a: Vector3, b: Vector3, w: float, t: float, col: Color) -> void:
	var d := (b - a).normalized()
	var side := d.cross(Vector3.BACK).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var fwd := side.cross(d).normalized()
	if fwd.z > 0.0:
		fwd = -fwd
	var rings: Array = []
	for f: float in [0.0, 1.0]:
		var c: Vector3 = a.lerp(b, f)
		var ring := PackedVector3Array()
		for q in [Vector2(0.5, 0), Vector2(0.3, 0.45), Vector2(-0.1, 0.48), Vector2(-0.5, 0), Vector2(-0.1, -0.48), Vector2(0.3, -0.45)]:
			ring.append(c + fwd * (float(q.x) * w) + side * (float(q.y) * t))
		rings.append(ring)
	k.loft(rings, col, true, true)


func _struts(s: float) -> void:
	var side := "L" if s < 0.0 else "R"
	var foot := Vector3(s * 0.37, -0.61, 0.15)
	var tops := [Vector3(s * STRUT_X, _wbot(STRUT_X, LE_Z + SPAR_F * CHORD) - 0.035, LE_Z + SPAR_F * CHORD),
		Vector3(s * STRUT_X, _wbot(STRUT_X, LE_Z + SPAR_R * CHORD) - 0.035, LE_Z + SPAR_R * CHORD)]
	var names := ["StrutFront", "StrutRear"]
	var col := _fix(base.darkened(0.03))
	for i in range(2):
		var p := _part(String(names[i]) + side)
		var top: Vector3 = tops[i]
		_streamline(p.paint, foot, top, 0.075 if i == 0 else 0.060, 0.028 if i == 0 else 0.024, col)
		p.metal.box_at(top + Vector3(0, 0.02, 0), Vector3(0.03, 0.05, 0.05), Color(0.45, 0.45, 0.45))
		_done(p)
	# the strut foot fitting on the fuselage
	var ft := _part("StrutFitting" + side)
	ft.metal.box_at(foot + Vector3(-s * 0.01, 0, 0), Vector3(0.04, 0.06, 0.10), Color(0.45, 0.45, 0.45))
	_done(ft)
	# jury struts: from each strut up to its spar, and a brace across
	var j := _part("Jury" + side)
	var pts: Array = []
	for i in range(2):
		var top2: Vector3 = tops[i]
		var f := (JURY_X - absf(foot.x)) / (STRUT_X - absf(foot.x))
		var on: Vector3 = foot.lerp(top2, f)
		pts.append(on)
		_tube(j.paint, [on, Vector3(on.x + s * 0.12, _wbot(absf(on.x) + 0.12, on.z) - 0.01, on.z)], 0.011, col)
	_tube(j.paint, [pts[0], Vector3((pts[1] as Vector3).x + s * 0.12, _wbot(absf((pts[1] as Vector3).x) + 0.12, (pts[1] as Vector3).z) - 0.01, (pts[1] as Vector3).z)], 0.009, col)
	_done(j)


# ------------------------------------------------------------------------------
#  Gear: the split-axle gear - each axle hinged under the belly on a V of
#  tubes, the shock strut up to the fuselage side with the bungee cords in
#  their cover; tundra tyres (photos 01/02)
# ------------------------------------------------------------------------------
func _main_gear(s: float) -> void:
	var side := "L" if s < 0.0 else "R"
	var g := _part("Gear" + side)
	var hub := Vector3(s * AXLE.x, AXLE.y, AXLE.z)
	var inner := Vector3(s * (AXLE.x - 0.17), AXLE.y, AXLE.z)
	var gc := _fix(base.darkened(0.05))
	# the V to the belly centre (front and rear)
	_tube(g.paint, [inner, Vector3(s * 0.04, -0.655, -0.37)], 0.020, gc)
	_tube(g.paint, [inner + Vector3(0, 0, 0.02), Vector3(s * 0.04, -0.655, 0.21)], 0.018, gc)
	# the shock strut: a fat tube up to the fuselage side, its cover over the bungees at the top
	var strut_top := Vector3(s * 0.37, -0.52, -0.37)      # down at the lower longeron (Dave: lower it)
	_tube(g.paint, [inner + Vector3(s * 0.04, 0.04, 0), strut_top], 0.024, gc)
	var bc := strut_top.lerp(inner, 0.18)
	g.paint.box(Transform3D(Basis.looking_at((strut_top - inner).normalized(), Vector3.BACK).rotated(Vector3.UP, 0.0), bc), Vector3(0.09, 0.09, 0.20), BANDED)
	for k in range(4):
		var c2 := strut_top.lerp(inner, 0.10 + float(k) * 0.035)
		g.dark.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c2 + Vector3(0, 0, -0.05)), 0.03, 0.03, 0.10, 10, Color(0.05, 0.05, 0.05), true)
	# the axle fitting where the legs meet, the axle through to the wheel's
	# centre, the brake disc and caliper on the inboard side of the hub
	g.metal.box_at(inner, Vector3(0.07, 0.07, 0.09), Color(0.50, 0.50, 0.50))
	g.metal.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5 * -s), inner), 0.022, 0.022, AXLE.x - absf(inner.x) + 0.02, 12, Color(0.62, 0.62, 0.62), true)
	g.dark.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5 * -s), inner + Vector3(s * 0.04, 0, 0)), 0.075, 0.075, 0.012, 18, Color(0.35, 0.35, 0.36), true)
	g.dark.box_at(inner + Vector3(s * 0.05, 0.06, -0.03), Vector3(0.04, 0.05, 0.06), Color(0.12, 0.12, 0.12))
	_done(g)
	var wn := Node3D.new()
	wn.name = "Wheel" + side
	wn.position = hub
	wn.set_meta("part", true)
	_root.add_child(wn)
	var wmi := MeshInstance3D.new()
	wmi.name = "Wheel"
	wmi.mesh = TyreMesh.wheel(TYRE_R, TYRE_W, 0.085, "tundra", "slot", s, [0.0], "", Color(0.80, 0.80, 0.78))
	var tm := ShaderMaterial.new()
	tm.shader = TYRE_SQUASH
	tm.set_shader_parameter("radius", TYRE_R)
	tm.set_shader_parameter("rim_r", 0.085)
	wmi.material_override = tm
	wmi.set_instance_shader_parameter("squash", 0.045)
	wn.add_child(wmi)
	_wheels.append(wmi)


func _tail_gear() -> void:
	var p := _part("TailGear")
	# the leaf spring from under the tail post back and down to the fork
	var a := Vector3(0, -0.01, 4.30)
	var b := Vector3(0, -0.05, 4.70)
	var rings: Array = []
	for f: float in [0.0, 0.5, 1.0]:
		var c: Vector3 = a.lerp(b, f) + Vector3(0, -0.02 * sin(PI * f), 0)
		var w := lerpf(0.045, 0.030, f)
		var ring := PackedVector3Array()
		for q in [Vector2(-w, -0.008), Vector2(w, -0.008), Vector2(w, 0.008), Vector2(-w, 0.008)]:
			ring.append(c + Vector3(q.x, q.y, 0))
		rings.append(ring)
	p.dark.loft(rings, Color(0.12, 0.12, 0.12), true, true)
	p.metal.box_at(b + Vector3(0, -0.02, 0.04), Vector3(0.05, 0.05, 0.08), Color(0.5, 0.5, 0.5))
	for s: float in [-1.0, 1.0]:
		_tube(p.metal, [b + Vector3(s * 0.045, -0.02, 0.04), TAIL_HUB + Vector3(s * 0.045, 0, 0)], 0.008, Color(0.5, 0.5, 0.5))
		# steering springs and chains to the rudder horns
		_tube(p.dark, [b + Vector3(s * 0.03, 0.0, 0.0), Vector3(s * 0.12, 0.10, 4.62)], 0.004, Color(0.25, 0.25, 0.25))
	_done(p)
	var wn := Node3D.new()
	wn.name = "TailWheel"
	wn.position = TAIL_HUB
	wn.set_meta("part", true)
	_root.add_child(wn)
	var wmi := MeshInstance3D.new()
	wmi.mesh = TyreMesh.wheel(TAILTYRE_R, 0.075, 0.045, "highway", "slot", 1.0, [0.0], "", Color(0.85, 0.85, 0.82))
	wn.add_child(wmi)


# ------------------------------------------------------------------------------
#  Tail: the round stabiliser and elevator, the triangular fin and the big
#  round rudder (3-view side / top), fabric with rib tapes, the brace wires
# ------------------------------------------------------------------------------
const STAB_Y := 0.40
const STAB_B := 1.55          # half span
const HINGE_E := 4.34
const HINGE_R := 4.51
## the rudder's back edge, (y, z) from the side view
const RUDDER := [Vector2(0.03, 4.55), Vector2(0.06, 4.73), Vector2(0.25, 4.94), Vector2(0.61, 5.00), Vector2(0.95, 4.99), Vector2(1.20, 4.95), Vector2(1.35, 4.89), Vector2(1.45, 4.82), Vector2(1.53, 4.73), Vector2(1.59, 4.62), Vector2(1.615, 4.53)]
## the fin's leading edge, (y, z): convex, rolling over the top into the
## rudder's round top (3-view side - Dave: the tail was pointy)
const FIN_LE := [Vector2(0.50, 3.62), Vector2(0.62, 3.80), Vector2(0.75, 3.92), Vector2(0.90, 4.00), Vector2(1.05, 4.06), Vector2(1.20, 4.10), Vector2(1.32, 4.15), Vector2(1.42, 4.22), Vector2(1.50, 4.29), Vector2(1.56, 4.37), Vector2(1.60, 4.45), Vector2(1.615, 4.505)]


static func _fin_le(y: float) -> float:
	for i in range(FIN_LE.size() - 1):
		var a: Vector2 = FIN_LE[i]
		var b: Vector2 = FIN_LE[i + 1]
		if y >= a.x and y <= b.x:
			return lerpf(a.y, b.y, (y - a.x) / maxf(b.x - a.x, 1e-4))
	return (FIN_LE[FIN_LE.size() - 1] as Vector2).y


func _thin(c: Vector3, ch: float, th: float, along: Vector3, across: Vector3) -> PackedVector3Array:
	# a thin symmetric section: along = chord direction, across = thickness direction
	var ring := PackedVector3Array()
	for q in [Vector2(0.0, 0.0), Vector2(0.05, 0.55), Vector2(0.25, 1.0), Vector2(0.6, 0.7), Vector2(1.0, 0.08), Vector2(1.0, -0.08), Vector2(0.6, -0.7), Vector2(0.25, -1.0), Vector2(0.05, -0.55)]:
		ring.append(c + along * (q.x * ch) + across * (q.y * th * 0.5))
	return ring


func _tail() -> void:
	var st := _part("Stabiliser")
	var el := _part("Elevator")
	el.node.set_meta("hinge", Vector3(0, STAB_Y, HINGE_E))
	var srings: Array = []
	var erings: Array = []
	for k in range(15):
		var x := lerpf(-STAB_B, STAB_B, (1.0 - cos(PI * float(k) / 14.0)) * 0.5)
		var e := sqrt(maxf(1.0 - pow(absf(x) / STAB_B, 2.2), 0.0))
		var fr := maxf(0.72 * pow(e, 0.8), 0.02)
		var af := maxf(0.57 * pow(e, 0.9), 0.02)
		srings.append(_thin(Vector3(x, STAB_Y, HINGE_E - fr), fr, 0.050 * maxf(e, 0.3), Vector3.BACK, Vector3.UP))
		erings.append(_thin(Vector3(x, STAB_Y, HINGE_E + 0.008), af, 0.030 * maxf(e, 0.3), Vector3.BACK, Vector3.UP))
	st.paint.loft(srings, _fix(base), true, true)
	el.paint.loft(erings, _fix(wing_top), true, true)
	# rib tapes
	for x2: float in [-1.3, -1.0, -0.7, -0.4, 0.4, 0.7, 1.0, 1.3]:
		var e2 := sqrt(maxf(1.0 - pow(absf(x2) / STAB_B, 2.2), 0.0))
		_tube(st.paint, [Vector3(x2, STAB_Y + 0.022 * e2, HINGE_E - 0.70 * e2), Vector3(x2, STAB_Y + 0.016, HINGE_E - 0.02)], 0.003, _fix(base.darkened(0.08)))
		_tube(el.paint, [Vector3(x2, STAB_Y + 0.014, HINGE_E + 0.02), Vector3(x2, STAB_Y + 0.004, HINGE_E + 0.55 * e2)], 0.003, _fix(wing_top.darkened(0.12)))
	el.metal.box_at(Vector3(0.15, STAB_Y - 0.05, HINGE_E + 0.05), Vector3(0.006, 0.08, 0.05), Color(0.6, 0.6, 0.6))   # the horn
	_done(st)
	_done(el)
	# the fin: root from the turtledeck, its leading edge up to the top of the hinge
	var fn := _part("Fin")
	var frings: Array = []
	for k in range(FIN_LE.size()):
		var le: Vector2 = FIN_LE[k]
		var f := (le.x - 0.50) / 1.115
		frings.append(_thin(Vector3(0, le.x, le.y), maxf(HINGE_R - le.y, 0.008), 0.055 * (1.0 - 0.6 * f) * (1.0 if k < FIN_LE.size() - 1 else 0.3), Vector3.BACK, Vector3.RIGHT))
	fn.paint.loft(frings, _fix(base), true, true)
	for y2: float in [0.75, 1.0, 1.25]:
		var zl := _fin_le(y2)
		for sx: float in [-1.0, 1.0]:
			_tube(fn.paint, [Vector3(sx * 0.014, y2, zl + 0.05), Vector3(sx * 0.008, y2, HINGE_R - 0.02)], 0.003, _fix(base.darkened(0.08)))
	_done(fn)
	# the rudder: the big round one
	var rd := _part("Rudder")
	rd.node.set_meta("hinge", Vector3(0, 0.8, HINGE_R))
	var rrings: Array = []
	for i in range(RUDDER.size()):
		var q: Vector2 = RUDDER[i]
		var ch2 := maxf(q.y - HINGE_R, 0.012)
		rrings.append(_thin(Vector3(0, q.x, HINGE_R + 0.008), ch2, 0.034, Vector3.BACK, Vector3.RIGHT))
	rd.paint.loft(rrings, _fix(wing_top), true, true)
	for y3: float in [0.30, 0.60, 0.90, 1.20]:
		for sx2: float in [-1.0, 1.0]:
			var zb := 4.98 if y3 < 1.0 else 4.86
			_tube(rd.paint, [Vector3(sx2 * 0.012, y3, HINGE_R + 0.03), Vector3(sx2 * 0.006, y3, zb - 0.04)], 0.003, _fix(wing_top.darkened(0.12)))
	for hy: float in [0.15, 0.80, 1.40]:
		rd.metal.box_at(Vector3(0, hy, HINGE_R), Vector3(0.035, 0.03, 0.03), Color(0.5, 0.5, 0.5))
	for sx3: float in [-1.0, 1.0]:
		rd.metal.box_at(Vector3(sx3 * 0.08, 0.08, HINGE_R + 0.02), Vector3(0.12, 0.012, 0.02), Color(0.55, 0.55, 0.55))   # the horns
	_done(rd)
	# brace wires: two over each side of the stab to the fin, two under to the fuselage
	var w := _part("TailWires")
	for sx4: float in [-1.0, 1.0]:
		for zz: float in [4.02, 4.28]:
			_tube(w.metal, [Vector3(0, 1.02, zz + 0.08), Vector3(sx4 * 0.92, STAB_Y + 0.02, zz)], 0.0035, Color(0.7, 0.7, 0.72))
			_tube(w.metal, [Vector3(sx4 * 0.92, STAB_Y - 0.02, zz), Vector3(sx4 * 0.10, -0.06, zz - 0.05)], 0.0035, Color(0.7, 0.7, 0.72))
	_done(w)


# ------------------------------------------------------------------------------
#  Lights: nav lights in the tips, the tail light, the landing light
# ------------------------------------------------------------------------------
func _lights() -> void:
	# each light belongs to what it's built into (Dave: join things like in
	# Blender) - the wingtip, landing and taxi lights with their wing, the tail
	# light and beacon with the tail - so they go wherever that part goes
	var pl := _part("LightsL")
	var pr := _part("LightsR")
	var pt := _part("LightsTail")
	for s: float in [-1.0, 1.0]:
		var pw: Part = pl if s < 0.0 else pr
		var c := Vector3(s * (SPAN_HALF - 0.02), _wing_y(SPAN_HALF) + 0.01, LE_Z + CHORD * 0.42)
		_lamp(pw, c, Color(1.0, 0.1, 0.08) if s < 0.0 else Color(0.1, 1.0, 0.25), "Nav%dBulb" % int(s))
		_bulb(pw.node, "StrobeTip%dBulb" % int(s), c + Vector3(0, 0, 0.05), 0.008, Color(1, 1, 1))   # the tip strobe behind the nav lens
		var o := OmniLight3D.new()
		o.name = "NavLightL" if s < 0.0 else "NavLightR"
		o.position = c
		o.light_color = Color(1.0, 0.1, 0.08) if s < 0.0 else Color(0.1, 1.0, 0.25)
		o.omni_range = 2.5
		o.light_energy = 1.2
		o.visible = false
		pw.node.add_child(o)
		var o2 := OmniLight3D.new()
		o2.name = "StrobeL" if s < 0.0 else "StrobeR"
		o2.position = Vector3(s * (SPAN_HALF + 0.02), _wing_y(SPAN_HALF), LE_Z + CHORD * 0.5)
		o2.light_color = Color(1, 1, 1)
		o2.omni_range = 9.0
		o2.light_energy = 0.0
		pw.node.add_child(o2)
		# the landing light (left) and taxi light (right) in the leading edges: a
		# recess into the nose, a chrome reflector bowl, the bulb, and the clear
		# prism-cell cover flush with the leading edge (as the truck's lamps)
		var lc := Vector3(2.4 * s, _wing_y(2.4) + 0.016, LE_Z + 0.004)
		var nm := "LandingBulb" if s < 0.0 else "TaxiBulb"
		pw.dark.box_at(lc + Vector3(0, 0, 0.028), Vector3(0.20, 0.044, 0.05), Color(0.03, 0.03, 0.03))
		pw.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), lc + Vector3(0, 0, 0.022)), 0.020, 0.008, 0.026, 20, Color(0.95, 0.95, 0.96), false)
		_bulb(pw.node, nm, lc + Vector3(0, 0, 0.016), 0.010, Color(1.0, 0.9, 0.7))
		var lens := MeshInstance3D.new()
		lens.name = "LandingLens" if s < 0.0 else "TaxiLens"
		var lb := BoxMesh.new()
		lb.size = Vector3(0.20, 0.046, 0.003)
		lens.mesh = lb
		lens.position = lc + Vector3(0, 0, -0.004)
		lens.material_override = _lens_mat(Color(0.92, 0.95, 0.97, 0.14), 1.0)
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pw.node.add_child(lens)
	_lamp(pt, Vector3(0, 0.62, 5.02), Color(1, 1, 0.95), "TailNavBulb")
	_lamp(pt, Vector3(0, 1.63, 4.50), Color(1.0, 0.25, 0.2), "BeaconBulb")      # the red beacon on the fin top
	var ot := OmniLight3D.new()
	ot.name = "NavLightTail"
	ot.position = Vector3(0, 0.62, 5.06)
	ot.light_color = Color(1, 1, 0.95)
	ot.omni_range = 2.5
	ot.light_energy = 1.2
	ot.visible = false
	pt.node.add_child(ot)
	var ob := OmniLight3D.new()
	ob.name = "Beacon"
	ob.position = Vector3(0, 1.70, 4.50)
	ob.light_color = Color(1.0, 0.2, 0.15)
	ob.omni_range = 9.0
	ob.light_energy = 0.0
	pt.node.add_child(ob)
	_done(pl)
	_done(pr)
	_done(pt)


func _lamp(p: Part, c: Vector3, col: Color, nm: String) -> void:
	# a small coloured glass dome, the bulb inside it
	var srings: Array = []
	for k in range(5):
		var t := float(k) / 4.0
		var r := 0.035 * sqrt(1.0 - t * t)
		var ring := PackedVector3Array()
		for i in range(12):
			var a := TAU * float(i) / 12.0
			ring.append(c + Vector3(cos(a) * r, sin(a) * r * 0.8, t * 0.04 * (1.0 if c.z > 0 else -1.0) + (t * 0.03 * signf(c.x) if absf(c.x) > 1.0 else 0.0)))
		srings.append(ring)
	var g := MeshKit.new()
	g.loft(srings, Color.WHITE, false, true)
	var mi: MeshInstance3D = g.instance(nm.replace("Bulb", "Lens"))
	mi.material_override = _lens_mat(Color(col.r, col.g, col.b, 0.38), 0.6)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.node.add_child(mi)
	# a chrome reflector cup behind the bulb, like the truck's lamps (Dave)
	p.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c - Vector3(0, 0, 0.006 * (1.0 if c.z > 0 else -1.0))), 0.024, 0.010, 0.012, 14, Color(0.95, 0.95, 0.96), false)
	_bulb(p.node, nm, c, 0.010, col)


## Lamp glass as the truck's (truck_body._lens_glass): clear or tinted, glossy,
## with the moulded prism cells in it.
func _lens_mat(tint: Color, cells: float) -> StandardMaterial3D:
	var TB = load("res://scripts/truck_body.gd")
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic_specular = 1.0
	m.normal_enabled = true
	m.normal_texture = TB._flute_tex()
	m.normal_scale = 0.5
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.0, 1.0, 1.0) * (1.0 / 0.015) * cells
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _bulb(parent: Node3D, nm: String, at: Vector3, r: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.position = at
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.3
	m.roughness = 0.1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)



# ------------------------------------------------------------------------------
#  Cockpit (reference/supercub 10, 11, 12): tandem seats, the curved black
#  panel with two rows of round gauges and the compass, the radio under it,
#  the switch row (master, mags key, starter, light toggles, breakers), the
#  primer, carb heat, cabin heat and park brake knobs; the throttle and
#  mixture on the left wall, the flap handle, the fuel valve low on the left
#  wall, the trim crank overhead; both sticks, both sets of rudder pedals with
#  heel brakes; the fabric side panels and the tube frame inside.
#  Every control is its own node (meta "control") so it can move later.
# ------------------------------------------------------------------------------
const PANEL_Z := -0.70
const LEATHER := Color(0.06, 0.06, 0.06)       # black seats (ref 04, the bush Cub)
const LINING := Color(0.22, 0.22, 0.22)        # dark grey side panels and door insides (ref 04)
const TUBE := Color(0.62, 0.62, 0.60)          # the frame tubes, light grey (ref 04)


func _ctl(p: Part, nm: String, at: Vector3) -> Part:
	var c := _part(nm, p.node)
	c.node.position = at
	c.node.set_meta("control", nm)
	return c


func _gauge(k: Part, c: Vector3, r: float, kind: int) -> void:
	# a round instrument: the bezel, the black face, ticks, a needle, the glass
	var fb := Basis(Vector3.RIGHT, PI * 0.5)        # cylinder axis along +Z (toward the pilot)
	k.metal.cylinder(Transform3D(fb, c + Vector3(0, 0, -0.004)), r + 0.006, r + 0.006, 0.012, 24, Color(0.12, 0.12, 0.12), true)
	k.dark.cylinder(Transform3D(fb, c + Vector3(0, 0, 0.0)), r, r, 0.009, 24, Color(0.03, 0.03, 0.03), true)
	var n := 12 if kind != 2 else 8
	for i in range(n):
		var a := PI * 0.5 - TAU * float(i) / float(n)
		var d := Vector3(cos(a), sin(a), 0)
		var big := i % 3 == 0
		k.dark.box(Transform3D(Basis(Vector3.BACK, a - PI * 0.5), c + d * (r * (0.80 if big else 0.84)) + Vector3(0, 0, 0.0095)), Vector3(0.0018, r * (0.22 if big else 0.12), 0.001), Color(0.92, 0.92, 0.88))
	# coloured arcs on the airspeed and tach (green band)
	if kind == 0 or kind == 1:
		for i2 in range(6):
			var a2 := 0.2 - 0.32 * float(i2)
			k.dark.box(Transform3D(Basis(Vector3.BACK, a2 - PI * 0.5), c + Vector3(cos(a2), sin(a2), 0) * (r * 0.93) + Vector3(0, 0, 0.0095)), Vector3(0.004, r * 0.08, 0.001), Color(0.1, 0.7, 0.2))
	var na := 0.9 - float(kind) * 0.7
	k.dark.box(Transform3D(Basis(Vector3.BACK, na - PI * 0.5), c + Vector3(cos(na), sin(na), 0) * (r * 0.35) + Vector3(0, 0, 0.011)), Vector3(0.003, r * 0.75, 0.0012), Color(0.95, 0.95, 0.92))
	k.dark.cylinder(Transform3D(fb, c + Vector3(0, 0, 0.010)), 0.005, 0.005, 0.004, 8, Color(0.1, 0.1, 0.1), true)
	k.glass.quad(c + Vector3(-r, -r, 0.016), c + Vector3(r, -r, 0.016), c + Vector3(r, r, 0.016), c + Vector3(-r, r, 0.016), Color.WHITE, Vector3(0, 0, 1))


func _knob(k: Part, at: Vector3, r: float, col: Color, shaft: float = 0.02) -> void:
	var fb := Basis(Vector3.RIGHT, PI * 0.5)
	k.metal.cylinder(Transform3D(fb, at), 0.004, 0.004, shaft, 8, Color(0.6, 0.6, 0.6), true)
	k.dark.cylinder(Transform3D(fb, at + Vector3(0, 0, shaft)), r, r * 0.9, r * 1.2, 14, col, true)


func _toggle(k: Part, at: Vector3, up: bool) -> void:
	k.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at), 0.006, 0.006, 0.006, 10, Color(0.6, 0.6, 0.6), true)
	var tilt := -0.35 if up else 0.35
	k.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + tilt), at + Vector3(0, 0, 0.006)), 0.0025, 0.002, 0.022, 8, Color(0.85, 0.85, 0.85), true)


func _cabin() -> void:
	var cab := _part("Cockpit")
	# --- the shell inside: floorboards, fabric side panels, the headliner, the frame
	# the floorboards: molded to the belly - they follow the fuselage up at the
	# back and narrow where it narrows (no flat board poking through)
	var fl_prev: Array = []
	var zf := -0.86
	while zf <= 1.16:
		var sec := _sec_at(zf)
		var fy: float = float(sec[1]) + 0.045
		var fx := _skin_x(zf, fy) - 0.012
		var row := [Vector3(-fx, fy, zf), Vector3(fx, fy, zf)]
		if not fl_prev.is_empty():
			cab.dark.quad(fl_prev[0], fl_prev[1], row[1], row[0], Color(0.20, 0.15, 0.10), Vector3(0, 1, 0))
		fl_prev = row
		zf += 0.1
	for s: float in [-1.0, 1.0]:
		var x := s * 0.355
		var spans := [[-0.86, 1.15]] if s < 0.0 else [[-0.86, POST_F[0].x - 0.004], [DOOR_REAR_Z + 0.01, 1.15]]     # the door opening on the right (up to its front post: a slot there showed outside)
		for sp in spans:
			var zl: float = sp[0]
			while zl < float(sp[1]) - 0.001:
				var zn := minf(zl + 0.1, float(sp[1]))
				var ya: float = float(_sec_at(zl)[1]) + 0.05
				var yb2: float = float(_sec_at(zn)[1]) + 0.05
				var top := SILL if zl > -0.60 else 0.240          # ahead of the front post: up to the windshield's foot (that fabric was see-through from inside)
				var top2 := SILL if zn > -0.60 else 0.240
				var mida := (ya + top) * 0.5
				var midb := (yb2 + top2) * 0.5
				var la := Vector3(s * (_skin_x(zl, ya) - 0.012), ya, zl)
				var lb := Vector3(s * (_skin_x(zn, yb2) - 0.012), yb2, zn)
				var ma := Vector3(s * (_skin_x(zl, mida) - 0.012), mida, zl)
				var mb := Vector3(s * (_skin_x(zn, midb) - 0.012), midb, zn)
				var ta := Vector3(s * (_skin_x(zl, top) - 0.012), top, zl)
				var tb := Vector3(s * (_skin_x(zn, top2) - 0.012), top2, zn)
				cab.dark.quad(la, lb, mb, ma, LINING, Vector3(-s, 0, 0))
				cab.dark.quad(ma, mb, tb, ta, LINING, Vector3(-s, 0, 0))
				zl = zn
		# the inside of the door panel itself (lower door) - lining on its back

		# the kick panels ahead of the doors, firewall to front post, floor to the
		# windshield's foot, solid both ways (Dave: "needs to be closed up")
		var kz := -0.86
		while kz < POST_F[0].x - 0.005:
			var kn := minf(kz + 0.05, POST_F[0].x - 0.004)
			for ky in range(6):
				var y0 := lerpf(float(_sec_at(kz)[1]) + 0.04, 0.25, float(ky) / 6.0)
				var y1 := lerpf(float(_sec_at(kz)[1]) + 0.04, 0.25, float(ky + 1) / 6.0)
				var c0 := Vector3(s * (_skin_x(kz, y0) - 0.006), y0, kz)
				var c1 := Vector3(s * (_skin_x(kn, y0) - 0.006), y0, kn)
				var c2 := Vector3(s * (_skin_x(kn, y1) - 0.006), y1, kn)
				var c3 := Vector3(s * (_skin_x(kz, y1) - 0.006), y1, kz)
				cab.dark.quad(c0, c1, c2, c3, LINING, Vector3(-s, 0, 0))
				cab.dark.quad(c0, c1, c2, c3, LINING, Vector3(s, 0, 0))
			kz = kn
		# the frame tubes: the longerons, the door posts, the diagonals
		if s < 0.0:
			_tube(cab.dark, [Vector3(x, SILL - 0.01, -0.62), Vector3(s * (_skin_x(1.10, SILL) - 0.015), SILL - 0.01, 1.10)], 0.007, TUBE)
		else:                                # the door side: the longeron only behind the opening (ref 04: the opening's clear)
			_tube(cab.dark, [Vector3(x, SILL - 0.01, DOOR_REAR_Z + 0.01), Vector3(s * (_skin_x(1.10, SILL) - 0.015), SILL - 0.01, 1.10)], 0.007, TUBE)
		_tube(cab.dark, [Vector3(s * 0.33, 0.60, -0.30), Vector3(s * (_skin_x(1.10, 0.58) - 0.015), 0.58, 1.10)], 0.007, TUBE)   # (from behind the posts: it poked out at the windshield's top corners)
		# the posts only where a window frame covers them (Dave: no rods across the glass)
		for zp: float in WIN_Z:
			if s > 0.0 and zp < 0.6:
				continue                     # the door opening: clear
			_tube(cab.dark, [Vector3(x - s * 0.004, SILL, zp), Vector3(x - s * 0.004, 0.60, zp)], 0.007, TUBE)
		if s < 0.0:
			_tube(cab.dark, [Vector3(s * (_skin_x(-0.62, -0.50) - 0.015), -0.50, -0.62), Vector3(x, SILL, -0.20)], 0.007, TUBE)
	# the cross tubes overhead (the wing carry-through) and the headliner sling
	for zc: float in [-0.30, 0.63]:                  # (the front one behind the posts: it poked out through the windshield's corners)
		_tube(cab.dark, [Vector3(-0.33, 0.62, zc), Vector3(0.33, 0.62, zc)], 0.008, TUBE)
	# the firewall, insulated, cut to the fuselage's section below the windshield
	var fsec := _sec_at(-0.86)
	var fring := _section(float(fsec[0]) - 0.012, float(fsec[1]) + 0.012, float(fsec[2]) - 0.012, fsec[3], -0.86, 32)
	var fpts: Array = []
	for fp in fring:
		fpts.append(Vector3(fp.x, minf(fp.y, 0.20), fp.z))
	var fc := Vector3(0, -0.2, -0.86)
	for fi in range(fpts.size()):
		cab.dark.tri(fc, fpts[fi], fpts[(fi + 1) % fpts.size()], Color(0.08, 0.07, 0.06), Vector3(0, 0, 1))
	_done(cab)

	# --- the panel: a black panel with a curved top (ref 10), under the windshield
	var pn := _part("Panel", cab.node)
	var prow := PackedVector3Array()
	var top := PackedVector3Array()
	for i in range(13):
		var u := lerpf(-1.0, 1.0, float(i) / 12.0)
		prow.append(Vector3(u * (_skin_x(PANEL_Z, -0.09) - 0.008), -0.09, PANEL_Z - 0.020))      # down past the knobs (they hung in the air)      # wall to wall; a hair forward of the gauges' faces (they sit in it)
		top.append(Vector3(u * (_skin_x(PANEL_Z, 0.27) - 0.008), 0.27 + 0.09 * (1.0 - u * u), PANEL_Z - 0.020))
	for i in range(12):
		pn.dark.quad(prow[i], prow[i + 1], top[i + 1], top[i], Color(0.035, 0.035, 0.035), Vector3(0, 0, 1))
	_tube(pn.metal, Array(top), 0.004, Color(0.25, 0.25, 0.25))
	_done(pn)                                   # (it was never built: the panel's face was a hole - Dave: "still no dash")
	# the dash (Dave): the padded glareshield from the panel's top forward to
	# the windshield's foot, across the whole cabin - from the seat you look
	# over it and through the glass, not down into the nose
	var dash := _part("Dash", pn.node)
	var dcol := Color(0.10, 0.095, 0.09)        # black vinyl (the fabric grain comes from the interior texture)
	var drows: Array = []
	for k in range(7):
		var f := float(k) / 6.0
		var row := PackedVector3Array()
		for i in range(13):
			var u := lerpf(-1.0, 1.0, float(i) / 12.0)
			var x0 := u * (_skin_x(PANEL_Z, 0.27) - 0.008)
			var y0 := 0.27 + 0.09 * (1.0 - u * u) + 0.012
			var zw := _windshield_z(x0, y0 - 0.02)
			row.append(Vector3(x0, lerpf(y0 - 0.012, y0 - 0.025, f), lerpf(PANEL_Z + 0.002, zw + 0.012, f)))   # starts right on the panel's top edge (a slot showed the white cowl through it)
		drows.append(row)
	for k in range(drows.size() - 1):
		var ra: PackedVector3Array = drows[k]
		var rb: PackedVector3Array = drows[k + 1]
		for i in range(12):
			dash.dark.quad(ra[i], ra[i + 1], rb[i + 1], rb[i], dcol, Vector3(0, 1, 0))
			var dn := Vector3(0, -0.004, 0)
			dash.dark.quad(ra[i] + dn, ra[i + 1] + dn, rb[i + 1] + dn, rb[i] + dn, dcol, Vector3(0, -1, 0))   # its underside, a hair below (no flicker)
	var d0: PackedVector3Array = drows[0]
	_tube(dash.dark, Array(d0), 0.012, Color(0.06, 0.055, 0.05))              # the padded roll along its back edge
	_done(dash)
	# top row: airspeed, altimeter, tach; bottom row: turn coordinator, VSI,
	# oil temp/pressure, ammeter (ref 10: two rows)
	var gz := PANEL_Z + 0.002
	var big := 0.040
	# working instruments (real_gauges.gd: the game's painted dial faces, cased,
	# needles that swing to their readings): the Cub's panel (ref 10) - top
	# row airspeed, altimeter, tach; bottom row VSI, clock, oil pressure, oil
	# temperature, ammeter
	var RG = load("res://scripts/real_gauges.gd")
	var gg: Node3D = RG.new()
	gg.name = "Instruments"
	gg.position = Vector3(0, 0, gz + 0.001)
	pn.node.add_child(gg)
	gg.add("airspeed", Vector3(-0.165, 0.252, 0), 0.043, func() -> float: return ias_kt())
	gg.add("altimeter", Vector3(0.0, 0.262, 0), 0.043, func() -> float: return alt_ft())
	gg.add("tach", Vector3(0.165, 0.252, 0), 0.043, func() -> float: return _prop_rpm)
	gg.add("vsi", Vector3(-0.236, 0.150, 0), 0.030, func() -> float: return vsi_fpm())
	gg.add("clock", Vector3(-0.118, 0.150, 0), 0.030, func() -> float: return float(Time.get_ticks_msec()) / 3600000.0 + 9.0)
	gg.add("oilp", Vector3(0.0, 0.150, 0), 0.030, func() -> float: return oil_psi())
	gg.add("oilt", Vector3(0.118, 0.150, 0), 0.030, func() -> float: return oil_temp_f())
	gg.add("amps", Vector3(0.236, 0.150, 0), 0.030, func() -> float: return 8.0 if _prop_rpm > 900.0 else -2.0)
	# the wet compass on the top centre of the glareshield
	var cp := _part("Compass", pn.node)
	cp.dark.box_at(Vector3(0, 0.40, PANEL_Z - 0.04), Vector3(0.07, 0.06, 0.06), Color(0.05, 0.05, 0.05))
	cp.glass.quad(Vector3(-0.025, 0.38, PANEL_Z - 0.008), Vector3(0.025, 0.38, PANEL_Z - 0.008), Vector3(0.025, 0.42, PANEL_Z - 0.008), Vector3(-0.025, 0.42, PANEL_Z - 0.008), Color.WHITE, Vector3(0, 0, 1))
	cp.dark.box_at(Vector3(0, 0.40, PANEL_Z - 0.012), Vector3(0.04, 0.025, 0.004), Color(0.85, 0.82, 0.70))
	_done(cp)
	# the switch row along the bottom of the panel: master (split rocker),
	# the mags key, the starter button, toggles for nav / strobe / landing /
	# avionics, and a row of push-pull breakers
	var sw := _ctl(pn, "MasterSwitch", Vector3(-0.262, 0.075, gz))
	sw.dark.box_at(Vector3(0, 0, 0.008), Vector3(0.022, 0.03, 0.012), Color(0.75, 0.06, 0.04))
	sw.dark.box_at(Vector3(0.024, 0, 0.008), Vector3(0.022, 0.03, 0.012), Color(0.75, 0.06, 0.04))
	_done(sw)
	var mg := _ctl(pn, "MagSwitch", Vector3(-0.175, 0.075, gz))
	mg.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.020, 0.020, 0.008, 18, Color(0.55, 0.55, 0.55), true)
	mg.metal.box_at(Vector3(0, 0, 0.018), Vector3(0.008, 0.022, 0.016), Color(0.75, 0.75, 0.70))   # the key in it
	for i3 in range(4):
		var a3 := 0.9 + float(i3) * 0.45
		mg.dark.box_at(Vector3(cos(a3) * 0.028, sin(a3) * 0.028, 0.002), Vector3(0.006, 0.003, 0.001), Color(0.9, 0.9, 0.9))
	_done(mg)
	var st := _ctl(pn, "Starter", Vector3(-0.112, 0.075, gz))
	st.dark.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.010, 0.010, 0.012, 14, Color(0.08, 0.08, 0.08), true)
	_done(st)
	var names := ["NavSwitch", "StrobeSwitch", "LandingSwitch", "AvionicsSwitch", "FuelPumpSwitch"]
	for i4 in range(names.size()):
		var tg := _ctl(pn, String(names[i4]), Vector3(-0.064 + float(i4) * 0.032, 0.075, gz))
		_toggle(tg, Vector3.ZERO, i4 % 2 == 0)
		_done(tg)
	for i5 in range(6):
		var cb := _ctl(pn, "Breaker%d" % i5, Vector3(0.130 + float(i5) * 0.025, 0.075, gz))
		cb.dark.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.006, 0.006, 0.010, 10, Color(0.15, 0.15, 0.15), true)
		cb.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.010)), 0.004, 0.004, 0.004, 8, Color(0.85, 0.85, 0.85), true)
		_done(cb)
	# the placards (Dave: label every switch): white engraved lettering under
	# each switch, breaker and knob, as on the real panel
	var lbls := [["MASTER", Vector2(-0.250, 0.047), 1.0], ["BAT  ALT", Vector2(-0.250, 0.100), 0.8],
		["MAGS", Vector2(-0.175, 0.047), 1.0], ["OFF R L BOTH", Vector2(-0.175, 0.110), 0.7],
		["START", Vector2(-0.112, 0.055), 1.0], ["PUSH", Vector2(-0.112, 0.095), 0.7]]
	var tnames := ["NAV", "STROBE", "LAND", "AVION", "F PUMP"]
	for i6 in range(tnames.size()):
		lbls.append([tnames[i6], Vector2(-0.064 + float(i6) * 0.032, 0.053), 0.8])
	lbls.append(["ON", Vector2(0.0, 0.103), 0.8])
	var bn := ["INST", "RADIO", "XPDR", "NAV", "STRB", "LDG"]
	for i7 in range(bn.size()):
		lbls.append([bn[i7], Vector2(0.130 + float(i7) * 0.025, 0.057), 0.65])
	lbls.append(["CIRCUIT BREAKERS", Vector2(0.192, 0.095), 0.7])
	lbls.append(["PRIMER", Vector2(-0.27, -0.040), 0.85])
	lbls.append(["PARK BRK", Vector2(-0.18, -0.040), 0.85])
	lbls.append(["CARB HEAT", Vector2(-0.09, -0.040), 0.85])
	lbls.append(["CABIN HEAT", Vector2(0.22, -0.040), 0.85])
	for lb in lbls:
		var l3 := Label3D.new()
		l3.text = String(lb[0])
		l3.font_size = 32
		l3.outline_size = 0
		l3.pixel_size = 0.00021 * float(lb[2])
		l3.modulate = Color(0.92, 0.92, 0.88)
		l3.double_sided = false
		l3.shaded = false
		l3.position = Vector3((lb[1] as Vector2).x, (lb[1] as Vector2).y, gz + 0.0025)
		pn.node.add_child(l3)
	# primer, carb heat, cabin heat, parking brake: push-pull knobs under the panel
	var knobs := [["Primer", Vector3(-0.27, -0.015, gz), Color(0.75, 0.75, 0.72)], ["CarbHeat", Vector3(-0.09, -0.015, gz), Color(0.70, 0.08, 0.05)],
		["CabinHeat", Vector3(0.22, -0.015, gz), Color(0.08, 0.08, 0.08)], ["ParkBrake", Vector3(-0.18, -0.015, gz), Color(0.08, 0.08, 0.08)]]
	for kd in knobs:
		var kb := _ctl(pn, String(kd[0]), kd[1])
		_knob(kb, Vector3.ZERO, 0.013, kd[2], 0.025 if String(kd[0]) != "Primer" else 0.04)
		_done(kb)
	# the radio and transponder under the panel's centre (ref 11)
	var rd := _part("Radio", pn.node)
	for rr in [[-0.07, 0.6], [-0.125, 0.6]]:
		var ry: float = rr[0]
		rd.dark.box_at(Vector3(0.05, ry, PANEL_Z + 0.02), Vector3(0.16, 0.048, 0.18), Color(0.05, 0.05, 0.05))
		rd.dark.box_at(Vector3(0.03, ry + 0.004, PANEL_Z + 0.111), Vector3(0.07, 0.018, 0.002), Color(0.05, 0.25, 0.08))   # the display
		for kx: float in [-0.015, 0.105, 0.125]:
			rd.dark.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(kx, ry - 0.008, PANEL_Z + 0.11)), 0.007, 0.007, 0.012, 12, Color(0.12, 0.12, 0.12), true)
	_done(rd)
	# the intercom box and headphone jacks on the left, a placard
	var ic := _part("Intercom", pn.node)
	ic.dark.box_at(Vector3(-0.33, 0.18, -0.60), Vector3(0.03, 0.06, 0.08), Color(0.06, 0.06, 0.06))
	ic.dark.box_at(Vector3(-0.31, 0.20, PANEL_Z + 0.004), Vector3(0.04, 0.025, 0.001), Color(0.9, 0.9, 0.86))
	_done(ic)

	# --- left wall: throttle and mixture (two black levers in a quadrant, ref 11),
	# the flap handle on the floor-side, the fuel valve low with its red handle
	var q := _part("Quadrant", cab.node)
	var qw := _skin_x(-0.30, -0.02) - 0.012              # the lining: the quadrant is bolted to it (it floated - Dave)
	q.dark.box_at(Vector3(-(qw - 0.015), -0.02, -0.30), Vector3(0.03, 0.10, 0.22), Color(0.06, 0.06, 0.06))
	q.metal.box_at(Vector3(-(qw - 0.031), -0.02, -0.30), Vector3(0.004, 0.012, 0.18), Color(0.4, 0.4, 0.4))   # the slot
	_done(q)
	for lv in [["Throttle", -0.33, Color(0.06, 0.06, 0.06)], ["Mixture", -0.26, Color(0.75, 0.05, 0.04)]]:      # back by the seated left hand
		var l := _ctl(q, String(lv[0]), Vector3(-(qw - 0.032), -0.02, float(lv[1])))
		l.node.set_meta("pivot", Vector3(-(qw - 0.032), -0.02, float(lv[1])))
		_tube(l.metal, [Vector3.ZERO, Vector3(0.05, 0.10, 0.0)], 0.005, Color(0.55, 0.55, 0.55))
		l.dark.cylinder(Transform3D(Basis(Vector3.BACK, -0.45), Vector3(0.05, 0.10, 0)), 0.014, 0.012, 0.035, 12, lv[2], true)
		_done(l)
	var fl := _ctl(cab, "FlapHandle", Vector3(-0.30, -0.30, 0.18))
	fl.node.set_meta("pivot", Vector3(-0.30, -0.30, 0.18))
	_tube(fl.metal, [Vector3.ZERO, Vector3(0.0, 0.18, -0.20)], 0.009, Color(0.62, 0.62, 0.62))
	fl.dark.cylinder(Transform3D(Basis(Vector3.RIGHT, -0.85), Vector3(0.0, 0.18, -0.20)), 0.013, 0.013, 0.07, 12, Color(0.05, 0.05, 0.05), true)
	fl.metal.box_at(Vector3(0.0, 0.0, 0.0), Vector3(0.02, 0.05, 0.10), Color(0.4, 0.4, 0.4))   # the ratchet
	_done(fl)
	var fv := _ctl(cab, "FuelValve", Vector3(-(_skin_x(-0.42, -0.32) - 0.014), -0.32, -0.42))
	fv.dark.box_at(Vector3(0.002, 0, 0), Vector3(0.004, 0.12, 0.14), Color(0.85, 0.84, 0.80))       # the placard (FUEL L / R / OFF)
	fv.metal.cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(0.004, 0, 0)), 0.02, 0.02, 0.012, 14, Color(0.5, 0.5, 0.5), true)
	fv.dark.box_at(Vector3(0.024, 0, 0), Vector3(0.012, 0.075, 0.016), Color(0.80, 0.08, 0.05))       # the red handle
	_done(fv)
	# the trim crank overhead on the left, and its cable
	var tr := _ctl(cab, "TrimCrank", Vector3(-0.22, 0.58, -0.15))
	tr.metal.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0)), 0.035, 0.035, 0.012, 16, Color(0.45, 0.45, 0.45), true)
	_tube(tr.metal, [Vector3(0.02, -0.02, 0), Vector3(0.02, -0.06, 0.0)], 0.005, Color(0.6, 0.6, 0.6))
	tr.dark.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.02, -0.09, 0.0)), 0.008, 0.008, 0.03, 10, Color(0.05, 0.05, 0.05), true)
	_done(tr)
	# fuel sight gauges: a glass tube with a red float at each wing root, top front corners
	for s2: float in [-1.0, 1.0]:
		var sg := _ctl(cab, "FuelGauge" + ("L" if s2 < 0.0 else "R"), Vector3(s2 * 0.33, 0.50, -0.38))
		sg.glass.quad(Vector3(-0.006, -0.06, 0.006), Vector3(0.006, -0.06, 0.006), Vector3(0.006, 0.06, 0.006), Vector3(-0.006, 0.06, 0.006), Color.WHITE, Vector3(0, 0, 1))
		sg.dark.box_at(Vector3(0, 0.0, 0.0), Vector3(0.012, 0.012, 0.008), Color(0.8, 0.1, 0.05))
		sg.metal.box_at(Vector3(0, -0.065, 0), Vector3(0.02, 0.01, 0.02), Color(0.5, 0.5, 0.5))
		sg.metal.box_at(Vector3(0, 0.065, 0), Vector3(0.02, 0.01, 0.02), Color(0.5, 0.5, 0.5))
		_done(sg)

	# --- sticks, pedals, seats: front and rear
	for i6 in range(2):
		var sz: float = [-0.10, 0.62][i6]
		var tag := "Front" if i6 == 0 else "Rear"
		# the stick between the knees, its grip where the seated hand is (it was out of reach under the panel)
		var sk := _ctl(cab, "Stick" + tag, Vector3(0, -0.58, sz - 0.20))
		sk.node.set_meta("pivot", Vector3(0, -0.58, sz - 0.20))
		_tube(sk.dark, [Vector3.ZERO, Vector3(0, 0.50, 0.02)], 0.012, TUBE)
		sk.dark.cylinder(Transform3D(Basis(Vector3.RIGHT, 0.04), Vector3(0, 0.55, 0.022)), 0.018, 0.016, 0.10, 12, Color(0.03, 0.03, 0.03), true)
		sk.dark.box_at(Vector3(0, -0.01, 0), Vector3(0.06, 0.03, 0.06), Color(0.05, 0.05, 0.05))   # the boot
		if i6 == 0:
			sk.dark.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.59, 0.012)), 0.005, 0.005, 0.01, 8, Color(0.8, 0.1, 0.05), true)   # PTT button
		_done(sk)
		for s3: float in [-1.0, 1.0]:
			var pd := _ctl(cab, "Pedal" + tag + ("L" if s3 < 0.0 else "R"), Vector3(s3 * 0.12, -0.56, sz - 0.62 - (0.18 if i6 == 0 else 0.0)))
			pd.node.set_meta("pivot", Vector3(s3 * 0.12, -0.56, sz - 0.62))
			_tube(pd.metal, [Vector3.ZERO, Vector3(0, 0.14, -0.03)], 0.008, Color(0.45, 0.45, 0.45))
			pd.metal.box_at(Vector3(0, 0.15, -0.035), Vector3(0.08, 0.045, 0.012), Color(0.55, 0.55, 0.55))
			pd.dark.box_at(Vector3(0, 0.04, 0.06), Vector3(0.06, 0.012, 0.05), Color(0.12, 0.12, 0.12))   # the heel brake
			_done(pd)
		var seat := _part("Seat" + tag, cab.node)
		var base_y := -0.36 if i6 == 0 else -0.42
		seat.dark.rbox(Transform3D(Basis.IDENTITY, Vector3(0, base_y, sz)), Vector3(0.44, 0.08, 0.40), LEATHER, 0.03)
		seat.dark.rbox(Transform3D(Basis(Vector3.RIGHT, 0.18), Vector3(0, base_y + 0.30, sz + 0.24)), Vector3(0.44, 0.56, 0.07), LEATHER, 0.03)
		for sx: float in [-0.20, 0.20]:
			for lz: float in [sz - 0.15, sz + 0.18]:
				_tube(seat.dark, [Vector3(sx, float(_sec_at(lz)[1]) + 0.05, lz), Vector3(sx, base_y - 0.04, lz)], 0.010, TUBE)
		# lap belts lying on the seat, buckles
		for sx2: float in [-1.0, 1.0]:
			seat.dark.box_at(Vector3(sx2 * 0.12, base_y + 0.045, sz + 0.05), Vector3(0.18, 0.004, 0.045), Color(0.12, 0.12, 0.10))
		seat.metal.box_at(Vector3(0, base_y + 0.05, sz + 0.05), Vector3(0.05, 0.006, 0.05), Color(0.75, 0.75, 0.75))
		if i6 == 0:
			for sx3: float in [-0.12, 0.12]:
				seat.dark.box(Transform3D(Basis(Vector3.RIGHT, 0.18), Vector3(sx3, base_y + 0.36, sz + 0.20)), Vector3(0.045, 0.40, 0.004), Color(0.12, 0.12, 0.10))   # shoulder harness
		_done(seat)
	_texture_interior(cab.node)
	# the door handle inside (right) and the window latch
	var dh := _part("DoorLatch", cab.node)
	dh.metal.box_at(Vector3(0.34, 0.12, 0.40), Vector3(0.02, 0.02, 0.10), Color(0.7, 0.7, 0.7))
	_done(dh)


## A tie-down ring (DESIGN_NOTES 225): a threaded eye bolt into the fitting
## under the skin at `at` (where its top meets the skin), the ring hanging
## below - a real ring a rope goes through, not a disc.
func _tie_ring(k: RefCounted, at: Vector3) -> void:
	var col := Color(0.62, 0.62, 0.64)
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), at + Vector3(0, 0.002, 0)), 0.014, 0.012, 0.012, 8, col, true)    # the boss / nut on the skin
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), at - Vector3(0, 0.01, 0)), 0.006, 0.006, 0.018, 6, col, true)     # the shank
	var c := at - Vector3(0, 0.028 + 0.022, 0)
	var TP = load("res://scripts/tow_points.gd")
	for i in range(14):
		var a0 := TAU * float(i) / 14.0
		var a1 := TAU * float(i + 1) / 14.0
		TP._rod(k, c + Vector3(0, cos(a0), sin(a0)) * 0.022, c + Vector3(0, cos(a1), sin(a1)) * 0.022, 0.005, col)


## Where a winch hook, tow strap or tie-down rope can go (DESIGN_NOTES 225):
## the ring under each wing at the strut fitting, the ring under the tail.
func winch_points() -> Array:
	if _root == null or not _root.is_inside_tree():
		return []
	var xf: Transform3D = _root.global_transform
	return [
		["left wing tie-down", xf * Vector3(-STRUT_X, _wbot(STRUT_X, 0.30) - 0.05, 0.30)],
		["right wing tie-down", xf * Vector3(STRUT_X, _wbot(STRUT_X, 0.30) - 0.05, 0.30)],
		["tail tie-down", xf * Vector3(0, float(_sec_at(4.40)[1]) - 0.05, 4.40)],
	]


func _details() -> void:
	var p := _part("Details")
	# the whip antenna behind the wing, the tie-downs, a hand-hold on the tail
	_tube(p.dark, [Vector3(0, 0.62, 1.40), Vector3(0, 1.10, 1.75)], 0.004, Color(0.08, 0.08, 0.08))
	for s: float in [-1.0, 1.0]:
		_tie_ring(p.metal, Vector3(s * STRUT_X, _wbot(STRUT_X, 0.30), 0.30))
	for s2: float in [-1.0, 1.0]:
		_tube(p.metal, [Vector3(s2 * 0.20, 0.30, 4.05), Vector3(s2 * 0.20, 0.30, 4.25)], 0.012, Color(0.7, 0.7, 0.7))
	_done(p)



# ------------------------------------------------------------------------------
#  Everything opens (Dave): each moving part swings about its hinge, eased
# ------------------------------------------------------------------------------
var _anims: Array = []        # [node, hinge, axis, open_angle, cur, target, group]
var _caps: Array = []
var _cap_t := 0.0
var _cap_goal := 0.0
var _lights_on := false
var _ctl_sweep := false
var _ctl_t := 0.0


func _anim_reg(n: Node3D, hinge: Vector3, axis: Vector3, open_angle: float, group: String = "") -> void:
	_anims.append([n, hinge, axis.normalized(), open_angle, 0.0, 0.0, group if group != "" else String(n.name)])


func _set_group(names: Array, open: bool) -> void:
	for a in _anims:
		if names.has(String(a[6])):
			if (float(a[5]) > 0.5) != open:
				_clunk(String(a[6]), open)
			a[5] = 1.0 if open else 0.0


func _is_open(nm: String) -> bool:
	for a in _anims:
		if String(a[6]) == nm:
			return float(a[5]) > 0.5
	return false


## Air in the tundra tyres (both mains). Softer: a bigger flat spot, a
## softer ride (the tyre is part of the spring), more grip and float on soft
## ground, more drag rolling. Harder: the opposite.
func tyre_pressure(delta_psi: float) -> String:
	tyre_psi = clampf(tyre_psi + delta_psi, 3.0, 35.0)
	if body != null:
		var soft := 10.0 / tyre_psi
		body.spring_mul = 1.6 / (1.0 + 0.25 * (soft - 1.0))
		body.mu = clampf(0.80 + 0.05 * soft, 0.7, 1.0)
		body._recompute_springs()
	_animate()
	return "Tyres %.0f psi%s" % [tyre_psi, "  (soft: big flat spot, floats on mud)" if tyre_psi < 8.0 else ("  (hard: small footprint, bouncy)" if tyre_psi > 18.0 else "")]


func test_labels() -> Dictionary:
	return {"door_l": "Left window", "door_r": "Door: top half", "door_low": "Door: bottom half", "hood": "Cowl (engine)", "gate": "Baggage door",
		"fuel": "Fuel caps", "lights": "Lights", "blink": "Control sweep"}


func door_toggle(i: int) -> String:
	if i == 0 or i == -1:
		var o := not _is_open("WindowL")
		_set_group(["WindowL"], o)
		if i == 0:
			return "Left window %s." % ("open" if o else "shut")
	if i == 2:
		var o3 := not _is_open("DoorLower")
		_set_group(["DoorLower"], o3)
		return "Lower door %s." % ("folded down" if o3 else "shut")
	var o2 := not _is_open("DoorUpper")
	_set_group(["DoorUpper"] if i == 1 else ["DoorUpper", "DoorLower"], o2)
	return "Top door %s." % ("up under the wing (photo 03)" if o2 else "shut")


# ------------------------------------------------------------------------------
#  Sounds (Dave: proper sounds): the flat-four through its short stacks and
#  the prop's beat (engine_sound.gd "lyc4"), the starter grinding and the
#  coughs as it catches (the plane's own starter / start recordings), and a
#  clunk or a latch for every door, window, hatch and cowl panel
# ------------------------------------------------------------------------------
const EngineSound = preload("res://scripts/engine_sound.gd")
var _es: Node3D
var _clunks: Array = []


func _sounds() -> void:
	if _es != null and is_instance_valid(_es):
		_es.queue_free()
	_es = EngineSound.new()
	_es.name = "EngineSound"
	_es.kind = "lyc4"
	_es.position = Vector3(0, -0.15, -1.55)
	_es.state = func() -> Dictionary:
		var blades: float = float(PROPS[prop_kind]["blades"])
		return {"rpm": _prop_rpm, "running": _prop_goal > 0.0, "load": clampf((_prop_rpm - 700.0) / 1600.0, 0.0, 1.0), "blades": blades}
	_root.add_child(_es)
	_clunks.clear()
	for i in range(4):
		var c := AudioStreamPlayer3D.new()
		c.stream = EngineSound._dsl("clunk_%d.wav" % i, false, "res://assets/sounds/rattle/")
		c.unit_size = 3.0
		c.max_distance = 60.0
		_root.add_child(c)
		_clunks.append(c)


## A door / window / panel shutting (a solid clunk) or opening (lighter, higher).
func _clunk(part: String, open: bool) -> void:
	if _clunks.is_empty():
		return
	var c: AudioStreamPlayer3D = _clunks[randi() % _clunks.size()]
	if c.stream == null:
		return
	var n := _root.find_child(part, true, false) as Node3D
	c.position = n.position if n != null else Vector3.ZERO
	for a in _anims:
		if String(a[6]) == part:
			c.position = a[1]           # at the hinge
			break
	var light := part.begins_with("Window") or part.begins_with("Fuel") or part.begins_with("Baggage")
	c.pitch_scale = (1.25 if open else 0.95) * (1.25 if light else 1.0) * randf_range(0.95, 1.05)
	c.volume_db = linear_to_db(0.5 if open else 0.8)
	c.play()


## The cowl for maintenance (Dave: bigger doors / a way to see the engine):
## shut -> both side panels up -> the whole cowl off (panels and nose bowl
## lifted away on the bench, the engine bare from every side) -> shut.
var cowl_off := false


func hood_toggle() -> String:
	if cowl_off:
		cowl_off = false
		_cowl_show(true)
		_set_group(["CowlPanelL", "CowlPanelR"], false)
		return "Cowl back on and shut."
	if _is_open("CowlPanelL"):
		cowl_off = true
		_cowl_show(false)
		return "Cowl off: panels and nose bowl removed - the engine bare for maintenance."
	_set_group(["CowlPanelL", "CowlPanelR"], true)
	return "Cowl panels up: the engine. (Again: take the whole cowl off.)"


func _cowl_show(v: bool) -> void:
	for nm in ["CowlPanelL", "CowlPanelR", "NoseBowl", "CowlHinge"]:
		var n := _root.find_child(nm, true, false) as Node3D
		if n != null:
			n.visible = v


func tailgate_toggle() -> String:
	var o := not _is_open("BaggageDoor")
	_set_group(["BaggageDoor"], o)
	return "Baggage door %s." % ("open" if o else "shut")


func fuel_door_toggle() -> String:
	_cap_goal = 0.0 if _cap_goal > 0.5 else 1.0
	return "Fuel caps %s." % ("off, hanging on their chains" if _cap_goal > 0.5 else "on")


## Working the cockpit (Dave: left click hits the buttons and levers): every
## switch, lever and knob does its job and moves.
var _sw := {}
func control_click(nm: String) -> String:
	var n := find_child(nm, true, false) as Node3D
	var on: bool = not bool(_sw.get(nm, false))
	_sw[nm] = on
	var msg := nm
	match nm:
		"NavSwitch", "StrobeSwitch", "LandingSwitch", "AvionicsSwitch", "FuelPumpSwitch":
			if n != null:
				n.rotation.z = PI if on else 0.0
			if nm == "NavSwitch": _nav = on
			if nm == "StrobeSwitch": _strobe = on
			if nm == "LandingSwitch": _land = on
			_light_apply()
			msg = "%s %s" % [nm.replace("Switch", ""), "on" if on else "off"]
		"MasterSwitch":
			if n != null:
				n.rotation.x = -0.25 if on else 0.0
			msg = "Master " + ("on" if on else "off")
		"MagSwitch":
			var pos := int(_sw.get("mag_pos", 0) + 1) % 4
			_sw["mag_pos"] = pos
			_sw[nm] = pos > 0
			if n != null:
				n.rotation.z = -0.45 * float(pos)
			msg = "Mags: " + ["OFF", "R", "L", "BOTH"][pos]
			if pos == 0 and _prop_goal > 0.0:
				_prop_goal = 0.0
				msg += " - engine off"
		"Starter":
			if int(_sw.get("mag_pos", 0)) == 0 or not bool(_sw.get("MasterSwitch", false)):
				msg = "Starter: nothing - master on and the mags to BOTH first"
			elif _prop_goal <= 0.0:
				_prop_goal = 900.0 if not bool(_sw.get("Throttle", false)) else 2300.0
				msg = "Starter: it turns over, coughs and catches."
			else:
				msg = "Already running."
			_sw[nm] = false
		"Throttle":
			if n != null:
				n.transform = Transform3D(Basis(Vector3.RIGHT, -0.6 if on else 0.0), n.get_meta("pivot"))
			if _prop_goal > 0.0:
				_prop_goal = 2300.0 if on else 900.0
			msg = "Throttle " + ("full" if on else "idle")
		"Mixture":
			if n != null:
				n.transform = Transform3D(Basis(Vector3.RIGHT, 0.6 if on else 0.0), n.get_meta("pivot"))
			if on:
				_prop_goal = 0.0
			msg = "Mixture " + ("idle cut-off - the engine dies" if on else "rich")
		"FlapHandle":
			msg = flaps_toggle()
			if n != null:
				n.transform = Transform3D(Basis(Vector3.RIGHT, -0.7 if _flaps_goal > 0.5 else 0.0), n.get_meta("pivot"))
		"FuelValve":
			var fp := int(_sw.get("fuel_pos", 0) + 1) % 3
			_sw["fuel_pos"] = fp
			if n != null:
				n.rotation.x = 0.9 * float(fp)
			msg = "Fuel: " + ["BOTH", "LEFT", "OFF"][fp]
		"Primer", "CarbHeat", "CabinHeat", "ParkBrake":
			if n != null:
				var b0: Vector3 = n.get_meta("base_pos") if n.has_meta("base_pos") else n.position
				n.set_meta("base_pos", b0)
				n.position = b0 + Vector3(0, 0, 0.035 if on else 0.0)
			msg = "%s %s" % [nm, "pulled" if on else "in"]
		"TrimCrank":
			if n != null:
				n.rotation.y += 1.6
			msg = "Trim: nose " + ("up" if on else "down")
		_:
			if nm.begins_with("Breaker") and n != null:
				n.position.z += 0.006 if on else -0.006
				msg = "%s %s" % [nm, "popped" if on else "reset"]
			elif nm.begins_with("Stick") or nm.begins_with("Pedal"):
				msg = blinker(0)
	return msg


var _nav := false
var _strobe := false
var _land := false


## The light switches (the panel's toggles): each press of the test bed's
## Lights adds one - nav, then strobes + beacon, then the landing light -
## and the next turns them all off.
var _lights_stage := 0
var _strobe_t := 0.0


func lights_toggle() -> String:
	_lights_stage = (_lights_stage + 1) % 4
	_lights_on = _lights_stage > 0
	_nav = _lights_stage >= 1
	_strobe = _lights_stage >= 2
	_land = _lights_stage >= 3
	_light_apply()
	return ["Lights off.", "Nav lights on.", "Nav + strobes + beacon on.", "Nav, strobes, beacon and landing light on."][_lights_stage]


func _light_apply() -> void:
	var nav := _nav
	for nm in ["Nav-1Bulb", "Nav1Bulb", "TailNavBulb"]:
		_bulb_glow(nm, 6.0 if nav else 0.3)
	for nm2 in ["NavLightL", "NavLightR", "NavLightTail"]:
		var o := find_child(nm2, true, false) as Light3D
		if o != null:
			o.visible = nav
	var land := _land
	_bulb_glow("LandingBulb", 8.0 if land else 0.3)
	_bulb_glow("TaxiBulb", 8.0 if land else 0.3)
	for ln in ["LandingLight", "TaxiLight"]:
		var ll := find_child(ln, true, false) as Light3D
		if ll != null:
			ll.visible = land
	var pl := find_child("PanelLight", true, false) as Light3D
	if pl != null:
		pl.visible = nav
	var ig := find_child("Instruments", true, false)
	if ig != null:
		for gm in ig.find_children("*", "MeshInstance3D", true, false):
			var mm = (gm as MeshInstance3D).material_override
			if mm is StandardMaterial3D and (mm as StandardMaterial3D).emission_enabled:
				(mm as StandardMaterial3D).emission_energy_multiplier = 1.4 if nav else 1.0
	if not _strobe:
		for nm3 in ["StrobeL", "StrobeR", "Beacon"]:
			var o3 := find_child(nm3, true, false) as Light3D
			if o3 != null:
				o3.light_energy = 0.0
		for nm4 in ["StrobeTip-1Bulb", "StrobeTip1Bulb", "BeaconBulb"]:
			_bulb_glow(nm4, 0.3)


func _bulb_glow(nm: String, e: float) -> void:
	var b := find_child(nm, true, false) as MeshInstance3D
	if b != null and b.material_override is StandardMaterial3D:
		(b.material_override as StandardMaterial3D).emission_energy_multiplier = e


## Strobes: a double flash a second off the tips; the beacon a slower red pulse.
func _lights_step(dt: float) -> void:
	if not _strobe:
		return
	_strobe_t = fposmod(_strobe_t + dt, 1.2)
	var f := 1.0 if (_strobe_t < 0.05 or (_strobe_t > 0.15 and _strobe_t < 0.20)) else 0.0
	var bc := maxf(0.0, sin(_strobe_t / 1.2 * TAU * 1.0)) 
	for nm in ["StrobeL", "StrobeR"]:
		var o := find_child(nm, true, false) as Light3D
		if o != null:
			o.light_energy = 8.0 * f
	for nm2 in ["StrobeTip-1Bulb", "StrobeTip1Bulb"]:
		_bulb_glow(nm2, 0.3 + 20.0 * f)
	var bo := find_child("Beacon", true, false) as Light3D
	if bo != null:
		bo.light_energy = 3.0 * pow(bc, 4.0)
	_bulb_glow("BeaconBulb", 0.3 + 10.0 * pow(bc, 4.0))


## "Blinker" in the test bed: sweeps the controls - stick, ailerons, elevator,
## rudder, pedals, flaps down and up.
func blinker(_d: int) -> String:
	_ctl_sweep = not _ctl_sweep
	return "Control sweep %s." % ("on" if _ctl_sweep else "off")


func _swing(n: Node3D, hinge: Vector3, axis: Vector3, ang: float) -> void:
	n.transform = Transform3D(Basis(axis, ang), hinge) * Transform3D(Basis.IDENTITY, -hinge)


func _anim_step(dt: float) -> void:
	for a in _anims:
		var cur: float = a[4]
		var tgt: float = a[5]
		if absf(cur - tgt) > 0.0001:
			cur = move_toward(cur, tgt, dt * 0.9)
			a[4] = cur
			_swing(a[0], a[1], a[2], float(a[3]) * smoothstep(0.0, 1.0, cur))
	if absf(_cap_t - _cap_goal) > 0.0001:
		_cap_t = move_toward(_cap_t, _cap_goal, dt * 0.8)
		for c in _caps:
			var n: Node3D = c[0]
			var at: Vector3 = c[1]
			var up := clampf(_cap_t * 2.0, 0.0, 1.0)          # unscrew and lift
			var hang := clampf(_cap_t * 2.0 - 1.0, 0.0, 1.0)  # then over the side on its chain
			var xf := Transform3D(Basis(Vector3.UP, up * 6.0), Vector3.ZERO)
			xf = Transform3D(Basis(Vector3.BACK, -signf(at.x) * hang * 1.4), Vector3(signf(at.x) * hang * 0.07, up * 0.03 - hang * 0.05, 0)) * xf
			n.transform = Transform3D(Basis.IDENTITY, at) * xf * Transform3D(Basis.IDENTITY, -at)
	if _ctl_sweep:
		_ctl_t += dt
		var ail := sin(_ctl_t * 1.3) * 0.35
		var ele := sin(_ctl_t * 0.9) * 0.40
		var rud := sin(_ctl_t * 0.7) * 0.45
		var flp := (0.5 - 0.5 * cos(_ctl_t * 0.35)) * 0.75
		_surf("AileronL", ail)
		_surf("AileronR", -ail)
		_surf("Elevator", ele)
		_surf("Rudder", rud)
		_surf("FlapL", flp)
		_surf("FlapR", flp)
		_stick(ail, ele, rud)


func _surf(nm: String, ang: float) -> void:
	var n := _root.get_node_or_null(nm) as Node3D
	if n == null or not n.has_meta("hinge"):
		return
	var h: Vector3 = n.get_meta("hinge")
	var ax := Vector3.RIGHT if not nm.begins_with("Rudder") else Vector3.UP
	_swing(n, h, ax, ang)


func _stick(ail: float, ele: float, rud: float) -> void:
	for nm in ["StickFront", "StickRear"]:
		var n := find_child(nm, true, false) as Node3D
		if n != null:
			n.transform = Transform3D(Basis.from_euler(Vector3(-ele * 0.4, 0, -ail * 0.5)), n.get_meta("pivot"))
	for nm2 in ["PedalFrontL", "PedalFrontR", "PedalRearL", "PedalRearR"]:
		var p := find_child(nm2, true, false) as Node3D
		if p != null:
			var base: Vector3 = p.get_meta("base_pos") if p.has_meta("base_pos") else p.position
			p.set_meta("base_pos", base)
			p.position = base + Vector3(0, 0, rud * 0.06 * (1.0 if nm2.ends_with("L") else -1.0))


# ------------------------------------------------------------------------------
#  The engine under the cowl (it shows when the cowl opens): a flat four -
#  crankcase, two finned cylinders a side (staggered), the rocker covers, the
#  intake pipes down to the sump, the carb and air box, the exhaust risers,
#  the magnetos and the oil filter on the back, the starter and alternator at
#  the front, the baffles round the cylinders, the mount tubes to the firewall
# ------------------------------------------------------------------------------
func _engine() -> void:
	var e := _part("Engine")
	var alu := Color(0.62, 0.62, 0.60)
	var cast := Color(0.28, 0.28, 0.29)
	var cy := 0.0
	# crankcase and sump
	e.metal.rbox(Transform3D(Basis.IDENTITY, Vector3(0, cy, -1.36)), Vector3(0.24, 0.24, 0.56), alu, 0.04)
	e.metal.rbox(Transform3D(Basis.IDENTITY, Vector3(0, cy - 0.20, -1.30)), Vector3(0.30, 0.16, 0.44), alu.darkened(0.1), 0.03)
	e.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -1.64)), 0.07, 0.06, 0.06, 18, alu, true)   # the nose of the case
	for s: float in [-1.0, 1.0]:
		for k in range(2):
			var cz := -1.47 + float(k) * 0.24 + (0.0 if s < 0.0 else 0.06)
			var bas := Basis(Vector3.BACK, -PI * 0.5 * s)          # cylinder along +-X
			var c0 := Vector3(s * 0.10, cy + 0.02, cz)
			e.metal.cylinder(Transform3D(bas, c0), 0.058, 0.058, 0.13, 16, cast, true)
			for f in range(7):
				e.dark.cylinder(Transform3D(bas, c0 + Vector3(s * (0.02 + float(f) * 0.016), 0, 0)), 0.074, 0.074, 0.005, 16, Color(0.20, 0.20, 0.21), true)
			var hd := c0 + Vector3(s * 0.12, 0, 0)
			e.metal.rbox(Transform3D(Basis.IDENTITY, hd + Vector3(s * 0.05, 0, 0)), Vector3(0.09, 0.14, 0.14), alu.darkened(0.15), 0.02)   # the head
			for f2 in range(5):
				e.dark.box_at(hd + Vector3(s * 0.05, 0.08 + float(f2) * 0.0, -0.06 + float(f2) * 0.03), Vector3(0.10, 0.02, 0.004), Color(0.2, 0.2, 0.2))
			e.metal.rbox(Transform3D(Basis.IDENTITY, hd + Vector3(s * 0.105, 0.0, 0)), Vector3(0.025, 0.12, 0.13), Color(0.55, 0.12, 0.08), 0.01)   # rocker cover
			_tube(e.metal, [hd + Vector3(s * 0.04, -0.07, 0.02), Vector3(s * 0.20, -0.22, cz + 0.02), Vector3(s * 0.06, -0.26, cz + 0.02)], 0.016, alu)        # intake to the sump
			_tube(e.metal, [hd + Vector3(s * 0.06, -0.07, -0.03), Vector3(s * 0.20, -0.38, cz - 0.03), Vector3(s * 0.20, -0.48, -1.28)], 0.020, Color(0.35, 0.27, 0.20))   # exhaust riser
			e.dark.box_at(hd + Vector3(s * 0.10, 0.04, 0.0), Vector3(0.004, 0.004, 0.10), Color(0.6, 0.6, 0.6))   # plug lead
			e.dark.cylinder(Transform3D(Basis(Vector3.BACK, -PI * 0.5 * s), hd + Vector3(s * 0.08, 0.05, 0.05)), 0.008, 0.008, 0.03, 8, Color(0.85, 0.85, 0.85), true)   # spark plug
		# baffles: the aluminium walls round the top of the cylinders
		e.metal.box_at(Vector3(s * 0.15, 0.10, -1.30), Vector3(0.20, 0.004, 0.52), alu.lightened(0.1))
		e.metal.box_at(Vector3(s * 0.25, 0.02, -1.30), Vector3(0.004, 0.16, 0.52), alu.lightened(0.1))
		e.dark.box_at(Vector3(s * 0.25, 0.105, -1.30), Vector3(0.012, 0.012, 0.54), Color(0.05, 0.05, 0.05))   # the rubber seal
		# magnetos on the back
		e.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(s * 0.07, 0.10, -1.12)), 0.04, 0.04, 0.10, 14, Color(0.15, 0.15, 0.16), true)
		e.dark.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(s * 0.07, 0.10, -1.03)), 0.03, 0.03, 0.02, 14, Color(0.05, 0.05, 0.05), true)
		# mount tubes to the firewall
		for my: float in [0.15, -0.20]:
			_tube(e.dark, [Vector3(s * 0.33, my, -1.01), Vector3(s * 0.14, my * 0.5, -1.22)], 0.012, Color(0.15, 0.15, 0.15))
	# the carb and the air box under the sump, the oil filter, the starter, the alternator and belt
	e.metal.box_at(Vector3(0, -0.33, -1.42), Vector3(0.09, 0.08, 0.09), alu)
	e.dark.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.14, -1.10)), 0.045, 0.045, 0.10, 14, Color(0.06, 0.06, 0.06), true)    # oil filter
	e.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(-0.12, -0.12, -1.58)), 0.05, 0.05, 0.14, 14, Color(0.18, 0.18, 0.18), true)   # starter
	e.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.13, -0.10, -1.56)), 0.055, 0.055, 0.10, 14, Color(0.35, 0.35, 0.36), true)  # alternator
	_tube(e.dark, [Vector3(0.0, 0.0, -1.665), Vector3(0.13, -0.10, -1.665)], 0.008, Color(0.05, 0.05, 0.05))   # the belt
	e.metal.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -1.68)), 0.08, 0.08, 0.015, 20, alu, true)   # pulley
	# the oil dipstick and the cap
	e.dark.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.06, 0.12, -1.18)), 0.012, 0.012, 0.08, 10, Color(0.75, 0.05, 0.04), true)
	_done(e)


func _baggage_door() -> void:
	# the baggage door: left side behind the rear window, hinged at its front edge
	var z0 := 1.22
	var z1 := 1.58
	var y0 := -0.28
	var y1 := SILL - 0.035          # under the rear window (it clipped it)
	var bd := _part("BaggageDoor")
	var x0 := -(_skin_x(z0, (y0 + y1) * 0.5) + 0.004)
	_anim_reg(bd.node, Vector3(x0, 0, z0), Vector3(0, 1, 0), -1.7)
	var gd: Array = []
	for iz in range(7):
		var z := lerpf(z0, z1, float(iz) / 6.0)
		var col: Array = []
		for iy in range(7):
			var y := lerpf(y0, y1, float(iy) / 6.0)
			col.append(Vector3(-(_skin_x(z, y) + 0.004), y, z))
		gd.append(col)
	for iz in range(6):
		for iy in range(6):
			var a0: Vector3 = gd[iz][iy]
			var a1: Vector3 = gd[iz + 1][iy]
			var a2: Vector3 = gd[iz + 1][iy + 1]
			var a3: Vector3 = gd[iz][iy + 1]
			bd.paint.quad(a0, a1, a2, a3, BANDED, Vector3(-1, 0, 0))
			bd.dark.quad(a0 + Vector3(0.002, 0, 0), a1 + Vector3(0.002, 0, 0), a2 + Vector3(0.002, 0, 0), a3 + Vector3(0.002, 0, 0), LINING, Vector3(1, 0, 0))
	var edge: Array = []
	for i in range(7): edge.append(gd[i][0])
	for i in range(1, 7): edge.append(gd[6][i])
	for i in range(5, -1, -1): edge.append(gd[i][6])
	for i in range(5, -1, -1): edge.append(gd[0][i])
	_tube(bd.dark, edge, 0.004, Color(0.04, 0.04, 0.04))
	var hy := (y0 + y1) * 0.5
	bd.metal.box_at(Vector3(-(_skin_x(z1 - 0.05, hy) + 0.012), hy, z1 - 0.05), Vector3(0.012, 0.03, 0.05), Color(0.7, 0.7, 0.7))
	_done(bd)
	# the baggage bay behind it: a floor with tie-down rings, a bag strapped in
	var bay := _part("BaggageBay")
	var by: float = float(_sec_at((z0 + z1) * 0.5)[1]) + 0.06
	# the bay floor molded to the belly as it sweeps up toward the tail (Dave:
	# the flat board stuck out through the bottom at the back), up to the bulkhead
	var bprev: Array = []
	var bz := 1.15
	while bz <= 1.615:
		var bsec := _sec_at(bz)
		var fy: float = float(bsec[1]) + 0.05
		var fx := _skin_x(bz, fy) - 0.015
		var brow := [Vector3(-fx, fy, bz), Vector3(fx, fy, bz)]
		if not bprev.is_empty():
			bay.dark.quad(bprev[0], bprev[1], brow[1], brow[0], Color(0.22, 0.22, 0.22), Vector3(0, 1, 0))
		bprev = brow
		bz = minf(bz + 0.06, 1.615) if bz < 1.615 else 9.0
	bay.dark.rbox(Transform3D(Basis(Vector3.UP, 0.2), Vector3(0.02, by + 0.12, 1.40)), Vector3(0.36, 0.22, 0.26), Color(0.20, 0.26, 0.15), 0.06)   # a duffel
	for rz: float in [1.25, 1.55]:
		bay.metal.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.18, float(_sec_at(rz)[1]) + 0.056, rz)), 0.015, 0.015, 0.006, 10, Color(0.6, 0.6, 0.6), true)
	_done(bay)
	_texture_interior(bay.node)



# ------------------------------------------------------------------------------
#  Test bed tools: engine run, flaps, measure against the real plane, a clip
#  check for the cabin, the 3-view laid over the model
# ------------------------------------------------------------------------------
var _prop_rpm := 0.0
var _prop_goal := 0.0
var _flaps_goal := 0.0
var _flaps := 0.0


func prop_toggle() -> String:
	_prop_goal = 0.0 if _prop_goal > 0.0 else 2300.0
	return "Engine %s." % ("running, 2300 rpm" if _prop_goal > 0.0 else "off - the prop winds down")


func flaps_toggle() -> String:
	_flaps_goal = 0.0 if _flaps_goal > 0.5 else 1.0
	return "Flaps %s." % ("down (40 deg)" if _flaps_goal > 0.5 else "up")


func _tools_step(dt: float) -> void:
	_lights_step(dt)
	# the oil warms while it runs, cools when it's off
	_oil_t = move_toward(_oil_t, 185.0 if _prop_rpm > 500.0 else 70.0, dt * (1.5 if _prop_rpm > 500.0 else 0.4))
	_prop_rpm = move_toward(_prop_rpm, _prop_goal, dt * (900.0 if _prop_goal > _prop_rpm else 500.0))
	if _prop != null:
		spin += dt * (1.2 if _prop_rpm < 1.0 else _prop_rpm / 60.0 * TAU)
		_prop.rotation.z = spin
	if absf(_flaps - _flaps_goal) > 0.0005 and not _ctl_sweep:
		_flaps = move_toward(_flaps, _flaps_goal, dt * 0.4)
		_surf("FlapL", _flaps * 0.70)
		_surf("FlapR", _flaps * 0.70)


func _to_root(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent() as Node3D
	while p != null and p != _root:
		xf = p.transform * xf
		p = p.get_parent() as Node3D
	return xf


## The model's real size against the Super Cub's published numbers.
func measure() -> String:
	var bb := AABB()
	var first := true
	for mi in _root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if (_prop != null and _prop.is_ancestor_of(m)) or (_bp != null and _bp == m):
			continue
		var b: AABB = _to_root(m) * m.get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	var lines := ["MEASURED vs PA-18",
		"span %.2f m  (10.73)" % bb.size.x,
		"length %.2f m  (6.88, cowl to rudder)" % bb.size.z,
		"chord %.2f m  (1.60)" % CHORD,
		"track %.2f m  (1.84 stock)" % (AXLE.x * 2.0),
		"prop dia %.2f m  (1.88-2.0)" % (PROP_R * 2.0)]
	if body != null:
		lines.append("sits %.1f deg nose up" % rad_to_deg(asin(clampf(-body.basis.z.y, -1.0, 1.0))))
		lines.append("gear %s" % " ".join(Array(body.compress).map(func(c): return "%.2f" % c)))
	return "\n".join(lines)


## Anything in the cabin poking out through the fabric (floor, linings,
## seats, controls): every vertex is checked against the skin's real width.
func clip_check() -> String:
	var bad := {}
	var cab := _root.get_node_or_null("Cockpit")
	if cab == null:
		return "No cockpit."
	for mi in cab.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf: Transform3D = _to_root(m)
		var arr := m.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in range(0, v.size(), 7):
			var q: Vector3 = xf * v[i]
			if q.z < -1.0 or q.z > 4.6:
				continue
			var sec := _sec_at(q.z)
			if q.y < float(sec[1]) - 0.004 or (absf(q.x) > _skin_x(q.z, q.y) + 0.004 and q.y < SILL):
				var nm := String(m.get_parent().name)
				bad[nm] = int(bad.get(nm, 0)) + 1
	if bad.is_empty():
		return "Clip check: nothing pokes through the skin."
	var out := ["Clip check - poking out:"]
	for k in bad.keys():
		out.append("  %s (%d pts)" % [k, bad[k]])
	return "\n".join(out)


## The 3-view laid over the model at its real scale (reference/supercub/00):
## look with the flat side / front view and the drawing's lines show through.
var _bp: MeshInstance3D
## Reference markers (Dave's idea): numbered dots on known points off the
## 3-view and photos - door corners, posts, strut and gear fittings, the axle,
## inlets - so we can both say "marker 7 is too low" and check them against
## the photos. Debug only: toggled from the test bed, never in the game.
var _markers: Node3D


func marker_points() -> Array:
	var pf0: Vector2 = POST_F[0]
	var pf1: Vector2 = POST_F[1]
	var pts := [
		["front post foot", Vector3(0.40, pf0.y, pf0.x)], ["front post top", Vector3(0.40, pf1.y, pf1.x)],
		["door top rear", Vector3(0.40, WIN_TOP, DOOR_REAR_Z)], ["door sill rear", Vector3(0.40, SILL, DOOR_REAR_Z)],
		["lower door front foot", Vector3(0.40, DOOR_BOT_Y, DOOR_BOT_Z)], ["lower door rear foot", Vector3(0.40, DOOR_BOT_Y, DOOR_BOT_REAR_Z)],
		["rear window top", Vector3(0.40, WIN_TOP, 0.835)], ["rear window bottom", Vector3(0.38, 0.175, 1.40)],
		["windshield foot", Vector3(0.0, 0.245, -1.00)], ["wing LE root", Vector3(ROOT_X, WING_Y, LE_Z)],
		["strut wing fitting", Vector3(STRUT_X, WING_Y - 0.02, LE_Z + SPAR_F)], ["strut foot", Vector3(0.37, -0.61, 0.15)],
		["gear shock top", Vector3(0.37, -0.52, -0.37)], ["axle", AXLE],
		["inlet", Vector3(SNOUT_X, SNOUT_Y, -1.80)], ["prop hub", PROP_AT], ["tailwheel", TAIL_HUB],
	]
	return pts


func markers_toggle() -> String:
	if _markers != null and is_instance_valid(_markers):
		_markers.queue_free()
		_markers = null
		return "Markers off."
	_markers = Node3D.new()
	_markers.name = "RefMarkers"
	_root.add_child(_markers)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.1, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	var sm := SphereMesh.new()
	sm.radius = 0.018
	sm.height = 0.036
	var i := 1
	for e in marker_points():
		var m := MeshInstance3D.new()
		m.mesh = sm
		m.material_override = mat
		m.position = e[1]
		_markers.add_child(m)
		var l := Label3D.new()
		l.text = str(i)
		l.font_size = 40
		l.pixel_size = 0.0015
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.modulate = Color(1.0, 1.0, 0.2)
		l.outline_size = 10
		l.position = (e[1] as Vector3) + Vector3(0, 0.05, 0)
		_markers.add_child(l)
		i += 1
	var names: Array = []
	var j := 1
	for e2 in marker_points():
		names.append("%d %s" % [j, e2[0]])
		j += 1
	return "Markers: " + ", ".join(names)


func blueprint(view: String) -> String:
	if _bp != null and is_instance_valid(_bp):
		_bp.queue_free()
		_bp = null
	if view == "off":
		return "Blueprint off."
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://reference/supercub/00_3view.jpg"))
	if img == null:
		return "No 3-view image."
	# just the drawing's lines: the crop for this view, dark pixels kept,
	# the light (and the checker the drawing was shot on) see-through
	var r := Rect2i(20, 140, 310, 140) if view == "side" else Rect2i(330, 140, 460, 140)
	var crop := img.get_region(r)
	crop.convert(Image.FORMAT_RGBA8)
	for y in range(crop.get_height()):
		for x in range(crop.get_width()):
			var c := crop.get_pixel(x, y)
			var dark := clampf((0.62 - c.get_luminance()) * 3.0, 0.0, 1.0)
			crop.set_pixel(x, y, Color(0.05, 0.25, 1.0, dark))
	var tex := ImageTexture.create_from_image(crop)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	var q := QuadMesh.new()
	_bp = MeshInstance3D.new()
	_bp.name = "Blueprint"
	if view == "side":
		# crop (20,140)-(330,280), 40.7 px/m, the axle at (73.25, 122.5) in it
		var px := 40.7
		q.size = Vector2(310.0 / px, 140.0 / px)
		_bp.position = Vector3(0.6, AXLE.y - 0.044 - (70.0 - 122.5) / px, -0.36 + (155.0 - 73.25) / px)
		_bp.rotation = Vector3(0, -PI * 0.5, 0)
	else:
		# crop (330,140)-(790,280), 41.2 px/m, the centreline at x 556, the wing's chord at y 177.3
		var px2 := 41.2
		q.size = Vector2(460.0 / px2, 140.0 / px2)
		_bp.position = Vector3(-(560.0 - 556.0) / px2, WING_Y - (210.0 - 177.3) / px2, -2.6)
		_bp.rotation = Vector3(0, PI, 0)
	q.material = m
	_bp.mesh = q
	_root.add_child(_bp)
	return "Blueprint: %s (use the flat %s view)." % [view, view]


# ------------------------------------------------------------------------------
#  Damage (vehicle_breakage.gd does the denting, cracking, tearing off):
#  where the test bed's hits land on a Cub, and the plane's own crashes
# ------------------------------------------------------------------------------
var _brk: RefCounted
func part_detached(nm: String) -> void:
	if nm == "PropHub":
		_prop = null
		_prop_goal = 0.0
	# a gear leg gone: its wheel goes with it and that corner drops onto the belly / wing
	var lost := {"GearL": [0, "WheelL"], "GearR": [1, "WheelR"], "TailGear": [2, "TailWheel"]}
	if lost.has(nm):
		var wi: int = lost[nm][0]
		var wn := _root.get_node_or_null(String(lost[nm][1])) as Node3D
		if wn != null and _brk != null:
			_brk.detach(wn, Vector3(0, 0.5, 0) * 200.0, wn.global_position)
		if body != null and wi < body.wheels.size():
			(body.wheels[wi] as Array)[0] = Vector3(0, 50.0, 0)     # no wheel there any more
			body.compress[wi] = 0.0
	var keep: Array = []
	for a in _anims:
		var n: Node3D = a[0]
		if is_instance_valid(n) and n.get_parent() != null and _root.is_ancestor_of(n):
			keep.append(a)
	_anims = keep


## [point (plane frame), impulse (plane frame), radius] per test.
func damage_test(what: String, brk: RefCounted) -> String:
	_brk = brk
	var xf := _root.global_transform
	var hits := {
		"crash_front": [[Vector3(0, -0.1, -1.9), Vector3(0, 0.1, 1) * 15000.0, 0.7]],
		"crash_side": [[Vector3(-0.45, 0.0, 0.2), Vector3(1, 0, 0) * 9000.0, 0.7]],
		"shoot": [[Vector3(0.1, 0.45, -0.75), Vector3(0, -0.4, 1) * 300.0, 0.15]],
		"prop_strike": [[Vector3(0, PROP_AT.y - PROP_R, PROP_AT.z), Vector3(0, 0.6, 1) * 11000.0, 0.35]],
		"wing_tree": [[Vector3(-4.6, WING_Y, LE_Z - 0.05), Vector3(0.1, 0, 1) * 34000.0, 0.9]],
		"hard_landing": [[Vector3(-AXLE.x, AXLE.y, AXLE.z), Vector3(-0.3, 1, 0.2) * 15000.0, 0.45], [Vector3(AXLE.x, AXLE.y, AXLE.z), Vector3(0.3, 1, 0.2) * 15000.0, 0.45]],
		"tail_strike": [[Vector3(0, -0.05, 4.6), Vector3(0, 1, -0.3) * 6000.0, 0.5]],
	}
	if what == "explode":
		brk.explode(xf * Vector3(0, 0.0, -1.3), 45000.0)
		return "BOOM."
	if not hits.has(what):
		return ""
	for h in hits[what]:
		brk.hit(xf * (h[0] as Vector3), xf.basis * (h[1] as Vector3), float(h[2]))
	match what:
		"prop_strike": return "Prop strike: the prop hits the ground."
		"wing_tree": return "Left wing into a tree at 40 km/h."
		"hard_landing": return "Hard landing: the gear takes it."
		"tail_strike": return "Tail slammed down."
		"crash_front": return "Nose-first crash."
		"crash_side": return "Side hit at the cabin."
		"shoot": return "Something hit the windshield."
	return ""


# ------------------------------------------------------------------------------
#  The air filter (Dave: a better model, red or yellow, replaceable in the
#  game): a round pleated element on the chin tube's mouth - rubber lip
#  clamped on the tube, the pleated media (oiled cotton, red; or yellow foam),
#  the wire mesh round it, the chrome end cap and its stud. Its own part with
#  a "service" tag; it gets dirty and can be pulled and a new one fitted.
# ------------------------------------------------------------------------------
const SNOUT_X := 0.185             # the nose inlets ("snouts"), at the face's upper corners
const SNOUT_Y := 0.045
const FILTER_AT := Vector3(0, -0.585, -1.74)     # the filter's front end, slung under the nose
const FILTER_LEN := 0.24                         # 20% smaller (Dave)
const FILTER_R := 0.060
var filter_kind := "white"                       # "white" paper, "red" oiled cotton, "yellow" foam
var filter_dirt := 0.0                           # 0 clean .. 1 choked (brown, the engine loses power)
var _filter: Node3D


## The air filter where the black chin tube was (Dave, ref 05): a cylinder
## lying fore-and-aft under the nose - the pleated element in its diamond
## wire mesh between two black end caps (the front one open: the intake,
## the back one on the duct to the carb), the caps' moulded lugs.
func _air_filter() -> void:
	var f := _part("AirFilter")
	f.node.set_meta("service", "air_filter")
	_filter = f.node
	var ax := Vector3(0, 0.02, 1).normalized()       # back along the chin
	var bas := Basis.looking_at(-ax, Vector3.UP)
	var c0 := FILTER_AT
	var r := FILTER_R
	var L := FILTER_LEN
	var cap := 0.035
	var col := {"white": Color(0.90, 0.89, 0.84), "red": Color(0.70, 0.10, 0.06), "yellow": Color(0.92, 0.78, 0.12)}
	var media: Color = col.get(filter_kind, col["white"])
	media = media.lerp(Color(0.30, 0.24, 0.16), filter_dirt * 0.85)
	var cyl := bas * Basis(Vector3.RIGHT, PI * 0.5)    # cylinder axis (+Y) along ax
	# the black end caps, with their lugs
	for e in [0.0, L - cap]:
		var cc: Vector3 = c0 + ax * float(e)
		f.dark.cylinder(Transform3D(cyl, cc), r * 1.12, r * 1.12, cap, 24, Color(0.05, 0.05, 0.05), true)
		for k in range(6):
			var a := TAU * float(k) / 6.0
			var d := bas.x * cos(a) + bas.y * sin(a)
			f.dark.box(Transform3D(Basis.looking_at(d, ax), cc + ax * (cap * 0.5) + d * r * 1.14), Vector3(0.022, cap * 0.9, 0.010), Color(0.07, 0.07, 0.07))
	# the open front: the intake hole in the front cap
	f.dark.cylinder(Transform3D(cyl, c0 - ax * 0.001), r * 0.70, r * 0.70, 0.004, 20, Color(0.01, 0.01, 0.01), true)
	f.dark.cylinder(Transform3D(cyl, c0 - ax * 0.004), r * 0.82, r * 0.82, 0.004, 20, Color(0.10, 0.10, 0.10), true)
	# the pleated element between the caps: the paper cylinder and its pleat ridges
	f.dark.cylinder(Transform3D(cyl, c0 + ax * cap), r * 0.96, r * 0.96, L - 2.0 * cap, 40, media, false)
	for k2 in range(40):
		var a2 := TAU * (float(k2) + 0.5) / 40.0
		var d2 := bas.x * cos(a2) + bas.y * sin(a2)
		f.dark.box(Transform3D(Basis.looking_at(ax, d2), c0 + ax * (L * 0.5) + d2 * r * 0.975), Vector3(0.0045, 0.006, L - 2.0 * cap), media.darkened(0.18))
	# the diamond wire mesh over it
	var turns := 10
	for sgn: float in [-1.0, 1.0]:
		for k3 in range(turns):
			var pts: Array = []
			for q in range(13):
				var t := float(q) / 12.0
				var a3 := TAU * float(k3) / float(turns) + sgn * t * PI * 0.9
				pts.append(c0 + ax * (cap + t * (L - 2.0 * cap)) + (bas.x * cos(a3) + bas.y * sin(a3)) * r * 1.012)
			_tube(f.metal, pts, 0.0010, Color(0.62, 0.62, 0.62))
	_done(f)


## The intake tube (Dave: run it right to the filter): a black hose from the
## filter's back cap, straight aft under the chin and curving up into the
## carb box under the cowl; a clamp each end. It stays when the filter's pulled.
func _intake_tube() -> void:
	var t := _part("IntakeTube")
	var ax := Vector3(0, 0.02, 1).normalized()
	var a := FILTER_AT + ax * (FILTER_LEN - 0.004)
	var pts: Array = []
	for k in range(9):
		var u := float(k) / 8.0
		var z := lerpf(a.z, -1.20, u)
		var y := lerpf(a.y + 0.002, -0.46, smoothstep(0.35, 1.0, u))
		pts.append(Vector3(0, y, z))
	_tube(t.dark, pts, FILTER_R * 0.80, Color(0.06, 0.06, 0.06))
	for e in [pts[0] + ax * 0.03, pts[5]]:
		var dir: Vector3 = (pts[1] - pts[0]).normalized() if e == pts[0] + ax * 0.03 else (pts[6] - pts[4]).normalized()
		var b := Basis.looking_at(-dir, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
		t.metal.cylinder(Transform3D(b, e), FILTER_R * 0.86, FILTER_R * 0.86, 0.014, 20, Color(0.70, 0.70, 0.70), true)
	_done(t)


## Service: pull the filter (the intake left open), fit a new one (clean).
func filter_service() -> String:
	if _filter != null and is_instance_valid(_filter):
		_filter.queue_free()
		_filter = null
		return "Air filter off - the intake is open (don't run it like this)."
	filter_dirt = 0.0
	_air_filter()
	return "New %s air filter fitted." % filter_kind


func filter_swap_kind() -> String:
	var kinds := ["white", "red", "yellow"]
	filter_kind = kinds[(kinds.find(filter_kind) + 1) % kinds.size()]
	if _filter != null and is_instance_valid(_filter):
		_filter.queue_free()
		_air_filter()
	return "Filter: %s (%s)." % [filter_kind, {"white": "paper", "red": "oiled cotton", "yellow": "foam"}[filter_kind]]


## Dirt builds with dusty strips; a choked filter costs power (engine_power_k).
func filter_add_dirt(d: float = 0.25) -> String:
	filter_dirt = clampf(filter_dirt + d, 0.0, 1.0)
	if filter_dirt >= 1.0:
		filter_dirt = 0.0
	if _filter != null and is_instance_valid(_filter):
		_filter.queue_free()
		_air_filter()
	return "Air filter %d%% dirty (power %d%%)." % [int(filter_dirt * 100.0), int(engine_power_k() * 100.0)]


func engine_power_k() -> float:
	if _filter == null or not is_instance_valid(_filter):
		return 1.0
	return 1.0 - 0.18 * filter_dirt * filter_dirt


# ------------------------------------------------------------------------------
#  What the instruments read (the flight model will feed these in the game;
#  on the ground: the taxi speed, the field elevation, the engine's run)
# ------------------------------------------------------------------------------
var field_elev_ft := 41.0                # Hope (CYHE) is about 12 m / 39 ft
var _oil_t := 70.0
func ias_kt() -> float:
	return absf(body.speed) * 1.944 if body != null else 0.0


func alt_ft() -> float:
	return field_elev_ft + (global_position.y * 3.281 if is_inside_tree() else 0.0)


func vsi_fpm() -> float:
	return body.vel.y * 196.85 if body != null else 0.0


func oil_psi() -> float:
	return clampf(_prop_rpm / 2300.0 * 75.0, 0.0, 80.0)


func oil_temp_f() -> float:
	return _oil_t


# ------------------------------------------------------------------------------
#  Interior textures (Dave: full texture interior): a woven-fabric grain on
#  the seats, linings and floor, laid on by triplanar mapping (the meshes have
#  no UVs) and multiplied with the parts' own colours; the panel and the
#  instruments keep their own looks
# ------------------------------------------------------------------------------
static var _fabric: StandardMaterial3D
func _interior_mat() -> StandardMaterial3D:
	if _fabric != null:
		return _fabric
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_CELLULAR
	nz.frequency = 0.09
	tex.noise = nz
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.78, 0.78, 0.78))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	tex.color_ramp = ramp
	m.albedo_texture = tex
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	var nz2 := FastNoiseLite.new()
	nz2.noise_type = FastNoiseLite.TYPE_PERLIN
	nz2.frequency = 0.35
	nt.noise = nz2
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = 0.6
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(14, 14, 14)
	m.roughness = 0.92
	_fabric = m
	return m


func _texture_interior(cab: Node3D) -> void:
	for mi in cab.find_children("Trim", "MeshInstance3D", true, false):
		var n := mi as MeshInstance3D
		var under_panel := false
		var pnode := n.get_parent()
		while pnode != null and pnode != cab:
			if String(pnode.name) == "Dash":
				break                    # the dash's padded vinyl gets the texture too
			if String(pnode.name) == "Panel":
				under_panel = true
			pnode = pnode.get_parent()
		if not under_panel:
			n.material_override = _interior_mat()

func _tube(kit: RefCounted, pts: Array, r: float, col: Color) -> void:
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := b - a
		if d.length() < 0.0001:
			continue
		var y := d.normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		kit.cylinder(Transform3D(Basis(x, y, x.cross(y)), a), r, r, d.length(), 8, col, true)


var spin := 0.0
func _process(dt: float) -> void:
	_anim_step(dt)
	_tools_step(dt)
