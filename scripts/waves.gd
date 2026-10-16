extends Node
## Waves made on the water by wheels, skis, floats and hulls. Each one is a
## ring spreading out from where the water was pushed aside; a string of them
## from something moving adds up to a proper V-shaped wake, which rolls across
## the lake, breaks on the shore and rocks anything floating.
##
## The water shader draws the same rings (it gets the list every frame), and
## anything floating asks height_at() so it bobs on what you see.

const MAX := 64
const SPEED := 3.2           # how fast the rings spread, m/s (waves about 6 m long)
const LIFE := 75.0           # seconds until a ring has died away
const K := 0.97              # 2 pi / wavelength

var materials: Array[ShaderMaterial] = []
var time := 0.0
var _src: Array[Vector4] = []       # x, z, start time, height


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Push the water aside here. `height` is the size of the wave, metres.
func add(p: Vector3, height: float) -> void:
	if height < 0.005:
		return
	# Close to the last one and fresh: make that one bigger instead.
	if not _src.is_empty():
		var last: Vector4 = _src.back()
		if time - last.z < 0.25 and Vector2(p.x - last.x, p.z - last.y).length() < 3.0:
			_src[_src.size() - 1] = Vector4(last.x, last.y, last.z, minf(maxf(last.w, height) + height * 0.25, 1.2))
			return
	if _src.size() >= MAX:
		# Drop the weakest of the old ones.
		var weakest := 0
		var wv := INF
		for i in range(_src.size()):
			var v := _strength(_src[i])
			if v < wv:
				wv = v
				weakest = i
		_src.remove_at(weakest)
	_src.append(Vector4(p.x, p.z, time, minf(height, 1.2)))


func _strength(s: Vector4) -> float:
	var age := time - s.z
	return s.w / sqrt(1.0 + 0.25 * SPEED * age) * clampf(1.0 - age / LIFE, 0.0, 1.0)


## Height of the waves here, above or below the still water, metres.
func height_at(x: float, z: float) -> float:
	var h := 0.0
	for s in _src:
		var dx := x - s.x
		var dz := z - s.y
		var d := sqrt(dx * dx + dz * dz)
		var age := time - s.z
		var r := SPEED * age
		var w := 2.5 + 0.08 * r
		var u := d - r
		if absf(u) > 3.0 * w:
			continue
		# Nothing right at the source: the wave builds as the ring moves away
		# (and whatever made it does not get bounced by its own wake).
		var fall := s.w / sqrt(1.0 + 0.25 * r) * clampf(1.0 - age / LIFE, 0.0, 1.0) * smoothstep(0.0, 10.0, r)
		h += fall * exp(-u * u / (w * w)) * sin(K * u)
	return h


func clear() -> void:
	_src.clear()


func _process(delta: float) -> void:
	time += delta
	var i := 0
	while i < _src.size():
		if time - _src[i].z > LIFE:
			_src.remove_at(i)
		else:
			i += 1
	var arr := PackedVector4Array()
	arr.resize(MAX)
	for k in range(_src.size()):
		arr[k] = _src[k]
	for m in materials:
		m.set_shader_parameter("wave_src", arr)
		m.set_shader_parameter("wave_count", _src.size())
		m.set_shader_parameter("wave_time", time)
