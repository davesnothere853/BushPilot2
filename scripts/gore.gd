extends Node3D
## Propeller strike gore (DESIGN_NOTES 81): a burst of blood spray and
## chunks off the blades, red mist, blood splats projected (Decals) onto the
## ground round the plane and onto the plane itself - cowling, spinner,
## windscreen, wing leading edges. The plane's splats ride with it and stay
## until it's washed (water truck spray) or repaired.

const PilotRig = preload("res://scripts/pilot_rig.gd")

var _tex: Array = []                 # a few splat textures
var plane_decals: Array = []         # Decals parented to the plane
var ground_decals: Array = []
const MAX_GROUND := 60


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for i in range(4):
		_tex.append(_make_splat(i * 7 + 3, i == 3))


## A splat texture: a wet blob with droplets flung off it, or a long streak.
static func _make_splat(seed_v: int, streak: bool) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 0.06
	var blobs: Array = []
	if streak:
		for k in range(14):
			var t := float(k) / 13.0
			blobs.append([Vector2(20.0 + t * 88.0, 64.0 + sin(t * 3.0) * 6.0), lerpf(13.0, 3.0, t)])
	else:
		blobs.append([Vector2(64, 64), 26.0])
		for k in range(5):
			var a := rng.randf() * TAU
			blobs.append([Vector2(64, 64) + Vector2(cos(a), sin(a)) * rng.randf_range(14.0, 26.0), rng.randf_range(8.0, 14.0)])
	for k2 in range(28):
		var a2 := rng.randf() * TAU
		var r2 := rng.randf_range(30.0, 60.0)
		blobs.append([Vector2(64, 64) + Vector2(cos(a2), sin(a2)) * r2, rng.randf_range(1.5, 4.5)])
	for y in range(n):
		for x in range(n):
			var p := Vector2(x, y)
			var v := 0.0
			for b in blobs:
				var d: float = p.distance_to(b[0]) / float(b[1])
				v = maxf(v, 1.0 - d)
			v += noise.get_noise_2d(x, y) * 0.25
			if v > 0.0:
				var a3 := clampf(v * 4.0, 0.0, 1.0)
				var dark := clampf(v * 1.5, 0.0, 1.0)
				img.set_pixel(x, y, Color(lerpf(0.55, 0.28, dark), 0.02, 0.02, a3 * 0.95))
	return ImageTexture.create_from_image(img)


func _decal(parent: Node3D, xf: Transform3D, size: float, tex_i: int) -> Decal:
	var d := Decal.new()
	d.texture_albedo = _tex[tex_i % _tex.size()]
	d.size = Vector3(size, 0.6, size)
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.albedo_mix = 0.95
	d.modulate = Color(1, 1, 1, 1)
	parent.add_child(d)
	d.global_transform = xf
	return d


## The strike itself. `hub` world position of the prop hub, `axis` the
## shaft direction (forward), `victim` where the body met the blades.
func prop_strike(plane: Node3D, hub: Vector3, axis: Vector3, victim: Vector3, ground: Callable) -> void:
	if not Game.gore:
		return
	var fwd := axis.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	# --- the spray: thousands of droplets flung round the disc and forward ---
	for burst in range(3):
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.explosiveness = 0.92
		p.amount = 420 if burst < 2 else 120
		p.lifetime = 1.6
		p.position = Vector3.ZERO
		var dir := (fwd * 0.5 + side * (1.0 if burst == 0 else -1.0) + Vector3.UP * 0.25).normalized()
		if burst == 2:
			dir = (fwd + Vector3.UP * 0.6).normalized()
		p.direction = dir
		p.spread = 55.0 if burst < 2 else 30.0
		p.initial_velocity_min = 5.0
		p.initial_velocity_max = 16.0
		p.gravity = Vector3(0, -9.8, 0)
		p.damping_min = 0.5
		p.damping_max = 2.0
		p.scale_amount_min = 0.02 if burst < 2 else 0.05
		p.scale_amount_max = 0.06 if burst < 2 else 0.14
		var m: PrimitiveMesh = SphereMesh.new() if burst < 2 else BoxMesh.new()
		if m is SphereMesh:
			(m as SphereMesh).radius = 0.5
			(m as SphereMesh).height = 1.0
			(m as SphereMesh).radial_segments = 5
			(m as SphereMesh).rings = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.02, 0.02) if burst < 2 else Color(0.35, 0.04, 0.05)
		mat.roughness = 0.25
		m.material = mat
		p.mesh = m
		add_child(p)
		p.global_position = victim
		p.emitting = true
		get_tree().create_timer(3.0).timeout.connect(p.queue_free)
	# red mist that hangs a moment
	var mist := CPUParticles3D.new()
	mist.one_shot = true
	mist.explosiveness = 0.8
	mist.amount = 60
	mist.lifetime = 2.5
	mist.direction = fwd
	mist.spread = 80.0
	mist.initial_velocity_min = 0.5
	mist.initial_velocity_max = 2.5
	mist.gravity = Vector3(0, -0.4, 0)
	mist.scale_amount_min = 0.4
	mist.scale_amount_max = 1.0
	var qm := QuadMesh.new()
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.6, 0.05, 0.05, 0.25)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.material = mm
	mist.mesh = qm
	add_child(mist)
	mist.global_position = victim
	mist.emitting = true
	get_tree().create_timer(4.0).timeout.connect(mist.queue_free)
	# --- splats on the ground: a fan out in front and both sides of the disc ---
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(34):
		var a := rng.randf_range(-1.3, 1.3)
		var r := rng.randf_range(0.5, 7.5) * (1.0 if i > 4 else 0.3)
		var flat := Vector3(fwd.x, 0, fwd.z).normalized()
		var dirg := flat.rotated(Vector3.UP, a)
		var q := victim + dirg * r
		q.y = float(ground.call(q.x, q.z))
		var sz := rng.randf_range(0.4, 1.4) * (2.2 if i < 3 else 1.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		ground_decals.append(_decal(get_parent() as Node3D if get_parent() is Node3D else self, Transform3D(b, q), sz, rng.randi() % 3))
	while ground_decals.size() > MAX_GROUND:
		var old: Node = ground_decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	# --- splats on the plane: spinner and cowling, windscreen streaks, leading edges ---
	if plane != null:
		var pxf: Transform3D = plane.global_transform
		var local_spots := [
			[Vector3(0, 0.05, -2.0), 0.7, Vector3.FORWARD],     # spinner / cowl front
			[Vector3(0, 0.45, -1.6), 1.1, Vector3.UP],          # cowl top
			[Vector3(0.45, 0.2, -1.7), 0.8, Vector3.RIGHT],
			[Vector3(-0.45, 0.2, -1.7), 0.8, Vector3.LEFT],
			[Vector3(0, 0.8, -0.95), 1.0, Vector3(0, 0.6, -1)], # windscreen
			[Vector3(0.3, 0.8, -0.95), 0.8, Vector3(0, 0.6, -1)],
			[Vector3(-2.5, 1.25, -0.6), 1.2, Vector3.FORWARD],  # wing leading edges
			[Vector3(2.5, 1.25, -0.6), 1.2, Vector3.FORWARD],
		]
		for i2 in range(local_spots.size()):
			var sp: Array = local_spots[i2]
			var nrm: Vector3 = (sp[2] as Vector3).normalized()
			# a decal projects down its -Y: point its Y along the surface normal
			var y := nrm
			var x := Vector3.UP.cross(y) if absf(y.y) < 0.9 else Vector3.RIGHT
			x = x.normalized()
			var z := x.cross(y).normalized()
			var lx := Transform3D(Basis(x, y, z) * Basis(Vector3.UP, rng.randf() * TAU), sp[0] as Vector3)
			plane_decals.append(_decal(plane, pxf * lx, float(sp[1]) * rng.randf_range(0.8, 1.3), 3 if i2 >= 4 else rng.randi() % 3))


## The plane's blood comes off (washed).
func wash_plane() -> int:
	var n := 0
	for d in plane_decals:
		if is_instance_valid(d):
			(d as Node).queue_free()
			n += 1
	plane_decals.clear()
	return n


## One splat on the plane at a world point, facing out along `normal`
## (bird strikes, DESIGN_NOTES 82). tex_i: 0-2 blobs, 3 streak, 4 a crack.
func plane_splat(plane: Node3D, at: Vector3, normal: Vector3, size: float, tex_i: int) -> void:
	if plane == null:
		return
	if tex_i == 4 and _tex.size() < 5:
		_tex.append(_make_crack(17))
	var y := normal.normalized()
	var x := Vector3.UP.cross(y) if absf(y.y) < 0.9 else Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	var b := Basis(x, y, z) * Basis(Vector3.UP, randf() * TAU)
	var d := _decal(plane, Transform3D(b, at), size, tex_i)
	if tex_i == 4:
		d.albedo_mix = 1.0
	plane_decals.append(d)


## A cracked-glass star: white lines out from a crushed centre.
static func _make_crack(seed_v: int) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var c := Vector2(64, 64)
	for k in range(14):
		var a := rng.randf() * TAU
		var p := c
		var l := rng.randf_range(30.0, 62.0)
		var steps := int(l)
		for s in range(steps):
			a += rng.randf_range(-0.12, 0.12)
			p += Vector2(cos(a), sin(a))
			if p.x < 1 or p.y < 1 or p.x > n - 2 or p.y > n - 2:
				break
			img.set_pixel(int(p.x), int(p.y), Color(0.95, 0.97, 1.0, 0.9))
			img.set_pixel(int(p.x) + 1, int(p.y), Color(0.85, 0.9, 0.95, 0.5))
	for r in [10.0, 18.0, 27.0]:
		for i in range(90):
			var a2 := TAU * float(i) / 90.0
			if rng.randf() < 0.4:
				continue
			var q: Vector2 = c + Vector2(cos(a2), sin(a2)) * (r + rng.randf_range(-2.0, 2.0))
			img.set_pixel(int(q.x), int(q.y), Color(0.9, 0.95, 1.0, 0.7))
	for yy in range(56, 72):
		for xx in range(56, 72):
			if Vector2(xx, yy).distance_to(c) < 7.0:
				img.set_pixel(xx, yy, Color(0.95, 0.97, 1.0, 0.85))
	return ImageTexture.create_from_image(img)


## Feathers (and a little blood) bursting off a bird strike.
func feathers(at: Vector3, col: Color, vel: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 70
	p.lifetime = 3.0
	p.direction = vel.normalized() if vel.length() > 0.1 else Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -1.2, 0)
	p.damping_min = 2.0
	p.damping_max = 5.0
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.12
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 0.35)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.material = m
	p.mesh = qm
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(4.0).timeout.connect(p.queue_free)
	var b := CPUParticles3D.new()
	b.one_shot = true
	b.explosiveness = 0.95
	b.amount = 40
	b.lifetime = 1.2
	b.direction = p.direction
	b.spread = 40.0
	b.initial_velocity_min = 3.0
	b.initial_velocity_max = 10.0
	b.gravity = Vector3(0, -9.8, 0)
	b.scale_amount_min = 0.02
	b.scale_amount_max = 0.05
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 4
	sm.rings = 2
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.5, 0.02, 0.02)
	sm.material = bm
	b.mesh = sm
	add_child(b)
	b.global_position = at
	b.emitting = true
	get_tree().create_timer(2.0).timeout.connect(b.queue_free)



# ------------------------------------------------------------------------------
#  Bodies (DESIGN_NOTES 157): a fatal crash, being run over or caught under a
#  machine, a tree coming down on you. The pilot's own rigged figure is used
#  for every piece: the body with the lost parts shrunk away to stumps, and
#  each lost arm, leg or head as a copy with everything BUT that part shrunk
#  away (the hips scaled to nothing, the part's root scaled back up). The
#  pieces fly, tumble and come to rest like the aeroplane's debris, leaving
#  blood where they land.
# ------------------------------------------------------------------------------
const BONE := "mixamorig1_"
## part -> [root bone choices (a whole limb, or from the elbow / knee)]
const PARTS := {
	"arm_l": ["LeftArm", "LeftForeArm"], "arm_r": ["RightArm", "RightForeArm"],
	"leg_l": ["LeftUpLeg", "LeftLeg"], "leg_r": ["RightUpLeg", "RightLeg"],
	"head": ["Head"],
}
var ground_at: Callable            # func(x, z) -> float
var pieces: Array = []             # {node, vel, spin, size, rest, landed, settle, axis, flat}
var seat_corpse: Node3D            # the pilot, dead in his seat
var _bleeds: Array = []            # [CPUParticles3D, time left]


## Choose what comes off, by how violent it was (0..1+). Head last.
func pick_parts(violence: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if not Game.gore or not PilotRig.available():
		return out
	for k in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		if rng.randf() < clampf(violence * 0.55, 0.0, 0.7):
			out.append(k)
	if violence > 0.6 and rng.randf() < clampf((violence - 0.6) * 0.9, 0.0, 0.45):
		out.append("head")
	return out


## The rigged figure in a pose, frozen there.
func _figure(clip: String, parent: Node) -> Node3D:
	var r: Node3D = PilotRig.new()
	parent.add_child(r)
	var ap: AnimationPlayer = r.get("_player")
	if ap != null and not ap.has_animation(clip) and clip == "driving":
		clip = "sitting_idle"
	if ap != null and ap.has_animation(clip):
		ap.play(clip)
		ap.seek(0.05, true)
		ap.advance(0.0)
		ap.active = false
	r.set_process(false)
	return r


func _bone(r: Node3D, nm: String) -> int:
	return (r.get("skeleton") as Skeleton3D).find_bone(BONE + nm)


## Every bone under (and including) `bi`.
func _subtree(sk: Skeleton3D, bi: int) -> Array:
	var out: Array = [bi]
	var k := 0
	while k < out.size():
		for c in sk.get_bone_children(out[k]):
			out.append(c)
		k += 1
	return out


## (The cut ends used to get a red ball; Dave: no balls. The torn limb's
## own skin pinches in to the joint, and the bleeding marks it.)
func _stump(_sk: Skeleton3D, _on: int, _at: Vector3, _r: float) -> void:
	pass


## The body: the pose, the lost parts shrunk to stumps. Returns the figure.
func make_body(clip: String, lost: Array, parent: Node, rng: RandomNumberGenerator) -> Node3D:
	var r := _figure(clip, parent)
	var sk: Skeleton3D = r.get("skeleton")
	for part in lost:
		var choices: Array = PARTS[part]
		var root := _bone(r, String(choices[rng.randi() % choices.size()]))
		if root < 0:
			continue
		var at := sk.get_bone_global_pose(root).origin
		sk.set_bone_pose_scale(root, Vector3.ONE * 0.001)
		_stump(sk, sk.get_bone_parent(root), at, 0.07 if part == "head" else 0.055)
		r.set_meta("lost_" + part, sk.get_bone_name(root).trim_prefix(BONE))
	return r


## One lost part on its own, as a piece flying off from where it was on a
## body standing at `xf`. Returns the piece's pivot node.
func _part_piece(clip: String, part: String, bone_nm: String, xf: Transform3D) -> Node3D:
	var pivot := Node3D.new()
	add_child(pivot)
	var r := _figure(clip, pivot)
	r.global_transform = xf
	var sk: Skeleton3D = r.get("skeleton")
	var root := _bone(r, bone_nm)
	var hips := _bone(r, "Hips")
	if root < 0 or hips < 0:
		pivot.queue_free()
		return null
	sk.set_bone_pose_scale(hips, Vector3.ONE * 0.001)
	sk.set_bone_pose_scale(root, Vector3.ONE * 1000.0)
	# its middle, for it to tumble about, and the cut end
	var sub := _subtree(sk, root)
	var c := Vector3.ZERO
	for b in sub:
		c += sk.get_bone_global_pose(b).origin
	c /= float(sub.size())
	var cut := sk.get_bone_global_pose(root).origin
	_stump(sk, root, cut, 0.06 if part == "head" else 0.05)
	var to_world := sk.global_transform
	var cw: Vector3 = to_world * c
	var cut_w: Vector3 = to_world * cut
	pivot.global_position = cw
	r.global_transform = xf          # the figure stays put; the pivot is now at the part's middle
	pivot.set_meta("axis", (cw - cut_w).normalized() if cw.distance_to(cut_w) > 0.01 else Vector3.UP)
	return pivot


# ------------------------------------------------------------------------------
#  Losing a part and living (DESIGN_NOTES 180): a tool, a bullet or a blast
#  takes an arm or a leg off someone still standing. The live figure has
#  that bone shrunk away (kept shrunk after the animation every frame) and
#  bleeds from the stump; the part flies off as a piece like the crash ones.
# ------------------------------------------------------------------------------
func sever_live(rig: Node3D, part: String, vel: Vector3, rng: RandomNumberGenerator) -> bool:
	if not Game.gore or rig == null or not is_instance_valid(rig) or rig.get("skeleton") == null or not PARTS.has(part):
		return false
	if rig.has_meta("lost_" + part):
		return false
	var sk: Skeleton3D = rig.get("skeleton")
	var choices: Array = PARTS[part]
	var nm := String(choices[rng.randi() % choices.size()])
	var root := sk.find_bone(BONE + nm)
	if root < 0:
		return false
	var cut_w: Vector3 = sk.global_transform * sk.get_bone_global_pose(root).origin
	var pv := _part_piece("idle", part, nm, rig.global_transform)
	rig.set_meta("lost_" + part, nm)
	_keep_lost(rig)
	if pv != null:
		var out := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.5, 1.2), rng.randf_range(-1, 1)).normalized() * rng.randf_range(1.5, 4.0)
		pieces.append({"node": pv, "vel": vel + out,
			"spin": Vector3(rng.randf_range(-9, 9), rng.randf_range(-9, 9), rng.randf_range(-9, 9)),
			"size": 0.09 if part == "head" else 0.06, "rest": 0.0, "landed": false, "body": false})
		_bleed(pv, Vector3.ZERO, 3.0)
	_bleed(rig, rig.global_transform.affine_inverse() * cut_w, 10.0)       # the stump
	burst(cut_w, vel, 0.45)
	return true


## The parts this figure has lost (live), e.g. ["arm_l"].
func lost_live(rig: Node3D) -> Array:
	var out: Array = []
	if rig == null or not is_instance_valid(rig):
		return out
	for part in PARTS.keys():
		if rig.has_meta("lost_" + part):
			out.append(part)
	return out


## Whole again (a fresh start after dying).
func restore_live(rig: Node3D) -> void:
	if rig == null or not is_instance_valid(rig) or rig.get("skeleton") == null:
		return
	var sk: Skeleton3D = rig.get("skeleton")
	for part in PARTS.keys():
		if rig.has_meta("lost_" + part):
			var bi := sk.find_bone(BONE + String(rig.get_meta("lost_" + part)))
			if bi >= 0:
				sk.set_bone_pose_scale(bi, Vector3.ONE)
			rig.remove_meta("lost_" + part)


## Shrink the lost bones now, and again each time the animation has posed
## the skeleton (in case a clip keys scale).
func _keep_lost(rig: Node3D) -> void:
	_apply_lost(rig)
	var ap: AnimationPlayer = rig.get("_player")
	if ap != null and ap.has_signal("mixer_applied") and not ap.is_connected("mixer_applied", _apply_lost.bind(rig)):
		ap.connect("mixer_applied", _apply_lost.bind(rig))


func _apply_lost(rig: Node3D) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var sk: Skeleton3D = rig.get("skeleton")
	if sk == null:
		return
	for part in PARTS.keys():
		if rig.has_meta("lost_" + part):
			var bi := sk.find_bone(BONE + String(rig.get_meta("lost_" + part)))
			if bi >= 0:
				sk.set_bone_pose_scale(bi, Vector3.ONE * 0.001)


## Throw pieces: `body_xf` the figure (feet origin, facing -Z), `vel` the
## velocity it all carries, `lying` the body comes to rest on its back.
func scatter(body_xf: Transform3D, clip: String, lost: Array, vel: Vector3, rng: RandomNumberGenerator, throw_body: bool, flat: float = 1.0, body: Node3D = null) -> Node3D:
	if throw_body:
		body = make_body("sprawl" if clip == "" else clip, lost, self, rng)
		body.global_transform = body_xf
		pieces.append({"node": body, "vel": vel, "spin": Vector3(rng.randf_range(-3, 3), rng.randf_range(-2, 2), rng.randf_range(-3, 3)) * clampf(vel.length() / 8.0, 0.2, 1.5),
			"size": 0.14, "rest": 0.0, "landed": false, "body": true, "flat": flat})
		_bleed(body, Vector3(0, 0.3, 0), 6.0)
	for part in lost:
		var nm := String((body.get_meta("lost_" + part) if body != null and body.has_meta("lost_" + part) else (PARTS[part] as Array)[0]))
		var pv := _part_piece(clip if clip != "" else "sprawl", part, nm, body_xf)
		if pv == null:
			continue
		var out := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.4, 1.2), rng.randf_range(-1, 1)).normalized() * rng.randf_range(2.0, 6.0)
		pieces.append({"node": pv, "vel": vel * rng.randf_range(0.6, 1.1) + out,
			"spin": Vector3(rng.randf_range(-9, 9), rng.randf_range(-9, 9), rng.randf_range(-9, 9)),
			"size": 0.09 if part == "head" else 0.06, "rest": 0.0, "landed": false, "body": false})
		_bleed(pv, Vector3.ZERO, 3.0)
	return body


## Blood running from a fresh wound for a while.
func _bleed(on: Node3D, off: Vector3, secs: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = 30
	p.lifetime = 0.8
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.015
	p.scale_amount_max = 0.035
	p.local_coords = false
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 4
	sm.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.02, 0.02)
	m.roughness = 0.2
	sm.material = m
	p.mesh = sm
	on.add_child(p)
	p.position = off
	p.emitting = true
	_bleeds.append([p, secs])


## A burst of blood and red mist at a body (an impact, a crush).
func burst(at: Vector3, dir: Vector3, strength: float) -> void:
	if not Game.gore:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = int(80 + 220 * clampf(strength, 0.0, 1.5))
	p.lifetime = 1.4
	p.direction = (dir.normalized() + Vector3.UP * 0.4).normalized() if dir.length() > 0.1 else Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0 + 8.0 * strength
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.07
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 5
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.02, 0.02)
	m.roughness = 0.25
	sm.material = m
	p.mesh = sm
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)
	# splats round about, mostly along the way it was going
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
	for i in range(int(6 + 10 * clampf(strength, 0.0, 1.5))):
		var q: Vector3 = at + flat.rotated(Vector3.UP, rng.randf_range(-1.4, 1.4)) * rng.randf_range(0.0, 1.0 + 4.0 * strength)
		ground_splat(q, rng.randf_range(0.4, 1.3), rng)


func ground_splat(q: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	if not ground_at.is_valid():
		return
	q.y = float(ground_at.call(q.x, q.z))
	var par: Node3D = get_parent() as Node3D if get_parent() is Node3D else self
	ground_decals.append(_decal(par, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), q), size, rng.randi() % 3))
	while ground_decals.size() > MAX_GROUND:
		var old: Node = ground_decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## The pilot dead in his seat (a crash he didn't walk away from).
func corpse_in_seat(host: Node3D, xf: Transform3D, lost: Array, rng: RandomNumberGenerator) -> void:
	clear_seat()
	seat_corpse = make_body("driving", lost, host, rng)
	seat_corpse.transform = xf
	_bleed(seat_corpse, Vector3(0, 1.2, 0), 8.0)


func clear_seat() -> void:
	if seat_corpse != null and is_instance_valid(seat_corpse):
		seat_corpse.queue_free()
	seat_corpse = null


## All of it gone (start over at the last strip).
func clear_bodies() -> void:
	clear_seat()
	for pc in pieces:
		if is_instance_valid(pc["node"]):
			(pc["node"] as Node).queue_free()
	pieces.clear()


func _physics_process(delta: float) -> void:
	for k in range(_bleeds.size() - 1, -1, -1):
		var b: Array = _bleeds[k]
		b[1] = float(b[1]) - delta
		if not is_instance_valid(b[0]):
			_bleeds.remove_at(k)
		elif float(b[1]) <= 0.0:
			(b[0] as CPUParticles3D).emitting = false
			if float(b[1]) < -2.0:
				(b[0] as Node).queue_free()
				_bleeds.remove_at(k)
	if not ground_at.is_valid():
		return
	for pc in pieces:
		if float(pc["rest"]) > 2.0:
			continue
		var node: Node3D = pc["node"]
		if not is_instance_valid(node):
			continue
		var v: Vector3 = pc["vel"]
		var spin: Vector3 = pc["spin"]
		var size: float = pc["size"]
		v.y -= 9.81 * delta
		v *= 1.0 - minf(0.02 * delta * v.length(), 0.3)
		var p := node.global_position + v * delta
		var g: float = ground_at.call(p.x, p.z)
		var on_ground := false
		if p.y < g + size:
			p.y = g + size
			on_ground = true
			if not bool(pc["landed"]) or v.y < -3.0:
				# where it hits, it leaves blood
				var rng := RandomNumberGenerator.new()
				rng.randomize()
				ground_splat(p, rng.randf_range(0.5, 1.2) if bool(pc.get("body", false)) else rng.randf_range(0.25, 0.6), rng)
			pc["landed"] = true
			if v.y < 0.0:
				v.y = -v.y * 0.2
			v.x *= 1.0 - minf(5.0 * delta, 1.0)
			v.z *= 1.0 - minf(5.0 * delta, 1.0)
			spin *= 1.0 - minf(6.0 * delta, 1.0)
		var b := node.global_transform.basis
		if spin.length() > 0.01:
			b = Basis(spin.normalized(), spin.length() * delta) * b
		# coming to rest: a body on its back, a limb lying along the ground
		if on_ground and v.length() < 1.5:
			var want: Basis
			if bool(pc.get("body", false)):
				if not pc.has("lie"):
					var fl := float(pc.get("flat", 1.0))
					pc["lie"] = Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1, 1, fl))
				want = pc["lie"]
			else:
				var ax: Vector3 = b.orthonormalized() * (node.get_meta("axis") as Vector3) if node.has_meta("axis") else Vector3.UP
				var hz := Vector3(ax.x, 0.0, ax.z)
				if hz.length() < 0.05:
					hz = Vector3.RIGHT
				var q := Quaternion(ax.normalized(), hz.normalized())
				want = Basis(q) * b.orthonormalized()
			var sc := want.get_scale()
			b = Basis(b.orthonormalized().get_rotation_quaternion().slerp(want.orthonormalized().get_rotation_quaternion(), minf(4.0 * delta, 1.0))) * Basis.from_scale(sc)
			if bool(pc.get("body", false)):
				p.y = g + 0.1
			pc["rest"] = float(pc["rest"]) + delta
		node.global_transform = Transform3D(b, p)
		pc["vel"] = v
		pc["spin"] = spin
