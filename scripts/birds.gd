extends Node3D
## Birds over the square and bird strikes (DESIGN_NOTES 82).
## Flocks sit on the ground (the pond shore, the strip edge, the wet flats)
## and flush when something comes at them - a plane rolling or flying at
## them, a truck, a walker. They don't get out of the way instantly: a
## take-off roll through a flock of gulls is the classic strike. Geese fly
## Vs between the pond and the flats; a hawk circles high.
## A strike: the bird inside the plane's hull this frame. Damage by closing
## speed and where it hits - the prop / engine, the windscreen (cracks),
## a wing's leading edge, the fuselage. Feathers, blood on the plane, and a
## dead bird falls out of the sky.

const MeshKit = preload("res://scripts/meshkit.gd")

## kind: [count, body colour, wing colour, size m, speed m/s, cruise agl m, mass factor]
const KINDS := {
	"goose": [11, Color(0.42, 0.36, 0.28), Color(0.30, 0.27, 0.22), 0.9, 17.0, 55.0, 1.0],
	"gull": [9, Color(0.92, 0.92, 0.9), Color(0.62, 0.65, 0.68), 0.6, 12.0, 25.0, 0.45],
	"raven": [5, Color(0.07, 0.07, 0.09), Color(0.05, 0.05, 0.07), 0.55, 11.0, 30.0, 0.4],
	"hawk": [1, Color(0.45, 0.32, 0.2), Color(0.35, 0.25, 0.16), 0.75, 9.0, 120.0, 0.6],
}

var terrain: RefCounted
var plane: Node3D
var plane_ref: Callable             # func() -> the plane you're flying (it can change)
var walker: Node3D
var vehicles: Callable              # func() -> Array of Node3D (trucks, machines) that scare birds
var gore: Node3D                    # gore.gd: feathers, splats on the plane
var hud: Control
var strikes := 0                    # for tests
var flocks: Array = []              # {kind, state, spot, target, t, birds: [{p, v, phase, alive, off}]}
var _mm := {}                       # kind -> [MultiMesh up, down, folded]
var _corpses: Array = []            # [node, vel, landed]
var _threat_t := 0.0
var _spots: Array = []              # where flocks land


func setup() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # flocks move per frame
	var sp: Vector3 = terrain.strips[0]["pos"] if terrain.strips.size() > 0 else Vector3.ZERO
	_spots = [
		Vector3(-72.0, 0, 105.0),                 # pond shore
		Vector3(-24.0, 0, 104.0),                 # the wet flats
		sp + Vector3(30.0, 0, 16.0),              # strip edge
		sp + Vector3(-70.0, 0, -18.0),
		Vector3(60.0, 0, 40.0),                   # the open field
		Vector3(-40.0, 0, -60.0),
	]
	for kind in KINDS.keys():
		_build_meshes(kind)
	_add_flock("goose", 0, false)
	_add_flock("gull", 2, false)
	_add_flock("raven", 3, false)
	_add_flock("hawk", 4, true)


func _add_flock(kind: String, spot_i: int, airborne: bool) -> void:
	var spec: Array = KINDS[kind]
	var f := {"kind": kind, "state": "air" if airborne else "ground", "spot": spot_i,
		"target": _spots[spot_i], "t": randf_range(60.0, 140.0), "birds": [], "circle": randf() * TAU}
	for i in range(int(spec[0])):
		var off := Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0))
		var p: Vector3 = _spots[spot_i] + off
		p.y = _ground(p) + (float(spec[5]) if airborne else 0.0)
		(f["birds"] as Array).append({"p": p, "v": Vector3.ZERO, "phase": randf() * TAU, "alive": true,
			"off": off, "yaw": randf() * TAU, "slot": i})
	flocks.append(f)


func _ground(p: Vector3) -> float:
	var h: float = terrain.height_at(p.x, p.z)
	var wl: float = terrain.water_level_at(p.x, p.z)
	return maxf(h, wl) if wl > -1.0e8 else h


# ------------------------------------------------------------------------------
#  Meshes: one MultiMesh per kind and wing pose (up, down, folded)
# ------------------------------------------------------------------------------
func _build_meshes(kind: String) -> void:
	var spec: Array = KINDS[kind]
	var s: float = spec[3]
	var body: Color = spec[1]
	var wing: Color = spec[2]
	var mms: Array = []
	for pose in range(3):
		var k := MeshKit.new()
		k.box_at(Vector3(0, 0, 0), Vector3(0.22, 0.2, 0.62) * s, body)                   # body
		k.box_at(Vector3(0, 0.02, 0.38) * s, Vector3(0.18, 0.06, 0.2) * s, wing)          # tail
		var neck_c := Color(0.05, 0.05, 0.05) if kind == "goose" else body
		var neck_len := 0.32 if kind == "goose" else 0.12
		k.box_at(Vector3(0, 0.08, -0.31 - neck_len * 0.5) * s, Vector3(0.08, 0.08, neck_len) * s, neck_c)
		k.box_at(Vector3(0, 0.1, -0.36 - neck_len) * s, Vector3(0.11, 0.11, 0.14) * s, neck_c)      # head
		var beak := Color(0.95, 0.75, 0.2) if kind == "gull" else Color(0.1, 0.1, 0.1)
		k.box_at(Vector3(0, 0.08, -0.48 - neck_len) * s, Vector3(0.04, 0.04, 0.1) * s, beak)
		if kind == "goose":
			k.box_at(Vector3(0, 0.1, -0.36 - neck_len) * s, Vector3(0.115, 0.05, 0.06) * s, Color(0.95, 0.95, 0.92))   # chinstrap
		var span := 1.0 if kind != "hawk" else 1.2
		for sx in [-1.0, 1.0]:
			var root := Vector3(sx * 0.1, 0.05, -0.05) * s
			var tip: Vector3
			match pose:
				0:
					tip = Vector3(sx * 0.55 * span, 0.35, 0.05) * s
				1:
					tip = Vector3(sx * 0.55 * span, -0.3, 0.05) * s
				_:
					tip = Vector3(sx * 0.13, 0.08, 0.3) * s
			var c1 := root + Vector3(0, 0, 0.22 * s)
			var c2 := tip + Vector3(0, 0, 0.12 * s)
			k.quad(root, tip, c2, c1, wing, Vector3.UP)
			k.quad(root, c1, c2, tip, wing.darkened(0.15), Vector3.DOWN)
		if pose == 2:
			for lx in [-0.05, 0.05]:
				k.box_at(Vector3(lx, -0.17, 0.02) * s, Vector3(0.02, 0.16, 0.02) * s, Color(0.85, 0.5, 0.15) if kind != "raven" else Color(0.1, 0.1, 0.1))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = k.commit()
		mm.instance_count = int(spec[0])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = MeshKit.material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		mms.append(mm)
	_mm[kind] = mms


# ------------------------------------------------------------------------------
#  Behaviour
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if terrain == null:
		return
	if plane_ref.is_valid():
		plane = plane_ref.call()
	delta = minf(delta, 0.05)
	_threat_t -= delta
	var check := _threat_t <= 0.0
	if check:
		_threat_t = 0.2
	# (DESIGN_NOTES 171) a flock sitting on the ground far from the camera
	# does nothing anyone can see: skip its steps and its drawing (~0.4 ms)
	var cam := get_viewport().get_camera_3d()
	var cp: Vector3 = cam.global_position if cam != null else Vector3.INF
	_far.clear()
	for fi in range(flocks.size()):
		var f: Dictionary = flocks[fi]
		var bl: Array = f["birds"]
		if not bl.is_empty() and String(f["state"]) == "ground" and cp != Vector3.INF \
				and (bl[0]["p"] as Vector3).distance_squared_to(cp) > 1200.0 * 1200.0 and _drawn.has(fi):
			_far[fi] = true
			continue
		_step_flock(f, delta, check)
	_strikes()
	_draw_birds()
	_step_corpses(delta)


## Is something coming at this spot? Returns the threat position or INF.
func _threat(p: Vector3) -> Vector3:
	if plane != null:
		var pp: Vector3 = plane.global_position
		var d := pp.distance_to(p)
		var spd: float = (plane.get("vel") as Vector3).length() if plane.get("vel") != null else 0.0
		if d < 25.0 and bool(plane.get("engine_running")):
			return pp
		if spd > 4.0 and d < 40.0 + spd * 1.2:
			var to: Vector3 = (p - pp).normalized()
			if (plane.get("vel") as Vector3).normalized().dot(to) > 0.6:
				return pp
	if walker != null and walker.is_inside_tree() and walker.visible:
		if walker.global_position.distance_to(p) < 11.0:
			return walker.global_position
	if vehicles.is_valid():
		for v in vehicles.call():
			if v != null and is_instance_valid(v) and (v as Node3D).global_position.distance_to(p) < 22.0:
				return (v as Node3D).global_position
	return Vector3.INF


func _step_flock(f: Dictionary, dt: float, check: bool) -> void:
	var kind: String = f["kind"]
	var spec: Array = KINDS[kind]
	var speed: float = spec[4]
	var cruise: float = spec[5]
	f["t"] = float(f["t"]) - dt
	var centre := Vector3.ZERO
	var n := 0
	for b in f["birds"]:
		if b["alive"]:
			centre += b["p"]
			n += 1
	if n == 0:
		return
	centre /= float(n)
	match String(f["state"]):
		"ground":
			if check:
				var th := _threat(centre)
				if th != Vector3.INF:
					_flush(f, th)
					return
			if float(f["t"]) <= 0.0 and kind != "hawk":
				_flush(f, centre + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
				return
			for b in f["birds"]:
				if not b["alive"]:
					continue
				var home: Vector3 = (f["target"] as Vector3) + (b["off"] as Vector3)
				var p: Vector3 = b["p"]
				# pecking about: little walks toward a wandering spot
				if randf() < dt * 0.4:
					b["off"] = (b["off"] as Vector3) + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
					b["off"] = (b["off"] as Vector3).limit_length(5.0)
				var to := home - p
				to.y = 0.0
				if to.length() > 0.05:
					p += to.normalized() * minf(to.length(), 0.6 * dt)
					b["yaw"] = atan2(-to.x, -to.z)
				p.y = _ground(p)
				b["p"] = p
				b["v"] = Vector3.ZERO
				b["phase"] = 0.0
		"flush":
			# straight up and away, wings going hard
			for b in f["birds"]:
				if not b["alive"]:
					continue
				var v: Vector3 = b["v"]
				v.y = minf(v.y + 9.0 * dt, speed * 0.6)
				b["v"] = v.limit_length(speed)
				b["p"] = (b["p"] as Vector3) + (b["v"] as Vector3) * dt
				b["phase"] = float(b["phase"]) + dt * 22.0
			if float(f["t"]) <= 0.0:
				f["state"] = "air"
				var ns: int = (int(f["spot"]) + 1 + randi() % (_spots.size() - 1)) % _spots.size()
				f["spot"] = ns
				f["target"] = _spots[ns]
				f["t"] = randf_range(25.0, 60.0)
		"air", "land":
			var tgt: Vector3 = f["target"]
			var landing := String(f["state"]) == "land"
			if kind == "hawk":
				f["circle"] = float(f["circle"]) + dt * 0.12
				tgt = Vector3(0, 0, 0) + Vector3(cos(float(f["circle"])), 0, sin(float(f["circle"]))) * 90.0
			var gy := _ground(tgt)
			var goal_alt := gy + (0.0 if landing else cruise)
			if not landing and kind != "hawk":
				if Vector2(centre.x - tgt.x, centre.z - tgt.z).length() < 30.0 and float(f["t"]) <= 0.0:
					f["state"] = "land"
			var lead: Vector3 = Vector3(tgt.x, goal_alt, tgt.z)
			for b in f["birds"]:
				if not b["alive"]:
					continue
				var p: Vector3 = b["p"]
				var slot: int = b["slot"]
				var want := lead
				if kind == "goose" and not landing:
					# a V behind the leader
					var fwd := (lead - centre)
					fwd.y = 0.0
					fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
					var side := fwd.cross(Vector3.UP)
					var rank := float((slot + 1) / 2)
					want = lead - fwd * rank * 3.0 + side * (rank * 2.2 * (1.0 if slot % 2 == 0 else -1.0))
				else:
					want += (b["off"] as Vector3) * (1.0 if landing else 2.0)
				var to: Vector3 = want - p
				var desired := to.normalized() * speed * (clampf(to.length() / 12.0, 0.3, 1.0) if landing else 1.0)
				var v: Vector3 = (b["v"] as Vector3).lerp(desired, clampf(1.5 * dt, 0.0, 1.0))
				p += v * dt
				var floor_y := _ground(p) + (0.0 if landing else 3.0)
				p.y = maxf(p.y, floor_y)
				b["p"] = p
				b["v"] = v
				if v.length() > 0.5:
					b["yaw"] = atan2(-v.x, -v.z)
				b["phase"] = float(b["phase"]) + dt * (14.0 if v.y > 0.5 or landing else (4.0 if kind == "hawk" else 9.0))
			if landing:
				var down := 0
				for b in f["birds"]:
					if b["alive"] and absf((b["p"] as Vector3).y - _ground(b["p"])) < 0.15:
						down += 1
				if down >= n:
					f["state"] = "ground"
					f["t"] = randf_range(80.0, 200.0)
					for b in f["birds"]:
						var o: Vector3 = (b["p"] as Vector3) - tgt
						o.y = 0.0
						b["off"] = o


func _flush(f: Dictionary, threat: Vector3) -> void:
	f["state"] = "flush"
	f["t"] = 3.5
	var spec: Array = KINDS[f["kind"]]
	for b in f["birds"]:
		var away: Vector3 = (b["p"] as Vector3) - threat
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
		# they scatter, not all quite away (and a slow reaction for some)
		away = away.rotated(Vector3.UP, randf_range(-1.0, 1.0))
		b["v"] = away * float(spec[4]) * randf_range(0.3, 0.7) + Vector3.UP * randf_range(0.5, 3.0)


# ------------------------------------------------------------------------------
#  Strikes
# ------------------------------------------------------------------------------
func _strikes() -> void:
	if plane == null:
		return
	var pv: Vector3 = plane.get("vel") if plane.get("vel") != null else Vector3.ZERO
	if pv.length() < 6.0:
		return
	var xf: Transform3D = plane.global_transform
	var inv := xf.affine_inverse()
	var span: float = float(plane.get("wing_span")) if plane.get("wing_span") != null else 11.0
	var dc3: bool = String(plane.get("plane_type")) == "dc3"
	for f in flocks:
		if String(f["state"]) == "ground" and pv.length() < 6.0:
			continue
		for b in f["birds"]:
			if not b["alive"]:
				continue
			var p: Vector3 = b["p"]
			if p.distance_to(xf.origin) > span:
				continue
			var lp: Vector3 = inv * (p + Vector3(0, 0.1, 0))
			var where := _hit_zone(lp, span, dc3)
			if where != "":
				_strike(f, b, where, lp, pv - (b["v"] as Vector3))


## Where on the plane a bird at plane-space `lp` is, or "".
func _hit_zone(lp: Vector3, span: float, dc3: bool) -> String:
	var prop_r: float = float(plane.get("prop_radius")) if plane.get("prop_radius") != null else 1.0
	var hubs := [Vector3(-3.35, 0.9, -3.55), Vector3(3.35, 0.9, -3.55)] if dc3 else [Vector3(0, 0.05, -2.12)]
	for h in hubs:
		if absf(lp.z - h.z) < 0.7 and Vector2(lp.x - h.x, lp.y - h.y).length() < prop_r + 0.2:
			return "prop"
	if dc3:
		if absf(lp.x) < 1.6 and lp.z > -7.5 and lp.z < 12.0 and lp.y > -1.5 and lp.y < 1.8:
			return "windscreen" if lp.z < -5.0 and lp.y > 0.3 else "fuselage"
		if absf(lp.x) < span * 0.5 and absf(lp.y - 0.0) < 0.8 and lp.z > -3.0 and lp.z < 0.6:
			return "wing_l" if lp.x < 0.0 else "wing_r"
		return ""
	if absf(lp.x) < 0.75 and lp.z > -2.2 and lp.z < 5.0 and lp.y > -1.0 and lp.y < 1.1:
		if lp.z < -0.4 and lp.z > -1.6 and lp.y > 0.25:
			return "windscreen"
		return "fuselage"
	if absf(lp.x) < span * 0.5 and lp.y > 0.8 and lp.y < 1.7 and lp.z > -1.2 and lp.z < 0.6:
		return "wing_l" if lp.x < 0.0 else "wing_r"
	return ""


func _strike(f: Dictionary, b: Dictionary, where: String, lp: Vector3, rel_v: Vector3) -> void:
	b["alive"] = false
	strikes += 1
	var spec: Array = KINDS[f["kind"]]
	var v := rel_v.length()
	var sev := clampf(pow(v / 40.0, 2.0) * float(spec[6]), 0.02, 1.2)
	var xf: Transform3D = plane.global_transform
	var at: Vector3 = xf * lp
	var name: String = String(f["kind"])
	var msg := ""
	match where:
		"prop":
			plane.hurt("prop", 0.25 * sev)
			msg = "Bird strike - a %s went through the prop. Check the engine." % name
		"windscreen":
			plane.hurt("fuselage", 0.08 * sev)
			msg = "Bird strike on the windscreen - %s." % ("it's cracked" if sev < 0.6 else "it's starred right across")
		"wing_l", "wing_r":
			plane.hurt(where, 0.18 * sev)
			msg = "Bird strike on the %s wing's leading edge." % ("left" if where == "wing_l" else "right")
		_:
			plane.hurt("fuselage", 0.06 * sev)
			msg = "Bird strike - you hit a %s." % name
	if gore != null:
		gore.feathers(at, spec[2], -rel_v.normalized() * 2.0)
		var nrm: Vector3 = xf.basis * (Vector3(0, 0.6, -1).normalized() if where == "windscreen" else (Vector3.FORWARD if where != "fuselage" else Vector3(signf(lp.x) if absf(lp.x) > 0.2 else 0.0, 0.4, -1).normalized()))
		gore.plane_splat(plane, at, nrm, 0.5 + 0.5 * sev, randi() % 3)
		if where == "windscreen":
			gore.plane_splat(plane, at + nrm * 0.01, nrm, 0.6 + 0.6 * sev, 4)
	if hud != null and hud.has_method("push_message"):
		hud.push_message(msg, 6.0)
	# the bird falls out of the sky
	var k := MeshKit.new()
	var s: float = spec[3]
	k.box_at(Vector3.ZERO, Vector3(0.22, 0.2, 0.6) * s, spec[1])
	k.box_at(Vector3(0.25, 0, 0) * s, Vector3(0.4, 0.03, 0.2) * s, spec[2])
	k.box_at(Vector3(-0.2, 0.05, 0.1) * s, Vector3(0.3, 0.03, 0.18) * s, spec[2])
	k.box_at(Vector3(0.05, 0.11, 0.05) * s, Vector3(0.12, 0.01, 0.2) * s, Color(0.45, 0.02, 0.02))
	var c := k.instance("DeadBird")
	add_child(c)
	c.global_position = at
	_corpses.append([c, plane.get("vel") * 0.3 + Vector3(randf_range(-2, 2), 2.0, randf_range(-2, 2)), false])


func _step_corpses(dt: float) -> void:
	for cp in _corpses:
		if cp[2]:
			continue
		var n: Node3D = cp[0]
		var v: Vector3 = cp[1]
		v.y -= 9.8 * dt
		v *= 1.0 - 0.3 * dt
		n.global_position += v * dt
		n.rotate_x(dt * 6.0)
		var g := _ground(n.global_position)
		if n.global_position.y <= g + 0.05:
			n.global_position.y = g + 0.05
			n.rotation = Vector3(0, randf() * TAU, PI * 0.5 * signf(randf() - 0.5))
			cp[2] = true
		cp[1] = v
	while _corpses.size() > 30:
		var old: Array = _corpses.pop_front()
		(old[0] as Node).queue_free()


var _far := {}                      # flocks skipped this frame (far and sitting)
var _drawn := {}                    # flocks drawn at least once
func _draw_birds() -> void:
	for fi in range(flocks.size()):
		var f: Dictionary = flocks[fi]
		if _far.has(fi):
			continue
		_drawn[fi] = true
		var kind: String = f["kind"]
		var mms: Array = _mm[kind]
		var i := 0
		for b in f["birds"]:
			var pose := 2
			if b["alive"] and String(f["state"]) != "ground":
				pose = 0 if sin(float(b["phase"])) > 0.0 else 1
				if kind == "hawk" and fmod(float(b["phase"]), 12.0) > 3.0:
					pose = 0        # soaring: wings held up a bit
			var bank := 0.0
			var xf := Transform3D(Basis(Vector3.UP, float(b["yaw"])) * Basis(Vector3.FORWARD, bank), b["p"])
			for k in range(3):
				var mm: MultiMesh = mms[k]
				if b["alive"] and k == pose:
					mm.set_instance_transform(i, xf)
				else:
					mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -1000, 0)))
			i += 1


## How many birds are on the ground / flying (tests).
func counts() -> Array:
	var g := 0
	var a := 0
	for f in flocks:
		for b in f["birds"]:
			if not b["alive"]:
				continue
			if String(f["state"]) == "ground":
				g += 1
			else:
				a += 1
	return [g, a]
