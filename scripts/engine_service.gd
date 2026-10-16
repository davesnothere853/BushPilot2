extends Node3D
## Working on the engine, on foot: open the cowling (door key at the nose),
## look at a part (it lights up), press interact for what you can do with it.
## What you know about each part is what you've found by looking: the dipstick,
## pulling a plug, a compression test. Small jobs can be done anywhere if you
## carry the spares; big ones (cylinders, magnetos, an overhaul) need a hangar.

const EngineModel = preload("res://scripts/engine_model.gd")
const Radial = preload("res://scripts/engine_model_radial.gd")

var main: Node
var plane: Node3D
var walker: Node3D
var jobs: Node
var fleet: Node
var hud: Control
var prompt := ""
var part := ""                 # what you're looking at
var result := ""               # the last thing you found or did (shown on the page)
var known := {}                # part id -> short status found by looking
var _ghost: MeshInstance3D

## [label, price]
const SPARES := {
	"oil_qt": ["Quart of oil", 12],
	"oil_filter": ["Oil filter", 45],
	"plug": ["Spark plug", 28],
	"air_filter": ["Air filter", 35],
	"belt": ["Alternator belt", 40],
	"mag": ["Magneto", 1450],
	"tester": ["Compression tester (tool, keeps)", 160],
}
const CYLINDER_PRICE := 3800
const MUFFLER_PRICE := 900
const OVERHAUL_PRICE := 24000
const TBO := 2000.0


func _ready() -> void:
	_ghost = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	_ghost.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.75, 0.25, 0.28)
	m.no_depth_test = true
	_ghost.material_override = m
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


var bay := 0                  # which engine is being worked on (DC-3: 0 left, 1 right)


func _is_dc3() -> bool:
	return plane != null and plane.plane_type == "dc3"


## The engine the current bay (or this part id) belongs to.
func _eng(id: String = ""):
	if _is_dc3():
		var b := bay
		if id.begins_with("e0_"):
			b = 0
		elif id.begins_with("e1_"):
			b = 1
		return plane.engine2 if b == 1 and plane.engine2 != null else plane.engine
	return plane.engine


## A DC-3 part id without its engine prefix ("e1_cyl_4" -> "cyl_4").
static func _pid(id: String) -> String:
	return id.substr(3) if id.begins_with("e0_") or id.begins_with("e1_") else id


func has_engine_bay() -> bool:
	return plane != null and (plane.plane_type == "wolverine" or _is_dc3())


## The door key for the engine covers ("cowl" on the Wolverine's nose,
## "cowl0"/"cowl1" for the DC-3's nacelle panels).
func _cowl_key() -> String:
	return "cowl%d" % bay if _is_dc3() else "cowl"


## Standing close enough to an engine to reach it? Sets `bay` for the DC-3.
func near_nose() -> bool:
	if not has_engine_bay() or walker == null or not walker.visible:
		return false
	var lp: Vector3 = plane.global_transform.affine_inverse() * walker.global_position
	if _is_dc3():
		for ei in range(2):
			var nx := Radial.nacelle_x(ei)
			if absf(lp.x - nx) < 1.9 and lp.z > -4.6 and lp.z < -1.2:
				bay = ei
				return true
		return false
	return lp.z < -0.4 and lp.z > -3.6 and absf(lp.x) < 2.2


func cowl_open() -> bool:
	return bool(plane.door_open.get(_cowl_key(), false))


func toggle_cowl() -> String:
	var what := "nacelle panels" if _is_dc3() else "cowl doors"
	if cowl_open():
		plane.door_open[_cowl_key()] = false
		return "Panels closed and fastened." if _is_dc3() else "Cowling closed and latched."
	if _eng().running:
		return "Shut the engine down first: that propeller will take your head off."
	if not plane.on_ground or plane.ground_speed > 0.5:
		return "Not while it's moving."
	plane.door_open[_cowl_key()] = true
	return "You undo the fasteners and swing the %s up." % what


## Called every frame on foot: what you're looking at, and the prompt.
func find_target() -> void:
	prompt = ""
	part = ""
	_ghost.visible = false
	if not job.is_empty():
		prompt = job_prompt()
		return
	if not near_nose():
		return
	if not cowl_open():
		prompt = "%s  Open the cowling" % Game.hint("door")
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	# The part nearest the middle of the view (measured as an angle, so small
	# parts behind bigger ones can still be picked by aiming right at them).
	var best := 1.0
	var best_spot: Array = []
	var xf: Transform3D = plane.global_transform
	for sp in (Radial.spots(bay) if _is_dc3() else EngineModel.spots()):
		var c: Vector3 = xf * (sp[2] as Vector3)
		var oc := c - o
		var t := oc.dot(d)
		if t < 0.1 or t > 3.2:
			continue
		var miss := (oc - d * t).length() / (float(sp[3]) * 1.3 + 0.02 * t)
		if miss < best:
			best = miss
			best_spot = sp
	if best_spot.is_empty():
		prompt = "Look at a part of the engine.   %s  Close the cowling" % Game.hint("door")
		return
	part = best_spot[0]
	var k: String = known.get(part, "")
	prompt = "%s  %s%s" % [Game.hint("interact"), best_spot[1], ("  (" + k + ")") if k != "" else ""]
	_ghost.global_position = xf * (best_spot[2] as Vector3)
	_ghost.scale = Vector3.ONE * float(best_spot[3]) * 1.1
	_ghost.visible = true


func label_of(id: String) -> String:
	for sp in (Radial.spots(0) + Radial.spots(1)) if _is_dc3() else EngineModel.spots():
		if sp[0] == id:
			return sp[1]
	if id == "logbook":
		return "Engine logbook"
	return id


# ------------------------------------------------------------------------------
#  Reading the parts
# ------------------------------------------------------------------------------
static func _oil_colour(life: float) -> String:
	if life > 0.8:
		return "clean and golden"
	if life > 0.55:
		return "amber"
	if life > 0.3:
		return "dark brown"
	if life > 0.1:
		return "black"
	return "black and gritty, like tar"


static func _plug_look(foul: float, wear: float) -> String:
	var s := "light tan, a healthy plug"
	if foul > 0.6:
		s = "black and sooty: badly fouled"
	elif foul > 0.3:
		s = "sooty: running rich, fouling up"
	elif foul > 0.15:
		s = "a little dark"
	if wear > 0.8:
		s += ", electrodes worn down to nothing"
	elif wear > 0.5:
		s += ", electrodes rounded and worn"
	return s


static func _comp_word(c: float) -> String:
	if c >= 70.0:
		return "good"
	if c >= 60.0:
		return "fair"
	if c >= 50.0:
		return "weak: ring or valve wear"
	return "bad: a burnt valve or broken ring"


func _plug_index(id: String) -> int:
	var bits := _pid(id).split("_")
	var n := int(bits[1])
	return (n - 1) * 2 + (0 if bits.size() > 2 and bits[2] == "bot" else 0 if bits.size() > 2 and bits[2] == "top" else 0) + (1 if bits.size() > 2 and bits[2] == "bot" else 0)


func _cyl_index(id: String) -> int:
	return int(_pid(id).split("_")[1]) - 1


## Facts already found about a part (for the page).
func describe(id: String) -> Array:
	var e = _eng()
	var out: Array = []
	if id == "logbook":
		out.append("Hours since overhaul: %d of %d (TBO)." % [int(e.hours), int(TBO)])
		out.append("Oil changed %d hours ago." % int(e.oil_hours))
		if e.hours > TBO:
			out.append("Past TBO: an overhaul is due.")
	if known.has(id):
		out.append("Last look: " + String(known[id]))
	return out


# ------------------------------------------------------------------------------
#  What you can do: [button text, action id, why not (or "")]
# ------------------------------------------------------------------------------
func at_hangar() -> bool:
	return fleet != null and fleet.hangar_here() >= 0


func _have(kind: String, n: int = 1) -> bool:
	return int(jobs.spares.get(kind, 0)) >= n


## Can you get this part here: carried, or bought at a hangar's parts counter?
func _source(kind: String, n: int = 1) -> String:
	if _have(kind, n):
		return ""
	if at_hangar():
		var cost := int(SPARES[kind][1]) * n
		if Game.sandbox or jobs.money >= cost:
			return ""
		return "need $%d" % cost
	return "no spare %s with you" % String(SPARES[kind][0]).to_lower()


func _price_tag(kind: String, n: int = 1) -> String:
	if _have(kind, n):
		return "(from your spares)"
	if at_hangar() and not Game.sandbox:
		return "($%d)" % (int(SPARES[kind][1]) * n)
	return ""


func actions(id: String) -> Array:
	var e = _eng(id)
	var out: Array = []
	var hangar_only := "" if at_hangar() else "needs a hangar"
	var id_full := id
	id = _pid(id)
	if _is_dc3() and id.begins_with("cyl_"):
		var tool_why2 := "" if (_have("tester") or at_hangar()) else "needs a compression tester (or a hangar)"
		out.append(["Pull both plugs and read them", "read_plug", ""])
		out.append(["Clean them, regap them and put them back", "clean_plug", ""])
		out.append(["Fit two new plugs %s" % _price_tag("plug", 2), "new_plug", _source("plug", 2)])
		out.append(["Compression test this cylinder", "comp_one", tool_why2])
		out.append(["Compression test all fourteen", "comp_all", tool_why2])
		out.append(["Replace the cylinder ($%d)" % CYLINDER_PRICE, "new_cyl", hangar_only if hangar_only != "" else _money_why(CYLINDER_PRICE)])
		out.append(["Full engine overhaul ($%d): everything as new, hours back to zero" % OVERHAUL_PRICE, "overhaul", hangar_only if hangar_only != "" else _money_why(OVERHAUL_PRICE)])
		return out
	if id == "dipstick":
		out.append(["Pull the dipstick and check the oil", "check_oil", ""])
		out.append(["Add a quart of oil %s" % _price_tag("oil_qt"), "add_oil", _source("oil_qt") if e.oil_qts < e.oil_capacity - 0.5 else "it's full"])
		out.append(["Change the oil and filter (%d qt + filter) %s" % [int(e.oil_capacity), _price_tag("oil_qt", int(e.oil_capacity))], "oil_change",
			_source("oil_qt", int(e.oil_capacity)) if _source("oil_qt", int(e.oil_capacity)) != "" else _source("oil_filter")])
	elif id == "oil_filter":
		out.append(["Look the filter over", "look_filter", ""])
		out.append(["Change the oil and filter %s" % _price_tag("oil_filter"), "oil_change",
			_source("oil_qt", int(e.oil_capacity)) if _source("oil_qt", int(e.oil_capacity)) != "" else _source("oil_filter")])
	elif id.begins_with("plug_"):
		out.append(["Pull the plug and read it", "read_plug", ""])
		out.append(["Clean it, regap it and put it back", "clean_plug", ""])
		out.append(["Fit a new plug %s" % _price_tag("plug"), "new_plug", _source("plug")])
		out.append(["New plugs all round (12) %s" % _price_tag("plug", 12), "all_plugs", _source("plug", 12)])
	elif id.begins_with("cyl_"):
		var tool_why := "" if (_have("tester") or at_hangar()) else "needs a compression tester (or a hangar)"
		out.append(["Compression test this cylinder", "comp_one", tool_why])
		out.append(["Compression test all six", "comp_all", tool_why])
		out.append(["Replace the cylinder ($%d)" % CYLINDER_PRICE, "new_cyl", hangar_only if hangar_only != "" else _money_why(CYLINDER_PRICE)])
	elif id == "mag_l" or id == "mag_r":
		out.append(["Check the points and timing", "check_mag", ""])
		out.append(["Fit a new magneto %s" % _price_tag("mag"), "new_mag", _source("mag")])
	elif id == "air_filter":
		out.append(["Pull the filter and look at it", "look_air", ""])
		out.append(["Knock the dust out of it", "knock_air", ""])
		out.append(["Fit a new air filter %s" % _price_tag("air_filter"), "new_air", _source("air_filter")])
	elif id == "belt":
		out.append(["Check the belt for cracks and tension", "look_belt", ""])
		out.append(["Fit a new belt %s" % _price_tag("belt"), "new_belt", _source("belt")])
	elif id == "exhaust":
		out.append(["Look for cracks and soot streaks", "look_exhaust", ""])
		out.append(["Replace the muffler ($%d)" % MUFFLER_PRICE, "new_muffler", hangar_only if hangar_only != "" else _money_why(MUFFLER_PRICE)])
	elif id == "battery":
		out.append(["Check the charge", "look_battery", ""])
		out.append(["Put it on the charger", "charge", hangar_only])
	if id == "logbook" or id.begins_with("cyl_"):
		out.append(["Full engine overhaul ($%d): everything as new, hours back to zero" % OVERHAUL_PRICE, "overhaul", hangar_only if hangar_only != "" else _money_why(OVERHAUL_PRICE)])
	return out


func _money_why(cost: int) -> String:
	return "" if Game.sandbox or jobs.money >= cost else "need $%d" % cost


func _take(kind: String, n: int = 1) -> void:
	if _have(kind, n):
		jobs.spares[kind] = int(jobs.spares[kind]) - n
	elif not Game.sandbox:
		jobs.money -= int(SPARES[kind][1]) * n
	jobs.save_career()


func _pay(cost: int) -> void:
	if not Game.sandbox:
		jobs.money -= cost
	jobs.save_career()


## Time passes while you work.
func _work(minutes: float) -> void:
	Game.time_of_day = fposmod(Game.time_of_day + minutes / 60.0, 24.0)
	Game.notify_changed()


## How long each job really takes at the engine, in seconds of standing
## there with the part in your hands (the clock also jumps via _work()).
const DURATIONS := {"check_oil": 3.0, "add_oil": 3.0, "oil_change": 8.0, "look_filter": 2.5,
	"read_plug": 3.0, "clean_plug": 5.0, "new_plug": 4.0, "all_plugs": 12.0,
	"comp_one": 4.0, "comp_all": 12.0, "new_cyl": 10.0, "check_mag": 3.0, "new_mag": 6.0,
	"look_air": 3.0, "knock_air": 3.5, "new_air": 4.0, "look_belt": 2.0, "new_belt": 6.0,
	"look_exhaust": 2.5, "new_muffler": 8.0, "look_battery": 2.0, "charge": 4.0, "overhaul": 15.0}

var job := {}                 # the work in hand: {id, act, t, dur, out: [part ids off the engine]}
var _mat_node: Node3D         # the shop cloth with the removed part lying on it
var _tip: MeshInstance3D      # the wetted end of the pulled dipstick


## Which parts visibly come off the engine for this job.
func _parts_out(id: String, act: String) -> Array:
	var pre := id.substr(0, 3) if id.begins_with("e0_") or id.begins_with("e1_") else ""
	match act:
		"read_plug", "clean_plug", "new_plug":
			return [pre + "cyl_%d" % (_cyl_index(id) + 1)] if pre != "" else [id]
		"all_plugs":
			var out: Array = []
			for n in range(1, 7):
				out.append("plug_%d_top" % n)
				out.append("plug_%d_bot" % n)
			return out
		"comp_one":
			return [pre + "cyl_%d" % (_cyl_index(id) + 1)] if pre != "" else ["plug_%d_top" % (_cyl_index(id) + 1)]
		"comp_all":
			var out2: Array = []
			if pre != "":
				for n in range(1, 15):
					out2.append(pre + "cyl_%d" % n)
			else:
				for n in range(1, 7):
					out2.append("plug_%d_top" % n)
			return out2
		"new_cyl":
			var c := _cyl_index(id) + 1
			if pre != "":
				return [pre + "cyl_%d" % c]
			return ["cyl_%d" % c, "plug_%d_top" % c, "plug_%d_bot" % c]
		"look_filter", "oil_change":
			return [pre + "oil_filter"]
		"look_air", "knock_air", "new_air":
			return [pre + "air_filter"]
		"new_muffler":
			return [pre + "exhaust"]
		"charge":
			return [pre + "battery"]
		"check_mag", "new_mag":
			return [id] if pre != "" else []
	return []


func _part_node(pid: String) -> Node3D:
	if plane == null or not plane.has_meta("visual"):
		return null
	var pv = plane.get_meta("visual")
	if pv == null or not pv.has_method("part_node"):
		return null
	return pv.part_node(pid)


## Start the work: the part comes off onto a shop cloth on the ground and you
## stand there doing it; the result lands when it's done (_process).
func do(id: String, act: String) -> String:
	if not job.is_empty():
		return "Hands are full: finish what you're doing."
	var dur := float(DURATIONS.get(act, 0.0))
	if dur <= 0.0:
		return _apply(id, act)
	var outp := _parts_out(id, act)
	for pid in outp:
		var n := _part_node(pid)
		if n != null:
			n.visible = false
	job = {"id": id, "act": act, "t": 0.0, "dur": dur, "out": outp}
	_lay_out_part(outp)
	if act == "check_oil" or act == "add_oil" or act == "oil_change":
		pass        # the dipstick slides out in _process
	return ""


## The removed part, lying on a red shop cloth under the nose.
func _lay_out_part(outp: Array) -> void:
	_clear_mat()
	if outp.is_empty() or plane == null:
		return
	_mat_node = Node3D.new()
	var cloth := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.55, 0.45)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.48, 0.10, 0.08)
	cm.roughness = 1.0
	pm.material = cm
	cloth.mesh = pm
	_mat_node.add_child(cloth)
	var kit = EngineModel.part_kit(outp[0])
	var pi: Node3D = kit.instance("Part")
	# The kit builds in plane space round the engine: bring it down to the mat.
	var centre := _spot_pos(outp[0])
	pi.position = Vector3(-centre.x, -centre.y + 0.05, -centre.z)
	pi.rotation.z = 0.5
	_mat_node.add_child(pi)
	var side := 1.0 if _spot_pos(outp[0]).x >= 0.0 else -1.0
	var mat_local := Vector3(side * 1.05, 0.0, -1.5)
	if _is_dc3():
		mat_local = Vector3(Radial.nacelle_x(bay) + 1.4, 0.0, -3.0)
	var world_at: Vector3 = plane.global_transform * mat_local
	world_at.y = plane.terrain.height_at(world_at.x, world_at.z) + 0.03
	_mat_node.position = world_at
	add_child(_mat_node)


func _spot_pos(pid: String) -> Vector3:
	for sp in (Radial.spots(0) + Radial.spots(1)) if _is_dc3() else EngineModel.spots():
		if sp[0] == pid:
			return sp[2]
	return Vector3(0, 0, -1.4)


func _clear_mat() -> void:
	if _mat_node != null:
		_mat_node.queue_free()
		_mat_node = null


func _process(delta: float) -> void:
	if job.is_empty():
		return
	job["t"] = float(job["t"]) + delta
	# The dipstick slides out of its tube while you check the oil.
	var act: String = job["act"]
	if act == "check_oil" or act == "add_oil" or act == "oil_change":
		var ds := _part_node(("e%d_dipstick" % bay) if _is_dc3() else "dipstick")
		if ds != null:
			var k := clampf(float(job["t"]) / 1.2, 0.0, 1.0)
			ds.position.y = 0.24 * k
			if _tip == null and k >= 1.0:
				_tip = MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.014, 0.05, 0.006)
				var tm := StandardMaterial3D.new()
				var e = _eng()
				tm.albedo_color = Color(0.25, 0.18, 0.05).lerp(Color(0.05, 0.04, 0.02), 1.0 - clampf(e.oil_life, 0.0, 1.0))
				tm.roughness = 0.25
				bm.material = tm
				_tip.mesh = bm
				_tip.position = Vector3(Radial.nacelle_x(bay), 0.60 + 0.24, -2.44) if _is_dc3() else Vector3(0.13, EngineModel.AXIS_Y + 0.02 + 0.24, -1.30)
				ds.get_parent().add_child(_tip)
	if float(job["t"]) >= float(job["dur"]):
		_finish_job()


func _finish_job() -> void:
	var r := _apply(String(job["id"]), String(job["act"]))
	# Everything back on (a job that fitted a new part shows the new one).
	for pid in job["out"]:
		var n := _part_node(pid)
		if n != null:
			n.visible = true
	var ds := _part_node(("e%d_dipstick" % bay) if _is_dc3() else "dipstick")
	if ds != null:
		ds.position.y = 0.0
	if _tip != null:
		_tip.queue_free()
		_tip = null
	_clear_mat()
	job = {}
	if main != null and main.hud != null:
		main.hud.push_message(r, 6.0)


func working() -> bool:
	return not job.is_empty()


func job_prompt() -> String:
	if job.is_empty():
		return ""
	var left := maxf(float(job["dur"]) - float(job["t"]), 0.0)
	return "Working on the %s... %d s" % [label_of(String(job["id"])).to_lower(), int(ceil(left))]


func _apply(id: String, act: String) -> String:
	var e = _eng(id)
	var dc3_cyl := _is_dc3() and _pid(id).begins_with("cyl_")
	var r := ""
	# On the DC-3 the plug work hangs off the cylinder spot: both plugs at once.
	if dc3_cyl and act in ["read_plug", "clean_plug", "new_plug"]:
		var ci := _cyl_index(id)
		match act:
			"read_plug":
				r = "Front plug %s; rear plug %s." % [_plug_look(float(e.plug_foul[ci * 2]), float(e.plug_wear[ci * 2])),
					_plug_look(float(e.plug_foul[ci * 2 + 1]), float(e.plug_wear[ci * 2 + 1]))]
				known[id] = r.split(";")[0].trim_prefix("Front plug ")
				_work(12)
			"clean_plug":
				for k in [ci * 2, ci * 2 + 1]:
					e.plug_foul[k] = 0.03
					e.plug_wear[k] = minf(float(e.plug_wear[k]) + 0.03, 1.0)
				r = "Both plugs cleaned, gapped and back in."
				known[id] = "plugs cleaned"
				_work(20)
			"new_plug":
				_take("plug", 2)
				for k in [ci * 2, ci * 2 + 1]:
					e.plug_foul[k] = 0.0
					e.plug_wear[k] = 0.0
				r = "Two new plugs in, torqued down, leads back on."
				known[id] = "new plugs"
				_work(16)
		result = r
		return r
	match act:
		"check_oil":
			r = "%.1f of %d quarts on the dipstick, %s. Changed %d hours ago." % [e.oil_qts, int(e.oil_capacity), _oil_colour(e.oil_life), int(e.oil_hours)]
			known["dipstick"] = "%.1f qt, %s" % [e.oil_qts, _oil_colour(e.oil_life)]
			_work(2)
		"add_oil":
			_take("oil_qt")
			e.oil_qts = minf(e.oil_qts + 1.0, e.oil_capacity)
			e.oil_life = lerpf(e.oil_life, 1.0, 1.0 / maxf(e.oil_qts, 1.0))
			r = "A quart in. Now %.1f quarts." % e.oil_qts
			known["dipstick"] = "%.1f qt" % e.oil_qts
			_work(3)
		"oil_change":
			_take("oil_qt", int(e.oil_capacity))
			_take("oil_filter")
			var old: String = _oil_colour(e.oil_life)
			e.oil_qts = e.oil_capacity
			e.oil_life = 1.0
			e.oil_filter = 1.0
			e.oil_hours = 0.0
			r = "Drained it (it came out %s), new filter on, %d quarts of fresh oil in." % [old, int(e.oil_capacity)]
			if e.health < 0.5:
				r += " There were metal flakes in the old filter: the bearings are going."
			known["dipstick"] = "%d qt, fresh" % int(e.oil_capacity)
			known["oil_filter"] = "new"
			_work(45)
		"look_filter":
			var f: float = e.oil_filter
			r = "The filter is %s." % ("new and clean" if f > 0.8 else ("in service, fine" if f > 0.4 else ("due for changing" if f > 0.15 else "clogged: the oil is going round it unfiltered")))
			known["oil_filter"] = "due" if f < 0.4 else "ok"
			_work(3)
		"read_plug":
			var i := _plug_index(id)
			r = "The plug is %s." % _plug_look(float(e.plug_foul[i]), float(e.plug_wear[i]))
			known[id] = _plug_look(float(e.plug_foul[i]), float(e.plug_wear[i])).split(":")[0].split(",")[0]
			_work(6)
		"clean_plug":
			var i := _plug_index(id)
			e.plug_foul[i] = 0.03
			e.plug_wear[i] = minf(float(e.plug_wear[i]) + 0.03, 1.0)
			r = "Cleaned, gapped and back in. %s" % ("Those electrodes are worn though: it wants replacing." if float(e.plug_wear[i]) > 0.7 else "")
			known[id] = "cleaned"
			_work(10)
		"new_plug":
			_take("plug")
			var i := _plug_index(id)
			e.plug_foul[i] = 0.0
			e.plug_wear[i] = 0.0
			r = "A new plug in, torqued down, lead back on."
			known[id] = "new"
			_work(8)
		"all_plugs":
			_take("plug", 12)
			for i in range(e.plug_foul.size()):
				e.plug_foul[i] = 0.0
				e.plug_wear[i] = 0.0
			for n in range(1, 7):
				known["plug_%d_top" % n] = "new"
				known["plug_%d_bot" % n] = "new"
			r = "Twelve new plugs in."
			_work(60)
		"comp_one":
			var c := _cyl_index(id)
			var v := float(e.comp[c])
			r = "Cylinder %d: %d/80. %s." % [c + 1, int(round(v)), _comp_word(v).capitalize()]
			known[id] = "%d/80" % int(round(v))
			_work(10)
		"comp_all":
			var parts: Array[String] = []
			for c in range(e.comp.size()):
				var v := float(e.comp[c])
				parts.append("#%d %d" % [c + 1, int(round(v))])
				known["cyl_%d" % (c + 1)] = "%d/80" % int(round(v))
			r = "Compression (out of 80): " + ", ".join(parts) + ". Under 60 is weak; under 50 needs a cylinder."
			_work(45)
		"new_cyl":
			_pay(CYLINDER_PRICE)
			var c := _cyl_index(id)
			e.comp[c] = 79.0
			e.plug_foul[c * 2] = 0.0
			e.plug_foul[c * 2 + 1] = 0.0
			e.plug_wear[c * 2] = 0.0
			e.plug_wear[c * 2 + 1] = 0.0
			known[id] = "79/80, new"
			r = "New cylinder, piston and rings on #%d, with new plugs. Run it in gently." % (c + 1)
			_work(300)
		"check_mag":
			var mi := 0 if _pid(id) == "mag_l" else 1
			var m := float(e.mag_cond[mi])
			r = "The %s magneto: %s." % ["left" if mi == 0 else "right", "points clean, timing spot on" if m > 0.7 else ("points pitted, timing drifting" if m > 0.35 else "points burnt and the timing way off: it's missing")]
			known[id] = "ok" if m > 0.7 else ("worn" if m > 0.35 else "failing")
			_work(20)
		"new_mag":
			_take("mag")
			var mi := 0 if _pid(id) == "mag_l" else 1
			e.mag_cond[mi] = 1.0
			known[id] = "new"
			r = "New magneto fitted and timed to the engine."
			_work(90)
		"look_air":
			var a: float = e.air_filter
			r = "The air filter is %s." % ("clean" if a < 0.2 else ("dusty" if a < 0.5 else ("caked with dirt: it's choking the engine" if a < 0.8 else "almost solid with dirt")))
			known[id] = "clean" if a < 0.2 else ("dusty" if a < 0.5 else "dirty")
			_work(5)
		"knock_air":
			e.air_filter *= 0.55
			r = "You bang it on the tyre until the dust stops coming out. Better, not new."
			known[id] = "knocked clean"
			_work(5)
		"new_air":
			_take("air_filter")
			e.air_filter = 0.0
			known[id] = "new"
			r = "New air filter in."
			_work(8)
		"look_belt":
			var bl: float = e.belt
			r = "The belt is %s." % ("snapped" if bl <= 0.0 else ("good and tight" if bl > 0.6 else ("glazed and cracking" if bl > 0.25 else "frayed: it won't last")))
			known[id] = "snapped" if bl <= 0.0 else ("ok" if bl > 0.6 else "worn")
			_work(3)
		"new_belt":
			_take("belt")
			e.belt = 1.0
			known[id] = "new"
			r = "New belt on and tensioned."
			_work(25)
		"look_exhaust":
			var x: float = e.exhaust
			r = "The exhaust %s." % ("looks sound" if x > 0.6 else ("has soot streaks at a joint: a small leak" if x > 0.3 else "is cracked at the muffler: carbon monoxide can get in the cabin heat"))
			known[id] = "ok" if x > 0.6 else ("leaking" if x > 0.3 else "cracked")
			_work(5)
		"new_muffler":
			_pay(MUFFLER_PRICE)
			e.exhaust = 1.0
			known[id] = "new"
			r = "New muffler and gaskets."
			_work(120)
		"look_battery":
			r = "The battery is about %d%% charged (%.1f V resting)." % [int(e.battery * 100.0), 11.4 + 1.2 * e.battery]
			known[id] = "%d%%" % int(e.battery * 100.0)
			_work(2)
		"charge":
			e.battery = 1.0
			known[id] = "charged"
			r = "Charged up overnight on the hangar charger."
			_work(240)
		"overhaul":
			_pay(OVERHAUL_PRICE)
			e.hours = 0.0
			e.health = 1.0
			for c in range(e.comp.size()):
				e.comp[c] = randf_range(77.0, 79.5)
			for i in range(e.plug_foul.size()):
				e.plug_foul[i] = 0.0
				e.plug_wear[i] = 0.0
			e.mag_cond = [1.0, 1.0]
			e.oil_life = 1.0
			e.oil_filter = 1.0
			e.oil_hours = 0.0
			e.oil_qts = e.oil_capacity
			e.air_filter = 0.0
			e.belt = 1.0
			e.exhaust = 1.0
			known.clear()
			r = "The engine comes back from the overhaul shop zero-timed: everything as new."
			_work(60 * 24)
	result = r
	return r


## Buying spares to carry, at a hangar.
func buy_spare(kind: String, n: int) -> String:
	var cost := int(SPARES[kind][1]) * n
	if not Game.sandbox and jobs.money < cost:
		return "Not enough money."
	if not Game.sandbox:
		jobs.money -= cost
	jobs.spares[kind] = int(jobs.spares.get(kind, 0)) + n
	jobs.save_career()
	return "Bought %d x %s." % [n, String(SPARES[kind][0]).to_lower()]


func spares_text() -> String:
	var bits: Array[String] = []
	for k in SPARES.keys():
		var n := int(jobs.spares.get(k, 0))
		if n > 0:
			bits.append("%s x%d" % [String(SPARES[k][0]).split(" (")[0].to_lower(), n])
	return "Spares on board: " + (", ".join(bits) if not bits.is_empty() else "none")
