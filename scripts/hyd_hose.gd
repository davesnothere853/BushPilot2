extends Node3D
## A hydraulic hose that really hangs and swings (Dave: "simulate all the
## hydraulic lines and physics"): a chain of points (Verlet) under gravity,
## held at a fixed length, a little stiff so it bends in a smooth loop, both
## ends pinned to fittings on whatever parts they're fastened to (the frame, a
## ram's barrel, the boom). When the boom lifts or the machine bounces the
## hose follows, sags, swings and settles. Drawn as a rubber tube rebuilt
## each frame in world space.

var a_node: Node3D
var a_local := Vector3.ZERO
var b_node: Node3D
var b_local := Vector3.ZERO
var radius := 0.018
var slack := 1.18                  # hose length / straight distance at setup
var segs := 24
var stiffness := 0.25              # 0 a rope .. 1 a rod
var hard := true                   # Dave: steel hard line, no soft rope - bent tube between the fittings
var _p: PackedVector3Array
var _q: PackedVector3Array         # last frame's points
var _seg_len := 0.1
var _mesh := ImmediateMesh.new()
var _mi := MeshInstance3D.new()
static var _mat: StandardMaterial3D


func setup(a: Node3D, a_pt: Vector3, b: Node3D, b_pt: Vector3, r: float = 0.018, sl: float = 1.18) -> void:
	a_node = a
	a_local = a_pt
	b_node = b
	b_local = b_pt
	radius = r
	slack = sl
	top_level = true
	global_transform = Transform3D.IDENTITY
	var A := a_node.global_transform * a_local
	var B := b_node.global_transform * b_local
	_seg_len = A.distance_to(B) * slack / float(segs)
	_p = PackedVector3Array()
	_q = PackedVector3Array()
	for i in range(segs + 1):
		var f := float(i) / segs
		var p := A.lerp(B, f) - Vector3(0, A.distance_to(B) * 0.25 * 4.0 * f * (1.0 - f), 0)
		_p.append(p)
		_q.append(p)
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.62, 0.63, 0.65)
		_mat.metallic = 0.8
		_mat.roughness = 0.3
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi.mesh = _mesh
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mi)
	for k in range(40):
		_step(1.0 / 60.0)
	_draw()


func _physics_process(dt: float) -> void:
	if a_node == null or not is_instance_valid(a_node) or not is_instance_valid(b_node):
		return
	_step(minf(dt, 1.0 / 30.0))


func _process(dt: float) -> void:
	_draw()
	if leak > 0.0 or not _drops.is_empty():
		_leak_step(dt)


## A crack in the line (Dave: a damaged line leaks): oil sprays and drips from
## it, and a puddle spreads on the ground under it. `pressure` (bar) is set by
## the machine from its sim - the harder it's pushed, the harder it sprays.
var leak := 0.0
var leak_pressure := 0.0
var _drops: Array = []
var _drop_t := 0.0
var _puddle: MeshInstance3D
var _puddle_r := 0.0
static var _drop_mat: StandardMaterial3D


func _leak_step(dt: float) -> void:
	var n := _p.size()
	if n < 2:
		return
	var at := _p[n / 2]
	var dir := (_p[mini(n / 2 + 1, n - 1)] - _p[n / 2 - 1]).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var ground := (get_parent() as Node3D).global_position.y + 0.01 if get_parent() is Node3D else at.y - 2.0
	if _drop_mat == null:
		_drop_mat = StandardMaterial3D.new()
		_drop_mat.albedo_color = Color(0.22, 0.13, 0.04)
		_drop_mat.metallic = 0.3
		_drop_mat.roughness = 0.15
	_drop_t -= dt
	var rate := leak * (6.0 + leak_pressure * 0.25)          # drops a second: a weep at low pressure, a spray at high
	while leak > 0.0 and _drop_t <= 0.0 and _drops.size() < 160:
		_drop_t += 1.0 / maxf(rate, 0.5)
		var q := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.008 + 0.006 * randf()
		sm.height = sm.radius * 2.0
		sm.radial_segments = 6
		sm.rings = 3
		sm.material = _drop_mat
		q.mesh = sm
		q.top_level = true
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
		q.global_position = at
		var jet := clampf(leak_pressure / 200.0, 0.0, 1.0)
		var v := (side * (1.0 if randf() < 0.5 else -1.0) * (0.3 + 3.5 * jet) + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 1.2) * jet, randf_range(-0.3, 0.3)))
		_drops.append([q, v])
	var i := 0
	while i < _drops.size():
		var d: Array = _drops[i]
		var q2: MeshInstance3D = d[0]
		var v2: Vector3 = d[1]
		v2 += Vector3(0, -9.8, 0) * dt
		d[1] = v2
		q2.global_position += v2 * dt
		if q2.global_position.y <= ground:
			_grow_puddle(Vector3(q2.global_position.x, ground, q2.global_position.z))
			q2.queue_free()
			_drops.remove_at(i)
			continue
		i += 1


func _grow_puddle(p: Vector3) -> void:
	if _puddle == null:
		_puddle = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.height = 0.004
		cm.radial_segments = 20
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.05, 0.02, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.4
		m.roughness = 0.05
		cm.material = m
		_puddle.mesh = cm
		_puddle.top_level = true
		add_child(_puddle)
		_puddle.global_position = p
		_puddle_r = 0.04
	_puddle_r = minf(_puddle_r + 0.0015 / maxf(_puddle_r, 0.04), 0.9)        # spreads, slower as it gets big
	_puddle.global_position = _puddle.global_position.lerp(p, 0.02)
	_puddle.scale = Vector3(_puddle_r, 1, _puddle_r * 0.85)


## Mend it: no more leak (the puddle stays where it soaked in).
func mend() -> void:
	leak = 0.0


func _step(dt: float) -> void:
	if hard:
		_hard_path()
		return
	var g := Vector3(0, -9.8, 0) * dt * dt
	var n := _p.size()
	for i in range(1, n - 1):
		var cur := _p[i]
		var v := (cur - _q[i]) * 0.97             # air and rubber damping
		_q[i] = cur
		_p[i] = cur + v + g
	_p[0] = a_node.global_transform * a_local
	_p[n - 1] = b_node.global_transform * b_local
	_q[0] = _p[0]
	_q[n - 1] = _p[n - 1]
	for it in range(10):
		for i in range(n - 1):
			var d := _p[i + 1] - _p[i]
			var L := d.length()
			if L < 0.00001:
				continue
			var corr := d * ((L - _seg_len) / L) * 0.5
			if i > 0:
				_p[i] += corr
			else:
				_p[i + 1] -= corr
				continue
			if i + 1 < n - 1:
				_p[i + 1] -= corr
			else:
				_p[i] += corr
		# stiffness: each inner point eased toward the middle of its neighbours
		for i in range(1, n - 1):
			var mid := (_p[i - 1] + _p[i + 1]) * 0.5
			_p[i] = _p[i].lerp(mid, stiffness * 0.3)
	# never below the ground the machine stands on
	var gy := (get_parent() as Node3D).global_position.y + 0.02 if get_parent() is Node3D else -INF
	for i in range(1, n - 1):
		if _p[i].y < gy:
			_p[i].y = gy


## A hard line routed through waypoints fixed on the first part (along the
## boom, round a casting), then a short bend into the fitting at the far end;
## laid again every frame as the parts move.
var via: Array = []                # waypoints in a_node's frame


func _hard_path() -> void:
	var pts: Array = [a_node.global_transform * a_local]
	for w in via:
		pts.append(a_node.global_transform * (w as Vector3))
	var B := b_node.global_transform * b_local
	var last: Vector3 = pts[pts.size() - 1]
	pts.append(B + (last - B).normalized() * minf(0.08, last.distance_to(B) * 0.3))
	pts.append(B)
	# resample by length so the tube's rings are even
	var total := 0.0
	for i in range(pts.size() - 1):
		total += (pts[i] as Vector3).distance_to(pts[i + 1])
	var n := _p.size()
	var seg := 0
	var acc := 0.0
	for k in range(n):
		var want := total * float(k) / float(n - 1)
		while seg < pts.size() - 2 and acc + (pts[seg] as Vector3).distance_to(pts[seg + 1]) < want:
			acc += (pts[seg] as Vector3).distance_to(pts[seg + 1])
			seg += 1
		var L: float = (pts[seg] as Vector3).distance_to(pts[seg + 1])
		var f: float = clampf((want - acc) / maxf(L, 0.0001), 0.0, 1.0)
		_p[k] = (pts[seg] as Vector3).lerp(pts[seg + 1], f)
		_q[k] = _p[k]


func _draw() -> void:
	_mesh.clear_surfaces()
	var n := _p.size()
	if n < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	var rings: Array = []
	var prev_side := Vector3.RIGHT
	for i in range(n):
		var t := (_p[mini(i + 1, n - 1)] - _p[maxi(i - 1, 0)]).normalized()
		var side := t.cross(prev_side.cross(t)).normalized()
		if side.length() < 0.5:
			side = t.cross(Vector3.UP).normalized()
		prev_side = side
		var up := t.cross(side).normalized()
		var ring := PackedVector3Array()
		for s in range(sides):
			var a := TAU * float(s) / sides
			ring.append(_p[i] + (side * cos(a) + up * sin(a)) * radius)
		rings.append(ring)
	for i in range(n - 1):
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		for s in range(sides):
			var s2 := (s + 1) % sides
			var nrm := ((r0[s] + r0[s2]) * 0.5 - _p[i]).normalized()
			_mesh.surface_set_normal(nrm)
			_mesh.surface_add_vertex(r0[s])
			_mesh.surface_add_vertex(r1[s])
			_mesh.surface_add_vertex(r1[s2])
			_mesh.surface_add_vertex(r0[s])
			_mesh.surface_add_vertex(r1[s2])
			_mesh.surface_add_vertex(r0[s2])
	_mesh.surface_end()
