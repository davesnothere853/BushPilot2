extends Node3D
## The look of the aeroplane: a low-poly high-wing taildragger built from simple
## shapes, with moving control surfaces, wheels and propeller.
## Sits as a child of the flight model and reads its state every frame.

const MeshKit = preload("res://scripts/meshkit.gd")
const DentMesh = preload("res://scripts/dent_mesh.gd")
const CockpitScript = preload("res://scripts/cockpit.gd")
const Fx = preload("res://scripts/fx.gd")

const Liveries = preload("res://scripts/liveries.gd")

# Paint (set from the plane's livery before building; liveries.gd).
var CREAM := Color(0.90, 0.86, 0.76)
var ORANGE := Color(0.82, 0.36, 0.10)
var BROWN := Color(0.36, 0.22, 0.13)
const GLASS := Color(0.10, 0.14, 0.19)
const DARK := Color(0.10, 0.10, 0.11)
const TIRE := Color(0.08, 0.08, 0.08)
const METAL := Color(0.62, 0.63, 0.64)

var plane: Node3D
var _prop: Node3D
var _prop_blades: MeshInstance3D
var _prop_disc: MeshInstance3D
var _flap_l: Node3D
var _flap_r: Node3D
var _ail_l: Node3D
var _ail_r: Node3D
var _elevator: Node3D
var _rudder: Node3D
var _wheels: Array[Node3D] = []
var _wheel_rest: Array[Vector3] = []
var _wheel_spin: Array[float] = [0.0, 0.0, 0.0]
var _tyre_fitted := ""
var _caster_angle := 0.0
var _prop_angle := 0.0
var _body: MeshInstance3D
var _windscreen: Array = []
var debris: Node3D                  # set by main: where broken-off pieces go
var wind: Node                      # for smoke drift
var _glass: MeshInstance3D
var _fire: Node3D
var _fire_t := 0.0
var _burn_wait := 0.0
var _fire_point := Vector3(0, -0.1, -1.5)
var _shown_off: Array[bool] = [false, false]
var _legs: Array[MeshInstance3D] = []
var _leg_tops: Array[Vector3] = [Vector3(-0.50, -0.48, -0.52), Vector3(0.50, -0.48, -0.52)]
var _tyres: Array[Node3D] = []
const FloatVisual = preload("res://scripts/float_visual.gd")
var _floats: Node3D
var _doors := {}          # "cabin"/"bay" -> [pivot, opening, angle now]
var _reg_labels: Array[Label3D] = []
var _surface_rest := {}             # hinged panel -> its undamaged position
var _droop := Vector2.ZERO          # how far each wingtip sags (left, right), metres
var _flex := 0.0                    # wing bend from load (negative: tips up), metres
var _prop_state := -1
var _pending: Array = []            # dents and scrapes waiting to be pressed into the skin
var _rebuild_wait := 0.0
var _smoke: CPUParticles3D
var _smoke_mat: StandardMaterial3D
var _mist: Array[CPUParticles3D] = []
var _interior_hidden := false
var cockpit: Node3D                 # the clickable cockpit; main.gd calls cockpit.build()
var _disc_mat: StandardMaterial3D


func _apply_livery() -> void:
	if plane == null:
		return
	var lv: Array = Liveries.for_plane(plane)
	CREAM = lv[1]
	ORANGE = lv[2]
	BROWN = lv[3]


## Strip everything this visual built (not what main hung on it, meta "ext")
## and build it again in the plane's current paint.
func repaint() -> void:
	_apply_livery()
	for c in get_children():
		if c.has_meta("ext"):
			continue
		remove_child(c)
		c.queue_free()
	_wheels.clear()
	_wheel_rest.clear()
	_tyres.clear()
	_legs.clear()
	_floats = null
	_doors.clear()
	_reg_labels.clear()
	_surface_rest.clear()
	_mist.clear()
	_windscreen.clear()
	_pending.clear()
	_prop_state = -1
	_shown_off = [false, false]
	_tyre_fitted = ""
	engine_parts = null
	_build_body()
	_build_moving_parts()
	_build_cockpit()
	_build_effects()


func _ready() -> void:
	_apply_livery()
	_build_body()
	_build_moving_parts()
	_build_cockpit()
	_build_effects()
	if plane != null:
		plane.dented.connect(_on_dented)
		plane.scraped.connect(_on_scraped)
		plane.repaired.connect(_on_repaired)
		plane.part_broken.connect(_on_part_broken)
		plane.fire_started.connect(_on_fire)
		plane.exploded.connect(_on_exploded)
		plane.crashed.connect(_on_crashed_look)


## A fuselage cross-section: a rectangle with rounded corners of radius `c`.
static func _ring(z: float, w: float, top: float, bot: float, c: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var centres := [Vector2(w - c, top - c), Vector2(w - c, bot + c), Vector2(-w + c, bot + c), Vector2(-w + c, top - c)]
	var starts := [90.0, 0.0, -90.0, -180.0]
	for k in range(4):
		for j in range(4):
			var a := deg_to_rad(starts[k] - 30.0 * float(j))
			var cc: Vector2 = centres[k]
			out.append(Vector3(cc.x + cos(a) * c, cc.y + sin(a) * c, z))
	return out


## An airfoil section (about 12 % thick, slightly cambered) at span position `x`.
static func _airfoil(x: float, y: float, z_le: float, chord: float, scale: float = 1.0) -> PackedVector3Array:
	var xs := [1.0, 0.85, 0.7, 0.55, 0.4, 0.3, 0.2, 0.1, 0.05, 0.025, 0.0]
	var yt := [0.0013, 0.0247, 0.0402, 0.0507, 0.058, 0.06, 0.0574, 0.0468, 0.0355, 0.0262, 0.0]
	var out := PackedVector3Array()
	for k in range(xs.size()):
		var f: float = xs[k]
		var camber := 0.08 * f * (1.0 - f)
		out.append(Vector3(x, y + (camber + float(yt[k]) * 1.1 * scale) * chord, z_le + f * chord))
	for k in range(xs.size() - 2, 0, -1):
		var f2: float = xs[k]
		var camber2 := 0.08 * f2 * (1.0 - f2)
		out.append(Vector3(x, y + (camber2 - float(yt[k]) * 1.1 * scale) * chord, z_le + f2 * chord))
	return out


static func _centroid(ring: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for q in ring:
		c += q
	return c / float(ring.size())


## Where a window is open at station z: [bottom, top], or [] where the side is solid.
static func _window_at(z: float) -> Array:
	if z >= -0.78 and z <= -0.47:
		return [0.28, lerpf(0.28, 0.79, (z + 0.78) / 0.31)]
	if z > -0.47 and z <= 0.32:
		return [0.28, 0.79]
	if z >= 0.42 and z <= 1.02:
		return [lerpf(0.30, 0.34, (z - 0.42) / 0.60), 0.79]
	return []


## The pilot's door opening in the left side (z front/back, y bottom/top).
const BAY_Z0 := 1.16
const BAY_Z1 := 1.58
var _stripe_secs: Array = []
const DOOR_Z0 := -0.48
const DOOR_Z1 := 0.34
const DOOR_Y0 := -0.42
const DOOR_Y1 := 0.78


## The flat sides of the cabin, with openings for the windows.
func _cabin_sides(kit: RefCounted, sections: Array) -> void:
	var zs := [-1.15, -0.78, -0.47, -0.45, 0.32, 0.42, 1.02, 1.10, 1.65]
	# Side half-width and the top and bottom of the flat part, along the cabin.
	var side_at := func(z: float) -> Vector3:
		for k in range(sections.size() - 1):
			var a: Array = sections[k]
			var b: Array = sections[k + 1]
			if z >= float(a[0]) - 0.0001 and z <= float(b[0]) + 0.0001:
				var t := (z - float(a[0])) / (float(b[0]) - float(a[0]))
				return Vector3(lerpf(a[1], b[1], t), lerpf(float(a[2]) - float(a[4]), float(b[2]) - float(b[4]), t), lerpf(float(a[3]) + float(a[4]), float(b[3]) + float(b[4]), t))
		return Vector3(0.5, 0.8, -0.5)
	for side in [-1.0, 1.0]:
		var out := Vector3(side, 0, 0)
		for k in range(zs.size() - 1):
			var za: float = zs[k]
			var zb: float = zs[k + 1]
			var sa: Vector3 = side_at.call(za)
			var sb: Vector3 = side_at.call(zb)
			var pa := func(y: float) -> Vector3: return Vector3(side * sa.x, y, za)
			var pb := func(y: float) -> Vector3: return Vector3(side * sb.x, y, zb)
			var wa := _window_at(za + 0.0005)
			var wb := _window_at(zb - 0.0005)
			if side < 0.0 and za > DOOR_Z0 - 0.04 and zb < DOOR_Z1 + 0.04:
				# The pilot's door: a real hole in the skin (the door panel
				# closes it), so the cabin shows when it swings open.
				kit.quad(pa.call(sa.z), pb.call(sb.z), pb.call(DOOR_Y0), pa.call(DOOR_Y0), CREAM, out)
				if sa.y > DOOR_Y1:
					kit.quad(pa.call(DOOR_Y1), pb.call(DOOR_Y1), pb.call(sb.y), pa.call(sa.y), CREAM, out)
			elif wa.is_empty() or wb.is_empty():
				kit.quad(pa.call(sa.z), pb.call(sb.z), pb.call(sb.y), pa.call(sa.y), CREAM, out)
			else:
				kit.quad(pa.call(sa.z), pb.call(sb.z), pb.call(float(wb[0])), pa.call(float(wa[0])), CREAM, out)
				kit.quad(pa.call(float(wa[1])), pb.call(float(wb[1])), pb.call(sb.y), pa.call(sa.y), CREAM, out)


static func _beam(kit: RefCounted, a: Vector3, b: Vector3, radius: float, col: Color, sides: int = 5) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	kit.cylinder(Transform3D(Basis(x, y, z), a), radius, radius, d.length(), sides, col, true)


## The stripe's height and band size at fuselage station k.
static func _stripe_station(sections: Array, k: int) -> Array:
	var sec: Array = sections[k]
	var y: float = lerpf(sec[3], sec[2], 0.5) * 0.3 + 0.02
	if k >= 5:
		y = lerpf(sec[3], sec[2], 0.55)
	var sz: float = clampf((float(sec[2]) - float(sec[3])) / 1.54, 0.3, 1.0)
	return [float(sec[1]), y, sz]


## The orange and brown bands between stations z0 and z1 inside section i,
## as [a, b, c, d, colour, normal] quads.
func _stripe_quads(sections: Array, i: int, side: float, z0: float, z1: float) -> Array:
	var A := _stripe_station(sections, i)
	var B := _stripe_station(sections, i + 1)
	var za: float = sections[i][0]
	var zb: float = sections[i + 1][0]
	var at := func(z: float) -> Array:
		var t := clampf((z - za) / (zb - za), 0.0, 1.0)
		return [lerpf(A[0], B[0], t), lerpf(A[1], B[1], t), lerpf(A[2], B[2], t)]
	var p: Array = at.call(z0)
	var q: Array = at.call(z1)
	var xa: float = side * (float(p[0]) + 0.012)
	var xb: float = side * (float(q[0]) + 0.012)
	var out := Vector3(side, 0, 0)
	var bands := [[0.10, -0.03, ORANGE], [-0.075, -0.125, BROWN]]
	var res: Array = []
	for bd in bands:
		res.append([Vector3(xa, p[1] + bd[0] * p[2], z0), Vector3(xb, q[1] + bd[0] * q[2], z1),
			Vector3(xb, q[1] + bd[1] * q[2], z1), Vector3(xa, p[1] + bd[1] * p[2], z0), bd[2], out])
	return res


func _build_body() -> void:
	var kit := MeshKit.new()
	# Fuselage: [z, half width, top, bottom, corner bevel]
	var sections := [
		[-2.05, 0.34, 0.28, -0.36, 0.12],
		[-1.92, 0.48, 0.42, -0.50, 0.14],
		[-1.15, 0.54, 0.50, -0.58, 0.14],
		[-0.45, 0.56, 0.92, -0.62, 0.12],
		[1.10, 0.54, 0.92, -0.62, 0.12],
		[1.65, 0.46, 0.60, -0.50, 0.12],
		[3.20, 0.26, 0.38, -0.22, 0.08],
		[5.10, 0.07, 0.30, 0.02, 0.03],
	]
	var rings: Array = []
	for s in sections:
		rings.append(_ring(s[0], s[1], s[2], s[3], s[4]))
	# Skin, leaving out the flat cabin sides (built next, with window openings).
	var cabin_from := 2
	var cabin_to := 5
	for r in range(rings.size() - 1):
		var ra: PackedVector3Array = rings[r]
		var rb: PackedVector3Array = rings[r + 1]
		var count := ra.size()
		var mid := (_centroid(ra) + _centroid(rb)) * 0.5
		for i in range(count):
			if r >= cabin_from and r < cabin_to and (i == 3 or i == 11):
				continue
			var j := (i + 1) % count
			if r == 1 and ((i >= 1 and i <= 4) or (i >= 9 and i <= 12)):
				# The side cowl doors: built as their own hinged panels.
				var cs := 1.0 if i <= 4 else -1.0
				(_cowl_q[cs] as Array).append([ra[i], ra[j], rb[j], rb[i], CREAM, (ra[i] + ra[j] + rb[i] + rb[j]) * 0.25 - mid])
				continue
			var face_mid := (ra[i] + ra[j] + rb[i] + rb[j]) * 0.25
			if r == cabin_from and (i >= 13 or i <= 1):
				# The windscreen wraps over the top and round the upper corners.
				_windscreen.append([ra[i], ra[j], rb[j], rb[i], face_mid - mid])
				continue
			kit.quad(ra[i], ra[j], rb[j], rb[i], CREAM, face_mid - mid)
			if r == cabin_from and (i == 2 or i == 12):
				# Windscreen pillars: also seen from inside the cabin.
				kit.quad(ra[i], ra[j], rb[j], rb[i], Color(0.42, 0.40, 0.36), mid - face_mid)
	_cowl_hinge = {1.0: [(rings[1] as PackedVector3Array)[1], (rings[2] as PackedVector3Array)[1]],
		-1.0: [(rings[1] as PackedVector3Array)[13], (rings[2] as PackedVector3Array)[13]]}
	var first: PackedVector3Array = rings[0]
	var last: PackedVector3Array = rings[rings.size() - 1]
	for i in range(first.size()):
		kit.tri(_centroid(first), first[i], first[(i + 1) % first.size()], CREAM, Vector3.FORWARD)
		kit.tri(_centroid(last), last[i], last[(i + 1) % last.size()], CREAM, Vector3.BACK)
	_cabin_sides(kit, sections)

	# Paint stripes along each side, following the taper of the hull. Each
	# station has one height and one band size, so the pieces meet without
	# a step; the baggage door carries its own piece (see _build_doors).
	for i in range(1, sections.size() - 1):
		for side in [-1.0, 1.0]:
			if i == 1:
				# On the cowl door: goes with it.
				for q in _stripe_quads(sections, i, side, float(sections[i][0]), float(sections[i + 1][0])):
					(_cowl_q[side] as Array).append(q)
				continue
			var za: float = sections[i][0]
			var zb: float = sections[i + 1][0]
			var spans := [[za, zb]]
			if side < 0.0:
				# the baggage door and the cabin door carry their own pieces
				# of the stripe (see _build_doors), so it swings open with them
				for hole in [[DOOR_Z0, DOOR_Z1], [BAY_Z0, BAY_Z1]]:
					var cut: Array = []
					for sp0 in spans:
						var s0: float = sp0[0]
						var s1: float = sp0[1]
						if s0 < float(hole[1]) and s1 > float(hole[0]):
							if s0 < float(hole[0]):
								cut.append([s0, float(hole[0])])
							if s1 > float(hole[1]):
								cut.append([float(hole[1]), s1])
						else:
							cut.append(sp0)
					spans = cut
			for sp in spans:
				for q in _stripe_quads(sections, i, side, float(sp[0]), float(sp[1])):
					kit.quad(q[0], q[1], q[2], q[3], q[4], q[5])
	_stripe_secs = sections

	# Glass
	# Glass is its own see-through mesh (built below), so the cabin shows through it.
	var glass_kit := MeshKit.new()
	for q in _windscreen:
		glass_kit.quad(q[0], q[1], q[2], q[3], GLASS, q[4])
	for side in [-1.0, 1.0]:
		var x: float = side * 0.575
		if side < 0.0:
			# the left side's big window is the cabin door's (it swings with
			# it); only the little fixed quarter light ahead of it is here
			glass_kit.tri(Vector3(x, 0.79, -0.48), Vector3(x, 0.28, -0.48), Vector3(x, 0.28, -0.78), GLASS, Vector3(side, 0, 0))
		else:
			glass_kit.quad(Vector3(x, 0.79, -0.47), Vector3(x, 0.79, 0.32), Vector3(x, 0.28, 0.32), Vector3(x, 0.28, -0.78), GLASS, Vector3(side, 0, 0))
		glass_kit.quad(Vector3(x * 0.985, 0.79, 0.42), Vector3(x * 0.97, 0.79, 1.02), Vector3(x * 0.97, 0.34, 1.02), Vector3(x * 0.985, 0.30, 0.42), GLASS, Vector3(side, 0, 0))
		# Window frames
		for zz in [0.37]:
			_beam(kit, Vector3(x * 1.005, 0.28, zz), Vector3(x * 1.005, 0.79, zz), 0.03, CREAM, 6)
		if side < 0.0:
			_beam(kit, Vector3(x * 1.005, 0.795, DOOR_Z1), Vector3(x * 1.005, 0.795, 1.02), 0.012, CREAM, 6)
			_beam(kit, Vector3(x * 1.005, 0.28, -0.78), Vector3(x * 1.005, 0.28, DOOR_Z0), 0.012, CREAM, 6)
		else:
			_beam(kit, Vector3(x * 1.005, 0.795, -0.47), Vector3(x * 1.005, 0.795, 1.02), 0.012, CREAM, 6)
			_beam(kit, Vector3(x * 1.005, 0.28, -0.78), Vector3(x * 1.005, 0.28, 0.32), 0.012, CREAM, 6)
	# Anti-glare paint on top of the cowl, as bush planes of the era wore
	kit.quad(Vector3(-0.38, 0.508, -1.16), Vector3(0.38, 0.508, -1.16), Vector3(0.32, 0.428, -1.92), Vector3(-0.32, 0.428, -1.92), Color(0.13, 0.14, 0.13), Vector3.UP)
	# Nose bowl and air intake
	kit.box_at(Vector3(0, -0.05, -2.07), Vector3(0.42, 0.20, 0.05), DARK)
	# Exhaust stub
	_beam(kit, Vector3(0.30, -0.50, -1.50), Vector3(0.34, -0.66, -1.30), 0.04, DARK, 4)

	# Wing: airfoil-section panels with a little dihedral and rounded, coloured tips.
	var dih := tan(deg_to_rad(1.6))
	var wing_y := func(ax: float) -> float: return 0.955 + (ax - 0.25) * dih
	kit.loft([_airfoil(-0.25, wing_y.call(0.25), -0.39, 1.17), _airfoil(0.25, wing_y.call(0.25), -0.39, 1.17)], CREAM, false, false)
	for side in [-1.0, 1.0]:
		var panel_secs: Array = []
		for ax in [0.25, 1.9, 3.6, 5.25]:
			panel_secs.append(_airfoil(side * ax, wing_y.call(ax), -0.39, 1.17))
		if side < 0.0:
			panel_secs.reverse()
		kit.loft(panel_secs, CREAM, false, false)
		var tip_sections: Array = [_airfoil(side * 5.25, wing_y.call(5.25), -0.39, 1.17),
			_airfoil(side * 5.42, wing_y.call(5.42), -0.37, 1.13, 0.85),
			_airfoil(side * 5.50, wing_y.call(5.50), -0.33, 1.02, 0.45)]
		if side < 0.0:
			tip_sections.reverse()
		kit.loft(tip_sections, ORANGE, side < 0.0, side > 0.0)
		# Struts
		_beam(kit, Vector3(side * 0.54, -0.52, -0.10), Vector3(side * 2.75, 0.93, -0.05), 0.035, CREAM, 8)
		_beam(kit, Vector3(side * 0.54, -0.52, 0.35), Vector3(side * 2.75, 0.93, 0.50), 0.035, CREAM, 8)

	# Tailplane (fixed part) and fin
	kit.box_at(Vector3(0, 0.12, 4.44), Vector3(3.3, 0.07, 0.78), CREAM)
	var fin_l := PackedVector3Array([Vector3(-0.035, 0.28, 3.95), Vector3(-0.035, 1.55, 4.72), Vector3(-0.035, 1.62, 5.05), Vector3(-0.035, 0.28, 5.05)])
	var fin_r := PackedVector3Array()
	for p in fin_l:
		fin_r.append(Vector3(0.035, p.y, p.z))
	kit.loft([fin_l, fin_r], CREAM, false, false)
	kit.quad(fin_l[0], fin_l[1], fin_l[2], fin_l[3], CREAM, Vector3.LEFT)
	kit.quad(fin_r[0], fin_r[1], fin_r[2], fin_r[3], CREAM, Vector3.RIGHT)
	kit.quad(Vector3(-0.037, 1.20, 4.52), Vector3(-0.037, 1.56, 4.74), Vector3(-0.037, 1.62, 5.04), Vector3(-0.037, 1.20, 5.04), ORANGE, Vector3.LEFT)
	kit.quad(Vector3(0.037, 1.20, 4.52), Vector3(0.037, 1.56, 4.74), Vector3(0.037, 1.62, 5.04), Vector3(0.037, 1.20, 5.04), ORANGE, Vector3.RIGHT)
	# Tailwheel spring
	_beam(kit, Vector3(0, 0.02, 4.72), Vector3(0, -0.18, 5.0), 0.03, METAL, 4)

	# The body is cut into small pieces so it can be dented where it hits.
	var dm := DentMesh.new()
	dm.name = "Body"
	dm.bend = _wing_bend
	dm.setup(kit, 0.26)
	_body = dm
	add_child(_body)
	var glass := glass_kit.instance("Glass")
	_glass = glass
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.albedo_color = Color(0.55, 0.66, 0.72, 0.16)
	gm.roughness = 0.04
	gm.metallic = 0.0
	gm.metallic_specular = 0.9
	gm.vertex_color_use_as_albedo = false
	glass.material_override = gm
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)

	# Registration on the tail cone
	for side in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = plane.reg if plane != null else "C-GKBP"
		_reg_labels.append(label)
		label.font_size = 96
		label.pixel_size = 0.0026
		label.modulate = BROWN
		label.outline_size = 0
		label.double_sided = false
		label.position = Vector3(side * 0.335, 0.26, 2.75)
		label.rotation = Vector3(0, side * (PI * 0.5 - 0.125), 0)
		add_child(label)


func _hinged_panel(node_name: String, hinge: Vector3, size: Vector3, col: Color, tilt: Basis = Basis.IDENTITY) -> Node3D:
	var pivot := Node3D.new()
	_surface_rest[node_name] = hinge
	pivot.name = node_name
	pivot.position = hinge
	pivot.basis = tilt
	# A tapered control surface: rounded at the hinge, thin at the trailing edge.
	var kit := MeshKit.new()
	var vertical := size.x < size.y
	var t := size.x if vertical else size.y
	var span := size.y if vertical else size.x
	var rings: Array = []
	for e in [-0.5, 0.5]:
		var ring := PackedVector3Array()
		var prof := [Vector2(0.0, 0.0), Vector2(t * 0.42, 0.03), Vector2(0.004, size.z), Vector2(-0.004, size.z), Vector2(-t * 0.42, 0.03)]
		for q in prof:
			var qq: Vector2 = q
			if vertical:
				ring.append(Vector3(qq.x, e * span, qq.y))
			else:
				ring.append(Vector3(e * span, qq.x, qq.y))
		rings.append(ring)
	kit.loft(rings, col, true, true)
	kit.smooth(35.0)
	pivot.add_child(kit.instance("Panel"))
	add_child(pivot)
	return pivot


func _build_moving_parts() -> void:
	# Trailing-edge surfaces hinge along the back of the wing.
	var tilt_l := Basis(Vector3.BACK, deg_to_rad(-1.6))
	var tilt_r := Basis(Vector3.BACK, deg_to_rad(1.6))
	# Main gear legs: drawn each frame from the fuselage to the wheel, so they
	# follow the springs, bend and fold.
	for side in [-1.0, 1.0]:
		var leg_kit := MeshKit.new()
		leg_kit.box_at(Vector3(0, -0.5, 0), Vector3(0.10, 1.0, 0.20), CREAM)
		var leg := leg_kit.instance("Leg")
		add_child(leg)
		_legs.append(leg)
	_flap_l = _hinged_panel("FlapL", Vector3(-1.75, 0.96 + 0.049, 0.78), Vector3(2.4, 0.10, 0.38), CREAM, tilt_l)
	_flap_r = _hinged_panel("FlapR", Vector3(1.75, 0.96 + 0.049, 0.78), Vector3(2.4, 0.10, 0.38), CREAM, tilt_r)
	_ail_l = _hinged_panel("AileronL", Vector3(-4.1, 0.96 + 0.115, 0.78), Vector3(2.2, 0.10, 0.38), CREAM, tilt_l)
	_ail_r = _hinged_panel("AileronR", Vector3(4.1, 0.96 + 0.115, 0.78), Vector3(2.2, 0.10, 0.38), CREAM, tilt_r)
	_elevator = _hinged_panel("Elevator", Vector3(0, 0.12, 4.83), Vector3(3.3, 0.06, 0.42), CREAM)
	_rudder = _hinged_panel("Rudder", Vector3(0, 0.80, 5.05), Vector3(0.06, 1.62, 0.45), CREAM)

	# Wheels: the mains are rebuilt whenever different tyres are fitted.
	for i in range(3):
		var pivot := Node3D.new()
		pivot.name = "Wheel%d" % i
		pivot.position = plane.hub_rest[i] if plane != null else Vector3.ZERO
		# Squash sits between the leg and the spinning tyre, so the tyre can bulge.
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
	_fit_tyres()

	_build_doors()
	_build_cowl()

	# Propeller
	_prop = Node3D.new()
	_prop.name = "Prop"
	_prop.position = Vector3(0, 0.05, -2.12)
	add_child(_prop)
	var hub_kit := MeshKit.new()
	hub_kit.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 0.06)), 0.15, 0.0, 0.34, 20, ORANGE, true)
	hub_kit.smooth(60.0)
	_prop.add_child(hub_kit.instance("Spinner"))
	_prop_blades = MeshInstance3D.new()
	_prop_blades.name = "Blades"
	_prop.add_child(_prop_blades)
	_build_blades(0)
	# A faint disc stands in for the blades once they are spinning fast.
	_prop_disc = MeshInstance3D.new()
	_prop_disc.name = "Disc"
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.01
	disc.radial_segments = 24
	disc.rings = 1
	_prop_disc.mesh = disc
	_prop_disc.rotation = Vector3(PI * 0.5, 0, 0)
	_prop_disc.position = Vector3(0, 0, -0.08)
	var disc_mat := StandardMaterial3D.new()
	_disc_mat = disc_mat
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.albedo_color = Color(0.15, 0.15, 0.15, 0.16)
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_prop_disc.material_override = disc_mat
	_prop_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop.add_child(_prop_disc)


## The cockpit view shows the cabin and thins out the prop disc.
func set_cockpit_view(enabled: bool) -> void:
	_interior_hidden = enabled
	if cockpit != null:
		cockpit.set_active(enabled)
	_disc_mat.albedo_color = Color(0.15, 0.15, 0.15, 0.05 if enabled else 0.16)


func _build_cockpit() -> void:
	cockpit = CockpitScript.new()
	cockpit.name = "Cockpit"
	add_child(cockpit)
	# Every plane has its cabin, not just the one you fly: open the door of
	# a parked or for-sale plane and the seats, panel and yokes are there.
	# (main.gd builds the flown plane's first and wires it up; this only
	# fills in the ones nobody built.)
	_fill_cockpit.call_deferred(cockpit)


func _fill_cockpit(c: Node3D) -> void:
	if is_instance_valid(c) and plane != null and plane.terrain != null:
		c.build(plane, plane.terrain)


## A rounded tyre with a hub: a loft of circles across the tread.
func _set_tyre_mesh(i: int, radius: float, width: float) -> void:
	var kit := MeshKit.new()
	var seg := 18 if radius > 0.2 else 12
	var profile := [[-0.50, 0.66], [-0.47, 0.86], [-0.36, 0.98], [-0.15, 1.0], [0.15, 1.0], [0.36, 0.98], [0.47, 0.86], [0.50, 0.66]]
	var rings: Array = []
	for pr in profile:
		var ring := PackedVector3Array()
		for k in range(seg):
			var a := TAU * float(k) / float(seg)
			ring.append(Vector3(float(pr[0]) * width, cos(a) * radius * float(pr[1]), sin(a) * radius * float(pr[1])))
		rings.append(ring)
	kit.loft(rings, TIRE, true, true)
	# Tread blocks on the bigger tyres
	if radius > 0.2:
		for k in range(seg * 2):
			var a := TAU * (float(k) + 0.5) / float(seg * 2)
			var d := Vector3(0, cos(a), sin(a))
			var blk := Transform3D(Basis(Vector3.RIGHT, a), d * (radius + 0.004))
			kit.box(blk, Vector3(width * (0.62 if k % 2 == 0 else 0.4), 0.012, radius * 0.11), Color(0.05, 0.05, 0.05))
	var hub := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(width * 0.5 + 0.012, 0, 0))
	kit.cylinder(hub, radius * 0.40, radius * 0.40, width + 0.024, 10, METAL, true)
	kit.smooth(50.0)
	var spinner: Node3D = _tyres[i].get_child(0)
	for c in spinner.get_children():
		c.queue_free()
	spinner.add_child(kit.instance("Tyre"))


func _fit_tyres() -> void:
	if plane == null:
		return
	_tyre_fitted = plane.tyre_kind
	var t: Dictionary = plane.tyre_spec()
	for i in range(2):
		_set_tyre_mesh(i, float(t["radius"]), float(t["width"]))
		_wheel_rest[i] = plane.hub_rest[i]


## Propeller blades for a damage state: 0 fine, 1 nicked, 2 bent, 3 wrecked.
## Bent blades curl back towards the cowl, as they do after a prop strike.
func _build_blades(state: int) -> void:
	_prop_state = state
	var curls := [[0.0, 0.0], [0.22, 0.0], [0.95, 0.35], [1.45, 1.15]]
	var tips := [[0.47, 0.47], [0.40, 0.47], [0.44, 0.47], [0.28, 0.36]]
	var kit := MeshKit.new()
	for k in range(2):
		var spin := Basis(Vector3.BACK, PI * float(k))
		var root := Transform3D(spin * Basis(Vector3.UP, 0.35), Vector3.ZERO)
		kit.box(root * Transform3D(Basis.IDENTITY, Vector3(0, 0.30, -0.08)), Vector3(0.15, 0.46, 0.025), DARK)
		var joint := root * Transform3D(Basis(Vector3.RIGHT, curls[state][k]), Vector3(0, 0.53, -0.08))
		var tip_len: float = tips[state][k]
		kit.box(joint * Transform3D(Basis.IDENTITY, Vector3(0, tip_len * 0.5, 0)), Vector3(0.15, tip_len, 0.025), DARK)
		if tip_len > 0.45:
			kit.box(joint * Transform3D(Basis.IDENTITY, Vector3(0, tip_len - 0.04, 0)), Vector3(0.14, 0.08, 0.03), Color(0.9, 0.8, 0.2))
	_prop_blades.mesh = kit.commit()


## Smoke from a sick engine and fuel mist from a leaking tank. The particles are
## left behind in the world, so they stream out behind the plane.
func _build_effects() -> void:
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.albedo_color = Color(1, 1, 1, 0.8)
	_smoke_mat.albedo_texture = Fx.puff_texture()
	_smoke = _particles(_smoke_mat, Color(0.20, 0.19, 0.18, 0.55), 56, 2.6, 0.55)
	_smoke.position = Vector3(0.34, -0.66, -1.30)
	_smoke.direction = Vector3(0.3, -0.4, 1.0)
	_smoke.gravity = Vector3(0, 0.7, 0)
	add_child(_smoke)
	var mist_mat := _smoke_mat.duplicate() as StandardMaterial3D
	mist_mat.albedo_color = Color(1, 1, 1, 1)
	for side in [-1.0, 1.0]:
		var m := _particles(mist_mat, Color(0.86, 0.89, 0.92, 0.16), 40, 1.0, 0.18)
		m.position = Vector3(side * 1.55, 0.86, 0.55)
		m.direction = Vector3(0, -1.0, 0.4)
		m.gravity = Vector3(0, -2.0, 0)
		add_child(m)
		_mist.append(m)


func _particles(mat: StandardMaterial3D, col: Color, count: int, life: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	p.mesh = quad
	p.amount = count
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.spread = 18.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.damping_min = 0.4
	p.damping_max = 0.8
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 2.6))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, col)
	ramp.set_color(1, Color(col, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## How far the skin moves when a wing is damaged: the outer panel sags.
func _wing_bend(p: Vector3) -> Vector3:
	return _wing_flex(p) + _crash_deform(p)


func _wing_flex(p: Vector3) -> Vector3:
	var ax := absf(p.x)
	if ax < 0.62:
		return Vector3.ZERO
	var side_i := 0 if p.x < 0.0 else 1
	if plane != null and plane.wing_off[side_i] and p.y > 0.55:
		var cut := 2.45 + 0.35 * DentMesh._hash(Vector3(0, snappedf(p.y, 0.05), snappedf(p.z, 0.08)))
		if ax > cut:
			var sgn := -1.0 if p.x < 0.0 else 1.0
			var torn := DentMesh._hash(p)
			return Vector3(sgn * (cut - ax) + sgn * torn * 0.12, (torn - 0.5) * 0.18, (DentMesh._hash(p * 1.7) - 0.5) * 0.1)
	var amt := _droop.x if p.x < 0.0 else _droop.y
	if absf(amt) < 0.002:
		return Vector3.ZERO
	return Vector3(0.0, -_bend_shape(ax, amt) * smoothstep(0.3, 0.85, p.y), 0.0)


## How far the wing sits below its line at span |x|. Flex in flight is a
## smooth bow; crash damage is a fold just outboard of the strut, the outer
## panel staying straight (not the tip curling - DESIGN_NOTES 155, Dave).
func _bend_shape(ax: float, amt: float) -> float:
	if plane != null and plane.is_crashed and amt > 0.0:
		var hinge := 2.9
		if ax <= hinge:
			var t0 := (ax - 0.6) / (hinge - 0.6)
			return amt * 0.12 * t0 * t0
		return amt * (0.12 + 0.88 * (ax - hinge) / (5.5 - hinge))
	var t := (ax - 0.6) / 4.9
	return amt * t * t


func _droop_at(x: float) -> float:
	var amt := _droop.x if x < 0.0 else _droop.y
	return _bend_shape(absf(x), amt)


func _on_dented(point: Vector3, push: Vector3, sev: float) -> void:
	_pending.append([0, point, push, sev])


func _on_scraped(point: Vector3, amount: float) -> void:
	for ev in _pending:
		if ev[0] == 1 and ev[1] == point:
			ev[2] += amount
			return
	_pending.append([1, point, amount])


func _on_repaired() -> void:
	_clear_crash_look()
	_pending.clear()
	(_body as DentMesh).clear_damage()
	_droop = Vector2.ZERO
	(_body as DentMesh).bend_active = false
	_shown_off = [false, false]
	if _fire != null:
		_fire.queue_free()
		_fire = null
	if debris != null:
		debris.clear()


# ------------------------------------------------------------------------------
#  Parts breaking away, fire and explosions
# ------------------------------------------------------------------------------
func _throw(mesh: Mesh, local_center: Vector3, extra_vel: Vector3, spin: float, size: float) -> void:
	if debris == null:
		return
	var xf: Transform3D = global_transform * Transform3D(Basis.IDENTITY, local_center)
	var v: Vector3 = plane.vel + global_transform.basis * extra_vel
	var w := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * spin
	debris.spawn(mesh, xf, v, w, size)


## The outer wing panel as a loose piece, centred on its own middle.
func _wing_piece(side: float) -> Array:
	var dih := tan(deg_to_rad(1.6))
	var c := Vector3(side * 3.9, 0.955 + 3.65 * dih, 0.2)
	var kit := MeshKit.new()
	var secs: Array = []
	for ax in [2.6, 3.6, 5.25]:
		var sec := _airfoil(side * ax, 0.955 + (ax - 0.25) * dih, -0.39, 1.17)
		var moved := PackedVector3Array()
		for q in sec:
			moved.append(q - c)
		secs.append(moved)
	if side < 0.0:
		secs.reverse()
	kit.loft(secs, CREAM, true, true)
	# Torn-off aileron and a stub of strut still attached
	kit.box_at(Vector3(side * 0.2, 0.05, 0.75), Vector3(2.2, 0.06, 0.36), CREAM)
	kit.box_at(Vector3(side * -1.2, -0.25, -0.2), Vector3(0.07, 0.6, 0.07), CREAM)
	kit.box_at(Vector3(side * 1.45, 0.08, 0.2), Vector3(0.25, 0.14, 1.1), ORANGE)
	kit.smooth(35.0)
	return [kit.commit(), c]


func _panel_piece(size: Vector3, col: Color) -> Mesh:
	var kit := MeshKit.new()
	kit.box_at(Vector3.ZERO, size, col)
	kit.box(Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(0, size.y * 0.5, size.z * 0.3)), size * Vector3(0.8, 0.3, 0.4), col.darkened(0.3))
	return kit.commit()


func _on_part_broken(part: String) -> void:
	if part == "wing_l" or part == "wing_r":
		var side := -1.0 if part == "wing_l" else 1.0
		var wp := _wing_piece(side)
		_throw(wp[0], wp[1], Vector3(side * 2.5, 2.0, 2.0), 2.5, 2.0)
		_pending.append([0, Vector3(side * 2.5, 0.97, 0.2), Vector3(0, -0.3, 1.0).normalized(), 1.5])


func _on_fire(_strength: float) -> void:
	if _fire != null:
		return
	# The fire starts where the fuel is: the engine, or a burst wing tank.
	_fire_point = Vector3(0, -0.1, -1.5)
	if plane.part("tank_l") < plane.part("tank_r") and plane.part("tank_l") < 0.8:
		_fire_point = Vector3(-1.4, 0.8, 0.3)
	elif plane.part("tank_r") < 0.8:
		_fire_point = Vector3(1.4, 0.8, 0.3)
	_fire = Fx.make_fire()
	_fire.position = _fire_point
	add_child(_fire)


func _on_exploded(strength: float) -> void:
	var boom := Fx.make_explosion(strength)
	var scene_root: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent().get_parent()
	scene_root.add_child(boom)
	boom.global_position = global_transform * Vector3(0, 0.3, -0.5)
	(_body as DentMesh).burn(Vector3(0, 0.2, -0.5), 3.5, 0.9)
	# Bits everywhere.
	# (Dave: a few bits, not a scatter - the wreck itself is the story)
	for i in range(3):
		var sz := Vector3(randf_range(0.2, 0.7), randf_range(0.03, 0.1), randf_range(0.2, 0.6))
		var col: Color = [CREAM, CREAM, ORANGE, METAL, DARK, BROWN][i % 6]
		var at := Vector3(randf_range(-1.2, 1.2), randf_range(-0.4, 0.9), randf_range(-2.0, 3.0))
		var out := (at + Vector3(0, 1.5, 0)).normalized() * randf_range(8.0, 22.0) * strength
		_throw(_panel_piece(sz, col), at, out, randf_range(4.0, 12.0), sz.length())
	for side in [-1.0, 1.0]:
		var wname := "wing_l" if side < 0.0 else "wing_r"
		var si := 0 if side < 0.0 else 1
		# at most one wing comes off: the other stays on, bent
		if not plane.wing_off[0] and not plane.wing_off[1] and randf() < 0.2 * strength:
			plane.wing_off[si] = true
			plane.hurt(wname, 1.0)
			var wp := _wing_piece(side)
			_throw(wp[0], wp[1], Vector3(side * 8.0, 9.0, 1.0) * strength, 3.0, 2.0)
	_glass.visible = false


func _update_fire(delta: float) -> void:
	if _fire == null:
		return
	_fire_t += delta
	var w := Vector3.ZERO
	if wind != null:
		w = wind.sample(global_position)
	Fx.set_fire_strength(_fire, float(plane.fire_strength), w, _fire_t)
	# The paint blisters and blackens, spreading out from the fire.
	_burn_wait -= delta
	if _burn_wait <= 0.0 and plane.fire_strength > 0.15:
		_burn_wait = 0.8
		(_body as DentMesh).burn(_fire_point, minf(1.2 + _fire_t * 0.12, 6.5), 0.12 * plane.fire_strength)
		(_body as DentMesh).mark_dirty()
	if not plane.on_fire and plane.fire_strength <= 0.0:
		_fire.queue_free()
		_fire = null


## Press waiting dents into the skin, a few times a second at most.
func _update_skin(delta: float) -> void:
	var body := _body as DentMesh
	# a crash bends them a good deal further than a hard landing (DESIGN_NOTES 155)
	var bend_k := 1.25 if plane.is_crashed else 0.9
	var target := Vector2(maxf(0.6 - plane.part("wing_l"), 0.0) * bend_k, maxf(0.6 - plane.part("wing_r"), 0.0) * bend_k)
	# Wing flex: in the air the wings carry the plane and bow up, more as the
	# g comes on (negative droop is up); a bump on the ground shakes them down.
	# Bending the wings means rebuilding the whole airframe mesh (~15 ms), so
	# it has just two shapes: resting on the gear, and bowed up in flight.
	# Following the g-load moment to moment rebuilt it ten times a second and
	# made the frame rate stutter (jitter log 2026-10-10).
	# (DESIGN_NOTES 186) airborne, not on_ground: on_ground flickers on every bounce
	# of a rough strip and each flip rebuilt the airframe (airborne has hysteresis).
	_flex = -0.045 if plane.airborne else 0.0
	target += Vector2(_flex, _flex)
	if target.distance_to(_droop) > 0.02 or plane.wing_off[0] != _shown_off[0] or plane.wing_off[1] != _shown_off[1]:
		_droop = target
		_shown_off = [plane.wing_off[0], plane.wing_off[1]]
		body.bend_active = absf(_droop.x) > 0.002 or absf(_droop.y) > 0.002 or plane.wing_off[0] or plane.wing_off[1]
		body.mark_dirty()
	_ail_l.visible = not plane.wing_off[0]
	_ail_r.visible = not plane.wing_off[1]
	_glass.visible = plane.part("fuselage") > 0.3
	_rebuild_wait -= delta
	if _rebuild_wait > 0.0 or (_pending.is_empty() and not body.is_dirty()):
		return
	for ev in _pending:
		if ev[0] == 0:
			var sev: float = ev[3]
			body.dent(ev[1], ev[2], clampf(0.07 + 0.30 * sev, 0.07, 0.95), 0.45 + 0.42 * minf(sev, 3.0))
		else:
			body.scrape(ev[1], ev[2], 0.45)
	var only_paint := true
	for ev in _pending:
		if ev[0] == 0:
			only_paint = false
	_pending.clear()
	body.rebuild()
	_rebuild_wait = 0.3 if only_paint else 0.1


func _process(delta: float) -> void:
	if plane == null:
		return
	_update_skin(delta)
	_update_fire(delta)
	var flap_angle: float = plane.flaps * deg_to_rad(40.0)
	var flap_bend: float = maxf(0.92 - plane.part("flaps"), 0.0) * 0.25
	for k in range(2):
		var side := -1.0 if k == 0 else 1.0
		var flap: Node3D = _flap_l if k == 0 else _flap_r
		var ail: Node3D = _ail_l if k == 0 else _ail_r
		var flap_rest: Vector3 = _surface_rest["FlapL" if k == 0 else "FlapR"]
		var ail_rest: Vector3 = _surface_rest["AileronL" if k == 0 else "AileronR"]
		# Follow a sagging wing.
		flap.position = flap_rest - Vector3(0, _droop_at(flap_rest.x), 0)
		ail.position = ail_rest - Vector3(0, _droop_at(ail_rest.x), 0)
		var amt := _droop.x if k == 0 else _droop.y
		var slope := 2.0 * amt * (absf(ail_rest.x) - 0.6) / 24.0
		flap.rotation = Vector3(flap_angle, 0, side * (deg_to_rad(1.6) - slope * 0.4) + flap_bend * side)
		# A damaged aileron moves less and hangs down; a jammed one stays put.
		var ah: float = plane.part("aileron_l" if k == 0 else "aileron_r")
		var travel := 0.0 if ah < 0.2 else lerpf(0.5, 1.0, clampf((ah - 0.2) / 0.55, 0.0, 1.0))
		var hang := maxf(0.75 - ah, 0.0) * 0.55
		ail.rotation = Vector3(-side * plane.aileron * deg_to_rad(17.0) * travel + hang, 0, side * (deg_to_rad(1.6) - slope))
	var eh: float = plane.part("elevator")
	_elevator.rotation = Vector3(-clampf(plane.elevator + plane.trim * 0.45, -1.0, 1.0) * deg_to_rad(24.0) * (0.4 + 0.6 * eh), 0, maxf(0.75 - eh, 0.0) * 0.25)
	var rh: float = plane.part("rudder")
	_rudder.rotation = Vector3(maxf(0.75 - rh, 0.0) * 0.2, plane.rudder * deg_to_rad(24.0) * (0.4 + 0.6 * rh) + maxf(0.75 - rh, 0.0) * 0.4, 0)

	# Wheels ride up as the gear compresses and turn with ground speed. Bent legs
	# sag and toe out, collapsed ones fold up, flat tyres squash.
	_update_doors(delta)
	if not _reg_labels.is_empty() and _reg_labels[0].text != plane.reg:
		for l in _reg_labels:
			l.text = plane.reg
	var amphib: bool = plane.is_amphib()
	if amphib and _floats == null:
		_floats = FloatVisual.new()
		_floats.name = "AmphibFloats"
		_floats.plane = plane
		add_child(_floats)
		_floats.build()
	if _floats != null:
		_floats.visible = amphib
	for wn in _wheels:
		wn.visible = not amphib
	for ln in _legs:
		ln.visible = not amphib
	if amphib:
		_floats.update(delta)
	if plane.tyre_kind != _tyre_fitted:
		_fit_tyres()
	_update_skis(delta)
	var vb: Vector3 = plane.vel * plane.b
	if plane.tail_castering and Vector2(vb.x, vb.z).length() > 0.3:
		_caster_angle = lerp_angle(_caster_angle, atan2(-vb.x, -vb.z), clampf(delta * 10.0, 0.0, 1.0))
	elif not plane.tail_castering:
		_caster_angle = lerp_angle(_caster_angle, plane.rudder * deg_to_rad(24.0), clampf(delta * 10.0, 0.0, 1.0))
	var tyre_w: float = plane.tyre_spec()["width"]
	for i in range(3):
		_wheel_spin[i] = fmod(_wheel_spin[i] + float(plane.wheel_spin_rate[i]) * delta, TAU)
		var side := -1.0 if i == 0 else 1.0
		var gh: float = plane.part(["gear_l", "gear_r", "tailwheel"][i])
		var th: float = plane.part("tire_l") if i == 0 else (plane.part("tire_r") if i == 1 else 1.0)
		var pos: Vector3 = _wheel_rest[i] + Vector3(0, plane.wheel_comp[i], 0)
		var rot := Vector3.ZERO
		if gh < 0.25:
			if i < 2:
				pos = _wheel_rest[i] + Vector3(-side * 0.30, 0.62, 0.35)
				rot = Vector3(0.4, 0.3 * side, side * 1.1)
			else:
				pos = _wheel_rest[i] + Vector3(0, 0.16, -0.25)
				rot = Vector3(0.6, 0, 0.3)
		elif gh < 0.75:
			var k := 0.75 - gh
			pos.y += (1.0 - gh) * 0.25
			if i < 2:
				rot = Vector3(0, k * 0.35 * (1.0 if i == 0 else -1.0), -side * k * 0.6)
		if i == 2 and gh >= 0.25:
			rot.y += _caster_angle
		# The tyre squashes flat at the bottom and bulges out at the sides.
		var r: float = plane.tyre_spec()["radius"] if i < 2 else 0.11
		var sq: float = clampf(float(plane.tyre_defl[i]) / r * 1.8, 0.0, 0.6) if gh >= 0.25 else 0.0
		if th < 0.4 and not plane.on_ground:
			sq = 0.25
		_tyres[i].scale = Vector3(1.0 + sq * 0.6, 1.0 - sq * 0.5, 1.0 + sq * 0.1)
		_tyres[i].position = Vector3(0, r * sq * 0.5, 0)
		_wheels[i].position = pos
		_wheels[i].rotation = rot
		_tyres[i].get_child(0).rotation.x = -_wheel_spin[i]
		if i < 2:
			var top: Vector3 = _leg_tops[i]
			var bottom: Vector3 = pos + Vector3(-side * (tyre_w * 0.5 + 0.04), 0, 0)
			var d := top - bottom
			var length := d.length()
			var y := d / length
			var x := y.cross(Vector3.FORWARD).normalized()
			var z := x.cross(y)
			_legs[i].transform = Transform3D(Basis(x, y * length, z), top)

	var rpm: float = plane.rpm
	_prop_angle = fposmod(_prop_angle + rpm / 60.0 * TAU * delta, TAU)
	_prop.rotation.z = -_prop_angle
	var ph: float = plane.part("prop")
	var state := 0 if ph > 0.92 else (1 if ph > 0.4 else (2 if ph > 0.05 else 3))
	if state != _prop_state:
		_build_blades(state)
	var fast := rpm > 500.0
	_prop_blades.visible = not fast
	_prop_disc.visible = fast

	# Smoke and leaks
	var e = plane.engine
	var smoke := 0.0
	if rpm > 250.0 and not plane.is_crashed:
		smoke = maxf(0.6 - float(e.health), 0.0) / 0.6 + float(e.roughness) * 0.4
		if e.oil_qts < 4.0:
			smoke += 0.5
	_smoke.emitting = smoke > 0.15
	_smoke_mat.albedo_color = Color(1, 1, 1, clampf(0.3 + smoke, 0.3, 1.0))
	_mist[0].emitting = plane.part("tank_l") < 0.85 and e.tank_left > 0.5
	_mist[1].emitting = plane.part("tank_r") < 0.85 and e.tank_right > 0.5
	_apply_crash_pose()



# ------------------------------------------------------------------------------
#  What a crash does to the airframe (DESIGN_NOTES 155), from photos of real
#  light-plane accidents: the fuselage buckles and breaks just aft of the
#  cabin, the tail cone twisting off at an angle; the engine is shoved back
#  and down into the firewall, the nose skewed to one side; the prop is
#  bent back; and the pieces that come off are real parts - a cowling
#  panel, a wheel, the door, a wingtip - thrown ahead along the line the
#  plane was travelling.
# ------------------------------------------------------------------------------
var _crash_k := 0.0
var _tail_basis := Basis.IDENTITY
var _nose_off := Vector3.ZERO
var TAIL_BREAK := Vector3(0.0, 0.15, 1.72)    # where the tail cone buckles (overridden per type)
var NOSE_FROM := -1.15                         # forward of this the engine bay crushes
var NOSE_TO := -2.1
var _prop_rest := Vector3.INF
var _thrown_wheels: Array = []


func _crash_deform(p: Vector3) -> Vector3:
	if _crash_k <= 0.0:
		return Vector3.ZERO
	var off := Vector3.ZERO
	var w := smoothstep(TAIL_BREAK.z, TAIL_BREAK.z + 0.12, p.z)
	if w > 0.0:
		var q := TAIL_BREAK + _tail_basis * (p - TAIL_BREAK)
		off += (q - p) * w
	if p.z < NOSE_FROM:
		off += _nose_off * smoothstep(NOSE_FROM, NOSE_TO, p.z)
	return off


func _on_crashed_look(_reason: String) -> void:
	var sev := clampf((float(plane.last_impact) - 8.0) / 24.0, 0.0, 1.0)
	if sev < 0.12:
		return
	_crash_k = sev
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var yaw := deg_to_rad(rng.randf_range(8.0, 24.0)) * sev * (1.0 if rng.randf() < 0.5 else -1.0)
	var pitch := -deg_to_rad(rng.randf_range(4.0, 14.0)) * sev
	var roll := deg_to_rad(rng.randf_range(-12.0, 12.0)) * sev
	_tail_basis = Basis.from_euler(Vector3(pitch, yaw, roll))
	_nose_off = Vector3(rng.randf_range(-0.14, 0.14), -0.16, 0.30) * sev
	var body := _body as DentMesh
	body.bend_active = true
	body.mark_dirty()
	_throw_parts(sev, rng)


## Real parts off the wreck, thrown on ahead (they keep the plane's speed).
func _throw_parts(sev: float, rng: RandomNumberGenerator) -> void:
	if debris == null:
		return
	var fwd := Vector3(0, 0, -1)
	var spots: Array = []
	# a cowling panel off the nose
	for side in _cowl_doors.keys():
		if rng.randf() < 0.35 + 0.5 * sev:
			var pv: Node3D = _cowl_doors[side][0]
			var mi: MeshInstance3D = pv.get_child(0) as MeshInstance3D
			if mi != null and pv.visible:
				pv.visible = false
				spots.append([mi.mesh, pv.position + _nose_off, fwd * 3.0 + Vector3(side * 2.0, 2.5, 0), 6.0, 0.8])
			break
	# a main wheel, if the leg let go
	for i in range(2):
		if plane.part(["gear_l", "gear_r"][i]) < 0.25 and rng.randf() < 0.6:
			var sp: Node3D = _tyres[i].get_child(0)
			if sp.get_child_count() > 0:
				var tm: MeshInstance3D = sp.get_child(0) as MeshInstance3D
				if tm != null and _wheels[i].visible:
					_wheels[i].visible = false
					_thrown_wheels.append(i)
					spots.append([tm.mesh, _wheels[i].position, fwd * 4.0 + Vector3((-1.0 if i == 0 else 1.0) * 1.5, 1.5, 0), 9.0, 0.5])
	# the cabin door bursts open and tears off
	if _doors.has("cabin") and sev > 0.5 and rng.randf() < 0.5:
		var dpv: Node3D = _doors["cabin"][0]
		var dmi: MeshInstance3D = dpv.get_child(0) as MeshInstance3D
		if dmi != null and dpv.visible:
			dpv.visible = false
			(_doors["cabin"][1] as Node3D).visible = true
			spots.append([dmi.mesh, dpv.position, Vector3(-3.0, 2.0, -2.0), 4.0, 0.9])
	# a bent prop blade if the prop broke up
	if plane.part("prop") < 0.06:
		var bk := MeshKit.new()
		bk.box(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 0.25, 0)), Vector3(0.15, 0.5, 0.025), DARK)
		bk.box_at(Vector3(0, 0.52, 0.12), Vector3(0.14, 0.08, 0.03), Color(0.9, 0.8, 0.2))
		spots.append([bk.commit(), _prop.position, fwd * 6.0 + Vector3(rng.randf_range(-3, 3), 3.0, 0), 14.0, 0.5])
	for s2 in spots:
		_throw(s2[0], s2[1], s2[2] * (0.6 + 0.6 * sev), float(s2[3]), float(s2[4]))


## Called every frame: keep the tail surfaces on the broken tail and the
## engine, cowls and prop with the crushed nose.
func _apply_crash_pose() -> void:
	if _crash_k <= 0.0:
		return
	for wi in _thrown_wheels:
		_wheels[wi].visible = false
	for nd in [_elevator, _rudder]:
		if nd == null:
			continue
		var rest: Vector3 = _surface_rest.get(String(nd.name), nd.position)
		nd.position = TAIL_BREAK + _tail_basis * (rest - TAIL_BREAK)
		nd.basis = _tail_basis * nd.basis
	if _prop_rest == Vector3.INF:
		_prop_rest = _prop.position
	_prop.position = _prop_rest + _nose_off
	var en := get_node_or_null("Engine")
	if en != null:
		en.position = _nose_off
	if engine_parts != null:
		engine_parts.position = _nose_off
	for side in _cowl_doors.keys():
		var d: Array = _cowl_doors[side]
		(d[0] as Node3D).position = (d[1] as Vector3) + _nose_off


func _clear_crash_look() -> void:
	_crash_k = 0.0
	_tail_basis = Basis.IDENTITY
	_nose_off = Vector3.ZERO
	if _prop_rest != Vector3.INF:
		_prop.position = _prop_rest
	var en := get_node_or_null("Engine")
	if en != null:
		en.position = Vector3.ZERO
	if engine_parts != null:
		engine_parts.position = Vector3.ZERO
	for side in _cowl_doors.keys():
		(_cowl_doors[side][0] as Node3D).visible = true
	_thrown_wheels.clear()
	for w in _wheels:
		w.visible = true
	if _doors.has("cabin"):
		(_doors["cabin"][0] as Node3D).visible = true


# ------------------------------------------------------------------------------
#  Doors: the pilot's cabin door (hinged at the front) and the baggage door
#  (hinged at the top), both on the left side. Open, they show the dark
#  doorway behind.
# ------------------------------------------------------------------------------
## The hull's half-width at station z, through the baggage-door bay
## (fuselage stations 1.10 and 1.65).
static func _hull_half_width(z: float) -> float:
	return lerpf(0.54, 0.46, clampf((z - 1.10) / 0.55, 0.0, 1.0))


func _build_doors() -> void:
	# [name, z front, z back, y bottom, y top, side x, hinge]
	var defs := [["cabin", DOOR_Z0, DOOR_Z1, DOOR_Y0, DOOR_Y1, -0.575, "front"], ["bay", BAY_Z0, BAY_Z1, -0.38, 0.12, -0.53, "top"]]
	for d in defs:
		var z0: float = d[1]
		var z1: float = d[2]
		var y0: float = d[3]
		var y1: float = d[4]
		var x: float = d[5]
		var pivot := Node3D.new()
		var kit := MeshKit.new()
		var hinge_at: Vector3
		if d[6] == "front":
			hinge_at = Vector3(x, (y0 + y1) * 0.5, z0)
		else:
			hinge_at = Vector3(x, y1, (z0 + z1) * 0.5)
		var c := Vector3(x, (y0 + y1) * 0.5, (z0 + z1) * 0.5) - hinge_at
		if d[0] == "bay":
			# The baggage door lies on the tapering hull: built to its slope
			# (not a flat slab, which stood proud of the skin at the back),
			# with its own piece of the paint stripe.
			var w0 := _hull_half_width(z0)
			var w1 := _hull_half_width(z1)
			hinge_at = Vector3(-(w0 + w1) * 0.5, y1, (z0 + z1) * 0.5)
			var o0 := Vector3(-(w0 + 0.006), 0, z0) - hinge_at
			var o1 := Vector3(-(w1 + 0.006), 0, z1) - hinge_at
			var i0 := Vector3(-(w0 - 0.014), 0, z0) - hinge_at
			var i1 := Vector3(-(w1 - 0.014), 0, z1) - hinge_at
			var yb := Vector3(0, y0, 0)
			var yt := Vector3(0, y1, 0)
			kit.quad(o0 + yt, o1 + yt, o1 + yb, o0 + yb, CREAM, Vector3.LEFT)
			kit.quad(i0 + yt, i0 + yb, i1 + yb, i1 + yt, CREAM.darkened(0.3), Vector3.RIGHT)
			kit.quad(o0 + yb, o1 + yb, i1 + yb, i0 + yb, CREAM.darkened(0.2), Vector3.DOWN)
			kit.quad(o0 + yb, i0 + yb, i0 + yt, o0 + yt, CREAM.darkened(0.2), Vector3.FORWARD)
			kit.quad(o1 + yt, i1 + yt, i1 + yb, o1 + yb, CREAM.darkened(0.2), Vector3.BACK)
			for q in _stripe_quads(_stripe_secs, 4, -1.0, z0 + 0.004, z1 - 0.004):
				kit.quad(q[0] - hinge_at, q[1] - hinge_at, q[2] - hinge_at, q[3] - hinge_at, q[4], q[5])
			var hm := (o0 + o1) * 0.5 + Vector3(-0.012, y0 + 0.23, 0)
			kit.box(Transform3D(Basis.IDENTITY, hm), Vector3(0.025, 0.025, 0.1), METAL)
			x = -(w0 + w1) * 0.5
		else:
			kit.box(Transform3D(Basis.IDENTITY, c), Vector3(0.025, y1 - y0, z1 - z0), CREAM)
		if d[0] == "cabin":
			# Window in the upper part, handle below it.
			kit.box(Transform3D(Basis.IDENTITY, c + Vector3(-0.014, 0.33, 0.0)), Vector3(0.004, 0.42, (z1 - z0) * 0.8), GLASS)
			# window frame and its piece of the paint stripe ride on the door
			kit.box(Transform3D(Basis.IDENTITY, c + Vector3(-0.016, 0.33 + 0.215, 0.0)), Vector3(0.012, 0.02, (z1 - z0) * 0.84), CREAM)
			kit.box(Transform3D(Basis.IDENTITY, c + Vector3(-0.016, 0.33 - 0.215, 0.0)), Vector3(0.012, 0.02, (z1 - z0) * 0.84), CREAM)
			for si in range(_stripe_secs.size() - 1):
				var sa: float = _stripe_secs[si][0]
				var sb: float = _stripe_secs[si + 1][0]
				var q0 := maxf(sa, z0 + 0.004)
				var q1 := minf(sb, z1 - 0.004)
				if q1 <= q0:
					continue
				for q in _stripe_quads(_stripe_secs, si, -1.0, q0, q1):
					var pts: Array = []
					for vi in range(4):
						var v: Vector3 = q[vi]
						v.x = x - 0.016
						pts.append(v - hinge_at)
					kit.quad(pts[0], pts[1], pts[2], pts[3], q[4], q[5])
			kit.box(Transform3D(Basis.IDENTITY, c + Vector3(-0.03, -0.05, (z1 - z0) * 0.35)), Vector3(0.03, 0.03, 0.12), METAL)
			# Inside face: a trim panel with an armrest, the inside handle,
			# a map pocket and a rubber seal round the edge.
			var trim := Color(0.30, 0.27, 0.23)
			kit.box(Transform3D(Basis.IDENTITY, c + Vector3(0.016, -0.22, 0.0)), Vector3(0.008, 0.70, (z1 - z0) * 0.9), trim)
			kit.box(Transform3D(Basis.IDENTITY, c + Vector3(0.05, -0.02, 0.04)), Vector3(0.06, 0.05, (z1 - z0) * 0.5), Color(0.16, 0.15, 0.14))
			kit.box(Transform3D(Basis.IDENTITY, c + Vector3(0.035, -0.04, (z1 - z0) * 0.36)), Vector3(0.03, 0.025, 0.10), METAL)
			kit.box(Transform3D(Basis.IDENTITY, c + Vector3(0.024, -0.40, -0.05)), Vector3(0.02, 0.16, (z1 - z0) * 0.55), Color(0.18, 0.17, 0.15))
			for e in [[Vector3(0, (y1 - y0) * 0.5, 0), Vector3(0.03, 0.02, z1 - z0)], [Vector3(0, -(y1 - y0) * 0.5, 0), Vector3(0.03, 0.02, z1 - z0)], [Vector3(0, 0, -(z1 - z0) * 0.5), Vector3(0.03, y1 - y0, 0.02)], [Vector3(0, 0, (z1 - z0) * 0.5), Vector3(0.03, y1 - y0, 0.02)]]:
				kit.box(Transform3D(Basis.IDENTITY, c + (e[0] as Vector3) + Vector3(0.012, 0, 0)), e[1], Color(0.06, 0.06, 0.06))
		pivot.position = hinge_at
		pivot.add_child(kit.instance("Door"))
		add_child(pivot)
		var ok := MeshKit.new()
		var ym := (y0 + y1) * 0.5
		var zm := (z0 + z1) * 0.5
		if d[0] == "cabin":
			# A see-through doorway: just its frame (sill, header, posts) in
			# the skin's thickness; the cabin is right there behind it.
			var fr := Color(0.12, 0.12, 0.12)
			ok.box(Transform3D(Basis.IDENTITY, Vector3(x + 0.03, y0 + 0.012, zm)), Vector3(0.07, 0.025, z1 - z0), METAL)       # sill plate
			ok.box(Transform3D(Basis.IDENTITY, Vector3(x + 0.03, y1 - 0.01, zm)), Vector3(0.07, 0.02, z1 - z0), fr)
			ok.box(Transform3D(Basis.IDENTITY, Vector3(x + 0.03, ym, z0 + 0.01)), Vector3(0.07, y1 - y0, 0.02), fr)
			ok.box(Transform3D(Basis.IDENTITY, Vector3(x + 0.03, ym, z1 - 0.01)), Vector3(0.07, y1 - y0, 0.02), fr)
		else:
			var hw0 := _hull_half_width(z0 + 0.01) - 0.002
			var hw1 := _hull_half_width(z1 - 0.01) - 0.002
			ok.quad(Vector3(-hw0, y1 - 0.01, z0 + 0.01), Vector3(-hw1, y1 - 0.01, z1 - 0.01), Vector3(-hw1, y0 + 0.01, z1 - 0.01), Vector3(-hw0, y0 + 0.01, z0 + 0.01), Color(0.05, 0.05, 0.055), Vector3.LEFT)
		var opening := ok.instance("Doorway")
		opening.visible = false
		add_child(opening)
		_doors[d[0]] = [pivot, opening, 0.0, d[6]]


# ------------------------------------------------------------------------------
#  Cowling: two side doors hinged along the top (they swing up, gull-wing) and
#  the engine underneath (engine_model.gd).
# ------------------------------------------------------------------------------
const EngineModel = preload("res://scripts/engine_model.gd")
var _cowl_q := {1.0: [], -1.0: []}
var _cowl_hinge := {}
var _cowl_doors := {}           # side -> [pivot, hinge point, axis]
var _cowl_open := 0.0


var engine_parts: Node3D       # the removable engine parts, named by id


func part_node(pid: String) -> Node3D:
	return engine_parts.get_node_or_null(NodePath(pid)) if engine_parts != null else null


func _build_cowl() -> void:
	var ek := MeshKit.new()
	EngineModel.build(ek)
	var em := ek.instance("Engine")
	add_child(em)
	engine_parts = Node3D.new()
	engine_parts.name = "EngineParts"
	add_child(engine_parts)
	EngineModel.build_removable(engine_parts)
	plane.set_meta("visual", self)
	for side in [1.0, -1.0]:
		var h: Array = _cowl_hinge.get(side, [])
		if h.is_empty():
			continue
		var a: Vector3 = h[0]
		var b: Vector3 = h[1]
		var mid := (a + b) * 0.5
		var kit := MeshKit.new()
		for q in _cowl_q[side]:
			kit.quad(q[0] - mid, q[1] - mid, q[2] - mid, q[3] - mid, q[4], q[5])
			# Inside face, bare and darker.
			if q[4] == CREAM:
				kit.quad(q[0] - mid, q[1] - mid, q[2] - mid, q[3] - mid, Color(0.45, 0.45, 0.43), -(q[5] as Vector3))
		# A latch at the bottom edge.
		var pivot := Node3D.new()
		pivot.name = "CowlDoor"
		pivot.position = mid
		pivot.add_child(kit.instance("Panel"))
		add_child(pivot)
		var axis := (b - a).normalized() * (1.0 if side > 0.0 else -1.0)
		_cowl_doors[side] = [pivot, mid, axis]


func _update_cowl(delta: float) -> void:
	var want := 1.0 if plane.door_open.get("cowl", false) else 0.0
	_cowl_open = move_toward(_cowl_open, want, delta * 0.9)
	var ang := smoothstep(0.0, 1.0, _cowl_open) * deg_to_rad(115.0)
	for side in _cowl_doors.keys():
		var d: Array = _cowl_doors[side]
		var pivot: Node3D = d[0]
		pivot.transform = Transform3D(Basis(d[2], ang), d[1])


func _update_doors(delta: float) -> void:
	_update_cowl(delta)
	for k in _doors.keys():
		var d: Array = _doors[k]
		var want := 1.0 if plane.door_open.get(k, false) else 0.0
		d[2] = move_toward(float(d[2]), want, delta * 1.6)
		var a: float = d[2]
		var pivot: Node3D = d[0]
		if d[3] == "front":
			pivot.rotation = Vector3(0, -a * 1.35, 0)
		else:
			pivot.rotation = Vector3(0, 0, -a * 1.5)
		(d[1] as Node3D).visible = a > 0.02



# ------------------------------------------------------------------------------
#  Wheel-skis: a ski under each wheel, lowered below the tyre or raised above it
# ------------------------------------------------------------------------------
var _skis: Array[Node3D] = []
var _ski_lift := 0.0


func _update_skis(delta: float) -> void:
	var on: bool = plane.has_skis() and not plane.is_amphib()
	if on and _skis.is_empty():
		for i in range(3):
			var main := i < 2
			var length := 1.7 if main else 0.75
			var width := 0.32 if main else 0.18
			var kit := MeshKit.new()
			var rings: Array = []
			# A flat board with its tip curled up.
			for k in range(7):
				var f := float(k) / 6.0
				var z := lerpf(length * 0.45, -length * 0.55, f)
				var y := 0.0 if f < 0.75 else pow((f - 0.75) / 0.25, 2.0) * 0.16
				var r := PackedVector3Array([Vector3(-width * 0.5, y, z), Vector3(width * 0.5, y, z), Vector3(width * 0.5, y + 0.04, z), Vector3(-width * 0.5, y + 0.04, z)])
				rings.append(r)
			kit.loft(rings, Color(0.75, 0.74, 0.70), true, true)
			kit.box_at(Vector3(0, 0.1, 0.0), Vector3(0.05, 0.2, 0.3), METAL)
			var ski := kit.instance("Ski")
			_wheels[i].add_child(ski)
			_skis.append(ski)
	for s in _skis:
		s.visible = on
	if not on:
		return
	var want := 0.0 if plane.gear_down else 0.16
	_ski_lift = move_toward(_ski_lift, want, delta * 0.08)
	for i in range(_skis.size()):
		var r: float = plane.tyre_spec()["radius"] if i < 2 else 0.11
		_skis[i].position = Vector3(0, -r - 0.05 + _ski_lift, 0)
