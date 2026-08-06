class_name GameplayHud
extends CanvasLayer

## In-level HUD: moves, score, objective progress and the booster bar.
##
## The whole thing is assembled in code rather than authored in the .tscn. That
## keeps the layout verifiable in a headless build (there is no way to eyeball a
## scene file here) and keeps every offset in one readable place, which matters
## more for a fixed-size portrait game than editor-tweakability does.

signal booster_pressed(booster_id: String)

const VIEW_WIDTH := 720.0

const PANEL_BG := Color(0.09, 0.07, 0.17, 0.88)
const PANEL_BORDER := Color(0.42, 0.34, 0.72, 0.9)
const TEXT_BRIGHT := Color(1.0, 0.98, 0.92)
const TEXT_DIM := Color(0.68, 0.66, 0.82)
const ACCENT := Color(1.0, 0.77, 0.19)

var _level_label: Label
var _moves_value: Label
var _score_value: Label
var _goal_icon: TextureRect
var _goal_value: Label
var _objective_label: Label
var _progress: ProgressBar
var _toast: Label
var _booster_buttons: Dictionary = {} # booster_id -> Button
var _booster_counts: Dictionary = {} # booster_id -> Label
var _level_data: LevelData

func _ready() -> void:
	layer = 10
	_build()

func _build() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := _make_panel(Vector2(20, 24), Vector2(680, 236))
	root.add_child(top)

	_level_label = _make_label("LEVEL 1", 30, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_level_label.position = Vector2(0, 10)
	_level_label.size = Vector2(680, 36)
	top.add_child(_level_label)

	top.add_child(_make_caption("MOVES", Vector2(24, 58), 190.0))
	_moves_value = _make_label("0", 56, TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_moves_value.position = Vector2(24, 84)
	_moves_value.size = Vector2(190, 66)
	top.add_child(_moves_value)

	top.add_child(_make_caption("SCORE", Vector2(466, 58), 190.0))
	_score_value = _make_label("0", 44, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_score_value.position = Vector2(466, 90)
	_score_value.size = Vector2(190, 56)
	top.add_child(_score_value)

	_goal_icon = TextureRect.new()
	_goal_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_goal_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_goal_icon.position = Vector2(306, 56)
	_goal_icon.size = Vector2(68, 68)
	_goal_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_goal_icon)

	_goal_value = _make_label("", 26, TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_goal_value.position = Vector2(250, 126)
	_goal_value.size = Vector2(180, 32)
	top.add_child(_goal_value)

	_objective_label = _make_label("", 24, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_objective_label.position = Vector2(24, 166)
	_objective_label.size = Vector2(632, 30)
	top.add_child(_objective_label)

	_progress = ProgressBar.new()
	_progress.position = Vector2(24, 200)
	_progress.size = Vector2(632, 20)
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.value = 0.0
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.add_theme_stylebox_override("background", _make_stylebox(Color(0.05, 0.04, 0.11, 0.9), Color(0, 0, 0, 0), 10.0))
	_progress.add_theme_stylebox_override("fill", _make_stylebox(ACCENT, Color(0, 0, 0, 0), 10.0))
	top.add_child(_progress)

	_build_booster_bar(root)

	_toast = _make_label("", 38, TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.position = Vector2(60, 600)
	_toast.size = Vector2(600, 60)
	_toast.modulate = Color(1, 1, 1, 0)
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("shadow_offset_y", 3)
	root.add_child(_toast)

func _build_booster_bar(root: Control) -> void:
	var ids: Array = [Economy.BOOSTER_EXTRA_MOVES, Economy.BOOSTER_HAMMER, Economy.BOOSTER_COLOR_BOMB_START]
	var labels: Array = ["+5 MOVES", "HAMMER", "BOMB START"]
	var button_width := 200.0
	var gap := 20.0
	var total: float = button_width * ids.size() + gap * (ids.size() - 1)
	var start_x: float = (VIEW_WIDTH - total) * 0.5

	for i in range(ids.size()):
		var id: String = ids[i]
		var button := Button.new()
		button.text = str(labels[i])
		button.position = Vector2(start_x + i * (button_width + gap), 1050)
		button.size = Vector2(button_width, 108)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 24)
		button.add_theme_color_override("font_color", TEXT_BRIGHT)
		button.add_theme_color_override("font_disabled_color", Color(0.45, 0.43, 0.55))
		button.add_theme_stylebox_override("normal", _make_stylebox(PANEL_BG, PANEL_BORDER, 18.0))
		button.add_theme_stylebox_override("hover", _make_stylebox(Color(0.16, 0.13, 0.28, 0.95), ACCENT, 18.0))
		button.add_theme_stylebox_override("pressed", _make_stylebox(Color(0.24, 0.19, 0.38, 0.98), ACCENT, 18.0))
		button.add_theme_stylebox_override("disabled", _make_stylebox(Color(0.07, 0.06, 0.12, 0.7), Color(0.2, 0.18, 0.3, 0.8), 18.0))
		button.pressed.connect(_on_booster_button.bind(id))
		root.add_child(button)
		_booster_buttons[id] = button

		var count := _make_label("x0", 22, ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
		count.position = Vector2(button_width - 74, 70)
		count.size = Vector2(60, 28)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(count)
		_booster_counts[id] = count

func _on_booster_button(booster_id: String) -> void:
	booster_pressed.emit(booster_id)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func bind_level(level: LevelData) -> void:
	_level_data = level
	if level == null:
		return
	_level_label.text = "LEVEL %d" % level.level_number
	match level.objective:
		LevelData.Objective.SCORE:
			_goal_icon.texture = GemArt.gem_texture(GemTypes.GemColor.TOPAZ)
			_goal_icon.modulate = Color(1, 1, 1, 1)
		LevelData.Objective.COLLECT_COLOR:
			_goal_icon.texture = GemArt.gem_texture(level.objective_color)
			_goal_icon.modulate = Color(1, 1, 1, 1)
		LevelData.Objective.CLEAR_BLOCKERS:
			_goal_icon.texture = GemArt.blocker_texture()
			_goal_icon.modulate = Color(1, 1, 1, 1)
	refresh()
	refresh_boosters()

## Pulls the current numbers straight off LevelManager — the HUD deliberately
## keeps no copy of level state that could drift out of sync.
func refresh() -> void:
	if _level_data == null:
		return
	_moves_value.text = str(LevelManager.moves_remaining)
	_score_value.text = str(LevelManager.score)
	_progress.value = LevelManager.objective_progress_fraction()

	match _level_data.objective:
		LevelData.Objective.SCORE:
			_objective_label.text = "Reach %d points" % _level_data.objective_target
			_goal_value.text = "%d" % maxi(0, _level_data.objective_target - LevelManager.score)
		LevelData.Objective.COLLECT_COLOR:
			_objective_label.text = "Collect %d gems" % _level_data.objective_target
			_goal_value.text = "%d" % maxi(0, _level_data.objective_target - LevelManager.collected_of_color)
		LevelData.Objective.CLEAR_BLOCKERS:
			_objective_label.text = "Break every blocker"
			_goal_value.text = "%d" % LevelManager.blockers_remaining

	# Running low on moves is the moment that decides whether a player spends a
	# booster, so it gets its own colour state.
	_moves_value.add_theme_color_override("font_color", Color(1.0, 0.35, 0.4) if LevelManager.moves_remaining <= 3 else TEXT_BRIGHT)

func refresh_boosters(bomb_start_available: bool = true) -> void:
	for id in _booster_buttons.keys():
		var count: int = Economy.booster_count(id)
		var button: Button = _booster_buttons[id]
		var label: Label = _booster_counts[id]
		label.text = "x%d" % count
		var usable: bool = count > 0
		if id == Economy.BOOSTER_COLOR_BOMB_START:
			usable = usable and bomb_start_available
		if count <= 0 and AdManager.is_rewarded_ad_ready():
			# Hook for the rewarded-ad top-up path. AdManager is a stub in v1 and
			# always reports false, so this branch is intentionally dormant.
			label.text = "AD"
			usable = true
		button.disabled = not usable

func pulse_score() -> void:
	if _score_value == null:
		return
	_score_value.pivot_offset = _score_value.size * 0.5
	var tween := _score_value.create_tween()
	tween.tween_property(_score_value, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_score_value, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func show_toast(text: String, duration: float = 1.1) -> void:
	if _toast == null:
		return
	_toast.text = text
	var tween := _toast.create_tween()
	tween.tween_property(_toast, "modulate:a", 1.0, 0.16)
	tween.tween_interval(duration)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.28)

# ---------------------------------------------------------------------------
# Small widget factories
# ---------------------------------------------------------------------------

func _make_panel(pos: Vector2, panel_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_stylebox(PANEL_BG, PANEL_BORDER, 24.0))
	return panel

func _make_stylebox(bg: Color, border: Color, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	return sb

func _make_label(text: String, font_size: int, color: Color, align: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.pivot_offset = Vector2.ZERO
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _make_caption(text: String, pos: Vector2, width: float) -> Label:
	var label := _make_label(text, 20, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	label.position = pos
	label.size = Vector2(width, 26)
	return label
