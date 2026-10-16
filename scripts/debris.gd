extends Node3D
## Pieces that have broken off the aeroplane: they fly, tumble, bounce and
## slide to a stop on the ground, or bob and sink in water. Simple and cheap:
## each piece is a point with a size, so there is no physics engine involved.

var terrain: RefCounted
var _pieces: Array = []     # each: {node, vel, spin, size, rest}
const MAX_PIECES := 60


func spawn(mesh: Mesh, xf: Transform3D, vel: Vector3, spin: Vector3, size: float) -> MeshInstance3D:
	if _pieces.size() >= MAX_PIECES:
		var old: Dictionary = _pieces.pop_front()
		(old["node"] as Node3D).queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.global_transform = xf
	add_child(mi)
	mi.global_transform = xf
	_pieces.append({"node": mi, "vel": vel, "spin": spin, "size": size, "rest": 0.0})
	return mi


func clear() -> void:
	for pc in _pieces:
		(pc["node"] as Node3D).queue_free()
	_pieces.clear()


func _physics_process(delta: float) -> void:
	if terrain == null:
		return
	for pc in _pieces:
		if pc["rest"] > 3.0:
			continue
		var node: MeshInstance3D = pc["node"]
		var v: Vector3 = pc["vel"]
		var spin: Vector3 = pc["spin"]
		var size: float = pc["size"]
		v.y -= 9.81 * delta
		# (DESIGN_NOTES 155: thrown further - less air drag, livelier bounces,
		# tumbling and sliding longer on the ground before it stops)
		v *= 1.0 - minf(0.025 * delta * v.length() / maxf(size, 0.3), 0.5)
		var p := node.global_position + v * delta
		var ground: float = terrain.ground_level_at(p.x, p.z)
		var water: float = terrain.water_level_at(p.x, p.z)
		var floor_y := ground + size * 0.25
		if water > -1.0e8 and water > ground:
			# Floating for a while, then going under.
			if p.y < water:
				v.y += (9.81 * 1.4 - pc["rest"] * 2.0) * delta
				v *= 1.0 - 2.0 * delta
				spin *= 1.0 - 2.0 * delta
				pc["rest"] += delta * 0.05
				floor_y = ground + size * 0.25
		if p.y < floor_y:
			p.y = floor_y
			if v.y < 0.0:
				v.y = -v.y * 0.38
				# Each bounce knocks the spin about a bit.
				spin = spin * 0.6 + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * v.length() * 0.15
			var hv := Vector2(v.x, v.z)
			hv *= maxf(1.0 - 0.9 * delta, 0.0)
			v.x = hv.x
			v.z = hv.y
			spin *= maxf(1.0 - 1.2 * delta, 0.0)
			if v.length() < 0.4:
				pc["rest"] += delta
		node.global_position = p
		var w := spin.length()
		if w > 0.001:
			node.global_basis = Basis(spin / w, w * delta) * node.global_basis
		pc["vel"] = v
		pc["spin"] = spin
