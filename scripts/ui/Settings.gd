class_name SettingsScreen
extends Control

## Audio prefs + the destructive "reset progress" action.
##
## Prefs live in GameSettings (user://settings.cfg), deliberately separate from
## Economy's save file: wiping progress must not also reset the player's audio
## choices, and vice versa.

var _confirm_layer: Control
var _summary_label: Label

func _ready() -> void:
	GameSettings.apply()

	add_child(UITheme.make_background("sunset_beach"))
	add_child(UITheme.make_scrim(0.7))

	var root_box := VBoxContainer.new()
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_box)

	root_box.add_child(_build_top_bar())

	var pad := MarginContainer.new()
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 34)
	pad.add_theme_constant_override("margin_right", 34)
	pad.add_theme_constant_override("margin_top", 28)
	pad.add_theme_constant_override("margin_bottom", 40)
	root_box.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	pad.add_child(column)

	# --- audio -----------------------------------------------------------------
	var audio_card := _card(UITheme.CYAN)
	var audio_col := VBoxContainer.new()
	audio_col.add_theme_constant_override("separation", 12)
	audio_card.add_child(audio_col)
	audio_col.add_child(_card_title("AUDIO", UITheme.CYAN))
	audio_col.add_child(_build_toggle("Sound effects", GameSettings.sound_enabled, _on_sound_toggled))
	audio_col.add_child(_build_toggle("Music", GameSettings.music_enabled, _on_music_toggled))
	column.add_child(audio_card)
	UITheme.slide_in(audio_card, 0.05, 30.0, 0.32)

	# --- progress --------------------------------------------------------------
	var progress_card := _card(UITheme.PINK)
	var progress_col := VBoxContainer.new()
	progress_col.add_theme_constant_override("separation", 12)
	progress_card.add_child(progress_col)
	progress_col.add_child(_card_title("PROGRESS", UITheme.PINK))

	_summary_label = UITheme.make_label(_summary_text(), 21, UITheme.INK_DIM, 0)
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_col.add_child(_summary_label)

	var reset := UITheme.make_button("RESET PROGRESS", UITheme.RED, 26)
	reset.custom_minimum_size = Vector2(0, 72)
	reset.pressed.connect(_show_confirm)
	progress_col.add_child(reset)

	var warn := UITheme.make_label("This wipes every star, coin and unlocked level. It can't be undone.",
		18, Color(1, 0.75, 0.75, 0.9), 0)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_col.add_child(warn)
	column.add_child(progress_card)
	UITheme.slide_in(progress_card, 0.12, 30.0, 0.32)

	# --- about -----------------------------------------------------------------
	var about_card := _card(UITheme.PURPLE)
	var about_col := VBoxContainer.new()
	about_col.add_theme_constant_override("separation", 8)
	about_card.add_child(about_col)
	about_col.add_child(_card_title("ABOUT", UITheme.PURPLE))
	var about := UITheme.make_label("GemCascade v1.0\nMade with Godot 4.\nNo ads, no accounts, no tracking.",
		20, UITheme.INK_DIM, 0)
	about.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	about_col.add_child(about)
	column.add_child(about_card)
	UITheme.slide_in(about_card, 0.19, 30.0, 0.32)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(filler)

	_build_confirm_overlay()


# --- layout helpers ----------------------------------------------------------

func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	var sb := UITheme.panel_style(Color(0.06, 0.03, 0.13, 0.92), 0)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	bar.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

	var back := UITheme.make_ghost_button("BACK", UITheme.INK, 24)
	back.pressed.connect(_go_back)
	row.add_child(back)
	row.add_child(UITheme.make_label("SETTINGS", 34, UITheme.INK, 6))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	return bar


func _go_back() -> void:
	UITheme.go_to_scene(self, UITheme.SCENE_MAIN_MENU)


func _card(accent: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0.10, 0.06, 0.20, 0.92), 28, accent, 3))
	return card


func _card_title(text: String, color: Color) -> Label:
	var l := UITheme.make_label(text, 26, color, 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _build_toggle(text: String, initial: bool, handler: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := UITheme.make_label(text, 24, UITheme.INK, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = initial
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.custom_minimum_size = Vector2(130, 60)
	toggle.add_theme_font_size_override("font_size", 24)
	toggle.add_theme_color_override("font_color", UITheme.INK)
	toggle.add_theme_color_override("font_hover_color", UITheme.INK)
	toggle.add_theme_color_override("font_pressed_color", UITheme.INK)
	toggle.add_theme_stylebox_override("normal", UITheme.button_style(UITheme.SLATE, 26, 4))
	toggle.add_theme_stylebox_override("hover", UITheme.button_style(UITheme.SLATE.lightened(0.1), 26, 4))
	toggle.add_theme_stylebox_override("pressed", UITheme.button_style(UITheme.GREEN, 26, 4))
	toggle.add_theme_stylebox_override("hover_pressed", UITheme.button_style(UITheme.GREEN.lightened(0.1), 26, 4))
	toggle.add_theme_stylebox_override("focus", UITheme.button_style(UITheme.SLATE, 26, 4))
	toggle.text = "ON" if initial else "OFF"
	toggle.toggled.connect(func(pressed: bool) -> void:
		toggle.text = "ON" if pressed else "OFF"
		handler.call(pressed))
	UITheme.add_press_feedback(toggle)
	row.add_child(toggle)
	return row


func _summary_text() -> String:
	if Economy == null:
		return ""
	var played := 0
	for v in Economy.stars_by_level.values():
		if int(v) > 0:
			played += 1
	return "Levels cleared: %d\nStars earned: %d / %d\nCoins: %d    Crystals: %d" % [
		played, Economy.total_stars(), UITheme.MAX_LEVEL * 3, Economy.coins, Economy.crystals]


# --- reset confirmation ------------------------------------------------------

## Two-step destructive action: the button only opens this overlay, and the
## overlay's default/large button is CANCEL. One stray tap can't wipe a save.
func _build_confirm_overlay() -> void:
	_confirm_layer = Control.new()
	_confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.visible = false
	add_child(_confirm_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("1c1033"), 32, UITheme.RED, 4))
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)

	column.add_child(UITheme.make_label("RESET EVERYTHING?", 32, UITheme.RED, 6))
	var body := UITheme.make_label(
		"All stars, coins, boosters and unlocked levels will be permanently deleted. You'll start again at level 1.",
		21, UITheme.INK_DIM, 0)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(500, 0)
	column.add_child(body)

	var cancel := UITheme.make_button("KEEP MY PROGRESS", UITheme.GREEN, 26)
	cancel.custom_minimum_size = Vector2(0, 76)
	cancel.pressed.connect(_hide_confirm)
	column.add_child(cancel)

	var confirm := UITheme.make_ghost_button("Yes, delete everything", UITheme.RED, 22)
	confirm.pressed.connect(_do_reset)
	column.add_child(confirm)

	_confirm_layer.set_meta("panel", panel)


func _show_confirm() -> void:
	if _confirm_layer == null:
		return
	_confirm_layer.visible = true
	_confirm_layer.modulate.a = 0.0
	var tw := _confirm_layer.create_tween()
	tw.tween_property(_confirm_layer, "modulate:a", 1.0, 0.18)
	var panel: Control = _confirm_layer.get_meta("panel")
	if panel != null:
		UITheme.pop_in(panel, 0.0, 0.7, 0.35)


func _hide_confirm() -> void:
	if _confirm_layer == null:
		return
	var tw := _confirm_layer.create_tween()
	tw.tween_property(_confirm_layer, "modulate:a", 0.0, 0.16)
	tw.tween_callback(func() -> void: _confirm_layer.visible = false)


func _do_reset() -> void:
	if Economy != null:
		Economy.reset_all()
	if _summary_label != null:
		_summary_label.text = _summary_text()
	_hide_confirm()
	UITheme.toast(self, "Progress reset — back to level 1.")


func _on_sound_toggled(enabled: bool) -> void:
	GameSettings.set_sound(enabled)


func _on_music_toggled(enabled: bool) -> void:
	GameSettings.set_music(enabled)


## Android hardware back button: closes the confirm overlay first if it's open,
## otherwise leaves the screen — never wipes anything by accident.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if _confirm_layer != null and _confirm_layer.visible:
		_hide_confirm()
	else:
		_go_back()
