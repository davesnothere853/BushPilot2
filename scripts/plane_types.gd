extends RefCounted
## The aeroplanes you can own, and what makes each one fly the way it does.
## plane.gd starts as the Wolverine and takes on a type with apply_type().
## Positions are aircraft coordinates: -Z forward, Y up, origin at the wing's
## quarter chord on the centreline. Inertia is (pitch, yaw, roll), kg m^2.

const TYPES := {
	"wolverine": {
		"name": "Wolverine 180", "price": 28000, "engines": 1,
		"empty_mass": 760.0, "empty_cg": Vector3(0.0, -0.05, 0.08), "empty_inertia": Vector3(1750.0, 2500.0, 1250.0),
		"max_mass": 1270.0, "rated_power": 172000.0, "prop_radius": 1.0, "rated_rpm": 2600.0,
		"fuel_capacity": 150.0, "crew_mass": 85.0, "cargo_front_max": 220.0, "cargo_rear_max": 90.0,
		"station_pilot": Vector3(0.0, -0.10, 0.05), "station_fuel": Vector3(0.0, 0.85, 0.15),
		"station_front": Vector3(0.0, -0.25, 0.90), "station_rear": Vector3(0.0, -0.20, 1.90),
		"cg_fwd": 0.05, "cg_aft": 0.30,
		"wing_area": 16.2, "wing_span": 11.0, "chord": 1.5, "cl0": 0.30, "cl_slope": 4.95, "stall_alpha": 0.232,
		"flap_dcl": 1.0, "cd0_wing": 0.010, "cm0": -0.04, "cm_flap": -0.10, "parasite_area": 0.43,
		"wing_y": 0.90, "wing_x": [-4.0, -1.45, 1.45, 4.0], "wing_panel_area": [3.5, 4.6, 4.6, 3.5], "dihedral": 4.0,
		"tail_pos": Vector3(0.0, 0.10, 4.70), "tail_area": 3.2, "tail_slope": 3.8, "tail_aspect": 4.0,
		"fin_pos": Vector3(0.0, 0.70, 4.90), "fin_area": 1.7, "fin_slope": 2.6,
		"side_pos": Vector3(0.0, -0.10, 0.75), "side_area": 5.5, "side_slope": 0.9,
		"props": [Vector3(0.0, 0.05, -2.20)], "drag_pos": Vector3(0.0, -0.30, 0.20),
		"hubs": [Vector3(-1.15, -1.27, -0.55), Vector3(1.15, -1.27, -0.55), Vector3(0.0, -0.21, 5.00)],
		"brake_force": 2900.0, "sit_pitch": 11.2, "approach_speed": 33.5, "vne": 160.0, "vfe": 85.0, "prop_inertia": 5.0, "gear_mass_pos": Vector3(0.0, -1.2, -0.55),
		"control_rate": 1.0, "tyres": "", "legs": "",
		"body": [
			["propeller", Vector3(0.0, -0.93, -2.20)], ["nose", Vector3(0.0, -0.45, -2.00)],
			["left wingtip", Vector3(-5.5, 0.92, 0.30)], ["right wingtip", Vector3(5.5, 0.92, 0.30)],
			["belly", Vector3(0.0, -0.66, 0.60)], ["tail", Vector3(0.0, -0.12, 4.60)],
			["fin", Vector3(0.0, 1.75, 5.10)], ["cabin roof", Vector3(0.0, 1.08, 0.20)],
			["left wing mid", Vector3(-2.7, 0.97, 0.10)], ["right wing mid", Vector3(2.7, 0.97, 0.10)],
			["left wing root", Vector3(-1.2, 1.00, 0.10)], ["right wing root", Vector3(1.2, 1.00, 0.10)],
			["left tailplane", Vector3(-1.6, 0.12, 4.50)], ["right tailplane", Vector3(1.6, 0.12, 4.50)],
		],
	},
	# DC-3: two 1,200 hp radials, 29 m of wing, a big tail.
	# Heavy, slow to roll, steady as a rock; long take-off run; flies on one
	# engine but only just, with a hard swing toward the dead one.
	"dc3": {
		"name": "DC-3", "price": 95000, "engines": 2,
		"empty_mass": 8200.0, "empty_cg": Vector3(0.0, -0.05, 0.35), "empty_inertia": Vector3(118000.0, 245000.0, 135000.0),
		"max_mass": 12700.0, "rated_power": 895000.0, "prop_radius": 1.75, "rated_rpm": 2550.0,
		"fuel_capacity": 2200.0, "crew_mass": 170.0, "cargo_front_max": 1600.0, "cargo_rear_max": 1400.0,
		"station_pilot": Vector3(0.0, 0.2, -5.9), "station_fuel": Vector3(0.0, -1.05, 0.30),
		"station_front": Vector3(0.0, -0.6, -1.5), "station_rear": Vector3(0.0, -0.5, 3.0),
		"cg_fwd": -0.05, "cg_aft": 0.95,
		"wing_area": 91.7, "wing_span": 29.0, "chord": 3.2, "cl0": 0.25, "cl_slope": 5.1, "stall_alpha": 0.25,
		"flap_dcl": 0.85, "cd0_wing": 0.008, "cm0": -0.05, "cm_flap": -0.12, "parasite_area": 1.55,
		"wing_y": -1.05, "wing_x": [-10.5, -3.8, 3.8, 10.5], "wing_panel_area": [18.0, 27.85, 27.85, 18.0], "dihedral": 5.0,
		"tail_pos": Vector3(0.0, 1.0, 10.6), "tail_area": 17.8, "tail_slope": 3.6, "tail_aspect": 4.2, "tail_incidence": -0.018,
		"fin_pos": Vector3(0.0, 2.6, 11.0), "fin_area": 8.6, "fin_slope": 2.6,
		"side_pos": Vector3(0.0, 0.1, 1.5), "side_area": 38.0, "side_slope": 0.9,
		"props": [Vector3(-3.35, -0.05, -3.55), Vector3(3.35, -0.05, -3.55)], "drag_pos": Vector3(0.0, -0.4, 0.5),
		"hubs": [Vector3(-3.35, -1.95, -0.85), Vector3(3.35, -1.95, -0.85), Vector3(0.0, -0.45, 10.6)],
		"brake_force": 32000.0, "sit_pitch": 9.7, "approach_speed": 44.0, "vne": 190.0, "vfe": 97.0, "prop_inertia": 120.0, "gear_mass_pos": Vector3(0.0, -1.6, -0.85),
		"control_rate": 0.55, "tyres": "dc3", "legs": "dc3",
		"body": [
			["left propeller", Vector3(-3.35, -1.80, -3.55)], ["right propeller", Vector3(3.35, -1.80, -3.55)],
			["nose", Vector3(0.0, -0.9, -7.4)], ["left wingtip", Vector3(-14.4, -0.2, 0.9)],
			["right wingtip", Vector3(14.4, -0.2, 0.9)], ["belly", Vector3(0.0, -1.35, -2.0)],
			["aft belly", Vector3(0.0, -1.1, 5.0)], ["tail", Vector3(0.0, 0.2, 11.6)],
			["fin", Vector3(0.0, 4.3, 11.6)], ["cabin roof", Vector3(0.0, 1.6, -1.0)],
			["left nacelle", Vector3(-3.35, -0.85, -2.6)], ["right nacelle", Vector3(3.35, -0.85, -2.6)],
			["left wing mid", Vector3(-8.5, -0.55, 0.6)], ["right wing mid", Vector3(8.5, -0.55, 0.6)],
			["left tailplane", Vector3(-4.3, 1.0, 11.2)], ["right tailplane", Vector3(4.3, 1.0, 11.2)],
		],
	},
	# Meadowlark: a 1930s-40s two-seat open-cockpit trainer biplane (the kind
	# that ended up dusting crops and hopping rides across the North), 220 hp
	# 7-cylinder radial, equal-span staggered wings, fabric over steel tube.
	# Slow, draggy, gentle; lands short, floats in ground effect, and the
	# radial makes it swing on take-off. Flown from the rear cockpit.
	# The bush Super Cub (plane_body.gd, DESIGN_NOTES 209-213): a 150 hp
	# flat-four, 10.7 m of fabric wing, very light - stalls around 38 kt
	# with flaps, gets off in a few hundred feet, slow and draggy.
	"supercub": {
		"name": "Super Cub", "price": 24000, "engines": 1, "cylinders": 4, "oil_capacity": 7.6,
		"empty_mass": 460.0, "empty_cg": Vector3(0.0, -0.05, 0.10), "empty_inertia": Vector3(900.0, 1350.0, 1050.0),
		"max_mass": 794.0, "rated_power": 112000.0, "prop_radius": 1.04, "rated_rpm": 2700.0,
		"fuel_capacity": 136.0, "crew_mass": 85.0, "cargo_front_max": 90.0, "cargo_rear_max": 23.0,
		"station_pilot": Vector3(0.0, -0.25, -0.10), "station_fuel": Vector3(0.0, 0.70, 0.10),
		"station_front": Vector3(0.0, -0.30, 0.62), "station_rear": Vector3(0.0, -0.25, 1.40),
		"cg_fwd": 0.0, "cg_aft": 0.32,
		"wing_area": 16.6, "wing_span": 10.73, "chord": 1.6, "cl0": 0.35, "cl_slope": 4.9, "stall_alpha": 0.27,
		"flap_dcl": 0.8, "cd0_wing": 0.012, "cm0": -0.05, "cm_flap": -0.10, "parasite_area": 0.62,
		"wing_y": 0.70, "wing_x": [-4.0, -1.45, 1.45, 4.0], "wing_panel_area": [3.6, 4.7, 4.7, 3.6], "dihedral": 1.0,
		"tail_pos": Vector3(0.0, 0.40, 4.15), "tail_area": 2.9, "tail_slope": 3.8, "tail_aspect": 3.6,
		"fin_pos": Vector3(0.0, 0.95, 4.45), "fin_area": 1.3, "fin_slope": 2.6,
		"side_pos": Vector3(0.0, -0.05, 0.9), "side_area": 4.6, "side_slope": 0.9,
		"props": [Vector3(0.0, 0.0, -1.86)], "drag_pos": Vector3(0.0, -0.10, 0.10),
		"hubs": [Vector3(-1.00, -1.21, -0.36), Vector3(1.00, -1.21, -0.36), Vector3(0.0, -0.14, 4.80)],
		"brake_force": 1900.0, "sit_pitch": 12.0, "approach_speed": 25.0, "vne": 133.0, "vfe": 110.0, "prop_inertia": 4.5, "gear_mass_pos": Vector3(0.0, -1.1, -0.36),
		"control_rate": 1.15, "tyres": "", "legs": "",
		"eye": Vector3(0.0, 0.47, -0.02), "door": Vector3(1.4, 0.0, 0.1), "visual": "res://scripts/supercub_visual.gd",
		"body": [
			["propeller", Vector3(0.0, -1.0, -1.86)], ["nose", Vector3(0.0, -0.45, -1.75)],
			["left wingtip", Vector3(-5.35, 0.70, 0.40)], ["right wingtip", Vector3(5.35, 0.70, 0.40)],
			["belly", Vector3(0.0, -0.64, 0.40)], ["tail", Vector3(0.0, -0.05, 4.62)],
			["fin", Vector3(0.0, 1.60, 4.50)], ["cabin roof", Vector3(0.0, 0.85, 0.20)],
			["left wing mid", Vector3(-2.7, 0.72, 0.40)], ["right wing mid", Vector3(2.7, 0.72, 0.40)],
			["left wing root", Vector3(-1.0, 0.72, 0.40)], ["right wing root", Vector3(1.0, 0.72, 0.40)],
			["left tailplane", Vector3(-1.5, 0.40, 4.30)], ["right tailplane", Vector3(1.5, 0.40, 4.30)],
		],
	},
	"biplane": {
		"name": "Meadowlark biplane", "price": 21000, "engines": 1, "cylinders": 7, "oil_capacity": 13.0,
		"empty_mass": 880.0, "empty_cg": Vector3(0.0, 0.05, -0.12), "empty_inertia": Vector3(1550.0, 2350.0, 1700.0),
		"max_mass": 1230.0, "rated_power": 164000.0, "prop_radius": 1.25, "rated_rpm": 2100.0,
		"fuel_capacity": 174.0, "crew_mass": 85.0, "cargo_front_max": 110.0, "cargo_rear_max": 25.0,
		"station_pilot": Vector3(0.0, -0.20, 1.30), "station_fuel": Vector3(0.0, 1.20, -0.35),
		"station_front": Vector3(0.0, -0.25, 0.15), "station_rear": Vector3(0.0, -0.10, 2.15),
		"cg_fwd": -0.10, "cg_aft": 0.25,
		"wing_area": 27.6, "wing_span": 9.8, "chord": 1.42, "cl0": 0.26, "cl_slope": 4.3, "stall_alpha": 0.26,
		"flap_dcl": 0.0, "cd0_wing": 0.014, "cm0": -0.03, "cm_flap": 0.0, "parasite_area": 0.78,
		"wing_y": 0.35, "wing_x": [-3.6, -1.35, 1.35, 3.6], "wing_panel_area": [6.1, 7.7, 7.7, 6.1], "dihedral": 2.3,
		"tail_pos": Vector3(0.0, 0.27, 4.75), "tail_area": 2.7, "tail_slope": 3.7, "tail_aspect": 3.6,
		"fin_pos": Vector3(0.0, 0.72, 5.05), "fin_area": 1.25, "fin_slope": 2.5,
		"side_pos": Vector3(0.0, 0.0, 1.0), "side_area": 5.2, "side_slope": 0.9,
		"props": [Vector3(0.0, 0.0, -2.30)], "drag_pos": Vector3(0.0, 0.10, 0.0),
		"hubs": [Vector3(-1.0, -1.40, -0.55), Vector3(1.0, -1.40, -0.55), Vector3(0.0, -0.32, 5.0)],
		"brake_force": 2300.0, "sit_pitch": 13.5, "approach_speed": 31.0, "vne": 160.0, "vfe": 160.0, "prop_inertia": 7.0, "gear_mass_pos": Vector3(0.0, -1.1, -0.55),
		"control_rate": 1.05, "tyres": "bi", "legs": "bi", "amphib": false,
		"eye": Vector3(0.0, 0.50, 1.30), "door": Vector3(-1.35, 0.0, 0.9), "visual": "res://scripts/biplane_visual.gd",
		"body": [
			["propeller", Vector3(0.0, -1.20, -2.30)], ["nose", Vector3(0.0, -0.45, -2.05)],
			["upper left wingtip", Vector3(-4.9, 1.30, -0.10)], ["upper right wingtip", Vector3(4.9, 1.30, -0.10)],
			["lower left wingtip", Vector3(-4.85, -0.27, 0.35)], ["lower right wingtip", Vector3(4.85, -0.27, 0.35)],
			["belly", Vector3(0.0, -0.66, 0.40)], ["tail", Vector3(0.0, -0.05, 4.95)],
			["fin", Vector3(0.0, 1.25, 5.15)], ["top wing", Vector3(0.0, 1.30, -0.20)],
			["left wing mid", Vector3(-2.6, -0.42, 0.30)], ["right wing mid", Vector3(2.6, -0.42, 0.30)],
			["left tailplane", Vector3(-1.5, 0.27, 4.85)], ["right tailplane", Vector3(1.5, 0.27, 4.85)],
		],
	},
}


static func spec(t: String) -> Dictionary:
	return TYPES.get(t, TYPES["wolverine"])
