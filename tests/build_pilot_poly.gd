extends SceneTree
# Builds res://assets/characters/pilot.scn from the POLYART pilot
# (assets/characters/src_poly/Ch17_polyart.fbx, made by tools/polyart_pilot.py
# in Blender) plus every animation, in one AnimationPlayer.
#   godot --headless --path . -s tests/build_pilot_poly.gd

const SRC := "res://assets/characters/src/"
const POLY := "res://assets/characters/src_poly/Ch17_polyart.fbx"
const ANIMS := {
	"idle": true, "walking": true, "running": true, "jump": false,
	"falling": true, "sitting_idle": true, "sit_down": false, "stand_up": false,
	"driving": true, "switch_low": false, "switch_high": false, "get_in": false,
}

func _initialize():
	_go.call_deferred()

func _load(path: String) -> Node:
	var doc := FBXDocument.new()
	var st := FBXState.new()
	if doc.append_from_file(path, st) != OK:
		push_error("could not read " + path)
		return null
	return doc.generate_scene(st)

func _dump(n: Node, depth: int) -> void:
	if depth > 3:
		return
	print("  ".repeat(depth), n.name, " <", n.get_class(), ">")
	for c in n.get_children():
		_dump(c, depth + 1)

func _go():
	await process_frame
	var root: Node3D = _load(POLY)
	_dump(root, 0)
	var skel: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	print("skeleton at ", root.get_path_to(skel), " bones ", skel.get_bone_count(), " e.g. ", skel.get_bone_name(0), " / head ", skel.find_bone("mixamorig1_Head"))
	# Flat polyart colours straight from the vertex colours.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	for mi in skel.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for si in range(m.get_surface_count()):
			m.surface_set_material(si, mat)
	# The animations from the original rig files (same bone names).
	var player: AnimationPlayer = root.get_node_or_null("AnimationPlayer")
	if player == null:
		player = AnimationPlayer.new()
		player.name = "AnimationPlayer"
		root.add_child(player)
	for lib_name in player.get_animation_library_list():
		player.remove_animation_library(lib_name)
	var lib := AnimationLibrary.new()
	for nm in ANIMS.keys():
		var a_root: Node = _load(SRC + nm + ".fbx")
		var ap: AnimationPlayer = a_root.get_node("AnimationPlayer")
		var anim: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
		anim.loop_mode = Animation.LOOP_LINEAR if ANIMS[nm] else Animation.LOOP_NONE
		# Point the tracks at wherever the skeleton sits in this scene.
		var skel_path := String(root.get_path_to(skel))
		for t in range(anim.get_track_count()):
			var tp := String(anim.track_get_path(t))
			var colon := tp.find(":")
			if colon > 0:
				anim.track_set_path(t, NodePath(skel_path + tp.substr(colon)))
		lib.add_animation(nm, anim)
		if nm == "idle":
			print("idle track 0 -> ", anim.track_get_path(0))
		a_root.free()
	player.add_animation_library("", lib)
	# The game expects the skeleton directly under the root, named Skeleton3D.
	if skel.get_parent() != root:
		skel.get_parent().remove_child(skel)
		root.add_child(skel)
		skel.name = "Skeleton3D"
		for t_lib in player.get_animation_library_list():
			var L: AnimationLibrary = player.get_animation_library(t_lib)
			for an in L.get_animation_list():
				var A: Animation = L.get_animation(an)
				for t in range(A.get_track_count()):
					var tp2 := String(A.track_get_path(t))
					A.track_set_path(t, NodePath("Skeleton3D" + tp2.substr(tp2.find(":"))))
	for n in root.find_children("*", "", true, false):
		n.owner = root
	var ps := PackedScene.new()
	print("pack ", ps.pack(root))
	print("save ", ResourceSaver.save(ps, "res://assets/characters/pilot.scn"))
	var aabb := AABB()
	var first := true
	for c in skel.find_children("*", "MeshInstance3D", true, false):
		var b := (c as MeshInstance3D).get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	print("mesh bounds ", aabb, " skeleton scale ", skel.scale, " root scale ", root.scale)
	quit()
