extends Node3D
## Landmarks you can find your way by from the air (DESIGN_NOTES 228, Dave:
## "different landmarks that you would be able to recognise", 1980s): a guyed
## radio mast on the ridge over town (red and white, blinking beacons), fire
## lookouts on the peaks (a steel tower and a ground cab), a microwave relay
## with a passive reflector billboard, the mine headframe and its tailings, the
## harbor lighthouse. The glacier at the head of the north-east valley with an
## ice cave in its snout and the meltwater river out of it - and a woolly
## mammoth frozen in the ice by the cave (a future mission: saw it out, crane
## it out), and dinosaur bones weathering out of a rock outcrop.
## All placed on the region's real ground (R.height) at true size.

const MeshKit = preload("res://scripts/meshkit.gd")

var R: Node3D                      # the region (height(), _coast_side(), _unwarp(), px())
var k := MeshKit.new()             # paint, steel, wood, concrete
var k_glass := MeshKit.new()       # dark window glass
var k_ice := MeshKit.new()         # the glacier
var k_clear := MeshKit.new()       # clear ice (the mammoth block)
var k_mesh := MeshKit.new()        # chain-link (see-through)
var k_beacon := MeshKit.new()      # the blinking red beacons
var k_lamp := MeshKit.new()        # the lighthouse lantern
var _beacon_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _t := 0.0
var spots := {}                    # name -> world position (for the map, missions)

const RED := Color(0.78, 0.14, 0.10)
const WHITE := Color(0.92, 0.92, 0.90)
const STEEL := Color(0.52, 0.53, 0.54)
const GALV := Color(0.62, 0.63, 0.62)
const WOOD := Color(0.42, 0.32, 0.22)
const CONC := Color(0.62, 0.60, 0.56)


var _at := {}


## Pick every site and level it into the region's ground (before the ground
## mesh is built): summits shaved a little and flattened like a bulldozed
## lookout or mast site, a bench for the mine, a pad for the lighthouse.
func plan(region: Node3D) -> void:
	R = region
	var px := func(x: float, y: float) -> Vector2: return R.px(Vector2(x, y))
	_at["mast"] = _site(_peak(px.call(525.0, 425.0), 530.0), 74.0, 6.0)        # the guy anchors 68 m out
	_at["tower"] = _site(_peak(px.call(250.0, 370.0), 730.0), 16.0, 2.0)
	_at["ground_cab"] = _site(_peak(px.call(505.0, 600.0), 600.0), 14.0, 2.0)
	_at["relay"] = _site(_peak(px.call(600.0, 240.0), 730.0), 24.0, 3.0)
	_at["reflector"] = _site(_peak(px.call(560.0, 330.0), 500.0), 16.0, 2.0)
	var mine := _mine_spot(px.call(185.0, 382.0))
	_at["mine"] = _site(mine, 30.0, 0.0)
	var lh := _lighthouse_spot(px.call(950.0, 700.0))
	_at["lighthouse"] = _site(lh, 22.0, 0.0)
	_at["fossils"] = _fossil_spot(px.call(440.0, 575.0))
	# the steel arch over the south gorge, 125 m above the river (fly under it):
	# where the two rims stand level (probed: x -100 and +25 at z 440)
	var ga := Vector2(-100, 440)
	var gb := Vector2(25, 440)
	var gy := maxf(_g(ga.x, ga.y), _g(gb.x, gb.y)) + 1.0
	_at["gorge_bridge"] = Vector3((ga.x + gb.x) * 0.5, gy, ga.y)
	_at["gorge_span"] = gb.x - ga.x
	R.add_flat(ga + Vector2(-8, 0), 9.0, 18.0, gy)
	R.add_flat(gb + Vector2(8, 0), 9.0, 18.0, gy)
	if not R.game.is_empty() and R.game.get("bench", false):
		_plan_bench()


# ------------------------------------------------------------------------------
#  Round the mountain airport (Dave: "make sure to add the building assets -
#  barns, towers, fire stations - on the map"). Behind the bench, up the
#  access track, the fire base: the volunteer fire station, its avgas tanks
#  and a quonset. The lookout on the summit above the airport. Down on the
#  valley floors, homesteads: pole barns and a water tower.
# ------------------------------------------------------------------------------
var _bench := []           # [asset, position, yaw]

func _plan_bench() -> void:
	var c: Vector2 = R.game["center"]
	var a: float = R.game["angle"]
	var half: float = R.game["half"]
	var u := Vector2(cos(a), sin(a))          # along the runway, toward the cliff
	var v := Vector2(-u.y, u.x)
	# the fire base: beside the road where it runs in level onto the airport
	# (a pad at the airport's level, the road on one side, the square ahead)
	var lv: float = R.game["level"]
	var road: PackedVector3Array = R.town.mountain_road if R.town != null else PackedVector3Array()
	var fs := Vector3.INF
	var face_down := 0.0
	if road.size() > 8:
		var e_in := road[road.size() - 1]
		var k := road.size() - 1
		while k > 1 and Vector2(road[k].x - e_in.x, road[k].z - e_in.z).length() < 70.0:
			k -= 1
		var a3 := road[k]
		var dir := Vector2(e_in.x - a3.x, e_in.z - a3.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		# the side away from the square's middle
		if (Vector2(a3.x, a3.z) + side * 10.0).distance_to(c) < Vector2(a3.x, a3.z).distance_to(c):
			side = -side
		# the station's origin is its front middle, its doors (-Z) to the road,
		# the building back from there (+Z, away from the road)
		var fp := Vector2(a3.x, a3.z) + side * 11.0
		face_down = atan2(side.x, side.y)
		R.add_pad(fp + side * 9.0, Vector2(30.0, 13.0), -face_down, lv, false)
		fs = Vector3(fp.x, lv, fp.y)
	else:
		var back := c - u * (half + 135.0)
		face_down = atan2(u.x, u.y) + PI
		fs = _site(Vector3(back.x, _g(back.x, back.y), back.y), 30.0, 3.0)
	_bench.append(["civic:3", fs, face_down])
	var rgt := Vector3(cos(face_down), 0, -sin(face_down))
	var t1 := fs + rgt * 12.0
	_bench.append(["town_props:2", t1, face_down + PI * 0.5])
	_bench.append(["town_props:2", t1 + rgt * 4.5, face_down + PI * 0.5])
	var q := fs - rgt * 16.0
	_bench.append(["town_props:0", q, face_down])
	# the fire lookout on the summit right above the airport
	# (off to the side: the approach behind the runway's west end stays clear)
	var v2 := Vector2(-u.y, u.x)
	var pk := _peak(c + v2 * 650.0 - u * 150.0, 450.0)
	var pk2 := _peak(c - v2 * 650.0 - u * 150.0, 450.0)
	if pk2.y > pk.y:
		pk = pk2
	_bench.append(["lookout_tower", _site(pk, 16.0, 2.0), atan2(u.x, u.y)])
	# homesteads on the valley floors: pole barns, a water tower
	var farms := [[R.px(Vector2(560, 560)), 0.6], [R.px(Vector2(330, 430)), 2.1], [R.px(Vector2(620, 590)), -0.4]]
	for f in farms:
		var fp: Vector2 = _farm_spot(f[0])
		var yaw: float = f[1]
		var site := _site(Vector3(fp.x, _g(fp.x, fp.y), fp.y), 34.0, 0.5)
		var b := Basis(Vector3.UP, yaw)
		_bench.append(["pole_barn", site + b * Vector3(-9, 0, 0), yaw])
		_bench.append(["pole_barn", site + b * Vector3(9, 0, 4), yaw])
		_bench.append(["town_props:4", site + b * Vector3(0, 0, 18), yaw])
	print("landmarks: fire base %s, lookout %s" % [str(fs.round()), str(pk.round())])


## Level a site: flat at the point's height less `shave` out to r. Returns the
## levelled point.
func _site(p: Vector3, r: float, shave: float) -> Vector3:
	var lvl := p.y - shave
	var fall := maxf(r * 2.0, 70.0)
	R.add_flat(Vector2(p.x, p.z), r, fall, lvl)
	return Vector3(p.x, lvl, p.z)


const AssetLib = preload("res://scripts/assets/asset_lib.gd")
const Glow = preload("res://scripts/assets/glow.gd")


## One of the built-once assets (scripts/assets/) standing at p, turned yaw.
func _place(asset: String, p: Vector3, yaw: float, key: String) -> void:
	var n := AssetLib.get_asset(asset)
	n.position = p
	n.rotation.y = yaw
	add_child(n)
	spots[key] = p


func _downhill_yaw(p: Vector3) -> float:
	var gx := _g(p.x + 25.0, p.z) - _g(p.x - 25.0, p.z)
	var gz := _g(p.x, p.z + 25.0) - _g(p.x, p.z - 25.0)
	return atan2(-gx, -gz)


func build() -> void:
	var rel: Vector3 = _at["relay"]
	_place("radio_mast", _at["mast"], 0.3, "radio_mast")
	_place("lookout_tower", _at["tower"], 0.8, "lookout_tower")
	_lookout_ground(_at["ground_cab"])
	_place("microwave_relay", rel, 0.0, "microwave_relay")
	var rf: Vector3 = _at["reflector"]
	_place("passive_reflector", rf, atan2(rel.x - rf.x, rel.z - rf.z) + PI + 0.6, "reflector")
	var mp: Vector3 = _at["mine"]
	_place("headframe", mp, _downhill_yaw(mp), "mine")
	var lp: Vector3 = _at["lighthouse"]
	# the sea toward the asset's -Z: face away from the land (uphill)
	_place("lighthouse", lp, _downhill_yaw(lp) + PI, "lighthouse")
	_place("bridge:%d" % (1000 + int(_at["gorge_span"])), _at["gorge_bridge"], 0.0, "gorge_bridge")
	for i in range(_bench.size()):
		var e: Array = _bench[i]
		var bp: Vector3 = e[1]
		bp.y = _g(bp.x, bp.z)              # on the ground as it finally lies
		_place(e[0], bp, e[2], "bench_%d" % i)
	_glacier()
	_fossils(_at["fossils"])
	_finish()


## A homestead's spot near c: on the valley floor, off the river (90 m+),
## clear of the roads and the town, the flattest found.
func _farm_spot(c: Vector2) -> Vector2:
	var rivers: Array = R.town._river_lines(Rect2(c - Vector2(500, 500), Vector2(1000, 1000))) if R.town != null else []
	var best := c
	var bs := 1e9
	for i in range(-6, 7):
		for j in range(-6, 7):
			var p := c + Vector2(i, j) * 45.0
			var cv: Vector4 = R._carve(p.x, p.y)
			if cv.y < 0.5:
				continue
			var rd := 1e9
			for rl in rivers:
				rd = minf(rd, R.town._dist_poly(p, rl))
			if rd < 90.0:
				continue
			if R._town_box.grow(60.0).has_point(p) or R._near_road(p.x, p.y, 40.0):
				continue
			var sl := absf(_g(p.x + 20.0, p.y) - _g(p.x - 20.0, p.y)) + absf(_g(p.x, p.y + 20.0) - _g(p.x, p.y - 20.0))
			var sc := sl + p.distance_to(c) * 0.01
			if sc < bs:
				bs = sc
				best = p
	return best


# ------------------------------------------------------------------------------
#  Helpers
# ------------------------------------------------------------------------------
func _g(x: float, z: float) -> float:
	return float(R.height(x, z))


## The highest ground within r of c (sampled), as a world point.
func _peak(c: Vector2, r: float) -> Vector3:
	var best := Vector3(c.x, -1e9, c.y)
	var n := 18
	for i in range(n + 1):
		for j in range(n + 1):
			var p := c + Vector2(-r + 2.0 * r * i / n, -r + 2.0 * r * j / n)
			if p.distance_to(c) > r:
				continue
			var h := _g(p.x, p.y)
			if h > best.y:
				best = Vector3(p.x, h, p.y)
	# refine round the best one
	var c2 := Vector2(best.x, best.z)
	var r2 := 2.0 * r / n
	for i2 in range(9):
		for j2 in range(9):
			var p2 := c2 + Vector2(-r2 + 2.0 * r2 * i2 / 8.0, -r2 + 2.0 * r2 * j2 / 8.0)
			var h2 := _g(p2.x, p2.y)
			if h2 > best.y:
				best = Vector3(p2.x, h2, p2.y)
	return best


func _rod(kk: MeshKit, a: Vector3, b: Vector3, r: float, c: Color, sides: int = 5) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	kk.cylinder(Transform3D(Basis(x, y, z), a), r, r, l, sides, c, false)


func _box(kk: MeshKit, at: Vector3, s: Vector3, c: Color, yaw: float = 0.0) -> void:
	kk.box(Transform3D(Basis(Vector3.UP, yaw), at), s, c)


## A pad levelled into the ground under a building: a slab down to the lowest corner.
func _pad(at: Vector3, s: Vector2, yaw: float, c: Color) -> float:
	var b := Basis(Vector3.UP, yaw)
	var lo := 1e9
	var hi := -1e9
	for cx in [-0.5, 0.5]:
		for cz in [-0.5, 0.5]:
			var p := at + b * Vector3(s.x * cx, 0, s.y * cz)
			var h := _g(p.x, p.z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var top := hi + 0.15
	_box(k, Vector3(at.x, (top + lo - 1.0) * 0.5, at.z), Vector3(s.x, top - lo + 1.0, s.y), c, yaw)
	return top


func _finish() -> void:
	add_child(k.instance("Landmarks"))
	var gi := k_glass.instance("LandmarkGlass")
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.vertex_color_is_srgb = true
	gm.roughness = 0.05
	gm.metallic = 0.6
	gi.material_override = gm
	add_child(gi)
	var ii := k_ice.instance("Glacier")
	var im := StandardMaterial3D.new()
	im.vertex_color_use_as_albedo = true
	im.vertex_color_is_srgb = true
	im.roughness = 0.35
	im.metallic_specular = 0.7
	im.rim_enabled = true
	im.rim = 0.3
	ii.material_override = im
	add_child(ii)
	var ci := k_clear.instance("ClearIce")
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.vertex_color_is_srgb = true
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.roughness = 0.1
	cm.metallic_specular = 0.9
	ci.material_override = cm
	ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ci)
	var mi := k_mesh.instance("ChainLink")
	var mm := StandardMaterial3D.new()
	mm.vertex_color_use_as_albedo = true
	mm.vertex_color_is_srgb = true
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mm.metallic = 0.5
	mm.roughness = 0.5
	mi.material_override = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(0.9, 0.1, 0.05)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.12, 0.05)
	_beacon_mat.emission_energy_multiplier = 6.0
	var bi := k_beacon.instance("Beacons")
	bi.material_override = _beacon_mat
	add_child(bi)
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(1.0, 0.95, 0.8)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.92, 0.7)
	_lamp_mat.emission_energy_multiplier = 4.0
	var li := k_lamp.instance("Lantern")
	li.material_override = _lamp_mat
	add_child(li)


func _process(dt: float) -> void:
	_t += dt
	Glow.tick(_t)
	if _beacon_mat != null:
		# the mast's beacons flash about 40 a minute
		var on := fmod(_t, 1.5) < 0.75
		_beacon_mat.emission_energy_multiplier = 6.0 if on else 0.0
		_beacon_mat.albedo_color = Color(0.9, 0.1, 0.05) if on else Color(0.35, 0.05, 0.03)
	if _lamp_mat != null:
		# the lighthouse: a flash every 6 s
		var f := fmod(_t, 6.0)
		_lamp_mat.emission_energy_multiplier = 12.0 if f < 0.5 else 0.6


# ------------------------------------------------------------------------------
#  The radio mast: a 150 m guyed lattice mast (triangular, 1.5 m faces), painted
#  in red and white bands, guy wires out three ways at three levels, beacons at
#  the top and the middle; the transmitter building, a chain-link fence, the
#  generator, a dish
# ------------------------------------------------------------------------------
func _radio_mast(p: Vector3) -> void:
	spots["radio_mast"] = p
	var H := 150.0
	var f := 1.5
	var base := p + Vector3(0, -0.5, 0)
	var legs: Array = []
	for i in range(3):
		var a := TAU * float(i) / 3.0
		legs.append(Vector3(cos(a), 0, sin(a)) * f / sqrt(3.0))
	var bay := 1.5
	var nb := int(H / bay)
	for b in range(nb):
		var y0 := bay * float(b)
		var y1 := y0 + bay
		var band := int(y0 / (H / 7.0))
		var col := RED if band % 2 == 0 else WHITE
		for i in range(3):
			var l0: Vector3 = legs[i]
			var l1: Vector3 = legs[(i + 1) % 3]
			_rod(k, base + l0 + Vector3(0, y0, 0), base + l0 + Vector3(0, y1, 0), 0.06, col, 4)
			_rod(k, base + l0 + Vector3(0, y0, 0), base + l1 + Vector3(0, y1, 0), 0.025, col, 3)
			_rod(k, base + l0 + Vector3(0, y1, 0), base + l1 + Vector3(0, y1, 0), 0.025, col, 3)
	# the top: antenna mast, beacon
	_rod(k, base + Vector3(0, H, 0), base + Vector3(0, H + 8.0, 0), 0.12, RED, 6)
	k_beacon.cylinder(Transform3D(Basis.IDENTITY, base + Vector3(0, H + 8.0, 0)), 0.35, 0.25, 0.6, 8, RED)
	for lv in [H * 0.5, H * 0.25]:
		for i2 in range(3):
			var lp: Vector3 = legs[i2]
			k_beacon.cylinder(Transform3D(Basis.IDENTITY, base + lp * 1.3 + Vector3(0, lv, 0)), 0.22, 0.15, 0.4, 6, RED)
	# FM bays and a couple of horns up near the top
	for j in range(6):
		var yy := H - 4.0 - 3.0 * float(j)
		_rod(k, base + Vector3(0, yy, 0), base + Vector3(1.6, yy, 0), 0.05, STEEL, 4)
		k.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), base + Vector3(1.6, yy, 0)), 0.4, 0.4, 0.06, 8, STEEL, true)
	# guy wires: three ways, three levels, to concrete anchors
	for i3 in range(3):
		var a3 := TAU * float(i3) / 3.0 + PI / 3.0
		var dirv := Vector3(cos(a3), 0, sin(a3))
		for lv2 in [0.3, 0.6, 0.92]:
			var top := base + Vector3(0, H * lv2, 0)
			var out := H * 0.55 + 10.0
			var ax := p + dirv * out
			var ay := _g(ax.x, ax.z)
			_rod(k, top, Vector3(ax.x, ay + 0.6, ax.z), 0.03, Color(0.3, 0.3, 0.3), 3)
		var an := p + dirv * (H * 0.55 + 10.0)
		_box(k, Vector3(an.x, _g(an.x, an.z) + 0.3, an.z), Vector3(2.0, 1.2, 2.0), CONC, a3)
	_box(k, base + Vector3(0, 0.5, 0), Vector3(3.0, 1.6, 3.0), CONC)
	# the transmitter building: block, flat roof, a steel door, the coax bridge
	var bp := p + Vector3(16, 0, 6)
	var top2 := _pad(bp, Vector2(9, 6), 0.2, CONC)
	_box(k, Vector3(bp.x, top2 + 1.6, bp.z), Vector3(8, 3.2, 5), Color(0.80, 0.78, 0.72), 0.2)
	_box(k, Vector3(bp.x, top2 + 3.3, bp.z), Vector3(8.4, 0.25, 5.4), Color(0.35, 0.33, 0.30), 0.2)
	var bb := Basis(Vector3.UP, 0.2)
	_box(k, Vector3(bp.x, top2, bp.z) + bb * Vector3(-4.02, 1.05, 0), Vector3(0.05, 2.1, 1.0), Color(0.45, 0.30, 0.20), 0.2)
	_rod(k, Vector3(bp.x, top2 + 2.6, bp.z) + bb * Vector3(-4.0, 0, 1.0), base + Vector3(0.8, 3.0, 0), 0.15, GALV, 6)
	# a dish on a pole by it
	var dp := bp + bb * Vector3(5.5, 0, 3.0)
	var dy := _g(dp.x, dp.z)
	_rod(k, Vector3(dp.x, dy, dp.z), Vector3(dp.x, dy + 3.2, dp.z), 0.08, GALV)
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, 1.2), Vector3(dp.x, dy + 3.4, dp.z)), 0.1, 1.5, 0.6, 14, WHITE, true)
	# the generator shed and the propane tank
	var gp := bp + bb * Vector3(0, 0, -6.5)
	_box(k, Vector3(gp.x, _g(gp.x, gp.z) + 1.1, gp.z), Vector3(3, 2.2, 2.5), Color(0.45, 0.50, 0.42), 0.2)
	var tp := bp + bb * Vector3(-6, 0, -5)
	k.rbox(Transform3D(bb, Vector3(tp.x, _g(tp.x, tp.z) + 0.8, tp.z)), Vector3(1.2, 1.2, 3.2), WHITE, 0.55)
	# the chain-link fence round it all
	_fence(p + Vector3(6, 0, 2), Vector2(32, 26), 0.2)


func _fence(c: Vector3, s: Vector2, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var corners := [Vector3(-s.x, 0, -s.y) * 0.5, Vector3(s.x, 0, -s.y) * 0.5, Vector3(s.x, 0, s.y) * 0.5, Vector3(-s.x, 0, s.y) * 0.5]
	for i in range(4):
		var a: Vector3 = c + b * (corners[i] as Vector3)
		var e: Vector3 = c + b * (corners[(i + 1) % 4] as Vector3)
		var n := maxi(int(a.distance_to(e) / 3.0), 1)
		var prev := Vector3.ZERO
		for j in range(n + 1):
			var q := a.lerp(e, float(j) / n)
			q.y = _g(q.x, q.z)
			_rod(k, q, q + Vector3(0, 2.2, 0), 0.04, GALV, 4)
			if j > 0:
				_rod(k, prev + Vector3(0, 2.15, 0), q + Vector3(0, 2.15, 0), 0.02, GALV, 3)
				# the mesh: a see-through-ish grey panel (thin)
				var mid := (prev + q) * 0.5 + Vector3(0, 1.1, 0)
				var d := q - prev
				k_mesh.quad(prev + Vector3(0, 0.05, 0), q + Vector3(0, 0.05, 0), q + Vector3(0, 2.15, 0), prev + Vector3(0, 2.15, 0), Color(0.70, 0.71, 0.70, 0.35), Vector3(d.z, 0, -d.x))
				var _m := mid
			prev = q


# ------------------------------------------------------------------------------
#  Fire lookout, steel tower: four galvanised legs tapering up 18 m, X-braced
#  every 3 m, stairs inside in flights to a trap in the floor; the 14 ft cab,
#  windows all round, shutters propped out over them, a hip roof with the
#  lightning rod; the catwalk and its rail. And the outhouse and woodpile below.
# ------------------------------------------------------------------------------
func _lookout_tower(p: Vector3) -> void:
	spots["lookout_tower"] = p
	var H := 18.0
	var b0 := 3.6
	var b1 := 2.0
	var y0 := p.y - 0.3
	var leg := func(i: int, t: float) -> Vector3:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var sz := -1.0 if i < 2 else 1.0
		var hw := lerpf(b0, b1, t)
		return Vector3(p.x + sx * hw, y0 + H * t, p.z + sz * hw)
	var order := [0, 1, 3, 2]
	for i in range(4):
		_rod(k, leg.call(i, 0.0), leg.call(i, 1.0), 0.08, GALV, 5)
		k.box(Transform3D(Basis.IDENTITY, leg.call(i, 0.0) + Vector3(0, 0.3, 0)), Vector3(0.7, 0.8, 0.7), CONC)
	for s in range(6):
		var t0 := float(s) / 6.0
		var t1 := float(s + 1) / 6.0
		for e in range(4):
			var i0: int = order[e]
			var i1: int = order[(e + 1) % 4]
			_rod(k, leg.call(i0, t0), leg.call(i1, t1), 0.03, GALV, 3)
			_rod(k, leg.call(i1, t0), leg.call(i0, t1), 0.03, GALV, 3)
			_rod(k, leg.call(i0, t1), leg.call(i1, t1), 0.04, GALV, 3)
	# the stairs: flights zig-zagging up the middle, landings
	var nfl := 6
	for fl in range(nfl):
		var ya := y0 + H * float(fl) / nfl
		var yb := y0 + H * float(fl + 1) / nfl
		var sd := 0.5 if fl % 2 == 0 else -0.5
		var a := Vector3(p.x - 0.8 * sd * 2.0, ya, p.z + sd)
		var bpt := Vector3(p.x + 0.8 * sd * 2.0, yb, p.z + sd)
		_rod(k, a + Vector3(0, 0, 0.35), bpt + Vector3(0, 0, 0.35), 0.04, GALV, 3)
		_rod(k, a - Vector3(0, 0, 0.35), bpt - Vector3(0, 0, 0.35), 0.04, GALV, 3)
		for st in range(10):
			var q := a.lerp(bpt, (float(st) + 0.5) / 10.0)
			_box(k, q, Vector3(0.22, 0.04, 0.7), Color(0.5, 0.4, 0.28))
		_box(k, Vector3(bpt.x, yb - 0.03, p.z), Vector3(0.9, 0.06, 1.8), Color(0.5, 0.4, 0.28))
	_cab(Vector3(p.x, y0 + H, p.z), 4.3, true)
	# below: the outhouse and a woodpile
	var oh := p + Vector3(9, 0, 5)
	_box(k, Vector3(oh.x, _g(oh.x, oh.z) + 1.1, oh.z), Vector3(1.2, 2.2, 1.2), Color(0.45, 0.36, 0.25), 0.4)
	var wp := p + Vector3(-7, 0, 6)
	for w in range(5):
		_rod(k, Vector3(wp.x - 1.2, _g(wp.x, wp.z) + 0.15 + 0.25 * float(w), wp.z), Vector3(wp.x + 1.2, _g(wp.x, wp.z) + 0.15 + 0.25 * float(w), wp.z), 0.13, Color(0.5, 0.38, 0.26), 6)


## A lookout cab: a square floor, windows all round over a wainscot, the shutters
## hinged at the top and propped out (awnings), a hip roof, a catwalk round it
## with a rail; the fire finder on its stand inside. Centre of the floor at c.
func _cab(c: Vector3, w: float, catwalk: bool) -> void:
	var hw := w * 0.5
	var paint := Color(0.82, 0.80, 0.72)
	var trim := Color(0.20, 0.33, 0.22)
	_box(k, c + Vector3(0, -0.1, 0), Vector3(w + (2.0 if catwalk else 0.0), 0.2, w + (2.0 if catwalk else 0.0)), Color(0.5, 0.4, 0.28))
	for s in range(4):
		var yaw := PI * 0.5 * float(s)
		var bas := Basis(Vector3.UP, yaw)
		# wainscot up to 1 m, the window band to 2.2, a strip above
		_box(k, c + bas * Vector3(0, 0.5, -hw), Vector3(w, 1.0, 0.12), paint, yaw)
		k_glass.box(Transform3D(bas, c + bas * Vector3(0, 1.6, -hw)), Vector3(w - 0.1, 1.2, 0.04), Color(0.18, 0.22, 0.25))
		for m in range(5):
			_box(k, c + bas * Vector3(-hw + w * float(m) / 4.0, 1.6, -hw - 0.02), Vector3(0.08, 1.2, 0.08), trim, yaw)
		_box(k, c + bas * Vector3(0, 2.4, -hw), Vector3(w, 0.4, 0.12), paint, yaw)
		# the shutter propped out over the windows
		k.box(Transform3D(bas * Basis(Vector3.RIGHT, -1.0), c + bas * Vector3(0, 2.35, -hw - 0.55)), Vector3(w + 0.1, 1.2, 0.05), trim)
	# the hip roof and the lightning rod
	for s2 in range(4):
		var b2 := Basis(Vector3.UP, PI * 0.5 * float(s2))
		var e0 := c + b2 * Vector3(-hw - 0.4, 2.6, -hw - 0.4)
		var e1 := c + b2 * Vector3(hw + 0.4, 2.6, -hw - 0.4)
		k.tri(e0, e1, c + Vector3(0, 3.8, 0), trim, b2 * Vector3(0, 0.6, -1))
		k.tri(e0, c + Vector3(0, 3.8, 0), e1, trim.darkened(0.3), b2 * Vector3(0, -0.6, 1))
	_rod(k, c + Vector3(0, 3.8, 0), c + Vector3(0, 5.0, 0), 0.02, Color(0.7, 0.5, 0.25), 4)
	# the fire finder on its stand in the middle
	_rod(k, c, c + Vector3(0, 1.1, 0), 0.06, WOOD)
	k.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, 1.1, 0)), 0.4, 0.4, 0.06, 16, Color(0.6, 0.5, 0.3), true)
	if catwalk:
		var cw := hw + 1.0
		for s3 in range(4):
			var b3 := Basis(Vector3.UP, PI * 0.5 * float(s3))
			_rod(k, c + b3 * Vector3(-cw, 1.0, -cw), c + b3 * Vector3(cw, 1.0, -cw), 0.03, GALV, 4)
			_rod(k, c + b3 * Vector3(-cw, 0.5, -cw), c + b3 * Vector3(cw, 0.5, -cw), 0.02, GALV, 4)
			for pp in range(4):
				var q := c + b3 * Vector3(-cw + 2.0 * cw * float(pp) / 4.0, 0, -cw)
				_rod(k, q, q + Vector3(0, 1.0, 0), 0.025, GALV, 4)


# ------------------------------------------------------------------------------
#  Fire lookout, ground cab: the cab on a rock-and-mortar base right on the summit
# ------------------------------------------------------------------------------
func _lookout_ground(p: Vector3) -> void:
	spots["lookout_ground"] = p
	var top := _pad(p, Vector2(6.0, 6.0), 0.3, Color(0.48, 0.46, 0.43))
	_cab(Vector3(p.x, top, p.z), 4.3, true)
	# the cistern and the radio aerial
	_rod(k, Vector3(p.x + 3.4, top, p.z - 3.4), Vector3(p.x + 3.4, top + 7.0, p.z - 3.4), 0.03, GALV, 4)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x - 6, _g(p.x - 6, p.z + 2), p.z + 2)), 1.0, 1.0, 1.4, 12, Color(0.42, 0.40, 0.36), true)


# ------------------------------------------------------------------------------
#  Microwave relay: a 30 m square lattice tower with drum antennas under white
#  radome caps aimed down the valleys, the equipment building and generator.
#  And the passive reflector: a big flat billboard of steel on a lower ridge,
#  bouncing the beam round the mountain.
# ------------------------------------------------------------------------------
func _microwave(p: Vector3) -> void:
	spots["microwave_relay"] = p
	var H := 30.0
	var hw0 := 2.5
	var hw1 := 1.2
	var y0 := p.y - 0.3
	for s in range(8):
		var t0 := float(s) / 8.0
		var t1 := float(s + 1) / 8.0
		for i in range(4):
			var sx := -1.0 if i % 2 == 0 else 1.0
			var sz := -1.0 if i < 2 else 1.0
			var a := Vector3(p.x + sx * lerpf(hw0, hw1, t0), y0 + H * t0, p.z + sz * lerpf(hw0, hw1, t0))
			var b := Vector3(p.x + sx * lerpf(hw0, hw1, t1), y0 + H * t1, p.z + sz * lerpf(hw0, hw1, t1))
			_rod(k, a, b, 0.09, GALV, 4)
			var sx2 := sz
			var sz2 := -sx
			var c2 := Vector3(p.x + sx2 * lerpf(hw0, hw1, t1), y0 + H * t1, p.z + sz2 * lerpf(hw0, hw1, t1))
			_rod(k, a, c2, 0.035, GALV, 3)
			_rod(k, b, c2, 0.04, GALV, 3)
	# the drums: aimed at the radio mast, the town, down the valleys
	var aims := [spots.get("radio_mast", p + Vector3(1000, 0, 3000)), Vector3(0, 300, 0), p + Vector3(-4000, 0, -2000), p + Vector3(3000, 0, -3000)]
	for j in range(aims.size()):
		var at := p + Vector3(0, H - 2.5 - 3.2 * float(j), 0)
		var d: Vector3 = ((aims[j] as Vector3) - at)
		d.y = 0.0
		d = d.normalized()
		var o := at + d * 1.6
		var bas := Basis.looking_at(-d, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
		k.cylinder(Transform3D(bas, o - d * 0.6), 1.5, 1.5, 0.6, 18, Color(0.75, 0.75, 0.73), true)
		k.cylinder(Transform3D(bas, o), 1.5, 1.35, 0.15, 18, WHITE, true)
	_beacon_light(Vector3(p.x, y0 + H + 0.5, p.z))
	var bp := p + Vector3(10, 0, 4)
	var top := _pad(bp, Vector2(8, 6), 0.0, CONC)
	_box(k, Vector3(bp.x, top + 1.5, bp.z), Vector3(7, 3, 5), Color(0.78, 0.76, 0.70))
	_box(k, Vector3(bp.x, top + 3.1, bp.z), Vector3(7.3, 0.2, 5.3), Color(0.35, 0.33, 0.30))
	_rod(k, Vector3(bp.x - 3.5, top + 2.6, bp.z), Vector3(p.x, p.y + 2.6, p.z), 0.2, GALV, 6)
	_fence(p + Vector3(4, 0, 2), Vector2(24, 18), 0.0)


func _beacon_light(at: Vector3) -> void:
	k_beacon.cylinder(Transform3D(Basis.IDENTITY, at), 0.3, 0.22, 0.5, 8, RED)


func _reflector(p: Vector3, toward: Vector3) -> void:
	spots["reflector"] = p
	var d := toward - p
	d.y = 0.0
	var yaw := atan2(d.x, d.z) + 0.6          # turned to bounce the beam round into the next valley
	var bas := Basis(Vector3.UP, yaw)
	var W := 12.0
	var Hh := 9.0
	var y0 := p.y
	# the legs and the back frame
	for sx in [-0.45, -0.15, 0.15, 0.45]:
		var foot := p + bas * Vector3(W * sx, 0, 1.5)
		var fy := _g(foot.x, foot.z)
		_rod(k, Vector3(foot.x, fy - 0.3, foot.z), p + bas * Vector3(W * sx, 0, 0) + Vector3(0, y0 - p.y + 2.0 + Hh, 0), 0.12, GALV, 4)
		var foot2 := p + bas * Vector3(W * sx, 0, -2.5)
		_rod(k, Vector3(foot2.x, _g(foot2.x, foot2.z) - 0.3, foot2.z), p + bas * Vector3(W * sx, 0, 0) + Vector3(0, 2.0 + Hh * 0.6, 0), 0.1, GALV, 4)
	# the face: a grid of steel panels, bright galvanised (it flashes in the sun)
	for i in range(4):
		for j in range(3):
			var cpos := p + bas * Vector3(-W * 0.5 + W * (float(i) + 0.5) / 4.0, 2.0 + Hh * (float(j) + 0.5) / 3.0, 0.15)
			k_glass.box(Transform3D(bas, cpos), Vector3(W / 4.0 - 0.06, Hh / 3.0 - 0.06, 0.08), Color(0.78, 0.80, 0.80))


# ------------------------------------------------------------------------------
#  The mine on the hillside over the mine town: a timber headframe with its
#  sheave wheel, the hoist house, the ore bin over the track, the waste dump
#  spilling grey-orange down the slope, the portal of the adit
# ------------------------------------------------------------------------------
func _mine_spot(c: Vector2) -> Vector3:
	# up the valley's wall till the ground's 70 m above the floor
	var floor_y := _g(c.x, c.y)
	var p := Vector3(c.x, floor_y, c.y)
	var best_s := 1e9
	for i in range(41):
		for j in range(41):
			var q := c + Vector2(-400.0 + 20.0 * i, -400.0 + 20.0 * j)
			var h := _g(q.x, q.y)
			var sc := absf(h - floor_y - 30.0) + q.distance_to(c) * 0.06
			if sc < best_s:
				best_s = sc
				p = Vector3(q.x, h, q.y)
	return p


func _mine(p: Vector3) -> void:
	spots["mine"] = p
	# which way is downhill
	var gx := _g(p.x + 10.0, p.z) - _g(p.x - 10.0, p.z)
	var gz := _g(p.x, p.z + 10.0) - _g(p.x, p.z - 10.0)
	var down := Vector3(-gx, 0, -gz).normalized()
	var yaw := atan2(down.x, down.z)
	var bas := Basis(Vector3.UP, yaw)
	var top := _pad(p, Vector2(14, 14), yaw, Color(0.50, 0.44, 0.36))
	var timber := Color(0.36, 0.27, 0.19)
	# the headframe: four posts leaning in to 20 m, cross-braced, the back legs
	# raking down behind to take the pull of the hoist
	var Hh := 20.0
	var cpt := Vector3(p.x, top, p.z)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_rod(k, cpt + bas * Vector3(2.4 * sx, 0, 2.4 * sz), cpt + bas * Vector3(1.0 * sx, Hh, 1.0 * sz), 0.18, timber, 4)
		_rod(k, cpt + bas * Vector3(1.6 * sx, 0, -9.0), cpt + bas * Vector3(1.0 * sx, Hh - 1.0, -0.8), 0.18, timber, 4)
	for lv in range(5):
		var t := float(lv + 1) / 5.0
		var hw := lerpf(2.4, 1.0, t)
		var yy := Hh * t
		for e in range(4):
			var bb := Basis(Vector3.UP, PI * 0.5 * float(e))
			_rod(k, cpt + bas * (bb * Vector3(-hw, yy, -hw)), cpt + bas * (bb * Vector3(hw, yy, -hw)), 0.1, timber, 4)
	# the sheave wheel at the top
	k.cylinder(Transform3D(bas * Basis(Vector3.FORWARD, PI * 0.5), cpt + bas * Vector3(-0.2, Hh + 1.0, 0)), 1.4, 1.4, 0.25, 18, Color(0.25, 0.24, 0.22), true)
	_box(k, cpt + Vector3(0, Hh + 0.1, 0), Vector3(2.4, 0.3, 2.4), timber, yaw)
	# the hoist house behind: a long tin shed, a tall stack
	var hh := cpt + bas * Vector3(0, 0, -14.0)
	var htop := _pad(Vector3(hh.x, 0, hh.z), Vector2(9, 12), yaw, Color(0.5, 0.44, 0.36))
	_box(k, Vector3(hh.x, htop + 2.5, hh.z), Vector3(8, 5, 11), Color(0.55, 0.30, 0.20), yaw)
	_box(k, Vector3(hh.x, htop + 5.3, hh.z), Vector3(8.6, 0.6, 11.6), Color(0.45, 0.45, 0.44), yaw)
	_rod(k, Vector3(hh.x, htop + 5.0, hh.z) + bas * Vector3(2.5, 0, -3.0), Vector3(hh.x, htop + 12.0, hh.z) + bas * Vector3(2.5, 0, -3.0), 0.4, Color(0.2, 0.2, 0.2), 8)
	# the ore bin downhill on stilts over the track, and the waste dump
	var ob := cpt + bas * Vector3(0, 0, 10.0)
	var oy := _g(ob.x, ob.z)
	for sx2 in [-1.5, 1.5]:
		for sz2 in [-1.5, 1.5]:
			var lp := ob + bas * Vector3(sx2, 0, sz2)
			_rod(k, Vector3(lp.x, _g(lp.x, lp.z) - 0.3, lp.z), Vector3(lp.x, maxf(oy, top) + 5.0, lp.z), 0.15, timber, 4)
	_box(k, Vector3(ob.x, maxf(oy, top) + 7.0, ob.z), Vector3(4.2, 4.0, 4.2), Color(0.42, 0.32, 0.22), yaw)
	var dump := cpt + bas * Vector3(9.0, 0, 6.0)
	var dy := _g(dump.x, dump.z)
	k.cylinder(Transform3D(bas * Basis(Vector3.RIGHT, 0.35), Vector3(dump.x, dy - 6.0, dump.z) + down * 6.0), 26.0, 3.0, 16.0, 16, Color(0.58, 0.48, 0.38), true)
	k.cylinder(Transform3D(bas * Basis(Vector3.RIGHT, 0.4), Vector3(dump.x, dy - 7.0, dump.z) + down * 18.0), 18.0, 2.0, 10.0, 14, Color(0.66, 0.50, 0.34), true)


# ------------------------------------------------------------------------------
#  The lighthouse on the point by the harbor: a white tower with a red band, the
#  gallery and the lantern, the keeper's house beside it
# ------------------------------------------------------------------------------
func _lighthouse_spot(near: Vector2) -> Vector3:
	var best := Vector3(near.x, 0, near.y)
	var bs := 1e9
	for i in range(31):
		for j in range(31):
			var q := near + Vector2(-500.0 + 33.0 * i, -500.0 + 33.0 * j)
			var h := _g(q.x, q.y)
			var cs: float = R._coast_side(q.x, q.y)
			if h < 4.0 or cs > -15.0:
				continue
			var sc := absf(cs + 30.0) + absf(h - 10.0) * 2.0
			if sc < bs:
				bs = sc
				best = Vector3(q.x, h, q.y)
	return best


func _lighthouse(p: Vector3) -> void:
	spots["lighthouse"] = p
	var top := _pad(p, Vector2(8, 8), 0.0, Color(0.55, 0.53, 0.50))
	var H := 16.0
	var c := Vector3(p.x, top, p.z)
	k.cylinder(Transform3D(Basis.IDENTITY, c), 2.4, 1.6, H * 0.45, 20, WHITE, true)
	k.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, H * 0.45, 0)), 1.6, 1.4, H * 0.2, 20, RED, true)
	k.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, H * 0.65, 0)), 1.4, 1.2, H * 0.35, 20, WHITE, true)
	k.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, H, 0)), 2.0, 2.0, 0.25, 20, Color(0.15, 0.15, 0.15), true)
	for r in range(16):
		var a := TAU * float(r) / 16.0
		_rod(k, c + Vector3(cos(a) * 1.95, H + 0.25, sin(a) * 1.95), c + Vector3(cos(a) * 1.95, H + 1.2, sin(a) * 1.95), 0.025, Color(0.15, 0.15, 0.15), 4)
	k_glass.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, H + 0.25, 0)), 1.1, 1.1, 1.8, 12, Color(0.55, 0.62, 0.62), false)
	k_lamp.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, H + 0.6, 0)), 0.45, 0.45, 1.0, 10, Color(1, 0.95, 0.8), true)
	k.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, H + 2.05, 0)), 1.3, 0.1, 1.0, 16, RED, true)
	# the keeper's house: white clapboard, red roof
	var hp := p + Vector3(9, 0, 3)
	var ht := _pad(hp, Vector2(8, 6), 0.0, Color(0.55, 0.53, 0.50))
	_box(k, Vector3(hp.x, ht + 1.5, hp.z), Vector3(7.5, 3.0, 5.5), WHITE)
	for sz in [-1.0, 1.0]:
		k.quad(Vector3(hp.x - 4.0, ht + 3.0, hp.z + sz * 3.0), Vector3(hp.x + 4.0, ht + 3.0, hp.z + sz * 3.0), Vector3(hp.x + 4.0, ht + 5.0, hp.z), Vector3(hp.x - 4.0, ht + 5.0, hp.z), RED, Vector3(0, 1, sz))
	for sx in [-1.0, 1.0]:
		k.tri(Vector3(hp.x + sx * 3.75, ht + 3.0, hp.z - 2.75), Vector3(hp.x + sx * 3.75, ht + 3.0, hp.z + 2.75), Vector3(hp.x + sx * 3.75, ht + 5.0, hp.z), WHITE, Vector3(sx, 0, 0))


# ------------------------------------------------------------------------------
#  The glacier at the head of the north-east valley: a tongue of ice filling the
#  valley floor, convex across, crevassed where it steepens, dirty with moraine
#  at the edges and a medial stripe; its snout an ice cliff with the cave mouth
#  and the meltwater river out of it. The mammoth in the clear ice by the cave.
# ------------------------------------------------------------------------------
func _glacier() -> void:
	var path := [Vector2(702, 168), Vector2(712, 120), Vector2(720, 70), Vector2(728, 20)]
	var pts: Array = []
	for i in range(path.size() - 1):
		var a: Vector2 = R.px(path[i])
		var b: Vector2 = R.px(path[i + 1])
		var n := int(a.distance_to(b) / 40.0)
		for j in range(n):
			pts.append(R._unwarp(a.lerp(b, float(j) / n)))
	pts.append(R._unwarp(R.px(path[path.size() - 1])))
	var nl := 25
	var W := 110.0
	var rows: Array = []
	for i2 in range(pts.size()):
		var c: Vector2 = pts[i2]
		var d: Vector2 = ((pts[mini(i2 + 1, pts.size() - 1)] as Vector2) - (pts[maxi(i2 - 1, 0)] as Vector2)).normalized()
		var sd := Vector2(-d.y, d.x)
		var s := float(i2) / float(pts.size() - 1)
		var thick := lerpf(28.0, 70.0, smoothstep(0.0, 0.5, s))
		var cy := _g(c.x, c.y)
		var w := W * lerpf(0.7, 1.15, smoothstep(0.0, 0.6, s))
		var row: Array = []
		for l in range(nl):
			var u := -1.0 + 2.0 * float(l) / float(nl - 1)
			var q := c + sd * u * w
			var gy := _g(q.x, q.y)
			var surf := cy + thick * (1.0 - u * u * 0.85)
			# hug the walls: the ice never stands off the ground at its edges
			var y := maxf(surf, gy + 0.4)
			if absf(u) > 0.92:
				y = gy + 0.3
			row.append(Vector3(q.x, y, q.y))
		rows.append(row)
	# colours: clean blue-white ice, dirty moraine at the edges and a medial
	# stripe, crevasses as dark blue bands where the bed steepens, snow higher up
	for i3 in range(rows.size() - 1):
		var s3 := float(i3) / float(rows.size() - 1)
		var steep := absf(float((rows[mini(i3 + 3, rows.size() - 1)] as Array)[nl / 2].y) - float((rows[i3] as Array)[nl / 2].y)) / 40.0
		for l3 in range(nl - 1):
			var u3 := -1.0 + 2.0 * (float(l3) + 0.5) / float(nl - 1)
			# summer ice: grey-blue, streaked with dirt along the flow; the
			# snow of the accumulation zone further up
			var streak := 0.5 + 0.5 * sin(u3 * 37.0 + sin(float(i3) * 0.15) * 2.0)
			var col := Color(0.62, 0.69, 0.74).lerp(Color(0.74, 0.80, 0.85), streak).lerp(Color(0.92, 0.94, 0.97), smoothstep(0.5, 0.75, s3))
			if absf(u3) > 0.75:
				col = col.lerp(Color(0.40, 0.38, 0.35), smoothstep(0.75, 0.9, absf(u3)))
			if absf(u3 - 0.1) < 0.06:
				col = col.lerp(Color(0.45, 0.43, 0.40), 0.7)
			if steep > 0.06 and (i3 % 2 == 0) and absf(u3) < 0.75:
				col = Color(0.22, 0.36, 0.48).lerp(col, 0.25 * streak)          # crevasses, across the flow where it steepens
			var a0: Vector3 = (rows[i3] as Array)[l3]
			var a1: Vector3 = (rows[i3] as Array)[l3 + 1]
			var b0: Vector3 = (rows[i3 + 1] as Array)[l3]
			var b1: Vector3 = (rows[i3 + 1] as Array)[l3 + 1]
			k_ice.quad(a0, a1, b1, b0, col, Vector3.UP)
	# the snout: an ice cliff from the first row down to the ground, the cave
	# mouth a dark arch in the middle with a blue rim
	var r0: Array = rows[0]
	var fwd := ((rows[0] as Array)[nl / 2] as Vector3) - ((rows[1] as Array)[nl / 2] as Vector3)
	fwd.y = 0.0
	fwd = fwd.normalized()
	for l4 in range(nl - 1):
		var a: Vector3 = r0[l4]
		var b2: Vector3 = r0[l4 + 1]
		var ga := Vector3(a.x, _g(a.x, a.z) - 1.0, a.z) + fwd * 4.0
		var gb := Vector3(b2.x, _g(b2.x, b2.z) - 1.0, b2.z) + fwd * 4.0
		var u4 := absf(-1.0 + 2.0 * (float(l4) + 0.5) / float(nl - 1))
		var col4 := Color(0.62, 0.76, 0.86).lerp(Color(0.45, 0.42, 0.38), smoothstep(0.7, 0.9, u4))
		k_ice.quad(ga, gb, b2, a, col4, fwd)
	var mid: Vector3 = r0[nl / 2]
	var foot := Vector3(mid.x, _g(mid.x, mid.z), mid.z) + fwd * 4.5
	spots["ice_cave"] = foot
	# the arch: a dark half-disc and a ring of blue ice round it
	var side := fwd.cross(Vector3.UP).normalized()
	var ar := 9.0
	for q4 in range(12):
		var t0 := PI * float(q4) / 12.0
		var t1 := PI * float(q4 + 1) / 12.0
		var e0 := foot + side * cos(t0) * ar + Vector3(0, sin(t0) * ar * 0.8, 0)
		var e1 := foot + side * cos(t1) * ar + Vector3(0, sin(t1) * ar * 0.8, 0)
		k_ice.tri(foot + fwd * 0.3, e0 + fwd * 0.3, e1 + fwd * 0.3, Color(0.03, 0.06, 0.10), fwd)
		var o0 := foot + side * cos(t0) * ar * 1.25 + Vector3(0, sin(t0) * ar, 0)
		var o1 := foot + side * cos(t1) * ar * 1.25 + Vector3(0, sin(t1) * ar, 0)
		k_ice.quad(e0 + fwd * 0.35, e1 + fwd * 0.35, o1 + fwd * 0.2, o0 + fwd * 0.2, Color(0.30, 0.62, 0.85), fwd)
	# the meltwater river: grey-green, braided over gravel down the valley
	var prev := foot + fwd * 2.0
	for m in range(30):
		var nxt := prev + fwd * 40.0 + side * sin(float(m) * 0.7) * 12.0
		nxt.y = _g(nxt.x, nxt.z) + 0.6
		var sdw := side * (6.0 + float(m) * 0.2)
		k_ice.quad(prev - sdw, prev + sdw, nxt + sdw, nxt - sdw, Color(0.50, 0.62, 0.62), Vector3.UP)
		k_ice.quad(prev - sdw * 2.2 - Vector3(0, 0.2, 0), prev - sdw, nxt - sdw, nxt - sdw * 2.2 - Vector3(0, 0.2, 0), Color(0.55, 0.53, 0.50), Vector3.UP)
		k_ice.quad(prev + sdw, prev + sdw * 2.2 - Vector3(0, 0.2, 0), nxt + sdw * 2.2 - Vector3(0, 0.2, 0), nxt + sdw, Color(0.55, 0.53, 0.50), Vector3.UP)
		prev = nxt
	_mammoth_block(foot + side * 26.0 + Vector3(0, 0, 0) - fwd * 1.0, fwd, side)


## A block of clear blue ice standing out of the snout, and in it the mammoth,
## on its side the way it fell: shaggy brown, the tusks curling, the trunk.
func _mammoth_block(base: Vector3, fwd: Vector3, side: Vector3) -> void:
	spots["mammoth"] = base
	var bas := Basis(side, Vector3.UP, -fwd).orthonormalized()
	var size := Vector3(9.0, 6.5, 7.0)
	var c := base + Vector3(0, size.y * 0.5 - 0.5, 0)
	k_clear.box(Transform3D(bas, c), size, Color(0.62, 0.80, 0.92, 0.42))
	# the animal (in the block's frame, facing +x): the big domed head higher
	# than the shoulder hump, the back sloping away to small hips, the long
	# hair hanging in a skirt to the knees, pillar legs
	var hair := Color(0.30, 0.20, 0.13)
	var m := Transform3D(bas, c + bas * Vector3(0, -0.4, 0))
	var body := Transform3D.IDENTITY
	k.rbox(m * Transform3D(Basis(Vector3.FORWARD, -0.12), Vector3(0.7, 0.4, 0)), Vector3(2.6, 2.8, 2.5), hair, 1.0)       # chest and shoulders
	k.rbox(m * Transform3D(Basis(Vector3.FORWARD, -0.2), Vector3(-1.0, 0.0, 0)), Vector3(2.4, 2.2, 2.2), hair.darkened(0.05), 0.9)    # the hips, lower
	k.rbox(m * Transform3D(Basis.IDENTITY, Vector3(1.0, 1.75, 0)), Vector3(1.5, 0.8, 1.3), hair.lightened(0.05), 0.4)     # the hump
	k.rbox(m * Transform3D(Basis(Vector3.FORWARD, 0.25), Vector3(2.45, 1.55, 0)), Vector3(1.4, 2.0, 1.5), hair.darkened(0.1), 0.65)     # the domed head
	k.rbox(m * Transform3D(Basis.IDENTITY, Vector3(-0.1, -0.85, 0)), Vector3(4.0, 1.2, 2.6), hair.darkened(0.2), 0.5)     # the hair skirt
	for lx in [-1.4, 1.1]:
		for lz in [-0.6, 0.6]:
			k.rbox(m * Transform3D(Basis.IDENTITY, Vector3(lx, -1.7, lz)), Vector3(0.75, 1.5, 0.75), hair.darkened(0.25), 0.3)
	for ez in [-0.78, 0.78]:
		k.rbox(m * Transform3D(Basis.IDENTITY, Vector3(2.1, 1.6, ez)), Vector3(0.4, 0.45, 0.08), hair.darkened(0.3), 0.08)     # the small ears
	# the tusks: long curls out and up
	for tz in [-0.45, 0.45]:
		# out of the face low, sweeping forward and down, then up, curling in
		var prevp := Vector3(2.9, 0.7, tz)
		for t in range(12):
			var a := float(t + 1) * 0.36
			var np := Vector3(2.9 + sin(a) * 1.7, 0.7 - sin(a * 0.9) * 1.0 + (1.0 - cos(a)) * 0.9, tz * (1.0 + float(t) * 0.18) - signf(tz) * maxf(0.0, float(t) - 7.0) * 0.12)
			_rod(k, m * prevp, m * np, 0.12 - 0.008 * float(t), Color(0.88, 0.82, 0.68), 6)
			prevp = np
	var tp := Vector3(3.1, 0.9, 0.0)
	for t2 in range(9):
		var np2 := tp + Vector3(0.08 + 0.03 * float(t2), -0.3, 0.05 * sin(float(t2)))
		_rod(k, m * tp, m * np2, 0.25 - 0.02 * float(t2), hair, 6)
		tp = np2
	var _u := body


# ------------------------------------------------------------------------------
#  Dinosaur bones weathering out of a pale rock outcrop over the gorge: a run
#  of vertebrae, ribs arching out of the rock, a big skull half in the stone
# ------------------------------------------------------------------------------
func _fossil_spot(near: Vector2) -> Vector3:
	# a steep pale bank above the gorge: the steepest spot near `near`
	var best := Vector3(near.x, _g(near.x, near.y), near.y)
	var bs := -1.0
	for i in range(21):
		for j in range(21):
			var q := near + Vector2(-250.0 + 25.0 * i, -250.0 + 25.0 * j)
			var h := _g(q.x, q.y)
			var sl := Vector2(_g(q.x + 8, q.y) - _g(q.x - 8, q.y), _g(q.x, q.y + 8) - _g(q.x, q.y - 8)).length() / 16.0
			if sl > 0.5 and sl < 2.5 and h > 70.0 and h - 70.0 < 120.0:
				var sc := sl - q.distance_to(near) * 0.0005
				if sc > bs:
					bs = sc
					best = Vector3(q.x, h, q.y)
	return best


func _fossils(p: Vector3) -> void:
	spots["fossils"] = p
	var gx := _g(p.x + 6.0, p.z) - _g(p.x - 6.0, p.z)
	var gz := _g(p.x, p.z + 6.0) - _g(p.x, p.z - 6.0)
	var down := Vector3(-gx, 0, -gz).normalized()
	var bas := Basis(Vector3.UP, atan2(down.x, down.z))
	# the outcrop: pale sandstone ledges
	for l in range(5):
		var lc := p + bas * Vector3(_rng_f(l, -3, 3), 1.0 + 1.6 * float(l), -float(l) * 1.4)
		lc.y = _g(lc.x, lc.z) + 1.0
		_box(k, lc, Vector3(16.0 - float(l), 2.4, 4.0), Color(0.74, 0.66, 0.52).darkened(0.05 * float(l % 2)), atan2(down.x, down.z))
	var bone := Color(0.62, 0.52, 0.40)
	var o := p + bas * Vector3(0, 0, 2.2)
	o.y = _g(o.x, o.z) + 1.4
	# the spine along the face
	for v in range(16):
		var vp := o + bas * Vector3(-6.0 + 0.8 * float(v), sin(float(v) * 0.4) * 0.3, 0)
		k.rbox(Transform3D(bas, vp), Vector3(0.55, 0.5, 0.5), bone, 0.15)
		_rod(k, vp, vp + Vector3(0, 0.7, 0), 0.08, bone, 4)
		if v > 3 and v < 12:
			# a rib arching out and down
			var r0 := vp
			for s in range(6):
				var a := float(s + 1) * 0.3
				var r1 := vp + bas * Vector3(0.1 * float(s), -sin(a) * 1.8, 0.4 + (1.0 - cos(a)) * 1.6 + 0.2 * float(s))
				_rod(k, r0, r1, 0.07, bone, 4)
				r0 = r1
	# the skull at the end, half in the rock: long jaw, teeth
	var sk := o + bas * Vector3(7.2, 0.2, 0.3)
	k.rbox(Transform3D(bas, sk), Vector3(2.4, 1.1, 0.9), bone, 0.35)
	k.rbox(Transform3D(bas, sk + bas * Vector3(0.3, -0.75, 0.1)), Vector3(2.2, 0.35, 0.7), bone.darkened(0.1), 0.12)
	for t in range(8):
		_rod(k, sk + bas * Vector3(-0.5 + 0.22 * float(t), -0.5, 0.42), sk + bas * Vector3(-0.5 + 0.22 * float(t), -0.75, 0.42), 0.035, Color(0.85, 0.80, 0.70), 3)
	k.rbox(Transform3D(bas, sk + bas * Vector3(-0.6, 0.15, 0.46)), Vector3(0.4, 0.35, 0.05), Color(0.12, 0.10, 0.08), 0.1)      # the eye socket
	# a dig: string grid on stakes, a tarp, a pick and a bucket (somebody's been at it)
	for gx2 in range(4):
		var s0 := o + bas * Vector3(-4.0 + 3.0 * float(gx2), -0.9, 1.6)
		_rod(k, s0, s0 + Vector3(0, 0.5, 0), 0.02, WOOD, 3)
	k.cylinder(Transform3D(Basis.IDENTITY, o + bas * Vector3(1.5, -1.3, 2.5)), 0.15, 0.17, 0.3, 10, Color(0.80, 0.30, 0.12), true)


func _rng_f(i: int, lo: float, hi: float) -> float:
	return lo + (hi - lo) * (0.5 + 0.5 * sin(float(i) * 12.9898 + 78.233))
