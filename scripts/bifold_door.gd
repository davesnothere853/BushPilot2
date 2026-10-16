extends Node3D
## A bifold lift-strap hangar door (DESIGN_NOTES 78): two leaves hinged at
## the header and at the middle knuckle. Opening, the straps lift the bottom
## edge up the jambs, the knuckle swings out, and the leaves fold up into a
## canopy over the opening (Schweiss style). Closed, the leaves hang flat in
## the doorway and the hangar is shut - walls for walkers, planes and trucks.
## Lives in the hangar's local frame (door on -Z).

const MeshKit = preload("res://scripts/meshkit.gd")

var door_w := 20.0
var door_h := 5.6
var hz := 9.0
var open := 1.0                    # 0 shut .. 1 open
var target := 1.0
var hollow: Dictionary = {}        # the terrain hollow whose door width follows this
const SPEED := 0.09                # of the travel a second (about 11 s end to end)

var _top: Node3D
var _bot: Node3D
var _straps: Array = []            # [node, x]
var _hinge := Vector3.ZERO
var _leaf := 2.8


func build(skin: Color, trim: Color) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # animated per frame
	_leaf = door_h * 0.5
	_hinge = Vector3(0, door_h + 0.1, -hz - 0.15)
	var steel := Color(0.40, 0.42, 0.44)
	_top = _make_leaf(skin, trim, steel, 1.0)
	_bot = _make_leaf(skin, trim, steel, -1.0)
	for i in range(6):
		var x := -door_w * 0.5 + 0.6 + float(i) * (door_w - 1.2) / 5.0
		var k := MeshKit.new()
		k.box_at(Vector3(0, -0.5, 0), Vector3(0.08, 1.0, 0.012), Color(0.95, 0.80, 0.10))
		var n := k.instance("Strap")
		add_child(n)
		_straps.append([n, x])
	_pose()


## One leaf: hinge along its top edge at the local origin, hanging down -Y,
## outside skin on -Z (`face` flips which side shows the skin when folded).
func _make_leaf(skin: Color, trim: Color, steel: Color, face: float) -> Node3D:
	var k := MeshKit.new()
	var w := door_w + 0.3
	k.box_at(Vector3(0, -_leaf * 0.5, 0), Vector3(w, _leaf, 0.2), steel)
	k.box_at(Vector3(0, -_leaf * 0.5, -0.11), Vector3(w, _leaf, 0.03), skin)
	var nr := int(w / 0.3)
	for i in range(nr + 1):
		var x := -w * 0.5 + float(i) * w / float(nr)
		k.box_at(Vector3(x, -_leaf * 0.5, -0.135), Vector3(0.035, _leaf, 0.025), skin.darkened(0.1))
	for e in [-1.0, 1.0]:
		k.box_at(Vector3(e * w * 0.5, -_leaf * 0.5, -0.13), Vector3(0.12, _leaf, 0.04), trim)
	k.box_at(Vector3(0, -_leaf + 0.06, -0.13), Vector3(w, 0.12, 0.04), trim)
	for t in range(5):
		var tx := -door_w * 0.5 + float(t) * door_w / 4.0
		k.box_at(Vector3(tx, -_leaf * 0.5, 0.13), Vector3(0.1, _leaf - 0.1, 0.06), steel.darkened(0.2))
	k.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-w * 0.5, 0, 0)), 0.08, 0.08, w, 8, steel.darkened(0.3))
	var n := k.instance("Leaf")
	add_child(n)
	return n


func _process(delta: float) -> void:
	if absf(open - target) < 0.0005:
		return
	open = move_toward(open, target, SPEED * delta)
	_pose()


## Place the leaves for `open`, and open or shut the walls to match.
func _pose() -> void:
	var a := deg_to_rad(80.0) * open                     # top leaf, out from hanging straight down
	var knuckle := _hinge + Vector3(0, -cos(a), -sin(a)) * _leaf
	# the bottom edge rides on the straps up the face of the jambs
	var dz := knuckle.z - _hinge.z
	var by := knuckle.y - sqrt(maxf(_leaf * _leaf - dz * dz, 0.0))
	var bottom := Vector3(0, by, _hinge.z)
	_top.transform = Transform3D(Basis(Vector3.RIGHT, a), _hinge)
	var d := bottom - knuckle
	var b_ang := atan2(-d.z, -d.y)                      # the bottom leaf hangs from the knuckle toward `bottom`
	_bot.transform = Transform3D(Basis(Vector3.RIGHT, b_ang), knuckle)
	for s in _straps:
		var n: Node3D = s[0]
		var x: float = s[1]
		var top := Vector3(x, door_h + 0.75, -hz - 0.3)
		var bot := bottom + Vector3(x, 0, -0.12)
		var v := bot - top
		var l := v.length()
		var y := -v.normalized()
		var xa := Vector3.RIGHT
		var z := xa.cross(y).normalized()
		n.transform = Transform3D(Basis(xa, y * l, z), top)
	if not hollow.is_empty():
		# walls: shut until the door is nearly all the way up
		hollow["door"] = door_w if open > 0.97 else 0.0


func toggle() -> String:
	target = 0.0 if target > 0.5 else 1.0
	return "Hangar door %s." % ("opening" if target > 0.5 else "closing")


func state_text() -> String:
	if absf(open - target) > 0.001:
		return "opening" if target > open else "closing"
	return "open" if open > 0.5 else "shut"
