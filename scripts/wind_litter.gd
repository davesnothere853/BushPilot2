extends Node3D
## Loose litter the wind pushes round town: sheets of paper and newspaper that
## skitter and flip along the ground, dry leaves, and a plastic grocery bag or two
## that lift off in a gust and float. Cheap hand-rolled physics (no bodies):
## gravity, air drag toward the wind, ground friction, bounce off walls.
## The town hands over ground_y(p) and blocked(p); set_wind() ties it to the
## game's weather later (DESIGN_NOTES: everything gets real physics in the game).

var ground_y: Callable            # func(p: Vector2) -> float
var blocked: Callable             # func(p: Vector2) -> bool  (inside a building)
var center := Vector2.ZERO
var area := 110.0                 # metres round the centre before a piece is sent back upwind
var wind_dir := Vector2(0.9, 0.35).normalized()
var wind_speed := 4.0             # m/s mean; gusts on top

var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _items: Array = []            # {node, pos, vel, spin, kind, flat_yaw}
var start_empty := false          # only what the trees drop (a lone tree in the lab)
var max_leaves := 260             # fallen leaves kept; the oldest go first
var _leaves: Array = []
var _leaf_mats := {}
var _leaf_mesh: QuadMesh

const KINDS := {
	# drag: how hard the air grabs it; fall: settling speed; stick: wind needed to move it on the ground
	"paper": {"drag": 2.2, "fall": 1.1, "stick": 2.6, "lift": 0.18},
	"news": {"drag": 1.8, "fall": 1.4, "stick": 3.2, "lift": 0.12},
	"leaf": {"drag": 2.8, "fall": 0.9, "stick": 2.0, "lift": 0.22},
	"bag": {"drag": 3.2, "fall": 0.45, "stick": 1.4, "lift": 0.55},
	"fleaf": {"drag": 2.6, "fall": 0.55, "stick": 2.2, "lift": 0.2},
	"cup": {"drag": 0.9, "fall": 9.0, "stick": 3.5, "lift": 0.0},
}


func _ready() -> void:
	_rng.seed = 82
	if start_empty:
		return
	for i in range(16):
		_spawn("paper" if i % 3 != 0 else "news", true)
	for i in range(14):
		_spawn("leaf", true)
	for i in range(3):
		_spawn("bag", true)
	for i in range(3):
		_spawn("cup", true)


func set_wind(dir: Vector2, speed: float) -> void:
	wind_dir = dir.normalized()
	wind_speed = speed


func _mesh(kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.85
	match kind:
		"paper", "news":
			var q := QuadMesh.new()
			q.size = Vector2(0.21, 0.28) if kind == "paper" else Vector2(0.38, 0.29)
			q.orientation = PlaneMesh.FACE_Y
			mi.mesh = q
			m.albedo_color = Color(0.93, 0.92, 0.86) if kind == "paper" else Color(0.78, 0.77, 0.72)
		"leaf":
			var q2 := QuadMesh.new()
			q2.size = Vector2(0.08, 0.1)
			q2.orientation = PlaneMesh.FACE_Y
			mi.mesh = q2
			m.albedo_color = [Color(0.62, 0.36, 0.10), Color(0.70, 0.52, 0.12), Color(0.45, 0.22, 0.08)][_rng.randi() % 3]
		"bag":
			var s := SphereMesh.new()
			s.radius = 0.16
			s.height = 0.22
			s.radial_segments = 7
			s.rings = 4
			mi.mesh = s
			mi.scale = Vector3(1.2, 0.8, 0.9)
			m.albedo_color = Color(0.95, 0.95, 0.93, 0.82)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.35
		"cup":
			var c := CylinderMesh.new()
			c.top_radius = 0.045
			c.bottom_radius = 0.035
			c.height = 0.11
			c.radial_segments = 8
			mi.mesh = c
			m.albedo_color = Color(0.92, 0.90, 0.85)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _spawn(kind: String, anywhere: bool) -> void:
	var it := {"kind": kind, "node": _mesh(kind), "vel": Vector3.ZERO, "spin": Vector3.ZERO, "yaw": _rng.randf() * TAU}
	add_child(it["node"])
	_items.append(it)
	_place(it, anywhere)


func _place(it: Dictionary, anywhere: bool) -> void:
	var p := Vector2.ZERO
	for k in range(20):
		if anywhere:
			p = center + Vector2(_rng.randf_range(-area, area), _rng.randf_range(-area, area)) * 0.8
		else:                       # come in from the upwind edge
			var side := Vector2(-wind_dir.y, wind_dir.x)
			p = center - wind_dir * area * 0.95 + side * _rng.randf_range(-area, area) * 0.8
		if not blocked.is_valid() or not blocked.call(p):
			break
	var gy := _gy(p)
	it["pos"] = Vector3(p.x, gy + (0.0 if anywhere else _rng.randf_range(0.0, 1.5)), p.y)
	it["vel"] = Vector3.ZERO


func _gy(p: Vector2) -> float:
	return float(ground_y.call(p)) if ground_y.is_valid() else 0.0


## Wind at a point: the mean, a slow swing in direction, rolling gusts, and a
## little swirl that changes from place to place (eddies round the buildings).
func _wind_at(p: Vector3) -> Vector3:
	var swing := 0.35 * sin(_t * 0.045) + 0.15 * sin(_t * 0.17 + 2.0)
	var d := wind_dir.rotated(swing)
	var gust := maxf(0.0, sin(_t * 0.31 + p.x * 0.02) * sin(_t * 0.11 + p.z * 0.015 + 1.0)) * 2.4
	var spd := wind_speed * (0.7 + 0.3 * sin(_t * 0.7 + p.x * 0.1)) * (1.0 + gust)
	var swirl := Vector2(sin(p.z * 0.21 + _t * 0.9), cos(p.x * 0.19 - _t * 0.8)) * wind_speed * 0.25
	var w := d * spd + swirl
	var up := (0.6 + 0.4 * sin(_t * 1.3 + p.x)) * gust * 0.6
	return Vector3(w.x, up, w.y)


## A leaf letting go of its tree at `pos`: it flutters down, lands, and the wind has it.
func drop_leaf(pos: Vector3, col: Color) -> void:
	var it: Dictionary
	if _leaves.size() >= max_leaves:
		it = _leaves.pop_front()
		_leaves.append(it)
	else:
		if _leaf_mesh == null:
			_leaf_mesh = QuadMesh.new()
			_leaf_mesh.size = Vector2(0.13, 0.13)
			_leaf_mesh.orientation = PlaneMesh.FACE_Y
		var mi := MeshInstance3D.new()
		mi.mesh = _leaf_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		it = {"kind": "fleaf", "node": mi, "spin": Vector3.ZERO}
		_leaves.append(it)
		_items.append(it)
	# colour bucketed so a few materials serve them all
	var key := "%d_%d_%d" % [int(col.r * 8), int(col.g * 8), int(col.b * 8)]
	if not _leaf_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://scripts/leaf_tree.gd")._img_tex("res://textures/leaf_one.png")
		m.albedo_color = Color(col.r * 1.5, col.g * 1.5, col.b * 1.5)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.8
		m.backlight_enabled = true
		m.backlight = Color(col.r * 0.5, col.g * 0.5, col.b * 0.5)
		_leaf_mats[key] = m
	(it["node"] as MeshInstance3D).material_override = _leaf_mats[key]
	it["pos"] = pos
	it["vel"] = Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))
	it["yaw"] = _rng.randf() * TAU
	it["phase"] = _rng.randf() * TAU
	it["kind"] = "fleaf"


func _physics_process(dt: float) -> void:
	_t += dt
	for it in _items:
		var k: Dictionary = KINDS[it["kind"]]
		var pos: Vector3 = it["pos"]
		var vel: Vector3 = it["vel"]
		var p2 := Vector2(pos.x, pos.z)
		var gy := _gy(p2)
		var w := _wind_at(pos)
		var on_ground := pos.y <= gy + 0.01
		var ws := Vector2(w.x, w.z).length()
		if on_ground and ws < float(k["stick"]):
			# lying still: just a shiver of the edges
			vel = vel * maxf(0.0, 1.0 - 6.0 * dt)
		else:
			var rel := w - vel
			vel.x += rel.x * float(k["drag"]) * dt
			vel.z += rel.z * float(k["drag"]) * dt
			# lift from the gust, settling under its own weight
			vel.y += (w.y * float(k["lift"]) * 3.0 - float(k["fall"]) * 2.0) * dt
			vel.y = maxf(vel.y, -float(k["fall"]) * 1.6)
			if on_ground:
				vel.x *= 1.0 - 1.5 * dt                 # scraping along
				vel.z *= 1.0 - 1.5 * dt
				if ws > float(k["stick"]) * 1.6 and _rng.randf() < dt * 2.0:
					vel.y = _rng.randf_range(0.4, 1.4) * (2.0 if it["kind"] == "bag" else 1.0)   # caught and flipped up
		if it["kind"] == "fleaf" and pos.y > gy + 0.05:
			# falling like a leaf: rocking side to side as it sinks, swinging under its own lift
			var ph: float = float(it.get("phase", 0.0)) + dt * 3.2
			it["phase"] = ph
			var sway := Vector3(cos(float(it["yaw"])), 0, sin(float(it["yaw"]))) * cos(ph) * 1.3
			vel.y = lerpf(vel.y, -0.75 - 0.35 * sin(ph * 2.0), dt * 3.0)
			vel.x += (sway.x - vel.x * 0.3) * dt * 2.0
			vel.z += (sway.z - vel.z * 0.3) * dt * 2.0
		var np := pos + vel * dt
		var n2 := Vector2(np.x, np.z)
		if blocked.is_valid() and blocked.call(n2):
			# hit a wall: stop dead, slide up it a bit in a strong wind
			np.x = pos.x
			np.z = pos.z
			vel.x *= -0.25
			vel.z *= -0.25
			vel.y += ws * 0.08
		var g2 := _gy(Vector2(np.x, np.z))
		if np.y < g2:
			np.y = g2
			vel.y = absf(vel.y) * 0.15
		it["pos"] = np
		it["vel"] = vel
		# turning: tumbles in the air, flat (with its slow spin) on the ground
		var node: MeshInstance3D = it["node"]
		var spd := vel.length()
		var air := np.y > g2 + 0.03
		if air or spd > 0.4:
			var sp: Vector3 = it["spin"]
			sp = sp.lerp(Vector3(vel.z, vel.length() * 0.5, -vel.x) * (3.0 if it["kind"] != "bag" else 0.8), dt * 2.0)
			it["spin"] = sp
			var b := node.basis.orthonormalized()
			if sp.length() > 0.001:
				b = Basis(sp.normalized(), sp.length() * dt) * b
			node.basis = b.scaled(node.scale) if it["kind"] == "bag" else b
		else:
			var flat := Basis(Vector3.UP, float(it["yaw"]))
			node.basis = node.basis.orthonormalized().slerp(flat, minf(1.0, dt * 4.0)).scaled(node.scale) if it["kind"] == "bag" else node.basis.orthonormalized().slerp(flat, minf(1.0, dt * 4.0))
		var lift := 0.004 if it["kind"] != "bag" else 0.08
		if it["kind"] == "cup":
			lift = 0.04
		node.position = np + Vector3(0, lift, 0)
		if Vector2(np.x, np.z).distance_to(center) > area and it["kind"] != "fleaf":
			_place(it, false)
