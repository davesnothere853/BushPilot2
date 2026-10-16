extends Node
## Damage for every machine on the ground (DESIGN_NOTES 137): the pickup, the
## water and fuel trucks, the loader, the tug, the log trailer, forklifts,
## dozers and excavators. Planes have their own (plane.gd).
##
## Three numbers each, 1 = new: engine (pull, smoke, and a wrecked one won't
## run), body, and running gear (wheels, tracks, suspension, steering: a bent
## one pulls to a side and won't go as fast). Hits are read off how fast the
## machine's own velocity changes - a hard stop against a building, a drop
## off a bank, a roll - so it works the same for every kind of body.
## Repairs at the workshop (menu, Workshop page). Saved in vehicle_damage.cfg.

const SAVE := "user://vehicle_damage.cfg"
const Fx = preload("res://scripts/fx.gd")

const HIT_DV := 5.0          # m/s of velocity change inside ~0.1 s before it hurts
const HIT_SPAN := 10.0       # m/s above that for a full-strength hit

var vehicles: Callable       # () -> Array of [key, name, Node3D]
var notice: Callable         # (text)
var watching: Callable       # () -> Node3D the player is driving or standing by (who hears about hits)
var burning: Callable        # (Vector3) -> bool: fire.gd burning_at - a grass fire under it scorches it

var state := {}              # key -> {"engine", "body", "gear"}

# --- fire (DESIGN_NOTES 142): a machine alight burns toward going up; the
# water truck's spray puts it out. Not saved: a fire is now or never.
const FUSE := 40.0           # seconds from catching to the tanks going up (a fuel truck: less)
var on_explode: Callable     # func(key, node, strength) - main blows it up (explosions.gd)
var ground_fire: Callable    # func(at, r) - fire.gd ignite: it lights what's under it
var fires := {}              # key -> {"heat", "t", "fuse", "node", "told"}
var _fire_nodes := {}
var _track := {}             # key -> per-machine motion history
var _smoke := {}             # key -> CPUParticles3D
var _dirty := false
var _save_t := 0.0


func _ready() -> void:
	_load()


func get_d(key: String) -> Dictionary:
	if not state.has(key):
		state[key] = {"engine": 1.0, "body": 1.0, "gear": 1.0}
	return state[key]


## How much of its power the engine still makes (0 = wrecked, won't run).
func power_k(key: String) -> float:
	var e := float(get_d(key)["engine"])
	return 0.0 if e <= 0.05 else lerpf(0.4, 1.0, e)


func dead(key: String) -> bool:
	return float(get_d(key)["engine"]) <= 0.05


## Bent running gear: top speed falls off, and it pulls to one side.
func speed_k(key: String) -> float:
	return lerpf(0.55, 1.0, float(get_d(key)["gear"]))


func pull(key: String) -> float:
	var side := 1.0 if (hash(key) & 1) == 0 else -1.0
	return (1.0 - float(get_d(key)["gear"])) * 0.3 * side


func damaged(key: String) -> bool:
	var d := get_d(key)
	return float(d["engine"]) < 0.98 or float(d["body"]) < 0.98 or float(d["gear"]) < 0.98


func status(key: String) -> String:
	var d := get_d(key)
	return "engine %d%%, body %d%%, wheels %d%%" % [int(float(d["engine"]) * 100.0), int(float(d["body"]) * 100.0), int(float(d["gear"]) * 100.0)]


## The shop's price to put it right; big machines cost more.
func repair_cost(key: String) -> int:
	var d := get_d(key)
	var missing := (1.0 - float(d["engine"])) * 1.4 + (1.0 - float(d["body"])) + (1.0 - float(d["gear"])) * 0.8
	var size := 1.0
	for big in ["water", "fuel", "loader", "dozer", "excavator"]:
		if key.begins_with(big):
			size = 3.0
	if key == "log_trailer" or key == "tug" or key.begins_with("forklift"):
		size = 0.6
	return int(round(missing * 1500.0 * size / 10.0)) * 10


var on_repaired: Callable    # func(key) - main takes the burnt look off
func repair(key: String) -> void:
	_put_out(key)
	state[key] = {"engine": 1.0, "body": 1.0, "gear": 1.0}
	if on_repaired.is_valid():
		on_repaired.call(key)
	_dirty = true
	save()


## A hit by hand (the console, a falling tree, a fire): each part loses this much.
func hurt(key: String, engine: float, body: float, gear: float) -> void:
	var d := get_d(key)
	d["engine"] = clampf(float(d["engine"]) - engine, 0.0, 1.0)
	d["body"] = clampf(float(d["body"]) - body, 0.0, 1.0)
	d["gear"] = clampf(float(d["gear"]) - gear, 0.0, 1.0)
	_dirty = true


func _physics_process(delta: float) -> void:
	if delta <= 0.0 or not vehicles.is_valid():
		return
	var who: Node3D = watching.call() if watching.is_valid() else null
	for e in vehicles.call():
		var key: String = e[0]
		var n: Node3D = e[2]
		if n == null or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		_watch(key, String(e[1]), n, delta, n == who)
		_fire_step(key, String(e[1]), n, delta, n == who)
		_smoke_step(key, n)
	_save_t += delta
	if _dirty and _save_t > 3.0:
		_save_t = 0.0
		save()


func _watch(key: String, vname: String, n: Node3D, delta: float, told: bool) -> void:
	var p := n.global_position
	var tr: Dictionary = _track.get(key, {})
	if tr.is_empty():
		_track[key] = {"p": p, "fast": Vector3.ZERO, "slow": Vector3.ZERO, "settle": 3.0, "cool": 0.0, "upside": 0.0, "rolled": false}
		return
	var v := (p - (tr["p"] as Vector3)) / delta
	tr["p"] = p
	if v.length() > 60.0:
		tr["settle"] = 3.0          # teleported (parked, brought, respawned)
	if float(tr["settle"]) > 0.0:
		# just appeared or moved by hand: it drops onto its spot, that's no crash
		tr["settle"] = float(tr["settle"]) - delta
		tr["fast"] = v if v.length() < 60.0 else Vector3.ZERO
		tr["slow"] = tr["fast"]
		return
	# a quick and a slow follow of its velocity: on a hard stop the quick one
	# drops at once and the slow one lags - the gap is the hit
	var fast: Vector3 = (tr["fast"] as Vector3).lerp(v, clampf(delta / 0.03, 0.0, 1.0))
	var slow: Vector3 = (tr["slow"] as Vector3).lerp(v, clampf(delta / 0.12, 0.0, 1.0))
	tr["fast"] = fast
	tr["slow"] = slow
	tr["cool"] = maxf(float(tr["cool"]) - delta, 0.0)
	var dv := fast - slow
	if dv.length() > HIT_DV and float(tr["cool"]) <= 0.0:
		tr["cool"] = 0.5
		var sev := clampf((dv.length() - HIT_DV) / HIT_SPAN, 0.0, 1.2)
		var flat := Vector2(dv.x, dv.z).length()
		if flat >= absf(dv.y):
			hurt(key, sev * 0.45, sev * 0.6, sev * 0.2)      # into something: the front end takes it
		else:
			hurt(key, sev * 0.1, sev * 0.3, sev * 0.6)       # dropped: springs, axles, wheels
		if sev > 0.8 and randf() < 0.35:
			set_on_fire(key, vname, 0.5)                    # a split line, sparks
		if told and notice.is_valid():
			notice.call("%s! The %s took a hard hit: %s." % ["Crunch" if sev > 0.4 else "Bang", vname, status(key)])
	# over on its side or roof
	var up := n.global_transform.basis.y.normalized().y
	if up < 0.3:
		tr["upside"] = float(tr["upside"]) + delta
		if float(tr["upside"]) > 1.5 and not bool(tr["rolled"]):
			tr["rolled"] = true
			hurt(key, 0.2, 0.4, 0.15)
			if n.get("engine_on") == true and randf() < 0.25:
				set_on_fire(key, vname, 0.4)                # fuel on the hot exhaust
			if n.get("engine_on") == true:
				n.set("engine_on", false)
			if told and notice.is_valid():
				notice.call("The %s rolled over: %s." % [vname, status(key)])
	else:
		tr["upside"] = 0.0
		tr["rolled"] = false


## Parked or driven through a burning patch: paint, tyres, hoses and wiring
## go, and before long the machine itself catches.
var _fire_told := {}
func _fire_step(key: String, vname: String, n: Node3D, delta: float, told: bool) -> void:
	_burn_step(key, vname, n, delta)
	if not burning.is_valid() or not burning.call(n.global_position):
		return
	hurt(key, 0.03 * delta, 0.05 * delta, 0.04 * delta)
	if not fires.has(key) and randf() < 0.12 * delta:
		set_on_fire(key, vname, 0.4)
	var t := Time.get_ticks_msec() / 1000.0
	if told and notice.is_valid() and t - float(_fire_told.get(key, -100.0)) > 8.0:
		_fire_told[key] = t
		notice.call("The %s is in the fire! Get it out of there: %s." % [vname, status(key)])


## The machine itself alight.
func set_on_fire(key: String, vname: String, heat: float = 0.5) -> void:
	if fires.has(key) or bool(get_d(key).get("blown", false)):
		return
	var fuse := FUSE * (0.6 if key.begins_with("fuel") else 1.0) * randf_range(0.85, 1.15)
	fires[key] = {"heat": heat, "t": 0.0, "fuse": fuse, "name": vname, "told": 0}
	if notice.is_valid():
		notice.call("The %s is on fire! Put it out with the water truck's sprays, or get well clear - it'll go up." % vname)


func on_fire(key: String) -> bool:
	return fires.has(key)


## Water on it (the water truck's sprays, fire.douse's caller): knocks the fire
## back; enough and it's out.
func douse(p: Vector3, r: float) -> void:
	if not vehicles.is_valid():
		return
	for e in vehicles.call():
		var key: String = e[0]
		if not fires.has(key):
			continue
		var n: Node3D = e[2]
		if n != null and n.global_position.distance_to(p) < r + 3.0:
			var f: Dictionary = fires[key]
			f["heat"] = float(f["heat"]) - 0.12
			f["t"] = maxf(float(f["t"]) - 1.5, 0.0)     # cooling it buys time
			if float(f["heat"]) <= 0.0:
				_put_out(key)
				if notice.is_valid():
					notice.call("The fire on the %s is out." % String(e[1]))


func _put_out(key: String) -> void:
	fires.erase(key)
	var fn: Node3D = _fire_nodes.get(key)
	if fn != null and is_instance_valid(fn):
		fn.queue_free()
	_fire_nodes.erase(key)


func _burn_step(key: String, vname: String, n: Node3D, delta: float) -> void:
	if not fires.has(key):
		return
	var f: Dictionary = fires[key]
	f["heat"] = minf(float(f["heat"]) + 0.03 * delta, 1.0)
	f["t"] = float(f["t"]) + delta
	var heat := float(f["heat"])
	hurt(key, 0.02 * heat * delta, 0.03 * heat * delta, 0.015 * heat * delta)
	if n.get("engine_on") == true and float(get_d(key)["engine"]) < 0.3:
		n.set("engine_on", false)
	var fn: Node3D = _fire_nodes.get(key)
	if fn == null or not is_instance_valid(fn):
		fn = Fx.make_fire()
		n.add_child(fn)
		fn.position = Vector3(0, 1.0, -0.8)
		_fire_nodes[key] = fn
	Fx.set_fire_strength(fn, 0.25 + 0.75 * heat, Vector3.ZERO, float(f["t"]))
	# it lights the ground round it
	if ground_fire.is_valid() and fmod(float(f["t"]), 4.0) < delta:
		ground_fire.call(n.global_position, 3.0)
	var left := float(f["fuse"]) - float(f["t"])
	if left < 10.0 and int(f["told"]) == 0:
		f["told"] = 1
		if notice.is_valid():
			notice.call("The %s is about to go up! GET CLEAR!" % vname)
	if left <= 0.0:
		_put_out(key)
		var d := get_d(key)
		d["engine"] = 0.0
		d["body"] = 0.0
		d["gear"] = 0.0
		d["blown"] = true
		_dirty = true
		if on_explode.is_valid():
			on_explode.call(key, n)


## Grey smoke from a hurt engine, black from a dying one, while it runs.
func _smoke_step(key: String, n: Node3D) -> void:
	var e := float(get_d(key)["engine"])
	var running: bool = n.get("engine_on") == true or (n.get("engine_on") == null and n.get("driven") == true)
	var want := e < 0.55 and running
	var sm: CPUParticles3D = _smoke.get(key)
	if want and sm == null:
		sm = Fx.particles(Fx.smoke_material(), 24, 3.0, 0.9,
			Fx.gradient([[0.0, Color(0.2, 0.2, 0.2, 0.0)], [0.1, Color(0.25, 0.25, 0.25, 0.6)], [1.0, Color(0.5, 0.5, 0.5, 0.0)]]), 3.0)
		sm.direction = Vector3.UP
		sm.spread = 15.0
		sm.initial_velocity_min = 1.0
		sm.initial_velocity_max = 2.0
		sm.gravity = Vector3(0, 0.8, 0)
		n.add_child(sm)
		sm.position = Vector3(0, 1.6, -1.6)
		_smoke[key] = sm
	if sm != null and is_instance_valid(sm):
		sm.emitting = want
		var k := clampf((0.55 - e) / 0.5, 0.0, 1.0)
		if want and absf(k - float(sm.get_meta("k", -1.0))) > 0.05:
			sm.set_meta("k", k)
			sm.color_ramp = Fx.gradient([[0.0, Color(0.2, 0.2, 0.2, 0.0)], [0.1, Color(0.3 - 0.25 * k, 0.3 - 0.25 * k, 0.3 - 0.25 * k, 0.4 + 0.4 * k)], [1.0, Color(0.5, 0.5, 0.5, 0.0)]])


func save() -> void:
	_dirty = false
	var cf := ConfigFile.new()
	for k in state:
		cf.set_value("d", String(k), state[k])
	cf.save(SAVE)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	for k in cf.get_section_keys("d"):
		var d = cf.get_value("d", k, {})
		if d is Dictionary:
			state[k] = {"engine": float(d.get("engine", 1.0)), "body": float(d.get("body", 1.0)), "gear": float(d.get("gear", 1.0)), "blown": bool(d.get("blown", false))}
