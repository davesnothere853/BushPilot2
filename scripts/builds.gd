extends Node3D
## Build and clear, Out of Ore style. On foot, open the Build page (B) to:
##  - lay out a bush strip where you stand, along the way you face: the trees
##    in the way are cut for you (paid per tree), the edges marked with tyres;
##  - put up a log cabin (warm up inside), a hangar at one of your strips (keep
##    planes there), or a camp at a claim you own (it works faster).
## Cabins and camps take logs: fell trees with the chainsaw to get them.
## Everything is saved in user://builds.cfg; your strips are read back by the
## terrain when the world is made, so they are real strips (jobs fly to them).

const MeshKit = preload("res://scripts/meshkit.gd")
const Flora = preload("res://scripts/flora.gd")
const SAVE := "user://builds.cfg"

const STRIP_LEN := [300.0, 400.0, 500.0]
const STRIP_W := 14.0
const STRIP_BASE := 1500          # $ to grade and mark a strip
const STRIP_PER_TREE := 35        # $ for each tree cut out of the way
const MAX_GRADE := 0.07
const MAX_BUMP := 2.5             # m the ground may stray from a straight line

## kind: [name, price, logs, what it does]
const KINDS := {
	"bushcamp": ["Bush camp", 0, 0, "Tent, campfire, a cooler of beer and a camp chair, out of the plane. Sleep, warm up, have a beer. One at a time: a new one packs up the old."],
	"cabin": ["Log cabin", 800, 12, "Saddle-notched log cabin with a porch, wood stove and bunk. Walk inside to thaw out."],
	"loghouse": ["Log house", 2600, 30, "Big log house: full-width porch, stone chimney, windows all round. Warm inside."],
	"polebarn": ["Steel pole barn", 14000, 0, "12 x 18 m machine shed, ribbed steel on wood posts, 6 m sliding doors you can drive the equipment through."],
	"poleshed": ["Open pole shed", 6000, 0, "12 x 8 m open-front steel shed to park machines out of the weather."],
	"hangar": ["Hangar", 9000, 20, "Keep planes here. Must stand beside one of your strips."],
	"camp": ["Mining camp", 2500, 10, "Your claim here works half again as fast. Must stand at a claim you own."],
}

const Models = preload("res://scripts/building_models.gd")
## kind: [width (X), depth (Z), wall height, door width] for footprint, pad and walls.
const FOOT := {
	"cabin": [7.0, 6.0, 2.7, 1.3],
	"loghouse": [10.0, 8.0, 3.0, 1.3],
	"polebarn": [12.0, 18.0, 4.8, 6.0],
	"poleshed": [12.0, 8.0, 4.4, 12.0],
	"hangar": [22.0, 18.0, 6.5, 21.2],
	"camp": [12.0, 10.0, 0.0, 0.0],
	"bushcamp": [8.0, 8.0, 0.0, 0.0],
}
const PORCH := {"cabin": 1.8, "loghouse": 2.4}
const WARM := ["cabin", "loghouse"]

var terrain: RefCounted
var world: Node3D
var jobs: Node
var mining: Node
var walker: Node3D
var plane: Node3D
var lights: Node                 # building_lights.gd (switches in cabins and hangars)
var logs := 0
var items: Array = []             # {kind, pos, yaw, strip}
var _nodes: Array = []
var _pending_door: Array = []
signal camp_changed


func _ready() -> void:
	_load()
	for it in items:
		_spawn(it)


# ------------------------------------------------------------------------------
#  Bush strips
# ------------------------------------------------------------------------------
## Heading (degrees) for someone facing along `look_yaw` (the walker's camera yaw).
static func heading_of(look_yaw: float) -> float:
	return fposmod(-rad_to_deg(look_yaw), 360.0)


## Survey a strip starting at `start`, `len` metres along `heading`. Returns
## {ok, why, trees, price, centre, slope} without building anything.
func survey(start: Vector3, heading: float, length: float) -> Dictionary:
	var hr := deg_to_rad(heading)
	var dir := Vector2(sin(hr), -cos(hr))
	var a := Vector2(start.x, start.z)
	var b := a + dir * length
	var ha: float = terrain.height_at(a.x, a.y)
	var hb: float = terrain.height_at(b.x, b.y)
	var out := {"ok": false, "why": "", "trees": 0, "price": 0, "heading": heading, "length": length}
	var worst := 0.0
	for i in range(21):
		var f := float(i) / 20.0
		var p := a.lerp(b, f)
		for side in [-1.0, 0.0, 1.0]:
			var q: Vector2 = p + Vector2(-dir.y, dir.x) * float(side) * STRIP_W * 0.5
			if terrain.water_level_at(q.x, q.y) > -1.0e8:
				out["why"] = "There's water in the way."
				return out
			var h: float = terrain.height_at(q.x, q.y)
			worst = maxf(worst, absf(h - lerpf(ha, hb, f)))
		if terrain.strip_index_at(p.x, p.y, 40.0) >= 0:
			out["why"] = "That runs into another strip."
			return out
	var grade := absf(hb - ha) / length
	if grade > MAX_GRADE:
		out["why"] = "Too steep: %d%% grade (%d%% at most)." % [int(grade * 100.0), int(MAX_GRADE * 100.0)]
		return out
	if worst > MAX_BUMP:
		out["why"] = "Too rough: the ground strays %.1f m from level. Try another line." % worst
		return out
	# Count the trees to cut.
	var trees := 0
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(40, 40)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(40, 40)
	var mid := (a + b) * 0.5
	for j in range(int(floor((lo.y + terrain.half) / Flora.G)), int(ceil((hi.y + terrain.half) / Flora.G)) + 1):
		for i in range(int(floor((lo.x + terrain.half) / Flora.G)), int(ceil((hi.x + terrain.half) / Flora.G)) + 1):
			var tr := Flora.tree_at(terrain, i, j)
			if tr.is_empty() or Flora.felled.has(Flora.key(i, j)):
				continue
			var tp: Vector3 = tr["pos"]
			var d := Vector2(tp.x, tp.z) - mid
			if absf(d.dot(dir)) < length * 0.5 + 30.0 and absf(d.dot(Vector2(-dir.y, dir.x))) < STRIP_W * 0.5 + 30.0:
				trees += 1
	out["trees"] = trees
	out["price"] = STRIP_BASE + trees * STRIP_PER_TREE
	out["centre"] = Vector3(mid.x, (ha + hb) * 0.5, mid.y)
	out["slope"] = (hb - ha) / length
	out["ok"] = true
	return out


## Build the strip a survey found. Returns "" or why not.
func build_strip(sv: Dictionary, strip_name: String = "") -> String:
	if not bool(sv.get("ok", false)):
		return String(sv.get("why", "Can't build there."))
	var price: int = sv["price"]
	if jobs.money < price:
		return "You need $%d." % price
	jobs.money -= price
	var n := 1
	for s in terrain.strips:
		if bool(s.get("player", false)):
			n += 1
	if strip_name == "":
		strip_name = "Bush Strip %d" % n
	var d := {"name": strip_name, "pos": sv["centre"], "heading": float(sv["heading"]),
		"length": float(sv["length"]), "slope": float(sv["slope"])}
	var k: int = terrain.add_player_strip(d)
	var it := {"kind": "strip", "pos": sv["centre"], "yaw": 0.0, "strip": k, "def": d}
	items.append(it)
	_spawn(it)
	world.paint_strips()
	if world.vegetation != null:
		world.vegetation.refresh_area(sv["centre"], float(sv["length"]) * 0.5 + 120.0)
	_save()
	jobs.save_career()
	return ""


# ------------------------------------------------------------------------------
#  Buildings
# ------------------------------------------------------------------------------
## Why `kind` can't go up at `p` right now, or "".
func cannot_build(kind: String, p: Vector3) -> String:
	var spec: Array = KINDS[kind]
	if terrain.water_level_at(p.x, p.z) > -1.0e8:
		return "Not in the water."
	if terrain.strip_index_at(p.x, p.z, 6.0) >= 0:
		return "Not on the runway. Step off to the side."
	if kind == "bushcamp":
		if plane == null or not plane.on_ground or plane.global_position.distance_to(p) > 120.0:
			return "Set up camp near your plane: the gear is in it."
		if terrain.normal_at(p.x, p.z).y < 0.9:
			return "Too steep for a tent here."
		return ""
	for it in items:
		if it["kind"] != "strip" and it["kind"] != "bushcamp" and (it["pos"] as Vector3).distance_to(p) < reach(kind) + reach(String(it["kind"])) + 2.0:
			return "Too close to your %s." % String(KINDS[it["kind"]][0]).to_lower()
	var uneven := pad_unevenness(kind, p)
	if uneven > 3.0:
		return "The ground is too uneven here (%.1f m). Doze it flatter first." % uneven
	var k: int = terrain.nearest_strip(p.x, p.z)
	var near: bool = k >= 0 and Vector2(p.x, p.z).distance_to(Vector2(terrain.strips[k]["pos"].x, terrain.strips[k]["pos"].z)) < float(terrain.strips[k]["length"]) * 0.5 + 200.0
	if kind == "hangar":
		if not near:
			return "A hangar goes beside an airstrip."
		if has_hangar(k):
			return "There's already a hangar here."
	if kind == "camp":
		var c: Array = mining.claim_at(k) if near else []
		if c.is_empty() or not bool(mining.state(c[1])["owned"]):
			return "A mining camp goes at a claim you own."
		if has_camp(String(c[1])):
			return "You already have a camp here."
	if logs < int(spec[2]):
		return "You need %d logs (you have %d). Fell some trees." % [int(spec[2]), logs]
	if jobs.money < int(spec[1]):
		return "You need $%d." % int(spec[1])
	return ""


func build(kind: String, p: Vector3, yaw: float) -> String:
	var why := cannot_build(kind, p)
	if why != "":
		return why
	var spec: Array = KINDS[kind]
	if kind == "bushcamp":
		# Pack up the old one.
		for i in range(items.size() - 1, -1, -1):
			if items[i]["kind"] == "bushcamp":
				items.remove_at(i)
				var nd: Node = _nodes[i] if i < _nodes.size() else null
				if nd != null and is_instance_valid(nd):
					nd.queue_free()
				if i < _nodes.size():
					_nodes.remove_at(i)
		camp_changed.emit()
	jobs.money -= int(spec[1])
	logs -= int(spec[2])
	var k: int = terrain.nearest_strip(p.x, p.z)
	if kind in ["cabin", "loghouse", "polebarn", "poleshed", "hangar"]:
		_level_pad(kind, p, yaw)
	var it := {"kind": kind, "pos": Vector3(p.x, terrain.height_at(p.x, p.z), p.z), "yaw": yaw, "strip": k}
	if kind == "camp":
		it["claim"] = String(mining.claim_at(k)[1])
	items.append(it)
	_spawn(it)
	_save()
	jobs.save_career()
	if kind == "bushcamp":
		camp_changed.emit()
	return ""


func has_hangar(k: int) -> bool:
	for it in items:
		if it["kind"] == "hangar" and int(it["strip"]) == k:
			return true
	return false


func has_camp(claim: String) -> bool:
	for it in items:
		if it["kind"] == "camp" and String(it.get("claim", "")) == claim:
			return true
	return false


## Standing in one of your cabins?
func in_cabin(p: Vector3) -> bool:
	for it in items:
		if String(it["kind"]) in WARM:
			var f: Array = FOOT[it["kind"]]
			var c: Vector3 = it["pos"]
			var l := Basis(Vector3.UP, -float(it["yaw"])) * (p - c)
			if absf(l.x) < float(f[0]) * 0.5 and absf(l.z) < float(f[1]) * 0.5 and l.y > -0.5 and l.y < 3.5:
				return true
	return false


## Rough radius a building takes up (porch included).
func reach(kind: String) -> float:
	if not FOOT.has(kind):
		return 6.0
	var f: Array = FOOT[kind]
	return Vector2(float(f[0]), float(f[1]) + float(PORCH.get(kind, 0.0)) * 2.0).length() * 0.5


## Where a building goes for someone standing at `at` looking along `look_yaw`:
## far enough ahead that its door (which faces you) is a few steps away.
func spot_for(kind: String, at: Vector3, look_yaw: float) -> Vector3:
	var fwd := Vector3(-sin(look_yaw), 0.0, -cos(look_yaw))
	var dz := 9.0
	if FOOT.has(kind):
		dz = float(FOOT[kind][1]) * 0.5 + float(PORCH.get(kind, 0.0)) + 3.0
	return at + fwd * dz


## Highest minus lowest ground over the footprint itself (porch included).
func pad_range(kind: String, p: Vector3, yaw: float) -> float:
	var f: Array = FOOT[kind]
	var w := float(f[0])
	var d := float(f[1]) + float(PORCH.get(kind, 0.0)) * 2.0
	var b := Basis(Vector3.UP, yaw)
	var lo := INF
	var hi := -INF
	for i in range(7):
		for j in range(7):
			var q := p + b * Vector3((float(i) / 6.0 - 0.5) * w, 0, (float(j) / 6.0 - 0.5) * d)
			var h: float = terrain.height_at(q.x, q.z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


## Highest minus lowest ground round the spot (before you know which way it faces).
func pad_unevenness(kind: String, p: Vector3) -> float:
	if not FOOT.has(kind):
		return 0.0
	var f: Array = FOOT[kind]
	var r := Vector2(float(f[0]), float(f[1])).length() * 0.5
	var lo := INF
	var hi := -INF
	for i in range(-2, 3):
		for j in range(-2, 3):
			var h: float = terrain.height_at(p.x + r * 0.5 * float(i), p.z + r * 0.5 * float(j))
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


## Cut and fill the pad flat at the ground height in the middle, so the floor
## sits on the ground everywhere (the voxel ground follows).
func _level_pad(kind: String, p: Vector3, yaw: float) -> void:
	var f: Array = FOOT[kind]
	var target: float = terrain.height_at(p.x, p.z)
	var w := float(f[0]) + 1.0
	var d := float(f[1]) + float(PORCH.get(kind, 0.0)) * 2.0 + 1.0
	var b := Basis(Vector3.UP, yaw)
	# a grid of small round levellings covers the rectangle
	for _pass in range(24):
		var x := -w * 0.5
		while x <= w * 0.5 + 0.01:
			var z := -d * 0.5
			while z <= d * 0.5 + 0.01:
				terrain.level(p + b * Vector3(x, 0, z), 3.2, target, 1.0e9)
				z += 2.0
			x += 2.0


## Fly logs out to the sawmill at Port Ashby: a job from the strip you are at.
const LOG_KG := 45.0
const LOG_PAY := 55

func ship_logs(k: int, by_hand: bool) -> String:
	if k < 0:
		return "Walk to an airstrip with them first."
	if logs <= 0:
		return "No logs on hand. Fell some trees."
	var r: Dictionary = jobs.room()
	var n := mini(logs, int(floor(minf(float(r["front"]) + float(r["rear"]), float(r["weight"])) / LOG_KG)))
	if n <= 0:
		return "No room on board for a log."
	var mill := 0
	for i in range(terrain.strips.size()):
		if String(terrain.strips[i]["name"]) == "Proving Ground":
			mill = i
	if mill == k:
		logs -= n
		jobs.money += n * LOG_PAY
		_save()
		jobs.save_career()
		return ""
	var job := {"id": 770000 + randi() % 100000, "kind": "logs", "title": "Sawlogs", "from": k, "to": mill,
		"what": "%d sawlogs for the mill" % n, "kg": float(n) * LOG_KG, "pay": n * LOG_PAY + 120,
		"fragile": false, "urgent": false, "limit_min": 0.0, "pax": 0, "n": n}
	if not jobs.take_custom(job, by_hand):
		return "Couldn't load them."
	logs -= n
	_save()
	return ""


func add_logs(n: int) -> void:
	logs += n
	_save()


# ------------------------------------------------------------------------------
#  Meshes
# ------------------------------------------------------------------------------
func _spawn(it: Dictionary) -> void:
	var kit := MeshKit.new()
	var p: Vector3 = it["pos"]
	var xf := Transform3D(Basis(Vector3.UP, float(it["yaw"])), p)
	match String(it["kind"]):
		"strip":
			_strip_marks(kit, int(it["strip"]))
			terrain.clear_spot(p.x, p.z, 1.0)
			if world.has_method("_add_windsock"):
				world._add_windsock(int(it["strip"]), STRIP_W * 0.5)
			xf = Transform3D.IDENTITY
		"cabin", "loghouse", "polebarn", "poleshed":
			var f: Array = FOOT[it["kind"]]
			var sol: Array = []
			match String(it["kind"]):
				"cabin":
					sol = Models.log_building(kit, 7.0, 6.0, 9, 1.8, {
						"front": [[0.0, 1.3, 0, 6], [-2.0, 1.0, 3, 6]],
						"back": [[1.6, 1.0, 3, 6]],
						"left": [[0.0, 1.0, 3, 5]],
						"right": [[-1.4, 0.8, 3, 5]],
					}, 11, false)["solids"]
					sol += Models.cabin_furniture(kit, 7.0, 6.0, 2.68, 4.9, true)
				"loghouse":
					sol = Models.log_building(kit, 10.0, 8.0, 10, 2.4, {
						"front": [[0.0, 1.3, 0, 6], [-2.6, 1.3, 3, 7], [2.6, 1.3, 3, 7]],
						"back": [[-2.5, 1.1, 3, 7], [2.5, 1.1, 3, 7]],
						"left": [[-1.5, 1.1, 3, 6], [1.8, 1.1, 3, 6]],
						"right": [[2.0, 0.9, 3, 6]],
					}, 23, true)["solids"]
					sol += Models.cabin_furniture(kit, 10.0, 8.0, 2.96, 5.96, false)
				"polebarn":
					sol = Models.pole_barn(kit, 12.0, 18.0, 4.8, 6.0, 4.2, {"wall": Color(0.90, 0.90, 0.87),
						"wainscot": Color(0.20, 0.34, 0.24), "trim": Color(0.20, 0.34, 0.24), "roof": Color(0.66, 0.68, 0.69)})["solids"]
				"poleshed":
					sol = Models.pole_shed(kit, 12.0, 8.0, 4.4, 3.4, {"wall": Color(0.70, 0.72, 0.72),
						"wainscot": Color(0.24, 0.36, 0.27), "trim": Color(0.24, 0.36, 0.27), "roof": Color(0.66, 0.68, 0.69)})["solids"]
			terrain.clear_spot(p.x, p.z, reach(String(it["kind"])) + 3.0)
			terrain.add_hollow(xf, Vector3(float(f[0]), float(f[2]), float(f[1])), float(f[3]))
			for so in sol:
				terrain.add_solid(xf * Transform3D(Basis.IDENTITY, so[0] as Vector3), so[1])
		"hangar":
			var hi: Dictionary = Models.bush_hangar(kit, 22.0, 18.0, 6.5, 20.0, 5.4, {"wall": Color(0.92, 0.92, 0.89),
				"wainscot": Color(0.20, 0.34, 0.24), "trim": Color(0.95, 0.95, 0.93), "roof": Color(0.66, 0.68, 0.69)})
			terrain.clear_spot(p.x, p.z, 20.0)
			terrain.add_hollow(xf, Vector3(22.0, 6.5, 18.0), 20.0)
			for so in hi["solids"]:
				terrain.add_solid(xf * Transform3D(Basis.IDENTITY, so[0] as Vector3), so[1])
			for pf in hi["platforms"]:
				terrain.add_platform(xf * Transform3D(Basis.IDENTITY, pf[0] as Vector3), pf[1], float(pf[2]), float(pf[3]))
			_pending_door = [hi, xf]
			if lights != null:
				var hfx: Array = []
				for f in hi["fixtures"]:
					hfx.append([xf * (f[0] as Transform3D), f[1]])
				var hl: Array = []
				for lp3 in hi["lamps"]:
					hl.append(xf * (lp3 as Vector3))
				lights.add_group(xf * (hi["switch"] as Vector3), hl, hfx)
		"camp":
			_camp(kit)
			terrain.clear_spot(p.x, p.z, 14.0)
		"bushcamp":
			_bushcamp(kit)
			terrain.clear_spot(p.x, p.z, 7.0)
	if lights != null:
		match String(it["kind"]):
			"polebarn":
				var bfx: Array = []
				for lz in [-6.0, 0.0, 6.0]:
					bfx.append([xf * Transform3D(Basis.IDENTITY, Vector3(0, 4.6, lz)), Vector3(1.2, 0.03, 0.12)])
				lights.add_group(xf * Vector3(5.85, 1.35, -8.0), [xf * Vector3(0, 4.4, -5.0), xf * Vector3(0, 4.4, 5.0)], bfx)
			"loghouse":
				var lp2 := xf * Vector3(0, 2.3, 0.3)
				lights.add_group(lp2, [lp2 + Vector3(0, -0.1, 0)], [[xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.3, 0.3)), Vector3(0.09, 0.13, 0.09)]], "lantern")
			"cabin":
				var lp := xf * Vector3(0, 2.05, 0.3)
				lights.add_group(lp, [lp + Vector3(0, -0.1, 0)], [[xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.05, 0.3)), Vector3(0.09, 0.13, 0.09)]], "lantern")
	var mi := kit.instance("Build_" + String(it["kind"]))
	mi.transform = xf
	add_child(mi)
	_nodes.append(mi)
	if not _pending_door.is_empty():
		var hi2: Dictionary = _pending_door[0]
		var door: Node3D = load("res://scripts/bifold_door.gd").new()
		door.door_w = 20.0
		door.door_h = 5.4
		door.hz = 9.0
		door.hollow = terrain.hollows[terrain.hollows.size() - 1]
		mi.add_child(door)
		door.build(Color(0.92, 0.92, 0.89), Color(0.95, 0.95, 0.93))
		if world != null and world.get("hangar_doors") != null:
			world.hangar_doors.append([door, xf * (hi2["door_switch"] as Vector3)])
		_pending_door = []


## Old tyres, painted white, down both edges; a cone at each corner.
func _strip_marks(kit: MeshKit, k: int) -> void:
	var s: Dictionary = terrain.strips[k]
	var hl: float = float(s["length"]) * 0.5
	var hw: float = float(s["width"]) * 0.5
	var white := Color(0.9, 0.9, 0.86)
	var orange := Color(0.95, 0.45, 0.08)
	var steps := int(float(s["length"]) / 40.0)
	for i in range(steps + 1):
		var along := -hl + float(s["length"]) * float(i) / float(steps)
		for side in [-1.0, 1.0]:
			var q: Vector3 = terrain.strip_point(k, along, side * (hw + 1.2))
			var t := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), q + Vector3(0, 0.2, 0))
			kit.cylinder(t * Transform3D(Basis.IDENTITY, Vector3(0, -0.12, 0)), 0.38, 0.38, 0.24, 8, white)
			if i == 0 or i == steps:
				kit.cylinder(Transform3D(Basis.IDENTITY, q + Vector3(side * 2.0, 0, 0)), 0.25, 0.02, 0.7, 6, orange)


func _hangar(kit: MeshKit) -> void:
	var tin := Color(0.55, 0.57, 0.58)
	var frame := Color(0.32, 0.25, 0.17)
	var w := 22.0
	var d := 18.0
	var h := 6.5
	kit.box_at(Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, 0.2), tin)
	for sx in [-1.0, 1.0]:
		kit.box_at(Vector3(sx * w * 0.5, h * 0.5, 0), Vector3(0.2, h, d), tin)
	kit.quad(Vector3(-w * 0.5 - 0.4, h, -d * 0.5 - 0.4), Vector3(w * 0.5 + 0.4, h, -d * 0.5 - 0.4),
		Vector3(w * 0.5 + 0.4, h + 1.6, d * 0.5 + 0.4), Vector3(-w * 0.5 - 0.4, h + 1.6, d * 0.5 + 0.4), Color(0.45, 0.46, 0.47))
	for sx in [-1.0, 1.0]:
		kit.box_at(Vector3(sx * (w * 0.5 - 0.2), h * 0.5, -d * 0.5), Vector3(0.4, h, 0.4), frame)
	kit.box_at(Vector3(0, h - 0.4, -d * 0.5), Vector3(w, 0.8, 0.3), frame)
	kit.box_at(Vector3(0, 0.03, 0), Vector3(w, 0.06, d), Color(0.36, 0.33, 0.29))
	for lz in [-4.0, 4.0]:
		for lx in [-5.0, 5.0]:
			kit.box_at(Vector3(lx, 5.95, lz), Vector3(1.5, 0.05, 0.24), Color(0.3, 0.3, 0.32))
			kit.box_at(Vector3(lx, 6.2, lz), Vector3(0.01, 0.5, 0.01), Color(0.2, 0.2, 0.2))
	kit.box_at(Vector3(-10.4, 1.35, -8.95), Vector3(0.10, 0.14, 0.03), Color(0.75, 0.75, 0.72))


func _camp(kit: MeshKit) -> void:
	var canvas := Color(0.78, 0.74, 0.62)
	var wood := Color(0.45, 0.33, 0.2)
	# Wall tent
	kit.box_at(Vector3(-4, 0.8, 0), Vector3(3.2, 1.6, 4.2), canvas)
	kit.quad(Vector3(-5.7, 1.6, -2.1), Vector3(-2.3, 1.6, -2.1), Vector3(-2.3, 2.6, -2.1), Vector3(-5.7, 2.6, -2.1), canvas)
	kit.quad(Vector3(-5.7, 1.6, 2.1), Vector3(-5.7, 1.6, -2.1), Vector3(-4.0, 2.6, -2.1), Vector3(-4.0, 2.6, 2.1), canvas.darkened(0.1))
	kit.quad(Vector3(-2.3, 1.6, -2.1), Vector3(-2.3, 1.6, 2.1), Vector3(-4.0, 2.6, 2.1), Vector3(-4.0, 2.6, -2.1), canvas.darkened(0.1))
	# Sluice run on trestles
	var sl := Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(3.0, 1.0, 0))
	kit.box(sl, Vector3(0.7, 0.3, 6.0), wood)
	for z in [-2.4, 0.0, 2.4]:
		kit.box_at(Vector3(3.0, 0.45 + z * 0.12 * -1.0 * 0.0, z), Vector3(0.9, 0.9 - z * 0.12, 0.12), wood.darkened(0.2))
	# Fuel drums and a shovel pile
	for i in range(3):
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.5 + 0.65 * float(i), 0, 3.6)), 0.3, 0.3, 0.9, 10, Color(0.6, 0.12, 0.08))
	kit.box_at(Vector3(0.6, 0.2, -3.0), Vector3(2.0, 0.4, 1.4), Color(0.4, 0.36, 0.3))


## A bush camp, round the fire at the origin: dome tent, stone ring and
## logs, a cooler, a folding chair and a log to sit on.
const CAMP_TENT := Vector3(-3.4, 0, -1.2)
const CAMP_COOLER := Vector3(1.5, 0, 0.9)
const CAMP_CHAIR := Vector3(0.2, 0, 1.9)


func _bushcamp(kit: MeshKit) -> void:
	var nylon := Color(0.20, 0.42, 0.30)
	var fly := Color(0.85, 0.48, 0.12)
	# Dome tent: rings lofted over a 2.2 x 2.4 m floor, 1.3 m high.
	var rings: Array = []
	var nz := 6
	for i in range(nz + 1):
		var f := float(i) / float(nz)
		var z := lerpf(-1.2, 1.2, f)
		var sq := sqrt(maxf(1.0 - pow((f - 0.5) * 2.0, 2.0), 0.0))
		var ring := PackedVector3Array()
		for k in range(9):
			var a := PI * float(k) / 8.0
			ring.append(CAMP_TENT + Vector3(cos(a) * 1.1 * maxf(sq, 0.15), sin(a) * 1.3 * maxf(sq, 0.05), z))
		rings.append(ring)
	kit.loft(rings, nylon, false, false)
	# Door flap (darker) and the rain fly strip over the top.
	kit.box_at(CAMP_TENT + Vector3(0, 0.45, 1.16), Vector3(0.7, 0.85, 0.02), nylon.darkened(0.45))
	kit.box_at(CAMP_TENT + Vector3(0, 1.27, 0), Vector3(0.5, 0.05, 1.2), fly)
	# Fire ring: stones round, three logs.
	for k in range(10):
		var a := TAU * float(k) / 10.0
		kit.box(Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 0.62, 0.09, sin(a) * 0.62)), Vector3(0.22, 0.18, 0.26), Color(0.45, 0.44, 0.42))
	for k in range(3):
		var a := TAU * float(k) / 3.0 + 0.4
		kit.cylinder(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI * 0.5 - 0.35), Vector3(cos(a) * 0.15, 0.15, sin(a) * 0.15)), 0.07, 0.06, 0.75, 6, Color(0.25, 0.16, 0.09))
	kit.box_at(Vector3(0, 0.02, 0), Vector3(0.9, 0.03, 0.9), Color(0.12, 0.11, 0.10))
	# Cooler: red with a white lid and handles.
	kit.box_at(CAMP_COOLER + Vector3(0, 0.2, 0), Vector3(0.65, 0.38, 0.42), Color(0.72, 0.10, 0.08))
	kit.box_at(CAMP_COOLER + Vector3(0, 0.42, 0), Vector3(0.67, 0.06, 0.44), Color(0.92, 0.92, 0.90))
	for sx in [-1.0, 1.0]:
		kit.box_at(CAMP_COOLER + Vector3(sx * 0.35, 0.3, 0), Vector3(0.04, 0.05, 0.16), Color(0.85, 0.85, 0.85))
	# Folding camp chair facing the fire.
	var blue := Color(0.12, 0.22, 0.45)
	var leg := Color(0.2, 0.2, 0.2)
	kit.box_at(CAMP_CHAIR + Vector3(0, 0.42, 0), Vector3(0.52, 0.05, 0.48), blue)
	kit.box(Transform3D(Basis(Vector3.RIGHT, 0.25), CAMP_CHAIR + Vector3(0, 0.75, 0.26)), Vector3(0.52, 0.6, 0.04), blue)
	for sx in [-0.25, 0.25]:
		for sz in [-0.22, 0.22]:
			kit.box_at(CAMP_CHAIR + Vector3(sx, 0.21, sz), Vector3(0.03, 0.42, 0.03), leg)
		kit.box_at(CAMP_CHAIR + Vector3(sx, 0.62, 0), Vector3(0.05, 0.03, 0.48), leg)
	# A log to sit on, the other side of the fire.
	kit.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-1.9, 0.2, 0.6)), 0.2, 0.2, 1.6, 8, Color(0.36, 0.25, 0.15))
	# A few empties by the chair.
	for k in range(3):
		kit.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5) if k == 1 else Basis.IDENTITY, CAMP_CHAIR + Vector3(0.45 + 0.12 * k, 0.03 if k == 1 else 0.0, -0.1 * k)), 0.033, 0.033, 0.12, 8, Color(0.75, 0.75, 0.8))


## The bush camp, if you have one: the item, or {}.
func bush_camp() -> Dictionary:
	for it in items:
		if it["kind"] == "bushcamp":
			return it
	return {}


## World position of a spot in the bush camp (local offset from the fire).
func camp_point(local: Vector3) -> Vector3:
	var it := bush_camp()
	if it.is_empty():
		return Vector3.INF
	var p: Vector3 = it["pos"]
	var w := p + Basis(Vector3.UP, float(it["yaw"])) * local
	w.y = terrain.height_at(w.x, w.z)
	return w


# ------------------------------------------------------------------------------
#  Saving
# ------------------------------------------------------------------------------
func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("builds", "items", items)
	cf.set_value("builds", "logs", logs)
	cf.save(SAVE)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	var a = cf.get_value("builds", "items", [])
	items = a if a is Array else []
	logs = int(cf.get_value("builds", "logs", 0))
	# Strip indexes: the terrain read them back in the same order.
	var k := 0
	for it in items:
		if it["kind"] == "strip":
			var idx: int = terrain.player_strip_index(k)
			it["strip"] = idx
			k += 1
	items = items.filter(func(it): return it["kind"] != "strip" or int(it["strip"]) >= 0)


## Read by the terrain while it generates (before anything else sees the strips).
static func saved_strips() -> Array:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return []
	var out: Array = []
	for it in cf.get_value("builds", "items", []):
		if it is Dictionary and it.get("kind", "") == "strip" and it.has("def"):
			out.append(it["def"])
	return out
