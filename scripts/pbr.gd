extends RefCounted
## Realistic-looking materials made in code (no image files): worn paint over
## aluminium with rivet lines, bare scuffed metal, leather, rubber matting,
## black crinkle-finish panel paint, and glass. They work on the low-poly
## MeshKit meshes (which have no UVs) through triplanar mapping, and keep the
## mesh's vertex colours as the base colour, so a part is painted by the
## colour it was built with and these add the wear, grain and shine.
##
## Real photo textures (free CC0 photo textures) can replace the
## generated ones later: put them in res://assets/textures/ and load them here.

static var _cache := {}


static func _noise_img(size: int, freq: float, seed_v: int, octaves: int = 4) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = octaves
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n.get_seamless_image(size, size)


## Grime and wear: mostly light, with darker smudges and paler scuffs.
static func _grime(size: int, seed_v: int, amount: float) -> ImageTexture:
	var a := _noise_img(size, 0.012, seed_v)
	var b := _noise_img(size, 0.09, seed_v + 7, 2)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in range(size):
		for x in range(size):
			var v := a.get_pixel(x, y).r
			var f := b.get_pixel(x, y).r
			var g := 1.0 - amount * (smoothstep(0.45, 0.85, v) * 0.6 + f * 0.25) + amount * 0.25 * smoothstep(0.75, 0.95, f)
			img.set_pixel(x, y, Color(g, g * 0.99, g * 0.97))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _rough(size: int, seed_v: int, lo: float, hi: float, freq: float = 0.03) -> ImageTexture:
	var a := _noise_img(size, freq, seed_v)
	var img := Image.create(size, size, false, Image.FORMAT_L8)
	for y in range(size):
		for x in range(size):
			img.set_pixel(x, y, Color(lerpf(lo, hi, a.get_pixel(x, y).r), 0, 0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A height picture turned into a normal map.
static func _normal_from(img: Image, strength: float) -> ImageTexture:
	var h := img.duplicate()
	h.convert(Image.FORMAT_RF)
	h.bump_map_to_normal_map(strength)
	h.generate_mipmaps()
	return ImageTexture.create_from_image(h)


## Rows of round rivet heads along panel seams, on gently dented sheet.
static func _rivet_normal(size: int) -> ImageTexture:
	var dent := _noise_img(size, 0.02, 31, 3)
	var img := Image.create(size, size, false, Image.FORMAT_RF)
	var pitch := size / 16
	for y in range(size):
		for x in range(size):
			var hgt := dent.get_pixel(x, y).r * 0.25
			# A seam every half texture, rivets along it.
			for seam_y in [size / 4, 3 * size / 4]:
				var dy: int = absi(y - seam_y)
				if dy < 3:
					hgt -= 0.15
				var cx := (x % pitch) - pitch / 2
				var d := sqrt(float(cx * cx + (y - seam_y - 6) * (y - seam_y - 6)))
				if d < 3.0:
					hgt += 0.6 * (1.0 - d / 3.0)
			img.set_pixel(x, y, Color(hgt, 0, 0))
	return _normal_from(img, 3.0)


static func _base(key: String, rough_lo: float, rough_hi: float, metal: float, scale: float, grime_amt: float, seed_v: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = _grime(256, seed_v, grime_amt)
	m.roughness = 1.0
	m.roughness_texture = _rough(256, seed_v + 3, rough_lo, rough_hi)
	m.metallic = metal
	m.metallic_specular = 0.5
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


## Painted aluminium, a bit worn, with rivet lines.
static func painted() -> StandardMaterial3D:
	if _cache.has("painted"):
		return _cache["painted"]
	var m := _base("painted", 0.45, 0.75, 0.15, 1.6, 0.35, 11)
	m.normal_enabled = true
	m.normal_texture = _rivet_normal(256)
	m.normal_scale = 0.6
	return m


## Smooth painted parts (no rivets): panels, pedestal, frames.
static func paint_smooth() -> StandardMaterial3D:
	if _cache.has("paint_smooth"):
		return _cache["paint_smooth"]
	var m := _base("paint_smooth", 0.40, 0.70, 0.1, 3.0, 0.25, 13)
	m.normal_enabled = true
	m.normal_texture = _normal_from(_noise_img(256, 0.05, 17, 3), 1.0)
	m.normal_scale = 0.25
	return m


## Black crinkle finish of an old instrument panel.
static func crinkle() -> StandardMaterial3D:
	if _cache.has("crinkle"):
		return _cache["crinkle"]
	var m := _base("crinkle", 0.55, 0.85, 0.0, 9.0, 0.15, 19)
	m.normal_enabled = true
	m.normal_texture = _normal_from(_noise_img(256, 0.35, 23, 2), 4.0)
	m.normal_scale = 0.5
	return m


## Bare, scuffed aluminium and steel: levers, frames, rails.
static func metal() -> StandardMaterial3D:
	if _cache.has("metal"):
		return _cache["metal"]
	var m := _base("metal", 0.25, 0.5, 0.85, 4.0, 0.2, 29)
	m.normal_enabled = true
	m.normal_texture = _normal_from(_noise_img(256, 0.6, 37, 1), 0.6)
	m.normal_scale = 0.3
	return m


## Leather seats: grain and worn, shinier patches.
static func leather() -> StandardMaterial3D:
	if _cache.has("leather"):
		return _cache["leather"]
	var m := _base("leather", 0.35, 0.7, 0.0, 6.0, 0.3, 41)
	m.normal_enabled = true
	m.normal_texture = _normal_from(_noise_img(256, 0.25, 43, 3), 3.0)
	m.normal_scale = 0.6
	return m


## Ribbed rubber floor matting.
static func floor_mat() -> StandardMaterial3D:
	if _cache.has("floor"):
		return _cache["floor"]
	var m := _base("floor", 0.8, 0.95, 0.0, 2.0, 0.4, 47)
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RF)
	for y in range(size):
		for x in range(size):
			img.set_pixel(x, y, Color(0.5 + 0.5 * sin(float(x) / float(size) * TAU * 24.0), 0, 0))
	m.normal_enabled = true
	m.normal_texture = _normal_from(img, 2.0)
	m.normal_scale = 0.7
	return m


## Bakelite and black knobs: smooth and a little glossy.
static func bakelite() -> StandardMaterial3D:
	if _cache.has("bakelite"):
		return _cache["bakelite"]
	var m := _base("bakelite", 0.18, 0.35, 0.0, 12.0, 0.1, 53)
	return m


## Window glass: clear, slightly green at the edges, with a soft reflection.
static func glass() -> StandardMaterial3D:
	if _cache.has("glass"):
		return _cache["glass"]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.85, 0.85, 0.10)
	m.roughness = 0.04
	m.metallic_specular = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["glass"] = m
	return m
