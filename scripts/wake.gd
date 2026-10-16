extends MultiMeshInstance3D
## Foam left on water: patches dropped behind whatever touches it (tyres,
## floats, a hull) that spread out, break up and fade. One for the whole world.

const MAX := 700
const LIFE := 10.0

var _born := PackedFloat32Array()
var _pos := PackedVector3Array()
var _yaw := PackedFloat32Array()
var _size := PackedVector2Array()      # width, length when dropped
var _spread := PackedFloat32Array()   # how fast it widens, m/s
var _str := PackedFloat32Array()
var _next := 0
var _clock := 0.0
var _live := 0


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/wake.gdshader")
	pm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = pm
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	multimesh = mm
	custom_aabb = AABB(Vector3(-1.0e5, -1.0e3, -1.0e5), Vector3(2.0e5, 1.0e4, 2.0e5))
	_born.resize(MAX)
	_born.fill(-100.0)
	_pos.resize(MAX)
	_yaw.resize(MAX)
	_size.resize(MAX)
	_spread.resize(MAX)
	_str.resize(MAX)


## Drop a patch at `p` (on the surface), lying along `dir`.
func drop(p: Vector3, dir: Vector3, width: float, length: float, strength: float, spread: float = 0.6) -> void:
	var i := _next
	_next = (_next + 1) % MAX
	_born[i] = _clock
	_pos[i] = p + Vector3(0, 0.03 + 0.0004 * float(i % 20), 0)
	_yaw[i] = atan2(dir.x, dir.z)
	_size[i] = Vector2(width, length)
	_spread[i] = spread
	_str[i] = clampf(strength, 0.0, 1.0)
	_live = mini(_live + 1, MAX)


func _process(delta: float) -> void:
	_clock += delta
	if _live == 0:
		return
	var mm := multimesh
	var shown := 0
	# Slots are reused in a ring, so the live ones are the newest `_live`.
	mm.visible_instance_count = MAX if _live > 0 else 0
	for i in range(MAX):
		var age := _clock - _born[i]
		if age >= LIFE or age < 0.0:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(0.0001, 1, 0.0001)), Vector3(0, -1000, 0)))
			continue
		shown += 1
		var k := age / LIFE
		var w := _size[i].x + _spread[i] * age * 2.0
		var l := _size[i].y * (1.0 + 0.25 * age)
		var basis := Basis(Vector3.UP, _yaw[i]) * Basis.from_scale(Vector3(w, 1.0, l))
		mm.set_instance_transform(i, Transform3D(basis, _pos[i]))
		mm.set_instance_custom_data(i, Color(k, _str[i], float(i % 37) / 37.0, 0.0))
	if shown == 0:
		_live = 0
		mm.visible_instance_count = 0
