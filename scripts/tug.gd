extends Node3D
## A small aircraft tow tractor (DESIGN_NOTES 130, 149): an off-white
## airport tug with a tow bar that clips to a tailwheel and a pintle hook
## for trailers. Drive it up so the hitch at its back is by a plane's tail -
## yours, one of your fleet, one for sale - E hooks the bar on, and the plane
## follows like a trailer: its main wheels roll, its tail goes where the bar
## takes it. Pull it out of the hangar tail first; back up to push it in
## nose first. Back the hook up to any trailer's tongue (log trailer, sluice,
## wash plant) and E hitches that instead. E again lets go. Lives by the home
## hangar.

const MeshKit = preload("res://scripts/meshkit.gd")
const EK = preload("res://scripts/equip_kit.gd")
const YELLOW := Color(0.93, 0.70, 0.10)
const BODY := Color(0.86, 0.84, 0.78)        # off-white
const STRIPE_Y := Color(0.95, 0.76, 0.10)
const HUB := Color(0.72, 0.72, 0.70)
const TyreMesh = preload("res://scripts/tyre_mesh.gd")
const WHEEL_R := 0.27           # 6.00-9 industrial tyres
const FRONT_Z := -0.82
const REAR_Z := 0.82
const BLACK := Color(0.08, 0.08, 0.08)
const STEEL := Color(0.45, 0.46, 0.48)
const MAX_SPEED := 3.6          # m/s, about 13 km/h
const TOW_SPEED := 2.2          # with a plane on the bar
const WHEELBASE := 1.64
const HITCH := Vector3(0, 0.46, 1.56)     # the pintle hook at the back
const BAR := 2.0                # tow bar, pin to tailwheel axle
const SAVE := "user://tug.cfg"

var terrain: RefCounted
var plane: Node3D               # the player's plane (kept clear of when not towing it)
var planes: Callable            # func() -> Array of every plane on the field (yours, the fleet's, for sale)
var towables: Callable          # func() -> Array of trailers (towable.gd)
var trailer: Node3D = null      # a trailer on the pintle hook
var tow_plane: Node3D = null    # the plane on the bar
var yaw := 0.0
var speed := 0.0
var steer := 0.0
var driven := false
var towing := false
var mud_now := 0.0
var spin_now := 0.0
var home := Transform3D.IDENTITY
var _wheels: Array = []         # [node, steers]
var _roll := 0.0
var _bar: Node3D
var _b0 := Basis.IDENTITY       # the plane's attitude when hooked on (yaw taken out)
var _yaw0 := 0.0
var _dy := 0.0                  # its node origin's height over the ground under the main wheels
var _save_t := 0.0


func display_name() -> String:
	return "tug"


func build() -> void:
	# Proportions of a real small tow tractor: ~2.9 m long, 1.4 m wide, the
	# hood about 1.05 m high, the steering wheel ~1.25 m; 6.00-9 tyres on a
	# 1.64 m wheelbase; a low open deck, the seat over the rear axle, a heavy
	# ballast body at the back with the pintle hook, a light bar with a
	# beacon. Off-white with black-and-yellow hazard stripes.
	var k := MeshKit.new()
	var hw := 0.62
	# chassis: a heavy steel frame the length of it, bumpers each end
	k.box_at(Vector3(0, 0.36, 0.0), Vector3(1.0, 0.28, 2.8), BLACK)
	k.box_at(Vector3(0, 0.36, -1.47), Vector3(1.3, 0.24, 0.1), BLACK)          # front bumper
	k.box_at(Vector3(0, 0.36, 1.47), Vector3(1.3, 0.24, 0.1), BLACK)           # rear bumper
	# the hood over the engine: chamfered, its face raked back
	var rings: Array = []
	rings.append(_section(hw, 0.5, 1.02, 0.08, -1.42, 0.12))
	rings.append(_section(hw, 0.5, 1.06, 0.08, -0.32, 0.0))
	k.loft(rings, BODY, true, true)
	# grille in the face, headlamps, a dark rubber strip along the bottom
	var face := func(x: float, y: float) -> Vector3: return Vector3(x, y, -1.42 + (y - 0.5) / 0.52 * 0.12 - 0.008)
	for gy in range(5):
		k.box_at(face.call(0.0, 0.66 + 0.055 * float(gy)), Vector3(0.62, 0.025, 0.02), Color(0.18, 0.18, 0.18))
	var lm := MeshKit.new()
	for hx in [-0.44, 0.44]:
		var hp: Vector3 = face.call(hx, 0.82)
		EK.lamp(k, lm, self, hp + Vector3(0, 0, -0.005), Vector3(0, 0, -1), 0.13, 0.13, Color(1, 0.97, 0.86), true)
		EK.lamp(k, lm, self, face.call(hx, 0.66) + Vector3(0, 0, -0.005), Vector3(0, 0, -1), 0.1, 0.05, Color(1.0, 0.6, 0.1))   # indicators
	_stripes(k, Vector3(0, 0.36, -1.525), Vector3(1.0, 0, 0), 1.26)
	_stripes(k, Vector3(0, 0.36, 1.525), Vector3(1.0, 0, 0), 1.26)
	# side louvres in the hood, the filler cap
	for sx in [-1.0, 1.0]:
		k.box_at(Vector3(sx * (hw + 0.002), 0.82, -0.8), Vector3(0.012, 0.22, 0.6), BLACK)
		for i in range(5):
			k.box_at(Vector3(sx * (hw + 0.008), 0.74 + 0.04 * float(i), -0.8), Vector3(0.006, 0.01, 0.56), Color(0.25, 0.25, 0.25))
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(-0.42, 1.04, -0.5)), 0.05, 0.05, 0.04, 10, BLACK)
	# the open deck: a ribbed floor plate between the hood and the seat
	k.box_at(Vector3(0, 0.52, 0.02), Vector3(1.2, 0.04, 0.68), Color(0.32, 0.32, 0.33))
	for rz in range(6):
		k.box_at(Vector3(0, 0.545, -0.25 + 0.1 * float(rz)), Vector3(1.1, 0.01, 0.02), Color(0.42, 0.42, 0.44))
	# dash on the back of the hood, the column and wheel, the pedals
	k.box_at(Vector3(0, 0.95, -0.27), Vector3(1.0, 0.22, 0.1), Color(0.2, 0.2, 0.21))
	k.box_at(Vector3(-0.25, 0.97, -0.215), Vector3(0.22, 0.12, 0.01), Color(0.05, 0.07, 0.06))
	var ca := Vector3(0, 0.92, -0.24)
	var cb := Vector3(0, 1.2, -0.02)
	_slab(k, ca, cb, Vector2(0.06, 0.06), Color(0.2, 0.2, 0.2))
	var ax := (cb - ca).normalized()
	var rx := Vector3.RIGHT
	k.cylinder(Transform3D(Basis(rx, ax, rx.cross(ax)), cb), 0.19, 0.19, 0.03, 18, BLACK, true)
	for px in [-0.15, 0.12, 0.28]:
		k.box(Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(px, 0.6, -0.2)), Vector3(0.1, 0.03, 0.16), Color(0.25, 0.25, 0.25))
	# the rear body: ballast and batteries, the seat on top over the axle
	var rb: Array = [_section(hw, 0.5, 0.92, 0.06, 0.36, 0.0), _section(hw, 0.5, 0.92, 0.06, 1.45, 0.0)]
	k.loft(rb, BODY.darkened(0.03), true, true)
	k.box_at(Vector3(0, 0.98, 0.62), Vector3(0.62, 0.12, 0.55), Color(0.25, 0.25, 0.26))     # seat base
	EK.seat(k, Vector3(0, 1.1, 0.62), 0.0)
	# rear fenders over the back wheels, the light bar and beacon behind the seat
	for sx3 in [-1.0, 1.0]:
		k.box_at(Vector3(sx3 * 0.66, 0.62, REAR_Z), Vector3(0.24, 0.04, 0.7), BODY.darkened(0.1))
		k.box_at(Vector3(sx3 * 0.66, 0.62, FRONT_Z), Vector3(0.24, 0.04, 0.68), BODY.darkened(0.1))
		_slab(k, Vector3(sx3 * 0.45, 0.92, 1.25), Vector3(sx3 * 0.45, 1.85, 1.25), Vector2(0.05, 0.05), Color(0.3, 0.3, 0.3))
		EK.lamp(k, lm, self, Vector3(sx3 * 0.45, 0.82, 1.455), Vector3(0, 0, 1), 0.11, 0.11, Color(0.85, 0.08, 0.05), true)   # tail lamps
		EK.lamp(k, lm, self, Vector3(sx3 * 0.27, 0.82, 1.455), Vector3(0, 0, 1), 0.08, 0.08, Color(1.0, 0.6, 0.1), true)
		EK.bolts(lm, Vector3(sx3 * (hw + 0.005), 0.56, -1.3), Vector3(sx3 * (hw + 0.005), 0.56, -0.4), 6, Vector3(sx3, 0, 0), 0.012)
		EK.decal(self, "TUG 2", Vector3(sx3 * (hw + 0.006), 0.98, -0.45), Vector3(sx3, 0, 0), 0.0016, Color(0.1, 0.1, 0.1))
		_stripes(k, Vector3(sx3 * (hw + 0.004), 0.62, 0.95), Vector3(0, 0, 1.0), 0.9)
		k.box_at(Vector3(sx3 * 0.7, 0.42, 0.0), Vector3(0.1, 0.04, 0.4), Color(0.3, 0.3, 0.3))   # step
	k.box_at(Vector3(0, 1.85, 1.25), Vector3(0.95, 0.05, 0.05), Color(0.3, 0.3, 0.3))
	EK.beacon(k, self, Vector3(0, 1.88, 1.25))
	EK.decal(self, "NO RIDERS", Vector3(0, 1.0, 1.456), Vector3(0, 0, 1), 0.0012, Color(0.05, 0.05, 0.05), Color(0.95, 0.75, 0.1), k, 0.2, 0.06)
	# the pintle hook and its plate
	k.box_at(Vector3(0, HITCH.y, 1.5), Vector3(0.24, 0.2, 0.08), STEEL)
	k.box_at(Vector3(0, HITCH.y - 0.02, HITCH.z - 0.01), Vector3(0.1, 0.06, 0.14), STEEL)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, HITCH.y - 0.06, HITCH.z)), 0.03, 0.03, 0.16, 8, STEEL)
	add_child(k.instance("Tug"))
	var lmi := lm.instance("TugMetal")
	lmi.material_override = EK.metal_mat()
	add_child(lmi)
	# four wheels: industrial tyres on grey disc wheels (tyre_mesh.gd)
	for w in [[Vector3(-0.6, WHEEL_R, FRONT_Z), true], [Vector3(0.6, WHEEL_R, FRONT_Z), true], [Vector3(-0.6, WHEEL_R, REAR_Z), false], [Vector3(0.6, WHEEL_R, REAR_Z), false]]:
		var wn := Node3D.new()
		wn.position = w[0]
		var wmi := MeshInstance3D.new()
		wmi.mesh = TyreMesh.wheel(WHEEL_R, 0.17, 0.12, "lug", "disc", signf((w[0] as Vector3).x), [0.0], "", HUB)
		wmi.material_override = MeshKit.material()
		wn.add_child(wmi)
		add_child(wn)
		_wheels.append([wn, w[1]])
	EK.dust_all(self, 0.4, 0.55)
	EK.add_collision(self)
	# the tow bar: a long tube on a pair of little wheels near the tractor
	# end, a lunette eye on the pin, a fork that clamps the tailwheel
	_bar = Node3D.new()
	_bar.top_level = true
	_bar.visible = false
	add_child(_bar)
	var tube := MeshInstance3D.new()
	tube.name = "Tube"
	var tk := MeshKit.new()
	tk.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.04, 0.04, 1.0, 8, YELLOW.darkened(0.15))   # along +Z, 0..1
	tube.mesh = tk.commit()
	tube.material_override = MeshKit.material()
	_bar.add_child(tube)
	var ek := MeshKit.new()
	ek.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.03, 0)), 0.08, 0.08, 0.05, 10, STEEL, true)      # lunette eye on the pin
	for sx5 in [-0.22, 0.22]:
		ek.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx5 + 0.04 * signf(sx5), -0.25, 0.45)), 0.13, 0.13, 0.08, 10, BLACK)
	ek.box_at(Vector3(0, -0.13, 0.45), Vector3(0.48, 0.04, 0.06), STEEL)
	ek.box_at(Vector3(0, -0.07, 0.45), Vector3(0.05, 0.12, 0.05), STEEL)
	var eye := MeshInstance3D.new()
	eye.mesh = ek.commit()
	eye.material_override = MeshKit.material()
	_bar.add_child(eye)
	var fk := MeshKit.new()
	for sx6 in [-0.12, 0.12]:
		fk.box_at(Vector3(sx6, -0.05, -0.08), Vector3(0.03, 0.16, 0.22), STEEL)
	fk.box_at(Vector3(0, 0.02, -0.18), Vector3(0.27, 0.04, 0.05), STEEL)
	var fork := MeshInstance3D.new()
	fork.name = "Fork"
	fork.mesh = fk.commit()
	fork.material_override = MeshKit.material()
	_bar.add_child(fork)


## Lay the bar from the pin `h` to the tailwheel `t`.
func _lay_bar(h: Vector3, t: Vector3) -> void:
	var d := t - h
	var l := d.length()
	if l < 0.05:
		return
	var z := d / l
	var x := Vector3.UP.cross(z).normalized() if absf(z.y) < 0.95 else Vector3.RIGHT
	var y := z.cross(x)
	_bar.global_transform = Transform3D(Basis(x, y, z), h)
	(_bar.get_node("Tube") as Node3D).transform = Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1, l)), Vector3.ZERO)
	(_bar.get_node("Fork") as Node3D).position = Vector3(0, 0, l)


## A chamfered box section at station z: half-width w, bottom y0, top y1,
## corners cut by c; `rake` leans the section's top back (toward +Z).
static func _section(w: float, y0: float, y1: float, c: float, z: float, rake: float) -> PackedVector3Array:
	var pts := [Vector2(-w + c, y1), Vector2(w - c, y1), Vector2(w, y1 - c), Vector2(w, y0 + c),
		Vector2(w - c, y0), Vector2(-w + c, y0), Vector2(-w, y0 + c), Vector2(-w, y1 - c)]
	var out := PackedVector3Array()
	for p2 in pts:
		var q: Vector2 = p2
		out.append(Vector3(q.x, q.y, z + rake * (q.y - y0) / (y1 - y0)))
	return out


## A bar of section `sec` (x across, y thick) from a to b.
static func _slab(k, a: Vector3, b: Vector3, sec: Vector2, col: Color) -> void:
	var d := b - a
	var y := d.normalized()
	var x := Vector3.RIGHT
	var z := x.cross(y).normalized()
	k.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(sec.x, d.length(), sec.y), col)


## A band of black and yellow hazard stripes centred at c, running along `along`.
static func _stripes(k, c: Vector3, along: Vector3, length: float) -> void:
	var n := int(length / 0.1)
	var side := along.cross(Vector3.UP).normalized()
	for i in range(n):
		var p := c + along * (-length * 0.5 + (float(i) + 0.5) * length / float(n))
		var col := STRIPE_Y if i % 2 == 0 else BLACK
		var b := Basis(along, Vector3.UP, along.cross(Vector3.UP)).orthonormalized()
		k.box(Transform3D(b * Basis(Vector3.BACK, 0.6), p), Vector3(0.05, 0.12, 0.012), col)


func park(xf: Transform3D) -> void:
	home = xf
	var f := -xf.basis.z
	yaw = atan2(-f.x, -f.z)
	global_position = xf.origin
	speed = 0.0
	_settle()


func _settle() -> void:
	var p := global_position
	p.y = terrain.ground_level_at(p.x, p.z)
	var n: Vector3 = terrain.ground_normal_at(p.x, p.z)
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var right := fwd.cross(n).normalized()
	global_transform = Transform3D(Basis(right, n, -fwd), p)


func eye_xf() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.87, 0.6))


func step_out_point() -> Vector3:
	return global_transform * Vector3(-1.1, 0, 0.6)


func hitch_point() -> Vector3:
	return global_transform * HITCH


# ------------------------------------------------------------------------------
#  The plane on the bar
# ------------------------------------------------------------------------------
func _plane_pts(pl: Node3D = null) -> Array:
	# main wheels' middle and the tailwheel, in the plane's node frame
	if pl == null:
		pl = tow_plane
	var wp: Array = pl.wheel_pos
	return [((wp[0] as Vector3) + (wp[1] as Vector3)) * 0.5, wp[2] as Vector3]


## Where the bar would clip on (the tailwheel), in the world.
func tail_point(pl: Node3D = null) -> Vector3:
	if pl == null:
		pl = tow_plane
	return pl.global_transform * (_plane_pts(pl)[1] as Vector3)


## Every plane standing on the field.
func _all_planes() -> Array:
	var out: Array = planes.call() if planes.is_valid() else []
	if plane != null and not out.has(plane):
		out.append(plane)
	return out


## The plane whose tailwheel is nearest the hitch, and how far.
func _nearest_plane() -> Array:
	var best: Node3D = null
	var bd := 1.0e9
	var h := hitch_point()
	for pl in _all_planes():
		if pl == null or not is_instance_valid(pl) or pl.get("wheel_pos") == null:
			continue
		var tp: Vector3 = tail_point(pl)
		var d := Vector2(tp.x - h.x, tp.z - h.z).length()
		if d < bd:
			bd = d
			best = pl
	return [best, bd]


func can_hook(pl: Node3D = null) -> String:
	if pl == null:
		var np := _nearest_plane()
		pl = np[0]
	if pl == null or not bool(pl.on_ground) or bool(pl.is_crashed):
		return "No plane to hook on to."
	if float(pl.ground_speed) > 0.5:
		return "Wait for the plane to stop."
	var d := Vector2(tail_point(pl).x - hitch_point().x, tail_point(pl).z - hitch_point().z).length()
	if d > BAR + 1.0:
		return "Back the hitch up to a plane's tailwheel (%.1f m away) or a trailer's tongue." % d
	return ""


## The nearest trailer tongue the hook could take, or null.
func tongue_near(r: float = 2.5) -> Node3D:
	if not towables.is_valid():
		return null
	var h := hitch_point()
	var best: Node3D = null
	var bd := r
	for t in towables.call():
		if t == null or not is_instance_valid(t) or t.towed_by != null:
			continue
		var tp: Vector3 = t.tongue_point()
		var d := Vector2(tp.x - h.x, tp.z - h.z).length()
		if d < bd and absf(tp.y - h.y) < 1.2:
			bd = d
			best = t
	return best


func prompt() -> String:
	if trailer != null:
		return "%s  Unhitch the %s" % [Game.hint("interact"), trailer.display_name()]
	if towing:
		return "%s  Take the tow bar off" % Game.hint("interact")
	var tn := tongue_near()
	if tn != null:
		return "%s  Hitch the %s" % [Game.hint("interact"), tn.display_name()]
	var np := _nearest_plane()
	if np[0] != null and float(np[1]) < BAR + 1.0:
		return "%s  Hook the tow bar on the tailwheel" % Game.hint("interact")
	return ""


func tow_toggle() -> String:
	if trailer != null:
		if absf(speed) > 0.3:
			return "Stop before you unhitch."
		var t := trailer
		trailer = null
		t.towed_by = null
		t.settle()
		if t.has_method("set_folded"):
			t.set_folded(false)
		return "Unhitched the %s." % t.display_name()
	if towing:
		if absf(speed) > 0.3:
			return "Stop before you unhook."
		towing = false
		_bar.visible = false
		tow_plane.frozen = false
		tow_plane.place_parked(tow_plane.global_position, tow_plane.global_transform.basis.get_rotation_quaternion())
		tow_plane = null
		return "Tow bar off. The plane's on its brakes."
	var tn := tongue_near()
	if tn != null:
		if absf(speed) > 0.3:
			return "Stop to hitch up."
		trailer = tn
		tn.towed_by = self
		if tn.has_method("set_folded"):
			tn.set_folded(true)
		tn.follow(hitch_point())
		var tm: float = float(tn.total_mass()) if tn.has_method("total_mass") else float(tn.mass)
		return "Hitched the %s on the pintle hook: %d kg behind you." % [tn.display_name(), int(tm)]
	var np := _nearest_plane()
	var pl: Node3D = np[0]
	var why := can_hook(pl)
	if why != "":
		return why
	for e in pl.engines():
		if bool(e.running):
			return "Shut the engine%s down before you hook on." % ("s" if pl.engines().size() > 1 else "")
	tow_plane = pl
	towing = true
	pl.frozen = true
	var xf: Transform3D = pl.global_transform
	_yaw0 = _yaw_of(xf.basis)
	_b0 = Basis(Vector3.UP, -_yaw0) * xf.basis
	var m := xf * (_plane_pts()[0] as Vector3)
	_dy = xf.origin.y - float(terrain.ground_level_at(m.x, m.z))
	_bar.visible = true
	_follow()
	return "Tow bar on the tailwheel. Drive: the plane follows tail first; back up to push it. E unhooks."


static func _yaw_of(b: Basis) -> float:
	var f := -b.z
	return atan2(-f.x, -f.z)


## The plane follows the pin like a trailer: its main wheels are the axle,
## its tailwheel the tongue, the bar the drawbar.
func _follow() -> void:
	var pts := _plane_pts()
	var ml: Vector3 = pts[0]
	var tl: Vector3 = pts[1]
	var xf: Transform3D = tow_plane.global_transform
	var m := xf * ml
	var h := hitch_point()
	var to_h := Vector2(h.x - m.x, h.z - m.z)
	if to_h.length() < 0.05:
		return
	var dir := to_h.normalized()
	# main wheels to tailwheel along the ground, plus the bar
	var tail_flat: Vector3 = _b0 * (tl - ml)
	var reach := Vector2(tail_flat.x, tail_flat.z).length() + BAR
	var m2 := Vector2(h.x, h.z) - dir * reach
	# turn so the tail points at the pin
	var want := atan2(-dir.x, -dir.y)
	var have := atan2(-tail_flat.x, -tail_flat.z)
	var yw := want - have
	var b := Basis(Vector3.UP, yw) * _b0
	var gy: float = terrain.ground_level_at(m2.x, m2.y)
	var origin := Vector3(m2.x, 0.0, m2.y) - b * ml
	origin.y = gy + _dy
	tow_plane.place_parked(origin, b.get_rotation_quaternion())
	tow_plane.frozen = true
	# lay the bar from the pin to the tailwheel
	_lay_bar(h, tow_plane.global_transform * tl)


## One step: move.y forward (+) / back, move.x steer right (+).
func drive(delta: float, move: Vector2, _lift_in: float = 0.0) -> void:
	var top := TOW_SPEED if (towing or trailer != null) else MAX_SPEED
	var want := move.y * top * (0.6 if move.y < 0.0 else 1.0)
	var gp := global_position
	mud_now = float(terrain.mud_at(gp.x, gp.z)) if terrain.has_method("mud_at") else 0.0
	want *= lerpf(1.0, 0.1, smoothstep(0.15, 0.8, mud_now))
	speed = move_toward(speed, want, (1.8 if absf(want) > absf(speed) else 3.5) * delta)
	steer = move_toward(steer, move.x, 2.2 * delta)
	yaw -= speed * tan(steer * 0.6) / WHEELBASE * delta
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var p := global_position + fwd * speed * delta
	if terrain.blocked_by_building(p + fwd * (1.4 if speed >= 0.0 else -1.4) + Vector3(0, 0.5, 0), 0.6):
		speed = 0.0
		p = global_position
	# don't drive into the plane you're not towing
	for pl in _all_planes():
		if pl != tow_plane and _in_plane(pl, p + fwd * signf(speed) * 1.5):
			speed = 0.0
			p = global_position
			break
	global_position = p
	_roll += speed * delta
	_settle()
	for w in _wheels:
		var wn: Node3D = w[0]
		wn.rotation = Vector3(_roll / WHEEL_R, (-steer * 0.6) if bool(w[1]) else 0.0, 0)
	if towing:
		_follow()
	if trailer != null:
		trailer.follow(hitch_point())


func _in_plane(pl: Node3D, p: Vector3) -> bool:
	if pl == null or not is_instance_valid(pl):
		return false
	var l: Vector3 = pl.global_transform.affine_inverse() * p
	var span := 8.0 if String(pl.plane_type) == "dc3" else 5.6
	# the fuselage (above the tailwheel the tail's high enough to roll under)
	return absf(l.x) < 1.2 and l.z > -span * 0.6 and l.z < 3.5 and l.y < 2.0


func _process(delta: float) -> void:
	if towing and not driven:
		_follow()
	if trailer != null and not driven:
		trailer.follow(hitch_point())
	_save_t += delta
	if _save_t > 5.0:
		_save_t = 0.0
		save()


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("t", "xf", global_transform)
	cf.save(SAVE)


func load_or_park(default: Transform3D) -> void:
	var cf := ConfigFile.new()
	var xf := default
	if cf.load(SAVE) == OK:
		var x = cf.get_value("t", "xf", default)
		if x is Transform3D:
			xf = x
	park(xf)
	home = default
