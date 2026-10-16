extends "res://scripts/town_block.gd"
## Harry's Bush Air (DESIGN_NOTES 226, Dave): his home strip just outside town,
## 1982. A dirt road off the highway past the mailbox and the sign, down to a
## ~600 m dirt runway; a small old corrugated hangar he lives out of - a
## plywood room in the back corner with a cot, a heater, the radios, a phone,
## a rabbit-ear TV, magazines, the calendar and the chart, a storage loft over
## it. He flies anything from cargo to people, and he's the volunteer forest
## firefighter: the fire cache is in the hangar, the danger sign by the road.
## Built in the town kit (town_block.gd) plus corrugated steel and plywood.
## Local frame: the hangar door's middle at the origin, the door facing -Z
## (toward the runway), x east.  References: reference/home_strip/REFERENCE.txt

const COMPANY := "HARRY'S BUSH AIR"
const SUBTITLE := "DEEP IN THE BUSH SERVICES"
const SLOGAN := "We go deep in the bush"

# the hangar
const HW := 16.0          # wide (x)
const HD := 13.0          # deep (z), door in the front (-z) gable
const EAVE := 4.4
const PITCH := 4.0 / 12.0
const DOOR_W := 13.6
const DOOR_H := 4.1
const HZ0 := -HD * 0.5    # front wall
const HZ1 := HD * 0.5     # back wall
# the living quarters, back left corner
const RX0 := -HW * 0.5 + 0.08
const RX1 := RX0 + 4.3
const RZ1 := HZ1 - 0.08
const RZ0 := RZ1 - 3.9
const RH := 2.35          # its ceiling (the loft floor on top)
# the strip
const RWY_W := 14.0

var in_town := false            # placed in the Hope valley (small_town.gd): its ground and highway are there already
var rwy_x := 0.0                 # the runway's middle along x (in the valley it runs off west from the hangar)
var rwy_z := -60.0               # its centreline (local z)
var rwy_l := 500.0
var ground: Callable = func(_x: float, _z: float) -> float: return 0.0     # local ground height (the valley's, graded)
var road_pts: Array = []         # local points of the road in (from the highway), set by the valley
var k_corr := MeshKit.new()     # corrugated galvanised steel
var k_ply := MeshKit.new()      # plywood
var k_dirt := MeshKit.new()     # dirt and gravel
var k_cloth := MeshKit.new()    # blankets, coats, sacks
var k_lamp := MeshKit.new()     # glowing: bulbs, tubes, the TV screen


func _ready() -> void:
	_rng.seed = 1982
	_ground_strip()
	_hangar()
	_quarters()
	_hangar_inside()
	_fire_cache()
	_outside()
	_road_end()
	_park_plane()
	_finish()
	_finish_extra()
	set_meta("frame_aabb", AABB(Vector3(-30, 0, -90), Vector3(80, 12, 140)))


# ------------------------------------------------------------------------------
#  Materials
# ------------------------------------------------------------------------------
func _tex(kind: String) -> ImageTexture:
	if kind != "corr" and kind != "ply" and kind != "dirt":
		return super._tex(kind)
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	for y in range(s):
		for x in range(s):
			var v := 1.0
			match kind:
				"corr":      # corrugations: a soft sine across, 16 px a rib
					v = 0.78 + 0.22 * (0.5 + 0.5 * sin(float(x) / 16.0 * TAU)) + 0.03 * randf()
				"ply":       # plywood: long grain streaks and a knot now and then
					v = 0.9 + 0.035 * sin(float(y) * 1.3 + 2.0 * sin(float(x) * 0.03 + float(y) * 0.02)) + 0.04 * randf() - 0.12 * float((x + y * 3) % 97 == 0)
				"dirt":
					v = 0.78 + 0.3 * randf() * randf() + 0.06 * sin(float(x) * 0.2) * sin(float(y) * 0.23)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _finish_extra() -> void:
	var cm := _mat("corr", 1.0 / 0.6, 0.55, 0.45)
	cm.uv1_triplanar = true
	_add(k_corr, "Corrugated", cm)
	_add(k_ply, "Plywood", _mat("ply", 1.0 / 0.5, 0.85))
	_add(k_dirt, "Dirt", _mat("dirt", 0.4, 1.0), false)
	_add(k_cloth, "Cloth", _mat("", 1.0, 1.0))
	var lm := _mat("", 1.0, 0.4)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.92, 0.75)
	lm.emission_energy_multiplier = 1.2
	_add(k_lamp, "Lamps", lm, false)


# ------------------------------------------------------------------------------
#  Small helpers (all in a local frame xf: a prop's own origin and facing)
# ------------------------------------------------------------------------------
static func _b(k: MeshKit, xf: Transform3D, p: Vector3, s: Vector3, c: Color, yaw: float = 0.0) -> void:
	k.box(Transform3D(xf.basis * Basis(Vector3.UP, yaw), xf * p), s, c)


## A cylinder standing up from p (or along the local axis given), radius r.
static func _cy(k: MeshKit, xf: Transform3D, p: Vector3, r: float, h: float, c: Color, axis: Vector3 = Vector3.UP, sides: int = 12) -> void:
	var a := axis.normalized()
	var bas := Basis.IDENTITY
	if a.distance_to(Vector3.UP) > 0.001:
		if a.distance_to(Vector3.DOWN) < 0.001:
			bas = Basis(Vector3.RIGHT, PI)
		else:
			var ax := Vector3.UP.cross(a).normalized()
			bas = Basis(ax, Vector3.UP.angle_to(a))
	k.cylinder(Transform3D(xf.basis * bas, xf * p), r, r, h, sides, c, true)


static func _rod(k: MeshKit, xf: Transform3D, a: Vector3, b: Vector3, r: float, c: Color, sides: int = 6) -> void:
	var d := b - a
	if d.length() < 0.0005:
		return
	_cy(k, xf, a, r, d.length(), c, d, sides)


static func X(x: float, z: float, yaw: float = 0.0, y: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))


func _label(text: String, at: Vector3, yaw: float, px: float, col: Color, font := 48, outline := 0, pitch_x := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.pixel_size = px
	l.modulate = col
	l.outline_size = outline
	l.double_sided = false
	l.position = at
	l.rotation = Vector3(pitch_x, yaw, 0)
	l.shaded = true
	add_child(l)
	return l


# ------------------------------------------------------------------------------
#  Ground: grass, the dirt runway and taxiway, the gravel apron, the road
# ------------------------------------------------------------------------------
func _ground_strip() -> void:
	# grass all round (big tiles, slightly varied) - in the valley the
	# valley's own ground is under it
	var s := 0.0 if in_town else 420.0
	var n := 14
	for i in range(n):
		for j in range(n):
			var x0 := -s + 2.0 * s * float(i) / n
			var x1 := -s + 2.0 * s * float(i + 1) / n
			var z0 := -s + 2.0 * s * float(j) / n
			var z1 := -s + 2.0 * s * float(j + 1) / n
			var g := Color(0.40, 0.45, 0.24).lerp(Color(0.50, 0.48, 0.30), _rng.randf())
			k_grass.quad(Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1), g, Vector3.UP)
	var dirt := Color(0.55, 0.46, 0.34)
	var dirt_d := Color(0.46, 0.38, 0.28)
	# the runway: packed dirt, two darker wheel tracks worn down the middle, a
	# grass verge
	var hl := rwy_l * 0.5
	_drape(k_dirt, rwy_x - hl, rwy_z - RWY_W * 0.5, rwy_x + hl, rwy_z + RWY_W * 0.5, 0.02, dirt)
	for tz in [-1.6, 1.6]:
		_drape(k_dirt, rwy_x - hl + 15.0, rwy_z + tz - 0.45, rwy_x + hl - 15.0, rwy_z + tz + 0.45, 0.025, dirt_d)
	# white painted tyres half buried along both edges every 50 m, and the
	# threshold boards across each end
	for i in range(13):
		var mx := rwy_x - hl + 50.0 * float(i)
		if mx > rwy_x + hl + 0.1:
			break
		for side in [-1.0, 1.0]:
			var mz: float = rwy_z + side * (RWY_W * 0.5 + 1.0)
			_tyre_marker(Vector3(mx, float(ground.call(mx, mz)), mz))
	for e in [-1.0, 1.0]:
		for t in range(5):
			var tx: float = rwy_x + e * (hl - 2.0)
			var tz2: float = rwy_z - 6.0 + 3.0 * float(t)
			_b(k_paint, X(tx, tz2, 0.0, float(ground.call(tx, tz2))), Vector3(0, 0.12, 0), Vector3(0.3, 0.2, 2.0), Color(0.95, 0.95, 0.92))
	# the taxiway up to the hangar, the gravel apron in front of the door
	_drape(k_dirt, -6.0, rwy_z + RWY_W * 0.5 - 0.5, 6.0, HZ0 - 10.0, 0.022, dirt)
	_drape(k_dirt, -12.0, HZ0 - 12.0, 12.0, HZ0, 0.024, Color(0.60, 0.57, 0.52))
	# the dirt road: from the highway (north-east), round the east side of the
	# hangar to the apron; two wheel ruts with grass between
	var road := [Vector2(150.0, 95.0), Vector2(90.0, 70.0), Vector2(45.0, 40.0), Vector2(20.0, 14.0), Vector2(13.0, -4.0), Vector2(8.0, HZ0 - 8.0)]
	if not road_pts.is_empty():      # in the valley: the switchbacks up from the highway
		road = road_pts
	for i2 in range(road.size() - 1):
		var a: Vector2 = road[i2]
		var b: Vector2 = road[i2 + 1]
		var d := (b - a).normalized()
		var sd := Vector2(-d.y, d.x)
		var nseg := maxi(int(a.distance_to(b) / 4.0), 1)
		for q in range(nseg):
			var qa := a.lerp(b, float(q) / nseg)
			var qb := a.lerp(b, float(q + 1) / nseg)
			_strip3(k_dirt, qa, qb, 4.2, 0.03, dirt)
			_strip3(k_grass, qa, qb, 0.7, 0.045, Color(0.45, 0.47, 0.26))       # the crown of grass between the ruts
			for rs in [-0.9, 0.9]:
				_strip3(k_dirt, qa + sd * rs, qb + sd * rs, 0.45, 0.038, dirt_d)
	# the highway the road comes off (asphalt, centre line, gravel shoulders)
	if in_town:
		return
	_flat(k_asphalt, Vector3(80.0, 0.03, 101.0), Vector3(400.0, 0.03, 109.0), Color(0.24, 0.24, 0.25))
	_flat(k_dirt, Vector3(80.0, 0.025, 99.5), Vector3(400.0, 0.025, 110.5), Color(0.58, 0.55, 0.50))
	var cl := 82.0
	while cl < 398.0:
		_b(k_paint, Transform3D.IDENTITY, Vector3(cl + 1.5, 0.035, 105.0), Vector3(3.0, 0.005, 0.12), Color(0.92, 0.78, 0.15))
		cl += 9.0


## A rectangle of ground cover draped on the ground in 4 m squares.
func _drape(k: MeshKit, x0: float, z0: float, x1: float, z1: float, lift: float, c: Color) -> void:
	var nx := maxi(int(absf(x1 - x0) / 4.0), 1)
	var nz := maxi(int(absf(z1 - z0) / 4.0), 1)
	for i in range(nx):
		for j in range(nz):
			var xa := lerpf(x0, x1, float(i) / nx)
			var xb := lerpf(x0, x1, float(i + 1) / nx)
			var za := lerpf(z0, z1, float(j) / nz)
			var zb := lerpf(z0, z1, float(j + 1) / nz)
			var p := [Vector3(xa, 0, za), Vector3(xb, 0, za), Vector3(xb, 0, zb), Vector3(xa, 0, zb)]
			for q in range(4):
				p[q].y = float(ground.call(p[q].x, p[q].z)) + lift
			k.quad(p[0], p[1], p[2], p[3], c, Vector3.UP)


## A short ribbon from a to b (local x, z) w wide, on the ground.
func _strip3(k: MeshKit, a: Vector2, b: Vector2, w: float, lift: float, c: Color) -> void:
	var d := (b - a).normalized()
	var sd := Vector2(-d.y, d.x) * w * 0.5
	var ea := a - d * 0.15
	var eb := b + d * 0.15
	var pts := [ea + sd, eb + sd, eb - sd, ea - sd]
	var v: Array = []
	for q in pts:
		v.append(Vector3(q.x, float(ground.call(q.x, q.y)) + lift, q.y))
	k.quad(v[0], v[1], v[2], v[3], c, Vector3.UP)


func _flat(k: MeshKit, a: Vector3, b: Vector3, c: Color) -> void:
	k.quad(Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z), c, Vector3.UP)


func _strip(k: MeshKit, a: Vector2, b: Vector2, w: float, y: float, c: Color) -> void:
	var d := (b - a).normalized()
	var sd := Vector2(-d.y, d.x) * w * 0.5
	var ea := a - d * w * 0.3
	var eb := b + d * w * 0.3
	k.quad(Vector3(ea.x + sd.x, y, ea.y + sd.y), Vector3(eb.x + sd.x, y, eb.y + sd.y), Vector3(eb.x - sd.x, y, eb.y - sd.y), Vector3(ea.x - sd.x, y, ea.y - sd.y), c, Vector3.UP)


func _tyre_marker(p: Vector3) -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 0.2, -0.12))
	k_paint.cylinder(xf, 0.38, 0.38, 0.24, 14, Color(0.93, 0.93, 0.9), true)
	k_trim.cylinder(Transform3D(xf.basis, xf.origin - xf.basis.y * 0.002), 0.2, 0.2, 0.245, 10, Color(0.35, 0.3, 0.22), true)


# ------------------------------------------------------------------------------
#  The hangar: an old corrugated galvanised shed, rust bleeding from the laps,
#  red trim, a low gable, two sliding doors on a track run back open
# ------------------------------------------------------------------------------
func _hangar() -> void:
	var hx := HW * 0.5
	var rise := hx * PITCH
	var galv := Color(0.74, 0.75, 0.74)
	var red := Color(0.58, 0.14, 0.10)
	# concrete slab, a lip out front
	_b(k_concrete, Transform3D.IDENTITY, Vector3(0, -0.1, 0), Vector3(HW + 0.2, 0.3, HD + 0.2), Color(0.62, 0.61, 0.58))
	# walls: corrugated sheet (outside), each sheet 0.9 m, some rusty, a few
	# lighter (patched later)
	for side in [-1.0, 1.0]:
		_corr_wall(Vector3(side * hx, 0, HZ0), Vector3(side * hx, 0, HZ1), EAVE, Vector3(side, 0, 0), galv)
	_corr_wall(Vector3(-hx, 0, HZ1), Vector3(hx, 0, HZ1), EAVE, Vector3(0, 0, 1), galv)
	var sw := (HW - DOOR_W) * 0.5
	_corr_wall(Vector3(-hx, 0, HZ0), Vector3(-hx + sw, 0, HZ0), EAVE, Vector3(0, 0, -1), galv)
	_corr_wall(Vector3(hx - sw, 0, HZ0), Vector3(hx, 0, HZ0), EAVE, Vector3(0, 0, -1), galv)
	_corr_wall(Vector3(-DOOR_W * 0.5, DOOR_H + 0.15, HZ0), Vector3(DOOR_W * 0.5, DOOR_H + 0.15, HZ0), EAVE - DOOR_H - 0.15, Vector3(0, 0, -1), galv)
	# gables
	for gz in [HZ0, HZ1]:
		var o := -1.0 if gz < 0.0 else 1.0
		k_corr.tri(Vector3(-hx, EAVE, gz), Vector3(hx, EAVE, gz), Vector3(0, EAVE + rise, gz), galv.darkened(0.04), Vector3(0, 0, o))
		k_corr.tri(Vector3(-hx, EAVE, gz - o * 0.04), Vector3(0, EAVE + rise, gz - o * 0.04), Vector3(hx, EAVE, gz - o * 0.04), galv.darkened(0.2), Vector3(0, 0, -o))
	# the inside face of the walls (same sheet, darker inside)
	for side in [-1.0, 1.0]:
		k_corr.quad(Vector3(side * (hx - 0.03), 0, HZ0), Vector3(side * (hx - 0.03), 0, HZ1), Vector3(side * (hx - 0.03), EAVE, HZ1), Vector3(side * (hx - 0.03), EAVE, HZ0), galv.darkened(0.25), Vector3(-side, 0, 0))
	k_corr.quad(Vector3(-hx, 0, HZ1 - 0.03), Vector3(hx, 0, HZ1 - 0.03), Vector3(hx, EAVE, HZ1 - 0.03), Vector3(-hx, EAVE, HZ1 - 0.03), galv.darkened(0.25), Vector3(0, 0, -1))
	for s2 in [-1.0, 1.0]:
		var xa: float = s2 * hx
		var xb: float = s2 * DOOR_W * 0.5
		k_corr.quad(Vector3(xa, 0, HZ0 + 0.03), Vector3(xb, 0, HZ0 + 0.03), Vector3(xb, EAVE, HZ0 + 0.03), Vector3(xa, EAVE, HZ0 + 0.03), galv.darkened(0.25), Vector3(0, 0, 1))
	k_corr.quad(Vector3(-DOOR_W * 0.5, DOOR_H + 0.15, HZ0 + 0.03), Vector3(DOOR_W * 0.5, DOOR_H + 0.15, HZ0 + 0.03), Vector3(DOOR_W * 0.5, EAVE, HZ0 + 0.03), Vector3(-DOOR_W * 0.5, EAVE, HZ0 + 0.03), galv.darkened(0.25), Vector3(0, 0, 1))
	# roof: corrugated, a bit of overhang, ridge cap; rust streaks by the ridge
	var over := 0.35
	for sx in [-1.0, 1.0]:
		var a := Vector3(0, EAVE + rise, HZ0 - over)
		var b := Vector3(0, EAVE + rise, HZ1 + over)
		var c := Vector3(sx * (hx + over), EAVE - over * PITCH, HZ1 + over)
		var d := Vector3(sx * (hx + over), EAVE - over * PITCH, HZ0 - over)
		var up := Vector3(sx * PITCH, 1, 0).normalized()
		k_corr.quad(a, b, c, d, galv.darkened(0.06), up)
		k_corr.quad(a - Vector3(0, 0.05, 0), d - Vector3(0, 0.05, 0), c - Vector3(0, 0.05, 0), b - Vector3(0, 0.05, 0), galv.darkened(0.3), -up)
		# rust patches on the roof
		for rp in range(5):
			var u := _rng.randf_range(0.1, 0.8)
			var zz := _rng.randf_range(HZ0, HZ1 - 2.0)
			var p0 := a.lerp(d, u) + Vector3(0, 0.012, zz - HZ0 + over)
			k_paint.box(Transform3D(Basis(Vector3.FORWARD, sx * atan(PITCH)), p0), Vector3(_rng.randf_range(0.6, 1.6), 0.005, _rng.randf_range(0.5, 1.5)), Color(0.50, 0.30, 0.18).lerp(Color(0.62, 0.40, 0.25), _rng.randf()))
	_b(k_trim, Transform3D.IDENTITY, Vector3(0, EAVE + rise + 0.04, 0), Vector3(0.45, 0.08, HD + over * 2.0), red)
	# red trim: corners, eaves, the door frame, rake boards
	for sx2 in [-1.0, 1.0]:
		for sz in [HZ0, HZ1]:
			_b(k_trim, Transform3D.IDENTITY, Vector3(sx2 * (hx + 0.03), EAVE * 0.5, sz + (0.03 if sz > 0 else -0.03)), Vector3(0.16, EAVE, 0.16), red)
	for sx3 in [-1.0, 1.0]:
		_b(k_trim, Transform3D.IDENTITY, Vector3(sx3 * DOOR_W * 0.5, DOOR_H * 0.5, HZ0 - 0.05), Vector3(0.18, DOOR_H + 0.2, 0.1), red)
		for sz2 in [HZ0 - 0.06, HZ1 + 0.06]:
			var rake := Vector3(sx3 * (hx + over), EAVE - over * PITCH, sz2)
			var top := Vector3(0, EAVE + rise + 0.05, sz2)
			_beam(k_trim, rake, top, Vector2(0.18, 0.05), red)
	_b(k_trim, Transform3D.IDENTITY, Vector3(0, DOOR_H + 0.12, HZ0 - 0.06), Vector3(DOOR_W + 0.2, 0.14, 0.1), red)
	# the door track: an I-beam along the top of the opening, run out past
	# both sides on brackets so the doors slide clear
	var tr := Color(0.25, 0.25, 0.26)
	_b(k_metal, Transform3D.IDENTITY, Vector3(0, DOOR_H + 0.35, HZ0 - 0.22), Vector3(HW + DOOR_W * 0.5 * 2.0 - 2.0, 0.12, 0.1), tr)
	for bx in [-HW * 0.5 - 5.0, -HW * 0.5 - 1.0, HW * 0.5 + 1.0, HW * 0.5 + 5.0]:
		_b(k_metal, Transform3D.IDENTITY, Vector3(bx, DOOR_H + 0.35, HZ0 - 0.12), Vector3(0.08, 0.1, 0.25), tr)
		if absf(bx) > HW * 0.5 + 2.0:
			# a post holding the track out where the wall stops
			_b(k_trim, Transform3D.IDENTITY, Vector3(bx, (DOOR_H + 0.35) * 0.5, HZ0 - 0.22), Vector3(0.15, DOOR_H + 0.35, 0.15), red.darkened(0.2))
	# the doors: two corrugated leaves on hangers, run out each side
	for side3 in [-1.0, 1.0]:
		var dc: float = side3 * (HW * 0.5 + DOOR_W * 0.25 - 0.6)
		var leaf_w := DOOR_W * 0.5 + 0.1
		_corr_panel(Vector3(dc, 0.05, HZ0 - 0.3), leaf_w, DOOR_H + 0.15, galv.lightened(0.04))
		# frame round the leaf, the hangers on top, a handle, the bottom guide
		_b(k_trim, Transform3D.IDENTITY, Vector3(dc, DOOR_H + 0.2, HZ0 - 0.32), Vector3(leaf_w, 0.1, 0.06), red)
		_b(k_trim, Transform3D.IDENTITY, Vector3(dc, 0.08, HZ0 - 0.32), Vector3(leaf_w, 0.1, 0.06), red)
		for e2 in [-1.0, 1.0]:
			_b(k_trim, Transform3D.IDENTITY, Vector3(dc + e2 * leaf_w * 0.5, DOOR_H * 0.5 + 0.1, HZ0 - 0.32), Vector3(0.1, DOOR_H + 0.2, 0.06), red)
			_b(k_metal, Transform3D.IDENTITY, Vector3(dc + e2 * leaf_w * 0.35, DOOR_H + 0.32, HZ0 - 0.25), Vector3(0.05, 0.22, 0.05), tr)
			_cy(k_metal, Transform3D.IDENTITY, Vector3(dc + e2 * leaf_w * 0.35, DOOR_H + 0.41, HZ0 - 0.27), 0.06, 0.04, tr, Vector3(0, 0, 1))
		_b(k_metal, Transform3D.IDENTITY, Vector3(dc - side3 * (leaf_w * 0.5 - 0.3), 1.1, HZ0 - 0.37), Vector3(0.04, 0.4, 0.04), tr)
	# the walk-in door on the east wall, front end (to the road), a concrete step
	var dz := HZ0 + 1.6
	_b(k_trim, Transform3D.IDENTITY, Vector3(hx + 0.05, 1.05, dz), Vector3(0.06, 2.15, 1.0), red)
	_b(k_wood, Transform3D.IDENTITY, Vector3(hx + 0.08, 1.02, dz), Vector3(0.05, 2.02, 0.86), Color(0.50, 0.14, 0.10))
	_cy(k_metal, Transform3D.IDENTITY, Vector3(hx + 0.11, 1.0, dz - 0.32), 0.03, 0.05, Color(0.8, 0.7, 0.3), Vector3(1, 0, 0))
	_b(k_concrete, Transform3D.IDENTITY, Vector3(hx + 0.45, 0.08, dz), Vector3(0.7, 0.16, 1.1), Color(0.6, 0.6, 0.57))
	# windows: the quarters' (west wall and back wall), two down the east side
	_window(Vector3(-hx, 1.45, (RZ0 + RZ1) * 0.5), Vector3(-1, 0, 0), 0.9, 0.75)
	_window(Vector3(RX0 + 2.6, 1.45, HZ1), Vector3(0, 0, 1), 0.9, 0.75)
	for wz in [-0.5, 3.5]:
		_window(Vector3(hx, 2.2, wz), Vector3(1, 0, 0), 1.2, 0.8)
	# the sign across the front gable
	var gy := EAVE + rise * 0.35
	_b(k_wood, Transform3D.IDENTITY, Vector3(0, gy, HZ0 - 0.09), Vector3(7.4, 1.1, 0.06), Color(0.93, 0.91, 0.84))
	_b(k_trim, Transform3D.IDENTITY, Vector3(0, gy, HZ0 - 0.07), Vector3(7.6, 1.24, 0.04), red)
	_label(COMPANY, Vector3(0, gy + 0.15, HZ0 - 0.125), PI, 0.0105, Color(0.62, 0.1, 0.08), 72)
	_label(SUBTITLE, Vector3(0, gy - 0.3, HZ0 - 0.125), PI, 0.0055, Color(0.15, 0.15, 0.15), 64)
	# NO SMOKING by the door, a light over the door
	_b(k_paint, Transform3D.IDENTITY, Vector3(-DOOR_W * 0.5 - 0.6, 2.0, HZ0 - 0.06), Vector3(0.7, 0.35, 0.02), Color(0.95, 0.95, 0.92))
	_label("NO SMOKING", Vector3(-DOOR_W * 0.5 - 0.6, 2.0, HZ0 - 0.075), PI, 0.0028, Color(0.75, 0.08, 0.06), 64)
	for lx in [-DOOR_W * 0.5 - 0.6, DOOR_W * 0.5 + 0.6]:
		_flood(Vector3(lx, EAVE - 0.3, HZ0 - 0.1), Vector3(0, -0.4, -1))


## A wall of corrugated sheets from a to b (feet of the wall), h tall, facing out.
func _corr_wall(a: Vector3, b: Vector3, h: float, out: Vector3, base: Color) -> void:
	var L := a.distance_to(b)
	var n := maxi(int(ceil(L / 0.9)), 1)
	for i in range(n):
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		var p0 := a.lerp(b, u0) + out * 0.003 * float(i % 2)
		var p1 := a.lerp(b, u1) + out * 0.003 * float(i % 2)
		var r := _rng.randf()
		var c := base
		if r < 0.18:
			c = base.lerp(Color(0.55, 0.38, 0.26), _rng.randf_range(0.3, 0.6))     # rusty sheet
		elif r < 0.26:
			c = base.lightened(0.1)                                                  # a newer patch
		k_corr.quad(p0, p1, p1 + Vector3(0, h, 0), p0 + Vector3(0, h, 0), c.darkened(_rng.randf_range(0.0, 0.06)), out)
		# rust streak from the top lap now and then
		if _rng.randf() < 0.3:
			var sx := _rng.randf_range(0.2, 0.8)
			var ps := p0.lerp(p1, sx) + out * 0.006
			var sh := _rng.randf_range(0.6, 1.8)
			var dd := (p1 - p0).normalized()
			k_paint.quad(ps - dd * 0.06 + Vector3(0, h - sh, 0), ps + dd * 0.06 + Vector3(0, h - sh, 0), ps + dd * 0.1 + Vector3(0, h - 0.02, 0), ps - dd * 0.1 + Vector3(0, h - 0.02, 0), Color(0.55, 0.34, 0.2), out)
	# the bottom of the sheets rusted where the snow sat
	k_paint.quad(a + out * 0.008, b + out * 0.008, b + out * 0.008 + Vector3(0, 0.25, 0), a + out * 0.008 + Vector3(0, 0.25, 0), Color(0.48, 0.34, 0.24), out)


func _corr_panel(c: Vector3, w: float, h: float, col: Color) -> void:
	var n := maxi(int(ceil(w / 0.9)), 1)
	for i in range(n):
		var x0 := c.x - w * 0.5 + w * float(i) / n
		var x1 := c.x - w * 0.5 + w * float(i + 1) / n
		var cc := col.darkened(_rng.randf_range(0.0, 0.08))
		k_corr.quad(Vector3(x0, c.y, c.z), Vector3(x1, c.y, c.z), Vector3(x1, c.y + h, c.z), Vector3(x0, c.y + h, c.z), cc, Vector3(0, 0, -1))
		k_corr.quad(Vector3(x0, c.y, c.z + 0.03), Vector3(x0, c.y + h, c.z + 0.03), Vector3(x1, c.y + h, c.z + 0.03), Vector3(x1, c.y, c.z + 0.03), cc.darkened(0.25), Vector3(0, 0, 1))


## A wood-framed window in a wall at c, facing `out`, w x h: frame, sill, two
## panes with a muntin, the glass.
func _window(c: Vector3, out: Vector3, w: float, h: float) -> void:
	var o := out.normalized()
	var along := Vector3.UP.cross(o).normalized()
	var bas := Basis(along, Vector3.UP, o)
	var white := Color(0.92, 0.91, 0.86)
	var xf := Transform3D(bas, c)
	_b(k_glass, xf, Vector3(0, 0, 0.0), Vector3(w, h, 0.02), Color(0.30, 0.38, 0.42))
	for sd in [-1.0, 1.0]:
		_b(k_trim, xf, Vector3(sd * (w * 0.5 + 0.04), 0, 0.04), Vector3(0.08, h + 0.16, 0.05), white)
		_b(k_trim, xf, Vector3(0, sd * (h * 0.5 + 0.04), 0.04), Vector3(w + 0.16, 0.08, 0.05), white)
		_b(k_trim, xf, Vector3(sd * (w * 0.5 + 0.04), 0, -0.07), Vector3(0.06, h + 0.12, 0.05), white)
		_b(k_trim, xf, Vector3(0, sd * (h * 0.5 + 0.03), -0.07), Vector3(w + 0.12, 0.06, 0.05), white)
	_b(k_trim, xf, Vector3(0, 0, 0.03), Vector3(0.04, h, 0.03), white)
	_b(k_trim, xf, Vector3(0, -h * 0.5 - 0.1, 0.08), Vector3(w + 0.25, 0.04, 0.12), white)


## A gooseneck flood lamp on the wall at p, aimed `aim`.
func _flood(p: Vector3, aim: Vector3) -> void:
	var tr := Color(0.18, 0.2, 0.18)
	_rod(k_metal, Transform3D.IDENTITY, p + Vector3(0, -0.3, 0.06), p + Vector3(0, 0.05, -0.12), 0.015, tr)
	_cy(k_metal, Transform3D.IDENTITY, p + Vector3(0, 0.05, -0.12), 0.16, 0.12, tr, aim, 12)
	_cy(k_lamp, Transform3D.IDENTITY, p + Vector3(0, 0.05, -0.12) + aim.normalized() * 0.121, 0.13, 0.004, Color(1, 0.95, 0.8), aim, 12)


func _beam(k: MeshKit, a: Vector3, b: Vector3, sec: Vector2, col: Color) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.001:
		return
	var z := d / L
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x).normalized()
	k.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(sec.x, sec.y, L), col)


# ------------------------------------------------------------------------------
#  The living quarters: a plywood room in the back left corner, framed in 2x4,
#  a plywood ceiling with the loft over it. Harry lives here.
# ------------------------------------------------------------------------------
func _quarters() -> void:
	var stud := Color(0.72, 0.60, 0.42)
	var ply := Color(0.80, 0.68, 0.50)
	var ply_in := Color(0.74, 0.62, 0.46)
	var T := 0.1            # wall: 2x4 studs, plywood both faces
	var door_x := RX1 - 0.75          # the door in the front wall, near the hangar side
	var door_w := 0.82
	var door_h := 2.03
	# front wall (z = RZ0), with the door; east wall (x = RX1) with a window
	# into the hangar. Plywood both faces, the 2x4 edges showing at openings.
	var walls := [[Vector3(RX0, 0, RZ0), Vector3(RX1, 0, RZ0), Vector3(0, 0, -1)], [Vector3(RX1, 0, RZ0), Vector3(RX1, 0, RZ1), Vector3(1, 0, 0)]]
	for w in walls:
		var a: Vector3 = w[0]
		var b: Vector3 = w[1]
		var out: Vector3 = w[2]
		var L := a.distance_to(b)
		var dir := (b - a) / L
		var holes: Array = []          # [u0, u1, y0, y1] along the wall
		if out.z < 0.0:
			holes.append([door_x - door_w * 0.5 - RX0, door_x + door_w * 0.5 - RX0, 0.0, door_h])
		else:
			holes.append([1.4, 2.6, 0.95, 1.85])                  # the window onto the plane
		_holed_wall(a, dir, out, L, RH, holes, ply, ply_in, T)
	# the ceiling (plywood underneath, the loft floor on top), and the loft's
	# rail and its ladder up the east wall outside the room
	var cx := (RX0 + RX1) * 0.5
	var cz := (RZ0 + RZ1) * 0.5
	k_ply.quad(Vector3(RX0, RH, RZ0), Vector3(RX0, RH, RZ1), Vector3(RX1, RH, RZ1), Vector3(RX1, RH, RZ0), ply_in.darkened(0.08), Vector3.DOWN)
	_b(k_ply, Transform3D.IDENTITY, Vector3(cx, RH + 0.12, cz), Vector3(RX1 - RX0 + 0.1, 0.02, RZ1 - RZ0 + 0.1), ply)
	for j in range(9):
		var jz := RZ0 + 0.05 + (RZ1 - RZ0 - 0.1) * float(j) / 8.0
		_b(k_wood, Transform3D.IDENTITY, Vector3(cx, RH + 0.055, jz), Vector3(RX1 - RX0, 0.2, 0.045), stud)      # 2x8 joists between
	_b(k_wood, Transform3D.IDENTITY, Vector3(cx, RH + 0.055, RZ0 - 0.02), Vector3(RX1 - RX0 + 0.1, 0.2, 0.05), stud)
	var rail := Color(0.62, 0.50, 0.34)
	for e in range(6):
		var ex := lerpf(RX0 + 0.1, RX1 - 0.05, float(e) / 5.0)
		_b(k_wood, Transform3D.IDENTITY, Vector3(ex, RH + 0.13 + 0.45, RZ0 + 0.02), Vector3(0.07, 0.9, 0.07), rail)
	_b(k_wood, Transform3D.IDENTITY, Vector3(cx, RH + 1.04, RZ0 + 0.02), Vector3(RX1 - RX0, 0.07, 0.09), rail)
	for e2 in range(5):
		var ez := lerpf(RZ0 + 0.02, RZ1 - 0.6, float(e2) / 4.0)
		_b(k_wood, Transform3D.IDENTITY, Vector3(RX1 - 0.02, RH + 0.13 + 0.45, ez), Vector3(0.07, 0.9, 0.07), rail)
	_b(k_wood, Transform3D.IDENTITY, Vector3(RX1 - 0.02, RH + 1.04, (RZ0 + RZ1 - 0.6) * 0.5), Vector3(0.09, 0.07, RZ1 - RZ0 - 0.6), rail)
	# a wooden ladder up to the loft at the back end of the east wall
	var lx := RX1 + 0.35
	var lz := RZ1 - 0.35
	for sd in [-0.22, 0.22]:
		_beam(k_wood, Vector3(lx + 0.3, 0, lz + sd), Vector3(lx - 0.05, RH + 1.0, lz + sd), Vector2(0.05, 0.09), stud.darkened(0.1))
	for r in range(9):
		var t := (float(r) + 0.6) / 9.6
		var rp := Vector3(lx + 0.3, 0, lz).lerp(Vector3(lx - 0.05, RH + 1.0, lz), t)
		_cy(k_wood, Transform3D.IDENTITY, rp - Vector3(0, 0, 0.22), 0.016, 0.44, stud, Vector3(0, 0, 1), 6)
	# the loft: stuff stored up there
	_loft_stuff(Vector3(cx, RH + 0.13, cz))
	# the door: a hollow-core slab hung on the left, open into the room, a
	# knob, a calendar-ish notice on it
	var dhx := door_x - door_w * 0.5
	var dxf := Transform3D(Basis(Vector3.UP, -1.25), Vector3(dhx, 0, RZ0 + 0.05))
	_b(k_wood, dxf, Vector3(door_w * 0.5 - 0.02, door_h * 0.5, 0), Vector3(door_w - 0.04, door_h - 0.02, 0.035), Color(0.62, 0.50, 0.36))
	_cy(k_metal, dxf, Vector3(door_w - 0.1, 0.95, 0.02), 0.028, 0.06, Color(0.75, 0.62, 0.30), Vector3(0, 0, 1))
	_cy(k_metal, dxf, Vector3(door_w - 0.1, 0.95, -0.02), 0.028, 0.06, Color(0.75, 0.62, 0.30), Vector3(0, 0, -1))
	_b(k_paint, dxf, Vector3(door_w * 0.5, 1.5, -0.022), Vector3(0.21, 0.28, 0.003), Color(0.95, 0.93, 0.85))
	# trim round the door and the window (both faces)
	var trim := Color(0.55, 0.42, 0.28)
	for f in [-1.0, 1.0]:
		for s in [-1.0, 1.0]:
			_b(k_wood, Transform3D.IDENTITY, Vector3(door_x + s * (door_w * 0.5 + 0.035), door_h * 0.5, RZ0 + f * 0.065), Vector3(0.07, door_h + 0.07, 0.015), trim)
		_b(k_wood, Transform3D.IDENTITY, Vector3(door_x, door_h + 0.035, RZ0 + f * 0.065), Vector3(door_w + 0.14, 0.07, 0.015), trim)
	# the window into the hangar: sliding aluminium sash
	var wcz := RZ0 + 2.0
	_b(k_glass, Transform3D.IDENTITY, Vector3(RX1, 1.4, wcz - 0.3), Vector3(0.01, 0.86, 0.6), Color(0.35, 0.42, 0.46))
	_b(k_glass, Transform3D.IDENTITY, Vector3(RX1 + 0.02, 1.4, wcz + 0.3), Vector3(0.01, 0.86, 0.6), Color(0.35, 0.42, 0.46))
	for s2 in [-1.0, 1.0]:
		_b(k_metal, Transform3D.IDENTITY, Vector3(RX1 + 0.01, 1.4 + s2 * 0.44, wcz), Vector3(0.06, 0.03, 1.22), Color(0.72, 0.72, 0.70))
		_b(k_metal, Transform3D.IDENTITY, Vector3(RX1 + 0.01, 1.4, wcz + s2 * 0.6), Vector3(0.06, 0.9, 0.03), Color(0.72, 0.72, 0.70))
	_b(k_metal, Transform3D.IDENTITY, Vector3(RX1 + 0.01, 1.4, wcz), Vector3(0.05, 0.9, 0.03), Color(0.72, 0.72, 0.70))
	# floor: sheet linoleum over the slab (brown and gold squares), a braided
	# rag rug by the cot
	_flat(k_paint, Vector3(RX0, 0.006, RZ0), Vector3(RX1, 0.006, RZ1), Color(0.52, 0.40, 0.22))
	for i in range(int((RX1 - RX0) / 0.3)):
		for j2 in range(int((RZ1 - RZ0) / 0.3)):
			if (i + j2) % 2 == 0:
				var px := RX0 + 0.15 + 0.3 * float(i)
				var pz := RZ0 + 0.15 + 0.3 * float(j2)
				_flat(k_paint, Vector3(px - 0.14, 0.008, pz - 0.14), Vector3(px + 0.14, 0.008, pz + 0.14), Color(0.66, 0.52, 0.26))
	for ring in range(6):
		var rr := 0.62 - 0.1 * float(ring)
		var rug_c: Color = [Color(0.55, 0.20, 0.15), Color(0.30, 0.35, 0.25), Color(0.62, 0.50, 0.30)][ring % 3]
		k_cloth.cylinder(Transform3D(Basis.IDENTITY, Vector3(RX0 + 1.5, 0.009 + 0.002 * float(ring), RZ1 - 1.4)), rr * 1.3, rr * 1.3, 0.004, 20, rug_c, true)
	_furnish()


## A wall of 2x4 studs and plywood both faces, from a along dir, facing `out`,
## with rectangular openings [u0, u1, y0, y1] cut through it.
func _holed_wall(a: Vector3, dir: Vector3, out: Vector3, L: float, h: float, holes: Array, c_out: Color, c_in: Color, T: float) -> void:
	# split the wall into rectangles round the holes: columns between hole
	# edges, each column full height except where a hole is
	var cuts := [0.0, L]
	for hh in holes:
		cuts.append(float(hh[0]))
		cuts.append(float(hh[1]))
	cuts.sort()
	for i in range(cuts.size() - 1):
		var u0: float = cuts[i]
		var u1: float = cuts[i + 1]
		if u1 - u0 < 0.001:
			continue
		var um := (u0 + u1) * 0.5
		var spans := [[0.0, h]]
		for hh2 in holes:
			if um > float(hh2[0]) and um < float(hh2[1]):
				spans = [[0.0, float(hh2[2])], [float(hh2[3]), h]]
		for sp in spans:
			var y0: float = sp[0]
			var y1: float = sp[1]
			if y1 - y0 < 0.001:
				continue
			for f in [1.0, -1.0]:
				var o: Vector3 = out * (T * 0.5 * f)
				var p0 := a + dir * u0 + o + Vector3(0, y0, 0)
				var p1 := a + dir * u1 + o + Vector3(0, y0, 0)
				var q1 := p1 + Vector3(0, y1 - y0, 0)
				var q0 := p0 + Vector3(0, y1 - y0, 0)
				k_ply.quad(p0, p1, q1, q0, c_out if f > 0.0 else c_in, out * f)
	# the stud ends showing in the openings, the top plate
	for hh3 in holes:
		for u in [float(hh3[0]), float(hh3[1])]:
			var p: Vector3 = a + dir * u
			k_wood.box(Transform3D(Basis.looking_at(out, Vector3.UP), p + Vector3(0, h * 0.5, 0)), Vector3(0.04, h, T), Color(0.72, 0.60, 0.42))
		for yy in [float(hh3[2]), float(hh3[3])]:
			if yy <= 0.001:
				continue
			var pm := a + dir * ((float(hh3[0]) + float(hh3[1])) * 0.5)
			k_wood.box(Transform3D(Basis.looking_at(out, Vector3.UP), pm + Vector3(0, yy, 0)), Vector3(float(hh3[1]) - float(hh3[0]), 0.04, T), Color(0.72, 0.60, 0.42))
	k_wood.box(Transform3D(Basis.looking_at(out, Vector3.UP), a + dir * L * 0.5 + Vector3(0, h + 0.02, 0)), Vector3(L, 0.04, T), Color(0.72, 0.60, 0.42))


## His plane, pushed in tail first, nose to the door (for scale and because
## that's where it lives).
func _park_plane() -> void:
	var PB = load("res://scripts/plane_body.gd")
	if PB == null:
		return
	var pl: Node3D = PB.new()
	pl.name = "HarrysPlane"
	add_child(pl)
	pl.build()
	pl.position = Vector3(0.3, 0, HZ0 + 3.2 + 2.0)


# ------------------------------------------------------------------------------
#  Inside the hangar: trusses, lights, the shop, cargo
# ------------------------------------------------------------------------------
func _hangar_inside() -> void:
	var hx := HW * 0.5
	var rise := hx * PITCH
	var lumber := Color(0.62, 0.50, 0.34)
	# wood trusses every 2.4 m: bottom chord, top chords, king post, webs,
	# gusset plates; purlins across them under the sheet
	var nt := int(HD / 2.4)
	for i in range(nt + 1):
		var z := lerpf(HZ0 + 0.2, HZ1 - 0.2, float(i) / float(nt))
		var l := Vector3(-hx + 0.05, EAVE - 0.05, z)
		var r := Vector3(hx - 0.05, EAVE - 0.05, z)
		var top := Vector3(0, EAVE + rise - 0.2, z)
		_beam(k_wood, l, r, Vector2(0.05, 0.19), lumber)
		_beam(k_wood, l, top, Vector2(0.05, 0.19), lumber)
		_beam(k_wood, r, top, Vector2(0.05, 0.19), lumber)
		_beam(k_wood, Vector3(0, EAVE - 0.05, z), top, Vector2(0.05, 0.14), lumber.darkened(0.05))
		for sx in [-1.0, 1.0]:
			var q := Vector3(sx * hx * 0.5, EAVE - 0.05, z)
			_beam(k_wood, q, Vector3(sx * hx * 0.5, EAVE + rise * 0.5 - 0.2, z), Vector2(0.05, 0.09), lumber.darkened(0.05))
			_beam(k_wood, q, Vector3(0, EAVE + rise - 0.2, z), Vector2(0.05, 0.09), lumber.darkened(0.08))
			_beam(k_wood, q, Vector3(sx * hx * 0.25, EAVE + rise * 0.75 - 0.2, z), Vector2(0.05, 0.09), lumber.darkened(0.08))
		for gx in [-hx + 0.3, 0.0, hx - 0.3]:
			_b(k_metal, Transform3D.IDENTITY, Vector3(gx, EAVE - 0.05, z), Vector3(0.3, 0.2, 0.06), Color(0.6, 0.6, 0.6))
	for pu in range(7):
		var u := float(pu) / 6.0
		for sx2 in [-1.0, 1.0]:
			_b(k_wood, Transform3D.IDENTITY, Vector3(sx2 * hx * u, EAVE + rise * (1.0 - u) - 0.03, 0), Vector3(0.09, 0.04, HD - 0.1), lumber.darkened(0.1))
	# wall girts on the inside, the sheets screwed to them
	for gy in [0.9, 2.2, 3.5]:
		for sx3 in [-1.0, 1.0]:
			_b(k_wood, Transform3D.IDENTITY, Vector3(sx3 * (hx - 0.08), gy, 0), Vector3(0.05, 0.14, HD - 0.2), lumber)
		_b(k_wood, Transform3D.IDENTITY, Vector3(0, gy, HZ1 - 0.08), Vector3(HW - 0.2, 0.14, 0.05), lumber)
	# fluorescent shop lights on chains: two rows; a bulb over the bench
	for lz in [HZ0 + 2.5, 0.0, HZ1 - 3.0]:
		for lx in [-3.2, 3.2]:
			var ly := EAVE - 0.7
			_b(k_metal, Transform3D.IDENTITY, Vector3(lx, ly, lz), Vector3(0.22, 0.08, 1.25), Color(0.85, 0.85, 0.82))
			for t in [-0.06, 0.06]:
				_cy(k_lamp, Transform3D.IDENTITY, Vector3(lx + t, ly - 0.04, lz - 0.6), 0.016, 1.2, Color(1, 1, 0.95), Vector3(0, 0, 1), 6)
			for e in [-0.5, 0.5]:
				_rod(k_metal, Transform3D.IDENTITY, Vector3(lx, ly + 0.04, lz + e), Vector3(lx, EAVE - 0.05, lz + e), 0.006, Color(0.3, 0.3, 0.3), 4)
	# the floor: tyre tracks, oil spots
	for st in [[Vector3(0.6, 0.002, HZ0 + 4.0), 0.8], [Vector3(-0.3, 0.002, 1.0), 0.5], [Vector3(4.6, 0.002, HZ1 - 1.6), 0.4], [Vector3(-2.0, 0.002, -1.0), 0.3]]:
		k_paint.cylinder(Transform3D(Basis.IDENTITY, st[0]), float(st[1]), float(st[1]) * 0.85, 0.003, 12, Color(0.40, 0.40, 0.38), true)
	_shop()
	_cargo()


## The back wall's shop: the workbench with a vise and a pegboard of tools, the
## tool chest, parts shelves, oil cases, the compressor, the engine hoist,
## avgas drums and their pump, a spare prop and skis on the wall.
func _shop() -> void:
	var hx := HW * 0.5
	var bz := HZ1 - 0.45
	var wood := Color(0.55, 0.42, 0.28)
	var steel := Color(0.35, 0.36, 0.37)
	var red := Color(0.70, 0.11, 0.09)
	# workbench: 2x6 top, 4x4 legs, a shelf under with coffee cans of bolts
	var bx := 0.5
	var bw := 3.6
	_b(k_wood, Transform3D.IDENTITY, Vector3(bx, 0.88, bz), Vector3(bw, 0.06, 0.75), wood)
	_b(k_wood, Transform3D.IDENTITY, Vector3(bx, 0.25, bz), Vector3(bw - 0.1, 0.03, 0.65), wood.darkened(0.1))
	for lx in [-bw * 0.5 + 0.1, bw * 0.5 - 0.1]:
		for lz in [-0.3, 0.3]:
			_b(k_wood, Transform3D.IDENTITY, Vector3(bx + lx, 0.43, bz + lz), Vector3(0.09, 0.86, 0.09), wood.darkened(0.15))
	for c in range(5):
		_cy(k_metal, Transform3D.IDENTITY, Vector3(bx - 1.3 + 0.32 * float(c), 0.265, bz + 0.1), 0.075, 0.16, [Color(0.6, 0.45, 0.2), Color(0.3, 0.35, 0.5), Color(0.55, 0.15, 0.1)][c % 3], Vector3.UP, 10)
	# the vise at the right end
	var vx := bx + bw * 0.5 - 0.35
	_b(k_metal, Transform3D.IDENTITY, Vector3(vx, 0.98, bz - 0.33), Vector3(0.16, 0.14, 0.24), Color(0.2, 0.32, 0.5))
	_b(k_metal, Transform3D.IDENTITY, Vector3(vx, 1.04, bz - 0.47), Vector3(0.18, 0.1, 0.05), Color(0.2, 0.32, 0.5))
	_cy(k_metal, Transform3D.IDENTITY, Vector3(vx, 0.98, bz - 0.52), 0.012, 0.2, steel, Vector3(0, 0, -1), 6)
	_cy(k_metal, Transform3D.IDENTITY, Vector3(vx - 0.12, 0.98, bz - 0.7), 0.008, 0.24, steel, Vector3(1, 0, 0), 6)
	# on the bench: a drill, an oil can, a rag, a coffee mug, a magneto in bits
	_b(k_metal, Transform3D.IDENTITY, Vector3(bx - 0.9, 0.97, bz - 0.1), Vector3(0.22, 0.12, 0.07), Color(0.75, 0.55, 0.15))
	_cy(k_metal, Transform3D.IDENTITY, Vector3(bx - 0.4, 0.91, bz + 0.1), 0.05, 0.1, Color(0.7, 0.6, 0.2))
	_rod(k_metal, Transform3D.IDENTITY, Vector3(bx - 0.4, 1.0, bz + 0.1), Vector3(bx - 0.25, 1.1, bz + 0.05), 0.006, Color(0.7, 0.6, 0.2))
	_b(k_cloth, Transform3D.IDENTITY, Vector3(bx + 0.2, 0.915, bz - 0.15), Vector3(0.3, 0.012, 0.25), Color(0.75, 0.2, 0.15), 0.4)
	_cy(k_paint, Transform3D.IDENTITY, Vector3(bx + 0.55, 0.91, bz + 0.15), 0.04, 0.1, Color(0.9, 0.88, 0.8))
	_b(k_metal, Transform3D.IDENTITY, Vector3(bx - 0.05, 0.95, bz + 0.05), Vector3(0.14, 0.1, 0.12), Color(0.25, 0.25, 0.27))
	# pegboard over the bench with the tools hung on it (outlines painted)
	var pz := HZ1 - 0.1
	_b(k_ply, Transform3D.IDENTITY, Vector3(bx, 1.55, pz), Vector3(bw, 1.1, 0.02), Color(0.68, 0.56, 0.40))
	for i in range(14):
		var tx := bx - bw * 0.5 + 0.2 + 0.24 * float(i)
		var kind := i % 5
		var ty := 1.55 + (0.25 if i % 2 == 0 else -0.2)
		match kind:
			0:      # wrench
				_b(k_metal, Transform3D.IDENTITY, Vector3(tx, ty, pz - 0.03), Vector3(0.025, 0.24, 0.01), Color(0.72, 0.72, 0.72))
			1:      # hammer
				_b(k_wood, Transform3D.IDENTITY, Vector3(tx, ty - 0.05, pz - 0.03), Vector3(0.025, 0.28, 0.02), Color(0.7, 0.55, 0.3))
				_b(k_metal, Transform3D.IDENTITY, Vector3(tx, ty + 0.1, pz - 0.04), Vector3(0.11, 0.035, 0.03), steel)
			2:      # screwdriver
				_b(k_paint, Transform3D.IDENTITY, Vector3(tx, ty + 0.06, pz - 0.03), Vector3(0.03, 0.09, 0.03), Color(0.85, 0.2, 0.1))
				_b(k_metal, Transform3D.IDENTITY, Vector3(tx, ty - 0.05, pz - 0.03), Vector3(0.008, 0.14, 0.008), Color(0.75, 0.75, 0.75))
			3:      # pliers
				_b(k_metal, Transform3D.IDENTITY, Vector3(tx - 0.015, ty, pz - 0.03), Vector3(0.014, 0.2, 0.01), Color(0.2, 0.3, 0.6), 0.1)
				_b(k_metal, Transform3D.IDENTITY, Vector3(tx + 0.015, ty, pz - 0.03), Vector3(0.014, 0.2, 0.01), Color(0.2, 0.3, 0.6), -0.1)
			4:      # a coil of safety wire / a saw
				_cy(k_metal, Transform3D.IDENTITY, Vector3(tx, ty, pz - 0.02), 0.07, 0.015, Color(0.7, 0.7, 0.68), Vector3(0, 0, -1), 10)
	# red rolling tool chest with its top box
	var tc := Vector3(bx + bw * 0.5 + 0.8, 0, bz)
	_b(k_paint, Transform3D.IDENTITY, tc + Vector3(0, 0.55, 0), Vector3(0.95, 0.9, 0.5), red)
	_b(k_paint, Transform3D.IDENTITY, tc + Vector3(0, 1.25, 0.02), Vector3(0.9, 0.45, 0.42), red.darkened(0.1))
	for d in range(7):
		var dy := 0.18 + 0.13 * float(d) if d < 5 else 1.12 + 0.12 * float(d - 5)
		_b(k_metal, Transform3D.IDENTITY, tc + Vector3(0, dy, -0.26 if d < 5 else -0.2), Vector3(0.85, 0.015, 0.015), Color(0.8, 0.8, 0.8))
	for wx in [-0.4, 0.4]:
		for wz in [-0.2, 0.2]:
			_cy(k_trim, Transform3D.IDENTITY, tc + Vector3(wx, 0.05, wz), 0.05, 0.04, Color(0.1, 0.1, 0.1), Vector3(1, 0, 0), 8)
	# parts shelves (slotted angle) in the back right corner: oil cases, filters,
	# spark plug boxes, tyres, a battery
	var sx0 := hx - 1.4
	for sy in [0.1, 0.65, 1.2, 1.75, 2.3]:
		_b(k_metal, Transform3D.IDENTITY, Vector3(sx0, sy, bz), Vector3(2.4, 0.03, 0.6), Color(0.45, 0.47, 0.42))
		if sy > 2.0:
			continue
		var n := 6
		for i2 in range(n):
			if _rng.randf() < 0.25:
				continue
			var c2: Color = [Color(0.85, 0.65, 0.15), Color(0.6, 0.1, 0.1), Color(0.78, 0.72, 0.56), Color(0.2, 0.35, 0.6), Color(0.12, 0.12, 0.12), Color(0.9, 0.9, 0.86)][_rng.randi() % 6]
			var hh := _rng.randf_range(0.14, 0.42)
			_b(k_paint, Transform3D.IDENTITY, Vector3(sx0 - 1.0 + 0.4 * float(i2), sy + 0.015 + hh * 0.5, bz + _rng.randf_range(-0.08, 0.08)), Vector3(0.32, hh, 0.36), c2, _rng.randf_range(-0.1, 0.1))
	for px in [sx0 - 1.18, sx0 + 1.18]:
		for pz2 in [bz - 0.28, bz + 0.28]:
			_b(k_metal, Transform3D.IDENTITY, Vector3(px, 1.2, pz2), Vector3(0.04, 2.4, 0.04), Color(0.45, 0.47, 0.42))
	# oil: a case of quarts, a 45-gal drum of oil with a pump, a drain pan
	_drum(Vector3(hx - 0.6, 0, HZ1 - 2.0), Color(0.2, 0.3, 0.5), "OIL")
	_b(k_metal, Transform3D.IDENTITY, Vector3(hx - 0.6, 1.05, HZ1 - 2.0), Vector3(0.08, 0.3, 0.08), Color(0.75, 0.6, 0.15))
	k_paint.cylinder(Transform3D(Basis.IDENTITY, Vector3(hx - 1.4, 0.0, HZ1 - 2.2)), 0.35, 0.38, 0.1, 14, Color(0.15, 0.15, 0.15), true)
	# compressor: a horizontal tank on wheels, motor and pump on top, a coil
	# of red air hose on the wall
	var cp := Vector3(hx - 1.0, 0, HZ1 - 3.4)
	_cy(k_paint, Transform3D.IDENTITY, cp + Vector3(-0.55, 0.35, 0), 0.25, 1.1, red, Vector3(1, 0, 0), 14)
	_b(k_metal, Transform3D.IDENTITY, cp + Vector3(0.1, 0.72, 0), Vector3(0.3, 0.22, 0.22), Color(0.25, 0.25, 0.27))
	_b(k_metal, Transform3D.IDENTITY, cp + Vector3(-0.25, 0.72, 0), Vector3(0.22, 0.24, 0.24), Color(0.3, 0.3, 0.32))
	_cy(k_metal, Transform3D.IDENTITY, cp + Vector3(-0.07, 0.72, -0.13), 0.12, 0.03, Color(0.6, 0.6, 0.6), Vector3(0, 0, -1), 12)
	_cy(k_paint, Transform3D.IDENTITY, Vector3(hx - 0.1, 1.6, HZ1 - 3.4), 0.25, 0.08, Color(0.75, 0.12, 0.1), Vector3(-1, 0, 0), 14)
	# engine hoist: an A-frame on casters with a chain fall, parked by the wall
	var ho := Vector3(-hx + 2.0, 0, -1.2)
	for sd in [-0.45, 0.45]:
		_beam(k_paint, ho + Vector3(sd, 0.08, -0.6), ho + Vector3(sd, 0.08, 0.6), Vector2(0.08, 0.08), Color(0.85, 0.65, 0.1))
	_beam(k_paint, ho + Vector3(0, 0.08, 0.5), ho + Vector3(0, 1.9, 0.2), Vector2(0.1, 0.1), Color(0.85, 0.65, 0.1))
	_beam(k_paint, ho + Vector3(0, 1.6, 0.25), ho + Vector3(0, 2.0, -0.9), Vector2(0.09, 0.09), Color(0.85, 0.65, 0.1))
	_rod(k_metal, Transform3D.IDENTITY, ho + Vector3(0, 1.95, -0.85), ho + Vector3(0, 1.2, -0.85), 0.01, Color(0.3, 0.3, 0.3))
	_b(k_metal, Transform3D.IDENTITY, ho + Vector3(0, 1.15, -0.85), Vector3(0.06, 0.1, 0.04), Color(0.3, 0.3, 0.3))
	# avgas: four drums on their side on a rack by the front, a barrel pump and
	# a filter funnel; a red jerry can
	for i3 in range(3):
		_drum(Vector3(hx - 0.6, 0, HZ0 + 3.0 + 0.7 * float(i3)), Color(0.15, 0.30, 0.60) if i3 != 1 else red, "AVGAS 100LL")
	_b(k_metal, Transform3D.IDENTITY, Vector3(hx - 0.6, 1.1, HZ0 + 3.0), Vector3(0.1, 0.35, 0.1), Color(0.8, 0.65, 0.1))
	_rod(k_metal, Transform3D.IDENTITY, Vector3(hx - 0.6, 1.25, HZ0 + 3.0), Vector3(hx - 0.9, 1.4, HZ0 + 2.8), 0.01, Color(0.3, 0.3, 0.3))
	_cy(k_trim, Transform3D.IDENTITY, Vector3(hx - 0.6, 1.25, HZ0 + 3.0), 0.02, 1.0, Color(0.1, 0.1, 0.1), Vector3(-0.5, -1.0, -0.4).normalized(), 6)
	_b(k_paint, Transform3D.IDENTITY, Vector3(hx - 1.2, 0.25, HZ0 + 2.2), Vector3(0.18, 0.46, 0.34), red)
	# a spare prop on the right wall, skis, a set of big tyres
	_b(k_metal, Transform3D.IDENTITY, Vector3(hx - 0.12, 2.9, 0.4), Vector3(0.04, 0.17, 2.1), Color(0.2, 0.2, 0.2))
	_cy(k_metal, Transform3D.IDENTITY, Vector3(hx - 0.13, 2.9, 0.4), 0.12, 0.12, Color(0.6, 0.6, 0.62), Vector3(-1, 0, 0), 12)
	for e2 in [-1.0, 1.0]:
		_b(k_paint, Transform3D.IDENTITY, Vector3(hx - 0.12, 2.9, 0.4 + e2 * 1.0), Vector3(0.045, 0.18, 0.1), Color(0.9, 0.75, 0.15))
	for sk in range(2):
		_b(k_paint, Transform3D.IDENTITY, Vector3(-hx + 0.25 + 0.12 * float(sk), 3.0 + 0.4 * float(sk), -2.5), Vector3(0.08, 0.1, 2.4), Color(0.85, 0.85, 0.82))
	for ty2 in range(2):
		k_trim.cylinder(Transform3D(Basis.IDENTITY, Vector3(hx - 0.6, 0.02 + 0.32 * float(ty2), HZ1 - 4.6)), 0.45, 0.45, 0.3, 16, Color(0.08, 0.08, 0.09), true)
		k_metal.cylinder(Transform3D(Basis.IDENTITY, Vector3(hx - 0.6, 0.025 + 0.32 * float(ty2), HZ1 - 4.6)), 0.15, 0.15, 0.305, 10, Color(0.7, 0.7, 0.7), true)
	# fire extinguishers by both doors, a first-aid box
	for fe in [Vector3(-DOOR_W * 0.5 - 0.7, 0, HZ0 + 0.18), Vector3(hx - 0.2, 0, HZ0 + 2.4)]:
		_cy(k_paint, Transform3D.IDENTITY, fe + Vector3(0, 0.9, 0), 0.08, 0.5, red, Vector3.UP, 10)
		_b(k_metal, Transform3D.IDENTITY, fe + Vector3(0, 1.45, 0), Vector3(0.05, 0.08, 0.05), Color(0.2, 0.2, 0.2))
	_b(k_paint, Transform3D.IDENTITY, Vector3(hx - 0.1, 1.6, HZ0 + 3.0), Vector3(0.12, 0.3, 0.4), Color(0.92, 0.92, 0.9))
	_b(k_paint, Transform3D.IDENTITY, Vector3(hx - 0.17, 1.6, HZ0 + 3.0), Vector3(0.01, 0.1, 0.04), Color(0.8, 0.1, 0.1))
	_b(k_paint, Transform3D.IDENTITY, Vector3(hx - 0.17, 1.6, HZ0 + 3.0), Vector3(0.01, 0.04, 0.1), Color(0.8, 0.1, 0.1))
	# tail stand, a creeper on the floor, chocks, a coil of tie-down rope
	_b(k_paint, Transform3D.IDENTITY, Vector3(2.5, 0.06, 2.5), Vector3(0.45, 0.04, 1.0), Color(0.2, 0.35, 0.5))
	for cz in [-0.4, 0.4]:
		for cx2 in [-0.18, 0.18]:
			_cy(k_trim, Transform3D.IDENTITY, Vector3(2.5 + cx2, 0.0, 2.5 + cz), 0.03, 0.04, Color(0.1, 0.1, 0.1))
	for ch in [-1.6, 1.6]:
		_b(k_wood, X(ch + 0.3, HZ0 + 3.4), Vector3(0, 0.08, 0), Vector3(0.18, 0.14, 0.32), Color(0.8, 0.65, 0.15))
	k_cloth.cylinder(Transform3D(Basis.IDENTITY, Vector3(-hx + 0.6, 0.0, HZ0 + 1.0)), 0.25, 0.25, 0.12, 12, Color(0.85, 0.82, 0.70), true)


## A 45-gallon drum standing at p, a stencilled band.
func _drum(p: Vector3, col: Color, text: String) -> void:
	k_paint.cylinder(Transform3D(Basis.IDENTITY, p), 0.29, 0.29, 0.88, 14, col, true)
	for ry in [0.29, 0.59]:
		k_metal.cylinder(Transform3D(Basis.IDENTITY, p + Vector3(0, ry, 0)), 0.295, 0.295, 0.025, 14, col.darkened(0.2), false)
	_cy(k_metal, Transform3D.IDENTITY, p + Vector3(0.15, 0.88, 0.1), 0.03, 0.02, Color(0.6, 0.6, 0.6))
	if text != "":
		_label(text, p + Vector3(0, 0.45, -0.3), PI, 0.0022, Color(0.95, 0.95, 0.9), 48)


## Freight waiting to go: a platform scale, boxes, sacks of flour, a crate of
## groceries, mail sacks, a hand truck, a propane bottle for a camp, a canoe.
func _cargo() -> void:
	var c0 := Vector3(HW * 0.5 - 2.6, 0, -0.6)
	# platform scale: a low deck on a base, a beam and a poise on a column
	_b(k_paint, Transform3D.IDENTITY, c0 + Vector3(0, 0.08, 0), Vector3(0.9, 0.12, 0.7), Color(0.32, 0.42, 0.32))
	_b(k_metal, Transform3D.IDENTITY, c0 + Vector3(0, 0.15, 0), Vector3(0.84, 0.02, 0.64), Color(0.55, 0.55, 0.55))
	_b(k_paint, Transform3D.IDENTITY, c0 + Vector3(0, 0.75, 0.3), Vector3(0.1, 1.2, 0.08), Color(0.32, 0.42, 0.32))
	_b(k_metal, Transform3D.IDENTITY, c0 + Vector3(0, 1.32, 0.3), Vector3(0.6, 0.04, 0.03), Color(0.75, 0.75, 0.72))
	_b(k_metal, Transform3D.IDENTITY, c0 + Vector3(0.12, 1.32, 0.3), Vector3(0.05, 0.07, 0.05), Color(0.3, 0.3, 0.3))
	# on the scale: a stack of boxes
	_b(k_paint, Transform3D.IDENTITY, c0 + Vector3(-0.1, 0.33, -0.05), Vector3(0.5, 0.35, 0.4), Color(0.72, 0.58, 0.38))
	_b(k_paint, Transform3D.IDENTITY, c0 + Vector3(0.05, 0.62, -0.05), Vector3(0.4, 0.25, 0.32), Color(0.76, 0.62, 0.42), 0.2)
	# the pile: boxes, flour sacks, a groceries crate, two mail sacks
	var pile := c0 + Vector3(0, 0, 1.5)
	for i in range(7):
		var w := _rng.randf_range(0.35, 0.6)
		var h := _rng.randf_range(0.25, 0.45)
		var px := pile.x + _rng.randf_range(-0.6, 0.6)
		var pz := pile.z + _rng.randf_range(-0.5, 0.5)
		var py := h * 0.5 + (0.0 if i < 4 else 0.45)
		_b(k_paint, Transform3D.IDENTITY, Vector3(px, py, pz), Vector3(w, h, w * 0.8), Color(0.70, 0.56, 0.36).darkened(_rng.randf_range(0, 0.15)), _rng.randf_range(-0.3, 0.3))
		_b(k_paint, Transform3D.IDENTITY, Vector3(px, py + h * 0.5 + 0.001, pz), Vector3(0.05, 0.003, w * 0.8 + 0.002), Color(0.6, 0.55, 0.4), 0.0)
	for j in range(4):
		var sp := pile + Vector3(-1.0 + 0.1 * float(j), 0.14 + 0.24 * float(j / 2), 0.9 + 0.32 * float(j % 2))
		k_cloth.rbox(Transform3D(Basis(Vector3.UP, 0.1 * float(j)), sp), Vector3(0.6, 0.24, 0.42), Color(0.86, 0.84, 0.76), 0.08)
	_label("FLOUR", pile + Vector3(-1.0, 0.16, 0.68), PI, 0.0022, Color(0.25, 0.3, 0.6), 48)
	for m in range(2):
		k_cloth.rbox(Transform3D(Basis(Vector3.UP, 0.4), pile + Vector3(0.9, 0.3, 1.0 + 0.5 * float(m))), Vector3(0.45, 0.6, 0.4), Color(0.45, 0.42, 0.30), 0.12)
	_label("MAIL", pile + Vector3(0.75, 0.35, 0.78), PI + 0.4, 0.0022, Color(0.12, 0.12, 0.1), 48)
	# a crate of groceries, open, cans and a loaf showing
	var cr := pile + Vector3(0.2, 0, 1.8)
	_b(k_wood, Transform3D.IDENTITY, cr + Vector3(0, 0.2, 0), Vector3(0.6, 0.4, 0.4), Color(0.62, 0.48, 0.30))
	for cc in range(4):
		_cy(k_paint, Transform3D.IDENTITY, cr + Vector3(-0.2 + 0.13 * float(cc), 0.4, -0.08), 0.04, 0.11, [Color(0.8, 0.2, 0.1), Color(0.9, 0.8, 0.2), Color(0.2, 0.5, 0.25), Color(0.85, 0.85, 0.82)][cc])
	k_cloth.rbox(Transform3D(Basis.IDENTITY, cr + Vector3(0.1, 0.45, 0.08)), Vector3(0.28, 0.12, 0.12), Color(0.82, 0.62, 0.32), 0.05)
	# the hand truck leaning by the pile
	var ht := pile + Vector3(1.2, 0, -0.3)
	var hb := Basis(Vector3.RIGHT, 0.25)
	for sd in [-0.18, 0.18]:
		k_paint.box(Transform3D(hb, ht + Vector3(sd, 0.65, 0.15)), Vector3(0.03, 1.3, 0.03), Color(0.2, 0.25, 0.5))
	k_paint.box(Transform3D(hb, ht + Vector3(0, 0.05, -0.02)), Vector3(0.4, 0.02, 0.2), Color(0.2, 0.25, 0.5))
	for sd2 in [-0.22, 0.22]:
		_cy(k_trim, Transform3D.IDENTITY, ht + Vector3(sd2, 0.1, 0.05), 0.1, 0.05, Color(0.1, 0.1, 0.1), Vector3(1, 0, 0), 10)
	# a propane bottle and a canoe on the wall going out to a camp
	_cy(k_paint, Transform3D.IDENTITY, pile + Vector3(-0.3, 0, -1.0), 0.15, 0.6, Color(0.92, 0.92, 0.9))
	_cy(k_metal, Transform3D.IDENTITY, pile + Vector3(-0.3, 0.6, -1.0), 0.05, 0.1, Color(0.6, 0.6, 0.6))
	var cn := Vector3(HW * 0.5 - 0.3, 3.4, -1.0)
	k_paint.rbox(Transform3D(Basis.IDENTITY, cn), Vector3(0.3, 0.35, 4.8), Color(0.15, 0.40, 0.25), 0.15)
	k_paint.rbox(Transform3D(Basis.IDENTITY, cn + Vector3(0, -0.18, 0)), Vector3(0.24, 0.05, 4.2), Color(0.12, 0.30, 0.18), 0.02)
	# the freight tag clipboard on a nail by the scale
	_b(k_wood, Transform3D.IDENTITY, Vector3(HW * 0.5 - 0.1, 1.5, -0.3), Vector3(0.02, 0.32, 0.23), Color(0.62, 0.48, 0.3))
	_b(k_paint, Transform3D.IDENTITY, Vector3(HW * 0.5 - 0.115, 1.48, -0.3), Vector3(0.005, 0.27, 0.21), Color(0.95, 0.94, 0.9))
	_b(k_metal, Transform3D.IDENTITY, Vector3(HW * 0.5 - 0.12, 1.63, -0.3), Vector3(0.015, 0.03, 0.08), Color(0.7, 0.7, 0.7))


# (filled in next, live in the lab)
func _furnish() -> void:
	pass


func _loft_stuff(_at: Vector3) -> void:
	pass


func _fire_cache() -> void:
	pass


func _outside() -> void:
	pass


func _road_end() -> void:
	pass
