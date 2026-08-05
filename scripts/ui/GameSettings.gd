class_name GameSettings
extends RefCounted

## Player preferences (sound/music), kept deliberately out of Economy.gd so a
## progress wipe (Economy.reset_all) never silently changes the player's audio
## prefs. Same ConfigFile-to-user:// approach as the save file — no autoload
## needed, since the whole API is static.

const SETTINGS_PATH := "user://settings.cfg"

static var sound_enabled: bool = true
static var music_enabled: bool = true
static var _loaded: bool = false


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		sound_enabled = bool(cfg.get_value("audio", "sound", true))
		music_enabled = bool(cfg.get_value("audio", "music", true))
	_loaded = true


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sound", sound_enabled)
	cfg.set_value("audio", "music", music_enabled)
	cfg.save(SETTINGS_PATH)


## Loads once per process, then pushes the prefs at the audio buses. Safe to
## call from every screen's _ready().
static func apply() -> void:
	if not _loaded:
		load_settings()
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, not sound_enabled)
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_mute(music_bus, not music_enabled)


static func set_sound(enabled: bool) -> void:
	sound_enabled = enabled
	save_settings()
	apply()


static func set_music(enabled: bool) -> void:
	music_enabled = enabled
	save_settings()
	apply()
