extends Node3D
## The pilot: a human body built from code on a skeleton, so elbows, knees and
## hips bend smoothly. Dressed for the bush in 1988: canvas work jacket, duck
## work pants, leather boots and gloves, and a ball cap. Faces -Z, feet at the
## origin, 1.80 m tall.
##
## Animation is worked out each frame from the gait (no animation files):
## idle, walk, run, in the air, and sitting at the controls.

enum { IDLE, WALK, RUN, AIR, SIT, DRIVE }

const SKIN := Color(0.86, 0.68, 0.56)
const STUBBLE := Color(0.76, 0.60, 0.50)
const HAIR := Color(0.34, 0.25, 0.18)
const LIPS := Color(0.68, 0.48, 0.42)
const EYE_DARK := Color(0.10, 0.09, 0.08)
## Colours are sRGB. Alpha below 1 makes a surface glossy (leather, glass, metal).
const JACKET := Color(0.48, 0.30, 0.19, 0.45)        # worn brown flight-jacket leather
const JACKET_SEAM := Color(0.34, 0.21, 0.13, 0.55)
const KNIT := Color(0.28, 0.20, 0.15)                # ribbed cuffs and waistband
const ZIP := Color(0.52, 0.46, 0.34, 0.15)
const COLLAR := Color(0.80, 0.72, 0.58)              # sheepskin
const SCARF := Color(0.83, 0.79, 0.69)               # cream wool
const LENS := Color(0.16, 0.22, 0.20, 0.0)
const FRAME := Color(0.74, 0.60, 0.30, 0.1)
const PANTS := Color(0.52, 0.48, 0.36)
const BOOT := Color(0.32, 0.22, 0.15, 0.7)
const SOLE := Color(0.10, 0.09, 0.08)
const GLOVE := Color(0.46, 0.33, 0.21, 0.8)
const CAP := Color(0.30, 0.36, 0.30)
const CAP_PATCH := Color(0.78, 0.74, 0.64)

## [name, parent, joint position in model space]
const BONES := [
	["hips", "", Vector3(0, 0.98, 0)],
	["spine", "hips", Vector3(0, 1.10, 0)],
	["chest", "spine", Vector3(0, 1.28, 0)],
	["neck", "chest", Vector3(0, 1.49, 0)],
	["head", "neck", Vector3(0, 1.585, 0)],
	["upperarm_r", "chest", Vector3(0.185, 1.44, 0)],
	["forearm_r", "upperarm_r", Vector3(0.235, 1.165, 0.0)],
	["hand_r", "forearm_r", Vector3(0.27, 0.925, -0.01)],
	["upperarm_l", "chest", Vector3(-0.185, 1.44, 0)],
	["forearm_l", "upperarm_l", Vector3(-0.235, 1.165, 0.0)],
	["hand_l", "forearm_l", Vector3(-0.27, 0.925, -0.01)],
	["thigh_r", "hips", Vector3(0.10, 0.95, 0)],
	["shin_r", "thigh_r", Vector3(0.11, 0.52, 0)],
	["foot_r", "shin_r", Vector3(0.115, 0.09, 0)],
	["thigh_l", "hips", Vector3(-0.10, 0.95, 0)],
	["shin_l", "thigh_l", Vector3(-0.11, 0.52, 0)],
	["foot_l", "shin_l", Vector3(-0.115, 0.09, 0)],
]

var skeleton: Skeleton3D
var body: MeshInstance3D
var head_part: MeshInstance3D       # head, face and cap: hidden in first person
var _bone := {}                     # name -> index
var _joint := {}                    # name -> model-space joint position
var mode := IDLE
var phase := 0.0                    # gait cycle, radians
var _blend := {}                    # name -> current Vector3 euler, eased toward the target
var _hip_off := Vector3.ZERO


func _ready() -> void:
	if skeleton == null:
		build()


func build() -> void:
	if skeleton != null:
		return          # already built (adding to the tree builds it too)
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	for b in BONES:
		var bname: String = b[0]
		var parent: String = b[1]
		var p: Vector3 = b[2]
		var idx := skeleton.add_bone(bname)
		_bone[bname] = idx
		_joint[bname] = p
		var local := p
		if parent != "":
			skeleton.set_bone_parent(idx, int(_bone[parent]))
			local = p - (_joint[parent] as Vector3)
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, local))
		skeleton.set_bone_pose_position(idx, local)
		_blend[bname] = Vector3.ZERO
	var skin := skeleton.create_skin_from_rest_transforms()
	var mat := ShaderMaterial.new()
	mat.shader = _shader()
	body = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _build_body()
	body.material_override = mat
	skeleton.add_child(body)
	body.skin = skin
	body.skeleton = NodePath("..")
	head_part = MeshInstance3D.new()
	head_part.name = "Head"
	head_part.mesh = _build_head()
	head_part.material_override = mat
	skeleton.add_child(head_part)
	head_part.skin = skin
	head_part.skeleton = NodePath("..")


static var _sh: Shader


## Vertex colours are sRGB; alpha below 1 marks glossy parts.
static func _shader() -> Shader:
	if _sh == null:
		_sh = Shader.new()
		_sh.code = """shader_type spatial;
varying vec4 col;
void vertex() { col = COLOR; }
void fragment() {
	ALBEDO = pow(clamp(col.rgb, vec3(0.0), vec3(1.0)), vec3(2.2));
	float gloss = clamp(1.0 - col.a, 0.0, 1.0);
	ROUGHNESS = mix(0.9, 0.45, gloss);
	SPECULAR = mix(0.3, 0.5, gloss);
	// A bad normal (a squashed bone) would light as NaN and bloom into a white blob.
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) {
		NORMAL = vec3(0.0, 0.0, 1.0);
	}
}
"""
	return _sh


# ------------------------------------------------------------------------------
#  Mesh building
# ------------------------------------------------------------------------------
class Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var bi := PackedInt32Array()
	var bw := PackedFloat32Array()
	var idx := PackedInt32Array()

	func vert(p: Vector3, col: Color, w: Array) -> int:
		v.append(p)
		n.append(Vector3.ZERO)
		c.append(col)
		var b0: int = w[0][0]
		var w0: float = w[0][1]
		var b1: int = w[1][0] if w.size() > 1 else 0
		var w1: float = w[1][1] if w.size() > 1 else 0.0
		bi.append_array(PackedInt32Array([b0, b1, 0, 0]))
		bw.append_array(PackedFloat32Array([w0, w1, 0.0, 0.0]))
		return v.size() - 1

	## A triangle facing away from `inside`.
	func tri(a: int, b: int, cc: int, inside: Vector3) -> void:
		var fn := (v[cc] - v[a]).cross(v[b] - v[a])
		var mid := (v[a] + v[b] + v[cc]) / 3.0
		if fn.dot(mid - inside) < 0.0:
			idx.append_array(PackedInt32Array([a, cc, b]))
		else:
			idx.append_array(PackedInt32Array([a, b, cc]))

	func commit() -> ArrayMesh:
		# Smooth normals from the faces around each corner.
		for i in range(0, idx.size(), 3):
			var a := idx[i]
			var b := idx[i + 1]
			var cc := idx[i + 2]
			var fn := (v[b] - v[a]).cross(v[cc] - v[a])
			n[a] += fn
			n[b] += fn
			n[cc] += fn
		for i in range(n.size()):
			n[i] = n[i].normalized() if n[i].length_squared() > 1.0e-12 else Vector3.UP
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_BONES] = bi
		arrays[Mesh.ARRAY_WEIGHTS] = bw
		arrays[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


## Weights for one bone, or a blend of two.
func _w(a: String, b: String = "", t: float = 0.0) -> Array:
	if b == "" or t <= 0.0:
		return [[int(_bone[a]), 1.0]]
	if t >= 1.0:
		return [[int(_bone[b]), 1.0]]
	return [[int(_bone[a]), 1.0 - t], [int(_bone[b]), t]]


## A tube through a list of rings. Each ring: {c: centre, x: side axis (scaled
## by its half width), z: front axis (scaled by its half depth), col: Color or
## Callable(angle, ring index) -> Color, w: weights, sq: squareness 0..1}.
## Ends are closed with a cap if asked.
func _tube(B: Builder, rings: Array, sides: int, cap0: bool, cap1: bool) -> void:
	var first := B.v.size()
	for r in rings:
		var cc: Vector3 = r["c"]
		var ax: Vector3 = r["x"]
		var az: Vector3 = r["z"]
		var sq: float = r.get("sq", 0.0)
		for k in range(sides):
			var a := TAU * float(k) / float(sides)
			var ca := cos(a)
			var sa := sin(a)
			if sq > 0.0:
				var e := 1.0 / (1.0 + sq * 1.5)
				ca = signf(ca) * pow(absf(ca), e)
				sa = signf(sa) * pow(absf(sa), e)
			var col: Color
			if r["col"] is Callable:
				col = (r["col"] as Callable).call(a, cc + ax * ca + az * sa)
			else:
				col = r["col"]
			B.vert(cc + ax * ca + az * sa, col, r["w"])
	for ri in range(rings.size() - 1):
		var mid: Vector3 = ((rings[ri]["c"] as Vector3) + (rings[ri + 1]["c"] as Vector3)) * 0.5
		for k in range(sides):
			var k2 := (k + 1) % sides
			var a := first + ri * sides + k
			var b := first + ri * sides + k2
			var c2 := first + (ri + 1) * sides + k
			var d := first + (ri + 1) * sides + k2
			B.tri(a, b, d, mid)
			B.tri(a, d, c2, mid)
	for end in [0, 1]:
		if (end == 0 and not cap0) or (end == 1 and not cap1):
			continue
		var ri := 0 if end == 0 else rings.size() - 1
		var r: Dictionary = rings[ri]
		var other: Vector3 = rings[1 if end == 0 else rings.size() - 2]["c"]
		var cc: Vector3 = r["c"]
		var col0: Color = B.c[first + ri * sides]
		var centre := B.vert(cc + (cc - other).normalized() * 0.004, col0, r["w"])
		var inside := cc - (cc - other).normalized() * 0.2
		for k in range(sides):
			B.tri(first + ri * sides + k, first + ri * sides + (k + 1) % sides, centre, inside)


## A limb tube along `pts`, rings perpendicular to the path. `rad` holds
## Vector2(half width across, half depth front to back) per point.
func _limb(B: Builder, pts: Array, rad: Array, cols: Array, ws: Array, front: Vector3, sides: int, cap0: bool, cap1: bool, sq: float = 0.0) -> void:
	var rings: Array = []
	for i in range(pts.size()):
		var p: Vector3 = pts[i]
		var d: Vector3
		if i == 0:
			d = (pts[1] as Vector3) - p
		elif i == pts.size() - 1:
			d = p - (pts[i - 1] as Vector3)
		else:
			d = (pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)
		d = d.normalized()
		var side := d.cross(front).normalized()
		var fr := side.cross(d).normalized()
		if fr.dot(front) < 0.0:
			fr = -fr
		var r2: Vector2 = rad[i]
		rings.append({"c": p, "x": side * r2.x, "z": fr * r2.y, "col": cols[i], "w": ws[i], "sq": sq})
	_tube(B, rings, sides, cap0, cap1)


## A lumpy ellipsoid stuck to one bone (ears, nose, eyes).
func _blob(B: Builder, c: Vector3, r: Vector3, col: Color, w: Array, rings: int = 5, sides: int = 8) -> void:
	var rr: Array = []
	for i in range(rings + 1):
		var t := float(i) / float(rings)
		var a := PI * (t - 0.5)
		var s := maxf(cos(a), 0.06)
		rr.append({"c": c + Vector3(0, sin(a) * r.y, 0), "x": Vector3(r.x * s, 0, 0), "z": Vector3(0, 0, r.z * s), "col": col, "w": w})
	_tube(B, rr, sides, true, true)


func _build_body() -> ArrayMesh:
	var B := Builder.new()
	var fwd := Vector3(0, 0, -1)
	# --- Torso in the work jacket: hips up to the collar ----------------------
	var jacket_col := func(a: float, p: Vector3) -> Color:
		var front := sin(a)    # the ring's front axis points along -Z, the way he faces
		if absf(cos(a)) < 0.035 and front > 0.0:
			return ZIP
		if front > 0.6 and absf(p.x) > 0.06 and absf(p.x) < 0.14 and absf(p.y - 1.05) < 0.012:
			return JACKET_SEAM     # pocket flaps
		return JACKET
	var torso := [
		# y, half width, half depth, weights
		[0.84, 0.165, 0.115, _w("hips")],
		[0.90, 0.175, 0.12, _w("hips")],
		[0.98, 0.172, 0.118, _w("hips")],
		[1.06, 0.166, 0.112, _w("hips", "spine", 0.5)],
		[1.16, 0.168, 0.114, _w("spine")],
		[1.24, 0.176, 0.12, _w("spine", "chest", 0.5)],
		[1.32, 0.186, 0.124, _w("chest")],
		[1.40, 0.19, 0.118, _w("chest")],
		[1.45, 0.175, 0.105, _w("chest")],
		[1.49, 0.125, 0.088, _w("chest")],
		[1.525, 0.072, 0.07, _w("chest", "neck", 0.5)],
	]
	var rings: Array = []
	for t in torso:
		var col: Variant = jacket_col
		rings.append({"c": Vector3(0, t[0], 0.008), "x": Vector3(t[1], 0, 0), "z": Vector3(0, 0, -float(t[2])), "col": col, "w": t[3], "sq": 0.35})
	_tube(B, rings, 18, true, false)
	# Jacket hem: a slightly flared band at the bottom.
	_tube(B, [
		{"c": Vector3(0, 0.83, 0.008), "x": Vector3(0.17, 0, 0), "z": Vector3(0, 0, -0.12), "col": KNIT, "w": _w("hips"), "sq": 0.35},
		{"c": Vector3(0, 0.89, 0.008), "x": Vector3(0.174, 0, 0), "z": Vector3(0, 0, -0.122), "col": KNIT, "w": _w("hips"), "sq": 0.35}], 18, false, false)
	# Sheepskin collar, turned down over the shoulders.
	_tube(B, [
		{"c": Vector3(0, 1.41, 0.008), "x": Vector3(0.205, 0, 0), "z": Vector3(0, 0, -0.132), "col": COLLAR, "w": _w("chest"), "sq": 0.3},
		{"c": Vector3(0, 1.45, 0.008), "x": Vector3(0.198, 0, 0), "z": Vector3(0, 0, -0.13), "col": COLLAR, "w": _w("chest"), "sq": 0.3},
		{"c": Vector3(0, 1.49, 0.01), "x": Vector3(0.15, 0, 0), "z": Vector3(0, 0, -0.108), "col": COLLAR, "w": _w("chest"), "sq": 0.25},
		{"c": Vector3(0, 1.52, 0.012), "x": Vector3(0.1, 0, 0), "z": Vector3(0, 0, -0.088), "col": COLLAR, "w": _w("chest", "neck", 0.4), "sq": 0.1},
		{"c": Vector3(0, 1.54, 0.014), "x": Vector3(0.082, 0, 0), "z": Vector3(0, 0, -0.078), "col": COLLAR, "w": _w("chest", "neck", 0.6), "sq": 0.0}], 18, false, false)
	# Wool scarf: wrapped once round the neck, the ends hanging down the front.
	_tube(B, [
		{"c": Vector3(0, 1.53, 0.0), "x": Vector3(0.072, 0, 0), "z": Vector3(0, 0, -0.07), "col": SCARF, "w": _w("neck"), "sq": 0.0},
		{"c": Vector3(0, 1.56, 0.0), "x": Vector3(0.07, 0, 0), "z": Vector3(0, 0, -0.068), "col": SCARF, "w": _w("neck"), "sq": 0.0},
		{"c": Vector3(0, 1.585, 0.002), "x": Vector3(0.064, 0, 0), "z": Vector3(0, 0, -0.064), "col": SCARF, "w": _w("neck", "head", 0.3), "sq": 0.0}], 14, true, true)
	for tail in [[-0.035, 1.0], [0.03, 0.82]]:
		var tx: float = tail[0]
		var ln: float = tail[1]
		_limb(B, [Vector3(tx, 1.54, -0.07), Vector3(tx * 1.2, 1.47, -0.12), Vector3(tx * 1.3, 1.40 - 0.02 * ln, -0.13), Vector3(tx * 1.3, 1.30 + 0.08 * (1.0 - ln), -0.128)],
			[Vector2(0.034, 0.008), Vector2(0.036, 0.009), Vector2(0.036, 0.009), Vector2(0.036, 0.009)], [SCARF, SCARF, SCARF, SCARF],
			[_w("neck"), _w("chest", "neck", 0.3), _w("chest"), _w("chest")], Vector3(0, 0, -1), 8, true, true)
	# --- Neck --------------------------------------------------------------------
	_limb(B, [Vector3(0, 1.47, 0.01), Vector3(0, 1.54, 0.0), Vector3(0, 1.60, -0.008)],
		[Vector2(0.056, 0.054), Vector2(0.053, 0.052), Vector2(0.055, 0.056)],
		[SKIN, SKIN, SKIN], [_w("chest", "neck", 0.5), _w("neck"), _w("neck", "head", 0.5)], fwd, 12, false, false)
	# --- Arms in jacket sleeves, gloved hands -------------------------------------
	for s in [1.0, -1.0]:
		var side := "_r" if s > 0.0 else "_l"
		var sh: Vector3 = _joint["upperarm" + side]
		var el: Vector3 = _joint["forearm" + side]
		var wr: Vector3 = _joint["hand" + side]
		var shoulder_in := sh + Vector3(-0.065 * s, -0.005, 0)
		var up_mid := sh.lerp(el, 0.5)
		var fo_mid := el.lerp(wr, 0.5)
		_limb(B, [shoulder_in, sh + Vector3(0.0, -0.02, 0), up_mid, el + Vector3(0, 0.03, 0), el, el + Vector3(0, -0.03, 0), fo_mid, wr + Vector3(0, 0.025, 0), wr],
			[Vector2(0.07, 0.072), Vector2(0.066, 0.066), Vector2(0.058, 0.056), Vector2(0.052, 0.052), Vector2(0.05, 0.05), Vector2(0.05, 0.05), Vector2(0.047, 0.046), Vector2(0.046, 0.045), Vector2(0.043, 0.042)],
			[JACKET, JACKET, JACKET, JACKET, JACKET, JACKET, JACKET, KNIT, KNIT],
			[_w("chest", "upperarm" + side, 0.6), _w("upperarm" + side), _w("upperarm" + side), _w("upperarm" + side, "forearm" + side, 0.25),
			 _w("upperarm" + side, "forearm" + side, 0.5), _w("upperarm" + side, "forearm" + side, 0.8), _w("forearm" + side), _w("forearm" + side), _w("forearm" + side, "hand" + side, 0.3)],
			fwd, 12, true, false)
		# Glove: a flattened mitt with the fingers curled a little, and a thumb.
		var hd := (wr - el).normalized()
		var palm_side := Vector3(0, 0, -1)
		var h0 := wr + hd * 0.005
		_limb(B, [h0, h0 + hd * 0.05, h0 + hd * 0.10 + palm_side * 0.008, h0 + hd * 0.15 + palm_side * 0.025, h0 + hd * 0.175 + palm_side * 0.04],
			[Vector2(0.04, 0.026), Vector2(0.048, 0.022), Vector2(0.046, 0.02), Vector2(0.042, 0.018), Vector2(0.03, 0.012)],
			[GLOVE, GLOVE, GLOVE, GLOVE, GLOVE], [_w("hand" + side), _w("hand" + side), _w("hand" + side), _w("hand" + side), _w("hand" + side)],
			Vector3(s, 0, 0), 10, true, true)
		var tb := h0 + hd * 0.035 + Vector3(0, 0, -0.035)
		_limb(B, [tb, tb + Vector3(-0.012 * s, -0.035, -0.02), tb + Vector3(-0.02 * s, -0.065, -0.025)],
			[Vector2(0.014, 0.014), Vector2(0.012, 0.012), Vector2(0.009, 0.009)], [GLOVE, GLOVE, GLOVE],
			[_w("hand" + side), _w("hand" + side), _w("hand" + side)], Vector3(s, 0, 0), 8, false, true)
	# --- Legs in work pants -------------------------------------------------------
	for s in [1.0, -1.0]:
		var side := "_r" if s > 0.0 else "_l"
		var hp: Vector3 = _joint["thigh" + side]
		var kn: Vector3 = _joint["shin" + side]
		var an: Vector3 = _joint["foot" + side]
		var top := hp + Vector3(-0.02 * s, 0.07, 0)
		_limb(B, [top, hp, hp.lerp(kn, 0.45), kn + Vector3(0, 0.04, 0), kn, kn + Vector3(0, -0.05, 0), kn.lerp(an, 0.5), an + Vector3(0, 0.13, 0), an + Vector3(0, 0.10, 0)],
			[Vector2(0.088, 0.095), Vector2(0.09, 0.095), Vector2(0.078, 0.08), Vector2(0.066, 0.068), Vector2(0.064, 0.066), Vector2(0.062, 0.062), Vector2(0.06, 0.06), Vector2(0.066, 0.066), Vector2(0.068, 0.068)],
			[PANTS, PANTS, PANTS, PANTS, PANTS, PANTS, PANTS, PANTS, PANTS],
			[_w("hips", "thigh" + side, 0.5), _w("thigh" + side), _w("thigh" + side), _w("thigh" + side, "shin" + side, 0.2), _w("thigh" + side, "shin" + side, 0.5),
			 _w("thigh" + side, "shin" + side, 0.85), _w("shin" + side), _w("shin" + side), _w("shin" + side)],
			fwd, 12, false, true)
		# Boot: shaft, then the foot running forward to a rounded toe.
		# One piece from under the pant cuff right down into the foot.
		_limb(B, [an + Vector3(0, 0.17, 0), an + Vector3(0, 0.05, 0.004), Vector3(an.x, 0.07, 0.01), Vector3(an.x, 0.045, 0.012)],
			[Vector2(0.058, 0.06), Vector2(0.062, 0.066), Vector2(0.06, 0.068), Vector2(0.056, 0.064)], [BOOT, BOOT, BOOT, BOOT],
			[_w("shin" + side), _w("shin" + side, "foot" + side, 0.6), _w("foot" + side), _w("foot" + side)], fwd, 12, true, false)
		var fb := Vector3(an.x, 0.0, 0.0)
		var foot_pts := [fb + Vector3(0, 0.062, 0.072), fb + Vector3(0, 0.066, 0.04), fb + Vector3(0, 0.062, -0.02), fb + Vector3(0, 0.052, -0.09), fb + Vector3(0, 0.046, -0.15), fb + Vector3(0, 0.042, -0.185)]
		var foot_rad := [Vector2(0.046, 0.058), Vector2(0.054, 0.066), Vector2(0.055, 0.062), Vector2(0.052, 0.052), Vector2(0.047, 0.044), Vector2(0.03, 0.03)]
		var sole_col := func(a: float, p: Vector3) -> Color:
			return SOLE if p.y < 0.012 else BOOT
		_limb(B, foot_pts, foot_rad, [sole_col, sole_col, sole_col, sole_col, sole_col, sole_col],
			[_w("foot" + side), _w("foot" + side), _w("foot" + side), _w("foot" + side), _w("foot" + side), _w("foot" + side)],
			Vector3(0, 1, 0), 12, true, true, 0.6)
	return B.commit()


## One aviator lens: a teardrop, wider and deeper toward the outer bottom,
## with a slight curve, glossy both sides.
func _lens(B: Builder, c: Vector3, sx: float, w: Array) -> void:
	var n := 14
	var ring: Array[int] = []
	var back: Array[int] = []
	for k in range(n):
		var a := TAU * float(k) / float(n)
		var x := cos(a) * 0.027
		var y := sin(a) * 0.019
		if sin(a) < 0.0:
			y *= 1.0 + 0.45 * maxf(0.0, cos(a) * sx * 1.0 + 0.2)   # sag at the outer bottom
		if sin(a) > 0.0 and cos(a) * sx < 0.0:
			y *= 0.85                                            # flatter top toward the nose
		var p := c + Vector3(x, y, 0.004 * (x * x + y * y) / 0.0007)
		ring.append(B.vert(p, LENS, w))
		back.append(B.vert(p + Vector3(0, 0, 0.002), LENS, w))
	var fc := B.vert(c - Vector3(0, 0, 0.001), LENS, w)
	var bc := B.vert(c + Vector3(0, 0, 0.003), LENS, w)
	for k in range(n):
		var k2 := (k + 1) % n
		B.tri(ring[k], ring[k2], fc, c + Vector3(0, 0, 0.05))
		B.tri(back[k], back[k2], bc, c - Vector3(0, 0, 0.05))


func _build_head() -> ArrayMesh:
	var B := Builder.new()
	var hw := _w("head")
	var cz := -0.005
	# Skin colour by place: stubble on the jaw, hair at the back and sides.
	var face := func(a: float, p: Vector3) -> Color:
		var front := (cz - p.z) / 0.11        # 1 at the face, -1 at the back
		if p.y > 1.69 and front < 0.2:
			return HAIR
		if p.y > 1.665 and absf(p.x) > 0.072 and front < 0.55:
			return HAIR
		if p.y < 1.655 and front > -0.2:
			return STUBBLE
		return SKIN
	var prof := [
		# y, half width, half depth
		[1.575, 0.04, 0.05],
		[1.59, 0.06, 0.075],
		[1.61, 0.068, 0.088],
		[1.635, 0.073, 0.094],
		[1.66, 0.077, 0.098],
		[1.69, 0.08, 0.104],
		[1.72, 0.082, 0.105],
		[1.75, 0.079, 0.1],
		[1.775, 0.068, 0.088],
		[1.795, 0.046, 0.062],
		[1.805, 0.018, 0.026],
	]
	var rings: Array = []
	for t in prof:
		rings.append({"c": Vector3(0, t[0], cz), "x": Vector3(t[1], 0, 0), "z": Vector3(0, 0, -float(t[2])), "col": face, "w": hw, "sq": 0.12})
	_tube(B, rings, 18, true, true)
	# Nose, brow, eyes, mouth, ears.
	_limb(B, [Vector3(0, 1.708, cz - 0.096), Vector3(0, 1.69, cz - 0.112), Vector3(0, 1.668, cz - 0.128), Vector3(0, 1.66, cz - 0.112)],
		[Vector2(0.009, 0.01), Vector2(0.012, 0.013), Vector2(0.016, 0.014), Vector2(0.018, 0.01)], [SKIN, SKIN, SKIN, SKIN], [hw, hw, hw, hw], Vector3(0, 1, 0), 8, true, true)
	for s in [1.0, -1.0]:
		_blob(B, Vector3(0.033 * s, 1.697, cz - 0.094), Vector3(0.012, 0.007, 0.006), EYE_DARK, hw, 4, 8)
		_blob(B, Vector3(0.035 * s, 1.713, cz - 0.098), Vector3(0.02, 0.005, 0.008), HAIR, hw, 3, 8)
		_blob(B, Vector3(0.083 * s, 1.68, cz + 0.005), Vector3(0.012, 0.028, 0.02), SKIN, hw, 4, 8)
	_blob(B, Vector3(0, 1.64, cz - 0.093), Vector3(0.022, 0.004, 0.006), LIPS, hw, 3, 8)
	# Ball cap: crown, front patch, and the brim.
	var cap_col := func(a: float, p: Vector3) -> Color:
		return CAP_PATCH if (p.z < cz - 0.06 and absf(p.x) < 0.045 and p.y > 1.75) else CAP
	var cap := [[1.725, 0.088, 0.113], [1.76, 0.088, 0.11], [1.79, 0.078, 0.096], [1.81, 0.058, 0.07], [1.823, 0.03, 0.036], [1.828, 0.004, 0.004]]
	var crings: Array = []
	for t in cap:
		crings.append({"c": Vector3(0, t[0], cz + 0.004), "x": Vector3(t[1], 0, 0), "z": Vector3(0, 0, -float(t[2])), "col": cap_col, "w": hw, "sq": 0.1})
	_tube(B, crings, 18, false, true)
	# Brim: a curved slab sticking out the front.
	var brim: Array = []
	for i in range(5):
		var t := float(i) / 4.0
		var y := 1.73 - 0.012 * t * t
		var zf := cz - 0.105 - 0.075 * t
		var half := lerpf(0.082, 0.06, t * t)
		brim.append({"c": Vector3(0, y, zf), "x": Vector3(half, 0, 0), "z": Vector3(0, 0.006, 0), "col": CAP, "w": hw, "sq": 0.6})
	_tube(B, brim, 12, true, true)
	# Aviator sunglasses: teardrop lenses, a double bridge and arms back to the ears.
	for sx in [1.0, -1.0]:
		var lc := Vector3(0.034 * sx, 1.693, cz - 0.113)
		_lens(B, lc, sx, hw)
		_limb(B, [lc + Vector3(0.026 * sx, 0.012, 0.0), Vector3(0.083 * sx, 1.70, cz - 0.07), Vector3(0.086 * sx, 1.695, cz + 0.02)],
			[Vector2(0.0025, 0.0025), Vector2(0.0025, 0.0025), Vector2(0.0025, 0.0025)], [FRAME, FRAME, FRAME], [hw, hw, hw], Vector3(0, 1, 0), 5, true, true)
		_limb(B, [lc + Vector3(-0.022 * sx, 0.018, 0.0), lc + Vector3(0.0, 0.021, 0.0), lc + Vector3(0.024 * sx, 0.014, 0.0)],
			[Vector2(0.002, 0.002), Vector2(0.002, 0.002), Vector2(0.002, 0.002)], [FRAME, FRAME, FRAME], [hw, hw, hw], Vector3(0, 0, -1), 5, true, true)
	_limb(B, [Vector3(-0.012, 1.703, cz - 0.116), Vector3(0, 1.706, cz - 0.118), Vector3(0.012, 1.703, cz - 0.116)],
		[Vector2(0.002, 0.002), Vector2(0.002, 0.002), Vector2(0.002, 0.002)], [FRAME, FRAME, FRAME], [hw, hw, hw], Vector3(0, 0, -1), 5, true, true)
	# Sit the whole head a little lower and forward on the neck.
	for i in range(B.v.size()):
		B.v[i] += Vector3(0, -0.014, -0.008)
	return B.commit()


# ------------------------------------------------------------------------------
#  Animation
# ------------------------------------------------------------------------------
## Pose for this frame. `speed` is ground speed in m/s; `t` a running clock.
func animate(delta: float, new_mode: int, speed: float, t: float) -> void:
	mode = new_mode
	var target := {}
	for b in BONES:
		target[b[0]] = Vector3.ZERO
	var hip := Vector3.ZERO
	match mode:
		IDLE:
			var br := sin(t * 1.7)
			target["chest"] = Vector3(0.015 * br, 0, 0)
			target["upperarm_r"] = Vector3(0.02, 0, -0.07)
			target["upperarm_l"] = Vector3(0.02, 0, 0.07)
			target["forearm_r"] = Vector3(0.12, 0, 0)
			target["forearm_l"] = Vector3(0.12, 0, 0)
			target["head"] = Vector3(0.02 * sin(t * 0.4), 0.15 * sin(t * 0.23), 0)
			target["hips"] = Vector3(0, 0, 0.015 * sin(t * 0.5))
			hip = Vector3(0, -0.005 + 0.003 * br, 0)
		WALK, RUN:
			var run := mode == RUN
			phase = fmod(phase + delta * speed * (2.3 if run else 3.6), TAU)
			var p := phase
			var s := sin(p)
			var thigh_amp := 0.72 if run else 0.42
			var lean := 0.06 if run else 0.0
			target["thigh_r"] = Vector3(thigh_amp * s + lean * 2.0, 0, 0)
			target["thigh_l"] = Vector3(-thigh_amp * s + lean * 2.0, 0, 0)
			var knee_r := maxf(0.0, cos(p))
			var knee_l := maxf(0.0, -cos(p))
			var kmax := 1.5 if run else 0.7
			target["shin_r"] = Vector3(-(0.08 + kmax * knee_r * knee_r), 0, 0)
			target["shin_l"] = Vector3(-(0.08 + kmax * knee_l * knee_l), 0, 0)
			target["foot_r"] = Vector3(-0.6 * ((target["thigh_r"] as Vector3).x + (target["shin_r"] as Vector3).x), 0, 0)
			target["foot_l"] = Vector3(-0.6 * ((target["thigh_l"] as Vector3).x + (target["shin_l"] as Vector3).x), 0, 0)
			var arm_amp := 0.6 if run else 0.32
			target["upperarm_r"] = Vector3(-arm_amp * s, 0, -0.03)
			target["upperarm_l"] = Vector3(arm_amp * s, 0, 0.03)
			var fb := 1.25 if run else 0.22
			target["forearm_r"] = Vector3(fb + 0.18 * maxf(0.0, -s), 0, 0)
			target["forearm_l"] = Vector3(fb + 0.18 * maxf(0.0, s), 0, 0)
			target["hips"] = Vector3(lean, 0.09 * s, 0)
			target["spine"] = Vector3(lean * 1.5, 0, 0)
			target["chest"] = Vector3(0.0, -0.13 * s, 0)
			target["head"] = Vector3(-lean * 1.5, 0.04 * s, 0)
			hip = Vector3(0, (-0.05 if run else -0.015) + (0.045 if run else 0.022) * cos(2.0 * p), 0)
		AIR:
			target["thigh_r"] = Vector3(0.55, 0, 0)
			target["thigh_l"] = Vector3(0.15, 0, 0)
			target["shin_r"] = Vector3(-0.8, 0, 0)
			target["shin_l"] = Vector3(-0.5, 0, 0)
			target["upperarm_r"] = Vector3(-0.2, 0, 0.45)
			target["upperarm_l"] = Vector3(-0.2, 0, -0.45)
			target["forearm_r"] = Vector3(0.5, 0, 0)
			target["forearm_l"] = Vector3(0.5, 0, 0)
		SIT:
			target["thigh_r"] = Vector3(1.45, 0, 0.04)
			target["thigh_l"] = Vector3(1.45, 0, -0.04)
			target["shin_r"] = Vector3(-1.25, 0, 0)
			target["shin_l"] = Vector3(-1.3, 0, 0)
			target["foot_r"] = Vector3(-0.15, 0, 0)
			target["foot_l"] = Vector3(-0.1, 0, 0)
			target["spine"] = Vector3(-0.08, 0, 0)
			target["upperarm_r"] = Vector3(0.55, 0, 0.12)
			target["upperarm_l"] = Vector3(0.75, 0, -0.1)
			target["forearm_r"] = Vector3(0.75, 0, 0)
			target["forearm_l"] = Vector3(0.7, 0, 0)
			target["head"] = Vector3(0.03 * sin(t * 0.3), 0.12 * sin(t * 0.17), 0)
		DRIVE:
			# Seated at machine controls: reaching forward, left hand on the
			# wheel, right hand dropped to the hydraulic levers.
			target["thigh_r"] = Vector3(1.45, 0, 0.04)
			target["thigh_l"] = Vector3(1.45, 0, -0.04)
			target["shin_r"] = Vector3(-1.25, 0, 0)
			target["shin_l"] = Vector3(-1.3, 0, 0)
			target["foot_r"] = Vector3(-0.15, 0, 0)
			target["foot_l"] = Vector3(-0.1, 0, 0)
			target["spine"] = Vector3(0.10, 0, 0)
			target["upperarm_l"] = Vector3(1.15, 0.15, -0.05)
			target["forearm_l"] = Vector3(0.55, 0, 0)
			target["upperarm_r"] = Vector3(0.85, -0.25, 0.18)
			target["forearm_r"] = Vector3(0.9, 0, 0)
			target["head"] = Vector3(0.05, 0.08 * sin(t * 0.2), 0)
	# Ease toward the target pose so changes of gait blend.
	var k := 1.0 if delta <= 0.0 else clampf(delta * 12.0, 0.0, 1.0)
	for bname in target.keys():
		var cur: Vector3 = _blend[bname]
		cur = cur.lerp(target[bname], k)
		_blend[bname] = cur
		skeleton.set_bone_pose_rotation(int(_bone[bname]), Quaternion.from_euler(cur))
	_hip_off = _hip_off.lerp(hip, k)
	var hi := int(_bone["hips"])
	skeleton.set_bone_pose_position(hi, (_joint["hips"] as Vector3) + _hip_off)


## Where the eyes are, in this node's space (for the first-person camera).
func eye_local() -> Vector3:
	var hx := skeleton.get_bone_global_pose(int(_bone["head"]))
	return skeleton.transform * (hx * Vector3(0, 0.11, -0.085))
