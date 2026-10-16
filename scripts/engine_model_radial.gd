extends RefCounted
## The DC-3's engine in its nacelle: a twin-row fourteen-cylinder radial
## (a 14-cylinder twin-row radial), in the plane's own space, one per side.
## The side panels of the nacelle open for servicing (dc3_visual.gd); the
## cylinders sit in two rows of seven round the crankcase, the magnetos and
## oil filter on the accessory case behind, the carburettor under the back,
## the oil tank with its dipstick on the firewall.
##
## SPOTS are what you can look at and work on (engine_service.gd). Ids are
## prefixed e0_ (left engine) or e1_ (right), so the service knows which
## engine's parts it is holding.

const MeshKit = preload("res://scripts/meshkit.gd")

const CASE := Color(0.55, 0.56, 0.58)
const CYL := Color(0.16, 0.16, 0.17)
const HEAD := Color(0.62, 0.63, 0.62)
const BLACK := Color(0.07, 0.07, 0.07)
const LEAD := Color(0.15, 0.25, 0.55)
const CERAMIC := Color(0.92, 0.92, 0.88)
const FILTER := Color(0.85, 0.40, 0.10)
const RUST := Color(0.45, 0.28, 0.16)

const CENTRE := Vector3(0.0, -0.05, -3.18)   # crank centreline, nacelle space (add x)
const ROW_Z := [-3.30, -3.08]                # front row, back row


static func nacelle_x(ei: int) -> float:
	return -3.35 if ei == 0 else 3.35


## Cylinder n (1..14): front row odd positions, back row staggered between.
static func cyl_at(n: int) -> Array:
	var row := (n - 1) % 2            # 0 front, 1 back
	var i := (n - 1) / 2
	var a := TAU * (float(i) + (0.5 if row == 1 else 0.0)) / 7.0 - PI * 0.5
	return [a, ROW_Z[row]]


## [id, label, position (plane space), radius]
static func spots(ei: int) -> Array:
	var x := nacelle_x(ei)
	var p := "e%d_" % ei
	var side := "left" if ei == 0 else "right"
	var out: Array = []
	out.append([p + "dipstick", "Oil tank dipstick (%s engine)" % side, Vector3(x, 0.52, -2.43), 0.07])
	out.append([p + "oil_filter", "Oil filter (%s engine)" % side, Vector3(x - 0.42, -0.30, -2.62), 0.07])
	out.append([p + "mag_l", "Left magneto (%s engine)" % side, Vector3(x - 0.18, 0.28, -2.72), 0.06])
	out.append([p + "mag_r", "Right magneto (%s engine)" % side, Vector3(x + 0.18, 0.28, -2.72), 0.06])
	out.append([p + "air_filter", "Carburettor air filter (%s engine)" % side, Vector3(x, -0.62, -2.55), 0.09])
	out.append([p + "exhaust", "Exhaust collector ring (%s engine)" % side, Vector3(x + 0.55, -0.60, -2.85), 0.09])
	out.append([p + "logbook", "Engine data plate (%s engine)" % side, Vector3(x, 0.10, -2.55), 0.06])
	if ei == 0:
		out.append([p + "battery", "Battery", Vector3(x + 0.55, 0.30, -2.52), 0.09])
	for n in range(1, 15):
		var c := cyl_at(n)
		var a: float = c[0]
		var z: float = c[1]
		var at := Vector3(x + cos(a) * 0.62, -0.05 + sin(a) * 0.62, z)
		out.append([p + "cyl_%d" % n, "Cylinder %d (%s engine)" % [n, side], at, 0.085])
	return out


static func _rod(kit: RefCounted, a: Vector3, b: Vector3, r: float, col: Color, sides: int = 6) -> void:
	var d := b - a
	if d.length() < 0.0005:
		return
	var y := d.normalized()
	var xx := y.cross(Vector3.UP)
	if xx.length() < 0.01:
		xx = y.cross(Vector3.RIGHT)
	xx = xx.normalized()
	var z := xx.cross(y)
	kit.cylinder(Transform3D(Basis(xx, y, z), a), r, r, d.length(), sides, col)


## The fixed heart of the engine: crankcase, accessory case, oil tank,
## carburettor, pushrods and plug leads (the rest is removable nodes).
static func build(kit: RefCounted, ei: int) -> void:
	var x := nacelle_x(ei)
	var c := CENTRE + Vector3(x, 0, 0)
	# Crankcase: a short drum between the rows, nose case ahead.
	kit.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), c + Vector3(0, 0, -0.24)), 0.34, 0.34, 0.46, 14, CASE)
	kit.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), c + Vector3(0, 0, -0.40)), 0.22, 0.26, 0.16, 12, CASE.darkened(0.1))
	# Accessory case behind, with the drives the mags sit on.
	kit.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), c + Vector3(0, 0, 0.38)), 0.30, 0.34, 0.30, 12, CASE.darkened(0.15))
	# Oil tank: a kidney drum high on the firewall, filler neck for the dipstick.
	kit.box_at(Vector3(x, 0.38, -2.45), Vector3(0.70, 0.30, 0.22), Color(0.35, 0.37, 0.33))
	_rod(kit, Vector3(x, 0.50, -2.44), Vector3(x, 0.545, -2.44), 0.025, CASE, 8)
	# Carburettor under the accessory case.
	kit.box_at(Vector3(x, -0.52, -2.68), Vector3(0.26, 0.22, 0.26), CASE.darkened(0.2))
	# Pushrod tubes fanning to the front row, and plug leads to both rows.
	for n in range(1, 15):
		var cc := cyl_at(n)
		var a: float = cc[0]
		var z: float = cc[1]
		var foot := Vector3(x + cos(a) * 0.36, -0.05 + sin(a) * 0.36, z)
		var head := Vector3(x + cos(a) * 0.74, -0.05 + sin(a) * 0.74, z)
		_rod(kit, Vector3(x + cos(a) * 0.3, -0.05 + sin(a) * 0.3, -3.42), foot + Vector3(0, 0, -0.06), 0.012, CASE.darkened(0.2), 5)
		_rod(kit, head + Vector3(0, 0, 0.1), Vector3(x + cos(a) * 0.30, -0.05 + sin(a) * 0.30, -2.86), 0.008, LEAD, 4)
	# Data plate.
	kit.box_at(Vector3(x, 0.10, -2.56), Vector3(0.10, 0.06, 0.008), Color(0.80, 0.78, 0.70))


## A removable part's geometry, in plane space.
static func part_kit(id: String) -> RefCounted:
	var kit = MeshKit.new()
	var bits := id.split("_", false, 1)
	var ei := int(bits[0].substr(1))
	var pid := bits[1]
	var x := nacelle_x(ei)
	if pid.begins_with("cyl_"):
		var n := int(pid.split("_")[1])
		var c := cyl_at(n)
		var a: float = c[0]
		var z: float = c[1]
		var dirv := Vector3(cos(a), sin(a), 0)
		var foot := Vector3(x, -0.05, z) + dirv * 0.34
		# Finned barrel and head, pointing out of the case.
		for k in range(5):
			_rod(kit, foot + dirv * (0.05 + 0.06 * k), foot + dirv * (0.07 + 0.06 * k), 0.125, CYL, 10)
		_rod(kit, foot, foot + dirv * 0.30, 0.095, CYL, 10)
		_rod(kit, foot + dirv * 0.30, foot + dirv * 0.42, 0.105, HEAD, 10)
		# Both plugs, top and bottom of the head.
		for s in [-1.0, 1.0]:
			var pp: Vector3 = foot + dirv * 0.38 + Vector3(-sin(a), cos(a), 0) * 0.09 * float(s)
			_rod(kit, pp, pp + Vector3(-sin(a), cos(a), 0) * 0.05 * float(s), 0.014, CERAMIC, 6)
	elif pid == "oil_filter":
		_rod(kit, Vector3(x - 0.42, -0.30, -2.70), Vector3(x - 0.42, -0.30, -2.56), 0.05, FILTER, 12)
	elif pid == "mag_l" or pid == "mag_r":
		var mx := x + (-0.18 if pid == "mag_l" else 0.18)
		_rod(kit, Vector3(mx, 0.24, -2.78), Vector3(mx, 0.24, -2.64), 0.055, BLACK, 10)
		_rod(kit, Vector3(mx, 0.24, -2.79), Vector3(mx, 0.24, -2.78), 0.06, Color(0.6, 0.1, 0.08), 10)
	elif pid == "air_filter":
		kit.box_at(Vector3(x, -0.64, -2.55), Vector3(0.30, 0.08, 0.22), Color(0.75, 0.15, 0.10))
	elif pid == "exhaust":
		# A section of the collector ring with the tailpipe stub.
		_rod(kit, Vector3(x + 0.50, -0.70, -3.00), Vector3(x + 0.58, -0.52, -2.68), 0.065, RUST, 10)
		_rod(kit, Vector3(x + 0.58, -0.52, -2.68), Vector3(x + 0.60, -0.58, -2.42), 0.055, RUST.lightened(0.1), 8)
	elif pid == "battery":
		kit.box_at(Vector3(x + 0.55, 0.28, -2.52), Vector3(0.20, 0.17, 0.13), BLACK)
		kit.box_at(Vector3(x + 0.50, 0.375, -2.52), Vector3(0.03, 0.02, 0.03), Color(0.7, 0.1, 0.1))
		kit.box_at(Vector3(x + 0.60, 0.375, -2.52), Vector3(0.03, 0.02, 0.03), BLACK.lightened(0.2))
	elif pid == "dipstick":
		_rod(kit, Vector3(x, 0.545, -2.44), Vector3(x, 0.57, -2.44), 0.028, Color(0.85, 0.75, 0.10), 8)
		kit.box_at(Vector3(x, 0.42, -2.44), Vector3(0.014, 0.26, 0.004), CASE)
	return kit


## Every removable part of engine `ei` as named children of `holder`.
static func build_removable(holder: Node3D, ei: int) -> void:
	var ids: Array = ["oil_filter", "mag_l", "mag_r", "air_filter", "exhaust", "dipstick"]
	if ei == 0:
		ids.append("battery")
	for n in range(1, 15):
		ids.append("cyl_%d" % n)
	for pid in ids:
		var id := "e%d_%s" % [ei, pid]
		holder.add_child((part_kit(id) as RefCounted).instance(id))
