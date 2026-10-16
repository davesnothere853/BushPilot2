extends Node3D
## WINCH (DESIGN_NOTES 203): a bumper winch with a real cable. The cable is
## rope.gd (a verlet chain that sags, lies on the ground and goes taut); the
## winch pays it out as you walk the hook away, and reels it in under power.
## When it's taut the pull is real: the truck is pulled toward the anchor and
## whatever it's hooked to is pulled toward the truck (wheeled_body.pull) -
## a tree holds, a stuck truck comes out of the mud, a log drags. Two winches
## on one stuck truck add up (co-op double winching: main/net sum the pulls).
##
## States: "stowed" (hook on the fairlead), "carried" (in your hand),
## "hooked" (on a tree, a log or another vehicle). Reel: -1 in, 0 hold, +1 out.

const RopeScript = preload("res://scripts/rope.gd")

const MAX_LEN := 30.0             # m of cable on the drum
const LINE_PULL := 60000.0        # N: what the motor can pull (a 13,500 lb winch - more bite under load)
const BREAK := 130000.0           # N: the cable snaps
const STIFF := 450000.0           # N per metre of stretch: steel cable, taut and quick to load up
const SPEED_FREE := 0.35          # m/s reeling with no load
const SPEED_LOAD := 0.16          # m/s at full pull (it keeps winding under load)
const MIN_LEN := 3.0              # it stops reeling this far out (hooked to something)

var veh: Node3D                   # the truck it's on (has `body`: wheeled_body)
var fairlead := Vector3.ZERO      # where the cable leaves the bumper (vehicle frame)
var state := "stowed"
var reel := 0
var line_out := 0.6               # cable paid out, m
var tension := 0.0                # N, now
var hand := Vector3.ZERO          # the hook while carried (world)
var anchor: Node3D = null         # what it's hooked to (null: a fixed world point)
var anchor_local := Vector3.ZERO  # on the anchor (its frame), or the world point
var anchor_kind := ""             # "tree", "vehicle", "log", "ground"
var ground: Callable              # func(x, z) -> float
var on_snap: Callable             # func() - the cable broke
var _rope: MeshInstance3D
var _hook: MeshInstance3D


func setup(v: Node3D, fair_local: Vector3) -> void:
	veh = v
	fairlead = fair_local
	_rope = RopeScript.new()
	_rope.segments = 28
	_rope.radius = 0.006
	_rope.colour = Color(0.55, 0.56, 0.56)
	_rope.top_level = true
	add_child(_rope)
	var f := fair_world()
	_rope.ground = func(x: float, z: float) -> float: return float(ground.call(x, z)) if ground.is_valid() else 0.0
	_rope.length = line_out
	_rope.setup(f, f + Vector3(0, -0.3, 0))
	_hook = MeshInstance3D.new()
	var hm := TorusMesh.new()
	hm.inner_radius = 0.018
	hm.outer_radius = 0.035
	hm.rings = 12
	hm.ring_segments = 6
	_hook.mesh = hm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.12, 0.08)
	mat.roughness = 0.5
	_hook.material_override = mat
	_hook.top_level = true
	add_child(_hook)


func fair_world() -> Vector3:
	return veh.global_transform * fairlead


func end_world() -> Vector3:
	match state:
		"carried":
			return hand
		"hooked":
			if anchor != null and is_instance_valid(anchor):
				return anchor.global_transform * anchor_local
			return anchor_local
	return fair_world() + veh.global_transform.basis * Vector3(0, -0.08, -0.05)


## Take the hook off the bumper (on foot, at the front of the truck).
func take(at_hand: Vector3) -> String:
	if state != "stowed":
		return ""
	state = "carried"
	hand = at_hand
	line_out = maxf(fair_world().distance_to(at_hand) + 0.4, 0.8)
	return "Winch hook in hand: walk it out to a tree or a vehicle, E to hook it."


## Hook it: on a node (tree, log, vehicle) at a world point, or the ground.
func hook_to(node: Node3D, world_point: Vector3, kind: String) -> String:
	if state != "carried":
		return ""
	# a machine: the hook goes on its nearest winch point (shackle, tow hook,
	# hitch: DESIGN_NOTES 225), never just anywhere on the body
	if node != null and node.has_method("winch_points"):
		var near: Array = load("res://scripts/tow_points.gd").nearest(node.winch_points(), world_point, 100.0)
		if not near.is_empty():
			world_point = near[1]
	anchor = node
	anchor_kind = kind
	anchor_local = node.global_transform.affine_inverse() * world_point if node != null else world_point
	state = "hooked"
	line_out = clampf(maxf(line_out, fair_world().distance_to(world_point) + 0.3), 0.3, MAX_LEN)   # it starts slack
	return "Hooked to the %s. Winch in to pull (and out to give slack)." % kind


func unhook(at_hand: Vector3) -> String:
	if state != "hooked":
		return ""
	state = "carried"
	anchor = null
	hand = at_hand
	tension = 0.0
	return "Unhooked: the hook's in your hand."


## Put the hook back on the bumper: the drum winds the slack in.
func stow() -> String:
	if state == "stowed":
		return ""
	state = "stowed"
	anchor = null
	tension = 0.0
	return "Hook back on the bumper."


func set_reel(r: int) -> void:
	reel = clampi(r, -1, 1)


## Each physics step: the drum, the cable's tension and its pulls, the rope.
func step(dt: float) -> void:
	if veh == null or not is_instance_valid(veh):
		return
	var f := fair_world()
	var e := end_world()
	var d := f.distance_to(e)
	match state:
		"stowed":
			line_out = move_toward(line_out, 0.25, SPEED_FREE * 2.0 * dt)
			tension = 0.0
		"carried":
			# the drum free-spools as he walks it out, up to the end of the cable
			line_out = clampf(maxf(line_out, d + 0.3), 0.3, MAX_LEN)
			tension = 0.0
		"hooked":
			var stretch := d - line_out
			tension = clampf(stretch * STIFF, 0.0, BREAK * 1.2)
			if reel < 0:
				# reel in: slower the harder it pulls; stalls at the motor's limit
				var k := clampf(1.0 - tension / LINE_PULL, 0.0, 1.0)
				line_out = maxf(line_out - lerpf(SPEED_LOAD * 0.2, SPEED_FREE, k) * dt, MIN_LEN)
				if line_out <= MIN_LEN + 0.01:
					reel = 0                          # the operator stops it short of the bumper
			elif reel > 0:
				line_out = minf(line_out + SPEED_FREE * dt, MAX_LEN)
			if tension > 0.0:
				var dir := (e - f) / maxf(d, 0.01)
				var t := minf(tension, LINE_PULL * 1.25)   # the drum brake slips above this
				var vb = veh.get("body")
				if vb != null:
					vb.pull(dir * t, f)
				if anchor != null and is_instance_valid(anchor):
					var ab = anchor.get("body")
					if ab != null:
						ab.pull(-dir * t, e)
					elif anchor.has_method("winch_pull"):
						anchor.winch_pull(-dir * t, e, dt)
			if tension > BREAK:
				_snap()
	_rope.length = maxf(line_out, 0.25)
	# under load the cable straightens out: no sag once it's carrying the pull
	var want_taut := clampf(tension / 6000.0, 0.0, 1.0) if state == "hooked" else 0.0
	_rope.taut = lerpf(_rope.taut, want_taut, clampf(dt * 8.0, 0.0, 1.0))
	_rope.a_pin = f
	_rope.b_pin = end_world()
	_rope.b_pinned = true
	_rope.step(dt)
	_hook.global_position = _rope.end_b()


func _snap() -> void:
	state = "stowed"
	anchor = null
	tension = 0.0
	line_out = 0.4
	if on_snap.is_valid():
		on_snap.call()


## For the HUD / net.
func status() -> String:
	match state:
		"carried":
			return "Winch hook in hand (%.0f m out)." % line_out
		"hooked":
			return "Winch: hooked to the %s, %.0f m out, pulling %.1f t." % [anchor_kind, line_out, tension / 9810.0]
	return ""


func net_state() -> Dictionary:
	return {"s": state, "e": end_world(), "l": line_out, "t": tension}
