extends Node
## Lab tool (DESIGN_NOTES 228): download CC0 photo-scanned textures from Poly
## Haven (polyhaven.com, CC0, no account) into textures/ph/<id>/. Dave OK'd it
## (free, ~200 MB). Run from the lab: "run res://tools/fetch_textures.gd".
## First run (WANT empty or the catalog missing) saves the catalog
## textures/ph/_catalog.json so the right ids can be picked; ids in WANT are
## then fetched at 2K: colour, normal (GL), roughness, AO/ARM, displacement.

const WANT_FILE := "res://textures/ph/_want.txt"     # one id per line
const RES := "2k"
const UA := ["User-Agent: BushPilot2-lab/1.0 (game texture fetch; CC0)"]

var _queue: Array = []        # [url, path]
var _ids: Array = []
var _http: HTTPRequest
var _cur := ""
var _mode := ""
var done := 0
var failed := 0
var status := "starting"
var _root := ""


func _ready() -> void:
	_root = ProjectSettings.globalize_path("res://textures/ph")
	DirAccess.make_dir_recursive_absolute(_root)
	_http = HTTPRequest.new()
	_http.timeout = 120.0
	add_child(_http)
	_http.request_completed.connect(_on_done)
	if FileAccess.file_exists(WANT_FILE):
		for l in FileAccess.get_file_as_string(WANT_FILE).split("\n"):
			var id := l.strip_edges()
			if id != "" and not id.begins_with("#"):
				_ids.append(id)
	if not FileAccess.file_exists(_root + "/_catalog.json"):
		_mode = "catalog"
		_cur = _root + "/_catalog.json"
		status = "fetching the catalog"
		_http.request("https://api.polyhaven.com/assets?t=textures", UA)
		return
	_next_id()


func _next_id() -> void:
	if _ids.is_empty():
		_mode = "files"
		_next()
		return
	var id: String = _ids.pop_front()
	_mode = "info:" + id
	status = "looking up " + id
	_http.request("https://api.polyhaven.com/files/" + id, UA)


func _next() -> void:
	if _queue.is_empty():
		status = "done: %d files, %d failed -> textures/ph" % [done, failed]
		print("[fetch_textures] ", status)
		var f := FileAccess.open(_root + "/LICENSE.txt", FileAccess.WRITE)
		if f:
			f.store_string("Textures in this folder: Poly Haven (polyhaven.com), CC0 1.0 public domain.\n")
		return
	var q: Array = _queue.pop_front()
	_cur = q[1]
	if FileAccess.file_exists(_cur):
		done += 1
		_next.call_deferred()
		return
	status = "fetching %s (%d left)" % [_cur.get_file(), _queue.size()]
	if _http.request(q[0], UA) != OK:
		failed += 1
		_next.call_deferred()


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if _mode == "catalog":
		if ok:
			var f := FileAccess.open(_cur, FileAccess.WRITE)
			f.store_buffer(body)
			f.close()
			status = "catalog saved"
		else:
			status = "catalog failed: result %d code %d" % [result, code]
		print("[fetch_textures] ", status)
		if ok:
			_next_id()
		return
	if _mode.begins_with("info:"):
		var id := _mode.substr(5)
		if ok:
			var j = JSON.parse_string(body.get_string_from_utf8())
			if j is Dictionary:
				DirAccess.make_dir_recursive_absolute(_root + "/" + id)
				# colour and normal at 2K, AO/rough/metal packed (ARM) at 1K
				for key in ["Diffuse", "nor_gl", "arm"]:
					var res := RES if key != "arm" else "1k"
					if j.has(key) and j[key].has(res):
						var fm: Dictionary = j[key][res]
						var ext := "jpg" if fm.has("jpg") else ("png" if fm.has("png") else "")
						if ext != "":
							var url: String = fm[ext]["url"]
							_queue.append([url, "%s/%s/%s" % [_root, id, url.get_file()]])
		else:
			failed += 1
			print("[fetch_textures] no such id ", id, " code ", code)
		_next_id.call_deferred()
		return
	if ok:
		var f2 := FileAccess.open(_cur, FileAccess.WRITE)
		f2.store_buffer(body)
		f2.close()
		done += 1
	else:
		failed += 1
		print("[fetch_textures] failed ", _cur, " result ", result, " code ", code)
	_next.call_deferred()
