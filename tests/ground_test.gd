extends SceneTree
## Headless proof of the unified deformable ground:
##   godot --headless --path . -s tests/ground_test.gd

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var Ground = load("res://scripts/ground.gd")
	var g: RefCounted = Ground.new()
	print("built grid in ", Time.get_ticks_msec() - t0, " ms")
	var ok := true

	# Continuity across a chunk border (24 m lines).
	var h1: float = g.height_at(23.999, 10.0)
	var h2: float = g.height_at(24.001, 10.0)
	ok = _check(ok, absf(h1 - h2) < 0.02, "no seam at chunk border (%.4f vs %.4f)" % [h1, h2])

	# The runway is flat and gravel.
	var a: float = g.height_at(-100.0, -130.0)
	var b: float = g.height_at(100.0, -130.0)
	ok = _check(ok, absf((b - a) - 0.8) < 0.1, "runway slope ~0.4%% (%.2f m over 200 m)" % (b - a))
	ok = _check(ok, g.surface_at(0.0, -130.0) == 1, "runway surface is gravel")
	ok = _check(ok, g.strip_index_at(140.0, -133.0) == 0, "strip_index_at finds 09/27")

	# Void outside the square.
	ok = _check(ok, g.height_at(500.0, 0.0) < -50.0, "void beyond the edge")

	# Pond water, dry land elsewhere.
	ok = _check(ok, absf(g.water_level_at(-105.0, 105.0) - 3.2) < 0.01, "pond holds water at 3.2")
	ok = _check(ok, g.water_level_at(0.0, 0.0) < -1.0e8, "no water on the grass")

	# Dig in the pay zone: layers must come out and the hole must be there.
	var spot := Vector3(78.0, 0.0, 62.0)
	var before: float = g.height_at(spot.x, spot.z)
	var total := {"over": 0.0, "pay": 0.0, "g": 0.0}
	for k in range(40):
		var r: Dictionary = g.dig(spot, 1.6, 0.5)
		for kk in ["over", "pay", "g"]:
			total[kk] += r[kk]
	var after: float = g.height_at(spot.x, spot.z)
	print("  dug: over %.1f m3, pay %.1f m3, gold %.1f g, depth %.2f m" %
		[total["over"], total["pay"], total["g"], before - after])
	ok = _check(ok, before - after > 1.0, "digging makes a hole")
	ok = _check(ok, total["over"] > 1.0, "overburden came out first")
	ok = _check(ok, total["pay"] > 0.5, "pay gravel under it")
	ok = _check(ok, total["g"] > 0.1, "gold in the pay")
	ok = _check(ok, g.layer_at(spot.x, spot.z) != "turf", "surface reads dug layer: " + g.layer_at(spot.x, spot.z))
	ok = _check(ok, not g.dirty_chunks.is_empty(), "dirty chunks marked: %d" % g.dirty_chunks.size())

	# Bedrock stops the bucket.
	var hit_bed := false
	for k in range(400):
		var r2: Dictionary = g.dig(spot, 1.6, 0.5)
		if bool(r2["bedrock"]):
			hit_bed = true
			break
	ok = _check(ok, hit_bed, "bedrock stops the dig")

	# Deposit piles up.
	var pile := Vector3(60.0, 0.0, 48.0)
	var hb: float = g.height_at(pile.x, pile.z)
	for k in range(10):
		g.deposit(pile, 0.5)
	ok = _check(ok, g.height_at(pile.x, pile.z) - hb > 0.5, "deposit builds a heap (%.2f m)" % (g.height_at(pile.x, pile.z) - hb))

	# Level benches a slope (the knoll's west toe).
	var bc := Vector3(95.0, 0.0, -30.0)
	var tgt: float = g.height_at(bc.x, bc.z)
	for k in range(30):
		g.level(bc, 2.0, tgt, 2.0, 2.0)
	var s0: float = g.height_at(bc.x - 1.5, bc.z)
	var s1: float = g.height_at(bc.x + 1.5, bc.z)
	ok = _check(ok, absf(s1 - s0) / 3.0 < 0.08, "levelled bench is near flat (%.1f%%)" % (absf(s1 - s0) / 3.0 * 100.0))

	# Trees grow, and not on the strip.
	var Flora = load("res://scripts/flora.gd")
	var found := 0
	for j in range(0, 57):
		for i in range(0, 57):
			if not Flora.tree_at(g, i, j).is_empty():
				found += 1
	print("  trees on the square: ", found)
	ok = _check(ok, found > 300, "a real forest grows")
	var on_strip := false
	for i in range(100):
		var t: Dictionary = Flora.tree_at(g, i % 57, i / 10)
		if not t.is_empty() and g.strip_index_at((t["pos"] as Vector3).x, (t["pos"] as Vector3).z, 10.0) >= 0:
			on_strip = true
	ok = _check(ok, not on_strip, "no trees on the runway")

	# Save round-trip.
	var cf := ConfigFile.new()
	g.save_to(cf)
	var g2: RefCounted = Ground.new()
	g2.load_from(cf)
	ok = _check(ok, absf(g2.height_at(spot.x, spot.z) - g.height_at(spot.x, spot.z)) < 0.01, "save/load keeps the hole")

	print("GROUND TEST ", "ALL OK" if ok else "FAILURES ABOVE")
	quit()


func _check(ok: bool, cond: bool, what: String) -> bool:
	print(("  OK  " if cond else "  FAIL") + "  " + what)
	return ok and cond
