extends RefCounted
## The Wolverine's engine under the cowling: a six-cylinder horizontally
## opposed engine (a 470 cu in flat six), in the plane's own space. The
## crankcase runs fore and aft on the propeller line; three cylinders a side,
## the left bank set back a little; spark plugs top and bottom of each head;
## two magnetos, the oil filter and the dipstick on the back by the firewall;
## the alternator and its belt low on the front; the air filter at the intake.
##
## SPOTS are the places you can look at and work on, used by engine_service.gd.

const MeshKit = preload("res://scripts/meshkit.gd")

const AXIS_Y := 0.05
const CASE := Color(0.62, 0.62, 0.60)        # cast aluminium
const CYL := Color(0.18, 0.18, 0.19)         # black barrel fins
const HEAD := Color(0.70, 0.71, 0.70)        # bare aluminium heads
const GOLD := Color(0.74, 0.55, 0.18)        # gold valve covers
const STEEL := Color(0.55, 0.56, 0.58)
const RUST := Color(0.45, 0.28, 0.16)
const BLACK := Color(0.07, 0.07, 0.07)
const LEAD := Color(0.15, 0.25, 0.55)
const CERAMIC := Color(0.92, 0.92, 0.88)
const FILTER := Color(0.85, 0.40, 0.10)
const AIRF := Color(0.75, 0.15, 0.10)
const FIREWALL := Color(0.30, 0.31, 0.30)


## Cylinder n (1..6, the usual numbering: 1 right rear, 2 left rear, then
## forward in pairs): [side (+1 right), station z].
static func cylinder_at(n: int) -> Array:
	var side := 1.0 if n % 2 == 1 else -1.0
	var row := (n - 1) / 2            # 0 rear, 1 middle, 2 front
	var z := -1.36 - 0.20 * float(row)
	if side < 0.0:
		z += 0.07
	return [side, z]


## Where you look to see something: [id, label, position, radius].
static func spots() -> Array:
	var out: Array = []
	out.append(["dipstick", "Oil filler and dipstick", Vector3(0.13, 0.24, -1.30), 0.06])
	out.append(["oil_filter", "Oil filter", Vector3(-0.19, 0.02, -1.25), 0.07])
	out.append(["mag_l", "Left magneto", Vector3(-0.10, 0.10, -1.24), 0.06])
	out.append(["mag_r", "Right magneto", Vector3(0.10, 0.10, -1.24), 0.06])
	out.append(["air_filter", "Air filter", Vector3(0.0, -0.37, -1.88), 0.09])
	out.append(["belt", "Alternator and belt", Vector3(-0.17, -0.10, -1.88), 0.08])
	out.append(["exhaust", "Exhaust and muffler", Vector3(0.30, -0.45, -1.45), 0.09])
	out.append(["battery", "Battery", Vector3(0.30, 0.20, -1.24), 0.09])
	out.append(["logbook", "Engine data plate and logbook", Vector3(-0.32, 0.26, -1.19), 0.06])
	for n in range(1, 7):
		var c := cylinder_at(n)
		var s: float = c[0]
		var z: float = c[1]
		out.append(["plug_%d_top" % n, "Cylinder %d top spark plug" % n, Vector3(s * 0.39, 0.15 + AXIS_Y - 0.05, z), 0.035])
		out.append(["plug_%d_bot" % n, "Cylinder %d bottom spark plug" % n, Vector3(s * 0.39, -0.12, z), 0.035])
		out.append(["cyl_%d" % n, "Cylinder %d" % n, Vector3(s * 0.28, AXIS_Y, z), 0.075])
	return out


## The parts you can take off, each its own node so it can visibly come out:
## kit geometry in the plane's own space (same numbers as build()).
static func part_kit(id: String) -> RefCounted:
	var kit = MeshKit.new()
	var ay := AXIS_Y
	if id.begins_with("plug_"):
		var bits := id.split("_")
		var n := int(bits[1])
		var top := bits[2] == "top"
		var c := cylinder_at(n)
		var s: float = c[0]
		var z: float = c[1]
		var py: float = ay + (0.10 if top else -0.17)
		var tip := Vector3(s * 0.39, py, z + 0.05)
		var outer := Vector3(s * 0.39, py + (0.05 if top else -0.05), z + 0.05)
		_rod(kit, tip, outer, 0.011, CERAMIC, 6)
		_rod(kit, outer, outer + Vector3(0, 0.02 if top else -0.02, 0), 0.014, STEEL, 6)
	elif id.begins_with("cyl_"):
		var n2 := int(id.split("_")[1])
		var c2 := cylinder_at(n2)
		var s2: float = c2[0]
		var z2: float = c2[1]
		_rod(kit, Vector3(s2 * 0.14, ay, z2), Vector3(s2 * 0.33, ay, z2), 0.066, CYL, 12)
		var fx := 0.16
		while fx < 0.33:
			_rod(kit, Vector3(s2 * fx, ay, z2), Vector3(s2 * (fx + 0.006), ay, z2), 0.084, CYL, 12)
			fx += 0.018
		_rod(kit, Vector3(s2 * 0.33, ay, z2), Vector3(s2 * 0.45, ay, z2), 0.072, HEAD, 10)
		var hx := 0.335
		while hx < 0.44:
			kit.box_at(Vector3(s2 * hx, ay, z2), Vector3(0.005, 0.19, 0.17), HEAD.darkened(0.06))
			hx += 0.016
		kit.box_at(Vector3(s2 * 0.41, ay + 0.105, z2), Vector3(0.09, 0.035, 0.15), GOLD)
		kit.box_at(Vector3(s2 * 0.41, ay - 0.105, z2), Vector3(0.09, 0.035, 0.15), GOLD)
	elif id == "oil_filter":
		_rod(kit, Vector3(-0.19, ay - 0.03, -1.28), Vector3(-0.19, ay - 0.03, -1.15), 0.045, FILTER, 12)
	elif id == "air_filter":
		kit.box_at(Vector3(0, -0.36, -1.88), Vector3(0.22, 0.06, 0.14), AIRF)
	elif id == "battery":
		kit.box_at(Vector3(0.30, 0.20, -1.24), Vector3(0.18, 0.17, 0.12), BLACK)
		kit.box_at(Vector3(0.25, 0.295, -1.24), Vector3(0.03, 0.02, 0.03), Color(0.7, 0.1, 0.1))
		kit.box_at(Vector3(0.35, 0.295, -1.24), Vector3(0.03, 0.02, 0.03), BLACK.lightened(0.2))
	elif id == "exhaust":
		_rod(kit, Vector3(0.30, -0.47, -1.62), Vector3(0.30, -0.47, -1.32), 0.06, RUST.lightened(0.1), 10)
	elif id == "dipstick":
		# Yellow T-handle cap; the blade below it sits hidden in the filler tube
		# until it's pulled (engine_service slides the node out).
		_rod(kit, Vector3(0.13, 0.19 + ay, -1.30), Vector3(0.13, 0.215 + ay, -1.30), 0.026, Color(0.85, 0.75, 0.10), 8)
		kit.box_at(Vector3(0.13, 0.10 + ay, -1.30), Vector3(0.012, 0.22, 0.004), STEEL)
	return kit


## All the removable parts as named child nodes of `holder` (plane space).
static func build_removable(holder: Node3D) -> void:
	var ids: Array = ["oil_filter", "air_filter", "battery", "exhaust", "dipstick"]
	for n in range(1, 7):
		ids.append("cyl_%d" % n)
		ids.append("plug_%d_top" % n)
		ids.append("plug_%d_bot" % n)
	for id in ids:
		holder.add_child((part_kit(id) as RefCounted).instance(id))


static func _rod(kit: RefCounted, a: Vector3, b: Vector3, r: float, col: Color, sides: int = 6) -> void:
	var d := b - a
	if d.length() < 0.0005:
		return
	var y := d.normalized()
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	kit.cylinder(Transform3D(Basis(x, y, z), a), r, r, d.length(), sides, col)


static func build(kit: RefCounted) -> void:
	var ay := AXIS_Y
	# Firewall behind it all, so you don't see into the cabin.
	kit.box_at(Vector3(0, -0.05, -1.17), Vector3(0.98, 0.95, 0.02), FIREWALL)
	# Crankcase, the nose and the propeller flange, the sump underneath.
	kit.box_at(Vector3(0, ay, -1.57), Vector3(0.28, 0.30, 0.66), CASE)
	kit.box_at(Vector3(0, ay + 0.16, -1.57), Vector3(0.18, 0.04, 0.60), CASE.darkened(0.08))
	_rod(kit, Vector3(0, ay, -1.90), Vector3(0, ay, -2.03), 0.07, CASE, 12)
	kit.box_at(Vector3(0, ay - 0.21, -1.55), Vector3(0.24, 0.12, 0.50), CASE.darkened(0.15))
	# Accessory case on the back.
	kit.box_at(Vector3(0, ay, -1.24), Vector3(0.34, 0.26, 0.08), CASE.darkened(0.05))
	for n in range(1, 7):
		var c := cylinder_at(n)
		var s: float = c[0]
		var z: float = c[1]
		# A short mounting stub (the cylinder itself is its own node, so a
		# removed one leaves a bare pad with studs - build_removable()).
		_rod(kit, Vector3(s * 0.13, ay, z), Vector3(s * 0.155, ay, z), 0.062, CASE.darkened(0.1), 10)
		# The plug leads (the plugs themselves are their own nodes, so they can
		# come out in your hand - build_removable()).
		for top in [true, false]:
			var py: float = ay + (0.10 if top else -0.17)
			var outer := Vector3(s * 0.39, py + (0.05 if top else -0.05), z + 0.05)
			var mag_x := 0.10 if s > 0.0 else -0.10
			_rod(kit, outer, Vector3(s * 0.25, ay + (0.22 if top else -0.05), lerpf(z, -1.26, 0.5)), 0.006, LEAD, 4)
			_rod(kit, Vector3(s * 0.25, ay + (0.22 if top else -0.05), lerpf(z, -1.26, 0.5)), Vector3(mag_x, ay + 0.05, -1.26), 0.006, LEAD, 4)
		# Intake tube up from the sump; exhaust pipe down to the collector.
		_rod(kit, Vector3(s * 0.08, ay - 0.27, z), Vector3(s * 0.37, ay - 0.12, z - 0.04), 0.018, STEEL, 6)
		_rod(kit, Vector3(s * 0.42, ay - 0.12, z + 0.04), Vector3(s * 0.33, -0.44, z + 0.04), 0.022, RUST, 6)
	# Exhaust collectors and the muffler under the right side, out the stack.
	for s in [-1.0, 1.0]:
		_rod(kit, Vector3(s * 0.33, -0.44, -1.80), Vector3(s * 0.33, -0.44, -1.30), 0.03, RUST, 8)
	_rod(kit, Vector3(-0.33, -0.44, -1.80), Vector3(0.33, -0.44, -1.80), 0.03, RUST, 8)
	# (the muffler is its own node: build_removable())
	# Magnetos on the accessory case, with red caps.
	for s in [-1.0, 1.0]:
		_rod(kit, Vector3(s * 0.10, ay + 0.05, -1.20), Vector3(s * 0.10, ay + 0.05, -1.08), 0.045, BLACK, 10)
		_rod(kit, Vector3(s * 0.10, ay + 0.05, -1.21), Vector3(s * 0.10, ay + 0.05, -1.20), 0.05, Color(0.6, 0.1, 0.08), 10)
	# Oil filler tube (the dipstick in it is its own node: build_removable()).
	_rod(kit, Vector3(0.10, ay + 0.10, -1.30), Vector3(0.13, ay + 0.19, -1.30), 0.018, CASE, 8)
	# Alternator low on the left front, the belt round the prop flange pulley.
	_rod(kit, Vector3(-0.18, -0.13, -1.84), Vector3(-0.18, -0.13, -1.66), 0.06, CASE.darkened(0.2), 12)
	_rod(kit, Vector3(-0.18, -0.13, -1.87), Vector3(-0.18, -0.13, -1.84), 0.035, STEEL, 10)
	_rod(kit, Vector3(0, ay, -1.92), Vector3(0, ay, -1.89), 0.10, STEEL, 14)
	for off in [-1.0, 1.0]:
		var n := Vector2(0.18, -0.18).normalized()
		var perp: Vector3 = Vector3(-n.y, n.x, 0) * 0.07 * float(off)
		_rod(kit, Vector3(0, ay, -1.885) + perp * 1.3, Vector3(-0.18, -0.13, -1.855) + perp * 0.5, 0.008, BLACK, 4)
	# Intake box frame and the carburettor (the filter element is its own node).
	kit.box_at(Vector3(0, -0.36, -1.88), Vector3(0.26, 0.085, 0.18), CASE.darkened(0.25))
	kit.box_at(Vector3(0, -0.33, -1.70), Vector3(0.12, 0.10, 0.12), CASE.darkened(0.1))
	_rod(kit, Vector3(0, -0.33, -1.76), Vector3(0, -0.36, -1.82), 0.04, STEEL, 8)
	# Battery tray on the firewall (the battery is its own node).
	kit.box_at(Vector3(0.30, 0.115, -1.24), Vector3(0.20, 0.02, 0.14), STEEL.darkened(0.2))
	# Data plate on the firewall (the logbook lives in the plane).
	kit.box_at(Vector3(-0.32, 0.26, -1.185), Vector3(0.10, 0.06, 0.005), Color(0.80, 0.78, 0.70))
	# Engine mounts to the firewall.
	for s in [-1.0, 1.0]:
		for yy in [ay + 0.12, ay - 0.15]:
			_rod(kit, Vector3(s * 0.12, yy, -1.28), Vector3(s * 0.30, yy + 0.05 * s, -1.18), 0.012, Color(0.2, 0.25, 0.2), 6)
