extends Node3D
## Downtown Hope, early-1980s (DESIGN_NOTES 214): built straight from the
## real OpenStreetMap data (reference/hope/hope_osm.json, (c) OpenStreetMap
## contributors) round Wallace Street and 3rd Avenue - every street, curb,
## sidewalk and building at its real place and footprint - dressed with a
## building kit at the trucks' level of detail: siding / brick walls, framed
## windows with sills, storefronts with awnings and sign boards, doors and
## steps, gable / hip / flat roofs with eaves and parapets; and the street
## furniture of the time: wooden power poles carrying the wires and the
## cobra-head lights, payphones, hydrants, stop signs, newspaper boxes,
## benches, bins, parking lines.
## Generic only: no real business names or brands on anything.

const MeshKit = preload("res://scripts/meshkit.gd")
const OSM := "res://reference/hope/hope_osm.json"
const LON0 := -121.441705
const LAT0 := 49.37947            # Wallace Street at 3rd Avenue
const RADIUS := 270.0             # metres of town to build round it (out to Water Ave and Hudson Bay St)

var radius := RADIUS
var main_names: Array = MAIN
var _sign_text := ""             # a designed lot's shop sign (else a random one)
var _sign_col := Color(0, 0, 0, 0)
var _awning := -1                # -1 random, 0 none, 1 yes
var _painted := -1
var _cur_wall := Color(0.86, 0.82, 0.66)
var _roads: Array = []            # [{pts: PackedVector2Array, w: float, kind: String, name: String}]
var _rng := RandomNumberGenerator.new()

# one kit per material, all the town in a handful of meshes
var k_siding := MeshKit.new()
var k_brick := MeshKit.new()
var k_trim := MeshKit.new()
var k_glass := MeshKit.new()
var k_roof := MeshKit.new()
var k_asphalt := MeshKit.new()
var k_concrete := MeshKit.new()
var k_paint := MeshKit.new()      # road lines, signs, plain painted metal
var k_metal := MeshKit.new()
var k_wood := MeshKit.new()
var k_grass := MeshKit.new()
var k_leaf := MeshKit.new()

const MOTELS := [Vector2(-56.8, -44.1), Vector2(-62.0, 169.9), Vector2(23.0, 156.4), Vector2(165.2, -17.4), Vector2(209.4, -145.8), Vector2(-71.6, 168.6)]
const GAS_CORNER := Vector2(-64.4, 242.7)        # Water Ave at Hudson Bay St: the old gas station corner
const PLAZA := Vector2(-35.4, 33.6)
const MAIN := ["Wallace Street", "3rd Avenue", "Water Avenue", "Fort Street", "King Street", "Hudson Bay Street", "Commission Street", "Park Street"]
const SIGNS := ["HARDWARE", "CAFE", "DRUGS", "BARBER", "DINER", "BAKERY", "TV - RADIO", "SPORTS", "BOOKS", "SHOES", "MEATS", "INSURANCE", "LAUNDRY", "VARIETY", "FABRICS", "JEWELLER", "PIZZA", "TAVERN", "GROCERY", "SAVINGS", "GUNS - TACKLE", "HOTEL", "GIFTS", "MOTEL", "ELECTRIC", "FLORIST"]
const SIDING := [Color(0.86, 0.82, 0.66), Color(0.62, 0.68, 0.56), Color(0.66, 0.74, 0.80), Color(0.55, 0.42, 0.30), Color(0.90, 0.89, 0.84), Color(0.76, 0.64, 0.46), Color(0.72, 0.56, 0.50), Color(0.80, 0.76, 0.60)]
const STUCCO := [Color(0.88, 0.84, 0.74), Color(0.80, 0.76, 0.68), Color(0.74, 0.70, 0.62), Color(0.84, 0.78, 0.64)]
const BRICK := [Color(0.62, 0.34, 0.26), Color(0.55, 0.30, 0.24), Color(0.68, 0.46, 0.36)]
const TRIM := [Color(0.95, 0.95, 0.92), Color(0.40, 0.28, 0.18), Color(0.20, 0.30, 0.22), Color(0.18, 0.22, 0.32), Color(0.55, 0.15, 0.12)]


func _ready() -> void:
	_rng.seed = 1982
	var f := FileAccess.open(OSM, FileAccess.READ)
	if f == null:
		f = FileAccess.open(ProjectSettings.globalize_path(OSM), FileAccess.READ)
	if f == null:
		push_error("town_block: no OSM data at " + OSM)
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	_ground()
	_read_roads(d["ways"])
	for r in _roads:
		_road(r)
	for w in d["ways"]:
		var t: Dictionary = w["tags"]
		if t.has("building"):
			_building(w)
	_street_furniture()
	_finish()


# ------------------------------------------------------------------------------
#  Data: lon/lat -> metres (x east, z south), clipped to the block
# ------------------------------------------------------------------------------
static func xy(c: Array) -> Vector2:
	return Vector2((float(c[0]) - LON0) * 111320.0 * cos(deg_to_rad(LAT0)), -(float(c[1]) - LAT0) * 110540.0)


func _inside(p: Vector2, margin: float = 0.0) -> bool:
	return p.length() < radius + margin


const ROAD_W := {"trunk": 11.0, "primary": 10.0, "secondary": 10.0, "tertiary": 10.0, "residential": 8.0, "unclassified": 7.0, "living_street": 6.0, "service": 4.5}


func _read_roads(ways: Array) -> void:
	for w in ways:
		var t: Dictionary = w["tags"]
		var hw := String(t.get("highway", ""))
		if not ROAD_W.has(hw):
			continue
		if String(t.get("service", "")) in ["parking_aisle", "drive-through"]:
			continue
		var pts := PackedVector2Array()
		for c in w["c"]:
			pts.append(xy(c))
		var keep := false
		for p in pts:
			if _inside(p, 30.0):
				keep = true
		if not keep:
			continue
		_roads.append({"pts": pts, "w": float(ROAD_W[hw]), "kind": hw, "name": String(t.get("name", "")), "walks": hw != "service"})


## Distance from p to the nearest road centreline other than `skip`, minus that road's half width.
func _road_clear(p: Vector2, skip: int) -> float:
	var best := 1e9
	for i in range(_roads.size()):
		if i == skip:
			continue
		var r: Dictionary = _roads[i]
		var pts: PackedVector2Array = r["pts"]
		for j in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])
			best = minf(best, p.distance_to(q) - float(r["w"]) * 0.5)
	return best


# ------------------------------------------------------------------------------
#  Ground, roads, curbs and sidewalks
# ------------------------------------------------------------------------------
func _ground() -> void:
	var s := radius + 60.0
	var n := 24
	for i in range(n):
		for j in range(n):
			var x0 := -s + 2.0 * s * float(i) / n
			var x1 := -s + 2.0 * s * float(i + 1) / n
			var z0 := -s + 2.0 * s * float(j) / n
			var z1 := -s + 2.0 * s * float(j + 1) / n
			var g := Color(0.36, 0.42, 0.22).lerp(Color(0.44, 0.44, 0.28), _rng.randf())
			k_grass.quad(Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1), g, Vector3.UP)


const CURB_H := 0.15
const WALK_W := 1.8


func _road(r: Dictionary) -> void:
	var pts: PackedVector2Array = r["pts"]
	var w: float = r["w"]
	var idx := _roads.find(r)
	var y := 0.03 if String(r["kind"]) != "service" else 0.025
	var main := String(r["name"]) in main_names
	var lined: bool = String(r["kind"]) in ["tertiary", "secondary", "primary", "trunk"] or main
	for j in range(pts.size() - 1):
		var a: Vector2 = pts[j]
		var b: Vector2 = pts[j + 1]
		if not (_inside(a, 40.0) or _inside(b, 40.0)):
			continue
		var d := b - a
		var L := d.length()
		if L < 0.01:
			continue
		var t := d / L
		var nrm := Vector2(-t.y, t.x)
		# the asphalt, a hair longer each end so the joints don't show
		var a2 := a - t * 0.3
		var b2 := b + t * 0.3
		var col := Color(0.20, 0.20, 0.21).lerp(Color(0.25, 0.25, 0.25), _rng.randf())
		k_asphalt.quad(_v3(a2 + nrm * w * 0.5, y), _v3(b2 + nrm * w * 0.5, y), _v3(b2 - nrm * w * 0.5, y), _v3(a2 - nrm * w * 0.5, y), col, Vector3.UP)
		# the centre line: yellow dashes (1982), on the through streets
		if lined:
			var s := 0.0
			while s < L:
				var p0 := a + t * s
				var p1 := a + t * minf(s + 3.0, L)
				if _road_clear(p0, idx) > 1.0 and _road_clear(p1, idx) > 1.0:
					_flat_strip(k_paint, p0, p1, 0.12, y + 0.004, Color(0.86, 0.70, 0.18))
				s += 9.0
		# curbs and sidewalks both sides, stepped along so the cross streets cut them
		if not bool(r["walks"]):
			continue
		var steps := maxi(1, int(L / 1.5))
		for sd: float in [-1.0, 1.0]:
			for k in range(steps):
				var q0 := a + t * (L * float(k) / steps)
				var q1 := a + t * (L * float(k + 1) / steps)
				var mid := (q0 + q1) * 0.5 + nrm * sd * (w * 0.5 + WALK_W * 0.5)
				if _road_clear(mid, idx) < WALK_W * 0.5 + 0.4:
					continue
				if _no_walk(mid):
					continue
				var e0 := q0 + nrm * sd * w * 0.5
				var e1 := q1 + nrm * sd * w * 0.5
				var o0 := q0 + nrm * sd * (w * 0.5 + WALK_W)
				var o1 := q1 + nrm * sd * (w * 0.5 + WALK_W)
				var cc := Color(0.70, 0.70, 0.67).lerp(Color(0.62, 0.62, 0.60), _rng.randf() * 0.5)
				var hint := Vector3(nrm.x * -sd, 0, nrm.y * -sd)
				k_concrete.quad(_v3(e0, y), _v3(e1, y), _v3(e1, CURB_H), _v3(e0, CURB_H), Color(0.66, 0.66, 0.63), hint)           # curb face
				k_concrete.quad(_v3(e0, CURB_H), _v3(e1, CURB_H), _v3(o1, CURB_H), _v3(o0, CURB_H), cc, Vector3.UP)                # sidewalk slab
				k_concrete.quad(_v3(o0, CURB_H), _v3(o1, CURB_H), _v3(o1, 0.0), _v3(o0, 0.0), Color(0.60, 0.60, 0.58), -hint)  # back edge down to the grass
				# the slab's joint, a dark line across it
				_flat_strip(k_paint, e1, o1, 0.025, CURB_H + 0.003, Color(0.48, 0.48, 0.46))


func _flat_strip(k: MeshKit, a: Vector2, b: Vector2, w: float, y: float, col: Color):
	var d := b - a
	if d.length() < 0.001:
		return null
	var n := Vector2(-d.y, d.x).normalized() * w * 0.5
	k.quad(_v3(a + n, y), _v3(b + n, y), _v3(b - n, y), _v3(a - n, y), col, Vector3.UP)
	return null


static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


# ------------------------------------------------------------------------------
#  Buildings: the kit
# ------------------------------------------------------------------------------
func _building(w: Dictionary) -> void:
	var t: Dictionary = w["tags"]
	var poly := PackedVector2Array()
	for c in w["c"]:
		poly.append(xy(c))
	if poly.size() > 1 and poly[0].distance_to(poly[poly.size() - 1]) < 0.05:
		poly.remove_at(poly.size() - 1)
	if poly.size() < 3:
		return
	_building_poly(poly, t)


## One building from its footprint and tags (OSM's, or a designed lot's:
## "building" kind, "building:levels", and for the designed town "sign" / "style").
func _building_poly(poly: PackedVector2Array, t: Dictionary) -> void:
	var cen := Vector2.ZERO
	for p in poly:
		cen += p
	cen /= float(poly.size())
	if not _inside(cen):
		return
	var bc: Array = get_meta("_bldg_cents", [])
	bc.append(cen)
	set_meta("_bldg_cents", bc)
	if _area(poly) < 0.0:
		poly.reverse()                 # positive area in (x, z): the right-hand normal of each edge points out
	var bp: Array = get_meta("_bldg_polys", [])
	bp.append(poly)
	set_meta("_bldg_polys", bp)
	var area := absf(_area(poly))
	var kind := String(t.get("building", "yes"))
	var near_main := _near_main(cen) < 22.0
	var shop := kind in ["commercial", "retail", "hotel", "civic", "public", "office", "fire_station", "supermarket", "church"] or (kind == "yes" and near_main and area > 90.0)
	if t.has("shop"):
		shop = bool(t["shop"])
	var small := kind in ["garage", "garages", "shed", "carport", "roof", "hut"] or area < 32.0
	var levels := int(t.get("building:levels", "0"))
	if levels <= 0:
		levels = 1 if small else (2 if (shop and area > 500.0 and _rng.randf() < 0.5) or (not shop and area > 110.0 and _rng.randf() < 0.35) else 1)
	var storey := 2.7 if not shop else 3.4
	var ground := 0.0 if not shop else 0.9          # shops: a taller ground floor
	var h := float(levels) * storey + ground
	if small:
		h = 2.6
	var brick := shop and _rng.randf() < 0.45
	if t.has("wall"):
		brick = String(t["wall"]) == "brick"
	var wall: Color
	if brick:
		wall = BRICK[_rng.randi() % BRICK.size()]
	elif shop:
		wall = STUCCO[_rng.randi() % STUCCO.size()]
	else:
		wall = SIDING[_rng.randi() % SIDING.size()]
	if t.has("wall_col"):
		wall = t["wall_col"]
	var trim: Color = TRIM[_rng.randi() % TRIM.size()] if not shop else Color(0.92, 0.92, 0.88)
	if t.has("trim_col"):
		trim = t["trim_col"]
	_sign_text = String(t.get("sign", ""))
	_sign_col = t.get("sign_col", Color(0, 0, 0, 0))
	_awning = int(t.get("awning", -1))
	_painted = int(t.get("painted", -1))
	var wk: MeshKit = k_brick if brick else k_siding
	_cur_wall = wall
	var base_y := 0.0
	# the walls, a skirt / foundation, and on each one its windows or storefront
	var front := _front_edge(poly) if not t.has("front") else int(t["front"])
	var motel := String(t.get("style", "")) == "motel"
	for mp in MOTELS:
		if (mp as Vector2).distance_to(cen) < 18.0 or Geometry2D.is_point_in_polygon(mp, poly):
			motel = motel or area > 120.0
	if motel:
		_motel(poly, front, cen)
		return
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var d := b - a
		var L := d.length()
		if L < 0.05:
			continue
		var out := Vector2(d.y, -d.x).normalized()           # outward (clockwise ring)
		var oh := Vector3(out.x, 0, out.y)
		wk.quad(_v3(a, base_y + 0.35), _v3(b, base_y + 0.35), _v3(b, h), _v3(a, h), wall, oh)
		k_concrete.quad(_v3(a + out * 0.03, 0.0), _v3(b + out * 0.03, 0.0), _v3(b + out * 0.03, 0.35), _v3(a + out * 0.03, 0.35), Color(0.52, 0.51, 0.48), oh)   # foundation
		k_trim.quad(_v3(a + out * 0.02, h - 0.18), _v3(b + out * 0.02, h - 0.18), _v3(b + out * 0.02, h), _v3(a + out * 0.02, h), trim, oh)                  # frieze board
		if i == front and _front_custom(a, b, out, t, h, trim):
			continue
		if small:
			if i == front and L > 2.6:
				_garage_door(a, b, out, trim)
			continue
		if shop and i == front:
			_storefront(a, b, out, ground + storey, trim, h)
			if L > 9.0 and _rng.randf() < 0.35 and not t.has("sign"):
				_pole_sign((a + b) * 0.5 + out * 2.5, h + 3.5)
			for lv in range(1, levels):
				_window_row(a, b, out, ground + storey * float(lv) + 0.9, trim, 2.8)
		else:
			for lv2 in range(levels):
				_window_row(a, b, out, (ground if shop else 0.0) + storey * float(lv2) + (0.9 if lv2 > 0 or not shop else 1.2), trim, 3.0 if shop else 2.6)
			if not shop and i == front and L > 3.0:
				_house_door(a, b, out, trim)
	# the roof
	var roof := String(t.get("roof", ""))
	if roof == "gable" and poly.size() == 4:
		_gable_roof(poly, h, small)
	elif roof == "hip":
		_hip_roof(poly, h, cen)
	elif roof == "none":
		pass
	elif roof == "flat" or shop or area > 400.0 or poly.size() > 8:
		_flat_roof(poly, h, wall, shop)
	elif poly.size() == 4:
		_gable_roof(poly, h, small)
	else:
		_hip_roof(poly, h, cen)
	if shop and not small:
		_rooftop(poly, cen, h)


## A driveway crosses the sidewalk here: leave a curb cut (designed towns say where).
func _no_walk(_p: Vector2) -> bool:
	return false


## A designed lot can draw its own front (fire hall bays, church doors...): return true if it did.
func _front_custom(_a: Vector2, _b: Vector2, _out: Vector2, _t: Dictionary, _h: float, _trim: Color) -> bool:
	return false


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(p.size()):
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


func _near_main(p: Vector2) -> float:
	var best := 1e9
	for r in _roads:
		if not (String(r["name"]) in main_names):
			continue
		var pts: PackedVector2Array = r["pts"]
		for j in range(pts.size() - 1):
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])) - float(r["w"]) * 0.5)
	return best


## The wall that faces the street: the long-enough edge whose middle is nearest a road.
func _front_edge(poly: PackedVector2Array) -> int:
	var best := 0
	var bd := 1e9
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		if a.distance_to(b) < 2.5:
			continue
		var m := (a + b) * 0.5
		var out := Vector2(b.y - a.y, -(b.x - a.x)).normalized()
		var dd := _road_clear(m + out * 2.0, -1)
		if dd < bd:
			bd = dd
			best = i
	return best


func _window_row(a: Vector2, b: Vector2, out: Vector2, sill: float, trim: Color, spacing: float) -> void:
	var d := b - a
	var L := d.length()
	if L < 2.2:
		return
	var t := d / L
	var n := maxi(1, int((L - 1.0) / spacing))
	var oh := Vector3(out.x, 0, out.y)
	for k in range(n):
		var c := a + t * (L * (float(k) + 0.5) / float(n))
		var ww := 1.0
		var wh := 1.25
		var p0 := c - t * ww * 0.5
		var p1 := c + t * ww * 0.5
		# glass, set in a hair
		k_glass.quad(_v3(p0 + out * 0.01, sill), _v3(p1 + out * 0.01, sill), _v3(p1 + out * 0.01, sill + wh), _v3(p0 + out * 0.01, sill + wh), Color(0.12, 0.16, 0.20), oh)
		# the frame: four boards and the muntin, the sill sticking out below
		_board(p0, p1, out, sill + wh, sill + wh + 0.08, 0.04, trim)
		_board(p0 - t * 0.08, p0, out, sill, sill + wh + 0.08, 0.04, trim)
		_board(p1, p1 + t * 0.08, out, sill, sill + wh + 0.08, 0.04, trim)
		_board(p0 - t * 0.1, p1 + t * 0.1, out, sill - 0.07, sill, 0.07, trim)
		_board(p0, p1, out, sill + wh * 0.5 - 0.02, sill + wh * 0.5 + 0.02, 0.025, trim)


## A flat board on the wall from a to b, y0..y1, standing `depth` proud.
func _board(a: Vector2, b: Vector2, out: Vector2, y0: float, y1: float, depth: float, col: Color) -> void:
	var a2 := a + out * depth
	var b2 := b + out * depth
	var oh := Vector3(out.x, 0, out.y)
	k_trim.quad(_v3(a2, y0), _v3(b2, y0), _v3(b2, y1), _v3(a2, y1), col, oh)
	k_trim.quad(_v3(a2, y1), _v3(b2, y1), _v3(b, y1), _v3(a, y1), col, Vector3.UP)
	k_trim.quad(_v3(a, y0), _v3(b, y0), _v3(b2, y0), _v3(a2, y0), col.darkened(0.3), Vector3.DOWN)
	var t := (b - a).normalized()
	k_trim.quad(_v3(a, y0), _v3(a2, y0), _v3(a2, y1), _v3(a, y1), col.darkened(0.1), Vector3(-t.x, 0, -t.y))
	k_trim.quad(_v3(b2, y0), _v3(b, y0), _v3(b, y1), _v3(b2, y1), col.darkened(0.1), Vector3(t.x, 0, t.y))


func _storefront(a: Vector2, b: Vector2, out: Vector2, top: float, trim: Color, h: float) -> void:
	var d := b - a
	var L := d.length()
	var t := d / L
	var oh := Vector3(out.x, 0, out.y)
	var m0 := a + t * 0.4
	var m1 := b - t * 0.4
	var glass_top := 2.7
	# kick plate under the glass, the glass, the mullions, the door
	_board(m0, m1, out, 0.0, 0.5, 0.05, Color(0.30, 0.24, 0.18))
	k_glass.quad(_v3(m0 + out * 0.02, 0.5), _v3(m1 + out * 0.02, 0.5), _v3(m1 + out * 0.02, glass_top), _v3(m0 + out * 0.02, glass_top), Color(0.10, 0.13, 0.16), oh)
	if _painted == 1 or (_painted == -1 and _rng.randf() < 0.4):
		_painted_window(m0, m1, out)
	var nm := maxi(2, int((L - 0.8) / 1.8))
	var dk := _rng.randi_range(0, nm - 1)
	for k in range(nm + 1):
		var c := m0.lerp(m1, float(k) / float(nm))
		_board(c - t * 0.05, c + t * 0.05, out, 0.5, glass_top, 0.07, Color(0.55, 0.55, 0.52))
	_board(m0, m1, out, glass_top, glass_top + 0.1, 0.07, Color(0.55, 0.55, 0.52))
	var dc := m0.lerp(m1, (float(dk) + 0.5) / float(nm))
	_board(dc - t * 0.5, dc + t * 0.5, out, 0.0, 0.08, 0.3, Color(0.55, 0.55, 0.52))         # the step
	_board(dc - t * 0.45, dc + t * 0.45, out, 0.08, 2.2, 0.035, Color(0.38, 0.38, 0.36))      # the door frame
	k_glass.quad(_v3(dc - t * 0.38 + out * 0.04, 0.2), _v3(dc + t * 0.38 + out * 0.04, 0.2), _v3(dc + t * 0.38 + out * 0.04, 2.1), _v3(dc - t * 0.38 + out * 0.04, 2.1), Color(0.10, 0.12, 0.14), oh)
	_board(dc + t * 0.25, dc + t * 0.32, out, 1.0, 1.06, 0.08, Color(0.75, 0.72, 0.6))          # the push bar
	# the sign board and its lettering, the awning
	var sb0 := glass_top + 0.2
	var sb1 := minf(top - 0.1, sb0 + 0.75)
	var sc: Color = [Color(0.92, 0.90, 0.82), Color(0.15, 0.25, 0.45), Color(0.55, 0.12, 0.10), Color(0.12, 0.30, 0.18), Color(0.90, 0.80, 0.30)][_rng.randi() % 5]
	if _sign_col.a > 0.0:
		sc = _sign_col
	_board(m0, m1, out, sb0, sb1, 0.08, sc)
	var lab := Label3D.new()
	lab.text = _sign_text if _sign_text != "" else SIGNS[_rng.randi() % SIGNS.size()]
	lab.font_size = 96
	lab.pixel_size = clampf((sb1 - sb0) * 0.0062, 0.002, 0.006)
	lab.modulate = Color(0.1, 0.1, 0.1) if sc.v > 0.6 else Color(0.96, 0.95, 0.88)
	lab.outline_size = 0
	lab.shaded = true
	var mid := (m0 + m1) * 0.5 + out * 0.095
	lab.position = Vector3(mid.x, (sb0 + sb1) * 0.5, mid.y)
	lab.basis = Basis.looking_at(-oh, Vector3.UP)
	add_child(lab)
	if _awning == 1 or (_awning == -1 and _rng.randf() < 0.7):
		var aw: Color = [Color(0.60, 0.12, 0.10), Color(0.15, 0.35, 0.20), Color(0.20, 0.25, 0.45), Color(0.75, 0.55, 0.15), Color(0.35, 0.25, 0.18)][_rng.randi() % 5]
		var ay := glass_top + 0.12
		var p0 := _v3(m0 - t * 0.1, ay)
		var p1 := _v3(m1 + t * 0.1, ay)
		var q0 := _v3(m0 - t * 0.1 + out * 1.3, ay - 0.55)
		var q1 := _v3(m1 + t * 0.1 + out * 1.3, ay - 0.55)
		var stripes := maxi(2, int((L + 0.2) / 0.5))
		for s in range(stripes):
			var f0 := float(s) / stripes
			var f1 := float(s + 1) / stripes
			var c2: Color = aw if s % 2 == 0 else Color(0.92, 0.90, 0.84)
			k_paint.quad(p0.lerp(p1, f0), p0.lerp(p1, f1), q0.lerp(q1, f1), q0.lerp(q0 + (q1 - q0), f0), c2, Vector3(out.x, 1.3, out.y))
			k_paint.quad(q0.lerp(q1, f0), q0.lerp(q1, f1), q0.lerp(q1, f1) + Vector3(0, -0.25, 0), q0.lerp(q1, f0) + Vector3(0, -0.25, 0), c2, oh)     # the valance


## Holiday scenes painted on the shop glass (FILM_NOTES 4): trees, snowmen, stars, a border.
func _painted_window(a: Vector2, b: Vector2, out: Vector2) -> void:
	var t := (b - a).normalized()
	var L := a.distance_to(b)
	var oh := Vector3(out.x, 0, out.y)
	var n := int(L / 1.4)
	for k in range(n):
		var c := a + t * (0.7 + float(k) * 1.4) + out * 0.025
		var what := _rng.randi() % 3
		if what == 0:          # a tree
			for lv in range(3):
				var y0 := 0.8 + float(lv) * 0.35
				var hw := 0.4 - float(lv) * 0.1
				k_paint.tri(_v3(c - t * hw, y0), _v3(c + t * hw, y0), _v3(c, y0 + 0.5), Color(0.15, 0.50, 0.20), oh)
			k_paint.quad(_v3(c - t * 0.06, 0.62), _v3(c + t * 0.06, 0.62), _v3(c + t * 0.06, 0.8), _v3(c - t * 0.06, 0.8), Color(0.4, 0.25, 0.1), oh)
		elif what == 1:        # a snowman: three white blobs
			for bl in [[0.8, 0.28], [1.25, 0.2], [1.58, 0.14]]:
				var r: float = bl[1]
				for q in range(8):
					var a0 := TAU * float(q) / 8.0
					var a1 := TAU * float(q + 1) / 8.0
					k_paint.tri(_v3(c, float(bl[0])), _v3(c + t * cos(a0) * r, float(bl[0]) + sin(a0) * r), _v3(c + t * cos(a1) * r, float(bl[0]) + sin(a1) * r), Color(0.95, 0.95, 0.95), oh)
		else:                  # a red star / ornament
			var cy := 1.6
			for q2 in range(5):
				var a2 := TAU * float(q2) / 5.0 + PI * 0.5
				k_paint.tri(_v3(c, cy), _v3(c + t * cos(a2) * 0.25, cy + sin(a2) * 0.25), _v3(c + t * cos(a2 + 0.6) * 0.1, cy + sin(a2 + 0.6) * 0.1), Color(0.8, 0.1, 0.08), oh)
	k_paint.quad(_v3(a + out * 0.025, 2.45), _v3(b + out * 0.025, 2.45), _v3(b + out * 0.025, 2.6), _v3(a + out * 0.025, 2.6), Color(0.8, 0.1, 0.08), oh)   # a painted border along the top


func _house_door(a: Vector2, b: Vector2, out: Vector2, trim: Color) -> void:
	var d := b - a
	var t := d.normalized()
	var c := a.lerp(b, 0.3 + _rng.randf() * 0.4)
	var door: Color = [Color(0.45, 0.28, 0.16), Color(0.55, 0.12, 0.10), Color(0.18, 0.25, 0.20), Color(0.92, 0.90, 0.85)][_rng.randi() % 4]
	_board(c - t * 0.5, c + t * 0.5, out, 0.35, 2.4, 0.04, trim)                          # the casing
	_board(c - t * 0.43, c + t * 0.43, out, 0.4, 2.33, 0.06, door)                         # the door
	_board(c + t * 0.28, c + t * 0.34, out, 1.15, 1.2, 0.1, Color(0.75, 0.68, 0.40))       # knob
	# the steps / stoop and its rails
	_board(c - t * 0.8, c + t * 0.8, out * 1.0, 0.0, 0.18, 1.2, Color(0.58, 0.57, 0.54))
	_board(c - t * 0.8, c + t * 0.8, out * 1.0, 0.18, 0.35, 0.8, Color(0.62, 0.61, 0.58))
	if _rng.randf() < 0.6:                                                                  # a little porch roof
		var p0 := _v3(c - t * 1.0, 2.6)
		var p1 := _v3(c + t * 1.0, 2.6)
		var q0 := _v3(c - t * 1.0 + out * 1.3, 2.35)
		var q1 := _v3(c + t * 1.0 + out * 1.3, 2.35)
		k_roof.quad(p0, p1, q1, q0, Color(0.30, 0.28, 0.26), Vector3(out.x, 1.5, out.y))


func _garage_door(a: Vector2, b: Vector2, out: Vector2, trim: Color) -> void:
	var t := (b - a).normalized()
	var c := (a + b) * 0.5
	var hw := minf(1.25, (b - a).length() * 0.5 - 0.2)
	_board(c - t * (hw + 0.08), c + t * (hw + 0.08), out, 0.0, 2.2, 0.03, trim)
	for k in range(4):
		_board(c - t * hw, c + t * hw, out, 0.02 + float(k) * 0.52, 0.02 + float(k) * 0.52 + 0.48, 0.05, Color(0.85, 0.84, 0.80))


func _flat_roof(poly: PackedVector2Array, h: float, wall: Color, parapet: bool) -> void:
	var tri := Geometry2D.triangulate_polygon(poly)
	var ry := h + (0.0 if not parapet else 0.05)
	for i in range(0, tri.size(), 3):
		k_roof.tri(_v3(poly[tri[i]], ry), _v3(poly[tri[i + 1]], ry), _v3(poly[tri[i + 2]], ry), Color(0.22, 0.21, 0.20).lerp(Color(0.30, 0.29, 0.27), _rng.randf()), Vector3.UP)
	# the parapet: a low wall round the edge, its cap flashing
	var ph := 0.6 if parapet else 0.25
	for i2 in range(poly.size()):
		var a: Vector2 = poly[i2]
		var b: Vector2 = poly[(i2 + 1) % poly.size()]
		var d := b - a
		if d.length() < 0.05:
			continue
		var out := Vector2(d.y, -d.x).normalized()
		var wk: MeshKit = k_siding
		wk.quad(_v3(a, h), _v3(b, h), _v3(b, h + ph), _v3(a, h + ph), wall, Vector3(out.x, 0, out.y))
		wk.quad(_v3(b - out * 0.2, h), _v3(a - out * 0.2, h), _v3(a - out * 0.2, h + ph), _v3(b - out * 0.2, h + ph), wall.darkened(0.2), Vector3(-out.x, 0, -out.y))
		k_metal.quad(_v3(a + out * 0.04, h + ph), _v3(b + out * 0.04, h + ph), _v3(b - out * 0.24, h + ph), _v3(a - out * 0.24, h + ph), Color(0.62, 0.62, 0.60), Vector3.UP)


func _gable_roof(poly: PackedVector2Array, h: float, small: bool) -> void:
	# ridge along the long axis, eaves out 0.45, gables filled with the wall
	var e0 := poly[1] - poly[0]
	var e1 := poly[2] - poly[1]
	var long0 := e0.length() >= e1.length()
	var A: Vector2 = poly[0]
	var B: Vector2 = poly[1]
	var C: Vector2 = poly[2]
	var D: Vector2 = poly[3]
	if not long0:
		A = poly[1]; B = poly[2]; C = poly[3]; D = poly[0]
	var ov := 0.45
	var span := (D - A).length()
	var pitch := 0.42 if not small else 0.25
	var rise := span * 0.5 * pitch
	var ax := (B - A).normalized()
	var mA := (A + D) * 0.5 - ax * ov
	var mB := (B + C) * 0.5 + ax * ov
	var A2 := A - ax * ov + (A - D).normalized() * ov
	var B2 := B + ax * ov + (B - C).normalized() * ov
	var C2 := C + ax * ov + (C - B).normalized() * ov
	var D2 := D - ax * ov + (D - A).normalized() * ov
	var ey := h - ov * pitch
	var col: Color = [Color(0.25, 0.24, 0.23), Color(0.34, 0.22, 0.18), Color(0.20, 0.26, 0.22), Color(0.40, 0.36, 0.30), Color(0.30, 0.30, 0.34)][_rng.randi() % 5]
	k_roof.quad(_v3(A2, ey), _v3(B2, ey), _v3(mB, h + rise), _v3(mA, h + rise), col, _v3((A - D).normalized(), 1.0))
	k_roof.quad(_v3(C2, ey), _v3(D2, ey), _v3(mA, h + rise), _v3(mB, h + rise), col, _v3((D - A).normalized(), 1.0))
	# the roof's underside (seen from the street) and the gable ends
	k_trim.quad(_v3(mA, h + rise - 0.06), _v3(mB, h + rise - 0.06), _v3(B2, ey - 0.06), _v3(A2, ey - 0.06), Color(0.85, 0.84, 0.80), Vector3.DOWN)
	k_trim.quad(_v3(mB, h + rise - 0.06), _v3(mA, h + rise - 0.06), _v3(D2, ey - 0.06), _v3(C2, ey - 0.06), Color(0.85, 0.84, 0.80), Vector3.DOWN)
	var wcol: Color = _cur_wall          # the gable ends in the house's own colour
	k_siding.tri(_v3(A, h), _v3(D, h), _v3((A + D) * 0.5, h + rise), wcol, _v3(-ax, 0.0))
	k_siding.tri(_v3(C, h), _v3(B, h), _v3((B + C) * 0.5, h + rise), wcol, _v3(ax, 0.0))
	if not small and _rng.randf() < 0.55:          # a brick chimney through the roof
		var cp := (mA.lerp(mB, 0.25 + _rng.randf() * 0.5)) + (A - D).normalized() * span * 0.15
		k_brick.box_at(Vector3(cp.x, h + rise * 0.7 + 0.6, cp.y), Vector3(0.55, rise + 1.0, 0.55), BRICK[0])


func _hip_roof(poly: PackedVector2Array, h: float, cen: Vector2) -> void:
	var span := 0.0
	for p in poly:
		span = maxf(span, p.distance_to(cen))
	var top := Vector3(cen.x, h + span * 0.35, cen.y)
	var col: Color = [Color(0.25, 0.24, 0.23), Color(0.34, 0.22, 0.18), Color(0.40, 0.36, 0.30)][_rng.randi() % 3]
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var a2 := a + (a - cen).normalized() * 0.45
		var b2 := b + (b - cen).normalized() * 0.45
		var oh := (a + b) * 0.5 - cen
		k_roof.tri(_v3(a2, h - 0.15), _v3(b2, h - 0.15), top, col, Vector3(oh.x, oh.length(), oh.y))
		k_trim.tri(_v3(b2, h - 0.2), _v3(a2, h - 0.2), top - Vector3(0, 0.08, 0), Color(0.85, 0.84, 0.80), Vector3.DOWN)


func _rooftop(poly: PackedVector2Array, cen: Vector2, h: float) -> void:
	if _rng.randf() < 0.6:            # a rooftop furnace / cooler unit
		k_metal.box_at(Vector3(cen.x, h + 0.55, cen.y), Vector3(1.6, 1.0, 1.1), Color(0.70, 0.70, 0.68))
		k_metal.box_at(Vector3(cen.x + 0.4, h + 1.1, cen.y), Vector3(0.5, 0.15, 0.5), Color(0.40, 0.40, 0.40))
	var v: Vector2 = poly[0].lerp(cen, 0.3)
	k_metal.cylinder(Transform3D(Basis.IDENTITY, Vector3(v.x, h, v.y)), 0.08, 0.08, 0.8, 8, Color(0.35, 0.35, 0.35), true)   # a vent stack


# ------------------------------------------------------------------------------
#  Street furniture, 1982: power poles with the wires and cobra-head lights,
#  payphones, hydrants, stop signs, newspaper boxes, benches, bins, parking
# ------------------------------------------------------------------------------
func _street_furniture() -> void:
	_poles_and_stops()
	# payphones: on the main corner (Wallace and 3rd) and by the plaza
	_payphone(Vector2(7.5, 7.0), Vector2(0, -1))
	_payphone(Vector2(-8.0, -7.5), Vector2(1, 0))
	_payphone(Vector2(-30.0, 25.0), Vector2(0, -1))
	_booth(Vector2(12.0, -9.0), Vector2(-1, 0))
	# benches and bins along the main corner
	for bp in [[Vector2(10.0, 12.0), Vector2(0, -1)], [Vector2(-12.0, -11.0), Vector2(0, 1)], [Vector2(-14.0, 9.5), Vector2(1, 0)]]:
		_bench(bp[0], bp[1])
		_bin(bp[0] + Vector2(1.6, 0))
	_traffic_lights(Vector2.ZERO)
	_pole_sign(PLAZA + Vector2(-6, -14), 9.0, "SHOPPING PLAZA")
	_gas_station()
	_parked_cars()
	_trees()


## Power poles and their wires, hydrants, newspaper boxes, stop signs: along every road.
func _poles_and_stops() -> void:
	var poles: Array = []          # per road: the pole tops, for the wires
	for ri in range(_roads.size()):
		var r: Dictionary = _roads[ri]
		if not bool(r["walks"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		var w: float = r["w"]
		var side := 1.0 if ri % 2 == 0 else -1.0
		var main := String(r["name"]) in main_names
		var run: Array = []
		var acc := 18.0
		for j in range(pts.size() - 1):
			var a: Vector2 = pts[j]
			var b: Vector2 = pts[j + 1]
			var L := a.distance_to(b)
			if L < 0.01:
				continue
			var t := (b - a) / L
			var n := Vector2(-t.y, t.x)
			var s := 0.0
			while s < L:
				if acc >= 38.0:
					var p := a + t * s + n * side * (w * 0.5 + 0.45)
					if _inside(p) and _road_clear(p, ri) > 1.0:
						var top := _pole(p, n * -side, main)
						run.append(top)
					else:
						if run.size() > 1:
							poles.append(run)
						run = []
					acc = 0.0
				var stepl := minf(4.0, L - s)
				s += stepl
				acc += stepl
			# hydrants and newspaper boxes now and then
			if main and _rng.randf() < 0.35:
				var hp := a.lerp(b, _rng.randf()) - n * side * (w * 0.5 + 0.5)
				if _inside(hp) and _road_clear(hp, ri) > 1.5:
					_hydrant(hp)
			if main and _rng.randf() < 0.25:
				var np := a.lerp(b, _rng.randf()) - n * side * (w * 0.5 + 1.2)
				if _inside(np) and _road_clear(np, ri) > 1.5:
					_paper_box(np, t)
		if run.size() > 1:
			poles.append(run)
	for run2 in poles:
		for k in range(run2.size() - 1):
			for wi in range(3):
				var off := Vector3(0, -0.05, 0) + (Vector3(-0.9, 0, 0) if wi == 0 else (Vector3(0.9, 0, 0) if wi == 2 else Vector3(0, 0.3, 0)))
				_wire(run2[k] + off, run2[k + 1] + off)
	# stop signs at the corners where a side street meets a main one
	for ri2 in range(_roads.size()):
		var r2: Dictionary = _roads[ri2]
		if String(r2["name"]) in main_names or not bool(r2["walks"]):
			continue
		var pts2: PackedVector2Array = r2["pts"]
		for end in [0, pts2.size() - 1]:
			var e: Vector2 = pts2[end]
			if not _inside(e) or _near_main(e) > 2.0:
				continue
			var inn: Vector2 = pts2[1] if end == 0 else pts2[pts2.size() - 2]
			var dir := (inn - e).normalized()
			var nn := Vector2(-dir.y, dir.x)
			_stop_sign(e + dir * 9.0 + nn * (float(r2["w"]) * 0.5 + 0.6), -dir)


## A wooden power pole with its crossarm, insulators and a cobra-head street
## light reaching over the road; returns the crossarm's middle (for the wires).
func _pole(p: Vector2, toward_road: Vector2, light: bool) -> Vector3:
	var hgt := 10.5
	k_wood.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)), 0.16, 0.12, hgt, 10, Color(0.36, 0.28, 0.20), true)
	k_wood.box(Transform3D(Basis.looking_at(Vector3(toward_road.x, 0, toward_road.y), Vector3.UP), Vector3(p.x, hgt - 0.5, p.y)), Vector3(2.2, 0.1, 0.12), Color(0.40, 0.32, 0.22))
	for o in [-0.9, 0.0, 0.9]:
		var q := p + Vector2(toward_road.y, -toward_road.x) * float(o)
		k_glass.cylinder(Transform3D(Basis.IDENTITY, Vector3(q.x, hgt - 0.33 + (0.3 if float(o) == 0.0 else 0.0), q.y)), 0.05, 0.04, 0.18, 8, Color(0.25, 0.40, 0.30), true)
	k_metal.box_at(Vector3(p.x, hgt - 2.2, p.y), Vector3(0.35, 0.5, 0.25), Color(0.45, 0.47, 0.48))     # a transformer can on some
	if light:
		var tip := p + toward_road * 2.4
		_tube3(Vector3(p.x, hgt - 2.8, p.y), Vector3(tip.x, hgt - 2.5, tip.y), 0.04, Color(0.55, 0.56, 0.56))
		k_metal.box(Transform3D(Basis.looking_at(Vector3(toward_road.x, 0, toward_road.y), Vector3.UP), Vector3(tip.x, hgt - 2.55, tip.y)), Vector3(0.32, 0.16, 0.65), Color(0.60, 0.61, 0.60))
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(tip.x, hgt - 2.8, tip.y)
		lamp.light_color = Color(1.0, 0.75, 0.45)        # the old sodium orange
		lamp.omni_range = 14.0
		lamp.light_energy = 0.0                           # night only
		lamp.add_to_group("street_lights")
		add_child(lamp)
	return Vector3(p.x, hgt - 0.33, p.y)


func _wire(a: Vector3, b: Vector3) -> void:
	var pts: Array = []
	for k in range(9):
		var f := float(k) / 8.0
		var sag := 0.6 * 4.0 * f * (1.0 - f)
		pts.append(a.lerp(b, f) - Vector3(0, sag, 0))
	for k2 in range(pts.size() - 1):
		_tube3(pts[k2], pts[k2 + 1], 0.012, Color(0.08, 0.08, 0.08))


func _tube3(a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	k_metal.cylinder(Transform3D(Basis(x, y, x.cross(y)), a), r, r, d.length(), 6, col, false)


func _hydrant(p: Vector2) -> void:
	var y0 := CURB_H
	k_paint.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, y0, p.y)), 0.12, 0.12, 0.6, 12, Color(0.80, 0.70, 0.10), true)
	k_paint.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, y0 + 0.59, p.y)), 0.10, 0.04, 0.14, 12, Color(0.75, 0.12, 0.08), true)
	for s in [-1.0, 1.0]:
		k_paint.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(p.x + s * 0.16, y0 + 0.42, p.y)), 0.05, 0.05, 0.1, 8, Color(0.75, 0.12, 0.08), true)


func _paper_box(p: Vector2, along: Vector2) -> void:
	var b := Basis.looking_at(Vector3(along.y, 0, -along.x), Vector3.UP)
	var y0 := CURB_H
	k_metal.box(Transform3D(b, Vector3(p.x, y0 + 0.75, p.y)), Vector3(0.48, 0.45, 0.42), [Color(0.80, 0.70, 0.10), Color(0.20, 0.35, 0.60), Color(0.70, 0.12, 0.10)][_rng.randi() % 3])
	k_metal.box(Transform3D(b, Vector3(p.x, y0 + 0.27, p.y)), Vector3(0.06, 0.55, 0.06), Color(0.3, 0.3, 0.3))
	k_glass.box(Transform3D(b, Vector3(p.x, y0 + 0.8, p.y) + b.z * -0.215), Vector3(0.38, 0.22, 0.01), Color(0.6, 0.6, 0.55))


func _stop_sign(p: Vector2, facing: Vector2) -> void:
	var y0 := CURB_H
	k_metal.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, y0, p.y)), 0.03, 0.03, 2.4, 8, Color(0.6, 0.6, 0.6), true)
	var b := Basis.looking_at(Vector3(-facing.x, 0, -facing.y), Vector3.UP)
	var c := Vector3(p.x, y0 + 2.25, p.y) + Vector3(facing.x, 0, facing.y) * 0.04
	var ring: Array = []
	for i in range(8):
		var a := TAU * (float(i) + 0.5) / 8.0
		ring.append(c + b * Vector3(cos(a) * 0.38, sin(a) * 0.38, 0))
	for i2 in range(8):
		k_paint.tri(c, ring[i2], ring[(i2 + 1) % 8], Color(0.75, 0.08, 0.06), Vector3(facing.x, 0, facing.y))
		k_paint.tri(c, ring[(i2 + 1) % 8], ring[i2], Color(0.6, 0.6, 0.6), Vector3(-facing.x, 0, -facing.y))
	var l := Label3D.new()
	l.text = "STOP"
	l.font_size = 64
	l.pixel_size = 0.0028
	l.modulate = Color(1, 1, 1)
	l.outline_size = 0
	l.shaded = true
	l.position = c + Vector3(facing.x, 0, facing.y) * 0.005
	l.basis = Basis.looking_at(Vector3(-facing.x, 0, -facing.y), Vector3.UP)
	add_child(l)


const PHONE_FOOT := 1.0          # the bottom of the phone's vault above the curb

## A pedestal payphone (DESIGN_NOTES 222, from photos of the 80s pedestal
## kiosks): a black post on a bolted base plate carrying the brushed aluminium
## half-shell (rounded back corners, open front, the shelf at the bottom, the
## lit "Phone" sign across the top), and in it the three-slot coin phone: chrome
## front, black sides, coin slots on top, twelve-key pad, number card,
## instruction card, the lock, the vault with its coin return, the handset on
## its hook on the left and the armoured cord looping down into the phone.
func _payphone(p: Vector2, facing: Vector2) -> void:
	var b := Basis.looking_at(Vector3(-facing.x, 0, -facing.y), Vector3.UP)     # local +Z = toward the caller
	var o := Vector3(p.x, CURB_H, p.y)
	var P := func(x: float, y: float, z: float) -> Vector3: return o + b * Vector3(x, y, z)
	var X := func(l: Basis) -> Basis: return b * l
	var alu := Color(0.74, 0.75, 0.74)
	var chrome := Color(0.86, 0.87, 0.88)
	var blk := Color(0.07, 0.07, 0.075)
	var dark := Color(0.16, 0.16, 0.17)
	# base plate, its anchor bolts, the post
	k_metal.rbox(Transform3D(b, P.call(0, 0.015, -0.05)), Vector3(0.36, 0.03, 0.30), dark, 0.01)
	for bx in [-0.14, 0.14]:
		for bz in [-0.17, 0.07]:
			k_metal.cylinder(Transform3D(b, P.call(float(bx), 0.03, float(bz))), 0.012, 0.012, 0.014, 6, Color(0.45, 0.45, 0.45))
	k_paint.rbox(Transform3D(b, P.call(0, 0.46, -0.08)), Vector3(0.17, 0.86, 0.11), blk, 0.02)
	k_metal.box(Transform3D(b, P.call(0, 0.46, -0.023)), Vector3(0.13, 0.82, 0.004), alu)      # aluminium face on the post
	# the shell: a U section (rounded back corners) swept up from the shelf to
	# the sign box, skinned outside and in, its front edges closed
	var y0 := 0.93
	var y1 := 1.77
	var zb := -0.25
	var zf := 0.15
	var hw := 0.27
	var r := 0.07
	var t := 0.018
	var u_ring := func(y: float, ins: float) -> PackedVector3Array:
		var ring := PackedVector3Array()
		var rr := r - ins
		ring.append(Vector3(-(hw - ins), y, zf))
		for i in range(5):
			var th := PI * 0.5 * float(i) / 4.0
			ring.append(Vector3(-(hw - r) - rr * cos(th), y, zb + r - rr * sin(th)))
		for i2 in range(5):
			var th2 := PI * 0.5 - PI * 0.5 * float(i2) / 4.0
			ring.append(Vector3((hw - r) + rr * cos(th2), y, zb + r - rr * sin(th2)))
		ring.append(Vector3(hw - ins, y, zf))
		return ring
	# (corner points: back-left arc then back-right arc, from the front of each side)
	var ro: Array = [u_ring.call(y0, 0.0), u_ring.call(y1, 0.0)]
	var ri: Array = [u_ring.call(y0, t), u_ring.call(y1, t)]
	for ring_set in [[ro, false, alu], [ri, true, alu.darkened(0.08)]]:
		var rs: Array = ring_set[0]
		var a0: PackedVector3Array = rs[0]
		var a1: PackedVector3Array = rs[1]
		for i3 in range(a0.size() - 1):
			var m := (a0[i3] + a0[i3 + 1]) * 0.5
			var out := Vector3(m.x, 0, m.z - (zb + 0.2))
			if bool(ring_set[1]):
				out = -out
			k_metal.quad(o + b * a0[i3], o + b * a0[i3 + 1], o + b * a1[i3 + 1], o + b * a1[i3], ring_set[2], b * out)
	for sx in [-1.0, 1.0]:
		var ex: float = sx * (hw - t * 0.5)
		k_metal.box(Transform3D(b, P.call(ex, (y0 + y1) * 0.5, zf - 0.004)), Vector3(t + 0.004, y1 - y0, 0.012), alu.lightened(0.05))     # rolled front edge
	# the shelf at the bottom, a lip at the front
	k_metal.rbox(Transform3D(b, P.call(0, y0 - 0.02, (zb + zf) * 0.5 + 0.015)), Vector3(hw * 2.0, 0.04, zf - zb + 0.03), alu, 0.012)
	k_metal.box(Transform3D(b, P.call(0, y0 + 0.005, zf + 0.025)), Vector3(hw * 2.0 - 0.02, 0.012, 0.012), alu.lightened(0.05))
	# the sign box over the top: rounded, the lit lens across the front
	k_metal.rbox(Transform3D(b, P.call(0, y1 + 0.08, (zb + zf) * 0.5)), Vector3(hw * 2.0, 0.17, zf - zb), alu, 0.04)
	var lens := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(hw * 2.0 - 0.06, 0.12, 0.004)
	lens.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.97, 0.96, 0.90)
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.97, 0.88)
	lmat.emission_energy_multiplier = 0.6
	lens.material_override = lmat
	lens.transform = Transform3D(b, P.call(0, y1 + 0.08, zf + 0.001))
	lens.set_meta("lamp_lens", true)
	add_child(lens)
	for sx2 in [-1.0, 1.0]:
		var sl := lens.duplicate() as MeshInstance3D
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.004, 0.10, zf - zb - 0.08)
		sl.mesh = bm2
		sl.transform = Transform3D(b, P.call(float(sx2) * (hw + 0.001), y1 + 0.08, (zb + zf) * 0.5))
		add_child(sl)
	# the handset badge left of the word: blue disc, white handset
	k_paint.cylinder(Transform3D(X.call(Basis(Vector3.RIGHT, PI * 0.5)), P.call(-0.19, y1 + 0.08, zf + 0.0035)), 0.045, 0.045, 0.003, 16, Color(0.10, 0.25, 0.62))
	k_paint.box(Transform3D(X.call(Basis(Vector3.BACK, 0.7)), P.call(-0.19, y1 + 0.08, zf + 0.006)), Vector3(0.012, 0.055, 0.002), Color(0.97, 0.97, 0.97))
	for e in [-1.0, 1.0]:
		k_paint.box(Transform3D(X.call(Basis(Vector3.BACK, 0.7)), P.call(-0.19, y1 + 0.08, zf + 0.006) + b * (Basis(Vector3.BACK, 0.7) * Vector3(0.008, float(e) * 0.026, 0))), Vector3(0.02, 0.012, 0.002), Color(0.97, 0.97, 0.97))
	k_paint.box(Transform3D(b, P.call(0, y1 + 0.08, zf - 0.001)), Vector3(hw * 2.0 - 0.04, 0.14, 0.004), dark)
	var l := Label3D.new()
	l.text = "Phone"
	l.font_size = 64
	l.pixel_size = 0.0019
	l.modulate = Color(0.10, 0.25, 0.62)
	l.outline_size = 0
	l.shaded = false
	l.position = P.call(0.04, y1 + 0.075, zf + 0.006)
	l.basis = b
	add_child(l)
	# black back plate the phone bolts to, its bolts; rivet rows up the shell's
	# side seams; the post's access cover
	k_paint.box(Transform3D(b, P.call(0.0, (y0 + y1) * 0.5, zb + t + 0.003)), Vector3(hw * 2.0 - 0.12, y1 - y0 - 0.1, 0.006), blk)
	for by in [y0 + 0.08, y1 - 0.08]:
		for bx2 in [-0.17, 0.17]:
			k_metal.cylinder(Transform3D(X.call(Basis(Vector3.RIGHT, PI * 0.5)), P.call(float(bx2), float(by), zb + t + 0.006)), 0.009, 0.009, 0.006, 6, Color(0.5, 0.5, 0.5))
	for sx3 in [-1.0, 1.0]:
		for ry in range(7):
			k_metal.cylinder(Transform3D(X.call(Basis(Vector3.BACK, -float(sx3) * PI * 0.5)), P.call(float(sx3) * hw, y0 + 0.06 + float(ry) * 0.12, zb + 0.10)), 0.006, 0.006, 0.004, 6, alu.lightened(0.1))
	k_metal.rbox(Transform3D(b, P.call(0, 0.32, -0.02)), Vector3(0.10, 0.22, 0.006), alu.darkened(0.1), 0.01)
	for cy2 in [0.23, 0.41]:
		k_metal.cylinder(Transform3D(X.call(Basis(Vector3.RIGHT, PI * 0.5)), P.call(0, cy2, -0.018)), 0.007, 0.007, 0.004, 6, Color(0.5, 0.5, 0.5))
	# the post into the shell's floor: a collar
	k_paint.rbox(Transform3D(b, P.call(0, y0 - 0.06, -0.08)), Vector3(0.21, 0.04, 0.15), blk, 0.01)
	# --- the phone on the back wall ------------------------------------------
	# built at its drawing size, then scaled to the real one (21 in tall, the
	# keypad at a grown man's shoulder) about its foot on the back wall
	var pm := MeshKit.new()
	var pp := MeshKit.new()
	var labels0 := get_child_count()
	var zw := zb + t                       # the inside of the back wall
	var px := 0.03
	var fz := zw + 0.12                    # its face
	var ph := func(x: float, y: float, z: float) -> Vector3: return P.call(px + x, y, z)
	# upper housing: black case, chrome face
	pp.rbox(Transform3D(b, ph.call(0, 1.585, zw + 0.055)), Vector3(0.19, 0.37, 0.11), blk, 0.012)
	pm.box(Transform3D(b, ph.call(0, 1.585, fz - 0.005)), Vector3(0.175, 0.355, 0.01), chrome)
	# coin slots on the stepped top, tipped toward the caller: three
	# round badges (25, 10, 5) each over its slot
	var tb: Basis = X.call(Basis(Vector3.RIGHT, -0.45))
	pm.rbox(Transform3D(tb, ph.call(0, 1.795, zw + 0.075)), Vector3(0.16, 0.05, 0.075), chrome, 0.012)
	for ci in range(3):
		var cx := -0.048 + 0.048 * float(ci)
		var bc: Vector3 = ph.call(cx, 1.795, zw + 0.075) + tb * Vector3(0, 0.0, 0.039)
		pp.cylinder(Transform3D(tb * Basis(Vector3.RIGHT, PI * 0.5), bc), 0.017, 0.017, 0.003, 14, Color(0.93, 0.93, 0.9))
		pp.cylinder(Transform3D(tb * Basis(Vector3.RIGHT, PI * 0.5), bc + tb * Vector3(0, 0, 0.0015)), 0.012, 0.012, 0.002, 14, Color(0.2, 0.2, 0.22))
		pp.box(Transform3D(tb, ph.call(cx, 1.795, zw + 0.075) + tb * Vector3(0, 0.026, 0.0)), Vector3(0.024, 0.003, 0.014), blk)     # the slot on top
		var cl := Label3D.new()
		cl.text = ["25", "10", "5"][ci]
		cl.font_size = 32
		cl.pixel_size = 0.0006
		cl.modulate = Color(0.95, 0.95, 0.95)
		cl.outline_size = 0
		cl.position = bc + tb * Vector3(0, 0, 0.004)
		cl.basis = tb
		add_child(cl)
	# twelve keys (3 x 4) on their dark pad, the number card under them
	pp.box(Transform3D(b, ph.call(0.01, 1.70, fz + 0.001)), Vector3(0.10, 0.125, 0.004), dark)
	for ky in range(4):
		for kx in range(3):
			pm.rbox(Transform3D(b, ph.call(-0.02 + 0.03 * float(kx), 1.745 - 0.03 * float(ky), fz + 0.007)), Vector3(0.022, 0.022, 0.01), chrome.darkened(0.05), 0.004)
	pm.cylinder(Transform3D(X.call(Basis(Vector3.RIGHT, PI * 0.5)), ph.call(0.07, 1.745, fz)), 0.01, 0.01, 0.012, 10, chrome)   # the volume knob
	pp.box(Transform3D(b, ph.call(0.01, 1.62, fz + 0.002)), Vector3(0.07, 0.016, 0.004), Color(0.92, 0.90, 0.80))
	var lb2 := Label3D.new()
	lb2.text = "555-0142"
	lb2.font_size = 32
	lb2.pixel_size = 0.0005
	lb2.modulate = Color(0.1, 0.1, 0.1)
	lb2.outline_size = 0
	lb2.position = ph.call(0.01, 1.62, fz + 0.005)
	lb2.basis = b
	add_child(lb2)
	pp.box(Transform3D(b, ph.call(-0.025, 1.445, fz - 0.0)), Vector3(0.07, 0.02, 0.003), Color(0.8, 0.12, 0.1))
	var lb3 := Label3D.new()
	lb3.text = "911 NO COIN"
	lb3.font_size = 32
	lb3.pixel_size = 0.00045
	lb3.modulate = Color(1, 1, 1)
	lb3.outline_size = 0
	lb3.position = ph.call(-0.025, 1.445, fz + 0.002)
	lb3.basis = b
	add_child(lb3)
	# instruction card in its frame
	pm.box(Transform3D(b, ph.call(0.01, 1.53, fz + 0.002)), Vector3(0.15, 0.115, 0.006), chrome.darkened(0.15))
	pp.box(Transform3D(b, ph.call(0.01, 1.53, fz + 0.005)), Vector3(0.135, 0.1, 0.003), Color(0.93, 0.86, 0.55))
	for li in range(6):
		pp.box(Transform3D(b, ph.call(0.01, 1.565 - 0.014 * float(li), fz + 0.0068)), Vector3(0.11, 0.003, 0.001), Color(0.3, 0.28, 0.22))
	pm.cylinder(Transform3D(X.call(Basis(Vector3.RIGHT, PI * 0.5)), ph.call(0.06, 1.445, fz - 0.004)), 0.012, 0.012, 0.012, 10, chrome.darkened(0.2))   # upper lock
	# the vault under it: black case, chrome door with its lock, the coin return
	pp.rbox(Transform3D(b, ph.call(0, 1.29, zw + 0.055)), Vector3(0.19, 0.21, 0.11), blk, 0.012)
	pm.box(Transform3D(b, ph.call(0.025, 1.275, fz - 0.005)), Vector3(0.12, 0.17, 0.01), chrome)
	pm.cylinder(Transform3D(X.call(Basis(Vector3.RIGHT, PI * 0.5)), ph.call(0.025, 1.32, fz)), 0.012, 0.012, 0.01, 10, chrome.darkened(0.25))
	pm.rbox(Transform3D(b, ph.call(-0.06, 1.23, fz - 0.005)), Vector3(0.05, 0.08, 0.04), chrome, 0.008)             # coin return chute
	pp.box(Transform3D(b, ph.call(-0.06, 1.235, fz + 0.016)), Vector3(0.038, 0.05, 0.004), dark)                       # its flap
	# hook on the left side and the handset hanging in it
	var hx := -0.112
	pm.box(Transform3D(b, ph.call(hx + 0.012, 1.69, zw + 0.07)), Vector3(0.025, 0.04, 0.06), chrome)                    # hookswitch
	# the handset: a curved grip, the ear cup at the top and the mouth cup at
	# the bottom both turned in toward the phone, the cord's guard at the bottom
	var hz := fz - 0.02
	var hs := [ph.call(hx - 0.035, 1.70, hz), ph.call(hx - 0.045, 1.65, hz), ph.call(hx - 0.047, 1.60, hz), ph.call(hx - 0.045, 1.55, hz), ph.call(hx - 0.035, 1.50, hz)]
	for hi in range(hs.size() - 1):
		_pp_rod(pp, hs[hi], hs[hi + 1], 0.016, blk)
	for cup in [[1.71, 0.033], [1.49, 0.03]]:
		var cy: float = cup[0]
		var cr: float = cup[1]
		pp.cylinder(Transform3D(X.call(Basis(Vector3.BACK, -PI * 0.5)), ph.call(hx - 0.04, cy, hz)), cr * 0.75, cr, 0.035, 14, blk)
		pp.cylinder(Transform3D(X.call(Basis(Vector3.BACK, -PI * 0.5)), ph.call(hx - 0.005, cy, hz)), cr * 0.8, cr * 0.8, 0.003, 14, Color(0.18, 0.18, 0.19))
	pp.cylinder(Transform3D(b, ph.call(hx - 0.035, 1.445, hz)), 0.012, 0.016, 0.035, 10, Color(0.15, 0.35, 0.7))      # cord guard
	# armoured cord: from the bottom of the handset, a loop down, back up into
	# the phone's left side; steel coil (rings along it)
	var cord := [ph.call(hx - 0.035, 1.445, fz - 0.02), ph.call(hx - 0.03, 1.30, fz - 0.03), ph.call(hx + 0.0, 1.15, fz - 0.02), ph.call(hx + 0.03, 1.12, fz - 0.03), ph.call(hx + 0.05, 1.17, zw + 0.06), ph.call(hx + 0.03, 1.24, zw + 0.06)]
	for ci2 in range(cord.size() - 1):
		var c0: Vector3 = cord[ci2]
		var c1: Vector3 = cord[ci2 + 1]
		_pp_rod(pm, c0, c1, 0.006, Color(0.62, 0.63, 0.64))
		var n := int(c0.distance_to(c1) / 0.012)
		for ri2 in range(n):
			var pt := c0.lerp(c1, (float(ri2) + 0.5) / float(n))
			var d := (c1 - c0).normalized()
			var ax := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
			pm.cylinder(Transform3D(Basis(ax, d, ax.cross(d)), pt - d * 0.002), 0.0085, 0.0085, 0.004, 6, Color(0.70, 0.71, 0.72), false)
	var S := 0.85
	var W: Vector3 = P.call(px, 1.185, zw)
	var lift := Vector3(0, PHONE_FOOT - 1.185, 0)
	var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(S, S, S)), W - W * S + lift)
	for pair in [[pm, k_metal], [pp, k_paint]]:
		var src: MeshKit = pair[0]
		var dst: MeshKit = pair[1]
		for vi in range(src.verts.size()):
			dst.verts.append(xf * src.verts[vi])
			dst.norms.append(src.norms[vi])
			dst.cols.append(src.cols[vi])
	for ci3 in range(labels0, get_child_count()):
		var lb := get_child(ci3) as Label3D
		if lb != null:
			lb.position = xf * lb.position
			lb.pixel_size *= S


static func _pp_rod(k: MeshKit, a: Vector3, c: Vector3, r: float, col: Color) -> void:
	var d := c - a
	if d.length() < 0.001:
		return
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	k.cylinder(Transform3D(Basis(x, y, x.cross(y)), a), r, r, d.length(), 8, col, true)
	k.cylinder(Transform3D(Basis(x, y, x.cross(y)), a - y * r * 0.7), r, r, r * 1.4, 8, col, true)


## A full glass phone booth (aluminium frame, folding door).
func _booth(p: Vector2, facing: Vector2) -> void:
	var b := Basis.looking_at(Vector3(-facing.x, 0, -facing.y), Vector3.UP)
	var o := Vector3(p.x, CURB_H, p.y)
	var hw := 0.45
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			k_metal.box(Transform3D(b, o + b * Vector3(cx * hw, 1.1, cz * hw)), Vector3(0.06, 2.2, 0.06), Color(0.72, 0.73, 0.72))
	k_metal.box(Transform3D(b, o + Vector3(0, 2.25, 0)), Vector3(0.98, 0.12, 0.98), Color(0.72, 0.73, 0.72))
	k_paint.box(Transform3D(b, o + Vector3(0, 2.15, 0)), Vector3(0.96, 0.1, 0.96), Color(0.15, 0.30, 0.60))
	for side in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, -1)]:
		var sb: Vector3 = b * side
		var basis_side := Basis.looking_at(sb, Vector3.UP)
		k_glass.box(Transform3D(basis_side, o + sb * hw + Vector3(0, 1.15, 0)), Vector3(0.84, 1.7, 0.01), Color(0.55, 0.62, 0.66))
	k_metal.box(Transform3D(b, o + Vector3(0, 1.45, 0) + b.z * hw * 0.8), Vector3(0.24, 0.5, 0.12), Color(0.22, 0.22, 0.24))
	k_concrete.box(Transform3D(b, o + Vector3(0, 0.03, 0)), Vector3(1.0, 0.06, 1.0), Color(0.6, 0.6, 0.58))


func _bench(p: Vector2, facing: Vector2) -> void:
	var b := Basis.looking_at(Vector3(-facing.x, 0, -facing.y), Vector3.UP)
	var o := Vector3(p.x, CURB_H, p.y)
	for k in range(3):
		k_wood.box(Transform3D(b, o + Vector3(0, 0.45, 0) + b.z * (-0.15 + float(k) * 0.14)), Vector3(1.6, 0.04, 0.11), Color(0.50, 0.36, 0.22))
	for k2 in range(2):
		k_wood.box(Transform3D(b * Basis(Vector3.RIGHT, -0.2), o + Vector3(0, 0.75 + float(k2) * 0.15, 0) + b.z * 0.2), Vector3(1.6, 0.11, 0.04), Color(0.50, 0.36, 0.22))
	for sx in [-0.7, 0.7]:
		k_metal.box(Transform3D(b, o + Vector3(0, 0.22, 0) + b.x * float(sx)), Vector3(0.05, 0.45, 0.45), Color(0.2, 0.2, 0.2))


func _bin(p: Vector2) -> void:
	k_paint.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, CURB_H, p.y)), 0.28, 0.28, 0.9, 14, Color(0.20, 0.32, 0.22), true)
	k_metal.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, CURB_H + 0.895, p.y)), 0.30, 0.30, 0.05, 14, Color(0.45, 0.45, 0.45), true)


func _trees() -> void:
	var placed := 0
	var tries := 0
	while placed < 140 and tries < 3000:
		tries += 1
		var p := Vector2(_rng.randf_range(-radius, radius), _rng.randf_range(-radius, radius))
		if not _inside(p) or _road_clear(p, -1) < 4.0:
			continue
		var blocked := false
		for pg in get_meta("_bldg_polys", []):
			for o in [Vector2.ZERO, Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
				if Geometry2D.is_point_in_polygon(p + o, pg):
					blocked = true
			if blocked:
				break
		if blocked:
			continue
		placed += 1
		if _rng.randf() < 0.55:
			# a conifer (fir / cedar)
			var h := _rng.randf_range(9.0, 20.0)
			k_wood.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)), 0.22, 0.18, 2.0, 8, Color(0.30, 0.22, 0.16), true)
			for k in range(4):
				var f := float(k) / 4.0
				k_leaf.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 1.2 + h * f * 0.62, p.y)), h * 0.24 * (1.0 - f * 0.7), 0.05, h * 0.36, 10, Color(0.12, 0.24, 0.14).lerp(Color(0.16, 0.30, 0.16), _rng.randf()), true)
		else:
			# a maple / birch: trunk and a lumpy crown
			var h2 := _rng.randf_range(6.0, 11.0)
			k_wood.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)), 0.2, 0.14, h2 * 0.6, 8, Color(0.34, 0.28, 0.22), true)
			for k2 in range(4):
				var off := Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-0.5, 0.8), _rng.randf_range(-1.2, 1.2))
				var r := _rng.randf_range(1.6, 2.4)
				k_leaf.rbox(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(p.x, h2 * 0.75, p.y) + off), Vector3(r * 1.6, r * 1.3, r * 1.6), Color(0.22, 0.36, 0.16).lerp(Color(0.30, 0.42, 0.18), _rng.randf()), r * 0.5)


# ------------------------------------------------------------------------------
#  1982 (reference/hope/FILM_NOTES.md): the motel, the gas station, pole signs,
#  painted shop windows, the light over the main corner, the cars of the time
# ------------------------------------------------------------------------------
## The two-storey motel: white, with orange-brown panels between the units,
## an open walkway along the upper floor with its rail, stairs at the end.
func _motel(poly: PackedVector2Array, front: int, cen: Vector2) -> void:
	var h := 5.8
	var wall := Color(0.93, 0.92, 0.88)
	var panel := Color(0.72, 0.38, 0.16)
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var d := b - a
		var L := d.length()
		if L < 0.05:
			continue
		var out := Vector2(d.y, -d.x).normalized()
		var oh := Vector3(out.x, 0, out.y)
		k_siding.quad(_v3(a, 0.3), _v3(b, 0.3), _v3(b, h), _v3(a, h), wall, oh)
		k_concrete.quad(_v3(a + out * 0.03, 0.0), _v3(b + out * 0.03, 0.0), _v3(b + out * 0.03, 0.3), _v3(a + out * 0.03, 0.3), Color(0.52, 0.51, 0.48), oh)
		if i != front:
			_window_row(a, b, out, 1.0, Color(0.95, 0.95, 0.92), 3.6)
			_window_row(a, b, out, 3.9, Color(0.95, 0.95, 0.92), 3.6)
			continue
		var t := d / L
		var units := maxi(2, int(L / 3.6))
		for u in range(units):
			var c0 := a.lerp(b, float(u) / units)
			var c1 := a.lerp(b, float(u + 1) / units)
			_board(c0, c0 + t * 0.5, out, 0.3, h, 0.03, panel)                          # the coloured panel between units
			for fl in [0.0, 2.9]:
				var dc := c0 + t * 1.0
				_board(dc, dc + t * 0.9, out, fl + 0.3, fl + 2.3, 0.04, Color(0.45, 0.28, 0.16))   # the room door
				var wc := c0 + t * 2.3
				k_glass.quad(_v3(wc + out * 0.01, fl + 1.2), _v3(wc + t * 1.0 + out * 0.01, fl + 1.2), _v3(wc + t * 1.0 + out * 0.01, fl + 2.2), _v3(wc + out * 0.01, fl + 2.2), Color(0.14, 0.16, 0.18), oh)
				_board(wc - t * 0.05, wc + t * 1.05, out, fl + 1.12, fl + 1.2, 0.06, Color(0.95, 0.95, 0.92))
		# the upper walkway: its slab, posts, rail; the stair at the end
		var wa := a + out * 1.6
		var wb := b + out * 1.6
		k_concrete.quad(_v3(a, 2.95), _v3(b, 2.95), _v3(wb, 2.95), _v3(wa, 2.95), Color(0.66, 0.65, 0.62), Vector3.UP)
		k_concrete.quad(_v3(wa, 2.75), _v3(wb, 2.75), _v3(b, 2.75), _v3(a, 2.75), Color(0.55, 0.54, 0.52), Vector3.DOWN)
		k_concrete.quad(_v3(wa, 2.75), _v3(wb, 2.75), _v3(wb, 2.95), _v3(wa, 2.95), Color(0.62, 0.61, 0.58), oh)
		var np := maxi(2, int(L / 3.0))
		for k in range(np + 1):
			var pp := wa.lerp(wb, float(k) / np)
			k_metal.box_at(Vector3(pp.x, 1.4, pp.y), Vector3(0.1, 2.8, 0.1), Color(0.9, 0.9, 0.88))
			k_metal.box_at(Vector3(pp.x, 3.45, pp.y), Vector3(0.05, 1.0, 0.05), Color(0.9, 0.9, 0.88))
		_tube3(_v3(wa, 3.95), _v3(wb, 3.95), 0.035, Color(0.9, 0.9, 0.88))
		_tube3(_v3(wa, 3.45), _v3(wb, 3.45), 0.02, Color(0.9, 0.9, 0.88))
		for st in range(10):
			var f := float(st) / 10.0
			var sp := wb + t * (0.6 + f * 3.2)
			k_concrete.box_at(Vector3(sp.x, 2.95 * (1.0 - f) - 0.08, sp.y), Vector3(1.0, 0.16, 0.34) if absf(t.x) < 0.5 else Vector3(0.34, 0.16, 1.0), Color(0.6, 0.6, 0.58))
		# the sign on its pole by the road
		_pole_sign(b + out * 8.0, 7.5, "MOTEL")
	_flat_roof(poly, h, wall, false)


## A tall roadside pole sign: steel pipe, a lit box sign on top with generic words.
func _pole_sign(p: Vector2, hgt: float, text: String = "") -> void:
	if _road_clear(p, -1) < 0.8:
		p += (p - _nearest_road_point(p)).normalized() * 2.0
	var words: String = text if text != "" else ["BURGERS", "STEAKS", "MOTEL", "GAS", "SHOPPING PLAZA", "RESTAURANT", "COFFEE", "TIRES", "LIQUOR"][_rng.randi() % 9]
	k_metal.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)), 0.13, 0.13, hgt, 10, Color(0.55, 0.56, 0.56), true)
	var face := (p - _nearest_road_point(p)).normalized()
	var along := Vector2(-face.y, face.x)
	var b := Basis.looking_at(Vector3(along.x, 0, along.y), Vector3.UP)
	var bw := clampf(float(words.length()) * 0.42, 2.4, 5.5)
	var col: Color = [Color(0.85, 0.12, 0.08), Color(0.95, 0.85, 0.20), Color(0.15, 0.30, 0.65), Color(0.95, 0.95, 0.92)][_rng.randi() % 4]
	k_paint.box(Transform3D(b, Vector3(p.x, hgt + 0.6, p.y)), Vector3(0.35, 1.3, bw), col)
	k_metal.box(Transform3D(b, Vector3(p.x, hgt + 1.3, p.y)), Vector3(0.4, 0.1, bw + 0.1), Color(0.3, 0.3, 0.3))
	for sd in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = words
		l.font_size = 96
		l.pixel_size = 0.0075
		l.modulate = Color(0.08, 0.08, 0.08) if col.v > 0.8 and col.s < 0.5 or col.r > 0.9 and col.g > 0.8 else Color(1, 1, 0.95)
		l.outline_size = 0
		l.shaded = true
		l.position = Vector3(p.x, hgt + 0.6, p.y) + Vector3(along.x, 0, along.y) * 0.0 + b.x * 0.18 * sd
		l.basis = Basis.looking_at(-b.x * sd, Vector3.UP)
		add_child(l)


func _nearest_road_point(p: Vector2) -> Vector2:
	var best := p + Vector2(0, 1)
	var bd := 1e9
	for r in _roads:
		var pts: PackedVector2Array = r["pts"]
		for j in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])
			if p.distance_to(q) < bd:
				bd = p.distance_to(q)
				best = q
	return best


## The light hung over the main corner on a span wire between two poles, its
## red / amber / green heads facing each way.
func _traffic_lights(c: Vector2) -> void:
	var p0 := c + Vector2(-9.0, -8.5)
	var p1 := c + Vector2(9.0, 8.5)
	for p in [p0, p1]:
		k_wood.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)), 0.16, 0.13, 9.0, 10, Color(0.36, 0.28, 0.20), true)
	_tube3(Vector3(p0.x, 7.6, p0.y), Vector3(c.x, 7.0, c.y), 0.015, Color(0.1, 0.1, 0.1))
	_tube3(Vector3(c.x, 7.0, c.y), Vector3(p1.x, 7.6, p1.y), 0.015, Color(0.1, 0.1, 0.1))
	for k in range(4):
		var b := Basis(Vector3.UP, PI * 0.5 * float(k) + PI * 0.25)
		var o := Vector3(c.x, 6.3, c.y)
		k_paint.box(Transform3D(b, o + b.z * 0.2), Vector3(0.36, 1.05, 0.25), Color(0.80, 0.68, 0.12))
		var cols := [Color(0.9, 0.1, 0.05), Color(0.35, 0.25, 0.05), Color(0.05, 0.3, 0.1)]
		for li in range(3):
			k_glass.cylinder(Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), o + b.z * 0.33 + Vector3(0, 0.32 - float(li) * 0.32, 0)), 0.11, 0.11, 0.02, 14, cols[li], true)
			k_paint.box(Transform3D(b, o + b.z * 0.38 + Vector3(0, 0.40 - float(li) * 0.32, 0)), Vector3(0.28, 0.03, 0.12), Color(0.15, 0.15, 0.15))   # visor
	var red := OmniLight3D.new()
	red.position = Vector3(c.x, 6.6, c.y)
	red.light_color = Color(1, 0.15, 0.1)
	red.omni_range = 4.0
	red.light_energy = 0.6
	add_child(red)


## The gas station on the corner: a concrete island with two old round-shouldered
## pumps, a flat canopy on two posts, oil cans and a bin, the pole sign.
func _gas_station() -> void:
	var p := GAS_CORNER + Vector2(14.0, -14.0)
	for k in range(30):
		if _road_clear(p, -1) > 6.0 and not _in_building(p, 5.0):
			break
		p += Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-4, 4))
	var face := (p - _nearest_road_point(p)).normalized()
	var along := Vector2(-face.y, face.x)
	var b := Basis.looking_at(Vector3(face.x, 0, face.y), Vector3.UP)
	var o := Vector3(p.x, 0, p.y)
	k_concrete.box(Transform3D(b, o + Vector3(0, 0.1, 0)), Vector3(1.2, 0.2, 5.5), Color(0.7, 0.7, 0.68))         # the island
	k_asphalt.box(Transform3D(b, o + Vector3(0, 0.01, 0)), Vector3(14.0, 0.04, 16.0), Color(0.24, 0.24, 0.25))   # the apron
	for z in [-1.4, 1.4]:
		var pp := o + b.z * float(z) + Vector3(0, 0.2, 0)
		k_paint.rbox(Transform3D(b, pp + Vector3(0, 0.75, 0)), Vector3(0.55, 1.5, 0.75), Color(0.94, 0.94, 0.92), 0.12)   # the pump body
		k_paint.box(Transform3D(b, pp + Vector3(0, 1.55, 0)), Vector3(0.5, 0.25, 0.7), Color(0.20, 0.35, 0.70))           # its lit top
		k_glass.box(Transform3D(b, pp + Vector3(0, 1.05, 0) + b.x * 0.28), Vector3(0.01, 0.35, 0.45), Color(0.8, 0.8, 0.7))  # the dials
		k_metal.box(Transform3D(b, pp + Vector3(0, 0.9, 0) + b.x * -0.3), Vector3(0.08, 0.3, 0.1), Color(0.2, 0.2, 0.2))   # the nozzle
		_tube3(pp + Vector3(0, 0.9, 0) + b.x * -0.3, pp + Vector3(0, 0.25, 0) + b.x * -0.45, 0.02, Color(0.08, 0.08, 0.08))
	for z2 in [-3.0, 3.0]:
		k_metal.box(Transform3D(b, o + b.z * float(z2) + Vector3(0, 2.4, 0)), Vector3(0.3, 4.8, 0.3), Color(0.9, 0.9, 0.88))
	k_paint.box(Transform3D(b, o + Vector3(0, 4.95, 0)), Vector3(7.0, 0.5, 8.0), Color(0.95, 0.95, 0.93))
	k_paint.box(Transform3D(b, o + Vector3(0, 4.95, 0)), Vector3(7.05, 0.18, 8.05), Color(0.20, 0.35, 0.70))
	_pole_sign(p + face * 9.0 + along * 4.0, 8.0, "GAS")


func _in_building(p: Vector2, margin: float = 0.0) -> bool:
	for pg in get_meta("_bldg_polys", []):
		for o in [Vector2.ZERO, Vector2(margin, 0), Vector2(-margin, 0), Vector2(0, margin), Vector2(0, -margin)]:
			if Geometry2D.is_point_in_polygon(p + o, pg):
				return true
	return false


## Cars of the time parked along the main streets, nose to the curb or parallel.
const CAR_COLS := [Color(0.45, 0.30, 0.16), Color(0.85, 0.80, 0.62), Color(0.42, 0.45, 0.22), Color(0.45, 0.10, 0.10), Color(0.55, 0.68, 0.80), Color(0.92, 0.92, 0.88), Color(0.20, 0.25, 0.40), Color(0.70, 0.45, 0.15), Color(0.30, 0.30, 0.30), Color(0.60, 0.55, 0.40)]


func _parked_cars() -> void:
	for ri in range(_roads.size()):
		var r: Dictionary = _roads[ri]
		if not (String(r["name"]) in main_names):
			continue
		var pts: PackedVector2Array = r["pts"]
		var w: float = r["w"]
		for j in range(pts.size() - 1):
			var a: Vector2 = pts[j]
			var b: Vector2 = pts[j + 1]
			var L := a.distance_to(b)
			if L < 6.0:
				continue
			var t := (b - a) / L
			var n := Vector2(-t.y, t.x)
			var s := 4.0
			while s < L - 4.0:
				for sd in [-1.0, 1.0]:
					if _rng.randf() < 0.45:
						var cp := a + t * s + n * float(sd) * (w * 0.5 - 1.1)
						if _inside(cp) and _road_clear(cp, ri) > 4.0:
							_car(cp, t * (1.0 if _rng.randf() < 0.5 else -1.0) if float(sd) > 0.0 else -t)
				s += 6.2


## One car of about 1975: a long low body, the greenhouse, chrome bumpers, wheels.
## kinds: sedan, wagon, pickup, 4x4 wagon, the VW-style bus.
func _car(p: Vector2, fwd: Vector2, kind: String = "", col: Color = Color(0, 0, 0, 0)) -> void:
	if kind == "":
		kind = ["sedan", "sedan", "sedan", "wagon", "pickup", "pickup", "4x4", "bus"][_rng.randi() % 8]
	if col.a == 0.0:
		col = CAR_COLS[_rng.randi() % CAR_COLS.size()]
	var b := Basis.looking_at(Vector3(fwd.x, 0, fwd.y), Vector3.UP)
	var o := Vector3(p.x, 0, p.y)
	var L := 5.4
	var W := 1.95
	var lift := 0.0
	var cab := [-0.4, 1.2]       # roof from / to along the car (front -z)
	var cab_h := 0.55
	match kind:
		"wagon":
			L = 5.5
			cab = [-0.4, 2.3]
		"pickup":
			L = 5.3
			cab = [-0.9, 0.6]
			cab_h = 0.65
		"4x4":
			L = 4.6
			W = 2.0
			lift = 0.25
			cab = [-0.6, 2.0]
			cab_h = 0.7
		"bus":
			L = 4.4
			W = 1.75
			cab = [-2.0, 2.1]
			cab_h = 1.0
	var by := 0.35 + lift
	var bh := 0.6 if kind != "bus" else 0.85
	# the body (a rounded box), the hood / deck lines, the greenhouse
	k_paint.rbox(Transform3D(b, o + Vector3(0, by + bh * 0.5, 0)), Vector3(W, bh, L), col, 0.08)
	var gz0: float = cab[0]
	var gz1: float = cab[1]
	var gl := gz1 - gz0
	var gm := (gz0 + gz1) * 0.5
	if kind == "pickup":
		k_paint.box(Transform3D(b, o + Vector3(0, by + bh + 0.04, 1.6)), Vector3(W, 0.08, 2.0), col.darkened(0.25))   # the bed (open)
		k_trim.box(Transform3D(b, o + Vector3(0, by + bh * 0.6, 1.6)), Vector3(W - 0.2, 0.05, 1.9), Color(0.15, 0.15, 0.15))
	k_paint.rbox(Transform3D(b, o + Vector3(0, by + bh + cab_h * 0.5, gm)), Vector3(W - 0.18, cab_h, gl), col if kind != "bus" else Color(0.92, 0.92, 0.88), 0.07)
	k_glass.box(Transform3D(b, o + Vector3(0, by + bh + cab_h * 0.45, gm)), Vector3(W - 0.15, cab_h * 0.7, gl - 0.25), Color(0.12, 0.15, 0.18))
	# chrome bumpers, the grille, lights
	for e in [-1.0, 1.0]:
		k_metal.box(Transform3D(b, o + Vector3(0, by + 0.08, float(e) * (L * 0.5 + 0.05))), Vector3(W + 0.05, 0.16, 0.12), Color(0.85, 0.86, 0.86))
	k_trim.box(Transform3D(b, o + Vector3(0, by + 0.32, -L * 0.5 - 0.01)), Vector3(W * 0.6, 0.25, 0.04), Color(0.2, 0.2, 0.2))
	for sx in [-1.0, 1.0]:
		k_glass.box(Transform3D(b, o + Vector3(float(sx) * (W * 0.5 - 0.25), by + 0.34, -L * 0.5 - 0.02)), Vector3(0.3, 0.16, 0.03), Color(0.95, 0.95, 0.85))
		k_glass.box(Transform3D(b, o + Vector3(float(sx) * (W * 0.5 - 0.2), by + 0.34, L * 0.5 + 0.02)), Vector3(0.28, 0.14, 0.03), Color(0.7, 0.08, 0.05))
	# the wheels
	var wr := 0.34 + lift * 0.4
	for wz in [-L * 0.5 + 0.9, L * 0.5 - 0.95]:
		for wx in [-1.0, 1.0]:
			var wc := o + b * Vector3(float(wx) * (W * 0.5 - 0.2), wr, float(wz))
			var wb := b * Basis(Vector3.BACK, PI * 0.5)            # the wheel's axle along the car's x
			k_trim.cylinder(Transform3D(wb, wc - wb.y * 0.12), wr, wr, 0.24, 14, Color(0.06, 0.06, 0.06), true)
			k_metal.cylinder(Transform3D(wb, wc + b.x * float(wx) * 0.12 - wb.y * 0.005), wr * 0.55, wr * 0.55, 0.012, 12, Color(0.75, 0.75, 0.74), true)


# ------------------------------------------------------------------------------
#  Materials and meshes
# ------------------------------------------------------------------------------
func _tex(kind: String) -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	for y in range(s):
		for x in range(s):
			var v := 0.5
			match kind:
				"siding":            # lap siding: a shadow line under each board, 16 px boards
					var r := y % 16
					v = 1.0 - 0.32 * smoothstep(12.0, 16.0, float(r)) + 0.04 * sin(float(x) * 0.7 + float(y))
				"brick":             # running bond, mortar lines
					var row := y / 8
					var xo := (x + (16 if row % 2 == 1 else 0)) % 32
					var mortar := (y % 8 == 0) or (xo == 0)
					v = 1.25 if mortar else (0.85 + 0.15 * sin(float(row * 37 + (x + (16 if row % 2 == 1 else 0)) / 32 * 13)))
				"concrete":
					v = 0.92 + 0.08 * randf()
				"asphalt":
					v = 0.85 + 0.25 * randf() * randf()
				"roof":              # asphalt shingles: rows with staggered tabs
					var rr := y / 10
					var tab := ((x + (8 if rr % 2 == 1 else 0)) / 16) % 2
					v = 0.85 + 0.1 * float(tab) - 0.25 * float(y % 10 == 9) + 0.06 * randf()
				"grass":
					v = 0.8 + 0.35 * randf()
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _mat(tex: String, scale: float, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	if tex != "":
		m.albedo_texture = _tex(tex)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC   # crisp at a glancing angle
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
	return m


func _add(k: MeshKit, nm: String, m: Material, shadows: bool = true) -> void:
	if k.is_empty():
		return
	var mi := k.instance(nm)
	mi.material_override = m
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _finish() -> void:
	_add(k_grass, "Grass", _mat("grass", 0.25, 1.0), false)
	_add(k_asphalt, "Asphalt", _mat("asphalt", 0.6, 0.9), false)
	_add(k_concrete, "Concrete", _mat("concrete", 0.5, 0.85))
	_add(k_paint, "Paint", _mat("", 1.0, 0.6))
	_add(k_siding, "Siding", _mat("siding", 1.0 / 2.6, 0.8))       # boards ~16 cm
	_add(k_brick, "Brick", _mat("brick", 1.0 / 1.4, 0.9))
	_add(k_trim, "Trim", _mat("", 1.0, 0.6))
	_add(k_roof, "Roofs", _mat("roof", 1.0 / 2.0, 0.9))
	_add(k_metal, "Metal", _mat("", 1.0, 0.4, 0.6))
	_add(k_wood, "Wood", _mat("", 1.0, 0.9))
	var gm := _mat("", 1.0, 0.05, 0.3)
	gm.metallic_specular = 1.0
	_add(k_glass, "Glass", gm)
	var lm := _mat("grass", 0.6, 0.95)
	_add(k_leaf, "Trees", lm)
