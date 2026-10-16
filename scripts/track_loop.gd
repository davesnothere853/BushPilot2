extends MultiMeshInstance3D
## One crawler track's shoes, running round the real loop: along the ground,
## up over the sprocket, back over the top and down the idler. advance() by
## metres travelled and the shoes go round; reverse and they come back.

var _total := 1.0
var _phase := 0.0
var _count := 0
var _x := 0.0
var _zc := 0.0      # end-circle centres sit at +/- _zc
var _yc := 0.0
var _r := 0.0
var _run := 0.0


func setup(x: float, zc: float, y_bottom: float, y_top: float,
		count: int, shoe: Vector3, col: Color) -> void:
	_x = x
	_zc = zc
	_r = (y_top - y_bottom) * 0.5
	_yc = y_bottom + _r
	_run = zc * 2.0
	_total = _run * 2.0 + TAU * _r
	_count = count
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = shoe
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.9
	bm.material = mat
	mm.mesh = bm
	mm.instance_count = count
	multimesh = mm
	_bushings(shoe)
	_layout()
	_links(shoe, col)


## The chain's bushings: a steel tube across between the two link rails at every
## link, where the sprocket's teeth bite (Dave: the real chain, from the photos).
var _bush: MultiMeshInstance3D
var _bush_in := 0.0
func _bushings(shoe: Vector3) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.028
	cm.bottom_radius = 0.028
	cm.height = shoe.x * 0.5
	cm.radial_segments = 8
	cm.rings = 1
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.32, 0.31, 0.30)
	bm.metallic = 0.6
	bm.roughness = 0.5
	cm.material = bm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = _count
	_bush = MultiMeshInstance3D.new()
	_bush.name = "Bushings"
	_bush.multimesh = mm
	_bush_in = shoe.y * 0.5 + 0.045
	add_child(_bush)


## Wheels that turn with the belt: [node, rolling radius]. The sprocket and
## idler are registered here so their teeth and flanges roll with the chain.
var wheels: Array = []
func add_wheel(n: Node3D, roll_r: float) -> void:
	wheels.append([n, roll_r])


## The chain under the shoes: two rails of links running the whole loop, so the
## track reads as one connected belt (Dave: the tracks weren't connected).
func _links(shoe: Vector3, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 96
	var lc := col.darkened(0.25)
	for side in [-1.0, 1.0]:
		var xr: float = _x + float(side) * shoe.x * 0.28
		var rings: Array = []
		for i in range(n + 1):
			var xf := _pose(_total * float(i) / float(n))
			var up := xf.basis.y                  # out of the loop's middle
			var c := xf.origin + up * (shoe.y * 0.5 + 0.03)
			c.x = xr
			var ring := PackedVector3Array()
			for q in [Vector2(-0.035, 0.0), Vector2(0.035, 0.0), Vector2(0.035, 0.07), Vector2(-0.035, 0.07)]:
				ring.append(c + Vector3(q.x, 0, 0) + up * q.y)
			rings.append(ring)
		for i in range(n):
			var r0: PackedVector3Array = rings[i]
			var r1: PackedVector3Array = rings[i + 1]
			for e in range(4):
				var e2 := (e + 1) % 4
				var nrm := ((r0[e] + r0[e2]) * 0.5 - (r0[0] + r0[1] + r0[2] + r0[3]) * 0.25).normalized()
				for v in [r0[e], r1[e], r1[e2], r0[e], r1[e2], r0[e2]]:
					st.set_normal(nrm)
					st.set_color(lc)
					st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "Links"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	m.metallic = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)


## Shoe pose `s` metres along the loop, starting under the front idler and
## running back along the ground first.
func _pose(s: float) -> Transform3D:
	var arc := PI * _r
	var ang: float
	var z: float
	var y: float
	if s < _run:                       # bottom run, rolling back
		z = -_zc + s
		y = _yc - _r
		ang = 0.0
	elif s < _run + arc:               # up and over the rear wheel
		var th := (s - _run) / _r
		z = _zc + _r * sin(th)
		y = _yc - _r * cos(th)
		ang = -th                       # the shoe's face stays out from the wheel (was +th: the pads fanned out like a paddle wheel)
	elif s < _run * 2.0 + arc:         # top run, coming forward
		z = _zc - (s - _run - arc)
		y = _yc + _r
		ang = PI
	else:                              # down round the front wheel
		var th := (s - _run * 2.0 - arc) / _r
		z = -_zc - _r * sin(th)
		y = _yc + _r * cos(th)
		ang = PI - th
	return Transform3D(Basis(Vector3.RIGHT, ang), Vector3(_x, y, z))


func _layout() -> void:
	for k in range(_count):
		var s := fposmod(_phase + _total * float(k) / float(_count), _total)
		var xf := _pose(s)
		multimesh.set_instance_transform(k, xf)
		if _bush != null:
			# offset half a pitch so each bushing sits at the joint between two shoes
			var xb := _pose(fposmod(s + _total / float(_count) * 0.5, _total))
			_bush.multimesh.set_instance_transform(k, Transform3D(xb.basis * Basis(Vector3.BACK, PI * 0.5), xb.origin + xb.basis.y * _bush_in))
	for w in wheels:
		(w[0] as Node3D).rotation.x = -_phase / float(w[1])


## The track rolled `dist` metres (negative in reverse).
func advance(dist: float) -> void:
	if absf(dist) < 0.00001:
		return
	_phase = fposmod(_phase + dist, _total)
	_layout()
