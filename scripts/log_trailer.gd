extends "res://scripts/towable.gd"
## A tandem log trailer for the pickup (DESIGN_NOTES 124): a steel deck on
## two axles with three bunks and their stakes. Logs ride lengthways, five
## across and three high (LOG_CAP); anything else goes on the deck grid.
## Back the pickup's ball to its tongue and hitch it like the sluice
## trailer. Kept at the tool yard; where you leave it is saved.

const BED_MAX_KG := 2600.0
const DECK_Y := 0.92
const LOG_CAP := 15
const LOG_Z := 0.3                  # middle of the load, along the trailer
## Cargo pieces on the deck (crates, drums): a 2 x 3 grid.
const BED_SPOTS := [
	Vector3(-0.5, DECK_Y, -1.2), Vector3(0.5, DECK_Y, -1.2),
	Vector3(-0.5, DECK_Y, 0.3), Vector3(0.5, DECK_Y, 0.3),
	Vector3(-0.5, DECK_Y, 1.8), Vector3(0.5, DECK_Y, 1.8),
]
const PAINT := Color(0.16, 0.17, 0.18)
const SAVE := "user://log_trailer.cfg"

var driven := false                 # (cargo.gd asks: a trailer's never driven)
var cargo_kg: Callable              # func() -> float, what's on it (main)


func _init() -> void:
	kind = "logtrailer"
	tongue_local = Vector3(0, 0.58, -3.55)
	axle_local = Vector3(0, 0.36, 0.55)
	track = 1.75
	wheel_r = 0.36
	mass = 850.0
	axles = 2
	axle_gap = 0.9


func display_name() -> String:
	return "log trailer"


const TowPoints = preload("res://scripts/tow_points.gd")
## Winch / tow points (DESIGN_NOTES 225): the tongue's eye, and a shackle
## each side on the back of the frame.
const WINCH_POINTS_REAR := [
	["rear left shackle", Vector3(-0.85, 0.85, 2.60), Vector3(0, 0, 1)],
	["rear right shackle", Vector3(0.85, 0.85, 2.60), Vector3(0, 0, 1)],
]

func build() -> void:
	var kit = load("res://scripts/meshkit.gd").new()
	var steel := Color(0.40, 0.41, 0.43)
	var wood := Color(0.47, 0.36, 0.24)
	# main rails and the deck
	for sx in [-0.45, 0.45]:
		kit.box_at(Vector3(sx, DECK_Y - 0.14, 0.3), Vector3(0.12, 0.18, 4.6), PAINT)
	kit.box_at(Vector3(0, DECK_Y - 0.03, 0.3), Vector3(2.0, 0.04, 4.4), wood)
	for k in range(8):
		kit.box_at(Vector3(0, DECK_Y - 0.008, -1.85 + k * 0.6), Vector3(2.02, 0.02, 0.03), wood.darkened(0.3))
	# bunks and stakes
	for bz in [-1.2, 0.3, 1.8]:
		kit.box_at(Vector3(0, DECK_Y + 0.06, bz), Vector3(2.1, 0.12, 0.16), PAINT)
		for sx in [-1.0, 1.0]:
			kit.box_at(Vector3(sx, DECK_Y + 0.55, bz), Vector3(0.08, 1.0, 0.08), steel)
	# headache rack at the front
	kit.box_at(Vector3(0, DECK_Y + 0.6, -1.95), Vector3(2.0, 1.1, 0.06), PAINT.lightened(0.05))
	for k in range(4):
		kit.box_at(Vector3(0, DECK_Y + 0.2 + k * 0.28, -1.92), Vector3(1.9, 0.05, 0.05), steel)
	# lights like the truck's, the plate, mud flaps, chain binders on the stakes (DESIGN_NOTES 215)
	var EK = load("res://scripts/equip_kit.gd")
	var m = load("res://scripts/meshkit.gd").new()
	for sx in [-0.85, 0.85]:
		kit.box_at(Vector3(sx, DECK_Y - 0.12, 2.55), Vector3(0.24, 0.12, 0.06), steel)
		EK.lamp(kit, m, self, Vector3(sx, DECK_Y - 0.12, 2.6), Vector3(0, 0, 1), 0.11, 0.11, Color(0.85, 0.08, 0.05), true)
		EK.lamp(kit, m, self, Vector3(sx * 1.17, DECK_Y - 0.05, -1.9), Vector3(sx, 0, 0), 0.06, 0.04, Color(1.0, 0.6, 0.1))     # side markers
		kit.box_at(Vector3(sx, DECK_Y - 0.55, 2.3), Vector3(0.55, 0.6, 0.015), Color(0.06, 0.06, 0.06))                    # mud flaps
		for bz in [-1.2, 0.3, 1.8]:
			m.box_at(Vector3(sx * 1.0, DECK_Y + 0.85, bz + 0.05), Vector3(0.05, 0.22, 0.05), Color(0.2, 0.2, 0.2))           # binders
	kit.box_at(Vector3(0, DECK_Y - 0.15, 2.62), Vector3(0.3, 0.15, 0.01), Color(0.9, 0.85, 0.3))
	EK.hazard(kit, Vector3(-1.0, DECK_Y - 0.02, 2.56), Vector3(1.0, DECK_Y - 0.02, 2.56), Vector3(1.0, DECK_Y + 0.02, 2.56), Vector3(-1.0, DECK_Y + 0.02, 2.56), Vector3(0, 0, 1), 16)
	add_running_gear(kit, PAINT)
	add_child(kit.instance("LogTrailer"))
	var mi = m.instance("LogTrailerMetal")
	mi.material_override = EK.metal_mat()
	add_child(mi)
	TowPoints.build(self, WINCH_POINTS_REAR, PAINT)


## Where log `i` lies (world): along the trailer, five across, three high.
func log_xf(i: int) -> Transform3D:
	var tier := clampi(i / 5, 0, 2)
	var col := i % 5
	var x := (float(col) - 2.0) * 0.36 + (0.18 if tier % 2 == 1 else 0.0) * (1.0 if col < 4 else -1.0)
	var y := DECK_Y + 0.12 + float(tier) * 0.31
	return get_global_transform_interpolated() * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, y, LOG_Z))


func bed_xf(spot: int) -> Transform3D:
	var sp: Vector3 = BED_SPOTS[clampi(spot, 0, BED_SPOTS.size() - 1)]
	return get_global_transform_interpolated() * Transform3D(Basis.IDENTITY, sp)


## Standing beside it or at the back.
func at_bed(p: Vector3) -> bool:
	var l := global_transform.affine_inverse() * p
	if absf(l.x) < 1.3 and l.z > 2.5 and l.z < 3.6:
		return true
	return absf(l.x) > 1.0 and absf(l.x) < 2.1 and l.z > -1.9 and l.z < 2.5


var _dirty := false
var _save_t := 0.0


func mark_moved() -> void:
	_dirty = true


func _physics_process(delta: float) -> void:
	_save_t += delta
	if _dirty and _save_t > 3.0:
		_save_t = 0.0
		_dirty = false
		save_spot()


func total_mass() -> float:
	return mass + (float(cargo_kg.call()) if cargo_kg.is_valid() else 0.0)


func save_spot() -> void:
	var cf := ConfigFile.new()
	cf.set_value("t", "xf", global_transform)
	cf.save(SAVE)


static func saved_xf(default: Transform3D) -> Transform3D:
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		var x = cf.get_value("t", "xf", default)
		if x is Transform3D:
			return x
	return default


## Where a winch hook or tow strap can go: [[name, world point], ...].
func winch_points() -> Array:
	var out: Array = [["tongue eye", global_transform * tongue_local]] if is_inside_tree() else []
	return out + TowPoints.world(self, WINCH_POINTS_REAR)
