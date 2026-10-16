extends Node3D
## What the wheels and tracks throw up and carry away (DESIGN_NOTES 108, 109):
##   dust   off dry ground as you drive (red on the Outback, grey-brown up north)
##   spray  clods and slop flung back out of mud, worst when the tyres spin
##   muck   mud caked on the wheels, lower body and undercarriage, building up
##          the more you drive in it; rain and deep water wash it off slowly
## The planes have their own dust (ground_fx.gd).

const Fx = preload("res://scripts/fx.gd")
const MUCK_SHADER = preload("res://shaders/muck.gdshader")

var terrain: RefCounted
var vehicles: Callable           # () -> Array of Node3D (anything you can drive)
var _st := {}                    # instance id -> {dust: [2], spray: [2], last, muck, mat, scan}


func _process(delta: float) -> void:
	if not vehicles.is_valid() or terrain == null or delta <= 0.0:
		return
	var outback: bool = Game.outback()
	var damp: bool = Game.weather == 2 or (not outback and (Game.season == Game.WINTER or Game.season == Game.SPRING))
	var seen := {}
	for v in vehicles.call():
		var n := v as Node3D
		if n == null or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var id := n.get_instance_id()
		seen[id] = true
		if not _st.has(id):
			var mm := ShaderMaterial.new()
			mm.shader = MUCK_SHADER
			var tm := ShaderMaterial.new()
			tm.shader = MUCK_SHADER
			tm.set_shader_parameter("spin_mode", true)
			_st[id] = {"dust": [_dust(), _dust()], "spray": [_spray(), _spray()], "last": n.global_position, "muck": 0.0, "mat": mm, "tmat": tm, "scan": 0.0}
		var e: Dictionary = _st[id]
		var pos := n.global_position
		var speed := (pos - (e["last"] as Vector3)).length() / delta
		e["last"] = pos
		var bx := n.global_transform.basis
		var half := _half_size(n)
		# what it's driving in
		var src: Object = n.get("body") if n.get("body") != null else n
		var mud: float = float(src.get("mud_now")) if src.get("mud_now") != null else 0.0
		var spin: float = float(src.get("spin_now")) if src.get("spin_now") != null else 0.0
		var ground: float = terrain.ground_level_at(pos.x, pos.z)
		var in_water: bool = terrain.has_method("water_level_at") and float(terrain.water_level_at(pos.x, pos.z)) > ground + 0.25
		var moving := clampf((speed - 1.0) / 10.0, 0.0, 1.0)
		var dust_amt := 0.0 if (damp or mud > 0.12 or in_water) else clampf((speed - 1.5) / 12.0, 0.0, 1.0) * (1.0 if outback else 0.35)
		var spray_amt := clampf(mud * 1.4 - 0.15, 0.0, 1.0) * clampf(moving + spin * 1.2, 0.0, 1.0)
		var dcol := Color(0.78, 0.46, 0.29) if outback else Color(0.62, 0.56, 0.46)
		for s in range(2):
			var local := Vector3((-1.0 if s == 0 else 1.0) * half.x * 0.85, 0.0, half.y * 0.8)
			var wp := pos + bx * local
			var g: float = terrain.ground_level_at(wp.x, wp.z)
			var d: CPUParticles3D = e["dust"][s]
			d.global_position = Vector3(wp.x, g + 0.25, wp.z)
			d.emitting = dust_amt > 0.05 and absf(wp.y - g) < 2.5
			d.color = Color(dcol.r, dcol.g, dcol.b, dust_amt)
			var sp: CPUParticles3D = e["spray"][s]
			sp.global_position = Vector3(wp.x, g + 0.3, wp.z)
			sp.emitting = spray_amt > 0.05 and absf(wp.y - g) < 2.5
			sp.direction = bx * Vector3(0.0, 1.2, 1.0 if speed >= 0.0 else -1.0)
			sp.initial_velocity_max = 2.5 + 5.0 * maxf(spin, moving)
			sp.color = Color(0.24, 0.18, 0.12, clampf(0.4 + spray_amt, 0.0, 1.0))
		# muck builds up in mud, washes off slowly in rain or deep water
		var mk: float = e["muck"]
		mk += mud * (0.02 + 0.06 * moving + 0.08 * spin) * delta
		if in_water:
			mk -= 0.05 * delta
		elif Game.weather == 2:
			mk -= 0.004 * delta
		mk = clampf(mk, 0.0, 1.0)
		e["muck"] = mk
		var mat: ShaderMaterial = e["mat"]
		mat.set_shader_parameter("muck", mk)
		(e["tmat"] as ShaderMaterial).set_shader_parameter("muck", mk)
		mat.set_shader_parameter("base_y", ground)
		# the vehicle's frame, dropped to the ground under it: the mud rides with it
		var vx := n.global_transform
		vx.origin.y = ground
		mat.set_shader_parameter("veh_inv", Projection(vx.affine_inverse()))
		mat.set_shader_parameter("reach", clampf(half.y * 0.3, 0.75, 1.15))
		_cab_box(n, mat)
		# put the muck on any mesh that hasn't got it (tyres get rebuilt on a swap)
		e["scan"] = float(e["scan"]) - delta
		if float(e["scan"]) <= 0.0 and mk > 0.01:
			e["scan"] = 2.0
			_apply_muck(n, mat, e["tmat"])
	for id in _st.keys():
		if not seen.has(id):
			for k in ["dust", "spray"]:
				for p in _st[id][k]:
					(p as Node).queue_free()
			_st.erase(id)


## Where the cab is, from where the driver sits (its eye), in the vehicle's
## frame: the shader keeps the inside of it clean. Not for a cab that turns
## on its own (the excavator's).
func _cab_box(n: Node3D, mat: ShaderMaterial) -> void:
	if not n.has_method("eye_xf") or n.get("_cab") != null:
		return
	var e: Vector3 = n.global_transform.affine_inverse() * (n.eye_xf() as Transform3D).origin
	var hx := absf(e.x) + 0.5
	mat.set_shader_parameter("cab_lo", Vector3(-hx, e.y - 0.95, e.z - 1.1))
	mat.set_shader_parameter("cab_hi", Vector3(hx, e.y + 0.7, e.z + 0.8))


## The muck overlay on the outside of the vehicle (not the gauges and dash).
func _apply_muck(n: Node, mat: ShaderMaterial, tyre_mat: ShaderMaterial) -> void:
	# the wheels: their own mud, which turns with them
	var wheels := {}
	var wl = n.get("_wheel_nodes")
	if wl is Array:
		for w in wl:
			var wn: Node = (w as Array)[0] if w is Array else w
			if wn != null:
				wheels[wn.get_instance_id()] = true
	var st: Array = [[n, false]]
	while not st.is_empty():
		var e: Array = st.pop_back()
		var c: Node = e[0]
		var on_wheel: bool = bool(e[1]) or wheels.has(c.get_instance_id())
		var nm := String(c.name)
		if nm.begins_with("Dash") or nm.contains("Cockpit") or nm.contains("Gauge") or c is Label3D:
			continue
		for k in c.get_children():
			st.append([k, on_wheel])
		if c is MeshInstance3D:
			var want := tyre_mat if on_wheel else mat
			if (c as MeshInstance3D).material_overlay != want:
				(c as MeshInstance3D).material_overlay = want


## Muck on this vehicle now, 0..1 (for the HUD / tests).
func muck_of(n: Node) -> float:
	var id := n.get_instance_id()
	return float(_st[id]["muck"]) if _st.has(id) else 0.0


func _dust() -> CPUParticles3D:
	var ramp := Fx.gradient([[0.0, Color(1, 1, 1, 0.0)], [0.1, Color(1, 1, 1, 0.5)], [0.5, Color(1, 1, 1, 0.28)], [1.0, Color(1, 1, 1, 0.0)]])
	var p := Fx.particles(Fx.smoke_material(), 40, 2.6, 1.3, ramp, 3.6)
	p.direction = Vector3(0, 1, 0)
	p.spread = 60.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -0.2, 0)
	p.damping_min = 0.5
	p.damping_max = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.emitting = false
	add_child(p)
	return p


## Mud flung off a tyre: heavy dark clods that arc up and fall back.
func _spray() -> CPUParticles3D:
	var ramp := Fx.gradient([[0.0, Color(1, 1, 1, 1.0)], [0.7, Color(1, 1, 1, 0.9)], [1.0, Color(1, 1, 1, 0.0)]])
	var p := Fx.particles(Fx.smoke_material(), 60, 1.1, 0.22, ramp, 0.8)
	p.direction = Vector3(0, 1, 1)
	p.spread = 28.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9.8, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.emitting = false
	add_child(p)
	return p


## Half width and half length of the thing, from its meshes (cached).
func _half_size(n: Node3D) -> Vector2:
	if n.has_meta("dust_half"):
		return n.get_meta("dust_half")
	var inv := n.global_transform.affine_inverse()
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var st: Array = [n]
	while not st.is_empty():
		var c: Node = st.pop_back()
		for k in c.get_children():
			st.append(k)
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var ab: AABB = (c as MeshInstance3D).get_aabb()
			for ci in range(8):
				var cp: Vector3 = inv * ((c as MeshInstance3D).global_transform * ab.get_endpoint(ci))
				lo = lo.min(cp)
				hi = hi.max(cp)
	var h := Vector2(1.0, 2.0)
	if lo.x < 1e8:
		h = Vector2(clampf((hi.x - lo.x) * 0.5, 0.6, 2.0), clampf((hi.z - lo.z) * 0.5, 1.0, 5.0))
	n.set_meta("dust_half", h)
	return h
