extends Node
## Lab tool (DESIGN_NOTES 227): download open elevation tiles (AWS Terrain
## Tiles, terrarium PNG; Mapzen / USGS / NRCan open data) for a place into
## reference/<name>/. Run from the lab: "run res://tools/fetch_tiles.gd".
## Dave OK'd this download (Silverton, CO, for the town's hills).

const PLACE := "silverton"
const LAT := 37.8119
const LON := -107.6645
const JOBS := [[13, 3], [14, 3], [15, 2]]     # zoom, tiles out from the centre each way

var _queue: Array = []
var _http: HTTPRequest
var _cur := ""
var done := 0
var failed := 0
var status := "starting"


func _ready() -> void:
	var dir := ProjectSettings.globalize_path("res://reference/" + PLACE)
	DirAccess.make_dir_recursive_absolute(dir)
	for j in JOBS:
		var z: int = j[0]
		var r: int = j[1]
		var n := float(1 << z)
		var cx := int((LON + 180.0) / 360.0 * n)
		var lat_r := deg_to_rad(LAT)
		var cy := int((1.0 - log(tan(lat_r) + 1.0 / cos(lat_r)) / PI) / 2.0 * n)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				_queue.append([z, cx + dx, cy + dy, dir])
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)
	_http.request_completed.connect(_on_done)
	_next()


func _next() -> void:
	if _queue.is_empty():
		status = "done: %d tiles, %d failed -> reference/%s" % [done, failed, PLACE]
		var f := FileAccess.open(ProjectSettings.globalize_path("res://reference/%s/tiles.json" % PLACE), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"place": PLACE, "lat": LAT, "lon": LON, "jobs": JOBS, "encoding": "terrarium: h = R*256 + G + B/256 - 32768 (m)", "source": "AWS Terrain Tiles (Mapzen terrarium): USGS NED / SRTM / NRCan open data"}, " "))
		print("[fetch_tiles] ", status)
		return
	var q: Array = _queue.pop_front()
	_cur = "%s/t%d_%d_%d.png" % [q[3], q[0], q[1], q[2]]
	if FileAccess.file_exists(_cur):
		done += 1
		_next.call_deferred()
		return
	var url := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png" % [q[0], q[1], q[2]]
	status = "fetching %s (%d left)" % [url, _queue.size()]
	if _http.request(url) != OK:
		failed += 1
		_next.call_deferred()


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var f := FileAccess.open(_cur, FileAccess.WRITE)
		f.store_buffer(body)
		f.close()
		done += 1
	else:
		failed += 1
		print("[fetch_tiles] failed ", _cur, " result ", result, " code ", code)
	_next.call_deferred()
