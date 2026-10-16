extends Node3D
## Skydiving jobs: take the jumpers up over the drop zone beside the strip, at
## the height they paid for, slow down, and give them the green light (the job
## board key). Out they go: freefall, canopies open low, and they steer for the
## target. Paid by how close they land.

const PilotRig = preload("res://scripts/pilot_rig.gd")
const PilotModel = preload("res://scripts/pilot_model.gd")
const MeshKit = preload("res://scripts/meshkit.gd")
const TERMINAL := 55.0          # m/s in freefall
const OPEN_AGL := 700.0         # canopy opens this high above the ground
const SINK := 6.0               # m/s under canopy
const GLIDE := 9.0              # m/s forward under canopy, at most

var plane: Node3D
var jobs: Node
var terrain: RefCounted
var wind: Node
var notice: Callable            # func(text)
var _jumpers: Array = []        # {node, canopy, pos, vel, phase, job, dz}
var _markers := {}              # strip -> Node3D (target on the ground and a label)


func _ready() -> void:
	# A target on the ground at each drop zone, and a label to find it from the air.
	for k in range(terrain.strips.size()):
		var dz: Vector3 = jobs.drop_zone(k)
		if dz == Vector3.INF:
			continue
		var kit := MeshKit.new()
		var orange := Color(0.95, 0.45, 0.08)
		var white := Color(0.92, 0.92, 0.88)
		for i in range(24):
			var a0 := TAU * float(i) / 24.0
			var a1 := TAU * float(i + 1) / 24.0
			for ring in [[9.0, 11.0, orange], [3.0, 4.5, white]]:
				var r0: float = ring[0]
				var r1: float = ring[1]
				kit.quad(Vector3(cos(a0) * r0, 0.08, sin(a0) * r0), Vector3(cos(a1) * r0, 0.08, sin(a1) * r0),
					Vector3(cos(a1) * r1, 0.08, sin(a1) * r1), Vector3(cos(a0) * r1, 0.08, sin(a0) * r1), ring[2], Vector3.UP)
		kit.box_at(Vector3(0, 0.08, 0), Vector3(14.0, 0.05, 1.6), white)
		kit.box_at(Vector3(0, 0.08, 0), Vector3(1.6, 0.05, 14.0), white)
		var mi := kit.instance("DropZone")
		mi.position = dz
		add_child(mi)
		var label := Label3D.new()
		label.text = "DROP ZONE"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.pixel_size = 0.0012
		label.font_size = 28
		label.outline_size = 6
		label.modulate = Color(1.0, 0.7, 0.3)
		label.position = dz + Vector3(0, 40, 0)
		label.visible = false
		add_child(label)
		_markers[k] = label
		terrain.clear_spot(dz.x, dz.z, 16.0)


## The skydiving job on board, if any.
func _job() -> Dictionary:
	for j in jobs.carried:
		if String(j["kind"]) == "skydive" and not bool(j.get("jumped", false)):
			return j
	return {}


## Ready for the green light? Returns "" when ready, or what's missing.
func ready_text() -> String:
	var j := _job()
	if j.is_empty():
		return "-"
	if plane.on_ground:
		return "Take them up to %d ft over the drop zone." % int(j["alt_ft"])
	var dz: Vector3 = jobs.drop_zone(int(j["from"]))
	var p: Vector3 = plane.global_position
	var d := Vector2(p.x - dz.x, p.z - dz.z).length()
	var agl_ft := (p.y - dz.y) * 3.28084
	if agl_ft < float(j["alt_ft"]) - 300.0:
		return "Jump run: climb to %d ft above the drop zone (now %d)." % [int(j["alt_ft"]), int(agl_ft)]
	if d > 1500.0:
		return "Jump run: fly over the drop zone (%.1f nm)." % (d / 1852.0)
	if plane.ias_kt > 100.0:
		return "Jump run: slow below 100 kt for the door."
	return ""


func can_jump() -> bool:
	return ready_text() == ""


## Green light: out they go, a couple of seconds apart.
func jump() -> void:
	var j := _job()
	if j.is_empty() or not can_jump():
		return
	j["jumped"] = true
	var n: int = int(j["pax"])
	var dz: Vector3 = jobs.drop_zone(int(j["from"]))
	for i in range(n):
		var m: Node3D = PilotRig.new() if PilotRig.available() else PilotModel.new()
		add_child(m)
		m.build()
		var canopy := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(3.2, 0.35, 1.3)
		canopy.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = [Color(0.85, 0.2, 0.15), Color(0.95, 0.75, 0.15), Color(0.2, 0.4, 0.8)][i % 3]
		canopy.material_override = mat
		canopy.visible = false
		add_child(canopy)
		var exit_at: Vector3 = plane.global_transform * Vector3(0.6, 0.0, 0.3)
		_jumpers.append({"node": m, "canopy": canopy, "pos": exit_at, "vel": plane.vel,
			"phase": "wait", "delay": 1.5 * float(i), "job": j, "dz": dz})
	# The seats empty as they go.
	for pc in j["pieces"]:
		pc["at"] = "dropped"
		pc["strip"] = -1
	jobs._stow()
	_tell("Green light! %d out the door." % n)


func _tell(t: String) -> void:
	if notice.is_valid():
		notice.call(t)


func _process(delta: float) -> void:
	# Show the drop zone label for a jump on board.
	var j := _job()
	for k in _markers.keys():
		(_markers[k] as Node3D).visible = not j.is_empty() and int(j["from"]) == k
	var done_jobs := {}
	for jp in _jumpers:
		var m: Node3D = jp["node"]
		var phase: String = jp["phase"]
		if phase == "wait":
			jp["delay"] = float(jp["delay"]) - delta
			if float(jp["delay"]) <= 0.0:
				jp["phase"] = "free"
				jp["pos"] = plane.global_transform * Vector3(0.6, 0.0, 0.3)
				jp["vel"] = plane.vel * 0.9
			m.visible = false
			continue
		m.visible = true
		var p: Vector3 = jp["pos"]
		var v: Vector3 = jp["vel"]
		var g: float = terrain.height_at(p.x, p.z)
		var w := Vector3.ZERO
		if wind != null:
			w = wind.sample(p)
		match phase:
			"free":
				var rel := v - w
				var k := 9.81 / (TERMINAL * TERMINAL)
				v += (Vector3(0, -9.81, 0) - rel * rel.length() * k) * delta
				if p.y - g < OPEN_AGL:
					jp["phase"] = "canopy"
					(jp["canopy"] as Node3D).visible = true
				m.animate(delta, PilotModel.AIR, 0.0, 0.0)
				m.global_transform = Transform3D(Basis(Vector3.RIGHT, -1.3), p)
			"canopy":
				var dz: Vector3 = jp["dz"]
				var to := Vector3(dz.x - p.x, 0.0, dz.z - p.z)
				var want := to.normalized() * minf(GLIDE, to.length() * 0.4) if to.length() > 0.5 else Vector3.ZERO
				var target := want + Vector3(w.x, -SINK, w.z)
				v = v.lerp(target, clampf(delta * 1.5, 0.0, 1.0))
				var face := atan2(-v.x, -v.z) if Vector2(v.x, v.z).length() > 0.3 else m.rotation.y
				m.global_transform = Transform3D(Basis(Vector3.UP, face), p)
				m.animate(delta, PilotModel.IDLE, 0.0, 0.0)
				(jp["canopy"] as Node3D).global_transform = Transform3D(Basis(Vector3.UP, face), p + Vector3(0, 4.2, 0))
				if p.y <= g + 0.05:
					jp["phase"] = "landed"
					p.y = g
					v = Vector3.ZERO
					(jp["canopy"] as Node3D).visible = false
					jp["miss"] = Vector2(p.x - dz.x, p.z - dz.z).length()
			"landed":
				m.animate(delta, PilotModel.IDLE, 0.0, 0.0)
				m.global_transform = Transform3D(m.global_transform.basis, p)
		if phase != "landed":
			p += v * delta
		jp["pos"] = p
		jp["vel"] = v
	# A job is finished when all its jumpers are down.
	for jp in _jumpers:
		var job: Dictionary = jp["job"]
		var key := int(job["id"])
		if not done_jobs.has(key):
			done_jobs[key] = [job, true, 0.0, 0]
		var e: Array = done_jobs[key]
		if jp["phase"] != "landed":
			e[1] = false
		else:
			e[2] = float(e[2]) + float(jp.get("miss", 999.0))
			e[3] = int(e[3]) + 1
	for key in done_jobs.keys():
		var e: Array = done_jobs[key]
		var job2: Dictionary = e[0]
		if bool(e[1]) and job2 in jobs.carried:
			var avg := float(e[2]) / maxf(float(e[3]), 1.0)
			var score := clampf(1.0 - avg / 500.0, 0.2, 1.0)
			var got: int = jobs.finish_skydive(job2, score)
			_tell("All down, %d m from the target on average. Paid $%d." % [int(avg), got])
	# Tidy up jumpers long after landing and far away.
	var cam := get_viewport().get_camera_3d()
	for i in range(_jumpers.size() - 1, -1, -1):
		var jp2: Dictionary = _jumpers[i]
		if jp2["phase"] == "landed" and not (jp2["job"] in jobs.carried) and cam != null and cam.global_position.distance_to(jp2["pos"]) > 2500.0:
			(jp2["node"] as Node).queue_free()
			(jp2["canopy"] as Node).queue_free()
			_jumpers.remove_at(i)
