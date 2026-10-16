extends CanvasLayer
## The vehicle and item picker (Dave: "a vehicle selector menu and an inventory
## selector"). F10 opens or closes it; Esc closes it. The game pauses while
## it's open.
##   VEHICLES: click one and it's brought in front of you and you're in it
##             (the plane: you're put in its seat where it stands).
##   ITEMS:    click an item to put one in your inventory, right-click for a
##             full stack (what won't fit goes at your feet). Your hotbar and
##             backpack are listed on the right: click a hotbar slot to hold
##             it, the x drops it at your feet.

var main: Node
var _box: PanelContainer
var _tabs: TabContainer
var _carry_list: VBoxContainer
var _carry_head: Label
var _note: Label

const ORANGE := Color(0.82, 0.36, 0.10)

## [label, what it is, key]
const VEHICLES := [
	["STORY: THE FIRE", "The 15-minute story opening (plays on a copy of your save)", "story"],
	["Super Cub", "The new red and white Cub: you're put in its seat", "supercub"],
	["Bush plane", "Your plane (whatever type it is now), where it's parked", "plane"],
	["Pickup", "8 ft bed, hitch and winch", "pickup"],
	["Short SUV", "2-door 4x4, removable white top", "blazer"],
	["Big SUV", "4-door, long roof, three rows", "suburban"],
	["Water truck", "4,000 gal: fills at water, sprays", "water"],
	["Fuel truck", "Diesel and avgas for everything else", "fuel"],
	["Wheel loader", "Bucket or forks", "loader"],
	["Dozer", "Blade, ripper; cuts and spreads ground", "dozer"],
	["Excavator", "Digs, loads, dumps where you want", "excavator"],
	["Tunnel miner", "Drives drifts into a bank", "miner"],
	["Plane tug", "Tows the plane by its tailwheel", "tug"],
	["Forklift", "Yard forklift", "forklift"],
	["Log trailer", "Brought to you to hitch up", "trailer"],
]


func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.04, 0.94)
	sb.border_color = ORANGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	_box.add_theme_stylebox_override("panel", sb)
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.custom_minimum_size = Vector2(1180, 720)
	_box.position = Vector2(-590, -360)
	add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_box.add_child(v)
	var title := Label.new()
	title.text = "GARAGE AND GEAR      (F10 or Esc to close)"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", ORANGE)
	v.add_child(title)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 18)
	v.add_child(_tabs)
	_tabs.add_child(_vehicle_tab())
	_tabs.add_child(_item_tab())
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 16)
	_note.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	v.add_child(_note)
	_box.visible = false
	if "--garage-test" in OS.get_cmdline_user_args():
		_self_test()


## Safety net: with no menu open the world must be drawn (a grey screen otherwise).
func _process(_dt: float) -> void:
	var vp := get_viewport()
	if vp != null and vp.disable_3d and main != null and main.menu != null and not main.menu.is_open:
		vp.disable_3d = false


func is_open() -> bool:
	return _box.visible


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_F10 or (k == KEY_ESCAPE and _box.visible):
			_toggle()
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	_box.visible = not _box.visible
	if _box.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = true
		_note.text = "Pick a vehicle to drive, or items to carry."
		_refresh_carry()
	else:
		var con = main.get_node_or_null("Console")
		if not (main.menu.is_open or (con != null and con.is_open())):
			get_tree().paused = false


# ---------------------------------------------------------------- vehicles

func _vehicle_tab() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "Vehicles"
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(g)
	for e in VEHICLES:
		var b := Button.new()
		b.text = "%s\n%s" % [e[0], e[1]]
		b.custom_minimum_size = Vector2(370, 84)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 17)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_pick_vehicle.bind(String(e[2]), String(e[0])))
		g.add_child(b)
	return sc


func _pick_vehicle(key: String, label: String) -> void:
	var con = main.get_node_or_null("Console")
	_toggle()                      # close and unpause first: the machines settle on the ground
	if key == "story":
		main.start_story()
		return
	if key == "supercub":
		if main.driving != null:
			main._get_off_forklift()
		if not main.on_foot:
			main._toggle_foot()
		if main.plane.plane_type != "supercub":
			main.plane.apply_type("supercub")
			main._apply_plane_type()
		key = "plane"
	if key == "plane":
		if main.driving != null:
			main._get_off_forklift()
		if main.on_foot:
			main._get_in(false)
		main.hud.push_message("In the plane.", 3.0)
		return
	if key in ["pickup", "blazer", "suburban"]:
		_set_truck_style(key)
		key = "pickup"
	if key == "forklift":
		if main.forklifts.is_empty():
			main.hud.push_message("No forklift on this map.", 3.0)
			return
		_bring(main.forklifts[0])
		if main.driving != null:
			main._get_off_forklift()
		if not main.on_foot:
			main._toggle_foot()
		main._get_on_forklift(main.forklifts[0])
		main.hud.push_message("On the forklift.", 3.0)
		return
	if con == null:
		return
	if key in ["pickup", "water", "fuel", "loader", "tug", "trailer"]:
		con._run("bring " + key)
	if key != "trailer":
		con._run("in " + key)
	main.hud.push_message("%s: ready." % label, 3.0)


## Bring a machine with no console shortcut in front of you.
func _bring(veh: Node3D) -> void:
	var wp: Vector3 = main.walker.global_position
	var fw := Basis(Vector3.UP, main.walker.yaw) * Vector3(0, 0, -1)
	var at := wp + fw * 6.0
	at.y = main.world.terrain.ground_level_at(at.x, at.z)
	var xf := Transform3D(Basis(Vector3.UP, main.walker.yaw), at)
	if veh.has_method("park"):
		veh.park(xf)
	else:
		veh.global_transform = xf


## The pickup, short SUV and big SUV are one truck built three ways: rebuild
## it as the one picked (the old one goes, unhitched).
func _set_truck_style(style: String) -> void:
	var old: Node3D = main.pickup
	var want := "" if style == "pickup" else style
	if old != null and String(old.get("variant")) == want:
		return
	if main.driving == old:
		main._get_off_forklift()
	var xf: Transform3D = old.global_transform if old != null else Transform3D.IDENTITY
	if old != null:
		var tw = old.get("towing")
		if tw != null:
			tw.towed_by = null
			old.set("towing", null)
		main.remove_child(old)
		old.queue_free()
	var p: Node3D = load("res://scripts/pickup_truck.gd").new()
	p.variant = want
	p.name = "Pickup"
	p.terrain = main.world.terrain
	p.towables = func() -> Array: return main.prospect.towables
	p.bed_load = func() -> float: return main.cargo.truck_load_kg()
	main.add_child(p)
	p.build()
	p.setup_parts()
	p.park(xf)
	main.pickup = p
	var trucks: Array = main.cargo.trucks
	if trucks.size() > 0:
		trucks[0] = p
	main.cargo.trucks = trucks


# ---------------------------------------------------------------- items

func _item_tab() -> Control:
	var h := HBoxContainer.new()
	h.name = "Items"
	h.add_theme_constant_override("separation", 14)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_stretch_ratio = 2.0
	h.add_child(sc)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(g)
	var items: Dictionary = main.inv.ITEMS
	for id in items.keys():
		var spec: Array = items[id]
		var b := Button.new()
		b.text = "%s\n%.1f kg%s" % [spec[0], float(spec[1]), ("   (stack %d)" % int(spec[2])) if int(spec[2]) > 1 else ""]
		b.tooltip_text = String(spec[3])
		b.custom_minimum_size = Vector2(240, 64)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.gui_input.connect(_item_click.bind(String(id)))
		g.add_child(b)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	h.add_child(right)
	_carry_head = Label.new()
	_carry_head.add_theme_font_size_override("font_size", 17)
	_carry_head.add_theme_color_override("font_color", ORANGE)
	right.add_child(_carry_head)
	var sc2 := ScrollContainer.new()
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sc2)
	_carry_list = VBoxContainer.new()
	_carry_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(_carry_list)
	return h


func _item_click(event: InputEvent, id: String) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	var inv: Node = main.inv
	var want: int = int(inv.spec(id)[2]) if mb.button_index == MOUSE_BUTTON_RIGHT else 1
	var put: int = inv.add(id, want, true)
	var left := want - put
	if left > 0:
		var p: Vector3 = main.walker.global_transform * Vector3(0.4, 0, -0.9)
		p.y = main.world.terrain.ground_level_at(p.x, p.z)
		inv.place_in_world(id, left, p, main.walker.yaw)
	_note.text = "%s: %d in your inventory%s." % [inv.item_name(id), put, (", %d at your feet (too heavy / no room)" % left) if left > 0 else ""]
	_refresh_carry()


func _refresh_carry() -> void:
	if _carry_list == null:
		return
	for c in _carry_list.get_children():
		c.queue_free()
	var inv: Node = main.inv
	_carry_head.text = "CARRYING  %.1f / %.0f kg   (in hand: %s)" % [inv.weight(), inv.MAX_KG, inv.item_name(inv.in_hand()) if inv.in_hand() != "" else "nothing"]
	for i in range(inv.slots.size()):
		var s: Dictionary = inv.slots[i]
		var row := HBoxContainer.new()
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		var where := ("Hotbar %d" % (i + 1)) if i < inv.HOTBAR else ("Pack %d" % (i - inv.HOTBAR + 1))
		if s.is_empty():
			b.text = "%s:  -" % where
			b.disabled = true
		else:
			b.text = "%s:  %s  x%d%s" % [where, inv.item_name(String(s["id"])), int(s["n"]), "   < in hand" if i == inv.active else ""]
			if i < inv.HOTBAR:
				b.pressed.connect(func() -> void:
					inv.select(i)
					_refresh_carry())
			else:
				b.tooltip_text = "Backpack: drag it to the hotbar in the game's backpack screen (Tab) to hold it."
		row.add_child(b)
		if not s.is_empty():
			var x := Button.new()
			x.text = " x "
			x.tooltip_text = "Drop it at your feet"
			x.pressed.connect(func() -> void:
				var id := String(s["id"])
				var n := int(s["n"])
				inv.slots[i] = {}
				inv._touch()
				var p: Vector3 = main.walker.global_transform * Vector3(0.4, 0, -0.9)
				p.y = main.world.terrain.ground_level_at(p.x, p.z)
				inv.place_in_world(id, n, p, main.walker.yaw)
				_note.text = "Dropped %s x%d at your feet." % [inv.item_name(id), n]
				_refresh_carry())
			row.add_child(x)
		_carry_list.add_child(row)


## Headless self-test: godot --headless --path . -- --garage-test
func _self_test() -> void:
	await get_tree().create_timer(4.0).timeout
	print("GARAGE TEST: open")
	_toggle()
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_RIGHT
	_item_click(ev, "timber")
	ev.button_index = MOUSE_BUTTON_LEFT
	_item_click(ev, "shovel")
	_item_click(ev, "pump")
	print("GARAGE TEST: ", _note.text, " | ", _carry_head.text)
	for k in ["blazer", "suburban", "pickup", "excavator", "dozer", "water", "loader", "forklift", "tug", "plane"]:
		if not _box.visible:
			_toggle()
		_pick_vehicle(k, k)
		await get_tree().create_timer(1.0).timeout
		print("GARAGE TEST: ", k, " driving=", main.driving.name if main.driving != null else "-", " on_foot=", main.on_foot, " pickup variant=", main.pickup.variant)
	print("GARAGE TEST: done")
	get_tree().quit()
