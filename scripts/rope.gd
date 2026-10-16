extends MeshInstance3D
## A rope, hose or strap (DESIGN_NOTES 94): a chain of points with gravity,
## fixed segment lengths, lying on the ground where it reaches it, drawn as a
## tube. Either end can be pinned to a point that moves (a reel, a hand, a
## hitch); `tension()` says how hard it's pulling when stretched taut, so
## whatever holds it can be held back or dragged.

var segments := 24
var length := 15.0                 # rope length when slack can't take up more
var radius := 0.02
var colour := Color(0.75, 0.12, 0.08)
var ground: Callable               # func(x, z) -> float, the ground under it
var stiff := 0.0                   # 0 a rope; a hose a little stiffer (fewer kinks)
var a_pin := Vector3.ZERO          # end A (always pinned)
var b_pin := Vector3.ZERO          # end B
var b_pinned := true
var sides := 6
var taut := 0.0                    # 0..1: under load the line pulls dead straight (a winch cable bar-tight)

var _p := PackedVector3Array()
var _o := PackedVector3Array()     # previous positions (verlet)
var _mesh: ImmediateMesh
var _mat: StandardMaterial3D


func setup(from: Vector3, to: Vector3) -> void:
	a_pin = from
	b_pin = to
	_p.resize(segments + 1)
	_o.resize(segments + 1)
	for i in range(segments + 1):
		var q := from.lerp(to, float(i) / float(segments))
		_p[i] = q
		_o[i] = q
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = colour
	_mat.roughness = 0.8
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func points() -> PackedVector3Array:
	return _p


func end_b() -> Vector3:
	return _p[segments]


## How far the pinned ends are apart beyond the rope's length (0 = slack).
func stretch() -> float:
	return maxf(a_pin.distance_to(b_pin) - length, 0.0)


func step(dt: float) -> void:
	if _p.is_empty():
		return
	var seg := length / float(segments)
	var g := Vector3(0, -9.81, 0) * dt * dt
	for i in range(segments + 1):
		var cur := _p[i]
		var vel := (cur - _o[i]) * 0.985
		_o[i] = cur
		_p[i] = cur + vel + g
	for it in range(12):
		_p[0] = a_pin
		if b_pinned:
			_p[segments] = b_pin
		for i in range(segments):
			var d := _p[i + 1] - _p[i]
			var l := d.length()
			if l <= seg or l < 0.00001:
				continue          # a rope goes slack; it won't stretch
			var wa := 0.0 if i == 0 else 1.0
			var wb := 0.0 if (i + 1 == segments and b_pinned) else 1.0
			if wa + wb <= 0.0:
				continue
			var corr := d * (1.0 - seg / l) / (wa + wb)
			_p[i] += corr * wa
			_p[i + 1] -= corr * wb
		if stiff > 0.0:
			for i in range(1, segments):
				var mid := (_p[i - 1] + _p[i + 1]) * 0.5
				_p[i] = _p[i].lerp(mid, stiff * 0.2)
		if ground.is_valid():
			for i in range(segments + 1):
				var gy: float = float(ground.call(_p[i].x, _p[i].z)) + radius
				if _p[i].y < gy:
					_p[i].y = gy
					# friction on the ground
					_o[i] = _o[i].lerp(_p[i], 0.5)
	_p[0] = a_pin
	if b_pinned:
		_p[segments] = b_pin
		if taut > 0.0:
			for i in range(1, segments):
				var line := a_pin.lerp(b_pin, float(i) / float(segments))
				_p[i] = _p[i].lerp(line, taut)
				_o[i] = _o[i].lerp(_p[i], taut)
	_draw()


func _draw() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in range(segments + 1):
		var t: Vector3
		if i == 0:
			t = _p[1] - _p[0]
		elif i == segments:
			t = _p[segments] - _p[segments - 1]
		else:
			t = _p[i + 1] - _p[i - 1]
		if t.length_squared() < 0.000001:
			t = Vector3.FORWARD
		t = t.normalized()
		var up := Vector3.UP if absf(t.y) < 0.95 else Vector3.RIGHT
		var x := t.cross(up).normalized()
		var y := x.cross(t).normalized()
		var ring: Array = []
		for s in range(sides):
			var a := TAU * float(s) / float(sides)
			ring.append([_p[i] + (x * cos(a) + y * sin(a)) * radius, x * cos(a) + y * sin(a)])
		rings.append(ring)
	for i in range(segments):
		for s in range(sides):
			var s2 := (s + 1) % sides
			var a0: Array = rings[i][s]
			var a1: Array = rings[i][s2]
			var b0: Array = rings[i + 1][s]
			var b1: Array = rings[i + 1][s2]
			for v in [a0, b0, a1, a1, b0, b1]:
				_mesh.surface_set_normal(v[1])
				_mesh.surface_add_vertex(v[0])
	_mesh.surface_end()
