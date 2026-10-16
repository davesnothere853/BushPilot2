extends Node3D
## Guyed radio mast on the ridge over town (DESIGN_NOTES 228): 120 m, a
## triangular lattice (1.4 m faces), solid round legs with zig-zag rods,
## painted in seven bands aviation orange and white (orange top and bottom, as
## the FAA rule has it), a flashing red beacon on top and steady red lights at
## the levels between. Guyed three ways at three levels to concrete deadmen;
## the FM antenna bays up top, a dish; the block transmitter building with the
## coax ice bridge to the mast, the generator shed, a propane tank, chain-link
## round it all. Base at the origin, the site levelled ~75 m round.
## Lab: "radio_mast".

const Kits = preload("res://scripts/assets/kits.gd")
const Glow = preload("res://scripts/assets/glow.gd")

const H := 120.0
const FACE := 1.4
const GUY_R := 68.0
const ORANGE := Color(0.90, 0.36, 0.10)
const WHITE := Color(0.93, 0.93, 0.91)


func _ready() -> void:
	if get_child_count() == 0:
		add_child(make())


static func make() -> Node3D:
	var K := Kits.new()
	var p := K.k("paint")
	var legs: Array = []
	for i in range(3):
		var a := TAU * float(i) / 3.0 + PI / 6.0
		legs.append(Vector3(cos(a), 0, sin(a)) * FACE / sqrt(3.0))
	var bay := 1.4
	var nb := int(H / bay)
	for b in range(nb):
		var y0 := bay * float(b)
		var y1 := y0 + bay
		var band := mini(int(y0 / (H / 7.0)), 6)
		var col := ORANGE if band % 2 == 0 else WHITE
		for i in range(3):
			var l0: Vector3 = legs[i]
			var l1: Vector3 = legs[(i + 1) % 3]
			Kits.rod(p, l0 + Vector3(0, y0, 0), l0 + Vector3(0, y1, 0), 0.05, col, 6)
			Kits.rod(p, l0 + Vector3(0, y0, 0), l1 + Vector3(0, y0 + bay * 0.5, 0), 0.016, col, 3)
			Kits.rod(p, l1 + Vector3(0, y0 + bay * 0.5, 0), l0 + Vector3(0, y1, 0), 0.016, col, 3)
	# the base pier and the top plate, the lightning rod / beacon pole
	K.k("concrete").box(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), Vector3(2.4, 1.0, 2.4), Color.WHITE)
	Kits.rod(p, Vector3(0, H, 0), Vector3(0, H + 4.0, 0), 0.08, ORANGE, 8)
	K.k_mat("beacon", Glow.get_beacon()).cylinder(Transform3D(Basis.IDENTITY, Vector3(0, H + 4.0, 0)), 0.22, 0.18, 0.45, 10, Color.WHITE)
	var st := K.k_mat("steady", Glow.get_steady())
	for lv in [H * 0.25, H * 0.5, H * 0.75]:
		for i2 in range(3):
			var lp: Vector3 = legs[i2]
			st.cylinder(Transform3D(Basis.IDENTITY, lp * 1.25 + Vector3(0, lv, 0)), 0.1, 0.08, 0.2, 8, Color.WHITE)
	# FM bays on a side arm, the side-mounted dish at mid height
	var g := K.k("galv")
	for j in range(6):
		var yy := H - 3.0 - 2.8 * float(j)
		Kits.rod(g, Vector3(0, yy, 0), Vector3(1.4, yy, 0), 0.035, Color.WHITE, 5)
		g.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(1.4, yy, 0)), 0.45, 0.45, 0.04, 12, Color.WHITE, false)
		g.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(1.4, yy, -0.02)), 0.45, 0.45, 0.04, 12, Color.WHITE, false)
	K.k("plain").cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(1.6, 62.0, 0)), 1.2, 1.2, 0.5, 18, Color(0.85, 0.85, 0.83))
	# the guys: three ways, three levels, to concrete deadmen
	var cable := K.k("plain")
	for i3 in range(3):
		var a3 := TAU * float(i3) / 3.0 + PI / 6.0
		var dv := Vector3(cos(a3), 0, sin(a3))
		var an := dv * GUY_R
		for lv2 in [0.33, 0.66, 0.95]:
			Kits.rod(cable, (legs[i3] as Vector3) + Vector3(0, H * float(lv2), 0), an + Vector3(0, 0.8, 0), 0.016, Color(0.35, 0.35, 0.35), 3)
			# the turnbuckle and insulators at the bottom
			cable.cylinder(Transform3D(Basis.looking_at(-((legs[i3] as Vector3) + Vector3(0, H * float(lv2), 0) - an).normalized(), Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5), an + Vector3(0, 0.8, 0)), 0.04, 0.04, 1.2, 6, Color(0.4, 0.4, 0.4))
		K.k("concrete").box(Transform3D(Basis(Vector3.UP, -a3), an + Vector3(0, 0.25, 0)), Vector3(2.4, 1.0, 1.6), Color.WHITE)
	# the transmitter building: concrete block, a flat roof with a parapet, a
	# steel door, the ice bridge (a grating on posts) carrying the coax to the mast
	var bc := Vector3(14.0, 0, 7.0)
	var conc := K.k("concrete")
	conc.box(Transform3D(Basis.IDENTITY, bc + Vector3(0, 1.6, 0)), Vector3(8.0, 3.2, 5.0), Color(0.95, 0.94, 0.9))
	K.k("rust").box(Transform3D(Basis.IDENTITY, bc + Vector3(0, 3.28, 0)), Vector3(8.3, 0.16, 5.3), Color(0.5, 0.5, 0.5))
	K.k("paint").box(Transform3D(Basis.IDENTITY, bc + Vector3(-4.02, 1.05, 0.8)), Vector3(0.05, 2.1, 0.95), Color(0.35, 0.42, 0.50))
	K.k("paint").box(Transform3D(Basis.IDENTITY, bc + Vector3(-1.5, 2.4, -2.52)), Vector3(1.0, 0.6, 0.05), Color(0.55, 0.55, 0.55))      # the AC unit grille
	for k2 in range(6):
		var t := float(k2) / 5.0
		var q := (bc + Vector3(-4.0, 2.6, -1.0)).lerp(Vector3(0.6, 2.6, 0.3), t)
		Kits.rod(g, Vector3(q.x, 0, q.z), q, 0.05, Color.WHITE, 5)
	Kits.beam(g, bc + Vector3(-4.0, 2.65, -1.0), Vector3(0.6, 2.65, 0.3), 0.4, Color.WHITE)
	Kits.rod(K.k("plain"), bc + Vector3(-4.0, 2.75, -1.0), Vector3(0.6, 2.75, 0.3), 0.06, Color(0.1, 0.1, 0.1), 6)
	# the generator shed and the propane tank on its saddles
	var gs := Vector3(14.0, 0, -2.0)
	K.k("corr").box(Transform3D(Basis.IDENTITY, gs + Vector3(0, 1.1, 0)), Vector3(3.0, 2.2, 2.4), Color(0.85, 0.85, 0.85))
	Kits.rod(K.k("rust"), gs + Vector3(0.8, 2.2, 0.5), gs + Vector3(0.8, 3.4, 0.5), 0.07, Color.WHITE, 8)
	var tk := Vector3(20.0, 0, 3.0)
	for sx in [-0.9, 0.9]:
		conc.box(Transform3D(Basis.IDENTITY, tk + Vector3(sx, 0.25, 0)), Vector3(0.3, 0.5, 1.0), Color.WHITE)
	K.k("paint").rbox(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), tk + Vector3(0, 1.0, 0)), Vector3(1.05, 3.0, 1.05), Color(0.92, 0.92, 0.9), 0.5)
	_fence(K, Vector3(8.0, 0, 3.0), Vector2(34.0, 26.0))
	return K.node("radio_mast")


static func _fence(K: Kits, c: Vector3, s: Vector2) -> void:
	var g := K.k("galv")
	var mesh := K.k_mat("chainlink", load("res://scripts/tex.gd").clear(Color(0.62, 0.64, 0.64, 0.38), 0.4))
	var corners := [Vector3(-s.x, 0, -s.y) * 0.5, Vector3(s.x, 0, -s.y) * 0.5, Vector3(s.x, 0, s.y) * 0.5, Vector3(-s.x, 0, s.y) * 0.5]
	for i in range(4):
		var a: Vector3 = c + (corners[i] as Vector3)
		var e: Vector3 = c + (corners[(i + 1) % 4] as Vector3)
		var n := maxi(int(a.distance_to(e) / 3.0), 1)
		for j in range(n + 1):
			var q := a.lerp(e, float(j) / n)
			Kits.rod(g, q, q + Vector3(0, 2.1, 0), 0.03, Color.WHITE, 6)
			for bw in range(3):
				var arm := q + Vector3(0, 2.1, 0) + (e - a).normalized().cross(Vector3.UP) * 0.06 * float(bw)
				var _x := arm
		Kits.rod(g, a + Vector3(0, 2.08, 0), e + Vector3(0, 2.08, 0), 0.02, Color.WHITE, 5)
		for wy in [2.25, 2.4]:
			Kits.rod(K.k("plain"), a + Vector3(0, wy, 0), e + Vector3(0, wy, 0), 0.005, Color(0.4, 0.4, 0.4), 3)     # barbed wire
		var nrm := (e - a).cross(Vector3.UP).normalized()
		mesh.quad(a + Vector3(0, 0.03, 0), e + Vector3(0, 0.03, 0), e + Vector3(0, 2.06, 0), a + Vector3(0, 2.06, 0), Color.WHITE, nrm)
