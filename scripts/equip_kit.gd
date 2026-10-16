extends RefCounted
## The truck treatment for the heavy equipment (DESIGN_NOTES 215): the same
## finish as the pickup - painted panels in the truck's paint shader (dust kicked
## up from the ground), truck-style lamps (chrome reflector, bulb, prism lens),
## chrome cylinder rods with their hoses, rubber-sealed glass, grated steps,
## handrails, bolt heads, hazard stripes, decals. All static helpers working
## on MeshKits in the machine's own frame (-Z forward, +Y up).

const MeshKit = preload("res://scripts/meshkit.gd")
const PAINT_SHADER := preload("res://shaders/truck_paint.gdshader")

const CHROME := Color(0.86, 0.87, 0.89)
const RUBBER := Color(0.06, 0.06, 0.065)
const STEEL := Color(0.40, 0.41, 0.43)
const HOSE := Color(0.07, 0.07, 0.07)


## The machine's paint: one colour, dulled and dusted toward the ground.
static func paint_mat(col: Color, dust: float = 0.4, dust_top: float = 1.1) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PAINT_SHADER
	m.set_shader_parameter("paint_a", col)
	m.set_shader_parameter("paint_b", col)
	m.set_shader_parameter("two_tone", false)
	m.set_shader_parameter("dust", dust)
	m.set_shader_parameter("dust_top", dust_top)
	m.set_shader_parameter("rough", 0.55)
	m.set_shader_parameter("ripple_k", 0.0)
	return m


static func metal_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.metallic = 0.85
	m.roughness = 0.22
	return m


static func dull_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.85
	return m


## Every lamp on the machine on or off: the beams, the bulbs lit, the lenses glowing.
static func lights_toggle(root: Node3D) -> String:
	var on := not bool(root.get_meta("ek_lights", false))
	root.set_meta("ek_lights", on)
	for n in root.find_children("*", "Light3D", true, false):
		if (n as Node).is_in_group("machine_light_src"):
			(n as Light3D).light_energy = float(n.get_meta("on_energy", 1.0)) if on else 0.0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if (mi as Node).has_meta("lamp"):
			var bm := (mi as MeshInstance3D).material_override as StandardMaterial3D
			if bm != null:
				bm.emission_energy_multiplier = 6.0 if on else 0.4
		if (mi as Node).has_meta("lamp_lens"):
			var lm := (mi as MeshInstance3D).material_override as StandardMaterial3D
			if lm != null:
				lm.emission_energy_multiplier = 1.6 if on else 0.15
	return "lights on" if on else "lights off"


## The engine: smoke at the stack, the sound, start-up (machine_engine.gd).
static func engine(root: Node3D, stack_top: Vector3, cap: Node3D = null, stack_r: float = 0.0) -> Node3D:
	var E = ResourceLoader.load("res://scripts/machine_engine.gd", "", ResourceLoader.CACHE_MODE_REPLACE)
	var e = E.new()
	e.name = "Engine"
	e.position = stack_top
	e.cap = cap
	root.add_child(e)
	if stack_r > 0.0:
		e.make_cap(stack_r)            # the working rain-cap flap on the stack
	return e


## Damage a hydraulic line (Dave: it leaks, the hydraulics lose pressure and
## the load slowly falls): one of the machine's working rams' lines cracks.
static func damage_line(root: Node, severity: float = 0.35) -> String:
	var rams: Array = root.find_children("*", "Node3D", true, false).filter(func(n): return n.has_method("plumb") and n.get("sim_ram") != null and not (n.get("hoses") as Array).is_empty())
	if rams.is_empty():
		return "No hydraulic lines to damage."
	var r = rams[randi() % rams.size()]
	var h = (r.hoses as Array)[randi() % (r.hoses as Array).size()]
	h.leak = severity
	r.sim_ram.leak = maxf(float(r.sim_ram.leak), severity)
	return "A %s line is cracked: it's leaking oil and the %s won't hold." % [String(r.sim_ram.name).to_lower(), String(r.sim_ram.name).to_lower()]


static func repair_lines(root: Node) -> String:
	for n in root.find_children("*", "Node3D", true, false):
		if n.has_method("mend"):
			n.mend()
		if n.get("sim_ram") != null:
			n.sim_ram.leak = 0.0
	return "Lines mended."


## True when the machine stands in the Model Lab (not in the game): it then
## works its rams on its own so they can be watched stroking.
static func in_lab(n: Node) -> bool:
	if not n.is_inside_tree():
		return false
	var cs := n.get_tree().current_scene
	return cs != null and cs.get_script() != null and String((cs.get_script() as Script).resource_path).ends_with("model_lab.gd")


## Collision for everything (Dave): each solid mesh of the machine gets a
## simplified convex hull on a body that rides with its part, so people,
## props and other machines bump into the arm, the bucket, the blade, the cab.
## Glass, lamps and tiny bits are skipped (the panes' frames cover them).
static func add_collision(root: Node3D, layer: int = 1) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.name.begins_with("Glass") or m.name.contains("Lens") or m.get_parent() is CollisionObject3D:
			continue
		var ab := m.get_aabb()
		if ab.size.x * ab.size.y * ab.size.z < 0.002 or m.mesh.get_surface_count() == 0:
			continue
		var cur := m.material_override
		if cur is StandardMaterial3D and (cur as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var shape := m.mesh.create_convex_shape(true, true)
		if shape == null:
			continue
		var body := AnimatableBody3D.new()
		body.name = m.name + "_col"
		body.collision_layer = layer
		body.collision_mask = 0
		body.sync_to_physics = false
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		m.add_child(body)


## A pin boss at a hinge: the boss either side and the pin through, across x.
static func pin(k: MeshKit, c: Vector3, half_w: float, r: float, col: Color) -> void:
	for sx in [-1.0, 1.0]:
		k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), c + Vector3(float(sx) * half_w + (r * 0.4 if sx > 0.0 else 0.0), 0, 0)), r, r, r * 0.4, 14, col, true)
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), c + Vector3(half_w + r * 0.55, 0, 0)), r * 0.45, r * 0.45, half_w * 2.0 + r * 1.1, 10, STEEL, true)


## A real clevis (Dave: no square-block mounts): two plates either side of the
## eye, each with a rounded end round the pin, flaring down to where they're
## welded on (`base_dir` from the pin to that surface, `base_len` away, in the
## part's Y-Z plane), a boss ring on the outside of each and the pin through
## with its keeper heads. `half_gap` is half the room between the plates (the
## eye's half width). Built in the part's own frame, pin across X.
static func lug(k: MeshKit, c: Vector3, half_gap: float, t: float, r_out: float, base_dir: Vector3, base_len: float, col: Color, pin_r: float = 0.0, pin_half: float = 0.0) -> void:
	var d := Vector3(0, base_dir.y, base_dir.z).normalized()
	if d.length() < 0.5:
		d = Vector3.DOWN
	var pp := Vector3(0, -d.z, d.y)                  # across the plate, in Y-Z
	var w := r_out * 1.3
	var outline: Array = []
	for i in range(11):
		var ang := PI * 0.5 + PI * float(i) / 10.0
		outline.append(c + (d * cos(ang) + pp * sin(ang)) * r_out)
	outline.append(c + d * base_len - pp * w)
	outline.append(c + d * base_len + pp * w)
	var cen := Vector3.ZERO
	for q in outline:
		cen += q as Vector3
	cen /= float(outline.size())
	for sx in [-1.0, 1.0]:
		var x0 := float(sx) * half_gap
		var x1 := float(sx) * (half_gap + t)
		var n := outline.size()
		for i in range(n):
			var a: Vector3 = outline[i]
			var b: Vector3 = outline[(i + 1) % n]
			var ai := Vector3(c.x + x0, a.y, a.z)
			var bi := Vector3(c.x + x0, b.y, b.z)
			var ao := Vector3(c.x + x1, a.y, a.z)
			var bo := Vector3(c.x + x1, b.y, b.z)
			var ci := Vector3(c.x + x0, cen.y, cen.z)
			var co := Vector3(c.x + x1, cen.y, cen.z)
			k.tri(ci, ai, bi, col, Vector3(-float(sx), 0, 0))
			k.tri(co, ao, bo, col, Vector3(float(sx), 0, 0))
			var mid := (a + b) * 0.5 - cen
			k.quad(ai, bi, bo, ao, col, Vector3(0, mid.y, mid.z))
		# the boss ring on the outside, round the pin
		k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5) if sx < 0.0 else Basis(Vector3.FORWARD, PI * 0.5), Vector3(c.x + x1, c.y, c.z)), r_out * 0.72, r_out * 0.72, t * 0.45, 14, col.darkened(0.08), true)
	var pr := pin_r if pin_r > 0.0 else r_out * 0.38
	var span := maxf(half_gap + t * 1.6, pin_half)       # a long cross pin carries rams outside the plates
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), c + Vector3(span, 0, 0)), pr, pr, span * 2.0, 10, STEEL, true)
	for sx2 in [-1.0, 1.0]:
		k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), c + Vector3(float(sx2) * span + (pr * 0.3 if sx2 > 0.0 else 0.0), 0, 0)), pr * 1.35, pr * 1.35, pr * 0.3, 10, STEEL.darkened(0.2), true)


## A tube from a to b.
static func rod(k: MeshKit, a: Vector3, b: Vector3, r: float, col: Color, sides: int = 10) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	k.cylinder(Transform3D(Basis(x, y, x.cross(y)), a), r, r, d.length(), sides, col, true)


## A hydraulic cylinder from its barrel end `a` to its rod end `b`, the rod out
## `ext` (0..1 of the barrel): painted barrel, end caps, the gland, chrome rod,
## clevis eyes; returns the gland position (for hoses).
static func hyd(paint: MeshKit, metal: MeshKit, a: Vector3, b: Vector3, r: float, col: Color, ext: float = 0.5) -> Vector3:
	var d := b - a
	var L := d.length()
	if L < 0.01:
		return a
	var dir := d / L
	var barrel := L / (1.0 + ext)
	var g := a + dir * barrel
	rod(paint, a + dir * r * 0.6, g, r, col, 14)
	rod(paint, a + dir * r * 0.3, a + dir * (r * 0.3 + r * 0.5), r * 1.12, col.darkened(0.15), 14)      # the base cap
	rod(paint, g - dir * r * 0.5, g, r * 1.14, col.darkened(0.15), 14)                                   # the head
	rod(metal, g, g + dir * r * 0.18, r * 0.62, STEEL, 12)                                               # the gland nut
	rod(metal, g, b - dir * r * 0.5, r * 0.5, CHROME, 12)                                                # the rod
	for e in [a, b]:
		var ep: Vector3 = e
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
		metal.cylinder(Transform3D(Basis(side.cross(dir).normalized(), side, dir), ep - side * r * 0.55), r * 0.62, r * 0.62, r * 1.1, 12, STEEL, true)   # clevis eye
	# the two ports and their hoses curling away
	for pe in [[a + dir * r * 1.2, 1.0], [g - dir * r * 0.8, -1.0]]:
		var pp: Vector3 = pe[0]
		var up := dir.cross(dir.cross(Vector3.UP)).normalized() * -1.0
		if up.length() < 0.1:
			up = Vector3.FORWARD
		metal.box(Transform3D(Basis.looking_at(up, dir), pp + up * r * 0.95), Vector3(r * 0.5, r * 0.5, r * 0.5), STEEL)
	return g


## A hose drawn as a sagging curve from a to b.
static func hose(k: MeshKit, a: Vector3, b: Vector3, r: float, sag: float = 0.15) -> void:
	var prev := a
	for i in range(1, 9):
		var f := float(i) / 8.0
		var p := a.lerp(b, f) - Vector3(0, sag * 4.0 * f * (1.0 - f), 0)
		rod(k, prev, p, r, HOSE, 6)
		prev = p


## A truck-style lamp: housing, chrome reflector, bulb, prism lens (truck_body's).
## Adds the lens as its own node under `root`; `facing` is the beam direction.
static func lamp(k_housing: MeshKit, k_metal: MeshKit, root: Node3D, c: Vector3, facing: Vector3, w: float, h: float, lens_col: Color, round_: bool = false) -> void:
	var f := facing.normalized()
	var up := Vector3.UP if absf(f.y) < 0.9 else Vector3.FORWARD
	var b := Basis.looking_at(-f, up)            # +z of b points along the beam
	var depth := minf(w, h) * 0.7
	if round_:
		k_housing.cylinder(Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), c - f * depth), w * 0.5 + 0.015, w * 0.5 + 0.02, depth, 16, RUBBER, true)
		k_metal.cylinder(Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), c - f * depth * 0.5), w * 0.2, w * 0.48, depth * 0.45, 16, CHROME, false)
	else:
		k_housing.box(Transform3D(b, c - f * depth * 0.5), Vector3(w + 0.03, h + 0.03, depth), RUBBER)
		k_metal.box(Transform3D(b, c - f * 0.006), Vector3(w * 0.96, h * 0.96, 0.01), CHROME)
	# the bulb, lit a little
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = minf(w, h) * 0.12
	sm.height = sm.radius * 2.0
	bulb.mesh = sm
	bulb.position = c - f * 0.02
	var bm := StandardMaterial3D.new()
	bm.albedo_color = lens_col
	bm.emission_enabled = true
	bm.emission = lens_col
	bm.emission_energy_multiplier = 0.4
	bulb.material_override = bm
	root.add_child(bulb)
	# the bezel (Dave: better lights and lenses, from the real 80s lamps): a raised
	# chrome ring round a round lens with its screws; a chrome frame round a square one
	var R := w * 0.48
	if round_:
		var segs := 24
		for i in range(segs):
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var u0 := b.x * cos(a0) + b.y * sin(a0)
			var u1 := b.x * cos(a1) + b.y * sin(a1)
			var face := c + f * 0.006
			k_metal.quad(face + u0 * R, face + u1 * R, face + u1 * R * 1.16, face + u0 * R * 1.16, CHROME, f)          # the ring's face
			k_metal.quad(face + u0 * R * 1.16, face + u1 * R * 1.16, face + u1 * R * 1.16 - f * 0.03, face + u0 * R * 1.16 - f * 0.03, CHROME, u0 + u1)   # its rolled edge
			k_metal.quad(face + u1 * R, face + u0 * R, face + u0 * R - f * 0.01, face + u1 * R - f * 0.01, CHROME, -(u0 + u1))   # the lip inside
		for sc in range(3):
			var sa := TAU * float(sc) / 3.0 + 0.5
			var sp := c + f * 0.008 + (b.x * cos(sa) + b.y * sin(sa)) * R * 1.08
			k_metal.cylinder(Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), sp), 0.006, 0.005, 0.004, 6, STEEL, true)      # bezel screws
	else:
		var fr := 0.014
		for e in [[Vector3(0, h * 0.5 + fr * 0.5, 0), Vector3(w + fr * 2.0, fr, 0.016)], [Vector3(0, -h * 0.5 - fr * 0.5, 0), Vector3(w + fr * 2.0, fr, 0.016)],
				[Vector3(w * 0.5 + fr * 0.5, 0, 0), Vector3(fr, h, 0.016)], [Vector3(-w * 0.5 - fr * 0.5, 0, 0), Vector3(fr, h, 0.016)]]:
			k_metal.box(Transform3D(b, c + b * (e[0] as Vector3) + f * 0.004), e[1], CHROME)
	# the lens: domed glass with fresnel rings and a bullseye (round), prism cells (square)
	var lens := MeshInstance3D.new()
	lens.mesh = _lens_mesh(round_, w, h)
	lens.transform = Transform3D(b, c + f * 0.002)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(lens_col.r, lens_col.g, lens_col.b, 0.6)
	m.albedo_texture = _ring_tex() if round_ else null
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 1.0
	m.normal_enabled = true
	m.normal_texture = _ring_norm() if round_ else (load("res://scripts/truck_body.gd") as GDScript).call("_flute_tex")
	m.normal_scale = 0.8
	if not round_:
		m.uv1_scale = Vector3(w / 0.02, h / 0.02, 1)
	m.emission_enabled = true
	m.emission = lens_col
	m.emission_energy_multiplier = 0.15          # a little colour even off; glows when the lights are switched on (lights_toggle)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	lens.material_override = m
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lens.add_to_group("machine_lamps")
	lens.set_meta("lamp_lens", true)
	root.add_child(lens)
	# the light it throws: off until the switch (lights_toggle); white lamps
	# throw a beam, the coloured ones just glow round themselves
	var white := lens_col.r > 0.9 and lens_col.g > 0.9
	var lt: Light3D
	if white:
		var sp := SpotLight3D.new()
		sp.spot_range = 22.0
		sp.spot_angle = 38.0
		sp.light_energy = 0.0
		lt = sp
	else:
		var om := OmniLight3D.new()
		om.omni_range = 1.4
		om.light_energy = 0.0
		lt = om
	lt.light_color = lens_col
	lt.shadow_enabled = false
	lt.transform = Transform3D(Basis.looking_at(f, up), c + f * 0.05)
	lt.set_meta("on_energy", 2.0 if white else 0.6)
	lt.add_to_group("machine_light_src")
	root.add_child(lt)
	bulb.set_meta("lamp", true)


## A lamp's lens in its own frame (+z out): domed, with planar UVs.
static func _lens_mesh(round_: bool, w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dome := minf(w, h) * 0.12
	if round_:
		var R := w * 0.48
		var rings := 6
		var segs := 24
		var pts: Array = []
		for ri in range(rings + 1):
			var rr := R * float(ri) / float(rings)
			var row: Array = []
			for si in range(segs):
				var a := TAU * float(si) / float(segs)
				var x := cos(a) * rr
				var y := sin(a) * rr
				row.append(Vector3(x, y, dome * (1.0 - (rr / R) * (rr / R))))
			pts.append(row)
		for ri2 in range(rings):
			for si2 in range(segs):
				var s2 := (si2 + 1) % segs
				for v in [pts[ri2][si2], pts[ri2 + 1][s2], pts[ri2 + 1][si2], pts[ri2][si2], pts[ri2][s2], pts[ri2 + 1][s2]]:
					var vv := v as Vector3
					st.set_normal(Vector3(vv.x * 2.0 * dome / (R * R), vv.y * 2.0 * dome / (R * R), 1.0).normalized())     # out of the dome
					st.set_uv(Vector2(vv.x / (2.0 * R) + 0.5, vv.y / (2.0 * R) + 0.5))
					st.add_vertex(vv)
	else:
		var n := 6
		for i in range(n):
			for j in range(n):
				var q: Array = []
				for e in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
					var u := float(e[0]) / float(n)
					var v2 := float(e[1]) / float(n)
					var x2 := (u - 0.5) * w
					var y2 := (v2 - 0.5) * h
					q.append([Vector3(x2, y2, dome * 0.4 * (1.0 - 4.0 * (u - 0.5) * (u - 0.5)) * (1.0 - 4.0 * (v2 - 0.5) * (v2 - 0.5))), Vector2(u, v2)])
				for k in [0, 2, 1, 0, 3, 2]:
					st.set_normal(Vector3(0, 0, 1))
					st.set_uv(q[k][1])
					st.add_vertex(q[k][0])
	st.generate_tangents()
	return st.commit()


static var _rt: ImageTexture
static var _rn: ImageTexture
## Fresnel rings and a bullseye: light and dark bands for the glass.
static func _ring_tex() -> ImageTexture:
	if _rt == null:
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in range(128):
			for x in range(128):
				var r := Vector2(x - 63.5, y - 63.5).length() / 63.5
				var band := 0.5 + 0.5 * cos(r * 9.0 * TAU)
				var v := 0.8 + 0.2 * band if r > 0.18 else (0.95 if r > 0.1 else 1.0)
				img.set_pixel(x, y, Color(v, v, v, 1.0))
		img.generate_mipmaps()
		_rt = ImageTexture.create_from_image(img)
	return _rt


## The rings' ridges as a normal map, so the light catches each one.
static func _ring_norm() -> ImageTexture:
	if _rn == null:
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in range(128):
			for x in range(128):
				var d := Vector2(x - 63.5, y - 63.5)
				var r := d.length() / 63.5
				var slope := -sin(r * 9.0 * TAU) * 0.6 if r > 0.18 else 0.0
				var dir := d.normalized() if d.length() > 0.01 else Vector2.ZERO
				var nrm := Vector3(dir.x * slope, dir.y * slope, 1.0).normalized()
				img.set_pixel(x, y, Color(nrm.x * 0.5 + 0.5, nrm.y * 0.5 + 0.5, nrm.z * 0.5 + 0.5, 1.0))
		img.generate_mipmaps()
		_rn = ImageTexture.create_from_image(img)
	return _rn


## Glass in a black rubber seal: the pane (into `glass`) and its gasket frame.
## The pane spans corners p0 (bottom-left) .. p2 (top-right) on a flat plane.
static func pane(glass: MeshKit, seal: MeshKit, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, out: Vector3) -> void:
	glass.quad(p0, p1, p2, p3, Color(0.45, 0.58, 0.66, 0.35), out)
	var pts := [p0, p1, p2, p3]
	for i in range(4):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % 4]
		var mid := (a + b) * 0.5
		var along := (b - a).normalized()
		var bb := Basis(along, out.normalized().cross(along).normalized() * -1.0, out.normalized()).orthonormalized()
		seal.box(Transform3D(bb, mid), Vector3(a.distance_to(b) + 0.05, 0.05, 0.035), RUBBER)


## A step of open steel grating (the dark slots read as the holes).
static func grate_step(k: MeshKit, c: Vector3, w: float, d: float, yaw: float = 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	k.box(Transform3D(b, c), Vector3(w, 0.03, d), STEEL)
	var n := int(w / 0.05)
	for i in range(n):
		var x := -w * 0.5 + (float(i) + 0.5) * w / n
		k.box(Transform3D(b, c + b * Vector3(x, 0.016, 0)), Vector3(0.012, 0.004, d * 0.85), Color(0.08, 0.08, 0.08))
	for sx in [-1.0, 1.0]:
		k.box(Transform3D(b, c + b * Vector3(float(sx) * w * 0.5, -0.04, 0)), Vector3(0.01, 0.1, d), STEEL)


## A handrail through the points, posts down to `post_y` at each end.
static func rail(k: MeshKit, pts: Array, col: Color, r: float = 0.02) -> void:
	for i in range(pts.size() - 1):
		rod(k, pts[i], pts[i + 1], r, col, 8)


## A row of hex bolt heads from a to b on a face looking along `out`.
static func bolts(k: MeshKit, a: Vector3, b: Vector3, n: int, out: Vector3, r: float = 0.018, col: Color = STEEL) -> void:
	var o := out.normalized()
	var x := o.cross(Vector3.UP if absf(o.y) < 0.9 else Vector3.RIGHT).normalized()
	for i in range(n):
		var p := a.lerp(b, (float(i) + 0.5) / float(n)) if n > 1 else (a + b) * 0.5
		k.cylinder(Transform3D(Basis(x, o, x.cross(o)), p), r, r, r * 0.6, 6, col, true)


## Black / yellow hazard stripes on a flat face (quad p0..p3, stripes along p0->p1).
static func hazard(k: MeshKit, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, out: Vector3, n: int = 8) -> void:
	for i in range(n):
		var f0 := float(i) / n
		var f1 := float(i + 1) / n
		var col := Color(0.95, 0.75, 0.08) if i % 2 == 0 else Color(0.06, 0.06, 0.06)
		var off := out.normalized() * 0.004
		k.quad(p0.lerp(p1, f0) + off, p0.lerp(p1, f1) + off, p3.lerp(p2, f1) + off, p3.lerp(p2, f0) + off, col, out)


## A decal: text on a face (warning stickers, the model number).
static func decal(root: Node3D, text: String, at: Vector3, facing: Vector3, px: float, col: Color, bg: Color = Color(0, 0, 0, 0), k: MeshKit = null, w: float = 0.0, h: float = 0.0) -> void:
	var f := facing.normalized()
	if bg.a > 0.0 and k != null:
		var b := Basis.looking_at(-f, Vector3.UP if absf(f.y) < 0.9 else Vector3.FORWARD)
		k.box(Transform3D(b, at - f * 0.002), Vector3(w, h, 0.003), bg)
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = at + f * 0.003
	l.basis = Basis.looking_at(-f, Vector3.UP if absf(f.y) < 0.9 else Vector3.FORWARD)
	root.add_child(l)


## A grille of bars across a frame: w x h on the face at c looking along out.
static func grille(k: MeshKit, frame: MeshKit, c: Vector3, out: Vector3, w: float, h: float, bars: int, horizontal: bool = true) -> void:
	var o := out.normalized()
	var b := Basis.looking_at(-o, Vector3.UP if absf(o.y) < 0.9 else Vector3.FORWARD)
	k.box(Transform3D(b, c - o * 0.06), Vector3(w, h, 0.02), Color(0.04, 0.04, 0.04))     # dark behind
	for i in range(bars):
		var f := (float(i) + 0.5) / bars - 0.5
		if horizontal:
			frame.box(Transform3D(b * Basis(Vector3.RIGHT, 0.5), c + b * Vector3(0, f * h, -0.02)), Vector3(w, 0.012, h / bars * 1.1), Color(0.12, 0.12, 0.12))
		else:
			frame.box(Transform3D(b, c + b * Vector3(f * w, 0, -0.02)), Vector3(0.02, h, 0.05), Color(0.12, 0.12, 0.12))
	for s in [[Vector3(0, h * 0.5, 0), Vector3(w + 0.06, 0.04, 0.06)], [Vector3(0, -h * 0.5, 0), Vector3(w + 0.06, 0.04, 0.06)],
			[Vector3(w * 0.5, 0, 0), Vector3(0.04, h, 0.06)], [Vector3(-w * 0.5, 0, 0), Vector3(0.04, h, 0.06)]]:
		frame.box(Transform3D(b, c + b * (s[0] as Vector3)), s[1], Color(0.14, 0.14, 0.14))


## A padded seat: cushion, back, the bolsters, the arm rests, on its base.
static func seat(k: MeshKit, c: Vector3, yaw: float, col: Color = Color(0.13, 0.13, 0.14)) -> void:
	var b := Basis(Vector3.UP, yaw)
	k.rbox(Transform3D(b, c + Vector3(0, 0.07, 0)), Vector3(0.5, 0.13, 0.48), col, 0.05)
	k.rbox(Transform3D(b * Basis(Vector3.RIGHT, -0.18), c + b * Vector3(0, 0.42, 0.24)), Vector3(0.48, 0.6, 0.12), col, 0.05)
	for sx in [-1.0, 1.0]:
		k.rbox(Transform3D(b, c + b * Vector3(float(sx) * 0.29, 0.25, 0.02)), Vector3(0.07, 0.07, 0.4), col.lightened(0.05), 0.03)
	k.box(Transform3D(b, c + Vector3(0, -0.12, 0)), Vector3(0.36, 0.24, 0.36), Color(0.15, 0.15, 0.15))


## An air-suspension seat (air_seat.gd) as its own node, its valve a control.
static func air_seat(parent: Node3D, base: Vector3, yaw: float, col: Color = Color(0.13, 0.13, 0.14)) -> Node3D:
	var S = ResourceLoader.load("res://scripts/air_seat.gd", "", ResourceLoader.CACHE_MODE_REPLACE)
	var n = S.new()
	n.name = "AirSeat"
	n.position = base
	n.rotation.y = yaw
	parent.add_child(n)
	n.build(col)
	return n


## A side mirror on its arm.
static func mirror(k: MeshKit, base: Vector3, tip: Vector3) -> void:
	rod(k, base, tip, 0.012, RUBBER, 6)
	k.rbox(Transform3D(Basis.IDENTITY, tip + Vector3(0, -0.05, 0)), Vector3(0.04, 0.24, 0.17), RUBBER, 0.015)
	k.box(Transform3D(Basis.IDENTITY, tip + Vector3(0, -0.05, -0.0)), Vector3(0.045, 0.2, 0.13), Color(0.55, 0.62, 0.68))


## A beacon: the amber dome on its base.
static func beacon(k: MeshKit, root: Node3D, c: Vector3) -> void:
	k.cylinder(Transform3D(Basis.IDENTITY, c), 0.09, 0.09, 0.04, 14, RUBBER, true)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.075
	cm.height = 0.14
	mi.mesh = cm
	mi.position = c + Vector3(0, 0.11, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.55, 0.05, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.05)
	m.emission_energy_multiplier = 0.3
	m.roughness = 0.1
	mi.material_override = m
	root.add_child(mi)


## Give every vertex-coloured mesh under `root` a painted finish with the dust
## kicked up from the ground BAKED into its vertex colours (no custom shader:
## it showed nothing on Dave's card), each part's dust from its own height.
static var _paint_std: StandardMaterial3D


static var _wear: ImageTexture
static var _wear_rough: ImageTexture


## The wear texture: mostly 1.0 (the paint as it is), with grime blotches,
## streaks running down, and fine scratches (bright where the steel shows,
## dark where dirt's packed in) - multiplies the vertex paint.
static func wear_tex() -> ImageTexture:
	if _wear != null:
		return _wear
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var fn := FastNoiseLite.new()
	fn.seed = 7
	fn.frequency = 0.012
	fn.fractal_octaves = 4
	var fs := FastNoiseLite.new()
	fs.seed = 11
	fs.frequency = 0.004
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var v := PackedFloat32Array()
	v.resize(n * n)
	for y in range(n):
		for x in range(n):
			var g := fn.get_noise_2d(x, y) * 0.5 + 0.5
			var streak := fs.get_noise_2d(x * 0.15, y * 2.0) * 0.5 + 0.5        # grime runs down
			var val := 1.0 - smoothstep(0.6, 0.95, g) * 0.05          # faded paint, very light (the grime is its own layer now)
			val += (rng.randf() - 0.5) * 0.025
			v[y * n + x] = val
	# scratches: short straight-ish strokes
	for k in range(140):
		var x0 := rng.randf() * n
		var y0 := rng.randf() * n
		var ang := rng.randf() * TAU
		var L := rng.randf_range(8.0, 60.0)
		var bright := rng.randf() < 0.6
		for t in range(int(L)):
			var px := int(x0 + cos(ang) * t + sin(t * 0.3) * 0.6) % n
			var py := int(y0 + sin(ang) * t) % n
			if px < 0: px += n
			if py < 0: py += n
			v[py * n + px] = 1.12 if bright else 0.8
	var rimg := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y2 in range(n):
		for x2 in range(n):
			var c := clampf(v[y2 * n + x2], 0.0, 1.3)
			var a := clampf(c * 0.97, 0.0, 1.0)
			img.set_pixel(x2, y2, Color(a, a, a))
			var r := clampf(0.4 + (1.0 - c) * 1.3, 0.2, 1.0)        # grime is dull, scratches catch the light
			rimg.set_pixel(x2, y2, Color(r, r, r))
	img.generate_mipmaps()
	rimg.generate_mipmaps()
	_wear = ImageTexture.create_from_image(img)
	_wear_rough = ImageTexture.create_from_image(rimg)
	return _wear


static var _grime: ImageTexture


## Grime alone (blotches and streaks) - the dirt that washes off. The wear
## texture keeps only the scratches, which don't.
static func grime_tex() -> ImageTexture:
	if _grime != null:
		return _grime
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var fn := FastNoiseLite.new()
	fn.seed = 7
	fn.frequency = 0.024
	fn.fractal_octaves = 4
	var fs := FastNoiseLite.new()
	fs.seed = 11
	fs.frequency = 0.008
	for y in range(n):
		for x in range(n):
			var g := fn.get_noise_2d(x, y) * 0.5 + 0.5
			var streak := fs.get_noise_2d(x * 0.15, y * 2.0) * 0.5 + 0.5
			var val := 1.0 - smoothstep(0.45, 0.95, g) * 0.35 - smoothstep(0.5, 0.95, streak) * 0.25
			img.set_pixel(x, y, Color(val * 0.97, val * 0.93, val * 0.86))     # brownish
	img.generate_mipmaps()
	_grime = ImageTexture.create_from_image(img)
	return _grime


## Paint a machine: its own material (scratches for good, grime on a mask
## that washes), dust baked into the vertex colours from the ground up. The
## clean colours are kept so set_dirt() can wash it or muck it up again.
static func dust_all(root: Node3D, dust: float = 0.4, dust_top: float = 1.1) -> void:
	wear_tex()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.4
	mat.clearcoat_roughness = 0.25
	mat.albedo_texture = _wear
	mat.roughness_texture = _wear_rough
	mat.roughness = 1.0
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.detail_enabled = true
	mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	mat.detail_albedo = grime_tex()
	mat.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
	var mask := Image.create(4, 4, false, Image.FORMAT_L8)
	mask.fill(Color(1, 1, 1))
	mat.detail_mask = ImageTexture.create_from_image(mask)
	root.set_meta("ek_mat", mat)
	root.set_meta("ek_dust", [dust, dust_top])
	var meshes: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var cur := m.material_override
		if cur is StandardMaterial3D:
			var sm := cur as StandardMaterial3D
			if not sm.vertex_color_use_as_albedo or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.emission_enabled or sm.metallic > 0.5:
				continue
		elif cur != null:
			continue
		var am := m.mesh as ArrayMesh
		if am == null or am.get_surface_count() == 0:
			continue
		var surfs: Array = []
		for si in range(am.get_surface_count()):
			surfs.append(am.surface_get_arrays(si))
		m.set_meta("ek_surfs", surfs)
		m.set_meta("ek_yo", _local_to(root, m).y - root.transform.origin.y)
		m.material_override = mat
		meshes.append(m)
	root.set_meta("ek_meshes", meshes)
	set_dirt(root, 0.6)              # a working machine: some dust on it


## How dirty the machine is, 0 just washed .. 1 a season's muck (damage and
## scratches stay either way).
static func set_dirt(root: Node3D, amt: float) -> void:
	if not root.has_meta("ek_meshes"):
		return
	var dd: Array = root.get_meta("ek_dust")
	var dust: float = float(dd[0]) * amt
	var dust_top: float = float(dd[1])
	var dust_col := Color(0.42, 0.37, 0.30)
	for m in root.get_meta("ek_meshes"):
		var mi := m as MeshInstance3D
		if not is_instance_valid(mi):
			continue
		var yo: float = mi.get_meta("ek_yo")
		var out := ArrayMesh.new()
		for arr0 in mi.get_meta("ek_surfs"):
			var arr: Array = (arr0 as Array).duplicate()
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cs = arr[Mesh.ARRAY_COLOR]
			if cs != null and (cs as PackedColorArray).size() == vs.size():
				var cols: PackedColorArray = (cs as PackedColorArray).duplicate()
				for vi in range(vs.size()):
					var d := clampf((dust_top - (vs[vi].y + yo)) / 0.35, 0.0, 1.0) * dust
					cols[vi] = cols[vi].lerp(dust_col, d)
				arr[Mesh.ARRAY_COLOR] = cols
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mi.mesh = out
	var mat: StandardMaterial3D = root.get_meta("ek_mat")
	var mask := Image.create(4, 4, false, Image.FORMAT_L8)
	mask.fill(Color(amt, amt, amt))
	mat.detail_mask = ImageTexture.create_from_image(mask)
	root.set_meta("ek_dirt", amt)


static func _local_to(root: Node3D, n: Node3D) -> Vector3:
	var xf := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != root:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return root.transform * xf.origin   # in root's parent frame


## The material for a kit: paint (with dust) for the painted parts.
static func add_kit(root: Node3D, k: MeshKit, nm: String, m: Material) -> MeshInstance3D:
	if k.is_empty():
		return null
	var mi := k.instance(nm)
	mi.material_override = m
	root.add_child(mi)
	return mi
