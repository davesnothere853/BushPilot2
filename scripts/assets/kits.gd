extends RefCounted
## A set of MeshKits, one per material (DESIGN_NOTES 228): an asset builds its
## geometry into k("galv"), k("wood")... and node() turns each into one
## MeshInstance3D with the shared photo-scan material. Built once per asset
## (scripts/assets/asset_lib.gd), then copied wherever it stands.

const MeshKit = preload("res://scripts/meshkit.gd")
const Tex = preload("res://scripts/tex.gd")

## The materials: [scan id, metres a tile, tint, metal (-1 = the scan's), neutral (paint)]
const MATS := {
	"galv": ["rusty_painted_metal", 1.6, Color(0.80, 0.82, 0.83), 0.55, true],   # galvanised steel (the scan's wear, no colour)
	"paint": ["rusty_painted_metal", 1.8, Color(1, 1, 1), 0.2, true],           # painted steel: vertex colour is the paint
	"rust": ["rusty_metal_02", 2.0, Color(1, 1, 1), -1.0, false],
	"corr": ["corrugated_iron", 1.6, Color(1, 1, 1), 0.6, false],
	"corr_rust": ["rusty_corrugated_iron", 2.0, Color(1, 1, 1), -1.0, false],
	"wood": ["weathered_planks", 2.0, Color(1, 1, 1), 0.0, false],              # grey weathered timber
	"timber": ["rough_wood", 1.2, Color(1, 1, 1), 0.0, false],                  # posts, beams, bark-off logs
	"siding": ["weathered_plank_siding", 2.4, Color(1, 1, 1), 0.0, false],
	"paint_wood": ["wood_peeling_paint_weathered", 2.0, Color(1, 1, 1), 0.0, true],   # painted boards (vertex colour)
	"concrete": ["concrete_wall_004", 3.0, Color(1, 1, 1), 0.0, false],
	"paint_conc": ["concrete_wall_004", 3.0, Color(1, 1, 1), 0.0, true],        # painted concrete (vertex colour)
	"rock": ["rock_face", 4.0, Color(1, 1, 1), 0.0, false],
	"sandstone": ["sandstone_cracks", 3.0, Color(1, 1, 1), 0.0, false],
	"gravel": ["gravel_floor", 2.5, Color(1, 1, 1), 0.0, false],
	"hair": ["pine_bark", 0.6, Color(1, 1, 1), 0.0, true],                      # long shaggy streaks (vertex colour)
	"bone": ["sandstone_cracks", 0.8, Color(0.95, 0.9, 0.8), 0.0, false],
	"brick": ["red_brick", 2.4, Color(1, 1, 1), 0.0, false],
	"brick_buff": ["brick_wall_09", 2.4, Color(1.0, 0.92, 0.78), 0.0, false],
	"brick_dark": ["dark_brick_wall", 2.4, Color(1, 1, 1), 0.0, false],
	"clapboard": ["white_planks_clean", 2.0, Color(1, 1, 1), 0.0, true],          # painted siding: vertex colour is the paint
	"cutstone": ["castle_wall_slates", 3.0, Color(1, 1, 1), 0.0, false],
	"shingle": ["roof_slates_02", 2.0, Color(0.8, 0.8, 0.8), 0.0, false],
	"asphalt": ["asphalt_02", 6.0, Color(1, 1, 1), 0.0, false],
	"dirt": ["dirt", 4.0, Color(1, 1, 1), 0.0, false],
	"boards": ["weathered_planks", 1.6, Color(1, 1, 1), 0.0, false],
	"plain": ["", 1.0, Color(1, 1, 1), 0.0, false],                            # small bits, no scan
}

var _kits := {}
var _extra := {}             # key -> custom material (glass, glow)
## Pieces (DESIGN_NOTES 229): what's built after piece(id, info) belongs to
## that piece (its own node, so it can break off and fall); "" is the fixed
## part. info: mat, kind ("member"/"panel"/"cable"/"block"), and its
## dimensions and links (see structure.gd).
var _cur := ""
var pieces := {}             # id -> info


func piece(id: String, info: Dictionary = {}) -> void:
	_cur = id
	if id != "" and not pieces.has(id):
		pieces[id] = info


func k(key: String) -> MeshKit:
	var ck := _cur + "|" + key
	if not _kits.has(ck):
		_kits[ck] = MeshKit.new()
	return _kits[ck]


## A kit with its own material (glass, clear ice, a lamp).
func k_mat(key: String, mat: Material) -> MeshKit:
	_extra[key] = mat
	return k(key)


func node(name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	var groups := {}
	for pid in pieces.keys():
		var g := Node3D.new()
		g.name = "P_" + String(pid)
		g.set_meta("piece", pieces[pid])
		root.add_child(g)
		groups[pid] = g
	for ck in _kits.keys():
		var kit: MeshKit = _kits[ck]
		if kit.is_empty():
			continue
		var pid2 := String(ck).get_slice("|", 0)
		var key := String(ck).get_slice("|", 1)
		var parent: Node3D = groups.get(pid2, root)
		var mi := kit.instance(key)
		if _extra.has(key):
			mi.material_override = _extra[key]
		elif MATS.has(key) and String(MATS[key][0]) != "":
			var d: Array = MATS[key]
			var mat: BaseMaterial3D = Tex.mat(d[0], d[1], d[2], true, d[3], 1.0, d[4])
			if key in ["corr", "corr_rust"]:
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED      # sheet steel: its bare back shows from inside
			mi.material_override = mat
		if _extra.has(key) and (_extra[key] as BaseMaterial3D) != null and (_extra[key] as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	return root


# --- small helpers every asset uses -----------------------------------------
static func rod(kit: MeshKit, a: Vector3, b: Vector3, r: float, c: Color, sides: int = 5, caps: bool = false) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	kit.cylinder(Transform3D(Basis(x, y, z), a), r, r, l, sides, c, caps)


## A square-section member (angle iron, a 4x4) from a to b.
static func beam(kit: MeshKit, a: Vector3, b: Vector3, w: float, c: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	kit.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, l, w), c)


static func box(kit: MeshKit, at: Vector3, s: Vector3, c: Color, yaw: float = 0.0) -> void:
	kit.box(Transform3D(Basis(Vector3.UP, yaw), at), s, c)
