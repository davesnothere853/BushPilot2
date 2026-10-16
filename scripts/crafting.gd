extends Node3D
## The crafting bench at the tool yard (DESIGN_NOTES 92): turn logs you've
## cut, a bit of cash for hardware, and gold into gear. Stand at the bench:
## the door key picks what to make, interact makes it.

const MeshKit = preload("res://scripts/meshkit.gd")
var BENCH := Vector3(-49.0, 0, -80.5)        # moved to the hangar bench in build()
const REACH := 2.4
const BAR_G := 100.0

## [id, name, logs, dollars, what you get]
const RECIPES := [
	["timber", "Timber set", 2, 0, "two posts and a cap for a drift"],
	["ladder", "Rope ladder", 2, 20, "rungs from the logs, rope from the store"],
	["sluice", "Sluice box", 3, 60, "riffles and a box, hardware bought"],
	["rope_light", "Rope light", 0, 40, "a 15 m string, wire and bulbs bought"],
	["gold_bar", "Gold bar", 0, 0, "pour 100 g of dust into a bar (sells for 8% more)"],
]

var terrain: RefCounted
var inv: Node
var builds: Node
var jobs: Node
var prospect: Node
var pick := 0


## The crafting bench is the workbench in the home hangar (DESIGN_NOTES
## 152): world.gd hands its spot over; only the yard bench is a fallback.
func build(at: Vector3 = Vector3.INF, face_yaw: float = 0.0) -> void:
	if at != Vector3.INF:
		BENCH = at
	var root := Node3D.new()
	root.name = "Bench"
	add_child(root)
	var y: float = terrain.ground_level_at(BENCH.x, BENCH.z) if terrain.has_method("ground_level_at") else terrain.height_at(BENCH.x, BENCH.z)
	root.global_transform = Transform3D(Basis(Vector3.UP, face_yaw), Vector3(BENCH.x, y, BENCH.z))
	if at == Vector3.INF:
		var k := MeshKit.new()
		var kb = load("res://scripts/building_models.gd")
		var rng := RandomNumberGenerator.new()
		rng.seed = 92
		kb.workbench(k, Vector3.ZERO, 2.4, 0.45, rng)
		root.add_child(k.instance("BenchMesh"))
	var lab := Label3D.new()
	lab.text = "WORKBENCH"
	lab.font_size = 40
	lab.pixel_size = 0.0035
	lab.position = Vector3(0, 2.55, -0.05)
	lab.modulate = Color(0.95, 0.9, 0.75)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(lab)


func near(p: Vector3) -> bool:
	return Vector2(p.x - BENCH.x, p.z - BENCH.z).length() < REACH


func target(p: Vector3, key: String) -> Array:
	if not near(p):
		return []
	var r: Array = RECIPES[pick]
	return ["craft", "%s  Make: %s (%s)   %s next   [%d logs, $%d, %.0f g]" % [key, r[1], _cost(r), Game.hint("door"), builds.logs if builds != null else 0, jobs.money if jobs != null else 0, prospect.gold_g if prospect != null else 0.0]]


func _cost(r: Array) -> String:
	if r[0] == "gold_bar":
		return "%.0f g of gold" % BAR_G
	var parts: Array = []
	if int(r[2]) > 0:
		parts.append("%d logs" % int(r[2]))
	if int(r[3]) > 0:
		parts.append("$%d" % int(r[3]))
	return " + ".join(parts)


func next_recipe() -> String:
	pick = (pick + 1) % RECIPES.size()
	var r: Array = RECIPES[pick]
	return "%s: %s - %s." % [r[1], _cost(r), r[4]]


func craft() -> String:
	var r: Array = RECIPES[pick]
	var id: String = r[0]
	if id == "gold_bar":
		if prospect == null or prospect.gold_g < BAR_G:
			return "You need %.0f g of gold to pour a bar (you have %.1f g)." % [BAR_G, prospect.gold_g if prospect != null else 0.0]
		if inv.add("gold_bar", 1) <= 0:
			return "No room on you for the bar."
		prospect.gold_g -= BAR_G
		prospect._dirty = true
		return "Poured a 100 g gold bar. It sells for 8% more than dust at the assay office."
	var logs_need := int(r[2])
	var cash := int(r[3])
	if builds != null and builds.logs < logs_need:
		return "You need %d logs (you have %d): fell a few trees with the chainsaw." % [logs_need, builds.logs]
	if not Game.sandbox and jobs != null and jobs.money < cash:
		return "That needs $%d for the hardware." % cash
	if id == "sluice":
		prospect.owned_sluices += 1
		prospect._dirty = true
	elif inv.add(id, 1) <= 0:
		return "No room on you for it."
	if builds != null and logs_need > 0:
		builds.logs -= logs_need
		builds.add_logs(0)
	if not Game.sandbox and jobs != null and cash > 0:
		jobs.money -= cash
	return "Made a %s.%s" % [String(r[1]).to_lower(), " Set it up at a creek from the build menu." if id == "sluice" else ""]
