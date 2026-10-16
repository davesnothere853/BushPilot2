extends Node3D
## Trees, shrubs, ground plants and rocks around the camera, streamed in square
## chunks: worked out on background threads, drawn as MultiMeshes, near ones
## in full detail and far ones simpler. Where each plant grows is decided in
## flora.gd, so the same plant is always in the same spot.

const Flora = preload("res://scripts/flora.gd")
const Meshes = preload("res://scripts/veg_meshes.gd")
const VEG_SHADER = preload("res://shaders/veg.gdshader")
const CARD_SHADER = preload("res://shaders/veg_cards.gdshader")
const Tex = preload("res://scripts/veg_textures.gd")

var terrain: RefCounted
var camera: Camera3D
var wind: Node

enum { TREES, FAR, SHRUBS, GROUND, ROCKS }
const LAYER_NAMES := ["trees", "far", "shrubs", "ground", "rocks"]
const CHUNK := [224.0, 448.0, 112.0, 44.0, 896.0]
const GRID := [Flora.G, Flora.G, Flora.SHRUB_G, Flora.GROUND_G, Flora.ROCK_G]
const STEP := [1, 1, 1, 1, 1]
const FAR_SHADER = preload("res://shaders/veg_far.gdshader")
const IMP_SIZE := Vector2i(256, 512)       # picture of each tree (sharp enough up close)
const IMP_H := 1.1                         # height the picture covers (trees are 1 tall)
var _imp_tex := {}                         # "kind:bare" -> Texture2D
var _imp_ready := false
var _imp_busy := false

var _radius := [1800.0, 5500.0, 600.0, 130.0, 1600.0]
var _near_lod := 480.0
var _flat := true
var _chunks: Array = [{}, {}, {}, {}, {}]       # per layer: Vector2i -> {node, lod}
var _pending: Array = [{}, {}, {}, {}, {}]      # per layer: Vector2i -> true
var _results: Array = []                        # [layer, key, buffers]
var _mutex := Mutex.new()
var _running := 0
var _meshes := {}            # "layer:kind:lod:bare" -> ArrayMesh
var _mats := {}              # "layer:kind" -> ShaderMaterial
var _bare := false
var _winter := false
var _season := 0
var _wait := 0.0
var _cam_pos := Vector3.ZERO
var _last_cp := Vector3.INF
var _show_ground := true
var instance_count := 0
var _layer_turn := 0
var perf_ms := 0.0           # what the last streaming pass cost (perf readout)
var perf_builds := 0         # chunks turned into nodes (for the perf test)
var perf_gens := 0           # chunks started
var perf_drops := 0          # chunks dropped
var _backlog := 0            # chunks wanted but not yet started
var _tasks: Array[int] = []  # background jobs still running
var _max_running := clampi(OS.get_processor_count() - 1, 2, 6)

const KINDS := [Flora.TREE_KINDS, Flora.TREE_KINDS, Flora.SHRUB_KINDS, Flora.GROUND_KINDS, 3]


func setup(t: RefCounted) -> void:
	terrain = t
	# Lighter plant models unless the plants are on Very far (Ultra).
	Meshes.lite = Game.gfx_plants < 3
	apply_quality(Game.gfx_plants)
	bake_impostors.call_deferred()


func apply_quality(q: int) -> void:
	# trees, far forest, shrubs, ground plants, rocks
	# Near trees are full 3D (needle cards); beyond them each tree is one card
	# with its picture on it, out to the Tree distance.
	q = clampi(q, 0, 3)
	_radius = [[850.0, 0.0, 170.0, 40.0, 1400.0], [1150.0, 0.0, 340.0, 80.0, 2600.0], [1500.0, 0.0, 420.0, 100.0, 3500.0],
		[1500.0, 0.0, 560.0, 140.0, 4200.0]][q]
	# The Tree distance setting stretches or shrinks how far the trees go.
	_radius[TREES] *= [0.7, 1.0, 1.35, 1.75][clampi(Game.tree_distance, 0, 3)]
	_near_lod = [160.0, 220.0, 300.0, 380.0][q]
	# Flat trees: every standing tree is one picture card turned to face you
	# (cheap enough to draw much further); the 3D layer only keeps the ones
	# you've felled, lying on the ground.
	var was_flat := _flat
	_flat = not Game.trees_3d
	if was_flat != _flat:
		# Switched between flat and 3D trees: rebuild the tree chunks.
		for layer in [TREES, FAR]:
			for key in _chunks[layer].keys():
				var ch: Dictionary = _chunks[layer][key]
				(ch["node"] as Node).queue_free()
				instance_count -= int(ch["count"])
			_chunks[layer].clear()
	if _flat:
		# The picture-card forest reaches past the 3D trees, but no further
		# than the eye can pick a tree out anyway.
		_radius[FAR] = minf(_radius[TREES] * 2.0, 2400.0)
		_radius[TREES] = 260.0
	else:
		_radius[FAR] = 0.0
	for k in _mats.keys():
		var parts: PackedStringArray = String(k).split(":")
		_fade_mat(int(parts[0]), int(parts[2]), _mats[k])


func _material(layer: int, kind: int, lod: int, cards: bool = false) -> ShaderMaterial:
	var k := "%d:%d:%d" % [layer, kind, lod]
	if cards:
		k += ":c"
	if not _mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = CARD_SHADER if cards else VEG_SHADER
		if layer == FAR:
			m.shader = FAR_SHADER
			m.set_shader_parameter("tex", _imp_tex.get("%d:%s" % [kind, str(_bare_kind(kind))]))
		if cards:
			var needly := (layer == TREES or layer == FAR) and (kind == Flora.WHITE_SPRUCE or kind == Flora.BLACK_SPRUCE)
			m.set_shader_parameter("tex", Tex.frond() if needly else Tex.leaves())
			if Meshes.eztree and layer == TREES:
				m.set_shader_parameter("tex", load("res://scripts/assets/trees.gd").veg_leaf_tex(kind))
		m.set_shader_parameter("sway", 0.0 if layer == ROCKS else (0.6 if layer == GROUND else 1.0))
		_mats[k] = m
		if _last_cp != Vector3.INF:
			m.set_shader_parameter("cam_pos", _last_cp)      # (it's only re-sent when the camera moves)
		_season_mat(k, m)
		_fade_mat(layer, lod, m)
	return _mats[k]


## Plants dissolve in and out over a band at the edge of their range instead
## of popping, and the far forest dissolves in where the near trees end.
## Near trees also cross-dissolve from the detailed shape to the simpler one.
func _fade_mat(layer: int, lod: int, m: ShaderMaterial) -> void:
	var r: float = _radius[layer]
	var fin := Vector2(-2.0, -1.0)
	var fout := Vector2(r * (0.7 if layer == TREES else 0.5), r)
	if layer == FAR:
		var rt: float = _radius[TREES]
		fin = Vector2(rt * 0.78, rt) if not _flat else Vector2(-2.0, -1.0)
		fout = Vector2(r * 0.85, r)
	m.set_shader_parameter("fade_in", fin)
	m.set_shader_parameter("fade_out", fout)


func _mesh(layer: int, kind: int, lod: int) -> ArrayMesh:
	var bare := _bare
	if layer == TREES or layer == FAR:
		bare = bare and (kind == Flora.BIRCH or kind == Flora.ASPEN or kind == Flora.POPLAR)
	elif layer == SHRUBS:
		bare = bare
	else:
		bare = false
	var k := "%d:%d:%d:%s" % [layer, kind, lod, str(bare)]
	if not _meshes.has(k):
		var m: ArrayMesh
		match layer:
			FAR:
				m = _imp_quad()
			TREES:
				m = Meshes.tree_cards(kind, lod, bare)
			SHRUBS:
				m = Meshes.shrub_cards(kind, bare)
			GROUND:
				m = Meshes.ground(kind)
			_:
				m = Meshes.rock(kind)
		m.surface_set_material(0, _material(layer, kind, lod))
		if m.get_surface_count() > 1:
			m.surface_set_material(1, _material(layer, kind, lod, true))
		_meshes[k] = m
	return _meshes[k]


# ------------------------------------------------------------------------------
#  Background generation
# ------------------------------------------------------------------------------
func _gen(layer: int, key: Vector2i) -> void:
	var t := terrain
	var cs: float = CHUNK[layer]
	var g: float = GRID[layer]
	var step: int = STEP[layer]
	var x0 := float(key.x) * cs - float(t.half)
	var z0 := float(key.y) * cs - float(t.half)
	var i0 := int(ceil((x0 + float(t.half)) / g))
	var i1 := int(ceil((x0 + cs + float(t.half)) / g))
	var j0 := int(ceil((z0 + float(t.half)) / g))
	var j1 := int(ceil((z0 + cs + float(t.half)) / g))
	var bufs: Array = []
	for _k in range(KINDS[layer]):
		bufs.append(PackedFloat32Array())
	for j in range(j0, j1):
		if step > 1 and j % step != 0:
			continue
		for i in range(i0, i1):
			if step > 1 and i % step != 0:
				continue
			var p: Dictionary
			match layer:
				TREES, FAR:
					p = Flora.tree_at(t, i, j)
				SHRUBS:
					p = Flora.shrub_at(t, i, j)
				GROUND:
					p = Flora.ground_at(t, i, j)
				_:
					p = Flora.rock_at(t, i, j)
			if p.is_empty():
				continue
			var pos: Vector3 = p["pos"]
			var yaw: float = p["yaw"]
			var basis: Basis
			var kind := 0
			var charred := 0.0
			match layer:
				TREES, FAR:
					var hgt: float = p["height"]
					kind = p["kind"]
					var girth := hgt * (0.9 + 0.25 * float(p["tint"]))
					basis = Basis(Vector3.UP, yaw).scaled(Vector3(girth, hgt, girth))
					var fk := Flora.key(i, j)
					if layer == FAR and Flora.felled.has(fk):
						continue
					if layer == TREES and _flat and not Flora.felled.has(fk):
						continue       # standing trees are the picture cards
					if layer == FAR:
						# Far off, draw every 2nd tree (then every 4th), a little
						# bigger, so the forest stays solid with far fewer cards.
						var dc := Vector2(pos.x - _cam_pos.x, pos.z - _cam_pos.z).length()
						var keep_every := 1
						if dc > _radius[FAR] * 0.55:
							keep_every = 4
						elif dc > _radius[FAR] * 0.28:
							keep_every = 2
						if keep_every > 1:
							if (i * 73856093 ^ j * 19349663) % keep_every != 0:
								continue
							var up := 1.35 if keep_every == 4 else 1.18
							basis = basis.scaled(Vector3(up, up, up))
					if Flora.felled.has(fk):
						var dir: Vector3 = Flora.felled[fk]
						if dir.y > 0.5:
							continue                 # bucked up and hauled away
						if dir.y < -0.5:
							charred = 1.0            # brought down by fire (fire.gd marks it)
						dir.y = 0.0
						dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
						var axis := Vector3.UP.cross(dir).normalized()
						basis = Basis(axis, deg_to_rad(84.0)) * basis
						pos += Vector3(0, 0.5, 0)
					pos.y -= 0.25
				SHRUBS:
					kind = p["kind"]
					var sz: float = p["size"]
					basis = Basis(Vector3.UP, yaw).scaled(Vector3(sz, sz, sz))
					pos.y -= 0.1
				GROUND:
					kind = p["kind"]
					var gs: float = p["size"]
					basis = Basis(Vector3.UP, yaw).scaled(Vector3(gs, gs, gs))
					pos.y -= 0.05
				_:
					kind = int(float(p["tint"]) * 2.99)
					var rs: float = p["size"]
					var n: Vector3 = p["nrm"]
					# Cliffs stand upright (level strata), sunk into the slope.
					basis = Basis(Vector3.UP, yaw).scaled(Vector3(rs, rs * (0.55 + 0.45 * float(p["tint"])), rs))
					pos.y -= rs * (0.12 + 0.25 * (1.0 - n.y))
			var b: PackedFloat32Array = bufs[kind]
			b.append_array([basis.x.x, basis.y.x, basis.z.x, pos.x,
				basis.x.y, basis.y.y, basis.z.y, pos.y,
				basis.x.z, basis.y.z, basis.z.z, pos.z,
				float(p["tint"]), charred, 0.0, 0.0])
			bufs[kind] = b
	_mutex.lock()
	_results.append([layer, key, bufs])
	_running -= 1
	_mutex.unlock()


func _build_chunk(layer: int, key: Vector2i, bufs: Array) -> void:
	var old: Dictionary = _chunks[layer].get(key, {})
	if not old.is_empty():
		(old["node"] as Node3D).queue_free()
		instance_count -= int(old["count"])
	var holder := Node3D.new()
	var lods := _lods_for(layer, key)
	var count := 0
	for kind in range(bufs.size()):
		count += (bufs[kind] as PackedFloat32Array).size() / 16
	add_child(holder)
	_chunks[layer][key] = {"node": holder, "lod": lods, "count": count, "bufs": bufs, "band": _far_band(key) if layer == FAR else 0}
	_fill(layer, key)
	instance_count += count


## (Re)make a chunk's drawn plants for the detail levels it needs right now.
func _fill(layer: int, key: Vector2i) -> void:
	var ch: Dictionary = _chunks[layer][key]
	var holder: Node3D = ch["node"]
	for c in holder.get_children():
		c.queue_free()
	var bufs: Array = ch["bufs"]
	for lod in ch["lod"]:
		for kind in range(bufs.size()):
			var buf: PackedFloat32Array = bufs[kind]
			var n := buf.size() / 16
			if n == 0:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = _mesh(layer, kind, lod)
			mm.instance_count = n
			mm.buffer = buf
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = _shadow_for(layer, lod, key)
			mmi.set_meta("kind", kind)
			mmi.set_meta("lod", lod)
			holder.add_child(mmi)


## Which thinning band a far-forest chunk's centre sits in (0 near: every
## tree; 1: every 2nd; 2: every 4th). Chunks rebuild when they change band.
func _far_band(key: Vector2i) -> int:
	var d := _chunk_dist(FAR, key)
	if d > _radius[FAR] * 0.55:
		return 2
	if d > _radius[FAR] * 0.28:
		return 1
	return 0


## Only plants near the camera cast shadows; far off you would never see them.
func _shadow_for(layer: int, lod: int, key: Vector2i) -> int:
	# No further than the sun's shadows reach at this Shadows setting.
	var reach: float = [0.0, 100.0, 300.0, 420.0, 500.0][clampi(Game.gfx_shadows, 0, 4)]
	var on := (layer == TREES or layer == ROCKS or layer == FAR) and _chunk_dist(layer, key) < minf(reach, 420.0 if layer != FAR else 500.0)
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Which detail levels a chunk draws: near trees in full, far ones simpler,
## and both across the band where one dissolves into the other.
func _lods_for(layer: int, key: Vector2i) -> Array:
	return [0]      # one detailed version of every plant, near or far


func _chunk_dist(layer: int, key: Vector2i) -> float:
	var cs: float = CHUNK[layer]
	var cx := (float(key.x) + 0.5) * cs - float(terrain.half)
	var cz := (float(key.y) + 0.5) * cs - float(terrain.half)
	return Vector2(cx - _cam_pos.x, cz - _cam_pos.z).length()


# ------------------------------------------------------------------------------
#  Streaming
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if terrain == null or camera == null:
		return
	var _t0 := Time.get_ticks_usec()
	_reap(false)
	# Every frame, so the dissolve bands move smoothly with the camera.
	var cp := camera.global_position
	# (DESIGN_NOTES 171) only when the camera has moved a little: standing
	# still or idling it was ~40 material writes a frame for nothing
	if cp.distance_squared_to(_last_cp) > 0.04:
		_last_cp = cp
		for m in _mats.values():
			(m as ShaderMaterial).set_shader_parameter("cam_pos", cp)
	# Finished chunks: turn a few into nodes each frame.
	_mutex.lock()
	var ready: Array = _results.slice(0, 2)       # a couple a frame: no hitch
	_results = _results.slice(2)
	_mutex.unlock()
	for r in ready:
		_pending[r[0]].erase(r[1])
		if _wanted(r[0], r[1]):
			perf_builds += 1
			_build_chunk(r[0], r[1], r[2])
	_wait -= delta
	if _wait > 0.0:
		return
	# One layer a pass, in turn (DESIGN_NOTES 158): scanning all five at
	# once was a ~10 ms hitch every 0.3 s.
	_wait = 0.06
	_layer_turn = (_layer_turn + 1) % 5
	_cam_pos = camera.global_position
	var agl: float = _cam_pos.y - maxf(terrain.height_at(_cam_pos.x, _cam_pos.z), 0.0)
	# Ground plants load once you are low enough to see them; they fade in by
	# true distance in the shader, so descending they appear gradually.
	_show_ground = agl < _radius[GROUND] * 1.4 and not _winter
	var todo: Array = []
	for layer in [_layer_turn]:
		var cs: float = CHUNK[layer]
		var rad: float = _radius[layer]
		var ci := int(floor((_cam_pos.x + float(terrain.half)) / cs))
		var cj := int(floor((_cam_pos.z + float(terrain.half)) / cs))
		var reach := int(ceil(rad / cs)) + 1
		var maxc := int(ceil(float(terrain.size) / cs))
		# Drop chunks that are now too far away.
		for key in _chunks[layer].keys():
			if not _wanted(layer, key, 1.15):
				var ch: Dictionary = _chunks[layer][key]
				instance_count -= int(ch["count"])
				(ch["node"] as Node3D).queue_free()
				_chunks[layer].erase(key)
				perf_drops += 1
			elif layer == FAR and _flat and int(_chunks[layer][key].get("band", 0)) != _far_band(key):
				# Flown closer or further: this patch of far forest needs its
				# trees thinned differently, so grow it again.
				var chf: Dictionary = _chunks[layer][key]
				instance_count -= int(chf["count"])
				(chf["node"] as Node3D).queue_free()
				_chunks[layer].erase(key)
			elif layer == TREES:
				# Shadows switch on as you come close and off as you leave.
				var sh := _shadow_for(layer, 0, key)
				if sh != int(_chunks[layer][key].get("shadow", -1)):
					_chunks[layer][key]["shadow"] = sh
					for mmi in (_chunks[layer][key]["node"] as Node3D).get_children():
						(mmi as MultiMeshInstance3D).cast_shadow = sh
		for dj in range(-reach, reach + 1):
			for di in range(-reach, reach + 1):
				var key := Vector2i(ci + di, cj + dj)
				if key.x < 0 or key.y < 0 or key.x >= maxc or key.y >= maxc:
					continue
				if _chunks[layer].has(key) or _pending[layer].has(key):
					continue
				if _wanted(layer, key):
					todo.append([_chunk_dist(layer, key) / maxf(rad, 1.0) + (0.0 if layer != FAR else 0.35), layer, key])
	todo.sort_custom(func(a, b): return a[0] < b[0])
	var started := 0
	for item in todo:
		if _running >= _max_running:
			break
		_pending[item[1]][item[2]] = true
		_running += 1
		started += 1
		perf_gens += 1
		_tasks.append(WorkerThreadPool.add_task(_gen.bind(item[1], item[2])))
	_backlog = todo.size() - started
	if _backlog > 0:
		_wait = 0.05      # more to do: come back soon
	if wind != null and _layer_turn == 0:
		var w: Vector3 = wind.sample(_cam_pos)
		var strength := clampf(Vector2(w.x, w.z).length() / 10.0, 0.1, 1.5)
		for m in _mats.values():
			(m as ShaderMaterial).set_shader_parameter("wind", Vector2(w.x, w.z).normalized() if strength > 0.11 else Vector2(1, 0))
			(m as ShaderMaterial).set_shader_parameter("wind_strength", strength)
	perf_ms = lerpf(perf_ms, float(Time.get_ticks_usec() - _t0) / 1000.0, 0.1)


## Instances and triangles drawn per layer (for tuning).
func stats() -> Dictionary:
	var out := {}
	for layer in range(5):
		var inst := 0
		var tris := 0
		var shadow_tris := 0
		for key in _chunks[layer].keys():
			for mmi in (_chunks[layer][key]["node"] as Node3D).get_children():
				var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
				var t: int = mm.mesh.get_faces().size() / 3
				inst += mm.instance_count
				tris += t * mm.instance_count
				if (mmi as MultiMeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					shadow_tris += t * mm.instance_count
		out[LAYER_NAMES[layer]] = [inst, tris, shadow_tris]
	return out


## Tidy up finished background jobs; on exit, wait for the rest so none is
## left working on a world that is being freed.
func _reap(wait_all: bool) -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		var id: int = _tasks[i]
		if wait_all or WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_tasks.remove_at(i)


func _exit_tree() -> void:
	_reap(true)


func is_idle() -> bool:
	_mutex.lock()
	var idle := _running == 0 and _results.is_empty()
	_mutex.unlock()
	for layer in range(5):
		if not _pending[layer].is_empty():
			return false
	return idle and _backlog == 0 and _wait > 0.0 


func _wanted(layer: int, key: Vector2i, slack: float = 1.0) -> bool:

	if layer == FAR and not _flat:
		return false        # 3D trees chosen: no picture cards
	var d := _chunk_dist(layer, key)
	var half_diag: float = CHUNK[layer] * 0.71
	if layer == GROUND and not _show_ground:
		return false
	if layer == FAR:
		# Any chunk that reaches into the band where the far forest shows.
		if _flat:
			return d - half_diag < _radius[FAR] * slack
		return d - half_diag < _radius[FAR] * slack and d + half_diag > _radius[TREES] * 0.78
	if (layer == SHRUBS or layer == GROUND) and _winter:
		return false
	return d - half_diag < _radius[layer] * slack


## A tree has been knocked down: redraw its chunk with the tree lying flat.
func fell(i: int, j: int, dir: Vector3) -> void:
	Flora.felled[Flora.key(i, j)] = dir
	for layer in [TREES, FAR]:
		var cs: float = CHUNK[layer]
		var x := (float(i) + 0.5) * Flora.G
		var z := (float(j) + 0.5) * Flora.G
		var key := Vector2i(int(floor(x / cs)), int(floor(z / cs)))
		if _chunks[layer].has(key) and not _pending[layer].has(key):
			_pending[layer][key] = true
			_running += 1
			_tasks.append(WorkerThreadPool.add_task(_gen.bind(layer, key)))


## Rebuild every loaded chunk that overlaps a circle (after ground is cleared).
func refresh_area(c: Vector3, r: float) -> void:
	for layer in [TREES, FAR, SHRUBS, GROUND, ROCKS]:
		var cs: float = CHUNK[layer]
		var k0 := Vector2i(int(floor((c.x - r + terrain.half) / cs)), int(floor((c.z - r + terrain.half) / cs)))
		var k1 := Vector2i(int(floor((c.x + r + terrain.half) / cs)), int(floor((c.z + r + terrain.half) / cs)))
		for kz in range(k0.y, k1.y + 1):
			for kx in range(k0.x, k1.x + 1):
				var key := Vector2i(kx, kz)
				if _chunks[layer].has(key) and not _pending[layer].has(key):
					_pending[layer][key] = true
					_running += 1
					_tasks.append(WorkerThreadPool.add_task(_gen.bind(layer, key)))


## Season: autumn colours, bare deciduous trees in winter, snow on everything.
func apply_season(season: int) -> void:
	var bare := season == Game.WINTER
	_winter = season == Game.WINTER
	_season = season
	for k in _mats.keys():
		_season_mat(k, _mats[k])
	if bare != _bare:
		_bare = bare
		for layer in [TREES, SHRUBS]:
			for key in _chunks[layer].keys():
				_fill(layer, key)
	# The far trees' pictures are taken again in the new season's colours
	# (the bake also points every card at its new picture when it's done).
	bake_impostors.call_deferred()
	_wait = 0.0


func _season_mat(k: String, m: ShaderMaterial) -> void:
	var spring := _season == Game.SPRING
	var fall := _season == Game.FALL
	if true:
		var parts: PackedStringArray = k.split(":")
		var layer := int(parts[0])
		var kind := int(parts[1])
		var deciduous := ((layer == TREES or layer == FAR) and kind >= Flora.BIRCH) or layer == SHRUBS
		m.set_shader_parameter("snow", 0.85 if _winter else 0.0)
		m.set_shader_parameter("alt_amount", 1.0 if (fall and (deciduous or layer == GROUND)) else 0.0)
		# Autumn: birch and willow go gold, aspen orange-gold, dwarf birch and
		# the berry heath crimson, fireweed red, grass and sedge straw.
		var alt := Color(0.86, 0.64, 0.16)
		if (layer == TREES or layer == FAR) and kind == Flora.ASPEN:
			alt = Color(0.92, 0.58, 0.12)
		elif (layer == TREES or layer == FAR) and kind == Flora.POPLAR:
			alt = Color(0.80, 0.66, 0.22)
		elif layer == SHRUBS and kind == Flora.ALDER:
			alt = Color(0.40, 0.40, 0.22)
		elif layer == SHRUBS and kind == Flora.DWARF_BIRCH:
			alt = Color(0.72, 0.26, 0.12)
		elif layer == GROUND:
			match kind:
				Flora.FIREWEED:
					alt = Color(0.68, 0.20, 0.14)
				Flora.LOWSHRUB:
					alt = Color(0.58, 0.16, 0.12)
				Flora.FERN:
					alt = Color(0.64, 0.44, 0.18)
				_:
					alt = Color(0.66, 0.56, 0.34)
		m.set_shader_parameter("leaf_alt", alt)
		var tint := Color(1, 1, 1)
		if spring and deciduous:
			tint = Color(1.15, 1.25, 0.85)
		elif _winter and not deciduous:
			tint = Color(0.8, 0.85, 0.85)
		m.set_shader_parameter("leaf_tint", tint)


# ------------------------------------------------------------------------------
#  Far trees: a picture of each kind, taken in a little offscreen studio
# ------------------------------------------------------------------------------
func _bare_kind(kind: int) -> bool:
	return _bare and (kind == Flora.BIRCH or kind == Flora.ASPEN or kind == Flora.POPLAR)


## One upright card, 1 tall, as wide as the picture covers.
func _imp_quad() -> ArrayMesh:
	var w := IMP_H * float(IMP_SIZE.x) / float(IMP_SIZE.y) * 0.5
	var y0 := -0.03
	var y1 := y0 + IMP_H
	var verts := PackedVector3Array([Vector3(-w, y0, 0), Vector3(w, y0, 0), Vector3(w, y1, 0), Vector3(-w, y0, 0), Vector3(w, y1, 0), Vector3(-w, y1, 0)])
	var uvs := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(0, 0)])
	var norms := PackedVector3Array()
	for _i in range(6):
		norms.append(Vector3(0, 0, 1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Photograph every tree kind (in this season's colours) for the far forest.
func bake_impostors() -> void:
	if _imp_busy or not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	_imp_busy = true
	var vp := SubViewport.new()
	vp.size = IMP_SIZE
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = IMP_H
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(0, -0.03 + IMP_H * 0.5, 6.0)
	cam.near = 0.1
	cam.far = 20.0
	vp.add_child(cam)
	cam.current = true
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(mi)
	var got := {}
	for kind in range(Flora.TREE_KINDS):
		var bare := _bare_kind(kind)
		var src := Meshes.tree(kind, 0, bare)
		for si in range(src.get_surface_count()):
			var mat := _material(TREES, kind, 0, si == 1).duplicate() as ShaderMaterial
			mat.set_shader_parameter("fade_in", Vector2(-2.0, -1.0))
			mat.set_shader_parameter("fade_out", Vector2(1.0e6, 2.0e6))
			mat.set_shader_parameter("wind_strength", 0.0)
			src.surface_set_material(si, mat)
		mi.mesh = src
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img == null or img.is_empty():
			continue
		img.generate_mipmaps()
		got["%d:%s" % [kind, str(bare)]] = ImageTexture.create_from_image(img)
	vp.queue_free()
	_imp_tex = got
	for k in _mats.keys():
		var parts: PackedStringArray = String(k).split(":")
		if int(parts[0]) == FAR:
			var kd := int(parts[1])
			(_mats[k] as ShaderMaterial).set_shader_parameter("tex", _imp_tex.get("%d:%s" % [kd, str(_bare_kind(kd))]))
	_imp_ready = true
	_imp_busy = false
	_wait = 0.0
