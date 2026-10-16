extends RefCounted
## The hydraulic system, simulated (Dave: "real working cylinders, pump,
## lines... all simulation pressures"). An engine-driven gear pump pushes oil
## through the control valve to the rams; every frame:
##   flow   Q = pump displacement x engine rpm (less slip as the pressure climbs)
##   each open spool takes a share of the flow (more open, more share)
##   a ram's pressure p = load force / the area it's pushing on
##        (the full bore extending, the ring round the rod retracting)
##   its speed v = its flow / that area - unless the pressure it needs is over
##        the relief valve's setting: then it stalls, the relief blows off and
##        the oil heats up
##   the pump's pressure is the highest any working ram needs, plus the losses
##        in the lines (they grow with the flow through them)
## Units: bar, L/min, mm for bores, m/s, N.

class Ram:
	var name := ""
	var bore := 0.12                # m
	var rod := 0.08
	var spool := 0.0                # -1 .. 1 (retract .. extend)
	var force := 0.0                # N, + resists extending (gravity on the boom...)
	var p_cap := 0.0                # bar on the bore side
	var p_rod := 0.0                # bar on the rod side
	var flow := 0.0                 # L/min into it
	var speed := 0.0                # m/s, + extending
	var stalled := false
	var leak := 0.0                 # 0 sound .. 1 a burst line (Dave: a damaged line bleeds and the load sinks)
	var leak_flow := 0.0            # L/min going out of the crack now

	## Oil out of the crack at a pressure (an orifice: grows with the root of it).
	func leak_at(p_bar: float) -> float:
		return leak * 14.0 * sqrt(maxf(p_bar, 0.0))

	func area_cap() -> float:
		return PI * bore * bore * 0.25

	func area_rod() -> float:
		return area_cap() - PI * rod * rod * 0.25


var rams: Array = []                # [Ram]
var displacement := 0.09            # L per rev (a 20 t excavator's pump, ~180 L/min at 2000 rpm)
var rpm := 2000.0
var relief := 330.0                 # bar
var pressure := 0.0                 # bar at the pump
var flow := 0.0                     # L/min out of the pump
var oil_temp := 45.0                # C
var line_k := 0.0009                # bar per (L/min)^2: pipe and valve losses
var _blow := 0.0                    # how much is going over the relief
var power_avail := 0.0              # W the engine can give the pump right now (0 = unlimited); set each frame from the engine


func add_ram(nm: String, bore_mm: float, rod_mm: float) -> Ram:
	var r := Ram.new()
	r.name = nm
	r.bore = bore_mm / 1000.0
	r.rod = rod_mm / 1000.0
	rams.append(r)
	return r


## One step: spools and loads are set on the rams first; this works out the
## flows, pressures and speeds.
func step(dt: float) -> void:
	var slip := clampf(pressure / relief, 0.0, 1.0) * 0.08          # a worn gear pump leaks more at high pressure
	flow = displacement * rpm * (1.0 - slip)
	var open := 0.0
	for r in rams:
		open += absf((r as Ram).spool)
	_blow = 0.0
	var top := 0.0
	for r2 in rams:
		var ram := r2 as Ram
		var s := ram.spool
		if absf(s) < 0.02:
			ram.flow = 0.0
			ram.speed = 0.0
			ram.stalled = false
			# held: the load sits on the trapped oil
			var hold_a := ram.area_cap() if ram.force >= 0.0 else ram.area_rod()
			var ph := minf(absf(ram.force) / hold_a / 1.0e5, relief)      # held oil can't go over the relief (port reliefs blow off)
			if ram.force >= 0.0:
				ram.p_cap = ph
				ram.p_rod = 0.0
			else:
				ram.p_rod = ph
				ram.p_cap = 0.0
			ram.leak_flow = ram.leak_at(ph)
			if ram.leak > 0.0 and ph > 2.0:
				# the trapped oil bleeds out of the crack: the load sinks with it
				ram.speed = -signf(ram.force) * (ram.leak_flow / 60000.0) / hold_a
			continue
		var share := flow * absf(s) / maxf(open, 1.0)
		var a := ram.area_cap() if s > 0.0 else ram.area_rod()
		# the pressure needed: the load against the motion (a load that helps,
		# like the boom coming down, still needs a little to push the oil out)
		var f_against := ram.force * signf(s)
		var p_need := maxf(f_against / a / 1.0e5, 8.0) + line_k * share * share
		ram.leak_flow = ram.leak_at(p_need)
		if ram.leak > 0.0:
			var p_max := pow(share / (ram.leak * 14.0), 2.0)        # where all the pump's oil goes out the crack
			if p_max < p_need:
				# it can't build the pressure the load needs: the load comes down
				ram.flow = 0.0
				ram.leak_flow = share
				var sink := (ram.leak_at(p_need) - share) / 60000.0 / a
				ram.speed = -signf(ram.force) * maxf(sink, 0.0) if f_against > 0.0 else signf(s) * (share / 60000.0) / a
				ram.stalled = f_against > 0.0
				if s > 0.0:
					ram.p_cap = p_max
					ram.p_rod = 3.0
				else:
					ram.p_rod = p_max
					ram.p_cap = 3.0
				top = maxf(top, p_max)
				continue
			share -= ram.leak_flow
		ram.stalled = p_need > relief
		if ram.stalled:
			ram.flow = 0.0
			ram.speed = 0.0
			_blow += share
			p_need = relief
		else:
			ram.flow = share
			ram.speed = signf(s) * (share / 60000.0) / a
		if s > 0.0:
			ram.p_cap = p_need
			ram.p_rod = 3.0
		else:
			ram.p_rod = p_need
			ram.p_cap = 3.0
		top = maxf(top, p_need)
	# the engine can only turn the pump so hard (Dave: throttle up to lift): oil
	# x pressure can't be more than its power at these revs - at idle a loaded
	# lift just crawls
	if power_avail > 0.0:
		var need_w := 0.0
		for r3 in rams:
			var rm := r3 as Ram
			if rm.flow > 0.0:
				need_w += maxf(rm.p_cap, rm.p_rod) * 1.0e5 * rm.flow / 60000.0
		if need_w > power_avail:
			var k := power_avail / need_w
			for r4 in rams:
				var rn := r4 as Ram
				rn.flow *= k
				rn.speed *= k
	pressure = lerpf(pressure, maxf(top, 6.0 + line_k * flow * flow * 0.2), clampf(dt * 12.0, 0.0, 1.0))
	# heat: oil over the relief turns straight to heat; cooler pulls it back
	oil_temp += dt * (_blow * pressure * 0.00004 - (oil_temp - 45.0) * 0.01)


## How hard the work is going (for the engine's governor): 0 while every open
## ram moves easily, rising as one nears the relief, 1 when one has stalled.
func strain() -> float:
	var st := 0.0
	for r in rams:
		var ram := r as Ram
		if absf(ram.spool) < 0.02:
			continue
		if ram.stalled:
			return 1.0
		st = maxf(st, clampf((maxf(ram.p_cap, ram.p_rod) / relief - 0.55) / 0.4, 0.0, 1.0))
	return st


func psi(bar: float) -> float:
	return bar * 14.5038


func summary() -> String:
	return "PUMP %d rpm  %d L/min  %d bar (%d psi)  oil %d C%s" % [int(rpm), int(flow), int(pressure), int(psi(pressure)), int(oil_temp), "  RELIEF!" if _blow > 1.0 else ""]


## Drive a machine's joints through the hydraulics (shared by every machine).
## Each joint: {ram: Ram, get: Callable() -> float, set: Callable(float),
## length: Callable() -> float (pin to pin, live), lo: float, hi: float,
## label: Label3D or null, at: Callable() -> Vector3 (where its label sits)}.
## potential: Callable() -> float, the moving parts' weight x height (J);
## pose: Callable() re-lays the parts after a joint is moved.
var depth: Callable                # func() -> float: how far a part is into another (or the ground); 0 = clear


func drive(dt: float, joints: Array, potential: Callable, pose: Callable) -> void:
	var rates := []
	for jt in joints:
		var r: Ram = jt["ram"]
		var v0: float = jt["get"].call()
		var eps := 0.01
		var L0: float = jt["length"].call()
		var U0: float = potential.call()
		jt["set"].call(v0 + eps)
		pose.call()
		var L1: float = jt["length"].call()
		var U1: float = potential.call()
		jt["set"].call(v0)
		pose.call()
		var dL := (L1 - L0) / eps
		if absf(dL) < 0.0005:
			dL = 0.0005 if dL >= 0.0 else -0.0005
		var force := ((U1 - U0) / eps) / dL
		var going_up := r.spool * signf(dL) > 0.0
		if absf(r.spool) > 0.02 and ((going_up and v0 >= float(jt["hi"]) - 0.003) or (not going_up and v0 <= float(jt["lo"]) + 0.003)):
			force = 1.0e7 * signf(r.spool)            # against the end of its stroke
		r.force = force
		rates.append(dL)
	step(dt)
	for i in range(joints.size()):
		var jt2: Dictionary = joints[i]
		var r2: Ram = jt2["ram"]
		var old: float = jt2["get"].call()
		var nv := clampf(old + r2.speed / float(rates[i]) * dt, float(jt2["lo"]), float(jt2["hi"]))
		var before: float = float(depth.call()) if depth.is_valid() else 0.0
		jt2["set"].call(nv)
		# never through itself or the ground (Dave): a move that goes in deeper is
		# refused, and the ram feels it - it stalls up against the relief
		if depth.is_valid():
			pose.call()
			if float(depth.call()) > before + 0.0001:
				jt2["set"].call(old)
				pose.call()
				r2.stalled = true
				r2.speed = 0.0
				if r2.spool > 0.0:
					r2.p_cap = relief
				else:
					r2.p_rod = relief
	pose.call()
	for jt3 in joints:
		var l = jt3.get("label")
		if l == null:
			continue
		var r3: Ram = jt3["ram"]
		var p := maxf(r3.p_cap, r3.p_rod)
		(l as Label3D).text = "%s  %d bar\n%d L/min%s" % [r3.name, int(p), int(r3.flow), "  STALL" if r3.stalled else ""]
		(l as Label3D).modulate = Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.2, 0.1), clampf(p / relief, 0.0, 1.0))
		if jt3.has("at"):
			(l as Label3D).global_position = jt3["at"].call()


static func make_label(parent: Node) -> Label3D:
	var l := Label3D.new()
	l.font_size = 40
	l.pixel_size = 0.004
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 8
	parent.add_child(l)
	return l
