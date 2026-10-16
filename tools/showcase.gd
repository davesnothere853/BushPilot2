extends Node
## Lab tool: the vehicle showcase (Dave: "every new vehicle, a quick range of
## motion and a cold start"). One after another: the camera swings round it,
## a cold start (the starter, coughs, catch, idle), then everything that moves
## - doors, hood, tailgate, lights, blinkers, steering, suspension; the
## loader's arms and bucket, the dozer's blade, the excavator's swing, boom,
## stick and bucket; the plane's prop, flaps and controls.
## Test bed button "SHOWCASE", or "run res://tools/showcase.gd".

const ORDER := ["pickup", "blazer", "suburban", "water_truck", "fuel_truck", "loader", "dozer", "excavator", "tug", "forklift", "plane"]
const PER := 11.0                    # seconds each
var status := "showcase"
var lab: Node
var _i := -1
var _t := 0.0
var _done: Dictionary = {}


func _ready() -> void:
	lab = get_parent()
	_next()


func _next() -> void:
	_i += 1
	if _i >= ORDER.size():
		status = "showcase done"
		queue_free()
		return
	_t = 0.0
	_done.clear()
	lab.call("_run_cmd", ORDER[_i])
	status = "showcase: %s (%d of %d)" % [ORDER[_i], _i + 1, ORDER.size()]


func _veh() -> Node:
	var bed = lab.get("_bed")
	if bed == null:
		return null
	var v = bed.get("veh")
	return v if v != null and is_instance_valid(v) else null


func _bed(cmd: String) -> void:
	var bed = lab.get("_bed")
	if bed != null and bed.has_method("command"):
		bed.command(cmd)


## Do something once at time `at` in this vehicle's slot.
func _at(at: float, key: String) -> bool:
	if _t >= at and not _done.has(key):
		_done[key] = true
		return true
	return false


func _process(dt: float) -> void:
	_t += dt
	var v := _veh()
	var kind: String = ORDER[_i]
	# the camera swings round from the front quarter, a little lower as it goes
	var span := 6.0 if kind in ["tug", "forklift"] else (13.0 if kind == "plane" else (11.0 if kind in ["water_truck", "fuel_truck", "excavator", "loader"] else 8.5))
	if _t > 1.2:
		lab.call("orbit", -0.9 + (_t - 1.2) / PER * 3.6, -0.16 + 0.05 * sin(_t * 0.6), span)
	if v == null:
		if _t > PER:
			_next()
		return
	# the cold start
	if _at(1.6, "start"):
		var eng = v.get("engine")
		if eng != null and eng is Node and eng.has_method("start"):
			if "temp" in eng:
				eng.temp = -15.0
			eng.start()
		elif v.has_method("engine_toggle"):
			v.engine_toggle()
		elif v.has_method("prop_toggle"):
			v.prop_toggle()
	# trucks and the plane: doors, hood, tailgate, lights, blinker
	if v.has_method("door_toggle"):
		if _at(4.0, "dl"): _bed("door_l")
		if _at(4.6, "dr"): _bed("door_r")
		if _at(6.2, "dc"): _bed("doors")
	if v.has_method("hood_toggle"):
		if _at(5.2, "h"): _bed("hood")
		if _at(7.0, "h2"): _bed("hood")
	if v.has_method("tailgate_toggle"):
		if _at(5.6, "g"): _bed("gate")
		if _at(7.4, "g2"): _bed("gate")
	if v.has_method("lights_toggle") and _at(3.4, "l"): _bed("lights")
	if v.has_method("blinker") and kind != "plane" and _at(3.6, "b"): _bed("blink")
	# wheels: a steering sweep and the suspension working
	if kind in ["pickup", "blazer", "suburban", "water_truck", "fuel_truck", "loader", "tug", "forklift"]:
		if _at(7.8, "st"): _bed("steer")
		if _at(9.0, "st2"): _bed("steer")
		if _at(9.0, "bo"): _bed("bounce")
		if _at(10.6, "bo2"): _bed("bounce")
	# the machines' arms and blades
	match kind:
		"loader":
			if "lift" in v:
				var k := clampf((_t - 3.5) / 6.0, 0.0, 1.0)
				v.lift = sin(k * PI)
				v.tilt = sin(k * TAU) * 0.6
				if v.has_method("_pose"):
					v._pose()
		"dozer":
			if _at(3.5, "bl"): v.blade_toggle()
			if _at(6.5, "bl2"): v.blade_toggle()
		"excavator":
			if "swing" in v:
				var k2 := clampf((_t - 3.0) / 7.5, 0.0, 1.0)
				v.swing = sin(k2 * TAU) * 0.9
				v.boom_a = 0.4 - sin(k2 * PI) * 0.7
				v.knee = 1.2 + sin(k2 * TAU) * 0.8
				v.bucket_a = sin(k2 * TAU * 1.5) * 1.0
				if v.has_method("_apply_pose"):
					v._apply_pose()
		"plane":
			if _at(4.0, "dr"): _bed("door_r")
			if _at(5.0, "fl"): _bed("flaps")
			if _at(6.0, "ctl"): _bed("ctl")
			if _at(8.5, "fl2"): _bed("flaps")
			if _at(9.0, "dr2"): _bed("door_r")
	if _t > PER:
		_bed("stop")
		_next()
