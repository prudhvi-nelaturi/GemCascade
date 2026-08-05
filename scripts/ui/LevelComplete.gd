class_name LevelCompleteScreen
extends Control

## ============================================================================
## INTEGRATION CONTRACT — read this before wiring up the gameplay screen.
##
## The gameplay screen sets this static var and then changes scene:
##
##     LevelCompleteScreen.pending_result = {
##         "level_number": int,   # the level that was just cleared (1-based)
##         "stars": int,          # 0-3, from LevelData.stars_for_score(score)
##         "score": int,          # final score
##         "coins_earned": int,   # coins to award (LevelManager uses 20 + stars*15)
##     }
##     get_tree().change_scene_to_file("res://scenes/LevelComplete.tscn")
##
## THIS SCREEN owns persistence — the gameplay side must NOT also credit the
## economy, or every win pays out twice:
##     Economy.record_level_result("level_%03d" % level_number, stars, coins_earned)
##     Economy.unlock_next_level(level_number + 1)
## are both called here, in _ready(), exactly once. pending_result is consumed
## (cleared) on read so a scene reload can't double-credit either.
##
## Missing keys degrade gracefully; an entirely empty pending_result puts the
## screen into a self-contained demo mode that credits nothing (which is what
## the headless smoke test exercises).
## ============================================================================

static var pending_result: Dictionary = {}

var _level_number: int = 0
var _stars: int = 0
var _score: int = 0
var _coins_earned: int = 0
var _demo_mode: bool = false

var _card: PanelContainer
var _banner: Label
var _score_label: Label
var _coins_row: Control
var _perfect_label: Label
var _buttons: Control
var _star_slots: Array[Control] = []
var _star_fills: Array[StarIcon] = []
var _star_rings: Array[BurstRing] = []
var _star_bursts: Array[CPUParticles2D] = []
var _confetti: CPUParticles2D

func _ready() -> void:
	GameSettings.apply()
	_consume_result()
	_credit_progress()
	_build_ui()

	await get_tree().process_frame
	await get_tree().process_frame
	_play_celebration()


# --- contract handling -------------------------------------------------------

func _consume_result() -> void:
	var result: Dictionary = pending_result.duplicate()
	pending_result = {}

	_level_number = int(result.get("level_number", 0))
	_stars = clampi(int(result.get("stars", 0)), 0, 3)
	_score = maxi(0, int(result.get("score", 0)))
	_coins_earned = maxi(0, int(result.get("coins_earned", 0)))

	if _level_number <= 0:
		# Opened directly (editor run / smoke test) — show something sensible but
		# never touch the save file.
		_demo_mode = true
		_level_number = maxi(1, Economy.highest_unlocked_level if Economy != null else 1)
		_stars = 3
		_score = 12480
		_coins_earned = 65
		push_warning("LevelCompleteScreen: no pending_result — running in demo mode, nothing credited.")


func _credit_progress() -> void:
	if _demo_mode or Economy == null:
		return
	Economy.record_level_result(SceneRouter.level_id(_level_number), _stars, _coins_earned)
	Economy.unlock_next_level(_level_number + 1)


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	var episode := UITheme.episode_of_level(_level_number)
	add_child(UITheme.make_background(episode))
	add_child(UITheme.make_scrim(0.62))

	_confetti = _make_confetti()
	add_child(_confetti)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(600, 0)
	var card_sb := UITheme.panel_style(Color("1a0f33"), 36, UITheme.GOLD, 4)
	card_sb.set_content_margin_all(30)
	card_sb.shadow_size = 26
	_card.add_theme_stylebox_override("panel", card_sb)
	center.add_child(_card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	_card.add_child(column)

	_banner = UITheme.make_label("LEVEL COMPLETE!", 46, UITheme.GOLD, 10)
	column.add_child(_banner)

	var sub := UITheme.make_label("Level %d  ·  %s" % [
		_level_number, UITheme.EPISODE_TITLES.get(episode, "")], 22, UITheme.INK_DIM, 3)
	column.add_child(sub)

	column.add_child(_build_star_row())

	_perfect_label = UITheme.make_label("PERFECT!", 34, UITheme.PINK, 8)
	_perfect_label.modulate.a = 0.0
	column.add_child(_perfect_label)

	# Score
	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", -4)
	column.add_child(score_box)
	score_box.add_child(UITheme.make_label("SCORE", 20, UITheme.INK_DIM, 0))
	_score_label = UITheme.make_label("0", 52, UITheme.INK, 8)
	score_box.add_child(_score_label)

	# Coins earned
	_coins_row = HBoxContainer.new()
	var coins_row := _coins_row as HBoxContainer
	coins_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coins_row.add_theme_constant_override("separation", 10)
	coins_row.add_child(UITheme.make_currency_icon("coin", 44))
	coins_row.add_child(UITheme.make_label("+%d" % _coins_earned, 38, UITheme.GOLD, 6))
	coins_row.modulate.a = 0.0
	column.add_child(_coins_row)

	column.add_child(UITheme.make_spacer(6))

	_buttons = VBoxContainer.new()
	var buttons := _buttons as VBoxContainer
	buttons.add_theme_constant_override("separation", 14)
	buttons.modulate.a = 0.0
	column.add_child(_buttons)

	var next := UITheme.make_button("NEXT LEVEL", UITheme.GREEN, 34)
	next.custom_minimum_size = Vector2(0, 88)
	next.pressed.connect(_on_next_pressed)
	buttons.add_child(next)

	var map := UITheme.make_button("LEVEL MAP", UITheme.PURPLE, 28)
	map.custom_minimum_size = Vector2(0, 70)
	map.pressed.connect(_on_map_pressed)
	buttons.add_child(map)


func _build_star_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)

	for i in 3:
		var px: float = 150.0 if i == 1 else 124.0
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(px, px)
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var ring := BurstRing.new()
		ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(ring)

		var empty := StarIcon.new(false, px)
		empty.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(empty)

		var fill := StarIcon.new(true, px)
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
		fill.modulate.a = 0.0
		fill.scale = Vector2(2.6, 2.6)
		slot.add_child(fill)

		var burst := _make_star_burst()
		burst.position = Vector2(px, px) * 0.5
		slot.add_child(burst)

		row.add_child(slot)
		_star_slots.append(slot)
		_star_fills.append(fill)
		_star_rings.append(ring)
		_star_bursts.append(burst)
	return row


func _make_star_burst() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 26
	p.lifetime = 0.9
	p.texture = UITheme.dot_texture(12)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 420.0
	p.gravity = Vector2(0, 620)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	p.damping_min = 40.0
	p.damping_max = 90.0
	p.color_initial_ramp = UITheme.party_ramp()
	return p


func _make_confetti() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.55
	p.amount = 140
	p.lifetime = 2.6
	p.position = Vector2(360, -30)
	p.texture = UITheme.square_texture(8)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(380, 12)
	p.direction = Vector2(0, 1)
	p.spread = 30.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 340.0
	p.gravity = Vector2(0, 320)
	p.angular_velocity_min = -420.0
	p.angular_velocity_max = 420.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.8
	p.color_initial_ramp = UITheme.party_ramp()
	return p


# --- the celebration ---------------------------------------------------------

## Beat-by-beat reveal. The stars are the payoff, so everything else (card,
## banner, score, coins, buttons) is deliberately sequenced around them rather
## than appearing at once.
func _play_celebration() -> void:
	UITheme.pop_in(_card, 0.0, 0.72, 0.5)

	if is_instance_valid(_banner):
		_banner.pivot_offset = _banner.size * 0.5
		_banner.scale = Vector2(0.2, 0.2)
		var bt := _banner.create_tween()
		bt.tween_interval(0.12)
		bt.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		bt.tween_property(_banner, "scale", Vector2.ONE, 0.7)

	await get_tree().create_timer(0.45).timeout

	for i in 3:
		if i < _stars:
			_reveal_star(i)
			await get_tree().create_timer(0.42).timeout
		else:
			_miss_star(i)
			await get_tree().create_timer(0.18).timeout

	if _stars >= 3:
		_celebrate_perfect()
	elif _stars > 0 and is_instance_valid(_confetti):
		_confetti.amount = 70
		_confetti.restart()
		_confetti.emitting = true

	_count_up_score()

	await get_tree().create_timer(0.55).timeout
	if is_instance_valid(_coins_row):
		UITheme.pop_in(_coins_row, 0.0, 0.4, 0.45)

	await get_tree().create_timer(0.35).timeout
	if is_instance_valid(_buttons):
		UITheme.slide_in(_buttons, 0.0, 40.0, 0.35)


func _reveal_star(index: int) -> void:
	var fill := _star_fills[index]
	var slot := _star_slots[index]
	if not is_instance_valid(fill):
		return
	fill.pivot_offset = fill.size * 0.5
	var tw := fill.create_tween()
	tw.set_parallel(true)
	tw.tween_property(fill, "modulate:a", 1.0, 0.14)
	tw.tween_property(fill, "scale", Vector2.ONE, 0.42)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Slot squash-and-settle after the star lands, so it reads as an impact.
	var st := slot.create_tween()
	st.tween_interval(0.30)
	st.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	slot.pivot_offset = slot.size * 0.5
	st.tween_property(slot, "scale", Vector2(1.18, 1.18), 0.10)
	st.tween_property(slot, "scale", Vector2.ONE, 0.22)

	# Shockwave + particle burst timed to the landing, plus a punch on the card.
	var ring := _star_rings[index]
	var burst := _star_bursts[index]
	var punch := func() -> void:
		if is_instance_valid(ring):
			ring.play(0.5)
		if is_instance_valid(burst):
			burst.restart()
			burst.emitting = true
		_punch_card()
	get_tree().create_timer(0.28).timeout.connect(punch)


func _miss_star(index: int) -> void:
	var slot := _star_slots[index]
	if not is_instance_valid(slot):
		return
	slot.pivot_offset = slot.size * 0.5
	var tw := slot.create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(slot, "modulate:a", 0.45, 0.15)


func _punch_card() -> void:
	if not is_instance_valid(_card):
		return
	_card.pivot_offset = _card.size * 0.5
	var tw := _card.create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "scale", Vector2(1.025, 1.025), 0.07)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.18)


func _celebrate_perfect() -> void:
	if is_instance_valid(_confetti):
		_confetti.amount = 160
		_confetti.restart()
		_confetti.emitting = true
	if not is_instance_valid(_perfect_label):
		return
	_perfect_label.pivot_offset = _perfect_label.size * 0.5
	_perfect_label.scale = Vector2(0.3, 0.3)
	var tw := _perfect_label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(_perfect_label, "modulate:a", 1.0, 0.2)
	tw.tween_property(_perfect_label, "scale", Vector2.ONE, 0.6)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _count_up_score() -> void:
	if not is_instance_valid(_score_label):
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_score_text, 0.0, float(_score), 0.9)


func _set_score_text(value: float) -> void:
	if is_instance_valid(_score_label):
		_score_label.text = str(int(round(value)))


# --- navigation --------------------------------------------------------------

func _on_next_pressed() -> void:
	var next_level := _level_number + 1
	if next_level > UITheme.MAX_LEVEL or not SceneRouter.level_exists(next_level):
		UITheme.toast(self, "That's the last level for now — more episodes coming soon!")
		LevelMapScreen.focus_level_number = _level_number
		await get_tree().create_timer(0.9).timeout
		UITheme.go_to_scene(self, UITheme.SCENE_LEVEL_MAP)
		return
	if not SceneRouter.play_level(self, next_level):
		UITheme.toast(self, "Gameplay screen isn't wired up yet.")


func _on_map_pressed() -> void:
	LevelMapScreen.focus_level_number = _level_number + 1
	UITheme.go_to_scene(self, UITheme.SCENE_LEVEL_MAP)


## Android hardware back button — falls through to the level map rather than
## dropping the player back into the level they just cleared.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_map_pressed()
