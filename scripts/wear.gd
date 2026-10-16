extends Node
## Track and tyre marks on the claim (DESIGN_NOTES 150): every machine's
## tracks and every truck's tyres paint into a fine map over the 360 m square
## (20 cm a pixel) - the turf torn off and the dirt packed, the grouser bars
## of a crawler's shoes showing as stripes across its two tracks, a tyre a
## softer band - and the ground shader (voxel_ground.gdshader, bp_wear) shows
## it. A pivot turn on tracks scuffs a wider, deeper patch. Saved.
##
## And soft ground tears: a crawler working turf, moss or muskeg presses ruts
## a centimetre or two deep as it goes (ground.gd rut()), deeper turning.

const RES := 0.2               # metres a pixel
const SAVE := "user://wear.bin"

var terrain: RefCounted
var _n := 0
var _sq := 180.0
var _img: Image
var _tex: ImageTexture
var _dirty := false
var _t := 0.0
var _save_t := 0.0
var _last := {}                # body id -> [last position, distance since a rut]


func setup(t: RefCounted) -> void:
	terrain = t
	_sq = float(t.get("SQ")) if t.get("SQ") != null else 180.0
	_n = int(ceil(_sq * 2.0 / RES))
	_img = Image.create(_n, _n, false, Image.FORMAT_R8)
	var f := FileAccess.open_compressed(SAVE, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f != null:
		var data := f.get_buffer(_n * _n)
		f.close()
		if data.size() == _n * _n:
			_img.set_data(_n, _n, false, Image.FORMAT_R8, data)
	_tex = ImageTexture.create_from_image(_img)
	load("res://scripts/voxel_ground.gd").set_global("bp_wear", _tex)


func _px(x: float, z: float) -> Vector2i:
	return Vector2i(int((x + _sq) / RES), int((z + _sq) / RES))


func _put(x: float, z: float, v: float) -> void:
	var q := _px(x, z)
	if q.x < 0 or q.y < 0 or q.x >= _n or q.y >= _n:
		return
	var old := _img.get_pixel(q.x, q.y).r
	if v > old:
		_img.set_pixel(q.x, q.y, Color(v, 0, 0))
		_dirty = true


## A crawler at `xf` (its frame: -Z forward), tracks `gauge` apart, `shoe`
## wide, `length` on the ground. `turning`: 0..1 how hard it's pivoting.
func track(key: String, xf: Transform3D, gauge: float, shoe: float, length: float, turning: float, mass: float) -> void:
	if _img == null:
		return
	var p := xf.origin
	var prev: Array = _last.get(key, [])
	var moved := 0.0
	if not prev.is_empty():
		moved = Vector2(p.x - (prev[0] as Vector3).x, p.z - (prev[0] as Vector3).z).length()
		if moved < RES * 0.7 and turning < 0.3:
			return
	var since: float = (float(prev[1]) if not prev.is_empty() else 0.0) + moved
	_last[key] = [p, since]
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := Vector3(-fwd.z, 0, fwd.x)
	var depth := clampf(0.55 + 0.25 * turning, 0.0, 1.0)
	for sd in [-1.0, 1.0]:
		var c: Vector3 = p + side * float(sd) * gauge * 0.5
		# the shoes on the ground: stripes across the track at the grouser pitch
		var along := -length * 0.5
		while along <= length * 0.5:
			var a: Vector3 = c + fwd * along
			var bar := fposmod(along + Vector2(p.x, p.z).dot(Vector2(fwd.x, fwd.z)), 0.4) < 0.2
			var v := depth * (1.0 if bar else 0.72)
			var w := -shoe * 0.5
			while w <= shoe * 0.5:
				_put(a.x + side.x * w, a.z + side.z * w, v)
				w += RES * 0.8
			along += RES * 0.8
	# soft ground tears: ruts, deeper when it's pivoting
	if since > 1.2 and terrain != null and terrain.has_method("rut"):
		_last[key][1] = 0.0
		var soft := _soft(p)
		if soft > 0.0:
			for sd2 in [-1.0, 1.0]:
				var tp: Vector3 = p + side * float(sd2) * gauge * 0.5
				tp.y = terrain.height_at(tp.x, tp.z)
				terrain.rut(tp, shoe * 0.9, (0.008 + 0.02 * turning) * soft * clampf(mass / 12000.0, 0.5, 2.0))


## A tyre at `at`, `width` wide, rolling along `fwd`.
func tyre(at: Vector3, fwd: Vector3, width: float, strength: float) -> void:
	if _img == null:
		return
	var side := Vector3(-fwd.z, 0, fwd.x).normalized()
	var w := -width * 0.5
	while w <= width * 0.5:
		var q := _px(at.x + side.x * w, at.z + side.z * w)
		if q.x >= 0 and q.y >= 0 and q.x < _n and q.y < _n:
			var old := _img.get_pixel(q.x, q.y).r
			var v := minf(old + 0.12 * strength, 0.65)
			if v > old + 0.004:
				_img.set_pixel(q.x, q.y, Color(v, 0, 0))
				_dirty = true
		w += RES * 0.8


## How much the ground here gives: turf, moss and muskeg do, gravel and the
## pads and strips don't (they're marked but don't rut).
func _soft(p: Vector3) -> float:
	if terrain.has_method("strip_index_at") and terrain.strip_index_at(p.x, p.z, 0.0) >= 0:
		return 0.0
	var surf: int = terrain.surface_at(p.x, p.z) if terrain.has_method("surface_at") else 0
	if surf == 1:              # gravel
		return 0.15
	return 1.0


func _process(delta: float) -> void:
	_t += delta
	if _dirty and _t > 0.5:
		_t = 0.0
		_dirty = false
		_tex.update(_img)
		_save_t += 1.0
	_save_t += delta
	if _save_t > 30.0:
		_save_t = 0.0
		save()


func save() -> void:
	if _img == null:
		return
	var f := FileAccess.open_compressed(SAVE, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f != null:
		f.store_buffer(_img.get_data())
		f.close()
