extends SceneTree
## Tracked body physics on simple ground: straight run, pivot turn, a climb,
## a side-slope tip test.
const TB = preload("res://scripts/tracked_body.gd")

func mk(ground: Callable) -> RefCounted:
	var b := TB.new()
	b.mass = 9000.0
	b.length = 2.7
	b.width = 1.95
	b.height = 2.4
	b.com = Vector3(0, 0.8, -0.15)
	b.top_speed = 1.8
	b.ground_y = ground
	b.setup()
	var e := 0.5
	var n := Vector3(ground.call(-e, 0.0) - ground.call(e, 0.0), 2.0 * e, ground.call(0.0, -e) - ground.call(0.0, e)).normalized()
	var fw := (Vector3.FORWARD - n * Vector3.FORWARD.dot(n)).normalized()
	var rt := fw.cross(n).normalized()
	b.place(Transform3D(Basis(rt, n, -fw), Vector3(0, ground.call(0.0, 0.0) + 0.05, 0)))
	b.settle()
	return b

func run(b: RefCounted, secs: float, l: float, r: float) -> void:
	for i in range(int(secs * 120.0)):
		b.step(1.0 / 120.0, l, r)

func _init() -> void:
	var flat := func(x: float, z: float) -> float: return 0.0
	var b := mk(flat)
	print("settled: y %.3f tilt %.1f contacts %d" % [b.pos.y, b.tilt_deg, b.on_ground])
	run(b, 5.0, 1.0, 1.0)
	print("straight 5 s: moved %.2f m (top %.1f m/s), drift x %.2f, y %.3f" % [-b.pos.z, b.top_speed, b.pos.x, b.pos.y])
	var y0: float = b.yaw()
	run(b, 4.0, 1.0, -1.0)
	print("pivot 4 s: turned %.0f deg, slid %.2f m" % [rad_to_deg(wrapf(b.yaw() - y0, -PI, PI)), Vector2(b.vel.x, b.vel.z).length()])
	for g in [0.3, 0.5, 0.7]:
		var slope := func(x: float, z: float) -> float: return -z * g
		var c := mk(slope)
		run(c, 8.0, 1.0, 1.0)
		print("climb %d%% grade 8 s: made %.2f m up the hill, tilt %.0f" % [int(g * 100), -c.pos.z, c.tilt_deg])
	for g2 in [0.6, 0.9, 1.3]:
		var side := func(x: float, z: float) -> float: return x * g2
		var d := mk(side)
		run(d, 6.0, 0.6, 0.6)
		print("side-slope %.0f deg: tilt %.0f after driving across (over: %s)" % [rad_to_deg(atan(g2)), d.tilt_deg, d.tilt_deg > 75.0])
	quit()
