extends Node3D
## Power for the drifts (DESIGN_NOTES 90): a little portable generator on
## gas, and strings of rope light hung one after another from it along the
## tunnel. A string lights when its chain runs back to a running generator.
##
## generators: [{xf, fuel, on}]   strings: [{a, b, from}] where `from` is
## "g<i>" (plugged into generator i) or "s<j>" (into the end of string j).

const MeshKit = preload("res://scripts/meshkit.gd")
const SAVE := "user://power.cfg"
const GEN_TANK := 5.0              # litres
const GEN_BURN := 0.004            # litres a second (game-quick)
const STRING_LEN := 15.0           # metres of rope light a string
const PLUG_REACH := 2.5            # how close to a generator / string end to plug in
const LIGHT_EVERY := 5.0           # an actual light every few metres
const MAX_LIGHTS := 40             # across the whole map, nearest first

var terrain: RefCounted
var inv: Node
var say: Callable                  # func(text)
var generators: Array = []
var strings: Array = []
var _gen_nodes: Array = []         # [root, smoke]
var _string_nodes: Array = []      # [MeshInstance3D wire, MeshInstance3D bulbs, Array lights]
var _lit: Array = []               # bool per string
var _bulb_on: StandardMaterial3D
var _bulb_off: StandardMaterial3D
var _dirty := false
var _save_t := 0.0
var _relight_t := 0.0
var _pending := ""                 # plugged in, being walked out: "g<i>" / "s<j>"


func _ready() -> void:
	_bulb_on = StandardMaterial3D.new()
	_bulb_on.albedo_color = Color(1.0, 0.85, 0.5)
	_bulb_on.emission_enabled = true
	_bulb_on.emission = Color(1.0, 0.78, 0.4)
	_bulb_on.emission_energy_multiplier = 3.0
	_bulb_off = StandardMaterial3D.new()
	_bulb_off.albedo_color = Color(0.45, 0.42, 0.35)


# ------------------------------------------------------------------------------
#  What E does here
# ------------------------------------------------------------------------------
func target(p: Vector3, tool: String, key: String) -> Array:
	if tool == "rope_light" and _pending != "":
		var a0 := _plug_point(_pending)
		var d := a0.distance_to(Vector3(p.x, p.y + 1.9, p.z))
		if d > STRING_LEN + 0.5:
			return ["", "The string's only %.0f m: it won't reach (%.0f m). Walk back toward where you plugged it in." % [STRING_LEN, d]]
		return ["rope", "%s  Hang the rope light here (%.0f m)" % [key, d]]
	var gi := gen_near(p)
	if gi >= 0:
		var g: Dictionary = generators[gi]
		if tool == "gas_can":
			return ["gen_fuel", "%s  Fill the generator (%.1f of %.0f L)" % [key, float(g["fuel"]), GEN_TANK]]
		if tool == "rope_light":
			return ["rope", "%s  Plug a string of rope light into the generator, then walk it out" % key]
		if tool == "":
			return ["gen_toggle", "%s  %s the generator (%.1f L)   %s pick it up" % [key, "Stop" if bool(g["on"]) else "Start", float(g["fuel"]), Game.hint("door")]]
	if tool == "generator":
		return ["gen_place", "%s  Set the generator down here" % key]
	if tool == "rope_light":
		var end := _end_near(p)
		if end != "":
			return ["rope", "%s  Hang rope light on from here (up to %.0f m)" % [key, STRING_LEN]]
		return ["", "Start rope light at a generator or at the end of a string already hung."]
	return []


func act(a: String, p: Vector3, front: Vector3, yaw: float) -> String:
	match a:
		"gen_place":
			if inv == null or not inv.holding("generator"):
				return ""
			inv.remove("generator", 1)
			var at := Vector3(front.x, p.y, front.z)      # where he stands: a drift floor or the open ground
			generators.append({"xf": Transform3D(Basis(Vector3.UP, yaw), at), "fuel": 0.0, "on": false})
			_spawn_gen(generators.size() - 1)
			_dirty = true
			return "Generator down. It's dry: pour a gas can in, then %s to start it." % Game.hint("interact")
		"gen_toggle":
			var gi := gen_near(p)
			if gi < 0:
				return ""
			var g: Dictionary = generators[gi]
			if bool(g["on"]):
				g["on"] = false
				_relight()
				_dirty = true
				return "Generator off."
			if float(g["fuel"]) <= 0.02:
				return "It won't start: the tank's dry."
			g["on"] = true
			_relight()
			_dirty = true
			return "Generator running."
		"gen_fuel":
			var gi2 := gen_near(p)
			if gi2 < 0 or inv == null or not inv.holding("gas_can"):
				return ""
			var g2: Dictionary = generators[gi2]
			var took := GEN_TANK - float(g2["fuel"])
			if took < 0.1:
				return "The generator's tank is full."
			var got: float = inv.pour_can(took)
			g2["fuel"] = float(g2["fuel"]) + got
			_dirty = true
			return "Filled the generator (%.1f L).%s" % [got, "" if inv.holding("gas_can_empty") else " %.0f L left in the can." % inv.can_l]
		"rope":
			if inv == null or not inv.holding("rope_light"):
				return ""
			if _pending == "":
				_pending = _end_near(p)
				if _pending == "":
					return ""
				return "Plugged in. Walk it out along the drift and %s to hang it (up to %.0f m)." % [Game.hint("interact"), STRING_LEN]
			var from := _pending
			_pending = ""
			var a0 := _plug_point(from)
			var b := Vector3(p.x, 0, p.z)
			b.y = _ceiling_at(b, p.y)
			if a0.distance_to(b) > STRING_LEN:
				b = a0 + (b - a0).normalized() * STRING_LEN
			if a0.distance_to(b) < 1.5:
				return "Walk it out further before you hang it."
			inv.remove("rope_light", 1)
			strings.append({"a": a0, "b": b, "from": from})
			_spawn_string(strings.size() - 1)
			_relight()
			_dirty = true
			return "Rope light hung: %.0f m.%s" % [a0.distance_to(b), " It's lit." if _lit[strings.size() - 1] else " Dark: start the generator."]
	return ""


## Pick a generator back up (door key near it).
func take_generator(p: Vector3) -> String:
	var gi := gen_near(p)
	if gi < 0 or inv == null:
		return ""
	if inv.add("generator", 1, true) <= 0:
		return "Too much on you to carry the generator."
	(_gen_nodes[gi][0] as Node).queue_free()
	_gen_nodes.remove_at(gi)
	generators.remove_at(gi)
	# strings plugged into later generators shift down one
	for s in strings:
		var f: String = s["from"]
		if f.begins_with("g"):
			var k := int(f.substr(1))
			if k == gi:
				s["from"] = "x"          # unplugged
			elif k > gi:
				s["from"] = "g%d" % (k - 1)
	_relight()
	_dirty = true
	return "Picked up the generator."


func gen_near(p: Vector3) -> int:
	for i in range(generators.size()):
		if p.distance_to((generators[i]["xf"] as Transform3D).origin) < PLUG_REACH:
			return i
	return -1


## A generator or a string end within reach: "g<i>" / "s<j>", or "".
func _end_near(p: Vector3) -> String:
	var gi := gen_near(p)
	if gi >= 0:
		return "g%d" % gi
	var best := ""
	var bd := PLUG_REACH
	for j in range(strings.size()):
		var e: Vector3 = strings[j]["b"]
		var d := Vector2(p.x - e.x, p.z - e.z).length()
		if d < bd and absf(p.y - e.y) < 3.5:
			bd = d
			best = "s%d" % j
	return best


func _plug_point(from: String) -> Vector3:
	if from.begins_with("g"):
		return (generators[int(from.substr(1))]["xf"] as Transform3D) * Vector3(0, 0.55, 0)
	return strings[int(from.substr(1))]["b"]


## Where to hang it: up near the back (roof of a drift), or head height in
## the open.
func _ceiling_at(q: Vector3, feet_y: float) -> float:
	return feet_y + 1.9


# ------------------------------------------------------------------------------
#  Running
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	var changed := false
	for i in range(generators.size()):
		var g: Dictionary = generators[i]
		if bool(g["on"]):
			g["fuel"] = maxf(float(g["fuel"]) - GEN_BURN * delta, 0.0)
			if float(g["fuel"]) <= 0.0:
				g["on"] = false
				changed = true
				if say.is_valid():
					say.call("The generator's run dry. The lights are out.")
		var sm = _gen_nodes[i][1]
		if sm != null and (sm as CPUParticles3D).emitting != bool(g["on"]):
			(sm as CPUParticles3D).emitting = bool(g["on"])
	_relight_t += delta
	if changed or _relight_t > 1.0:
		_relight_t = 0.0
		_relight()
	_save_t += delta
	if _dirty and _save_t > 6.0:
		_save_t = 0.0
		_dirty = false
		save()


## Which strings have power, and turn their bulbs and lights on or off.
func _relight() -> void:
	_lit.resize(strings.size())
	for j in range(strings.size()):
		_lit[j] = _powered(j, 0)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cp: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	# real lights only on the nearest lit strings
	var order: Array = []
	for j in range(strings.size()):
		var mid: Vector3 = (strings[j]["a"] + strings[j]["b"]) * 0.5
		order.append([cp.distance_to(mid), j])
	order.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var budget := MAX_LIGHTS
	for o in order:
		var j: int = o[1]
		var on: bool = _lit[j]
		var sn: Array = _string_nodes[j]
		(sn[1] as MeshInstance3D).material_override = _bulb_on if on else _bulb_off
		for l in sn[2]:
			var lit_here: bool = on and budget > 0
			(l as OmniLight3D).visible = lit_here
			if lit_here:
				budget -= 1


func _powered(j: int, depth: int) -> bool:
	if depth > 200:
		return false
	var f: String = strings[j]["from"]
	if f.begins_with("g"):
		var gi := int(f.substr(1))
		return gi < generators.size() and bool(generators[gi]["on"])
	if f.begins_with("s"):
		return _powered(int(f.substr(1)), depth + 1)
	return false


func lit_count() -> int:
	var n := 0
	for b in _lit:
		if b:
			n += 1
	return n


# ------------------------------------------------------------------------------
#  Models
# ------------------------------------------------------------------------------
## A small open-frame generator: tubular cage, red tank on top, engine one
## side and the alternator the other, a panel with outlets.
static func gen_mesh(k: RefCounted) -> void:
	var frame := Color(0.12, 0.12, 0.13)
	var red := Color(0.72, 0.12, 0.08)
	for x in [-0.32, 0.32]:
		for z in [-0.22, 0.22]:
			k.box_at(Vector3(x, 0.27, z), Vector3(0.03, 0.54, 0.03), frame)
		k.box_at(Vector3(x, 0.53, 0), Vector3(0.03, 0.03, 0.47), frame)
		k.box_at(Vector3(x, 0.02, 0), Vector3(0.03, 0.03, 0.47), frame)
	k.box_at(Vector3(0, 0.47, 0), Vector3(0.5, 0.12, 0.32), red)                       # tank
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.1, 0.53, 0.05)), 0.035, 0.035, 0.04, 8, frame)
	k.box_at(Vector3(-0.13, 0.22, 0), Vector3(0.26, 0.28, 0.3), Color(0.2, 0.2, 0.21))   # engine
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.16, 0.2, 0)), 0.13, 0.13, 0.26, 10, red.darkened(0.2))   # alternator
	k.box_at(Vector3(0.16, 0.2, -0.2), Vector3(0.22, 0.2, 0.02), Color(0.75, 0.75, 0.72))   # panel
	k.box_at(Vector3(-0.26, 0.3, 0.14), Vector3(0.08, 0.08, 0.1), Color(0.3, 0.3, 0.3))     # muffler


func _spawn_gen(i: int) -> void:
	var root := Node3D.new()
	root.name = "Generator%d" % i
	add_child(root)
	root.global_transform = generators[i]["xf"]
	var k := MeshKit.new()
	gen_mesh(k)
	root.add_child(k.instance("Gen"))
	var sm := CPUParticles3D.new()
	sm.position = Vector3(-0.26, 0.36, 0.2)
	sm.amount = 10
	sm.lifetime = 1.6
	sm.emitting = false
	sm.direction = Vector3.UP
	sm.spread = 15.0
	sm.initial_velocity_min = 0.4
	sm.initial_velocity_max = 0.7
	sm.scale_amount_min = 0.08
	sm.scale_amount_max = 0.2
	var smm := SphereMesh.new()
	smm.radius = 0.2
	smm.height = 0.4
	smm.radial_segments = 6
	smm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.3, 0.3, 0.3, 0.3)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smm.material = smat
	sm.mesh = smm
	root.add_child(sm)
	_gen_nodes.append([root, sm])


## A string: a thin cord sagging between its ends, small bulbs along it, and
## a real light every few metres.
func _spawn_string(j: int) -> void:
	var a: Vector3 = strings[j]["a"]
	var b: Vector3 = strings[j]["b"]
	var wire := MeshKit.new()
	var bulbs := MeshKit.new()
	var n := maxi(int(a.distance_to(b) / 0.5), 2)
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var q := a.lerp(b, t) - Vector3(0, 0.25 * 4.0 * t * (1.0 - t), 0)     # sag
		_cord(wire, prev, q, 0.008, Color(0.15, 0.15, 0.15))
		bulbs.box_at(q - Vector3(0, 0.02, 0), Vector3(0.025, 0.025, 0.025), Color(1, 1, 1))
		prev = q
	var wm := wire.instance("Cord")
	wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wm)
	var bm := bulbs.instance("Bulbs")
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bm)
	var lights: Array = []
	var m := maxi(int(a.distance_to(b) / LIGHT_EVERY), 1)
	for i in range(m):
		var t2 := (float(i) + 0.5) / float(m)
		var l := OmniLight3D.new()
		l.position = a.lerp(b, t2) - Vector3(0, 0.3, 0)
		l.light_color = Color(1.0, 0.82, 0.55)
		l.light_energy = 1.4
		l.omni_range = 7.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		lights.append(l)
	_string_nodes.append([wm, bm, lights])


static func _cord(k: RefCounted, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.001:
		return
	var y := d / len
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	k.cylinder(Transform3D(Basis(x, y, x.cross(y)), a), r, r, len, 4, col, false)


# ------------------------------------------------------------------------------
#  Saving
# ------------------------------------------------------------------------------
func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("p", "generators", generators)
	cf.set_value("p", "strings", strings)
	cf.save(SAVE)


func load_all() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	generators = cf.get_value("p", "generators", [])
	strings = cf.get_value("p", "strings", [])
	for i in range(generators.size()):
		_spawn_gen(i)
	for j in range(strings.size()):
		_spawn_string(j)
	_relight()
