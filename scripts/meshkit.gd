extends RefCounted
## Small helper for building flat-shaded, vertex-coloured low-poly meshes in code.
## Every shape takes care of its own triangle winding, so callers only describe geometry.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()

static var _shared_material: StandardMaterial3D = null


static func material() -> StandardMaterial3D:
	if _shared_material == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.85
		m.metallic = 0.0
		m.metallic_specular = 0.3
		_shared_material = m
	return _shared_material


## One triangle. `out_hint` is any vector pointing roughly away from the solid;
## the winding is flipped when needed so the face points that way.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out_hint: Vector3 = Vector3.ZERO) -> void:
	var nrm := (c - a).cross(b - a)
	if out_hint != Vector3.ZERO and nrm.dot(out_hint) < 0.0:
		var t := b
		b = c
		c = t
		nrm = -nrm
	if nrm.length_squared() < 1.0e-12:
		return
	nrm = nrm.normalized()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	norms.append(nrm)
	norms.append(nrm)
	norms.append(nrm)
	cols.append(col)
	cols.append(col)
	cols.append(col)


## A triangle with its own colour and normal at each corner (plants: blades
## shade dark at the root and light at the tip, and catch light softly).
func tri_c(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	verts.append(a)
	verts.append(b)
	verts.append(c)
	norms.append(na)
	norms.append(nb)
	norms.append(nc)
	cols.append(ca)
	cols.append(cb)
	cols.append(cc)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out_hint: Vector3 = Vector3.ZERO) -> void:
	tri(a, b, c, col, out_hint)
	tri(a, c, d, col, out_hint)


## Detail settings a builder can turn up while it builds (the code-built
## vehicles, DESIGN_NOTES 197) and put back after: `detail` multiplies the sides
## of every cylinder, `bevel` (m) rounds the edges of every box.
static var detail := 1.0
static var bevel := 0.0


## Box centred on xf.origin, with `size` measured along the transform's axes.
func box(xf: Transform3D, size: Vector3, col: Color) -> void:
	if bevel > 0.0:
		var r := minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.3)
		if r > 0.0008:
			rbox(xf, size, col, r)
			return
	var h := size * 0.5
	var p: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				p.append(xf * Vector3(h.x * sx, h.y * sy, h.z * sz))
	# index = (sx>0)*4 + (sy>0)*2 + (sz>0)
	var bx := xf.basis.x
	var by := xf.basis.y
	var bz := xf.basis.z
	quad(p[4], p[5], p[7], p[6], col, bx)
	quad(p[0], p[1], p[3], p[2], col, -bx)
	quad(p[2], p[3], p[7], p[6], col, by)
	quad(p[0], p[1], p[5], p[4], col, -by)
	quad(p[1], p[3], p[7], p[5], col, bz)
	quad(p[0], p[2], p[6], p[4], col, -bz)


## A box with rounded edges and corners (radius r): each face a grid whose
## outer rows wrap round the edge in three steps.
func rbox(xf: Transform3D, size: Vector3, col: Color, r: float) -> void:
	var h := size * 0.5
	var inner := h - Vector3(r, r, r)
	# per axis: the flat middle, then three steps round each edge
	var fr := [0.0, 0.38, 0.71, 0.92, 1.0]
	var axes := [[0, 1, 2], [1, 2, 0], [2, 0, 1]]
	for ax in axes:
		var n_i: int = ax[0]
		var u_i: int = ax[1]
		var v_i: int = ax[2]
		for sgn in [-1.0, 1.0]:
			var us := _rb_coords(h[u_i], r, fr)
			var vs := _rb_coords(h[v_i], r, fr)
			for iu in range(us.size() - 1):
				for iv in range(vs.size() - 1):
					var pts: Array = []
					for c in [[iu, iv], [iu + 1, iv], [iu + 1, iv + 1], [iu, iv + 1]]:
						var q := Vector3.ZERO
						q[n_i] = sgn * h[n_i]
						q[u_i] = us[c[0]]
						q[v_i] = vs[c[1]]
						var inn := q.clamp(-inner, inner)
						var d := q - inn
						var pp := inn + (d.normalized() * r if d.length() > 1e-6 else d)
						pts.append(xf * pp)
					var nrm := Vector3.ZERO
					nrm[n_i] = sgn
					quad(pts[0], pts[1], pts[2], pts[3], col, xf.basis * nrm)


static func _rb_coords(hh: float, r: float, fr: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in range(fr.size() - 1, -1, -1):
		out.append(-(hh - r) - r * float(fr[i]) * 0.0 - (r * sin(float(fr[i]) * PI * 0.5) if i > 0 else 0.0))
	for i in range(fr.size()):
		out.append((hh - r) + (r * sin(float(fr[i]) * PI * 0.5) if i > 0 else 0.0))
	# (the two middle points are the flat face's edges: -(hh-r) and hh-r)
	return out


## Box given by its centre and size in the kit's own space.
func box_at(center: Vector3, size: Vector3, col: Color) -> void:
	box(Transform3D(Basis.IDENTITY, center), size, col)


## Cylinder or cone frustum along the transform's +Y axis, from y = 0 to y = height.
func cylinder(xf: Transform3D, r_bottom: float, r_top: float, height: float, sides: int, col: Color, caps: bool = true) -> void:
	sides = maxi(sides, int(round(sides * detail)))
	var axis := xf.basis.y.normalized()
	var c0 := xf * Vector3.ZERO
	var c1 := xf * Vector3(0.0, height, 0.0)
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var b0 := xf * (d0 * r_bottom)
		var b1 := xf * (d1 * r_bottom)
		var t0 := xf * (d0 * r_top + Vector3(0.0, height, 0.0))
		var t1 := xf * (d1 * r_top + Vector3(0.0, height, 0.0))
		var out := xf.basis * ((d0 + d1) * 0.5)
		if r_top > 0.0001:
			quad(b0, b1, t1, t0, col, out)
		else:
			tri(b0, b1, c1, col, out)
		if caps:
			if r_bottom > 0.0001:
				tri(c0, b0, b1, col, -axis)
			if r_top > 0.0001:
				tri(c1, t0, t1, col, axis)


## Skin stretched over a series of rings (each ring has the same number of points).
func loft(rings: Array, col: Color, cap_start: bool = true, cap_end: bool = true) -> void:
	for r in range(rings.size() - 1):
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		var ca := _centroid(a)
		var cb := _centroid(b)
		var mid := (ca + cb) * 0.5
		var count := a.size()
		for i in range(count):
			var j := (i + 1) % count
			var face_mid := (a[i] + a[j] + b[i] + b[j]) * 0.25
			quad(a[i], a[j], b[j], b[i], col, face_mid - mid)
	if cap_start:
		_cap(rings[0], col, _centroid(rings[0]) - _centroid(rings[1]))
	if cap_end:
		var last: int = rings.size() - 1
		_cap(rings[last], col, _centroid(rings[last]) - _centroid(rings[last - 1]))


func _centroid(ring: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	return c / float(ring.size())


func _cap(ring: PackedVector3Array, col: Color, out: Vector3) -> void:
	var c := _centroid(ring)
	for i in range(ring.size()):
		tri(c, ring[i], ring[(i + 1) % ring.size()], col, out)


## Smooth shading: corners shared by faces that meet at less than `crease_deg`
## get an averaged normal, so curved shapes look round while sharp edges such as
## box corners and trailing edges stay crisp.
func smooth(crease_deg: float = 40.0) -> void:
	var groups := shared_groups(verts)
	var face := PackedVector3Array()
	face.resize(verts.size())
	for i in range(0, verts.size(), 3):
		var nrm := norms[i]
		face[i] = nrm
		face[i + 1] = nrm
		face[i + 2] = nrm
	norms = smoothed(face, groups, cos(deg_to_rad(crease_deg)))


## For each vertex, the other vertices at the same spot (flattened: start, count, then indices).
static func shared_groups(v: PackedVector3Array) -> Array:
	var by_pos := {}
	for i in range(v.size()):
		var key := Vector3i((v[i] * 2000.0).round())
		if by_pos.has(key):
			by_pos[key].append(i)
		else:
			by_pos[key] = [i]
	var owner := PackedInt32Array()
	owner.resize(v.size())
	var lists: Array = []
	for key in by_pos.keys():
		var lst: Array = by_pos[key]
		var packed := PackedInt32Array(lst)
		var id := lists.size()
		lists.append(packed)
		for i in lst:
			owner[i] = id
	return [owner, lists]


static func smoothed(face: PackedVector3Array, groups: Array, cos_limit: float) -> PackedVector3Array:
	var owner: PackedInt32Array = groups[0]
	var lists: Array = groups[1]
	var out := PackedVector3Array()
	out.resize(face.size())
	for i in range(face.size()):
		var fi := face[i]
		var acc := Vector3.ZERO
		var lst: PackedInt32Array = lists[owner[i]]
		for j in lst:
			var fj := face[j]
			if fj.dot(fi) >= cos_limit:
				acc += fj
		out[i] = acc.normalized() if acc.length_squared() > 1.0e-12 else fi
	return out


func is_empty() -> bool:
	return verts.is_empty()


func clear() -> void:
	verts = PackedVector3Array()
	norms = PackedVector3Array()
	cols = PackedColorArray()


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	return mesh


func instance(node_name: String = "Mesh") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = commit()
	return mi
