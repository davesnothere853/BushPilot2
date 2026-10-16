extends CanvasLayer
## Phone and tablet controls (DESIGN_NOTES 128). Everything here presses the
## game's own input actions (Input.action_press with a strength), so the plane,
## the trucks and the pilot on foot take touches exactly like keys or a
## gamepad - and a Bluetooth controller still works alongside.
##   left thumb stick   fly: roll and pitch   drive / walk: steer and go
##   right half drag    look round
##   throttle slider    the plane's throttle (it stays where you leave it);
##                      in a vehicle, spring-loaded gas and brake
##   buttons            change with what you're doing (flying, driving, on foot)
##   tilt to fly        (option) bank and pitch by tilting the phone like a
##                      yoke; "Level" sets how you're holding it as centred
## Shown when Game.touch_mode is on, or automatic on a touch screen.

var m: Node                                  # main
var _root: Control
var _stick_id := -1
var _stick_c := Vector2.ZERO                 # where the thumb came down
var _stick_v := Vector2.ZERO                 # -1..1
var _look_id := -1
var _look_last := Vector2.ZERO
var _look_v := Vector2.ZERO
var _thr_id := -1
var _thr := 0.0                              # plane throttle 0..1, or gas -1..1 in a vehicle
var _btn_ids := {}                           # touch index -> button key
var _held := {}                              # button key -> true while down
var _buttons: Array = []                     # [key, label, action, rect]
var _ctx := ""
var _more := false
var _tilt0 := Vector3.ZERO                   # gravity when levelled
var _pressed_axes := {}                      # action -> strength we set last frame
const STICK_R := 90.0
const TILT_DEG := 25.0                       # this much tilt is full control


func _ready() -> void:
	layer = 40
	# hidden until _process says otherwise: the start menu pauses the tree, and
	# a layer left at its default (visible) showed the stick on a PC's title screen
	visible = wanted()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_all)
	add_child(_root)


static func wanted() -> bool:
	match int(Game.touch_mode):
		1:
			return true
		2:
			return false
	return DisplayServer.is_touchscreen_available() and (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"))


func _context() -> String:
	if m == null:
		return "fly"
	if bool(m.on_foot):
		return "drive" if m.driving != null else "foot"
	return "fly"


func _layout() -> void:
	var sz := _root.get_viewport_rect().size
	var s := clampf(sz.y / 720.0, 0.6, 2.0)
	var bw := 92.0 * s
	var bh := 64.0 * s
	var gap := 10.0 * s
	var sets := {
		"fly": [["exit", "OUT", "get_out"], ["cam", "VIEW", "camera"], ["brake", "BRAKE", "brake"], ["flaps_dn", "FLAP+", "flaps_down"],
			["flaps_up", "FLAP-", "flaps_up"], ["gear", "GEAR", "gear"], ["yaw_l", "◀ RUD", "yaw_left"], ["yaw_r", "RUD ▶", "yaw_right"]],
		"drive": [["exit", "OUT", "get_out"], ["cam", "VIEW", "camera"], ["use", "USE", "interact"], ["brake", "HAND", "brake"],
			["eng", "ENGINE", "engine_auto"], ["awd", "4WD", "four_wd"], ["lock", "LOCK", "diff_lock"], ["lights", "LIGHTS", "lights"]],
		"foot": [["use", "USE", "interact"], ["door", "DOOR", "door"], ["jump", "JUMP", "brake"], ["run", "RUN", "throttle_up"],
			["cam", "VIEW", "camera"], ["exit", "IN", "get_out"], ["inv", "BAG", "inventory"], ["build", "BUILD", "build"]],
	}
	var extra := [["menu", "MENU", "menu"], ["map", "MAP", "map"], ["jobs", "JOBS", "jobs"], ["eng2", "ENGINE", "engine_auto"],
		["lights2", "LIGHTS", "lights"], ["help", "HELP", "help"], ["level", "LEVEL", ""], ["more", "LESS", ""]]
	var list: Array = (extra if _more else sets.get(_ctx, sets["fly"])) + ([] if _more else [["more", "MORE", ""]])
	_buttons.clear()
	# two columns up the right edge, clear of the throttle
	var x0 := sz.x - gap - bw
	var y := sz.y - gap - bh
	var col := 0
	for b in list:
		var r := Rect2(Vector2(x0 - col * (bw + gap), y), Vector2(bw, bh))
		_buttons.append([b[0], b[1], b[2], r])
		col += 1
		if col == 2:
			col = 0
			y -= bh + gap


func _thr_rect() -> Rect2:
	var sz := _root.get_viewport_rect().size
	var s := clampf(sz.y / 720.0, 0.6, 2.0)
	var w := 70.0 * s
	var h := sz.y * 0.55
	return Rect2(Vector2(sz.x - 2.0 * (92.0 * s + 10.0 * s) - w - 24.0 * s, sz.y - h - 20.0 * s), Vector2(w, h))


func _input(event: InputEvent) -> void:
	if not visible or (m != null and m.menu != null and bool(m.menu.is_open)):
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var sz := _root.get_viewport_rect().size
		if t.pressed:
			for b in _buttons:
				if (b[3] as Rect2).grow(6.0).has_point(t.position):
					_btn_ids[t.index] = b[0]
					_press_button(b)
					_root.queue_redraw()
					get_viewport().set_input_as_handled()
					return
			if _ctx != "foot" and _thr_rect().grow(20.0).has_point(t.position):
				_thr_id = t.index
				_set_throttle(t.position)
				get_viewport().set_input_as_handled()
				return
			if t.position.x < sz.x * 0.45 and _stick_id < 0:
				_stick_id = t.index
				_stick_c = t.position
				_stick_v = Vector2.ZERO
			elif _look_id < 0:
				_look_id = t.index
				_look_last = t.position
			get_viewport().set_input_as_handled()
		else:
			if _btn_ids.has(t.index):
				var key: String = _btn_ids[t.index]
				_btn_ids.erase(t.index)
				_release_button(key)
			if t.index == _stick_id:
				_stick_id = -1
				_stick_v = Vector2.ZERO
			if t.index == _look_id:
				_look_id = -1
				_look_v = Vector2.ZERO
			if t.index == _thr_id:
				_thr_id = -1
				if _ctx == "drive":
					_thr = 0.0          # gas and brake spring back
			_root.queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_id:
			var off := d.position - _stick_c
			if off.length() > STICK_R:
				_stick_c += off - off.normalized() * STICK_R      # the stick follows a thumb that wanders off
				off = off.normalized() * STICK_R
			_stick_v = off / STICK_R
			_root.queue_redraw()
		elif d.index == _look_id:
			_look_v += (d.position - _look_last) * 0.012
			_look_last = d.position
		elif d.index == _thr_id:
			_set_throttle(d.position)
		get_viewport().set_input_as_handled()


func _set_throttle(p: Vector2) -> void:
	var r := _thr_rect()
	var f := clampf(1.0 - (p.y - r.position.y) / r.size.y, 0.0, 1.0)
	if _ctx == "fly":
		_thr = f
		if m != null and m.plane != null:
			m.plane.throttle = f
	else:
		_thr = f * 2.0 - 1.0                # top half gas, bottom half brake / reverse
	_root.queue_redraw()


func _press_button(b: Array) -> void:
	var key: String = b[0]
	match key:
		"more":
			_more = not _more
			_layout()
			return
		"level":
			_tilt0 = Input.get_gravity()
			if m != null and m.hud != null:
				m.hud.push_message("Tilt levelled: hold the phone like this for straight and level.", 2.5)
			return
	_held[key] = true
	var act: String = b[2]
	if act != "" and InputMap.has_action(act):
		var ev := InputEventAction.new()
		ev.action = act
		ev.pressed = true
		Input.parse_input_event(ev)        # the one-shot actions (is_action_pressed in _input)


func _release_button(key: String) -> void:
	_held.erase(key)
	for b in _buttons:
		if b[0] == key:
			var act: String = b[2]
			if act != "" and InputMap.has_action(act):
				var ev := InputEventAction.new()
				ev.action = act
				ev.pressed = false
				Input.parse_input_event(ev)


func _axis(neg: String, pos: String, v: float) -> void:
	for a in [[neg, maxf(-v, 0.0)], [pos, maxf(v, 0.0)]]:
		var act: String = a[0]
		var st: float = a[1]
		if st > 0.02:
			Input.action_press(act, clampf(st, 0.0, 1.0))
			_pressed_axes[act] = st
		elif _pressed_axes.has(act):
			Input.action_release(act)
			_pressed_axes.erase(act)


func _process(delta: float) -> void:
	var want := wanted() and not (m != null and m.menu != null and bool(m.menu.is_open))
	if visible != want:
		visible = want
		if not want:
			_release_all()
	if not visible:
		return
	var c := _context()
	if c != _ctx:
		_ctx = c
		_more = false
		_release_all()
		_thr = float(m.plane.throttle) if (c == "fly" and m != null and m.plane != null) else 0.0
	_layout()
	# the stick: x steers / rolls, up is forward (nose down, walk on, gas)
	var sv := _stick_v
	if _ctx == "fly" and bool(Game.tilt_fly):
		var g := Input.get_gravity()
		if g.length() > 1.0:
			if _tilt0 == Vector3.ZERO:
				_tilt0 = g
			var roll := atan2(g.x, -g.y) - atan2(_tilt0.x, -_tilt0.y)
			var pitch := atan2(g.z, -g.y) - atan2(_tilt0.z, -_tilt0.y)
			var k := 1.0 / deg_to_rad(TILT_DEG) * float(Game.tilt_gain)
			sv += Vector2(clampf(roll * k, -1.0, 1.0), clampf(-pitch * k, -1.0, 1.0))
	sv = sv.limit_length(1.0)
	_axis("roll_left", "roll_right", sv.x)
	_axis("pitch_up", "pitch_down", -sv.y)
	# vehicles: the slider's gas (up) and brake (down)
	if _ctx == "drive":
		_axis("throttle_down", "throttle_up", _thr)
	elif _ctx == "fly" and _thr_id < 0 and m != null and m.plane != null:
		_thr = float(m.plane.throttle)        # keys or a controller may have moved it
	# look: a drag is a nudge that dies away
	_axis("look_left", "look_right", clampf(_look_v.x, -1.0, 1.0))
	_axis("look_up", "look_down", clampf(_look_v.y, -1.0, 1.0))
	_look_v = _look_v.lerp(Vector2.ZERO, clampf(delta * 14.0, 0.0, 1.0))
	_root.queue_redraw()


func _release_all() -> void:
	for a in _pressed_axes.keys():
		Input.action_release(a)
	_pressed_axes.clear()
	for k in _held.keys():
		_release_button(k)
	_held.clear()
	_btn_ids.clear()
	_stick_id = -1
	_look_id = -1
	_thr_id = -1
	_stick_v = Vector2.ZERO
	_look_v = Vector2.ZERO


func _draw_all() -> void:
	if not visible:
		return
	var sz := _root.get_viewport_rect().size
	var s := clampf(sz.y / 720.0, 0.6, 2.0)
	var fill := Color(0.08, 0.09, 0.08, 0.35)
	var edge := Color(1, 1, 1, 0.45)
	var font := ThemeDB.fallback_font
	# stick: where the thumb is, or a ghost where it would go
	var c := _stick_c if _stick_id >= 0 else Vector2(sz.x * 0.14, sz.y * 0.72)
	_root.draw_circle(c, STICK_R * s, fill)
	_root.draw_arc(c, STICK_R * s, 0.0, TAU, 40, edge, 2.0 * s)
	_root.draw_circle(c + _stick_v * STICK_R * s, 34.0 * s, Color(1, 1, 1, 0.35 if _stick_id >= 0 else 0.18))
	# throttle
	if _ctx != "foot":
		var r := _thr_rect()
		_root.draw_rect(r, fill)
		_root.draw_rect(r, edge, false, 2.0 * s)
		var f := _thr if _ctx == "fly" else (_thr + 1.0) * 0.5
		var hy := r.position.y + r.size.y * (1.0 - f)
		if _ctx == "drive":
			_root.draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), edge, 1.0 * s)
		_root.draw_rect(Rect2(Vector2(r.position.x - 6.0 * s, hy - 10.0 * s), Vector2(r.size.x + 12.0 * s, 20.0 * s)), Color(0.95, 0.75, 0.25, 0.8))
		var lab := "THR %d%%" % int(round(_thr * 100.0)) if _ctx == "fly" else ("GAS" if _thr > 0.05 else ("BRAKE" if _thr < -0.05 else ""))
		_root.draw_string(font, r.position + Vector2(0, -8.0 * s), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), Color(1, 1, 1, 0.8))
	# buttons
	for b in _buttons:
		var br: Rect2 = b[3]
		var on := _held.has(b[0])
		_root.draw_rect(br, Color(0.95, 0.75, 0.25, 0.55) if on else fill)
		_root.draw_rect(br, edge, false, 2.0 * s)
		var txt: String = b[1]
		var fs := int(18 * s)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_root.draw_string(font, br.get_center() + Vector2(-tw * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
