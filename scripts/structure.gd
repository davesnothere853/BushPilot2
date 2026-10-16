extends Node3D
## A building that can be crashed into and come apart the way it's built
## (DESIGN_NOTES 229, Dave: "every building... simulate the material and how
## it's built and comes apart if crashed into"; "build the building to have
## structure and supports physics").
##
## Add one as a child of an asset built with pieces (Kits.piece): each piece
## is a member (post, girt, header, truss, purlin), a panel (sheet steel,
## plywood, glass) or a block, with its material (materials.gd), its real
## size, what it's fastened to (links) and whether it stands in the ground.
##
## Hit it (hit(), or probe() from a vehicle's collision): every piece the
## impact reaches takes the energy it can: one that can't hold breaks free
## (member snaps, sheet tears off its screws, glass shatters) and flies off as
## debris with the impact's speed; the vehicle loses what was spent. Then the
## structure settles: anything with no path to the ground through its fasteners
## falls, and every beam checks its span over the supports it has left
## (M = wL^2/8 against the section's strength) - a lost post can bring the
## header, the truss and the roof down with it.

const Materials = preload("res://scripts/materials.gd")

static var all: Array = []             # every live structure (probe() walks them)
const DEBRIS_LAYER := 1 << 5

var pieces := {}                       # id -> piece dict
var aabb := AABB()                     # world box of the whole building
var root: Node3D
var debris: Array = []
var _settle_left := 0                  # frames of settling still to run
var on_break: Callable                 # optional: func(id, piece) (sound, dust)


## Hook a built asset (the node from asset_lib / Kits.node) up.
func setup(asset_root: Node3D) -> void:
	root = asset_root
	var first := true
	for c in asset_root.get_children():
		if not (c is Node3D) or not c.has_meta("piece"):
			continue
		var info: Dictionary = c.get_meta("piece")
		var id := String(c.name).substr(2)
		var box := AABB()
		var got := false
		for mi in c.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (mi as MeshInstance3D).get_aabb()
			box = b if not got else box.merge(b)
			got = true
		if not got:
			continue
		var p := {"id": id, "node": c, "info": info, "box": box, "broken": false, "damage": 0.0,
			"mat": String(info.get("mat", "timber")), "kind": String(info.get("kind", "member")),
			"links": info.get("links", []), "ground": bool(info.get("ground", false)), "T": 15.0}
		p["mass"] = _mass(p)
		p["energy"] = _break_energy(p)
		pieces[id] = p
		var wb: AABB = asset_root.global_transform * box
		aabb = wb if first else aabb.merge(wb)
		first = false
	# fastenings go both ways
	for id2 in pieces.keys():
		var nb: Array = []
		for l in pieces[id2]["links"]:
			if pieces.has(l):
				nb.append(l)
		pieces[id2]["links"] = nb
	for id3 in pieces.keys():
		for l2 in pieces[id3]["links"]:
			var back: Array = pieces[l2].get("held", [])
			back.append(id3)
			pieces[l2]["held"] = back
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


func _mass(p: Dictionary) -> float:
	var m := Materials.get_mat(p["mat"])
	var info: Dictionary = p["info"]
	match String(p["kind"]):
		"member":
			var sec: Vector2 = info.get("sec", Vector2(0.1, 0.1))
			var a: Vector3 = info.get("a", Vector3.ZERO)
			var b: Vector3 = info.get("b", Vector3.ZERO)
			return float(m["rho"]) * sec.x * sec.y * a.distance_to(b) * float(info.get("fill", 1.0))
		"panel":
			var s: Vector2 = info.get("size", Vector2.ONE)
			return float(m["rho"]) * s.x * s.y * float(info.get("t", 0.01)) * 1.15      # ribs and laps
		_:
			var bx: AABB = p["box"]
			return float(m["rho"]) * bx.size.x * bx.size.y * bx.size.z


func _break_energy(p: Dictionary) -> float:
	var info: Dictionary = p["info"]
	match String(p["kind"]):
		"member":
			var sec: Vector2 = info.get("sec", Vector2(0.1, 0.1))
			# struck from the side: bending about the weaker way the section faces
			return Materials.member_break_energy(p["mat"], maxf(sec.x, sec.y), minf(sec.x, sec.y), float(info.get("fill", 1.0)))
		"panel":
			var s: Vector2 = info.get("size", Vector2.ONE)
			# what hits it punches a hole its own size or the panel's, whichever is less
			var hole := Vector2(minf(s.x, 2.0), minf(s.y, 1.8))
			var e := Materials.panel_break_energy(p["mat"], float(info.get("t", 0.01)), hole)
			# a sheet also has to pull over its screws: ~8 a row on each girt it's on
			if String(p["mat"]) == "steel_sheet":
				e += 8.0 * float(p["links"].size()) * 60.0
			return e
		_:
			var bx: AABB = p["box"]
			return float(Materials.get_mat(p["mat"])["Gf"]) * bx.size.y * maxf(bx.size.x, bx.size.z) * 4.0


# ------------------------------------------------------------------------------
#  Impacts
# ------------------------------------------------------------------------------
## A vehicle's leading point p (world), radius r, moving at vel with mass m.
## Returns the energy the structure took (J) and whether it held:
## {"absorbed": J, "held": bool, "broke": [ids]}.
func hit(p: Vector3, r: float, vel: Vector3, m: float) -> Dictionary:
	var out := {"absorbed": 0.0, "held": false, "broke": []}
	var lp := root.global_transform.affine_inverse() * p
	var ek := 0.5 * m * vel.length_squared()
	if ek < 1.0:
		return out
	# the pieces it's touching, nearest first
	var touching: Array = []
	for id in pieces.keys():
		var pc: Dictionary = pieces[id]
		if pc["broken"]:
			continue
		var b: AABB = (pc["box"] as AABB).grow(r)
		if b.has_point(lp):
			touching.append([lp.distance_squared_to((pc["box"] as AABB).get_center()), id])
	touching.sort()
	for t in touching:
		var pc2: Dictionary = pieces[t[1]]
		var need := float(pc2["energy"]) * _weakened(pc2) - float(pc2["damage"])
		if ek > need:
			ek -= need
			out["absorbed"] = float(out["absorbed"]) + need
			_break(t[1], vel * 0.85)
			(out["broke"] as Array).append(t[1])
		else:
			# it holds: it takes what came (bent, cracked, dented) and stops you
			pc2["damage"] = float(pc2["damage"]) + ek * 0.6
			out["absorbed"] = float(out["absorbed"]) + ek
			out["held"] = true
			ek = 0.0
			break
	if not (out["broke"] as Array).is_empty():
		_settle_left = 90
	return out


## Fire weakens (materials.strength_left) and char thins wood (structure fire, next).
func _weakened(pc: Dictionary) -> float:
	return Materials.strength_left(pc["mat"], float(pc["T"])) * float(pc.get("section", 1.0))


## The whole front of something moving (a box in world space: the vehicle's
## nose swept through this step), at vel with mass m. Members it reaches hold
## (you stop) or snap and fly; sheet steel bends round it - every vertex the
## nose has got past is pushed along in front of it, the sheet stays screwed
## to its girts - and tears off its screws once it's taken too much.
## {"absorbed": J, "held": bool, "broke": [ids]}
func push(box: AABB, vel: Vector3, m: float) -> Dictionary:
	var out := {"absorbed": 0.0, "held": false, "broke": []}
	var ek := 0.5 * m * vel.length_squared()
	if ek < 1.0 or not aabb.intersects(box):
		return out
	var inv := root.global_transform.affine_inverse()
	var lbox: AABB = inv * box
	var lvel: Vector3 = inv.basis * vel
	var fwd := lvel.normalized()
	# the nose's leading face along fwd, in local space
	var lead := -1e9
	for k in range(8):
		lead = maxf(lead, lbox.get_endpoint(k).dot(fwd))
	for id in pieces.keys():
		var pc: Dictionary = pieces[id]
		if pc["broken"] or not (pc["box"] as AABB).grow(0.05).intersects(lbox):      # (a sheet's box is flat: give it some depth)
			continue
		if String(pc["kind"]) == "panel" and String(Materials.get_mat(pc["mat"])["mode"]) == "tear":
			var work := _fold(pc, lbox, fwd, lead)
			if work < 0.0:
				# nothing left holding it above the nose: off its screws, on the nose
				_break(id, vel * 0.9)
				(out["broke"] as Array).append(id)
				continue
			pc["damage"] = float(pc["damage"]) + work
			out["absorbed"] = float(out["absorbed"]) + work
			ek -= work
			continue
		# a member: snaps where it's hit (or holds)
		var hit_at: Vector3 = (pc["box"] as AABB).intersection(lbox.grow(0.05)).get_center() if (pc["box"] as AABB).grow(0.05).intersects(lbox) else lbox.get_center()
		if bool(pc["ground"]):
			hit_at.y = lbox.position.y + 0.12            # a post goes at the bumper
		var need := float(pc["energy"]) * _weakened(pc) - float(pc["damage"])
		if ek > need:
			ek -= need
			out["absorbed"] = float(out["absorbed"]) + need
			_snap(id, hit_at, vel)
			(out["broke"] as Array).append(id)
		else:
			pc["damage"] = float(pc["damage"]) + ek * 0.6
			out["absorbed"] = float(out["absorbed"]) + ek
			out["held"] = true
			ek = 0.0
			break
	if not (out["broke"] as Array).is_empty():
		_settle_left = 90
	return out


## A sheet folding in: it's screwed to its girts; below the lowest girt that
## still holds above the nose, it swings in on that line like a hinge, as far
## as the nose has pushed it (and stays bent - steel doesn't spring back),
## creased across at the sides of the hit, its ribs buckling. Returns the work
## (plastic hinge plus the screws it pulls over), or -1 when no girt above the
## nose still holds it (it comes right off).
func _fold(pc: Dictionary, lbox: AABB, fwd: Vector3, lead: float) -> float:
	var top := lbox.end.y
	var hinge := 1e9
	for l in pc["links"]:
		var g: Dictionary = pieces[l]
		if g["broken"]:
			continue
		var gy := (g["box"] as AABB).get_center().y
		if gy > top + 0.05:
			hinge = minf(hinge, gy)
	if hinge > 1e8:
		return -1.0
	var nrm: Vector3 = pc["info"].get("normal", Vector3.FORWARD)
	var axis := nrm.cross(Vector3.UP).normalized()        # along the sheet, level
	var t := float(pc["info"].get("t", 0.0004))
	var fy := float(Materials.get_mat(pc["mat"])["fy"])
	var work := 0.0
	for mi in (pc["node"] as Node3D).find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.has_meta("rest"):
			m.mesh = m.mesh.duplicate(true)                # this sheet's own copy from now on
			m.set_meta("rest", (m.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
			m.set_meta("fold", 0.0)
		var rest: PackedVector3Array = m.get_meta("rest")
		var am := m.mesh as ArrayMesh
		# how far it has to swing: the furthest-down vertex inside the nose's
		# width must clear the nose's leading face
		var need := float(m.get_meta("fold"))
		var lo := lbox.position.dot(axis) if absf(axis.dot(Vector3(1, 0, 0))) > 0.5 or absf(axis.dot(Vector3(0, 0, 1))) > 0.5 else 0.0
		var a0 := minf(lbox.position.dot(axis.abs()), lbox.end.dot(axis.abs()))
		var a1 := maxf(lbox.position.dot(axis.abs()), lbox.end.dot(axis.abs()))
		var _lo := lo
		for p in rest:
			if p.y >= hinge or p.y < lbox.position.y - 0.1:
				continue
			var along := p.dot(axis.abs())
			if along < a0 or along > a1:
				continue
			var r := hinge - p.y
			var d := lead + 0.04 - p.dot(fwd)
			if d > 0.0 and r > 0.05:
				need = maxf(need, asin(clampf(d / r, 0.0, 1.0)) if d < r else PI * 0.5 + minf((d - r) / r, 1.2))
		var was := float(m.get_meta("fold"))
		if need <= was + 0.001:
			continue
		m.set_meta("fold", need)
		# swing everything below the hinge in: full inside the nose's width,
		# creased off over half a metre either side, ribs buckling a little
		var v := PackedVector3Array()
		v.resize(rest.size())
		for i in range(rest.size()):
			var p2 := rest[i]
			if p2.y >= hinge:
				v[i] = p2
				continue
			var along2 := p2.dot(axis.abs())
			var w := 1.0 - smoothstep(0.0, 0.55, maxf(a0 - along2, along2 - a1))
			var ang := need * w
			var rel := Vector3(0, p2.y - hinge, 0)
			# rotate about the hinge line so the bottom goes forward and up
			var swung := rel * cos(ang) + fwd * (-rel.y) * sin(ang)
			var buckle := sin(along2 * 21.0 + p2.y * 9.0) * 0.035 * ang * w
			v[i] = Vector3(p2.x, hinge, p2.z) + swung + nrm * buckle
		var arr := am.surface_get_arrays(0)
		arr[Mesh.ARRAY_VERTEX] = v
		var mat := am.surface_get_material(0)
		am.clear_surfaces()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		if mat != null:
			am.surface_set_material(0, mat)
		# a plastic hinge across the sheet's width, and the screws it pulled over
		var width := a1 - a0
		work += fy * t * t / 4.0 * 6.0 * width * (need - was)      # ribbed: ~6x a flat sheet
		if was <= 0.001:
			work += 6.0 * 120.0                                       # screws through the girts it lost
	return work


## Bend a sheet round the nose: each vertex inside the nose's outline that the
## nose has passed is pushed to just ahead of it; neighbours are drawn after
## it (a smooth fold). Returns the work done (yield over the stretched area).
func _dent(pc: Dictionary, lbox: AABB, fwd: Vector3, lead: float) -> float:
	var work := 0.0
	var t := float(pc["info"].get("t", 0.0004))
	var fy := float(Materials.get_mat(pc["mat"])["fy"])
	for mi in (pc["node"] as Node3D).find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.has_meta("own_mesh"):
			m.mesh = m.mesh.duplicate(true)            # this sheet's own copy from now on
			m.set_meta("own_mesh", true)
		var am := m.mesh as ArrayMesh
		if am == null:
			continue
		var arr := am.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var grown := lbox.grow(0.25)
		var moved := false
		for i in range(v.size()):
			var p := v[i]
			if not grown.has_point(p):
				continue
			# how far inside the outline (across the travel): full in the
			# middle, fading at the edge - the fold
			var inside := 1.0
			for ax in range(3):
				if absf(fwd[ax]) > 0.5:
					continue
				var lo := lbox.position[ax]
				var hi := lbox.end[ax]
				var d := minf(p[ax] - lo, hi - p[ax])
				inside = minf(inside, clampf((d + 0.25) / 0.5, 0.0, 1.0))
			var ahead := lead + 0.03 - p.dot(fwd)
			if ahead > 0.0 and inside > 0.0:
				var step := ahead * inside
				v[i] = p + fwd * step
				pc["dent"] = maxf(float(pc.get("dent", 0.0)), float(pc.get("dent_at", {}).get(i, 0.0)) + step)
				var da: Dictionary = pc.get("dent_at", {})
				da[i] = float(da.get(i, 0.0)) + step
				pc["dent_at"] = da
				work += fy * t * 0.3 * step * 0.05                  # bending a 0.3 m strip of sheet through that much
				moved = true
		if moved:
			arr[Mesh.ARRAY_VERTEX] = v
			am.clear_surfaces()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			if m.material_override == null and am.get_surface_count() > 0:
				pass
	return work


## A vehicle (anything with a wheeled_body `body`: pos, basis, vel, size,
## mass()) driving into whatever's here: its nose, swept through this step,
## against every structure it reaches. Slows it by what was spent; true if
## something held (it stops). The ground's blocked_by_building calls this.
static func probe_vehicle(veh: Node, dt: float = 1.0 / 60.0) -> bool:
	var body = veh.get("body") if veh != null else null
	if body == null:
		return false
	var vel: Vector3 = body.vel
	var spd := vel.length()
	if spd < 0.3:
		return false
	var fwd: Vector3 = -body.basis.z * signf(vel.dot(-body.basis.z))
	var size: Vector3 = body.size
	var right: Vector3 = body.basis.x
	var c: Vector3 = body.pos + fwd * (size.z * 0.5 + spd * dt * 0.5) + body.basis.y * (size.y * 0.5 + 0.25)
	var ext: Vector3 = (right * size.x * 0.5).abs() + (body.basis.y * size.y * 0.42).abs() + (fwd * (spd * dt * 0.5 + 0.05)).abs()
	var box := AABB(c - ext, ext * 2.0)
	var held := false
	for s in all:
		var st: Node3D = s
		if not is_instance_valid(st) or not st.aabb.intersects(box):
			continue
		var m: float = body.mass()
		var res: Dictionary = st.push(box, vel, m)
		var a := float(res["absorbed"])
		if a > 0.0:
			var ek := 0.5 * m * vel.length_squared()
			body.vel = vel * sqrt(maxf(0.0, 1.0 - a / maxf(ek, 1.0)))
			vel = body.vel
			# the truck's own front takes it too (vehicle_breakage.gd)
			var brk = veh.get("breakage")
			if brk != null and brk.has_method("hit"):
				brk.hit(c, -fwd * sqrt(2.0 * m * a) * 0.3, 0.9)
		if res["held"]:
			held = true
	return held


## From a vehicle (wheeled_body via ground.gd blocked_by_building): any
## structure there? Slows the vehicle by what it spent; true if it's stopped.
static func probe(p: Vector3, r: float, veh: Node) -> bool:
	for s in all:
		var st: Node3D = s
		if not is_instance_valid(st) or not st.aabb.grow(r + 0.5).has_point(p):
			continue
		var body = veh.get("body") if veh != null else null
		var vel: Vector3 = body.vel if body != null else Vector3.ZERO
		var m: float = body.mass() if body != null else 2000.0
		var res: Dictionary = st.hit(p, r, vel, m)
		if float(res["absorbed"]) <= 0.0 and not bool(res["held"]):
			continue
		if res["held"]:
			return true
		var ek := 0.5 * m * vel.length_squared()
		if body != null and ek > 0.0:
			body.vel = vel * sqrt(maxf(0.0, 1.0 - float(res["absorbed"]) / ek))
		return false
	return false


# ------------------------------------------------------------------------------
#  Breaking and falling
# ------------------------------------------------------------------------------
## A member breaks where it's struck: two pieces, splintered at the break (wood)
## or kinked (steel). Each half keeps the fastenings at its own end - a post's
## stub stays in the ground, its top hangs from the header; a girt's halves
## each hang off their post by the screws - and the settle decides what falls.
func _snap(id: String, at: Vector3, vel: Vector3) -> void:
	var pc: Dictionary = pieces[id]
	var info: Dictionary = pc["info"]
	# already a broken-off half, or a short bit: it just gets knocked flying
	if String(pc["kind"]) != "member" or not info.has("a") or bool(info.get("half", false)) or (info["a"] as Vector3).distance_to(info["b"]) < 0.9:
		_break(id, vel * 0.85)
		return
	var a: Vector3 = info["a"]
	var b: Vector3 = info["b"]
	var L := a.distance_to(b)
	var dir := (b - a) / maxf(L, 0.001)
	var t := clampf((at - a).dot(dir), 0.25, L - 0.25)
	var gap := 0.06
	var sec: Vector2 = info.get("sec", Vector2(0.1, 0.1))
	var mkey := String(info.get("mkey", "wood"))
	var col: Color = info.get("col", Color(0.78, 0.68, 0.52))
	_burst(root.global_transform * (a + dir * t), vel, pc)
	# which fastenings go with which end
	var near_a: Array = []
	var near_b: Array = []
	for l in pc["links"]:
		var lc: Vector3 = (pieces[l]["box"] as AABB).get_center()
		if (lc - a).dot(dir) < t:
			near_a.append(l)
		else:
			near_b.append(l)
	var halves := [[a, a + dir * (t - gap), near_a, bool(pc["ground"]) and a.y < b.y + 0.01 and (a.y <= b.y)], [a + dir * (t + gap), b, near_b, false]]
	if bool(pc["ground"]) and b.y < a.y:
		halves[1][3] = true
	var K = load("res://scripts/assets/kits.gd").new()
	var new_ids: Array = []
	for hi in range(2):
		var h: Array = halves[hi]
		var hid := "%s_%s" % [id, "a" if hi == 0 else "b"]
		var hinfo := info.duplicate(true)
		hinfo["a"] = h[0]
		hinfo["b"] = h[1]
		hinfo["links"] = h[2]
		hinfo["ground"] = h[3]
		hinfo["half"] = true
		K.piece(hid, hinfo)
		var kit = K.k(mkey)
		var ha: Vector3 = h[0]
		var hb: Vector3 = h[1]
		_member_box(kit, ha, hb, sec, col)
		# the splintered end: a few long slivers sticking out of the break
		var brk: Vector3 = hb if hi == 0 else ha
		var out_dir: Vector3 = dir if hi == 0 else -dir
		if String(pc["mat"]).begins_with("timber") or String(pc["mat"]) == "plywood":
			for sp in range(5):
				var off := Vector3(randf_range(-0.4, 0.4) * sec.x, randf_range(-0.4, 0.4) * sec.y, 0)
				var side := out_dir.cross(Vector3.UP if absf(out_dir.y) < 0.9 else Vector3.RIGHT).normalized()
				var p0 := brk + side * off.x + out_dir.cross(side) * off.y
				_member_box(kit, p0 - out_dir * 0.02, p0 + out_dir * randf_range(0.05, 0.22) + side * randf_range(-0.03, 0.03), Vector2(0.012, 0.02), col.darkened(0.1))
		new_ids.append(hid)
	var made: Node3D = K.node("halves")
	# replace the piece with its two halves
	(pc["node"] as Node3D).queue_free()
	pc["broken"] = true
	for l2 in pc["links"]:
		(pieces[l2].get("held", []) as Array).erase(id)
	for ch in made.get_children():
		made.remove_child(ch)
		root.add_child(ch)
		var nid := String(ch.name).substr(2)
		var ninfo: Dictionary = ch.get_meta("piece")
		var box := AABB()
		var got := false
		for mi in ch.find_children("*", "MeshInstance3D", true, false):
			var bb: AABB = (mi as MeshInstance3D).get_aabb()
			box = bb if not got else box.merge(bb)
			got = true
		var np := {"id": nid, "node": ch, "info": ninfo, "box": box, "broken": false, "damage": 0.0, "mat": pc["mat"], "kind": "member",
			"links": ninfo["links"], "ground": ninfo["ground"], "T": pc["T"], "held": []}
		np["mass"] = _mass(np)
		np["energy"] = _break_energy(np)
		pieces[nid] = np
		for l3 in np["links"]:
			var back: Array = pieces[l3].get("held", [])
			back.append(nid)
			pieces[l3]["held"] = back
		# a post's top half hanging from the header: shoved aside, it swings
		# out of the way on its bolts
		if absf(dir.y) >= 0.5 and not np["ground"] and not np["links"].is_empty():
			var top_end: Vector3 = ninfo["b"] if (ninfo["b"] as Vector3).y > (ninfo["a"] as Vector3).y else ninfo["a"]
			var lf: Vector3 = (root.global_transform.affine_inverse().basis * vel).normalized()
			lf.y = 0.0
			var ax := Vector3.UP.cross(lf).normalized()
			if ax.length() > 0.1:
				var sw := Basis(ax, -randf_range(0.7, 1.1))
				(ch as Node3D).transform = Transform3D(sw, top_end - sw * top_end)
				np["box"] = (ch as Node3D).transform * box
		# a girt half hanging off one post by its screws: it swings down
		elif absf(dir.y) < 0.5 and not np["links"].is_empty():
			var pivot: Vector3 = ninfo["a"] if nid.ends_with("_a") else ninfo["b"]
			var swing := Basis(dir.cross(Vector3.UP).normalized(), (1.0 if nid.ends_with("_a") else -1.0) * randf_range(0.6, 1.3))
			(ch as Node3D).transform = Transform3D(swing, pivot - swing * pivot)
			np["box"] = (ch as Node3D).transform * box
		else:
			# a loose half (nothing to hang from) flies with the hit
			pass
	made.free()
	_settle_left = 90


static func _member_box(kit, a: Vector3, b: Vector3, sec: Vector2, col: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	kit.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(sec.x, l, sec.y), col)


## Dust and wood chips (or sparks of paint and rust) where something breaks.
func _burst(at: Vector3, vel: Vector3, pc: Dictionary) -> void:
	var wood := String(pc["mat"]).begins_with("timber") or String(pc["mat"]) == "plywood"
	for kind in ["chips", "dust"]:
		var ps := CPUParticles3D.new()
		ps.one_shot = true
		ps.explosiveness = 0.95
		ps.emitting = true
		var q := QuadMesh.new()
		var mt := StandardMaterial3D.new()
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if kind == "dust" else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mt.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if kind == "dust" else BaseMaterial3D.BILLBOARD_DISABLED
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if kind == "dust" else BaseMaterial3D.TRANSPARENCY_DISABLED
		mt.vertex_color_use_as_albedo = true
		mt.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material = mt
		ps.mesh = q
		if kind == "chips":
			ps.amount = 40 if wood else 12
			q.size = Vector2(0.05, 0.015)
			ps.color = Color(0.82, 0.7, 0.5) if wood else Color(0.5, 0.15, 0.1)
			ps.lifetime = 2.0
			ps.initial_velocity_min = 2.0
			ps.initial_velocity_max = 2.0 + vel.length() * 0.5
			ps.gravity = Vector3(0, -9.8, 0)
			ps.angular_velocity_min = -720.0
			ps.angular_velocity_max = 720.0
		else:
			ps.amount = 24
			q.size = Vector2(0.6, 0.6)
			ps.color = Color(0.62, 0.58, 0.5, 0.35)
			ps.lifetime = 3.0
			ps.initial_velocity_min = 0.3
			ps.initial_velocity_max = 1.5
			ps.gravity = Vector3(0, 0.15, 0)
			ps.scale_amount_min = 0.8
			ps.scale_amount_max = 2.5
		ps.direction = vel.normalized() if vel.length() > 0.1 else Vector3.UP
		ps.spread = 70.0
		root.get_parent().add_child(ps)
		ps.global_position = at
		get_tree().create_timer(4.0).timeout.connect(ps.queue_free)
func _break(id: String, vel: Vector3) -> void:
	var pc: Dictionary = pieces[id]
	if pc["broken"]:
		return
	pc["broken"] = true
	if on_break.is_valid():
		on_break.call(id, pc)
	var node: Node3D = pc["node"]
	var xf := node.global_transform
	var box: AABB = pc["box"]
	var rb := RigidBody3D.new()
	rb.name = "Debris_" + id
	rb.mass = maxf(float(pc["mass"]), 0.5)
	rb.collision_layer = DEBRIS_LAYER
	rb.collision_mask = 1 | DEBRIS_LAYER
	rb.continuous_cd = true
	var world: Node = root.get_parent() if root.get_parent() != null else root
	world.add_child(rb)
	# the body sits at the piece's centre; the meshes move under it
	var c := xf * box.get_center()
	rb.global_transform = Transform3D(xf.basis, c)
	node.get_parent().remove_child(node)
	rb.add_child(node)
	node.transform = Transform3D(Basis.IDENTITY, -box.get_center())
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.size.x, 0.03), maxf(box.size.y, 0.03), maxf(box.size.z, 0.03))
	cs.shape = shape
	rb.add_child(cs)
	# sheet steel catches the air: it flaps and drifts rather than drops
	if String(pc["kind"]) == "panel":
		rb.linear_damp = 1.2
		rb.angular_damp = 1.5
	var spd := minf(vel.length(), 14.0)
	rb.linear_velocity = vel.normalized() * spd + Vector3(0, minf(spd * 0.15, 2.0), 0)
	rb.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)) * clampf(spd / 8.0, 0.2, 1.0)
	debris.append(rb)
	_settle_left = maxi(_settle_left, 90)


## What's still held up: a path through intact fastenings to a piece in the
## ground. And beams over too long a span now.
func _settle() -> void:
	var up := {}
	var queue: Array = []
	for id in pieces.keys():
		var pc: Dictionary = pieces[id]
		if not pc["broken"] and pc["ground"]:
			up[id] = true
			queue.append(id)
	while not queue.is_empty():
		var id2: String = queue.pop_front()
		for nb in (pieces[id2]["links"] as Array) + (pieces[id2].get("held", []) as Array):
			if not up.has(nb) and not pieces[nb]["broken"]:
				up[nb] = true
				queue.append(nb)
	var fell := false
	for id3 in pieces.keys():
		var pc3: Dictionary = pieces[id3]
		if pc3["broken"]:
			continue
		if not up.has(id3):
			_break(id3, Vector3(0, -0.5, 0))
			fell = true
			continue
		if bool(pc3["info"].get("beam", false)) and not _span_ok(pc3):
			_break(id3, Vector3(0, -1.0, 0))
			fell = true
	if fell:
		_settle_left = 60


## A beam (header, truss, door header) over its remaining supports: the
## longest clear span and the overhangs past the end supports against what its
## section can carry under its load w (N/m: its share of roof, snow).
func _span_ok(pc: Dictionary) -> bool:
	var info: Dictionary = pc["info"]
	var a: Vector3 = info.get("a", Vector3.ZERO)
	var b: Vector3 = info.get("b", Vector3.ZERO)
	var L := a.distance_to(b)
	if L < 0.5:
		return true
	var dir := (b - a) / L
	var ts: Array = []
	for l in pc["links"]:
		var sp: Dictionary = pieces[l]
		if sp["broken"] or String(sp["kind"]) != "member":
			continue
		if bool(sp["info"].get("beam", false)) and bool(info.get("beam", false)) and String(sp["id"]).begins_with("truss") == String(pc["id"]).begins_with("truss"):
			continue
		var sc: Vector3 = (sp["box"] as AABB).get_center()
		ts.append(clampf((sc - a).dot(dir), 0.0, L))
	if ts.is_empty():
		return false
	ts.sort()
	var sec: Vector2 = info.get("sec", Vector2(0.1, 0.1))
	var w := float(info.get("w", 1000.0)) + float(pc["mass"]) * 9.81 / L
	var fill := float(info.get("fill", 1.0))
	var k := _weakened(pc)
	var span_max := Materials.max_span(pc["mat"], minf(sec.x, sec.y), maxf(sec.x, sec.y), w, fill) * sqrt(k)
	var cant_max := Materials.max_cantilever(pc["mat"], minf(sec.x, sec.y), maxf(sec.x, sec.y), w, fill) * sqrt(k)
	if float(ts[0]) > cant_max or L - float(ts[ts.size() - 1]) > cant_max:
		return false
	for i in range(ts.size() - 1):
		if float(ts[i + 1]) - float(ts[i]) > span_max:
			return false
	return true


func _physics_process(_dt: float) -> void:
	if _settle_left > 0:
		_settle_left -= 1
		if _settle_left % 6 == 0:          # a few times a second while things are moving
			_settle()
	# debris that's come to rest: freeze it (no cost while it lies there)
	for rb in debris:
		if is_instance_valid(rb) and (rb as RigidBody3D).sleeping and not (rb as RigidBody3D).freeze:
			(rb as RigidBody3D).freeze = true
