extends Node3D
## The town's civic buildings (DESIGN_NOTES 234, Dave: "church, town hall,
## police station, fire station, a couple of houses, a gas station, general
## store"), in the look of his Skagway photo, as they stood in the '80s:
##   0 church       white clapboard, a steeple with the bell, lancet windows
##   1 town_hall    two storeys of painted wood, a clock cupola, a flagpole
##   2 police       a low concrete-block station (a '60s addition), flat roof
##   3 fire_station the volunteer fire department: two tall bay doors, the
##                  hose-drying tower, the siren on its pole
##   4 gas_station  a canopy over two pump islands, the station with its
##                  service bay, the price sign (no brand), the air hose
## Origin: the front middle at the street, the street toward -Z.
## Lab: "civic" (all five in a row). make_variant(i) builds one.

const Kits = preload("res://scripts/assets/kits.gd")

const WHITE := Color(0.94, 0.93, 0.89)
const TRIM := Color(0.30, 0.38, 0.32)
const ROOF := Color(0.58, 0.59, 0.60)


func _ready() -> void:
	if get_child_count() > 0:
		return
	for i in range(5):
		var n: Node3D = make_variant(i)
		n.position = Vector3(float(i) * 26.0, 0, 0)
		add_child(n)


static func make() -> Node3D:
	return make_variant(0)


static func make_variant(i: int) -> Node3D:
	var K := Kits.new()
	match i:
		0: _church(K)
		1: _town_hall(K)
		2: _police(K)
		3: _fire_station(K)
		_: _gas_station(K)
	var n := K.node(["church", "town_hall", "police", "fire_station", "gas_station"][clampi(i, 0, 4)])
	for l in K.get_meta("labels", []):
		n.add_child(l)
	return n


# --- helpers ------------------------------------------------------------------
static func _blue() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.35, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.2, 0.35, 1.0)
	m.emission_energy_multiplier = 2.0
	return m


static func _glass() -> Material:
	return load("res://scripts/assets/lookout_cab.gd")._glass()


static func _label(K: Kits, text: String, at: Vector3, px: float, col: Color, yaw: float = PI) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = px
	l.modulate = col
	l.position = at
	l.rotation.y = yaw
	l.shaded = true
	var arr: Array = K.get_meta("labels", [])
	arr.append(l)
	K.set_meta("labels", arr)


## A gable-roofed box: walls (clapboard or other), the gable ends, the roof.
static func _gabled(K: Kits, c: Vector3, w: float, d: float, h: float, pitch: float, wall_key: String, wall_col: Color, roof_key: String, roof_col: Color, id: String) -> float:
	var hw := w * 0.5
	var hd := d * 0.5
	K.piece(id + "_walls", {"mat": "timber", "kind": "panel", "t": 0.15, "size": Vector2(w * 2.0 + d * 2.0, h), "normal": Vector3(0, 0, -1), "ground": true, "links": []})
	Kits.box(K.k(wall_key), c + Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall_col)
	var rise := hw * pitch
	for gz in [-hd, hd]:
		K.k(wall_key).tri(c + Vector3(-hw, h, gz), c + Vector3(hw, h, gz), c + Vector3(0, h + rise, gz), wall_col, Vector3(0, 0, signf(gz)))
	K.piece(id + "_roof", {"mat": "steel_sheet", "kind": "panel", "t": 0.0005, "size": Vector2(d, hw * 1.4), "normal": Vector3.UP, "links": [id + "_walls"]})
	var ov := 0.4
	for side in [-1.0, 1.0]:
		var e0 := c + Vector3(side * (hw + ov), h - ov * pitch, -hd - ov)
		var e1 := c + Vector3(side * (hw + ov), h - ov * pitch, hd + ov)
		var r0 := c + Vector3(0, h + rise + 0.04, -hd - ov)
		var r1 := c + Vector3(0, h + rise + 0.04, hd + ov)
		K.k(roof_key).quad(e0, e1, r1, r0, roof_col, Vector3(side * pitch, 1, 0).normalized())
		K.k(roof_key).quad(e0 - Vector3(0, 0.04, 0), r0 - Vector3(0, 0.04, 0), r1 - Vector3(0, 0.04, 0), e1 - Vector3(0, 0.04, 0), roof_col.darkened(0.4), Vector3(-side * pitch, -1, 0).normalized())
	return rise


static func _window(K: Kits, at: Vector3, w: float, h: float, trim: Color, yaw: float = 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	K.k_mat("glass", _glass()).box(Transform3D(b, at), Vector3(w, h, 0.03), Color(0.09, 0.11, 0.13))
	for tb in [[0.0, h * 0.5 + 0.05, w + 0.2, 0.1], [0.0, -h * 0.5 - 0.04, w + 0.16, 0.08], [-w * 0.5 - 0.05, 0.0, 0.1, h + 0.1], [w * 0.5 + 0.05, 0.0, 0.1, h + 0.1], [0.0, 0.0, w, 0.04]]:
		K.k("paint_wood").box(Transform3D(b, at + b * Vector3(float(tb[0]), float(tb[1]), -0.03)), Vector3(float(tb[2]), float(tb[3]), 0.05), trim)


# --- 0: the church --------------------------------------------------------------
static func _church(K: Kits) -> void:
	var c := Vector3(0, 0.5, 9.0)
	Kits.box(K.k("cutstone"), Vector3(0, 0.25, 9.0), Vector3(9.4, 0.5, 14.4), Color(0.8, 0.78, 0.74))
	_gabled(K, c, 9.0, 14.0, 5.2, 1.2, "clapboard", WHITE, "corr", ROOF, "nave")
	# lancet windows down each side
	for side in [-1.0, 1.0]:
		for k in range(4):
			var z := c.z - 5.0 + 3.3 * float(k)
			_window(K, Vector3(side * 4.52, c.y + 2.6, z), 0.9, 2.4, TRIM, PI * 0.5 * side)
	# the steeple: a square tower at the front, the belfry with its louvers, the spire
	var t := Vector3(0, c.y, c.z - 7.0 - 1.4)
	K.piece("steeple", {"mat": "timber", "kind": "member", "a": t, "b": t + Vector3(0, 17.0, 0), "sec": Vector2(2.8, 2.8), "fill": 0.2, "ground": true, "links": ["nave_walls"]})
	Kits.box(K.k("clapboard"), t + Vector3(0, 4.5, 0), Vector3(2.8, 9.0, 2.8), WHITE)
	Kits.box(K.k("paint_wood"), t + Vector3(0, 10.0, 0), Vector3(2.4, 2.0, 2.4), WHITE)
	for s in range(4):
		var b := Basis(Vector3.UP, PI * 0.5 * float(s))
		K.k("plain").box(Transform3D(b, t + Vector3(0, 10.0, 0) + b * Vector3(0, 0, -1.21)), Vector3(1.2, 1.4, 0.02), Color(0.12, 0.12, 0.12))     # the louvered openings
	K.k("plain").cylinder(Transform3D(Basis.IDENTITY, t + Vector3(0, 9.4, 0)), 0.45, 0.25, 0.7, 12, Color(0.55, 0.45, 0.2))           # the bell
	K.k("corr").cylinder(Transform3D(Basis.IDENTITY, t + Vector3(0, 11.0, 0)), 1.9, 0.02, 6.0, 8, ROOF, true)                            # the spire
	Kits.rod(K.k("plain"), t + Vector3(0, 17.0, 0), t + Vector3(0, 18.4, 0), 0.04, Color(0.2, 0.2, 0.2))
	Kits.box(K.k("plain"), t + Vector3(0, 18.0, 0), Vector3(0.6, 0.06, 0.06), Color(0.2, 0.2, 0.2))
	# the doors, the steps
	K.k("paint_wood").box(Transform3D(Basis.IDENTITY, t + Vector3(0, 1.3, -1.42)), Vector3(1.6, 2.6, 0.06), Color(0.45, 0.20, 0.15))
	for st in range(3):
		Kits.box(K.k("cutstone"), Vector3(0, 0.12 + 0.17 * float(st), t.z - 1.9 - 0.3 * float(2 - st)), Vector3(2.6, 0.17, 0.3 + 0.3 * float(2 - st)), Color(0.8, 0.78, 0.74))
	_window(K, t + Vector3(0, 6.2, -1.42), 0.8, 1.6, TRIM)


# --- 1: the town hall -------------------------------------------------------------
static func _town_hall(K: Kits) -> void:
	var c := Vector3(0, 0.6, 7.5)
	var paint := Color(0.88, 0.88, 0.85)          # white-painted (the aerial reference)
	Kits.box(K.k("cutstone"), Vector3(0, 0.3, 7.5), Vector3(12.4, 0.6, 15.4), Color(0.78, 0.76, 0.72))
	var rise := _gabled(K, c, 12.0, 15.0, 7.4, 0.55, "clapboard", paint, "corr", Color(0.40, 0.18, 0.14), "hall")
	for f in range(2):
		for k in range(4):
			var x := -4.5 + 3.0 * float(k)
			if f == 0 and absf(x) < 1.6:
				continue
			_window(K, Vector3(x, c.y + 1.6 + 3.5 * float(f), c.z - 7.52), 1.0, 2.0, WHITE)
	# the double doors under a pediment, the steps
	K.k("paint_wood").box(Transform3D(Basis.IDENTITY, Vector3(0, c.y + 1.35, c.z - 7.53)), Vector3(1.8, 2.7, 0.06), Color(0.30, 0.22, 0.16))
	for side in [-1.0, 1.0]:
		K.k("paint_wood").tri(Vector3(side * 1.6, c.y + 3.0, c.z - 7.6), Vector3(0, c.y + 3.7, c.z - 7.6), Vector3(0, c.y + 3.0, c.z - 7.6), WHITE, Vector3(0, 0, -1))
	_label(K, "TOWN HALL", Vector3(0, c.y + 7.9, c.z - 7.58), 0.006, Color(0.2, 0.18, 0.15))
	# the cupola with its clock faces on the ridge
	var cu := Vector3(0, c.y + 7.4 + rise, c.z)
	Kits.box(K.k("paint_wood"), cu + Vector3(0, 0.9, 0), Vector3(2.0, 1.8, 2.0), WHITE)
	for s in range(4):
		var b := Basis(Vector3.UP, PI * 0.5 * float(s))
		K.k("plain").cylinder(Transform3D(b * Basis(Vector3.RIGHT, -PI * 0.5), cu + Vector3(0, 1.0, 0) + b * Vector3(0, 0, -1.02)), 0.7, 0.7, 0.02, 20, Color(0.95, 0.94, 0.88))
		K.k("plain").box(Transform3D(b, cu + Vector3(0, 1.15, 0) + b * Vector3(0, 0, -1.04)), Vector3(0.05, 0.45, 0.01), Color(0.1, 0.1, 0.1))
	K.k("corr").cylinder(Transform3D(Basis.IDENTITY, cu + Vector3(0, 1.8, 0)), 1.5, 0.05, 1.6, 4, Color(0.40, 0.18, 0.14), true)
	# the flagpole by the steps
	Kits.rod(K.k("galv"), Vector3(4.5, 0, 0.5), Vector3(4.5, 10.0, 0.5), 0.05, Color.WHITE, 8)
	K.k("plain").box(Transform3D(Basis.IDENTITY, Vector3(4.5 + 0.75, 9.3, 0.5)), Vector3(1.5, 0.95, 0.01), Color(0.7, 0.15, 0.15))


# --- 2: the police station ---------------------------------------------------------
static func _police(K: Kits) -> void:
	var w := 11.0
	var d := 9.0
	K.piece("walls", {"mat": "block", "kind": "panel", "t": 0.2, "size": Vector2(w * 2.0 + d * 2.0, 3.4), "normal": Vector3(0, 0, -1), "ground": true, "links": []})
	Kits.box(K.k("concrete"), Vector3(0, 1.7, 2.0 + d * 0.5), Vector3(w, 3.4, d), Color(0.92, 0.90, 0.84))
	K.piece("roof", {"mat": "timber", "kind": "panel", "t": 0.25, "size": Vector2(w, d), "normal": Vector3.UP, "links": ["walls"]})
	Kits.box(K.k("paint"), Vector3(0, 3.5, 2.0 + d * 0.5), Vector3(w + 0.4, 0.2, d + 0.4), Color(0.30, 0.32, 0.36))     # the fascia
	for x in [-3.5, 3.5]:
		_window(K, Vector3(x, 1.7, 1.98), 2.2, 1.2, Color(0.55, 0.56, 0.58))
	K.k_mat("glass", _glass()).box(Transform3D(Basis.IDENTITY, Vector3(0, 1.15, 1.97)), Vector3(1.0, 2.2, 0.03), Color(0.1, 0.12, 0.14))
	Kits.box(K.k("paint"), Vector3(0, 2.45, 1.4), Vector3(2.4, 0.12, 1.4), Color(0.30, 0.32, 0.36))            # the door canopy
	_label(K, "POLICE", Vector3(0, 2.9, 1.95), 0.007, Color(0.12, 0.18, 0.40))
	# the light over the door and the radio antenna on the roof
	K.k_mat("lamp", load("res://scripts/assets/glow.gd").get_lamp()).cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 2.2, 1.9)), 0.12, 0.12, 0.2, 8, Color.WHITE)
	Kits.rod(K.k("galv"), Vector3(4.0, 3.6, 5.0), Vector3(4.0, 11.0, 5.0), 0.03, Color.WHITE, 5)
	# the blue light on the roof over the door
	K.k_mat("beacon_b", _blue()).cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 3.62, 3.0)), 0.18, 0.15, 0.3, 10, Color.WHITE)


# --- 3: the fire station -------------------------------------------------------------
static func _fire_station(K: Kits) -> void:
	var w := 14.0
	var d := 16.0
	var red := Color(0.50, 0.17, 0.13)          # weathered barn red
	var c := Vector3(0, 0, 1.0 + d * 0.5)
	_gabled(K, c, w, d, 5.6, 0.4, "clapboard", red, "corr", ROOF, "hall")
	# the two bay doors (overhead, white panels) and the man door
	for x in [-3.4, 3.4]:
		K.piece("bay_%d" % int(x), {"mat": "steel_sheet", "kind": "panel", "t": 0.001, "size": Vector2(4.0, 4.3), "normal": Vector3(0, 0, -1), "links": ["hall_walls"]})
		Kits.box(K.k("paint"), Vector3(x, 2.15, 0.97), Vector3(4.0, 4.3, 0.05), Color(0.92, 0.92, 0.90))
		for p in range(6):
			Kits.box(K.k("paint"), Vector3(x, 0.35 + 0.72 * float(p), 0.94), Vector3(4.0, 0.03, 0.02), Color(0.75, 0.75, 0.73))
		K.k_mat("glass", _glass()).box(Transform3D(Basis.IDENTITY, Vector3(x, 3.25, 0.93)), Vector3(3.4, 0.4, 0.02), Color(0.1, 0.12, 0.14))
	_label(K, "VOLUNTEER FIRE DEPT", Vector3(0, 5.0, 0.93), 0.0055, Color(0.96, 0.95, 0.90))
	K.k("paint_wood").box(Transform3D(Basis.IDENTITY, Vector3(6.3, 1.05, 0.96)), Vector3(0.9, 2.1, 0.05), WHITE)
	# the hose tower at the back corner (tall, to hang the hose to dry)
	var ht := Vector3(w * 0.5 - 1.6, 0, 1.0 + d - 1.6)
	K.piece("hose_tower", {"mat": "timber", "kind": "member", "a": ht, "b": ht + Vector3(0, 11.0, 0), "sec": Vector2(3.0, 3.0), "fill": 0.2, "ground": true, "links": ["hall_walls"]})
	Kits.box(K.k("clapboard"), ht + Vector3(0, 5.5, 0), Vector3(3.0, 11.0, 3.0), red)
	K.k("corr").cylinder(Transform3D(Basis.IDENTITY, ht + Vector3(0, 11.0, 0)), 2.3, 0.05, 1.4, 4, ROOF, true)
	# the siren on its pole beside the station
	Kits.rod(K.k("timber"), Vector3(-w * 0.5 - 2.0, 0, 3.0), Vector3(-w * 0.5 - 2.0, 9.0, 3.0), 0.14, Color(0.6, 0.5, 0.4), 8)
	K.k("paint").cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-w * 0.5 - 2.0 + 0.4, 9.2, 3.0)), 0.35, 0.45, 0.8, 12, red)
	# the apron in front of the bays
	Kits.box(K.k("concrete"), Vector3(0, 0.02, -4.0), Vector3(w, 0.06, 10.0), Color(0.85, 0.84, 0.80))


# --- 4: the gas station ---------------------------------------------------------------
static func _gas_station(K: Kits) -> void:
	# the station: a small box with the office and one service bay at the back of the lot
	var bz := 14.0
	K.piece("station", {"mat": "block", "kind": "panel", "t": 0.2, "size": Vector2(40.0, 4.0), "normal": Vector3(0, 0, -1), "ground": true, "links": []})
	Kits.box(K.k("concrete"), Vector3(0, 2.0, bz + 4.0), Vector3(13.0, 4.0, 8.0), Color(0.95, 0.94, 0.90))
	Kits.box(K.k("paint"), Vector3(0, 4.15, bz + 4.0), Vector3(13.4, 0.35, 8.4), Color(0.17, 0.30, 0.22))         # the fascia band
	K.k_mat("glass", _glass()).box(Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.6, bz - 0.02)), Vector3(5.0, 2.2, 0.03), Color(0.1, 0.12, 0.14))
	Kits.box(K.k("paint"), Vector3(3.3, 1.8, bz - 0.03), Vector3(3.6, 3.4, 0.05), Color(0.85, 0.86, 0.86))          # the bay door
	_label(K, "GAS  -  SERVICE", Vector3(0, 4.15, bz - 0.25), 0.006, Color(0.95, 0.95, 0.92))
	# the canopy on its two columns over the pump islands
	K.piece("canopy", {"mat": "steel_sheet", "kind": "panel", "t": 0.002, "size": Vector2(12.0, 7.0), "normal": Vector3.UP, "links": []})
	Kits.box(K.k("paint"), Vector3(0, 4.6, 5.0), Vector3(12.0, 0.7, 7.0), Color(0.95, 0.95, 0.93))
	Kits.box(K.k("paint"), Vector3(0, 4.6, 5.0), Vector3(12.1, 0.3, 7.1), Color(0.17, 0.30, 0.22))
	for x in [-3.0, 3.0]:
		K.piece("column_%d" % int(x), {"mat": "steel", "kind": "member", "a": Vector3(x, 0, 5.0), "b": Vector3(x, 4.3, 5.0), "sec": Vector2(0.3, 0.3), "fill": 0.2, "ground": true, "links": ["canopy"]})
		Kits.box(K.k("paint"), Vector3(x, 2.15, 5.0), Vector3(0.3, 4.3, 0.3), Color(0.95, 0.95, 0.93))
		# the island and its two pumps (1980s: a tall box, the dial faces, the hose)
		Kits.box(K.k("concrete"), Vector3(x, 0.1, 5.0), Vector3(1.2, 0.2, 4.0), Color(0.85, 0.84, 0.8))
		for pz in [3.8, 6.2]:
			Kits.box(K.k("paint"), Vector3(x, 0.95, pz), Vector3(0.7, 1.5, 0.5), Color(0.92, 0.92, 0.90))
			Kits.box(K.k("paint"), Vector3(x, 1.4, pz - 0.26), Vector3(0.55, 0.45, 0.02), Color(0.17, 0.30, 0.22))
			Kits.rod(K.k("plain"), Vector3(x + 0.36, 1.2, pz), Vector3(x + 0.6, 0.3, pz + 0.3), 0.02, Color(0.08, 0.08, 0.08), 4)
	# the price sign on its pole by the street
	Kits.rod(K.k("galv"), Vector3(-6.5, 0, -1.0), Vector3(-6.5, 5.0, -1.0), 0.08, Color.WHITE, 8)
	Kits.box(K.k("paint"), Vector3(-6.5, 5.6, -1.0), Vector3(2.2, 1.4, 0.2), Color(0.95, 0.95, 0.93))
	_label(K, "GAS\n1.19", Vector3(-6.5, 5.6, -1.12), 0.006, Color(0.15, 0.25, 0.45))
	# the lot: asphalt
	Kits.box(K.k("asphalt"), Vector3(0, 0.02, 7.0), Vector3(18.0, 0.04, 18.0), Color.WHITE)
