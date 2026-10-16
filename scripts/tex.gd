extends RefCounted
## Photo-scanned materials (DESIGN_NOTES 228, Dave: "make everything have really
## good texture"). CC0 scans from Poly Haven in textures/ph/<id>/ (fetched by
## tools/fetch_textures.gd): colour, normal (GL), and AO/rough/metal packed
## (ARM). Mapped triplanar in world space so MeshKit geometry needs no UVs;
## `size` is how many metres one tile covers. Vertex colour tints the scan
## (paint colour, rust, a band of red on the mast).
## Every material is made once and shared (cached by its key).

static var _mats := {}
static var _imgs := {}


static func _path(id: String, map: String, res: String) -> String:
	return "res://textures/ph/%s/%s_%s_%s.jpg" % [id, id, map, res]


static func _load(p: String, normal: bool = false, neutral: bool = false) -> Texture2D:
	var ck := p + ("|n" if neutral else "")
	if _imgs.has(ck):
		return _imgs[ck]
	var t: Texture2D = null
	var gp := ProjectSettings.globalize_path(p)
	if FileAccess.file_exists(gp) or FileAccess.file_exists(p):
		var img := Image.load_from_file(gp)
		if img != null and not img.is_empty():
			if normal:
				img.convert(Image.FORMAT_RGB8)
			if neutral:
				_neutralise(img, ck)
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	_imgs[ck] = t
	return t


## For paint: keep only the scan's light and dark (grime, dents, streaks), in
## grey, so the paint colour (vertex colour) shows true. Its mean brightness
## is kept so the material can lift it back to 1.
static var _means := {}


static func _neutralise(img: Image, key: String) -> void:
	img.convert(Image.FORMAT_RGB8)
	var small := img.duplicate() as Image
	small.resize(16, 16, Image.INTERPOLATE_BILINEAR)
	var sum := 0.0
	for y in range(16):
		for x in range(16):
			sum += small.get_pixel(x, y).get_luminance()
	var mean := maxf(sum / 256.0, 0.05)
	_means[key] = mean
	# grey, brightened so the scan averages 0.85: only its grime and wear left
	img.adjust_bcs(0.85 / mean, 1.0, 0.0)


static func has(id: String) -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(_path(id, "diff", "2k")))


## A material from scan `id`, one tile per `size` metres. `tint` multiplies the
## colour (with vertex colours on top when vcol). metal: 0..1 over the scan's.
## neutral: the scan's colour is taken out (paint: the vertex colour is the colour).
static func mat(id: String, size: float = 2.0, tint: Color = Color.WHITE, vcol: bool = true, metal: float = -1.0, normal_strength: float = 1.0, neutral: bool = false) -> BaseMaterial3D:
	var key := "%s|%.3f|%s|%s|%.2f|%.2f|%s" % [id, size, tint.to_html(), vcol, metal, normal_strength, neutral]
	if _mats.has(key):
		return _mats[key]
	var m := ORMMaterial3D.new()
	m.albedo_color = tint
	m.vertex_color_use_as_albedo = vcol
	m.vertex_color_is_srgb = true
	var alb := _load(_path(id, "diff", "2k"), false, neutral)

	if alb != null:
		m.albedo_texture = alb
		var nrm := _load(_path(id, "nor_gl", "2k"), true)
		if nrm != null:
			m.normal_enabled = true
			m.normal_texture = nrm
			m.normal_scale = normal_strength
		var arm := _load(_path(id, "arm", "2k"))
		if arm == null:
			arm = _load(_path(id, "arm", "1k"))
		if arm != null:
			m.orm_texture = arm
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_triplanar_sharpness = 4.0
		m.uv1_scale = Vector3.ONE / size
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		m.roughness = 0.85
	if metal >= 0.0:
		m.metallic = metal
	_mats[key] = m
	return m


## A transparent version (chain-link, ice): plain, no scan.
static func clear(col: Color, rough: float = 0.1, double_sided: bool = true) -> StandardMaterial3D:
	var key := "clear|" + col.to_html() + "|%.2f|%s" % [rough, double_sided]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = rough
	m.metallic_specular = 0.8
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m
