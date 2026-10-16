extends Node
## Trailer shots (DESIGN_NOTES 125). main.gd adds this when run with
## `-- trailer=1 shot=<name>`; it sets the scene up, flies a free camera for
## the shot's length, puts a caption up, then quits. Run each shot under the
## Movie Maker (--write-movie dir/f.png --fixed-fps 24) and stitch them
## (tools/make_trailer.sh). Prints "TRAILER_REC <frame>" when the shot
## starts, so the loading frames before it can be dropped.

const FPS := 24.0

var m: Node                      # main
var _cap: Label
var _sub: Label
var _fade: ColorRect


func _ready() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 50
	add_child(cl)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(_fade)
	for k in range(2):
		var l := Label.new()
		l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 46 if k == 0 else 24)
		l.add_theme_color_override("font_color", Color(1, 0.97, 0.9))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 10 if k == 0 else 6)
		l.offset_top = -150.0 if k == 0 else -92.0
		l.offset_bottom = l.offset_top + 60.0
		l.modulate.a = 0.0
		cl.add_child(l)
		if k == 0:
			_cap = l
		else:
			_sub = l


func run(shots: String) -> void:
	var base := out_dir
	for shot in shots.split(","):
		if base != "":
			out_dir = base + "/" + shot
			DirAccess.make_dir_recursive_absolute(out_dir)
			_frame = 0
		var t0 := Time.get_ticks_msec()
		await _one(shot)
		print("TRAILER_DONE %s %d frames in %.0f s" % [shot, _frame, (Time.get_ticks_msec() - t0) / 1000.0])
	m.get_tree().quit()


func _one(shot: String) -> void:
	m.hud.visible = false
	_cap.modulate.a = 0.0
	_sub.modulate.a = 0.0
	match shot:
		"title":
			await _title()
		"fly":
			await _fly()
		"dc3":
			await _dc3()
		"trucks":
			await _trucks()
		"dig":
			await _dig()
		"fire":
			await _fire()
		"hose":
			await _hose()
		"winter":
			await _winter()
		"end":
			await _end()


# ------------------------------------------------------------------------------
#  Helpers
# ------------------------------------------------------------------------------
func _cam(eye: Vector3, tgt: Vector3, fov: float = 55.0) -> void:
	var xf := Transform3D.IDENTITY.looking_at((tgt - eye).normalized(), Vector3.UP)
	xf.origin = eye
	m._eco_xf = xf
	m._eco_on = true
	m.cam.global_transform = xf
	m.cam.fov = fov


func _ground(x: float, z: float) -> float:
	return m.world.terrain.height_at(x, z)


func _settle(frames: int = 12) -> void:
	var t0 := Time.get_ticks_msec()
	for i in range(frames):
		await m.get_tree().process_frame
	var veg = m.world.vegetation
	var n := 0
	if veg != null:
		for i in range(240):
			await m.get_tree().process_frame
			n = i
			if veg.is_idle() and i > 4:
				break
	print("TRAILER_SETTLE %d frames, %.1f s a frame" % [frames + n, (Time.get_ticks_msec() - t0) / 1000.0 / float(frames + n + 1)])


func _rec() -> void:
	print("TRAILER_REC %d" % Engine.get_frames_drawn())


## Caption: fades in over 0.4 s, holds, fades out by the end of `secs`.
func _caption(t: float, secs: float, a: String, b: String = "") -> void:
	_cap.text = a
	_sub.text = b
	var al := clampf(t / 0.5, 0.0, 1.0) * clampf((secs - t) / 0.5, 0.0, 1.0)
	_cap.modulate.a = al
	_sub.modulate.a = al


var out_dir := ""
var _frame := 0


## Run `secs` of shot, calling step(t) each frame (t seconds into it), and
## save each frame as a PNG in out_dir (run with --fixed-fps 24 so every
## frame is exactly 1/24 s of game time however long it takes to draw).
func _roll(secs: float, step: Callable, cap: String = "", sub: String = "") -> void:
	var n := int(secs * FPS)
	for i in range(n):
		var t := float(i) / FPS
		step.call(t)
		if cap != "":
			_caption(t, secs, cap, sub)
		_fade.color.a = clampf(1.0 - t / 0.3, 0.0, 1.0) if i < 8 else clampf((t - (secs - 0.3)) / 0.3, 0.0, 1.0)
		await RenderingServer.frame_post_draw
		if out_dir != "":
			m.get_viewport().get_texture().get_image().save_png("%s/f%04d.png" % [out_dir, _frame])
			_frame += 1


func _time(h: float, season: int = 0) -> void:
	Game.time_of_day = h
	Game.season = season
	Game.weather = 0
	Game.notify_changed()


func _plane_in_air(p: Vector3, heading_deg: float, speed: float) -> void:
	var pl = m.plane
	pl.frozen = false
	pl.place_in_air(p, heading_deg, speed)
	pl.throttle = 0.7
	pl.engine.rpm = maxf(float(pl.engine.rpm), 2000.0)


# ------------------------------------------------------------------------------
#  Shots
# ------------------------------------------------------------------------------
func _title() -> void:
	_time(7.2)
	await _settle()
	var c := Vector3(0, 0, -130)
	_rec()
	await _roll(3.5, func(t: float) -> void:
		var eye := Vector3(-260.0 + t * 22.0, 95.0 - t * 4.0, 120.0 - t * 30.0)
		_cam(eye, Vector3(c.x, _ground(c.x, c.z), c.z), 50.0),
		"BUSH PILOT 2", "fly it, drive it, dig it")


func _fly() -> void:
	_time(10.0)
	var p := Vector3(-300, 0, -60)
	p.y = _ground(p.x, p.z) + 120.0
	_plane_in_air(p, 90.0, 52.0)
	m.plane.frozen = true
	await _settle()
	m.plane.frozen = false
	_rec()
	await _roll(4.0, func(t: float) -> void:
		var pl = m.plane
		var b: Basis = pl.global_transform.basis
		var ang := 0.9 - t * 0.28
		var off := Vector3(sin(ang) * 14.0, 2.5 + t * 0.3, cos(ang) * 14.0)
		_cam(pl.global_position + b * off, pl.global_position + b * Vector3(0, 0.5, -1.0), 50.0),
		"Fly the bush", "short strips, gravel bars and lakes")


func _dc3() -> void:
	_time(18.6)
	m.plane.apply_type("dc3")
	m._apply_plane_type()
	var p := Vector3(-260, 0, 80)
	p.y = _ground(p.x, p.z) + 150.0
	_plane_in_air(p, 70.0, 68.0)
	m.plane.frozen = true
	await _settle()
	m.plane.frozen = false
	_rec()
	await _roll(4.0, func(t: float) -> void:
		var pl = m.plane
		var b: Basis = pl.global_transform.basis
		var ang := -1.25 + t * 0.12
		var off := Vector3(sin(ang) * 34.0, 4.0, cos(ang) * 34.0)
		_cam(pl.global_position + b * off, pl.global_position, 45.0),
		"Haul freight in the DC-3", "two engines, eleven paint schemes")


func _trucks() -> void:
	_time(16.5)
	var list: Array = []
	for v in [m.pickup, m.water_truck, m.fuel_truck, m.loader]:
		if v != null:
			list.append(v)
	if m.prospect.dozers.is_empty():
		var dp := Vector3(-10, 0, -70)
		m.prospect._spawn_dozer(Transform3D(Basis(Vector3.UP, 0.6), Vector3(dp.x, _ground(dp.x, dp.z), dp.z)))
	list.append(m.prospect.dozers[0])
	await _settle()
	_rec()
	var each := 1.5
	await _roll(each * list.size(), func(t: float) -> void:
		var k := mini(int(t / each), list.size() - 1)
		var v: Node3D = list[k]
		var lt := t - float(k) * each
		var big: float = 1.0 if v == m.pickup else 1.6
		var ang := float(k) * 1.3 + 0.6 + lt * 0.22
		var c := v.global_position + Vector3(0, 1.2 * big, 0)
		_cam(c + Vector3(sin(ang) * 8.5 * big, 1.6 * big, cos(ang) * 8.5 * big), c, 50.0),
		"Every machine works", "pickup, water truck, fuel truck, loader, dozer")


func _dig() -> void:
	_time(11.0)
	m._get_out()
	var wk = m.walker
	wk.first_person = false
	var p := Vector3(40, 0, 30)
	p.y = _ground(p.x, p.z)
	wk.place(p, 0.4)
	if not m.inv.holding("shovel"):
		m.inv.add("shovel", 1, true)
	await _settle()
	_rec()
	var st := {"next": 0.0}          # (lambdas capture by value: keep state in a dict)
	await _roll(3.5, func(t: float) -> void:
		if t >= float(st["next"]):
			st["next"] = t + 1.7
			var front: Vector3 = wk.global_transform * Vector3(0, 0, -0.9)
			if wk.model != null and wk.model.has_method("work_motion"):
				wk.model.work_motion("dig")
			m.prospect.dig(front, 0.7, 0.12)
		var ang := 2.3 + t * 0.12
		var c: Vector3 = wk.global_position + Vector3(0, 0.9, 0)
		_cam(c + Vector3(sin(ang) * 4.2, 1.2, cos(ang) * 4.2), c + Vector3(0, -0.2, 0), 55.0),
		"Dig for gold", "pan it, sluice it, tunnel after it")


func _fire() -> void:
	_time(15.0)
	m.wind.base_speed = 7.0
	m.wind.base_dir = Vector3(1, 0, 0)
	var fp := Vector3(20, 0, 0)
	fp.y = _ground(fp.x, fp.z)
	m.fire.ignite(fp, 4.0)
	for i in range(60):
		m.fire._tick(0.25)
	await _settle()
	_rec()
	await _roll(4.0, func(t: float) -> void:
		m.fire._tick(0.25)
		m.fire._tick(0.25)
		var eye := fp + Vector3(-40.0 + t * 3.0, 14.0 + t * 3.5, 48.0 - t * 2.0)
		_cam(eye, fp + Vector3(18.0, 2.0, 0.0), 55.0),
		"Fire spreads with the wind", "dry summers, wet springs, frozen winters")


func _hose() -> void:
	_time(16.0)
	var W = m.water_truck
	var fp := Vector3(20, 0, 0)
	fp.y = _ground(fp.x, fp.z)
	# the truck on the open ground short of the fire, the reel side toward it
	var tp := fp + Vector3(-24, 0, 6)
	W.park(Transform3D(Basis(Vector3.UP, -PI * 0.5), tp))
	W.engine_on = true
	m.fire.ignite(fp, 4.0)
	for i in range(40):
		m.fire._tick(0.25)
	m._get_out()
	var wk = m.walker
	wk.first_person = false
	var rp: Vector3 = W.global_transform * W.REEL
	W.foot_act("truck_hose", rp)
	W.foot_act("truck_nozzle", rp)
	var stand := fp + Vector3(-11, 0, 1)
	stand.y = _ground(stand.x, stand.z)
	wk.place(stand, -PI * 0.5)
	await _settle()
	_rec()
	await _roll(4.0, func(t: float) -> void:
		wk.place(stand, atan2(-(fp.x - stand.x), -(fp.z - stand.z)))
		var c: Vector3 = wk.global_position + Vector3(0, 1.4, 0)
		var sway := sin(t * 0.9) * 3.0
		_cam(c + Vector3(-3.2, 0.9, 2.4), fp + Vector3(0, 1.0, sway), 58.0),
		"Put it out", "the water truck's hose, 50 ft off the reel")


func _winter() -> void:
	_time(12.5, Game.WINTER)
	var fp := Vector3(20, 0, 0)
	fp.y = m.world.terrain.ground_level_at(fp.x, fp.z)
	m.fire.ignite(fp, 4.0)
	for i in range(400):
		m.fire._tick(0.25)
	m.fire._update_melt_tex()
	await _settle()
	_rec()
	await _roll(3.5, func(t: float) -> void:
		m.fire._tick(0.25)
		var ang := 2.4 + t * 0.08
		_cam(fp + Vector3(sin(ang) * 40.0, 24.0 - t, cos(ang) * 40.0), fp, 55.0),
		"Four seasons", "even in winter, a fire melts its way through")


func _end() -> void:
	_time(19.3)
	m.plane.apply_type("dc3")
	m._apply_plane_type()
	var cam_at := Vector3(-120, 0, -130)
	cam_at.y = _ground(cam_at.x, cam_at.z) + 3.0
	var p := cam_at + Vector3(-260, 70, 30)
	_plane_in_air(p, 90.0, 66.0)
	m.plane.frozen = true
	await _settle()
	m.plane.frozen = false
	_rec()
	await _roll(3.5, func(t: float) -> void:
		_cam(cam_at, m.plane.global_position, 40.0),
		"BUSH PILOT 2", "in development")
