extends Node3D
## Bridges (DESIGN_NOTES 235; Dave: "gorges with bridges going over that I
## can fly under"). Variant = kind * 1000 + span in metres:
##   kind 0  a steel pony-truss road bridge (1930s-50s highway style): two
##           Pratt trusses either side of a timber-decked roadway on steel
##           floor beams, concrete abutments
##   kind 1  a steel deck-arch bridge high over a gorge: two ribbed arches
##           springing from the gorge walls below, spandrel columns up to a
##           deck girder, railings - room to fly a plane under the arch
## Origin: the middle of the deck at road level, the roadway along X.
## Built of pieces (structure.gd) like everything else.
## Lab: "bridge" (both, 40 m and 170 m).

const Kits = preload("res://scripts/assets/kits.gd")

const STEEL := Color(0.42, 0.45, 0.46)          # old grey-green bridge paint, weathered
const DECK_W := 7.6


func _ready() -> void:
	if get_child_count() > 0:
		return
	var a: Node3D = make_variant(40)
	add_child(a)
	var b: Node3D = make_variant(1170)
	b.position = Vector3(0, 0, 60)
	add_child(b)


static func make() -> Node3D:
	return make_variant(40)


static func make_variant(v: int) -> Node3D:
	var kind := v / 1000
	var span := float(maxi(v % 1000, 10))
	var K := Kits.new()
	if kind == 1:
		_deck_arch(K, span)
	else:
		_pony_truss(K, span)
	return K.node("bridge")


# --- 0: the pony truss ---------------------------------------------------------------
static func _pony_truss(K: Kits, L: float) -> void:
	var hw := DECK_W * 0.5
	var bays := maxi(int(round(L / 5.0)), 4)
	var bl := L / float(bays)
	var H := 2.6
	var y0 := -0.6                                     # the bottom chord, under the deck
	# the deck: timber planks on steel stringers, steel floor beams at each panel point
	K.piece("deck", {"mat": "timber", "kind": "panel", "t": 0.1, "size": Vector2(L, DECK_W), "normal": Vector3.UP, "links": ["truss_l", "truss_r"]})
	Kits.box(K.k("asphalt"), Vector3(0, -0.05, 0), Vector3(L, 0.1, DECK_W - 0.6), Color(0.9, 0.9, 0.9))
	Kits.box(K.k("timber"), Vector3(0, -0.2, 0), Vector3(L, 0.2, DECK_W - 0.4), Color(0.55, 0.45, 0.35))
	for i in range(bays + 1):
		Kits.box(K.k("paint"), Vector3(-L * 0.5 + bl * float(i), y0 + 0.15, 0), Vector3(0.3, 0.45, DECK_W + 0.6), STEEL)
	for sz in [-hw + 1.2, -1.2, 1.2, hw - 1.2]:
		Kits.box(K.k("paint"), Vector3(0, -0.45, sz), Vector3(L, 0.3, 0.2), STEEL)
	# the two trusses: chords, verticals, diagonals (Pratt: sloping toward the middle)
	for side in [-1.0, 1.0]:
		var z: float = side * (hw + 0.25)
		var id := "truss_l" if side < 0.0 else "truss_r"
		K.piece(id, {"mat": "steel", "kind": "member", "a": Vector3(-L * 0.5, y0, z), "b": Vector3(L * 0.5, y0, z), "sec": Vector2(0.3, H), "fill": 0.15, "ground": true, "links": []})
		var pk := K.k("paint")
		Kits.box(pk, Vector3(0, y0, z), Vector3(L, 0.35, 0.3), STEEL)                       # bottom chord
		Kits.box(pk, Vector3(0, y0 + H, z), Vector3(L - bl * 2.0, 0.3, 0.32), STEEL)       # top chord
		for e in [-1.0, 1.0]:                                                                  # the end posts slope down
			Kits.beam(pk, Vector3(e * L * 0.5, y0, z), Vector3(e * (L * 0.5 - bl), y0 + H, z), 0.3, STEEL)
		for i in range(1, bays):
			var x := -L * 0.5 + bl * float(i)
			Kits.beam(pk, Vector3(x, y0, z), Vector3(x, y0 + H, z), 0.16, STEEL)            # verticals
			var mid := x < 0.0
			var x2 := x + (bl if mid else -bl)
			if absf(x2) < L * 0.5 - bl * 0.5:
				Kits.beam(pk, Vector3(x, y0 + H, z), Vector3(x2, y0, z), 0.12, STEEL)         # diagonals
		# a rail along the inside
		Kits.box(pk, Vector3(0, 0.9, z - side * 0.25), Vector3(L, 0.12, 0.08), STEEL)
	# the abutments: concrete, with wing walls, going down into the bank
	for e in [-1.0, 1.0]:
		K.piece("abut_%d" % int(e), {"mat": "concrete", "kind": "block", "ground": true, "links": ["deck"]})
		Kits.box(K.k("concrete"), Vector3(e * (L * 0.5 + 1.2), -3.0, 0), Vector3(2.6, 6.0, DECK_W + 1.6), Color(0.75, 0.74, 0.70))
		for sz in [-1.0, 1.0]:
			Kits.box(K.k("concrete"), Vector3(e * (L * 0.5 + 4.0), -2.2, sz * (hw + 0.6)), Vector3(4.0, 4.4, 0.5), Color(0.75, 0.74, 0.70))


# --- 1: the deck arch over a gorge ------------------------------------------------------
static func _deck_arch(K: Kits, L: float) -> void:
	var hw := DECK_W * 0.5
	var rise := L * 0.38                               # the arch's crown under the deck, springing well down the walls
	var crown := -3.2                                  # the crown just under the deck girders
	var spring := crown - rise
	var segs := 28
	var bay := L / 14.0
	# the deck: concrete on steel girders, railings
	K.piece("deck", {"mat": "concrete", "kind": "panel", "t": 0.25, "size": Vector2(L, DECK_W), "normal": Vector3.UP, "links": ["arch_l", "arch_r"]})
	Kits.box(K.k("asphalt"), Vector3(0, -0.06, 0), Vector3(L + 2.0, 0.12, DECK_W - 0.8), Color(0.9, 0.9, 0.9))
	Kits.box(K.k("concrete"), Vector3(0, -0.3, 0), Vector3(L + 2.0, 0.4, DECK_W), Color(0.72, 0.71, 0.68))
	for sz in [-hw + 0.8, hw - 0.8]:
		Kits.box(K.k("paint"), Vector3(0, -1.3, sz), Vector3(L + 2.0, 1.6, 0.4), STEEL)       # deck girders
		Kits.box(K.k("concrete"), Vector3(0, 0.45, sz + signf(sz) * 0.55), Vector3(L + 2.0, 0.9, 0.25), Color(0.72, 0.71, 0.68))   # parapet
	# the two arch ribs (box girders, deeper at the springing)
	for side in [-1.0, 1.0]:
		var z: float = side * (hw - 0.8)
		var id := "arch_l" if side < 0.0 else "arch_r"
		K.piece(id, {"mat": "steel", "kind": "member", "a": Vector3(-L * 0.5, spring, z), "b": Vector3(L * 0.5, spring, z), "sec": Vector2(1.0, 2.4), "fill": 0.2, "ground": true, "links": []})
		var prev := Vector3.ZERO
		for i in range(segs + 1):
			var t := float(i) / float(segs)
			var x := -L * 0.5 + L * t
			var y := spring + rise * (1.0 - pow(2.0 * t - 1.0, 2.0))     # a parabola
			var p := Vector3(x, y, z)
			if i > 0:
				var depth := lerpf(2.6, 1.6, 1.0 - absf(2.0 * t - 1.0))
				Kits.beam(K.k("paint"), prev, p, depth * 0.55, STEEL)
			prev = p
		# the spandrel columns from the rib up to the deck
		var nb := int(L / bay)
		for i in range(1, nb):
			var x := -L * 0.5 + bay * float(i)
			var t := (x + L * 0.5) / L
			var y := spring + rise * (1.0 - pow(2.0 * t - 1.0, 2.0))
			if crown - y > 0.8:
				Kits.beam(K.k("paint"), Vector3(x, y, z), Vector3(x, -2.1, z), 0.45, STEEL)
	# cross bracing between the ribs (lateral struts)
	for i in range(1, segs, 2):
		var t := float(i) / float(segs)
		var x := -L * 0.5 + L * t
		var y := spring + rise * (1.0 - pow(2.0 * t - 1.0, 2.0))
		Kits.box(K.k("paint"), Vector3(x, y, 0), Vector3(0.35, 0.35, DECK_W - 1.6), STEEL)
	# the skewbacks: concrete footings where the arch meets the rock
	for e in [-1.0, 1.0]:
		K.piece("foot_%d" % int(e), {"mat": "concrete", "kind": "block", "ground": true, "links": ["arch_l", "arch_r"]})
		Kits.box(K.k("concrete"), Vector3(e * (L * 0.5 + 1.5), spring - 1.0, 0), Vector3(5.0, 5.0, DECK_W + 1.0), Color(0.72, 0.71, 0.68))
		# the approach piers from the deck ends down to the rim
		Kits.box(K.k("concrete"), Vector3(e * (L * 0.5 + 2.0), -4.0, 0), Vector3(3.0, 8.0, DECK_W), Color(0.72, 0.71, 0.68))
