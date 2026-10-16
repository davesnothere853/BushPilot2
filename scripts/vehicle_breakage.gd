extends RefCounted
## VEHICLE BREAKAGE (DESIGN_NOTES 199) - the visible side of damage; the
## numbers (engine, body, running gear) stay in vehicle_damage.gd: works on any machine built from parts
## (truck_body's: every component its own node with meta "part"; doors, hood
## and tailgate on their pivots). Hits come in as a point and an impulse:
##   - panels DENT where they're struck (their mesh pushed in, normals redone)
##   - glass CRACKS (a spider web round the hit, cracked_glass shader), then
##     SHATTERS into falling shards
##   - lamps BUST OUT (the lens goes, shards fall, the bulb no longer lights)
##   - parts TEAR OFF when hit hard enough: they become physics bodies that
##     tumble, bounce and stay in the world (mirrors and trim first; bumpers,
##     doors, hood need a big hit; the cab and engine block never)
## explode() hits every part from one point, with a flash.
##
## Use: var brk := VehicleBreakage.new(vehicle_node)  then  brk.hit(p, impulse)
## (world space). The vehicle may implement part_detached(name) to drop its
## own references (pivots, bulbs).

const MeshKit = preload("res://scripts/meshkit.gd")
const CRACK_SHADER = preload("res://shaders/cracked_glass.gdshader")

## name prefix -> [kind, mass kg, tear-off impulse N*s] (first match wins).
## kind: "trim" light bits, "lamp", "panel" dents, "mech", "fixed" never tears off.
const RULES := [
	# the Super Cub (plane_body.gd, DESIGN_NOTES 212): fabric-covered surfaces dent and tear off,
	# struts and gear legs snap, the prop comes off in a prop strike
	["WingL", "panel", 45.0, 32000.0], ["WingR", "panel", 45.0, 32000.0], ["Flap", "panel", 6.0, 5000.0], ["Aileron", "panel", 5.0, 5000.0],
	["StrutFitting", "fixed", 1.0, 1e9], ["StrutFront", "mech", 6.0, 9000.0], ["StrutRear", "mech", 5.0, 8000.0], ["Jury", "trim", 1.0, 2500.0],
	["GearL", "mech", 14.0, 14000.0], ["GearR", "mech", 14.0, 14000.0], ["PropHub", "mech", 25.0, 9000.0],
	["Stabiliser", "panel", 10.0, 9000.0], ["Elevator", "panel", 5.0, 5000.0], ["Fin", "panel", 6.0, 9000.0], ["Rudder", "panel", 5.0, 5000.0],
	["TailWires", "trim", 0.5, 1500.0], ["TailGear", "mech", 4.0, 5000.0], ["TailWheel", "mech", 3.0, 5000.0],
	["DoorUpper", "panel", 4.0, 5500.0], ["DoorLower", "panel", 5.0, 6500.0], ["WindowL", "panel", 3.0, 5500.0], ["BaggageDoor", "panel", 3.0, 5000.0],
	["FuelCap", "trim", 0.3, 600.0], ["AirFilter", "trim", 0.5, 900.0], ["NoseBowl", "panel", 4.0, 7000.0], ["CowlPanel", "panel", 3.0, 5000.0], ["CowlHinge", "trim", 0.3, 3000.0],
	["Fuselage", "panel", 1.0, 1e9], ["CabinShell", "fixed", 1.0, 1e9], ["CenterSection", "panel", 1.0, 1e9], ["SideWindows", "panel", 1.0, 1e9],
	["Lights", "fixed", 1.0, 1e9], ["Cockpit", "fixed", 1.0, 1e9], ["Engine", "fixed", 1.0, 1e9], ["BaggageBay", "fixed", 1.0, 1e9],
	["Mirror", "trim", 3.0, 500.0], ["Antenna", "trim", 0.5, 150.0], ["Wipers", "trim", 1.0, 300.0],
	["Plate", "trim", 0.8, 300.0], ["Winch", "mech", 40.0, 12000.0], ["RearPlate", "trim", 0.8, 300.0], ["TowHooks", "trim", 2.0, 2500.0],
	["SideMarker", "lamp", 0.3, 350.0], ["TailLampLow", "lamp", 0.5, 600.0], ["ParkLamp", "lamp", 0.6, 600.0], ["TailLamps", "lamp", 2.0, 2500.0],
	["Headlamp", "lamp", 1.5, 1400.0], ["HeadlampBezel", "trim", 1.0, 1400.0],
	["TrimStrips", "trim", 1.5, 900.0], ["DripRails", "trim", 1.0, 1200.0], ["StakePockets", "fixed", 1.0, 1e9],
	["FuelDoor", "trim", 0.4, 500.0], ["Valance", "panel", 6.0, 2500.0], ["Grille", "trim", 5.0, 1800.0],
	["GrilleSurround", "trim", 4.0, 2200.0], ["FrontPanel", "panel", 12.0, 6000.0],
	["Bumper", "panel", 30.0, 7000.0], ["RearBumper", "panel", 28.0, 7000.0],
	["HoodPivot", "panel", 25.0, 6000.0], ["TailgatePivot", "panel", 20.0, 5000.0],
	["DoorLPivot", "panel", 32.0, 7000.0], ["DoorRPivot", "panel", 32.0, 7000.0],
	["Fender", "panel", 14.0, 11000.0], ["BedSide", "panel", 30.0, 16000.0], ["WheelLip", "panel", 2.0, 9000.0],
	["Roof", "panel", 1.0, 1e9], ["Pillars", "panel", 1.0, 1e9], ["Cab", "panel", 1.0, 1e9],
	["Windshield", "glass", 12.0, 1e9], ["BackGlass", "glass", 6.0, 1e9],
	["Battery", "mech", 20.0, 5000.0], ["AirCleaner", "mech", 3.0, 2500.0], ["ValveCover", "mech", 2.0, 4000.0],
	["Radiator", "mech", 12.0, 6000.0], ["Fan", "mech", 3.0, 4000.0], ["WasherBottle", "mech", 1.0, 1500.0],
	["Horn", "mech", 0.5, 1200.0], ["SpareTire", "mech", 30.0, 9000.0], ["Exhaust", "mech", 15.0, 9000.0],
	["EngineBlock", "fixed", 1.0, 1e9], ["FrameRails", "fixed", 1.0, 1e9], ["Suspension", "fixed", 1.0, 1e9],
	["Axle", "fixed", 1.0, 1e9], ["Wheel", "fixed", 1.0, 1e9],
	["TailgateLatches", "trim", 0.3, 800.0], ["DoorHinges", "fixed", 1.0, 1e9], ["Cowl", "trim", 3.0, 6000.0],
	["HoodLatch", "trim", 0.5, 3000.0], ["HoodHinge", "trim", 1.0, 6000.0], ["RadiatorSupport", "mech", 8.0, 12000.0],
	["FanShroud", "mech", 2.0, 4000.0], ["Alternator", "mech", 6.0, 7000.0], ["Distributor", "mech", 2.0, 6000.0],
	["SparkPlugWires", "trim", 0.3, 3000.0], ["Carburetor", "mech", 4.0, 9000.0], ["BatteryCables", "trim", 1.0, 5000.0],
	["WiperMotor", "mech", 2.0, 8000.0], ["HeaterHoses", "trim", 0.5, 5000.0], ["Pinstripes", "fixed", 1.0, 1e9],
]
const GLASS_CRACK := 150.0          # N*s on a pane: it cracks
const GLASS_SHATTER := 700.0        # (total) it shatters
const LAMP_BUST := 220.0

var veh: Node3D
var body: Node3D                    # the "Body" node the parts live under
var _hurt := {}                     # part path -> impulse taken so far
var _glass_hits := {}               # glass MeshInstance -> impulse taken
var _crack_mats := {}               # glass MeshInstance -> its cracked ShaderMaterial
var _groups := {}                   # mesh -> MeshKit.shared_groups (dents)
var broken_bulbs := {}              # bulb name -> true
var debris: Array = []              # what's come off (RigidBody3D)


func _init(v: Node3D) -> void:
	veh = v
	body = v.find_child("Body", true, false) as Node3D


static func rule(nm: String) -> Array:
	for r in RULES:
		if nm.begins_with(String(r[0])):
			return r
	return ["", "fixed", 10.0, 1e9]          # anything not listed stays on (cab structure, interior, frame)


## Every breakable thing on the vehicle now: part nodes and the pivots.
func parts() -> Array:
	var out: Array = []
	if body == null or not is_instance_valid(body):
		return out
	for c in body.get_children():
		if c is Node3D and (c as Node).has_meta("part"):
			out.append(c)
	for c in veh.find_children("*Pivot", "Node3D", true, false):
		if not out.has(c) and (c as Node).get_parent() != null and not String(c.name).begins_with("SteeringWheel"):
			out.append(c)
	return out


## A hit at world point p with impulse (N*s, the direction it pushes).
## radius: how far round it the damage spreads.
func hit(p: Vector3, impulse: Vector3, radius: float = 0.6) -> void:
	var mag := impulse.length()
	if mag < 1.0:
		return
	var dir := impulse / mag
	for part in parts():
		if not is_instance_valid(part) or (part as Node).get_parent() == null:
			continue
		var d := _distance_to(part as Node3D, p)
		if d > radius * 2.5:
			continue
		var share := mag * pow(clampf(1.0 - d / (radius * 2.5), 0.0, 1.0), 2.0)
		if share < 5.0:
			continue
		_damage_part(part as Node3D, p, dir, share, radius)


## Everything gets hit from one point (world): the closer, the harder.
func explode(center: Vector3, power: float = 40000.0) -> void:
	_flash(center, power)
	for part in parts():
		if not is_instance_valid(part):
			continue
		var c := _centre(part as Node3D)
		var off := c - center
		var d := maxf(off.length(), 0.3)
		var imp := power / (1.0 + d * d * 1.5)
		var dir := (off / d + Vector3(0, 0.6, 0)).normalized()
		_damage_part(part as Node3D, c - dir * 0.2, dir, imp * 0.6, 0.8)


func _damage_part(part: Node3D, p: Vector3, dir: Vector3, share: float, radius: float) -> void:
	var nm := String(part.name)
	var r := rule(nm)
	var kind: String = r[1]
	var key := str(part.get_path())
	_hurt[key] = float(_hurt.get(key, 0.0)) + share
	# glass panes inside this part (a part's "Glass" meshes, or the whole part)
	for mi in part.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.name).begins_with("Glass"):
			_glass(m, p, share)
		elif String(m.name).ends_with("Bulb") and share > LAMP_BUST:
			_bust_lamp(m, dir)
	if kind == "panel" or kind == "trim" or kind == "lamp":
		_dent(part, p, dir, share, radius)
	if float(_hurt[key]) > float(r[3]) and kind != "fixed":
		detach(part, dir * share * 0.35, p)


# ------------------------------------------------------------------------------
#  Dents: push the part's skin in round the hit
# ------------------------------------------------------------------------------
func _dent(part: Node3D, p: Vector3, dir: Vector3, share: float, radius: float) -> void:
	var depth := clampf(share / 26000.0, 0.0, 0.14)
	if depth < 0.004:
		return
	var R := radius * clampf(0.5 + share / 12000.0, 0.5, 1.4)
	for mi in part.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not (m.mesh is ArrayMesh) or String(m.name).begins_with("Glass") or String(m.name).ends_with("Bulb"):
			continue
		var am := m.mesh as ArrayMesh
		if am.get_surface_count() == 0:
			continue
		var inv := m.global_transform.affine_inverse()
		var lp := inv * p
		var ld := (inv.basis * dir).normalized()
		var arr := am.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var moved := false
		for i in range(verts.size()):
			var dd := verts[i].distance_to(lp)
			if dd < R:
				var f := 1.0 - dd / R
				verts[i] += ld * depth * f * f * (3.0 - 2.0 * f)
				moved = true
		if not moved:
			continue
		# redo the shading so the dent catches the light
		var face := PackedVector3Array()
		face.resize(verts.size())
		for i in range(0, verts.size() - 2, 3):
			var n := (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i])
			var old: Vector3 = (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array)[i]
			n = n.normalized() if n.length_squared() > 1e-14 else old
			if n.dot(old) < 0.0:
				n = -n
			face[i] = n
			face[i + 1] = n
			face[i + 2] = n
		if not _groups.has(am):
			_groups[am] = MeshKit.shared_groups(verts)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = MeshKit.smoothed(face, _groups[am], cos(deg_to_rad(40.0)))
		var mat := am.surface_get_material(0)
		am.clear_surfaces()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		if mat != null:
			am.surface_set_material(0, mat)


# ------------------------------------------------------------------------------
#  Glass: crack, then shatter
# ------------------------------------------------------------------------------
func _glass(m: MeshInstance3D, p: Vector3, share: float) -> void:
	if not m.visible:
		return
	var total := float(_glass_hits.get(m, 0.0)) + share
	_glass_hits[m] = total
	if total > GLASS_SHATTER:
		_shatter(m)
		return
	if total > GLASS_CRACK:
		var sm: ShaderMaterial = _crack_mats.get(m)
		if sm == null:
			sm = ShaderMaterial.new()
			sm.shader = CRACK_SHADER
			var old := m.material_override as StandardMaterial3D
			if old != null:
				sm.set_shader_parameter("tint", old.albedo_color)
			m.material_override = sm
			_crack_mats[m] = sm
			sm.set_shader_parameter("hits", 0)
		# up to 4 impact points each with its own web
		var n: int = int(sm.get_shader_parameter("hits"))
		if n < 4:
			sm.set_shader_parameter("hit%d" % n, m.global_transform.affine_inverse() * p)
			sm.set_shader_parameter("hits", n + 1)
		sm.set_shader_parameter("amount", clampf((total - GLASS_CRACK) / (GLASS_SHATTER - GLASS_CRACK) * 1.5 + 0.35, 0.35, 1.0))


func _shatter(m: MeshInstance3D) -> void:
	m.visible = false
	var aabb := m.global_transform * m.get_aabb()
	var count := clampi(int(aabb.size.length() * 14.0), 6, 40)
	for i in range(count):
		var at := aabb.position + Vector3(randf(), randf(), randf()) * aabb.size
		_shard(at, Vector3(randf_range(-1, 1), randf_range(0.5, 2.0), randf_range(-1, 1)) * 1.2, Color(0.75, 0.82, 0.85, 0.7), randf_range(0.03, 0.09))


func _bust_lamp(m: MeshInstance3D, dir: Vector3) -> void:
	if not m.visible:
		return
	m.visible = false
	broken_bulbs[String(m.name)] = true
	for i in range(5):
		_shard(m.global_position, (dir + Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1))) * 1.5, Color(0.9, 0.9, 0.88, 0.8), randf_range(0.02, 0.05))
	if veh.has_method("part_detached"):
		veh.part_detached(String(m.name))


func _shard(at: Vector3, vel: Vector3, col: Color, size: float) -> void:
	var rb := RigidBody3D.new()
	rb.mass = 0.05
	rb.collision_layer = 1 << 5
	rb.collision_mask = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size, 0.004, size * 0.7)
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(size, size * 0.8, 0.004)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic_specular = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.rotation = Vector3(PI * 0.5, 0, 0)
	rb.add_child(mi)
	_world_node().add_child(rb)
	rb.global_position = at
	rb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	# shards settle and go after a while (big pieces stay)
	rb.get_tree().create_timer(12.0).timeout.connect(func(): if is_instance_valid(rb): rb.queue_free())


# ------------------------------------------------------------------------------
#  Tear-off: the part becomes a physics body in the world
# ------------------------------------------------------------------------------
func detach(part: Node3D, impulse: Vector3, at: Vector3) -> RigidBody3D:
	if part == null or not is_instance_valid(part) or part.get_parent() == null:
		return null
	var nm := String(part.name)
	var r := rule(nm)
	var xf := part.global_transform
	var rb := RigidBody3D.new()
	rb.name = "Debris_" + nm
	rb.mass = float(r[2])
	_world_node().add_child(rb)
	rb.global_transform = xf
	part.get_parent().remove_child(part)
	rb.add_child(part)
	part.transform = Transform3D.IDENTITY
	# collision from the part's own meshes (convex hulls), centre of mass in the middle
	var aabb := AABB()
	var first := true
	for mi in part.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var rel := rb.global_transform.affine_inverse() * m.global_transform
		var cs := CollisionShape3D.new()
		cs.shape = m.mesh.create_convex_shape(true, true)
		cs.transform = rel
		rb.add_child(cs)
		var b := rel * m.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	if first:
		rb.queue_free()
		return null
	rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	rb.center_of_mass = aabb.get_center()
	rb.continuous_cd = true
	rb.collision_layer = 1 << 5
	rb.collision_mask = 1
	# (set the velocity itself: an impulse on a body just added used the wrong mass)
	var spd := clampf(impulse.length() / rb.mass, 0.0, 12.0)        # no rockets
	rb.linear_velocity = impulse.normalized() * spd + Vector3(0, 1.5, 0)
	rb.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3)) * clampf(spd / 6.0, 0.3, 1.5)
	debris.append(rb)
	if veh.has_method("part_detached"):
		veh.part_detached(nm)
	return rb


# ------------------------------------------------------------------------------
func _world_node() -> Node:
	var w: Node = veh.get_parent()
	return w if w != null else veh


func _centre(n: Node3D) -> Vector3:
	var aabb := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.global_transform * m.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	return aabb.get_center() if not first else n.global_position


func _distance_to(n: Node3D, p: Vector3) -> float:
	var best := 1e9
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.global_transform * m.get_aabb()
		var q := p.clamp(b.position, b.end)
		best = minf(best, q.distance_to(p))
	return best


func _flash(at: Vector3, power: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.3)
	l.light_energy = clampf(power / 4000.0, 2.0, 16.0)
	l.omni_range = 14.0
	_world_node().add_child(l)
	l.global_position = at + Vector3(0, 0.5, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.6)
	tw.tween_callback(l.queue_free)
	# a burst of smoke and sparks
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.amount = 80
	ps.lifetime = 2.2
	ps.explosiveness = 0.95
	ps.direction = Vector3.UP
	ps.spread = 180.0
	ps.initial_velocity_min = 3.0
	ps.initial_velocity_max = 9.0
	ps.gravity = Vector3(0, -2.0, 0)
	ps.damping_min = 2.0
	ps.damping_max = 4.0
	ps.scale_amount_min = 0.3
	ps.scale_amount_max = 1.1
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 8
	sm.rings = 4
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.2, 0.18, 0.16, 0.7)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = mm
	ps.mesh = sm
	_world_node().add_child(ps)
	ps.global_position = at
	ps.emitting = true
	ps.get_tree().create_timer(3.0).timeout.connect(func(): if is_instance_valid(ps): ps.queue_free())
