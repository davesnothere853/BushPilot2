extends RefCounted
## Gold-bearing quartz veins in the bedrock (DESIGN_NOTES 139).
##
## A handful of steep sheets of milky quartz, laid out from the world seed:
## most cut across the rock knoll (where the bedrock is thin, so they show as
## white float in the moss and outcrop a spade's depth down), one or two
## blind ones out in the flats that only a drift or a deep pit finds.
## Each: strike, dip, thickness (wobbling), length (tapering at the ends), a
## gentle meander, and gold in shoots along it - rich patches with lean
## quartz between. The same formula runs in voxel_ground.gdshader (the vein
## data goes there as the global texture bp_veins), so the white seam you see
## is exactly where the pick finds quartz.

const Ground = preload("res://scripts/ground.gd")
const MAX := 8
const QUARTZ_T_M3 := 2.65         # tonnes a cubic metre

## [ox, oz, strike, thickness, dip, half_length, grade g/t]
static var list: Array = []
static var _seed := -1
static var _tex: ImageTexture


static func make(seed_v: int) -> void:
	if seed_v == _seed and not list.is_empty():
		return
	_seed = seed_v
	list = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 7919 + 31
	var lay_: Dictionary = Ground.lay()
	var kn: Array = lay_["knoll"]
	var kc: Vector2 = kn[0]
	var kr := float(kn[1])
	var on_knoll := rng.randi_range(3, 4)
	for i in range(on_knoll + 2):
		var o: Vector2
		if i < on_knoll:
			o = kc + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, kr * 0.55)
		else:
			o = Vector2(rng.randf_range(-150.0, 150.0), rng.randf_range(-150.0, 150.0))
		list.append([o.x, o.y, rng.randf() * PI, rng.randf_range(0.35, 1.0), deg_to_rad(rng.randf_range(65.0, 88.0)),
			rng.randf_range(25.0, 60.0), rng.randf_range(8.0, 40.0) * (1.4 if i >= on_knoll else 1.0)])
	_tex = null


## The veins as a texture for the ground shader: column i, row 0 = (ox, oz,
## strike, thickness), row 1 = (dip, half length, grade, 0).
static func texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var img := Image.create(MAX, 2, false, Image.FORMAT_RGBAF)
	for i in range(mini(list.size(), MAX)):
		var v: Array = list[i]
		img.set_pixel(i, 0, Color(float(v[0]), float(v[1]), float(v[2]), float(v[3])))
		img.set_pixel(i, 1, Color(float(v[4]), float(v[5]), float(v[6]), 0.0))
	_tex = ImageTexture.create_from_image(img)
	return _tex


## The vein at world point p, given the natural surface height there:
## {"i": vein, "g": grade g/t at this spot, "edge": 0 middle .. 1 the wall}, or {}.
## Mirrors vein_at() in voxel_ground.gdshader - change both together.
static func at(p: Vector3, natural_y: float) -> Dictionary:
	var depth := maxf(natural_y - p.y, 0.0)
	for i in range(list.size()):
		var v: Array = list[i]
		var a := float(v[2])
		var rx := p.x - float(v[0])
		var rz := p.z - float(v[1])
		var along := rx * cos(a) + rz * sin(a)
		var across := -rx * sin(a) + rz * cos(a)
		var hl := float(v[5])
		if absf(along) > hl:
			continue
		var fi := float(i)
		var d := across - depth / tan(float(v[4])) + 0.25 * sin(along * 0.13 + fi * 2.3)
		var taper := 1.0 - smoothstep(hl * 0.7, hl, absf(along))
		var halfw := float(v[3]) * 0.5 * (0.7 + 0.3 * sin(along * 0.37 + fi * 1.7)) * taper
		if absf(d) < halfw:
			var shoot := maxf(sin(along * 0.09 + fi * 0.7 + depth * 0.05), 0.0)
			return {"i": i, "g": float(v[6]) * (0.15 + 0.85 * shoot * shoot), "edge": absf(d) / maxf(halfw, 0.01)}
	return {}
