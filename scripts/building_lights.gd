extends Node3D
## Lights in buildings, each lot on a switch you work on foot: the hangars'
## overhead lights (switch by the door), and an oil lantern in a log cabin.

var groups: Array = []      # {switch: Vector3, lights: [OmniLight3D], glow: MeshInstance3D, on: bool, kind: String}
var _glow_mat: StandardMaterial3D
var _lantern_mat: StandardMaterial3D


func _ready() -> void:
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.albedo_color = Color(1.0, 0.98, 0.9)
	_lantern_mat = StandardMaterial3D.new()
	_lantern_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lantern_mat.albedo_color = Color(1.0, 0.7, 0.3)


## A lot of lights on one switch. `lamps`: where the light comes from;
## `fixtures`: [[Transform3D, size]] of the glowing tubes or the lantern glass.
func add_group(switch_at: Vector3, lamps: Array, fixtures: Array, kind: String = "hangar") -> int:
	var g := {"switch": switch_at, "lights": [], "on": false, "kind": kind}
	for p in lamps:
		var l := OmniLight3D.new()
		l.position = p
		if kind == "lantern":
			l.light_color = Color(1.0, 0.72, 0.38)
			l.light_energy = 1.3
			l.omni_range = 7.0
			l.shadow_enabled = true
		else:
			l.light_color = Color(1.0, 0.97, 0.9)
			l.light_energy = 2.0
			l.omni_range = 14.0
			l.shadow_enabled = false
		l.visible = false
		add_child(l)
		(g["lights"] as Array).append(l)
	var bm := MeshKit.new()
	for f in fixtures:
		bm.box(f[0], f[1], Color.WHITE)
	if not bm.is_empty():
		var mi := bm.instance("Glow")
		mi.material_override = _lantern_mat if kind == "lantern" else _glow_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		g["glow"] = mi
	groups.append(g)
	return groups.size() - 1


const MeshKit = preload("res://scripts/meshkit.gd")


func set_on(i: int, on: bool) -> void:
	var g: Dictionary = groups[i]
	g["on"] = on
	for l in g["lights"]:
		(l as OmniLight3D).visible = on
	if g.has("glow"):
		(g["glow"] as MeshInstance3D).visible = on


func toggle(i: int) -> String:
	var g: Dictionary = groups[i]
	set_on(i, not bool(g["on"]))
	if g["kind"] == "lantern":
		return "You light the lantern." if g["on"] else "You blow the lantern out."
	return "Click. The lights come on." if g["on"] else "Click. Lights off."


## The switch within reach of `p`, or -1.
func switch_near(p: Vector3, reach: float = 1.3) -> int:
	for i in range(groups.size()):
		var s: Vector3 = groups[i]["switch"]
		if s.distance_to(p + Vector3(0, 1.2, 0)) < reach:
			return i
	return -1


func prompt_for(i: int) -> String:
	var g: Dictionary = groups[i]
	if g["kind"] == "lantern":
		return "%s  %s the lantern" % [Game.hint("interact"), "Put out" if g["on"] else "Light"]
	return "%s  Lights %s" % [Game.hint("interact"), "off" if g["on"] else "on"]


