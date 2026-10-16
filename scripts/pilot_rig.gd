extends Node3D
## The pilot, using the motion-captured rigged character (assets/characters/
## pilot.scn, built by tests/build_pilot.gd) dressed for the bush: leather
## jacket, ball cap, wool scarf and aviators. Same interface as pilot_model.gd
## (build, animate, eye_local, head_part), so the game can use either.
## Faces -Z, feet at the origin.

const PilotModel = preload("res://scripts/pilot_model.gd")
const MeshKit = preload("res://scripts/meshkit.gd")
const SCENE := "res://assets/characters/pilot.scn"

const CAP := Color(0.24, 0.27, 0.22)
const CAP_PATCH := Color(0.78, 0.74, 0.64)
const SCARF := Color(0.83, 0.79, 0.69)
const LENS := Color(0.16, 0.22, 0.20, 0.0)
const FRAME := Color(0.74, 0.60, 0.30, 0.1)

var skeleton: Skeleton3D
var head_part: Node3D          # hair, cap and glasses: hidden in first person
var model: Node3D
var mode := PilotModel.IDLE
var aim := false               # pistol up: the aiming idle / walk
var _player: AnimationPlayer
var _clip := ""
var _head := -1
var _gesture := ""
var seat_clip := ""            # a machine's own seated pose ("cub_seat": legs out to the pedals)


static func available() -> bool:
	return ResourceLoader.exists(SCENE)


func _ready() -> void:
	if skeleton == null:
		build()


func build() -> void:
	if skeleton != null:
		return
	model = (load(SCENE) as PackedScene).instantiate()
	model.rotation.y = PI          # these characters face +Z
	add_child(model)
	skeleton = model.get_node("Skeleton3D")
	_player = model.get_node("AnimationPlayer")
	_head = skeleton.find_bone("mixamorig1_Head")
	head_part = Node3D.new()
	head_part.name = "HeadPart"
	add_child(head_part)
	var mat := ShaderMaterial.new()
	mat.shader = PilotModel._shader()
	# Hair and eyelashes go with the head (hidden in first person).
	for c in skeleton.get_children():
		if c is MeshInstance3D and (c.name.ends_with("Hair") or c.name.ends_with("Eyelashes")):
			c.set_meta("head", true)
	# Worn as the rig came, plus a pair of aviators.
	_attach("mixamorig1_Head", _glasses(), mat)
	_add_tool_clips()
	animate(0.0, PilotModel.IDLE, 0.0, 0.0)


## Put a mesh built in the character's own space onto a bone, so it moves with it.
func _attach(bone: String, mesh: ArrayMesh, mat: Material) -> MeshInstance3D:
	var bi := skeleton.find_bone(bone)
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = skeleton.get_bone_global_rest(bi).affine_inverse()
	ba.add_child(mi)
	if bone == "mixamorig1_Head":
		mi.set_meta("head", true)
	return mi


## Ear muffs (hearing protection round the diesel, the pump, the plane):
## on or off his head.
var _muffs: MeshInstance3D
func ear_muffs(on: bool) -> void:
	if _muffs == null and on:
		var mat := ShaderMaterial.new()
		mat.shader = PilotModel._shader()
		_muffs = _attach("mixamorig1_Head", _muffs_mesh(), mat)
	if _muffs != null:
		_muffs.visible = on


## Built on his head in the character's own space (face +Z): a cup over each
## ear (yellow shell, black cushion against the hair at x 0.107), the band up
## over the crown (top of the hair 1.764), a fork from the band to each cup.
static func _muffs_mesh() -> ArrayMesh:
	var kit := MeshKit.new()
	var shell := Color(0.92, 0.74, 0.08, 0.0)
	var cush := Color(0.06, 0.06, 0.06, 0.0)
	var band := Color(0.10, 0.10, 0.11, 0.05)
	var cy := 1.632
	var cz := -0.008
	var hw := 0.031          # half width (front-back)
	var hh := 0.042          # half height
	for sx in [1.0, -1.0]:
		# cushion ring then the cup, as rings of an oval swept outward
		var rings: Array = []
		var prof := [[0.104, 0.86, cush], [0.110, 1.0, cush], [0.118, 1.0, cush], [0.120, 1.04, shell], [0.140, 1.0, shell], [0.146, 0.80, shell], [0.148, 0.45, shell]]
		for pr in prof:
			var ring := PackedVector3Array()
			for k in range(20):
				var a := TAU * float(k) / 20.0
				ring.append(Vector3(float(pr[0]) * sx, cy + sin(a) * hh * float(pr[1]), cz + cos(a) * hw * float(pr[1])))
			rings.append(ring)
		for ri in range(rings.size() - 1):
			var ra: PackedVector3Array = rings[ri]
			var rb: PackedVector3Array = rings[ri + 1]
			var col: Color = prof[ri + 1][2]
			for k in range(20):
				var k2 := (k + 1) % 20
				var mid := (ra[k] + rb[k2]) * 0.5
				var out := (mid - Vector3(float(prof[ri][0]) * sx * 0.5, cy, cz))
				kit.quad(ra[k], ra[k2], rb[k2], rb[k], col, out)
		# outer cap and the inner face (on the hair)
		var last: PackedVector3Array = rings[rings.size() - 1]
		var first: PackedVector3Array = rings[0]
		for k in range(20):
			var k2 := (k + 1) % 20
			kit.tri(Vector3(0.149 * sx, cy, cz), last[k], last[k2], shell, Vector3(sx, 0, 0))
			kit.tri(Vector3(0.104 * sx, cy, cz), first[k], first[k2], cush, Vector3(-sx, 0, 0))
		# the fork: a yoke over the top of the cup to its pivots front and back
		for fz in [-1.0, 1.0]:
			_bar(kit, Vector3(0.150 * sx, cy + hh * 0.9, cz), Vector3(0.143 * sx, cy, cz + fz * (hw + 0.004)), 0.0035, band)
		_bar(kit, Vector3(0.150 * sx, cy + hh * 0.9, cz), Vector3(0.147 * sx, cy + hh + 0.022, cz), 0.004, band)
	# the band: over the crown, clear of the hair
	var pts: Array = []
	for i in range(17):
		var a := PI * float(i) / 16.0
		pts.append(Vector3(cos(a) * 0.147, cy + hh + 0.022 + sin(a) * (1.778 - (cy + hh + 0.022)), cz))
	for i in range(pts.size() - 1):
		var a0: Vector3 = pts[i]
		var a1: Vector3 = pts[i + 1]
		var w := Vector3(0, 0, 0.012)
		var n0 := Vector3(a0.x / 0.147, (a0.y - cy) * 0.5, 0).normalized()
		var n1 := Vector3(a1.x / 0.147, (a1.y - cy) * 0.5, 0).normalized()
		var th := 0.003
		kit.quad(a0 - w + n0 * th, a1 - w + n1 * th, a1 + w + n1 * th, a0 + w + n0 * th, band, n0 + n1)      # outside
		kit.quad(a0 - w - n0 * th, a1 - w - n1 * th, a1 + w - n1 * th, a0 + w - n0 * th, band, -(n0 + n1))   # inside
		kit.quad(a0 + w + n0 * th, a1 + w + n1 * th, a1 + w - n1 * th, a0 + w - n0 * th, band, Vector3(0, 0, 1))
		kit.quad(a0 - w + n0 * th, a1 - w + n1 * th, a1 - w - n1 * th, a0 - w - n0 * th, band, Vector3(0, 0, -1))
	kit.smooth(40.0)
	return kit.commit()


## Put a tool in the right hand. The tool is built grip-at-origin, handle
## along +Z (see shovel.gd); null takes it out of the hand.
var _held: Node3D
var _held_ba: BoneAttachment3D
var _anchors := {}             # bone name -> BoneAttachment3D
var _grip_wait := 0            # frames until a carried thing's grip is worked out


## Items carry a "carry" meta (inventory.gd): {"anchor": "hand" | "chest" |
## "head", "xf": Transform3D} in the rig's own frame (forward -Z, right +X,
## up +Y). For the hand, xf's basis is how the thing hangs and its origin an
## offset from where the hand is; for the chest and head, where it sits.
## Worked out against the pose he's actually in (arm hanging), once the
## animation has run a frame, then it rides on that bone.
func hold_tool(tool: Node3D) -> void:
	if _held != null and is_instance_valid(_held) and _held.get_parent() != null and _held.get_parent() is BoneAttachment3D:
		_held.get_parent().remove_child(_held)
	_held = tool
	_head_on = -1           # re-run set_head_visible with the new tool
	if tool == null:
		return
	if tool.has_meta("carry"):
		var c: Dictionary = tool.get_meta("carry")
		var bone: String = {"hand": B + "RightHand", "chest": B + "Spine2", "head": B + "Head", "hip": B + "Hips"}.get(String(c.get("anchor", "hand")), B + "RightHand")
		var ba: BoneAttachment3D = _anchors.get(bone)
		if ba == null:
			ba = BoneAttachment3D.new()
			ba.bone_name = bone
			skeleton.add_child(ba)
			_anchors[bone] = ba
		if tool.get_parent() != null:
			tool.get_parent().remove_child(tool)
		ba.add_child(tool)
		tool.visible = false
		_grip_wait = 2
		return
	if _held_ba == null:
		_held_ba = BoneAttachment3D.new()
		_held_ba.bone_name = "mixamorig1_RightHand"
		skeleton.add_child(_held_ba)
	var bi := skeleton.find_bone("mixamorig1_RightHand")
	var rest := skeleton.get_bone_global_rest(bi)
	# in the palm, a little along the fingers; handle pointing forward and down
	var palm := rest.origin + rest.basis.orthonormalized() * Vector3(0, 0.085, 0.025)
	var place := Transform3D(Basis(Vector3.RIGHT, 0.45), palm)
	if tool.get_parent() != null:
		tool.get_parent().remove_child(tool)
	_held_ba.add_child(tool)
	tool.transform = rest.affine_inverse() * place
	tool.set_meta("grip", tool.transform)


## On the phone: the handset in his right hand and the talking pose (the
## motion-captured "phone_talk" when it's been downloaded, otherwise our own
## "phone_hold"); off puts the handset down and lets the gait take over.
var _handset: Node3D
func phone(on: bool) -> void:
	if on:
		if _handset == null or not is_instance_valid(_handset):
			_handset = handset_mesh()
		hold_tool(_handset)
		_handset.transform = _handset.transform * PHONE_GRIP
		var nm := "phone_talk" if _player.has_animation("phone_talk") else "phone_hold"
		_working = nm
		_player.play(nm, 0.3)
		_clip = nm
	else:
		hold_tool(null)
		if _handset != null and is_instance_valid(_handset):
			_handset.queue_free()
		_handset = null
		_working = ""
		animate(0.0, PilotModel.IDLE, 0.0, 0.0)


## How the handset sits in the palm (from the default grip): turned so the
## ear cup is at the ear and the mouth cup by the chin.
const PHONE_GRIP := Transform3D(Basis(Vector3.BACK, PI) * Basis(Vector3.BACK, -1.4), Vector3.ZERO)


## The payphone's handset at its real size (0.215 m): a curved black grip,
## the ear cup at +Y, the mouth cup at -Y, both facing -Z (toward the face).
static func handset_mesh() -> Node3D:
	var MK = load("res://scripts/meshkit.gd")
	var k = MK.new()
	var blk := Color(0.07, 0.07, 0.075)
	var pts := [Vector3(0, 0.09, 0.012), Vector3(0, 0.045, 0.02), Vector3(0, 0.0, 0.022), Vector3(0, -0.045, 0.02), Vector3(0, -0.09, 0.012)]
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var d := c - a
		var y := d.normalized()
		var x := y.cross(Vector3.FORWARD).normalized()
		k.cylinder(Transform3D(Basis(x, y, x.cross(y)), a), 0.0135, 0.0135, d.length(), 8, blk, true)
	for cup in [[0.095, 0.028], [-0.095, 0.025]]:
		k.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, float(cup[0]), 0.015)), float(cup[1]) * 0.75, float(cup[1]), 0.03, 14, blk, true)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.13, 0.012)), 0.01, 0.013, 0.03, 8, Color(0.15, 0.35, 0.7), true)    # cord guard
	var mi: MeshInstance3D = k.instance("Handset")
	var n := Node3D.new()
	n.name = "Handset"
	n.add_child(mi)
	return n


func set_first_person(on: bool) -> void:
	set_head_visible(not on)


var _head_on := -1
var _head_at := 0.0
func set_head_visible(on: bool) -> void:
	# (DESIGN_NOTES 186) called every physics tick by the walker and the seated
	# driver; the tree walk below only runs when the state changes, or twice a
	# second to catch meshes added since (hats, gore pieces).
	var now := Time.get_ticks_msec() * 0.001
	if int(on) == _head_on and now - _head_at < 0.5:
		return
	_head_on = int(on)
	_head_at = now
	# In first person the whole body is drawn only into the shadows: the face
	# and torso are one skinned mesh, so hiding just the hat and hair left the
	# camera looking at the inside of the head and collar. A tool in his hand
	# still shows.
	for n in skeleton.find_children("*", "MeshInstance3D", true, false):
		if _held_ba != null and _held_ba.is_ancestor_of(n):
			continue
		# a tool on a "carry" anchor rides the hand bone's own attachment, not
		# _held_ba: keep it drawn in first person too (it was going shadow-only)
		if _held != null and is_instance_valid(_held) and (_held == n or _held.is_ancestor_of(n)):
			continue
		var on_head: Node = _anchors.get(B + "Head")
		if on_head != null and on_head.is_ancestor_of(n):
			(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			continue
		var on_chest: Node = _anchors.get(B + "Spine2")
		if on_chest != null and on_chest.is_ancestor_of(n):
			continue
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


# ------------------------------------------------------------------------------
#  Accessories, in the character's space (facing +Z, metres)
# ------------------------------------------------------------------------------
static func _ring(c: Vector3, rx: float, rz: float, n: int, sq: float = 0.0) -> PackedVector3Array:
	var r := PackedVector3Array()
	for k in range(n):
		var a := TAU * float(k) / float(n)
		var ca := cos(a)
		var sa := sin(a)
		if sq > 0.0:
			var e := 1.0 / (1.0 + sq * 1.5)
			ca = signf(ca) * pow(absf(ca), e)
			sa = signf(sa) * pow(absf(sa), e)
		r.append(c + Vector3(ca * rx, 0, sa * rz))
	return r


## A full head of hair over the scalp: a close shell following the skull,
## higher over the forehead, down to the nape behind, a little ragged at the
## edge, in the beard's dark brown.
const HAIR := Color(0.21, 0.17, 0.12, 0.3)


func _glasses() -> ArrayMesh:
	var kit := MeshKit.new()
	# Aviators: teardrop lenses on the face, a gold bridge and arms to the ears.
	for sx in [1.0, -1.0]:
		var lc := Vector3(0.034 * sx, 1.649, 0.122)
		var outline := PackedVector3Array()
		for k in range(14):
			var a3 := TAU * float(k) / 14.0
			var x := cos(a3) * 0.027
			var y2 := sin(a3) * 0.019
			if sin(a3) < 0.0:
				y2 *= 1.0 + 0.45 * maxf(0.0, cos(a3) * sx + 0.2)
			outline.append(lc + Vector3(x, y2, -0.006 * absf(x) / 0.027))
		for k in range(14):
			var k2 := (k + 1) % 14
			kit.tri(lc, outline[k], outline[k2], LENS, Vector3(0, 0, 1))
			kit.tri(lc - Vector3(0, 0, 0.002), outline[k2] - Vector3(0, 0, 0.002), outline[k] - Vector3(0, 0, 0.002), LENS, Vector3(0, 0, -1))
		var temple_a := lc + Vector3(0.027 * sx, 0.006, -0.006)
		var temple_b := Vector3(0.095 * sx, 1.656, 0.045)
		var temple_c := Vector3(0.098 * sx, 1.650, -0.030)
		for seg in [[temple_a, temple_b], [temple_b, temple_c]]:
			_bar(kit, seg[0], seg[1], 0.0025, FRAME)
	_bar(kit, Vector3(-0.009, 1.661, 0.127), Vector3(0.009, 1.661, 0.127), 0.002, FRAME)
	_bar(kit, Vector3(-0.058, 1.668, 0.123), Vector3(0.058, 1.668, 0.123), 0.0018, FRAME)
	kit.smooth(50.0)
	return kit.commit()


static func _bar(kit: RefCounted, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	kit.cylinder(Transform3D(Basis(x, y, z), a), r, r, d.length(), 5, col, true)


# ------------------------------------------------------------------------------
#  Animation
# ------------------------------------------------------------------------------
## Play the motion for this gait, blending from the last one.
func animate(_delta: float, new_mode: int, speed: float, _t: float) -> void:
	mode = new_mode
	if _working != "" and (new_mode == PilotModel.IDLE or new_mode == PilotModel.WALK):
		return              # mid-shovelful: finish it
	var clip := "idle"
	var rate := 1.0
	if aim and (mode == PilotModel.IDLE or mode == PilotModel.WALK or mode == PilotModel.RUN) and _player.has_animation("pistol_aim"):
		clip = "pistol_aim"
		if mode != PilotModel.IDLE and _player.has_animation("pistol_walk"):
			clip = "pistol_walk"
			rate = clampf(speed / 1.45, 0.6, 1.4)
		if clip != _clip:
			_player.play(clip, 0.2)
			_clip = clip
		_player.speed_scale = rate
		return
	match mode:
		PilotModel.WALK:
			clip = "walking"
			rate = clampf(speed / 1.45, 0.6, 1.6)
		PilotModel.RUN:
			clip = "running"
			rate = clampf(speed / 4.2, 0.7, 1.4)
		PilotModel.AIR:
			clip = "falling"
		PilotModel.SIT, PilotModel.DRIVE:
			# seated: in the plane and at the wheel of every machine (DRIVE used
			# to fall through to "idle" - the driver stood up through the floor)
			clip = "driving" if _player.has_animation("driving") else "sitting_idle"
			if seat_clip != "" and _player.has_animation(seat_clip):
				clip = seat_clip
			if _gesture != "":
				return          # a switch reach is playing; it hands back by itself
	if clip != _clip:
		_player.play(clip, 0.25 if (_clip != "" and _delta > 0.0) else 0.0)
		_clip = clip
		if _delta <= 0.0:
			_player.advance(0.0)
	_player.speed_scale = rate


# ------------------------------------------------------------------------------
#  Tool work (DESIGN_NOTES 120): a shovelful and a pick swing, made from key
#  poses. Each bone's turn is given in the character's own frame (it faces
#  +Z, up is +Y, its right hand is out at -X in the T-pose rest): a list of
#  [axis, degrees] applied in order to the bone's rest. A bone not listed
#  keeps its parent's turn. "hips_y" drops the hips (knees bend with it).
# ------------------------------------------------------------------------------
const B := "mixamorig1_"
const CHAIN := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightUpLeg", "RightLeg", "LeftUpLeg", "LeftLeg", "RightFoot", "LeftFoot"]
const X := Vector3.RIGHT
const Y := Vector3.UP
const Z := Vector3.BACK

## On the phone (until the motion-captured "phone_talk" is downloaded): the
## right hand up at the ear holding the handset, the left arm down, a little
## nod now and then. Loops, 3 s.
const PHONE_ARM := [[Vector3(0, 0.834, 0.552), 84.3]]
const PHONE_FORE := [[Vector3(0, -0.56, -0.829), 111.7]]
const PHONE_KEYS := [
	[0.0, {"RightArm": PHONE_ARM, "RightForeArm": PHONE_FORE, "LeftArm": [[Z, -78]], "LeftForeArm": [[Z, -72]], "Neck": [[Z, 5]]}],
	[1.5, {"RightArm": PHONE_ARM, "RightForeArm": PHONE_FORE, "LeftArm": [[Z, -76], [Y, -6]], "LeftForeArm": [[Z, -70], [Y, -10]], "Neck": [[Z, 5], [X, 6]]}],
	[3.0, {"RightArm": PHONE_ARM, "RightForeArm": PHONE_FORE, "LeftArm": [[Z, -78]], "LeftForeArm": [[Z, -72]], "Neck": [[Z, 5]]}],
]

## A shovelful: drive the blade in, lever and lift, swing it off to the
## right and dump, back to the start. 1.6 s.
const DIG_KEYS := [
	[0.0, {"Spine": [[X, 18]], "Neck": [[X, 8]],
		"RightArm": [[Y, 92], [X, 55]], "RightForeArm": [[Y, 115], [X, 55]],
		"LeftArm": [[Y, -100], [X, 35]], "LeftForeArm": [[Y, -140], [X, 20]],
		"hips_y": -0.04}],
	[0.45, {"Spine": [[X, 34]], "Neck": [[X, 4]],
		"RightArm": [[Y, 90], [X, 70]], "RightForeArm": [[Y, 110], [X, 72]],
		"LeftArm": [[Y, -98], [X, 50]], "LeftForeArm": [[Y, -135], [X, 40]],
		"hips_y": -0.13}],
	[0.9, {"Spine": [[X, 14]], "Neck": [[X, 10]],
		"RightArm": [[Y, 95], [X, 35]], "RightForeArm": [[Y, 120], [X, 25]],
		"LeftArm": [[Y, -100], [X, 15]], "LeftForeArm": [[Y, -140], [X, 0]],
		"hips_y": -0.06}],
	[1.2, {"Spine": [[X, 16], [Y, -30]], "Neck": [[X, 8], [Y, -20]],
		"RightArm": [[Y, 60], [X, 28]], "RightForeArm": [[Y, 80], [X, 20]],
		"LeftArm": [[Y, -125], [X, 18]], "LeftForeArm": [[Y, -155], [X, 8]],
		"hips_y": -0.05}],
	[1.6, {"Spine": [[X, 18]], "Neck": [[X, 8]],
		"RightArm": [[Y, 92], [X, 55]], "RightForeArm": [[Y, 115], [X, 55]],
		"LeftArm": [[Y, -100], [X, 35]], "LeftForeArm": [[Y, -140], [X, 20]],
		"hips_y": -0.04}],
]
## A pick swing: up over the right shoulder, a hard swing down in front,
## the recovery. 1.2 s.
const PICK_KEYS := [
	[0.0, {"Spine": [[X, -6]], "Neck": [[X, 4]],
		"RightArm": [[Y, 98], [X, -70]], "RightForeArm": [[Y, 104], [X, -100]],
		"LeftArm": [[Y, -112], [X, -66]], "LeftForeArm": [[Y, -118], [X, -96]],
		"hips_y": 0.0}],
	[0.4, {"Spine": [[X, -10]], "Neck": [[X, 2]],
		"RightArm": [[Y, 100], [X, -88]], "RightForeArm": [[Y, 106], [X, -120]],
		"LeftArm": [[Y, -114], [X, -84]], "LeftForeArm": [[Y, -120], [X, -116]],
		"hips_y": 0.0}],
	[0.62, {"Spine": [[X, 32]], "Neck": [[X, 6]],
		"RightArm": [[Y, 95], [X, 55]], "RightForeArm": [[Y, 110], [X, 60]],
		"LeftArm": [[Y, -100], [X, 50]], "LeftForeArm": [[Y, -115], [X, 55]],
		"hips_y": -0.12}],
	[0.8, {"Spine": [[X, 30]], "Neck": [[X, 6]],
		"RightArm": [[Y, 95], [X, 58]], "RightForeArm": [[Y, 110], [X, 62]],
		"LeftArm": [[Y, -100], [X, 53]], "LeftForeArm": [[Y, -115], [X, 58]],
		"hips_y": -0.12}],
	[1.2, {"Spine": [[X, -6]], "Neck": [[X, 4]],
		"RightArm": [[Y, 98], [X, -70]], "RightForeArm": [[Y, 104], [X, -100]],
		"LeftArm": [[Y, -112], [X, -66]], "LeftForeArm": [[Y, -118], [X, -96]],
		"hips_y": 0.0}],
]


## Lying where he fell (gore.gd, DESIGN_NOTES 157): arms flung out and
## down, legs a little apart, one knee bent, the head turned.
const SPRAWL_KEYS := [
	[0.0, {"Neck": [[Y, 35]], "Head": [[Y, 35], [X, 10]],
		"RightArm": [[Z, 30], [X, -10]], "RightForeArm": [[Z, 30], [Y, 25], [X, -10]],
		"LeftArm": [[Z, -55], [X, 15]], "LeftForeArm": [[Z, -55], [Y, -40], [X, 15]],
		"RightUpLeg": [[Z, -8]], "RightLeg": [[Z, -8]],
		"LeftUpLeg": [[Z, 12], [X, 30]], "LeftLeg": [[Z, 12], [X, -20]]}],
	[0.1, {"Neck": [[Y, 35]], "Head": [[Y, 35], [X, 10]],
		"RightArm": [[Z, 30], [X, -10]], "RightForeArm": [[Z, 30], [Y, 25], [X, -10]],
		"LeftArm": [[Z, -55], [X, 15]], "LeftForeArm": [[Z, -55], [Y, -40], [X, 15]],
		"RightUpLeg": [[Z, -8]], "RightLeg": [[Z, -8]],
		"LeftUpLeg": [[Z, 12], [X, 30]], "LeftLeg": [[Z, 12], [X, -20]]}],
]


## Sitting in a Cub (DESIGN_NOTES 211): low seat, legs straight out to the
## rudder pedals, right hand on the stick between the knees, left hand
## forward on the throttle on the left wall, leaning back a little. A gentle
## breathing sway so he isn't a statue.
const CUB_SEAT_KEYS := [
	[0.0, {"Spine": [[X, -10]], "Spine1": [[X, -6]], "Neck": [[X, 4]], "Head": [[X, 6]],
		"RightArm": [[Y, 100], [X, 20]], "RightForeArm": [[Y, 112], [X, 55]], "RightHand": [[Y, 112], [X, 40]],
		"LeftArm": [[Y, -92], [X, 20]], "LeftForeArm": [[Y, -88], [X, 30]], "LeftHand": [[Y, -88], [X, 30]],
		"RightUpLeg": [[X, -86], [Y, -6]], "RightLeg": [[X, -65]], "RightFoot": [[X, -35]],
		"LeftUpLeg": [[X, -86], [Y, 6]], "LeftLeg": [[X, -65]], "LeftFoot": [[X, -35]]}],
	[2.0, {"Spine": [[X, -9]], "Spine1": [[X, -5]], "Neck": [[X, 2], [Y, 6]], "Head": [[X, 4], [Y, 8]],
		"RightArm": [[Y, 100], [X, 20]], "RightForeArm": [[Y, 112], [X, 55]], "RightHand": [[Y, 112], [X, 39]],
		"LeftArm": [[Y, -92], [X, 20]], "LeftForeArm": [[Y, -88], [X, 30]], "LeftHand": [[Y, -88], [X, 29]],
		"RightUpLeg": [[X, -86], [Y, -6]], "RightLeg": [[X, -65]], "RightFoot": [[X, -35]],
		"LeftUpLeg": [[X, -86], [Y, 6]], "LeftLeg": [[X, -65]], "LeftFoot": [[X, -35]]}],
	[4.0, {"Spine": [[X, -10]], "Spine1": [[X, -6]], "Neck": [[X, 4]], "Head": [[X, 6]],
		"RightArm": [[Y, 100], [X, 20]], "RightForeArm": [[Y, 112], [X, 55]], "RightHand": [[Y, 112], [X, 40]],
		"LeftArm": [[Y, -92], [X, 20]], "LeftForeArm": [[Y, -88], [X, 30]], "LeftHand": [[Y, -88], [X, 30]],
		"RightUpLeg": [[X, -86], [Y, -6]], "RightLeg": [[X, -65]], "RightFoot": [[X, -35]],
		"LeftUpLeg": [[X, -86], [Y, 6]], "LeftLeg": [[X, -65]], "LeftFoot": [[X, -35]]}],
]


func _add_tool_clips() -> void:
	var lib: AnimationLibrary = _player.get_animation_library("")
	if lib == null:
		return
	for clip in [["dig", DIG_KEYS], ["pick", PICK_KEYS], ["sprawl", SPRAWL_KEYS], ["cub_seat", CUB_SEAT_KEYS], ["phone_hold", PHONE_KEYS]]:
		if not lib.has_animation(clip[0]):
			var an := _clip_from(clip[1])
			if clip[0] == "cub_seat" or clip[0] == "phone_hold":
				an.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation(clip[0], an)
	for nm in EXTRA.keys():
		if not lib.has_animation(nm):
			var a := _extra_clip(nm, lib)
			if a != null:
				lib.add_animation(nm, a)


# ------------------------------------------------------------------------------
#  Motion-captured clips (DESIGN_NOTES 181): downloaded for this same
#  character (same bone names), imported by the editor from
#  assets/characters/src/, retargeted onto our skeleton path once and shared.
# ------------------------------------------------------------------------------
const EXTRA := {
	"pistol_aim": true, "pistol_walk": true, "pistol_shoot": false, "throw": false,
	"swing": false, "hit_react": false, "pick_up": false, "shovel_dig": false,
}
static var _extra_cache := {}


func _extra_clip(nm: String, lib: AnimationLibrary) -> Animation:
	if _extra_cache.has(nm):
		return _extra_cache[nm]
	var path := "res://assets/characters/src/%s.fbx" % nm
	if not ResourceLoader.exists(path):
		_extra_cache[nm] = null
		return null
	var ps: PackedScene = load(path)
	var root: Node = ps.instantiate()
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	if ap == null or ap.get_animation_list().is_empty():
		root.free()
		_extra_cache[nm] = null
		return null
	var src: Animation = ap.get_animation(ap.get_animation_list()[0])
	var a: Animation = src.duplicate(true)
	root.free()
	a.loop_mode = Animation.LOOP_LINEAR if EXTRA[nm] else Animation.LOOP_NONE
	# the hips' height in our clips vs this one (an import can scale it)
	var ours := 1.0
	var idle: Animation = lib.get_animation("idle") if lib.has_animation("idle") else null
	if idle != null:
		for t in range(idle.get_track_count()):
			if idle.track_get_type(t) == Animation.TYPE_POSITION_3D and String(idle.track_get_path(t)).ends_with("Hips") and idle.track_get_key_count(t) > 0:
				ours = (idle.track_get_key_value(t, 0) as Vector3).y
	for t in range(a.get_track_count()):
		var tp := String(a.track_get_path(t))
		var colon := tp.find(":")
		if colon > 0:
			a.track_set_path(t, NodePath("Skeleton3D" + tp.substr(colon)))
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D and tp.ends_with("Hips") and a.track_get_key_count(t) > 0:
			var theirs: float = (a.track_get_key_value(t, 0) as Vector3).y
			if absf(theirs) > 0.0001 and absf(ours) > 0.0001:
				var k := ours / theirs
				if absf(k - 1.0) > 0.2:
					for i in range(a.track_get_key_count(t)):
						a.track_set_key_value(t, i, (a.track_get_key_value(t, i) as Vector3) * k)
	_extra_cache[nm] = a
	return a


## Play a one-off motion-captured clip (throw, swing, hit_react, ...),
## then back to the gait. Returns false if the clip isn't there.
func one_shot(nm: String, speed: float = 1.0) -> bool:
	if _player == null or not _player.has_animation(nm) or mode == PilotModel.SIT:
		return false
	_working = nm
	_player.play(nm, 0.12, speed)
	_clip = nm
	if not _player.animation_finished.is_connected(_on_work_done):
		_player.animation_finished.connect(_on_work_done)
	return true


## Key poses -> an animation of bone rotations (and the hips' height).
func _clip_from(keys: Array) -> Animation:
	var an := Animation.new()
	an.length = float(keys[keys.size() - 1][0])
	an.loop_mode = Animation.LOOP_NONE
	var tracks := {}
	for nm in CHAIN:
		var bi := skeleton.find_bone(B + nm)
		if bi < 0:
			continue
		var t := an.add_track(Animation.TYPE_ROTATION_3D)
		an.track_set_path(t, NodePath("Skeleton3D:" + B + nm))
		an.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
		tracks[nm] = t
	var hips := skeleton.find_bone(B + "Hips")
	var ht := an.add_track(Animation.TYPE_POSITION_3D)
	an.track_set_path(ht, NodePath("Skeleton3D:" + B + "Hips"))
	an.track_set_interpolation_type(ht, Animation.INTERPOLATION_CUBIC)
	var hips_rest: Vector3 = skeleton.get_bone_rest(hips).origin
	for k in keys:
		var tm: float = k[0]
		var pose: Dictionary = k[1]
		var turned := {}            # bone -> its turn in the character's frame
		var glob := {}              # bone -> its global basis in this pose
		for nm in CHAIN:
			var bi := skeleton.find_bone(B + nm)
			if bi < 0:
				continue
			var par := skeleton.get_bone_parent(bi)
			var pnm := skeleton.get_bone_name(par).trim_prefix(B) if par >= 0 else ""
			var r := Basis.IDENTITY
			if pose.has(nm):
				for step in pose[nm]:
					r = Basis((step[0] as Vector3).normalized(), deg_to_rad(float(step[1]))) * r
			elif turned.has(pnm):
				r = turned[pnm]
			# the legs bend with the hips going down: thighs forward, shins back
			if nm.ends_with("UpLeg") and pose.has("hips_y"):
				r = Basis(X, deg_to_rad(float(pose["hips_y"]) * 260.0))       # thigh forward (hips_y < 0)
			elif nm.ends_with("Leg") and not nm.ends_with("UpLeg") and pose.has("hips_y"):
				r = Basis(X, deg_to_rad(float(pose["hips_y"]) * -260.0))      # shin back
			turned[nm] = r
			var rest_g := skeleton.get_bone_global_rest(bi).basis.orthonormalized()
			var want := r * rest_g
			glob[nm] = want
			var parent_g: Basis = glob[pnm] if glob.has(pnm) else (skeleton.get_bone_global_rest(par).basis.orthonormalized() if par >= 0 else Basis.IDENTITY)
			var local := (parent_g.inverse() * want).orthonormalized()
			an.rotation_track_insert_key(tracks[nm], tm, local.get_rotation_quaternion())
		an.position_track_insert_key(ht, tm, hips_rest + Vector3(0, float(pose.get("hips_y", 0.0)), 0))
	return an


## Play one shovelful ("dig") or pick swing ("pick") on foot, then back to
## whatever he was doing.
var _working := ""
func work_motion(kind: String) -> void:
	if mode == PilotModel.SIT or not _player.has_animation(kind):
		return
	_working = kind
	_player.play(kind, 0.12)
	_clip = kind
	if not _player.animation_finished.is_connected(_on_work_done):
		_player.animation_finished.connect(_on_work_done)


func _on_work_done(nm: StringName) -> void:
	if String(nm) == _working:
		_working = ""
		_clip = ""
		if _held != null and is_instance_valid(_held) and _held.has_meta("grip"):
			_held.transform = _held.get_meta("grip")


## While digging or swinging, the tool lies the way it's really held: a
## shovel's shaft runs from the left hand through the right to the blade; a
## pick runs on out from the hands along the forearms, a little up.
func _fit_carry() -> void:
	var c: Dictionary = _held.get_meta("carry")
	var anchor := String(c.get("anchor", "hand"))
	var xf: Transform3D = c["xf"]
	var me := global_transform.orthonormalized()
	var want: Transform3D
	# Some things are fitted in the pose they're used in (the pistol: in the
	# aiming pose, so it points where he aims; down at his side otherwise).
	var fit_clip := String(c.get("fit", ""))
	if fit_clip == "" and anchor == "hand":
		fit_clip = "idle"          # always fitted in the same standing pose (not mid-blend)
	var back_clip := _player.current_animation
	var back_pos := _player.current_animation_position if back_clip != "" else 0.0
	var posed := fit_clip != "" and _player.has_animation(fit_clip)
	if posed:
		_player.play(fit_clip, 0.0)
		_player.seek(0.0, true)
	var ba := _held.get_parent() as BoneAttachment3D
	var bi := skeleton.find_bone(String(ba.bone_name)) if ba != null else skeleton.find_bone(B + "RightHand")
	var bone_xf: Transform3D = (skeleton.global_transform * skeleton.get_bone_global_pose(bi)).orthonormalized()
	if anchor == "hand":
		var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(B + "RightHand")).origin
		var palm := hand
		if fit_clip == "idle":
			# the middle of the grip: halfway down the palm to the knuckles, a
			# little in toward the curl of the fingers
			var mid := skeleton.find_bone(B + "RightHandMiddle1")
			if mid >= 0:
				var knuckle := skeleton.global_transform * skeleton.get_bone_global_pose(mid).origin
				palm = hand.lerp(knuckle, 0.6) + me.basis * Vector3(-0.02, 0.0, 0.0)
			else:
				palm = hand + me.basis * Vector3(0.0, -0.07, 0.0)
		want = Transform3D(me.basis * xf.basis, palm + me.basis * xf.origin)
	else:
		want = me * xf
	_held.transform = bone_xf.affine_inverse() * want
	if posed:
		if back_clip != "":
			_player.play(back_clip, 0.0)
			_player.seek(back_pos, true)
		else:
			_player.stop()
	_held.set_meta("grip", _held.transform)
	_held.visible = true


func _process(_delta: float) -> void:
	if _grip_wait > 0 and _held != null and is_instance_valid(_held) and _held.has_meta("carry") and skeleton != null:
		_grip_wait -= 1
		if _grip_wait == 0:
			_fit_carry()
	if not (_working == "dig" or _working == "pick") or _held == null or not is_instance_valid(_held) or skeleton == null:
		return
	var rh := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(B + "RightHand")).origin
	var lh := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(B + "LeftHand")).origin
	var dir := Vector3.ZERO
	if _working == "dig":
		# down the shaft from the left hand through the right, toward the
		# ground in front of him
		var fwd := -global_transform.basis.z
		dir = ((rh - lh).normalized() + (fwd * 0.55 - global_transform.basis.y * 0.85).normalized()).normalized()
	else:
		var el := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(B + "RightForeArm")).origin
		dir = ((rh - el).normalized() + global_transform.basis.y * 0.45).normalized()
	if dir.length() < 0.5:
		return
	var side := global_transform.basis.x
	var up := dir.cross(side).normalized()
	if up.length() < 0.5:
		up = Vector3.UP
	var bz := dir
	var by := up
	var bx := by.cross(bz).normalized()
	_held.global_transform = Transform3D(Basis(bx, bz.cross(bx), bz), rh)


func working() -> bool:
	return _working != ""


## A one-off reach while seated (flipping a panel switch), then back to flying.
func gesture(name: String) -> void:
	if mode != PilotModel.SIT or not _player.has_animation(name) or _gesture != "":
		return
	_gesture = name
	_player.play(name, 0.2)
	var back := _clip
	_player.animation_finished.connect(func(_n):
		_gesture = ""
		_clip = ""
		_player.play(back, 0.3)
		_clip = back, CONNECT_ONE_SHOT)


## Where the eyes are, in this node's space (for the first-person camera).
func eye_local() -> Vector3:
	var hp := skeleton.get_bone_global_pose(_head)
	var in_model := skeleton.transform * (hp * (Vector3(0.0, 1.637, 0.11) - skeleton.get_bone_global_rest(_head).origin))
	return model.transform * in_model
