extends Node
## Bush flying work: each airstrip has a board of jobs (freight, groceries,
## mail, fuel drums, medical supplies, passengers). Accept one at the strip,
## it is loaded into the cabin and baggage bay (real weight and balance), fly
## it to its destination, stop, and unload it to get paid. Rough landings and
## damage knock the pay down; a crash loses the load. Money and the jobs you
## are carrying are saved.
##
## For now loading and unloading are done from the job board menu; later the
## pilot will carry each item himself.

const SAVE := "user://career.cfg"
const START_MONEY := 1500

signal changed
signal detonated(strength: float)      # dynamite aboard went up (main blows the plane)
signal warn(text: String)
signal rep_up(strip_name: String, standing: String)

var plane: Node3D
var terrain: RefCounted
var cargo: Node = null           # cargo handler, for piece stowage capacity
var money := START_MONEY
var spares := {}              # engine parts carried in the plane: {kind: count}
var carried: Array = []          # jobs on board: Dictionary each
var completed := 0
var _epoch := 0                  # bumps when boards should refresh
var _boards := {}                # strip index -> [epoch, jobs]
var _next_id := 1
var contracts: Array = []        # running contracts (see contract_offers)
signal contract_done(title: String, bonus: int)
var rep := {}                    # strip name -> jobs done for it (to or from)
const REP_NAMES := ["Stranger", "Known", "Regular", "Trusted", "Their pilot", "Legend"]
var last_paid: Array = []        # [title, amount] of the last delivery, for messages

## kind -> [title, item, kg per unit (min, max), units (min, max), $ per kg-nm, base $, fragile, urgent, where]
## where: "any", "small" (bush strips), "town" (Proving Ground)
const KINDS := {
	"groceries": ["Groceries", "boxes of groceries", 15.0, 25.0, 2, 8, 0.10, 60, true, false, "small"],
	"freight": ["Freight", "crates of supplies", 20.0, 45.0, 1, 5, 0.09, 50, false, false, "any"],
	"parts": ["Engine parts", "crate of engine parts", 35.0, 70.0, 1, 2, 0.11, 80, true, false, "any"],
	"mail": ["Mail", "mail sacks", 8.0, 14.0, 1, 4, 0.16, 70, false, true, "any"],
	"fuel": ["Fuel drums", "drums of avgas", 85.0, 85.0, 1, 2, 0.08, 90, false, false, "small"],
	"medical": ["Medical supplies", "medical cases", 6.0, 12.0, 1, 3, 0.22, 150, true, true, "any"],
	"pax": ["Passengers", "passengers", 80.0, 95.0, 1, 2, 0.20, 120, true, false, "any"],
	"pallet": ["Pallet freight", "pallets", 220.0, 520.0, 1, 4, 0.045, 220, false, false, "any"],
	# (DESIGN_NOTES 173) hazardous and sensitive loads: big money, a hard
	# landing or a crash with dynamite aboard and it goes up
	"explosives": ["Dynamite for the mine", "cases of dynamite", 22.0, 25.0, 1, 4, 0.30, 260, true, false, "small"],
	"samples": ["Core samples (assay lab)", "boxes of core samples", 10.0, 18.0, 1, 3, 0.20, 140, true, true, "any"],
}
const PALLET_TITLES := ["Mine machinery", "Building supplies", "Drill pipe", "Generator and parts", "Camp supplies", "Lumber"]

## Pallet positions down the DC-3's cabin floor (station z), front first. The
## cargo door is over the last two; pallets slide forward on the floor rollers.
const PALLET_Z := [-3.9, -2.6, -1.3, 0.0, 1.3, 2.6, 3.85]


## Strips with a forklift (the hangar towns and the mines).
func has_forklift(k: int) -> bool:
	if k < 0:
		return false
	var nm := String(terrain.strips[k]["name"])
	return nm in terrain.HANGARS or nm.contains("Mine")


static func pallet_compartment(slot: int) -> String:
	return "cabin" if float(PALLET_Z[slot]) < 1.6 else "bay"


## Slots holding a pallet: {slot: [job, piece]}.
func pallet_slots() -> Dictionary:
	var out := {}
	for j in carried:
		if String(j.get("kind", "")) != "pallet":
			continue
		for pc in j.get("pieces", []):
			if (pc["at"] == "cabin" or pc["at"] == "bay") and pc.has("slot"):
				out[int(pc["slot"])] = [j, pc]
	return out


## The frontmost free slot (where a pallet pushed in at the door rolls to), or -1.
func pallet_free_slot() -> int:
	var used := pallet_slots()
	for i in range(PALLET_Z.size()):
		if not used.has(i):
			return i
	return -1


## The pallet nearest the door (the one that comes out first), or [].
func pallet_rearmost() -> Array:
	var used := pallet_slots()
	for i in range(PALLET_Z.size() - 1, -1, -1):
		if used.has(i):
			return used[i]
	return []
## Strips with a skydiving drop zone beside them (and the jump heights on offer, ft above the ground).
const SKYDIVE_STRIPS := ["Proving Ground"]
const JUMP_HEIGHTS := [3500, 5000, 7500, 10000]
const PAX_NAMES := ["a geologist", "a trapper", "two hunters", "a schoolteacher", "a surveyor", "a cannery worker",
	"a lineman", "a nurse", "a fisherman", "a prospector", "a game warden", "a family of two"]


func _ready() -> void:
	load_career()



# ------------------------------------------------------------------------------
#  Boards
# ------------------------------------------------------------------------------
## The jobs offered at airstrip `k` right now.
func board(k: int) -> Array:
	if k < 0:
		return []
	var b: Array = _boards.get(k, [])
	if b.is_empty() or int(b[0]) != _epoch:
		b = [_epoch, _generate(k)]
		_boards[k] = b
	_add_contract_loads(k, b[1])
	return b[1]


# ------------------------------------------------------------------------------
#  Contracts: a run of loads from a town out to one bush strip, with a bonus
#  when the last one is delivered. Offered once people know you (standing
#  "Known" or better at the town).
# ------------------------------------------------------------------------------
const CONTRACT_KINDS := [
	["freight", "Supply run", "crates of supplies", 140.0, 230.0],
	["groceries", "Store resupply", "boxes of groceries", 110.0, 190.0],
	["fuel", "Fuel cache", "drums of avgas", 170.0, 170.0],
	["parts", "Machinery parts", "crates of parts", 120.0, 220.0],
]

func contract_offers(k: int) -> Array:
	if k < 0 or not bool(terrain.strips[k]["fuel"]) or rep_tier(k) < 1:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([k, completed / 4, 4242])
	var out: Array = []
	for n in range(1 + mini(rep_tier(k), 2)):
		var to: int = rng.randi() % terrain.strips.size()
		if to == k or (bool(terrain.strips[to]["fuel"]) and int(terrain.strips[to]["difficulty"]) <= 1):
			continue
		var spec: Array = CONTRACT_KINDS[rng.randi() % CONTRACT_KINDS.size()]
		var loads := rng.randi_range(3, 6)
		var kg := roundf(rng.randf_range(float(spec[3]), float(spec[4])))
		var nm := _distance_nm(k, to)
		var per := int(roundf((90.0 + 0.11 * kg * nm * (1.0 + 0.25 * (float(terrain.strips[to]["difficulty"]) - 1.0))) / 5.0) * 5.0)
		var id := int(hash([k, to, completed / 4, n])) & 0x3fffffff
		var taken := false
		for c in contracts:
			if int(c["id"]) == id:
				taken = true
		if taken:
			continue
		out.append({"id": id, "title": "%s for %s" % [spec[1], terrain.strips[to]["name"]], "kind": spec[0],
			"what": spec[2], "from": k, "to": to, "loads": loads, "done": 0, "kg": kg, "per_load": per,
			"bonus": int(roundf(float(per * loads) * 0.6 / 10.0) * 10.0)})
	return out


func accept_contract(c: Dictionary) -> void:
	contracts.append(c.duplicate())
	_epoch += 1
	save_career()
	changed.emit()


## Put the next loads of each contract running from strip k on its board.
func _add_contract_loads(k: int, list: Array) -> void:
	for c in contracts:
		if int(c["from"]) != k:
			continue
		var cid := int(c["id"])
		var pending := 0
		for j in carried:
			if int(j.get("contract", -1)) == cid:
				pending += 1
		for j in list:
			if int(j.get("contract", -1)) == cid:
				pending += 1
		var left: int = int(c["loads"]) - int(c["done"]) - pending
		if left > 0 and pending == 0:
			var units := clampi(int(roundf(float(c["kg"]) / 40.0)), 1, 6)
			if cargo != null:   # never more pieces a trip than the plane can stow
				units = clampi(units, 1, maxi(int(cargo.piece_capacity(String(c["kind"]))), 1))
			list.append({"id": cid * 10 + int(c["done"]) % 10, "kind": c["kind"], "title": "Contract",
				"what": "load %d of %d: %s for %s" % [int(c["done"]) + 1, int(c["loads"]), c["what"], terrain.strips[int(c["to"])]["name"]],
				"from": k, "to": int(c["to"]), "kg": float(c["kg"]), "pay": int(c["per_load"]), "fragile": false,
				"urgent": false, "limit_min": 0.0, "pax": 0, "n": units, "contract": cid})


func _generate(k: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([k, _epoch, 1988])
	var strips: Array = terrain.strips
	var here: Dictionary = strips[k]
	var town := bool(here["fuel"]) and int(here["difficulty"]) <= 1
	var count := (rng.randi_range(5, 7) if town else rng.randi_range(2, 4)) + mini(rep_tier(k), 3)
	var out: Array = []
	var tries := 0
	while out.size() < count and tries < 40:
		tries += 1
		var kinds := KINDS.keys()
		var kind: String = kinds[rng.randi() % kinds.size()]
		if kind == "pallet" and not has_forklift(k):
			continue
		var spec: Array = KINDS[kind]
		var where: String = spec[10]
		var to := rng.randi() % strips.size()
		if to == k:
			continue
		var dest: Dictionary = strips[to]
		var dest_town := bool(dest["fuel"]) and int(dest["difficulty"]) <= 1
		# Groceries and fuel go out to the bush, not into town.
		if where == "small" and dest_town:
			continue
		var units := rng.randi_range(int(spec[4]), int(spec[5]))
		var kg_each := rng.randf_range(float(spec[2]), float(spec[3]))
		var kg := roundf(kg_each * float(units))
		var nm := _distance_nm(k, to)
		var hard := float(dest["difficulty"])
		var pay := float(spec[7]) + float(spec[6]) * kg * nm * (1.0 + 0.25 * (hard - 1.0)) + 40.0 * hard
		pay *= 1.0 + 0.05 * float(rep_tier(k))
		var urgent: bool = spec[9]
		var limit := 0.0
		if urgent:
			limit = ceilf(nm / 95.0 * 60.0 * 1.6 + 8.0)     # minutes, at a 95 kt cruise with slack
			pay *= 1.25
		var title: String = spec[0]
		var what := "%d %s" % [units, spec[1]]
		if kind == "pax":
			what = PAX_NAMES[rng.randi() % PAX_NAMES.size()]
			units = 2 if what.begins_with("two") or what.begins_with("a family") else 1
			kg = roundf(float(units) * kg_each + 12.0 * float(units))   # with their bags
			title = "Passenger" if units == 1 else "Passengers"
		if kind == "pallet":
			title = PALLET_TITLES[rng.randi() % PALLET_TITLES.size()]
			what = "%d pallet%s, %d kg (DC-3, forklift)" % [units, "" if units == 1 else "s", int(kg)]
		out.append({
			"id": _next_id, "kind": kind, "title": title, "what": what, "from": k, "to": to,
			"kg": kg, "pay": int(roundf(pay / 5.0) * 5.0), "fragile": bool(spec[8]),
			"urgent": urgent, "limit_min": limit, "pax": units if kind == "pax" else 0, "n": units,
			"explosive": kind == "explosives",
		})
		_next_id += 1
	# Skydivers: up to the drop zone beside this strip and back.
	if String(here["name"]) in SKYDIVE_STRIPS and rng.randf() < 0.75:
		var jumpers := rng.randi_range(1, 3)
		var alt_ft: int = JUMP_HEIGHTS[rng.randi() % JUMP_HEIGHTS.size()]
		var pay2 := 90.0 + 0.05 * float(alt_ft) * float(jumpers)
		out.append({
			"id": _next_id, "kind": "skydive", "title": "Skydivers", "from": k, "to": k,
			"what": "%d skydiver%s to %d ft over the drop zone" % [jumpers, "" if jumpers == 1 else "s", alt_ft],
			"kg": float(jumpers) * 95.0, "pay": int(roundf(pay2 / 5.0) * 5.0), "fragile": false,
			"urgent": false, "limit_min": 0.0, "pax": jumpers, "n": jumpers, "alt_ft": alt_ft,
		})
		_next_id += 1
	return out


## The drop zone beside a skydiving strip (on the ground), or Vector3.INF.
func drop_zone(k: int) -> Vector3:
	if k < 0 or not (String(terrain.strips[k]["name"]) in SKYDIVE_STRIPS):
		return Vector3.INF
	var p: Vector3 = terrain.strip_point(k, 0.0, 380.0)
	p.y = terrain.height_at(p.x, p.z)
	return p


## The skydivers are all down: paid by how close to the target they landed.
func finish_skydive(j: Dictionary, score: float) -> int:
	var amount := int(roundf(float(j["pay"]) * clampf(score, 0.2, 1.0) / 5.0) * 5.0)
	_pay(j, amount)
	return amount


func _distance_nm(a: int, b: int) -> float:
	var pa: Vector3 = terrain.strips[a]["pos"]
	var pb: Vector3 = terrain.strips[b]["pos"]
	return Vector2(pa.x - pb.x, pa.z - pb.z).length() / 1852.0


# ------------------------------------------------------------------------------
#  Where we are
# ------------------------------------------------------------------------------
## The airstrip the plane is stopped at, or -1.
func strip_here() -> int:
	if plane == null or not plane.on_ground or plane.ground_speed > 1.0 or plane.is_crashed:
		return -1
	var p: Vector3 = plane.global_position
	var k: int = terrain.strip_index_at(p.x, p.z, 70.0)
	return k


# ------------------------------------------------------------------------------
#  Loading
# ------------------------------------------------------------------------------
## Weight of job loads actually on board.
func carried_kg() -> float:
	var t := 0.0
	for j in carried:
		for pc in j["pieces"]:
			if pc["at"] == "cabin" or pc["at"] == "bay":
				t += float(pc["kg"])
	return t


func carried_pax() -> int:
	var n := 0
	for j in carried:
		n += int(j["pax"])
	return n


## Room left for job loads, kg: cabin, aft bay, and before the maximum weight.
func room() -> Dictionary:
	var front_free: float = plane.cargo_front_max - plane.cargo_front - plane.job_front
	var rear_free: float = plane.cargo_rear_max - plane.cargo_rear - plane.job_rear
	var weight_free: float = plane.max_mass - plane.gross_mass()
	return {"front": maxf(front_free, 0.0), "rear": maxf(rear_free, 0.0), "weight": weight_free}


## Why a job cannot be taken right now, or "" if it can.
func cannot_take(j: Dictionary) -> String:
	var r := room()
	var kg: float = j["kg"]
	if String(j.get("kind", "")) == "pallet":
		if plane.plane_type != "dc3":
			return "Pallets need the DC-3's cargo door"
		var free := 0
		var used := pallet_slots()
		free = PALLET_Z.size() - used.size()
		if int(j.get("n", 1)) > free:
			return "No floor space for %d pallets" % int(j.get("n", 1))
	if int(j["pax"]) > 0:
		if carried_pax() + int(j["pax"]) > 3:
			return "No seats free"
		if kg > float(r["front"]):
			return "Cabin is full"
	elif kg > float(r["front"]) + float(r["rear"]):
		return "No room on board"
	elif String(j.get("kind", "")) != "pallet" and cargo != null:
		var n := maxi(int(j.get("n", 1)), 1)
		var cap: int = cargo.piece_capacity(String(j.get("kind", "freight")))
		if n > cap:
			return "%d pieces won't stow in this plane (%d at most)" % [n, cap]
	if kg > float(r["weight"]):
		return "Too heavy: over maximum weight"
	return ""


## Accept a job at this strip. Quick: it is loaded for you. By hand: the
## pieces are set out on the ramp for you to carry aboard (cargo.gd).
func take(j: Dictionary, by_hand: bool = false) -> bool:
	if cannot_take(j) != "" or strip_here() != int(j["from"]):
		return false
	var job := j.duplicate()
	job["condition"] = 1.0
	job["minutes"] = 0.0
	job["hard_landings"] = 0
	var n: int = maxi(int(j.get("n", 1)), 1)
	var pieces: Array = []
	for i in range(n):
		pieces.append({"kg": float(j["kg"]) / float(n), "at": "ramp", "strip": int(j["from"]), "pos": Vector3.ZERO})
	job["pieces"] = pieces
	job["by_hand"] = by_hand
	carried.append(job)
	var list: Array = board(int(j["from"]))
	list.erase(j)
	if not job["by_hand"]:
		_auto_load(job)
	_stow()
	save_career()
	changed.emit()
	return true


## A job made somewhere other than the board (a mine's output): taken here.
func take_custom(j: Dictionary, by_hand: bool) -> bool:
	if strip_here() != int(j["from"]):
		return false
	var job := j.duplicate()
	job["condition"] = 1.0
	job["minutes"] = 0.0
	job["hard_landings"] = 0
	var n: int = maxi(int(j.get("n", 1)), 1)
	var pieces: Array = []
	for i in range(n):
		pieces.append({"kg": float(j["kg"]) / float(n), "at": "ramp", "strip": int(j["from"]), "pos": Vector3.ZERO})
	job["pieces"] = pieces
	job["by_hand"] = by_hand
	carried.append(job)
	if not by_hand:
		_auto_load(job)
	_stow()
	save_career()
	changed.emit()
	return true


## Load whatever of a job is still on the ramp: cabin first (passengers always), then the bay.
func _auto_load(job: Dictionary) -> void:
	for pc in job["pieces"]:
		if pc["at"] != "ramp" and pc["at"] != "hands":
			continue
		if String(job.get("kind", "")) == "pallet":
			var slot := pallet_free_slot()
			if slot < 0:
				continue
			pc["slot"] = slot
			pc["at"] = pallet_compartment(slot)
			_stow()
			continue
		var r := room()
		var kg: float = pc["kg"]
		if int(job["pax"]) > 0 or kg <= float(r["front"]):
			pc["at"] = "cabin"
		else:
			pc["at"] = "bay"
		_stow()


## Load the rest of a job for the player (the job board's quick button).
func load_rest(job: Dictionary) -> void:
	_auto_load(job)
	_stow()
	save_career()
	changed.emit()


## Room in a compartment for one more piece.
func fits(where: String, kg: float) -> bool:
	var r := room()
	if kg > float(r["weight"]):
		return false
	return kg <= float(r["front"] if where == "cabin" else r["rear"])


## Move a piece (by hand): "hands", "cabin", "bay", "ramp" / "dropped" at a position.
func move_piece(job: Dictionary, pc: Dictionary, where: String, pos: Vector3 = Vector3.ZERO, strip: int = -1) -> void:
	pc["at"] = where
	pc["pos"] = pos
	pc["strip"] = strip
	_stow()
	# Everything dropped at the destination: delivered.
	if where == "dropped" and strip == int(job["to"]):
		var all_here := true
		for q in job["pieces"]:
			if not (q["at"] == "dropped" and int(q["strip"]) == strip):
				all_here = false
		if all_here:
			var p: Array = payout(job)
			_pay(job, p[0])
			changed.emit()
			return
	save_career()
	changed.emit()


## How many pieces of a job are where.
func count_at(job: Dictionary, where: String) -> int:
	var c := 0
	for pc in job["pieces"]:
		if pc["at"] == where:
			c += 1
	return c


## Weight from what is stowed in the cabin and the baggage bay.
func _stow() -> void:
	var front := 0.0
	var rear := 0.0
	for j in carried:
		for pc in j.get("pieces", []):
			if pc["at"] == "cabin":
				front += float(pc["kg"])
			elif pc["at"] == "bay":
				rear += float(pc["kg"])
	plane.set_job_load(front, rear)


## Jobs on board that end here.
func deliverable() -> Array:
	var k := strip_here()
	var out: Array = []
	for j in carried:
		if int(j["to"]) == k and String(j["kind"]) != "skydive":
			out.append(j)
	return out


## What a carried job will pay if delivered now: [amount, note].
func payout(j: Dictionary) -> Array:
	var pay := float(j["pay"])
	var notes: Array[String] = []
	var c: float = j["condition"]
	if c < 0.999:
		pay *= c
		notes.append("%d%% damaged" % int(round((1.0 - c) * 100.0)))
	if bool(j["urgent"]) and float(j["minutes"]) > float(j["limit_min"]):
		pay *= 0.5
		notes.append("late")
	if int(j["pax"]) > 0 and int(j["hard_landings"]) > 0:
		pay *= maxf(1.0 - 0.15 * float(j["hard_landings"]), 0.4)
		notes.append("rough ride")
	return [int(roundf(pay)), ", ".join(notes)]


## Unload a job at its destination and get paid (quick). Pieces still sitting
## on a ramp somewhere else mean it cannot be finished yet. Returns the amount.
func deliver(j: Dictionary) -> int:
	if not (j in deliverable()):
		return 0
	for pc in j["pieces"]:
		if pc["at"] == "ramp" or pc["at"] == "truck" or (pc["at"] == "dropped" and int(pc["strip"]) != int(j["to"])):
			return 0
	var p: Array = payout(j)
	_pay(j, p[0])
	return p[0]


## Standing with the people at a strip: 0 (stranger) to 5, from the jobs you
## have flown for them. Higher standing: more work on the board, better pay.
func rep_tier(k: int) -> int:
	if k < 0 or k >= terrain.strips.size():
		return 0
	var n := int(rep.get(String(terrain.strips[k]["name"]), 0))
	for t in range(5, 0, -1):
		if n >= [0, 3, 8, 15, 25, 40][t]:
			return t
	return 0


func _bump_rep(k: int) -> void:
	if k >= 0 and k < terrain.strips.size():
		var nm := String(terrain.strips[k]["name"])
		var before := rep_tier(k)
		rep[nm] = int(rep.get(nm, 0)) + 1
		if rep_tier(k) > before:
			rep_up.emit(nm, REP_NAMES[rep_tier(k)])


func _pay(j: Dictionary, amount: int) -> void:
	money += amount
	completed += 1
	_bump_rep(int(j["from"]))
	if int(j["to"]) != int(j["from"]):
		_bump_rep(int(j["to"]))
	var cid := int(j.get("contract", -1))
	for c in contracts.duplicate():
		if int(c["id"]) == cid:
			c["done"] = int(c["done"]) + 1
			if int(c["done"]) >= int(c["loads"]):
				money += int(c["bonus"])
				contracts.erase(c)
				_bump_rep(int(c["to"]))
				contract_done.emit(String(c["title"]), int(c["bonus"]))
	carried.erase(j)
	_epoch += 1          # boards change after each job
	_stow()
	save_career()
	changed.emit()
	last_paid = [String(j["title"]), amount]


## Can this job be unloaded with the quick button here?
func can_quick_unload(j: Dictionary) -> bool:
	if not (j in deliverable()):
		return false
	for pc in j["pieces"]:
		if pc["at"] == "ramp" or (pc["at"] == "dropped" and int(pc["strip"]) != int(j["to"])):
			return false
	return true


## Drop a job without delivering (left on the ramp here). No pay.
func abandon(j: Dictionary) -> void:
	carried.erase(j)
	_stow()
	save_career()
	changed.emit()


# ------------------------------------------------------------------------------
#  What happens on the way
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	# Sandbox: the money never runs out.
	if Game.sandbox and money < 5000000:
		money = 10000000
	if carried.is_empty() or plane == null or get_tree().paused:
		return
	for j in carried:
		j["minutes"] = float(j["minutes"]) + delta / 60.0
	# dynamite in a burning plane: a few seconds, then it goes
	if bool(plane.get("on_fire")) and _explosives_aboard():
		_fire_cook += delta
		if _fire_cook > 6.0:
			_fire_cook = 0.0
			_blow(1.5, "The fire reached the dynamite.")
	else:
		_fire_cook = 0.0


## Hazardous loads (DESIGN_NOTES 173).
var _fire_cook := 0.0
func _explosives_aboard() -> bool:
	for j in carried:
		if bool(j.get("explosive", false)):
			for pc in j.get("pieces", []):
				if pc["at"] == "cabin" or pc["at"] == "bay":
					return true
	return false


func _blow(strength: float, why: String) -> void:
	for i in range(carried.size() - 1, -1, -1):
		if bool(carried[i].get("explosive", false)):
			carried.remove_at(i)
	_stow()
	save_career()
	changed.emit()
	detonated.emit(strength)
	warn.emit(why)


func on_landed(info: Dictionary) -> void:
	var sink_fpm := float(info["sink"]) * 196.85
	if _explosives_aboard():
		if sink_fpm > 700.0 and randf() < clampf((sink_fpm - 700.0) / 600.0, 0.25, 0.9):
			_blow(1.3, "Too hard with dynamite aboard.")
			return
		elif sink_fpm > 450.0:
			warn.emit("Easy! The dynamite cases jumped in their straps.")
	for j in carried:
		if sink_fpm > 420.0:
			j["hard_landings"] = int(j["hard_landings"]) + 1
			if bool(j["fragile"]):
				j["condition"] = maxf(float(j["condition"]) - clampf((sink_fpm - 420.0) / 900.0, 0.05, 0.4), 0.0)


func on_damage(severity: float) -> void:
	if severity > 0.3 and _explosives_aboard() and randf() < severity:
		_blow(1.2, "The hit set the dynamite off.")
		return
	for j in carried:
		var hit := clampf(severity * (0.5 if bool(j["fragile"]) else 0.25), 0.0, 0.6)
		j["condition"] = maxf(float(j["condition"]) - hit, 0.0)


## A crash (DESIGN_NOTES 79): the load takes a beating, fragile things worse.
## Anything left under 15% is destroyed; the rest stays in the wreck to be
## pulled out and taken on by truck or another plane. Passengers are shaken
## but fine and walk away (their trip is over). Pieces already out of the
## plane (on the ground, in the pickup) aren't touched.
var salvage_note := ""
func on_crashed() -> void:
	if carried.is_empty():
		return
	if _explosives_aboard():
		_blow(1.6, "The dynamite went up with the crash.")
	var lost: Array[String] = []
	var kept := 0
	for i in range(carried.size() - 1, -1, -1):
		var j: Dictionary = carried[i]
		if int(j.get("pax", 0)) > 0 or not j.has("pieces"):
			carried.remove_at(i)
			continue
		var aboard := false
		for pc in j["pieces"]:
			if pc["at"] == "cabin" or pc["at"] == "bay" or pc["at"] == "hands":
				aboard = true
		if not aboard:
			continue
		var hit := randf_range(0.15, 0.5) * (1.6 if bool(j["fragile"]) else 1.0)
		j["condition"] = maxf(float(j["condition"]) - hit, 0.0)
		if float(j["condition"]) < 0.15:
			lost.append(String(j["title"]))
			carried.remove_at(i)
		else:
			kept += 1
	salvage_note = ""
	if kept > 0:
		salvage_note = "%d load%s survived in the wreck - pull %s out and truck %s on." % [kept, "" if kept == 1 else "s", "it" if kept == 1 else "them", "it" if kept == 1 else "them"]
	if not lost.is_empty():
		salvage_note += ("  " if salvage_note != "" else "") + "Destroyed: %s." % ", ".join(lost)
	_stow()
	save_career()
	changed.emit()


## The destination of the first job on board, or -1.
func next_destination() -> int:
	return int(carried[0]["to"]) if not carried.is_empty() else -1


## One line for the screen about what is on board.
func status_line() -> String:
	if carried.is_empty():
		return ""
	var j: Dictionary = carried[0]
	var s := "%s to %s, %d kg" % [j["title"], terrain.strips[int(j["to"])]["name"], int(carried_kg())]
	if String(j["kind"]) == "skydive":
		s = "Skydivers: climb to %d ft above the drop zone by %s, then %s for the green light" % [int(j["alt_ft"]), terrain.strips[int(j["to"])]["name"], Game.hint("jobs")]
	if carried.size() > 1:
		s += "  (+%d more)" % (carried.size() - 1)
	if bool(j["urgent"]):
		var left := float(j["limit_min"]) - float(j["minutes"])
		s += "  %s" % ("%d min left" % int(ceil(left)) if left > 0.0 else "LATE")
	return s


# ------------------------------------------------------------------------------
#  Saving
# ------------------------------------------------------------------------------
func save_career() -> void:
	var cf := ConfigFile.new()
	cf.set_value("career", "money", money)
	cf.set_value("career", "completed", completed)
	cf.set_value("career", "epoch", _epoch)
	cf.set_value("career", "next_id", _next_id)
	cf.set_value("career", "carried", carried)
	cf.set_value("career", "rep", rep)
	cf.set_value("career", "contracts", contracts)
	cf.set_value("career", "dc3_gift", true)
	cf.set_value("career", "spares", spares)
	cf.save(SAVE)


func load_career() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	money = int(cf.get_value("career", "money", START_MONEY))
	completed = int(cf.get_value("career", "completed", 0))
	_epoch = int(cf.get_value("career", "epoch", 0))
	_next_id = int(cf.get_value("career", "next_id", 1))
	carried = cf.get_value("career", "carried", [])
	var r = cf.get_value("career", "rep", {})
	rep = r if r is Dictionary else {}
	# One-off: money to try the DC-3 with (October 2026 test build).
	if not cf.has_section_key("career", "dc3_gift"):
		money += 100000
		cf.set_value("career", "dc3_gift", true)
		cf.save(SAVE)
	var sp = cf.get_value("career", "spares", {})
	spares = sp if sp is Dictionary else {}
	var cs = cf.get_value("career", "contracts", [])
	contracts = cs if cs is Array else []
	for j in carried:
		if not j.has("pieces"):
			var n: int = maxi(int(j.get("n", 1)), 1)
			var pieces: Array = []
			for i in range(n):
				pieces.append({"kg": float(j["kg"]) / float(n), "at": "cabin", "strip": -1, "pos": Vector3.ZERO})
			j["pieces"] = pieces
			j["by_hand"] = false
		for pc in j["pieces"]:
			if pc["at"] == "hands":
				pc["at"] = "cabin"     # you were holding it when the game closed
			elif pc["at"] == "forks":
				pc["at"] = "ramp"      # it was on a forklift: back on the ramp


## After the plane has been placed (start of a flight), put the saved loads back on board.
func restow() -> void:
	if plane != null:
		_stow()
