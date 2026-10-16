extends Node
## MODEL LAB (DESIGN_NOTES 189): look at one model without starting the game,
## and see code changes live.
##
## - Type a name in the box (top left) and press Enter: "cockpit", "gauges", or
##   any res:// script path whose node builds itself (Node3D or Control).
## - Whenever that script (or another script it lists in WATCH) changes on disk,
##   the model is rebuilt on the spot, and a screenshot is saved to
##   res://_rec/lab_latest.png (plus a numbered copy).
## - Claude can drive it without the keyboard: write a name (and optional camera
##   "yaw pitch dist") into res://_rec/lab_cmd.txt; "shot" takes a picture.
## - 3D models: drag with the left mouse to turn round them, wheel to zoom,
##   F12 for a screenshot.

const ALIASES := {
	"cockpit": "res://scripts/menu_cockpit.gd",
	"menu": "res://scripts/menu_cockpit.gd",
	"gauges": "res://scripts/real_gauges.gd",
	"hope_town": "res://scripts/town_block.gd", "town": "res://scripts/small_town.gd", "home_strip": "res://scripts/home_strip.gd", "region": "res://scripts/region.gd", "lookout_tower": "res://scripts/assets/lookout_tower.gd", "trees": "res://scripts/assets/trees.gd", "commercial_block": "res://scripts/assets/commercial_block.gd", "house_victorian": "res://scripts/assets/house_victorian.gd", "pole_barn": "res://scripts/assets/pole_barn.gd", "crash_test": "res://tools/crash_test.gd", "radio_mast": "res://scripts/assets/radio_mast.gd", "microwave_relay": "res://scripts/assets/microwave_relay.gd", "passive_reflector": "res://scripts/assets/passive_reflector.gd", "headframe": "res://scripts/assets/headframe.gd", "lighthouse": "res://scripts/assets/lighthouse.gd", "civic": "res://scripts/assets/civic.gd", "rocks": "res://scripts/assets/rock_kit.gd", "bridge": "res://scripts/assets/bridge.gd", "town_props": "res://scripts/assets/town_props.gd", "shops": "res://tools/_t_shops.gd", "strip": "res://scripts/home_strip.gd", "small_town": "res://scripts/small_town.gd", "lineup": "res://tools/lineup.gd",
}
const WATCH := ["res://scripts/meshkit.gd", "res://scripts/equip_kit.gd", "res://scripts/hyd_ram.gd", "res://scripts/hyd_hose.gd", "res://scripts/hyd_system.gd", "res://scripts/track_loop.gd", "res://scripts/air_seat.gd", "res://scripts/machine_engine.gd", "res://scripts/town_block.gd", "res://scripts/home_strip.gd", "res://scripts/region.gd", "res://scripts/region_town.gd", "res://scripts/assets/civic.gd", "res://scripts/assets/town_props.gd", "res://scripts/assets/rock_kit.gd", "res://shaders/rock_moss.gdshader", "res://scripts/assets/bridge.gd", "res://scripts/assets/commercial_block.gd", "res://scripts/assets/house_victorian.gd", "res://scripts/structure.gd", "res://scripts/assets/pole_barn.gd", "res://scripts/flora.gd", "res://scripts/veg_meshes.gd", "res://scripts/vegetation.gd", "res://scripts/assets/trees.gd", "res://scripts/eztree.gd", "res://scripts/region_terrain.gd", "res://scripts/region_geology.gd", "res://scripts/region_landmarks.gd", "res://shaders/region_ground.gdshader", "res://scripts/tex.gd", "res://scripts/materials.gd", "res://scripts/assets/kits.gd", "res://scripts/assets/asset_lib.gd", "res://scripts/assets/glow.gd", "res://scripts/assets/lookout_cab.gd", "res://scripts/region_landmarks.gd", "res://shaders/region_ground.gdshader", "res://scripts/tex.gd", "res://scripts/materials.gd", "res://scripts/assets/kits.gd", "res://scripts/assets/asset_lib.gd", "res://scripts/assets/glow.gd", "res://scripts/assets/lookout_cab.gd", "res://scripts/wind_litter.gd", "res://scripts/tune.gd", "res://tools/tune.cfg", "res://scripts/tyre_mesh.gd",
	"res://shaders/truck_paint.gdshader", "res://shaders/tyre_squash.gdshader", "res://shaders/wet_glass.gdshader",
	"res://scripts/rope.gd", "res://scripts/winch.gd", "res://scripts/hull.gd", "res://scripts/wheeled_body.gd",
	"res://scripts/parts.gd", "res://scripts/engine_sim.gd", "res://scripts/gauge_wiring.gd", "res://scripts/vehicle_breakage.gd",
	"res://scripts/menu_cockpit.gd", "res://scripts/real_gauges.gd", "res://scripts/hud.gd",
	"res://scripts/truck_dash.gd", "res://scripts/truck_body.gd", "res://scripts/engine_sound.gd", "res://scripts/water_truck_model.gd", "res://scripts/hose_line.gd"]
## Saving one of these can't be swapped in place (the lab / test bed itself, the
## driver): the lab restarts itself on the same model in a second - no editor needed.
const RESTART := ["res://tools/model_lab.gd", "res://tools/vehicle_testbed.gd", "res://scripts/on_foot.gd", "res://scripts/pilot_rig.gd"]
## Machines: name -> [script, variant]. Built on flat ground, parked, orbit round them.
const VEHICLES := {
	"pickup": ["res://scripts/pickup_truck.gd", ""], "truck": ["res://scripts/pickup_truck.gd", ""],
	"blazer": ["res://scripts/pickup_truck.gd", "blazer"], "suburban": ["res://scripts/pickup_truck.gd", "suburban"],
	"water_truck": ["res://scripts/water_truck.gd", ""], "fuel_truck": ["res://scripts/water_truck.gd", "fuel"],
	"loader": ["res://scripts/loader.gd", ""], "dozer": ["res://scripts/dozer.gd", ""],
	"excavator": ["res://scripts/excavator.gd", ""], "tug": ["res://scripts/tug.gd", ""],
	"forklift": ["res://scripts/forklift.gd", ""], "log_trailer": ["res://scripts/log_trailer.gd", ""],
	"wolverine": ["res://scripts/plane_body.gd", ""], "plane": ["res://scripts/plane_body.gd", ""],
}

## The lab's ground: flat round the model, and a test course ahead of it
## (-z): a single bump, whoops, and offset mounds that twist the axles.
class FlatGround extends RefCounted:
	const MOUNDS := [
		# x, z, radius, height
		[0.0, -14.0, 1.2, 0.18],
		[-0.9, -22.0, 1.6, 0.40], [0.9, -25.5, 1.6, 0.40], [-0.9, -29.0, 1.6, 0.40], [0.9, -32.5, 1.6, 0.40],
	]
	func height_at(x: float, z: float) -> float:
		var h := 0.0
		for m in MOUNDS:
			var d := Vector2(x - float(m[0]), z - float(m[1])).length() / float(m[2])
			if d < 1.0:
				h += float(m[3]) * (0.5 + 0.5 * cos(d * PI))
		# whoops: rolling humps across the course, z -40 .. -52
		if z < -40.0 and z > -52.0 and absf(x) < 4.0:
			h += 0.10 * (0.5 - 0.5 * cos((z + 40.0) * TAU / 2.4))
		return h
	func ground_level_at(x: float, z: float) -> float: return height_at(x, z)
	func strip_index_at(_x: float, _z: float, _m: float = 0.0) -> int: return 0
	func blocked_by_building(_p: Vector3, _r: float = 0.0, _skip = null) -> bool: return false
	func normal_at(_x: float, _z: float) -> Vector3: return Vector3.UP
	func ground_normal_at(_x: float, _z: float) -> Vector3: return Vector3.UP
	func mud_at(_x: float, _z: float) -> float: return 0.0
	var lakes: Array = []

const CMD := "res://_rec/lab_cmd.txt"

class FakeBtn:
	extends RefCounted
	var text := ""
	var said: Callable
	func _init(t: String, cb: Callable = Callable()) -> void:
		text = t
		said = cb
	func press() -> void:
		if said.is_valid():
			said.call("worked: " + text)

var _box: LineEdit
var _status: Label
var _perf: Label                 # fps and frame budget (DESIGN_NOTES 231): 60 fps ultra at 4K on Dave's RX 7800 XT
var _perf_t := 0.0
var _perf_worst := 0.0
var _holder: Node
var _canvas: CanvasLayer
var _world: Node3D
var _cam: Camera3D
var _yaw := 0.6
var _pitch := -0.25
var _dist := 4.0
var _target := Vector3.ZERO
var _current := ""
var _stamps := {}
var _poll := 0.0
var _shot_in := -1.0
var _shot_n := 0
var _cmd_stamp := 0
var _drag := false
var _versioned := {}
var _fixed_cam := false
var _sheet: Array = []            # [SubViewport, Camera3D, name] - the four-view sheet
var _ref: TextureRect             # the reference photo, see-through over the model
var _driver := true               # sit the character in a vehicle's seat
var _driver_node: Node3D
var _rstamps := {}
var _bed: Node                    # the vehicle test bed (tools/vehicle_testbed.gd)
var _ui: CanvasLayer


func _ready() -> void:
	# capped at 120 (Dave), so it never runs unlimited: keeps the PC (and Dave's
	# generator) from running flat out (DESIGN_NOTES 228)
	Engine.max_fps = 120
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_rec"))
	_world = Node3D.new()
	add_child(_world)
	# a neutral studio for 3D models: soft key and fill, grey backdrop
	var we := WorldEnvironment.new()
	var env := Environment.new()
	# an outdoor sky, so chrome and glass have something to reflect (as in the game)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.50, 0.78)
	sm.sky_horizon_color = Color(0.72, 0.76, 0.80)
	sm.ground_bottom_color = Color(0.22, 0.20, 0.17)
	sm.ground_horizon_color = Color(0.55, 0.52, 0.46)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.ssao_intensity = 2.2
	env.ssil_enabled = true                  # light bouncing off the ground into the wheel wells
	env.ssr_enabled = true                   # the paint and chrome reflect the truck and ground
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.tonemap_exposure = 1.0
	we.environment = env
	_world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.7
	key.light_color = Color(1.0, 0.95, 0.87)
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	key.light_angular_distance = 0.6
	_world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.4
	_world.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_world.add_child(_cam)
	_holder = Node3D.new()
	_world.add_child(_holder)
	_canvas = CanvasLayer.new()
	_canvas.layer = 1
	add_child(_canvas)
	var ui := CanvasLayer.new()
	_ui = ui
	ui.layer = 50
	add_child(ui)
	_box = LineEdit.new()
	_box.placeholder_text = "model: cockpit, gauges, pickup, water_truck, fuel_truck, loader, dozer, excavator, tug, forklift   (Enter)"
	_box.position = Vector2(12, 10)
	_box.size = Vector2(520, 34)
	_box.text_submitted.connect(func(t): show_model(t.strip_edges()))
	ui.add_child(_box)
	_status = Label.new()
	_status.position = Vector2(14, 48)
	_status.add_theme_color_override("font_shadow_color", Color.BLACK)
	_status.add_theme_constant_override("shadow_offset_y", 1)
	ui.add_child(_status)
	_perf = Label.new()
	_perf.position = Vector2(14, 76)          # under the status line (the top right is under Claude's window)
	_perf.size = Vector2(520, 90)
	_perf.add_theme_font_size_override("font_size", 18)
	_perf.add_theme_color_override("font_shadow_color", Color.BLACK)
	_perf.add_theme_constant_override("shadow_offset_y", 1)
	ui.add_child(_perf)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_make_sheet()
	_write_launcher()
	_bed = load("res://tools/vehicle_testbed.gd").new()
	_bed.lab = self
	add_child(_bed)
	_ref = TextureRect.new()
	_ref.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ref.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ref.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ref.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ref.visible = false
	ui.add_child(_ref)
	ui.move_child(_ref, 0)
	var first := "plane"          # the test bed opens straight on the truck (no menu cockpit)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("model="):
			first = a.substr(6)
	show_model(first)


func show_model(name: String) -> void:
	if name == "":
		return
	var path: String = VEHICLES[name][0] if VEHICLES.has(name) else String(ALIASES.get(name, name))
	if not ResourceLoader.exists(path):
		_status.text = "no such model: " + name
		return
	_current = name
	_box.text = name
	_rebuild()


## The corner readout: fps, the frame's time on the CPU and the GPU against
## the 16.6 ms budget (green under, amber close, red over), the worst frame in
## the last second, draw calls, triangles, video memory.
func _perf_update(delta: float) -> void:
	if _perf == null:
		return
	_perf_worst = maxf(_perf_worst, delta * 1000.0)
	_perf_t += delta
	if _perf_t < 0.5:
		return
	_perf_t = 0.0
	var vp := get_viewport().get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var fps := Engine.get_frames_per_second()
	var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var tris := float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1.0e6
	var vram := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1073741824.0
	var worst := maxf(gpu, cpu)
	_perf.text = "%d fps   GPU %.1f ms   CPU %.1f ms\nworst frame %.1f ms   budget 16.6\n%d draws   %.1f M tris   %.2f GB VRAM" % [fps, gpu, cpu, _perf_worst, calls, tris, vram]
	_perf.modulate = Color(0.55, 1.0, 0.55) if worst < 13.0 else (Color(1.0, 0.8, 0.3) if worst < 16.6 else Color(1.0, 0.4, 0.35))
	_perf_worst = 0.0


func _rebuild() -> void:
	for c in _holder.get_children():
		c.queue_free()
	for c in _canvas.get_children():
		c.queue_free()
	var path: String = VEHICLES[_current][0] if VEHICLES.has(_current) else String(ALIASES.get(_current, _current))
	var t0 := Time.get_ticks_msec()
	# reload the script and everything it uses from disk (Godot's cache would hand
	# back the old copy): fresh resources take over the paths, so load() finds them
	for w in WATCH:
		if w != path:
			_fresh(w)
	var scr: Script = _fresh(path)
	if scr == null or not scr.can_instantiate():
		_status.text = "%s: script error (see the Output panel)" % _current
		return
	var node: Object = scr.new()
	_bed.attach(null, [])
	if VEHICLES.has(_current):
		var veh: Node3D = node
		if String(VEHICLES[_current][1]) != "" and veh.get("variant") != null:
			veh.variant = VEHICLES[_current][1]
		veh.terrain = FlatGround.new()
		_holder.add_child(veh)
		if veh.has_method("build"):
			veh.build()
		if veh.has_method("park"):
			veh.park(Transform3D.IDENTITY)
		var g := MeshInstance3D.new()
		g.mesh = _course_mesh(veh.terrain)
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.45, 0.40, 0.33)          # packed dirt, like the bush strips
		gm.roughness = 0.95
		gm.cull_mode = BaseMaterial3D.CULL_DISABLED
		g.material_override = gm
		_holder.add_child(g)
		# something solid for broken-off parts to land on (the flat part of the lab)
		var floor_body := StaticBody3D.new()
		var fcs := CollisionShape3D.new()
		fcs.shape = WorldBoundaryShape3D.new()
		floor_body.add_child(fcs)
		_holder.add_child(floor_body)
		_cam.current = true
		if not _fixed_cam:
			_frame(veh)
		if _driver and veh.has_method("eye_xf"):
			_seat_driver(veh)
		_frame_sheet(veh)
		_bed.attach(veh, [g])
		_finish(path, t0)
		return
	if node is Control:
		_canvas.add_child(node)
		if node.has_method("show_buttons"):
			# the cockpit menu, with the start menu's items
			var names := ["Start", "How to play", "Travel: airstrips and docks", "Plane load and fuel", "Co-op (play with friends)",
				"Load a saved game", "New game (start over)", "Season, weather and realism", "Graphics", "Controls and controller", "Quit to desktop"]
			node.show_buttons(names.map(func(t): return FakeBtn.new(t, func(m): _status.text = m)))
			node.active = true
		_cam.current = false
	elif node is Node3D:
		_holder.add_child(node)
		if _current == "gauges":
			_gauge_demo(node)
		_cam.current = true
		_frame(node)
	else:
		_status.text = "%s isn't a Node3D or Control" % _current
		return
	_finish(path, t0)


func _finish(path: String, t0: int) -> void:
	if not _versioned.has(path):
		_versioned[path] = true
		_save_version(path)
	_stamps = {}
	for w in WATCH + [path]:
		_stamps[w] = FileAccess.get_modified_time(w)
	if _rstamps.is_empty():
		for w in RESTART:
			_rstamps[w] = FileAccess.get_modified_time(w)
	_status.text = "%s   built in %d ms   (live: saves reload it)" % [_current, Time.get_ticks_msec() - t0]
	pass   # (no automatic screenshot: the GPU read-back after each rebuild was the likely trigger of the AMD driver resets - F12 / "shot" only)


# ------------------------------------------------------------------------------
#  Four-view sheet (DESIGN_NOTES 193): side, front, rear and a 3/4 from above,
#  rendered with every screenshot into one picture: _rec/lab_sheet.png
# ------------------------------------------------------------------------------
func _make_sheet() -> void:
	pass                          # (the sheet is shot through the main camera: _save_sheet)


## The four sheet views for the model now: side, front, rear, 3/4 from above.
func _frame_sheet(n: Node3D) -> void:
	var aabb := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	if first:
		return
	var c := aabb.get_center()
	var L := maxf(aabb.size.z, aabb.size.x) * 0.62
	_sheet = [
		{"xf": Transform3D(Basis.IDENTITY, c + Vector3(-12, 0, 0)).looking_at(c), "ortho": true, "size": L * 1.25},
		{"xf": Transform3D(Basis.IDENTITY, c + Vector3(0, 0, -12)).looking_at(c), "ortho": true, "size": aabb.size.y * 1.35},
		{"xf": Transform3D(Basis.IDENTITY, c + Vector3(0, 0, 12)).looking_at(c), "ortho": true, "size": aabb.size.y * 1.35},
		{"xf": Transform3D(Basis.IDENTITY, c + Vector3(L * 1.5, L * 1.6, L * 1.2)).looking_at(c), "ortho": false, "fov": 38.0},
		# (8 views since DESIGN_NOTES 198: one look shows everything)
		{"xf": Transform3D(Basis.IDENTITY, c + Vector3(-L * 1.25, -aabb.size.y * 0.25, -L * 1.35)).looking_at(c + Vector3(0, -0.2, 0)), "ortho": false, "fov": 38.0},
		{"xf": Transform3D(Basis.IDENTITY, c + Vector3(L * 1.3, 0.2, L * 1.3)).looking_at(c), "ortho": false, "fov": 38.0},
		{"xf": Transform3D(Basis.IDENTITY, Vector3(c.x + 0.9, aabb.end.y + 1.2, aabb.position.z + 0.3)).looking_at(Vector3(c.x, aabb.position.y + aabb.size.y * 0.45, aabb.position.z + aabb.size.z * 0.2)), "ortho": false, "fov": 50.0, "mode": "engine"},
		{"xf": Transform3D(Basis.IDENTITY, c + Vector3(-L * 1.1, L * 0.9, L * 0.9)).looking_at(c + Vector3(0, -0.3, 0)), "ortho": false, "fov": 40.0, "mode": "under"},
	]


## Sheet views that need things out of the way: the engine bay (hood off), the
## underside (body panels and the ground off).
func _sheet_mode(mode: String, on: bool) -> void:
	if mode == "" or _holder == null:
		return
	for veh in _holder.get_children():
		if mode == "engine":
			var hd := (veh as Node).find_child("HoodPivot", true, false) as Node3D
			if hd != null:
				hd.visible = not on
		elif mode == "under":
			if veh is MeshInstance3D:
				(veh as Node3D).visible = not on          # the ground
	if mode == "under" and _bed != null and _bed.veh != null:
		_bed._set_chassis(on if not _bed.chassis else true)
	if _driver_node != null and is_instance_valid(_driver_node):
		_driver_node.visible = not on or mode == "engine"


## (The sheet used to come from four SubViewports; on the PC they stopped
## updating after the first frames, so the sheet showed an old model. Now the
## main camera visits each view for a couple of frames, UI hidden.)
var _sheet_busy := false
func _save_sheet() -> void:
	if _sheet.is_empty() or not VEHICLES.has(_current) or _sheet_busy:
		return
	_sheet_busy = true
	var keep_xf := _cam.global_transform
	var keep_proj := _cam.projection
	var keep_fov := _cam.fov
	var keep_size := _cam.size
	_ui.visible = false
	_bed.set_ui(false)
	var out := Image.create(1280, 400 * int(ceil(_sheet.size() / 2.0)), false, Image.FORMAT_RGBA8)
	for i in range(_sheet.size()):
		var v: Dictionary = _sheet[i]
		_cam.global_transform = v["xf"]
		if bool(v["ortho"]):
			_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			_cam.size = float(v["size"])
		else:
			_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			_cam.fov = float(v["fov"])
		_sheet_mode(String(v.get("mode", "")), true)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null:
			continue
		# the middle 16:10 of the window, down to 640 x 400
		var sz := img.get_size()
		var h := mini(sz.y, int(sz.x * 10.0 / 16.0))
		var w := int(h * 16.0 / 10.0)
		img = img.get_region(Rect2i((sz.x - w) / 2, (sz.y - h) / 2, w, h))
		img.resize(640, 400, Image.INTERPOLATE_BILINEAR)
		img.convert(Image.FORMAT_RGBA8)
		out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % 2) * 640, (i / 2) * 400))
		_sheet_mode(String(v.get("mode", "")), false)
	_cam.global_transform = keep_xf
	_cam.projection = keep_proj
	_cam.fov = keep_fov
	_cam.size = keep_size
	_ui.visible = true
	_bed.set_ui(true)
	out.save_png(ProjectSettings.globalize_path("res://_rec/lab_sheet.png"))
	_sheet_busy = false


# ------------------------------------------------------------------------------
#  Driver fit: the character seated as in the game (main._seat_driver)
# ------------------------------------------------------------------------------
func _seat_driver(veh: Node3D) -> void:
	var PR = load("res://scripts/pilot_rig.gd")
	var dm: Node3D = PR.new() if PR.available() else load("res://scripts/pilot_model.gd").new()
	if veh.has_method("seat_clip") and dm.get("seat_clip") != null:
		dm.seat_clip = veh.seat_clip()          # the machine's own seated pose (the Cub: legs out to the pedals)
	_holder.add_child(dm)
	_driver_node = dm
	_driver_veh = veh
	_driver_frames = 45            # the seated pose plays over real frames (_process), then he's placed
	_place_driver()


var _driver_veh: Node3D
var _driver_frames := 0
func _place_driver() -> void:
	var dm := _driver_node
	var veh := _driver_veh
	if dm == null or veh == null or not is_instance_valid(dm) or not is_instance_valid(veh):
		return
	var ex: Transform3D = veh.eye_xf()
	var dy: float = veh.cab_yaw() if veh.has_method("cab_yaw") else float(veh.get("yaw") if veh.get("yaw") != null else 0.0)
	# seated: he takes the cab's full pitch and roll (a rollover turns him over too)
	var yb := Basis(Vector3.UP, dy)
	var tilt: Basis = (yb.inverse() * ex.basis.orthonormalized()).orthonormalized()
	var b: Basis = yb * tilt
	var el: Vector3 = dm.eye_local() if dm.has_method("eye_local") else Vector3.ZERO
	dm.global_transform = Transform3D(b, ex.origin - b * el)


# ------------------------------------------------------------------------------
#  Reference photo overlay: "ref <file in res://reference/> [opacity]" / "ref off"
# ------------------------------------------------------------------------------
func _show_ref(file: String, alpha: float) -> void:
	if file == "off":
		_ref.visible = false
		return
	var path := ProjectSettings.globalize_path("res://reference/" + file)
	var img := Image.load_from_file(path)
	if img == null:
		_status.text = "no reference image: " + file
		return
	_ref.texture = ImageTexture.create_from_image(img)
	_ref.modulate = Color(1, 1, 1, alpha)
	_ref.visible = true


## Every version kept (Dave: "save every version"): a timestamped copy of the
## changed file in res://_versions/<file>/, as .txt so Godot doesn't load it.
func _save_version(p: String) -> void:
	var dir := "res://_versions/%s" % p.get_file().get_basename()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var dst := "%s/%s_%s.txt" % [dir, stamp, p.get_file()]
	DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(dst))


## Relaunch the lab as its own window (same model), then close this one.
func _restart() -> void:
	_status.text = "lab changed: restarting"
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "res://tools/model_lab.tscn", "--", "model=" + _current])
	OS.create_process(OS.get_executable_path(), args)
	get_tree().quit()


## A double-click launcher on the desktop that opens just this lab (no editor,
## no game menu).
func _write_launcher() -> void:
	var exe := OS.get_executable_path()
	if OS.get_name() != "Windows" or exe == "":
		return
	var bat := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).path_join("Model Lab.bat")
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f:
		f.store_string('@echo off\r\nstart "" "%s" --path "%s" res://tools/model_lab.tscn\r\n' % [exe.replace("/", "\\"), ProjectSettings.globalize_path("res://").replace("/", "\\").trim_suffix("\\")])
		f.close()


func _fresh(p: String) -> Resource:
	if not FileAccess.file_exists(p) or p.ends_with(".cfg"):
		return null
	var text := FileAccess.get_file_as_string(p)
	if p.ends_with(".gd"):
		var g := GDScript.new()
		g.source_code = text
		if g.reload() != OK:
			return null
		g.take_over_path(p)
		return g
	if p.ends_with(".gdshader"):
		var sh := Shader.new()
		sh.code = text
		sh.take_over_path(p)
		return sh
	return load(p)


## A row of every instrument, needles moving, for checking the gauges alone.
func _gauge_demo(g: Node3D) -> void:
	var ids := ["airspeed", "attitude", "altimeter", "tach", "heading", "vsi", "clock", "map", "oilp", "oilt", "fuell", "cht"]
	for i in range(ids.size()):
		var id: String = ids[i]
		var x := float(i % 6) * 0.12 - 0.3
		var y := 0.07 - float(i / 6) * 0.13
		var r := 0.05 if i < 6 else 0.03
		match id:
			"attitude":
				g.add(id, Vector3(x, y, 0), r, func() -> Vector2: return Vector2(sin(Time.get_ticks_msec() * 0.001) * 0.3, 0.1))
			_:
				g.add(id, Vector3(x, y, 0), r, func() -> float: return (sin(Time.get_ticks_msec() * 0.0007) * 0.5 + 0.5) * 2500.0)


func _frame(n: Node3D) -> void:
	var aabb := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	if first:
		aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	if n.has_meta("frame_aabb"):
		aabb = n.get_meta("frame_aabb")          # a town: frame the streets, not the mountains round it
	_target = aabb.get_center()
	_dist = maxf(aabb.size.length() * 1.3, 0.3)
	_place_cam()


func _place_cam() -> void:
	var off := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.position = _target + off
	_cam.look_at(_target)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# (Dave) right button drags to look / turn round it; the left button
		# works the cockpit: click a switch, lever or knob
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_click_control(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if _fixed_cam:
				_cam.fov = clampf(_cam.fov * 0.85, 6.0, 100.0)     # in a seat: the wheel zooms (right in, to read a gauge or a placard)
			else:
				_dist *= 0.9
				_place_cam()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if _fixed_cam:
				_cam.fov = clampf(_cam.fov / 0.85, 6.0, 100.0)
			else:
				_dist *= 1.1
				_place_cam()
	elif event is InputEventMouseMotion and _drag and _cam.current and _fixed_cam:
		# a fixed camera (the cockpit view, a close-up): dragging turns your head
		# where you sit instead of throwing the camera back out to orbit (Dave)
		var hm := event as InputEventMouseMotion
		_cam.rotate(Vector3.UP, -hm.relative.x * 0.005)
		var pitch_now := _cam.rotation.x - hm.relative.y * 0.005
		if absf(pitch_now) < 1.45:
			_cam.rotate_object_local(Vector3.RIGHT, -hm.relative.y * 0.005)
	elif event is InputEventMouseMotion and _drag and _cam.current:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.01
		_pitch = clampf(_pitch - mm.relative.y * 0.01, -1.4, 1.4)
		_place_cam()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_F12:
		_shot()
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_M:
		_ear_muffs(not _muffs)


## Ear muffs (M, or "muffs on/off"): hearing protection round the lab's diesel -
## everything quieter and dull, the highs cut, as through real muffs.
var _muffs := false
func _ear_muffs(on: bool) -> void:
	_muffs = on
	load("res://scripts/audio.gd").set_muffled(on)
	if _person != null and is_instance_valid(_person) and _person.has_method("ear_muffs"):
		_person.ear_muffs(on)                 # the standing character puts them on too
	if _status != null:
		_status.text = "%s   Ear muffs %s (M)" % [_current, "ON" if on else "off"]


## Click a control: the nearest thing marked "control" on screen (within a
## finger's width) gets worked - veh.control_click(name) says what it did.
func _click_control(at: Vector2) -> void:
	var v: Node3D = _bed.get("veh") if _bed != null else null
	if v == null or not v.has_method("control_click"):
		return
	var best: Node3D = null
	var bd := 34.0
	for n in v.find_children("*", "Node3D", true, false):
		var nd := n as Node3D
		if not nd.has_meta("control") or not nd.is_visible_in_tree():
			continue
		var c := nd.global_position
		var mis := nd.find_children("*", "MeshInstance3D", false, false)
		if not mis.is_empty():
			var mi := mis[0] as MeshInstance3D
			c = mi.global_transform * mi.get_aabb().get_center()
		if _cam.is_position_behind(c):
			continue
		var d := _cam.unproject_position(c).distance_to(at)
		if d < bd:
			bd = d
			best = nd
	if best != null:
		_status.text = "%s   %s" % [_current, String(v.control_click(String(best.get_meta("control"))))]


func _process(delta: float) -> void:
	_perf_update(delta)
	if _tool != null and is_instance_valid(_tool) and _tool.get("status") != null and _status != null:
		_status.text = "%s   %s" % [_current, String(_tool.get("status"))]
	# Dave: quieter engines in the test bed
	var ebus := AudioServer.get_bus_index("Engines")
	if ebus >= 0 and AudioServer.get_bus_volume_db(ebus) > -11.9:
		AudioServer.set_bus_volume_db(ebus, -12.0)
	if _driver_frames > 0 and _driver_node != null and is_instance_valid(_driver_node):
		_driver_frames -= 1
		if _driver_node.has_method("animate"):
			_driver_node.animate(delta, 5, 0.0, float(Time.get_ticks_msec()) * 0.001)
		_place_driver()
		if _driver_frames == 0:
			pass   # (no automatic screenshot: the GPU read-back after each rebuild was the likely trigger of the AMD driver resets - F12 / "shot" only)
	elif _driver_node != null and is_instance_valid(_driver_node):
		_place_driver()          # he rides with the cab every frame (the excavator's upper swings away from where he was put)
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.5
		for w in _rstamps.keys():
			if FileAccess.get_modified_time(w) != int(_rstamps[w]):
				_restart()
				return
		for w in _stamps.keys():
			if FileAccess.get_modified_time(w) != int(_stamps[w]):
				_status.text = "%s changed: rebuilding" % String(w).get_file()
				_save_version(w)
				_rebuild()
				break
		_read_cmd()
	if _shot_in > 0.0:
		_shot_in -= delta
		if _shot_in <= 0.0:
			_shot(false)


func _read_cmd() -> void:
	if not FileAccess.file_exists(CMD):
		return
	var st := FileAccess.get_modified_time(CMD)
	if st == _cmd_stamp:
		return
	_cmd_stamp = st
	if _cmd_stamp_first:
		_cmd_stamp_first = false
		return            # don't replay the last session's command on start-up
	# several commands, one per line: run one after another, a couple of
	# seconds apart (one file push does a whole test: set up, camera, go)
	var lines := FileAccess.get_file_as_string(CMD).strip_edges().split("\n", false)
	for i in range(lines.size()):
		var ln := String(lines[i]).strip_edges()
		if ln == "":
			continue
		if i == 0:
			_run_cmd(ln)
		else:
			get_tree().create_timer(2.5 * float(i)).timeout.connect(_run_cmd.bind(ln))


var _cmd_stamp_first := true
var _tool: Node
var _person: Node3D
func _run_cmd(line: String) -> void:
	var words := line.split(" ", false)
	if words.is_empty():
		return
	if words[0] == "shot":
		_shot()
		return
	if words[0] == "sheet":
		_save_sheet()
		return
	if words[0] == "ref":
		_show_ref(words[1] if words.size() > 1 else "off", float(words[2]) if words.size() > 2 else 0.45)
		return
	if words[0] == "test":
		_bed.command(words[1] if words.size() > 1 else "run")
		return
	# "run res://tools/x.gd": run a lab tool script (a Node) - downloads, bakes
	if words[0] == "run" and words.size() > 1:
		# always the copy on disk now (load() would hand back a cached old one)
		var sc = ResourceLoader.load(words[1], "", ResourceLoader.CACHE_MODE_REPLACE)
		if sc != null:
			var tool_node: Node = sc.new()
			tool_node.name = "LabTool"
			add_child(tool_node)
			_tool = tool_node
		return
	if words[0] == "muffs":
		_ear_muffs(words.size() < 2 or words[1] != "off")
		return
	# "ctl <name> [<name>...]": work controls on the vehicle by name (as if clicked),
	# e.g. "ctl valve_0 valve_1" shuts/opens spray valves
	if words[0] == "ctl":
		var cv: Node = _bed.get("veh") if _bed != null else null
		if cv != null and cv.has_method("control_click"):
			var said := ""
			for wi in range(1, words.size()):
				said = String(cv.control_click(words[wi]))
			_status.text = "%s   %s" % [_current, said]
		return
	# "person x y z yaw [phone]" (world, yaw in degrees; phone = on the phone) or "person off": a standing
	# character for scale beside whatever's in the lab
	if words[0] == "person":
		if _person != null and is_instance_valid(_person):
			_person.queue_free()
			_person = null
		if words.size() >= 4:
			var PR2 = load("res://scripts/pilot_rig.gd")
			var pm: Node3D = PR2.new() if PR2.available() else load("res://scripts/pilot_model.gd").new()
			add_child(pm)
			pm.position = Vector3(float(words[1]), float(words[2]), float(words[3]))
			pm.rotation.y = deg_to_rad(float(words[4]) if words.size() >= 5 else 0.0)
			if pm.has_method("animate"):
				pm.animate(0.016, 0, 0.0, 0.0)
			if words.has("phone") and pm.has_method("phone"):
				pm.phone(true)
			if words.has("muffs") and pm.has_method("ear_muffs"):
				pm.ear_muffs(true)
			_person = pm
		return
	if words[0] == "driver":
		_driver = words.size() < 2 or words[1] != "off"
		_rebuild()
		return
	# "<model> pcam px py pz tx ty tz [fov]": the same, in the model's own frame
	# (the plane's: -Z forward, origin at the wing's quarter chord) - it follows
	# the model however it's sitting (tail down, rolled on a squashed tyre...)
	if words.size() >= 8 and words[1] == "pcam":
		var v: Node3D = _bed.get("veh") if _bed != null else null
		if v != null:
			var xf: Transform3D = v.global_transform
			var rt = v.get("_root")
			if rt is Node3D:
				xf = (rt as Node3D).global_transform
			var a := xf * Vector3(float(words[2]), float(words[3]), float(words[4]))
			var b := xf * Vector3(float(words[5]), float(words[6]), float(words[7]))
			var rest := " ".join(words.slice(8))
			_run_cmd("%s cam %f %f %f %f %f %f %s" % [words[0], a.x, a.y, a.z, b.x, b.y, b.z, rest])
		return
	# "<model> cam px py pz tx ty tz": put the camera exactly there (inside a cab, say)
	if words.size() >= 8 and words[1] == "cam":
		if words[0] != _current:
			show_model(words[0])
		_cam.position = Vector3(float(words[2]), float(words[3]), float(words[4]))
		_cam.look_at(Vector3(float(words[5]), float(words[6]), float(words[7])))
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		if words.size() >= 9:
			var fv := float(words[8])
			if fv < 0.0:            # negative = orthographic, that many metres tall (for checking against drawings)
				_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
				_cam.size = -fv
			else:
				_cam.fov = fv
		_fixed_cam = true
		pass   # (no automatic screenshot: the GPU read-back after each rebuild was the likely trigger of the AMD driver resets - F12 / "shot" only)
		return
	_fixed_cam = false
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 40.0
	if words.size() >= 4:
		_yaw = float(words[1])
		_pitch = float(words[2])
		_dist = float(words[3])
	if words[0] != _current:
		show_model(words[0])
	else:
		_place_cam()
		pass   # (no automatic screenshot: the GPU read-back after each rebuild was the likely trigger of the AMD driver resets - F12 / "shot" only)


func _shot(keep: bool = true) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	if _shot_n == 0:
		# carry on the numbering after a restart (the timelapse is every frame in order)
		for f in DirAccess.get_files_at("res://_rec"):
			if f.begins_with("lab_") and f.ends_with(".jpg"):
				_shot_n = maxi(_shot_n, int(f.trim_prefix("lab_").trim_suffix(".jpg")))
	_shot_n += 1
	img.save_png(ProjectSettings.globalize_path("res://_rec/lab_latest.png"))
	# (the 8-view sheet only on the "sheet" command now: shooting it after every
	# reload was a GPU spike each time - DESIGN_NOTES 206)
	if keep:      # numbered copies only when asked (F12 / "shot"): milestones, not every reload
		img.save_jpg(ProjectSettings.globalize_path("res://_rec/lab_%03d.jpg" % _shot_n), 0.85)
	_status.text = "%s   screenshot saved (_rec/lab_latest.png)" % _current


# ------------------------------------------------------------------------------
#  For the test bed
# ------------------------------------------------------------------------------
func say(m: String) -> void:
	_status.text = "%s   %s" % [_current, m]


func orbit(yaw: float, pitch: float, dist: float) -> void:
	_fixed_cam = false
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 40.0
	_yaw = yaw
	_pitch = pitch
	_dist = dist
	_place_cam()


## Drive mode: the camera keeps its angle and follows; the driver rides along.
func follow(target: Vector3) -> void:
	_target = _target.lerp(target, 0.15)
	_place_cam()
	_place_driver()


## The ground mesh: 60 x 60 m, the course's bumps in it.
func _course_mesh(gnd: Object) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 120
	var size := 60.0
	var c0 := Vector2(-size * 0.5, -size * 0.5 - 18.0)
	var step := size / n
	for j in range(n):
		for i in range(n):
			var p := [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]
			var v: Array = []
			for q in p:
				var x: float = c0.x + (q as Vector2).x * step
				var z: float = c0.y + (q as Vector2).y * step
				v.append(Vector3(x, float(gnd.height_at(x, z)), z))
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var a: Vector3 = v[tri[0]]
				var b: Vector3 = v[tri[1]]
				var c: Vector3 = v[tri[2]]
				var nn := (b - a).cross(c - a).normalized()
				if nn.y < 0.0:
					nn = -nn
				for vv in [a, b, c]:
					st.set_normal(nn)
					st.add_vertex(vv)
	return st.commit()
