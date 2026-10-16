extends Node
## Flight sticks, throttles and rudder pedals (HOTAS), used alongside the
## keyboard and a gamepad. Any number of devices at once: the Logitech X56,
## for one, is two devices (stick and throttle).
##
## Each flight axis is bound to one axis of one device, found by moving it
## (calibrated from the two ends the player moves it to, so no inverting or
## range fiddling is needed). Buttons and hats on these devices can be bound to
## any action; pressing one sends that action as if a key had been pressed.
## Created by Game (game.gd) and reached as Game.hotas.

signal changed

const AXES: Array = [
	# [id, label, kind, first end, second end]   kind: centre or lever
	["roll", "Roll", "centre", "fully LEFT", "fully RIGHT"],
	["pitch", "Pitch", "centre", "fully FORWARD (nose down)", "fully BACK (nose up)"],
	["yaw", "Rudder", "centre", "full LEFT rudder", "full RIGHT rudder"],
	["throttle", "Throttle lever", "lever", "IDLE (all the way back)", "FULL (all the way forward)"],
	["prop", "Prop lever", "lever", "low rpm (back)", "high rpm (forward)"],
	["mixture", "Mixture lever", "lever", "lean / cut-off (back)", "full rich (forward)"],
	["brake_left", "Left toe brake", "lever", "released", "pressed fully"],
	["brake_right", "Right toe brake", "lever", "released", "pressed fully"],
	["trim", "Trim wheel", "centre", "nose DOWN", "nose UP"],
	["look_x", "Look left / right", "centre", "LEFT", "RIGHT"],
	["look_y", "Look up / down", "centre", "UP", "DOWN"],
]
const STICK_AXES := ["roll", "pitch", "yaw"]
const MAX_AXES := 10

var axes: Dictionary = {}       # id -> {dev, guid, a, lo, hi}
var buttons: Dictionary = {}    # action -> {dev, guid, i}
var deadzone := 0.03            # stick, rudder and look axes
var curve := 0.25               # 0 = straight, 1 = soft round the centre

var _ids: Dictionary = {}       # device key -> joypad id (rebuilt when plugged in or out)
var _last_lever: Dictionary = {}
var test_raw: Dictionary = {}   # self-test only: "id:axis" -> value for a pretend device


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_ids()
	Input.joy_connection_changed.connect(func(_id, _c): _refresh_ids())


# ------------------------------------------------------------------------------
#  Devices
# ------------------------------------------------------------------------------
static func dev_key(id: int) -> String:
	return Input.get_joy_guid(id) + "|" + Input.get_joy_name(id)


func _refresh_ids() -> void:
	_ids.clear()
	for id in Input.get_connected_joypads():
		var k := dev_key(id)
		if not _ids.has(k):
			_ids[k] = id
		# Also findable by name alone, in case the GUID changes between ports.
		var nk := "|" + Input.get_joy_name(id)
		if not _ids.has(nk):
			_ids[nk] = id


func _id_for(b: Dictionary) -> int:
	var k := String(b.get("guid", "")) + "|" + String(b.get("dev", ""))
	if _ids.has(k):
		return _ids[k]
	return _ids.get("|" + String(b.get("dev", "")), -1)


## Joypad ids that have something bound here: these are flight gear, so the
## gamepad bindings leave them alone.
func gear_ids() -> Array:
	var out: Array = []
	for b in axes.values():
		var id := _id_for(b)
		if id >= 0 and not out.has(id):
			out.append(id)
	for b in buttons.values():
		var id2 := _id_for(b)
		if id2 >= 0 and not out.has(id2):
			out.append(id2)
	return out


## A short name for a device: "X-56 Stick" rather than the full USB name.
static func short_name(dev: String) -> String:
	var n := dev
	for cut in ["Saitek Pro Flight ", "Logitech G ", "Logitech ", "Thrustmaster ", "Rhino "]:
		n = n.replace(cut, "")
	return n.strip_edges() if n.strip_edges() != "" else dev


static func label_of(id: String) -> String:
	for row in AXES:
		if row[0] == id:
			return row[1]
	return id


static func kind_of(id: String) -> String:
	for row in AXES:
		if row[0] == id:
			return row[2]
	return "centre"


# ------------------------------------------------------------------------------
#  Reading
# ------------------------------------------------------------------------------
func has_axis(id: String) -> bool:
	return axes.has(id) and _id_for(axes[id]) >= 0


func raw(id: String) -> float:
	var b: Dictionary = axes.get(id, {})
	if b.is_empty():
		return 0.0
	var dev := _id_for(b)
	if dev < 0:
		return 0.0
	var tk := "%d:%d" % [dev, int(b["a"])]
	if test_raw.has(tk):
		return test_raw[tk]
	return Input.get_joy_axis(dev, int(b["a"]) as JoyAxis)


## The axis as the game wants it: -1..1 for a stick axis, 0..1 for a lever.
func value(id: String) -> float:
	if not has_axis(id):
		return 0.0
	var b: Dictionary = axes[id]
	var r := raw(id)
	var lo: float = b["lo"]
	var hi: float = b["hi"]
	if is_equal_approx(lo, hi):
		return 0.0
	if kind_of(id) == "lever":
		return clampf(inverse_lerp(lo, hi, r), 0.0, 1.0)
	var v := clampf(remap(r, lo, hi, -1.0, 1.0), -1.0, 1.0)
	var dz := deadzone
	var m := absf(v)
	m = 0.0 if m < dz else (m - dz) / (1.0 - dz)
	if id in STICK_AXES:
		# Blend a cubic in: finer round the centre, full travel at the ends.
		m = lerpf(m, m * m * m, curve)
	return signf(v) * m


## True when a lever has been moved since the game last followed it (and the
## first time it is read), so keys can still nudge the throttle in between.
func lever_moved(id: String) -> bool:
	if not has_axis(id):
		return false
	var v := value(id)
	var last: float = _last_lever.get(id, -10.0)
	if absf(v - last) > 0.008:
		_last_lever[id] = v
		return true
	return false


func axis_name(id: String) -> String:
	if not axes.has(id):
		return "-"
	var b: Dictionary = axes[id]
	var s := "%s, axis %d" % [short_name(String(b["dev"])), int(b["a"])]
	if _id_for(b) < 0:
		s += " (unplugged)"
	return s


# ------------------------------------------------------------------------------
#  Buttons
# ------------------------------------------------------------------------------
## A button on any device that is not the gamepad in use goes through here.
func handle_button(ev: InputEventJoypadButton) -> bool:
	if not Input.get_connected_joypads().has(ev.device):
		return false
	var key := dev_key(ev.device)
	var name := Input.get_joy_name(ev.device)
	var hit := false
	for action in buttons.keys():
		var b: Dictionary = buttons[action]
		if int(b["i"]) != int(ev.button_index):
			continue
		if String(b["guid"]) + "|" + String(b["dev"]) != key and String(b["dev"]) != name:
			continue
		var a := InputEventAction.new()
		a.action = action
		a.pressed = ev.pressed
		a.strength = 1.0 if ev.pressed else 0.0
		Input.parse_input_event(a)
		hit = true
	return hit


func bind_button(action: String, ev: InputEventJoypadButton) -> String:
	var b := {"dev": Input.get_joy_name(ev.device), "guid": Input.get_joy_guid(ev.device), "i": int(ev.button_index)}
	var taken := ""
	for other in buttons.keys():
		var o: Dictionary = buttons[other]
		if other != action and int(o["i"]) == b["i"] and String(o["dev"]) == b["dev"]:
			buttons.erase(other)
			taken = other
	buttons[action] = b
	changed.emit()
	return taken


func button_name(action: String) -> String:
	if not buttons.has(action):
		return "-"
	var b: Dictionary = buttons[action]
	return "%s %s" % [short_name(String(b["dev"])), _btn_text(int(b["i"]))]


static func _btn_text(i: int) -> String:
	match i:
		11:
			return "hat up"
		12:
			return "hat down"
		13:
			return "hat left"
		14:
			return "hat right"
	return "btn %d" % (i + 1)


# ------------------------------------------------------------------------------
#  Finding an axis by moving it: a snapshot with the control at one end, another
#  at the other end; the axis that changed most is the one.
# ------------------------------------------------------------------------------
func snapshot() -> Dictionary:
	var out := {}
	for dev in Input.get_connected_joypads():
		for a in range(MAX_AXES):
			out["%d:%d" % [dev, a]] = Input.get_joy_axis(dev, a as JoyAxis)
	for k in test_raw.keys():
		out[k] = test_raw[k]
	return out


## Which axis moved most between two snapshots (skipping ones bound elsewhere).
func best_change(first: Dictionary, second: Dictionary, skip_for: String) -> Dictionary:
	var best := {}
	var best_d := 0.0
	for k in second.keys():
		if not first.has(k):
			continue
		var parts: PackedStringArray = String(k).split(":")
		var dev := int(parts[0])
		var a := int(parts[1])
		if _bound_elsewhere(dev, a, skip_for):
			continue
		var d := absf(float(second[k]) - float(first[k]))
		if d > best_d:
			best_d = d
			best = {"dev": dev, "a": a, "lo": float(first[k]), "hi": float(second[k]), "travel": d}
	return best


func _bound_elsewhere(dev: int, a: int, skip_for: String) -> bool:
	for id in axes.keys():
		if id == skip_for:
			continue
		var b: Dictionary = axes[id]
		if _id_for(b) == dev and int(b["a"]) == a:
			return true
	return false


## Bind `id` from two snapshots. Returns "" or what went wrong.
func bind_axis(id: String, first: Dictionary, second: Dictionary) -> String:
	var best := best_change(first, second, id)
	if best.is_empty() or float(best["travel"]) < 0.4:
		return "Nothing moved far enough. Try again, moving it all the way."
	var dev: int = best["dev"]
	axes[id] = {"dev": Input.get_joy_name(dev), "guid": Input.get_joy_guid(dev), "a": int(best["a"]), "lo": best["lo"], "hi": best["hi"]}
	_last_lever.erase(id)
	changed.emit()
	return ""


func flip(id: String) -> void:
	if axes.has(id):
		var b: Dictionary = axes[id]
		var t: float = b["lo"]
		b["lo"] = b["hi"]
		b["hi"] = t
		_last_lever.erase(id)
		changed.emit()


func clear_axis(id: String) -> void:
	axes.erase(id)
	_last_lever.erase(id)
	changed.emit()


func clear_all() -> void:
	axes.clear()
	buttons.clear()
	_last_lever.clear()
	changed.emit()


# ------------------------------------------------------------------------------
#  Saving (into Game's settings file)
# ------------------------------------------------------------------------------
func save_to(cf: ConfigFile) -> void:
	cf.set_value("hotas", "axes", axes)
	cf.set_value("hotas", "buttons", buttons)
	cf.set_value("hotas", "deadzone", deadzone)
	cf.set_value("hotas", "curve", curve)


func load_from(cf: ConfigFile) -> void:
	var a = cf.get_value("hotas", "axes", {})
	var b = cf.get_value("hotas", "buttons", {})
	axes = a if a is Dictionary else {}
	buttons = b if b is Dictionary else {}
	deadzone = clampf(float(cf.get_value("hotas", "deadzone", deadzone)), 0.0, 0.3)
	curve = clampf(float(cf.get_value("hotas", "curve", curve)), 0.0, 1.0)
