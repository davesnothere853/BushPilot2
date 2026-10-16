extends RefCounted
## EZ-Tree in GDScript (DESIGN_NOTES 231, Dave's link eztree.dev): a port of
## Daniel Greenheck's procedural tree generator (MIT, github.com/dgreenheck/
## ez-tree, src/lib/tree.js). Same algorithm and the same random sequence, so
## its presets grow the same trees: a trunk of sections, perturbed by
## gnarliness, bent toward a growth force; child branches stratified along it
## at a set angle; leaves (double billboard quads) on the last level.
## Evergreens: no terminal branch, children shorter up the trunk (the cone).
##
## make(options, detail) -> {branches: ArrayMesh arrays, leaves: arrays}.
## detail: section_stride, segment_factor, leaf_stride, leaf_scale, billboard
## ("single"/"double") - the LOD levels, as in tree.js defaultLODLevels.
## Units: the preset's (EZ-Tree's trees are ~60-80 units tall); the caller
## scales to metres.

var o: Dictionary              # options (a preset, see PRESETS)
var _mw := 0
var _mz := 0
var _queue: Array = []
var skel_branches: Array = []  # [{sections: [[origin, euler, radius]], segs, base_r}]
var skel_leaves: Array = []    # [[origin, euler, size]]


# --- the random sequence (rng.js, 32-bit as JavaScript does it) --------------
static func _i32(x: int) -> int:
	x &= 0xffffffff
	return x - 0x100000000 if x >= 0x80000000 else x


func _seed(s: int) -> void:
	_mw = _i32(123456789 + s)
	_mz = _i32(987654321 - s)


func _rand(mx: float = 1.0, mn: float = 0.0) -> float:
	_mz = _i32(36969 * (_mz & 65535) + (_mz >> 16))
	_mw = _i32(18000 * (_mw & 65535) + (_mw >> 16))
	var r := ((_mz << 16) + (_mw & 65535)) & 0xffffffff
	return (mx - mn) * (float(r) / 4294967296.0) + mn


# --- three.js Euler 'XYZ' (matrix = Rx Ry Rz) ---------------------------------
static func _basis(e: Vector3) -> Basis:
	return Basis.from_euler(e, EULER_ORDER_ZYX)


static func _euler(b: Basis) -> Vector3:
	return b.get_euler(EULER_ORDER_ZYX)


static func _q(e: Vector3) -> Quaternion:
	return Quaternion(_basis(e))


static func _qe(q: Quaternion) -> Vector3:
	return _euler(Basis(q))


func _lv(key: String, level: int) -> float:
	var d: Dictionary = o["branch"][key]
	return float(d.get(str(level), d.get(level, 0.0)))


# --- growing ------------------------------------------------------------------
func generate(options: Dictionary) -> void:
	o = options
	skel_branches.clear()
	skel_leaves.clear()
	_seed(int(o["seed"]))
	_queue = [[Vector3.ZERO, Vector3.ZERO, _lv("length", 0), _lv("radius", 0), 0, int(_lv("sections", 0)), int(_lv("segments", 0))]]
	while not _queue.is_empty():
		_grow(_queue.pop_front())


func _grow(br: Array) -> void:
	var levels := int(o["branch"]["levels"])
	var evergreen := String(o["type"]) == "evergreen"
	var orient: Vector3 = br[1]
	var origin: Vector3 = br[0]
	var level: int = br[4]
	var nsec: int = br[5]
	var sec_len: float = float(br[2]) / float(nsec)
	var sections: Array = []
	var fdir: Vector3 = Vector3(o["branch"]["force"]["direction"]["x"], o["branch"]["force"]["direction"]["y"], o["branch"]["force"]["direction"]["z"]).normalized()
	var fstr := float(o["branch"]["force"]["strength"])
	for i in range(nsec + 1):
		var r: float = br[3]
		if i == nsec and level == levels:
			r = 0.001
		elif not evergreen:
			r *= 1.0 - _lv("taper", level) * (float(i) / nsec)
		else:
			r *= 1.0 - float(i) / nsec
		sections.append([origin, orient, r])
		origin = origin + _basis(orient) * Vector3(0, sec_len, 0)
		var g := maxf(1.0, 1.0 / sqrt(maxf(r, 1e-6))) * _lv("gnarliness", level)
		orient.x += _rand(g, -g)
		orient.z += _rand(g, -g)
		var qs := _q(orient) * Quaternion(Vector3.UP, _lv("twist", level))
		var up := qs * Vector3.UP
		var axis := up.cross(fdir)
		var s := axis.length()
		if s > 1e-6:
			axis /= s
			var full := atan2(s, up.dot(fdir))
			var step := fstr / maxf(r, 1e-6)
			qs = Quaternion(axis, clampf(step, -full, full)) * qs
		orient = _qe(qs)
	skel_branches.append({"sections": sections, "segs": int(br[6]), "base_r": float(br[3])})
	if not evergreen:
		var last: Array = sections[sections.size() - 1]
		if level < levels:
			_queue.append([last[0], last[1], _lv("length", level + 1), last[2], level + 1, nsec, int(br[6])])
		else:
			_leaf(last[0], last[1])
	if level == levels:
		_leaves(sections)
	elif level < levels:
		_children(int(_lv("children", level)), level + 1, sections)


func _shuffled(n: int) -> Array:
	var a: Array = range(n)
	for k in range(n - 1, 0, -1):
		var r := int(floor(_rand() * (k + 1)))
		var t = a[k]
		a[k] = a[r]
		a[r] = t
	return a


func _at(sections: Array, t: float) -> Array:
	var si := int(floor(t * (sections.size() - 1)))
	var a: Array = sections[si]
	var b: Array = sections[mini(si + 1, sections.size() - 1)]
	var alpha := (t - float(si) / (sections.size() - 1)) / (1.0 / (sections.size() - 1))
	var org: Vector3 = (a[0] as Vector3).lerp(b[0], alpha)
	var po := _qe(_q(b[1]).slerp(_q(a[1]), alpha))
	return [org, po, (1.0 - alpha) * float(a[2]) + alpha * float(b[2])]


func _children(count: int, level: int, sections: Array) -> void:
	var radial_off := _rand()
	var smin := _lv("start", level)
	var hstep := (1.0 - smin) / maxf(float(count), 1.0)
	var slots := _shuffled(count)
	var evergreen := String(o["type"]) == "evergreen"
	for i in range(count):
		var st := smin + (float(i) + _rand()) * hstep
		var at := _at(sections, st)
		var rad := _lv("radius", level) * float(at[2])
		var jit := _rand(0.5, -0.5)
		var ra := TAU * (radial_off + (float(slots[i]) + jit) / count)
		var q := _q(at[1]) * (Quaternion(Vector3.UP, ra) * Quaternion(Vector3.RIGHT, deg_to_rad(_lv("angle", level))))
		var ln := _lv("length", level) * ((1.0 - st) if evergreen else 1.0)
		_queue.append([at[0], _qe(q), ln, rad, level, int(_lv("sections", level)), int(_lv("segments", level))])


func _leaves(sections: Array) -> void:
	var L: Dictionary = o["leaves"]
	var radial_off := _rand()
	var count := int(L["count"])
	var smin := float(L["start"])
	var hstep := (1.0 - smin) / maxf(float(count), 1.0)
	var slots := _shuffled(count)
	for i in range(count):
		var st := smin + (float(i) + _rand()) * hstep
		var at := _at(sections, st)
		var jit := _rand(0.5, -0.5)
		var ra := TAU * (radial_off + (float(slots[i]) + jit) / count)
		var q := _q(at[1]) * (Quaternion(Vector3.UP, ra) * Quaternion(Vector3.RIGHT, deg_to_rad(float(L["angle"]))))
		_leaf(at[0], _qe(q))


func _leaf(origin: Vector3, orient: Vector3) -> void:
	var L: Dictionary = o["leaves"]
	var sv := float(L["sizeVariance"])
	skel_leaves.append([origin, orient, float(L["size"]) * (1.0 + _rand(sv, -sv))])


# --- meshing ------------------------------------------------------------------
## Arrays for ArrayMesh: [bark, leaves] (each Mesh.ARRAY_MAX long), scaled by s.
func mesh_arrays(detail: Dictionary = {}, s: float = 1.0) -> Array:
	var stride: int = maxi(1, int(detail.get("section_stride", 1)))
	var segf: float = detail.get("segment_factor", 1.0)
	var lstride: int = maxi(1, int(detail.get("leaf_stride", 1)))
	var lscale: float = detail.get("leaf_scale", 1.0)
	var billboard: String = detail.get("billboard", String(o["leaves"]["billboard"]))
	var bv := PackedVector3Array()
	var bn := PackedVector3Array()
	var buv := PackedVector2Array()
	var bi := PackedInt32Array()
	for b in skel_branches:
		var sections: Array = b["sections"]
		var segs := maxi(3, int(round(float(b["segs"]) * segf)))
		var wraps := maxf(1.0, round(float(b["base_r"]) * float(o["bark"]["textureScale"]["x"])))
		var sampled: Array = []
		for i in range(0, sections.size(), stride):
			sampled.append(sections[i])
		if (sections.size() - 1) % stride != 0:
			sampled.append(sections[sections.size() - 1])
		var off := bv.size()
		for k in range(sampled.size()):
			var sec: Array = sampled[k]
			var bs := _basis(sec[1])
			for j in range(segs + 1):
				var a := TAU * float(j % segs) / segs
				var d := Vector3(cos(a), 0, sin(a))
				bv.append(((sec[0] as Vector3) + bs * (d * float(sec[2]))) * s)
				bn.append((bs * d).normalized())
				buv.append(Vector2(float(j) / segs * wraps, 0.0 if k % 2 == 0 else 1.0))
		var N := segs + 1
		for i2 in range(sampled.size() - 1):
			for j2 in range(segs):
				var v1 := off + i2 * N + j2
				var v2 := v1 + 1
				var v3 := v1 + N
				var v4 := v2 + N
				bi.append_array([v1, v2, v3, v2, v4, v3])
	var lv := PackedVector3Array()
	var ln := PackedVector3Array()
	var luv := PackedVector2Array()
	var li := PackedInt32Array()
	for idx in range(0, skel_leaves.size(), lstride):
		var lf: Array = skel_leaves[idx]
		var sz: float = float(lf[2]) * lscale
		var bs2 := _basis(lf[1])
		var org: Vector3 = lf[0]
		var rots := [0.0, PI * 0.5] if billboard == "double" else [0.0]
		for rot in rots:
			var rb := bs2 * Basis(Vector3.UP, rot)
			var q := [Vector3(-sz * 0.5, sz, 0), Vector3(-sz * 0.5, 0, 0), Vector3(sz * 0.5, 0, 0), Vector3(sz * 0.5, sz, 0)]
			var nrm := (bs2 * Vector3(0, 0, 1)).normalized()
			var base := lv.size()
			for c in range(4):
				var p: Vector3 = org + rb * (q[c] as Vector3)
				lv.append(p * s)
				# rounded normals: the leaf's facing plus out from its origin
				ln.append((nrm + (p - org).normalized()).normalized())
			luv.append_array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)])
			li.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	var A := []
	A.resize(Mesh.ARRAY_MAX)
	A[Mesh.ARRAY_VERTEX] = bv
	A[Mesh.ARRAY_NORMAL] = bn
	A[Mesh.ARRAY_TEX_UV] = buv
	A[Mesh.ARRAY_INDEX] = bi
	var B := []
	B.resize(Mesh.ARRAY_MAX)
	B[Mesh.ARRAY_VERTEX] = lv
	B[Mesh.ARRAY_NORMAL] = ln
	B[Mesh.ARRAY_TEX_UV] = luv
	B[Mesh.ARRAY_INDEX] = li
	return [A, B]


## The LOD levels of tree.js (near, middle, far).
const LODS := [
	{},
	{"section_stride": 3, "segment_factor": 0.75, "leaf_stride": 2, "leaf_scale": 1.25},
	{"section_stride": 6, "segment_factor": 0.4, "leaf_stride": 2, "leaf_scale": 1.3, "billboard": "single"},
]
