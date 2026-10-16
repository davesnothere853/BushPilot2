extends Node3D
## The cockpit you sit in: walls, seats, the instrument panel with live gauges,
## and every switch, knob and lever as a real 3D part you can work with the mouse.
##
## Each control knows its own axis of travel and range, so a tracked VR hand
## can later grab it and move it along that axis (see hand_move()), and the
## mouse does the same through a ray from the camera.

const MeshKit = preload("res://scripts/meshkit.gd")
const Layout = preload("res://scripts/panel_layout.gd")
const HudScript = preload("res://scripts/hud.gd")
const EngineScript = preload("res://scripts/engine.gd")

const FABRIC := Color(0.34, 0.31, 0.27)
const HEADLINER := Color(0.40, 0.38, 0.34)
const FLOOR_COL := Color(0.09, 0.09, 0.085)
const VINYL := Color(0.30, 0.16, 0.09)
const PANEL_DARK := Color(0.07, 0.068, 0.065)
const BLACK := Color(0.03, 0.03, 0.03)
const CHROME := Color(0.72, 0.72, 0.74)
const KNOB_RED := Color(0.72, 0.08, 0.06)
const KNOB_BLUE := Color(0.12, 0.22, 0.62)
const SWITCH_RED := Color(0.62, 0.06, 0.05)
const GRIP := Color(0.13, 0.09, 0.07)

signal said(text: String)
signal clicked

var plane: Node3D
var controls: Array = []
var hover := -1
var active := -1
var yoke_active := false
var yoke_input := Vector2.ZERO        # x roll (+right), y pitch (+back)
var panel_hud: Control
var _viewport: SubViewport
var _hl_mat: StandardMaterial3D
var _drag_acc := 0.0
var _primer_t := 0.0
var _yokes: Array[Node3D] = []
var _pedals: Array = []               # [node, rest position, side (-1 left pedal / +1 right)]
var _compass: Label3D
var _glass_mat: StandardMaterial3D
var _needles: Array = []          # [node, angle function, current angle]
var _ai_ball: Node3D
var _ai_pointer: Node3D
var _slip_ball: MeshInstance3D
var _hdg_card: Node3D
var _hdg_bug: Node3D
var _lamps: Array = []            # [material, is-on function, colour]
var _panel_lamp: OmniLight3D      # instrument flood light (the panel dimmer)
var _slow := 0.0


var _built := false


## The fuselage's sections (plane_visual.gd: z, half width, top, bottom,
## corner bevel). Nothing of the cabin may poke out through the skin: a
## vertex outside it (the trim at the top corners by the windscreen stood
## 9 cm proud of the bevel) is pulled back in.
const SKIN := [[-2.05, 0.34, 0.28, -0.36, 0.12], [-1.92, 0.48, 0.42, -0.50, 0.14], [-1.15, 0.54, 0.50, -0.58, 0.14], [-0.45, 0.56, 0.92, -0.62, 0.12],
	[1.10, 0.54, 0.92, -0.62, 0.12], [1.65, 0.46, 0.60, -0.50, 0.12], [3.20, 0.26, 0.38, -0.22, 0.08]]


static func _keep_inside_skin(kit) -> void:
	var m := 0.006
	for vi in range(kit.verts.size()):
		var v: Vector3 = kit.verts[vi]
		if v.z < -0.45:
			continue                 # forward of the cabin the panel and the cowl sit as built
		for si in range(SKIN.size() - 1):
			var a: Array = SKIN[si]
			var b: Array = SKIN[si + 1]
			if v.z < float(a[0]) or v.z > float(b[0]):
				continue
			var t := (v.z - float(a[0])) / (float(b[0]) - float(a[0]))
			var hw := lerpf(a[1], b[1], t) - m
			var top := lerpf(a[2], b[2], t) - m
			var bot := lerpf(a[3], b[3], t) + m
			var bev := lerpf(a[4], b[4], t)
			var sx := signf(v.x) if absf(v.x) > 0.0001 else 1.0
			var x := minf(absf(v.x), hw)
			var y := clampf(v.y, bot, top)
			var over_t := x + y - (hw + top - bev)
			if over_t > 0.0:
				x -= over_t * 0.5
				y -= over_t * 0.5
			var over_b := x - y - (hw - bot - bev)
			if over_b > 0.0:
				x -= over_b * 0.5
				y += over_b * 0.5
			kit.verts[vi] = Vector3(sx * x, y, v.z)
			break


func build(p: Node3D, terrain: RefCounted) -> void:
	if _built:
		return
	_built = true
	plane = p
	_hl_mat = StandardMaterial3D.new()
	_hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hl_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_hl_mat.albedo_color = Color(1.0, 0.75, 0.3, 0.35)
	_build_shell()
	_build_panel(terrain)
	_build_controls()
	_build_yokes_and_pedals()
	build_pod()
	set_active(false)


## The aftermarket gauge pod under the panel (DESIGN_NOTES 121): two gauges,
## each wired to a reading in the workshop. Kept per aeroplane.
const Wiring = preload("res://scripts/gauge_wiring.gd")
const PodDash = preload("res://scripts/truck_dash.gd")
const POD_AT := Vector3(0.38, -0.08, -0.72)
var _pod: Node3D


func pod_key() -> String:
	return "plane:" + String(plane.get("reg")) if plane != null else "plane"


func build_pod() -> void:
	if _pod != null:
		_pod.queue_free()
	var w: Array = Wiring.load_wiring(pod_key(), Wiring.PLANE_DEFAULT)
	var pod := PodDash.new()
	pod.name = "GaugePod"
	add_child(pod)
	pod.transform = Transform3D(Basis(Vector3.RIGHT, -0.5), POD_AT)
	_pod = pod
	var k := MeshKit.new()
	k.box_at(Vector3(0, 0, -0.03), Vector3(0.15, 0.07, 0.025), PANEL_DARK)
	pod.add_child(k.instance("PodBracket"))
	for i in range(2):
		var sig: String = w[i]
		var spec: Dictionary = (Wiring.PLANE_SIGNALS.get(sig, Wiring.PLANE_SIGNALS["none"]) as Array)[1]
		var s2 := sig
		pod.gauge(Vector2(-0.035 + 0.07 * float(i), 0.0), 0.026, spec, func() -> float: return Wiring.read_plane(s2, plane.engine) if plane != null else 0.0)


func pod_wiring() -> Array:
	return Wiring.load_wiring(pod_key(), Wiring.PLANE_DEFAULT)


func wire_gauge(i: int, sig: String) -> void:
	var w := pod_wiring()
	w[i] = sig
	Wiring.save_wiring(pod_key(), w)
	build_pod()


## The cabin is always there (you can see in through the windows); the
## needles and hover highlights only update while you sit in it.
var active_view := false


func set_active(on: bool) -> void:
	active_view = on
	if not on:
		set_hover(-1)
		release()


# ------------------------------------------------------------------------------
#  The cabin
# ------------------------------------------------------------------------------
static func _beam(kit: RefCounted, a: Vector3, b: Vector3, radius: float, col: Color, sides: int = 5) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	kit.cylinder(Transform3D(Basis(x, y, z), a), radius, radius, d.length(), sides, col, true)


func _build_shell() -> void:
	var kit := MeshKit.new()
	var x := 0.535
	# The cabin follows the fuselage: full width to the back of the rear
	# windows (z 1.02), then the baggage bay tapers in with the tail to the
	# bulkhead at 1.62, its roof corners chamfered like the skin's, so nothing
	# of the inside pokes out through the roof or sides behind the wing.
	var ZA := 1.02
	var ZB := 1.62
	var aft := func(z: float, k: int) -> Vector3:
		# k 0: floor corner, 1: top of the flat side, 2: roof chamfer edge
		var t := clampf((z - ZA) / (ZB - ZA), 0.0, 1.0)
		var w := lerpf(x, 0.42, t)
		match k:
			0: return Vector3(w, -0.42, z)
			1: return Vector3(w, lerpf(0.79, 0.47, t), z)
			_: return Vector3(lerpf(0.43, 0.32, t), lerpf(0.895, 0.595, t), z)
	var mx := func(v: Vector3, side: float) -> Vector3: return Vector3(v.x * side, v.y, v.z)
	# Floor and firewall
	kit.quad(Vector3(-x, -0.42, -1.02), Vector3(x, -0.42, -1.02), Vector3(x, -0.42, ZA), Vector3(-x, -0.42, ZA), FLOOR_COL, Vector3.UP)
	var fa: Vector3 = aft.call(ZA, 0)
	var fb: Vector3 = aft.call(ZB, 0)
	kit.quad(mx.call(fa, -1.0), fa, fb, mx.call(fb, -1.0), FLOOR_COL, Vector3.UP)
	kit.quad(Vector3(-x, -0.42, -1.0), Vector3(x, -0.42, -1.0), Vector3(x, -0.04, -1.0), Vector3(-x, -0.04, -1.0), PANEL_DARK, Vector3.BACK)
	for side in [-1.0, 1.0]:
		var sx: float = side * x
		var inward := Vector3(-side, 0, 0)
		# Below the windows, between them, the roof chamfer above them
		kit.quad(Vector3(sx, -0.42, -1.02), Vector3(sx, -0.42, ZA), Vector3(sx, 0.29, ZA), Vector3(sx, 0.29, -1.02), FABRIC, inward)
		kit.quad(Vector3(sx, 0.29, 0.32), Vector3(sx, 0.29, 0.42), Vector3(sx, 0.79, 0.42), Vector3(sx, 0.79, 0.32), FABRIC, inward)
		kit.quad(Vector3(sx, 0.79, -0.50), Vector3(sx, 0.79, ZA), Vector3(side * 0.43, 0.895, ZA), Vector3(side * 0.43, 0.895, -0.50), FABRIC, Vector3(-side, -1, 0))
		# The tapering bay: side wall and roof chamfer
		var a0: Vector3 = mx.call(aft.call(ZA, 0), side)
		var a1: Vector3 = mx.call(aft.call(ZA, 1), side)
		var a2: Vector3 = mx.call(aft.call(ZA, 2), side)
		var b0: Vector3 = mx.call(aft.call(ZB, 0), side)
		var b1: Vector3 = mx.call(aft.call(ZB, 1), side)
		var b2: Vector3 = mx.call(aft.call(ZB, 2), side)
		kit.quad(a0, b0, b1, a1, FABRIC, inward)
		kit.quad(a1, b1, b2, a2, HEADLINER, Vector3(-side, -1, 0))
		# In front of the side window, up to the windscreen
		var a := Vector3(sx, 0.29, -1.02)
		var b := Vector3(sx, 0.29, -0.78)
		var c := Vector3(sx, 0.79, -0.47)
		var d := Vector3(sx, 0.77, -0.50)
		var e := Vector3(sx, 0.44, -1.02)
		kit.tri(a, b, c, FABRIC, inward)
		kit.tri(a, c, d, FABRIC, inward)
		kit.tri(a, d, e, FABRIC, inward)
		# Door handle and window frames
		kit.box_at(Vector3(side * 0.52, 0.18, 0.05), Vector3(0.03, 0.03, 0.14), CHROME)
		_beam(kit, Vector3(sx * 0.99, 0.29, -0.78), Vector3(sx * 0.99, 0.79, -0.47), 0.015, Color(0.13, 0.125, 0.12))
		_beam(kit, Vector3(sx * 0.99, 0.29, 0.37), Vector3(sx * 0.99, 0.79, 0.37), 0.03, BLACK)
	# Headliner, the bay roof, and the bulkhead behind the cargo floor
	kit.quad(Vector3(-0.43, 0.895, -0.50), Vector3(0.43, 0.895, -0.50), Vector3(0.43, 0.895, ZA), Vector3(-0.43, 0.895, ZA), HEADLINER, Vector3.DOWN)
	var ra: Vector3 = aft.call(ZA, 2)
	var rb: Vector3 = aft.call(ZB, 2)
	kit.quad(mx.call(ra, -1.0), ra, rb, mx.call(rb, -1.0), HEADLINER, Vector3.DOWN)
	var bk: Array = [mx.call(aft.call(ZB, 0), -1.0), aft.call(ZB, 0), aft.call(ZB, 1), aft.call(ZB, 2), mx.call(aft.call(ZB, 2), -1.0), mx.call(aft.call(ZB, 1), -1.0)]
	for i in range(1, bk.size() - 1):
		kit.tri(bk[0], bk[i], bk[i + 1], FABRIC, Vector3.FORWARD)
	# Windscreen frame: top bar and the centre post
	_beam(kit, Vector3(-0.52, 0.905, -0.45), Vector3(0.52, 0.905, -0.45), 0.025, Color(0.20, 0.19, 0.18))
	_beam(kit, Vector3(0.0, 0.50, -1.15), Vector3(0.0, 0.915, -0.45), 0.012, Color(0.20, 0.19, 0.18))
	# Glareshield
	kit.box_at(Vector3(0, 0.512, -0.92), Vector3(1.06, 0.03, 0.24), Color(0.085, 0.08, 0.075))
	kit.box_at(Vector3(0, 0.505, -0.79), Vector3(1.10, 0.05, 0.04), Color(0.06, 0.058, 0.055))
	# Panel back plate and the lip under it
	kit.box_at(Vector3(0, 0.225, -0.905), Vector3(1.10, 0.55, 0.03), PANEL_DARK)
	# Panel side edges (the face itself is the painted surface with holes)
	for ex in [-0.548, 0.548]:
		kit.box_at(Vector3(ex, 0.225, -0.852), Vector3(0.004, 0.55, 0.10), PANEL_DARK)
	kit.box_at(Vector3(0, -0.05, -0.80), Vector3(1.10, 0.02, 0.06), BLACK)
	# Seats
	for side in [-1.0, 1.0]:
		var sx2: float = side * 0.235
		kit.box_at(Vector3(sx2, -0.25, 0.04), Vector3(0.40, 0.10, 0.46), VINYL)
		kit.box(Transform3D(Basis(Vector3.RIGHT, 0.20), Vector3(sx2, 0.11, 0.30)), Vector3(0.40, 0.64, 0.09), VINYL)
		kit.box_at(Vector3(sx2, -0.35, 0.04), Vector3(0.30, 0.12, 0.36), BLACK)
		# Seat belt lying across
		kit.box(Transform3D(Basis(Vector3.BACK, 0.5 * side), Vector3(sx2, -0.19, 0.16)), Vector3(0.05, 0.005, 0.40), Color(0.25, 0.24, 0.20))
	# Rear bench and cargo floor tie-downs
	kit.box_at(Vector3(0, -0.25, 0.92), Vector3(0.98, 0.10, 0.40), VINYL)
	kit.box(Transform3D(Basis(Vector3.RIGHT, 0.18), Vector3(0, 0.10, 1.16)), Vector3(0.98, 0.60, 0.09), VINYL)
	for tz in [1.35, 1.55]:
		for tx in [-0.4, 0.4]:
			kit.box_at(Vector3(tx, -0.41, tz), Vector3(0.05, 0.02, 0.05), CHROME)
	# Centre console between the seats
	kit.box_at(Vector3(0, -0.36, -0.40), Vector3(0.15, 0.12, 0.58), BLACK)
	# Magnetic compass on the centre post, with the heading in a window
	kit.box_at(Vector3(0, 0.885, -0.64), Vector3(0.036, 0.024, 0.03), BLACK)
	_keep_inside_skin(kit)
	var shell := kit.instance("Cabin")
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	_compass = Label3D.new()
	_compass.font_size = 24
	_compass.pixel_size = 0.00034
	_compass.modulate = Color(0.95, 0.92, 0.80)
	_compass.outline_size = 0
	_compass.position = Vector3(0, 0.885, -0.624)
	add_child(_compass)


# ------------------------------------------------------------------------------
#  Instrument panel: the gauges are drawn by a copy of the HUD into a texture
# ------------------------------------------------------------------------------
func _build_panel(terrain: RefCounted) -> void:
	# The painted panel surface is drawn once into a texture.
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(int(Layout.W), int(Layout.H))
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	panel_hud = HudScript.new()
	panel_hud.plane = plane
	panel_hud.terrain = terrain
	panel_hud.panel3d = true
	panel_hud.cockpit_mode = true
	panel_hud.show_help = false
	_viewport.add_child(panel_hud)          # full-rect: fills the viewport
	panel_hud.set_process(false)

	_glass_mat = StandardMaterial3D.new()
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A faint glint, not a mirror: a full-strength sky reflection on every
	# glass washed the dials out from the pilot's seat.
	_glass_mat.albedo_color = Color(0.8, 0.85, 0.9, 0.04)
	_glass_mat.roughness = 0.12
	_glass_mat.metallic_specular = 0.25
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Holes in the panel for each instrument, then the instruments themselves.
	var holes: Array[Vector4] = []
	var add_hole := func(px: Vector2, r_m: float) -> void:
		var rp := Layout.m_to_px(r_m + 0.0025)
		holes.append(Vector4(px.x / Layout.W, px.y / Layout.H, rp / Layout.W, rp / Layout.H))
	for id in Layout.GAUGES.keys():
		add_hole.call(Layout.GAUGES[id], Layout.SIX_R)
		_flight_instrument(id, Layout.GAUGES[id])
	for id in Layout.DIALS.keys():
		var spec: Dictionary = Layout.DIALS[id]
		add_hole.call(spec["pos"], Layout.SMALL_R)
		_engine_dial(id, spec)
	add_hole.call(Layout.CLOCK_POS, Layout.CLOCK_R)
	_clock()
	_build_lamps()

	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(Layout.WIDTH_M, Layout.WIDTH_M * Layout.H / Layout.W)
	face.mesh = quad
	face.position = Vector3(0, Layout.TOP_Y - quad.size.y * 0.5, Layout.FACE_Z)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/panel.gdshader")
	mat.set_shader_parameter("panel_tex", _viewport.get_texture())
	while holes.size() < 40:
		holes.append(Vector4(-1, -1, 0.0001, 0.0001))
	mat.set_shader_parameter("holes", holes)
	mat.set_shader_parameter("hole_count", 40)
	face.material_override = mat
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(face)


# ------------------------------------------------------------------------------
#  Instruments: real 3D parts set into the panel
# ------------------------------------------------------------------------------
## Surface of revolution around the instrument's axis (local z toward the pilot).
## `profile` is a list of Vector2(radius, z); the visible side is on the left
## when walking along the profile.
static func _lathe(kit: RefCounted, profile: Array, segs: int, col: Color) -> void:
	for k in range(profile.size() - 1):
		var a: Vector2 = profile[k]
		var b: Vector2 = profile[k + 1]
		var t := b - a
		var n2 := Vector2(-t.y, t.x)
		for i in range(segs):
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var d0 := Vector3(cos(a0), sin(a0), 0.0)
			var d1 := Vector3(cos(a1), sin(a1), 0.0)
			var dm := (d0 + d1).normalized()
			var hint := dm * n2.x + Vector3(0, 0, n2.y)
			kit.quad(d0 * a.x + Vector3(0, 0, a.y), d1 * a.x + Vector3(0, 0, a.y), d1 * b.x + Vector3(0, 0, b.y), d0 * b.x + Vector3(0, 0, b.y), col, hint)


## A dial face picture, painted once by a copy of the HUD.
func _face_texture(id: String, size_px: int, transparent: bool) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(size_px, size_px)
	vp.disable_3d = true
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var h: Control = HudScript.new()
	h.plane = plane
	h.face_id = id
	h.cockpit_mode = true
	h.show_help = false
	h.face_scale = float(size_px) / (2.0 * (Layout.GAUGE_R + 9.0))
	vp.add_child(h)          # (full-rect anchors: it fills the viewport, no size to set)
	h.set_process(false)
	h.queue_redraw()
	return vp.get_texture()


## The case, bezel, screws, dial and glass of one instrument. Returns its root
## (local origin on the panel face at the instrument centre, z toward the pilot).
func _case(px: Vector2, r: float, face_tex: Texture2D, face_alpha: bool, deep: float = 0.03) -> Node3D:
	var root := Node3D.new()
	root.position = Layout.to_local(px)
	add_child(root)
	var kit := MeshKit.new()
	var rh := r + 0.0025
	# Case wall, seen from inside the hole
	_lathe(kit, [Vector2(rh, -deep), Vector2(rh, 0.0)], 32, Color(0.025, 0.025, 0.028))
	# Bezel ring standing proud of the panel
	_lathe(kit, [Vector2(rh, 0.0), Vector2(rh, 0.004), Vector2(rh + 0.003, 0.0065), Vector2(rh + 0.008, 0.006), Vector2(rh + 0.011, 0.0)], 32, Color(0.06, 0.06, 0.065))
	# Four screws
	for k in range(4):
		var a := PI * 0.25 + PI * 0.5 * float(k)
		var at := Vector3(cos(a), sin(a), 0) * (rh + 0.015) if r > 0.035 else Vector3(cos(a), sin(a), 0) * (rh + 0.010)
		kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at), 0.0028, 0.0024, 0.002, 8, Color(0.42, 0.42, 0.44), true)
		kit.box(Transform3D(Basis(Vector3.BACK, a), at + Vector3(0, 0, 0.0021)), Vector3(0.0045, 0.0007, 0.0004), Color(0.08, 0.08, 0.08))
	kit.smooth(40.0)
	var mi := kit.instance("Case")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if face_tex != null:
		root.add_child(_dial_quad(r, face_tex, face_alpha, -0.014))
	# Glass, with the case's back in darkness behind the dial
	var glass := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = rh
	disc.bottom_radius = rh
	disc.height = 0.0005
	disc.radial_segments = 32
	disc.rings = 1
	glass.mesh = disc
	glass.rotation = Vector3(PI * 0.5, 0, 0)
	glass.position = Vector3(0, 0, 0.0035)
	glass.material_override = _glass_mat
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass)
	return root


func _dial_quad(r: float, tex: Texture2D, alpha: bool, z: float) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var side := 2.0 * r * (Layout.GAUGE_R + 9.0) / Layout.GAUGE_R
	qm.size = Vector2(side, side)
	q.mesh = qm
	q.position = Vector3(0, 0, z)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission_energy_multiplier = 0.85      # dials read in the shade under the glareshield
	m.roughness = 0.8
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return q


## A needle pointing up (+y) from its hub; `kind`: "long", "short", "thin".
func _needle(parent: Node3D, r: float, z: float, kind: String, fn: Callable, col: Color = Color(0.95, 0.95, 0.92)) -> void:
	var node := Node3D.new()
	node.position = Vector3(0, 0, z)
	parent.add_child(node)
	var kit := MeshKit.new()
	var length := r * (0.92 if kind != "short" else 0.58)
	var w := r * (0.045 if kind == "long" else (0.085 if kind == "short" else 0.025))
	var t := 0.0012
	# Tapered blade with a point, and a counterweight tail
	kit.quad(Vector3(-w * 0.5, 0, t), Vector3(w * 0.5, 0, t), Vector3(w * 0.3, length * 0.85, t), Vector3(-w * 0.3, length * 0.85, t), col, Vector3.BACK)
	kit.tri(Vector3(-w * 0.3, length * 0.85, t), Vector3(w * 0.3, length * 0.85, t), Vector3(0, length, t), col, Vector3.BACK)
	kit.box_at(Vector3(0, length * 0.42, 0.0), Vector3(w * 0.8, length * 0.84, t * 1.6), col.darkened(0.5))
	kit.box_at(Vector3(0, -r * 0.13, 0.0), Vector3(w * 1.6, r * 0.22, t * 1.6), Color(0.08, 0.08, 0.08))
	if kind == "thin":
		kit.tri(Vector3(-r * 0.07, length * 0.80, t * 1.2), Vector3(r * 0.07, length * 0.80, t * 1.2), Vector3(0, length * 0.97, t * 1.2), col, Vector3.BACK)
	kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.001)), r * 0.09, r * 0.07, 0.004, 12, Color(0.06, 0.06, 0.06), true)
	var mi := kit.instance("Needle")
	var nmat := StandardMaterial3D.new()
	nmat.vertex_color_use_as_albedo = true
	nmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED     # the pointer always reads against the dial
	mi.material_override = nmat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(mi)
	_needles.append([node, fn, fn.call()])


func _flight_instrument(id: String, px: Vector2) -> void:
	var r := Layout.SIX_R
	var e = plane.engine
	match id:
		"airspeed":
			var root := _case(px, r, _face_texture(id, 320, false), false)
			_needle(root, r, -0.010, "long", func() -> float: return lerpf(30.0, 330.0, clampf(plane.ias_kt / 180.0, 0.0, 1.0)))
		"altimeter":
			var root := _case(px, r, _face_texture(id, 320, false), false)
			_needle(root, r, -0.0115, "thin", func() -> float: return maxf(plane.altitude_ft(), 0.0) / 100000.0 * 360.0)
			_needle(root, r, -0.0095, "short", func() -> float: return maxf(plane.altitude_ft(), 0.0) / 10000.0 * 360.0)
			_needle(root, r, -0.0075, "long", func() -> float: return fposmod(maxf(plane.altitude_ft(), 0.0), 1000.0) / 1000.0 * 360.0)
		"vsi":
			var root := _case(px, r, _face_texture(id, 320, false), false)
			_needle(root, r, -0.010, "long", func() -> float: return 270.0 + clampf(plane.vertical_speed_fpm() / 100.0, -20.0, 20.0) / 20.0 * 165.0)
		"tach":
			var root := _case(px, r, _face_texture(id, 320, false), false)
			_needle(root, r, -0.010, "long", func() -> float: return lerpf(-130.0, 130.0, clampf(float(plane.rpm) / 3000.0, 0.0, 1.0)))
		"heading":
			var root := _case(px, r, null, false)
			# The compass card turns behind a fixed lubber line and aircraft outline.
			_hdg_card = Node3D.new()
			root.add_child(_hdg_card)
			_hdg_card.add_child(_dial_quad(r, _face_texture(id, 320, false), false, -0.014))
			_hdg_bug = MeshKit.new().instance("Bug")
			var bk := MeshKit.new()
			bk.box_at(Vector3(0, r * 0.97, -0.0125), Vector3(r * 0.14, r * 0.10, 0.002), Color(1.0, 0.55, 0.1))
			_hdg_bug = bk.instance("Bug")
			_hdg_card.add_child(_hdg_bug)
			var fk := MeshKit.new()
			fk.box_at(Vector3(0, r * 0.88, -0.006), Vector3(r * 0.04, r * 0.24, 0.002), Color(1.0, 0.55, 0.1))
			var wcol := Color(0.92, 0.92, 0.88)
			fk.box_at(Vector3(0, 0, -0.006), Vector3(r * 0.06, r * 0.55, 0.002), wcol)
			fk.box_at(Vector3(0, r * 0.06, -0.006), Vector3(r * 0.55, r * 0.06, 0.002), wcol)
			fk.box_at(Vector3(0, -r * 0.22, -0.006), Vector3(r * 0.22, r * 0.05, 0.002), wcol)
			var fixed := fk.instance("Lubber")
			fixed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(fixed)
		"attitude":
			var root := _case(px, r, null, false, 0.075)
			# An earth-stabilised ball: sky above, ground below, horizon and pitch lines.
			var R := r * 1.18
			var bk := MeshKit.new()
			var bands := [[-90.0, -21.0, "g"], [-21.0, -19.0, "w"], [-19.0, -11.0, "g"], [-11.0, -9.0, "w"], [-9.0, -0.9, "g"], [-0.9, 0.9, "w"],
				[0.9, 9.0, "s"], [9.0, 11.0, "w"], [11.0, 19.0, "s"], [19.0, 21.0, "w"], [21.0, 90.0, "s"]]
			var sky := Color(0.20, 0.45, 0.78)
			var ground := Color(0.42, 0.27, 0.13)
			for band in bands:
				var steps := maxi(1, int((float(band[1]) - float(band[0])) / 7.5))
				for k in range(steps):
					var la := deg_to_rad(lerpf(band[0], band[1], float(k) / float(steps)))
					var lb := deg_to_rad(lerpf(band[0], band[1], float(k + 1) / float(steps)))
					var col: Color = sky if band[2] == "s" else (ground if band[2] == "g" else Color(0.95, 0.95, 0.92))
					for i in range(32):
						var a0 := TAU * float(i) / 32.0
						var a1 := TAU * float(i + 1) / 32.0
						var p00 := Vector3(cos(la) * sin(a0), sin(la), cos(la) * cos(a0)) * R
						var p01 := Vector3(cos(la) * sin(a1), sin(la), cos(la) * cos(a1)) * R
						var p10 := Vector3(cos(lb) * sin(a0), sin(lb), cos(lb) * cos(a0)) * R
						var p11 := Vector3(cos(lb) * sin(a1), sin(lb), cos(lb) * cos(a1)) * R
						bk.quad(p00, p01, p11, p10, col, (p00 + p11) * 0.5)
			bk.smooth(60.0)
			_ai_ball = Node3D.new()
			_ai_ball.position = Vector3(0, 0, -0.006 - R)
			var ball_mi := bk.instance("Ball")
			ball_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ai_ball.add_child(ball_mi)
			root.add_child(_ai_ball)
			root.add_child(_dial_quad(r, _face_texture(id, 320, true), true, -0.004))
			# Bank pointer that turns with the ball, and the fixed orange aircraft
			_ai_pointer = Node3D.new()
			_ai_pointer.position = Vector3(0, 0, -0.0035)
			var pk := MeshKit.new()
			pk.tri(Vector3(-r * 0.07, r * 0.70, 0), Vector3(r * 0.07, r * 0.70, 0), Vector3(0, r * 0.84, 0), Color(1.0, 0.55, 0.1), Vector3.BACK)
			_ai_pointer.add_child(pk.instance("Pointer"))
			root.add_child(_ai_pointer)
			var ak := MeshKit.new()
			var orange := Color(1.0, 0.55, 0.1)
			ak.box_at(Vector3(-r * 0.42, 0, -0.002), Vector3(r * 0.38, r * 0.06, 0.003), orange)
			ak.box_at(Vector3(r * 0.42, 0, -0.002), Vector3(r * 0.38, r * 0.06, 0.003), orange)
			ak.box_at(Vector3(-r * 0.23, -r * 0.06, -0.002), Vector3(r * 0.05, r * 0.14, 0.003), orange)
			ak.box_at(Vector3(r * 0.23, -r * 0.06, -0.002), Vector3(r * 0.05, r * 0.14, 0.003), orange)
			ak.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.0035)), r * 0.05, r * 0.05, 0.003, 10, orange, true)
			var sym := ak.instance("Symbol")
			sym.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(sym)
			# Slip ball in its curved glass tube below the instrument
			var tk := MeshKit.new()
			tk.box_at(Vector3(0, -r - 0.021, 0.003), Vector3(0.058, 0.012, 0.008), Color(0.80, 0.80, 0.74))
			tk.box_at(Vector3(-0.007, -r - 0.021, 0.0072), Vector3(0.0012, 0.012, 0.0005), Color(0.1, 0.1, 0.1))
			tk.box_at(Vector3(0.007, -r - 0.021, 0.0072), Vector3(0.0012, 0.012, 0.0005), Color(0.1, 0.1, 0.1))
			root.add_child(tk.instance("SlipTube"))
			_slip_ball = MeshInstance3D.new()
			var sb := SphereMesh.new()
			sb.radius = 0.0048
			sb.height = 0.0096
			_slip_ball.mesh = sb
			var sbm := StandardMaterial3D.new()
			sbm.albedo_color = Color(0.03, 0.03, 0.03)
			sbm.roughness = 0.2
			_slip_ball.material_override = sbm
			_slip_ball.position = Vector3(0, -r - 0.021, 0.0075)
			root.add_child(_slip_ball)


func _engine_dial(id: String, spec: Dictionary) -> void:
	var r := Layout.SMALL_R
	var e = plane.engine
	var root := _case(spec["pos"], r, _face_texture(id, 224, false), false, 0.022)
	var lo: float = spec["lo"]
	var hi: float = spec["hi"]
	var a0: float = spec["a0"]
	var a1: float = spec["a1"]
	var value: Callable
	match id:
		"map":
			value = func() -> float: return e.map_inhg
		"oilt":
			value = func() -> float: return e.oil_temp * 1.8 + 32.0
		"oilp":
			value = func() -> float: return e.oil_press
		"cht":
			value = func() -> float: return e.cht * 1.8 + 32.0
		"egt":
			value = func() -> float: return (e.egt * 1.8 + 32.0 - 300.0) / 1300.0
		"fuell":
			value = func() -> float: return e.tank_left / maxf(e.tank_capacity, 1.0) * 20.0
		"fuelr":
			value = func() -> float: return e.tank_right / maxf(e.tank_capacity, 1.0) * 20.0
		_:
			value = func() -> float: return e.amps if e.master else 0.0
	_needle(root, r, -0.009, "long", func() -> float: return lerpf(a0, a1, clampf((float(value.call()) - lo) / (hi - lo), 0.0, 1.0)))


func _clock() -> void:
	var r := Layout.CLOCK_R
	var root := _case(Layout.CLOCK_POS, r, _face_texture("clock", 256, false), false, 0.022)
	_needle(root, r, -0.010, "short", func() -> float: return fposmod(float(Game.time_of_day), 12.0) / 12.0 * 360.0)
	_needle(root, r, -0.008, "long", func() -> float: return fposmod(float(Game.time_of_day) * 60.0, 60.0) / 60.0 * 360.0)


## Warning lamps: coloured glass lenses that light up.
func _build_lamps() -> void:
	var e = plane.engine
	for lamp in Layout.LAMPS:
		var at := Layout.to_local(lamp[1])
		var kit := MeshKit.new()
		_lathe(kit, [Vector2(0.0085, 0.0), Vector2(0.0085, 0.004), Vector2(0.0105, 0.005), Vector2(0.0125, 0.0)], 20, Color(0.30, 0.30, 0.32))
		var ring := kit.instance("LampRing")
		ring.position = at
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		var lens := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.0085
		sm.height = 0.0085
		sm.is_hemisphere = true
		lens.mesh = sm
		lens.rotation = Vector3(PI * 0.5, 0, 0)
		lens.position = at + Vector3(0, 0, 0.001)
		var col := Color(0.95, 0.12, 0.08) if lamp[3] == "r" else Color(1.0, 0.62, 0.08)
		var m := StandardMaterial3D.new()
		m.albedo_color = col.darkened(0.6)
		m.roughness = 0.15
		m.emission = col
		lens.material_override = m
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lens)
		var on: Callable
		match lamp[0]:
			"stall":
				on = func() -> bool: return plane.stall_warning
			"oil":
				on = func() -> bool: return (plane.engine_running and e.oil_press < 20.0) or (e.master and not plane.engine_running)
			"volts":
				on = func() -> bool: return e.master and e.volts > 0.1 and e.volts < 12.0
			"fuel":
				on = func() -> bool: return plane.fuel < 18.0
			"starter":
				on = func() -> bool: return e.cranking
			_:
				on = func() -> bool:
					var wb: Vector2 = plane.wheel_brakes()
					return plane.on_ground and (plane.park_brake or wb.x > 0.4 or wb.y > 0.4)
		_lamps.append([m, on, col])


func _update_instruments(delta: float) -> void:
	# Needles swing toward their readings with a little lag, like the real thing.
	var k := clampf(delta * 8.0, 0.0, 1.0)
	for nd in _needles:
		var target: float = nd[1].call()
		nd[2] = lerpf(nd[2], target, k)
		(nd[0] as Node3D).rotation.z = -deg_to_rad(nd[2])
	if _ai_ball != null:
		var roll: float = plane.roll_rad()
		var pitch: float = plane.pitch_rad()
		_ai_ball.basis = Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, clampf(pitch * 1.4, -1.2, 1.2))
		_ai_pointer.rotation.z = roll
		_slip_ball.position.x = lerpf(_slip_ball.position.x, clampf(float(plane.slip_ball), -1.0, 1.0) * 0.022, k)
	if _hdg_card != null:
		var hdg: float = plane.heading_deg()
		_hdg_card.rotation.z = deg_to_rad(hdg)
		var tgt: int = panel_hud.target_strip
		_hdg_bug.visible = tgt >= 0
		if tgt >= 0:
			_hdg_bug.rotation.z = -deg_to_rad(panel_hud._bearing_to(tgt))
	var powered: bool = plane.engine.master and plane.engine.volts > 6.0
	for lp in _lamps:
		var lit: bool = powered and lp[1].call()
		var m: StandardMaterial3D = lp[0]
		if m.emission_enabled != lit:
			m.emission_enabled = lit
			m.emission_energy_multiplier = 2.2
			m.albedo_color = (lp[2] as Color) if lit else (lp[2] as Color).darkened(0.6)


# ------------------------------------------------------------------------------
#  Controls
# ------------------------------------------------------------------------------
func _part(kit: RefCounted, node_name: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = at
	var mi: MeshInstance3D = kit.instance(node_name + "Mesh")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	add_child(node)
	return node


## Register a control. `kind`: toggle, rotary, notch, slide, button, yoke.
func _add(id: String, kind: String, node: Node3D, grip: Vector3, radius: float, getter: Callable, setter: Callable,
		poser: Callable, text: Callable, extra: Dictionary = {}) -> void:
	var c := {"id": id, "kind": kind, "node": node, "mesh": node.get_child(0), "grip": grip, "radius": radius,
		"get": getter, "set": setter, "pose": poser, "text": text, "min": 0.0, "max": 1.0, "steps": 2,
		"sens": 0.006, "fixed": false, "axis": Vector3.BACK, "travel": 0.07}
	c.merge(extra, true)
	controls.append(c)


func _bezel(kit: RefCounted, at: Vector3, r: float) -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at)
	kit.cylinder(xf, r, r, 0.005, 14, Color(0.20, 0.20, 0.21), true)


func _build_controls() -> void:
	var e = plane.engine
	var fixed_kit := MeshKit.new()

	# --- battery master and alternator: red rocker switches ---------------------------
	for id in ["master", "alternator"]:
		var at := Layout.to_local(Layout.CONTROLS[id][0]) + Vector3(0, 0, 0.012)
		fixed_kit.box_at(at - Vector3(0, 0, 0.008), Vector3(0.034, 0.054, 0.006), BLACK)
		var kit := MeshKit.new()
		kit.box_at(Vector3.ZERO, Vector3(0.026, 0.044, 0.018), SWITCH_RED)
		kit.box_at(Vector3(0, 0.012, 0.0095), Vector3(0.02, 0.012, 0.002), Color(0.9, 0.85, 0.8))
		var node := _part(kit, id, at)
		var getter: Callable
		var setter: Callable
		if id == "master":
			getter = func() -> float: return 1.0 if e.master else 0.0
			setter = func(v: float) -> void: e.master = v > 0.5
		else:
			getter = func() -> float: return 1.0 if e.alternator else 0.0
			setter = func(v: float) -> void: e.alternator = v > 0.5
		var label := "Battery master" if id == "master" else "Alternator"
		_add(id, "toggle", node, Vector3.ZERO, 0.032, getter, setter,
			func(n: Node3D, v: float) -> void: n.rotation.x = -0.28 if v > 0.5 else 0.28,
			func(v: float) -> String: return "%s %s" % [label, "ON" if v > 0.5 else "OFF"])

	# --- light switches: a row of black rockers, and the panel light dimmer ------------------
	for id in ["lt_beacon", "lt_nav", "lt_strobe", "lt_taxi", "lt_landing"]:
		var key: String = id.substr(3)
		var lat := Layout.to_local(Layout.CONTROLS[id][0]) + Vector3(0, 0, 0.012)
		fixed_kit.box_at(lat - Vector3(0, 0, 0.008), Vector3(0.030, 0.050, 0.006), BLACK)
		var lk := MeshKit.new()
		lk.box_at(Vector3.ZERO, Vector3(0.022, 0.040, 0.016), Color(0.12, 0.12, 0.12))
		lk.box_at(Vector3(0, 0.011, 0.0085), Vector3(0.016, 0.010, 0.002), Color(0.9, 0.85, 0.8))
		var lnode := _part(lk, id, lat)
		var lname: String = {"beacon": "Beacon", "nav": "Navigation lights", "strobe": "Strobes", "taxi": "Taxi light", "landing": "Landing light"}[key]
		_add(id, "toggle", lnode, Vector3.ZERO, 0.03,
			func() -> float: return 1.0 if bool(plane.lights.get(key, false)) else 0.0,
			func(v: float) -> void: plane.lights[key] = v > 0.5,
			func(n: Node3D, v: float) -> void: n.rotation.x = -0.28 if v > 0.5 else 0.28,
			func(v: float) -> String: return "%s %s" % [lname, "ON" if v > 0.5 else "OFF"])
	var pl_at := Layout.to_local(Layout.CONTROLS["lt_panel"][0]) + Vector3(0, 0, 0.004)
	_bezel(fixed_kit, pl_at, 0.022)
	var pk := MeshKit.new()
	pk.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.015, 0.013, 0.02, 12, BLACK, true)
	pk.box_at(Vector3(0, 0.009, 0.021), Vector3(0.004, 0.012, 0.002), Color(0.9, 0.9, 0.85))
	var pnode := _part(pk, "lt_panel", pl_at)
	_add("lt_panel", "rotary", pnode, Vector3(0, 0, 0.02), 0.03,
		func() -> float: return plane.panel_light * 3.0,
		func(v: float) -> void: plane.panel_light = clampf(round(v), 0.0, 3.0) / 3.0,
		func(n: Node3D, v: float) -> void: n.rotation.z = -deg_to_rad(-90.0 + 60.0 * v),
		func(v: float) -> String: return "Panel lights %s" % ["OFF", "DIM", "MEDIUM", "BRIGHT"][clampi(int(round(v)), 0, 3)],
		{"steps": 3})
	_panel_lamp = OmniLight3D.new()
	_panel_lamp.position = Vector3(0, 0.62, -0.55)
	_panel_lamp.light_color = Color(1.0, 0.75, 0.6)
	_panel_lamp.omni_range = 0.65
	_panel_lamp.light_energy = 0.0
	_panel_lamp.shadow_enabled = false
	add_child(_panel_lamp)

	# --- magneto key ---------------------------------------------------------------------
	var mag_at := Layout.to_local(Layout.CONTROLS["mags"][0]) + Vector3(0, 0, 0.004)
	_bezel(fixed_kit, mag_at, 0.028)
	var mk := MeshKit.new()
	mk.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.014, 0.014, 0.012, 10, CHROME, true)
	mk.box_at(Vector3(0, 0.0, 0.022), Vector3(0.010, 0.040, 0.016), Color(0.55, 0.50, 0.38))
	mk.box_at(Vector3(0, 0.026, 0.024), Vector3(0.026, 0.020, 0.008), Color(0.55, 0.50, 0.38))
	var mag_node := _part(mk, "mags", mag_at)
	_add("mags", "rotary", mag_node, Vector3(0, 0, 0.02), 0.034,
		func() -> float: return float(e.mags),
		func(v: float) -> void: e.mags = clampi(int(round(v)), 0, 4),
		func(n: Node3D, v: float) -> void: n.rotation.z = -deg_to_rad(-60.0 + 30.0 * v),
		func(v: float) -> String: return "Magnetos %s%s" % [EngineScript.MAG_NAMES[int(v)], "  (hold at START to crank)" if int(v) == 3 else ""],
		{"steps": 4})

	# --- push-pull knobs: primer, carb heat, throttle, prop, mixture ---------------------
	var knobs := [
		# id, knob colour, radius, "out" means more?, label
		["primer", CHROME, 0.012, false],
		["carb_heat", Color(0.12, 0.12, 0.12), 0.013, true],
		["throttle", Color(0.06, 0.06, 0.06), 0.021, false],
		["prop", KNOB_BLUE, 0.017, false],
		["mixture", KNOB_RED, 0.017, false],
	]
	for k in knobs:
		var id: String = k[0]
		var base := Layout.to_local(Layout.CONTROLS[id][0])
		_bezel(fixed_kit, base + Vector3(0, 0, 0.002), float(k[2]) + 0.008)
		var kit := MeshKit.new()
		var rr: float = k[2]
		kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.14)), 0.005, 0.005, 0.14, 6, CHROME, false)
		if id == "throttle":
			kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), rr, rr * 0.92, 0.034, 12, k[1], true)
		elif id == "mixture":
			kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), rr, rr, 0.026, 10, k[1], true)
			for j in range(8):
				var a := TAU * float(j) / 8.0
				kit.box_at(Vector3(cos(a) * rr, sin(a) * rr, 0.013), Vector3(0.004, 0.004, 0.024), k[1].darkened(0.3))
		elif id == "primer":
			kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.006, 0.006, 0.02, 6, CHROME, false)
			kit.box_at(Vector3(0, 0, 0.022), Vector3(0.036, 0.010, 0.010), CHROME)
		else:
			kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), rr, rr * 0.75, 0.024, 10, k[1], true)
		var node := _part(kit, id, base + Vector3(0, 0, 0.012))
		var travel := 0.07 if id in ["throttle", "prop", "mixture"] else 0.05
		var b := base
		match id:
			"primer":
				var primer_pose := func(n: Node3D, _v: float) -> void:
					var sw := sin(clampf(_primer_t / 0.7, 0.0, 1.0) * PI)
					n.position = b + Vector3(0, 0, 0.012 + 0.06 * sw)
				_add(id, "button", node, Vector3(0, 0, 0.02), 0.03,
					func() -> float: return float(e.prime),
					func(_v: float) -> void: _prime(),
					primer_pose,
					func(v: float) -> String: return "Primer: click to pump (%d strokes)" % int(round(v)))
			"carb_heat":
				_add(id, "toggle", node, Vector3(0, 0, 0.02), 0.03,
					func() -> float: return 1.0 if e.carb_heat else 0.0,
					func(v: float) -> void: e.carb_heat = v > 0.5,
					func(n: Node3D, v: float) -> void: n.position = b + Vector3(0, 0, 0.012 + travel * v),
					func(v: float) -> String: return "Carb heat %s (pull for ON)" % ("ON" if v > 0.5 else "OFF"),
					{"travel": travel, "axis": Vector3.BACK})
			"throttle":
				_add(id, "slide", node, Vector3(0, 0, 0.02), 0.035,
					func() -> float: return plane.throttle,
					func(v: float) -> void: plane.throttle = v,
					func(n: Node3D, v: float) -> void: n.position = b + Vector3(0, 0, 0.012 + travel * (1.0 - v)),
					func(v: float) -> String: return "Throttle %d%%  (push in for power)" % int(round(v * 100.0)),
					{"travel": travel, "axis": Vector3.FORWARD})
			"prop":
				_add(id, "slide", node, Vector3(0, 0, 0.02), 0.032,
					func() -> float: return e.prop_lever,
					func(v: float) -> void: e.prop_lever = v,
					func(n: Node3D, v: float) -> void: n.position = b + Vector3(0, 0, 0.012 + travel * (1.0 - v)),
					func(v: float) -> String: return "Propeller %d%%  (in = fine pitch, high rpm)" % int(round(v * 100.0)),
					{"travel": travel, "axis": Vector3.FORWARD})
			"mixture":
				_add(id, "slide", node, Vector3(0, 0, 0.02), 0.032,
					func() -> float: return e.mixture,
					func(v: float) -> void: e.mixture = v,
					func(n: Node3D, v: float) -> void: n.position = b + Vector3(0, 0, 0.012 + travel * (1.0 - v)),
					func(v: float) -> String: return "Mixture %d%%  (best now %d%%, pull out to stop)" % [int(round(v * 100.0)), int(round(e.best_mixture * 100.0))],
					{"travel": travel, "axis": Vector3.FORWARD})

	# --- cowl flap lever ------------------------------------------------------------------
	var cowl_at := Layout.to_local(Layout.CONTROLS["cowl"][0]) + Vector3(0, 0, 0.012)
	var ck := MeshKit.new()
	ck.box_at(Vector3(0, 0, -0.01), Vector3(0.008, 0.02, 0.03), CHROME)
	ck.box_at(Vector3(0, 0, 0.012), Vector3(0.05, 0.022, 0.022), BLACK)
	var cowl_node := _part(ck, "cowl", cowl_at)
	_add("cowl", "notch", cowl_node, Vector3(0, 0, 0.012), 0.035,
		func() -> float: return round(e.cowl_flaps * 2.0),
		func(v: float) -> void: e.cowl_flaps = clampf(round(v), 0.0, 2.0) * 0.5,
		func(n: Node3D, v: float) -> void: n.position = cowl_at + Vector3(0, 0.034 - 0.034 * v, 0),
		func(v: float) -> String: return "Cowl flaps %s" % ["CLOSED", "HALF", "OPEN"][clampi(int(v), 0, 2)],
		{"steps": 3, "axis": Vector3.DOWN, "travel": 0.068})

	# --- fuel selector on the console --------------------------------------------------
	var fuel_at := Vector3(0, -0.296, -0.60)
	fixed_kit.cylinder(Transform3D(Basis.IDENTITY, fuel_at - Vector3(0, 0.004, 0)), 0.055, 0.055, 0.004, 16, Color(0.18, 0.18, 0.18), true)
	var fk := MeshKit.new()
	fk.box_at(Vector3(0, 0.012, -0.012), Vector3(0.018, 0.022, 0.085), Color(0.75, 0.70, 0.55))
	fk.box_at(Vector3(0, 0.012, -0.055), Vector3(0.008, 0.024, 0.012), KNOB_RED)
	var fuel_node := _part(fk, "fuel", fuel_at)
	var fuel_angles := [PI, deg_to_rad(70.0), deg_to_rad(-70.0), 0.0]
	_add("fuel", "rotary", fuel_node, Vector3(0, 0.02, 0), 0.06,
		func() -> float: return float(e.fuel_selector),
		func(v: float) -> void: e.fuel_selector = clampi(int(round(v)), 0, 3),
		func(n: Node3D, v: float) -> void: n.rotation.y = fuel_angles[clampi(int(v), 0, 3)],
		func(v: float) -> String: return "Fuel selector %s" % EngineScript.FUEL_NAMES[clampi(int(v), 0, 3)],
		{"steps": 4, "fixed": true, "wrap": true})
	for i in range(4):
		var lab := Label3D.new()
		lab.text = EngineScript.FUEL_NAMES[i]
		lab.font_size = 40
		lab.pixel_size = 0.0007
		lab.modulate = Color(0.85, 0.82, 0.70)
		lab.outline_size = 0
		var a: float = fuel_angles[i]
		lab.position = fuel_at + Vector3(-sin(a), 0.002, -cos(a)) * 0.075 + Vector3(0, 0.001, 0)
		lab.rotation = Vector3(-PI * 0.5, 0, 0)
		add_child(lab)
	var flab := Label3D.new()
	flab.text = "FUEL"
	flab.font_size = 36
	flab.pixel_size = 0.0007
	flab.outline_size = 0
	flab.modulate = Color(0.85, 0.82, 0.70)
	flab.position = fuel_at + Vector3(0, 0.002, 0.10)
	flab.rotation = Vector3(-PI * 0.5, 0, 0)
	add_child(flab)

	# --- flap lever between the seats (a Johnson bar: pull up for more flap) -------------
	var flap_at := Vector3(-0.035, -0.30, -0.08)
	var lk := MeshKit.new()
	lk.box_at(Vector3(0, 0, -0.21), Vector3(0.022, 0.022, 0.42), CHROME)
	lk.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.50)), 0.017, 0.017, 0.11, 8, GRIP, true)
	lk.box_at(Vector3(0, 0.018, -0.445), Vector3(0.010, 0.010, 0.016), KNOB_RED)
	var flap_node := _part(lk, "flaps", flap_at)
	_add("flaps", "notch", flap_node, Vector3(0, 0, -0.45), 0.06,
		func() -> float: return float(plane.flap_notch),
		func(v: float) -> void: plane.flap_notch = clampi(int(round(v)), 0, 4),
		func(n: Node3D, v: float) -> void: n.rotation.x = deg_to_rad(8.0 + 12.0 * v),
		func(v: float) -> String: return "Flaps %d°  (pull the lever up for more)" % (int(v) * 10),
		{"steps": 5, "axis": Vector3.UP, "travel": 0.25})

	# --- elevator trim wheel ------------------------------------------------------------
	var trim_at := Vector3(0.04, -0.32, -0.42)
	var tk := MeshKit.new()
	tk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.010, 0, 0)), 0.085, 0.085, 0.02, 18, Color(0.10, 0.10, 0.10), true)
	for j in range(18):
		var a := TAU * float(j) / 18.0
		tk.box_at(Vector3(0, cos(a) * 0.087, sin(a) * 0.087), Vector3(0.022, 0.008, 0.008), Color(0.16, 0.16, 0.16))
	tk.box_at(Vector3(0, 0.088, 0), Vector3(0.023, 0.006, 0.012), Color(0.9, 0.9, 0.85))
	var trim_node := _part(tk, "trim", trim_at)
	_add("trim", "slide", trim_node, Vector3(0, 0.075, 0), 0.05,
		func() -> float: return plane.trim,
		func(v: float) -> void: plane.trim = v,
		func(n: Node3D, v: float) -> void: n.rotation.x = -v * 3.0,
		func(v: float) -> String: return "Elevator trim %d%% %s  (roll the wheel back for nose up)" % [int(absf(v) * 100.0), "nose up" if v > 0.02 else ("nose down" if v < -0.02 else "neutral")],
		{"min": -1.0, "max": 1.0, "sens": 0.008, "fixed": true})
	var tlab := Label3D.new()
	tlab.text = "TRIM\nNOSE DN ^\nNOSE UP v"
	tlab.font_size = 28
	tlab.pixel_size = 0.0007
	tlab.outline_size = 0
	tlab.modulate = Color(0.85, 0.82, 0.70)
	tlab.position = Vector3(0.076, -0.299, -0.30)
	tlab.rotation = Vector3(-PI * 0.5, 0, 0)
	add_child(tlab)

	var fixed := fixed_kit.instance("PanelHardware")
	fixed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fixed)


func _build_yokes_and_pedals() -> void:
	for side in [-1.0, 1.0]:
		var at := Vector3(side * 0.24, 0.035, -0.53)
		var kit := MeshKit.new()
		kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.42)), 0.012, 0.012, 0.42, 12, Color(0.32, 0.32, 0.33), false)
		kit.box_at(Vector3(0, 0, 0.01), Vector3(0.06, 0.06, 0.04), BLACK)
		kit.box_at(Vector3(0, 0.0, 0.02), Vector3(0.30, 0.03, 0.03), BLACK)
		for gx in [-0.15, 0.15]:
			kit.box_at(Vector3(gx, 0.045, 0.02), Vector3(0.032, 0.11, 0.036), GRIP)
		kit.box_at(Vector3(-0.15, 0.10, 0.02), Vector3(0.012, 0.006, 0.012), KNOB_RED)   # radio button
		var node := _part(kit, "yoke" if side < 0.0 else "yoke_r", at)
		_yokes.append(node)
		var rest := at
		var yoke_pose := func(n: Node3D, _v: float) -> void:
			var pitch_in: float = clampf(plane.elevator, -1.0, 1.0)
			var roll_in: float = clampf(plane.aileron, -1.0, 1.0)
			n.position = rest + Vector3(0, 0, 0.07 * pitch_in)
			n.rotation.z = -roll_in * 0.7
		_add("yoke" if side < 0.0 else "yoke_r", "yoke", node, Vector3(0, 0.03, 0.02), 0.12,
			func() -> float: return 0.0,
			func(_v: float) -> void: pass,
			yoke_pose,
			func(_v: float) -> String: return "Yoke: hold and drag to fly (drag down = pull back)")
		# Rudder pedals with toe brakes
		for ps in [-1.0, 1.0]:
			var pk := MeshKit.new()
			pk.box(Transform3D(Basis(Vector3.RIGHT, -0.45), Vector3(0, 0.06, 0)), Vector3(0.075, 0.13, 0.018), Color(0.25, 0.25, 0.26))
			pk.box_at(Vector3(0, -0.02, 0.06), Vector3(0.02, 0.02, 0.14), CHROME)
			var pat := Vector3(side * 0.24 + ps * 0.085, -0.40, -0.88)
			var pn := _part(pk, "pedal", pat)
			_pedals.append([pn, pat, ps, side])


# ------------------------------------------------------------------------------
#  Per-frame: every part shows the state it is in, however it was changed
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if plane == null:
		return
	if not active_view:
		# Seen from outside: keep the controls roughly right, a few times a second.
		_slow += delta
		if _slow < 0.25:
			return
		_slow = 0.0
	if _primer_t > 0.0:
		_primer_t = maxf(_primer_t - delta, 0.0)
	if _panel_lamp != null:
		var pw: bool = plane.engine.master and plane.engine.battery > 0.02
		_panel_lamp.light_energy = 0.55 * plane.panel_light if pw else 0.0
	_update_instruments(delta if active_view else 0.25)
	for c in controls:
		c["pose"].call(c["node"], float(c["get"].call()))
	var wb: Vector2 = plane.wheel_brakes()
	for p in _pedals:
		var node: Node3D = p[0]
		var ps: float = p[2]
		var push := -ps * clampf(plane.rudder, -1.0, 1.0) * 0.05
		node.position = p[1] + Vector3(0, 0, push)
		var brk: float = wb.x if ps < 0.0 else wb.y
		node.rotation.x = -0.35 * brk
	_compass.text = "%03d" % (int(round(plane.heading_deg())) % 360)


# ------------------------------------------------------------------------------
#  Picking and working the controls
# ------------------------------------------------------------------------------
func _center(c: Dictionary) -> Vector3:
	var node: Node3D = c["node"]
	if c["fixed"]:
		return node.position + c["grip"]
	return node.transform * Vector3(c["grip"])


## The control under a ray (in world space), or -1.
func pick(origin: Vector3, dir: Vector3) -> int:
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := (inv.basis * dir).normalized()
	var best := -1
	var best_t := 2.0
	for i in range(controls.size()):
		var c: Dictionary = controls[i]
		var oc := o - _center(c)
		var r: float = c["radius"]
		var bb := oc.dot(d)
		var cc := oc.length_squared() - r * r
		var disc := bb * bb - cc
		if disc < 0.0:
			continue
		var t := -bb - sqrt(disc)
		if t < 0.0:
			t = -bb + sqrt(disc)
		if t > 0.0 and t < best_t:
			best_t = t
			best = i
	return best


func set_hover(i: int) -> void:
	if i == hover:
		return
	if hover >= 0 and hover < controls.size():
		(controls[hover]["mesh"] as MeshInstance3D).material_overlay = null
	hover = i
	if hover >= 0:
		(controls[hover]["mesh"] as MeshInstance3D).material_overlay = _hl_mat


func hover_text() -> String:
	var i := active if active >= 0 else hover
	if i < 0:
		return ""
	var c: Dictionary = controls[i]
	return c["text"].call(float(c["get"].call()))


func _value(c: Dictionary) -> float:
	return float(c["get"].call())


func _apply(c: Dictionary, v: float, announce: bool) -> void:
	var before := _value(c)
	c["set"].call(v)
	var after := _value(c)
	if announce and absf(after - before) > 0.001:
		clicked.emit()
		said.emit(c["text"].call(after))


func _prime() -> void:
	var e = plane.engine
	if e.running:
		said.emit("Priming does nothing with the engine running.")
		return
	e.prime += 1.0
	_primer_t = 0.7
	clicked.emit()
	said.emit("Primer: %d strokes" % int(round(e.prime)))


## Mouse button down over the hovered control. Returns true when it was used.
func press() -> bool:
	if hover < 0:
		return false
	active = hover
	_drag_acc = 0.0
	var c: Dictionary = controls[active]
	var v := _value(c)
	match c["kind"]:
		"toggle":
			_apply(c, 0.0 if v > 0.5 else 1.0, true)
		"button":
			c["set"].call(1.0)
		"rotary":
			if c["id"] == "mags":
				# From BOTH the key turns on to START and springs back when let go.
				_apply(c, 4.0 if int(v) == 3 else minf(v + 1.0, 3.0), true)
			else:
				_apply(c, fmod(v + 1.0, float(c["steps"])), true)
		"notch":
			_apply(c, fmod(v + 1.0, float(c["steps"])), true)
		"yoke":
			yoke_active = true
			yoke_input = Vector2.ZERO
	return true


## Mouse moved while holding a control. `rel` is in pixels.
func drag(rel: Vector2) -> void:
	if active < 0:
		return
	var c: Dictionary = controls[active]
	match c["kind"]:
		"slide":
			var v := clampf(_value(c) - rel.y * float(c["sens"]) * (float(c["max"]) - float(c["min"])), c["min"], c["max"])
			c["set"].call(v)
		"notch", "rotary":
			if c["id"] == "mags":
				return
			_drag_acc += -rel.y if c["kind"] == "notch" else rel.x
			if absf(_drag_acc) > 26.0:
				var step := signf(_drag_acc)
				_drag_acc = 0.0
				var n := float(c["steps"])
				var v := _value(c) + step
				if c.get("wrap", false):
					v = fposmod(v, n)
				_apply(c, clampf(v, 0.0, n - 1.0), true)
		"yoke":
			yoke_input.x = clampf(yoke_input.x + rel.x * 0.006, -1.0, 1.0)
			yoke_input.y = clampf(yoke_input.y + rel.y * 0.006, -1.0, 1.0)


func release() -> void:
	if active >= 0:
		var c: Dictionary = controls[active]
		if c["id"] == "mags" and int(_value(c)) == 4:
			_apply(c, 3.0, false)
	active = -1
	yoke_active = false
	yoke_input = Vector2.ZERO


## Mouse wheel over a control: fine adjustment, one step at a time.
func wheel(step: int) -> bool:
	if hover < 0:
		return false
	var c: Dictionary = controls[hover]
	var v := _value(c)
	match c["kind"]:
		"slide":
			c["set"].call(clampf(v + 0.025 * float(step) * (float(c["max"]) - float(c["min"])), c["min"], c["max"]))
		"toggle":
			_apply(c, 1.0 if step > 0 else 0.0, true)
		"rotary", "notch":
			var n := float(c["steps"])
			var hi := 3.0 if c["id"] == "mags" else n - 1.0
			var nv := v + float(step)
			if c.get("wrap", false):
				nv = fposmod(nv, n)
			_apply(c, clampf(nv, 0.0, hi), true)
		"button":
			if step > 0:
				c["set"].call(1.0)
	return true


## VR later: a hand holding a control has moved to `hand` (cockpit coordinates).
## Moves the control along its own axis of travel.
func hand_move(i: int, grab_point: Vector3, hand: Vector3, start_value: float) -> void:
	var c: Dictionary = controls[i]
	var axis: Vector3 = c["axis"]
	var along := (hand - grab_point).dot(axis) / float(c["travel"])
	var span := float(c["max"]) - float(c["min"])
	if c["kind"] in ["notch", "rotary"]:
		span = float(c["steps"]) - 1.0
	c["set"].call(clampf(start_value + along * span, c["min"] if c["kind"] == "slide" else 0.0, c["max"] if c["kind"] == "slide" else span))


## Used by the self-test: work every control once.
func exercise() -> int:
	var count := 0
	for i in range(controls.size()):
		set_hover(i)
		press()
		drag(Vector2(10, -40))
		drag(Vector2(-10, 60))
		release()
		wheel(1)
		wheel(-1)
		hover_text()
		count += 1
	set_hover(-1)
	return count
