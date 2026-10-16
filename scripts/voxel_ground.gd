extends Node3D
## Smooth voxel ground for the diggable square (Voxel Tools, Transvoxel mesher).
## Quarter-metre voxels holding a signed distance field, so cuts, banks and
## tunnels come out smooth, like real dirt - never blocky. Mesh
## optimisation merges flat ground into bigger facets (the polyart look) and
## keeps the triangle count near the old half-metre heightmesh.
##
## ground.gd's heightfield stays the gameplay surface (wheels, walker, gold
## accounting). Every edit it makes is mirrored here column by column near the
## surface only, so tunnels dug below stay open. Underground work (drifts,
## caves, supports) edits the voxels directly through carve()/fill().
##
## Coordinates: the VoxelTerrain node sits at (-SQ, 0, -SQ) scaled by VOX, so
## voxel (i, y, j) is world (-SQ + i*VOX, y*VOX, -SQ + j*VOX).

const SHADER = preload("res://shaders/voxel_ground.gdshader")
const VOX := 0.25            # metres a voxel (0.5 is the light fallback)
const BAND := 1.5            # metres of live SDF either side of the surface
const DEEP := 150.0          # metres of diggable ground below the lowest surface
const SKY := 30.0            # metres of room above the highest surface

var ground: RefCounted
var terrain: VoxelLodTerrain
var tool: VoxelTool
var mat: ShaderMaterial
var viewer: VoxelViewer
var budget_cols := 2500      # voxel columns re-stamped a frame
var _pending_carves: Array = []   # [world pos, radius] waiting for blocks to load
var _sq := 180.0
var _n := 0
var _stamped := PackedFloat32Array()   # surface height (voxels) last written per column
var cave_openings: Array = []   # where a natural cave breaks out at the surface
var edits: Array = []         # player's own voxel digs/fills [x, y, z, r, add] - saved


## The ground's season settings as global shader values (the voxel engine
## copies the material per chunk, so plain uniforms set later never arrive).
static var _globals_ok := false


## The ground's global shader values are declared in project.godot
## ([shader_globals]); only add any that aren't (once, not every call: the
## list call is editor-only and slow at runtime).
static func ensure_globals() -> void:
	if _globals_ok:
		return
	_globals_ok = true
	var want := {"bp_mud_k": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0],
		"bp_rain": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		"bp_snow_cover": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		"bp_snow_line": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1350.0],
		"bp_col_snow": [RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.6, 0.63, 0.7)],
		"bp_melt": [RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, _black()],
		"bp_wear": [RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, _black()]}
	for k in want.keys():
		if not ProjectSettings.has_setting("shader_globals/" + k):
			RenderingServer.global_shader_parameter_add(k, want[k][0], want[k][1])


static var _black_tex: ImageTexture
static func _black() -> Texture2D:
	if _black_tex == null:
		_black_tex = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_R8))
	return _black_tex


static func set_global(k: String, v: Variant) -> void:
	ensure_globals()
	if v is Color:
		var c := (v as Color).srgb_to_linear()
		v = Vector3(c.r, c.g, c.b)
	RenderingServer.global_shader_parameter_set(k, v)


func setup(g: RefCounted, viewer_parent: Node3D = null) -> void:
	ensure_globals()
	ground = g
	_sq = float(g.SQ)
	_n = int(2.0 * _sq / VOX) + 1
	# Heightmap image, one pixel per voxel column; the native image generator
	# turns it into SDF far faster than a script could.
	var hs := PackedFloat32Array()
	hs.resize(_n * _n)
	var lo := 1.0e9
	var hi := -1.0e9
	for j in range(_n):
		var z := -_sq + j * VOX
		for i in range(_n):
			var h: float = g.height_at(-_sq + i * VOX, z)
			hs[j * _n + i] = h
			lo = minf(lo, h)
			hi = maxf(hi, h)
	lo -= 2.0
	hi += 2.0
	_stamped.resize(_n * _n)
	for k in range(_n * _n):
		_stamped[k] = hs[k] / VOX
	# The image generator tiles its image, and the mesher samples a voxel or
	# two past the bounds: there it read the far side of the map, standing a
	# wall 1.5-3.4 m high along the edges (seen by the bog, 2026-10-10). Pad
	# the image so whatever wraps in is this edge's own height: past +x/+z
	# repeat those edges; the half that -1, -2... wrap into repeats -x/-z.
	var pad := 0 if OS.has_environment("NOPAD") else 64     # 8 was too few: coarse LODs and a camera right at the edge read further past it (wall seen again 2026-10-11)
	var m := _n + pad
	var img := Image.create(m, m, false, Image.FORMAT_RF)
	var span := hi - lo
	for j in range(m):
		var sj := j if j < _n else (_n - 1 if j < _n + pad / 2 else 0)
		for i in range(m):
			var si := i if i < _n else (_n - 1 if i < _n + pad / 2 else 0)
			img.set_pixel(i, j, Color((hs[sj * _n + si] - lo) / span, 0, 0))
	var gen := VoxelGeneratorImage.new()
	gen.image = img
	gen.height_start = lo / VOX
	gen.height_range = span / VOX
	gen.channel = VoxelBuffer.CHANNEL_SDF

	var mesher := VoxelMesherTransvoxel.new()
	mesher.mesh_optimization_enabled = true
	mesher.mesh_optimization_error_threshold = 0.02
	mesher.mesh_optimization_target_ratio = 0.25

	# LOD terrain: full quarter-metre detail near the camera, coarser rings
	# further out, all of it kept in memory so any spot can be dug.
	terrain = VoxelLodTerrain.new()
	terrain.name = "VoxelGround"
	terrain.generator = gen
	terrain.mesher = mesher
	var y0 := int(floor((lo - DEEP) / VOX))
	var y1 := int(ceil((hi + SKY) / VOX))
	terrain.voxel_bounds = AABB(Vector3(0, y0, 0), Vector3(_n, y1 - y0, _n))
	terrain.full_load_mode_enabled = true
	terrain.mesh_block_size = 32
	terrain.lod_count = 4
	terrain.lod_distance = 160.0        # voxels: 40 m of full detail round the camera
	terrain.secondary_lod_distance = 160.0
	terrain.view_distance = 2048
	# (DESIGN_NOTES 186) no physics bodies or physics raycasts use the ground: wheels,
	# walkers and caves all ask height_at / floor_below / VoxelTool. Building trimesh
	# collision on every remesh (ruts restamp every tick) was pure main-thread cost.
	terrain.generate_collisions = false
	terrain.threaded_update_enabled = true
	terrain.scale = Vector3.ONE * VOX
	terrain.position = Vector3(-_sq, 0.0, -_sq)
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("layers", _layer_texture())
	_zone_textures()
	mat.set_shader_parameter("sq", _sq)
	# the quartz veins (veins.gd): fixed for the world seed, so set once here
	var Veins = load("res://scripts/veins.gd")
	Veins.make(int(Game.world_seed))
	mat.set_shader_parameter("bp_veins", Veins.texture())
	mat.set_shader_parameter("bp_vein_n", float(mini(Veins.list.size(), Veins.MAX)))
	terrain.material = mat
	add_child(terrain)
	tool = terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_SDF
	viewer = VoxelViewer.new()
	# view distance is in voxels; the square is 1440 across, so see all of it
	viewer.view_distance = 2048
	(viewer_parent if viewer_parent else self).add_child(viewer)
	(g.get("vox_dirty") as Dictionary).clear()   # the image already holds every edit so far


## Natural surface, pay top and bedrock depth for the shader to colour cuts.
func _layer_texture() -> ImageTexture:
	var vn: int = ground.FN + 1
	var img := Image.create(vn, vn, false, Image.FORMAT_RGBAF)
	for j in range(vn):
		for i in range(vn):
			var k: int = j * vn + i
			img.set_pixel(i, j, Color(ground.orig[k], ground.pay_top[k], ground.bedrock[k], ground.grade[k]))
	return ImageTexture.create_from_image(img)


## Surface zones (gravel, muskeg, sand, rock) and wetness, as ground_view had per vertex.
func _zone_textures() -> void:
	var vn: int = ground.FN + 1
	var zi := Image.create(vn, vn, false, Image.FORMAT_RGBA8)
	var wi := Image.create(vn, vn, false, Image.FORMAT_RG8)   # r wetness, g mud (DESIGN_NOTES 109)
	for j in range(vn):
		var z: float = -_sq + j * ground.FRES
		for i in range(vn):
			var x: float = -_sq + i * ground.FRES
			zi.set_pixel(i, j, ground.zone4(x, z))
			wi.set_pixel(i, j, Color(ground.wet_at(x, z), ground.mud_base_at(x, z) if ground.has_method("mud_base_at") else 0.0, 0))
	# the track in from the mountain road (world.gd _track_to_road): gravel
	var trk = ground.get("track")
	if trk != null and (trk as PackedVector2Array).size() > 1:
		var tp: PackedVector2Array = trk
		var rr := 3.4
		var fr: float = ground.FRES
		for k in range(tp.size() - 1):
			var a: Vector2 = tp[k]
			var b: Vector2 = tp[k + 1]
			var steps := maxi(int(a.distance_to(b) / fr), 1)
			for st in range(steps + 1):
				var q := a.lerp(b, float(st) / steps)
				var ci := int(round((q.x + _sq) / fr))
				var cj := int(round((q.y + _sq) / fr))
				var rc := int(ceil(rr / fr))
				for dj in range(-rc, rc + 1):
					for di in range(-rc, rc + 1):
						var ii := ci + di
						var jj := cj + dj
						if ii < 0 or jj < 0 or ii >= vn or jj >= vn:
							continue
						var dd: float = Vector2(di, dj).length() * fr
						if dd > rr:
							continue
						var wgt := smoothstep(rr, rr - 1.2, dd)
						var cz := zi.get_pixel(ii, jj)
						if wgt > cz.r:
							cz.r = wgt
							cz.g *= 1.0 - wgt
							zi.set_pixel(ii, jj, cz)
	mat.set_shader_parameter("zones", ImageTexture.create_from_image(zi))
	mat.set_shader_parameter("wetmap", ImageTexture.create_from_image(wi))


# ------------------------------------------------------------------------------
#  World <-> voxel
# ------------------------------------------------------------------------------
func to_voxel(p: Vector3) -> Vector3:
	return Vector3((p.x + _sq) / VOX, p.y / VOX, (p.z + _sq) / VOX)


func to_world(v: Vector3) -> Vector3:
	return Vector3(v.x * VOX - _sq, v.y * VOX, v.z * VOX - _sq)


# ------------------------------------------------------------------------------
#  Mirroring heightfield edits
# ------------------------------------------------------------------------------
## Re-stamp the surface skin over voxel columns [i0..i1] x [j0..j1].
## Only the band round the new surface is written; air already below it
## (a tunnel) is left alone. Returns false if the area isn't loaded yet.
func restamp(i0: int, j0: int, i1: int, j1: int) -> bool:
	i0 = clampi(i0, 0, _n - 1)
	j0 = clampi(j0, 0, _n - 1)
	i1 = clampi(i1, 0, _n - 1)
	j1 = clampi(j1, 0, _n - 1)
	var band := BAND / VOX
	# pass 1: which columns changed, and the height range they span
	var cols := PackedInt32Array()
	var news := PackedFloat32Array()
	var ylo := 1.0e9
	var yhi := -1.0e9
	for j in range(j0, j1 + 1):
		var z := -_sq + j * VOX
		for i in range(i0, i1 + 1):
			var hv: float = ground.height_at(-_sq + i * VOX, z) / VOX
			var old := _stamped[j * _n + i]
			if absf(hv - old) < 0.04:
				continue
			cols.append(j * _n + i)
			news.append(hv)
			ylo = minf(ylo, minf(hv, old))
			yhi = maxf(yhi, maxf(hv, old))
	if cols.is_empty():
		return true
	var box := AABB(Vector3(i0, ylo - band - 1, j0), Vector3(i1 - i0 + 1, yhi - ylo + 2 * band + 2, j1 - j0 + 1))
	if not tool.is_area_editable(box):
		return false
	# pass 2: write the skin
	for c in range(cols.size()):
		var k := cols[c]
		var i := k % _n
		var j := k / _n
		var hv := news[c]
		var old := _stamped[k]
		_stamped[k] = hv
		var ya := int(floor(minf(hv, old) - band))
		var yb := int(ceil(maxf(hv, old) + band))
		for y in range(ya, yb + 1):
			var d := clampf(float(y) - hv, -band, band)
			var v := Vector3i(i, y, j)
			if d < 0.0 and float(y) < hv - band * 0.6:
				if tool.get_voxel_f(v) > 0.0:
					continue          # keep a tunnel's air
			tool.set_voxel_f(v, d)
	return true


func _process(_dt: float) -> void:
	# the voxel viewer rides with whatever camera is live (chase, cockpit, walker)
	if viewer.get_parent() == self:
		var cam := get_viewport().get_camera_3d()
		if cam:
			viewer.global_position = cam.global_position
	_mirror_edits()
	if not _pending_carves.is_empty():
		var keep: Array = []
		for c in _pending_carves:
			var done: bool
			if int(c[2]) == 3 or int(c[2]) == 4:
				done = _box_now(c[0], float(c[3]), float(c[4]), float(c[5]), float(c[6]), int(c[2]) == 4)
			else:
				done = _carve_now(c[0], c[1], c[2])
			if not done:
				keep.append(c)
		_pending_carves = keep


func _mirror_edits() -> void:
	var dc = ground.get("vox_dirty")
	if dc == null or (dc as Dictionary).is_empty():
		return
	var done := 0
	var k := 1.0 / (VOX / float(ground.FRES))     # voxels per fine cell
	for key in (dc as Dictionary).keys():
		var r: Rect2i = dc[key]
		var i0 := int(floor(r.position.x * k)) - 1
		var j0 := int(floor(r.position.y * k)) - 1
		var i1 := int(ceil(r.end.x * k)) + 1
		var j1 := int(ceil(r.end.y * k)) + 1
		if restamp(i0, j0, i1, j1):
			dc.erase(key)
			done += (i1 - i0 + 1) * (j1 - j0 + 1)
			if done > budget_cols:
				break


# ------------------------------------------------------------------------------
#  Underground
# ------------------------------------------------------------------------------
## Cut a sphere of ground out (a drift face). Queued if not loaded.
## `log` keeps it in the save (the player's own digging).
func carve(p: Vector3, r: float, log: bool = true) -> void:
	if log:
		edits.append([p.x, p.y, p.z, r, 0])
	if not _carve_now(p, r, VoxelTool.MODE_REMOVE):
		_pending_carves.append([p, r, VoxelTool.MODE_REMOVE])


## Back-fill a sphere (a cave-in, a bulkhead).
func fill(p: Vector3, r: float, log: bool = true) -> void:
	if log:
		edits.append([p.x, p.y, p.z, r, 1])
	if not _carve_now(p, r, VoxelTool.MODE_ADD):
		_pending_carves.append([p, r, VoxelTool.MODE_ADD])


## Cut an oriented box out of the ground: floor at `base` (world, centre of
## the floor), facing `yaw`, `w` wide, `h` high, `l` long (centred on base).
## Square drifts: flat floor, straight walls, flat roof. add=true fills instead.
func cut_box(base: Vector3, yaw: float, w: float, h: float, l: float, add: bool = false, log: bool = true) -> void:
	if log:
		edits.append([base.x, base.y, base.z, 0.0, 3 if not add else 4, yaw, w, h, l])
	if not _box_now(base, yaw, w, h, l, add):
		_pending_carves.append([base, 0.0, 3 if not add else 4, yaw, w, h, l])


func _box_now(base: Vector3, yaw: float, w: float, h: float, l: float, add: bool) -> bool:
	var c := base + Vector3(0, h * 0.5, 0)
	var half := Vector3(w * 0.5, h * 0.5, l * 0.5)
	var rad := half.length() + 0.5
	var vc := to_voxel(c)
	var vr := rad / VOX
	var box := AABB(vc - Vector3.ONE * (vr + 1), Vector3.ONE * (2 * vr + 2))
	if not tool.is_area_editable(box):
		return false
	var inv_b := Basis(Vector3.UP, yaw).inverse()
	var x0 := int(floor(vc.x - vr))
	var x1 := int(ceil(vc.x + vr))
	var y0 := int(floor(vc.y - vr))
	var y1 := int(ceil(vc.y + vr))
	var z0 := int(floor(vc.z - vr))
	var z1 := int(ceil(vc.z + vr))
	var band := 2.0          # voxels of gradient kept round the cut
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			for y in range(y0, y1 + 1):
				var wp := to_world(Vector3(x, y, z))
				var q: Vector3 = inv_b * (wp - c)
				var d := q.abs() - half
				var outside := Vector3(maxf(d.x, 0.0), maxf(d.y, 0.0), maxf(d.z, 0.0)).length()
				var sd := outside + minf(maxf(d.x, maxf(d.y, d.z)), 0.0)    # box SDF, metres
				var sv := sd / VOX
				if sv > band:
					continue
				var v := Vector3i(x, y, z)
				var cur := tool.get_voxel_f(v)
				if add:
					tool.set_voxel_f(v, minf(cur, sv))
				else:
					tool.set_voxel_f(v, maxf(cur, -sv))
	return true


## Rub the scallops off a hand-dug face (blur the SDF a little).
func smooth(p: Vector3, r: float, log: bool = true) -> void:
	if log:
		edits.append([p.x, p.y, p.z, r, 2])
	if not _carve_now(p, r, -1):
		_pending_carves.append([p, r, -1])


## Replay a saved edit log (after the caves are cut).
func replay(log_in: Array) -> void:
	for e in log_in:
		var p := Vector3(float(e[0]), float(e[1]), float(e[2]))
		match int(e[4]):
			1:
				fill(p, float(e[3]))
			2:
				smooth(p, float(e[3]))
			3, 4:
				cut_box(p, float(e[5]), float(e[6]), float(e[7]), float(e[8]), int(e[4]) == 4)
			_:
				carve(p, float(e[3]))


# ------------------------------------------------------------------------------
#  Natural caves: branching worms and chambers
# ------------------------------------------------------------------------------
## Cut the map's natural cave systems. Deterministic from `seed_v`.
## `keep_out(x, z)` -> true where the surface must not be broken (runway...).
func cut_caves(seed_v: int, keep_out: Callable) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n_sys := 7
	var cuts := 0
	for s in range(n_sys):
		var start := Vector3(rng.randf_range(-_sq + 25.0, _sq - 25.0), 0.0, rng.randf_range(-_sq + 25.0, _sq - 25.0))
		var top: float = ground.natural_at(start.x, start.z)
		var dv := rng.randf()
		start.y = top - (lerpf(6.0, 30.0, dv) if s < 4 else lerpf(35.0, 90.0, dv))
		var worms: Array = [[start, rng.randf() * TAU, rng.randf_range(-0.15, 0.1), rng.randi_range(70, 150), rng.randf_range(1.1, 1.9)]]
		var branches_left := rng.randi_range(2, 5)
		while not worms.is_empty():
			var w: Array = worms.pop_back()
			var p: Vector3 = w[0]
			var yaw: float = w[1]
			var pitch: float = w[2]
			var steps: int = w[3]
			var rad: float = w[4]
			for k in range(steps):
				yaw += rng.randf_range(-0.28, 0.28)
				pitch = clampf(pitch + rng.randf_range(-0.12, 0.12), -0.5, 0.45)
				var d := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
				p += d * rad * 0.7
				if absf(p.x) > _sq - 6.0 or absf(p.z) > _sq - 6.0:
					break
				var surf: float = ground.natural_at(p.x, p.z)
				var r := rad * (0.8 + 0.4 * sin(float(k) * 0.37 + float(s)))
				# Stay under protected ground; elsewhere it may break out on a slope.
				if keep_out.call(p.x, p.z) and p.y + r > surf - 3.0:
					p.y = surf - 3.0 - r
					pitch = -0.2
				if p.y > surf + 1.0:
					break
				if p.y < float(terrain.voxel_bounds.position.y) * VOX + 6.0:
					pitch = 0.3
				carve(p, r, false)
				cuts += 1
				if p.y + r > surf - 0.3 and (cave_openings.is_empty() or (cave_openings.back() as Vector3).distance_to(p) > 15.0):
					cave_openings.append(Vector3(p.x, surf, p.z))
				# now and then a chamber, now and then a branch
				if rng.randf() < 0.025:
					for c in range(5):
						carve(p + Vector3(rng.randf_range(-3, 3), rng.randf_range(-1, 1.5), rng.randf_range(-3, 3)), rad * rng.randf_range(1.6, 2.6), false)
						cuts += 1
				if rng.randf() < 0.035 and branches_left > 0:
					branches_left -= 1
					worms.append([p, yaw + rng.randf_range(0.8, 1.6) * (1.0 if rng.randf() < 0.5 else -1.0), rng.randf_range(-0.2, 0.2), rng.randi_range(30, 80), maxf(rad * 0.8, 0.9)])
	return cuts


## A tunnel along a polyline of world points.
func drift(points: Array, r: float, spacing: float = 0.6) -> void:
	for k in range(points.size() - 1):
		var a: Vector3 = points[k]
		var b: Vector3 = points[k + 1]
		var steps := maxi(1, int(a.distance_to(b) / spacing))
		for s in range(steps + 1):
			carve(a.lerp(b, float(s) / steps), r)


func _carve_now(p: Vector3, r: float, mode: int) -> bool:
	var vp := to_voxel(p)
	var vr := r / VOX
	if not tool.is_area_editable(AABB(vp - Vector3.ONE * (vr + 2), Vector3.ONE * (2 * vr + 4))):
		return false
	if mode == -1:
		tool.smooth_sphere(vp, vr, 2.0)
		return true
	tool.mode = mode
	tool.do_sphere(vp, vr)
	return true


## The floor under `p` (world), smooth: the SDF zero crossing found down
## each of the 4 voxel columns round p, blended. Starts 0.7 m above p (a
## step up). Returns -INF if there's no floor within max_d.
func floor_below(p: Vector3, max_d: float = 40.0) -> float:
	var v := to_voxel(p + Vector3(0, 0.7, 0))
	var x0 := int(floor(v.x))
	var z0 := int(floor(v.z))
	var fx := v.x - x0
	var fz := v.z - z0
	var steps := int((max_d + 0.7) / VOX)
	var hs: Array[float] = []
	var in_rock := false
	var sum := 0.0
	var n := 0
	for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var h := _col_floor(x0 + c.x, z0 + c.y, v.y, steps)
		if h == INF:
			in_rock = true
		elif h != -INF:
			sum += h
			n += 1
		hs.append(h)
	if n == 0:
		return v.y * VOX if in_rock else -INF     # all rock up to the knee: a step up
	var avg := sum / n
	for i in range(4):          # a column in the wall or over a hole takes the others' level
		if hs[i] == INF or hs[i] == -INF:
			hs[i] = avg
	var a := lerpf(hs[0], hs[1], fx)
	var b := lerpf(hs[2], hs[3], fx)
	return lerpf(a, b, fz) * VOX


func _col_floor(x: int, z: int, ystart: float, steps: int) -> float:
	var y := int(floor(ystart))
	var prev := tool.get_voxel_f(Vector3i(x, y, z))
	if prev < 0.0:
		return INF               # this column is wall at knee height
	for k in range(steps):
		y -= 1
		var cur := tool.get_voxel_f(Vector3i(x, y, z))
		if cur < 0.0:
			return float(y) - cur / (prev - cur)
		prev = cur
	return -INF


## SDF (metres-ish) at a world point, interpolated; < 0 is rock.
func sdf_at(p: Vector3) -> float:
	var v := to_voxel(p)
	var i := Vector3i(int(floor(v.x)), int(floor(v.y)), int(floor(v.z)))
	var f := v - Vector3(i)
	var c00 := lerpf(tool.get_voxel_f(i), tool.get_voxel_f(i + Vector3i(1, 0, 0)), f.x)
	var c10 := lerpf(tool.get_voxel_f(i + Vector3i(0, 1, 0)), tool.get_voxel_f(i + Vector3i(1, 1, 0)), f.x)
	var c01 := lerpf(tool.get_voxel_f(i + Vector3i(0, 0, 1)), tool.get_voxel_f(i + Vector3i(1, 0, 1)), f.x)
	var c11 := lerpf(tool.get_voxel_f(i + Vector3i(0, 1, 1)), tool.get_voxel_f(i + Vector3i(1, 1, 1)), f.x)
	return lerpf(lerpf(c00, c10, f.y), lerpf(c01, c11, f.y), f.z) * VOX


## Is the area round p loaded (so its voxels can be trusted)?
func ready_at(p: Vector3) -> bool:
	var v := to_voxel(p)
	return tool.is_area_editable(AABB(v - Vector3(4, 12, 4), Vector3(8, 24, 8)))


## Voxel raycast in world space; returns the world hit point or null.
func raycast(from: Vector3, dir: Vector3, dist: float):
	var hit := tool.raycast(to_voxel(from), dir.normalized(), dist / VOX)
	if hit == null:
		return null
	return to_world(Vector3(hit.position))
