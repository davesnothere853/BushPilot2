extends Node
## Mining, Out of Ore style but small to start: buy a claim beside a bush
## strip, work it, and fly the concentrate out to the assay office in Port
## Ashby, where it is bought by weight. Better gear (a sluice, then a little
## excavator) makes more per hour; more makes bigger planes worth having.
##
## A claim keeps producing while you are away. The sacks it has filled show up
## on the claim's job board as a load to fly out (by hand or loaded for you).

const SAVE := "user://mining.cfg"
const SACK_KG := 25.0
const PRICE_PER_KG := 9            # what the assay office pays, $ per kg of concentrate
## Claims beside strips: strip name, claim name, price.
const CLAIMS := [
	["Proving Ground", "Proving Ground Claim", 0],
]
## Gear: name, price, kg of concentrate an hour of play.
const GEAR := [
	["Shovel and gold pan", 0, 40.0],
	["Sluice box", 3000, 150.0],
	["Small excavator", 15000, 500.0],
]

var jobs: Node
var terrain: RefCounted
var builds: Node                  # builds.gd: a camp at a claim works it faster
var claims: Dictionary = {}       # claim name -> {owned, gear, stock_kg}
var _save_t := 0.0

func _ready() -> void:
	load_mines()


func claim_at(k: int) -> Array:
	if k < 0:
		return []
	for c in CLAIMS:
		if c[0] == String(terrain.strips[k]["name"]):
			return c
	return []


func state(name: String) -> Dictionary:
	if not claims.has(name):
		claims[name] = {"owned": name == "Proving Ground Claim", "gear": 0, "stock_kg": 0.0}
	return claims[name]


func buy_claim(name: String, price: int) -> String:
	if jobs.money < price:
		return "You need $%d." % price
	jobs.money -= price
	state(name)["owned"] = true
	_save()
	return ""


func upgrade(name: String) -> String:
	var st := state(name)
	var g: int = st["gear"]
	if g >= GEAR.size() - 1:
		return "Already the best gear."
	var price: int = GEAR[g + 1][1]
	if jobs.money < price:
		return "You need $%d." % price
	jobs.money -= price
	st["gear"] = g + 1
	_save()
	return ""


## Work your claims: they fill sacks as time passes.
func _process(delta: float) -> void:
	for c in CLAIMS:
		var st := state(c[1])
		if bool(st["owned"]):
			var rate: float = GEAR[int(st["gear"])][2]
			if builds != null and builds.has_camp(c[1]):
				rate *= 1.5
			st["stock_kg"] = minf(float(st["stock_kg"]) + rate * delta / 3600.0, 1000.0)
	_save_t += delta
	if _save_t > 30.0:
		_save_t = 0.0
		_save()



## Put the full sacks on the ramp as a job to fly to the assay office.
func ship(k: int, by_hand: bool) -> String:
	var c := claim_at(k)
	if c.is_empty():
		return "No claim here."
	var st := state(c[1])
	var sacks := int(floor(float(st["stock_kg"]) / SACK_KG))
	if sacks <= 0:
		return "Nothing ready yet. Come back later."
	var r: Dictionary = jobs.room()
	sacks = mini(sacks, int(floor((float(r["front"]) + float(r["rear"])) / SACK_KG)))
	sacks = mini(sacks, int(floor(float(r["weight"]) / SACK_KG)))
	if sacks <= 0:
		return "No room on board for even one sack."
	var kg := float(sacks) * SACK_KG
	var to := _assay_strip()
	if to == k:
		# the assay office is right here: weigh it in and get paid
		var pay := int(kg * PRICE_PER_KG)
		jobs.money += pay
		st["stock_kg"] = float(st["stock_kg"]) - kg
		_save()
		return "Weighed in at the assay office: %d sacks, $%d." % [sacks, pay]
	var job := {"id": 880000 + randi() % 100000, "kind": "ore", "title": "Gold concentrate", "from": k, "to": to,
		"what": "%d sacks of concentrate from %s" % [sacks, c[1]], "kg": kg, "pay": int(kg * PRICE_PER_KG),
		"fragile": false, "urgent": false, "limit_min": 0.0, "pax": 0, "n": sacks}
	if not jobs.take_custom(job, by_hand):
		return "Couldn't load it."
	st["stock_kg"] = float(st["stock_kg"]) - kg
	_save()
	return ""


func _assay_strip() -> int:
	for k in range(terrain.strips.size()):
		if String(terrain.strips[k]["name"]) == "Proving Ground":
			return k
	return 0


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("mining", "claims", claims)
	cf.save(SAVE)


func load_mines() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	var c = cf.get_value("mining", "claims", {})
	claims = c if c is Dictionary else {}
