extends Control
## The 3D chart: a raised-relief miniature of the whole island, like a map
## table. Drag to turn it, wheel to zoom in on a valley, middle-drag (or
## shift-drag) to slide it. Airstrips are white bars with names that appear
## as you come in close; lakes keep their names; the red arrow is you.

const EXAG := 1.6                 # relief exaggeration, like a raised map
const CONTOUR := 150.0            # metres between contour lines

var terrain: RefCounted
var plane: Node3D
var hud: Control                  # for target_strip
var wind: Node

var _vp: SubViewport
var _cam: Camera3D
var _root: Node3D
var _ship: Node3D
var _dest: MeshInstance3D
var _labels: Array[Label3D] = []
var _strip_bars: Array[MeshInstance3D] = []
var _built_season := -99
var _built_strips := -1
var _focus := Vector3.ZERO
var _yaw := 0.0
var _pitch := -0.95
var _dist := 26000.0
var _wind_label: Label
var _hint_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.05, 0.86)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var vc := SubViewportContainer.new()
	vc.set_anchors_preset(Control.PRESET_FULL_RECT)
	vc.stretch = true
	vc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true   # our own sky: the island world's fog must not reach the map table
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vc.add_child(_vp)
	_root = Node3D.new()
	_vp.add_child(_root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.74, 0.80)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	_root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-40), 0)
	sun.light_energy = 1.35
	_root.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_cam.near = 60.0
	_cam.far = 120000.0
	_root.add_child(_cam)
	_cam.make_current()
	_wind_label = Label.new()
	_wind_label.position = Vector2(26, 18)
	_wind_label.add_theme_font_size_override("font_size", 15)
	_wind_label.add_theme_color_override("font_color", Color(0.88, 0.85, 0.74))
	add_child(_wind_label)
	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -34.0
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", Color(0.75, 0.73, 0.64))
	add_child(_hint_label)
	visibility_changed.connect(_on_shown)


func _on_shown() -> void:
	if not visible or terrain == null:
		return
	if _built_season != Game.season or _built_strips != terrain.strips.size():
		_build_world()
	if plane != null:
		_focus = Vector3(plane.pos.x, 0, plane.pos.z)
		_yaw = 0.0
	_hint_label.text = "Drag to turn   wheel to zoom   %s or middle-drag to slide   %s to close   %s destination" % [
		"Shift-drag", Game.hint("map"), Game.hint("next_target")]


static func _shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back;
varying float vh;
varying vec3 vcol;
void vertex() { vh = UV.x; vcol = COLOR.rgb; }
void fragment() {
	vec3 c = pow(vcol, vec3(2.2));
	if (vh > 0.5) {
		float f = fract(vh / %.1f);
		float w = clamp(fwidth(vh / %.1f) * 1.4, 0.002, 0.45);
		float line = 1.0 - smoothstep(w, w * 2.2, min(f, 1.0 - f));
		c *= 1.0 - 0.22 * line;
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = vh > 0.5 ? 0.15 : 0.45;
}
""" % [CONTOUR, CONTOUR]
	return sh


func _build_world() -> void:
	for c in _root.get_children():
		if c is MeshInstance3D or c is Label3D or (c is Node3D and c.has_meta("built")):
			c.queue_free()
	_labels.clear()
	_strip_bars.clear()
	_built_season = Game.season
	_built_strips = terrain.strips.size()
	var n: int = terrain.n
	var vn: int = n + 1
	var step: int = maxi(1, int(ceilf(float(n) / 220.0)))
	var side: int = n / step + 1
	var sl: float = terrain.snow_line()
	var frozen: bool = terrain.lakes_frozen()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(side * side)
	cols.resize(side * side)
	uvs.resize(side * side)
	for j in range(side):
		var gz: int = mini(j * step, n)
		var z: float = -terrain.half + gz * terrain.CELL
		for i in range(side):
			var gx: int = mini(i * step, n)
			var x: float = -terrain.half + gx * terrain.CELL
			var h: float = terrain.heights[gz * vn + gx]
			var col: Color
			var y: float = h
			var ch: float = h            # height the contours read
			var wl: float = terrain._water_level(x, z, h)
			if wl > -1.0e8:
				if frozen and wl > 1.0:
					col = Color(0.86, 0.92, 0.96)
				else:
					col = Color(0.55, 0.70, 0.82).lerp(Color(0.40, 0.56, 0.74), clampf((wl - h) / 30.0, 0.0, 1.0))
				y = wl
				ch = -1.0
			else:
				if h > sl:
					col = Color(0.95, 0.95, 0.93)
				elif h < 250.0:
					col = Color(0.80, 0.84, 0.66).lerp(Color(0.88, 0.84, 0.64), h / 250.0)
				elif h < 700.0:
					col = Color(0.88, 0.84, 0.64).lerp(Color(0.80, 0.68, 0.50), (h - 250.0) / 450.0)
				else:
					col = Color(0.80, 0.68, 0.50).lerp(Color(0.62, 0.52, 0.44), clampf((h - 700.0) / 900.0, 0.0, 1.0))
				col = col.lerp(Color(0.56, 0.70, 0.50), float(terrain.forest[gz * vn + gx]) * 0.55)
			var vi: int = j * side + i
			verts[vi] = Vector3(x, maxf(y, 0.0) * EXAG, z)
			cols[vi] = col
			uvs[vi] = Vector2(ch, 0)
	var idx := PackedInt32Array()
	idx.resize((side - 1) * (side - 1) * 6)
	var k := 0
	for j in range(side - 1):
		for i in range(side - 1):
			var a: int = j * side + i
			idx[k] = a
			idx[k + 1] = a + side
			idx[k + 2] = a + 1
			idx[k + 3] = a + 1
			idx[k + 4] = a + side
			idx[k + 5] = a + side + 1
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# Normals from the heights, for the sun to shade the relief.
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	mesh = st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = _shader()
	mi.material_override = mat
	_root.add_child(mi)
	# The sea around the island.
	var sea := MeshInstance3D.new()
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(terrain.size * 1.8, terrain.size * 1.8)
	sea.mesh = pmesh
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.13, 0.22, 0.32)
	smat.roughness = 0.35
	sea.material_override = smat
	sea.position.y = 0.25 * EXAG
	_root.add_child(sea)
	# Airstrips: white bars, names standing over them when you're in close.
	for si in range(terrain.strips.size()):
		var s: Dictionary = terrain.strips[si]
		var p: Vector3 = s["pos"]
		var d: Vector2 = s["dir"]
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(maxf(float(s["length"]), 400.0), 60.0, 170.0)
		bar.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.96, 0.96, 0.94)
		bar.material_override = bmat
		bar.position = Vector3(p.x, p.y * EXAG + 60.0, p.z)
		bar.rotation.y = -atan2(d.y, d.x)
		bar.set_meta("strip", si)
		_root.add_child(bar)
		_strip_bars.append(bar)
		var lb := Label3D.new()
		lb.text = "%s\n%d ft   %d m" % [s["name"], int(p.y * 3.28084), int(s["length"])]
		lb.font_size = 240
		lb.pixel_size = 1.2
		lb.modulate = Color(0.95, 0.93, 0.84)
		lb.outline_size = 56
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.position = bar.position + Vector3(0, 540.0, 0)
		_root.add_child(lb)
		_labels.append(lb)
	# Lakes keep their names.
	for lake in terrain.lakes:
		var c: Vector2 = lake["pos"]
		var ll := Label3D.new()
		ll.text = String(lake["name"])
		ll.font_size = 190
		ll.pixel_size = 1.2
		ll.modulate = Color(0.62, 0.76, 0.90)
		ll.outline_size = 40
		ll.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ll.no_depth_test = true
		ll.position = Vector3(c.x, float(lake.get("level", 2.0)) * EXAG + 260.0, c.y)
		_root.add_child(ll)
		_labels.append(ll)
	# You.
	_ship = Node3D.new()
	_ship.set_meta("built", true)
	var sk := MeshKitScript.new()
	sk.box_at(Vector3(0, 0, 120.0), Vector3(130, 60, 420), Color(0.80, 0.10, 0.06))
	sk.box_at(Vector3(0, 0, 40.0), Vector3(420, 50, 140), Color(0.80, 0.10, 0.06))
	_ship.add_child(sk.instance("You"))
	_root.add_child(_ship)
	# The line to your destination.
	_dest = MeshInstance3D.new()
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.85, 0.12, 0.08)
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dest.material_override = dmat
	_root.add_child(_dest)


const MeshKitScript = preload("res://scripts/meshkit.gd")


func _process(_delta: float) -> void:
	if not visible or _ship == null or plane == null:
		return
	var py: float = terrain.height_at(plane.pos.x, plane.pos.z)
	_ship.position = Vector3(plane.pos.x, maxf(maxf(py, 0.0), plane.pos.y) * EXAG + 220.0, plane.pos.z)
	_ship.rotation.y = -deg_to_rad(plane.heading_deg())
	_ship.scale = Vector3.ONE * clampf(_dist / 9000.0, 0.55, 3.2)
	# Destination line.
	var t: int = hud.target_strip if hud != null else -1
	if t >= 0 and t < terrain.strips.size():
		var tp: Vector3 = terrain.strips[t]["pos"]
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		im.surface_add_vertex(_ship.position)
		im.surface_add_vertex(Vector3(tp.x, tp.y * EXAG + 200.0, tp.z))
		im.surface_end()
		_dest.mesh = im
		_dest.visible = true
	else:
		_dest.visible = false
	for bi in range(_strip_bars.size()):
		var bmat := _strip_bars[bi].material_override as StandardMaterial3D
		bmat.albedo_color = Color(0.85, 0.12, 0.08) if _strip_bars[bi].get_meta("strip") == t else Color(0.96, 0.96, 0.94)
	# Names fade in as you come down toward the table.
	var show_names: bool = _dist < 15000.0
	for lb in _labels:
		lb.visible = show_names
		lb.scale = Vector3.ONE * clampf(_dist / 11000.0, 0.45, 1.35)
	if wind != null:
		var rep: Vector2 = wind.report()
		_wind_label.text = "Wind calm" if rep.y < 0.5 else "Wind from %03d° at %d kt" % [int(rep.x), int(round(rep.y))]
	_update_cam()


func _update_cam() -> void:
	_pitch = clampf(_pitch, -1.45, -0.22)
	_dist = clampf(_dist, 1500.0, 52000.0)
	_focus.x = clampf(_focus.x, -terrain.half * 1.2, terrain.half * 1.2)
	_focus.z = clampf(_focus.z, -terrain.half * 1.2, terrain.half * 1.2)
	var fy: float = maxf(terrain.height_at(_focus.x, _focus.z), 0.0) * EXAG
	var at := Vector3(_focus.x, fy, _focus.z)
	var dir := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Vector3(0, 0, 1)
	var from := at + dir * _dist
	_cam.transform = Transform3D(Basis.looking_at((at - from).normalized(), Vector3.UP), from)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist *= 0.86
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist /= 0.86
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE or (mm.button_mask & MOUSE_BUTTON_MASK_LEFT and mm.shift_pressed):
			var pan := Basis(Vector3.UP, _yaw) * Vector3(-mm.relative.x, 0, -mm.relative.y)
			_focus += pan * _dist * 0.0011
			accept_event()
		elif mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_yaw -= mm.relative.x * 0.008
			_pitch -= mm.relative.y * 0.006
			accept_event()
