extends Node3D
## The small things round the home town and its bush airport (DESIGN_NOTES
## 234; Dave's town pictures reference/towns/dave_town_*, entrance_v1-4):
##   0 quonset       the airport's round-roofed corrugated hangar (40 x 60 ft)
##   1 windsock      on its pole, orange and white
##   2 fuel_tank     a horizontal avgas tank on saddles, with a ladder
##   3 welcome_sign  "WELCOME TO ..." on two posts, a rail fence either side
##   4 water_tower   a wooden tank on a timber trestle
##   5 power_pole    a creosoted pole with its crossarm and insulators
##   6 street_lamp   a cobra-head lamp on a wooden pole
## Origin: the foot at the ground; the front toward -Z. Lab: "town_props".

const Kits = preload("res://scripts/assets/kits.gd")
const TOWN_NAME := "PINE RIDGE"        # from Dave's Grok pictures; change here
const NAMES := ["quonset", "windsock", "fuel_tank", "welcome_sign", "water_tower", "power_pole", "street_lamp"]
## the crossarm's insulator tops on a power pole (for stringing the lines)
const POLE_H := 10.0
const ARM := [-1.1, 0.0, 1.1]


func _ready() -> void:
	if get_child_count() > 0:
		return
	var x := 0.0
	for i in range(NAMES.size()):
		var n: Node3D = make_variant(i)
		n.position = Vector3(x, 0, 0)
		add_child(n)
		x += [24.0, 8.0, 10.0, 12.0, 12.0, 6.0, 6.0][i]


static func make() -> Node3D:
	return make_variant(0)


static func make_variant(i: int) -> Node3D:
	var K := Kits.new()
	match i:
		0: _quonset(K)
		1: _windsock(K)
		2: _fuel_tank(K)
		3: _welcome(K)
		4: _water_tower(K)
		5: _power_pole(K)
		_: _lamp(K)
	var n := K.node(NAMES[clampi(i, 0, NAMES.size() - 1)])
	for l in K.get_meta("labels", []):
		n.add_child(l)
	return n


static func _label(K: Kits, text: String, at: Vector3, px: float, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = px
	l.modulate = col
	l.position = at
	l.rotation.y = PI
	l.shaded = true
	l.outline_size = 0
	var arr: Array = K.get_meta("labels", [])
	arr.append(l)
	K.set_meta("labels", arr)


# --- 0: the Quonset hangar ---------------------------------------------------------
static func _quonset(K: Kits) -> void:
	var r := 6.1            # a 40 ft span
	var L := 18.3           # 60 ft long
	var segs := 16
	K.piece("shell", {"mat": "steel_sheet", "kind": "panel", "t": 0.001, "size": Vector2(L, PI * r), "normal": Vector3.UP, "ground": true, "links": []})
	var ck := K.k("corr")
	for s in range(segs):
		var a0 := PI * float(s) / float(segs)
		var a1 := PI * float(s + 1) / float(segs)
		var p0 := Vector3(cos(a0) * r, sin(a0) * r, 0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r, 0)
		var mid := (p0 + p1) * 0.5
		ck.quad(p0, p0 + Vector3(0, 0, L), p1 + Vector3(0, 0, L), p1, Color(0.62, 0.60, 0.56), mid.normalized())
	# the end walls: the back one plain, the front with the big sliding doors
	for z in [0.0, L]:
		var front: bool = is_zero_approx(float(z))
		K.piece("end_%s" % ("front" if front else "back"), {"mat": "steel_sheet", "kind": "panel", "t": 0.001, "size": Vector2(2.0 * r, r), "normal": Vector3(0, 0, -1 if front else 1), "links": ["shell"]})
		var ek := K.k("corr")
		for s in range(segs):
			var a0 := PI * float(s) / float(segs)
			var a1 := PI * float(s + 1) / float(segs)
			ek.tri(Vector3(0, 0, z), Vector3(cos(a0) * r, sin(a0) * r, z), Vector3(cos(a1) * r, sin(a1) * r, z), Color(0.55, 0.53, 0.50), Vector3(0, 0, -1 if front else 1))
	# the doors: two leaves of painted steel across the front, a header above
	for sd in [-1.0, 1.0]:
		K.piece("door_%d" % int(sd), {"mat": "steel_sheet", "kind": "panel", "t": 0.001, "size": Vector2(4.6, 4.6), "normal": Vector3(0, 0, -1), "links": ["end_front"]})
		Kits.box(K.k("paint"), Vector3(sd * 2.3, 2.3, -0.08), Vector3(4.55, 4.6, 0.06), Color(0.55, 0.20, 0.15))
		for p in range(4):
			Kits.box(K.k("paint"), Vector3(sd * 2.3, 0.6 + 1.15 * float(p), -0.12), Vector3(4.5, 0.05, 0.02), Color(0.42, 0.16, 0.12))
	Kits.box(K.k("rust"), Vector3(0, 4.75, -0.1), Vector3(9.6, 0.25, 0.2), Color.WHITE)
	Kits.box(K.k("rust"), Vector3(0, 0.03, -0.3), Vector3(9.6, 0.06, 0.4), Color.WHITE)            # the door track
	# a man door and a window in the back end; a concrete apron in front
	Kits.box(K.k("concrete"), Vector3(0, 0.02, -4.0), Vector3(11.0, 0.06, 8.0), Color(0.75, 0.74, 0.70))


# --- 1: the windsock ----------------------------------------------------------------
static func _windsock(K: Kits) -> void:
	K.piece("pole", {"mat": "steel", "kind": "member", "a": Vector3.ZERO, "b": Vector3(0, 6.0, 0), "sec": Vector2(0.08, 0.08), "fill": 1.0, "ground": true, "links": []})
	Kits.rod(K.k("galv"), Vector3.ZERO, Vector3(0, 6.0, 0), 0.04, Color.WHITE, 8)
	K.k("galv").cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.3, 6.0, 0)), 0.3, 0.3, 0.04, 12, Color.WHITE, false)   # the ring
	# the sock: five bands, orange and white, tapering, sagging a little
	var bands := 5
	for b in range(bands):
		var x0 := 0.32 + 0.5 * float(b)
		var r0 := 0.30 - 0.035 * float(b)
		var col := Color(0.95, 0.45, 0.10) if b % 2 == 0 else Color(0.95, 0.94, 0.92)
		K.k("plain").cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5 + 0.12), Vector3(x0 + 0.25, 6.0 - 0.06 * float(b), 0)), r0, r0 - 0.035, 0.5, 12, col, false)
	Kits.box(K.k("concrete"), Vector3(0, 0.1, 0), Vector3(0.8, 0.2, 0.8), Color(0.75, 0.74, 0.70))


# --- 2: the fuel tank ------------------------------------------------------------------
static func _fuel_tank(K: Kits) -> void:
	K.piece("tank", {"mat": "steel", "kind": "block", "ground": true, "links": []})
	K.k("paint").cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 1.6, 0)), 1.1, 1.1, 5.5, 18, Color(0.88, 0.87, 0.82))
	for x in [-1.8, 1.8]:
		Kits.box(K.k("concrete"), Vector3(x, 0.4, 0), Vector3(0.5, 0.8, 2.0), Color(0.75, 0.74, 0.70))
	Kits.box(K.k("paint"), Vector3(0, 1.6, -1.12), Vector3(5.0, 0.35, 0.02), Color(0.62, 0.15, 0.12))     # the band
	_label(K, "AVGAS 100LL", Vector3(0, 1.6, -1.15), 0.004, Color(0.95, 0.94, 0.9))
	# the pump stand and hose reel at one end
	Kits.box(K.k("paint"), Vector3(3.4, 0.7, 0), Vector3(0.6, 1.4, 0.6), Color(0.62, 0.15, 0.12))
	Kits.rod(K.k("plain"), Vector3(3.4, 1.2, -0.3), Vector3(3.6, 0.2, -1.0), 0.03, Color(0.08, 0.08, 0.08), 5)
	# the ladder to the fill cap
	for x in [-0.25, 0.25]:
		Kits.rod(K.k("galv"), Vector3(x, 0, -1.4), Vector3(x, 2.8, -0.6), 0.02, Color.WHITE, 4)


# --- 3: the welcome sign ------------------------------------------------------------------
static func _welcome(K: Kits) -> void:
	K.piece("sign", {"mat": "timber", "kind": "panel", "t": 0.08, "size": Vector2(3.6, 2.0), "normal": Vector3(0, 0, -1), "ground": true, "links": []})
	for x in [-1.5, 1.5]:
		Kits.box(K.k("timber"), Vector3(x, 1.3, 0), Vector3(0.22, 2.6, 0.22), Color(0.55, 0.42, 0.30))
	Kits.box(K.k("paint_wood"), Vector3(0, 2.0, 0), Vector3(3.6, 1.7, 0.1), Color(0.20, 0.32, 0.24))
	Kits.box(K.k("paint_wood"), Vector3(0, 2.0, 0.0), Vector3(3.8, 1.85, 0.06), Color(0.50, 0.40, 0.28))     # the frame
	_label(K, "WELCOME TO", Vector3(0, 2.5, -0.07), 0.0035, Color(0.92, 0.88, 0.75))
	_label(K, TOWN_NAME, Vector3(0, 2.05, -0.07), 0.0058, Color(0.95, 0.92, 0.80))
	_label(K, "EST. 1887", Vector3(0, 1.5, -0.07), 0.0032, Color(0.92, 0.88, 0.75))
	# rocks at its foot, the split-rail fence running off one side
	for p in [[-1.0, 0.25, 0.55], [0.6, 0.2, 0.45], [1.9, 0.3, 0.6]]:
		Kits.box(K.k("rock"), Vector3(float(p[0]), float(p[1]) * 0.6, -0.4), Vector3(float(p[2]) * 1.6, float(p[1]) * 1.6, float(p[2]) * 1.3), Color(0.7, 0.68, 0.64), float(p[0]))
	K.piece("fence", {"mat": "timber", "kind": "panel", "t": 0.1, "size": Vector2(9.0, 1.1), "normal": Vector3(0, 0, -1), "links": []})
	for k in range(4):
		Kits.box(K.k("timber"), Vector3(2.5 + 2.4 * float(k), 0.55, 0.3), Vector3(0.14, 1.1, 0.14), Color(0.6, 0.5, 0.4))
	for h in [0.45, 0.9]:
		Kits.box(K.k("timber"), Vector3(6.1, h, 0.3), Vector3(7.4, 0.1, 0.08), Color(0.6, 0.5, 0.4))


# --- 4: the water tower ----------------------------------------------------------------------
static func _water_tower(K: Kits) -> void:
	var h := 9.0
	var legs: Array = []
	for c in [Vector2(-1.8, -1.8), Vector2(1.8, -1.8), Vector2(1.8, 1.8), Vector2(-1.8, 1.8)]:
		var a := Vector3(c.x * 1.15, 0, c.y * 1.15)
		var b := Vector3(c.x, h, c.y)
		var id := "leg_%d_%d" % [int(c.x), int(c.y)]
		K.piece(id, {"mat": "timber", "kind": "member", "a": a, "b": b, "sec": Vector2(0.3, 0.3), "fill": 1.0, "ground": true, "links": ["tank"]})
		Kits.beam(K.k("timber"), a, b, 0.3, Color(0.55, 0.45, 0.35))
		legs.append([a, b])
	# cross bracing on each face, two bays
	for f in range(4):
		var l0: Array = legs[f]
		var l1: Array = legs[(f + 1) % 4]
		for bay in range(2):
			var t0 := float(bay) / 2.0
			var t1 := float(bay + 1) / 2.0
			Kits.beam(K.k("timber"), (l0[0] as Vector3).lerp(l0[1], t0), (l1[0] as Vector3).lerp(l1[1], t1), 0.12, Color(0.5, 0.42, 0.33))
			Kits.beam(K.k("timber"), (l1[0] as Vector3).lerp(l1[1], t0), (l0[0] as Vector3).lerp(l0[1], t1), 0.12, Color(0.5, 0.42, 0.33))
	K.piece("tank", {"mat": "timber", "kind": "block", "links": []})
	Kits.box(K.k("timber"), Vector3(0, h + 0.15, 0), Vector3(4.6, 0.3, 4.6), Color(0.5, 0.42, 0.33))
	K.k("wood").cylinder(Transform3D(Basis.IDENTITY, Vector3(0, h + 0.3, 0)), 2.5, 2.4, 4.2, 20, Color(0.62, 0.50, 0.40))
	for hy in [0.6, 1.8, 3.0, 3.9]:
		K.k("rust").cylinder(Transform3D(Basis.IDENTITY, Vector3(0, h + 0.3 + hy, 0)), 2.53, 2.53, 0.08, 20, Color.WHITE, false)   # the iron hoops
	K.k("shingle").cylinder(Transform3D(Basis.IDENTITY, Vector3(0, h + 4.5, 0)), 2.8, 0.1, 1.6, 12, Color(0.5, 0.48, 0.45))         # the conical roof
	Kits.rod(K.k("galv"), Vector3(0, h + 0.3, 2.5), Vector3(0, 0.0, 2.5), 0.08, Color.WHITE, 6)                                       # the down pipe


# --- 5: a power pole -----------------------------------------------------------------------------
static func _power_pole(K: Kits) -> void:
	K.piece("pole", {"mat": "timber", "kind": "member", "a": Vector3.ZERO, "b": Vector3(0, POLE_H + 0.6, 0), "sec": Vector2(0.28, 0.28), "fill": 1.0, "ground": true, "links": []})
	K.k("timber").cylinder(Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.15, 0.12, POLE_H + 0.6, 8, Color(0.42, 0.33, 0.25))
	Kits.box(K.k("timber"), Vector3(0, POLE_H, 0), Vector3(2.6, 0.12, 0.1), Color(0.45, 0.36, 0.27))
	for x in ARM:
		K.k("plain").cylinder(Transform3D(Basis.IDENTITY, Vector3(x, POLE_H + 0.06, 0)), 0.06, 0.05, 0.18, 6, Color(0.40, 0.55, 0.45))   # glass insulators
	for s in [-1.0, 1.0]:
		Kits.beam(K.k("timber"), Vector3(0, POLE_H - 0.6, 0), Vector3(s * 0.8, POLE_H - 0.02, 0), 0.04, Color(0.45, 0.36, 0.27))
	# a transformer can on some, the ground wire
	K.k("galv").cylinder(Transform3D(Basis.IDENTITY, Vector3(0, POLE_H - 1.6, 0.25)), 0.25, 0.25, 0.8, 10, Color(0.7, 0.72, 0.72))


# --- 6: a street lamp --------------------------------------------------------------------------------
static func _lamp(K: Kits) -> void:
	K.piece("pole", {"mat": "timber", "kind": "member", "a": Vector3.ZERO, "b": Vector3(0, 7.5, 0), "sec": Vector2(0.24, 0.24), "fill": 1.0, "ground": true, "links": []})
	K.k("timber").cylinder(Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.13, 0.11, 7.5, 8, Color(0.42, 0.33, 0.25))
	Kits.rod(K.k("galv"), Vector3(0, 7.0, 0), Vector3(0, 7.3, -1.8), 0.035, Color.WHITE, 5)
	Kits.box(K.k("galv"), Vector3(0, 7.25, -2.0), Vector3(0.35, 0.18, 0.7), Color(0.7, 0.72, 0.72))
	K.k_mat("lamp", load("res://scripts/assets/glow.gd").get_lamp()).box(Transform3D(Basis.IDENTITY, Vector3(0, 7.15, -2.0)), Vector3(0.28, 0.03, 0.55), Color.WHITE)
