extends Node
## Lab tool: fetch a list of files ("url -> res://path" per line in
## res://_rec/fetch_urls.txt) onto this PC. Used for the EZ-Tree leaf and bark
## textures from eztree.dev (MIT, Dave's link). "run res://tools/fetch_urls.gd"
const UA := ["User-Agent: BushPilot2-lab/1.0"]
var _q: Array = []
var _cur := ""
var _http: HTTPRequest
var status := "starting"
var done := 0
var failed := 0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 60.0
	add_child(_http)
	_http.request_completed.connect(_on_done)
	for l in FileAccess.get_file_as_string("res://_rec/fetch_urls.txt").split("\n"):
		var p := l.split("->")
		if p.size() == 2:
			_q.append([p[0].strip_edges(), p[1].strip_edges()])
	_next()


func _next() -> void:
	if _q.is_empty():
		status = "done: %d files, %d failed" % [done, failed]
		print("[fetch_urls] ", status)
		return
	var j: Array = _q.pop_front()
	_cur = ProjectSettings.globalize_path(j[1])
	DirAccess.make_dir_recursive_absolute(_cur.get_base_dir())
	status = "fetching " + String(j[0]).get_file()
	if _http.request(j[0], UA) != OK:
		failed += 1
		_next.call_deferred()


func _on_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 1000:
		var f := FileAccess.open(_cur, FileAccess.WRITE)
		f.store_buffer(body)
		f.close()
		done += 1
	else:
		failed += 1
		print("[fetch_urls] failed ", _cur, " ", result, " ", code, " ", body.size())
	_next.call_deferred()
