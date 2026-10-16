extends MeshInstance3D
## A mesh that can be dented and scratched. The source shapes are cut into
## small triangles first, so a hit can push in a patch of skin instead of
## moving a whole panel. Faces stay flat-shaded, so crumpled metal catches
## the light in creases.
##
## Long edges are split at their midpoints until every edge is short. An edge is
## always split the same way whichever triangle it belongs to, so neighbouring
## triangles stay joined however the skin is pushed around.

const BARE := Color(0.72, 0.73, 0.74)       # paint scraped back to aluminium
const GOUGE := Color(0.22, 0.21, 0.20)      # deep scratches and dirt
const MAX_PUSH := 1.1
const CHAR := Color(0.045, 0.04, 0.035)        # paint burned off and blackened

var base_v := PackedVector3Array()
var base_c := PackedColorArray()
var disp := PackedVector3Array()
var scuff := PackedFloat32Array()
var charred := PackedFloat32Array()
var noise := PackedFloat32Array()
var crease_deg := 38.0
var _groups: Array = []
## Optional extra shape change, called per vertex: func(p: Vector3) -> Vector3 offset.
var bend: Callable
var bend_active := false
var _dirty := true


func setup(kit: RefCounted, max_edge: float) -> void:
	_subdivide(kit.verts, kit.cols, max_edge)
	var n := base_v.size()
	disp.resize(n)
	scuff.resize(n)
	charred.resize(n)
	noise.resize(n)
	for i in range(n):
		noise[i] = _hash(base_v[i])
	_groups = preload("res://scripts/meshkit.gd").shared_groups(base_v)
	mesh = ArrayMesh.new()
	rebuild()


func _subdivide(src_v: PackedVector3Array, src_c: PackedColorArray, max_edge: float) -> void:
	var limit2 := max_edge * max_edge
	var stack: Array = []
	for i in range(0, src_v.size(), 3):
		stack.append([src_v[i], src_v[i + 1], src_v[i + 2], src_c[i]])
	while not stack.is_empty():
		var t: Array = stack.pop_back()
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var ab := a.distance_squared_to(b)
		var bc := b.distance_squared_to(c)
		var ca := c.distance_squared_to(a)
		var longest := maxf(ab, maxf(bc, ca))
		if longest <= limit2:
			base_v.append(a)
			base_v.append(b)
			base_v.append(c)
			base_c.append(t[3])
			base_c.append(t[3])
			base_c.append(t[3])
			continue
		# Split the longest edge; keep the winding the same in both halves.
		if longest == ab:
			var m := _mid(a, b)
			stack.append([a, m, c, t[3]])
			stack.append([m, b, c, t[3]])
		elif longest == bc:
			var m := _mid(b, c)
			stack.append([a, b, m, t[3]])
			stack.append([a, m, c, t[3]])
		else:
			var m := _mid(c, a)
			stack.append([a, b, m, t[3]])
			stack.append([m, b, c, t[3]])


## The same midpoint whichever way round the edge is given.
static func _mid(p: Vector3, q: Vector3) -> Vector3:
	if p.x < q.x or (p.x == q.x and (p.y < q.y or (p.y == q.y and p.z < q.z))):
		return (p + q) * 0.5
	return (q + p) * 0.5


## Steady pseudo-random number for a position, so copies of a corner shared by
## several triangles all get the same value.
static func _hash(p: Vector3) -> float:
	var q := (p * 500.0).round()
	var h := sin(q.x * 12.9898 + q.y * 78.233 + q.z * 37.719) * 43758.5453
	return h - floorf(h)


## Push the skin around `point` in direction `push`.
func dent(point: Vector3, push: Vector3, depth: float, radius: float) -> void:
	var r2 := radius * radius
	for i in range(base_v.size()):
		var d2 := base_v[i].distance_squared_to(point)
		if d2 >= r2:
			continue
		var f := 1.0 - d2 / r2
		f *= f
		var nd := disp[i] + push * (depth * f * (0.55 + 0.9 * noise[i]))
		if nd.length() > MAX_PUSH:
			nd = nd.normalized() * MAX_PUSH
		disp[i] = nd
		scuff[i] = minf(scuff[i] + f * minf(depth * 4.0, 0.6), 1.0)
	_dirty = true


## Scratch the paint around `point`.
func scrape(point: Vector3, amount: float, radius: float) -> void:
	var r2 := radius * radius
	for i in range(base_v.size()):
		var d2 := base_v[i].distance_squared_to(point)
		if d2 >= r2:
			continue
		scuff[i] = minf(scuff[i] + amount * (1.0 - d2 / r2), 1.0)
	_dirty = true


## Scorch the paint around `point` (a fire burning there).
func burn(point: Vector3, radius: float, amount: float) -> void:
	var r2 := radius * radius
	for i in range(base_v.size()):
		var d2 := base_v[i].distance_squared_to(point)
		if d2 >= r2:
			continue
		charred[i] = minf(charred[i] + amount * (1.0 - d2 / r2) * (0.6 + 0.8 * noise[i]), 1.0)
	_dirty = true


func clear_damage() -> void:
	disp.fill(Vector3.ZERO)
	scuff.fill(0.0)
	charred.fill(0.0)
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


func is_dirty() -> bool:
	return _dirty


func rebuild() -> void:
	_dirty = false
	var n := base_v.size()
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	out_v.resize(n)
	out_n.resize(n)
	out_c.resize(n)
	var has_bend := bend_active and bend.is_valid()
	for i in range(n):
		var p := base_v[i] + disp[i]
		if has_bend:
			p += bend.call(base_v[i])
		out_v[i] = p
		var s := scuff[i]
		var col := base_c[i]
		if s > 0.01:
			col = col.lerp(BARE, clampf(s * 1.5, 0.0, 0.85))
			if s > 0.45:
				col = col.lerp(GOUGE, (s - 0.45) * 1.1 * noise[i])
		var ch := charred[i]
		if ch > 0.01:
			col = col.lerp(CHAR.lerp(Color(0.3, 0.29, 0.27), noise[i] * 0.4), clampf(ch, 0.0, 1.0))
		out_c[i] = col
	for i in range(0, n, 3):
		var nrm := (out_v[i + 2] - out_v[i]).cross(out_v[i + 1] - out_v[i])
		if nrm.length_squared() > 1.0e-14:
			nrm = nrm.normalized()
		else:
			nrm = Vector3.UP
		out_n[i] = nrm
		out_n[i + 1] = nrm
		out_n[i + 2] = nrm
	# Smooth across gentle curves, keep creases (and fresh dents) sharp.
	out_n = preload("res://scripts/meshkit.gd").smoothed(out_n, _groups, cos(deg_to_rad(crease_deg)))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	arrays[Mesh.ARRAY_COLOR] = out_c
	var am := mesh as ArrayMesh
	am.clear_surfaces()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, preload("res://scripts/meshkit.gd").material())
