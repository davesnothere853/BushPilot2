extends Control
## The hotbar along the bottom while on foot, and the backpack screen (Tab /
## pad LB). In the backpack: click a slot, then another, to swap them; or
## hover one and press 1-8 to put it on that hotbar key. Pad: D-pad moves,
## A picks up / puts down, B or LB closes. (DESIGN_NOTES 73.)

var inv: Node
var visible_bar := false          # main: on foot and not driving
var is_open := false
var _cursor := 0                  # slot under the pad cursor / mouse
var _held := -1                   # slot picked up to move
var _font: Font
const HOTBAR := 8
const PACK := 16
const CELL := 64.0
const GAP := 6.0
const PAPER := Color(0.08, 0.09, 0.08, 0.72)
const EDGE := Color(0.85, 0.80, 0.62, 0.5)
const HOT := Color(1.0, 0.82, 0.35)
const INK := Color(0.93, 0.91, 0.84)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func toggle() -> void:
	is_open = not is_open
	_held = -1
	_cursor = inv.active if inv != null else 0
	mouse_filter = Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _process(_d: float) -> void:
	var vs := get_viewport_rect().size
	if size != vs:
		position = Vector2.ZERO
		size = vs
		queue_redraw()
	if inv != null and inv.changed:
		inv.changed = false
		queue_redraw()


# ------------------------------------------------------------------------------
#  Layout
# ------------------------------------------------------------------------------
func _bar_rect(i: int) -> Rect2:
	var w := HOTBAR * CELL + (HOTBAR - 1) * GAP
	var x0 := (size.x - w) * 0.5
	var y0 := size.y - CELL - 18.0
	if is_open:
		y0 = size.y * 0.5 + 2.0 * (CELL + GAP) + 30.0
	return Rect2(x0 + i * (CELL + GAP), y0, CELL, CELL)


func _pack_rect(k: int) -> Rect2:
	var cols := 8
	var w := cols * CELL + (cols - 1) * GAP
	var x0 := (size.x - w) * 0.5
	var y0 := size.y * 0.5 - 1.0 * (CELL + GAP)
	return Rect2(x0 + (k % cols) * (CELL + GAP), y0 + (k / cols) * (CELL + GAP), CELL, CELL)


func _slot_rect(i: int) -> Rect2:
	return _bar_rect(i) if i < HOTBAR else _pack_rect(i - HOTBAR)


func _slot_at(p: Vector2) -> int:
	for i in range(inv.slots.size()):
		if _slot_rect(i).has_point(p):
			return i
	return -1


# ------------------------------------------------------------------------------
#  Drawing
# ------------------------------------------------------------------------------
func _draw() -> void:
	if inv == null or not (visible_bar or is_open):
		return
	if is_open:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
		var r0 := _pack_rect(0)
		_txt(Vector2(r0.position.x, r0.position.y - 34.0), "BACKPACK", 18, INK)
		_txt(Vector2(r0.position.x + 8 * (CELL + GAP) - GAP - 300.0, r0.position.y - 34.0),
			"%.1f / %.0f kg" % [inv.weight(), inv.MAX_KG], 18, INK if inv.weight() < inv.MAX_KG * 0.9 else HOT, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
		for k in range(PACK):
			_draw_slot(HOTBAR + k)
		var hint := "Click a slot, then another, to swap.  Hover and press 1-8 to put it on that key.  Pad: D-pad, A, B."
		_txt(Vector2(size.x * 0.5 - 450.0, _bar_rect(0).end.y + 16.0), hint, 14, INK.darkened(0.2), HORIZONTAL_ALIGNMENT_CENTER, 900.0)
		var cs: Dictionary = inv.slots[_cursor]
		if not cs.is_empty():
			var desc := "%s: %s" % [inv.item_name(String(cs["id"])), String(inv.spec(String(cs["id"]))[3])]
			_txt(Vector2(size.x * 0.5 - 450.0, _pack_rect(0).position.y - 64.0), desc, 15, INK, HORIZONTAL_ALIGNMENT_CENTER, 900.0)
	for i in range(HOTBAR):
		_draw_slot(i)
	if not is_open:
		var id: String = inv.in_hand()
		var r := _bar_rect(inv.active)
		if id != "":
			_txt(Vector2(r.get_center().x - 150.0, r.position.y - 26.0), inv.item_name(id), 16, INK, HORIZONTAL_ALIGNMENT_CENTER, 300.0)


func _draw_slot(i: int) -> void:
	var r := _slot_rect(i)
	draw_rect(r, PAPER)
	var edge := EDGE
	var wdt := 1.5
	if i < HOTBAR and i == inv.active:
		edge = HOT
		wdt = 3.0
	if is_open and i == _cursor:
		edge = Color(1, 1, 1, 0.9)
		wdt = 2.5
	if i == _held:
		edge = Color(0.5, 0.9, 1.0)
		wdt = 3.0
	draw_rect(r, edge, false, wdt)
	if i < HOTBAR:
		_txt(r.position + Vector2(4, 2), str(i + 1), 12, INK.darkened(0.25), HORIZONTAL_ALIGNMENT_LEFT, 20.0)
	var s: Dictionary = inv.slots[i]
	if s.is_empty():
		return
	_icon(String(s["id"]), r.grow(-12.0))
	if int(s["n"]) > 1:
		_txt(r.end - Vector2(26, 20), "x%d" % int(s["n"]), 13, INK, HORIZONTAL_ALIGNMENT_RIGHT, 24.0)


## Simple flat icons in the polyart palette.
func _icon(id: String, r: Rect2) -> void:
	var c := r.get_center()
	var ash := Color(0.72, 0.56, 0.36)
	var steel := Color(0.62, 0.64, 0.66)
	match id:
		"shovel":
			draw_line(c + Vector2(-16, 16), c + Vector2(8, -8), ash, 4.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(6, -14), c + Vector2(14, -6), c + Vector2(20, -18), c + Vector2(19, -21), c + Vector2(16, -22)]), steel)
			draw_line(c + Vector2(-20, 13), c + Vector2(-13, 20), steel, 3.0)
		"pick":
			draw_line(c + Vector2(-14, 18), c + Vector2(8, -6), ash, 4.0)
			draw_polyline(PackedVector2Array([c + Vector2(-8, -14), c + Vector2(6, -10), c + Vector2(18, -2)]), steel, 4.0)
		"gold_pan":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-20, -4), c + Vector2(20, -4), c + Vector2(13, 8), c + Vector2(-13, 8)]), Color(0.25, 0.26, 0.28))
			draw_circle(c + Vector2(4, 2), 2.5, Color(1.0, 0.82, 0.25))
		"ear_muffs":
			draw_arc(c + Vector2(0, 4), 15.0, PI + 0.25, TAU - 0.25, 12, Color(0.15, 0.15, 0.16), 4.0)
			for ex in [-15.0, 15.0]:
				draw_circle(c + Vector2(ex, 8), 7.0, Color(0.92, 0.74, 0.08))
				draw_circle(c + Vector2(ex * 0.82, 8), 4.0, Color(0.08, 0.08, 0.08))
		"headlamp":
			draw_arc(c, 15.0, 0.2, PI - 0.2, 12, Color(0.2, 0.2, 0.2), 4.0)
			draw_rect(Rect2(c + Vector2(-6, -18), Vector2(12, 9)), Color(0.9, 0.75, 0.15))
		"ladder":
			draw_line(c + Vector2(-8, -20), c + Vector2(-8, 20), Color(0.6, 0.5, 0.3), 3.0)
			draw_line(c + Vector2(8, -20), c + Vector2(8, 20), Color(0.6, 0.5, 0.3), 3.0)
			for rr in range(5):
				draw_line(c + Vector2(-8, -16 + 8 * rr), c + Vector2(8, -16 + 8 * rr), Color(0.5, 0.38, 0.22), 3.0)
		"pump":
			draw_rect(Rect2(c + Vector2(-14, -8), Vector2(28, 18)), Color(0.75, 0.15, 0.1))
			draw_rect(Rect2(c + Vector2(-18, 10), Vector2(36, 4)), Color(0.15, 0.15, 0.15))
			draw_arc(c + Vector2(16, 0), 8.0, -1.4, 1.4, 8, Color(0.2, 0.2, 0.2), 3.0)
		"timber":
			draw_rect(Rect2(c + Vector2(-16, -10), Vector2(6, 26)), Color(0.6, 0.45, 0.28))
			draw_rect(Rect2(c + Vector2(10, -10), Vector2(6, 26)), Color(0.6, 0.45, 0.28))
			draw_rect(Rect2(c + Vector2(-20, -16), Vector2(40, 7)), Color(0.5, 0.37, 0.22))
		"pistol":
			var gun := Color(0.16, 0.16, 0.18)
			draw_rect(Rect2(c + Vector2(-20, -12), Vector2(36, 9)), gun)                       # slide
			draw_rect(Rect2(c + Vector2(-20, -3), Vector2(26, 4)), gun.lightened(0.1))        # frame
			draw_colored_polygon(PackedVector2Array([c + Vector2(4, 0), c + Vector2(15, 0), c + Vector2(19, 18), c + Vector2(8, 18)]), Color(0.36, 0.22, 0.12))   # grip
			draw_arc(c + Vector2(0, 2), 5.0, 0.0, PI, 8, gun, 2.0)                            # trigger guard
			draw_rect(Rect2(c + Vector2(-21, -10), Vector2(2, 3)), Color(0.02, 0.02, 0.02))
		"dynamite":
			# three buff sticks with red bands, a fuse curling off the top one
			for di in range(3):
				var o2 := c + Vector2(-9 + di * 9, 4 - (6 if di == 1 else 0))
				draw_rect(Rect2(o2 + Vector2(-4, -14), Vector2(8, 28)), Color(0.80, 0.68, 0.46))
				draw_rect(Rect2(o2 + Vector2(-4, -3), Vector2(8, 5)), Color(0.66, 0.12, 0.08))
			draw_polyline(PackedVector2Array([c + Vector2(0, -16), c + Vector2(4, -20), c + Vector2(1, -23), c + Vector2(6, -26)]), Color(0.15, 0.13, 0.12), 2.0)
			draw_circle(c + Vector2(6, -26), 2.0, Color(1.0, 0.75, 0.3))
		"rail":
			draw_line(c + Vector2(-20, -6), c + Vector2(20, -6), steel, 3.0)
			draw_line(c + Vector2(-20, 6), c + Vector2(20, 6), steel, 3.0)
			for tx in [-14, -4, 6, 16]:
				draw_line(c + Vector2(tx, -11), c + Vector2(tx - 2, 11), Color(0.45, 0.33, 0.2), 3.0)
		"gas_can", "gas_can_empty":
			var red := Color(0.78, 0.14, 0.10) if id == "gas_can" else Color(0.55, 0.22, 0.18)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-13, -10), c + Vector2(8, -10), c + Vector2(13, -4), c + Vector2(13, 18), c + Vector2(-13, 18)]), red)
			draw_line(c + Vector2(8, -10), c + Vector2(17, -19), Color(0.15, 0.15, 0.15), 3.0)
			draw_rect(Rect2(c + Vector2(-9, -16), Vector2(12, 4)), red.darkened(0.3))
		"generator":
			draw_rect(Rect2(c + Vector2(-16, -10), Vector2(32, 22)), Color(0.85, 0.65, 0.12))
			draw_rect(Rect2(c + Vector2(-18, -14), Vector2(36, 4)), Color(0.2, 0.2, 0.2))
			draw_circle(c + Vector2(-6, 2), 5.0, Color(0.25, 0.25, 0.25))
		"rope_light":
			var pts := PackedVector2Array()
			for i in range(9):
				pts.append(c + Vector2(-18 + i * 4.5, sin(float(i) * 1.3) * 7.0))
			draw_polyline(pts, Color(0.2, 0.2, 0.2), 2.0)
			for q in pts:
				draw_circle(q, 2.5, Color(1.0, 0.85, 0.4))
		"gold_bar":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-16, 8), c + Vector2(16, 8), c + Vector2(11, -6), c + Vector2(-11, -6)]), Color(0.95, 0.75, 0.2))
			draw_line(c + Vector2(-11, -6), c + Vector2(11, -6), Color(1.0, 0.92, 0.55), 2.0)
		"coin":
			draw_circle(c, 11.0, Color(0.75, 0.76, 0.78))
			draw_arc(c, 8.0, 0.0, TAU, 16, Color(0.55, 0.56, 0.58), 1.5)
		"bottle":
			draw_rect(Rect2(c + Vector2(-6, -4), Vector2(12, 22)), Color(0.35, 0.55, 0.45, 0.9))
			draw_rect(Rect2(c + Vector2(-3, -16), Vector2(6, 12)), Color(0.35, 0.55, 0.45, 0.9))
		"relic_pan":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-20, -4), c + Vector2(20, -4), c + Vector2(13, 8), c + Vector2(-13, 8)]), Color(0.45, 0.28, 0.15))
		"bison_skull":
			draw_circle(c + Vector2(0, 2), 9.0, Color(0.88, 0.84, 0.72))
			draw_arc(c + Vector2(-12, -4), 8.0, PI, PI * 1.8, 8, Color(0.3, 0.27, 0.22), 3.0)
			draw_arc(c + Vector2(12, -4), 8.0, PI * 1.2, TAU, 8, Color(0.3, 0.27, 0.22), 3.0)
		"tusk":
			draw_arc(c + Vector2(4, 10), 18.0, PI * 1.05, PI * 1.75, 12, Color(0.9, 0.85, 0.7), 5.0)
		_:
			# a part off the shelves: a parts box
			draw_rect(Rect2(c + Vector2(-15, -9), Vector2(30, 20)), Color(0.62, 0.48, 0.30))
			draw_rect(Rect2(c + Vector2(-15, -9), Vector2(30, 4)), Color(0.80, 0.72, 0.52))


func _txt(pos: Vector2, t: String, sz: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = 200.0) -> void:
	draw_string(_font, pos + Vector2(1, sz + 1), t, align, w, sz, Color(0, 0, 0, 0.7))
	draw_string(_font, pos + Vector2(0, sz), t, align, w, sz, col)


# ------------------------------------------------------------------------------
#  Input while the backpack is open
# ------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not is_open or inv == null:
		return
	var used := false
	if event.is_action_pressed("inventory") or event.is_action_pressed("menu") or (event is InputEventJoypadButton and event.pressed and ((event as InputEventJoypadButton).button_index == JOY_BUTTON_B or (event as InputEventJoypadButton).button_index == JOY_BUTTON_BACK)):
		toggle()
		used = true
	elif event is InputEventMouseMotion:
		var k := _slot_at((event as InputEventMouseMotion).position)
		if k >= 0 and k != _cursor:
			_cursor = k
			queue_redraw()
		used = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var k2 := _slot_at((event as InputEventMouseButton).position)
		if k2 >= 0:
			_cursor = k2
			_pick_or_put()
		used = true
	elif event is InputEventKey and event.pressed and not event.echo:
		var kc: int = (event as InputEventKey).physical_keycode
		if kc >= KEY_1 and kc <= KEY_8:
			var dst := kc - KEY_1
			if dst != _cursor:
				inv.swap(_cursor, dst)
			used = true
	elif event is InputEventJoypadButton and event.pressed:
		var bi: int = (event as InputEventJoypadButton).button_index
		match bi:
			JOY_BUTTON_DPAD_LEFT:
				_move(-1, 0)
			JOY_BUTTON_DPAD_RIGHT:
				_move(1, 0)
			JOY_BUTTON_DPAD_UP:
				_move(0, -1)
			JOY_BUTTON_DPAD_DOWN:
				_move(0, 1)
			JOY_BUTTON_A:
				_pick_or_put()
		used = true
	if used:
		get_viewport().set_input_as_handled()


func _pick_or_put() -> void:
	if _held < 0:
		if not (inv.slots[_cursor] as Dictionary).is_empty():
			_held = _cursor
	else:
		if _held != _cursor:
			inv.swap(_held, _cursor)
		_held = -1
	queue_redraw()


## Pad cursor: rows are pack row 0, pack row 1, hotbar.
func _move(dx: int, dy: int) -> void:
	var row: int
	var col: int
	if _cursor < HOTBAR:
		row = 2
		col = _cursor
	else:
		row = (_cursor - HOTBAR) / 8
		col = (_cursor - HOTBAR) % 8
	col = posmod(col + dx, 8)
	row = posmod(row + dy, 3)
	_cursor = col if row == 2 else HOTBAR + row * 8 + col
	queue_redraw()
