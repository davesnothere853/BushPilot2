extends Control
## The main menu as a cockpit (DESIGN_NOTES 187-188). Night, rain, lined up on
## a wet runway; the menu's items are the controls on a Beaver-style panel:
## the red-guarded starter toggle starts the game, toggles, push-pull breakers,
## rotary knobs, the radio, a fuel-shutoff T-handle to quit, and levers on the
## throttle quadrant for the settings sliders.
##
## It does not own any menu logic: menu.gd still builds its page of Buttons and
## HSliders; this reads them (text, pressed, value) and shows each one as a
## physical control. A new menu item appears here by itself.
##
## Its own World3D in a SubViewport: the game's world (still building, or
## streaming in) is never seen behind it.

const Tune = preload("res://scripts/tune.gd")
const START_WAV := "res://assets/sounds/plane/starter.wav"
const CATCH_WAV := "res://assets/sounds/plane/start.wav"

var menu: Node                        # menu.gd
var settle_check: Callable            # main: () -> bool, the world has streamed in
var active := false                   # taking input (the menu is on its main page)
var boot := false                     # shown before the world is built: no input

var _vp: SubViewport
var _svc: SubViewportContainer
var _cam: Camera3D
var _cam_base: Transform3D
var _scene: Node3D
var _panel: Node3D                    # the panel face: x right, y up, +z toward the pilot
var _quad: Node3D                     # throttle quadrant
var _ctl_root: Node3D
var _lever_root: Node3D
var _torch: SpotLight3D
var _glass_mat: ShaderMaterial
var _rain: GPUParticles3D
var _env: Environment
var _sky_light: DirectionalLight3D
var _hint: Label
var _title: Label
var _ctrls: Array = []                # each: Dictionary (see _add_control)
var _levers: Array = []
var _focus := -1
var _focus_lever := -1
var _last_focus_text := ""
var _t := 0.0
var _gust := 0.0                      # -1..1 now
var _gust_target := 0.0
var _gust_t := 0.0
var _rain_amt := 0.8
var _rain_target := 0.8
var _flash_t := 99.0                  # time to the next lightning
var _flash := 0.0
var _thunder_in := -1.0
var _thunder_vol := 0.0
var _sfx: AudioStreamPlayer
var _rain_snd: AudioStreamPlayer
var _wind_snd: AudioStreamPlayer
var _thunder: AudioStreamPlayer
var _drag_lever := -1
var _busy := false                    # a start sequence is running
var _beacon: MeshInstance3D
var _beacon_mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()

static var _font: Font
static var _noise_nrm: NoiseTexture2D


func _ready() -> void:
	_rng.seed = 1988
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_svc = SubViewportContainer.new()
	_svc.stretch = true
	_svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_vp.audio_listener_enable_3d = false
	_svc.add_child(_vp)
	_scene = Node3D.new()
	_vp.add_child(_scene)
	_build_environment()
	_build_outside()
	_build_cockpit()
	_build_sounds()
	_build_overlay()
	_flash_t = _rng.randf_range(6.0, 14.0)
	visibility_changed.connect(_on_visibility)


## Rain, wind and thunder stop when the cockpit's put away (they kept going
## under the game).
func _on_visibility() -> void:
	var on := is_visible_in_tree()
	for p in [_rain_snd, _wind_snd, _thunder, _sfx]:
		if p == null:
			continue
		if on and (p == _rain_snd or p == _wind_snd):
			if not p.playing:
				p.play()
		elif not on:
			p.stop()
	_engine_on = 0.0
	if not on:
		_thunder_in = -1.0


# ------------------------------------------------------------------------------
#  Materials: smooth, a little handmade (a faint thumbprint in every surface),
#  but crisp - clean colours, firm highlights.
# ------------------------------------------------------------------------------
static func _thumb() -> NoiseTexture2D:
	if _noise_nrm == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.035
		n.fractal_octaves = 3
		_noise_nrm = NoiseTexture2D.new()
		_noise_nrm.width = 256
		_noise_nrm.height = 256
		_noise_nrm.seamless = true
		_noise_nrm.as_normal_map = true
		_noise_nrm.bump_strength = 3.0
		_noise_nrm.noise = n
	return _noise_nrm


static func _mat(col: Color, rough: float = 0.6, metal: float = 0.0, thumb: float = 0.25) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if thumb > 0.0:
		m.normal_enabled = true
		m.normal_texture = _thumb()
		m.normal_scale = thumb
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 9.0
	return m


static func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "DIN Alternate", "DIN", "Roboto Condensed", "Arial Narrow", "Segoe UI"])
		f.font_weight = 700
		_font = f
	return _font


func _mesh(m: Mesh, mat: Material, parent: Node3D, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _cyl(r_top: float, r_bot: float, h: float, seg: int = 32) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _sphere(r: float, h: float = -1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 if h < 0.0 else h
	s.radial_segments = 32
	s.rings = 16
	return s


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 32
	c.rings = 8
	return c


# ------------------------------------------------------------------------------
#  Environment: a wet night, haze that eats the far lights
# ------------------------------------------------------------------------------
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.010, 0.013, 0.020)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.10, 0.12, 0.16)
	_env.ambient_light_energy = 0.25
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.05
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_env.glow_strength = 1.05
	_env.glow_bloom = 0.04
	_env.glow_hdr_threshold = 0.9
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in range(7):
		_env.set_glow_level(i, 1.0 if i >= 2 and i <= 5 else 0.0)
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.05, 0.06, 0.075)
	_env.fog_density = 0.0045
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.018
	_env.volumetric_fog_albedo = Color(0.75, 0.78, 0.82)
	_env.volumetric_fog_anisotropy = 0.55
	_env.volumetric_fog_length = 90.0
	_env.ssr_enabled = true
	_env.ssr_max_steps = 64
	_env.ssao_enabled = true
	_env.ssao_radius = 0.6
	_env.ssao_intensity = 1.6
	we.environment = _env
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 3.0
	ca.dof_blur_far_transition = 8.0
	ca.dof_blur_amount = 0.06
	we.camera_attributes = ca
	_scene.add_child(we)
	# moon behind cloud: barely there, it's the lightning's light too
	_sky_light = DirectionalLight3D.new()
	_sky_light.light_color = Color(0.62, 0.70, 0.95)
	_sky_light.light_energy = 0.04
	_sky_light.rotation_degrees = Vector3(-38, 150, 0)
	_sky_light.shadow_enabled = true
	_sky_light.directional_shadow_max_distance = 30.0
	_sky_light.light_volumetric_fog_energy = 0.4
	_scene.add_child(_sky_light)


# ------------------------------------------------------------------------------
#  Outside: the runway in the rain
# ------------------------------------------------------------------------------
const GROUND_Y := -1.05            # the runway, below the pilot's seat

func _build_outside() -> void:
	var out := Node3D.new()
	out.name = "Outside"
	_outside = out
	_scene.add_child(out)
	# wet asphalt: dark, glossy (SSR gives the light streaks), with a grass verge
	var asph := _mat(Color(0.035, 0.036, 0.04), 0.12, 0.0, 0.0)
	var pm := PlaneMesh.new()
	pm.size = Vector2(32, 2400)
	_mesh(pm, asph, out, Vector3(0, GROUND_Y, -1180))
	var grass := _mat(Color(0.025, 0.035, 0.022), 0.85, 0.0, 0.0)
	var gm := PlaneMesh.new()
	gm.size = Vector2(1400, 3200)
	_mesh(gm, grass, out, Vector3(0, GROUND_Y - 0.03, -1300))
	# centre-line dashes and the threshold piano keys (paint catches a little light)
	var paint := _mat(Color(0.55, 0.55, 0.52), 0.35, 0.0, 0.0)
	for i in range(40):
		_mesh(_box(Vector3(0.45, 0.01, 12.0)), paint, out, Vector3(0, GROUND_Y + 0.004, -30.0 - i * 30.0), Vector3.ZERO, false)
	for k in range(-6, 7):
		if k == 0:
			continue
		_mesh(_box(Vector3(1.0, 0.01, 18.0)), paint, out, Vector3(k * 2.1, GROUND_Y + 0.004, 4.0), Vector3.ZERO, false)
	# edge lights: white, the last 600 m amber; red across the far end; blue taxiway off left
	var white := _glow(Color(1.0, 0.86, 0.66), 7.0)
	var amber := _glow(Color(1.0, 0.55, 0.14), 7.0)
	var red := _glow(Color(1.0, 0.12, 0.06), 7.0)
	var green := _glow(Color(0.2, 1.0, 0.45), 6.0)
	var blue := _glow(Color(0.25, 0.4, 1.0), 6.0)
	_light_mats = [white, amber, red, green, blue]
	var bulb := _sphere(0.16)
	var stalk := _mat(Color(0.08, 0.08, 0.08), 0.5)
	for i in range(34):
		var z := -14.0 - i * 60.0
		var m := amber if i >= 24 else white
		for x in [-16.5, 16.5]:
			_mesh(_cyl(0.025, 0.03, 0.55, 8), stalk, out, Vector3(x, GROUND_Y + 0.27, z), Vector3.ZERO, false)
			var bm := _mesh(bulb, m, out, Vector3(x, GROUND_Y + 0.6, z), Vector3.ZERO, false)
			bm.scale = Vector3.ONE * maxf(1.0, absf(z) / 22.0)
	for k in range(-7, 8):
		_mesh(bulb, red, out, Vector3(k * 2.2, GROUND_Y + 0.35, -2060.0), Vector3.ZERO, false).scale = Vector3.ONE * 60.0
		_mesh(bulb, green, out, Vector3(k * 2.2, GROUND_Y + 0.35, 12.0), Vector3.ZERO, false)
	for i in range(14):
		_mesh(bulb, blue, out, Vector3(-48.0 - (i % 2) * 0.3, GROUND_Y + 0.3, -60.0 - i * 26.0), Vector3.ZERO, false).scale = Vector3.ONE * maxf(1.0, (60.0 + i * 26.0) / 30.0)
	# the nearest lights throw real light: halos in the haze, streaks on the wet runway
	for i in range(4):
		for x in [-16.5, 16.5]:
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.85, 0.65)
			ol.light_energy = 1.4
			ol.omni_range = 9.0
			ol.light_volumetric_fog_energy = 2.5
			ol.position = Vector3(x, GROUND_Y + 0.75, -14.0 - i * 60.0)
			out.add_child(ol)
	# the rotating beacon on the old tower, off to the left in the murk
	var tower := _mat(Color(0.05, 0.05, 0.055), 0.8)
	_mesh(_box(Vector3(3.0, 16.0, 3.0)), tower, out, Vector3(-210, GROUND_Y + 8.0, -420))
	_beacon_mat = _glow(Color(0.9, 1.0, 0.9), 0.0)
	_beacon = _mesh(_sphere(0.6), _beacon_mat, out, Vector3(-210, GROUND_Y + 16.8, -420), Vector3.ZERO, false)
	# a hangar with a sodium lamp over its door, far right
	var shed := _mat(Color(0.06, 0.06, 0.06), 0.7)
	_mesh(_box(Vector3(30, 9, 22)), shed, out, Vector3(95, GROUND_Y + 4.5, -160))
	_mesh(_sphere(0.35), _glow(Color(1.0, 0.62, 0.22), 9.0), out, Vector3(85, GROUND_Y + 7.0, -148.6), Vector3.ZERO, false)
	var sod := OmniLight3D.new()
	sod.light_color = Color(1.0, 0.6, 0.25)
	sod.light_energy = 3.0
	sod.omni_range = 18.0
	sod.light_volumetric_fog_energy = 3.0
	sod.position = Vector3(85, GROUND_Y + 6.5, -147.5)
	out.add_child(sod)
	# rain: streaks falling through the haze
	_rain = GPUParticles3D.new()
	_rain.amount = 2600
	_rain.lifetime = 0.9
	_rain.preprocess = 1.0
	_rain.visibility_aabb = AABB(Vector3(-14, -10, -13), Vector3(28, 14, 26))
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(12, 1.0, 11)
	pmat.direction = Vector3(0, -1, 0)
	pmat.spread = 4.0
	pmat.initial_velocity_min = 9.0
	pmat.initial_velocity_max = 11.0
	pmat.gravity = Vector3(0, -4.0, 0)
	_rain.process_material = pmat
	var streak := QuadMesh.new()
	streak.size = Vector2(0.006, 0.42)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.7, 0.75, 0.82, 0.22)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.billboard_keep_scale = true
	streak.material = smat
	_rain.draw_pass_1 = streak
	_rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	# all of it outside: the box ends 2 m ahead of the windshield (it was falling
	# through the cabin)
	_rain.position = Vector3(0, 4.5, -14.0)
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out.add_child(_rain)


# ------------------------------------------------------------------------------
#  The cockpit: Beaver-style panel, glare shield, posts, the windshield, the nose
# ------------------------------------------------------------------------------
const CAM_POS := Vector3(-0.05, 1.56, 0.34)
const PANEL_POS := Vector3(0.0, 0.98, -0.62)
const PANEL_TILT := -14.0            # degrees: the face leans back toward the pilot
const PW := 1.16                     # panel width, height (m)
const PH := 0.54

func _build_cockpit() -> void:
	_cam = Camera3D.new()
	_cam.fov = 54.0
	_cam.near = 0.02
	_cam.far = 3000.0
	_cam.position = CAM_POS
	_scene.add_child(_cam)
	_cam.look_at(Vector3(0.02, 1.16, -0.9))
	_cam_base = _cam.transform

	var crinkle := _mat(Color(0.030, 0.030, 0.032), 0.78, 0.0, 0.6)       # black crinkle paint
	var trim := _mat(Color(0.20, 0.21, 0.19), 0.55, 0.3, 0.3)
	var hide := _mat(Color(0.05, 0.045, 0.04), 0.7, 0.0, 0.4)             # glare shield leatherette
	var olive := _mat(Color(0.17, 0.19, 0.13), 0.7, 0.0, 0.35)            # interior paint

	_panel = Node3D.new()
	_panel.name = "Panel"
	_panel.position = PANEL_POS
	_panel.rotation_degrees = Vector3(PANEL_TILT, 0, 0)
	_scene.add_child(_panel)
	# the panel board, with a raised lip all round
	_crinkle = crinkle
	_mesh(_box(Vector3(PW + 0.04, 0.025, 0.05)), trim, _panel, Vector3(0, PH * 0.5 + 0.01, -0.01))
	_mesh(_box(Vector3(PW + 0.04, 0.025, 0.05)), trim, _panel, Vector3(0, -PH * 0.5 - 0.01, -0.01))
	# glare shield: a rounded leather brow over the top of the panel
	var brow := _mesh(_capsule(0.055, PW + 0.12), hide, _panel, Vector3(0, PH * 0.5 + 0.045, 0.02), Vector3(0, 0, 90))
	brow.scale = Vector3(1.0, 1.0, 1.6)
	# a whiskey compass on the glare shield, a little off-centre like they are
	var comp := Node3D.new()
	comp.position = Vector3(0.10, PH * 0.5 + 0.11, 0.02)
	_panel.add_child(comp)
	_mesh(_box(Vector3(0.07, 0.06, 0.07)), _mat(Color(0.04, 0.04, 0.04), 0.4), comp)
	_mesh(_cyl(0.016, 0.016, 0.004), _mat(Color(0.30, 0.28, 0.22), 0.4), comp, Vector3(0, 0.0, 0.036), Vector3(90, 0, 0))
	# flight instruments, left; engine gauges, centre
	_build_gauges()
	_build_board()
	# radio stack, centre-right: a 1980s nav/com head with amber digits
	var radio := Node3D.new()
	radio.position = Vector3(0.235, 0.13, 0.0)
	_panel.add_child(radio)
	_mesh(_box(Vector3(0.20, 0.075, 0.03)), _mat(Color(0.06, 0.06, 0.065), 0.45, 0.2), radio, Vector3(0, 0, 0.012))
	_mesh(_box(Vector3(0.11, 0.026, 0.004)), _glow(Color(1.0, 0.55, 0.12), 0.25), radio, Vector3(-0.03, 0.012, 0.028), Vector3.ZERO, false)
	var digits := Label3D.new()
	digits.text = "122.80"
	digits.font = font()
	digits.font_size = 64
	digits.pixel_size = 0.00028
	digits.modulate = Color(1.0, 0.62, 0.18)
	digits.outline_size = 0
	digits.shaded = false
	digits.position = Vector3(-0.03, 0.012, 0.031)
	radio.add_child(digits)
	_radio_digits = digits
	# lived-in bits: masking tape with a grease-pencil note, a photo tucked in the panel edge
	var tape := _mesh(_box(Vector3(0.12, 0.028, 0.0015)), _mat(Color(0.86, 0.80, 0.62), 0.9, 0.0, 0.2), _panel, Vector3(-0.30, -0.093, 0.004), Vector3(0, 0, 2.5), false)
	var note := Label3D.new()
	note.text = "C-FBDY  oil +2 qt\nprop seal - watch it"
	note.font_size = 34
	note.pixel_size = 0.00028
	note.modulate = Color(0.12, 0.10, 0.10)
	note.outline_size = 0
	note.shaded = true
	note.position = Vector3(0, 0, 0.0012)
	note.line_spacing = -4.0
	tape.add_child(note)
	var photo := _mesh(_box(Vector3(0.05, 0.06, 0.001)), _mat(Color(0.92, 0.90, 0.85), 0.8, 0.0, 0.1), _panel, Vector3(0.545, -0.20, 0.004), Vector3(0, 0, -8), false)
	_mesh(_box(Vector3(0.042, 0.042, 0.001)), _mat(Color(0.25, 0.30, 0.34), 0.6), photo, Vector3(0, 0.005, 0.001), Vector3.ZERO, false)
	# under the panel: the throttle quadrant
	_quad = Node3D.new()
	_quad.position = PANEL_POS + Vector3(0.02, -0.25, 0.10)
	_scene.add_child(_quad)
	_mesh(_box(Vector3(0.20, 0.06, 0.16)), crinkle, _quad)
	for x in [-0.055, 0.0, 0.055]:
		_mesh(_box(Vector3(0.008, 0.002, 0.13)), _mat(Color(0.0, 0.0, 0.0), 0.9, 0.0, 0.0), _quad, Vector3(x, 0.031, 0.0), Vector3.ZERO, false)
	_lever_root = Node3D.new()
	_quad.add_child(_lever_root)
	# windshield posts and frame, the side walls, the floor
	_mesh(_capsule(0.035, 0.85), olive, _scene, Vector3(-0.74, 1.48, -0.78), Vector3(-25, 0, -8))
	_mesh(_capsule(0.035, 0.85), olive, _scene, Vector3(0.74, 1.48, -0.78), Vector3(-25, 0, 8))
	_mesh(_capsule(0.04, 1.6), olive, _scene, Vector3(0, 1.86, -0.95), Vector3(0, 0, 90))
	_mesh(_box(Vector3(0.05, 1.6, 1.8)), olive, _scene, Vector3(-0.82, 0.9, -0.3))
	_mesh(_box(Vector3(0.05, 1.6, 1.8)), olive, _scene, Vector3(0.82, 0.9, -0.3))
	_mesh(_box(Vector3(1.7, 0.04, 1.8)), _mat(Color(0.05, 0.05, 0.045), 0.9), _scene, Vector3(0, 0.0, -0.3))
	# headliner and the upper cabin sides (the rain showed through the gap above)
	var headliner := _mat(Color(0.20, 0.19, 0.17), 0.9, 0.0, 0.5)
	_mesh(_box(Vector3(1.8, 0.04, 2.0)), headliner, _scene, Vector3(0, 1.96, -0.2))
	_mesh(_box(Vector3(0.05, 0.6, 2.0)), olive, _scene, Vector3(-0.86, 1.66, -0.2))
	_mesh(_box(Vector3(0.05, 0.6, 2.0)), olive, _scene, Vector3(0.86, 1.66, -0.2))
	# the wet windshield
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = load("res://shaders/wet_glass.gdshader")
	var gq := QuadMesh.new()
	gq.size = Vector2(1.5, 0.62)
	_glass_mat.set_shader_parameter("glass_size", gq.size)
	var glass := _mesh(gq, _glass_mat, _scene, Vector3(0, 1.50, -0.86), Vector3(-25, 0, 0), false)
	_glass = glass
	glass.sorting_offset = 1.0
	# the nose: the yellow cowling humped up in front, rain bouncing off it
	var cowl := _mat(Color(0.86, 0.62, 0.10), 0.35, 0.0, 0.25)
	var nose := _mesh(_capsule(0.62, 3.2), cowl, _scene, Vector3(0, 0.25, -2.6), Vector3(90, 0, 0))
	nose.scale = Vector3(1.0, 1.0, 0.8)
	# red flood light under the glare shield, and the pilot's torch
	var flood := OmniLight3D.new()
	_flood = flood
	flood.light_color = Color(1.0, 0.26, 0.16)
	flood.light_energy = 0.10
	flood.omni_range = 0.7
	flood.shadow_enabled = true
	flood.position = PANEL_POS + Vector3(0.0, 0.27, 0.16)
	_scene.add_child(flood)
	var dome := OmniLight3D.new()
	_dome = dome
	dome.light_color = Color(1.0, 0.82, 0.62)
	dome.light_energy = 0.18
	dome.omni_range = 2.2
	dome.position = Vector3(0.1, 1.95, 0.2)
	_scene.add_child(dome)
	_torch = SpotLight3D.new()
	_torch.light_color = Color(1.0, 0.90, 0.74)
	_torch.light_energy = 2.6
	_torch.spot_range = 3.0
	_torch.spot_angle = 8.5
	_torch.spot_angle_attenuation = 1.6
	_torch.shadow_enabled = true
	_torch.position = CAM_POS + Vector3(-0.22, 0.10, 0.05)
	_scene.add_child(_torch)
	_torch.look_at(PANEL_POS)
	_ctl_root = Node3D.new()
	_panel.add_child(_ctl_root)

var _radio_digits: Label3D
var plane: Node3D                     # main's plane (parked): altitude, heading, fuel for the gauges
var _engine_on := 0.0                 # 0..1: the engine catching after START
var _gauges: Node3D
var _holes: Array = []                # [Vector2 centre, radius] cut through the panel board
var _crinkle: Material


## The panel board, 3 cm thick, with a hole for every instrument so the dials sit
## recessed in their cases the way they do in the real thing.
func _build_board() -> void:
	var board := CSGBox3D.new()
	board.size = Vector3(PW, PH, 0.03)
	board.position = Vector3(0, 0, -0.015)
	board.material = _crinkle
	_panel.add_child(board)
	for h in _holes:
		var cut := CSGCylinder3D.new()
		cut.radius = float(h[1]) + 0.0025
		cut.height = 0.06
		cut.sides = 40
		cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		cut.rotation_degrees = Vector3(90, 0, 0)
		cut.position = Vector3((h[0] as Vector2).x, (h[0] as Vector2).y, 0.0)
		board.add_child(cut)


func _g(id: String, at: Vector2, r: float, fn: Callable) -> void:
	_gauges.add(id, Vector3(at.x, at.y, 0.0), r, fn)
	_holes.append([at, r])


## The Wolverine's own instruments (real_gauges.gd), laid out like a Beaver's:
## the six on the left, engine gauges in the middle. Live from the parked plane;
## the engine ones wake up when START is flipped; the airspeed needle twitches
## in the gusts (the wind's blowing into the pitot).
func _build_gauges() -> void:
	_gauges = load("res://scripts/real_gauges.gd").new()
	_gauges.face_glow = 0.55
	_panel.add_child(_gauges)
	var R := 0.048
	var s := 0.130
	var x0 := -0.45
	_g("airspeed", Vector2(x0, 0.14), R, func() -> float: return absf(_gust) * 22.0 + absf(sin(_t * 5.0)) * 4.0 * absf(_gust))
	_g("attitude", Vector2(x0 + s, 0.14), R, func() -> Vector2: return Vector2(_gust * 0.03, 0.02))
	_g("altimeter", Vector2(x0 + s * 2.0, 0.14), R, func() -> float: return _field_ft())
	_g("clock", Vector2(x0, 0.005), 0.034, func() -> float: return float(Game.time_of_day))
	_g("heading", Vector2(x0 + s, 0.005), R, func() -> float: return _heading())
	_g("vsi", Vector2(x0 + s * 2.0, 0.005), R, func() -> float: return _gust * 120.0)
	_g("tach", Vector2(-0.03, 0.15), 0.040, func() -> float: return _engine_on * 1050.0 + sin(_t * 9.0) * 15.0 * _engine_on)
	_g("map", Vector2(0.068, 0.15), 0.030, func() -> float: return lerpf(29.6, 14.0, _engine_on))
	_g("oilp", Vector2(-0.055, 0.052), 0.022, func() -> float: return _engine_on * 62.0)
	_g("oilt", Vector2(0.015, 0.052), 0.022, func() -> float: return 62.0 + _engine_on * 6.0)
	_g("cht", Vector2(0.085, 0.052), 0.022, func() -> float: return 70.0 + _engine_on * 40.0)
	_g("fuell", Vector2(-0.02, -0.025), 0.022, func() -> float: return _fuel(true))
	_g("fuelr", Vector2(0.05, -0.025), 0.022, func() -> float: return _fuel(false))


func _field_ft() -> float:
	if plane != null and is_instance_valid(plane) and plane.has_method("altitude_ft"):
		return float(plane.altitude_ft())
	return 1240.0


func _heading() -> float:
	if plane != null and is_instance_valid(plane) and plane.has_method("heading_deg"):
		return float(plane.heading_deg())
	return 327.0


func _fuel(left: bool) -> float:
	if plane != null and is_instance_valid(plane) and plane.get("engine") != null:
		var e = plane.engine
		var cap: float = maxf(float(e.tank_capacity), 1.0)
		return (float(e.tank_left) if left else float(e.tank_right)) / cap * 20.0
	return 14.0 if left else 11.5


# ------------------------------------------------------------------------------
#  Controls
# ------------------------------------------------------------------------------
## What each menu button becomes: [kind, tape text, colour]. Kinds: start (red-
## guarded toggle), toggle, guard (red-guarded toggle), breaker (push-pull),
## knob, radio, thandle.
func _kind_for(text: String) -> Array:
	var t := text.to_lower()
	if t.begins_with("start over"):
		return ["guard", "BACK TO STRIP", Color.BLACK]
	if t == "start" or t == "resume":
		return ["start", "START" if t == "start" else "RESUME", Color.BLACK]
	if t.begins_with("quit"):
		return ["thandle", "QUIT", Color.BLACK]
	if t.begins_with("travel"):
		return ["knob", "TRAVEL", Color.BLACK]
	if t.begins_with("plane load"):
		return ["knob", "LOAD/FUEL", Color.BLACK]
	if t.begins_with("season"):
		return ["knob", "WX/SEASON", Color.BLACK]
	if t.begins_with("co-op"):
		return ["radio", "CO-OP", Color.BLACK]
	if t.begins_with("graphics"):
		return ["toggle", "GRAPHICS", Color.BLACK]
	if t.begins_with("controls"):
		return ["toggle", "CONTROLS", Color.BLACK]
	if t.begins_with("new game"):
		return ["guard", "NEW GAME", Color.BLACK]
	if t.begins_with("how to"):
		return ["breaker", "HOW TO FLY", Color(0.86, 0.82, 0.70)]
	if t.begins_with("load a saved") or t.begins_with("save slots"):
		return ["breaker", "LOGBOOK", Color(0.80, 0.58, 0.16)]
	if t.begins_with("save game"):
		return ["breaker", "SAVE", Color(0.80, 0.58, 0.16)]
	if t.begins_with("job"):
		return ["breaker", "JOBS", Color(0.24, 0.42, 0.40)]
	if t.begins_with("your planes"):
		return ["breaker", "FLEET", Color(0.24, 0.42, 0.40)]
	if t.begins_with("workshop"):
		return ["breaker", "WORKSHOP", Color(0.24, 0.42, 0.40)]
	if t.begins_with("fail left"):
		return ["toggle", "FAIL L ENG", Color.BLACK]
	if t.begins_with("fail right"):
		return ["toggle", "FAIL R ENG", Color.BLACK]
	if t.begins_with("restart"):
		return ["toggle", "RESTART ENG", Color.BLACK]
	return ["breaker", text.to_upper().left(12), Color(0.86, 0.82, 0.70)]


## Where each kind lives on a Beaver panel (panel coordinates, metres): the
## toggle row along the bottom left, breakers in a block on the right, knobs
## down the right edge, START by the mags, the T-handle under the panel.
const SLOTS := {
	"toggle": [Vector2(-0.45, -0.155), Vector2(-0.375, -0.155), Vector2(-0.30, -0.155), Vector2(-0.225, -0.155), Vector2(-0.45, -0.225), Vector2(-0.375, -0.225), Vector2(-0.30, -0.225)],
	"breaker": [Vector2(0.16, -0.035), Vector2(0.235, -0.035), Vector2(0.31, -0.035), Vector2(0.16, -0.12), Vector2(0.235, -0.12), Vector2(0.31, -0.12), Vector2(0.385, -0.12), Vector2(0.16, -0.205), Vector2(0.235, -0.205)],
	"knob": [Vector2(0.475, 0.14), Vector2(0.475, 0.03), Vector2(0.475, -0.08)],
	"radio": [Vector2(0.305, 0.13)],
	"start": [Vector2(-0.09, -0.16)],
	"guard": [Vector2(-0.01, -0.16), Vector2(0.07, -0.16)],
	"thandle": [Vector2(-0.46, -0.32)],
}


func show_buttons(buttons: Array) -> void:
	for c in _ctrls:
		if is_instance_valid(c["node"]):
			c["node"].queue_free()
	_ctrls.clear()
	var used := {}
	for b in buttons:
		var text: String = b.text if b != null else ""
		var k: Array = _kind_for(text)
		var kind: String = k[0]
		var slots: Array = SLOTS.get(kind, SLOTS["breaker"])
		var i: int = used.get(kind, 0)
		if i >= slots.size():
			# out of room for that kind: overflow into the breaker block
			kind = "breaker"
			slots = SLOTS["breaker"]
			i = used.get(kind, 0)
			if i >= slots.size():
				continue
		used[kind] = i + 1
		_add_control(b, kind, String(k[1]), k[2], slots[i])
	_focus = -1
	var want := 0
	for j in range(_ctrls.size()):
		if _ctrls[j]["tape"] == _last_focus_text:
			want = j
	if not _ctrls.is_empty():
		_set_focus(want)


func _add_control(button: Variant, kind: String, tape: String, col: Color, at: Vector2) -> void:
	var root := Node3D.new()
	root.position = Vector3(at.x, at.y, 0.0)
	if kind == "thandle":
		# under the panel's bottom lip, not on the face
		root.position = Vector3(at.x, at.y, 0.03)
	_ctl_root.add_child(root)
	var c := {"node": root, "kind": kind, "button": button, "tape": tape, "parts": {}, "tape_label": null}
	var chrome := _mat(Color(0.78, 0.78, 0.76), 0.22, 1.0, 0.05)
	var nut := _mat(Color(0.55, 0.55, 0.53), 0.35, 1.0, 0.05)
	var worn := _mat(Color(0.11, 0.105, 0.10), 0.6, 0.2, 0.5)       # paint rubbed through by thumbs
	match kind:
		"toggle", "guard", "start":
			_mesh(_cyl(0.022, 0.024, 0.002), worn, root, Vector3(0, 0, 0.001), Vector3(90, 0, 0), false)
			_mesh(_cyl(0.013, 0.013, 0.008, 6), nut, root, Vector3(0, 0, 0.005), Vector3(90, 0, 0))
			_mesh(_cyl(0.008, 0.009, 0.012, 24), chrome, root, Vector3(0, 0, 0.012), Vector3(90, 0, 0))
			var piv := Node3D.new()
			piv.position = Vector3(0, 0, 0.016)
			root.add_child(piv)
			_mesh(_cyl(0.0032, 0.0042, 0.040, 16), chrome, piv, Vector3(0, 0.020, 0))
			_mesh(_sphere(0.0052, 0.0095), chrome, piv, Vector3(0, 0.041, 0))
			piv.rotation.x = deg_to_rad(112)          # down (off)
			c["parts"]["lever"] = piv
			if kind == "guard" or kind == "start":
				var hinge := Node3D.new()
				hinge.position = Vector3(0, 0.026, 0.006)
				root.add_child(hinge)
				var red := _mat(Color(0.72, 0.07, 0.05), 0.32, 0.0, 0.2)
				var big := 1.0 if kind == "start" else 0.82
				# the cover: a rounded red box open at the back
				_mesh(_box(Vector3(0.036 * big, 0.058 * big, 0.003)), red, hinge, Vector3(0, -0.029 * big, 0.044 * big))
				_mesh(_box(Vector3(0.003, 0.058 * big, 0.044 * big)), red, hinge, Vector3(0.018 * big, -0.029 * big, 0.022 * big))
				_mesh(_box(Vector3(0.003, 0.058 * big, 0.044 * big)), red, hinge, Vector3(-0.018 * big, -0.029 * big, 0.022 * big))
				_mesh(_box(Vector3(0.036 * big, 0.003, 0.044 * big)), red, hinge, Vector3(0, -0.058 * big, 0.022 * big))
				_mesh(_cyl(0.004, 0.004, 0.04 * big, 12), chrome, hinge, Vector3.ZERO, Vector3(0, 0, 90))
				c["parts"]["guard"] = hinge
		"breaker":
			_mesh(_cyl(0.017, 0.018, 0.004), nut, root, Vector3(0, 0, 0.002), Vector3(90, 0, 0))
			var cap := Node3D.new()
			cap.position = Vector3(0, 0, 0.004)
			root.add_child(cap)
			var cm := _mat(col, 0.45, 0.0, 0.3)
			_mesh(_cyl(0.0125, 0.0135, 0.020), cm, cap, Vector3(0, 0, 0.010), Vector3(90, 0, 0))
			_mesh(_sphere(0.0125, 0.008), cm, cap, Vector3(0, 0, 0.020))
			# the white collar that shows when it pops
			_mesh(_cyl(0.0095, 0.0095, 0.008), _mat(Color(0.9, 0.9, 0.86), 0.5), cap, Vector3(0, 0, -0.002), Vector3(90, 0, 0))
			c["parts"]["cap"] = cap
		"knob":
			_mesh(_cyl(0.034, 0.034, 0.003), _mat(Color(0.03, 0.03, 0.03), 0.5), root, Vector3(0, 0, 0.0015), Vector3(90, 0, 0), false)
			var tick := _mat(Color(0.85, 0.85, 0.80), 0.5, 0.0, 0.0)
			for i in range(5):
				var a := deg_to_rad(-60.0 + 30.0 * i)
				_mesh(_box(Vector3(0.0018, 0.006, 0.001)), tick, root, Vector3(sin(a) * 0.029, cos(a) * 0.029, 0.0035), Vector3(0, 0, -rad_to_deg(a)), false)
			var k := Node3D.new()
			k.position = Vector3(0, 0, 0.003)
			root.add_child(k)
			var km := _mat(Color(0.07, 0.065, 0.06), 0.5, 0.0, 0.35)
			_mesh(_cyl(0.019, 0.022, 0.024, 40), km, k, Vector3(0, 0, 0.012), Vector3(90, 0, 0))
			# a fluted grip: ridges round the skirt
			for i in range(18):
				var a2 := TAU * float(i) / 18.0
				_mesh(_box(Vector3(0.003, 0.003, 0.02)), km, k, Vector3(cos(a2) * 0.0205, sin(a2) * 0.0205, 0.012), Vector3.ZERO, false)
			_mesh(_box(Vector3(0.003, 0.016, 0.002)), _mat(Color(0.95, 0.93, 0.86), 0.4), k, Vector3(0, 0.007, 0.0245), Vector3.ZERO, false)
			k.rotation.z = deg_to_rad(_rng.randf_range(-40, 40))
			c["parts"]["knob"] = k
		"radio":
			var k2 := Node3D.new()
			k2.position = Vector3(0, -0.01, 0.026)
			root.add_child(k2)
			var km2 := _mat(Color(0.08, 0.08, 0.085), 0.4, 0.2, 0.2)
			_mesh(_cyl(0.013, 0.014, 0.016, 32), km2, k2, Vector3(0, 0, 0.008), Vector3(90, 0, 0))
			_mesh(_cyl(0.008, 0.008, 0.012, 24), km2, k2, Vector3(0, 0, 0.020), Vector3(90, 0, 0))
			c["parts"]["knob"] = k2
		"thandle":
			var sh := Node3D.new()
			root.add_child(sh)
			_mesh(_cyl(0.005, 0.005, 0.05, 16), chrome, sh, Vector3(0, 0, 0.025), Vector3(90, 0, 0))
			var red2 := _mat(Color(0.70, 0.06, 0.04), 0.35, 0.0, 0.3)
			_mesh(_capsule(0.010, 0.075), red2, sh, Vector3(0, 0, 0.052), Vector3(0, 0, 90))
			c["parts"]["shaft"] = sh
			_mesh(_cyl(0.012, 0.014, 0.006), nut, root, Vector3(0, 0, 0.0), Vector3(90, 0, 0))
	# the label-maker tape, stuck on by hand (never quite straight)
	var tape_y := -0.034
	if kind == "knob":
		tape_y = -0.047
	elif kind == "radio":
		tape_y = 0.052
	elif kind == "thandle":
		tape_y = 0.03
	elif kind == "start":
		tape_y = -0.042
	c["tape_label"] = _tape(root, tape, Vector3(0, tape_y, 0.002 if kind != "thandle" else 0.0), kind == "start")
	_ctrls.append(c)


func _tape(parent: Node3D, text: String, at: Vector3, red: bool) -> Label3D:
	var tp := Node3D.new()
	tp.position = at
	tp.rotation_degrees.z = _rng.randf_range(-3.0, 3.0)
	parent.add_child(tp)
	var px := 0.00030
	var fs := 40
	var w := float(text.length()) * fs * 0.58 * px + 0.012
	var tm := _mat(Color(0.55, 0.05, 0.04) if red else Color(0.035, 0.035, 0.04), 0.28, 0.0, 0.0)
	_mesh(_box(Vector3(w, 0.017, 0.0012)), tm, tp, Vector3.ZERO, Vector3.ZERO, false)
	var l := Label3D.new()
	l.text = text
	l.font = font()
	l.font_size = fs
	l.pixel_size = px
	l.modulate = Color(0.93, 0.92, 0.88)
	l.outline_size = 4
	l.outline_modulate = Color(0, 0, 0, 0.5)
	l.shaded = true
	l.position = Vector3(0, 0, 0.0008)
	tp.add_child(l)
	return l


## Levers on the quadrant for the sliders of the page that's open (brightness,
## volume, render scale...). Up to three; dragging one moves its slider.
func show_sliders(sliders: Array) -> void:
	for lv in _levers:
		if is_instance_valid(lv["node"]):
			lv["node"].queue_free()
	_levers.clear()
	_focus_lever = -1
	var colors := [Color(0.05, 0.05, 0.05), Color(0.12, 0.22, 0.55), Color(0.70, 0.07, 0.05)]
	var xs := [-0.055, 0.0, 0.055]
	for i in range(mini(sliders.size(), 3)):
		var sl: HSlider = sliders[i]
		var piv := Node3D.new()
		piv.position = Vector3(xs[i], 0.03, 0.0)
		_lever_root.add_child(piv)
		_mesh(_box(Vector3(0.006, 0.11, 0.008)), _mat(Color(0.6, 0.6, 0.58), 0.3, 1.0, 0.05), piv, Vector3(0, 0.055, 0))
		var kn := _mat(colors[i], 0.4, 0.0, 0.3)
		if i == 0:
			_mesh(_cyl(0.016, 0.016, 0.03, 24), kn, piv, Vector3(0, 0.115, 0), Vector3(0, 0, 90))
		elif i == 1:
			var kk := _mesh(_cyl(0.014, 0.017, 0.02, 24), kn, piv, Vector3(0, 0.118, 0))
			kk.scale = Vector3(1, 1, 1.3)
		else:
			_mesh(_sphere(0.015), kn, piv, Vector3(0, 0.118, 0))
		var lbl := _row_title(sl)
		var tl := _tape(piv, lbl, Vector3(0, 0.15, 0.0), false)
		tl.get_parent().rotation_degrees.x = -20.0
		var lv := {"node": piv, "slider": sl, "tape_label": tl}
		_levers.append(lv)
		_lever_pose(lv)
		sl.value_changed.connect(func(_v): _lever_pose(lv))


static func _row_title(sl: HSlider) -> String:
	var p := sl.get_parent()
	if p != null:
		for ch in p.get_children():
			if ch is Label:
				return String((ch as Label).text).to_upper().left(14)
	return "LEVER"


func _lever_pose(lv: Dictionary) -> void:
	var sl: HSlider = lv["slider"]
	if not is_instance_valid(sl) or not is_instance_valid(lv["node"]):
		return
	var f := 0.0 if sl.max_value <= sl.min_value else (sl.value - sl.min_value) / (sl.max_value - sl.min_value)
	# back (toward you) = low, forward = high, like a throttle
	(lv["node"] as Node3D).rotation.x = deg_to_rad(lerpf(40.0, -40.0, f))


# ------------------------------------------------------------------------------
#  Focus, the torch, input
# ------------------------------------------------------------------------------
func _ctl_pos(i: int) -> Vector3:
	return (_ctrls[i]["node"] as Node3D).global_position


func _set_focus(i: int) -> void:
	if i == _focus or i < 0 or i >= _ctrls.size():
		return
	if _focus >= 0 and _focus < _ctrls.size():
		var old: Dictionary = _ctrls[_focus]
		if is_instance_valid(old["tape_label"]):
			(old["tape_label"] as Label3D).modulate = Color(0.93, 0.92, 0.88)
		_scale_to(old["node"], 1.0)
	_focus = i
	var c: Dictionary = _ctrls[i]
	_last_focus_text = c["tape"]
	if is_instance_valid(c["tape_label"]):
		(c["tape_label"] as Label3D).modulate = Color(1.0, 0.86, 0.45)
	_scale_to(c["node"], 1.07)
	_click(0.35, 1.8)
	_update_hint()


func _scale_to(n: Node3D, s: float) -> void:
	if not is_instance_valid(n):
		return
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * s, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_hint() -> void:
	if _hint == null:
		return
	if boot:
		_hint.text = "warming up . . ."
		return
	var what := ""
	if _focus >= 0 and _focus < _ctrls.size():
		var b = _ctrls[_focus]["button"]
		what = String(b.text) if b != null and is_instance_valid(b) else String(_ctrls[_focus]["tape"])
	_hint.text = what


func _build_overlay() -> void:
	_hint = Label.new()
	_hint.add_theme_font_override("font", font())
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78, 0.85))
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -86
	_hint.offset_bottom = -54
	_hint.offset_left = -400
	_hint.offset_right = 400
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	var keys := Label.new()
	keys.text = "mouse or D-pad to choose     click / A to work it     drag a lever / LB RB"
	keys.add_theme_font_override("font", font())
	keys.add_theme_font_size_override("font_size", 14)
	keys.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6, 0.55))
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	keys.offset_top = -46
	keys.offset_bottom = -26
	keys.offset_left = -400
	keys.offset_right = 400
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(keys)
	_title = Label.new()
	_title.text = "BUSH PILOT"
	_title.add_theme_font_override("font", font())
	_title.add_theme_font_size_override("font_size", 44)
	_title.add_theme_color_override("font_color", Color(0.94, 0.52, 0.16, 0.9))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("shadow_offset_y", 3)
	_title.position = Vector2(46, 34)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	var sub := Label.new()
	sub.text = "NORTH OF SIXTY  ·  1988"
	sub.add_theme_font_override("font", font())
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.85, 0.80, 0.70, 0.6))
	sub.position = Vector2(50, 90)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub)
	_update_hint()


func _pick(mouse: Vector2) -> int:
	var best := -1
	var bd := 1e9
	var scale_px: float = size.y / 900.0
	for i in range(_ctrls.size()):
		var p: Vector3 = _ctl_pos(i)
		if _cam.is_position_behind(p):
			continue
		var sp: Vector2 = _cam.unproject_position(p)
		var d := sp.distance_to(mouse)
		if d < bd and d < 46.0 * scale_px:
			bd = d
			best = i
	return best


func _pick_lever(mouse: Vector2) -> int:
	var scale_px: float = size.y / 900.0
	for i in range(_levers.size()):
		var n: Node3D = _levers[i]["node"]
		var tip: Vector3 = n.global_transform * Vector3(0, 0.115, 0)
		if _cam.unproject_position(tip).distance_to(mouse) < 34.0 * scale_px:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if boot or _busy:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_lever >= 0:
			var lv: Dictionary = _levers[_drag_lever]
			var sl: HSlider = lv["slider"]
			if is_instance_valid(sl):
				var span := sl.max_value - sl.min_value
				sl.value = clampf(sl.value - mm.relative.y / (220.0 * size.y / 900.0) * span, sl.min_value, sl.max_value)
			accept_event()
			return
		if active:
			var i := _pick(mm.position)
			if i >= 0:
				_set_focus(i)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			var li := _pick_lever(mb.position)
			if li >= 0:
				_drag_lever = li
				_click(0.5, 0.9)
				accept_event()
				return
			if active:
				var i2 := _pick(mb.position)
				if i2 >= 0:
					_set_focus(i2)
					_work(i2)
					accept_event()
		else:
			if _drag_lever >= 0:
				_click(0.4, 1.1)
			_drag_lever = -1


func _input(event: InputEvent) -> void:
	if not visible or boot or _busy:
		return
	# levers on any page that has them: LB / RB pick one, the right stick or
	# up/down on the D-pad with a lever picked moves it
	if not _levers.is_empty() and event is InputEventJoypadButton and event.pressed:
		var jb := event as InputEventJoypadButton
		if jb.button_index == JOY_BUTTON_LEFT_SHOULDER or jb.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_focus_lever = wrapi(_focus_lever + (1 if jb.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1), 0, _levers.size())
			for j in range(_levers.size()):
				(_levers[j]["tape_label"] as Label3D).modulate = Color(1.0, 0.86, 0.45) if j == _focus_lever else Color(0.93, 0.92, 0.88)
			_click(0.4, 1.4)
			get_viewport().set_input_as_handled()
			return
	if not active:
		return
	var dir := Vector2.ZERO
	if event.is_action_pressed("ui_left"):
		dir = Vector2.LEFT
	elif event.is_action_pressed("ui_right"):
		dir = Vector2.RIGHT
	elif event.is_action_pressed("ui_up"):
		dir = Vector2.UP
	elif event.is_action_pressed("ui_down"):
		dir = Vector2.DOWN
	if dir != Vector2.ZERO:
		_nav(dir)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") and _focus >= 0:
		_work(_focus)
		get_viewport().set_input_as_handled()


## Move to the nearest control on screen in that direction.
func _nav(dir: Vector2) -> void:
	if _ctrls.is_empty():
		return
	if _focus < 0:
		_set_focus(0)
		return
	var from: Vector2 = _cam.unproject_position(_ctl_pos(_focus))
	var best := -1
	var bs := 1e9
	for i in range(_ctrls.size()):
		if i == _focus:
			continue
		var d: Vector2 = _cam.unproject_position(_ctl_pos(i)) - from
		var along := d.dot(dir)
		if along <= 4.0:
			continue
		var across := absf(d.dot(Vector2(-dir.y, dir.x)))
		var s := along + across * 2.2
		if s < bs:
			bs = s
			best = i
	if best >= 0:
		_set_focus(best)


# ------------------------------------------------------------------------------
#  Working the controls: each one moves and sounds like itself
# ------------------------------------------------------------------------------
func _work(i: int) -> void:
	var c: Dictionary = _ctrls[i]
	var b = c["button"]
	var parts: Dictionary = c["parts"]
	var tw := create_tween()
	match String(c["kind"]):
		"start":
			_busy = true
			tw.tween_callback(func(): _click(1.0, 0.7))
			tw.tween_property(parts["guard"], "rotation:x", deg_to_rad(-105), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_interval(0.18)
			tw.tween_callback(func(): _click(1.0, 0.55))
			tw.tween_property(parts["lever"], "rotation:x", deg_to_rad(68), 0.07)
			tw.tween_callback(func(): _start_sequence(b))
			return
		"toggle", "guard":
			if parts.has("guard"):
				tw.tween_callback(func(): _click(0.9, 0.8))
				tw.tween_property(parts["guard"], "rotation:x", deg_to_rad(-105), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_interval(0.10)
			tw.tween_callback(func(): _click(1.0, 0.65))
			tw.tween_property(parts["lever"], "rotation:x", deg_to_rad(68), 0.06)
			tw.tween_interval(0.14)
			tw.tween_callback(func(): _press(b))
			tw.tween_property(parts["lever"], "rotation:x", deg_to_rad(112), 0.10)
			if parts.has("guard"):
				tw.tween_property(parts["guard"], "rotation:x", 0.0, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
				tw.tween_callback(func(): _click(0.7, 0.9))
		"breaker":
			tw.tween_callback(func(): _click(1.0, 0.45))
			tw.tween_property(parts["cap"], "position:z", -0.006, 0.05)
			tw.tween_interval(0.08)
			tw.tween_callback(func(): _press(b))
			tw.tween_property(parts["cap"], "position:z", 0.004, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"knob", "radio":
			var k: Node3D = parts["knob"]
			var r0 := k.rotation.z
			for s in range(2):
				tw.tween_callback(func(): _click(0.7, 1.3))
				tw.tween_property(k, "rotation:z", r0 - deg_to_rad(30.0 * (s + 1)), 0.07)
			tw.tween_interval(0.06)
			tw.tween_callback(func(): _press(b))
		"thandle":
			tw.tween_callback(func(): _click(1.0, 0.5))
			tw.tween_property(parts["shaft"], "position:z", 0.05, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_interval(0.35)
			tw.tween_callback(func(): _press(b))


func _press(b: Variant) -> void:
	if b == null or not is_instance_valid(b):
		return
	if b is Button:
		(b as Button).pressed.emit()
	elif b.has_method("press"):
		b.press()          # the Model Lab's stand-in buttons


## START: flip the cover, flip the switch, the starter grinds, she catches -
## and the cockpit fades to black while the world finishes rendering in.
var _fade: ColorRect
var _fade_layer: CanvasLayer
func _start_sequence(b: Variant) -> void:
	var first: bool = menu != null and bool(menu.get("first_open"))
	_play_file(START_WAV, -4.0)
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 60
	_fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)
	var tw := _fade_layer.create_tween()
	tw.tween_interval(0.9 if first else 0.15)
	if first:
		tw.tween_callback(func():
			_play_file(CATCH_WAV, -2.0)
			var et := create_tween()
			et.tween_property(self, "_engine_on", 1.0, 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT))
	tw.tween_property(_fade, "color:a", 1.0, 0.9 if first else 0.25)
	tw.tween_callback(func():
		_busy = false
		_press(b)
		_settle_then_fade(first))


func _settle_then_fade(first: bool) -> void:
	var layer := _fade_layer
	var fade := _fade
	# wait (in the dark) until the world has streamed in round you, then open up
	var t0 := Time.get_ticks_msec()
	if first:
		await get_tree().create_timer(1.2, true, false, true).timeout
		while Time.get_ticks_msec() - t0 < 6000 and settle_check.is_valid() and not bool(settle_check.call()):
			await get_tree().create_timer(0.2, true, false, true).timeout
	if not is_instance_valid(layer):
		return
	var tw := layer.create_tween()
	tw.tween_property(fade, "color:a", 0.0, 1.4 if first else 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(layer.queue_free)


# ------------------------------------------------------------------------------
#  Weather: rain that comes and goes in sheets, gusts that rock the plane and
#  lean the rain and the runs on the glass, lightning with thunder after it.
# ------------------------------------------------------------------------------
var _outside: Node3D
var _light_mats: Array = []
var _glass: MeshInstance3D
var _flood: OmniLight3D
var _dome: OmniLight3D
var _tv := {}                     # live-tuned values, easing toward tools/tune.cfg

## A live-tuned number/vector (Tune): eases toward the file's value at ~6/s.
func _tune(key: String, default: Variant, delta: float) -> Variant:
	var want: Variant = Tune.v("cockpit", key, default)
	if not _tv.has(key) or typeof(_tv[key]) != typeof(want):
		_tv[key] = want
	else:
		var k := clampf(delta * 6.0, 0.0, 1.0)
		if want is float or want is int:
			_tv[key] = lerpf(float(_tv[key]), float(want), k)
		elif want is Vector3 or want is Vector2 or want is Color:
			_tv[key] = _tv[key].lerp(want, k)
		else:
			_tv[key] = want
	return _tv[key]


func _apply_tuning(delta: float) -> void:
	Tune.poll(delta)
	var cp: Vector3 = _tune("cam_pos", CAM_POS, delta)
	var cl: Vector3 = _tune("cam_look", Vector3(0.02, 1.16, -0.9), delta)
	_cam_base = Transform3D(Basis.looking_at(cl - cp, Vector3.UP), cp)
	_cam.fov = _tune("fov", 54.0, delta)
	_flood.light_energy = _tune("flood", 0.10, delta)
	_dome.light_energy = _tune("dome", 0.18, delta)
	_torch.light_energy = _tune("torch", 2.6, delta)
	_torch.spot_angle = _tune("torch_angle", 8.5, delta)
	_env.tonemap_exposure = _tune("exposure", 1.05, delta)
	_env.fog_density = _tune("fog", 0.0045, delta)
	_env.volumetric_fog_density = _tune("haze", 0.018, delta)
	_env.glow_intensity = _tune("glow", 0.9, delta)
	_env.ambient_light_energy = _tune("ambient", 0.25, delta) + _flash * 1.6
	_glass_mat.set_shader_parameter("haze_lod", _tune("glass_blur", 2.6, delta))
	_glass_mat.set_shader_parameter("tint", _tune("glass_tint", Color(0.62, 0.68, 0.76), delta))
	_outside.position.y = _tune("outside_y", 0.0, delta)
	_panel.position = _tune("panel_pos", PANEL_POS, delta)
	_panel.rotation_degrees.x = _tune("panel_tilt", PANEL_TILT, delta)
	var lg: float = _tune("runway_glow", 7.0, delta)
	for m in _light_mats:
		(m as StandardMaterial3D).emission_energy_multiplier = lg
	_glass.visible = bool(Tune.v("cockpit", "glass_on", true))
	_glass_mat.set_shader_parameter("sheen", _tune("bead_sheen", 0.35, delta))
	_glass_mat.set_shader_parameter("bead_size", _tune("bead_size", 1.0, delta))
	_glass_mat.set_shader_parameter("rain", _rain_amt * float(_tune("glass_wet", 1.0, delta)))


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_apply_tuning(delta)
	# gusts: a new target every few seconds, eased toward; a gust brings a sheet of rain
	_gust_t -= delta
	if _gust_t <= 0.0:
		_gust_t = _rng.randf_range(1.5, 5.5)
		_gust_target = _rng.randf_range(-1.0, 1.0) * (1.0 if _rng.randf() < 0.55 else 0.25)
		_rain_target = clampf(0.55 + absf(_gust_target) * 0.5 + _rng.randf_range(-0.15, 0.15), 0.3, 1.0)
	_gust = lerpf(_gust, _gust_target, clampf(delta * 1.4, 0.0, 1.0))
	_rain_amt = lerpf(_rain_amt, _rain_target, clampf(delta * 0.6, 0.0, 1.0))
	var buffet := sin(_t * 7.3) * 0.5 + sin(_t * 11.9) * 0.3 + sin(_t * 3.1) * 0.6
	var g := absf(_gust)
	# the plane rocks on its gear: a slow roll with the gust, a shiver in it
	var roll := _gust * 0.012 + buffet * 0.0025 * g
	var pitch := sin(_t * 0.7) * 0.0015 + buffet * 0.0012 * g
	var breathe := sin(_t * 0.9) * 0.0018
	_cam.transform = _cam_base * Transform3D(Basis.from_euler(Vector3(pitch + breathe * 0.4, breathe * 0.3, roll)), Vector3(0, breathe * 0.01, 0))
	if _glass_mat != null:
		_glass_mat.set_shader_parameter("wet_time", _t)
		_glass_mat.set_shader_parameter("wind", _gust)
	if _rain != null:
		var pm: ParticleProcessMaterial = _rain.process_material
		pm.gravity = Vector3(_gust * 9.0, -4.0, 0)
		_rain.amount_ratio = _rain_amt
	if _wind_snd != null:
		_wind_snd.volume_db = lerpf(-32.0, -16.0, g)
		_wind_snd.pitch_scale = 0.8 + g * 0.35
	if _rain_snd != null:
		_rain_snd.volume_db = lerpf(-28.0, -17.0, _rain_amt) + float(Tune.v("cockpit", "rain_db", 0.0))
	# the beacon: a green and a white sweep, round every 4 s
	if _beacon_mat != null:
		var ph := fmod(_t / 2.0, 1.0)
		var on := exp(-pow((ph - 0.5) * 9.0, 2.0))
		_beacon_mat.emission = Color(0.4, 1.0, 0.55) if fmod(_t, 4.0) < 2.0 else Color(1.0, 0.95, 0.85)
		_beacon_mat.emission_energy_multiplier = on * 14.0
	# lightning: a flicker of two or three strokes; the thunder comes later the farther it is
	_flash_t -= delta
	if _flash_t <= 0.0:
		_flash_t = _rng.randf_range(9.0, 26.0)
		var dist := _rng.randf_range(1.5, 9.0)            # km
		_lightning(dist)
	_flash = maxf(_flash - delta * 9.0, 0.0)
	if _sky_light != null:
		_sky_light.light_energy = 0.04 + _flash * 3.2
	if _env != null:
		_env.background_color = Color(0.010, 0.013, 0.020).lerp(Color(0.32, 0.36, 0.48), _flash * 0.6)
	if _thunder_in > 0.0:
		_thunder_in -= delta
		if _thunder_in <= 0.0 and _thunder != null:
			_thunder.volume_db = _thunder_vol
			_thunder.pitch_scale = _rng.randf_range(0.8, 1.05)
			_thunder.play()
	# the torch follows what you're on
	if _torch != null and _focus >= 0 and _focus < _ctrls.size():
		var want := _torch.global_transform.looking_at(_ctl_pos(_focus), Vector3.UP)
		_torch.global_transform = _torch.global_transform.interpolate_with(want, clampf(delta * 9.0, 0.0, 1.0))
	if _radio_digits != null:
		# the old display flickers now and then
		_radio_digits.modulate.a = 0.7 + 0.3 * sin(_t * 40.0) if int(_t * 0.5) % 9 == 0 else 1.0


func _lightning(dist_km: float) -> void:
	var near := clampf(1.0 - (dist_km - 1.5) / 7.5, 0.0, 1.0)
	var tw := create_tween()
	var strokes := _rng.randi_range(2, 4)
	for s in range(strokes):
		var e := lerpf(0.35, 1.0, near) * _rng.randf_range(0.6, 1.0)
		tw.tween_callback(func(): _flash = e)
		tw.tween_interval(_rng.randf_range(0.05, 0.16))
	_sky_light.rotation_degrees = Vector3(_rng.randf_range(-55, -20), _rng.randf_range(100, 260), 0)
	_thunder_in = dist_km * 2.9                 # sound: ~3 s a km
	_thunder_vol = lerpf(-20.0, -3.0, near)


# ------------------------------------------------------------------------------
#  Sound: made here (rain on aluminium, wind, a switch click, thunder)
# ------------------------------------------------------------------------------
const RATE := 22050

## Rain, wind and thunder are outside: heard through the cabin's aluminium,
## muffled (a low-pass bus), the rain more drum than hiss (Dave: "need to sound
## like you're in the plane").
static func _cabin_bus() -> String:
	var name := "CabinMuffle"
	if AudioServer.get_bus_index(name) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 900.0
		lp.resonance = 0.6
		AudioServer.add_bus_effect(i, lp)
	return name


func _build_sounds() -> void:
	_sfx = AudioStreamPlayer.new()
	_sfx.max_polyphony = 6
	add_child(_sfx)
	_rain_snd = _loop_player(_rain_loop(), -20.0)
	_wind_snd = _loop_player(_wind_loop(), -26.0)
	_rain_snd.bus = _cabin_bus()
	_wind_snd.bus = _cabin_bus()
	_thunder = AudioStreamPlayer.new()
	_thunder.bus = _cabin_bus()
	_thunder.stream = _thunder_shot()
	add_child(_thunder)
	_clicks = [_click_shot(0), _click_shot(1), _click_shot(2)]


var _clicks: Array = []

func _click(vol: float, pitch: float) -> void:
	if _sfx == null or _clicks.is_empty():
		return
	_sfx.stream = _clicks[_rng.randi_range(0, _clicks.size() - 1)]
	_sfx.volume_db = linear_to_db(maxf(vol, 0.01)) - 4.0
	_sfx.pitch_scale = pitch * _rng.randf_range(0.95, 1.05)
	_sfx.play()


func _play_file(path: String, db: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _loop_player(st: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = db
	p.autoplay = true
	add_child(p)
	return p


static func _wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in range(buf.size()):
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = buf.size()
	return w


func _rain_loop() -> AudioStreamWAV:
	var n := RATE * 3
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in range(n):
		var w := r.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.10
		buf[i] = lp * 0.30
	# drops on the skin: little ticks, thousands of them
	for d in range(2600):
		var at := r.randi_range(0, n - 200)
		var a := r.randf_range(0.04, 0.3)
		var f := r.randf_range(380.0, 1300.0)          # drops thudding on aluminium
		for j in range(160):
			buf[at + j] += sin(TAU * f * float(j) / RATE) * a * exp(-float(j) / 30.0)
	# crossfade the ends so the loop has no seam
	var xf := 2000
	for i in range(xf):
		var k := float(i) / xf
		buf[n - xf + i] = buf[n - xf + i] * (1.0 - k) + buf[i] * k
	return _wav(buf, true)


func _wind_loop() -> AudioStreamWAV:
	var n := RATE * 4
	var buf := PackedFloat32Array()
	buf.resize(n)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var a := 0.0
	var b2 := 0.0
	for i in range(n):
		var w := r.randf_range(-1.0, 1.0)
		a += (w - a) * 0.02          # low moan
		b2 += (w - b2) * 0.12        # hiss past the struts
		var t := float(i) / RATE
		buf[i] = a * 2.2 * (0.7 + 0.3 * sin(TAU * 0.25 * t)) + b2 * 0.18
	var xf := 3000
	for i in range(xf):
		var k := float(i) / xf
		buf[n - xf + i] = buf[n - xf + i] * (1.0 - k) + buf[i] * k
	return _wav(buf, true)


func _click_shot(v: int) -> AudioStreamWAV:
	var n := int(RATE * 0.09)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var r := RandomNumberGenerator.new()
	r.seed = 100 + v
	var f: float = [2400.0, 1700.0, 3100.0][v]
	for i in range(n):
		var t := float(i) / RATE
		var snap := r.randf_range(-1.0, 1.0) * exp(-t * 900.0)
		var body := sin(TAU * f * t) * exp(-t * 160.0) * 0.6 + sin(TAU * 180.0 * t) * exp(-t * 60.0) * 0.5
		buf[i] = (snap * 0.8 + body) * 0.7
	return _wav(buf, false)


func _thunder_shot() -> AudioStreamWAV:
	var n := RATE * 6
	var buf := PackedFloat32Array()
	buf.resize(n)
	var r := RandomNumberGenerator.new()
	r.seed = 23
	var a := 0.0
	var b2 := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var w := r.randf_range(-1.0, 1.0)
		a += (w - a) * 0.008
		b2 += (w - b2) * 0.05
		# a crack, then rolling rumble in swells
		var env := (1.0 - exp(-t * 8.0)) * exp(-t * 0.55) * (0.6 + 0.4 * sin(TAU * 0.7 * t + sin(t * 2.3)))
		buf[i] = (a * 9.0 + b2 * 0.6 * exp(-t * 2.0)) * env
	return _wav(buf, false)
