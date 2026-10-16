extends Node3D
## Prospecting for placer gold, anywhere on the island. Gold isn't marked on
## any map: it lies in the gravel just above bedrock, mostly in creek beds and
## valley bottoms downstream of the gold-bearing country, richer in pockets.
## Open hillsides and ridges have next to none. You find it by digging and
## panning.
##
## Start small: a shovel and a gold pan (fill the pan, wash it at water, count
## the colours), then a sluice box set at the water's edge to shovel into.
## Later: a wash plant and an excavator you buy and set up where you've found
## good ground. Wherever you dig, that 24 m square of ground becomes real
## diggable ground (dig_site.gd), saved as you leave it.

const ExcavatorScript = preload("res://scripts/excavator.gd")
const TowableScript = preload("res://scripts/towable.gd")
const EquipModels = preload("res://scripts/equipment_models.gd")
const DozerScript = preload("res://scripts/dozer.gd")
const MeshKit = preload("res://scripts/meshkit.gd")
const Flora = preload("res://scripts/flora.gd")
const SAVE := "user://prospect.cfg"
const PRICE_PER_G := 42          # the assay office pays this a gram
const PAN_M3 := 0.012            # a pan of dirt
const SHOVEL_M3 := 0.03          # a shovelful
const SLUICE_PRICE := 350
const WASHPLANT_PRICE := 6500
const EXCAVATOR_PRICE := 22000
const TUNNELER_PRICE := 46000     # the drift miner (tunneler.gd, DESIGN_NOTES 148)
const DOZER_PRICE := 30000

var terrain: RefCounted
var world: Node3D
var jobs: Node
var hud: Control
var gold_g := 0.0                # gold you're carrying, grams
var pan := {}                    # the pan's load: {} empty, or {vol, g}
var sluices: Array = []          # placed: [Transform3D]
var plants: Array = []           # wash plants: [Transform3D]
var excavators: Array = []       # nodes
var tunnelers: Array = []        # drift miners (tunneler.gd)
var owned_excavators := 0
var dozers: Array = []           # nodes
var owned_dozers := 0
var tree_cb: Callable            # main: a dozer pushed a tree over
var owned_sluices := 0
var tiles := {}                  # Vector2i -> dig_site
var _belt: FastNoiseLite
var _pocket: FastNoiseLite
var _dirty := false
var _save_t := 0.0
var _nodes: Array = []           # other meshes
var _drums: Array = []           # trommel drums: they turn while the plant runs
# Each trommel plant runs on gas (DESIGN_NOTES 88): fuel in its drum, the
# engine on or off, and what's been dumped in the hopper waiting to wash.
var plant_fuel: Array = []       # litres
var plant_on: Array = []         # bool
var plant_hopper: Array = []     # [m3, grams] waiting in the hopper
var _plant_smoke: Array = []     # CPUParticles3D at the exhaust
var _plant_fx: Array = []        # EquipModels.trommel_fx() per plant
var _plant_report: Array = []    # grams washed since the last word to the player
const PLANT_FUEL_START := 40.0   # litres in the drum when it's delivered
const PLANT_FUEL_MAX := 200.0    # a 45-gallon drum
const PLANT_BURN := 0.012        # litres a second running (game-quick)
const PLANT_RATE := 0.08         # m3 a second through the drum (a bucket in ~11 s)
const HOPPER_MAX := 4.0          # m3 the hopper holds
const CAN_L := 20.0              # a jerry can
const CAN_PRICE := 30


## A fuel pump (the strips with fuel) within reach.
func fuel_point_near(p: Vector3) -> bool:
	if world == null:
		return false
	for fp in world.get("fuel_points"):
		if Vector2(p.x - (fp as Vector3).x, p.z - (fp as Vector3).z).length() < 4.0:
			return true
	return false
var towables: Array = []         # towable.gd: the sluice trailers and wash plants (hitch them to the pickup)
# Tools are real things in the inventory: you dig by hand only with one in hand.
var inv: Node                    # inventory.gd
var power: Node                  # tunnel_power.gd: generators and rope lights
var crafting: Node               # crafting.gd: the workbench
var truck: Node                  # water_truck.gd: its valve levers and hose
var fuel_truck: Node             # the fuel truck: its pump at the back
var aim_pitch := 0.0            # main: where he's looking (radians, + up) - steers a drift up or down
var _drift_at := Vector3.INF    # last drift bite: the floor level carries on from it
const DRIFT_W := 1.8             # a hand drift: wide enough to swing a shovel, barrow past
const DRIFT_H := 2.2
const DRIFT_REACH := 0.9         # the face is this far in front of where he stands
# Ground support: every drift bite under cover is a roof that wants holding up.
# Timber sets hold it; rock holds itself; gravel and muck come down in time.
var roofs: Array = []            # [Vector3 roof point, float age s, int state 0 ok / 1 warned]
var sets: Array = []             # timber sets: [Transform3D at the floor, float height]
var _set_nodes: Array = []
var _roof_t := 0.0
var walker_pos := Vector3.INF    # main: where the pilot is (for warnings and injuries)
var on_cave_in: Callable         # main: func(point, hit_him: bool)
const SET_REACH := 1.7           # a set holds the roof this far either side
const STAND_UP := 150.0          # seconds unsupported gravel stands before it may go
var vox_edits: Array = []        # loaded voxel dig log (voxel_ground.edits is the live one)


func _ready() -> void:
	_rng.randomize()
	_belt = FastNoiseLite.new()
	_belt.seed = 1849
	_belt.frequency = 1.0 / 2600.0
	_pocket = FastNoiseLite.new()
	_pocket.seed = 1897
	_pocket.frequency = 1.0 / 45.0


# ------------------------------------------------------------------------------
#  The ground: what's in it
# ------------------------------------------------------------------------------
## For a spot: [grams of gold a cubic metre of pay gravel, depth the pay
## starts, depth to bedrock]. Creeks collect the gold where they slow down;
## gold country is in broad belts; pockets make it patchy.
func geology(x: float, z: float) -> Array:
	return terrain.geology(x, z)


## Why you can't dig here, or "".
func cannot_dig(p: Vector3) -> String:
	if terrain.strip_index_at(p.x, p.z, 4.0) >= 0:
		return "Not on the runway."
	if not terrain.hollow_at(p.x, p.z).is_empty():
		return "Not inside a building."
	var wl: float = terrain.water_level_at(p.x, p.z)
	if wl > -1.0e8 and wl - terrain.height_at(p.x, p.z) > 0.6:
		return "Too deep here: work the bank or the shallows."
	return ""


## Dig `m3` round `p`, anywhere on the ground.
## `rock`: how well the tool breaks rock below the bedrock line (0 = it
## can't, the pick ~0.6, a shovel or bucket ~0.15).
func dig(p: Vector3, radius: float, m3: float, rock: float = 0.0) -> Dictionary:
	var why := cannot_dig(p)
	if why != "":
		return {"why": why}
	if not terrain.inside(p.x, p.z):
		return {"why": "Can't dig out here."}
	var got: Dictionary = terrain.dig(p, radius, m3, rock)
	_clear_plants(p, radius)
	_dirty = true
	_maybe_find(got, p)
	return got


# ------------------------------------------------------------------------------
#  Finds (DESIGN_NOTES 91): what turns up when you dig. Gold-rush leftovers
#  near the surface, ice-age bones in the frozen muck, nuggets in the pay.
# ------------------------------------------------------------------------------
## id -> [name, value $, where ("top" near the surface, "muck" deeper
## overburden), chance a cubic metre]
const FINDS := {
	"coin": ["1898 silver dollar", 120, "top", 0.04],
	"bottle": ["Gold-rush bottle", 25, "top", 0.15],
	"relic_pan": ["Rusted gold pan", 40, "top", 0.04],
	"bison_skull": ["Steppe bison skull", 400, "muck", 0.03],
	"tusk": ["Mammoth tusk", 1500, "muck", 0.012],
}
const NUGGETS_PER_M3 := 0.12     # in the pay gravel
var _rng := RandomNumberGenerator.new()


func _maybe_find(got: Dictionary, p: Vector3) -> void:
	var over := float(got.get("over", 0.0))
	var pay := float(got.get("pay", 0.0))
	if over + pay <= 0.0:
		return
	var depth: float = terrain.natural_at(p.x, p.z) - p.y
	for id in FINDS.keys():
		var f: Array = FINDS[id]
		var in_layer: bool = depth < 1.6 if f[2] == "top" else depth > 1.0
		if in_layer and _rng.randf() < float(f[3]) * over:
			_found(id, p)
			return
	if pay > 0.0 and _rng.randf() < NUGGETS_PER_M3 * pay:
		var g := 1.0 + 14.0 * pow(_rng.randf(), 3.0)     # mostly small, now and then a big one
		gold_g += g
		_say("A nugget! %.1f g, right there in the gravel (%.0f g carried)." % [g, gold_g])


func _found(id: String, p: Vector3) -> void:
	var f: Array = FINDS[id]
	var where := ""
	if inv != null and inv.add(id, 1) > 0:
		where = "In your pack."
	elif inv != null:
		inv.place_in_world(id, 1, p + Vector3(0, 0.3, 0), 0.0)
		where = "Too much to carry: it's on the ground."
	var why := ""
	match id:
		"tusk":
			why = " Ivory from the ice age, frozen in the muck for thirty thousand years."
		"bison_skull":
			why = " A steppe bison, out of the frozen muck."
		"coin", "bottle", "relic_pan":
			why = " Someone worked this ground in the rush."
	_say("You turned up a %s!%s %s" % [String(f[0]).to_lower(), why, where])


func has_finds() -> bool:
	if inv == null:
		return false
	if inv.has("gold_bar"):
		return true
	for id in FINDS.keys():
		if inv.has(id):
			return true
	return false


## Grade a disc of ground toward one level (the dozer's blade): the cut
## comes back as spoil for the blade, hollows are filled from `fill_m3`.
func grade_level(p: Vector3, radius: float, target: float, fill_m3: float, cut_m3: float, max_step: float = 0.30, holes_only: bool = false) -> Dictionary:
	if cannot_dig(p) != "" or not terrain.inside(p.x, p.z):
		return {}
	var got: Dictionary = terrain.level(p, radius, target, fill_m3, cut_m3, max_step, holes_only)
	_clear_plants(p, radius)
	_dirty = true
	return got


func pile(p: Vector3, m3: float) -> void:
	if cannot_dig(p) != "" or not terrain.inside(p.x, p.z):
		return
	terrain.deposit(p, m3)
	_clear_plants(p, 2.0)
	_dirty = true


## Torn-up ground: the grass and brush on it go.
func _clear_plants(p: Vector3, radius: float) -> void:
	terrain.clear_spot(p.x, p.z, radius + 0.8)
	if world != null and world.vegetation != null:
		world.vegetation.refresh_area(p, radius + 2.0)


# ------------------------------------------------------------------------------
#  Hand tools: shovel, pan, sluice box
# ------------------------------------------------------------------------------
## Water to pan in: a lake, the sea, or a running creek (the creek beds of
## the drainages carry a trickle even where no water is drawn).
## The same sums the ground shader uses to wind the creek water through its
## band, so the pan works where you can see water (a little forgiving).
static func _hash21(q: Vector2) -> float:
	var r := Vector2(fposmod(q.x * 0.1031, 1.0), fposmod(q.y * 0.1030, 1.0))
	var d := r.dot(Vector2(r.y + 33.33, r.x + 33.33))
	r += Vector2(d, d)
	return fposmod((r.x + r.y) * r.x, 1.0)


static func _vnoise(q: Vector2) -> float:
	var i := q.floor()
	var f := q - i
	var u := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := _hash21(i)
	var b := _hash21(i + Vector2(1.0, 0.0))
	var c := _hash21(i + Vector2(0.0, 1.0))
	var d := _hash21(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


static func _fbm3(q: Vector2) -> float:
	var v := 0.5 * _vnoise(q)
	v += 0.25 * _vnoise(q * 2.03 + Vector2(17.1, 17.1))
	v += 0.125 * _vnoise(q * 4.07 + Vector2(3.7, 3.7))
	return v / 0.875


## Standing at drawn creek water (the thread or a pond in the willow band)?
func creek_water_at(x: float, z: float) -> bool:
	if terrain.has_method("creek_at"):
		return terrain.creek_at(x, z)
	if Flora.field(terrain, terrain.creek, x, z) < 0.6:
		return false
	var q := Vector2(x, z)
	var thread := 1.0 - absf(_fbm3(q / 26.0 + Vector2(9.0, 9.0)) - 0.5) * 2.0
	var pool := _fbm3(q / 9.0 + Vector2(23.0, 23.0))
	return thread > 0.84 or pool > 0.81


func near_water(p: Vector3, reach: float = 3.0) -> bool:
	for a in range(5):
		var q2 := p + Vector3(cos(a * TAU / 4.0), 0, sin(a * TAU / 4.0)) * (reach if a > 0 else 0.0)
		if creek_water_at(q2.x, q2.z):
			return true
	for a in range(8):
		var q := p + Vector3(cos(a * TAU / 8.0), 0, sin(a * TAU / 8.0)) * reach
		for qq in [p, q]:
			var wl: float = terrain.water_level_at(qq.x, qq.z)
			if wl > -1.0e8 and wl > terrain.height_at(qq.x, qq.z) + 0.05:
				return true
	return false


func sluice_near(p: Vector3) -> int:
	for i in range(sluices.size()):
		if (sluices[i] as Transform3D).origin.distance_to(p) < 4.0 and _set_up("sluice", i):
			return i
	return -1


## What's at the bottom of the hole here: "over", "pay" or "rock".
func layer_at(p: Vector3) -> String:
	var depth: float = terrain.natural_at(p.x, p.z) - terrain.height_at(p.x, p.z)
	var g := geology(p.x, p.z)
	if depth < float(g[1]) - 0.03:
		return "over"
	if depth < float(g[2]) - 0.03:
		return "pay"
	return "rock"


## What the interact key does on foot here: [action, prompt] or [].
func target(p: Vector3, front: Vector3) -> Array:
	var key := Game.hint("interact")
	if not pan.is_empty() and near_water(p):
		return ["pan", "%s  Pan it out at the water" % key]
	var pt := _pump_target(p, key)
	if not pt.is_empty():
		return pt
	var tool_in_hand: String = inv.in_hand() if inv != null else "shovel"
	if truck != null:
		var tt: Array = truck.foot_target(p, key)
		if not tt.is_empty():
			return tt
	if fuel_truck != null:
		var ft: Array = fuel_truck.foot_target(p, key)
		if not ft.is_empty():
			return ft
	if crafting != null:
		var cr: Array = crafting.target(p, key)
		if not cr.is_empty():
			return cr
	if power != null:
		var pw: Array = power.target(p, tool_in_hand, key)
		if not pw.is_empty():
			return pw
	# The trommel's engine: start / stop it, or pour a can into its drum.
	var eng := plant_engine_near(p)
	if eng >= 0:
		if tool_in_hand == "gas_can":
			return ["plant_fuel", "%s  Pour the gas can into the trommel's fuel drum (%.0f L in it)" % [key, float(plant_fuel[eng])]]
		return ["plant_engine", "%s  %s the trommel.  %s" % [key, "Stop" if bool(plant_on[eng]) else "Start", plant_engine_text(eng)]]
	if tool_in_hand == "gas_can_empty" and fuel_point_near(p):
		return ["can_fill", "%s  Fill the gas can at the pump" % key]
	if tool_in_hand in ["gas_can", "gas_can_empty"]:
		return []
	if tool_in_hand == "ladder":
		var lip := _ladder_spot(p, front)
		if lip.is_empty():
			return ["", "Hang the ladder at the edge of a drop (2 m or more)."]
		return ["ladder", "%s  Hang the ladder down here (%.0f m)" % [key, float(lip["top"].y) - float(lip["bottom"])]]
	if tool_in_hand == "timber":
		var vgt = _vox()
		if vgt != null and p.y < terrain.height_at(p.x, p.z) - 1.2:
			var bare := 0
			for r in roofs:
				if (r[0] as Vector3).distance_to(p) < 12.0 and not _supported(r[0]):
					bare += 1
			var here := "this spot's already held" if _supported(p + Vector3(0, DRIFT_H, 0)) else "holds the roof %.1f m either side" % SET_REACH
			return ["timber", "%s  Stand a timber set here (%s; %d bare span%s near you)" % [key, here, bare, "" if bare == 1 else "s"]]
		return ["", "Timber sets go up inside a drift, under the roof."]
	if not tool_in_hand in ["shovel", "pick"]:
		return []
	var tun := _tunnel_target(p, front, key)
	if not tun.is_empty():
		return tun
	var why := cannot_dig(front)
	if why != "":
		return []
	var layer := layer_at(front)
	if layer == "rock":
		var vs := _vein_floor(front)
		if not vs.is_empty():
			return _vein_prompt(vs, key)
		# down on bedrock: the pick breaks it, a shovel only chips at it
		if tool_in_hand == "pick":
			return ["dig_rock", "%s  Break the rock with the pick (%.0f m down)" % [key, terrain.natural_at(front.x, front.z) - terrain.height_at(front.x, front.z)]]
		return ["dig_rock", "%s  Chip at the bedrock (slow: a pick breaks it)" % key]
	if tool_in_hand != "shovel":
		return []                 # a pick breaks rock; the shovel moves the loose ground
	if layer == "over":
		return ["dig", "%s  Dig down (topsoil and overburden: the gold sits lower, in the gravel)" % key]
	if sluice_near(p) >= 0:
		return ["sluice", "%s  Shovel the gravel into the sluice box" % key]
	if pan.is_empty() and (inv == null or inv.has("gold_pan")):
		return ["fill", "%s  Gravel! Fill the pan" % key]
	return ["dig", "%s  Dig (the pan's full: take it to water to pan it)" % key]


# ------------------------------------------------------------------------------
#  Tunnelling by hand (voxel ground): drive a drift into a face, sink the floor
# ------------------------------------------------------------------------------
## What's at a 3-D point: "over", "pay" or "rock" (by depth below the natural surface).
func layer_at3(q: Vector3) -> String:
	var depth: float = terrain.natural_at(q.x, q.z) - q.y
	var g := geology(q.x, q.z)
	if depth < float(g[1]):
		return "over"
	if depth < float(g[2]):
		return "pay"
	return "rock"


func _face_point(p: Vector3, front: Vector3) -> Vector3:
	var fwd := Vector3(front.x - p.x, 0, front.z - p.z)
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	return p + fwd * 0.75 + Vector3(0, 1.0, 0)


func _tunnel_target(p: Vector3, front: Vector3, key: String) -> Array:
	var vg = _vox()
	if vg == null or not terrain.inside(p.x, p.z) or not vg.ready_at(p):
		return []
	var face := _face_point(p, front)
	var under: bool = p.y < terrain.height_at(p.x, p.z) - 1.2
	# a face: ground ahead standing above the knee (a steep bank, a cut, a drift end)
	if vg.sdf_at(face + Vector3(0, -0.4, 0)) < 0.0:
		if strip_or_building(face):
			return ["", "Not under the runway or the buildings."]
		var layer := layer_at3(face)
		if layer == "pay" and pan.is_empty() and (inv == null or inv.has("gold_pan")):
			return ["tunnel_pan", "%s  Pay gravel in the face! Fill the pan from it" % key]
		if layer == "rock":
			var vf := _vein_face(face)
			if not vf.is_empty():
				return _vein_prompt(vf, key)
		var pick: bool = inv != null and inv.holding("pick")
		var what := "Dig into the face" if layer != "rock" else ("Break into the rock" if pick else "Dig into the rock (slow going without a pick)")
		return ["tunnel", "%s  %s" % [key, what]]
	if under:
		return ["sink", "%s  Dig the floor down" % key]
	return []


# ------------------------------------------------------------------------------
#  Pumping a flooded hole out (water_sim.gd)
# ------------------------------------------------------------------------------
const PUMP_RATE := 0.25          # m3 a second (a big trash pump, game-quick)
var pump_nodes: Array = []       # [pump dict from water_sim, node]
var _near_pump := -1


func _water():
	return terrain.get("water")


func _pump_target(p: Vector3, key: String) -> Array:
	var ws = _water()
	if ws == null:
		return []
	_near_pump = -1
	for i in range(pump_nodes.size()):
		var pd: Dictionary = pump_nodes[i][0]
		var at: Vector3 = (pump_nodes[i][1] as Node3D).global_position
		if Vector2(at.x - p.x, at.z - p.z).length() < 1.8:
			_near_pump = i
			if bool(pd["on"]):
				return ["pump_off", "%s  Stop the pump (%.1f m3 moved)" % [key, float(pd["moved"])]]
			return ["pump_on", "%s  Start the pump   %s  Take it back" % [key, Game.hint("door")]]
	if inv != null and inv.holding("pump"):
		if _water_near(p, 3.0) != Vector3.INF:
			return ["pump_set", "%s  Set the pump here: suction in the water, hose to the lowest ground" % key]
		return ["", "Set the pump at the water's edge."]
	return []


func _water_near(p: Vector3, r: float) -> Vector3:
	var ws = _water()
	var best := Vector3.INF
	var bd := r
	var step := 0.5
	var x := -r
	while x <= r:
		var z := -r
		while z <= r:
			var q := p + Vector3(x, 0, z)
			if ws.depth_at(q.x, q.z) > 0.08:
				var d := Vector2(x, z).length()
				if d < bd:
					bd = d
					best = Vector3(q.x, terrain.height_at(q.x, q.z), q.z)
			z += step
		x += step
	return best


## The hose end: the lowest ground 12-20 m away that's below the intake.
func _hose_end(intake: Vector3) -> Vector3:
	var best := Vector3.INF
	var by := intake.y + 50.0
	for ring in [12.0, 16.0, 20.0]:
		for a in range(24):
			var ang := TAU * float(a) / 24.0
			var q := intake + Vector3(cos(ang), 0, sin(ang)) * float(ring)
			if not terrain.inside(q.x, q.z):
				continue
			var y: float = terrain.height_at(q.x, q.z)
			var ws = _water()
			if ws.depth_at(q.x, q.z) > 0.05:
				continue          # not back into the same hole
			if y < by:
				by = y
				best = Vector3(q.x, y, q.z)
	return best


func _pump_act(a: String, p: Vector3, front: Vector3) -> String:
	var ws = _water()
	if ws == null:
		return ""
	match a:
		"pump_set":
			var intake := _water_near(p, 3.0)
			var outlet := _hose_end(intake)
			if outlet == Vector3.INF:
				return "Nowhere lower to run the hose to."
			inv.remove("pump", 1)
			var pd: Dictionary = ws.add_pump(intake, outlet, PUMP_RATE)
			var node := _spawn_pump(p, intake, outlet)
			pump_nodes.append([pd, node])
			return "Pump running: %.0f m of hose down to the low ground. Watch the hole drop." % intake.distance_to(outlet)
		"pump_off", "pump_on":
			if _near_pump >= 0:
				var pd2: Dictionary = pump_nodes[_near_pump][0]
				pd2["on"] = a == "pump_on"
				return "Pump %s." % ("started" if pd2["on"] else "stopped")
	return ""


## Y beside a stopped pump: coil the hose and carry it off.
func take_pump(p: Vector3) -> String:
	_pump_target(p, "")
	if _near_pump < 0 or inv == null:
		return ""
	var pd: Dictionary = pump_nodes[_near_pump][0]
	if bool(pd["on"]):
		return "Stop it first."
	if inv.add("pump", 1, true) <= 0:
		return "Too much on you to carry the pump."
	_water().pumps.erase(pd)
	(pump_nodes[_near_pump][1] as Node).queue_free()
	pump_nodes.remove_at(_near_pump)
	return "Pump and hose picked up."


func _spawn_pump(at: Vector3, intake: Vector3, outlet: Vector3) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var y: float = terrain.height_at(at.x, at.z)
	root.global_position = Vector3(at.x, y, at.z)
	var body: Node3D = inv.build_mesh("pump") if inv != null else Node3D.new()
	root.add_child(body)
	# suction hose to the water and discharge hose to the outlet
	var k := MeshKit.new()
	var base := root.global_position + Vector3(0, 0.2, 0.2)
	var pts := [base, (base + intake) * 0.5 + Vector3(0, 0.1, 0), intake + Vector3(0, -0.2, 0)]
	var pts2 := [base, base.lerp(outlet, 0.33), base.lerp(outlet, 0.66), outlet + Vector3(0, 0.08, 0)]
	for chain in [pts, pts2]:
		for i in range(chain.size() - 1):
			var a: Vector3 = chain[i]
			var b: Vector3 = chain[i + 1]
			a.y = maxf(a.y, terrain.height_at(a.x, a.z) + 0.05)
			b.y = maxf(b.y, terrain.height_at(b.x, b.z) + 0.05) if i + 1 < chain.size() - 1 else b.y
			var d := b - a
			if d.length() < 0.01:
				continue
			var yax := d.normalized()
			var xax := yax.cross(Vector3.UP if absf(yax.y) < 0.9 else Vector3.RIGHT).normalized()
			k.cylinder(Transform3D(Basis(xax, yax, xax.cross(yax)), a - root.global_position), 0.045, 0.045, d.length(), 6, Color(0.1, 0.1, 0.1), false)
	root.add_child(k.instance("Hoses"))
	return root


## Stand a timber set (two posts and a cap) across the drift in front of him.
func set_timber(p: Vector3, front: Vector3) -> String:
	var vg = _vox()
	if vg == null or inv == null or not inv.holding("timber"):
		return ""
	var fwd := Vector3(front.x - p.x, 0, front.z - p.z).normalized()
	var at := p + fwd * 0.5
	var roof_h := 1.4
	while roof_h < 3.2 and vg.sdf_at(at + Vector3(0, roof_h, 0)) > 0.0:
		roof_h += 0.05
	if roof_h >= 3.2:
		return "Nothing overhead to hold up here."
	var xf := Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), at)
	sets.append([xf, roof_h])
	_spawn_set(xf, roof_h)
	inv.remove("timber", 1)
	_dirty = true
	var held := 0
	for r in roofs:
		if _supported(r[0]):
			held += 1
	return "Timber set stood. %d of %d roof spans in your drifts are held." % [held, roofs.size()]


func _supported(q: Vector3) -> bool:
	for st in sets:
		var o: Vector3 = (st[0] as Transform3D).origin
		if Vector2(o.x - q.x, o.z - q.z).length() < SET_REACH and absf(o.y + float(st[1]) - q.y) < 1.6:
			return true
	return false


## A timber set (DESIGN_NOTES 132), after Dave's pictures of real drifts.
## Inside the hill: round logs - the same logs you buck from the trees,
## barked dark and wet - two posts splayed a little wider at the foot, a cap
## log across, poles laid lengthways over the cap against the roof (lagging,
## reaching on to the next set), and some side poles packed in behind the
## posts. Near the mouth of the drift, where the cover is thin: a portal
## set of square-sawn timbers - posts on a sill, a heavy cap overhanging
## them with header blocks on top, boards up the sides.
func _spawn_set(xf: Transform3D, h: float) -> void:
	var k := MeshKit.new()
	var o := xf.origin
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(roundi(o.x * 10.0), roundi(o.y * 10.0), roundi(o.z * 10.0)))
	var cover: float = terrain.height_at(o.x, o.z) - (o.y + h)
	if cover < 1.2:
		_portal_set(k, xf, h, rng)
	else:
		_log_set(k, xf, h, rng)
	var mi := k.instance("TimberSet")
	add_child(mi)
	_set_nodes.append(mi)


const LOG_BARK := Color(0.25, 0.18, 0.12)
const LOG_PEELED := Color(0.40, 0.29, 0.19)
const LOG_END := Color(0.56, 0.45, 0.31)


## A round log from a to b, radius r0 at a and r1 at b, with pale cut ends.
static func _log(k, a: Vector3, b: Vector3, r0: float, r1: float, col: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var bs := Basis(x, y, z)
	k.cylinder(Transform3D(bs, a), r0, r1, l, 9, col, false)
	k.cylinder(Transform3D(bs, a - y * 0.004), r0 * 0.96, r0 * 0.96, 0.008, 9, LOG_END, true)
	k.cylinder(Transform3D(bs, b - y * 0.004), r1 * 0.96, r1 * 0.96, 0.008, 9, LOG_END.darkened(0.08), true)


func _log_col(rng: RandomNumberGenerator) -> Color:
	# peeled in patches, darkened with damp and age
	return LOG_BARK.lerp(LOG_PEELED, rng.randf_range(0.2, 0.9)).darkened(rng.randf_range(0.0, 0.25))


func _log_set(k, xf: Transform3D, h: float, rng: RandomNumberGenerator) -> void:
	var cap_r := rng.randf_range(0.10, 0.12)
	var cap_y := h - cap_r - 0.02
	# posts: splayed, the foot wider than the head, each its own log
	for sx in [-1.0, 1.0]:
		var foot := Vector3(sx * rng.randf_range(0.70, 0.76), -0.05, rng.randf_range(-0.04, 0.04))
		var head := Vector3(sx * rng.randf_range(0.58, 0.63), cap_y - cap_r * 0.6, rng.randf_range(-0.03, 0.03))
		var r := rng.randf_range(0.085, 0.105)
		_log(k, xf * foot, xf * head, r * 1.08, r, _log_col(rng))
	# the cap across the heads, overhanging a little each side
	var over := rng.randf_range(0.12, 0.2)
	_log(k, xf * Vector3(-0.75 - over, cap_y + rng.randf_range(-0.02, 0.02), 0.0), xf * Vector3(0.75 + over, cap_y + rng.randf_range(-0.02, 0.02), 0.0), cap_r * 1.05, cap_r, _log_col(rng))
	# lagging over the cap against the roof, running on toward the next set
	var n := rng.randi_range(5, 7)
	for i in range(n):
		var lx := lerpf(-0.62, 0.62, float(i) / float(n - 1)) + rng.randf_range(-0.03, 0.03)
		var lr := rng.randf_range(0.045, 0.065)
		var ly := cap_y + cap_r + lr - 0.01
		var z0 := rng.randf_range(-0.95, -0.7)
		var z1 := rng.randf_range(0.7, 0.95)
		_log(k, xf * Vector3(lx, ly, z0), xf * Vector3(lx + rng.randf_range(-0.05, 0.05), ly + rng.randf_range(-0.02, 0.02), z1), lr, lr * 0.9, _log_col(rng))
	# side poles packed in behind the posts, on one side or both
	for sx2 in [-1.0, 1.0]:
		if rng.randf() < 0.45:
			continue
		var ny := rng.randi_range(5, 8)
		for j in range(ny):
			var y := rng.randf_range(0.15, cap_y - 0.15)
			var sr := rng.randf_range(0.05, 0.07)
			_log(k, xf * Vector3(sx2 * 0.84, y, rng.randf_range(-0.85, -0.6)), xf * Vector3(sx2 * 0.84, y + rng.randf_range(-0.05, 0.05), rng.randf_range(0.6, 0.85)), sr, sr * 0.9, _log_col(rng))
	# a wedge driven between the cap and a post head now and then
	if rng.randf() < 0.6:
		var wx := (1.0 if rng.randf() < 0.5 else -1.0) * 0.6
		k.box(xf * Transform3D(Basis(Vector3.BACK, 0.25 * signf(wx)), Vector3(wx, cap_y - cap_r * 0.9, 0.0)), Vector3(0.16, 0.05, 0.12), LOG_END.darkened(0.25))


func _portal_set(k, xf: Transform3D, h: float, rng: RandomNumberGenerator) -> void:
	var wood := Color(0.62, 0.40, 0.30).darkened(rng.randf_range(0.0, 0.12))     # fresh-sawn
	var wood2 := wood.lightened(0.06)
	var cap_h := 0.26
	var cap_y := h - cap_h * 0.5 - 0.02
	# sill along the floor, the two posts standing on it
	k.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.04, 0.0)), Vector3(1.55, 0.10, 0.24), wood.darkened(0.15))
	for sx in [-0.68, 0.68]:
		k.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, (cap_y - cap_h * 0.5 + 0.09) * 0.5 + 0.045, 0.0)), Vector3(0.20, cap_y - cap_h * 0.5 - 0.09, 0.20), wood)
		# boards up the outside of each post
		for bi in range(3):
			var bz := -0.22 + bi * 0.22
			k.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx + signf(sx) * 0.16, (cap_y - cap_h * 0.5) * 0.5, bz)), Vector3(0.05, cap_y - cap_h * 0.5, 0.2), wood2.darkened(rng.randf_range(0.0, 0.1)))
	# the cap: heavy, overhanging the posts, header blocks on top
	k.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, cap_y, 0.0)), Vector3(2.05, cap_h, 0.28), wood2)
	var nb := 7
	for i in range(nb):
		var bx := lerpf(-0.9, 0.9, float(i) / float(nb - 1))
		k.box(xf * Transform3D(Basis.IDENTITY, Vector3(bx, cap_y + cap_h * 0.5 + 0.07, rng.randf_range(-0.02, 0.02))), Vector3(0.26, 0.14, 0.26), wood.darkened(rng.randf_range(0.0, 0.15)))
	# bolt heads on the posts and cap
	for sx3 in [-0.68, 0.68]:
		for by in [0.5, 1.2]:
			k.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx3, by, -0.105)), Vector3(0.025, 0.025, 0.01), Color(0.25, 0.22, 0.2))


## Every few seconds: unsupported gravel roofs age, creak, and fall in.
func _ground_check(dt: float) -> void:
	var vg = _vox()
	if vg == null or roofs.is_empty():
		return
	var keep: Array = []
	for r in roofs:
		var q: Vector3 = r[0]
		if _supported(q):
			keep.append(r)
			continue
		r[1] = float(r[1]) + dt
		var near_him: bool = walker_pos != Vector3.INF and walker_pos.distance_to(q) < 14.0
		if float(r[1]) > STAND_UP and int(r[2]) == 0:
			r[2] = 1
			if near_him:
				_say("Dirt trickles from the roof. The ground's working: get timber up, or get out.")
			keep.append(r)
			continue
		if int(r[2]) == 1 and randf() < 0.12:
			# it comes down: the drift fills back in there, the surface sags
			vg.fill(q + Vector3(0, -0.4, 0), 1.0)
			vg.fill(q + Vector3(0, -1.1, 0), 0.9)
			var hit: bool = walker_pos != Vector3.INF and Vector2(walker_pos.x - q.x, walker_pos.z - q.z).length() < 1.3 and absf(walker_pos.y + 1.0 - q.y) < 2.5
			if terrain.inside(q.x, q.z):
				terrain.dig(Vector3(q.x, 0, q.z), 1.4, 0.8)      # a sag in the ground above
			if on_cave_in.is_valid():
				on_cave_in.call(q, hit)
			_dirty = true
			continue
		keep.append(r)
	roofs = keep


func strip_or_building(q: Vector3) -> bool:
	return terrain.strip_index_at(q.x, q.z, 6.0) >= 0 or not terrain.hollow_at(q.x, q.z).is_empty()


func _tunnel_act(a: String, p: Vector3, front: Vector3) -> String:
	var vg = _vox()
	if vg == null:
		return ""
	var face := _face_point(p, front)
	var fwd := Vector3(face.x - p.x, 0, face.z - p.z).normalized()
	var layer := layer_at3(face)
	_dirty = true
	match a:
		"tunnel_pan":
			vg.carve(face, 0.33)
			var g := geology(face.x, face.z)
			pan = {"vol": PAN_M3, "g": float(g[0]) * PAN_M3, "pay": true}
			return "Pan full of pay gravel from the face." + ("" if near_water(p) else " Find water to pan it.")
		"tunnel":
			# a square drift, DRIFT_W x DRIFT_H, a bite at a time
			var pick: bool = inv != null and inv.holding("pick")
			var hard := layer == "rock" and not pick
			var adv := 0.5 if not hard else 0.3
			if pick and layer != "rock":
				adv = 0.4           # a pick loosens gravel, but the shovel shifts it
			# Keep the drift's floor where the last bite left it; look up or
			# down (past a little dead zone) to drive it up or down a grade.
			var floor_y := p.y
			var back := p
			if _drift_at != Vector3.INF and Vector2(_drift_at.x - p.x, _drift_at.z - p.z).length() < 2.5 and absf(_drift_at.y - p.y) < 0.6:
				floor_y = _drift_at.y
				back = _drift_at
			var grade := 0.0
			if absf(aim_pitch) > 0.25:
				grade = clampf(tan(aim_pitch), -0.5, 0.5)
			var yaw := atan2(-fwd.x, -fwd.z)
			# Square heading: flat floor, straight walls, flat roof. The bite
			# reaches back over the last one so the walls run on without a seam.
			var face_at := back + fwd * (DRIFT_REACH + adv) if back != p else p + fwd * (DRIFT_REACH + adv - 0.3)
			face_at.y = floor_y + grade * adv
			var mid := (back if back != p else p).lerp(face_at, 0.5)
			mid.y = minf(floor_y, face_at.y)
			var len := Vector2(face_at.x - mid.x, face_at.z - mid.z).length() * 2.0
			vg.cut_box(mid, yaw, DRIFT_W, DRIFT_H, maxf(len, adv + 0.4))
			# hand-dug, not machined: a few bites out of the walls and the
			# roof's corners so the drift comes out rough and a little arched
			var side_v := Vector3(-fwd.z, 0, fwd.x)
			for ri in range(3):
				var along := randf_range(-0.2, adv + 0.2)
				var sd := 1.0 if randf() < 0.5 else -1.0
				var at := (back if back != p else p) + fwd * (DRIFT_REACH + along)
				at.y = floor_y
				if ri == 2:
					vg.carve(at + side_v * sd * randf_range(0.35, 0.6) + Vector3(0, DRIFT_H - 0.05, 0), randf_range(0.3, 0.45))
				else:
					vg.carve(at + side_v * sd * (DRIFT_W * 0.5 + randf_range(-0.05, 0.1)) + Vector3(0, randf_range(0.5, DRIFT_H - 0.4), 0), randf_range(0.22, 0.38))
			var base := face_at - fwd * DRIFT_REACH
			_drift_at = base
			var roof := base + Vector3(0, DRIFT_H, 0)
			if terrain.height_at(roof.x, roof.z) - roof.y > 0.5 and layer_at3(roof + Vector3(0, 0.3, 0)) != "rock":
				roofs.append([roof, 0.0, 0])
			if hard:
				return "Rock. Chip, chip... a pick would go faster."
			return ""
		"sink":
			vg.cut_box(p + fwd * 0.5 + Vector3(0, -0.5, 0), atan2(-fwd.x, -fwd.z), 1.2, 0.6, 1.2)
			_drift_at = Vector3.INF
			return ""
	return ""


## Rocks in the dirt (DESIGN_NOTES 133): now and then a shovelful turns
## up a rock too big for the shovel. It lies in the hole (or at the face of
## a drift) and blocks the digging there until it's lifted out by hand and
## carried off. main sets these to the cargo's rock pieces.
var rock_found: Callable           # func(at: Vector3, kg: float)
var cart_fill: Callable            # func(p, layer, g_per_m3) -> String: a shovelful into an ore car near p (mine_rails.gd)
var rock_in_way: Callable          # func(at: Vector3, r: float) -> Dictionary
const ROCK_CHANCE := {"dig": 0.04, "tunnel": 0.06, "sink": 0.05}     # about one in 20 shovelfuls


func _rock_spot(a: String, p: Vector3, front: Vector3) -> Vector3:
	var f := Vector3(front.x - p.x, 0, front.z - p.z)
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	if a in ["tunnel", "tunnel_pan", "sink"]:
		return Vector3(p.x, p.y, p.z) + f * 0.7
	var q := p + f * 0.9
	q.y = terrain.height_at(q.x, q.z)
	return q


func act(a: String, p: Vector3, front: Vector3) -> String:
	var digging := a in ["dig", "sluice", "fill", "tunnel", "tunnel_pan", "sink"]
	if digging and rock_in_way.is_valid():
		var q := _rock_spot(a, p, front)
		var rk: Dictionary = rock_in_way.call(q, 0.9)
		if not rk.is_empty():
			# one you can get the blade under: levered out and flicked aside
			if float(rk["kg"]) < 40.0 and inv != null and inv.holding("shovel") and rocks_take.is_valid() and rocks_put.is_valid():
				var taken: Array = rocks_take.call(rk["pos"], 0.05)
				rocks_put.call(_throw_spot(p, front), taken)
				return "You lever the rock out with the shovel and flick it aside."
			return "A big rock's in the way: too heavy to shovel out. Lift it by hand and carry it off, or scoop it up with the loader."
	var msg := _act_inner(a, p, front)
	# an ore car alongside: the shovelful goes in it (DESIGN_NOTES 151)
	if a in ["tunnel", "sink", "dig"] and cart_fill.is_valid() and not msg.begins_with("Rock") and not msg.begins_with("Not ") and not msg.begins_with("A big"):
		var fq := _face_point(p, front) if a != "dig" else front + Vector3(0, -0.3, 0)
		var gl: Array = geology(fq.x, fq.z)
		var cm: String = cart_fill.call(p, layer_at3(fq), float(gl[0]))
		if cm != "":
			msg = cm if msg == "" else msg + "  " + cm
	if msg == "" and ROCK_CHANCE.has(a) and rock_found.is_valid() and randf() < float(ROCK_CHANCE[a]):
		var q2 := _rock_spot(a, p, front)
		if a in ["tunnel", "sink"]:
			var vg = _vox()
			if vg != null:
				q2.y = vg.floor_below(q2 + Vector3(0, 0.8, 0), 3.0)
		var kg := randf_range(18.0, 75.0)
		rock_found.call(q2, kg)
		msg = "Clunk - the shovel hits a rock%s. Too big to shovel: lift it out by hand." % (" the size of a melon" if kg < 35.0 else (" - a heavy one" if kg > 60.0 else ""))
	return msg


func _act_inner(a: String, p: Vector3, front: Vector3) -> String:
	if a == "ladder":
		var lip := _ladder_spot(p, front)
		if lip.is_empty() or inv == null:
			return ""
		inv.remove("ladder", 1)
		ladders.append([lip["top"], float(lip["bottom"]), lip["out"]])
		_spawn_ladder(lip["top"], float(lip["bottom"]))
		_dirty = true
		return "Ladder hung: %.0f m down. Walk onto it, then forward climbs up, back climbs down; %s at the top pulls it up." % [float(lip["top"].y) - float(lip["bottom"]), Game.hint("door")]
	if a.begins_with("pump"):
		return _pump_act(a, p, front)
	if a == "vein":
		return _vein_act(p, front)
	if a in ["tunnel", "tunnel_pan", "sink"]:
		return _tunnel_act(a, p, front)
	if a == "timber":
		return set_timber(p, front)
	if (a == "truck_fuel" or a.begins_with("fuel_")) and fuel_truck != null:
		return fuel_truck.foot_act(a, p)
	if a.begins_with("truck_") and truck != null:
		return truck.foot_act(a, p)
	if a == "craft" and crafting != null:
		return crafting.craft()
	if power != null and (a.begins_with("gen_") or a == "rope"):
		return power.act(a, p, front, atan2(p.x - front.x, p.z - front.z))
	if a == "plant_engine":
		var e1 := plant_engine_near(p)
		return plant_toggle(e1) if e1 >= 0 else ""
	if a == "plant_fuel":
		var e2 := plant_engine_near(p)
		if e2 < 0 or inv == null or not inv.holding("gas_can"):
			return ""
		var room := PLANT_FUEL_MAX - float(plant_fuel[e2])
		if room < 0.5:
			return "The trommel's fuel drum is full."
		var took: float = plant_add_fuel(e2, inv.pour_can(room))
		return "Poured %.0f L into the trommel's drum: %.0f L now." % [took, float(plant_fuel[e2])]
	if a == "can_fill":
		if inv == null or not inv.holding("gas_can_empty"):
			return ""
		inv.fill_can(CAN_L)
		if not Game.sandbox and jobs != null:
			jobs.money -= CAN_PRICE
		return "Filled the gas can: %.0f L%s." % [CAN_L, "" if Game.sandbox else " ($%d)" % CAN_PRICE]
	match a:
		"fill":
			var got := dig(front, 0.3, PAN_M3)
			if got.has("why"):
				return String(got["why"])
			var vol := float(got.get("over", 0.0)) + float(got.get("pay", 0.0))
			if vol < 0.001:
				return "Bedrock: nothing to dig." if bool(got.get("bedrock", false)) else ""
			pan = {"vol": vol, "g": float(got.get("g", 0.0)), "pay": float(got.get("pay", 0.0)) > 0.0001}
			return "Pan full. %s" % ("Gravel near bedrock: promising." if bool(pan["pay"]) else "Just topsoil and silt so far.") + ("" if near_water(p) else " Find water to pan it.")
		"pan":
			var g := float(pan["g"]) * 0.85
			pan = {}
			gold_g += g
			_dirty = true
			var colours := int(round(g * 45.0))
			if colours <= 0:
				return "Nothing but black sand. Try somewhere else, or deeper."
			if colours < 4:
				return "%d colour%s in the pan: a trace. (%.2f g, %.1f g carried)" % [colours, "" if colours == 1 else "s", g, gold_g]
			if colours < 20:
				return "%d colours! Worth a closer look here. (%.2f g, %.1f g carried)" % [colours, g, gold_g]
			return "The pan's bottom is yellow: %d colours, %.2f g! Rich ground. (%.1f g carried)" % [colours, g, gold_g]
		"sluice":
			var got2 := dig(front, 0.35, SHOVEL_M3)
			if got2.has("why"):
				return String(got2["why"])
			var g2 := float(got2.get("g", 0.0)) * 0.9
			gold_g += g2
			_dirty = true
			return ("Into the sluice: %.2f g caught in the riffles (%.1f g carried)." % [g2, gold_g]) if g2 > 0.005 else "Into the sluice: no gold in that shovelful."
		"dig_rock":
			var pick: bool = inv != null and inv.holding("pick")
			var got4 := dig(front, 0.45, SHOVEL_M3 * 2.5, 0.6 if pick else 0.12)
			if got4.has("why"):
				return String(got4["why"])
			pile(_throw_spot(p, front), float(got4.get("rock", 0.0)) + float(got4.get("over", 0.0)))
			return ""
		"dig":
			var got3 := dig(front, 0.45, SHOVEL_M3 * 2.5)
			if got3.has("why"):
				return String(got3["why"])
			pile(_throw_spot(p, front), float(got3.get("over", 0.0)) + float(got3.get("pay", 0.0)))
			return ""
	return ""


# ------------------------------------------------------------------------------
#  Quartz veins: hard-rock gold (veins.gd, DESIGN_NOTES 139)
# ------------------------------------------------------------------------------
const Veins = preload("res://scripts/veins.gd")
const VEIN_HITS := 3              # pick swings to break a piece out
var ore_found: Callable           # func(at: Vector3, kg: float, grams: float) - a chunk of ore to carry
var _vein_spot := Vector3.INF
var _vein_hits := 0


## The vein at a point in the rock, or {}.
func vein_here(q: Vector3) -> Dictionary:
	if not terrain.inside(q.x, q.z) or layer_at3(q) != "rock":
		return {}
	Veins.make(int(Game.world_seed))
	var v := Veins.at(q, terrain.natural_at(q.x, q.z))
	if not v.is_empty():
		v["at"] = q
	return v


## A vein in a drift face (anywhere from knee to head height).
func _vein_face(face: Vector3) -> Dictionary:
	for dy in [0.0, -0.5, 0.5, -0.8]:
		var v := vein_here(face + Vector3(0, dy, 0))
		if not v.is_empty():
			return v
	return {}


## A vein in the floor of a pit or an outcrop in front of him.
func _vein_floor(front: Vector3) -> Dictionary:
	var g := Vector3(front.x, terrain.height_at(front.x, front.z) - 0.12, front.z)
	return vein_here(g)


func _vein_prompt(v: Dictionary, key: String) -> Array:
	var rich := float(v["g"])
	var look := "milky quartz, a few specks of gold in it" if rich > 22.0 else ("milky quartz, rusty here and there" if rich > 8.0 else "plain white quartz")
	if inv == null or not inv.holding("pick"):
		return ["", "A quartz vein: %s. Too hard for a shovel - it wants a pick." % look]
	return ["vein", "%s  Break quartz out of the vein with the pick (%s)" % [key, look]]


func _vein_act(p: Vector3, front: Vector3) -> String:
	if inv == null or not inv.holding("pick"):
		return "Too hard for a shovel: quartz wants a pick."
	var vg = _vox()
	var under: bool = p.y < terrain.height_at(p.x, p.z) - 1.2
	var v: Dictionary = _vein_face(_face_point(p, front)) if under or vg != null and vg.sdf_at(_face_point(p, front) + Vector3(0, -0.4, 0)) < 0.0 else {}
	var in_face := not v.is_empty()
	if v.is_empty():
		v = _vein_floor(front)
	if v.is_empty():
		return ""
	var at: Vector3 = v["at"]
	if _vein_spot == Vector3.INF or _vein_spot.distance_to(at) > 1.0:
		_vein_spot = at
		_vein_hits = 0
	_vein_hits += 1
	if _vein_hits < VEIN_HITS:
		return "Chink. The quartz is hard going (%d more)." % (VEIN_HITS - _vein_hits)
	_vein_hits = 0
	# a piece breaks out of the vein
	if in_face and vg != null:
		vg.carve(at, 0.42)
	else:
		var got := dig(front, 0.42, SHOVEL_M3 * 1.5, 0.6)
		if got.has("why"):
			return String(got["why"])
	var grade := float(v["g"])
	var kg := randf_range(16.0, 32.0)
	var grams := kg / 1000.0 * grade
	var msg := "A chunk of quartz breaks out (%d kg). Carry it to the wash plant's hopper to crush it for the gold." % int(kg)
	# rich shoots: now and then a bit of free gold you can pick right out
	if grade > 20.0 and randf() < 0.18 + grade / 300.0:
		var nug := randf_range(0.2, 1.2) * grade / 30.0
		gold_g += nug
		_dirty = true
		msg = "Gold! You pick %.1f g of free gold out of the quartz (%.1f g carried). %s" % [nug, gold_g, msg]
	if ore_found.is_valid():
		var drop := p.lerp(at, 0.5)
		drop.y = p.y + 0.1
		ore_found.call(drop, kg, grams)
	return msg


# ------------------------------------------------------------------------------
#  Ladders down shafts and drops
# ------------------------------------------------------------------------------
var ladders: Array = []          # [Vector3 top (at the lip), float bottom y, Vector3 out (away from the drop)]
var _ladder_nodes: Array = []


func _floor_y(q: Vector3) -> float:
	var vg = _vox()
	if vg != null and terrain.inside(q.x, q.z) and vg.ready_at(q):
		var f: float = vg.floor_below(q + Vector3(0, -0.6, 0), 200.0)
		if f != -INF:
			return f
	return terrain.height_at(q.x, q.z)


## The lip in front of him with a drop of 2 m+ below: {top, bottom}.
func _ladder_spot(p: Vector3, front: Vector3) -> Dictionary:
	var f := Vector3(front.x - p.x, 0, front.z - p.z).normalized()
	for d in [0.6, 0.9, 1.2]:
		var q := p + f * float(d)
		var below := _floor_y(Vector3(q.x, p.y + 0.3, q.z))
		if p.y - below >= 2.0:
			return {"top": Vector3(q.x, p.y, q.z), "bottom": below, "out": -f}
	return {}


## The ladder he's on or at: index, or -1.
func ladder_at(pos: Vector3) -> int:
	for i in range(ladders.size()):
		var top: Vector3 = ladders[i][0]
		if Vector2(top.x - pos.x, top.z - pos.z).length() < 0.75 and pos.y > float(ladders[i][1]) - 1.7 and pos.y < top.y + 0.6:
			return i
	return -1


func take_ladder(p: Vector3) -> String:
	var i := ladder_at(p)
	if i < 0 or inv == null:
		return ""
	var top: Vector3 = ladders[i][0]
	if p.y < top.y - 0.8:
		return "Climb out first."
	if inv.add("ladder", 1, true) <= 0:
		return "Too much on you."
	ladders.remove_at(i)
	(_ladder_nodes[i] as Node).queue_free()
	_ladder_nodes.remove_at(i)
	_dirty = true
	return "Ladder pulled up."


func _spawn_ladder(top: Vector3, bottom: float) -> void:
	var k := MeshKit.new()
	var len := top.y - bottom
	var rope := Color(0.6, 0.5, 0.3)
	for lx in [-0.2, 0.2]:
		k.box_at(Vector3(lx, -len * 0.5 + 0.3, 0), Vector3(0.03, len + 0.6, 0.03), rope)
	var n := int(len / 0.3)
	for r in range(n):
		k.box_at(Vector3(0, -float(r) * 0.3, 0), Vector3(0.44, 0.04, 0.05), Color(0.5, 0.38, 0.22))
	k.box_at(Vector3(0, 0.3, 0.2), Vector3(0.6, 0.06, 0.4), Color(0.3, 0.3, 0.3))     # stake and anchor at the lip
	var mi := k.instance("Ladder")
	add_child(mi)
	mi.global_position = top
	_ladder_nodes.append(mi)


## Where a shovelful goes: thrown off to his right, clear of the hole.
var _throw_side := 1.0
func _throw_spot(p: Vector3, front: Vector3) -> Vector3:
	var f := Vector3(front.x - p.x, 0, front.z - p.z).normalized()
	var right := Vector3(-f.z, 0, f.x)
	_throw_side = -_throw_side
	# up and over the lip: farther the deeper the hole is
	var deep: float = maxf(terrain.natural_at(front.x, front.z) - terrain.height_at(front.x, front.z), 0.0)
	return p + right * _throw_side * (3.0 + minf(deep, 3.0) * 1.2) - f * 0.6


## Set a sluice box down at the water's edge in front of you.
func place_sluice(p: Vector3, yaw: float) -> String:
	if owned_sluices <= sluices.size():
		return "You haven't got a sluice box. Buy one at the assay office in a town."
	if not near_water(p, 3.0):
		return "A sluice box goes at the water's edge: it needs the creek running through it."
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, terrain.height_at(p.x, p.z), p.z))
	sluices.append(xf)
	_spawn_sluice(xf)
	_dirty = true
	return "Sluice box set up. Shovel gravel into it."


func _spawn_sluice(xf: Transform3D) -> void:
	# A highbanker on a little utility trailer (DESIGN_NOTES 79, 83).
	var t = _make_towable("sluice", sluices.size() - 1, xf)
	EquipModels.sluice_trailer(t)


## Wrap a piece of gear as something a hitch can pull.
func _make_towable(kind: String, i: int, xf: Transform3D) -> Node3D:
	var t = TowableScript.new()
	t.kind = kind
	t.idx = i
	t.name = "%s%d" % [kind.capitalize(), i]
	t.ground = func(x: float, z: float) -> float: return terrain.height_at(x, z)
	add_child(t)
	t.global_transform = xf
	t.on_moved = func(n: Node3D) -> void:
		if n.kind == "sluice" and n.idx < sluices.size():
			sluices[n.idx] = n.global_transform
		elif n.kind == "washplant" and n.idx < plants.size():
			plants[n.idx] = n.global_transform
		_dirty = true
	towables.append(t)
	return t


# ------------------------------------------------------------------------------
#  Big gear: wash plant and excavator, bought and set up where you choose
# ------------------------------------------------------------------------------
func place_washplant(p: Vector3, yaw: float) -> String:
	if not Game.sandbox and jobs.money < WASHPLANT_PRICE:
		return "A wash plant costs $%d." % WASHPLANT_PRICE
	if cannot_dig(p) != "" or terrain.normal_at(p.x, p.z).y < 0.9:
		return "Needs flat, dry ground (not the runway)."
	if not Game.sandbox:
		jobs.money -= WASHPLANT_PRICE
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, terrain.height_at(p.x, p.z), p.z))
	plants.append(xf)
	_spawn_plant(xf)
	plant_fuel[plants.size() - 1] = PLANT_FUEL_START
	_dirty = true
	jobs.save_career()
	return "Trommel plant set up, %.0f L of gas in its drum. Start the engine (%s at the engine), then dump pay gravel in the hopper." % [PLANT_FUEL_START, Game.hint("interact")]


## A small excavator, delivered to where you stand.
func buy_excavator(p: Vector3, yaw: float) -> String:
	if not Game.sandbox and jobs.money < EXCAVATOR_PRICE:
		return "A small excavator costs $%d." % EXCAVATOR_PRICE
	if not Game.sandbox:
		jobs.money -= EXCAVATOR_PRICE
	owned_excavators += 1
	_spawn_excavator(Transform3D(Basis(Vector3.UP, yaw), p))
	_dirty = true
	jobs.save_career()
	return "Your excavator is here. Get in and dig."


## The drift miner, delivered to where you stand (DESIGN_NOTES 148).
func buy_tunneler(p: Vector3, yaw: float) -> String:
	if not Game.sandbox and jobs.money < TUNNELER_PRICE:
		return "A drift miner costs $%d." % TUNNELER_PRICE
	if not Game.sandbox:
		jobs.money -= TUNNELER_PRICE
	_spawn_tunneler(Transform3D(Basis(Vector3.UP, yaw), p))
	_dirty = true
	jobs.save_career()
	return "Your drift miner is here. Climb on, start the cutter (%s) and drive into a bank." % Game.hint("interact")


func _spawn_tunneler(xf: Transform3D, tub: Dictionary = {}, grade: float = 0.0) -> Node3D:
	var tn: Node3D = load("res://scripts/tunneler.gd").new()
	tn.name = "Tunneler%d" % tunnelers.size()
	tn.terrain = terrain
	tn.vox = _vox()
	tn.prospect = self
	add_child(tn)
	tn.build()
	xf.origin.y = terrain.height_at(xf.origin.x, xf.origin.z)
	tn.park(xf)
	tn.tub = tub
	tn.grade = grade
	tunnelers.append(tn)
	var mn := get_parent()
	if mn != null and mn.has_method("machine_sound"):
		mn.machine_sound(tn, "machine", Vector3(0.6, 1.3, 1.2), 1.4)
	return tn


## A bulldozer, delivered to where you stand: roads, pads and ramps anywhere.
func buy_dozer(p: Vector3, yaw: float) -> String:
	if not Game.sandbox and jobs.money < DOZER_PRICE:
		return "A bulldozer costs $%d." % DOZER_PRICE
	if not Game.sandbox:
		jobs.money -= DOZER_PRICE
	owned_dozers += 1
	_spawn_dozer(Transform3D(Basis(Vector3.UP, yaw), p))
	_dirty = true
	jobs.save_career()
	return "Your dozer is here. Get in, drop the blade, and push."


func _spawn_dozer(xf: Transform3D) -> Node3D:
	var dz := DozerScript.new()
	dz.name = "Dozer%d" % dozers.size()
	dz.terrain = terrain
	add_child(dz)
	dz.build()
	dz.park(xf)
	dz.on_grade = func(pt: Vector3, radius: float, target: float, fill_m3: float, cut_m3: float, max_step: float = 0.30, holes_only: bool = false) -> Dictionary:
		return grade_level(pt, radius, target, fill_m3, cut_m3, max_step, holes_only)
	dz.on_spill = func(pt: Vector3, m3: float) -> void:
		pile(pt, m3)
	dz.on_tree = func(tr: Dictionary, push: Vector3) -> void:
		if tree_cb.is_valid():
			tree_cb.call(tr, push)
	dozers.append(dz)
	var mn := get_parent()
	if mn != null and mn.has_method("machine_sound"):
		mn.machine_sound(dz, "machine", Vector3(0, 1.8, -1.2), 2.4)
	return dz


func _spawn_excavator(xf: Transform3D) -> Node3D:
	var ex := ExcavatorScript.new()
	ex.name = "Excavator%d" % excavators.size()
	ex.terrain = terrain
	add_child(ex)
	ex.build()
	ex.park(xf)
	ex.on_message = func(t: String) -> void: _say(t)
	ex.on_dig = func(pt: Vector3, m3: float) -> Dictionary:
		var got := dig(pt, 0.75 * ExcavatorScript.SCALE, m3, 0.15)
		if got.has("why"):
			_say(String(got["why"]))
			return {}
		return scoop_rocks(got, pt, 0.75 * ExcavatorScript.SCALE + 0.6)
	ex.on_dump = func(pt: Vector3, l: Dictionary) -> String: return _dump(pt, l)
	ex.hopper_at = func(pt: Vector3) -> Vector3: return hopper_near(pt)
	ex.on_cut = func(pt: Vector3, floor_y: float, m3: float) -> Dictionary:
		if cannot_dig(pt) != "" or not terrain.inside(pt.x, pt.z):
			return {}
		var got: Dictionary = terrain.cut_to(pt, 0.45 * ExcavatorScript.SCALE, floor_y, m3, 0.15)
		_clear_plants(pt, 0.6 * ExcavatorScript.SCALE)
		_maybe_find(got, pt)
		_dirty = true
		return got
	excavators.append(ex)
	var mn2 := get_parent()
	if mn2 != null and mn2.has_method("machine_sound"):
		mn2.machine_sound(ex, "machine", Vector3(0, 2.0, 1.4), 2.0)
	return ex


func hopper_near(p: Vector3) -> Vector3:
	for i in range(plants.size()):
		var hop: Vector3 = (plants[i] as Transform3D) * EquipModels.TROMMEL_HOPPER
		if Vector2(p.x - hop.x, p.z - hop.z).length() < 2.2 and _set_up("washplant", i):
			return hop
	return Vector3.INF


## Is that piece of gear unhitched and unfolded, ready to work?
func _set_up(kind: String, i: int) -> bool:
	for t in towables:
		if t.kind == kind and t.idx == i:
			return t.working()
	return true


## A chunk of vein quartz tipped into the hopper: the trommel crushes and
## washes it with the gravel (quartz 2.65 t a cubic metre).
func ore_into_hopper(p: Vector3, kg: float, grams: float) -> String:
	var hop := hopper_near(p)
	if hop == Vector3.INF:
		return ""
	var said := _dump(hop, {"rock": kg / (Veins.QUARTZ_T_M3 * 1000.0), "g": grams})
	return said if said != "" else "Into the hopper."


## A machine bucket digging where rocks lie takes them too (DESIGN_NOTES 140):
## they ride in the load and come out wherever it's dumped.
var rocks_take: Callable         # func(at: Vector3, r: float) -> Array of rock pieces (taken out of the world)
var rocks_put: Callable          # func(at: Vector3, pieces: Array) - back out on the ground or into a bed
func scoop_rocks(got: Dictionary, pt: Vector3, r: float) -> Dictionary:
	if not rocks_take.is_valid():
		return got
	var rk: Array = rocks_take.call(pt, r)
	if rk.is_empty():
		return got
	got["rocks"] = rk
	got["over"] = maxf(float(got.get("over", 0.0)), 0.02)     # a bucket of rocks is a load
	got.erase("bedrock")
	return got


func _dump(p: Vector3, l: Dictionary) -> String:
	var vol := float(l.get("over", 0.0)) + float(l.get("pay", 0.0)) + float(l.get("rock", 0.0))
	var rk: Array = l.get("rocks", [])
	var pli := plant_at(p)
	if not rk.is_empty():
		if pli >= 0:
			# into the hopper: the trommel takes them (quartz gets crushed for its gold)
			for pc in rk:
				vol += float(pc["kg"]) / 2650.0
				l["g"] = float(l.get("g", 0.0)) + float(pc.get("g", 0.0))
		elif rocks_put.is_valid():
			rocks_put.call(p, rk)
	if pli >= 0:
		var hop: Array = plant_hopper[pli]
		if float(hop[0]) + vol > HOPPER_MAX:
			pile(p + (plants[pli] as Transform3D).basis.x * 2.5, vol)
			return "The hopper's full (%.1f m3): it spilled over the side. Let the trommel wash it down." % float(hop[0])
		hop[0] = float(hop[0]) + vol
		hop[1] = float(hop[1]) + float(l.get("g", 0.0)) * 0.92
		if pli < _plant_fx.size():
			(_plant_fx[pli]["dump"] as CPUParticles3D).restart()
		_dirty = true
		if bool(plant_on[pli]):
			return "Into the hopper: %.1f m3 to wash." % float(hop[0])
		return "Into the hopper (%.1f m3). The trommel's stopped: start its engine (%s at the engine) to wash it." % [float(hop[0]), Game.hint("interact")]
	pile(p, vol)
	return ""


func _spawn_plant(xf: Transform3D) -> void:
	# A skid-mounted trommel plant, from Dave's photo (DESIGN_NOTES 85). It
	# isn't towed: a loader on forks lifts it onto a trailer (to come).
	var n := Node3D.new()
	n.name = "WashPlant%d" % (plants.size() - 1)
	add_child(n)
	n.global_transform = xf
	EquipModels.skid_trommel(n)
	_nodes.append(n)
	var dn := n.get_node_or_null("Drum")
	_drums.append(dn)
	var sm := CPUParticles3D.new()
	sm.name = "Exhaust"
	sm.position = EquipModels.TROMMEL_EXHAUST
	sm.amount = 24
	sm.lifetime = 2.2
	sm.emitting = false
	sm.direction = Vector3.UP
	sm.spread = 12.0
	sm.initial_velocity_min = 0.8
	sm.initial_velocity_max = 1.4
	sm.gravity = Vector3(0.25, 0.15, 0)
	sm.scale_amount_min = 0.25
	sm.scale_amount_max = 0.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	sm.scale_amount_curve = curve
	var smm := SphereMesh.new()
	smm.radius = 0.25
	smm.height = 0.5
	smm.radial_segments = 6
	smm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.25, 0.25, 0.25, 0.35)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smm.material = smat
	sm.mesh = smm
	sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(sm)
	_plant_smoke.append(sm)
	_plant_fx.append(EquipModels.trommel_fx(n))
	plant_fuel.append(0.0)
	plant_on.append(false)
	plant_hopper.append([0.0, 0.0])
	_plant_report.append(0.0)


# ------------------------------------------------------------------------------
#  Selling and buying (the assay office in the hangar towns)
# ------------------------------------------------------------------------------
func sell_gold() -> String:
	var sold: Array = []
	var pay := 0
	if gold_g >= 0.01:
		pay += int(round(gold_g * float(PRICE_PER_G)))
		sold.append("%.1f g of gold" % gold_g)
		gold_g = 0.0
	if inv != null and inv.count("gold_bar") > 0:
		var nb: int = inv.count("gold_bar")
		inv.remove("gold_bar", nb)
		pay += int(round(nb * 100.0 * float(PRICE_PER_G) * 1.08))
		sold.append("%d gold bar%s" % [nb, "" if nb == 1 else "s"])
	if inv != null:
		for id in FINDS.keys():
			var n: int = inv.count(id)
			if n > 0:
				inv.remove(id, n)
				pay += n * int(FINDS[id][1])
				sold.append(("%d x %s" % [n, FINDS[id][0]]) if n > 1 else ("a " + String(FINDS[id][0]).to_lower()))
	if sold.is_empty():
		return "You've nothing to sell."
	jobs.money += pay
	_dirty = true
	jobs.save_career()
	return "Sold %s for $%d." % [", ".join(sold), pay]


func buy_sluice() -> String:
	if not Game.sandbox and jobs.money < SLUICE_PRICE:
		return "A sluice box costs $%d." % SLUICE_PRICE
	if not Game.sandbox:
		jobs.money -= SLUICE_PRICE
	owned_sluices += 1
	_dirty = true
	jobs.save_career()
	return "A sluice box is in the plane. Set it up at a creek from the build menu."


## Which plant's hopper is at p (within reach), or -1.
func plant_at(p: Vector3) -> int:
	for i in range(plants.size()):
		var hop: Vector3 = (plants[i] as Transform3D) * EquipModels.TROMMEL_HOPPER
		if Vector2(p.x - hop.x, p.z - hop.z).length() < 2.2 and _set_up("washplant", i):
			return i
	return -1


## A plant whose engine (or fuel drum) he's standing at, or -1.
func plant_engine_near(p: Vector3, r: float = 2.2) -> int:
	for i in range(plants.size()):
		var xf: Transform3D = plants[i]
		if p.distance_to(xf * EquipModels.TROMMEL_ENGINE) < r or p.distance_to(xf * EquipModels.TROMMEL_FUEL) < r:
			return i
	return -1


func plant_engine_text(i: int) -> String:
	var hop: Array = plant_hopper[i]
	var state := "running" if bool(plant_on[i]) else "stopped"
	return "Trommel %s: %.0f L of gas, %.1f m3 in the hopper" % [state, float(plant_fuel[i]), float(hop[0])]


func plant_toggle(i: int) -> String:
	if bool(plant_on[i]):
		plant_on[i] = false
		_dirty = true
		return "Trommel stopped."
	if float(plant_fuel[i]) <= 0.05:
		return "It won't start: the fuel drum's dry. Pour a gas can in."
	plant_on[i] = true
	_dirty = true
	return "Trommel running: the drum's turning and the spray's on. %.0f L of gas." % float(plant_fuel[i])


## Pour fuel into a plant's drum. Returns the litres it took.
func plant_add_fuel(i: int, litres: float) -> float:
	var took := minf(litres, PLANT_FUEL_MAX - float(plant_fuel[i]))
	plant_fuel[i] = float(plant_fuel[i]) + took
	_dirty = true
	return took


## Every this many m3 washed, a rock big enough to carry comes off the
## oversize chute; it lands past the end of the chute (plant-local).
const OVERSIZE_EVERY := 0.45
const OVERSIZE_END := Vector3(-1.15, 0.0, -5.0)
var _oversize := {}
var rock_pile_full: Callable     # func(at: Vector3) -> bool: rocks heaped up there already
var oversize_out: Callable       # func(at: Vector3, kg: float) -> "bed" / "full" / "ground"
var _oversize_told := {}


## Running plants burn gas, turn their drums and wash what's in the hopper.
func _run_plants(delta: float) -> void:
	for i in range(plants.size()):
		var on: bool = bool(plant_on[i])
		if on:
			plant_fuel[i] = maxf(float(plant_fuel[i]) - PLANT_BURN * delta, 0.0)
			if float(plant_fuel[i]) <= 0.0:
				plant_on[i] = false
				on = false
				_say("The trommel's run out of gas and stopped.")
			var dn = _drums[i]
			if dn != null and is_instance_valid(dn):
				(dn as Node3D).rotate_object_local(Vector3.UP, 1.6 * delta)     # ~15 rpm
			var hop: Array = plant_hopper[i]
			if float(hop[0]) > 0.0:
				var through := minf(PLANT_RATE * delta, float(hop[0]))
				var g := float(hop[1]) * through / float(hop[0])
				hop[0] = float(hop[0]) - through
				hop[1] = float(hop[1]) - g
				gold_g += g
				_plant_report[i] = float(_plant_report[i]) + g
				_dirty = true
				# the oversize: real rocks off the end of the chute, onto a pile
				# you can carry away (DESIGN_NOTES 140)
				_oversize[i] = float(_oversize.get(i, 0.0)) + through
				if float(_oversize[i]) >= OVERSIZE_EVERY and rock_found.is_valid():
					_oversize[i] = 0.0
					var pxf: Transform3D = plants[i]
					var drop := pxf * (OVERSIZE_END + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.4)))
					drop.y = terrain.height_at(drop.x, drop.z)
					var okg := randf_range(15.0, 55.0)
					if oversize_out.is_valid():
						var went := String(oversize_out.call(drop, okg))
						if went == "full" and not bool(_oversize_told.get(i, false)):
							_oversize_told[i] = true
							_say("The bed under the trommel's chute is full: the rocks are piling up on the ground.")
						elif went == "bed":
							_oversize_told[i] = false
					elif not rock_pile_full.is_valid() or not bool(rock_pile_full.call(drop)):
						rock_found.call(drop, okg)
				if float(hop[0]) <= 0.0001:
					hop[0] = 0.0
					hop[1] = 0.0
					var got := float(_plant_report[i])
					_plant_report[i] = 0.0
					if got < 0.05:
						_say("Hopper washed: no gold in that lot. Dig deeper, to the gravel on bedrock.")
					else:
						_say("Hopper washed: %.1f g in the riffles (%.0f g carried)%s" % [got, gold_g, "  Rich gravel!" if got > 6.0 else ""])
		if i < _plant_fx.size():
			var fxd: Dictionary = _plant_fx[i]
			var washing := on and float(plant_hopper[i][0]) > 0.0
			(fxd["spray"] as CPUParticles3D).emitting = on
			(fxd["tail"] as CPUParticles3D).emitting = on
			(fxd["tail2"] as CPUParticles3D).emitting = on
			(fxd["gravel"] as CPUParticles3D).emitting = washing
			(fxd["oversize"] as CPUParticles3D).emitting = washing
			for sh in fxd["sheets"]:
				var shm: ShaderMaterial = sh
				(shm.get_meta("node") as Node3D).visible = on
				var mud: float = float(shm.get_shader_parameter("mud"))
				shm.set_shader_parameter("mud", move_toward(mud, 1.0 if washing else 0.0, delta * 0.4))
		var sm = _plant_smoke[i]
		if sm != null and is_instance_valid(sm) and (sm as CPUParticles3D).emitting != on:
			(sm as CPUParticles3D).emitting = on


func _say(t: String) -> void:
	if hud != null:
		hud.push_message(t, 3.5)


# ------------------------------------------------------------------------------
#  Saving
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_run_plants(delta)
	_roof_t += delta
	if _roof_t > 4.0:
		_ground_check(_roof_t)
		_roof_t = 0.0
	_save_t += delta
	if _dirty and _save_t > 8.0:
		_save_t = 0.0
		_dirty = false
		save()


## The smooth voxel ground, if this build has it.
func _vox() -> Node:
	if world == null:
		return null
	var vg = world.get("ground_view")
	return vg if vg != null and vg.has_method("carve") else null


func save() -> void:
	var cf := ConfigFile.new()
	var vg = _vox()
	cf.set_value("p", "vox_edits", vg.edits if vg != null else vox_edits)
	cf.set_value("p", "roofs", roofs)
	cf.set_value("p", "ladders", ladders)
	cf.set_value("p", "sets", sets)
	cf.set_value("p", "gold_g", gold_g)
	cf.set_value("p", "sluices", sluices)
	cf.set_value("p", "owned_sluices", owned_sluices)
	cf.set_value("p", "plants", plants)
	cf.set_value("p", "plant_fuel", plant_fuel)
	cf.set_value("p", "plant_on", plant_on)
	cf.set_value("p", "plant_hopper", plant_hopper)
	cf.set_value("p", "owned_excavators", owned_excavators)
	var ex_xf: Array = []
	for ex in excavators:
		ex_xf.append((ex as Node3D).global_transform)
	cf.set_value("p", "excavators", ex_xf)
	var tn_s: Array = []
	for tn in tunnelers:
		tn_s.append(tn.save_state())
	cf.set_value("p", "tunnelers", tn_s)
	cf.set_value("p", "owned_dozers", owned_dozers)
	var dz_xf: Array = []
	for dzn in dozers:
		dz_xf.append((dzn as Node3D).global_transform)
	cf.set_value("p", "dozers", dz_xf)
	terrain.save_to(cf)
	cf.save(SAVE)


func load_all() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	vox_edits = cf.get_value("p", "vox_edits", [])
	roofs = cf.get_value("p", "roofs", [])
	ladders = cf.get_value("p", "ladders", [])
	for ld in ladders:
		_spawn_ladder(ld[0], float(ld[1]))
	sets = cf.get_value("p", "sets", [])
	for st in sets:
		_spawn_set(st[0], float(st[1]))
	gold_g = float(cf.get_value("p", "gold_g", 0.0))
	owned_sluices = int(cf.get_value("p", "owned_sluices", 0))
	owned_excavators = int(cf.get_value("p", "owned_excavators", 0))
	for xf in cf.get_value("p", "sluices", []):
		sluices.append(xf)
		_spawn_sluice(xf)
	for xf0 in cf.get_value("p", "plants", []):
		var xf: Transform3D = xf0
		xf.origin.y = terrain.height_at(xf.origin.x, xf.origin.z)    # sits on the ground (moved by a new layout)
		plants.append(xf)
		_spawn_plant(xf)
	var pf: Array = cf.get_value("p", "plant_fuel", [])
	var po: Array = cf.get_value("p", "plant_on", [])
	var ph: Array = cf.get_value("p", "plant_hopper", [])
	for i in range(plants.size()):
		plant_fuel[i] = float(pf[i]) if i < pf.size() else PLANT_FUEL_START
		plant_on[i] = bool(po[i]) if i < po.size() else false
		plant_hopper[i] = (ph[i] as Array).duplicate() if i < ph.size() else [0.0, 0.0]
	for xf in cf.get_value("p", "excavators", []):
		_spawn_excavator(xf)
	for ts in cf.get_value("p", "tunnelers", []):
		var td: Dictionary = ts
		_spawn_tunneler(td["xf"], td.get("tub", {}), float(td.get("grade", 0.0)))
	owned_dozers = int(cf.get_value("p", "owned_dozers", 0))
	for xf in cf.get_value("p", "dozers", []):
		_spawn_dozer(xf)
	terrain.load_from(cf)
