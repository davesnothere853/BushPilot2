extends MeshInstance3D
## A real hose off a reel (DESIGN_NOTES 224, Dave): a chain of points 0.25 m
## apart with gravity (verlet), pinned at the reel's roller guide. It pays off
## the drum as the nozzle is pulled away (up to its full length) and winds back
## on when reeled in. It lies on the ground with friction and is kept out of
## every solid collider round it (the truck's own hulls, buildings, other
## machines): each point moving is ray-checked against the physics world and
## stopped on the surface, and each length of hose is checked so it can't cut
## through an edge. Drawn as a smooth tube with the nozzle on the end.

var seg := 0.15                    # m between points (short: it bends like a real hose)
var max_len := 15.2                # 50 ft
var stow_len := 0.22                # what hangs out of the guide when it's put away (the nozzle just below it)
var radius := 0.022
var colour := Color(0.62, 0.10, 0.08)
var ground: Callable               # func(x, z) -> float
var mask := 1                      # physics layers it can't pass through
var exclude: Array[RID] = []

var anchor := Vector3.ZERO         # world: the roller guide
var anchor_dir := Vector3.BACK     # world: which way the hose leaves the guide
var hand := Vector3.ZERO           # world: the nozzle when it's held
var held := false
var reeling := false               # winding back on
var paid := 0.22                    # m off the drum
var pressure := 0.0                 # 0 dry (lies flat and limp) .. 1 water on at pump pressure (round, firmer)
var _fill := 0.0                    # how full it is now (fills and drains over a second or two)

var _p := PackedVector3Array()
var _o := PackedVector3Array()
var _mesh: ImmediateMesh
var _mat: StandardMaterial3D
var _nozzle: MeshInstance3D
var _ready_done := false
var _anchor_prev := Vector3.ZERO
var pre := PackedVector3Array()     # world: the hose before the guide (what's left of the turn on the drum, the length down to the rollers): the same tube
var _hit := 0.0                     # hardest knock against a solid this step (m/s)
var _clank_cd := 0.0
var _clank: AudioStreamPlayer3D
var _clank_st: Array = []


func setup(at: Vector3, dir: Vector3) -> void:
	anchor = at
	anchor_dir = dir.normalized()
	_p.clear()
	_o.clear()
	var n := maxi(int(ceil(paid / seg)), 1)
	for i in range(n + 1):
		var q := at + anchor_dir * 0.05 * float(mini(i, 1)) + Vector3(0, -seg * float(maxi(i - 1, 0)), 0)
		_p.append(q)
		_o.append(q)
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = colour
	_mat.roughness = 0.85
	_mat.metallic_specular = 0.3
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED     # the same rubber as the turns on the drum, lit from outside
	material_override = _mat
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_nozzle = MeshInstance3D.new()
	_nozzle.mesh = _nozzle_mesh()
	_nozzle.top_level = true
	add_child(_nozzle)
	_ready_done = true
	_draw()


func end_point() -> Vector3:
	return _p[_p.size() - 1] if not _p.is_empty() else anchor


func end_b() -> Vector3:
	return end_point()


func points() -> PackedVector3Array:
	return _p


## How much is wound on the drum, 0..1 (the drum's hose shrinks as it pays out).
func on_drum() -> float:
	return clampf(1.0 - paid / max_len, 0.0, 1.0)


func step(dt: float) -> void:
	if not _ready_done or _p.size() < 2:
		return
	dt = minf(dt, 1.0 / 30.0)
	_fill = move_toward(_fill, pressure, dt * (0.8 if pressure > _fill else 0.5))
	# how the guide (the truck) is moving: knocks are measured against it
	var av := (anchor - _anchor_prev) if _anchor_prev != Vector3.ZERO else Vector3.ZERO
	_anchor_prev = anchor
	_hit = 0.0
	_clank_cd = maxf(_clank_cd - dt, 0.0)
	var stiff := lerpf(0.025, 0.07, _fill)          # dry: floppy; charged: holds a curve
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null
	# pay out / wind in at the reel end
	var n := _p.size() - 1
	if reeling:
		paid = maxf(paid - 1.6 * dt, stow_len)
		if paid <= stow_len + 0.001:
			reeling = false
	elif held:
		# the hand pulls hose off when the line from the guide is nearly straight
		var straight := anchor.distance_to(hand)
		if (straight > float(n) * seg * 0.92 or _p[n].distance_to(hand) > 0.3) and paid < max_len:
			paid = minf(paid + maxf(2.5 * dt, straight - float(n) * seg * 0.92), max_len)
	var want := maxi(int(ceil(paid / seg - 0.0001)), 1)
	while _p.size() - 1 < want:
		# a new point comes off the guide: right at the guide, on the line to the
		# one before it (the first length grows from nothing, so it feeds smoothly)
		var to1 := (_p[1] - anchor)
		var q := anchor + (to1.normalized() if to1.length_squared() > 1e-8 else anchor_dir) * 0.002
		_p.insert(1, q)
		_o.insert(1, q)
	while _p.size() - 1 > want and _p.size() > 2:
		_p.remove_at(1)
		_o.remove_at(1)
	n = _p.size() - 1
	# the first length (at the guide) is whatever's left over, 0..seg: the hose
	# runs out through the guide continuously, not a length at a time
	var first := clampf(paid - float(n - 1) * seg, 0.002, seg)
	# integrate
	var g := Vector3(0, -9.81, 0) * dt * dt
	for i in range(1, n + 1):
		var cur := _p[i]
		var vel := av + (cur - _o[i] - av) * 0.975    # damped relative to the truck (not air drag): it swings when the truck moves
		_o[i] = cur
		_p[i] = cur + vel + g
	var end_pinned := held and not reeling
	if not held and not reeling and paid <= stow_len + 0.01:
		end_pinned = false
	# constraints: fixed lengths, a little stiffness, the ground
	for it in range(14):
		_p[0] = anchor
		_p[1] = _p[1].lerp(anchor + anchor_dir * first, 0.5)     # it leaves the guide straight
		if end_pinned:
			_p[n] = hand
		for i in range(n):
			var d := _p[i + 1] - _p[i]
			var l := d.length()
			if l < 0.00001:
				continue
			var wa := 0.0 if i == 0 else 1.0
			var wb := 0.0 if (i + 1 == n and end_pinned) else (0.45 if i + 1 == n else 1.0)     # the nozzle's weight on the end
			if wa + wb <= 0.0:
				continue
			var rest := first if i == 0 else seg
			var corr := d * (1.0 - rest / l) / (wa + wb)
			_p[i] += corr * wa
			_p[i + 1] -= corr * wb
		for i2 in range(1, n):
			var mid := (_p[i2 - 1] + _p[i2 + 1]) * 0.5
			_p[i2] = _p[i2].lerp(mid, stiff)                         # a hose's stiffness: no sharp kinks
		if ground.is_valid():
			for i3 in range(1, n + 1):
				var gy: float = float(ground.call(_p[i3].x, _p[i3].z)) + radius * lerpf(0.35, 1.0, _fill)
				if _p[i3].y < gy:
					_p[i3].y = gy
					_o[i3] = _o[i3].lerp(_p[i3], 0.6)             # friction on the ground
	# solids: no point passes into a collider, no length cuts through an edge
	if space != null:
		var q := PhysicsRayQueryParameters3D.new()
		q.collision_mask = mask
		q.exclude = exclude
		q.hit_back_faces = false
		for i4 in range(1, n + 1):
			if end_pinned and i4 == n:
				continue
			q.from = _o[i4]
			q.to = _p[i4]
			if q.from.distance_squared_to(q.to) < 1e-8:
				continue
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var nrm: Vector3 = hit["normal"]
				_p[i4] = (hit["position"] as Vector3) + nrm * (radius * 1.5)
				# lose the speed into the surface, keep a bit of slide
				var v := _p[i4] - _o[i4]
				var knock := -(v - av).dot(nrm) / maxf(dt, 0.001)
				if i4 >= maxi(n - 1, 2) and knock < 6.0:                    # the nozzle end knocking the truck (faster = a collider a tick behind, not a knock)
					_hit = maxf(_hit, knock)
				var vr := v - av                                   # against the truck, not the world
				_o[i4] = _p[i4] - (av + (vr - nrm * vr.dot(nrm)) * 0.5)
		for i5 in range(n):
			q.from = _p[i5]
			q.to = _p[i5 + 1]
			var hit2 := space.intersect_ray(q)
			if not hit2.is_empty():
				var nrm2: Vector3 = hit2["normal"]
				if i5 + 1 < n or not end_pinned:
					_p[i5 + 1] += nrm2 * radius * 2.0
				if i5 > 0:
					_p[i5] += nrm2 * radius * 2.0
	_p[0] = anchor
	if end_pinned:
		_p[n] = hand
	if _hit > 0.35 and _clank_cd <= 0.0:
		_play_clank(_hit)
	_draw()


## The brass nozzle knocking the steel at the back of the truck.
func _play_clank(speed: float) -> void:
	_clank_cd = 0.22
	if _clank == null:
		_clank = AudioStreamPlayer3D.new()
		_clank.top_level = true
		_clank.max_distance = 40.0
		add_child(_clank)
		var A = load("res://scripts/audio.gd")
		for ci in range(4):
			var st: AudioStream = A._file("res://assets/sounds/rattle/clunk_%d.wav" % ci, false)
			if st != null:
				_clank_st.append(st)
	if _clank_st.is_empty():
		return
	_clank.global_position = end_point()
	_clank.stream = _clank_st[randi() % _clank_st.size()]
	_clank.pitch_scale = randf_range(1.5, 1.9)          # higher than a body clunk: brass on steel
	_clank.volume_db = clampf(linear_to_db(clampf(speed / 2.5, 0.05, 1.0)), -26.0, 0.0)
	_clank.play()


func _draw() -> void:
	_mesh.clear_surfaces()
	var pts := pre.duplicate()
	pts.append_array(_p)
	var np := pre.size()
	var n := pts.size() - 1
	if n < 1:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var rings: Array = []
	var up_prev := Vector3.UP
	var x_prev := Vector3.ZERO
	for i in range(n + 1):
		var t: Vector3
		if i == 0:
			t = pts[1] - pts[0]
		elif i == n:
			t = pts[n] - pts[n - 1]
		else:
			t = pts[i + 1] - pts[i - 1]
		if t.length_squared() < 1e-8:
			t = Vector3.FORWARD
		t = t.normalized()
		var up := up_prev if absf(up_prev.dot(t)) < 0.95 else (Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD)
		var x := t.cross(up).normalized()
		var y := x.cross(t).normalized()
		up_prev = y
		# dry hose lies flat: the flat side faces up (as it would lie on the
		# ground); it rounds out as water fills it. Off the guide it's still round
		# (it comes off the drum like that), going flat over the first 0.4 m.
		var flat := (1.0 - _fill) * clampf(float(i - np) * seg / 0.4, 0.0, 1.0)
		# lean the flat side toward level, smoothly (a hanging length keeps the
		# way it was turned, so it doesn't twist like a ribbon)
		var wup := Vector3.UP - t * t.dot(Vector3.UP)
		var lw := clampf((wup.length_squared() - 0.05) / 0.4, 0.0, 1.0)
		if lw > 0.0:
			var yb := y.slerp(wup.normalized() * signf(y.dot(wup) + 1e-6), lw) if y.dot(wup) > -0.99 else y
			y = (yb - t * t.dot(yb)).normalized()
			x = t.cross(y).normalized()
		if x_prev != Vector3.ZERO and x.dot(x_prev) < 0.0:
			x = -x                                   # no half turn between rings
			y = -y
		x_prev = x
		up_prev = y
		var rx := radius * (1.0 + 0.45 * flat)
		var ry := radius * (1.0 - 0.62 * flat)
		var ring: Array = []
		for s in range(sides):
			var a := TAU * float(s) / float(sides)
			var nrm := (x * (cos(a) / rx) + y * (sin(a) / ry)).normalized()
			ring.append([pts[i] + x * cos(a) * rx + y * sin(a) * ry, nrm])
		rings.append(ring)
	for i2 in range(n):
		for s2 in range(sides):
			var s3 := (s2 + 1) % sides
			for v in [rings[i2][s2], rings[i2][s3], rings[i2 + 1][s2], rings[i2][s3], rings[i2 + 1][s3], rings[i2 + 1][s2]]:
				_mesh.surface_set_normal(v[1])
				_mesh.surface_add_vertex(v[0])
	_mesh.surface_end()
	# the nozzle on the end, along the last length
	n = _p.size() - 1
	var d := (_p[n] - _p[n - 1]).normalized()
	if d.length_squared() < 0.5:
		d = Vector3.DOWN
	var upv := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	_nozzle.global_transform = Transform3D(Basis.looking_at(d, upv), _p[n])


## The nozzle: brass coupling, black body with its bail handle, the tip.
static func _nozzle_mesh() -> ArrayMesh:
	var MK = load("res://scripts/meshkit.gd")
	var k = MK.new()
	var fwd := Basis(Vector3.RIGHT, -PI * 0.5)        # cylinders along -Z (the way it points)
	k.cylinder(Transform3D(fwd, Vector3.ZERO), 0.03, 0.03, 0.04, 10, Color(0.72, 0.58, 0.25))
	k.cylinder(Transform3D(fwd, Vector3(0, 0, -0.04)), 0.028, 0.024, 0.14, 10, Color(0.08, 0.08, 0.08))
	k.cylinder(Transform3D(fwd, Vector3(0, 0, -0.18)), 0.024, 0.016, 0.06, 10, Color(0.72, 0.58, 0.25))
	k.box_at(Vector3(0, 0.045, -0.09), Vector3(0.012, 0.012, 0.11), Color(0.1, 0.1, 0.1))        # bail
	for bz in [-0.04, -0.14]:
		k.box_at(Vector3(0, 0.035, bz), Vector3(0.01, 0.025, 0.01), Color(0.1, 0.1, 0.1))
	return k.commit()
