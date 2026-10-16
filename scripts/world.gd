extends Node3D
## Builds everything you can see that is not the aeroplane: the island, water,
## forest, airstrips, sky and light. Also applies the season and time of day.

const Terrain = preload("res://scripts/terrain.gd")
const GroundScript = preload("res://scripts/ground.gd")
const GroundView = preload("res://scripts/ground_view.gd")
const WorldLook = preload("res://scripts/world_look.gd")
const GerstnerWater = preload("res://scripts/water.gd")
const GROUND_SHADER = preload("res://shaders/ground.gdshader")
const Flora = preload("res://scripts/flora.gd")
const MeshKit = preload("res://scripts/meshkit.gd")
const BuildingModels = preload("res://scripts/building_models.gd")
const WATER_SHADER = preload("res://shaders/water.gdshader")
const VegScript = preload("res://scripts/vegetation.gd")
const DigSiteScript = preload("res://scripts/dig_site.gd")
const VoxelGroundLib = preload("res://scripts/voxel_ground.gd")

const CHUNK := 64   # terrain cells per chunk side

var terrain: RefCounted
var wind: Node = null

var _terrain_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var fuel_points: Array = []      # fuel pumps at the strips (fill a gas can here)
var _ice_mat: StandardMaterial3D
var _conifer_mat: ShaderMaterial
var _birch_mat: ShaderMaterial
var _lake_nodes: Array[MeshInstance3D] = []
const WavesScript = preload("res://scripts/waves.gd")
var waves: Node                      # wakes on the water (waves.gd)
var _patch: MeshInstance3D           # the moving, wavy water near the camera
var _patch_mat: ShaderMaterial
const PATCH_R := 90.0
var _birch_nodes: Array[MultiMeshInstance3D] = []
var _birch_mesh: ArrayMesh
var _birch_bare_mesh: ArrayMesh
var _windsocks: Array[Node3D] = []
var _env: Environment
var _cloud_ramp: Gradient
var night := 0.0                       # 0 day .. 1 full night
var runway_pts: Array = []             # [position, colour] of every runway light (storm.gd lights the near ones)
var storm: Node3D                      # storm.gd: wet ground, glow and haze, lightning (the main menu's look)
var _precip: CPUParticles3D
var _rwy_mats: Array = []              # runway light materials: edge white, threshold green
var _runway_light_mat: StandardMaterial3D
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var vegetation: Node3D
var ground_view: Node3D
var ponds: Array = []
var sale_planes: Array = []    # planes parked on aprons, for sale: {node, type}


## The for-sale plane the walker is beside, or {}.
func sale_near(p: Vector3, reach: float = 5.0) -> Dictionary:
	for e in sale_planes:
		var n: Node3D = e["node"]
		if is_instance_valid(n) and (n.global_position - p).length() < reach + (12.0 if e["type"] == "dc3" else 0.0):
			return e
	return {}


## It's been bought: the display node goes, the fleet copy has taken over.
func remove_sale(e: Dictionary) -> void:
	sale_planes.erase(e)
	var n: Node3D = e.get("node")
	if n != null and is_instance_valid(n):
		n.queue_free()


func build(seed_value: int = 1987, cells: int = 768, with_trees: bool = true) -> void:
	# Bush Pilot 2: the world is the small deformable map (ground.gd), with
	# the open plain round it and mountains far off in the haze.
	# Which map: the plants and rocks are chosen from this (flora.gd).
	Flora.outback = Game.outback()
	terrain = GroundScript.new()
	terrain.season = Game.SUMMER if Flora.outback else Game.season
	_build_sky()
	_build_region()
	_build_terrain_mesh()
	_build_water()
	# Buildings first: each one clears a patch that no plant may grow in.
	_build_strip_objects()
	_runway_lights()
	_build_docks()
	if with_trees:
		_load_felled()
		vegetation = VegScript.new()
		vegetation.name = "Vegetation"
		add_child(vegetation)
		vegetation.setup(terrain)
		terrain.has_trees = true
	apply_season()
	storm = load("res://scripts/storm.gd").new()
	storm.name = "Storm"
	storm.world = self
	add_child(storm)


# ------------------------------------------------------------------------------
#  Terrain mesh
# ------------------------------------------------------------------------------
func _build_terrain_mesh() -> void:
	# Smooth voxel ground when the Voxel Tools add-on is present (DESIGN_NOTES 69),
	# otherwise the old half-metre heightmesh.
	if ClassDB.class_exists("VoxelLodTerrain") and not OS.get_cmdline_user_args().has("heightmesh=1"):
		ground_view = load("res://scripts/voxel_ground.gd").new()
		ground_view.name = "Ground"
		add_child(ground_view)
		ground_view.setup(terrain)
		_terrain_mat = ground_view.mat
	else:
		ground_view = GroundView.new()
		ground_view.name = "Ground"
		add_child(ground_view)
		ground_view.setup(terrain)
		_terrain_mat = ground_view._mat
	if region == null:
		WorldLook.plain(self, terrain, GROUND_SHADER)


# ------------------------------------------------------------------------------
#  The mountains round the airport (Dave: "pick the most feature rich area,
#  where you can fit everything, to scale"): the built region (region.gd) -
#  Pine Ridge and its bush airport, the gorge with the steel arch bridge, the
#  road bridge, the radio mast, the fire lookout, the mine, the fossils, the
#  ore where the rocks put it - with the home airport's square set into the
#  south-east valley on the floor, its runway along the valley. The fine
#  ground and the forest cover the piece with all of that in it (4 x 2.7 km);
#  the rest of the region carries on coarser to the horizon.
# ------------------------------------------------------------------------------
# Dave: "the airport 3/4 up a mountain, a cliff at the end of the runway, great
# views, same mountains, like it was meant to be there". A bench 584 m up the
# mountain south of Pine Ridge (floor 35 m, peak 749 m), found by
# tools/_home_search.gd (open fan of view and climb-out off the cliff end,
# easy approach behind); region.gd molds the rest (the cliff, the approach,
# the spires calmed) and region_town.gd runs a dirt road up from town.
const REGION_CENTER := Vector2(-1200.0, 500.0)    # region metres
const REGION_ANGLE := PI * 292.0 / 180.0          # runway east (+x) points over the drop, at the town
const REGION_BENCH := true
const REGION_NEAR := Rect2(-2900.0, -1300.0, 4100.0, 2650.0)
var region: Node3D


func _build_region() -> void:
	if Game.outback() or OS.get_cmdline_user_args().has("noregion=1"):
		return
	var t0 := Time.get_ticks_msec()
	var RS = load("res://scripts/region.gd")
	RS.game = {"center": REGION_CENTER, "angle": REGION_ANGLE, "half": GroundScript.SQ, "near": REGION_NEAR, "bench": REGION_BENCH}
	region = RS.new()
	region.name = "Region"
	add_child(region)
	var lv := float(RS.game.get("level", 0.0))
	var dy := lv - GroundScript.PLAIN_Y
	var b := Basis(Vector3.UP, REGION_ANGLE)
	var c3 := Vector3(REGION_CENTER.x, 0.0, REGION_CENTER.y)
	region.transform = Transform3D(b, -(b * c3) - Vector3(0, dy, 0))
	GroundScript.region = region
	GroundScript.region_xf = Transform3D(b.inverse(), c3)
	GroundScript.region_dy = dy
	# Pine Ridge's airstrip, as one of the game's strips (lights, landing, the map)
	var TS = load("res://scripts/region_town.gd")
	var ga: Vector3 = region.transform * Vector3(TS.STRIP_A.x, 0, TS.STRIP_A.y)
	var gb: Vector3 = region.transform * Vector3(TS.STRIP_B.x, 0, TS.STRIP_B.y)
	var mid := (ga + gb) * 0.5
	mid.y = terrain.height_at(mid.x, mid.z)
	var d := gb - ga
	var hdg := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
	terrain._add_strip("Pine Ridge", mid, hdg, Vector2(d.x, d.z).length(), 24.0, 1, 2, true,
		"Gravel strip at Pine Ridge: the town's airport, fuel and the hangar.")
	terrain.strips[terrain.strips.size() - 1]["region"] = true
	print("region: %d ms, lowered %.1f m, Pine Ridge strip at %s heading %d" % [Time.get_ticks_msec() - t0, dy, str(mid.round()), int(hdg)])
	_track_to_road()
	_cliff_strip(RS)


## Where the mountain road comes onto the airport's square: a track cut
## through the claim's trees from there to the apron (round the knoll's
## north side, clear of the mud bog), so a truck drives straight in.
var road_end := Vector3.INF

func _track_to_road() -> void:
	var town = region.get("town")
	if town == null or town.mountain_road.size() < 2:
		return
	var e: Vector3 = region.transform * town.mountain_road[town.mountain_road.size() - 1]
	road_end = e
	var pts: Array = [Vector2(e.x, e.z)]
	# into the square, then the waypoints (claim layout: knoll (-50, 50),
	# bog (-108, -44), apron (-25, -94))
	var inside := Vector2(clampf(e.x, -165.0, 165.0), clampf(e.z, -165.0, 165.0))
	pts.append(inside)
	for w in [Vector2(-150.0, 110.0), Vector2(-140.0, 30.0), Vector2(-88.0, -18.0), Vector2(-45.0, -75.0)]:
		if (pts[pts.size() - 1] as Vector2).distance_to(w) > 20.0:
			pts.append(w)
	# rounded off a little (the corners cut), drawn as gravel on the claim
	var sm: Array = pts.duplicate()
	for it in range(2):
		var o: Array = [sm[0]]
		for i in range(sm.size() - 1):
			o.append((sm[i] as Vector2).lerp(sm[i + 1], 0.25))
			o.append((sm[i] as Vector2).lerp(sm[i + 1], 0.75))
		o.append(sm[sm.size() - 1])
		sm = o
	terrain.track = PackedVector2Array(sm)
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(int(a.distance_to(b) / 8.0), 1)
		for k in range(n + 1):
			var q := a.lerp(b, float(k) / n)
			terrain.clearings.append(Vector3(q.x, q.y, 5.0))
	print("region: track from the road at %s to the apron" % str(e.round()))


## Eagle Rock: the strip on the mountain shelf that ends at the cliff
## (region.gd plans and levels it). A game strip (landing, the map), a
## gravel runway laid on the shelf, the windsock, a shed and two fuel drums,
## orange markers along the edges and a row across the end at the drop.
func _cliff_strip(RS) -> void:
	if not RS.game.has("cliff"):
		return
	var cs: Dictionary = RS.game["cliff"]
	var lvl: float = cs["level"]
	var a: Vector3 = region.transform * Vector3((cs["a"] as Vector2).x, lvl, (cs["a"] as Vector2).y)
	var b: Vector3 = region.transform * Vector3((cs["b"] as Vector2).x, lvl, (cs["b"] as Vector2).y)
	var d := b - a
	var L := Vector2(d.x, d.z).length()
	var mid := (a + b) * 0.5
	var hdg := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
	terrain._add_strip("Eagle Rock", mid, hdg, L, 24.0, 1, 4, false,
		"A shelf on the mountain over the home valley: 300 m of gravel that ends at a sheer drop. Take off toward the edge - have your speed, or you go over it.")
	terrain.strips[terrain.strips.size() - 1]["region"] = true
	var fwd := Vector3(d.x, 0, d.z).normalized()
	var side := Vector3(-fwd.z, 0, fwd.x)
	var yaw := atan2(-fwd.x, -fwd.z)
	# the gravel
	var kit := MeshKit.new()
	var hw: float = RS.CLIFF_HW - 2.0
	var n := 30
	for i in range(n):
		var p0 := a + d * (float(i) / n)
		var p1 := a + d * (float(i + 1) / n)
		p0.y = lvl - GroundScript.region_dy + 0.06
		p1.y = p0.y
		kit.quad(p0 - side * hw, p1 - side * hw, p1 + side * hw, p0 + side * hw, Color(0.47, 0.44, 0.40), Vector3.UP)
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://scripts/tex.gd")._load("res://textures/ph/gravel_floor/gravel_floor_diff_2k.jpg")
	gm.uv1_triplanar = true
	gm.uv1_world_triplanar = true
	gm.uv1_scale = Vector3(0.4, 0.4, 0.4)
	gm.vertex_color_use_as_albedo = true
	gm.roughness = 0.95
	var gmi := kit.instance("EagleRockGravel")
	gmi.material_override = gm
	add_child(gmi)
	# markers along both edges and a row of them across the end at the drop
	var mk := MeshKit.new()
	var orange := Color(0.95, 0.42, 0.08)
	var ground_y := lvl - GroundScript.region_dy
	for i in range(7):
		for sd in [-1.0, 1.0]:
			var q: Vector3 = a + d * (float(i) / 6.0) + side * float(sd) * (hw + 2.5)
			mk.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, ground_y + 0.3, q.z)), Vector3(0.5, 0.6, 0.5), orange)
	for j in range(-3, 4):
		var q2 := b - fwd * 2.0 + side * (float(j) * hw / 3.0)
		mk.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(q2.x, ground_y + 0.25, q2.z)), Vector3(1.4, 0.5, 0.35), Color(0.92, 0.92, 0.88))
	add_child(mk.instance("EagleRockMarkers"))
	# the windsock, a shed and the drums at the uphill (landing) end
	var AL = load("res://scripts/assets/asset_lib.gd")
	var sock: Node3D = AL.get_asset("town_props:1")
	sock.position = a + fwd * 40.0 + side * (hw + 14.0)
	sock.position.y = terrain.height_at(sock.position.x, sock.position.z)
	add_child(sock)
	var shed: Node3D = AL.get_asset("pole_barn")
	shed.position = a + fwd * 25.0 - side * (hw + 16.0)
	shed.position.y = terrain.height_at(shed.position.x, shed.position.z)
	shed.rotation.y = yaw + PI * 0.5
	add_child(shed)
	terrain.add_solid(Transform3D(Basis(Vector3.UP, shed.rotation.y), shed.position + Vector3(0, 3.0, 0)), Vector3(9.2, 6.0, 12.3))
	print("Eagle Rock: %s, %.0f m long, heading %d, %.0f m up" % [str(mid.round()), L, int(hdg), ground_y])


## A point in region metres -> game metres (landmarks, for the map and the HUD).
func region_to_game(p: Vector3) -> Vector3:
	return region.transform * p if region != null else p


# ------------------------------------------------------------------------------
#  Water
# ------------------------------------------------------------------------------
func _build_water() -> void:
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = WATER_SHADER
	waves = WavesScript.new()
	waves.name = "Waves"
	waves.materials.append(_water_mat)
	add_child(waves)
	# Near the camera the water is real geometry with waves in it.
	_patch_mat = ShaderMaterial.new()
	_patch_mat.shader = WATER_SHADER
	_patch_mat.set_shader_parameter("displace", true)
	_patch_mat.set_shader_parameter("patch_r", PATCH_R)
	waves.materials.append(_patch_mat)
	var pm2 := PlaneMesh.new()
	pm2.size = Vector2(PATCH_R * 2.0, PATCH_R * 2.0)
	pm2.subdivide_width = 143
	pm2.subdivide_depth = 143
	_patch = MeshInstance3D.new()
	_patch.name = "WaterNear"
	_patch.mesh = pm2
	_patch.material_override = _patch_mat
	_patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_patch.extra_cull_margin = 4.0
	_patch.visible = false
	_patch.set_meta("off", true)        # BP2: ponds carry their own waves
	add_child(_patch)
	_ice_mat = StandardMaterial3D.new()
	_ice_mat.albedo_color = Color(0.80, 0.88, 0.93)
	_ice_mat.roughness = 0.35
	_ice_mat.metallic_specular = 0.6

	for lake in terrain.lakes:
		var c: Vector2 = lake["pos"]
		var w := GerstnerWater.new()
		w.name = String(lake["name"])
		add_child(w)
		w.setup(Vector3(c.x, 0, c.y), float(lake["radius"]) + 4.0, float(lake["level"]), 0.3)
		ponds.append(w)
		for ch in w.get_children():
			if ch is MeshInstance3D:
				_lake_nodes.append(ch)


# ------------------------------------------------------------------------------
#  Trees
# ------------------------------------------------------------------------------
func _conifer_mesh() -> ArrayMesh:
	var kit := MeshKit.new()
	var leaf_dark := Color(1.0, 0.25, 0.0)
	var leaf_light := Color(1.0, 0.75, 0.0)
	var bark := Color(0.0, 0.5, 0.0)
	kit.cylinder(Transform3D.IDENTITY, 0.035, 0.03, 0.2, 4, bark, false)
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.13, 0)), 0.22, 0.0, 0.50, 6, leaf_dark, true)
	kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.42, 0)), 0.16, 0.0, 0.58, 6, leaf_light, true)
	return kit.commit()


func _make_birch_mesh(bare: bool) -> ArrayMesh:
	var kit := MeshKit.new()
	var bark := Color(0.0, 1.0, 0.0)
	kit.cylinder(Transform3D.IDENTITY, 0.03, 0.02, 0.62, 4, bark, false)
	if bare:
		for a in [0.3, 2.4, 4.4]:
			var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.75)
			kit.cylinder(Transform3D(b, Vector3(0, 0.45, 0)), 0.012, 0.004, 0.42, 3, bark, false)
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), 0.02, 0.004, 0.4, 3, bark, false)
	else:
		var rings: Array = []
		var profile := [[0.38, 0.10], [0.52, 0.24], [0.74, 0.26], [0.92, 0.15], [1.0, 0.02]]
		for pr in profile:
			var ring := PackedVector3Array()
			for i in range(6):
				var ang := TAU * float(i) / 6.0
				ring.append(Vector3(cos(ang) * pr[1], pr[0], sin(ang) * pr[1]))
			rings.append(ring)
		kit.loft(rings, Color(1.0, 0.55, 0.0), true, true)
	return kit.commit()


## Knock a tree over: it falls away from `push` and stops being an obstacle.
## Runways painted on the ground by the terrain shader (16 at most).
func paint_strips() -> void:
	var sa: Array[Vector4] = []
	var sb: Array[Vector4] = []
	for s in terrain.strips:
		if sa.size() >= 16:
			break
		var p: Vector3 = s["pos"]
		var d: Vector2 = s["dir"]
		sa.append(Vector4(p.x, p.z, d.x, d.y))
		sb.append(Vector4(s["length"] * 0.5, s["width"] * 0.5, float(s["surface"]), 1.0 if bool(s.get("player", false)) else 0.0))
	var count := sa.size()
	while sa.size() < 16:
		sa.append(Vector4.ZERO)
		sb.append(Vector4.ZERO)
	_terrain_mat.set_shader_parameter("strip_count", count)
	_terrain_mat.set_shader_parameter("strip_a", sa)
	_terrain_mat.set_shader_parameter("strip_b", sb)


## Cut the dug tiles out of the island's ground (they draw their own): a
## mask texture with one texel per 24 m tile, so there's no limit on how many.
var _dig_img: Image
var _dig_tex: ImageTexture
var _dig_origin := Vector2.ZERO


func paint_digs() -> void:
	return       # BP2: the whole ground deforms; no dig tiles to cut out
	const CELL := 24.0
	if _dig_img == null:
		var n := int(ceil(terrain.half * 2.0 / CELL)) + 4
		_dig_origin = Vector2(floor(-terrain.half / CELL) - 2.0, floor(-terrain.half / CELL) - 2.0) * CELL
		_dig_img = Image.create(n, n, false, Image.FORMAT_R8)
		_dig_tex = ImageTexture.create_from_image(_dig_img)
		_terrain_mat.set_shader_parameter("dig_mask", _dig_tex)
		_terrain_mat.set_shader_parameter("dig_origin", _dig_origin)
		_terrain_mat.set_shader_parameter("dig_cell", CELL)
	for d in terrain.digs:
		var t := Vector2i(int(floor((d.x0 + 1.0 - _dig_origin.x) / CELL)), int(floor((d.z0 + 1.0 - _dig_origin.y) / CELL)))
		if t.x >= 0 and t.y >= 0 and t.x < _dig_img.get_width() and t.y < _dig_img.get_height():
			_dig_img.set_pixel(t.x, t.y, Color(1, 0, 0))
	_dig_tex.update(_dig_img)
	_terrain_mat.set_shader_parameter("dig_on", 1 if not terrain.digs.is_empty() else 0)


func fell_tree(ti: int, tj: int, push: Vector3) -> void:
	if vegetation != null:
		vegetation.fell(ti, tj, push)
	else:
		Flora.felled[Flora.key(ti, tj)] = push
	_save_felled()


## Trees that are down (cut, or knocked over) stay down between sessions.
const FELLED_SAVE := "user://world.cfg"


func _save_felled() -> void:
	var cf := ConfigFile.new()
	cf.set_value("world", "felled", Flora.felled)
	cf.save(FELLED_SAVE)


func _load_felled() -> void:
	var cf := ConfigFile.new()
	# Flora.felled is static, so it outlives a scene reload: start from nothing,
	# or a new game would bring back the last game's stumps and burnt trunks
	Flora.felled = {}
	Flora._near_cache = {}
	if cf.load(FELLED_SAVE) != OK:
		return
	var f = cf.get_value("world", "felled", {})
	if f is Dictionary:
		Flora.felled = f


func _make_multimesh(mesh: Mesh, xfs: Array[Transform3D], tints: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in range(xfs.size()):
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, Color.WHITE)
		mm.set_instance_custom_data(i, tints[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.visibility_range_end = 5200.0
	return node


# ------------------------------------------------------------------------------
#  Airstrip furniture
# ------------------------------------------------------------------------------
func _strip_xf(k: int, along: float, across: float, yaw_offset: float = 0.0) -> Transform3D:
	var s: Dictionary = terrain.strips[k]
	var p: Vector3 = terrain.strip_point(k, along, across)
	p.y = terrain.height_at(p.x, p.z)
	var yaw := -deg_to_rad(float(s["heading"])) + yaw_offset
	return Transform3D(Basis(Vector3.UP, yaw), p)


func _house(kit: RefCounted, xf: Transform3D, size: Vector3, wall: Color, roof: Color) -> void:
	if terrain.has_method("pad") and size.y > 0.5:
		terrain.pad(xf, size.x, size.z, 1.0)
	terrain.clear_spot(xf.origin.x, xf.origin.z, Vector2(size.x, size.z).length() * 0.5 + 3.0)
	terrain.add_solid(xf, Vector3(size.x + 0.9, size.y + size.x * 0.22, size.z + 0.8))
	# Walls, sunk a little so sloping ground does not leave a gap.
	kit.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5 - 0.6, 0)), Vector3(size.x, size.y + 1.2, size.z), wall)
	# Pitched roof with the ridge along the building's length (local Z), with
	# eaves that overhang and a fascia board edge.
	var hx := size.x * 0.5 + 0.45
	var hz := size.z * 0.5 + 0.40
	var y0 := size.y - 0.08
	var y1 := size.y + size.x * 0.32
	var a := xf * Vector3(-hx, y0, -hz)
	var b := xf * Vector3(hx, y0, -hz)
	var c := xf * Vector3(hx, y0, hz)
	var d := xf * Vector3(-hx, y0, hz)
	var r0 := xf * Vector3(0, y1, -hz)
	var r1 := xf * Vector3(0, y1, hz)
	kit.quad(a, r0, r1, d, roof, xf.basis * Vector3(-1, 1, 0))
	kit.quad(b, r0, r1, c, roof, xf.basis * Vector3(1, 1, 0))
	# Underside of the eaves and the thickness of the roof edge.
	var t := Vector3(0, -0.12, 0)
	kit.quad(a, d, d + xf.basis * t, a + xf.basis * t, roof.darkened(0.35), xf.basis * Vector3(-1, 0, 0))
	kit.quad(b, c, c + xf.basis * t, b + xf.basis * t, roof.darkened(0.35), xf.basis * Vector3(1, 0, 0))
	var gx := size.x * 0.5
	var ga := xf * Vector3(-gx, size.y, -size.z * 0.5)
	var gb := xf * Vector3(gx, size.y, -size.z * 0.5)
	var gc := xf * Vector3(gx, size.y, size.z * 0.5)
	var gd := xf * Vector3(-gx, size.y, size.z * 0.5)
	kit.tri(ga, gb, xf * Vector3(0, size.y + gx * 0.64, -size.z * 0.5), wall, xf.basis * Vector3(0, 0, -1))
	kit.tri(gd, gc, xf * Vector3(0, size.y + gx * 0.64, size.z * 0.5), wall, xf.basis * Vector3(0, 0, 1))
	if size.y < 1.0:
		return            # a tent: no windows
	var trim := Color(0.90, 0.89, 0.84) if wall.get_luminance() < 0.55 else Color(0.30, 0.24, 0.18)
	var glass := Color(0.10, 0.13, 0.16)
	var logs := wall.r < 0.45 and wall.r > wall.b + 0.1 and wall.g < 0.32
	# Log walls: a dark line between each course of logs.
	if logs:
		var y := 0.28
		while y < size.y - 0.1:
			for sx in [-1.0, 1.0]:
				kit.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx * (size.x * 0.5 + 0.01), y, 0)), Vector3(0.02, 0.035, size.z + 0.1), wall.darkened(0.45))
			for sz in [-1.0, 1.0]:
				kit.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, y, sz * (size.z * 0.5 + 0.01))), Vector3(size.x + 0.1, 0.035, 0.02), wall.darkened(0.45))
			y += 0.3
		# Log ends sticking out at the corners.
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				kit.box(xf * Transform3D(Basis.IDENTITY, Vector3(cx * size.x * 0.5, size.y * 0.5, cz * size.z * 0.5)), Vector3(0.36, size.y, 0.36), wall.darkened(0.15))
	else:
		# Corner boards.
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				kit.box(xf * Transform3D(Basis.IDENTITY, Vector3(cx * size.x * 0.5, size.y * 0.5, cz * size.z * 0.5)), Vector3(0.16, size.y, 0.16), trim)
	# Windows down both long sides, framed.
	var n := maxi(1, int(size.z / 3.2))
	var wy := minf(1.55, size.y * 0.55)
	for sx in [-1.0, 1.0]:
		for i in range(n):
			var z := -size.z * 0.5 + size.z * (float(i) + 0.5) / float(n)
			if sx < 0.0 and i == n / 2 and n > 1:
				continue          # the door goes here on one side
			var wxf := xf * Transform3D(Basis.IDENTITY, Vector3(sx * (size.x * 0.5 + 0.02), wy, z))
			kit.box(wxf, Vector3(0.04, 1.0, 0.86), trim)
			kit.box(wxf * Transform3D(Basis.IDENTITY, Vector3(sx * 0.01, 0, 0)), Vector3(0.04, 0.84, 0.70), glass)
			kit.box(wxf * Transform3D(Basis.IDENTITY, Vector3(sx * 0.02, 0, 0)), Vector3(0.04, 0.84, 0.05), trim)
			kit.box(wxf * Transform3D(Basis.IDENTITY, Vector3(sx * 0.02, 0, 0)), Vector3(0.04, 0.05, 0.70), trim)
	# The door: on the long side (or the gable end of a small cabin), with a step.
	var dxf: Transform3D
	if n > 1:
		dxf = xf * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-(size.x * 0.5 + 0.03), 0.0, -size.z * 0.5 + size.z * (float(n / 2) + 0.5) / float(n)))
	else:
		dxf = xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -(size.z * 0.5 + 0.03)))
	kit.box(dxf * Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)), Vector3(1.06, 2.08, 0.06), trim)
	kit.box(dxf * Transform3D(Basis.IDENTITY, Vector3(0, 0.98, -0.02)), Vector3(0.9, 1.96, 0.06), Color(0.33, 0.20, 0.12) if not logs else Color(0.22, 0.14, 0.08))
	kit.box(dxf * Transform3D(Basis.IDENTITY, Vector3(0.33, 0.98, -0.06)), Vector3(0.06, 0.06, 0.04), Color(0.75, 0.70, 0.55))
	kit.box(dxf * Transform3D(Basis.IDENTITY, Vector3(0, 0.08, -0.35)), Vector3(1.4, 0.16, 0.7), Color(0.42, 0.35, 0.27))
	# A stovepipe through the roof.
	var cx2 := size.x * 0.22
	kit.cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(cx2, size.y + cx2 * 0.64 * 0.5, size.z * 0.25)), 0.11, 0.11, size.x * 0.32 + 0.9, 8, Color(0.12, 0.12, 0.12), true)


## A hangar: a steel shed with big sliding doors (panels, a track along the
## top, a small door for people in one leaf), ribbed walls and a window strip.
## A steel hangar you can walk and taxi into: walls on three sides, the big
## sliding doors run back to either side of the front, a level concrete floor,
## and a workshop along the back wall (bench, tool chest, parts shelves, oil
## drums, an engine hoist) under hanging lights.
var _hangar_lights: Array = []       # {switch, lamps, fixtures}: handed to building_lights.gd
var workbench := Vector3.INF          # the home hangar's workbench (crafting.gd uses it)
var workbench_yaw := 0.0
var hangar_doors: Array = []         # [bifold_door node, switch position] - home hangar (builds.gd adds its own)


static func _rod_w(kit: RefCounted, a: Vector3, b: Vector3) -> void:
	kit.box(Transform3D(Basis.IDENTITY, (a + b) * 0.5), Vector3(0.01, a.distance_to(b), 0.01), Color(0.2, 0.2, 0.2))


## The home hangar: white steel, Alaska bush style, bifold door (building_models.gd).
const HANGAR_PALETTE := {"wall": Color(0.92, 0.92, 0.89), "wainscot": Color(0.20, 0.34, 0.24),
	"trim": Color(0.95, 0.95, 0.93), "roof": Color(0.66, 0.68, 0.69)}

func _bush_hangar(xf: Transform3D, size: Vector3) -> void:
	if terrain.has_method("pad"):
		terrain.pad(xf, size.x, size.z, 1.5)
	terrain.clear_spot(xf.origin.x, xf.origin.z, Vector2(size.x, size.z).length() * 0.5 + 4.0)
	var door_w := size.x - 2.0
	terrain.add_hollow(xf, size, door_w)
	var kit := MeshKit.new()
	var info: Dictionary = BuildingModels.bush_hangar(kit, size.x, size.z, size.y, door_w, 5.6, HANGAR_PALETTE)
	var mi := kit.instance("BushHangar")
	mi.transform = xf
	add_child(mi)
	for so in info["solids"]:
		terrain.add_solid(xf * Transform3D(Basis.IDENTITY, so[0] as Vector3), so[1])
	for pf in info["platforms"]:
		terrain.add_platform(xf * Transform3D(Basis.IDENTITY, pf[0] as Vector3), pf[1], float(pf[2]), float(pf[3]))
	# the bifold door that opens and shuts (DESIGN_NOTES 78)
	var door: Node3D = load("res://scripts/bifold_door.gd").new()
	door.door_w = door_w
	door.door_h = 5.6
	door.hz = size.z * 0.5
	door.hollow = terrain.hollows[terrain.hollows.size() - 1]
	mi.add_child(door)
	door.build(HANGAR_PALETTE["wall"], HANGAR_PALETTE["trim"])
	hangar_doors.append([door, xf * (info["door_switch"] as Vector3)])
	var fx: Array = []
	for f in info["fixtures"]:
		fx.append([xf * (f[0] as Transform3D), f[1]])
	var lamps: Array = []
	for lp in info["lamps"]:
		lamps.append(xf * (lp as Vector3))
	_hangar_lights.append({"switch": xf * (info["switch"] as Vector3), "lamps": lamps, "fixtures": fx})
	if workbench == Vector3.INF and info.has("bench"):
		workbench = xf * (info["bench"] as Vector3)     # the home hangar's bench is the crafting bench
		workbench_yaw = atan2(-xf.basis.z.x, -xf.basis.z.z)


func _hangar(kit: RefCounted, xf: Transform3D, size: Vector3, wall: Color) -> void:
	if terrain.has_method("pad"):
		terrain.pad(xf, size.x, size.z, 1.5)
	terrain.clear_spot(xf.origin.x, xf.origin.z, Vector2(size.x, size.z).length() * 0.5 + 3.0)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var dw := size.x * 0.84
	var dh := size.y * 0.86
	terrain.add_hollow(xf, size, dw)
	var t := 0.15
	var inside := Color(0.62, 0.63, 0.62)
	var B := func(c: Vector3, sz: Vector3, col: Color) -> void:
		kit.box(xf * Transform3D(Basis.IDENTITY, c), sz, col)
	# Concrete floor slab (sunk into the slope), with a ramp lip at the door.
	B.call(Vector3(0, -0.35, 0), Vector3(size.x, 0.82, size.z), Color(0.55, 0.55, 0.53))
	B.call(Vector3(0, -0.35, -hz - 1.0), Vector3(dw, 0.80, 2.0), Color(0.50, 0.50, 0.48))
	# Walls: back, sides, the front either side of the door and above it.
	# Each is a box (both faces), outside in the tin colour.
	B.call(Vector3(0, size.y * 0.5, hz), Vector3(size.x, size.y, t), wall)
	for sx in [-1.0, 1.0]:
		B.call(Vector3(sx * hx, size.y * 0.5, 0), Vector3(t, size.y, size.z), wall)
		B.call(Vector3(sx * (hx + dw * 0.5) * 0.5, size.y * 0.5, -hz), Vector3(hx - dw * 0.5, size.y, t), wall)
	B.call(Vector3(0, (dh + size.y) * 0.5, -hz), Vector3(dw, size.y - dh, t), wall)
	# Inside lining a shade lighter, just in from the walls.
	B.call(Vector3(0, size.y * 0.5, hz - t), Vector3(size.x - 0.4, size.y, 0.02), inside)
	for sx in [-1.0, 1.0]:
		B.call(Vector3(sx * (hx - t), size.y * 0.5, 0), Vector3(0.02, size.y, size.z - 0.4), inside)
	# Low-pitched roof, and its underside.
	var rx := hx + 0.3
	var rz := hz + 0.3
	var y0 := size.y
	var y1 := size.y + size.x * 0.12
	var roofc: Color = wall.darkened(0.2)
	kit.quad(xf * Vector3(-rx, y0, -rz), xf * Vector3(0, y1, -rz), xf * Vector3(0, y1, rz), xf * Vector3(-rx, y0, rz), roofc, xf.basis * Vector3(-1, 1, 0))
	kit.quad(xf * Vector3(rx, y0, -rz), xf * Vector3(0, y1, -rz), xf * Vector3(0, y1, rz), xf * Vector3(rx, y0, rz), roofc, xf.basis * Vector3(1, 1, 0))
	kit.quad(xf * Vector3(-hx, y0 - 0.02, -hz), xf * Vector3(0, y1 - 0.02, -hz), xf * Vector3(0, y1 - 0.02, hz), xf * Vector3(-hx, y0 - 0.02, hz), inside.darkened(0.2), xf.basis * Vector3(1, -1, 0))
	kit.quad(xf * Vector3(hx, y0 - 0.02, -hz), xf * Vector3(0, y1 - 0.02, -hz), xf * Vector3(0, y1 - 0.02, hz), xf * Vector3(hx, y0 - 0.02, hz), inside.darkened(0.2), xf.basis * Vector3(-1, -1, 0))
	for sz in [-1.0, 1.0]:
		kit.tri(xf * Vector3(-hx, y0, sz * hz), xf * Vector3(hx, y0, sz * hz), xf * Vector3(0, y1, sz * hz), wall, xf.basis * Vector3(0, 0, sz))
		kit.tri(xf * Vector3(-hx, y0, sz * (hz - 0.05)), xf * Vector3(hx, y0, sz * (hz - 0.05)), xf * Vector3(0, y1, sz * (hz - 0.05)), inside, xf.basis * Vector3(0, 0, -sz))
	# Roof trusses across.
	var trusses := int(size.z / 4.0)
	for i in range(trusses + 1):
		var tz := -hz + size.z * float(i) / float(trusses)
		B.call(Vector3(0, y0 - 0.1, tz), Vector3(size.x - 0.3, 0.12, 0.12), Color(0.35, 0.35, 0.36))
		B.call(Vector3(0, (y0 + y1) * 0.5, tz), Vector3(0.1, y1 - y0, 0.1), Color(0.35, 0.35, 0.36))
	# Ribs on the long walls, outside.
	var ribs := int(size.z / 0.9)
	for i in range(ribs + 1):
		var z := -hz + size.z * float(i) / float(ribs)
		for sx in [-1.0, 1.0]:
			B.call(Vector3(sx * (hx + 0.09), size.y * 0.5, z), Vector3(0.04, size.y, 0.06), wall.darkened(0.12))
	# Window strip high on each long wall (both faces).
	for sx in [-1.0, 1.0]:
		B.call(Vector3(sx * (hx + 0.1), size.y - 1.0, 0), Vector3(0.04, 0.6, size.z * 0.7), Color(0.12, 0.15, 0.18))
		B.call(Vector3(sx * (hx - t - 0.03), size.y - 1.0, 0), Vector3(0.02, 0.6, size.z * 0.7), Color(0.75, 0.82, 0.88))
	# Door track, and the sliding leaves pushed open, stacked at each side.
	var fz := -hz - 0.12
	B.call(Vector3(0, dh + 0.12, fz - 0.05), Vector3(size.x + 0.4, 0.22, 0.18), wall.darkened(0.4))
	var lw := dw / 4.0
	for sx in [-1.0, 1.0]:
		for i in range(2):
			var lx: float = sx * (hx - lw * 0.5 - 0.1)
			var lc: Color = wall.lightened(0.04) if i == 0 else wall.darkened(0.04)
			B.call(Vector3(lx, dh * 0.5, fz - 0.08 * float(i)), Vector3(lw - 0.04, dh, 0.06), lc)
			for k in range(1, 4):
				B.call(Vector3(lx, dh * float(k) / 4.0, fz - 0.08 * float(i) - 0.04), Vector3(lw - 0.1, 0.05, 0.02), wall.darkened(0.25))
	# Name board over the doors.
	B.call(Vector3(0, dh + 0.7, fz - 0.03), Vector3(size.x * 0.4, 0.8, 0.05), Color(0.90, 0.88, 0.82))
	# --- the workshop along the back wall ---------------------------------------
	var bz := hz - 0.8
	var wood := Color(0.45, 0.32, 0.20)
	var red := Color(0.72, 0.10, 0.08)
	# Workbench with a vice and a pegboard of tools.
	B.call(Vector3(-4.0, 0.92, bz), Vector3(3.2, 0.08, 0.8), wood)
	for lx in [-5.5, -2.5]:
		for lz in [bz - 0.35, bz + 0.35]:
			B.call(Vector3(lx, 0.46, lz), Vector3(0.08, 0.92, 0.08), Color(0.3, 0.3, 0.3))
	B.call(Vector3(-4.0, 0.3, bz), Vector3(3.0, 0.04, 0.7), wood.darkened(0.2))
	B.call(Vector3(-3.0, 1.03, bz - 0.25), Vector3(0.18, 0.14, 0.2), Color(0.2, 0.3, 0.5))
	B.call(Vector3(-4.0, 1.8, hz - t - 0.04), Vector3(3.0, 1.2, 0.03), Color(0.62, 0.50, 0.34))
	for i in range(9):
		var tx := -5.2 + 0.3 * float(i)
		B.call(Vector3(tx, 1.8 + 0.25 * sin(float(i) * 1.7), hz - t - 0.08), Vector3(0.04, 0.32, 0.03), Color(0.25, 0.25, 0.27))
	# Rolling red tool chest.
	B.call(Vector3(-1.4, 0.55, bz), Vector3(1.1, 1.0, 0.55), red)
	for d in range(5):
		B.call(Vector3(-1.4, 0.2 + 0.18 * float(d), bz - 0.29), Vector3(1.0, 0.02, 0.02), Color(0.75, 0.75, 0.75))
	# Parts shelves: boxes and oil cans.
	for sy in [0.4, 1.1, 1.8]:
		B.call(Vector3(2.5, sy, bz), Vector3(2.4, 0.04, 0.6), Color(0.35, 0.36, 0.38))
		for i in range(7):
			var px := 1.5 + 0.32 * float(i)
			var pc: Color = [Color(0.85, 0.65, 0.15), Color(0.6, 0.1, 0.1), Color(0.75, 0.70, 0.55), Color(0.2, 0.35, 0.6)][(i + int(sy * 3.0)) % 4]
			B.call(Vector3(px, sy + 0.14, bz), Vector3(0.22, 0.24, 0.3), pc)
	for sx in [1.3, 3.7]:
		B.call(Vector3(sx, 1.0, bz), Vector3(0.05, 2.0, 0.6), Color(0.35, 0.36, 0.38))
	# Oil drums and an engine hoist.
	for i in range(3):
		kit.cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(5.0 + 0.62 * float(i), 0.06, bz)), 0.29, 0.29, 0.88, 10, [Color(0.15, 0.3, 0.6), red, Color(0.15, 0.3, 0.6)][i])
	var hoist := Color(0.85, 0.65, 0.10)
	B.call(Vector3(-hx + 2.5, 0.12, 1.0), Vector3(0.12, 0.12, 1.6), hoist)
	B.call(Vector3(-hx + 2.5, 1.1, 0.4), Vector3(0.12, 2.0, 0.12), hoist)
	kit.box(xf * Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(-hx + 2.5, 2.0, 0.9)), Vector3(0.1, 0.1, 1.6), hoist)
	# Hanging lights (tubes in reflectors), on a switch inside by the door.
	var fixtures: Array = []
	for lz in [-hz * 0.5, hz * 0.4]:
		for lx in [-hx * 0.45, hx * 0.45]:
			B.call(Vector3(lx, y0 - 0.56, lz), Vector3(1.5, 0.05, 0.26), Color(0.3, 0.3, 0.32))
			B.call(Vector3(lx, y0 - 0.6, lz), Vector3(1.4, 0.04, 0.12), Color(0.85, 0.85, 0.82))
			fixtures.append([xf * Transform3D(Basis.IDENTITY, Vector3(lx, y0 - 0.625, lz)), Vector3(1.38, 0.02, 0.1)])
			_rod_w(kit, xf * Vector3(lx, y0 - 0.55, lz), xf * Vector3(lx, y0 - 0.1, lz))
	var sw := Vector3(-dw * 0.5 - 0.7, 1.35, -hz + t + 0.03)
	B.call(sw, Vector3(0.10, 0.14, 0.03), Color(0.75, 0.75, 0.72))
	B.call(sw + Vector3(0, 0.0, 0.025), Vector3(0.025, 0.05, 0.03), Color(0.2, 0.2, 0.2))
	B.call(sw + Vector3(0, 0.6, 0.0), Vector3(0.03, 1.2, 0.03), Color(0.4, 0.4, 0.42))
	_hangar_lights.append({"switch": xf * (sw + Vector3(0, 0, 0.1)), "lamps": [xf * Vector3(0, y0 - 0.9, -hz * 0.4), xf * Vector3(0, y0 - 0.9, hz * 0.5)], "fixtures": fixtures})

	# --- the place lived in ------------------------------------------------------
	# Pennant strings slung between the trusses: little coloured triangles.
	var pcols := [Color(0.80, 0.15, 0.12), Color(0.95, 0.75, 0.15), Color(0.15, 0.40, 0.70), Color(0.90, 0.88, 0.84), Color(0.20, 0.55, 0.30)]
	for row in range(2):
		var pz := -hz * 0.55 + float(row) * hz * 0.75
		var pa := xf * Vector3(-hx + 0.6, y0 - 0.25, pz)
		var pb := xf * Vector3(hx - 0.6, y0 - 0.25, pz + 1.5)
		var flags := int(size.x / 0.55)
		for i in range(flags):
			var u0 := (float(i) + 0.12) / float(flags)
			var u1 := (float(i) + 0.88) / float(flags)
			var top0: Vector3 = pa.lerp(pb, u0)
			var top1: Vector3 = pa.lerp(pb, u1)
			var sag: float = 0.35 * sin(PI * (u0 + u1) * 0.5)
			top0.y -= sag
			top1.y -= sag
			var tipp: Vector3 = (top0 + top1) * 0.5 - Vector3(0, 0.3, 0)
			var nrm2: Vector3 = xf.basis * Vector3(0, 0, -1)
			kit.tri(top0, top1, tipp, pcols[i % pcols.size()], nrm2)
			kit.tri(top1, top0, tipp, pcols[i % pcols.size()], -nrm2)
	# A big cloth banner on the back wall over the bench.
	B.call(Vector3(0.2, size.y - 1.15, bz + 0.72), Vector3(5.6, 1.15, 0.03), Color(0.78, 0.12, 0.10))
	B.call(Vector3(0.2, size.y - 1.15, bz + 0.70), Vector3(5.0, 0.72, 0.03), Color(0.92, 0.90, 0.85))
	for px2 in [-2.55, 2.95]:
		B.call(Vector3(0.2 + px2, size.y - 0.62, bz + 0.72), Vector3(0.05, 1.3, 0.05), Color(0.35, 0.28, 0.2))
	# Posters along the side walls, slightly skewed.
	var postc := [Color(0.85, 0.75, 0.45), Color(0.4, 0.55, 0.75), Color(0.75, 0.45, 0.35), Color(0.55, 0.65, 0.5)]
	for i in range(4):
		var wx: float = -1.0 if i % 2 == 0 else 1.0
		var pz2: float = -hz * 0.6 + float(i) * hz * 0.4
		kit.box(xf * Transform3D(Basis(Vector3.UP, 0.0) * Basis(Vector3.BACK, 0.05 - 0.03 * float(i % 3)), Vector3(wx * (hx - t - 0.05), 1.9, pz2)), Vector3(0.015, 0.62, 0.45), postc[i])
		kit.box(xf * Transform3D(Basis(Vector3.BACK, 0.05 - 0.03 * float(i % 3)), Vector3(wx * (hx - t - 0.057), 2.06, pz2)), Vector3(0.012, 0.2, 0.36), postc[i].darkened(0.45))
	# A couple of carry toolboxes left about, lids and handles.
	for tb in [[Vector3(-2.2, 0.14, bz - 2.2), Color(0.70, 0.12, 0.10), 0.5], [Vector3(3.3, 0.14, bz - 3.6), Color(0.15, 0.35, 0.55), -0.9]]:
		var txf: Transform3D = xf * Transform3D(Basis(Vector3.UP, float(tb[2])), tb[0] as Vector3)
		kit.box(txf, Vector3(0.52, 0.22, 0.24), tb[1])
		kit.box(txf * Transform3D(Basis.IDENTITY, Vector3(0, 0.13, 0)), Vector3(0.52, 0.05, 0.24), (tb[1] as Color).darkened(0.2))
		kit.box(txf * Transform3D(Basis.IDENTITY, Vector3(0, 0.18, 0)), Vector3(0.16, 0.03, 0.03), Color(0.2, 0.2, 0.2))
	# A stack of worn tyres in the corner, and a spare prop on the wall.
	for i in range(4):
		kit.cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(hx - 1.0, 0.065 + 0.21 * float(i), hz - 1.2 - 0.04 * float(i))), 0.30 - 0.02 * float(i % 2), 0.30 - 0.02 * float(i % 2), 0.19, 10, Color(0.10, 0.10, 0.11))
	kit.box(xf * Transform3D(Basis(Vector3.BACK, 0.45), Vector3(hx - t - 0.10, 1.7, -hz * 0.35)), Vector3(0.05, 2.4, 0.16), Color(0.72, 0.45, 0.15))
	# Jerry cans by the drums, a broom on the wall, oil stains on the slab.
	for i in range(2):
		kit.box(xf * Transform3D(Basis(Vector3.UP, 0.4 * float(i)), Vector3(5.1 + 0.4 * float(i), 0.26, bz - 1.1)), Vector3(0.18, 0.44, 0.34), Color(0.25, 0.35, 0.2) if i == 0 else Color(0.6, 0.1, 0.1))
	kit.box(xf * Transform3D(Basis(Vector3.BACK, 0.12), Vector3(-hx + t + 0.10, 1.0, hz * 0.55)), Vector3(0.03, 1.6, 0.03), Color(0.55, 0.42, 0.25))
	kit.box(xf * Transform3D(Basis(Vector3.BACK, 0.12), Vector3(-hx + t + 0.10, 0.28, hz * 0.55)), Vector3(0.05, 0.22, 0.14), Color(0.45, 0.40, 0.3))
	for st2 in [[Vector3(-1.5, 0.062, -2.0), 0.7], [Vector3(2.0, 0.062, 1.5), 0.45], [Vector3(0.6, 0.062, bz - 2.8), 0.3]]:
		kit.cylinder(xf * Transform3D(Basis.IDENTITY, st2[0] as Vector3), float(st2[1]), float(st2[1]) * 0.8, 0.004, 9, Color(0.16, 0.15, 0.13))


## Edge and threshold lights along the kept-up strips (difficulty 1-2).
## Little glass beads that come alight at dusk (_apply_sun drives them);
## the bush strips stay dark, as they would.
func _runway_lights() -> void:
	_rwy_mats.clear()
	var holder := Node3D.new()
	holder.name = "RunwayLights"
	add_child(holder)
	var sets := [[Color(1.0, 0.95, 0.75), []], [Color(0.1, 1.0, 0.4), []]]
	for k in range(terrain.strips.size()):
		var st: Dictionary = terrain.strips[k]
		if int(st["difficulty"]) > 2:
			continue
		var hl := float(st["length"]) * 0.5
		var hw := float(st["width"]) * 0.5 + 2.0
		var n := int(floor((hl * 2.0 - 20.0) / 55.0))
		for i in range(n + 1):
			var along := -hl + 10.0 + (hl * 2.0 - 20.0) * float(i) / float(n)
			for side in [-1.0, 1.0]:
				var q: Vector3 = terrain.strip_point(k, along, hw * side)
				q.y = terrain.height_at(q.x, q.z) + 0.3
				(sets[0][1] as Array).append(q)
		for e in [-1.0, 1.0]:
			for i in range(4):
				var across := (-1.0 + 2.0 * float(i) / 3.0) * (hw - 2.0)
				var q2: Vector3 = terrain.strip_point(k, (hl + 3.0) * e, across)
				q2.y = terrain.height_at(q2.x, q2.z) + 0.3
				(sets[1][1] as Array).append(q2)
	runway_pts.clear()
	for cset in sets:
		for q in (cset[1] as Array):
			runway_pts.append([q, cset[0]])
	for cset in sets:
		var pts: Array = cset[1]
		if pts.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var sm := SphereMesh.new()
		sm.radius = 0.20
		sm.height = 0.40
		sm.radial_segments = 6
		sm.rings = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = (cset[0] as Color).darkened(0.5)
		mat.emission_enabled = true
		mat.emission = cset[0]
		mat.emission_energy_multiplier = 0.0
		sm.material = mat
		_rwy_mats.append(mat)
		mm.mesh = sm
		mm.instance_count = pts.size()
		for i in range(pts.size()):
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i]))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)


func _build_strip_objects() -> void:
	var kit := MeshKit.new()
	var lights := MeshKit.new()
	var orange := Color(0.95, 0.45, 0.08)
	var white := Color(0.92, 0.92, 0.88)
	for k in range(terrain.strips.size()):
		var s: Dictionary = terrain.strips[k]
		if bool(s.get("player", false)) or bool(s.get("region", false)):
			continue        # your own strips are marked by builds.gd; Pine Ridge's by its town
		var hl: float = s["length"] * 0.5
		var hw: float = s["width"] * 0.5
		# Edge markers and threshold boards
		var steps := int(s["length"] / 50.0)
		for i in range(steps + 1):
			var along: float = -hl + float(s["length"]) * float(i) / float(steps)
			for side in [-1.0, 1.0]:
				var xf := _strip_xf(k, along, side * (hw + 1.6))
				var at_end := i == 0 or i == steps
				var sz := Vector3(1.6, 1.1, 0.25) if at_end else Vector3(0.45, 0.55, 0.45)
				kit.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, sz.y * 0.5, 0)), sz, white if at_end else orange)
				# Edge lights at the strips with fuel (the towns): lit after dark.
				if bool(s["fuel"]):
					var lc := Color(1.0, 0.85, 0.55) if not at_end else Color(0.4, 1.0, 0.45)
					lights.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, sz.y + 0.08, 0)), Vector3(0.16, 0.16, 0.16), lc)
		_build_site(kit, k, hw)
		_build_apron(kit, k, hw)
		_add_windsock(k, hw)
	var mi: MeshInstance3D = kit.instance("StripObjects")
	add_child(mi)
	if not lights.is_empty():
		_runway_light_mat = StandardMaterial3D.new()
		_runway_light_mat.vertex_color_use_as_albedo = true
		_runway_light_mat.emission_enabled = true
		_runway_light_mat.emission = Color(1.0, 0.85, 0.6)
		_runway_light_mat.emission_energy_multiplier = 0.0
		var lm := lights.instance("RunwayLights")
		lm.material_override = _runway_light_mat
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lm)


func _build_site(kit: RefCounted, k: int, hw: float) -> void:
	var log_brown := Color(0.36, 0.25, 0.16)
	var tin := Color(0.55, 0.57, 0.58)
	var rust := Color(0.50, 0.28, 0.18)
	var red := Color(0.62, 0.16, 0.13)
	var green := Color(0.20, 0.36, 0.24)
	var blue := Color(0.20, 0.33, 0.52)
	var cream := Color(0.85, 0.80, 0.68)
	var white := Color(0.90, 0.90, 0.86)
	var off := hw + 48.0
	var roofs := [red, blue, green, rust, tin, blue, red, green, rust, blue, red, tin]
	match String(terrain.strips[k]["name"]):
		"Proving Ground":  # the home base: hangar, office, fuel tank, bunkhouse
			_bush_hangar(_strip_xf(k, -62.0, hw + 36.0, PI * 0.5), Vector3(22, 7.0, 18))
			_home_base(k, hw)
			kit.cylinder(_strip_xf(k, 34.0, hw + 40.0) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.6, -2.5)), 1.2, 1.2, 5.0, 8, white, true)
		"Bluff Camp":  # a cabin and a fuel cache
			_house(kit, _strip_xf(k, -70.0, off - 30.0, 0.2), Vector3(5, 2.8, 6.5), log_brown, rust)
			for i in range(4):
				kit.cylinder(_strip_xf(k, -52.0 + 1.1 * float(i), off - 34.0), 0.3, 0.3, 0.9, 6, red if i % 2 else blue, true)
		"Willow Bar":  # a trapper's shack
			_house(kit, _strip_xf(k, -50.0, off - 36.0, -0.3), Vector3(4.5, 2.6, 5.5), log_brown, tin)
		"Port Ashby":  # hangars, office, fuel tank and a scatter of houses
			_hangar(kit, _strip_xf(k, -120.0, off + 8.0, PI * 0.5), Vector3(24, 7.0, 20), tin)
			_house(kit, _strip_xf(k, -70.0, off + 4.0), Vector3(14, 5.0, 16), cream, green)
			_house(kit, _strip_xf(k, -30.0, off - 4.0), Vector3(6, 3.0, 8), red, tin)
			kit.cylinder(_strip_xf(k, 5.0, off - 6.0) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.8, -3.0)), 1.3, 1.3, 6.0, 8, white, true)
			for i in range(12):
				var ax := -260.0 + 55.0 * float(i % 6) + 20.0 * Terrain.hash01(i, 3, 21)
				var ac := off + 70.0 + 46.0 * float(i / 6) + 15.0 * Terrain.hash01(i, 5, 22)
				var yaw := 0.5 * (Terrain.hash01(i, 7, 23) - 0.5)
				_house(kit, _strip_xf(k, ax, ac, yaw), Vector3(7.0, 3.2, 9.0), cream if i % 3 else log_brown, roofs[i])
		"Tern Harbor":  # a small fishing village with a store and a fuel tank
			_house(kit, _strip_xf(k, -60.0, off + 6.0), Vector3(12, 4.5, 16), tin, blue)
			_hangar(kit, _strip_xf(k, 60.0, off + 6.0, PI * 0.5), Vector3(18, 6.0, 16), tin)
			_house(kit, _strip_xf(k, -20.0, off - 2.0), Vector3(6, 3.0, 8), white, red)
			kit.cylinder(_strip_xf(k, 12.0, off - 6.0) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.6, -2.5)), 1.1, 1.1, 5.0, 8, white, true)
			for i in range(8):
				var ax2 := -150.0 + 48.0 * float(i % 4) + 18.0 * Terrain.hash01(i, 3, 31)
				var ac2 := off + 62.0 + 42.0 * float(i / 4) + 12.0 * Terrain.hash01(i, 5, 32)
				var yaw2 := 0.6 * (Terrain.hash01(i, 7, 33) - 0.5)
				_house(kit, _strip_xf(k, ax2, ac2, yaw2), Vector3(6.5, 3.0, 8.0), white if i % 2 else cream, roofs[i + 2])
		"Salmon Bend":  # a shack and a drying rack
			_house(kit, _strip_xf(k, -60.0, off - 12.0), Vector3(4.5, 2.6, 5.5), log_brown, tin)
			var rack := _strip_xf(k, -45.0, off - 10.0)
			kit.box(rack * Transform3D(Basis.IDENTITY, Vector3(0, 1.9, 0)), Vector3(4.0, 0.15, 0.15), log_brown)
			kit.box(rack * Transform3D(Basis.IDENTITY, Vector3(-1.9, 0.95, 0)), Vector3(0.15, 1.9, 0.15), log_brown)
			kit.box(rack * Transform3D(Basis.IDENTITY, Vector3(1.9, 0.95, 0)), Vector3(0.15, 1.9, 0.15), log_brown)
		"Moose Lake Lodge":  # main lodge and cabins on the lake side
			_house(kit, _strip_xf(k, 20.0, -(off + 20.0), 0.3), Vector3(12, 5.0, 20), log_brown, green)
			_hangar(kit, _strip_xf(k, -110.0, off + 4.0, PI * 0.5), Vector3(18, 6.0, 16), tin)
			_house(kit, _strip_xf(k, 70.0, -(off + 34.0), -0.4), Vector3(5, 2.8, 6), log_brown, rust)
			_house(kit, _strip_xf(k, 100.0, -(off + 22.0), 0.7), Vector3(5, 2.8, 6), log_brown, rust)
			_house(kit, _strip_xf(k, -40.0, -(off + 26.0), 0.1), Vector3(5, 2.8, 6), log_brown, green)
			for i in range(4):
				kit.cylinder(_strip_xf(k, -80.0 + 1.1 * float(i), -(off - 14.0)), 0.3, 0.3, 0.9, 6, red if i % 2 else blue, true)
		"Caribou Flats":  # hunting cabin and a wall tent
			_house(kit, _strip_xf(k, -90.0, off - 6.0), Vector3(5, 2.8, 7), log_brown, green)
			_house(kit, _strip_xf(k, -70.0, off + 4.0, 0.5), Vector3(3.4, 0.2, 4.4), white, white)
		"Cape Sorrow":  # a small light on the shore and a keeper's hut
			var light := _strip_xf(k, 60.0, -(off + 10.0))
			kit.cylinder(light, 1.8, 1.2, 9.0, 8, white, true)
			kit.cylinder(light * Transform3D(Basis.IDENTITY, Vector3(0, 9.0, 0)), 1.4, 1.4, 1.6, 8, Color(0.95, 0.85, 0.35), true)
			kit.cylinder(light * Transform3D(Basis.IDENTITY, Vector3(0, 10.6, 0)), 1.6, 0.0, 1.4, 8, red, true)
			_house(kit, _strip_xf(k, 45.0, -(off + 4.0)), Vector3(4.5, 2.6, 6), white, red)
		"Otter Creek":  # a trapper's cabin and a cache on stilts
			_house(kit, _strip_xf(k, -40.0, off - 8.0, 0.2), Vector3(5, 2.8, 6.5), log_brown, rust)
			var cache := _strip_xf(k, -24.0, off - 2.0)
			for sx in [-0.8, 0.8]:
				for sz in [-0.8, 0.8]:
					kit.box(cache * Transform3D(Basis.IDENTITY, Vector3(sx, 1.5, sz)), Vector3(0.14, 3.0, 0.14), log_brown)
			_house(kit, cache * Transform3D(Basis.IDENTITY, Vector3(0, 3.0, 0)), Vector3(2.2, 1.3, 2.2), log_brown, tin)
		"Granite Creek Mine":  # shed, headframe and spoil heaps at the uphill end
			_house(kit, _strip_xf(k, 150.0, off + 2.0), Vector3(10, 5.0, 16), tin, rust)
			var tower := _strip_xf(k, 185.0, off + 22.0)
			kit.cylinder(tower, 2.2, 0.9, 13.0, 4, log_brown, true)
			kit.box(tower * Transform3D(Basis.IDENTITY, Vector3(0, 13.6, 0)), Vector3(3.0, 1.2, 3.0), rust)
			kit.cylinder(_strip_xf(k, 120.0, off + 30.0), 11.0, 0.0, 6.5, 7, Color(0.44, 0.42, 0.40), false)
			kit.cylinder(_strip_xf(k, 95.0, off + 44.0), 8.0, 0.0, 4.5, 6, Color(0.47, 0.44, 0.41), false)
		"Windy Pass":  # weather hut and mast
			_house(kit, _strip_xf(k, 0.0, off - 14.0), Vector3(4, 2.5, 5), red, tin)
			kit.cylinder(_strip_xf(k, 8.0, off - 8.0), 0.12, 0.05, 11.0, 4, tin, false)
		"Kestrel Glacier":  # a survey camp: two tents and a line of flags
			_house(kit, _strip_xf(k, 120.0, off - 14.0, 0.3), Vector3(3.6, 0.2, 5.0), Color(0.90, 0.55, 0.12), Color(0.90, 0.55, 0.12))
			_house(kit, _strip_xf(k, 132.0, off - 8.0, -0.2), Vector3(3.0, 0.2, 4.0), Color(0.85, 0.75, 0.20), Color(0.85, 0.75, 0.20))
			for i in range(6):
				var flag := _strip_xf(k, -150.0 + 60.0 * float(i), hw + 6.0)
				kit.cylinder(flag, 0.05, 0.05, 2.4, 4, tin, false)
				kit.box(flag * Transform3D(Basis.IDENTITY, Vector3(0.35, 2.1, 0)), Vector3(0.7, 0.45, 0.04), red)


## The home base's buildings (DESIGN_NOTES 147), all in structures.gd so
## they can burn: the log office (where a new game starts, its stove going),
## the bunkhouse cabin, the red pole-barn shop, and round them a woodpile, an
## outhouse, drums and propane. Doors face the strip.
var structures: Node3D


func _make_structures() -> void:
	if structures != null:
		return
	structures = load("res://scripts/structures.gd").new()
	structures.name = "Structures"
	structures.terrain = terrain
	add_child(structures)


func _home_base(k: int, hw: float) -> void:
	_make_structures()
	var face := PI * 0.5          # door (-Z) toward the runway
	var st: Node3D = structures
	st.add("office", "office", _strip_xf(k, -29.0, hw + 47.0, face), {"stove_lit": true, "loads": 2.0, "box": 4, "sign": "OFFICE"})
	st.add("office_wood", "woodpile", _strip_xf(k, -21.5, hw + 49.0, face + PI * 0.5), {"len": 3.2, "seed": 5})
	st.add("office_propane", "propane", _strip_xf(k, -36.0, hw + 50.0, face + PI * 0.5))
	st.add("bunkhouse", "cabin", _strip_xf(k, -11.0, hw + 50.0, face), {"seed": 31, "box": 2})
	st.add("bunk_wood", "woodpile", _strip_xf(k, -5.5, hw + 51.0, face + PI * 0.5), {"len": 2.6, "seed": 9})
	st.add("outhouse", "outhouse", _strip_xf(k, -4.0, hw + 60.0, face + PI))
	st.add("shop", "polebarn", _strip_xf(k, 12.0, hw + 54.0, face))
	st.add("shop_drums", "drums", _strip_xf(k, 20.5, hw + 47.0, face + PI * 0.5), {"n": 6, "seed": 2})
	_cabin_in_woods()


## The little cabin in the woods: a trapper's cabin back in the trees off the
## north side of the claim, smoke going, its cache and woodpile, an outhouse.
func _cabin_in_woods() -> void:
	var best := Vector3.ZERO
	var best_s := -1.0e9
	var L: Dictionary = terrain.lay()
	var pond: Vector2 = L["pond"][0]
	var pad: Vector2 = L["pad"]
	var bog: Vector2 = terrain.mudbog()
	for i in range(160):
		var a := TAU * float(i) / 40.0
		var r := 120.0 + 12.0 * float(i / 40)
		var x := -20.0 + cos(a) * r
		var z := -60.0 + sin(a) * r * 0.9
		if absf(x) > 150.0 or absf(z) > 150.0 or z < -95.0:
			continue
		var n: Vector3 = terrain.normal_at(x, z)
		if n.y < 0.975:
			continue
		var p2 := Vector2(x, z)
		if p2.distance_to(pond) < 60.0 or p2.distance_to(pad) < 55.0 or p2.distance_to(bog) < 45.0:
			continue
		if terrain.creek_dist(x, z) < 28.0 or terrain.height_at(x, z) < 4.0:
			continue
		var score: float = terrain.forest_at(x, z) * 10.0 + n.y * 5.0 - absf(r - 140.0) * 0.02
		if score > best_s:
			best_s = score
			best = Vector3(x, 0, z)
	if best_s < -1.0e8:
		best = Vector3(-60.0, 0, 60.0)
	var yaw := atan2(best.x - (-20.0), best.z - (-60.0))          # door back toward the base
	var at := Vector3(best.x, terrain.height_at(best.x, best.z), best.z)
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	var st: Node3D = structures
	st.add("woods_cabin", "cabin", xf, {"seed": 47, "stove_lit": true, "loads": 3.0, "box": 3})
	st.add("woods_cache", "cache", _on_ground(xf * Transform3D(Basis(Vector3.UP, 0.4), Vector3(6.5, 0, 4.0))))
	st.add("woods_wood", "woodpile", _on_ground(xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(5.0, 0, -1.0))), {"len": 2.8, "seed": 13})
	st.add("woods_outhouse", "outhouse", _on_ground(xf * Transform3D(Basis(Vector3.UP, PI), Vector3(-6.0, 0, 7.0))))
	woods_cabin = at


var woods_cabin := Vector3.ZERO


func _on_ground(xf: Transform3D) -> Transform3D:
	xf.origin.y = terrain.height_at(xf.origin.x, xf.origin.z)
	return xf


func _add_windsock(k: int, hw: float) -> void:
	var base := _strip_xf(k, 0.0, -(hw + 16.0))
	var root := Node3D.new()
	root.name = "Windsock%d" % k
	root.position = base.origin
	add_child(root)
	var kit := MeshKit.new()
	kit.cylinder(Transform3D.IDENTITY, 0.09, 0.06, 6.5, 5, Color(0.85, 0.85, 0.82), false)
	root.add_child(kit.instance("Pole"))
	# The sock hangs from a pivot at the top of the pole and points along its own -Z.
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0, 6.5, 0)
	root.add_child(pivot)
	var sock := MeshKit.new()
	var bands := [Color(0.95, 0.42, 0.05), Color(0.95, 0.93, 0.88), Color(0.95, 0.42, 0.05), Color(0.95, 0.93, 0.88)]
	for i in range(4):
		var r0 := lerpf(0.5, 0.2, float(i) / 4.0)
		var r1 := lerpf(0.5, 0.2, float(i + 1) / 4.0)
		var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.9 * float(i)))
		sock.cylinder(xf, r0, r1, 0.9, 6, bands[i], false)
	var sock_node: MeshInstance3D = sock.instance("Sock")
	var sock_mat := MeshKit.material().duplicate() as StandardMaterial3D
	sock_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sock_node.material_override = sock_mat
	pivot.add_child(sock_node)
	_windsocks.append(pivot)


# ------------------------------------------------------------------------------
#  Sky, sun and atmosphere
# ------------------------------------------------------------------------------
func _build_sky() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sun_angle_max = 8.0
	_sky_mat.sun_curve = 0.08
	# Clouds: soft noise painted on the sky dome.
	var clouds := NoiseTexture2D.new()
	clouds.width = 1024
	clouds.height = 512
	clouds.seamless = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.006
	fn.fractal_octaves = 5
	fn.fractal_gain = 0.55
	clouds.noise = fn
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0, 0, 0))
	ramp.set_offset(0, 0.52)
	ramp.set_color(1, Color(1, 1, 1))
	ramp.set_offset(1, 0.78)
	clouds.color_ramp = ramp
	_cloud_ramp = ramp
	_sky_mat.sky_cover = clouds
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.ambient_light_sky_contribution = 1.0
	_env.ambient_light_energy = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.0
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_aerial_perspective = 0.75
	_env.fog_sky_affect = 0.25
	_env.glow_enabled = true
	_env.glow_intensity = 0.35
	_env.glow_bloom = 0.03
	_env.glow_hdr_threshold = 1.2
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.15     # polyart colour (reference/)
	_env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_blend_splits = true
	_sun.shadow_bias = 0.05
	_sun.shadow_normal_bias = 1.5
	_sun.light_angular_distance = 0.25
	add_child(_sun)
	apply_quality()


## Graphics quality: how far shadows reach and which screen-space effects run.
func apply_quality() -> void:
	# Shadows: off, then further and sharper with each step.
	var sh: int = clampi(Game.gfx_shadows, 0, 4)
	_sun.shadow_enabled = sh > 0
	# (Ultra was most of a 15 ms GPU frame at 1400 m: 1000 m looks the same
	# from the cockpit - the far cascade only ever held tree specks)
	_sun.directional_shadow_max_distance = [100.0, 300.0, 500.0, 800.0, 1000.0][sh]
	_sun.directional_shadow_fade_start = 0.6
	_sun.shadow_blur = [1.0, 1.0, 1.0, 1.2, 1.3][sh]
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if sh >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096, 8192, 8192][sh], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][sh])
	_env.ssao_enabled = Game.gfx_ao
	_env.ssao_radius = 2.5
	_env.ssao_intensity = 1.2        # enough to seat things on the ground without muddying the flat facets
	_env.ssao_detail = 0.6
	_env.ssil_enabled = Game.gfx_ssil
	_env.ssil_radius = 6.0
	_env.ssil_intensity = 0.6
	_env.ssr_enabled = Game.gfx_ssr
	_env.ssr_max_steps = 48
	_env.glow_enabled = Game.gfx_glow
	_env.sdfgi_enabled = false
	if vegetation != null:
		vegetation.apply_quality(Game.gfx_plants)
	# (DESIGN_NOTES 186) the near-camera wave patch stays off at every quality: BP2's
	# ponds carry their own waves. This line used to switch it back on (GPU cost).
	if _patch != null:
		_patch.set_meta("off", true)
	var vp := get_viewport()
	if vp != null:
		var aa: int = clampi(Game.gfx_aa, 0, 6)
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X,
			Viewport.MSAA_DISABLED, Viewport.MSAA_4X][aa]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = aa == 5 or aa == 6
		vp.scaling_3d_scale = clampf(Game.render_scale * _res_factor(), 0.25, 1.0)
		vp.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_FSR2][clampi(Game.upscaler, 0, 2)]
		if Game.upscaler == 2:
			vp.use_taa = false        # FSR 2 does its own anti-aliasing
		# sharpening: the engine's 0 is sharpest, 2 is softest
		vp.fsr_sharpness = (1.0 - clampf(Game.upscale_sharp, 0.0, 1.0)) * 2.0
	_apply_window()


## How much of the window's height the chosen resolution is (1 = native).
func _res_factor() -> float:
	var res: Vector2i = Game.RESOLUTIONS[clampi(Game.resolution, 0, Game.RESOLUTIONS.size() - 1)]
	var win := get_window()
	if res == Vector2i.ZERO or win == null or win.mode == Window.MODE_WINDOWED or win.size.y <= 0:
		return 1.0
	return clampf(float(res.y) / float(win.size.y), 0.25, 1.0)


## Window mode, vsync and frame-rate cap.
func _apply_window() -> void:
	var win := get_window()
	if win == null or DisplayServer.get_name() == "headless":
		return
	var want: Window.Mode = [Window.MODE_WINDOWED, Window.MODE_MAXIMIZED, Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN][clampi(Game.window_mode, 0, 3)]
	if win.mode != want:
		win.mode = want
	# Resolution (DESIGN_NOTES 164): in a window, the window's size; full
	# screen keeps the screen's own mode and draws the 3D at that resolution
	# (scaled up), the menus and HUD staying sharp.
	var res: Vector2i = Game.RESOLUTIONS[clampi(Game.resolution, 0, Game.RESOLUTIONS.size() - 1)]
	if res != Vector2i.ZERO and want == Window.MODE_WINDOWED:
		var scr := DisplayServer.screen_get_size(win.current_screen)
		var r := Vector2i(mini(res.x, scr.x), mini(res.y, scr.y))
		if win.size != r:
			win.size = r
			win.move_to_center()
	var vp2 := get_viewport()
	if vp2 != null:
		vp2.scaling_3d_scale = clampf(Game.render_scale * _res_factor(), 0.25, 1.0)
	DisplayServer.window_set_vsync_mode([DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_ADAPTIVE][clampi(Game.vsync, 0, 2)])
	Engine.max_fps = int(Game.FPS_LIMITS[clampi(Game.fps_limit, 0, Game.FPS_LIMITS.size() - 1)])


## Apply the current season and time of day from the Game settings.
func apply_season() -> void:
	var outback: bool = Game.outback()
	# The Outback has one season here: the long hot dry (DESIGN_NOTES 108).
	var season: int = Game.SUMMER if outback else Game.season
	terrain.season = season
	# Muted palette: olive grass, straw tundra, dark spruce floor.
	var grass := Color(0.30, 0.33, 0.19)
	var tundra := Color(0.42, 0.40, 0.27)
	var forest := Color(0.13, 0.17, 0.12)
	var bog := Color(0.36, 0.36, 0.23)
	var burn := Color(0.33, 0.30, 0.27)
	var fireweed := Color(0.42, 0.32, 0.34)
	var conifer := Color(0.08, 0.19, 0.10)
	var birch := Color(0.24, 0.38, 0.13)
	var snow_cover := 0.0
	var tree_snow := 0.0
	var sky_top := Color(0.18, 0.40, 0.74)
	var sky_hor := Color(0.62, 0.76, 0.90)
	var fog_density := 0.000055
	match season:
		Game.FALL:
			grass = Color(0.52, 0.45, 0.25)
			tundra = Color(0.52, 0.32, 0.20)
			forest = Color(0.16, 0.19, 0.12)
			bog = Color(0.56, 0.34, 0.20)
			fireweed = Color(0.50, 0.24, 0.18)
			birch = Color(0.88, 0.62, 0.08)
			sky_top = Color(0.22, 0.40, 0.68)
			sky_hor = Color(0.70, 0.78, 0.86)
			fog_density = 0.00008
		Game.WINTER:
			grass = Color(0.55, 0.55, 0.50)
			tundra = Color(0.60, 0.60, 0.58)
			forest = Color(0.17, 0.24, 0.19)
			bog = Color(0.55, 0.55, 0.50)
			burn = Color(0.50, 0.50, 0.48)
			fireweed = burn
			conifer = Color(0.10, 0.20, 0.13)
			snow_cover = 1.0
			tree_snow = 1.0
			sky_top = Color(0.30, 0.48, 0.74)
			sky_hor = Color(0.80, 0.86, 0.93)
			fog_density = 0.00009
		Game.SPRING:
			grass = Color(0.40, 0.39, 0.23)
			tundra = Color(0.46, 0.39, 0.25)
			bog = Color(0.44, 0.36, 0.24)
			fireweed = burn
			birch = Color(0.52, 0.66, 0.24)
			sky_top = Color(0.20, 0.42, 0.74)
			sky_hor = Color(0.66, 0.78, 0.90)
			fog_density = 0.00007
	if outback:
		# Hot, clear and dry: a deep blue overhead going pale and a touch dusty
		# at the horizon, very little haze.
		sky_top = Color(0.08, 0.27, 0.70)
		sky_hor = Color(0.66, 0.74, 0.84)
		fog_density = 0.000035
	for mat0 in [_terrain_mat, _plain_mat(), DigSiteScript.shared_mat]:
		if mat0 is ShaderMaterial:
			(mat0 as ShaderMaterial).set_shader_parameter("outback", 1.0 if outback else 0.0)
			# the mud dries in summer, freezes (and snows over) in winter, and is
			# at its worst in spring break-up (DESIGN_NOTES 109)
			(mat0 as ShaderMaterial).set_shader_parameter("mud_k", [0.9, 1.0, 0.0, 1.25][clampi(season, 0, 3)] + (0.15 if Game.weather == 2 else 0.0))
	VoxelGroundLib.set_global("bp_mud_k", [0.9, 1.0, 0.0, 1.25][clampi(season, 0, 3)] + (0.15 if Game.weather == 2 else 0.0))
	if _terrain_mat != null:
		# Full snow cover under a low sun needs a slightly greyer white to keep its shape.
		_terrain_mat.set_shader_parameter("col_snow", Color(0.76, 0.79, 0.85) if season == Game.WINTER else Color(0.79, 0.81, 0.86))
		_terrain_mat.set_shader_parameter("snow_line", terrain.snow_line())
		_terrain_mat.set_shader_parameter("snow_cover", snow_cover)
		VoxelGroundLib.set_global("bp_snow_cover", snow_cover)
		VoxelGroundLib.set_global("bp_snow_line", terrain.snow_line())
		VoxelGroundLib.set_global("bp_col_snow", Color(0.76, 0.79, 0.85) if season == Game.WINTER else Color(0.79, 0.81, 0.86))
		# The diggable tiles wear the same season.
		if DigSiteScript.shared_mat != null:
			DigSiteScript.shared_mat.set_shader_parameter("snow_line", terrain.snow_line())
			DigSiteScript.shared_mat.set_shader_parameter("snow_cover", snow_cover)
		_terrain_mat.set_shader_parameter("col_grass", grass)
		_terrain_mat.set_shader_parameter("col_tundra", tundra)
		_terrain_mat.set_shader_parameter("col_forest", forest)
		_terrain_mat.set_shader_parameter("col_bog", bog)
		_terrain_mat.set_shader_parameter("col_burn", burn)
		_terrain_mat.set_shader_parameter("col_fireweed", fireweed)
	if _conifer_mat != null:
		_conifer_mat.set_shader_parameter("foliage", conifer)
		_conifer_mat.set_shader_parameter("snow", tree_snow)
		_birch_mat.set_shader_parameter("foliage", birch)
		_birch_mat.set_shader_parameter("snow", 0.0)
		var bare := season == Game.WINTER
		for node in _birch_nodes:
			node.multimesh.mesh = _birch_bare_mesh if bare else _birch_mesh
	for mi in _lake_nodes:
		mi.material_override = _ice_mat if terrain.lakes_frozen() else _water_mat
	var to := deg_to_rad(Game.wind_dir_deg + 180.0)
	_water_mat.set_shader_parameter("wind_dir", Vector2(sin(to), -cos(to)))
	_water_mat.set_shader_parameter("chop", 0.25 + 0.55 * float(Game.wind_level))
	_patch_mat.set_shader_parameter("wind_dir", Vector2(sin(to), -cos(to)))
	_patch_mat.set_shader_parameter("chop", 0.25 + 0.55 * float(Game.wind_level))
	_apply_sun(sky_top, sky_hor, fog_density)
	if _sun != null:
		apply_quality()
	if vegetation != null:
		vegetation.apply_season(season)


func _apply_sun(sky_top: Color, sky_hor: Color, fog_density: float) -> void:
	# Latitude is about 60 degrees north: long summer days, short winter ones.
	var rise := 4.0
	var set_h := 22.5
	var max_elev := 53.0
	match Game.season:
		Game.FALL, Game.SPRING:
			rise = 7.0
			set_h = 19.0
			max_elev = 30.0
		Game.WINTER:
			rise = 9.5
			set_h = 15.5
			max_elev = 9.0
	var outback: bool = Game.outback()
	var cold: bool = not outback and Game.cold_look
	if cold:
		# Alaska at 62-64 N: the sun stays low all day (summer noon about 40
		# degrees, autumn 22, midwinter barely clears the hills): long shadows.
		max_elev *= 0.75
	if outback:
		# About 23 degrees south, in the dry: up at six, down by half past
		# six, nearly overhead at noon, and it crosses the NORTHERN sky.
		rise = 6.0
		set_h = 18.6
		max_elev = 80.0
	var t: float = Game.time_of_day
	var day_frac := (t - rise) / (set_h - rise)
	var elev_deg := max_elev * sin(PI * clampf(day_frac, -0.25, 1.25))
	if day_frac < 0.0 or day_frac > 1.0:
		elev_deg = maxf(elev_deg, -18.0)
	var azim := deg_to_rad(90.0 + 180.0 * day_frac)   # 90 = east, 180 = south
	if outback:
		azim = deg_to_rad(90.0 - 180.0 * day_frac)      # east, north (0), west
	var elev := deg_to_rad(elev_deg)
	# Direction from the ground toward the sun.
	var to_sun := Vector3(sin(azim) * cos(elev), sin(elev), -cos(azim) * cos(elev)).normalized()
	var daylight := smoothstep(-6.0, 6.0, elev_deg)      # 0 at night, 1 in full day
	var low_sun := 1.0 - smoothstep(4.0, 22.0, absf(elev_deg))   # 1 near the horizon

	if to_sun.y > 0.02:
		_sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP)
	else:
		# Below the horizon: keep a faint light from just above it so shapes stay readable.
		var flat := Vector3(to_sun.x, 0.0, to_sun.z).normalized()
		_sun.look_at_from_position(Vector3.ZERO, -(flat + Vector3(0, 0.25, 0)).normalized(), Vector3.UP)
	var warm := Color(1.0, 0.78, 0.55)
	_sun.light_color = Color(1.0, 0.97, 0.92).lerp(warm, low_sun * 0.8)
	_sun.light_energy = lerpf(0.04, 1.6, daylight) * lerpf(1.0, 0.8, low_sun)
	if cold:
		# Alaska: cold, clean northern light - a bluish-white sun, warm only
		# right at the horizon.
		_sun.light_color = Color(0.86, 0.93, 1.0).lerp(Color(1.0, 0.74, 0.50), low_sun * 0.8)
		_sun.light_energy = lerpf(0.04, 1.9, daylight) * lerpf(1.0, 0.8, low_sun)
	if outback:
		# Harsh, bright, a little orange: hard shadows, high contrast.
		_sun.light_color = Color(1.0, 0.91, 0.78).lerp(Color(1.0, 0.66, 0.40), low_sun * 0.85)
		_sun.light_energy = lerpf(0.04, 2.15, daylight) * lerpf(1.0, 0.8, low_sun)

	# Runway lights come alight as the sun gets low, out by mid-morning.
	var rwy_on := 1.0 - smoothstep(2.0, 9.0, elev_deg)
	for m in _rwy_mats:
		(m as StandardMaterial3D).emission_energy_multiplier = 14.0 * rwy_on

	var night_top := Color(0.015, 0.025, 0.06)
	var night_hor := Color(0.04, 0.06, 0.11)
	var dusk_hor := Color(0.95, 0.60, 0.38)
	if outback:
		dusk_hor = Color(1.0, 0.50, 0.24)        # red-orange outback sunsets
	var top := night_top.lerp(sky_top, daylight)
	var hor := night_hor.lerp(sky_hor.lerp(dusk_hor, low_sun * 0.65), daylight)
	_sky_mat.sky_top_color = top
	_sky_mat.sky_horizon_color = hor
	_sky_mat.ground_horizon_color = hor
	_sky_mat.ground_bottom_color = hor.darkened(0.3)
	_sky_mat.sky_energy_multiplier = lerpf(0.25, 1.0, daylight)
	_sky_mat.sky_cover_modulate = Color(1.0, 0.97, 0.94).lerp(Color(1.0, 0.72, 0.55), low_sun * 0.7) * Color(1, 1, 1, lerpf(0.15, 0.85, daylight))
	# Weather: grey skies, flat light, rain or snow, fog.
	var w: int = Game.weather
	if w >= 1:
		var grey := Color(0.46, 0.49, 0.52) if w != 3 else Color(0.62, 0.64, 0.66)
		top = top.lerp(grey * lerpf(0.15, 0.85, daylight), 0.8)
		hor = hor.lerp(grey * lerpf(0.2, 1.0, daylight), 0.8)
		_sky_mat.sky_top_color = top
		_sky_mat.sky_horizon_color = hor
		_sky_mat.ground_horizon_color = hor
		_sky_mat.ground_bottom_color = hor.darkened(0.3)
		_sky_mat.sky_cover_modulate = Color(0.55, 0.56, 0.58, lerpf(0.15, 1.0, daylight))
		_sun.light_energy *= 0.35 if w == 1 else 0.22
	_cloud_ramp.set_offset(0, 0.52 if w == 0 else 0.15)
	_cloud_ramp.set_offset(1, 0.78 if w == 0 else 0.55)
	var fog_k: float = [1.0, 1.6, 3.0, 14.0][w]
	_env.fog_light_color = hor.lerp(top, 0.25)
	_env.fog_density = fog_density * 1.6 * fog_k
	_env.ambient_light_energy = lerpf(0.25, 1.0, daylight)
	if outback:
		# Dust in the air, not water: the haze goes warm, the shade stays deep.
		_env.fog_light_color = hor.lerp(Color(0.86, 0.66, 0.48), 0.45)
		_env.ambient_light_energy = lerpf(0.25, 0.82, daylight)
		_env.adjustment_contrast = 1.14
		_env.adjustment_saturation = 1.22
		_env.glow_intensity = 0.45
		_env.glow_hdr_threshold = 1.0
		_env.fog_aerial_perspective = 0.6
		_cloud_ramp.set_offset(0, 0.70 if w == 0 else 0.25)
		_cloud_ramp.set_offset(1, 0.90 if w == 0 else 0.62)
		_env.adjustment_color_correction = _grade_lut(false)
		_env.fog_sky_affect = 0.25
	elif cold:
		# Alaska: the distance goes clearly blue-grey (thick aerial perspective
		# over the forest), shadows go blue/cyan through the grade, mid-tones
		# muted and cool, crisp contrast, a cold bloom off snow and water.
		_env.fog_light_color = Color(0.56, 0.66, 0.79).lerp(hor, 0.25) * lerpf(0.12, 1.0, daylight)
		_env.fog_density = fog_density * 3.6 * fog_k
		_env.fog_aerial_perspective = 1.0
		_env.fog_sky_affect = 0.35
		_env.ambient_light_energy = lerpf(0.25, 1.05, daylight)
		_env.adjustment_contrast = 1.16
		_env.adjustment_saturation = 0.88
		_env.adjustment_color_correction = _grade_lut(true)
		_env.glow_intensity = 0.42
		_env.glow_hdr_threshold = 0.95
	else:
		# The old look (console: look classic), for comparing.
		_env.fog_aerial_perspective = 0.75
		_env.fog_sky_affect = 0.25
		_env.adjustment_contrast = 1.08
		_env.adjustment_saturation = 1.15
		_env.adjustment_color_correction = null
		_env.glow_intensity = 0.35
		_env.glow_hdr_threshold = 1.2
	# Morning mist: on a clear, calm morning cold air pools in the creek
	# hollow, over the pond and the low ground, and burns off by mid-morning.
	var mist := 0.0
	if cold and w == 0 and Game.wind_level <= 1:
		mist = smoothstep(rise - 1.5, rise + 0.5, t) * (1.0 - smoothstep(rise + 2.5, rise + 4.5, t))
	_env.fog_height = 8.5
	_env.fog_height_density = 0.22 * mist
	if region != null and GroundScript.region_dy > 100.0:
		# up on the mountain: the haze lies in the valleys below (the region's
		# own look, Dave's Alps photo), the morning mist pooled down there too
		_env.fog_height = 260.0 - GroundScript.region_dy
		_env.fog_height_density = 0.0012 + 0.02 * mist
	night = 1.0 - daylight
	_set_precip(w == 2, Game.season == Game.WINTER and not outback)
	if _runway_light_mat != null:
		_runway_light_mat.emission_energy_multiplier = lerpf(0.0, 3.0, smoothstep(0.4, 0.9, night))


func _process(_delta: float) -> void:
	_update_patch()
	if _precip != null and _precip.emitting:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_precip.global_position = cam.global_position + Vector3(0, 12, 0)
	if wind == null or _windsocks.is_empty():
		return
	# Socks point downwind and stand out straighter as the wind picks up.
	for pivot in _windsocks:
		var w: Vector3 = wind.sample(pivot.global_position)
		var speed := Vector2(w.x, w.z).length()
		var yaw := atan2(-w.x, -w.z)
		var droop := lerpf(-1.35, -0.06, clampf(speed / 9.0, 0.0, 1.0))
		droop += 0.05 * sin(Time.get_ticks_msec() * 0.006 + pivot.global_position.x)
		pivot.rotation = Vector3(droop, yaw, 0.0)


# ------------------------------------------------------------------------------
#  Seaplane docks: a plank dock on posts, a fuel pump at the end, drums and a
#  shack on the shore
# ------------------------------------------------------------------------------
func _build_docks() -> void:
	var kit := MeshKit.new()
	var plank := Color(0.42, 0.34, 0.25)
	var post := Color(0.26, 0.21, 0.16)
	var red := Color(0.66, 0.15, 0.12)
	var white := Color(0.88, 0.88, 0.84)
	var tin := Color(0.55, 0.57, 0.58)
	var log_brown := Color(0.36, 0.25, 0.16)
	for d in terrain.docks:
		var shore: Vector2 = d["shore"]
		var water: Vector2 = d["water"]
		var out: Vector2 = d["out"]
		var level: float = d["level"]
		var yaw := atan2(out.x, out.y)
		var start := shore - out * 5.0
		var finish := water + out * 3.0
		var length := start.distance_to(finish)
		var mid := (start + finish) * 0.5
		var deck_y := level + 0.65
		var basis := Basis(Vector3.UP, yaw)
		# Deck and posts
		kit.box(Transform3D(basis, Vector3(mid.x, deck_y, mid.y)), Vector3(2.4, 0.18, length), plank)
		var n := int(length / 3.0)
		for i in range(n + 1):
			var p := start + (finish - start) * (float(i) / float(n))
			var g: float = minf(terrain.height_at(p.x, p.y), level - 1.0)
			for sx in [-1.1, 1.1]:
				var off := basis * Vector3(sx, 0, 0)
				var top := deck_y
				kit.box(Transform3D(Basis.IDENTITY, Vector3(p.x + off.x, (g + top) * 0.5, p.y + off.z)), Vector3(0.22, top - g + 0.2, 0.22), post)
		# A wider float landing at the end, where a plane ties up.
		var end_c := water + out * 1.0
		kit.box(Transform3D(basis, Vector3(end_c.x, deck_y, end_c.y)) * Transform3D(Basis.IDENTITY, Vector3(-2.4, 0, 0)), Vector3(3.0, 0.18, 6.0), plank)
		# Fuel pump and hose reel
		var pump := Vector3(finish.x, deck_y + 0.09, finish.y) + basis * Vector3(0.7, 0, -1.0)
		kit.box(Transform3D(basis, pump + Vector3(0, 0.75, 0)), Vector3(0.6, 1.5, 0.45), red)
		kit.box(Transform3D(basis, pump + Vector3(0, 1.62, 0)), Vector3(0.5, 0.25, 0.4), white)
		kit.cylinder(Transform3D(basis * Basis(Vector3.BACK, PI * 0.5), pump + basis * Vector3(0.45, 0.8, 0)), 0.22, 0.22, 0.12, 10, Color(0.1, 0.1, 0.1), true)
		# Drums on the shore end
		for i in range(4):
			var dp := Vector3(start.x, 0, start.y) + basis * Vector3(1.8 + 0.65 * float(i % 2), 0, 1.0 + 0.65 * float(i / 2))
			dp.y = terrain.height_at(dp.x, dp.z)
			kit.cylinder(Transform3D(Basis.IDENTITY, dp), 0.3, 0.3, 0.9, 8, red if i % 2 else Color(0.20, 0.33, 0.52), true)
		# Shack set back from the water
		var shack := shore - out * 13.0
		var sp := Vector3(shack.x, terrain.height_at(shack.x, shack.y), shack.y)
		_house(kit, Transform3D(basis, sp), Vector3(4.5, 2.7, 5.5), log_brown, tin)
	if not kit.is_empty():
		var mi: MeshInstance3D = kit.instance("Docks")
		add_child(mi)


## Move the wavy near-water patch to the water by the camera (a lake or the
## sea), and cut a hole in the flat water there for it.
func _update_patch() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _patch == null or terrain.lakes_frozen() or bool(_patch.get_meta("off", false)):
		if _patch != null:
			_patch.visible = false
			_water_mat.set_shader_parameter("hole_r", 0.0)
		return
	var c := cam.global_position
	var level := 0.0
	var shape := Vector4.ZERO
	for lake in terrain.lakes:
		var lc: Vector2 = lake["pos"]
		if Vector2(c.x - lc.x, c.z - lc.y).length() < float(lake["radius"]) * 1.5 + PATCH_R:
			level = lake["level"]
			shape = Vector4(lc.x, lc.y, lake["radius"], lake["seed"])
	var show := c.y - level < 220.0 and (shape.z > 0.0 or c.y < 220.0)
	_patch.visible = show
	if not show:
		_water_mat.set_shader_parameter("hole_r", 0.0)
		return
	var step := PATCH_R * 2.0 / 144.0
	var at := Vector3(snappedf(c.x, step), level, snappedf(c.z, step))
	_patch.global_position = at
	_patch_mat.set_shader_parameter("patch_center", Vector2(at.x, at.z))
	_patch_mat.set_shader_parameter("lake_shape", shape)
	_water_mat.set_shader_parameter("hole_center", Vector2(at.x, at.z))
	_water_mat.set_shader_parameter("hole_r", PATCH_R * 0.93)


# ------------------------------------------------------------------------------
#  Airport dressing: a sign with the strip's name, a fuel pump and drums where
#  there is fuel, a couple of people about, and planes parked at the towns.
# ------------------------------------------------------------------------------
const PilotModelW = preload("res://scripts/pilot_model.gd")
const PlaneScriptW = preload("res://scripts/plane.gd")
const PlaneVisualW = preload("res://scripts/plane_visual.gd")


func _build_apron(kit: RefCounted, k: int, hw: float) -> void:
	var s: Dictionary = terrain.strips[k]
	var hl: float = s["length"] * 0.5
	var red := Color(0.66, 0.15, 0.12)
	var white := Color(0.90, 0.90, 0.86)
	var post := Color(0.30, 0.24, 0.18)
	# Name board at the near end
	var sign_xf := _strip_xf(k, -hl + 30.0, -(hw + 10.0), PI * 0.5)
	kit.box(sign_xf * Transform3D(Basis.IDENTITY, Vector3(-1.4, 1.0, 0)), Vector3(0.15, 2.0, 0.15), post)
	kit.box(sign_xf * Transform3D(Basis.IDENTITY, Vector3(1.4, 1.0, 0)), Vector3(0.15, 2.0, 0.15), post)
	kit.box(sign_xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.9, 0)), Vector3(3.4, 0.9, 0.08), white)
	var label := Label3D.new()
	label.text = String(s["name"]).to_upper()
	label.font_size = 64
	label.pixel_size = 0.004
	label.modulate = Color(0.15, 0.12, 0.10)
	label.outline_size = 0
	label.transform = sign_xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.9, -0.06))
	label.rotate_object_local(Vector3.UP, PI)
	add_child(label)
	var label2 := label.duplicate() as Label3D
	label2.transform = sign_xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.9, 0.06))
	add_child(label2)
	if bool(s["fuel"]):
		# Fuel pump on a little concrete pad, drums beside it.
		var pump := _strip_xf(k, -hl + 70.0, hw + 14.0)
		fuel_points.append(pump.origin)
		kit.box(pump * Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)), Vector3(3.0, 0.1, 2.0), Color(0.6, 0.6, 0.58))
		kit.box(pump * Transform3D(Basis.IDENTITY, Vector3(0, 0.85, 0)), Vector3(0.65, 1.6, 0.5), red)
		kit.box(pump * Transform3D(Basis.IDENTITY, Vector3(0, 1.75, 0)), Vector3(0.55, 0.3, 0.45), white)
		for i in range(5):
			var d := pump * Transform3D(Basis.IDENTITY, Vector3(2.4 + 0.65 * float(i % 3), 0, -0.4 + 0.65 * float(i / 3)))
			d.origin.y = terrain.height_at(d.origin.x, d.origin.z)
			kit.cylinder(d, 0.3, 0.3, 0.9, 8, red if i % 2 else Color(0.20, 0.33, 0.52), true)
		terrain.clear_spot(pump.origin.x, pump.origin.z, 6.0)
	# People and parked planes at the bigger places.
	var people := 0
	var parked := 0
	match String(s["name"]):
		"Port Ashby", "Proving Ground":
			people = 2
			parked = 1
		"Tern Harbor", "Moose Lake Lodge":
			people = 2
			parked = 1
		"Caribou Flats", "Salmon Bend", "Otter Creek":
			people = 1
	# (Dave, 2026-10-12: no loafers on the aprons - the old blocky figure is gone)
	people = 0
	if "noparked=1" in OS.get_cmdline_user_args():
		parked = 0
	for i in range(people):
		var m: Node3D = PilotModelW.new()
		add_child(m)
		m.build()
		var px := _strip_xf(k, -hl + 50.0 + 9.0 * float(i), hw + 9.0 + 2.0 * float(i % 2), PI * 0.5 + 0.7 * float(i))
		px.origin.y = terrain.height_at(px.origin.x, px.origin.z)
		m.global_transform = px
		m.animate(0.0, PilotModelW.IDLE, 0.0, float(i))
	if String(s["name"]) == "Port Ashby" or String(s["name"]) == "Proving Ground":
		# A real DC-3 for sale on the far side of the apron: walk up and buy it.
		var dcp: Node3D = PlaneScriptW.new()
		dcp.name = "SaleDC3"
		dcp.terrain = terrain
		add_child(dcp)
		dcp.apply_type("dc3")
		dcp.reg = "CF-TDJ"
		var dvis := preload("res://scripts/dc3_visual.gd").new()
		dvis.plane = dcp
		dcp.add_child(dvis)
		var dxf := _strip_xf(k, -hl + 175.0, hw + 30.0, PI * 0.5 + 0.5)
		terrain.clear_spot(dxf.origin.x, dxf.origin.z, 20.0)
		_park_live(dcp, dxf)
		sale_planes.append({"node": dcp, "type": "dc3"})
	if String(s["name"]) == "Proving Ground":
		# A biplane for sale on the grass beside the apron (DESIGN_NOTES 153).
		var bp: Node3D = PlaneScriptW.new()
		bp.name = "SaleBiplane"
		bp.terrain = terrain
		add_child(bp)
		bp.apply_type("biplane")
		bp.reg = "CF-AKB"
		bp.livery = 0
		var bvis: Node3D = load("res://scripts/biplane_visual.gd").new()
		bvis.plane = bp
		bp.add_child(bvis)
		var bxf := _strip_xf(k, -hl + 150.0, hw + 26.0, PI * 0.5 + 0.35)
		terrain.clear_spot(bxf.origin.x, bxf.origin.z, 9.0)
		bp.engine.set_cold_and_dark(5.0)
		_park_live(bp, bxf)
		sale_planes.append({"node": bp, "type": "biplane"})
	for i in range(parked):
		var pl: Node3D = PlaneScriptW.new()
		pl.name = "Parked_%s_%d" % [String(s["name"]).replace(" ", "_"), i]
		pl.terrain = terrain
		pl.reg = ["C-FWQX", "C-GRTA", "C-FBNL", "C-GOMP"][(k + i) % 4]
		add_child(pl)
		var vis: Node3D = PlaneVisualW.new()
		vis.plane = pl
		pl.add_child(vis)
		var at := _strip_xf(k, -hl + 120.0 + 18.0 * float(i), hw + 22.0, PI * 0.5 + 0.4)
		terrain.clear_spot(at.origin.x, at.origin.z, 9.0)
		pl.engine.set_cold_and_dark(5.0)
		_park_live(pl, at)
		sale_planes.append({"node": pl, "type": "wolverine"})


## A parked plane is a real plane, not a prop: put it at `at` facing the
## same way, sit it down on its own wheels (whatever gear it has on), brakes
## set, and leave its flight model running so it rests on the ground, rocks
## in the wind and can be pushed, bought and flown. (Planes were placed at a
## guessed height and frozen, so they hung in the air when the gear or the
## ground didn't match the guess.)
func _park_live(pl: Node3D, at: Transform3D) -> void:
	var gy: float = terrain.ground_level_at(at.origin.x, at.origin.z)
	pl.place_parked(Vector3(at.origin.x, gy + 4.0, at.origin.z), Quaternion(at.basis))
	pl.settle_here()
	pl.brake = 1.0
	pl.frozen = false


## Rain or snow falling round the camera.
func _set_precip(on: bool, snow: bool) -> void:
	if _precip == null:
		_precip = CPUParticles3D.new()
		_precip.name = "Precip"
		_precip.local_coords = false
		_precip.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_precip.emission_box_extents = Vector3(35, 4, 35)
		_precip.direction = Vector3(0, -1, 0)
		_precip.spread = 4.0
		_precip.particle_flag_align_y = true
		add_child(_precip)
	_precip.emitting = on
	if not on:
		return
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var q := QuadMesh.new()
	if snow:
		q.size = Vector2(0.06, 0.06)
		m.albedo_color = Color(0.95, 0.96, 1.0, 0.85)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_precip.particle_flag_align_y = false
		_precip.amount = 5000
		_precip.lifetime = 9.0
		_precip.initial_velocity_min = 0.8
		_precip.initial_velocity_max = 1.4
		_precip.gravity = Vector3(0.4, -0.6, 0.2)
	else:
		q.size = Vector2(0.012, 0.7)
		_precip.particle_flag_align_y = true
		_precip.amount = 6000
		_precip.lifetime = 1.6
		_precip.initial_velocity_min = 8.0
		_precip.initial_velocity_max = 10.0
		_precip.gravity = Vector3(0, -4.0, 0)
	if snow:
		# fades out far off (no white wall in the distance)
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = 40.0
		m.distance_fade_max_distance = 20.0
		q.material = m
	else:
		var rm := ShaderMaterial.new()
		rm.shader = load("res://shaders/rain.gdshader")
		q.material = rm
	_precip.mesh = q
	_precip.emission_box_extents = Vector3(26, 4, 26)


## The open plain's ground material (world_look.plain), or null.
func _plain_mat() -> ShaderMaterial:
	var pl := get_node_or_null("Plain") as MeshInstance3D
	if pl == null or pl.mesh == null:
		return null
	return pl.mesh.surface_get_material(0) as ShaderMaterial


## The colour grade (a per-channel curve). Cold: shadows lifted toward
## blue-cyan, reds held down a touch, highlights clean white. Warm (Outback):
## shadows toward rust, highlights a little golden.
static var _luts := {}
func _grade_lut(cold: bool) -> GradientTexture1D:
	if _luts.has(cold):
		return _luts[cold]
	var g := Gradient.new()
	if cold:
		g.set_color(0, Color(0.0, 0.025, 0.06))
		g.set_color(1, Color(0.985, 1.0, 1.0))
		g.add_point(0.25, Color(0.215, 0.25, 0.29))
		g.add_point(0.55, Color(0.52, 0.555, 0.58))
	else:
		g.set_color(0, Color(0.035, 0.012, 0.0))
		g.set_color(1, Color(1.0, 0.985, 0.94))
		g.add_point(0.25, Color(0.28, 0.245, 0.21))
		g.add_point(0.55, Color(0.585, 0.55, 0.51))
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 256
	_luts[cold] = tex
	return tex
