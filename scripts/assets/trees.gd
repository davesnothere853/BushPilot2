extends Node3D
## The real trees (DESIGN_NOTES 231, Dave: "real trees", eztree.dev): grown
## with the EZ-Tree generator (scripts/eztree.gd) from its pine and aspen
## presets, tuned to the trees of this country and scaled to their real
## heights. Each species built once per detail level and kept (mesh(species,
## lod)); bark and leaf textures from EZ-Tree (ambientCG bark scans, its leaf
## atlases). Lab: "trees" - the lineup beside a 1.8 m man.

const EzTree = preload("res://scripts/eztree.gd")

## species: [base preset, overrides, height m, bark texture, leaf texture, leaf tint]
const SPECIES := {
	# Sitka / white spruce: a tall narrow cone, branches to the ground, drooping
	"spruce": ["pine_large", {"branch": {"angle": {"1": 112}, "children": {"0": 120}, "length": {"1": 15.0}, "gnarliness": {"0": 0.012, "1": 0.06}, "start": {"1": 0.1}}, "leaves": {"count": 24, "size": 2.1}}, 38.0, "Bark003", "pine", Color(0.40, 0.52, 0.46)],
	# western hemlock: a softer cone, the leader nodding, sweeping limbs
	"hemlock": ["pine_large", {"seed": 911, "branch": {"angle": {"1": 104}, "children": {"0": 100}, "length": {"1": 16.0}, "gnarliness": {"0": 0.015, "1": 0.12}, "start": {"1": 0.16}}, "leaves": {"count": 26, "size": 2.3, "angle": 30}}, 34.0, "Bark013", "pine", Color(0.46, 0.58, 0.44)],
	# subalpine fir: a spire, short stiff branches
	"fir": ["pine_large", {"seed": 4471, "branch": {"angle": {"1": 98}, "children": {"0": 105}, "length": {"1": 9.0}, "gnarliness": {"0": 0.01, "1": 0.04}, "start": {"1": 0.06}}, "leaves": {"count": 22, "size": 1.9}}, 20.0, "Bark007", "pine", Color(0.36, 0.48, 0.46)],
	# black cottonwood: tall, furrowed, a broad open crown up high
	"cottonwood": ["ash_large", {"seed": 2020, "branch": {"length": {"0": 52.0}}}, 30.0, "Bark001", "ash", Color(0.82, 0.92, 0.72)],
	# paper birch / aspen: slim pale trunks, light crowns
	"aspen": ["aspen_large", {}, 18.0, "Bark001", "aspen", Color(1.0, 1.0, 0.9)],
}

static var _meshes := {}
static var _mats := {}


func _ready() -> void:
	if get_child_count() > 0:
		return
	var x := -24.0
	for sp in SPECIES.keys():
		var mi := MeshInstance3D.new()
		mi.mesh = mesh(sp, 0)
		mi.position = Vector3(x, 0, 0)
		add_child(mi)
		x += 12.0
	# a 1.8 m man for scale
	var man := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.25
	cm.height = 1.8
	man.mesh = cm
	man.position = Vector3(-30, 0.9, 4)
	add_child(man)


static func _preset(name: String) -> Dictionary:
	var f := FileAccess.open("res://scripts/eztree_presets/%s.json" % name, FileAccess.READ)
	if f == null:
		return {}
	return JSON.parse_string(f.get_as_text())


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b.keys():
		if out.has(k) and out[k] is Dictionary and b[k] is Dictionary:
			out[k] = _merge(out[k], b[k])
		else:
			out[k] = b[k]
	return out


## The species' tree at a detail level (0 near, 1 middle, 2 far), metres, base at 0.
static func mesh(sp: String, lod: int) -> ArrayMesh:
	var key := "%s:%d" % [sp, lod]
	if _meshes.has(key):
		return _meshes[key]
	var d: Array = SPECIES[sp]
	var opts := _merge(_preset(d[0]), d[1])
	var t := EzTree.new()
	t.generate(opts)
	# scale to the real height: the trunk's top is the tallest point
	var top := 1.0
	for b in t.skel_branches:
		for s in b["sections"]:
			top = maxf(top, (s[0] as Vector3).y)
	var arr := t.mesh_arrays(EzTree.LODS[lod], float(d[2]) / top)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr[0])
	m.surface_set_material(0, _bark(d[3]))
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr[1])
	m.surface_set_material(1, _leaf(d[4], d[5]))
	_meshes[key] = m
	return m


static func _img(p: String) -> ImageTexture:
	var img := Image.load_from_file(ProjectSettings.globalize_path(p))
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _bark(id: String) -> StandardMaterial3D:
	if _mats.has(id):
		return _mats[id]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _img("res://textures/eztree/bark/%s_Color.jpg" % id)
	var n := _img("res://textures/eztree/bark/%s_NormalGL.jpg" % id)
	if n != null:
		m.normal_enabled = true
		m.normal_texture = n
	m.roughness = 0.95
	m.uv1_scale = Vector3(1, 0.25, 1)
	_mats[id] = m
	return m


static func _leaf(id: String, tint: Color) -> StandardMaterial3D:
	var key := id + tint.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _img("res://textures/eztree/leaves/%s.png" % id)
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	m.backlight_enabled = true
	m.backlight = Color(0.25, 0.3, 0.15)
	_mats[key] = m
	return m


## For the forest system (vegetation.gd / veg_meshes.gd): the species' tree
## at unit height, two surfaces - bark (vertex colour, alpha 0) and the leaf
## cards (UVs into the leaf picture, colour ~0.48 so the picture shows true,
## alpha 1) - the conventions of veg_common.gdshaderinc.
const KIND_SPECIES := ["spruce", "fir", "aspen", "aspen", "cottonwood", "hemlock"]     # Flora: white spruce, black spruce, birch, aspen, poplar, snag->hemlock
const BARK_COL := {"spruce": Color(0.34, 0.28, 0.23), "hemlock": Color(0.36, 0.30, 0.26), "fir": Color(0.42, 0.40, 0.38), "cottonwood": Color(0.40, 0.38, 0.35), "aspen": Color(0.80, 0.79, 0.74)}


static func veg_mesh(kind: int, lod: int, bare: bool) -> ArrayMesh:
	var sp: String = KIND_SPECIES[clampi(kind, 0, KIND_SPECIES.size() - 1)]
	var d: Array = SPECIES[sp]
	var opts := _merge(_preset(d[0]), d[1])
	var t := EzTree.new()
	t.generate(opts)
	var top := 1.0
	for b in t.skel_branches:
		for s in b["sections"]:
			top = maxf(top, (s[0] as Vector3).y)
	# for the forest: a step simpler than the close-up lineup, and the needle
	# cards thinned (a forest is thousands of these: ~20k triangles each was
	# 350 M on screen and 3 fps)
	var det: Dictionary = (EzTree.LODS[clampi(lod + 1, 1, 2)] as Dictionary).duplicate()
	det["leaf_stride"] = 3 if lod == 0 else 4
	det["leaf_scale"] = 1.45 if lod == 0 else 1.6
	det["segment_factor"] = 0.5
	det["section_stride"] = 4 if lod == 0 else 6
	var arr := t.mesh_arrays(det, 1.0 / top)
	var bc: Color = BARK_COL[sp]
	var cols := PackedColorArray()
	cols.resize((arr[0][Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	cols.fill(Color(bc.r, bc.g, bc.b, 0.0))
	arr[0][Mesh.ARRAY_COLOR] = cols
	var tint: Color = d[5]
	var lc := PackedColorArray()
	lc.resize((arr[1][Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	lc.fill(Color(tint.r * 0.48, tint.g * 0.48, tint.b * 0.48, 1.0))
	arr[1][Mesh.ARRAY_COLOR] = lc
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr[0])
	if not bare:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr[1])
	return m


static var _leaf_tex := {}


## The leaf picture for a forest kind (for the card material).
static func veg_leaf_tex(kind: int) -> Texture2D:
	var sp: String = KIND_SPECIES[clampi(kind, 0, KIND_SPECIES.size() - 1)]
	var id: String = SPECIES[sp][4]
	if not _leaf_tex.has(id):
		_leaf_tex[id] = _img("res://textures/eztree/leaves/%s.png" % id)
	return _leaf_tex[id]
