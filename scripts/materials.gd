extends RefCounted
## What the world is made of (DESIGN_NOTES 229, Dave: "simulate the material
## everything in the world is made out of"). Real engineering numbers for each
## material; a structure's pieces (structure.gd) take their mass, stiffness and
## the energy it takes to break them from these and their actual dimensions.
##
##   rho   density, kg/m3
##   E     Young's modulus, Pa (how stiff)
##   fy    strength in bending/yield, Pa (steel: yield; wood: modulus of rupture)
##   ft    tensile strength, Pa
##   Gf    fracture energy, J/m2 (energy to open a crack through it)
##   rot   plastic hinge rotation before it lets go, rad (ductile steel bends a
##         long way; wood and concrete hardly at all)
##   mode  how it fails: "bend" (steel: bends, kinks, then tears), "splinter"
##         (wood: snaps with splinters), "tear" (sheet metal: dents, then tears
##         off its screws), "shatter" (glass, ice), "crumble" (concrete, block,
##         brick, rock), "snap" (cable: whips)
##
##
## Fire (DESIGN_NOTES 229, Dave: buildings burn, the whole town can burn and
## spread, wildfires spread):
##   ign   piloted ignition temperature, C (0: doesn't burn)
##   hoc   heat of combustion, MJ/kg
##   char  char rate, mm/min (wood: the section burns away from the faces)
##   hot   temperature it loses half its strength, C (steel ~550)
##   crack temperature it cracks/fails from heat, C (glass ~150 shock; concrete spalls)
##
## Sources: handbook values (AISC steel, NDS/Wood Handbook Douglas-fir,
## ACI concrete, glass and ice from the materials literature), rounded.

const M := {
	# (fuels for roofs, furnishings and the wildfire are in FUELS below)
	"steel":       {"rho": 7850.0, "E": 200e9, "fy": 250e6, "ft": 400e6, "Gf": 2.0e5, "rot": 0.35, "mode": "bend", "ign": 0.0, "hoc": 0.0, "char": 0.00, "hot": 550.0, "crack": 0.0},
	"steel_sheet": {"rho": 7850.0, "E": 200e9, "fy": 280e6, "ft": 380e6, "Gf": 1.0e5, "rot": 0.8, "mode": "tear", "ign": 0.0, "hoc": 0.0, "char": 0.00, "hot": 550.0, "crack": 0.0},       # 29-26 ga ribbed roofing and siding
	"cable":       {"rho": 7850.0, "E": 150e9, "fy": 1.1e9, "ft": 1.3e9, "Gf": 0.0, "rot": 0.0, "mode": "snap", "ign": 0.0, "hoc": 0.0, "char": 0.00, "hot": 500.0, "crack": 0.0},          # EHS guy strand (E of a strand, not a bar)
	"timber":      {"rho": 530.0, "E": 12.4e9, "fy": 50e6, "ft": 60e6, "Gf": 6000.0, "rot": 0.06, "mode": "splinter", "ign": 300.0, "hoc": 18.0, "char": 0.65, "hot": 250.0, "crack": 0.0},     # Douglas-fir dimension lumber / posts
	"timber_old":  {"rho": 500.0, "E": 10e9, "fy": 32e6, "ft": 40e6, "Gf": 4000.0, "rot": 0.05, "mode": "splinter", "ign": 280.0, "hoc": 18.0, "char": 0.80, "hot": 220.0, "crack": 0.0},     # weathered, checked, a bit of rot
	"plywood":     {"rho": 550.0, "E": 8e9, "fy": 30e6, "ft": 25e6, "Gf": 8000.0, "rot": 0.08, "mode": "splinter", "ign": 290.0, "hoc": 18.0, "char": 0.90, "hot": 200.0, "crack": 0.0},
	"osb":         {"rho": 620.0, "E": 5e9, "fy": 22e6, "ft": 12e6, "Gf": 5000.0, "rot": 0.06, "mode": "splinter", "ign": 290.0, "hoc": 18.5, "char": 1.00, "hot": 190.0, "crack": 0.0},
	"drywall":     {"rho": 700.0, "E": 2e9, "fy": 3e6, "ft": 1.5e6, "Gf": 300.0, "rot": 0.02, "mode": "crumble", "ign": 0.0, "hoc": 0.0, "char": 0.00, "hot": 400.0, "crack": 700.0},
	"concrete":    {"rho": 2400.0, "E": 30e9, "fy": 30e6, "ft": 3e6, "Gf": 120.0, "rot": 0.01, "mode": "crumble", "ign": 0.0, "hoc": 0.0, "char": 0.00, "hot": 600.0, "crack": 350.0},      # fy here: compressive
	"block":       {"rho": 1400.0, "E": 12e9, "fy": 12e6, "ft": 0.8e6, "Gf": 60.0, "rot": 0.005, "mode": "crumble", "ign": 0.0, "hoc": 0.0, "char": 0.00, "hot": 700.0, "crack": 500.0},     # hollow CMU wall, unreinforced (per gross volume)
	"brick":       {"rho": 1900.0, "E": 14e9, "fy": 15e6, "ft": 0.6e6, "Gf": 50.0, "rot": 0.005, "mode": "crumble", "ign": 0.0, "hoc": 0.0, "char": 0.00, "hot": 900.0, "crack": 800.0},
	"stone":       {"rho": 2500.0, "E": 30e9, "fy": 40e6, "ft": 2e6, "Gf": 100.0, "rot": 0.005, "mode": "crumble", "ign": 0.0, "hoc": 0.0, "char": 0.00, "hot": 800.0, "crack": 600.0},     # rubble masonry
	"glass":       {"rho": 2500.0, "E": 70e9, "fy": 40e6, "ft": 40e6, "Gf": 8.0, "rot": 0.0, "mode": "shatter", "ign": 0.0, "hoc": 0.0, "char": 0.00, "hot": 500.0, "crack": 150.0},
	"ice":         {"rho": 917.0, "E": 9e9, "fy": 1.0e6, "ft": 1.0e6, "Gf": 10.0, "rot": 0.0, "mode": "shatter", "ign": 0.0, "hoc": 0.0, "char": 0.00, "hot": 0.0, "crack": 0.0},
	"rock":        {"rho": 2700.0, "E": 50e9, "fy": 150e6, "ft": 10e6, "Gf": 150.0, "rot": 0.002, "mode": "crumble", "ign": 0.0, "hoc": 0.0, "char": 0.00, "hot": 900.0, "crack": 700.0},
	"chainlink":   {"rho": 7850.0, "E": 200e9, "fy": 400e6, "ft": 500e6, "Gf": 1.0e5, "rot": 1.2, "mode": "tear", "ign": 0.0, "hoc": 0.0, "char": 0.00, "hot": 550.0, "crack": 0.0},       # 9 ga wire mesh (per its solid wire)
}


static func get_mat(name: String) -> Dictionary:
	return M.get(name, M["timber"])


## Mass of a member (a straight piece of section b x h, length L).
static func member_mass(mat: String, b: float, h: float, L: float) -> float:
	return float(get_mat(mat)["rho"]) * b * h * L


## Plastic (ultimate) bending moment of a solid rectangular section, N m.
## Steel angle/tube passed as an equivalent solid by its area: use `fill` < 1.
static func moment_cap(mat: String, b: float, h: float, fill: float = 1.0) -> float:
	return float(get_mat(mat)["fy"]) * b * h * h / 4.0 * fill


## Energy to break a member struck from the side (J): a three-hinge mechanism
## (fixed-ish ends, the hit in the span), each hinge turning to its limit
## rotation; plus the energy to crack it right through.
static func member_break_energy(mat: String, b: float, h: float, fill: float = 1.0) -> float:
	var m := get_mat(mat)
	var hinge := moment_cap(mat, b, h, fill) * maxf(float(m["rot"]), 0.01) * 4.0
	var crack := float(m["Gf"]) * b * h * fill
	return hinge + crack


## Energy to punch through a panel (sheet, wall, glass) with a hole the size of
## `hole` (m, the width and height of what hits it): crack round the hole's
## edge through the thickness, plus (sheet metal) the membrane stretching first.
static func panel_break_energy(mat: String, t: float, hole: Vector2) -> float:
	var m := get_mat(mat)
	var edge := 2.0 * (hole.x + hole.y)
	var e := float(m["Gf"]) * t * edge
	if String(m["mode"]) == "tear":
		e += float(m["fy"]) * t * edge * 0.004     # dented and pulled over its screws before it tears
	return e


## The longest a beam can span (simply supported) under a load of w N/m, and
## as a cantilever: M = w L^2 / 8, M = w L^2 / 2.
static func max_span(mat: String, b: float, h: float, w: float, fill: float = 1.0) -> float:
	return sqrt(8.0 * moment_cap(mat, b, h, fill) / maxf(w, 1.0))


static func max_cantilever(mat: String, b: float, h: float, w: float, fill: float = 1.0) -> float:
	return sqrt(2.0 * moment_cap(mat, b, h, fill) / maxf(w, 1.0))


## Breaking load of a cable of diameter d (m), N.
static func cable_break(d: float) -> float:
	return float(M["cable"]["ft"]) * PI * d * d / 4.0 * 0.78     # a 7-wire strand fills ~78% of its circle


static func cable_EA(d: float) -> float:
	return float(M["cable"]["E"]) * PI * d * d / 4.0 * 0.78


## Other fuels (no structural job): [ign C, hoc MJ/kg]
const FUELS := {
	"asphalt_shingle": [370.0, 30.0], "tar_paper": [330.0, 28.0], "furnishings": [280.0, 20.0],
	"hay": [220.0, 15.0], "fuel_oil": [250.0, 43.0], "avgas": [280.0, 44.0], "propane": [470.0, 46.0],
	"grass": [250.0, 16.0], "brush": [270.0, 18.0], "conifer": [280.0, 20.0], "litter": [260.0, 17.0],
}


static func burns(mat: String) -> bool:
	return float(get_mat(mat).get("ign", 0.0)) > 0.0


## How much a material's strength is left at temperature T (C): steel and
## concrete soften (half at "hot", near nothing at 1.6x); wood's strength is
## in the uncharred section (structure.gd shrinks it) and drops a bit with heat.
static func strength_left(mat: String, T: float) -> float:
	var hot := float(get_mat(mat).get("hot", 0.0))
	if hot <= 0.0 or T < 100.0:
		return 1.0
	return clampf(1.0 - 0.5 * pow(maxf(T - 100.0, 0.0) / (hot - 100.0), 1.6), 0.05, 1.0)
