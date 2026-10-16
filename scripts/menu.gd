extends CanvasLayer

const Gear = preload("res://scripts/gear.gd")
const Liveries = preload("res://scripts/liveries.gd")

const TYRE_NOTES := {
	"wskis": "Skis with the wheels poking through: skis down (L) for snow, ice and water (they skim beautifully), up for gravel and grass. Heavy and draggy.",
	"std": "Light and slick in the air, but small hard tyres sink into mud and snow and hate rocks.",
	"850": "A good all-rounder for gravel and grass.",
	"26": "Rolls over rough ground and soft spots that would stop smaller tyres. A little slower in cruise.",
	"29": "Big and soft: soaks up rocks and floats on mud and snow. Heavier, and draggier in the air.",
	"31": "The biggest bush tyres. Lands almost anywhere, short and soft. The heaviest and slowest in cruise.",
}
const LEG_NOTES := {
	"spring": "Light and tough, but springy: land flat and fast and it will bounce you back into the air.",
	"oleo": "Damped struts that soak up a firm arrival without bouncing. Heavier.",
	"amphib": "Floats with wheels that fold up into them: land on water or a runway. Wheels up (L) for water, down for land. Heavy and slow, so plan on less payload.",
}
## Pause menu: pick an airstrip, load the aeroplane, change season, weather and realism.
## The game is paused while it is open.

const Terrain = preload("res://scripts/terrain.gd")

signal start_requested(strip: int, on_approach: bool)
signal dock_requested(dock: int)
signal reset_requested
signal tutorial_requested
signal story_requested
signal closed

const LB := 2.20462
const GAL_KG := 2.72

var plane: Node3D
var terrain: RefCounted
var jobs: Node                 # jobs.gd: the job board
var fleet: Node                # fleet.gd: the planes you own
var net: Node                  # net.gd: co-op
var mining: Node               # mining.gd: your claims
var builds: Node               # builds.gd: strips, cabins, hangars, camps you put up
var walker: Node3D             # the pilot on foot (where to build)
var service: Node             # engine_service.gd: working on the engine
var prospect: Node            # prospect.gd: gold, pans, sluices, wash plants
var rails: Node                # mine_rails.gd
var repaint: Callable         # main._repaint_active: respray the plane you're in
var save_all: Callable        # main._save_all: write the whole game to disk now
var new_game: Callable        # main._new_game: wipe the career and start over
var engine_part := ""         # the part the engine page is about
var workshop: Callable        # main._workshop_vehicles: what's parked at the workshop (DESIGN_NOTES 111)
var repairs: Callable         # main._repair_list: damaged machines and the bill to fix each (DESIGN_NOTES 137)
var _ws_i := 0
var _ws_slot := ""
var is_open := false
var first_open := true

var _root: Control
var _dim: ColorRect
var _centre: CenterContainer
## (DESIGN_NOTES 188) the main menu as a cockpit: menu_cockpit.gd shows this page's
## buttons as switches and its sliders as levers. Only when the menu is opened at
## its main page (the pause / start menu), not the quick menu or build pages.
const CockpitScript = preload("res://scripts/menu_cockpit.gd")
var cockpit: Control
var settle_check: Callable          # main: the world round you has streamed in
var _cockpit_session := false
var _hid_3d := false
var _content: VBoxContainer
var _scroll: ScrollContainer
var _panel: PanelContainer
var _page := "main"
var _listen_action := ""
var _listen_slot := -1
var _bind_buttons: Dictionary = {}     # "action:slot" -> Button
var _bind_note: Label
var _axes_label: Label
# Flight gear setup
var _wiz: Array = []            # axis ids still to set
var _wiz_phase := 0
var _wiz_first: Dictionary = {}
var _wiz_label: Label
var _wiz_box: Control
var _hotas_note: Label


## A live bar for one flight-gear axis.
class AxisBar:
	extends Control
	var id := ""

	func _init() -> void:
		custom_minimum_size = Vector2(150, 18)

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 3, w, h - 6), Color(0.16, 0.16, 0.17))
		var hz: Node = Game.hotas
		if not hz.has_axis(id):
			return
		var v: float = hz.value(id)
		var col := Color(0.82, 0.42, 0.12)
		if hz.kind_of(id) == "lever":
			draw_rect(Rect2(0, 3, w * v, h - 6), col)
		else:
			var mid := w * 0.5
			draw_rect(Rect2(minf(mid, mid + v * mid), 3, absf(v) * mid, h - 6), col)
			draw_rect(Rect2(mid - 1, 1, 2, h - 2), Color(0.7, 0.7, 0.66))


class BalanceBar:
	extends Control
	var fraction := 0.5

	func _init() -> void:
		custom_minimum_size = Vector2(420, 34)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# The bar shows from a little ahead of the forward limit to a little behind the aft one.
		var lo := -0.35
		var hi := 1.35
		var x_fwd := (0.0 - lo) / (hi - lo) * w
		var x_aft := (1.0 - lo) / (hi - lo) * w
		draw_rect(Rect2(0, 8, w, h - 16), Color(0.45, 0.14, 0.12))
		draw_rect(Rect2(x_fwd, 8, x_aft - x_fwd, h - 16), Color(0.20, 0.50, 0.24))
		var x := clampf((fraction - lo) / (hi - lo), 0.0, 1.0) * w
		draw_rect(Rect2(x - 3, 2, 6, h - 4), Color(0.95, 0.93, 0.88))


const ORANGE := Color(0.92, 0.45, 0.12)
const CREAM := Color(0.94, 0.90, 0.80)
const CREAM_DIM := Color(0.62, 0.60, 0.52)
const BOARD := Color(0.11, 0.14, 0.12)


## The menus' look (DESIGN_NOTES 163): DIN lettering (Bahnschrift on
## Windows, like the placards and charts), dark board buttons with a cream
## keyline down the left that turns hazard orange and thickens when picked -
## easy to see where a controller is.
static func _make_theme() -> Theme:
	var theme := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "DIN Alternate", "DIN", "Roboto Condensed", "Arial Narrow", "Segoe UI"])
	f.font_weight = 500
	theme.default_font = f
	theme.default_font_size = 18
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = BOARD
		sb.border_color = Color(0.40, 0.40, 0.34)
		sb.border_width_left = 3
		match state:
			"hover":
				sb.bg_color = Color(0.20, 0.17, 0.12)
				sb.border_color = ORANGE
				sb.border_width_left = 6
			"focus":
				sb.bg_color = Color(0.24, 0.15, 0.08)
				sb.border_color = ORANGE
				sb.set_border_width_all(1)
				sb.border_width_left = 8
			"pressed":
				sb.bg_color = Color(0.78, 0.36, 0.10)
				sb.border_color = CREAM
				sb.border_width_left = 8
			"disabled":
				sb.bg_color = Color(0.08, 0.10, 0.09)
				sb.border_color = Color(0.22, 0.24, 0.22)
		sb.set_corner_radius_all(1)
		sb.content_margin_left = 18
		sb.content_margin_right = 16
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		theme.set_stylebox(state, "Button", sb)
		if state != "focus":
			theme.set_stylebox(state, "OptionButton", sb)
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", Color(1, 0.97, 0.9))
	theme.set_color("font_focus_color", "Button", Color(1, 0.97, 0.9))
	theme.set_color("font_pressed_color", "Button", Color(0.08, 0.06, 0.04))
	theme.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.40))
	theme.set_color("font_color", "Label", CREAM)
	theme.set_color("font_color", "OptionButton", CREAM)
	# sliders: a dark slot, an orange fill, a cream tab
	var slot := StyleBoxFlat.new()
	slot.bg_color = Color(0.05, 0.06, 0.055)
	slot.content_margin_top = 3
	slot.content_margin_bottom = 3
	theme.set_stylebox("slider", "HSlider", slot)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ORANGE
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	# a thin orange scroll bar
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(0.05, 0.06, 0.055)
	bar.content_margin_left = 3
	bar.content_margin_right = 3
	theme.set_stylebox("scroll", "VScrollBar", bar)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.62, 0.30, 0.10)
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	theme.set_stylebox("grabber", "VScrollBar", grab)
	var grab_h := grab.duplicate()
	grab_h.bg_color = ORANGE
	theme.set_stylebox("grabber_highlight", "VScrollBar", grab_h)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grab_h)
	return theme


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var theme := _make_theme()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = theme
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.02, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_dim = dim

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)
	_centre = centre

	var panel := PanelContainer.new()
	# (DESIGN_NOTES 163) a bush plane's cockpit placard: dark spruce-green
	# board, a hazard-orange band across the top like the trim stripe, a thin
	# cream keyline, square corners, a heavy shadow
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.065, 0.085, 0.075, 0.97)
	box.border_color = CREAM_DIM
	box.set_border_width_all(1)
	box.border_width_top = 7
	box.border_color = ORANGE
	box.set_corner_radius_all(2)
	box.shadow_color = Color(0, 0, 0, 0.55)
	box.shadow_size = 22
	box.shadow_offset = Vector2(0, 8)
	box.set_content_margin_all(28)
	box.content_margin_top = 30
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(620, 0)
	centre.add_child(panel)
	_panel = panel

	# Long pages scroll inside the panel (mouse wheel, scroll bar, or a
	# controller moving focus down the page).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	panel.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)


## Take over the cockpit main.gd showed while the world was being built, so the
## one on screen simply comes alive (no second build, no jump).
func adopt_cockpit(c: Control) -> void:
	if c == null:
		return
	if cockpit != null and cockpit != c:
		cockpit.queue_free()
	cockpit = c
	if c.get_parent() != null:
		c.get_parent().remove_child(c)
	_root.add_child(c)
	_root.move_child(c, 0)
	c.boot = false
	c.menu = self
	c.settle_check = settle_check
	c.visible = false


func _ensure_cockpit() -> void:
	if cockpit != null:
		return
	cockpit = CockpitScript.new()
	cockpit.menu = self
	cockpit.settle_check = settle_check
	_root.add_child(cockpit)
	_root.move_child(cockpit, 0)


func open(page: String = "main") -> void:
	is_open = true
	visible = true
	_cockpit_session = page == "main" and not Game.get("menu_cockpit_off")
	if _cockpit_session:
		_ensure_cockpit()
		cockpit.settle_check = settle_check
		cockpit.plane = plane
		cockpit.visible = true
		# the game's own world isn't drawn under the cockpit (it's hidden anyway)
		var vp := get_viewport()
		if vp != null and not vp.disable_3d:
			vp.disable_3d = true
			_hid_3d = true
	elif cockpit != null:
		cockpit.visible = false
	# The game pauses under the menu, so free the mouse here (walking captures it).
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_show(page)


func close() -> void:
	is_open = false
	visible = false
	if cockpit != null:
		cockpit.visible = false
		cockpit.active = false
		cockpit.show_sliders([])
	# the world is always drawn again when the menu closes (it was left grey if
	# the menu had been opened twice)
	_hid_3d = false
	var vp := get_viewport()
	if vp != null:
		vp.disable_3d = false
	_cockpit_session = false
	first_open = false
	get_tree().paused = false
	closed.emit()


func _input(event: InputEvent) -> void:
	# During flight gear setup, any button on the stick or throttle means "Next"
	# (your hand is busy holding the stick over).
	if is_open and _page == "hotas" and not _wiz.is_empty() and event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		get_viewport().set_input_as_handled()
		_wiz_next()
		return
	# While waiting for a new binding, the next key, button or stick push is captured
	# here before the menu itself can react to it.
	if not is_open or _listen_action == "":
		return
	if _listen_slot == 3:
		if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_stop_listening("Cancelled.")
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey:
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
			get_viewport().set_input_as_handled()
			var jb := event as InputEventJoypadButton
			if Game._looks_like_gamepad(Input.get_joy_name(jb.device)) and not Game.hotas.gear_ids().has(jb.device):
				_bind_note.text = "That's a gamepad. Use the Controller column for it; this one is for a flight stick or throttle."
				return
			var act := _listen_action
			var took: String = Game.hotas.bind_button(act, jb)
			var msg2 := "%s set to %s." % [Game.action_label(act), Game.hotas.button_name(act)]
			if took != "":
				msg2 += "  (Removed from %s.)" % Game.action_label(took)
			_stop_listening(msg2)
		return
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_stop_listening("Cancelled.")
		get_viewport().set_input_as_handled()
		return
	var b: Dictionary = Game.event_to_binding(event)
	if b.is_empty():
		if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	var wants_pad := _listen_slot == 2
	var is_pad: bool = b["t"] != "key"
	if wants_pad != is_pad:
		_bind_note.text = "That slot is for a controller. Press a button or push a stick." if wants_pad else "That slot is for the keyboard. Press a key."
		return
	var action := _listen_action
	var taken: String = Game.set_binding(action, _listen_slot, b)
	var msg := "%s set to %s." % [Game.action_label(action), Game.binding_name(b)]
	if taken != "":
		msg += "  (Removed from %s.)" % taken
	_stop_listening(msg)


func _stop_listening(note: String) -> void:
	var key := "%s:%d" % [_listen_action, _listen_slot]
	_listen_action = ""
	_listen_slot = -1
	_refresh_bindings()
	if _bind_note != null:
		_bind_note.text = note
	if _bind_buttons.has(key):
		(_bind_buttons[key] as Button).grab_focus()


## Live readout of the chosen controller's sticks and triggers, to spot drift.
func _process(_delta: float) -> void:
	if _axes_label == null or not is_instance_valid(_axes_label):
		return
	var dev: int = Game.active_device()
	if Input.get_connected_joypads().is_empty():
		_axes_label.text = "No controller connected."
		return
	if dev == -1:
		dev = Input.get_connected_joypads()[0]
	_axes_label.text = "Live: left stick %+.2f %+.2f   right stick %+.2f %+.2f   LT %.2f   RT %.2f" % [
		Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y),
		Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y),
		Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT), Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT)]


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or _listen_action != "":
		return
	if event.is_action_pressed("menu"):
		if _page != "main":
			_show("main")
		else:
			close()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------------------
#  Small builders
# ------------------------------------------------------------------------------
func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()


func _label(text: String, size_px: int = 18, col: Color = Color(0.92, 0.92, 0.88)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(l)
	if size_px >= 22:
		# a heading: heavy, spaced out like a placard, a short orange rule under it
		l.add_theme_font_override("font", _heading_font(3 if size_px < 40 else 8))
		var rule := ColorRect.new()
		rule.color = Color(ORANGE.r, ORANGE.g, ORANGE.b, 0.8)
		rule.custom_minimum_size = Vector2(0, 2)
		_content.add_child(rule)
	return l


static var _hfonts := {}
static func _heading_font(spacing: int) -> Font:
	if _hfonts.has(spacing):
		return _hfonts[spacing]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "DIN Alternate", "DIN", "Roboto Condensed", "Arial Narrow", "Segoe UI"])
	f.font_weight = 700
	var v := FontVariation.new()
	v.base_font = f
	v.spacing_glyph = spacing
	_hfonts[spacing] = v
	return v


func _button(text: String, action: Callable, parent: Node = null) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	# long lines (a part with its price, what it does and why it won't fit)
	# wrap inside the menu instead of pushing it wider than the screen
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if parent is HBoxContainer or parent is FlowContainer:
		# Side by side in a row (vehicle tabs, the airstrip list's buttons):
		# wrapping let a row squeeze them to slivers with the text gone, so
		# they keep their words on one line.
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.size_flags_horizontal = Control.SIZE_FILL     # as wide as its words
	b.pressed.connect(action)
	if parent == null:
		_content.add_child(b)
	else:
		parent.add_child(b)
	return b


func _spacer(h: float = 8.0) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	_content.add_child(s)


func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	_content.add_child(row)
	return row


## The quick menu (DESIGN_NOTES 162): on a controller (LB in the plane or a
## machine) every switch and job that has no button of its own.
var quick_items: Callable          # main: -> [[label, Callable], ...] for where you are now
func _page_quick() -> void:
	_label("QUICK MENU", 26, Color(0.90, 0.50, 0.18))
	var items: Array = quick_items.call() if quick_items.is_valid() else []
	for it in items:
		var cb: Callable = it[1]
		_button(String(it[0]), func():
			close()
			cb.call())
	_spacer()
	_button("Close", close)


## Save slots (DESIGN_NOTES 169).
var slots_host: Node               # main: slot_info, save_to_slot, load_slot
func _page_slots() -> void:
	_label("SAVE SLOTS", 26, Color(0.90, 0.50, 0.18))
	_label("Save the game you're playing into a slot, or load one (the game you're in is replaced by it: save it first if you want it).", 14, Color(0.7, 0.7, 0.66))
	for n in range(1, int(slots_host.SLOTS) + 1):
		var nn := n
		var info: String = slots_host.slot_info(n)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := Label.new()
		l.text = "Slot %d:  %s" % [n, info]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		if not first_open:
			_button("Save here", func():
				_toast(slots_host.save_to_slot(nn))
				_show("slots"), row)
		if info != "empty":
			_button("Load", func():
				close()
				slots_host.load_slot(nn), row)
		_content.add_child(row)
	_back()


func _back() -> void:
	_spacer()
	_button("Back", func(): _show("main"))


func _show(page: String) -> void:
	_page = page
	_clear()
	_listen_action = ""
	_listen_slot = -1
	_bind_buttons.clear()
	_bind_note = null
	_axes_label = null
	_wiz.clear()
	_wiz_label = null
	_wiz_box = null
	_hotas_note = null
	var width := 620
	if page == "workshop":
		width = 980
	if page == "strips":
		width = 980
	elif page == "controls":
		width = 1060
	elif page == "hotas":
		width = 960
	# never wider than the window (less a margin), whatever the page wants
	var vw := get_viewport().get_visible_rect().size.x if is_inside_tree() else float(width)
	width = int(minf(float(width), vw - 40.0))
	_panel.custom_minimum_size = Vector2(width, 0)
	_panel.size = Vector2.ZERO
	match page:
		"strips":
			_page_strips()
		"load":
			_page_load()
		"jobs":
			_page_jobs()
		"settings":
			_page_settings()
		"controls":
			_page_controls()
		"hotas":
			_page_hotas()
		"fleet":
			_page_fleet()
		"newgame":
			_page_newgame()
		"coop":
			_page_coop()
		"build":
			_page_build()
		"graphics":
			_page_graphics()
		"help":
			_page_help()
		"engine":
			_page_engine()
		"workshop":
			_page_workshop()
		"quick":
			_page_quick()
		"slots":
			_page_slots()
		_:
			_page_main()
	_cockpit_sync(page)
	_focus_first.call_deferred()
	_fit_scroll.call_deferred()


## Main page: the cockpit IS the menu (the list is hidden). Other pages: the list
## sits over the cockpit, and its sliders become levers on the quadrant.
func _cockpit_sync(page: String) -> void:
	if not _cockpit_session or cockpit == null:
		_centre.visible = true
		_dim.visible = true
		_dim.color = Color(0.015, 0.025, 0.02, 0.62)
		return
	var main_page := page == "main" or page == ""
	_centre.visible = not main_page
	_dim.visible = not main_page
	_dim.color = Color(0.0, 0.0, 0.0, 0.45)
	cockpit.active = main_page
	var btns: Array = []
	var sliders: Array = []
	_collect(_content, btns, sliders)
	if main_page:
		cockpit.show_buttons(btns)
		cockpit.show_sliders([])
	else:
		cockpit.show_sliders(sliders)


func _collect(node: Node, btns: Array, sliders: Array) -> void:
	for c in node.get_children():
		if c is Button:
			btns.append(c)
		elif c is HSlider:
			sliders.append(c)
		else:
			_collect(c, btns, sliders)


## Make the panel as tall as its page, but never taller than the screen.
func _fit_scroll() -> void:
	if _scroll == null:
		return
	await get_tree().process_frame
	var want: float = _content.get_combined_minimum_size().y + 4.0
	# Only the part of the window that is actually on screen counts: a window
	# can run under the taskbar or past the bottom of the display.
	var vp_h: float = _root.get_viewport_rect().size.y
	var win := get_window()
	var frac := 1.0
	if win != null and win.size.y > 0:
		var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
		var bottom: int = mini(win.position.y + win.size.y, usable.position.y + usable.size.y)
		var top: int = maxi(win.position.y, usable.position.y)
		frac = clampf(float(bottom - top) / float(win.size.y), 0.4, 1.0)
	var room: float = vp_h * frac * 0.84 - 60.0
	_scroll.custom_minimum_size = Vector2(0, minf(want, room))
	_scroll.scroll_vertical = 0


## Give a controller something to start from: focus the first button on the page.
func _focus_first() -> void:
	if _cockpit_session and (_page == "main" or _page == ""):
		return          # the cockpit has the focus (its own highlight)
	if _keep_focus != null and is_instance_valid(_keep_focus) and _keep_focus.is_inside_tree():
		_keep_focus.grab_focus()
		_keep_focus = null
		return
	_keep_focus = null
	var first := _find_button(_content)
	if first != null:
		first.grab_focus()


func _find_button(node: Node) -> Control:
	for c in node.get_children():
		if c is Button or c is HSlider or c is OptionButton:
			return c
		var found := _find_button(c)
		if found != null:
			return found
	return null


# ------------------------------------------------------------------------------
#  Pages
# ------------------------------------------------------------------------------
func _page_main() -> void:
	var title := _label("BUSH PILOT", 52, ORANGE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label("SOMEWHERE NORTH OF SIXTY  ·  1988  ·  FLY  HAUL  MINE  LOG", 14, CREAM_DIM)
	sub.add_theme_font_override("font", _heading_font(2))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spacer(10)
	_button("Start" if first_open else "Resume", close)
	if jobs != null and not first_open:
		_button("Job board", func(): _show("jobs"))
	if fleet != null and not first_open:
		_button("Your planes", func(): _show("fleet"))
	if workshop.is_valid() and not first_open:
		_button("Workshop: parts and tuning", func():
			_ws_slot = ""
			_show("workshop"))
	_button("How to play", func(): _show("help"))
	_button("Travel: airstrips and docks", func(): _show("strips"))
	_button("Plane load and fuel", func(): _show("load"))
	if net != null:
		_button("Co-op (play with friends)", func(): _show("coop"))
	if plane != null and plane.is_twin() and not first_open:
		var frow := HBoxContainer.new()
		frow.add_theme_constant_override("separation", 10)
		_content.add_child(frow)
		_button("Fail left engine", func():
			plane.fail_engine(0, "Practice failure.")
			close(), frow)
		_button("Fail right engine", func():
			plane.fail_engine(1, "Practice failure.")
			close(), frow)
		_button("Restart engines", func():
			plane.restart_engine(0)
			plane.restart_engine(1)
			close(), frow)
	if not first_open and save_all.is_valid():
		_button("Save game", func():
			save_all.call()
			_toast("Saved."))
	var guest: bool = net != null and net.has_method("is_guest") and net.is_guest()
	if slots_host != null and not first_open and not guest:
		_button("Save slots: save / load", func(): _show("slots"))
	elif slots_host != null and not guest:
		_button("Load a saved game", func(): _show("slots"))
	if new_game.is_valid() and not guest:
		_button("New game (start over)", func(): _show("newgame"))
	_button("Season, weather and realism", func(): _show("settings"))
	_button("Graphics", func(): _show("graphics"))
	_button("Controls and controller", func(): _show("controls"))
	if not first_open:
		_button("Start over at the last airstrip", func():
			reset_requested.emit()
			close())
	_spacer(6)
	_button("Quit to desktop", func(): get_tree().quit())


func _page_strips() -> void:
	_label("AIRSTRIPS", 26, Color(0.90, 0.50, 0.18))
	_label("Start on the runway, or in the air lined up to land.", 15, Color(0.70, 0.70, 0.66))
	for k in range(terrain.strips.size()):
		var s: Dictionary = terrain.strips[k]
		var p: Vector3 = s["pos"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_l := Label.new()
		name_l.text = "%s   (difficulty %d of 5)" % [s["name"], int(s["difficulty"])]
		info.add_child(name_l)
		var det := Label.new()
		det.text = "%d m %s, %d ft.  %s" % [int(s["length"]), Terrain.SURFACE_NAMES[int(s["surface"])], int(p.y * 3.28084), s["desc"]]
		det.add_theme_font_size_override("font_size", 13)
		det.add_theme_color_override("font_color", Color(0.66, 0.66, 0.62))
		info.add_child(det)
		row.add_child(info)
		_button("On the runway", func(): _start(k, false), row)
		_button("On approach", func(): _start(k, true), row)
		_content.add_child(row)
	if not terrain.docks.is_empty():
		_spacer(4.0)
		_label("SEAPLANE DOCKS  (start on the water: amphibious floats are fitted for you)", 18, Color(0.90, 0.50, 0.18))
		for di in range(terrain.docks.size()):
			var d: Dictionary = terrain.docks[di]
			var drow := HBoxContainer.new()
			drow.add_theme_constant_override("separation", 10)
			var dl := Label.new()
			dl.text = "%s   %s, fuel at the pump" % [d["name"], "on the coast" if int(d["lake"]) < 0 else "on " + String(terrain.lakes[int(d["lake"])]["name"])]
			dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			drow.add_child(dl)
			_button("On the water", func():
				dock_requested.emit(di)
				close(), drow)
			_content.add_child(drow)
	_back()


func _start(k: int, on_approach: bool) -> void:
	start_requested.emit(k, on_approach)
	close()


## $ a gallon here: the town pump, or a bush cache at any other strip or dock.
func fuel_price() -> float:
	var k: int = jobs.strip_here() if jobs != null else -1
	if k >= 0 and bool(terrain.strips[k]["fuel"]):
		return 2.4
	return 4.8


func _page_load() -> void:
	_label("LOAD AND FUEL", 26, Color(0.90, 0.50, 0.18))
	var can_load: bool = plane.on_ground and plane.ground_speed < 1.0 and not plane.is_crashed
	if not can_load:
		_label("You can only change the load on the ground, stopped.", 15, Color(1.0, 0.62, 0.12))
	_label("%s.  Empty %d lb, maximum %d lb.  Weight behind the wing moves the balance point aft: the plane gets twitchy in pitch, and past the limit it will not recover from a stall." % [
		plane.type_name, int(round(plane.empty_mass * LB)), int(round(plane.max_mass * LB))], 14, Color(0.70, 0.70, 0.66))

	var summary := Label.new()
	var bar := BalanceBar.new()

	var fuel_row := _row("Fuel")
	var fuel_s := HSlider.new()
	fuel_s.min_value = 0.0
	fuel_s.max_value = floorf(plane.fuel_capacity / GAL_KG)
	fuel_s.step = 1.0
	fuel_s.value = round(plane.fuel / GAL_KG)
	fuel_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuel_s.editable = can_load
	var fuel_l := Label.new()
	fuel_l.custom_minimum_size = Vector2(110, 0)
	fuel_row.add_child(fuel_s)
	fuel_row.add_child(fuel_l)

	var front_row := _row("Cabin cargo")
	var front_s := HSlider.new()
	front_s.min_value = 0.0
	front_s.max_value = round(plane.cargo_front_max * LB / 5.0) * 5.0
	front_s.step = 5.0
	front_s.value = round(plane.cargo_front * LB / 5.0) * 5.0
	front_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	front_s.editable = can_load
	var front_l := Label.new()
	front_l.custom_minimum_size = Vector2(110, 0)
	front_row.add_child(front_s)
	front_row.add_child(front_l)

	var rear_row := _row("Aft baggage bay")
	var rear_s := HSlider.new()
	rear_s.min_value = 0.0
	rear_s.max_value = round(plane.cargo_rear_max * LB / 5.0) * 5.0
	rear_s.step = 5.0
	rear_s.value = round(plane.cargo_rear * LB / 5.0) * 5.0
	rear_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rear_s.editable = can_load
	var rear_l := Label.new()
	rear_l.custom_minimum_size = Vector2(110, 0)
	rear_row.add_child(rear_s)
	rear_row.add_child(rear_l)

	_spacer(4)
	_content.add_child(summary)
	var bar_row := _row("Balance")
	bar_row.add_child(bar)
	var ends := _label("nose heavy   |   forward limit  ...  aft limit   |   tail heavy", 12, Color(0.60, 0.60, 0.56))
	ends.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Fuel is bought: what you add past what was in the tanks is billed, and
	# taking it back out again (down to that) is refunded.
	var start_gal: float = fuel_s.value
	var price: float = fuel_price()
	var paid := [0]
	var refresh := func() -> void:
		if can_load and not Game.free_repairs and not Game.sandbox:
			var afford: float = start_gal + floorf(float(jobs.money + paid[0]) / maxf(price, 0.01))
			if fuel_s.value > afford:
				fuel_s.set_value_no_signal(maxf(afford, start_gal))
			var bill := int(roundf(maxf(fuel_s.value - start_gal, 0.0) * price))
			if bill != paid[0]:
				jobs.money -= bill - paid[0]
				paid[0] = bill
				jobs.save_career()
		fuel_l.text = "%d gal" % int(fuel_s.value)
		if paid[0] > 0:
			fuel_l.text += "  $%d" % paid[0]
		front_l.text = "%d lb" % int(front_s.value)
		rear_l.text = "%d lb" % int(rear_s.value)
		if can_load:
			plane.set_load(fuel_s.value * GAL_KG, front_s.value / LB, rear_s.value / LB)
		var gross: float = plane.mass * LB
		var over: float = gross - plane.max_mass * LB
		var frac: float = plane.cg_fraction()
		var text := "Gross weight %d lb" % int(gross)
		if over > 1.0:
			text += "   (%d lb OVER maximum)" % int(over)
		else:
			text += "   (%d lb to spare)" % int(-over)
		if frac > 1.0:
			text += "\nBalance: too far aft. Expect it to be unstable."
		elif frac < 0.0:
			text += "\nBalance: too far forward. Hard to raise the nose to land."
		elif frac > 0.8:
			text += "\nBalance: near the aft limit. Light on the controls."
		else:
			text += "\nBalance: within limits."
		summary.text = text
		summary.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if (over > 1.0 or frac > 1.0 or frac < 0.0) else Color(0.92, 0.92, 0.88))
		bar.fraction = frac
		bar.queue_redraw()
	fuel_s.value_changed.connect(func(_v): refresh.call())
	front_s.value_changed.connect(func(_v): refresh.call())
	rear_s.value_changed.connect(func(_v): refresh.call())
	refresh.call()

	# Tyres and gear legs. Later these will be bought and fitted in the hangar.
	_spacer(10)
	_label("TYRES AND LANDING GEAR", 22, Color(0.90, 0.50, 0.18))
	var gear_info := _label("", 13, Color(0.70, 0.70, 0.66))
	var tyre_names: Array = []
	for k in Gear.TYRE_ORDER:
		tyre_names.append(Gear.TYRES[k]["name"])
	var leg_names: Array = []
	for k in Gear.LEG_ORDER:
		leg_names.append(Gear.LEGS[k]["name"])
	var describe := func() -> void:
		var t: Dictionary = Gear.TYRES[plane.tyre_kind]
		var l: Dictionary = Gear.LEGS[plane.leg_kind]
		gear_info.text = "%s: %d psi, %d in tall. %s\n%s: %s" % [t["name"], int(t["psi"]), int(round(float(t["radius"]) * 2.0 / 0.0254)), TYRE_NOTES.get(plane.tyre_kind, "Big DC-3 mainwheels, fixed to this aircraft."), l["name"], LEG_NOTES.get(plane.leg_kind, "DC-3 oleo legs.")]
	var tyre_ob := _option(_row("Tyres"), tyre_names, Gear.TYRE_ORDER.find(plane.tyre_kind), func(i):
		plane.tyre_kind = Gear.TYRE_ORDER[i]
		plane.apply_gear()
		plane.settle_here()
		Game.tyre_kind = plane.tyre_kind
		Game.save_settings()
		describe.call()
		refresh.call())
	var leg_ob := _option(_row("Gear legs"), leg_names, Gear.LEG_ORDER.find(plane.leg_kind), func(i):
		plane.leg_kind = Gear.LEG_ORDER[i]
		plane.apply_gear()
		plane.settle_here()
		Game.leg_kind = plane.leg_kind
		Game.save_settings()
		describe.call()
		refresh.call())
	tyre_ob.disabled = not can_load
	leg_ob.disabled = not can_load
	_content.move_child(gear_info, _content.get_child_count() - 1)
	describe.call()
	_back()


func _option(row: HBoxContainer, items: Array, selected: int, on_pick: Callable) -> OptionButton:
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(String(it))
	ob.selected = selected
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.item_selected.connect(on_pick)
	row.add_child(ob)
	return ob


## The job board: what is on board (unload it here for pay), and the work
## offered at the airstrip you are stopped at.
func _page_jobs() -> void:
	_label("JOB BOARD", 26, Color(0.90, 0.50, 0.18))
	_label("$%s in the bank      %d jobs done" % [_money(jobs.money), jobs.completed], 17, Color(0.85, 0.82, 0.70))
	var k: int = jobs.strip_here()
	var dim := Color(0.66, 0.66, 0.62)
	if k >= 0:
		var tier: int = jobs.rep_tier(k)
		_label("Standing at %s: %s%s" % [terrain.strips[k]["name"], jobs.REP_NAMES[tier],
			"  (more work, +%d%% pay)" % (5 * tier) if tier > 0 else "  (fly their jobs to get known)"], 14, Color(0.75, 0.85, 0.95))
	if k >= 0 and prospect != null and String(terrain.strips[k]["name"]) in terrain.HANGARS:
		_spacer(4)
		_label("ASSAY OFFICE AND PROSPECTOR'S STORE", 16, Color(0.95, 0.80, 0.35))
		_label("Gold carried: %.1f g (worth $%d at $%d a gram).  Sluice boxes: %d." % [prospect.gold_g, int(prospect.gold_g * prospect.PRICE_PER_G), prospect.PRICE_PER_G, prospect.owned_sluices], 14, dim)
		var arow := HBoxContainer.new()
		arow.add_theme_constant_override("separation", 10)
		_content.add_child(arow)
		var sb := _button("Sell your gold and finds", func():
			_toast(prospect.sell_gold())
			_show("jobs"), arow)
		sb.disabled = prospect.gold_g < 0.01 and not prospect.has_finds()
		_button("Buy a sluice box  $%d" % prospect.SLUICE_PRICE, func():
			_toast(prospect.buy_sluice())
			_show("jobs"), arow)
	if not jobs.carried.is_empty():
		_spacer(4)
		_label("ON BOARD  (%d lb)" % int(round(jobs.carried_kg() * LB)), 16, Color(0.75, 0.85, 0.95))
		for j in jobs.carried.duplicate():
			var dest: String = terrain.strips[int(j["to"])]["name"]
			var p: Array = jobs.payout(j)
			var line := "%s: %s, %d lb, to %s.  $%s%s" % [j["title"], j["what"], int(round(float(j["kg"]) * LB)), dest, _money(p[0]),
				("  (" + String(p[1]) + ")") if String(p[1]) != "" else ""]
			if bool(j["urgent"]):
				var left := float(j["limit_min"]) - float(j["minutes"])
				line += "  %s" % ("%d min left" % int(ceil(left)) if left > 0.0 else "late")
			_label(line, 15)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			_content.add_child(row)
			var on_ramp: int = jobs.count_at(j, "ramp")
			if on_ramp > 0 and k == int(j["from"]):
				_label("%d of %d still on the ramp." % [on_ramp, (j["pieces"] as Array).size()], 14, dim)
				_button("Load the rest for me", func():
					jobs.load_rest(j)
					_show("jobs"), row)
			if int(j["to"]) == k:
				if jobs.can_quick_unload(j):
					_button("Unload for me  +$%s" % _money(p[0]), func():
						var got: int = jobs.deliver(j)
						_toast("Delivered. +$%s" % _money(got))
						_show("jobs"), row)
				else:
					_label("Some of it was left behind; it can't be finished here.", 14, dim)
			elif k >= 0 and on_ramp == 0:
				_button("Leave it here (no pay)", func():
					jobs.abandon(j)
					_show("jobs"), row)
	_spacer(6)
	if k < 0:
		_label("Land and stop at an airstrip to see the work there.", 15, dim)
	else:
		var here: Dictionary = terrain.strips[k]
		_label("WORK AT %s" % String(here["name"]).to_upper(), 16, Color(0.75, 0.85, 0.95))
		var r: Dictionary = jobs.room()
		_label("Room: cabin %d lb, baggage bay %d lb, %d lb below maximum weight." % [
			int(round(float(r["front"]) * LB)), int(round(float(r["rear"]) * LB)), int(round(maxf(float(r["weight"]), 0.0) * LB))], 14, dim)
		var list: Array = jobs.board(k)
		if list.is_empty():
			_label("Nothing going out from here right now. Check back after your next delivery.", 15, dim)
		for j in list.duplicate():
			var dest2: String = terrain.strips[int(j["to"])]["name"]
			var nm: float = jobs._distance_nm(k, int(j["to"]))
			var tags: Array[String] = []
			if bool(j["fragile"]):
				tags.append("fragile")
			if bool(j["urgent"]):
				tags.append("urgent: %d min" % int(j["limit_min"]))
			var head := "%s to %s, %d nm.  $%s" % [j["title"], dest2, int(round(nm)), _money(int(j["pay"]))]
			_label(head, 16)
			_label("%s, %d lb%s" % [String(j["what"]).capitalize() if int(j["pax"]) > 0 else String(j["what"]), int(round(float(j["kg"]) * LB)),
				("   (" + ", ".join(tags) + ")") if not tags.is_empty() else ""], 14, dim)
			var why: String = jobs.cannot_take(j)
			var brow := HBoxContainer.new()
			brow.add_theme_constant_override("separation", 10)
			_content.add_child(brow)
			var b := _button("Load it for me" if why == "" else why, func():
				if jobs.take(j):
					_toast("Loaded: %s for %s." % [j["what"], dest2])
				_show("jobs"), brow)
			b.disabled = why != ""
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if why == "":
				var pax_job: bool = int(j["pax"]) > 0
				var b2 := _button("I'll walk them to the plane" if pax_job else "I'll load it by hand", func():
					if jobs.take(j, true):
						if pax_job:
							_toast("Your passengers are waiting off the left wingtip. Get out (%s) and show them aboard (%s)." % [Game.hint("get_out"), Game.hint("interact")])
						else:
							_toast("It's on the ramp off your left wingtip. Get out (%s) and carry it aboard (%s)." % [Game.hint("get_out"), Game.hint("interact")])
					close(), brow)
				b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if k >= 0:
		_contracts_section(k)
	if mining != null and k >= 0:
		_mining_section(k)
	_back()


func _contracts_section(k: int) -> void:
	var dim := Color(0.66, 0.66, 0.62)
	var offers: Array = jobs.contract_offers(k)
	if jobs.contracts.is_empty() and offers.is_empty():
		if bool(terrain.strips[k]["fuel"]) and jobs.rep_tier(k) < 1:
			_spacer(6)
			_label("CONTRACTS: fly a few jobs from here and they'll offer you regular runs.", 14, dim)
		return
	_spacer(6)
	_label("CONTRACTS", 16, Color(0.95, 0.80, 0.35))
	for c in jobs.contracts:
		_label("%s: %d of %d loads delivered, $%s per load, $%s bonus at the end. Loads go from %s." % [c["title"], int(c["done"]), int(c["loads"]),
			_money(int(c["per_load"])), _money(int(c["bonus"])), terrain.strips[int(c["from"])]["name"]], 14)
	for c in offers:
		_label("%s: %d loads of %d lb, $%s each, $%s bonus when the last one lands." % [c["title"], int(c["loads"]), int(round(float(c["kg"]) * LB)),
			_money(int(c["per_load"])), _money(int(c["bonus"]))], 14, dim)
		_button("Take the contract", func():
			jobs.accept_contract(c)
			_toast("Contract signed. The first load is on the board.")
			_show("jobs"))


static func _money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


## A message on the game screen (the HUD shows it once the menu closes).
signal toast(text: String)
func _toast(text: String) -> void:
	toast.emit(text)


func _page_settings() -> void:
	_label("SEASON, WEATHER AND REALISM", 26, Color(0.90, 0.50, 0.18))

	if net != null and net.has_method("is_guest") and net.is_guest():
		_label("Map: %s - the host picks the map." % ("Outback (Australia)" if Game.map == "outback" else "Alaska (the northern bush)"), 15, Color(0.92, 0.45, 0.12))
	else:
		_map_row()
	_label("Changing the map rebuilds the world straight away. The Outback is always the hot dry season.", 13, Color(0.66, 0.66, 0.62))

	_option(_row("Flight realism"), Game.REALISM_NAMES, Game.realism, func(i):
		Game.realism = i
		Game.notify_changed())
	_label("Sim-lite: gentler stalls, the rudder looks after itself, the wings level when you let go, tougher landing gear, and the wind is shown on screen.\nRealistic: you work the rudder and trim, engine torque pulls left on takeoff, stalls bite, and the gear breaks sooner.", 13, Color(0.66, 0.66, 0.62))

	_option(_row("Auto-trim (sim-lite)"), ["Off: trim only with the trim buttons", "On: holding the stick re-trims"], 1 if Game.auto_trim else 0, func(i):
		Game.auto_trim = i == 1
		Game.notify_changed())

	_option(_row("Gauges in outside view"), ["Off", "On"], 1 if Game.chase_gauges else 0, func(i):
		Game.chase_gauges = i == 1
		Game.notify_changed())

	_option(_row("Controller rumble"), ["Off", "On"], 1 if Game.rumble else 0, func(i):
		Game.rumble = i == 1
		Game.notify_changed())

	_slider_row("Rumble strength", 0.0, 2.0, 0.05, Game.rumble_strength, "%.2f", func(v):
		Game.rumble_strength = v
		Game.save_settings())
	_slider_row("Engine pulses in the rumble", 0.0, 2.0, 0.05, Game.rumble_engine, "%.2f", func(v):
		Game.rumble_engine = v
		Game.save_settings())

	_option(_row("Stall warning beep"), ["Off", "On (quiet)"], 1 if Game.stall_horn else 0, func(i):
		Game.stall_horn = i == 1
		Game.notify_changed())

	_option(_row("Getting-started list"), ["Off", "On"], 1 if Game.goals_on else 0, func(i):
		Game.goals_on = i == 1
		Game.notify_changed())
	_option(_row("Machine control tips"), ["Off", "On"], 1 if Game.machine_hints else 0, func(i):
		Game.machine_hints = i == 1
		Game.notify_changed())

	_option(_row("Gore"), ["Off", "On"], 1 if Game.gore else 0, func(i):
		Game.gore = i == 1
		Game.notify_changed())
	_label("Blood, and lost arms, legs and heads, when a crash, a machine or a propeller kills you.", 13, Color(0.66, 0.66, 0.62))

	_option(_row("Engine management"), ["Automatic", "Manual"], 0 if Game.engine_auto else 1, func(i):
		Game.engine_auto = i == 0
		Game.notify_changed())
	_label("Automatic: the engine starts running and the game handles mixture, propeller, carb heat and cowl flaps.\nManual: you start from cold and dark and work every switch and lever yourself. Press %s for a guided automatic start." % Game.hint("engine_auto"), 13, Color(0.66, 0.66, 0.62))

	_option(_row("Game mode"), ["Career", "Sandbox (free money, no bills)"], 1 if Game.sandbox else 0, func(i):
		Game.sandbox = i == 1
		Game.notify_changed())
	_label("Sandbox: money never runs out, nothing costs anything, and planes are sold at any strip. Press ` (or F1) any time for the admin console: type help.", 13, Color(0.66, 0.66, 0.62))

	_option(_row("Bills"), ["Pay for fuel and repairs", "Free (sandbox)"], 1 if Game.free_repairs else 0, func(i):
		Game.free_repairs = i == 1
		Game.notify_changed())
	_label("Fuel costs about $2.40 a gallon at a town pump and twice that from a bush cache. Going back to the last airstrip after damage or a crash sends you the recovery and repair bill.", 13, Color(0.66, 0.66, 0.62))


	_option(_row("Cockpit gauges"), ["In the 3D panel", "Also on screen"], 1 if Game.cockpit_overlay else 0, func(i):
		Game.cockpit_overlay = i == 1
		Game.notify_changed())

	if net != null and net.has_method("is_guest") and net.is_guest():
		_label("You've joined a game: the host sets the season, time of day, wind and weather.", 15, Color(0.92, 0.45, 0.12))
	else:
		_world_rows()

	var vol_row := _row("Sound volume")
	var vol_s := HSlider.new()
	vol_s.min_value = 0.0
	vol_s.max_value = 1.0
	vol_s.step = 0.05
	vol_s.value = Game.volume
	vol_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_s.value_changed.connect(func(v):
		Game.volume = v
		Game.notify_changed())
	vol_row.add_child(vol_s)

	_back()


static func _clock(hours: float) -> String:
	var h := int(hours)
	var m := int(round((hours - float(h)) * 60.0))
	return "%02d:%02d" % [h, m]


func _slider_row(title: String, lo: float, hi: float, step: float, value: float, fmt: String, on_change: Callable) -> void:
	var row := _row(title)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.custom_minimum_size = Vector2(70, 0)
	l.text = fmt % value
	sl.value_changed.connect(func(v):
		l.text = fmt % v
		on_change.call(v))
	row.add_child(sl)
	row.add_child(l)


## How to play: what the game is, the basics of flying, and the rest.
func _page_help() -> void:
	var dim := Color(0.78, 0.78, 0.74)
	var head := Color(0.95, 0.80, 0.35)
	_label("HOW TO PLAY", 26, Color(0.90, 0.50, 0.18))
	_button("Start the tutorial: first flight and first job", func():
		tutorial_requested.emit()
		close())
	_button("Story: THE FIRE (about 15 minutes - plays on a copy of your save)", func():
		close()
		story_requested.emit())
	var sections := [
		["THE GAME", "You're a bush pilot somewhere north of sixty in 1988. Fly cargo, mail, passengers and skydivers between the towns and bush strips, earn money, and grow: better tyres and floats, more planes, a DC-3, mining claims, your own strips and cabins. Weather, darkness, rough strips, water and damage are the challenge."],
		["FLYING", "Throttle up (%s) and keep straight with the rudder (%s / %s). Lift off at about 55 knots by easing back (%s). Climb at 65-75 knots. Trim (%s / %s) so the plane holds its attitude. To land: slow to about 65 knots, flaps down (%s), aim for the runway's start, and hold the nose up gently as it settles. Brakes: %s." % [Game.hint("throttle_up"), Game.hint("yaw_left"), Game.hint("yaw_right"), Game.hint("pitch_up"), Game.hint("trim_up"), Game.hint("trim_down"), Game.hint("flaps_down"), Game.hint("brake")]],
		["VIEWS", "%s switches cockpit / chase view. Right-mouse drag to look round, mouse wheel to zoom. In the cockpit you can click and drag every switch, lever and the yoke. %s shows all the flying keys, %s the chart." % [Game.hint("camera"), Game.hint("help"), Game.hint("map")]],
		["ENGINE", "Settings can start the engine for you (Automatic) or leave it cold and dark (Manual): then master, fuel, mixture rich, prime, magnetos to START. %s does a guided start. Watch the oil and temperatures." % Game.hint("engine_auto")],
		["JOBS AND MONEY", "Stopped at a strip, %s opens the job board. Take a job and it's loaded for you, or carry it aboard yourself through the doors. Fly it to where it's going and unload for pay. Fuel and repairs cost money. Fly for a town often and they offer contracts with a bonus." % Game.hint("jobs")],
		["ON FOOT", "%s gets you out (and back in). Walk, run and jump; carry cargo with %s, open doors with %s, fell trees with the chainsaw (%s at a tree) and buck the trunks up for logs (%s along a downed or burnt trunk), and build with %s: your own bush strip, a cabin, a hangar, a mining camp. Keep warm: cold and wet hurt." % [Game.hint("get_out"), Game.hint("interact"), Game.hint("door"), Game.hint("interact"), Game.hint("interact"), Game.hint("build")]],
		["BUSH CAMP", "Landed somewhere nice? Get out and press %s, then Bush camp: a tent, a campfire, a cooler of beer and a chair go up next to the plane. %s at the cooler for a beer, at the tent to sleep till morning (sleeping it off clears your head). %s lights a cigarette anywhere, even in the cockpit. Too many beers and you'll walk crooked, the view swims and your hands wander on the controls: flying drunk is a bad idea." % [Game.hint("build"), Game.hint("interact"), Game.hint("smoke")]],
		["WATER AND SNOW", "Floats (Load and fuel → Gear legs) let you land on lakes; raise the wheels (%s) for water and lower them for a runway, or you'll flip. Wheel-skis work on snow and ice. Fuel docks sit on the bigger lakes." % Game.hint("gear")],
		["THE DC-3", "Buy the one parked by the hangar at Proving Ground. Heavy and slow to respond, needs a long strip. Either engine can fail (practise from the menu): the plane swings toward the dead one, so hold rudder, feather its prop (%s) and fly on the other." % Game.hint("feather")],
		["MINING AND BUILDING", "Dig the pay ground on the Proving Ground claim: shovel and pan, sluice, then the excavator and wash plant, and weigh the concentrate in at the assay office by the hangar. Logs from felled trees build cabins and camps, or sell at the sawmill."],
		["TUNNELS AND TIMBER", "Shovel or pick in hand, face a steep bank or a pit wall and %s digs a drift straight in; look down or up to drive it on a grade. Gravel roofs stand for a couple of minutes, then start to work: dirt trickles, and a bare span can come in on you. Make timber sets at the crafting bench in the tool yard (2 logs each), carry them in (9 kg apiece) and %s in the drift to stand one: each holds the roof 1.7 m either side. Rock roofs need nothing. Take a headlamp, and rope lights and a generator for long drifts." % [Game.hint("interact"), Game.hint("interact")]],
		["CO-OP", "Esc → Co-op: host or join. Fly your own planes together, ride along in a friend's plane, hand over the controls (%s), or land near a crashed friend to pick them up." % Game.hint("controls")],
	]
	for sec in sections:
		_spacer(4)
		_label(String(sec[0]), 16, head)
		_label(String(sec[1]), 14, dim)
	_back()


## Every graphics option on its own. Changing any of them makes the preset "Custom".
func _page_graphics() -> void:
	var dim := Color(0.66, 0.66, 0.62)
	_label("GRAPHICS", 26, Color(0.90, 0.50, 0.18))
	var custom := func() -> void:
		Game.graphics_quality = 4
		Game.notify_changed()
	_option(_row("Preset"), Game.QUALITY_NAMES, Game.graphics_quality, func(i):
		if i < 4:
			Game.apply_preset(i)
		Game.graphics_quality = i
		Game.notify_changed()
		_show("graphics"))
	_label("DISPLAY", 16, Color(0.95, 0.80, 0.35))
	var res_names: Array = []
	var scr := DisplayServer.screen_get_size()
	for r in Game.RESOLUTIONS:
		var rv: Vector2i = r
		res_names.append("Screen's own (%d x %d)" % [scr.x, scr.y] if rv == Vector2i.ZERO else "%d x %d" % [rv.x, rv.y])
	_option(_row("Resolution"), res_names, Game.resolution, func(i):
		Game.resolution = i
		Game.notify_changed())
	_option(_row("Window"), Game.WINDOW_MODE_NAMES, Game.window_mode, func(i):
		Game.window_mode = i
		Game.notify_changed())
	_option(_row("V-sync"), Game.VSYNC_NAMES, Game.vsync, func(i):
		Game.vsync = i
		Game.notify_changed())
	var fps_names: Array = []
	for f in Game.FPS_LIMITS:
		fps_names.append("Unlimited" if f == 0 else "%d fps" % f)
	_option(_row("Frame-rate cap"), fps_names, Game.fps_limit, func(i):
		Game.fps_limit = i
		Game.notify_changed())
	_slider_row("Field of view", -15.0, 25.0, 1.0, Game.fov_offset, "%+.0f°", func(v):
		Game.fov_offset = v
		Game.notify_changed())
	_slider_row("Camera shake", 0.0, 200.0, 10.0, Game.cam_shake * 100.0, "%.0f%%", func(v):
		Game.cam_shake = v / 100.0
		Game.notify_changed())
	_label("RESOLUTION AND SMOOTHING", 16, Color(0.95, 0.80, 0.35))
	_slider_row("Render scale", 50.0, 100.0, 5.0, Game.render_scale * 100.0, "%.0f%%", func(v):
		Game.render_scale = v / 100.0
		custom.call())
	_option(_row("Upscaler"), Game.UPSCALER_NAMES, Game.upscaler, func(i):
		Game.upscaler = i
		custom.call())
	# FSR 2 quality modes: pick one and it sets the render scale for you
	var modes := ["Native (100%)", "Quality (67%)", "Balanced (59%)", "Performance (50%)"]
	var scales := [1.0, 0.67, 0.59, 0.5]
	var cur_mode := -1
	for mi in range(scales.size()):
		if absf(Game.render_scale - float(scales[mi])) < 0.01 and (mi == 0 or Game.upscaler == 2):
			cur_mode = mi
	_option(_row("FSR 2 mode"), modes + (["Custom"] if cur_mode < 0 else []), cur_mode if cur_mode >= 0 else modes.size(), func(i):
		if i < scales.size():
			Game.render_scale = scales[i]
			if i > 0:
				Game.upscaler = 2
			custom.call()
			_show("graphics"))
	_slider_row("Sharpness", 0.0, 100.0, 5.0, Game.upscale_sharp * 100.0, "%.0f%%", func(v):
		Game.upscale_sharp = v / 100.0
		Game.notify_changed())
	_label("Below 100% the 3D is drawn smaller and scaled up: much faster. FSR 2 looks sharpest and also smooths edges; Quality is a good start. Sharpness counters the softness of upscaling.", 13, dim)
	_option(_row("Anti-aliasing"), Game.AA_NAMES, Game.gfx_aa, func(i):
		Game.gfx_aa = i
		custom.call())
	_label("LIGHT AND SHADOW", 16, Color(0.95, 0.80, 0.35))
	_option(_row("Shadows"), Game.SHADOW_NAMES, Game.gfx_shadows, func(i):
		Game.gfx_shadows = i
		custom.call())
	_option(_row("Ambient occlusion"), ["Off", "On"], 1 if Game.gfx_ao else 0, func(i):
		Game.gfx_ao = i == 1
		custom.call())
	_option(_row("Indirect light"), ["Off", "On"], 1 if Game.gfx_ssil else 0, func(i):
		Game.gfx_ssil = i == 1
		custom.call())
	_option(_row("Reflections"), ["Off", "On"], 1 if Game.gfx_ssr else 0, func(i):
		Game.gfx_ssr = i == 1
		custom.call())
	_option(_row("Glow"), ["Off", "On"], 1 if Game.gfx_glow else 0, func(i):
		Game.gfx_glow = i == 1
		custom.call())
	_label("WORLD DETAIL", 16, Color(0.95, 0.80, 0.35))
	_option(_row("Trees"), ["Flat picture cards (fast)", "Full 3D up close (slow)"], 1 if Game.trees_3d else 0, func(i):
		Game.trees_3d = i == 1
		custom.call())
	_option(_row("Tree distance"), Game.TREE_DISTANCE_NAMES, Game.tree_distance, func(i):
		Game.tree_distance = i
		custom.call())
	_option(_row("Bushes and grass"), Game.TREE_DISTANCE_NAMES, Game.gfx_plants, func(i):
		Game.gfx_plants = i
		custom.call())
	_option(_row("Water"), ["Flat", "Waves and wakes up close"], Game.gfx_water, func(i):
		Game.gfx_water = i
		custom.call())
	_label("Biggest speed-ups: Render scale, Shadows, Tree distance, Bushes and grass.", 13, dim)
	_back()


func _page_controls() -> void:
	_label("CONTROLS AND CONTROLLER", 26, Color(0.90, 0.50, 0.18))
	_label("Pick a slot and press the key, button or stick direction you want. Esc cancels. Each action has two keyboard slots and one controller slot.", 13, Color(0.66, 0.66, 0.62))

	# Which controller to listen to
	var pads: Array = Game.connected_controllers()
	var names: Array = ["Automatic (%s)" % Game.active_device_name() if not pads.is_empty() else "Automatic (none connected)", "Any controller"]
	for p in pads:
		names.append(String(p[1]))
	var picked := 0
	if Game.controller_pref == "*":
		picked = 1
	elif Game.controller_pref != "":
		for i in range(pads.size()):
			if pads[i][1] == Game.controller_pref:
				picked = i + 2
	_option(_row("Controller in use"), names, picked, func(i):
		if i == 0:
			Game.controller_pref = ""
		elif i == 1:
			Game.controller_pref = "*"
		else:
			Game.controller_pref = String(pads[i - 2][1])
		Game.apply_bindings()
		Game.save_settings())
	_axes_label = _label(" ", 12, Color(0.60, 0.70, 0.60))
	_button("Flight stick, throttle and pedals (HOTAS) setup", func(): _show("hotas"))
	if pads.size() > 1:
		_label("%d controllers are plugged in. If the plane moves on its own, pick your gamepad here so the others are ignored." % pads.size(), 13, Color(1.0, 0.62, 0.12))

	var inv := CheckBox.new()
	inv.text = "Invert nose up / nose down"
	inv.button_pressed = Game.invert_pitch
	inv.toggled.connect(func(on):
		Game.invert_pitch = on
		Game.notify_changed())
	_content.add_child(inv)
	_slider_row("Stick sensitivity", 0.4, 1.6, 0.05, Game.stick_sensitivity, "%.2f", func(v):
		Game.stick_sensitivity = v
		Game.save_settings())
	_slider_row("Stick dead zone", 0.02, 0.4, 0.01, Game.stick_deadzone, "%.2f", func(v):
		Game.stick_deadzone = v
		Game.apply_bindings()
		Game.save_settings())
	_slider_row("Look speed", 0.3, 2.0, 0.05, Game.look_speed, "%.2f", func(v):
		Game.look_speed = v
		Game.save_settings())
	# phones and tablets (DESIGN_NOTES 128)
	_option(_row("Touch controls"), ["Automatic (on a touch screen)", "On", "Off"], Game.touch_mode, func(i):
		Game.touch_mode = i
		Game.save_settings())
	var tf := CheckBox.new()
	tf.text = "Tilt the phone to fly (bank and pitch); LEVEL sets the centre"
	tf.button_pressed = Game.tilt_fly
	tf.toggled.connect(func(on):
		Game.tilt_fly = on
		Game.save_settings())
	_content.add_child(tf)
	_slider_row("Tilt sensitivity", 0.4, 2.5, 0.05, Game.tilt_gain, "%.2f", func(v):
		Game.tilt_gain = v
		Game.save_settings())

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	for t in [["Action", 250], ["Key", 160], ["Second key", 160], ["Controller", 180], ["Flight gear", 190]]:
		var hl := Label.new()
		hl.text = t[0]
		hl.custom_minimum_size = Vector2(t[1], 0)
		hl.add_theme_color_override("font_color", Color(0.90, 0.50, 0.18))
		header.add_child(hl)
	_content.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_content.add_child(scroll)
	for row_def in Game.ACTIONS:
		var action: String = row_def[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := Label.new()
		name_l.text = row_def[1]
		name_l.custom_minimum_size = Vector2(250, 0)
		row.add_child(name_l)
		for slot in range(4):
			var b := Button.new()
			b.custom_minimum_size = Vector2([160, 160, 180, 190][slot], 32)
			b.add_theme_font_size_override("font_size", 15)
			b.clip_text = true
			b.pressed.connect(func(): _start_listening(action, slot))
			row.add_child(b)
			_bind_buttons["%s:%d" % [action, slot]] = b
		list.add_child(row)
	_refresh_bindings()

	_bind_note = _label(" ", 14, Color(1.0, 0.62, 0.12))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	_button("Reset all to defaults", func():
		Game.reset_bindings()
		_refresh_bindings()
		_bind_note.text = "All controls are back to their defaults.", bottom)
	_button("Back", func(): _show("main"), bottom)
	_content.add_child(bottom)


func _start_listening(action: String, slot: int) -> void:
	_listen_action = action
	_listen_slot = slot
	_refresh_bindings()
	if _bind_note != null:
		_bind_note.text = "Press a %s for \"%s\"..." % [["key", "key", "controller button or push a stick", "button or hat on your flight stick or throttle"][slot], Game.action_label(action)]


func _refresh_bindings() -> void:
	for key in _bind_buttons.keys():
		var parts: PackedStringArray = String(key).split(":")
		var action := parts[0]
		var slot := int(parts[1])
		var b: Button = _bind_buttons[key]
		if action == _listen_action and slot == _listen_slot:
			b.text = "press..."
		elif slot == 3:
			b.text = Game.hotas.button_name(action)
		else:
			b.text = Game.binding_name(Game.bindings[action][slot])


# ------------------------------------------------------------------------------
#  Flight stick, throttle and pedals
# ------------------------------------------------------------------------------
const WIZ_STEPS := ["roll", "pitch", "yaw", "throttle", "prop", "mixture", "brake_left", "brake_right", "trim", "look_x", "look_y"]
const WIZ_OPTIONAL := ["prop", "mixture", "brake_left", "brake_right", "trim", "look_x", "look_y"]


func _page_hotas() -> void:
	var hz: Node = Game.hotas
	_label("FLIGHT STICK, THROTTLE AND PEDALS", 26, Color(0.90, 0.50, 0.18))
	var names: Array = []
	for p in Game.connected_controllers():
		names.append(hz.short_name(String(p[1])))
	_label("Plugged in: %s" % (", ".join(names) if not names.is_empty() else "nothing. Plug in your stick and throttle, then open this page again."), 15, Color(0.66, 0.72, 0.62))
	_label("Use Quick setup and move each control when asked. The stick, throttle and pedals can be separate devices (the X56 is two). Buttons and hats are set on the Controls page, in the Flight gear column.", 13, Color(0.66, 0.66, 0.62))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_content.add_child(top)
	_button("Quick setup", func(): _wiz_start(WIZ_STEPS.duplicate()), top)
	_button("Clear all", func():
		hz.clear_all()
		_show("hotas"), top)

	# The step-by-step box (hidden until setup runs)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.visible = false
	_content.add_child(box)
	_wiz_box = box
	_wiz_label = Label.new()
	_wiz_label.add_theme_font_size_override("font_size", 22)
	_wiz_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	_wiz_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_wiz_label)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 12)
	box.add_child(wrow)
	_button("Next  (or any stick button)", _wiz_next, wrow)
	_button("Skip this one", _wiz_skip, wrow)
	_button("Stop", func(): _show("hotas"), wrow)

	# One row per flight axis
	for row in hz.AXES:
		var id: String = row[0]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		var l := Label.new()
		l.text = row[1]
		l.custom_minimum_size = Vector2(170, 0)
		r.add_child(l)
		var bound := Label.new()
		bound.text = hz.axis_name(id)
		bound.custom_minimum_size = Vector2(250, 0)
		bound.clip_text = true
		bound.add_theme_color_override("font_color", Color(0.75, 0.75, 0.70))
		r.add_child(bound)
		var bar := AxisBar.new()
		bar.id = id
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(bar)
		for bdef in [["Set", func(): _wiz_start([id])], ["Flip", func():
				hz.flip(id)
				_hotas_note.text = "%s reversed." % row[1]], ["Clear", func():
				hz.clear_axis(id)
				_show("hotas")]]:
			var b := Button.new()
			b.text = bdef[0]
			b.custom_minimum_size = Vector2(70, 30)
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(bdef[1])
			r.add_child(b)
		_content.add_child(r)

	_slider_row("Stick dead zone", 0.0, 0.2, 0.01, hz.deadzone, "%.2f", func(v):
		hz.deadzone = v
		Game.save_settings())
	_slider_row("Stick curve (soft centre)", 0.0, 1.0, 0.05, hz.curve, "%.2f", func(v):
		hz.curve = v
		Game.save_settings())
	_hotas_note = _label(" ", 14, Color(1.0, 0.62, 0.12))
	_spacer()
	_button("Back to controls", func(): _show("controls"))


func _wiz_start(steps: Array) -> void:
	if Game.connected_controllers().is_empty() and Game.hotas.test_raw.is_empty():
		_hotas_note.text = "Nothing is plugged in."
		return
	_wiz = steps
	_wiz_phase = 0
	_wiz_box.visible = true
	_wiz_prompt()


func _wiz_prompt() -> void:
	var hz: Node = Game.hotas
	var id: String = _wiz[0]
	var row: Array = []
	for r in hz.AXES:
		if r[0] == id:
			row = r
	var extra := "  (Skip it if you don't have one.)" if id in WIZ_OPTIONAL else ""
	if _wiz_phase == 0:
		_wiz_label.text = "%s: put it %s, then press Next.%s" % [row[1], row[3], extra]
	else:
		_wiz_label.text = "%s: now move it %s and HOLD it there, then press Next." % [row[1], row[4]]


func _wiz_next() -> void:
	if _wiz.is_empty():
		return
	var hz: Node = Game.hotas
	var id: String = _wiz[0]
	if _wiz_phase == 0:
		_wiz_first = hz.snapshot()
		_wiz_phase = 1
		_wiz_prompt()
		return
	var err: String = hz.bind_axis(id, _wiz_first, hz.snapshot())
	if err != "":
		_wiz_phase = 0
		_wiz_prompt()
		_wiz_label.text = err + "\n" + _wiz_label.text
		return
	_hotas_note.text = "%s set: %s." % [hz.label_of(id), hz.axis_name(id)]
	_wiz_skip()


func _wiz_skip() -> void:
	if _wiz.is_empty():
		return
	_wiz.pop_front()
	_wiz_phase = 0
	if _wiz.is_empty():
		var note := _hotas_note.text
		_show("hotas")
		_hotas_note.text = note + "  All done." if note.strip_edges() != "" else "All done."
		return
	_wiz_prompt()



# ------------------------------------------------------------------------------
#  Hangar and your planes
# ------------------------------------------------------------------------------
func _page_newgame() -> void:
	_label("START OVER?", 26, Color(0.90, 0.50, 0.18))
	_label("This wipes the whole career: money, planes and their paint, the trucks, the pickup and its parts, the loader, your inventory, cargo, claims, mining gear, buildings, camps and felled trees. The claim is dealt fresh.", 15, Color(0.80, 0.78, 0.72))
	_label("Your settings, graphics and controls are kept.", 14, Color(0.66, 0.66, 0.62))
	_spacer(10)
	_button("Yes - wipe it and start a new game", func():
		new_game.call())
	_button("No, keep my game", func(): _show("main"))


func _page_fleet() -> void:
	var dim := Color(0.66, 0.66, 0.62)
	_label("HANGAR AND YOUR PLANES", 26, Color(0.90, 0.50, 0.18))
	fleet.sync_active()
	var k: int = jobs.strip_here()
	var hk: int = fleet.hangar_here()
	_label("Money: $%s" % _money(jobs.money), 15, dim)
	if k < 0:
		_label("Land and stop at an airstrip to swap planes. Hangars are at %s." % ", ".join(terrain.HANGARS), 14, dim)
	for i in range(fleet.planes.size()):
		var d: Dictionary = fleet.planes[i]
		var st: Dictionary = d["state"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := Label.new()
		var where := "you're flying it"
		if i != fleet.active:
			var sn: String = terrain.strips[int(d["strip"])]["name"]
			where = ("in the hangar at " if d["where"] == "hangar" else "parked at ") + sn
		var dmg := 0
		for v in (st.get("parts", {}) as Dictionary).values():
			if float(v) < 0.9:
				dmg += 1
		var fuel_gal := int(round((float(st.get("tank_l", 0.0)) + float(st.get("tank_r", 0.0))) / GAL_KG))
		l.text = "%s   %s, %d gal%s%s" % [d["reg"], where, fuel_gal,
			(", %d parts damaged" % dmg) if dmg > 0 else "", ", floats" if String(st.get("leg", "")) == "amphib" else ""]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if i != fleet.active and k >= 0 and int(d["strip"]) == k:
			if hk >= 0:
				_button("Fly it (mine into the hangar)", func():
					var err: String = fleet.switch_to(i, true)
					if err != "":
						_toast(err)
					close(), row)
			_button("Fly it (leave mine parked here)", func():
				var err2: String = fleet.switch_to(i, false)
				if err2 != "":
					_toast(err2)
				close(), row)
		_content.add_child(row)
	_spacer(6)
	if hk >= 0:
		for t in ["wolverine", "biplane", "dc3"]:
			var sp: Dictionary = fleet.PlaneTypes.spec(t)
			var tt: String = t
			var b := _button("Buy a %s  ($%s)" % [sp["name"], _money(int(sp["price"]))], func():
				var err3: String = fleet.buy(tt)
				_toast("Bought. It's waiting in the hangar: pick it in the list above to fly it." if err3 == "" else err3)
				_show("fleet"))
			b.disabled = jobs.money < int(sp["price"])
		_label("The DC-3: two engines, 3 t of cargo, needs a long strip (Proving Ground). Either engine can fail; feather the dead one (%s) and hold the swing with rudder." % Game.hint("feather"), 13, dim)
		# Paint shop: respray the plane you're sitting in.
		if plane != null and repaint.is_valid():
			_spacer(6)
			_label("PAINT SHOP (the plane you're in)", 15, Color(0.95, 0.80, 0.35))
			var t: String = plane.plane_type
			var lt: Array = Liveries.table(t)
			for li in range(lt.size()):
				var here: bool = li == int(plane.livery) and (plane.paint as Array).is_empty()
				var row2 := HBoxContainer.new()
				row2.add_theme_constant_override("separation", 10)
				var sw := ColorRect.new()
				sw.color = lt[li][1]
				sw.custom_minimum_size = Vector2(22, 22)
				row2.add_child(sw)
				var sw2 := ColorRect.new()
				sw2.color = lt[li][2]
				sw2.custom_minimum_size = Vector2(22, 22)
				row2.add_child(sw2)
				var nm: String = lt[li][0]
				var lidx := li
				var b2 := _button("%s%s" % [nm, "  (this paint)" if here else "  ($%d)" % Liveries.PRICE], func():
					if jobs.money < Liveries.PRICE:
						_toast("Not enough money.")
						return
					jobs.money -= Liveries.PRICE
					plane.paint = []
					repaint.call(lidx)
					_toast("Resprayed: %s." % nm)
					_show("fleet"), row2)
				b2.disabled = here or jobs.money < Liveries.PRICE
				_content.add_child(row2)
			_paint_mixer(t)
	else:
		_label("Planes can be bought, stored and swapped at a strip with a hangar: %s." % ", ".join(terrain.HANGARS), 14, dim)
	_back()



## Mix your own: pick a colour for each part of the paint from the
## enamels on the shelf, then spray it (DESIGN_NOTES 153).
var _mix: Array = []
var _mix_type := ""
var _mix_focus := Vector2i(-1, -1)
var _keep_focus: Control = null


func _paint_mixer(t: String) -> void:
	var slots: Array = Liveries.PAINT_SLOTS.get(t, ["Body", "Trim", "Stripe"])
	if _mix_type != t or _mix.size() != slots.size():
		_mix_type = t
		var cur: Array = Liveries.for_plane(plane)
		_mix = []
		for k in range(slots.size()):
			_mix.append(cur[k + 1])
	_spacer(4)
	_label("MIX YOUR OWN COLOURS", 14, Color(0.95, 0.80, 0.35))
	for si in range(slots.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var l := Label.new()
		l.text = String(slots[si])
		l.custom_minimum_size = Vector2(130, 0)
		row.add_child(l)
		var now := ColorRect.new()
		now.color = _mix[si]
		now.custom_minimum_size = Vector2(30, 30)
		row.add_child(now)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(8, 0)
		row.add_child(gap)
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 3)
		grid.add_theme_constant_override("v_separation", 3)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for pi in range(Liveries.PALETTE.size()):
			var pc: Array = Liveries.PALETTE[pi]
			var col: Color = pc[1]
			var b := Button.new()
			if _mix_focus == Vector2i(si, pi):
				_keep_focus = b
			b.custom_minimum_size = Vector2(28, 28)
			b.tooltip_text = String(pc[0])
			for st_name in ["normal", "hover", "pressed", "focus", "disabled"]:
				var sb := StyleBoxFlat.new()
				sb.bg_color = col
				sb.set_corner_radius_all(3)
				if st_name == "focus" or st_name == "hover":
					sb.set_border_width_all(3)
					sb.border_color = Color(1, 1, 1)
				elif col.is_equal_approx(_mix[si]):
					sb.set_border_width_all(3)
					sb.border_color = Color(0.95, 0.80, 0.35)
				b.add_theme_stylebox_override(st_name, sb)
			var slot := si
			var pidx := pi
			b.pressed.connect(func():
				_mix[slot] = col
				_mix_focus = Vector2i(slot, pidx)
				_show("fleet"))
			grid.add_child(b)
		row.add_child(grid)
		_content.add_child(row)
	var spray := _button("Spray these colours  ($%d)" % Liveries.PRICE, func():
		if jobs.money < Liveries.PRICE:
			_toast("Not enough money.")
			return
		jobs.money -= Liveries.PRICE
		plane.paint = _mix.duplicate()
		repaint.call(int(plane.livery))
		_toast("Resprayed in your own colours.")
		_show("fleet"))
	spray.disabled = jobs.money < Liveries.PRICE


# ------------------------------------------------------------------------------
#  Co-op
# ------------------------------------------------------------------------------
var _net_status: Label


func _page_coop() -> void:
	var dim := Color(0.66, 0.66, 0.62)
	_label("CO-OP", 26, Color(0.90, 0.50, 0.18))
	_label("One of you hosts, the others join with the host's address. Hosting tries to open port %d on your router by itself and then shows the address to give your friend (on the same network: %s). Everyone flies their own plane; walk up to a friend's plane and press %s to ride along, and %s to ask for (or hand over) the controls." % [net.PORT, net.local_address(), Game.hint("interact"), Game.hint("controls")], 14, dim)
	var name_row := _row("Your name")
	var name_e := LineEdit.new()
	name_e.text = net.player_name
	name_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_e.text_changed.connect(func(t): net.player_name = t if t.strip_edges() != "" else "Pilot")
	name_row.add_child(name_e)
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 10)
	_content.add_child(host_row)
	_button("Host a game", func():
		var err: String = net.host()
		if err != "":
			_net_status.text = err, host_row)
	_button("Leave", func(): net.leave(), host_row)
	var join_row := _row("Join address")
	var addr := LineEdit.new()
	addr.placeholder_text = "e.g. 192.168.1.20"
	addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(addr)
	_button("Join", func():
		var err2: String = net.join(addr.text.strip_edges())
		if err2 != "":
			_net_status.text = err2, join_row)
	_net_status = _label("Connected." if net.is_online() else "Not connected.", 15, Color(0.75, 0.85, 0.95))
	if not net.status_changed.is_connected(_on_net_status):
		net.status_changed.connect(_on_net_status)
	for id in net.remotes.keys():
		var r: Dictionary = net.remotes[id]
		var s: Dictionary = r.get("last", {})
		_label("  %s, flying %s%s" % [r["name"], s.get("reg", "?"), "  (on foot)" if s.get("foot", false) else ""], 14, dim)
	_back()


# ------------------------------------------------------------------------------
#  Build (on foot)
# ------------------------------------------------------------------------------
func _page_build() -> void:
	var dim := Color(0.66, 0.66, 0.62)
	_label("BUILD", 26, Color(0.90, 0.50, 0.18))
	if builds == null or walker == null or not walker.is_inside_tree() or not walker.visible:
		_label("Get out of the plane and walk to where you want to build.", 15, Color(1.0, 0.62, 0.12))
		_back()
		return
	_label("Logs on hand: %d     Money: $%s" % [builds.logs, _money(int(jobs.money))], 16, Color(0.75, 0.85, 0.95))
	_label("Fell trees with the chainsaw (%s at a tree), then buck up the trunk for logs. Trees knocked down or burnt by fire can be salvaged too." % Game.hint("interact"), 14, dim)
	var at: Vector3 = walker.global_position
	var hdg: float = builds.heading_of(walker.look.x)
	var here: int = jobs.strip_here()
	if builds.logs > 0:
		var lb := _button("Sell logs to the sawmill at Proving Ground ($%d a log)%s" % [builds.LOG_PAY, "" if here >= 0 else "   -  walk to an airstrip"], func():
			var e: String = builds.ship_logs(here, true)
			_toast("Logs on the ramp: carry them aboard and fly them to Proving Ground." if e == "" else e)
			_show("build"))
		lb.disabled = here < 0
	_spacer(6)
	_label("BUSH STRIP", 16, Color(0.95, 0.80, 0.35))
	_label("Starts where you stand and runs the way you face (%03d°). Trees in the way are cut for you, $%d each; the edges are marked with old tyres. Jobs will start coming to it." % [int(round(hdg)), builds.STRIP_PER_TREE], 14, dim)
	for L in builds.STRIP_LEN:
		var sv: Dictionary = builds.survey(at, hdg, L)
		var txt := "%d m strip toward %03d°" % [int(L), int(round(hdg))]
		if bool(sv["ok"]):
			txt += "   $%s  (%d trees to cut)" % [_money(int(sv["price"])), int(sv["trees"])]
		else:
			txt += "   -  " + String(sv["why"])
		var b := _button(txt, func():
			var err: String = builds.build_strip(sv)
			_toast("Strip laid out. It's on the map and the airstrip list." if err == "" else err)
			if err == "":
				close())
		b.disabled = not bool(sv["ok"]) or jobs.money < int(sv["price"])
	if prospect != null:
		_spacer(6)
		_label("PROSPECTING", 16, Color(0.95, 0.80, 0.35))
		_label("Gold hides in creek beds and valley bottoms, just above bedrock. Dig a pan (%s), wash it at the water and count the colours." % Game.hint("interact"), 14, dim)
		var fwd2 := Vector3(-sin(walker.look.x), 0.0, -cos(walker.look.x))
		var sb2 := _button("Set up a sluice box here at the water's edge  (you have %d)" % (prospect.owned_sluices - prospect.sluices.size()), func():
			var r: String = prospect.place_sluice(at + fwd2 * 1.2, walker.look.x)
			_toast(r)
			close())
		sb2.disabled = prospect.owned_sluices <= prospect.sluices.size()
		_button("Wash plant, set up here  $%s" % _money(prospect.WASHPLANT_PRICE), func():
			_toast(prospect.place_washplant(at + fwd2 * 6.0, walker.look.x + PI))
			close())
		_button("Small excavator, delivered here  $%s" % _money(prospect.EXCAVATOR_PRICE), func():
			_toast(prospect.buy_excavator(at + fwd2 * 4.0, walker.look.x))
			close())
		if rails != null:
			_button("Ore car, set on your track  $%s   (shovel into it, push it on the rails)" % _money(rails.CAR_PRICE), func():
				_toast(rails.buy_car(walker.global_position, jobs))
				close())
		_button("Drift miner, delivered here  $%s   (a tunnelling machine: cuts drifts)" % _money(prospect.TUNNELER_PRICE), func():
			_toast(prospect.buy_tunneler(at + fwd2 * 6.0, walker.look.x))
			close())
		_button("Bulldozer, delivered here  $%s   (cuts roads and pads)" % _money(prospect.DOZER_PRICE), func():
			_toast(prospect.buy_dozer(at + fwd2 * 5.0, walker.look.x))
			close())
	_spacer(6)
	_label("BUILDINGS", 16, Color(0.95, 0.80, 0.35))
	for kind in builds.KINDS.keys():
		var spec: Array = builds.KINDS[kind]
		var spot: Vector3 = builds.spot_for(kind, at, walker.look.x)
		var why: String = builds.cannot_build(kind, spot)
		var b2 := _button("%s   $%s + %d logs%s" % [spec[0], _money(int(spec[1])), int(spec[2]), "" if why == "" else "   -  " + why], func():
			var err2: String = builds.build(kind, spot, walker.look.x + PI)
			_toast("Built. " + String(spec[3]) if err2 == "" else err2)
			if err2 == "":
				close())
		b2.disabled = why != ""
		_label("    " + String(spec[3]), 13, dim)
	_back()


# ------------------------------------------------------------------------------
#  Working on the engine (opened by looking at a part with the cowling open)
# ------------------------------------------------------------------------------
func _page_engine() -> void:
	var dim := Color(0.66, 0.66, 0.62)
	var id := engine_part
	_label(String(service.label_of(id)).to_upper(), 24, Color(0.90, 0.50, 0.18))
	if service.result != "":
		_label(service.result, 16, Color(0.95, 0.85, 0.55))
	for line in service.describe(id):
		_label(String(line), 15, Color(0.85, 0.88, 0.92))
	_spacer(4)
	for a in service.actions(id):
		var act: String = a[1]
		var why: String = a[2]
		var b := _button(String(a[0]) + ("" if why == "" else "   -  " + why), func():
			var started: String = service.do(id, act)
			if started == "" and service.working():
				close()        # watch the part come off while you work
			else:
				_show("engine"))
		b.disabled = why != "" or service.working()
	_spacer(6)
	_label(service.spares_text(), 14, dim)
	if service.at_hangar():
		_label("PARTS COUNTER (this hangar): buy spares to carry for repairs out in the bush", 15, Color(0.95, 0.80, 0.35))
		for k in service.SPARES.keys():
			var spec: Array = service.SPARES[k]
			var n := 6 if k == "oil_qt" else 1
			var kk: String = k
			_button("Buy %s%s   $%d" % ["%d x " % n if n > 1 else "", String(spec[0]).to_lower(), int(spec[1]) * n], func():
				service.result = service.buy_spare(kk, n)
				_show("engine"))
	else:
		_label("Big jobs (cylinders, magnetos, overhaul) and the parts counter are at a hangar.", 13, dim)
	_label("Money: $%s" % _money(int(jobs.money)), 14, dim)
	_spacer()
	_button("Done", func():
		service.result = ""
		close())


func _on_net_status(t: String) -> void:
	if _net_status != null and is_instance_valid(_net_status):
		_net_status.text = t



# ------------------------------------------------------------------------------
#  Your claim (on the job board at a strip with one)
# ------------------------------------------------------------------------------
func _mining_section(k: int) -> void:
	var c: Array = mining.claim_at(k)
	if c.is_empty():
		return
	var dim := Color(0.66, 0.66, 0.62)
	_spacer(6)
	_label("CLAIM: %s" % String(c[1]).to_upper(), 16, Color(0.95, 0.80, 0.35))
	var st: Dictionary = mining.state(c[1])
	if not bool(st["owned"]):
		_label("A placer claim beside the strip. Work it, then fly the concentrate to the assay office at Proving Ground ($%d a kg)." % mining.PRICE_PER_KG, 14, dim)
		var b := _button("Buy the claim  ($%s)" % _money(int(c[2])), func():
			var err: String = mining.buy_claim(c[1], int(c[2]))
			_toast("It's yours. It starts producing now." if err == "" else err)
			_show("jobs"))
		b.disabled = jobs.money < int(c[2])
		return
	var gear: Array = mining.GEAR[int(st["gear"])]
	var sacks := int(floor(float(st["stock_kg"]) / mining.SACK_KG))
	_label("Working with: %s (%d kg an hour).  Ready: %d sacks (%d kg), worth about $%s." % [gear[0], int(gear[2]), sacks, int(float(st["stock_kg"])), _money(int(float(sacks) * mining.SACK_KG * mining.PRICE_PER_KG))], 14, dim)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_content.add_child(row)
	if sacks > 0:
		_button("Load the sacks for me", func():
			var err2: String = mining.ship(k, false)
			_toast("Loaded. Fly them to the assay office at Proving Ground." if err2 == "" else err2)
			_show("jobs"), row)
		_button("I'll carry them", func():
			var err3: String = mining.ship(k, true)
			_toast("The sacks are on the ramp off your left wingtip." if err3 == "" else err3)
			close(), row)
	if int(st["gear"]) < mining.GEAR.size() - 1:
		var nxt: Array = mining.GEAR[int(st["gear"]) + 1]
		var b2 := _button("Buy a %s  ($%s, %d kg an hour)" % [String(nxt[0]).to_lower(), _money(int(nxt[1])), int(nxt[2])], func():
			var err4: String = mining.upgrade(c[1])
			_toast("Set up and working." if err4 == "" else err4)
			_show("jobs"))
		b2.disabled = jobs.money < int(nxt[1])


# ------------------------------------------------------------------------------
#  The workshop (DESIGN_NOTES 111): park it, pick a part, see what it does
# ------------------------------------------------------------------------------
const PartsLib = preload("res://scripts/parts.gd")


## Damaged machines: fix the ones parked at the workshop, see the rest.
func _repairs_block() -> void:
	if not repairs.is_valid():
		return
	var rl: Array = repairs.call()
	if rl.is_empty():
		return
	_label("Repairs:", 15, Color(0.7, 0.7, 0.66))
	for r in rl:
		if bool(r["here"]):
			var doit: Callable = r["do"]
			_button("Fix the %s (%s)  -  $%d" % [String(r["name"]).to_lower(), String(r["status"]), int(r["cost"])], func():
				_toast(doit.call())
				_show("workshop"))
		else:
			_label("%s: %s. Bring it to the workshop to fix it ($%d)." % [String(r["name"]), String(r["status"]), int(r["cost"])], 14, Color(0.85, 0.6, 0.4))
	_spacer(6)


func _page_workshop() -> void:
	_label("WORKSHOP: PARTS AND TUNING", 26, Color(0.90, 0.50, 0.18))
	_repairs_block()
	var vs: Array = workshop.call()
	if vs.is_empty():
		_label("Nothing's parked at the workshop. Bring the pickup or a plane onto the Proving Ground apron (by the hangar), stop, switch the engine off, then come back here.", 15, Color(0.75, 0.75, 0.7))
		_back()
		return
	_ws_i = clampi(_ws_i, 0, vs.size() - 1)
	if vs.size() > 1:
		var vrow := HFlowContainer.new()             # wraps onto a second line with many machines
		vrow.add_theme_constant_override("h_separation", 10)
		vrow.add_theme_constant_override("v_separation", 6)
		_content.add_child(vrow)
		for i in range(vs.size()):
			var ii := i
			var b := _button(String(vs[i]["name"]), func():
				_ws_i = ii
				_ws_slot = ""
				_show("workshop"), vrow)
			b.disabled = i == _ws_i
	var v: Dictionary = vs[_ws_i]
	var key: String = v["key"]
	if not PartsLib.fitted.has(key):
		PartsLib.fitted[key] = {}
	var fitted: Dictionary = PartsLib.fitted[key]
	var busy: String = (v["busy"] as Callable).call()
	var now: Dictionary = (v["estimate"] as Callable).call(fitted)
	_label("%s   -   %s" % [v["name"], _ws_stats(now)], 16, Color(0.85, 0.9, 0.8))
	if busy != "":
		_label(busy, 15, Color(1.0, 0.6, 0.3))
	_spacer(4)
	if _ws_slot == "":
		_label("What's in it (pick one to change it):", 15, Color(0.7, 0.7, 0.66))
		for sl in v["slots"]:
			var slot := String(sl)
			var u := int(fitted.get(slot, 0))
			var txt := "%-22s %s" % [String(PartsLib.SLOT_NAMES[slot]).capitalize() + ":", PartsLib.label(u) if u > 0 else "- none -"]
			_button(txt, func():
				_ws_slot = slot
				_show("workshop"))
		# the gauge pod: send a reading to each gauge (DESIGN_NOTES 121)
		if v.has("pod_get"):
			_spacer(6)
			var cur: Array = (v["pod_get"] as Callable).call()
			_label("Gauge pod wiring (the %d gauges under the %s):" % [cur.size(), "panel" if v.get("pod_plane", false) else "dash"], 15, Color(0.7, 0.7, 0.66))
			var wl = load("res://scripts/gauge_wiring.gd")
			var order: Array = wl.PLANE_ORDER if v.get("pod_plane", false) else wl.ORDER
			var sigs: Dictionary = wl.PLANE_SIGNALS if v.get("pod_plane", false) else wl.SIGNALS
			var names: Array = []
			for sid in order:
				names.append(String(sigs[sid][0]))
			for gi in range(cur.size()):
				var gix := gi
				var sel: int = order.find(cur[gi])
				_option(_row("Gauge %d" % (gi + 1)), names, maxi(sel, 0), func(i):
					(v["pod_set"] as Callable).call(gix, String(order[i]))
					_toast("Gauge %d now reads: %s" % [gix + 1, names[i]]))
		_spacer()
		_label("On the shelves: %d parts." % PartsLib.storage.size(), 14, Color(0.6, 0.6, 0.56))
		_back()
		return
	# --- one slot ---
	var slot2 := _ws_slot
	var cur := int(fitted.get(slot2, 0))
	_label(String(PartsLib.SLOT_NAMES[slot2]).capitalize() + (": " + PartsLib.label(cur) if cur > 0 else ": none fitted"), 20)
	if cur > 0:
		var without := fitted.duplicate()
		without.erase(slot2)
		for dsl in PartsLib.dependents(slot2):
			without.erase(dsl)
		var e0: Dictionary = (v["estimate"] as Callable).call(without)
		var deps: Array = []
		for dsl2 in PartsLib.dependents(slot2):
			if fitted.has(dsl2):
				deps.append(PartsLib.SLOT_NAMES[dsl2])
		var rb := _button("Take it off (onto the shelves)%s   ->   %s" % [("  (and the " + ", ".join(deps) + ")") if not deps.is_empty() else "", _ws_delta(now, e0)], func():
			_ws_remove(key, slot2)
			(v["changed"] as Callable).call()
			_show("workshop"))
		rb.disabled = busy != ""
	# parts on the shelves that would go in: pick one and it's swapped in,
	# with whatever goes with it (DESIGN_NOTES 111)
	var tags: Array = v["tags"]
	var any := false
	for u2 in PartsLib.storage:
		var uid := int(u2)
		if String(PartsLib.def_of(uid).get("slot", "")) != slot2:
			continue
		any = true
		var pl := PartsLib.plan_swap(uid, slot2, tags, fitted)
		var why := String(pl["why"])
		var e1: Dictionary = (v["estimate"] as Callable).call(pl["fitted"]) if why == "" else {}
		var notes: Array = pl["notes"]
		PartsLib.discard_plan(pl)
		var b2 := _button("Fit: %s%s   ->   %s" % [PartsLib.label(uid), _ws_notes(notes, cur), _ws_delta(now, e1) if why == "" else why], func():
			_ws_swap(v, key, slot2, uid))
		b2.disabled = why != "" or busy != ""
	if not any:
		_label("Nothing for this on the shelves.", 14, Color(0.6, 0.6, 0.56))
	# buy new
	_spacer(4)
	_label("Buy new (fitted straight away, the old one goes on the shelves):", 15, Color(0.7, 0.7, 0.66))
	var all_defs: Dictionary = PartsLib.CATALOG.duplicate()
	all_defs.merge(PartsLib.CHASSIS)
	for d in all_defs.keys():
		var dd: Dictionary = all_defs[d]
		if String(dd["slot"]) != slot2:
			continue
		var did := String(d)
		var price := int(dd["price"])
		var tmp := PartsLib.make(did, 1.0)
		var pl2 := PartsLib.plan_swap(tmp, slot2, tags, fitted)
		var why2 := String(pl2["why"])
		var e2: Dictionary = (v["estimate"] as Callable).call(pl2["fitted"]) if why2 == "" else {}
		var total := price + int(pl2["cost"])
		var notes2: Array = pl2["notes"]
		PartsLib.discard_plan(pl2)
		PartsLib.inst.erase(tmp)
		var bb := _button("%s  $%d%s   ->   %s" % [dd["name"], total, _ws_notes(notes2, cur), _ws_delta(now, e2) if why2 == "" else why2], func():
			_ws_swap(v, key, slot2, -1, did))
		bb.disabled = why2 != "" or busy != ""
	_spacer()
	_button("Back to the parts list", func():
		_ws_slot = ""
		_show("workshop"))


func _ws_stats(e: Dictionary) -> String:
	if String(e.get("ok", "")) != "":
		return "won't run: " + String(e["ok"])
	var t := "%.0f hp" % float(e.get("hp", 0.0))
	if float(e.get("boost", 0.0)) > 0.3:
		t += " (%.1f psi boost)" % float(e["boost"])
	if e.has("top_kmh"):
		t += ", top %.0f km/h" % float(e["top_kmh"])
	if e.has("hp_high"):
		t += ", %.0f hp at 8,000 ft" % float(e["hp_high"])
	if e.has("temp_f"):
		t += ", runs at %.0f F flat out" % float(e["temp_f"])
	t += ", %.0f kg" % float(e.get("kg", 0.0))
	return t


func _ws_delta(a: Dictionary, b: Dictionary) -> String:
	if b.is_empty():
		return ""
	if String(b.get("ok", "")) != "":
		return "won't run (%s)" % b["ok"]
	var bits: Array = []
	var dh := float(b.get("hp", 0.0)) - float(a.get("hp", 0.0))
	bits.append("%.0f hp (%+.0f)" % [float(b.get("hp", 0.0)), dh])
	if float(b.get("boost", 0.0)) > 0.3:
		bits.append("%.1f psi" % float(b["boost"]))
	if b.has("top_kmh"):
		bits.append("top %.0f km/h" % float(b["top_kmh"]))
	if b.has("hp_high"):
		bits.append("%.0f hp at 8,000 ft" % float(b["hp_high"]))
	if b.has("temp_f") and float(b["temp_f"]) > 215.0:
		bits.append("OVERHEATS (%.0f F)" % float(b["temp_f"]))
	var dk := float(b.get("kg", 0.0)) - float(a.get("kg", 0.0))
	if absf(dk) > 0.5:
		bits.append("%+.0f kg" % dk)
	return ", ".join(bits)


## What else a swap does, for the button: "(also fits the ..., takes off ...)".
func _ws_notes(notes: Array, cur: int) -> String:
	var bits: Array = []
	if cur > 0:
		bits.append("swaps out the " + PartsLib.label(cur).to_lower())
	bits.append_array(notes)
	return ("   (" + "; ".join(bits) + ")") if not bits.is_empty() else ""


## Swap it in: a part off the shelves (uid), or a new one bought (did).
## Plans again now (things may have changed), pays, fits, and stops the
## engine if it was running.
func _ws_swap(v: Dictionary, key: String, slot: String, uid: int, did: String = "") -> void:
	var tags: Array = v["tags"]
	var nu := uid
	if did != "":
		nu = PartsLib.make(did, 1.0)
	var pl := PartsLib.plan_swap(nu, slot, tags, PartsLib.fitted[key])
	if String(pl["why"]) != "":
		if did != "":
			PartsLib.inst.erase(nu)
		_toast(String(pl["why"]))
		return
	var price := (int(PartsLib.CATALOG.get(did, PartsLib.CHASSIS.get(did, {})).get("price", 0)) if did != "" else 0) + int(pl["cost"])
	if price > 0 and not (Game.sandbox or Game.free_repairs):
		if jobs == null or jobs.money < price:
			PartsLib.discard_plan(pl)
			if did != "":
				PartsLib.inst.erase(nu)
			_toast("Not enough money: it's $%d." % price)
			return
		jobs.money -= price
		jobs.save_career()
	PartsLib.apply_plan(key, pl)
	(v["changed"] as Callable).call()
	var extra: Array = pl["notes"]
	_toast("Fitted: %s%s" % [PartsLib.label(nu), (" (and " + ", ".join(extra) + ")") if not extra.is_empty() else ""])
	_show("workshop")


## Take a part off (and what hangs on it) onto the shelves.
func _ws_remove(key: String, slot: String) -> void:
	var fitted: Dictionary = PartsLib.fitted[key]
	for sl in [slot] + PartsLib.dependents(slot):
		if fitted.has(sl):
			PartsLib.storage.append(int(fitted[sl]))
			fitted.erase(sl)
	PartsLib.save_all()
	_toast("Taken off and put on the shelves.")




## Season, time of day, wind and weather (the host's to set in co-op).
func _world_rows() -> void:
	_option(_row("Season"), Game.SEASON_NAMES, Game.season, func(i):
		Game.season = i
		Game.notify_changed())

	var time_row := _row("Time of day")
	var time_s := HSlider.new()
	time_s.min_value = 0.0
	time_s.max_value = 23.5
	time_s.step = 0.5
	time_s.value = Game.time_of_day
	time_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var time_l := Label.new()
	time_l.custom_minimum_size = Vector2(70, 0)
	time_l.text = _clock(Game.time_of_day)
	time_s.value_changed.connect(func(v):
		Game.time_of_day = v
		time_l.text = _clock(v)
		Game.notify_changed())
	time_row.add_child(time_s)
	time_row.add_child(time_l)

	_option(_row("Wind"), Game.WIND_NAMES, Game.wind_level, func(i):
		Game.wind_level = i
		Game.notify_changed())
	_option(_row("Weather"), Game.WEATHER_NAMES, Game.weather, func(i):
		Game.weather = i
		Game.notify_changed())
	_option(_row("Weather changes"), ["Stays as set", "Fronts come and go"], 1 if Game.weather_changes else 0, func(i):
		Game.weather_changes = i == 1
		Game.notify_changed())

	var dir_row := _row("Wind from")
	var dir_s := HSlider.new()
	dir_s.min_value = 0.0
	dir_s.max_value = 350.0
	dir_s.step = 10.0
	dir_s.value = Game.wind_dir_deg
	dir_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dir_l := Label.new()
	dir_l.custom_minimum_size = Vector2(70, 0)
	dir_l.text = "%03d°" % int(Game.wind_dir_deg)
	dir_s.value_changed.connect(func(v):
		Game.wind_dir_deg = v
		dir_l.text = "%03d°" % int(v)
		Game.notify_changed())
	dir_row.add_child(dir_s)
	dir_row.add_child(dir_l)


func _map_row() -> void:
	_option(_row("Map"), ["Alaska (the northern bush)", "Outback (Australia)"], 1 if Game.map == "outback" else 0, func(i):
		var want := "outback" if i == 1 else "north"
		if want == Game.map:
			return
		Game.map = want
		Game.save_settings()
		# A different country: build the world again (your planes, money and
		# jobs carry over).
		get_tree().paused = false
		get_tree().reload_current_scene())
