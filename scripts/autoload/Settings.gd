extends Node
## Player settings: graphics + audio. Held here, applied to the engine, and
## persisted to user://settings.cfg so they survive between sessions.

const PATH := "user://settings.cfg"

var fullscreen := false
var vsync := true
var msaa := 2            ## 0 off, 1 = 2x, 2 = 4x, 3 = 8x (matches Viewport.MSAA_*)
var bloom := true
var scanlines := true
var master := 0.9
var music := 0.55
var music_on := true

func _ready() -> void:
	_load()
	# engine-level settings can be applied right away; bloom/scanlines are
	# applied by their owners (Main's WorldEnvironment, HUD's scanline overlay).
	set_fullscreen(fullscreen, false)
	set_vsync(vsync, false)
	set_msaa(msaa, false)
	set_master(master, false)
	set_music_vol(music, false)
	set_music_on(music_on, false)

func _db(v: float) -> float:
	return linear_to_db(maxf(v, 0.0008))

func _music_bus() -> int:
	return AudioServer.get_bus_index("Music")

# ---- setters (apply immediately; save unless told not to) ----
func set_fullscreen(v: bool, save := true) -> void:
	fullscreen = v
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if v else DisplayServer.WINDOW_MODE_WINDOWED)
	if save: _save()

func set_vsync(v: bool, save := true) -> void:
	vsync = v
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
	if save: _save()

func set_msaa(v: int, save := true) -> void:
	msaa = v
	get_viewport().msaa_2d = v
	if save: _save()

func set_bloom(v: bool, save := true) -> void:
	bloom = v
	if Game.environment:
		Game.environment.glow_enabled = v
	if save: _save()

func set_scanlines(v: bool, save := true) -> void:
	scanlines = v
	if save: _save()

func set_master(v: float, save := true) -> void:
	master = v
	AudioServer.set_bus_volume_db(0, _db(v))
	if save: _save()

func set_music_vol(v: float, save := true) -> void:
	music = v
	var mi := _music_bus()
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, _db(v))
	if save: _save()

func set_music_on(v: bool, save := true) -> void:
	music_on = v
	Music.set_enabled(v)
	if save: _save()

# ---- persistence ----
func _load() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	fullscreen = c.get_value("gfx", "fullscreen", fullscreen)
	vsync = c.get_value("gfx", "vsync", vsync)
	msaa = c.get_value("gfx", "msaa", msaa)
	bloom = c.get_value("gfx", "bloom", bloom)
	scanlines = c.get_value("gfx", "scanlines", scanlines)
	master = c.get_value("audio", "master", master)
	music = c.get_value("audio", "music", music)
	music_on = c.get_value("audio", "music_on", music_on)

func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("gfx", "fullscreen", fullscreen)
	c.set_value("gfx", "vsync", vsync)
	c.set_value("gfx", "msaa", msaa)
	c.set_value("gfx", "bloom", bloom)
	c.set_value("gfx", "scanlines", scanlines)
	c.set_value("audio", "master", master)
	c.set_value("audio", "music", music)
	c.set_value("audio", "music_on", music_on)
	c.save(PATH)
