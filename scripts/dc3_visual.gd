extends Node3D
## A DC-3 in the same low-poly style as the Wolverine: bare
## aluminium, a red cheat line, two radial engines, tail-down on its wheels.
## First a look-only model (parked at the big strips) so the size and style can
## be approved; flying it comes after (DESIGN_NOTES 32, 36).
##
## Real sizes: span 29.0 m, length 19.7 m, height 5.2 m, wing area 92 m^2,
## main wheels 6.7 m apart under the nacelles, empty 8,200 kg, max 12,700 kg.
## Coordinates like plane.gd: -Z forward, Y up, origin at the wing's quarter
## chord on the centreline. Built level; tilt the node for the tail-down sit.

const MeshKit = preload("res://scripts/meshkit.gd")
const PlaneVisual = preload("res://scripts/plane_visual.gd")
const Shape = preload("res://scripts/dc3_shape.gd")
const Fx = preload("res://scripts/fx.gd")

const Liveries = preload("res://scripts/liveries.gd")

# Paint (set from the plane's livery before building; liveries.gd).
var METAL := Color(0.74, 0.75, 0.76)
var METAL_DK := Color(0.58, 0.59, 0.60)
var STRIPE := Color(0.62, 0.12, 0.10)
const BLACK := Color(0.08, 0.08, 0.09)
const GLASS := Color(0.16, 0.20, 0.24)
const TYRE := Color(0.10, 0.10, 0.10)

## Height of the wheels' contact points below the origin, and how far the
## tail sits down (radians), for parking it on the ground.
const MAIN_GROUND := -2.62
const SIT_PITCH := 0.17

var reg := "CF-TDJ"
## The engines out on the wing, the main gear centred under them (the
## 3.5 m props clear the fuselage by ~0.14 m).
const ENGINE_X := 3.35
var plane: Node3D                 # when flown: props turn with each engine's rpm
var _props: Array[Node3D] = []
var _prop_angle := [0.0, 0.0]
var debris: Node3D                # set by main: where broken-off pieces land
var wind: Node                    # set by main: drifts the fire and smoke
var _fire: Node3D
var _fire_t := 0.0
var _bent_props := false


## The cowling barrel between the lip and the firewall seam. Its sides are the
## two hinged service panels (real geometry: when they swing up, the engine
## shows); the narrow top strip and the flat bottom stay fixed.
const COWL_Z0 := -3.25
const COWL_Z1 := -2.35
const COWL_N := 14
const COWL_R0 := [0.86, 0.86, -0.05]        # hw, hh, cy at the front seam
const COWL_R1 := [0.845, 0.863, -0.0755]    # and at the firewall seam


## A point on the cowl section at ring index k (same 14-gon as the lofts,
## flattened bottom and all), in nacelle cross-section space (no x offset).
static func _cowl_pt(k: int, z: float, r: Array) -> Vector3:
	var a := TAU * float(posmod(k, COWL_N)) / float(COWL_N)
	var y := sin(a) * float(r[1])
	if y < -float(r[1]) * 0.85:
		y = -float(r[1]) * 0.85
	return Vector3(cos(a) * float(r[0]), float(r[2]) + y, z)


## Hinged side panels on the nacelle, swinging up from the top seam so you
## can get at the engine (the door key by a nacelle works them).
func _service_panels(ei: int) -> void:
	var x := Radial.nacelle_x(ei)
	var panels: Array = []
	# Left panel: ring segments 4..8 (hinge at edge 4, 103 deg). Right panel:
	# segments 12..16 wrapping through the front (hinge at edge 17 = 3, 77 deg).
	for pdef in [[-1.0, [4, 5, 6, 7, 8], 4], [1.0, [12, 13, 14, 15, 16], 17]]:
		var side: float = pdef[0]
		var hinge_k: int = pdef[2]
		var hp := _cowl_pt(hinge_k, (COWL_Z0 + COWL_Z1) * 0.5, COWL_R0)
		var pivot := Node3D.new()
		pivot.name = "SvcPanel%d%s" % [ei, "L" if side < 0.0 else "R"]
		pivot.position = Vector3(x + hp.x, hp.y, hp.z)
		pivot.set_meta("side", side)
		pivot.set_meta("open", 0.0)
		var pk := MeshKit.new()
		var axis := Vector3(x, -0.06, -2.8) - pivot.position
		for k in pdef[1]:
			var a0 := _cowl_pt(k, COWL_Z0, COWL_R0) + Vector3(x, 0, 0) - pivot.position
			var a1 := _cowl_pt(k + 1, COWL_Z0, COWL_R0) + Vector3(x, 0, 0) - pivot.position
			var b0 := _cowl_pt(k, COWL_Z1, COWL_R1) + Vector3(x, 0, 0) - pivot.position
			var b1 := _cowl_pt(k + 1, COWL_Z1, COWL_R1) + Vector3(x, 0, 0) - pivot.position
			var hint := (a0 + a1 + b0 + b1) * 0.25 - axis
			pk.quad(a0, a1, b1, b0, METAL.darkened(0.02), hint)
			# The underside, a shade darker, so the open panel has an inside.
			var inset := hint.normalized() * 0.03
			pk.quad(a0 - inset, b0 - inset, b1 - inset, a1 - inset, METAL.darkened(0.35), -hint)
		pivot.add_child(pk.instance("Panel"))
		add_child(pivot)
		panels.append(pivot)
	_svc_panels[ei] = panels


func part_node(pid: String) -> Node3D:
	return engine_parts.get_node_or_null(NodePath(pid)) if engine_parts != null else null


func _apply_livery() -> void:
	if plane == null:
		return
	var lv: Array = Liveries.for_plane(plane)
	METAL = lv[1]
	METAL_DK = (lv[1] as Color).darkened(0.21)
	STRIPE = lv[2]


## Strip everything this visual built (not what main hung on it, meta "ext")
## and build it again in the plane's current paint.
func repaint() -> void:
	_apply_livery()
	for c in get_children():
		if c.has_meta("ext"):
			continue
		remove_child(c)
		c.queue_free()
	_props.clear()
	_prop_angle = [0.0, 0.0]
	gear_nodes.clear()
	engine_parts = null
	_svc_panels.clear()
	door_leaves.clear()
	_door_shown = -1.0
	build()


func _ready() -> void:
	_apply_livery()
	build()
	if plane != null:
		plane.fire_started.connect(_on_fire)
		plane.exploded.connect(_on_exploded)
		plane.crashed.connect(_on_crashed_visual)


## Fire where the fuel is: the worse wing tank's nacelle, or the belly.
func _on_fire(_strength: float) -> void:
	if _fire != null:
		return
	var at := Vector3(0, -1.2, -1.0)
	if plane.part("tank_l") < plane.part("tank_r") and plane.part("tank_l") < 0.9:
		at = Vector3(-ENGINE_X, -0.4, -2.0)
	elif plane.part("tank_r") < 0.9:
		at = Vector3(ENGINE_X, -0.4, -2.0)
	_fire = Fx.make_fire()
	_fire.position = at
	_fire.scale = Vector3.ONE * 1.8        # a big aeroplane burns big
	add_child(_fire)


## It went up: a blast, a rain of aluminium, the props bent back.
func _on_exploded(strength: float) -> void:
	var boom := Fx.make_explosion(strength * 1.4)
	var scene_root: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	scene_root.add_child(boom)
	boom.global_position = global_transform * Vector3(0, 0, -1.0)
	if debris != null and plane != null:
		for i in range(22):
			var sz := Vector3(randf_range(0.5, 1.8), randf_range(0.04, 0.15), randf_range(0.4, 1.4))
			var col: Color = [METAL, METAL, METAL_DK, STRIPE, BLACK][i % 5]
			var kit := MeshKit.new()
			kit.box_at(Vector3.ZERO, sz, col)
			var at := Vector3(randf_range(-4.0, 4.0), randf_range(-1.5, 1.5), randf_range(-5.0, 7.0))
			var out := (at + Vector3(0, 2.5, 0)).normalized() * randf_range(9.0, 26.0) * strength
			var xf: Transform3D = global_transform * Transform3D(Basis.IDENTITY, at)
			debris.spawn(kit.commit(), xf, plane.vel + global_transform.basis * out,
				Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(4.0, 12.0), sz.length())
	_bend_props()


## A wreck on the ground: bent blades, even without a fireball.
func _on_crashed_visual(_reason: String) -> void:
	_bend_props()


func _bend_props() -> void:
	if _bent_props:
		return
	_bent_props = true
	# One baked mesh per prop: fold the whole disc back against the nacelle.
	for pr in _props:
		pr.scale = Vector3(0.96, 0.96, 0.4)
		pr.rotation.x = randf_range(-0.3, 0.3)


func _process(delta: float) -> void:
	if plane == null or not is_visible_in_tree():
		return
	for ei2 in _svc_panels.keys():
		var want := 1.0 if plane.door_open.get("cowl%d" % int(ei2), false) else 0.0
		for pv in _svc_panels[ei2]:
			var n3 := pv as Node3D
			var cur: float = n3.get_meta("open", 0.0)
			cur = move_toward(cur, want, delta * 1.6)
			n3.set_meta("open", cur)
			n3.rotation.z = (1.5 if float(n3.get_meta("side", 1.0)) > 0.0 else -1.5) * cur
	for gn in gear_nodes:
		# Eased, so it starts gently off the locks and settles into the well.
		var gp := smoothstep(0.0, 1.0, 1.0 - float(plane.gear_pos))
		gn.rotation.x = deg_to_rad(GEAR_SWING) * gp
	if _fire != null:
		_fire_t += delta
		var wnd := Vector3.ZERO
		if wind != null:
			wnd = wind.sample(global_position)
		Fx.set_fire_strength(_fire, float(plane.fire_strength), wnd, _fire_t)
		if not plane.on_fire and float(plane.fire_strength) <= 0.0:
			_fire.queue_free()
			_fire = null
	if _bent_props:
		return
	var es: Array = plane.engines()
	for i in range(_props.size()):
		var e = es[mini(i, es.size() - 1)]
		var rpm: float = float(e.rpm) if (e.running or float(e.rpm) > 50.0) else 0.0
		if plane.feathered[mini(i, 1)] and not e.running:
			rpm = 0.0
		_prop_angle[i] = fmod(float(_prop_angle[i]) + rpm / 60.0 * TAU * delta * (1.0 if i == 0 else -1.0), TAU)
		# Fast blades are shown slowed down, like a camera sees them.
		var shown: float = _prop_angle[i] if rpm < 600.0 else fmod(float(_prop_angle[i]) * 0.031, TAU)
		_props[i].rotation = Vector3(0, 0, shown)


## Park it with its wheels on the ground at `at` (ground point under the
## main wheels), nose toward `yaw`.
func park(at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, SIT_PITCH)
	var contact := Basis(Vector3.RIGHT, SIT_PITCH) * Vector3(0, MAIN_GROUND, -0.85)
	global_transform = Transform3D(b, at - Basis(Vector3.UP, yaw) * contact)


func build() -> void:
	var kit := MeshKit.new()
	_fuselage(kit)
	_wing(kit)
	_tail(kit)
	for side in [-1.0, 1.0]:
		_nacelle(kit, side)
	_tailwheel(kit)
	var mi := kit.instance("DC3")
	add_child(mi)
	# Propellers: three blades each, separate so they can turn later.
	for side in [-1.0, 1.0]:
		var pk := MeshKit.new()
		for b in range(3):
			var a := TAU * float(b) / 3.0 + 0.3
			var blade := Transform3D(Basis(Vector3.BACK, a), Vector3.ZERO)
			pk.box(blade * Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0)), Vector3(0.24, 1.75, 0.05), BLACK)     # the full 3.5 m disc
			pk.box(blade * Transform3D(Basis.IDENTITY, Vector3(0, 1.68, 0)), Vector3(0.244, 0.19, 0.054), Color(0.95, 0.95, 0.93))   # white tips
		pk.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.05)), 0.32, 0.05, 0.55, 10, METAL)
		var pm := pk.instance("Prop")
		pm.position = Vector3(side * ENGINE_X, -0.05, -3.55)
		add_child(pm)
		_props.append(pm)
	for side in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = reg
		l.font_size = 96
		l.pixel_size = 0.006
		# dark letters on a light skin, light ones on a dark skin
		l.modulate = BLACK if METAL.get_luminance() > 0.4 else Color(0.93, 0.93, 0.9)
		l.outline_size = 0
		l.double_sided = false
		# The tail cone tapers under the letters: stand them off the skin at
		# the wide (front) end and turn them to follow the taper, so the
		# front letters don't sink into it.
		var zc := 6.6
		var w0: float = Shape.inner_half_width(zc - 0.95, 0.35)
		var w1: float = Shape.inner_half_width(zc + 0.95, 0.35)
		var yaw := atan2(w0 - w1, 1.9)
		l.transform = Transform3D(Basis(Vector3.UP, side * (PI * 0.5 - yaw)), Vector3(side * ((w0 + w1) * 0.5 + 0.1), 0.35, zc))
		add_child(l)


## Fuselage: round sections, a blunt nose with a stepped windscreen, a long
## tapering tail cone that sweeps up to the fin.
func _fuselage(kit: MeshKit) -> void:
	# z, half width, half height, centre y
	var st: Array = Shape.ST
	# The skin from the shared shape (dc3_shape.gd): fine steps round the nose
	# and windscreen, coarse along the cabin and tail.
	var gk := MeshKit.new()
	var zs: Array[float] = []
	var z := -7.70
	while z < 12.0:
		zs.append(z)
		z += 0.04 if z < -5.3 else 0.5
	for wz in [Shape.SIDE_WIN[0], Shape.SIDE_WIN[1]]:
		zs.append(wz)
	for hz in Shape.hole_breaks():
		zs.append(hz)
	zs.append(12.0)
	zs.sort()
	var nr := Shape.ring_size()
	for zi in range(zs.size() - 1):
		var r0: PackedFloat32Array = Shape.ring_angles(zs[zi])
		var r1: PackedFloat32Array = Shape.ring_angles(zs[zi + 1])
		var zmid := (zs[zi] + zs[zi + 1]) * 0.5
		for k in range(nr):
			var k1 := (k + 1) % nr
			var p00: Vector3 = Shape.point(r0[k], zs[zi])
			var p01: Vector3 = Shape.point(r0[k1] if k1 > 0 else r0[0] + TAU, zs[zi])
			var p10: Vector3 = Shape.point(r1[k], zs[zi + 1])
			var p11: Vector3 = Shape.point(r1[k1] if k1 > 0 else r1[0] + TAU, zs[zi + 1])
			var mid := (p00 + p01 + p10 + p11) * 0.25
			var axis: Vector3 = Shape.section(mid.z)[3] * Vector3.UP + Vector3(0, 0, mid.z)
			var out := mid - axis
			var glass := (Shape.sector_of(k) == "win" and Shape.in_side_window_z(zmid)) or (zmid < -6.3 and Shape.is_glass(mid))
			if glass:
				gk.quad(p00, p01, p11, p10, Color(1, 1, 1), out)
			else:
				Shape.skin_quad(kit, zs[zi], zs[zi + 1], r0[k], r0[k1] if k1 > 0 else r0[0] + TAU,
					r1[k], r1[k1] if k1 > 0 else r1[0] + TAU, 0.0, METAL, true)
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.06, 0.08, 0.09, 0.55)
	gm.roughness = 0.04
	gm.metallic_specular = 1.0
	gm.cull_mode = BaseMaterial3D.CULL_BACK
	for side in [-1.0, 1.0]:
		Shape.pane_frame(kit, side, 0.012, 0.09, METAL_DK, true)
	var gi := gk.instance("CockpitGlass")
	gi.material_override = gm
	add_child(gi)
	# Cheat line along both sides, cabin windows above it, all laid on the skin.
	for side in [-1.0, 1.0]:
		# On the left the cargo door cuts the line: the leaves carry their own
		# piece of it (see _cargo_door) so it swings away with them.
		if side < 0.0:
			_cheat_line(kit, side, -7.2, DOOR_Z[0], 0.006)
			_cheat_line(kit, side, DOOR_Z[1], 9.6, 0.006)
		else:
			_cheat_line(kit, side, -7.2, 9.6, 0.006)
		# Cabin windows: real holes in the skin (see dc3_shape) with glass in
		# them and a thin frame round each.
		for wz in Shape.window_zs(side):
			var z0: float = wz - Shape.WIN_HALF
			var z1: float = wz + Shape.WIN_HALF
			_skin_patch(gk, side, z0, z1, Shape.WIN_A[0], Shape.WIN_A[1], Color(1, 1, 1), -0.01)
			_skin_patch(kit, side, z0 - 0.025, z1 + 0.025, Shape.WIN_A[1], Shape.WIN_A[1] + 0.018, METAL_DK, 0.004)
			_skin_patch(kit, side, z0 - 0.025, z1 + 0.025, Shape.WIN_A[0] - 0.018, Shape.WIN_A[0], METAL_DK, 0.004)
			_skin_patch(kit, side, z0 - 0.025, z0, Shape.WIN_A[0], Shape.WIN_A[1], METAL_DK, 0.004)
			_skin_patch(kit, side, z1, z1 + 0.025, Shape.WIN_A[0], Shape.WIN_A[1], METAL_DK, 0.004)
	_cargo_door(kit)


## The painted cheat line (and its thin pinstripe above) between z0 and z1.
func _cheat_line(kit: MeshKit, side: float, z0: float, z1: float, lift: float) -> void:
	_skin_patch(kit, side, z0, z1, -0.10, 0.03, STRIPE, lift)
	_skin_patch(kit, side, maxf(z0, -7.0), z1, 0.045, 0.065, STRIPE.darkened(0.25), lift)


## A patch lying on the skin: between stations z0..z1 and angles a0..a1
## round the section (0 = level with the centre, + up), on one side.
func _skin_patch(kit: MeshKit, side: float, z0: float, z1: float, a0: float, a1: float, col: Color, lift: float) -> void:
	var nz := maxi(2, int((z1 - z0) / 0.25))
	var na := 3
	for i in range(nz):
		for j in range(na):
			var za := lerpf(z0, z1, float(i) / float(nz))
			var zb := lerpf(z0, z1, float(i + 1) / float(nz))
			var aa := lerpf(a0, a1, float(j) / float(na))
			var ab := lerpf(a0, a1, float(j + 1) / float(na))
			var ang := func(a: float) -> float: return a if side > 0.0 else PI - a
			var p00: Vector3 = Shape.point(ang.call(aa), za, -lift)
			var p01: Vector3 = Shape.point(ang.call(ab), za, -lift)
			var p10: Vector3 = Shape.point(ang.call(aa), zb, -lift)
			var p11: Vector3 = Shape.point(ang.call(ab), zb, -lift)
			kit.quad(p00, p10, p11, p01, col, Vector3(side, 0, 0))


## The big double cargo door on the left side aft: two leaves on
## hinges (the front one hinged at its front edge, the back one at its back
## edge) that swing out against the fuselage. Seams drawn round them.
const DOOR_Z := Shape.DOOR_Z
const DOOR_A := Shape.DOOR_A        # angles round the section: floor to top
var gear_nodes: Array[Node3D] = []     # main gear legs, folding forward into the nacelles
var engine_parts: Node3D               # removable engine parts, named e0_/e1_...
var _svc_panels := {}                  # engine index -> [left panel pivot, right panel pivot]
const Radial = preload("res://scripts/engine_model_radial.gd")
const GEAR_SWING := 85.0              # degrees the legs swing up (half the tyre left out)
var door_leaves: Array[Node3D] = []
var door_open := 0.0                # 0 shut .. 1 wide open
var _door_shown := -1.0

func _cargo_door(kit: MeshKit) -> void:
	var side := -1.0
	var zm: float = (DOOR_Z[0] + DOOR_Z[1]) * 0.5
	# Dark seam round the opening and between the leaves.
	_skin_patch(kit, side, DOOR_Z[0] - 0.04, DOOR_Z[1] + 0.04, DOOR_A[1], DOOR_A[1] + 0.03, BLACK, 0.004)
	_skin_patch(kit, side, DOOR_Z[0] - 0.04, DOOR_Z[1] + 0.04, DOOR_A[0] - 0.03, DOOR_A[0], BLACK, 0.004)
	_skin_patch(kit, side, DOOR_Z[0] - 0.04, DOOR_Z[0], DOOR_A[0], DOOR_A[1], BLACK, 0.004)
	_skin_patch(kit, side, DOOR_Z[1], DOOR_Z[1] + 0.04, DOOR_A[0], DOOR_A[1], BLACK, 0.004)
	for li in range(2):
		var z0: float = DOOR_Z[0] if li == 0 else zm + 0.01
		var z1: float = zm - 0.01 if li == 0 else DOOR_Z[1]
		var hinge_z: float = DOOR_Z[0] if li == 0 else DOOR_Z[1]
		var hinge: Vector3 = Shape.point(PI, hinge_z, -0.01)
		var pivot := Node3D.new()
		pivot.name = "CargoDoor%d" % li
		pivot.position = Vector3(hinge.x, 0, hinge_z)
		add_child(pivot)
		var dk := MeshKit.new()
		var tmp := MeshKit.new()
		_skin_patch(tmp, side, z0, z1, DOOR_A[0], DOOR_A[1], METAL.darkened(0.05), 0.012)
		_cheat_line(tmp, side, z0, z1, 0.018)       # the leaf's piece of the cheat line
		if li == 0:
			# a dark lip on the front leaf covers the gap between the leaves
			_skin_patch(tmp, side, zm - 0.02, zm + 0.02, DOOR_A[0], DOOR_A[1], BLACK, 0.021)
		# The inside of the leaf (seen from the cabin, or when it's swung open).
		_skin_patch(tmp, -side, z0, z1, PI - DOOR_A[1], PI - DOOR_A[0], Color(0.45, 0.50, 0.45), -0.05)
		# Move the leaf into the pivot's space.
		for vi in range(tmp.verts.size()):
			tmp.verts[vi] = tmp.verts[vi] - pivot.position
		dk.verts = tmp.verts
		dk.norms = tmp.norms
		dk.cols = tmp.cols
		# Handle
		var hz: float = (z1 - 0.15) if li == 0 else (z0 + 0.15)
		var hp: Vector3 = Shape.point(PI, hz, -0.03) - pivot.position
		dk.box_at(hp, Vector3(0.03, 0.05, 0.16), BLACK)
		var mi := dk.instance("Leaf")
		pivot.add_child(mi)
		door_leaves.append(pivot)


## Swing the cargo door leaves to `door_open` (called every frame by the owner).
func update_door(delta: float, want_open: bool) -> void:
	door_open = move_toward(door_open, 1.0 if want_open else 0.0, delta / 2.5)
	if absf(door_open - _door_shown) < 0.001:
		return
	_door_shown = door_open
	var swing := smoothstep(0.0, 1.0, door_open) * deg_to_rad(165.0)
	if door_leaves.size() == 2:
		door_leaves[0].rotation.y = -swing       # front leaf swings out and forward
		door_leaves[1].rotation.y = swing        # back leaf swings out and aft


func _ring(z: float, hw: float, hh: float, cy: float, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in range(n):
		var a := TAU * float(k) / float(n)
		# A little flat on the bottom like the real cabin floor.
		var y := sin(a) * hh
		if y < -hh * 0.85:
			y = -hh * 0.85
		out.append(Vector3(cos(a) * hw, cy + y, z))
	return out


## Low wing: a straight-tapered centre section with the nacelles, swept-back
## outer panels with dihedral, rounded tips; flaps and ailerons marked.
func _wing(kit: MeshKit) -> void:
	var y0 := -1.05
	# Centre section, through the fuselage to the outer joint (x = 4.9).
	var root_c := 4.35
	var join_c := 3.75
	var secs: Array = []
	# Inside the fuselage the spar box runs under the cabin floor: there the
	# section is cut flat just below the floor so it doesn't show in the cabin.
	for x in [-4.9, -1.3, -1.24, 1.24, 1.3, 4.9]:
		var c := root_c if absf(x) < 2.0 else join_c
		var le := -0.25 * c
		var sec := PlaneVisual._airfoil(x, y0, le, c, 1.25)
		if absf(x) < 1.25:
			for i in range(sec.size()):
				sec[i].y = minf(sec[i].y, Shape.cabin_floor(0.0) - 0.03)
		secs.append(sec)
	kit.loft(secs, METAL, true, true)
	for side in [-1.0, 1.0]:
		var outer: Array = []
		var n := 6
		for i in range(n + 1):
			var f := float(i) / float(n)
			var x: float = side * lerpf(4.9, 14.3, f)
			var c := lerpf(join_c, 1.45, f)
			# The leading edge sweeps back; the trailing edge is nearly straight.
			var le := -0.25 * join_c + 1.75 * f
			var y := y0 + 9.4 * f * tan(deg_to_rad(5.0))
			var sc := 1.0 if i < n else 0.6
			outer.append(PlaneVisual._airfoil(x, y, le, c, sc * lerpf(1.25, 0.9, f)))
		var tip_x: float = side * 14.5
		outer.append(PlaneVisual._airfoil(tip_x, y0 + 9.6 * tan(deg_to_rad(5.0)), 0.75, 1.0, 0.3))
		kit.loft(outer, METAL, false, true)
		# Aileron and flap hinge lines (dark strips on the upper surface).
		for f in [0.45, 0.98]:
			var ff: float = f
			var x2: float = side * lerpf(4.9, 14.3, ff)
			var c2: float = lerpf(join_c, 1.45, ff)
			var le2: float = -0.25 * join_c + 1.75 * ff
			kit.box(Transform3D(Basis.IDENTITY, Vector3(x2, y0 + 9.4 * ff * tan(deg_to_rad(5.0)) + 0.12 * c2, le2 + c2 * 0.74)), Vector3(0.05, 0.02, c2 * 0.25), METAL_DK)


func _tail(kit: MeshKit) -> void:
	# Tailplane
	var ty := 1.0
	for side in [-1.0, 1.0]:
		var secs: Array = []
		for i in range(4):
			var f := float(i) / 3.0
			var x: float = side * lerpf(0.0, 4.35, f)
			var c := lerpf(2.6, 1.0, f)
			secs.append(PlaneVisual._airfoil(x, ty, 9.9 + 0.9 * f, c, 0.9))
		kit.loft(secs, METAL, true, true)
	# Fin: symmetric aerofoil sections from the fuselage to a rounded top,
	# with a dorsal fillet running forward, and the rudder hinge line.
	var fin: Array = []
	var fs := [[0.85, 7.6, 4.6, 0.10], [1.25, 8.6, 3.9, 0.12], [2.2, 9.6, 2.95, 0.12], [3.3, 10.2, 2.25, 0.10],
		[4.1, 10.55, 1.7, 0.08], [4.45, 10.85, 1.15, 0.06], [4.6, 11.1, 0.6, 0.04]]
	for f in fs:
		fin.append(_fin_section(f[0], f[1], f[2], f[3]))
	kit.loft(fin, METAL, false, true)
	kit.box(Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 2.6, 11.62)), Vector3(0.11, 3.4, 0.02), METAL_DK)
	# A red band on the fin.
	for side in [-1.0, 1.0]:
		_fin_band(kit, side, 3.2, 3.6, STRIPE)


## A thin symmetric aerofoil lying fore-and-aft at height y (for the fin).
func _fin_section(y: float, le: float, c: float, t: float) -> PackedVector3Array:
	var xs := [1.0, 0.8, 0.6, 0.4, 0.25, 0.12, 0.05, 0.0]
	var yt := [0.002, 0.03, 0.045, 0.05, 0.046, 0.036, 0.024, 0.0]
	var out := PackedVector3Array()
	for k in range(xs.size()):
		out.append(Vector3(float(yt[k]) / 0.05 * t * 0.5, y, le + float(xs[k]) * c))
	for k in range(xs.size() - 2, 0, -1):
		out.append(Vector3(-float(yt[k]) / 0.05 * t * 0.5, y, le + float(xs[k]) * c))
	return out


func _fin_band(kit: MeshKit, side: float, y0: float, y1: float, col: Color) -> void:
	var a := _fin_section(y0, lerpf(10.2, 10.55, (y0 - 3.3) / 0.8), lerpf(2.25, 1.7, (y0 - 3.3) / 0.8), 0.10)
	var b := _fin_section(y1, lerpf(10.2, 10.55, (y1 - 3.3) / 0.8), lerpf(2.25, 1.7, (y1 - 3.3) / 0.8), 0.09)
	var n := a.size() / 2
	for k in range(n):
		var i0 := k if side > 0.0 else a.size() - k - 1
		var i1 := (k + 1) if side > 0.0 else a.size() - k - 2
		if i1 < 0 or i1 >= a.size():
			continue
		var o := Vector3(side * 0.006, 0, 0)
		kit.quad(a[i0] + o, a[i1] + o, b[i1] + o, b[i0] + o, col, Vector3(side, 0, 0))


func _nacelle(kit: MeshKit, side: float) -> void:
	var x := side * ENGINE_X
	# The nacelle aft of the cowling (the firewall seam back to the tail cone).
	var st := [
		[COWL_Z1, COWL_R1[0], COWL_R1[1], COWL_R1[2]],
		[-1.5, 0.76, 0.88, -0.22], [0.0, 0.62, 0.80, -0.48], [1.6, 0.36, 0.40, -0.78], [2.6, 0.06, 0.08, -0.9],
	]
	var rings: Array = []
	for s in st:
		var r := _ring(s[0], s[1], s[2], s[3], 14)
		for k in range(r.size()):
			r[k] = r[k] + Vector3(x, 0, 0)
		rings.append(r)
	kit.loft(rings, METAL, false, true)
	# The cowling's nose: lip ring up to the front panel seam.
	var r_nose := _ring(-3.45, 0.62, 0.62, -0.05, 14)
	var r_seam := _ring(COWL_Z0, COWL_R0[0], COWL_R0[1], COWL_R0[2], 14)
	for k in range(14):
		r_nose[k] = r_nose[k] + Vector3(x, 0, 0)
		r_seam[k] = r_seam[k] + Vector3(x, 0, 0)
	kit.loft([r_nose, r_seam], METAL, false, false)
	# Between the seams: the narrow fixed strip on top and the flat belly;
	# the sides are the hinged service panels (_service_panels).
	for k in [3, 9, 10, 11]:
		var a0 := _cowl_pt(k, COWL_Z0, COWL_R0) + Vector3(x, 0, 0)
		var a1 := _cowl_pt(k + 1, COWL_Z0, COWL_R0) + Vector3(x, 0, 0)
		var b0 := _cowl_pt(k, COWL_Z1, COWL_R1) + Vector3(x, 0, 0)
		var b1 := _cowl_pt(k + 1, COWL_Z1, COWL_R1) + Vector3(x, 0, 0)
		var mid := (a0 + a1 + b0 + b1) * 0.25
		kit.quad(a0, a1, b1, b0, METAL, mid - Vector3(x, -0.06, mid.z))
	# A dark wall deep in the nacelle, so the open bay has a back.
	kit.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x, -0.08, -1.95)), 0.76, 0.76, 0.03, 14, Color(0.09, 0.09, 0.10), true)
	# The cowling's open front: a rounded lip, the fourteen cylinder heads of
	# the twin-row radial showing through it.
	var lip := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x, -0.05, -3.47))
	kit.cylinder(lip, 0.70, 0.66, 0.06, 20, METAL.darkened(0.08), false)
	# The real radial sits in the nacelle: its fixed heart in this kit,
	# the serviceable parts as their own nodes (engine_service pulls them).
	var ei := 0 if x < 0.0 else 1
	Radial.build(kit, ei)
	if engine_parts == null:
		engine_parts = Node3D.new()
		engine_parts.name = "EngineParts"
		add_child(engine_parts)
		if plane != null:    # the parked show plane on the apron has no flight model
			plane.set_meta("visual", self)
	Radial.build_removable(engine_parts, ei)
	_service_panels(ei)
	kit.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x, -0.05, -3.40)), 0.24, 0.20, 0.10, 12, Color(0.30, 0.30, 0.32), true)
	# Cowl flaps round the back of the cowling, and the exhaust under it.
	for fi in range(10):
		var fa := PI * 0.15 + PI * 0.7 * float(fi) / 9.0
		var fp := Vector3(x + cos(fa) * 0.845, -0.07 + sin(fa) * 0.85, -2.25)
		kit.box(Transform3D(Basis(Vector3.BACK, fa + PI * 0.5) * Basis(Vector3.RIGHT, -0.2), fp), Vector3(0.24, 0.02, 0.22), METAL_DK)

	# Main gear: twin oleo legs from the nacelle down to the axle, a drag
	# brace, and a big tyre. It swings forward and up into the nacelle on a
	# pivot at the top of the legs (the tyre still hangs a third out).
	var piv := Vector3(x, -0.80, -0.70)
	var gk := MeshKit.new()
	var hub := Vector3(x, -1.95, -0.85) - piv
	for dx in [-0.30, 0.30]:
		var top := Vector3(dx, 0.0, 0.0)
		var bot := hub + Vector3(dx, 0.0, 0.0)
		_beam(gk, top, top.lerp(bot, 0.55), 0.10, METAL_DK)
		_beam(gk, top.lerp(bot, 0.5), bot, 0.07, Color(0.80, 0.80, 0.82))
	_beam(gk, Vector3(-0.30, -0.75, -0.16), Vector3(0.30, -0.75, -0.16), 0.05, METAL_DK)
	_tyre(gk, hub, 0.67, 0.42)
	# The drag brace folds with it (drawn from the leg back to the spar).
	_beam(gk, Vector3(0, -0.05, 0.6), Vector3(0, -0.65, -0.12), 0.05, METAL_DK)
	var gn := Node3D.new()
	gn.name = "MainGear"
	gn.position = piv
	gn.add_child(gk.instance("Gear"))
	add_child(gn)
	gear_nodes.append(gn)
	# Wheel well: a dark opening under the nacelle.
	kit.box_at(Vector3(x, -0.86, -1.2), Vector3(0.9, 0.04, 1.6), Color(0.06, 0.06, 0.06))


## A rounded tyre with a hub, axle across (x).
func _tyre(kit: MeshKit, hub: Vector3, r: float, w: float) -> void:
	var rings: Array = []
	var prof := [[-0.5, 0.62], [-0.45, 0.86], [-0.3, 0.98], [0.0, 1.0], [0.3, 0.98], [0.45, 0.86], [0.5, 0.62]]
	for pr in prof:
		var ring := PackedVector3Array()
		for k in range(18):
			var a := TAU * float(k) / 18.0
			ring.append(hub + Vector3(float(pr[0]) * w, sin(a) * r * float(pr[1]), cos(a) * r * float(pr[1])))
		rings.append(ring)
	kit.loft(rings, TYRE, true, true)
	for sx in [-1.0, 1.0]:
		kit.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5 * sx), hub + Vector3(sx * w * 0.5, 0, 0)), r * 0.45, r * 0.35, 0.03, 14, Color(0.70, 0.70, 0.72), true)


func _beam(kit: MeshKit, a: Vector3, b: Vector3, radius: float, col: Color) -> void:
	var d := b - a
	var y := d.normalized()
	var xx := y.cross(Vector3.FORWARD)
	if xx.length_squared() < 0.001:
		xx = y.cross(Vector3.RIGHT)
	xx = xx.normalized()
	var z := xx.cross(y)
	kit.cylinder(Transform3D(Basis(xx, y, z), a), radius, radius, d.length(), 10, col, true)


func _tailwheel(kit: MeshKit) -> void:
	var hub := Vector3(0, -0.45, 10.6)
	_beam(kit, Vector3(0, 0.15, 10.25), hub + Vector3(0, 0.05, -0.12), 0.06, METAL_DK)
	for sx in [-0.09, 0.09]:
		_beam(kit, hub + Vector3(sx, 0.05, -0.12), hub + Vector3(sx, 0, 0), 0.025, METAL_DK)
	_tyre(kit, hub, 0.22, 0.14)
