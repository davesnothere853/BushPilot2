extends Node3D
## A truck's dash (DESIGN_NOTES 95): real gauges with painted faces, cased
## like the plane's (bezel, screws, glass, needle), warning lamps, and a row
## of rocker switches. Each gauge reads a callable every frame.
##
## Local frame: the dash face, +Y up, +Z toward the driver. Gauges are placed
## in metres on that face.

const MeshKit = preload("res://scripts/meshkit.gd")

## A dial face: arc of ticks and numbers, a title, a red band, drawn once.
class Face extends Control:
	var spec := {}
	func _draw() -> void:
		var sz := size.x
		var c := Vector2(sz, sz) * 0.5
		var r := sz * 0.46
		var font := ThemeDB.fallback_font
		draw_circle(c, r * 1.04, Color(0.03, 0.03, 0.035))
		draw_circle(c, r, Color(0.07, 0.07, 0.075))
		var lo: float = spec.get("lo", 0.0)
		var hi: float = spec.get("hi", 100.0)
		var a0: float = deg_to_rad(spec.get("a0", 225.0))
		var a1: float = deg_to_rad(spec.get("a1", -45.0))
		var major: float = spec.get("major", 10.0)
		var minor: float = spec.get("minor", 5.0)
		# red / amber bands
		for band in spec.get("bands", []):
			var b0: float = lerpf(a0, a1, (float(band[0]) - lo) / (hi - lo))
			var b1: float = lerpf(a0, a1, (float(band[1]) - lo) / (hi - lo))
			draw_arc(c, r * 0.86, -b0, -b1, 32, band[2], r * 0.07)
		var v := lo
		while v <= hi + 0.0001:
			var t := (v - lo) / (hi - lo)
			var a := lerpf(a0, a1, t)
			var d := Vector2(cos(a), -sin(a))
			var is_major := absf(fmod(v - lo + 0.0001, major)) < 0.001
			var inner := r * (0.78 if is_major else 0.85)
			draw_line(c + d * inner, c + d * r * 0.93, Color(0.93, 0.93, 0.9), r * (0.035 if is_major else 0.018), true)
			if is_major and spec.get("numbers", true):
				var txt := str(int(round(v * float(spec.get("label_mul", 1.0)))))
				var fs := int(r * 0.2)
				var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, c + d * r * 0.6 - Vector2(tw * 0.5, -fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.93, 0.93, 0.9))
			v += minor
		for lab in spec.get("labels", []):
			var fs2 := int(r * 0.16)
			var tw2 := font.get_string_size(lab[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			var la: float = lerpf(a0, a1, float(lab[1]))
			var d2 := Vector2(cos(la), -sin(la))
			draw_string(font, c + d2 * r * 0.62 - Vector2(tw2 * 0.5, -fs2 * 0.35), lab[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(0.93, 0.93, 0.9))
		var title: String = spec.get("title", "")
		var fs3 := int(r * 0.15)
		var tw3 := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3).x
		draw_string(font, c + Vector2(-tw3 * 0.5, r * 0.42), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3, Color(0.85, 0.85, 0.8))
		var unit: String = spec.get("unit", "")
		if unit != "":
			var tw4 := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs3 * 0.85)).x
			draw_string(font, c + Vector2(-tw4 * 0.5, r * 0.6), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs3 * 0.85), Color(0.7, 0.7, 0.66))


var _needles: Array = []          # [node, Callable -> angle (rad, 0 = up)]
var _lamps: Array = []            # [MeshInstance3D, Callable -> bool, on mat, off mat]
var _switches: Array = []         # [node, Callable -> bool]
var _glass_mat: StandardMaterial3D


func _ready() -> void:
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.8, 0.85, 0.9, 0.04)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.roughness = 0.12
	_glass_mat.metallic_specular = 0.25          # a glint, not a mirror over the dial


## A round gauge at `at` (dash metres), radius r. `value` returns the reading
## in the spec's units.
func gauge(at: Vector2, r: float, spec: Dictionary, value: Callable) -> void:
	var root := Node3D.new()
	root.position = Vector3(at.x, at.y, 0)
	add_child(root)
	var kit := MeshKit.new()
	var rh := r + 0.003
	_lathe(kit, [Vector2(rh, -0.03), Vector2(rh, 0.0)], 32, Color(0.025, 0.025, 0.028))
	_lathe(kit, [Vector2(rh, 0.0), Vector2(rh, 0.005), Vector2(rh + 0.004, 0.008), Vector2(rh + 0.01, 0.007), Vector2(rh + 0.013, 0.0)], 32, Color(0.62, 0.62, 0.64))   # chrome bezel
	for k in range(3):
		var a := PI * 0.5 + TAU * float(k) / 3.0
		var sp := Vector3(cos(a), sin(a), 0) * (rh + 0.008)
		kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), sp + Vector3(0, 0, 0.007)), 0.0022, 0.002, 0.0015, 8, Color(0.3, 0.3, 0.32), true)
	kit.smooth(40.0)
	var mi := kit.instance("Case")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# the face, painted once
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var f := Face.new()
	f.spec = spec
	f.size = Vector2(256, 256)
	vp.add_child(f)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(r * 2.0 / 0.92, r * 2.0 / 0.92)
	q.mesh = qm
	q.position = Vector3(0, 0, -0.012)
	var m := StandardMaterial3D.new()
	m.albedo_texture = vp.get_texture()
	m.emission_enabled = true
	m.emission_texture = vp.get_texture()
	# Faces glow a little (as if lit by the cab's panel lights / daylight
	# through the glass) so they read in the shade under the dash.
	m.emission_energy_multiplier = 0.85
	m.roughness = 0.8
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(q)
	# the needle
	var lo: float = spec.get("lo", 0.0)
	var hi: float = spec.get("hi", 100.0)
	var a0: float = deg_to_rad(spec.get("a0", 225.0))
	var a1: float = deg_to_rad(spec.get("a1", -45.0))
	var nn := Node3D.new()
	nn.position = Vector3(0, 0, -0.006)
	root.add_child(nn)
	var nk := MeshKit.new()
	var ln := r * 0.88
	var w := r * 0.05
	var col := Color(0.95, 0.45, 0.1) if spec.get("orange", false) else Color(0.96, 0.96, 0.92)
	nk.quad(Vector3(-w * 0.5, 0, 0.001), Vector3(w * 0.5, 0, 0.001), Vector3(w * 0.25, ln * 0.85, 0.001), Vector3(-w * 0.25, ln * 0.85, 0.001), col, Vector3.BACK)
	nk.tri(Vector3(-w * 0.25, ln * 0.85, 0.001), Vector3(w * 0.25, ln * 0.85, 0.001), Vector3(0, ln, 0.001), col, Vector3.BACK)
	nk.box_at(Vector3(0, -r * 0.12, 0.0), Vector3(w * 1.6, r * 0.2, 0.002), Color(0.08, 0.08, 0.08))
	nk.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.0)), r * 0.1, r * 0.08, 0.005, 12, Color(0.06, 0.06, 0.06), true)
	var nmi: MeshInstance3D = nk.instance("Needle")
	var nmat := StandardMaterial3D.new()
	nmat.vertex_color_use_as_albedo = true
	nmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED     # the pointer always reads against the face
	nmi.material_override = nmat
	nn.add_child(nmi)
	var angle_of := func() -> float:
		var t := clampf((float(value.call()) - lo) / (hi - lo), 0.0, 1.0)
		return lerpf(a0, a1, t) - PI * 0.5      # 0 = pointing up
	_needles.append([nn, angle_of])
	# glass
	var gl := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = rh
	disc.bottom_radius = rh
	disc.height = 0.0005
	disc.radial_segments = 32
	disc.rings = 1
	gl.mesh = disc
	gl.rotation = Vector3(PI * 0.5, 0, 0)
	gl.position = Vector3(0, 0, 0.004)
	gl.material_override = _glass_mat
	gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(gl)


## A warning lamp: lit when `on` returns true.
func lamp(at: Vector2, col: Color, on: Callable) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.008
	cm.bottom_radius = 0.009
	cm.height = 0.006
	cm.radial_segments = 12
	mi.mesh = cm
	mi.rotation = Vector3(PI * 0.5, 0, 0)
	mi.position = Vector3(at.x, at.y, 0.002)
	var lit := StandardMaterial3D.new()
	lit.albedo_color = col
	lit.emission_enabled = true
	lit.emission = col
	lit.emission_energy_multiplier = 2.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = col.darkened(0.75)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_lamps.append([mi, on, lit, dark])
	var bez := MeshKit.new()
	_lathe(bez, [Vector2(0.011, 0.0), Vector2(0.011, 0.003), Vector2(0.013, 0.0)], 16, Color(0.5, 0.5, 0.52))
	var bm := bez.instance("LampBezel")
	bm.position = Vector3(at.x, at.y, 0)
	add_child(bm)


## A rocker switch with a little label plate: tips up when `on` is true.
func rocker(at: Vector2, label: String, on: Callable) -> void:
	var plate := MeshKit.new()
	plate.box_at(Vector3(at.x, at.y, 0.001), Vector3(0.034, 0.05, 0.002), Color(0.05, 0.05, 0.05))
	add_child(plate.instance("SwitchPlate"))
	var n := Node3D.new()
	n.position = Vector3(at.x, at.y, 0.006)
	add_child(n)
	var k := MeshKit.new()
	k.box_at(Vector3(0, 0.0, 0.0), Vector3(0.022, 0.032, 0.008), Color(0.12, 0.12, 0.12))
	k.box_at(Vector3(0, 0.009, 0.0045), Vector3(0.02, 0.008, 0.001), Color(0.85, 0.3, 0.1))    # lit stripe on the top half
	n.add_child(k.instance("Rocker"))
	_switches.append([n, on])
	var lab := Label3D.new()
	lab.text = label
	lab.font_size = 22
	lab.pixel_size = 0.0004
	lab.position = Vector3(at.x, at.y - 0.035, 0.004)
	lab.modulate = Color(0.85, 0.85, 0.8)
	lab.outline_size = 0
	add_child(lab)


func _process(_delta: float) -> void:
	for nd in _needles:
		var target: float = nd[1].call()
		var cur: float = (nd[0] as Node3D).rotation.z
		(nd[0] as Node3D).rotation.z = lerp_angle(cur, target, 0.25)
	for l in _lamps:
		(l[0] as MeshInstance3D).material_override = l[2] if bool(l[1].call()) else l[3]
	for s in _switches:
		(s[0] as Node3D).rotation.x = -0.28 if bool(s[1].call()) else 0.28


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
