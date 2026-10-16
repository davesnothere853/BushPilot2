extends RefCounted
## Where everything sits on the instrument panel. The panel surface is a
## 1280 x 640 picture (paint, printed labels, placards, radio) shown on a flat
## face with round holes cut where the instruments go. Each instrument is a real
## 3D part sitting in its hole: a recessed case, a printed dial, 3D needles,
## a bezel and glass. Knobs and switches are 3D parts over the printed labels.

const W := 1280.0
const H := 640.0
const WIDTH_M := 1.10              # panel width in metres
const PX_PER_M := W / WIDTH_M
const TOP_Y := 0.50                # height of the panel's top edge (aircraft coordinates)
const FACE_Z := -0.80              # the panel face, metres ahead of the cabin centre

## Virtual drawing radius used for every dial face picture (the HUD code draws at this size).
const GAUGE_R := 62.0

## The six main flight instruments (3 1/8 inch): position in pixels, dial radius in metres.
const SIX_R := 0.044
const GAUGES := {
	"airspeed": Vector2(217, 132), "attitude": Vector2(361, 132), "altimeter": Vector2(505, 132),
	"tach": Vector2(217, 282), "heading": Vector2(361, 282), "vsi": Vector2(505, 282),
}

## Small engine dials (2 1/4 inch). Values in the units printed on the dial.
const SMALL_R := 0.026
const DIALS := {
	"map": {"pos": Vector2(642, 104), "title": "MAN PRESS", "lo": 10.0, "hi": 35.0, "a0": -135.0, "a1": 135.0,
		"labels": [[10, "10"], [15, "15"], [20, "20"], [25, "25"], [30, "30"], [35, "35"]], "minor": 25, "zones": [[15.0, 29.0, "g"]]},
	"oilt": {"pos": Vector2(718, 104), "title": "OIL °F", "lo": 60.0, "hi": 260.0, "a0": -120.0, "a1": 120.0,
		"labels": [[60, "60"], [100, "100"], [150, "150"], [200, "200"], [250, "250"]], "minor": 20, "zones": [[100.0, 245.0, "g"], [245.0, 260.0, "r"]]},
	"oilp": {"pos": Vector2(794, 104), "title": "OIL PSI", "lo": 0.0, "hi": 115.0, "a0": -120.0, "a1": 120.0,
		"labels": [[0, "0"], [25, "25"], [50, "50"], [75, "75"], [100, "100"]], "minor": 23, "zones": [[0.0, 25.0, "r"], [25.0, 90.0, "g"], [100.0, 115.0, "r"]]},
	"cht": {"pos": Vector2(870, 104), "title": "CYL °F", "lo": 100.0, "hi": 500.0, "a0": -120.0, "a1": 120.0,
		"labels": [[100, "100"], [200, "200"], [300, "300"], [400, "400"], [500, "500"]], "minor": 20, "zones": [[200.0, 460.0, "g"], [460.0, 500.0, "r"]]},
	"egt": {"pos": Vector2(642, 188), "title": "EGT", "lo": 0.0, "hi": 1.0, "a0": -120.0, "a1": 120.0,
		"labels": [], "minor": 10, "zones": []},
	"fuell": {"pos": Vector2(718, 188), "title": "LEFT GAL", "lo": 0.0, "hi": 20.0, "a0": -100.0, "a1": 100.0,
		"labels": [[0, "E"], [10, "1/2"], [20, "F"]], "minor": 8, "zones": [[0.0, 2.0, "r"]]},
	"fuelr": {"pos": Vector2(794, 188), "title": "RIGHT GAL", "lo": 0.0, "hi": 20.0, "a0": -100.0, "a1": 100.0,
		"labels": [[0, "E"], [10, "1/2"], [20, "F"]], "minor": 8, "zones": [[0.0, 2.0, "r"]]},
	"amps": {"pos": Vector2(870, 188), "title": "AMPS", "lo": -60.0, "hi": 60.0, "a0": -100.0, "a1": 100.0,
		"labels": [[-60, "-"], [0, "0"], [60, "+"]], "minor": 12, "zones": []},
}

const CLOCK_POS := Vector2(960, 132)
const CLOCK_R := 0.030

## Warning lamps: id, position, label, colour key ("r" red, "a" amber)
const LAMPS := [
	["stall", Vector2(640, 262), "STALL", "r"],
	["oil", Vector2(700, 262), "OIL", "r"],
	["volts", Vector2(760, 262), "VOLTS", "a"],
	["fuel", Vector2(820, 262), "FUEL", "a"],
	["starter", Vector2(880, 262), "START", "a"],
	["brake", Vector2(940, 262), "BRAKE", "a"],
]

const RADIO_RECT := Rect2(1030, 50, 220, 290)

## Lower-panel controls: id -> [position in pixels, printed label]
const CONTROLS := {
	"master": [Vector2(118, 430), "BAT"],
	"alternator": [Vector2(166, 430), "ALT"],
	"mags": [Vector2(250, 440), "MAGNETOS"],
	"primer": [Vector2(470, 470), "PRIMER"],
	"carb_heat": [Vector2(575, 455), "CARB HEAT"],
	"throttle": [Vector2(668, 480), "THROTTLE"],
	"prop": [Vector2(760, 480), "PROP"],
	"mixture": [Vector2(852, 480), "MIXTURE"],
	"cowl": [Vector2(1100, 450), "COWL FLAPS"],
	"lt_beacon": [Vector2(110, 540), "BCN"],
	"lt_nav": [Vector2(152, 540), "NAV"],
	"lt_strobe": [Vector2(194, 540), "STROBE"],
	"lt_taxi": [Vector2(236, 540), "TAXI"],
	"lt_landing": [Vector2(278, 540), "LAND"],
	"lt_panel": [Vector2(56, 540), "PANEL LT"],
}


## A spot on the panel picture, in aircraft coordinates on the panel face.
static func to_local(px: Vector2) -> Vector3:
	return Vector3(px.x / PX_PER_M - WIDTH_M * 0.5, TOP_Y - px.y / PX_PER_M, FACE_Z)


static func m_to_px(m: float) -> float:
	return m * PX_PER_M
