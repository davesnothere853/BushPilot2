extends Node3D
## A patch of Gerstner-wave water (the pond now; lakes and the coast later).
## The shader (water_gerstner.gdshader) displaces the surface; THIS script
## computes the same wave sum on the CPU, so the flight model's floats and
## anything buoyant ride exactly the water you see.
##
## Sea state: calm pond 0.2-0.3, lake chop 0.5-0.8, open coast 1.0+.

const SHADER = preload("res://shaders/water_gerstner.gdshader")

## xy direction, z steepness, w wavelength - MUST match the shader defaults.
const WAVES := [
	Vector4(1.0, 0.0, 0.35, 14.0),
	Vector4(0.84, 0.54, 0.30, 9.0),
	Vector4(0.93, -0.37, 0.25, 5.5),
	Vector4(0.58, 0.81, 0.22, 3.2),
	Vector4(-0.26, 0.97, 0.18, 1.7),
]

var level := 0.0                 # still-water height
var sea_state := 0.25
var _mat: ShaderMaterial
var _t := 0.0


## A round patch of `radius` metres at still-water height `lvl`.
func setup(center: Vector3, radius: float, lvl: float, state: float = 0.25) -> void:
	level = lvl
	sea_state = state
	position = Vector3(center.x, lvl, center.z)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("amp_scale", state)
	var mesh := PlaneMesh.new()
	# Fine enough that the shortest wave still shows (~4 verts per 1.7 m).
	mesh.size = Vector2(radius * 2.0, radius * 2.0)
	mesh.subdivide_width = int(radius * 2.0 / 0.45)
	mesh.subdivide_depth = int(radius * 2.0 / 0.45)
	mesh.material = _mat
	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	_t += delta


## The wave surface height at a world point - same sum as the shader runs.
## (Gerstner displaces horizontally too; for float physics the vertical
## field at the query point is accurate enough at these sea states.)
func surface_height(x: float, z: float) -> float:
	var h := level
	var rot_waves := _current_waves()
	for wv in rot_waves:
		var w: Vector4 = wv
		var k: float = TAU / w.w
		var c: float = sqrt(9.8 / k)
		var d := Vector2(w.x, w.y).normalized()
		var f: float = k * (d.dot(Vector2(x, z)) - c * _t)
		h += (w.z / k * sea_state) * sin(f)
	return h


func _current_waves() -> Array:
	if _mat == null:
		return WAVES
	var out: Array = []
	for n in ["wave_a", "wave_b", "wave_c", "wave_d", "wave_e"]:
		out.append(_mat.get_shader_parameter(n))
	return out
