extends Node3D
## The pilot on foot: walking and running over the terrain, jumping, wading,
## bumping into trees, rocks, buildings and the plane, with a first-person or
## third-person camera. Also keeps the pilot's health and body warmth.

const PilotModel = preload("res://scripts/pilot_model.gd")
const PilotRig = preload("res://scripts/pilot_rig.gd")
const Flora = preload("res://scripts/flora.gd")

const WALK := 1.7          # m/s
const RUN := 4.6
const JUMP_V := 3.6
const GRAVITY := 9.81
const RADIUS := 0.3        # body radius for bumping into things

var terrain: RefCounted
var plane: Node3D
var model: Node3D
var extra_planes: Callable      # main: other hulls on the field to walk around
var vel := Vector3.ZERO
var yaw := 0.0             # which way the body faces
var look := Vector2.ZERO   # camera yaw, pitch
var aiming := false        # pistol up (aim down sights): the body turns with the view
var first_person := true
var grounded := true
var health := 1.0
var warmth := 1.0
var cam_dist := 3.4
var _clock := 0.0
var _fall_from := 0.0
var _warned := {}
var notice: Callable       # func(text: String) for messages on screen
var load_kg := 0.0         # what he is carrying
var swimming := false      # in water too deep to stand: floats with his head out
const SWIM := 1.1          # m/s, breaststroke; "run" is a hard crawl
const SWIM_FAST := 1.8
const FLOAT_DEPTH := 1.38  # feet this far under the surface while swimming
const Shape = preload("res://scripts/dc3_shape.gd")
## Walking around inside the DC-3: position kept in the plane's own space, on
## its floor (which slopes uphill toward the nose while the tail is down).
var in_plane := false
## The smooth voxel ground (voxel_ground.gd) when the build has it: floors,
## walls and roofs underground - tunnels, caves, overhangs.
var vox: Node3D
var ladder_at: Callable            # main: func(pos) -> ladder index or -1
var ladder_info: Callable          # main: func(i) -> [top, bottom_y]
var climbing := false


## On a ladder (DESIGN_NOTES 76): walk at the drop to get on, forward climbs
## up, back climbs down; forward at the top steps you off onto the lip, back
## at the bottom steps you off onto the floor.
var _ladder_cool := 0.0
var _left_at := ""
func _climb(delta: float, move: Vector2, wish: Vector3) -> bool:
	_ladder_cool = maxf(_ladder_cool - delta, 0.0)
	if not ladder_at.is_valid():
		return false
	var i: int = ladder_at.call(global_position)
	if i < 0:
		climbing = false
		return false
	var info: Array = ladder_info.call(i)
	var top: Vector3 = info[0]
	var bottom: float = info[1]
	var out: Vector3 = info[2] if info.size() > 2 else Vector3.BACK
	var p := global_position
	if not climbing:
		var toward_drop := wish.dot(-out) > 0.5
		# the cool-down only stops you dropping straight back over the lip you
		# just stepped onto; at the bottom, forward takes the rungs again at once
		if p.y >= top.y - 0.3 and toward_drop and (_ladder_cool <= 0.0 or _left_at != "top"):
			climbing = true                 # over the lip onto the rungs
		elif p.y <= bottom + 0.3 and p.y >= bottom - 1.6 and move.y > 0.3:
			climbing = true                 # up from the floor (or reaching up to the bottom rung)
		else:
			return false
	p.x = lerpf(p.x, top.x, clampf(6.0 * delta, 0.0, 1.0))
	p.z = lerpf(p.z, top.z, clampf(6.0 * delta, 0.0, 1.0))
	p.y = clampf(p.y + move.y * (1.1 if move.y > 0.0 else 1.4) * delta, minf(bottom, p.y), top.y)
	if p.y >= top.y - 0.01 and move.y > 0.1:
		p = top + out * 0.9                 # step off onto the lip
		climbing = false
		_ladder_cool = 0.4
		_left_at = "top"
	elif p.y <= bottom + 0.01 and move.y < -0.1:
		climbing = false                    # feet on the floor
		_ladder_cool = 0.4
		_left_at = "bottom"
	vel = Vector3.ZERO
	grounded = true
	global_position = p
	model.animate(delta, PilotModel.WALK if absf(move.y) > 0.1 else PilotModel.IDLE, absf(move.y), _clock)
	return true


## Ground under p: the voxel floor inside the square, else the heightfield.
func _ground_y(p: Vector3) -> float:
	var g: float = terrain.ground_level_at(p.x, p.z)
	if terrain.has_method("platform_y"):
		var pf: float = terrain.platform_y(p)
		if pf > g:
			return pf
	if vox == null or not terrain.inside(p.x, p.z) or not terrain.hollow_at(p.x, p.z).is_empty():
		return g
	if not vox.ready_at(p):
		return g
	var f: float = vox.floor_below(p, 40.0)
	return g if f == -INF else f


## Underground: rock over his head (a tunnel or cave), not open sky.
func underground() -> bool:
	if vox == null or in_plane:
		return false
	var p := global_position
	return terrain.inside(p.x, p.z) and p.y < terrain.height_at(p.x, p.z) - 1.2


## Rock in the way at knee or chest height at p (a tunnel wall, a cut face).
func _wall_at(p: Vector3) -> bool:
	if vox == null or not terrain.inside(p.x, p.z) or not vox.ready_at(p):
		return false
	return vox.sdf_at(p + Vector3(0, 0.75, 0)) < -0.02 or vox.sdf_at(p + Vector3(0, 1.45, 0)) < -0.02


func _ready() -> void:
	model = PilotRig.new() if PilotRig.available() else PilotModel.new()
	model.name = "Pilot"
	add_child(model)
	model.build()


## Stand at `p`, facing `facing` (radians, 0 = -Z).
func _reset_interp() -> void:
	if is_inside_tree():
		reset_physics_interpolation.call_deferred()


func place(p: Vector3, facing: float) -> void:
	in_plane = false
	swimming = false
	global_position = Vector3(p.x, terrain.ground_level_at(p.x, p.z), p.z)
	if p.y < global_position.y - 1.2:
		global_position.y = p.y          # placed in a tunnel
	_reset_interp()
	yaw = facing
	look = Vector2(facing, -0.05)
	vel = Vector3.ZERO
	grounded = true
	rotation = Vector3(0, yaw, 0)


## One step. `move`: x right, y forward, each -1..1.
func step(delta: float, move: Vector2, run: bool, jump: bool) -> void:
	_clock += delta
	var p := global_position
	var fwd := Vector3(-sin(look.x), 0, -cos(look.x))
	var right := Vector3(cos(look.x), 0, -sin(look.x))
	var wish := fwd * move.y + right * move.x
	if wish.length() > 1.0:
		wish = wish.normalized()
	# A load in his arms: no running with anything heavy, and slower with more.
	if load_kg > 30.0:
		run = false
	if load_kg > 15.0:
		jump = false
	if in_plane and plane != null:
		_step_inside(delta, wish, run)
		return
	if wish.length() > 0.1 and _try_climb_in(global_position, wish):
		return
	if _climb(delta, move, wish):
		return
	var speed := RUN if run else WALK
	if swimming:
		speed = (SWIM_FAST if run else SWIM) * clampf(1.0 - load_kg / 60.0, 0.3, 1.0)
	speed *= clampf(1.0 - load_kg / 140.0, 0.45, 1.0)
	# Hard going: deep snow, steep slopes, wading.
	var surf: int = terrain.surface_at(p.x, p.z)
	if surf == 4:
		speed *= 0.55
	var ground: float = terrain.ground_level_at(p.x, p.z)
	var water: float = terrain.water_level_at(p.x, p.z)
	var depth := maxf(water - ground, 0.0) if water > -1.0e8 else 0.0
	if depth > 0.05 and not swimming:
		speed *= lerpf(0.8, 0.35, clampf(depth / 1.0, 0.0, 1.0))
	var n: Vector3 = terrain.normal_at(p.x, p.z)
	var downhill := Vector3(n.x, 0, n.z)
	if wish.length() > 0.01 and downhill.length() > 0.01:
		var up_amount := -wish.normalized().dot(downhill.normalized())   # > 0 going uphill
		var steep := 1.0 - n.y
		if up_amount > 0.0:
			speed *= clampf(1.0 - steep * 2.2 * up_amount, 0.15, 1.0)
	var target := wish * speed
	var accel := 10.0 if grounded else 2.0
	if swimming:
		accel = 2.5
	vel.x = lerpf(vel.x, target.x, clampf(accel * delta, 0.0, 1.0))
	vel.z = lerpf(vel.z, target.z, clampf(accel * delta, 0.0, 1.0))
	if grounded and jump and depth < 0.6:
		vel.y = JUMP_V
		grounded = false
		_fall_from = p.y
	if not grounded and not swimming:
		vel.y -= GRAVITY * delta
	var np := p + vel * delta
	# Too steep to stand: slide back down.
	var nn: Vector3 = terrain.normal_at(np.x, np.z)
	if nn.y < 0.62 and grounded and not underground():
		np.x += nn.x * 1.5 * delta
		np.z += nn.z * 1.5 * delta
	# Deep water: swim, head out of the water, until you can stand again.
	var nwater: float = terrain.water_level_at(np.x, np.z)
	var nground: float = terrain.ground_level_at(np.x, np.z)
	var deep: bool = nwater > -1.0e8 and nwater - nground > FLOAT_DEPTH - 0.05 and not terrain.lakes_frozen()
	if deep and not swimming and np.y < nwater - 0.6:
		swimming = true
		grounded = false
		_tell("swim", "Swimming. It's cold: get out quickly. (Hold run for a faster crawl.)")
	elif swimming and not deep:
		swimming = false
	if swimming:
		# Bob gently at the surface.
		var want_y := nwater - FLOAT_DEPTH + 0.04 * sin(_clock * 2.1)
		np.y = lerpf(np.y, want_y, clampf(4.0 * delta, 0.0, 1.0))
		vel.y = 0.0
		np = _collide(np)
		global_position = np
		var flat2 := Vector2(vel.x, vel.z)
		if first_person or aiming:
			yaw = look.x
		elif flat2.length() > 0.2:
			yaw = lerp_angle(yaw, atan2(-vel.x, -vel.z), clampf(6.0 * delta, 0.0, 1.0))
		rotation = Vector3(0, yaw, 0)
		model.animate(delta, PilotModel.WALK if flat2.length() > 0.2 else PilotModel.IDLE, flat2.length() * 0.6, _clock)
		if model.has_method("set_head_visible"):
			model.set_head_visible(not first_person)
		else:
			model.head_part.visible = not first_person
		_update_warmth(delta, 2.0, flat2.length())
		return
	if vox != null:
		var dir := Vector3(np.x - p.x, 0, np.z - p.z)
		if dir.length() > 0.0001:
			var probe := np + dir.normalized() * RADIUS
			if _wall_at(probe):
				# slide along the face: try each axis on its own
				var px := Vector3(np.x, np.y, p.z)
				var pz := Vector3(p.x, np.y, np.z)
				if not _wall_at(px + Vector3(signf(dir.x) * RADIUS, 0, 0)):
					np = px
					vel.z = 0.0
				elif not _wall_at(pz + Vector3(0, 0, signf(dir.z) * RADIUS)):
					np = pz
					vel.x = 0.0
				else:
					np.x = p.x
					np.z = p.z
					vel.x = 0.0
					vel.z = 0.0
		if vel.y > 0.0 and terrain.inside(np.x, np.z) and vox.ready_at(np) and vox.sdf_at(np + Vector3(0, 1.85, 0)) < 0.0:
			vel.y = 0.0          # head on the roof
	np = _collide(np)
	var g: float = _ground_y(np)
	if np.y <= g + 0.02 and vel.y <= 0.0:
		if not grounded:
			_land(maxf(_fall_from - g, 0.0), -vel.y)
		np.y = g
		vel.y = 0.0
		grounded = true
	elif grounded and np.y - g < 0.35:
		np.y = g       # follow the ground down small dips
	else:
		if grounded:
			_fall_from = p.y
		grounded = false
	global_position = np
	# Body faces where it is going (third person), or where you look (first).
	var flat := Vector2(vel.x, vel.z)
	if first_person or aiming:
		yaw = look.x
	elif flat.length() > 0.3:
		yaw = lerp_angle(yaw, atan2(-vel.x, -vel.z), clampf(10.0 * delta, 0.0, 1.0))
	rotation = Vector3(0, yaw, 0)
	var gait: int = PilotModel.IDLE
	if not grounded:
		gait = PilotModel.AIR
	elif flat.length() > 2.6:
		gait = PilotModel.RUN
	elif flat.length() > 0.25:
		gait = PilotModel.WALK
	model.animate(delta, gait, flat.length(), _clock)
	if model.has_method("set_head_visible"):
		model.set_head_visible(not first_person)
	else:
		model.head_part.visible = not first_person
	_footsteps(flat.length(), depth, np)
	_update_warmth(delta, depth, flat.length())


## Footsteps (DESIGN_NOTES 113): a step every stride, the sound picked by what
## is underfoot - gravel, tundra and moss, mud, snow, water, a floor.
const STEPS := "res://assets/sounds/steps/"
## How loud a walking step is (dB). Tune here.
const STEP_DB := -30.0
static var _step_cache := {}
var _steps: Array = []
var _stride := 0.0
var _step_rng := RandomNumberGenerator.new()


func _footsteps(speed: float, depth: float, p: Vector3) -> void:
	if not grounded or speed < 0.25:
		_stride = minf(_stride, 0.35)
		return
	_stride += speed * get_physics_process_delta_time()
	var stride_len := 1.35 if speed > 2.6 else 0.78
	if _stride < stride_len:
		return
	_stride = 0.0
	var kind := "soft"
	var surf: int = terrain.surface_at(p.x, p.z)
	var mud: float = terrain.mud_at(p.x, p.z) if terrain.has_method("mud_at") else 0.0
	if depth > 0.04:
		kind = "water"
	elif terrain.has_method("platform_y") and terrain.platform_y(p) > terrain.ground_level_at(p.x, p.z) + 0.05:
		kind = "hard"
	elif surf == 4 or surf == 5 or surf == 6 or Game.season == Game.WINTER:
		kind = "snow"
	elif mud > 0.35:
		kind = "mud"
	elif surf == 1 or surf == 3 or underground():
		kind = "gravel"
	play_step(kind, speed > 2.6)


func play_step(kind: String, running: bool) -> void:
	if _steps.is_empty():
		for i in range(2):
			var a := AudioStreamPlayer3D.new()
			a.unit_size = 2.5
			a.max_distance = 30.0
			a.position = Vector3(0, 0.1, 0)
			add_child(a)
			_steps.append(a)
	var take := "%s_%d.wav" % [kind, _step_rng.randi() % 4]
	if not _step_cache.has(take):
		var st: AudioStream = null
		if ResourceLoader.exists(STEPS + take):
			st = load(STEPS + take)
		if st == null:
			st = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(STEPS + take))
		_step_cache[take] = st
	var s: AudioStream = _step_cache[take]
	if s == null:
		return
	var pl: AudioStreamPlayer3D = _steps[0] if not (_steps[0] as AudioStreamPlayer3D).playing else _steps[1]
	pl.stream = s
	pl.pitch_scale = _step_rng.randf_range(0.9, 1.1)
	# quiet: you hear your own boots under everything else, not over it
	pl.volume_db = STEP_DB + (5.0 if running else 0.0) + _step_rng.randf_range(-2.0, 1.0)
	pl.play()


## Inside the DC-3: walk on its floor, kept between the walls; through the
## bulkhead doorway to the flight deck; out of the open cargo door.
func _step_inside(delta: float, wish: Vector3, run: bool) -> void:
	var xf: Transform3D = plane.global_transform
	var inv := xf.affine_inverse()
	var lp: Vector3 = inv * global_position
	var speed := (2.4 if run else WALK) * clampf(1.0 - load_kg / 140.0, 0.45, 1.0)
	var target := wish * speed
	vel.x = lerpf(vel.x, target.x, clampf(10.0 * delta, 0.0, 1.0))
	vel.z = lerpf(vel.z, target.z, clampf(10.0 * delta, 0.0, 1.0))
	vel.y = 0.0
	var lv: Vector3 = inv.basis * Vector3(vel.x, 0, vel.z)
	lv.y = 0.0
	var np := lp + lv * delta
	# Out of the cargo door, if it's open and you walk into it.
	var door_open: bool = plane.door_open.get("bay", false)
	var at_door: bool = np.z > Shape.DOOR_Z[0] + 0.25 and np.z < Shape.DOOR_Z[1] - 0.25
	var fy := Shape.cabin_floor(np.z)
	var hw := minf(Shape.inner_half_width(np.z, fy + 0.25), Shape.inner_half_width(np.z, fy + 1.5)) - RADIUS
	if door_open and at_door and np.x < -hw + 0.02 and lv.x < -0.2:
		_step_out(np)
		return
	# Through the bulkhead only by its doorway.
	var bz := Shape.BULKHEAD_Z
	if (lp.z >= bz) != (np.z >= bz) or absf(np.z - bz) < RADIUS:
		if absf(np.x) > Shape.DOORWAY_HALF - 0.12:
			if absf(np.z - bz) < RADIUS:
				np.z = bz + (RADIUS if lp.z >= bz else -RADIUS)
		else:
			np.x = clampf(np.x, -(Shape.DOORWAY_HALF - 0.12), Shape.DOORWAY_HALF - 0.12)
	np.z = clampf(np.z, Shape.FRONT_Z, Shape.AFT_Z - RADIUS)
	fy = Shape.cabin_floor(np.z)
	hw = minf(Shape.inner_half_width(np.z, fy + 0.25), Shape.inner_half_width(np.z, fy + 1.5)) - RADIUS
	# On the flight deck, between the seats once you're up by them.
	if np.z < -5.3:
		hw = minf(hw, 0.22)
	np.x = clampf(np.x, -maxf(hw, 0.05), maxf(hw, 0.05))
	np.y = fy
	global_position = xf * np
	grounded = true
	swimming = false
	if first_person or aiming:
		yaw = look.x
	elif Vector2(vel.x, vel.z).length() > 0.3:
		yaw = lerp_angle(yaw, atan2(-vel.x, -vel.z), clampf(10.0 * delta, 0.0, 1.0))
	rotation = Vector3(0, yaw, 0)
	var flat := Vector2(vel.x, vel.z)
	model.animate(delta, PilotModel.WALK if flat.length() > 0.25 else PilotModel.IDLE, flat.length(), _clock)
	# boots on the cabin floor
	_stride += flat.length() * delta
	if flat.length() > 0.25 and _stride > 0.78:
		_stride = 0.0
		play_step("hard", false)
	if model.has_method("set_head_visible"):
		model.set_head_visible(not first_person)
	else:
		model.head_part.visible = not first_person
	warm_in_cabin(delta, bool(plane.engine_running))


## Hop down from the cargo door to the ground beside it.
func _step_out(lp: Vector3) -> void:
	in_plane = false
	var out: Vector3 = plane.global_transform * Vector3(-2.05, 0.0, clampf(lp.z, Shape.DOOR_Z[0] + 0.4, Shape.DOOR_Z[1] - 0.4))
	var g: float = terrain.ground_level_at(out.x, out.z)
	var water: float = terrain.water_level_at(out.x, out.z)
	global_position = Vector3(out.x, maxf(g, water - FLOAT_DEPTH) if water > g else g, out.z)
	vel = Vector3.ZERO
	grounded = true


## Climb in at the open cargo door (walking into it from outside).
func _try_climb_in(p: Vector3, wish: Vector3) -> bool:
	if plane == null or plane.plane_type != "dc3" or not plane.door_open.get("bay", false):
		return false
	if plane.ground_speed > 1.0:
		return false
	var inv: Transform3D = plane.global_transform.affine_inverse()
	var lp: Vector3 = inv * p
	var lw: Vector3 = inv.basis * wish
	if lp.x < -2.6 or lp.x > -0.9 or lp.z < Shape.DOOR_Z[0] + 0.2 or lp.z > Shape.DOOR_Z[1] - 0.2 or lw.x < 0.3:
		return false
	in_plane = true
	var z := clampf(lp.z, Shape.DOOR_Z[0] + 0.4, Shape.DOOR_Z[1] - 0.4)
	global_position = plane.global_transform * Vector3(-0.55, Shape.cabin_floor(z), z)
	vel = Vector3.ZERO
	return true


## Put the walker inside the DC-3 at a spot in the plane's space (getting out of the seat).
func place_inside(local: Vector3, facing: float) -> void:
	in_plane = true
	swimming = false
	global_position = plane.global_transform * Vector3(local.x, Shape.cabin_floor(local.z), local.z)
	yaw = facing
	look = Vector2(facing, -0.05)
	vel = Vector3.ZERO
	grounded = true
	rotation = Vector3(0, yaw, 0)


func _land(drop: float, impact: float) -> void:
	if impact > 7.5:
		var hurt := clampf((impact - 7.5) / 6.0, 0.0, 1.0)
		health = maxf(health - hurt, 0.0)
		_tell_now("You land hard and hurt yourself." if health > 0.0 else "That fall was too far.")


## Push the body out of trees, boulders, buildings and the plane.
func _collide(p: Vector3) -> Vector3:
	# Trees: the trunk is solid.
	var tr: Dictionary = Flora.tree_near(terrain, p + Vector3(0, 1.0, 0))
	if not tr.is_empty():
		var base: Vector3 = tr["base"]
		var r: float = float(tr["trunk_r"]) + RADIUS
		var d := Vector2(p.x - base.x, p.z - base.z)
		if d.length() < r:
			d = d.normalized() * r if d.length() > 0.001 else Vector2(r, 0)
			p.x = base.x + d.x
			p.z = base.z + d.y
	# Walk-in buildings: their walls (the front is open across the door).
	for hb in terrain.hollows:
		var o: Vector3 = (hb["xf"] as Transform3D).origin
		if Vector2(p.x - o.x, p.z - o.z).length() > float(hb["r"]) + 1.0:
			continue
		p = _collide_hollow(p, hb)
	# Solid buildings: pushed out of the box itself, sliding along the wall
	# (a clearing alone - a camp, a dig, a drop zone - is open ground to walk).
	for sb in terrain.solids:
		var o2: Vector3 = (sb["xf"] as Transform3D).origin
		if Vector2(p.x - o2.x, p.z - o2.z).length() > float(sb["r"]) + RADIUS + 0.5:
			continue
		var l2: Vector3 = (sb["inv"] as Transform3D) * p
		var s2: Vector3 = sb["size"]
		if l2.y < -1.0 or l2.y > s2.y:
			continue
		var hx2 := s2.x * 0.5 + RADIUS
		var hz2 := s2.z * 0.5 + RADIUS
		if absf(l2.x) < hx2 and absf(l2.z) < hz2:
			# Out the nearest face.
			if hx2 - absf(l2.x) < hz2 - absf(l2.z):
				l2.x = hx2 * (1.0 if l2.x >= 0.0 else -1.0)
			else:
				l2.z = hz2 * (1.0 if l2.z >= 0.0 else -1.0)
			p = (sb["xf"] as Transform3D) * l2
	# Vehicles and machines (ground.gd movers): out of the box, along its side.
	if terrain.get("movers") != null:
		for mk in terrain.movers:
			var mv: Dictionary = terrain.movers[mk]
			var o3: Vector3 = (mv["xf"] as Transform3D).origin
			if Vector2(p.x - o3.x, p.z - o3.z).length() > float(mv["r"]) + RADIUS + 0.5:
				continue
			var l3: Vector3 = (mv["inv"] as Transform3D) * p
			var s3: Vector3 = mv["size"]
			if l3.y < -1.0 or l3.y > s3.y:
				continue
			var hx3 := s3.x * 0.5 + RADIUS
			var hz3 := s3.z * 0.5 + RADIUS
			if absf(l3.x) < hx3 and absf(l3.z) < hz3:
				if hx3 - absf(l3.x) < hz3 - absf(l3.z):
					l3.x = hx3 * (1.0 if l3.x >= 0.0 else -1.0)
				else:
					l3.z = hz3 * (1.0 if l3.z >= 0.0 else -1.0)
				p = (mv["xf"] as Transform3D) * l3
	# The plane: fuselage, and a wide berth round a turning propeller.
	if plane != null:
		var xf: Transform3D = plane.global_transform
		var lp := xf.affine_inverse() * p
		var feet := lp.y
		if plane.plane_type == "dc3":
			p = xf * _collide_dc3(lp)
			return p
		if lp.z > -2.1 and lp.z < 5.1 and feet < 0.9 and feet + 1.8 > -0.62:
			var w := _fuselage_half_width(lp.z) + RADIUS
			if absf(lp.x) < w:
				lp.x = w * (1.0 if lp.x >= 0.0 else -1.0)
		# The propeller (DESIGN_NOTES 81): close is a warning, the disc is death.
		if plane.engine_running or float(plane.rpm) > 200.0:
			_prop_check(xf, lp, Vector3(0, 0.05, -2.12), float(plane.prop_radius), feet)
		p = xf * lp
	# Other planes on the field (parked fleet, planes for sale): same hulls.
	if extra_planes.is_valid():
		for ep in extra_planes.call():
			if ep == null or not is_instance_valid(ep) or ep == plane:
				continue
			var exf: Transform3D = (ep as Node3D).global_transform
			if (exf.origin - p).length() > 22.0:
				continue
			var lp2: Vector3 = exf.affine_inverse() * p
			if String(ep.get("plane_type")) == "dc3":
				p = exf * _collide_dc3(lp2)
			elif lp2.z > -2.1 and lp2.z < 5.1 and lp2.y < 0.9 and lp2.y + 1.8 > -0.62:
				var w2 := _fuselage_half_width(lp2.z) + RADIUS
				if absf(lp2.x) < w2:
					lp2.x = w2 * (1.0 if lp2.x >= 0.0 else -1.0)
					p = exf * lp2
	return p


## The DC-3 from outside: its round body (at whatever height he is), the
## engine nacelles, and the propellers while they turn.
func _collide_dc3(lp: Vector3) -> Vector3:
	if lp.z > -7.7 and lp.z < 12.0:
		var w := 0.0
		for hy in [0.3, 1.0, 1.7]:
			w = maxf(w, Shape.inner_half_width(lp.z, lp.y + hy) + 0.06)
		w += RADIUS
		if w > RADIUS + 0.05 and absf(lp.x) < w:
			lp.x = w * (1.0 if lp.x >= 0.0 else -1.0)
	# Nacelles and the main gear under them.
	for sx in [-3.35, 3.35]:        # the nacelle with its gear under it
		if lp.z > -3.4 and lp.z < 0.6 and absf(lp.x - sx) < 0.75 + RADIUS:
			lp.x = sx + (0.75 + RADIUS) * (1.0 if lp.x >= sx else -1.0)
	var spinning := false
	for e in plane.engines():
		if e.running or e.rpm > 200.0:
			spinning = true
	if spinning:
		for sx in [-3.35, 3.35]:
			_prop_check(plane.global_transform, lp, Vector3(sx, 0.9, -3.55), float(plane.prop_radius), lp.y)
	return lp


## Walked into a turning propeller? `hub` in plane space, `feet` his feet's
## height in plane space (the body runs from there up 1.8 m).
signal prop_strike(at: Vector3)
var dead_by_prop := false
func _prop_check(xf: Transform3D, lp: Vector3, hub: Vector3, radius: float, feet: float) -> void:
	if dead_by_prop:
		return
	var cy := clampf(hub.y, feet, feet + 1.8)
	var rr := Vector2(lp.x - hub.x, cy - hub.y).length()
	var dz := lp.z - hub.z
	if absf(dz) < 0.2 + RADIUS and rr < radius + RADIUS * 0.4:
		dead_by_prop = true
		health = 0.0
		prop_strike.emit(xf * Vector3(lp.x, cy, hub.z))
	elif absf(dz) < 1.4 and rr < radius + 1.0:
		_tell("prop", "Stay clear of the propeller!")


## Keep out of a hollow building's walls: back, both sides, and the front
## either side of the door.
func _collide_hollow(p: Vector3, hb: Dictionary) -> Vector3:
	var inv: Transform3D = hb["inv"]
	var l: Vector3 = inv * p
	var sz: Vector3 = hb["size"]
	var hx := sz.x * 0.5
	var hz := sz.z * 0.5
	var dh: float = float(hb["door"]) * 0.5
	var r := RADIUS + 0.12
	if absf(l.x) > hx + r or absf(l.z) > hz + r:
		return p
	# Side walls.
	if absf(l.z) < hz + 0.1 and absf(absf(l.x) - hx) < r:
		l.x = signf(l.x) * (hx - r if absf(l.x) < hx else hx + r)
	# Back wall.
	if absf(l.x) < hx + 0.1 and absf(l.z - hz) < r:
		l.z = hz - r if l.z < hz else hz + r
	# Front wall beside the door.
	if absf(l.x) > dh and absf(l.x) < hx + 0.1 and absf(l.z + hz) < r:
		l.z = -hz + r if l.z > -hz else -hz - r
	return (hb["xf"] as Transform3D) * l


static func _fuselage_half_width(z: float) -> float:
	var st := [[-2.1, 0.34], [-1.92, 0.48], [-1.15, 0.54], [-0.45, 0.56], [1.10, 0.54], [1.65, 0.46], [3.20, 0.26], [5.10, 0.07]]
	for i in range(st.size() - 1):
		var a: float = st[i][0]
		var b: float = st[i + 1][0]
		if z >= a and z <= b:
			return lerpf(st[i][1], st[i + 1][1], (z - a) / (b - a))
	return 0.0


## Cold eats at you outside; moving keeps you a little warmer; water soaks you.
func _update_warmth(delta: float, depth: float, speed: float) -> void:
	var air_c: float = Game.sea_level_temp_k() - 273.15 - 0.0065 * global_position.y
	var night := 1.0 if (Game.time_of_day < 6.0 or Game.time_of_day > 21.0) else 0.0
	air_c -= 5.0 * night
	var clothing := 8.0          # a work jacket is good to about this many degrees
	var loss := clampf((clothing - air_c) / 30.0, -0.5, 1.5) * 0.002
	loss -= clampf(speed / RUN, 0.0, 1.0) * 0.0008
	if depth > 0.1:
		loss += 0.006 * clampf(depth, 0.0, 1.2)
	warmth = clampf(warmth - loss * delta * 10.0 / 10.0, 0.0, 1.0)
	if warmth < 0.3:
		_tell("cold", "You're getting cold. Get back in the plane or keep moving.")
	if warmth <= 0.0:
		health = maxf(health - 0.01 * delta, 0.0)


## Warm up in the cabin (faster with the engine and heater running).
func warm_in_cabin(delta: float, engine_on: bool) -> void:
	warmth = minf(warmth + (0.01 if engine_on else 0.003) * delta, 1.0)


## The camera for this frame.
var vehicle_cam := 0.0          # > 0: third person while driving a truck, this far back
var seat_tilt := Basis.IDENTITY  # the machine's pitch / roll while seated (main._seat_driver)


func camera_transform() -> Transform3D:
	var basis := Basis(Vector3.UP, look.x) * Basis(Vector3.RIGHT, look.y)
	# The walker moves on physics ticks (120 Hz); the camera runs every
	# frame. Follow where he's DRAWN (interpolated between ticks), not his
	# raw physics position, or the view steps and jitters at any frame rate
	# that isn't the tick rate.
	var gt: Transform3D = get_global_transform_interpolated() if is_inside_tree() else global_transform
	if first_person:
		var eye: Vector3 = gt * (model.eye_local() as Vector3)
		eye += Basis(Vector3.UP, look.x) * Vector3(0, 0, -0.04)
		if seat_tilt != Basis.IDENTITY:
			# in a seat: the view rolls and pitches with the cab (a rollover turns it over)
			var yb := Basis(Vector3.UP, yaw)
			basis = yb * seat_tilt * yb.inverse() * basis
			eye = gt * (model.eye_local() as Vector3) + basis * Vector3(0, 0, -0.04)
		return Transform3D(basis, eye)
	if underground():
		var eye2: Vector3 = gt * (model.eye_local() as Vector3)
		return Transform3D(basis, eye2)   # no room for a chase camera down here
	var target := gt.origin + Vector3(0, 1.55, 0)
	var pos := target + basis * Vector3(0.35, 0.15, cam_dist if not in_plane else 1.1)
	if vehicle_cam > 0.0:
		# driving a truck: a chase camera well back, over the whole rig
		target = gt.origin + Vector3(0, 1.2, 0)
		pos = target + basis * Vector3(0.0, vehicle_cam * 0.12, vehicle_cam)
	var floor_y: float = terrain.ground_level_at(pos.x, pos.z) + 0.3
	pos.y = maxf(pos.y, floor_y)
	return Transform3D(basis, pos)


## Near enough to the pilot's door (left side of the cabin) to get in. In the
## DC-3: up on the flight deck, by the seats.
func near_door() -> bool:
	if plane == null:
		return false
	var lp: Vector3 = plane.global_transform.affine_inverse() * global_position
	if plane.plane_type == "dc3":
		return in_plane and lp.z < -5.0
	var sp: Dictionary = plane.PlaneTypes.spec(plane.plane_type)
	if plane.plane_type != "wolverine" and sp.has("door"):
		var d: Vector3 = sp["door"]
		return Vector2(lp.x - d.x, lp.z - d.z).length() < 1.6
	return lp.x < 0.0 and lp.x > -2.6 and lp.z > -1.4 and lp.z < 1.2


func _tell(key: String, text: String) -> void:
	var last: float = _warned.get(key, -100.0)
	if _clock - last > 6.0:
		_warned[key] = _clock
		_tell_now(text)


func _tell_now(text: String) -> void:
	if notice.is_valid():
		notice.call(text)
