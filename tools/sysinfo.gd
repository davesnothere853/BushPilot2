extends Node
## Lab tool: write this PC's hardware to _rec/sysinfo.txt (for the
## performance budget, DESIGN_NOTES 228). "run res://tools/sysinfo.gd"
var status := "reading"


func _ready() -> void:
	var mem := OS.get_memory_info()
	var t := ""
	t += "cpu: %s, %d threads\n" % [OS.get_processor_name(), OS.get_processor_count()]
	t += "gpu: %s (%s) driver %s\n" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), ",".join(OS.get_video_adapter_driver_info())]
	t += "api: %s\n" % RenderingServer.get_video_adapter_api_version()
	t += "ram: %.1f GB\n" % (float(mem.get("physical", 0)) / 1073741824.0)
	var vram := RenderingServer.get_rendering_device().get_memory_usage(RenderingDevice.MEMORY_TOTAL) if RenderingServer.get_rendering_device() != null else 0
	t += "vram in use by the lab: %.2f GB\n" % (float(vram) / 1073741824.0)
	var sc := DisplayServer.window_get_current_screen()
	t += "screen: %s at %d Hz\n" % [str(DisplayServer.screen_get_size(sc)), int(DisplayServer.screen_get_refresh_rate(sc))]
	t += "os: %s %s\n" % [OS.get_name(), OS.get_version()]
	t += "renderer: %s\n" % ProjectSettings.get_setting("rendering/renderer/rendering_method")
	t += "fps now: %d\n" % Engine.get_frames_per_second()
	var f := FileAccess.open("res://_rec/sysinfo.txt", FileAccess.WRITE)
	f.store_string(t)
	f.close()
	status = "wrote _rec/sysinfo.txt"
	print(t)
