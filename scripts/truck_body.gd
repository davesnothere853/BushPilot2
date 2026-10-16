extends RefCounted
## The pickup's body, built in code (DESIGN_NOTES 191) - a generic late-'80s
## full-size work truck, extended cab, 8 ft bed, no maker's names. Smooth,
## curved panels lofted from cross-sections (a real beltline, a sloped nose,
## wheel arches with flares, flush raked glass, a rounded roof), but crisp:
## the character lines keep a hard edge.
##
## Same parts and frame as the old Blender body (pickup_body.glb) so the truck
## code is unchanged: Body, Hood, Tailgate, SteeringWheel, AxleF, AxleR and the
## *Bulb lamps. Frame: x right, y up (ground 0, wheel centres 0.4175), -z front.
##
## Every shape number is in tools/tune.cfg [pickup] so it can be reshaped live
## in the Model Lab (the lab rebuilds it when the file changes).

const MeshKit = preload("res://scripts/meshkit.gd")
const Tune = preload("res://scripts/tune.gd")

const AXLE_Y := 0.4175
const FZ := -1.72          # (pickup_truck: square body, 131.5 in wheelbase)
static var RZ := 1.62          # rear axle: set by the body style (_read)
## Body styles (DESIGN_NOTES 202) - the same truck, front end, cab and doors:
## "pickup" (8 ft bed, 131.5 in), "blazer" (2-door, 106.5 in, removable top),
## "suburban" (4-door, 129.5 in, long roof).
static var style := "pickup"
const STYLES := {
	"pickup": {"wb": 3.34, "tail": 2.87},
	"blazer": {"wb": 2.705, "tail": 2.00},
	"suburban": {"wb": 3.29, "tail": 2.86},
}


static func suv() -> bool:
	return style != "pickup"

## Factory-style two-tone schemes (body, band, roof) - after the '70s-'80s
## square-body photos Dave picked (blue with a white band and roof).
const SCHEMES := {
	"blue": [Color(0.15, 0.27, 0.52), Color(0.85, 0.84, 0.79), Color(0.87, 0.86, 0.82)],
	"red": [Color(0.50, 0.10, 0.08), Color(0.85, 0.84, 0.79), Color(0.87, 0.86, 0.82)],
	"green": [Color(0.20, 0.30, 0.21), Color(0.80, 0.76, 0.63), Color(0.80, 0.76, 0.63)],
	"tan": [Color(0.42, 0.30, 0.19), Color(0.72, 0.62, 0.45), Color(0.72, 0.62, 0.45)],
	"orange": [Color(0.70, 0.33, 0.12), Color(0.86, 0.84, 0.78), Color(0.86, 0.84, 0.78)],
	"black": [Color(0.06, 0.06, 0.07), Color(0.62, 0.62, 0.60), Color(0.06, 0.06, 0.07)],
	"yellow": [Color(0.78, 0.62, 0.18), Color(0.86, 0.84, 0.78), Color(0.86, 0.84, 0.78)],
}

static var P := {}          # this build's tuned numbers


static func t(key: String, default: Variant) -> Variant:
	return Tune.v("pickup", key, default)


static func _read() -> void:
	Tune.poll(1.0)
	var sc: Array = SCHEMES.get(String(t("scheme", "blue")), SCHEMES["blue"])
	P = {
		"paint": t("paint", sc[0]), "paint2": t("paint2", sc[1]), "roof_col": t("roof_col", sc[2]),
		"crease_y": t("crease_y", 1.10), "arch_len": t("arch_len", 0.50), "arch_top": t("arch_top", 0.86),
		"arch_corner": t("arch_corner", 0.16),
		"two_tone": t("two_tone", true), "tone_lo": t("tone_lo", 0.60), "tone_hi": t("tone_hi", 0.92),
		"w": t("half_width", 1.0), "nose_z": t("nose_z", -2.64), "tail_z": t("tail_z", 3.13),
		"nose_y": t("nose_y", 1.06), "hood_y": t("hood_y", 1.25), "cowl_y": t("cowl_y", 1.38),
		"belt_y": t("belt_y", 1.38), "rail_y": t("rail_y", 1.31), "roof_y": t("roof_y", 1.93),
		"rocker_y": t("rocker_y", 0.56), "arch_r": t("arch_r", 0.52), "flare": t("flare", 0.045),
		"cowl_z": t("cowl_z", -1.32), "glass_top_z": t("glass_top_z", -0.70), "cab_back_z": t("cab_back_z", 0.24),
		"bed_z": t("bed_z", 0.31), "tumble": t("tumblehome", 0.13), "nose_round": t("nose_round", 0.10),
		"bulge": t("bulge", 0.018), "nose_span": t("nose_span", 0.16), "dust": t("dust", 0.28), "bed_bottom": t("bed_bottom", 0.61), "roof_thick": t("roof_thick", 0.10), "glass": t("glass", Color(0.05, 0.07, 0.09, 0.78)),
	}
	var st: Dictionary = STYLES[style]
	RZ = FZ + float(st["wb"])
	if style != "pickup":
		P["tail_z"] = float(st["tail"])
		P["rail_y"] = P["belt_y"]                   # the body side runs at the beltline to the back
	P["rear_door"] = Vector2(float(P["cab_back_z"]) + 0.025, float(P["cab_back_z"]) + 0.88)   # suburban's back doors


static func build(body_style: String = "") -> Node3D:
	style = body_style if STYLES.has(body_style) else String(t("body", "pickup"))
	if not STYLES.has(style):
		style = "pickup"
	_read()
	# (DESIGN_NOTES 197) built with real detail: round parts with many sides,
	# every small box with rounded edges - not literal low poly
	var keep_detail: float = MeshKit.detail
	var keep_bevel: float = MeshKit.bevel
	MeshKit.detail = float(t("detail", 3.0))
	MeshKit.bevel = float(t("bevel", 0.006))
	var root := Node3D.new()
	root.name = "Body"
	var paint := MeshKit.new()
	var black := MeshKit.new()
	var chrome := MeshKit.new()
	var glass := MeshKit.new()
	var inside := MeshKit.new()
	# every component is its own part (DESIGN_NOTES 197): the section builders
	# below call _sw("Name") at each component, and what was drawn so far goes
	# into its own node
	_root = root
	_cur = ""
	_K = {"paint": paint, "black": black, "chrome": chrome, "glass": glass, "inside": inside}
	_sides(paint)
	_front_clip(paint, black)
	_greenhouse(paint, glass)
	_bed(paint, black)
	_flares(black)
	_front_end(chrome, black, glass, root)
	_rear_end(chrome, black, glass, root)
	_details(paint, black, chrome)
	_underside(black, chrome)
	_drivetrain(black, chrome)
	_mechanical(black, chrome)
	_interior(inside)
	_flush()
	_cur = ""
	# the spare: the same tyre and wheel as on the truck, tread and all
	var sp := root.get_node_or_null("SpareTire") as Node3D
	if sp != null:
		var smi := MeshInstance3D.new()
		smi.name = "Tyre"
		smi.mesh = TyreMesh.wheel(0.33, 0.20, 0.17, "at", "slot", 1.0, [0.0], "", Color(0.80, 0.80, 0.78))   # a smaller spare, tucked up out of sight
		smi.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), _spare_at)
		sp.add_child(smi)
	_hood(root)
	if bool(t("xray", false)):
		# the Model Lab: hood off to look at the engine bay (tune.cfg xray = true)
		var hd := root.get_node_or_null("Hood")
		if hd != null:
			hd.visible = false
	_tailgate(root)
	_doors(root)
	_steering_wheel(root)
	_axles(root)
	_suspension(root)
	MeshKit.detail = keep_detail
	MeshKit.bevel = keep_bevel
	return root


static var _root: Node3D
static var _cur := ""
static var _cur_chassis := false
static var _K := {}
static var _spare_at := Vector3.ZERO
const TyreMesh = preload("res://scripts/tyre_mesh.gd")
## Parts that are running gear (the test bed's chassis view keeps these).
const CHASSIS := ["FrameRails", "Crossmembers", "SpringHangers", "SteeringBox", "SwayBar", "Exhaust", "SpareTire",
	"FuelTank", "Engine", "AirCleaner", "FanAndPump", "Alternator", "Battery", "Transmission", "TransferCase", "Radiator"]


## Start the next component: what's been drawn goes into the one before.
static func _sw(nm: String) -> void:
	_flush()
	_cur = nm


static func _flush() -> void:
	if _cur == "" or _K.is_empty():
		return
	var any := false
	for r in _K.values():
		if not (r as RefCounted).is_empty():
			any = true
	if not any:
		return
	var n := _root.get_node_or_null(NodePath(_cur)) as Node3D
	if n == null:
		n = Node3D.new()
		n.name = _cur
		n.set_meta("part", true)
		n.set_meta("chassis", CHASSIS.has(_cur))
		_root.add_child(n)
	var paint: RefCounted = _K["paint"]
	_tone(paint)
	paint.smooth(34.0)
	(_K["black"] as RefCounted).smooth(40.0)
	(_K["chrome"] as RefCounted).smooth(50.0)
	(_K["glass"] as RefCounted).smooth(40.0)
	(_K["inside"] as RefCounted).smooth(40.0)
	_add(n, paint, "Paint", _paint_mat())
	_add(n, _K["black"], "Trim", _mat(Color.WHITE, 0.6, 0.0, true))
	_add(n, _K["chrome"], "Chrome", _mat(Color.WHITE, 0.16, 1.0, true))
	_add(n, _K["inside"], "Interior", _mat(Color.WHITE, 0.85, 0.0, true))
	_add(n, _K["glass"], "Glass", _glass_mat())
	for r in _K.values():
		(r as RefCounted).clear()


## How far the cab (seat, wheel, gauges, eye) sits back of where it was first
## built (cowl at -1.32): the side photo put the cowl 0.74 m behind the front
## axle (DESIGN_NOTES 198).
static func cab_dz() -> float:
	return float(P["cowl_z"]) + 1.32


## The driver (seat, wheel, gauges, eye) moves back a little less than the cab
## does: in a regular cab the seat back sits against the back wall.
static func driver_dz() -> float:
	return cab_dz() - 0.20


## The engine's middle, fore-aft: just ahead of the firewall.
static func engine_z() -> float:
	return float(P["cowl_z"]) - 0.60


## Where the doors are, fore and aft: from just behind the front wheel opening
## to just ahead of the cab's back corner.
static func door_z() -> Vector2:
	return Vector2(float(P["cowl_z"]) - 0.05, float(P["cab_back_z"]) - 0.10)


static func _glass_mat() -> StandardMaterial3D:
	var gm := _mat(P["glass"], 0.02, 0.0, false)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.metallic_specular = 1.0
	return gm


# ------------------------------------------------------------------------------
#  Materials
# ------------------------------------------------------------------------------
static var _peel: NoiseTexture2D
const PAINT_SHADER := preload("res://shaders/truck_paint.gdshader")
static func _paint_mat() -> Material:
	# the paint shader (DESIGN_NOTES 206): bands per pixel, by height
	if _peel == null:
		var fn := FastNoiseLite.new()
		fn.frequency = 0.05
		fn.fractal_octaves = 3
		_peel = NoiseTexture2D.new()
		_peel.width = 256
		_peel.height = 256
		_peel.seamless = true
		_peel.as_normal_map = true
		_peel.bump_strength = 2.0
		_peel.noise = fn
	var m := ShaderMaterial.new()
	m.shader = PAINT_SHADER
	m.set_shader_parameter("paint_a", P["paint"])
	m.set_shader_parameter("paint_b", P["paint2"])
	m.set_shader_parameter("two_tone", bool(P["two_tone"]))
	m.set_shader_parameter("tone_lo", float(P["tone_lo"]))
	m.set_shader_parameter("tone_hi", float(P["tone_hi"]))
	m.set_shader_parameter("dust", float(P.get("dust", 0.28)))
	m.set_shader_parameter("rough", float(t("paint_rough", 0.30)))
	m.set_shader_parameter("ripple", _peel)
	m.set_shader_parameter("ripple_k", float(t("peel", 0.12)))
	return m


static func _mat(col: Color, rough: float, metal: float, vcol: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if vcol:
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
	return m


static func _add(root: Node3D, kit: RefCounted, nm: String, m: Material) -> MeshInstance3D:
	if kit.is_empty():
		return null
	var mi: MeshInstance3D = kit.instance(nm)
	mi.material_override = m
	root.add_child(mi, true)
	return mi


# ------------------------------------------------------------------------------
#  Shape helpers
# ------------------------------------------------------------------------------
## The bottom edge of the side panels at z: the rocker, cut up round each wheel.
## Half length of a wheel opening: the front one is longer (room for the
## tyre to steer without the tread touching the back edge).
static func _alen(az: float) -> float:
	return float(P["arch_len"]) + (float(t("arch_front_extra", 0.06)) if az < 0.0 else 0.0)


static func _bottom(z: float, base: float) -> float:
	# square-body wheel openings, from the side photos (an '85 K10, an '83 K20,
	# a '77 C10 and a '77 C20 - DESIGN_NOTES 206): a long flat top over the
	# tyre, rounded corners, and the sides leaning OUT as they come down (the
	# opening is wider at the rocker than at the top), not straight up and down
	var H: float = P["arch_top"]
	var c: float = P["arch_corner"]
	var run: float = t("arch_slant", 0.14)          # how far each side leans out, top to bottom
	for az in [FZ, RZ]:
		var Lb := _alen(az)                         # half width at the rocker
		var dz := absf(z - az)
		if dz >= Lb:
			continue
		var V: float = Lb - run                      # where the side meets the top line
		var m: float = (H - base) / maxf(run, 0.01)  # the side's slope
		var th := atan(m)
		var tg := c * tan(th * 0.5)                  # the corner's round starts this far before V
		var top := H
		if dz > V - tg:
			var cx := V - tg
			if dz <= V + tg * cos(th):
				var e := dz - cx
				top = H - c + sqrt(maxf(c * c - e * e, 0.0))
			else:
				top = H - (dz - V) * m
		base = maxf(base, top)
	return base


## z stations along a span, denser round the arches so they come out round.
static func _stations(z0: float, z1: float, step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var z := z0
	step *= float(t("density", 0.4))
	while z < z1:
		out.append(z)
		var near := minf(absf(z - FZ), absf(z - RZ))
		var endd := minf(z - z0, z1 - z)
		z += step * (0.35 if near < float(P["arch_r"]) + 0.05 else 1.0) * (0.25 if endd < 0.15 else 1.0)
	out.append(z1)
	return out


## How far out the bed side's skin is at (z, y): read off the panel's own
## cross-section, so things set on it (the fuel door) sit exactly on it.
static func _bed_skin_x(z: float, y: float) -> float:
	var ring := _bed_ring(1.0, _width(z), _bottom(z, float(P["bed_bottom"])), _top(z))
	var best := 0.0
	for i in range(ring.size() - 1):
		var a: Vector3 = ring[i]
		var c: Vector3 = ring[i + 1]
		if (a.y - y) * (c.y - y) <= 0.0 and absf(c.y - a.y) > 1e-6:
			best = maxf(best, lerpf(a.x, c.x, (y - a.y) / (c.y - a.y)))
	return best


## The whole bed side as one pressing (DESIGN_NOTES 208): the side section
## (_bed_ring) runs back along the side, turns the rear corner on a tight
## radius and carries on ACROSS THE BACK as the corner pillar the tail lamp
## sits on, ending at the tailgate's gap - the same section all the way, so
## the shoulder line, the paint break and the rail wrap round the corner and
## the tailgate meets them.
static func _bed_side_full(kit: RefCounted, s: float, zst: Array, base: float) -> void:
	var tz: float = P["tail_z"]
	var rings: Array = []          # PackedVector3Array per station
	var outs: Array = []           # each ring's outward direction (horizontal)
	var offs: Array = []           # each ring's section as (offset out from the skin line, y)
	for z in zst:
		var W := _width(z)
		var yb := _bottom(z, base)
		var sec := _bed_ring(1.0, W, yb, _top(z))
		var ring := PackedVector3Array()
		var off := PackedVector2Array()
		for q in sec:
			ring.append(Vector3(s * q.x, q.y, z))
			off.append(Vector2(q.x - W, q.y))
		rings.append(ring)
		outs.append(Vector3(s, 0, 0))
		offs.append(off)
	# round the corner and across the back
	var zc: float = tz - BED_RC
	var Wc := _width(zc)
	var sec2 := _bed_ring(1.0, Wc, _bottom(zc, base), _top(zc))
	var off2 := PackedVector2Array()
	for q in sec2:
		off2.append(Vector2(q.x - Wc, q.y))
	var cx := Wc - BED_RC                 # the corner's centre (plan), right side
	var xi: float = float(P["w"]) - 0.185 + 0.004      # the tailgate's edge, a shut gap short of it
	var steps := 6
	for k in range(steps + 2):
		var th := PI * 0.5 * clampf(float(k) / float(steps), 0.0, 1.0)
		var n := Vector3(cos(th), 0, sin(th))          # outward, right side
		var ring := PackedVector3Array()
		for o in off2:
			var r := BED_RC + o.x
			var px: float
			var pz: float
			if r > 0.002:
				px = cx + n.x * r
				pz = zc + n.z * r
			else:
				px = cx + r * 0.7071
				pz = zc + r * 0.7071
			if k == steps + 1:
				px = minf(px, xi)                      # across the back to the tailgate's edge
				if r > 0.002:
					px = xi
			ring.append(Vector3(s * px, o.y, pz))
		rings.append(ring)
		outs.append(Vector3(s * n.x, 0, n.z))
		offs.append(off2)
	# loft: faces turned by the section (it runs clockwise round the metal,
	# seen from outside with "out" to the right)
	for r in range(rings.size() - 1):
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		var oa: PackedVector2Array = offs[r]
		var na: Vector3 = (outs[r] as Vector3 + outs[r + 1] as Vector3).normalized()
		var cnt := a.size()
		for i in range(cnt):
			var j := (i + 1) % cnt
			var d_o: float = oa[j].x - oa[i].x
			var d_y: float = oa[j].y - oa[i].y
			var hint := na * (-d_y) + Vector3(0, d_o, 0)
			if hint.length_squared() < 1e-10:
				hint = na
			kit.quad(a[i], a[j], b[j], b[i], Color.WHITE, hint)
	# the front end (at the cab gap) and the end at the tailgate gap
	var first: PackedVector3Array = rings[0]
	var last: PackedVector3Array = rings[rings.size() - 1]
	kit._cap(first, Color.WHITE, Vector3(0, 0, -1))
	kit._cap(last, GAP, Vector3(-s, 0, 0))


## Loft a one-piece panel with its faces turned by the cross-section itself
## (the ring goes clockwise round the metal on the right side), not by a guess
## from its middle - a thin, folded section fools that and faces come out
## inside-out (dark). Ends capped.
static func _panel_loft(kit: RefCounted, rings: Array, s: float) -> void:
	for r in range(rings.size() - 1):
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		var n := a.size()
		for i in range(n):
			var j := (i + 1) % n
			var dx: float = (absf(a[j].x) - absf(a[i].x))
			var dy: float = a[j].y - a[i].y
			var hint := Vector3(-dy * s, dx, 0.0)
			if hint.length_squared() < 1e-10:
				hint = Vector3(s, 0, 0)
			kit.quad(a[i], a[j], b[j], b[i], Color.WHITE, hint)
	for e in [0, rings.size() - 1]:
		var rr: PackedVector3Array = rings[e]
		var other: PackedVector3Array = rings[1 if e == 0 else rings.size() - 2]
		kit._cap(rr, Color.WHITE, Vector3(0, 0, rr[0].z - other[0].z))


## The pickup's bed side as ONE stamped panel (DESIGN_NOTES 206), the way
## the real one is pressed: the inner wall comes up out of the bed, rolls over
## into the flat top rail, round its outer edge, down the outside (the bulge
## and the body line), and at the bottom - the rocker or the wheel opening -
## rolls under into a lip and a flange turned back in. One cross-section, the
## same all the way along, so nothing has to be lined up: the lip round the
## wheel, the rail and the inside wall can't come apart or show a seam.
static func _bed_ring(s: float, w: float, yb: float, yt: float) -> PackedVector3Array:
	var b: float = P["bulge"]
	var fy := 0.86                                   # bed floor
	var xin := w - 0.105                             # the inside wall's face
	var cy := clampf(float(P["crease_y"]), yb + 0.06, yt - 0.06)
	var pts: Array = []
	# the top rail: flat cap, rounded outer edge
	pts.append(Vector2(xin, yt - 0.010))
	pts.append(Vector2(xin + 0.006, yt - 0.001))
	pts.append(Vector2(w - 0.034, yt + 0.002))
	pts.append(Vector2(w - 0.018, yt - 0.002))
	pts.append(Vector2(w - 0.011, yt - 0.009))
	pts.append(Vector2(w - 0.008, yt - 0.018))
	# the outside, top down: in a touch under the rail, the body line (a sharp
	# crease), the bulge, then in again toward the bottom
	# (K10 / K5 photos) from the rail a soft curve out and down to the shoulder line just under it
	var ctl := [Vector2(w - 0.008, yt - 0.018), Vector2(w + b * 0.4 - 0.004, lerpf(cy, yt, 0.55)), Vector2(w + b - 0.006, cy + 0.008),
		Vector2(w + b + 0.016, cy - 0.004), Vector2(w + b + 0.004, cy - 0.022), Vector2(w + b, lerpf(yb, cy, 0.6)), Vector2(w + b * 0.5, yb + 0.03)]
	for i in range(1, ctl.size()):
		var a: Vector2 = ctl[i - 1]
		var c: Vector2 = ctl[i]
		var n := 1 if i == 4 else (3 if i == 3 else 2)
		for k in range(1, n + 1):
			pts.append(a.lerp(c, float(k) / float(n)))
	# the lip: rolls out over the edge, under, and turns back in as a flange
	pts.append(Vector2(w + b * 0.4, yb + 0.012))
	pts.append(Vector2(w + b * 0.5 + 0.004, yb - 0.002))
	pts.append(Vector2(w - 0.010, yb - 0.014))
	pts.append(Vector2(w - 0.060, yb - 0.012))
	pts.append(Vector2(w - 0.075, yb + 0.004))
	# up inside to the bed: the inner wall meets the floor (or, over the wheel,
	# closes just above the lip - the tub fills in under it)
	pts.append(Vector2(xin, maxf(yb + 0.03, fy - 0.03)))
	var ring := PackedVector3Array()
	for q in pts:
		ring.append(Vector3((q as Vector2).x * s, (q as Vector2).y, 0.0))
	return ring


## One side panel's cross-section at z (a thick, gently bulging skin), for the
## side `s` (+1 right, -1 left). From the inside bottom, round the outside, to
## the inside top.
static func _side_ring(s: float, w: float, yb: float, yt: float) -> PackedVector3Array:
	var b: float = P["bulge"]
	var th := 0.045
	# the outer skin as x(y), then sampled at its own points plus the two paint
	# lines, so a stripe edge is a real seam and stays crisp (always the same count)
	var cy := clampf(float(P["crease_y"]), yb + 0.05, yt - 0.025)
	# the bottom rolls under over 8 cm along the rocker; round a wheel opening
	# it turns in tight, straight down onto the lip (no second outline above it)
	var lo2 := maxf(float(P["rocker_y"]), float(P["bed_bottom"]))
	var ka := clampf((yb - lo2 - 0.02) / 0.08, 0.0, 1.0)
	var ctl := [Vector2(w - lerpf(0.03, 0.012, ka), yb), Vector2(w - 0.008 * (1.0 - ka), yb + lerpf(0.025, 0.006, ka)), Vector2(w, yb + lerpf(0.08, 0.018, ka)),
		Vector2(w + b, lerpf(yb, cy, 0.6)), Vector2(w + b + 0.004, cy - 0.022), Vector2(w + b + 0.016, cy - 0.004), Vector2(w + b - 0.006, lerpf(cy, yt, 0.3)),
		Vector2(w + b * 0.4 - 0.004, lerpf(cy, yt, 0.55)), Vector2(w - 0.010, lerpf(cy, yt, 0.78)), Vector2(w - 0.018, lerpf(cy, yt, 0.92)),
		Vector2(w - 0.030, yt - 0.001), Vector2(w - 0.050, yt)]
	var ys: Array = []
	for c in ctl:
		ys.append((c as Vector2).y)
	for ty in [float(P["tone_lo"]), float(P["tone_hi"])]:
		var yy := clampf(ty, yb + 0.002, yt - 0.002)
		var dup := false
		for e in ys:
			if absf(float(e) - yy) < 0.003:
				dup = true
		ys.append(yy + (0.004 if dup else 0.0))
	ys.sort()
	var ring := PackedVector3Array()
	ring.append(Vector3((w - th) * s, yb, 0.0))
	for y in ys:
		var x := _skin_x(ctl, y)
		ring.append(Vector3(x * s, y, 0.0))
	ring.append(Vector3((w - th - 0.01) * s, yt - 0.01, 0.0))
	return ring


static func _skin_x(ctl: Array, y: float) -> float:
	for i in range(ctl.size() - 1):
		var a: Vector2 = ctl[i]
		var c: Vector2 = ctl[i + 1]
		if y >= a.y and y <= c.y:
			return lerpf(a.x, c.x, 0.0 if c.y - a.y < 1e-5 else (y - a.y) / (c.y - a.y))
	return (ctl[ctl.size() - 1] as Vector2).x


static func _at_z(ring: PackedVector3Array, z: float) -> PackedVector3Array:
	var r := PackedVector3Array()
	for p in ring:
		r.append(Vector3(p.x, p.y, z))
	return r


## Width in plan at z: the nose and the tail corners are rounded off.
static func _width(z: float) -> float:
	var w: float = P["w"]
	var nr: float = P["nose_round"]
	var nz: float = P["nose_z"]
	w -= _corner(z - nz, nr, float(P.get("nose_span", 0.16)))   # a tight, crisp fender corner
	var tz: float = P["tail_z"]
	w -= _corner(tz - z, 0.022, 0.05)                       # bed's back corners
	var cb: float = P["cab_back_z"]
	var bz: float = P["bed_z"]
	if z <= cb + 0.001:
		w -= _corner(cb - z, 0.028, 0.07)                   # the cab's back corners wrap round
	elif z >= bz - 0.001:
		w -= _corner(z - bz, 0.02, 0.05)                    # the bed's front corners
	return w


## How far a rounded corner of radius-ish `r` pulls the side in, `d` from the
## panel's end (quarter-circle profile over `span`).
## A flat disc on the left side (facing -x).
static func _rdisc(kit: RefCounted, c: Vector3, r: float, col: Color) -> void:
	for i in range(20):
		var a0 := TAU * float(i) / 20.0
		var a1 := TAU * float(i + 1) / 20.0
		var p0 := c + Vector3(0, sin(a0) * r, cos(a0) * r)
		var p1 := c + Vector3(0, sin(a1) * r, cos(a1) * r)
		kit.tri(c, p0, p1, col, Vector3(-1, 0, 0))
		kit.tri(c, p1, p0, col, Vector3(1, 0, 0))


## A flat rounded rectangle on the left side (facing -x): fuel door, badges.
static func _rrect(kit: RefCounted, c: Vector3, lz: float, hy: float, r: float, col: Color) -> void:
	var pts: Array = []
	var hz := lz * 0.5 - r
	var hh := hy * 0.5 - r
	var corners := [Vector2(hz, hh), Vector2(-hz, hh), Vector2(-hz, -hh), Vector2(hz, -hh)]
	for ci in range(4):
		for k in range(5):
			var a := PI * 0.5 * float(ci) + PI * 0.5 * float(k) / 4.0
			pts.append(corners[ci] + Vector2(cos(a), sin(a)) * r)
	for i in range(pts.size()):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % pts.size()]
		var a3 := c + Vector3(0, p0.y, p0.x)
		var b3 := c + Vector3(0, p1.y, p1.x)
		kit.tri(c, a3, b3, col, Vector3(-1, 0, 0))
		kit.tri(c, b3, a3, col, Vector3(1, 0, 0))


static func _corner(d: float, r: float, span: float) -> float:
	var k := clampf(d / span, 0.0, 1.0)
	return r * (1.0 - sqrt(maxf(1.0 - (1.0 - k) * (1.0 - k), 0.0)))


## Top of the side panels at z: nose up over the hood to the cowl, the
## beltline along the cab, the bed rail.
static func _top(z: float) -> float:
	var nz: float = P["nose_z"]
	var cz: float = P["cowl_z"]
	if z <= cz:
		var f := clampf((z - nz) / (cz - nz), 0.0, 1.0)
		var front := lerpf(float(P["nose_y"]), float(P["hood_y"]), clampf(f * 4.0, 0.0, 1.0))
		return lerpf(front, float(P["cowl_y"]), f * f)
	if z <= float(P["cab_back_z"]):
		return P["belt_y"]
	return P["rail_y"]


# ------------------------------------------------------------------------------
#  Panels
# ------------------------------------------------------------------------------
static func _sides(kit: RefCounted) -> void:
	# cab and front fenders as one skin; the bed sides as another (the gap between)
	var dz := door_z()
	var cz: float = P["cowl_z"]
	var fend_end := minf(cz, dz.x - 0.004)
	var spans := [[float(P["nose_z"]), fend_end, float(P["rocker_y"]), "Fender", true, false]]
	if dz.x - 0.004 > cz + 0.01:
		spans.append([cz, dz.x - 0.004, float(P["rocker_y"]), "CabFront", false, true])
	var rear: Array = [[dz.y + 0.004, float(P["cab_back_z"]), float(P["rocker_y"]), "CabRear", true, true],
			[float(P["bed_z"]), float(P["tail_z"]) - BED_RC, float(P["bed_bottom"]), "BedSide", true, true]]
	if style == "blazer":
		rear = [[dz.y + 0.004, float(P["tail_z"]), float(P["rocker_y"]), "Quarter", true, true]]
	elif style == "suburban":
		var rd: Vector2 = P["rear_door"]
		rear = [[dz.y + 0.004, rd.x - 0.004, float(P["rocker_y"]), "BPillar", true, true],
			[rd.y + 0.004, float(P["tail_z"]), float(P["rocker_y"]), "Quarter", true, true]]
	for span in spans + rear:
		for s in [-1.0, 1.0]:
			_sw(String(span[3]) + ("L" if s < 0.0 else "R"))
			var rings: Array = []
			var one_piece := String(span[3]) == "BedSide"
			var zst: Array = Array(_stations(span[0], span[1], 0.12))
			if one_piece:
				# stations right at the opening's straight edges, so they come out crisp
				for e2 in [-1.0, 1.0]:
					for dd in [-0.003, 0.003]:
						var ze: float = RZ + e2 * _alen(RZ) + dd
						if ze > float(span[0]) and ze < float(span[1]):
							zst.append(ze)
				zst.sort()
			for z in zst:
				var yb := _bottom(z, span[2])
				if one_piece:
					rings.append(_at_z(_bed_ring(s, _width(z), yb, _top(z)), z))
				else:
					rings.append(_at_z(_side_ring(s, _width(z), yb, _top(z)), z))
			var rdz: Vector2 = P["rear_door"]
			var gap_front: bool = absf(float(span[1]) - (dz.x - 0.004)) < 0.001 or (style == "suburban" and absf(float(span[1]) - (rdz.x - 0.004)) < 0.001)
			var gap_back: bool = absf(float(span[0]) - (dz.y + 0.004)) < 0.001 or (style == "suburban" and absf(float(span[0]) - (rdz.y + 0.004)) < 0.001)
			if one_piece:
				_bed_side_full(kit, s, zst, float(span[2]))
			else:
				kit.loft(rings, Color.WHITE, bool(span[4]) and not gap_back, bool(span[5]) and not gap_front)
			if gap_back:
				kit._cap(rings[0], GAP, _centroid_of(rings[0]) - _centroid_of(rings[1]))
			if gap_front:
				kit._cap(rings[rings.size() - 1], GAP, _centroid_of(rings[rings.size() - 1]) - _centroid_of(rings[rings.size() - 2]))
	_arch_lips(kit)
	_wheel_wells()
	_sw("")
	# (the doors are their own hinged parts: _doors)


const GAP := Color(0.035, 0.035, 0.04)       # inside a shut line
const CORNER := 0.11                          # the bed's rear corner posts (they carry the tail lamps)
const BED_RC := 0.05                          # the bed side's rear corner: it turns this tight onto the back face


static func _centroid_of(ring: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	return c / float(ring.size())


## The wheel openings: the panel edge rolls in (a lip with thickness, as
## pressed steel does) and a dark wheelhouse behind it.
static func _wheel_wells() -> void:
	for ai in range(2):
		var az: float = FZ if ai == 0 else RZ
		for s in [-1.0, 1.0]:
			_sw("WheelWell%s%s" % ["F" if ai == 0 else "R", "L" if s < 0.0 else "R"])
			var shell: Array = []
			var base: float = float(P["rocker_y"]) if (ai == 0 or suv()) else float(P["bed_bottom"])
			# room for the tyre at full bump and full lock: a wider, taller housing
			var bed_rear := ai == 1 and not suv()          # under the pickup's bed: stay inside the tubs
			var cy := AXLE_Y + (0.03 if bed_rear else 0.07)
			var ro := 0.58 if bed_rear else 0.66
			var ri := ro - 0.03
			var a0 := rad_to_deg(asin(clampf((base + 0.01 - cy) / ro, -1.0, 1.0)))
			# outside: the liner follows the body's square opening right up under
			# the lip (nothing behind shows through the corners); inside it rounds
			# up into the circle over the tyre (room at full bump)
			var L2: float = _alen(az)
			var ca := cos(deg_to_rad(a0))
			for xi in range(2):
				var xx: float = s * (float(P["w"]) - 0.06) if xi == 0 else s * 0.57
				var ring := PackedVector3Array()
				for k in range(15):
					var th := deg_to_rad(lerpf(a0, 180.0 - a0, float(k) / 14.0))
					if xi == 0:
						var zo := az + L2 * cos(th) / maxf(ca, 0.2)
						ring.append(Vector3(xx, _bottom(zo, base) + 0.03, zo))
					else:
						ring.append(Vector3(xx, cy + sin(th) * ro, az + cos(th) * ro))
				for k in range(14, -1, -1):
					var th2 := deg_to_rad(lerpf(a0, 180.0 - a0, float(k) / 14.0))
					if xi == 0:
						var zo2 := az + (L2 - 0.012) * cos(th2) / maxf(ca, 0.2)
						ring.append(Vector3(xx, _bottom(zo2, base) + 0.002, zo2))
					else:
						ring.append(Vector3(xx, cy + sin(th2) * ri, az + cos(th2) * ri))
				shell.append(ring)
			(_K["black"] as RefCounted).loft(shell, Color(0.03, 0.03, 0.03), true, true)
			# the inboard wall of the well (a proper wheelhouse: it closes the well
			# off from the engine bay / under the bed)
			var kb: RefCounted = _K["black"]
			var xw: float = s * 0.57
			var mid := Vector3(xw, base + 0.01, az)
			var prev := Vector3.ZERO
			for k in range(15):
				var th3 := deg_to_rad(lerpf(a0, 180.0 - a0, float(k) / 14.0))
				var q := Vector3(xw, cy + sin(th3) * ro, az + cos(th3) * ro)
				if k > 0:
					kb.tri(mid, prev, q, Color(0.035, 0.035, 0.035), Vector3(-s, 0, 0))
					kb.tri(mid, q, prev, Color(0.035, 0.035, 0.035), Vector3(s, 0, 0))
				prev = q
			# the splash walls fore and aft of the tyre: the inner fender closes
			# off the well, so past the tyre you see black, not the inside of the
			# fender, the door shut or the cab floor
			if not bed_rear:
				var Lw := _alen(az)
				var wo: float = float(P["w"]) - 0.015
				for e in [-1.0, 1.0]:
					var zw: float = az + e * (Lw + 0.012)
					var dzw: float = minf(Lw + 0.012, ro - 0.01)
					var ytop: float = cy + sqrt(maxf(ro * ro - dzw * dzw, 0.0))
					var ybot: float = base - 0.03
					kb.box_at(Vector3(s * (0.57 + wo) * 0.5, (ytop + ybot) * 0.5, zw), Vector3(wo - 0.57, ytop - ybot, 0.012), Color(0.03, 0.03, 0.03))


static func _arch_lips(kit: RefCounted) -> void:
	var b: float = P["bulge"]
	for ai in range(2):
		var az: float = FZ if ai == 0 else RZ
		if ai == 1 and not suv():
			continue          # the bed side's lip is part of the panel itself (_bed_ring)
		var L := _alen(az)
		var base: float = float(P["rocker_y"]) if ai == 0 else float(P["bed_bottom"])
		for s in [-1.0, 1.0]:
			_sw("WheelLip%s%s" % ["F" if ai == 0 else "R", "L" if s < 0.0 else "R"])
			var rings: Array = []
			var n := 40
			# stations, plus extra ones bunched where the lip crosses a paint line
			# (so its colour edge lines up with the panel's)
			var zs2: Array = []
			for k in range(n + 1):
				zs2.append(az - L + 0.002 + (2.0 * L - 0.004) * float(k) / float(n))
			for ty in [float(P["tone_lo"]), float(P["tone_hi"])]:
				for k in range(n):
					var za2: float = zs2[k]
					var zb2: float = zs2[k + 1]
					var ya2 := _bottom(za2, base)
					var yb2 := _bottom(zb2, base)
					if (ya2 - ty) * (yb2 - ty) < 0.0:
						var zc := lerpf(za2, zb2, (ty - ya2) / (yb2 - ya2))
						for dzz in [-0.004, -0.001, 0.001, 0.004]:
							zs2.append(zc + dzz)
			zs2.sort()
			for z in zs2:
				var y := _bottom(z, base)
				if y <= base + 0.001:
					continue
				var w := _width(z)
				# section across the lip: outer edge, roll under, return inward
				var ring := PackedVector3Array()
				ring.append(Vector3(s * (w + b * 0.4), y + 0.012, z))
				ring.append(Vector3(s * (w + b * 0.5 + 0.004), y - 0.004, z))
				ring.append(Vector3(s * (w - 0.015), y - 0.014, z))
				ring.append(Vector3(s * (w - 0.075), y - 0.010, z))
				ring.append(Vector3(s * (w - 0.075), y + 0.004, z))
				rings.append(ring)
			if rings.size() >= 2:
				kit.loft(rings, Color.WHITE, false, false)


static func _front_clip(kit: RefCounted, black: RefCounted) -> void:
	# the inner fender walls either side of the engine bay (open on top: the
	# engine shows when the hood is up)
	var nz: float = P["nose_z"]
	var cz: float = P["cowl_z"]
	_sw("InnerFenders")
	for s in [-1.0, 1.0]:
		var x: float = s * 0.56                      # inboard of the tyre (it sliced through the wheel at w - 0.22)
		black.box_at(Vector3(x, 0.92, (nz + cz) * 0.5 + 0.05), Vector3(0.03, 0.42, cz - nz - 0.25), Color(0.06, 0.06, 0.065))
		black.box_at(Vector3(s * (float(P["w"]) - 0.12), 1.12, (nz + cz) * 0.5 + 0.05), Vector3(0.20, 0.02, cz - nz - 0.25), Color(0.06, 0.06, 0.065))
	_sw("Cowl")
	# the cowl panel and wipers in front of the windshield
	kit.box_at(Vector3(0, float(P["cowl_y"]) - 0.01, cz + 0.06), Vector3(float(P["w"]) * 1.9, 0.03, 0.14), Color(0.04, 0.04, 0.04))
	_sw("Wipers")
	for x in [-0.38, 0.22]:
		black.box(Transform3D(Basis(Vector3.UP, 0.12), Vector3(x, float(P["cowl_y"]) + 0.02, cz + 0.02)), Vector3(0.5, 0.012, 0.012), Color(0.03, 0.03, 0.03))


static func _greenhouse(kit: RefCounted, glass: RefCounted) -> void:
	# glass all round (flush), the roof cap, the pillars in paint
	var cz: float = P["cowl_z"]
	var gz: float = P["glass_top_z"]
	var bz: float = P["cab_back_z"] - 0.03
	if suv():
		bz = float(P["tail_z"]) - 0.02                  # the roof runs to the back of the body
	var belt: float = P["belt_y"]
	var roof: float = P["roof_y"]
	var tum: float = P["tumble"]
	var w: float = P["w"] - 0.03
	var gt: float = roof - float(P["roof_thick"])       # top of the glass: the roof rail shows above it
	# glass as separate panes (a closed shell put a sheet of glass across the cab
	# at the sill): windshield, back glass, a door window each side
	var tw := w - tum                                # half width at the roof
	var wsb := [Vector3(-w, belt + 0.01, cz + 0.02), Vector3(w, belt + 0.01, cz + 0.02)]
	var wst := [Vector3(tw, gt, gz), Vector3(-tw, gt, gz)]
	_sw("Windshield")
	glass.quad(wsb[0], wsb[1], wst[0], wst[1], Color.WHITE, Vector3(0, 0.5, -1))
	_sw("BackGlass")
	glass.quad(Vector3(-w + 0.02, belt + 0.02, bz), Vector3(w - 0.02, belt + 0.02, bz), Vector3(tw - 0.03, gt - 0.005, bz - 0.05), Vector3(-tw + 0.03, gt - 0.005, bz - 0.05), Color.WHITE, Vector3(0, 0, 1))
	# black rubber trim along the top of the windshield and back glass
	var trim_w := (w - tum) * 2.0 - 0.06
	kit.box_at(Vector3(0, gt, gz - 0.005), Vector3(trim_w, 0.02, 0.03), Color(0.03, 0.03, 0.03))
	kit.box_at(Vector3(0, gt - 0.005, bz - 0.055), Vector3(trim_w, 0.02, 0.025), Color(0.03, 0.03, 0.03))
	var bgl := [Vector3(-w + 0.02, belt + 0.02, bz + 0.004), Vector3(w - 0.02, belt + 0.02, bz + 0.004), Vector3(tw - 0.03, gt - 0.005, bz - 0.046), Vector3(-tw + 0.03, gt - 0.005, bz - 0.046)]
	_tube(kit, [bgl[0], bgl[1], bgl[2], bgl[3], bgl[0]], 0.012, Color(0.03, 0.03, 0.03), 6)   # the back glass's rubber
	_sw("Roof")
	# roof cap, a touch proud of the glass, drip rails along its edges
	var roof_rings: Array = []
	var zs := [gz - 0.03, gz - 0.015, gz + 0.02, gz + 0.08, bz - 0.14, bz - 0.08, bz - 0.05, bz - 0.04]
	for zi in range(zs.size()):
		var z: float = zs[zi]
		# plan corners: the ends pull in on a curve
		var e := minf(z - (gz - 0.03), (bz - 0.04) - z)
		var hw := w - tum + 0.012 - _corner(e, 0.035, 0.06)
		var drop := -0.012 * (1.0 - clampf(e / 0.05, 0.0, 1.0))
		var ring := PackedVector3Array()
		var prof: Array = []
		for k in range(7):
			var u := lerpf(-0.86, 0.86, float(k) / 6.0)
			prof.append(Vector2(u * hw, roof + 0.012 * (1.0 - u * u)))
		var edge := [Vector2(hw - 0.035, roof - 0.003), Vector2(hw - 0.014, roof - 0.014), Vector2(hw - 0.003, roof - 0.032), Vector2(hw, roof - 0.055), Vector2(hw - 0.004, gt + 0.004)]
		var full: Array = []
		for q in range(edge.size() - 1, -1, -1):
			full.append(Vector2(-(edge[q] as Vector2).x, (edge[q] as Vector2).y))
		full += prof
		full += edge
		for q in full:
			ring.append(Vector3((q as Vector2).x, (q as Vector2).y + drop, z))
		roof_rings.append(ring)
	kit.loft(roof_rings, P["roof_col"], true, true)
	_sw("Pillars")
	# pillars: A (along the windshield edge), B (door), C (cab corner)
	for s in [-1.0, 1.0]:
		# A pillar: pressed steel, not a tube - a flat outer face with rolled
		# edges, the windshield's rubber along its front edge, the door frame
		# against its back edge (DESIGN_NOTES 207)
		var a_bot := Vector3(s * (w + 0.002), belt + 0.01, cz + 0.02)
		var a_top := Vector3(s * (w - tum + 0.004), gt, gz)
		var a_rings: Array = []
		for k in range(7):
			var u := float(k) / 6.0
			var p := a_bot.lerp(a_top, u)
			# it stops just ahead of the door's window frame (the frame makes the
			# back half of what you see as the pillar), so the door swings clear
			var wdt := lerpf(0.034, 0.024, u)
			var ring := PackedVector3Array()
			ring.append(p + Vector3(-s * 0.030, 0, 0.000))           # inside, at the glass
			ring.append(p + Vector3(s * 0.004, 0, -0.002))           # front edge, rolled
			ring.append(p + Vector3(s * 0.014, 0, 0.010))
			ring.append(p + Vector3(s * 0.016, 0, wdt * 0.6))        # the flat outer face
			ring.append(p + Vector3(s * 0.012, 0, wdt - 0.003))
			ring.append(p + Vector3(s * 0.002, 0, wdt))              # back edge, the door shuts on it
			ring.append(p + Vector3(-s * 0.028, 0, wdt - 0.004))     # inside
			a_rings.append(ring)
		kit.loft(a_rings, Color.WHITE, true, true)
		var a_dir := (a_top - a_bot).normalized()
		_tube(kit, [a_bot + Vector3(s * 0.006, 0, -0.006), a_top + Vector3(s * 0.006, 0, -0.006)], 0.007, Color(0.03, 0.03, 0.03), 6)   # windshield rubber
		var topc: Color = P["roof_col"] if style == "blazer" else Color.WHITE      # the Blazer's removable top is white
		# the cab's back corner (C pillar): a wide panel that wraps round from the
		# side to the back, out to the back glass - one piece, square-body crisp
		var c_rings: Array = []
		var zd: float = door_z().y + 0.004
		for k in range(5):
			var u2 := float(k) / 4.0
			var y := lerpf(belt, gt, u2)
			var xs: float = w + 0.004 - tum * u2          # the side, leaning in with the tumblehome
			var zb2: float = bz - 0.012 - 0.04 * u2       # the back, leaning forward a touch at the top
			var xg: float = (w - 0.02) - (tum + 0.03) * u2 - 0.03   # out to the back glass
			var ring2 := PackedVector3Array()
			ring2.append(Vector3(s * (xs - 0.030), y, zd))                    # inside the door shut
			ring2.append(Vector3(s * xs, y, zd))                             # side face, from the door gap
			ring2.append(Vector3(s * xs, y, zb2 - 0.030))
			ring2.append(Vector3(s * (xs - 0.008), y, zb2 - 0.008))          # the rounded corner
			ring2.append(Vector3(s * (xs - 0.030), y, zb2))
			ring2.append(Vector3(s * xg, y, zb2))                            # back face, to the glass
			ring2.append(Vector3(s * xg, y, zb2 - 0.030))                    # inside
			c_rings.append(ring2)
		kit.loft(c_rings, topc, true, true)
		if suv():
			# the B pillar behind the front door; the suburban's C pillar behind its back door
			var cb: float = float(P["cab_back_z"]) - 0.03
			_bar(kit, Vector3(s * (w + 0.004), belt, cb), Vector3(s * (w - tum + 0.01), gt, cb - 0.03), 0.045, Color.WHITE)
			var qz0 := cb + 0.04
			if style == "suburban":
				var rd: Vector2 = P["rear_door"]
				_bar(kit, Vector3(s * (w + 0.004), belt, rd.y + 0.01), Vector3(s * (w - tum + 0.01), gt, rd.y - 0.02), 0.045, topc)
				qz0 = rd.y + 0.05
			# the quarter: a solid panel (the Blazer's removable top, white) with a
			# framed window in it - rounded corners, a slider divider - and a wide
			# solid section behind it (reference k10_80s/04)
			var wz0 := qz0 + 0.04
			var wz1 := bz - (0.40 if style == "blazer" else 0.30)
			var wy0 := belt + 0.06
			var wy1 := gt - 0.05
			var xat := func(y: float) -> float: return w - tum * clampf((y - belt) / maxf(gt - belt, 0.01), 0.0, 1.0) + 0.004
			var pc: Color = topc
			for r in [[qz0 - 0.02, wz0, belt, gt], [wz1, bz - 0.04, belt, gt], [wz0, wz1, belt, wy0], [wz0, wz1, wy1, gt]]:
				var za: float = r[0]
				var zb: float = r[1]
				var ya: float = r[2]
				var yb: float = r[3]
				kit.quad(Vector3(s * xat.call(ya), ya, za), Vector3(s * xat.call(ya), ya, zb), Vector3(s * xat.call(yb), yb, zb), Vector3(s * xat.call(yb), yb, za), pc, Vector3(s, 0, 0))
				kit.quad(Vector3(s * (xat.call(ya) - 0.02), ya, za), Vector3(s * (xat.call(ya) - 0.02), ya, zb), Vector3(s * (xat.call(yb) - 0.02), yb, zb), Vector3(s * (xat.call(yb) - 0.02), yb, za), Color(0.22, 0.17, 0.13), Vector3(-s, 0, 0))   # inside trim
			if style == "blazer":
				kit.box_at(Vector3(s * (w + 0.006), belt + 0.006, (qz0 + bz) * 0.5), Vector3(0.012, 0.012, bz - qz0), Color(0.04, 0.04, 0.04))   # the top's seal on the body
			_sw("QuarterGlass")
			glass.quad(Vector3(s * (xat.call(wy0) - 0.006), wy0, wz0), Vector3(s * (xat.call(wy0) - 0.006), wy0, wz1), Vector3(s * (xat.call(wy1) - 0.006), wy1, wz1), Vector3(s * (xat.call(wy1) - 0.006), wy1, wz0), Color.WHITE, Vector3(s, 0, 0))
			# rubber frame round it, rounded corners, and the slider's divider
			var frame: Array = []
			var cr := 0.05
			var cs := [Vector2(wz1 - cr, wy1 - cr), Vector2(wz0 + cr, wy1 - cr), Vector2(wz0 + cr, wy0 + cr), Vector2(wz1 - cr, wy0 + cr)]
			for ci in range(4):
				for k in range(5):
					var a := (float(ci) + float(k) / 4.0) * PI * 0.5
					var zz: float = (cs[ci] as Vector2).x + cos(a) * cr
					var yy: float = (cs[ci] as Vector2).y + sin(a) * cr
					frame.append(Vector3(s * (xat.call(yy) + 0.002), yy, zz))
			frame.append(frame[0])
			_tube(kit, frame, 0.012, Color(0.03, 0.03, 0.03), 6)
			var mz := (wz0 + wz1) * 0.5
			_tube(kit, [Vector3(s * (xat.call(wy0) + 0.002), wy0, mz), Vector3(s * (xat.call(wy1) + 0.002), wy1, mz)], 0.008, Color(0.03, 0.03, 0.03), 6)
			_sw("Pillars")


static func _bar(kit: RefCounted, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	kit.cylinder(Transform3D(Basis(x, y, z), a + d * 0.5) * Transform3D(Basis.IDENTITY, Vector3(0, -d.length() * 0.5, 0)), r, r, d.length(), 10, col, true)


static func _bed(kit: RefCounted, black: RefCounted) -> void:
	if suv():
		_cargo(kit, black)
		return
	# (DESIGN_NOTES 201) a real pickup bed, painted body colour inside: a
	# corrugated floor (long raised ribs), the front wall with its stamped bands,
	# boxy wheel tubs with rounded tops, the sills under the floor, tie-down loops
	var z0: float = P["bed_z"]
	var z1: float = P["tail_z"] - 0.05
	var rail: float = P["rail_y"]
	var w: float = P["w"]
	var wi := w - 0.04                                    # inside the bed walls (tucked into them)
	var bedc: Color = (P["paint"] as Color).darkened(0.08)
	var fy := 0.86
	_sw("BedFloor")
	# the floor is cut round the wheel tubs (the tyres come up into them): a
	# middle section the full length, the outer strips ahead of and behind the tubs
	var xt := wi - 0.36
	var zf := float(P["tail_z"]) - 0.02
	_floor_section(black, -xt, xt, z0 + 0.045, zf, fy, bedc)
	for sx in [-1.0, 1.0]:
		var xa: float = minf(sx * xt, sx * wi)
		var xb: float = maxf(sx * xt, sx * wi)
		_floor_section(black, xa, xb, z0 + 0.045, RZ - 0.50, fy, bedc)
		_floor_section(black, xa, xb, RZ + 0.50, zf, fy, bedc)
	for zz in range(6):
		black.box_at(Vector3(0, fy - 0.07, lerpf(z0 + 0.15, z1 - 0.1, float(zz) / 5.0)), Vector3(wi * 2.0 - 0.1, 0.07, 0.05), Color(0.06, 0.06, 0.06))   # sills
	_sw("BedFrontWall")
	black.box_at(Vector3(0, (fy + rail) * 0.5, z0 + 0.03), Vector3(wi * 2.0 + 0.04, rail - fy, 0.04), bedc)
	for i in range(4):
		black.box_at(Vector3(0, lerpf(fy + 0.09, rail - 0.08, float(i) / 3.0), z0 + 0.057), Vector3(wi * 2.0 - 0.12, 0.035, 0.012), bedc)   # stamped bands
	black.box_at(Vector3(0, rail + 0.008, z0 + 0.03), Vector3(wi * 2.0 + 0.1, 0.022, 0.07), P["paint"])     # the front rail cap
	_sw("WheelTubs")
	for s in [-1.0, 1.0]:
		# boxy tubs with a rounded top, from the side wall in to the frame
		var tub: Array = []
		var tz := RZ
		var hl := 0.50                                     # half length along the bed
		var top := 1.10
		var rad := 0.16
		var prof: Array = [Vector2(-hl, fy)]
		for k in range(7):
			var a := lerpf(PI, PI * 0.5, float(k) / 6.0)
			prof.append(Vector2(-hl + rad + cos(a) * rad, top - rad + sin(a) * rad))
		for k in range(7):
			var a := lerpf(PI * 0.5, 0.0, float(k) / 6.0)
			prof.append(Vector2(hl - rad + cos(a) * rad, top - rad + sin(a) * rad))
		prof.append(Vector2(hl, fy))
		for xx in [s * (wi - 0.005), s * (wi - 0.36)]:
			var rr := PackedVector3Array()
			for q in prof:
				rr.append(Vector3(xx, (q as Vector2).y, tz + (q as Vector2).x))
			tub.append(rr)
		black.loft(tub, bedc, true, true)
		# its underside, seen up through the wheel opening: black undercoat
		var und: Array = []
		for xx2 in [s * (float(P["w"]) - 0.02), s * (wi - 0.37)]:
			var ru := PackedVector3Array()
			for q in prof:
				var qv: Vector2 = q
				ru.append(Vector3(xx2, minf(qv.y, top - 0.015) - 0.01, tz + qv.x * 0.97))
			und.append(ru)
		black.loft(und, Color(0.03, 0.03, 0.03), true, true)
		var und2: Array = [und[1], und[0]]
		black.loft(und2, Color(0.03, 0.03, 0.03), true, true)
		pass   # (the rail cap is part of the one-piece bed side now: _bed_ring)
	_sw("TieDowns")
	for s in [-1.0, 1.0]:
		for zz in [z0 + 0.12, z1 - 0.12]:
			var p0 := Vector3(s * (wi - 0.01), fy + 0.10, zz)
			black.box_at(p0 + Vector3(s * 0.004, 0, 0), Vector3(0.008, 0.05, 0.07), Color(0.5, 0.5, 0.5))
			var loop: Array = []
			for j in range(9):
				var a := lerpf(0.0, PI, float(j) / 8.0)
				loop.append(p0 + Vector3(-s * (0.012 + sin(a) * 0.025), 0, cos(a) * 0.025))
			_tube(black, loop, 0.005, Color(0.6, 0.6, 0.6), 8)


## A corrugated floor slab between xa..xb, za..zb: raised ribs every ~20 cm.
static func _floor_section(kit: RefCounted, xa: float, xb: float, za: float, zb: float, fy: float, col: Color) -> void:
	if zb - za < 0.02 or xb - xa < 0.02:
		return
	# the top surface as a strip (each face wound to face up - a loft got some
	# of them upside down, the dark slits between the ribs), then the underside
	var ribs := maxi(int(round((xb - xa) / 0.21)), 1)
	var pitch := (xb - xa) / float(ribs)
	var top: Array = [Vector2(xa, fy)]
	for i in range(ribs):
		var xc := xa + pitch * (i + 0.5)
		top += [Vector2(xc - 0.032, fy), Vector2(xc - 0.024, fy + 0.016), Vector2(xc + 0.024, fy + 0.016), Vector2(xc + 0.032, fy)]
	top.append(Vector2(xb, fy))
	for i in range(top.size() - 1):
		var p0: Vector2 = top[i]
		var p1: Vector2 = top[i + 1]
		kit.quad(Vector3(p0.x, p0.y, za), Vector3(p1.x, p1.y, za), Vector3(p1.x, p1.y, zb), Vector3(p0.x, p0.y, zb), col, Vector3(0, 1, 0))
	kit.quad(Vector3(xa, fy - 0.03, za), Vector3(xb, fy - 0.03, za), Vector3(xb, fy - 0.03, zb), Vector3(xa, fy - 0.03, zb), col.darkened(0.3), Vector3(0, -1, 0))
	for z in [za, zb]:
		kit.quad(Vector3(xa, fy - 0.03, z), Vector3(xb, fy - 0.03, z), Vector3(xb, fy + 0.016, z), Vector3(xa, fy + 0.016, z), col, Vector3(0, 0, -1 if z == za else 1))


## SUVs: a carpeted floor to the tailgate, the wheel housings inside, a rear
## bench (and the suburban's middle bench), side trim panels.
static func _cargo(kit: RefCounted, black: RefCounted) -> void:
	var cb: float = P["cab_back_z"]
	var tz: float = P["tail_z"]
	var w: float = P["w"] - 0.06
	var carpet := Color(0.16, 0.13, 0.11)
	var cloth := Color(0.30, 0.22, 0.16)
	_sw("CargoFloor")
	black.box_at(Vector3(0, 0.62, (cb + tz) * 0.5), Vector3(w * 2.0, 0.03, tz - cb), carpet)
	for s in [-1.0, 1.0]:
		black.box_at(Vector3(s * (w - 0.17), 0.80, RZ), Vector3(0.34, 0.36, 1.0), carpet)                  # wheel housings
		black.box_at(Vector3(s * (w + 0.0), 1.02, (cb + tz) * 0.5), Vector3(0.03, 0.66, tz - cb - 0.1), Color(0.22, 0.17, 0.13))   # side trim
	var hw3: float = float(P["w"]) - 0.03 - float(P["tumble"]) - 0.05
	black.box_at(Vector3(0, float(P["roof_y"]) - float(P["roof_thick"]) - 0.012, (cb + tz) * 0.5), Vector3(hw3 * 2.0, 0.012, tz - cb - 0.1), Color(0.55, 0.52, 0.46))   # headliner, inside the glass
	_sw("RearSeat")
	var seats := [RZ - 0.35] if style == "blazer" else [cb + 0.55, RZ + 0.05]
	for sz in seats:
		black.box_at(Vector3(0, 0.78, sz), Vector3(w * 1.8, 0.14, 0.48), cloth)
		black.box(Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(0, 1.10, sz + 0.25)), Vector3(w * 1.8, 0.56, 0.10), cloth)


static func _flares(kit: RefCounted) -> void:
	var r: float = P["arch_r"] + 0.03
	var f: float = P["flare"]
	if f < 0.001:
		return          # the square body has plain openings, no flares
	for az in [FZ, RZ]:
		for s in [-1.0, 1.0]:
			var rings: Array = []
			var n := 16
			for i in range(n + 1):
				var a := lerpf(-0.18, PI + 0.18, float(i) / float(n))
				var c := Vector3(0, AXLE_Y + sin(a) * r, az + cos(a) * r)
				var w := _width(c.z) + float(P["bulge"]) * 0.4
				var outward := Vector3(0, sin(a), cos(a))
				var ring := PackedVector3Array()
				for p in [Vector2(w - 0.01, 0.0), Vector2(w + f, 0.0), Vector2(w + f, 0.05), Vector2(w - 0.01, 0.065)]:
					ring.append(Vector3((p as Vector2).x * s, 0, 0) + c + outward * (p as Vector2).y)
				rings.append(ring)
			kit.loft(rings, Color(0.05, 0.05, 0.05), true, true)


## A component's kits (DESIGN_NOTES 197: every component its own part - grille,
## bezels, headlamps, bumper, radiator... - its own node with its own meshes,
## so each can be looked at alone in the Model Lab ("solo <name>").
class Kits:
	var paint := MeshKit.new()
	var chrome := MeshKit.new()
	var black := MeshKit.new()
	var glass := MeshKit.new()
	var node: Node3D


static func _new_part(root: Node3D, nm: String) -> Kits:
	var k := Kits.new()
	k.node = Node3D.new()
	k.node.name = nm
	k.node.set_meta("part", true)
	root.add_child(k.node)
	return k


static func _end_part(k: Kits) -> void:
	_tone(k.paint)
	k.paint.smooth(34.0)
	k.chrome.smooth(50.0)
	k.black.smooth(40.0)
	k.glass.smooth(40.0)
	_add(k.node, k.paint, "Paint", _paint_mat())
	_add(k.node, k.chrome, "Chrome", _mat(Color.WHITE, 0.16, 1.0, true))
	_add(k.node, k.black, "Trim", _mat(Color.WHITE, 0.6, 0.0, true))
	_add(k.node, k.glass, "Glass", _glass_mat())


static func _front_end(_chrome: RefCounted, _black: RefCounted, _glass: RefCounted, root: Node3D) -> void:
	if String(t("front", "84")) == "84":
		_front_end_84(root)
	else:
		_front_end_73(root)


## (DESIGN_NOTES 200) the '81-'87 face, after Dave's black K10/K20 photos
## (reference/k10_80s): stacked rectangular lamps in bright-framed pods at each
## end, a dark charcoal egg-crate grille with three bright cross bars, one thin
## bright surround round the lot; chrome bumper with a black rub strip and a
## dark valance; amber reflectors on the fender corners. Each its own part.
static func _front_end_84(root: Node3D) -> void:
	var nz: float = P["nose_z"]
	var w: float = P["w"]
	var top: float = float(P["nose_y"]) - 0.012
	var bot := 0.835
	var paint: Color = P["paint"]
	var charcoal := Color(0.09, 0.09, 0.10)
	var silver := Color(0.80, 0.81, 0.82)
	var ox := w - float(P["nose_round"]) - 0.012
	var oy0 := bot
	var oy1 := top - 0.03
	var oc := (oy0 + oy1) * 0.5
	var ohh := (oy1 - oy0) * 0.5
	var pod := 0.235                                 # lamp pod width
	var gx := ox - pod - 0.02                        # grille half width
	# --- FrontPanel: header strip, the fender ends, the dark opening behind
	var k := _new_part(root, "FrontPanel")
	k.black.box_at(Vector3(0, top - 0.012, nz + 0.02), Vector3(w * 2.0 - 0.03, 0.03, 0.05), paint)
	var nr: float = P["nose_round"]
	for s in [-1.0, 1.0]:
		# the fender's front edge wraps round in a curve (not a squared-off box)
		k.black.cylinder(Transform3D(Basis.IDENTITY, Vector3(s * (w - nr), 0.78, nz + nr)), nr, nr, top - 0.78, 14, paint, true)
		k.black.box_at(Vector3(s * (w - nr - 0.03), (top + 0.78) * 0.5, nz + 0.03), Vector3(0.06, top - 0.78, 0.04), paint)
	k.black.box_at(Vector3(0, oc, nz + 0.12), Vector3(ox * 2.0, oy1 - oy0, 0.02), Color(0.015, 0.015, 0.015))
	k.black.box_at(Vector3(0, (0.78 + bot) * 0.5, nz + 0.04), Vector3(w * 2.0 - 0.06, bot - 0.78 + 0.01, 0.05), charcoal)   # filler under the grille
	_end_part(k)
	# --- GrilleSurround: a thin bright frame round the whole front, dividers at the pods
	k = _new_part(root, "GrilleSurround")
	_frame_loop(k.chrome, Vector3(0, oc, nz - 0.006), ox, ohh, 0.012, 0.009)
	for s in [-1.0, 1.0]:
		k.chrome.box_at(Vector3(s * (gx + 0.01), oc, nz - 0.004), Vector3(0.012, oy1 - oy0, 0.014), Color.WHITE)
	_end_part(k)
	# --- Grille: charcoal egg crate, cells wider than tall, three bright cross bars
	k = _new_part(root, "Grille")
	var gy0 := oy0 + 0.015
	var gy1 := oy1 - 0.015
	for i in range(0, 9):
		k.black.box_at(Vector3(0, lerpf(gy0, gy1, float(i) / 8.0), nz + 0.03), Vector3(gx * 2.0, 0.008, 0.05), charcoal)
	for i in range(0, 13):
		k.black.box_at(Vector3(lerpf(-gx, gx, float(i) / 12.0), oc, nz + 0.03), Vector3(0.008, gy1 - gy0, 0.05), charcoal)
	for fy in [0.25, 0.5, 0.75]:
		k.chrome.box_at(Vector3(0, lerpf(gy0, gy1, fy), nz + 0.002), Vector3(gx * 2.0, 0.012 if fy != 0.5 else 0.02, 0.016), silver)
	k.chrome.box_at(Vector3(0, oc, nz - 0.004), Vector3(0.14, 0.05, 0.012), silver)      # the plain badge plate in the middle (no name)
	_end_part(k)
	for s in [-1.0, 1.0]:
		var sd := "L" if s < 0.0 else "R"
		var px: float = s * (ox - pod * 0.5 - 0.005)
		# --- HeadlampBezel: the pod's bright frame, a dark recess for each lamp
		k = _new_part(root, "HeadlampBezel" + sd)
		var uy := oc + ohh * 0.47
		var ly := oc - ohh * 0.47
		for ly2 in [uy, ly]:
			_frame_loop(k.chrome, Vector3(px, ly2, nz - 0.002), pod * 0.5 - 0.012, ohh * 0.47 - 0.008, 0.008, 0.007)
			k.black.box_at(Vector3(px, ly2, nz + 0.085), Vector3(pod - 0.03, ohh * 0.94 - 0.03, 0.01), Color(0.07, 0.07, 0.08))   # back plate (behind the lamp's bowl)
		_end_part(k)
		# --- Headlamp (upper) and ParkLamp (lower): real lamps you can see into -
		# a chrome reflector bowl, the bulb in the middle of it (it lights), and
		# a clear glass lens with fluted texture over the front
		var lw := pod - 0.05
		var lh := ohh * 0.94 - 0.05
		k = _new_part(root, "Headlamp" + sd)
		_lamp_unit(k, root, Vector3(px, uy, nz), lw, lh, "HeadLamp%dBulb" % int(s), Color(0.95, 0.95, 0.92))
		_end_part(k)
		_lens_glass(k.node, Vector3(px, uy, nz + 0.006), lw, lh)
		k = _new_part(root, "ParkLamp" + sd)
		_lamp_unit(k, root, Vector3(px, ly, nz), lw, lh, "ParkLamp%dBulb" % int(s), Color(1.0, 0.62, 0.12))
		_end_part(k)
		_lens_glass(k.node, Vector3(px, ly, nz + 0.006), lw, lh, Color(1.0, 0.62, 0.12, 0.45))      # amber parking lamp
		# --- SideMarker: amber reflector on the fender's front corner, low
		k = _new_part(root, "SideMarker" + sd)
		var mz := nz + 0.13
		var mx: float = s * (_width(mz) + float(P["bulge"]) + 0.003)
		k.chrome.box_at(Vector3(mx - s * 0.003, 0.86, mz), Vector3(0.008, 0.05, 0.16), Color.WHITE)
		_end_part(k)
		_bulb(k.node, "FrontMarker%dBulb" % int(s), Vector3(mx, 0.86, mz), Vector3(0.012, 0.04, 0.145), Color(1.0, 0.62, 0.12))
	# --- Bumper: tall chrome face, a black rub strip along it, ends wrapping back
	k = _new_part(root, "Bumper")
	var rings: Array = []
	var by0 := 0.55
	var by1 := 0.775
	for i in range(41):
		var x := lerpf(-w - 0.025, w + 0.025, float(i) / 40.0)
		var wrap := pow(absf(x) / (w + 0.025), 12.0) * 0.16
		var z := nz - 0.12 + wrap
		var ring := PackedVector3Array()
		var prof := [Vector2(0.0, by1), Vector2(-0.015, by1 - 0.004), Vector2(-0.028, by1 - 0.02), Vector2(-0.032, by1 - 0.06),
			Vector2(-0.034, by0 + 0.06), Vector2(-0.03, by0 + 0.02), Vector2(-0.016, by0 + 0.003), Vector2(0.0, by0), Vector2(0.10, by0 + 0.01), Vector2(0.10, by1 - 0.01)]
		for q in prof:
			ring.append(Vector3(x, (q as Vector2).y, z + (q as Vector2).x))
		rings.append(ring)
	k.chrome.loft(rings, Color.WHITE, true, true)
	var strip: Array = []
	for i in range(31):
		var x2 := lerpf(-w + 0.02, w - 0.02, float(i) / 30.0)
		strip.append(Vector3(x2, (by0 + by1) * 0.5 + 0.005, nz - 0.12 + pow(absf(x2) / (w + 0.025), 12.0) * 0.16 - 0.036))
	_tube(k.black, strip, 0.016, Color(0.03, 0.03, 0.03), 10)
	for s in [-1.0, 1.0]:
		k.black.box_at(Vector3(s * 0.45, 0.66, nz - 0.0), Vector3(0.06, 0.10, 0.16), Color(0.06, 0.06, 0.06))   # brackets
	_end_part(k)
	# --- Winch: on a cradle in front of the bumper - drum with the cable wound
	# on, motor one end, gearbox and clutch lever the other, a roller fairlead
	k = _new_part(root, "Winch")
	var wz := nz - 0.20
	k.black.box_at(Vector3(0, 0.585, wz + 0.02), Vector3(0.62, 0.02, 0.20), Color(0.06, 0.06, 0.06))     # cradle plate
	k.black.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.16, 0.66, wz)), 0.055, 0.055, 0.32, 24, Color(0.08, 0.08, 0.08), true)   # drum ends
	k.chrome.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.15, 0.66, wz)), 0.05, 0.05, 0.30, 24, Color(0.55, 0.56, 0.56), true)    # cable on the drum
	k.black.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.16, 0.66, wz)), 0.065, 0.065, 0.18, 24, Color(0.07, 0.07, 0.07), true)   # motor
	k.black.box_at(Vector3(0.24, 0.66, wz), Vector3(0.10, 0.14, 0.13), Color(0.07, 0.07, 0.07))           # gearbox
	k.chrome.box(Transform3D(Basis(Vector3.BACK, 0.4), Vector3(0.24, 0.75, wz)), Vector3(0.012, 0.07, 0.012), Color(0.75, 0.1, 0.08))   # clutch lever
	_frame_loop(k.chrome, Vector3(0, 0.66, wz - 0.09), 0.10, 0.045, 0.01, 0.012)                      # roller fairlead frame
	for xr in [-0.06, 0.06]:
		k.chrome.cylinder(Transform3D(Basis.IDENTITY, Vector3(xr, 0.62, wz - 0.09)), 0.016, 0.016, 0.08, 12, Color(0.7, 0.7, 0.7), true)
	_end_part(k)
	k = _new_part(root, "Valance")
	k.black.box_at(Vector3(0, 0.515, nz - 0.03), Vector3(w * 1.75, 0.07, 0.06), charcoal)
	_end_part(k)
	k = _new_part(root, "Plate")
	k.black.box_at(Vector3(0, 0.66, nz - 0.162), Vector3(0.32, 0.16, 0.006), Color(0.80, 0.78, 0.70))
	_end_part(k)
	k = _new_part(root, "TowHooks")
	for s in [-1.0, 1.0]:
		k.black.box_at(Vector3(s * 0.42, 0.52, nz - 0.03), Vector3(0.08, 0.06, 0.012), Color(0.05, 0.05, 0.05))
		var hk: Array = []
		for j in range(13):
			var aa := lerpf(0.0, PI * 1.25, float(j) / 12.0)
			hk.append(Vector3(s * 0.42, 0.52 - 0.035 + cos(aa) * 0.035, nz - 0.06 - sin(aa) * 0.035))
		_tube(k.black, hk, 0.011, Color(0.05, 0.05, 0.05))
	_end_part(k)
	_radiator_part(root)


static func _front_end_73(root: Node3D) -> void:
	# (DESIGN_NOTES 194/197) the '73-'74 face, after the reference photos
	# (reference/squarebody/01, 04 and Dave's), each component its own part:
	# FrontPanel (header, filler, slot), GrilleSurround (one bright frame from
	# headlamp to headlamp), Grille (fine egg crate, cells twice as wide as tall),
	# HeadlampBezelL/R (square recessed bezels), HeadlampL/R (reflector bowl,
	# trim ring, clear domed lens = the bulb), ParkLampL/R, SideMarkerL/R,
	# Bumper (flat face, raised band, bolts), Valance, TowHooks, Plate.
	var nz: float = P["nose_z"]
	var w: float = P["w"]
	var top: float = float(P["nose_y"]) - 0.012         # right under the hood lip
	var bot := 0.885                                    # bottom of the bright frame
	var paint: Color = P["paint"]
	var silver := Color(0.78, 0.79, 0.80)
	var ox := w - 0.085
	var oy0 := bot
	var oy1 := top - 0.035
	var oc := (oy0 + oy1) * 0.5
	var ohh := (oy1 - oy0) * 0.5
	var gx := 0.57
	# --- FrontPanel: header over the frame, filler under it, the fender ends
	var k := _new_part(root, "FrontPanel")
	k.black.box_at(Vector3(0, top - 0.015, nz + 0.02), Vector3(w * 2.0 - 0.03, 0.035, 0.05), paint)
	k.black.box_at(Vector3(0, (0.785 + bot) * 0.5, nz + 0.03), Vector3(w * 2.0 - 0.05, bot - 0.785, 0.05), paint)
	for s in [-1.0, 1.0]:
		k.black.box_at(Vector3(s * (w - 0.045), (top + 0.785) * 0.5, nz + 0.02), Vector3(0.07, top - 0.785, 0.05), paint)
	# the slot under the grille, its little vertical bars
	k.black.box_at(Vector3(0, bot - 0.045, nz + 0.012), Vector3(1.0, 0.035, 0.02), Color(0.02, 0.02, 0.02))
	for i in range(1, 16):
		k.chrome.box_at(Vector3(lerpf(-0.5, 0.5, float(i) / 16.0), bot - 0.045, nz + 0.006), Vector3(0.006, 0.033, 0.012), silver)
	k.black.box_at(Vector3(0, oc, nz + 0.12), Vector3(ox * 2.0, oy1 - oy0, 0.02), Color(0.02, 0.02, 0.02))     # dark behind the opening
	_end_part(k)
	# --- GrilleSurround: the bright frame round the whole opening
	k = _new_part(root, "GrilleSurround")
	_frame_loop(k.chrome, Vector3(0, oc, nz - 0.008), ox, ohh, 0.03, 0.016)
	k.chrome.box_at(Vector3(0, oy1 - 0.004, nz), Vector3(ox * 2.0, 0.03, 0.03), Color.WHITE)
	k.chrome.box_at(Vector3(0, oy0 + 0.004, nz), Vector3(ox * 2.0, 0.03, 0.03), Color.WHITE)
	_end_part(k)
	# --- Grille: its own frame, 8 rows x 14 columns of deep bright bars
	k = _new_part(root, "Grille")
	var gy0 := oy0 + 0.03
	var gy1 := oy1 - 0.03
	_frame_loop(k.chrome, Vector3(0, oc, nz + 0.005), gx, (gy1 - gy0) * 0.5, 0.012, 0.011)
	for i in range(1, 8):
		k.chrome.box_at(Vector3(0, lerpf(gy0, gy1, float(i) / 8.0), nz + 0.04), Vector3(gx * 2.0, 0.012, 0.06), silver)
	for i in range(1, 14):
		k.chrome.box_at(Vector3(lerpf(-gx, gx, float(i) / 14.0), oc, nz + 0.04), Vector3(0.01, gy1 - gy0, 0.06), silver)
	_end_part(k)
	for s in [-1.0, 1.0]:
		var sd := "L" if s < 0.0 else "R"
		var hc := Vector3(s * (gx + (ox - gx) * 0.5 + 0.005), oc, nz)
		var hb := (ox - gx) * 0.5 - 0.02
		# --- HeadlampBezel: square bright bezel, the recess stepping back into it
		k = _new_part(root, "HeadlampBezel" + sd)
		_frame_loop(k.chrome, hc, hb, minf(hb, ohh - 0.02), 0.025, 0.018)
		var bh := minf(hb, ohh - 0.02)
		for e2 in [[Vector3(0, bh - 0.02, 0.004), Vector3(hb * 2.0 - 0.02, 0.03, 0.01)], [Vector3(0, -bh + 0.02, 0.004), Vector3(hb * 2.0 - 0.02, 0.03, 0.01)],
				[Vector3(hb - 0.02, 0, 0.004), Vector3(0.03, bh * 2.0 - 0.02, 0.01)], [Vector3(-hb + 0.02, 0, 0.004), Vector3(0.03, bh * 2.0 - 0.02, 0.01)]]:
			k.chrome.box_at(hc + (e2[0] as Vector3), e2[1], Color(0.85, 0.86, 0.86))
		for e in [[Vector3(0, hb - 0.01, 0.035), Vector3(hb * 2.0, 0.012, 0.07)], [Vector3(0, -hb + 0.01, 0.035), Vector3(hb * 2.0, 0.012, 0.07)],
				[Vector3(hb - 0.01, 0, 0.035), Vector3(0.012, hb * 2.0, 0.07)], [Vector3(-hb + 0.01, 0, 0.035), Vector3(0.012, hb * 2.0, 0.07)]]:
			k.black.box_at(hc + (e[0] as Vector3), e[1], Color(0.10, 0.10, 0.11))
		k.black.box_at(hc + Vector3(0, 0, 0.07), Vector3(hb * 2.0, hb * 2.0, 0.01), Color(0.12, 0.12, 0.13))
		_end_part(k)
		# --- Headlamp: reflector bowl, trim ring with its screws, the domed lens (the bulb)
		k = _new_part(root, "Headlamp" + sd)
		k.chrome.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), hc + Vector3(0, 0, 0.065)), 0.075, 0.091, 0.04, 32, Color.WHITE, false)
		_ring(k.chrome, hc + Vector3(0, 0, 0.012), 0.091, 0.008)
		for a in [0.6, 2.2, 4.0]:
			k.chrome.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), hc + Vector3(cos(a) * 0.098, sin(a) * 0.098, 0.006)), 0.006, 0.004, 0.004, 10, Color.WHITE, true)
		_end_part(k)
		_lens(k.node, "HeadLamp%dBulb" % int(s), hc + Vector3(0, 0, 0.016), 0.089, 0.018)
		# --- ParkLamp: amber lens in a bright rim, in the filler under the headlamp
		k = _new_part(root, "ParkLamp" + sd)
		var pc := Vector3(hc.x, 0.835, nz)
		_frame_loop(k.chrome, pc, 0.10, 0.028, 0.01, 0.006)
		_end_part(k)
		_bulb(k.node, "ParkLamp%dBulb" % int(s), pc + Vector3(0, 0, 0.004), Vector3(0.19, 0.05, 0.012), Color(1.0, 0.62, 0.12))
		# --- SideMarker on the fender
		k = _new_part(root, "SideMarker" + sd)
		var mz := nz + 0.17
		var mx: float = s * (_width(mz) + float(P["bulge"]) + 0.003)
		k.chrome.box_at(Vector3(mx - s * 0.003, 0.98, mz), Vector3(0.008, 0.045, 0.115), Color.WHITE)
		_end_part(k)
		_bulb(k.node, "FrontMarker%dBulb" % int(s), Vector3(mx, 0.98, mz), Vector3(0.012, 0.035, 0.10), Color(1.0, 0.62, 0.12))
	# --- Bumper: flat face, a raised band, rolled edges, ends wrapping back, bolts
	k = _new_part(root, "Bumper")
	var rings: Array = []
	var by0 := 0.56
	var by1 := 0.785
	for i in range(41):
		var x := lerpf(-w - 0.03, w + 0.03, float(i) / 40.0)
		var wrap := pow(absf(x) / (w + 0.03), 10.0) * 0.14
		var z := nz - 0.13 + wrap
		var ring := PackedVector3Array()
		var prof := [Vector2(0.0, by1 - 0.005), Vector2(-0.012, by1 - 0.002), Vector2(-0.022, by1 - 0.02), Vector2(-0.024, by1 - 0.06),
			Vector2(-0.034, by1 - 0.075), Vector2(-0.036, by1 - 0.12), Vector2(-0.024, by1 - 0.135), Vector2(-0.022, by0 + 0.03),
			Vector2(-0.012, by0 + 0.004), Vector2(0.0, by0), Vector2(0.09, by0 + 0.01), Vector2(0.09, by1 - 0.01)]
		for q in prof:
			ring.append(Vector3(x, (q as Vector2).y, z + (q as Vector2).x))
		rings.append(ring)
	k.chrome.loft(rings, Color.WHITE, true, true)
	for bx in [-0.75, -0.45, -0.15, 0.15, 0.45, 0.75]:
		k.chrome.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(bx, by1 - 0.04, nz - 0.152)), 0.009, 0.006, 0.006, 12, Color(0.9, 0.9, 0.9), true)
	# brackets back to the frame horns
	for s in [-1.0, 1.0]:
		k.black.box_at(Vector3(s * 0.45, 0.66, nz - 0.0), Vector3(0.06, 0.10, 0.16), Color(0.06, 0.06, 0.06))
	_end_part(k)
	k = _new_part(root, "Valance")
	k.black.box_at(Vector3(0, 0.52, nz - 0.02), Vector3(w * 1.7, 0.07, 0.06), paint)
	_end_part(k)
	k = _new_part(root, "Plate")
	k.black.box_at(Vector3(0, 0.665, nz - 0.172), Vector3(0.32, 0.16, 0.006), Color(0.80, 0.78, 0.70))
	_end_part(k)
	k = _new_part(root, "TowHooks")
	for s in [-1.0, 1.0]:
		# a real J hook: a bent bar off a mounting plate
		k.black.box_at(Vector3(s * 0.42, 0.53, nz - 0.03), Vector3(0.08, 0.06, 0.012), Color(0.30, 0.20, 0.10))
		var hk: Array = []
		for j in range(13):
			var aa := lerpf(0.0, PI * 1.25, float(j) / 12.0)
			hk.append(Vector3(s * 0.42, 0.53 - 0.035 + cos(aa) * 0.035, nz - 0.06 - sin(aa) * 0.035))
		_tube(k.black, hk, 0.011, Color(0.30, 0.20, 0.10))
	_end_part(k)
	_radiator_part(root)


static func _radiator_part(root: Node3D) -> void:
	var nz: float = P["nose_z"]
	var k: Kits
	# --- Radiator: core with fins, side tanks' brackets, top and bottom tanks,
	# the cap, the hoses to the engine
	k = _new_part(root, "Radiator")
	var rz := nz + 0.20
	k.black.box_at(Vector3(0, 0.90, rz), Vector3(0.74, 0.46, 0.05), Color(0.09, 0.09, 0.09))
	for i in range(23):
		k.black.box_at(Vector3(0, lerpf(0.68, 1.12, float(i) / 22.0), rz - 0.026), Vector3(0.74, 0.004, 0.004), Color(0.16, 0.16, 0.15))   # fins
	k.black.box_at(Vector3(0, 1.15, rz), Vector3(0.78, 0.05, 0.08), Color(0.14, 0.13, 0.12))     # top tank
	k.black.box_at(Vector3(0, 0.655, rz), Vector3(0.78, 0.05, 0.08), Color(0.14, 0.13, 0.12))    # bottom tank
	for s in [-1.0, 1.0]:
		k.black.box_at(Vector3(s * 0.40, 0.90, rz), Vector3(0.025, 0.55, 0.07), Color(0.12, 0.12, 0.12))  # side brackets
	k.chrome.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.22, 1.175, rz)), 0.025, 0.025, 0.02, 20, Color.WHITE, true)   # cap
	var ez := engine_z()
	_tube(k.black, [Vector3(-0.2, 1.12, rz + 0.04), Vector3(-0.12, 1.08, rz + 0.2), Vector3(-0.04, 1.0, ez - 0.36)], 0.025, Color(0.05, 0.05, 0.05))      # upper hose
	_tube(k.black, [Vector3(0.25, 0.70, rz + 0.04), Vector3(0.16, 0.72, rz + 0.2), Vector3(0.04, 0.80, ez - 0.36)], 0.025, Color(0.05, 0.05, 0.05))       # lower hose
	_end_part(k)


## A lamp's insides (DESIGN_NOTES 205): a chrome reflector bowl stepping back
## from the lens to a small round socket, and the bulb in it (named so the
## truck lights it). The glass goes on after (_lens_glass).
static func _lamp_unit(k: Kits, root: Node3D, c: Vector3, lw: float, lh: float, bulb_name: String, col: Color) -> void:
	var rings: Array = []
	for st in [[0.0, 1.0], [0.018, 0.82], [0.036, 0.58], [0.052, 0.32], [0.06, 0.18]]:
		var dz: float = st[0]
		var f: float = st[1]
		var ring := PackedVector3Array()
		var hw := lw * 0.5 * f
		var hh := lh * 0.5 * f
		var rr := minf(hw, hh) * (0.25 + 0.75 * (1.0 - f))      # corners round off toward the back
		for ci in range(4):
			var cxs := [Vector2(hw - rr, hh - rr), Vector2(-hw + rr, hh - rr), Vector2(-hw + rr, -hh + rr), Vector2(hw - rr, -hh + rr)]
			for kk in range(4):
				var a := (float(ci) + float(kk) / 3.0) * PI * 0.5
				ring.append(Vector3(c.x + (cxs[ci] as Vector2).x + cos(a) * rr, c.y + (cxs[ci] as Vector2).y + sin(a) * rr, c.z + 0.012 + dz))
		rings.append(ring)
	# a bowl: you look into it, so its faces are turned inward (a loft points them out)
	var bowl := MeshKit.new()
	bowl.loft(rings, Color(0.95, 0.95, 0.96), false, true)
	for i in range(0, bowl.verts.size(), 3):
		var v1: Vector3 = bowl.verts[i + 1]
		bowl.verts[i + 1] = bowl.verts[i + 2]
		bowl.verts[i + 2] = v1
		for j in range(3):
			bowl.norms[i + j] = -bowl.norms[i + j]
	k.chrome.verts.append_array(bowl.verts)
	k.chrome.norms.append_array(bowl.norms)
	k.chrome.cols.append_array(bowl.cols)
	k.black.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c + Vector3(0, 0, 0.06)), 0.018, 0.018, 0.02, 16, Color(0.2, 0.2, 0.2), true)   # socket
	var mi := MeshInstance3D.new()
	mi.name = bulb_name
	var sm := SphereMesh.new()
	sm.radius = 0.016
	sm.height = 0.04
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.position = c + Vector3(0, 0, 0.045)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	k.node.add_child(mi)


## A small round bulb (lights up: pickup_truck finds *Bulb).
static func _round_bulb(root: Node3D, nm: String, at: Vector3, r: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.4
	sm.radial_segments = 14
	sm.rings = 7
	mi.mesh = sm
	mi.position = at
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _flute_tex() -> ImageTexture:
	if _flutes == null:
		_lens_glass(null, Vector3.ZERO, 0.1, 0.1)
	return _flutes


## Clear lamp glass with the fluted texture (vertical ribs and a fine grid).
static var _flutes: ImageTexture
static func _lens_glass(parent: Node3D, c: Vector3, lw: float, lh: float, tint: Color = Color(0.92, 0.95, 0.97, 0.12)) -> void:
	if _flutes == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
		for y in range(64):
			for x in range(64):
				# a normal map: the sealed beam's little prism cells (8 x 8 px each),
				# taller than wide like the real glass
				var nx := sin(float(x) / 8.0 * TAU) * 0.6
				var ny := sin(float(y) / 8.0 * TAU) * 0.35
				img.set_pixel(x, y, Color(0.5 + nx * 0.5, 0.5 + ny * 0.5, 1.0))
		_flutes = ImageTexture.create_from_image(img)
	if parent == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Lens"
	var bm := BoxMesh.new()
	bm.size = Vector3(lw + 0.006, lh + 0.006, 0.006)
	mi.mesh = bm
	mi.position = c
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic_specular = 1.0
	m.normal_enabled = true
	m.normal_texture = _flutes
	m.normal_scale = 0.5
	m.uv1_scale = Vector3(lw / 0.11, lh / 0.15, 1.0)          # cells ~14 x 19 mm
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## A headlamp lens that is also its bulb (so it lights): a shallow dome.
static func _lens(root: Node3D, nm: String, at: Vector3, radius: float, depth: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = depth * 2.0
	sm.radial_segments = 32
	sm.rings = 8
	sm.is_hemisphere = true
	mi.mesh = sm
	mi.position = at
	mi.rotation = Vector3(-PI * 0.5, 0, 0)          # the dome bulges forward (-z)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.87, 0.88)
	m.roughness = 0.08
	m.metallic = 0.6
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## A rounded-rectangle loop of round tube (grille surround, lamp bezels).
static func _frame_loop(kit: RefCounted, c: Vector3, hw: float, hh: float, corner: float, r: float) -> void:
	var path: Array = []
	var corners := [Vector2(hw - corner, hh - corner), Vector2(-hw + corner, hh - corner), Vector2(-hw + corner, -hh + corner), Vector2(hw - corner, -hh + corner)]
	for ci in range(4):
		for k in range(5):
			var a := (float(ci) + float(k) / 4.0) * PI * 0.5
			path.append(Vector3(c.x + corners[ci].x + cos(a) * corner, c.y + corners[ci].y + sin(a) * corner, c.z))
	path.append(path[0])
	_tube(kit, path, r)


## A circle of round tube facing the front (lamp trim rings).
static func _ring(kit: RefCounted, c: Vector3, radius: float, r: float) -> void:
	var path: Array = []
	for k in range(25):
		var a := TAU * float(k) / 24.0
		path.append(c + Vector3(cos(a) * radius, sin(a) * radius, 0))
	_tube(kit, path, r)


static func _tube(kit: RefCounted, path: Array, r: float, col: Color = Color.WHITE, sides: int = 12) -> void:
	if path.size() < 2:
		return
	var rings: Array = []
	var n := Vector3.ZERO
	for i in range(path.size()):
		var p: Vector3 = path[i]
		var nxt: Vector3 = path[mini(i + 1, path.size() - 1)]
		var prv: Vector3 = path[maxi(i - 1, 0)]
		var tg := (nxt - prv).normalized()
		if i == 0:
			n = tg.cross(Vector3.UP if absf(tg.y) < 0.9 else Vector3.RIGHT).normalized()
		else:
			n = (n - tg * n.dot(tg)).normalized()          # carried along the bend (no twist)
		var bn := tg.cross(n)
		var ring := PackedVector3Array()
		for k in range(sides):
			var a := TAU * float(k) / float(sides)
			ring.append(p + (n * cos(a) + bn * sin(a)) * r)
		rings.append(ring)
	kit.loft(rings, col, true, true)


## A smooth path through control points (Catmull-Rom), `per` points a span.
static func _curve(ctl: Array, per: int = 6) -> Array:
	var out: Array = []
	for i in range(ctl.size() - 1):
		var p0: Vector3 = ctl[maxi(i - 1, 0)]
		var p1: Vector3 = ctl[i]
		var p2: Vector3 = ctl[i + 1]
		var p3: Vector3 = ctl[mini(i + 2, ctl.size() - 1)]
		for j in range(per):
			var t := float(j) / float(per)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctl[ctl.size() - 1])
	return out


## A shallow domed lens facing forward.
static func _dome(kit: RefCounted, c: Vector3, radius: float, depth: float) -> void:
	var rings: Array = []
	for k in range(6):
		var f := float(k) / 5.0
		var rr: float = radius * cos(f * PI * 0.5) + 0.0005
		var ring := PackedVector3Array()
		for j in range(24):
			var a := TAU * float(j) / 24.0
			ring.append(c + Vector3(cos(a) * rr, sin(a) * rr, -depth * sin(f * PI * 0.5)))
		rings.append(ring)
	kit.loft(rings, Color.WHITE, false, true)


static func _rear_end(chrome: RefCounted, black: RefCounted, glass: RefCounted, root: Node3D) -> void:
	# (DESIGN_NOTES 201) the '81-'87 rear, after the K10 photos: tall tail lamps
	# set deep into the bed corners - a bright bezel, a red lens with horizontal
	# flutes and the white reverse band across it; a chrome step bumper with real
	# depth, rolled edges, wrapped ends, a rubber step pad, the plate in a recess
	var tz: float = P["tail_z"]
	var w: float = P["w"]
	_sw("BedCorners")
	# the bed's rear corner posts: they finish the bed sides flush, carry the tail
	# lamps on their back and outer faces, and the tailgate swings between them
	var wo := _width(tz - CORNER) + float(P["bulge"])
	for s in [-1.0, 1.0]:
		var yb: float = float(P["bed_bottom"]) if not suv() else float(P["rocker_y"])
		var yt: float = float(P["rail_y"])
		var xi := w - 0.185
		if not suv():
			continue          # the pickup's corner is part of the one-piece bed side (_bed_side_full)
		# painted like the panels round it: the paint shader bands it (alpha 0)
		(_K["paint"] as RefCounted).box_at(Vector3(s * (xi + wo) * 0.5, (yb + yt) * 0.5, tz - CORNER * 0.5 + 0.003), Vector3(wo - xi, yt - yb, CORNER + 0.006), Color(1, 1, 1, 0))
	_sw("TailLamps")
	var tzl: float = tz + float(P["bulge"]) + 0.002     # on the one-piece bed side's back face (it carries the bulge round)
	for s in [-1.0, 1.0]:
		# the square body's tail lamp (reference k10_80s/03): it bends round the
		# corner of the body - the rear face, a rounded corner, a short wrap down
		# the side; a bright bezel all round, a stippled reflector strip on the
		# inboard edge, the white reverse lens low in the middle, four screws
		var y0 := 0.90
		var y1 := 1.15
		var wb := _width(tzl - CORNER) + float(P["bulge"]) + 0.005    # flush on the corner post's side
		var path: Array = []                                  # plan outline, inboard to the side
		var xi := wb - 0.17
		var rc := BED_RC
		path.append(Vector2(xi, tzl + 0.008))
		path.append(Vector2(wb - rc, tzl + 0.008))
		for k in range(1, 7):
			var a := lerpf(PI * 0.5, 0.0, float(k) / 6.0)
			path.append(Vector2(wb - rc + cos(a) * (rc + 0.008), tzl - rc + sin(a) * (rc + 0.008)))
		path.append(Vector2(wb + 0.008, tzl - 0.10))
		var lens := MeshKit.new()
		var refl := MeshKit.new()
		for i in range(path.size() - 1):
			var p0: Vector2 = path[i]
			var p1: Vector2 = path[i + 1]
			var outn := Vector3(p1.y - p0.y, 0, -(p1.x - p0.x)).normalized() * -1.0
			outn = Vector3(outn.x * s, 0, outn.z)
			var kk := refl if i == 0 and p1.x - p0.x > 0.1 else lens
			if i == 0:
				# split the first (rear) run: reflector strip, then lens
				var pm := Vector2(p0.x + 0.035, p0.y)
				refl.quad(Vector3(s * p0.x, y0 + 0.012, p0.y), Vector3(s * pm.x, y0 + 0.012, pm.y), Vector3(s * pm.x, y1 - 0.012, pm.y), Vector3(s * p0.x, y1 - 0.012, p0.y), Color.WHITE, Vector3(0, 0, 1))
				p0 = pm
				kk = lens
			kk.quad(Vector3(s * p0.x, y0 + 0.012, p0.y), Vector3(s * p1.x, y0 + 0.012, p1.y), Vector3(s * p1.x, y1 - 0.012, p1.y), Vector3(s * p0.x, y1 - 0.012, p0.y), Color.WHITE, Vector3(s * (p1.y - p0.y) * 0.0, 0, 0) + _out2(p0, p1, s))
		lens.smooth(60.0)
		refl.smooth(60.0)
		# the lens is red GLASS (DESIGN_NOTES 206): see-through, with fine
		# horizontal flutes; behind it a bright reflector and two real bulbs
		# (they're what lights up), like the headlamps
		var lmi: MeshInstance3D = lens.instance("TailLens%d" % int(s))
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.85, 0.04, 0.03, 0.55)
		lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lmat.roughness = 0.05
		lmat.metallic_specular = 1.0
		lmat.normal_enabled = true
		lmat.normal_texture = _flute_tex()
		lmat.normal_scale = 0.45
		lmat.uv1_triplanar = true
		lmat.uv1_scale = Vector3(9.0, 7.0, 9.0)
		lmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		lmi.material_override = lmat
		lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(lmi)
		var bx: float = s * (xi + 0.105)
		chrome.box_at(Vector3(bx, (y0 + y1) * 0.5, tzl - 0.016), Vector3(0.15, y1 - y0 - 0.02, 0.006), Color(0.85, 0.85, 0.86))   # the reflector
		for by in [y0 + 0.085, y1 - 0.06]:
			chrome.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(bx, by, tzl - 0.012)), 0.022, 0.016, 0.01, 14, Color(0.9, 0.9, 0.9), true)   # each bulb's cup
		_round_bulb(root, "TailLamp%dBulb" % int(s), Vector3(bx, y1 - 0.06, tzl - 0.004), 0.016, Color(0.95, 0.30, 0.25))
		_round_bulb(root, "TailLamp%dLowerBulb" % int(s), Vector3(bx, y0 + 0.085, tzl - 0.004), 0.016, Color(0.95, 0.30, 0.25))
		_bulb_mesh(root, "TailLampLow%dBulb" % int(s), refl, Color(0.70, 0.04, 0.03))
		# the bezel: a bright tube round the outline (top, bottom, the two ends)
		var top_path: Array = []
		var bot_path: Array = []
		for q in path:
			top_path.append(Vector3(s * (q as Vector2).x, y1, (q as Vector2).y + 0.003))
			bot_path.append(Vector3(s * (q as Vector2).x, y0, (q as Vector2).y + 0.003))
		_tube(chrome, top_path, 0.009, Color.WHITE, 8)
		_tube(chrome, bot_path, 0.009, Color.WHITE, 8)
		_tube(chrome, [Vector3(s * xi, y0, tzl + 0.011), Vector3(s * xi, y1, tzl + 0.011)], 0.009, Color.WHITE, 8)
		var pe: Vector2 = path[path.size() - 1]
		_tube(chrome, [Vector3(s * (pe.x + 0.003), y0, pe.y), Vector3(s * (pe.x + 0.003), y1, pe.y)], 0.009, Color.WHITE, 8)
		black.box_at(Vector3(s * (xi + 0.08), (y0 + y1) * 0.5, tzl - 0.035), Vector3(0.16, y1 - y0, 0.03), Color(0.03, 0.03, 0.03))   # housing (behind the reflector)
		# reverse lens and screws on the rear face
		var rx: float = s * (xi + 0.10)
		_bulb(root, "ReverseLamp%dBulb" % int(s), Vector3(rx, y0 + 0.04, tzl + 0.013), Vector3(0.07, 0.045, 0.008), Color(0.92, 0.92, 0.9))
		for e in [Vector2(xi + 0.025, y0 + 0.022), Vector2(xi + 0.025, y1 - 0.022), Vector2(wb - 0.05, y0 + 0.022), Vector2(wb - 0.05, y1 - 0.022)]:
			chrome.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(s * e.x, e.y, tzl + 0.012)), 0.006, 0.006, 0.004, 8, Color.WHITE, true)
	_sw("RearBumper")
	var rings: Array = []
	var by0 := 0.55
	var by1 := 0.72
	var bz := tz + 0.11
	for i in range(41):
		var x := lerpf(-w - 0.03, w + 0.03, float(i) / 40.0)
		var wrap := pow(absf(x) / (w + 0.03), 12.0) * 0.14
		var ring := PackedVector3Array()
		# from the step's back edge, over the top, down the face, under
		var prof := [Vector2(-0.13, by1 - 0.004), Vector2(-0.01, by1), Vector2(0.008, by1 - 0.006), Vector2(0.014, by1 - 0.02),
			Vector2(0.016, by0 + 0.03), Vector2(0.01, by0 + 0.006), Vector2(-0.005, by0), Vector2(-0.13, by0 + 0.01)]
		for q in prof:
			ring.append(Vector3(x, (q as Vector2).y, bz - wrap + (q as Vector2).x))
		rings.append(ring)
	chrome.loft(rings, Color.WHITE, true, true)
	black.box_at(Vector3(0, by1 + 0.004, bz - 0.06), Vector3(0.62, 0.008, 0.10), Color(0.03, 0.03, 0.03))     # rubber step pad
	for i in range(8):
		black.box_at(Vector3(lerpf(-0.28, 0.28, float(i) / 7.0), by1 + 0.01, bz - 0.06), Vector3(0.012, 0.004, 0.09), Color(0.05, 0.05, 0.05))   # its ribs
	black.box_at(Vector3(0, 0.625, bz + 0.004), Vector3(0.36, 0.17, 0.01), Color(0.04, 0.04, 0.04))          # the plate recess
	for s2 in [-1.0, 1.0]:
		black.box_at(Vector3(s2 * 0.45, 0.62, bz - 0.12), Vector3(0.06, 0.08, 0.14), Color(0.06, 0.06, 0.06))   # brackets to the frame
	_bulb(root, "PlateLampBulb", Vector3(0, 0.715, bz + 0.012), Vector3(0.05, 0.012, 0.012), Color(0.9, 0.9, 0.85))
	_sw("RearPlate")
	black.box_at(Vector3(0, 0.62, bz + 0.012), Vector3(0.30, 0.15, 0.004), Color(0.80, 0.78, 0.70))      # plate (blank)


## Raised lettering pressed out of a panel facing +z: the word laid out with
## a heavy block font, stretched to fill `width` x `height` (the old trucks'
## letters are wide and spaced out), standing `depth` proud of z0, added to
## `kit` as part of the panel (so it's painted with it).
static func _stamp_text(kit: RefCounted, txt: String, centre: Vector3, width: float, height: float, depth: float) -> void:
	# block letters drawn as straight strokes (the old tailgate lettering is
	# squared-off and heavy), each stroke a raised slab pressed out of the panel
	var k := 0.24                                   # stroke weight, of the letter's height
	var strokes := {
		"H": [[0, 0, k, 1], [1 - k, 0, 1, 1], [k, 0.39, 1 - k, 0.61]],
		"A": [[0, 0, k, 1], [1 - k, 0, 1, 1], [k, 1 - k, 1 - k, 1], [k, 0.36, 1 - k, 0.58]],
		"E": [[0, 0, k, 1], [k, 1 - k, 1, 1], [k, 0.39, 0.82, 0.61], [k, 0, 1, k]],
		"R": [[0, 0, k, 1], [k, 1 - k, 1, 1], [1 - k, 0.45, 1, 1 - k], [k, 0.45, 1, 0.45 + k]],
		"M": [[0, 0, k, 1], [1 - k, 0, 1, 1]],
	}
	var n := txt.length()
	var gap := 0.55                                 # space between letters, of a letter's width
	var lw := width / (float(n) + gap * float(n - 1))
	var x0 := centre.x - width * 0.5
	for li in range(n):
		var ch := txt.substr(li, 1)
		var lx := x0 + float(li) * lw * (1.0 + gap)
		var polys: Array = []
		for r in strokes.get(ch, []):
			polys.append([Vector2(r[0], r[1]), Vector2(r[2], r[1]), Vector2(r[2], r[3]), Vector2(r[0], r[3])])
		if ch == "M":
			polys.append([Vector2(k, 1), Vector2(0.5 + k * 0.5, 0.40), Vector2(0.5 - k * 0.2, 0.40), Vector2(0.0 + k * 0.2, 1)])
			polys.append([Vector2(1 - k, 1), Vector2(1 - k * 0.2, 1), Vector2(0.5 + k * 0.2, 0.40), Vector2(0.5 - k * 0.5, 0.40)])
		if ch == "R":
			polys.append([Vector2(0.38, 0.45), Vector2(0.38 + k, 0.45), Vector2(1, 0), Vector2(1 - k * 1.1, 0)])
		for poly in polys:
			var pts: Array = []
			for q in poly:
				pts.append(Vector3(lx + (q as Vector2).x * lw, centre.y - height * 0.5 + (q as Vector2).y * height, 0.0))
			_slab(kit, pts, centre.z - 0.002, centre.z + depth)


## A raised slab: a flat convex outline (x, y) pushed out from z0 to z1, its
## face and its sides (the back is inside the panel).
static func _slab(kit: RefCounted, pts: Array, z0: float, z1: float) -> void:
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var fc := Vector3(c.x, c.y, z1)
	for i in range(pts.size()):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		kit.tri(fc, Vector3(a.x, a.y, z1), Vector3(b.x, b.y, z1), Color.WHITE, Vector3(0, 0, 1))
		var side := Vector3(b.y - a.y, -(b.x - a.x), 0.0)
		if side.dot(Vector3(a.x - c.x, a.y - c.y, 0)) < 0.0:
			side = -side
		kit.quad(Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1), Color.WHITE, side)


## Outward direction of a plan-view run (for the bent tail lamp).
static func _out2(p0: Vector2, p1: Vector2, s: float) -> Vector3:
	var d := p1 - p0
	var n := Vector2(d.y, -d.x).normalized()
	if n.y < 0.0 and absf(n.y) > absf(n.x):
		n = -n
	if absf(n.x) >= absf(n.y) and n.x < 0.0:
		n = -n
	return Vector3(n.x * s, 0, n.y)


## A lamp whose lens is a shaped mesh (it lights: pickup_truck finds *Bulb).
static func _bulb_mesh(root: Node3D, nm: String, kit: RefCounted, col: Color) -> void:
	var mi: MeshInstance3D = kit.instance(nm)
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.3)
	m.roughness = 0.2
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _bulb(root: Node3D, nm: String, at: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.3)
	m.roughness = 0.2
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _mirrors(black: RefCounted, chrome: RefCounted, sides: Array = [-1.0, 1.0]) -> void:
	# the '81-'87 West Coast-style mirror: a tall rectangular chrome head facing
	# back (the glass on its rear face), on two tube arms from the door's front
	# corner under the window (it faced sideways before)
	var w: float = P["w"]
	var belt: float = P["belt_y"]
	var cz: float = P["cowl_z"]
	for s in sides:
		var head := Vector3(s * (w + 0.18), belt + 0.13, cz + 0.16)
		chrome.box_at(head, Vector3(0.15, 0.23, 0.045), Color(0.85, 0.85, 0.86))                       # housing
		chrome.box_at(head + Vector3(0, 0, 0.024), Vector3(0.132, 0.21, 0.004), Color(0.38, 0.43, 0.48))   # the glass, facing back
		black.box_at(head + Vector3(0, 0, 0.0), Vector3(0.155, 0.235, 0.03), Color(0.05, 0.05, 0.05))     # rubber edge between
		var inner := head + Vector3(-s * 0.075, 0, 0)
		for e in [[Vector3(s * (w + 0.008), belt - 0.06, cz + 0.13), inner + Vector3(0, -0.09, 0)],
				[Vector3(s * (w + 0.008), belt + 0.04, cz + 0.11), inner + Vector3(0, 0.08, 0)]]:
			_bar(chrome, e[0], e[1], 0.007, Color(0.85, 0.85, 0.86))
			chrome.box_at(e[0], Vector3(0.02, 0.035, 0.035), Color(0.85, 0.85, 0.86))                   # mount foot
		_bar(chrome, inner + Vector3(0, -0.09, 0), inner + Vector3(0, 0.08, 0), 0.006, Color(0.85, 0.85, 0.86))   # the upright the head pivots on


## Pass 1 details (DESIGN_NOTES 192): the bright trim along both edges of the
## two-tone band (broken at the wheel openings and the cab/bed gap), drip rails,
## door handles and hinges, the fuel door on the left bed side, stake pockets,
## tailgate latches and handle, the antenna.
static func _details(paint: RefCounted, black: RefCounted, chrome: RefCounted) -> void:
	var w: float = P["w"]
	var b: float = P["bulge"]
	var cy: float = P["crease_y"]
	var lo: float = P["tone_lo"]
	var cab_back: float = P["cab_back_z"]
	var bed_z: float = P["bed_z"]
	var tz: float = P["tail_z"]
	var nz: float = P["nose_z"]
	for s in [-1.0, 1.0]:
		_sw("Pinstripes")
		# painted pinstripes, after Dave's black K10/K20 photos: a pair along the
		# shoulder, and a pair low on the body that rises over each wheel opening
		var dz := door_z()
		var pspans := [[nz + 0.06, dz.x - 0.006], [dz.y + 0.006, cab_back - 0.01], [bed_z + 0.01, tz - CORNER - 0.005]]
		if style == "blazer":
			pspans = [[nz + 0.06, dz.x - 0.006], [dz.y + 0.006, tz - CORNER - 0.005]]
		elif style == "suburban":
			var rd: Vector2 = P["rear_door"]
			pspans = [[nz + 0.06, dz.x - 0.006], [dz.y + 0.006, rd.x - 0.006], [rd.y + 0.006, tz - CORNER - 0.005]]
		for span in pspans:
			_pin_lines(black, s, float(span[0]), float(span[1]), chrome)
		_sw("DripRails")
		# drip rail along the roof edge
		var roof: float = P["roof_y"]
		var hw: float = float(P["w"]) - 0.03 - float(P["tumble"]) + 0.02
		var dr := roof - float(P["roof_thick"]) + 0.03
		_bar(chrome, Vector3(s * (hw + 0.005), dr, float(P["glass_top_z"]) - 0.02), Vector3(s * (hw + 0.005), dr, (tz - 0.08) if suv() else (cab_back - 0.06)), 0.007, Color.WHITE)
		_sw("DoorHinges")
		# door hinges on the A pillar (the door itself: _doors)
		for hy in [0.86, 1.22]:
			black.box_at(Vector3(s * (_width(-1.24) + b + 0.006), hy, float(P["cowl_z"]) + 0.07), Vector3(0.012, 0.07, 0.03), Color(0.08, 0.08, 0.08))
		if suv():
			continue
		_sw("StakePockets")
		# stake pockets in the bed rail caps
		for z in [bed_z + 0.16, (bed_z + tz) * 0.5, tz - 0.16]:
			black.box_at(Vector3(s * (w - 0.06), float(P["rail_y"]) + 0.003, z), Vector3(0.05, 0.003, 0.10), Color(0.01, 0.01, 0.01))
	_sw("FuelFiller")
	# the fuel filler (DESIGN_NOTES 206): a dark pocket pressed into the bed
	# side with the cap in it; the door over it is its own part (FuelDoor,
	# hinged at its front edge - it opens, and it can be knocked off)
	var fz := bed_z + 0.42
	var fy: float = (float(P["tone_lo"]) + float(P["tone_hi"])) * 0.5 - 0.02   # in the middle colour band
	var fx: float = -(_bed_skin_x(fz, fy + 0.076) + 0.002)   # on the skin (its bulge is fullest at the door's top edge)
	_rrect(black, Vector3(fx - 0.0012, fy, fz), 0.172, 0.150, 0.03, Color(0.012, 0.012, 0.012))
	_rdisc(chrome, Vector3(fx - 0.0016, fy, fz), 0.046, Color(0.28, 0.28, 0.29))   # the filler neck's rim
	_flush()
	# the cap: its own part. Screwed in, its body sits back inside the panel
	# and only the face and grip show (the door shuts over them); it unscrews
	# out and hangs on its tether (pickup_truck: fuel_door_toggle)
	var ck := _new_part(_root, "FuelCap")
	ck.node.set_meta("center", Vector3(fx, fy, fz))
	ck.node.set_meta("tether", Vector3(fx - 0.003, fy + 0.050, fz - 0.045))
	var capc := Color(0.10, 0.10, 0.11)
	var spin_up := Basis(Vector3.BACK, PI * 0.5)            # a cylinder's axis turned to point out (-x)
	ck.black.cylinder(Transform3D(spin_up, Vector3(fx + 0.030, fy, fz)), 0.034, 0.034, 0.026, 24, capc, true)   # threaded body
	ck.black.cylinder(Transform3D(spin_up, Vector3(fx + 0.004, fy, fz)), 0.039, 0.039, 0.006, 24, capc, true)   # the face, ridged rim
	for gi in range(12):
		var ga := TAU * float(gi) / 12.0
		ck.black.box_at(Vector3(fx - 0.0012, fy + sin(ga) * 0.038, fz + cos(ga) * 0.038), Vector3(0.0018, 0.008, 0.008), capc.lightened(0.05))
	ck.black.box_at(Vector3(fx - 0.0028, fy, fz), Vector3(0.0022, 0.050, 0.010), Color(0.16, 0.16, 0.17))   # the grip bar
	_end_part(ck)
	var fk := _new_part(_root, "FuelDoor")
	fk.node.set_meta("hinge", Vector3(fx - 0.006, fy, fz - 0.078))
	var dcol: Color = P["paint"]
	if bool(P["two_tone"]) and fy > float(P["tone_lo"]) and fy < float(P["tone_hi"]):
		dcol = P["paint2"]
	_rrect(fk.paint, Vector3(fx - 0.0055, fy, fz), 0.160, 0.138, 0.025, Color.WHITE)     # outer skin: the body paint (the shader bands it)
	_rrect(fk.black, Vector3(fx - 0.0045, fy, fz), 0.150, 0.128, 0.022, dcol.darkened(0.25))   # its inside
	_rrect(fk.black, Vector3(fx - 0.0062, fy, fz + 0.060), 0.016, 0.040, 0.007, Color(0.03, 0.03, 0.03))   # finger notch
	fk.black.box_at(Vector3(fx - 0.004, fy, fz - 0.074), Vector3(0.006, 0.06, 0.008), Color(0.05, 0.05, 0.05))   # hinge
	_end_part(fk)
	_sw("TailgateLatches")
	# tailgate latches at the top corners, the handle in the middle
	for s2 in [-1.0, 1.0]:
		chrome.box_at(Vector3(s2 * (w - 0.10), float(P["rail_y"]) - 0.04, tz + 0.03), Vector3(0.05, 0.03, 0.02), Color.WHITE)
	chrome.box_at(Vector3(0, float(P["rail_y"]) - 0.06, tz + 0.045), Vector3(0.18, 0.035, 0.02), Color.WHITE)
	_sw("Antenna")
	# antenna on the right front fender
	_bar(chrome, Vector3(w - 0.08, float(P["hood_y"]) - 0.01, float(P["cowl_z"]) - 0.25), Vector3(w - 0.11, float(P["hood_y"]) + 0.85, float(P["cowl_z"]) - 0.22), 0.003, Color.WHITE)


## Pass 3: what's underneath - frame rails and crossmembers, leaf springs over
## each axle, the diff covers, the exhaust down the right side to a turned-down
## tip, the spare tyre slung under the back of the bed, the gas tank.
static func _underside(black: RefCounted, chrome: RefCounted) -> void:
	var nz: float = P["nose_z"]
	var tz: float = P["tail_z"]
	var steel := Color(0.07, 0.07, 0.07)
	_sw("FrameRails")
	for s in [-1.0, 1.0]:
		black.box_at(Vector3(s * 0.45, 0.62, (nz + 0.25 + tz - 0.05) * 0.5), Vector3(0.07, 0.17, tz - nz - 0.3), steel)
	_sw("SpringHangers")
	# (leaf springs, shocks, the drag link: _suspension - they move with the axles)
	for s in [-1.0, 1.0]:
		for az in [FZ, RZ]:
			black.box_at(Vector3(s * 0.45, 0.58, az - 0.64), Vector3(0.06, 0.12, 0.05), steel)          # spring hanger
			black.box_at(Vector3(s * 0.45, 0.60, az + 0.66), Vector3(0.06, 0.10, 0.05), steel)          # shackle bracket
			black.box_at(Vector3(s * 0.50, 0.76, az + (0.30 if az < 0.0 else -0.30)), Vector3(0.08, 0.04, 0.06), steel)   # shock tower
	_sw("SteeringBox")
	# front steering: box on the left frame rail, pitman arm, drag link to the left
	# knuckle, tie rod across behind the axle, knuckles at the wheels, a sway bar
	black.box_at(Vector3(-0.44, 0.66, FZ - 0.42), Vector3(0.14, 0.14, 0.16), Color(0.10, 0.10, 0.10))
	black.box_at(Vector3(-0.44, 0.55, FZ - 0.36), Vector3(0.03, 0.16, 0.04), steel)
	_bar(black, Vector3(-0.50, 0.50, FZ - 0.30), Vector3(0.50, 0.50, FZ - 0.30), 0.014, steel)
	_sw("Crossmembers")
	for cz in [nz + 0.35, -1.1, 0.2, RZ + 0.75, tz - 0.08]:
		black.box_at(Vector3(0, 0.62, cz), Vector3(0.90, 0.10, 0.08), steel)
	_sw("Exhaust")
	# exhaust: muffler under the cab, pipe back to a tip ahead of the right rear wheel
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.30, 0.46, -0.9)), 0.09, 0.09, 0.62, 16, Color(0.20, 0.18, 0.16), true)
	_bar(black, Vector3(0.30, 0.46, -0.28), Vector3(0.62, 0.42, RZ - 0.62), 0.028, Color(0.18, 0.16, 0.14))
	_bar(black, Vector3(0.62, 0.42, RZ - 0.62), Vector3(0.72, 0.36, RZ - 0.66), 0.03, Color(0.18, 0.16, 0.14))
	_sw("SpareTire")
	# spare tyre under the back of the bed
	# (a real tyre with tread, lying flat in its carrier: added as a mesh after this part)
	black.box_at(Vector3(0, 0.555, tz - 0.62), Vector3(0.62, 0.025, 0.05), Color(0.06, 0.06, 0.06))    # carrier bar
	_spare_at = Vector3(0, 0.68, tz - 0.62)          # tucked up under the bed floor, not hanging below the bumper
	_sw("FuelTank")
	# gas tank between the frame rails, behind the cab
	black.box_at(Vector3(-0.0, 0.55, 0.55), Vector3(0.70, 0.22, 0.55), Color(0.09, 0.09, 0.09))


## The drivetrain (DESIGN_NOTES 192): a small-block V8 between the frame rails
## (block, heads, valve covers, intake, a round chrome air cleaner, exhaust
## manifolds into the down pipes), the radiator and fan, battery and
## alternator, then the transmission and the 4x4 transfer case behind it
## (the drive shafts and axles are pickup_truck's own moving parts).
static func _drivetrain(black: RefCounted, chrome: RefCounted) -> void:
	# (DESIGN_NOTES 197) a small-block V8, every component its own part, laid out
	# as a real one: block and pan, heads leaning out in the vee, valve covers,
	# intake with a 4-barrel and the air cleaner, log exhaust manifolds, the front
	# drive (balancer, water pump, fan, belts, alternator, power steering pump),
	# distributor and plug wires, coil, starter, oil filter, dipstick, mounts;
	# then bellhousing, transmission and the transfer case
	var nz: float = P["nose_z"]
	var ez := engine_z()                      # engine centre, fore-aft
	var ef := ez - 0.31                       # front face of the block
	var er := ez + 0.31                       # back face
	var orange := Color(0.62, 0.24, 0.07)     # engine paint
	var iron := Color(0.13, 0.12, 0.11)
	var alu := Color(0.55, 0.55, 0.53)
	var rubber := Color(0.03, 0.03, 0.03)
	_sw("EngineBlock")
	black.box_at(Vector3(0, 0.74, ez), Vector3(0.42, 0.24, 0.62), orange)                       # crankcase
	for s in [-1.0, 1.0]:
		var hb := Basis(Vector3.BACK, s * 0.785)
		black.box(Transform3D(hb, Vector3(s * 0.11, 0.90, ez)), Vector3(0.26, 0.14, 0.60), orange)   # cylinder bank
		for zz in [-0.18, 0.0, 0.18]:
			black.cylinder(Transform3D(Basis(Vector3.BACK, s * PI * 0.5), Vector3(s * 0.21, 0.74, ez + zz)), 0.022, 0.022, 0.008, 16, iron, true)   # freeze plugs
	_sw("OilPan")
	black.box_at(Vector3(0, 0.58, ez + 0.02), Vector3(0.36, 0.09, 0.58), iron)
	black.box_at(Vector3(0, 0.53, ez + 0.14), Vector3(0.30, 0.06, 0.26), iron)                   # sump
	black.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.05, 0.495, ez + 0.20)), 0.012, 0.012, 0.01, 6, alu, true)   # drain plug
	for s in [-1.0, 1.0]:
		var sd := "L" if s < 0.0 else "R"
		var hb := Basis(Vector3.BACK, s * 0.62)
		_sw("CylinderHead" + sd)
		black.box(Transform3D(hb, Vector3(s * 0.215, 0.97, ez)), Vector3(0.17, 0.10, 0.58), orange)
		# spark plugs along the outside of the head, between the exhaust ports
		for i in range(4):
			var pz := ez - 0.21 + i * 0.14
			black.cylinder(Transform3D(Basis(Vector3.BACK, s * 1.2), Vector3(s * 0.285, 0.92, pz)), 0.008, 0.008, 0.04, 8, Color(0.85, 0.85, 0.82), true)
		_sw("ValveCover" + sd)
		var vc := Vector3(s * 0.255, 1.045, ez)
		chrome.box(Transform3D(hb, vc), Vector3(0.13, 0.055, 0.54), Color.WHITE)
		for i in range(4):
			chrome.cylinder(Transform3D(hb, vc + hb * Vector3(0, 0.028, -0.22 + i * 0.147)), 0.008, 0.008, 0.008, 8, Color.WHITE, true)   # hold-downs
		black.cylinder(Transform3D(hb, vc + hb * Vector3(0, 0.026, 0.17 if s < 0.0 else -0.17)), 0.022, 0.022, 0.03, 16, rubber, true)       # oil cap / breather
		_sw("ExhaustManifold" + sd)
		var log := Vector3(s * 0.31, 0.84, ez)
		black.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), log + Vector3(0, 0, -0.25)), 0.028, 0.028, 0.50, 14, iron, true)
		for i in range(4):
			var pz := ez - 0.21 + i * 0.14
			_tube(black, [Vector3(s * 0.25, 0.90, pz + 0.07), Vector3(s * 0.29, 0.87, pz + 0.07), log + Vector3(0, 0.01, pz + 0.07 - ez)], 0.02, iron, 10)
		_tube(black, _curve([log + Vector3(0, -0.02, 0.22), log + Vector3(s * 0.02, -0.12, 0.30), Vector3(s * 0.33, 0.50, ez + 0.50), Vector3(s * 0.31, 0.46, ez + 0.70)]), 0.026, iron, 12)   # down pipe
	_sw("IntakeManifold")
	black.box_at(Vector3(0, 1.02, ez), Vector3(0.24, 0.07, 0.50), orange)
	black.box_at(Vector3(0, 1.065, ez - 0.02), Vector3(0.16, 0.03, 0.18), orange)               # carb pad
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.35), Vector3(0, 1.02, ez - 0.26)), 0.03, 0.025, 0.06, 14, orange, true)   # thermostat housing
	_sw("Carburetor")
	black.box_at(Vector3(0, 1.10, ez - 0.02), Vector3(0.14, 0.05, 0.15), alu)
	_tube(black, [Vector3(0.06, 1.10, ez + 0.06), Vector3(0.12, 1.08, ez + 0.20), Vector3(0.14, 1.12, er + 0.05)], 0.004, alu, 6)   # throttle cable
	_sw("AirCleaner")
	var ac := Vector3(0, 1.13, ez - 0.02)
	chrome.cylinder(Transform3D(Basis.IDENTITY, ac), 0.20, 0.20, 0.012, 36, Color.WHITE, true)        # base
	black.cylinder(Transform3D(Basis.IDENTITY, ac + Vector3(0, 0.012, 0)), 0.185, 0.185, 0.045, 36, Color(0.75, 0.70, 0.40), false)   # filter element
	chrome.cylinder(Transform3D(Basis.IDENTITY, ac + Vector3(0, 0.057, 0)), 0.20, 0.17, 0.02, 36, Color.WHITE, true)   # lid
	chrome.cylinder(Transform3D(Basis.IDENTITY, ac + Vector3(0, 0.077, 0)), 0.02, 0.014, 0.02, 12, Color.WHITE, true)  # wing nut
	chrome.box_at(ac + Vector3(0, 0.03, -0.24), Vector3(0.11, 0.06, 0.10), Color.WHITE)            # snorkel
	_sw("Distributor")
	var dc := Vector3(0, 1.10, er + 0.02)
	black.cylinder(Transform3D(Basis.IDENTITY, dc + Vector3(0, -0.10, 0)), 0.03, 0.03, 0.10, 14, iron, true)
	black.cylinder(Transform3D(Basis.IDENTITY, dc), 0.065, 0.06, 0.05, 20, rubber, true)          # cap
	for i in range(8):
		var aa := TAU * float(i) / 8.0
		black.cylinder(Transform3D(Basis.IDENTITY, dc + Vector3(cos(aa) * 0.045, 0.05, sin(aa) * 0.045)), 0.008, 0.008, 0.02, 8, rubber, true)
	_sw("SparkPlugWires")
	for s in [-1.0, 1.0]:
		for i in range(4):
			var pz := ez - 0.21 + i * 0.14
			var aa := TAU * float(i + (0 if s < 0.0 else 4)) / 8.0
			var top := dc + Vector3(cos(aa) * 0.045, 0.07, sin(aa) * 0.045)
			_tube(black, _curve([top, top + Vector3(s * 0.08, 0.04, -0.02), Vector3(s * 0.25, 1.08, pz + 0.03), Vector3(s * 0.31, 0.95, pz)], 4), 0.005, Color(0.10, 0.12, 0.35), 6)
	_sw("IgnitionCoil")
	black.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.14, 1.04, er - 0.05)), 0.03, 0.03, 0.12, 14, rubber, true)
	_sw("TimingCover")
	black.box_at(Vector3(0, 0.80, ef - 0.02), Vector3(0.30, 0.22, 0.04), orange)
	_sw("CrankPulley")
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.66, ef - 0.03)), 0.10, 0.10, 0.04, 32, iron, true)     # balancer
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.66, ef - 0.07)), 0.085, 0.085, 0.025, 32, iron, true)  # pulley
	_sw("WaterPump")
	black.box_at(Vector3(0, 0.86, ef - 0.06), Vector3(0.20, 0.12, 0.06), orange)
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.86, ef - 0.09)), 0.075, 0.075, 0.025, 32, iron, true)  # pulley
	_sw("Fan")
	var fc := Vector3(0, 0.86, ef - 0.13)
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), fc + Vector3(0, 0, 0.02)), 0.05, 0.05, 0.04, 20, alu, true)        # clutch
	for i in range(5):
		var aa := TAU * float(i) / 5.0
		var bb := Basis(Vector3.BACK, aa) * Basis(Vector3.UP, 0.35)
		black.box(Transform3D(bb, fc + Basis(Vector3.BACK, aa) * Vector3(0.12, 0, 0)), Vector3(0.18, 0.07, 0.006), Color(0.12, 0.12, 0.10))
	_sw("FanShroud")
	var rz := nz + 0.20
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.88, fc.z - 0.05)), 0.235, 0.235, 0.10, 40, rubber, false)
	black.box_at(Vector3(0, 0.88, rz + 0.04), Vector3(0.70, 0.46, 0.012), rubber)
	_sw("Alternator")
	var alt := Vector3(0.22, 0.98, ef - 0.02)
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), alt + Vector3(0, 0, 0.06)), 0.068, 0.068, 0.10, 28, alu, true)
	for i in range(10):
		var aa := TAU * float(i) / 10.0
		black.box_at(alt + Vector3(cos(aa) * 0.068, sin(aa) * 0.068, 0.01), Vector3(0.008, 0.008, 0.08), alu.darkened(0.2))   # cooling fins
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), alt + Vector3(0, 0, -0.06)), 0.04, 0.04, 0.02, 20, iron, true)   # pulley
	black.box(Transform3D(Basis(Vector3.BACK, -0.5), Vector3(0.17, 0.92, ef - 0.03)), Vector3(0.12, 0.02, 0.02), iron)          # bracket
	_sw("PowerSteeringPump")
	var ps := Vector3(-0.22, 0.95, ef - 0.03)
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), ps + Vector3(0, 0, 0.08)), 0.055, 0.055, 0.10, 24, iron, true)
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), ps + Vector3(0, 0, -0.05)), 0.06, 0.06, 0.02, 24, iron, true)   # pulley
	black.cylinder(Transform3D(Basis.IDENTITY, ps + Vector3(0, 0.05, 0.06)), 0.035, 0.035, 0.04, 16, alu, true)                 # reservoir cap
	_sw("Belts")
	# fan belt round crank, water pump and alternator; a second to the power steering pump
	var crank := Vector3(0, 0.66, ef - 0.075)
	var wp := Vector3(0, 0.86, ef - 0.095)
	var altp := alt + Vector3(0, 0, -0.07)
	_tube(black, [crank + Vector3(0.087, 0, 0), altp + Vector3(0.042, 0, 0), altp + Vector3(0, 0.042, 0), wp + Vector3(0, 0.077, 0), wp + Vector3(-0.077, 0, 0), crank + Vector3(-0.087, 0, 0), crank + Vector3(0, -0.087, 0), crank + Vector3(0.087, 0, 0)], 0.007, rubber, 6)
	var psp := ps + Vector3(0, 0, -0.045)
	_tube(black, [crank + Vector3(-0.08, 0.03, -0.02), psp + Vector3(-0.06, 0, 0), psp + Vector3(0, 0.062, 0), psp + Vector3(0.06, 0, 0), crank + Vector3(0.0, 0.08, -0.02)], 0.006, rubber, 6)
	_sw("Starter")
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.20, 0.62, er - 0.12)), 0.05, 0.05, 0.20, 20, iron, true)
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.20, 0.69, er - 0.10)), 0.025, 0.025, 0.12, 14, iron, true)   # solenoid
	_sw("OilFilter")
	black.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.21, 0.64, er - 0.10)), 0.045, 0.045, 0.12, 20, Color(0.80, 0.42, 0.10), true)
	_sw("Dipstick")
	_tube(black, _curve([Vector3(0.19, 0.62, ez), Vector3(0.24, 0.80, ez - 0.05), Vector3(0.27, 1.06, ez - 0.10)], 5), 0.005, iron, 6)
	black.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.27, 1.06, ez - 0.10)), 0.015, 0.015, 0.012, 10, Color(0.85, 0.70, 0.10), true)
	_sw("MotorMounts")
	for s in [-1.0, 1.0]:
		black.box_at(Vector3(s * 0.32, 0.70, ez - 0.10), Vector3(0.12, 0.05, 0.08), iron)
		black.box_at(Vector3(s * 0.40, 0.70, ez - 0.10), Vector3(0.05, 0.08, 0.10), rubber)
	_sw("Bellhousing")
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.76, er)), 0.21, 0.16, 0.18, 32, alu, true)
	_sw("Transmission")
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.73, er + 0.18)), 0.15, 0.13, 0.36, 28, iron, true)
	for i in range(5):
		black.box_at(Vector3(0, 0.62, er + 0.22 + i * 0.07), Vector3(0.22, 0.012, 0.012), iron)          # ribs
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.70, er + 0.54)), 0.08, 0.07, 0.20, 24, iron, true)    # tail housing
	_sw("TransferCase")
	black.box_at(Vector3(-0.07, 0.64, ez + 1.10), Vector3(0.26, 0.26, 0.22), iron)
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(-0.15, 0.55, ez + 1.00)), 0.045, 0.04, 0.05, 20, iron, true)  # front output
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.56, ez + 1.21)), 0.045, 0.04, 0.05, 20, iron, true)    # rear output
	_tube(black, [Vector3(0.05, 0.75, ez + 1.10), Vector3(0.12, 0.85, ez + 1.10), Vector3(0.12, 0.80, -0.72 + driver_dz())], 0.008, iron, 8)     # shift linkage


## Everything else mechanical (DESIGN_NOTES 197), each its own part: radiator
## support and hood latch, hood hinges, brake booster and master cylinder with
## lines, wiper motor, heater box and hoses, washer bottle, voltage regulator,
## horn, battery tray, cables, steering column and shaft, fuel filler neck and
## lines, parking brake cables.
static func _mechanical(black: RefCounted, chrome: RefCounted) -> void:
	var nz: float = P["nose_z"]
	var cz: float = P["cowl_z"]
	var w: float = P["w"]
	var ez := engine_z()
	var iron := Color(0.13, 0.12, 0.11)
	var steel := Color(0.07, 0.07, 0.07)
	var rubber := Color(0.03, 0.03, 0.03)
	var alu := Color(0.55, 0.55, 0.53)
	var zinc := Color(0.62, 0.62, 0.55)
	var fw := cz - 0.0                         # the engine side of the firewall
	_sw("RadiatorSupport")
	var sz := nz + 0.14
	black.box_at(Vector3(0, 1.19, sz), Vector3(w * 1.7, 0.05, 0.07), steel)                 # top bar
	black.box_at(Vector3(0, 0.62, sz), Vector3(w * 1.6, 0.06, 0.08), steel)                 # bottom
	for s in [-1.0, 1.0]:
		black.box_at(Vector3(s * 0.46, 0.90, sz), Vector3(0.06, 0.56, 0.06), steel)
		black.box_at(Vector3(s * 0.70, 0.98, sz + 0.05), Vector3(0.40, 0.36, 0.02), steel)   # to the fenders
	_sw("HoodLatch")
	var hl := Vector3(0, 1.19, sz - 0.01)
	black.box_at(hl + Vector3(0, 0.0, -0.035), Vector3(0.12, 0.08, 0.012), zinc)            # latch plate
	black.box_at(hl + Vector3(0, 0.03, -0.045), Vector3(0.03, 0.03, 0.02), zinc)            # catch
	_tube(black, _curve([hl + Vector3(0.02, 0.05, -0.04), hl + Vector3(0.02, 0.10, -0.04), hl + Vector3(0.0, 0.11, -0.04)], 4), 0.006, zinc, 8)   # spring
	_tube(black, [hl + Vector3(0.05, -0.01, -0.045), hl + Vector3(0.09, -0.06, -0.10)], 0.005, zinc, 6)   # release lever
	black.cylinder(Transform3D(Basis.IDENTITY, hl + Vector3(-0.05, 0.03, -0.045)), 0.012, 0.012, 0.03, 10, rubber, true)   # bump stop
	for s in [-1.0, 1.0]:
		var sd := "L" if s < 0.0 else "R"
		_sw("HoodHinge" + sd)
		var hh := Vector3(s * (w - 0.17), 1.22, cz - 0.04)
		black.box(Transform3D(Basis(Vector3.RIGHT, 0.5), hh), Vector3(0.012, 0.03, 0.22), zinc)
		black.box_at(hh + Vector3(0, -0.06, 0.06), Vector3(0.012, 0.10, 0.05), zinc)
		_tube(black, [hh + Vector3(s * 0.012, -0.08, 0.02), hh + Vector3(s * 0.012, 0.02, -0.12)], 0.009, Color(0.10, 0.10, 0.10), 10)   # spring
	_sw("BrakeBooster")
	var bb := Vector3(-0.45, 1.02, fw - 0.02)
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), bb), 0.12, 0.12, 0.14, 40, Color(0.09, 0.09, 0.09), true)
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), bb + Vector3(0, 0, -0.07)), 0.125, 0.125, 0.01, 40, Color(0.12, 0.12, 0.12), true)   # seam ring
	_tube(black, _curve([bb + Vector3(0.08, 0.06, -0.10), bb + Vector3(0.20, 0.10, -0.20), Vector3(0.0, 1.06, ez + 0.10)], 6), 0.011, rubber, 10)   # vacuum hose
	_sw("MasterCylinder")
	var mc := bb + Vector3(0, 0.0, -0.14)
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), mc), 0.035, 0.035, 0.18, 20, alu, true)
	black.box_at(mc + Vector3(0, 0.06, -0.09), Vector3(0.11, 0.07, 0.17), alu)              # reservoir
	black.box_at(mc + Vector3(0, 0.10, -0.09), Vector3(0.115, 0.012, 0.175), alu.darkened(0.1))   # lid
	_tube(black, [mc + Vector3(0, 0.12, -0.03), mc + Vector3(0, 0.12, -0.15)], 0.004, zinc, 6)   # bail
	_sw("BrakeLines")
	for off in [0.03, -0.03]:
		_tube(black, _curve([mc + Vector3(off, -0.02, -0.12), mc + Vector3(off + 0.02, -0.15, -0.14), Vector3(-0.40, 0.72, cz - 0.25), Vector3(-0.42, 0.62, FZ + 0.10)], 6), 0.003, zinc, 6)
	_tube(black, _curve([Vector3(-0.40, 0.72, cz - 0.25), Vector3(-0.38, 0.60, -0.5), Vector3(-0.38, 0.60, RZ - 0.3), Vector3(0.0, 0.50, RZ)], 6), 0.003, zinc, 6)
	_sw("WiperMotor")
	var wm := Vector3(-0.30, 1.22, fw - 0.03)
	black.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), wm), 0.04, 0.04, 0.10, 20, Color(0.10, 0.10, 0.10), true)
	black.box_at(wm + Vector3(0.07, 0, 0), Vector3(0.06, 0.07, 0.05), Color(0.08, 0.08, 0.08))
	_sw("HeaterBox")
	black.box_at(Vector3(0.48, 1.02, fw - 0.06), Vector3(0.34, 0.24, 0.10), Color(0.06, 0.06, 0.06))
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.40, 1.02, fw - 0.11)), 0.07, 0.07, 0.04, 28, Color(0.07, 0.07, 0.07), true)   # blower
	_sw("HeaterHoses")
	for dx in [0.0, 0.07]:
		_tube(black, _curve([Vector3(0.54 + dx, 1.00, fw - 0.11), Vector3(0.50 + dx, 1.02, fw - 0.25), Vector3(0.12 + dx * 0.5, 1.00, ez - 0.20), Vector3(0.05 + dx * 0.5, 0.88, ez - 0.32)], 6), 0.012, rubber, 10)
	_sw("WasherBottle")
	var wb := Vector3(w - 0.32, 1.00, nz + 0.45)
	black.box_at(wb, Vector3(0.12, 0.18, 0.14), Color(0.85, 0.85, 0.80, 1.0))
	black.cylinder(Transform3D(Basis.IDENTITY, wb + Vector3(0, 0.09, 0)), 0.022, 0.022, 0.02, 14, Color(0.15, 0.25, 0.7), true)
	_tube(black, _curve([wb + Vector3(0, 0.05, 0.07), Vector3(w - 0.35, 1.18, cz - 0.3), Vector3(0.0, 1.30, cz - 0.02)], 6), 0.003, rubber, 6)
	_sw("VoltageRegulator")
	black.box_at(Vector3(w - 0.24, 1.08, nz + 0.75), Vector3(0.012, 0.08, 0.12), Color(0.30, 0.30, 0.32))
	_sw("Horn")
	black.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(-0.55, 0.80, nz + 0.17)), 0.05, 0.03, 0.06, 24, rubber, true)
	_sw("BatteryTray")
	var bt := Vector3(-0.66, 1.0, nz + 0.40)
	black.box_at(bt + Vector3(0, -0.11, 0), Vector3(0.22, 0.02, 0.32), steel)
	black.box_at(bt + Vector3(0, 0.105, 0), Vector3(0.04, 0.012, 0.30), steel)              # hold-down
	_sw("Battery")
	black.box_at(bt, Vector3(0.18, 0.20, 0.28), Color(0.06, 0.06, 0.06))
	black.box_at(bt + Vector3(0, 0.101, 0), Vector3(0.17, 0.008, 0.27), Color(0.75, 0.70, 0.30))   # top
	for e in [[Vector3(0.05, 0.11, -0.10), Color(0.7, 0.1, 0.1)], [Vector3(0.05, 0.11, 0.10), Color(0.05, 0.05, 0.05)]]:
		black.cylinder(Transform3D(Basis.IDENTITY, bt + (e[0] as Vector3)), 0.012, 0.010, 0.02, 12, Color(0.6, 0.6, 0.55), true)   # posts
	_sw("BatteryCables")
	_tube(black, _curve([bt + Vector3(0.05, 0.13, -0.10), bt + Vector3(0.20, 0.10, -0.05), Vector3(0.10, 0.62, ez + 0.10), Vector3(0.20, 0.66, ez + 0.19)], 6), 0.009, Color(0.55, 0.05, 0.05), 10)
	_tube(black, _curve([bt + Vector3(0.05, 0.13, 0.10), bt + Vector3(0.12, 0.05, 0.16), Vector3(-0.20, 0.80, ez - 0.05)], 6), 0.009, rubber, 10)
	_sw("SteeringColumn")
	var wc := Vector3(-0.42, 1.28, -0.72 + driver_dz())
	var ax := Vector3(0, 0.469, 0.883).normalized()
	var through := Vector3(-0.44, 0.92, fw + 0.02)
	_tube(black, [wc - ax * 0.12, through], 0.035, Color(0.08, 0.08, 0.08), 16)
	black.box_at(wc - ax * 0.20 + Vector3(0.05, 0, 0), Vector3(0.03, 0.02, 0.10), Color(0.08, 0.08, 0.08))   # turn signal stalk
	_sw("SteeringShaft")
	var box := Vector3(-0.44, 0.66, FZ - 0.42)
	_tube(black, [through, Vector3(-0.46, 0.80, cz - 0.30)], 0.012, steel, 10)
	_tube(black, [Vector3(-0.46, 0.80, cz - 0.30), box + Vector3(0, 0.04, 0.10)], 0.012, steel, 10)
	black.box_at(Vector3(-0.46, 0.80, cz - 0.30), Vector3(0.04, 0.04, 0.04), iron)          # U-joint
	_sw("FuelFillerNeck")
	var fz: float = float(P["bed_z"]) + 0.42
	# down inside the bed side's double wall, out under the bed floor, to the tank
	var wx := _width(fz) - 0.025
	_tube(black, _curve([Vector3(-wx, 1.0, fz), Vector3(-wx, 0.80, fz + 0.02), Vector3(-wx + 0.05, 0.70, fz + 0.05), Vector3(-0.62, 0.64, 0.50), Vector3(-0.36, 0.60, 0.50)], 6), 0.022, rubber, 10)
	_sw("FuelLines")
	_tube(black, _curve([Vector3(-0.30, 0.48, 0.40), Vector3(-0.40, 0.55, -0.4), Vector3(-0.40, 0.62, ez + 0.20), Vector3(-0.20, 0.70, ez - 0.25), Vector3(0.0, 1.06, ez - 0.06)], 6), 0.004, zinc, 6)
	_sw("ParkingBrakeCables")
	for s in [-1.0, 1.0]:
		_tube(black, _curve([Vector3(0.0, 0.50, 0.30), Vector3(s * 0.30, 0.48, RZ - 0.40), Vector3(s * 0.66, AXLE_Y + 0.05, RZ - 0.05)], 6), 0.004, steel, 6)


## A thin bright strip through points along the body side.
## The pinstripes on one side between z_a and z_b (DESIGN_NOTES 200).
static func _pin_lines(kit: RefCounted, s: float, z_a: float, z_b: float, bright: RefCounted = null) -> void:
	# the two-tone's edges. K10 (default): painted double pinstripes along the
	# shoulder line and the lower paint line (Dave's K10 / K20 photos). tune
	# trim = "molding" gives the older bright strips instead: a bright
	# trim strip right on the shoulder line where the upper colour stops, and
	# another along the lower paint line, broken at the wheel openings and the
	# door gaps. tune trim = "pinstripe" for the painted double lines instead.
	var cy: float = P["crease_y"]
	var lo: float = P["tone_lo"]
	var b: float = P["bulge"]
	var cab_back: float = P["cab_back_z"]
	if String(t("trim", "pinstripe")) == "molding" and bright != null:
		var up: Array = []
		var low: Array = []
		for z in _stations(z_a, z_b, 0.06):
			var base: float = P["rocker_y"] if z < cab_back else P["bed_bottom"]
			var w := _width(z)
			up.append(Vector3(s * (w + b + 0.017), cy - 0.006, z))
			if _bottom(z, base) + 0.03 > lo:
				if low.size() >= 2:
					_strip(bright, low)
				low = []
				continue
			low.append(Vector3(s * (_bed_skin_x(z, lo) + 0.002), lo, z))
		if up.size() >= 2:
			_strip(bright, up)
		if low.size() >= 2:
			_strip(bright, low)
		return
	var col := Color(0.70, 0.70, 0.68)
	for dy in [0.022, 0.040]:
		var up: Array = []
		var low: Array = []
		for z in _stations(z_a, z_b, 0.06):
			var base: float = P["rocker_y"] if z < cab_back else P["bed_bottom"]
			var w := _width(z)
			up.append(Vector3(s * (_bed_skin_x(z, cy - 0.012 - float(dy)) + 0.0015), cy - 0.012 - dy, z))     # just under the shoulder line
			var yl: float = lo + float(dy) - 0.02
			if _bottom(z, base) + 0.02 > yl:
				if low.size() >= 2:
					_pin(kit, low, col)
				low = []
				continue
			low.append(Vector3(s * (w + b + 0.004), yl, z))
		_pin(kit, up, col)
		if low.size() >= 2:
			_pin(kit, low, col)


static func _pin(kit: RefCounted, pts: Array, col: Color) -> void:
	if pts.size() < 2:
		return
	var rings: Array = []
	for p in pts:
		var c: Vector3 = p
		var sx := signf(c.x)
		var ring := PackedVector3Array()
		for q in [Vector2(-0.002, -0.0025), Vector2(0.0015, -0.0025), Vector2(0.0015, 0.0025), Vector2(-0.002, 0.0025)]:
			ring.append(Vector3(c.x + sx * (q as Vector2).x, c.y + (q as Vector2).y, c.z))
		rings.append(ring)
	kit.loft(rings, col, true, true)


static func _strip(kit: RefCounted, pts: Array) -> void:
	var rings: Array = []
	for p in pts:
		var c: Vector3 = p
		var sx := signf(c.x)
		var ring := PackedVector3Array()
		for q in [Vector2(-0.004, -0.006), Vector2(0.002, -0.006), Vector2(0.004, 0.0), Vector2(0.002, 0.006), Vector2(-0.004, 0.006)]:
			ring.append(Vector3(c.x + sx * (q as Vector2).x, c.y + (q as Vector2).y, c.z))
		rings.append(ring)
	kit.loft(rings, Color.WHITE, true, true)


static func _interior(kit: RefCounted) -> void:
	var w: float = P["w"] - 0.06
	var cz: float = P["cowl_z"]
	var bz: float = P["cab_back_z"]
	var cloth := Color(0.30, 0.22, 0.16)
	var dash := Color(0.12, 0.11, 0.10)
	_sw("Floor")
	# floor: a footwell down below the door sill, so a seated driver's boots are
	# inside the cab (lab driver-fit check, DESIGN_NOTES 193)
	var fl := 0.50                                 # the floor pan: the seated driver's boots rest on it
	kit.box_at(Vector3(0, fl, (cz + bz) * 0.5), Vector3(w * 2.0, 0.03, bz - cz), Color(0.08, 0.075, 0.07))
	kit.box(Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0, fl + 0.12, cz + 0.12)), Vector3(w * 2.0, 0.30, 0.03), Color(0.08, 0.075, 0.07))   # toe board, slanted
	# the transmission tunnel: a rounded hump down the middle over the gearbox,
	# transfer case and drive shaft (they came up through a flat floor)
	var tun: Array = []
	for zz in [cz + 0.04, cz + 0.45, cz + 0.85, bz - 0.06]:
		var f := clampf((zz - cz) / maxf(bz - cz, 0.1), 0.0, 1.0)
		var ht := lerpf(0.36, 0.24, f)                       # higher over the gearbox
		var hw2 := lerpf(0.30, 0.24, f)
		var ring := PackedVector3Array()
		for k in range(11):
			var u := lerpf(-1.0, 1.0, float(k) / 10.0)
			ring.append(Vector3(u * hw2, fl + 0.015 + ht * sqrt(maxf(1.0 - pow(absf(u), 3.0), 0.0)), zz))
		ring.append(Vector3(hw2, fl - 0.01, zz))
		ring.append(Vector3(-hw2, fl - 0.01, zz))
		tun.append(ring)
	kit.loft(tun, Color(0.08, 0.075, 0.07), true, true)
	# the floor's edges closed up to the rockers (no seeing in underneath)
	for s3 in [-1.0, 1.0]:
		kit.box_at(Vector3(s3 * (w + 0.015), fl - 0.02, (cz + bz) * 0.5), Vector3(0.06, 0.06, bz - cz), Color(0.06, 0.06, 0.06))
	_sw("Firewall")
	kit.box_at(Vector3(0, 0.95, cz + 0.03), Vector3(w * 2.0, 0.76, 0.04), dash)                                        # firewall
	_sw("Dash")
	# the dash: kept clear of the gauge cluster (pickup_truck CLUSTER, tilted 0.62
	# rad) - the gauges sit in their own angled panel under a padded brow
	kit.box_at(Vector3(0, 1.04, cz + 0.13), Vector3(w * 2.0, 0.30, 0.18), dash)                                        # lower dash
	kit.box_at(Vector3(0, float(P["belt_y"]) - 0.09, cz + 0.10), Vector3(w * 2.0, 0.18, 0.18), dash)                  # upper dash, up to the glass
	var cl := Vector3(-0.45, 1.30, -0.889 + driver_dz())
	var tilt := Basis(Vector3.RIGHT, -0.62)
	kit.box(Transform3D(tilt, cl + tilt * Vector3(0, 0, -0.03)), Vector3(0.66, 0.24, 0.03), Color(0.04, 0.04, 0.045))     # cluster panel
	kit.box(Transform3D(tilt, cl + tilt * Vector3(0, 0.14, 0.03)), Vector3(0.70, 0.04, 0.12), Color(0.09, 0.085, 0.08))   # padded brow
	kit.box_at(Vector3(0.30, 1.21, cz + 0.30), Vector3(0.80, 0.03, 0.18), Color(0.09, 0.085, 0.08))                       # pad, passenger side
	_sw("BenchSeat")
	kit.box_at(Vector3(0, 0.75, bz - 0.33), Vector3(w * 1.85, 0.14, 0.46), cloth)                                          # bench seat
	kit.box(Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(0, 1.08, bz - 0.15)), Vector3(w * 1.85, 0.56, 0.10), cloth)  # back
	if not suv():
		_sw("BackWall")
		kit.box_at(Vector3(0, 1.0, bz - 0.04), Vector3(w * 2.0, 0.85, 0.03), dash)                                     # cab back wall
	_sw("Headliner")
	# headliner: tucked up under the roof, inside the pillars and above the door
	# glass (it poked out through the windows and the roof edge before)
	var gtop: float = float(P["roof_y"]) - float(P["roof_thick"])
	var hw2: float = float(P["w"]) - 0.03 - float(P["tumble"]) - 0.05
	kit.box_at(Vector3(0, gtop - 0.012, (float(P["glass_top_z"]) + bz) * 0.5), Vector3(hw2 * 2.0, 0.012, bz - float(P["glass_top_z"]) - 0.12), Color(0.55, 0.52, 0.46))
	_sw("DoorJambs")
	for s in [-1.0, 1.0]:
		var dz := door_z()
		kit.box_at(Vector3(s * (w + 0.02), 0.585, (dz.x + dz.y) * 0.5), Vector3(0.10, 0.012, dz.y - dz.x), Color(0.42, 0.42, 0.40))   # sill scuff plate
		kit.box_at(Vector3(s * (w + 0.04), 1.0, dz.x + 0.01), Vector3(0.05, 0.75, 0.04), Color(0.08, 0.075, 0.07))         # door jamb, front
		kit.box_at(Vector3(s * (w + 0.04), 1.0, dz.y - 0.01), Vector3(0.05, 0.75, 0.04), Color(0.08, 0.075, 0.07))         # door jamb, back
		kit.box_at(Vector3(s * 0.42, float(P["roof_y"]) - 0.09, cz + 0.55), Vector3(0.38, 0.02, 0.17), Color(0.45, 0.42, 0.36)) # sun visors
	var metal := Color(0.55, 0.55, 0.53)
	_sw("RearviewMirror")
	kit.box_at(Vector3(0, float(P["roof_y"]) - 0.12, cz + 0.45), Vector3(0.20, 0.06, 0.02), Color(0.06, 0.06, 0.06))        # rear-view mirror
	_sw("Pedals")
	kit.box_at(Vector3(-0.52, 0.66, cz + 0.36), Vector3(0.06, 0.02, 0.08), metal)                                          # clutch
	kit.box_at(Vector3(-0.38, 0.66, cz + 0.36), Vector3(0.08, 0.02, 0.07), metal)                                          # brake
	kit.box_at(Vector3(-0.24, 0.64, cz + 0.32), Vector3(0.04, 0.02, 0.10), metal)                                          # throttle
	_sw("Shifters")
	kit.box(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0.0, 0.85, cz + 0.62)), Vector3(0.015, 0.40, 0.015), metal)       # floor shifter
	kit.box(Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(0.12, 0.80, cz + 0.62)), Vector3(0.012, 0.30, 0.012), metal)      # transfer-case lever
	kit.box_at(Vector3(0.0, 1.05, cz + 0.62), Vector3(0.04, 0.04, 0.04), Color(0.05, 0.05, 0.05))                          # shifter knob
	_sw("DashKnobs")
	for i in range(4):
		kit.box_at(Vector3(0.05 + i * 0.07, 1.16, cz + 0.515), Vector3(0.025, 0.025, 0.02), Color(0.06, 0.06, 0.06))       # dash knobs


static func _hood(root: Node3D) -> void:
	# the hood: a separate panel over the clip, hinged at the cowl
	var kit := MeshKit.new()
	var nz: float = P["nose_z"]
	var cz: float = P["cowl_z"]
	var rings: Array = []
	for z in _stations(nz + 0.03, cz + 0.01, 0.1):
		var w := _width(z) - 0.030
		var yt := _top(z) + 0.012
		var crown := 0.025                     # the hood bows up a little along the middle
		var ring := PackedVector3Array()
		# two raised lines run down the hood (the square body's), a crown between
		var fz := clampf((z - nz) / (cz - nz), 0.0, 1.0)
		var rise := 0.03 * clampf((z - nz) / 0.25, 0.3, 1.0)       # the raised centre panel
		var cx := lerpf(0.22, 0.34, fz)                              # its edges, narrower at the nose
		for p in [Vector2(-w, yt - 0.010), Vector2(-w + 0.012, yt - 0.003), Vector2(-w + 0.05, yt), Vector2(-cx - 0.05, yt + crown * 0.5), Vector2(-cx - 0.006, yt + crown * 0.55),
				Vector2(-cx, yt + crown * 0.6 + rise), Vector2(-cx + 0.05, yt + crown * 0.75 + rise), Vector2(0.0, yt + crown + rise),
				Vector2(cx - 0.05, yt + crown * 0.75 + rise), Vector2(cx, yt + crown * 0.6 + rise), Vector2(cx + 0.006, yt + crown * 0.55), Vector2(cx + 0.05, yt + crown * 0.5),
				Vector2(w - 0.05, yt), Vector2(w - 0.012, yt - 0.003), Vector2(w, yt - 0.010)]:
			ring.append(Vector3((p as Vector2).x, (p as Vector2).y, z))
		rings.append(ring)
	# the rolled front lip: the leading edge curls down over the grille
	var front: PackedVector3Array = rings[0]
	var lip1 := PackedVector3Array()
	var lip2 := PackedVector3Array()
	for p in front:
		lip1.append(Vector3(p.x, p.y - 0.012, p.z - 0.025))
		lip2.append(Vector3(p.x * 0.995, p.y - 0.06, p.z - 0.03))
	rings.insert(0, lip1)
	rings.insert(0, lip2)
	kit.loft(rings, Color.WHITE, true, true)
	_tone(kit)
	kit.smooth(34.0)
	_add(root, kit, "Hood", _paint_mat())


static func _tailgate(root: Node3D) -> void:
	# (DESIGN_NOTES 204) a stamped double-wall gate, after the '81-'87 photos:
	# a rounded top cap, a recessed band across the upper half (where the
	# letters go - left blank), a raised ridge under it, a crease low down, the
	# bottom edge rolled under; the latch handle in a dark recess at the top
	# middle; hinges at the bottom corners; stamped ribs on the inside face
	var kit := MeshKit.new()
	var trim := MeshKit.new()
	var tz: float = P["tail_z"]
	var w: float = P["w"] - 0.185
	var y0 := 0.735
	var gt: float = float(P["rail_y"]) - (0.0 if suv() else 0.03)
	var h := gt - y0
	var fb0: float = clampf(float(P["tone_hi"]), y0 + h * 0.42, gt - 0.05)
	# the section, outside (+z) from the bottom up over the cap and down the inside
	var prof: Array = [
		Vector2(-0.022, y0), Vector2(0.012, y0 + 0.002), Vector2(0.024, y0 + 0.012),            # rolled bottom edge
		Vector2(0.026, y0 + h * 0.30), Vector2(0.034, y0 + h * 0.32), Vector2(0.034, y0 + h * 0.36), Vector2(0.026, y0 + h * 0.38),   # low crease
		Vector2(0.026, y0 + h * 0.41), Vector2(0.016, y0 + h * 0.43), Vector2(0.016, fb0 - 0.006), Vector2(0.026, fb0 + 0.006),   # recessed band (the name in it, in the lower colour); its top step IS the paint line, level with the body's shoulder (reference squarebody/02)
		Vector2(0.026, gt - 0.03), Vector2(0.016, gt - 0.008), Vector2(0.0, gt), Vector2(-0.018, gt - 0.008), Vector2(-0.026, gt - 0.03),   # the top cap
		Vector2(-0.026, y0 + 0.02)]
	# seams exactly at the paint lines, so the two-tone edge is straight (by whole
	# triangles it zig-zagged across the tall faces)
	for ty in [float(P["tone_lo"]), float(P["tone_hi"])]:
		for i in range(prof.size() - 1):
			var q0: Vector2 = prof[i]
			var q1: Vector2 = prof[i + 1]
			if q0.x > 0.0 and q1.x > 0.0 and ty > minf(q0.y, q1.y) + 0.003 and ty < maxf(q0.y, q1.y) - 0.003:
				var f: float = (ty - q0.y) / (q1.y - q0.y)
				prof.insert(i + 1, Vector2(lerpf(q0.x, q1.x, f), ty))
				break
	var rings: Array = []
	for i in range(15):
		var u := lerpf(-1.0, 1.0, float(i) / 14.0)
		var x := u * w
		var inset := 0.006 * pow(absf(u), 12.0)               # the ends roll in a touch
		var ring := PackedVector3Array()
		for q in prof:
			ring.append(Vector3(x, (q as Vector2).y, tz + (q as Vector2).x - inset))
		rings.append(ring)
	# faces turned by the section itself (it runs anticlockwise round the metal,
	# seen from the right): the guess from the middle turned the stamped band
	# inside-out (it looked dented in where it stands out, and dark)
	for r in range(rings.size() - 1):
		var a: PackedVector3Array = rings[r]
		var bq: PackedVector3Array = rings[r + 1]
		var n := a.size()
		for i in range(n):
			var j := (i + 1) % n
			var dzz: float = a[j].z - a[i].z
			var dyy: float = a[j].y - a[i].y
			var hint := Vector3(0.0, -dzz, dyy)
			if hint.length_squared() < 1e-10:
				hint = Vector3(0, 0, 1)
			kit.quad(a[i], a[j], bq[j], bq[i], Color.WHITE, hint)
	kit._cap(rings[0], Color.WHITE, Vector3(-1, 0, 0))
	kit._cap(rings[rings.size() - 1], Color.WHITE, Vector3(1, 0, 0))
	# the maker's name (Dave's make: HAMMER) STAMPED into the gate the way the
	# old trucks had it: big, wide block letters spread right across the
	# recessed band, pressed up out of the sheet metal and painted with it -
	# you read them by their edges catching the light
	var name_txt := String(t("tailgate_name", "HAMMER"))
	if name_txt != "" and not suv():
		var band_mid: float = (y0 + h * 0.43 + fb0 - 0.006) * 0.5
		_stamp_text(kit, name_txt, Vector3(0, band_mid, tz + 0.016), w * 2.0 * 0.78, minf((fb0 - 0.006 - y0 - h * 0.43) * 0.70, 0.11), 0.007)
	_tone(kit, false)
	# the inside face (toward the bed) is one colour, the bed's
	var bedc: Color = (P["paint"] as Color).darkened(0.08)
	for i in range(0, kit.cols.size(), 3):
		if (kit.norms[i] as Vector3).z < -0.5:
			kit.cols[i] = bedc
			kit.cols[i + 1] = bedc
			kit.cols[i + 2] = bedc
	# the inside face: stamped horizontal ribs, in the bed's colour
	for i in range(4):
		kit.box_at(Vector3(0, lerpf(y0 + 0.07, gt - 0.08, float(i) / 3.0), tz - 0.03), Vector3(w * 2.0 - 0.14, 0.03, 0.012), (P["paint"] as Color).darkened(0.08))
	# latch handle: a dark recess in the cap's face, a chrome pull in it
	trim.box_at(Vector3(0, gt - 0.05, tz + 0.03), Vector3(0.24, 0.05, 0.012), Color(0.03, 0.03, 0.03))
	trim.box_at(Vector3(0, gt - 0.055, tz + 0.036), Vector3(0.20, 0.022, 0.01), Color(0.80, 0.80, 0.80))
	# hinges at the bottom corners, latch strikers at the top corners
	for s in [-1.0, 1.0]:
		trim.box_at(Vector3(s * (w - 0.04), y0 + 0.02, tz - 0.005), Vector3(0.06, 0.04, 0.05), Color(0.06, 0.06, 0.06))
		trim.box_at(Vector3(s * (w - 0.01), gt - 0.06, tz), Vector3(0.02, 0.05, 0.03), Color(0.75, 0.75, 0.74))
	kit.smooth(34.0)
	trim.smooth(40.0)
	var n := Node3D.new()
	n.name = "Tailgate"
	root.add_child(n)
	_add(n, kit, "Paint", _paint_mat())
	_add(n, trim, "Trim", _mat(Color.WHITE, 0.4, 0.5, true))


static func _steering_wheel(root: Node3D) -> void:
	var c := Vector3(-0.42, 1.28, -0.72 + driver_dz())
	var ax := Vector3(0, 0.469, 0.883).normalized()
	var n := Node3D.new()
	n.name = "SteeringWheelRoot"
	root.add_child(n)
	var mi := MeshInstance3D.new()
	mi.name = "SteeringWheel"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.175
	tm.outer_radius = 0.20
	tm.rings = 24
	tm.ring_segments = 8
	mi.mesh = tm
	mi.transform = Transform3D(Basis(Vector3.RIGHT, ax, Vector3.RIGHT.cross(ax)).orthonormalized(), c)
	mi.material_override = _mat(Color(0.06, 0.055, 0.05), 0.6, 0.0, false)
	n.add_child(mi)
	var hub := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.035
	cm.height = 0.22
	hub.mesh = cm
	hub.material_override = mi.material_override
	hub.position = Vector3(0, -0.11, 0)
	mi.add_child(hub)


static func _axles(root: Node3D) -> void:
	for pair in [["AxleF", FZ], ["AxleR", RZ]]:
		var kit := MeshKit.new()
		var z: float = pair[1]
		# (MeshKit cylinders start at their origin) - from hub to hub, inside the wheels
		kit.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.66, AXLE_Y, z)), 0.05, 0.05, 1.32, 12, Color(0.12, 0.12, 0.12), true)
		var dx: float = 0.12 if z < 0.0 else 0.0
		kit.box_at(Vector3(dx, AXLE_Y, z), Vector3(0.28, 0.26, 0.26), Color(0.12, 0.12, 0.12))
		kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(dx, AXLE_Y, z + 0.13)), 0.14, 0.13, 0.04, 20, Color(0.10, 0.10, 0.10), true)   # diff cover
		for s in [-1.0, 1.0]:
			kit.box_at(Vector3(s * 0.45, AXLE_Y + 0.06, z), Vector3(0.09, 0.05, 0.12), Color(0.10, 0.10, 0.10))    # spring perch
			kit.box_at(Vector3(s * 0.56, AXLE_Y - 0.03, z + (0.16 if z < 0.0 else -0.16)), Vector3(0.05, 0.05, 0.05), Color(0.10, 0.10, 0.10))   # shock mount
		if z < 0.0:
			# the steering knuckles at the wheels and the tie rod behind the axle
			for s2 in [-1.0, 1.0]:
				kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(s2 * 0.72, AXLE_Y - 0.10, z)), 0.06, 0.06, 0.20, 12, Color(0.07, 0.07, 0.07), true)
			_bar(kit, Vector3(-0.74, AXLE_Y - 0.03, z + 0.14), Vector3(0.74, AXLE_Y - 0.03, z + 0.14), 0.016, Color(0.07, 0.07, 0.07))
		kit.smooth(40.0)
		_add(root, kit, String(pair[0]), _mat(Color.WHITE, 0.6, 0.3, true))


## Two-tone paint: the band between tone_lo and tone_hi (heights) in the
## second colour, the rest in the first; trim colours (vertex colours not
## white) are left alone.
static func _tone(kit: RefCounted, ends_plain: bool = true) -> void:
	var a: Color = P["paint"]
	var b: Color = P["paint2"]
	var two: bool = P["two_tone"]
	var lo: float = P["tone_lo"]
	var hi: float = P["tone_hi"]
	# by whole triangles (its middle height), so the colour edge is sharp
	for i in range(0, kit.cols.size(), 3):
		if kit.cols[i] != Color.WHITE:
			continue
		var y: float = (kit.verts[i].y + kit.verts[i + 1].y + kit.verts[i + 2].y) / 3.0
		var c := Color(1, 1, 1, 0)       # banded: the paint shader colours it by height, per pixel
		if ends_plain and absf((kit.norms[i] as Vector3).z) > 0.9:
			c = a           # a panel's end face (a fan from its middle): one colour
		var n: Vector3 = kit.norms[i]
		var vx: float = (kit.verts[i].x + kit.verts[i + 1].x + kit.verts[i + 2].x) / 3.0
		if n.x * signf(vx) < -0.5:
			c = a           # the inside of a panel (bed walls): body colour all over
			var vz: float = (kit.verts[i].z + kit.verts[i + 1].z + kit.verts[i + 2].z) / 3.0
			if y < float(P["arch_top"]) + 0.08 and (absf(vz - FZ) < _alen(FZ) + 0.06 or absf(vz - RZ) < _alen(RZ) + 0.06):
				c = Color(0.035, 0.035, 0.035)   # seen up inside the wheel opening: undercoat, not paint
		# (dust toward the bottom: the paint shader adds it, per pixel)
		kit.cols[i] = c
		kit.cols[i + 1] = c
		kit.cols[i + 2] = c


# ------------------------------------------------------------------------------
#  Doors (DESIGN_NOTES 195): each its own part, hinged at the A pillar
# ------------------------------------------------------------------------------
static func _doors(root: Node3D) -> void:
	var specs := [["", door_z(), true]]
	if style == "suburban":
		specs.append(["Back", P["rear_door"], false])
	for sp in specs:
		_door_pair(root, String(sp[0]), sp[1], bool(sp[2]))


static func _door_pair(root: Node3D, tag: String, dz: Vector2, front: bool) -> void:
	var z0 := dz.x + 0.004
	var z1 := dz.y - 0.004
	var cz: float = P["cowl_z"]
	var gz: float = P["glass_top_z"]
	var belt: float = P["belt_y"]
	var roof: float = P["roof_y"]
	var tum: float = P["tumble"]
	var bz: float = float(P["cab_back_z"]) - 0.03
	var b: float = P["bulge"]
	var cy: float = P["crease_y"]
	for s in [-1.0, 1.0]:
		var n := Node3D.new()
		n.name = ("Door" + tag + "L") if s < 0.0 else ("Door" + tag + "R")
		n.set_meta("hinge", Vector3(s * (float(P["w"]) + b + 0.01), 1.0, z0 + 0.01))
		n.set_meta("side", s)
		root.add_child(n)
		var paint := MeshKit.new()
		var chrome := MeshKit.new()
		var black := MeshKit.new()
		var glass := MeshKit.new()
		var inside := MeshKit.new()
		# the outer skin and its inner wall, the same section as the cab side
		var rings: Array = []
		for z in _stations(z0, z1, 0.10):
			rings.append(_at_z(_side_ring(s, _width(z), _bottom(z, float(P["rocker_y"])), belt), z))
		paint.loft(rings, Color.WHITE, false, false)
		paint._cap(rings[0], GAP, _centroid_of(rings[0]) - _centroid_of(rings[1]))
		paint._cap(rings[rings.size() - 1], GAP, _centroid_of(rings[rings.size() - 1]) - _centroid_of(rings[rings.size() - 2]))
		# the window: its frame follows the A pillar up front, the B pillar behind
		var w := float(P["w"]) - 0.03
		var tw := w - tum
		var a0 := Vector3(s * w, belt + 0.01, cz + 0.06)
		var a1 := Vector3(s * tw, roof - float(P["roof_thick"]) - 0.01, gz + 0.03)
		if not front:
			a0 = Vector3(s * w, belt + 0.01, z0 + 0.03)
			a1 = Vector3(s * tw, roof - float(P["roof_thick"]) - 0.01, z0 + 0.03)
		var b0 := Vector3(s * w, belt + 0.01, z1 - 0.01)
		var b1 := Vector3(s * tw, roof - float(P["roof_thick"]) - 0.01, z1 - 0.05 if not front else minf(z1 - 0.05, bz - 0.05))
		glass.quad(a0, b0, b1, a1, Color.WHITE, Vector3(s, 0, 0))
		var out := Vector3(s * 0.006, 0, 0)
		_bar(chrome, a1 + out, b1 + out, 0.009, Color.WHITE)                  # frame along the top
		_bar(chrome, b0 + out, b1 + out, 0.009, Color.WHITE)                  # and the back edge
		_bar(chrome, a0 + out, a1 + out, 0.009, Color.WHITE)                  # and the front
		# the vent window's divider, just behind the front of the frame
		if front:
			var v0 := a0.lerp(b0, 0.17)
			var v1 := a1.lerp(b1, 0.10)
			_bar(chrome, v0 + out, v1 + out, 0.008, Color.WHITE)
		# window sill weatherstrip, chrome along the outside
		_bar(chrome, Vector3(s * (w + 0.012), belt + 0.004, z0 + 0.02), Vector3(s * (w + 0.012), belt + 0.004, z1 - 0.02), 0.007, Color.WHITE)
		# the trim strips across the door (lined up with the cab's)
		_pin_lines(black, s, z0 + 0.002, z1 - 0.002, chrome)
		# the pull handle with its push button, near the back edge
		var hz := z1 - 0.17
		var hx: float = s * (_width(hz) + b + 0.012)
		chrome.box_at(Vector3(hx, cy + 0.06, hz), Vector3(0.016, 0.03, 0.13), Color.WHITE)
		black.box_at(Vector3(hx - s * 0.004, cy + 0.06, hz), Vector3(0.012, 0.016, 0.09), Color(0.03, 0.03, 0.03))
		chrome.cylinder(Transform3D(Basis(Vector3.BACK, s * PI * 0.5), Vector3(hx, cy + 0.06, hz + 0.075)), 0.011, 0.011, 0.012, 10, Color.WHITE, true)
		# the mirror rides on the door
		if front:
			_mirrors(black, chrome, [s])
		# inside: the door card, armrest, window crank and handle, the lock button
		var ix: float = s * (float(P["w"]) - 0.075)
		var zm := (z0 + z1) * 0.5
		inside.box_at(Vector3(ix, 0.98, zm), Vector3(0.03, 0.74, z1 - z0 - 0.06), Color(0.24, 0.18, 0.14))
		for ry in [0.80, 1.16]:
			inside.box_at(Vector3(ix - s * 0.018, ry, zm), Vector3(0.008, 0.012, z1 - z0 - 0.14), Color(0.17, 0.12, 0.09))   # pleat lines
		inside.box_at(Vector3(ix - s * 0.045, 0.98, zm + 0.12), Vector3(0.07, 0.05, 0.42), Color(0.16, 0.12, 0.09))           # armrest
		inside.box_at(Vector3(ix - s * 0.03, 1.08, zm - 0.22), Vector3(0.03, 0.03, 0.03), Color(0.6, 0.6, 0.58))              # crank hub
		inside.box(Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(ix - s * 0.04, 1.08, zm - 0.18)), Vector3(0.015, 0.015, 0.10), Color(0.6, 0.6, 0.58))   # crank arm
		inside.box_at(Vector3(ix - s * 0.03, 1.10, z0 + 0.20), Vector3(0.02, 0.03, 0.08), Color(0.6, 0.6, 0.58))              # inside handle
		inside.cylinder(Transform3D(Basis.IDENTITY, Vector3(s * (w - 0.04), belt - 0.02, z1 - 0.12)), 0.006, 0.005, 0.05, 8, Color(0.12, 0.10, 0.08), true)   # lock button
		_tone(paint)
		paint.smooth(34.0)
		chrome.smooth(50.0)
		black.smooth(40.0)
		inside.smooth(40.0)
		_add(n, paint, "Paint", _paint_mat())
		_add(n, chrome, "Chrome", _mat(Color.WHITE, 0.18, 1.0, true))
		_add(n, black, "Trim", _mat(Color.WHITE, 0.7, 0.0, true))
		_add(n, inside, "Card", _mat(Color.WHITE, 0.85, 0.0, true))
		_add(n, glass, "Glass", _glass_mat())


# ------------------------------------------------------------------------------
#  Suspension (DESIGN_NOTES 195): parts that move with the axles. Each is a
#  "link" between two points: its mesh is built along +y from 0 to its rest
#  length, and meta "ends" = [a, b, axle_a, axle_b] (axle -1 = on the frame,
#  0 front, 1 rear) says which end rides on which axle. place_link() puts it
#  between where its ends are now; "stretch" links (springs, the drag link)
#  stretch to fit, the shock's two halves slide over each other.
# ------------------------------------------------------------------------------
static func _suspension(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Suspension"
	root.add_child(holder)
	var leafm := _mat(Color.WHITE, 0.55, 0.35, true)
	var chromem := _mat(Color.WHITE, 0.18, 1.0, true)
	for ai in range(2):
		var az: float = FZ if ai == 0 else RZ
		for s in [-1.0, 1.0]:
			var seat := Vector3(s * 0.45, AXLE_Y + 0.085, az)
			# a leaf spring is two halves, hanger to axle and axle to shackle,
			# so it flexes into a V when one end of the axle comes up
			var hang := Vector3(s * 0.45, 0.545, az - 0.62)
			var shack := Vector3(s * 0.45, 0.545, az + 0.62)
			_leaf_half(holder, "Leaf%d%sF" % [ai, "L" if s < 0.0 else "R"], hang, seat, -1, ai, true, leafm)
			_leaf_half(holder, "Leaf%d%sR" % [ai, "L" if s < 0.0 else "R"], seat, shack, ai, -1, false, leafm)
			# the shock: body on the axle, rod down from the frame
			var lo := Vector3(s * 0.56, AXLE_Y - 0.03, az + (0.16 if az < 0.0 else -0.16))
			var hi := Vector3(s * 0.50, 0.75, az + (0.30 if az < 0.0 else -0.30))
			var k1 := MeshKit.new()
			k1.cylinder(Transform3D.IDENTITY, 0.032, 0.032, 0.24, 12, Color(0.15, 0.15, 0.15), true)
			k1.cylinder(Transform3D.IDENTITY, 0.02, 0.02, 0.02, 10, Color(0.05, 0.05, 0.05), true)
			_link(holder, "Shock%d%sBody" % [ai, "L" if s < 0.0 else "R"], k1, leafm, lo, hi, ai, -1, false)
			var k2 := MeshKit.new()
			k2.cylinder(Transform3D.IDENTITY, 0.012, 0.012, 0.25, 10, Color.WHITE, true)
			k2.cylinder(Transform3D.IDENTITY, 0.026, 0.026, 0.02, 10, Color(0.1, 0.1, 0.1), true)
			_link(holder, "Shock%d%sRod" % [ai, "L" if s < 0.0 else "R"], k2, chromem, hi, lo, -1, ai, false)
	# the drag link, from the pitman arm (frame) to the left knuckle (axle)
	var kd := MeshKit.new()
	var da := Vector3(-0.44, 0.48, FZ - 0.34)
	var db := Vector3(-0.72, AXLE_Y + 0.03, FZ - 0.08)
	kd.cylinder(Transform3D.IDENTITY, 0.016, 0.016, (db - da).length(), 10, Color(0.07, 0.07, 0.07), true)
	_link(holder, "DragLink", kd, leafm, da, db, -1, 0, true)


static func _leaf_half(holder: Node3D, nm: String, a: Vector3, b: Vector3, ax_a: int, ax_b: int, toward_b: bool, m: Material) -> void:
	var L := (b - a).length()
	var kit := MeshKit.new()
	for leaf in range(3):
		var frac := 1.0 - leaf * 0.24                     # each leaf shorter than the one above
		var y0 := (1.0 - frac) * L if toward_b else 0.0   # the short leaves bunch up at the axle
		var y1 := L if toward_b else frac * L
		# local z is down (x lateral, y along the half toward +z in the truck)
		kit.box_at(Vector3(0, (y0 + y1) * 0.5, leaf * 0.013), Vector3(0.06, y1 - y0, 0.011), Color(0.10, 0.10, 0.10))
	kit.box_at(Vector3(0, 0.0 if toward_b else L, 0), Vector3(0.07, 0.04, 0.04), Color(0.06, 0.06, 0.06))   # spring eye
	_link(holder, nm, kit, m, a, b, ax_a, ax_b, true)


static func _link(holder: Node3D, nm: String, kit: RefCounted, m: Material, a: Vector3, b: Vector3, ax_a: int, ax_b: int, stretch: bool) -> void:
	kit.smooth(40.0)
	var mi: MeshInstance3D = kit.instance(nm)
	mi.material_override = m
	mi.set_meta("ends", [a, b, ax_a, ax_b])
	mi.set_meta("rest_len", (b - a).length())
	mi.set_meta("stretch", stretch)
	holder.add_child(mi)
	place_link(mi, a, b)


## Put a link between a and b (its ends now). `turn`: about its own length.
static func place_link(n: Node3D, a: Vector3, b: Vector3, turn: float = 0.0) -> void:
	var d := b - a
	var L := d.length()
	if L < 1e-5:
		return
	var y := d / L
	var x := Vector3.RIGHT - y * y.x
	if x.length() < 1e-4:
		x = Vector3.BACK
	x = x.normalized()
	var z := x.cross(y)
	var k: float = L / maxf(float(n.get_meta("rest_len", L)), 1e-4) if bool(n.get_meta("stretch", false)) else 1.0
	var bas := Basis(x, y * k, z)
	if turn != 0.0:
		bas = bas * Basis(Vector3.UP, turn)
	n.transform = Transform3D(bas, a)
