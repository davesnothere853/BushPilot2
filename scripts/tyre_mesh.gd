extends RefCounted
## Tyres and steel wheels that look like the real thing (DESIGN_NOTES 116),
## still low-poly and flat-shaded:
##   the carcass   turned from a profile: bead, sidewall with its bulge,
##                 rounded shoulders, a crown a little under the tread
##   the tread     raised blocks that follow the curve of the crown -
##                 highway ribs, all-terrain blocks, mud lugs that run out
##                 over the shoulder and down the sidewall
##   the wheel     a steel rim turned from its profile too: the flange lip,
##                 the barrel, the dished centre, the hub, with slots or hand
##                 holes and hex nuts
## The axle is along X; the tyre's middle is at x = 0. `side` (+1 / -1) is
## which way is outboard (the face you see).
## Meshes are cached: every wheel of the same kind and side shares one.

const MeshKit = preload("res://scripts/meshkit.gd")

const RUBBER := Color(0.075, 0.075, 0.078)
const SIDEWALL := Color(0.11, 0.11, 0.115)
const SEGS := 56

static var _cache := {}


## The whole wheel: tyre(s) and rim, one mesh.
##   r: tyre radius; w: tread width; rim_r: rim radius; tread: highway / at /
##   mud / rib / lug / flot; rim: "slot" (8-slot steel), "disc" (truck disc
##   with hand holes); duals: [x offsets] (one tyre at 0, or a dual pair);
##   hub: "lock" for front locking hubs; rim_col: the wheel's paint.
static func wheel(r: float, w: float, rim_r: float, tread: String, rim: String, side: float, duals: Array = [0.0], hub: String = "", rim_col: Color = Color(0.85, 0.85, 0.82)) -> ArrayMesh:
	var key := "%.3f|%.3f|%.3f|%s|%s|%d|%s|%s|%s" % [r, w, rim_r, tread, rim, int(side), str(duals), hub, rim_col.to_html()]
	if _cache.has(key):
		return _cache[key]
	var k := MeshKit.new()
	for i in range(duals.size()):
		var dx: float = duals[i]
		_tyre(k, dx, r, w, rim_r, tread)
		# the rim of each tyre: the outer one of a dual pair shows its face; the
		# inner one's face is hidden behind it (just the barrel shows)
		var outer := duals.size() == 1 or (dx * side > 0.0)
		_rim(k, dx, w, rim_r, side, rim, outer, hub, rim_col)
	var m := k.commit()
	_cache[key] = m
	return m


# ------------------------------------------------------------------------------
#  The tyre
# ------------------------------------------------------------------------------
static func _p(cx: float, x: float, a: float, rr: float) -> Vector3:
	return Vector3(cx + x, sin(a) * rr, cos(a) * rr)


static func _lug_h(tread: String) -> float:
	match tread:
		"mud":
			return 0.024
		"lug":
			return 0.022
		"at":
			return 0.015
		"flot":
			return 0.012
		"tundra":
			return 0.004
	return 0.008


static func _tyre(k: MeshKit, cx: float, R: float, w: float, rim_r: float, tread: String) -> void:
	var lh := _lug_h(tread)
	var rc := R - lh                    # the crown under the tread
	var h := rc - rim_r
	var hw := w * 0.5
	# the profile, bead to bead over the crown: (x, radius)
	var prof: Array = [
		Vector2(-hw * 0.82, rim_r + 0.006),
		Vector2(-hw * 0.97, rim_r + h * 0.28),
		Vector2(-hw * 1.04, rim_r + h * 0.55),       # the bulge
		Vector2(-hw * 1.0, rim_r + h * 0.80),
		Vector2(-hw * 0.93, rc - h * 0.06),
		Vector2(-hw * 0.80, rc - 0.004),             # the shoulder
		Vector2(-hw * 0.45, rc),
		Vector2(hw * 0.45, rc),
		Vector2(hw * 0.80, rc - 0.004),
		Vector2(hw * 0.93, rc - h * 0.06),
		Vector2(hw * 1.0, rim_r + h * 0.80),
		Vector2(hw * 1.04, rim_r + h * 0.55),
		Vector2(hw * 0.97, rim_r + h * 0.28),
		Vector2(hw * 0.82, rim_r + 0.006),
	]
	if tread == "tundra":
		# a balloon tundra tyre: almost round in section, the sidewall bulging
		# well past the small rim, a smooth crown with fine ribs
		prof = []
		var cr := (rc - rim_r) * 0.5
		var cy := rim_r + cr
		for q in range(15):
			var a := lerpf(-PI * 0.80, PI * 0.80, float(q) / 14.0)
			prof.append(Vector2(sin(a) * hw * 1.02, cy + cos(a) * cr))
		prof[0] = Vector2(-hw * 0.55, rim_r + 0.006)
		prof[prof.size() - 1] = Vector2(hw * 0.55, rim_r + 0.006)
	var mid := Vector2(0.0, rim_r + h * 0.5)
	for i in range(SEGS):
		var a0 := TAU * float(i) / float(SEGS)
		var a1 := TAU * float(i + 1) / float(SEGS)
		for j in range(prof.size() - 1):
			var p0: Vector2 = prof[j]
			var p1: Vector2 = prof[j + 1]
			var hint2 := (p0 + p1) * 0.5 - mid
			var am := (a0 + a1) * 0.5
			var hint := Vector3(hint2.x, sin(am) * hint2.y, cos(am) * hint2.y)
			var crown: bool = absf(p0.x) < hw * 0.81 and absf(p1.x) < hw * 0.81
			var col := RUBBER if crown else SIDEWALL
			k.quad(_p(cx, p0.x, a0, p0.y), _p(cx, p1.x, a0, p1.y), _p(cx, p1.x, a1, p1.y), _p(cx, p0.x, a1, p0.y), col, hint)
	# the tread on the crown
	match tread:
		"tundra":
			pass       # smooth balloon crown
		"highway", "rib":
			_ribs(k, cx, rc, hw, lh)
		"at":
			_at_blocks(k, cx, rc, hw, lh, h)
		"flot":
			_flot_blocks(k, cx, rc, hw, lh)
		_:
			_mud_lugs(k, cx, rc, hw, lh, h, 14 if tread == "mud" else 18)


## A block of tread: from x0 to x1 across, a0 to a1 round, radius rb up to rt;
## `skew` turns it (the angle shifts across its width, for chevrons).
static func _block(k: MeshKit, cx: float, x0: float, x1: float, a0: float, a1: float, rb: float, rt: float, skew: float = 0.0, col: Color = RUBBER) -> void:
	var xm := (x0 + x1) * 0.5
	var sk0 := skew * (x0 - xm)
	var sk1 := skew * (x1 - xm)
	var c: Array = [
		_p(cx, x0, a0 + sk0, rb), _p(cx, x1, a0 + sk1, rb), _p(cx, x1, a1 + sk1, rb), _p(cx, x0, a1 + sk0, rb),
		_p(cx, x0, a0 + sk0, rt), _p(cx, x1, a0 + sk1, rt), _p(cx, x1, a1 + sk1, rt), _p(cx, x0, a1 + sk0, rt),
	]
	var ctr := Vector3.ZERO
	for v in c:
		ctr += v
	ctr /= 8.0
	var faces := [[4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	for f in faces:
		var fc: Vector3 = (c[f[0]] + c[f[1]] + c[f[2]] + c[f[3]]) * 0.25
		k.quad(c[f[0]], c[f[1]], c[f[2]], c[f[3]], col, fc - ctr)


## Highway: four ribs round the tyre with grooves between, siped across.
static func _ribs(k: MeshKit, cx: float, rc: float, hw: float, lh: float) -> void:
	var n := 40
	var edges := [-0.88, -0.47, -0.04, 0.04, 0.47, 0.88]
	var ribs := [[-0.88, -0.5], [-0.44, -0.04], [0.04, 0.44], [0.5, 0.88]]
	for i in range(n):
		var a0 := TAU * float(i) / float(n)
		var a1 := a0 + TAU / float(n) * 0.9
		for rb in ribs:
			_block(k, cx, float(rb[0]) * hw, float(rb[1]) * hw, a0, a1, rc - 0.003, rc + lh)


## All-terrain: three staggered rows of chunky blocks, the outer ones running
## onto the shoulder.
static func _at_blocks(k: MeshKit, cx: float, rc: float, hw: float, lh: float, h: float) -> void:
	var n := 22
	var step := TAU / float(n)
	for i in range(n):
		var a := step * float(i)
		# the middle row
		_block(k, cx, -0.26 * hw, 0.26 * hw, a + step * 0.5, a + step * 1.12, rc - 0.003, rc + lh, 0.6)
		for sd: float in [-1.0, 1.0]:
			var x0 := sd * 0.34 * hw
			var x1 := sd * 0.86 * hw
			_block(k, cx, minf(x0, x1), maxf(x0, x1), a, a + step * 0.66, rc - 0.003, rc + lh, -0.5 * sd)
			# a little way down the shoulder
			var s0 := sd * 0.86 * hw
			var s1 := sd * 1.0 * hw
			_block(k, cx, minf(s0, s1), maxf(s0, s1), a + step * 0.08, a + step * 0.56, rc - h * 0.12, rc + lh * 0.5)


## Mud: big, widely spaced lugs, staggered side to side and angled into a
## chevron, that run out over the shoulder and down the sidewall.
static func _mud_lugs(k: MeshKit, cx: float, rc: float, hw: float, lh: float, h: float, n: int) -> void:
	var step := TAU / float(n)
	for i in range(n):
		for sd: float in [-1.0, 1.0]:
			var a := step * float(i) + (step * 0.5 if sd > 0.0 else 0.0)
			var x0 := sd * 0.06 * hw
			var x1 := sd * 0.92 * hw
			_block(k, cx, minf(x0, x1), maxf(x0, x1), a, a + step * 0.42, rc - 0.004, rc + lh, 0.9 * sd)
			# the shoulder lug, down the sidewall
			var s0 := sd * 0.88 * hw
			var s1 := sd * 1.06 * hw
			var skew_end := 0.9 * sd * (x1 - (x0 + x1) * 0.5)
			_block(k, cx, minf(s0, s1), maxf(s0, s1), a + skew_end * 0.9, a + skew_end * 0.9 + step * 0.36, rc - h * 0.22, rc + lh * 0.6)


## Flotation: lots of low, wide blocks.
static func _flot_blocks(k: MeshKit, cx: float, rc: float, hw: float, lh: float) -> void:
	var n := 26
	var step := TAU / float(n)
	for i in range(n):
		for row in range(4):
			var x0 := (-0.9 + 0.46 * float(row)) * hw
			var a := step * float(i) + (step * 0.5 if row % 2 == 1 else 0.0)
			_block(k, cx, x0, x0 + 0.4 * hw, a, a + step * 0.7, rc - 0.003, rc + lh)


# ------------------------------------------------------------------------------
#  The wheel
# ------------------------------------------------------------------------------
## A turned surface from a profile, one-sided: `hints` gives, per segment of
## the profile, which way its face looks ((x, radial) in the profile's plane).
static func _lathe(k: MeshKit, cx: float, prof: Array, hints: Array, col: Color, segs: int = SEGS) -> void:
	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var am := (a0 + a1) * 0.5
		for j in range(prof.size() - 1):
			var p0: Vector2 = prof[j]
			var p1: Vector2 = prof[j + 1]
			var h2: Vector2 = hints[mini(j, hints.size() - 1)]
			var hint := Vector3(h2.x, sin(am) * h2.y, cos(am) * h2.y)
			k.quad(_p(cx, p0.x, a0, p0.y), _p(cx, p1.x, a0, p1.y), _p(cx, p1.x, a1, p1.y), _p(cx, p0.x, a1, p0.y), col, hint)


static func _rim(k: MeshKit, cx: float, w: float, rim_r: float, side: float, style: String, outer: bool, hub: String, col: Color) -> void:
	var hw := w * 0.5
	var sd := side
	var dark := Color(0.05, 0.05, 0.05)
	var steel := col
	# the rim: inner flange, barrel, outer flange
	var lip := 0.022
	var barrel: Array = [
		Vector2(-sd * hw * 0.9, rim_r + lip),
		Vector2(-sd * hw * 0.84, rim_r + 0.004),
		Vector2(-sd * hw * 0.8, rim_r - 0.012),
		Vector2(sd * hw * 0.8, rim_r - 0.012),
		Vector2(sd * hw * 0.84, rim_r + 0.004),
		Vector2(sd * hw * 0.9, rim_r + lip),
	]
	# seen from outboard: the lip faces out, the barrel inside it faces the axle
	_lathe(k, cx, barrel, [Vector2(-sd * 0.4, 1.0), Vector2(-sd * 0.2, -1.0), Vector2(0.0, -1.0), Vector2(sd * 0.2, -1.0), Vector2(sd * 0.6, 1.0)], steel if outer else steel.darkened(0.35))
	if not outer:
		return
	# the centre: dished in from the outer flange to the hub
	var face_x := sd * hw * 0.35
	var hub_r := rim_r * 0.42
	var centre: Array
	if style == "disc":
		# a truck disc: flat, close to the outer face, then the hub boss
		centre = [
			Vector2(sd * hw * 0.8, rim_r - 0.012),
			Vector2(sd * hw * 0.55, rim_r - 0.03),
			Vector2(sd * hw * 0.5, hub_r + 0.02),
			Vector2(sd * hw * 0.62, hub_r),
			Vector2(sd * hw * 0.72, hub_r * 0.6),
			Vector2(sd * hw * 0.74, 0.0),
		]
	else:
		# a pressed steel wheel: dished well in, a raised ring, the hub
		centre = [
			Vector2(sd * hw * 0.8, rim_r - 0.012),
			Vector2(face_x, rim_r - 0.03),
			Vector2(face_x * 0.6, rim_r * 0.72),
			Vector2(face_x * 0.75, rim_r * 0.62),
			Vector2(face_x * 0.5, hub_r + 0.012),
			Vector2(face_x * 0.75, hub_r * 0.75),
			Vector2(face_x * 0.95, hub_r * 0.55),
			Vector2(face_x * 0.95, 0.0),
		]
	_lathe(k, cx, centre, [Vector2(sd, 0.0)], steel)
	# hub cap / centre
	var cap_x := cx + (centre[centre.size() - 1] as Vector2).x
	var tb := Basis(Vector3.BACK, -PI * 0.5 * sd)     # cylinders grow outboard from where they start
	if hub == "lock":
		# a front locking hub: a chunky dial sticking out
		k.cylinder(Transform3D(tb, Vector3(cap_x, 0, 0)), 0.06, 0.055, 0.045, 12, Color(0.7, 0.71, 0.72))
		k.box_at(Vector3(cap_x + sd * 0.047, 0, 0), Vector3(0.008, 0.075, 0.018), Color(0.25, 0.25, 0.26))
	else:
		k.cylinder(Transform3D(tb, Vector3(cap_x, 0, 0)), hub_r * 0.55, hub_r * 0.45, 0.025, 12, steel.darkened(0.15))
	# nuts on a circle round the hub: hex
	var nuts := 10 if style == "disc" else 8
	var nut_r := hub_r * (0.75 if style == "disc" else 0.82)
	var nut_x := cx + (sd * hw * 0.62 if style == "disc" else face_x * 0.5)
	for i in range(nuts):
		var na := TAU * float(i) / float(nuts)
		k.cylinder(Transform3D(tb, Vector3(nut_x, sin(na) * nut_r, cos(na) * nut_r)), 0.018, 0.016, 0.03, 6, Color(0.62, 0.63, 0.64))
	# slots or hand holes, dark, in the dish
	if style == "disc":
		var holes := 5
		for i in range(holes):
			var ha := TAU * (float(i) + 0.5) / float(holes)
			var hr := (rim_r + hub_r) * 0.52
			k.cylinder(Transform3D(tb, Vector3(cx + sd * hw * 0.52, sin(ha) * hr, cos(ha) * hr)), 0.045, 0.045, 0.006, 10, dark)
	else:
		for i in range(8):
			var sa := TAU * (float(i) + 0.5) / 8.0
			var sr := rim_r * 0.82
			var bx := Basis(Vector3.RIGHT, -sa)
			k.box(Transform3D(bx, Vector3(cx + face_x * 0.72, sin(sa) * sr, cos(sa) * sr)), Vector3(0.01, 0.024, 0.06), dark)
