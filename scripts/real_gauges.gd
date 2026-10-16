extends Node3D
## The plane cockpit's real instruments (DESIGN_NOTES 188), built anywhere: the
## same HUD-painted dial faces, cased like the Wolverine's (bezel, screws, glass),
## with 3D needles that swing toward their readings with a little lag. Used by
## the cockpit menu; the truck dash can use it too.
##
## Add as a child of a panel (local +Z toward the viewer), then call add():
##   gauges.add("airspeed", Vector3(x, y, 0), 0.044, func(): return knots)
## Ids: airspeed, altimeter (value = feet), vsi (fpm), tach (rpm), clock (hours),
## heading (degrees, card turns), attitude (Vector2(roll, pitch) radians), and
## any engine dial id from panel_layout DIALS (value in the dial's own units).

const HudScript = preload("res://scripts/hud.gd")
const Layout = preload("res://scripts/panel_layout.gd")
const MeshKit = preload("res://scripts/meshkit.gd")

## The HUD only needs a non-null plane to paint a face, and reads a few fields
## while it does (for needles it then skips).
class FaceStub:
	extends Node3D
	var ias_kt := 0.0
	var rpm := 0.0
	func altitude_ft() -> float:
		return 0.0
	func vertical_speed_fpm() -> float:
		return 0.0

var _needles: Array = []           # [node, fn -> degrees, current]
var _cards: Array = []             # [node, fn -> degrees]
var _balls: Array = []             # [ball, pointer, fn -> Vector2(roll, pitch)]
var _glass_mat: StandardMaterial3D
var _stub: FaceStub
var face_glow := 0.85              # dial faces read in the dark


func _init() -> void:
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.albedo_color = Color(0.8, 0.85, 0.9, 0.05)
	_glass_mat.roughness = 0.08
	_glass_mat.metallic_specular = 0.6
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_stub = FaceStub.new()
	add_child(_stub)


func add(id: String, at: Vector3, r: float, value: Callable) -> Node3D:
	var root: Node3D
	match id:
		"airspeed":
			root = _case(at, r, _face(id, 320, false, {}), false)
			_needle(root, r, -0.010 * r / 0.044, "long", func() -> float: return lerpf(30.0, 330.0, clampf(float(value.call()) / 180.0, 0.0, 1.0)))
		"altimeter":
			root = _case(at, r, _face(id, 320, false, {}), false)
			var k := r / 0.044
			_needle(root, r, -0.0115 * k, "thin", func() -> float: return maxf(float(value.call()), 0.0) / 100000.0 * 360.0)
			_needle(root, r, -0.0095 * k, "short", func() -> float: return maxf(float(value.call()), 0.0) / 10000.0 * 360.0)
			_needle(root, r, -0.0075 * k, "long", func() -> float: return fposmod(maxf(float(value.call()), 0.0), 1000.0) / 1000.0 * 360.0)
		"vsi":
			root = _case(at, r, _face(id, 320, false, {}), false)
			_needle(root, r, -0.010 * r / 0.044, "long", func() -> float: return 270.0 + clampf(float(value.call()) / 100.0, -20.0, 20.0) / 20.0 * 165.0)
		"tach":
			root = _case(at, r, _face(id, 320, false, {}), false)
			_needle(root, r, -0.010 * r / 0.044, "long", func() -> float: return lerpf(-130.0, 130.0, clampf(float(value.call()) / 3000.0, 0.0, 1.0)))
		"clock":
			root = _case(at, r, _face(id, 256, false, {}), false, 0.022)
			_needle(root, r, -0.010, "short", func() -> float: return fposmod(float(value.call()), 12.0) / 12.0 * 360.0)
			_needle(root, r, -0.008, "long", func() -> float: return fposmod(float(value.call()) * 60.0, 60.0) / 60.0 * 360.0)
		"heading":
			root = _case(at, r, null, false)
			var card := Node3D.new()
			root.add_child(card)
			card.add_child(_dial_quad(r, _face(id, 320, false, {}), false, -0.014))
			var fk := MeshKit.new()
			var wcol := Color(0.92, 0.92, 0.88)
			fk.box_at(Vector3(0, r * 0.88, -0.006), Vector3(r * 0.04, r * 0.24, 0.002), Color(1.0, 0.55, 0.1))
			fk.box_at(Vector3(0, 0, -0.006), Vector3(r * 0.06, r * 0.55, 0.002), wcol)
			fk.box_at(Vector3(0, r * 0.06, -0.006), Vector3(r * 0.55, r * 0.06, 0.002), wcol)
			fk.box_at(Vector3(0, -r * 0.22, -0.006), Vector3(r * 0.22, r * 0.05, 0.002), wcol)
			var fixed := fk.instance("Lubber")
			fixed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(fixed)
			_cards.append([card, value])
		"attitude":
			root = _case(at, r, null, false, 0.075)
			var R := r * 1.18
			var bk := MeshKit.new()
			var bands := [[-90.0, -21.0, "g"], [-21.0, -19.0, "w"], [-19.0, -11.0, "g"], [-11.0, -9.0, "w"], [-9.0, -0.9, "g"], [-0.9, 0.9, "w"],
				[0.9, 9.0, "s"], [9.0, 11.0, "w"], [11.0, 19.0, "s"], [19.0, 21.0, "w"], [21.0, 90.0, "s"]]
			var sky := Color(0.20, 0.45, 0.78)
			var ground := Color(0.42, 0.27, 0.13)
			for band in bands:
				var steps := maxi(1, int((float(band[1]) - float(band[0])) / 7.5))
				for kk in range(steps):
					var la := deg_to_rad(lerpf(band[0], band[1], float(kk) / float(steps)))
					var lb := deg_to_rad(lerpf(band[0], band[1], float(kk + 1) / float(steps)))
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
			var ball := Node3D.new()
			ball.position = Vector3(0, 0, -0.006 - R)
			var ball_mi := bk.instance("Ball")
			ball_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ball.add_child(ball_mi)
			root.add_child(ball)
			root.add_child(_dial_quad(r, _face(id, 320, true, {}), true, -0.004))
			var ptr := Node3D.new()
			ptr.position = Vector3(0, 0, -0.0035)
			var pk := MeshKit.new()
			pk.tri(Vector3(-r * 0.07, r * 0.70, 0), Vector3(r * 0.07, r * 0.70, 0), Vector3(0, r * 0.84, 0), Color(1.0, 0.55, 0.1), Vector3.BACK)
			ptr.add_child(pk.instance("Pointer"))
			root.add_child(ptr)
			var ak := MeshKit.new()
			var orange := Color(1.0, 0.55, 0.1)
			ak.box_at(Vector3(-r * 0.42, 0, -0.002), Vector3(r * 0.38, r * 0.06, 0.003), orange)
			ak.box_at(Vector3(r * 0.42, 0, -0.002), Vector3(r * 0.38, r * 0.06, 0.003), orange)
			ak.box_at(Vector3(-r * 0.23, -r * 0.06, -0.002), Vector3(r * 0.05, r * 0.14, 0.003), orange)
			ak.box_at(Vector3(r * 0.23, -r * 0.06, -0.002), Vector3(r * 0.05, r * 0.14, 0.003), orange)
			var sym := ak.instance("Symbol")
			sym.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(sym)
			_balls.append([ball, ptr, value])
		_:
			var spec: Dictionary = Layout.DIALS.get(id, {})
			if spec.is_empty():
				return null
			root = _case(at, r, _face(id, 224, false, {}), false, 0.022)
			var lo: float = spec["lo"]
			var hi: float = spec["hi"]
			var a0d: float = spec["a0"]
			var a1d: float = spec["a1"]
			_needle(root, r, -0.009 * r / 0.026, "long", func() -> float: return lerpf(a0d, a1d, clampf((float(value.call()) - lo) / (hi - lo), 0.0, 1.0)))
	return root


func _process(delta: float) -> void:
	var k := clampf(delta * 8.0, 0.0, 1.0)
	for nd in _needles:
		var target: float = nd[1].call()
		nd[2] = lerpf(nd[2], target, k)
		(nd[0] as Node3D).rotation.z = -deg_to_rad(nd[2])
	for cd in _cards:
		(cd[0] as Node3D).rotation.z = deg_to_rad(float(cd[1].call()))
	for bl in _balls:
		var rp: Vector2 = bl[2].call()
		(bl[0] as Node3D).basis = Basis(Vector3.BACK, rp.x) * Basis(Vector3.RIGHT, clampf(rp.y * 1.4, -1.2, 1.2))
		(bl[1] as Node3D).rotation.z = rp.x


# ------------------------------------------------------------------------------
#  Builders (after cockpit.gd)
# ------------------------------------------------------------------------------
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


func _face(id: String, size_px: int, transparent: bool, spec: Dictionary) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(size_px, size_px)
	vp.disable_3d = true
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var h: Control = HudScript.new()
	h.plane = _stub
	h.face_id = id
	if not spec.is_empty():
		h.face_spec = spec
	h.cockpit_mode = true
	h.show_help = false
	h.face_scale = float(size_px) / (2.0 * (Layout.GAUGE_R + 9.0))
	vp.add_child(h)
	h.set_process(false)
	h.queue_redraw()
	return vp.get_texture()


func _case(at: Vector3, r: float, face_tex: Texture2D, face_alpha: bool, deep: float = 0.03) -> Node3D:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var kit := MeshKit.new()
	var rh := r + 0.0025
	_lathe(kit, [Vector2(rh, -deep), Vector2(rh, 0.0)], 32, Color(0.025, 0.025, 0.028))
	_lathe(kit, [Vector2(rh, 0.0), Vector2(rh, 0.004), Vector2(rh + 0.003, 0.0065), Vector2(rh + 0.008, 0.006), Vector2(rh + 0.011, 0.0)], 32, Color(0.06, 0.06, 0.065))
	for k in range(4):
		var a := PI * 0.25 + PI * 0.5 * float(k)
		var p := Vector3(cos(a), sin(a), 0) * ((rh + 0.015) if r > 0.035 else (rh + 0.010))
		kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p), 0.0028, 0.0024, 0.002, 8, Color(0.42, 0.42, 0.44), true)
		kit.box(Transform3D(Basis(Vector3.BACK, a), p + Vector3(0, 0, 0.0021)), Vector3(0.0045, 0.0007, 0.0004), Color(0.08, 0.08, 0.08))
	kit.smooth(40.0)
	var mi := kit.instance("Case")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if face_tex != null:
		root.add_child(_dial_quad(r, face_tex, face_alpha, -0.014))
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
	m.emission_energy_multiplier = face_glow
	m.roughness = 0.8
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return q


func _needle(parent: Node3D, r: float, z: float, kind: String, fn: Callable, col: Color = Color(0.95, 0.95, 0.92)) -> void:
	var node := Node3D.new()
	node.position = Vector3(0, 0, z)
	parent.add_child(node)
	var kit := MeshKit.new()
	var length := r * (0.92 if kind != "short" else 0.58)
	var w := r * (0.045 if kind == "long" else (0.085 if kind == "short" else 0.025))
	var t := 0.0012
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
	nmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = nmat
	node.add_child(mi)
	_needles.append([node, fn, fn.call()])
