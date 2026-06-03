extends Node
## Player settings: graphics + audio. Held here, applied to the engine, and
## persisted to user://settings.cfg so they survive between sessions.

const PATH := "user://settings.cfg"

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const DEFAULT_BINDS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE, KEY_W, KEY_UP],
	"toggle_inventory": [KEY_E, KEY_TAB],
	"interact": [KEY_F],
	"sprint": [KEY_SHIFT],
	"toggle_enemies": [KEY_P],
	"pause": [KEY_ESCAPE],
}

var fullscreen := false
var vsync := true
var msaa := 2            ## 0 off, 1 = 2x, 2 = 4x, 3 = 8x (matches Viewport.MSAA_*)
var bloom := true
var scanlines := true
var res_index := 0
var master := 0.9
var music := 0.55
var sfx := 0.7
var music_on := true
var keybinds := {}       ## action -> overridden physical keycode

func _ready() -> void:
	_load()
	# engine-level settings can be applied right away; bloom/scanlines are
	# applied by their owners (Main's WorldEnvironment, HUD's scanline overlay).
	set_fullscreen(fullscreen, false)
	set_vsync(vsync, false)
	set_msaa(msaa, false)
	set_master(master, false)
	set_music_vol(music, false)
	set_sfx_vol(sfx, false)
	set_music_on(music_on, false)
	apply_binds()
	if not fullscreen:
		set_resolution(res_index, false)

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

func set_sfx_vol(v: float, save := true) -> void:
	sfx = v
	var si := AudioServer.get_bus_index("SFX")
	if si >= 0:
		AudioServer.set_bus_volume_db(si, _db(v))
	if save: _save()

func set_music_on(v: bool, save := true) -> void:
	music_on = v
	Music.set_enabled(v)
	if save: _save()

func set_resolution(i: int, save := true) -> void:
	res_index = clampi(i, 0, RESOLUTIONS.size() - 1)
	if not fullscreen:
		var sz: Vector2i = RESOLUTIONS[res_index]
		DisplayServer.window_set_size(sz)
		var screen := DisplayServer.window_get_current_screen()
		DisplayServer.window_set_position(
			DisplayServer.screen_get_position(screen) + (DisplayServer.screen_get_size(screen) - sz) / 2)
	if save: _save()

# ---- controls ----
func key_for(action: String) -> int:
	if keybinds.has(action):
		return keybinds[action]
	var d: Array = DEFAULT_BINDS.get(action, [])
	return d[0] if d.size() > 0 else KEY_NONE

func rebind(action: String, keycode: int) -> void:
	keybinds[action] = keycode
	apply_binds()
	_save()

func apply_binds() -> void:
	for action in DEFAULT_BINDS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var keys: Array = [keybinds[action]] if keybinds.has(action) else DEFAULT_BINDS[action]
		for kc in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = kc
			InputMap.action_add_event(action, ev)

func reset() -> void:
	fullscreen = false
	vsync = true
	msaa = 2
	bloom = true
	scanlines = true
	res_index = 0
	master = 0.9
	music = 0.55
	sfx = 0.7
	music_on = true
	keybinds = {}
	set_fullscreen(fullscreen, false)
	set_vsync(vsync, false)
	set_msaa(msaa, false)
	set_master(master, false)
	set_music_vol(music, false)
	set_sfx_vol(sfx, false)
	set_music_on(music_on, false)
	set_bloom(bloom, false)
	apply_binds()
	set_resolution(res_index, false)
	_save()

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
	res_index = c.get_value("gfx", "res_index", res_index)
	master = c.get_value("audio", "master", master)
	music = c.get_value("audio", "music", music)
	sfx = c.get_value("audio", "sfx", sfx)
	music_on = c.get_value("audio", "music_on", music_on)
	keybinds = c.get_value("controls", "keybinds", {})

func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("gfx", "fullscreen", fullscreen)
	c.set_value("gfx", "vsync", vsync)
	c.set_value("gfx", "msaa", msaa)
	c.set_value("gfx", "bloom", bloom)
	c.set_value("gfx", "scanlines", scanlines)
	c.set_value("gfx", "res_index", res_index)
	c.set_value("audio", "master", master)
	c.set_value("audio", "music", music)
	c.set_value("audio", "sfx", sfx)
	c.set_value("audio", "music_on", music_on)
	c.set_value("controls", "keybinds", keybinds)
	c.save(PATH)
