extends Node3D
## Mine track and ore cars (DESIGN_NOTES 151), the way the small drift mines
## moved their muck: narrow-gauge track (24 in / 610 mm gauge, light 16 lb
## rail spiked to timber ties every 0.6 m) laid down the drift a section at
## a time, and a side-dump ore car you shovel into at the face and push out
## to the portal by hand, then tip.
##
##  - Track sections come 3 m long (two rails, five ties, the fishplates and
##    spikes): 26 kg, one at a time in your hands. With one in hand, E lays
##    it - on the end of the track nearest you, carrying it on the way
##    you're facing (a few degrees of curve a section), or a fresh start
##    under your feet. It follows the floor: the drift's, or the ground's.
##  - The ore car: a 0.7 m3 V-tub on a frame, four flanged wheels, a coupler
##    each end, the tub on a rocker so it tips to either side. Walk into its
##    end and push: it rolls with you along the rails, and on its own down a
##    grade (and back down to you if you leave it on one). Shovelling at the
##    face or digging within 3 m of it throws the muck in; a rock carried up
##    to it goes in too. E beside it tips the tub - into the wash plant's
##    hopper if it's alongside, otherwise a pile by the track.
##  - Pay gravel in the car carries its gold to wherever it's dumped.

const MeshKit = preload("res://scripts/meshkit.gd")
const SAVE := "user://rails.cfg"
const GAUGE := 0.61
const SEG_L := 3.0
const CAR_M3 := 0.7
const BITE_M3 := 0.12           # what one go with the shovel throws in
const RAIL := Color(0.30, 0.28, 0.27)
const TIE := Color(0.36, 0.27, 0.18)
const STEEL := Color(0.38, 0.37, 0.36)
const CAR_C := Color(0.30, 0.34, 0.30)

var terrain: RefCounted
var vox: Node                   # voxel_ground.gd
var prospect: Node
var inv: Node
var walker: Node3D
var hud: Control

var segs: Array = []            # [a: Vector3, b: Vector3] world, on the floor
var cars: Array = []            # {seg, s (m along it), v (m/s), load {pay, over, g}, node}
var prompt := ""
var _target := ""
var _seg_nodes: Array = []
var _dirty := false
var _save_t := 0.0


func _ready() -> void:
	_load()


# ==============================================================================
#  Track
# ==============================================================================
## The floor under (x, z) near height y: a drift floor, or the ground.
func _floor(x: float, z: float, y: float) -> float:
	var g: float = terrain.height_at(x, z)
	# in a drift (well under the surface): its floor; out in the open: the ground
	if vox != null and y < g - 1.0 and vox.ready_at(Vector3(x, y, z)):
		var f: float = vox.floor_below(Vector3(x, y + 0.6, z), 4.0)
		if f != -INF:
			return f
	return g


## The open end of the track nearest p (within r): [point, direction out], or [].
func _end_near(p: Vector3, r: float) -> Array:
	var best: Array = []
	var bd := r
	for i in range(segs.size()):
		var a: Vector3 = segs[i][0]
		var b: Vector3 = segs[i][1]
		for e in [[b, (b - a).normalized(), a], [a, (a - b).normalized(), b]]:
			var pt: Vector3 = e[0]
			if _joined(pt, i):
				continue
			var d := Vector2(pt.x - p.x, pt.z - p.z).length()
			if d < bd and absf(pt.y - p.y) < 2.0:
				bd = d
				best = [pt, e[1]]
	return best


func _joined(pt: Vector3, skip: int) -> bool:
	for j in range(segs.size()):
		if j == skip:
			continue
		if (segs[j][0] as Vector3).distance_to(pt) < 0.25 or (segs[j][1] as Vector3).distance_to(pt) < 0.25:
			return true
	return false


## Lay a section: from the nearest open end (bent toward `facing` by up to
## 12 degrees), or a new start at p heading `facing`.
func lay(p: Vector3, facing: Vector3) -> String:
	facing.y = 0.0
	facing = facing.normalized()
	var start := p
	var dir := facing
	var end := _end_near(p, 2.5)
	if not end.is_empty():
		start = end[0]
		var d0: Vector3 = end[1]
		d0.y = 0.0
		d0 = d0.normalized()
		var ang := clampf(d0.signed_angle_to(facing, Vector3.UP), -0.21, 0.21)
		dir = d0.rotated(Vector3.UP, ang)
	else:
		start.y = _floor(p.x, p.z, p.y)
	var b := start + dir * SEG_L
	b.y = _floor(b.x, b.z, start.y)
	if absf(b.y - start.y) > 0.6:
		return "Too steep there for track: level the floor first."
	if prospect != null and prospect.has_method("strip_or_building") and prospect.strip_or_building(b):
		return "Not on the runway or in the buildings."
	segs.append([start, b])
	_build_seg(segs.size() - 1)
	_dirty = true
	return "Track laid: %.0f m of it now. %s" % [float(segs.size()) * SEG_L, "Carried on from the end." if not end.is_empty() else "A new line."]


func _build_seg(i: int) -> void:
	var a: Vector3 = segs[i][0]
	var b: Vector3 = segs[i][1]
	var k := MeshKit.new()
	var d := b - a
	var l := d.length()
	var z := d / l
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	var bas := Basis(x, y, z)
	# ties every 0.6 m, each settled to the floor under it
	var nt := int(l / 0.6)
	for t in range(nt):
		var c := a + z * (0.3 + 0.6 * float(t))
		c.y = _floor(c.x, c.z, a.y) + 0.05
		k.box(Transform3D(bas, c), Vector3(1.05, 0.1, 0.16), TIE.darkened(0.12 * float(t % 3)))
		for sx in [-GAUGE * 0.5, GAUGE * 0.5]:
			k.box(Transform3D(bas, c + x * sx + y * 0.055), Vector3(0.12, 0.012, 0.13), STEEL)     # tie plates
			for sp in [-0.04, 0.04]:
				k.box(Transform3D(bas, c + x * (sx + sp) + y * 0.07), Vector3(0.015, 0.03, 0.015), STEEL.darkened(0.3))
	# the rails: base, web, head
	for sx2 in [-GAUGE * 0.5, GAUGE * 0.5]:
		var c2: Vector3 = (a + b) * 0.5 + x * float(sx2) + y * 0.1
		k.box(Transform3D(bas, c2 + y * -0.025), Vector3(0.065, 0.01, l), RAIL)
		k.box(Transform3D(bas, c2), Vector3(0.012, 0.045, l), RAIL)
		k.box(Transform3D(bas, c2 + y * 0.03), Vector3(0.032, 0.02, l), RAIL.lightened(0.25))
		# fishplate at the joint
		k.box(Transform3D(bas, a + x * sx2 + y * 0.1), Vector3(0.05, 0.035, 0.3), STEEL)
	var mi := k.instance("Track%d" % i)
	add_child(mi)
	while _seg_nodes.size() <= i:
		_seg_nodes.append(null)
	_seg_nodes[i] = mi


## Point on segment i at distance s from its start, on the railhead.
func _at(i: int, s: float) -> Vector3:
	var a: Vector3 = segs[i][0]
	var b: Vector3 = segs[i][1]
	return a.lerp(b, clampf(s / a.distance_to(b), 0.0, 1.0)) + Vector3(0, 0.13, 0)


## The segment joined to segment i at its end `at_end` (true: b), and which
## of that one's ends it is: [index, joins at its b], or [-1, false].
func _next(i: int, at_end: bool) -> Array:
	var pt: Vector3 = segs[i][1] if at_end else segs[i][0]
	for j in range(segs.size()):
		if j == i:
			continue
		if (segs[j][0] as Vector3).distance_to(pt) < 0.25:
			return [j, false]
		if (segs[j][1] as Vector3).distance_to(pt) < 0.25:
			return [j, true]
	return [-1, false]


# ==============================================================================
#  Ore cars
# ==============================================================================
func add_car(seg: int, s: float, load: Dictionary = {}) -> void:
	var c := {"seg": seg, "s": s, "v": 0.0, "load": load, "node": _car_node()}
	add_child(c["node"])
	cars.append(c)
	_place_car(c)
	_dirty = true


## A side-dump ore car: a V-tub on a rocker, a steel frame, four flanged
## wheels, a coupler at each end.
func _car_node() -> Node3D:
	var root := Node3D.new()
	var k := MeshKit.new()
	# frame and axles
	for sx in [-0.3, 0.3]:
		k.box_at(Vector3(sx, 0.32, 0), Vector3(0.08, 0.1, 1.3), STEEL)
	for az in [-0.42, 0.42]:
		k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.38, 0.17, az)), 0.035, 0.035, 0.76, 8, STEEL.darkened(0.2))
		for sx2 in [-GAUGE * 0.5, GAUGE * 0.5]:
			# wheel: tread and flange on the inside
			k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx2 + 0.04, 0.17, az)), 0.16, 0.16, 0.07, 12, STEEL.darkened(0.35))
			k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx2 - signf(sx2) * 0.035 + 0.01, 0.17, az)), 0.19, 0.19, 0.02, 12, STEEL.darkened(0.4))
	for ez in [-0.72, 0.72]:
		k.box_at(Vector3(0, 0.33, ez), Vector3(0.16, 0.1, 0.14), STEEL.darkened(0.2))        # couplers
		k.box_at(Vector3(0, 0.33, ez + signf(ez) * 0.1), Vector3(0.06, 0.06, 0.1), STEEL)
	# rocker cradles the tub sits in
	for rz in [-0.35, 0.35]:
		k.box_at(Vector3(0, 0.42, rz), Vector3(0.7, 0.08, 0.1), STEEL)
	root.add_child(k.instance("Frame"))
	var tub := Node3D.new()
	tub.name = "Tub"
	tub.position = Vector3(0, 0.46, 0)
	var t := MeshKit.new()
	# the V: two sloping sides meeting at a rounded bottom, flat ends
	var prof := [Vector2(-0.48, 0.62), Vector2(-0.34, 0.12), Vector2(-0.12, 0.0), Vector2(0.12, 0.0), Vector2(0.34, 0.12), Vector2(0.48, 0.62)]
	for i in range(prof.size() - 1):
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		var n := Vector3(p1.y - p0.y, -(p1.x - p0.x), 0).normalized()
		t.quad(Vector3(p0.x, p0.y, -0.6), Vector3(p1.x, p1.y, -0.6), Vector3(p1.x, p1.y, 0.6), Vector3(p0.x, p0.y, 0.6), CAR_C, -n)
		t.quad(Vector3(p0.x, p0.y, 0.6), Vector3(p1.x, p1.y, 0.6), Vector3(p1.x, p1.y, -0.6), Vector3(p0.x, p0.y, -0.6), CAR_C.darkened(0.3), n)
	for ez2 in [-0.6, 0.6]:
		for i2 in range(prof.size() - 1):
			var a2: Vector2 = prof[i2]
			var b2: Vector2 = prof[i2 + 1]
			t.tri(Vector3(0, 0.35, ez2), Vector3(a2.x, a2.y, ez2), Vector3(b2.x, b2.y, ez2), CAR_C.darkened(0.1), Vector3(0, 0, signf(ez2)))
			t.tri(Vector3(0, 0.35, ez2), Vector3(b2.x, b2.y, ez2), Vector3(a2.x, a2.y, ez2), CAR_C.darkened(0.3), Vector3(0, 0, -signf(ez2)))
		t.tri(Vector3(0, 0.35, ez2), Vector3(prof[5].x, prof[5].y, ez2), Vector3(prof[0].x, prof[0].y, ez2), CAR_C.darkened(0.1), Vector3(0, 0, signf(ez2)))
	# a rolled rim, two bands, the tipping latch
	for sx3 in [-0.48, 0.48]:
		t.box_at(Vector3(sx3, 0.62, 0), Vector3(0.05, 0.05, 1.22), CAR_C.darkened(0.2))
	for bz in [-0.3, 0.3]:
		t.box_at(Vector3(0, 0.31, bz), Vector3(1.0, 0.04, 0.05), CAR_C.darkened(0.25))
	t.box_at(Vector3(0, 0.25, 0.62), Vector3(0.08, 0.2, 0.04), STEEL)
	tub.add_child(t.instance("TubMesh"))
	var muck := MeshInstance3D.new()
	muck.name = "Muck"
	var mk := MeshKit.new()
	mk.box_at(Vector3(0, 0.0, 0), Vector3(0.8, 0.06, 1.1), Color(0.38, 0.31, 0.22))
	for i3 in range(5):
		mk.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.3 + 0.15 * float(i3), 0.02, -0.3 + 0.15 * float(i3 % 3))), 0.22, 0.0, 0.18, 6, Color(0.42, 0.34, 0.24).darkened(0.08 * float(i3 % 3)), false)
	muck.mesh = mk.commit()
	muck.material_override = MeshKit.material()
	muck.visible = false
	tub.add_child(muck)
	root.add_child(tub)
	return root


func _place_car(c: Dictionary) -> void:
	var i: int = c["seg"]
	if i < 0 or i >= segs.size():
		return
	var a: Vector3 = segs[i][0]
	var b: Vector3 = segs[i][1]
	var p := _at(i, float(c["s"])) - Vector3(0, 0.13, 0)
	var z := (b - a).normalized()
	var x := Vector3.UP.cross(z).normalized()
	var n: Node3D = c["node"]
	n.global_transform = Transform3D(Basis(x, z.cross(x), z), p + Vector3(0, 0.12, 0))
	var m3 := _m3(c)
	var muck: MeshInstance3D = n.get_node("Tub/Muck")
	muck.visible = m3 > 0.02
	muck.position = Vector3(0, 0.08 + 0.5 * clampf(m3 / CAR_M3, 0.0, 1.0), 0)


func _m3(c: Dictionary) -> float:
	var l: Dictionary = c["load"]
	return float(l.get("pay", 0.0)) + float(l.get("over", 0.0)) + float(l.get("rock", 0.0))


func _car_pos(c: Dictionary) -> Vector3:
	return (c["node"] as Node3D).global_position


## Shovelling near a car: the muck goes in. `layer`: "pay", "over", "rock";
## g: grams of gold a cubic metre. Returns a line for the HUD, or "".
func load_near(p: Vector3, layer: String, g_m3: float) -> String:
	for c in cars:
		if _car_pos(c).distance_to(p) < 3.0:
			var room := CAR_M3 - _m3(c)
			if room <= 0.005:
				return "The car's full: push it out and tip it."
			var put := minf(BITE_M3, room)
			var l: Dictionary = c["load"]
			var k := "pay" if layer == "pay" else ("rock" if layer == "rock" else "over")
			l[k] = float(l.get(k, 0.0)) + put
			if layer == "pay":
				l["g"] = float(l.get("g", 0.0)) + g_m3 * put
			_place_car(c)
			_dirty = true
			return "Into the car: %.2f / %.1f m3%s." % [_m3(c), CAR_M3, " - full" if _m3(c) >= CAR_M3 - 0.01 else ""]
	return ""


func _physics_process(delta: float) -> void:
	for c in cars:
		var i: int = c["seg"]
		if i < 0 or i >= segs.size():
			continue
		var a: Vector3 = segs[i][0]
		var b: Vector3 = segs[i][1]
		var l := a.distance_to(b)
		var dir := (b - a) / l
		# pushed: the walker leaning on an end, moving along the line
		var v := float(c["v"])
		if walker != null and walker.visible and walker.get("in_plane") != true:
			var cp := _car_pos(c)
			var wp: Vector3 = walker.global_position
			var rel := wp - cp
			var along := rel.dot(dir)
			var side := (rel - dir * along).length()
			var wv: Vector3 = walker.get("vel") if walker.get("vel") != null else Vector3.ZERO
			var wv_along := wv.dot(dir)
			if side < 0.7 and absf(along) < 1.25 and absf(along) > 0.55 and absf(rel.y) < 1.2:
				# behind the end, walking toward it: it goes with him
				if (along < 0.0 and wv_along > 0.2) or (along > 0.0 and wv_along < -0.2):
					v = wv_along * 0.95
		# the grade: it runs downhill by itself; rolling resistance holds it on the level
		var grade := (b.y - a.y) / l
		var m3 := _m3(c)
		v += -9.81 * grade * delta
		var rr := 0.12 * delta
		v = move_toward(v, 0.0, rr)
		c["v"] = v
		var s := float(c["s"]) + v * delta
		# off an end: on to the next section, or stop at the bumper
		if s > l or s < 0.0:
			var forward := s > l
			var nx := _next(i, forward)
			if int(nx[0]) < 0:
				s = clampf(s, 0.3, l - 0.3) if l > 0.6 else l * 0.5
				c["v"] = 0.0
			else:
				var j: int = nx[0]
				var at_b: bool = nx[1]
				var over := (s - l) if forward else -s
				var lj := (segs[j][0] as Vector3).distance_to(segs[j][1])
				var spd := absf(v)
				c["seg"] = j
				if at_b:
					s = lj - over          # in at its b end: running back toward a
					c["v"] = -spd
				else:
					s = over
					c["v"] = spd
		c["s"] = s
		if absf(v) > 0.001 or m3 >= 0.0:
			_place_car(c)
	_save_t += delta
	if _dirty and _save_t > 5.0:
		_save_t = 0.0
		_dirty = false
		save()


# ==============================================================================
#  The E key
# ==============================================================================
func find_target() -> void:
	prompt = ""
	_target = ""
	if walker == null or inv == null:
		return
	var p: Vector3 = walker.global_position
	var hint: String = Game.hint("interact")
	if inv.holding("rail"):
		var end := _end_near(p, 2.5)
		_target = "lay"
		prompt = "%s  Lay a section of track %s" % [hint, "on from the end here" if not end.is_empty() else "starting here, the way you're facing"]
		return
	for ci in range(cars.size()):
		var c: Dictionary = cars[ci]
		var cp := _car_pos(c)
		if cp.distance_to(p) < 1.6:
			var m3 := _m3(c)
			if m3 > 0.02:
				_target = "tip:%d" % ci
				var hop := _hopper(cp)
				prompt = "%s  Tip the car (%.2f m3%s)%s   walk into an end to push it" % [hint, m3, ", pay" if float(c["load"].get("pay", 0.0)) > 0.01 else "", " into the hopper" if hop != Vector3.INF else ""]
			else:
				prompt = "Ore car, empty. Shovel at the face within 3 m of it to fill it; walk into an end to push it."
			return
	if inv.has("car_kit") and not _end_near(p, 3.0).is_empty():
		_target = "car"
		prompt = "%s  Set the ore car on the track" % hint


func _hopper(p: Vector3) -> Vector3:
	if prospect == null or not prospect.has_method("hopper_near"):
		return Vector3.INF
	return prospect.hopper_near(p)


func interact(facing: Vector3) -> bool:
	if _target == "":
		return false
	var p: Vector3 = walker.global_position
	if _target == "lay":
		var m := lay(p, facing)
		if m.begins_with("Track laid"):
			inv.remove("rail", 1)
		_say(m)
		return true
	if _target == "car":
		var end := _end_near(p, 3.0)
		for i in range(segs.size()):
			if (segs[i][0] as Vector3).distance_to(end[0]) < 0.3 or (segs[i][1] as Vector3).distance_to(end[0]) < 0.3:
				var sa: bool = (segs[i][0] as Vector3).distance_to(end[0]) < 0.3
				add_car(i, 0.8 if sa else (segs[i][0] as Vector3).distance_to(segs[i][1]) - 0.8)
				inv.remove("car_kit", 1)
				_say("The ore car's on the rails.")
				return true
		return false
	if _target.begins_with("tip:"):
		var c: Dictionary = cars[int(_target.substr(4))]
		var cp := _car_pos(c)
		var at := _hopper(cp)
		if at == Vector3.INF:
			var side := (c["node"] as Node3D).global_transform.basis.x
			at = cp + side * 1.1
			at.y = _floor(at.x, at.z, cp.y)
		var ld: Dictionary = (c["load"] as Dictionary).duplicate()
		c["load"] = {}
		_place_car(c)
		_dirty = true
		# the tub rocks over and back
		var tub: Node3D = (c["node"] as Node3D).get_node("Tub")
		var tw := create_tween()
		tw.tween_property(tub, "rotation:z", -0.9, 0.5)
		tw.tween_property(tub, "rotation:z", 0.0, 0.7)
		var m2: String = prospect._dump(at, ld) if prospect != null and prospect.has_method("_dump") else "Tipped."
		_say(m2 if m2 != "" else "Tipped.")
		return true
	return false


const CAR_PRICE := 1400

## The shop: an ore car delivered and set on the track nearest p.
func buy_car(p: Vector3, jobs: Node) -> String:
	var best := -1
	var bs := 0.0
	var bd := 12.0
	for i in range(segs.size()):
		for e in [[segs[i][0], 0.8], [segs[i][1], -0.8]]:
			var q: Vector3 = e[0]
			var d := q.distance_to(p)
			if d < bd:
				bd = d
				best = i
				bs = float(e[1]) if float(e[1]) > 0.0 else (segs[i][0] as Vector3).distance_to(segs[i][1]) - 0.8
	if best < 0:
		return "Lay some track first (track sections are stacked in the tool yard), then the car goes on it."
	if not Game.sandbox and jobs != null:
		if jobs.money < CAR_PRICE:
			return "An ore car costs $%d." % CAR_PRICE
		jobs.money -= CAR_PRICE
	add_car(best, bs)
	return "The ore car's on your track. Shovel at the face near it to fill it, walk into an end to push it, E beside it to tip it."


func _say(t: String) -> void:
	if hud != null:
		hud.push_message(t, 4.0)


# ==============================================================================
#  Saving
# ==============================================================================
func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("r", "segs", segs)
	var cs: Array = []
	for c in cars:
		cs.append([int(c["seg"]), float(c["s"]), c["load"]])
	cf.set_value("r", "cars", cs)
	cf.save(SAVE)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	segs = cf.get_value("r", "segs", [])
	for i in range(segs.size()):
		_build_seg(i)
	for e in cf.get_value("r", "cars", []):
		add_car(int(e[0]), float(e[1]), e[2])
