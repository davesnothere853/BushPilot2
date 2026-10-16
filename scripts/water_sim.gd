extends Node3D
## Surface water on the square (DESIGN_NOTES 62): a 1 m grid of water depths
## over the deformable ground.
##   - Groundwater seeps into anything dug below the water table, up to it.
##   - Water flows downhill cell to cell and finds its level; on dry ground
##     it slowly soaks away. The creek is real running water: its bed sits a
##     little under the table, so it seeps full and runs down to the pond.
##   - The pond is the sink: water reaching its shore joins it.
##   - Pumps take water out at an intake and dump it at a hose end.
## Only "active" cells (wet, or dug below the table, and their neighbours) are
## stepped, so a dry square costs nothing.

const CELL := 1.0
const STEP := 0.1            # seconds a sim step
const FLOW := 0.22           # fraction of a level difference passed per step (stable < 0.25)
const SEEP := 0.006          # m/s of rise per metre of head below the table (slows as it fills)
const SOAK := 0.0006         # m per step lost on dry ground above the table
const MIN_W := 0.002

var ground: RefCounted
var n := 0
var sq := 180.0
var h := PackedFloat32Array()        # ground height per cell (centre)
var tab := PackedFloat32Array()      # water table per cell
var w := PackedFloat32Array()        # water depth
var sink := PackedByteArray()        # 1: the pond - water arriving here is gone
var active := {}                     # cell index -> true
var pumps: Array = []                # {"in": Vector3, "out": Vector3, "rate": m3/s, "on": bool, "node": Node3D}
var _acc := 0.0
var _mesh_t := 0.0
var _mesh_dirty := {}                # chunk Vector2i -> true
var _chunks := {}                    # chunk -> MeshInstance3D
var _mat: StandardMaterial3D
const CH := 24                       # cells a mesh chunk


func setup(g: RefCounted) -> void:
	ground = g
	sq = float(g.SQ)
	n = int(2.0 * sq / CELL)
	h.resize(n * n)
	tab.resize(n * n)
	w.resize(n * n)
	sink.resize(n * n)
	for j in range(n):
		for i in range(n):
			var k := j * n + i
			var x := _cx(i)
			var z := _cz(j)
			h[k] = g.height_at(x, z)
			tab[k] = g.water_table_at(x, z)
			w[k] = 0.0
			var pond: Dictionary = g.lakes[0] if not g.lakes.is_empty() else {"pos": Vector2(1.0e6, 1.0e6), "radius": 0.0}
			sink[k] = 1 if Vector2(x, z).distance_to(pond["pos"]) < float(pond["radius"]) + 2.0 else 0
			if h[k] < tab[k] - 0.01 and sink[k] == 0:
				active[k] = true
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.22, 0.27, 0.24, 0.78)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.08
	_mat.metallic_specular = 0.7
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	g.water = self


func _cx(i: int) -> float:
	return -sq + (float(i) + 0.5) * CELL


func _cz(j: int) -> float:
	return -sq + (float(j) + 0.5) * CELL


func cell_of(x: float, z: float) -> int:
	var i := int(floor((x + sq) / CELL))
	var j := int(floor((z + sq) / CELL))
	if i < 0 or j < 0 or i >= n or j >= n:
		return -1
	return j * n + i


## Water depth at a world spot (0 if dry or off the square).
func depth_at(x: float, z: float) -> float:
	var k := cell_of(x, z)
	return 0.0 if k < 0 else w[k]


## Water surface height at a spot, or -INF if dry.
func surface_at(x: float, z: float) -> float:
	var k := cell_of(x, z)
	if k < 0 or w[k] < 0.01:
		return -INF
	return h[k] + w[k]


func add_water(p: Vector3, m3: float) -> void:
	var k := cell_of(p.x, p.z)
	if k < 0 or sink[k] == 1:
		return
	w[k] += m3 / (CELL * CELL)
	active[k] = true


## Take up to m3 from round p (radius r); returns what it got.
func take_water(p: Vector3, m3: float, r: float = 2.5) -> float:
	var got := 0.0
	var cells: Array = []
	var ri := int(ceil(r / CELL))
	var c := cell_of(p.x, p.z)
	if c < 0:
		return 0.0
	var ci := c % n
	var cj := c / n
	for dj in range(-ri, ri + 1):
		for di in range(-ri, ri + 1):
			var i := ci + di
			var j := cj + dj
			if i < 0 or j < 0 or i >= n or j >= n:
				continue
			var k := j * n + i
			if w[k] > MIN_W:
				cells.append(k)
	cells.sort_custom(func(a: int, b: int) -> bool: return w[a] > w[b])
	for k in cells:
		var want := (m3 - got) / (CELL * CELL)
		if want <= 0.0:
			break
		var t := minf(w[k], want)
		w[k] -= t
		got += t * CELL * CELL
		_touch(k)
	return got


func _touch(k: int) -> void:
	active[k] = true
	_mesh_dirty[Vector2i((k % n) / CH, (k / n) / CH)] = true


# ------------------------------------------------------------------------------
#  Stepping
# ------------------------------------------------------------------------------
func _process(dt: float) -> void:
	_refresh_ground()
	# Nobody near the square: the water holds as it is (DESIGN_NOTES 158 -
	# it cost ~3 ms a frame flying miles away).
	var cam := get_viewport().get_camera_3d()
	if cam != null and pumps_idle() and Vector2(cam.global_position.x, cam.global_position.z).length() > sq + 700.0:
		_acc = 0.0
		return
	_acc += dt
	var steps := 0
	while _acc >= STEP and steps < 3:
		_acc -= STEP
		_pumps(STEP)
		_step()
		steps += 1
	_mesh_t += dt
	if _mesh_t > 0.25:
		_mesh_t = 0.0
		_rebuild_meshes()


func pumps_idle() -> bool:
	for p in pumps:
		if bool(p["on"]):
			return false
	return true


## Ground dug or piled: re-read heights there and wake those cells.
func _refresh_ground() -> void:
	var dc = ground.get("wat_dirty")
	if dc == null or (dc as Dictionary).is_empty():
		return
	var fres: float = ground.FRES
	for key in (dc as Dictionary).keys():
		var r: Rect2i = dc[key]
		var x0 := -sq + r.position.x * fres
		var z0 := -sq + r.position.y * fres
		var x1 := -sq + r.end.x * fres
		var z1 := -sq + r.end.y * fres
		var a := cell_of(x0, z0)
		var b := cell_of(minf(x1, sq - 0.01), minf(z1, sq - 0.01))
		if a < 0 or b < 0:
			continue
		for j in range(a / n, b / n + 1):
			for i in range(a % n, b % n + 1):
				var k := j * n + i
				h[k] = ground.height_at(_cx(i), _cz(j))
				if h[k] < tab[k] - 0.01 or w[k] > MIN_W:
					_touch(k)
	(dc as Dictionary).clear()


var _dw := PackedFloat32Array()      # this step's change per cell (scratch)
var _mark := PackedByteArray()       # 1: cell already in _touched
var _touched := PackedInt32Array()


func _add(k: int, v: float) -> void:
	if _mark[k] == 0:
		_mark[k] = 1
		_touched.append(k)
	_dw[k] += v


## One step over the active cells. Packed arrays and unrolled neighbours
## (no Dictionaries or temporary Arrays per cell): ~10x faster than it was.
func _step() -> void:
	if active.is_empty():
		return
	if _dw.size() != n * n:
		_dw.resize(n * n)
		_mark.resize(n * n)
	var keys := PackedInt32Array(active.keys())
	_touched.clear()
	for k in keys:
		if sink[k] == 1:
			if w[k] > 0.0:
				w[k] = 0.0
				_touch(k)
			continue
		var hk := h[k]
		var wk := w[k]
		var tk := tab[k]
		var s := hk + wk
		var d := 0.0
		# groundwater: in below the table, out (soaking away) above it
		if s < tk and hk < tk:
			d += minf(SEEP * STEP * (tk - s), tk - s)
		elif wk > 0.0 and hk >= tk:
			d -= minf(SOAK, wk)
		# flow to the four neighbours, downhill on the water surface (the
		# square's edge holds it: the plain is dry)
		if wk > MIN_W:
			var i := k % n
			var j := k / n
			var qe := 0.0
			var qw := 0.0
			var qs := 0.0
			var qn := 0.0
			if i + 1 < n:
				var s2 := h[k + 1] + w[k + 1]
				if s2 < s:
					qe = (s - s2) * FLOW
			if i > 0:
				var s3 := h[k - 1] + w[k - 1]
				if s3 < s:
					qw = (s - s3) * FLOW
			if j + 1 < n:
				var s4 := h[k + n] + w[k + n]
				if s4 < s:
					qs = (s - s4) * FLOW
			if j > 0:
				var s5 := h[k - n] + w[k - n]
				if s5 < s:
					qn = (s - s5) * FLOW
			var total := qe + qw + qs + qn
			if total > 0.0:
				var sc := minf(1.0, wk / total)
				d -= total * sc
				if qe > 0.0:
					_add(k + 1, qe * sc)
				if qw > 0.0:
					_add(k - 1, qw * sc)
				if qs > 0.0:
					_add(k + n, qs * sc)
				if qn > 0.0:
					_add(k - n, qn * sc)
		if d != 0.0:
			_add(k, d)
	var next := {}
	for k3 in _touched:
		var nw := maxf(w[k3] + _dw[k3], 0.0)
		if absf(nw - w[k3]) > 0.0005:
			_mesh_dirty[Vector2i((k3 % n) / CH, (k3 / n) / CH)] = true
		w[k3] = nw
		next[k3] = true
		_dw[k3] = 0.0
		_mark[k3] = 0
	# stay active: wet, or still below the table and not yet full
	for k4 in keys:
		if w[k4] > MIN_W or (h[k4] < tab[k4] - 0.01 and h[k4] + w[k4] < tab[k4] - 0.005):
			next[k4] = true
		elif next.has(k4) and w[k4] <= MIN_W:
			next.erase(k4)
	# settled cells (full to the table, nothing moving) can sleep
	active = next


# ------------------------------------------------------------------------------
#  Pumps
# ------------------------------------------------------------------------------
func add_pump(intake: Vector3, outlet: Vector3, rate: float) -> Dictionary:
	var p := {"in": intake, "out": outlet, "rate": rate, "on": true, "node": null, "moved": 0.0}
	pumps.append(p)
	return p


func _pumps(dt: float) -> void:
	for p in pumps:
		if not bool(p["on"]):
			continue
		var got := take_water(p["in"], float(p["rate"]) * dt)
		p["moved"] = float(p["moved"]) + got
		if got > 0.0:
			add_water(p["out"], got)


# ------------------------------------------------------------------------------
#  Drawing: one mesh per 24 m chunk, rebuilt when its water changes
# ------------------------------------------------------------------------------
func _rebuild_meshes() -> void:
	var budget := 6
	for key in _mesh_dirty.keys():
		_build_chunk(key)
		_mesh_dirty.erase(key)
		budget -= 1
		if budget <= 0:
			break


func _build_chunk(key: Vector2i) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for j in range(key.y * CH, mini((key.y + 1) * CH, n)):
		for i in range(key.x * CH, mini((key.x + 1) * CH, n)):
			var k := j * n + i
			if w[k] < 0.015:
				continue
			any = true
			var y := h[k] + w[k]
			var x0 := -sq + i * CELL
			var z0 := -sq + j * CELL
			# corners lean toward wet neighbours' level so the sheet reads smooth
			var c := [Vector3(x0, y, z0), Vector3(x0 + CELL, y, z0), Vector3(x0 + CELL, y, z0 + CELL), Vector3(x0, y, z0 + CELL)]
			st.set_normal(Vector3.UP)
			st.add_vertex(c[0]); st.add_vertex(c[1]); st.add_vertex(c[2])
			st.add_vertex(c[0]); st.add_vertex(c[2]); st.add_vertex(c[3])
	var mi: MeshInstance3D = _chunks.get(key)
	if not any:
		if mi != null:
			mi.visible = false
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_chunks[key] = mi
	mi.mesh = st.commit()
	mi.visible = true


## How much water is standing on the square (m3) - for tests.
func volume() -> float:
	var v := 0.0
	for k in range(w.size()):
		v += w[k]
	return v * CELL * CELL
