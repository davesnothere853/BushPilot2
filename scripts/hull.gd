extends RefCounted
## Keeps a machine's body out of the ground (DESIGN_NOTES 99). The wheels or
## tracks hold it up on springs, but the hull itself - bumpers, corners, cab
## roof - used to have no collision: nose into a deep, steep-sided hole and
## it went straight through the far wall. Each step, any hull point more
## than a hand's depth into the ground is pushed back out the short way
## (sideways out of a wall, up out of a floor) and the speed into it is
## taken away.

const SLACK := 0.12               # this much in is the springs' business


## Corners and mid points of a box `half` (half extents) around `centre`,
## in the body frame.
static func box_points(centre: Vector3, half: Vector3) -> Array:
	var out: Array = []
	for x in [-1.0, 1.0]:
		for z in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			for y in [-1.0, 0.0, 1.0]:
				out.append(centre + Vector3(x * half.x, y * half.y, z * half.z))
	for z2 in [-1.0, 1.0]:
		out.append(centre + Vector3(0, 0, z2 * half.z))          # nose and tail, mid height
	return out


## read once: OS.has_environment ran on every sub-step (DESIGN_NOTES 186)
static var _hull_off: bool = OS.has_environment("HULLOFF")

## Push the body out of the ground, turning it as well as moving it (a
## corner caught in a wall swings the body round, the way a real impact
## would). Returns [pos, basis, vel, angvel, hit] (hit: m/s into the ground).
## dt > 0: the ground also grips what's on it (a truck on its roof or side
## scrapes to a stop and stops spinning, it doesn't skate). DESIGN_NOTES 206.
static func resolve(pos: Vector3, basis: Basis, vel: Vector3, angvel: Vector3, pts: Array, ground: Callable, dt: float = 0.0, mu: float = 0.65) -> Array:
	var hit := 0.0
	var touching := 0
	var nsum := Vector3.ZERO
	if _hull_off:
		return [pos, basis, vel, angvel, 0.0]
	for it in range(8):
		var any := false
		for lc in pts:
			var r: Vector3 = basis * (lc as Vector3)
			var p: Vector3 = pos + r
			var gy: float = ground.call(p.x, p.z)
			var pen := gy - p.y
			if pen <= SLACK:
				continue
			any = true
			var out := _way_out(p, pen, ground)
			if it == 0:
				touching += 1
				nsum += out.normalized()
			# share the correction between moving and turning the body
			pos += out * 0.6
			var axis := r.cross(out)
			var al := axis.length()
			if al > 0.00001:
				var ang := minf(al / (r.length_squared() + 0.6) * 0.4, 0.08)
				basis = (Basis(axis / al, ang) * basis).orthonormalized()
			var n := out.normalized()
			var vp := vel + angvel.cross(r)
			var into := vp.dot(-n)
			if into > 0.0:
				hit = maxf(hit, into)
				vel += n * minf(into, vel.dot(-n) if vel.dot(-n) > 0.0 else 0.0)
				angvel *= 0.9
		if not any:
			break
	if dt > 0.0 and touching > 0:
		# sliding friction on the ground's plane: about mu g of slowing, more
		# the more of the hull is down; and the spin scrubbed off with it
		var n := nsum.normalized()
		var vt := vel - n * vel.dot(n)
		var share := clampf(float(touching) / 6.0, 0.35, 1.0)
		var dv := minf(vt.length(), mu * 9.81 * dt * share * 1.6)
		if vt.length() > 0.0001:
			vel -= vt.normalized() * dv
		angvel *= maxf(1.0 - 4.0 * share * dt, 0.0)
	return [pos, basis, vel, angvel, hit]


## The short way out of the ground for a point `pen` under it: sideways
## down the slope if it's in a wall, otherwise up.
static func _way_out(p: Vector3, pen: float, ground: Callable) -> Vector3:
	var e := 0.25
	var gx: float = float(ground.call(p.x + e, p.z)) - float(ground.call(p.x - e, p.z))
	var gz: float = float(ground.call(p.x, p.z + e)) - float(ground.call(p.x, p.z - e))
	var slope := Vector2(gx, gz) / (2.0 * e)
	if slope.length() > 1.2:
		var dir := Vector3(-slope.x, 0, -slope.y).normalized()
		for k in range(1, 26):
			var q := p + dir * 0.08 * float(k)
			if float(ground.call(q.x, q.z)) <= p.y + SLACK:
				return dir * 0.08 * float(k)
	return Vector3.UP * (pen - SLACK)
