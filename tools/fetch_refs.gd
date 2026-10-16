extends Node
## Lab tool (DESIGN_NOTES 228): gather real reference photos (Dave's most
## important rule: build everything from real photos). Searches Wikimedia
## Commons for each line of res://_rec/ref_queries.txt ("folder | search words
## | how many") and saves 1024 px copies to reference/<folder>/ with a
## credits.txt (file page, author, licence). Reference only: not shipped.
## Run from the lab: "run res://tools/fetch_refs.gd".

const LIST := "res://_rec/ref_queries.txt"
const UA := ["User-Agent: BushPilot2-lab/1.0 (reference photos for modelling)"]

var _jobs: Array = []        # [folder, query, n]
var _files: Array = []       # [url, path, credit line]
var _http: HTTPRequest
var _mode := ""
var _job: Array = []
var _cur: Array = []
var done := 0
var failed := 0
var status := "starting"
var _retry := 0
var _last := []              # the last request: [url] (to retry after a 429)


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 60.0
	add_child(_http)
	_http.request_completed.connect(_on_done)
	if FileAccess.file_exists(LIST):
		for l in FileAccess.get_file_as_string(LIST).split("\n"):
			var parts := l.split("|")
			if parts.size() >= 2 and not l.strip_edges().begins_with("#"):
				_jobs.append([parts[0].strip_edges(), parts[1].strip_edges(), int(parts[2]) if parts.size() > 2 else 6])
	_next_job()


func _next_job() -> void:
	if _jobs.is_empty():
		_next_file()
		return
	_job = _jobs.pop_front()
	_mode = "search"
	status = "searching " + String(_job[1])
	var q := String(_job[1]).uri_encode()
	await get_tree().create_timer(1.2).timeout          # Wikimedia asks for a gentle pace
	# Openverse (openly licensed photos from Flickr, Wikimedia and more); its
	# thumbnails are plenty for reference
	var url := "https://api.openverse.org/v1/images/?q=%s&page_size=%d&mature=false" % [q, int(_job[2])]
	_last = [url]
	_http.request(url, UA)


func _next_file() -> void:
	if _files.is_empty():
		status = "done: %d photos, %d failed" % [done, failed]
		print("[fetch_refs] ", status)
		return
	_cur = _files.pop_front()
	_mode = "file"
	if FileAccess.file_exists(String(_cur[1])):
		done += 1
		_next_file.call_deferred()
		return
	status = "fetching %s (%d left)" % [String(_cur[1]).get_file(), _files.size()]
	await get_tree().create_timer(1.0).timeout
	_last = [String(_cur[0])]
	_http.request(String(_cur[0]), UA)


func _on_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	# too many requests: wait and try the same one again (a few times)
	if code == 429 and _retry < 4:
		_retry += 1
		status = "Wikimedia says slow down: waiting (%d)" % _retry
		await get_tree().create_timer(8.0 * _retry).timeout
		_http.request(String(_last[0]), UA)
		return
	_retry = 0
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if _mode == "search":
		if ok:
			var j = JSON.parse_string(body.get_string_from_utf8())
			var dir := ProjectSettings.globalize_path("res://reference/" + String(_job[0]))
			DirAccess.make_dir_recursive_absolute(dir)
			var credits := FileAccess.open(dir + "/credits.txt", FileAccess.READ_WRITE if FileAccess.file_exists(dir + "/credits.txt") else FileAccess.WRITE)
			if credits:
				credits.seek_end()
			var n := 0
			if j is Dictionary and j.has("results"):
				for r in j["results"]:
					var tu: String = String(r.get("thumbnail", ""))
					if tu == "":
						tu = String(r.get("url", ""))
					if tu == "":
						continue
					n += 1
					var slug := String(_job[1]).replace(" ", "_").left(24)
					var path := "%s/%s_%02d.jpg" % [dir, slug, n]
					_files.append([tu, path, ""])
					if credits:
						credits.store_line("%s | %s | %s %s | %s" % [path.get_file(), r.get("foreign_landing_url", ""), r.get("license", "?"), r.get("license_version", ""), String(r.get("creator", "?")).left(80)])
			if credits:
				credits.close()
		else:
			failed += 1
			print("[fetch_refs] search failed ", _job[1], " code ", code)
		_next_job.call_deferred()
		return
	if ok:
		var f := FileAccess.open(String(_cur[1]), FileAccess.WRITE)
		f.store_buffer(body)
		f.close()
		done += 1
	else:
		failed += 1
	_next_file.call_deferred()
