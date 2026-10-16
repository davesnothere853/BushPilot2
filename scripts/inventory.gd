extends Node3D
## What the pilot carries on his person: an 8-slot hotbar (what's in hand is
## the selected slot) and a backpack, all limited by weight. Also the things
## lying about in the world that can be picked up (a shovel by the hangar,
## a pick you leaned on a wall). Tools only work from the hand.
## Saved in user://inventory.cfg. (DESIGN_NOTES 73.)

const ShovelKit = preload("res://scripts/shovel.gd")
const Parts = preload("res://scripts/parts.gd")
const MeshKit = preload("res://scripts/meshkit.gd")
const SAVE := "user://inventory.cfg"
const HOTBAR := 8
const PACK := 16
const MAX_KG := 32.0          # what he can hump about before he's over-loaded
## The tool yard: open ground between the hangar and the office (DESIGN_NOTES 72).
const YARD := {
	"shovel": Vector3(-46.0, 0, -79.0), "pick": Vector3(-44.6, 0, -79.4),
	"timber": Vector3(-47.0, 0, -76.0), "pump": Vector3(-43.0, 0, -77.0),
	"ladder": Vector3(-41.5, 0, -79.0), "gas_can": Vector3(-42.2, 0, -76.4),
	"generator": Vector3(-45.6, 0, -76.6), "rope_light": Vector3(-46.6, 0, -78.0),
	"rail": Vector3(-48.5, 0, -78.5),
	"dynamite": Vector3(-44.0, 0, -75.6),
	"pistol": Vector3(-43.2, 0, -75.4),
}

## id -> [name, kg each, stack size, one-line use]
const ITEMS := {
	"shovel": ["Shovel", 2.2, 1, "Dig: ground, gravel, drift faces. In hand."],
	"pick": ["Miner's pick", 2.8, 1, "Breaks rock and frozen ground fast. In hand."],
	"gold_pan": ["Gold pan", 0.7, 1, "Fill it with pay gravel, pan it at water."],
	"headlamp": ["Headlamp", 0.3, 1, "Light underground (lights key) while you carry it."],
	"ear_muffs": ["Ear muffs", 0.3, 1, "Hearing protection round engines and pumps: J puts them on or takes them off while you carry them. Everything sounds muffled with them on."],
	"rail": ["Track section (3 m)", 26.0, 1, "Two 3 m lengths of light mine rail spiked to five ties, 610 mm gauge. In hand, E lays it on the end of your track (or starts one). Ore cars run on it."],
	"timber": ["Timber set", 9.0, 6, "Two posts, a cap and lagging: holds up a drift roof 1.7 m either side. In hand, E in the drift to stand it."],
	"ladder": ["Rope ladder", 9.0, 1, "Hang it down a shaft or over a drop from the lip (E at the edge); climb with forward / back."],
	"pump": ["Trash pump", 26.0, 1, "Pumps a flooded hole dry. In hand, set it at the water's edge: the hose runs to the lowest ground nearby."],
	"gas_can": ["Gas can (full)", 16.5, 1, "20 L of gas. In hand, E at the trommel's engine to pour it into its fuel drum."],
	"gas_can_empty": ["Gas can (empty)", 1.8, 1, "In hand, E at a fuel pump to fill it."],
	"gold_bar": ["Gold bar (100 g)", 0.1, 10, "Poured at the workbench. Sells for 8% more than dust at the assay office."],
	"coin": ["1898 silver dollar", 0.03, 10, "A find. Sell it at the assay office."],
	"bottle": ["Gold-rush bottle", 0.4, 5, "A find. Sell it at the assay office."],
	"relic_pan": ["Rusted gold pan", 0.8, 2, "A find. Sell it at the assay office."],
	"bison_skull": ["Steppe bison skull", 9.0, 1, "A find from the ice age. Sell it at the assay office."],
	"tusk": ["Mammoth tusk", 18.0, 1, "Ice-age ivory. Sell it at the assay office."],
	"generator": ["Generator", 28.0, 1, "A small gas generator for the drifts. In hand, E to set it down; E to start it, fill it from a gas can."],
	"dynamite": ["Dynamite", 0.25, 12, "A stick of 40% dynamite, cap and safety fuse crimped in. In hand, E against rock, a drift face or the ground to set it and light the fuse: 8 seconds - get well clear."],
	"pistol": ["Pistol", 0.95, 1, "A plain 9 mm semi-auto, the kind every bush pilot kept for bears. In hand, E fires where you look."],
	"rope_light": ["Rope light", 1.5, 10, "15 m strings of lights. In hand, E at the generator (or a string's end) to hang one on toward where you stand."],
}

var slots: Array = []          # HOTBAR + PACK entries: {} or {"id": String, "n": int}
var active := 0                # hotbar slot in hand
var world_items: Array = []    # {"id", "n", "xf": Transform3D, "node": Node3D}
var terrain: RefCounted
var changed := false           # UI redraw hint
var can_l := 20.0              # litres in the gas can (when it's a full one)
var _dirty := false
var _save_t := 0.0


func _init() -> void:
	slots.resize(HOTBAR + PACK)
	for i in range(slots.size()):
		slots[i] = {}


# ------------------------------------------------------------------------------
#  Carrying
# ------------------------------------------------------------------------------
## [name, kg, stack, use] for an item: the fixed list, or a vehicle part
## ("part:<uid>", parts.gd), each one its own item with its own condition.
func spec(id: String) -> Array:
	if id.begins_with("part:"):
		return Parts.item_spec(id)
	return ITEMS.get(id, [id, 1.0, 1, ""])


func item_name(id: String) -> String:
	return String(spec(id)[0])


func weight() -> float:
	var kg := 0.0
	for s in slots:
		if not (s as Dictionary).is_empty():
			kg += float(spec(String(s["id"]))[1]) * int(s["n"])
	return kg


func count(id: String) -> int:
	var n := 0
	for s in slots:
		if not (s as Dictionary).is_empty() and s["id"] == id:
			n += int(s["n"])
	return n


func has(id: String) -> bool:
	return count(id) > 0


func in_hand() -> String:
	var s: Dictionary = slots[active]
	return "" if s.is_empty() else String(s["id"])


func holding(id: String) -> bool:
	return in_hand() == id


## Put `n` of `id` on him: stacks first, then an empty hotbar slot, then the
## pack. Returns how many fitted (weight and space).
func add(id: String, n: int = 1, prefer_hand: bool = false) -> int:
	var kg: float = spec(id)[1]
	var stack: int = spec(id)[2]
	var room := int(floor((MAX_KG - weight()) / kg + 0.0001))
	if id.begins_with("part:") and kg > MAX_KG:
		room = 0                      # an engine block is a two-man (or a loader) job
	n = mini(n, room)
	var put := 0
	for i in range(slots.size()):
		var s: Dictionary = slots[i]
		if put < n and not s.is_empty() and s["id"] == id and int(s["n"]) < stack:
			var k := mini(stack - int(s["n"]), n - put)
			s["n"] = int(s["n"]) + k
			put += k
	var order: Array = []
	if prefer_hand and (slots[active] as Dictionary).is_empty():
		order.append(active)
	for i in range(slots.size()):
		if not order.has(i):
			order.append(i)
	for i in order:
		if put >= n:
			break
		if (slots[i] as Dictionary).is_empty():
			var k2 := mini(stack, n - put)
			slots[i] = {"id": id, "n": k2}
			put += k2
			if prefer_hand and i < HOTBAR:
				active = i
				prefer_hand = false
	if put > 0:
		_touch()
	return put


## Pour up to `want` litres from the can in hand; returns what came out.
## The can goes empty when it's dry.
func pour_can(want: float) -> float:
	if not holding("gas_can"):
		return 0.0
	var got := minf(want, can_l)
	can_l -= got
	if can_l <= 0.1:
		swap_in_hand("gas_can_empty")
		can_l = 0.0
	_dirty = true
	return got


## Fill the empty can in hand.
func fill_can(litres: float) -> void:
	if holding("gas_can_empty"):
		swap_in_hand("gas_can")
	can_l = litres
	_dirty = true


## Swap what's in hand for another item in the same slot (a can filled or
## emptied).
func swap_in_hand(id: String) -> void:
	slots[active] = {"id": id, "n": 1}
	changed = true
	_dirty = true


func remove(id: String, n: int = 1) -> int:
	var took := 0
	for i in range(slots.size() - 1, -1, -1):
		var s: Dictionary = slots[i]
		if took < n and not s.is_empty() and s["id"] == id:
			var k := mini(int(s["n"]), n - took)
			s["n"] = int(s["n"]) - k
			took += k
			if int(s["n"]) <= 0:
				slots[i] = {}
	if took > 0:
		_touch()
	return took


func select(i: int) -> void:
	active = clampi(i, 0, HOTBAR - 1)
	_touch()


func cycle(d: int) -> void:
	select(posmod(active + d, HOTBAR))


## Swap two slots (backpack screen).
func swap(a: int, b: int) -> void:
	var t: Dictionary = slots[a]
	slots[a] = slots[b]
	slots[b] = t
	_touch()


func _touch() -> void:
	changed = true
	_dirty = true


# ------------------------------------------------------------------------------
#  Things lying in the world
# ------------------------------------------------------------------------------
## Drop what's in hand at `p` facing `yaw`. Long tools are stuck in the
## ground, blade down, handle up; the rest lie on the ground.
func drop_active(p: Vector3, yaw: float) -> String:
	var id := in_hand()
	if id == "":
		return ""
	var n: int = int((slots[active] as Dictionary)["n"])
	slots[active] = {}
	_touch()
	place_in_world(id, n, p, yaw)
	return "%s %s here." % [item_name(id), "stuck in the ground" if id in ["shovel", "pick"] else "set down"]


func place_in_world(id: String, n: int, p: Vector3, yaw: float) -> void:
	var y: float = terrain.height_at(p.x, p.z) if terrain != null else p.y
	if p.y < y - 1.2:
		y = p.y                       # underground: on the drift floor where he stands
	var xf: Transform3D
	if id in ["shovel", "pick"]:
		xf = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 1.2), Vector3(p.x, y + 1.0, p.z))
	else:
		xf = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y + 0.04, p.z))
	var e := {"id": id, "n": n, "xf": xf, "node": null}
	world_items.append(e)
	_spawn(e)
	_dirty = true


func _spawn(e: Dictionary) -> void:
	var nd := build_mesh(String(e["id"]))
	add_child(nd)
	nd.global_transform = e["xf"]
	e["node"] = nd
	_coll(e, true)


## Things on the ground are part of the world (DESIGN_NOTES 141): the big
## ones (generator, pump, a heavy part) are solid, the rest you step over.
func _coll(e: Dictionary, on: bool) -> void:
	if terrain == null or not terrain.has_method("set_platform"):
		return
	if not e.has("uid"):
		e["uid"] = randi()
	var key := "item:%s" % str(e["uid"])
	terrain.clear_platform(key)
	terrain.clear_solid(key)
	if not on or e["node"] == null:
		return
	var nd: Node3D = e["node"]
	var box := AABB()
	var first := true
	for mi in nd.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var bb: AABB = (nd.global_transform.affine_inverse() * m.global_transform) * m.mesh.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if nd is MeshInstance3D and (nd as MeshInstance3D).mesh != null:
		var bb2: AABB = (nd as MeshInstance3D).mesh.get_aabb()
		box = bb2 if first else box.merge(bb2)
		first = false
	if first:
		return
	var xf: Transform3D = nd.global_transform
	var c := xf * Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var flat := Transform3D(Basis(Vector3.UP, xf.basis.get_euler().y), c)
	if box.size.y > 0.6 and String(e["id"]) in ["generator", "pump"]:
		terrain.set_solid(key, flat, box.size)
	elif box.size.y < 0.6:
		terrain.set_platform(key, flat, box.size)


## The nearest thing on the ground within reach of `p`, or {}.
func world_item_near(p: Vector3, reach: float = 1.7) -> Dictionary:
	var best := {}
	var bd := reach
	for e in world_items:
		var o: Vector3 = (e["xf"] as Transform3D).origin
		var d := Vector2(o.x - p.x, o.z - p.z).length()
		if d < bd and absf(o.y - p.y) < 2.5:
			bd = d
			best = e
	return best


func pick_up(e: Dictionary) -> String:
	var id: String = e["id"]
	var got := add(id, int(e["n"]), id.begins_with("part:") or id in ["shovel", "pick", "gold_pan", "timber", "pump", "ladder", "gas_can", "gas_can_empty", "generator", "rope_light", "rail"])
	if got <= 0:
		return "Too much on you already (%.0f of %.0f kg)." % [weight(), MAX_KG]
	e["n"] = int(e["n"]) - got
	if int(e["n"]) <= 0:
		_coll(e, false)
		if e["node"] != null:
			(e["node"] as Node).queue_free()
		world_items.erase(e)
	_dirty = true
	return "Picked up: %s%s. %s" % [item_name(id), "" if got == 1 else " x%d" % got, String(spec(id)[3])]


# ------------------------------------------------------------------------------
#  Meshes (polyart, grip at the origin, handle along +Z, for the hand)
# ------------------------------------------------------------------------------
## A 15-inch plastic gold pan: flat bottom, sloped sides, a rolled lip, and
## three riffles moulded into one side of the wall to catch the gold. `xf`
## puts the middle of the bottom; the pan opens up +Y.
static func gold_pan(k, xf: Transform3D, col: Color, riffles: bool = true) -> void:
	var n := 24
	# profile, middle out: [radius, height]
	var prof := [[0.0, 0.0], [0.105, 0.0], [0.13, 0.012], [0.185, 0.066], [0.198, 0.07], [0.2, 0.062]]
	var inside := col.lightened(0.08)
	var under := col.darkened(0.25)
	var th := 0.004
	for i in range(n):
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		for j in range(prof.size() - 1):
			var r0: float = prof[j][0]
			var y0: float = prof[j][1]
			var r1: float = prof[j + 1][0]
			var y1: float = prof[j + 1][1]
			var p00 := xf * (d0 * r0 + Vector3(0, y0, 0))
			var p01 := xf * (d1 * r0 + Vector3(0, y0, 0))
			var p10 := xf * (d0 * r1 + Vector3(0, y1, 0))
			var p11 := xf * (d1 * r1 + Vector3(0, y1, 0))
			var mid := (d0 + d1).normalized()
			var slope := Vector3(mid.x * (y1 - y0), -(r1 - r0), mid.z * (y1 - y0)).normalized()     # outward-down normal of the wall
			if j == prof.size() - 2:
				slope = xf.basis * (mid * 0.6 + Vector3(0, -0.8, 0)).normalized()
			else:
				slope = xf.basis * slope
			var up := Vector3(0, th, 0)
			# the inside (seen from above) and the outside (from below)
			if j < prof.size() - 2:
				k.quad(p00 + xf.basis * up, p10 + xf.basis * up, p11 + xf.basis * up, p01 + xf.basis * up, inside if j > 0 else inside.darkened(0.06), -slope)
			k.quad(p00, p01, p11, p10, under if j < 2 else col, slope)
		# the lip's top
		var lip0 := xf * (d0 * 0.185 + Vector3(0, 0.066 + th, 0))
		var lip1 := xf * (d1 * 0.185 + Vector3(0, 0.066 + th, 0))
		var lo0 := xf * (d0 * 0.2 + Vector3(0, 0.062, 0))
		var lo1 := xf * (d1 * 0.2 + Vector3(0, 0.062, 0))
		k.quad(lip0, lo0, lo1, lip1, col.lightened(0.04), xf.basis * Vector3.UP)
	if riffles:
		# three ridges across one side of the wall (the far side from the hand)
		for rr in range(3):
			var t := 0.3 + 0.22 * float(rr)
			var rad := lerpf(0.13, 0.185, t)
			var hy := lerpf(0.012, 0.066, t)
			for sgi in range(7):
				var aa := PI * 0.5 + (float(sgi) - 3.0) * 0.16
				var c := Vector3(cos(aa) * rad, hy + 0.008, sin(aa) * rad)
				k.box(xf * Transform3D(Basis(Vector3.UP, -aa).rotated(Vector3(sin(aa), 0, -cos(aa)).normalized(), 0.7), c), Vector3(0.012, 0.008, 0.06), col.darkened(0.12))
	# the bottom's underside
	k.cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.001, 0)), 0.105, 0.105, 0.001, n, under, true)


static func build_mesh(id: String) -> Node3D:
	if id == "pistol_holster":
		# the pistol when it isn't up: in a holster on the right hip, muzzle
		# down, grip back (DESIGN_NOTES 182)
		var hg := build_mesh("pistol")
		hg.set_meta("carry", {"anchor": "hip", "xf": HOLSTER_XF, "fit": ""})
		return hg
	if id.begins_with("part:"):
		return Parts.build_mesh(Parts.uid_of_item(id))
	match id:
		"shovel":
			var sh: Node3D = ShovelKit.build()
			sh.set_meta("carry", {"anchor": CARRY["shovel"][0], "xf": CARRY["shovel"][1]})
			return sh
	var root := Node3D.new()
	root.name = id
	var k := MeshKit.new()
	var along := Basis(Vector3.RIGHT, PI * 0.5)
	var ash := Color(0.62, 0.47, 0.30)
	var steel := Color(0.33, 0.34, 0.36)
	match id:
		"pick":
			k.cylinder(Transform3D(along, Vector3(0, 0, -0.30)), 0.018, 0.022, 0.92, 6, ash)
			k.box_at(Vector3(0, 0, 0.62), Vector3(0.07, 0.07, 0.09), steel)
			k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.62)), 0.03, 0.006, 0.36, 5, steel)
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 0, 0.62)), 0.03, 0.012, 0.30, 5, steel)
		"gold_pan":
			# held by the rim, the pan out in front of the hand, level
			gold_pan(k, Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0.2)), Color(0.13, 0.45, 0.24))
		"headlamp":
			k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.0)), 0.104, 0.104, 0.03, 12, Color(0.12, 0.12, 0.12), false)
			k.box_at(Vector3(0, 0.015, -0.112), Vector3(0.06, 0.045, 0.04), Color(0.75, 0.6, 0.1))
			k.box_at(Vector3(0, 0.015, -0.133), Vector3(0.04, 0.03, 0.004), Color(1.0, 0.95, 0.7))
		"ladder":
			# rolled up: rungs and rope round and round, a carrying loop on top
			var rope := Color(0.62, 0.55, 0.40)
			k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.21, -0.2, 0)), 0.13, 0.13, 0.42, 10, Color(0.5, 0.38, 0.22))
			for lx in [-0.17, 0.17]:
				k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(lx + 0.02, -0.2, 0)), 0.137, 0.137, 0.04, 10, rope)
				k.box_at(Vector3(lx * 0.5, -0.04, 0), Vector3(0.02, 0.1, 0.02), rope)
		"pump":
			k.box_at(Vector3(0, 0.22, 0.2), Vector3(0.42, 0.3, 0.36), Color(0.75, 0.15, 0.1))
			k.box_at(Vector3(0, 0.05, 0.2), Vector3(0.5, 0.06, 0.5), Color(0.15, 0.15, 0.15))
			k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.3, 0.2, 0.2)), 0.07, 0.07, 0.14, 8, Color(0.2, 0.2, 0.2))
		"gas_can", "gas_can_empty":
			# a steel jerry can: flat-sided, three handles, spout cap
			var red := Color(0.62, 0.10, 0.08)
			k.box_at(Vector3(0, -0.02, 0.12), Vector3(0.16, 0.46, 0.34), red)
			for hx in [-0.06, 0.0, 0.06]:
				k.box_at(Vector3(hx, 0.24, 0.12), Vector3(0.02, 0.05, 0.16), red.darkened(0.2))
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 0.22, -0.02)), 0.025, 0.025, 0.06, 6, Color(0.2, 0.2, 0.2))
			k.box_at(Vector3(0.081, -0.02, 0.12), Vector3(0.004, 0.36, 0.26), red.lightened(0.15))   # the X pressing
		"generator":
			var TP = load("res://scripts/tunnel_power.gd")
			var gk := MeshKit.new()
			TP.gen_mesh(gk)
			var gi := gk.instance("gen")
			gi.position = Vector3(0, -0.3, 0.35)
			root.add_child(gi)
			root.set_meta("carry", {"anchor": CARRY["generator"][0], "xf": CARRY["generator"][1]})
			return root
		"rope_light":
			# a coil of cord with bulbs on it
			for c in range(6):
				k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.12 + 0.012 * c)), 0.16 - 0.01 * c, 0.16 - 0.01 * c, 0.012, 14, Color(0.15, 0.15, 0.15), true)
			for bb in range(12):
				var ba := TAU * float(bb) / 12.0
				k.box_at(Vector3(sin(ba) * 0.15, cos(ba) * 0.15, 0.16), Vector3(0.03, 0.03, 0.05), Color(1.0, 0.85, 0.5))
		"gold_bar":
			k.box_at(Vector3(0, 0, 0.08), Vector3(0.05, 0.025, 0.1), Color(0.95, 0.75, 0.2))
		"coin":
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.05)), 0.02, 0.02, 0.004, 10, Color(0.75, 0.75, 0.72))
		"bottle":
			var bg := Color(0.22, 0.38, 0.25)
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.0)), 0.04, 0.04, 0.16, 8, bg)
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.16)), 0.04, 0.015, 0.05, 8, bg)
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.21)), 0.015, 0.015, 0.06, 6, bg)
		"relic_pan":
			gold_pan(k, Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0.2)), Color(0.42, 0.22, 0.12), false)
		"bison_skull":
			var bone := Color(0.82, 0.76, 0.62)
			k.box_at(Vector3(0, 0, 0.2), Vector3(0.28, 0.2, 0.45), bone)
			k.box_at(Vector3(0, -0.03, 0.47), Vector3(0.16, 0.12, 0.15), bone.darkened(0.1))
			for hs in [-1.0, 1.0]:
				k.cylinder(Transform3D(Basis(Vector3.BACK, hs * 1.2), Vector3(hs * 0.14, 0.06, 0.1)), 0.05, 0.015, 0.4, 6, Color(0.25, 0.22, 0.2))
		"tusk":
			var ivory := Color(0.85, 0.78, 0.6)
			var prev := Vector3(0, 0, -0.3)
			for ts in range(8):
				var t := float(ts + 1) / 8.0
				var q := Vector3(0, 0.35 * sin(t * 2.2), -0.3 + 1.4 * t)
				var r := 0.07 * (1.0 - t * 0.7)
				var d := q - prev
				var y := d.normalized()
				var x := y.cross(Vector3.RIGHT).normalized()
				k.cylinder(Transform3D(Basis(x, y, x.cross(y)), prev), r + 0.008, r, d.length(), 7, ivory.darkened(0.15 * (1.0 - t)))
				prev = q
		"pistol":
			# (DESIGN_NOTES 180) a generic 1980s 9 mm service pistol: 197 mm
			# long, 138 mm tall, a 30 mm-wide blued steel slide with grip
			# serrations at the back, an alloy frame, a trigger guard, a
			# hammer, fixed sights and checkered walnut grip panels. The grip
			# origin is the web of the hand; the muzzle points down -Z.
			var blue := Color(0.10, 0.10, 0.11, 0.35)
			var alloy := Color(0.16, 0.16, 0.17, 0.4)
			var walnut := Color(0.30, 0.18, 0.10)
			k.box_at(Vector3(0, 0.072, -0.062), Vector3(0.028, 0.030, 0.197), blue)                 # slide
			for si in range(6):
				k.box_at(Vector3(0, 0.072, 0.012 + 0.005 * float(si)), Vector3(0.0285, 0.026, 0.0015), Color(0.06, 0.06, 0.07))
			k.box_at(Vector3(0, 0.0455, -0.052), Vector3(0.024, 0.023, 0.15), alloy)                # frame / dust cover
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.074, -0.161)), 0.0048, 0.0048, 0.004, 8, Color(0.02, 0.02, 0.02), true)   # the muzzle
			k.box_at(Vector3(0, 0.090, -0.150), Vector3(0.004, 0.006, 0.008), blue)               # front sight
			k.box_at(Vector3(0, 0.090, 0.024), Vector3(0.016, 0.006, 0.008), blue)                # rear sight
			k.box(Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(0, 0.022, 0.026)), Vector3(0.012, 0.010, 0.012), blue)   # hammer
			# the grip: raked back, walnut panels on the sides
			var gb := Basis(Vector3.RIGHT, 0.26)
			k.box(Transform3D(gb, Vector3(0, -0.012, 0.012)), Vector3(0.026, 0.105, 0.046), alloy)
			for gx in [-0.0145, 0.0145]:
				k.box(Transform3D(gb, Vector3(gx, -0.010, 0.012)), Vector3(0.004, 0.088, 0.038), walnut)
			k.box(Transform3D(gb, Vector3(0, -0.066, 0.026)), Vector3(0.028, 0.008, 0.048), Color(0.08, 0.08, 0.08))    # magazine base
			# trigger guard and trigger
			k.box_at(Vector3(0, 0.012, -0.050), Vector3(0.010, 0.005, 0.056), alloy)
			k.box_at(Vector3(0, 0.024, -0.077), Vector3(0.010, 0.026, 0.005), alloy)
			k.box(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 0.026, -0.040)), Vector3(0.006, 0.020, 0.005), Color(0.05, 0.05, 0.05))
		"dynamite":
			# (DESIGN_NOTES 176) 1980s permissible dynamite: a 32 mm x 200 mm
			# stick in buff waxed paper, a red maker's band printed round it,
			# the crimped paper ends, a copper blasting cap pushed into one end
			# and a length of black-and-orange safety fuse curling out of it.
			# Lying on the ground it's a little bundle of three, tied with twine.
			var paper := Color(0.80, 0.68, 0.46)
			var band := Color(0.66, 0.12, 0.08)
			var sticks := [Vector3(-0.018, 0.016, 0), Vector3(0.018, 0.016, 0), Vector3(0.0, 0.046, 0)]
			for si in range(sticks.size()):
				var c0: Vector3 = sticks[si]
				var lay := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c0)        # lying along z
				k.cylinder(lay * Transform3D(Basis.IDENTITY, Vector3(0, -0.10, 0)), 0.016, 0.016, 0.2, 10, paper, true)
				k.cylinder(lay * Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0)), 0.0165, 0.0165, 0.04, 10, band, false)
				k.cylinder(lay * Transform3D(Basis.IDENTITY, Vector3(0, 0.10, 0)), 0.016, 0.006, 0.012, 10, paper.darkened(0.12), true)   # the crimped end
				k.cylinder(lay * Transform3D(Basis.IDENTITY, Vector3(0, -0.112, 0)), 0.016, 0.006, 0.012, 10, paper.darkened(0.12), true)
			# the cap in the top stick and the fuse curling up out of it
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.046, -0.112)), 0.004, 0.004, 0.02, 6, Color(0.72, 0.45, 0.22), true)
			var fp := Vector3(0.0, 0.046, -0.13)
			for fi in range(6):
				var nx := fp + Vector3(sin(float(fi) * 0.9) * 0.02, 0.012, -0.018)
				var fd := nx - fp
				var fxf := Transform3D(Basis(Vector3.UP.cross(fd.normalized()).normalized() if absf(fd.normalized().y) < 0.99 else Vector3.RIGHT, Vector3.UP.angle_to(fd.normalized())), fp)
				k.cylinder(fxf, 0.0035, 0.0035, fd.length(), 6, Color(0.12, 0.11, 0.10) if fi % 2 == 0 else Color(0.85, 0.45, 0.12), false)
				fp = nx
			# twine round the bundle
			for tz in [-0.05, 0.05]:
				k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.03, tz)), 0.04, 0.04, 0.006, 10, Color(0.62, 0.55, 0.40), false)
		"rail":
			var tie := Color(0.36, 0.27, 0.18)
			for tz in range(5):
				k.box_at(Vector3(0, 0.05, 0.3 + 0.6 * float(tz) - 0.9), Vector3(1.0, 0.1, 0.15), tie.darkened(0.1 * float(tz % 2)))
			for rx in [-0.305, 0.305]:
				k.box_at(Vector3(rx, 0.13, 0.0), Vector3(0.05, 0.065, 3.0), Color(0.32, 0.30, 0.29))
		"timber":
			var wood := Color(0.55, 0.42, 0.27)
			for x in [-0.09, 0.09]:
				k.box_at(Vector3(x, 0.08, 0.6), Vector3(0.16, 0.16, 2.2), wood)
			k.box_at(Vector3(0, 0.24, 0.45), Vector3(0.18, 0.16, 1.6), wood.darkened(0.1))
		_:
			# a part off the shelves (or anything without its own model): a
			# cardboard parts box with a strip of tape
			k.box_at(Vector3(0, 0.12, 0), Vector3(0.42, 0.24, 0.32), Color(0.62, 0.48, 0.30))
			k.box_at(Vector3(0, 0.245, 0), Vector3(0.43, 0.012, 0.08), Color(0.80, 0.72, 0.52))
	root.add_child(k.instance(id))
	if CARRY.has(id):
		var c: Array = CARRY[id]
		root.set_meta("carry", {"anchor": c[0], "xf": c[1], "fit": c[2] if c.size() > 2 else ""})
	return root


## The pistol in its hip holster, in the rig's frame (right +X, forward -Z).
const HOLSTER_XF := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3(0.215, 1.0, 0.035))


## How each thing is carried (pilot_rig.hold_tool): [anchor, Transform3D]
## in the rig's frame (forward -Z, right +X, up +Y). Hand: the basis is how
## it hangs from the hand, the origin an offset from the hand.
const CARRY := {
	# by the rim at his side, the dish facing out
	"gold_pan": ["hand", Transform3D(Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)), Vector3(0.05, 0.02, 0.0))],
	"relic_pan": ["hand", Transform3D(Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)), Vector3(0.05, 0.02, 0.0))],
	# held near the head, the handle hanging back and down... the head low and forward
	"pick": ["hand", Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -0.34, -0.94), Vector3(0, 0.94, -0.34)), Basis(Vector3(1, 0, 0), Vector3(0, -0.34, -0.94), Vector3(0, 0.94, -0.34)) * Vector3(0, 0, -0.48))],
	# at its balance point, the blade forward and a little down
	"shovel": ["hand", Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -0.82, 0.57), Vector3(0, -0.57, -0.82)), Basis(Vector3(1, 0, 0), Vector3(0, -0.82, 0.57), Vector3(0, -0.57, -0.82)) * Vector3(0, 0, -0.08))],
	# hanging from their top handles
	"gas_can": ["hand", Transform3D(Basis.IDENTITY, Vector3(0.05, -0.26, -0.12))],
	"gas_can_empty": ["hand", Transform3D(Basis.IDENTITY, Vector3(0.05, -0.26, -0.12))],
	"pump": ["hand", Transform3D(Basis.IDENTITY, Vector3(0.1, -0.42, -0.2))],
	"generator": ["hand", Transform3D(Basis.IDENTITY, Vector3(0.14, -0.1, -0.35))],
	"ladder": ["hand", Transform3D(Basis.IDENTITY, Vector3(0.04, 0.0, 0.0))],
	"rope_light": ["hand", Transform3D(Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)), Vector3(0.05 - 0.15, -0.14, 0.0))],
	# a stick held up in the fist like a torch, the fuse up top
	"dynamite": ["hand", Transform3D(Basis.IDENTITY, Vector3(0.03, -0.02, -0.02))],
	# in the fist, muzzle forward
	"pistol": ["hand", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.02, -0.075)), "pistol_aim"],
	# on the right shoulder, lengthways
	"timber": ["chest", Transform3D(Basis.IDENTITY, Vector3(0.2, 1.14, -0.6))],
	"rail": ["chest", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.85, -0.4))],
	# worn: the lamp at the front of his head
	"headlamp": ["head", Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0.01))],
}


# ------------------------------------------------------------------------------
#  Save
# ------------------------------------------------------------------------------
## A new game: the pan and headlamp on him, the shovel and pick by the hangar,
## a few timber sets stacked beside them.
func new_game() -> void:
	for i in range(slots.size()):
		slots[i] = {}
	add("gold_pan")
	add("headlamp")
	add("ear_muffs")
	for id in YARD.keys():
		place_in_world(id, 4 if id == "timber" else (6 if id == "rope_light" or id == "dynamite" else (8 if id == "rail" else 1)), YARD[id], 0.4)
	active = 2


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("i", "slots", slots)
	cf.set_value("i", "active", active)
	cf.set_value("i", "can_l", can_l)
	cf.set_value("i", "dyn_v1", true)
	cf.set_value("i", "gun_v1", true)
	var wi: Array = []
	for e in world_items:
		wi.append([e["id"], e["n"], e["xf"]])
	cf.set_value("i", "world", wi)
	cf.save(SAVE)


func load_all() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		new_game()
		return
	var sl: Array = cf.get_value("i", "slots", [])
	for i in range(mini(sl.size(), slots.size())):
		slots[i] = sl[i]
	active = int(cf.get_value("i", "active", 0))
	can_l = float(cf.get_value("i", "can_l", 20.0))
	for w in cf.get_value("i", "world", []):
		var e := {"id": String(w[0]), "n": int(w[1]), "xf": w[2], "node": null}
		world_items.append(e)
		_spawn(e)
	# saves from before an item existed get it by the hangar
	var have := {}
	for e2 in world_items:
		have[e2["id"]] = true
	# (the shovel and pick too: a save that lost them - dropped somewhere
	# in an old world - gets a new one in the yard)
	if not bool(cf.get_value("i", "dyn_v1", false)) and not has("dynamite") and not have.has("dynamite"):
		place_in_world("dynamite", 6, YARD["dynamite"], 0.4)      # a box of it in the yard, once (DESIGN_NOTES 176)
	if not bool(cf.get_value("i", "gun_v1", false)) and not has("pistol") and not have.has("pistol"):
		place_in_world("pistol", 1, YARD["pistol"], 0.4)          # (DESIGN_NOTES 180)
	for nid in ["shovel", "pick", "pump", "ladder", "gas_can", "generator", "rope_light"]:
		if not has(nid) and not have.has(nid) and not (nid == "gas_can" and (has("gas_can_empty") or have.has("gas_can_empty"))):
			place_in_world(nid, 1, YARD[nid], 0.2)
	# the first yard was laid out inside the office building: move anything still there
	for e3 in world_items:
		var o: Vector3 = (e3["xf"] as Transform3D).origin
		if o.x > -41.0 and o.x < -26.0 and o.z > -83.0 and o.z < -71.0 and YARD.has(String(e3["id"])):
			var yp: Vector3 = YARD[String(e3["id"])]
			yp.y = o.y
			var xf: Transform3D = e3["xf"]
			var ground_y: float = terrain.height_at(yp.x, yp.z) if terrain != null else 0.0
			xf.origin = Vector3(yp.x, ground_y + (xf.origin.y - (terrain.height_at(o.x, o.z) if terrain != null else 0.0)), yp.z)
			e3["xf"] = xf
			if e3["node"] != null:
				(e3["node"] as Node3D).global_transform = xf
			_dirty = true
	changed = true


func _process(delta: float) -> void:
	_save_t += delta
	if _dirty and _save_t > 5.0:
		_save_t = 0.0
		_dirty = false
		save()
