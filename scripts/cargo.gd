extends Node3D
## Cargo you can see and handle: every piece of a job (a crate, a box of
## groceries, a mail sack, a fuel drum, a medical case) is a real object. Taken
## "by hand", the pieces are set out on the ramp beside the plane; the pilot
## picks each one up, carries it (heavy ones slow him down) and loads it
## through the cabin door or the baggage door, which decides where the weight
## sits. Loaded pieces ride visibly inside the plane. At the destination he
## takes them out and puts them down by the strip; when the last piece of a
## job is down, it is delivered and paid.

const MeshKit = preload("res://scripts/meshkit.gd")
const PilotModel = preload("res://scripts/pilot_model.gd")

var jobs: Node
var plane: Node3D
var terrain: RefCounted
var walker: Node3D
var on_foot := false
var prompt := ""                      # shown by the HUD while on foot
var extra_prompt := ""                # main.gd's own hint (chainsaw, ride along) when nothing else applies
var holding: Array = []               # [job, piece] in the pilot's arms

var _nodes := {}                      # piece key -> MeshInstance3D
var _meshes := {}                     # kind -> ArrayMesh
var _mat: ShaderMaterial
var _target: Array = []               # what interact would act on: [action, job, piece, where]

## kind -> [size (x, y, z) in metres, shape]
const LOOKS := {
	"groceries": [Vector3(0.46, 0.32, 0.36), "box"],
	"freight": [Vector3(0.62, 0.46, 0.48), "crate"],
	"parts": [Vector3(0.56, 0.5, 0.5), "crate_dark"],
	"mail": [Vector3(0.56, 0.3, 0.36), "sack"],
	"fuel": [Vector3(0.58, 0.88, 0.58), "drum"],
	"medical": [Vector3(0.5, 0.22, 0.36), "case"],
	"ore": [Vector3(0.42, 0.26, 0.3), "sack"],
	"logs": [Vector3(0.9, 0.3, 0.3), "log"],
	"sawlog": [Vector3(2.4, 0.34, 0.34), "log"],
	"rock": [Vector3(0.46, 0.34, 0.40), "rock"],
	"quartz": [Vector3(0.40, 0.30, 0.36), "quartz"],
	"pallet": [Vector3(1.1, 1.05, 1.2), "pallet"],
	"explosives": [Vector3(0.52, 0.30, 0.34), "dynamite"],
	"samples": [Vector3(1.0, 0.16, 0.34), "core_box"],
}
## Set by main.gd: the forklift carrying a piece, if any (for drawing it on the forks).
var forklifts: Array = []
## Set by main.gd: pickups whose beds take pieces (pickup_truck.gd).
var trucks: Array = []
const HAND_MAX_KG := 120.0           # heavier than this needs the forklift

## Your own logs (DESIGN_NOTES 124): bucked off a downed tree they lie where
## they fell; carry them (one at a time, they're heavy) to the pickup bed or
## the log trailer, and drop them at the log deck in the tool yard, where they
## go into your stock for building and crafting. Not a job: kept apart from
## jobs.carried (and out of the plane), saved in user://logs.cfg.
const LOG_KG := 55.0
const LOG_SAVE := "user://logs.cfg"
var own_logs := {"id": 990001, "kind": "sawlog", "title": "Your logs", "from": -99, "to": -99, "pieces": [],
	"pax": 0, "fragile": false, "urgent": false, "condition": 1.0}
## The log deck (tool yard), and what main does with a log landed on it.
var deck_at := Vector3.INF
const DECK_R := 7.0
var on_deck: Callable                 # func(n: int)


## Rocks dug out of the ground (DESIGN_NOTES 133): too big for the shovel,
## lifted out by hand and carried off - piled up out of the way, or into a
## bed. Kept like the logs, out of the job book.
var own_rocks := {"id": 990002, "kind": "rock", "title": "Rocks", "from": -99, "to": -99, "pieces": [],
	"pax": 0, "fragile": false, "urgent": false, "condition": 1.0}


func _all_jobs() -> Array:
	var out: Array = jobs.carried
	if not (own_logs["pieces"] as Array).is_empty() or not (own_rocks["pieces"] as Array).is_empty():
		out = jobs.carried + [own_logs, own_rocks]
	return out


func _own(job: Dictionary) -> bool:
	return job == own_logs or job == own_rocks


## A rock turned up by the shovel: it lies at `q` (kg sets its size).
func add_rock(q: Vector3, kg: float) -> void:
	(own_rocks["pieces"] as Array).append({"kg": kg, "at": "dropped", "strip": -1, "pos": q, "yaw": randf() * TAU})
	save_logs()


## A chunk of gold-bearing quartz broken out of a vein (DESIGN_NOTES 139):
## carried like a rock, and tipped into a wash plant's hopper for its gold.
var hopper_at: Callable        # func(p: Vector3) -> Vector3 (INF if no hopper in reach)
var into_hopper: Callable      # func(p: Vector3, kg: float, grams: float) -> String
func add_ore(q: Vector3, kg: float, grams: float) -> void:
	(own_rocks["pieces"] as Array).append({"kg": kg, "at": "dropped", "strip": -1, "pos": q, "yaw": randf() * TAU, "q": true, "g": grams})
	save_logs()


## Rocks (and quartz) lying within r of q, scooped up by a machine's bucket:
## taken out of the world and handed back to go in the load.
func take_rocks_near(q: Vector3, r: float) -> Array:
	var out: Array = []
	for pc in (own_rocks["pieces"] as Array).duplicate():
		if pc["at"] == "dropped" and Vector2((pc["pos"] as Vector3).x - q.x, (pc["pos"] as Vector3).z - q.z).length() < r:
			(own_rocks["pieces"] as Array).erase(pc)
			out.append(pc)
	if not out.is_empty():
		save_logs()
	return out


## Rocks out of a bucket: into a bed under it if there's room, else on the ground round q.
func put_rocks(q: Vector3, pieces: Array) -> void:
	for pc in pieces:
		var at := q + Vector3(randf_range(-0.7, 0.7), 0, randf_range(-0.7, 0.7))
		at.y = terrain.height_at(at.x, at.z) if terrain != null else q.y
		var placed := false
		for tr in trucks:
			if tr == null or not is_instance_valid(tr) or bool(tr.get("driven")) or not _over_bed(tr, at):
				continue
			var fs := truck_free_spot(tr, "rock")
			if fs >= 0 and truck_load_kg(tr) + float(pc["kg"]) <= float(tr.BED_MAX_KG):
				pc["at"] = "truck"
				pc["spot"] = fs
				pc["veh"] = trucks.find(tr)
				placed = true
			break
		if not placed:
			pc["at"] = "dropped"
			pc["pos"] = at
		(own_rocks["pieces"] as Array).append(pc)
	save_logs()


## Is q over the bed (within reach of one of its loading spots)?
func _over_bed(tr: Node3D, q: Vector3) -> bool:
	for si in range((tr.BED_SPOTS as Array).size()):
		var c: Vector3 = (tr.bed_xf(si) as Transform3D).origin
		if Vector2(c.x - q.x, c.z - q.z).length() < 1.3:
			return true
	return false


## A rock off the trommel's oversize chute (DESIGN_NOTES 140): into a bed
## backed up under the chute if there's one with room, else onto the ground.
func oversize_rock(q: Vector3, kg: float) -> String:
	for tr in trucks:
		if tr == null or not is_instance_valid(tr) or bool(tr.get("driven")) or not _over_bed(tr, q):
			continue
		var fs := truck_free_spot(tr, "rock")
		if fs >= 0 and truck_load_kg(tr) + kg <= float(tr.BED_MAX_KG):
			(own_rocks["pieces"] as Array).append({"kg": kg, "at": "truck", "strip": -1, "pos": q, "yaw": randf() * TAU,
				"spot": fs, "veh": trucks.find(tr)})
			save_logs()
			return "bed"
		return "full"
	add_rock(q, kg)
	return "ground"


## A rock lying within r of q (in the way of the shovel), or {}.
func rock_near(q: Vector3, r: float) -> Dictionary:
	for pc in own_rocks["pieces"]:
		if pc["at"] == "dropped" and not bool(pc.get("q", false)) and (pc["pos"] as Vector3).distance_to(q) < r:
			return pc
	return {}


func add_own_logs(points: Array) -> void:
	for q in points:
		(own_logs["pieces"] as Array).append({"kg": LOG_KG, "at": "dropped", "strip": -1, "pos": q})
	save_logs()


func _near_deck(p: Vector3) -> bool:
	return deck_at != Vector3.INF and Vector2(p.x - deck_at.x, p.z - deck_at.z).length() < DECK_R


## Logs off onto the deck: out of the world and into your stock.
func _to_deck(pcs: Array) -> void:
	for pc in pcs:
		(own_logs["pieces"] as Array).erase(pc)
	if on_deck.is_valid() and not pcs.is_empty():
		on_deck.call(pcs.size())
	save_logs()


func save_logs() -> void:
	var cf := ConfigFile.new()
	var out: Array = []
	for pc in own_logs["pieces"]:
		var at: String = pc["at"]
		var pos: Vector3 = pc["pos"]
		if at == "hands" and walker != null:
			at = "dropped"
			pos = walker.global_position
		out.append({"at": at, "pos": pos, "spot": int(pc.get("spot", 0)), "veh": int(pc.get("veh", 0))})
	cf.set_value("logs", "pieces", out)
	var rk: Array = []
	for pc2 in own_rocks["pieces"]:
		var at2: String = pc2["at"]
		var pos2: Vector3 = pc2["pos"]
		if at2 == "hands" and walker != null:
			at2 = "dropped"
			pos2 = walker.global_position
		rk.append({"at": at2, "pos": pos2, "kg": float(pc2["kg"]), "yaw": float(pc2.get("yaw", 0.0)), "spot": int(pc2.get("spot", 0)), "veh": int(pc2.get("veh", 0)),
			"q": bool(pc2.get("q", false)), "g": float(pc2.get("g", 0.0))})
	cf.set_value("rocks", "pieces", rk)
	cf.save(LOG_SAVE)


func load_logs() -> void:
	own_logs["pieces"] = []
	own_rocks["pieces"] = []
	var cf := ConfigFile.new()
	if cf.load(LOG_SAVE) != OK:
		return
	for d2 in cf.get_value("rocks", "pieces", []):
		var at3: String = d2.get("at", "dropped")
		if not at3 in ["dropped", "truck"]:
			at3 = "dropped"
		(own_rocks["pieces"] as Array).append({"kg": float(d2.get("kg", 40.0)), "at": at3, "strip": -1, "pos": d2.get("pos", Vector3.ZERO),
			"yaw": float(d2.get("yaw", 0.0)), "spot": int(d2.get("spot", 0)), "veh": int(d2.get("veh", 0)),
			"q": bool(d2.get("q", false)), "g": float(d2.get("g", 0.0))})
	for d in cf.get_value("logs", "pieces", []):
		var at: String = d.get("at", "dropped")
		if not at in ["dropped", "truck"]:
			at = "dropped"
		(own_logs["pieces"] as Array).append({"kg": LOG_KG, "at": at, "strip": -1, "pos": d.get("pos", Vector3.ZERO),
			"spot": int(d.get("spot", 0)), "veh": int(d.get("veh", 0))})


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = PilotModel._shader()


## Pieces on the ground are part of the world (DESIGN_NOTES 141): low ones
## (rocks, logs, boxes) you step up onto and wheels roll over; tall ones
## (drums, pallets) are solid. Only re-registered when a piece moves.
var _coll_xf := {}
func _coll_set(k: String, xf: Transform3D, size: Vector3) -> void:
	if terrain == null or not terrain.has_method("set_platform"):
		return
	if _coll_xf.get(k) == xf:
		return
	_coll_xf[k] = xf
	var sc := xf.basis.get_scale().x
	var sz := size * sc
	var flat := Transform3D(xf.basis.orthonormalized(), xf.origin)
	if sz.y > 0.6:
		terrain.clear_platform("cargo:" + k)
		terrain.set_solid("cargo:" + k, flat, sz)
	else:
		terrain.clear_solid("cargo:" + k)
		terrain.set_platform("cargo:" + k, flat, sz)


func _coll_clear(k: String) -> void:
	if not _coll_xf.has(k) or terrain == null:
		return
	_coll_xf.erase(k)
	terrain.clear_platform("cargo:" + k)
	terrain.clear_solid("cargo:" + k)


static func _key(job: Dictionary, i: int) -> String:
	return "%d:%d" % [int(job["id"]), i]


# ------------------------------------------------------------------------------
#  Models
# ------------------------------------------------------------------------------
func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var look: Array = LOOKS.get(kind, LOOKS["freight"])
	var sz: Vector3 = look[0]
	var shape: String = look[1]
	var kit := MeshKit.new()
	var h := sz * 0.5
	match shape:
		"rock":
			# A dug-out rock: a lumpy, faceted stone (each piece is scaled
			# and turned its own way when it's drawn)
			var rr := RandomNumberGenerator.new()
			rr.seed = 1897
			var rings: Array = []
			var ys := [0.0, 0.25, 0.6, 0.9, 1.0]
			var rs := [0.55, 0.95, 1.0, 0.7, 0.2]
			for yi in range(ys.size()):
				var ring := PackedVector3Array()
				for ai in range(7):
					var a := TAU * float(ai) / 7.0 + float(yi) * 0.4
					var rj: float = float(rs[yi]) * rr.randf_range(0.82, 1.12)
					ring.append(Vector3(cos(a) * h.x * rj, float(ys[yi]) * sz.y + rr.randf_range(-0.02, 0.02), sin(a) * h.z * rj))
				rings.append(ring)
			kit.loft(rings, Color(0.42, 0.40, 0.36), true, true)
		"quartz":
			# A chunk of vein quartz: blocky, milky white, a rusty face on one
			# side (the vein wall) and gold flecks and a little streak in it
			var rq := RandomNumberGenerator.new()
			rq.seed = 2203
			var rings_q: Array = []
			var ys_q := [0.0, 0.3, 0.75, 1.0]
			var rs_q := [0.7, 1.0, 0.85, 0.35]
			for yi in range(ys_q.size()):
				var ring_q := PackedVector3Array()
				for ai in range(5):
					var a := TAU * float(ai) / 5.0 + float(yi) * 0.5
					var rj: float = float(rs_q[yi]) * rq.randf_range(0.85, 1.1)
					ring_q.append(Vector3(cos(a) * h.x * rj, float(ys_q[yi]) * sz.y, sin(a) * h.z * rj))
				rings_q.append(ring_q)
			kit.loft(rings_q, Color(0.86, 0.85, 0.82), true, true)
			# the rusty wall side
			kit.box(Transform3D(Basis(Vector3.UP, 0.3), Vector3(-h.x * 0.78, sz.y * 0.45, 0)), Vector3(0.03, sz.y * 0.6, sz.z * 0.55), Color(0.56, 0.32, 0.14))
			# gold: specks and a short streak, standing just proud of the faces
			var gold := Color(1.0, 0.78, 0.22)
			for gi in range(9):
				var ga := rq.randf() * TAU
				var gy := rq.randf_range(0.25, 0.8) * sz.y
				kit.box_at(Vector3(cos(ga) * h.x * 0.9, gy, sin(ga) * h.z * 0.9), Vector3(0.025, 0.02, 0.025), gold)
			kit.box(Transform3D(Basis(Vector3.FORWARD, 0.5), Vector3(h.x * 0.2, sz.y * 0.98, h.z * 0.1)), Vector3(0.12, 0.012, 0.025), gold)
		"box":
			# Cardboard box with a darker tape stripe over the top.
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, h.y, 0)), sz, Color(0.62, 0.48, 0.32))
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, sz.y + 0.002, 0)), Vector3(0.08, 0.004, sz.z + 0.004), Color(0.48, 0.40, 0.30))
		"dynamite":
			# A pale wooden dynamite case with a red band and a red-orange
			# hazard diamond on the side (DESIGN_NOTES 173)
			var pine := Color(0.74, 0.62, 0.42)
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, h.y, 0)), sz, pine)
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, h.y, 0)), Vector3(sz.x + 0.006, 0.06, sz.z + 0.006), Color(0.72, 0.12, 0.08))
			kit.box(Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0, h.y, h.z + 0.004)), Vector3(0.11, 0.11, 0.006), Color(0.92, 0.40, 0.10))
		"core_box":
			# A long shallow wooden core tray with grey rock cores in it
			var wood2 := Color(0.56, 0.44, 0.30)
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, h.y, 0)), sz, wood2)
			for ci in range(3):
				kit.box(Transform3D(Basis.IDENTITY, Vector3(0, sz.y + 0.01, -h.z + 0.06 + float(ci) * 0.11)), Vector3(sz.x * 0.94, 0.05, 0.05), Color(0.48, 0.48, 0.46))
		"crate", "crate_dark":
			# Wooden crate: a box with proud slats around the edges and across.
			var wood := Color(0.58, 0.44, 0.28) if shape == "crate" else Color(0.38, 0.33, 0.27)
			var slat := wood.darkened(0.2)
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, h.y, 0)), sz * 0.98, wood)
			for sy in [0.04, sz.y - 0.04]:
				kit.box(Transform3D(Basis.IDENTITY, Vector3(0, sy, 0)), Vector3(sz.x + 0.02, 0.06, sz.z + 0.02), slat)
			for sx in [-1.0, 1.0]:
				for szz in [-1.0, 1.0]:
					kit.box(Transform3D(Basis.IDENTITY, Vector3(sx * (h.x - 0.02), h.y, szz * (h.z - 0.02))), Vector3(0.06, sz.y, 0.06), slat)
			kit.box(Transform3D(Basis(Vector3.BACK, 0.62), Vector3(0, h.y, h.z + 0.004)), Vector3(0.05, sz.length() * 0.7, 0.01), slat)
		"sack":
			# A canvas mail sack, tied at one end.
			var canvas := Color(0.58, 0.55, 0.44)
			var rings: Array = []
			for i in range(7):
				var t := float(i) / 6.0
				var r := sin(PI * clampf(t * 1.05, 0.0, 1.0)) * 0.5 + 0.08
				var ring := PackedVector3Array()
				for k in range(10):
					var a := TAU * float(k) / 10.0
					ring.append(Vector3((t - 0.5) * sz.x, h.y + sin(a) * h.y * r * 1.6, cos(a) * h.z * r * 1.7))
				rings.append(ring)
			kit.loft(rings, canvas, true, true)
			kit.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(h.x + 0.06, h.y, 0)), 0.03, 0.02, 0.08, 6, canvas.darkened(0.3), true)
		"log":
			# A short spruce bolt: bark round the outside, pale cut ends.
			var bark := Color(0.30, 0.22, 0.15)
			var cut := Color(0.80, 0.68, 0.48)
			var lx := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(h.x, h.y, 0))
			kit.cylinder(lx, h.y, h.y * 0.94, sz.x, 9, bark, false)
			kit.cylinder(lx * Transform3D(Basis.IDENTITY, Vector3(0, -0.005, 0)), h.y * 0.95, h.y * 0.95, 0.01, 9, cut, true)
			kit.cylinder(lx * Transform3D(Basis.IDENTITY, Vector3(0, sz.x - 0.005, 0)), h.y * 0.9, h.y * 0.9, 0.01, 9, cut, true)
		"pallet":
			# A wooden pallet with a load strapped on: crates under stretch wrap.
			var wood := Color(0.62, 0.50, 0.33)
			for bx in [-1.0, 0.0, 1.0]:
				kit.box(Transform3D(Basis.IDENTITY, Vector3(bx * (h.x - 0.05), 0.06, 0)), Vector3(0.1, 0.1, sz.z), wood.darkened(0.15))
			for bz in range(5):
				kit.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.125, -h.z + 0.06 + (sz.z - 0.12) * float(bz) / 4.0)), Vector3(sz.x, 0.025, 0.1), wood)
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)), Vector3(sz.x, 0.02, 0.1), wood.darkened(0.1))
			var load_h := sz.y - 0.15
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.14 + load_h * 0.5, 0)), Vector3(sz.x - 0.04, load_h, sz.z - 0.04), Color(0.55, 0.42, 0.28))
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.14 + load_h * 0.5, 0)), Vector3(sz.x - 0.02, load_h * 0.96, sz.z - 0.02), Color(0.66, 0.62, 0.55))
			for sx in [-0.3, 0.3]:
				kit.box(Transform3D(Basis.IDENTITY, Vector3(sx, 0.14 + load_h * 0.5, 0)), Vector3(0.05, load_h + 0.02, sz.z + 0.01), Color(0.15, 0.3, 0.7))
				kit.box(Transform3D(Basis.IDENTITY, Vector3(sx, sz.y - 0.005, 0)), Vector3(0.05, 0.01, sz.z + 0.01), Color(0.15, 0.3, 0.7))
		"drum":
			# A 44-gallon avgas drum: red, with rolling hoops and a lid.
			var paint := Color(0.62, 0.16, 0.12, 0.6)
			kit.cylinder(Transform3D.IDENTITY, h.x, h.x, sz.y, 16, paint, true)
			for hy in [sz.y * 0.33, sz.y * 0.66]:
				kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, hy - 0.015, 0)), h.x + 0.012, h.x + 0.012, 0.03, 16, paint.darkened(0.25), false)
			kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.12, sz.y, 0.05)), 0.03, 0.03, 0.015, 8, Color(0.5, 0.5, 0.5, 0.3), true)
		_:
			# Medical case: white with a red cross on the lid.
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, h.y, 0)), sz, Color(0.86, 0.86, 0.82, 0.6))
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, sz.y + 0.002, 0)), Vector3(0.18, 0.004, 0.05), Color(0.72, 0.12, 0.10))
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, sz.y + 0.002, 0)), Vector3(0.05, 0.004, 0.18), Color(0.72, 0.12, 0.10))
			kit.box(Transform3D(Basis.IDENTITY, Vector3(0, sz.y + 0.03, 0)), Vector3(0.14, 0.02, 0.025), Color(0.25, 0.25, 0.25))
	var m := kit.commit()
	_meshes[kind] = m
	return m


# ------------------------------------------------------------------------------
#  Where each piece is drawn
# ------------------------------------------------------------------------------
## Load spots inside the plane, in its own space: [base position, ceiling].
## Cabin: the floor ahead of the rear bench and the bench itself. Baggage bay:
## the floor behind the bench, up to the bulkhead. Pieces stack in a spot up to
## its ceiling, so nothing pokes through the seats or the skin.
const SPOTS_WOLV := {
	# The floor ahead of the bench is open to the roof: a fuel drum stands there,
	# grocery boxes stack two high. The bench and the bay stay a single layer.
	"cabin": [[Vector3(-0.22, -0.42, 0.50), 0.92], [Vector3(0.22, -0.42, 0.50), 0.92],
		[Vector3(-0.19, -0.19, 0.93), 0.55], [Vector3(0.19, -0.19, 0.93), 0.55]],
	# The tail narrows, so the bay stows single file down the middle.
	"bay": [[Vector3(0.0, -0.42, 1.26), 0.62], [Vector3(0.0, -0.42, 1.60), 0.45]],
}


const Shape = preload("res://scripts/dc3_shape.gd")
static var _dc3_spots := {}


## The load spots for the plane type being flown. The DC-3: two rows down the
## cabin floor (pieces stack to head height), the rest in the rear past the
## cargo door, where the floor starts to rise.
func _spots() -> Dictionary:
	if plane == null or plane.plane_type != "dc3":
		return SPOTS_WOLV
	if _dc3_spots.is_empty():
		var cabin: Array = []
		var bay: Array = []
		var z := -4.25
		while z < 5.4:
			var fy: float = Shape.cabin_floor(z)
			for x in [-0.5, 0.5]:
				var top: float = 1.75 if z < 4.5 else 1.75 - (z - 4.5) * 0.5
				var spot := [Vector3(x, fy, z), top]
				if z < 1.6:
					cabin.append(spot)
				else:
					bay.append(spot)
			z += 0.8
		_dc3_spots = {"cabin": cabin, "bay": bay}
	return _dc3_spots


## Where each loaded piece sits: {piece key: local position}, stacking pieces
## that share a spot. Pieces without a spot yet get the one with most room.
func _layout() -> Dictionary:
	var out := {}
	var all_spots := _spots()
	var height := {}
	for c in ["cabin", "bay"]:
		var hz: Array = []
		for _i in range((all_spots[c] as Array).size()):
			hz.append(0.0)
		height[c] = hz
	for job in jobs.carried:
		if not job.has("pieces") or int(job["pax"]) > 0:
			continue
		if String(job["kind"]) == "pallet":
			var pps: Array = job["pieces"]
			for i in range(pps.size()):
				var ppc: Dictionary = pps[i]
				if (ppc["at"] == "cabin" or ppc["at"] == "bay") and ppc.has("slot"):
					var pz: float = jobs.PALLET_Z[int(ppc["slot"])]
					out[_key(job, i)] = Vector3(0, Shape.cabin_floor(pz) + 0.01, pz)
			continue
		var look: Array = LOOKS.get(String(job["kind"]), LOOKS["freight"])
		var sz: Vector3 = look[0]
		var pieces: Array = job["pieces"]
		for i in range(pieces.size()):
			var pc: Dictionary = pieces[i]
			var at: String = pc["at"]
			if at != "cabin" and at != "bay":
				continue
			var spots: Array = all_spots[at]
			var h: Array = height[at]
			var si := int(pc.get("spot", -1))
			if si < 0 or si >= spots.size():
				si = _first_room(at, h, sz.y)
				pc["spot"] = si
			var base: Vector3 = spots[si][0]
			out[_key(job, i)] = base + Vector3(0, h[si], 0)
			h[si] = float(h[si]) + sz.y + 0.01
	return out


## How many pieces of this kind the plane's spots can hold in all (empty plane):
## each spot stacks them up to its ceiling. Jobs bigger than this can never be
## carried, so the job board checks before offering the flight (jobs.cannot_take).
func piece_capacity(kind: String) -> int:
	var h: float = ((LOOKS.get(kind, LOOKS["freight"]) as Array)[0] as Vector3).y
	var cap := 0
	var all_spots := _spots()
	for c in ["cabin", "bay"]:
		for s in all_spots[c]:
			cap += int(floorf((float(s[1]) + 0.01) / (h + 0.01)))
	return cap


func _first_room(at: String, h: Array, piece_h: float) -> int:
	var spots: Array = _spots()[at]
	var best := 0
	var lowest := INF
	for si in range(spots.size()):
		if float(h[si]) + piece_h <= float(spots[si][1]) and float(h[si]) < lowest:
			lowest = h[si]
			best = si
	return best


## Spots in a compartment that can take a piece this tall: [index, local position].
func _free_spots(at: String, piece_h: float) -> Array:
	_layout()
	var height: Array = []
	for _s in _spots()[at]:
		height.append(0.0)
	for job in jobs.carried:
		if not job.has("pieces") or int(job["pax"]) > 0:
			continue
		var sz: Vector3 = (LOOKS.get(String(job["kind"]), LOOKS["freight"]) as Array)[0]
		for pc in job["pieces"]:
			if pc["at"] == at:
				var si := clampi(int(pc.get("spot", 0)), 0, height.size() - 1)
				height[si] = float(height[si]) + sz.y + 0.01
	var out: Array = []
	var spots: Array = _spots()[at]
	var pal_z: Array = []
	if plane.plane_type == "dc3":
		for slot in jobs.pallet_slots().keys():
			pal_z.append(float(jobs.PALLET_Z[int(slot)]))
	for si in range(spots.size()):
		var under_pallet := false
		for pz in pal_z:
			if absf((spots[si][0] as Vector3).z - float(pz)) < 0.8:
				under_pallet = true
		if under_pallet:
			continue
		if float(height[si]) + piece_h <= float(spots[si][1]):
			out.append([si, (spots[si][0] as Vector3) + Vector3(0, height[si], 0)])
	return out


func _process(_delta: float) -> void:
	if jobs == null or plane == null:
		return
	var seen := {}
	var lay := _layout()
	# draw the pieces where the plane and the walker are DRAWN (physics
	# interpolation), so what's in the cabin or in his arms doesn't jitter
	var pxf: Transform3D = plane.get_global_transform_interpolated()
	for job in _all_jobs():
		if not job.has("pieces") or int(job["pax"]) > 0:
			continue
		var kind: String = job["kind"]
		var look: Array = LOOKS.get(kind, LOOKS["freight"])
		var pieces: Array = job["pieces"]
		for i in range(pieces.size()):
			var pc: Dictionary = pieces[i]
			var k := _key(job, i)
			seen[k] = true
			var mi: MeshInstance3D = _nodes.get(k)
			if mi == null:
				mi = MeshInstance3D.new()
				mi.mesh = _mesh(kind)
				mi.material_override = _mat
				add_child(mi)
				_nodes[k] = mi
			if kind == "rock":
				# nodes go by index, so a quartz chunk and a plain rock can swap
				var want: ArrayMesh = _mesh("quartz" if bool(pc.get("q", false)) else "rock")
				if mi.mesh != want:
					mi.mesh = want
			var at: String = pc["at"]
			if at != "ramp" and at != "dropped":
				_coll_clear(k)
			match at:
				"ramp", "dropped":
					if (pc["pos"] as Vector3) == Vector3.ZERO:
						pc["pos"] = _ramp_spot(int(pc["strip"]), i, job)
					var p: Vector3 = pc["pos"]
					mi.global_transform = Transform3D(Basis(Vector3.UP, float(i) * 1.3 + float(job["id"])), p)
					if kind == "sawlog":
						mi.global_transform = Transform3D(Basis(Vector3.UP, float(i) * 0.37), p + Vector3(0, -0.04, 0))
					elif kind == "rock":
						var rs := pow(float(pc["kg"]) / 45.0, 1.0 / 3.0)
						mi.global_transform = Transform3D(Basis(Vector3.UP, float(pc.get("yaw", 0.0))).scaled(Vector3(rs, rs, rs)), p + Vector3(0, -0.05, 0))
					_coll_set(k, mi.global_transform, look[0])
				"hands":
					if walker != null:
						var hold := Vector3(0, 0.82, -0.42) if look[1] != "drum" else Vector3(0, 0.0, -0.55)
						if kind == "sawlog":
							# on the right shoulder, along the way he's walking
							mi.global_transform = walker.get_global_transform_interpolated() * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.22, 1.42, -0.2))
						else:
							mi.global_transform = walker.get_global_transform_interpolated() * Transform3D(Basis.IDENTITY, hold - Vector3(0, (look[0] as Vector3).y * 0.5 if look[1] != "drum" else 0.0, 0))
				"cabin", "bay":
					mi.global_transform = pxf * Transform3D(Basis.IDENTITY, lay.get(k, Vector3.ZERO))
				"truck":
					var vi := int(pc.get("veh", 0))
					if vi < trucks.size() and trucks[vi] != null:
						var tv: Node3D = trucks[vi]
						if kind == "sawlog" and tv.has_method("log_xf"):
							mi.global_transform = tv.log_xf(int(pc.get("spot", 0)))
						else:
							mi.global_transform = tv.bed_xf(int(pc.get("spot", 0))) * Transform3D(Basis(Vector3.UP, float(i) * 0.3), Vector3.ZERO)
				"forks":
					for fl in forklifts:
						if fl.carrying == pc:
							mi.global_transform = fl.load_xf()
			mi.visible = at != "dropped" or _near_camera(pc["pos"])
	for k in _nodes.keys():
		if not seen.has(k):
			(_nodes[k] as Node).queue_free()
			_nodes.erase(k)
			_coll_clear(k)
	if on_foot:
		_find_target()
		if prompt == "":
			prompt = extra_prompt
	else:
		prompt = ""
		_target = []
	_update_ghost()
	_update_pax(_delta)


func _near_camera(p: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam == null or cam.global_position.distance_to(p) < 1500.0


## Somewhere on the ramp beside the plane for piece `i` of a job, in a neat row
## a few paces off the left wingtip.
func _ramp_spot(strip: int, i: int, job: Dictionary) -> Vector3:
	var xf: Transform3D = plane.global_transform
	var row := int(job["id"]) % 3
	var local := Vector3(-7.0 - 0.95 * float(i % 4), 0.0, -1.0 + 1.1 * float(row) + 0.9 * float(i / 4))
	if String(job["kind"]) == "pallet":
		# Out from the cargo door, in a row, room to get a forklift in.
		local = Vector3(-9.0 - 2.2 * float(row), 0.0, 1.0 + 1.9 * float(i))
	elif plane.plane_type == "dc3":
		local = Vector3(-6.0 - 0.95 * float(i % 4), 0.0, 5.0 + 1.1 * float(row) + 0.9 * float(i / 4))
	var p := xf * local
	p.y = terrain.ground_level_at(p.x, p.z)
	return p


# ------------------------------------------------------------------------------
#  Handling, on foot
# ------------------------------------------------------------------------------
## Which door the pilot is standing at: "cabin", "bay" or "".
## In the DC-3 the one big cargo door serves everything: standing at it
## (outside, or inside next to it) you load the rear; inside the cabin you can
## stow anywhere along the floor.
func _door() -> String:
	if walker == null:
		return ""
	var lp: Vector3 = plane.global_transform.affine_inverse() * walker.global_position
	if plane.plane_type == "dc3":
		if bool(walker.get("in_plane")):
			if lp.z < Shape.BULKHEAD_Z:
				return ""
			return "cabin" if lp.z < 1.6 else "bay"
		if lp.x < -0.9 and lp.x > -3.2 and lp.z > Shape.DOOR_Z[0] - 0.5 and lp.z < Shape.DOOR_Z[1] + 0.5:
			return "bay"
		return ""
	if absf(lp.x) > 0.45 and absf(lp.x) < 2.4 and lp.z > -1.0 and lp.z < 0.9:
		return "cabin"
	if lp.x < -0.4 and lp.x > -2.4 and lp.z >= 0.9 and lp.z < 2.6:
		return "bay"
	return ""


## The door that has to be open to reach a compartment ("cabin" / "bay").
## The DC-3 has only the cargo door (kept as "bay"); from inside nothing needs opening.
func _door_key(compartment: String) -> String:
	if plane.plane_type == "dc3":
		return "bay"
	return compartment


func _door_ok(compartment: String) -> bool:
	if plane.plane_type == "dc3" and bool(walker.get("in_plane")):
		return true
	return bool(plane.door_open.get(_door_key(compartment), false))


static func _describe(job: Dictionary) -> String:
	var what: String = String(KIND_ONE.get(String(job["kind"]), "piece"))
	return what


const KIND_ONE := {"sawlog": "log", "rock": "rock", "groceries": "box of groceries", "freight": "crate", "parts": "crate of engine parts",
	"mail": "mail sack", "fuel": "drum of avgas", "medical": "medical case", "ore": "sack of concentrate",
	"explosives": "case of dynamite", "samples": "core box"}


func _find_target() -> void:
	_target = []
	prompt = ""
	var hint := Game.hint("interact")
	var door := _door()
	var stopped: bool = plane.on_ground and plane.ground_speed < 0.5
	var here: int = terrain.strip_index_at(walker.global_position.x, walker.global_position.z, 90.0)
	if holding.is_empty():
		var pt := _pax_target()
		if not pt.is_empty():
			_target = ["pax", pt]
			prompt = "%s  %s" % [hint, "Show the passenger to the plane" if pt[0] == "board" else "Let the passenger out"]
			return
	var dname := "cabin door" if door == "cabin" else "baggage door"
	if plane.plane_type == "dc3":
		dname = "cargo door"
	if door != "" and stopped and not _door_ok(door):
		_target = ["open", {}, {}, _door_key(door)]
		prompt = "%s  Open the %s" % [hint, dname]
		return
	if not holding.is_empty():
		var job: Dictionary = holding[0]
		var pc: Dictionary = holding[1]
		var lb := int(round(float(pc["kg"]) * 2.20462))
		var tr := _truck_at()
		if tr != null:
			var bed_name: String = "pickup bed" if trucks.find(tr) == 0 else String(tr.display_name())
			var fs := truck_free_spot(tr, String(job["kind"]))
			if fs < 0:
				prompt = "The %s is full" % bed_name
			elif truck_load_kg(tr) + float(pc["kg"]) > float(tr.BED_MAX_KG):
				prompt = "Too heavy for the %s with what's in it (%d lb)" % [bed_name, lb]
			else:
				_target = ["truckput", job, pc, "", fs, tr]
				prompt = "%s  Put the %s on the %s" % [hint, _describe(job), bed_name]
			return
		if job == own_rocks:
			if bool(pc.get("q", false)) and hopper_at.is_valid() and (hopper_at.call(walker.global_position) as Vector3) != Vector3.INF:
				_target = ["hopper", job, pc, ""]
				prompt = "%s  Tip the quartz into the hopper (crushed and washed for its gold)" % hint
				return
			_target = ["drop", job, pc, ""]
			prompt = ("%s  Put the quartz down    (take it to the wash plant's hopper for the gold)" if bool(pc.get("q", false)) else "%s  Put the rock down    (pile them out of the way, or in a bed)") % hint
			return
		if job == own_logs:
			if _near_deck(walker.global_position):
				_target = ["deck", job, pc, ""]
				prompt = "%s  Drop the log on the log deck (into your stock)" % hint
			else:
				_target = ["drop", job, pc, ""]
				prompt = "%s  Put the log down    (take it to the pickup bed, the log trailer or the log deck in the tool yard)" % hint
			return
		if plane.is_crashed and door != "":
			_target = ["drop", job, pc, ""]
			prompt = "%s  Put down the %s (the wreck won't fly)" % [hint, _describe(job)]
			return
		if door != "" and stopped:
			var sz: Vector3 = (LOOKS.get(String(job["kind"]), LOOKS["freight"]) as Array)[0]
			var spot := _aimed_spot(door, sz.y)
			if not jobs.fits(door, float(pc["kg"])):
				prompt = "Too heavy for the %s with what's in it (%d lb)" % [_compartment_name(door), lb]
			elif spot.is_empty():
				prompt = "No room left in the %s" % _compartment_name(door)
			else:
				_target = ["stow", job, pc, door, spot[0]]
				prompt = "%s  Put it in the highlighted spot  (look to choose)" % hint
		elif bool(walker.get("in_plane")):
			prompt = "Carry it back into the cabin to stow it" if door == "" else "Stop the plane to stow it"
		else:
			_target = ["drop", job, pc, ""]
			var where := " here"
			if here >= 0 and here == int(job["to"]):
				where = " (delivery)"
			prompt = "%s  Put down the %s%s" % [hint, _describe(job), where]
		return
	# Hands free: the nearest piece on the ground, or one to take out of the plane.
	var best := 1.9
	var p: Vector3 = walker.global_position
	var near_pallet := false
	for job in _all_jobs():
		if not job.has("pieces") or int(job["pax"]) > 0:
			continue
		for pc in job["pieces"]:
			if pc["at"] != "ramp" and pc["at"] != "dropped":
				continue
			if pc["at"] == "dropped" and int(pc["strip"]) == int(job["to"]):
				continue
			var q: Vector3 = pc["pos"]
			var d := Vector2(q.x - p.x, q.z - p.z).length()
			if String(job["kind"]) == "pallet" or float(pc["kg"]) > HAND_MAX_KG:
				near_pallet = near_pallet or d < 1.8
				continue
			if d < best:
				best = d
				_target = ["pick", job, pc, ""]
	# A wreck: pull what survived out of it (DESIGN_NOTES 79).
	if _target.is_empty() and plane.is_crashed and Vector2(plane.global_position.x - p.x, plane.global_position.z - p.z).length() < 5.0:
		for ji2 in range(jobs.carried.size() - 1, -1, -1):
			var jw: Dictionary = jobs.carried[ji2]
			if not jw.has("pieces") or int(jw["pax"]) > 0 or String(jw["kind"]) == "pallet":
				continue
			for pw in jw["pieces"]:
				if pw["at"] == "cabin" or pw["at"] == "bay":
					_target = ["salvage", jw, pw, ""]
					prompt = "%s  Pull the %s out of the wreck (%d%% damaged)" % [hint, _describe(jw), int(round((1.0 - float(jw["condition"])) * 100.0))]
					return
	# The pickup bed: take something out.
	if _target.is_empty():
		var tr2 := _truck_at()
		if tr2 != null:
			var vi2 := trucks.find(tr2)
			# at the log deck: roll every log off at once
			var mine: Array = []
			for pl in own_logs["pieces"]:
				if pl["at"] == "truck" and int(pl.get("veh", 0)) == vi2:
					mine.append(pl)
			if not mine.is_empty() and _near_deck(tr2.global_position):
				_target = ["truckdeck", own_logs, {}, "", mine]
				prompt = "%s  Roll the %d log%s off onto the log deck" % [hint, mine.size(), "" if mine.size() == 1 else "s"]
				return
			var alljobs := _all_jobs()
			for ji3 in range(alljobs.size() - 1, -1, -1):
				var jt: Dictionary = alljobs[ji3]
				if not jt.has("pieces"):
					continue
				for pt in jt["pieces"]:
					if pt["at"] == "truck" and int(pt.get("veh", 0)) == vi2:
						_target = ["truckout", jt, pt, ""]
						var dest2 := " (for here)" if here >= 0 and here == int(jt["to"]) else ""
						prompt = "%s  Take the %s off the %s%s" % [hint, _describe(jt), "pickup" if vi2 == 0 else "trailer", dest2]
						return
	# Inside the DC-3: roll the pallet nearest the open door out onto the ground.
	if _target.is_empty() and plane.plane_type == "dc3" and bool(walker.get("in_plane")) and stopped:
		var rp: Array = jobs.pallet_rearmost()
		if not rp.is_empty():
			var pz: float = jobs.PALLET_Z[int((rp[1] as Dictionary)["slot"])]
			var lp: Vector3 = plane.global_transform.affine_inverse() * walker.global_position
			if absf(lp.z - pz) < 1.9 and pz > 1.2:
				if plane.door_open.get("bay", false):
					_target = ["rollout", rp[0], rp[1], ""]
					prompt = "%s  Roll the pallet out of the cargo door (%d kg)" % [hint, int((rp[1] as Dictionary)["kg"])]
				else:
					prompt = "Open the cargo door to roll the pallet out"
				return
	if _target.is_empty() and near_pallet:
		prompt = "Too heavy to lift: drive a forklift to it (hangar towns and mines have one)"
		return
	if not _target.is_empty():
		var j2: Dictionary = _target[1]
		var pc2: Dictionary = _target[2]
		prompt = "%s  Pick up the %s (%d lb)" % [hint, "quartz" if bool(pc2.get("q", false)) else _describe(j2), int(round(float(pc2["kg"]) * 2.20462))]
		return
	if door != "" and stopped:
		# The last piece put in through this door comes out first.
		for ji in range(jobs.carried.size() - 1, -1, -1):
			var job3: Dictionary = jobs.carried[ji]
			if not job3.has("pieces") or int(job3["pax"]) > 0 or String(job3["kind"]) == "pallet":
				continue
			for pi in range((job3["pieces"] as Array).size() - 1, -1, -1):
				var pc3: Dictionary = job3["pieces"][pi]
				if pc3["at"] == door:
					_target = ["unstow", job3, pc3, door]
					var dest := ""
					if here >= 0 and here == int(job3["to"]):
						dest = " (for here)"
					prompt = "%s  Take out the %s%s    %s  Close the door" % [hint, _describe(job3), dest, Game.hint("door")]
					return
		if plane.plane_type == "dc3" and bool(walker.get("in_plane")) and not _at_cargo_door_inside():
			return
		var shut: bool = not plane.door_open.get(_door_key(door), false)
		_target = ["open" if shut else "close", {}, {}, _door_key(door)]
		prompt = "%s  %s the %s" % [hint, "Open" if shut else "Close", dname]


func _compartment_name(c: String) -> String:
	if plane.plane_type == "dc3":
		return "cabin" if c == "cabin" else "rear cabin"
	return "cabin" if c == "cabin" else "baggage bay"


## Inside the DC-3, standing by the cargo door.
func _at_cargo_door_inside() -> bool:
	var lp: Vector3 = plane.global_transform.affine_inverse() * walker.global_position
	return lp.x < -0.2 and lp.z > Shape.DOOR_Z[0] - 0.3 and lp.z < Shape.DOOR_Z[1] + 0.3


## The interact button, on foot.
func interact() -> void:
	if _target.is_empty():
		return
	var action: String = _target[0]
	if action == "pax":
		_pax_interact(_target[1])
		_find_target()
		return
	var job: Dictionary = _target[1]
	var pc: Dictionary = _target[2]
	match action:
		"open":
			plane.door_open[String(_target[3])] = true
		"close":
			plane.door_open[String(_target[3])] = false
		"pick", "unstow", "salvage", "truckout":
			holding = [job, pc]
			_move(job, pc, "hands")
		"truckput":
			holding = []
			pc["spot"] = int(_target[4])
			pc["veh"] = maxi(trucks.find(_target[5]), 0)
			_move(job, pc, "truck")
		"deck":
			holding = []
			_to_deck([pc])
		"hopper":
			holding = []
			(own_rocks["pieces"] as Array).erase(pc)
			save_logs()
			if into_hopper.is_valid():
				into_hopper.call(walker.global_position, float(pc["kg"]), float(pc.get("g", 0.0)))
		"truckdeck":
			_to_deck((_target[4] as Array).duplicate())
		"stow":
			holding = []
			pc["spot"] = int(_target[4])
			jobs.move_piece(job, pc, String(_target[3]))
		"rollout":
			# Off the end of the rollers and down onto the ground by the door.
			var out := plane.global_transform * Vector3(-3.0, 0.0, clampf(float(jobs.PALLET_Z[int(pc["slot"])]), Shape.DOOR_Z[0] + 0.6, Shape.DOOR_Z[1] - 0.6))
			out.y = terrain.ground_level_at(out.x, out.z)
			var st: int = terrain.strip_index_at(out.x, out.z, 90.0)
			pc.erase("slot")
			jobs.move_piece(job, pc, "dropped", out, st)
		"drop":
			holding = []
			var front: Vector3 = walker.global_transform * Vector3(0, 0, -0.75)
			front.y = terrain.ground_level_at(front.x, front.z)
			var here: int = terrain.strip_index_at(front.x, front.z, 90.0)
			_move(job, pc, "dropped", front, here)
	_find_target()


## The pickup whose bed you're standing at, or null.
func _truck_at() -> Node3D:
	if walker == null or bool(walker.get("in_plane")):
		return null
	for tr in trucks:
		if tr != null and tr.at_bed(walker.global_position) and tr.driven == false:
			return tr
	return null


## A piece moving: own logs don't go through the job book.
func _move(job: Dictionary, pc: Dictionary, where: String, pos: Vector3 = Vector3.ZERO, strip: int = -1) -> void:
	if _own(job):
		pc["at"] = where
		pc["pos"] = pos
		pc["strip"] = strip
		save_logs()
		return
	jobs.move_piece(job, pc, where, pos, strip)


## First free spot in a bed (pickup or trailer), or -1. Logs have their own
## spots (lying along the bed, stacked); cargo pieces the bed's grid.
func truck_free_spot(tr: Node3D, kind: String = "") -> int:
	var vi := trucks.find(tr)
	var logs := kind == "sawlog" and tr.has_method("log_xf")
	var used := {}
	for j in _all_jobs():
		for pc in j.get("pieces", []):
			if pc["at"] == "truck" and int(pc.get("veh", 0)) == vi and (String(j["kind"]) == "sawlog") == logs:
				used[int(pc.get("spot", 0))] = true
	var n: int = int(tr.LOG_CAP) if logs else (tr.BED_SPOTS as Array).size()
	for i in range(n):
		if not used.has(i):
			return i
	return -1


## Weight of the cargo in a bed (the pickup's if none given), kg.
func truck_load_kg(tr: Node3D = null) -> float:
	var vi := 0 if tr == null else trucks.find(tr)
	var kg := 0.0
	for j in _all_jobs():
		for pc in j.get("pieces", []):
			if pc["at"] == "truck" and int(pc.get("veh", 0)) == vi:
				kg += float(pc["kg"])
	return kg


## How much the pilot is carrying, kg (slows him down).
func carried_load() -> float:
	if holding.is_empty():
		return 0.0
	return float((holding[1] as Dictionary)["kg"])


## Getting back in the plane with something in your arms: it goes in the cabin
## if it fits, otherwise it is set down by the door.
func stow_held() -> void:
	if holding.is_empty():
		return
	var job: Dictionary = holding[0]
	var pc: Dictionary = holding[1]
	holding = []
	if _own(job):
		var lp: Vector3 = walker.global_position
		_move(job, pc, "dropped", Vector3(lp.x, terrain.ground_level_at(lp.x, lp.z), lp.z))
		return
	if jobs.fits("cabin", float(pc["kg"])) and not _free_spots("cabin", 0.0).is_empty():
		jobs.move_piece(job, pc, "cabin")
	else:
		var p: Vector3 = walker.global_position
		jobs.move_piece(job, pc, "dropped", Vector3(p.x, terrain.ground_level_at(p.x, p.z), p.z), terrain.strip_index_at(p.x, p.z, 90.0))


## Close (or open) the door you are standing at.
func toggle_door() -> void:
	var door := _door()
	if door == "":
		return
	if plane.plane_type == "dc3" and bool(walker.get("in_plane")) and not _at_cargo_door_inside():
		return
	door = _door_key(door)
	plane.door_open[door] = not plane.door_open.get(door, false)


## The free spot the pilot is looking toward, as [index, local position], or [].
func _aimed_spot(door: String, piece_h: float) -> Array:
	var free := _free_spots(door, piece_h)
	if free.is_empty():
		return []
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return free[0]
	var fwd := -cam.global_transform.basis.z
	var best: Array = free[0]
	var best_dot := -2.0
	for f in free:
		var wp: Vector3 = plane.global_transform * (f[1] as Vector3)
		var d := (wp - cam.global_position).normalized().dot(fwd)
		if d > best_dot:
			best_dot = d
			best = f
	return best


# ------------------------------------------------------------------------------
#  The highlighted spot
# ------------------------------------------------------------------------------
var _ghost: MeshInstance3D


func _update_ghost() -> void:
	var show: bool = on_foot and not _target.is_empty() and _target[0] == "stow"
	if not show:
		if _ghost != null:
			_ghost.visible = false
		return
	if _ghost == null:
		_ghost = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.4, 1.0, 0.5, 0.35)
		m.no_depth_test = true
		_ghost.material_override = m
		_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ghost)
	var job: Dictionary = _target[1]
	var sz: Vector3 = (LOOKS.get(String(job["kind"]), LOOKS["freight"]) as Array)[0]
	var bm := BoxMesh.new()
	bm.size = sz
	_ghost.mesh = bm
	var local := Vector3.ZERO
	for f in _free_spots(String(_target[3]), sz.y):
		if int(f[0]) == int(_target[4]):
			local = f[1]
	_ghost.global_transform = plane.global_transform * Transform3D(Basis.IDENTITY, local + Vector3(0, sz.y * 0.5, 0))
	var pulse := 0.25 + 0.15 * sin(Time.get_ticks_msec() * 0.006)
	(_ghost.material_override as StandardMaterial3D).albedo_color = Color(0.4, 1.0, 0.5, pulse)
	_ghost.visible = true


# ------------------------------------------------------------------------------
#  Passengers: a basic figure for each one. Loaded for you, they are already
#  in their seats. "By hand", they wait on the ramp until you show them to the
#  plane; at the destination you let them out at the cabin door and they walk
#  off (the job is paid when the last one is out).
# ------------------------------------------------------------------------------
const PilotModel2 = preload("res://scripts/pilot_model.gd")
const PilotRig2 = preload("res://scripts/pilot_rig.gd")
## Seats for passengers: front right, then the rear bench (eye positions, plane space).
const PAX_EYES := [Vector3(0.24, 0.80, -0.30), Vector3(-0.22, 0.76, 0.72), Vector3(0.22, 0.76, 0.72)]
const PAX_DOOR := Vector3(-1.3, 0.0, -0.1)     # where they climb in, plane space
## DC-3: the fold-down troop benches along each wall, facing in.
const DC3_BENCH_Z := [-3.6, -2.9, -2.2, -1.5, -0.8, -0.1, 0.6, 1.3]
const DC3_PAX_DOOR := Vector3(-2.3, 0.0, 3.2)


func _pax_door() -> Vector3:
	return DC3_PAX_DOOR if plane.plane_type == "dc3" else PAX_DOOR


## Seat n: [eye position, facing (radians about up, 0 = forward)].
func _pax_seat(n: int) -> Array:
	if plane.plane_type == "dc3":
		var side := 1.0 if n % 2 == 0 else -1.0
		var z: float = DC3_BENCH_Z[mini(n / 2, DC3_BENCH_Z.size() - 1)]
		return [Vector3(0.80 * side, Shape.cabin_floor(z) + 1.22, z), PI * 0.5 * side]
	return [PAX_EYES[mini(n, PAX_EYES.size() - 1)], 0.0]
var _pax := {}                                 # piece key -> model


func _update_pax(delta: float) -> void:
	var seen := {}
	var seat := 0
	var pxf: Transform3D = plane.global_transform
	for job in jobs.carried:
		if int(job["pax"]) <= 0 or not job.has("pieces") or bool(job.get("jumped", false)):
			continue
		var pieces: Array = job["pieces"]
		for i in range(pieces.size()):
			var pc: Dictionary = pieces[i]
			var k := "p" + _key(job, i)
			seen[k] = true
			var m: Node3D = _pax.get(k)
			if m == null:
				m = PilotRig2.new() if PilotRig2.available() else PilotModel2.new()
				add_child(m)
				m.build()
				_pax[k] = m
			var at: String = pc["at"]
			if at == "cabin":
				var st: Array = _pax_seat(seat)
				var eye: Vector3 = st[0]
				seat += 1
				m.animate(delta, PilotModel2.SIT, 0.0, Time.get_ticks_msec() * 0.001)
				var b := Basis(Vector3.UP, float(st[1]))
				var ml: Vector3 = b * (m.eye_local() as Vector3)
				m.global_transform = pxf * Transform3D(b, eye - ml)
				m.visible = true
				continue
			# On the ground: waiting, or walking (to the plane, or away from it).
			if (pc["pos"] as Vector3) == Vector3.ZERO:
				pc["pos"] = _ramp_spot(int(pc["strip"]), i + 4, job)
			var p: Vector3 = pc["pos"]
			var goal: Vector3 = pc.get("goal", p)
			var to := goal - p
			to.y = 0.0
			var moving := to.length() > 0.15
			if moving:
				var step := minf(1.3 * delta, to.length())
				p += to.normalized() * step
				p.y = terrain.ground_level_at(p.x, p.z)
				pc["pos"] = p
				m.global_transform = Transform3D(Basis(Vector3.UP, atan2(-to.x, -to.z)), p)
				m.animate(delta, PilotModel2.WALK, 1.3, Time.get_ticks_msec() * 0.001)
			else:
				var face := pxf.origin - p
				m.global_transform = Transform3D(Basis(Vector3.UP, atan2(-face.x, -face.z)), p)
				m.animate(delta, PilotModel2.IDLE, 0.0, Time.get_ticks_msec() * 0.001)
				if bool(pc.get("boarding", false)):
					# Reached the door: in they get.
					pc.erase("boarding")
					pc.erase("goal")
					jobs.move_piece(job, pc, "cabin")
			m.visible = not (at == "dropped" and not moving and int(pc["strip"]) == int(job["to"]) and p.distance_to(pxf.origin) > 14.0)
	for k in _pax.keys():
		if not seen.has(k):
			(_pax[k] as Node).queue_free()
			_pax.erase(k)


## Passenger actions for interact, or [] (checked before the cargo ones).
func _pax_target() -> Array:
	var door := _door()
	var here: int = terrain.strip_index_at(walker.global_position.x, walker.global_position.z, 90.0)
	var p: Vector3 = walker.global_position
	for job in jobs.carried:
		if int(job["pax"]) <= 0 or not job.has("pieces"):
			continue
		for pc in job["pieces"]:
			if pc["at"] == "ramp" and not bool(pc.get("boarding", false)):
				var q: Vector3 = pc["pos"]
				if q != Vector3.ZERO and Vector2(q.x - p.x, q.z - p.z).length() < 2.2:
					return ["board", job, pc]
			if pc["at"] == "cabin" and (door == "cabin" or (plane.plane_type == "dc3" and door != "" and not bool(walker.get("in_plane")))) and here >= 0 and here == int(job["to"]):
				return ["deplane", job, pc]
	return []


func _pax_interact(t: Array) -> void:
	var job: Dictionary = t[1]
	var pc: Dictionary = t[2]
	var pxf: Transform3D = plane.global_transform
	if t[0] == "board":
		var dk := "bay" if plane.plane_type == "dc3" else "cabin"
		if not plane.door_open.get(dk, false):
			plane.door_open[dk] = true      # you open it for them
		pc["boarding"] = true
		var d := pxf * _pax_door()
		d.y = terrain.ground_level_at(d.x, d.z)
		pc["goal"] = d
	else:
		# Out at the door, then off toward the buildings, a dozen paces away.
		var out := pxf * _pax_door()
		out.y = terrain.ground_level_at(out.x, out.z)
		var away := pxf * (_pax_door() + Vector3(-14.0, 0, 3.0 * float(randi() % 3)))
		away.y = terrain.ground_level_at(away.x, away.z)
		var strip: int = terrain.strip_index_at(out.x, out.z, 90.0)
		jobs.move_piece(job, pc, "dropped", out, strip)
		pc["goal"] = away
