class_name LevelFailScreen
extends Control

## ============================================================================
## INTEGRATION CONTRACT — two accepted handoffs, whichever the gameplay screen
## finds more convenient. Both are read (and cleared) in _ready().
##
## 1. Discrete statics:
##     LevelFailScreen.pending_level_number = <int>   # the level that was lost
##     LevelFailScreen.pending_score = <int>            # optional
##     LevelFailScreen.pending_progress = <float 0..1>  # optional
##
## 2. A single payload dict, mirroring LevelCompleteScreen.pending_result so the
##    gameplay side can use one code path for both endings:
##     LevelFailScreen.pending_result = {
##         "level_number": int, "score": int, "progress": float,  # progress optional
##     }
##    (GameplayController._go_to_result_scene() takes this route: it writes
##    `pending_result` onto whichever result scene it is about to show.)
##
## Nothing is credited here — a loss changes no persistent state. The retry
## path re-enters gameplay through the same handoff the LevelMap uses.
## ============================================================================

static var pending_level_number: int = 0
static var pending_score: int = 0
static var pending_progress: float = -1.0
static var pending_result: Dictionary = {}

var _level_number: int = 1
var _score: int = 0
var _progress: float = -1.0

var _card: PanelContainer
var _title: Label

func _ready() -> void:
	GameSettings.apply()

	_consume_handoff()

	var episode := UITheme.episode_of_level(_level_number)
	add_child(UITheme.make_background(episode))
	add_child(UITheme.make_scrim(0.72, Color("0b0618")))

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(580, 0)
	var sb := UITheme.panel_style(Color("1a0f33"), 36, UITheme.RED, 4)
	sb.set_content_margin_all(32)
	sb.shadow_size = 24
	_card.add_theme_stylebox_override("panel", sb)
	center.add_child(_card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	_card.add_child(column)

	_title = UITheme.make_label("OUT OF MOVES!", 46, UITheme.RED, 10)
	column.add_child(_title)

	column.add_child(UITheme.make_label(
		"So close. One more run at it?", 24, UITheme.INK_DIM, 3))

	column.add_child(_build_stat_block(episode))
	column.add_child(UITheme.make_spacer(8))

	var retry := UITheme.make_button("RETRY LEVEL", UITheme.GREEN, 34)
	retry.custom_minimum_size = Vector2(0, 88)
	retry.pressed.connect(_on_retry_pressed)
	column.add_child(retry)

	var map := UITheme.make_button("LEVEL MAP", UITheme.PURPLE, 28)
	map.custom_minimum_size = Vector2(0, 70)
	map.pressed.connect(_on_map_pressed)
	column.add_child(map)

	await get_tree().process_frame
	await get_tree().process_frame
	_animate_in()


## Reads whichever handoff the gameplay screen used, then clears both so a
## re-entry can't inherit a stale level number.
func _consume_handoff() -> void:
	var payload: Dictionary = pending_result.duplicate()
	pending_result = {}

	_level_number = maxi(1, int(payload.get("level_number", pending_level_number)))
	_score = maxi(0, int(payload.get("score", pending_score)))
	_progress = float(payload.get("progress", pending_progress))

	pending_level_number = 0
	pending_score = 0
	pending_progress = -1.0


func _build_stat_block(episode: String) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 10)

	block.add_child(UITheme.make_label("Level %d  ·  %s" % [
		_level_number, UITheme.EPISODE_TITLES.get(episode, "")], 22, UITheme.INK, 4))

	if _score > 0:
		block.add_child(UITheme.make_label("Score: %d" % _score, 24, UITheme.GOLD, 4))

	if _progress >= 0.0:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 26)
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = clampf(_progress, 0.0, 1.0)
		bar.show_percentage = false
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.12)
		bg.set_corner_radius_all(13)
		var fg := StyleBoxFlat.new()
		fg.bg_color = UITheme.episode_accent(episode)
		fg.set_corner_radius_all(13)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fg)
		block.add_child(bar)
		block.add_child(UITheme.make_label("%d%% of the objective cleared" % int(round(clampf(_progress, 0.0, 1.0) * 100.0)),
			19, UITheme.INK_DIM, 0))
	return block


func _animate_in() -> void:
	UITheme.pop_in(_card, 0.0, 0.75, 0.45)
	await get_tree().create_timer(0.35).timeout
	if is_instance_valid(_title):
		UITheme.shake(_title, 16.0, 0.45)


func _on_retry_pressed() -> void:
	if not SceneRouter.level_exists(_level_number):
		UITheme.toast(self, "Level %d isn't available yet." % _level_number)
		return
	if not SceneRouter.play_level(self, _level_number):
		UITheme.toast(self, "Gameplay screen isn't wired up yet.")


func _on_map_pressed() -> void:
	LevelMapScreen.focus_level_number = _level_number
	UITheme.go_to_scene(self, UITheme.SCENE_LEVEL_MAP)


## Android hardware back button — a loss should always be escapable to the map.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_map_pressed()
