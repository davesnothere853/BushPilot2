extends Node
## A guided first flight and first job. Started from the menu (How to play →
## Tutorial). One step at a time: a line of instructions stays on screen until
## you have done it, then the next one comes up. Esc → How to play stops it.

var main: Node              # main.gd
var plane: Node3D
var jobs: Node
var hud: Control
var active := false
var step := 0
var _t := 0.0
var _start_completed := 0

## [instruction (with {key} hints), done test]
var _steps: Array = []


func start() -> void:
	active = true
	step = 0
	_t = 0.0
	_start_completed = int(jobs.completed)
	_steps = [
		["Welcome to Bush Pilot. You're at Proving Ground in a Wolverine 180. First, take a job: press {jobs} for the job board.",
			func() -> bool: return not jobs.carried.is_empty()],
		["Now the engine: if it isn't running, press {engine_auto} for a guided start (or work the switches yourself in the cockpit).",
			func() -> bool: return bool(plane.engine_running)],
		["Engine running. Press {camera} to switch between the cockpit and the chase view whenever you like. Now: brakes off and full throttle, hold {throttle_up}.",
			func() -> bool: return plane.throttle > 0.9 and plane.ground_speed > 3.0],
		["Keep it straight with the rudder ({yaw_left} / {yaw_right}). At about 55 knots, ease back on the stick ({pitch_up}) to lift off.",
			func() -> bool: return plane.airborne and plane.agl > 30.0],
		["You're flying! Climb to 1,000 ft. The orange marker shows your destination; {next_target} picks another, {map} opens the chart.",
			func() -> bool: return plane.altitude_ft() - _strip_alt_ft() > 900.0],
		["Level off: lower the nose and bring the throttle back to about 70% ({throttle_down}). Use trim ({trim_up} / {trim_down}) so the plane holds its attitude by itself.",
			func() -> bool: return _t > 25.0],
		["Fly to the strip the job is going to (it's on the HUD at the top left). To land: slow to about 65 knots, flaps down ({flaps_down}), and aim for the start of the runway.",
			func() -> bool: return plane.on_ground and jobs.strip_here() >= 0 and jobs.strip_here() != Game.last_strip],
		["Down safely. Stop, then open the job board ({jobs}) and unload the job for your pay.",
			func() -> bool: return int(jobs.completed) > _start_completed],
		["That's the job done. From here: take more work, buy fuel (Esc → Load and fuel), get out and walk ({get_out}), build ({build} on foot), or fly to a hangar for a bigger plane. Have fun out there!",
			func() -> bool: return _t > 14.0],
	]


func stop() -> void:
	active = false
	if hud != null:
		hud.tutorial_text = ""


func _strip_alt_ft() -> float:
	var k: int = clampi(Game.last_strip, 0, plane.terrain.strips.size() - 1)
	return float(plane.terrain.strips[k]["pos"].y) * 3.28084


func _process(delta: float) -> void:
	if not active or hud == null:
		return
	_t += delta
	if step >= _steps.size():
		stop()
		return
	var s: Array = _steps[step]
	hud.tutorial_text = "TUTORIAL %d/%d   %s" % [step + 1, _steps.size(), _fill(String(s[0]))]
	if _t > 1.5 and bool((s[1] as Callable).call()):
		step += 1
		_t = 0.0


func _fill(text: String) -> String:
	var out := text
	var i := out.find("{")
	while i >= 0:
		var j := out.find("}", i)
		if j < 0:
			break
		var action := out.substr(i + 1, j - i - 1)
		out = out.substr(0, i) + Game.hint(action) + out.substr(j + 1)
		i = out.find("{")
	return out
