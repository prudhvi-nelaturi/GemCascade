class_name LevelMapScreen
extends Control

## The meta-progression screen: 24 levels in 3 episode bands, each band wearing
## its own episode background, with lock state and earned stars read live from
## the Economy autoload.
##
## STATIC CONTRACT (set by MainMenu / LevelComplete / LevelFail before entering):
##   LevelMapScreen.focus_level_number = <int>   # 0 = auto (highest unlocked)
## The map scrolls that level's episode into view on open.
##
## Tapping an unlocked node performs the agreed gameplay handoff via
## SceneRouter.play_level() -> GameplayController.pending_level_number = n
## + change_scene_to_file("res://scenes/Gameplay.tscn").

static var focus_level_number: int = 0

const NODE_SIZE := 116.0
const COLUMNS := 4

var _scroll: ScrollContainer
var _sections: Dictionary = {} # episode (String) -> Control
var _star_label: Label

func _ready() -> void:
	GameSettings.apply()

	add_child(UITheme.make_background(""))
	add_child(UITheme.make_scrim(0.35))

	var root_box := VBoxContainer.new()
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 0)
	add_child(root_box)

	root_box.add_child(_build_top_bar())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = false
	root_box.add_child(_scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	_scroll.add_child(content)

	for i in UITheme.EPISODES.size():
		var episode: String = UITheme.EPISODES[i]
		var section := _build_episode_section(episode, i)
		_sections[episode] = section
		content.add_child(section)

	content.add_child(UITheme.make_spacer(40))
	var footer := UITheme.make_label("More episodes coming soon", 22, UITheme.INK_DIM, 3)
	content.add_child(footer)
	content.add_child(UITheme.make_spacer(40))

	await get_tree().process_frame
	await get_tree().process_frame
	_scroll_to_focus()


# --- Top bar -----------------------------------------------------------------

func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	var sb := UITheme.panel_style(Color(0.06, 0.03, 0.13, 0.92), 0)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	sb.shadow_size = 12
	bar.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

	var back := UITheme.make_ghost_button("BACK", UITheme.INK, 24)
	back.pressed.connect(func() -> void: UITheme.go_to_scene(self, UITheme.SCENE_MAIN_MENU))
	row.add_child(back)

	var stars_pill := PanelContainer.new()
	var pill_sb := UITheme.panel_style(Color(1, 1, 1, 0.10), 22, UITheme.GOLD, 2)
	pill_sb.content_margin_left = 16
	pill_sb.content_margin_right = 16
	pill_sb.content_margin_top = 8
	pill_sb.content_margin_bottom = 8
	stars_pill.add_theme_stylebox_override("panel", pill_sb)
	var pill_row := HBoxContainer.new()
	pill_row.add_theme_constant_override("separation", 8)
	stars_pill.add_child(pill_row)
	pill_row.add_child(StarIcon.new(true, 28))
	var total: int = Economy.total_stars() if Economy != null else 0
	_star_label = UITheme.make_label("%d / %d" % [total, UITheme.MAX_LEVEL * 3], 24, UITheme.GOLD, 4)
	pill_row.add_child(_star_label)
	row.add_child(stars_pill)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	row.add_child(CurrencyBar.new(false))
	return bar


# --- Episode sections --------------------------------------------------------

func _build_episode_section(episode: String, index: int) -> Control:
	# MarginContainer stacks all children into the same rect: background image,
	# tint scrim, then the content column on top.
	var section := MarginContainer.new()
	section.add_theme_constant_override("margin_left", 0)
	section.add_theme_constant_override("margin_right", 0)

	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := UITheme.texture("res://assets/backgrounds/%s.png" % episode)
	bg.texture = tex if tex != null else UITheme.gradient_texture(
		UITheme.episode_accent(episode).darkened(0.45), UITheme.episode_backdrop(episode))
	section.add_child(bg)

	var tint := ColorRect.new()
	var backdrop := UITheme.episode_backdrop(episode)
	tint.color = Color(backdrop.r, backdrop.g, backdrop.b, 0.62)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(tint)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 34)
	pad.add_theme_constant_override("margin_right", 34)
	pad.add_theme_constant_override("margin_top", 30)
	pad.add_theme_constant_override("margin_bottom", 38)
	section.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	pad.add_child(column)

	column.add_child(_build_episode_header(episode, index))

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 24)
	column.add_child(grid)

	var first := index * UITheme.LEVELS_PER_EPISODE + 1
	for n in range(first, first + UITheme.LEVELS_PER_EPISODE):
		grid.add_child(_build_level_node(n, episode))

	return section


func _build_episode_header(episode: String, index: int) -> Control:
	var accent := UITheme.episode_accent(episode)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)

	var badge := PanelContainer.new()
	var badge_sb := UITheme.panel_style(accent, 18)
	badge_sb.content_margin_left = 16
	badge_sb.content_margin_right = 16
	badge_sb.content_margin_top = 6
	badge_sb.content_margin_bottom = 6
	badge.add_theme_stylebox_override("panel", badge_sb)
	badge.add_child(UITheme.make_label("EPISODE %d" % (index + 1), 20, UITheme.OUTLINE, 0))
	header.add_child(badge)

	var title := UITheme.make_label(UITheme.EPISODE_TITLES.get(episode, episode).to_upper(), 34, UITheme.INK, 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var earned := 0
	var first := index * UITheme.LEVELS_PER_EPISODE + 1
	if Economy != null:
		for n in range(first, first + UITheme.LEVELS_PER_EPISODE):
			earned += Economy.stars_for(SceneRouter.level_id(n))
	var progress := HBoxContainer.new()
	progress.add_theme_constant_override("separation", 6)
	progress.add_child(StarIcon.new(true, 24))
	progress.add_child(UITheme.make_label("%d/%d" % [earned, UITheme.LEVELS_PER_EPISODE * 3], 22, UITheme.GOLD, 4))
	header.add_child(progress)
	return header


# --- Level nodes -------------------------------------------------------------

func _build_level_node(n: int, episode: String) -> Control:
	var unlocked: bool = Economy == null or Economy.is_level_unlocked(n)
	var stars: int = Economy.stars_for(SceneRouter.level_id(n)) if Economy != null else 0
	var is_current: bool = unlocked and Economy != null and n == Economy.highest_unlocked_level

	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 6)
	cell.alignment = BoxContainer.ALIGNMENT_CENTER

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
	btn.text = str(n) if unlocked else ""
	btn.disabled = not unlocked
	btn.add_theme_font_size_override("font_size", 44)
	btn.add_theme_color_override("font_color", UITheme.INK)
	btn.add_theme_color_override("font_hover_color", UITheme.INK)
	btn.add_theme_color_override("font_pressed_color", UITheme.INK)
	btn.add_theme_color_override("font_outline_color", UITheme.OUTLINE)
	btn.add_theme_constant_override("outline_size", 8)

	var accent := UITheme.episode_accent(episode)
	if stars > 0:
		accent = accent.lightened(0.12)
	btn.add_theme_stylebox_override("normal", _node_style(accent, is_current))
	btn.add_theme_stylebox_override("hover", _node_style(accent.lightened(0.15), is_current))
	var pressed := _node_style(accent.darkened(0.2), is_current)
	pressed.border_width_bottom = 0
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", _node_style(accent, is_current))

	var locked_style := _node_style(Color("2f2748"), false)
	locked_style.border_color = Color(1, 1, 1, 0.12)
	locked_style.set_border_width_all(2)
	btn.add_theme_stylebox_override("disabled", locked_style)

	UITheme.add_press_feedback(btn)
	cell.add_child(btn)

	if unlocked:
		btn.pressed.connect(_on_level_pressed.bind(n))
	else:
		var lock := LockIcon.new(NODE_SIZE * 0.42)
		lock.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock.modulate = Color(1, 1, 1, 0.75)
		btn.add_child(lock)

	if is_current:
		# The one node the player should tap next gets a heartbeat.
		UITheme.pulse(btn, 0.07, 1.1)

	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	star_row.add_theme_constant_override("separation", 2)
	for i in 3:
		star_row.add_child(StarIcon.new(i < stars, 22))
	star_row.modulate = Color(1, 1, 1, 1.0 if unlocked else 0.3)
	cell.add_child(star_row)
	return cell


func _node_style(base: Color, highlight: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = base
	sb.set_corner_radius_all(int(NODE_SIZE * 0.5))
	sb.set_content_margin_all(0)
	sb.border_width_bottom = 7
	sb.border_color = base.darkened(0.4)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 5)
	if highlight:
		sb.set_border_width_all(5)
		sb.border_width_bottom = 8
		sb.border_color = UITheme.GOLD
	return sb


func _on_level_pressed(n: int) -> void:
	if Economy != null and not Economy.is_level_unlocked(n):
		return
	if not SceneRouter.level_exists(n):
		UITheme.toast(self, "Level %d is still being built — check back soon!" % n)
		return
	if not SceneRouter.play_level(self, n):
		UITheme.toast(self, "Gameplay screen isn't wired up yet (level %d)." % n)


func _scroll_to_focus() -> void:
	if _scroll == null:
		return
	var target: int = focus_level_number
	if target <= 0:
		target = Economy.highest_unlocked_level if Economy != null else 1
	focus_level_number = 0 # consume, so a plain re-entry defaults to auto
	var episode := UITheme.episode_of_level(clampi(target, 1, UITheme.MAX_LEVEL))
	var section: Control = _sections.get(episode)
	if section == null:
		return
	var to: float = maxf(0.0, section.position.y - 8.0)
	var tw := _scroll.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_scroll, "scroll_vertical", int(to), 0.45)


## Android hardware back button — mirrors the on-screen BACK button.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		UITheme.go_to_scene(self, UITheme.SCENE_MAIN_MENU)
