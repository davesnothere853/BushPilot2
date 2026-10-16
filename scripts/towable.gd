extends Node3D
## Anything with a tongue that a hitch can pull (DESIGN_NOTES 79): the sluice
## and wash plant on their wheels now, flatbeds, dump trailers and a lowboy
## later. Local frame: origin on the ground under the middle of the axle.
## Following a hitch is kinematic, like a real single-axle trailer: the axle
## is dragged along behind the hitch at a fixed tongue length, so it cuts
## corners (off-tracking), and the body pitches to keep the tongue on the
## ball and rolls with the ground under its wheels.

var kind := ""                  # "sluice", "washplant", ...
var idx := -1                   # index in its owner's list
var tongue_local := Vector3(0, 0.55, -2.0)
var axle_local := Vector3(0, 0.3, 0)     # axle centre (y = wheel radius)
var track := 1.6                # wheel to wheel
var wheel_r := 0.3
var mass := 500.0               # kg
var towed_by: Node3D = null
var on_moved: Callable          # func(node) - the owner updates its record
var ground: Callable            # func(x, z) -> float
var wheels: Array = []          # Node3D per wheel (spun when moving)
var _spin := 0.0
var axles := 1                  # 2: tandem, `axle_gap` apart either side of axle_local.z
var axle_gap := 1.0
# Folding for the road (DESIGN_NOTES 83): parts that swing up and in when
# hitched and back out when you set up: [node, working xf, folded xf].
var fold_parts: Array = []
var folded := false
var _fold := 0.0                # 0 working .. 1 folded
const FOLD_SPEED := 0.35        # of the travel a second


func display_name() -> String:
	match kind:
		"sluice":
			return "sluice trailer"
		"washplant":
			return "wash plant"
	return kind


func tongue_point() -> Vector3:
	return global_transform * tongue_local


## Put the trailer behind `hitch` (world point on the tow ball).
func follow(hitch: Vector3) -> void:
	var xf := global_transform
	var a := xf * Vector3(axle_local.x, 0, axle_local.z)
	var dl := Vector2(tongue_local.x - axle_local.x, tongue_local.z - axle_local.z)
	var tl := dl.length()
	var to_h := Vector2(hitch.x - a.x, hitch.z - a.z)
	if to_h.length() < 0.01:
		return
	var dir := to_h.normalized()
	var a2 := Vector2(hitch.x, hitch.z) - dir * tl
	var moved := Vector2(a2.x - a.x, a2.y - a.z).length()
	# yaw that turns the local axle->tongue direction onto `dir`
	var yaw := atan2(-dir.x, -dir.y) - atan2(-dl.x, -dl.y)
	var gy: float = ground.call(a2.x, a2.y)
	var b := Basis(Vector3.UP, yaw)
	# roll from the two wheels, pitch to lift the tongue to the ball
	var side := b * Vector3(track * 0.5, 0, 0)
	var hl: float = ground.call(a2.x - side.x, a2.y - side.z)
	var hr: float = ground.call(a2.x + side.x, a2.y + side.z)
	var roll := atan2(hl - hr, track)
	var pitch := atan2(hitch.y - (gy + tongue_local.y), tl)
	b = b * Basis(Vector3.RIGHT, pitch * signf(-dl.y if absf(dl.y) > 0.01 else 1.0)) * Basis(Vector3.FORWARD, roll)
	var origin := Vector3(a2.x, gy, a2.y) - b * Vector3(axle_local.x, 0, axle_local.z)
	global_transform = Transform3D(b, origin)
	_spin += moved / maxf(wheel_r, 0.05) * (1.0 if to_h.dot(Vector2(-sin(yaw), -cos(yaw))) >= 0.0 else -1.0)
	for w in wheels:
		(w as Node3D).rotation.x = -_spin
	if on_moved.is_valid():
		on_moved.call(self)


## Unhitched: let the tongue down onto its jack, level on the ground.
func settle() -> void:
	var xf := global_transform
	var f := xf.basis.z
	var yaw := atan2(f.x, f.z)
	var a := xf * Vector3(axle_local.x, 0, axle_local.z)
	var gy: float = ground.call(a.x, a.z)
	var b := Basis(Vector3.UP, yaw)
	global_transform = Transform3D(b, Vector3(a.x, gy, a.z) - b * Vector3(axle_local.x, 0, axle_local.z))
	if on_moved.is_valid():
		on_moved.call(self)


## Wheels, a tongue (A-frame), a jack and a hitch coupler, added to `kit`
## in local space. Wheel meshes are separate nodes so they turn.
func add_running_gear(kit, frame_c: Color, draw_tongue: bool = true) -> void:
	var dark := Color(0.10, 0.10, 0.11)
	var steel := Color(0.45, 0.46, 0.48)
	var ay := axle_local.y
	kit.box_at(Vector3(axle_local.x, ay, axle_local.z), Vector3(track - 0.1, 0.08, 0.08), dark)
	# A-frame from the frame corners to the coupler
	for s in ([-1.0, 1.0] if draw_tongue else []):
		var a := Vector3(s * minf(track * 0.4, 0.9), ay + 0.1, axle_local.z + signf(tongue_local.z - axle_local.z) * 0.6)
		var b := tongue_local + Vector3(0, -0.02, 0)
		_beam(kit, a, b, Vector2(0.08, 0.1), frame_c)
	kit.box_at(tongue_local, Vector3(0.14, 0.1, 0.22), steel)                      # coupler
	kit.box_at(tongue_local + Vector3(0.18, -tongue_local.y * 0.5, 0.25 * signf(axle_local.z - tongue_local.z)), Vector3(0.06, tongue_local.y, 0.06), steel)   # jack
	kit.box_at(tongue_local + Vector3(0.18, -tongue_local.y + 0.02, 0.25 * signf(axle_local.z - tongue_local.z)), Vector3(0.18, 0.04, 0.18), steel)
	var zs: Array = [axle_local.z] if axles < 2 else [axle_local.z - axle_gap * 0.5, axle_local.z + axle_gap * 0.5]
	if axles >= 2:
		kit.box_at(Vector3(axle_local.x, ay, zs[0]), Vector3(track - 0.1, 0.08, 0.08), dark)
		kit.box_at(Vector3(axle_local.x, ay, zs[1]), Vector3(track - 0.1, 0.08, 0.08), dark)
	for wz in zs:
		for s2 in [-1.0, 1.0]:
			_wheel(kit, Vector3(axle_local.x + s2 * track * 0.5, wheel_r, float(wz)), s2, frame_c)


func _wheel(kit, at: Vector3, s2: float, frame_c: Color) -> void:
	var dark := Color(0.10, 0.10, 0.11)
	var steel := Color(0.45, 0.46, 0.48)
	if true:
		var wn := Node3D.new()
		wn.position = at
		var wmi := MeshInstance3D.new()
		wmi.mesh = load("res://scripts/tyre_mesh.gd").wheel(wheel_r, maxf(wheel_r * 0.62, 0.16), wheel_r * 0.56, "highway", "slot", s2, [0.0], "", Color(0.78, 0.78, 0.75))
		wmi.material_override = load("res://scripts/meshkit.gd").material()
		wn.add_child(wmi)
		add_child(wn)
		wheels.append(wn)
		# fender
		kit.box_at(Vector3(at.x, wheel_r * 2.0 + 0.06, at.z), Vector3(0.3, 0.04, wheel_r * 2.4), frame_c)


static func _beam(kit, a: Vector3, b: Vector3, sec: Vector2, col: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var y := d / l
	var x := Vector3.UP.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	kit.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(sec.x, l, sec.y), col)



## Hitched up: fold for the road. Set down: unfold and go to work.
func set_folded(f: bool) -> void:
	folded = f


## Folded all the way out and set up (not moving, not half folded).
func working() -> bool:
	return towed_by == null and _fold <= 0.001


func _process(delta: float) -> void:
	var goal := 1.0 if folded else 0.0
	if absf(_fold - goal) < 0.0001 or fold_parts.is_empty():
		return
	_fold = move_toward(_fold, goal, FOLD_SPEED * delta)
	_pose_folds()


func _pose_folds() -> void:
	var t := smoothstep(0.0, 1.0, _fold)
	for fp in fold_parts:
		var n: Node3D = fp[0]
		n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # folds per frame
		var a: Transform3D = fp[1]
		var b: Transform3D = fp[2]
		n.transform = a.interpolate_with(b, t)
