extends RefCounted
## Paint schemes. Each plane keeps its livery index in its save (plane.livery),
## and the hangar's paint shop (menu.gd fleet page) resprays for a few dollars.
## Wolverine rows: [name, body, trim, stripe]. DC-3 rows: [name, skin, cheat].

const WOLVERINE := [
	["Bush Classic", Color(0.90, 0.86, 0.76), Color(0.82, 0.36, 0.10), Color(0.36, 0.22, 0.13)],
	["Forest Service", Color(0.86, 0.87, 0.78), Color(0.15, 0.37, 0.20), Color(0.09, 0.22, 0.12)],
	["Arctic Rescue", Color(0.93, 0.93, 0.92), Color(0.76, 0.13, 0.11), Color(0.14, 0.22, 0.44)],
	["Yukon Gold", Color(0.88, 0.72, 0.15), Color(0.13, 0.13, 0.14), Color(0.32, 0.25, 0.07)],
	["Bare Metal", Color(0.70, 0.71, 0.73), Color(0.62, 0.12, 0.10), Color(0.38, 0.39, 0.41)],
	["Lake Patrol", Color(0.93, 0.93, 0.91), Color(0.16, 0.27, 0.52), Color(0.85, 0.66, 0.12)],
	["Mail Run", Color(0.72, 0.09, 0.07), Color(0.92, 0.88, 0.76), Color(0.10, 0.10, 0.11)],
	["Muskeg Green", Color(0.33, 0.36, 0.22), Color(0.88, 0.36, 0.10), Color(0.12, 0.12, 0.12)],
	["Sky Hawk", Color(0.50, 0.68, 0.84), Color(0.93, 0.93, 0.91), Color(0.10, 0.14, 0.28)],
]

const DC3 := [
	["Silverliner", Color(0.74, 0.75, 0.76), Color(0.62, 0.12, 0.10)],
	["Polar Star", Color(0.90, 0.91, 0.93), Color(0.13, 0.28, 0.54)],
	["Bush Freight", Color(0.44, 0.45, 0.35), Color(0.85, 0.66, 0.12)],
	["Fireweed", Color(0.84, 0.82, 0.78), Color(0.55, 0.19, 0.40)],
	["Midnight Mail", Color(0.16, 0.20, 0.32), Color(0.86, 0.70, 0.22)],
	["Olive Drab", Color(0.33, 0.36, 0.22), Color(0.90, 0.90, 0.86)],
	["Tundra Orange", Color(0.86, 0.42, 0.12), Color(0.12, 0.12, 0.13)],
	["Glacier Blue", Color(0.62, 0.72, 0.80), Color(0.10, 0.20, 0.40)],
	["Spruce", Color(0.20, 0.34, 0.26), Color(0.90, 0.82, 0.55)],
	["Cream & Red", Color(0.90, 0.86, 0.74), Color(0.70, 0.10, 0.08)],
]

## Biplane rows: [name, fuselage, wings and tail, trim].
const BIPLANE := [
	["Navy Trainer", Color(0.16, 0.27, 0.52), Color(0.93, 0.74, 0.10), Color(0.70, 0.10, 0.08)],
	["Barnstormer", Color(0.72, 0.09, 0.07), Color(0.92, 0.88, 0.76), Color(0.08, 0.08, 0.09)],
	["Silver Wings", Color(0.72, 0.73, 0.75), Color(0.74, 0.75, 0.77), Color(0.10, 0.10, 0.11)],
	["Duster Yellow", Color(0.92, 0.76, 0.12), Color(0.92, 0.76, 0.12), Color(0.14, 0.32, 0.18)],
	["Air Mail", Color(0.13, 0.30, 0.20), Color(0.85, 0.82, 0.70), Color(0.75, 0.55, 0.12)],
	["Air Circus", Color(0.93, 0.93, 0.91), Color(0.72, 0.10, 0.08), Color(0.16, 0.27, 0.52)],
	["Black Cat", Color(0.08, 0.08, 0.09), Color(0.93, 0.74, 0.10), Color(0.72, 0.10, 0.08)],
	["Seaplane Base", Color(0.10, 0.14, 0.28), Color(0.72, 0.73, 0.75), Color(0.88, 0.36, 0.10)],
]

const PRICE := 350


static func table(plane_type: String) -> Array:
	if plane_type == "biplane":
		return BIPLANE
	return DC3 if plane_type == "dc3" else WOLVERINE


## Paint you mix yourself in the paint shop (DESIGN_NOTES 153): period
## aircraft enamels. A plane with its own colours (plane.paint) uses them in
## place of its scheme's.
const PALETTE := [
	["White", Color(0.93, 0.93, 0.91)], ["Cream", Color(0.90, 0.86, 0.74)], ["Silver", Color(0.72, 0.73, 0.75)],
	["Light grey", Color(0.58, 0.60, 0.61)], ["Black", Color(0.08, 0.08, 0.09)], ["Insignia red", Color(0.72, 0.10, 0.08)],
	["Maroon", Color(0.42, 0.08, 0.10)], ["Int'l orange", Color(0.88, 0.36, 0.10)], ["Chrome yellow", Color(0.93, 0.74, 0.10)],
	["Lemon", Color(0.95, 0.88, 0.30)], ["Olive drab", Color(0.33, 0.36, 0.22)], ["Forest green", Color(0.15, 0.37, 0.20)],
	["Sea green", Color(0.22, 0.50, 0.44)], ["Sky blue", Color(0.50, 0.68, 0.84)], ["Insignia blue", Color(0.16, 0.27, 0.52)],
	["Navy", Color(0.10, 0.14, 0.28)], ["Sand", Color(0.78, 0.68, 0.50)], ["Brown", Color(0.36, 0.22, 0.13)],
	["Purple", Color(0.40, 0.22, 0.48)], ["Pink", Color(0.86, 0.50, 0.58)],
]
const PAINT_SLOTS := {"wolverine": ["Body", "Trim", "Stripe"], "biplane": ["Fuselage", "Wings and tail", "Trim"], "dc3": ["Skin", "Cheat line"]}


## The colours to paint a plane in: its own mix if it has one, else its scheme.
static func for_plane(p: Object) -> Array:
	var t := String(p.get("plane_type"))
	var r: Array = row(t, int(p.get("livery"))).duplicate()
	var own = p.get("paint")
	if own is Array and (own as Array).size() >= r.size() - 1:
		r[0] = "Custom"
		for k in range(1, r.size()):
			r[k] = (own as Array)[k - 1]
	return r


static func row(plane_type: String, i: int) -> Array:
	var t := table(plane_type)
	return t[clampi(i, 0, t.size() - 1)]
