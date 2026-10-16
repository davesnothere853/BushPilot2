extends Node

## Smoking is switched off for now (Dave kept lighting up by accident, P).
const SMOKING := false
## Global settings, saved options and the input map (with player rebinding).
## Registered as the "Game" autoload in project.godot.

signal settings_changed
signal bindings_changed

const SEASON_NAMES: Array[String] = ["Summer", "Fall", "Winter", "Spring"]
const REALISM_NAMES: Array[String] = ["Sim-lite", "Realistic"]
const WIND_NAMES: Array[String] = ["Calm", "Light", "Moderate", "Strong"]
const WIND_SPEEDS: Array[float] = [0.0, 3.5, 7.5, 12.5]   # metres per second

const SUMMER := 0
const FALL := 1
const WINTER := 2
const SPRING := 3

const SAVE_PATH := "user://settings.cfg"

# --- options the player can change -------------------------------------------
var realism: int = 0            # 0 = Sim-lite, 1 = Realistic
var season: int = SUMMER
var time_of_day: float = 13.0   # hours, 0-24
var wind_level: int = 1
var wind_dir_deg: float = 250.0 # direction the wind blows FROM
var engine_failures: int = 0      # twins: 0 off, 1 rare, 2 often
var cold_look := true             # Alaska grade on; console "look classic" turns it off to compare
var map: String = "north"          # which test map: "north" (the northern bush) or "outback" (Australia)
var world_seed: int = 1987         # the square's layout (map_gen.gd): knoll, creek, pond, gold
var free_repairs := false
var sandbox := false               # money never runs out, no bills, planes sold at any strip          # sandbox: no bills for fuel, recovery and repairs
var weather: int = 0              # 0 clear, 1 overcast, 2 rain or snow, 3 fog
const WEATHER_NAMES: Array[String] = ["Clear", "Overcast", "Rain (snow in winter)", "Fog"]
var invert_pitch: bool = false
var volume: float = 0.7
var last_strip: int = 0
var pending_join := ""              # rejoin this host after reloading into its world (net.gd)
var load_slot_pending := 0          # a save slot to bring back before main loads anything (DESIGN_NOTES 169)
var new_game_pending := false     # "New game" was chosen: main wipes the saves before it loads anything
var stick_sensitivity: float = 1.0   # 0.5 = gentle, 1.5 = sharp
var stick_deadzone: float = 0.12
var look_speed: float = 1.0
## Phone controls (DESIGN_NOTES 128): 0 automatic (on a touch screen), 1 on, 2 off.
var touch_mode: int = 0
var tilt_fly: bool = false             # bank and pitch by tilting the phone
var tilt_gain: float = 1.0
var engine_auto: bool = true         # the game manages mixture, prop, carb heat and starting
var cockpit_overlay: bool = false    # also draw the flat gauge strip in the cockpit view
var tyre_kind: String = "850"        # fitted tyres (until the hangar exists)
var leg_kind: String = "spring"
var auto_trim: bool = false          # sim-lite only: re-trim while the stick is held
var graphics_quality: int = 2        # 0 low, 1 medium, 2 high
var tree_distance: int = 1           # 0 near, 1 normal, 2 far, 3 very far
var chase_gauges := true
var rumble := true                  # controller rumble: engine, rough air, stall buffet, the ground            # the gauge row in the outside (third-person) view
var rumble_strength := 1.0          # 0..2 everything the controller does
var rumble_engine := 1.0            # 0..2 the engine's firing pulses in it
var weather_changes := true         # fronts come and go on their own (DESIGN_NOTES 168)
var goals_on := true                # the getting-started list
var machine_hints := true           # the control tips each machine shows when you get on
var gore := true                    # blood and lost limbs in fatal accidents (DESIGN_NOTES 157)
var stall_horn := true              # a quiet stall-warning beep (Season, weather and realism page)
var trees_3d := false                # false: every tree a flat picture card facing you (fast)
const TREE_DISTANCE_NAMES := ["Near", "Normal", "Far", "Very far"]
var seat_height: float = 0.0         # cockpit eye height adjustment, metres
var seat_fore: float = 0.0           # cockpit eye forward (+) / back (-), metres
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra", "Custom"]
# --- detailed graphics (a preset above sets all of these; changing one makes it Custom)
var resolution: int = 0              # index into RESOLUTIONS (0 = the screen's own)
const RESOLUTIONS := [Vector2i(0, 0), Vector2i(3840, 2160), Vector2i(3440, 1440), Vector2i(2560, 1440), Vector2i(2560, 1080),
	Vector2i(1920, 1200), Vector2i(1920, 1080), Vector2i(1680, 1050), Vector2i(1600, 900), Vector2i(1366, 768), Vector2i(1280, 720)]
var window_mode: int = 1             # 0 windowed, 1 maximized, 2 borderless fullscreen, 3 exclusive fullscreen
const WINDOW_MODE_NAMES := ["Windowed", "Maximized window", "Borderless fullscreen", "Exclusive fullscreen"]
var vsync: int = 1                   # 0 off, 1 on, 2 adaptive
const VSYNC_NAMES := ["Off", "On", "Adaptive"]
var fps_limit: int = 0               # index into FPS_LIMITS
const FPS_LIMITS := [0, 30, 60, 90, 120, 144, 165, 240]
var render_scale: float = 1.0        # 3D resolution, 0.5..1.0 of the window
var upscaler: int = 1                # 0 bilinear, 1 FSR 1, 2 FSR 2
var upscale_sharp: float = 0.8       # 0..1 how much the upscaler sharpens (FSR 1 and 2)
const UPSCALER_NAMES := ["Bilinear", "FSR 1", "FSR 2"]
var gfx_aa: int = 3                  # 0 off, 1 FXAA, 2 MSAA 2x, 3 MSAA 4x, 4 MSAA 8x, 5 TAA, 6 MSAA 4x + TAA
const AA_NAMES := ["Off", "FXAA", "MSAA 2x", "MSAA 4x", "MSAA 8x", "TAA", "MSAA 4x + TAA"]
var gfx_shadows: int = 3             # 0 off, 1 low, 2 medium, 3 high, 4 ultra
const SHADOW_NAMES := ["Off", "Low", "Medium", "High", "Ultra"]
var gfx_ao: bool = true              # screen-space ambient occlusion
var gfx_ssil: bool = true            # screen-space indirect light
var gfx_ssr: bool = false            # screen-space reflections (water, metal)
var gfx_glow: bool = true
var gfx_plants: int = 2              # bushes and ground plants: 0 near .. 3 very far
var gfx_water: int = 1               # 0 flat, 1 waves near the camera
var fov_offset: float = 0.0          # added to every camera's field of view, degrees
var cam_shake: float = 1.0           # camera shake strength (0 off .. 2)


## Set every detailed graphics option from a preset (0 low .. 3 ultra).
func apply_preset(q: int) -> void:
	if q > 3:
		return
	graphics_quality = q
	gfx_aa = [1, 2, 3, 6][q]
	gfx_shadows = [1, 2, 3, 4][q]
	gfx_ao = q >= 1
	gfx_ssil = q >= 2
	gfx_ssr = q >= 3
	gfx_glow = q >= 1
	gfx_plants = q
	gfx_water = 0 if q == 0 else 1
	render_scale = [0.75, 0.9, 1.0, 1.0][q]
	tree_distance = [0, 1, 2, 3][q]
var controller_pref: String = ""     # "" = automatic, "*" = any controller, otherwise a controller's name

# --- runtime -------------------------------------------------------------------
var using_gamepad: bool = false

# ------------------------------------------------------------------------------
#  Rebindable actions. Each has two keyboard slots and one controller slot.
#  A binding is stored as a small dictionary:
#    {"t": "key", "code": physical keycode}
#    {"t": "btn", "i": joypad button index}
#    {"t": "axis", "a": joypad axis, "v": +1 or -1}
# ------------------------------------------------------------------------------
const ACTIONS: Array = [
	# [action, label, analog]
	["pitch_up", "Nose up (pull)", true],
	["pitch_down", "Nose down (push)", true],
	["roll_left", "Roll left", true],
	["roll_right", "Roll right", true],
	["yaw_left", "Rudder left", true],
	["yaw_right", "Rudder right", true],
	["throttle_up", "Throttle up", true],
	["throttle_down", "Throttle down", true],
	["brake", "Both brakes", true],
	["brake_left", "Left toe brake", true],
	["brake_right", "Right toe brake", true],
	["flaps_down", "Flaps down a notch", false],
	["flaps_up", "Flaps up a notch", false],
	["trim_up", "Trim nose up", false],
	["trim_down", "Trim nose down", false],
	["look_left", "Look left", true],
	["look_right", "Look right", true],
	["look_up", "Look up", true],
	["look_down", "Look down", true],
	["engine_auto", "Automatic engine start / shut-down", false],
	["master", "Battery master switch", false],
	["alternator", "Alternator switch", false],
	["mags", "Magnetos (OFF, R, L, BOTH)", false],
	["starter", "Starter (hold)", false],
	["primer", "Primer (one stroke)", false],
	["fuel_selector", "Fuel selector (OFF, LEFT, RIGHT, BOTH)", false],
	["mixture_rich", "Mixture richer", true],
	["mixture_lean", "Mixture leaner", true],
	["prop_up", "Prop rpm up", true],
	["prop_down", "Prop rpm down", true],
	["carb_heat", "Carburettor heat", false],
	["cowl_flaps", "Cowl flaps", false],
	["camera", "Chase / cockpit view", false],
	["next_target", "Next destination", false],
	["map", "Chart", false],
	["four_wd", "4WD: 2H / 4H / 4L (trucks)", false],
	["diff_lock", "Diff lock / lockers (trucks)", false],
	["help", "Controls reminder", false],
	["reset", "Back to last airstrip", false],
	["menu", "Menu", false],
	["fullscreen", "Full screen", false],
	["seat_up", "Seat up (cockpit)", false],
	["seat_down", "Seat down (cockpit)", false],
	["seat_fwd", "Seat forward (cockpit)", false],
	["seat_back", "Seat back (cockpit)", false],
	["gear", "Wheels up / down (amphibious floats)", false],
	["get_out", "Get out of / into the plane", false],
	["jobs", "Job board", false],
	["free_look", "Free look (hold; the right stick looks instead of steering)", false],
	["interact", "Pick up / put down / load (on foot)", false],
	["door", "Open / close the door you're standing at (on foot)", false],
	["build", "Build: lay out a strip, put up a cabin, hangar or camp (on foot)", false],
	["feather", "Twin engines: feather the dead engine's propeller", false],
	["smoke", "Light a cigarette (on foot or in the plane)", false],
	["lights", "Outside lights all on / off (or the panel switches)", false],
	["controls", "Co-op: ask for / hand over the controls", false],
	["inventory", "Backpack / inventory (on foot)", false],
]

const NO_DEVICE := 99            # a joypad id nothing has: gamepad bindings switched off
const HotasScript = preload("res://scripts/hotas.gd")
var hotas: Node                  # flight sticks, throttles, pedals (hotas.gd)
var using_hotas := false

var _defaults: Dictionary = {}
var bindings: Dictionary = {}   # action -> [key1, key2, pad], each a Dictionary or {}


func _init() -> void:
	_defaults = _default_bindings()
	hotas = HotasScript.new()
	hotas.name = "Hotas"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hotas)
	bindings = _defaults.duplicate(true)
	load_settings()
	hotas.changed.connect(func():
		apply_bindings()
		save_settings())
	apply_bindings()
	Input.joy_connection_changed.connect(func(_id, _connected): apply_bindings())


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		# Flight gear: its buttons are sent on as actions; its axes are read directly.
		if hotas.gear_ids().has(event.device):
			if event is InputEventJoypadButton:
				hotas.handle_button(event as InputEventJoypadButton)
				if (event as InputEventJoypadButton).pressed:
					using_hotas = true
					using_gamepad = false
			elif absf((event as InputEventJoypadMotion).axis_value) > 0.5:
				using_hotas = true
				using_gamepad = false
			return
		var dev := active_device()
		if dev != -1 and event.device != dev:
			return
		if event is InputEventJoypadMotion:
			if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
				using_gamepad = true
				using_hotas = false
		elif (event as InputEventJoypadButton).pressed:
			using_gamepad = true
			using_hotas = false
	elif event is InputEventKey:
		using_gamepad = false


# ------------------------------------------------------------------------------
#  Which controller to listen to. Joysticks, throttles and wheels left plugged in
#  can otherwise look like a gamepad with its triggers held down.
# ------------------------------------------------------------------------------
static func _looks_like_gamepad(name: String) -> bool:
	var n := name.to_lower()
	for word in ["xbox", "xinput", "gamepad", "game pad", "controller", "dualshock", "dualsense", "wireless", "8bitdo", "switch pro"]:
		if n.contains(word):
			return true
	return false


func connected_controllers() -> Array:
	var out: Array = []
	for id in Input.get_connected_joypads():
		out.append([id, Input.get_joy_name(id)])
	return out


## Device id the bindings listen to, or -1 for every controller.
func active_device() -> int:
	if controller_pref == "*" and hotas.gear_ids().is_empty():
		return -1
	var gear: Array = hotas.gear_ids()
	var pads: Array = []
	for p in connected_controllers():
		if not gear.has(p[0]):
			pads.append(p)
	if pads.is_empty():
		return NO_DEVICE if not gear.is_empty() else -1
	if controller_pref != "":
		for p in pads:
			if p[1] == controller_pref:
				return p[0]
	for p in pads:
		if _looks_like_gamepad(p[1]):
			return p[0]
	return pads[0][0]


func active_device_name() -> String:
	var dev := active_device()
	if dev == -1:
		return "any controller"
	if dev == NO_DEVICE:
		return "none (flight gear only)"
	return Input.get_joy_name(dev)


func is_realistic() -> bool:
	return realism == 1


func notify_changed() -> void:
	save_settings()
	settings_changed.emit()


# --- sea level air temperature for the season, in kelvin ------------------------
func sea_level_temp_k() -> float:
	match season:
		SUMMER:
			return 291.0
		FALL:
			return 277.0
		WINTER:
			return 251.0
		_:
			return 276.0


# ------------------------------------------------------------------------------
#  Saving
# ------------------------------------------------------------------------------
func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("state", "pad_layout", 2)
	cf.set_value("options", "realism", realism)
	cf.set_value("options", "season", season)
	cf.set_value("options", "time_of_day", time_of_day)
	cf.set_value("options", "wind_level", wind_level)
	cf.set_value("options", "wind_dir_deg", wind_dir_deg)
	cf.set_value("options", "weather", weather)
	cf.set_value("options", "free_repairs", free_repairs)
	cf.set_value("options", "sandbox", sandbox)
	cf.set_value("options", "world_seed", world_seed)
	cf.set_value("options", "map", map)
	cf.set_value("options", "engine_failures", engine_failures)
	cf.set_value("options", "invert_pitch", invert_pitch)
	cf.set_value("options", "volume", volume)
	cf.set_value("options", "stick_sensitivity", stick_sensitivity)
	cf.set_value("options", "stick_deadzone", stick_deadzone)
	cf.set_value("options", "look_speed", look_speed)
	cf.set_value("options", "touch_mode", touch_mode)
	cf.set_value("options", "tilt_fly", tilt_fly)
	cf.set_value("options", "tilt_gain", tilt_gain)
	cf.set_value("options", "engine_auto", engine_auto)
	cf.set_value("options", "cockpit_overlay", cockpit_overlay)
	cf.set_value("plane", "tyre_kind", tyre_kind)
	cf.set_value("plane", "leg_kind", leg_kind)
	cf.set_value("options", "auto_trim", auto_trim)
	cf.set_value("options", "graphics_quality", graphics_quality)
	for k in ["resolution", "window_mode", "vsync", "fps_limit", "render_scale", "upscaler", "gfx_aa", "gfx_shadows", "gfx_ao", "gfx_ssil",
			"gfx_ssr", "gfx_glow", "gfx_plants", "gfx_water", "fov_offset", "cam_shake", "upscale_sharp"]:
		cf.set_value("graphics", k, get(k))
	cf.set_value("options", "tree_distance", tree_distance)
	cf.set_value("options", "trees_3d", trees_3d)
	cf.set_value("options", "stall_horn", stall_horn)
	cf.set_value("options", "gore", gore)
	cf.set_value("options", "machine_hints", machine_hints)
	cf.set_value("options", "goals_on", goals_on)
	cf.set_value("options", "weather_changes", weather_changes)
	cf.set_value("options", "rumble_strength", rumble_strength)
	cf.set_value("options", "rumble_engine", rumble_engine)
	cf.set_value("options", "chase_gauges", chase_gauges)
	cf.set_value("options", "rumble", rumble)
	cf.set_value("options", "seat_height", seat_height)
	cf.set_value("options", "seat_fore", seat_fore)
	cf.set_value("options", "controller_pref", controller_pref)
	cf.set_value("state", "last_strip", last_strip)
	for a in bindings.keys():
		cf.set_value("bindings", a, bindings[a])
	hotas.save_to(cf)
	cf.save(SAVE_PATH)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		# first run on a phone or tablet: start on the Low preset, fewer trees
		if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
			graphics_quality = 0
			apply_preset(0)
		return
	realism = clampi(int(cf.get_value("options", "realism", realism)), 0, 1)
	season = clampi(int(cf.get_value("options", "season", season)), 0, 3)
	time_of_day = clampf(float(cf.get_value("options", "time_of_day", time_of_day)), 0.0, 24.0)
	wind_level = clampi(int(cf.get_value("options", "wind_level", wind_level)), 0, 3)
	wind_dir_deg = float(cf.get_value("options", "wind_dir_deg", wind_dir_deg))
	weather = clampi(int(cf.get_value("options", "weather", weather)), 0, 3)
	world_seed = int(cf.get_value("options", "world_seed", world_seed))
	map = String(cf.get_value("options", "map", map))
	if not map in ["north", "outback"]:
		map = "north"
	free_repairs = bool(cf.get_value("options", "free_repairs", free_repairs))
	sandbox = bool(cf.get_value("options", "sandbox", sandbox))
	engine_failures = clampi(int(cf.get_value("options", "engine_failures", engine_failures)), 0, 2)
	invert_pitch = bool(cf.get_value("options", "invert_pitch", invert_pitch))
	volume = clampf(float(cf.get_value("options", "volume", volume)), 0.0, 1.0)
	stick_sensitivity = clampf(float(cf.get_value("options", "stick_sensitivity", stick_sensitivity)), 0.4, 1.6)
	stick_deadzone = clampf(float(cf.get_value("options", "stick_deadzone", stick_deadzone)), 0.02, 0.4)
	look_speed = clampf(float(cf.get_value("options", "look_speed", look_speed)), 0.3, 2.0)
	touch_mode = clampi(int(cf.get_value("options", "touch_mode", touch_mode)), 0, 2)
	tilt_fly = bool(cf.get_value("options", "tilt_fly", tilt_fly))
	tilt_gain = clampf(float(cf.get_value("options", "tilt_gain", tilt_gain)), 0.4, 2.5)
	engine_auto = bool(cf.get_value("options", "engine_auto", engine_auto))
	cockpit_overlay = bool(cf.get_value("options", "cockpit_overlay", cockpit_overlay))
	tyre_kind = String(cf.get_value("plane", "tyre_kind", tyre_kind))
	leg_kind = String(cf.get_value("plane", "leg_kind", leg_kind))
	auto_trim = bool(cf.get_value("options", "auto_trim", auto_trim))
	graphics_quality = clampi(int(cf.get_value("options", "graphics_quality", graphics_quality)), 0, 4)
	if cf.has_section("graphics"):
		for k in cf.get_section_keys("graphics"):
			if k in self:
				set(k, cf.get_value("graphics", k))
	else:
		apply_preset(mini(graphics_quality, 3))
	tree_distance = clampi(int(cf.get_value("options", "tree_distance", tree_distance)), 0, 3)
	trees_3d = bool(cf.get_value("options", "trees_3d", trees_3d))
	stall_horn = bool(cf.get_value("options", "stall_horn", stall_horn))
	gore = bool(cf.get_value("options", "gore", gore))
	machine_hints = bool(cf.get_value("options", "machine_hints", machine_hints))
	goals_on = bool(cf.get_value("options", "goals_on", goals_on))
	weather_changes = bool(cf.get_value("options", "weather_changes", weather_changes))
	rumble_strength = float(cf.get_value("options", "rumble_strength", rumble_strength))
	rumble_engine = float(cf.get_value("options", "rumble_engine", rumble_engine))
	chase_gauges = bool(cf.get_value("options", "chase_gauges", chase_gauges))
	rumble = bool(cf.get_value("options", "rumble", rumble))
	seat_height = clampf(float(cf.get_value("options", "seat_height", seat_height)), -0.12, 0.15)
	seat_fore = clampf(float(cf.get_value("options", "seat_fore", seat_fore)), -0.06, 0.25)   # far back put the eye behind the head
	controller_pref = String(cf.get_value("options", "controller_pref", controller_pref))
	last_strip = int(cf.get_value("state", "last_strip", last_strip))
	hotas.load_from(cf)
	if cf.has_section("bindings"):
		for a in cf.get_section_keys("bindings"):
			if not bindings.has(a):
				continue
			var v = cf.get_value("bindings", a)
			if v is Array and v.size() == 3:
				var slots: Array = []
				for slot in v:
					slots.append(slot if slot is Dictionary else {})
				bindings[a] = slots
	# F10 opens the menu too (Escape can be taken by other apps on the desktop,
	# e.g. an assistant app watching for it). Older saves get it added once.
	# (F10 is the garage, so the menu's second key is F12)
	var mb: Array = bindings.get("menu", [])
	if mb.size() == 3 and ((mb[1] as Dictionary).is_empty() or (mb[1] as Dictionary) == _k(KEY_F10)):
		mb[1] = _k(KEY_F12)
	# Controller layout 2: rudder on the right stick, RB held for free look,
	# nothing on the right-stick click. Older saves get these slots updated once.
	if int(cf.get_value("state", "pad_layout", 1)) < 2:
		for a in ["yaw_left", "yaw_right", "reset", "free_look", "look_left", "look_right", "look_up", "look_down"]:
			if bindings.has(a) and _defaults.has(a):
				var slots2: Array = (bindings[a] as Array).duplicate()
				slots2[2] = (_defaults[a] as Array)[2]
				bindings[a] = slots2

# ------------------------------------------------------------------------------
#  Bindings
# ------------------------------------------------------------------------------
static func _k(code: Key) -> Dictionary:
	return {"t": "key", "code": int(code)}


static func _b(i: JoyButton) -> Dictionary:
	return {"t": "btn", "i": int(i)}


static func _ax(a: JoyAxis, v: float) -> Dictionary:
	return {"t": "axis", "a": int(a), "v": v}


func _default_bindings() -> Dictionary:
	var none := {}
	return {
		"pitch_up": [_k(KEY_S), _k(KEY_DOWN), _ax(JOY_AXIS_LEFT_Y, 1.0)],
		"pitch_down": [_k(KEY_W), _k(KEY_UP), _ax(JOY_AXIS_LEFT_Y, -1.0)],
		"roll_left": [_k(KEY_A), _k(KEY_LEFT), _ax(JOY_AXIS_LEFT_X, -1.0)],
		"roll_right": [_k(KEY_D), _k(KEY_RIGHT), _ax(JOY_AXIS_LEFT_X, 1.0)],
		"yaw_left": [_k(KEY_Q), none, _ax(JOY_AXIS_RIGHT_X, -1.0)],
		"yaw_right": [_k(KEY_E), none, _ax(JOY_AXIS_RIGHT_X, 1.0)],
		"throttle_up": [_k(KEY_SHIFT), _k(KEY_EQUAL), _ax(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"throttle_down": [_k(KEY_CTRL), _k(KEY_MINUS), _ax(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"brake": [_k(KEY_SPACE), none, _b(JOY_BUTTON_A)],
		"brake_left": [_k(KEY_Z), none, none],
		"brake_right": [_k(KEY_X), none, none],
		"flaps_down": [_k(KEY_F), none, _b(JOY_BUTTON_X)],
		"flaps_up": [_k(KEY_R), none, _b(JOY_BUTTON_Y)],
		"trim_up": [_k(KEY_T), none, _b(JOY_BUTTON_DPAD_DOWN)],
		"trim_down": [_k(KEY_G), none, _b(JOY_BUTTON_DPAD_UP)],
		"look_left": [_k(KEY_KP_4), none, _ax(JOY_AXIS_RIGHT_X, -1.0)],
		"look_right": [_k(KEY_KP_6), none, _ax(JOY_AXIS_RIGHT_X, 1.0)],
		"look_up": [_k(KEY_KP_8), none, _ax(JOY_AXIS_RIGHT_Y, -1.0)],
		"look_down": [_k(KEY_KP_2), none, _ax(JOY_AXIS_RIGHT_Y, 1.0)],
		"engine_auto": [_k(KEY_I), none, none],
		"master": [_k(KEY_1), none, none],
		"alternator": [_k(KEY_2), none, none],
		"mags": [_k(KEY_3), none, none],
		"starter": [_k(KEY_4), none, none],
		"primer": [_k(KEY_5), none, none],
		"fuel_selector": [_k(KEY_6), none, none],
		"mixture_rich": [_k(KEY_BRACKETRIGHT), none, none],
		"mixture_lean": [_k(KEY_BRACKETLEFT), none, none],
		"prop_up": [_k(KEY_PERIOD), none, none],
		"prop_down": [_k(KEY_COMMA), none, none],
		"carb_heat": [_k(KEY_7), none, none],
		"cowl_flaps": [_k(KEY_8), none, none],
		"camera": [_k(KEY_C), none, _b(JOY_BUTTON_B)],
		"next_target": [_k(KEY_N), none, _b(JOY_BUTTON_DPAD_LEFT)],
		"map": [_k(KEY_M), none, _b(JOY_BUTTON_BACK)],
		"four_wd": [_k(KEY_G), none, _b(JOY_BUTTON_DPAD_UP)],
		"diff_lock": [_k(KEY_9), none, _b(JOY_BUTTON_RIGHT_STICK)],
		"help": [_k(KEY_H), none, _b(JOY_BUTTON_DPAD_RIGHT)],
		"reset": [_k(KEY_BACKSPACE), none, none],
		"menu": [_k(KEY_ESCAPE), _k(KEY_F12), _b(JOY_BUTTON_START)],
		"fullscreen": [_k(KEY_F11), none, none],
		"seat_up": [_k(KEY_PAGEUP), none, none],
		"seat_down": [_k(KEY_PAGEDOWN), none, none],
		"seat_fwd": [_k(KEY_HOME), none, none],
		"seat_back": [_k(KEY_END), none, none],
		"gear": [_k(KEY_L), none, none],
		"get_out": [_k(KEY_O), none, _b(JOY_BUTTON_LEFT_STICK)],
		"jobs": [_k(KEY_J), none, none],
		"free_look": [none, none, _b(JOY_BUTTON_RIGHT_SHOULDER)],
		"interact": [_k(KEY_E), none, _b(JOY_BUTTON_X)],
		"door": [_k(KEY_Y), none, _b(JOY_BUTTON_Y)],
		"controls": [_k(KEY_K), none, none],
		"build": [_k(KEY_B), none, none],
		"feather": [_k(KEY_U), none, none],
		"smoke": [_k(KEY_P), none, none],
		"lights": [_k(KEY_V), none, none],
		"inventory": [_k(KEY_TAB), none, _b(JOY_BUTTON_LEFT_SHOULDER)],
	}


func reset_bindings() -> void:
	bindings = _defaults.duplicate(true)
	apply_bindings()
	save_settings()


## Put `binding` into one slot of an action. The same key or button is taken off
## any other action first, so one press never does two things.
## Returns the label of the action it was taken from, or "".
func set_binding(action: String, slot: int, binding: Dictionary) -> String:
	var taken_from := ""
	if not binding.is_empty():
		for a in bindings.keys():
			var slots: Array = bindings[a]
			for s in range(3):
				if (a != action or s != slot) and _same(slots[s], binding):
					slots[s] = {}
					taken_from = action_label(a)
	bindings[action][slot] = binding
	apply_bindings()
	save_settings()
	return taken_from


static func _same(x: Dictionary, y: Dictionary) -> bool:
	if x.is_empty() or y.is_empty() or x.get("t") != y.get("t"):
		return false
	match String(x["t"]):
		"key":
			return int(x["code"]) == int(y["code"])
		"btn":
			return int(x["i"]) == int(y["i"])
		"axis":
			return int(x["a"]) == int(y["a"]) and signf(float(x["v"])) == signf(float(y["v"]))
	return false


func action_label(action: String) -> String:
	for row in ACTIONS:
		if row[0] == action:
			return row[1]
	return action


func apply_bindings() -> void:
	for row in ACTIONS:
		var action: String = row[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action, stick_deadzone)
		InputMap.action_set_deadzone(action, stick_deadzone if row[2] else 0.5)
		InputMap.action_erase_events(action)
		var dev := active_device()
		for b in bindings[action]:
			var ev := binding_to_event(b)
			if ev != null:
				if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
					ev.device = dev
				InputMap.action_add_event(action, ev)
	# "Confirm" is not rebindable: Enter on the keyboard, A on a controller.
	if not InputMap.has_action("confirm"):
		InputMap.add_action("confirm", 0.5)
		var k := InputEventKey.new()
		k.physical_keycode = KEY_ENTER
		InputMap.action_add_event("confirm", k)
		var j := InputEventJoypadButton.new()
		j.button_index = JOY_BUTTON_A
		InputMap.action_add_event("confirm", j)
	bindings_changed.emit()


static func binding_to_event(b: Dictionary) -> InputEvent:
	if b.is_empty():
		return null
	match String(b.get("t", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(b["code"]) as Key
			return k
		"btn":
			var j := InputEventJoypadButton.new()
			j.button_index = int(b["i"]) as JoyButton
			return j
		"axis":
			var m := InputEventJoypadMotion.new()
			m.axis = int(b["a"]) as JoyAxis
			m.axis_value = signf(float(b["v"]))
			return m
	return null


## Turn something the player just pressed into a binding, or {} if it is not usable.
static func event_to_binding(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if not k.pressed or k.echo:
			return {}
		var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return {"t": "key", "code": code}
	if ev is InputEventJoypadButton:
		var j := ev as InputEventJoypadButton
		if not j.pressed:
			return {}
		return {"t": "btn", "i": int(j.button_index)}
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		if absf(m.axis_value) < 0.6:
			return {}
		return {"t": "axis", "a": int(m.axis), "v": signf(m.axis_value)}
	return {}


const BUTTON_NAMES := {
	0: "A", 1: "B", 2: "X", 3: "Y", 4: "View / Back", 5: "Guide", 6: "Menu / Start",
	7: "Left stick click", 8: "Right stick click", 9: "LB", 10: "RB",
	11: "D-pad up", 12: "D-pad down", 13: "D-pad left", 14: "D-pad right",
	15: "Share", 16: "Paddle 1", 17: "Paddle 2", 18: "Paddle 3", 19: "Paddle 4", 20: "Touchpad",
}


static func binding_name(b: Dictionary) -> String:
	if b.is_empty():
		return "-"
	match String(b.get("t", "")):
		"key":
			var s := OS.get_keycode_string(int(b["code"]) as Key)
			return s if s != "" else "Key %d" % int(b["code"])
		"btn":
			return BUTTON_NAMES.get(int(b["i"]), "Button %d" % int(b["i"]))
		"axis":
			var a := int(b["a"])
			var pos := float(b["v"]) > 0.0
			match a:
				JOY_AXIS_LEFT_X:
					return "Left stick right" if pos else "Left stick left"
				JOY_AXIS_LEFT_Y:
					return "Left stick down" if pos else "Left stick up"
				JOY_AXIS_RIGHT_X:
					return "Right stick right" if pos else "Right stick left"
				JOY_AXIS_RIGHT_Y:
					return "Right stick down" if pos else "Right stick up"
				JOY_AXIS_TRIGGER_LEFT:
					return "LT"
				JOY_AXIS_TRIGGER_RIGHT:
					return "RT"
			return "Axis %d %s" % [a, "+" if pos else "-"]
	return "?"


## Short text for an action's first binding on the device in use, for on-screen hints.
func hint(action: String) -> String:
	if not bindings.has(action):
		return "?"
	var slots: Array = bindings[action]
	if using_hotas and hotas.buttons.has(action):
		return hotas.button_name(action)
	if using_gamepad and not (slots[2] as Dictionary).is_empty():
		if action == "get_out":
			return "Hold " + binding_name(slots[2])      # getting out on a pad is a hold (no accidents)
		return binding_name(slots[2])
	for s in [0, 1]:
		if not (slots[s] as Dictionary).is_empty():
			return binding_name(slots[s])
	return binding_name(slots[2])


## Hint for a machine's implement lever (forks, arms, blade, boom): the right
## stick on a pad (the triggers are the pedals there), else the throttle keys.
func lever_hint(up: bool) -> String:
	if using_gamepad and not using_hotas:
		return "Right stick back" if up else "Right stick forward"
	return hint("throttle_up" if up else "throttle_down")


## The Outback map is on (DESIGN_NOTES 108). A "map=outback" / "map=north"
## command-line argument overrides the saved choice (for tests).
func outback() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="):
			return a.substr(4) == "outback"
	return map == "outback"
