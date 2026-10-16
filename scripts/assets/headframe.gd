extends Node3D
## The mine headframe (DESIGN_NOTES 228): an old timber four-post headframe
## over the shaft like the ones above the mountain mining towns - 18 m of
## 12x12 posts leaning in, girts and X-braces, the two back legs raking down
## to take the hoist's pull; the twin sheave wheels on the deck; the collar
## and the shaft; the hoist house behind (rusty corrugated iron on a timber
## frame, a stack); the ore bin downhill on its timber stilts over the
## track, the chute. Base at the shaft collar, downhill +Z. Lab: "headframe".

const Kits = preload("res://scripts/assets/kits.gd")

const H := 18.0


func _ready() -> void:
	if get_child_count() == 0:
		add_child(make())


static func make() -> Node3D:
	var K := Kits.new()
	var tb := K.k("timber")
	var T := Color(0.62, 0.52, 0.42)
	var hb := 2.2
	var ht := 1.2
	var post := func(sx: float, sz: float, t: float) -> Vector3: return Vector3(sx * lerpf(hb, ht, t), H * t, sz * lerpf(hb, ht, t))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Kits.beam(tb, post.call(sx, sz, 0.0), post.call(sx, sz, 1.0), 0.3, T)
			K.k("concrete").box(Transform3D(Basis.IDENTITY, post.call(sx, sz, 0.0) + Vector3(0, 0.1, 0)), Vector3(0.9, 0.5, 0.9), Color.WHITE)
		# the back leg: from a footing behind up to near the top
		Kits.beam(tb, Vector3(sx * 1.6, 0, -9.5), post.call(sx, -1.0, 0.92), 0.3, T)
		K.k("concrete").box(Transform3D(Basis.IDENTITY, Vector3(sx * 1.6, 0.1, -9.5)), Vector3(0.9, 0.5, 0.9), Color.WHITE)
		for bl in range(3):
			var tbl := float(bl + 1) / 4.0
			var on_leg := Vector3(sx * 1.6, 0, -9.5).lerp(post.call(sx, -1.0, 0.92), tbl)
			Kits.beam(tb, on_leg, post.call(sx, -1.0, on_leg.y / H), 0.18, T)
	for lv in range(5):
		var t0 := float(lv) / 5.0
		var t1 := float(lv + 1) / 5.0
		for e in range(4):
			var c0: Array = [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]][e]
			var c1: Array = [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]][(e + 1) % 4]
			Kits.beam(tb, post.call(c0[0], c0[1], t1), post.call(c1[0], c1[1], t1), 0.22, T)
			Kits.beam(tb, post.call(c0[0], c0[1], t0), post.call(c1[0], c1[1], t1), 0.14, T)
			Kits.beam(tb, post.call(c1[0], c1[1], t0), post.call(c0[0], c0[1], t1), 0.14, T)
	# the sheave deck and the two wheels, the cables back to the hoist house
	var wd := K.k("wood")
	Kits.box(wd, Vector3(0, H + 0.1, 0), Vector3(ht * 2.0 + 0.6, 0.2, ht * 2.0 + 0.6), Color.WHITE)
	# the sheaves: dark steel spoked wheels (a rim, a hub, eight spokes) on the deck
	var stl := K.k("galv")
	var dark := Color(0.22, 0.22, 0.23)
	for sx2 in [-0.5, 0.5]:
		var hub := Vector3(sx2, H + 1.4, 0)
		for q in range(24):
			var a0 := TAU * float(q) / 24.0
			var a1 := TAU * float(q + 1) / 24.0
			Kits.rod(stl, hub + Vector3(0, sin(a0), cos(a0)) * 1.25, hub + Vector3(0, sin(a1), cos(a1)) * 1.25, 0.07, dark, 5)
		for sp in range(8):
			var a2 := TAU * float(sp) / 8.0
			Kits.rod(stl, hub, hub + Vector3(0, sin(a2), cos(a2)) * 1.2, 0.035, dark, 4)
		stl.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), hub - Vector3(0.15, 0, 0)), 0.15, 0.15, 0.3, 10, dark)
		Kits.rod(K.k("plain"), hub + Vector3(0, 1.25, 0.1), Vector3(sx2 * 0.6, 3.2, -16.0), 0.02, Color(0.15, 0.15, 0.15), 3)
		Kits.rod(K.k("plain"), hub + Vector3(0, 0, 1.25), Vector3(sx2, 1.0, 1.25), 0.02, Color(0.15, 0.15, 0.15), 3)
	# the collar: timber sets round the shaft, the dark hole, the cage at the top of it
	Kits.box(wd, Vector3(0, 0.15, 0), Vector3(3.2, 0.3, 3.2), Color(0.8, 0.75, 0.7))
	K.k("plain").box(Transform3D(Basis.IDENTITY, Vector3(0, 0.31, 0)), Vector3(2.0, 0.02, 1.6), Color(0.02, 0.02, 0.02))
	K.k("rust").box(Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 0.4)), Vector3(1.3, 2.0, 1.1), Color(0.8, 0.8, 0.8))
	# the hoist house: a long corrugated shed behind, timber frame, a stack
	var hc := Vector3(0, 0, -16.0)
	var cr := K.k("corr_rust")
	cr.box(Transform3D(Basis.IDENTITY, hc + Vector3(0, 2.5, 0)), Vector3(8.0, 5.0, 11.0), Color.WHITE)
	for sz2 in [-1.0, 1.0]:
		cr.quad(hc + Vector3(-4.3, 5.0, 5.8 * sz2), hc + Vector3(4.3, 5.0, 5.8 * sz2), hc + Vector3(4.3, 6.6, 0), hc + Vector3(-4.3, 6.6, 0), Color(0.85, 0.85, 0.85), Vector3(0, 1, sz2))
	for sx3 in [-1.0, 1.0]:
		cr.tri(hc + Vector3(4.0 * sx3, 5.0, -5.5), hc + Vector3(4.0 * sx3, 5.0, 5.5), hc + Vector3(4.0 * sx3, 6.6, 0), Color.WHITE, Vector3(sx3, 0, 0))
	K.k("plain").box(Transform3D(Basis.IDENTITY, hc + Vector3(0, 3.2, 5.52)), Vector3(1.6, 1.0, 0.03), Color(0.03, 0.03, 0.03))       # the rope opening
	Kits.rod(K.k("rust"), hc + Vector3(2.4, 6.0, -3.0), hc + Vector3(2.4, 13.0, -3.0), 0.35, Color(0.5, 0.45, 0.4), 10)
	# the ore bin downhill on stilts, its chute over the track
	var ob := Vector3(0, 0, 9.0)
	for sx4 in [-1.6, 1.6]:
		for sz4 in [-1.6, 1.6]:
			Kits.beam(tb, ob + Vector3(sx4, -3.0, sz4), ob + Vector3(sx4, 5.0, sz4), 0.28, T)
	K.k("wood").box(Transform3D(Basis.IDENTITY, ob + Vector3(0, 7.0, 0)), Vector3(4.2, 4.0, 4.2), Color(0.75, 0.7, 0.62))
	K.k("wood").box(Transform3D(Basis(Vector3.RIGHT, 0.6), ob + Vector3(0, 4.6, 2.6)), Vector3(1.0, 0.3, 2.2), Color(0.7, 0.65, 0.58))
	# the tramway from the collar to the bin: two rails on ties on a trestle
	for k2 in range(8):
		var z := 1.8 + float(k2)
		Kits.box(wd, Vector3(0, 0.45 + float(k2) * 0.0, z), Vector3(1.4, 0.12, 0.2), Color(0.6, 0.55, 0.5))
	for sx5 in [-0.3, 0.3]:
		Kits.beam(K.k("rust"), Vector3(sx5, 0.55, 1.8), Vector3(sx5, 0.55, 9.0), 0.06, Color.WHITE)
	return K.node("headframe")
