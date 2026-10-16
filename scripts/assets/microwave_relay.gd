extends Node3D
## Microwave relay on a summit (DESIGN_NOTES 228): the phone and TV links of
## the '70s-'80s hopping peak to peak. A 30 m square self-supporting galvanised
## tower, K-braced, a platform with a rail at the top; drum antennas (dishes
## behind white fabric radome covers, the round grey shrouds) aimed off along
## the valleys at different heights, the waveguide running down to the
## equipment building (concrete block, flat roof), the generator and fuel tank,
## a steady red light on top. Base at the origin. Lab: "microwave_relay".

const Kits = preload("res://scripts/assets/kits.gd")
const Glow = preload("res://scripts/assets/glow.gd")

const H := 30.0
const B0 := 2.6
const B1 := 1.3


func _ready() -> void:
	if get_child_count() == 0:
		add_child(make())


static func leg(i: int, t: float) -> Vector3:
	var sx := -1.0 if (i == 0 or i == 3) else 1.0
	var sz := -1.0 if i < 2 else 1.0
	var hw := lerpf(B0, B1, t)
	return Vector3(sx * hw, H * t, sz * hw)


static func make() -> Node3D:
	var K := Kits.new()
	var g := K.k("galv")
	var W := Color.WHITE
	var ns := 6
	for i in range(4):
		Kits.beam(g, leg(i, 0.0), leg(i, 1.0), 0.14, W)
		K.k("concrete").box(Transform3D(Basis.IDENTITY, leg(i, 0.0) + Vector3(0, 0.2, 0)), Vector3(1.0, 0.7, 1.0), W)
	for s in range(ns):
		var t0 := float(s) / ns
		var t1 := float(s + 1) / ns
		var tm := (t0 + t1) * 0.5
		for e in range(4):
			var i0 := e
			var i1 := (e + 1) % 4
			# K-bracing: from each leg at the bottom of the panel to the middle of the girt above
			var mid := (leg(i0, t1) + leg(i1, t1)) * 0.5
			Kits.beam(g, leg(i0, t0), mid, 0.06, W)
			Kits.beam(g, leg(i1, t0), mid, 0.06, W)
			Kits.beam(g, leg(i0, t1), leg(i1, t1), 0.08, W)
			var _m := tm
	# the top platform: grating, a rail
	Kits.box(g, Vector3(0, H, 0), Vector3(B1 * 2.0 + 1.2, 0.08, B1 * 2.0 + 1.2), Color(0.8, 0.8, 0.8))
	var r := B1 + 0.6
	for s2 in range(4):
		var b := Basis(Vector3.UP, PI * 0.5 * float(s2))
		Kits.beam(g, b * Vector3(-r, H + 1.05, -r), b * Vector3(r, H + 1.05, -r), 0.05, W)
		for pp in range(4):
			var q := b * Vector3(-r + 2.0 * r * float(pp) / 4.0, H, -r)
			Kits.beam(g, q, q + Vector3(0, 1.05, 0), 0.05, W)
	K.k_mat("steady", Glow.get_steady()).cylinder(Transform3D(Basis.IDENTITY, Vector3(0, H + 2.4, 0)), 0.12, 0.1, 0.25, 8, W)
	Kits.rod(g, Vector3(0, H, 0), Vector3(0, H + 2.4, 0), 0.04, W, 6)
	# the drums: [height, aim yaw, diameter]
	var shroud := K.k("paint")
	var cover := K.k("plain")
	for d in [[H - 2.0, 0.4, 3.0], [H - 2.0, 2.6, 3.0], [H - 6.5, 4.4, 2.4], [H - 10.0, 1.4, 1.8], [H - 6.5, 5.6, 1.8]]:
		var y: float = d[0]
		var yaw: float = d[1]
		var rad: float = float(d[2]) * 0.5
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var hw := lerpf(B0, B1, y / H)
		var o := Vector3(0, y, 0) + dir * (hw + rad * 0.5 + 0.5)
		var bas := Basis.looking_at(-dir, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
		shroud.cylinder(Transform3D(bas, o - dir * rad * 0.55), rad, rad, rad * 0.55, 24, Color(0.62, 0.64, 0.66))
		cover.cylinder(Transform3D(bas, o), rad * 0.98, rad * 0.9, 0.12, 24, Color(0.93, 0.93, 0.9))
		# the mount: two pipes back to the legs
		for sd in [-1.0, 1.0]:
			Kits.rod(g, o - dir * rad * 0.5 + dir.cross(Vector3.UP) * rad * 0.6 * sd, Vector3(0, y, 0) + dir * hw * 0.9 + dir.cross(Vector3.UP) * hw * 0.9 * sd, 0.05, W, 5)
		# the waveguide (elliptical, black) down the leg to the building
		Kits.rod(K.k("plain"), o - dir * rad * 0.6, Vector3(B1 * 0.8, y, B1 * 0.8), 0.04, Color(0.08, 0.08, 0.08), 4)
	Kits.rod(K.k("plain"), Vector3(B1 * 0.8, H - 2.0, B1 * 0.8), Vector3(B0 * 0.9, 2.6, B0 * 0.9), 0.09, Color(0.08, 0.08, 0.08), 5)
	# the equipment building and the waveguide bridge
	var bc := Vector3(11.0, 0, 5.0)
	K.k("concrete").box(Transform3D(Basis.IDENTITY, bc + Vector3(0, 1.5, 0)), Vector3(7.0, 3.0, 5.0), Color(0.95, 0.94, 0.9))
	K.k("rust").box(Transform3D(Basis.IDENTITY, bc + Vector3(0, 3.08, 0)), Vector3(7.3, 0.16, 5.3), Color(0.5, 0.5, 0.5))
	K.k("paint").box(Transform3D(Basis.IDENTITY, bc + Vector3(0.8, 1.05, 2.52)), Vector3(0.95, 2.1, 0.05), Color(0.35, 0.42, 0.50))
	Kits.beam(g, Vector3(B0 * 0.9, 2.6, B0 * 0.9), bc + Vector3(-3.5, 2.6, 0), 0.35, W)
	# fuel tank and the generator exhaust
	K.k("paint").rbox(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(17.0, 1.0, 2.0)), Vector3(1.1, 3.4, 1.1), Color(0.92, 0.92, 0.9), 0.5)
	Kits.rod(K.k("rust"), bc + Vector3(3.0, 3.0, -1.5), bc + Vector3(3.0, 4.6, -1.5), 0.07, W, 8)
	return K.node("microwave_relay")
