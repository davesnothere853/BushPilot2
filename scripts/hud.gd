extends Control
## Instrument panel, messages, navigation marker, chart and help, all drawn in code.
## The gauges are the round "steam gauges" of a late-1980s light aircraft.

const Terrain = preload("res://scripts/terrain.gd")
const EngineScript = preload("res://scripts/engine.gd")
const Layout = preload("res://scripts/panel_layout.gd")

const FACE := Color(0.045, 0.045, 0.05)
const BEZEL := Color(0.20, 0.20, 0.21)
const MARK := Color(0.93, 0.93, 0.90)
const DIM := Color(0.70, 0.70, 0.68)
const AMBER := Color(1.0, 0.62, 0.12)
const GREEN := Color(0.25, 0.80, 0.30)
const RED := Color(0.92, 0.18, 0.14)
const SKY := Color(0.22, 0.47, 0.80)
const EARTH := Color(0.45, 0.30, 0.16)
const PANEL := Color(0.115, 0.105, 0.10)

var plane: Node3D
var terrain: RefCounted
var wind: Node
var camera: Camera3D

var cockpit_mode := false
var panel3d := false                # true: this copy paints the cockpit's instrument panel
var cockpit_has_panel := false      # the 3D cockpit shows its own gauges, so skip the flat ones
var face_spec := {}                  # a dial spec (like panel_layout DIALS) for a face_id not in the layout
var face_id := ""                   # set: this copy paints one dial face (no needles) for a 3D instrument
var face_scale := 1.0               # picture pixels per drawing unit for a dial face
var tooltip := ""                   # name and state of the cockpit control under the mouse
var tooltip_pos := Vector2.ZERO
var cockpit_dot := false            # mouse captured in the cockpit: the dot works switches
var target_strip := -1
var show_help := true
var foot_keys := true
var crosshair := false           # the pistol's in hand: a dot; aiming (aim 0..1): the full reticle
var aim := 0.0
var in_machine := false
var inset_on := false
var _redraw_t := 0.0             # the 3D chart is open: show the close-up beside it
var goals: Array = []              # [[text, done], ...] the getting-started list (main._goals_tick)            # driving a truck or machine: the walking keys don't apply
var blackout := 0.0          # 0..1 black over everything (passed out)
var drunk_text := ""         # BUZZED / DRUNK ... shown at the top
var tutorial_text := ""               # set by tutorial.gd                 # the key legend while on foot
var show_map := false
var crash_text := ""
var red_flash := 0.0             # blood on the lens (prop strike): 1 fades to a red tint
var walker: Node3D                  # set while the pilot is out on foot
var jobs: Node                      # jobs.gd, for the line about what is on board
var skydive: Node3D             # skydive.gd
var cargo: Node3D                   # cargo.gd, for its pick-up / load prompt

var _font: Font
var _messages: Array = []       # each is [text, seconds left]
var _map_tex: ImageTexture
var _map_season := -1
var _blink := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# DIN lettering like the menus and a cockpit placard (DESIGN_NOTES 163)
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift", "DIN Alternate", "DIN", "Roboto Condensed", "Arial Narrow", "Segoe UI"])
	sf.font_weight = 500
	_font = sf


func push_message(text: String, seconds: float = 5.0) -> void:
	for m in _messages:
		if m[0] == text:
			m[1] = seconds
			return
	_messages.append([text, seconds])
	if _messages.size() > 4:
		_messages.pop_front()


func _process(delta: float) -> void:
	if red_flash > 0.35:
		red_flash = maxf(red_flash - delta * 0.25, 0.35)
	if terrain != null and target_strip >= terrain.strips.size():
		target_strip = -1          # a strip that no longer exists (the demo is one square)
	_blink = fposmod(_blink + delta, 1.0)
	for m in _messages:
		m[1] -= delta
	_messages = _messages.filter(func(m): return m[1] > 0.0)
	# (DESIGN_NOTES 171) on foot nothing on the HUD moves fast (bars, prompts,
	# the legend, messages): 20 redraws a second there, every frame flying
	if walker != null and not show_map and face_id == "" and not panel3d and red_flash <= 0.36 and (aim <= 0.0 or aim >= 1.0):
		_redraw_t += delta
		if _redraw_t < 0.05:
			return
		_redraw_t = 0.0
	queue_redraw()


# ------------------------------------------------------------------------------
#  Drawing helpers
# ------------------------------------------------------------------------------
## Unit vector for a gauge angle: 0 is straight up, positive is clockwise.
static func _dir(angle_deg: float) -> Vector2:
	var a := deg_to_rad(angle_deg)
	return Vector2(sin(a), -cos(a))


func _text(pos: Vector2, text: String, size_px: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, width: float = 200.0) -> void:
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= width
	# Baseline sits about a third of the font size below the centre line.
	p.y += size_px * 0.36
	if face_scale != 1.0:
		# Draw text at full resolution rather than stretching small glyphs.
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_string(_font, p * face_scale, text, align, width * face_scale, int(round(size_px * face_scale)), col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(face_scale, face_scale))
		return
	draw_string(_font, p, text, align, width, size_px, col)


func _shadow_text(pos: Vector2, text: String, size_px: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = 900.0) -> void:
	_text(pos + Vector2(1.5, 1.5), text, size_px, Color(0, 0, 0, 0.75), align, width)
	_text(pos, text, size_px, col, align, width)


func _face(c: Vector2, r: float, title: String, title_at: Vector2 = Vector2(0, 0.42)) -> void:
	draw_circle(c, r + 7.0, Color(0.03, 0.03, 0.03, 0.9 if cockpit_mode else 0.55))
	draw_circle(c, r + 5.0, BEZEL)
	draw_circle(c, r, FACE)
	if title != "":
		_text(c + title_at * r, title, 10, DIM)


func _ticks(c: Vector2, r: float, from_deg: float, to_deg: float, count: int, length: float, width: float, col: Color = MARK) -> void:
	for i in range(count + 1):
		var d := _dir(lerpf(from_deg, to_deg, float(i) / float(count)))
		draw_line(c + d * (r - length), c + d * r, col, width, true)


func _arc(c: Vector2, r: float, from_deg: float, to_deg: float, col: Color, width: float) -> void:
	draw_arc(c, r, deg_to_rad(from_deg - 90.0), deg_to_rad(to_deg - 90.0), 28, col, width, true)


func _needle(c: Vector2, angle_deg: float, length: float, width: float, col: Color = MARK, tail: float = 10.0) -> void:
	if face_id != "":
		return      # the 3D instrument has real needles
	var d := _dir(angle_deg)
	draw_line(c - d * tail, c + d * length, col, width, true)
	draw_circle(c, width * 1.4, Color(0.25, 0.25, 0.26))


# ------------------------------------------------------------------------------
#  Main draw
# ------------------------------------------------------------------------------
func _draw() -> void:
	if plane == null:
		return
	if red_flash > 0.0:
		var vs := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.55, 0.0, 0.0, red_flash * 0.55))
		var rng := RandomNumberGenerator.new()
		rng.seed = 81
		for i in range(26):
			var c := Vector2(rng.randf() * vs.x, rng.randf() * vs.y * 0.8)
			draw_circle(c, rng.randf_range(8.0, 60.0), Color(0.35, 0.0, 0.0, 0.75 * minf(red_flash * 1.5, 1.0)))
			for k in range(4):
				draw_circle(c + Vector2(rng.randf_range(-1, 1), rng.randf_range(0, 2)) * 70.0, rng.randf_range(2.0, 9.0), Color(0.4, 0.0, 0.0, 0.7 * minf(red_flash * 1.5, 1.0)))
	if face_id != "":
		_draw_face()
		return
	if inset_on and plane != null:
		var szi := size
		_draw_local_inset(szi, Vector2(24.0 - 32.0, 120.0), 0.0)        # top left, under the readout
	if panel3d:
		_draw_panel3d()
		return
	var sz := size
	if crosshair and walker != null:
		_draw_crosshair(sz)
	if blackout > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, blackout))
	if drunk_text != "":
		_text(Vector2(sz.x * 0.5, 30.0), drunk_text, 15, Color(1.0, 0.72, 0.25), HORIZONTAL_ALIGNMENT_CENTER, 300.0)
	if show_map:
		_draw_map(sz)
		_draw_messages(sz)
		return
	if walker != null:
		_draw_target_marker(sz)
		_draw_on_foot(sz)
		_draw_messages(sz)
		return
	_draw_target_marker(sz)
	if (not cockpit_mode and Game.chase_gauges) or (cockpit_mode and (not cockpit_has_panel or Game.cockpit_overlay)):
		_draw_panel(sz)
	elif not cockpit_mode:
		_draw_annunciators(Vector2(sz.x * 0.5, 34.0))
	elif cockpit_mode:
		_draw_annunciators(Vector2(sz.x * 0.5, 34.0))
	_draw_info(sz)
	if crash_text == "" and (plane.is_crashed or (plane.on_ground and plane.ground_speed < 0.8)):
		_shadow_text(Vector2(sz.x * 0.5 - 150.0, sz.y * 0.16), "%s   Get out" % Game.hint("get_out"), 17, Color(0.92, 0.88, 0.78, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 300.0)
	if cockpit_mode and cockpit_dot:
		draw_circle(sz * 0.5, 2.6, Color(0, 0, 0, 0.45))
		draw_circle(sz * 0.5, 1.8, Color(1, 1, 1, 0.75) if tooltip == "" else Color(1.0, 0.8, 0.35, 0.95))
	if tooltip != "" and cockpit_mode:
		_draw_tooltip()
	_draw_messages(sz)
	if show_help and not plane.is_crashed:
		_draw_help(sz)


func _draw_panel(sz: Vector2) -> void:
	var r := 62.0
	var gap := 144.0
	var count := 7
	var total := gap * float(count - 1)
	var y := sz.y - r - 40.0
	var x0 := sz.x * 0.5 - total * 0.5 - 40.0
	if cockpit_mode:
		var top := sz.y - 2.0 * r - 74.0
		draw_rect(Rect2(0, top, sz.x, sz.y - top), PANEL)
		draw_rect(Rect2(0, top - 14.0, sz.x, 16.0), Color(0.05, 0.05, 0.05))
		draw_line(Vector2(0, top + 2.0), Vector2(sz.x, top + 2.0), Color(0.22, 0.20, 0.18), 2.0)
	_g_airspeed(Vector2(x0, y), r)
	_g_attitude(Vector2(x0 + gap, y), r)
	_g_altimeter(Vector2(x0 + gap * 2.0, y), r)
	_g_vsi(Vector2(x0 + gap * 3.0, y), r)
	_g_heading(Vector2(x0 + gap * 4.0, y), r)
	_g_tach(Vector2(x0 + gap * 5.0, y), r)
	_g_fuel(Vector2(x0 + gap * 6.0, y), r)
	_g_levers(Vector2(x0 + gap * 6.0 + r + 30.0, y), r)
	# (the engine box that sat bottom left is gone: with the gauges up it
	# only repeated them - DESIGN_NOTES 153)
	_draw_annunciators(Vector2(sz.x * 0.5, y - r - 30.0))


func _g_airspeed(c: Vector2, r: float) -> void:
	_face(c, r, "KNOTS", Vector2(0, -0.30))
	var a0 := 30.0
	var a1 := 330.0
	var vmax := 180.0
	var ang := func(v: float) -> float: return lerpf(a0, a1, clampf(v / vmax, 0.0, 1.0))
	_arc(c, r - 4.0, ang.call(42.0), ang.call(90.0), Color(0.95, 0.95, 0.95), 3.0)
	_arc(c, r - 8.0, ang.call(50.0), ang.call(135.0), GREEN, 4.0)
	_arc(c, r - 8.0, ang.call(135.0), ang.call(165.0), Color(0.95, 0.85, 0.15), 4.0)
	var red_d := _dir(ang.call(165.0))
	draw_line(c + red_d * (r - 14.0), c + red_d * r, RED, 3.0, true)
	_ticks(c, r - 11.0, a0, a1, 18, 6.0, 1.5)
	for v in range(20, 181, 20):
		var d := _dir(ang.call(float(v)))
		_text(c + d * (r - 28.0), str(v), 12, MARK, HORIZONTAL_ALIGNMENT_CENTER, 40.0)
	_needle(c, ang.call(plane.ias_kt), r - 12.0, 3.0)


func _g_attitude(c: Vector2, r: float) -> void:
	_face(c, r, "")
	var roll: float = plane.roll_rad()
	var pitch_deg: float = rad_to_deg(plane.pitch_rad())
	var ppd := r / 28.0                                  # pixels per degree of pitch
	var g := Vector2(sin(roll), cos(roll))                # screen direction toward the ground
	var along := Vector2(cos(roll), -sin(roll))           # direction along the horizon
	var centre := c + g * (pitch_deg * ppd)
	# Sky disc, then the part of it below the horizon in brown.
	draw_circle(c, r, SKY)
	var poly := PackedVector2Array()
	var n := 40
	var prev := c + Vector2(r, 0)
	var prev_in := (prev - centre).dot(g) > 0.0
	for i in range(1, n + 1):
		var a := TAU * float(i) / float(n)
		var cur := c + Vector2(cos(a), sin(a)) * r
		var cur_in := (cur - centre).dot(g) > 0.0
		if cur_in != prev_in:
			var d0 := (prev - centre).dot(g)
			var d1 := (cur - centre).dot(g)
			poly.append(prev.lerp(cur, d0 / (d0 - d1)))
		if cur_in:
			poly.append(cur)
		prev = cur
		prev_in = cur_in
	if poly.size() >= 3 and not Geometry2D.triangulate_polygon(poly).is_empty():
		draw_colored_polygon(poly, EARTH)
	# Horizon and pitch ladder
	for deg in [-20, -10, 0, 10, 20]:
		var p: Vector2 = centre - g * (float(deg) * ppd)
		if (p - c).length() > r - 8.0:
			continue
		var half_len := r if deg == 0 else 16.0
		var a_pt := p - along * half_len
		var b_pt := p + along * half_len
		if deg == 0:
			# Trim the horizon line to the dial.
			var t := sqrt(maxf(r * r - (p - c).length_squared(), 0.0))
			var mid := c + along * (p - c).dot(along)
			a_pt = p + along * ((mid - p).dot(along) - t)
			b_pt = p + along * ((mid - p).dot(along) + t)
		draw_line(a_pt, b_pt, MARK, 2.0 if deg == 0 else 1.5, true)
	# Bank marks and pointer
	for bank in [-60, -30, -20, -10, 0, 10, 20, 30, 60]:
		var d := _dir(float(bank))
		draw_line(c + d * (r - (9.0 if bank % 30 == 0 else 5.0)), c + d * r, MARK, 1.5, true)
	var pd := _dir(-rad_to_deg(roll))
	var pside := Vector2(-pd.y, pd.x)
	draw_colored_polygon(PackedVector2Array([c + pd * (r - 10.0), c + pd * (r - 20.0) + pside * 5.0, c + pd * (r - 20.0) - pside * 5.0]), AMBER)
	# Fixed aeroplane symbol
	draw_line(c + Vector2(-34, 0), c + Vector2(-12, 0), AMBER, 3.5, true)
	draw_line(c + Vector2(12, 0), c + Vector2(34, 0), AMBER, 3.5, true)
	draw_circle(c, 3.0, AMBER)
	draw_arc(c, r + 2.5, 0.0, TAU, 48, BEZEL, 5.0, true)
	# Slip ball in a tube under the dial face
	var tube := c + Vector2(0, r - 12.0)
	draw_rect(Rect2(tube.x - 26.0, tube.y - 6.0, 52.0, 12.0), Color(0.82, 0.82, 0.76))
	draw_line(tube + Vector2(-7, -6), tube + Vector2(-7, 6), FACE, 1.5)
	draw_line(tube + Vector2(7, -6), tube + Vector2(7, 6), FACE, 1.5)
	draw_circle(tube + Vector2(plane.slip_ball * 19.0, 0), 5.5, FACE)


func _g_altimeter(c: Vector2, r: float) -> void:
	_face(c, r, "ALT  FEET", Vector2(0, 0.27))
	_ticks(c, r - 4.0, 0.0, 360.0, 50, 4.0, 1.0)
	_ticks(c, r - 4.0, 0.0, 360.0, 10, 9.0, 2.0)
	for i in range(10):
		_text(c + _dir(36.0 * float(i)) * (r - 22.0), str(i), 14, MARK, HORIZONTAL_ALIGNMENT_CENTER, 30.0)
	var alt: float = maxf(plane.altitude_ft(), 0.0)
	_needle(c, alt / 10000.0 * 360.0, r * 0.48, 5.0)
	_needle(c, fposmod(alt, 1000.0) / 1000.0 * 360.0, r - 10.0, 2.5)
	if face_id == "":
		draw_rect(Rect2(c.x - 26.0, c.y - 30.0, 52.0, 17.0), Color(0, 0, 0))
		_text(c + Vector2(0, -21.5), "%05d" % int(round(alt / 10.0) * 10.0), 13, MARK, HORIZONTAL_ALIGNMENT_CENTER, 60.0)


func _g_vsi(c: Vector2, r: float) -> void:
	_face(c, r, "FPM x100", Vector2(0.30, 0.0))
	for v in [-20, -15, -10, -5, 0, 5, 10, 15, 20]:
		var a := 270.0 + float(v) / 20.0 * 165.0
		var d := _dir(a)
		draw_line(c + d * (r - 10.0), c + d * (r - 2.0), MARK, 2.0, true)
		if v != 0:
			_text(c + d * (r - 22.0), str(absi(v)), 11, MARK, HORIZONTAL_ALIGNMENT_CENTER, 30.0)
	_text(c + Vector2(-r + 22.0, -12.0), "UP", 9, DIM, HORIZONTAL_ALIGNMENT_CENTER, 30.0)
	_text(c + Vector2(-r + 22.0, 12.0), "DN", 9, DIM, HORIZONTAL_ALIGNMENT_CENTER, 30.0)
	var vs: float = clampf(plane.vertical_speed_fpm() / 100.0, -20.0, 20.0)
	_needle(c, 270.0 + vs / 20.0 * 165.0, r - 12.0, 3.0)


func _g_heading(c: Vector2, r: float) -> void:
	_face(c, r, "")
	var hdg: float = plane.heading_deg()
	var names := {0: "N", 90: "E", 180: "S", 270: "W"}
	for deg in range(0, 360, 10):
		var d := _dir(float(deg) - hdg)
		var long := deg % 30 == 0
		draw_line(c + d * (r - (10.0 if long else 5.0)), c + d * (r - 1.0), MARK, 1.5, true)
		if long:
			var label: String = names[deg] if names.has(deg) else str(deg / 10)
			_text(c + d * (r - 22.0), label, 14 if names.has(deg) else 12, AMBER if deg == 0 else MARK, HORIZONTAL_ALIGNMENT_CENTER, 30.0)
	# Bearing bug for the selected airstrip
	if target_strip >= 0:
		var brg := _bearing_to(target_strip)
		var bd := _dir(brg - hdg)
		var bs := Vector2(-bd.y, bd.x)
		draw_colored_polygon(PackedVector2Array([c + bd * (r - 1.0), c + bd * (r + 9.0) + bs * 6.0, c + bd * (r + 9.0) - bs * 6.0]), AMBER)
	# Lubber line and aeroplane outline
	draw_line(c + Vector2(0, -r), c + Vector2(0, -r + 13.0), AMBER, 2.5, true)
	draw_line(c + Vector2(0, -15), c + Vector2(0, 16), MARK, 2.5, true)
	draw_line(c + Vector2(-15, -2), c + Vector2(15, -2), MARK, 2.5, true)
	draw_line(c + Vector2(-6, 13), c + Vector2(6, 13), MARK, 2.0, true)
	_text(c + Vector2(0, r * 0.5), "%03d" % (int(round(hdg)) % 360), 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, 40.0)


func _g_tach(c: Vector2, r: float) -> void:
	_face(c, r, "RPM x100", Vector2(0, 0.58))
	var a0 := -130.0
	var a1 := 130.0
	var ang := func(v: float) -> float: return lerpf(a0, a1, clampf(v / 3000.0, 0.0, 1.0))
	_arc(c, r - 6.0, ang.call(2000.0), ang.call(2500.0), GREEN, 4.0)
	var rd := _dir(ang.call(2700.0))
	draw_line(c + rd * (r - 13.0), c + rd * r, RED, 3.0, true)
	_ticks(c, r - 9.0, a0, a1, 30, 5.0, 1.0)
	for v in range(0, 31, 5):
		var d := _dir(ang.call(float(v) * 100.0))
		draw_line(c + d * (r - 18.0), c + d * (r - 9.0), MARK, 2.0, true)
		_text(c + d * (r - 28.0), str(v), 12, MARK, HORIZONTAL_ALIGNMENT_CENTER, 30.0)
	_needle(c, ang.call(plane.rpm), r - 14.0, 3.0)


func _g_fuel(c: Vector2, r: float) -> void:
	_face(c, r, "FUEL", Vector2(0, 0.30))
	var a0 := -60.0
	var a1 := 60.0
	_arc(c, r - 12.0, a0, a1, MARK, 2.0)
	_arc(c, r - 12.0, a0, a0 + 16.0, RED, 4.0)
	for i in range(5):
		var d := _dir(lerpf(a0, a1, float(i) / 4.0))
		draw_line(c + d * (r - 20.0), c + d * (r - 8.0), MARK, 2.0, true)
	_text(c + _dir(a0) * (r - 30.0), "E", 13, MARK, HORIZONTAL_ALIGNMENT_CENTER, 20.0)
	_text(c + _dir(a1) * (r - 30.0), "F", 13, MARK, HORIZONTAL_ALIGNMENT_CENTER, 20.0)
	var frac: float = clampf(plane.fuel / plane.fuel_capacity, 0.0, 1.0)
	_needle(c, lerpf(a0, a1, frac), r - 16.0, 3.0, MARK, 0.0)
	_text(c + Vector2(0, r * 0.70), "%.0f gal" % plane.fuel_gallons(), 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, 80.0)


func _g_levers(c: Vector2, r: float) -> void:
	# Throttle, propeller, mixture, flap and trim positions as vertical slots.
	var labels := ["THR", "PROP", "MIX", "FLAP", "TRIM"]
	var knobs := [Color(0.10, 0.10, 0.10), Color(0.25, 0.35, 0.75), Color(0.80, 0.15, 0.12), MARK, MARK]
	var top := c.y - r + 8.0
	var height := 2.0 * r - 34.0
	var e = plane.engine
	var bg := Color(0.03, 0.03, 0.03, 0.9 if cockpit_mode else 0.55)
	for i in range(5):
		var x := c.x + 30.0 * float(i)
		draw_rect(Rect2(x - 11.0, top - 6.0, 22.0, height + 12.0), bg)
		draw_rect(Rect2(x - 2.0, top, 4.0, height), Color(0.25, 0.25, 0.26))
		var k := 0.0
		match i:
			0:
				k = 1.0 - plane.throttle
			1:
				k = 1.0 - e.prop_lever
			2:
				k = 1.0 - e.mixture
				# Mark where best power sits for this altitude.
				var by: float = top + height * (1.0 - e.best_mixture)
				draw_line(Vector2(x - 9.0, by), Vector2(x + 9.0, by), Color(GREEN, 0.8), 1.0)
			3:
				k = plane.flaps
				for notch in range(5):
					var ny := top + height * float(notch) / 4.0
					draw_line(Vector2(x - 8.0, ny), Vector2(x + 8.0, ny), DIM, 1.0)
			4:
				k = 0.5 - plane.trim * 0.5
				draw_line(Vector2(x - 9.0, top + height * 0.5), Vector2(x + 9.0, top + height * 0.5), DIM, 1.0)
		var ky := top + height * clampf(k, 0.0, 1.0)
		draw_rect(Rect2(x - 8.0, ky - 4.0, 16.0, 8.0), knobs[i])
		draw_rect(Rect2(x - 8.0, ky - 4.0, 16.0, 8.0), MARK, false, 1.0)
	draw_rect(Rect2(c.x - 13.0, top + height + 10.0, 146.0, 32.0), bg)
	for i in range(5):
		_text(Vector2(c.x + 30.0 * float(i), top + height + 18.0), labels[i], 9, DIM, HORIZONTAL_ALIGNMENT_CENTER, 40.0)
	_text(Vector2(c.x + 60.0, top + height + 32.0), "%d%%   flaps %d°" % [int(round(plane.throttle * 100.0)), plane.flap_degrees()], 11, MARK, HORIZONTAL_ALIGNMENT_CENTER, 140.0)


## Engine gauges and switch positions, as a column of small bar gauges.
func _g_engine(rect: Rect2) -> void:
	var e = plane.engine
	draw_rect(rect, Color(0.03, 0.03, 0.03, 0.9 if cockpit_mode else 0.6))
	draw_rect(rect, Color(0.25, 0.25, 0.26), false, 1.0)
	var x := rect.position.x + 8.0
	var w := rect.size.x - 16.0
	var y := rect.position.y + 11.0
	# Switches
	var sw := [
		["BAT", e.master], ["ALT", e.alternator], ["CARB", e.carb_heat],
	]
	var sx := x
	for item in sw:
		var on: bool = item[1]
		draw_rect(Rect2(sx, y - 6.0, 40.0, 13.0), Color(0.55, 0.42, 0.10) if on else Color(0.16, 0.16, 0.17))
		_text(Vector2(sx + 20.0, y), item[0], 9, MARK if on else DIM, HORIZONTAL_ALIGNMENT_CENTER, 40.0)
		sx += 44.0
	var cowl_name: String = ["CWL C", "CWL H", "CWL O"][int(round(e.cowl_flaps * 2.0))]
	_text(Vector2(sx + 2.0, y), cowl_name, 9, DIM, HORIZONTAL_ALIGNMENT_LEFT, 60.0)
	y += 15.0
	_text(Vector2(x, y), "MAGS %s" % EngineScript.MAG_NAMES[e.mags], 10, AMBER if e.mags != 3 else MARK, HORIZONTAL_ALIGNMENT_LEFT, 120.0)
	_text(Vector2(x + w, y), "FUEL %s" % EngineScript.FUEL_NAMES[e.fuel_selector], 10, AMBER if e.fuel_selector != 3 else MARK, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)
	y += 16.0
	var cht_f: float = e.cht * 1.8 + 32.0
	var oil_f: float = e.oil_temp * 1.8 + 32.0
	var rows := [
		["MAN", "%.1f in" % e.map_inhg, (e.map_inhg - 10.0) / 20.0, [[0.0, 1.0, GREEN]]],
		["OIL", "%d°F" % int(oil_f), (oil_f - 40.0) / 220.0, [[(100.0 - 40.0) / 220.0, (245.0 - 40.0) / 220.0, GREEN], [(245.0 - 40.0) / 220.0, 1.0, RED]]],
		["OIL", "%d psi" % int(e.oil_press), e.oil_press / 115.0, [[0.0, 25.0 / 115.0, RED], [25.0 / 115.0, 90.0 / 115.0, GREEN], [100.0 / 115.0, 1.0, RED]]],
		["CHT", "%d°F" % int(cht_f), (cht_f - 50.0) / 450.0, [[(200.0 - 50.0) / 450.0, (460.0 - 50.0) / 450.0, GREEN], [(460.0 - 50.0) / 450.0, 1.0, RED]]],
		["EGT", "", (e.egt * 1.8 + 32.0 - 300.0) / 1300.0, []],
		["FUEL L", "%d gal" % int(e.tank_left / 2.72), e.tank_left / e.tank_capacity, [[0.0, 0.1, RED]]],
		["FUEL R", "%d gal" % int(e.tank_right / 2.72), e.tank_right / e.tank_capacity, [[0.0, 0.1, RED]]],
		["AMPS", "%+d  %.1fV" % [int(e.amps), e.volts], 0.5 + clampf(e.amps, -60.0, 60.0) / 120.0, []],
	]
	for row in rows:
		_text(Vector2(x, y), row[0], 9, DIM, HORIZONTAL_ALIGNMENT_LEFT, 50.0)
		var bx := x + 42.0
		var bw := w - 42.0 - 62.0
		draw_rect(Rect2(bx, y - 3.0, bw, 6.0), Color(0.16, 0.16, 0.17))
		for zone in row[3]:
			draw_rect(Rect2(bx + bw * float(zone[0]), y + 3.0, bw * (float(zone[1]) - float(zone[0])), 2.0), zone[2])
		var fx: float = bx + bw * clampf(float(row[2]), 0.0, 1.0)
		draw_rect(Rect2(fx - 1.5, y - 5.0, 3.0, 10.0), MARK)
		_text(Vector2(x + w, y), row[1], 10, MARK, HORIZONTAL_ALIGNMENT_RIGHT, 70.0)
		y += 14.5


func _draw_annunciators(c: Vector2) -> void:
	var items: Array = []
	pass   # no flashing STALL box (removed at Dave's request)
	if plane.on_ground:
		var wb: Vector2 = plane.wheel_brakes()
		if wb.x > 0.4 and wb.y > 0.4:
			items.append(["BRAKES", AMBER])
		elif wb.x > 0.4:
			items.append(["L BRAKE", AMBER])
		elif wb.y > 0.4:
			items.append(["R BRAKE", AMBER])
	var e = plane.engine
	if e.cranking:
		items.append(["STARTER", AMBER])
	elif not plane.engine_running and not plane.is_crashed:
		items.append(["ENGINE OFF", AMBER] if plane.on_ground else ["ENGINE OUT", RED])
	elif e.oil_press < 20.0:
		items.append(["OIL PRESS", RED])
	if e.master and e.volts > 0.1 and e.volts < 12.0 and not e.cranking:
		items.append(["LOW VOLTS", AMBER])
	if plane.fuel < 18.0:
		items.append(["LOW FUEL", AMBER])
	if plane.mass > plane.max_mass + 1.0:
		items.append(["OVERWEIGHT", AMBER])
	var frac: float = plane.cg_fraction()
	if frac > 1.0:
		items.append(["TAIL HEAVY", RED])
	elif frac < 0.0:
		items.append(["NOSE HEAVY", AMBER])
	var w := 118.0
	var x := c.x - w * float(items.size()) * 0.5
	for it in items:
		draw_rect(Rect2(x + 3.0, c.y - 13.0, w - 6.0, 26.0), Color(0.03, 0.03, 0.03, 0.85))
		draw_rect(Rect2(x + 3.0, c.y - 13.0, w - 6.0, 26.0), it[1], false, 1.5)
		_text(Vector2(x + w * 0.5, c.y), it[0], 14, it[1], HORIZONTAL_ALIGNMENT_CENTER, w)
		x += w


# ------------------------------------------------------------------------------
#  The cockpit's own instrument panel (painted into a texture)
# ------------------------------------------------------------------------------
func _draw_panel3d() -> void:
	draw_rect(Rect2(0, 0, Layout.W, Layout.H), PANEL)
	# Brushed, slightly worn paint: faint streaks and darker grime toward the bottom.
	for i in range(160):
		var y := float(i) * 4.0
		draw_line(Vector2(0, y), Vector2(Layout.W, y), Color(1, 1, 1, 0.006 + 0.006 * sin(float(i) * 1.7)), 2.0)
	draw_rect(Rect2(0, 372, Layout.W, Layout.H - 372), Color(0.092, 0.086, 0.082))
	draw_line(Vector2(0, 372), Vector2(Layout.W, 372), Color(0.05, 0.05, 0.05), 3.0)
	for i in range(10):
		draw_rect(Rect2(0, float(i) * 2.0, Layout.W, 2.0), Color(0, 0, 0, 0.5 - float(i) * 0.05))
	# Darker sub-panels behind the flight and engine instruments, with screws.
	_plate(Rect2(140, 60, 442, 300))
	_plate(Rect2(600, 62, 410, 236))
	# Lamp labels
	for lamp in Layout.LAMPS:
		_text(lamp[1] + Vector2(0, 21), lamp[2], 10, DIM, HORIZONTAL_ALIGNMENT_CENTER, 60.0)
	_panel_radio(Layout.RADIO_RECT)
	# Printed labels under the knobs and switches
	for id in Layout.CONTROLS.keys():
		var item: Array = Layout.CONTROLS[id]
		var pp: Vector2 = item[0]
		var below := 44.0 if id in ["throttle", "prop", "mixture", "carb_heat", "primer"] else 40.0
		_text(pp + Vector2(0, below), item[1], 11 if String(id).begins_with("lt_") else 13, DIM, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	var mp: Vector2 = Layout.CONTROLS["mags"][0]
	var names := ["OFF", "R", "L", "BOTH", "START"]
	for i in range(5):
		var a := -60.0 + 30.0 * float(i)
		_text(mp + _dir(a) * 40.0, names[i], 10, MARK if i != 4 else AMBER, HORIZONTAL_ALIGNMENT_CENTER, 50.0)
	var cp: Vector2 = Layout.CONTROLS["cowl"][0]
	for i in range(3):
		var y2 := cp.y - 40.0 + 40.0 * float(i)
		_text(Vector2(cp.x + 44.0, y2), ["CLOSED", "HALF", "OPEN"][i], 10, MARK, HORIZONTAL_ALIGNMENT_LEFT, 80.0)
	draw_rect(Rect2(cp.x - 4.0, cp.y - 46.0, 8.0, 92.0), Color(0.02, 0.02, 0.02))
	_text(Vector2(1140, 372 + 200), plane.reg, 16, Color(0.75, 0.72, 0.62), HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	_text(Vector2(1140, 372 + 224), "FLAPS BELOW 85 KT", 10, DIM, HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	_text(Vector2(361, 372 + 236), "MANOEUVRING SPEED 105 KT", 10, DIM, HORIZONTAL_ALIGNMENT_CENTER, 300.0)


func _plate(r: Rect2) -> void:
	draw_rect(r, Color(0.07, 0.068, 0.066))
	draw_rect(r, Color(0.03, 0.03, 0.03), false, 2.0)
	for corner in [r.position + Vector2(9, 9), r.position + Vector2(r.size.x - 9, 9), r.position + Vector2(9, r.size.y - 9), r.end - Vector2(9, 9)]:
		draw_circle(corner, 3.5, Color(0.30, 0.29, 0.28))
		draw_line(corner - Vector2(2.5, 0), corner + Vector2(2.5, 0), Color(0.1, 0.1, 0.1), 1.0)


## A 1980s nav/com stack with white numbers on black drums.
func _panel_radio(rect: Rect2) -> void:
	draw_rect(rect, Color(0.035, 0.035, 0.038))
	var x := rect.position.x
	var y := rect.position.y
	var rows := [["COM", "122.80"], ["NAV", "114.30"], ["ADF", "344"], ["XPDR", "1200"]]
	var h := rect.size.y / float(rows.size())
	for i in range(rows.size()):
		var ry := y + h * float(i)
		draw_rect(Rect2(x + 4.0, ry + 4.0, rect.size.x - 8.0, h - 8.0), Color(0.11, 0.11, 0.115))
		draw_rect(Rect2(x + 52.0, ry + 16.0, 110.0, 26.0), Color(0.01, 0.01, 0.01))
		_text(Vector2(x + 28.0, ry + 29.0), rows[i][0], 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, 44.0)
		_text(Vector2(x + 107.0, ry + 29.0), rows[i][1], 18, Color(0.92, 0.92, 0.88), HORIZONTAL_ALIGNMENT_CENTER, 110.0)
		for k in range(2):
			var kc := Vector2(x + 70.0 + 80.0 * float(k), ry + h - 15.0)
			draw_circle(kc, 8.0, Color(0.06, 0.06, 0.06))
			draw_circle(kc, 6.0, Color(0.16, 0.16, 0.17))
		draw_circle(Vector2(x + 190.0, ry + 29.0), 9.0, Color(0.16, 0.16, 0.17))


# ------------------------------------------------------------------------------
#  Dial faces for the 3D instruments (drawn once, without needles)
# ------------------------------------------------------------------------------
func _draw_face() -> void:
	var r := Layout.GAUGE_R
	var c := Vector2(r + 9.0, r + 9.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(face_scale, face_scale))
	match face_id:
		"airspeed":
			_g_airspeed(c, r)
		"altimeter":
			_g_altimeter(c, r)
		"vsi":
			_g_vsi(c, r)
		"tach":
			_g_tach(c, r)
		"heading":
			_g_heading_card(c, r)
		"attitude":
			_g_attitude_ring(c, r)
		"clock":
			_g_clock(c, r)
		_:
			if not face_spec.is_empty():
				_g_dial(c, r, face_spec)
			elif Layout.DIALS.has(face_id):
				_g_dial(c, r, Layout.DIALS[face_id])


func _zone_col(k: String) -> Color:
	return GREEN if k == "g" else (RED if k == "r" else Color(0.95, 0.85, 0.15))


## A small engine dial from a spec in panel_layout.gd.
func _g_dial(c: Vector2, r: float, spec: Dictionary) -> void:
	draw_circle(c, r + 8.0, Color(0.02, 0.02, 0.02))
	draw_circle(c, r, FACE)
	var lo: float = spec["lo"]
	var hi: float = spec["hi"]
	var a0: float = spec["a0"]
	var a1: float = spec["a1"]
	var ang := func(v: float) -> float: return lerpf(a0, a1, clampf((v - lo) / (hi - lo), 0.0, 1.0))
	for z in spec["zones"]:
		_arc(c, r - 8.0, ang.call(float(z[0])), ang.call(float(z[1])), _zone_col(z[2]), 7.0)
	_ticks(c, r - 4.0, a0, a1, int(spec["minor"]), 7.0, 2.0)
	for lb in spec["labels"]:
		var d := _dir(ang.call(float(lb[0])))
		draw_line(c + d * (r - 18.0), c + d * (r - 3.0), MARK, 3.5, true)
		_text(c + d * (r - 32.0), lb[1], 17, MARK, HORIZONTAL_ALIGNMENT_CENTER, 60.0)
	_text(c + Vector2(0, r * 0.52), spec["title"], 15, DIM, HORIZONTAL_ALIGNMENT_CENTER, 120.0)


func _g_heading_card(c: Vector2, r: float) -> void:
	draw_circle(c, r + 8.0, Color(0.02, 0.02, 0.02))
	draw_circle(c, r, FACE)
	var names := {0: "N", 90: "E", 180: "S", 270: "W"}
	for deg in range(0, 360, 5):
		var d := _dir(float(deg))
		var long := deg % 30 == 0
		var mid := deg % 10 == 0
		draw_line(c + d * (r - (11.0 if long else (7.0 if mid else 4.0))), c + d * (r - 1.0), MARK, 1.6, true)
		if long:
			var label: String = names[deg] if names.has(deg) else str(deg / 10)
			_text(c + d * (r - 22.0), label, 15 if names.has(deg) else 13, AMBER if deg == 0 else MARK, HORIZONTAL_ALIGNMENT_CENTER, 30.0)


## Ring around the attitude ball: a dark frame with the bank marks; clear inside.
func _g_attitude_ring(c: Vector2, r: float) -> void:
	var inner := r * 0.84
	for k in range(4):
		draw_arc(c, inner + (r + 8.0 - inner) * (float(k) + 0.5) / 4.0, 0.0, TAU, 64, Color(0.05, 0.05, 0.055), (r + 8.0 - inner) / 4.0 + 1.0, true)
	for bank in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var d := _dir(float(bank))
		var long := absi(bank) % 30 == 0
		var col := AMBER if bank == 0 else MARK
		draw_line(c + d * (r - (10.0 if long else 6.0)), c + d * (r + 1.0), col, 2.5 if long else 1.8, true)


func _g_clock(c: Vector2, r: float) -> void:
	draw_circle(c, r + 8.0, Color(0.02, 0.02, 0.02))
	draw_circle(c, r, FACE)
	_ticks(c, r - 3.0, 0.0, 354.0, 59, 4.0, 1.2)
	for hr in range(1, 13):
		var d := _dir(float(hr) * 30.0)
		draw_line(c + d * (r - 12.0), c + d * (r - 2.0), MARK, 3.0, true)
		_text(c + d * (r - 24.0), str(hr), 15, MARK, HORIZONTAL_ALIGNMENT_CENTER, 30.0)


func _draw_tooltip() -> void:
	var w := 16.0 + float(tooltip.length()) * 8.2
	var p := tooltip_pos + Vector2(22, 18)
	p.x = minf(p.x, size.x - w - 8.0)
	draw_rect(Rect2(p, Vector2(w, 26)), Color(0.02, 0.02, 0.02, 0.85))
	draw_rect(Rect2(p, Vector2(w, 26)), AMBER, false, 1.0)
	_text(p + Vector2(8, 13), tooltip, 14, MARK, HORIZONTAL_ALIGNMENT_LEFT, w)


# ------------------------------------------------------------------------------
#  Navigation help
# ------------------------------------------------------------------------------
func _bearing_to(k: int) -> float:
	if k < 0 or k >= terrain.strips.size():
		return 0.0
	var p: Vector3 = terrain.strips[k]["pos"]
	return fposmod(rad_to_deg(atan2(p.x - plane.pos.x, -(p.z - plane.pos.z))), 360.0)


func _distance_nm(k: int) -> float:
	var p: Vector3 = terrain.strips[k]["pos"]
	return Vector2(p.x - plane.pos.x, p.z - plane.pos.z).length() / 1852.0


func _draw_info(sz: Vector2) -> void:
	var x := 22.0
	var y := 26.0
	var lines: Array = []
	if target_strip >= 0 and target_strip < terrain.strips.size():
		var s: Dictionary = terrain.strips[target_strip]
		var p: Vector3 = s["pos"]
		lines.append(["To %s   %.1f nm   bearing %03d°" % [s["name"], _distance_nm(target_strip), int(round(_bearing_to(target_strip))) % 360], MARK])
		var hdg: float = s["heading"]
		lines.append(["Runway %02d/%02d   %d m %s   elevation %d ft" % [
			_runway_number(hdg), _runway_number(hdg + 180.0), int(s["length"]),
			Terrain.SURFACE_NAMES[int(s["surface"])], int(p.y * 3.28084)], DIM])
	else:
		lines.append(["No destination selected. Press N to pick an airstrip.", DIM])
	if not Game.is_realistic() and wind != null:
		var rep: Vector2 = wind.report()
		if rep.y < 0.5:
			lines.append(["Wind calm", DIM])
		else:
			lines.append(["Wind from %03d° at %d kt" % [int(rep.x), int(round(rep.y))], DIM])
	if plane.on_ground:
		lines.append(["On %s" % Terrain.SURFACE_NAMES[plane.surface_now], DIM])
	if jobs != null:
		var jl: String = jobs.status_line()
		if jl != "":
			lines.append(["JOB  " + jl, Color(0.75, 0.85, 0.95)])
		if jobs.strip_here() >= 0:
			lines.append(["%s  Job board" % Game.hint("jobs"), DIM])
	if plane.has_skis():
		lines.append(["SKIS %s   %s skis" % ["DOWN" if plane.gear_down else "UP (on wheels)", Game.hint("gear")], Color(0.75, 0.85, 0.95)])
	if plane.is_retractable():
		var gp2: float = plane.gear_pos
		var gt2 := "GEAR DOWN" if gp2 > 0.99 else ("GEAR UP" if gp2 < 0.01 else "GEAR IN TRANSIT")
		lines.append(["%s   %s gear" % [gt2, Game.hint("gear")], Color(0.55, 0.85, 0.55) if gp2 > 0.99 else (Color(0.75, 0.75, 0.75) if gp2 < 0.01 else AMBER)])
		# The warning horn: throttles back low down with the gear not down.
		if not plane.on_ground and gp2 < 0.99 and plane.throttle < 0.25 and plane.agl < 300.0:
			if int(Time.get_ticks_msec() / 400) % 2 == 0:
				lines.append(["GEAR!  GEAR!  The wheels aren't down.", RED])
	if plane.is_amphib():
		var gp: float = plane.gear_pos
		var gtxt := "WHEELS DOWN (land)" if gp > 0.99 else ("WHEELS UP (water)" if gp < 0.01 else "WHEELS MOVING")
		lines.append(["%s   %s wheels" % [gtxt, Game.hint("gear")], Color(0.55, 0.85, 0.55) if gp > 0.99 else (Color(0.55, 0.75, 0.95) if gp < 0.01 else AMBER)])
		if not plane.on_ground and plane.agl < 150.0 and plane.vel.y < -0.5:
			var gpos: Vector3 = plane.global_position
			var over_water: bool = terrain.water_level_at(gpos.x, gpos.z) > -1.0e8 and not terrain.lakes_frozen()
			if over_water and plane.gear_down:
				lines.append(["CHECK WHEELS: they're DOWN and you're over water!", RED])
			elif not over_water and not plane.gear_down and terrain.strip_index_at(gpos.x, gpos.z, 600.0) >= 0:
				lines.append(["Check wheels: UP for a runway landing?", AMBER])
	if skydive != null and skydive.ready_text() != "-" and not plane.on_ground:
		var rt: String = skydive.ready_text()
		lines.append(["GREEN LIGHT: press %s to drop the jumpers" % Game.hint("jobs") if rt == "" else rt, Color(0.55, 0.95, 0.55) if rt == "" else AMBER])
	if plane.door_open.get("cowl", false) and walker == null:
		lines.append(["COWLING OPEN", AMBER])
	if plane.door_open.get("bay", false) or (plane.door_open.get("cabin", false) and walker == null):
		lines.append(["%s DOOR OPEN" % ("BAGGAGE" if plane.door_open.get("bay", false) else "CABIN"), AMBER])
	var eh: String = plane.engine_hint()
	if eh != "":
		lines.append([eh, AMBER])
	var dmg: Array = plane.damage_report()
	if not dmg.is_empty():
		lines.append(["DAMAGE", RED])
		for i in range(mini(dmg.size(), 7)):
			var h: float = dmg[i][1]
			lines.append(["  " + String(dmg[i][0]), RED if h < 0.4 else AMBER])
	for ln in lines:
		_shadow_text(Vector2(x, y), ln[0], 17, ln[1])
		y += 24.0
	var right := "%s   %s   %d°C" % [Game.SEASON_NAMES[Game.season], Game.REALISM_NAMES[Game.realism], int(round(plane.oat_c))]
	_shadow_text(Vector2(sz.x - 22.0, 26.0), right, 15, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 500.0)
	_shadow_text(Vector2(sz.x - 22.0, 48.0), "%s help    %s chart    %s menu" % [Game.hint("help"), Game.hint("map"), Game.hint("menu")], 13, Color(DIM, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, 500.0)


static func _runway_number(heading: float) -> int:
	var n := int(round(fposmod(heading, 360.0) / 10.0))
	if n == 0:
		n = 36
	return n


func _draw_target_marker(sz: Vector2) -> void:
	if target_strip < 0 or camera == null or terrain == null or target_strip >= terrain.strips.size():
		return
	var p: Vector3 = terrain.strips[target_strip]["pos"]
	p.y += 25.0
	var strip_name: String = terrain.strips[target_strip]["name"]
	var label := "%s  %.1f nm" % [strip_name, _distance_nm(target_strip)]
	var margin := 60.0
	var bottom := sz.y - 200.0
	if not camera.is_position_behind(p):
		var sp := camera.unproject_position(p)
		if sp.x > margin and sp.x < sz.x - margin and sp.y > margin and sp.y < bottom:
			var d := 9.0
			draw_polyline(PackedVector2Array([sp + Vector2(0, -d), sp + Vector2(d, 0), sp + Vector2(0, d), sp + Vector2(-d, 0), sp + Vector2(0, -d)]), AMBER, 2.0, true)
			_shadow_text(sp + Vector2(0, -22.0), label, 14, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 400.0)
			return
	# Off screen: an arrow at the edge pointing the way to turn.
	var rel := wrapf(_bearing_to(target_strip) - plane.heading_deg(), -180.0, 180.0)
	var left := rel < 0.0
	var ax := margin if left else sz.x - margin
	var ay := sz.y * 0.38
	var dir := -1.0 if left else 1.0
	draw_colored_polygon(PackedVector2Array([Vector2(ax + dir * 16.0, ay), Vector2(ax - dir * 8.0, ay - 12.0), Vector2(ax - dir * 8.0, ay + 12.0)]), AMBER)
	_shadow_text(Vector2(ax - dir * 20.0, ay + 28.0) if left else Vector2(ax + 20.0, ay + 28.0), label, 14, AMBER,
		HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT, 400.0)


## The pistol's aim mark: a small dot from the hip; aiming, a ring with
## four ticks closes in on it.
func _draw_crosshair(sz: Vector2) -> void:
	var c := sz * 0.5
	var ink := Color(0.97, 0.94, 0.86, 0.85)
	var shade := Color(0.0, 0.0, 0.0, 0.45)
	draw_circle(c, 3.0, shade)
	draw_circle(c, 2.0, ink)
	if aim <= 0.01:
		return
	var a := clampf(aim, 0.0, 1.0)
	var gap := lerpf(40.0, 7.0, a)
	var col := Color(ink, ink.a * a)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * gap, c + d * (gap + 11.0), Color(shade, shade.a * a), 4.0)
		draw_line(c + d * gap, c + d * (gap + 11.0), col, 2.0)
	draw_arc(c, gap + 16.0, 0.0, TAU, 40, Color(0.92, 0.45, 0.12, 0.7 * a), 1.5)


var _goals_x := Rect2()


## The getting-started list's close box. (On foot the mouse is captured:
## hold Alt to free it, or turn the list off in Options.)
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not goals.is_empty() and _goals_x.size.x > 0.0 and _goals_x.has_point((event as InputEventMouseButton).position):
		Game.goals_on = false
		Game.notify_changed()
		goals = []
		_goals_x = Rect2()
		push_message("Getting-started list off (Options to bring it back).", 4.0)
		get_viewport().set_input_as_handled()


func _draw_goals(sz: Vector2) -> void:
	if goals.is_empty() or show_map or inset_on or not foot_keys:
		_goals_x = Rect2()
	if goals.is_empty() or show_map or inset_on or not foot_keys:      # the hide-keys button hides it too
		return
	var w := 400.0
	var o := Vector2(20.0, sz.y * 0.30)
	var h := 34.0 + 22.0 * float(goals.size())
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.04, 0.06, 0.05, 0.72))
	draw_rect(Rect2(o, Vector2(4.0, h)), Color(0.92, 0.45, 0.12, 0.95))
	_text(o + Vector2(14.0, 8.0), "GETTING STARTED", 13, Color(0.92, 0.45, 0.12), HORIZONTAL_ALIGNMENT_LEFT, w)
	# the close box (also: Options > Getting-started list)
	_goals_x = Rect2(o + Vector2(w - 30.0, 4.0), Vector2(24.0, 22.0))
	var hot := _goals_x.has_point(get_viewport().get_mouse_position()) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	draw_rect(_goals_x, Color(0.92, 0.45, 0.12, 0.9 if hot else 0.35))
	var xc := _goals_x.get_center()
	var xcol := Color(0.04, 0.06, 0.05) if hot else Color(0.94, 0.90, 0.80)
	draw_line(xc + Vector2(-6, -6), xc + Vector2(6, 6), xcol, 2.0)
	draw_line(xc + Vector2(-6, 6), xc + Vector2(6, -6), xcol, 2.0)
	var y := o.y + 30.0
	for g in goals:
		var done: bool = g[1]
		var col := Color(0.55, 0.62, 0.52) if done else Color(0.94, 0.90, 0.80)
		_text(Vector2(o.x + 14.0, y), ("[x] " if done else "[  ] ") + String(g[0]), 13, col, HORIZONTAL_ALIGNMENT_LEFT, w - 20.0)
		y += 22.0


func _draw_messages(sz: Vector2) -> void:
	_draw_goals(sz)
	var y := 96.0
	if tutorial_text != "":
		# The tutorial's current step: a wide banner that stays until it's done.
		var tw := minf(sz.x - 80.0, 980.0)
		var lines := ceilf(_font.get_string_size(tutorial_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x / (tw - 40.0))
		var th := 16.0 + 24.0 * maxf(lines, 1.0)
		var tp := Vector2(sz.x * 0.5 - tw * 0.5, 54.0)
		draw_rect(Rect2(tp, Vector2(tw, th)), Color(0.10, 0.06, 0.02, 0.82))
		draw_rect(Rect2(tp, Vector2(tw, th)), AMBER, false, 1.5)
		draw_multiline_string(_font, tp + Vector2(20.0, 28.0), tutorial_text, HORIZONTAL_ALIGNMENT_LEFT, tw - 40.0, 18, -1, Color(0.97, 0.93, 0.84))
		y = tp.y + th + 30.0
	for m in _messages:
		var alpha := clampf(m[1] / 0.6, 0.0, 1.0)
		var text: String = m[0]
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 36.0
		draw_rect(Rect2(sz.x * 0.5 - w * 0.5, y - 17.0, w, 34.0), Color(0.04, 0.06, 0.05, 0.80 * alpha))
		draw_rect(Rect2(sz.x * 0.5 - w * 0.5, y - 17.0, 4.0, 34.0), Color(0.92, 0.45, 0.12, alpha))
		_text(Vector2(sz.x * 0.5, y), text, 20, Color(MARK, alpha), HORIZONTAL_ALIGNMENT_CENTER, w)
		y += 40.0


## Health and warmth bars, and what you can do here.
func _draw_on_foot(sz: Vector2) -> void:
	# where you are (handy for testing and for bug reports)
	var wp: Vector3 = walker.global_position
	var hd := int(round(fposmod(-rad_to_deg(float(walker.look.x)), 360.0))) % 360
	var below: float = terrain.natural_at(wp.x, wp.z) - wp.y
	_shadow_text(Vector2(22.0, 26.0), "x %d  z %d   facing %03d°%s" % [int(round(wp.x)), int(round(wp.z)), hd, ("   %.0f m down" % below) if below > 1.5 else ""], 14, Color(0.85, 0.85, 0.8, 0.8))
	var x := 28.0
	var y := sz.y - 92.0
	var bars := [["Health", float(walker.health), Color(0.72, 0.30, 0.26)], ["Warmth", float(walker.warmth), Color(0.85, 0.62, 0.30)]]
	for b in bars:
		var v: float = b[1]
		_shadow_text(Vector2(x, y - 2.0), b[0], 15, Color(0.9, 0.88, 0.82))
		draw_rect(Rect2(x + 74.0, y - 13.0, 180.0, 12.0), Color(0, 0, 0, 0.45))
		var col: Color = b[2]
		if v < 0.3 and int(_blink * 2.0) % 2 == 0:
			col = col.lightened(0.35)
		draw_rect(Rect2(x + 74.0, y - 13.0, 180.0 * clampf(v, 0.0, 1.0), 12.0), col)
		y += 26.0
	var py := sz.y * 0.62
	if cargo != null and String(cargo.prompt) != "":
		_shadow_text(Vector2(sz.x * 0.5 - 300.0, py), cargo.prompt, 18, Color(0.95, 0.92, 0.82), HORIZONTAL_ALIGNMENT_CENTER, 600.0)
		py += 28.0
	if walker.call("near_door"):
		_shadow_text(Vector2(sz.x * 0.5 - 150.0, py), "%s   Get in" % Game.hint("get_out"), 18, Color(0.95, 0.92, 0.82), HORIZONTAL_ALIGNMENT_CENTER, 300.0)
	if walker.first_person:
		draw_circle(sz * 0.5, 2.2, Color(1, 1, 1, 0.55))
	if foot_keys and not in_machine:
		_draw_foot_keys(sz)


## A small key legend for walking about (hidden with the help key).
func _draw_foot_keys(sz: Vector2) -> void:
	var pad: bool = Game.using_gamepad
	var rows := [
		["Left stick" if pad else _keys(["pitch_up", "roll_left", "pitch_down", "roll_right"]), "Walk"],
		["Left stick click" if pad else _keys(["throttle_up"]), "Run (toggle)" if pad else "Run (hold)"],
		["A" if pad else _keys(["brake"]), "Jump"],
		["Right stick" if pad else "Mouse", "Look around"],
		["RT / X" if pad else _keys(["interact"]), "Use what's in your hand / pick up / board"],
		["LT" if pad else "Right mouse", "Aim the pistol"],
		[_keys(["door"]), "Open / close a door"],
		[Game.hint("get_out").trim_prefix("Hold "), "Get in the plane (at its door)"],
		["D-pad down" if pad else _keys(["build"]), "Build: strips, cabins, hangars, camps"],
		["LB / RB" if pad else "1-8 / wheel", "Hotbar: what's in your hand"],
		["View" if pad else _keys(["inventory"]), "Backpack"],
		["D-pad left" if pad else _keys(["map"]), "Chart"],
		["D-pad up" if pad else _keys(["lights"]), "Headlamp"],
		[_keys(["camera"]), "First / third person"],
		[Game.hint("menu"), "Menu (help, jobs, settings)"],
		["Right stick click" if pad else Game.hint("help"), "Hide these keys"],
	]
	var w := 380.0
	var h := 14.0 + 21.0 * float(rows.size())
	var o := Vector2(sz.x - w - 20.0, sz.y - h - 20.0)
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.04, 0.06, 0.05, 0.72))
	draw_rect(Rect2(o, Vector2(w, 3.0)), Color(0.92, 0.45, 0.12, 0.9))
	var y := o.y + 18.0
	for row in rows:
		_text(Vector2(o.x + 12.0, y), String(row[0]), 13, MARK, HORIZONTAL_ALIGNMENT_LEFT, 130.0)
		_text(Vector2(o.x + 146.0, y), String(row[1]), 13, DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 156.0)
		y += 21.0


func _keys(actions: Array) -> String:
	var parts: Array[String] = []
	for a in actions:
		parts.append(Game.hint(a))
	return " / ".join(parts)


func _draw_help(sz: Vector2) -> void:
	var pad := Game.using_gamepad
	var rows := [
		[_keys(["pitch_down", "pitch_up"]), "Nose down / nose up"],
		[_keys(["roll_left", "roll_right"]), "Roll left / right"],
		[_keys(["yaw_left", "yaw_right"]), "Rudder left / right (steers on the ground)"],
		[_keys(["throttle_up", "throttle_down"]), "Throttle up / down"],
		[_keys(["flaps_down", "flaps_up"]), "Flaps down / up one notch"],
		[_keys(["brake"]), "Brakes (add rudder to brake harder on that side)"],
		[_keys(["brake_left", "brake_right"]), "Left / right toe brake"],
		[_keys(["trim_up", "trim_down"]), "Trim nose up / nose down"],
		["LB" if pad else _keys(["engine_auto"]), "Quick menu: auto start, switches, lights, map, jobs" if pad else "Automatic engine start / shut-down"],
		["LB" if pad else _keys(["master", "mags", "starter", "primer"]), "(in the quick menu)" if pad else "Master, magnetos, starter, primer (by hand)"],
		[Game.hint("get_out"), "Get out (on the ground, stopped)"],
		[_keys(["camera"]), "Switch between chase and cockpit view"],
		["Hold RB + right stick" if pad else "Right mouse drag, wheel", "Look around" if pad else "Look around, zoom"],
		[_keys(["next_target"]), "Next destination"],
		[_keys(["map"]), "Chart"],
		[_keys(["reset"]), "Start again from the last airstrip"],
		[_keys(["menu"]), "Menu: airstrips, loading, season, controls"],
	]
	var w := 640.0
	var h := 62.0 + 25.0 * float(rows.size()) + 96.0
	var o := Vector2(sz.x * 0.5 - w * 0.5, 100.0)
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.04, 0.04, 0.045, 0.84))
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.5, 0.5, 0.5, 0.5), false, 1.0)
	_text(o + Vector2(w * 0.5, 26.0), "CONTROLLER" if pad else "CONTROLS", 20, AMBER, HORIZONTAL_ALIGNMENT_CENTER, w)
	var y := o.y + 62.0
	for row in rows:
		_text(Vector2(o.x + 24.0, y), row[0], 15, MARK, HORIZONTAL_ALIGNMENT_LEFT, 260.0)
		_text(Vector2(o.x + 290.0, y), row[1], 15, DIM, HORIZONTAL_ALIGNMENT_LEFT, 340.0)
		y += 25.0
	y += 8.0
	_text(Vector2(o.x + 24.0, y), "To take off: full throttle (%s), keep straight with the rudder," % Game.hint("throttle_up"), 14, MARK, HORIZONTAL_ALIGNMENT_LEFT, w)
	_text(Vector2(o.x + 24.0, y + 20.0), "and ease the nose up (%s) at about 55 knots. Every control can be changed in the menu." % Game.hint("pitch_up"), 14, MARK, HORIZONTAL_ALIGNMENT_LEFT, w)
	_text(Vector2(o.x + w * 0.5, y + 54.0), "Press %s to hide or show this" % Game.hint("help"), 14, AMBER, HORIZONTAL_ALIGNMENT_CENTER, w)


# ------------------------------------------------------------------------------
#  Chart
# ------------------------------------------------------------------------------
func refresh_map() -> void:
	_map_tex = null


func _draw_map(sz: Vector2) -> void:
	if _map_tex == null or _map_season != Game.season:
		_map_tex = ImageTexture.create_from_image(terrain.make_map_image())
		_map_season = Game.season
	var side := minf(sz.x, sz.y) - 80.0
	var o := Vector2(sz.x * 0.5 - side * 0.5, 40.0)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.04, 0.78))
	draw_rect(Rect2(o - Vector2(8, 8), Vector2(side + 16.0, side + 16.0)), Color(0.86, 0.82, 0.70))
	draw_texture_rect(_map_tex, Rect2(o, Vector2(side, side)), false)
	var scale_px: float = side / terrain.size
	var to_map := func(wx: float, wz: float) -> Vector2:
		return o + Vector2((wx + terrain.half) * scale_px, (wz + terrain.half) * scale_px)
	var ink := Color(0.16, 0.12, 0.10)
	# Airstrips
	for k in range(terrain.strips.size()):
		var s: Dictionary = terrain.strips[k]
		var p: Vector3 = s["pos"]
		var d: Vector2 = s["dir"]
		var mp: Vector2 = to_map.call(p.x, p.z)
		var half_len: float = maxf(float(s["length"]) * 0.5 * scale_px, 7.0)
		var col := RED if k == target_strip else ink
		draw_line(mp - d * half_len, mp + d * half_len, col, 3.0, true)
		draw_arc(mp, half_len + 5.0, 0.0, TAU, 24, col, 1.5, true)
		# Put the label on the left when another strip sits close by on the right.
		var crowded := false
		for j in range(terrain.strips.size()):
			if j == k:
				continue
			var op: Vector3 = terrain.strips[j]["pos"]
			var omp: Vector2 = to_map.call(op.x, op.z)
			if omp.x > mp.x and omp.x - mp.x < 190.0 and absf(omp.y - mp.y) < 26.0:
				crowded = true
		var details := "%d ft   %d m" % [int(p.y * 3.28084), int(s["length"])]
		if crowded:
			_text(mp + Vector2(-half_len - 12.0, -7.0), s["name"], 14, col, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
			_text(mp + Vector2(-half_len - 12.0, 9.0), details, 11, col, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
		else:
			_text(mp + Vector2(half_len + 12.0, -7.0), s["name"], 14, col, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
			_text(mp + Vector2(half_len + 12.0, 9.0), details, 11, col, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
	for lake in terrain.lakes:
		var c: Vector2 = lake["pos"]
		var lake_at: Vector2 = to_map.call(c.x, c.y + float(lake["radius"]) + 260.0)
		_text(lake_at, lake["name"], 11, Color(0.15, 0.25, 0.45), HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	# Line to the destination, and the aeroplane
	var pp: Vector2 = to_map.call(plane.pos.x, plane.pos.z)
	if target_strip >= 0:
		var tp: Vector3 = terrain.strips[target_strip]["pos"]
		draw_dashed_line(pp, to_map.call(tp.x, tp.z), RED, 1.5, 8.0)
	var hd := _dir(plane.heading_deg())
	var hs := Vector2(-hd.y, hd.x)
	draw_colored_polygon(PackedVector2Array([pp + hd * 13.0, pp - hd * 9.0 + hs * 8.0, pp - hd * 4.0, pp - hd * 9.0 - hs * 8.0]), Color(0.75, 0.08, 0.05))
	# North arrow, scale bar and wind
	var na := o + Vector2(side - 34.0, 46.0)
	draw_line(na + Vector2(0, 18), na + Vector2(0, -18), ink, 2.0, true)
	draw_colored_polygon(PackedVector2Array([na + Vector2(0, -24), na + Vector2(-6, -12), na + Vector2(6, -12)]), ink)
	_text(na + Vector2(0, 30.0), "N", 14, ink, HORIZONTAL_ALIGNMENT_CENTER, 30.0)
	var bar := 1852.0 * 2.0 * scale_px
	var bo := o + Vector2(24.0, side - 26.0)
	draw_line(bo, bo + Vector2(bar, 0), ink, 3.0)
	_text(bo + Vector2(bar * 0.5, -12.0), "2 nautical miles", 11, ink, HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	if wind != null:
		var rep: Vector2 = wind.report()
		var wtxt := "Wind calm" if rep.y < 0.5 else "Wind from %03d° at %d kt" % [int(rep.x), int(round(rep.y))]
		_text(o + Vector2(24.0, 22.0), wtxt, 13, ink, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
	_text(Vector2(sz.x * 0.5, o.y + side + 22.0), "%s to close the chart     %s to change destination" % [Game.hint("map"), Game.hint("next_target")], 14, MARK, HORIZONTAL_ALIGNMENT_CENTER, 600.0)
	_draw_local_inset(sz, o, side)


## Around you (DESIGN_NOTES 165): the chart is the whole country, so the home
## base's tool yard, bench and machines are one dot on it. A close-up beside
## it, 500 m across, north up, centred on you, with each place named.
var places: Callable              # main: -> [[name, Vector3, Color], ...]
func _draw_local_inset(sz: Vector2, chart_o: Vector2, chart_side: float) -> void:
	if not places.is_valid():
		return
	var me: Vector3 = walker.global_position if walker != null and walker.visible else plane.pos
	var w := 330.0
	var room_r := sz.x - (chart_o.x + chart_side + 16.0) - 24.0
	var room_l := chart_o.x - 24.0 - 16.0
	var ox: float
	if room_r >= w:
		ox = chart_o.x + chart_side + 32.0
	elif room_l >= w:
		ox = chart_o.x - 24.0 - w
	else:
		ox = sz.x - w - 24.0
	var o2 := Vector2(ox, chart_o.y)
	var span := 260.0
	var k := w / span
	draw_rect(Rect2(o2 - Vector2(6, 6), Vector2(w + 12.0, w + 40.0)), Color(0.04, 0.06, 0.05, 0.92))
	draw_rect(Rect2(o2 - Vector2(6, 6), Vector2(w + 12.0, 4.0)), Color(0.92, 0.45, 0.12))
	draw_rect(Rect2(o2, Vector2(w, w)), Color(0.86, 0.82, 0.70))
	var ink := Color(0.16, 0.12, 0.10)
	var at := func(p: Vector3) -> Vector2:
		return o2 + Vector2(w, w) * 0.5 + Vector2(p.x - me.x, p.z - me.z) * k
	# 100 m grid
	for g in range(-1, 2):
		var off := float(g) * 100.0 * k
		draw_line(o2 + Vector2(w * 0.5 + off, 0), o2 + Vector2(w * 0.5 + off, w), Color(0.6, 0.56, 0.46, 0.5), 1.0)
		draw_line(o2 + Vector2(0, w * 0.5 + off), o2 + Vector2(w, w * 0.5 + off), Color(0.6, 0.56, 0.46, 0.5), 1.0)
	for pl in places.call():
		var mp: Vector2 = at.call(pl[1] as Vector3)
		if mp.x < o2.x + 4.0 or mp.y < o2.y + 4.0 or mp.x > o2.x + w - 4.0 or mp.y > o2.y + w - 4.0:
			continue
		var col: Color = pl[2]
		draw_circle(mp, 5.0, col)
		draw_arc(mp, 5.5, 0.0, TAU, 12, ink, 1.0)
		_text(mp + Vector2(8.0, -7.0), String(pl[0]), 11, ink, HORIZONTAL_ALIGNMENT_LEFT, 160.0)
	# you
	var c := o2 + Vector2(w, w) * 0.5
	var hd := -float(walker.look.x) if walker != null and walker.visible else deg_to_rad(plane.heading_deg())
	var f := Vector2(-sin(hd), -cos(hd)) if walker != null and walker.visible else _dir(plane.heading_deg())
	var sd := Vector2(-f.y, f.x)
	draw_colored_polygon(PackedVector2Array([c + f * 10.0, c - f * 6.0 + sd * 6.0, c - f * 3.0, c - f * 6.0 - sd * 6.0]), Color(0.75, 0.08, 0.05))
	_text(o2 + Vector2(0, w + 8.0), "AROUND YOU  -  250 m across, north up", 12, Color(0.94, 0.9, 0.8), HORIZONTAL_ALIGNMENT_LEFT, w)
