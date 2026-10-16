extends Node3D
## Puts the game together: world, wind, aeroplane, cameras, panel, menu and sound,
## and turns key presses into control inputs.

const WorldScript = preload("res://scripts/world.gd")
const WindScript = preload("res://scripts/wind.gd")
const PlaneScript = preload("res://scripts/plane.gd")
const EngineScript = preload("res://scripts/engine.gd")
const PlaneVisual = preload("res://scripts/plane_visual.gd")
const DC3Visual = preload("res://scripts/dc3_visual.gd")
const DC3Cockpit = preload("res://scripts/dc3_cockpit.gd")
const PlaneTypes = preload("res://scripts/plane_types.gd")
var prospect: Node3D                  # digging and panning for gold, anywhere
var _pros_target: Array = []
var forklifts: Array = []             # yard forklifts at the hangar towns and mines
var noises: Node = null               # vehicle_noises.gd
var vdamage: Node = null              # vehicle_damage.gd
var explosions: Node = null           # explosions.gd
var dynamite: Node3D = null           # dynamite.gd: lit sticks thrown or set (DESIGN_NOTES 176)
var _plane_fire_t := 0.0              # how long the plane's been alight (it goes up at PLANE_FUSE)
var _plane_fuse_told := false
const PLANE_FUSE := 45.0
var driving: Node3D = null            # the forklift you're on
var _near_fork: Node3D = null
var _near_sale := {}                  # for-sale plane you're standing beside
var alights: Node3D                   # the plane's nav, beacon, strobe, landing and taxi lights
var blights: Node3D                   # building light switches
var _switch := -1
var service: Node3D                   # working on the engine with the cowling open
var camp: Node3D                      # bush camp: fire, beer, smokes, being drunk
var dc3_vis: Node3D                  # the DC-3's outside and flight deck, shown when flying one
var dc3_cockpit: Node3D
var wolverine_cockpit: Node3D
var type_vis := {}                   # other types (biplane...): type -> their visual (DESIGN_NOTES 153)
const HudScript = preload("res://scripts/hud.gd")
const TopoMapScript = preload("res://scripts/topo_map.gd")
const MenuScript = preload("res://scripts/menu.gd")
const MenuCockpitScript = preload("res://scripts/menu_cockpit.gd")
## Stand-in for a menu Button while the boot cockpit shows (only .text is read).
class _BootBtn:
	extends RefCounted
	var text := ""
	func _init(t: String) -> void:
		text = t
const AudioScript = preload("res://scripts/audio.gd")
const EngineSound = preload("res://scripts/engine_sound.gd")
const PartsLib = preload("res://scripts/parts.gd")
const AmbienceScript = preload("res://scripts/ambience.gd")
const DebrisScript = preload("res://scripts/debris.gd")
const OnFootScript = preload("res://scripts/on_foot.gd")
const PilotModel = preload("res://scripts/pilot_model.gd")
const Flora = preload("res://scripts/flora.gd")
const MeshKit = preload("res://scripts/meshkit.gd")
const GroundFx = preload("res://scripts/ground_fx.gd")
const FleetScript = preload("res://scripts/fleet.gd")
var fleet: Node
const NetScript = preload("res://scripts/net.gd")
var net: Node
const SkydiveScript = preload("res://scripts/skydive.gd")
var skydive: Node3D
var landing_light: SpotLight3D
const MiningScript = preload("res://scripts/mining.gd")
var mining: Node
const BuildsScript = preload("res://scripts/builds.gd")
const CampScript = preload("res://scripts/camp.gd")
const ServiceScript = preload("res://scripts/engine_service.gd")
const BLightsScript = preload("res://scripts/building_lights.gd")
const ALightsScript = preload("res://scripts/aircraft_lights.gd")
const ForkliftScript = preload("res://scripts/forklift.gd")
const ProspectScript = preload("res://scripts/prospect.gd")
var builds: Node3D
const PilotRig = preload("res://scripts/pilot_rig.gd")
const JobsScript = preload("res://scripts/jobs.gd")
const CargoScript = preload("res://scripts/cargo.gd")

const EYE := Vector3(-0.24, 0.80, -0.32)      # pilot's eye, left front seat (moved by Game.seat_height and seat_fore)

var world: Node3D
var wind: Node
var plane: Node3D
var visual: Node3D
var hud: Control
var topo: Control                     # the 3D relief chart (topo_map.gd)
var menu: CanvasLayer
var cam: Camera3D
var touch: CanvasLayer                  # touch_controls.gd: phone controls

var cockpit := false
var _chase_yaw := 0.0
var _chase_dist := 19.0
var _orbit := Vector2.ZERO          # extra look angles from the mouse (yaw, pitch)
var _orbit_idle := 0.0
var _dragging := false
var _ready_to_fly := false
var _test: Dictionary = {}
var _test_keys := false
var _cockpit_fov := 72.0
var _mouse_looked := false
var cockpit_ctl: Node3D               # the clickable cockpit
var _shake := 0.0
var ambience: Node3D
var _part_target: Array = []          # [vehicle, slot] you're looking at (DESIGN_NOTES 111)
var _zoom_hold := false            # right button held in the cockpit: lean in
var _cockpit_fov_now := 72.0
var _shake_t := 0.0
var _shake_kick := 0.0             # a bump that dies away (touchdown, a rut)
var _was_on_ground := true
var _prev_vy := 0.0
var walker: Node3D                    # the pilot on foot
var _perf_label: Label                # the console's "perf" frame-time readout
var on_foot := false
var wear: Node                        # wear.gd: track and tyre marks on the ground
var rails: Node                       # mine_rails.gd: track and ore cars
var _foot_down := false
var _exit_hold := 0.0                 # seconds the controller's get-out button has been held
var seated: Node3D                    # the pilot sitting in the plane, seen from outside
var _clock := 0.0
var jobs: Node                        # the job board and what is on board
var cargo: Node3D                     # the pieces of cargo you carry by hand


func _ready() -> void:
	# the story mission plays on a copy of the save: if it was quit half way, put the player's own game back
	load("res://scripts/story_mission.gd").restore_if_needed()
	_parse_args()
	if Game.load_slot_pending > 0:
		_restore_slot(Game.load_slot_pending)
		Game.load_slot_pending = 0
	if Game.new_game_pending:
		_wipe_saves()
	# (DESIGN_NOTES 188) a normal start shows the cockpit menu straight away, so the
	# world is never seen half-built; tests keep the plain loading card.
	var loading: Node = null
	var boot: Control = null
	if _test.is_empty():
		loading = CanvasLayer.new()
		(loading as CanvasLayer).layer = 21
		add_child(loading)
		boot = MenuCockpitScript.new()
		boot.boot = true
		loading.add_child(boot)
		boot.show_buttons(["Start", "How to play", "Travel: airstrips and docks", "Plane load and fuel",
			"Co-op (play with friends)", "Load a saved game", "New game (start over)",
			"Season, weather and realism", "Graphics", "Controls and controller", "Quit to desktop"].map(func(t): return _BootBtn.new(t)))
		# a few frames so the rain is falling and the shaders are warm before the long build
		for _i in range(30):
			await get_tree().process_frame
	else:
		loading = _loading_label()
		await get_tree().process_frame
		await get_tree().process_frame
	_build()
	_ready_to_fly = true
	if _test.is_empty() or _test.has("indoors"):
		_start_indoors()
	if _test.is_empty():
		menu.settle_check = func() -> bool:
			return world == null or world.vegetation == null or world.vegetation.is_idle()
		menu.adopt_cockpit(boot)
		menu.open("main")
	if loading != null:
		loading.queue_free()
	elif _test.has("selftest"):
		_run_selftest()
	else:
		_run_test()


func _loading_label() -> CanvasLayer:
	var layer := CanvasLayer.new()
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var label := Label.new()
	label.text = "Surveying the claim..."
	label.add_theme_font_size_override("font_size", 30)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(label)
	add_child(layer)
	return layer


func _build() -> void:
	_check_world_stamp()
	world = WorldScript.new()
	world.name = "World"
	add_child(world)
	var t0 := Time.get_ticks_msec()
	world.build(1987, 768, not _test.has("notrees"))
	if not _test.is_empty():
		print("world build ms: ", Time.get_ticks_msec() - t0)

	wind = WindScript.new()
	wind.name = "Wind"
	wind.terrain = world.terrain
	add_child(wind)
	world.wind = wind

	plane = PlaneScript.new()
	plane.name = "Aeroplane"
	plane.terrain = world.terrain
	plane.waves = world.waves
	plane.wind = wind
	plane.tyre_kind = Game.tyre_kind
	plane.leg_kind = Game.leg_kind
	plane.apply_gear()
	add_child(plane)
	var debris := DebrisScript.new()
	debris.name = "Debris"
	debris.terrain = world.terrain
	add_child(debris)
	visual = PlaneVisual.new()
	visual.name = "Visual"
	visual.plane = plane
	visual.debris = debris
	visual.wind = wind
	plane.add_child(visual)
	# Landing light in the left wing's leading edge: on after dark.
	landing_light = SpotLight3D.new()
	landing_light.name = "LandingLight"
	landing_light.position = Vector3(-2.6, 0.86, -0.75)
	landing_light.rotation = Vector3(deg_to_rad(-6.0), 0.0, 0.0)
	landing_light.spot_range = 320.0
	landing_light.spot_angle = 16.0
	landing_light.light_energy = 0.0
	landing_light.light_color = Color(1.0, 0.93, 0.8)
	landing_light.set_meta("ext", true)   # survives visual.repaint()
	visual.add_child(landing_light)
	landing_light.visible = false        # replaced by aircraft_lights.gd (on a switch)
	alights = ALightsScript.new()
	alights.name = "AircraftLights"
	alights.plane = plane
	plane.add_child(alights)
	alights.setup(plane.plane_type)
	# The pilot in the left seat, placed so his eyes are where the cockpit camera is.
	seated = PilotRig.new() if PilotRig.available() else PilotModel.new()
	seated.name = "SeatedPilot"
	seated.set_meta("ext", true)          # survives visual.repaint()
	visual.add_child(seated)
	seated.build()
	seated.animate(0.0, PilotModel.SIT, 0.0, 0.0)
	seated.position = EYE - seated.eye_local()
	jobs = JobsScript.new()
	jobs.name = "Jobs"
	jobs.plane = plane
	jobs.terrain = world.terrain
	add_child(jobs)
	fleet = FleetScript.new()
	fleet.name = "Fleet"
	fleet.plane = plane
	fleet.jobs = jobs
	fleet.terrain = world.terrain
	fleet.world = world
	add_child(fleet)
	fleet.setup()
	jobs.changed.connect(fleet.save_fleet)
	var gfx := GroundFx.new()
	gfx.name = "GroundFx"
	gfx.plane = plane
	gfx.terrain = world.terrain
	gfx.waves = world.waves
	add_child(gfx)
	walker = OnFootScript.new()
	walker.name = "PilotOnFoot"
	walker.terrain = world.terrain
	walker.plane = plane
	walker.extra_planes = func() -> Array:
		var out: Array = fleet._parked_nodes.values()
		for e in world.sale_planes:
			out.append(e["node"])
		return out
	add_child(walker)
	walker.visible = false
	touch = load("res://scripts/touch_controls.gd").new()
	touch.m = self
	add_child(touch)
	cargo = CargoScript.new()
	cargo.name = "Cargo"
	cargo.jobs = jobs
	jobs.cargo = cargo
	cargo.plane = plane
	cargo.terrain = world.terrain
	cargo.walker = walker
	add_child(cargo)
	_make_forklifts()
	_make_tug()

	cam = Camera3D.new()
	cam.name = "Camera"
	# moved every frame in _process from interpolated positions: no physics
	# interpolation of its own (that would lag it a tick and jitter)
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.near = 0.25
	cam.far = 42000.0
	cam.fov = 68.0
	add_child(cam)
	cam.make_current()
	if world.vegetation != null:
		world.vegetation.camera = cam
		world.vegetation.wind = wind

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = HudScript.new()
	hud.plane = plane
	hud.terrain = world.terrain
	hud.wind = wind
	hud.camera = cam
	hud_layer.add_child(hud)
	topo = TopoMapScript.new()
	topo.name = "TopoMap"
	topo.terrain = world.terrain
	topo.plane = plane
	topo.hud = hud
	topo.wind = wind
	topo.visible = false
	hud_layer.add_child(topo)

	menu = MenuScript.new()
	menu.plane = plane
	menu.jobs = jobs
	menu.fleet = fleet
	skydive = SkydiveScript.new()
	skydive.name = "Skydive"
	skydive.plane = plane
	skydive.jobs = jobs
	skydive.terrain = world.terrain
	skydive.wind = wind
	skydive.notice = func(t: String): hud.push_message(t, 6.0)
	add_child(skydive)
	hud.skydive = skydive
	mining = MiningScript.new()
	mining.name = "Mining"
	mining.jobs = jobs
	mining.terrain = world.terrain
	add_child(mining)
	menu.mining = mining
	# Vehicle parts (DESIGN_NOTES 111): every real part and where it's fitted.
	var parts_existed: bool = PartsLib.load_all()
	inv = load("res://scripts/inventory.gd").new()
	inv.name = "Inventory"
	inv.terrain = world.terrain
	add_child(inv)
	inv.load_all()
	if not parts_existed:
		PartsLib.stock_shelves()          # a turbo kit, heads, a radiator... in the workshop
		PartsLib.save_all()
	inv_ui = load("res://scripts/inventory_ui.gd").new()
	inv_ui.name = "InventoryUI"
	inv_ui.inv = inv
	hud_layer.add_child(inv_ui)
	prospect = ProspectScript.new()
	prospect.name = "Prospecting"
	prospect.inv = inv
	# Generators and rope lights for the drifts (DESIGN_NOTES 90).
	power = load("res://scripts/tunnel_power.gd").new()
	power.name = "TunnelPower"
	power.terrain = world.terrain
	power.inv = inv
	power.say = func(t: String) -> void: hud.push_message(t, 4.0)
	add_child(power)
	power.load_all()
	prospect.power = power
	prospect.on_cave_in = func(q: Vector3, hit: bool) -> void:
		if hit:
			walker.health = maxf(walker.health - 0.55, 0.05)
			hud.push_message("The roof came in on you! You dig yourself out, battered.", 6.0)
		elif on_foot and walker.global_position.distance_to(q) < 45.0:
			hud.push_message("A dull thump and a gust of dust: a cave-in back in the drift.", 5.0)
	prospect.terrain = world.terrain
	prospect.world = world
	prospect.jobs = jobs
	prospect.hud = hud
	prospect.tree_cb = func(tr: Dictionary, push: Vector3) -> void:
		world.fell_tree(int(tr["ti"]), int(tr["tj"]), push)
		hud.push_message("Pushed a tree over. Get down and buck it up for the logs.", 2.0)
	add_child(prospect)
	prospect.load_all()
	world.paint_digs()
	_cut_caves()
	water_sim = load("res://scripts/water_sim.gd").new()
	water_sim.name = "Water"
	add_child(water_sim)
	water_sim.setup(world.terrain)
	water_truck = load("res://scripts/water_truck.gd").new()
	water_truck.name = "WaterTruck"
	water_truck.terrain = world.terrain
	water_truck.water = water_sim
	add_child(water_truck)
	water_truck.build()
	water_truck.load_or_default()
	# The fuel truck (DESIGN_NOTES 118): the same truck with an aluminium tank,
	# diesel and avgas, parked by the fuel pump on the apron.
	fuel_truck = load("res://scripts/water_truck.gd").new()
	fuel_truck.variant = "fuel"
	fuel_truck.name = "FuelTruck"
	fuel_truck.terrain = world.terrain
	fuel_truck.water = water_sim
	fuel_truck.home_xf = _fuel_truck_home()
	fuel_truck.fuel_points = func() -> Array: return world.fuel_points
	fuel_truck.refuel_targets = func() -> Array: return _refuel_targets()
	fuel_truck.charge = func(dollars: float) -> bool: return _pay_fuel(dollars)
	add_child(fuel_truck)
	fuel_truck.build()
	fuel_truck.load_or_default()
	# The log trailer (DESIGN_NOTES 124): at the tool yard, hitch it to the pickup.
	log_trailer = load("res://scripts/log_trailer.gd").new()
	log_trailer.name = "LogTrailer"
	log_trailer.idx = 0
	log_trailer.ground = func(x: float, z: float) -> float: return world.terrain.height_at(x, z)
	add_child(log_trailer)
	log_trailer.build()
	var lt_home := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(LOG_TRAILER_HOME.x, world.terrain.height_at(LOG_TRAILER_HOME.x, LOG_TRAILER_HOME.z), LOG_TRAILER_HOME.z))
	log_trailer.global_transform = log_trailer.saved_xf(lt_home)
	log_trailer.on_moved = func(n: Node3D) -> void: n.mark_moved()
	log_trailer.cargo_kg = func() -> float: return cargo.truck_load_kg(log_trailer)
	prospect.towables.append(log_trailer)
	_build_log_deck()
	# The pickup (DESIGN_NOTES 79): cargo in the bed, a hitch for the gear.
	pickup = load("res://scripts/pickup_truck.gd").new()
	pickup.name = "Pickup"
	pickup.terrain = world.terrain
	pickup.towables = func() -> Array: return prospect.towables
	pickup.bed_load = func() -> float: return cargo.truck_load_kg()
	add_child(pickup)
	pickup.build()
	var tow0: Array = pickup.load_or_default()
	pickup.setup_parts()
	water_truck.setup_parts()          # tyres, suspension and engine parts (DESIGN_NOTES 125)
	fuel_truck.setup_parts()
	if tow0.size() == 2:
		for tw in prospect.towables:
			if tw.kind == String(tow0[0]) and tw.idx == int(tow0[1]):
				pickup.towing = tw
				tw.towed_by = pickup
				tw.follow(pickup.hitch_point())
	cargo.trucks = [pickup, log_trailer]
	cargo.deck_at = LOG_DECK
	cargo.on_deck = func(n: int) -> void:
		builds.add_logs(n)
		hud.push_message("+%d log%s on the deck: %d in stock for building and the crafting bench." % [n, "" if n == 1 else "s", builds.logs], 3.5)
	cargo.load_logs()
	prospect.rock_found = func(at: Vector3, kg: float) -> void: cargo.add_rock(at, kg)
	prospect.rock_in_way = func(at: Vector3, r: float) -> Dictionary: return cargo.rock_near(at, r)
	prospect.rocks_take = func(at: Vector3, r: float) -> Array: return cargo.take_rocks_near(at, r)
	prospect.rocks_put = func(at: Vector3, pcs: Array) -> void: cargo.put_rocks(at, pcs)
	prospect.oversize_out = func(at: Vector3, kg: float) -> String:
		var n2 := 0
		for pc in cargo.own_rocks["pieces"]:
			if pc["at"] == "dropped" and (pc["pos"] as Vector3).distance_to(at) < 2.5:
				n2 += 1
		var went: String = cargo.oversize_rock(at, kg) if n2 < 14 else "ground"
		return went
	prospect.rock_pile_full = func(at: Vector3) -> bool:
		var n := 0
		for pc in cargo.own_rocks["pieces"]:
			if pc["at"] == "dropped" and (pc["pos"] as Vector3).distance_to(at) < 2.5:
				n += 1
		return n >= 14
	# quartz veins (DESIGN_NOTES 139): chunks of ore to carry to the hopper
	prospect.ore_found = func(at: Vector3, kg: float, g: float) -> void: cargo.add_ore(at, kg, g)
	cargo.hopper_at = func(at: Vector3) -> Vector3: return prospect.hopper_near(at)
	cargo.into_hopper = func(at: Vector3, kg: float, g: float) -> String:
		var said: String = prospect.ore_into_hopper(at, kg, g)
		hud.push_message(said, 4.0)
		return said
	# Engines you hear where they are (DESIGN_NOTES 105).
	_engine_sound(pickup, "v8cam", Vector3(0, 1.0, -2.2), func() -> Dictionary:
		return {"rpm": pickup.rpm, "running": pickup.engine_on, "boost": pickup.esim.spool if pickup.esim.part("turbo") > 0 else 0.0})
	_engine_sound(fuel_truck, "diesel", Vector3(0.4, 1.8, -2.6), func() -> Dictionary:
		return {"rpm": fuel_truck.rpm, "running": fuel_truck.engine_on, "load": fuel_truck.load_now,
			"throttle": fuel_truck.throttle_in if fuel_truck.driven else 0.0,
			"speed": fuel_truck.body.speed if fuel_truck.body != null else 0.0})
	_engine_sound(water_truck, "diesel", Vector3(0.4, 1.8, -2.6), func() -> Dictionary:
		return {"rpm": water_truck.rpm, "running": water_truck.engine_on, "load": water_truck.load_now,
			"throttle": water_truck.throttle_in if water_truck.driven else 0.0,
			"speed": water_truck.body.speed if water_truck.body != null else 0.0})
	ambience = AmbienceScript.new()
	ambience.name = "Ambience"
	ambience.terrain = world.terrain
	add_child(ambience)
	# Clunks, squeaks, rattles and the odd squealing belt (DESIGN_NOTES 114).
	noises = load("res://scripts/vehicle_noises.gd").new()
	noises.name = "VehicleNoises"
	add_child(noises)
	# Damage for every ground machine (DESIGN_NOTES 137).
	vdamage = load("res://scripts/vehicle_damage.gd").new()
	vdamage.name = "VehicleDamage"
	vdamage.vehicles = _all_vehicles
	vdamage.notice = func(t: String): hud.push_message(t, 5.0)
	vdamage.watching = func() -> Node3D: return driving
	vdamage.burning = func(p: Vector3) -> bool: return fire != null and fire.burning_at(p)
	add_child(vdamage)
	# Wildfire (DESIGN_NOTES 80).
	fire = load("res://scripts/fire.gd").new()
	fire.name = "Fire"
	fire.terrain = world.terrain
	fire.world = world
	fire.wind = wind
	fire.hud = hud
	add_child(fire)
	fire.setup()
	water_truck.on_spray = func(at: Vector3) -> void:
		fire.douse(at, 3.0)
		_douse_machines(at, 3.0)
		if world.structures != null:
			world.structures.douse(at, 3.0)
	# The buildings (DESIGN_NOTES 147): stoves, smoke, and they burn.
	if world.structures != null:
		var sts: Node3D = world.structures
		sts.fire = fire
		sts.wind = wind
		sts.walker = walker
		sts.hud = hud
	# Explosions (DESIGN_NOTES 142): a burning plane or machine left too long.
	explosions = load("res://scripts/explosions.gd").new()
	explosions.name = "Explosions"
	explosions.terrain = world.terrain
	explosions.fire = fire
	explosions.debris = debris
	add_child(explosions)
	explosions.on_shake = func(k: float) -> void: _shake = maxf(_shake, 3.0 * k)
	explosions.listener = func() -> Vector3: return walker.global_position if on_foot else plane.global_position
	explosions.hurt_near = _blast_hurt
	dynamite = load("res://scripts/dynamite.gd").new()
	dynamite.name = "Dynamite"
	dynamite.terrain = world.terrain
	dynamite.vox = world.ground_view
	dynamite.explosions = explosions
	dynamite.prospect = prospect
	dynamite.world = world
	dynamite.on_blast = _on_dynamite_blast
	add_child(dynamite)
	explosions.ignite_obj = func(at: Vector3, r: float) -> void:
		_ignite_near(at, r)
		if world.structures != null:
			world.structures.ignite_near(at, r)
	explosions.boom = func(_st: float) -> void:
		var au := get_node_or_null("Audio")
		if au != null:
			au.explode()
	if vdamage != null:
		vdamage.ground_fire = func(at: Vector3, r: float) -> void: fire.ignite(at, r)
		vdamage.on_explode = _machine_blew
		vdamage.on_repaired = func(k: String) -> void:
			for e in _all_vehicles():
				if String(e[0]) == k:
					_char(e[2], false)
	# The wheel loader (DESIGN_NOTES 89): bucket or forks, by the mining pad.
	loader = load("res://scripts/loader.gd").new()
	loader.ready.connect(func() -> void: machine_sound(loader, "machine", Vector3(0, 1.6, 1.4), 4.0), CONNECT_ONE_SHOT)
	loader.name = "Loader"
	loader.terrain = world.terrain
	loader.on_dig = func(pt: Vector3, r: float, m3: float) -> Dictionary:
		var got: Dictionary = prospect.dig(pt, r, m3, 0.1)
		if got.has("why"):
			# nothing to dig, but rocks lying there still go in the bucket
			var only: Dictionary = prospect.scoop_rocks({}, pt, r + 0.8)
			return only
		return prospect.scoop_rocks(got, pt, r + 0.8)
	loader.on_dump = func(pt: Vector3, l: Dictionary) -> String: return prospect._dump(pt, l)
	loader.hopper_at = func(pt: Vector3) -> Vector3: return prospect.hopper_near(pt)
	add_child(loader)
	loader.build()
	loader.load_or_default()
	# The mud bog's sign (DESIGN_NOTES 112).
	var bogc: Vector2 = load("res://scripts/ground.gd").mudbog()
	var sign_at := Vector3(bogc.x - 30.0, 0, bogc.y + 9.0)
	sign_at.y = world.terrain.height_at(sign_at.x, sign_at.z)
	var mk = load("res://scripts/meshkit.gd").new()
	for px in [-0.9, 0.9]:
		mk.box(Transform3D(Basis.IDENTITY, Vector3(px, 1.0, 0)), Vector3(0.12, 2.0, 0.12), Color(0.36, 0.27, 0.18))
	mk.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.75, 0)), Vector3(2.3, 0.75, 0.06), Color(0.55, 0.42, 0.28))
	var sign_node: MeshInstance3D = mk.instance("MudBogSign")
	sign_node.position = sign_at
	sign_node.rotation.y = PI * 0.5
	world.add_child(sign_node)
	var sl := Label3D.new()
	sl.text = "MUD BOG\nenter at your own risk"
	sl.font_size = 64
	sl.pixel_size = 0.006
	sl.modulate = Color(0.15, 0.1, 0.06)
	sl.position = Vector3(0, 1.78, 0.04)
	sign_node.add_child(sl)
	# Mud for every wheel and track (DESIGN_NOTES 109).
	var wb_script := load("res://scripts/wheeled_body.gd")
	var tb_script := load("res://scripts/tracked_body.gd")
	if _test.has("nomud"):
		world.terrain.mud_base.fill(0.0)
	wb_script.mud_fn = world.terrain.mud_at
	wb_script.rut_fn = world.terrain.rut
	# track and tyre marks (DESIGN_NOTES 150)
	wear = load("res://scripts/wear.gd").new()
	wear.name = "Wear"
	add_child(wear)
	wear.setup(world.terrain)
	tb_script.wear_fn = wear.track
	wb_script.tyre_fn = wear.tyre
	tb_script.mud_fn = world.terrain.mud_at
	tb_script.rut_fn = world.terrain.rut
	# Dust off the wheels and tracks of everything you can drive (DESIGN_NOTES 108).
	var vdust := load("res://scripts/vehicle_dust.gd").new() as Node3D
	vdust.name = "VehicleDust"
	vdust.terrain = world.terrain
	vdust.vehicles = func() -> Array:
		var out: Array = [pickup, water_truck, fuel_truck, loader]
		out.append_array(prospect.dozers)
		out.append_array(prospect.excavators)
		out.append_array(forklifts)
		return out
	add_child(vdust)
	# Gore (DESIGN_NOTES 81): walk into a turning prop.
	gore = load("res://scripts/gore.gd").new()
	gore.name = "Gore"
	gore.ground_at = func(x: float, z: float) -> float: return world.terrain.ground_level_at(x, z)
	add_child(gore)
	walker.prop_strike.connect(_on_prop_strike)
	# Birds and bird strikes (DESIGN_NOTES 82).
	birds = load("res://scripts/birds.gd").new()
	birds.name = "Birds"
	birds.terrain = world.terrain
	birds.plane_ref = func() -> Node3D: return plane
	birds.walker = walker
	birds.gore = gore
	birds.hud = hud
	birds.vehicles = func() -> Array: return [pickup, water_truck, fuel_truck, loader] + prospect.excavators + prospect.dozers
	add_child(birds)
	birds.setup()
	if world.ground_view != null and world.ground_view.has_method("floor_below"):
		walker.vox = world.ground_view
	walker.ladder_at = func(pos: Vector3) -> int: return prospect.ladder_at(pos)
	walker.ladder_info = func(i: int) -> Array: return prospect.ladders[i]
	menu.prospect = prospect
	# mine track and ore cars (DESIGN_NOTES 151)
	rails = load("res://scripts/mine_rails.gd").new()
	rails.name = "Rails"
	rails.terrain = world.terrain
	rails.vox = world.ground_view if world.ground_view != null and world.ground_view.has_method("floor_below") else null
	rails.prospect = prospect
	rails.inv = inv
	rails.walker = walker
	rails.hud = hud
	world.add_child(rails)
	menu.rails = rails
	prospect.cart_fill = func(p: Vector3, layer: String, g: float) -> String: return rails.load_near(p, layer, g)
	menu.workshop = _workshop_vehicles
	menu.quick_items = _quick_items
	menu.slots_host = self
	_goals_load()
	hud.places = _places
	menu.repairs = _repair_list
	jobs.contract_done.connect(func(t: String, b: int): hud.push_message("Contract complete: %s. Bonus $%d." % [t, b], 8.0))
	jobs.rep_up.connect(func(nm: String, st: String): hud.push_message("%s: you're now \"%s\" there. More work, better pay." % [nm, st], 6.0))
	jobs.warn.connect(func(t: String): hud.push_message(t, 5.0))
	jobs.detonated.connect(_on_dynamite)
	blights = BLightsScript.new()
	blights.name = "BuildingLights"
	add_child(blights)
	for hl in world._hangar_lights:
		blights.add_group(hl["switch"], hl["lamps"], hl["fixtures"])
	if world.structures != null:
		for ln in world.structures.lanterns:
			var lp: Vector3 = ln[0]
			blights.add_group(lp, [lp + Vector3(0, -0.1, 0)], [[ln[1], Vector3(0.09, 0.13, 0.09)]], "lantern")
	builds = BuildsScript.new()
	builds.lights = blights
	builds.name = "Builds"
	builds.terrain = world.terrain
	builds.world = world
	builds.jobs = jobs
	builds.mining = mining
	builds.walker = walker
	builds.plane = plane
	world.add_child(builds)
	# The workbench in the hangar (DESIGN_NOTES 92, 152).
	crafting = load("res://scripts/crafting.gd").new()
	crafting.name = "Crafting"
	crafting.terrain = world.terrain
	crafting.inv = inv
	crafting.builds = builds
	crafting.jobs = jobs
	crafting.prospect = prospect
	add_child(crafting)
	crafting.build(world.workbench, world.workbench_yaw)
	prospect.crafting = crafting
	prospect.truck = water_truck
	prospect.fuel_truck = fuel_truck
	camp = CampScript.new()
	camp.name = "Camp"
	camp.main = self
	camp.builds = builds
	camp.walker = walker
	camp.hud = hud
	add_child(camp)
	service = ServiceScript.new()
	service.name = "EngineService"
	service.main = self
	service.plane = plane
	service.walker = walker
	service.jobs = jobs
	service.fleet = fleet
	service.hud = hud
	add_child(service)
	menu.service = service
	mining.builds = builds
	fleet.builds = builds
	menu.builds = builds
	menu.walker = walker
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	net.note.connect(func(t: String): hud.push_message(t, 6.0))
	if Game.pending_join != "":
		var addr_j: String = Game.pending_join
		Game.pending_join = ""
		var rejoin := func() -> void:
			var err_j: String = net.join(addr_j)
			hud.push_message(err_j if err_j != "" else "Rejoining %s in the host's world..." % addr_j, 5.0)
		rejoin.call_deferred()
	menu.net = net
	hud.jobs = jobs
	hud.cargo = cargo
	menu.terrain = world.terrain
	menu.repaint = _repaint_active
	menu.save_all = _save_all
	menu.new_game = _new_game
	add_child(menu)
	menu.start_requested.connect(_on_start_requested)
	menu.dock_requested.connect(_on_dock_requested)
	menu.reset_requested.connect(_reset_to_last_strip)
	menu.tutorial_requested.connect(_start_tutorial)
	menu.story_requested.connect(start_story)
	var console = load("res://scripts/console.gd").new()
	console.name = "Console"
	console.main = self
	add_child(console)
	# F10: the vehicle and item picker (garage_menu.gd)
	var garage = load("res://scripts/garage_menu.gd").new()
	garage.name = "Garage"
	garage.main = self
	add_child(garage)
	menu.toast.connect(func(t: String): hud.push_message(t, 6.0))

	var audio := AudioScript.new()
	audio.name = "Audio"
	audio.plane = plane
	add_child(audio)

	cockpit_ctl = visual.cockpit
	cockpit_ctl.build(plane, world.terrain)
	cockpit_ctl.said.connect(func(text: String): hud.push_message(text, 2.5))
	cockpit_ctl.clicked.connect(audio.click)
	wolverine_cockpit = cockpit_ctl
	hud.cockpit_has_panel = true
	# The DC-3: its own outside and flight deck, swapped in when you fly one.
	dc3_vis = DC3Visual.new()
	dc3_vis.name = "DC3Visual"
	dc3_vis.plane = plane
	dc3_vis.debris = debris
	dc3_vis.wind = wind
	dc3_vis.visible = false
	plane.add_child(dc3_vis)
	dc3_cockpit = DC3Cockpit.new()
	dc3_cockpit.name = "DC3Cockpit"
	dc3_cockpit.set_meta("ext", true)     # survives dc3_vis.repaint()
	dc3_vis.add_child(dc3_cockpit)
	dc3_cockpit.build(plane, world.terrain)
	dc3_cockpit.said.connect(func(text: String): hud.push_message(text, 2.5))
	dc3_cockpit.clicked.connect(audio.click)
	fleet.changed.connect(_apply_plane_type)
	_apply_plane_type()

	plane.crashed.connect(_on_crashed)
	hazards = load("res://scripts/crash_hazards.gd").new()
	hazards.name = "CrashHazards"
	hazards.plane = plane
	hazards.fire = fire
	hazards.wind = wind
	hazards.on_notice = func(t: String) -> void: hud.push_message(t, 6.0)
	add_child(hazards)
	plane.crashed.connect(func(_r):
		jobs.on_crashed()
		if jobs.salvage_note != "":
			hud.push_message(jobs.salvage_note, 9.0))
	plane.dented.connect(func(_p, _d, sev): jobs.on_damage(float(sev) * 0.3))
	jobs.changed.connect(_on_jobs_changed)
	plane.tree_felled.connect(func(ti: int, tj: int, push: Vector3): world.fell_tree(ti, tj, push))
	plane.exploded.connect(func(st: float):
		_shake = maxf(_shake, 1.2 * st)
		# a crash that goes up all at once: burning fuel thrown about (the
		# fireball and the wreckage are the plane's own)
		if explosions != null:
			explosions.blow(plane.global_position, st, Color(0.3, 0.3, 0.3), false))
	plane.landed.connect(_on_landed)
	plane.notice.connect(func(text: String): hud.push_message(text, 6.0))
	walker.notice = func(text: String): hud.push_message(text, 4.0)
	Game.settings_changed.connect(_on_settings_changed)

	var k: int = clampi(Game.last_strip, 0, world.terrain.strips.size() - 1)
	plane.place_on_strip(k)
	jobs.restow()
	_on_jobs_changed()
	hud.target_strip = -1 if world.terrain.strips.size() < 2 else (1 if k == 0 else 0)
	_chase_yaw = _plane_yaw()
	_update_camera(1.0, true)


func _on_jobs_changed() -> void:
	var d: int = jobs.next_destination()
	if d >= 0:
		hud.target_strip = d
	if not jobs.last_paid.is_empty():
		hud.push_message("Delivered: %s.  +$%d" % [jobs.last_paid[0], int(jobs.last_paid[1])], 6.0)
		jobs.last_paid = []


var tutorial: Node

## THE FIRE: the story opening, ~15 minutes (story_mission.gd).
var story: Node
func start_story() -> void:
	if story != null and is_instance_valid(story):
		story.queue_free()
	story = load("res://scripts/story_mission.gd").new()
	story.name = "Story"
	story.main = self
	add_child(story)
	story.start()


func _start_tutorial() -> void:
	if tutorial == null:
		tutorial = load("res://scripts/tutorial.gd").new()
		tutorial.name = "Tutorial"
		tutorial.main = self
		tutorial.plane = plane
		tutorial.jobs = jobs
		tutorial.hud = hud
		add_child(tutorial)
	# Start at Port Ashby, on the runway, engine running, no load.
	if on_foot:
		_get_in(true)
	_on_start_requested(0, false)
	tutorial.start()


## Amphibian coming down over water with its wheels down: say so loudly,
## because touching down like that flips it onto its back.
var _gear_warn_t := 0.0

func _gear_warning(delta: float) -> void:
	_gear_warn_t -= delta
	if not plane.is_amphib() or plane.on_ground or not plane.gear_down or plane.agl > 120.0 or plane.vel.y > -0.3:
		return
	var gp: Vector3 = plane.global_position
	if world.terrain.water_level_at(gp.x, gp.z) < -1.0e8 or world.terrain.lakes_frozen():
		return
	if _gear_warn_t <= 0.0:
		_gear_warn_t = 3.0
		hud.push_message("WHEELS ARE DOWN OVER WATER!  Press %s to raise them, or you'll flip on touchdown." % Game.hint("gear"), 3.0)


## Show the right aeroplane, flight deck and seat for the type being flown.
## Write every piece of the game's state to disk right now (menu "Save game").
func _save_all() -> void:
	fleet.sync_active()
	fleet.save_fleet()
	jobs.save_career()
	if mining != null:
		mining._save()
	if builds != null:
		builds._save()
	if prospect != null:
		prospect.save()
	if camp != null:
		camp._save()
	if world != null:
		world._save_felled()
	hud.push_message("Game saved.", 2.5)


# ------------------------------------------------------------------------------
#  Save slots (DESIGN_NOTES 169): the live game is the files in user://; a
#  slot is a copy of them in user://slots/N with what the settings file
#  holds about the world (its seed, last strip, wheels).
# ------------------------------------------------------------------------------
const SLOTS := 5


func slot_info(n: int) -> String:
	var cf := ConfigFile.new()
	if cf.load("user://slots/%d/slot.cfg" % n) != OK:
		return "empty"
	return "%s   -   $%d   -   %s" % [String(cf.get_value("s", "when", "?")), int(cf.get_value("s", "money", 0)), String(cf.get_value("s", "where", ""))]


func save_to_slot(n: int) -> String:
	_save_all()
	if inv != null:
		inv.save()
	PartsLib.save_all()
	var dir := "user://slots/%d" % n
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for f in SAVE_FILES:
		var src := ProjectSettings.globalize_path("user://" + f)
		var dst := ProjectSettings.globalize_path(dir + "/" + f)
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(src, dst)
		elif FileAccess.file_exists(dst):
			DirAccess.remove_absolute(dst)
	var cf := ConfigFile.new()
	var t := Time.get_datetime_dict_from_system()
	cf.set_value("s", "when", "%04d-%02d-%02d %02d:%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"]])
	cf.set_value("s", "money", int(jobs.money))
	var k: int = Game.last_strip
	cf.set_value("s", "where", String(world.terrain.strips[k]["name"]) if k >= 0 and k < world.terrain.strips.size() else "")
	cf.set_value("s", "seed", Game.world_seed)
	cf.set_value("s", "last_strip", Game.last_strip)
	cf.set_value("s", "tyre_kind", Game.tyre_kind)
	cf.set_value("s", "leg_kind", Game.leg_kind)
	cf.save(dir + "/slot.cfg")
	return "Saved to slot %d." % n


func load_slot(n: int) -> void:
	if not FileAccess.file_exists("user://slots/%d/slot.cfg" % n):
		return
	# the copy happens in the fresh scene's _ready, before anything loads
	Game.load_slot_pending = n
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


func _restore_slot(n: int) -> void:
	var dir := "user://slots/%d" % n
	var cf := ConfigFile.new()
	if cf.load(dir + "/slot.cfg") != OK:
		return
	for f in SAVE_FILES:
		var live := ProjectSettings.globalize_path("user://" + f)
		var kept := ProjectSettings.globalize_path(dir + "/" + f)
		if FileAccess.file_exists(kept):
			DirAccess.copy_absolute(kept, live)
		elif FileAccess.file_exists(live):
			DirAccess.remove_absolute(live)
	PartsLib.clear()
	Flora.felled = {}
	Flora._near_cache = {}
	Game.world_seed = int(cf.get_value("s", "seed", Game.world_seed))
	Game.last_strip = int(cf.get_value("s", "last_strip", 0))
	Game.tyre_kind = String(cf.get_value("s", "tyre_kind", Game.tyre_kind))
	Game.leg_kind = String(cf.get_value("s", "leg_kind", Game.leg_kind))
	load("res://scripts/ground.gd").use_seed(Game.world_seed)
	Game.save_settings()


## Wipe the career and start the island over (menu "New game"). Settings,
## controls and graphics are kept; money, planes, claims and buildings go.
## Start over: every save goes (career, planes, trucks, the pickup, the
## loader, parts, inventory, mining, buildings, camps, fire, the world);
## only your settings, graphics and controls (settings.cfg) are kept.
func _new_game() -> void:
	# The wipe itself happens in the fresh scene's _ready (_wipe_saves), before
	# anything loads: the old scene runs on to the end of this frame, and a
	# timed save in it (log trailer, tug, parts) would write a file straight back.
	Game.new_game_pending = true
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


const SAVE_FILES := ["career.cfg", "fleet.cfg", "mining.cfg", "builds.cfg", "prospect.cfg", "camp.cfg", "world.cfg", "world_stamp.cfg",
		"truck.cfg", "fuel_truck.cfg", "wiring.cfg", "pickup.cfg", "loader.cfg", "parts.cfg", "inventory.cfg", "fire.cfg", "power.cfg",
		"logs.cfg", "log_trailer.cfg", "tug.cfg", "vehicle_damage.cfg", "structures.cfg", "wear.bin", "rails.cfg", "goals.cfg"]

## Every save goes, and everything the game keeps in memory across a scene
## reload (static vars, the Game autoload's plane and strip) goes back to new.
func _wipe_saves() -> void:
	Game.new_game_pending = false
	for f in SAVE_FILES:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))
	PartsLib.clear()
	Flora.felled = {}
	Flora._near_cache = {}
	Game.last_strip = 0
	Game.tyre_kind = "850"
	Game.leg_kind = "spring"
	# a new world too: the knoll, the creek, the pay and the veins laid out
	# fresh, not the old map with the saves wiped
	Game.world_seed = randi_range(1, 999999)
	load("res://scripts/ground.gd").use_seed(Game.world_seed)
	Game.save_settings()


## Respray the plane you're in (the hangar paint shop; menu.gd calls this).
func _repaint_active(idx: int) -> void:
	plane.livery = idx
	if plane.plane_type == "dc3":
		dc3_vis.repaint()
	elif type_vis.has(plane.plane_type):
		var tv: Node3D = type_vis[plane.plane_type]
		tv.repaint()
		_wire_cockpit(tv)
	else:
		visual.repaint()
		# The clickable cockpit was rebuilt with the body: wire the new one up.
		wolverine_cockpit = visual.cockpit
		wolverine_cockpit.build(plane, world.terrain)
		wolverine_cockpit.said.connect(func(text: String): hud.push_message(text, 2.5))
		var audio := get_node_or_null("Audio")
		if audio != null:
			wolverine_cockpit.clicked.connect(audio.click)
	_apply_plane_type()
	fleet.save_fleet()


func _apply_plane_type() -> void:
	if dc3_vis == null:
		return
	var is_dc3: bool = plane.plane_type == "dc3"
	var tv: Node3D = _type_visual(plane.plane_type)
	var was_cockpit := cockpit
	if was_cockpit:
		_set_cockpit(false)
	visual.visible = not is_dc3 and tv == null
	dc3_vis.visible = is_dc3
	visual.process_mode = Node.PROCESS_MODE_INHERIT if visual.visible else Node.PROCESS_MODE_DISABLED
	dc3_vis.process_mode = Node.PROCESS_MODE_INHERIT if is_dc3 else Node.PROCESS_MODE_DISABLED
	for t in type_vis.keys():
		var on: bool = tv != null and t == plane.plane_type
		(type_vis[t] as Node3D).visible = on
		# a hidden aeroplane's model stops working too (it cost ~0.5 ms a frame)
		(type_vis[t] as Node3D).process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if alights != null:
		alights.setup(plane.plane_type)
	cockpit_ctl = dc3_cockpit if is_dc3 else (tv.cockpit if tv != null else wolverine_cockpit)
	# the seated pilot rides in whichever visual is showing
	var host: Node3D = tv if tv != null else visual
	if seated != null and seated.get_parent() != host:
		seated.get_parent().remove_child(seated)
		host.add_child(seated)
	if seated != null:
		seated.position = _eye_point() - seated.eye_local()
	if was_cockpit:
		_set_cockpit(true)


## The visual for a type that has its own (plane_types "visual"), made the
## first time it's needed; null for the Wolverine and the DC-3.
func _type_visual(t: String) -> Node3D:
	if t == "wolverine" or t == "dc3":
		return null
	if type_vis.has(t):
		return type_vis[t]
	var path := String(PlaneTypes.spec(t).get("visual", ""))
	if path == "":
		return null
	var v: Node3D = load(path).new()
	v.name = "Visual_" + t
	v.plane = plane
	v.debris = visual.debris
	v.wind = wind
	v.visible = false
	plane.add_child(v)
	type_vis[t] = v
	_wire_cockpit(v)
	return v


func _wire_cockpit(v: Node3D) -> void:
	var ck: Node3D = v.cockpit
	if ck == null:
		return
	ck.build(plane, world.terrain)
	if not ck.said.is_connected(_on_cockpit_said):
		ck.said.connect(_on_cockpit_said)
	var audio := get_node_or_null("Audio")
	if audio != null and not ck.clicked.is_connected(audio.click):
		ck.clicked.connect(audio.click)
	if plane.plane_type == v.name.trim_prefix("Visual_"):
		cockpit_ctl = ck


func _on_cockpit_said(text: String) -> void:
	hud.push_message(text, 2.5)


func _eye_point() -> Vector3:
	if plane.plane_type == "dc3":
		return DC3Cockpit.EYE
	var sp: Dictionary = PlaneTypes.spec(plane.plane_type)
	return sp.get("eye", EYE) if plane.plane_type != "wolverine" else EYE


## Bigger aeroplanes get the chase camera further back.
func _size_scale() -> float:
	return clampf(plane.wing_span / 11.0, 1.0, 2.6) if plane.plane_type != "wolverine" else 1.0


func _on_settings_changed() -> void:
	world.apply_season()
	hud.refresh_map()
	if topo != null:
		topo._built_strips = -1    # rebuilt next time the chart opens


## Start floating at a seaplane dock (fits amphibious floats if need be).
func _on_dock_requested(di: int) -> void:
	var d: Dictionary = world.terrain.docks[di]
	if not plane.is_amphib():
		plane.leg_kind = "amphib"
		Game.leg_kind = "amphib"
		plane.apply_gear()
		Game.save_settings()
		hud.push_message("Amphibious floats fitted.", 4.0)
	if on_foot:
		_get_in(true)
	hud.crash_text = ""
	hud.show_help = false
	var out: Vector2 = d["out"]
	var w: Vector2 = (d["water"] as Vector2) + Vector2(-out.y, out.x) * 7.5
	plane.place_on_water(Vector3(w.x, 0.0, w.y), float(d["heading"]))
	jobs.restow()
	world.waves.clear()
	hud.push_message("At %s. Wheels are UP for water (%s to lower them for a runway)." % [d["name"], Game.hint("gear")], 7.0)
	_chase_yaw = _plane_yaw()
	_orbit = Vector2.ZERO
	_update_camera(1.0, true)


func _on_start_requested(k: int, on_approach: bool) -> void:
	if driving != null:
		_get_off_forklift()
	for fl in forklifts:
		fl.go_home()
	if on_foot:
		# Travelling from the menu while outside: you climb back aboard first,
		# or the plane would fly off without you.
		cargo.stow_held()
		on_foot = false
		walker.visible = false
		walker.in_plane = false
		walker.swimming = false
		seated.visible = true
		hud.walker = null
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_set_cockpit(true)
	Game.last_strip = k
	Game.save_settings()
	hud.crash_text = ""
	hud.show_help = false
	if on_approach:
		plane.place_on_approach(k)
		jobs.restow()
		hud.target_strip = k
	else:
		plane.place_on_strip(k)
		# Not on top of a plane already parked there: move up the strip.
		var off := 0.0
		while off < 140.0 and _spawn_blocked():
			off += 18.0
			plane.place_on_strip(k, false, off)
		jobs.restow()
	_chase_yaw = _plane_yaw()
	_orbit = Vector2.ZERO
	_update_camera(1.0, true)


## A parked plane sitting where the player's would appear?
## What a plane standing on the apron goes for: three quarters of list.
func _sale_price(t: String) -> int:
	return int(roundf(float(fleet.PlaneTypes.spec(t)["price"]) * 0.75 / 500.0)) * 500


func _spawn_blocked() -> bool:
	var others: Array = fleet._parked_nodes.values()
	for e in world.sale_planes:
		others.append(e["node"])
	for node in others:
		if node == null or not is_instance_valid(node):
			continue
		var d := Vector2(node.global_position.x - plane.pos.x, node.global_position.z - plane.pos.z).length()
		if d < (plane.wing_span + node.wing_span) * 0.5 * 0.8:
			return true
	return false


func _on_crashed(reason: String) -> void:
	jolt(1.0)
	# The wreck: cut wiring that sparks while the master's on, split tanks
	# that pool fuel (crash_hazards.gd).
	if hazards != null:
		hazards.fire = fire
		hazards.on_crash(float(plane.last_impact))
		hazards.spray_fuel(plane.vel)
	# The pilot takes the hit too, by how hard it was.
	if net.riding == 0 and walker != null:
		var hit: float = clampf((float(plane.last_impact) - 7.0) / 25.0, 0.0, 1.0)
		if hit > 0.0:
			walker.health = maxf(float(walker.health) - hit, 0.0)
			if walker.health <= 0.0:
				reason += "  You didn't survive it."
				_crash_gore(float(plane.last_impact))
			elif hit > 0.45:
				reason += "  You're badly hurt."
			elif hit > 0.15:
				reason += "  You're banged up."
	# A wreck often burns: fuel on hot metal, in the grass.
	if fire != null and randf() < 0.5 and fire.ignite(plane.global_position, 4.0):
		reason += "  She's caught fire: get clear!"
	# No banner: a note, and you carry on. Climb out, or recover the plane from the menu.
	hud.push_message("%s  %s climb out,  %s menu to recover the plane." % [reason, Game.hint("get_out"), Game.hint("menu")], 9.0)


## A crash that killed him (DESIGN_NOTES 157): he stays in his seat, or a
## really fast one throws him out through the windscreen; a violent one
## tears off arms, legs, the head.
func _crash_gore(impact: float) -> void:
	_foot_down = true
	if gore == null or not Game.gore or seated == null or seated.get_parent() == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var violence := clampf((impact - 28.0) / 25.0, 0.0, 1.3)
	var lost: Array = gore.pick_parts(violence, rng)
	var host: Node3D = seated.get_parent()
	var sxf: Transform3D = seated.transform
	var wxf: Transform3D = host.global_transform * sxf
	var chest: Vector3 = wxf * Vector3(0, 1.0, 0)
	if impact > 40.0 and rng.randf() < 0.6:
		var out_vel: Vector3 = plane.vel * 0.55 + Vector3(0, 3.0, 0)
		gore.scatter(Transform3D(wxf.basis.orthonormalized(), wxf.origin + plane.global_transform.basis * Vector3(0, 0.3, -1.2)), "sprawl", lost, out_vel, rng, true)
		gore.burst(chest, plane.vel, 1.2)
	else:
		gore.corpse_in_seat(host, sxf, lost, rng)
		if not lost.is_empty():
			gore.scatter(wxf, "driving", lost, plane.vel * 0.4 + Vector3(0, 2.0, 0), rng, false, 1.0, gore.seat_corpse)
		gore.burst(chest, plane.vel, 0.6)


## On foot near a moving machine (DESIGN_NOTES 157): anything rolling over
## you, a truck hitting you, tracks or a blade going over you.
var _veh_prev := {}          # instance id -> last Transform3D
var _veh_box := {}           # instance id -> AABB in its own frame
var _runover_pf := -1
func _runover_check(delta: float) -> void:
	if not on_foot or driving != null or walker.health <= 0.0 or delta <= 0.0:
		_runover_pf = -1
		return
	# (DESIGN_NOTES 186) speeds come from physics positions, so time them by the
	# physics ticks that actually ran (0, 1 or 2 per frame), not the frame delta;
	# and forget positions remembered before he got out (they read as a huge speed).
	var pf: int = Engine.get_physics_frames()
	if _runover_pf < 0:
		_veh_prev.clear()
		_runover_pf = pf
	var dtp: float = float(pf - _runover_pf) / float(Engine.physics_ticks_per_second)
	if dtp <= 0.0:
		return
	_runover_pf = pf
	delta = dtp
	var me: Vector3 = walker.global_position
	for e in _all_vehicles():
		var v: Node3D = e[2]
		if v == null or not v.is_inside_tree() or not v.visible:
			continue
		var id := v.get_instance_id()
		var xf: Transform3D = v.global_transform
		var prev: Transform3D = _veh_prev.get(id, xf)
		_veh_prev[id] = xf
		if xf.origin.distance_to(me) > 14.0:
			continue
		if not _veh_box.has(id):
			_veh_box[id] = _local_box(v)
		var box: AABB = _veh_box[id]
		var lp: Vector3 = xf.affine_inverse() * me
		var low: float = box.position.y + minf(0.8, box.size.y * 0.5)
		if lp.y > low or lp.x < box.position.x - 0.1 or lp.x > box.end.x + 0.1 or lp.z < box.position.z - 0.1 or lp.z > box.end.z + 0.1:
			continue
		# how fast that bit of the machine is coming through where he stands
		var pv: Vector3 = (me - prev * lp) / delta
		var spd := Vector2(pv.x, pv.z).length()
		var kind: String = e[1]
		var tracked := kind == "dozer" or kind == "excavator"
		var heavy := tracked or kind in ["loader", "water truck", "fuel truck", "log trailer"]
		if spd < (0.35 if tracked else 2.2):
			continue
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var fwd: Vector3 = Vector3(pv.x, 0, pv.z).normalized()
		if not tracked and not heavy and spd < 4.5:
			# knocked flying, hurt, alive
			walker.health = maxf(float(walker.health) - 0.25 - 0.08 * spd, 0.05)
			walker.global_position = me + fwd * 2.0 + xf.basis.x.normalized() * signf(lp.x if absf(lp.x) > 0.01 else 1.0) * 1.2
			hud.red_flash = 0.6
			jolt(0.8)
			if gore != null:
				gore.burst(me + Vector3(0, 0.9, 0), fwd, 0.15)
			hud.push_message("The %s hit you! You pick yourself up, hurting." % kind, 5.0)
			return
		walker.health = 0.0
		_foot_down = true
		hud.red_flash = 1.0
		jolt(1.0)
		walker.model.visible = false
		var what := "run over by the %s" % kind
		if tracked:
			what = "caught under the %s's tracks" % kind
		hud.push_message("You were %s. Open the menu to start again from the last airstrip." % what, 12.0)
		if gore != null and Game.gore:
			var violence := clampf(spd / 8.0, 0.4, 1.2) if not tracked else 0.9
			var lost: Array = gore.pick_parts(violence, rng)
			if tracked and lost.is_empty():
				lost = ["leg_l"] if rng.randf() < 0.5 else ["leg_r"]
			var bxf := Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), me)
			gore.scatter(bxf, "sprawl", lost, pv * (0.15 if tracked else 0.8) + Vector3(0, 0.5 if tracked else 2.5, 0), rng, true, 0.35 if tracked or heavy else 1.0)
			gore.burst(me + Vector3(0, 0.6, 0), fwd, 1.0 if tracked or heavy else 0.7)
			gore.plane_splat(v, me + Vector3(0, 0.5, 0), fwd, 0.9, rng.randi() % 3)
		else:
			walker.model.visible = true
			walker.model.rotation = Vector3(-PI * 0.5, 0, 0.4)
			walker.model.position = Vector3(0, 0.25, 0)
		return


## A tree goes down along `dir`: anyone under it is hit (DESIGN_NOTES 157).
var _tree_coming := {}
func _fell_and_check(tr: Dictionary, dir: Vector3) -> void:
	var base: Vector3 = tr["base"]
	var hgt: float = float(tr.get("height", 12.0))
	dir.y = 0.0
	dir = dir.normalized()
	world.fell_tree(int(tr["ti"]), int(tr["tj"]), dir * 4.0)
	logs_cut += 1
	if not on_foot or driving != null or walker.health <= 0.0:
		return
	var rel: Vector3 = walker.global_position - base
	rel.y = 0.0
	var along := rel.dot(dir)
	var lateral := (rel - dir * along).length()
	if along < 0.3 or along > hgt:
		return
	var k := along / hgt                          # the crown spreads wider up the tree
	if lateral < 0.55 + 0.4 * k:
		walker.health = 0.0
		_foot_down = true
		hud.red_flash = 1.0
		hud.push_message("The tree came down on you. Open the menu to start again from the last airstrip.", 12.0)
		jolt(1.0)
		var me: Vector3 = walker.global_position
		if gore != null and Game.gore:
			walker.model.visible = false
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var lost: Array = gore.pick_parts(0.5 + 0.5 * (1.0 - k), rng)
			gore.scatter(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), me), "sprawl", lost, dir * 1.5, rng, true, 0.45)
			gore.burst(me + Vector3(0, 0.5, 0), dir, 0.9)
		else:
			walker.model.rotation = Vector3(-PI * 0.5, 0, 0.4)
			walker.model.position = Vector3(0, 0.25, 0)
	elif lateral < 1.2 + 1.6 * k:
		walker.health = maxf(float(walker.health) - 0.45, 0.05)
		hud.red_flash = 0.5
		hud.push_message("The branches caught you as it came down. You're hurt.", 5.0)
		jolt(0.6)


## Console: look at the gore pieces without dying.
func gore_test(kind: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var c3 := get_viewport().get_camera_3d()
	var fwd: Vector3 = -c3.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var at: Vector3 = c3.global_position + fwd * 5.0
	at.y = world.terrain.ground_level_at(at.x, at.z)
	var all := ["arm_l", "arm_r", "leg_l", "leg_r", "head"]
	var lost: Array = []
	for p in all:
		if rng.randf() < 0.6:
			lost.append(p)
	var xf := Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), at)
	match kind:
		"crushed":
			gore.scatter(xf, "sprawl", lost, Vector3(0, 0.5, 0), rng, true, 0.35)
		"seat":
			if seated != null and seated.get_parent() != null:
				gore.corpse_in_seat(seated.get_parent(), seated.transform, lost, rng)
		_:
			gore.scatter(xf, "sprawl", lost, fwd * 3.0 + Vector3(0, 4.0, 0), rng, true)
	gore.burst(at + Vector3(0, 0.8, 0), fwd, 0.8)
	return "gore %s: lost %s" % [kind, str(lost)]


## Machines and trees (DESIGN_NOTES 159): a truck or machine driving into a
## tree stops against the trunk; a small one, or a heavy machine going at it,
## snaps it and it falls the way you were going. The dozer flattens anything.
var _tree_prev := {}             # instance id -> last Transform3D
var _tree_told := 0.0
var _trees_pf := -1
func _vehicle_trees(delta: float) -> void:
	if delta <= 0.0:
		return
	_tree_told = maxf(_tree_told - delta, 0.0)
	# physics-tick time, as in _runover_check (DESIGN_NOTES 186)
	var pf: int = Engine.get_physics_frames()
	if _trees_pf < 0:
		_trees_pf = pf
	var dtp: float = float(pf - _trees_pf) / float(Engine.physics_ticks_per_second)
	if dtp <= 0.0:
		return
	_trees_pf = pf
	delta = dtp
	for e in _all_vehicles():
		var v: Node3D = e[2]
		if v == null or not v.is_inside_tree() or not v.visible:
			continue
		var id := v.get_instance_id()
		var xf: Transform3D = v.global_transform
		var prev: Transform3D = _tree_prev.get(id, xf)
		_tree_prev[id] = xf
		var mv: Vector3 = (xf.origin - prev.origin) / delta
		mv.y = 0.0
		var spd := mv.length()
		if spd < 0.15:
			continue
		var dir: Vector3 = mv / spd
		if not _veh_box.has(id):
			_veh_box[id] = _local_box(v)
		var box: AABB = _veh_box[id]
		var ld: Vector3 = xf.basis.orthonormalized().inverse() * dir
		if absf(ld.z) < 0.3:
			continue                  # going sideways (sliding): leave it
		var sgn := signf(ld.z)
		var front_z: float = (box.end.z if sgn > 0.0 else box.position.z) + sgn * 0.1
		var hit := {}
		for fx in [0.15, 0.5, 0.85]:
			var lx: float = lerpf(box.position.x, box.end.x, fx)
			var wp: Vector3 = xf * Vector3(lx, box.position.y + 1.0, front_z)
			var tr: Dictionary = Flora.tree_near(world.terrain, wp)
			if not tr.is_empty() and float(tr["dist"]) < float(tr["trunk_r"]) + 0.2:
				hit = tr
				break
		if hit.is_empty():
			continue
		var kind: String = e[1]
		var hgt: float = float(hit.get("height", 12.0))
		var heavy: bool = kind in ["dozer", "excavator", "loader", "water truck", "fuel truck", "log trailer"]
		var snaps: bool = kind == "dozer" or hgt < 4.0 or (heavy and spd > 2.5 and hgt < 16.0) or (spd > 7.0 and hgt < 9.0)
		var body = v.get("body")
		if driving == v:
			jolt(0.35 if snaps else clampf(spd / 6.0, 0.3, 0.9))
		if snaps:
			world.fell_tree(int(hit["ti"]), int(hit["tj"]), dir * 4.0)
			if body != null:
				body.vel *= 0.85 if heavy else 0.6
			if driving == v and _tree_told <= 0.0:
				_tree_told = 3.0
				hud.push_message("Knocked a tree down. Get out and buck it up for the logs.", 3.0)
		else:
			# against the trunk: no further that way, back to where it touched
			if body != null:
				var into: float = maxf((body.vel as Vector3).dot(dir), 0.0)
				body.vel -= dir * into
				body.pos -= dir * spd * delta
			elif v.get("speed") != null:
				v.set("speed", 0.0)
				v.global_position -= dir * spd * delta
			_tree_prev[id] = v.global_transform
			if driving == v and _tree_told <= 0.0 and spd > 1.0:
				_tree_told = 3.0
				hud.push_message("Into a tree. Back off it, or bring the dozer.", 3.0)


## The how-to-drive-it line a machine shows when you get on, unless turned off
## (the help key while driving, or Options).
func _machine_tip(text: String, secs: float) -> void:
	if Game.machine_hints:
		hud.push_message(text, secs)


## Press (and let go of) an action as if its key was pressed: the quick menu's
## buttons go through the same code as the keyboard.
func _fire(action: String, hold: float = 0.0) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := func() -> void:
		var ev2 := InputEventAction.new()
		ev2.action = action
		ev2.pressed = false
		Input.parse_input_event(ev2)
	if hold > 0.0:
		get_tree().create_timer(hold).timeout.connect(up)
	else:
		up.call_deferred()


## What the quick menu offers where you are (DESIGN_NOTES 162).
func _quick_items() -> Array:
	var out: Array = []
	var f := func(label: String, action: String, hold: float = 0.0) -> void:
		out.append([label, func() -> void: _fire(action, hold)])
	if driving != null:
		if driving.has_method("engine_toggle"):
			f.call("Engine on / off", "engine_auto")
		if driving.has_method("lights_toggle"):
			f.call("Lights", "lights")
		if driving.has_method("four_wd_toggle"):
			f.call("4WD", "four_wd")
		if driving.has_method("diff_lock_toggle"):
			f.call("Diff lock", "diff_lock")
	elif not on_foot:
		f.call("Automatic engine start / shut-down", "engine_auto")
		f.call("Battery master", "master")
		f.call("Alternator", "alternator")
		f.call("Magnetos (off / L / R / both)", "mags")
		f.call("Primer (one stroke)", "primer")
		f.call("Starter (crank 3 s)", "starter", 3.0)
		f.call("Fuel selector", "fuel_selector")
		f.call("Mixture richer", "mixture_rich")
		f.call("Mixture leaner", "mixture_lean")
		f.call("Prop: more rpm", "prop_up")
		f.call("Prop: less rpm", "prop_down")
		f.call("Carb heat", "carb_heat")
		f.call("Cowl flaps", "cowl_flaps")
		f.call("Outside lights", "lights")
		f.call("Landing gear (if retractable)", "gear")
		f.call("Feather the prop", "feather")
		f.call("Seat up", "seat_up")
		f.call("Seat down", "seat_down")
		f.call("Next destination", "next_target")
	if net != null and net.is_online() and (net.riding != 0 or not on_foot):
		f.call("Ask for / hand over the flight controls", "controls")     # co-op (keyboard: K)
	out.append(["Map", func() -> void: _fire("map")])
	out.append(["Job board", func() -> void: menu.open("jobs")])
	f.call("Get out" if not on_foot or driving != null else "Get in", "get_out")
	return out


## Getting started (DESIGN_NOTES 166): a short list of first things to do,
## each ticking itself off when it's done; kept in goals.cfg, gone for good
## once every one is done (or switched off in Options).
const GOALS := [
	["shovel", "Pick up the shovel in the tool yard (M: chart shows where)"],
	["gold", "Dig pay gravel and pan it at water for gold"],
	["engine", "Get in the plane and start the engine"],
	["air", "Take off"],
	["job", "Fly a job from the job board"],
	["tree", "Fell a tree with the chainsaw"],
	["machine", "Drive the loader, dozer or excavator"],
]
var goals_done := {}
var _goals_t := 0.0
func _goals_load() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://goals.cfg") == OK:
		goals_done = cf.get_value("g", "done", {})


func _goals_tick(delta: float) -> void:
	_goals_t -= delta
	if _goals_t > 0.0:
		return
	_goals_t = 1.0
	var ticks := {
		"shovel": inv != null and inv.has("shovel"),
		"gold": prospect != null and float(prospect.gold_g) > 0.0,
		"engine": plane != null and bool(plane.engine.running),
		"air": plane != null and bool(plane.airborne),
		"job": jobs != null and int(jobs.completed) > 0,
		"tree": logs_cut > 0,
		"machine": driving != null and prospect != null and (driving == loader or driving in prospect.dozers or driving in prospect.excavators),
	}
	var changed := false
	for k in ticks.keys():
		if bool(ticks[k]) and not goals_done.has(k):
			goals_done[k] = true
			changed = true
			if Game.goals_on:
				hud.push_message("Done: %s" % _goal_text(k), 4.0)
	if changed:
		var cf := ConfigFile.new()
		cf.set_value("g", "done", goals_done)
		cf.save("user://goals.cfg")
	var lines: Array = []
	if Game.goals_on and goals_done.size() < GOALS.size():
		for g in GOALS:
			lines.append([String(g[1]), goals_done.has(String(g[0]))])
	hud.goals = lines


func _goal_text(k: String) -> String:
	for g in GOALS:
		if String(g[0]) == k:
			return String(g[1]).split(" (")[0]
	return k


## Weather that changes (DESIGN_NOTES 168): every half hour or so a front
## comes through, and you see and hear it coming - the radio calls it ahead,
## the sky greys over and the wind picks up first, then the rain (or snow, or
## fog) sets in, then it clears behind. Off in Options: it stays as set.
var _wx_t := 1200.0                 # seconds to the next change
var _wx_plan: Array = []            # steps still to come: [weather, wind level]
func _weather_tick(delta: float) -> void:
	if not Game.weather_changes or menu.is_open or (net != null and net.is_guest()):
		return
	_wx_t -= delta
	if _wx_t > 0.0:
		if _wx_plan.is_empty() and _wx_t < 300.0 and _wx_t + delta >= 300.0:
			# plan the next front and call it on the radio, five minutes out
			if Game.weather == 0:
				var bad: int = [1, 2, 2, 3][randi() % 4]
				_wx_plan = [[1, mini(Game.wind_level + 1, 3)], [bad, mini(Game.wind_level + 1, 3)]]
				var what: String = ["", "low cloud", "rain" if Game.season != Game.WINTER else "snow", "fog"][bad]
				hud.push_message("Radio: a front's moving in - %s in the next half hour, wind picking up. Get down before it closes in." % what, 9.0)
			else:
				_wx_plan = [[1, maxi(Game.wind_level - 1, 0)], [0, maxi(Game.wind_level - 1, 0)]]
				hud.push_message("Radio: it's clearing from the west behind this lot. Should open up within the half hour.", 8.0)
		return
	if _wx_plan.is_empty():
		_wx_t = randf_range(1500.0, 2400.0)
		return
	var step: Array = _wx_plan.pop_front()
	if int(step[0]) != Game.weather or int(step[1]) != Game.wind_level:
		Game.weather = int(step[0])
		Game.wind_level = int(step[1])
		Game.notify_changed()
		var names: Array = ["Clearing.", "The sky's greying over.", "Here it comes: rain." if Game.season != Game.WINTER else "Here it comes: snow.", "Fog's rolling in."]
		hud.push_message(names[clampi(Game.weather, 0, 3)], 5.0)
	# the next step of the front a few minutes on
	_wx_t = randf_range(240.0, 480.0) if not _wx_plan.is_empty() else randf_range(1500.0, 2400.0)


## The places named on the chart's close-up (DESIGN_NOTES 165).
func _places() -> Array:
	var out: Array = []
	var tool := Color(0.85, 0.55, 0.12)
	var mach := Color(0.95, 0.80, 0.20)
	var bld := Color(0.35, 0.45, 0.55)
	out.append(["Tool yard (shovel, pick, pump...)", (load("res://scripts/inventory.gd").YARD as Dictionary)["shovel"], tool])
	if world.workbench != Vector3.INF:
		out.append(["Workbench (in the hangar)", world.workbench, tool])
	out.append(["Workshop apron (parts, repairs)", WORKSHOP_AT, Color(0.80, 0.25, 0.15)])
	if world.structures != null:
		for id in world.structures.items.keys():
			var it: Dictionary = world.structures.items[id]
			out.append([world.structures._name(it).capitalize(), (it["xf"] as Transform3D).origin, bld])
	for e in _all_vehicles():
		var v: Node3D = e[2]
		if v != null and v.is_inside_tree():
			out.append([String(e[1]).capitalize(), v.global_position, mach])
	if plane != null and (on_foot or driving != null):
		out.append(["Your plane", plane.global_position, Color(0.85, 0.15, 0.12)])
	return out


## The dynamite went up (DESIGN_NOTES 173): the plane blows apart where it
## is; aboard, you don't walk away from that.
func _on_dynamite(strength: float) -> void:
	jolt(1.0)
	_shake = maxf(_shake, 1.0)
	plane._start_fire(1.0)
	plane.exploded.emit(strength)
	if not plane.is_crashed:
		plane._wreck("The dynamite went up.", 50.0)
	if not on_foot and net.riding == 0 and walker != null and walker.health > 0.0:
		walker.health = 0.0
		_crash_gore(60.0)
		hud.push_message("The dynamite went up. Open the menu to start again from the last airstrip.", 12.0)
	elif on_foot and walker != null and walker.global_position.distance_to(plane.global_position) < 25.0:
		var d: float = walker.global_position.distance_to(plane.global_position)
		walker.health = maxf(float(walker.health) - (1.0 - d / 25.0) * 1.2, 0.0)
		hud.red_flash = 0.8


func _light_dynamite() -> void:
	var cxf: Transform3D = walker.camera_transform()
	var fwd: Vector3 = -cxf.basis.z.normalized()
	var eye: Vector3 = walker.global_position + Vector3(0, 1.5, 0)
	inv.remove("dynamite", 1)
	var face = null
	if world.ground_view != null and world.ground_view.has_method("raycast"):
		face = world.ground_view.raycast(eye, fwd, 1.8)
	if face == null and fwd.y < -0.55:
		# looking down at your feet: set it on the ground there
		var gp: Vector3 = walker.global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 0.8
		gp.y = world.terrain.height_at(gp.x, gp.z) + 0.05
		dynamite.light(gp, Vector3.ZERO, 8.0)
		hud.push_message("Fuse lit - 8 seconds. Get well clear!", 4.0)
	elif face != null:
		dynamite.light((face as Vector3) - fwd * 0.12, Vector3.ZERO, 8.0)
		hud.push_message("Charge set against the face, fuse lit - 8 seconds. Get well clear!", 4.0)
	else:
		if not (walker.model.has_method("one_shot") and walker.model.one_shot("throw", 1.4)) and walker.model.has_method("work_motion"):
			walker.model.work_motion("pick")          # an overhand throw
		var vel: Vector3 = fwd * 12.0 + Vector3(0, 3.5, 0)
		dynamite.light(eye + fwd * 0.6 + walker.global_transform.basis.x * 0.25, vel, 5.5)
		hud.push_message("Fire in the hole!", 3.0)
	jolt(0.15)
	net.dynamite_lit(dynamite.last_at, dynamite.last_vel, dynamite.last_fuse)
	if not inv.has("dynamite"):
		hud.push_message("That was your last stick.", 3.0)


func _on_dynamite_blast(at: Vector3) -> void:
	jolt(clampf(1.0 - walker.global_position.distance_to(at) / 40.0, 0.2, 1.0))
	net.blast_near(at)
	var d := walker.global_position.distance_to(at)
	var away: Vector3 = walker.global_position - at
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	if on_foot and walker.health <= 0.0 and not _foot_down:
		_die_in_pieces(away * 7.0 + Vector3(0, 5.0, 0), clampf(1.2 - d / 6.0, 0.5, 1.2),
			"Too close to the blast. Open the menu to start again from the last airstrip.")
		if gore != null:
			gore.burst(walker.global_position + Vector3(0, 0.9, 0), away, 1.0)
	elif on_foot and not _foot_down and d < 5.0 and gore != null and Game.gore and randf() < 0.75:
		# alive, but it took something with it
		_lose_part(["arm_l", "arm_r", "leg_l", "leg_r"].pick_random(), away * 4.0 + Vector3(0, 3.0, 0))
		hud.push_message("The blast took a piece of you.", 4.0)
	elif not _foot_down and d < 30.0:
		hud.push_message("BOOM.", 1.5)


## Dead, in pieces: the body (minus whatever's already gone, and `violence`
## more) thrown with `vel`, your figure hidden, the message up.
func _die_in_pieces(vel: Vector3, violence: float, msg: String) -> void:
	_foot_down = true
	jolt(1.0)
	hud.push_message(msg, 12.0)
	if gore != null and Game.gore:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var lost: Array = gore.pick_parts(violence, rng)
		for p in gore.lost_live(walker.model):
			if not lost.has(p):
				lost.append(p)
		walker.model.visible = false
		gore.scatter(Transform3D(Basis(Vector3.UP, walker.yaw), walker.global_position), "sprawl", lost, vel, rng, true)


## Lose an arm or a leg (or your head: that's the end) and live.
func _lose_part(part: String, vel: Vector3) -> void:
	if gore == null or not Game.gore:
		return
	if part == "head":
		_die_in_pieces(vel, 0.3, "That one took your head off. Open the menu to start again from the last airstrip.")
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if gore.sever_live(walker.model, part, vel, rng):
		jolt(1.0)
		hud.red_flash = 1.0


# ------------------------------------------------------------------------------
#  The pistol (DESIGN_NOTES 180): a plain 9 mm semi-auto. E fires along your
#  view: another player in line takes it (a head shot kills; arms and legs can
#  come off), otherwise the round kicks up dirt where it lands.
# ------------------------------------------------------------------------------
var _pistol_cd := 0.0
var _ads := 0.0                     # 0 hip .. 1 aiming down the sights
var _ready_until := 0.0             # fired from the hip: the pistol stays up until then
var force_aim := false              # console handcheck aim: hold the aim (testing)
var handcam := 0                    # console handcheck: 1 front, 2 behind, 0 off
var hits_taken := 0                 # co-op: others play your flinch when it ticks


func _pad_rt() -> float:
	var v := 0.0
	for d in Input.get_connected_joypads():
		v = maxf(v, Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT))
	return v


## On foot RT is the use trigger: dig, swing, fire, pick up - the same as E
## / X (DESIGN_NOTES 183). Pulled past 60% it presses "interact" once.
var _pad_sprint := false
var _rt_down := false
func _rt_use() -> void:
	var v := _pad_rt()
	if not _rt_down and v > 0.6 and not menu.is_open:
		_rt_down = true
		var ev := InputEventAction.new()
		ev.action = "interact"
		ev.pressed = true
		Input.parse_input_event(ev)
	elif _rt_down and v < 0.3:
		_rt_down = false
		var ev2 := InputEventAction.new()
		ev2.action = "interact"
		ev2.pressed = false
		Input.parse_input_event(ev2)


func _pad_lt() -> float:
	var v := 0.0
	for d in Input.get_connected_joypads():
		v = maxf(v, Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT))
	return v
var _shot_wav: AudioStreamWAV


func _fire_pistol() -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now < _pistol_cd:
		return
	_pistol_cd = now + 0.32
	_ready_until = now + 1.5
	if _ads < 0.3 and (_hand_node == null or _hand_id != "pistol"):
		# drawing from the holster: the first press only brings it up
		walker.aiming = true
		_sync_shovel()
		return
	# along the actual view (over the shoulder when aiming); from the hip it wanders
	var cxf: Transform3D = cam.global_transform
	var from: Vector3 = cxf.origin
	var spread := lerpf(0.045, 0.004, _ads)
	var dir: Vector3 = (-cxf.basis.z + cxf.basis.x * randf_range(-spread, spread) + cxf.basis.y * randf_range(-spread, spread)).normalized()
	net.swings += 1
	if _ads < 0.5 and walker.model.has_method("one_shot"):
		walker.model.one_shot("pistol_shoot", 1.6)
	var muzzle: Vector3 = walker.global_position + Vector3(0, 1.2, 0) + Basis(Vector3.UP, walker.yaw) * Vector3(0.25, 0, -0.5)
	if _hand_node != null and is_instance_valid(_hand_node) and _hand_node.is_visible_in_tree():
		muzzle = _hand_node.global_transform * Vector3(0, 0.074, -0.19)
	pistol_fx(muzzle)
	jolt(0.35)
	# what's in the way first: the ground, a face
	var wall := 150.0
	if world.ground_view != null and world.ground_view.has_method("raycast"):
		var hp = world.ground_view.raycast(from, dir, 150.0)
		if hp != null:
			wall = from.distance_to(hp as Vector3)
	# machines and planes in the way: glass breaks and lets it through,
	# anything else stops it (and takes the damage)
	var thing: Dictionary = _bullet_trace(from, dir, wall)
	if not thing.is_empty():
		wall = float(thing["t"])
	var hit: Array = net.shot_target(from, dir, wall)
	if not hit.is_empty():
		var vic: int = hit[0]
		var head: bool = hit[1]
		var at: Vector3 = hit[2]
		if gore != null and Game.gore:
			gore.burst(at, dir, 0.3)
		var dmg := 1.5 if head else randf_range(0.28, 0.38)
		var line: String = net.hit_player(vic, dmg, "pistol", from, "head" if head else ("limb" if randf() < 0.2 else ""))
		if line != "":
			hud.push_message(line, 2.5)
		return
	if not thing.is_empty():
		_bullet_hits(thing, from + dir * wall, dir)
		_bullet_mark(from + dir * wall, dir, thing["node"], true)
	elif wall < 150.0:
		_dirt_puff(from + dir * wall)
		_bullet_mark(from + dir * wall, dir, null, false)


## What a round along `dir` strikes before `wall` m among the machines and
## planes: {t, kind, node, key, mi} or {}. Glass on the way breaks (it
## doesn't stop the round). Tested mesh by mesh against each box.
func _bullet_trace(from: Vector3, dir: Vector3, wall: float) -> Dictionary:
	var targets: Array = []
	for e in _all_vehicles():
		targets.append([e[2], "veh", String(e[0])])
	if on_foot and plane != null:
		targets.append([plane, "plane", ""])
	if fleet != null:
		for n in (fleet.get("_parked_nodes") as Dictionary).values():
			targets.append([n, "plane", ""])
	for id in net.remotes.keys():
		var rn: Node3D = net.remotes[id].get("node")
		if rn != null:
			targets.append([rn, "remote", str(id)])
	var best := {}
	var best_t := wall
	var glass: Array = []
	for tg in targets:
		var node: Node3D = tg[0]
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var to: Vector3 = node.global_position - from
		var along := to.dot(dir)
		if along < -20.0 or along > best_t + 20.0 or (to - dir * along).length() > 16.0:
			continue
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.is_visible_in_tree() or m.has_meta("shot_out"):
				continue
			var t := _ray_box(from, dir, m.global_transform, m.get_aabb())
			if t < 0.0 or t >= best_t:
				continue
			if _is_glass(m):
				glass.append([t, m])
			else:
				best_t = t
				best = {"t": t, "kind": tg[1], "node": node, "key": tg[2], "mi": m}
	for g in glass:
		if float(g[0]) < best_t:
			_break_glass(g[1] as MeshInstance3D, from + dir * float(g[0]), dir)
	return best


## Where a ray enters a box (mesh space) or -1.
func _ray_box(from: Vector3, dir: Vector3, xf: Transform3D, box: AABB) -> float:
	var inv := xf.affine_inverse()
	var o: Vector3 = inv * from
	var d: Vector3 = inv.basis * dir
	var t0 := -1e9
	var t1 := 1e9
	for a in range(3):
		if absf(d[a]) < 1e-8:
			if o[a] < box.position[a] or o[a] > box.end[a]:
				return -1.0
			continue
		var ta := (box.position[a] - o[a]) / d[a]
		var tb := (box.end[a] - o[a]) / d[a]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t1 < maxf(t0, 0.0):
		return -1.0
	return maxf(t0, 0.0)


func _is_glass(m: MeshInstance3D) -> bool:
	var nm := String(m.name).to_lower()
	if "glass" in nm or "window" in nm or "windshield" in nm or "screen" in nm:
		return true
	var mat: Material = m.material_override if m.material_override != null else m.get_active_material(0)
	if "prop" in nm or "disc" in nm or "blur" in nm or "shadow" in nm or "smoke" in nm or "flame" in nm:
		return false
	return mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
		and (mat as BaseMaterial3D).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED \
		and (mat as BaseMaterial3D).albedo_color.a < 0.6


## A pane goes: the glass vanishes, a shower of bits, a crunch.
func _break_glass(m: MeshInstance3D, at: Vector3, dir: Vector3) -> void:
	m.visible = false
	m.set_meta("shot_out", true)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 40
	p.lifetime = 1.2
	p.direction = dir
	p.spread = 55.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.01
	p.scale_amount_max = 0.035
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.15, 1.0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.85, 0.92, 0.95, 0.7)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.metallic_specular = 1.0
	gm.roughness = 0.05
	bm.material = gm
	p.mesh = bm
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## The round struck a machine or a plane: sparks, and the damage.
func _bullet_hits(thing: Dictionary, at: Vector3, dir: Vector3) -> void:
	_dirt_puff(at, Color(0.55, 0.52, 0.48))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.5)
	l.light_energy = 2.0
	l.omni_range = 2.0
	add_child(l)
	l.global_position = at - dir * 0.1
	get_tree().create_timer(0.04).timeout.connect(l.queue_free)
	var node: Node3D = thing["node"]
	match String(thing["kind"]):
		"veh":
			if vdamage != null:
				vdamage.hurt(String(thing["key"]), 0.02, 0.05, 0.0)
		"plane", "remote":
			var lp: Vector3 = node.global_transform.affine_inverse() * at
			var part := "fuselage"
			if absf(lp.x) > 1.0 and lp.y > 0.6:
				part = ("wing_l" if lp.x < 0.0 else "wing_r") if absf(lp.x) < 4.0 else ("aileron_l" if lp.x < 0.0 else "aileron_r")
				if absf(lp.x) < 2.2 and randf() < 0.4:
					part = "tank_l" if lp.x < 0.0 else "tank_r"
			elif lp.z < -1.6:
				part = "prop"
			elif lp.z > 3.5:
				part = "rudder" if lp.y > 0.9 else "elevator"
			elif lp.y < 0.0:
				part = "tire_l" if lp.x < 0.0 else "tire_r"
			if String(thing["kind"]) == "remote":
				net.shoot_plane(int(String(thing["key"])), part)
			elif node.has_method("hurt"):
				node.hurt(part, 0.06)


## A bullet hole where a round struck (DESIGN_NOTES 183): a small decal
## pressed onto whatever is there - ground, a rock face, a truck's door, a
## wing - riding along with a machine it's on. The newest 80 are kept.
var _marks: Array = []
var _hole_tex: ImageTexture
var _hole_metal_tex: ImageTexture


func _bullet_mark(at: Vector3, dir: Vector3, on: Node3D, metal: bool) -> void:
	if metal and _hole_metal_tex == null:
		_hole_metal_tex = _make_hole(true)
	if not metal and _hole_tex == null:
		_hole_tex = _make_hole(false)
	var d := Decal.new()
	d.texture_albedo = _hole_metal_tex if metal else _hole_tex
	d.size = Vector3(0.09, 0.5, 0.09) if metal else Vector3(0.16, 0.6, 0.16)
	d.upper_fade = 0.0
	d.lower_fade = 0.2
	d.cull_mask = 0xFFFFF
	var y := -dir.normalized()
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var spin := Basis(y, randf() * TAU)
	var host: Node = on if (on != null and is_instance_valid(on)) else self
	host.add_child(d)
	d.global_transform = Transform3D(spin * Basis(x, y, z), at)
	_marks.append(d)
	while _marks.size() > 80:
		var old_m = _marks.pop_front()
		if old_m != null and is_instance_valid(old_m):
			(old_m as Node).queue_free()


## The hole itself, drawn once: a black centre, a torn dark ring, and (on
## metal) a bright scuffed rim where the paint flaked off.
func _make_hole(metal: bool) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51 if metal else 17
	for py in range(n):
		for px in range(n):
			var v := Vector2(px - n * 0.5 + 0.5, py - n * 0.5 + 0.5)
			var r := v.length() / (n * 0.5)
			var ang := atan2(v.y, v.x)
			var rough := 0.06 * sin(ang * 7.0) + 0.04 * sin(ang * 13.0 + 1.3) + rng.randf_range(-0.03, 0.03)
			var c := Color(0, 0, 0, 0)
			if r < 0.22 + rough * 0.5:
				c = Color(0.02, 0.02, 0.02, 1.0)
			elif metal and r < 0.38 + rough:
				c = Color(0.62, 0.60, 0.56, 0.9)          # bare metal round the hole
			elif r < 0.62 + rough:
				var k := (r - 0.22) / 0.4
				c = Color(0.10, 0.08, 0.06, (1.0 - k) * (0.55 if metal else 0.8))
			elif not metal and r < 0.95 and rng.randf() < 0.08:
				c = Color(0.18, 0.14, 0.10, 0.6)          # flecks of thrown dirt
			img.set_pixel(px, py, c)
	return ImageTexture.create_from_image(img)


## A shot's flash and crack at `at` (yours, or another player's).
func pistol_fx(at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 6.0
	l.omni_range = 6.0
	add_child(l)
	l.global_position = at
	get_tree().create_timer(0.05).timeout.connect(l.queue_free)
	# the flash itself: a small bright star of flame for a frame or three
	var fm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 6
	sm.rings = 3
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.85, 0.45)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.7, 0.3)
	fmat.emission_energy_multiplier = 4.0
	sm.material = fmat
	fm.mesh = sm
	fm.scale = Vector3(1.0, 1.0, 2.2)
	add_child(fm)
	fm.global_position = at
	get_tree().create_timer(0.045).timeout.connect(fm.queue_free)
	if _shot_wav == null:
		_shot_wav = _make_shot()
	var ap := AudioStreamPlayer3D.new()
	ap.stream = _shot_wav
	ap.unit_size = 18.0
	ap.max_db = 6.0
	ap.volume_db = 2.0
	ap.pitch_scale = randf_range(0.95, 1.05)
	add_child(ap)
	ap.global_position = at
	ap.play()
	ap.finished.connect(ap.queue_free)


## A pistol report: a sharp crack, a low thump under it, and the slap back
## off the ground, all made here (22 kHz, half a second).
func _make_shot() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.5)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var lp := 0.0
	for i in range(n):
		var t := float(i) / float(rate)
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.35
		var crack := noise * exp(-t * 90.0)
		var body := lp * exp(-t * 14.0) * 0.8
		var thump := sin(TAU * 90.0 * t) * exp(-t * 25.0) * 0.7
		var echo := 0.0
		if t > 0.09:
			echo = lp * exp(-(t - 0.09) * 18.0) * 0.25
		var v := clampf((crack + body + thump + echo) * 0.9, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Dirt kicked up where a round lands (or grit off a machine).
func _dirt_puff(at: Vector3, col: Color = Color(0.42, 0.36, 0.28)) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 14
	p.lifetime = 0.7
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.07
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	bm.material = m
	p.mesh = bm
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


## Co-op: how hard each thing in hand hits (a share of a full health bar).
const TOOL_HIT := {"pick": 0.45, "shovel": 0.3, "rail": 0.35, "timber": 0.25, "gold_pan": 0.12, "bottle": 0.15, "ladder": 0.2}
var _swing_cd := 0.0


## Swing what's in your hand at another player.
func _tool_swing(vic: int) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now < _swing_cd:
		return
	_swing_cd = now + 0.9
	var tool: String = inv.in_hand()
	if not (walker.model.has_method("one_shot") and walker.model.one_shot("swing", 1.5)) and walker.model.has_method("work_motion"):
		walker.model.work_motion("pick" if tool != "shovel" else "dig")
	net.swings += 1
	jolt(0.5)
	var dmg: float = float(TOOL_HIT.get(tool, 0.2)) * randf_range(0.85, 1.15)
	var at: Vector3 = net.player_pos(vic)
	if gore != null and Game.gore:
		gore.burst(at + Vector3(0, 1.3, 0), at - walker.global_position, 0.35)
	var cut := "limb" if (tool in ["pick", "rail", "shovel"] and randf() < 0.22) else ""
	var who: String = net.hit_player(vic, dmg, inv.item_name(tool).to_lower(), walker.global_position, cut)
	if who != "":
		hud.push_message(who, 2.5)


## Co-op: someone hit you with something. `from` is where they stood;
## `cut` "head" (a kill shot), "limb" (an arm or leg comes off) or "".
func take_hit(dmg: float, tool: String, from: Vector3, who: String, cut: String = "") -> void:
	if not on_foot or _foot_down or walker == null:
		return
	var away: Vector3 = walker.global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	if cut == "head":
		_lose_part("head", away * 3.0 + Vector3(0, 2.0, 0))
		if gore != null:
			gore.burst(walker.global_position + Vector3(0, 1.6, 0), away, 0.8)
		hud.push_message("%s shot you in the head." % who, 12.0)
		return
	walker.health = maxf(walker.health - dmg, 0.0)
	jolt(0.8)
	if gore != null and Game.gore:
		gore.burst(walker.global_position + Vector3(0, 1.3, 0), away, 0.5)
	if walker.health > 0.0:
		if cut == "limb":
			_lose_part(["arm_l", "arm_r", "leg_l", "leg_r"].pick_random(), away * 3.0 + Vector3(0, 2.0, 0))
		elif tool != "pistol":
			walker.place(walker.global_position + away * 0.6, walker.yaw)     # knocked back a step
		hits_taken += 1
		if walker.model.has_method("one_shot"):
			walker.model.one_shot("hit_react", 1.6)
		hud.push_message("%s %s you%s." % [who, "shot" if tool == "pistol" else "hit", "" if tool == "pistol" else " with the " + tool], 3.0)
		return
	_die_in_pieces(away * 2.5 + Vector3(0, 1.5, 0), 0.55,
		"%s did you in with the %s. Open the menu to start again from the last airstrip." % [who, tool])


## A machine's bounding box in its own frame (meshes only, once).
func _local_box(v: Node3D) -> AABB:
	var inv: Transform3D = v.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	var stack: Array = [v]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is VisualInstance3D and not (n is Decal) and not (n is Light3D) and not (n is GPUParticles3D) and not (n is CPUParticles3D):
			var vi := n as VisualInstance3D
			var a: AABB = (inv * vi.global_transform) * vi.get_aabb()
			if a.size.length() > 30.0:
				continue
			out = a if first else out.merge(a)
			first = false
	if first:
		out = AABB(Vector3(-1.2, 0, -2.5), Vector3(2.4, 2.0, 5.0))
	return out


func _on_landed(info: Dictionary) -> void:
	jobs.on_landed(info)
	var sink_fpm := int(float(info["sink"]) * 196.85)
	var verdict := "Greased it."
	if sink_fpm > 420:
		verdict = "That was a hard one."
	elif sink_fpm > 260:
		verdict = "Firm."
	elif sink_fpm > 130:
		verdict = "Nice landing."
	var where := "off the strip"
	var k: int = info["strip"]
	if k >= 0:
		where = "at " + String(world.terrain.strips[k]["name"])
		Game.last_strip = k
		Game.save_settings()
	var text := "Down %s. Touchdown %d ft/min, stopped in %d m. %s" % [where, sink_fpm, int(info["roll"]), verdict]
	if plane.is_damaged():
		text += " Check the damage list."
	if int(info["bounces"]) > 1:
		text += " (%d bounces)" % int(info["bounces"])
	hud.push_message(text, 9.0)


func _reset_to_last_strip() -> void:
	if gore != null:
		gore.clear_bodies()
		gore.restore_live(walker.model)
	walker.model.visible = true
	walker.model.rotation = Vector3.ZERO
	walker.model.position = Vector3.ZERO
	if walker.dead_by_prop:
		walker.dead_by_prop = false
		walker.model.rotation = Vector3.ZERO
		walker.model.position = Vector3.ZERO
		walker.health = 1.0
		hud.red_flash = 0.0
	if on_foot:
		_get_in(true)
	walker.health = maxf(walker.health, 0.6)
	_foot_down = false
	hud.crash_text = ""
	# Recovery and the shop's bill: you can go into debt, but it has to be paid off.
	var bill: int = plane.repair_cost()
	if bill > 0 and not Game.free_repairs and not Game.sandbox:
		jobs.money -= bill
		jobs.save_career()
		hud.push_message("Recovery and repairs: $%d.%s" % [bill, "  You're in debt." if jobs.money < 0 else ""], 8.0)
	plane.place_on_strip(clampi(Game.last_strip, 0, world.terrain.strips.size() - 1))
	jobs.restow()
	_chase_yaw = _plane_yaw()
	_orbit = Vector2.ZERO
	_update_camera(1.0, true)


# ------------------------------------------------------------------------------
#  Input
# ------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	# F9 anywhere (flying, on foot, driving, a menu open): record the frame timing (87)
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_F9 and hud != null:
		_jit = []
		_jit_on = true
		_jit_last = 0
		_jit_t0 = Time.get_ticks_usec()
		_jit_pf = Engine.get_physics_frames()
		hud.push_message("Recording the frame timing for 15 s - keep playing as you were when it jittered.", 4.0)
		get_viewport().set_input_as_handled()
		return
	# a click in the game window takes the mouse back
	if _mouse_free and event is InputEventMouseButton and event.pressed and _app_focused:
		_mouse_free = false


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_fly:
		return

	if event.is_action_pressed("controls") and net.is_online():
		net.controls_key()
		return
	if event.is_action_pressed("lights") and not on_foot:
		var any_off := false
		for k in plane.lights.keys():
			if not bool(plane.lights[k]):
				any_off = true
		for k in plane.lights.keys():
			plane.lights[k] = any_off
		hud.push_message("Outside lights %s." % ("ON: nav, beacon, strobes, landing and taxi" if any_off else "OFF") + ("" if plane.engine.master else "  (The battery master is off: no power.)"), 3.0)
		return
	if event.is_action_pressed("smoke") and camp != null and Game.SMOKING:
		camp.light_up()
		return
	# LB in the plane or a machine: the quick menu (on foot LB is the backpack)
	if event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_LEFT_SHOULDER \
			and (not on_foot or driving != null) and not menu.is_open:
		menu.open("quick")
		return
	if event.is_action_pressed("get_out") and net.riding != 0:
		_stop_riding()
		return
	if event.is_action_pressed("get_out") and driving != null:
		_get_off_forklift()
		return
	if event.is_action_pressed("get_out"):
		if event is InputEventJoypadButton and not on_foot:
			_exit_hold = 0.001      # getting OUT on a controller: hold it (see _process)
		elif event is InputEventJoypadButton and on_foot and driving == null and not walker.near_door() \
				and (net == null or net.plane_at_door(walker.global_position) == 0):
			_pad_sprint = not _pad_sprint       # away from the plane's door: L3 runs
		else:
			_toggle_foot()
		return
	if event.is_action_released("get_out"):
		_exit_hold = 0.0
	if on_foot and _foot_input(event):
		return
	if on_foot:
		# On foot or driving a machine, the plane's own keys (starter, auto
		# start, mags, flaps...) must not reach the plane parked somewhere else.
		for pa in PLANE_ONLY:
			if event.is_action(pa):
				return
	if seated.has_method("gesture"):
		for a in ["master", "alternator", "mags", "primer", "fuel_selector", "carb_heat", "cowl_flaps", "engine_auto"]:
			if event.is_action_pressed(a):
				seated.gesture("switch_low" if a != "primer" else "switch_high")
	if event.is_action_pressed("jobs") and not on_foot and skydive.ready_text() != "-" and not plane.on_ground:
		if skydive.can_jump():
			skydive.jump()
		else:
			hud.push_message(skydive.ready_text(), 4.0)
		return
	if event.is_action_pressed("jobs"):
		menu.open("jobs")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu"):
		menu.open("main")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera"):
		_set_cockpit(not cockpit)
	elif event.is_action_pressed("help"):
		if driving != null:
			# the long how-to-drive-it line each machine shows getting in
			Game.machine_hints = not Game.machine_hints
			Game.save_settings()
			hud.push_message("Machine control tips %s (%s toggles them)." % ["ON" if Game.machine_hints else "OFF", Game.hint("help")], 3.0)
		elif on_foot:
			hud.foot_keys = not hud.foot_keys
		else:
			hud.show_help = not hud.show_help
	elif event.is_action_pressed("map"):
		# The 3D relief chart is set aside for now (Dave, DESIGN_NOTES 170):
		# M is the flat chart with the "around you" close-up beside it.
		topo.visible = false
		hud.show_map = not hud.show_map
	elif event.is_action_pressed("next_target"):
		var count: int = world.terrain.strips.size()
		hud.target_strip += 1
		if hud.target_strip >= count:
			hud.target_strip = -1
		if hud.target_strip >= 0:
			hud.push_message("Destination: %s" % world.terrain.strips[hud.target_strip]["name"], 3.0)
		else:
			hud.push_message("Destination cleared", 3.0)
	elif event.is_action_pressed("reset"):
		_reset_to_last_strip()
	elif event.is_action_pressed("confirm"):
		if plane.is_crashed:
			_reset_to_last_strip()
	elif event.is_action_pressed("engine_auto"):
		plane.toggle_auto_sequence()
	elif event.is_action_pressed("master"):
		plane.engine.master = not plane.engine.master
		hud.push_message("Battery master %s" % ("ON" if plane.engine.master else "OFF"), 2.0)
	elif event.is_action_pressed("alternator"):
		plane.engine.alternator = not plane.engine.alternator
		hud.push_message("Alternator %s" % ("ON" if plane.engine.alternator else "OFF"), 2.0)
	elif event.is_action_pressed("mags"):
		plane.engine.mags = (plane.engine.mags + 1) % 4
		hud.push_message("Magnetos %s" % EngineScript.MAG_NAMES[plane.engine.mags], 2.0)
	elif event.is_action_pressed("starter"):
		plane.engine.mags = EngineScript.MAGS_START
	elif event.is_action_released("starter"):
		if plane.engine.mags == EngineScript.MAGS_START:
			plane.engine.mags = EngineScript.MAGS_BOTH
	elif event.is_action_pressed("primer"):
		if plane.engine.running:
			hud.push_message("Priming does nothing with the engine running.", 2.0)
		else:
			plane.engine.prime += 1.0
			hud.push_message("Primer: %d strokes" % int(round(plane.engine.prime)), 2.0)
	elif event.is_action_pressed("fuel_selector"):
		plane.engine.fuel_selector = (plane.engine.fuel_selector + 1) % 4
		hud.push_message("Fuel selector %s" % EngineScript.FUEL_NAMES[plane.engine.fuel_selector], 2.0)
	elif event.is_action_pressed("carb_heat"):
		plane.engine.carb_heat = not plane.engine.carb_heat
		hud.push_message("Carb heat %s" % ("ON" if plane.engine.carb_heat else "OFF"), 2.0)
	elif event.is_action_pressed("cowl_flaps"):
		var c: float = plane.engine.cowl_flaps
		plane.engine.cowl_flaps = 0.5 if c < 0.25 else (1.0 if c < 0.75 else 0.0)
		hud.push_message("Cowl flaps %s" % ["CLOSED", "HALF", "OPEN"][int(round(plane.engine.cowl_flaps * 2.0))], 2.0)
	elif event.is_action_pressed("feather"):
		var fm: String = plane.feather()
		if fm != "":
			hud.push_message(fm, 3.0)
	elif event.is_action_pressed("gear"):
		if plane.is_retractable():
			if plane.set_gear(not plane.gear_down):
				hud.push_message("Gear lever %s" % ("DOWN" if plane.gear_down else "UP"), 2.5)
			else:
				hud.push_message("The gear lever won't go up with weight on the wheels.", 3.0)
		elif plane.set_gear(not plane.gear_down):
			if plane.has_skis():
				hud.push_message("Skis %s" % ("DOWN (snow, ice, water)" if plane.gear_down else "UP (on the wheels)"), 3.0)
			else:
				hud.push_message("Wheels %s" % ("DOWN (for land)" if plane.gear_down else "UP (for water)"), 3.0)
		else:
			hud.push_message("Nothing to raise or lower on this plane.", 2.0)
	elif event.is_action_pressed("seat_fwd") or event.is_action_pressed("seat_back"):
		Game.seat_fore = clampf(Game.seat_fore + (0.03 if event.is_action_pressed("seat_fwd") else -0.03), -0.06, 0.25)
		Game.save_settings()
		hud.push_message("Seat %s" % ("forward" if event.is_action_pressed("seat_fwd") else "back"), 1.5)
	elif event.is_action_pressed("seat_up") or event.is_action_pressed("seat_down"):
		Game.seat_height = clampf(Game.seat_height + (0.03 if event.is_action_pressed("seat_up") else -0.03), -0.12, 0.15)
		Game.save_settings()
		hud.push_message("Seat %s" % ("up" if event.is_action_pressed("seat_up") else "down"), 1.5)
	elif event.is_action_pressed("fullscreen"):
		var win := get_window()
		win.mode = Window.MODE_WINDOWED if win.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	elif event.is_action_pressed("flaps_down"):
		if plane.flap_notch < 4:
			plane.flap_notch += 1
			hud.push_message("Flaps %d°" % plane.flap_degrees(), 2.0)
	elif event.is_action_pressed("flaps_up"):
		if plane.flap_notch > 0:
			plane.flap_notch -= 1
			hud.push_message("Flaps %d°" % plane.flap_degrees() if plane.flap_notch > 0 else "Flaps up", 2.0)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if cockpit and mb.button_index == MOUSE_BUTTON_LEFT:
			# Work a switch or lever; on empty space, drag to look around.
			if mb.pressed:
				if not cockpit_ctl.press():
					_dragging = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
			else:
				cockpit_ctl.release()
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if cockpit and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_zoom_hold = mb.pressed          # hold to lean in and read a gauge
			else:
				_dragging = mb.pressed
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
			if cockpit:
				# Over a control the wheel nudges it; elsewhere it zooms the view.
				# Over a control the wheel works it. The view no longer zooms on
				# the wheel: it crept out to 80 deg and felt like sliding back
				# in the seat. Hold the right button to zoom instead.
				cockpit_ctl.wheel(1 if up else -1)
			elif up:
				_chase_dist = maxf(_chase_dist * 0.9, 9.0)
			else:
				_chase_dist = minf(_chase_dist * 1.1, 70.0)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if cockpit and cockpit_ctl.active >= 0:
			cockpit_ctl.drag(mm.relative)
		elif cockpit and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var kz := _cockpit_fov_now / 72.0
			_orbit.x -= mm.relative.x * 0.0035 * Game.look_speed * kz
			_orbit.y = clampf(_orbit.y - mm.relative.y * 0.003 * Game.look_speed * kz, -1.2, 1.3)
			_orbit_idle = 0.0
			_mouse_looked = true
		elif _dragging:
			var k := _cockpit_fov / 72.0 if cockpit else 1.0
			_orbit.x -= mm.relative.x * 0.006 * k
			_orbit.y = clampf(_orbit.y - mm.relative.y * 0.005 * k, -1.2, 1.3)
			_orbit_idle = 0.0
			_mouse_looked = true


# ------------------------------------------------------------------------------
#  On foot
# ------------------------------------------------------------------------------
const PLANE_ONLY := ["flaps_down", "flaps_up", "engine_auto", "master", "alternator", "mags", "starter",
	"primer", "fuel_selector", "carb_heat", "cowl_flaps", "seat_up", "seat_down", "seat_fwd", "seat_back", "gear", "trim_up", "trim_down"]


## Input that means something different on foot. Returns true if used.
var _saw_tree := {}
var _saw_target := {}
var _saw_t := 0.0
## A tree lying on the ground in reach (cut, pushed over, burnt): buck it
## into lengths and load the logs.
var _down_log := {}
var _buck_target := {}
var _buck_t := 0.0
var logs_cut := 0
var _fire_told := 0.0


func _foot_input(event: InputEvent) -> bool:
	if driving != null:
		if event.is_action_pressed("interact"):
			if driving.has_method("tow_toggle"):
				hud.push_message(driving.tow_toggle(), 4.0)
				return true
			if driving.has_method("swap_attachment"):
				hud.push_message(driving.swap_attachment(), 3.0)
				return true
			if driving.has_method("truck_action"):
				hud.push_message(driving.truck_action(), 4.0)
				return true
			if driving.has_method("blade_toggle"):
				hud.push_message(driving.blade_toggle(), 3.5)
				return true
			if driving.has_method("machine_action"):
				hud.push_message(driving.machine_action(), 4.0)
				return true
			if driving.has_method("dig_or_dump"):
				if driving.levers:
					return true
				driving.dig_or_dump()
				return true
			var msg: String = driving.fork_action()
			if msg != "":
				hud.push_message(msg, 3.0)
			return true
		if driving.has_method("engine_toggle") and event.is_action_pressed("engine_auto"):
			if vdamage != null and vdamage.dead(_veh_key(driving)) and driving.get("engine_on") != true:
				hud.push_message("It turns over but won't catch: the engine's wrecked. The workshop can fix it (menu, Workshop).", 4.0)
				return true
			hud.push_message(driving.engine_toggle(), 4.0)
			return true
		if driving.has_method("diff_lock_toggle") and event.is_action_pressed("diff_lock"):
			hud.push_message(driving.diff_lock_toggle(), 3.0)
			return true
		if driving.has_method("four_wd_toggle") and event.is_action_pressed("four_wd"):
			hud.push_message(driving.four_wd_toggle(), 2.5)
			return true
		if driving.has_method("lights_toggle") and event.is_action_pressed("lights"):
			hud.push_message(driving.lights_toggle(), 2.0)
			return true
		if driving.has_method("blinker") and (event.is_action_pressed("brake_left") or event.is_action_pressed("brake_right")):
			hud.push_message(driving.blinker(-1 if event.is_action_pressed("brake_left") else 1), 1.5)
			return true
		if driving.has_method("toggle_valve") and event is InputEventKey and event.pressed and not event.echo:
			var vk: int = (event as InputEventKey).physical_keycode
			if vk >= KEY_1 and vk <= KEY_5:
				hud.push_message(driving.toggle_valve(vk - KEY_1), 2.5)
				return true
			if vk == KEY_6 and driving.has_method("toggle_pto"):
				hud.push_message(driving.toggle_pto(), 3.0)
				return true
		if event.is_action_pressed("door") and driving.has_method("levers_step"):
			driving.cycle_mode()
			_lever_hint(driving)
			return true
		if event.is_action_pressed("camera"):
			walker.first_person = not walker.first_person
			return true
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mm2 := event as InputEventMouseMotion
			walker.look.x -= mm2.relative.x * 0.0035 * Game.look_speed
			walker.look.y = clampf(walker.look.y - mm2.relative.y * 0.003 * Game.look_speed, -1.35, 1.25)
			return true
		return event.is_action("interact") or event.is_action("door") or event.is_action("build")
	if event.is_action_pressed("interact") and cargo._target.is_empty() and not _part_target.is_empty():
		var host: Node = _part_target[0]
		hud.push_message(host.part_act(String(_part_target[1]), inv), 4.0)
		if host.has_method("parts_changed"):
			host.parts_changed()
		return true
	if event.is_action_pressed("interact") and cargo._target.is_empty() and _near_fork != null:
		_get_on_forklift(_near_fork)
		return true
	# Dynamite in hand (DESIGN_NOTES 176): E lights it - set against a face
	# right in front of you, otherwise thrown where you're looking
	if event.is_action_pressed("interact") and inv.in_hand() == "dynamite" and cargo._target.is_empty() and dynamite != null:
		_light_dynamite()
		return true
	# The pistol (DESIGN_NOTES 180): E fires where you're looking.
	if event.is_action_pressed("interact") and inv.in_hand() == "pistol" and cargo._target.is_empty() and _ground_item.is_empty() and not _foot_down:
		_fire_pistol()
		return true
	# Co-op scrapping (DESIGN_NOTES 179): a tool in hand and another player
	# right in front of you - E swings it at them.
	if event.is_action_pressed("interact") and net.is_online() and TOOL_HIT.has(inv.in_hand()) and not _foot_down:
		var fwd_h: Vector3 = Basis(Vector3.UP, walker.yaw) * Vector3.FORWARD
		var vic: int = net.player_in_reach(walker.global_position, fwd_h)
		if vic != 0:
			_tool_swing(vic)
			return true
	if event.is_action_pressed("interact") and cargo._target.is_empty() and not _ground_item.is_empty():
		hud.push_message(inv.pick_up(_ground_item), 4.0)
		_ground_item = {}
		return true
	if event.is_action_pressed("interact") and cargo._target.is_empty() and _near_fork == null and not _near_sale.is_empty():
		var sn: Node3D = _near_sale["node"]
		var t2: String = _near_sale["type"]
		var err4: String = fleet.buy_parked(sn, _sale_price(t2))
		if err4 != "":
			hud.push_message(err4, 3.5)
		else:
			hud.push_message("She's yours: %s. Climb in when you're ready." % plane.reg, 5.0)
			world.remove_sale(_near_sale)
			_near_sale = {}
		return true
	if event.is_action_pressed("interact") and cargo._target.is_empty() and not _pros_target.is_empty() and service.part == "" and _switch < 0 and camp.prompt == "":
		var act := String(_pros_target[0])
		if act in ["dig", "dig_rock", "tunnel", "tunnel_pan", "sink", "vein"] and walker.model.has_method("work_motion"):
			if walker.model.working():
				return true                 # one shovelful (or swing) at a time
			# a shovelful, or a pick swing at rock (DESIGN_NOTES 120)
			walker.model.work_motion("pick" if (act == "dig_rock" or inv.in_hand() == "pick") else "dig")
			jolt(0.45 if (act == "dig_rock" or inv.in_hand() == "pick") else 0.2)     # the blade biting in
		var m: String = prospect.act(act, walker.global_position, walker.global_transform * Vector3(0, 0, -0.9))
		if m != "":
			hud.push_message(m, 4.0)
		return true
	if event.is_action_pressed("interact") and cargo._target.is_empty() and driving == null and plane.is_crashed and hazards != null and hazards.sparking() and walker.near_door():
		hud.push_message(hazards.reach_in_master_off(), 4.0)
		return true
	if event.is_action_pressed("interact") and cargo._target.is_empty() and _hdoor != null and driving == null:
		hud.push_message(_hdoor.toggle(), 3.0)
		return true
	if event.is_action_pressed("interact") and cargo._target.is_empty() and _switch >= 0:
		hud.push_message(blights.toggle(_switch), 2.0)
		return true
	if event.is_action_pressed("interact") and cargo._target.is_empty() and service.part != "":
		menu.engine_part = service.part
		service.result = ""
		menu.open("engine")
		return true
	if event.is_action_pressed("door") and service.near_nose() and cargo._door() == "":
		hud.push_message(service.toggle_cowl(), 3.0)
		return true
	if event.is_action_pressed("interact") and cargo._target.is_empty() and camp.interact():
		return true
	if event.is_action_pressed("interact") and on_foot and cargo._target.is_empty() and world.structures != null and world.structures.interact():
		return true
	if event.is_action_pressed("interact") and on_foot and driving == null and cargo._target.is_empty() and rails != null and rails.interact(Basis(Vector3.UP, walker.yaw) * Vector3.FORWARD):
		return true
	if event.is_action_pressed("interact") and cargo._target.is_empty() and not _saw_tree.is_empty() and _saw_t <= 0.0:
		_saw_target = _saw_tree
		_saw_t = 2.5 + float(_saw_tree["height"]) * 0.08
		return true
	if event.is_action_pressed("interact") and cargo._target.is_empty() and not _down_log.is_empty() and _buck_t <= 0.0:
		_buck_target = _down_log
		_buck_t = 1.8 + float(_down_log["height"]) * 0.1
		return true
	if event.is_action_pressed("interact") and cargo._target.is_empty() and net.is_online():
		var other: int = net.plane_at_door(walker.global_position)
		if other != 0:
			_start_riding(other)
			return true
	if event.is_action_pressed("interact"):
		cargo.interact()
		return true
	if event.is_action_pressed("door") and pickup != null and driving == null and pickup.has_method("hood_toggle"):
		var pl: Vector3 = pickup.global_transform.affine_inverse() * walker.global_position
		if pl.z < -2.3 and pl.z > -4.0 and absf(pl.x) < 1.4:
			hud.push_message(pickup.hood_toggle(), 2.0)
			return true
		if pl.z > 3.1 and pl.z < 4.6 and absf(pl.x) < 1.3:
			hud.push_message(pickup.tailgate_toggle(), 2.0)
			return true
	if event.is_action_pressed("door") and water_truck != null and water_truck.hose_out:
		hud.push_message(water_truck.reel_in(), 2.5)
		return true
	if event.is_action_pressed("door") and fuel_truck != null and fuel_truck.hose_out:
		fuel_truck.delivering = {}
		hud.push_message(fuel_truck.reel_in(), 2.5)
		return true
	if event.is_action_pressed("door") and crafting != null and crafting.near(walker.global_position):
		hud.push_message(crafting.next_recipe(), 4.0)
		return true
	if event.is_action_pressed("door") and cargo._door() == "":
		var tl: String = prospect.take_ladder(walker.global_position)
		if tl != "":
			hud.push_message(tl, 3.0)
			return true
		var tp: String = prospect.take_pump(walker.global_position)
		if tp != "":
			hud.push_message(tp, 3.0)
			return true
		if power != null and inv.in_hand() == "":
			var tg: String = power.take_generator(walker.global_position)
			if tg != "":
				hud.push_message(tg, 3.0)
				return true
	if event.is_action_pressed("door") and inv.in_hand() != "" and cargo._door() == "":
		var dp: Vector3 = walker.global_transform * Vector3(0.5, 0, -0.7)
		dp.y = walker.global_position.y
		hud.push_message(inv.drop_active(dp, walker.yaw), 3.0)
		return true
	# Test-bed shortcuts: F2 the tool spot by the hangar, F3 the water truck,
	# F4 the wet flats by the creek (shallow water table).
	if event is InputEventKey and event.pressed and not event.echo:
		var fk: int = (event as InputEventKey).physical_keycode
		var to := Vector3.INF
		if fk == KEY_F2:
			to = Vector3(-44.5, 0, -74.5)
		elif fk == KEY_F3 and water_truck != null:
			to = water_truck.step_out_point() + water_truck.global_transform.basis.x * -1.0
		elif fk == KEY_F4:
			to = Vector3(-24.0, 0, 104.0)
		elif fk == KEY_F6 and pickup != null:
			to = pickup.step_out_point()
		elif fk == KEY_F7 and loader != null:
			to = loader.step_out_point()
		elif fk == KEY_F8 and fuel_truck != null:
			to = fuel_truck.step_out_point() + fuel_truck.global_transform.basis.x * -1.0
		if to != Vector3.INF:
			walker.place(to, PI)
			hud.push_message("Moved to x %d z %d." % [int(to.x), int(to.z)], 2.0)
			return true
	# Hotbar: 1-8 on the keyboard, LB / RB on a pad, the wheel in first person.
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = (event as InputEventKey).physical_keycode
		if kc >= KEY_1 and kc <= KEY_8:
			inv.select(kc - KEY_1)
			return true
	if event is InputEventJoypadButton and event.pressed:
		var bi: int = (event as InputEventJoypadButton).button_index
		# (DESIGN_NOTES 183) a survival-shooter layout on foot: bumpers flip
		# through the hotbar, View opens the backpack, D-pad left the chart
		if bi == JOY_BUTTON_LEFT_SHOULDER or bi == JOY_BUTTON_RIGHT_SHOULDER:
			inv.cycle(-1 if bi == JOY_BUTTON_LEFT_SHOULDER else 1)
			return true
		if bi == JOY_BUTTON_BACK:
			inv_ui.toggle()
			return true
		if bi == JOY_BUTTON_DPAD_LEFT:
			var ma := InputEventAction.new()
			ma.action = "map"
			ma.pressed = true
			Input.parse_input_event(ma)
			return true
		# on foot the pad's D-pad and right stick click do the keyboard-only jobs
		if bi == JOY_BUTTON_DPAD_DOWN:
			menu.open("build")
			return true
		if bi == JOY_BUTTON_DPAD_UP:
			var la := InputEventAction.new()
			la.action = "lights"
			la.pressed = true
			return _foot_input(la)
		if bi == JOY_BUTTON_RIGHT_STICK:
			hud.foot_keys = not hud.foot_keys
			return true
	if event is InputEventMouseButton and walker.first_person and (event as InputEventMouseButton).pressed:
		var wb: int = (event as InputEventMouseButton).button_index
		if wb == MOUSE_BUTTON_WHEEL_UP or wb == MOUSE_BUTTON_WHEEL_DOWN:
			inv.cycle(-1 if wb == MOUSE_BUTTON_WHEEL_UP else 1)
			return true
	if event.is_action_pressed("inventory"):
		inv_ui.toggle()
		return true
	if event.is_action_pressed("door"):
		cargo.toggle_door()
		return true
	if event.is_action_pressed("build"):
		menu.open("build")
		return true
	if event.is_action_pressed("lights"):
		if not inv.has("headlamp"):
			hud.push_message("No headlamp on you.", 2.0)
			return true
		_headlamp_on = not _headlamp_on
		hud.push_message("Headlamp on." if _headlamp_on else "Headlamp off.", 1.5)
		return true
	if event.is_action("interact"):
		return true
	if event.is_action_pressed("camera"):
		walker.first_person = not walker.first_person
		return true
	for a in PLANE_ONLY:
		if event.is_action(a):
			return true
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		walker.look.x -= mm.relative.x * 0.0035 * Game.look_speed
		walker.look.y = clampf(walker.look.y - mm.relative.y * 0.003 * Game.look_speed * (-1.0 if Game.invert_pitch else 1.0), -1.35, 1.25)
		return true
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			walker.cam_dist = maxf(walker.cam_dist * 0.9, 1.6)
			return true
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			walker.cam_dist = minf(walker.cam_dist * 1.1, 9.0)
			return true
	return false


func _toggle_foot() -> void:
	if on_foot:
		_get_in(false)
	else:
		_get_out()


## A session starts on your feet inside the home base office (DESIGN_NOTES
## 147): the stove ticking, the radio on the desk, the plane out on the
## strip. If the office has burnt down, by the hangar instead.
func _start_indoors() -> void:
	if Game.last_strip != 0 or world.structures == null or plane == null or plane.is_crashed:
		return
	var sts: Node3D = world.structures
	var id := "office" if sts.items.has("office") and not bool(sts.items["office"]["burnt"]) else ("bunkhouse" if sts.items.has("bunkhouse") and not bool(sts.items["bunkhouse"]["burnt"]) else "")
	_get_out()
	if id == "":
		return
	var xf: Transform3D = sts.items[id]["xf"]
	var p: Vector3 = xf * Vector3(-0.6, 0.2, -1.2)
	var to: Vector3 = xf * (sts.items[id]["stove"]["at"] as Vector3)
	var dir := to - p
	walker.place(p, atan2(-dir.x, -dir.z))
	hud.push_message("Home base. The stove's going in the office; the plane's out on the strip.", 6.0)


func _get_out() -> void:
	if walker.health <= 0.0 and plane.is_crashed:
		hud.push_message("You didn't survive the crash. Open the menu to start again from the last airstrip.", 5.0)
		return
	if not plane.is_crashed and (not plane.on_ground or plane.ground_speed > 1.0):
		hud.push_message("Stop the plane before you get out.", 3.0)
		return
	on_foot = true
	plane.throttle = 0.0 if not plane.engine_running else plane.throttle
	var door: Vector3 = plane.global_transform * (PlaneTypes.spec(plane.plane_type).get("door", Vector3(-1.5, 0.0, -0.15)) as Vector3)
	var facing := _plane_yaw() + PI * 0.5
	walker.visible = true
	if plane.plane_type == "dc3" and not plane.is_crashed:
		# Up out of the captain's seat into the gap between the seats, facing
		# back toward the cabin and the cargo door.
		walker.place_inside(Vector3(0.0, 0.0, -5.15), _plane_yaw() + PI)
	else:
		walker.place(door, facing)
	seated.visible = false
	_set_cockpit(false)
	hud.walker = walker
	hud.push_message("%s walk   %s run   %s jump   %s first / third person   %s get back in" % [
		hud._keys(["pitch_down", "roll_left", "pitch_up", "roll_right"]), Game.hint("throttle_up"), Game.hint("brake"), Game.hint("camera"), Game.hint("get_out")], 8.0)


## Climb back in (from the pilot's door unless `anywhere`).
func _get_in(anywhere: bool) -> void:
	if anywhere and driving != null:
		_get_off_forklift()      # recovered / docked / tutorial from inside a machine
	if tug != null and tug.towing and tug.tow_plane == plane and (anywhere or walker.near_door()):
		tug.speed = 0.0
		hud.push_message(tug.tow_toggle(), 3.0)      # you can't fly it on the bar
	if not anywhere and not walker.near_door():
		var where := "Walk to the pilot's door, on the left side of the cabin, to get in."
		if plane.plane_type == "dc3":
			where = "Walk up to the flight deck and the captain's seat to get in."
		elif plane.plane_type == "biplane":
			where = "Climb up on the left lower wing root, by the rear cockpit, to get in."
		hud.push_message(where, 3.0)
		return
	cargo.stow_held()
	plane.door_open["cabin"] = false      # you pull the door shut behind you
	var closed_cowl := false
	for ck in ["cowl", "cowl0", "cowl1"]:
		if plane.door_open.get(ck, false):
			plane.door_open[ck] = false
			closed_cowl = true
	if closed_cowl:
		hud.push_message("You close and latch the engine covers on the way in.", 3.0)
	on_foot = false
	walker.visible = false
	seated.visible = true
	hud.walker = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_cockpit(true)


## Co-op: climb into another player's plane as a passenger.
func _start_riding(id: int) -> void:
	cargo.stow_held()
	net.start_riding(id)
	on_foot = false
	walker.visible = false
	hud.walker = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_cockpit(true)


## Out of the other plane, on the right-hand side.
func _stop_riding() -> void:
	var xf: Transform3D = net.ride_transform()
	net.stop_riding()
	on_foot = true
	walker.visible = true
	walker.place(xf * Vector3(1.6, 0.0, -0.15), atan2(-xf.basis.x.x, -xf.basis.x.z))
	_set_cockpit(false)
	hud.walker = walker


func _set_cockpit(on: bool) -> void:
	cockpit = on
	_orbit = Vector2.ZERO
	_mouse_looked = false
	hud.cockpit_mode = on
	hud.tooltip = ""
	var dc3: bool = plane.plane_type == "dc3"
	var tv: Node3D = type_vis.get(plane.plane_type)
	visual.set_cockpit_view(on and not dc3 and tv == null)
	for t in type_vis.keys():
		(type_vis[t] as Node3D).set_cockpit_view(on and t == plane.plane_type)
	if dc3_cockpit != null:
		dc3_cockpit.set_active(on and dc3)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _physics_process(delta: float) -> void:
	if not _ready_to_fly or plane == null or (not _test.is_empty() and not _test_keys):
		return
	_gear_warning(delta)
	_plane_in_fire(delta)
	_update_movers()
	if net.riding != 0:
		# Riding in someone else's plane: ours waits where we left it.
		plane.in_pitch = 0.0
		plane.in_roll = 0.0
		plane.in_yaw = 0.0
		plane.brake = 1.0
		plane.throttle = 0.0
		return
	if on_foot:
		# Parking brake on, hands off the controls; drive the pilot instead.
		plane.in_pitch = 0.0
		plane.in_roll = 0.0
		plane.in_yaw = 0.0
		plane.brake = 1.0
		var move := Vector2(Input.get_axis("roll_left", "roll_right"), Input.get_axis("pitch_up", "pitch_down"))
		var look_in := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if inv_ui != null and inv_ui.is_open:
			move = Vector2.ZERO
			look_in = Vector2.ZERO
		if driving != null and driving.get("levers") == true:
			look_in = Vector2.ZERO       # the right stick works the boom and bucket
		elif driving != null and _implement_on_stick(driving):
			look_in.y = 0.0              # right stick up / down works the forks, arms, blade or boom
		walker.look.x -= look_in.x * 2.4 * Game.look_speed * delta
		walker.look.y = clampf(walker.look.y - look_in.y * 1.8 * Game.look_speed * delta, -1.35, 1.25)
		if driving != null:
			_drive_forklift(delta, move)
			return
		move = camp.walk_wobble(move)
		if walker.dead_by_prop or walker.health <= 0.0:
			move = Vector2.ZERO          # he's down
		walker.load_kg = cargo.carried_load() + maxf(inv.weight() - 12.0, 0.0)
		# run: Shift on the keyboard; on a controller the left stick click
		# toggles it (RT is the use trigger on foot) and it ends when you stop
		var kb_run: bool = Input.is_action_pressed("throttle_up") and _pad_rt() < 0.2
		if move.length() < 0.2:
			_pad_sprint = false
		walker.step(delta, move, kb_run or _pad_sprint, Input.is_action_just_pressed("brake"))
		_rt_use()
		if builds.in_cabin(walker.global_position):
			walker.warm_in_cabin(delta * 6.0, true)
		if walker.health <= 0.0 and not _foot_down:
			_foot_down = true
			hud.push_message("You didn't make it out here. Open the menu to start again from the last airstrip.", 10.0)
		return
	walker.warm_in_cabin(delta, plane.engine_running)
	if plane.on_fire and net.riding == 0:
		# still strapped in a burning plane: it hurts, get out
		walker.health = maxf(float(walker.health) - 0.05 * delta * float(plane.fire_strength), 0.0)
		if walker.health <= 0.0 and not _foot_down:
			_foot_down = true
			hud.push_message("You didn't get out in time. Open the menu to start again from the last airstrip.", 10.0)
	if plane.is_crashed:
		return
	if hud.show_help and (plane.throttle > 0.3 or plane.airborne):
		hud.show_help = false
	var pitch := Input.get_axis("pitch_down", "pitch_up")
	if Game.invert_pitch:
		pitch = -pitch
	var roll := Input.get_axis("roll_left", "roll_right")
	var yaw := Input.get_axis("yaw_left", "yaw_right")
	if Input.is_action_pressed("free_look") and Game.using_gamepad:
		yaw = 0.0           # the right stick is looking around, not on the rudder
	if Game.using_gamepad:
		# A curve around the centre makes small corrections easier; the sensitivity
		# setting makes it gentler or sharper.
		var expo := clampf(2.6 - Game.stick_sensitivity, 1.0, 2.2)
		pitch = signf(pitch) * pow(absf(pitch), expo)
		roll = signf(roll) * pow(absf(roll), expo)
		yaw = signf(yaw) * pow(absf(yaw), maxf(expo - 0.2, 1.0))
	plane.direct_controls = Game.using_gamepad
	# Flight stick and pedals add straight in (calibrated, with their own curve).
	var hz: Node = Game.hotas
	if hz.has_axis("pitch") or hz.has_axis("roll") or hz.has_axis("yaw"):
		pitch = clampf(pitch + hz.value("pitch"), -1.0, 1.0)
		roll = clampf(roll + hz.value("roll"), -1.0, 1.0)
		yaw = clampf(yaw + hz.value("yaw"), -1.0, 1.0)
		if not Game.using_gamepad and Input.get_axis("roll_left", "roll_right") == 0.0 and Input.get_axis("pitch_down", "pitch_up") == 0.0:
			plane.direct_controls = true
	if cockpit and cockpit_ctl.yoke_active:
		# Flying with the mouse on the yoke.
		pitch = cockpit_ctl.yoke_input.y
		roll = cockpit_ctl.yoke_input.x
		plane.direct_controls = true
	var thr := Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down")
	var brk := Input.get_action_strength("brake")
	# Co-op: a passenger we handed the controls to flies instead.
	if net.handed_to != 0 and not net.remote_input.is_empty():
		var ri: Dictionary = net.remote_input
		pitch = float(ri.get("pitch", 0.0))
		roll = float(ri.get("roll", 0.0))
		yaw = float(ri.get("yaw", 0.0))
		thr = float(ri.get("thr", 0.0))
		brk = float(ri.get("brake", 0.0))
		if float(ri.get("lever", -1.0)) >= 0.0:
			plane.throttle = float(ri["lever"])
		plane.direct_controls = true
	var wob: Vector3 = camp.control_wobble()
	plane.in_pitch = clampf(pitch + wob.x, -1.0, 1.0)
	plane.in_roll = clampf(roll + wob.y, -1.0, 1.0)
	plane.in_yaw = clampf(yaw + wob.z, -1.0, 1.0)
	plane.throttle = clampf(plane.throttle + thr * 0.55 * delta, 0.0, 1.0)
	plane.brake = brk
	plane.brake_left = Input.get_action_strength("brake_left")
	plane.brake_right = Input.get_action_strength("brake_right")
	var mix := Input.get_action_strength("mixture_rich") - Input.get_action_strength("mixture_lean")
	if absf(mix) > 0.01:
		plane.engine.mixture = clampf(plane.engine.mixture + mix * 0.35 * delta, 0.0, 1.0)
	var prop := Input.get_action_strength("prop_up") - Input.get_action_strength("prop_down")
	if absf(prop) > 0.01:
		plane.engine.prop_lever = clampf(plane.engine.prop_lever + prop * 0.5 * delta, 0.0, 1.0)
	var trim := Input.get_action_strength("trim_up") - Input.get_action_strength("trim_down")
	plane.trim = clampf(plane.trim + trim * 0.28 * delta, -1.0, 1.0)
	# Levers on the throttle quadrant: the game follows them whenever they move,
	# and the keys can still nudge things in between.
	if hz.lever_moved("throttle"):
		plane.throttle = hz.value("throttle")
	if hz.lever_moved("prop"):
		plane.engine.prop_lever = hz.value("prop")
	if hz.lever_moved("mixture"):
		plane.engine.mixture = hz.value("mixture")
	if hz.lever_moved("trim"):
		plane.trim = hz.value("trim")
	if hz.has_axis("brake_left"):
		plane.brake_left = maxf(plane.brake_left, hz.value("brake_left"))
	if hz.has_axis("brake_right"):
		plane.brake_right = maxf(plane.brake_right, hz.value("brake_right"))


# ------------------------------------------------------------------------------
#  Cameras
# ------------------------------------------------------------------------------
func _plane_yaw() -> float:
	var f: Vector3 = plane.global_transform.basis * Vector3.FORWARD
	return atan2(-f.x, -f.z)


func _process(delta: float) -> void:
	_plane_parts_key()
	if hud != null and world != null and walker != null:      # (set up yet)
		_runover_check(delta)
		_vehicle_trees(delta)
		_goals_tick(delta)
		_weather_tick(delta)
		hud.inset_on = false
		hud.in_machine = driving != null
	_fall_guard(delta)
	if fire != null and on_foot and driving == null and fire.burning_at(walker.global_position):
		walker.health = maxf(walker.health - 0.12 * delta, 0.0)
		walker.warmth = minf(walker.warmth + 0.3 * delta, 1.0)
		if _fire_told <= 0.0:
			_fire_told = 4.0
			hud.push_message("You're in the fire! Get out of it.", 3.0)
	_fire_told -= delta
	_perf_overlay_update()
	if not _ready_to_fly or plane == null:
		return
	_clock += delta
	cargo.on_foot = on_foot
	_sync_shovel()
	_sync_headlamp()
	_sync_ear_muffs()
	# The hose: the nozzle in his hand, aimed where he looks, and he can't
	# walk further than 50 ft from the reel.
	if water_truck != null and water_truck.hose_out:
		if not on_foot or driving != null:
			water_truck.reel_in()
		else:
			var lp: Vector3 = water_truck.hose_leash(walker.global_position)
			if lp.distance_to(walker.global_position) > 0.01:
				walker.global_position = Vector3(lp.x, walker.global_position.y, lp.z)
			var fwd: Vector3 = -cam.global_transform.basis.z
			water_truck.hose_hand = walker.global_position + Vector3(0, 1.15, 0) + Basis(Vector3.UP, walker.yaw) * Vector3(0.25, 0, -0.45)
			water_truck.hose_aim = (fwd + Vector3(0, 0.12, 0)).normalized()
	# the fuel truck's hose: the nozzle in his hand, 50 ft from the reel
	if fuel_truck != null and fuel_truck.hose_out:
		if not on_foot or driving != null:
			fuel_truck.delivering = {}
			fuel_truck.reel_in()
		else:
			var lpf: Vector3 = fuel_truck.hose_leash(walker.global_position)
			if lpf.distance_to(walker.global_position) > 0.01:
				walker.global_position = Vector3(lpf.x, walker.global_position.y, lpf.z)
			# reach up to a wing-root filler when you're under one
			var hand: Vector3 = walker.global_position + Vector3(0, 1.15, 0) + Basis(Vector3.UP, walker.yaw) * Vector3(0.25, 0, -0.45)
			var near: Dictionary = fuel_truck._fill_point_near(hand, 2.4)
			if not near.is_empty():
				var best_q: Vector3 = hand
				var bd := 99.0
				for q in near.get("fills", []):
					if (q as Vector3).distance_to(hand) < bd:
						bd = (q as Vector3).distance_to(hand)
						best_q = q
				hand = hand.lerp(best_q, 0.85)
			fuel_truck.hose_hand = hand
	if pickup != null and driving != pickup:
		pickup.work(delta)             # the engine idles (and is heard) with nobody in it
	for wt in [water_truck, fuel_truck]:
		if wt != null and driving != wt:
			var pm: String = wt.work(delta)
			if pm != "" and on_foot and walker.global_position.distance_to(wt.global_position) < 30.0:
				hud.push_message(pm, 4.0)
	if inv_ui != null:
		var bar: bool = on_foot and driving == null and not menu.is_open
		if bar != inv_ui.visible_bar:
			inv_ui.visible_bar = bar
			inv_ui.queue_redraw()
		if not on_foot and inv_ui.is_open:
			inv_ui.toggle()
	# The water truck's sprays wash the blood off the plane (DESIGN_NOTES 81).
	if water_truck != null and gore != null and not gore.plane_decals.is_empty() and water_truck.engine_on and water_truck._pumping() and float(water_truck.tank_m3) > 0.0:
		var wash_from: Vector3 = water_truck.hose_hand if water_truck.hose_out else water_truck.global_position
		if wash_from.distance_to(plane.global_position) < 14.0:
			if gore.wash_plane() > 0:
				hud.push_message("Hosed the blood off the plane.", 4.0)
	# Chainsaw: a tree right in front of you, hands free.
	_saw_tree = {}
	cargo.extra_prompt = ""
	if on_foot and cargo._target.is_empty() and cargo.holding.is_empty():
		var tr: Dictionary = Flora.tree_near(world.terrain, walker.global_position + Vector3(0, 1.0, 0))
		if not tr.is_empty() and float(tr["dist"]) < float(tr["trunk_r"]) + 1.0:
			_saw_tree = tr
			cargo.extra_prompt = "%s  Fell the tree (chainsaw)" % Game.hint("interact") if _saw_t <= 0.0 else "Cutting..."
	if _saw_t > 0.0:
		_saw_t -= delta
		if _saw_t <= 0.0 and not _saw_target.is_empty():
			var base: Vector3 = _saw_target["base"]
			var away := base - walker.global_position
			away.y = 0.0
			if randf() < 0.1:
				# The hinge tears, or it sits back on the bar: it comes round
				# and down toward the cutter (DESIGN_NOTES 157). Run.
				_tree_coming = _saw_target.duplicate()
				_tree_coming["dir"] = (-away.normalized()).rotated(Vector3.UP, randf_range(-0.6, 0.6))
				_tree_coming["t"] = 1.7
				hud.push_message("CRACK! The hinge let go - it's coming down your way! RUN!", 3.0)
			else:
				_fell_and_check(_saw_target, away.normalized())
				hud.push_message("Timber! Walk along the trunk and %s to buck it up into logs." % Game.hint("interact"), 3.5)
			_saw_target = {}
	if not _tree_coming.is_empty():
		_tree_coming["t"] = float(_tree_coming["t"]) - delta
		if float(_tree_coming["t"]) <= 0.0:
			_fell_and_check(_tree_coming, _tree_coming["dir"])
			_tree_coming = {}
	# Bucking a downed tree: anything lying in reach, hands free.
	_down_log = {}
	if on_foot and _saw_tree.is_empty() and cargo._target.is_empty() and cargo.holding.is_empty() and _saw_t <= 0.0:
		_down_log = Flora.down_near(world.terrain, walker.global_position)
		if not _down_log.is_empty():
			var nlog := _log_count(_down_log)
			if _buck_t > 0.0:
				cargo.extra_prompt = "Bucking..."
			elif bool(_down_log["charred"]):
				cargo.extra_prompt = "%s  Salvage the burnt trunk (+%d log%s: charred outside, sound inside)" % [Game.hint("interact"), nlog, "" if nlog == 1 else "s"]
			else:
				cargo.extra_prompt = "%s  Buck it up into logs (+%d)" % [Game.hint("interact"), nlog]
	if _buck_t > 0.0:
		_buck_t -= delta
		if _buck_t <= 0.0 and not _buck_target.is_empty():
			var bt := _buck_target
			_buck_target = {}
			var bd: Vector3 = bt["dir"]
			world.fell_tree(int(bt["ti"]), int(bt["tj"]), Vector3(bd.x, 1.0, bd.z))     # y +1: hauled off
			var got := _log_count(bt)
			# the lengths lie beside where the trunk was, a pace apart
			var pts: Array = []
			var side := Vector3(-bd.z, 0, bd.x)
			for li in range(got):
				var q: Vector3 = (bt["pos"] as Vector3) + bd * (2.0 + float(li) * 2.6) + side * 0.9
				q.y = world.terrain.ground_level_at(q.x, q.z)
				pts.append(q)
			cargo.add_own_logs(pts)
			hud.push_message("Bucked into %d log%s%s. Pick them up (%s) and carry them to the pickup, the log trailer or the log deck in the tool yard." % [got, "" if got == 1 else "s", " (burnt outside, the heart's good)" if bool(bt["charred"]) else "", Game.hint("interact")], 4.0)
	if on_foot:
		camp.find_target()
		if cargo._target.is_empty() and camp.prompt != "":
			cargo.extra_prompt = camp.prompt
		service.find_target()
		if cargo._target.is_empty() and service.prompt != "":
			cargo.extra_prompt = service.prompt
		if world.structures != null:
			world.structures.find_target()
			if cargo._target.is_empty() and world.structures.prompt != "":
				cargo.extra_prompt = world.structures.prompt
		if rails != null and driving == null:
			rails.find_target()
			if cargo._target.is_empty() and rails.prompt != "":
				cargo.extra_prompt = rails.prompt
		_switch = blights.switch_near(walker.global_position)
		_hdoor = null
		if driving == null:
			for hd in world.hangar_doors:
				if (hd[1] as Vector3).distance_to(walker.global_position + Vector3(0, 1.0, 0)) < 1.4:
					_hdoor = hd[0]
		if cargo._target.is_empty() and plane.is_crashed and hazards != null and hazards.sparking() and walker.near_door():
			cargo.extra_prompt = "%s  Reach in and switch the battery master OFF (it's sparking)" % Game.hint("interact")
		if cargo._target.is_empty() and _hdoor != null:
			cargo.extra_prompt = "%s  %s the hangar door (%s)" % [Game.hint("interact"), "Close" if _hdoor.target > 0.5 else "Open", _hdoor.state_text()]
		if cargo._target.is_empty() and _switch >= 0:
			cargo.extra_prompt = blights.prompt_for(_switch)
		_near_fork = _forklift_near() if driving == null and cargo.holding.is_empty() else null
		prospect.aim_pitch = walker.look.y
		prospect.walker_pos = walker.global_position
		_ground_item = {}
		_part_target = []
		if driving == null and cargo.holding.is_empty() and _near_fork == null and cargo._target.is_empty():
			var c3 := get_viewport().get_camera_3d()
			if c3 != null:
				for pv in [pickup, plane]:
					if pv != null and pv.has_method("part_target"):
						var pt: Array = pv.part_target(c3.global_position, -c3.global_transform.basis.z, inv.in_hand(), Game.hint("interact"))
						if not pt.is_empty():
							_part_target = [pv, pt[0]]
							cargo.extra_prompt = pt[1]
							break
		if driving == null and cargo.holding.is_empty() and _near_fork == null:
			_ground_item = inv.world_item_near(walker.global_position)
			if not _ground_item.is_empty() and cargo._target.is_empty() and cargo.extra_prompt == "":
				cargo.extra_prompt = "%s  Pick up the %s" % [Game.hint("interact"), String(inv.item_name(String(_ground_item["id"]))).to_lower()]
		_pros_target = []
		if driving == null and _ground_item.is_empty() and cargo.holding.is_empty() and _near_fork == null and _switch < 0 and service.prompt == "" and not walker.in_plane and not walker.swimming:
			_pros_target = prospect.target(walker.global_position, walker.global_transform * Vector3(0, 0, -0.9))
			if cargo._target.is_empty() and cargo.extra_prompt == "" and not _pros_target.is_empty():
				cargo.extra_prompt = _pros_target[1]
		if cargo._target.is_empty() and _near_fork != null:
			var mach := "Drive the forklift"
			if _near_fork.has_method("blade_toggle"):
				mach = "Get in the dozer"
			elif _near_fork.has_method("dig_or_dump"):
				mach = "Get in the excavator"
			elif _near_fork == pickup:
				mach = "Get in the pickup"
			elif _near_fork == water_truck:
				mach = "Get in the water truck"
			elif _near_fork == fuel_truck:
				mach = "Get in the fuel truck"
			elif _near_fork == loader:
				mach = "Get in the loader"
			cargo.extra_prompt = "%s  %s" % [Game.hint("interact"), mach]
		_near_sale = world.sale_near(walker.global_position) if (driving == null and _near_fork == null) else {}
		if cargo._target.is_empty() and cargo.extra_prompt == "" and not _near_sale.is_empty():
			var sname: String = String(PlaneTypes.spec(String(_near_sale["type"]))["name"])
			cargo.extra_prompt = "%s  Buy this %s  ($%s) - it flies away with you" % [
				Game.hint("interact"), sname, menu._money(_sale_price(String(_near_sale["type"])))]
		if driving != null and driving == pickup:
			cargo._target = []
			var pp: String = pickup.prompt()
			cargo.extra_prompt = pp if pp != "" else pickup.status()
		elif driving != null and (driving == water_truck or driving == fuel_truck):
			cargo._target = []
			cargo.extra_prompt = driving.status()
		elif driving != null and driving == tug:
			cargo._target = []
			cargo.extra_prompt = tug.prompt()
		elif driving != null and driving == loader:
			cargo._target = []
			cargo.extra_prompt = loader.status()
		elif driving != null and driving.has_method("blade_toggle"):
			cargo._target = []
			if driving.blade_down:
				cargo.extra_prompt = "Blade DOWN%s   %s blade up   %s get out" % [
					"  carrying %.1f m3" % driving.load_m3 if driving.load_m3 > 0.05 else "",
					Game.hint("interact"), Game.hint("get_out")]
			else:
				cargo.extra_prompt = "%s  Blade down (cut and fill)%s   %s get out" % [
					Game.hint("interact"),
					"  carrying %.1f m3" % driving.load_m3 if driving.load_m3 > 0.05 else "",
					Game.hint("get_out")]
		elif driving != null and driving.has_method("machine_action"):
			cargo._target = []
			cargo.extra_prompt = driving.status()
		elif driving != null and driving.has_method("dig_or_dump"):
			cargo._target = []
			var into: bool = prospect.hopper_near(driving.aim) != Vector3.INF
			if driving.busy():
				cargo.extra_prompt = "Digging..." if driving.state == "dig" else "Dumping..."
			elif driving.bucket_load.is_empty():
				cargo.extra_prompt = "%s  Dig here   (look where to dig; %s get out)" % [Game.hint("interact"), Game.hint("get_out")]
			else:
				cargo.extra_prompt = "%s  %s" % [Game.hint("interact"), "Dump it in the hopper: wash it" if into else "Dump it here (look at the wash plant's hopper to wash it)"]
		elif driving != null and driving.has_method("fork_target"):
			var ft: Array = driving.fork_target()
			cargo._target = []
			cargo.extra_prompt = ("%s  %s" % [Game.hint("interact"), ft[1]] if String(ft[0]) != "" else String(ft[1])) if not ft.is_empty() else "Forks %.1f m   (%s up, %s down)   %s get off" % [driving.lift, Game.hint("throttle_up"), Game.hint("throttle_down"), Game.hint("get_out")]
	else:
		_switch = -1
	hud.drunk_text = camp.state_text()
	if on_foot and net.is_online() and cargo._target.is_empty():
		var other: int = net.plane_at_door(walker.global_position)
		if other != 0:
			cargo.extra_prompt = "%s  Ride with %s" % [Game.hint("interact"), net.remotes[other]["name"]]
	if _exit_hold > 0.0:
		_exit_hold += delta
		if _exit_hold > 0.5:
			_exit_hold = 0.0
			_toggle_foot()
	if on_foot:
		# Let the mouse go when the game isn't the window you're using, or you
		# hold Alt (to click another window); a click back in the game takes it.
		var free: bool = _mouse_free or not _app_focused or Input.is_key_pressed(KEY_ALT)
		var want := Input.MOUSE_MODE_VISIBLE if (menu.is_open or hud.show_map or inv_ui.is_open or free) else Input.MOUSE_MODE_CAPTURED
		if Input.mouse_mode != want:
			Input.mouse_mode = want
	elif seated.visible:
		seated.animate(delta, PilotModel.SIT, 0.0, _clock)
	if not on_foot:
		# In the cockpit the mouse is your head: captured, it looks around and
		# the view stays where you leave it; the dot in the middle works the
		# switches. Hold Alt (or open a menu or the map) for the pointer.
		var free2: bool = not cockpit or _mouse_free or not _app_focused or Input.is_key_pressed(KEY_ALT) or menu.is_open or hud.show_map or net.riding != 0
		var want2 := Input.MOUSE_MODE_VISIBLE if free2 else Input.MOUSE_MODE_CAPTURED
		if Input.mouse_mode != want2:
			Input.mouse_mode = want2
		hud.cockpit_dot = cockpit and not free2
	var au := get_node_or_null("Audio")
	if au != null:
		au.in_plane = not on_foot and net.riding == 0
	if ambience != null:
		# muffled only when you're really in the cab: looking from outside
		# (third person) you hear it as you would standing there
		var in_cab: bool = driving != null and not forklifts.has(driving) and walker.first_person
		ambience.inside = (not on_foot) or in_cab
		EngineSound.cab_muffle = in_cab
		ambience.in_air = not on_foot and not plane.on_ground
	if noises != null:
		if driving != null:
			noises.host = driving
			noises.kind = "truck" if (driving == pickup or driving == water_truck or driving == fuel_truck) else "machine"
		elif not on_foot and net.riding == 0:
			noises.host = plane
			noises.kind = "plane"
		else:
			noises.host = null
	seated.visible = not on_foot and not cockpit and not plane.is_crashed and net.riding == 0
	if gore != null and gore.seat_corpse != null and is_instance_valid(gore.seat_corpse):
		gore.seat_corpse.visible = not cockpit

	if dc3_vis != null and dc3_vis.visible:
		dc3_vis.update_door(delta, bool(plane.door_open.get("bay", false)))
	_update_camera(delta, false)
	_rumble(delta)
	_jitter_sample()
	cam.global_transform = camp.camera_sway(cam.global_transform)
	if cockpit:
		_update_cockpit_hover()


## An engine sound on a vehicle or machine, at its engine.
func _engine_sound(host: Node3D, kind: String, at: Vector3, state: Callable) -> Node3D:
	if host == null:
		return null
	var es: Node3D = EngineSound.new()
	es.name = "EngineSound"
	es.kind = kind
	es.state = state
	es.position = at
	host.add_child(es)
	return es


## A machine with no engine model of its own (dozer, excavator, loader,
## forklift): it runs while someone's in it, revs with how fast it's going
## and how hard it's working.
func machine_sound(host: Node3D, kind: String, at: Vector3, top: float) -> void:
	_engine_sound(host, kind, at, func() -> Dictionary:
		var spd := 0.0
		var work := 0.0
		var bd = host.get("body")
		if bd != null:
			var v = bd.get("vel")
			if v != null:
				spd = (v as Vector3).length()
			elif bd.get("speed") != null:
				spd = absf(float(bd.get("speed")))
			if bd.get("drag") != null:
				work = clampf(float(bd.get("drag")) / 40000.0, 0.0, 1.0)
		elif host.get("speed") != null:
			spd = absf(float(host.get("speed")))
		if host.get("_resist") != null:
			work = maxf(work, float(host.get("_resist")))
		var on: bool = bool(host.get("driven"))
		var rpm := 750.0 + 900.0 * clampf(spd / top, 0.0, 1.0) + 450.0 * work
		return {"rpm": rpm if on else 0.0, "running": on, "load": clampf(spd / top * 0.5 + work, 0.0, 1.0)})


## What the mouse is pointing at in the cockpit, and its name and state as a tip.
func _update_cockpit_hover() -> void:
	cockpit_ctl.panel_hud.target_strip = hud.target_strip
	if menu.is_open or hud.show_map:
		cockpit_ctl.set_hover(-1)
		hud.tooltip = ""
		return
	var mp := get_viewport().get_mouse_position()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mp = get_viewport().get_visible_rect().size * 0.5
	if cockpit_ctl.active < 0 and not _dragging:
		cockpit_ctl.set_hover(cockpit_ctl.pick(cam.project_ray_origin(mp), cam.project_ray_normal(mp)))
	hud.tooltip = cockpit_ctl.hover_text()
	hud.tooltip_pos = mp
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if cockpit_ctl.hover >= 0 else Input.CURSOR_ARROW)


## Camera shake (Game.cam_shake scales it, 0 = off): small, smooth turns of
## the view, never a jump of the eye. Engine vibration from the rpm, rumble
## on the ground from speed and how rough it is, a kick on touchdown that
## dies away, buffet near the stall, and the blast of an explosion.
func _shake_basis(delta: float, k: float) -> Basis:
	var amt: float = Game.cam_shake * k
	if amt <= 0.0 or plane == null or get_tree().paused:
		return Basis.IDENTITY
	_shake_t += delta
	var t := _shake_t
	var rpm_f: float = clampf(plane.engine.rpm / maxf(plane.engine.rated_rpm, 1.0), 0.0, 1.2) if plane.engine != null else 0.0
	var a := 0.0006 * rpm_f                              # engine buzz
	var hz := 18.0 + 14.0 * rpm_f
	if plane.on_ground:
		var gs: float = plane.ground_speed
		var rough := 1.0
		if world != null and world.terrain != null:
			rough = 0.5 if world.terrain.strip_index_at(plane.pos.x, plane.pos.z, 0.0) >= 0 else 1.6
		a += clampf(gs / 25.0, 0.0, 1.0) * 0.004 * rough   # rolling on the ground
		if not _was_on_ground:
			_shake_kick = maxf(_shake_kick, clampf(absf(_prev_vy) * 0.006, 0.0, 0.03))   # touchdown
	if plane.stall_warning:
		a += 0.004                                          # buffet
	_was_on_ground = plane.on_ground
	_prev_vy = plane.vel.y
	_shake_kick = maxf(_shake_kick - delta * 0.06, 0.0)
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 0.8, 0.0)
	var big := _shake_kick + _shake * 0.03
	var px := (sin(t * hz * 1.0) + sin(t * hz * 1.37 + 1.3)) * 0.5 * a + sin(t * 9.0) * cos(t * 13.7) * big
	var py := (sin(t * hz * 0.91 + 2.1) + sin(t * hz * 1.53)) * 0.5 * a * 0.6 + cos(t * 7.3) * sin(t * 11.1) * big * 0.6
	var pz := sin(t * hz * 0.77 + 0.4) * a * 0.4 + sin(t * 6.1) * big * 0.5
	return Basis.from_euler(Vector3(px, py, pz) * amt)


var _head := Vector3.ZERO
var _head_v := Vector3.ZERO
var _sf_avg := Vector3(0.0, 9.81, 0.0)
var _jolt := 0.0                    # a one-off knock through the controller, fading (0..1)
var _veh_v := Vector3.ZERO


func jolt(amount: float) -> void:
	_jolt = maxf(_jolt, amount)


## Every rumble goes out through here, scaled by the Rumble strength slider.
func _vib(_dev: int, weak: float, strong: float) -> void:
	var k: float = Game.rumble_strength
	for d in _rumble_pads():
		if k <= 0.001:
			Input.stop_joy_vibration(d)
		else:
			Input.start_joy_vibration(d, clampf(weak * k, 0.0, 1.0), clampf(strong * k, 0.0, 1.0), 0.12)


func _rumble_pads() -> Array:
	var pads: Array = Array(Input.get_connected_joypads())
	var gear: Array = Game.hotas.gear_ids() if Game.get("hotas") != null else []
	var out: Array = []
	for d in pads:
		if not gear.has(d):
			out.append(d)
	return out if not out.is_empty() else pads


## Feel the engine (DESIGN_NOTES 161): a knock on the heavy motor for each
## firing - the starter heaving it through compression, a lumpy idle, a big
## cam's loping beat - played at the firing rate while the motor can follow
## it (halved down to about 12 a second when it can't, keeping the rhythm),
## the light motor's buzz rising with revs and load. Returns (weak, strong).
var _pulse_ph := 0.0
var _pulse_n := 0
var _pulse_skip := false
func _engine_pulse(delta: float, rpm: float, cyl: int, running: bool, cranking: bool, load: float, rough: float, lumpy: bool) -> Vector2:
	var amt: float = Game.rumble_engine
	if amt <= 0.001 or (not running and not cranking) or rpm < 30.0:
		return Vector2.ZERO
	var fire_hz := rpm / 60.0 * float(maxi(cyl, 1)) * 0.5
	var hz := fire_hz
	while hz > 12.0:
		hz *= 0.5
	var before := _pulse_ph
	_pulse_ph = fposmod(_pulse_ph + hz * delta, 1.0)
	if _pulse_ph < before:
		# a new firing: a rough engine misses one now and then
		_pulse_n += 1
		_pulse_skip = rough > 0.05 and randf() < rough * 0.35
	var shape := pow(maxf(cos(_pulse_ph * TAU), 0.0), 6.0)
	if _pulse_skip:
		shape *= 0.15
	if lumpy and _pulse_n % 2 == 1:
		shape *= 0.45                # the big cam: strong-weak, strong-weak
	# the faster it turns, the more the firings run together into a hum
	var smooth := clampf((fire_hz - 25.0) / 100.0, 0.0, 1.0)
	var knock: float
	if cranking and not running:
		knock = 0.55                 # heaving over compression on the starter
	else:
		knock = (0.30 + 0.35 * rough + 0.15 * load) * (1.0 - 0.65 * smooth)
	var strong := shape * knock * amt
	var weak := (0.05 + 0.18 * load + 0.12 * smooth + (0.12 if cranking else 0.0)) * amt
	return Vector2(weak, strong)


## A truck or machine's engine, from its engine sound's own state.
func _machine_engine_feel(v: Node, delta: float) -> Vector2:
	var es: Node = v.get_node_or_null("EngineSound")
	var cb: Callable = es.get("state") if es != null else Callable()
	if es == null or not cb.is_valid():
		var eng = v.get("engine_on")
		return Vector2(0.10 if (eng == null or bool(eng)) else 0.0, 0.0)
	var st: Dictionary = cb.call()
	var kind := String(es.get("kind"))
	var cyl: int = {"v8cam": 8, "diesel": 6, "machine": 6, "small": 1}.get(kind, 6)
	var running := bool(st.get("running", false))
	var cranking := bool(st.get("cranking", false))
	return _engine_pulse(delta, float(st.get("rpm", 0.0)), cyl, running, cranking, float(st.get("load", 0.3)), 0.25 if kind == "v8cam" else 0.08, kind == "v8cam")


func _head_motion(delta: float) -> Vector3:
	if plane == null or Game.cam_shake <= 0.0 or delta <= 0.0:
		return Vector3.ZERO
	var f: Vector3 = plane.seat_force - Vector3(0.0, 9.81, 0.0)
	var want := Vector3(-f.x * 0.0035, -f.y * 0.0055, -f.z * 0.003) * Game.cam_shake
	var dt := minf(delta, 0.05)
	# about 1.6 Hz, a little underdamped: the head settles with one small bob
	_head_v += ((want - _head) * 100.0 - _head_v * 11.0) * dt
	_head += _head_v * dt
	_head = _head.clamp(Vector3(-0.06, -0.09, -0.06), Vector3(0.06, 0.06, 0.06))
	return _head


## The controller shakes with the aeroplane (DESIGN_NOTES 154): the engine's
## buzz in the light motor, bumps of rough air, the stall buffet, the
## touchdown and the rumble of a rough strip in the heavy one.
func _rumble(delta: float) -> void:
	# Every connected pad that isn't flight gear (a GameSir and the like can
	# show up under a name that isn't picked out as "the" gamepad), and not
	# only while the last input was the pad: a nudge of the mouse used to
	# switch it off.
	if not Game.rumble or plane == null:
		return
	if _rumble_pads().is_empty():
		return
	var dev := -1
	_jolt = maxf(_jolt - delta * 2.0, 0.0)
	if not on_foot:
		_shake = maxf(_shake - delta * 0.8, 0.0)       # (on foot the camera lets it die away)
	if get_tree().paused:
		for d0 in _rumble_pads():
			Input.stop_joy_vibration(d0)
		return
	# Machines (DESIGN_NOTES 160): the engine's buzz, bumps and knocks through
	# the seat, wheels spinning in mud, tracks grinding along.
	if driving != null:
		var weak_m := 0.0
		var strong_m := _jolt
		var ef := _machine_engine_feel(driving, delta)
		weak_m = ef.x
		strong_m = maxf(strong_m, ef.y)
		var body = driving.get("body")
		if body != null:
			var v: Vector3 = body.vel
			var acc: float = (v - _veh_v).length() / maxf(delta, 0.001) / 9.81
			_veh_v = v
			strong_m = maxf(strong_m, clampf((acc - 0.2) * 0.5, 0.0, 1.0))
			var spd: float = v.length()
			weak_m += clampf(spd / 15.0, 0.0, 0.25)
			var spin = body.get("spin_now")
			if spin != null:
				weak_m += 0.4 * float(spin)
			if prospect != null and (driving in prospect.dozers or driving in prospect.excavators):
				if spd > 0.2:
					strong_m = maxf(strong_m, 0.2)
		_vib(dev, weak_m, maxf(strong_m, _shake * 0.8))      # a blast nearby rocks the cab too
		return
	if on_foot or plane.is_crashed:
		# on foot: only knocks (a blast, being hit, a tree coming down)
		var st: float = maxf(_jolt, _shake * 0.8)
		var buzz: float = 0.45 if _saw_t > 0.0 else 0.0          # the chainsaw running in your hands
		if st > 0.02 or buzz > 0.0:
			_vib(dev, maxf(st * 0.6, buzz), st)
		else:
			for d1 in _rumble_pads():
				Input.stop_joy_vibration(d1)
		return
	_sf_avg = _sf_avg.lerp(plane.seat_force, clampf(4.0 * delta, 0.0, 1.0))
	var bump: float = (plane.seat_force - _sf_avg).length() / 9.81
	var rpm_f: float = clampf(plane.engine.rpm / maxf(plane.engine.rated_rpm, 1.0), 0.0, 1.2)
	var weak := 0.05 * rpm_f + (0.35 if plane.stall_warning else 0.0)
	var strong := clampf((bump - 0.04) * 1.6, 0.0, 1.0)
	if plane.on_ground:
		strong = maxf(strong, clampf(plane.ground_speed / 30.0, 0.0, 1.0) * 0.18)
	# the engine itself, firing by firing, through the seat
	var e = plane.engine
	var cyl: int = int(e.get("cylinders")) if e.get("cylinders") != null else 6
	var pf := _engine_pulse(delta, float(e.rpm), cyl, bool(e.running), bool(e.cranking), clampf(float(plane.throttle), 0.0, 1.0), float(e.roughness), false)
	_vib(dev, maxf(weak, pf.x), maxf(maxf(strong, pf.y), maxf(_jolt, _shake * 0.8)))


func _update_camera(delta: float, snap: bool) -> void:
	if _eco_on:
		cam.global_transform = _eco_xf
		return
	if on_foot:
		cam.global_transform = walker.camera_transform()
		if _shake > 0.0:
			# a blast nearby: the ground heaves and the view shakes (DESIGN_NOTES 142)
			_shake = maxf(_shake - delta * 0.8, 0.0)
			_shake_t += delta
			var t2 := _shake_t
			var amt2 := Game.cam_shake * _shake * 0.03
			cam.global_transform.basis = cam.global_transform.basis * Basis.from_euler(Vector3(sin(t2 * 9.0) * cos(t2 * 13.7), cos(t2 * 7.3) * sin(t2 * 11.1) * 0.6, sin(t2 * 6.1) * 0.5) * amt2)
			cam.global_position += Vector3(0, sin(t2 * 23.0) * 0.06 * _shake * Game.cam_shake, 0)
		# Aiming the pistol (DESIGN_NOTES 181): right mouse / LT pulls the
		# view in over the shoulder and narrows it; the crosshair comes up.
		var want_aim: bool = inv != null and inv.in_hand() == "pistol" and not _foot_down and not menu.is_open \
			and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or _pad_lt() > 0.4 or force_aim or Time.get_ticks_msec() * 0.001 < _ready_until)
		walker.aiming = want_aim
		if "aim" in walker.model:
			walker.model.aim = want_aim
		_ads = move_toward(_ads, 1.0 if want_aim else 0.0, delta * 6.0)
		if _ads > 0.0 and not walker.first_person:
			var cb: Basis = cam.global_transform.basis
			var head: Vector3 = walker.get_global_transform_interpolated().origin + Vector3(0, 1.6, 0)
			cam.global_position = cam.global_position.lerp(head + cb * Vector3(0.42, 0.02, 0.95), _ads * 0.9)
		if handcam != 0:
			# console handcheck: a close look at what's in his hands (front right, or behind)
			var wx: Transform3D = walker.get_global_transform_interpolated()
			var eyep: Vector3 = wx * ([Vector3(1.3, 1.45, -1.6), Vector3(-0.9, 1.6, 1.6), Vector3(2.0, 1.3, 0.0)][clampi(handcam - 1, 0, 2)])
			cam.global_transform = Transform3D(Basis.IDENTITY, eyep).looking_at(wx * Vector3(0.15, 1.15, -0.2), Vector3.UP)
		hud.aim = _ads
		hud.crosshair = inv != null and inv.in_hand() == "pistol" and not _foot_down
		cam.fov = lerpf((74.0 if walker.first_person else 66.0), 36.0, _ads) + Game.fov_offset
		if handcam != 0:
			cam.fov = 55.0
		cam.near = 0.05 if walker.first_person else 0.2
		return
	# Looking around with the look keys, or the right stick while free look is held.
	var look_in := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if Game.using_gamepad and not Input.is_action_pressed("free_look"):
		look_in = Vector2.ZERO
	look_in += Vector2(Game.hotas.value("look_x"), Game.hotas.value("look_y"))
	if look_in.length() > 0.05:
		_orbit_idle = 0.0
		_mouse_looked = false
		var rate := 2.4 * Game.look_speed * delta
		_orbit.x -= look_in.x * rate
		var dy := look_in.y * rate * 0.8
		_orbit.y = clampf(_orbit.y + (-dy if cockpit else dy), -1.2, 1.3)
	# Let the view drift back to straight ahead after a moment (not in the cockpit
	# after looking with the mouse: you are probably reaching for a switch).
	if not _dragging and not (cockpit and _mouse_looked):
		_orbit_idle += delta
		if _orbit_idle > (0.8 if Game.using_gamepad else 2.5):
			_orbit = _orbit.lerp(Vector2.ZERO, clampf(2.0 * delta, 0.0, 1.0))
	var xf: Transform3D = plane.render_xf() if plane.has_method("render_xf") else plane.global_transform
	var eye := _eye_point() + Vector3(0, Game.seat_height, -Game.seat_fore)
	if net.riding != 0:
		xf = net.ride_transform()
		eye = net.SEATS[net.seat]
	if cockpit:
		# Resting gaze 12 deg below the fuselage line, as a pilot sits: the
		# top of the panel in view under the horizon (planeview measures the
		# instruments 42-54 deg below the line; -0.09 left them all off screen).
		var look := Basis(Vector3.UP, _orbit.x) * Basis(Vector3.RIGHT, clampf(_orbit.y, -1.1, 1.0) - 0.21)
		# The head rides on the pilot's neck (DESIGN_NOTES 154): pressed down
		# in a pull-up, thrown up in a bump, swaying in a skid, pushed back
		# by full power - a spring and damper on the g you're pulling.
		cam.global_transform = Transform3D(xf.basis * look * _shake_basis(delta, 1.0), xf * (eye + _head_motion(delta)))
		_cockpit_fov_now = lerpf(_cockpit_fov_now, _cockpit_fov * (0.5 if _zoom_hold else 1.0), clampf(10.0 * delta, 0.0, 1.0))
		cam.fov = _cockpit_fov_now + Game.fov_offset
		cam.near = 0.08
		return
	cam.fov = 66.0 + Game.fov_offset
	cam.near = 0.3
	var target := xf.origin + Vector3(0, 1.4 * _size_scale(), 0)
	var want := _plane_yaw()
	if snap:
		_chase_yaw = want
	else:
		_chase_yaw = lerp_angle(_chase_yaw, want, clampf(2.6 * delta, 0.0, 1.0))
	var tilt := clampf(0.24 + _orbit.y, -0.5, 1.4)
	var rot := Basis(Vector3.UP, _chase_yaw + _orbit.x) * Basis(Vector3.RIGHT, -tilt)
	var pos := target + rot * Vector3(0, 0, _chase_dist * _size_scale())
	# Stay above the ground and the water.
	var floor_y: float = maxf(world.terrain.ground_level_at(pos.x, pos.z), 0.0) + 1.6
	if pos.y < floor_y:
		pos.y = floor_y
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	cam.global_transform.basis = cam.global_transform.basis * _shake_basis(delta, 0.5)


# ------------------------------------------------------------------------------
#  Command-line test hooks (used during development to take screenshots)
#  Example:  godot --path . -- shot=chase,cockpit strip=2 season=1 air=1
# ------------------------------------------------------------------------------
func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		_test[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _test.has("season"):
		Game.season = int(_test["season"])
	if _test.has("trees3d"):
		Game.trees_3d = _test["trees3d"] != "0"
	if _test.has("plants"):
		Game.gfx_plants = int(_test["plants"])
	if _test.has("time"):
		Game.time_of_day = float(_test["time"])
	if _test.has("realism"):
		Game.realism = int(_test["realism"])
	if _test.has("wind"):
		Game.wind_level = int(_test["wind"])
	if _test.has("manual"):
		Game.engine_auto = false


func _run_test() -> void:
	var k := int(_test.get("strip", "0"))
	if _test.has("type"):
		plane.apply_type(String(_test["type"]))
		_apply_plane_type()
	if _test.has("leg"):
		plane.leg_kind = String(_test["leg"])
		plane.apply_gear()
	hud.show_help = _test.has("help")
	if _test.has("pos"):
		var c := String(_test["pos"]).split(",")
		plane.place_in_air(Vector3(float(c[0]), float(c[1]), float(c[2])), float(c[3]), 50.0)
		plane.frozen = true
	elif _test.has("air"):
		plane.place_on_approach(k, float(_test.get("dist", "1500")), float(_test.get("height", "150")))
		plane.frozen = true
	else:
		plane.place_on_strip(k)
		# Not on top of a plane already parked there: move up the strip.
		var off := 0.0
		while off < 140.0 and _spawn_blocked():
			off += 18.0
			plane.place_on_strip(k, false, off)
		jobs.restow()
	hud.target_strip = int(_test.get("target", "2"))
	if _test.has("cockpit"):
		_set_cockpit(true)
	if _test.has("nohud"):
		hud.visible = false
	if _test.has("slam"):
		# Drop the plane onto the runway, banked, to see real dents happen.
		var st: Dictionary = world.terrain.strips[k]
		var p0: Vector3 = world.terrain.strip_point(k, -float(st["length"]) * 0.5 + 90.0)
		plane.frozen = false
		plane.place_in_air(p0 + Vector3(0, 3.2, 0), float(st["heading"]), 30.0)
		plane.b = plane.b * Basis(Vector3.BACK, deg_to_rad(float(_test.get("bank", "14"))))
		plane.vel.y = -float(_test["slam"])
		plane.throttle = 0.0
		for i in range(int(_test.get("slamframes", "300"))):
			await get_tree().physics_frame
		plane.frozen = true
		print("after slam: crashed=", plane.is_crashed, " report=", plane.damage_report())
	if _test.has("treecrash") or _test.has("boom"):
		await _crash_test()
	if _test.get("damage", "") == "2":
		# A plane that has had a bad day, to check how damage looks.
		plane.frozen = true
		for pn in [["gear_l", 0.8], ["tire_r", 0.7], ["prop", 0.7], ["wing_r", 0.7], ["aileron_r", 0.6], ["tank_r", 0.3], ["rudder", 0.5], ["elevator", 0.4]]:
			plane.hurt(pn[0], pn[1])
		plane.engine.health = 0.15
		plane.dented.emit(Vector3(-5.4, 0.95, 0.3), Vector3(0, 1, 0.3).normalized(), 1.3)
		plane.dented.emit(Vector3(0, -0.4, -1.95), Vector3(0, 0.5, 1).normalized(), 0.9)
		plane.dented.emit(Vector3(-0.56, 0.2, 0.3), Vector3(1, 0, 0), 0.8)
		plane.dented.emit(Vector3(0, -0.1, 4.6), Vector3(0, 1, 0), 0.6)
		plane.dented.emit(Vector3(3.6, 1.0, -0.4), Vector3(0, -0.1, 1).normalized(), 1.0)
		plane.scraped.emit(Vector3(0, -0.62, 0.6), 1.0)
		plane.scraped.emit(Vector3(-0.5, -0.5, -0.8), 0.8)
	elif _test.has("damage"):
		plane.hurt("gear_r", 0.45)
		plane.hurt("prop", 0.3)
		plane.hurt("tank_l", 0.3)
		plane.hurt("aileron_l", 0.3)
	_chase_yaw = _plane_yaw()
	_chase_dist = float(_test.get("zoom", "19"))
	if _test.has("stopped"):
		plane.engine.stop()
		plane.engine.rpm = 0.0
	if _test.has("fakehotas"):
		# A pretend X56 (stick and throttle), for pictures of the setup page.
		var hz: Node = Game.hotas
		hz._ids["|Saitek Pro Flight X-56 Rhino Stick"] = 50
		hz._ids["|Saitek Pro Flight X-56 Rhino Throttle"] = 51
		hz.test_raw = {"50:0": 0.35, "50:1": -0.2, "50:5": 0.1, "51:0": -0.4, "51:1": 0.6, "51:4": -0.1}
		var stick := "Saitek Pro Flight X-56 Rhino Stick"
		var quad := "Saitek Pro Flight X-56 Rhino Throttle"
		hz.axes = {"roll": {"dev": stick, "guid": "", "a": 0, "lo": -1.0, "hi": 1.0},
			"pitch": {"dev": stick, "guid": "", "a": 1, "lo": -1.0, "hi": 1.0},
			"yaw": {"dev": stick, "guid": "", "a": 5, "lo": -1.0, "hi": 1.0},
			"throttle": {"dev": quad, "guid": "", "a": 0, "lo": 1.0, "hi": -1.0},
			"prop": {"dev": quad, "guid": "", "a": 1, "lo": 1.0, "hi": -1.0},
			"mixture": {"dev": quad, "guid": "", "a": 4, "lo": -1.0, "hi": 1.0}}
		hz.buttons = {"brake": {"dev": stick, "guid": "", "i": 0}, "flaps_down": {"dev": quad, "guid": "", "i": 6}}
	if _test.has("eco"):
		_place_eco_camera(String(_test["eco"]), st_pos_for_test())
	var settle := int(_test.get("frames", "40"))
	for i in range(settle):
		await get_tree().process_frame
	# Let the plants around the camera finish growing in.
	if world.vegetation != null and not _test.has("nowait"):
		_update_camera(0.016, true)
		for i in range(1200):
			await get_tree().process_frame
			if world.vegetation.is_idle() and i > 30:
				break
	var out_dir := String(_test.get("out", "/tmp/shots"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var tag := String(_test.get("tag", "s%d_k%d" % [Game.season, k]))
	if _test.has("cargo"):
		# Hand-loading picture: a job on the ramp, the pilot out carrying one piece.
		var kind_want := String(_test["cargo"])
		var cj := {}
		for j in jobs.board(k):
			if int(j["pax"]) == 0 and jobs.cannot_take(j) == "" and (kind_want == "1" or j["kind"] == kind_want):
				cj = j
				break
		if not cj.is_empty() and jobs.take(cj, true):
			_get_out()
			walker.first_person = false
			for i in range(3):
				await get_tree().process_frame
			var job: Dictionary = jobs.carried.back()
			var first: Dictionary = job["pieces"][0]
			walker.place((first["pos"] as Vector3) + Vector3(0.7, 0, 0), _plane_yaw() + PI * 0.5)
			await get_tree().process_frame
			cargo._find_target()
			cargo.interact()
			walker.place(walker.global_position + (plane.global_position - walker.global_position).normalized() * 2.0, 0.0)
			var to_plane: Vector3 = plane.global_position - walker.global_position
			walker.yaw = atan2(-to_plane.x, -to_plane.z)
			walker.look = Vector2(walker.yaw + 0.9, -0.25)
			walker.cam_dist = 5.5
			for i in range(3):
				await get_tree().process_frame
			print("cargo shot: ", job["what"])
	if _test.has("swimtest"):
		var lk: Dictionary = world.terrain.lakes[1]
		var lc: Vector2 = lk["pos"]
		var wl: float = world.terrain.water_level_at(lc.x, lc.y)
		_get_out()
		await get_tree().process_frame
		walker.place(Vector3(lc.x, wl - 0.5, lc.y), 0.0)
		var p0: Vector3 = walker.global_position
		for i in range(240):
			walker.step(1.0 / 60.0, Vector2(0.0, -1.0), false, false)
			await get_tree().process_frame
		var p1: Vector3 = walker.global_position
		print("swimtest: swimming %s, moved %.1f m, feet %.2f m below the surface, warmth %.2f" % [walker.swimming, Vector2(p1.x - p0.x, p1.z - p0.z).length(), wl - p1.y, walker.warmth])
		get_tree().quit()
		return
	if _test.has("floatroll"):
		plane.leg_kind = "amphib"
		Game.leg_kind = "amphib"
		plane.apply_gear()
		_on_start_requested(int(_test.get("strip", "0")), false)
		for i in range(20):
			await get_tree().process_frame
		for e in plane.engines():
			e.set_running(plane.oat_c)
		plane.brake = 0.0
		var p0: Vector3 = plane.global_position
		for i in range(60 * int(_test.get("secs", "30"))):
			plane.throttle = 1.0
			plane.brake = 0.0
			if _test.has("hold"):
				plane.direct_controls = false
				plane.in_pitch = 1.0 if plane.ias_kt > float(_test["hold"]) else 0.0
			if i % 120 == 0:
				var gy: float = world.terrain.ground_level_at(plane.global_position.x, plane.global_position.z)
				print("floatroll t %.0f gs %.1f kt ias %.0f moved %.0f m pitch %.1f on_ground %s gear_pos %.2f loads %s comp %s thrust %.0f rpm %.0f brake %.2f keel %.0f N agl %.2f" % [i / 60.0, plane.ground_speed * 1.944, plane.ias_kt,
					plane.global_position.distance_to(p0), rad_to_deg(plane.pitch_rad()), plane.on_ground, plane.gear_pos, plane.wheel_load, plane.wheel_comp, plane.thrust_now, plane.engine.rpm, plane.brake, plane.float_ground_n, plane.global_position.y - gy])
			await get_tree().physics_frame
		get_tree().quit()
		return
	if _test.has("enginetest"):
		await _engine_test()
		get_tree().quit()
		return
	if _test.has("perftest"):
		await _perf_test()
		get_tree().quit()
		return
	if _test.has("geartest"):
		await _gear_test()
		get_tree().quit()
		return
	if _test.has("dc3engtest"):
		await _dc3_eng_test()
		get_tree().quit()
		return
	if _test.has("bldtest"):
		await _bld_test()
		get_tree().quit()
		return
	if _test.has("cargotest"):
		await _cargo_hand_test()
		get_tree().quit()
		return
	if _test.has("doztest"):
		await _dozer_test()
		get_tree().quit()
		return
	if _test.has("saletest"):
		await _sale_test()
		get_tree().quit()
		return
	if _test.has("crashtest"):
		await _crash_test()
		get_tree().quit()
		return
	if _test.has("deeptest"):
		await _deep_test()
		get_tree().quit()
		return
	if _test.has("watertest"):
		await _water_test()
		get_tree().quit()
		return
	if _test.has("jittest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F9
		ev.keycode = KEY_F9
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().create_timer(0.5).timeout
		print("jittest: recording %s" % _jit_on)
		await get_tree().create_timer(16.0).timeout
		print("jittest: done, samples %d, file %s" % [_jit.size(), FileAccess.file_exists(ProjectSettings.globalize_path("res://jitter_log.txt"))])
		get_tree().quit()
		return
	if _test.has("edgetest"):
		_on_start_requested(0, false)
		var vx = world.ground_view
		for i in range(40):
			await get_tree().create_timer(0.5).timeout
			if vx.ready_at(Vector3(170, 5, 179)) and vx.ready_at(Vector3(-179, 5, 0)):
				break
		var worst := 0.0
		for pt in [Vector2(165, 179.6), Vector2(0, 179.6), Vector2(-150, 179.6), Vector2(-179.6, 0), Vector2(-179.6, 120), Vector2(179.6, 0), Vector2(0, -179.6), Vector2(150, -179.6)]:
			var want: float = world.terrain.height_at(pt.x, pt.y)
			var got: float = vx.floor_below(Vector3(pt.x, want + 6.0, pt.y), 40.0)
			worst = maxf(worst, absf(got - want))
			print("edgetest: at %s ground should be %.2f, voxel floor %.2f (off %.2f)" % [str(pt), want, got, got - want])
		print("edgetest: worst %.2f m %s" % [worst, "OK" if worst < 0.3 else "<-- STEP"])
		var walls := 0
		for pt2 in [Vector3(165, 0, 179.9), Vector3(0, 0, 179.9), Vector3(-179.9, 0, 0), Vector3(-179.9, 0, 120), Vector3(179.9, 0, 0), Vector3(0, 0, -179.9)]:
			var hh: float = world.terrain.height_at(pt2.x, pt2.z)
			var sd: float = vx.sdf_at(Vector3(pt2.x, hh + 1.0, pt2.z))
			if sd < 0.0:
				walls += 1
			print("edgetest: chest height at %s: %s" % [str(Vector2(pt2.x, pt2.z)), "ROCK (wall)" if sd < 0.0 else "air"])
		print("edgetest: %d of 6 edge spots walled" % walls)
		# What the mesher sees a voxel or two past each edge (outside the
		# bounds, straight from the generator): rock a metre up is a wall.
		var gen = vx.terrain.generator
		var n: int = vx._n
		var bad := 0
		var tried := 0
		for side in range(4):
			for kk in range(8):
				var along := 40 + kk * (n - 80) / 7
				for off in [1, 2]:
					var vi: Vector3i
					match side:
						0: vi = Vector3i(n - 1 + off, 0, along)
						1: vi = Vector3i(-off, 0, along)
						2: vi = Vector3i(along, 0, n - 1 + off)
						_: vi = Vector3i(along, 0, -off)
					var wx: float = -vx._sq + float(clampi(vi.x, 0, n - 1)) * vx.VOX
					var wz: float = -vx._sq + float(clampi(vi.z, 0, n - 1)) * vx.VOX
					var hh2: float = world.terrain.height_at(wx, wz)
					var vy := int(round((hh2 + 1.0) / vx.VOX))
					var buf := VoxelBuffer.new()
					buf.create(1, 1, 1)
					gen.generate_block(buf, Vector3i(vi.x, vy, vi.z), 0)
					var sdv: float = buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)
					tried += 1
					if sdv < 0.0:
						bad += 1
		print("edgetest: past the edges, %d of %d samples are rock a metre above the ground %s" % [bad, tried, "OK" if bad == 0 else "<-- WALL"])
		get_tree().quit()
		return
	if _test.has("cabintest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		var secs := [[-2.05, 0.34, 0.28, -0.36, 0.12], [-1.92, 0.48, 0.42, -0.50, 0.14], [-1.15, 0.54, 0.50, -0.58, 0.14], [-0.45, 0.56, 0.92, -0.62, 0.12], [1.10, 0.54, 0.92, -0.62, 0.12], [1.65, 0.46, 0.60, -0.50, 0.12], [3.20, 0.26, 0.38, -0.22, 0.08]]
		var cab: MeshInstance3D = visual.cockpit.get_node_or_null("Cabin")
		var outn := 0
		var worst := 0.0
		var worst_v := Vector3.ZERO
		var arr: Array = cab.mesh.surface_get_arrays(0)
		for cv in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if cv.z < float(_test.get("cabz", "-0.45")):
				continue      # the windscreen/panel end: its own shapes
			for si in range(secs.size() - 1):
				var sa: Array = secs[si]
				var sb: Array = secs[si + 1]
				if cv.z >= float(sa[0]) and cv.z <= float(sb[0]):
					var tt := (cv.z - float(sa[0])) / (float(sb[0]) - float(sa[0]))
					var hw := lerpf(sa[1], sb[1], tt)
					var top := lerpf(sa[2], sb[2], tt)
					var bot := lerpf(sa[3], sb[3], tt)
					var bev := lerpf(sa[4], sb[4], tt)
					var over := maxf(maxf(absf(cv.x) - hw, cv.y - top), maxf(bot - cv.y, maxf(absf(cv.x) + cv.y - (hw + top - bev), absf(cv.x) - cv.y - (hw - bot - bev))))
					if over > 0.003:
						outn += 1
						if outn < 12:
							print("  out %.3f at %s" % [over, cv])
						if over > worst:
							worst = over
							worst_v = cv
		print("cabintest: interior vertices outside the skin: %d, worst %.3f m at %s %s" % [outn, worst, worst_v, "OK" if outn == 0 else "<-- pokes out"])
		get_tree().quit()
		return
	if _test.has("viewtest"):
		# What the driver sees: each gauge's angle below the default view and
		# whether anything in the cab is between the eye and it, and how far
		# down past the dash the road shows.
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		for veh in [water_truck, pickup]:
			if veh == null:
				continue
			var tris := PackedVector3Array()
			var tri_owner: Array = []
			var stack: Array = [veh]
			while not stack.is_empty():
				var nd: Node = stack.pop_back()
				for ch in nd.get_children():
					stack.append(ch)
				if nd is MeshInstance3D and (nd as MeshInstance3D).mesh != null and not String(nd.get_path()).contains("Dash") and not String(nd.name).contains("Glass") and not String(nd.name).contains("Wheel") and (nd as MeshInstance3D).is_visible_in_tree():
					var mn := nd as MeshInstance3D
					var mesh_xf: Transform3D = mn.global_transform
					for si in range(mn.mesh.get_surface_count()):
						var sa: Array = mn.mesh.surface_get_arrays(si)
						var vv: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]
						var ix = sa[Mesh.ARRAY_INDEX]
						if ix != null and (ix as PackedInt32Array).size() > 0:
							for ii in (ix as PackedInt32Array):
								tris.append(mesh_xf * vv[ii])
						else:
							for vq in vv:
								tris.append(mesh_xf * vq)
						while tri_owner.size() < tris.size() / 3:
							tri_owner.append(String(mn.name))
			var eye: Transform3D = veh.eye_xf()
			var pitch := -0.15
			var fwd: Vector3 = (veh.global_transform.basis * Vector3(0, 0, -1)).normalized()
			var lookdir := (fwd * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
			var dash: Node3D = veh.find_child("Dash", true, false)
			var hidden := 0
			var outside := 0
			var nshow := 0
			for g in dash.get_children():
				if not (g is Node3D) or (g as Node3D).get_child_count() == 0:
					continue
				var gp: Vector3 = (g as Node3D).global_position
				var dv := (gp - eye.origin)
				var ang := rad_to_deg(lookdir.angle_to(dv.normalized()))
				var below := rad_to_deg(asin(clampf(dv.normalized().dot(Vector3.UP), -1, 1)))
				var blocked := false
				var end := gp + (eye.origin - gp).normalized() * 0.03
				for ti in range(0, tris.size() - 2, 3):
					var hit = Geometry3D.segment_intersects_triangle(eye.origin, end, tris[ti], tris[ti + 1], tris[ti + 2])
					if hit != null:
						blocked = true
						print("   blocked by %s at %s" % [tri_owner[ti / 3], (veh.global_transform.affine_inverse() * (hit as Vector3)).snapped(Vector3(0.01, 0.01, 0.01))])
						break
				nshow += 1
				if blocked:
					hidden += 1
				if ang > 34.0:
					outside += 1
				print("viewtest %s: gauge at %s, %.0f deg below level, %.0f deg off view centre %s%s" % [veh.name, (veh.global_transform.affine_inverse() * gp).snapped(Vector3(0.01, 0.01, 0.01)), -below, ang, "BLOCKED " if blocked else "", "OFF SCREEN" if ang > 34.0 else ""])
			# road: lowest angle straight ahead where the eye sees out past the cab
			var lowest := 0.0
			for dg in range(0, 60):
				var dirv := (fwd * cos(deg_to_rad(-float(dg))) + Vector3.UP * sin(deg_to_rad(-float(dg)))).normalized()
				var hitd := false
				for ti2 in range(0, tris.size() - 2, 3):
					var h2 = Geometry3D.segment_intersects_triangle(eye.origin, eye.origin + dirv * 8.0, tris[ti2], tris[ti2 + 1], tris[ti2 + 2])
					if h2 != null:
						hitd = true
						print("   view down %d deg stopped by %s at %s" % [dg, tri_owner[ti2 / 3], (veh.global_transform.affine_inverse() * (h2 as Vector3)).snapped(Vector3(0.01, 0.01, 0.01))])
						break
				if hitd:
					break
				lowest = float(dg)
			print("viewtest %s: %d gauges, %d blocked, %d off screen; sees out straight ahead down to %.0f deg below level" % [veh.name, nshow, hidden, outside, lowest])
		get_tree().quit()
		return
	if _test.has("planeview"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		var ck: Node3D = visual.cockpit
		var roots: Array = []
		var st2: Array = [ck]
		while not st2.is_empty():
			var n2: Node = st2.pop_back()
			for c2 in n2.get_children():
				st2.append(c2)
			if n2.name == "Needle" and n2.get_parent() != null and n2.get_parent().get_parent() != null:
				var rt: Node = n2.get_parent().get_parent()
				if not roots.has(rt):
					roots.append(rt)
		var tr2 := PackedVector3Array()
		var own2: Array = []
		var st3: Array = [visual]
		while not st3.is_empty():
			var n3: Node = st3.pop_back()
			for c3 in n3.get_children():
				st3.append(c3)
			if not (n3 is MeshInstance3D) or (n3 as MeshInstance3D).mesh == null or not (n3 as MeshInstance3D).is_visible_in_tree():
				continue
			var skip := String(n3.name).contains("lass") or String(n3.name).begins_with("Ch") or (n3 as MeshInstance3D).mesh is CylinderMesh or (n3 as MeshInstance3D).mesh is QuadMesh
			for rt2 in roots:
				if (rt2 as Node).is_ancestor_of(n3):
					skip = true
			if skip:
				continue
			var m3 := n3 as MeshInstance3D
			for si3 in range(m3.mesh.get_surface_count()):
				var ar3: Array = m3.mesh.surface_get_arrays(si3)
				var v3: PackedVector3Array = ar3[Mesh.ARRAY_VERTEX]
				var i3 = ar3[Mesh.ARRAY_INDEX]
				if i3 != null and (i3 as PackedInt32Array).size() > 0:
					for q3 in (i3 as PackedInt32Array):
						tr2.append(m3.global_transform * v3[q3])
				else:
					for w3 in v3:
						tr2.append(m3.global_transform * w3)
				while own2.size() < tr2.size() / 3:
					own2.append(String(n3.name))
		var eye2: Vector3 = visual.global_transform * _eye_point()
		var fw2: Vector3 = (plane.b * Vector3(0, 0, -1)).normalized()
		var nb := 0
		for rt3 in roots:
			var gp2: Vector3 = (rt3 as Node3D).global_position
			var d2 := gp2 - eye2
			var ang2 := rad_to_deg(fw2.angle_to(d2.normalized()))
			var hit3 := ""
			var end2 := gp2 + (eye2 - gp2).normalized() * 0.03
			for t3 in range(0, tr2.size() - 2, 3):
				var h3 = Geometry3D.segment_intersects_triangle(eye2, end2, tr2[t3], tr2[t3 + 1], tr2[t3 + 2])
				if h3 != null:
					hit3 = own2[t3 / 3]
					break
			if hit3 != "":
				nb += 1
			print("planeview: %s %.0f deg off nose %s" % [rt3.name, ang2, ("BLOCKED by " + hit3) if hit3 != "" else ""])
		print("planeview: %d instruments, %d blocked" % [roots.size(), nb])
		get_tree().quit()
		return
	if _test.has("soundtest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		_get_out()
		var PK = pickup
		var WT = water_truck
		var pes: Node = PK.get_node("EngineSound")
		var wes: Node = WT.get_node("EngineSound")
		print("soundtest: engines on pickup %s (%s), water truck %s (%s)" % [pes != null, pes.kind, wes != null, wes.kind])
		print("soundtest: pickup ", PK.engine_toggle())
		for i in range(90):
			await get_tree().process_frame
		print("soundtest: pickup idle rpm %.0f, lo %.1f dB pitch %.2f, hi %.1f dB" % [PK.rpm, pes._lo.volume_db, pes._lo.pitch_scale, pes._hi.volume_db])
		print("soundtest: water ", WT.engine_toggle())
		for i in range(90):
			WT.work(1.0 / 60.0)
			await get_tree().process_frame
		var r0: float = WT.rpm
		print("soundtest: water ", WT.toggle_pto())
		for i in range(90):
			WT.work(1.0 / 60.0)
			await get_tree().process_frame
		print("soundtest: diesel idle %.0f rpm -> PTO in %.0f rpm; lo %.1f dB pitch %.2f, whine %.1f dB" % [r0, WT.rpm, wes._lo.volume_db, wes._lo.pitch_scale, wes._whine.volume_db])
		var au := get_node("Audio")
		print("soundtest: plane engine is 3D on the plane: %s, in_plane now %s" % [au._engine is AudioStreamPlayer3D, au.in_plane])
		print("soundtest: ambience %s, bus Ambient %d" % [ambience != null, AudioServer.get_bus_index("Ambient")])
		print("soundtest: machines with sound: dozers %d, excavators %d, loader %s" % [prospect.dozers.filter(func(d): return d.get_node_or_null("EngineSound") != null).size(), prospect.excavators.filter(func(d): return d.get_node_or_null("EngineSound") != null).size(), loader.get_node_or_null("EngineSound") != null])
		get_tree().quit()
		return
	if _test.has("dimtest"):
		# Overall size of each truck from its meshes, against the real thing.
		_on_start_requested(0, false)
		await get_tree().create_timer(0.5).timeout
		for veh in [pickup, water_truck]:
			if veh == null:
				continue
			var lo := Vector3(1e9, 1e9, 1e9)
			var hi := Vector3(-1e9, -1e9, -1e9)
			var inv_xf: Transform3D = (veh as Node3D).global_transform.affine_inverse()
			var stk: Array = [veh]
			while not stk.is_empty():
				var nd: Node = stk.pop_back()
				for ch in nd.get_children():
					stk.append(ch)
				if nd is MeshInstance3D and (nd as MeshInstance3D).mesh != null and not String(nd.name).contains("Mirror"):
					var mn := nd as MeshInstance3D
					var aabb: AABB = mn.mesh.get_aabb()
					for ci in range(8):
						var c: Vector3 = inv_xf * (mn.global_transform * aabb.get_endpoint(ci))
						lo = lo.min(c)
						hi = hi.max(c)
			var sz := hi - lo
			if veh == pickup:
				var stk2: Array = [veh]
				while not stk2.is_empty():
					var nd2: Node = stk2.pop_back()
					for ch2 in nd2.get_children():
						stk2.append(ch2)
					if nd2 is MeshInstance3D and (nd2 as MeshInstance3D).mesh != null:
						var ab2: AABB = (nd2 as MeshInstance3D).mesh.get_aabb()
						var top2 := -1e9
						for ci2 in range(8):
							top2 = maxf(top2, (inv_xf * ((nd2 as MeshInstance3D).global_transform * ab2.get_endpoint(ci2))).y)
						if top2 > 2.0:
							print("dimtest tall part: %s top %.2f" % [nd2.get_path(), top2])
			print("dimtest %s: length %.2f m (%.0f in), width %.2f m (%.0f in), height %.2f m (%.0f in) above ground %.2f; z %.2f..%.2f" % [veh.name, sz.z, sz.z / 0.0254, sz.x, sz.x / 0.0254, hi.y, hi.y / 0.0254, lo.y, lo.z, hi.z])
		get_tree().quit()
		return
	if _test.has("tyretest"):
		# The trucks' parts (DESIGN_NOTES 125): stock, then tyres, suspension
		# and a bigger engine through the workshop's swap.
		_on_start_requested(0, false)
		await get_tree().create_timer(0.5).timeout
		for tv in [water_truck, fuel_truck]:
			var key: String = tv.parts_key()
			var e0: Dictionary = tv.truck_estimate(PartsLib.fitted[key])
			print("tyretest %s: stock %s %.0f hp, %.0f kW, top %.1f m/s, travel %.2f, tyres %s" % [key, e0["ok"], e0["hp"], tv.body.power / 1000.0, tv.body.top_speed, tv.body.travel, tv.tyre_kind])
			for did in ["tyres_lug245", "tyres_flot", "susp_truck_air", "i6d14", "inj_hd", "turbo_d2", "ic_d", "diff_truck_617", "t_truck10"]:
				var u := PartsLib.make(did, 1.0)
				var sl := String(PartsLib.def_of(u)["slot"])
				var pl: Dictionary = PartsLib.plan_swap(u, sl, ["truck", "i6d"], PartsLib.fitted[key])
				if String(pl["why"]) != "":
					print("tyretest %s: %s -> can't: %s <-- PROBLEM" % [key, did, pl["why"]])
					continue
				PartsLib.apply_plan(key, pl)
				tv.parts_changed()
				var e1: Dictionary = tv.truck_estimate(PartsLib.fitted[key])
				print("tyretest %s: + %s -> %s %.0f hp, %.0f kW, top %.1f m/s, travel %.2f, springs x%.2f, tyres %s (r %.3f), +%.0f kg %s" % [key, did, e1["ok"], e1["hp"], tv.body.power / 1000.0, tv.body.top_speed, tv.body.travel, tv.body.spring_mul, tv.tyre_kind, tv._wr, e1["kg"], str(pl["notes"])])
			var pu := PartsLib.make("tyres_mud35", 1.0)
			print("tyretest %s: pickup tyres on a truck -> %s" % [key, PartsLib.fits(pu, "tyres", ["truck", "i6d"], PartsLib.fitted[key])])
			var cu := PartsLib.make("carb_4bbl", 1.0)
			print("tyretest %s: a carburettor on the diesel -> %s" % [key, PartsLib.fits(cu, "fuel", ["truck", "i6d"], PartsLib.fitted[key])])
		var wv: Array = _workshop_vehicles()
		print("tyretest: workshop list (if parked there): %s" % str(wv.map(func(v: Dictionary) -> String: return String(v["name"]))))
		get_tree().quit()
		return
	if _test.has("truckshot"):
		# Pictures of the trucks: outside from a few angles, and from the seat.
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		_get_out()
		hud.visible = false
		var out_dir2 := String(_test.get("out", "user://"))
		for tv in [pickup, water_truck]:
			var c: Vector3 = tv.global_position
			var up_y: float = 1.9 if tv == pickup else 3.6
			var bx: Basis = tv.global_transform.basis
			var views: Array = [
				["front34", bx * Vector3(-5.5, 1.6, -6.5) if tv == pickup else bx * Vector3(-8.0, 2.6, -9.5), Vector3(0, up_y * 0.45, 0)],
				["side", bx * Vector3(-8.0, 1.4, 0.3) if tv == pickup else bx * Vector3(-12.0, 2.2, 0.5), Vector3(0, up_y * 0.45, 0)],
				["rear34", bx * Vector3(5.0, 1.8, 6.5) if tv == pickup else bx * Vector3(7.0, 2.8, 9.0), Vector3(0, up_y * 0.45, 0)],
			]
			for v in views:
				var eye: Vector3 = c + v[1]
				var tgt: Vector3 = c + v[2]
				_eco_xf = Transform3D.IDENTITY.looking_at((tgt - eye).normalized(), Vector3.UP)
				_eco_xf.origin = eye
				_eco_on = true
				cam.global_transform = _eco_xf
				cam.fov = 50.0
				for i in range(4):
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir2, tv.name, v[0]])
			# from the driver's eye, looking a little down at the dash
			var ex: Transform3D = tv.eye_xf()
			var fwd2: Vector3 = -ex.basis.z
			var look2 := (fwd2 * cos(0.3) - Vector3.UP * sin(0.3)).normalized()
			_eco_xf = Transform3D.IDENTITY.looking_at(look2, Vector3.UP)
			_eco_xf.origin = ex.origin
			cam.global_transform = _eco_xf
			cam.fov = 74.0
			cam.near = 0.05
			for i in range(4):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_dash.png" % [out_dir2, tv.name])
		get_tree().quit()
		return
	if _test.has("nodelist"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.5).timeout
		var stk: Array = [[get_tree().root, 0]]
		while not stk.is_empty():
			var e: Array = stk.pop_back()
			var nd: Node = e[0]
			var dp: int = e[1]
			if nd is Node3D and dp <= 4:
				print("NODE %s%s %s %s" % ["  ".repeat(dp), nd.name, nd.get_class(), (nd as Node3D).global_position.snapped(Vector3.ONE)])
			if dp < 4:
				for c in nd.get_children():
					stk.append([c, dp + 1])
		get_tree().quit()
		return
	if _test.has("wintershot"):
		await _winter_shots()
		get_tree().quit()
		return
	if _test.has("lookshot"):
		await _look_shots()
		get_tree().quit()
		return
	if _test.has("assetshot"):
		await _asset_shots()
		get_tree().quit()
		return
	if _test.has("scaletest"):
		# Every vehicle's size from its meshes, and the pilot's height, so they
		# can be checked against the real things and each other.
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		_get_out()
		await get_tree().create_timer(0.3).timeout
		var things: Array = [["pilot", walker.model], ["pickup", pickup], ["water_truck", water_truck], ["loader", loader], ["plane", visual]]
		for dz2 in prospect.dozers:
			things.append(["dozer", dz2])
		if prospect.excavators.is_empty():
			prospect._spawn_excavator(Transform3D(Basis.IDENTITY, walker.global_position + Vector3(12, 0, 0)))
		for ex2 in prospect.excavators:
			things.append(["excavator", ex2])
		if not forklifts.is_empty():
			things.append(["forklift", forklifts[0]])
		if dc3_vis != null:
			things.append(["dc3", dc3_vis])
		for th in things:
			var nd0: Node3D = th[1]
			if nd0 == null:
				continue
			var inv0: Transform3D = nd0.global_transform.affine_inverse()
			var lo0 := Vector3(1e9, 1e9, 1e9)
			var hi0 := Vector3(-1e9, -1e9, -1e9)
			var st0: Array = [nd0]
			while not st0.is_empty():
				var n0: Node = st0.pop_back()
				for c0 in n0.get_children():
					st0.append(c0)
				if n0 is MeshInstance3D and (n0 as MeshInstance3D).mesh != null and (n0 as MeshInstance3D).is_visible_in_tree() and not String(n0.name).contains("Precip"):
					var ab: AABB = (n0 as MeshInstance3D).get_aabb()
					for ci in range(8):
						var cp: Vector3 = inv0 * ((n0 as MeshInstance3D).global_transform * ab.get_endpoint(ci))
						lo0 = lo0.min(cp)
						hi0 = hi0.max(cp)
			if lo0.x > 1e8:
				print("scaletest %s: no meshes" % th[0])
				continue
			var sz0 := hi0 - lo0
			print("scaletest %-12s length %5.2f m  width %5.2f m  height %5.2f m  (top %.2f, bottom %.2f)" % [th[0], sz0.z, sz0.x, sz0.y, hi0.y, lo0.y])
		get_tree().quit()
		return
	if _test.has("parktest"):
		_on_start_requested(0, false)
		var tp = world.terrain
		for pk in range(3):
			await get_tree().create_timer(2.0).timeout
			for se in world.sale_planes:
				var sp: Node3D = se["node"]
				if not is_instance_valid(sp):
					continue
				var lowp := 1.0e9
				for wi in range(3):
					var wp: Vector3 = sp.pos + sp.b * (sp.wheel_pos[wi] - sp.cg)
					lowp = minf(lowp, wp.y - tp.ground_level_at(wp.x, wp.z))
				print("parktest t=%d %s %s: lowest wheel %.2f m off ground, speed %.2f, pitch %.1f, step %.2f ms %s" % [(pk + 1) * 2, se["type"], sp.name, lowp, sp.vel.length(), rad_to_deg(sp.pitch_rad()), sp.perf_ms, "OK" if absf(lowp) < 0.15 else "<-- check"])
		get_tree().quit()
		return
	if _test.has("pittest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		if not on_foot:
			_get_out()
		var t = world.terrain
		var c := Vector3(40, 0, 20)
		var deep := OS.has_environment("DEEPPIT")
		for i in range(60 if deep else 14):
			for o in ([Vector3.ZERO, Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5), Vector3(0, 0, -1.5)] if deep else [Vector3.ZERO, Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5), Vector3(2.5, 0, 2.5), Vector3(-2.5, 0, -2.5), Vector3(2.5, 0, -2.5), Vector3(-2.5, 0, 2.5)]):
				var q: Vector3 = c + o
				q.y = t.height_at(q.x, q.z)
				t.dig(q, 1.6, 0.6, 1.0)
		print("pittest: pit floor %.1f m below the rim (%.2f vs %.2f)" % [t.height_at(c.x + 6, c.z) - t.height_at(c.x, c.z), t.height_at(c.x, c.z), t.height_at(c.x + 6, c.z)])
		var dz: Node3D = prospect._spawn_dozer(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(c.x + 12, t.height_at(c.x + 12, c.z), c.z)))
		var vehicles: Array = [dz, pickup]
		pickup.park(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(c.x - 14, t.height_at(c.x - 14, c.z), c.z)))
		pickup.engine_on = true
		for v in vehicles:
			_get_on_forklift(v)
			var worst := 0.0
			var worst_cam := 0.0
			for i in range(int(9.0 * 120)):
				_drive_forklift(1.0 / 120.0, Vector2(0, 1) if i < 6 * 120 else Vector2.ZERO)
				var b = v.body
				for lc in b._hull:
					var hp: Vector3 = b.pos + b.basis * (lc as Vector3)
					worst = maxf(worst, t.height_at(hp.x, hp.z) - hp.y)
				var ep: Vector3 = v.eye_xf().origin
				worst_cam = maxf(worst_cam, t.height_at(ep.x, ep.z) - ep.y)
				if i % 120 == 0:
					await get_tree().process_frame
			print("pittest: %s: ends at %s (%.1f m from the pit centre), deepest hull point %.2f m into the ground, driver's eye %.2f m under it, tilt %.0f, last hit %.1f m/s" % [String(v.get_script().resource_path).get_file(), str(v.global_position.round()), Vector2(v.global_position.x - c.x, v.global_position.z - c.z).length(), worst, worst_cam, v.body.tilt_deg, v.body.last_hit])
			_get_off_forklift()
		get_tree().quit()
		return
	if _test.has("wtest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		if not on_foot:
			_get_out()
		var W: Node3D = water_truck
		W.tank_m3 = 5.0
		var p0: Vector3 = W.global_position
		_get_on_forklift(W)
		var m1: String = ""
		for i in range(120):
			var mm: String = W.drive(1.0 / 60.0, Vector2(0, 1), false)
			if mm != "":
				m1 = mm
		print("wtest: engine off, throttle 2 s: moved %.2f m, said '%s'" % [W.global_position.distance_to(p0), m1])
		print("wtest: ", W.engine_toggle())
		print("wtest: ", W.toggle_pto())
		var m2 := ""
		for i in range(120):
			var mm2: String = W.drive(1.0 / 60.0, Vector2(0, 1), false)
			if mm2 != "":
				m2 = mm2
		print("wtest: running, 2 s: air %.0f psi, rpm %.0f, moved %.2f m, said '%s'" % [W.air_psi, W.rpm, W.global_position.distance_to(p0), m2])
		for i in range(600):
			W.drive(1.0 / 60.0, Vector2.ZERO, false)
		var p1: Vector3 = W.global_position
		for i in range(240):
			W.drive(1.0 / 60.0, Vector2(0, 1), false)
		print("wtest: air %.0f psi after 12 s; 4 s of throttle: moved %.1f m at %.1f mph, rpm %.0f, coolant %.0f F, oil %.0f psi" % [W.air_psi, W.global_position.distance_to(p1), absf(W.body.speed) * 2.237, W.rpm, W.coolant_f, W.oil_psi])
		for i in range(300):
			W.drive(1.0 / 60.0, Vector2(0, -1), true)
		var t0: float = W.tank_m3
		print("wtest: ", W.toggle_valve(3), " ", W.toggle_valve(4))
		for i in range(120):
			W.drive(1.0 / 60.0, Vector2.ZERO, true)
		print("wtest: rear sprays 2 s: used %.1f gal, jets on %s, pump %.0f psi" % [(t0 - W.tank_m3) * 264.17, W._jets[3][0].emitting, W.pump_psi])
		W.toggle_valve(3)
		W.toggle_valve(4)
		_get_off_forklift()
		var rp: Vector3 = W.global_transform * W.REEL
		print("wtest: at the reel: %s" % str(W.foot_target(rp, "E")))
		print("wtest: ", W.foot_act("truck_hose", rp))
		var t1: float = W.tank_m3
		W.hose_hand = rp + Vector3(0, 0.2, 2.0)
		W.hose_aim = Vector3(0, 0.2, 1).normalized()
		W.pto = false
		print("wtest: nozzle with the pump off (should switch it on) -> ", W.foot_act("truck_nozzle", rp))
		var mp: Vector3 = W.global_transform * W.MANIFOLD
		W.nozzle_open = false
		W.hose_out = false
		print("wtest: at the pump box: %s" % str(W.foot_target(mp + Vector3(0.0, 0, 0.6), "E")))
		W.hose_out = true
		print("wtest: nozzle -> ", W.foot_act("truck_nozzle", rp))
		for i in range(120):
			W.work(1.0 / 60.0)
		print("wtest: hose 2 s: used %.1f gal, jet %s, hose lies %d points, end %.1f m from the reel, leash at 30 m -> %.1f m" % [(t1 - W.tank_m3) * 264.17, W._hose_jet.emitting, W._hose.points().size(), W._hose.end_b().distance_to(W.global_transform * W.REEL), Vector2(W.hose_leash(rp + Vector3(30, 0, 0)).x - rp.x, W.hose_leash(rp + Vector3(30, 0, 0)).z - rp.z).length()])
		print("wtest: ", W.reel_in(), " ", W.status())
		get_tree().quit()
		return
	if _test.has("gentest"):
		var t = world.terrain
		var L: Dictionary = t.lay()
		var vn: int = t.FN + 1
		var pay_cells := 0
		var best := 0.0
		var best_at := Vector2.ZERO
		var sum := 0.0
		for gk in range(vn * vn):
			var g: float = t.grade[gk]
			if g > 0.05:
				pay_cells += 1
				sum += g
			if g > best:
				best = g
				best_at = Vector2(-t.SQ + (gk % vn) * t.FRES, -t.SQ + (gk / vn) * t.FRES)
		var pad: Vector2 = L["pad"]
		var pad_g := 0.0
		for dz in range(-10, 11, 2):
			for dx in range(-10, 11, 2):
				pad_g = maxf(pad_g, float(t.geology(pad.x + dx, pad.y + dz)[0]))
		print("gentest: seed %d: pay under %.0f%% of the square, mean %.2f g/m3, best %.1f g/m3 at %s, best within 10 m of the pad %.1f g/m3" % [L["seed"], 100.0 * pay_cells / float(vn * vn), sum / maxf(pay_cells, 1), best, str(best_at.round()), pad_g])
		# inside vs outside of bends on the main channel
		var ch: Dictionary = L["channels"][0]
		var ins := 0.0
		var outs := 0.0
		var ni := 0
		var no := 0
		var pts: Array = ch["pts"]
		for bi in range(1, pts.size() - 2):
			var d0: Vector2 = pts[bi] - pts[bi - 1]
			var d1: Vector2 = pts[bi + 2] - pts[bi + 1]
			var cv: float = d0.normalized().cross(d1.normalized())
			if absf(cv) < 0.1:
				continue
			var a: Vector2 = pts[bi]
			var b: Vector2 = pts[bi + 1]
			var side := Vector2(-(b - a).normalized().y, (b - a).normalized().x)
			var off: float = float(ch["w"]) * 0.6
			var gi: float = t.geology((a + b).x * 0.5 + side.x * off * signf(cv), (a + b).y * 0.5 + side.y * off * signf(cv))[0]
			var go: float = t.geology((a + b).x * 0.5 - side.x * off * signf(cv), (a + b).y * 0.5 - side.y * off * signf(cv))[0]
			ins += gi
			outs += go
			ni += 1
		print("gentest: main channel bends: inside %.2f g/m3 vs outside %.2f g/m3 on average (%d bends)" % [ins / maxf(ni, 1), outs / maxf(ni, 1), ni])
		var pond: Dictionary = t.lakes[0]
		var pc: Vector2 = pond["pos"]
		print("gentest: pond at %s holds water %s; creek mouth %s from the pond; knoll top %.1f m" % [str(pc.round()), t.water_level_at(pc.x, pc.y) > -1.0e8, str(int((L["creek"].back() as Vector2).distance_to(pc))) + " m", t.height_at(L["knoll"][0].x, L["knoll"][0].y)])
		get_tree().quit()
		return
	if _test.has("firetest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		Game.season = int(_test.get("season", Game.SUMMER))
		Game.weather = 0
		wind.base_speed = float(_test.get("wind", 6.0))
		wind.base_dir = Vector3(1, 0, 0)
		var fp := Vector3(20, 0, 0)
		print("firetest: season %d, dryness %.2f, wind %.0f m/s" % [Game.season, fire._dryness(), wind.base_speed])
		var felled0: int = Flora.felled.size()
		print("firetest: fuel at the forest spot %.2f, on the strip %.2f, in the bog %.2f" % [fire.fuel[fire._index(fp)], fire.fuel[fire._index(Vector3(0, 0, -130))], fire.fuel[fire._index(Vector3(150, 0, 150))]])
		var fuelled := 0
		var ok := 0
		var muddy := 0
		for fk0 in range(0, fire.n * fire.n, 7):
			if fire.fuel[fk0] < 0.05:
				continue
			fuelled += 1
			if fire._burnable_now(fk0):
				ok += 1
			var c0: Vector3 = fire._centre(fk0 % fire.n, fk0 / fire.n)
			if world.terrain.mud_at(c0.x, c0.z) > 0.3:
				muddy += 1
		print("firetest: of %d patches with fuel, %d will burn now (%d are muddy)" % [fuelled, ok, muddy])
		print("firetest: ignite -> %s" % fire.ignite(fp, 4.0))
		Engine.time_scale = 4.0
		var t0 := Time.get_ticks_msec()
		var worst := 0
		for fi in range(240):
			var a := Time.get_ticks_usec()
			fire._tick(0.25)
			worst = maxi(worst, Time.get_ticks_usec() - a)
			if fi % 40 == 0:
				var cx := 0.0
				for fk in fire.active:
					cx += fire._centre(fk % fire.n, fk / fire.n).x
				print("firetest: t %3.0f s burning %d, burnt %d, trees down %d, fire centre x %.0f" % [fi * 0.25, fire.active.size(), Array(fire.burnt).count(1), Flora.felled.size() - felled0, cx / maxf(fire.active.size(), 1.0)])
			await get_tree().process_frame
		Engine.time_scale = 1.0
		print("firetest: worst tick %.2f ms" % (worst / 1000.0))
		var b0: int = fire.active.size()
		var out := 0
		for fk2 in fire.active.duplicate():
			out += fire.douse(fire._centre(fk2 % fire.n, fk2 / fire.n), 3.0)
		print("firetest: hosed it: put out %d of %d, still burning %d" % [out, b0, fire.active.size()])
		Game.season = Game.WINTER
		print("firetest: winter ignite elsewhere -> %s" % fire.ignite(Vector3(-60, 0, 40), 4.0))
		for fi in range(480):
			fire._tick(0.25)
			if fi % 80 == 79:
				var thawed := 0
				for mv in fire.melt:
					if mv >= 0.99:
						thawed += 1
				print("firetest: winter t %3.0f s: burning %d, burnt %d, thawed %d" % [(fi + 1) * 0.25, fire.active.size(), Array(fire.burnt).count(1), thawed])
		get_tree().quit()
		return
	if _test.has("crafttest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		var bp: Vector3 = crafting.BENCH
		bp.y = world.terrain.height_at(bp.x, bp.z)
		jobs.money = 1000
		builds.logs = 0
		print("crafttest: at the bench: %s" % str(prospect.target(bp, bp)[1]))
		print("crafttest: no logs -> %s" % prospect.act("craft", bp, bp))
		builds.add_logs(10)
		for i in range(4):
			print("crafttest: %s -> %s" % [crafting.RECIPES[crafting.pick][1], prospect.act("craft", bp, bp)])
			print("crafttest: next: %s" % crafting.next_recipe())
		prospect.gold_g = 130.0
		print("crafttest: bar -> %s" % prospect.act("craft", bp, bp))
		print("crafttest: logs %d, money %d, sluices %d, timber %d, ladder %d, rope %d, bars %d, gold %.0f g" % [builds.logs, jobs.money, prospect.owned_sluices, inv.count("timber"), inv.count("ladder"), inv.count("rope_light"), inv.count("gold_bar"), prospect.gold_g])
		print("crafttest: sell -> %s" % prospect.sell_gold())
		get_tree().quit()
		return
	if _test.has("findtest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		var said: Array = []
		prospect.hud = null
		var old_say = prospect.get("_say")
		var g0: float = prospect.gold_g
		var dug := 0.0
		var spots := [Vector3(80, 0, 60), Vector3(84, 0, 60), Vector3(80, 0, 64), Vector3(84, 0, 64)]
		for i in range(400):
			var sp: Vector3 = spots[i % 4]
			sp.y = world.terrain.height_at(sp.x, sp.z)
			var got: Dictionary = prospect.dig(sp, 1.2, 0.1)
			dug += float(got.get("over", 0.0)) + float(got.get("pay", 0.0))
		var finds := {}
		for id in prospect.FINDS.keys():
			finds[id] = inv.count(id)
		var on_ground := 0
		for e in inv.world_items:
			if prospect.FINDS.has(String(e["id"])):
				on_ground += 1
		print("findtest: dug %.1f m3, down to %.1f m; finds carried %s, %d on the ground; nugget gold %.1f g" % [dug, world.terrain.natural_at(80, 60) - world.terrain.height_at(80, 60), str(finds), on_ground, prospect.gold_g - g0])
		print("findtest: sell -> %s" % prospect.sell_gold())
		get_tree().quit()
		return
	if _test.has("powertest"):
		await _power_test()
		get_tree().quit()
		return
	if _test.has("loadtest"):
		await _loader_test()
		get_tree().quit()
		return
	if _test.has("gastest"):
		await _gas_test()
		get_tree().quit()
		return
	if _test.has("feedtest"):
		await _feed_test()
		get_tree().quit()
		return
	if _test.has("deepdoz"):
		await _deep_doz_test()
		get_tree().quit()
		return
	if _test.has("machtest"):
		await _mach_test()
		get_tree().quit()
		return
	if _test.has("spottest"):
		await _spot_test()
		get_tree().quit()
		return
	if _test.has("doortest"):
		await _door_test()
		get_tree().quit()
		return
	if _test.has("birdtest"):
		await _bird_test()
		get_tree().quit()
		return
	if _test.has("spotmud"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		for v in [water_truck, pickup, loader]:
			var gp: Vector3 = v.global_position
			print("spotmud %s at %s: mud %.2f (summer base), spring %.2f" % [v.name, gp.snapped(Vector3.ONE), world.terrain.mud_at(gp.x, gp.z), world.terrain.mud_base_at(gp.x, gp.z) * 1.3])
		get_tree().quit()
		return
	if _test.has("partstest"):
		await _parts_test()
		get_tree().quit()
		return
	if _test.has("dieseltest"):
		await _diesel_test()
		get_tree().quit()
		return
	if _test.has("lowtest"):
		_low_test()
		return
	if _test.has("fueltest"):
		_fuel_test()
		return
	if _test.has("swaptest"):
		_swap_test()
		return
	if _test.has("rattletest"):
		_rattle_test()
		return
	if _test.has("mudtest"):
		await _mud_test()
		get_tree().quit()
		return
	if _test.has("trucktest"):
		await _truck_test()
		get_tree().quit()
		return
	if _test.has("kindtest"):
		await _build_kinds_test()
		get_tree().quit()
		return
	if _test.has("trailer"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		var tr: Node = load("res://scripts/trailer.gd").new()
		tr.m = self
		tr.out_dir = String(_test.get("out", ""))
		add_child(tr)
		await tr.run(String(_test.get("shot", "title")))
		return
	if _test.has("tugtest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		for e in plane.engines():
			e.stop()
		_get_out()
		var tp: Vector3 = tug.tail_point(plane)
		var pb: Basis = plane.global_transform.basis
		# park the tug past the tail, facing away from the plane
		var away := Vector3(pb.z.x, 0, pb.z.z).normalized()
		var tat: Vector3 = tp + away * (tug.BAR + 1.3)
		tug.park(Transform3D(Basis(Vector3.UP, atan2(-away.x, -away.z)), Vector3(tat.x, world.terrain.ground_level_at(tat.x, tat.z), tat.z)))
		walker.place(tug.global_transform * Vector3(0, 0, 0.5), 0.0)
		await get_tree().process_frame
		print("tugtest: near the tug -> %s" % (_forklift_near() == tug))
		_get_on_forklift(tug)
		print("tugtest: hitch to tail %.1f m: %s" % [Vector2(tug.hitch_point().x - tp.x, tug.hitch_point().z - tp.z).length(), tug.can_hook()])
		print("tugtest: %s" % tug.tow_toggle())
		var p0: Vector3 = plane.global_position
		var y0: float = tug._yaw_of(plane.global_transform.basis)
		for i in range(60 * 6):
			tug.drive(1.0 / 60.0, Vector2(0.0 if i < 120 else 0.7, 1.0))
			await get_tree().physics_frame
		var moved: float = plane.global_position.distance_to(p0)
		var turned: float = rad_to_deg(wrapf(tug._yaw_of(plane.global_transform.basis) - y0, -PI, PI))
		var bar: float = tug.hitch_point().distance_to(tug.tail_point(plane))
		print("tugtest: 6 s pulling (turning the last 4): plane moved %.1f m, turned %.0f deg, bar pin-to-tailwheel %.2f m (bar %.1f), plane up %.2f m, crashed %s %s" % [moved, turned, bar, tug.BAR, plane.global_position.y - p0.y, plane.is_crashed, "" if moved > 3.0 and absf(bar - tug.BAR) < 0.6 else "<-- PROBLEM"])
		for i in range(60 * 3):
			tug.drive(1.0 / 60.0, Vector2(0.0, -1.0))
			await get_tree().physics_frame
		print("tugtest: backed up 3 s: plane now %.1f m from the start" % plane.global_position.distance_to(p0))
		for i in range(30):
			tug.drive(1.0 / 60.0, Vector2.ZERO)
			await get_tree().physics_frame
		print("tugtest: %s, plane frozen %s" % [tug.tow_toggle(), plane.frozen])
		get_tree().quit()
		return
	if _test.has("touchtest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		Game.touch_mode = 1
		await get_tree().process_frame
		await get_tree().process_frame
		var sz: Vector2 = get_viewport().get_visible_rect().size
		print("touchtest: visible %s, %d buttons: %s" % [touch.visible, touch._buttons.size(), str(touch._buttons.map(func(b): return b[1]))])
		var send := func(ev: InputEvent) -> void: touch._input(ev)
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = Vector2(sz.x * 0.14, sz.y * 0.72)
		t.pressed = true
		send.call(t)
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = t.position + Vector2(40, -60)
		send.call(d)
		await get_tree().process_frame
		print("touchtest: stick up-right -> pitch_down %.2f roll_right %.2f" % [Input.get_action_strength("pitch_down"), Input.get_action_strength("roll_right")])
		var tr: Rect2 = touch._thr_rect()
		var t2 := InputEventScreenTouch.new()
		t2.index = 1
		t2.position = tr.position + Vector2(tr.size.x * 0.5, tr.size.y * 0.25)
		t2.pressed = true
		send.call(t2)
		await get_tree().process_frame
		print("touchtest: throttle slider 3/4 up -> plane throttle %.2f" % plane.throttle)
		t.pressed = false
		send.call(t)
		t2.pressed = false
		send.call(t2)
		await get_tree().process_frame
		print("touchtest: released -> pitch_down %.2f" % Input.get_action_strength("pitch_down"))
		plane.throttle = 0.0
		for b in touch._buttons:
			if b[0] == "exit":
				var t3 := InputEventScreenTouch.new()
				t3.index = 2
				t3.position = (b[3] as Rect2).get_center()
				t3.pressed = true
				send.call(t3)
				await get_tree().process_frame
				t3.pressed = false
				send.call(t3)
		for i in range(10):
			await get_tree().process_frame
		print("touchtest: OUT button -> on foot %s, buttons now %s" % [on_foot, str(touch._buttons.map(func(b): return b[1]))])
		Game.touch_mode = 0
		get_tree().quit()
		return
	if _test.has("dc3roll"):
		await _dc3_roll_test()
		get_tree().quit()
		return
	if _test.has("seattest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		_get_out()
		_get_on_forklift(pickup)
		walker.first_person = false
		for i in range(20):
			_drive_forklift(1.0 / 60.0, Vector2.ZERO)
			await get_tree().physics_frame
		var lp: Vector3 = pickup.global_transform.affine_inverse() * walker.global_position
		var shown := 0
		var shadow_only := 0
		for mi in walker.model.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				shadow_only += 1
			elif (mi as MeshInstance3D).is_visible_in_tree():
				shown += 1
		var eye: Vector3 = pickup.global_transform.affine_inverse() * (walker.global_transform * (walker.model.eye_local() as Vector3))
		print("seattest: walker visible %s, in the pickup at %s (local), eye at %s vs cab eye %s, meshes shown %d, shadow-only %d, model %s" % [walker.is_visible_in_tree(), lp, eye, pickup.global_transform.affine_inverse() * pickup.eye_xf().origin, shown, shadow_only, walker.model.get_class()])
		get_tree().quit()
		return
	if _test.has("baseshot"):
		# pictures of the home base buildings (DESIGN_NOTES 147)
		var od := String(_test.get("out", "/tmp/shots"))
		for i in range(int(_test.get("wait", "200"))):
			await get_tree().process_frame
		var sts2: Node3D = world.structures
		var o: Transform3D = sts2.items["office"]["xf"]
		var b2: Transform3D = sts2.items["bunkhouse"]["xf"]
		var sh: Transform3D = sts2.items["shop"]["xf"]
		await _shot_at(o * Vector3(-9.0, 4.5, -16.0), o * Vector3(4.0, 2.0, 0.0), od + "/base_front.png")
		await _shot_at(b2 * Vector3(10.0, 5.0, -12.0), b2 * Vector3(0, 2.0, 0), od + "/base_cabin.png")
		await _shot_at(sh * Vector3(-12.0, 5.0, -18.0), sh * Vector3(0, 3.0, 0), od + "/base_shop.png")
		await _shot_at(o * Vector3(-3.0, 1.65, -2.5), o * Vector3(3.0, 0.9, 3.0), od + "/office_in.png")
		var wc: Transform3D = sts2.items["woods_cabin"]["xf"]
		await _shot_at(wc * Vector3(-7.0, 3.0, -11.0), wc * Vector3(0, 2.0, 0), od + "/woods_cabin.png")
		get_tree().quit()
		return
	if _test.has("railtest"):
		# DESIGN_NOTES 151: lay track, a car on it, fill it, run it along, tip it
		Game.sandbox = true
		_get_out()
		await get_tree().create_timer(0.5).timeout
		var st6 := Vector3(-20.0, 0, -108.0)
		walker.place(st6, -PI * 0.5)
		print("railtest: add rail -> %d, in hand '%s', kg %.0f" % [inv.add("rail", 1, true), inv.in_hand(), inv.weight()])
		rails.find_target()
		print("railtest: prompt '%s'" % rails.prompt)
		for n6 in range(4):
			inv.add("rail", 1, true)
			rails.find_target()
			var e6: Array = rails._end_near(walker.global_position, 2.5)
			print("railtest: ", rails.lay(walker.global_position if e6.is_empty() else e6[0], Vector3(1, 0, 0.1 * float(n6))))
			walker.place((rails.segs.back()[1] as Vector3), -PI * 0.5)
		print("railtest: %d sections, ends %s .. %s" % [rails.segs.size(), str(rails.segs[0][0]), str(rails.segs.back()[1])])
		print("railtest: ", rails.buy_car(rails.segs[0][0], jobs))
		var car: Dictionary = rails.cars[0]
		for n7 in range(7):
			print("railtest: ", rails.load_near(rails._car_pos(car), "pay" if n7 % 2 == 0 else "over", 3.0))
		car["v"] = 1.4
		for i6 in range(600):
			await get_tree().physics_frame
		print("railtest: car on section %d at %.1f m, v %.2f, at %s" % [int(car["seg"]), float(car["s"]), float(car["v"]), str(rails._car_pos(car))])
		walker.place(rails._car_pos(car) + Vector3(0, 0, 1.0), 0.0)
		rails.find_target()
		print("railtest: prompt '%s'" % rails.prompt)
		print("railtest: tip: %s" % str(rails.interact(Vector3.FORWARD)))
		print("railtest: load now %s" % str(car["load"]))
		get_tree().quit()
		return
	if _test.has("stucktest"):
		# DESIGN_NOTES 150: an excavator in a pit drives and levers itself out
		Game.sandbox = true
		var t5: RefCounted = world.terrain
		_get_out()
		var c5 := Vector3(20.0, 0.0, 15.0)
		for k5 in range(500):
			var a5 := k5 * 0.61
			var r5 := 0.4 + (k5 % 50) * 0.11
			prospect.dig(c5 + Vector3(cos(a5) * r5, 0, sin(a5) * r5), 1.6, 0.5)
		c5.y = t5.height_at(c5.x, c5.z)
		print("stucktest: pit floor %.2f, natural %.2f" % [c5.y, t5.natural_at(c5.x, c5.z)])
		var ex5: Node3D = prospect._spawn_excavator(Transform3D(Basis(Vector3.UP, -PI * 0.5), c5))
		_get_on_forklift(ex5)
		var y0: float = ex5.global_position.y
		var p05: Vector3 = ex5.global_position
		for i in range(int(float(_test.get("secs", "30")) * 60.0)):
			ex5.drive(1.0 / 60.0, Vector2(0, 1))
			if i % 300 == 0:
				print("stucktest: t %2.0f  y %.2f  moved %.1f  stuck %.1f  rescue %s" % [float(i) / 60.0, ex5.global_position.y - y0, Vector2(ex5.global_position.x - p05.x, ex5.global_position.z - p05.z).length(), ex5._stuck_t, ex5._rescue])
			await get_tree().physics_frame
		print("stucktest: climbed %.2f m, moved %.1f m; ground there %.2f vs natural %.2f" % [ex5.global_position.y - y0, Vector2(ex5.global_position.x - p05.x, ex5.global_position.z - p05.z).length(), ex5.global_position.y, t5.natural_at(ex5.global_position.x, ex5.global_position.z)])
		get_tree().quit()
		return
	if _test.has("tugtrailer"):
		# DESIGN_NOTES 149: the tug hitches the log trailer and pulls it
		_get_out()
		await get_tree().create_timer(0.5).timeout
		var lt: Node3D = log_trailer
		var tp0: Vector3 = lt.tongue_point()
		var ax: Vector3 = lt.global_transform * Vector3(lt.axle_local.x, 0, lt.axle_local.z)
		var d := Vector3(tp0.x - ax.x, 0, tp0.z - ax.z).normalized()
		var org: Vector3 = tp0 + d * 1.56
		tug.park(Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), org))
		_get_on_forklift(tug)
		print("tugtrailer: prompt '%s'" % tug.prompt())
		print("tugtrailer: %s" % tug.tow_toggle())
		var a0: Vector3 = lt.global_position
		for i in range(300):
			tug.drive(1.0 / 60.0, Vector2(0.3 if i > 150 else 0.0, 1.0))
			await get_tree().physics_frame
		print("tugtrailer: trailer moved %.1f m, hook to tongue %.2f m" % [lt.global_position.distance_to(a0), tug.hitch_point().distance_to(lt.tongue_point())])
		for i in range(60):
			tug.drive(1.0 / 60.0, Vector2(0, 0))
			await get_tree().physics_frame
		print("tugtrailer: %s" % tug.tow_toggle())
		get_tree().quit()
		return
	if _test.has("minertest"):
		# DESIGN_NOTES 148: the drift miner drives a decline into flat ground
		Game.sandbox = true
		var t3: RefCounted = world.terrain
		var vg3: Node = world.ground_view
		_get_out()
		var c3 := Vector3(20.0, 0.0, 15.0)
		c3.y = t3.height_at(c3.x, c3.z)
		walker.place(c3 + Vector3(-6, 0, 0), -PI * 0.5)
		for i in range(240):
			await get_tree().physics_frame
			if vg3 != null and vg3.ready_at(c3):
				break
		var tn: Node3D = prospect._spawn_tunneler(Transform3D(Basis(Vector3.UP, -PI * 0.5), c3))
		_get_on_forklift(tn)
		print("minertest: on %s, prompt '%s'" % [driving == tn, tn.status()])
		print("minertest: ", tn.machine_action())
		tn.grade = float(_test.get("grade", "-0.25"))
		var p0: Vector3 = tn.global_position
		var secs := float(_test.get("secs", "40"))
		var steps := int(secs * 60.0)
		var last := ""
		for i in range(steps):
			var m: String = tn.drive(1.0 / 60.0, Vector2(0, 1), 0.0)
			if m != "" and m != last:
				print("minertest: msg '%s'" % m)
				last = m
			if i % 120 == 0 and i > 400 and i < 1300:
				var fw3: Vector3 = -tn.global_transform.basis.z
				var fp: Vector3 = tn.global_position + fw3 * 1.85 + Vector3(0, 0.6, 0)
				print("minertest:   speed %.2f  blocked-front %s  floor-here %.2f  floor-ahead %.2f  sdf ahead y+1 %.2f" % [tn.speed, tn._blocked(fp), tn._floor(tn.global_position.x, tn.global_position.z), tn._floor(fp.x, fp.z), vg3.sdf_at(Vector3(fp.x, tn.global_position.y + 1.0, fp.z)) if vg3 != null else 0.0])
			if i % 120 == 0 and i > 400 and i < 1300:
				var fw3: Vector3 = -tn.global_transform.basis.z
				var fp: Vector3 = tn.global_position + fw3 * 1.85 + Vector3(0, 0.6, 0)
				print("minertest:   speed %.2f  blocked-front %s  floor-here %.2f  floor-ahead %.2f  sdf ahead y+1 %.2f  y+1.8 %.2f" % [tn.speed, tn._blocked(fp), tn._floor(tn.global_position.x, tn.global_position.z), tn._floor(fp.x, fp.z), vg3.sdf_at(Vector3(fp.x, tn.global_position.y + 1.0, fp.z)), vg3.sdf_at(Vector3(fp.x, tn.global_position.y + 1.8, fp.z))])
			if i % 600 == 0:
				var q: Vector3 = tn.global_position
				print("minertest: t %4.0f s  moved %.1f m  y %.2f (ground %.2f)  bite %.2f  resist %.2f  tub %.2f" % [float(i) / 60.0, Vector2(q.x - p0.x, q.z - p0.z).length(), q.y, t3.height_at(q.x, q.z), tn._bite, tn._resist, float(tn.tub.get("pay", 0.0))])
			await get_tree().physics_frame
		var q2: Vector3 = tn.global_position
		print("minertest: after %.0f s: moved %.1f m, down %.2f m, %.2f m under the natural surface, tub %s, roofs %d" % [secs, Vector2(q2.x - p0.x, q2.z - p0.z).length(), p0.y - q2.y, t3.height_at(q2.x, q2.z) - q2.y, str(tn.tub), prospect.roofs.size()])
		get_tree().quit()
		return
	if _test.has("structtest"):
		# DESIGN_NOTES 147: the buildings stand, you start inside, the stove
		# works, a building burns down and leaves a ruin you can walk through.
		await get_tree().create_timer(0.5).timeout
		var sts: Node3D = world.structures
		print("structtest: ", sts.items.size(), " structures: ", ", ".join(PackedStringArray(sts.items.keys())))
		print("structtest: woods cabin at ", world.woods_cabin)
		print("structtest: on foot %s, inside '%s', walker %s" % [on_foot, sts.inside(walker.global_position), walker.global_position])
		var it: Dictionary = sts.items["office"]
		print("structtest: office stove lit %s fuel %.0f box %d, smoke emitting %s" % [it["stove"]["lit"], it["stove"]["fuel"], it["stove"]["box"], (it["stove"]["smoke"] as CPUParticles3D).emitting])
		walker.place(sts._stove_front(it), 0.0)
		sts.find_target()
		print("structtest: at the stove: '%s'" % sts.prompt)
		var f0: float = it["stove"]["fuel"]
		sts.interact()
		print("structtest: after load: fuel %.0f -> %.0f, box %d" % [f0, it["stove"]["fuel"], it["stove"]["box"]])
		var pile: Dictionary = sts.items["office_wood"]
		walker.place((pile["xf"] as Transform3D).origin + Vector3(0, 0, -1.2), 0.0)
		sts.find_target()
		print("structtest: at the woodpile: '%s'" % sts.prompt)
		sts.interact()
		print("structtest: carrying %d" % sts.carrying_wood)
		var bh: Dictionary = sts.items["bunkhouse"]
		var hol0: int = world.terrain.hollows.size()
		var sol0: int = world.terrain.solids.size()
		sts.set_on_fire("bunkhouse", 0.5)
		var bt := 0.0
		while not bool(bh["burnt"]) and bt < 900.0:
			sts._burn_step("bunkhouse", bh, 0.5, Vector3.ZERO)
			bt += 0.5
		print("structtest: bunkhouse burnt %s after %.0f s, fires %d, hollows %d -> %d, solids %d -> %d" % [bh["burnt"], bt, (bh["fires"] as Array).size(), hol0, world.terrain.hollows.size(), sol0, world.terrain.solids.size()])
		var bc: Vector3 = (bh["xf"] as Transform3D).origin
		print("structtest: blocked in the ruin: %s" % world.terrain.blocked_by_building(bc + Vector3(0.5, 0.5, -1.5), 0.3))
		sts.set_on_fire("shop", 0.4)
		sts.douse((sts.items["shop"]["xf"] as Transform3D).origin, 3.0)
		for i in range(30):
			sts.douse((sts.items["shop"]["xf"] as Transform3D).origin, 3.0)
		print("structtest: shop doused: lit %s heat %.2f" % [sts.items["shop"]["lit"], sts.items["shop"]["heat"]])
		sts.save()
		get_tree().quit()
		return
	if _test.has("boomtest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		_get_out()
		var t: RefCounted = world.terrain
		var w0: Vector3 = walker.global_position
		pickup.park(Transform3D(Basis.IDENTITY, Vector3(w0.x + 25.0, t.height_at(w0.x + 25.0, w0.z), w0.z)))
		water_truck.park(Transform3D(Basis.IDENTITY, Vector3(w0.x - 30.0, t.height_at(w0.x - 30.0, w0.z), w0.z + 10.0)))
		for i in range(20):
			await get_tree().physics_frame
		for e0 in _all_vehicles():
			vdamage.repair(String(e0[0]))
		# douse: the water truck alight, sprayed until it's out
		vdamage.set_on_fire("water_truck", "water truck", 0.5)
		for i in range(8):
			_douse_machines(water_truck.global_position, 3.0)
		print("boomtest: water truck sprayed -> still burning %s %s" % [vdamage.on_fire("water_truck"), "" if not vdamage.on_fire("water_truck") else "<-- PROBLEM"])
		# the pickup left burning: it goes up
		vdamage.set_on_fire("pickup", "pickup", 0.6)
		vdamage.fires["pickup"]["fuse"] = 2.0
		var h0: float = walker.health
		_shake = 0.0
		var shake_max := 0.0
		for i in range(420):
			await get_tree().physics_frame
			shake_max = maxf(shake_max, _shake)
		print("boomtest: pickup after its fuse: blown %s, %s, %d burning bits/fires thrown, shake %.2f, walker health %.2f -> %.2f" % [
			vdamage.get_d("pickup").get("blown", false), vdamage.status("pickup"), explosions.burning_spots(), shake_max, h0, walker.health])
		var charred := 0
		for mi in pickup.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).material_overlay != null:
				charred += 1
		vdamage.repair("pickup")
		var still := 0
		for mi2 in pickup.find_children("*", "MeshInstance3D", true, false):
			if (mi2 as MeshInstance3D).material_overlay != null:
				still += 1
		print("boomtest: wreck charred %d meshes; after repair %d %s" % [charred, still, "" if charred > 0 and still == 0 else "<-- PROBLEM"])
		# the plane alight: its tanks go
		plane._start_fire(0.5)
		_plane_fire_t = PLANE_FUSE - 0.05
		_plane_fuse(0.1)
		print("boomtest: plane after its fuse: crashed %s, fuel %.1f kg, burning bits %d" % [plane.is_crashed, plane.fuel, explosions.burning_spots()])
		get_tree().quit()
		return
	if _test.has("colltest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		_get_out()
		var t: RefCounted = world.terrain
		var w0: Vector3 = walker.global_position
		pickup.park(Transform3D(Basis.IDENTITY, Vector3(w0.x + 6.0, t.height_at(w0.x + 6.0, w0.z), w0.z)))
		for i in range(30):
			await get_tree().physics_frame
		_update_movers()
		walker.place(Vector3(w0.x + 2.0, t.height_at(w0.x + 2.0, w0.z), w0.z), -PI * 0.5)     # facing +x, at the pickup's side
		for i in range(240):
			walker.look = Vector2(-PI * 0.5, 0.0)
			walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
			await get_tree().physics_frame
		var dx: float = walker.global_position.x - pickup.global_position.x
		print("colltest: walked at the pickup's side: stopped %.2f m from its middle %s" % [absf(dx), "" if absf(dx) > 1.1 else "<-- PROBLEM (walked into it)"])
		# a log on the ground: step up onto it, and a wheel rides over it
		var lp: Vector3 = walker.global_position + Vector3(-3.0, 0, 3.0)
		lp.y = t.height_at(lp.x, lp.z)
		cargo.add_own_logs([lp])
		for i in range(4):
			await get_tree().process_frame
		print("colltest: log on the ground: wheel ground there %.2f vs ground %.2f %s" % [t.wheel_ground(lp.x, lp.z), t.height_at(lp.x, lp.z), "" if t.wheel_ground(lp.x, lp.z) > t.height_at(lp.x, lp.z) + 0.2 else "<-- PROBLEM"])
		# a rock off the chute over the log trailer's bed goes in the bed
		var bq: Vector3 = (log_trailer.bed_xf(0) as Transform3D).origin
		var went: String = cargo.oversize_rock(bq, 30.0)
		print("colltest: rock dropped over the trailer bed -> %s %s" % [went, "" if went == "bed" else "<-- PROBLEM"])
		var gq: Vector3 = bq + Vector3(8, 0, 8)
		print("colltest: rock dropped on open ground -> %s" % cargo.oversize_rock(gq, 30.0))
		# a machine bucket scoops the rock up and dumps it back out as a rock
		var taken: Array = cargo.take_rocks_near(gq, 1.0)
		cargo.put_rocks(gq + Vector3(3, 0, 0), taken)
		print("colltest: loader scoops %d rock(s), dumps them 3 m over" % taken.size())
		get_tree().quit()
		return
	if _test.has("veintest"):
		Game.sandbox = true
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		_get_out()
		var VeinsL = load("res://scripts/veins.gd")
		VeinsL.make(int(Game.world_seed))
		print("veintest: %d veins: %s" % [VeinsL.list.size(), str(VeinsL.list.map(func(v): return "(%.0f,%.0f) %.2fm %.0fg/t" % [v[0], v[1], v[3], v[6]]))])
		var t: RefCounted = world.terrain
		# stand beside the first vein where it crosses the surface, facing it
		var v0: Array = VeinsL.list[0]
		var a0 := float(v0[2])
		var nrm := Vector3(-sin(a0), 0, cos(a0))
		var c := Vector3(float(v0[0]), 0, float(v0[1]))
		var b0: float = float(prospect.geology(c.x, c.z)[2])
		c += nrm * ((b0 + 0.3) / tan(float(v0[4])) - 0.25 * sin(0.0))
		c.y = t.height_at(c.x, c.z)
		print("veintest: vein 0 at %s, bedrock %.2f m down, in the rock there: %s" % [c, b0, str(prospect.vein_here(c - Vector3(0, b0 + 0.3, 0)))])
		inv.add("pick", 1, true)
		inv.add("shovel", 1, true)
		var stand := c - nrm * 1.0
		walker.place(Vector3(stand.x, t.height_at(stand.x, stand.z), stand.z), atan2(nrm.x, nrm.z))
		var ore0: int = (cargo.own_rocks["pieces"] as Array).filter(func(pc): return bool(pc.get("q", false))).size()
		var seen_vein := false
		var pit: Vector3 = c
		for k3 in range(120):
			if prospect.layer_at(pit) == "rock" and t.natural_at(pit.x, pit.z) - t.height_at(pit.x, pit.z) > b0 + 0.25:
				break
			prospect.dig(pit, 1.6, 1.5, 0.6)
		stand = c - nrm * 0.7
		walker.place(Vector3(stand.x, t.height_at(stand.x, stand.z), stand.z), atan2(nrm.x, nrm.z))
		print("veintest: pit dug to %s, %.2f m down" % [prospect.layer_at(pit), t.natural_at(pit.x, pit.z) - t.height_at(pit.x, pit.z)])
		for i in range(20):
			var front: Vector3 = walker.global_position + nrm * 0.7
			var tool := "pick" if seen_vein or prospect.layer_at(front) == "rock" else "shovel"
			for si in range(inv.HOTBAR):
				if not (inv.slots[si] as Dictionary).is_empty() and String(inv.slots[si]["id"]) == tool:
					inv.select(si)
			cargo.own_rocks["pieces"] = (cargo.own_rocks["pieces"] as Array).filter(func(pc): return bool(pc.get("q", false)))
			var tg: Array = prospect.target(walker.global_position, front)
			if tg.is_empty():
				print("veintest: %d nothing to do (%s)" % [i, prospect.layer_at(front)])
				break
			if String(tg[0]) == "vein":
				seen_vein = true
			var m: String = prospect.act(String(tg[0]), walker.global_position, front) if String(tg[0]) != "" else ""
			if i % 4 == 0 or String(tg[0]) == "vein":
				print("veintest: %d %s | %s | %s" % [i, tool, tg[1], m])
			if seen_vein and m.begins_with("A chunk") or m.begins_with("Gold!"):
				break
		var ore1: int = (cargo.own_rocks["pieces"] as Array).filter(func(pc): return bool(pc.get("q", false))).size()
		print("veintest: quartz chunks %d -> %d %s" % [ore0, ore1, "" if ore1 > ore0 else "<-- PROBLEM"])
		get_tree().quit()
		return
	if _test.has("menuwidth"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		_get_out()
		pickup.park(Transform3D(Basis.IDENTITY, WORKSHOP_AT + Vector3(0, world.terrain.height_at(WORKSHOP_AT.x, WORKSHOP_AT.z), 10)))
		menu.open("main")
		menu._ws_slot = "engine"
		menu._show("workshop")
		for i in range(6):
			await get_tree().process_frame
		var vw: Vector2 = get_viewport().get_visible_rect().size
		var pr: Rect2 = menu._panel.get_global_rect()
		print("menuwidth: content needs at least %.0f px wide" % menu._content.get_combined_minimum_size().x)
		print("menuwidth: window %s, menu panel %s .. %s, %d buttons %s" % [vw, pr.position.x, pr.end.x, menu._content.get_child_count(),
			"" if pr.position.x >= 0.0 and pr.end.x <= vw.x else "<-- PROBLEM (off screen)"])
		get_tree().quit()
		return
	if _test.has("damagetest"):
		_on_start_requested(0, false)
		await get_tree().create_timer(1.0).timeout
		_get_out()
		vdamage.repair("pickup")
		pickup.park(Transform3D(Basis.IDENTITY, walker.global_position + Vector3(8, 0, 0)))
		for i in range(200):
			await get_tree().physics_frame
		_get_on_forklift(pickup)
		pickup.esim.battery = 1.0
		for k2 in range(6):
			if not pickup.engine_on:
				pickup.engine_toggle()
		for i in range(240):
			_drive_forklift(1.0 / 60.0, Vector2(0, 1))
			await get_tree().physics_frame
		print("damagetest: driving %.1f m/s, %s" % [pickup.body.speed, vdamage.status("pickup")])
		pickup.body.vel = Vector3.ZERO
		pickup.body.speed = 0.0
		pickup.body.place(pickup.body.transform())
		for i in range(30):
			await get_tree().physics_frame
		print("damagetest: sudden stop -> %s %s" % [vdamage.status("pickup"), "" if vdamage.damaged("pickup") else "<-- PROBLEM (no hit)"])
		vdamage.hurt("pickup", 1.0, 0.0, 0.0)
		for i in range(10):
			_drive_forklift(1.0 / 60.0, Vector2(0, 1))
			await get_tree().physics_frame
		print("damagetest: engine wrecked -> engine_on %s, dead %s" % [pickup.engine_on, vdamage.dead("pickup")])
		var rl: Array = _repair_list()
		print("damagetest: repair list %s" % str(rl.map(func(r): return [r["name"], r["cost"], r["here"]])))
		vdamage.repair("pickup")
		print("damagetest: repaired -> %s; keys %s" % [vdamage.status("pickup"), str(_all_vehicles().map(func(e): return e[0]))])
		get_tree().quit()
		return
	if _test.has("newgametest"):
		Flora.felled = {"1,2": [0.0, 1.0]}
		world._save_felled()
		Game.last_strip = 3
		var had := FileAccess.file_exists("user://world.cfg")
		Game.new_game_pending = true
		_wipe_saves()
		var left := SAVE_FILES.filter(func(f): return FileAccess.file_exists("user://" + f))
		print("newgametest: world.cfg there before %s; after: felled %d, last strip %d, files left %s %s" % [had, Flora.felled.size(), Game.last_strip, str(left),
			"" if Flora.felled.is_empty() and left.is_empty() and Game.last_strip == 0 else "<-- PROBLEM"])
		get_tree().quit()
		return
	if _test.has("consoletest"):
		# every admin command once, printing what the console answers
		var con = get_node("Console")
		for c in ["goto creek", "goto pond", "goto knoll", "goto bog", "goto pad", "goto vein", "goto forest", "goto strip", "give pick", "give rope 3", "logs 5", "log 3", "rock 2", "gold 10", "part nope", "part i6d14", "bring tug", "bring trailer", "bring pickup", "bring water", "bring fuel", "bring loader"]:
			con._run(c)
			await get_tree().process_frame
			print("consoletest: %s -> %s" % [c, String(con._lines.back()) if not con._lines.is_empty() else ""])
		get_tree().quit()
		return
	if _test.has("logtest"):
		await _log_test()
		get_tree().quit()
		return
	if _test.has("tunneltest"):
		await _tunnel_test()
		get_tree().quit()
		return
	if _test.has("digtest"):
		await _dig_test()
		get_tree().quit()
		return
	if _test.has("padtest"):
		var tt: RefCounted = world.terrain
		for hb in tt.hollows:
			var hxf: Transform3D = hb["xf"]
			var hs: Vector3 = hb["size"]
			var worst := 0.0
			for cx in [-0.5, 0.5]:
				for cz in [-0.5, 0.5]:
					var cp: Vector3 = hxf * Vector3(hs.x * cx, 0, hs.z * cz)
					worst = maxf(worst, absf(tt.height_at(cp.x, cp.z) - hxf.origin.y))
			print("padtest: building at %s size %s: corners off the ground by up to %.2f m" % [str(Vector2i(int(hxf.origin.x), int(hxf.origin.z))), str(hs), worst])
		get_tree().quit()
		return
	if _test.has("forkmove"):
		var fl0: Node3D = forklifts[0]
		_get_out()
		_get_on_forklift(fl0)
		var p0: Vector3 = fl0.global_position
		var fw0: Vector3 = Basis(Vector3.UP, fl0.yaw) * Vector3.FORWARD
		print("forkmove: at ", p0, " mud ", world.terrain.mud_at(p0.x, p0.z), " blocked ahead ", world.terrain.blocked_by_building(p0 + fw0 * 1.6 + Vector3(0, 0.6, 0), 0.7, fl0), " behind ", world.terrain.blocked_by_building(p0 - fw0 * 1.6 + Vector3(0, 0.6, 0), 0.7, fl0), " plane ", fl0._hits_plane(p0))
		for i in range(120):
			_drive_forklift(1.0 / 60.0, Vector2(0, 1))
			await get_tree().physics_frame
		print("forkmove: forward moved ", fl0.global_position.distance_to(p0), " speed ", fl0.speed, " driving ", driving == fl0)
		get_tree().quit()
		return
	if _test.has("forktest"):
		await _fork_test()
		get_tree().quit()
		return
	if _test.has("switchtest"):
		var g: Dictionary = blights.groups[0]
		_get_out()
		walker.place((g["switch"] as Vector3) + (world.terrain.hollows[0]["xf"] as Transform3D).basis * Vector3(0, -1.35, 0.6), 0.0)
		for i in range(3):
			await get_tree().process_frame
		print("switchtest: %d groups, near %d, prompt '%s'" % [blights.groups.size(), _switch, cargo.extra_prompt])
		if _switch >= 0:
			print("switchtest: ", blights.toggle(_switch), " lights visible ", (g["lights"][0] as OmniLight3D).visible)
		get_tree().quit()
		return
	if _test.has("hangarwalk"):
		var hb: Dictionary = world.terrain.hollows[0]
		var hxf: Transform3D = hb["xf"]
		var sz: Vector3 = hb["size"]
		_get_out()
		walker.place(hxf * Vector3(0, 0, -sz.z * 0.5 - 5.0), 0.0)
		var legs := [["in the door", Vector3(0, 0, 2.0)], ["to the side wall", Vector3(sz.x * 0.5 + 3.0, 0, 2.0)], ["to the back wall", Vector3(2.0, 0, sz.z * 0.5 + 3.0)], ["out the door", Vector3(0, 0, -sz.z * 0.5 - 4.0)], ["round to the front wall", Vector3(sz.x * 0.5 - 1.0, 0, -sz.z * 0.5 + 2.0)]]
		for leg in legs:
			var tgt: Vector3 = hxf * (leg[1] as Vector3)
			for i in range(60 * 12):
				var d: Vector3 = tgt - walker.global_position
				d.y = 0.0
				if d.length() < 0.2:
					break
				walker.look.x = atan2(-d.x, -d.z)
				walker.step(1.0 / 60.0, Vector2(0, 1), true, false)
				await get_tree().physics_frame
			var l: Vector3 = hxf.affine_inverse() * walker.global_position
			print("hangarwalk: %s -> local (%.1f, %.2f, %.1f)" % [leg[0], l.x, l.y, l.z])
		get_tree().quit()
		return
	if _test.has("walktest"):
		await _walk_test()
		get_tree().quit()
		return
	if _test.has("typetest"):
		await _type_test(String(_test["typetest"]))
		get_tree().quit()
		return
	if _test.has("skytest"):
		print("skytest result: ", await _skydive_test())
		get_tree().quit()
		return
	if _test.has("net"):
		await _net_test(String(_test["net"]))
		return
	if _test.has("coop"):
		# two copies on one computer, side by side (Run Instances):
		#   -- coop=host     /     -- coop=join
		var role := String(_test["coop"])
		var win := get_window()
		win.mode = Window.MODE_WINDOWED
		var scr: Rect2i = DisplayServer.screen_get_usable_rect(win.current_screen)
		win.size = Vector2i(scr.size.x / 2, scr.size.y - 40)
		win.position = scr.position + Vector2i(scr.size.x / 2 if role == "host" else 0, 30)
		net.player_name = "Host" if role == "host" else "Guest"
		if role == "host":
			var hr: String = net.host()
			print("coop host: ", hr)
			hud.push_message(hr, 6.0)
		else:
			await get_tree().create_timer(4.0).timeout
			var jr: String = net.join("127.0.0.1")
			print("coop join: ", jr)
			hud.push_message(jr, 6.0)
			await get_tree().create_timer(6.0).timeout
			print("coop join: online %s, guest %s, remotes %d" % [net._live(), net.is_guest(), net.remotes.size()])
		return
	if _test.has("dc3shot"):
		var dc: Node3D = world.get_node_or_null("ParkedDC3")
		if dc != null:
			var c: Vector3 = dc.global_position
			var off := Vector3(float(_test.get("dx", "-30")), 0, float(_test.get("dz", "-38")))
			var dyaw: float = dc.global_transform.basis.get_euler().y
			if _test.has("local"):
				var lc := String(_test["local"]).split(",")
				off = Basis(Vector3.UP, dyaw) * Vector3(float(lc[0]), 0, float(lc[1]))
			if _test.has("beside"):
				# Side by side, same heading, nose level with the DC-3's wing.
				off = Basis(Vector3.UP, dyaw) * Vector3(float(_test["beside"]), 0, 0)
			var p: Vector3 = c + off
			p.y = world.terrain.height_at(p.x, p.z) + 1.66
			var face := atan2(-(c.x - p.x), -(c.z - p.z))
			if _test.has("beside"):
				face = dyaw
			plane.place_parked(p, Quaternion(Basis(Vector3.UP, face) * Basis(Vector3.RIGHT, deg_to_rad(11.0))))
			plane.frozen = true
	if _test.has("buildshot"):
		jobs.money += 50000
		var sv: Dictionary = _find_strip_site(k)
		if not sv.is_empty():
			builds.build_strip(sv, "Test Strip")
			var nk: int = world.terrain.strips.size() - 1
			builds.logs = 40
			print("buildshot cabin: ", builds.build("cabin", world.terrain.strip_point(nk, -60.0, 30.0), PI * 0.5))
			print("buildshot hangar: ", builds.build("hangar", world.terrain.strip_point(nk, 40.0, 40.0), PI * 0.5))
			plane.place_on_strip(nk)
			for i in range(120):
				await get_tree().process_frame
			plane.frozen = true
		DirAccess.remove_absolute(ProjectSettings.globalize_path(builds.SAVE))
	if _test.has("campshot"):
		for i in range(10):
			await get_tree().physics_frame
		_get_out()
		var side: Vector3 = plane.global_transform.basis.x
		var fwd: Vector3 = -plane.global_transform.basis.z
		fwd.y = 0.0
		var spot: Vector3 = plane.global_position - side.normalized() * 34.0 + fwd.normalized() * 4.0
		print("campshot build: '%s'" % builds.build("bushcamp", spot, _plane_yaw()))
		var cooler: Vector3 = builds.camp_point(BuildsScript.CAMP_COOLER + Vector3(0.6, 0, 0.8))
		walker.place(cooler, _plane_yaw())
		await get_tree().process_frame
		camp.find_target()
		print("campshot prompt: ", camp.prompt)
		for i in range(4):
			camp.find_target()
			camp.interact()
		print("campshot drunk %.3f beers %d state %s" % [camp.drunk, camp.beers, camp.state_text()])
		camp.light_up()
		var fire: Vector3 = builds.camp_point(Vector3.ZERO)
		var view_from: Vector3 = builds.camp_point(Vector3(1.2, 0, 3.6))
		walker.place(view_from, atan2(-(fire.x - view_from.x), -(fire.z - view_from.z)) + 0.35)
		walker.look.y = -0.25
		walker.first_person = _test.get("fp", "0") == "1"
		for i in range(40):
			await get_tree().process_frame
	if _test.has("hangarshot"):
		# Stand in the doorway of the first hangar, looking in; the plane parked inside.
		var hb: Dictionary = world.terrain.hollows[int(_test["hangarshot"])]
		var hxf: Transform3D = hb["xf"]
		var sz: Vector3 = hb["size"]
		plane.place_parked(hxf * Vector3(0, 1.66, 0.5), Quaternion(hxf.basis * Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(11.0))))
		plane.frozen = true
		_get_out()
		var at: Vector3 = hxf * Vector3(float(_test.get("hx", "4.0")), 0, -sz.z * 0.5 - float(_test.get("back", "4.0")))
		var tgt: Vector3 = hxf * Vector3(-1.0, 1.5, sz.z * 0.3)
		walker.place(at, atan2(-(tgt.x - at.x), -(tgt.z - at.z)))
		walker.look.y = -0.05
		walker.first_person = true
		for i in range(10):
			await get_tree().process_frame
		print("hangarshot: floor %.2f, walker y %.2f" % [world.terrain.ground_level_at(hxf.origin.x, hxf.origin.z), walker.global_position.y])
	if _test.has("dock"):
		_on_dock_requested(int(_test["dock"]))
		plane.frozen = false
		for i in range(180):
			await get_tree().physics_frame
		plane.frozen = true
	if _test.has("floatshot"):
		var lk: Dictionary = world.terrain.lakes[1]
		var lc: Vector2 = lk["pos"]
		plane.leg_kind = "amphib"
		plane.apply_gear()
		plane.frozen = false
		plane.place_on_water(Vector3(lc.x, 0.0, lc.y + 500.0), 30.0)
		plane.set_gear(_test["floatshot"] == "down")
		for i in range(240):
			await get_tree().physics_frame
		plane.frozen = true
	if _test.has("floattest"):
		await _float_test()
	if _test.has("skim"):
		await _skim_test(float(_test["skim"]), String(_test.get("tyre", "29")), float(_test.get("dip", "0.03")))
	if _test.has("roll"):
		# Take-off roll at full power, to see dust and prop wash.
		plane.frozen = false
		plane.engine.set_running(plane.oat_c)
		plane.throttle = 1.0
		plane.brake = 0.0
		var lift_at := -1.0
		for i in range(int(_test["roll"])):
			if _test.has("pull"):
				plane.direct_controls = true
				plane.in_pitch = 1.0 if plane.ias_kt > float(_test["pull"]) else 0.0
				if lift_at < 0.0 and plane.airborne:
					lift_at = plane.ias_kt
					print("roll: airborne at %.0f kt after %.1f s" % [lift_at, float(i) / 120.0])
			await get_tree().physics_frame
		print("roll debug: gear_pos %.2f wheels_down %d loads %s rpm %.0f thr %.2f brake %.2f park %s crashed %s agl %.2f float %s" % [plane.gear_pos, plane.wheels_down, str(plane.wheel_load), plane.rpm, plane.throttle, plane.brake, plane.park_brake, plane.is_crashed, plane.agl, str(plane.float_water)])
		print("roll: speed %.1f m/s, surface %s" % [plane.ground_speed, world.terrain.SURFACE_NAMES[world.terrain.surface_at(plane.global_position.x, plane.global_position.z)]])
	for view in String(_test.get("shot", "chase")).split(","):
		match view:
			"chase":
				cockpit = false
				_orbit = Vector2(0.5, 0.05)
			"behind":
				cockpit = false
				_orbit = Vector2.ZERO
			"side":
				cockpit = false
				_orbit = Vector2(1.5, -0.1)
			"front":
				cockpit = false
				_orbit = Vector2(2.7, 0.0)
			"wheels":
				cockpit = false
				_orbit = Vector2(2.25, -0.32)
			"high":
				cockpit = false
				_orbit = Vector2(0.4, 0.9)
				_chase_dist = 60.0
			"cockpit":
				cockpit = true
				_orbit = Vector2(float(_test.get("lookx", "0")), -float(_test.get("lookdown", "0")))
			"eco", "foot":
				pass
			"map":
				hud.show_map = true
			"menu":
				menu.open(String(_test.get("page", "main")))
		hud.cockpit_mode = cockpit
		visual.set_cockpit_view(cockpit)
		_orbit_idle = -100.0
		_update_camera(0.016, true)
		for i in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [out_dir, tag, view])
		hud.show_map = false
		if menu.is_open:
			menu.close()
		_chase_dist = float(_test.get("zoom", "19"))
	print("plants: ", world.vegetation.instance_count if world.vegetation != null else 0)
	if world.vegetation != null:
		var st: Dictionary = world.vegetation.stats()
		var tt := 0
		var ts := 0
		for lname in st.keys():
			print("  %-7s instances %7d   triangles %9d   shadow triangles %9d" % [lname, st[lname][0], st[lname][1], st[lname][2]])
			tt += int(st[lname][1])
			ts += int(st[lname][2])
		print("  total triangles %d, casting shadows %d" % [tt, ts])
	get_tree().quit()


var _eco_on := false
var _eco_xf := Transform3D.IDENTITY


func st_pos_for_test() -> Vector3:
	var st: Dictionary = world.terrain.strips[int(_test.get("strip", "0"))]
	return st["pos"]


## Development test: stand at head height in a given habitat (see flora.gd),
## searching outward from `from`, and look across it.
func _place_eco_camera(habitat_name: String, from: Vector3) -> void:
	var Flora = preload("res://scripts/flora.gd")
	var t: RefCounted = world.terrain
	var want: int = Flora.HABITAT_NAMES.find(habitat_name.replace("_", " "))
	var skip := int(_test.get("skip", "0"))
	for r in range(10, 260):
		var rad := float(r) * 45.0
		var steps := maxi(8, int(rad / 45.0))
		for k in range(steps):
			var a := TAU * float(k) / float(steps)
			var x := from.x + cos(a) * rad
			var z := from.z + sin(a) * rad
			var h: float = t.height_at(x, z)
			var n: Vector3 = t.normal_at(x, z)
			if h < 2.0 or n.y < 0.95 or t.is_cleared(x, z, 20.0):
				continue
			if Flora.habitat(t, x, z, h, n) != want:
				continue
			# Look the way the habitat carries on furthest.
			var best_a := 0.0
			var best_n := -1
			for m in range(12):
				var b := TAU * float(m) / 12.0
				var cnt := 0
				for d in [20.0, 40.0, 70.0, 110.0]:
					var px: float = x + cos(b) * d
					var pz: float = z + sin(b) * d
					if Flora.habitat(t, px, pz, t.height_at(px, pz), t.normal_at(px, pz)) == want:
						cnt += 1
				if cnt > best_n:
					best_n = cnt
					best_a = b
			if best_n < 3:
				continue
			if skip > 0:
				skip -= 1
				continue
			var eye := Vector3(x, h + float(_test.get("eyeh", "1.8")), z)
			var dir := Vector3(cos(best_a), -float(_test.get("lookdown", "0.08")), sin(best_a)).normalized()
			_eco_xf = Transform3D.IDENTITY.looking_at(dir, Vector3.UP)
			_eco_xf.origin = eye
			_eco_on = true
			cam.global_transform = _eco_xf
			print("eco camera: ", habitat_name, " at ", eye)
			return
	print("eco camera: no ", habitat_name, " found")


## Development test: fly into a stand of trees, or into the ground hard.
func _crash_test() -> void:
	if _test.has("dc3"):
		plane.apply_type("dc3")
		_apply_plane_type()
	var t: RefCounted = world.terrain
	var st: Dictionary = t.strips[int(_test.get("strip", "0"))]
	var c: Vector3 = st["pos"]
	if _test.has("treecrash"):
		# Find a thick stand of trees near the strip.
		var tn: int = t.tree_n
		var ci := int((c.x + t.half) / 32.0)
		var cj := int((c.z + t.half) / 32.0)
		var best := Vector2i(-1, -1)
		var best_n := 0
		for r in range(4, 90):
			for k in range(16):
				var a := TAU * float(k) / 16.0
				var ti := ci + int(cos(a) * r)
				var tj := cj + int(sin(a) * r)
				if ti < 2 or tj < 2 or ti >= tn - 2 or tj >= tn - 2:
					continue
				var cnt := 0
				for dj in range(-2, 3):
					for di in range(-2, 3):
						if t.tree_h[(tj + dj) * tn + ti + di] > 0:
							cnt += 1
				if cnt > best_n:
					best_n = cnt
					best = Vector2i(ti, tj)
			if best_n >= 20:
				break
		var tp: Vector2 = t.tree_position(best.x, best.y)
		var hdg := 90.0
		var start := Vector3(tp.x - 32.0, t.height_at(tp.x, tp.y) + 5.0, tp.y - float(_test.get("offset", "2.7")))
		plane.place_in_air(start, hdg, float(_test.get("speed", "30")))
		print("tree crash test at ", tp, " trees nearby ", best_n)
	else:
		var start2 := Vector3(c.x + 300.0, c.y + 70.0, c.z)
		plane.place_in_air(start2, 270.0, 58.0)
		plane.b = plane.b * Basis(Vector3.RIGHT, deg_to_rad(-38.0))
		plane.vel = plane.b * Vector3(0, 0, -58.0)
	plane.throttle = 0.5
	plane.frozen = false
	var frames := int(_test.get("crashframes", "420"))
	for i in range(frames):
		await get_tree().physics_frame
		if _test.has("debug") and i % 20 == 0:
			print("  f%d pos %s agl %.1f vel %s crashed %s wings %s" % [i, str(plane.pos), plane.agl, str(plane.vel), plane.is_crashed, plane.wing_off])
	print("after crash test: crashed=", plane.is_crashed, " fire=", plane.on_fire, " wings off=", plane.wing_off, " report=", plane.damage_report().map(func(x): return x[0]))
	await get_tree().create_timer(1.5).timeout
	if plane.plane_type == "dc3":
		print("after crash visuals (dc3): fire node=", dc3_vis._fire != null,
			" props bent=", dc3_vis._bent_props, " debris=", dc3_vis.debris.get_child_count() if dc3_vis.debris != null else -1)
	else:
		print("after crash visuals: fire node=", visual._fire != null, " fire visible=", visual._fire.visible if visual._fire != null else false,
			" wings shown off=", visual._shown_off, " debris=", visual.debris.get_child_count() if visual.debris != null else -1,
			" smoke=", visual._smoke.emitting if visual._smoke != null else false)


## Exercises every strip, view, menu page and setting, then a flight and a crash,
## so script errors show up without anyone at the keyboard.
## The console's "perf" readout: what each frame costs and where it goes,
## top-left, updated every frame while it's shown.
var _perf_probe_t := 0
var _perf_top: Array = []


func perf_overlay(on: bool) -> void:
	if not on:
		if _perf_label != null:
			_perf_label.get_parent().queue_free()
			_perf_label = null
		return
	if _perf_label != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 90
	_perf_label = Label.new()
	_perf_label.position = Vector2(10, 10)
	_perf_label.add_theme_font_size_override("font_size", 14)
	_perf_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_perf_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_perf_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_perf_label)
	add_child(layer)


var _perf_wait := 0.0
func _perf_overlay_update() -> void:
	if _perf_label == null:
		return
	# (DESIGN_NOTES 171) the readout itself was a load: 4 updates a second,
	# and the per-script probe (it runs every script's _process a second
	# time) only every 40th update - it was every 5th frame, skewing the very
	# numbers it shows
	_perf_wait -= get_process_delta_time()
	if _perf_wait > 0.0:
		return
	_perf_wait = 0.25
	var veg = world.vegetation
	var lines: Array[String] = []
	lines.append("fps %d  frame %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)])
	lines.append("process %.1f ms  physics %.1f ms" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	# where the frame goes: the CPU preparing it, the graphics card drawing it
	var vrid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vrid, true)
	lines.append("render: cpu %.1f ms  gpu %.1f ms" % [RenderingServer.viewport_get_measured_render_time_cpu(vrid) + RenderingServer.get_frame_setup_time_cpu(), RenderingServer.viewport_get_measured_render_time_gpu(vrid)])
	lines.append("draw calls %d  triangles %.1fM  vram %d MB" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)])
	lines.append("objects %d  nodes %d" % [int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	if veg != null:
		var ch: Array[int] = []
		for layer in range(5):
			ch.append((veg._chunks[layer] as Dictionary).size())
		lines.append("plants %.2f ms  %d instances  chunks t%d f%d s%d g%d r%d  backlog %d%s" % [veg.perf_ms, veg.instance_count, ch[0], ch[1], ch[2], ch[3], ch[4], veg._backlog, "" if veg.is_idle() else "  STREAMING"])
	if plane != null and not on_foot:
		lines.append("flight model %.2f ms" % plane.perf_ms)
	lines.append("trees %s  preset %s  shadows %s" % ["3D" if Game.trees_3d else "flat", Game.QUALITY_NAMES[clampi(Game.graphics_quality, 0, 4)], Game.SHADOW_NAMES[clampi(Game.gfx_shadows, 0, 4)]])
	# Every few seconds, clock each script's _process directly and name the
	# heaviest, so a runaway one points straight at itself.
	_perf_probe_t += 1
	if _perf_probe_t >= 40:
		_perf_probe_t = 0
		var found: Array = []
		_perf_scripts(get_tree().root, found)
		var res: Array = []
		for n in found:
			for fn in ["_process", "_physics_process"]:
				if not (n as Node).has_method(fn) or (n as Node).get_script() == null:
					continue
				var t0 := Time.get_ticks_usec()
				(n as Node).call(fn, 0.0001)
				var us := Time.get_ticks_usec() - t0
				if us > 300:
					res.append([us, "%s.%s %s" % [(n as Node).name, fn.trim_prefix("_"), String((n as Node).get_script().resource_path).get_file()]])
		res.sort_custom(func(x, y): return int(x[0]) > int(y[0]))
		_perf_top = []
		for i in range(mini(4, res.size())):
			_perf_top.append("  %.1f ms  %s" % [float(res[i][0]) / 1000.0, res[i][1]])
	if not _perf_top.is_empty():
		lines.append("heaviest scripts (one probe call):")
		for ln2 in _perf_top:
			lines.append(ln2)
	_perf_label.text = "\n".join(lines)


func _run_selftest() -> void:
	# Always the standard plane, whatever an earlier test left in the save.
	if plane.plane_type != "wolverine":
		plane.apply_type("wolverine")
		_apply_plane_type()
	plane.leg_kind = "spring"
	plane.tyre_kind = "850"
	plane.apply_gear()
	# And an empty hold: an earlier test may have left cargo aboard.
	jobs.carried.clear()
	plane.set_job_load(0.0, 0.0)
	jobs.save_career()
	Engine.time_scale = 6.0
	var strips: int = world.terrain.strips.size()
	var problems := 0
	for k in range(strips):
		_on_start_requested(k, false)
		await get_tree().create_timer(4.0).timeout
		var ok: bool = plane.on_ground and not plane.is_crashed and plane.ground_speed < 0.6
		print("runway start %-20s on_ground=%s speed=%.2f pitch=%.1f %s" % [world.terrain.strips[k]["name"], plane.on_ground, plane.ground_speed, rad_to_deg(plane.pitch_rad()), "" if ok else "  <-- PROBLEM"])
		if not ok:
			problems += 1
	for k in range(strips):
		_on_start_requested(k, true)
		await get_tree().create_timer(4.0).timeout
		print("approach start %-18s agl=%.0f ias=%.0f crashed=%s" % [world.terrain.strips[k]["name"], plane.agl, plane.ias_kt, plane.is_crashed])
		if plane.is_crashed:
			problems += 1
	# Views, chart, help, destinations
	for action in ["camera", "map", "map", "help", "help", "camera", "flaps_down", "flaps_up", "fullscreen", "fullscreen"]:
		_tap(action)
		await get_tree().process_frame
		await get_tree().process_frame
	for i in range(strips + 2):
		_tap("next_target")
		await get_tree().process_frame
	# Every cockpit control, worked by the mouse code paths
	_set_cockpit(true)
	await get_tree().process_frame
	var worked: int = cockpit_ctl.exercise()
	_update_cockpit_hover()
	for i in range(3):
		await get_tree().process_frame
	print("cockpit controls worked: ", worked)
	# Jobs: take one at Port Ashby, fly it (by moving the plane), unload, get paid.
	_on_start_requested(0, false)
	await get_tree().create_timer(3.0).timeout
	var offered: Array = jobs.board(0)
	var pick := {}
	for j in offered:
		if jobs.cannot_take(j) == "":
			pick = j
			break
	var mass0: float = plane.gross_mass()
	var money0: int = jobs.money
	var took: bool = not pick.is_empty() and jobs.take(pick)
	var mass1: float = plane.gross_mass()
	var paid := 0
	if took:
		_on_start_requested(int(pick["to"]), false)
		await get_tree().create_timer(3.0).timeout
		var here: Array = jobs.deliverable()
		if not here.is_empty():
			paid = jobs.deliver(here[0])
	print("jobs: offered %d, took %s (%s, %.0f kg, mass +%.0f kg), paid $%d, money %d -> %d, on board %d" % [
		offered.size(), took, pick.get("title", "-"), float(pick.get("kg", 0.0)), mass1 - mass0, paid, money0, jobs.money, jobs.carried.size()])
	if not took or paid <= 0 or mass1 - mass0 < 1.0 or not jobs.carried.is_empty():
		problems += 1
	# Cargo by hand: carry each piece aboard, fly, carry it out at the other end.
	_on_start_requested(0, false)
	await get_tree().create_timer(3.0).timeout
	var pj := {}
	for j in jobs.board(0):
		if int(j["pax"]) == 0 and jobs.cannot_take(j) == "" and int(j.get("n", 1)) >= 2:
			pj = j
			break
	var took2: bool = not pj.is_empty() and jobs.take(pj, true)
	var job2: Dictionary = jobs.carried.back() if took2 else {}
	var loaded2 := 0
	var paid2 := 0
	var mass_before: float = plane.gross_mass()
	if took2:
		_get_out()
		for i in range(4):
			await get_tree().process_frame
		for pc in job2["pieces"]:
			walker.place((pc["pos"] as Vector3) + Vector3(0.7, 0, 0), 0.0)
			await get_tree().process_frame
			cargo._find_target()
			cargo.interact()
			var stowed := false
			for dpos in [Vector3(-1.3, 0, -0.1), Vector3(-1.0, 0, 1.7)]:
				walker.place(plane.global_transform * (dpos as Vector3), 0.0)
				await get_tree().process_frame
				cargo._find_target()
				if not cargo._target.is_empty() and cargo._target[0] == "open":
					cargo.interact()       # open the door first
				cargo._find_target()
				if not cargo._target.is_empty() and cargo._target[0] == "stow":
					cargo.interact()
					stowed = true
					break
			if not stowed:
				print("  load step: ", cargo.prompt, " holding=", not cargo.holding.is_empty())
		loaded2 = jobs.count_at(job2, "cabin") + jobs.count_at(job2, "bay")
		var mass_after: float = plane.gross_mass()
		_get_in(true)
		_on_start_requested(int(job2["to"]), false)
		await get_tree().create_timer(3.0).timeout
		var money_before: int = jobs.money
		_get_out()
		for i in range(4):
			await get_tree().process_frame
		for n in range((job2["pieces"] as Array).size()):
			for dpos in [Vector3(-1.3, 0, -0.1), Vector3(-1.0, 0, 1.7)]:
				walker.place(plane.global_transform * (dpos as Vector3), 0.0)
				await get_tree().process_frame
				cargo._find_target()
				if not cargo._target.is_empty() and cargo._target[0] == "open":
					cargo.interact()       # open the door first
				cargo._find_target()
				if not cargo._target.is_empty() and cargo._target[0] == "unstow":
					cargo.interact()
					break
			walker.place(plane.global_transform * Vector3(-5.0, 0, -0.1 + 0.8 * float(n)), 0.0)
			await get_tree().process_frame
			cargo._find_target()
			cargo.interact()
		paid2 = jobs.money - money_before
		_get_in(true)
		print("cargo by hand: %s, %d pieces, loaded %d, mass +%.0f kg, paid $%d, still carried %d" % [
			pj["title"], (job2["pieces"] as Array).size(), loaded2, mass_after - mass_before, paid2, jobs.carried.size()])
	else:
		print("cargo by hand: no suitable job offered")
	if not took2 or loaded2 != (job2["pieces"] as Array).size() or paid2 <= 0:
		problems += 1
	problems += await _pax_test()
	problems += await _fleet_test()
	problems += await _skydive_test()
	problems += await _mining_test()
	problems += await _build_test()
	problems += await _contract_test()
	# On foot: out of the plane, walk, run, jump, both views, back in.
	_set_cockpit(false)
	_on_start_requested(2, false)
	await get_tree().create_timer(3.0).timeout
	_get_out()
	var start_pos: Vector3 = walker.global_position
	var max_air := 0.0
	for i in range(300):
		walker.step(1.0 / 60.0, Vector2(0.3, 1.0), i > 150, i == 90)
		max_air = maxf(max_air, walker.global_position.y - world.terrain.ground_level_at(walker.global_position.x, walker.global_position.z))
		if i == 200:
			walker.first_person = false
		await get_tree().process_frame
	var walked := start_pos.distance_to(walker.global_position)
	var ct: Transform3D = walker.camera_transform()
	print("on foot: walked %.1f m, jump %.2f m, health %.2f, warmth %.2f, camera ok %s" % [walked, max_air, walker.health, walker.warmth, ct.origin.is_finite()])
	if walked < 6.0 or max_air < 0.3 or not ct.origin.is_finite():
		problems += 1
	walker.place(plane.global_transform * Vector3(-1.4, 0.0, -0.1), 0.0)
	_get_in(false)
	print("back in the plane: ", not on_foot)
	if on_foot:
		problems += 1
		_get_in(true)
	if worked < 12:
		problems += 1
	_set_cockpit(false)
	_on_start_requested(0, false)
	# Menu pages and settings
	for page in ["main", "strips", "load", "settings", "controls", "hotas"]:
		menu.open(page)
		await get_tree().process_frame
		await get_tree().process_frame
		menu.close()
	for season in [1, 2, 3, 0]:
		Game.season = season
		Game.realism = season % 2
		Game.wind_level = season
		Game.time_of_day = 6.0 + 5.0 * season
		Game.notify_changed()
		hud.show_map = true
		await get_tree().create_timer(1.0).timeout
		hud.show_map = false
	Game.realism = 0
	Game.wind_level = 1
	Game.time_of_day = 13.0
	Game.notify_changed()
	# A takeoff, a climb, then straight into the ground.
	_on_start_requested(0, false)
	plane.direct_controls = true
	var t := 0.0
	while t < 40.0 and not plane.is_crashed:
		plane.throttle = 1.0
		plane.brake = 0.0
		plane.in_pitch = clampf(4.0 * (deg_to_rad(8.0) - plane.pitch_rad()) - 0.8 * plane.omega.x, -1.0, 1.0)
		plane.in_roll = clampf(-2.5 * plane.roll_rad() + 0.5 * plane.omega.z, -1.0, 1.0)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("after climb: alt %.0f ft  ias %.0f kt  crashed=%s" % [plane.altitude_ft(), plane.ias_kt, plane.is_crashed])
	_tap("camera")
	t = 0.0
	while t < 60.0 and not plane.is_crashed:
		plane.in_pitch = -0.6
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("crash: ", plane.crash_reason, "  agl %.1f m, on_ground %s, ias %.0f" % [plane.altitude_ft() / 3.28, plane.on_ground, plane.ias_kt])
	await get_tree().create_timer(3.0).timeout
	_tap("confirm")
	await get_tree().create_timer(2.0).timeout
	print("after reset: on_ground=%s crashed=%s" % [plane.on_ground, plane.is_crashed])
	# Rebinding through the Controls page, with a key and with a controller button.
	menu.open("controls")
	await get_tree().process_frame
	menu._start_listening("camera", 0)
	var kev := InputEventKey.new()
	kev.physical_keycode = KEY_V
	kev.pressed = true
	Input.parse_input_event(kev)
	await get_tree().process_frame
	await get_tree().process_frame
	menu._start_listening("camera", 2)
	var jev := InputEventJoypadButton.new()
	jev.button_index = JOY_BUTTON_A
	jev.pressed = true
	Input.parse_input_event(jev)
	await get_tree().process_frame
	await get_tree().process_frame
	var cam_ok: bool = int(Game.bindings["camera"][0].get("code", 0)) == KEY_V and int(Game.bindings["camera"][2].get("i", -1)) == JOY_BUTTON_A
	var brake_lost: bool = (Game.bindings["brake"][2] as Dictionary).is_empty()
	print("rebind: camera now %s and %s, brake lost A=%s  %s" % [Game.binding_name(Game.bindings["camera"][0]), Game.binding_name(Game.bindings["camera"][2]), brake_lost, "" if cam_ok and brake_lost else "<-- PROBLEM"])
	if not (cam_ok and brake_lost):
		problems += 1
	Game.reset_bindings()
	print("after reset: camera %s / %s, brake pad %s" % [Game.binding_name(Game.bindings["camera"][0]), Game.binding_name(Game.bindings["camera"][2]), Game.binding_name(Game.bindings["brake"][2])])
	menu.close()
	await _hotas_test()
	# Finally fly through the same path a player's key presses take.
	Engine.time_scale = 3.0
	_on_start_requested(2, false)
	plane.direct_controls = false
	_test_keys = true
	Input.action_press("throttle_up")
	await get_tree().create_timer(9.0).timeout
	print("keys: throttle %.2f  speed %.1f m/s  brake %.1f  (%s/%s, %.0f kg, rpm %.0f)" % [plane.throttle, plane.ground_speed, plane.brake, plane.leg_kind, plane.tyre_kind, plane.mass, plane.engine.rpm])
	if plane.throttle < 0.95 or plane.ground_speed < 8.0:
		problems += 1
	Input.action_press("pitch_up")
	await get_tree().create_timer(12.0).timeout
	Input.action_release("pitch_up")
	print("keys: airborne=%s alt %.0f ft  ias %.0f kt  pitch %.1f  trim %.2f  crashed=%s" % [plane.airborne, plane.altitude_ft(), plane.ias_kt, rad_to_deg(plane.pitch_rad()), plane.trim, plane.is_crashed])
	await get_tree().create_timer(10.0).timeout
	print("keys, 10 s hands off: alt %.0f ft  ias %.0f kt  pitch %.1f  roll %.1f  crashed=%s" % [plane.altitude_ft(), plane.ias_kt, rad_to_deg(plane.pitch_rad()), rad_to_deg(plane.roll_rad()), plane.is_crashed])
	Input.action_release("throttle_up")
	_test_keys = false
	print("SELFTEST DONE, problems: ", problems + _hotas_problems)
	get_tree().quit()


var _hotas_problems := 0


## Flight gear, with a pretend device: the setup wizard binds a stick axis and a
## reversed throttle lever, then the plane follows them.
func _hotas_test() -> void:
	var hz: Node = Game.hotas
	hz._ids["|"] = 50
	hz.test_raw = {"50:0": -1.0, "50:1": 0.0, "50:2": 1.0}
	menu.open("hotas")
	await get_tree().process_frame
	menu._wiz_start(["roll", "throttle"])
	menu._wiz_next()                    # stick fully left
	hz.test_raw["50:0"] = 1.0
	menu._wiz_next()                    # fully right
	hz.test_raw["50:0"] = 0.0
	menu._wiz_next()                    # throttle at idle (this lever reads +1 at idle)
	hz.test_raw["50:2"] = -1.0
	menu._wiz_next()                    # full
	menu.close()
	var bound_ok: bool = hz.has_axis("roll") and hz.has_axis("throttle") and int(hz.axes["roll"]["a"]) == 0 and int(hz.axes["throttle"]["a"]) == 2
	_on_start_requested(2, false)
	await get_tree().create_timer(1.0).timeout
	_test_keys = true
	hz.test_raw["50:0"] = 0.6
	hz.test_raw["50:2"] = 0.0           # lever half way
	for i in range(10):
		await get_tree().process_frame
	_test_keys = false
	var thr: float = plane.throttle
	var rl: float = plane.in_roll
	var ok: bool = bound_ok and rl > 0.25 and absf(thr - 0.5) < 0.05
	print("hotas: roll on %s, throttle on %s, roll in %.2f, throttle %.2f %s" % [hz.axis_name("roll"), hz.axis_name("throttle"), rl, thr, "" if ok else "<-- PROBLEM"])
	if not ok:
		_hotas_problems += 1
	hz.test_raw.clear()
	hz.clear_all()
	hz._ids.erase("|")
	plane.in_roll = 0.0


func _tap(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


## Skim the wheels along Loon Lake at `speed` m/s, `dip` metres into the water,
## for four seconds, then climb away. Prints what happened.
func _skim_test(speed: float, tyre: String, dip: float) -> void:
	var lake: Dictionary = world.terrain.lakes[1]
	var level: float = lake["level"]
	plane.tyre_kind = tyre
	plane.leg_kind = String(_test.get("leg", "spring"))
	plane.apply_gear()
	plane.gear_down = true
	plane.frozen = false
	plane.place_in_air(Vector3(-9300.0, level + 2.6, -2200.0), 0.0, speed)
	plane.direct_controls = true
	plane.throttle = 0.75
	var t := 0.0
	var max_dip := 0.0
	var min_spd := 999.0
	var max_pitch := -99.0
	var min_pitch := 99.0
	var touched := 0.0
	var stop_at := float(_test.get("shotat", "9"))
	while t < minf(12.0, stop_at) and not plane.is_crashed:
		var xf: Transform3D = plane.global_transform
		var low := 1.0e9
		for i in range(2):
			low = minf(low, (xf * plane.wheel_pos[i]).y)
		var want := level - dip if t > 4.0 and t < 8.0 else level + (0.3 if t <= 4.0 else 12.0)
		var err := want - low
		var vs: float = plane.vel.y
		var tgt_vs := clampf(0.9 * err, -0.3 if absf(err) < 1.0 else -1.5, 2.0)
		var tgt_pitch := clampf(0.07 + 0.12 * (tgt_vs - vs), -0.06, 0.26)
		plane.in_pitch = clampf(8.0 * (tgt_pitch - plane.pitch_rad()) - 1.5 * plane.omega.x, -1.0, 1.0)
		plane.in_roll = clampf(-2.5 * plane.roll_rad() + 0.5 * plane.omega.z, -1.0, 1.0)
		plane.throttle = 1.0 if t > 8.0 else 0.75
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var wd: float = maxf(plane.wheel_water[0], plane.wheel_water[1])
		if wd > 0.0:
			touched += dt
		max_dip = maxf(max_dip, wd)
		if _test.has("trace") and fmod(t, 0.1) < dt:
			print("  t %.1f  wheels %.2f m above water  vs %.1f  dip %.2f  pitch %.1f  kt %.0f" % [t, low - level, plane.vel.y, wd, rad_to_deg(plane.pitch_rad()), plane.ias_kt])
		min_spd = minf(min_spd, plane.ias_kt)
		max_pitch = maxf(max_pitch, rad_to_deg(plane.pitch_rad()))
		min_pitch = minf(min_pitch, rad_to_deg(plane.pitch_rad()))
	if stop_at < 9.0:
		plane.frozen = true
	print("skim %s tyres at %.0f kt, %.2f m deep: in the water %.1f s, deepest %.2f m, slowest %.0f kt, pitch %.0f..%.0f, end alt %.0f ft, crashed=%s %s" % [
		tyre, speed * 1.944, dip, touched, max_dip, min_spd, min_pitch, max_pitch, plane.altitude_ft(), plane.is_crashed, plane.crash_reason])



## Amphibious floats on Loon Lake: sit, taxi round with the water rudders,
## then a take-off run. Prints what happened.
func _float_test() -> void:
	var lake: Dictionary = world.terrain.lakes[1]
	var c: Vector2 = lake["pos"]
	plane.leg_kind = "amphib"
	plane.apply_gear()
	plane.frozen = false
	Game.wind_level = int(_test.get("wind", "0"))
	plane.place_on_water(Vector3(c.x, 0.0, c.y + 500.0), 0.0)
	plane.direct_controls = true
	var t := 0.0
	while t < 6.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("floats at rest: draft %.2f / %.2f m, pitch %.1f, roll %.1f, speed %.1f, crashed=%s" % [plane.float_water[0], plane.float_water[1], rad_to_deg(plane.pitch_rad()), rad_to_deg(plane.roll_rad()), plane.ground_speed, plane.is_crashed])
	# Taxi: a bit of power, rudder right, centred, then left.
	for yaw_in in [1.0, 0.0, -1.0]:
		var h0: float = plane.heading_deg()
		t = 0.0
		plane.throttle = 0.35
		while t < 8.0:
			plane.in_yaw = yaw_in
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		print("taxi rudder %+.0f: turned %.0f deg in 8 s at %.1f kt, roll %.1f" % [yaw_in, wrapf(plane.heading_deg() - h0, -180.0, 180.0), plane.ground_speed * 1.944, rad_to_deg(plane.roll_rad())])
	plane.in_yaw = 0.0
	if _test.has("notakeoff"):
		return
	plane.throttle = 0.0
	t = 0.0
	while t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	# Take-off run into the lake.
	plane.flap_notch = 2
	plane.throttle = 1.0
	var start: Vector3 = plane.global_position
	var hdg0: float = plane.heading_deg()
	t = 0.0
	var off_t := -1.0
	var dry := 0.0
	var max_pitch := -99.0
	var min_pitch := 99.0
	var t40 := -1.0
	var log_t := 0.0
	while t < 70.0 and not plane.is_crashed:
		var kt: float = plane.ias_kt
		var tgt := 7.0 if kt < 20.0 else (4.5 if kt < 48.0 else 8.0)
		plane.in_pitch = clampf(0.15 * (tgt - rad_to_deg(plane.pitch_rad())) - 1.5 * plane.omega.x, -1.0, 1.0)
		plane.in_roll = clampf(-2.5 * plane.roll_rad() + 0.5 * plane.omega.z, -1.0, 1.0)
		plane.in_yaw = clampf(-0.04 * wrapf(plane.heading_deg() - hdg0, -180.0, 180.0) + 0.8 * plane.omega.y, -1.0, 1.0)
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		max_pitch = maxf(max_pitch, rad_to_deg(plane.pitch_rad()))
		min_pitch = minf(min_pitch, rad_to_deg(plane.pitch_rad()))
		if t40 < 0.0 and kt >= 40.0:
			t40 = t
		var wet: bool = plane.float_water[0] > 0.0 or plane.float_water[1] > 0.0
		dry = 0.0 if wet else dry + dt
		if off_t < 0.0 and dry > 1.0:
			off_t = t - 1.0
		if _test.has("trace") and t - log_t > 0.5:
			log_t = t
			print("  t %.0f  %.0f kt  pitch %.1f  roll %.1f  hdg %.0f  draft %.2f/%.2f  rud %.2f wy %.2f  aero %.0f contact %.0f" % [t, kt, rad_to_deg(plane.pitch_rad()), rad_to_deg(plane.roll_rad()), plane.heading_deg(), plane.float_water[0], plane.float_water[1], plane.rudder, plane.omega.y, plane.dbg_aero_yaw, plane.dbg_contact_yaw])
		if off_t > 0.0 and t > off_t + 5.0:
			break
	print("float take-off: 40 kt at %.0f s, off the water at %.0f s after %.0f m, pitch %.0f..%.0f, crashed=%s %s" % [t40, off_t, start.distance_to(plane.global_position), min_pitch, max_pitch, plane.is_crashed, plane.crash_reason])



## Passengers by hand: walk two aboard, fly them over, let them out, get paid.
## Tests start from an empty plane with half fuel, whatever earlier runs saved.
func _test_light_load() -> void:
	jobs.carried.clear()
	jobs._stow()
	plane.set_load(plane.fuel_capacity * 0.5, 0.0, 0.0)


func _pax_test() -> int:
	_on_start_requested(0, false)
	await get_tree().create_timer(3.0).timeout
	_test_light_load()
	var base: Array = jobs.board(0)
	if base.is_empty():
		print("pax: no job to copy")
		return 1
	var pj: Dictionary = (base[0] as Dictionary).duplicate()
	pj["kind"] = "pax"
	pj["title"] = "Passengers"
	pj["what"] = "2 passengers"
	pj["pax"] = 2
	pj["n"] = 2
	pj["kg"] = 170.0
	pj["id"] = 99901
	if not jobs.take(pj, true):
		print("pax: could not take the job: ", jobs.cannot_take(pj))
		return 1
	var job: Dictionary = jobs.carried.back()
	_get_out()
	for i in range(30):
		await get_tree().process_frame
	for pc in job["pieces"]:
		walker.place((pc["pos"] as Vector3) + Vector3(0.8, 0, 0), 0.0)
		await get_tree().process_frame
		cargo._find_target()
		cargo.interact()
	for i in range(900):
		await get_tree().process_frame
		if jobs.count_at(job, "cabin") == 2:
			break
	var boarded: int = jobs.count_at(job, "cabin")
	walker.place(plane.global_transform * Vector3(-1.4, 0.0, -0.1), 0.0)
	_get_in(false)
	_on_start_requested(int(job["to"]), false)
	await get_tree().create_timer(3.0).timeout
	var before: int = jobs.money
	_get_out()
	for i in range(5):
		await get_tree().process_frame
	for n in range(2):
		walker.place(plane.global_transform * Vector3(-1.3, 0, -0.1), 0.0)
		await get_tree().process_frame
		cargo._find_target()
		cargo.interact()
	var paid: int = jobs.money - before
	_get_in(true)
	print("pax by hand: boarded %d of 2, paid $%d, still carried %s %s" % [boarded, paid, str(job in jobs.carried), "" if boarded == 2 and paid > 0 else "<-- PROBLEM"])
	return 0 if boarded == 2 and paid > 0 else 1



## Fleet: buy a second plane at Port Ashby, swap into it, swap back.
func _fleet_test() -> int:
	_on_start_requested(0, false)
	await get_tree().create_timer(2.0).timeout
	jobs.money += fleet.PRICE
	var n0: int = fleet.planes.size()
	var reg0: String = plane.reg
	var err: String = fleet.buy()
	var bought: int = fleet.planes.size() - n0
	var err2: String = fleet.switch_to(fleet.planes.size() - 1, false)
	var reg1: String = plane.reg
	await get_tree().create_timer(1.0).timeout
	var parked: int = fleet.parked_at(0).size()
	var back := -1
	for i in range(fleet.planes.size()):
		if fleet.planes[i]["reg"] == reg0:
			back = i
	var err3: String = fleet.switch_to(back, true)
	var ok: bool = err == "" and bought == 1 and err2 == "" and reg1 != reg0 and parked >= 1 and err3 == "" and plane.reg == reg0
	print("fleet: bought %d (%s), flew %s, %d parked, back in %s %s" % [bought, err, reg1, parked, plane.reg, "" if ok else "<-- PROBLEM " + err2 + err3])
	return 0 if ok else 1



## Two copies on one machine: "net=host" and "net=join". The guest walks to
## the host's plane, rides along, asks for the controls and pulls back.
func _net_test(role: String) -> void:
	_test_keys = true
	plane.brake = 1.0
	if role == "host":
		net.player_name = "Host"
		print("net host: ", net.host())
	else:
		net.player_name = "Guest"
		await get_tree().create_timer(2.0).timeout
		print("net join: ", net.join("127.0.0.1"))
	var t := 0.0
	while t < 25.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not net.remotes.is_empty() and (net.remotes.values()[0] as Dictionary).get("node") != null:
			break
	print("net %s: online %s, remotes %d" % [role, net.is_online(), net.remotes.size()])
	if net.remotes.is_empty():
		get_tree().quit()
		return
	var id: int = net.remotes.keys()[0]
	var rp: Node3D = net.remotes[id]["node"]
	if role == "join":
		print("net join: their plane at %s (%s)" % [str(rp.global_position.round()), rp.reg])
		_get_out()
		walker.place(rp.global_transform * Vector3(1.6, 0, -0.1), 0.0)
		await get_tree().create_timer(0.5).timeout
		var at: int = net.plane_at_door(walker.global_position)
		if at != 0:
			_start_riding(at)
		net.controls_key()
		await get_tree().create_timer(2.0).timeout
		print("net join: riding %s, have control %s" % [net.riding != 0, net.have_control])
		Input.action_press("pitch_up")
		await get_tree().create_timer(3.0).timeout
		Input.action_release("pitch_up")
		await get_tree().create_timer(1.0).timeout
	else:
		var seen_ctl := false
		var max_pitch := 0.0
		var rode := false
		t = 0.0
		while t < 14.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if net.handed_to != 0:
				seen_ctl = true
			max_pitch = maxf(max_pitch, plane.in_pitch)
			if net.remotes.has(id) and int((net.remotes[id].get("last", {}) as Dictionary).get("ride", 0)) == multiplayer.get_unique_id():
				rode = true
		print("net host: guest rode in my plane %s, handed controls %s, stick from guest %.2f" % [rode, seen_ctl, max_pitch])
	get_tree().quit()



## Skydivers: take two up over the Port Ashby drop zone, green light, wait for
## them to land, check the pay.
func _skydive_test() -> int:
	_on_start_requested(0, false)
	await get_tree().create_timer(2.0).timeout
	_test_light_load()
	var job := {"id": 99902, "kind": "skydive", "title": "Skydivers", "from": 0, "to": 0, "what": "2 skydivers",
		"kg": 190.0, "pay": 600, "fragile": false, "urgent": false, "limit_min": 0.0, "pax": 2, "n": 2, "alt_ft": 3500}
	if not jobs.take(job):
		print("skydive: could not take: ", jobs.cannot_take(job))
		return 1
	var dz: Vector3 = jobs.drop_zone(0)
	plane.place_in_air(dz + Vector3(-150.0, 3500.0 / 3.28084 + 60.0, 0.0), 90.0, 38.0)
	plane.frozen = true
	await get_tree().process_frame
	var ready: String = skydive.ready_text()
	skydive.jump()
	plane.frozen = true
	var money0: int = jobs.money
	var t := 0.0
	Engine.time_scale = 4.0
	while t < 200.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var still := false
		for j in jobs.carried:
			if int(j["id"]) == 99902:
				still = true
		if not still:
			break
	Engine.time_scale = 1.0
	var paid: int = jobs.money - money0
	print("skydive: ready '%s', paid $%d after %.0f s %s" % [ready, paid, t, "" if paid > 0 else "<-- PROBLEM"])
	plane.frozen = false
	return 0 if paid > 0 else 1



## Mining: own the Salmon Bend claim, ship its sacks, sell them in Port Ashby.
## Fly a type: take off from Port Ashby, climb, then (twins) lose the left
## engine at 1,000 ft and see if it can be held straight and level-ish.
func _type_test(t: String) -> int:
	plane.apply_type(t)
	_apply_plane_type()
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	plane.set_load(plane.fuel_capacity * 0.5, 0.0, 0.0)
	plane.engine.set_running(15.0)       # whatever the engine-management setting
	plane.direct_controls = true
	var st: Dictionary = world.terrain.strips[0]
	var hdg: float = st["heading"]
	var start: Vector3 = plane.global_position
	plane.brake = 0.0
	plane.flap_notch = 1
	var t0 := 0.0
	var lift_d := -1.0
	var lift_kt := 0.0
	var dt := 1.0 / 60.0
	var phase := "roll"
	var fail_t := -1.0
	var rep := ""
	var max_yaw := 0.0
	while t0 < 150.0 and not plane.is_crashed:
		plane.throttle = 1.0
		var herr := wrapf(hdg - plane.heading_deg(), -180.0, 180.0)
		var want_pitch := deg_to_rad(8.0 if t != "dc3" else 7.0)
		if plane.on_ground and plane.ias_kt < (55.0 if t != "dc3" else 78.0):
			want_pitch = plane.pitch_rad() if plane.ias_kt < 30.0 else deg_to_rad(2.0)
		if fail_t >= 0.0:
			want_pitch = deg_to_rad(2.5)
		plane.in_pitch = clampf((9.0 if t == "dc3" else 3.0) * (want_pitch - plane.pitch_rad()) - 1.5 * plane.omega.x, -1.0, 1.0)
		if _test.has("hold"):
			# Like a player: keyboard, stick held full back once rolling.
			plane.direct_controls = false
			plane.in_pitch = 1.0 if plane.ias_kt > float(_test["hold"]) else 0.0
		plane.in_roll = clampf(-2.0 * (plane.roll_rad() - deg_to_rad(-0.0)) + 0.5 * plane.omega.z, -1.0, 1.0)
		plane.in_yaw = clampf(0.08 * herr - 1.5 * plane.omega.y, -1.0, 1.0)
		if lift_d < 0.0 and not plane.on_ground and plane.altitude_ft() - 46.0 > 0.0 and plane.airborne:
			lift_d = plane.global_position.distance_to(start)
			lift_kt = plane.ias_kt
			plane.flap_notch = 0
		var agl: float = plane.global_position.y - world.terrain.height_at(plane.global_position.x, plane.global_position.z)
		if plane.is_twin() and fail_t < 0.0 and agl > 100.0:
			fail_t = t0
			plane.fail_engine(0, "test")
			rep += " | failed left at %.0f kt, climb was %.0f fpm" % [plane.ias_kt, plane.vertical_speed_fpm()]
		if fail_t >= 0.0:
			max_yaw = maxf(max_yaw, absf(herr))
			if t0 - fail_t > 6.0 and not plane.feathered[0]:
				print("feather: ", plane.feather())
			if t0 - fail_t > 40.0:
				break
		if int(t0 / dt) % 300 == 0:
			print("  t %.0f agl %.0f m ias %.0f kt pitch %.1f vs %.0f thrust %.0f N power %.0f kW rpm %.0f mass %.0f gnd %s crash '%s'" % [t0, agl, plane.ias_kt, rad_to_deg(plane.pitch_rad()), plane.vertical_speed_fpm(), plane.thrust_now, plane.engine.power / 1000.0, plane.engine.rpm, plane.mass, plane.on_ground, plane.crash_reason])
		await get_tree().physics_frame
		t0 += dt
	print("type %s: lift-off after %.0f m at %.0f kt, after %.0f s: alt %.0f ft agl, %.0f kt, vs %.0f fpm, crashed=%s%s, worst heading error after failure %.0f deg, rudder %.2f" % [
		t, lift_d, lift_kt, t0, (plane.global_position.y - world.terrain.height_at(plane.global_position.x, plane.global_position.z)) * 3.28,
		plane.ias_kt, plane.vertical_speed_fpm(), plane.is_crashed, rep, max_yaw, plane.rudder])
	return 0


## Get known at Port Ashby, sign a contract, fly one load of it.
func _contract_test() -> int:
	_on_start_requested(0, false)
	await get_tree().create_timer(2.0).timeout
	_test_light_load()
	var nm := String(world.terrain.strips[0]["name"])
	var old_rep: int = int(jobs.rep.get(nm, 0))
	jobs.rep[nm] = maxi(old_rep, 3)
	var offers: Array = jobs.contract_offers(0)
	if offers.is_empty():
		print("contract: no offers <-- PROBLEM")
		return 1
	var c: Dictionary = offers[0]
	jobs.accept_contract(c)
	var load := {}
	for j in jobs.board(0):
		if int(j.get("contract", -1)) == int(c["id"]):
			load = j
	var took: bool = not load.is_empty() and jobs.take(load, false)
	var why: String = jobs.cannot_take(load) if not load.is_empty() else "no load on the board"
	_on_start_requested(int(c["to"]), false)
	await get_tree().create_timer(2.0).timeout
	var got := 0
	for j in jobs.deliverable():
		got += jobs.deliver(j)
	var done := 0
	for cc in jobs.contracts:
		if int(cc["id"]) == int(c["id"]):
			done = int(cc["done"])
	var ok: bool = took and got > 0 and done == 1
	print("contract: %s, took %s (%s), paid $%d, loads done %d %s" % [c["title"], took, why, got, done, "" if ok else "<-- PROBLEM"])
	jobs.contracts = jobs.contracts.filter(func(x): return int(x["id"]) != int(c["id"]))
	jobs.rep[nm] = old_rep
	jobs.save_career()
	return 0 if ok else 1


## A workable line for a bush strip somewhere round strip k0 (a survey), or {}.
func _find_strip_site(k0: int) -> Dictionary:
	var t: RefCounted = world.terrain
	var c: Vector3 = t.strips[k0]["pos"]
	for r in [700.0, 1100.0, 1600.0, 2200.0, 3000.0]:
		for a in range(12):
			for hdg in [0.0, 45.0, 90.0, 135.0]:
				var p: Vector3 = c + Vector3(cos(TAU * a / 12.0), 0, sin(TAU * a / 12.0)) * float(r)
				p.y = t.height_at(p.x, p.z)
				var s2: Dictionary = builds.survey(p, hdg, 300.0)
				if bool(s2["ok"]):
					return s2
	return {}


## Lay out a bush strip somewhere workable near Salmon Bend, then put up a
## cabin and a hangar at it, and check the strip is a real strip.
func _build_test() -> int:
	var t: RefCounted = world.terrain
	var k0 := 0
	_on_start_requested(k0, false)
	await get_tree().create_timer(2.0).timeout
	jobs.money += 50000
	var n0: int = t.strips.size()
	var sv: Dictionary = _find_strip_site(k0)
	if sv.is_empty():
		print("build: found no place for a strip <-- PROBLEM")
		return 1
	var err: String = builds.build_strip(sv, "Test Strip")
	var k: int = t.strips.size() - 1
	var ctr: Vector3 = sv["centre"]
	var on_it: bool = t.strip_index_at(ctr.x, ctr.z) == k
	var trees_left := 0
	for j in range(-6, 7):
		var p2: Vector3 = t.strip_point(k, float(j) * 20.0)
		if t.hits_tree(p2 + Vector3(0, 2, 0)):
			trees_left += 1
	builds.logs = 40
	var side: Vector3 = t.strip_point(k, 0.0, 45.0)
	var e1: String = builds.build("cabin", side, 0.0)
	var side2: Vector3 = t.strip_point(k, 80.0, 50.0)
	var e2: String = builds.build("hangar", side2, 0.0)
	var hangar_ok: bool = fleet.has_hangar(k)
	var ok: bool = err == "" and t.strips.size() == n0 + 1 and on_it and e1 == "" and (e2 == "" or e2.begins_with("The ground")) 
	print("build: strip %s (%d trees cut, $%d) on it %s, trees on it %d, cabin %s, hangar %s/%s %s" % [
		err if err != "" else "ok", int(sv["trees"]), int(sv["price"]), on_it, trees_left,
		e1 if e1 != "" else "ok", e2 if e2 != "" else "ok", hangar_ok, "" if ok else "<-- PROBLEM"])
	# Leave no test builds behind.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(builds.SAVE))
	return 0 if ok else 1


func _mining_test() -> int:
	var k := 0
	jobs.carried.clear()
	jobs._stow()
	_on_start_requested(k, false)
	await get_tree().create_timer(2.0).timeout
	var st: Dictionary = mining.state("Proving Ground Claim")
	st["stock_kg"] = 110.0
	var m0: int = jobs.money
	var msg: String = mining.ship(k, false)
	var got: int = jobs.money - m0
	var ok: bool = bool(st["owned"]) and got > 0
	print("mining: claim owned %s, %s %s" % [st["owned"], msg, "" if ok else "<-- PROBLEM"])
	return 0 if ok else 1


## DC-3 walk-through: out of the seat, aft through the cabin, out of the cargo
## door, back in, forward to the flight deck and into the seat.
func _walk_test() -> void:
	plane.apply_type("dc3")
	_apply_plane_type()
	_reset_to_last_strip()
	for i in range(30):
		await get_tree().process_frame
	_get_out()
	var lp := func() -> Vector3: return plane.global_transform.affine_inverse() * walker.global_position
	print("walktest: out of seat, inside %s at %s" % [walker.in_plane, lp.call()])
	var legs := [["to cabin", Vector3(0.0, 0, -3.0)], ["to door", Vector3(-0.6, 0, 3.2)]]
	for leg in legs:
		await _walk_to(leg[1], 8.0)
		print("walktest: %s -> inside %s at %s" % [leg[0], walker.in_plane, lp.call()])
	cargo._find_target()
	print("walktest: prompt at door: ", cargo.prompt)
	plane.door_open["bay"] = true
	await _walk_to(Vector3(-3.0, 0, 3.2), 4.0)
	print("walktest: walked out -> inside %s at %s" % [walker.in_plane, lp.call()])
	cargo._find_target()
	print("walktest: prompt outside: ", cargo.prompt)
	await _walk_to(Vector3(0.0, 0, 3.2), 4.0)
	print("walktest: walked in -> inside %s at %s" % [walker.in_plane, lp.call()])
	await _walk_to(Vector3(0.0, 0, -5.6), 10.0)
	print("walktest: flight deck -> inside %s at %s, near seat %s" % [walker.in_plane, lp.call(), walker.near_door()])
	_get_in(false)
	print("walktest: seated %s" % (not on_foot))


func _walk_to(local: Vector3, secs: float) -> void:
	var n := int(secs * 60.0)
	for i in range(n):
		var target: Vector3 = plane.global_transform * local
		var d := target - walker.global_position
		d.y = 0.0
		if d.length() < 0.15:
			break
		walker.look.x = atan2(-d.x, -d.z)
		walker.step(1.0 / 60.0, Vector2(0.0, 1.0), false, false)
		await get_tree().process_frame


## Engine work: open the cowling, look at parts, inspect and service them.
func _engine_test() -> void:
	_on_start_requested(0, false)
	for i in range(20):
		await get_tree().process_frame
	plane.engine.stop()
	_get_out()
	var xf: Transform3D = plane.global_transform
	walker.place(xf * Vector3(1.3, 0, -1.6), 0.0)
	await get_tree().process_frame
	print("enginetest: near nose %s, at hangar %s, prompt '%s'" % [service.near_nose(), service.at_hangar(), service.prompt if true else ""])
	service.find_target()
	print("enginetest: closed prompt: ", service.prompt)
	print("enginetest: ", service.toggle_cowl())
	# Look at the dipstick.
	for target in ["dipstick", "plug_3_top", "cyl_1", "mag_l", "air_filter"]:
		var spot: Array = []
		for sp in service.EngineModel.spots():
			if sp[0] == target:
				spot = sp
		var at: Vector3 = plane.global_transform * (spot[2] as Vector3)
		var eye: Vector3 = walker.camera_transform().origin
		var d := at - eye
		walker.look.x = atan2(-d.x, -d.z)
		walker.look.y = atan2(d.y, Vector2(d.x, d.z).length())
		_update_camera(0.016, true)
		service.find_target()
		print("enginetest: looking at %s -> part '%s' prompt '%s'" % [target, service.part, service.prompt])
	for a in [["dipstick", "check_oil"], ["plug_3_top", "read_plug"], ["cyl_1", "comp_all"], ["mag_l", "check_mag"], ["air_filter", "look_air"], ["dipstick", "oil_change"], ["plug_3_top", "all_plugs"], ["logbook", "overhaul"]]:
		var why := ""
		for ac in service.actions(a[0]):
			if ac[1] == a[1]:
				why = ac[2]
		var started: String = service.do(a[0], a[1]) if why == "" else ""
		var waited := 0
		while not service.job.is_empty() and waited < 1800:
			waited += 1
			await get_tree().process_frame
		print("enginetest: %s/%s %s-> %s" % [a[0], a[1], ("(blocked: " + why + ") ") if why != "" else "", service.result if why == "" else ""])
	print("enginetest: ", service.buy_spare("plug", 2), " ", service.spares_text())
	# Wear: a fouled engine runs rough and down on power.
	var e = plane.engine
	e.set_running(15.0)
	for i in range(e.plug_foul.size()):
		e.plug_foul[i] = 0.8
	e.comp[2] = 40.0
	e.mag_cond[1] = 0.1
	e.throttle = 1.0
	for i in range(300):
		e.update(1.0 / 60.0, 1.0, 101325.0, 15.0, 0.0, 0.3, false, 1)
	print("enginetest: abused engine power %.0f kW rough %.2f" % [e.power / 1000.0, e.roughness])
	for i in range(e.plug_foul.size()):
		e.plug_foul[i] = 0.0
	e.comp[2] = 78.0
	e.mag_cond[1] = 1.0
	for i in range(300):
		e.update(1.0 / 60.0, 1.0, 101325.0, 15.0, 0.0, 0.3, false, 1)
	print("enginetest: fixed engine power %.0f kW rough %.2f" % [e.power / 1000.0, e.roughness])



# ------------------------------------------------------------------------------
#  Forklifts
# ------------------------------------------------------------------------------
## The aircraft tug (DESIGN_NOTES 130), on the apron by the home hangar.
var tug: Node3D
func _make_tug() -> void:
	var t: RefCounted = world.terrain
	var at := Vector3.INF
	for c in [Vector3(-40.0, 0, -80.0), Vector3(-44.0, 0, -84.0), Vector3(-36.0, 0, -76.0), Vector3(-30.0, 0, -72.0), Vector3(-50.0, 0, -90.0)]:
		var q: Vector3 = c
		q.y = t.ground_level_at(q.x, q.z)
		if not t.blocked_by_building(q + Vector3(0, 0.5, 0), 2.2):
			at = q
			break
	if at == Vector3.INF:
		at = Vector3(-40.0, t.ground_level_at(-40.0, -80.0), -80.0)
	tug = load("res://scripts/tug.gd").new()
	tug.name = "Tug"
	tug.terrain = t
	tug.plane = plane
	tug.planes = func() -> Array:
		var ps: Array = [plane]
		for n in fleet._parked_nodes.values():
			if n != null and is_instance_valid(n):
				ps.append(n)
		for e in world.sale_planes:
			if e["node"] != null and is_instance_valid(e["node"]):
				ps.append(e["node"])
		return ps
	tug.towables = func() -> Array: return prospect.towables
	add_child(tug)
	tug.build()
	tug.load_or_park(Transform3D(Basis(Vector3.UP, PI * 0.5), at))
	machine_sound(tug, "machine", Vector3(0, 0.6, -0.6), 3.5)


func _make_forklifts() -> void:
	var t: RefCounted = world.terrain
	for k in range(t.strips.size()):
		if not jobs.has_forklift(k):
			continue
		var st: Dictionary = t.strips[k]
		var p: Vector3 = t.strip_point(k, -float(st["length"]) * 0.5 + 22.0)
		var b := Basis(Vector3.UP, -deg_to_rad(float(st["heading"])))
		# Off the left side of where planes park, nosed toward the strip.
		var at: Vector3 = p + b * Vector3(-16.0, 0, 12.0)
		at.y = t.ground_level_at(at.x, at.z)
		var fl := ForkliftScript.new()
		fl.name = "Forklift%d" % k
		fl.terrain = t
		fl.jobs = jobs
		fl.plane = plane
		add_child(fl)
		fl.build()
		fl.park(Transform3D(b * Basis(Vector3.UP, -PI * 0.5), at))
		forklifts.append(fl)
		machine_sound(fl, "machine", Vector3(0, 1.0, 0.6), 4.0)
	cargo.forklifts = forklifts


func _forklift_near() -> Node3D:
	for fl in forklifts:
		var seat: Vector3 = (fl as Node3D).global_transform * Vector3(0, 0, 0.3)
		if Vector2(seat.x - walker.global_position.x, seat.z - walker.global_position.z).length() < 1.8:
			return fl
	for ex in prospect.excavators:
		var c: Vector3 = (ex as Node3D).global_position
		if Vector2(c.x - walker.global_position.x, c.z - walker.global_position.z).length() < 2.4:
			return ex
	if pickup != null:
		var pdoor: Vector3 = pickup.step_out_point()
		if Vector2(pdoor.x - walker.global_position.x, pdoor.z - walker.global_position.z).length() < 1.8:
			return pickup
	if tug != null:
		var tsd: Vector3 = tug.global_transform * Vector3(0, 0, 0.5)
		if Vector2(tsd.x - walker.global_position.x, tsd.z - walker.global_position.z).length() < 1.8:
			return tug
	if loader != null:
		var ld: Vector3 = loader.step_out_point()
		if Vector2(ld.x - walker.global_position.x, ld.z - walker.global_position.z).length() < 2.2:
			return loader
	for wt2 in [water_truck, fuel_truck]:
		if wt2 != null:
			var door: Vector3 = wt2.step_out_point()
			if Vector2(door.x - walker.global_position.x, door.z - walker.global_position.z).length() < 2.2:
				return wt2
	for tn in prospect.tunnelers:
		var ts: Vector3 = tn.step_out_point()
		if Vector2(ts.x - walker.global_position.x, ts.z - walker.global_position.z).length() < 2.0:
			return tn
	for dzn in prospect.dozers:
		var c2: Vector3 = (dzn as Node3D).global_position
		if Vector2(c2.x - walker.global_position.x, c2.z - walker.global_position.z).length() < 2.8:
			return dzn
	return null


func _get_on_forklift(fl: Node3D) -> void:
	driving = fl
	fl.driven = true
	walker.look.x = fl.yaw
	walker.look.y = -0.15
	walker.first_person = true
	if fl == pickup:
		walker.vehicle_cam = 11.0
		walker.look.x = fl.yaw
		walker.look.y = -0.24        # the cluster and the road both in view
		_machine_tip("In the pickup. %s drive (back on %s brakes, then reverses), %s handbrake, I engine, V lights, Z / X blinkers, %s hitch / unhitch (back the ball up under a tongue), %s get out. On foot: Y at the front for the hood, at the back for the tailgate. Load cargo into the bed on foot at the tailgate." % [
			hud._keys(["pitch_down", "roll_left", "pitch_up", "roll_right"]), hud._keys(["pitch_up"]), Game.hint("brake"), Game.hint("interact"), Game.hint("get_out")], 9.0)
		return
	if fl == tug:
		walker.vehicle_cam = 9.0
		walker.look.x = fl.yaw
		walker.look.y = -0.2
		_machine_tip("On the tug. %s drive, %s at the plane's tailwheel hooks the tow bar on (engines off) - it follows tail first, back up to push it. %s again unhooks, %s gets off." % [
			hud._keys(["pitch_down", "roll_left", "pitch_up", "roll_right"]), Game.hint("interact"), Game.hint("interact"), Game.hint("get_out")], 9.0)
		return
	if fl == loader:
		walker.vehicle_cam = 12.0
		walker.look.x = fl.yaw
		walker.look.y = -0.12
		_machine_tip(loader.controls_hint(), 10.0)
		return
	if fl.has_method("truck_action"):
		walker.vehicle_cam = 14.0
		walker.look.x = fl.yaw
		walker.look.y = -0.1
		_machine_tip("In the water truck. %s drive (back on %s brakes, then reverses), %s handbrake, I engine, 6 pump on/off, %s fill at water / sprays on-off, %s get out. The suction hose is on the left at the back: park with it by the pond, the creek or a flooded hole." % [
			hud._keys(["pitch_down", "roll_left", "pitch_up", "roll_right"]), hud._keys(["pitch_up"]), Game.hint("brake"), Game.hint("interact"), Game.hint("get_out")], 10.0)
		return
	if fl.has_method("blade_toggle"):
		walker.look.x = fl.yaw
		walker.look.y = -0.2
		_machine_tip("In the dozer. %s drive the tracks, %s blade down / up, %s / %s raise / lower it by hand (below the tracks it cuts down, a ramp a pass). Push with the blade down and the ground is cut and filled: roads, pads, ramps. %s get out." % [
			hud._keys(["pitch_down", "roll_left", "pitch_up", "roll_right"]), Game.hint("interact"), Game.hint("throttle_up"), Game.hint("throttle_down"), Game.hint("get_out")], 9.0)
		return
	if fl.has_method("machine_action"):
		walker.vehicle_cam = 10.0
		walker.look.x = fl.yaw
		walker.look.y = -0.12
		_machine_tip("On the drift miner. %s drive the tracks, %s start / stop the cutter and drive into the face, %s / %s raise / lower the boom to cut up or down a grade. Pay gravel fills the tub on the back: out in the open, %s with the cutter off tips it (into the wash plant's hopper if you've backed up to it). %s get off." % [
			hud._keys(["pitch_down", "roll_left", "pitch_up", "roll_right"]), Game.hint("interact"), Game.hint("throttle_up"), Game.hint("throttle_down"), Game.hint("interact"), Game.hint("get_out")], 11.0)
		return
	if fl.has_method("dig_or_dump"):
		walker.look.x = fl.cab_yaw()
		walker.look.y = -0.45
		_machine_tip("In the excavator. %s drive the tracks, look where to dig (the arm follows), %s dig / dump, %s get out. %s changes mode: Auto, Boom (raise / lower the bucket yourself with the triggers) or Levers (every joint by hand). Dump into the wash plant's hopper to wash out the gold." % [
			hud._keys(["pitch_down", "roll_left", "pitch_up", "roll_right"]), Game.hint("interact"), Game.hint("get_out"), Game.hint("door")], 9.0)
		return
	_machine_tip("On the forklift. %s drive, %s / %s forks up / down, %s pick up or set down, %s get off." % [
		hud._keys(["pitch_down", "roll_left", "pitch_up", "roll_right"]), Game.lever_hint(true), Game.lever_hint(false), Game.hint("interact"), Game.hint("get_out")], 7.0)


## Ear muffs (the item): J puts them on or takes them off. On, they're on his
## head (walking and in the seat) and everything sounds muffled (audio.gd).
var _muffs_on := false
var _muffs_was := false
var _muffs_given := false
func _sync_ear_muffs() -> void:
	if not InputMap.has_action("ear_muffs"):
		InputMap.add_action("ear_muffs")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_J
		InputMap.action_add_event("ear_muffs", ev)
	if inv == null:
		return
	if not _muffs_given:
		_muffs_given = true
		if not inv.has("ear_muffs"):
			inv.add("ear_muffs")                 # a game saved before there were ear muffs
	if Input.is_action_just_pressed("ear_muffs"):
		if not inv.has("ear_muffs"):
			hud.push_message("No ear muffs on you.", 2.0)
		else:
			_muffs_on = not _muffs_on
			hud.push_message("Ear muffs on." if _muffs_on else "Ear muffs off.", 1.5)
	var wear: bool = _muffs_on and inv.has("ear_muffs")
	if wear != _muffs_was:
		_muffs_was = wear
		load("res://scripts/audio.gd").set_muffled(wear)
	for who in [walker.get("model") if walker != null else null, seated]:
		if who != null and is_instance_valid(who) and (who as Object).has_method("ear_muffs"):
			if bool((who as Node).get_meta("muffs", false)) != wear:
				(who as Node).set_meta("muffs", wear)
				who.ear_muffs(wear)


## A headlamp on the pilot's head (dark underground).
var _headlamp_on := false
var _headlamp: SpotLight3D
func _sync_headlamp() -> void:
	if _headlamp == null:
		_headlamp = SpotLight3D.new()
		_headlamp.light_color = Color(1.0, 0.93, 0.78)
		_headlamp.light_energy = 3.4
		_headlamp.spot_range = 55.0          # (Dave: reach further - was 22 m)
		_headlamp.spot_attenuation = 0.75    # falls off slower, so the far end of the beam still lights
		_headlamp.spot_angle = 32.0
		_headlamp.spot_angle_attenuation = 1.6
		_headlamp.shadow_enabled = true
		cam.add_child(_headlamp)
		_headlamp.position = Vector3(0.08, 0.05, 0.0)
	_headlamp.visible = _headlamp_on and on_foot and inv != null and inv.has("headlamp")


## The shovel in the walker's right hand when it's held (and he's on foot).
var inv: Node                     # inventory.gd: hotbar + backpack
var water_sim: Node3D             # water_sim.gd: groundwater, flowing water, pumps
var power: Node                   # tunnel_power.gd: generators and rope lights
var fire: Node                    # fire.gd: wildfire on a 4 m grid
var hazards: Node3D               # crash_hazards.gd: sparks from cut wiring, spilled fuel (DESIGN_NOTES 155)
var crafting: Node                # crafting.gd: the workbench
var loader: Node3D                # loader.gd: wheel loader, bucket or forks
var water_truck: Node3D           # water_truck.gd: 4,000 gal, fills and sprays into water_sim
var fuel_truck: Node3D            # water_truck.gd as "fuel": diesel and avgas for everything else
var _fuel_bill := 0.0             # cents and fractions owed for fuel, paid a dollar at a time


## Where the fuel truck lives: beside the fuel pump nearest the apron.
func _fuel_truck_home() -> Transform3D:
	var best := Vector3(40.0, 0, -80.0)
	var bd := 1.0e9
	for fp in world.fuel_points:
		var d: float = (fp as Vector3).distance_to(Vector3(30.0, 0, -96.0))
		if d < bd:
			bd = d
			best = fp
	var at := best + Vector3(9.0, 0, 7.0)
	return Transform3D(Basis(Vector3.UP, PI * 0.5), at)


## Everything the fuel truck could fill: the planes take avgas, the trucks and
## machines diesel (the pickup's old V8 runs fine on avgas too).
func _refuel_targets() -> Array:
	var out: Array = []
	if plane != null and plane.on_ground:
		var cap: float = plane.fuel_capacity
		var px: Transform3D = plane.global_transform
		out.append({"name": "plane", "kind": "avgas", "pos": plane.global_position, "need": maxf(cap - float(plane.fuel), 0.0) / 2.72,
			"fills": [px * Vector3(-0.9, 0.9, 0.15), px * Vector3(0.9, 0.9, 0.15)],
			"add": func(g: float) -> void: plane.fuel = minf(float(plane.fuel) + g * 2.72, plane.fuel_capacity)})
	if pickup != null:
		out.append({"name": "pickup", "kind": "avgas", "pos": pickup.global_position, "need": maxf(19.0 - pickup.fuel_gal, 0.0),
			"add": func(g: float) -> void: pickup.fuel_gal = minf(pickup.fuel_gal + g, 19.0)})
	if water_truck != null:
		out.append({"name": "water truck", "kind": "diesel", "pos": water_truck.global_position, "need": maxf(80.0 - water_truck.fuel_gal, 0.0),
			"add": func(g: float) -> void: water_truck.fuel_gal = minf(water_truck.fuel_gal + g, 80.0)})
	return out


## Pay for fuel off the pump, a bit at a time. False when you're broke.
func _pay_fuel(dollars: float) -> bool:
	if Game.sandbox or Game.free_repairs:
		return true
	if jobs == null:
		return true
	_fuel_bill += dollars
	if _fuel_bill >= 1.0:
		var whole := int(_fuel_bill)
		if jobs.money < whole:
			return false
		jobs.money -= whole
		_fuel_bill -= float(whole)
	return true
var pickup: Node3D                # pickup_truck.gd: bed for cargo, hitch for the gear
var log_trailer: Node3D           # log_trailer.gd: tandem trailer for logs (and cargo)
## The log deck in the tool yard: logs dropped here go into your stock.
const LOG_DECK := Vector3(-56.0, 0, -74.0)
const LOG_TRAILER_HOME := Vector3(-60.0, 0, -86.0)


## A few skids and a pile of logs, so you can see where the deck is.
func _build_log_deck() -> void:
	var t: RefCounted = world.terrain
	var k := MeshKit.new()
	var bark := Color(0.30, 0.22, 0.15)
	var cut := Color(0.80, 0.68, 0.48)
	var y: float = t.height_at(LOG_DECK.x, LOG_DECK.z)
	for sz in [-1.4, 1.4]:
		k.box_at(Vector3(0, 0.12, sz), Vector3(4.2, 0.24, 0.3), bark.darkened(0.2))
	for i in range(5):
		var lx := (float(i) - 2.0) * 0.4
		k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(lx, 0.42, -1.6)), 0.18, 0.17, 3.2, 9, bark, false)
		k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(lx, 0.42, -1.61)), 0.17, 0.17, 0.01, 9, cut, true)
	# sign post
	k.box_at(Vector3(2.6, 0.9, 0), Vector3(0.1, 1.8, 0.1), bark)
	k.box_at(Vector3(2.6, 1.7, 0), Vector3(0.05, 0.45, 1.1), Color(0.75, 0.62, 0.38))
	var mi: MeshInstance3D = k.instance("LogDeck")
	mi.position = Vector3(LOG_DECK.x, y, LOG_DECK.z)
	add_child(mi)
	var l := Label3D.new()
	l.text = "LOG DECK"
	l.font_size = 64
	l.pixel_size = 0.006
	l.modulate = Color(0.12, 0.09, 0.06)
	l.outline_size = 0
	l.position = Vector3(LOG_DECK.x + 2.63, y + 1.7, LOG_DECK.z)
	l.rotation = Vector3(0, PI * 0.5, 0)
	add_child(l)
var gore: Node3D                  # gore.gd: blood spray and splats
var birds: Node3D                 # birds.gd: flocks and bird strikes
var _hdoor: Node3D = null         # the hangar door switch you're standing at
var _app_focused := true          # the game window has focus (mouse is only captured then)
var _mouse_free := false          # let go of the mouse until you click back in the game


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_app_focused = false
		_mouse_free = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_app_focused = true
var _hand_id := "-"
var _ground_item := {}
var inv_ui: Control
var _hand_node: Node3D
func _sync_shovel() -> void:
	if inv == null:
		return
	var want: String = inv.in_hand() if (on_foot and driving == null and not walker.swimming) else ""
	if want == "pistol" and not walker.aiming:
		want = "pistol_holster"          # drawn only when it's up
	if want != _hand_id and walker.model.has_method("hold_tool"):
		_hand_id = want
		if _hand_node != null:
			walker.model.hold_tool(null)
			_hand_node.queue_free()
			_hand_node = null
		if want != "":
			_hand_node = inv.build_mesh(want)
			walker.model.hold_tool(_hand_node)


## Natural caves (branching systems) then the player's own saved digs.
func _cut_caves() -> void:
	var vg: Node = world.ground_view
	if vg == null or not vg.has_method("cut_caves"):
		return
	var t: RefCounted = world.terrain
	var keep := func(x: float, z: float) -> bool:
		if t.strip_index_at(x, z, 14.0) >= 0:
			return true
		if absf(x + 25.0) < 85.0 and absf(z + 94.0) < 34.0:     # apron and hangar
			return true
		var mp: Vector3 = t.clearings[1]
		if Vector2(x - mp.x, z - mp.z).length() < 32.0:          # mining pad
			return true
		if Vector2(x, z).distance_to(t.lakes[0]["pos"]) < float(t.lakes[0]["radius"]) + 9.0:   # Claim Pond
			return true
		return false
	var n: int = vg.cut_caves(1897, keep)
	vg.replay(prospect.vox_edits)
	print("caves: %d cuts, %d of your own digs replayed, openings at %s" % [n, prospect.vox_edits.size(), str(vg.cave_openings)])


func _lever_hint(ex: Node3D) -> void:
	if ex.levers:
		hud.push_message("Levers. %s swing, %s stick out / in, %s / %s boom up / down, %s / %s curl / dump the bucket. On a pad: left stick swing and stick, right stick boom and bucket. Bite in, drag the bucket toward you to fill it, swing, open it to dump. %s back to driving." % [
			hud._keys(["roll_left", "roll_right"]), hud._keys(["pitch_down", "pitch_up"]), Game.hint("throttle_up"), Game.hint("throttle_down"),
			Game.hint("flaps_up"), Game.hint("flaps_down"), Game.hint("door")], 10.0)
	elif ex.mode == 1:
		hud.push_message("Boom mode. Drive and look where to dig as before, and %s / %s raise / lower the bucket yourself. Stuck in a hole? Swing onto the bank, hold the bucket down so it plants and lifts her, and drive: the arm drags her out. %s dig / dump, %s for the levers." % [Game.lever_hint(true), Game.lever_hint(false), Game.hint("interact"), Game.hint("door")], 9.0)
	else:
		hud.push_message("Auto mode. Look where to dig, %s dig / dump. %s for boom mode (raise / lower the bucket yourself)." % [Game.hint("interact"), Game.hint("door")], 5.0)


func _get_off_forklift() -> void:
	var fl := driving
	driving = null
	walker.vehicle_cam = 0.0
	walker.model.transform = Transform3D.IDENTITY
	walker.seat_tilt = Basis.IDENTITY
	fl.driven = false
	if fl.has_method("truck_action") or fl.has_method("swap_attachment") or fl.has_method("tow_toggle") or fl.has_method("machine_action"):
		walker.place(fl.step_out_point(), fl.yaw)
		return
	if fl.has_method("dig_or_dump"):
		walker.place(fl.global_transform * Vector3(-2.5, 0, 0.3), fl.yaw)
		return
	if "speed" in fl:
		fl.speed = 0.0
	# The dozer is wide: step off beside the tracks, not into them.
	var side := 2.4 if fl.has_method("blade_text") or String(fl.get_script().resource_path).get_file() == "dozer.gd" else 1.0
	walker.place(fl.global_transform * Vector3(side, 0, 0.3), fl.yaw)


## One physics step on the forklift: drive it, keep the pilot in the seat.
func _drive_forklift(delta: float, move: Vector2) -> void:
	# damage (DESIGN_NOTES 137): a hurt engine pulls less, a wrecked one won't
	# run, bent running gear is slower and pulls to a side
	if vdamage != null:
		var vk := _veh_key(driving)
		if vdamage.dead(vk):
			if driving.get("engine_on") == true:
				driving.engine_on = false
				hud.push_message("The engine's wrecked: it won't run. Get it to the workshop (menu, Workshop).", 5.0)
			if driving.get("engine_on") == null:
				if absf(move.y) > 0.3:
					hud.push_message("It's wrecked: it won't go. Get it to the workshop (menu, Workshop).", 4.0)
				move.y = 0.0
		move.y *= vdamage.power_k(vk) * vdamage.speed_k(vk) if not vdamage.dead(vk) else 1.0
		if absf(move.y) > 0.1:
			move.x = clampf(move.x + vdamage.pull(vk), -1.0, 1.0)
	# On a pad the triggers are the pedals on every machine: RT go, LT brake
	# then reverse (DESIGN_NOTES 152). The forks, arms, blade and boom go on
	# the right stick (pull back = up) and Shift / Ctrl on the keyboard.
	var trig := _pedal_triggers()
	if absf(trig) > 0.02 and not (driving.has_method("dig_or_dump") and driving.levers):
		move.y = trig
	if driving.has_method("swap_attachment"):
		var y0l: float = driving.yaw
		var lift_in := _implement_axis()
		var tilt_in := (1.0 if Input.is_action_pressed("flaps_up") else 0.0) - (1.0 if Input.is_action_pressed("flaps_down") else 0.0)
		var lm: String = driving.drive(delta, move, lift_in, tilt_in, Input.is_action_pressed("brake"))
		if lm != "":
			hud.push_message(lm, 4.0)
		walker.look.x += driving.yaw - y0l
		var le: Transform3D = driving.eye_xf()
		walker.yaw = driving.yaw
		walker.rotation = Vector3(0, walker.yaw, 0)
		_seat_driver(delta, le)
		return
	if driving.has_method("truck_action") or driving.has_method("four_wd_toggle"):
		pass
	if driving.has_method("truck_action"):
		var y0t: float = driving.yaw
		var tm: String = driving.drive(delta, move, Input.is_action_pressed("brake"))
		if tm != "":
			hud.push_message(tm, 4.0)
		walker.look.x += driving.yaw - y0t
		var te: Transform3D = driving.eye_xf()
		walker.yaw = driving.yaw
		walker.rotation = Vector3(0, walker.yaw, 0)
		_seat_driver(delta, te)
		return
	if driving.has_method("blade_toggle"):
		driving.blade_adjust(delta, _implement_axis())
		var y0d: float = driving.yaw
		var dmsg: String = driving.drive(delta, move)
		if dmsg != "":
			hud.push_message(dmsg, 4.0)
		walker.look.x += driving.yaw - y0d
		var dz_eye: Transform3D = driving.eye_xf()
		walker.yaw = driving.yaw
		walker.rotation = Vector3(0, walker.yaw, 0)
		_seat_driver(delta, dz_eye)
		return
	if driving.has_method("machine_action"):
		var y0m: float = driving.yaw
		var mm: String = driving.drive(delta, move, _implement_axis())
		if mm != "":
			hud.push_message(mm, 4.0)
		walker.look.x += driving.yaw - y0m
		var me: Transform3D = driving.eye_xf()
		walker.yaw = driving.yaw
		walker.rotation = Vector3(0, walker.yaw, 0)
		_seat_driver(delta, me)
		return
	if driving.has_method("dig_or_dump"):
		var y0: float = driving.yaw
		var s0: float = driving.swing
		var msg := ""
		if driving.levers:
			# ISO pattern. Keys: W/S stick out/in, A/D swing, Shift/Ctrl boom
			# up/down, R/F curl/dump. Pad: left stick swing + stick, right
			# stick boom (pull back = up) + bucket (left = curl), triggers boom.
			var sw := Input.get_axis("roll_left", "roll_right")
			var st := Input.get_axis("pitch_up", "pitch_down")
			var bm := Input.get_axis("throttle_down", "throttle_up") + Input.get_axis("look_up", "look_down")
			var bk := Input.get_axis("look_right", "look_left")
			bk += (1.0 if Input.is_action_pressed("flaps_up") else 0.0) - (1.0 if Input.is_action_pressed("flaps_down") else 0.0)
			msg = driving.levers_step(delta, sw, st, clampf(bm, -1.0, 1.0), clampf(bk, -1.0, 1.0))
			walker.look.x += driving.swing - s0
		else:
			driving.boom_in = _implement_axis() if driving.mode == 1 else 0.0
			driving.drive(delta, move)
			walker.look.x += driving.yaw - y0
			var ct: Transform3D = cam.global_transform
			driving.aim_from(ct.origin, -ct.basis.z)
			msg = driving.work(delta)
		if msg != "":
			hud.push_message(msg, 4.0)
		var ex_eye: Transform3D = driving.eye_xf()
		walker.yaw = driving.cab_yaw()
		walker.rotation = Vector3(0, walker.yaw, 0)
		_seat_driver(delta, ex_eye)
		return
	var before: float = driving.yaw
	driving.drive(delta, move, _implement_axis())
	walker.look.x += driving.yaw - before
	var eye: Transform3D = driving.eye_xf()
	walker.yaw = driving.yaw
	walker.rotation = Vector3(0, driving.yaw, 0)
	_seat_driver(delta, eye)


## The driver in the seat of whatever he's driving: sitting pose, eyes at the
## machine's eye point, and his body drawn whenever the camera is outside
## (first person draws it only into the shadows, so the view isn't inside his head).
func _seat_driver(delta: float, eye: Transform3D) -> void:
	walker.model.animate(delta, PilotModel.DRIVE, 0.0, _clock)
	if walker.model.has_method("set_head_visible"):
		walker.model.set_head_visible(not walker.first_person)
	elif walker.model.get("head_part") != null:
		walker.model.head_part.visible = not walker.first_person
	walker.visible = true
	var yb := Basis(Vector3.UP, walker.yaw)
	var el: Vector3 = walker.model.eye_local()
	walker.global_position = eye.origin - yb * el
	# He sits IN the seat: his body takes the machine's pitch and roll (and a
	# rollover), pivoting on his eyes so the view point doesn't move.
	var r: Basis = (yb.inverse() * eye.basis.orthonormalized()).orthonormalized()
	walker.model.transform = Transform3D(r, el - r * el)
	walker.seat_tilt = r


## Forklift: pallets off the ramp and into the DC-3, one back out again.
func _fork_test() -> void:
	plane.apply_type("dc3")
	_apply_plane_type()
	_on_start_requested(0, false)
	for i in range(30):
		await get_tree().process_frame
	plane.engine.stop()
	if plane.engine2 != null:
		plane.engine2.stop()
	var job := {"id": 9001, "kind": "pallet", "title": "Mine machinery", "what": "3 pallets", "from": 0, "to": 3,
		"kg": 1200.0, "pay": 900, "fragile": false, "urgent": false, "limit_min": 0.0, "pax": 0, "n": 3}
	print("forktest: take ", jobs.take_custom(job, true), " forklifts ", forklifts.size())
	for i in range(3):
		await get_tree().process_frame
	_get_out()
	var fl: Node3D = forklifts[0]
	walker.place(fl.global_transform * Vector3(1.2, 0, 0.3), 0.0)
	for i in range(3):
		await get_tree().process_frame
	print("forktest: near forklift %s prompt '%s'" % [_near_fork != null, cargo.extra_prompt])
	_get_on_forklift(fl)
	plane.door_open["bay"] = true
	var jb: Dictionary = jobs.carried.back()
	for n in range(3):
		var pc: Dictionary = jb["pieces"][n]
		# To the pallet, forks low.
		await _fork_drive_to(fl, pc["pos"], 0.05, 25.0)
		print("forktest: at pallet %d: %s" % [n, fl.fork_target()])
		print("forktest: ", fl.fork_action())
		# Out to a spot square off the door, then in with the forks at sill height.
		await _fork_drive_to(fl, plane.global_transform * Vector3(-7.5, 0, 3.2), 0.3, 25.0)
		await _fork_drive_to(fl, plane.global_transform * Vector3(-1.6, 0, 3.2), fl._sill_height() + 0.05, 15.0)
		var l: Vector3 = plane.global_transform.affine_inverse() * fl.fork_point()
		print("forktest: at door forks local (%.2f, %.2f, %.2f) sill %.2f: %s" % [l.x, l.y, l.z, fl._sill_height(), fl.fork_target()])
		print("forktest: ", fl.fork_action())
		await _fork_drive_to(fl, plane.global_transform * Vector3(-7.5, 0, 3.2), -1.0, 6.0, true)
	print("forktest: slots %s, job load front %.0f rear %.0f kg" % [jobs.pallet_slots().keys(), plane.job_front, plane.job_rear])
	await _fork_drive_to(fl, plane.global_transform * Vector3(-1.6, 0, 3.2), fl._sill_height() + 0.05, 15.0)
	print("forktest: unload: %s -> %s" % [fl.fork_target(), fl.fork_action()])
	print("forktest: slots now %s" % [jobs.pallet_slots().keys()])


## Drive the forklift so its forks reach `target` (world), forks at `lift_to` (-1: leave them).
func _fork_drive_to(fl: Node3D, target: Vector3, lift_to: float, secs: float, reverse: bool = false) -> void:
	for i in range(int(secs * 60.0)):
		var fp: Vector3 = fl.fork_point() if not reverse else fl.global_position
		var d := target - fp
		d.y = 0.0
		var lift_in := 0.0
		if lift_to >= 0.0:
			lift_in = clampf((lift_to - fl.lift) * 5.0, -1.0, 1.0)
		if d.length() < 0.25 and absf(lift_in) < 0.05:
			break
		var fwd: Vector3 = Basis(Vector3.UP, fl.yaw) * Vector3.FORWARD
		var e := fwd.signed_angle_to(d.normalized(), Vector3.UP)
		var mv := Vector2(clampf(-2.0 * e, -1.0, 1.0), clampf(d.length() * 0.6, 0.15, 1.0))
		if reverse:
			e = (-fwd).signed_angle_to(d.normalized(), Vector3.UP)
			mv = Vector2(clampf(2.0 * e, -1.0, 1.0), -clampf(d.length() * 0.6, 0.2, 1.0))
		if d.length() < 0.25:
			mv = Vector2.ZERO
		fl.drive(1.0 / 60.0, mv, lift_in)
		await get_tree().physics_frame


## Digging anywhere: pan by a creek, a sluice box, then an excavator and wash plant.
## Sink a shaft by hand: shovel through the soil, pick through the rock.
func _deep_test() -> void:
	Game.sandbox = true
	var t: RefCounted = world.terrain
	var vg: Node = world.ground_view
	_get_out()
	var c := Vector3(40.0, 0.0, -20.0)        # dry ground, table deep
	c.y = t.height_at(c.x, c.z)
	walker.place(c + Vector3(0, 0, 0.9), 0.0)  # facing -z, the shaft spot in front
	inv.remove("shovel", 9)
	inv.remove("pick", 9)
	inv.add("shovel", 1, true)
	var front := c
	var n_soil := 0
	var n_rock := 0
	for i in range(1500):
		var tg: Array = prospect.target(walker.global_position, front)
		if tg.is_empty() or String(tg[0]) == "":
			print("deeptest: stuck: ", tg)
			break
		if tg[0] == "dig_rock" and not inv.holding("pick"):
			inv.remove("shovel", 9)
			inv.add("pick", 1, true)
			print("deeptest: hit rock at %.1f m after %d shovelfuls: swapped to the pick" % [t.natural_at(c.x, c.z) - t.height_at(c.x, c.z), n_soil])
			continue
		prospect.act(String(tg[0]), walker.global_position, front)
		if tg[0] == "dig_rock":
			n_rock += 1
		else:
			n_soil += 1
		if t.natural_at(c.x, c.z) - t.height_at(c.x, c.z) > 20.0:
			break
	var depth: float = t.natural_at(c.x, c.z) - t.height_at(c.x, c.z)
	var wall: float = t.natural_at(c.x + 2.5, c.z) - t.height_at(c.x + 2.5, c.z)
	print("deeptest: %d shovelfuls + %d pick swings: shaft %.1f m deep, ground 2.5 m away dug %.1f m (rock walls stand) %s" % [n_soil, n_rock, depth, wall, "" if depth > 15.0 else "<-- PROBLEM"])
	for i in range(60):
		await get_tree().process_frame
	vg._mirror_edits()
	var vf: float = vg.floor_below(Vector3(c.x, t.height_at(c.x, c.z) + 0.5, c.z), 4.0)
	print("deeptest: voxel floor at the bottom %.2f vs ground %.2f, water table there %.1f" % [vf, t.height_at(c.x, c.z), t.water_table_at(c.x, c.z)])
	# the ladder: from the rim of the rock shaft down to the bottom and back
	var rim := Vector3(c.x, 0, c.z + 1.0)
	rim.y = t.height_at(rim.x, rim.z)
	walker.place(rim, 0.0)
	inv.add("ladder", 1, true)
	var fr: Vector3 = walker.global_transform * Vector3(0, 0, -0.9)
	var tg: Array = prospect.target(walker.global_position, fr)
	print("deeptest: at the rim with the ladder -> ", tg)
	if tg.is_empty() or tg[0] != "ladder":
		print("deeptest: no place to hang the ladder <-- PROBLEM")
		return
	print("deeptest: ", prospect.act("ladder", walker.global_position, fr))
	var bottom_y: float = prospect.ladders.back()[1]
	for i in range(2400):          # walk at it, then hold back to climb down
		walker.look = Vector2(0.0, 0.0)
		walker.step(1.0 / 60.0, Vector2(0, 1) if not walker.climbing else Vector2(0, -1), false, false)
		if walker.climbing == false and walker.global_position.y <= bottom_y + 0.05:
			break
	var down_y: float = walker.global_position.y
	for i in range(2400):          # forward climbs up and steps off at the top
		walker.look = Vector2(0.0, 0.0)
		walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
		if not walker.climbing and walker.global_position.y > rim.y - 0.5 and i > 30:
			break
	var up_y: float = walker.global_position.y
	print("deeptest: climbed down to %.2f (bottom %.2f) and back up to %.2f (rim %.2f) %s" % [down_y, bottom_y, up_y, rim.y,
		"" if absf(down_y - bottom_y) < 0.3 and up_y > rim.y - 0.5 else "<-- PROBLEM"])


## Groundwater into a pit, the creek running, a pump emptying the pit.
func _water_test() -> void:
	Game.sandbox = true
	var t: RefCounted = world.terrain
	var ws: Node = water_sim
	print("watertest: %d cells active at start (dug below the table / creek)" % ws.active.size())
	var t0 := Time.get_ticks_usec()
	for i in range(600):          # one minute of creek
		ws._step()
	print("watertest: 60 s of sim in %.0f ms, %d active, %.0f m3 standing (the creek)" % [(Time.get_ticks_usec() - t0) / 1000.0, ws.active.size(), ws.volume()])
	# a pit on the wet flats south of the pad, away from the creek
	var c := Vector3(20.0, 0.0, 95.0)
	var best := 99.0
	for gz in range(70, 112, 4):
		for gx in range(-60, 60, 4):
			var q := Vector3(gx, 0, gz)
			if t.creek_dist(q.x, q.z) < 12.0 or Vector2(q.x + 105.0, q.z - 105.0).length() < 45.0:
				continue
			var d: float = t.natural_at(q.x, q.z) - t.water_table_at(q.x, q.z)
			if d < best:
				best = d
				c = q
	c.y = t.height_at(c.x, c.z)
	print("watertest: pit at %s, water table %.2f m down" % [c, best])
	for k in range(220):
		var a := k * 0.61
		var r := 0.3 + (k % 44) * 0.07
		prospect.dig(c + Vector3(cos(a) * r, 0, sin(a) * r), 1.4, 0.45)
	var floor_y: float = t.height_at(c.x, c.z)
	var table: float = t.water_table_at(c.x, c.z)
	print("watertest: pit floor %.2f, table %.2f (%.2f m below it)" % [floor_y, table, table - floor_y])
	for i in range(3):
		await get_tree().process_frame          # ground -> sim heights
	for i in range(6000):          # ten minutes
		ws._step()
	var dep: float = ws.depth_at(c.x, c.z)
	var ok1: bool = dep > 0.5 * (table - floor_y)
	print("watertest: after 10 min the pit holds %.2f m of water, surface %.2f vs table %.2f %s" % [dep, floor_y + dep, table, "" if ok1 else "<-- PROBLEM"])
	print("watertest: water level for the walker there %.2f (wading)" % t.water_level_at(c.x, c.z))
	# the pump: set at the edge, run five minutes
	_get_out()
	var edge := c + Vector3(3.2, 0, 0)
	walker.place(edge, PI * 0.5)
	var got_pump: int = inv.add("pump", 1, true)
	var tg: Array = prospect.target(walker.global_position, walker.global_transform * Vector3(0, 0, -0.9))
	print("watertest: at the edge with the pump (picked up %d, in hand '%s', %.0f kg on him, water within 3 m %s) -> %s" % [got_pump, inv.in_hand(), inv.weight(), prospect._water_near(walker.global_position, 3.0) != Vector3.INF, tg])
	if tg.is_empty() or tg[0] != "pump_set":
		print("watertest: couldn't set the pump <-- PROBLEM")
		return
	print("watertest: ", prospect.act("pump_set", walker.global_position, walker.global_transform * Vector3(0, 0, -0.9)))
	var pd: Dictionary = ws.pumps.back()
	for i in range(3000):
		ws._pumps(0.1)
		ws._step()
	var dep2: float = ws.depth_at(c.x, c.z)
	var out: Vector3 = pd["out"]
	print("watertest: pumped %.1f m3, pit water %.2f -> %.2f m, water at the hose end %.2f m %s" % [float(pd["moved"]), dep, dep2, ws.depth_at(out.x, out.z), "" if dep2 < dep * 0.6 else "<-- PROBLEM"])


## Dig a pit, then drive a drift into its wall by hand and walk in and out.
func _tunnel_test() -> void:
	Game.sandbox = true
	var t: RefCounted = world.terrain
	var vg: Node = world.ground_view
	if vg == null or not vg.has_method("floor_below"):
		print("tunneltest: no voxel ground <-- PROBLEM")
		return
	_get_out()
	if _test.has("out"):
		get_viewport().disable_3d = true     # fast walking; pictures at the end
	var c := Vector3(20.0, 0.0, 15.0)
	for k in range(260):
		var a := k * 0.61
		var r := 0.4 + (k % 40) * 0.09
		prospect.dig(c + Vector3(cos(a) * r, 0, sin(a) * r), 1.6, 0.5)
	c.y = t.height_at(c.x, c.z)
	print("tunneltest: pit floor %.2f, natural %.2f" % [c.y, t.natural_at(c.x, c.z)])
	walker.place(c, -PI * 0.5)     # facing +x (east)
	if not inv.holding("shovel"):
		inv.remove("shovel", 9)
		inv.add("shovel", 1, true)
	for i in range(240):
		await get_tree().physics_frame
		if vg.ready_at(walker.global_position):
			break
	# walk east to the pit wall
	for i in range(240):
		walker.look = Vector2(-PI * 0.5, 0.0)
		walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
		await get_tree().physics_frame
	var at_wall: Vector3 = walker.global_position
	var front: Vector3 = walker.global_transform * Vector3(0, 0, -0.9)
	print("tunneltest: at the wall %s -> %s" % [at_wall, prospect.target(at_wall, front)])
	var bites := 0
	for n in range(30):
		var p: Vector3 = walker.global_position
		front = walker.global_transform * Vector3(0, 0, -0.9)
		prospect.aim_pitch = -0.45 if n < 10 else 0.0      # look down: drive it down a grade first
		var tg: Array = prospect.target(p, front)
		if not tg.is_empty() and String(tg[0]).begins_with("tunnel"):
			prospect.act(String(tg[0]), p, front)
			bites += 1
		for i in range(12):
			await get_tree().physics_frame
		for i in range(30):
			walker.look = Vector2(-PI * 0.5, 0.0)
			walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
			prospect.aim_pitch = -0.45 if n < 10 else 0.0
			await get_tree().physics_frame
	var deep: Vector3 = walker.global_position
	var roof: float = vg.sdf_at(deep + Vector3(0, 2.5, 0))
	var surf: float = t.height_at(deep.x, deep.z)
	var ok: bool = walker.underground() and deep.x - at_wall.x > 4.0 and roof < 0.0
	print("tunneltest: %d bites, walked in %.1f m, now %.2f below the surface, roof solid %s, floor y %.2f (pit %.2f), first person cam %s %s" % [
		bites, deep.x - at_wall.x, surf - deep.y, roof < 0.0, deep.y, c.y, walker.underground(), "" if ok else "<-- PROBLEM"])
	# try to walk through the side wall: should be stopped
	var side0: Vector3 = walker.global_position
	for i in range(120):
		walker.look = Vector2(0.0, 0.0)       # facing -z (north wall)
		walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
		await get_tree().physics_frame
	print("tunneltest: pushed into the side wall, moved %.2f m %s" % [walker.global_position.distance_to(side0), "" if walker.global_position.distance_to(side0) < 0.8 else "<-- PROBLEM"])
	# and walk back out
	for i in range(900):
		walker.look = Vector2(PI * 0.5, 0.0)
		walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
		await get_tree().physics_frame
		if not walker.underground() and walker.global_position.x < at_wall.x - 1.0:
			break
	print("tunneltest: back out: underground=%s at %s %s" % [walker.underground(), walker.global_position, "" if not walker.underground() else "<-- PROBLEM"])
	print("tunneltest: edits logged %d" % vg.edits.size())
	# Timber: stand two sets near the portal end, leave the rest bare, then let time pass.
	var n_roofs: int = prospect.roofs.size()
	var held_pts: Array = []
	if prospect.roofs.size() < 8:
		print("tunneltest: only %d roof spans under cover <-- PROBLEM" % prospect.roofs.size())
		return
	var kit_on := []
	for si in range(inv.slots.size()):
		var sd: Dictionary = inv.slots[si]
		if not sd.is_empty():
			kit_on.append("%s x%d" % [sd["id"], int(sd["n"])])
			if not String(sd["id"]) in ["shovel", "headlamp"]:
				inv.slots[si] = {}          # set the rest down: timber's heavy
	print("tunneltest: he had on him: %s" % ", ".join(kit_on))
	for k in [prospect.roofs.size() - 6, prospect.roofs.size() - 3]:
		var q: Vector3 = (prospect.roofs[k][0] as Vector3)
		print("tunneltest: picked up timber: ", inv.add("timber", 1, true), " (%.0f kg on him)" % inv.weight())
		walker.place(Vector3(q.x - 0.5, 0.0, q.z), -PI * 0.5)
		walker.global_position.y = vg.floor_below(Vector3(q.x - 0.5, q.y - 1.0, q.z), 4.0)
		var tg3: Array = prospect.target(walker.global_position, walker.global_transform * Vector3(0, 0, -0.9))
		print("tunneltest: timber -> %s / %s" % [tg3, prospect.act(String(tg3[0]) if not tg3.is_empty() else "", walker.global_position, walker.global_transform * Vector3(0, 0, -0.9))])
		held_pts.append(q)
	if _test.has("out"):
		# pictures of a timbered drift: a set every few metres, him in it with
		# the headlamp on, from behind and through his eyes
		var od0 := String(_test["out"])
		hud.visible = false
		get_viewport().disable_3d = false
		if inv_ui != null:
			inv_ui.visible = false
		for k in range(1, prospect.roofs.size(), 3):
			var q4: Vector3 = (prospect.roofs[k][0] as Vector3)
			inv.add("timber", 1, true)
			walker.place(Vector3(q4.x - 0.5, 0.0, q4.z), -PI * 0.5)
			walker.global_position.y = vg.floor_below(Vector3(q4.x - 0.5, q4.y - 1.0, q4.z), 4.0)
			prospect.set_timber(walker.global_position, walker.global_transform * Vector3(0, 0, -0.9))
		var r0: Vector3 = (prospect.roofs[2][0] as Vector3)
		walker.place(Vector3(r0.x - 1.0, 0.0, r0.z), -PI * 0.5)
		walker.global_position.y = vg.floor_below(Vector3(r0.x - 1.0, r0.y - 1.0, r0.z), 4.0)
		inv.add("pick", 1, true)
		_headlamp_on = true
		walker.first_person = false
		walker.cam_dist = 2.6
		for i in range(90):
			walker.look = Vector2(-PI * 0.5, -0.08)
			walker.step(1.0 / 60.0, Vector2.ZERO, false, false)
			await get_tree().process_frame
		await _snap(od0 + "/timber_drift_behind.png")
		walker.first_person = true
		for i in range(60):
			walker.look = Vector2(-PI * 0.5, 0.02)
			walker.step(1.0 / 60.0, Vector2.ZERO, false, false)
			await get_tree().process_frame
		await _snap(od0 + "/timber_drift_eyes.png")
		walker.look = Vector2(-PI * 0.5, 0.45)
		for i in range(30):
			walker.step(1.0 / 60.0, Vector2.ZERO, false, false)
			await get_tree().process_frame
		await _snap(od0 + "/timber_drift_roof.png")
		get_tree().quit()
		return
	prospect.walker_pos = Vector3.INF
	for i in range(40):
		prospect._ground_check(30.0)
	var still_open := 0
	for q2 in held_pts:
		if vg.sdf_at(q2 + Vector3(0, -0.8, 0)) > 0.0:
			still_open += 1
	print("tunneltest: %d roof spans, %d held by timber, %d left after the bare ones came in; timbered spots still open %d/2 %s" % [
		n_roofs, prospect.sets.size(), prospect.roofs.size(), still_open, "" if still_open == 2 and prospect.roofs.size() < n_roofs else "<-- PROBLEM"])
	if _test.has("out"):
		# pictures: in the drift with the headlamp, at the portal with the shovel, the backpack
		var od := String(_test["out"])
		for i in range(240):
			walker.look = Vector2(-PI * 0.5, -0.05)
			walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
			await get_tree().physics_frame
		_headlamp_on = true
		walker.first_person = true
		for i in range(180):
			walker.look = Vector2(-PI * 0.5, -0.12)
			walker.step(1.0 / 60.0, Vector2.ZERO, false, false)
			await get_tree().process_frame
		get_viewport().disable_3d = false
		for i in range(30):
			await get_tree().process_frame
		await _snap(od + "/mine_inside.png")
		walker.place(at_wall + Vector3(-4.5, 0, 1.2), -PI * 0.5 - 0.3)
		walker.first_person = false
		walker.cam_dist = 3.2
		for i in range(120):
			walker.look = Vector2(-PI * 0.5 + 2.4, -0.18)
			walker.step(1.0 / 60.0, Vector2.ZERO, false, false)
			await get_tree().process_frame
		await _snap(od + "/mine_portal.png")
		inv_ui.toggle()
		await _snap(od + "/inventory.png")
		inv_ui.toggle()


func _snap(path: String) -> void:
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("snap: ", path)


func _dig_test() -> void:
	Game.sandbox = true
	# Find a creek bed with water near the start strip.
	var t: RefCounted = world.terrain
	var best := Vector3.INF
	var best_g := 0.0
	var c0: Vector3 = plane.global_position
	c0 = Vector3.ZERO
	for gz in range(-34, 35):
		for gx in range(-34, 35):
			var q: Vector3 = c0 + Vector3(gx * 5.0, 0, gz * 5.0)
			q.y = t.height_at(q.x, q.z)
			if prospect.cannot_dig(q) != "" or not prospect.near_water(q, 4.0):
				continue
			var g: float = prospect.geology(q.x, q.z)[0]
			if g > best_g:
				best_g = g
				best = q
	print("digtest: richest wet spot found %s grade %.1f g/m3" % [best, best_g])
	_get_out()
	walker.place(best, 0.0)
	await get_tree().process_frame
	var front: Vector3 = walker.global_transform * Vector3(0, 0, -0.9)
	# No shovel, no digging; fetch it from the hangar first.
	inv.remove("shovel", 9)
	print("digtest: without shovel -> ", prospect.target(walker.global_position, front))
	var sv: Dictionary = {}
	for e in inv.world_items:
		if e["id"] == "shovel":
			sv = e
	if sv.is_empty():
		inv.place_in_world("shovel", 1, Vector3(-40.0, 0, -80.0), 0.0)
		sv = inv.world_items.back()
	var sp: Vector3 = (sv["xf"] as Transform3D).origin
	print("digtest: near the shovel finds: ", inv.world_item_near(Vector3(sp.x, sp.y - 1.0, sp.z)).get("id", "nothing"))
	print("digtest: ", inv.pick_up(sv))
	for i in range(3):
		await get_tree().process_frame
	print("digtest: in hand '%s', hand mesh on the bone: %s, weight %.1f kg" % [inv.in_hand(), _hand_node != null and _hand_node.get_parent() is BoneAttachment3D, inv.weight()])
	var n_dig := 0
	var rocks_moved := 0
	for i in range(80):
		var tg: Array = prospect.target(walker.global_position, front)
		if tg.is_empty() or String(tg[0]) == "":
			print("digtest: nothing to do here ", tg)
			break
		if tg[0] == "dig":
			n_dig += 1
			var dm: String = prospect.act("dig", walker.global_position, front)
			if dm.contains("rock"):
				# lift it out and set it aside, as he would (E picks it up)
				for rp in cargo.own_rocks["pieces"]:
					if rp["at"] == "dropped" and (rp["pos"] as Vector3).distance_to(walker.global_position) < 3.0:
						rp["pos"] = walker.global_position + Vector3(2.5, 0, 2.5)
						rocks_moved += 1
			if n_dig % 10 == 0:
				print("digtest: %d shovelfuls, hole %.2f m deep" % [n_dig, world.terrain.height_at_base(front.x, front.z) - world.terrain.height_at(front.x, front.z)])
			continue
		if n_dig > 0:
			print("digtest: dug %d shovelfuls down to the gravel" % n_dig)
			n_dig = 0
		print("digtest: %s -> %s" % [tg[0], prospect.act(String(tg[0]), walker.global_position, front)])
		if tg[0] == "pan" and i > 30:
			break
	print("digtest: rocks turned up and set aside: %d" % rocks_moved)
	prospect.owned_sluices = 1
	print("digtest: sluice: ", prospect.place_sluice(walker.global_position, 0.0))
	for i in range(6):
		var tg2: Array = prospect.target(walker.global_position, front)
		print("digtest: %s -> %s" % [tg2[0], prospect.act(String(tg2[0]), walker.global_position, front)])
	print("digtest: ground at the hole %.2f (was %.2f), tiles %d" % [t.height_at(front.x, front.z), t.height_at_base(front.x, front.z), prospect.tiles.size()])
	# Excavator and wash plant on dry ground nearby.
	var dry: Vector3 = best + Vector3(8, 0, 8)
	print("digtest: ", prospect.place_washplant(dry, 0.0))
	# park it beside the hopper end of the plant, in reach of the hopper (3.9 m up)
	print("digtest: ", prospect.buy_excavator(dry + Vector3(0, 0, 9.0), 0.0))
	var ex: Node3D = prospect.excavators.back()
	var hop: Vector3 = prospect.plants.back() * prospect.EquipModels.TROMMEL_HOPPER
	var pi_last: int = prospect.plants.size() - 1
	print("digtest: ground here [grade g/m3, pay top, bedrock]: %s, dug %.2f m" % [t.geology(best.x, best.z), t.orig_depth_at(best.x, best.z)])
	print("digtest: ", prospect.plant_toggle(pi_last))
	for i in range(10):
		ex.aim = Vector3(best.x, t.height_at(best.x, best.z), best.z)
		ex.dig_or_dump()
		while ex.busy():
			var m: String = ex.work(1.0 / 30.0)
			if m != "":
				print("digtest: ", m)
			await get_tree().process_frame
		if i < 3:
			print("digtest: bucket load ", ex.bucket_load)
		ex.aim = hop
		ex.dig_or_dump()
		while ex.busy():
			var m2: String = ex.work(1.0 / 30.0)
			if m2 != "":
				print("digtest: ", m2)
			await get_tree().process_frame
	# Lever mode: bite in, drag the bucket in, swing to the hopper, open it.
	ex.levers = true
	var g0: float = prospect.gold_g
	var dt := 1.0 / 30.0
	for cyc in range(3):
		for k in range(150):          # reach out: boom up a touch, stick right out, bucket open
			ex.levers_step(dt, 0.0, 1.0, 0.3, -0.5)
		for k in range(240):          # boom down until the teeth are in
			var tp: Vector3 = ex.teeth()
			if t.height_at(tp.x, tp.z) - tp.y > 0.25:
				break
			ex.levers_step(dt, 0.0, 0.6, -1.0, -0.3)
		var bit: Vector3 = ex.teeth()
		for k in range(150):          # drag in and curl
			ex.levers_step(dt, 0.0, -1.0, -0.15, 0.5)
		print("digtest: levers cycle %d: bucket %.0f%% full, teeth went %.2f m deep" % [cyc, ex.fill() * 100.0, t.height_at_base(bit.x, bit.z) - bit.y])
		for k in range(300):          # boom up, stick out, keep it curled, till it's clear
			ex.levers_step(dt, 0.0, 0.5, 1.0, 1.0)
			var tq: Vector3 = ex.teeth()
			if tq.y > t.height_at(tq.x, tq.z) + 0.8:
				break
		for k in range(55):           # swing a quarter turn to dump beside the hole
			ex.levers_step(dt, 1.0, 0.0, 0.0, 1.0)
		var tq2: Vector3 = ex.teeth()
		var m3 := ""
		for k in range(60):
			var m4: String = ex.levers_step(dt, 0.0, 0.0, 0.0, -1.0)
			if m4 != "":
				m3 = m4
		print("digtest: levers dump -> '%s', bucket now %.0f%% (bucket angle %.2f)" % [m3, ex.fill() * 100.0, ex.bucket_a])
		for k in range(55):           # and back over the hole
			ex.levers_step(dt, -1.0, 0.0, 0.0, 0.0)
	print("digtest: levers cut/dump done, gold %.2f -> %.2f" % [g0, prospect.gold_g])
	Engine.time_scale = 8.0
	var tw := Time.get_ticks_msec()
	while float(prospect.plant_hopper[pi_last][0]) > 0.0 and Time.get_ticks_msec() - tw < 30000:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	print("digtest: hopper washed down: %.2f m3 left, %.1f L gas left, gold %.2f g" % [float(prospect.plant_hopper[pi_last][0]), float(prospect.plant_fuel[pi_last]), prospect.gold_g])
	print("digtest: gold carried %.1f g, sell: %s" % [prospect.gold_g, prospect.sell_gold()])
	print("digtest: hillside grade check: %s" % [prospect.geology(c0.x + 900.0, c0.z + 900.0)])
	# No limit: open 80 more tiles in a long trench.
	var t0 := Time.get_ticks_msec()
	for i in range(80):
		prospect.dig(best + Vector3(30.0 + 24.0 * float(i % 10), 0, 30.0 + 24.0 * float(i / 10)), 0.5, 0.2)
	var q: Vector3 = best + Vector3(30.0, 0, 30.0)
	print("digtest: tiles now %d (%d ms), ground there %.2f vs base %.2f" % [prospect.tiles.size(), Time.get_ticks_msec() - t0, world.terrain.height_at(q.x, q.z), world.terrain.height_at_base(q.x, q.z)])


## DC-3 gear: can't raise on the ground; up in the air; faster with it up; belly landing.
## Taxi into the hangar wall slowly (dent, no pass-through), roll in through
## the door cleanly, then fly into the wall (wreck).
## Walk up to a plane for sale on the Port Ashby apron, get pushed out of
## its hull (collision), buy it, and check the fleet took it over.
func _sale_test() -> void:
	Engine.time_scale = 4.0
	jobs.money = 10000000
	jobs.carried.clear()
	_on_start_requested(0, false)
	await get_tree().create_timer(3.0).timeout
	print("saletest: sale planes on the island: ", world.sale_planes.size())
	var wolv := {}
	for e in world.sale_planes:
		if e["type"] == "wolverine" and (e["node"] as Node3D).global_position.distance_to(plane.pos) < 400.0:
			wolv = e
			break
	if wolv.is_empty():
		print("saletest: no wolverine for sale near strip 0  <-- check")
		return
	var sn: Node3D = wolv["node"]
	_get_out()
	for i in range(4):
		await get_tree().process_frame
	# Stand inside the hull: collision must push the walker out.
	walker.place(sn.global_transform * Vector3(0.0, 0.2, 0.0), 0.0)
	await get_tree().process_frame
	var pushed: Vector3 = walker._collide(walker.global_position)
	var lp: Vector3 = sn.global_transform.affine_inverse() * pushed
	print("saletest: inside hull pushed to |x|=%.2f (hull half %.2f): %s" % [absf(lp.x), walker._fuselage_half_width(lp.z), "OK" if absf(lp.x) >= walker._fuselage_half_width(lp.z) else "still inside  <-- check"])
	# Beside it: the buy prompt flow.
	walker.place(sn.global_transform * Vector3(-3.0, 0, 0.3), 0.0)
	await get_tree().process_frame
	var near: Dictionary = world.sale_near(walker.global_position)
	print("saletest: sale_near found: ", not near.is_empty(), "  price $", _sale_price("wolverine"))
	var fleet_before: int = fleet.planes.size()
	var money0: int = jobs.money
	var old_reg: String = plane.reg
	var err: String = fleet.buy_parked(sn, _sale_price("wolverine"))
	if err == "":
		world.remove_sale(near if not near.is_empty() else wolv)
	print("saletest: buy -> '%s', fleet %d -> %d, paid $%d" % [err, fleet_before, fleet.planes.size(), money0 - jobs.money])
	print("saletest: now flying %s (was %s), old one %s" % [plane.reg, old_reg, fleet.planes[0]["where"] if fleet.planes.size() > 0 else "?"])
	var dist: float = (plane.pos - sn.global_position).length()
	print("saletest: active plane sits at the sale spot: %.1f m away %s" % [dist, "OK" if dist < 8.0 else "<-- check"])
	print("saletest: sale list now ", world.sale_planes.size(), "  DONE")


## The dozer: spawn it on sloping ground, push forward with the blade down,
## and check the strip it crossed has really been graded toward one level.
func _dozer_test() -> void:
	Engine.time_scale = 1.0
	jobs.money = 10000000
	# Find genuinely sloping ground near strip 0 (the strip's apron is flat).
	var base0: Vector3 = Vector3(70.0, 0.0, -35.0)     # between the pad and the rock knoll
	var p0 := base0
	var found := false
	for ring in range(2, 26):
		for ang in range(10):
			var a := TAU * float(ang) / 10.0
			var q0 := base0 + Vector3(cos(a), 0, sin(a)) * (8.0 * float(ring))
			if prospect.cannot_dig(q0) != "" or absf(q0.x) > 140.0 or absf(q0.z) > 140.0:
				continue
			var h0: float = world.terrain.height_at(q0.x, q0.z)
			var h1: float = world.terrain.height_at(q0.x + 8.0, q0.z)
			if absf(h1 - h0) > 0.9 and absf(h1 - h0) < 4.0:
				p0 = q0
				found = true
				break
		if found:
			break
	p0.y = world.terrain.height_at(p0.x, p0.z)
	print("doztest: slope spot %s (found %s)" % [p0, found])
	print("doztest: buy -> ", prospect.buy_dozer(p0, PI * 0.5))   # facing downhill, off the knoll
	var dz: Node3D = prospect.dozers.back()
	var fwd: Vector3 = -dz.global_transform.basis.z
	# Ground profile along the next 10 m before.
	var before: Array = []
	for k in range(6):
		var q: Vector3 = p0 + fwd * (2.0 + 1.6 * float(k))
		before.append(world.terrain.height_at(q.x, q.z))
	print("doztest: blade -> ", dz.blade_toggle())
	for f in range(400):
		var msg: String = dz.drive(1.0 / 30.0, Vector2(0, 1))
		if msg != "" and f % 50 == 0:
			print("doztest: ", msg)
		if f % 100 == 0:
			await get_tree().process_frame
	await get_tree().process_frame
	var after: Array = []
	var spread0 := 0.0
	var spread1 := 0.0
	for k in range(6):
		var q2: Vector3 = p0 + fwd * (2.0 + 1.6 * float(k))
		after.append(world.terrain.height_at(q2.x, q2.z))
	var pb := ""
	var pa := ""
	for k in range(6):
		pb += "%.2f " % float(before[k])
		pa += "%.2f " % float(after[k])
	print("doztest: profile before: ", pb)
	print("doztest: profile after:  ", pa)
	# Judge the finished part of the cut: the bench behind the machine
	# (the uphill end is always still climbing out when it stops).
	spread0 = absf(float(before[3]) - float(before[0])) / 4.8
	spread1 = absf(float(after[3]) - float(after[0])) / 4.8
	print("doztest: bench slope before %.1f%%, after %.1f%%, load %.2f m3" % [spread0 * 100.0, spread1 * 100.0, dz.load_m3])
	print("doztest: moved %.1f m, %s" % [(dz.global_position - p0).length(), "GRADED OK" if spread1 < spread0 * 0.6 else "no flatter  <-- check"])
	# Pushing a pile (Dave: "the dirt doesn't move enough"): a 15 m3 heap
	# 6 m ahead on the flat, blade down, push 25 s.
	var t: RefCounted = world.terrain
	var pp := Vector3(30.0, 0, -100.0)
	for ring in range(1, 40):
		var q3 := Vector3(60.0, 0, 30.0) + Vector3(cos(float(ring) * 2.4), 0, sin(float(ring) * 2.4)) * float(ring) * 4.0
		var ok := true
		for k in range(0, 40, 4):
			var q4 := q3 + Vector3(-float(k), 0, 0)
			if prospect.cannot_dig(q4) != "" or t.normal_at(q4.x, q4.z).y < 0.97:
				ok = false
				break
		if ok:
			pp = q3
			break
	pp.y = t.height_at(pp.x, pp.z)
	print("doztest: push spot %s" % pp)
	dz.blade_toggle() if dz.blade_down else null
	dz.park(Transform3D(Basis(Vector3.UP, PI * 0.5), pp))
	var f2: Vector3 = -dz.global_transform.basis.z
	var heap: Vector3 = pp + f2 * 7.0
	t.deposit(heap, 15.0)
	var vol_at := func(c: Vector3, r: float) -> float:
		var v := 0.0
		var x := -r
		while x <= r:
			var z := -r
			while z <= r:
				if x * x + z * z <= r * r:
					v += maxf(t.height_at(c.x + x, c.z + z) - t.natural_at(c.x + x, c.z + z), 0.0) * 0.25
				z += 0.5
			x += 0.5
		return v
	var v0: float = vol_at.call(heap, 4.0)
	dz.blade_toggle()
	var slow := 99.0
	for f in range(25 * 30):
		dz.drive(1.0 / 30.0, Vector2(0, 1))
		slow = minf(slow, absf(float(dz.body.vel.dot(-dz.global_transform.basis.z))) if f > 60 else 99.0)
		if f % 45 == 0 and f < 400:
			var fr: Vector3 = dz.global_position - dz.global_transform.basis.z * 2.4
			print("doztest:   t %.1f pos (%.1f, %.1f) blade_down %s goal %.2f load %.2f ground ahead %.2f natural %.2f" % [float(f) / 30.0, dz.global_position.x, dz.global_position.z, dz.blade_down, dz._blade_goal, dz.load_m3, t.height_at(fr.x, fr.z), t.natural_at(fr.x, fr.z)])
		if f % 100 == 0:
			await get_tree().process_frame
	var v1: float = vol_at.call(heap, 4.0)
	var endf: Vector3 = dz.global_position - dz.global_transform.basis.z * 4.0
	print("doztest:   dirt now ahead of the blade (r 5): %.1f m3; along the path every 8 m: %s" % [vol_at.call(endf, 5.0), str(range(0, 64, 8).map(func(k): return snappedf(vol_at.call(pp + f2 * float(k), 3.0), 0.1)))])
	var moved_m: float = (dz.global_position - pp).length()
	print("doztest: pushed a %.1f m3 heap: %.1f m3 left where it was, dozer went %.0f m (slowest %.1f m/s), blade carrying %.1f m3 %s" % [
		v0, v1, moved_m, slow, dz.load_m3, "" if vol_at.call(endf, 5.0) + dz.load_m3 > 4.0 and moved_m > 12.0 else "<-- PROBLEM"])


## Carry a multi-piece job aboard by hand, printing the free spots each step.
func _cargo_hand_test() -> void:
	Engine.time_scale = 4.0
	jobs.money = 10000000
	jobs.carried.clear()
	_on_start_requested(0, false)
	await get_tree().create_timer(3.0).timeout
	var pj := {}
	for j in jobs.board(0):
		if int(j["pax"]) == 0 and jobs.cannot_take(j) == "" and int(j.get("n", 1)) >= 2:
			pj = j
			break
	if pj.is_empty():
		print("cargotest: no suitable job")
		return
	var took: bool = jobs.take(pj, true)
	var job: Dictionary = jobs.carried.back()
	print("cargotest: took %s '%s' pieces %d kind %s" % [took, pj["title"], (job["pieces"] as Array).size(), job["kind"]])
	_get_out()
	for i in range(4):
		await get_tree().process_frame
	print("cargotest: capacity for %s: %d" % [job["kind"], cargo.piece_capacity(String(job["kind"]))])
	var step := 0
	for pc in job["pieces"]:
		step += 1
		walker.place((pc["pos"] as Vector3) + Vector3(0.7, 0, 0), 0.0)
		await get_tree().process_frame
		cargo._find_target()
		cargo.interact()
		var stowed := false
		for dpos in [Vector3(-1.3, 0, -0.1), Vector3(-1.0, 0, 1.7)]:
			walker.place(plane.global_transform * (dpos as Vector3), 0.0)
			await get_tree().process_frame
			cargo._find_target()
			if not cargo._target.is_empty() and cargo._target[0] == "open":
				cargo.interact()
			cargo._find_target()
			if not cargo._target.is_empty() and cargo._target[0] == "stow":
				cargo.interact()
				stowed = true
				break
		var spots_str := ""
		for pc2 in job["pieces"]:
			spots_str += "%s/%s " % [pc2["at"], pc2.get("spot", "-")]
		var sz: Vector3 = (cargo.LOOKS.get(String(job["kind"]), cargo.LOOKS["freight"]) as Array)[0]
		print("cargotest: step %d stowed=%s free c/b=%d/%d prompt='%s' at: %s" % [step, stowed,
			cargo._free_spots("cabin", sz.y).size(), cargo._free_spots("bay", sz.y).size(), cargo.prompt, spots_str])
	print("cargotest: loaded %d of %d" % [jobs.count_at(job, "cabin") + jobs.count_at(job, "bay"), (job["pieces"] as Array).size()])


## Working on the DC-3's engines: panels open at a nacelle, read a plug pair,
## compression, oil, and the two engines stay separate.
func _dc3_eng_test() -> void:
	plane.apply_type("dc3")
	_apply_plane_type()
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	_get_out()
	var xf: Transform3D = plane.global_transform
	walker.place(xf * Vector3(-3.35 + 1.4, 0, -3.0), 0.0)
	await get_tree().process_frame
	print("dc3eng: near nacelle %s bay %d" % [service.near_nose(), service.bay])
	print("dc3eng: ", service.toggle_cowl())
	plane.engine.comp[4] = 48.0
	plane.engine2.comp[4] = 77.0
	plane.engine.plug_foul[8] = 0.9
	for a in [["e0_cyl_5", "comp_one"], ["e0_cyl_5", "read_plug"], ["e0_dipstick", "check_oil"], ["e0_mag_l", "check_mag"]]:
		var why := ""
		for ac in service.actions(a[0]):
			if ac[1] == a[1]:
				why = ac[2]
		if why == "":
			service.do(a[0], a[1])
		var waited := 0
		while not service.job.is_empty() and waited < 1800:
			waited += 1
			await get_tree().process_frame
		print("dc3eng: %s/%s -> %s" % [a[0], a[1], service.result if why == "" else "(blocked: " + why + ")"])
	# The other side is its own engine.
	walker.place(xf * Vector3(3.35 + 1.4, 0, -3.0), 0.0)
	await get_tree().process_frame
	print("dc3eng: other nacelle %s bay %d" % [service.near_nose(), service.bay])
	print("dc3eng: ", service.toggle_cowl())
	service.do("e1_cyl_5", "comp_one")
	var w2 := 0
	while not service.job.is_empty() and w2 < 1800:
		w2 += 1
		await get_tree().process_frame
	print("dc3eng: e1_cyl_5/comp_one -> %s (engine 1 was set weak, engine 2 strong)" % service.result)


func _bld_test() -> void:
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	var hb: Dictionary = world.terrain.hollows[0]
	var xf: Transform3D = hb["xf"]
	var sz: Vector3 = hb["size"]
	# 1. Rolling at the side wall at walking pace.
	var start: Vector3 = xf * Vector3(sz.x * 0.5 + 9.0, 0.0, 2.0)
	start.y = world.terrain.height_at(start.x, start.z) + 1.4
	var aim: Vector3 = xf * Vector3(sz.x * 0.5, 0.0, 2.0)
	var head := rad_to_deg(atan2(-(aim.x - start.x), -(aim.z - start.z)))
	plane.place_parked(start, Quaternion(Basis(Vector3.UP, deg_to_rad(head)) * Basis(Vector3.RIGHT, deg_to_rad(plane.sit_pitch))))
	for e in plane.engines():
		e.set_running(15.0)
	plane.direct_controls = true
	for i in range(60 * 20):
		plane.throttle = 0.7 if plane.ground_speed < 2.5 else 0.25
		plane.brake = 0.0
		await get_tree().physics_frame
	var lp: Vector3 = (hb["inv"] as Transform3D) * plane.global_position
	print("bldtest: taxied at the wall: local x %.2f (wall at %.1f), speed %.1f, crashed %s, damage %s" % [lp.x, sz.x * 0.5, plane.ground_speed, plane.is_crashed, plane.is_damaged()])
	# 2. Flying into the back wall fast.
	var p2: Vector3 = xf * Vector3(0.0, 0.0, -sz.z * 0.5 - 70.0)
	p2.y = xf.origin.y + sz.y * 0.5
	var aim2: Vector3 = xf * Vector3(0.0, 0.0, -sz.z * 0.5)
	var dir2: Vector3 = (aim2 - p2).normalized()
	var head2 := -rad_to_deg(atan2(-dir2.x, -dir2.z))
	plane.repair_all()
	plane.place_in_air(p2, head2, 50.0)
	plane.direct_controls = true
	for i in range(60 * 6):
		plane.throttle = 0.4
		plane.in_pitch = clampf(-0.4 * plane.vel.y - 2.0 * plane.omega.x, -1.0, 1.0)
		await get_tree().physics_frame
		if plane.is_crashed:
			break
	var lp2: Vector3 = (hb["inv"] as Transform3D) * plane.global_position
	print("bldtest: flown at the wall: crashed %s (%s), local z %.1f (wall at %.1f)" % [plane.is_crashed, plane.crash_reason, lp2.z, -sz.z * 0.5])
	# 3. Dropped onto the hangar roof: it should come to rest on it, not fall through.
	plane.repair_all()
	var roof: Vector3 = xf * Vector3(0.0, sz.y + 2.5, 2.0)
	plane.place_parked(roof, Quaternion(xf.basis.get_rotation_quaternion()))
	plane.frozen = false
	for i in range(60 * 6):
		plane.brake = 1.0
		await get_tree().physics_frame
	var lr: Vector3 = (hb["inv"] as Transform3D) * plane.global_position
	print("bldtest: dropped on the roof: local y %.2f (roof at %.1f, floor at 0), crashed %s" % [lr.y, sz.y, plane.is_crashed])
	# 4. Flown into a house.
	var sb: Dictionary = world.terrain.solids[0]
	var hxf: Transform3D = sb["xf"]
	var hsz: Vector3 = sb["size"]
	plane.repair_all()
	var p3: Vector3 = hxf * Vector3(0.0, hsz.y * 0.35, -hsz.z * 0.5 - 70.0)
	var dir3: Vector3 = ((hxf * Vector3(0.0, hsz.y * 0.35, 0.0)) - p3).normalized()
	plane.place_in_air(p3, -rad_to_deg(atan2(-dir3.x, -dir3.z)), 50.0)
	plane.direct_controls = true
	for i in range(60 * 6):
		plane.throttle = 0.4
		plane.in_pitch = clampf(-0.4 * plane.vel.y - 2.0 * plane.omega.x, -1.0, 1.0)
		await get_tree().physics_frame
		if plane.is_crashed:
			break
	var lh: Vector3 = (sb["inv"] as Transform3D) * plane.global_position
	print("bldtest: flown at a house: crashed %s (%s), local (%.1f, %.1f, %.1f) box (%.1f, %.1f, %.1f)" % [plane.is_crashed, plane.crash_reason, lh.x, lh.y, lh.z, hsz.x * 0.5, hsz.y, hsz.z * 0.5])


## The DC-3 with its engines moved out (3.35 m): a take-off roll on strip 0
## holding the centreline with rudder, then a taxi turn on one brake.
func _dc3_roll_test() -> void:
	plane.apply_type("dc3")
	_apply_plane_type()
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	plane.frozen = false
	plane.direct_controls = true
	for e in plane.engines():
		e.set_running(15.0)
	var p0: Vector3 = plane.global_position
	var h0: float = _plane_yaw()
	var worst_dev := 0.0
	var lift_at := -1.0
	var n_dmg := 0
	for i in range(60 * 70):
		plane.throttle = 1.0
		plane.brake = 0.0
		var dyaw := wrapf(_plane_yaw() - h0, -PI, PI)
		worst_dev = maxf(worst_dev, absf(rad_to_deg(dyaw)))
		plane.in_yaw = clampf(dyaw * 3.0 + plane.omega.y * 1.0, -1.0, 1.0) * (-1.0 if _test.has("flipyaw") else 1.0)
		var kt: float = plane.ias_kt
		# tail down to 40 kt, then ease it up to a level attitude, rotate at 80
		var want_p := deg_to_rad(11.0) if kt < 40.0 else (deg_to_rad(lerpf(11.0, 3.0, clampf((kt - 40.0) / 20.0, 0.0, 1.0))) if kt < 80.0 else deg_to_rad(8.0))
		plane.in_pitch = clampf((want_p - plane.pitch_rad()) * 2.5 - plane.omega.x * 0.8, -0.6, 0.6)
		plane.in_roll = clampf(-2.0 * plane.roll_rad(), -1.0, 1.0)
		if lift_at < 0.0 and not plane.on_ground:
			lift_at = Vector2(plane.global_position.x - p0.x, plane.global_position.z - p0.z).length()
			print("dc3roll: off the ground at %.0f m, %.0f kt, worst heading swing %.1f deg" % [lift_at, kt, worst_dev])
		if plane.is_crashed or (lift_at > 0.0 and plane.global_position.y - p0.y > 30.0):
			break
		if i % 300 == 0:
			print("dc3roll: t %d s, %.0f kt, heading off %.1f deg, roll %.1f deg, on ground %s" % [i / 60, kt, rad_to_deg(dyaw), rad_to_deg(plane.roll_rad()), plane.on_ground])
		var dr: Array = plane.damage_report()
		if dr.size() > n_dmg:
			n_dmg = dr.size()
			print("dc3roll: DAMAGE at t %.1f s, %.0f kt, pitch %.1f deg, roll %.1f, vs %.1f m/s, agl %.2f: %s" % [i / 60.0, kt, rad_to_deg(plane.pitch_rad()), rad_to_deg(plane.roll_rad()), plane.vel.y, plane.agl, str(dr)])
		await get_tree().physics_frame
	print("dc3roll: crashed %s %s, damage: %s" % [plane.is_crashed, plane.crash_reason, plane.damage_report()])
	# taxi turn: back on the strip, slow, full left rudder and left brake
	plane.place_on_strip(0)
	plane.frozen = false
	plane.park_brake = false
	plane.tail_lock = false            # the lock was in for the take-off roll
	for e in plane.engines():
		e.set_running(15.0)
	await get_tree().physics_frame
	h0 = _plane_yaw()
	var max_roll := 0.0
	for i in range(60 * 15):
		plane.throttle = 0.45
		plane.park_brake = false
		plane.brake = 0.0
		plane.in_yaw = -1.0
		plane.brake_left = 0.8
		plane.brake_right = 0.0
		max_roll = maxf(max_roll, absf(rad_to_deg(plane.roll_rad())))
		await get_tree().physics_frame
	print("dc3roll: taxi turn 15 s: turned %.0f deg, worst roll %.1f deg, %.0f kt, crashed %s" % [rad_to_deg(wrapf(_plane_yaw() - h0, -PI, PI)), max_roll, plane.ias_kt, plane.is_crashed])


func _gear_test() -> void:
	plane.apply_type("dc3")
	_apply_plane_type()
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	print("geartest: raise on the ground -> ", plane.set_gear(false), " gear_down ", plane.gear_down)
	for up in [false, true]:
		var p0 := Vector3(plane.global_position.x, 2400.0, plane.global_position.z)
		plane.place_in_air(p0, 225.0, 70.0)
		plane.set_load(plane.fuel_capacity * 0.5, 0.0, 0.0)
		plane.direct_controls = true
		for e in plane.engines():
			e.set_running(15.0)
			if not e.has_meta("gt_hook"):
				e.set_meta("gt_hook", true)
				e.event.connect(func(t): print("geartest(engine): ", t))
		plane.gear_down = not up
		plane.gear_pos = 0.0 if up else 1.0
		for i in range(60 * 60):
			plane.throttle = 0.8
			var vs: float = plane.vel.y
			plane.in_pitch = clampf(-0.08 * vs - 2.0 * plane.omega.x + 0.3 * (deg_to_rad(2.0) - plane.pitch_rad()), -1.0, 1.0)
			plane.in_roll = clampf(-2.0 * plane.roll_rad() + 0.5 * plane.omega.z, -1.0, 1.0)
			if i % 600 == 0:
				print("geartest(trace %s t=%d): ias %.0f vs %.0f thrust %.0f+%.0f run %s/%s pw %.0f/%.0f kW rpm %.0f alpha %.1f el %.2f pitch %.1f" % ["UP" if up else "DN", i / 60, plane.ias_kt, plane.vertical_speed_fpm(), plane.engine_thrust[0], plane.engine_thrust[1], plane.engine.running, plane.engine2.running, plane.engine.power / 1000.0, plane.engine2.power / 1000.0, plane.engine.rpm, rad_to_deg(plane.wing_alpha), plane.elevator, rad_to_deg(plane.pitch_rad())] + " g %.1f fuelL %.0f/%.0f cht %.0f" % [plane.g_load, plane.engine.tank_left, plane.engine.tank_right, plane.engine.cht])
			await get_tree().physics_frame
		print("geartest: gear %s: %.0f kt after a minute at 80%% power, vs %.0f fpm, crashed %s %s" % ["UP" if up else "DOWN", plane.ias_kt, plane.vertical_speed_fpm(), plane.is_crashed, plane.crash_reason])
	# In the air: lower it and time it.
	plane.set_gear(true)
	var t := 0.0
	while plane.gear_pos < 1.0 and t < 30.0:
		t += 1.0 / 60.0
		await get_tree().physics_frame
	print("geartest: gear down in %.1f s" % t)
	# Belly landing: on the runway at speed with the wheels up.
	_on_start_requested(0, false)
	await get_tree().create_timer(0.5).timeout
	plane.gear_down = false
	plane.gear_pos = 0.0
	for e in plane.engines():
		e.set_running(15.0)
	for i in range(60 * 6):
		plane.throttle = 0.6
		plane.brake = 0.0
		await get_tree().physics_frame
	print("geartest: wheels-up on the ground: crashed %s prop %.2f engines running %s ground speed %.1f" % [plane.is_crashed, plane.parts["prop"], plane.engines()[0].running, plane.ground_speed])


## What costs the most to draw: triangles, draw calls, shadow casters, lights,
## grouped by what they belong to. Trees both ways (3D and flat cards).
func _perf_test() -> void:
	if _test.has("preset"):
		Game.apply_preset(int(_test["preset"]))
		world.vegetation.Meshes.lite = Game.gfx_plants < 3
		world.apply_quality()
	_on_start_requested(int(_test.get("strip", "4")), false)
	for mode in ([false] if _test.has("preset") else [true, false]):
		Game.trees_3d = mode
		world.vegetation.apply_quality(Game.gfx_plants)
		var t := 0.0
		while t < 60.0:
			await get_tree().create_timer(0.5).timeout
			t += 0.5
			if world.vegetation.is_idle() and t > 3.0:
				break
		print("perf: ===== trees %s (waited %.0f s) =====" % ["3D" if mode else "FLAT", t])
		var groups := {}
		_perf_walk(get_tree().root, groups, "")
		var rows: Array = []
		for k in groups.keys():
			rows.append([k, groups[k]])
		rows.sort_custom(func(a, b): return int(a[1][0]) > int(b[1][0]))
		print("perf: %-34s %12s %8s %12s %6s" % ["what", "triangles", "draws", "shadow tris", "lights"])
		var tot := [0, 0, 0, 0]
		for r in rows:
			var v: Array = r[1]
			for i in range(4):
				tot[i] += int(v[i])
			if int(v[0]) > 2000 or int(v[3]) > 0:
				print("perf: %-34s %12d %8d %12d %6d" % [String(r[0]).left(34), v[0], v[1], v[2], v[3]])
		print("perf: %-34s %12d %8d %12d %6d" % ["TOTAL", tot[0], tot[1], tot[2], tot[3]])
		var st: Dictionary = world.vegetation.stats()
		for ln in st.keys():
			print("perf:   plants %-7s instances %7d  tris %10d  shadow tris %10d" % [ln, st[ln][0], st[ln][1], st[ln][2]])
	# Script time per frame.
	var tp := 0.0
	var tph := 0.0
	for i in range(120):
		await get_tree().process_frame
		tp += Performance.get_monitor(Performance.TIME_PROCESS)
		tph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	print("perf: script time per frame %.2f ms, physics %.2f ms" % [tp / 120.0 * 1000.0, tph / 120.0 * 1000.0])
	# Time each script's own per-frame work directly (call it and clock it).
	var found: Array = []
	_perf_scripts(get_tree().root, found)
	var res: Array = []
	for n in found:
		for fn in ["_process", "_physics_process"]:
			if not (n as Node).has_method(fn) or (n as Node).get_script() == null:
				continue
			var dt := 1.0 / 60.0
			(n as Node).call(fn, dt)
			var t0 := Time.get_ticks_usec()
			for i in range(20):
				(n as Node).call(fn, dt)
			var us := float(Time.get_ticks_usec() - t0) / 20.0
			res.append([us, "%s.%s (%s)" % [(n as Node).name, fn, String((n as Node).get_script().resource_path).get_file()]])
	res.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	var total := 0.0
	for r in res:
		total += float(r[0])
	var t0m := Time.get_ticks_usec()
	for i in range(20):
		_process(1.0 / 60.0)
	print("perf: main.gd _process %.2f ms" % (float(Time.get_ticks_usec() - t0m) / 20000.0))
	var t0p := Time.get_ticks_usec()
	for i in range(20):
		_physics_process(1.0 / 60.0)
	print("perf: main.gd _physics_process %.2f ms" % (float(Time.get_ticks_usec() - t0p) / 20000.0))
	var vg = world.vegetation
	var b0: int = vg.perf_builds
	var g0: int = vg.perf_gens
	var d0: int = vg.perf_drops
	var tv0 := Time.get_ticks_usec()
	var fr := 0
	while Time.get_ticks_usec() - tv0 < 3000000:
		await get_tree().process_frame
		fr += 1
	print("perf: in 3 s (%d frames): chunks built %d, started %d, dropped %d, backlog %d, idle %s" % [fr, vg.perf_builds - b0, vg.perf_gens - g0, vg.perf_drops - d0, vg._backlog, vg.is_idle()])
	# One full streaming pass (normally every 0.3 s), timed.
	var tpass := Time.get_ticks_usec()
	for i in range(10):
		vg._wait = 0.0
		vg._process(0.016)
	print("perf: one plant streaming pass %.2f ms" % (float(Time.get_ticks_usec() - tpass) / 10000.0))
	var with_hud := await _perf_frame_ms()
	hud.visible = false
	var no_hud := await _perf_frame_ms()
	hud.visible = true
	world.vegetation.process_mode = Node.PROCESS_MODE_DISABLED
	var no_veg := await _perf_frame_ms()
	world.vegetation.process_mode = Node.PROCESS_MODE_INHERIT
	print("perf: frame process %.2f ms; without the HUD %.2f; with plant streaming paused %.2f" % [with_hud.x, no_hud.x, no_veg.x])
	print("perf: per-script cost, total %.2f ms a frame:" % (total / 1000.0))
	for i in range(mini(25, res.size())):
		print("perf:   %7.2f ms  %s" % [float(res[i][0]) / 1000.0, res[i][1]])


func _perf_scripts(n: Node, out: Array) -> void:
	if n.get_script() != null and n != self and not (n is CanvasLayer and n.name == "Console"):
		out.append(n)
	for c in n.get_children():
		_perf_scripts(c, out)


func _perf_frame_ms() -> Vector2:
	for i in range(10):
		await get_tree().process_frame
	var a := 0.0
	var b := 0.0
	for i in range(60):
		await get_tree().process_frame
		a += Performance.get_monitor(Performance.TIME_PROCESS)
		b += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return Vector2(a, b) / 60.0 * 1000.0


func _perf_group(n: Node) -> String:
	var path := String(n.get_path())
	var bits := path.split("/", false)
	# root/Main/<child>/<grandchild>
	if bits.size() >= 4:
		var a: String = bits[2]
		if a == "World" or a == "Plane" or a == "Prospecting":
			return a + "/" + String(bits[3]).rstrip("0123456789").left(20)
		return a
	return bits[bits.size() - 1] if bits.size() > 0 else "?"


func _perf_walk(n: Node, groups: Dictionary, _p: String) -> void:
	if n is GeometryInstance3D and (n as Node3D).is_visible_in_tree():
		var g := _perf_group(n)
		if not groups.has(g):
			groups[g] = [0, 0, 0, 0]
		var tris := 0
		var draws := 0
		if n is MultiMeshInstance3D:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null:
				tris = mm.mesh.get_faces().size() / 3 * mm.instance_count
				draws = mm.mesh.get_surface_count()
		elif n is MeshInstance3D:
			var m: Mesh = (n as MeshInstance3D).mesh
			if m != null:
				tris = m.get_faces().size() / 3
				draws = m.get_surface_count()
		elif n is CPUParticles3D or n is GPUParticles3D:
			draws = 1
			tris = 2 * int(n.get("amount"))
		groups[g][0] += tris
		groups[g][1] += draws
		if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			groups[g][2] += tris
	if n is Light3D and (n as Node3D).is_visible_in_tree() and (n as Light3D).light_energy > 0.0:
		var g2 := _perf_group(n)
		if not groups.has(g2):
			groups[g2] = [0, 0, 0, 0]
		groups[g2][3] += 1
	for c in n.get_children():
		_perf_walk(c, groups, _p)


## Buildings (DESIGN_NOTES 78): put up each kind on the square, the pad comes
## out level, you can walk in through the door and not through the walls.
func _build_kinds_test() -> void:
	Game.sandbox = true
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	# Taxi the plane straight in through the hangar door and stop in the middle.
	var th: Dictionary = world.terrain.hollows[0]
	var txf: Transform3D = th["xf"]
	var tsz: Vector3 = th["size"]
	var tstart: Vector3 = txf * Vector3(0.0, 0.0, -tsz.z * 0.5 - 16.0)
	tstart.y = world.terrain.height_at(tstart.x, tstart.z) + 1.4
	var taim: Vector3 = txf * Vector3.ZERO
	var thead := rad_to_deg(atan2(-(taim.x - tstart.x), -(taim.z - tstart.z)))
	plane.place_parked(tstart, Quaternion(Basis(Vector3.UP, deg_to_rad(thead)) * Basis(Vector3.RIGHT, deg_to_rad(plane.sit_pitch))))
	for e in plane.engines():
		e.set_running(15.0)
	plane.direct_controls = true
	var tl := Vector3.ZERO
	for i in range(60 * 30):
		tl = (th["inv"] as Transform3D) * plane.global_position
		var stop := tl.z > 1.0
		plane.throttle = 0.0 if stop else (0.6 if plane.ground_speed < 2.0 else 0.2)
		plane.brake = 1.0 if stop else 0.0
		await get_tree().physics_frame
		if stop and plane.ground_speed < 0.2:
			break
	var tin: bool = tl.z > -2.0 and absf(tl.x) < 3.0 and not plane.is_damaged() and not plane.is_crashed
	print("kindtest: taxied in through the door: local (%.1f, %.1f), damage %s, crashed %s %s" % [tl.x, tl.z, plane.is_damaged(), plane.is_crashed, "" if tin else "<-- PROBLEM"])
	plane.throttle = 0.0
	plane.direct_controls = false
	_get_out()
	get_viewport().disable_3d = not _test.has("pics")
	var t: RefCounted = world.terrain
	var bad := 0 if tin else 1
	jobs.money = 1000000
	builds.logs = 200
	print("kindtest: home hangar hollows %d, solids %d" % [t.hollows.size(), t.solids.size()])
	# The middle of the home hangar is clear for a plane: 15 m of wingspan.
	var hb0: Dictionary = t.hollows[0]
	var hxf: Transform3D = hb0["xf"]
	var hs: Vector3 = hb0["size"]
	var hits := 0
	for zi in range(int(hs.z) + 3):
		for xi in range(-15, 16):
			var q: Vector3 = hxf * Vector3(float(xi) * 0.5, 1.0, -hs.z * 0.5 - 2.0 + float(zi))
			if float(zi) - 2.0 > hs.z - 1.6:
				continue
			if t.blocked_by_building(q, 0.3):
				hits += 1
	print("kindtest: hangar centre lane blocked at %d spots %s" % [hits, "" if hits == 0 else "<-- PROBLEM"])
	if hits > 0:
		bad += 1
	# Walk at the workbench from the middle: it stops you.
	var bench: Vector3 = hxf * Vector3(-4.5, 0, hs.z * 0.5 - 3.0)
	bench.y = t.ground_level_at(bench.x, bench.z)
	var bdir: Vector3 = hxf.basis * Vector3(0, 0, 1)
	walker.place(bench, atan2(-bdir.x, -bdir.z))
	for i in range(240):
		await get_tree().physics_frame
		walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
	var lb: Vector3 = hxf.affine_inverse() * walker.global_position
	var bench_ok: bool = lb.z < hs.z * 0.5 - 0.75 - 0.42 + 0.05
	print("kindtest: walked at the workbench: stopped at local z %.2f (bench front %.2f) %s" % [lb.z, hs.z * 0.5 - 0.75 - 0.42, "" if bench_ok else "<-- PROBLEM"])
	if not bench_ok:
		bad += 1
	var placed := {}
	for kind in ["cabin", "loghouse", "polebarn", "poleshed", "hangar"]:
		var found := false
		for gi in range(0, 400):
			var a := float(gi) * 2.399
			var r := 30.0 + float(gi) * 0.35
			var p := Vector3(cos(a) * r, 0, sin(a) * r)
			if absf(p.x) > 160.0 or absf(p.z) > 160.0:
				continue
			if kind != "hangar" and t.strip_index_at(p.x, p.z, 30.0) >= 0:
				continue
			p.y = t.height_at(p.x, p.z)
			if builds.cannot_build(kind, p) != "":
				continue
			var before: float = builds.pad_range(kind, p, a)
			var yaw := a
			var err: String = builds.build(kind, p, yaw)
			var it: Dictionary = builds.items[builds.items.size() - 1]
			var after: float = builds.pad_range(kind, it["pos"], yaw)
			print("kindtest: %s at (%.0f, %.0f): %s, ground uneven %.2f -> %.2f m %s" % [kind, p.x, p.z, err if err != "" else "built",
				before, after, "" if err == "" and after < 0.6 else "<-- PROBLEM"])
			if err != "" or after >= 0.6:
				bad += 1
			placed[kind] = it
			found = true
			break
		if not found:
			print("kindtest: nowhere to put a %s <-- PROBLEM" % kind)
			bad += 1
	# Walk in through the door of each, then try the back and side walls.
	for kind in placed.keys():
		var it2: Dictionary = placed[kind]
		var f: Array = builds.FOOT[kind]
		var xf := Transform3D(Basis(Vector3.UP, float(it2["yaw"])), it2["pos"])
		var start: Vector3 = xf * Vector3(0, 0, -float(f[1]) * 0.5 - float(builds.PORCH.get(kind, 0.0)) - 2.5)
		start.y = t.height_at(start.x, start.z)
		var face: Vector3 = xf.basis * Vector3(0, 0, 1)
		walker.place(start, atan2(-face.x, -face.z))
		for i in range(int(60.0 * (float(f[1]) + 6.0) / 2.0)):
			await get_tree().physics_frame
			walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
		var l: Vector3 = xf.affine_inverse() * walker.global_position
		var inside: bool = absf(l.x) < float(f[0]) * 0.5 and absf(l.z) < float(f[1]) * 0.5
		var warm: bool = builds.in_cabin(walker.global_position)
		print("kindtest: %s walked in: local (%.1f, %.2f, %.1f) inside %s%s %s" % [kind, l.x, l.y, l.z, inside,
			(", warm %s" % warm) if kind in builds.WARM else "", "" if inside and (warm or not kind in builds.WARM) else "<-- PROBLEM"])
		if not inside:
			bad += 1
		# now turn right and walk into the side wall for 4 s
		var right: Vector3 = xf.basis * Vector3(1, 0, 0)
		walker.place(walker.global_position, atan2(-right.x, -right.z))
		for i in range(240):
			await get_tree().physics_frame
			walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
		var l2: Vector3 = xf.affine_inverse() * walker.global_position
		var held: bool = absf(l2.x) < float(f[0]) * 0.5 + 0.05
		print("kindtest: %s side wall: local x %.2f of %.2f %s" % [kind, l2.x, float(f[0]) * 0.5, "" if held else "<-- PROBLEM"])
		if not held:
			bad += 1
		if _test.has("pics"):
			walker.place(start - face * 6.0 + Vector3(0, 0, 0), atan2(-face.x, -face.z))
			for i in range(30):
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(String(_test.get("out", "user://")) + "/bld_%s.png" % kind)
	print("kindtest: %d problems" % bad)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(builds.SAVE))


## Pickup, crash salvage and towing (DESIGN_NOTES 79).
func _truck_test() -> void:
	Game.sandbox = true
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	pickup.engine_on = true
	var t: RefCounted = world.terrain
	var shots := _test.has("pics")
	get_viewport().disable_3d = not shots
	var out_dir := String(_test.get("out", "/tmp/shots"))
	var bad := 0
	var k: int = jobs.strip_here()
	var sp: Vector3 = t.strips[k]["pos"]
	# 1. A load of freight in the plane, then the plane crashes off the strip.
	var job := {"id": 880001, "kind": "freight", "title": "Test freight", "from": k, "to": k,
		"what": "4 crates", "kg": 160.0, "pay": 900, "fragile": false, "urgent": false, "limit_min": 0.0, "pax": 0, "n": 4}
	print("trucktest: took job %s" % jobs.take_custom(job, false))
	var jb: Dictionary = jobs.carried[jobs.carried.size() - 1]
	var wreck_at := sp + Vector3(0, 0, 120.0)
	wreck_at.y = t.height_at(wreck_at.x, wreck_at.z) + 1.5
	plane.place_parked(wreck_at, plane.global_transform.basis.get_rotation_quaternion())
	await get_tree().physics_frame
	plane._crash("Test crash.")
	await get_tree().physics_frame
	var still: bool = jobs.carried.has(jb)
	print("trucktest: after the crash: job kept %s, condition %.2f, note '%s'" % [still, float(jb["condition"]), jobs.salvage_note])
	if not still:
		print("trucktest: the load was wiped by the crash <-- PROBLEM")
		bad += 1
		print("trucktest: %d problems" % bad)
		return
	# 2. The pickup drives up; pull the crates out and put them in the bed.
	_get_out()
	var pxf := Transform3D(Basis(Vector3.UP, 0.0), plane.global_position + Vector3(6.0, 0, 6.0))
	pickup.park(pxf)
	for pc in jb["pieces"]:
		walker.place(plane.global_position + Vector3(1.5, 0, 0), 0.0)
		await get_tree().physics_frame
		cargo._find_target()
		if cargo._target.is_empty() or String(cargo._target[0]) != "salvage":
			print("trucktest: no salvage prompt by the wreck ('%s') <-- PROBLEM" % cargo.prompt)
			bad += 1
			break
		cargo.interact()
		walker.place(pickup.global_transform * Vector3(0, 0, 3.8), pickup.yaw)
		await get_tree().physics_frame
		cargo._find_target()
		if cargo._target.is_empty() or String(cargo._target[0]) != "truckput":
			print("trucktest: no 'put in the bed' prompt at the tailgate ('%s') <-- PROBLEM" % cargo.prompt)
			bad += 1
			break
		cargo.interact()
	var in_bed: int = jobs.count_at(jb, "truck")
	print("trucktest: %d of 4 crates in the pickup bed, %.0f kg %s" % [in_bed, cargo.truck_load_kg(), "" if in_bed == 4 else "<-- PROBLEM"])
	if in_bed != 4:
		bad += 1
	if shots:
		await _shot_at(pickup.global_transform * Vector3(3.5, 3.0, 7.0), pickup.global_position + Vector3(0, 1, 0), out_dir + "/truck_bed.png")
	# 3. Drive it back to the strip.
	driving = pickup
	pickup.driven = true
	pickup.esim.battery = 1.0           # he turns the key (I) until it catches
	for k4 in range(6):
		if not pickup.engine_on:
			pickup.engine_toggle()
	var t0 := pickup.global_position.distance_to(sp)
	for i in range(60 * 60):
		var to: Vector3 = sp - pickup.global_position
		var fwd: Vector3 = -pickup.global_transform.basis.z
		var steer := clampf(fwd.cross(to.normalized()).y * -2.0, -1.0, 1.0)
		var dmsg: String = pickup.drive(1.0 / 60.0, Vector2(steer, 0.6 if pickup.body.speed < 8.0 else 0.0), false)
		if i == 120:
			var wg := []
			for w in pickup.body.wheels:
				var wp: Vector3 = pickup.global_transform * (w[0] as Vector3)
				wg.append("%.2f/%.2f" % [world.terrain.wheel_ground(wp.x, wp.z), world.terrain.height_at(wp.x, wp.z)])
			print("trucktest: 2 s in: speed %.2f, msg '%s', blocked here %s, wheel ground %s, towing %s, mass %.0f, esim running %s rpm %.0f, nose blocked %s" % [pickup.body.speed, dmsg, world.terrain.blocked_by_building(pickup.global_position, 1.0, pickup), str(wg), pickup.towing, pickup.body.mass(), pickup.esim.running, pickup.esim.rpm,
				world.terrain.blocked_by_building(pickup.global_position - pickup.global_transform.basis.z * 3.2 + Vector3(0, 1, 0), 1.0, pickup)])
		if Vector2(to.x, to.z).length() < 25.0:
			break
		if i % 30 == 0:
			await get_tree().physics_frame
	for i in range(240):
		pickup.drive(1.0 / 60.0, Vector2.ZERO, true)
	driving = null
	pickup.driven = false
	var t1 := pickup.global_position.distance_to(sp)
	print("trucktest: drove from %.0f m to %.0f m from the strip, bed still %d crates %s" % [t0, t1, jobs.count_at(jb, "truck"), "" if t1 < 40.0 and jobs.count_at(jb, "truck") == 4 else "<-- PROBLEM"])
	if t1 >= 40.0:
		bad += 1
	# 4. Unload at the strip: delivered and paid.
	var money0: int = jobs.money
	for n in range(4):
		walker.place(pickup.global_transform * Vector3(0, 0, 3.8), pickup.yaw)
		await get_tree().physics_frame
		cargo._find_target()
		if cargo._target.is_empty() or String(cargo._target[0]) != "truckout":
			break
		cargo.interact()
		walker.place(pickup.global_transform * Vector3(2.5 + float(n) * 0.8, 0, 5.0), pickup.yaw)
		await get_tree().physics_frame
		cargo._find_target()
		cargo.interact()
	var paid: int = jobs.money - money0
	print("trucktest: unloaded at the strip: paid $%d %s" % [paid, "" if paid > 0 else "<-- PROBLEM"])
	if paid <= 0:
		bad += 1
	# 5. Hitch the wash plant and tow it.
	prospect.owned_sluices += 1
	var sl_msg: String = prospect.place_sluice(pickup.global_transform * Vector3(0, 0, 14.0), pickup.yaw + PI)
	print("trucktest: sluice trailer: ", sl_msg)
	var wp: Node3D = null
	for tw in prospect.towables:
		if tw.kind == "sluice" or tw.kind == "washplant":
			wp = tw
	if wp == null:
		print("trucktest: (towing part skipped: no sluice trailer or wash plant here)")
		print("trucktest: %d problems" % bad)
		return
	# park so the ball sits under its tongue
	var tg: Vector3 = wp.tongue_point()
	var hb: Basis = pickup.global_transform.basis
	pickup.park(Transform3D(hb, tg - hb * pickup.HITCH + Vector3(0, 0.0, 0)))
	var msg: String = pickup.truck_action()
	print("trucktest: hitch: %s" % msg)
	if pickup.towing != wp:
		print("trucktest: didn't hitch <-- PROBLEM")
		bad += 1
	else:
		var w0: Vector3 = wp.global_position
		driving = pickup
		pickup.driven = true
		var worst := 0.0
		for i in range(60 * 25):
			var steer2 := 0.5 if i > 60 * 8 and i < 60 * 14 else 0.0
			pickup.drive(1.0 / 60.0, Vector2(steer2, 0.5 if pickup.body.speed < 5.0 else 0.0), false)
			worst = maxf(worst, pickup.hitch_point().distance_to(wp.tongue_point()))
			if i % 60 == 0:
				await get_tree().physics_frame
		for i in range(240):
			pickup.drive(1.0 / 60.0, Vector2.ZERO, true)
		var moved: float = wp.global_position.distance_to(w0)
		var up: float = wp.global_transform.basis.y.y
		var rec: Array = prospect.plants if wp.kind == "washplant" else prospect.sluices
		print("trucktest: towed the %s %.0f m, tongue stayed within %.2f m of the ball, upright %.2f, its record follows %s %s" % [
			wp.display_name(), moved, worst, up, wp.idx < rec.size() and (rec[wp.idx] as Transform3D).origin.distance_to(wp.global_position) < 0.01,
			"" if moved > 30.0 and worst < 0.3 and up > 0.9 else "<-- PROBLEM"])
		if not (moved > 30.0 and worst < 0.3 and up > 0.9):
			bad += 1
		if shots:
			await _shot_at(pickup.global_transform * Vector3(-9.0, 4.0, 9.0), pickup.global_transform * Vector3(0, 1, 5), out_dir + "/truck_tow.png")
		for i in range(5):
			await get_tree().process_frame
		print("trucktest: prompt while towing: '%s' (extra '%s', on_foot %s)" % [cargo.prompt, cargo.extra_prompt, on_foot])
		print("trucktest: unhitch: %s" % pickup.truck_action())
		driving = null
		pickup.driven = false
	print("trucktest: %d problems" % bad)
	for f in ["pickup.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))


func _shot_at(from: Vector3, look: Vector3, path: String) -> void:
	var c := Camera3D.new()
	add_child(c)
	c.global_position = from
	c.look_at(look)
	c.make_current()
	for i in range(8):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	c.queue_free()
	cam.make_current()


## Walked into the prop (DESIGN_NOTES 81).
func _on_prop_strike(at: Vector3) -> void:
	var fwd: Vector3 = -plane.global_transform.basis.z
	gore.prop_strike(plane, plane.global_transform * Vector3(0, 0.05, -2.12), fwd, at,
		func(x: float, z: float) -> float: return world.terrain.ground_level_at(x, z))
	# he goes down, flung off to the side of the disc
	walker.model.rotation = Vector3(-PI * 0.5, 0, 0.4)
	walker.model.position = Vector3(0, 0.25, 0)
	hud.red_flash = 1.0
	jolt(1.0)
	_foot_down = true
	hud.push_message("You walked into the propeller. Open the menu to start again from the last airstrip.", 12.0)


## Birds flush and get hit on the take-off roll; walking into the prop (81, 82).
func _bird_test() -> void:
	Game.sandbox = true
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	var shots := _test.has("pics")
	get_viewport().disable_3d = not shots
	var out_dir := String(_test.get("out", "/tmp/shots"))
	var bad := 0
	var t: RefCounted = world.terrain
	var c0: Array = birds.counts()
	print("birdtest: %d birds on the ground, %d flying" % [c0[0], c0[1]])
	if c0[0] + c0[1] < 20:
		bad += 1
	# 1. Gulls sitting on the runway 160 m ahead; full power take-off roll.
	plane.place_on_strip(0)
	await get_tree().physics_frame
	var fwd: Vector3 = -plane.global_transform.basis.z
	var gulls: Dictionary = {}
	for f in birds.flocks:
		if f["kind"] == "gull":
			gulls = f
	var spot: Vector3 = plane.global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 160.0
	gulls["target"] = spot
	for b in gulls["birds"]:
		var o := Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0))
		b["off"] = o
		b["p"] = spot + o + Vector3(0, t.height_at(spot.x, spot.z), 0)
	if shots:
		await _shot_at(spot + Vector3(-6, 2.5, -8), spot, out_dir + "/birds_ground.png")
	for e in plane.engines():
		e.set_running(15.0)
	plane.direct_controls = true
	var flushed := false
	for i in range(60 * 14):
		plane.throttle = 1.0
		plane.brake = 0.0
		plane.in_yaw = 0.0
		await get_tree().physics_frame
		if String(gulls["state"]) != "ground":
			flushed = true
		if birds.strikes > 0 and shots and i % 30 == 0:
			pass
	print("birdtest: take-off roll through gulls: flushed %s, strikes %d, prop %.2f, fuselage %.2f, wings %.2f/%.2f, speed %.0f m/s %s" % [
		flushed, birds.strikes, plane.part("prop"), plane.part("fuselage"), plane.part("wing_l"), plane.part("wing_r"),
		(plane.vel as Vector3).length(), "" if flushed else "<-- PROBLEM"])
	if not flushed:
		bad += 1
	# force one strike to check the effects, if luck spared us
	if birds.strikes == 0:
		var b0: Dictionary = gulls["birds"][0]
		b0["alive"] = true
		b0["p"] = plane.global_transform * Vector3(0, 0.75, -1.0)
		birds._strikes()
		print("birdtest: forced strike: strikes %d, plane decals %d" % [birds.strikes, gore.plane_decals.size()])
		if birds.strikes == 0:
			bad += 1
	plane.throttle = 0.0
	# 2. Stop, engine running, walk into the prop.
	plane.place_on_strip(0)
	for e in plane.engines():
		e.set_running(15.0)
	await get_tree().physics_frame
	_get_out()
	var pxf: Transform3D = plane.global_transform
	var start: Vector3 = pxf * Vector3(0.0, 0, -6.0)
	start.y = t.height_at(start.x, start.z)
	walker.place(start, atan2(-(pxf.basis.z).x, -(pxf.basis.z).z))
	for i in range(60 * 6):
		await get_tree().physics_frame
		if walker.dead_by_prop:
			break
		walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
	print("birdtest: walked into the prop: dead %s, ground splats %d, plane splats %d %s" % [walker.dead_by_prop, gore.ground_decals.size(), gore.plane_decals.size(), "" if walker.dead_by_prop and gore.ground_decals.size() > 10 else "<-- PROBLEM"])
	if not walker.dead_by_prop:
		bad += 1
	if shots:
		for i in range(20):
			await get_tree().process_frame
		await _shot_at(pxf * Vector3(4.5, 2.2, -6.5), pxf * Vector3(0, 0.3, -2.0), out_dir + "/prop_gore.png")
	print("birdtest: %d problems" % bad)


## The hangar door opens and shuts (walls follow); the loft stairs climb (78).
func _door_test() -> void:
	Game.sandbox = true
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	_get_out()
	var shots := _test.has("pics")
	get_viewport().disable_3d = not shots
	var out_dir := String(_test.get("out", "/tmp/shots"))
	var bad := 0
	var t: RefCounted = world.terrain
	if world.hangar_doors.is_empty():
		print("doortest: no hangar door <-- PROBLEM")
		return
	var door: Node3D = world.hangar_doors[0][0]
	var hb: Dictionary = t.hollows[0]
	var xf: Transform3D = hb["xf"]
	var sz: Vector3 = hb["size"]
	var face: Vector3 = xf.basis * Vector3(0, 0, 1)
	var heading := atan2(-face.x, -face.z)
	# shut it: walk at it from outside, you stop at the door
	door.target = 0.0
	door.open = 0.0
	door._pose()
	if shots:
		await _shot_at(xf * Vector3(-14.0, 4.0, -sz.z * 0.5 - 22.0), xf * Vector3(0, 3.0, -sz.z * 0.5), out_dir + "/hangar_shut.png")
	var start: Vector3 = xf * Vector3(0, 0, -sz.z * 0.5 - 5.0)
	start.y = t.height_at(start.x, start.z)
	walker.place(start, heading)
	for i in range(300):
		await get_tree().physics_frame
		walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
	var l1: Vector3 = xf.affine_inverse() * walker.global_position
	print("doortest: door shut, walked at it: stopped at local z %.2f (door at %.2f) %s" % [l1.z, -sz.z * 0.5, "" if l1.z < -sz.z * 0.5 else "<-- PROBLEM"])
	if l1.z >= -sz.z * 0.5:
		bad += 1
	# open it from the switch
	door.toggle()
	if shots:
		await get_tree().create_timer(5.5).timeout
		await _shot_at(xf * Vector3(-14.0, 4.0, -sz.z * 0.5 - 22.0), xf * Vector3(0, 3.0, -sz.z * 0.5), out_dir + "/hangar_opening.png")
	var t_end := Time.get_ticks_msec() + 15000
	while door.open < 1.0 and Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
	walker.place(start, heading)
	for i in range(300):
		await get_tree().physics_frame
		walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
	var l2: Vector3 = xf.affine_inverse() * walker.global_position
	print("doortest: opened (%.2f), walked in: local z %.2f %s" % [door.open, l2.z, "" if l2.z > -sz.z * 0.5 + 1.0 else "<-- PROBLEM"])
	if l2.z <= -sz.z * 0.5 + 1.0:
		bad += 1
	# the stairs: start at the foot, walk up toward the back wall
	var pf: Dictionary = t.platforms[0]
	var pxf: Transform3D = pf["xf"]
	var psz: Vector3 = pf["size"]
	var foot: Vector3 = pxf * Vector3(0, 0, -psz.z * 0.5 - 0.4)
	foot.y = t.ground_level_at(foot.x, foot.z)
	var up: Vector3 = pxf.basis * Vector3(0, 0, 1)
	walker.place(foot, atan2(-up.x, -up.z))
	var top_y := -INF
	for i in range(240):
		await get_tree().physics_frame
		walker.step(1.0 / 60.0, Vector2(0, 1), false, false)
		top_y = maxf(top_y, walker.global_position.y)
	var rise: float = top_y - foot.y
	print("doortest: walked up the stairs: rose %.2f m (loft at %.2f) %s" % [rise, float(pf["h1"]), "" if rise > float(pf["h1"]) - 0.2 else "<-- PROBLEM"])
	if rise <= float(pf["h1"]) - 0.2:
		bad += 1
	if shots:
		await _shot_at(walker.global_position + Vector3(0, 1.6, 0) - up * 0.5 + Vector3(0, 0.2, 0), walker.global_position + Vector3(0, 1.0, 0) - pxf.basis.x * 6.0, out_dir + "/hangar_loft.png")
	print("doortest: %d problems" % bad)


## F9: record 15 s of frame timing and camera motion, then say what jitters
## and write it to jitter_log.txt in the project folder (DESIGN_NOTES 87).
var _jit_on := false
var _jit: Array = []
var _jit_t0 := 0
var _jit_last := 0
var _jit_pf := 0
func _jitter_sample() -> void:
	if not _jit_on:
		return
	var now := Time.get_ticks_usec()
	var pf := Engine.get_physics_frames()
	var subj: Vector3 = walker.get_global_transform_interpolated().origin if on_foot else plane.render_xf().origin
	_jit.append([float(now - _jit_last) / 1000.0 if _jit_last > 0 else 16.7, pf - _jit_pf, Engine.get_physics_interpolation_fraction(), cam.global_position, subj, Engine.get_frames_per_second()])
	_jit_last = now
	_jit_pf = pf
	if now - _jit_t0 > 15000000:
		_jit_on = false
		_jitter_report()


func _jitter_report() -> void:
	var n := _jit.size()
	if n < 30:
		return
	var dts: Array = []
	var ticks := {}
	var spikes := 0
	var cam_jerk := 0
	var rel_jerk := 0
	var lines: Array[String] = ["frame_ms,ticks,frac,cam_x,cam_y,cam_z,subj_x,subj_y,subj_z,cam_minus_subj_x,cam_minus_subj_y,cam_minus_subj_z,fps"]
	for i in range(n):
		var r: Array = _jit[i]
		dts.append(float(r[0]))
		ticks[int(r[1])] = int(ticks.get(int(r[1]), 0)) + 1
		var c: Vector3 = r[3]
		var sj: Vector3 = r[4]
		var rel := c - sj
		lines.append("%.2f,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f,%.4f,%.4f,%d" % [r[0], r[1], r[2], c.x, c.y, c.z, sj.x, sj.y, sj.z, rel.x, rel.y, rel.z, int(r[5])])
		if i >= 2:
			var s1: Vector3 = (_jit[i][3] as Vector3) - (_jit[i - 1][3] as Vector3)
			var s0: Vector3 = (_jit[i - 1][3] as Vector3) - (_jit[i - 2][3] as Vector3)
			if s1.length() > 0.02 and (s1 - s0).length() > 0.5 * maxf(s0.length(), s1.length()):
				cam_jerk += 1
			var r1: Vector3 = (_jit[i][3] as Vector3) - (_jit[i][4] as Vector3) - ((_jit[i - 1][3] as Vector3) - (_jit[i - 1][4] as Vector3))
			if r1.length() > 0.03:
				rel_jerk += 1
	dts.sort()
	var med: float = dts[n / 2]
	for d in dts:
		if float(d) > med * 1.6:
			spikes += 1
	var worst: float = dts[n - 1]
	var tick_txt := ""
	for k in ticks.keys():
		tick_txt += "%d tick:%d  " % [k, ticks[k]]
	var summary := "Frames %d, median %.1f ms, worst %.1f ms, slow frames %d. Physics ticks per frame: %s. Camera jerks %d, camera-vs-subject wobbles %d." % [n, med, worst, spikes, tick_txt, cam_jerk, rel_jerk]
	lines.insert(0, "# " + summary)
	var f := FileAccess.open(ProjectSettings.globalize_path("res://jitter_log.txt"), FileAccess.WRITE)
	if f == null:
		f = FileAccess.open("user://jitter_log.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()
	hud.push_message("Jitter check: " + summary, 15.0)
	print("jitter: ", summary)


## Fly the user's slow path (jitter log 2026-10-10) and time every script at
## each point, to find what grinds the frame rate down near (88, -31).
func _spot_test() -> void:
	_on_start_requested(0, false)
	await get_tree().create_timer(2.0).timeout
	var pts: Array = [Vector3(0, 60, 0), Vector3(155, 32, -57), Vector3(130, 30, -38), Vector3(110, 30, -32), Vector3(95, 18, -30), Vector3(88, 12, -31)]
	for p in pts:
		plane.place_in_air(p, deg_to_rad(240.0), 40.0)
		var tp := 0.0
		var tph := 0.0
		var n := 0
		var t0 := Time.get_ticks_usec()
		for i in range(90):
			plane.place_in_air(p, deg_to_rad(240.0), 40.0)
			await get_tree().process_frame
			if i >= 30:
				tp += Performance.get_monitor(Performance.TIME_PROCESS)
				tph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
				n += 1
		var found: Array = []
		_perf_scripts(get_tree().root, found)
		var res: Array = []
		for nd in found:
			for fn in ["_process", "_physics_process"]:
				if not (nd as Node).has_method(fn) or (nd as Node).get_script() == null or nd == self:
					continue
				var t1 := Time.get_ticks_usec()
				for k in range(5):
					(nd as Node).call(fn, 1.0 / 120.0)
				var us := float(Time.get_ticks_usec() - t1) / 5.0
				if us > 150.0:
					res.append([us, "%s.%s (%s)" % [(nd as Node).name, fn, String((nd as Node).get_script().resource_path).get_file()]])
		var t2 := Time.get_ticks_usec()
		for k in range(5):
			_physics_process(1.0 / 120.0)
		var mph := float(Time.get_ticks_usec() - t2) / 5.0
		var t3 := Time.get_ticks_usec()
		for k in range(5):
			_process(1.0 / 60.0)
		var mp := float(Time.get_ticks_usec() - t3) / 5.0
		var ta := Time.get_ticks_usec()
		for k in range(20):
			plane._tree_contacts(1.0 / 240.0)
		var tb := Time.get_ticks_usec()
		for k in range(20):
			plane._building_contacts(1.0 / 240.0)
		var tc := Time.get_ticks_usec()
		for k in range(20):
			plane._contacts(1.0 / 240.0)
		var td := Time.get_ticks_usec()
		print("spot:   trees %.3f ms  buildings %.3f ms  contacts %.3f ms  (solids %d hollows %d body points %d agl %.1f)" % [(tb - ta) / 20000.0, (tc - tb) / 20000.0, (td - tc) / 20000.0, plane.terrain.solids.size(), plane.terrain.hollows.size(), plane.BODY_POINTS.size(), plane.agl])
		res.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
		print("spot: %s  process %.2f ms  physics %.2f ms  main.process %.2f ms  main.physics %.2f ms  nodes %d" % [str(p), tp / n * 1000.0, tph / n * 1000.0, mp / 1000.0, mph / 1000.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		for r in res.slice(0, 6):
			print("spot:     %.2f ms  %s" % [float(r[0]) / 1000.0, r[1]])


## Get in, drive a moment and get out of every kind of machine.
func _mach_test() -> void:
	_on_start_requested(0, false)
	await get_tree().create_timer(1.5).timeout
	var p0: Vector3 = plane.global_position + Vector3(25, 0, 0)
	var d: Node3D = prospect._spawn_dozer(Transform3D(Basis.IDENTITY, Vector3(p0.x, world.terrain.height_at(p0.x, p0.z), p0.z)))
	var p1 := p0 + Vector3(0, 0, 14)
	var e: Node3D = prospect._spawn_excavator(Transform3D(Basis.IDENTITY, Vector3(p1.x, world.terrain.height_at(p1.x, p1.z), p1.z)))
	var list: Array = [d, e, pickup, water_truck, loader]
	if not forklifts.is_empty():
		list.append(forklifts[0])
	for m in list:
		if m == null:
			continue
		_get_out_of_plane_for_test()
		_get_on_forklift(m)
		for i in range(30):
			await get_tree().physics_frame
		_get_off_forklift()
		await get_tree().process_frame
		print("machtest: %s in/out ok, walker at %s" % [String(m.get_script().resource_path).get_file(), str(walker.global_position.round())])
	print("machtest: done")


func _get_out_of_plane_for_test() -> void:
	if not on_foot:
		_get_out()


## Dig a hole with the dozer, blade pressed down, pass after pass: does the
## machine stay on the ground?
func _deep_doz_test() -> void:
	_on_start_requested(0, false)
	await get_tree().create_timer(1.5).timeout
	var p0 := Vector3(57.0, 0, 34.0)
	var d: Node3D = prospect._spawn_dozer(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(p0.x, world.terrain.height_at(p0.x, p0.z), p0.z)))
	_get_out()
	_get_on_forklift(d)
	d.blade_toggle()
	var dt := 1.0 / 120.0
	for pass_i in range(14):
		for i in range(int(4.0 / dt)):
			d.blade_adjust(dt, -1.0)
			_drive_forklift(dt, Vector2(0, 1))
			if i == 240 and pass_i == 0:
				print("deepdoz: mid forward at %s load %.2f blade %.2f down %s" % [str(d.global_position), d.load_m3, d._blade_goal, d.blade_down])
			if i % 60 == 0:
				await get_tree().process_frame
		for i in range(int(4.0 / dt)):
			_drive_forklift(dt, Vector2(0, -1))
			if i % 60 == 0:
				await get_tree().process_frame
		var gp: Vector3 = d.global_position
		if pass_i == 0:
			print("deepdoz: after pass 0 at %s (start %s)" % [str(gp), str(p0)])
		var gy: float = world.terrain.height_at(gp.x, gp.z)
		var lo := 1.0e9
		for k in range(-6, 7):
			lo = minf(lo, world.terrain.height_at(gp.x, gp.z - float(k)))
		print("deepdoz: pass %d  dozer y %.2f  ground under %.2f  (gap %.2f)  lowest nearby %.2f  natural %.2f  load %.1f  tilt %.0f" % [pass_i, gp.y, gy, gp.y - gy, lo, world.terrain.natural_at(gp.x, gp.z), d.load_m3, d.body.tilt_deg])


## The 14 t excavator behind a trommel plant: dig beside it, swing to the
## hopper, dump. Does the bucket clear the grizzly and does the plant wash it?
func _feed_test() -> void:
	_on_start_requested(0, false)
	await get_tree().create_timer(1.5).timeout
	Game.sandbox = true
	var t = world.terrain
	var p := Vector3(57.0, 0, 34.0)
	print("feedtest: plant: ", prospect.place_washplant(p, 0.0))
	var pxf: Transform3D = prospect.plants.back()
	var hop: Vector3 = pxf * prospect.EquipModels.TROMMEL_HOPPER
	# Excavator behind the hopper, facing the plant.
	var back := float(OS.get_environment("FEEDBACK")) if OS.has_environment("FEEDBACK") else 4.2
	var ep: Vector3 = pxf * Vector3(0, 0, prospect.EquipModels.TROMMEL_HOPPER.z + back)
	ep.y = t.height_at(ep.x, ep.z)
	var ex: Node3D = prospect._spawn_excavator(Transform3D(Basis.IDENTITY, ep))
	await get_tree().process_frame
	print("feedtest: hopper top %s, excavator at %s, %.1f m apart (reach %.1f)" % [str(hop), str(ex.global_position), Vector2(hop.x - ep.x, hop.z - ep.z).length(), ex.REACH_MAX])
	var dig_at: Vector3 = ep + Vector3(5.0, 0, 2.0)
	for cyc in range(3):
		ex.aim = Vector3(dig_at.x, t.height_at(dig_at.x, dig_at.z), dig_at.z)
		ex.dig_or_dump()
		while ex.busy():
			var m: String = ex.work(1.0 / 30.0)
			if m != "":
				print("feedtest: ", m)
			await get_tree().process_frame
		print("feedtest: dug %.2f m3" % (float(ex.bucket_load.get("over", 0.0)) + float(ex.bucket_load.get("pay", 0.0))))
		ex.aim = Vector3(hop.x, t.height_at(hop.x, hop.z), hop.z)
		ex.dig_or_dump()
		var low_over := 1.0e9
		var said := ""
		while ex.busy():
			var m2: String = ex.work(1.0 / 30.0)
			if m2 != "":
				said = m2
			var tp: Vector3 = ex.teeth()
			if m2 != "":
				print("feedtest:   teeth at dump %s, %.2f m from the hopper centre, %.2f above its top" % [str(tp), Vector2(tp.x - hop.x, tp.z - hop.z).length(), tp.y - hop.y])
			if Vector2(tp.x - hop.x, tp.z - hop.z).length() < 1.4:
				low_over = minf(low_over, tp.y)
			await get_tree().process_frame
		print("feedtest: dump -> '%s'; lowest teeth over the hopper %.2f (hopper top %.2f) %s" % [said, low_over, hop.y, "CLEAR" if low_over > hop.y + 0.3 else "<-- THROUGH THE STEEL"])
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = ep + Vector3(9, 6, 6)
	cam.look_at(lerp(ep, hop, 0.5) + Vector3(0, 1.5, 0))
	cam.current = true
	ex.aim = Vector3(hop.x, t.height_at(hop.x, hop.z), hop.z)
	for i in range(60):
		ex.work(1.0 / 30.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT") if OS.has_environment("SHOT") else "user://feed.png")
	print("feedtest: shot saved")


## The trommel on gas: stopped plants don't turn or wash; started, they burn
## fuel and wash the hopper down; dry, they stop; a can refuels them; an
## empty can fills at a pump.
func _gas_test() -> void:
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	Game.sandbox = true
	if not on_foot:
		_get_out()
	var pr = prospect
	print("gastest: ", pr.place_washplant(Vector3(57, 0, 34), 0.0))
	var i: int = pr.plants.size() - 1
	var xf: Transform3D = pr.plants[i]
	var hop: Vector3 = xf * pr.EquipModels.TROMMEL_HOPPER
	var eng: Vector3 = xf * pr.EquipModels.TROMMEL_ENGINE
	var drum: Node3D = pr._drums[i]
	var b0: Basis = drum.transform.basis
	print("gastest: dump into stopped plant -> ", pr._dump(Vector3(hop.x, 0, hop.z), {"over": 0.5, "pay": 0.35, "g": 4.0}))
	await get_tree().create_timer(1.0).timeout
	print("gastest: stopped: drum turned %s, hopper %.2f m3 (want no, 0.85)" % [not drum.transform.basis.is_equal_approx(b0), float(pr.plant_hopper[i][0])])
	var tg: Array = pr.target(eng, eng + Vector3(0, 0, -1))
	print("gastest: at the engine: %s" % str(tg))
	print("gastest: start -> ", pr.act(String(tg[0]), eng, eng))
	var g0: float = pr.gold_g
	var f0: float = pr.plant_fuel[i]
	b0 = drum.transform.basis
	var t0 := Time.get_ticks_msec()
	while float(pr.plant_hopper[i][0]) > 0.0 and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	print("gastest: running %.0f s: drum turned %s, hopper %.2f m3, gold +%.2f g, fuel %.1f -> %.1f L, smoke %s" % [(Time.get_ticks_msec() - t0) / 1000.0, not drum.transform.basis.is_equal_approx(b0), float(pr.plant_hopper[i][0]), pr.gold_g - g0, f0, float(pr.plant_fuel[i]), pr._plant_smoke[i].emitting])
	pr.plant_fuel[i] = 0.05
	await get_tree().create_timer(6.0).timeout
	print("gastest: out of gas -> on %s, smoke %s" % [pr.plant_on[i], pr._plant_smoke[i].emitting])
	print("gastest: start dry -> ", pr.act("plant_engine", eng, eng))
	inv.add("gas_can", 1, true)
	var tg2: Array = pr.target(eng, eng)
	print("gastest: with the can: %s -> %s" % [tg2[0], pr.act(String(tg2[0]), eng, eng)])
	print("gastest: in hand now %s, fuel %.1f L" % [inv.in_hand(), float(pr.plant_fuel[i])])
	var fp: Vector3 = world.fuel_points[0] if not world.fuel_points.is_empty() else Vector3.INF
	print("gastest: fuel pumps %d" % world.fuel_points.size())
	if fp != Vector3.INF:
		var tg3: Array = pr.target(fp, fp)
		print("gastest: at the pump with the empty can: %s -> %s, in hand %s" % [tg3[0], pr.act(String(tg3[0]), fp, fp) if tg3.size() > 0 else "", inv.in_hand()])
	pr.save()
	var cf := ConfigFile.new()
	cf.load(pr.SAVE)
	print("gastest: saved fuel %s on %s hopper %s" % [str(cf.get_value("p", "plant_fuel", [])), str(cf.get_value("p", "plant_on", [])), str(cf.get_value("p", "plant_hopper", []))])


## The wheel loader: fill from a heap, lift, try a tall hopper, dump in a
## pile, swap to the forks.
func _loader_test() -> void:
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	Game.sandbox = true
	if not on_foot:
		_get_out()
	var L: Node3D = loader
	print("loadtest: loader at %s, lift %.2f, attach %s" % [str(L.global_position.round()), L.lift, L.attach])
	var ahead: Vector3 = L.global_transform * Vector3(0, 0, -7.0)
	prospect.pile(ahead, 6.0)
	print("loadtest: heap of 6 m3 ahead, ground there %.2f (natural %.2f)" % [world.terrain.height_at(ahead.x, ahead.z), world.terrain.natural_at(ahead.x, ahead.z)])
	_get_on_forklift(L)
	var dt := 1.0 / 120.0
	var msgs := {}
	var t := 0.0
	while t < 8.0 and L.fill() < 0.999:
		var m: String = L.drive(dt, Vector2(0, 0.6), -1.0, 0.0, false)
		if m != "":
			msgs[m] = true
		t += dt
		if int(t / dt) % 30 == 0:
			await get_tree().physics_frame
	print("loadtest: pushed in for %.1f s: bucket %.0f%% (%.2f m3), lip %.2f above ground, msgs %s" % [t, L.fill() * 100.0, L._load_m3(), L.lip().y - world.terrain.height_at(L.lip().x, L.lip().z), str(msgs.keys())])
	for i in range(int(2.5 / dt)):
		L.drive(dt, Vector2(0, -0.5) if i < int(1.5 / dt) else Vector2.ZERO, 1.0, 1.0, false)
	print("loadtest: curled and lifted: lift %.2f, tilt %.2f, lip %.2f m up, load %.2f m3" % [L.lift, L.tilt, L.lip().y - world.terrain.height_at(L.lip().x, L.lip().z), L._load_m3()])
	# a plant in front: the hopper is too tall for a loader
	var pp: Vector3 = L.global_transform * Vector3(0, 0, -9.0)
	var pxf := Transform3D(Basis(Vector3.UP, L.yaw), Vector3(pp.x, world.terrain.height_at(pp.x, pp.z), pp.z))
	prospect.plants.append(pxf)
	prospect._spawn_plant(pxf)
	prospect.plant_fuel[prospect.plants.size() - 1] = 40.0
	var hop: Vector3 = prospect.plants.back() * prospect.EquipModels.TROMMEL_HOPPER
	# put the loader so its lip is over the hopper
	var lipnow: Vector3 = L.lip()
	var shift := Vector3(hop.x - lipnow.x, 0, hop.z - lipnow.z)
	var xf: Transform3D = L.global_transform
	xf.origin += shift
	L.park(xf)
	print("loadtest: over the hopper, lip %.2f vs hopper top %.2f" % [L.lip().y, hop.y])
	var said := ""
	for i in range(int(2.0 / dt)):
		var m2: String = L.drive(dt, Vector2.ZERO, 0.0, -1.0, true)
		if m2 != "":
			said = m2
	print("loadtest: dump at the hopper -> '%s', load %.2f m3" % [said, L._load_m3()])
	xf.origin -= Vector3(L.global_transform.basis.z.x, 0, L.global_transform.basis.z.z) * -6.0
	L.park(xf)
	for i in range(int(1.0 / dt)):
		var m3: String = L.drive(dt, Vector2.ZERO, 0.0, -1.0, true)
		if m3 != "":
			said = m3
	print("loadtest: dump on open ground -> '%s', load %.2f m3" % [said, L._load_m3()])
	for i in range(int(4.0 / dt)):
		L.drive(dt, Vector2.ZERO, -1.0, 1.0, true)
	print("loadtest: swap -> %s; %s" % [L.swap_attachment(), L.status()])
	print("loadtest: swap back -> %s" % L.swap_attachment())
	_get_off_forklift()
	print("loadtest: out at %s" % str(walker.global_position.round()))


## Generator and rope lights: set it down, hang a chain of strings, dark
## until it runs, lit while it runs, dark when it's dry.
func _power_test() -> void:
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	if not on_foot:
		_get_out()
	var pw = power
	var p0 := Vector3(60, 0, 40)
	p0.y = world.terrain.height_at(p0.x, p0.z)
	inv.add("generator", 1, true)
	var tg: Array = prospect.target(p0, p0 + Vector3(0, 0, -1))
	print("powertest: holding the generator: %s" % str(tg))
	print("powertest: ", prospect.act(String(tg[0]), p0, p0 + Vector3(0, 0, -1)))
	inv.add("rope_light", 3, true)
	var at := p0
	for k in range(3):
		var tr: Array = prospect.target(at, at)
		var m1: String = prospect.act(String(tr[0]), at, at)
		var to := at + Vector3(12, 0, 0)
		to.y = world.terrain.height_at(to.x, to.z)
		var tr2: Array = prospect.target(to, to)
		var m2: String = prospect.act(String(tr2[0]), to, to)
		print("powertest: string %d: '%s' then '%s'" % [k, m1, m2])
		at = to
	print("powertest: strings %d, lit %d (want 0)" % [pw.strings.size(), pw.lit_count()])
	var gp: Vector3 = (pw.generators[0]["xf"] as Transform3D).origin
	var tt: Array = prospect.target(gp, gp)
	print("powertest: at the generator, hands full of rope: %s" % str(tt[0]))
	inv.add("gas_can", 1, true)
	inv.can_l = 20.0
	var tf: Array = prospect.target(gp, gp)
	print("powertest: with the can: %s -> %s" % [tf[0], prospect.act(String(tf[0]), gp, gp)])
	inv.slots[inv.active] = {}
	var ts: Array = prospect.target(gp, gp)
	print("powertest: empty-handed: %s -> %s" % [ts[0], prospect.act(String(ts[0]), gp, gp)])
	await get_tree().create_timer(1.2).timeout
	print("powertest: running: lit %d of %d, lights on %d" % [pw.lit_count(), pw.strings.size(), _count_lights(pw)])
	pw.generators[0]["fuel"] = 0.002
	await get_tree().create_timer(1.5).timeout
	print("powertest: dry: on %s, lit %d" % [pw.generators[0]["on"], pw.lit_count()])
	pw.save()
	print("powertest: pick up -> %s, in hand %s" % [pw.take_generator(gp), inv.in_hand()])


func _count_lights(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is OmniLight3D and (ch as OmniLight3D).visible:
			c += 1
	return c


## The square is laid out from Game.world_seed. Saves that change the ground
## (digs, burnt patches, felled trees, the tunnels' gear, where the machines
## stand) only fit the world they were made in: when the seed or the
## generator changes, start those afresh.
func _check_world_stamp() -> void:
	const STAMP := "user://world_stamp.cfg"
	var want := "%d:%d" % [Game.world_seed, load("res://scripts/map_gen.gd").VERSION]
	var cf := ConfigFile.new()
	var had := ""
	if cf.load(STAMP) == OK:
		had = String(cf.get_value("w", "stamp", ""))
	if had == want:
		return
	load("res://scripts/ground.gd").use_seed(Game.world_seed)
	for f in ["user://fire.cfg", "user://power.cfg", "user://world.cfg", "user://loader.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	# Prospecting: keep the gold and the gear you've paid for; the digs,
	# ladders and timber go, machines and plants move to the new mining pad,
	# placed sluice boxes go back in stock.
	var pc := ConfigFile.new()
	if pc.load("user://prospect.cfg") == OK:
		for key in ["vox_edits", "roofs", "ladders", "sets"]:
			pc.set_value("p", key, [])
		if pc.has_section_key("ground", "idxs"):
			pc.erase_section("ground")
		var placed: Array = pc.get_value("p", "sluices", [])
		pc.set_value("p", "owned_sluices", int(pc.get_value("p", "owned_sluices", 0)) + placed.size())
		pc.set_value("p", "sluices", [])
		var pad: Vector2 = load("res://scripts/ground.gd").lay()["pad"]
		var k := 0
		for key2 in ["plants", "excavators", "dozers"]:
			var xs: Array = pc.get_value("p", key2, [])
			for i in range(xs.size()):
				var at := Vector3(pad.x - 16.0 + 9.0 * float(k % 4), 0, pad.y + 16.0 + 10.0 * float(k / 4))
				xs[i] = Transform3D(Basis.IDENTITY, at)
				k += 1
			pc.set_value("p", key2, xs)
		pc.set_value("p", "plant_hopper", [])
		pc.save("user://prospect.cfg")
	if had != "":
		print("world: new layout (%s -> %s): digs, fires and placed gear start afresh" % [had, want])
	cf.set_value("w", "stamp", want)
	cf.save(STAMP)


## Safety net: anything that ends up under the ground it should be standing
## on (a machine below the dirt it's driving on, or anyone dropping out of the
## bottom of the world) is put back on top, and where and how goes in the log
## so the cause can be found.
var _guard_t := 0.0
func _fall_guard(delta: float) -> void:
	if world == null or prospect == null:
		return                   # still building (the first awaited frames of _ready)
	_guard_t += delta
	if _guard_t < 0.25:
		return
	_guard_t = 0.0
	var t = world.terrain
	var machines: Array = [pickup, water_truck, fuel_truck, loader] + prospect.dozers + prospect.excavators
	for m in machines:
		if m == null or not is_instance_valid(m):
			continue
		var mp: Vector3 = (m as Node3D).global_transform * Vector3(0, 1.0, 0)     # the middle of the body, whichever way up
		var gy: float = t.height_at(mp.x, mp.z)
		if mp.y < gy - 2.0:
			push_warning("FELL THROUGH: %s at %s, ground %.2f (natural %.2f), %s" % [String(m.get_script().resource_path).get_file(), str(mp.round()), gy, t.natural_at(mp.x, mp.z), "driven" if driving == m else "parked"])
			hud.push_message("Something went wrong with the ground under the %s: put it back on top." % String(m.name).to_lower(), 4.0)
			var xf: Transform3D = (m as Node3D).global_transform
			xf.origin.y = gy + 0.3
			if m.has_method("park"):
				m.park(xf)
	if on_foot and driving == null and not walker.in_plane:
		var wp: Vector3 = walker.global_position
		var vg = world.ground_view
		var bottom := -60.0
		if vg != null and vg.get("terrain") != null and vg.terrain is Node:
			bottom = float(vg.terrain.voxel_bounds.position.y) * 0.25 + 1.0
		if wp.y < bottom or not is_finite(wp.y):
			var gy2: float = t.height_at(wp.x, wp.z)
			push_warning("FELL THROUGH: walker at %s, ground %.2f, below the world (%.1f)" % [str(wp.round()), gy2, bottom])
			walker.place(Vector3(wp.x, gy2 + 0.5, wp.z), walker.yaw)
			hud.push_message("You fell out of the world there: put you back on the surface. (Logged.)", 5.0)


## Pictures of every asset (test "assetshot"): each vehicle, machine, plane
## and piece of kit framed from the front three-quarter (and the rear for the
## big ones), then the strip props by place.
func _asset_shots() -> void:
	_on_start_requested(0, false)
	await get_tree().create_timer(1.5).timeout
	_get_out()
	await get_tree().create_timer(0.5).timeout
	hud.visible = false
	var out_dir := String(_test.get("out", "user://"))
	if prospect.excavators.is_empty():
		prospect._spawn_excavator(Transform3D(Basis.IDENTITY, pickup.global_position + Vector3(14, 0, 8)))
	await get_tree().create_timer(1.0).timeout
	var list: Array = [["pickup", pickup, true], ["water_truck", water_truck, true], ["loader", loader, true]]
	for d in prospect.dozers:
		list.append(["dozer", d, true])
	for e in prospect.excavators:
		list.append(["excavator", e, true])
	if not forklifts.is_empty():
		list.append(["forklift", forklifts[0], true])
	list.append(["plane_wolverine", visual, true])
	for nm in ["SaleDC3", "Windsock0", "BushHangar", "Bench"]:
		var f := get_tree().root.find_child(nm, true, false) as Node3D
		if f != null:
			list.append([nm.to_lower(), f, nm == "SaleDC3"])
	for k in ["WashPlant", "Sluice", "Trommel", "Generator", "Pump"]:
		for f2 in get_tree().root.find_children(k + "*", "Node3D", true, false):
			if (f2 as Node3D).is_visible_in_tree() and (f2 as Node3D).global_position.y > 1.0:
				list.append([String(f2.name).to_lower(), f2, false])
				break
	for e2 in list:
		var nd: Node3D = e2[1]
		if nd == null or not is_instance_valid(nd):
			continue
		var ab := _world_aabb(nd)
		if ab.size == Vector3.ZERO:
			continue
		var c := ab.get_center()
		var r := maxf(ab.size.length() * 0.5, 0.4)
		var bx := nd.global_transform.basis.orthonormalized()
		var dirs: Array = [["front34", Vector3(-1.0, 0.45, -1.25)]]
		if e2[2]:
			dirs.append(["rear34", Vector3(1.1, 0.5, 1.2)])
		for dv in dirs:
			var dir: Vector3 = (bx * (dv[1] as Vector3)).normalized()
			dir.y = absf(dir.y)
			var eye := c + dir * (r / sin(deg_to_rad(20.0)) * 1.05)
			_eco_xf = Transform3D.IDENTITY.looking_at((c - eye).normalized(), Vector3.UP)
			_eco_xf.origin = eye
			_eco_on = true
			cam.global_transform = _eco_xf
			cam.fov = 40.0
			for i in range(5):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, e2[0], dv[0]])
			print("ASSETSHOT %s_%s" % [e2[0], dv[0]])
	# the pilot himself, close
	walker.visible = true
	await get_tree().create_timer(0.3).timeout
	var wp: Vector3 = walker.global_position + Vector3(0, 0.9, 0)
	var wb: Basis = walker.global_transform.basis
	var weye := wp + (wb * Vector3(-1.2, 0.3, -2.6))
	_eco_xf = Transform3D.IDENTITY.looking_at((wp - weye).normalized(), Vector3.UP)
	_eco_xf.origin = weye
	cam.global_transform = _eco_xf
	for i in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/pilot.png" % out_dir)
	# the strip props by place: each fuel pump with its drums
	var n := 0
	for fp in world.fuel_points:
		if n >= 3:
			break
		var fpos: Vector3 = fp
		var feye := fpos + Vector3(-5.0, 2.6, -6.0)
		_eco_xf = Transform3D.IDENTITY.looking_at((fpos + Vector3(0, 0.8, 0) - feye).normalized(), Vector3.UP)
		_eco_xf.origin = feye
		cam.global_transform = _eco_xf
		for i in range(5):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/fuelpump_%d.png" % [out_dir, n])
		n += 1


func _world_aabb(nd: Node3D) -> AABB:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var st: Array = [nd]
	while not st.is_empty():
		var n0: Node = st.pop_back()
		for c0 in n0.get_children():
			st.append(c0)
		if n0 is MeshInstance3D and (n0 as MeshInstance3D).mesh != null and (n0 as MeshInstance3D).is_visible_in_tree() and not String(n0.name).contains("Precip"):
			var ab: AABB = (n0 as MeshInstance3D).get_aabb()
			for ci in range(8):
				var cp: Vector3 = (n0 as MeshInstance3D).global_transform * ab.get_endpoint(ci)
				lo = lo.min(cp)
				hi = hi.max(cp)
	if lo.x > 1e8:
		return AABB()
	return AABB(lo, hi - lo)


## Before/after of the light (test "lookshot"): the same two cameras with the
## classic light and the Alaska cold light, at midday and at dawn (mist).
## Winter (test "wintershot"): snow on the ground, and a fire that's melted
## its way out through it for a couple of minutes.
func _winter_shots() -> void:
	Game.season = Game.WINTER
	Game.weather = 0
	Game.time_of_day = 12.5
	Game.notify_changed()
	_on_start_requested(0, false)
	await get_tree().create_timer(2.0).timeout
	_get_out()
	hud.visible = false
	walker.visible = false
	var out_dir := String(_test.get("out", "user://"))
	var fp := Vector3(20, 0, 0)
	fp.y = world.terrain.ground_level_at(fp.x, fp.z)
	print("WINTERSHOT ground shader: %s, ground view: %s" % [world._terrain_mat.shader.resource_path, world.ground_view.get_script().resource_path])
	if _test.has("snow0"):
		world._terrain_mat.set_shader_parameter("snow_cover", 0.0)
	var shots: Array = [["winter_before", 0], ["winter_fire", int(_test.get("burn", 600))]]
	if _test.has("fireonly"):
		shots = [shots[1]]
	for sh in shots:
		if int(sh[1]) > 0:
			fire.ignite(fp, 4.0)
			for fi in range(int(sh[1])):
				fire._tick(0.25)
			if _test.has("meltall"):
				fire.melt.fill(1.0)
				fire._melt_dirty = true
			fire._update_melt_tex()
			var mx := 0.0
			var cnt := 0
			for mv in fire.melt:
				mx = maxf(mx, mv)
				if mv > 0.5:
					cnt += 1
			var mt = world._terrain_mat.get_shader_parameter("melt")
			print("WINTERSHOT melt max %.2f, cells over half %d, ground has melt map: %s, snow_cover %s" % [mx, cnt, mt != null, str(world._terrain_mat.get_shader_parameter("snow_cover"))])
			if DisplayServer.get_name() == "headless":
				return
			fire._visuals()
			fire._update_char()
		var eye := fp + Vector3(-28, 22, 26)
		_eco_xf = Transform3D.IDENTITY.looking_at((fp - eye).normalized(), Vector3.UP)
		_eco_xf.origin = eye
		_eco_on = true
		cam.global_transform = _eco_xf
		cam.fov = 60.0
		for i in range(12):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, sh[0]])
		print("WINTERSHOT ", sh[0])


func _look_shots() -> void:
	_on_start_requested(0, false)
	await get_tree().create_timer(2.0).timeout
	_get_out()
	hud.visible = false
	walker.visible = false
	var out_dir := String(_test.get("out", "user://"))
	var g0: float = world.terrain.ground_level_at(-150.0, -60.0)
	var cams: Array = [
		["wide", Vector3(-170, g0 + 14.0, -70), Vector3(120, g0 - 10.0, 160)],
	]
	for tm in [13.0, 6.0]:
		for cold in [false, true]:
			Game.time_of_day = tm
			Game.cold_look = cold
			Game.notify_changed()
			for c in cams:
				var eye: Vector3 = c[1]
				var tgt: Vector3 = c[2]
				_eco_xf = Transform3D.IDENTITY.looking_at((tgt - eye).normalized(), Vector3.UP)
				_eco_xf.origin = eye
				_eco_on = true
				cam.global_transform = _eco_xf
				cam.fov = 65.0
				var waited := 0.0
				while waited < 8.0 and world.vegetation != null and not world.vegetation.is_idle():
					await get_tree().create_timer(0.5).timeout
					waited += 0.5
				for i in range(8):
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var nm := "%s_%02d_%s" % [c[0], int(tm), "cold" if cold else "classic"]
				get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, nm])
				print("LOOKSHOT ", nm)


## The water truck's low range (test "lowtest"): into the mud bog in 6x6
## and in 6x6 Low, 10 s full throttle each.
func _low_test() -> void:
	Game.sandbox = true
	Game.season = Game.SUMMER
	_on_start_requested(0, false)
	await get_tree().create_timer(0.5).timeout
	var t: RefCounted = world.terrain
	var bog: Vector2 = load("res://scripts/ground.gd").mudbog()
	for mode in [1, 2]:
		var at := Vector3(bog.x - 26.0, 0, bog.y)
		at.y = t.ground_level_at(at.x, at.z)
		water_truck.park(Transform3D(Basis(Vector3.UP, -PI * 0.5), at))
		water_truck.engine_on = true
		water_truck.air_psi = 120.0
		for k in range(mode):
			water_truck.four_wd_toggle()
		driving = water_truck
		water_truck.driven = true
		var p0: Vector3 = water_truck.global_position
		var top := 0.0
		for i in range(60 * 10):
			water_truck.drive(1.0 / 60.0, Vector2(0.0, 1.0), false)
			water_truck.work(1.0 / 60.0)
			top = maxf(top, water_truck.body.speed)
			if i % 60 == 0:
				await get_tree().physics_frame
		print("lowtest %s: %.1f m in 10 s, top %.0f km/h, rpm %.0f, power %.0f kW" % ["6x6" if mode == 1 else "6x6 LOW", Vector2(water_truck.global_position.x - p0.x, water_truck.global_position.z - p0.z).length(), top * 3.6, water_truck.rpm, water_truck.body.power / 1000.0])
	get_tree().quit()


## The fuel truck (test "fueltest"): where it parks, fuelling the pickup, then
## loading at the pump.
func _fuel_test() -> void:
	Game.sandbox = true
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	var ft = fuel_truck
	print("fueltest: parked at %s (pumps %s), diesel %.0f avgas %.0f" % [str(ft.global_position.round()), str(world.fuel_points), ft.diesel_gal, ft.avgas_gal])
	for cz in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		for cx in [-1.2, 1.2]:
			var cp: Vector3 = ft.global_transform * Vector3(cx, 1.0, cz)
			if world.terrain.blocked_by_building(cp, 0.2):
				print("fueltest: BLOCKED at ", cp.round())
	pickup.fuel_gal = 2.0
	var at: Vector3 = ft.global_transform * Vector3(4.0, 0, 0)
	at.y = world.terrain.ground_level_at(at.x, at.z)
	pickup.park(Transform3D(Basis.IDENTITY, at))
	ft.engine_on = true
	print("fueltest: E -> %s" % ft.truck_action())
	for i in range(60 * 10):
		var m: String = ft.work(1.0 / 60.0)
		if m != "":
			print("fueltest: says ", m)
	print("fueltest: pickup now %.1f gal, truck avgas %.0f" % [pickup.fuel_gal, ft.avgas_gal])
	ft.avgas_gal = 200.0
	var fp: Vector3 = world.fuel_points[0]
	ft.park(Transform3D(ft.global_transform.basis, fp + Vector3(6, world.terrain.ground_level_at(fp.x + 6, fp.z) - fp.y, 0)))
	print("fueltest: by the pump: E -> %s" % ft.truck_action())
	for i in range(60 * 20):
		var m2: String = ft.work(1.0 / 60.0)
		if m2 != "":
			print("fueltest: says ", m2)
	print("fueltest: after 20 s at the pump: diesel %.0f avgas %.0f" % [ft.diesel_gal, ft.avgas_gal])
	get_tree().quit()


## The workshop's one-step swaps (test "swaptest"): a big block, a turbo
## with no flanged manifold yet, 35-inch tyres on a stock truck.
func _swap_test() -> void:
	Game.sandbox = true
	_on_start_requested(0, false)
	await get_tree().create_timer(0.5).timeout
	var f: Dictionary = PartsLib.fitted["pickup"]
	for t in [["engine", "bb460"], ["turbo", "turbo_t3"], ["tyres", "tyres_mud35"]]:
		var u := PartsLib.make(String(t[1]))
		var pl := PartsLib.plan_swap(u, String(t[0]), ["pickup", "v8"], f)
		var names: Array = []
		for sl in ["engine", "heads", "intake", "exhaust", "turbo", "lift", "tyres"]:
			if pl["fitted"].has(sl):
				names.append("%s=%s" % [sl, PartsLib.def_of(int(pl["fitted"][sl])).get("name", "?")])
		print("swaptest %s: why '%s' cost $%d notes %s\n   %s" % [t[1], pl["why"], pl["cost"], pl["notes"], ", ".join(names)])
		PartsLib.discard_plan(pl)
		PartsLib.inst.erase(u)
	get_tree().quit()


## Rattles (test "rattletest"): the pickup across rough tundra for a few
## seconds, starting cold with the belt squealing; counts what played.
func _rattle_test() -> void:
	Game.sandbox = true
	Game.season = Game.SUMMER
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	_get_out()
	var t: RefCounted = world.terrain
	var at := Vector3(60, 0, 60)
	at.y = t.ground_level_at(at.x, at.z)
	pickup.park(Transform3D(Basis.IDENTITY, at))
	pickup.esim.battery = 1.0
	driving = pickup
	pickup.driven = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	noises.squeal()
	for k in range(6):
		if not pickup.engine_on:
			pickup.engine_toggle()
	var maxj := 0.0
	var squeal_s := 0.0
	for i in range(60 * 6):
		pickup.drive(1.0 / 60.0, Vector2(0.3 * sin(i * 0.02), 1.0), false)
		await get_tree().physics_frame
		maxj = maxf(maxj, noises.jolt)
		if noises.squealing():
			squeal_s += 1.0 / 60.0
	print("rattletest: speed %.1f m/s, max jolt %.1f m/s2, played %s, belt squealed %.1f s (vol %.1f dB)" % [pickup.body.speed, maxj, noises.counts, squeal_s, noises._belt.volume_db])
	get_tree().quit()


## Mud (test "mudtest"): the pickup and the water truck on firm ground, in
## light mud and in the deep muskeg; full throttle 8 s, then try rocking out.
## Fell a tree, buck it; burn one, salvage it. Logs on hand and the trunks gone.
func _log_test() -> void:
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	if not on_foot:
		await _get_out_of_plane_for_test()
	var t: RefCounted = world.terrain
	var found := 0
	for kind in ["cut", "burnt"]:
		var tr := {}
		for r in range(10, 300, 6):
			for a in range(16):
				var q := Vector3(cos(a * 0.39) * r, 0, sin(a * 0.39) * r)
				var c := Flora.tree_near(t, Vector3(q.x, t.height_at(q.x, q.z) + 1.0, q.z))
				if not c.is_empty() and not Flora.felled.has(Flora.key(int(c["ti"]), int(c["tj"]))):
					tr = c
					break
			if not tr.is_empty():
				break
		if tr.is_empty():
			print("logtest: no tree found <-- PROBLEM")
			return
		var base: Vector3 = tr["base"]
		world.fell_tree(int(tr["ti"]), int(tr["tj"]), Vector3(4.0, -1.0 if kind == "burnt" else 0.0, 0.0))
		var mid := base + Vector3(float(tr["height"]) * 0.4, 0, 1.0)
		walker.place(Vector3(mid.x, t.height_at(mid.x, mid.z), mid.z), 0.0)
		for i in range(6):
			await get_tree().process_frame
		var l0: int = (cargo.own_logs["pieces"] as Array).size()
		var seen := not _down_log.is_empty()
		print("logtest: %s tree %.0f m tall: prompt '%s'" % [kind, float(tr["height"]), cargo.extra_prompt])
		if seen:
			_buck_target = _down_log
			_buck_t = 0.05
		for i in range(10):
			await get_tree().process_frame
		var gone := Flora.cleared(Flora.key(int(tr["ti"]), int(tr["tj"])))
		var l1: int = (cargo.own_logs["pieces"] as Array).size()
		print("logtest: %s: bucked -> %d logs on the ground, trunk gone %s %s" % [kind, l1 - l0, gone, "" if seen and gone and l1 > l0 else "<-- PROBLEM"])
		found += 1
	# carry them: one to the pickup bed, one onto the log trailer, then the
	# trailer's to the deck
	var pcs: Array = cargo.own_logs["pieces"]
	var steps := [["pickup", pickup.global_transform * Vector3(0, 0, 3.8)], ["trailer", log_trailer.global_transform * Vector3(-1.5, 0, 0.3)]]
	for st in steps:
		var lp: Dictionary = {}
		for pc in pcs:
			if pc["at"] == "dropped":
				lp = pc
		if lp.is_empty():
			print("logtest: no log left to carry <-- PROBLEM")
			return
		var q: Vector3 = lp["pos"]
		walker.place(q + Vector3(0.6, 0, 0), 0.0)
		await get_tree().process_frame
		cargo._find_target()
		var a0: String = cargo._target[0] if not cargo._target.is_empty() else ""
		cargo.interact()
		var at2: Vector3 = st[1]
		walker.place(Vector3(at2.x, world.terrain.height_at(at2.x, at2.z), at2.z), 0.0)
		await get_tree().process_frame
		cargo._find_target()
		var pr: String = cargo.prompt
		cargo.interact()
		print("logtest: pick '%s' -> carried to the %s: '%s' -> now %s on vehicle %d" % [a0, st[0], pr, lp["at"], int(lp.get("veh", -1))])
	# drive the trailer to the deck (just move it) and roll the logs off
	log_trailer.global_transform = Transform3D(log_trailer.global_transform.basis, Vector3(LOG_DECK.x + 3.0, world.terrain.height_at(LOG_DECK.x + 3.0, LOG_DECK.z), LOG_DECK.z))
	var bp: Vector3 = log_trailer.global_transform * Vector3(-1.5, 0, 0.3)
	walker.place(Vector3(bp.x, world.terrain.height_at(bp.x, bp.z), bp.z), 0.0)
	await get_tree().process_frame
	var s0: int = builds.logs
	cargo._find_target()
	var pr2: String = cargo.prompt
	cargo.interact()
	print("logtest: at the deck: '%s' -> stock %d -> %d %s" % [pr2, s0, builds.logs, "" if builds.logs > s0 else "<-- PROBLEM"])


## Logs a downed tree gives: about one per 6 m of trunk; a burnt one
## loses one to the char.
func _log_count(t: Dictionary) -> int:
	var n := clampi(int(round(float(t["height"]) / 6.0)), 1, 4)
	if bool(t["charred"]):
		n = maxi(n - 1, 1)
	return n


func _mud_test() -> void:
	load("res://scripts/wheeled_body.gd").force_lock = _test.has("locked")
	load("res://scripts/wheeled_body.gd").debug = _test.has("dump")
	Game.sandbox = true
	Game.season = Game.SUMMER
	Game.weather = 0
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	_get_out()
	var t: RefCounted = world.terrain
	# find a firm, a light and a deep spot, each with the same 12 m run ahead (heading north)
	var spots := {}
	for z in range(-150, 150, 4):
		for x in range(-150, 150, 4):
			var ok := true
			var lo := 9.0
			var hi := -9.0
			for d in range(0, 14, 2):
				var mm: float = t.mud_at(float(x), float(z) - float(d))
				lo = minf(lo, mm)
				hi = maxf(hi, mm)
			if t.orig_depth_at(float(x), float(z)) > 0.05 or t.water_level_at(float(x), float(z)) > -1.0e8:
				ok = false
			if not ok:
				continue
			if hi < 0.03 and not spots.has("firm") and t.strip_index_at(float(x), float(z)) < 0:
				spots["firm"] = Vector3(x, 0, z)
			elif lo > 0.3 and hi < 0.5 and not spots.has("light"):
				spots["light"] = Vector3(x, 0, z)
			elif lo > 0.62 and not spots.has("deep"):
				spots["deep"] = Vector3(x, 0, z)
	var bogc2: Vector2 = load("res://scripts/ground.gd").mudbog()
	spots["bog"] = Vector3(bogc2.x - 26.0, 0, bogc2.y)
	print("mudtest spots: ", spots, " bog centre ", bogc2, " mud there ", t.mud_at(bogc2.x, bogc2.y), " depth ", t.height_at(bogc2.x - 30.0, bogc2.y) - t.height_at(bogc2.x, bogc2.y))
	for veh in [pickup, water_truck]:
		for kind in ["firm", "light", "deep", "bog"]:
			if not spots.has(kind):
				print("mudtest: no %s spot" % kind)
				continue
			var at: Vector3 = spots[kind]
			at.y = t.ground_level_at(at.x, at.z)
			veh.park(Transform3D(Basis(Vector3.UP, -PI * 0.5) if kind == "bog" else Basis.IDENTITY, at))     # the bog: drive in along it
			if veh == pickup:
				veh.esim.battery = 1.0
				for k in range(6):
					if not veh.engine_on:
						veh.engine_toggle()
			else:
				veh.engine_on = true
			if veh.get("air_psi") != null:
				veh.air_psi = 120.0
			if _test.has("awd") and veh.has_method("four_wd_toggle"):
				if veh.get("drive_mode") != null:
					veh.drive_mode = 0
				print("  ", veh.four_wd_toggle())
			driving = veh
			veh.driven = true
			var p0: Vector3 = veh.global_position
			var top := 0.0
			for i in range(60 * 8):
				veh.drive(1.0 / 60.0, Vector2(0.0, 1.0), false)
				top = maxf(top, veh.body.speed)
				if i % 60 == 0:
					await get_tree().physics_frame
			var dist := Vector2(veh.global_position.x - p0.x, veh.global_position.z - p0.z).length()
			var sk: Array = veh.body.sink
			var msk := 0.0
			for v in sk:
				msk = maxf(msk, float(v))
			print("mudtest %-11s %-5s: 8 s full throttle -> %5.1f m, top %4.1f m/s (%3.0f km/h), now %4.1f m/s, mud %.2f, sunk %.2f m, spinning %.2f" % [veh.name, kind, dist, top, top * 3.6, veh.body.speed, veh.body.mud_now, msk, veh.body.spin_now])
			if _test.has("dump") and absf(veh.body.speed) < 1.0:
				print(veh.body.dump())
			if kind == "deep" and absf(veh.body.speed) < 1.0:
				# rock it: back, forward, back, forward
				var p1: Vector3 = veh.global_position
				for r in range(4):
					var dir := -1.0 if r % 2 == 0 else 1.0
					for i in range(60 * 3):
						veh.drive(1.0 / 60.0, Vector2(0.0, dir * 0.7), false)
					for i in range(30):
						veh.drive(1.0 / 60.0, Vector2.ZERO, false)
				print("mudtest %-11s deep : rocking 4 times moved it %.1f m, sunk now %.2f" % [veh.name, Vector2(veh.global_position.x - p1.x, veh.global_position.z - p1.z).length(), float(veh.body.sink.max())])
			driving = null
			veh.driven = false
	var dz: Node3D = prospect.dozers[0] if not prospect.dozers.is_empty() else null
	if dz != null and spots.has("deep"):
		var at2: Vector3 = spots["deep"]
		at2.y = t.ground_level_at(at2.x, at2.z)
		dz.body.place(Transform3D(Basis.IDENTITY, at2 + Vector3(0, 0.3, 0)))
		dz.body.settle()
		var p2: Vector3 = dz.body.pos
		for i in range(60 * 8):
			dz.body.step(1.0 / 60.0, 1.0, 1.0)
		print("mudtest dozer       deep : 8 s full -> %.1f m, mud %.2f, sunk %.2f m" % [Vector2(dz.body.pos.x - p2.x, dz.body.pos.z - p2.z).length(), dz.body.mud_now, dz.body.sink])


## The water truck's diesel (test "dieseltest"): start, idle, pull away hard,
## lift (engine brake), into the mud; print what the sound is doing.
func _diesel_test() -> void:
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	_get_out()
	var wt = water_truck
	var es: Node = wt.get_node("EngineSound")
	driving = wt
	wt.driven = true
	wt.air_psi = 120.0
	var phases: Array = [["start", 0.0, 3.0], ["idle", 0.0, 1.5], ["pull", 1.0, 9.0], ["lift", 0.0, 3.0], ["light", 0.3, 3.0]]
	wt.engine_toggle()
	var t := 0.0
	for ph in phases:
		var tt := 0.0
		while tt < float(ph[2]):
			var dt := 1.0 / 30.0
			wt.drive(dt, Vector2(0.0, float(ph[1])), false)
			tt += dt
			t += dt
			await get_tree().process_frame
			if int(tt * 30.0) % 15 == 0:
				var vols := []
				for i in range(3):
					vols.append("%d:%+.0f/%+.0f" % [[1000, 1450, 1900][i], es._d_load[i].volume_db, es._d_coast[i].volume_db])
				print("dieseltest %-5s t=%4.1f rpm %4.0f spd %4.1f load %.2f heard %.2f idle %+.0f %s turbo %+.0f (boost %.2f) jake %+.0f start %s" % [ph[0], t, wt.rpm, wt.body.speed, wt.load_now, es._d_heard, es._d_idle.volume_db, " ".join(vols), es._d_turbo.volume_db, es._d_boost, es._d_jake.volume_db, es._d_start.playing])
	wt.engine_toggle()
	for i in range(20):
		wt.drive(1.0 / 30.0, Vector2.ZERO, true)
		await get_tree().process_frame
	print("dieseltest stop: rundown playing %s, heard %.2f" % [es._d_stop.playing, es._d_heard])


## The aeroplane you're in carries its parts under its registration: its own
## carburettor and maybe a turbo (DESIGN_NOTES 111).
func _plane_parts_key() -> void:
	if plane == null:
		return
	var want := "plane:" + String(plane.reg)
	for e in plane.engines():
		if e.parts_key != want:
			e.parts_key = want
	if not PartsLib.fitted.has(want):
		var d := {}
		for sl in PartsLib.PLANE_STOCK.keys():
			if String(PartsLib.PLANE_STOCK[sl]) != "":
				d[sl] = PartsLib.make(String(PartsLib.PLANE_STOCK[sl]), randf_range(0.7, 0.9))
		PartsLib.fitted[want] = d
		PartsLib.save_all()


## A plane sitting in a grass fire: tyres, fabric and paint go, and the
## tanks are next (DESIGN_NOTES 137).
var _plane_fire_told := -100.0
func _plane_in_fire(delta: float) -> void:
	_plane_fuse(delta)
	if fire == null or plane == null or not plane.on_ground or plane.is_crashed:
		return
	if not fire.burning_at(plane.global_position):
		return
	if not plane.on_fire and randf() < 0.1 * delta:
		plane._start_fire(0.4)
	for part in ["tire_l", "tire_r", "tailwheel", "fuselage", "elevator", "rudder", "flaps"]:
		plane.hurt(part, 0.05 * delta)
	for part2 in ["wing_l", "wing_r", "tank_l", "tank_r"]:
		plane.hurt(part2, 0.025 * delta)
	if _clock - _plane_fire_told > 8.0:
		_plane_fire_told = _clock
		hud.push_message("The plane's sitting in the fire! Move it or put it out.", 5.0)


## Every machine as a box in the world (ground.gd movers, DESIGN_NOTES 141):
## the walker can't walk through them and they can't drive through each other.
var _plant_solid_xf := {}
const MOVER_SIZE := {"tug": Vector3(1.3, 1.1, 2.3), "log_trailer": Vector3(2.3, 1.2, 5.2), "forklift": Vector3(1.25, 2.2, 2.7),
	"dozer": Vector3(3.2, 3.0, 4.8), "excavator": Vector3(2.8, 3.0, 4.6)}
func _update_movers() -> void:
	var t: RefCounted = world.terrain
	if t == null or not t.has_method("set_mover"):
		return
	for e in _all_vehicles():
		var n: Node3D = e[2]
		if n == null or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var key: String = e[0]
		var sz: Vector3
		var b = n.get("body")
		if b != null and b.get("size") is Vector3:
			sz = b.size
		else:
			sz = MOVER_SIZE.get(key.get_slice("_", 0) if not key.begins_with("log_") else "log_trailer", Vector3(2.0, 2.0, 3.0))
		t.set_mover(key, n, n.global_transform.orthonormalized(), sz)
	# towed gear: the wash plants (a tall hopper at one end, the drum and its
	# chute at the other) and the sluice trailers
	if prospect != null:
		for i in range(prospect.towables.size()):
			var tw: Node3D = prospect.towables[i]
			if tw == null or not is_instance_valid(tw) or not tw.is_inside_tree():
				continue
			var plant: bool = String(tw.kind) == "washplant"
			var tsz := Vector3(2.6, 3.6, 8.4) if plant else Vector3(1.5, 1.4, 2.4)       # the sluice's bed, not its tongue
			var toff := Vector3(0, 0, 0.4) if plant else Vector3(0, 0, 0.3)
			t.set_mover("tow_%d" % i, tw, tw.global_transform.orthonormalized() * Transform3D(Basis.IDENTITY, toff), tsz)
		# the skid wash plants: solid (the plane hits them too); the oversize
		# chute's end stays clear so a trailer can back under it
		for j in range(prospect.plants.size()):
			var pxf: Transform3D = prospect.plants[j]
			if _plant_solid_xf.get(j) != pxf:
				_plant_solid_xf[j] = pxf
				t.set_solid("plant_%d" % j, pxf.orthonormalized() * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.4)), Vector3(2.6, 3.6, 8.4))


## The plane alight: if nobody puts it out, the tanks go up (DESIGN_NOTES 142).
func _plane_fuse(delta: float) -> void:
	if plane == null or not plane.on_fire or float(plane._fire_fuel) < 3.0:
		_plane_fire_t = 0.0
		_plane_fuse_told = false
		return
	_plane_fire_t += delta
	if _plane_fire_t > PLANE_FUSE - 10.0 and not _plane_fuse_told:
		_plane_fuse_told = true
		hud.push_message("The plane's tanks are about to go! GET CLEAR!", 5.0)
	if _plane_fire_t >= PLANE_FUSE:
		_plane_fire_t = 0.0
		var fuel_kg: float = plane._fire_fuel
		var at: Vector3 = plane.global_position
		plane._fire_fuel = 0.0
		plane.engine.set_fuel(0.0)
		if plane.engine2 != null:
			plane.engine2.set_fuel(0.0)
		for pn in plane.PART_NAMES.keys():
			plane.hurt(pn, 1.0)
		plane.fire_strength = 0.5            # the wreck burns on a while
		if not plane.is_crashed:
			plane._wreck("The fuel tanks exploded.")
		if explosions != null:
			explosions.blow(at, clampf(0.5 + fuel_kg / 200.0, 0.6, 2.5), Color(0.75, 0.74, 0.7))
		if on_foot:
			hud.push_message("The plane blew up.", 6.0)


## Water from the truck's sprays on a burning machine or the plane.
func _douse_machines(at: Vector3, r: float) -> void:
	if vdamage != null:
		vdamage.douse(at, r)
	if plane != null and plane.on_fire and plane.global_position.distance_to(at) < r + 5.0:
		plane.fire_strength = float(plane.fire_strength) - 0.05
		_plane_fire_t = maxf(_plane_fire_t - 1.0, 0.0)
		if plane.fire_strength <= 0.0:
			plane.on_fire = false
			plane.fire_strength = 0.0
			hud.push_message("The fire on the plane is out.", 4.0)


## A machine's fuse ran out: the blast, sized by the fuel aboard.
func _machine_blew(key: String, n: Node3D) -> void:
	var fuel_kg := 150.0
	if n.get("fuel_gal") != null:
		fuel_kg = float(n.get("fuel_gal")) * 3.0
		n.set("fuel_gal", 0.0)
	if n.get("diesel_gal") != null:
		fuel_kg += float(n.get("diesel_gal")) * 3.18 + float(n.get("avgas_gal")) * 2.72
		n.set("diesel_gal", 0.0)
		n.set("avgas_gal", 0.0)
	if n.get("engine_on") != null:
		n.set("engine_on", false)
	if driving == n:
		_get_off_forklift()
	if explosions != null:
		explosions.blow(n.global_position + Vector3(0, 0.8, 0), clampf(0.5 + fuel_kg / 1500.0, 0.5, 3.0), Color(0.4, 0.38, 0.33))
	_char(n, true)
	hud.push_message("The %s blew up." % key.replace("_", " "), 6.0)


## A burnt-out machine: blackened all over, paint and glass gone (a repair
## at the workshop puts it right). Drawn as a dark coat over every mesh.
static var _char_mat: StandardMaterial3D
func _char(n: Node, on: bool) -> void:
	if _char_mat == null:
		_char_mat = StandardMaterial3D.new()
		_char_mat.albedo_color = Color(0.05, 0.045, 0.04, 0.88)
		_char_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_char_mat.roughness = 1.0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _char_mat if on else null


## The blast: people, machines and the plane close to it get hurt; machines
## and a plane right next to it catch fire.
func _blast_hurt(at: Vector3, r: float, st: float) -> void:
	if on_foot:
		var d := walker.global_position.distance_to(at)
		if d < r:
			walker.health = maxf(float(walker.health) - (1.0 - d / r) * 0.9 * st, 0.0)
			hud.red_flash = 1.0
	if vdamage != null:
		for e in _all_vehicles():
			var n: Node3D = e[2]
			if n == null or not is_instance_valid(n):
				continue
			var dv := n.global_position.distance_to(at)
			if dv < 0.5:
				continue                     # the one that blew
			if dv < r * 1.3:
				var k := (1.0 - dv / (r * 1.3)) * st
				vdamage.hurt(String(e[0]), 0.4 * k, 0.6 * k, 0.3 * k)
				if dv < r * 0.6:
					vdamage.set_on_fire(String(e[0]), String(e[1]), 0.5)
	if plane != null:
		var dp := plane.global_position.distance_to(at)
		if dp > 0.5 and dp < r * 1.3:
			var kp := (1.0 - dp / (r * 1.3)) * st
			for pn in ["fuselage", "wing_l", "wing_r", "elevator", "rudder", "tire_l", "tire_r"]:
				plane.hurt(pn, 0.4 * kp)
			if dp < r * 0.6 and plane.on_ground:
				plane._start_fire(0.5)


## A burning bit landed: anything it lands on catches.
func _ignite_near(at: Vector3, r: float) -> void:
	if vdamage != null:
		for e in _all_vehicles():
			var n: Node3D = e[2]
			if n != null and is_instance_valid(n) and n.global_position.distance_to(at) < r + 1.5 and randf() < 0.5:
				vdamage.set_on_fire(String(e[0]), String(e[1]), 0.3)
	if plane != null and plane.on_ground and plane.global_position.distance_to(at) < r + 3.0 and randf() < 0.5:
		plane._start_fire(0.35)


## Every ground machine, for the damage model: [save key, name, node].
## (DESIGN_NOTES 186) cached for one physics tick / one frame: it was rebuilt 5-6
## times a tick (movers, damage model, run-over, trees, forklift driving).
var _veh_cache: Array = []
var _veh_cache_at := -1
func _all_vehicles() -> Array:
	var stamp: int = Engine.get_physics_frames() * 4096 + (Engine.get_process_frames() & 4095)
	if stamp == _veh_cache_at:
		return _veh_cache
	_veh_cache_at = stamp
	var out: Array = []
	for e in [["pickup", "pickup", pickup], ["water_truck", "water truck", water_truck], ["fuel_truck", "fuel truck", fuel_truck],
			["loader", "loader", loader], ["tug", "tug", tug], ["log_trailer", "log trailer", log_trailer]]:
		if e[2] != null:
			out.append(e)
	for i in range(forklifts.size()):
		out.append(["forklift_%d" % i, "forklift", forklifts[i]])
	if prospect != null:
		for i in range(prospect.dozers.size()):
			out.append(["dozer_%d" % i, "dozer", prospect.dozers[i]])
		for i in range(prospect.excavators.size()):
			out.append(["excavator_%d" % i, "excavator", prospect.excavators[i]])
	_veh_cache = out
	return out


func _veh_key(n: Node) -> String:
	for e in _all_vehicles():
		if e[2] == n:
			return String(e[0])
	return ""


## The workshop's repair list (menu, Workshop page): every damaged machine
## parked in the workshop area, its state, the bill, and a way to pay it.
func _repair_list() -> Array:
	var out: Array = []
	if vdamage == null:
		return out
	for e in _all_vehicles():
		var key: String = e[0]
		var n: Node3D = e[2]
		if not vdamage.damaged(key):
			continue
		var here: bool = Vector2(n.global_position.x - WORKSHOP_AT.x, n.global_position.z - WORKSHOP_AT.z).length() < WORKSHOP_R
		var cost: int = vdamage.repair_cost(key)
		out.append({"name": String(e[1]).capitalize(), "status": vdamage.status(key), "cost": cost, "here": here,
			"do": func() -> String:
				if n == driving and absf(float(n.get("speed") if n.get("speed") != null else 0.0)) > 0.5:
					return "Stop it first."
				if not Game.free_repairs and not Game.sandbox:
					jobs.money -= cost
					jobs.save_career()
				vdamage.repair(key)
				return "The %s is fixed up. $%d." % [String(e[1]), cost]})
	return out


## What's parked at the workshop (the Proving Ground apron and hangar), as the
## menu's parts page wants it (DESIGN_NOTES 111).
const WORKSHOP_AT := Vector3(-25.0, 0.0, -94.0)
const WORKSHOP_R := 95.0
const EngineSimLib = preload("res://scripts/engine_sim.gd")


func _workshop_vehicles() -> Array:
	var out: Array = []
	var here := func(n: Node3D) -> bool:
		return n != null and Vector2(n.global_position.x - WORKSHOP_AT.x, n.global_position.z - WORKSHOP_AT.z).length() < WORKSHOP_R
	if pickup != null and here.call(pickup):
		out.append({"name": "Pickup", "key": "pickup", "tags": ["pickup", "v8"],
			"slots": PartsLib.SLOTS,
			"busy": func() -> String:
				if pickup.body != null and absf(pickup.body.speed) > 0.5:
					return "Stop the pickup first."
				return "",
			"estimate": func(f: Dictionary) -> Dictionary:
				var e: Dictionary = EngineSimLib.estimate(f, ["pickup", "v8"])
				e["top_kmh"] = 30.0 * float(e["top_k"]) * clampf(pow(maxf(float(e["hp"]), 1.0) / 165.0, 0.33), 0.4, 1.6) * 3.6 if String(e["ok"]) == "" else 0.0
				return e,
			"changed": func() -> void:
				pickup.engine_on = false          # it's switched off to do the job
				pickup.parts_changed(),
			"pod_get": func() -> Array: return pickup.pod_wiring,
			"pod_set": func(i: int, sig: String) -> void: pickup.wire_gauge(i, sig)})
	for tk in [water_truck, fuel_truck]:
		if tk != null and here.call(tk):
			var tkn: Node3D = tk
			out.append({"name": "Fuel truck" if tkn.is_fuel() else "Water truck", "key": tkn.parts_key(), "tags": ["truck", "i6d"],
				"slots": PartsLib.TRUCK_SLOTS,
				"busy": func() -> String:
					if tkn.body != null and absf(tkn.body.speed) > 0.5:
						return "Stop the truck first."
					return "",
				"estimate": func(f: Dictionary) -> Dictionary:
					var e: Dictionary = tkn.truck_estimate(f)
					e["top_kmh"] = tkn.STOCK_TOP * float(e["top_k"]) * clampf(pow(maxf(float(e["hp"]), 1.0) / tkn.STOCK_HP, 0.25), 0.7, 1.3) * 3.6 if String(e["ok"]) == "" else 0.0
					return e,
				"changed": func() -> void:
					tkn.engine_on = false
					tkn.parts_changed()})
	if plane != null and here.call(plane) and bool(plane.on_ground):
		var pkey := "plane:" + String(plane.reg)
		out.append({"name": "Plane %s" % plane.reg, "key": pkey, "tags": ["aircraft"],
			"slots": PartsLib.PLANE_SLOTS,
			"busy": func() -> String:
				for e0 in plane.engines():
					if e0.running:
						return "Shut the engine down to work on it."
				return "",
			"estimate": func(f: Dictionary) -> Dictionary: return _plane_estimate(f),
			"changed": func() -> void: pass})
		if plane.plane_type != "dc3" and wolverine_cockpit != null and wolverine_cockpit.has_method("wire_gauge"):
			var pv: Dictionary = out[out.size() - 1]
			pv["pod_plane"] = true
			pv["pod_get"] = func() -> Array: return wolverine_cockpit.pod_wiring()
			pv["pod_set"] = func(i: int, sig: String) -> void: wolverine_cockpit.wire_gauge(i, sig)
	return out


## What the aeroplane's engine would make with these parts: flat out, at sea
## level and at 8,000 ft (where a turbo really earns its keep).
func _plane_estimate(f: Dictionary) -> Dictionary:
	var eng = plane.engine
	var rated: float = eng.rated_power / 745.7
	var carb := PartsLib.def_of(int(f.get("fuel", 0))) if int(f.get("fuel", 0)) > 0 else {}
	var tu := int(f.get("turbo", 0))
	var td := PartsLib.def_of(tu) if tu > 0 else {}
	var kg := 0.0
	for sl in f.keys():
		kg += float(PartsLib.def_of(int(f[sl])).get("kg", 0.0))
	if carb.is_empty():
		return {"ok": "no carburettor", "hp": 0.0, "kg": kg}
	var hp_at := func(amb: float) -> Array:
		var boost := 0.0
		if not td.is_empty():
			var tc: float = PartsLib.cond(tu)
			boost = float(td.get("psi", 7.0)) * (0.5 + 0.5 * tc)
		var mp: float = amb - 0.7 + boost * 2.036
		var vol := clampf((mp - 8.0) / 21.92, 0.0, 1.9) * (1.0 - 0.012 * boost)
		return [maxf(rated * 1.06 * vol * float(eng.health * 0.14 + 0.86) - rated * 0.06, 0.0), boost, mp]
	var sl_r: Array = hp_at.call(29.92)
	var hi_r: Array = hp_at.call(22.2)
	return {"ok": "", "hp": sl_r[0], "boost": sl_r[1], "hp_high": hi_r[0], "kg": kg, "map": sl_r[2]}


## Parts (test "partstest"): the pickup stock, then with the turbo kit; then
## that same turbo moved to the aeroplane. Measured from the real physics.
func _parts_test() -> void:
	Game.sandbox = true
	Game.season = Game.SUMMER
	Game.weather = 0
	_on_start_requested(0, false)
	await get_tree().create_timer(1.0).timeout
	_get_out()
	var t: RefCounted = world.terrain
	var sp: Vector3 = t.strips[0]["pos"]
	var pf: Dictionary = PartsLib.fitted["pickup"]
	var fit_from_shelf := func(key: String, slot: String, def: String) -> int:
		var f: Dictionary = PartsLib.fitted[key]
		for u in PartsLib.storage:
			if String(PartsLib.inst[int(u)]["def"]) == def:
				if f.has(slot):
					PartsLib.storage.append(int(f[slot]))
				f[slot] = int(u)
				PartsLib.storage.erase(u)
				return int(u)
		return 0
	var run_pickup := func(label: String) -> void:
		var at := sp + Vector3(-135.0, 0, 0)
		at.y = t.ground_level_at(at.x, at.z)
		pickup.park(Transform3D(Basis(Vector3.UP, -PI * 0.5), at))     # nose east, down the strip
		pickup.engine_on = false
		pickup.esim.battery = 1.0
		var said := ""
		for k in range(5):
			said = pickup.engine_toggle()
			if pickup.engine_on:
				break
		print("partstest pickup %s: start -> %s" % [label, said])
		driving = pickup
		pickup.driven = true
		var t80 := -1.0
		var tt := 0.0
		var peak_boost := 0.0
		for i in range(60 * 12):
			pickup.drive(1.0 / 60.0, Vector2(0.0, 1.0), false)
			tt += 1.0 / 60.0
			peak_boost = maxf(peak_boost, pickup.esim.boost_psi)
			if t80 < 0.0 and pickup.body.speed * 3.6 >= 80.0:
				t80 = tt
			if i % 60 == 0:
				await get_tree().physics_frame
		var e = pickup.esim
		print("partstest pickup %s: 0-80 km/h %s, speed after 12 s %.0f km/h, %.0f hp now, boost %.1f psi (peak %.1f), MAP %.0f kPa, air/fuel %.1f, coolant %.0f F, mass %.0f kg" % [
			label, ("%.1f s" % t80) if t80 > 0.0 else "not reached", pickup.body.speed * 3.6, e.power_w / 745.7, e.boost_psi, peak_boost, e.map_kpa, e.afr, e.coolant_f, e.mass_kg()])
		pickup.drive(1.0 / 60.0, Vector2.ZERO, true)
		pickup.engine_toggle()
		driving = null
		pickup.driven = false
	await run_pickup.call("stock")
	# the turbo kit: flanged manifold, then the turbo
	fit_from_shelf.call("pickup", "exhaust", "sb_turbo_manifold")
	var tu: int = fit_from_shelf.call("pickup", "turbo", "turbo_t3")
	print("partstest: fitted %s" % PartsLib.label(tu))
	await run_pickup.call("TURBO")
	# --- the aeroplane ---
	var run_plane := func(label: String) -> void:
		# just the take-off roll on the strip, full power, no flying
		_on_start_requested(0, false)
		await get_tree().create_timer(0.5).timeout
		plane.frozen = false
		plane.engine.set_running(plane.oat_c)
		plane.throttle = 1.0
		plane.brake = 0.0
		var p0: Vector3 = plane.global_position
		var t60 := -1.0
		var d60 := 0.0
		var peak_hp := 0.0
		for i in range(120 * 25):
			peak_hp = maxf(peak_hp, plane.engine.power / 745.7)
			if t60 < 0.0 and plane.ias_kt >= 60.0:
				t60 = float(i) / 120.0
				d60 = Vector2(plane.global_position.x - p0.x, plane.global_position.z - p0.z).length()
				break
			await get_tree().physics_frame
		print("partstest plane %s: full power %.0f hp, MAP %.1f inHg, boost %.1f psi | 0-60 kt on the strip in %.1f s and %.0f m" % [
			label, peak_hp, plane.engine.map_inhg, plane.engine.boost_psi, t60, d60])
		plane.throttle = 0.0
		plane.brake = 1.0
		plane.engine.stop()
	_plane_parts_key()
	await run_plane.call("stock")
	# unbolt the turbo from the pickup, onto the shelves, onto the plane
	pf.erase("turbo")
	PartsLib.storage.append(tu)
	var pkey := "plane:" + String(plane.reg)
	fit_from_shelf.call(pkey, "turbo", "turbo_t3")
	print("partstest: the turbo is off the pickup and on %s: %s" % [plane.reg, PartsLib.label(int(PartsLib.fitted[pkey]["turbo"]))])
	await run_plane.call("TURBO")


## The pad's triggers as pedals: right trigger 0..1 throttle, left trigger
## brake then reverse (negative). 0 with no pad.
## The implement lever (forks, loader arms, blade, miner boom, excavator boom
## in boom mode): the throttle keys (Shift / Ctrl) on the keyboard, the right
## stick up / down on a pad (pull back = up). Not the triggers: those drive.
func _implement_axis() -> float:
	var v := 0.0
	for pair in [["throttle_up", 1.0], ["throttle_down", -1.0]]:
		var slots: Array = Game.bindings.get(pair[0], [])
		for si in range(mini(2, slots.size())):
			var b: Dictionary = slots[si]
			if not b.is_empty() and String(b.get("t", "")) == "key" and Input.is_physical_key_pressed(int(b["code"]) as Key):
				v += float(pair[1])
				break
	for dev in Input.get_connected_joypads():
		var ry := Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y)
		if absf(ry) > 0.2:
			v += (ry - signf(ry) * 0.2) / 0.8
			break
	return clampf(v, -1.0, 1.0)


## True when the right stick's up / down works a machine's implement, not the view.
func _implement_on_stick(v: Node) -> bool:
	if v.has_method("dig_or_dump"):
		return v.get("mode") == 1
	if v == pickup or v == tug or v.has_method("truck_action"):
		return false
	return v.has_method("swap_attachment") or v.has_method("blade_toggle") or v.has_method("machine_action") or forklifts.has(v)


func _pedal_triggers() -> float:
	var rt := 0.0
	var lt := 0.0
	for dev in Input.get_connected_joypads():
		rt = maxf(rt, Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT))
		lt = maxf(lt, Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT))
	rt = 0.0 if rt < 0.06 else rt
	lt = 0.0 if lt < 0.06 else lt
	return rt - lt
