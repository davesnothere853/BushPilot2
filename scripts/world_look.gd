extends RefCounted
## The demo's look, in one place so the game and the render tests match:
## Low-poly polyart under cinematic light (reference/*.png).
##   environment()  sky, low warm sun, haze with aerial perspective, AO, glow
##   mountains()    a ring of faceted low-poly peaks far out in the haze
##   plain()        the open grass plain past the square (storyboard PG-01)
##   camera_attrs() depth of field for the on-foot view

const MeshKit = preload("res://scripts/meshkit.gd")


static func environment(parent: Node) -> DirectionalLight3D:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.30, 0.47, 0.78)
	sm.sky_horizon_color = Color(0.70, 0.78, 0.86)
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color(0.25, 0.32, 0.22)
	sm.ground_horizon_color = Color(0.70, 0.78, 0.86)
	sm.sun_angle_max = 20.0
	sm.sun_curve = 0.1
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	# Haze: thin near, thickening with distance, tinted by the sky so far
	# hills and mountains go pale blue.
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.76, 0.86)
	env.fog_density = 0.0011
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.0
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.ssil_intensity = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.06
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.18
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-24.0), deg_to_rad(-135.0), 0)
	sun.light_color = Color(1.0, 0.90, 0.76)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 260.0
	parent.add_child(sun)
	return sun


static func camera_attrs(far_blur: bool) -> CameraAttributesPractical:
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = far_blur
	ca.dof_blur_far_distance = 70.0
	ca.dof_blur_far_transition = 90.0
	ca.dof_blur_amount = 0.06
	return ca


static func _h(i: int, k: int) -> float:
	var h: int = (i * 374761393 + k * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## Faceted mountains on a ring far out: grey-blue rock, snow on the high
## ones. Haze does the rest.
## The peaks as [centre, height, radius] - the same numbers the mesh is built
## from, so ground.gd can make them solid (fly into one and you hit it).
static func peaks(plain_y: float) -> Array:
	var out: Array = []
	var count := 34
	for m in range(count):
		var a := TAU * (float(m) + _h(m, 1) * 0.6) / float(count)
		var dist := 2600.0 + 1300.0 * _h(m, 2)
		var c := Vector3(cos(a) * dist, plain_y - 20.0, sin(a) * dist)
		var hgt := 450.0 + 900.0 * _h(m, 3)
		var rad := hgt * (1.1 + 0.6 * _h(m, 4))
		out.append([c, hgt, rad])
	return out


static func mountains(parent: Node, plain_y: float) -> void:
	var kit := MeshKit.new()
	var rock := Color(0.38, 0.42, 0.47)
	var rock_dk := Color(0.30, 0.33, 0.38)
	var snow := Color(0.86, 0.89, 0.93)
	var count := 34
	for m in range(count):
		var a := TAU * (float(m) + _h(m, 1) * 0.6) / float(count)
		var dist := 2600.0 + 1300.0 * _h(m, 2)
		var c := Vector3(cos(a) * dist, plain_y - 20.0, sin(a) * dist)
		var hgt := 450.0 + 900.0 * _h(m, 3)
		var rad := hgt * (1.1 + 0.6 * _h(m, 4))
		var sides := 7 + int(_h(m, 5) * 4.0)
		# Base ring, a jagged mid ring, and a summit off-centre.
		var base: Array = []
		var mid: Array = []
		for s in range(sides):
			var t := TAU * float(s) / float(sides) + _h(m * 31 + s, 6) * 0.4
			var r1 := rad * (0.85 + 0.3 * _h(m * 31 + s, 7))
			var r2 := rad * (0.38 + 0.22 * _h(m * 31 + s, 8))
			base.append(c + Vector3(cos(t) * r1, 0.0, sin(t) * r1))
			mid.append(c + Vector3(cos(t) * r2, hgt * (0.45 + 0.2 * _h(m * 31 + s, 9)), sin(t) * r2))
		var top := c + Vector3((_h(m, 10) - 0.5) * rad * 0.3, hgt, (_h(m, 11) - 0.5) * rad * 0.3)
		var snowy := hgt > 900.0
		for s in range(sides):
			var s2 := (s + 1) % sides
			var shade := rock if (s % 2 == 0) else rock_dk
			var out := ((base[s] as Vector3) + (base[s2] as Vector3)) * 0.5 - c
			kit.quad(base[s], base[s2], mid[s2], mid[s], shade, out)
			kit.tri(mid[s], mid[s2], top, snow if snowy else shade.lightened(0.06), out + Vector3(0, hgt * 0.3, 0))
	var mi := kit.instance("Mountains")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## The open plain round the square: flat grass to the horizon, flyable
## and landable, under the same ground shader (zone weights all zero).
## Leaves a hole where the square is; the inner edge tucks just under it.
static func plain(parent: Node, ground: RefCounted, shader: Shader) -> void:
	var sq: float = ground.SQ
	var far := 6000.0
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	# Rings of quads from the square's edge outward, getting coarser.
	var rings: Array = [sq - 1.0, sq + 8.0, sq + 24.0, sq + 60.0, sq + 140.0, sq + 320.0, 900.0, 1800.0, 3200.0, far]
	var per_side := 48
	var ring_pts: Array = []
	for r in rings:
		var pts: Array = []
		for k in range(per_side * 4):
			var t := float(k) / float(per_side)
			var side := int(t)
			var f := t - float(side)
			var p: Vector2
			match side:
				0: p = Vector2(-r + 2.0 * r * f, -r)
				1: p = Vector2(r, -r + 2.0 * r * f)
				2: p = Vector2(r - 2.0 * r * f, r)
				_: p = Vector2(-r, r - 2.0 * r * f)
			pts.append(p)
		ring_pts.append(pts)
	var n := per_side * 4
	for ri in range(rings.size()):
		for k in range(n):
			var p: Vector2 = ring_pts[ri][k]
			var y: float = ground.height_at(p.x, p.y)
			if ri == 0:
				y -= 0.15
			verts.append(Vector3(p.x, y, p.y))
			# The muskeg along the north of the square runs on out a little
			# and fades, so the bog colour doesn't stop dead at the edge.
			# The same forest-floor and bog weights the square uses, so the
			# ground types run on across the edge and fade out on the plain.
			var zw: Vector2 = ground.zone_at(p.x, p.y) if ground.has_method("zone_at") else Vector2.ZERO
			cols.append(Color(zw.x, 0, zw.y, 0))
			uvs.append(Vector2(0.15, 0.0))
	for ri in range(rings.size() - 1):
		for k in range(n):
			var a := ri * n + k
			var b := ri * n + (k + 1) % n
			var c := (ri + 1) * n + (k + 1) % n
			var d := (ri + 1) * n + k
			idx.append_array([a, c, b, a, d, c])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Plain"
	mi.mesh = mesh
	parent.add_child(mi)
