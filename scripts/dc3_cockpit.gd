extends "res://scripts/cockpit.gd"
## The DC-3 flight deck, built to true scale in the DC-3's own coordinates
## (see dc3_visual.gd): two leather seats, control columns with the open
## "ram's horn" wheels, a wide crinkle-black panel with the captain's flight
## instruments, the twin engine instruments in the middle (two needles each,
## 1 = left engine, 2 = right) and the first officer's set, a pedestal with
## props, throttles and mixtures, the big trim wheel, an overhead switch panel,
## sliding side windows and the bulkhead with its door to the cabin.
## Uses the same gauges as the Wolverine (cockpit.gd) and the PBR materials
## in pbr.gd. Everything is reachable by pointing (mouse ray now, VR hand later).

const Pbr = preload("res://scripts/pbr.gd")
const Shape = preload("res://scripts/dc3_shape.gd")
const Cabin = preload("res://scripts/dc3_cabin.gd")

const FLOOR_Y := -0.55
const PANEL_Z := -6.52
const PANEL_TILT := 0.21          # radians the panel leans back at the top
const EYE := Vector3(-0.45, 0.80, -5.86)
const BULKHEAD_Z := -4.80
const SEAT_X := 0.45

const INTERIOR := Color(0.52, 0.57, 0.52)      # grey-green paint
const INTERIOR_DK := Color(0.33, 0.36, 0.33)
const LEATHER := Color(0.36, 0.20, 0.11)
const RUBBER := Color(0.10, 0.10, 0.10)
const ALU := Color(0.62, 0.63, 0.64)
const CRINKLE := Color(0.075, 0.075, 0.075)
const WHITE := Color(0.92, 0.90, 0.85)

var _panel_xf := Transform3D.IDENTITY


func build(p: Node3D, terrain: RefCounted) -> void:
	plane = p
	_hl_mat = StandardMaterial3D.new()
	_hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hl_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_hl_mat.albedo_color = Color(1.0, 0.75, 0.3, 0.35)
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.albedo_color = Color(0.8, 0.85, 0.9, 0.07)
	_glass_mat.roughness = 0.03
	_glass_mat.metallic_specular = 1.0
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# A hidden copy of the HUD, for things the instruments ask it (bearing to a strip).
	var vp := SubViewport.new()
	vp.size = Vector2i(8, 8)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	panel_hud = HudScript.new()
	panel_hud.plane = plane
	panel_hud.terrain = terrain
	panel_hud.cockpit_mode = true
	panel_hud.show_help = false
	vp.add_child(panel_hud)
	panel_hud.set_process(false)
	_panel_xf = Transform3D(Basis(Vector3.RIGHT, -PANEL_TILT), Vector3(0, 0.50, PANEL_Z))
	_build_shell()
	Cabin.build(self)
	_build_panel(terrain)
	_build_controls()
	_build_yokes_and_pedals()
	# A light in the cabin roof so the flight deck isn't black on a dull day.
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 1.05, -5.6)
	lamp.light_energy = 0.7
	lamp.omni_range = 3.5
	lamp.shadow_enabled = false
	add_child(lamp)
	set_active(false)


func _mesh(kit: RefCounted, mat: Material, node_name: String) -> MeshInstance3D:
	var mi: MeshInstance3D = kit.instance(node_name)
	mi.material_override = mat
	add_child(mi)
	return mi


## The inside of the skin at angle `a` (0 = right side, PI/2 = top) and station z.
static func _skin(a: float, z: float, inset: float = 0.07) -> Vector3:
	return Shape.point(a, z, inset)


## A cushion: a box with rounded edges (sections with rounded corners lofted
## front to back, the ends rounded in).
static func _soft_box(kit: RefCounted, xf: Transform3D, size: Vector3, r: float, col: Color) -> void:
	var h := size * 0.5
	var rings: Array = []
	var steps := [[-h.z, r * 0.55], [-h.z + r * 0.3, r * 0.15], [-h.z + r, 0.0], [h.z - r, 0.0], [h.z - r * 0.3, r * 0.15], [h.z, r * 0.55]]
	for st in steps:
		var z: float = st[0]
		var shrink: float = st[1]
		var ring := PackedVector3Array()
		var hx: float = h.x - shrink
		var hy: float = h.y - shrink
		var rr := minf(r, minf(hx, hy) * 0.95)
		var corners := [Vector2(hx - rr, hy - rr), Vector2(-hx + rr, hy - rr), Vector2(-hx + rr, -hy + rr), Vector2(hx - rr, -hy + rr)]
		for ci in range(4):
			for k in range(4):
				var a := PI * 0.5 * float(ci) + PI * 0.5 * float(k) / 3.0
				var c2: Vector2 = corners[ci]
				ring.append(xf * Vector3(c2.x + cos(a) * rr, c2.y + sin(a) * rr, z))
		rings.append(ring)
	kit.loft(rings, col, true, true)


## The angle round the section where the skin is at height y (on side s).
static func _side_angle(s: float, y: float) -> float:
	var a := asin(clampf((y - 0.07) / 1.40, -1.0, 1.0))
	return a if s > 0.0 else PI - a


# ------------------------------------------------------------------------------
#  Shell: skin, frames, floor, bulkhead, seats
# ------------------------------------------------------------------------------
func _build_shell() -> void:
	var skin := MeshKit.new()
	var frames := MeshKit.new()
	var floor_k := MeshKit.new()
	var leather := MeshKit.new()
	var metal := MeshKit.new()
	# Inside of the skin, above the floor, from the nose bulkhead back to the cabin
	# bulkhead, leaving the windows open.
	var na := 128
	var zs: Array[float] = []
	var z := -7.0
	while z < BULKHEAD_Z + 0.001:
		zs.append(z)
		z += 0.03 if z < -5.3 else 0.08
	# Window edges land exactly on the side window rows (see dc3_shape SECTORS).
	for wz in [Shape.SIDE_WIN[0], Shape.SIDE_WIN[1]]:
		zs.append(wz)
	zs.sort()
	var nr := Shape.ring_size()
	for zi in range(zs.size() - 1):
		var r0: PackedFloat32Array = Shape.ring_angles(zs[zi], 0.07)
		var r1: PackedFloat32Array = Shape.ring_angles(zs[zi + 1], 0.07)
		var zmid := (zs[zi] + zs[zi + 1]) * 0.5
		for k in range(nr):
			var k1 := (k + 1) % nr
			var p00 := _skin(r0[k], zs[zi])
			var p01 := _skin(r0[k1] if k1 > 0 else r0[0] + TAU, zs[zi])
			var p10 := _skin(r1[k], zs[zi + 1])
			var p11 := _skin(r1[k1] if k1 > 0 else r1[0] + TAU, zs[zi + 1])
			var mid := (p00 + p11) * 0.5
			if mid.y < FLOOR_Y:
				continue
			if Shape.sector_of(k) == "win" and Shape.in_side_window_z(zmid):
				continue
			if zmid < -6.3 and Shape.is_glass(mid):
				continue
			var shade := INTERIOR if mid.y > 0.15 else INTERIOR_DK
			skin.quad(p00, p01, p11, p10, shade, Vector3(-mid.x, -(mid.y - 0.06), 0))
	# Ribs (frames) round the skin: smooth channels standing in from the skin,
	# broken only where a window is.
	for fz in [-6.45, -5.40, -4.95]:
		var ra: PackedFloat32Array = Shape.ring_angles(fz, 0.07)
		var nr2 := ra.size()
		for k in range(nr2):
			var k1 := (k + 1) % nr2
			var a0: float = ra[k]
			var a1: float = ra[k1] if k1 > 0 else ra[0] + TAU
			var o0 := _skin(a0, fz, 0.07)
			var o1 := _skin(a1, fz, 0.07)
			var i0 := _skin(a0, fz, 0.13)
			var i1 := _skin(a1, fz, 0.13)
			var mid4 := (o0 + i1) * 0.5
			if mid4.y < FLOOR_Y or (Shape.sector_of(k) == "win" and Shape.in_side_window_z(fz)) or Shape.is_glass(mid4):
				continue
			var dz := Vector3(0, 0, 0.025)
			frames.quad(o0 - dz, o1 - dz, i1 - dz, i0 - dz, INTERIOR_DK, Vector3.FORWARD)
			frames.quad(o0 + dz, o1 + dz, i1 + dz, i0 + dz, INTERIOR_DK, Vector3.BACK)
			frames.quad(i0 - dz, i1 - dz, i1 + dz, i0 + dz, INTERIOR_DK, -(mid4 - Vector3(0, 0.06, fz)))
	# Window frames: the windscreen posts, sill and top bars, and the sliding
	# window rails, just inside the glass.
	var fi := 0.055
	var c0: Vector3 = Shape.SILL_C
	var c1: Vector3 = Shape.TOP_C
	for side in [-1.0, 1.0]:
		var o0 := Vector3(Shape.SILL_O.x * side, Shape.SILL_O.y, Shape.SILL_O.z)
		var o1 := Vector3(Shape.TOP_O.x * side, Shape.TOP_O.y, Shape.TOP_O.z)
		var n: Vector3 = Shape.pane_plane(side)[0]
		var off := -n * fi
		Shape.pane_frame(frames, side, -0.082, 0.08, INTERIOR_DK, false)
		_beam(frames, c0 + off, c1 + off, 0.016, INTERIOR_DK, 8)
		_beam(frames, o0 + off, o1 + off, 0.02, INTERIOR_DK, 8)
		_beam(frames, c0 + off, o0 + off, 0.02, INTERIOR_DK, 8)
		_beam(frames, c1 + off, o1 + off, 0.02, INTERIOR_DK, 8)
		for wy in [Shape.SIDE_WIN[2], Shape.SIDE_WIN[3]]:
			var a := _side_angle(side, wy)
			_beam(metal, _skin(a, Shape.SIDE_WIN[0], 0.075), _skin(a, Shape.SIDE_WIN[1], 0.075), 0.014, ALU, 8)
		for wz in [Shape.SIDE_WIN[0], Shape.SIDE_WIN[1]]:
			_beam(frames, _skin(_side_angle(side, Shape.SIDE_WIN[2]), wz, 0.075), _skin(_side_angle(side, Shape.SIDE_WIN[3]), wz, 0.075), 0.022, INTERIOR_DK, 8)
		# Window handle
		var h := _skin(_side_angle(side, 0.72), -5.52, 0.1)
		metal.box_at(h, Vector3(0.03, 0.12, 0.03), ALU)
	# Floor, with a raised step under the seats, and the rudder pedal wells.
	floor_k.quad(Vector3(-1.05, FLOOR_Y, -6.9), Vector3(1.05, FLOOR_Y, -6.9), Vector3(1.15, FLOOR_Y, BULKHEAD_Z), Vector3(-1.15, FLOOR_Y, BULKHEAD_Z), RUBBER, Vector3.UP)
	# The bulkhead and the cabin behind it are built by dc3_cabin.gd.

	_beam(frames, Vector3(-0.32, FLOOR_Y, BULKHEAD_Z - 0.03), Vector3(-0.32, 1.12, BULKHEAD_Z - 0.03), 0.03, INTERIOR_DK)
	_beam(frames, Vector3(0.32, FLOOR_Y, BULKHEAD_Z - 0.03), Vector3(0.32, 1.12, BULKHEAD_Z - 0.03), 0.03, INTERIOR_DK)
	_beam(frames, Vector3(-0.32, 1.12, BULKHEAD_Z - 0.03), Vector3(0.32, 1.12, BULKHEAD_Z - 0.03), 0.03, INTERIOR_DK)
	# Radio rack behind the first officer.
	metal.box_at(Vector3(0.82, -0.05, -5.05), Vector3(0.45, 1.0, 0.4), Color(0.18, 0.18, 0.17))
	for ry in [0.25, 0.0, -0.25]:
		metal.box_at(Vector3(0.82, ry, -5.27), Vector3(0.40, 0.18, 0.02), Color(0.10, 0.10, 0.10))
		metal.box_at(Vector3(0.70, ry, -5.29), Vector3(0.03, 0.03, 0.02), WHITE)
	# Seats: leather cushions and backs on aluminium frames, with lap belts.
	for side in [-1.0, 1.0]:
		var sx: float = side * SEAT_X
		metal.box_at(Vector3(sx, FLOOR_Y + 0.17, -5.78), Vector3(0.36, 0.34, 0.38), Color(0.30, 0.31, 0.30))
		_soft_box(leather, Transform3D(Basis.IDENTITY, Vector3(sx, -0.06, -5.80)), Vector3(0.48, 0.13, 0.48), 0.05, LEATHER)
		_soft_box(leather, Transform3D(Basis(Vector3.RIGHT, -0.16), Vector3(sx, 0.32, -5.52)), Vector3(0.48, 0.66, 0.13), 0.055, LEATHER)
		_soft_box(leather, Transform3D(Basis(Vector3.RIGHT, -0.16), Vector3(sx, 0.76, -5.45)), Vector3(0.28, 0.18, 0.12), 0.05, LEATHER.darkened(0.1))
		# Tufted seams across the back
		for ty in [0.12, 0.32, 0.52]:
			leather.box(Transform3D(Basis(Vector3.RIGHT, -0.16), Vector3(sx, ty, -5.585 + (ty - 0.32) * 0.16)), Vector3(0.44, 0.008, 0.004), LEATHER.darkened(0.35))
		for ax in [-0.27, 0.27]:
			metal.box_at(Vector3(sx + ax, 0.12, -5.72), Vector3(0.05, 0.04, 0.38), ALU)
			_beam(metal, Vector3(sx + ax, -0.08, -5.55), Vector3(sx + ax, 0.12, -5.55), 0.012, ALU)
		frames.box(Transform3D(Basis(Vector3.BACK, 0.4 * side), Vector3(sx, -0.015, -5.68)), Vector3(0.06, 0.006, 0.50), Color(0.45, 0.42, 0.33))
	_mesh(skin, Pbr.painted(), "Skin")
	_mesh(frames, Pbr.paint_smooth(), "Frames")
	_mesh(floor_k, Pbr.floor_mat(), "Floor")
	_mesh(leather, Pbr.leather(), "Seats")
	_mesh(metal, Pbr.metal(), "Metal")
	# The magnetic compass on the windscreen centre post.
	var ck := MeshKit.new()
	ck.box_at(Vector3(0, 1.10, -6.55), Vector3(0.09, 0.07, 0.08), Color(0.06, 0.06, 0.06))
	_mesh(ck, Pbr.bakelite(), "Compass")
	_compass = Label3D.new()
	_compass.font_size = 32
	_compass.pixel_size = 0.0006
	_compass.modulate = Color(0.95, 0.92, 0.80)
	_compass.outline_size = 0
	_compass.position = Vector3(0, 1.10, -6.509)
	add_child(_compass)


# ------------------------------------------------------------------------------
#  Panel and instruments
# ------------------------------------------------------------------------------
## Panel coordinates: x right of centre, y down from the top edge, metres.
func _on_panel(px: Vector2, out: float = 0.0) -> Transform3D:
	return _panel_xf * Transform3D(Basis.IDENTITY, Vector3(px.x, -px.y, out))


func _case(px: Vector2, r: float, face_tex: Texture2D, face_alpha: bool, deep: float = 0.03) -> Node3D:
	var root: Node3D = super._case(px, r, face_tex, face_alpha, deep)
	root.transform = _on_panel(px)
	return root


func _spec_face(id: String, spec: Dictionary, size_px: int) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(size_px, size_px)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var h: Control = HudScript.new()
	h.plane = plane
	h.face_id = id
	h.face_spec = spec
	h.cockpit_mode = true
	h.show_help = false
	h.face_scale = float(size_px) / (2.0 * (Layout.GAUGE_R + 9.0))
	vp.add_child(h)
	h.size = Vector2(size_px, size_px)
	h.set_process(false)
	h.queue_redraw()
	return vp.get_texture()


## An engine instrument with two needles: "1" white for the left engine, "2"
## yellow for the right, like the real dual gauges.
func _dual(id: String, spec: Dictionary, px: Vector2, r: float, value: Callable) -> void:
	var root := _case(px, r, _spec_face(id, spec, 256), false, 0.025)
	var lo: float = spec["lo"]
	var hi: float = spec["hi"]
	var a0: float = spec["a0"]
	var a1: float = spec["a1"]
	for ei in range(2):
		var col := Color(0.95, 0.95, 0.92) if ei == 0 else Color(0.98, 0.80, 0.25)
		var e_i := ei
		_needle(root, r, -0.010 + 0.002 * ei, "long", func() -> float:
			var es: Array = plane.engines()
			var e = es[mini(e_i, es.size() - 1)]
			return lerpf(a0, a1, clampf((float(value.call(e)) - lo) / (hi - lo), 0.0, 1.0)), col)


func _label(text: String, px: Vector2, size: int = 22) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0004
	l.modulate = WHITE
	l.outline_size = 0
	l.transform = _on_panel(px, 0.002)
	add_child(l)


func _build_panel(_terrain: RefCounted) -> void:
	# The panel face: crinkle-black, with holes for every instrument.
	var w := 1.90
	var h := 0.62
	var holes: Array[Vector4] = []
	var instruments := []       # [kind, id, panel position, radius]
	var big := Layout.SIX_R
	var sm := 0.030
	# Captain (left): the basic six, in the old "T".
	instruments.append(["six", "airspeed", Vector2(-0.62, 0.12), big])
	instruments.append(["six", "attitude", Vector2(-0.45, 0.12), big])
	instruments.append(["six", "vsi", Vector2(-0.28, 0.12), big])
	instruments.append(["six", "altimeter", Vector2(-0.62, 0.30), big])
	instruments.append(["six", "heading", Vector2(-0.45, 0.30), big])
	instruments.append(["six", "tach", Vector2(-0.28, 0.30), big])
	# Engines (middle): dual manifold pressure and dual rpm on top, then the
	# small dual dials.
	instruments.append(["dual", "map2", Vector2(-0.08, 0.12), big])
	instruments.append(["dual", "rpm2", Vector2(0.08, 0.12), big])
	instruments.append(["dual", "oilp2", Vector2(-0.12, 0.28), sm])
	instruments.append(["dual", "oilt2", Vector2(-0.04, 0.28), sm])
	instruments.append(["dual", "fuelp2", Vector2(0.04, 0.28), sm])
	instruments.append(["dual", "cht2", Vector2(0.12, 0.28), sm])
	instruments.append(["dual", "fuel2", Vector2(0.0, 0.42), sm])
	# First officer (right): airspeed, altimeter, climb, and the clock.
	instruments.append(["six", "airspeed", Vector2(0.30, 0.12), big])
	instruments.append(["six", "vsi", Vector2(0.47, 0.12), big])
	instruments.append(["six", "altimeter", Vector2(0.30, 0.30), big])
	instruments.append(["clock", "clock", Vector2(0.47, 0.30), Layout.CLOCK_R])
	for ins in instruments:
		var pp: Vector2 = ins[2]
		var rr: float = ins[3] + 0.0025
		holes.append(Vector4((pp.x + w * 0.5) / w, pp.y / h, rr / w, rr / h))
	while holes.size() < 40:
		holes.append(Vector4(-1, -1, 0.0001, 0.0001))
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	face.mesh = quad
	face.transform = _on_panel(Vector2(0, h * 0.5))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/panel.gdshader")
	mat.set_shader_parameter("panel_tex", _crinkle_tex())
	mat.set_shader_parameter("holes", holes)
	mat.set_shader_parameter("hole_count", 40)
	mat.set_shader_parameter("glow", 0.0)
	face.material_override = mat
	add_child(face)
	# Behind the face: a box so nothing shows through round the instruments.
	var back := MeshKit.new()
	# Narrower than the face: the nose skin closes in behind the panel top,
	# and a full-width box here pokes through beside the windscreen.
	back.box(_on_panel(Vector2(0, h * 0.5), -0.17), Vector3(w - 0.20, h + 0.04, 0.10), CRINKLE)
	# The sides of the panel, closing the gap back to the box.
	for ex in [-1.0, 1.0]:
		back.box(_on_panel(Vector2(ex * (w * 0.5 + 0.01), h * 0.5), -0.07), Vector3(0.02, h + 0.04, 0.14), CRINKLE)
	back.box(_on_panel(Vector2(0, h + 0.01), -0.07), Vector3(w + 0.04, 0.02, 0.14), CRINKLE)
	# The glareshield hood over the top, padded.
	back.box(_panel_xf * Transform3D(Basis(Vector3.RIGHT, PANEL_TILT + 0.08), Vector3(0, 0.05, -0.05)), Vector3(1.58, 0.04, 0.24), Color(0.05, 0.05, 0.05))
	# The coaming: a padded shelf from the panel top forward to the foot of
	# the windscreen, cut to the hull at every station so it can never poke
	# through the nose skin (each strip stays a hand's width inside it).
	var czs := [-6.55, -6.70, -6.85, -7.00]
	var prev_edge: Array = []
	for cz in czs:
		var sct: Array = Shape.section(cz)
		var cy2: float = 0.582 + (cz + 6.55) * -0.09
		var frac: float = clampf((cy2 + 0.04 - float(sct[3])) / float(sct[2]), -1.0, 0.995)
		var hwz: float = maxf(float(sct[1]) * sqrt(maxf(1.0 - frac * frac, 0.0)) - 0.07, 0.12)
		var cur_edge := [Vector3(-hwz, cy2, cz), Vector3(hwz, cy2, cz)]
		if not prev_edge.is_empty():
			back.quad(prev_edge[0], prev_edge[1], cur_edge[1], cur_edge[0], Color(0.05, 0.05, 0.05), Vector3.UP)
			var dn := Vector3(0, -0.05, 0)
			back.quad(prev_edge[1] + dn, prev_edge[0] + dn, cur_edge[0] + dn, cur_edge[1] + dn, Color(0.04, 0.04, 0.04), Vector3.DOWN)
			# The sides, closing the pad.
			for side_i in [0, 1]:
				var a2: Vector3 = prev_edge[side_i]
				var b2: Vector3 = cur_edge[side_i]
				var n2 := Vector3(-1.0 if side_i == 0 else 1.0, 0, 0)
				if side_i == 0:
					back.quad(a2, b2, b2 + dn, a2 + dn, Color(0.045, 0.045, 0.045), n2)
				else:
					back.quad(b2, a2, a2 + dn, b2 + dn, Color(0.045, 0.045, 0.045), n2)
		prev_edge = cur_edge
	_mesh(back, Pbr.crinkle(), "PanelBack")
	for ins in instruments:
		var kind: String = ins[0]
		var id: String = ins[1]
		var pp2: Vector2 = ins[2]
		match kind:
			"six":
				_flight_instrument(id, pp2)
			"clock":
				var root := _case(pp2, Layout.CLOCK_R, _face_texture("clock", 256, false), false, 0.022)
				_needle(root, Layout.CLOCK_R, -0.010, "short", func() -> float: return fposmod(float(Game.time_of_day), 12.0) / 12.0 * 360.0)
				_needle(root, Layout.CLOCK_R, -0.008, "long", func() -> float: return fposmod(float(Game.time_of_day) * 60.0, 60.0) / 60.0 * 360.0)
			"dual":
				_dual_for(id, pp2, ins[3])
	# Placards
	_label("CAPTAIN", Vector2(-0.45, 0.43), 20)
	_label("ENGINES  1 - LEFT   2 - RIGHT", Vector2(0.0, 0.52), 18)
	_label("FIRST OFFICER", Vector2(0.38, 0.43), 20)
	_label("DC-3", Vector2(-0.80, 0.55), 16)


func _dual_for(id: String, px: Vector2, r: float) -> void:
	match id:
		"map2":
			_dual(id, {"title": "MAN PRESS", "lo": 10.0, "hi": 50.0, "a0": -135.0, "a1": 135.0, "minor": 40,
				"labels": [[10, "10"], [20, "20"], [30, "30"], [40, "40"], [50, "50"]], "zones": [[20.0, 42.0, "g"]]},
				px, r, func(e) -> float: return e.map_inhg)
		"rpm2":
			_dual(id, {"title": "RPM x100", "lo": 0.0, "hi": 3000.0, "a0": -135.0, "a1": 135.0, "minor": 30,
				"labels": [[0, "0"], [10, "10"], [20, "20"], [30, "30"]], "zones": [[1700.0, 2550.0, "g"], [2600.0, 3000.0, "r"]]},
				px, r, func(e) -> float: return e.rpm)
		"oilp2":
			_dual(id, {"title": "OIL PSI", "lo": 0.0, "hi": 120.0, "a0": -120.0, "a1": 120.0, "minor": 12,
				"labels": [[0, "0"], [60, "60"], [120, "120"]], "zones": [[60.0, 90.0, "g"]]},
				px, r, func(e) -> float: return e.oil_press)
		"oilt2":
			_dual(id, {"title": "OIL °C", "lo": 0.0, "hi": 120.0, "a0": -120.0, "a1": 120.0, "minor": 12,
				"labels": [[0, "0"], [60, "60"], [120, "120"]], "zones": [[40.0, 85.0, "g"], [100.0, 120.0, "r"]]},
				px, r, func(e) -> float: return e.oil_temp)
		"fuelp2":
			_dual(id, {"title": "FUEL PSI", "lo": 0.0, "hi": 25.0, "a0": -120.0, "a1": 120.0, "minor": 10,
				"labels": [[0, "0"], [10, "10"], [20, "20"]], "zones": [[14.0, 18.0, "g"]]},
				px, r, func(e) -> float: return 16.0 if e.running else (4.0 if e.master else 0.0))
		"cht2":
			_dual(id, {"title": "CYL °C", "lo": 0.0, "hi": 300.0, "a0": -120.0, "a1": 120.0, "minor": 12,
				"labels": [[0, "0"], [150, "150"], [300, "300"]], "zones": [[120.0, 232.0, "g"], [260.0, 300.0, "r"]]},
				px, r, func(e) -> float: return e.cht)
		"fuel2":
			_dual(id, {"title": "FUEL GAL", "lo": 0.0, "hi": 1.0, "a0": -100.0, "a1": 100.0, "minor": 8,
				"labels": [[0, "E"], [0.5, "1/2"], [1, "F"]], "zones": [[0.0, 0.1, "r"]]},
				px, r, func(e) -> float: return e.total_fuel() / maxf(e.tank_capacity * 2.0, 1.0))


static var _crinkle_cache: ImageTexture

static func _crinkle_tex() -> ImageTexture:
	if _crinkle_cache != null:
		return _crinkle_cache
	var n := FastNoiseLite.new()
	n.frequency = 0.25
	var img := Image.create(512, 168, false, Image.FORMAT_RGB8)
	for y in range(168):
		for x in range(512):
			var v := 0.055 + 0.03 * n.get_noise_2d(x, y)
			img.set_pixel(x, y, Color(v, v, v * 1.02))
	img.generate_mipmaps()
	_crinkle_cache = ImageTexture.create_from_image(img)
	return _crinkle_cache


# ------------------------------------------------------------------------------
#  Pedestal, overhead, and the controls you can work
# ------------------------------------------------------------------------------
func _build_controls() -> void:
	var ped := MeshKit.new()
	# Pedestal: from the floor up under the panel, the quadrant on top.
	ped.box_at(Vector3(0, FLOOR_Y + 0.27, -6.25), Vector3(0.34, 0.54, 0.46), INTERIOR_DK)
	ped.box(Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 0.02, -6.28)), Vector3(0.34, 0.06, 0.34), Color(0.08, 0.08, 0.08))
	for gx in [-0.12, -0.07, -0.02, 0.02, 0.07, 0.12]:
		ped.box(Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(gx, 0.055, -6.28)), Vector3(0.012, 0.01, 0.26), Color(0.02, 0.02, 0.02))
	_mesh(ped, Pbr.paint_smooth(), "Pedestal")
	var pivot := Vector3(0, -0.02, -6.22)
	# Props (left pair), throttles (middle), mixtures (right), like the real one.
	var levers := [
		["prop", -0.12, Color(0.06, 0.06, 0.06), "ball"], ["prop", -0.07, Color(0.06, 0.06, 0.06), "ball"],
		["throttle", -0.02, Color(0.06, 0.06, 0.06), "big"], ["throttle", 0.02, Color(0.06, 0.06, 0.06), "big"],
		["mixture", 0.07, Color(0.60, 0.07, 0.05), "ball"], ["mixture", 0.12, Color(0.60, 0.07, 0.05), "ball"],
	]
	for i in range(levers.size()):
		var lv: Array = levers[i]
		var kind: String = lv[0]
		var kit := MeshKit.new()
		kit.box_at(Vector3(0, 0.10, 0), Vector3(0.012, 0.20, 0.016), ALU)
		if lv[3] == "big":
			kit.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.03, 0.215, 0)), 0.024, 0.024, 0.06, 12, lv[2], true)
			kit.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.032, 0.215, 0)), 0.012, 0.012, 0.064, 10, ALU, true)
		else:
			kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.195, 0)), 0.018, 0.018, 0.035, 10, lv[2], true)
		var node := _part(kit, "%s%d" % [kind, i], pivot + Vector3(float(lv[1]), 0, 0))
		var ei := 0 if i % 2 == 0 else 1
		var getter: Callable
		var setter: Callable
		var label: String
		match kind:
			"throttle":
				getter = func() -> float: return plane.throttle
				setter = func(v: float) -> void: plane.throttle = clampf(v, 0.0, 1.0)
				label = "Throttles"
			"prop":
				getter = func() -> float: return plane.engines()[mini(ei, plane.engines().size() - 1)].prop_lever
				setter = func(v: float) -> void:
					for e in plane.engines():
						e.prop_lever = clampf(v, 0.0, 1.0)
				label = "Propellers"
			_:
				getter = func() -> float: return plane.engines()[mini(ei, plane.engines().size() - 1)].mixture
				setter = func(v: float) -> void:
					for e in plane.engines():
						e.mixture = clampf(v, 0.0, 1.0)
				label = "Mixtures"
		var lab := label
		_add(kind + str(i), "slide", node, Vector3(0, 0.2, 0), 0.04, getter, setter,
			func(n: Node3D, v: float) -> void: n.rotation.x = lerpf(0.55, -0.55, v),
			func(v: float) -> String: return "%s %d%%" % [lab, int(round(v * 100.0))],
			{"sens": 0.004})
	# The big trim wheel on the left of the pedestal.
	var tk := MeshKit.new()
	var tr := 0.13
	for k in range(16):
		var a0 := TAU * float(k) / 16.0
		var a1 := TAU * float(k + 1) / 16.0
		_beam(tk, Vector3(0, sin(a0) * tr, cos(a0) * tr), Vector3(0, sin(a1) * tr, cos(a1) * tr), 0.012, Color(0.06, 0.06, 0.06), 6)
	for k in range(4):
		var a := TAU * float(k) / 4.0
		_beam(tk, Vector3.ZERO, Vector3(0, sin(a) * tr, cos(a) * tr), 0.008, ALU, 5)
	var trim_node := _part(tk, "trim", Vector3(-0.19, -0.18, -6.20))
	_add("trim", "slide", trim_node, Vector3(0, tr, 0), 0.08,
		func() -> float: return plane.trim * 0.5 + 0.5,
		func(v: float) -> void: plane.trim = clampf(v * 2.0 - 1.0, -1.0, 1.0),
		func(n: Node3D, v: float) -> void: n.rotation.x = (v - 0.5) * 6.0,
		func(v: float) -> String: return "Elevator trim %+d" % int(round((v - 0.5) * 200.0)),
		{"sens": 0.003})
	# Overhead panel: ignition switches for each engine, by the windscreen top.
	# Landing gear lever on the floor beside the pedestal, with its wheel-shaped
	# knob, and the gear lights above it: green down and locked, red moving.
	var gl := MeshKit.new()
	gl.box_at(Vector3(0, 0.13, 0), Vector3(0.014, 0.26, 0.014), ALU)
	gl.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.02, 0.27, 0)), 0.035, 0.035, 0.04, 14, Color(0.08, 0.08, 0.08), true)
	var gbase := MeshKit.new()
	gbase.box_at(Vector3(0.23, FLOOR_Y + 0.08, -6.05), Vector3(0.10, 0.16, 0.16), INTERIOR_DK)
	_mesh(gbase, Pbr.paint_smooth(), "GearBox")
	var gnode := _part(gl, "gear_lever", Vector3(0.23, FLOOR_Y + 0.16, -6.05))
	_add("gear_lever", "toggle", gnode, Vector3(0, 0.27, 0), 0.05,
		func() -> float: return 1.0 if plane.gear_down else 0.0,
		func(v: float) -> void: plane.set_gear(v > 0.5),
		func(n: Node3D, v: float) -> void: n.rotation.x = 0.45 if v > 0.5 else -0.45,
		func(v: float) -> String:
			var gp: float = plane.gear_pos
			return "Landing gear lever %s  (%s)" % ["DOWN" if v > 0.5 else "UP", "three green" if gp > 0.99 else ("up" if gp < 0.01 else "moving")])
	var tbase := MeshKit.new()
	tbase.box_at(Vector3(0.40, FLOOR_Y + 0.06, -6.05), Vector3(0.06, 0.12, 0.10), INTERIOR_DK)
	_mesh(tbase, Pbr.paint_smooth(), "TlockBox")
	var tnode := _part(gl, "tail_lock", Vector3(0.40, FLOOR_Y + 0.12, -6.05))
	_add("tail_lock", "toggle", tnode, Vector3(0, 0.16, 0), 0.04,
		func() -> float: return 1.0 if plane.tail_lock else 0.0,
		func(v: float) -> void: plane.tail_lock = v > 0.5,
		func(n: Node3D, v: float) -> void: n.rotation.x = 0.5 if v > 0.5 else -0.3,
		func(v: float) -> String: return "Tailwheel %s" % ["LOCKED for the roll" if v > 0.5 else "unlocked (castors for taxi turns)"])
	for li in range(4):
		var lk := MeshKit.new()
		var lm := StandardMaterial3D.new()
		var lcol := Color(0.2, 1.0, 0.3) if li < 3 else Color(1.0, 0.15, 0.1)
		lm.albedo_color = lcol.darkened(0.6)
		lm.emission = lcol
		var sm := SphereMesh.new()
		sm.radius = 0.008
		sm.height = 0.016
		var lmi := MeshInstance3D.new()
		lmi.mesh = sm
		lmi.material_override = lm
		lmi.position = Vector3(0.20 + 0.022 * float(li), FLOOR_Y + 0.165, -6.13)
		add_child(lmi)
		var on: Callable = (func() -> bool: return plane.gear_pos > 0.99) if li < 3 else (func() -> bool: return plane.gear_pos > 0.01 and plane.gear_pos < 0.99)
		_lamps.append([lm, on, lcol])

	var ov := MeshKit.new()
	var ov_xf := Transform3D(Basis(Vector3.RIGHT, 0.9), Vector3(0, 1.20, -6.25))
	ov.box(ov_xf, Vector3(0.50, 0.24, 0.04), Color(0.07, 0.07, 0.07))
	_mesh(ov, Pbr.crinkle(), "Overhead")
	# Lights: a row of toggles along the overhead's lower edge, same keys the
	# Wolverine's rockers drive (aircraft_lights.gd reads plane.lights).
	var lkeys := [["beacon", "Beacon"], ["nav", "Navigation lights"], ["strobe", "Strobes"], ["taxi", "Taxi light"], ["landing", "Landing lights"], ["panel", "Panel lights"]]
	for si in range(lkeys.size()):
		var key: String = lkeys[si][0]
		var lname: String = lkeys[si][1]
		var swk := MeshKit.new()
		swk.box_at(Vector3(0, 0.014, 0), Vector3(0.009, 0.028, 0.009), ALU)
		var at2 := ov_xf * Vector3(-0.20 + 0.08 * float(si), -0.075, 0.025)
		var swn := _part(swk, "lt_" + key, at2)
		swn.basis = ov_xf.basis
		if key == "panel":
			_add("lt_" + key, "toggle", swn, Vector3(0, 0.022, 0), 0.032,
				func() -> float: return 1.0 if plane.panel_light > 0.05 else 0.0,
				func(v: float) -> void: plane.panel_light = 0.8 if v > 0.5 else 0.0,
				func(n: Node3D, v: float) -> void: n.rotation.x = -0.45 if v > 0.5 else 0.45,
				func(v: float) -> String: return "Panel lights %s" % ["ON" if v > 0.5 else "OFF"])
		else:
			var k2 := key
			_add("lt_" + key, "toggle", swn, Vector3(0, 0.022, 0), 0.032,
				func() -> float: return 1.0 if bool(plane.lights.get(k2, false)) else 0.0,
				func(v: float) -> void: plane.lights[k2] = v > 0.5,
				func(n: Node3D, v: float) -> void: n.rotation.x = -0.45 if v > 0.5 else 0.45,
				func(v: float) -> String: return "%s %s" % [lname, "ON" if v > 0.5 else "OFF"])
	for ei2 in range(2):
		var sk := MeshKit.new()
		sk.box_at(Vector3(0, 0.02, 0), Vector3(0.012, 0.04, 0.012), ALU)
		var at := ov_xf * Vector3(-0.08 + 0.16 * float(ei2), 0.03, 0.025)
		var sw := _part(sk, "ign%d" % ei2, at)
		sw.basis = ov_xf.basis
		var e_idx := ei2
		_add("ign%d" % ei2, "toggle", sw, Vector3(0, 0.03, 0), 0.04,
			func() -> float:
				var es: Array = plane.engines()
				return 1.0 if es[mini(e_idx, es.size() - 1)].mags != EngineScript.MAGS_OFF else 0.0,
			func(v: float) -> void:
				var es: Array = plane.engines()
				es[mini(e_idx, es.size() - 1)].mags = EngineScript.MAGS_BOTH if v > 0.5 else EngineScript.MAGS_OFF,
			func(n: Node3D, v: float) -> void: n.basis = ov_xf.basis * Basis(Vector3.RIGHT, -0.4 if v > 0.5 else 0.4),
			func(v: float) -> String: return "%s ignition %s" % ["Left" if e_idx == 0 else "Right", "ON" if v > 0.5 else "OFF"])


func _build_yokes_and_pedals() -> void:
	for side in [-1.0, 1.0]:
		var sx: float = side * SEAT_X
		var base := Vector3(sx, FLOOR_Y, -6.32)
		var top := Vector3(sx, 0.12, -6.18)
		var ck := MeshKit.new()
		# Column from the floor, leaning back to the wheel.
		_beam(ck, Vector3(0, FLOOR_Y - top.y, (base - top).z), Vector3(0, -0.04, 0), 0.03, Color(0.42, 0.43, 0.44), 8)
		# The open "ram's horn" wheel: a lower arc and two horns.
		var r := 0.18
		var segs := 12
		for k in range(segs):
			var a0 := lerpf(PI * 1.15, PI * 1.85, float(k) / float(segs))
			var a1 := lerpf(PI * 1.15, PI * 1.85, float(k + 1) / float(segs))
			_beam(ck, Vector3(cos(a0) * r, sin(a0) * r * 0.55 + 0.06, 0), Vector3(cos(a1) * r, sin(a1) * r * 0.55 + 0.06, 0), 0.016, Color(0.10, 0.06, 0.04), 6)
		for hx in [-1.0, 1.0]:
			var c0 := Vector3(hx * r * cos(PI * 0.15), 0.06 - r * 0.55 * sin(PI * 0.15), 0)
			_beam(ck, c0, c0 + Vector3(hx * 0.01, 0.14, 0.0), 0.02, Color(0.10, 0.06, 0.04), 6)
		ck.box_at(Vector3(0, 0.0, 0.0), Vector3(0.09, 0.07, 0.05), Color(0.12, 0.12, 0.12))
		ck.box_at(Vector3(0, 0.0, 0.026), Vector3(0.06, 0.03, 0.002), Color(0.75, 0.62, 0.30))
		var node := _part(ck, "yoke" if side < 0.0 else "yoke_r", top)
		_yokes.append(node)
		var rest := top
		var yoke_pose := func(n: Node3D, _v: float) -> void:
			var pitch_in: float = clampf(plane.elevator, -1.0, 1.0)
			var roll_in: float = clampf(plane.aileron, -1.0, 1.0)
			n.position = rest + Vector3(0, 0, 0.10 * pitch_in)
			n.rotation.z = -roll_in * 1.1
		_add("yoke" if side < 0.0 else "yoke_r", "yoke", node, Vector3(0, 0.05, 0.02), 0.2,
			func() -> float: return 0.0,
			func(_v: float) -> void: pass,
			yoke_pose,
			func(_v: float) -> String: return "Control wheel: hold and drag to fly (drag down = pull back)")
		# Rudder pedals with toe brakes.
		for ps in [-1.0, 1.0]:
			var pk := MeshKit.new()
			pk.box(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 0.08, 0)), Vector3(0.10, 0.17, 0.02), Color(0.20, 0.20, 0.20))
			pk.box_at(Vector3(0, -0.02, 0.07), Vector3(0.025, 0.025, 0.16), ALU)
			var pat := Vector3(sx + ps * 0.11, FLOOR_Y + 0.08, -6.62)
			var pn := _part(pk, "pedal", pat)
			_pedals.append([pn, pat, ps, side])
