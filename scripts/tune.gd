extends RefCounted
## LIVE TUNING (DESIGN_NOTES 190). Numbers that are being dialled in live in
## res://tools/tune.cfg (ConfigFile: [section] key = value). A model reads them
## through Tune.v() every frame and eases toward them, so when the file changes
## you watch the camera swing, the lamp brighten, the part slide - no rebuild,
## no restart. Without the file (the exported game) the defaults in the code
## are used.

const PATH := "res://tools/tune.cfg"

static var _cfg := ConfigFile.new()
static var _stamp := -1
static var _wait := 0.0


## Call once a frame; true when the file has just changed.
static func poll(delta: float) -> bool:
	_wait -= delta
	if _wait > 0.0:
		return false
	_wait = 0.25
	if not FileAccess.file_exists(PATH):
		return false
	var st := FileAccess.get_modified_time(PATH)
	if st == _stamp:
		return false
	_stamp = st
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		_cfg = c
		return true
	return false


static func v(section: String, key: String, default: Variant) -> Variant:
	return _cfg.get_value(section, key, default)
