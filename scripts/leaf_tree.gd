extends Node3D
## A dense, real-looking broadleaf tree of the Fraser Canyon country, with a fall:
## its leaves turn on their own schedule and drop, flutter down and blow about.
##   species: "bigleaf_maple" (the big native one: huge mossy limbs, gold-brown fall)
##            "red_maple" (planted on the town streets: orange to crimson)
##            "alder" (red alder: grey mottled bark, dull yellow-brown fall)
##            "cottonwood" (tall, furrowed bark, bright yellow fall)
## Bark and limbs: one mesh. Leaves: leaf-cluster cards in one MultiMesh, the
## colours, sway and drop all done in shaders/leaves.gdshader.

const MeshKit = preload("res://scripts/meshkit.gd")
const LEAF_SHADER = preload("res://shaders/leaves.gdshader")
const WindLitter = preload("res://scripts/wind_litter.gd")

@export var species := "red_maple"
@export var height := 12.0
@export var seed_ := 1
@export var autumn := 0.32           # 0 summer .. 0.5 peak colour .. 1.2 bare
@export var autumn_rate := 0.0       # per second (the lab runs a fall in a few minutes)
var litter: Node = null              # a wind_litter to drop leaves into (the town's); made if none

var _rng := RandomNumberGenerator.new()
var _bark := MeshKit.new()
var _cards: Array = []               # [Transform3D, outward, turn]
var _tips: Array = []
var _mm: MultiMeshInstance3D
var _mat: ShaderMaterial
var _drop_acc := 0.0

const SPECIES := {
	"bigleaf_maple": {"tex": "res://textures/leaf_cluster.png", "card": 0.95, "bark": Color(0.40, 0.36, 0.30), "moss": 0.55, "spread": 1.0, "trunk": 0.30,
		"cols": [Color(0.27, 0.40, 0.14), Color(0.62, 0.62, 0.16), Color(0.92, 0.72, 0.18), Color(0.80, 0.52, 0.14), Color(0.48, 0.34, 0.17)]},
	"red_maple": {"tex": "res://textures/leaf_cluster.png", "card": 0.7, "bark": Color(0.42, 0.40, 0.38), "moss": 0.08, "spread": 0.85, "trunk": 0.24,
		"cols": [Color(0.24, 0.40, 0.13), Color(0.70, 0.55, 0.12), Color(0.95, 0.42, 0.08), Color(0.78, 0.10, 0.06), Color(0.42, 0.16, 0.10)]},
	"alder": {"tex": "res://textures/leaf_cluster_oval.png", "card": 0.62, "bark": Color(0.66, 0.66, 0.62), "moss": 0.25, "spread": 0.6, "trunk": 0.18,
		"cols": [Color(0.24, 0.38, 0.15), Color(0.42, 0.46, 0.16), Color(0.62, 0.56, 0.20), Color(0.55, 0.42, 0.18), Color(0.40, 0.31, 0.18)]},
	"cottonwood": {"tex": "res://textures/leaf_cluster_oval.png", "card": 0.75, "bark": Color(0.50, 0.48, 0.44), "moss": 0.1, "spread": 0.55, "trunk": 0.32,
		"cols": [Color(0.26, 0.42, 0.16), Color(0.70, 0.70, 0.18), Color(0.98, 0.82, 0.16), Color(0.90, 0.68, 0.12), Color(0.55, 0.42, 0.18)]},
}


func _ready() -> void:
	_rng.seed = seed_
	var sp: Dictionary = SPECIES.get(species, SPECIES["red_maple"])
	var trunk_r: float = float(sp["trunk"]) * height / 12.0
	var tlen := height * _rng.randf_range(0.30, 0.38)
	_limb(Vector3.ZERO, Vector3(_rng.randf_range(-0.06, 0.06), 1, _rng.randf_range(-0.06, 0.06)).normalized(), tlen, trunk_r, 0, sp)
	_root_flare(trunk_r, sp)
	var bark_mi := _bark.instance("Bark")
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.albedo_texture = _img_tex("res://textures/bark.png")
	bm.uv1_triplanar = true
	bm.uv1_scale = Vector3(1.6, 0.5, 1.6)
	bm.roughness = 0.95
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	bark_mi.material_override = bm
	add_child(bark_mi)
	_leaves(sp)
	if litter == null:
		litter = WindLitter.new()
		litter.start_empty = true
		litter.area = height * 3.0
		add_child(litter)
		_ground_disc()


## One limb: a few bent segments, children off its end and along it.
func _limb(p: Vector3, dir: Vector3, length: float, r: float, depth: int, sp: Dictionary) -> void:
	var segs := 4 if depth < 2 else 2
	var pos := p
	var d := dir
	var r0 := r
	var r1 := r * 0.62
	var pts: Array = []
	for s in range(segs):
		var f0 := float(s) / segs
		var f1 := float(s + 1) / segs
		var ra := lerpf(r0, r1, f0)
		var rb := lerpf(r0, r1, f1)
		var L := length / segs
		# bend: young limbs reach up, heavy ones sag out, all wander a bit
		d = (d + Vector3(_rng.randf_range(-0.18, 0.18), (0.08 if depth < 2 else -0.05), _rng.randf_range(-0.18, 0.18))).normalized()
		var q := pos + d * L
		_seg(pos, q, ra, rb, depth, sp)
		pts.append(q)
		pos = q
	if depth >= 3 or length < 0.7:
		_tips.append(pos)
		_cluster_round(pos, d, length, depth)
		return
	# children: a crown of 3-4 at the end, one or two off the side
	var n := 4 if depth == 0 else _rng.randi_range(2, 3)
	var spread: float = float(sp["spread"])
	var az0 := _rng.randf() * TAU
	for k in range(n):
		var az := az0 + TAU * float(k) / n + _rng.randf_range(-0.4, 0.4)
		var tilt := (0.55 if depth == 0 else 0.45) * spread + _rng.randf_range(-0.12, 0.2)
		var cd := _tilt(d, az, tilt)
		_limb(pos, cd, length * _rng.randf_range(0.62, 0.78) * (1.15 if depth == 0 else 1.0), r1 * 0.78, depth + 1, sp)
	if depth >= 1:
		var side := pts[mini(1, pts.size() - 1)] as Vector3
		_limb(side, _tilt(d, _rng.randf() * TAU, 0.9), length * 0.5, r1 * 0.55, depth + 1, sp)
	if depth >= 2:
		_cluster_round(pos, d, length, depth)


func _tilt(d: Vector3, az: float, ang: float) -> Vector3:
	var side := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	side = side.rotated(d, az)
	return d.rotated(side, ang).normalized()


func _seg(a: Vector3, b: Vector3, ra: float, rb: float, depth: int, sp: Dictionary) -> void:
	var ax := b - a
	var y := ax.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var col: Color = sp["bark"]
	col = col.lerp(Color(0.28, 0.40, 0.14), float(sp["moss"]) * (1.0 if depth < 2 else 0.4) * _rng.randf_range(0.3, 1.0))   # coast-forest moss
	var sides := 10 if depth == 0 else (7 if depth == 1 else 5)
	# a hair longer so the joints close
	_bark.cylinder(Transform3D(Basis(x, y, x.cross(y)), a - y * ra * 0.3), ra, rb, ax.length() + ra * 0.3, sides, col, false)


func _root_flare(r: float, sp: Dictionary) -> void:
	for k in range(5):
		var az := TAU * float(k) / 5.0 + _rng.randf() * 0.5
		var d := Vector3(cos(az), 0, sin(az))
		_seg(d * r * 0.4 + Vector3(0, 0.9, 0), d * r * 2.4 + Vector3(0, -0.05, 0), r * 0.5, r * 0.15, 0, sp)


## Leaf clusters round a twig's end: a ball of cards, denser on the outside.
func _cluster_round(c: Vector3, d: Vector3, length: float, depth: int) -> void:
	var n := 7 if depth >= 3 else 4
	var rad := clampf(length * 0.75, 0.6, 1.6) * height / 12.0
	for k in range(n):
		var off := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 1), _rng.randf_range(-1, 1))
		if off.length() > 1.0:
			off = off.normalized()
		var p := c + d * rad * 0.4 + off * rad
		_cards.append(p)


func _leaves(sp: Dictionary) -> void:
	# the crown's centre and size, for the outward normals and the turning order
	var cen := Vector3.ZERO
	for p in _cards:
		cen += p
	cen /= maxf(1.0, float(_cards.size()))
	var top := 0.0
	for p2 in _cards:
		top = maxf(top, (p2 as Vector3).y)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	var cs: float = float(sp["card"]) * clampf(height / 12.0, 0.7, 1.4)
	q.size = Vector2(cs, cs)
	q.center_offset = Vector3(0, cs * 0.4, 0)        # the twig's end at the card's foot
	mm.mesh = q
	mm.instance_count = _cards.size()
	for i in range(_cards.size()):
		var p3: Vector3 = _cards[i]
		var out := (p3 - cen)
		out.y *= 0.6
		out = out.normalized() if out.length() > 0.01 else Vector3.UP
		# face roughly outward and up, twisted at random so the crown has no grain
		var up := (out + Vector3(_rng.randf_range(-0.6, 0.6), 0.9, _rng.randf_range(-0.6, 0.6))).normalized()
		var fwd := out.rotated(up, _rng.randf_range(-1.2, 1.2))
		fwd = (fwd - up * fwd.dot(up)).normalized()
		if fwd.length() < 0.1:
			fwd = Vector3.FORWARD
		var b := Basis(up.cross(fwd).normalized(), up, fwd).orthonormalized() * Basis(Vector3.RIGHT, _rng.randf_range(-0.5, 0.5))
		var s := _rng.randf_range(0.8, 1.2)
		var xf := Transform3D(b.scaled(Vector3(s, s, s)), p3)
		mm.set_instance_transform(i, xf)
		var v := _rng.randf_range(0.82, 1.12)
		# the shady inside of the crown a touch darker
		var shade := 0.75 + 0.25 * clampf(out.dot((p3 - cen).normalized()) * 0.5 + 0.5, 0.0, 1.0)
		mm.set_instance_color(i, Color(v * shade, v * shade * _rng.randf_range(0.95, 1.05), v * shade))
		var lo := b.inverse() * out
		# turn: the top and the sunny south side go first, plus chance
		var turn := clampf(0.5 + 0.25 * ((p3.y - cen.y) / maxf(1.0, top - cen.y)) + 0.15 * out.z + _rng.randf_range(-0.3, 0.3), 0.0, 1.0)
		mm.set_instance_custom_data(i, Color(lo.x * 0.5 + 0.5, lo.y * 0.5 + 0.5, lo.z * 0.5 + 0.5, turn))
	_mm = MultiMeshInstance3D.new()
	_mm.name = "Leaves"
	_mm.multimesh = mm
	_mat = ShaderMaterial.new()
	_mat.shader = LEAF_SHADER
	_mat.set_shader_parameter("leaf_tex", _img_tex(String(sp["tex"])))
	_mat.set_shader_parameter("tree_height", height)
	var cols: Array = sp["cols"]
	for k in range(5):
		_mat.set_shader_parameter(["c_summer", "c_early", "c_peak", "c_late", "c_dead"][k], cols[k])
	_mat.set_shader_parameter("autumn", autumn)
	_mm.material_override = _mat
	add_child(_mm)
	set_meta("leaf_colours", cols)


func _process(dt: float) -> void:
	if _mat == null:
		return
	autumn = minf(autumn + autumn_rate * dt, 1.25)
	_mat.set_shader_parameter("autumn", autumn)
	if litter != null and litter.has_method("drop_leaf"):
		var w: Vector2 = litter.wind_dir * litter.wind_speed
		_mat.set_shader_parameter("wind", w / 5.0)
		# leaves let go once they've turned: most at peak-to-brown, more in a gust
		var ripe := clampf((autumn - 0.3) * 2.0, 0.0, 1.0) * (1.0 - clampf((autumn - 1.1) * 6.0, 0.0, 1.0))
		_drop_acc += dt * ripe * (1.5 + w.length() * 0.8) * height / 12.0
		var cols: Array = get_meta("leaf_colours")
		while _drop_acc > 1.0:
			_drop_acc -= 1.0
			if _cards.is_empty():
				break
			var p: Vector3 = _cards[_rng.randi() % _cards.size()]
			var a := clampf(autumn + _rng.randf_range(-0.15, 0.15), 0.0, 1.0)
			var c: Color = cols[2].lerp(cols[3], clampf((a - 0.5) * 5.0, 0.0, 1.0)).lerp(cols[4], clampf((a - 0.7) * 5.0, 0.0, 1.0))
			if a < 0.35:
				c = cols[1].lerp(cols[2], a / 0.35)
			litter.drop_leaf(global_transform * p, c)


func _ground_disc() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(height * 6, height * 6)
	g.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.33, 0.38, 0.22)
	m.roughness = 1.0
	g.material_override = m
	add_child(g)


static var _tex_cache := {}


static func _img_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		img = Image.load_from_file(path)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex_cache[path] = t
	return t
