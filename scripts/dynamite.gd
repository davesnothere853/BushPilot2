extends Node3D
## Dynamite (DESIGN_NOTES 176): a lit stick thrown or set against a face. The
## fuse spits and hisses, then the blast: a flash, a boom, rock and dirt
## flung out, a crater cut into the ground (or a bite out of a drift face) and
## the spoil thrown up round its rim; trees close by go over; anyone near is
## hurt, the very near killed.

const Inventory = preload("res://scripts/inventory.gd")
const Flora = preload("res://scripts/flora.gd")

var terrain: RefCounted          # ground.gd
var vox: Node                    # voxel_ground.gd (drifts, caves), or null
var explosions: Node
var prospect: Node
var world: Node
var on_blast: Callable           # func(at) - main: gore, jolts

var charges: Array = []          # {node, vel, fuse, rest, spin}
static var _hiss: AudioStreamWAV


## Light one: `at` where it is, `vel` how it's thrown (zero: set in place).
var last_at := Vector3.ZERO     # the last one lit (co-op passes it on)
var last_vel := Vector3.ZERO
var last_fuse := 0.0


func light(at: Vector3, vel: Vector3, fuse: float) -> void:
	last_at = at
	last_vel = vel
	last_fuse = fuse
	var root := Node3D.new()
	add_child(root)
	var m: Node3D = Inventory.build_mesh("dynamite")
	m.scale = Vector3.ONE * 0.8
	root.add_child(m)
	# the fuse burning: hot sparks and a little smoke off the end
	var sp := CPUParticles3D.new()
	sp.amount = 24
	sp.lifetime = 0.35
	sp.local_coords = false
	sp.direction = Vector3.UP
	sp.spread = 70.0
	sp.initial_velocity_min = 0.4
	sp.initial_velocity_max = 1.6
	sp.gravity = Vector3(0, -4.0, 0)
	sp.scale_amount_min = 0.5
	sp.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(1.0, 0.75, 0.30)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.2)
	q.material = mat
	sp.mesh = q
	root.add_child(sp)
	sp.position = Vector3(0.0, 0.08, -0.12)
	sp.emitting = true
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.25)
	glow.light_energy = 0.8
	glow.omni_range = 2.5
	root.add_child(glow)
	glow.position = sp.position
	var hs := AudioStreamPlayer3D.new()
	hs.stream = _hiss_stream()
	hs.unit_size = 2.0
	hs.volume_db = -8.0
	root.add_child(hs)
	hs.play()
	root.global_position = at
	charges.append({"node": root, "vel": vel, "fuse": fuse, "rest": vel.length() < 0.01,
		"spin": Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)) if vel.length() > 0.01 else Vector3.ZERO})


static func _hiss_stream() -> AudioStreamWAV:
	if _hiss != null:
		return _hiss
	var rate := 22050
	var n := rate                       # one second, looped
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in range(n):
		var w := randf() * 2.0 - 1.0
		lp += (w - lp) * 0.35            # a soft hiss, the crackle of the powder on top
		var v := lp * 0.5 + (0.6 if randf() < 0.003 else 0.0) * (1.0 if randf() < 0.5 else -1.0)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	_hiss = AudioStreamWAV.new()
	_hiss.format = AudioStreamWAV.FORMAT_16_BITS
	_hiss.mix_rate = rate
	_hiss.data = data
	_hiss.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_hiss.loop_end = n
	return _hiss


func _ground(p: Vector3) -> float:
	var g: float = terrain.height_at(p.x, p.z)
	if vox != null and vox.has_method("floor_below"):
		var f: float = vox.floor_below(p + Vector3(0, 0.3, 0), 6.0)
		if f > -1.0e8 and f < p.y + 0.4:
			g = f                          # underground: the drift floor
	return g


func _physics_process(delta: float) -> void:
	for i in range(charges.size() - 1, -1, -1):
		var c: Dictionary = charges[i]
		var node: Node3D = c["node"]
		c["fuse"] = float(c["fuse"]) - delta
		if not bool(c["rest"]):
			var v: Vector3 = c["vel"]
			v.y -= 9.81 * delta
			var p := node.global_position + v * delta
			# into a drift wall or a rock face: it stops there
			if vox != null and vox.has_method("sdf_at") and vox.sdf_at(p) < 0.0:
				p = node.global_position
				v = Vector3.ZERO
			var g := _ground(p)
			if p.y < g + 0.04:
				p.y = g + 0.04
				if v.y < 0.0:
					v.y = -v.y * 0.25
				v.x *= 0.55
				v.z *= 0.55
				c["spin"] = (c["spin"] as Vector3) * 0.5
				if v.length() < 0.4:
					c["rest"] = true
					v = Vector3.ZERO
			var sp: Vector3 = c["spin"]
			if sp.length() > 0.01:
				node.global_transform.basis = Basis(sp.normalized(), sp.length() * delta) * node.global_transform.basis
			node.global_position = p
			c["vel"] = v
		if float(c["fuse"]) <= 0.0:
			var at := node.global_position
			node.queue_free()
			charges.remove_at(i)
			_blast(at)


func _blast(at: Vector3) -> void:
	if explosions != null and explosions.has_method("rock_blast"):
		explosions.rock_blast(at, 1.0)
	var removed := 0.0
	# the crater: dirt, gravel and rock broken out (it breaks rock, unlike a shovel)
	if prospect != null:
		var got: Dictionary = prospect.dig(at + Vector3(0, -0.3, 0), 2.2, 4.5, 1.0)
		removed = float(got.get("over", 0.0)) + float(got.get("pay", 0.0)) + float(got.get("rock", 0.0))
	# against a drift face or in a cave: a bite out of the rock
	if vox != null and vox.has_method("carve"):
		vox.carve(at, 1.6)
	# the spoil thrown up round the rim
	if removed > 0.05 and terrain != null and terrain.has_method("deposit"):
		var parts := 6
		for k in range(parts):
			var a := TAU * float(k) / float(parts) + randf_range(-0.3, 0.3)
			var r := randf_range(2.8, 4.5)
			terrain.deposit(at + Vector3(cos(a) * r, 0, sin(a) * r), removed * 0.85 / float(parts))
	# trees right by it go over, away from the blast
	if world != null:
		var tr: Dictionary = Flora.tree_near(terrain, at + Vector3(0, 1.0, 0))
		if not tr.is_empty() and float(tr["dist"]) < 3.5:
			var away: Vector3 = (tr["base"] as Vector3) - at
			away.y = 0.0
			world.fell_tree(int(tr["ti"]), int(tr["tj"]), (away.normalized() if away.length() > 0.1 else Vector3.FORWARD) * 4.0)
	if on_blast.is_valid():
		on_blast.call(at)
