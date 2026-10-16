extends Node3D
## A working hydraulic ram (Dave: "working simulated hydraulic cylinders"):
## the barrel pinned to one part, the rod's eye pinned to another; every frame
## the barrel swings to point at the rod end and the chrome rod slides in or out
## of it, so the ram really strokes as the boom, arm, blade or bucket moves.
## Put it under the machine's root; give it the two parts and the pin points in
## each part's own frame.

const MeshKit = preload("res://scripts/meshkit.gd")
const EK = preload("res://scripts/equip_kit.gd")

var a_node: Node3D                 # the part the barrel is pinned to
var a_local := Vector3.ZERO
var b_node: Node3D                 # the part the rod's eye is pinned to
var b_local := Vector3.ZERO
var radius := 0.07
var sim_ram = null                 # its Ram in the machine's hyd_system (for leaks)
var hoses: Array = []              # its two lines (plumb)
var pin_axis := Vector3.RIGHT      # the pins' direction in the parent's frame: the eyes line up with it (Dave: mounts properly oriented) - UP for a ram swinging flat (steering)
var barrel_len := 1.0
var _barrel: MeshInstance3D
var _rod: MeshInstance3D
var _eye_b: MeshInstance3D


## Build it. `closed` is the pin-to-pin length fully retracted (the barrel is a
## little shorter than that); left 0, it's taken as 60% of the length now.
func setup(a: Node3D, a_pt: Vector3, b: Node3D, b_pt: Vector3, r: float, col: Color, closed: float = 0.0) -> void:
	a_node = a
	a_local = a_pt
	b_node = b
	b_local = b_pt
	radius = r
	var now := _ends()
	var L: float = (now[0] as Vector3).distance_to(now[1] as Vector3)
	barrel_len = (closed if closed > 0.0 else L * 0.6) - r * 1.2
	# the barrel: along +Y from its base pin, painted, the caps, gland, ports
	var bk := MeshKit.new()
	var mk := MeshKit.new()
	bk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, r * 0.6, 0)), r, r, barrel_len - r * 0.6, 14, col, true)
	bk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, r * 0.3, 0)), r * 1.12, r * 1.12, r * 0.6, 14, col.darkened(0.15), true)
	bk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, barrel_len - r * 0.5, 0)), r * 1.14, r * 1.14, r * 0.5, 14, col.darkened(0.15), true)
	mk.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, barrel_len, 0)), r * 0.62, r * 0.62, r * 0.2, 12, EK.STEEL, true)
	for py in [r * 1.4, barrel_len - r * 0.9]:
		mk.box(Transform3D(Basis.IDENTITY, Vector3(0, py, r * 0.95)), Vector3(r * 0.5, r * 0.5, r * 0.5), EK.STEEL)
	mk.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(r * 0.55, 0, 0)), r * 0.62, r * 0.62, r * 1.1, 12, EK.STEEL, true)   # base eye
	_pin(mk, r)                        # and the pin through it (Dave: every cylinder end shows its pin)
	_barrel = MeshInstance3D.new()
	var bi := bk.instance("Barrel")
	bi.material_override = EK.paint_mat(Color.WHITE, 0.3, 0.9)
	_barrel.add_child(bi)
	var mi := mk.instance("BarrelMetal")
	mi.material_override = EK.metal_mat()
	_barrel.add_child(mi)
	add_child(_barrel)
	# the rod: a unit length along +Y, stretched to fit each frame
	var rk := MeshKit.new()
	rk.cylinder(Transform3D.IDENTITY, r * 0.5, r * 0.5, 1.0, 12, EK.CHROME, false)
	_rod = rk.instance("Rod")
	var cm := EK.metal_mat()
	cm.roughness = 0.08
	_rod.material_override = cm
	add_child(_rod)
	var ek := MeshKit.new()
	ek.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(r * 0.55, 0, 0)), r * 0.62, r * 0.62, r * 1.1, 12, EK.STEEL, true)
	_pin(ek, r)
	_eye_b = ek.instance("RodEye")
	_eye_b.material_override = EK.metal_mat()
	add_child(_eye_b)
	update()


## A pin through an eye (along the eye's axis): bright steel, standing out past
## the clevis plates either side, a keeper head on each end.
func _pin(k: MeshKit, r: float) -> void:
	var half := r * 1.25 + 0.05
	var pr := r * 0.3
	k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(half, 0, 0)), pr, pr, half * 2.0, 10, Color(0.78, 0.78, 0.8), true)
	for sx in [-1.0, 1.0]:
		k.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(float(sx) * half + (pr * 0.35 if sx > 0.0 else 0.0), 0, 0)), pr * 1.5, pr * 1.5, pr * 0.35, 10, Color(0.6, 0.6, 0.62), true)


func _ends() -> Array:
	var A := a_node.global_transform * a_local
	var B := b_node.global_transform * b_local
	var inv := (get_parent() as Node3D).global_transform.affine_inverse() if get_parent() is Node3D else Transform3D.IDENTITY
	return [inv * A, inv * B]


func _process(_dt: float) -> void:
	update()
	# a cracked line sprays as hard as the oil in it is pushed
	if sim_ram != null:
		for h in hoses:
			if is_instance_valid(h) and float(h.leak) > 0.0:
				h.leak_pressure = maxf(float(sim_ram.p_cap), float(sim_ram.p_rod))


func update() -> void:
	if a_node == null or b_node == null or not is_inside_tree() and not a_node.is_inside_tree():
		pass
	var e := _ends()
	var A: Vector3 = e[0]
	var B: Vector3 = e[1]
	var d := B - A
	var L := d.length()
	if L < 0.01:
		return
	var y := d / L
	var ref := pin_axis if absf(y.dot(pin_axis)) < 0.9 else Vector3.FORWARD
	var z := ref.cross(y).normalized()
	var x := y.cross(z).normalized()
	var basis := Basis(x, y, z)
	_barrel.transform = Transform3D(basis, A)
	var rod_from := A + y * (barrel_len - radius * 0.4)
	var rod_len := maxf(0.02, L - (barrel_len - radius * 0.4))
	_rod.transform = Transform3D(basis * Basis.from_scale(Vector3(1, rod_len, 1)), rod_from)
	_eye_b.transform = Transform3D(basis, B)


## A hose fitting on the barrel: 0 the base-end port, 1 the rod-end port.
## Returns [node, point in that node] for a hose to pin to.
func port(i: int) -> Array:
	var y := radius * 1.4 if i == 0 else barrel_len - radius * 0.9
	return [_barrel, Vector3(0, y, radius * 1.25)]


## Two hoses from the valve block at `from_node` / `from_pt` to this ram's ports.
func plumb(owner_root: Node3D, from_node: Node3D, from_pt: Vector3, r: float = 0.018, via: Array = []) -> void:
	var Hose = ResourceLoader.load("res://scripts/hyd_hose.gd", "", ResourceLoader.CACHE_MODE_REPLACE)
	for i in range(2):
		var pr := port(i)
		var h = Hose.new()
		var off := Vector3(0.045 * (float(i) - 0.5), 0, 0)
		var v2: Array = []
		for w in via:
			v2.append((w as Vector3) + off)
		h.via = v2
		owner_root.add_child(h)
		h.setup(from_node, from_pt + off, pr[0], pr[1], r, 1.15)
		hoses.append(h)


## The middle of the ram, in the world (for its pressure tag).
func mid_global() -> Vector3:
	var e := _ends()
	return (get_parent() as Node3D).global_transform * (((e[0] as Vector3) + (e[1] as Vector3)) * 0.5)
