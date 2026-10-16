extends RefCounted
## Pictures painted in code for the plant cards: a spruce frond (a twig thick
## with needles and side shoots) and a sprig of leaves for birch, aspen and
## poplar. Cards with these on them, cut out where there is no needle or leaf,
## give trees their fine detail for very few triangles.
##
## The frond lies along the picture from the bottom (where it joins the trunk)
## to the top (the tip). Colours are greyish so the vertex colour and season
## tint decide the final shade.

static var _frond: ImageTexture
static var _leaves: ImageTexture
static var _rng := RandomNumberGenerator.new()


static func frond() -> ImageTexture:
	if _frond == null:
		_frond = ImageTexture.create_from_image(_paint_frond(128, 256))
	return _frond


static func leaves() -> ImageTexture:
	if _leaves == null:
		_leaves = ImageTexture.create_from_image(_paint_leaves(256, 256))
	return _leaves


static func _line(img: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var d := b - a
	var n := maxi(int(d.length() * 1.5), 1)
	var sz := img.get_size()
	var r := int(ceil(w))
	for k in range(n + 1):
		var p := a + d * (float(k) / float(n))
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				if float(ox * ox + oy * oy) > w * w:
					continue
				var x := int(p.x) + ox
				var y := int(p.y) + oy
				if x >= 0 and y >= 0 and x < sz.x and y < sz.y:
					img.set_pixel(x, y, col)


static func _paint_frond(w: int, h: int) -> Image:
	_rng.seed = 1988
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.42, 0.45, 0.40, 0.0))
	var cx := float(w) * 0.5
	var twig := Color(0.42, 0.33, 0.26, 1.0)
	# Side shoots, longer near the base, swept toward the tip.
	var shoots: Array = []
	for k in range(9):
		var t := 0.08 + 0.8 * float(k) / 9.0 + _rng.randf_range(-0.03, 0.03)
		var side := -1.0 if k % 2 == 0 else 1.0
		var y0 := float(h) * (1.0 - t)
		var length := float(w) * (0.48 - 0.32 * t) * _rng.randf_range(0.8, 1.05)
		var tip := Vector2(cx + side * length, y0 - length * 0.75)
		shoots.append([Vector2(cx, y0), tip])
	# Needles first (so the twigs read through), from base to tip of every stem.
	var stems: Array = shoots.duplicate()
	stems.append([Vector2(cx, float(h) - 2.0), Vector2(cx + _rng.randf_range(-4, 4), 4.0)])
	for st in stems:
		var a: Vector2 = st[0]
		var b: Vector2 = st[1]
		var along := b - a
		var len := along.length()
		var dir := along / len
		var perp := Vector2(-dir.y, dir.x)
		var count := int(len * 4.2)
		for k in range(count):
			var t := _rng.randf()
			var p := a + along * t
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			var nl := lerpf(11.5, 6.0, t) * _rng.randf_range(0.7, 1.15)
			# Needles stick out all round the twig: forward and to the sides.
			var nd := (dir * 0.75 + perp * side * _rng.randf_range(0.35, 1.0)).normalized()
			var shade := _rng.randf_range(0.0, 1.0)
			var col := Color(0.30, 0.40, 0.30).lerp(Color(0.58, 0.68, 0.48), shade * shade)
			if t > 0.8 and _rng.randf() < 0.5:
				col = col.lerp(Color(0.62, 0.74, 0.46), 0.5)   # fresh growth at the tips
			_line(img, p, p + nd * nl, 1.7, col)
	for st in stems:
		_line(img, st[0], st[1], 1.1, twig)
	img.generate_mipmaps()
	return img


static func _paint_leaves(w: int, h: int) -> Image:
	_rng.seed = 1977
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.45, 0.48, 0.38, 0.0))
	var twig := Color(0.36, 0.31, 0.26, 1.0)
	var c := Vector2(w, h) * 0.5
	# A loose sprig: twigs out from the middle, small oval leaves along them.
	var twigs: Array = []
	for k in range(7):
		var a := TAU * float(k) / 7.0 + _rng.randf_range(-0.3, 0.3)
		var l := float(w) * _rng.randf_range(0.28, 0.46)
		twigs.append([c, c + Vector2(cos(a), sin(a)) * l])
	for tw in twigs:
		var a: Vector2 = tw[0]
		var b: Vector2 = tw[1]
		var d := (b - a)
		for k in range(int(d.length() / 3.0)):
			var p := a + d * _rng.randf_range(0.25, 1.0)
			var ang := _rng.randf() * TAU
			var size := _rng.randf_range(9.0, 15.0)
			var shade := _rng.randf()
			var col := Color(0.38, 0.46, 0.30).lerp(Color(0.66, 0.72, 0.46), shade * shade)
			_leaf(img, p, ang, size, size * 0.6, col)
	for tw in twigs:
		_line(img, tw[0], tw[1], 1.0, twig)
	img.generate_mipmaps()
	return img


static func _leaf(img: Image, p: Vector2, ang: float, l: float, wd: float, col: Color) -> void:
	var sz := img.get_size()
	var ca := cos(ang)
	var sa := sin(ang)
	var r := int(ceil(l))
	for oy in range(-r, r + 1):
		for ox in range(-r, r + 1):
			var u := (ox * ca + oy * sa) / l
			var v := (-ox * sa + oy * ca) / (wd * 0.5)
			if u * u + v * v > 1.0:
				continue
			var x := int(p.x) + ox
			var y := int(p.y) + oy
			if x >= 0 and y >= 0 and x < sz.x and y < sz.y:
				# Darker down the midrib, lighter at the edge.
				img.set_pixel(x, y, col.darkened(0.12 * (1.0 - absf(v))))
