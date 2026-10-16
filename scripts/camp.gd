extends Node3D
## Bush camp life: the campfire, the cooler of beer, smokes, sleeping in the
## tent, and what too many beers do to you (on your feet and at the controls).
##
## Drunk is kept as blood alcohol, like the real thing: about 0.02 a beer,
## wearing off at 0.004 a minute (faster than real, so a session isn't spent
## waiting; sleeping in the tent clears it). 0.05 you feel it,
## 0.08 is over the limit, 0.15 you're stumbling, 0.25 you pass out.

const Builds = preload("res://scripts/builds.gd")

var main: Node
var builds: Node
var walker: Node3D
var hud: Control
var drunk := 0.0             # blood alcohol, %
var beers := 0               # in the cooler at your camp
var smokes := 20             # cigarettes in your pocket
var smoking := 0.0           # seconds left on the one you're smoking
var prompt := ""             # what the interact key does here, or ""
var _target := ""
var _t := 0.0
var _sip := 0.0              # drinking animation, seconds left
var _puff := 0.0
var _passed_out := 0.0
var _fires: Array = []       # [node, light]
var _smoke: CPUParticles3D
var _can: MeshInstance3D
var _cig: MeshInstance3D
var _ember: OmniLight3D

const BEER := 0.022
const COOLER_FULL := 24


func _ready() -> void:
	builds.camp_changed.connect(func():
		_rebuild_fires()
		if not builds.bush_camp().is_empty():
			restock())
	_rebuild_fires()
	_load()
	_smoke = CPUParticles3D.new()
	_smoke.emitting = false
	_smoke.amount = 40
	_smoke.lifetime = 3.0
	_smoke.local_coords = false
	_smoke.direction = Vector3(0, 0.3, -1)
	_smoke.spread = 25.0
	_smoke.initial_velocity_min = 0.25
	_smoke.initial_velocity_max = 0.5
	_smoke.gravity = Vector3(0, 0.25, 0)
	_smoke.scale_amount_min = 0.6
	_smoke.scale_amount_max = 1.4
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.85, 0.85, 0.88, 0.22)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.material = smat
	_smoke.mesh = sm
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 2.5))
	_smoke.scale_amount_curve = grow
	add_child(_smoke)
	# What you hold up to your face: a can, a cigarette with a glowing tip.
	_can = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.033
	cm.bottom_radius = 0.033
	cm.height = 0.122
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.70, 0.12, 0.10)
	cmat.metallic = 0.8
	cmat.roughness = 0.3
	cm.material = cmat
	_can.mesh = cm
	_can.visible = false
	add_child(_can)
	_cig = MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.004
	gm.bottom_radius = 0.004
	gm.height = 0.08
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.95, 0.93, 0.88)
	gm.material = gmat
	_cig.mesh = gm
	_cig.visible = false
	add_child(_cig)
	_ember = OmniLight3D.new()
	_ember.light_color = Color(1.0, 0.45, 0.15)
	_ember.light_energy = 0.0
	_ember.omni_range = 0.4
	_cig.add_child(_ember)
	_ember.position = Vector3(0, 0.04, 0)


# ------------------------------------------------------------------------------
#  The fire
# ------------------------------------------------------------------------------
func _rebuild_fires() -> void:
	for f in _fires:
		(f[0] as Node).queue_free()
	_fires.clear()
	var it: Dictionary = builds.bush_camp()
	if it.is_empty():
		return
	var made := make_fire()
	var root: Node3D = made[0]
	add_child(root)
	root.global_position = builds.camp_point(Vector3.ZERO)
	_fires.append(made)


## Flames, firelight and sparks: [root node, light].
static func make_fire() -> Array:
	var root := Node3D.new()
	root.name = "Campfire"
	# Flames: a few glowing cones, flickered in _process.
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in range(4):
		var fl := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.16 - 0.025 * k
		cone.height = 0.55 - 0.08 * k
		cone.radial_segments = 6
		cone.material = fmat
		fl.mesh = cone
		var a := TAU * float(k) / 4.0
		fl.position = Vector3(cos(a) * 0.08, 0.32, sin(a) * 0.08)
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fl)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.28)
	light.light_energy = 2.2
	light.omni_range = 9.0
	light.shadow_enabled = true
	light.position = Vector3(0, 0.6, 0)
	root.add_child(light)
	var embers := CPUParticles3D.new()
	embers.amount = 16
	embers.lifetime = 1.6
	embers.direction = Vector3.UP
	embers.spread = 20.0
	embers.initial_velocity_min = 0.8
	embers.initial_velocity_max = 1.6
	embers.gravity = Vector3(0, 0.3, 0)
	var em := SphereMesh.new()
	em.radius = 0.012
	em.height = 0.024
	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.albedo_color = Color(1.0, 0.6, 0.2)
	em.material = emat
	embers.mesh = em
	embers.position = Vector3(0, 0.3, 0)
	root.add_child(embers)
	return [root, light]


# ------------------------------------------------------------------------------
#  What you can do here
# ------------------------------------------------------------------------------
func _near(local: Vector3, r: float) -> bool:
	var p: Vector3 = builds.camp_point(local)
	if p == Vector3.INF:
		return false
	var w: Vector3 = walker.global_position
	return Vector2(w.x - p.x, w.z - p.z).length() < r


## Called every frame on foot (main.gd): sets `prompt`.
func find_target() -> void:
	_target = ""
	prompt = ""
	if builds.bush_camp().is_empty() or _sip > 0.0:
		return
	var key: String = Game.hint("interact")
	if _near(Builds.CAMP_COOLER, 1.4):
		_target = "beer"
		prompt = "%s  Grab a beer (%d left)" % [key, beers] if beers > 0 else "The cooler's empty. Fly in some more beer."
		if beers <= 0:
			_target = ""
	elif _near(Builds.CAMP_TENT, 2.0):
		_target = "sleep"
		prompt = "%s  Crawl in the tent and sleep till morning" % key
	elif _near(Vector3.ZERO, 2.2):
		_target = "fire"
		prompt = ("Warm by the fire.  %s  Have a smoke (%d left)" % [Game.hint("smoke"), smokes]) if Game.SMOKING else "Warm by the fire."


func interact() -> bool:
	match _target:
		"beer":
			beers -= 1
			_sip = 3.0
			drunk += BEER
			_say(_beer_line())
			_save()
			return true
		"sleep":
			_sleep()
			return true
	return false


func light_up() -> void:
	if smoking > 0.0:
		_say("Already got one going.")
		return
	if smokes <= 0:
		_say("Out of smokes.")
		return
	smokes -= 1
	smoking = 75.0
	_puff = 2.0
	_say("You light one up. %d left in the pack." % smokes if smokes > 0 else "Your last one. Make it count.")
	_save()


func _sleep() -> void:
	var was := drunk
	Game.time_of_day = 7.0
	Game.notify_changed()
	drunk = 0.0
	walker.warmth = 1.0
	walker.health = minf(walker.health + 0.5, 1.0)
	_say("You sleep it off. Morning, %s." % ("and your head is pounding" if was > 0.1 else "fresh as a daisy"))
	_save()


func _beer_line() -> String:
	if drunk < 0.03:
		return "Crack. That first one's always the best."
	if drunk < 0.06:
		return "Feeling good."
	if drunk < 0.09:
		return "You're over the limit now. Maybe don't fly."
	if drunk < 0.15:
		return "The trees are moving a bit."
	if drunk < 0.22:
		return "Hammered. Walking is getting hard."
	return "You're about to pass out."


## A word for the HUD, or "".
func state_text() -> String:
	if drunk < 0.03:
		return ""
	if drunk < 0.06:
		return "BUZZED"
	if drunk < 0.10:
		return "DRUNK"
	if drunk < 0.18:
		return "VERY DRUNK"
	return "HAMMERED"


# ------------------------------------------------------------------------------
#  What it does to you
# ------------------------------------------------------------------------------
## Extra stick and pedal the drunk pilot puts in without meaning to:
## Vector3(pitch, roll, yaw), added to the real inputs.
func control_wobble() -> Vector3:
	var d := clampf((drunk - 0.03) / 0.15, 0.0, 1.5)
	if d <= 0.0:
		return Vector3.ZERO
	return Vector3(sin(_t * 0.9) * 0.6 + sin(_t * 2.3) * 0.4, sin(_t * 0.7 + 1.0) * 0.6 + sin(_t * 1.9) * 0.4,
		sin(_t * 0.5 + 2.0)) * 0.22 * d


## Sideways drift and slowness walking.
func walk_wobble(move: Vector2) -> Vector2:
	var d := clampf((drunk - 0.04) / 0.14, 0.0, 1.5)
	if d <= 0.0 or move.length() < 0.1:
		return move
	return move + Vector2(sin(_t * 1.3) * 0.7 + sin(_t * 3.1) * 0.3, 0.0) * 0.6 * d


## How the view sways (applied to the camera after it is placed).
func camera_sway(xf: Transform3D) -> Transform3D:
	var d := clampf((drunk - 0.03) / 0.12, 0.0, 1.6)
	if _passed_out > 0.0:
		d = 2.0
	if d <= 0.0 and _sip <= 0.0:
		return xf
	var roll := (sin(_t * 0.55) * 0.07 + sin(_t * 1.4) * 0.02) * d
	var yaw := sin(_t * 0.37 + 1.0) * 0.04 * d
	var pitch := sin(_t * 0.8) * 0.02 * d
	if _sip > 0.0:
		pitch += 0.25 * sin(clampf(_sip / 3.0, 0.0, 1.0) * PI)    # head back for a swig
	return Transform3D(xf.basis * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll), xf.origin)


func _process(delta: float) -> void:
	_t += delta
	# Sobering up: about 0.004 a minute (time of day doesn't run on its own).
	drunk = maxf(drunk - 0.004 / 60.0 * delta, 0.0)
	if drunk > 0.25 and _passed_out <= 0.0:
		_passed_out = 8.0
		_say("You pass out.")
	if _passed_out > 0.0:
		_passed_out -= delta
		hud.blackout = clampf(_passed_out / 2.0, 0.0, 1.0)
		if _passed_out <= 0.0:
			hud.blackout = 0.0
			drunk = 0.18
			_say("You come round on the ground. Ugh.")
	# The fire flickers.
	for f in _fires:
		var l: OmniLight3D = f[1]
		l.light_energy = 2.0 + 0.5 * sin(_t * 13.0) + 0.3 * sin(_t * 31.0 + 1.0)
		var root: Node3D = f[0]
		for c in root.get_children():
			if c is MeshInstance3D:
				c.scale = Vector3(1.0, 0.85 + 0.25 * absf(sin(_t * 9.0 + c.position.x * 40.0)), 1.0)
		if walker != null and walker.visible and root.global_position.distance_to(walker.global_position) < 4.0:
			walker.warm_in_cabin(delta * 5.0, true)
	_update_hands(delta)


## The can or the cigarette, held up in front of the face, and the smoke.
func _update_hands(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var head: Transform3D = cam.global_transform
	var on_foot: bool = walker != null and walker.visible
	if on_foot and not walker.first_person:
		var e: Vector3 = walker.global_transform * (walker.model.eye_local() as Vector3)
		head = Transform3D(Basis(Vector3.UP, walker.yaw), e)
	if _sip > 0.0:
		_sip -= delta
		var lift := sin(clampf(_sip / 3.0, 0.0, 1.0) * PI)
		_can.visible = true
		_can.global_transform = head * Transform3D(Basis(Vector3.RIGHT, 0.6 + 0.9 * lift), Vector3(0.06, -0.16 + 0.1 * lift, -0.22))
	else:
		_can.visible = false
	if smoking > 0.0:
		smoking -= delta
		_cig.visible = true
		_puff -= delta
		var drag := _puff < 0.0 and _puff > -1.2
		var at_mouth := Vector3(0.0, -0.09, -0.10) if drag else Vector3(0.14, -0.22, -0.28)
		_cig.global_transform = head * Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.FORWARD, 0.3), at_mouth)
		_ember.light_energy = 1.2 if drag else 0.4
		# Breathe it out a moment after the drag.
		_smoke.global_transform = head * Transform3D(Basis.IDENTITY, Vector3(0, -0.08, -0.12))
		_smoke.emitting = _puff < -1.6 and _puff > -3.0
		if _puff < -6.0:
			_puff = randf_range(0.0, 2.0)
		if smoking <= 0.0:
			_say("You flick the butt away.")
	else:
		_cig.visible = false
		_smoke.emitting = false
		_ember.light_energy = 0.0


func _say(t: String) -> void:
	if hud != null:
		hud.push_message(t, 3.5)


# ------------------------------------------------------------------------------
#  Saving (the cooler and your pack go with the career)
# ------------------------------------------------------------------------------
const SAVE := "user://camp.cfg"


## A new camp comes with a full cooler and a fresh pack.
func restock() -> void:
	beers = COOLER_FULL
	smokes = maxi(smokes, 20)
	_save()


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("camp", "beers", beers)
	cf.set_value("camp", "smokes", smokes)
	cf.set_value("camp", "drunk", drunk)
	cf.save(SAVE)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	beers = int(cf.get_value("camp", "beers", 0))
	smokes = int(cf.get_value("camp", "smokes", 20))
	drunk = float(cf.get_value("camp", "drunk", 0.0))
