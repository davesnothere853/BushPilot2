extends RefCounted
## Tyres and landing-gear legs that can be fitted to the aeroplane.
## Numbers are per main wheel. They are rounded from real tyres of the kind
## fitted to bush planes, then tuned so the differences can be felt.
##
## radius     outside radius, m
## width      tread width, m
## psi        inflation pressure
## k          vertical stiffness at that pressure, N/m (soft tyres squash more)
## travel     how far the tyre can squash before the rim hits, m
## damp       how much a bump is soaked up inside the tyre (0..1)
## mass       extra weight of both mains over the standard tyre, kg
## drag       extra flat-plate drag area of both mains over the standard tyre, m^2
## float      how well it stays on top of soft ground (1 = standard, higher floats)
## corner     sideways stiffness, times the load per radian of slip
## rough      how much of a rough surface's bumps reach the airframe (0..1)

const TYRES := {
	"std": {"name": "6.00-6 standard", "radius": 0.22, "width": 0.15, "psi": 29.0, "k": 170000.0, "travel": 0.10,
		"damp": 0.10, "mass": 0.0, "drag": 0.0, "float": 1.0, "corner": 9.0, "rough": 1.0, "price": 0},
	"850": {"name": "8.50-6 bush", "radius": 0.26, "width": 0.21, "psi": 20.0, "k": 125000.0, "travel": 0.14,
		"damp": 0.16, "mass": 8.0, "drag": 0.025, "float": 1.6, "corner": 8.0, "rough": 0.8, "price": 1400},
	"26": {"name": "26 in tundra", "radius": 0.33, "width": 0.27, "psi": 12.0, "k": 92000.0, "travel": 0.20,
		"damp": 0.24, "mass": 18.0, "drag": 0.06, "float": 2.6, "corner": 6.5, "rough": 0.6, "price": 3200},
	"29": {"name": "29 in tundra", "radius": 0.368, "width": 0.30, "psi": 8.0, "k": 77000.0, "travel": 0.23,
		"damp": 0.30, "mass": 26.0, "drag": 0.085, "float": 3.6, "corner": 5.5, "rough": 0.48, "price": 4600},
	"wskis": {"name": "Wheel-skis (8.50 tyres)", "radius": 0.26, "width": 0.21, "psi": 20.0, "k": 125000.0, "travel": 0.14,
		"damp": 0.16, "mass": 38.0, "drag": 0.07, "float": 6.0, "corner": 8.0, "rough": 0.8, "price": 7800, "ski": true},
	"31": {"name": "31 in bushwheel", "radius": 0.394, "width": 0.34, "psi": 6.0, "k": 66000.0, "travel": 0.25,
		"damp": 0.36, "mass": 34.0, "drag": 0.11, "float": 4.8, "corner": 4.8, "rough": 0.38, "price": 6500},
	# DC-3 only: 17.00-16 mains, about 1.35 m across.
	"dc3": {"name": "17.00-16 (DC-3)", "radius": 0.67, "width": 0.43, "psi": 45.0, "k": 1500000.0, "travel": 0.16,
		"damp": 0.14, "mass": 0.0, "drag": 0.0, "float": 2.2, "corner": 7.0, "rough": 0.6, "price": 0, "only": "dc3"},
	# Biplane only: smooth 7.50-10 tyres on spoked-look hubs.
	"bi": {"name": "7.50-10 (biplane)", "radius": 0.36, "width": 0.19, "psi": 22.0, "k": 115000.0, "travel": 0.14,
		"damp": 0.16, "mass": 0.0, "drag": 0.0, "float": 1.7, "corner": 7.5, "rough": 0.8, "price": 0, "only": "biplane"},
}
const TYRE_ORDER: Array[String] = ["std", "850", "26", "29", "31", "wskis"]

## Main gear legs.
## k / preload    spring, N/m and N; prog stiffens the last part of the stroke
## travel         stroke before the leg bottoms out, m
## comp / reb     damping squashing and extending, N per m/s. Spring steel has
##                almost none, so it bounces; an oleo soaks a landing up.
const LEGS := {
	"spring": {"name": "Spring steel", "k": 46000.0, "preload": 0.0, "prog": 0.6, "travel": 0.26,
		"comp": 1400.0, "reb": 1400.0, "mass": 0.0, "strength": 1.0, "price": 0},
	"oleo": {"name": "Oleo struts", "k": 30000.0, "preload": 2600.0, "prog": 3.0, "travel": 0.25,
		"comp": 5200.0, "reb": 14000.0, "mass": 14.0, "strength": 1.25, "price": 5200},
	"amphib": {"name": "Amphibious floats", "k": 34000.0, "preload": 2000.0, "prog": 2.5, "travel": 0.14,
		"comp": 4800.0, "reb": 12000.0, "mass": 190.0, "drag": 0.42, "strength": 1.1, "price": 48000},
	# DC-3 only: big oleo legs sized for 12.7 t (6,000 kg a side at rest).
	"dc3": {"name": "DC-3 oleo", "k": 420000.0, "preload": 30000.0, "prog": 3.0, "travel": 0.30,
		"comp": 60000.0, "reb": 160000.0, "mass": 0.0, "strength": 1.4, "price": 0, "only": "dc3"},
	# Biplane only: long-stroke oleo legs on a split axle.
	"bi": {"name": "Biplane oleo", "k": 32000.0, "preload": 2400.0, "prog": 3.0, "travel": 0.24,
		"comp": 5000.0, "reb": 13000.0, "mass": 0.0, "strength": 1.2, "price": 0, "only": "biplane"},
}
const DC3_TAIL_TYRE := {"radius": 0.22, "k": 700000.0, "travel": 0.06, "damp": 0.14, "corner": 7.0, "float": 1.0, "rough": 1.0}
const DC3_TAIL_LEG := {"k": 220000.0, "preload": 8000.0, "prog": 2.0, "travel": 0.2, "comp": 25000.0, "reb": 60000.0}
const LEG_ORDER: Array[String] = ["spring", "oleo", "amphib"]

## Amphibious floats: the wheels are part of the floats, so the tyres chosen
## above do not apply. Heavy and draggy, but land on water or a runway.
const AMPHIB_MAIN := {"radius": 0.20, "width": 0.13, "k": 150000.0, "travel": 0.06, "damp": 0.12, "corner": 8.0, "float": 1.0, "rough": 1.0}
const AMPHIB_NOSE := {"radius": 0.14, "width": 0.10, "k": 110000.0, "travel": 0.05, "damp": 0.12, "corner": 7.0, "float": 0.9, "rough": 1.0}
const AMPHIB_NOSE_LEG := {"k": 30000.0, "preload": 1200.0, "prog": 2.0, "travel": 0.12, "comp": 3500.0, "reb": 8000.0}

## The tailwheel is the same on every fit for now: a small solid-ish tyre on a leaf spring.
const TAIL_TYRE := {"radius": 0.11, "k": 90000.0, "travel": 0.04, "damp": 0.12, "corner": 7.0, "float": 0.8, "rough": 1.0}
const TAIL_LEG := {"k": 28000.0, "preload": 0.0, "prog": 1.0, "travel": 0.14, "comp": 900.0, "reb": 900.0}


## How a surface behaves under a tyre.
## grip     peak friction when the tyre is gripping
## slide    friction once it is skidding (locked or sliding sideways)
## roll     rolling resistance on a firm, standard tyre (fraction of the load)
## soft     how far a standard tyre sinks, m at full load; sinking adds drag
## bump     height of the ground's own bumps and ruts, m
## scale    length of those bumps, m
static func surface(kind: int, season: int) -> Dictionary:
	# Kinds match terrain.gd SURF_*: 0 rough, 1 gravel, 2 grass, 3 dirt, 4 snow,
	# 5 packed snow, 6 ice, 7 water
	match kind:
		1:
			return {"grip": 0.62, "slide": 0.50, "roll": 0.030, "soft": 0.012, "bump": 0.025, "scale": 3.0}
		2:
			var g := {"grip": 0.55, "slide": 0.40, "roll": 0.045, "soft": 0.03, "bump": 0.035, "scale": 5.0}
			if season == 1:       # wet autumn grass
				g["grip"] = 0.40
				g["slide"] = 0.26
			elif season == 3:     # spring: soft and soggy
				g["soft"] = 0.07
				g["roll"] = 0.06
			return g
		3:
			var d := {"grip": 0.60, "slide": 0.48, "roll": 0.035, "soft": 0.02, "bump": 0.035, "scale": 4.0}
			if season == 3:       # spring mud
				d = {"grip": 0.40, "slide": 0.30, "roll": 0.07, "soft": 0.11, "bump": 0.05, "scale": 3.0}
			return d
		4:
			return {"grip": 0.32, "slide": 0.22, "roll": 0.05, "soft": 0.16, "bump": 0.04, "scale": 6.0}
		5:
			return {"grip": 0.28, "slide": 0.18, "roll": 0.03, "soft": 0.03, "bump": 0.02, "scale": 6.0}
		6:
			return {"grip": 0.12, "slide": 0.07, "roll": 0.012, "soft": 0.0, "bump": 0.006, "scale": 8.0}
		7:
			return {"grip": 0.0, "slide": 0.0, "roll": 0.0, "soft": 0.0, "bump": 0.0, "scale": 1.0}
	# Rough, unprepared ground: tussocks, rocks and holes.
	return {"grip": 0.55, "slide": 0.45, "roll": 0.06, "soft": 0.05, "bump": 0.11, "scale": 2.2}
