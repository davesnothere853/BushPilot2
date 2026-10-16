extends RefCounted
## Winch / tow points on a machine (DESIGN_NOTES 225, Dave: every vehicle gets
## them, the winch hooks to the nearest one). Each point is a welded ear plate
## with a bow shackle through it: a real D-shackle (the bow, the pin across
## its jaws with the screw head and the eye), not a block.
##
## A list of points: [name, local position, out (which way a pull comes
## off it)], in the frame of the node they're built on (an articulated
## machine's front frame, an excavator's undercarriage...).

const MeshKit = preload("res://scripts/meshkit.gd")

const RED := Color(0.62, 0.10, 0.07)        # shackles painted red, so you find them
const PIN := Color(0.55, 0.55, 0.56)


## Build the hardware for `points` onto `node` (one mesh, "TowPoints"). `paint`
## is the ear plate's colour (the machine's own).
static func build(node: Node3D, points: Array, paint: Color, size: float = 1.0) -> void:
	var k := MeshKit.new()
	for p in points:
		ear(k, p[1], p[2], paint, size)
	var mi := k.instance("TowPoints")
	node.add_child(mi)


## The world positions: [[name, world point], ...].
static func world(node: Node3D, points: Array) -> Array:
	var out: Array = []
	if node == null or not node.is_inside_tree():
		return out
	for p in points:
		out.append([String(p[0]), node.global_transform * (p[1] as Vector3)])
	return out


## The one of `pts` ([[name, world]]) nearest `at`, or [] if none within `reach`.
static func nearest(pts: Array, at: Vector3, reach: float = 2.5) -> Array:
	var best: Array = []
	var bd := reach
	for p in pts:
		var d := (p[1] as Vector3).distance_to(at)
		if d < bd:
			bd = d
			best = p
	return best


## An ear plate welded on, standing out along `out`, with a D-shackle through
## its hole hanging off it.
static func ear(k: MeshKit, at: Vector3, out: Vector3, paint: Color, s: float = 1.0) -> void:
	var o := out.normalized()
	var side := Vector3.UP.cross(o)
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := o.cross(side).normalized()
	# the plate: vertical, in the plane of out and up, its end rounded off
	var b := Basis(side, up, o)
	k.box(Transform3D(b, at + o * 0.04 * s), Vector3(0.025 * s, 0.09 * s, 0.08 * s), paint)
	k.cylinder(Transform3D(b * Basis(Vector3.BACK, PI * 0.5), at + o * 0.08 * s + side * 0.0125 * s), 0.045 * s, 0.045 * s, 0.025 * s, 12, paint, true)
	# the hole's boss (a ring round the pin each side)
	for off in [0.0185, -0.0125]:
		k.cylinder(Transform3D(b * Basis(Vector3.BACK, PI * 0.5), at + o * 0.08 * s + side * float(off) * s), 0.024 * s, 0.024 * s, 0.006 * s, 10, paint.darkened(0.2), true)
	# the shackle: the pin across through the hole (head one side, eye nut the
	# other), the bow hanging down from its ends, round under the plate
	var pc := at + o * 0.08 * s
	var jaw := 0.032 * s
	k.cylinder(Transform3D(b * Basis(Vector3.BACK, PI * 0.5), pc + side * (jaw + 0.01 * s)), 0.008 * s, 0.008 * s, (jaw + 0.01 * s) * 2.0, 8, PIN, true)
	k.cylinder(Transform3D(b * Basis(Vector3.BACK, PI * 0.5), pc + side * (jaw + 0.018 * s)), 0.014 * s, 0.014 * s, 0.008 * s, 6, PIN, true)    # screw head
	# the eye on the other end (a little ring)
	var ec := pc - side * (jaw + 0.016 * s)
	for i in range(10):
		var a0 := TAU * float(i) / 10.0
		var a1 := TAU * float(i + 1) / 10.0
		_rod(k, ec + (up * cos(a0) + o * sin(a0)) * 0.012 * s, ec + (up * cos(a1) + o * sin(a1)) * 0.012 * s, 0.004 * s, PIN)
	# the bow: the two legs from the pin ends round under, a D
	var pts: Array = []
	for i in range(15):
		var t := float(i) / 14.0
		var a := PI * t
		pts.append(pc + side * cos(a) * jaw - up * sin(a) * 0.075 * s + o * sin(a) * 0.02 * s)
	for i2 in range(pts.size() - 1):
		_rod(k, pts[i2], pts[i2 + 1], 0.009 * s, RED)


static func _rod(k: MeshKit, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	k.cylinder(Transform3D(Basis(x, y, z), a), r, r, l, 6, col, true)
