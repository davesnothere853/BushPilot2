extends Node
## The planes you own. One is the plane you are flying; the others are parked
## where you left them (you see them there) or stored in a hangar. Each keeps
## its own fuel, damage, tyres and gear, and the jobs loaded in it. Saved in
## user://fleet.cfg.
##
## Hangars stand at the bigger strips (terrain HANGARS). Stopped at one, you can
## put the plane away, take another out, or buy another plane.

const PlaneScript = preload("res://scripts/plane.gd")
const PlaneVisual = preload("res://scripts/plane_visual.gd")
const PlaneTypes = preload("res://scripts/plane_types.gd")
const DC3Visual = preload("res://scripts/dc3_visual.gd")
const SAVE := "user://fleet.cfg"
const PRICE := 28000
const LETTERS := "ABCDEFGHJKLMNPRSTUVWXYZ"

signal changed

var plane: Node3D          # the plane you fly
var jobs: Node
var terrain: RefCounted
var world: Node3D
var builds: Node                  # builds.gd: hangars you put up at your own strips
## Each: {reg, state (plane.to_dict), where: "flying"/"parked"/"hangar", strip, carried}
var planes: Array = []
var active := 0
var _parked_nodes := {}    # reg -> plane node (with its visual)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not planes.is_empty():
		save_fleet()


func setup() -> void:
	load_fleet()
	if planes.is_empty():
		planes.append({"reg": plane.reg, "state": plane.to_dict(), "where": "flying", "strip": Game.last_strip, "carried": []})
		active = 0
	else:
		var me: Dictionary = planes[active]
		plane.from_dict(me["state"])
	_refresh_parked()


## Save the plane you are flying into the list (call before saving or switching).
func sync_active() -> void:
	var me: Dictionary = planes[active]
	me["state"] = plane.to_dict()
	me["reg"] = plane.reg
	me["where"] = "flying"
	me["carried"] = jobs.carried.duplicate(true)


func save_fleet() -> void:
	sync_active()
	var cf := ConfigFile.new()
	cf.set_value("fleet", "planes", planes)
	cf.set_value("fleet", "active", active)
	cf.save(SAVE)


func load_fleet() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	var p = cf.get_value("fleet", "planes", [])
	planes = p if p is Array else []
	active = clampi(int(cf.get_value("fleet", "active", 0)), 0, maxi(planes.size() - 1, 0))


## The strip with a hangar where the plane is stopped, or -1.
func hangar_here() -> int:
	var k: int = jobs.strip_here()
	if k >= 0 and (has_hangar(k) or Game.sandbox):
		return k
	return -1


func has_hangar(k: int) -> bool:
	return String(terrain.strips[k]["name"]) in terrain.HANGARS or (builds != null and builds.has_hangar(k))


## Planes parked outside at strip k (or anywhere when k is -1).
func parked_at(k: int) -> Array:
	var out: Array = []
	for i in range(planes.size()):
		var d: Dictionary = planes[i]
		if i != active and d["where"] == "parked" and (k < 0 or int(d["strip"]) == k):
			out.append(i)
	return out


## Swap into plane i (it must be in the hangar or parked at this strip). The
## plane you were in stays here: in the hangar if `store`, else parked.
func switch_to(i: int, store: bool) -> String:
	var k: int = jobs.strip_here()
	if k < 0:
		return "Stop at an airstrip first."
	var target: Dictionary = planes[i]
	if int(target["strip"]) != k:
		return "%s is at %s." % [target["reg"], terrain.strips[int(target["strip"])]["name"]]
	sync_active()
	var me: Dictionary = planes[active]
	me["where"] = "hangar" if store else "parked"
	me["strip"] = k
	var was_parked: bool = target["where"] == "parked"
	active = i
	target["where"] = "flying"
	plane.from_dict(target["state"])
	jobs.carried = (target.get("carried", []) as Array).duplicate(true)
	jobs._stow()
	if was_parked:
		var st: Dictionary = target["state"]
		plane.place_parked(st["pos"], st["basis"])
	else:
		plane.place_on_strip(k)
	save_fleet()
	jobs.save_career()
	_refresh_parked()
	changed.emit()
	return ""


## Buy the plane sitting right there on the apron and take it: it joins the
## fleet parked where it stands, and you're switched into it. Your old plane
## stays parked where you left it. The caller frees the sale display node.
func buy_parked(sale: Node3D, price: int) -> String:
	var k: int = jobs.strip_here()
	if k < 0:
		return "Come back when you're on the field."
	if not Game.sandbox and jobs.money < price:
		return "You need $%d." % price
	if not Game.sandbox:
		jobs.money -= price
	sync_active()
	var st: Dictionary = sale.to_dict()
	planes.append({"reg": st["reg"], "state": st, "where": "parked", "strip": k, "carried": []})
	var err := switch_to(planes.size() - 1, false)
	changed.emit()
	return err


## Buy another plane; it waits in the hangar here.
func buy(t: String = "wolverine") -> String:
	var k := hangar_here()
	if k < 0:
		return "Planes are sold at a strip with a hangar."
	var price: int = int(PlaneTypes.spec(t)["price"])
	if jobs.money < price:
		return "You need $%d." % price
	jobs.money -= price
	var fresh := PlaneScript.new()
	fresh.apply_type(t)
	fresh.reg = _new_reg()
	var st: Dictionary = fresh.to_dict()
	fresh.free()
	planes.append({"reg": st["reg"], "state": st, "where": "hangar", "strip": k, "carried": []})
	save_fleet()
	jobs.save_career()
	changed.emit()
	return ""


func _new_reg() -> String:
	var used := {}
	for d in planes:
		used[d["reg"]] = true
	while true:
		var r := "C-G"
		for _i in range(3):
			r += LETTERS[randi() % LETTERS.length()]
		if not used.has(r):
			return r
	return "C-GXXX"


## Show every plane parked outside, where it was left.
func _refresh_parked() -> void:
	var want := {}
	for i in parked_at(-1):
		want[String(planes[i]["reg"])] = i
	for reg in _parked_nodes.keys():
		if not want.has(reg):
			(_parked_nodes[reg] as Node).queue_free()
			_parked_nodes.erase(reg)
	for reg in want.keys():
		var d: Dictionary = planes[want[reg]]
		var node: Node3D = _parked_nodes.get(reg)
		if node == null:
			node = PlaneScript.new()
			node.name = "Parked_" + reg
			node.terrain = terrain
			world.add_child(node)
			var ptype := String(d["state"].get("type", "wolverine"))
			var vpath := String(PlaneTypes.spec(ptype).get("visual", "")) if ptype != "wolverine" else ""
			if ptype == "dc3":
				node.apply_type("dc3")
				var dv := DC3Visual.new()
				node.add_child(dv)
			elif vpath != "":
				node.apply_type(ptype)
				var tvis: Node3D = load(vpath).new()
				tvis.plane = node
				node.add_child(tvis)
			else:
				var vis := PlaneVisual.new()
				vis.plane = node
				node.add_child(vis)
			_parked_nodes[reg] = node
		node.from_dict(d["state"])
		var st: Dictionary = d["state"]
		node.place_parked(st["pos"], st["basis"])
		node.engine.set_cold_and_dark(5.0)
		# A real plane left where you parked it (on wheels, floats or skis):
		# its flight model keeps running so it sits on the ground or water.
		node.frozen = false
		node.may_doze = true


## Planes left on the water rock on the waves (and on passing wakes).
func _process(_delta: float) -> void:
	if world == null or world.waves == null:
		return
	for reg in _parked_nodes.keys():
		var node: Node3D = _parked_nodes[reg]
		if not node.is_amphib():
			continue
		var p: Vector3 = node.get("_cur_xf").origin
		var wl: float = terrain.water_level_at(p.x, p.z)
		if wl < -1.0e8:
			continue
		var h: float = world.waves.height_at(p.x, p.z)
		var t := Time.get_ticks_msec() * 0.001
		var bob := Vector3(0, h + 0.02 * sin(t * 1.3 + p.x), 0)
		var rock := Basis(Vector3.FORWARD, 0.015 * sin(t * 0.9 + p.z) + h * 0.15)
		var xf: Transform3D = node.get("_cur_xf")
		node.global_transform = Transform3D(xf.basis * rock, xf.origin + bob)
