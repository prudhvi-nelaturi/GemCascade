class_name GameplayController
extends Node2D

## Owns one playthrough of one level: the Board instance, the BoardView that
## draws it, the HUD, the boosters and the screen-level juice (shake + flash +
## combo popups).
##
## Scene entry contract: set `GameplayController.pending_level_number` before
## `change_scene_to_file("res://scenes/Gameplay.tscn")` — Godot has no way to
## pass arguments into a scene load, so a static var is the handoff.
##
## Cascade driving: rather than calling `Board.resolve_all()` (which resolves
## every tier in one synchronous burst and only hands back the final grid), this
## drives the identical loop one tier at a time —
## `find_matches()` -> `_process_groups()` -> animate the clear -> gravity ->
## animate the fall. That is the only way to know the *intermediate* board state
## each tier, which the view needs so incoming gems fall in with the colours
## they will actually have. `_process_groups`/`_apply_gravity_and_refill` are
## underscore-prefixed but not private (GDScript has no access control), and the
## sequence here mirrors `resolve_all()` exactly, including the cascade_index
## passed to each step so scoring is identical. `_resolve_fallback()` covers the
## case where those internals ever disappear.

static var pending_level_number: int = 1

const LEVEL_COMPLETE_SCENE := "res://scenes/LevelComplete.tscn"
const LEVEL_FAIL_SCENE := "res://scenes/LevelFail.tscn"
const MAIN_MENU_SCENE := "res://scenes/MainMenu.tscn"
const GAMEPLAY_SCENE := "res://scenes/Gameplay.tscn"

const MAX_CASCADE_TIERS := 64
const SHAKE_MAX := 22.0
const FLASH_MAX := 0.32
const END_BEAT := 0.5

var board: Board
var level: LevelData

var _view: BoardView
var _hud: GameplayHud
var _shake_root: Node2D
var _fx_layer: CanvasLayer
var _flash_rect: ColorRect
var _combo_label: Label

var _active_blockers: Dictionary = {} # Vector2i -> true, blockers not yet broken
var _input_locked: bool = false
var _ended: bool = false
var _end_kind: String = ""
var _end_payload: Dictionary = {}
var _moves_made: int = 0
var _hammer_armed: bool = false
var _combo_cells: int = 0
var _shake_home: Vector2 = Vector2.ZERO
var _shake_tween: Tween
var _combo_tween: Tween
var _supports_stepped_resolve: bool = true
var _economy_credited: bool = false

# ---------------------------------------------------------------------------
# Boot
# ---------------------------------------------------------------------------

func _ready() -> void:
	randomize()
	_resolve_nodes()
	_load_level()
	_setup_board()
	_build_background()
	_view.setup(board)
	_view.set_blockers(_active_blockers.keys())
	_hud.bind_level(level)
	_hud.refresh_boosters(true)
	_connect_signals()
	_view.set_input_enabled(true)

## Pulls the scene's nodes, creating any that are missing. The .tscn is the
## source of truth for structure, but the controller stays runnable if a node
## was renamed or the scene is instantiated bare in a test.
func _resolve_nodes() -> void:
	_shake_root = get_node_or_null("ShakeRoot") as Node2D
	if _shake_root == null:
		_shake_root = Node2D.new()
		_shake_root.name = "ShakeRoot"
		add_child(_shake_root)
	_shake_home = _shake_root.position

	_view = _shake_root.get_node_or_null("BoardView") as BoardView
	if _view == null:
		_view = BoardView.new()
		_view.name = "BoardView"
		_shake_root.add_child(_view)

	_hud = get_node_or_null("Hud") as GameplayHud
	if _hud == null:
		_hud = GameplayHud.new()
		_hud.name = "Hud"
		add_child(_hud)

	_fx_layer = get_node_or_null("FxLayer") as CanvasLayer
	if _fx_layer == null:
		_fx_layer = CanvasLayer.new()
		_fx_layer.name = "FxLayer"
		_fx_layer.layer = 20
		add_child(_fx_layer)

	_flash_rect = _fx_layer.get_node_or_null("Flash") as ColorRect
	if _flash_rect == null:
		_flash_rect = ColorRect.new()
		_flash_rect.name = "Flash"
		_fx_layer.add_child(_flash_rect)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 1, 1, 0)

	_combo_label = _fx_layer.get_node_or_null("Combo") as Label
	if _combo_label == null:
		_combo_label = Label.new()
		_combo_label.name = "Combo"
		_fx_layer.add_child(_combo_label)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_label.size = Vector2(640, 90)
	_combo_label.position = Vector2(40, 220)
	_combo_label.pivot_offset = Vector2(320, 45)
	_combo_label.add_theme_font_size_override("font_size", 64)
	_combo_label.add_theme_color_override("font_color", Color(1, 0.86, 0.3))
	_combo_label.add_theme_color_override("font_shadow_color", Color(0.25, 0.05, 0.35, 0.9))
	_combo_label.add_theme_constant_override("shadow_offset_x", 4)
	_combo_label.add_theme_constant_override("shadow_offset_y", 5)
	_combo_label.modulate = Color(1, 1, 1, 0)

func _connect_signals() -> void:
	_view.swap_requested.connect(_on_swap_requested)
	_view.cell_tapped.connect(_on_cell_tapped)
	_hud.booster_pressed.connect(_on_booster_pressed)
	LevelManager.level_won.connect(_on_level_won)
	LevelManager.level_lost.connect(_on_level_lost)
	LevelManager.objective_progress_changed.connect(_on_objective_progress_changed)

func _load_level() -> void:
	level = LevelManager.load_level(pending_level_number)
	if level == null:
		# Level resources are authored separately; a missing .tres must not make
		# the gameplay scene unplayable (it's also how this scene gets tested
		# before any level content exists).
		level = _make_fallback_level(pending_level_number)
		_install_level(level)

func _make_fallback_level(level_number: int) -> LevelData:
	var data := LevelData.new()
	data.level_number = level_number
	data.rows = 8
	data.cols = 8
	data.gem_type_count = 6
	data.move_limit = 20
	data.objective = LevelData.Objective.SCORE
	data.objective_target = 5000
	data.star_thresholds = [2500, 5000, 8000]
	return data

## Mirrors what LevelManager.load_level() would have done for a real resource.
func _install_level(data: LevelData) -> void:
	LevelManager.current_level = data
	LevelManager.moves_remaining = data.move_limit
	LevelManager.score = 0
	LevelManager.collected_of_color = 0
	LevelManager.blockers_remaining = data.blocker_cells.size()
	LevelManager._finished = false

func _setup_board() -> void:
	board = Board.new(level.rows, level.cols, level.gem_type_count, -1)
	board.fill_initial()
	_supports_stepped_resolve = board.has_method("_process_groups") and board.has_method("_apply_gravity_and_refill")
	if not _supports_stepped_resolve:
		push_warning("GameplayController: Board internals unavailable, falling back to whole-cascade resolve.")
	_active_blockers.clear()
	for cell in level.blocker_cells:
		if board.in_bounds(cell.x, cell.y):
			_active_blockers[cell] = true

## Backdrop: a vertical gradient plus a darker slab under the play area so gems
## read against it. Built in code so it scales with whatever board size the
## level data asks for.
func _build_background() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Background"
	layer.layer = -10
	add_child(layer)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.16, 0.08, 0.31))
	gradient.set_color(1, Color(0.05, 0.03, 0.12))
	var gradient_tex := GradientTexture2D.new()
	gradient_tex.gradient = gradient
	gradient_tex.fill_from = Vector2(0, 0)
	gradient_tex.fill_to = Vector2(0, 1)
	gradient_tex.width = 8
	gradient_tex.height = 128

	var backdrop := TextureRect.new()
	backdrop.texture = gradient_tex
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(backdrop)

	var rect: Rect2 = _view.board_rect()
	var slab := Panel.new()
	slab.position = rect.position - Vector2(12, 12)
	slab.size = rect.size + Vector2(24, 24)
	slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.16, 0.75)
	style.border_color = Color(0.35, 0.28, 0.62, 0.85)
	style.set_border_width_all(3)
	style.set_corner_radius_all(28)
	slab.add_theme_stylebox_override("panel", style)
	layer.add_child(slab)

# ---------------------------------------------------------------------------
# Player moves
# ---------------------------------------------------------------------------

func _on_swap_requested(a: Vector2i, b: Vector2i) -> void:
	if _input_locked or _ended:
		return
	_input_locked = true
	_view.set_input_enabled(false)
	await _perform_swap(a, b)
	_input_locked = false
	if not _ended and is_inside_tree():
		_view.set_input_enabled(true)

func _perform_swap(a: Vector2i, b: Vector2i) -> void:
	var gem_a: GemData = board.get_gem(a.x, a.y)
	var gem_b: GemData = board.get_gem(b.x, b.y)
	if gem_a == null or gem_b == null:
		return

	var both_special: bool = gem_a.is_special() and gem_b.is_special()
	var any_special: bool = gem_a.is_special() or gem_b.is_special()

	if not board.try_swap(a.x, a.y, b.x, b.y):
		await _view.animate_reject(a, b)
		return

	await _view.animate_swap(a, b)
	LevelManager.consume_move()
	_moves_made += 1
	_hud.refresh()
	_hud.refresh_boosters(false)
	_combo_cells = 0

	if both_special:
		# Board.try_swap() has already exchanged the two gems, so the combo is
		# evaluated on the post-swap grid. detonate_combo() does not run gravity
		# itself — _play_step() does that for every step uniformly.
		var combo_step: Dictionary = board.detonate_combo(a.x, a.y, b.x, b.y)
		await _play_step(combo_step)
		await _resolve_cascades(1)
	else:
		var tiers: int = await _resolve_cascades(0)
		if tiers == 0 and any_special:
			# Board accepts any swap involving a special even when no colour
			# match forms. Rather than silently burning the move, detonate the
			# special that was moved — which is also the expected behaviour for
			# a colour bomb swapped onto an ordinary gem.
			var lone_step: Dictionary = board.detonate_combo(a.x, a.y, b.x, b.y)
			await _play_step(lone_step)
			await _resolve_cascades(1)

	await _settle()

## Drives one cascade chain, one tier at a time. Returns the number of tiers.
func _resolve_cascades(start_index: int) -> int:
	if not _supports_stepped_resolve:
		return await _resolve_fallback()
	var tier: int = start_index
	var played: int = 0
	while played < MAX_CASCADE_TIERS:
		if not is_inside_tree():
			break
		var groups: Array = board.find_matches()
		if groups.is_empty():
			break
		var step: Dictionary = board._process_groups(groups, tier)
		await _play_step(step)
		played += 1
		tier += 1
	return played

## Degraded path used only if Board's per-step internals ever go away: resolve
## the whole chain at once, score every tier, then snap the view to the result.
func _resolve_fallback() -> int:
	var steps: Array = board.resolve_all()
	for step in steps:
		var typed_step: Dictionary = step
		_register_step_effects(typed_step)
		_apply_juice(typed_step)
		await _wait(0.12)
	_view.refresh_all_from_board()
	return steps.size()

## Animates one cascade tier: clear, then gravity. Scoring is applied at the
## moment of the clear so the HUD ticks with the pop rather than after it.
func _play_step(step: Dictionary) -> void:
	_register_step_effects(step)
	_apply_juice(step)

	await _view.animate_clear_phase(step)
	if not is_inside_tree():
		return
	board._apply_gravity_and_refill()
	await _view.animate_gravity_phase()

## Everything non-visual a step causes: blocker bookkeeping, LevelManager
## scoring, HUD refresh and the combo popup.
func _register_step_effects(step: Dictionary) -> void:
	var cleared: Array = step.get("cleared", [])
	var cascade_index: int = int(step.get("cascade_index", 0))
	_combo_cells += cleared.size()

	var broken: Array = []
	for cell in cleared:
		if _active_blockers.has(cell):
			_active_blockers.erase(cell)
			broken.append(cell)
	if not broken.is_empty():
		_view.break_blockers(broken)

	LevelManager.apply_step_result(step, broken.size())
	_hud.refresh()
	_hud.pulse_score()

	if cascade_index >= 1:
		_show_combo_popup(cascade_index)

# ---------------------------------------------------------------------------
# Juice
# ---------------------------------------------------------------------------

## Shake and flash scale with the cascade tier and with whether a special was
## just born, then hard-cap — a ten-tier chain should feel enormous without
## making the board unreadable.
func _apply_juice(step: Dictionary) -> void:
	var cascade_index: int = int(step.get("cascade_index", 0))
	var specials: Array = step.get("specials_created", [])
	if cascade_index <= 0 and specials.is_empty():
		return
	var tier: float = float(cascade_index)
	if not specials.is_empty():
		tier += 1.0
	var magnitude: float = minf(5.0 + tier * 4.5, SHAKE_MAX)
	var alpha: float = minf(0.08 + tier * 0.05, FLASH_MAX)
	_shake(magnitude, 0.15 + minf(tier * 0.015, 0.09))
	_flash(alpha, _dominant_color(step))

func _dominant_color(step: Dictionary) -> Color:
	var counts: Dictionary = step.get("color_counts", {})
	var best_color: int = -1
	var best_count: int = 0
	for key in counts.keys():
		var value: int = int(counts[key])
		if value > best_count:
			best_count = value
			best_color = int(key)
	if best_color < 0:
		return Color(1, 1, 1)
	return Color(1, 1, 1).lerp(GemArt.color_of(best_color), 0.35)

func _shake(magnitude: float, duration: float) -> void:
	if _shake_root == null:
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var steps: int = maxi(4, int(duration / 0.02))
	_shake_tween = create_tween()
	for i in range(steps):
		var falloff: float = 1.0 - float(i) / float(steps)
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * magnitude * falloff
		_shake_tween.tween_property(_shake_root, "position", _shake_home + offset, duration / float(steps))
	_shake_tween.tween_property(_shake_root, "position", _shake_home, 0.05).set_trans(Tween.TRANS_SINE)

func _flash(alpha: float, tint: Color = Color(1, 1, 1)) -> void:
	if _flash_rect == null:
		return
	_flash_rect.color = Color(tint.r, tint.g, tint.b, alpha)
	var tween := _flash_rect.create_tween()
	tween.tween_property(_flash_rect, "color:a", 0.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _show_combo_popup(cascade_index: int) -> void:
	if _combo_label == null:
		return
	if _combo_tween != null and _combo_tween.is_valid():
		_combo_tween.kill()
	_combo_label.text = "COMBO x%d!" % (cascade_index + 1)
	var boost: float = minf(1.0 + cascade_index * 0.12, 1.6)
	_combo_label.scale = Vector2(0.35, 0.35)
	_combo_label.position = Vector2(40, 220)
	_combo_label.modulate = Color(1, 1, 1, 1)
	_combo_tween = _combo_label.create_tween()
	_combo_tween.tween_property(_combo_label, "scale", Vector2(boost, boost), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_combo_tween.set_parallel(true)
	_combo_tween.tween_property(_combo_label, "position:y", 140.0, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_combo_tween.tween_property(_combo_label, "modulate:a", 0.0, 0.55).set_delay(0.15)

# ---------------------------------------------------------------------------
# Settling: end conditions, then stuck-board detection
# ---------------------------------------------------------------------------

func _settle() -> void:
	if _ended:
		await _finish_level()
		return
	# LevelManager only evaluates end conditions inside apply_step_result(), so a
	# final move that matched nothing would otherwise never register as a loss.
	if LevelManager.moves_remaining <= 0:
		LevelManager._check_end_conditions()
		if _ended:
			await _finish_level()
			return
	var attempts: int = 0
	while attempts < 3 and not board.has_any_valid_move():
		await _do_shuffle()
		attempts += 1

func _do_shuffle() -> void:
	_hud.show_toast("No moves left — shuffling...", 1.0)
	_view.set_input_enabled(false)
	await _view.animate_board_out()
	board.shuffle()
	_view.refresh_all_from_board()
	await _view.animate_board_in()
	# shuffle() only *tries* to land on a match-free arrangement and gives up
	# after a bounded number of attempts, which it can genuinely do on a board
	# down to very few distinct colours. Resolve whatever it left behind rather
	# than handing the player a board with a match already sitting on it.
	if not board.find_matches().is_empty():
		await _resolve_cascades(0)
	if not _ended and is_inside_tree():
		_view.set_input_enabled(true)

# ---------------------------------------------------------------------------
# Boosters
# ---------------------------------------------------------------------------

func _on_booster_pressed(booster_id: String) -> void:
	if _ended:
		return
	if booster_id == Economy.BOOSTER_EXTRA_MOVES:
		_use_extra_moves()
	elif booster_id == Economy.BOOSTER_HAMMER:
		_toggle_hammer()
	elif booster_id == Economy.BOOSTER_COLOR_BOMB_START:
		_use_color_bomb_start()

func _use_extra_moves() -> void:
	if Economy.booster_count(Economy.BOOSTER_EXTRA_MOVES) <= 0:
		_hud.show_toast("No extra-move boosters left")
		return
	if not Economy.consume_booster(Economy.BOOSTER_EXTRA_MOVES):
		return
	LevelManager.grant_extra_moves(5)
	_hud.refresh()
	_hud.refresh_boosters(_moves_made == 0)
	_hud.show_toast("+5 moves!")
	_flash(0.12, Color(0.5, 1.0, 0.7))

func _toggle_hammer() -> void:
	if _input_locked:
		return
	if _hammer_armed:
		_hammer_armed = false
		_view.set_hammer_mode(false)
		_hud.show_toast("Hammer put away")
		return
	if Economy.booster_count(Economy.BOOSTER_HAMMER) <= 0:
		_hud.show_toast("No hammers left")
		return
	_hammer_armed = true
	_view.set_hammer_mode(true)
	_hud.show_toast("Tap any gem to smash it")

## Replaces one random gem with a colour bomb. Only legal before the first move
## — it's a pre-level booster, not a mid-level rescue.
func _use_color_bomb_start() -> void:
	if _moves_made > 0:
		_hud.show_toast("Only before your first move")
		return
	if Economy.booster_count(Economy.BOOSTER_COLOR_BOMB_START) <= 0:
		_hud.show_toast("No colour-bomb boosters left")
		return
	if not Economy.consume_booster(Economy.BOOSTER_COLOR_BOMB_START):
		return
	var cell := Vector2i(randi() % board.rows, randi() % board.cols)
	var existing: GemData = board.get_gem(cell.x, cell.y)
	var color: int = existing.color if existing != null else 0
	board._set_gem(cell.x, cell.y, GemData.new(color, GemTypes.Special.COLOR_BOMB))
	_view.refresh_cell(cell, true)
	_hud.refresh_boosters(false)
	_hud.show_toast("Colour bomb dropped in!")
	_shake(9.0, 0.16)
	_flash(0.16)

func _on_cell_tapped(cell: Vector2i) -> void:
	if not _hammer_armed or _input_locked or _ended:
		return
	if not Economy.consume_booster(Economy.BOOSTER_HAMMER):
		_hammer_armed = false
		_view.set_hammer_mode(false)
		return
	_hammer_armed = false
	_view.set_hammer_mode(false)
	_hud.refresh_boosters(_moves_made == 0)

	_input_locked = true
	_view.set_input_enabled(false)
	_combo_cells = 0
	# A hammer strike is a booster, not a move, so consume_move() is not called.
	await _play_step(_manual_clear(cell))
	await _resolve_cascades(0)
	await _settle()
	_input_locked = false
	if not _ended and is_inside_tree():
		_view.set_input_enabled(true)

## Clears cells outside the normal match flow (the hammer) and shapes the result
## like a Board step so it flows through the same animation and scoring path.
func _manual_clear(cell: Vector2i) -> Dictionary:
	var targets := {cell: true}
	var gem: GemData = board.get_gem(cell.x, cell.y)
	if gem != null and gem.is_special():
		for extra in board._detonation_cells(cell, gem.special):
			targets[extra] = true

	var color_counts := {}
	for target in targets.keys():
		var g: GemData = board.get_gem(target.x, target.y)
		if g != null:
			color_counts[g.color] = int(color_counts.get(g.color, 0)) + 1
			board._set_gem(target.x, target.y, null)

	return {
		"cleared": targets.keys(),
		"specials_created": [],
		"color_counts": color_counts,
		"cascade_index": 0,
	}

# ---------------------------------------------------------------------------
# End of level
# ---------------------------------------------------------------------------

func _on_objective_progress_changed() -> void:
	if _hud != null:
		_hud.refresh()

## LevelManager deliberately does not touch Economy, so awarding the level's
## coins/stars and unlocking the next level has to happen somewhere on the
## integration layer — and that somewhere is normally LevelCompleteScreen._ready(),
## which calls Economy.record_level_result() + Economy.unlock_next_level() from
## the `pending_result` payload built below (see the contract block at the top of
## scripts/ui/LevelComplete.gd). Crediting here as well paid every win out twice.
##
## So the rule is "exactly one of us credits, decided at handoff time" rather
## than "the controller never credits" — see _credit_economy_once().
func _on_level_won(stars: int, score: int, coins_earned: int) -> void:
	if _ended:
		return
	_ended = true
	_end_kind = "win"
	_end_payload = {
		"level_number": level.level_number,
		"won": true,
		"stars": stars,
		"score": score,
		"coins_earned": coins_earned,
		"moves_left": LevelManager.moves_remaining,
		"progress": LevelManager.objective_progress_fraction(),
	}
	_view.set_input_enabled(false)
	_hud.show_toast("LEVEL COMPLETE!", 1.2)
	_shake(SHAKE_MAX, 0.3)
	_flash(FLASH_MAX)

func _on_level_lost() -> void:
	if _ended:
		return
	_ended = true
	_end_kind = "lose"
	_end_payload = {
		"level_number": level.level_number,
		"won": false,
		"stars": 0,
		"score": LevelManager.score,
		"coins_earned": 0,
		"moves_left": 0,
		"progress": LevelManager.objective_progress_fraction(),
	}
	_view.set_input_enabled(false)
	_hud.show_toast("Out of moves!", 1.2)

func _finish_level() -> void:
	await _wait(END_BEAT)
	if not is_inside_tree():
		return
	var path: String = LEVEL_COMPLETE_SCENE if _end_kind == "win" else LEVEL_FAIL_SCENE
	_go_to_result_scene(path, _end_payload)

## Hands the result to the LevelComplete/LevelFail scene through the same
## static-var contract this scene uses (`pending_result`). The scene is
## instantiated here rather than via change_scene_to_file() so the static can be
## written on its script *before* its _ready() runs. If the scene does not exist
## yet, an in-scene panel takes over so the level always has an ending.
func _go_to_result_scene(path: String, payload: Dictionary) -> void:
	if not ResourceLoader.exists(path):
		_credit_economy_once()
		_show_fallback_result_panel(payload)
		return
	var packed: Resource = ResourceLoader.load(path)
	if not (packed is PackedScene):
		_credit_economy_once()
		_show_fallback_result_panel(payload)
		return
	var instance: Node = (packed as PackedScene).instantiate()
	var script: Script = instance.get_script()
	if script != null and script.get("pending_result") != null:
		script.set("pending_result", payload)
	else:
		# The target screen does not implement the `pending_result` contract, so
		# nobody downstream is going to credit the win.
		_credit_economy_once()
	if "pending_result" in instance:
		instance.set("pending_result", payload)

	var tree := get_tree()
	var old_scene: Node = tree.current_scene
	tree.root.add_child(instance)
	tree.current_scene = instance
	if old_scene != null and old_scene != instance and old_scene.get_parent() == tree.root:
		tree.root.remove_child(old_scene)
		old_scene.queue_free()

## Credits a win to Economy, but only when the screen we are handing off to
## won't. LevelCompleteScreen declares a static `pending_result` and credits the
## payload itself; probing for that static is how "who owns persistence" is
## decided at runtime rather than by assumption, so exactly one side pays out
## whichever way the meta-UI evolves. A loss credits nothing either way.
func _credit_economy_once() -> void:
	if _economy_credited or _end_kind != "win":
		return
	_economy_credited = true
	Economy.record_level_result(
		"level_%03d" % int(_end_payload.get("level_number", level.level_number)),
		int(_end_payload.get("stars", 0)),
		int(_end_payload.get("coins_earned", 0)))
	Economy.unlock_next_level(int(_end_payload.get("level_number", level.level_number)) + 1)

func _show_fallback_result_panel(payload: Dictionary) -> void:
	var layer := CanvasLayer.new()
	layer.name = "ResultFallback"
	layer.layer = 30
	add_child(layer)

	var panel := Panel.new()
	panel.position = Vector2(70, 420)
	panel.size = Vector2(580, 440)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.18, 0.97)
	style.border_color = Color(0.55, 0.45, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(28)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	var won: bool = bool(payload.get("won", false))
	var title := Label.new()
	title.text = "LEVEL COMPLETE" if won else "OUT OF MOVES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 40)
	title.size = Vector2(580, 60)
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1, 0.86, 0.3) if won else Color(1, 0.5, 0.5))
	panel.add_child(title)

	var detail := Label.new()
	detail.text = "Score %d\nStars %d\nCoins +%d" % [
		int(payload.get("score", 0)),
		int(payload.get("stars", 0)),
		int(payload.get("coins_earned", 0)),
	]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.position = Vector2(0, 130)
	detail.size = Vector2(580, 170)
	detail.add_theme_font_size_override("font_size", 32)
	panel.add_child(detail)

	var retry := Button.new()
	retry.text = "RETRY"
	retry.position = Vector2(60, 330)
	retry.size = Vector2(200, 74)
	retry.add_theme_font_size_override("font_size", 26)
	retry.pressed.connect(_on_retry_pressed)
	panel.add_child(retry)

	var menu := Button.new()
	menu.text = "MENU"
	menu.position = Vector2(320, 330)
	menu.size = Vector2(200, 74)
	menu.add_theme_font_size_override("font_size", 26)
	menu.pressed.connect(_on_menu_pressed)
	panel.add_child(menu)

func _on_retry_pressed() -> void:
	pending_level_number = level.level_number
	if ResourceLoader.exists(GAMEPLAY_SCENE):
		get_tree().change_scene_to_file(GAMEPLAY_SCENE)

func _on_menu_pressed() -> void:
	if ResourceLoader.exists(MAIN_MENU_SCENE):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)

# ---------------------------------------------------------------------------

func _wait(seconds: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(maxf(0.01, seconds)).timeout
