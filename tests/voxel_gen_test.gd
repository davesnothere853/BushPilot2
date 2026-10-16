extends Node3D
## Headless voxel ground test: load, match, dig mirror, drift, physics.
const GroundScript = preload("res://scripts/ground.gd")
const VoxelGround = preload("res://scripts/voxel_ground.gd")
var g: RefCounted
var vg: Node3D
var t0 := 0
var _f := 0
var stage := 0
var fails := 0
func _ready() -> void:
	t0 = Time.get_ticks_msec()
	g = GroundScript.new()
	var c := Node3D.new()
	add_child(c)
	c.position = Vector3(75, 2, 60)
	vg = VoxelGround.new()
	add_child(vg)
	vg.setup(g, c)
	print("setup ", Time.get_ticks_msec() - t0, " ms")

func surf_err(x0: float, z0: float, w: float) -> float:
	var err := 0.0
	for k in range(60):
		var x := x0 + fmod(k * 3.7, w)
		var z := z0 + fmod(k * 5.3, w)
		var v: Vector3 = vg.to_voxel(Vector3(x, 0, z))
		var vx := int(round(v.x)); var vz := int(round(v.z))
		var wx: float = vx * vg.VOX - g.SQ
		var wz: float = vz * vg.VOX - g.SQ
		var h: float = g.height_at(wx, wz)
		var y := int(floor(h / vg.VOX)) + 8
		while vg.tool.get_voxel_f(Vector3i(vx, y, vz)) > 0.0 and y > h / vg.VOX - 30:
			y -= 1
		var a: float = vg.tool.get_voxel_f(Vector3i(vx, y + 1, vz))
		var b: float = vg.tool.get_voxel_f(Vector3i(vx, y, vz))
		err = maxf(err, absf((y + b / (b - a)) * vg.VOX - h))
	return err

func ray_y(x: float, z: float, top: float = 60.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, -80, z))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return -999.0 if hit.is_empty() else hit.position.y

func check(name: String, ok: bool, info: String) -> void:
	print(("PASS " if ok else "FAIL ") + name + "  " + info)
	if not ok:
		fails += 1

func _physics_process(_d: float) -> void:
	_f += 1
	if stage == 0:
		if vg.tool.is_area_editable(AABB(vg.to_voxel(Vector3(55, -20, 40)), Vector3(160, 200, 160))) and _f > 30:
			print("loaded at ", Time.get_ticks_msec() - t0, " ms")
			var e := surf_err(60, 45, 30)
			check("surface matches", e < 0.05, str(e))
			var t1 := Time.get_ticks_usec()
			for k in range(60):
				var a := k * 0.7
				g.dig(Vector3(75 + cos(a) * (k * 0.06), 0, 60 + sin(a) * (k * 0.06)), 2.5, 3.0)
			print("60 digs heightfield ", (Time.get_ticks_usec() - t1) / 1000.0, " ms, dirty ", g.vox_dirty.size())
			t1 = Time.get_ticks_usec()
			vg._mirror_edits()
			var guard := 0
			while not g.vox_dirty.is_empty() and guard < 50:
				vg._mirror_edits()
				guard += 1
			print("mirror passes ", guard, " left ", g.vox_dirty.size())
			print("mirror ", (Time.get_ticks_usec() - t1) / 1000.0, " ms")
			stage = 1
			_f = 0
	elif stage == 1 and _f > 180:
		var e2 := surf_err(66, 51, 18)
		check("dug pit mirrored", e2 < 0.06, str(e2))
		var py := ray_y(75, 60)
		check("physics in pit", absf(py - g.height_at(75, 60)) < 0.15, "%.2f vs %.2f" % [py, g.height_at(75, 60)])
		# a drift into the ground beside the pad
		var a := Vector3(90, g.height_at(90, 40) - 1.0, 40)
		vg.drift([a, a + Vector3(10, -2, 0), a + Vector3(20, -4, -6)], 1.6)
		stage = 2
		_f = 0
	elif stage == 2 and _f > 60:
		var mid := Vector3(100, g.height_at(90, 40) - 3.0, 40)
		check("drift is open", not vg.solid_at(mid), str(mid))
		check("rock above drift", vg.solid_at(mid + Vector3(0, 2.6, 0)) or g.height_at(100, 40) < mid.y + 2.6, "")
		var fy := ray_y(100, 40, mid.y + 0.5)
		check("drift floor collides", absf(fy - (mid.y - 1.6)) < 0.3, "%.2f vs %.2f" % [fy, mid.y - 1.6])
		print("DONE fails=", fails, " total ", Time.get_ticks_msec() - t0, " ms")
		get_tree().quit()
	if _f > 3000:
		print("TIMEOUT stage ", stage)
		get_tree().quit()
