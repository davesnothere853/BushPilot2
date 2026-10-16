extends RefCounted
## The DC-3's cabin, inside: the skin with its windows and the cargo door
## opening, the frames, the floor (level, then rising toward the tail), the
## bulkhead to the flight deck with its doorway, the aft wall, fold-down
## aluminium troop benches along both walls, tie-down rails and dome lights.
## Built under the flight deck node (dc3_cockpit.gd), in the plane's space.

const MeshKit = preload("res://scripts/meshkit.gd")
const Pbr = preload("res://scripts/pbr.gd")
const Shape = preload("res://scripts/dc3_shape.gd")

const INTERIOR := Color(0.52, 0.57, 0.52)
const INTERIOR_DK := Color(0.33, 0.36, 0.33)
const CHROMATE := Color(0.50, 0.56, 0.38)      # zinc-chromate primer on the frames
const ALU := Color(0.62, 0.63, 0.64)
const FLOOR := Color(0.36, 0.37, 0.36)
const INSET := 0.07
const BENCH_Z := [-3.95, 1.65]


static func build(parent: Node3D) -> void:
	var skin := MeshKit.new()
	var frames := MeshKit.new()
	var floor_k := MeshKit.new()
	var metal := MeshKit.new()
	_skin(skin)
	_reveals(frames)
	_frames(frames)
	_bulkhead(skin, frames)
	_aft_wall(skin)
	_floor(floor_k, metal)
	_benches(metal)
	_lamps(parent, metal)
	_add(parent, skin, Pbr.painted(), "CabinSkin")
	_add(parent, frames, Pbr.paint_smooth(), "CabinFrames")
	_add(parent, floor_k, Pbr.floor_mat(), "CabinFloor")
	_add(parent, metal, Pbr.metal(), "CabinMetal")


static func _add(parent: Node3D, kit: RefCounted, mat: Material, node_name: String) -> void:
	var mi: MeshInstance3D = kit.instance(node_name)
	mi.material_override = mat
	parent.add_child(mi)


## The inside of the skin from the bulkhead to the aft wall, round the holes.
static func _skin(kit: RefCounted) -> void:
	var zs: Array[float] = []
	var z: float = Shape.BULKHEAD_Z
	while z < Shape.AFT_Z:
		zs.append(z)
		z += 0.35
	zs.append(Shape.AFT_Z)
	for hz in Shape.hole_breaks():
		zs.append(hz)
	zs.sort()
	var nr := Shape.ring_size()
	for zi in range(zs.size() - 1):
		var z0: float = zs[zi]
		var z1: float = zs[zi + 1]
		if z1 - z0 < 0.001:
			continue
		var r0: PackedFloat32Array = Shape.ring_angles(z0, INSET)
		var r1: PackedFloat32Array = Shape.ring_angles(z1, INSET)
		var fy := minf(Shape.cabin_floor(z0), Shape.cabin_floor(z1))
		for k in range(nr):
			var k1 := (k + 1) % nr
			var hi0: float = r0[k1] if k1 > 0 else r0[0] + TAU
			var hi1: float = r1[k1] if k1 > 0 else r1[0] + TAU
			var top := maxf(Shape.point(r0[k], z0, INSET).y, Shape.point(hi0, z0, INSET).y)
			if top < fy - 0.02:
				continue
			var mid_y := (Shape.point(r0[k], z0, INSET).y + Shape.point(hi0, z0, INSET).y) * 0.5
			var col := INTERIOR if mid_y > -0.2 else INTERIOR_DK
			Shape.skin_quad(kit, z0, z1, r0[k], hi0, r1[k], hi1, INSET, col, false)


## The sides of each window and the door opening, from the skin to the lining.
static func _reveals(kit: RefCounted) -> void:
	for h in Shape.cabin_holes():
		var side: float = h[0]
		var z0: float = h[1]
		var z1: float = h[2]
		var r: Vector2 = Shape.hole_ring_range(h)
		var n := 6
		# Top and bottom edges (along z), then the front and back edges (round).
		for a in [r.x, r.y]:
			for i in range(n):
				var za := lerpf(z0, z1, float(i) / n)
				var zb := lerpf(z0, z1, float(i + 1) / n)
				_reveal_quad(kit, a, za, a, zb)
		for zz in [z0, z1]:
			for i in range(n):
				var aa := lerpf(r.x, r.y, float(i) / n)
				var ab := lerpf(r.x, r.y, float(i + 1) / n)
				_reveal_quad(kit, aa, zz, ab, zz)
		# A frame round the window, just proud of the lining.
		if String(h[5]) == "win":
			var c := (Shape.point(r.x, z0, INSET) + Shape.point(r.y, z1, INSET)) * 0.5
			var inward := Vector3(-side, 0, 0)
			var corners := [Shape.point(r.x, z0, INSET + 0.005), Shape.point(r.y, z0, INSET + 0.005),
				Shape.point(r.y, z1, INSET + 0.005), Shape.point(r.x, z1, INSET + 0.005)]
			for i in range(4):
				var p: Vector3 = corners[i]
				var q: Vector3 = corners[(i + 1) % 4]
				var po: Vector3 = p + (p - c).normalized() * 0.045
				var qo: Vector3 = q + (q - c).normalized() * 0.045
				kit.quad(p, q, qo, po, INTERIOR_DK, inward)


static func _reveal_quad(kit: RefCounted, a0: float, z0: float, a1: float, z1: float) -> void:
	var o0 := Shape.point(a0, z0, 0.0)
	var o1 := Shape.point(a1, z1, 0.0)
	var i0 := Shape.point(a0, z0, INSET)
	var i1 := Shape.point(a1, z1, INSET)
	# Faces into the hole: toward the hole's middle, which we don't know here,
	# so draw both sides.
	var n := (o1 - o0).cross(i0 - o0)
	kit.quad(o0, o1, i1, i0, INTERIOR_DK, n)
	kit.quad(o0, o1, i1, i0, INTERIOR_DK, -n)


## Frames between the windows: channels standing in from the lining, broken
## at the cargo door.
static func _frames(kit: RefCounted) -> void:
	var fzs: Array[float] = []
	var z := -3.35 - 0.475
	while z < Shape.AFT_Z - 0.2:
		fzs.append(z)
		z += 0.95
	for fz in fzs:
		var ra: PackedFloat32Array = Shape.ring_angles(fz, INSET)
		var fy: float = Shape.cabin_floor(fz)
		var nr := ra.size()
		for k in range(nr):
			var k1 := (k + 1) % nr
			var lo: float = ra[k]
			var hi: float = ra[k1] if k1 > 0 else ra[0] + TAU
			for sp in Shape.keep_spans(lo, hi, fz):
				var s: Vector2 = sp
				var o0 := Shape.point(s.x, fz, INSET)
				var o1 := Shape.point(s.y, fz, INSET)
				if maxf(o0.y, o1.y) < fy:
					continue
				var i0 := Shape.point(s.x, fz, INSET + 0.06)
				var i1 := Shape.point(s.y, fz, INSET + 0.06)
				var dz := Vector3(0, 0, 0.022)
				var inn := Vector3(0, float(Shape.section(fz)[3]), fz) - (o0 + o1) * 0.5
				kit.quad(o0 - dz, o1 - dz, i1 - dz, i0 - dz, CHROMATE, Vector3.FORWARD)
				kit.quad(o0 + dz, o1 + dz, i1 + dz, i0 + dz, CHROMATE, Vector3.BACK)
				kit.quad(i0 - dz, i1 - dz, i1 + dz, i0 + dz, CHROMATE, inn)


## The bulkhead between the flight deck and the cabin: solid below the flight
## deck floor (the step up), a doorway 0.64 m wide above it.
static func _bulkhead(kit: RefCounted, frames: RefCounted) -> void:
	var bz: float = Shape.BULKHEAD_Z
	var deck: float = Shape.cabin_floor(bz - 0.01)
	var top_door := 1.12
	var dh: float = Shape.DOORWAY_HALF
	var ys: Array[float] = []
	var y := -1.0
	while y < 1.55:
		ys.append(y)
		y += 0.08
	ys.append(deck)
	ys.append(top_door)
	ys.sort()
	for i in range(ys.size() - 1):
		var y0: float = ys[i]
		var y1: float = ys[i + 1]
		var w0 := Shape.inner_half_width(bz, y0) + 0.01
		var w1 := Shape.inner_half_width(bz, y1) + 0.01
		if w0 < 0.01 and w1 < 0.01:
			continue
		var door := y0 >= deck - 0.001 and y1 <= top_door + 0.001
		var spans: Array = [[-w0, -w1, w0, w1]] if not door else [[-w0, -w1, -dh, -dh], [dh, dh, w0, w1]]
		for sp in spans:
			var a := Vector3(sp[0], y0, bz)
			var b := Vector3(sp[2], y0, bz)
			var c := Vector3(sp[3], y1, bz)
			var d := Vector3(sp[1], y1, bz)
			# Cabin face (seen from behind) and flight-deck face (above its floor).
			kit.quad(a + Vector3(0, 0, 0.02), b + Vector3(0, 0, 0.02), c + Vector3(0, 0, 0.02), d + Vector3(0, 0, 0.02), INTERIOR, Vector3.BACK)
			if y0 >= deck - 0.001:
				kit.quad(a, b, c, d, INTERIOR, Vector3.FORWARD)
	# Door frame (both sides) and a step plate at the sill.
	for side in [-1.0, 1.0]:
		_post(frames, Vector3(side * (dh + 0.03), deck, bz + 0.01), Vector3(side * (dh + 0.03), top_door + 0.03, bz + 0.01))
	_post(frames, Vector3(-dh - 0.03, top_door + 0.03, bz + 0.01), Vector3(dh + 0.03, top_door + 0.03, bz + 0.01))
	frames.box_at(Vector3(0, deck - 0.01, bz + 0.03), Vector3(dh * 2.0 + 0.1, 0.03, 0.08), ALU)
	# A step up from the cabin floor.
	frames.box_at(Vector3(0, -0.89, bz + 0.16), Vector3(0.72, 0.22, 0.30), INTERIOR_DK)
	frames.box_at(Vector3(0, -0.777, bz + 0.16), Vector3(0.72, 0.006, 0.30), ALU)


static func _post(kit: RefCounted, a: Vector3, b: Vector3) -> void:
	var c := (a + b) * 0.5
	var size := (b - a).abs() + Vector3(0.06, 0.06, 0.05)
	kit.box_at(c, size, INTERIOR_DK)


## The aft wall (bulkhead to the tail cone), with a door to the toilet aft.
static func _aft_wall(kit: RefCounted) -> void:
	var az: float = Shape.AFT_Z
	var fy: float = Shape.cabin_floor(az)
	var y := fy
	while y < 1.4:
		var y1 := minf(y + 0.08, 1.4)
		var w0 := Shape.inner_half_width(az, y) + 0.02
		var w1 := Shape.inner_half_width(az, y1) + 0.02
		if w0 > 0.01 or w1 > 0.01:
			kit.quad(Vector3(-w0, y, az), Vector3(w0, y, az), Vector3(w1, y1, az), Vector3(-w1, y1, az), INTERIOR, Vector3.FORWARD)
		y = y1
	kit.box_at(Vector3(0.0, fy + 0.85, az - 0.012), Vector3(0.56, 1.6, 0.02), INTERIOR_DK)
	kit.box_at(Vector3(0.20, fy + 0.95, az - 0.03), Vector3(0.05, 0.03, 0.04), ALU)


## Floor: level from the bulkhead to the door, then rising to the aft wall,
## with tie-down rails and rings.
static func _floor(kit: RefCounted, metal: RefCounted) -> void:
	var z: float = Shape.BULKHEAD_Z
	while z < Shape.AFT_Z - 0.001:
		var z1 := minf(z + 0.25, Shape.AFT_Z)
		var f0: float = Shape.cabin_floor(maxf(z, Shape.BULKHEAD_Z + 0.32))
		var f1: float = Shape.cabin_floor(maxf(z1, Shape.BULKHEAD_Z + 0.32))
		var w0 := Shape.inner_half_width(z, f0 + 0.01) + 0.05
		var w1 := Shape.inner_half_width(z1, f1 + 0.01) + 0.05
		kit.quad(Vector3(-w0, f0, z), Vector3(w0, f0, z), Vector3(w1, f1, z1), Vector3(-w1, f1, z1), FLOOR, Vector3.UP)
		z = z1
	for rx in [-0.78, 0.0, 0.78]:
		var zz := Shape.BULKHEAD_Z + 0.4
		while zz < Shape.AFT_Z - 0.4:
			var fy: float = Shape.cabin_floor(zz)
			if absf(rx) > 0.1:
				metal.box_at(Vector3(rx, fy + 0.006, zz + 0.3), Vector3(0.05, 0.012, 0.6), ALU.darkened(0.15))
			else:
				metal.box_at(Vector3(rx, fy + 0.008, zz), Vector3(0.07, 0.016, 0.07), ALU.darkened(0.3))
			zz += 0.6


## Fold-down aluminium troop benches along each wall: bucket seats on tube legs.
static func _benches(metal: RefCounted) -> void:
	for side in [-1.0, 1.0]:
		var z: float = BENCH_Z[0]
		while z < BENCH_Z[1] - 0.001:
			var z1 := minf(z + 0.7, BENCH_Z[1])
			if side < 0.0 and z1 > Shape.DOOR_Z[0] - 0.1:
				break
			var zm := (z + z1) * 0.5
			var fy: float = Shape.cabin_floor(zm)
			var seat_y := fy + 0.43
			var wall := Shape.inner_half_width(zm, seat_y) - 0.02
			# Seat pan (dished: two slanted plates) and a back strip on the wall.
			var x_in: float = (wall - 0.38) * side
			var x_out: float = wall * side
			metal.box_at(Vector3((x_in + x_out) * 0.5, seat_y, zm), Vector3(0.38, 0.025, z1 - z - 0.04), ALU)
			metal.box_at(Vector3(x_in, seat_y + 0.02, zm), Vector3(0.025, 0.05, z1 - z - 0.04), ALU.darkened(0.1))
			var back_x: float = (Shape.inner_half_width(zm, seat_y + 0.35) - 0.04) * side
			metal.box_at(Vector3(back_x, seat_y + 0.33, zm), Vector3(0.025, 0.36, z1 - z - 0.04), ALU.darkened(0.08))
			# Legs.
			for lz in [z + 0.08, z1 - 0.08]:
				metal.box_at(Vector3(x_in + side * 0.04, (fy + seat_y) * 0.5, lz), Vector3(0.025, seat_y - fy, 0.025), ALU.darkened(0.2))
			z = z1


static func _lamps(parent: Node3D, metal: RefCounted) -> void:
	for lz in [-3.2, 0.4, 4.2]:
		var top: float = float(Shape.section(lz)[3]) + float(Shape.section(lz)[2]) - INSET - 0.05
		metal.box_at(Vector3(0, top, lz), Vector3(0.16, 0.04, 0.16), Color(0.95, 0.92, 0.80))
		var l := OmniLight3D.new()
		l.position = Vector3(0, top - 0.15, lz)
		l.light_energy = 0.55
		l.light_color = Color(1.0, 0.92, 0.78)
		l.omni_range = 3.8
		l.shadow_enabled = false
		parent.add_child(l)
