extends RefCounted
## The square's layout from a seed (DESIGN_NOTES 93). Same seed, same world.
##
## Fixed: the airstrip, apron, hangar and tool yard in the south, which the
## buildings are placed around. Made from the seed: the rolling ground, a
## rock knoll, which side the muskeg lies on, the pond in the low ground
## there, the creek running downhill from the knoll to the pond, buried
## ancient channels with pay gravel on bedrock (richest on the inside of
## bends), a bench-gravel terrace above the creek, and the mining pad on the
## best stretch of pay that's easy to reach.

const SQ := 180.0
const VERSION := 1

## Kept clear of features: the strip and the apron/hangar.
static func keep_out(x: float, z: float, pad: float = 0.0) -> bool:
	if absf(x) < 160.0 + pad and absf(z + 130.0) < 22.0 + pad:
		return true
	if absf(x + 25.0) < 90.0 + pad and absf(z + 94.0) < 40.0 + pad:
		return true
	return false


static func make(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var L := {"seed": seed_value, "version": VERSION}
	# --- rolling ground: the old map's waves, phases and pitch from the seed
	L["waves"] = [
		[rng.randf_range(0.018, 0.024), rng.randf_range(0.015, 0.019), rng.randf() * TAU, rng.randf() * TAU, 2.4],
		[rng.randf_range(0.04, 0.052), rng.randf_range(0.035, 0.044), rng.randf() * TAU, rng.randf() * TAU, 1.1],
		[rng.randf_range(0.10, 0.12), rng.randf_range(0.08, 0.10), rng.randf() * TAU, rng.randf() * TAU, 0.4],
	]
	# --- muskeg on one side (never the south: that's the strip)
	var sides := [Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0)]
	var bdir: Vector2 = sides[rng.randi() % sides.size()]
	var b0 := rng.randf_range(72.0, 92.0)
	L["bog"] = [bdir, b0, b0 + rng.randf_range(30.0, 40.0)]
	# --- the knoll: up off the muskeg, clear of the strip
	var knoll := Vector2.ZERO
	for t in range(200):
		knoll = Vector2(rng.randf_range(-140.0, 140.0), rng.randf_range(-45.0, 120.0))
		if knoll.dot(bdir) < b0 - 45.0 and not keep_out(knoll.x, knoll.y, 30.0):
			break
	L["knoll"] = [knoll, rng.randf_range(40.0, 52.0), rng.randf_range(11.0, 16.0)]
	# --- the pond: low ground on the muskeg side, back from the edges
	var best := Vector2.ZERO
	var best_h := 1.0e9
	for t in range(80):
		var c := Vector2(rng.randf_range(-140.0, 140.0), rng.randf_range(-20.0, 140.0))
		if c.dot(bdir) < b0 - 25.0 or c.distance_to(knoll) < 90.0 or keep_out(c.x, c.y, 40.0):
			continue
		var h := base_height(L, c.x, c.y)
		if h < best_h:
			best_h = h
			best = c
	if best_h > 1.0e8:
		best = bdir * (b0 + 15.0) + Vector2(bdir.y, bdir.x) * 60.0
	L["pond"] = [best, rng.randf_range(23.0, 29.0)]
	# --- the creek: off the knoll's flank, downhill to the pond, meandering
	L["creek"] = _creek(L, rng)
	# --- buried channels: the old creek's valley, a little off the new one,
	# and sometimes a second, older one across the claim
	var chans: Array = []
	chans.append(_channel_near(L["creek"], rng, rng.randf_range(8.0, 22.0) * (1.0 if rng.randf() < 0.5 else -1.0)))
	if rng.randf() < 0.65:
		chans.append(_channel_across(L, rng))
	L["channels"] = chans
	# --- a bench terrace above the creek, on one side
	L["bench"] = _offset_line(L["creek"], rng.randf_range(24.0, 34.0) * (1.0 if rng.randf() < 0.5 else -1.0), 0.0, rng)
	# --- the mining pad: richest easy-to-reach pay on the first channel
	L["pad"] = _pick_pad(L)
	return L


## The ground before the creek and pond are cut into it (used to route them).
static func base_height(L: Dictionary, x: float, z: float) -> float:
	var h := 6.0
	for w in L["waves"]:
		h += sin(x * float(w[0]) + float(w[2])) * cos(z * float(w[1]) + float(w[3])) * float(w[4])
	var kn: Array = L["knoll"]
	var k := maxf(0.0, 1.0 - Vector2(x, z).distance_to(kn[0]) / float(kn[1]))
	h += k * k * float(kn[2])
	var b := bog_weight(L, x, z)
	h = lerpf(h, 4.7 + sin((x + z) * 0.05) * 0.3, b * 0.85)
	return h


static func bog_weight(L: Dictionary, x: float, z: float) -> float:
	var bg: Array = L["bog"]
	var d := Vector2(clampf(x, -SQ, SQ), clampf(z, -SQ, SQ)).dot(bg[0])
	return smoothstep(float(bg[1]), float(bg[2]), d)


static func _creek(L: Dictionary, rng: RandomNumberGenerator) -> Array:
	var kn: Array = L["knoll"]
	var pond: Vector2 = L["pond"][0]
	var to_pond := (pond - (kn[0] as Vector2)).normalized()
	var start: Vector2 = (kn[0] as Vector2) + to_pond.rotated(rng.randf_range(-0.6, 0.6)) * float(kn[1]) * 0.55
	var pts: Array = [start]
	var p := start
	var heading := (pond - p).normalized()
	var phase := rng.randf() * TAU
	var wav := rng.randf_range(0.035, 0.06)
	var amp := rng.randf_range(0.35, 0.6)
	var step := 4.0
	for i in range(160):
		# downhill, toward the pond, with a meander
		var e := 2.0
		var gx := base_height(L, p.x + e, p.y) - base_height(L, p.x - e, p.y)
		var gz := base_height(L, p.x, p.y + e) - base_height(L, p.x, p.y - e)
		var down := -Vector2(gx, gz)
		var aim := (pond - p).normalized()
		var want := (aim * 1.0 + down.normalized() * 0.6 if down.length() > 0.001 else aim).normalized()
		want = want.rotated(sin(float(i) * step * wav + phase) * amp)
		heading = heading.lerp(want, 0.35).normalized()
		var nxt := p + heading * step
		if keep_out(nxt.x, nxt.y, 8.0):
			nxt.y = maxf(nxt.y, -50.0)
		nxt = nxt.clamp(Vector2(-SQ + 8.0, -SQ + 8.0), Vector2(SQ - 8.0, SQ - 8.0))
		p = nxt
		if i % 4 == 3:
			pts.append(p)
		if p.distance_to(pond) < float(L["pond"][1]) * 0.8:
			break
	pts.append(p)
	return pts


## A buried channel near a line: the same valley, shifted, with its own
## older meanders.
static func _channel_near(line: Array, rng: RandomNumberGenerator, shift: float) -> Dictionary:
	var pts := _offset_line(line, shift, rng.randf_range(6.0, 14.0), rng)
	return {"pts": _densify(pts, 6.0), "w": rng.randf_range(6.0, 10.0), "rich": rng.randf_range(0.9, 1.3), "seed": rng.randi()}


## An older channel across the claim, clear of the strip.
static func _channel_across(L: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var a := Vector2(rng.randf_range(-150.0, 150.0), rng.randf_range(-40.0, 40.0))
	var b := Vector2(-a.x * rng.randf_range(0.5, 1.0), rng.randf_range(60.0, 150.0))
	var pts: Array = []
	var n := 24
	var phase := rng.randf() * TAU
	var amp := rng.randf_range(8.0, 20.0)
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	for i in range(n + 1):
		var t := float(i) / float(n)
		var q := a.lerp(b, t) + side * sin(t * TAU * rng.randf_range(1.2, 1.4) + phase) * amp
		if keep_out(q.x, q.y, 10.0):
			continue
		pts.append(q)
	return {"pts": _densify(pts, 6.0), "w": rng.randf_range(5.0, 8.0), "rich": rng.randf_range(0.6, 1.0), "seed": rng.randi()}


static func _offset_line(line: Array, shift: float, wobble: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var phase := rng.randf() * TAU
	for i in range(line.size()):
		var a: Vector2 = line[maxi(i - 1, 0)]
		var b: Vector2 = line[mini(i + 1, line.size() - 1)]
		var d := (b - a).normalized()
		var side := Vector2(-d.y, d.x)
		var q: Vector2 = (line[i] as Vector2) + side * (shift + sin(float(i) * 0.9 + phase) * wobble)
		if not keep_out(q.x, q.y, 6.0):
			out.append(q.clamp(Vector2(-SQ + 4.0, -SQ + 4.0), Vector2(SQ - 4.0, SQ - 4.0)))
	return out


static func _densify(pts: Array, step: float) -> Array:
	if pts.size() < 2:
		return pts
	var out: Array = [pts[0]]
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var m := maxi(int(a.distance_to(b) / step), 1)
		for k in range(1, m + 1):
			out.append(a.lerp(b, float(k) / float(m)))
	return out


## How rich a channel runs at arc length s: patchy along its length.
static func richness(ch: Dictionary, s: float) -> float:
	var sd := float(int(ch["seed"]) % 1000)
	var w := 0.5 + 0.5 * sin(s * 0.045 + sd) * sin(s * 0.017 + sd * 0.3)
	return float(ch["rich"]) * (0.5 + 3.5 * pow(clampf(w, 0.0, 1.0), 1.6))


## Closest approach to a polyline: [distance, arc length there, signed side
## (+ left of the flow), curvature there (+ turning left)].
static func closest(pts: Array, p: Vector2) -> Array:
	var best := 1.0e9
	var best_s := 0.0
	var best_side := 0.0
	var best_i := 0
	var s := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
		var c := a + ab * t
		var d := p.distance_to(c)
		if d < best:
			best = d
			best_s = s + sqrt(l2) * t
			best_side = signf(ab.cross(p - a))
			best_i = i
		s += sqrt(l2)
	var curv := 0.0
	if best_i > 0 and best_i < pts.size() - 2:
		var d0: Vector2 = (pts[best_i] as Vector2) - (pts[best_i - 1] as Vector2)
		var d1: Vector2 = (pts[best_i + 2] as Vector2) - (pts[best_i + 1] as Vector2)
		curv = d0.normalized().cross(d1.normalized())
	return [best, best_s, best_side, curv]


## The pad: the best grade on the main channel that's dry, flat-ish ground
## and clear of the strip.
static func _pick_pad(L: Dictionary) -> Vector2:
	var ch: Dictionary = L["channels"][0]
	var pts: Array = ch["pts"]
	var best: Vector2 = pts[pts.size() / 2] if not pts.is_empty() else Vector2(75, 60)
	var best_v := -1.0
	var s := 0.0
	for i in range(1, pts.size()):
		s += (pts[i] as Vector2).distance_to(pts[i - 1])
		var q: Vector2 = pts[i]
		if keep_out(q.x, q.y, 25.0) or bog_weight(L, q.x, q.y) > 0.3:
			continue
		if q.distance_to(L["pond"][0]) < float(L["pond"][1]) + 25.0 or absf(q.x) > SQ - 25.0 or absf(q.y) > SQ - 25.0:
			continue
		var kn: Array = L["knoll"]
		if q.distance_to(kn[0]) < float(kn[1]) * 0.6:
			continue
		var v := richness(ch, s)
		if v > best_v:
			best_v = v
			best = q
	return best
