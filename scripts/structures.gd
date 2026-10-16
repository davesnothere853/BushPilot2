extends Node3D
## The buildings standing in the world (DESIGN_NOTES 147): the home base's
## log office and bunkhouse cabin, the steel pole-barn shop, the little cabin
## in the woods, and the outbuildings round them (outhouse, cache, woodpiles,
## drums, propane). Built in the bush style: round-log walls and pole-barn
## steel, all under steel roofs (building_models.gd).
##
## Each one here can burn:
##  - it catches from a grass fire reaching its walls, a burning brand from an
##    explosion landing on it, a stove left roaring, or the console's "burn";
##  - the fire grows over a minute or two - smoke from the eaves first, then
##    flames out of the windows and through the roof - lighting the grass
##    round it, and you can put it out with the water truck's hose while it's
##    young;
##  - left to burn it goes black and comes down: a charred floor, the stove
##    and its pipe still standing, the roof sheets fallen in; walls, doors
##    and furniture gone (you can walk through it). Saved.
##
## And the wood stoves inside the log buildings work: fill the wood box from
## the woodpile outside, load the stove and light it. A lit stove glows
## through its door window, ticks and crackles, lights the room, warms you
## up while you're inside, and puts smoke out of the pipe on the roof -
## drifting off downwind. A load burns about 25 minutes.

const Models = preload("res://scripts/building_models.gd")
const MeshKit = preload("res://scripts/meshkit.gd")
const Fx = preload("res://scripts/fx.gd")

const SAVE := "user://structures.cfg"
const LOAD_S := 1500.0              # a load of wood burns this long
const BOX_LOADS := 6                # the wood box holds this many loads
const ARMFUL := 3                   # loads you carry in from the woodpile at a time

var terrain: RefCounted
var fire: Node                      # fire.gd (grass and brush)
var wind: Node
var walker: Node3D
var hud: Control
var douse_hit: Callable             # (unused hook for the hose)

## id -> {kind, node, xf, size (footprint, base-centred), solids: [dict], hollows: [dict],
##        platforms: [dict], stove: {} | {at, top, lit, fuel, box}, burn, heat, lit, burnt,
##        fires: [Node3D], smoke: CPUParticles3D, glow: OmniLight3D, flame_pts: [Vector3]}
var items := {}
var lanterns: Array = []            # [switch Vector3, lamp Vector3, fixture Transform3D] for building_lights
var prompt := ""
var carrying_wood := 0              # loads of firewood in your arms
var _target := ""                   # "stove:<id>" | "pile:<id>"
var _t := 0.0
var _check_t := 0.0
var _save_t := 0.0
var _dirty := false
var _saved := {}
var _ember_mat: StandardMaterial3D


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		for id in cf.get_sections():
			var d := {}
			for k in cf.get_section_keys(id):
				d[k] = cf.get_value(id, k)
			_saved[id] = d
	_ember_mat = StandardMaterial3D.new()
	_ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ember_mat.albedo_color = Color(1.0, 0.45, 0.12)


# ==============================================================================
#  Building them
# ==============================================================================
## Put up a building. kinds: "cabin" (7 x 6 log), "office" (10 x 8 log, the
## home base office), "loghouse" (10 x 8 log home), "polebarn" (12 x 18 steel
## shop), "poleshed" (open-front steel shed), "outhouse", "cache",
## "woodpile", "drums", "propane". Returns the id.
func add(id: String, kind: String, xf: Transform3D, opts: Dictionary = {}) -> String:
	var kit := MeshKit.new()
	var sol: Array = []
	var foot := Vector3.ONE
	var hollow := Vector3.ZERO
	var door_w := 0.0
	var stove := {}
	var lantern := Vector3.ZERO
	var flame_pts: Array = []
	match kind:
		"cabin":
			var r: Dictionary = Models.log_building(kit, 7.0, 6.0, 9, 1.8, {
				"front": [[0.0, 1.3, 0, 6], [-2.0, 1.0, 3, 6]],
				"back": [[1.6, 1.0, 3, 6]],
				"left": [[0.0, 1.0, 3, 5]],
				"right": [[-1.4, 0.8, 3, 5]],
			}, int(opts.get("seed", 11)), false)
			sol = r["solids"]
			sol += Models.cabin_furniture(kit, 7.0, 6.0, float(r["eave"]), float(r["ridge"]), true)
			foot = Vector3(7.8, float(r["ridge"]), 6.8)
			hollow = Vector3(7.0, 2.7, 6.0)
			door_w = 1.3
			stove = {"at": Models.stove_spot(7.0, 6.0), "top": Models.pipe_top(7.0, 6.0, float(r["eave"]))}
			lantern = Vector3(0, float(r["eave"]) - 0.63, 0.3)
			flame_pts = [Vector3(-2.0, 1.4, -3.0), Vector3(1.6, 1.4, 3.0), Vector3(0, float(r["ridge"]), 0), Vector3(-2.5, 2.6, 0), Vector3(2.5, 2.6, 0)]
		"office", "loghouse":
			var r2: Dictionary = Models.log_building(kit, 10.0, 8.0, 10, 2.4, {
				"front": [[0.0, 1.3, 0, 6], [-2.6, 1.3, 3, 7], [2.6, 1.3, 3, 7]],
				"back": [[-2.5, 1.1, 3, 7], [2.5, 1.1, 3, 7]],
				"left": [[-1.5, 1.1, 3, 6], [1.8, 1.1, 3, 6]],
				"right": [[2.0, 0.9, 3, 6]],
			}, int(opts.get("seed", 23)), kind == "loghouse")
			sol = r2["solids"]
			sol += Models.cabin_furniture(kit, 10.0, 8.0, float(r2["eave"]), float(r2["ridge"]), true, kind == "office")
			foot = Vector3(10.8, float(r2["ridge"]), 8.8)
			hollow = Vector3(10.0, 3.0, 8.0)
			door_w = 1.3
			stove = {"at": Models.stove_spot(10.0, 8.0), "top": Models.pipe_top(10.0, 8.0, float(r2["eave"]))}
			lantern = Vector3(0, float(r2["eave"]) - 0.63, 0.3)
			flame_pts = [Vector3(-2.6, 1.6, -4.0), Vector3(2.6, 1.6, -4.0), Vector3(-2.5, 1.6, 4.0), Vector3(0, float(r2["ridge"]), -1.5), Vector3(0, float(r2["ridge"]), 1.5), Vector3(-5.0, 2.5, 0.0)]
			if kind == "office":
				_sign(kit, Vector3(0, float(r2["eave"]) + 0.15, -4.0 - 2.4 - 0.1), String(opts.get("sign", "OFFICE")))
		"polebarn":
			var pal: Dictionary = opts.get("palette", {"wall": Color(0.62, 0.16, 0.12), "wainscot": Color(0.22, 0.22, 0.22),
				"trim": Color(0.92, 0.92, 0.88), "roof": Color(0.66, 0.68, 0.69)})
			var r3: Dictionary = Models.pole_barn(kit, 12.0, 18.0, 4.8, 6.0, 4.2, pal)
			sol = r3["solids"]
			foot = Vector3(12.6, 7.0, 18.6)
			hollow = Vector3(12.0, 4.8, 18.0)
			door_w = 6.0
			flame_pts = [Vector3(-3, 5.5, -5), Vector3(3, 5.5, 4), Vector3(0, 6.3, 0), Vector3(-5.5, 2.5, 6)]
		"poleshed":
			var pal2: Dictionary = opts.get("palette", {"wall": Color(0.70, 0.72, 0.72), "wainscot": Color(0.24, 0.36, 0.27),
				"trim": Color(0.24, 0.36, 0.27), "roof": Color(0.66, 0.68, 0.69)})
			var r4: Dictionary = Models.pole_shed(kit, 12.0, 8.0, 4.4, 3.4, pal2)
			sol = r4["solids"]
			foot = Vector3(12.6, 4.6, 8.6)
			hollow = Vector3(12.0, 4.4, 8.0)
			door_w = 12.0
			flame_pts = [Vector3(-3, 4.0, 0), Vector3(3, 4.0, 1), Vector3(0, 3.5, 3)]
		"outhouse":
			sol = _local(Models.outhouse(kit, Vector3.ZERO, 0.0))
			foot = Vector3(1.4, 2.2, 1.4)
			flame_pts = [Vector3(0, 1.4, 0)]
		"cache":
			sol = _local(Models.cache(kit, Vector3.ZERO, 0.0))
			foot = Vector3(2.4, 5.0, 2.4)
			flame_pts = [Vector3(0, 3.8, 0)]
		"woodpile":
			var ln := float(opts.get("len", 3.0))
			sol = _local(Models.woodpile(kit, Vector3.ZERO, 0.0, ln, int(opts.get("seed", 3))))
			foot = Vector3(ln + 0.4, 1.5, 0.8)
			flame_pts = [Vector3(0, 0.9, 0)]
		"drums":
			sol = _local(Models.drums(kit, Vector3.ZERO, 0.0, int(opts.get("n", 5)), int(opts.get("seed", 1))))
			foot = Vector3(2.0, 0.9, 1.4)
			flame_pts = [Vector3(0, 1.0, 0.3)]
		"propane":
			sol = _local(Models.propane(kit, Vector3.ZERO, 0.0))
			foot = Vector3(1.9, 1.2, 0.9)
			flame_pts = [Vector3(0, 1.0, 0)]
	if kind in ["cabin", "office", "loghouse"]:
		Models.chopping_block(kit, Vector3(-2.2 if kind == "cabin" else -3.4, 0.0, -(foot.z * 0.5) - 3.2))
	if terrain.has_method("pad"):
		var big: bool = kind in ["cabin", "office", "loghouse", "polebarn", "poleshed"]
		terrain.pad(xf, foot.x, foot.z, 1.2 if big else 0.3, 2.5 if big else 1.2)
	var mi := kit.instance("Structure_" + id)
	mi.transform = xf
	add_child(mi)
	terrain.clear_spot(xf.origin.x, xf.origin.z, Vector2(foot.x, foot.z).length() * 0.5 + 2.5)
	var it := {"kind": kind, "node": mi, "xf": xf, "size": foot, "solids": [], "hollows": [], "platforms": [],
		"stove": stove, "burn": 0.0, "heat": 0.0, "lit": false, "burnt": false, "fires": [], "flame_pts": flame_pts}
	if hollow != Vector3.ZERO:
		terrain.add_hollow(xf, hollow, door_w)
		(it["hollows"] as Array).append(terrain.hollows[terrain.hollows.size() - 1])
	else:
		terrain.add_solid(xf, foot)
		(it["solids"] as Array).append(terrain.solids[terrain.solids.size() - 1])
	for so in sol:
		terrain.add_solid(xf * Transform3D(Basis.IDENTITY, so[0] as Vector3), so[1])
		(it["solids"] as Array).append(terrain.solids[terrain.solids.size() - 1])
	if lantern != Vector3.ZERO:
		lanterns.append([xf * lantern, xf * Transform3D(Basis.IDENTITY, lantern)])
	if not stove.is_empty():
		stove["lit"] = bool(opts.get("stove_lit", false))
		stove["fuel"] = LOAD_S * float(opts.get("loads", 1.5)) if stove["lit"] else 0.0
		stove["box"] = int(opts.get("box", 3))
		_stove_nodes(it)
	items[id] = it
	_restore(id)
	return id


## Props' solids come back as [world pos, size, yaw]; here they're built at the
## origin, so just the box.
func _local(a: Array) -> Array:
	var out: Array = []
	for s in a:
		out.append([Vector3.ZERO, s[1]])
	return out


## A painted board over the porch, lettered.
func _sign(kit: MeshKit, at: Vector3, text: String) -> void:
	kit.box_at(at, Vector3(2.6, 0.55, 0.06), Color(0.86, 0.82, 0.70))
	kit.box_at(at + Vector3(0, 0, 0.01), Vector3(2.75, 0.68, 0.04), Color(0.30, 0.20, 0.12))
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.pixel_size = 0.0045
	l.modulate = Color(0.22, 0.14, 0.08)
	l.outline_size = 0
	l.position = at + Vector3(0, 0, -0.045)
	l.rotation = Vector3(0, PI, 0)
	l.set_meta("sign", true)
	add_child(l)
	_pending_labels.append(l)


var _pending_labels: Array = []


# ==============================================================================
#  Stoves
# ==============================================================================
func _stove_nodes(it: Dictionary) -> void:
	var st: Dictionary = it["stove"]
	var xf: Transform3D = it["xf"]
	var at: Vector3 = st["at"]
	# the glow through the door window
	var gm := BoxMesh.new()
	gm.size = Vector3(0.26, 0.14, 0.012)
	var g := MeshInstance3D.new()
	g.mesh = gm
	g.material_override = _ember_mat
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.transform = xf * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.57, -0.42))
	add_child(g)
	st["ember"] = g
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.22)
	l.omni_range = 5.5
	l.shadow_enabled = true
	l.transform = xf * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.5, -0.9))
	add_child(l)
	st["light"] = l
	# crackle and tick
	var s: AudioStream = load("res://scripts/audio.gd")._file("res://assets/sounds/fx/fire.wav", true)
	if s != null:
		var p := AudioStreamPlayer3D.new()
		p.stream = s
		p.unit_size = 1.2
		p.max_distance = 14.0
		p.volume_db = -22.0
		p.pitch_scale = 1.25
		p.attenuation_filter_cutoff_hz = 2500.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.transform = xf * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.5, 0))
		add_child(p)
		st["sound"] = p
	# smoke from the pipe on the roof
	var sm := Fx.particles(Fx.smoke_material(), 40, 9.0, 0.7,
		Fx.gradient([[0.0, Color(0.55, 0.54, 0.52, 0.0)], [0.1, Color(0.50, 0.49, 0.48, 0.55)], [0.6, Color(0.70, 0.70, 0.70, 0.28)], [1.0, Color(0.85, 0.85, 0.86, 0.0)]]), 6.0)
	sm.direction = Vector3.UP
	sm.spread = 8.0
	sm.initial_velocity_min = 0.9
	sm.initial_velocity_max = 1.4
	sm.damping_min = 0.3
	sm.damping_max = 0.6
	sm.gravity = Vector3(0, 0.25, 0)
	sm.transform = xf * Transform3D(Basis.IDENTITY, st["top"] as Vector3 + Vector3(0, 0.15, 0))
	add_child(sm)
	st["smoke"] = sm
	_stove_show(st)


func _stove_show(st: Dictionary) -> void:
	var on := bool(st["lit"])
	(st["ember"] as MeshInstance3D).visible = on
	(st["light"] as OmniLight3D).visible = on
	(st["smoke"] as CPUParticles3D).emitting = on
	if st.has("sound"):
		var p: AudioStreamPlayer3D = st["sound"]
		if on and not p.playing:
			p.play()
		elif not on and p.playing:
			p.stop()


## The world point a walker stands at to work the stove.
func _stove_front(it: Dictionary) -> Vector3:
	return (it["xf"] as Transform3D) * ((it["stove"]["at"] as Vector3) + Vector3(0, 0, -1.0))


## The id of the building whose floor you're standing on, or "".
func inside(p: Vector3) -> String:
	for id in items:
		var it: Dictionary = items[id]
		if (it["hollows"] as Array).is_empty() or bool(it["burnt"]):
			continue
		var l: Vector3 = (it["xf"] as Transform3D).affine_inverse() * p
		var h: Dictionary = it["hollows"][0]
		var sz: Vector3 = h["size"]
		if absf(l.x) < sz.x * 0.5 and absf(l.z) < sz.z * 0.5 and l.y > -1.0 and l.y < sz.y + 1.0:
			return id
	return ""


func find_target() -> void:
	prompt = ""
	_target = ""
	if walker == null:
		return
	var p: Vector3 = walker.global_position
	var hint: String = Game.hint("interact")
	for id in items:
		var it: Dictionary = items[id]
		if bool(it["burnt"]):
			continue
		if not (it["stove"] as Dictionary).is_empty() and _stove_front(it).distance_to(p) < 1.15:
			var st: Dictionary = it["stove"]
			_target = "stove:" + id
			var box := int(st["box"])
			if carrying_wood > 0 and box < BOX_LOADS:
				prompt = "%s  Fill the wood box (%d loads in your arms)" % [hint, carrying_wood]
			elif bool(st["lit"]):
				var mins := int(float(st["fuel"]) / 60.0)
				prompt = ("%s  Put another load in the stove (%d left in the box)   burning, about %d min" % [hint, box, mins]) if box > 0 and float(st["fuel"]) < LOAD_S * 2.0 \
					else ("The stove's going, about %d min left%s" % [mins, "" if box > 0 else "   (the wood box is empty: fetch wood from the woodpile)"])
				if box <= 0 or float(st["fuel"]) >= LOAD_S * 2.0:
					_target = ""
			elif box > 0:
				prompt = "%s  Load the stove and light it (%d loads in the wood box)" % [hint, box]
			else:
				prompt = "The wood box is empty: fetch an armful from the woodpile outside."
				_target = ""
			return
		if String(it["kind"]) == "woodpile" and (it["xf"] as Transform3D).origin.distance_to(p) < 2.4:
			if carrying_wood < ARMFUL:
				_target = "pile:" + id
				prompt = "%s  Take an armful of firewood" % hint
			else:
				prompt = "Your arms are full of firewood: take it to a wood box by a stove."
			return


func interact() -> bool:
	if _target == "":
		return false
	var parts := _target.split(":")
	var id := parts[1]
	if not items.has(id):
		return false
	var it: Dictionary = items[id]
	if parts[0] == "pile":
		carrying_wood = ARMFUL
		_say("You load up an armful of split wood.")
		return true
	var st: Dictionary = it["stove"]
	if carrying_wood > 0 and int(st["box"]) < BOX_LOADS:
		var put := mini(carrying_wood, BOX_LOADS - int(st["box"]))
		st["box"] = int(st["box"]) + put
		carrying_wood -= put
		_say("You stack the wood in the box (%d loads)." % int(st["box"]))
	elif int(st["box"]) > 0:
		st["box"] = int(st["box"]) - 1
		st["fuel"] = float(st["fuel"]) + LOAD_S
		if not bool(st["lit"]):
			st["lit"] = true
			_say("Kindling, a match, then the splits on top. It catches and starts to tick as the stove warms.")
		else:
			_say("You open the door, rake the coals and lay another load on.")
		_stove_show(st)
	_dirty = true
	return true


func _say(t: String) -> void:
	if hud != null:
		hud.push_message(t, 4.0)


# ==============================================================================
#  Fire
# ==============================================================================
## Set a building alight (a brand, a grass fire at its walls, the console).
func set_on_fire(id: String, heat: float = 0.12) -> void:
	if not items.has(id):
		return
	var it: Dictionary = items[id]
	if bool(it["burnt"]) or bool(it["lit"]):
		return
	it["lit"] = true
	it["heat"] = maxf(float(it["heat"]), heat)
	_dirty = true


## Something burning came down at `at`: anything within r of its walls catches.
func ignite_near(at: Vector3, r: float) -> void:
	for id in items:
		if _dist_to(items[id], at) < r:
			set_on_fire(id)


## The hose on it: knocks the fire down; enough water puts it out.
func douse(at: Vector3, r: float) -> bool:
	var hit := false
	for id in items:
		var it: Dictionary = items[id]
		if bool(it["lit"]) and _dist_to(it, at) < r + 1.5:
			it["heat"] = float(it["heat"]) - 0.035
			hit = true
			if float(it["heat"]) <= 0.0:
				it["heat"] = 0.0
				it["lit"] = false
				_say("The fire in the %s is out." % _name(it))
				_dirty = true
	return hit


func burning_any() -> bool:
	for id in items:
		if bool(items[id]["lit"]):
			return true
	return false


## Distance from p to the building's footprint box (0 inside it).
func _dist_to(it: Dictionary, p: Vector3) -> float:
	var l: Vector3 = (it["xf"] as Transform3D).affine_inverse() * p
	var sz: Vector3 = it["size"]
	var dx := maxf(absf(l.x) - sz.x * 0.5, 0.0)
	var dz := maxf(absf(l.z) - sz.z * 0.5, 0.0)
	var dy := maxf(l.y - sz.y, 0.0) + maxf(-l.y - 1.0, 0.0)
	return sqrt(dx * dx + dy * dy + dz * dz)


func _name(it: Dictionary) -> String:
	return {"office": "office", "cabin": "cabin", "loghouse": "log house", "polebarn": "shop", "poleshed": "shed",
		"outhouse": "outhouse", "cache": "cache", "woodpile": "woodpile", "drums": "fuel drums", "propane": "propane tank"}.get(String(it["kind"]), "building")


## How long it takes to burn down at full heat (seconds).
func _burn_time(it: Dictionary) -> float:
	var sz: Vector3 = it["size"]
	return clampf(sz.x * sz.z * 4.0, 90.0, 600.0)


func _process(delta: float) -> void:
	_t += delta
	var wv := Vector3.ZERO
	if wind != null and wind.has_method("sample") and walker != null:
		wv = wind.sample(walker.global_position + Vector3(0, 6, 0))
	for id in items:
		var it: Dictionary = items[id]
		var st: Dictionary = it["stove"]
		if not st.is_empty() and bool(st["lit"]):
			st["fuel"] = float(st["fuel"]) - delta
			var sm: CPUParticles3D = st["smoke"]
			sm.gravity = Vector3(wv.x * 0.45, 0.3, wv.z * 0.45)
			var lt: OmniLight3D = st["light"]
			var k := clampf(float(st["fuel"]) / 300.0, 0.25, 1.0)
			lt.light_energy = (0.9 + 0.25 * sin(_t * 9.0) * sin(_t * 3.7 + float(id.length()))) * k
			if float(st["fuel"]) <= 0.0:
				st["fuel"] = 0.0
				st["lit"] = false
				_stove_show(st)
				_dirty = true
		if bool(it["lit"]):
			_burn_step(id, it, delta, wv)
	# warm by a lit stove
	if walker != null and walker.visible:
		var inn := inside(walker.global_position)
		if inn != "":
			var st2: Dictionary = items[inn]["stove"]
			if not st2.is_empty() and bool(st2["lit"]):
				walker.warmth = minf(float(walker.warmth) + 0.012 * delta, 1.0)
	_check_t += delta
	if _check_t > 1.0:
		_check_t = 0.0
		_catch_from_grass()
	_save_t += delta
	if _dirty and _save_t > 5.0:
		_save_t = 0.0
		_dirty = false
		save()


## A grass fire reaching a building's walls sets it going.
func _catch_from_grass() -> void:
	if fire == null or not fire.has_method("burning_at"):
		return
	for id in items:
		var it: Dictionary = items[id]
		if bool(it["lit"]) or bool(it["burnt"]):
			continue
		var xf: Transform3D = it["xf"]
		var sz: Vector3 = it["size"]
		for c in [Vector3(-0.6, 0, -0.6), Vector3(0.6, 0, -0.6), Vector3(0.6, 0, 0.6), Vector3(-0.6, 0, 0.6), Vector3(0, 0, -0.6), Vector3(0, 0, 0.6), Vector3(-0.6, 0, 0), Vector3(0.6, 0, 0)]:
			var p: Vector3 = xf * Vector3(c.x * sz.x, 0, c.z * sz.z)
			if fire.burning_at(p) and randf() < 0.35:
				set_on_fire(id)
				break


func _burn_step(id: String, it: Dictionary, delta: float, wv: Vector3) -> void:
	var xf: Transform3D = it["xf"]
	var heat := float(it["heat"])
	if not bool(it["burnt"]):
		heat = minf(heat + delta * 0.012, 1.0)
		it["burn"] = float(it["burn"]) + delta * heat / _burn_time(it)
	else:
		heat = maxf(heat - delta * 0.006, 0.0)       # the ruin burns down to embers
		if heat <= 0.0:
			it["lit"] = false
	it["heat"] = heat
	# flames: more of the building goes as it grows
	var pts: Array = it["flame_pts"]
	var fires: Array = it["fires"]
	var want := clampi(int(ceil(heat * float(pts.size()) * 1.2)), 1, pts.size()) if heat > 0.0 else 0
	while fires.size() < want:
		var f := Fx.make_fire()
		add_child(f)
		var lp: Vector3 = pts[fires.size()]
		if bool(it["burnt"]):
			lp.y = minf(lp.y, 0.6)
		f.global_position = xf * lp
		fires.append(f)
	for i in range(fires.size() - 1, -1, -1):
		var fn: Node3D = fires[i]
		if i >= want:
			Fx.set_fire_strength(fn, 0.0, wv, _t)
			if heat <= 0.0:
				fn.queue_free()
				fires.remove_at(i)
			continue
		var s := clampf(heat * (1.15 - 0.15 * float(i)), 0.05, 1.0)
		Fx.set_fire_strength(fn, s, wv, _t + float(i))
	if float(it["burn"]) > 0.3 and not it.has("charred"):
		it["charred"] = true
		_char(it["node"], true)
	# sparks start the grass round it
	if fire != null and heat > 0.4 and randf() < delta * 0.25:
		var sz: Vector3 = it["size"]
		var a := randf() * TAU
		var p := xf * Vector3(cos(a) * (sz.x * 0.5 + randf_range(1.0, 6.0)), 0, sin(a) * (sz.z * 0.5 + randf_range(1.0, 6.0)))
		p.y = terrain.height_at(p.x, p.z)
		fire.ignite(p + wv * randf_range(0.0, 1.5), 1.5)
	if float(it["burn"]) >= 1.0 and not bool(it["burnt"]):
		_collapse(id, it, true)
		_say("The %s has burnt down." % _name(it))


static var _char_mat: StandardMaterial3D
func _char(n: Node3D, on: bool) -> void:
	if _char_mat == null:
		_char_mat = StandardMaterial3D.new()
		_char_mat.albedo_color = Color(0.05, 0.045, 0.04, 0.85)
		_char_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_char_mat.roughness = 1.0
	(n as MeshInstance3D).material_overlay = _char_mat if on else null


## It comes down: the building goes, a ruin is left; nothing blocks you but
## the stove and the chimney.
func _collapse(id: String, it: Dictionary, live: bool) -> void:
	it["burnt"] = true
	it["burn"] = 1.0
	(it["node"] as Node3D).visible = false
	for s in it["solids"]:
		terrain.solids.erase(s)
	for h in it["hollows"]:
		terrain.hollows.erase(h)
	it["solids"] = []
	it["hollows"] = []
	var st: Dictionary = it["stove"]
	if not st.is_empty():
		st["lit"] = false
		_stove_show(st)
	for l in get_children():
		if l is Label3D and (l as Label3D).global_position.distance_to((it["xf"] as Transform3D).origin) < 9.0:
			l.visible = false
	var kit := MeshKit.new()
	_ruin(kit, it)
	var r := kit.instance("Ruin_" + id)
	r.transform = it["xf"]
	add_child(r)
	it["ruin"] = r
	if not st.is_empty():
		terrain.add_solid((it["xf"] as Transform3D) * Transform3D(Basis.IDENTITY, st["at"] as Vector3), Vector3(0.8, 1.0, 1.0))
	if live:
		it["heat"] = minf(float(it["heat"]), 0.6)
	_dirty = true


## What's left: the charred floor and sill, stumps of the bottom logs or the
## steel posts, the roof sheets fallen in across it, the stove and its pipe.
func _ruin(kit: MeshKit, it: Dictionary) -> void:
	var sz: Vector3 = it["size"]
	var rng := RandomNumberGenerator.new()
	rng.seed = String(it["kind"]).hash()
	var black := Color(0.07, 0.065, 0.06)
	var ash := Color(0.34, 0.33, 0.31)
	var w := sz.x - 0.8
	var d := sz.z - 0.8
	kit.box_at(Vector3(0, 0.05, 0), Vector3(w, 0.1, d), ash)
	match String(it["kind"]):
		"cabin", "office", "loghouse":
			for side in [-1.0, 1.0]:
				for row in range(2):
					var l1 := w * rng.randf_range(0.5, 1.0)
					kit.box_at(Vector3(rng.randf_range(-0.5, 0.5), 0.2 + 0.25 * float(row), side * d * 0.5), Vector3(l1, 0.26, 0.28), black)
					var l2 := d * rng.randf_range(0.4, 1.0)
					kit.box_at(Vector3(side * w * 0.5, 0.3 + 0.25 * float(row), rng.randf_range(-0.5, 0.5)), Vector3(0.28, 0.26, l2), black)
			for cx in [-1.0, 1.0]:
				for cz in [-1.0, 1.0]:
					kit.box_at(Vector3(cx * w * 0.5, rng.randf_range(0.5, 1.2), cz * d * 0.5), Vector3(0.32, 1.4, 0.32), black)
		_:
			for i in range(6):
				var px := (float(i % 3) - 1.0) * w * 0.45
				var pz := (float(i / 3) * 2.0 - 1.0) * d * 0.45
				kit.box(Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.4, 0.4)), Vector3(px, rng.randf_range(0.6, 1.6), pz)), Vector3(0.18, rng.randf_range(1.2, 3.0), 0.18), black)
	# roof sheets, buckled and fallen in
	for i in range(int(clampf(w * d / 6.0, 3.0, 14.0))):
		var c := Vector3(rng.randf_range(-w * 0.45, w * 0.45), rng.randf_range(0.15, 0.7), rng.randf_range(-d * 0.45, d * 0.45))
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5)) * Basis(Vector3.FORWARD, rng.randf_range(-0.3, 0.3))
		kit.box(Transform3D(b, c), Vector3(rng.randf_range(0.8, 1.6), 0.03, rng.randf_range(1.6, 3.2)), [Color(0.30, 0.28, 0.27), Color(0.42, 0.26, 0.18), Color(0.20, 0.19, 0.19)][i % 3])
	# heaps of ash and charcoal
	for i in range(8):
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-w * 0.4, w * 0.4), 0.08, rng.randf_range(-d * 0.4, d * 0.4))), rng.randf_range(0.4, 1.0), 0.0, rng.randf_range(0.15, 0.35), 6, ash.darkened(rng.randf_range(0.0, 0.5)), false)
	var st: Dictionary = it["stove"]
	if not st.is_empty():
		var at: Vector3 = st["at"]
		var top: Vector3 = st["top"]
		Models.wood_stove(kit, at, top.y * 0.7, false)


# ==============================================================================
#  Saving
# ==============================================================================
func save() -> void:
	var cf := ConfigFile.new()
	for id in items:
		var it: Dictionary = items[id]
		cf.set_value(id, "burnt", bool(it["burnt"]))
		cf.set_value(id, "burn", float(it["burn"]))
		cf.set_value(id, "lit", bool(it["lit"]))
		cf.set_value(id, "heat", float(it["heat"]))
		var st: Dictionary = it["stove"]
		if not st.is_empty():
			cf.set_value(id, "stove_lit", bool(st["lit"]))
			cf.set_value(id, "fuel", float(st["fuel"]))
			cf.set_value(id, "box", int(st["box"]))
	cf.set_value("_", "wood", carrying_wood)
	cf.save(SAVE)


func _restore(id: String) -> void:
	if _saved.has("_"):
		carrying_wood = int(_saved["_"].get("wood", 0))
	if not _saved.has(id):
		return
	var d: Dictionary = _saved[id]
	var it: Dictionary = items[id]
	it["burn"] = float(d.get("burn", 0.0))
	var st: Dictionary = it["stove"]
	if not st.is_empty():
		st["lit"] = bool(d.get("stove_lit", false))
		st["fuel"] = float(d.get("fuel", 0.0))
		st["box"] = int(d.get("box", 3))
		_stove_show(st)
	if bool(d.get("burnt", false)):
		_collapse(id, it, false)
		it["lit"] = false
		it["heat"] = 0.0
	elif bool(d.get("lit", false)):
		it["lit"] = true
		it["heat"] = float(d.get("heat", 0.2))
	if float(it["burn"]) > 0.3 and not bool(it["burnt"]):
		it["charred"] = true
		_char(it["node"], true)
