extends SceneTree
# builds a lab model headless and reports errors (no rendering): args: script [variant]
func _init():
	await process_frame
	var a := OS.get_cmdline_user_args()
	var Lab = load("res://tools/model_lab.gd")
	var v = load(a[0]).new()
	if a.size() > 1 and a[1] != "" and v.get("variant") != null:
		v.variant = a[1]
	if "terrain" in v:
		v.terrain = Lab.FlatGround.new()
	root.add_child(v)
	if v.has_method("build"):
		v.build()
	if v.has_method("park"):
		v.park(Transform3D.IDENTITY)
	print("BUILT ", a[0], " meshes: ", v.find_children("*", "MeshInstance3D", true, false).size())
	quit()
