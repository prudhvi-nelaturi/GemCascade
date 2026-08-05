class_name MainMenuScreen
extends Control

## Title screen. Everything is built in code rather than hand-authored in the
## .tscn: the layout is data-driven (episode colours, live currency, progress
## counters) and one script is far easier to keep in sync than a large scene
## file edited by hand without an editor GUI in this environment.

var _play_button: Button
var _title_box: Control
var _button_box: Control
var _progress_label: Label

func _ready() -> void:
	GameSettings.apply()

	var episode := UITheme.episode_of_level(_current_level())
	add_child(UITheme.make_background(episode))
	add_child(UITheme.make_scrim(0.55))
	_add_gem_confetti()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 52)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	# --- top row: live currency ------------------------------------------------
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(top)
	top.add_child(CurrencyBar.new(true))

	column.add_child(UITheme.make_spacer(40))

	# --- title -----------------------------------------------------------------
	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", -14)
	column.add_child(_title_box)

	var gem := UITheme.make_label("GEM", 104, UITheme.PINK, 14)
	_title_box.add_child(gem)
	var cascade := UITheme.make_label("CASCADE", 76, UITheme.GOLD, 12)
	_title_box.add_child(cascade)

	var tagline := UITheme.make_label("MATCH · CASCADE · CONQUER", 22, UITheme.INK_DIM, 4)
	_title_box.add_child(tagline)

	column.add_child(UITheme.make_spacer(30))

	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	star_row.add_theme_constant_override("separation", 6)
	column.add_child(star_row)
	for i in 3:
		star_row.add_child(StarIcon.new(true, 34))

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(filler)

	# --- actions ---------------------------------------------------------------
	_button_box = VBoxContainer.new()
	_button_box.add_theme_constant_override("separation", 20)
	column.add_child(_button_box)

	_play_button = UITheme.make_button("PLAY", UITheme.GREEN, 54)
	_play_button.custom_minimum_size = Vector2(0, 108)
	_play_button.pressed.connect(_on_play_pressed)
	_button_box.add_child(_play_button)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_button_box.add_child(row)

	var shop := UITheme.make_button("SHOP", UITheme.PURPLE, 32)
	shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop.custom_minimum_size = Vector2(0, 76)
	shop.pressed.connect(func() -> void: UITheme.go_to_scene(self, UITheme.SCENE_SHOP))
	row.add_child(shop)

	var settings := UITheme.make_button("SETTINGS", UITheme.CYAN, 32)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.custom_minimum_size = Vector2(0, 76)
	settings.pressed.connect(func() -> void: UITheme.go_to_scene(self, UITheme.SCENE_SETTINGS))
	row.add_child(settings)

	_progress_label = UITheme.make_label(_progress_text(), 24, UITheme.INK_DIM, 4)
	_button_box.add_child(_progress_label)

	await get_tree().process_frame
	await get_tree().process_frame
	_animate_in()


func _current_level() -> int:
	if Economy == null:
		return 1
	return clampi(Economy.highest_unlocked_level, 1, UITheme.MAX_LEVEL)


func _progress_text() -> String:
	if Economy == null:
		return ""
	var episode := UITheme.episode_of_level(_current_level())
	return "%s   ·   Level %d   ·   %d / %d stars" % [
		UITheme.EPISODE_TITLES.get(episode, ""),
		_current_level(),
		Economy.total_stars(),
		UITheme.MAX_LEVEL * 3,
	]


## Scatters a few gem sprites behind the title. Purely decorative and silently
## skipped when assets/gems/*.png hasn't been generated yet.
func _add_gem_confetti() -> void:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260805
	var spots: Array[Vector2] = [
		Vector2(70, 250), Vector2(600, 190), Vector2(120, 640),
		Vector2(640, 700), Vector2(560, 470), Vector2(90, 900),
	]
	for i in spots.size():
		var tex := UITheme.texture("res://assets/gems/gem_%d.png" % (i % 6))
		if tex == null:
			continue
		var tr := TextureRect.new()
		tr.texture = tex
		tr.position = spots[i]
		tr.custom_minimum_size = Vector2(84, 84)
		tr.size = Vector2(84, 84)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.pivot_offset = Vector2(42, 42)
		tr.rotation = rng.randf_range(-0.5, 0.5)
		tr.modulate = Color(1, 1, 1, 0.5)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(tr)

		# Slow bob so the menu is never completely static.
		var tw := tr.create_tween()
		tw.set_loops()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var drift := rng.randf_range(10.0, 22.0)
		var period := rng.randf_range(1.6, 2.8)
		tw.tween_property(tr, "position:y", spots[i].y - drift, period)
		tw.tween_property(tr, "position:y", spots[i].y, period)


func _animate_in() -> void:
	UITheme.pop_in(_title_box, 0.05, 0.65, 0.55)
	UITheme.slide_in(_button_box, 0.25, 60.0, 0.4)
	await get_tree().create_timer(0.7).timeout
	if is_instance_valid(_play_button):
		UITheme.pulse(_play_button, 0.045, 1.4)


func _on_play_pressed() -> void:
	LevelMapScreen.focus_level_number = _current_level()
	UITheme.go_to_scene(self, UITheme.SCENE_LEVEL_MAP)


## Android hardware back button on the root screen exits the game, which is
## what players expect there.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
