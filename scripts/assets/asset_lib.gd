extends RefCounted
## Assets built once, copied everywhere (DESIGN_NOTES 228, Dave: render the
## asset first, don't make it over and over). get("lookout_tower") builds
## scripts/assets/lookout_tower.gd's make() the first time and keeps it; each
## call hands back a copy sharing the same meshes and materials.

static var _proto := {}


## "name" or "name:variant" (a building type and which of its variants).
static func get_asset(name: String) -> Node3D:
	if not _proto.has(name):
		var base := name.get_slice(":", 0)
		var sc = load("res://scripts/assets/%s.gd" % base)
		if sc == null:
			_proto[name] = Node3D.new()
		elif name.contains(":"):
			_proto[name] = sc.make_variant(int(name.get_slice(":", 1)))
		else:
			_proto[name] = sc.make()
	var n: Node3D = (_proto[name] as Node3D).duplicate()
	n.name = name
	return n


static func forget() -> void:
	for v in _proto.values():
		(v as Node).free()
	_proto.clear()
