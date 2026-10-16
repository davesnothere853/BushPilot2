extends RefCounted
## A long-handled round-point shovel, polyart: ash handle, steel D-grip,
## pressed-steel blade with a step. Built with the grip (where the right hand
## holds it) at the origin, handle along +Z, blade at the far end.

const MeshKit = preload("res://scripts/meshkit.gd")
const ASH := Color(0.62, 0.47, 0.30)
const STEEL := Color(0.36, 0.37, 0.39)
const BLADE := Color(0.27, 0.28, 0.30)
const WORN := Color(0.55, 0.55, 0.56)


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Shovel"
	var k := MeshKit.new()
	var along := Basis(Vector3.RIGHT, PI * 0.5)     # cylinder axis Y -> +Z
	# handle: from behind the hand to the blade socket
	# (a 1.05 m round-point shovel with a D-grip: Dave found the first one too long)
	k.cylinder(Transform3D(along, Vector3(0, 0, -0.32)), 0.015, 0.017, 0.52, 6, ASH)
	# D-grip on the back end
	k.cylinder(Transform3D(along, Vector3(0, 0, -0.42)), 0.012, 0.016, 0.10, 5, STEEL)
	k.box_at(Vector3(0, 0, -0.50), Vector3(0.12, 0.025, 0.025), ASH)
	for sx in [-0.055, 0.055]:
		k.box(Transform3D(Basis(Vector3.UP, 0.35 * sign(sx)), Vector3(sx, 0, -0.455)), Vector3(0.02, 0.022, 0.10), STEEL)
	# socket (ferrule) and the blade
	k.cylinder(Transform3D(along, Vector3(0, 0, 0.18)), 0.019, 0.023, 0.14, 6, STEEL)
	var z0 := 0.31
	var w := 0.095
	var dish := 0.025
	var pts := [Vector3(-w, 0, z0), Vector3(w, 0, z0), Vector3(w * 0.95, -dish, z0 + 0.13), Vector3(w * 0.55, -dish, z0 + 0.20),
		Vector3(0, -dish * 0.6, z0 + 0.24), Vector3(-w * 0.55, -dish, z0 + 0.20), Vector3(-w * 0.95, -dish, z0 + 0.13)]
	var c := Vector3(0, -dish, z0 + 0.10)
	for i in range(pts.size()):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		k.tri(c, a, b, BLADE if i > 0 else STEEL, Vector3(0, 1, 0))
		k.tri(c + Vector3(0, -0.006, 0), b + Vector3(0, -0.006, 0), a + Vector3(0, -0.006, 0), WORN, Vector3(0, -1, 0))
	# the step the boot goes on
	k.box_at(Vector3(0, 0.008, z0 + 0.01), Vector3(w * 2.1, 0.012, 0.03), STEEL)
	root.add_child(k.instance("ShovelMesh"))
	return root
