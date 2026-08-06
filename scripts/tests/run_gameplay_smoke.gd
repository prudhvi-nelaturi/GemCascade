extends SceneTree

## Headless integration smoke test for the gameplay scene. run_tests.gd covers
## the pure logic; this covers the parts that only exist once there is a real
## SceneTree: scene instantiation, the BoardView mirror staying in sync with the
## Board across cascades, boosters, blocker bookkeeping and the end-of-level
## handoff. There is no display in this environment, so this is what stands in
## for playing the build.
##
##   godot --headless --script res://scripts/tests/run_gameplay_smoke.gd

const GAMEPLAY_SCENE := "res://scenes/Gameplay.tscn"

# The autoload identifiers (LevelManager/Economy) are not resolvable while the
# main-loop script itself is being compiled, so they are looked up as nodes and
# the booster ids are mirrored here — _test_booster_ids_match() proves the
# mirror still agrees with Economy.gd.
const B_EXTRA_MOVES := "extra_moves"
const B_HAMMER := "hammer"
const B_BOMB_START := "color_bomb_start"

var _lm: Node
var _econ: Node

var _pass := 0
var _fail := 0
var _current := ""

func _initialize() -> void:
	print("=== GemCascade gameplay smoke test ===")
	_lm = root.get_node("LevelManager")
	_econ = root.get_node("Economy")
	_run()

func _run() -> void:
	await _test_booster_ids_match()
	await _test_scripts_compile()
	await _test_scene_boots()
	await _test_valid_swap_resolves()
	await _test_rejected_swap_costs_nothing()
	await _test_special_swap_detonates()
	await _test_hammer_booster()
	await _test_color_bomb_start_booster()
	await _test_extra_moves_booster()
	await _test_blocker_accounting()
	await _test_shuffle_on_dead_board()
	await _test_out_of_moves_loses()
	await _test_input_gestures()
	await _test_win_awards_economy()
	await _test_win_fallback_credits_itself()
	await _test_win_handoff_credits_exactly_once()
	await _test_every_shipped_level_boots()
	await _test_static_var_handoff()

	print("\n=== smoke: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

# ---------------------------------------------------------------------------
# Assertions / helpers
# ---------------------------------------------------------------------------

func _begin(name: String) -> void:
	_current = name

func _ok(condition: bool, message: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("FAIL [%s] %s" % [_current, message])

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _seconds(amount: float) -> void:
	await create_timer(amount).timeout

## Waits for the controller to finish whatever animation chain it is running.
func _wait_idle(controller: Node, timeout: float = 8.0) -> void:
	var waited := 0.0
	while controller._input_locked and waited < timeout:
		await create_timer(0.05).timeout
		waited += 0.05

func _make_controller(level_number: int = 1) -> Node:
	# Loaded dynamically rather than referenced by class name: a static
	# reference would force GameplayController.gd to compile while this
	# main-loop script is loading, which is before the autoloads it depends on
	# have been registered.
	var controller_script: GDScript = load("res://scripts/gameplay/GameplayController.gd")
	controller_script.set("pending_level_number", level_number)
	var packed: PackedScene = load(GAMEPLAY_SCENE)
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await _frames(2)
	return instance

func _teardown(controller: Node) -> void:
	if is_instance_valid(controller):
		root.remove_child(controller)
		controller.queue_free()
	await _frames(3)

## The single most important invariant in the whole gameplay layer: the sprite
## grid BoardView maintains must describe exactly the grid Board holds.
func _views_match_board(controller: Node, check_positions: bool = true) -> String:
	var board: Board = controller.board
	var view: BoardView = controller._view
	for r in range(board.rows):
		for c in range(board.cols):
			var gem: GemData = board.get_gem(r, c)
			var gv: GemView = view._views[r][c]
			if gem == null:
				if gv != null:
					return "cell (%d,%d) empty on board but has a sprite" % [r, c]
				continue
			if gv == null:
				return "cell (%d,%d) has a gem but no sprite" % [r, c]
			if not gv.matches(gem.color, gem.special):
				return "cell (%d,%d) sprite is (%d/%d), board is (%d/%d)" % [
					r, c, gv.gem_color, gv.gem_special, gem.color, gem.special]
			if check_positions:
				var expected: Vector2 = view.cell_center(Vector2i(r, c))
				if gv.position.distance_to(expected) > 1.0:
					return "cell (%d,%d) sprite at %s, expected %s" % [r, c, str(gv.position), str(expected)]
	return ""

func _count_empty_cells(board: Board) -> int:
	var empty := 0
	for r in range(board.rows):
		for c in range(board.cols):
			if board.get_gem(r, c) == null:
				empty += 1
	return empty

func _find_valid_swap(board: Board) -> Array:
	for r in range(board.rows):
		for c in range(board.cols):
			if c + 1 < board.cols and board._would_swap_match(r, c, r, c + 1):
				return [Vector2i(r, c), Vector2i(r, c + 1)]
			if r + 1 < board.rows and board._would_swap_match(r, c, r + 1, c):
				return [Vector2i(r, c), Vector2i(r + 1, c)]
	return []

func _find_invalid_swap(board: Board) -> Array:
	for r in range(board.rows):
		for c in range(board.cols):
			if c + 1 >= board.cols:
				continue
			var a: GemData = board.get_gem(r, c)
			var b: GemData = board.get_gem(r, c + 1)
			if a == null or b == null or a.is_special() or b.is_special():
				continue
			if not board._would_swap_match(r, c, r, c + 1):
				return [Vector2i(r, c), Vector2i(r, c + 1)]
	return []

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func _test_booster_ids_match() -> void:
	_begin("booster_ids_match")
	var econ_script: GDScript = _econ.get_script()
	var constants: Dictionary = econ_script.get_script_constant_map()
	_ok(constants.get("BOOSTER_EXTRA_MOVES", "") == B_EXTRA_MOVES, "BOOSTER_EXTRA_MOVES id drifted")
	_ok(constants.get("BOOSTER_HAMMER", "") == B_HAMMER, "BOOSTER_HAMMER id drifted")
	_ok(constants.get("BOOSTER_COLOR_BOMB_START", "") == B_BOMB_START, "BOOSTER_COLOR_BOMB_START id drifted")
	await _frames(1)

func _test_scripts_compile() -> void:
	_begin("scripts_compile")
	# --check-only cannot resolve autoload identifiers, so compilation of the
	# gameplay scripts is confirmed here instead, where the autoloads exist.
	for path in [
		"res://scripts/gameplay/GemArt.gd",
		"res://scripts/gameplay/GemView.gd",
		"res://scripts/gameplay/BoardView.gd",
		"res://scripts/gameplay/GameplayHud.gd",
		"res://scripts/gameplay/GameplayController.gd",
	]:
		var script: Resource = load(path)
		_ok(script != null and script is GDScript, "%s failed to compile" % path)
	await _frames(1)

func _test_scene_boots() -> void:
	_begin("scene_boots")
	var controller: Node = await _make_controller()
	_ok(controller != null, "scene did not instantiate")
	_ok(controller.board != null, "controller has no board")
	_ok(controller.level != null, "controller has no level data")
	_ok(controller.board.rows == controller.level.rows, "board rows do not match level data")
	_ok(_count_empty_cells(controller.board) == 0, "board has empty cells after fill_initial()")
	_ok(controller.board.has_any_valid_move(), "fresh board has no valid move")
	_ok(controller.board.find_matches().is_empty(), "fresh board starts with a match already on it")
	_ok(_views_match_board(controller) == "", "view/board mismatch at boot: " + _views_match_board(controller))
	_ok(controller._view.cell_size > 10.0, "cell size was not computed")
	var rect: Rect2 = controller._view.board_rect()
	_ok(rect.position.x >= 0.0 and rect.end.x <= 720.0, "board is wider than the viewport: %s" % str(rect))
	_ok(rect.position.y >= 260.0 and rect.end.y <= 1040.0, "board overlaps the HUD bands: %s" % str(rect))
	await _teardown(controller)

func _test_valid_swap_resolves() -> void:
	_begin("valid_swap_resolves")
	var controller: Node = await _make_controller()
	var pair: Array = _find_valid_swap(controller.board)
	_ok(not pair.is_empty(), "no valid swap found on a fresh board")
	if pair.is_empty():
		await _teardown(controller)
		return

	var moves_before: int = _lm.moves_remaining
	var score_before: int = _lm.score
	controller._view.swap_requested.emit(pair[0], pair[1])
	await _frames(1)
	await _wait_idle(controller)
	await _seconds(0.2)

	_ok(_lm.moves_remaining == moves_before - 1, "a legal swap did not consume exactly one move")
	_ok(_lm.score > score_before, "a legal swap scored nothing")
	_ok(_count_empty_cells(controller.board) == 0, "board left with holes after a cascade")
	_ok(controller.board.find_matches().is_empty(), "board left with unresolved matches")
	var mismatch: String = _views_match_board(controller)
	_ok(mismatch == "", "view/board mismatch after cascade: " + mismatch)
	await _teardown(controller)

func _test_rejected_swap_costs_nothing() -> void:
	_begin("rejected_swap_costs_nothing")
	var controller: Node = await _make_controller()
	var pair: Array = _find_invalid_swap(controller.board)
	_ok(not pair.is_empty(), "no illegal swap available to test")
	if pair.is_empty():
		await _teardown(controller)
		return

	var moves_before: int = _lm.moves_remaining
	var color_a: int = controller.board.get_gem(pair[0].x, pair[0].y).color
	var color_b: int = controller.board.get_gem(pair[1].x, pair[1].y).color
	controller._view.swap_requested.emit(pair[0], pair[1])
	await _frames(1)
	await _wait_idle(controller)
	await _seconds(0.1)

	_ok(_lm.moves_remaining == moves_before, "an illegal swap consumed a move")
	_ok(controller.board.get_gem(pair[0].x, pair[0].y).color == color_a, "illegal swap was not reverted (a)")
	_ok(controller.board.get_gem(pair[1].x, pair[1].y).color == color_b, "illegal swap was not reverted (b)")
	var mismatch: String = _views_match_board(controller)
	_ok(mismatch == "", "view/board mismatch after rejected swap: " + mismatch)
	await _teardown(controller)

func _test_special_swap_detonates() -> void:
	_begin("special_swap_detonates")
	var controller: Node = await _make_controller()
	var board: Board = controller.board
	# Plant two specials side by side and swap them: this is the combo path,
	# which uses detonate_combo() and therefore needs gravity applied by hand.
	board._set_gem(3, 3, GemData.new(0, GemTypes.Special.STRIPED_H))
	board._set_gem(3, 4, GemData.new(1, GemTypes.Special.STRIPED_V))
	controller._view.refresh_all_from_board()
	await _frames(1)

	var score_before: int = _lm.score
	controller._view.swap_requested.emit(Vector2i(3, 3), Vector2i(3, 4))
	await _frames(1)
	await _wait_idle(controller)
	await _seconds(0.2)

	_ok(_lm.score > score_before, "a special-on-special combo scored nothing")
	_ok(_count_empty_cells(board) == 0, "detonate_combo left holes (gravity was not applied)")
	_ok(board.find_matches().is_empty(), "board left unresolved after a combo")
	var mismatch: String = _views_match_board(controller)
	_ok(mismatch == "", "view/board mismatch after combo: " + mismatch)
	await _teardown(controller)

func _test_hammer_booster() -> void:
	_begin("hammer_booster")
	var controller: Node = await _make_controller()
	_econ.boosters[B_HAMMER] = 2
	controller._hud.refresh_boosters(true)

	controller._on_booster_pressed(B_HAMMER)
	_ok(controller._hammer_armed, "hammer did not arm")

	var moves_before: int = _lm.moves_remaining
	var count_before: int = _econ.booster_count(B_HAMMER)
	controller._view.cell_tapped.emit(Vector2i(4, 4))
	await _frames(1)
	await _wait_idle(controller)
	await _seconds(0.2)

	_ok(_econ.booster_count(B_HAMMER) == count_before - 1, "hammer was not consumed")
	_ok(_lm.moves_remaining == moves_before, "hammer consumed a move (it is a booster, not a move)")
	_ok(not controller._hammer_armed, "hammer stayed armed after use")
	_ok(_count_empty_cells(controller.board) == 0, "hammer left a hole in the board")
	var mismatch: String = _views_match_board(controller)
	_ok(mismatch == "", "view/board mismatch after hammer: " + mismatch)
	await _teardown(controller)

func _test_color_bomb_start_booster() -> void:
	_begin("color_bomb_start_booster")
	var controller: Node = await _make_controller()
	_econ.boosters[B_BOMB_START] = 1
	var count_before: int = _econ.booster_count(B_BOMB_START)
	controller._on_booster_pressed(B_BOMB_START)
	await _frames(2)

	_ok(_econ.booster_count(B_BOMB_START) == count_before - 1, "bomb-start booster was not consumed")
	var bombs := 0
	for r in range(controller.board.rows):
		for c in range(controller.board.cols):
			var gem: GemData = controller.board.get_gem(r, c)
			if gem != null and gem.special == GemTypes.Special.COLOR_BOMB:
				bombs += 1
	_ok(bombs == 1, "expected exactly one colour bomb on the board, found %d" % bombs)
	var mismatch: String = _views_match_board(controller)
	_ok(mismatch == "", "view/board mismatch after bomb-start: " + mismatch)

	# Consuming it again mid-level must be refused.
	controller._moves_made = 3
	_econ.boosters[B_BOMB_START] = 1
	controller._on_booster_pressed(B_BOMB_START)
	await _frames(1)
	_ok(_econ.booster_count(B_BOMB_START) == 1, "bomb-start was usable after the first move")
	await _teardown(controller)

func _test_extra_moves_booster() -> void:
	_begin("extra_moves_booster")
	var controller: Node = await _make_controller()
	_econ.boosters[B_EXTRA_MOVES] = 1
	var moves_before: int = _lm.moves_remaining
	controller._on_booster_pressed(B_EXTRA_MOVES)
	await _frames(1)
	_ok(_lm.moves_remaining == moves_before + 5, "extra-moves booster did not grant 5 moves")
	_ok(_econ.booster_count(B_EXTRA_MOVES) == 0, "extra-moves booster was not consumed")

	# With none left the booster must be a no-op rather than granting moves.
	var moves_after: int = _lm.moves_remaining
	controller._on_booster_pressed(B_EXTRA_MOVES)
	await _frames(1)
	_ok(_lm.moves_remaining == moves_after, "extra-moves booster worked with a zero balance")
	await _teardown(controller)

func _test_blocker_accounting() -> void:
	_begin("blocker_accounting")
	var controller: Node = await _make_controller()
	var data := LevelData.new()
	data.level_number = 1
	data.rows = 8
	data.cols = 8
	data.gem_type_count = 6
	data.move_limit = 20
	data.objective = LevelData.Objective.CLEAR_BLOCKERS
	data.objective_target = 3
	data.blocker_cells = [Vector2i(2, 2), Vector2i(2, 3), Vector2i(5, 5)]
	controller.level = data
	controller._install_level(data)
	controller._setup_board()
	controller._view.setup(controller.board)
	controller._view.set_blockers(controller._active_blockers.keys())
	controller._hud.bind_level(data)
	await _frames(1)

	_ok(controller._active_blockers.size() == 3, "blockers were not registered")
	_ok(_lm.blockers_remaining == 3, "LevelManager blocker count wrong")

	# A step clearing two blocker cells plus an ordinary cell should retire
	# exactly the two blockers.
	controller._register_step_effects({
		"cleared": [Vector2i(2, 2), Vector2i(5, 5), Vector2i(7, 0)],
		"specials_created": [],
		"color_counts": {0: 3},
		"cascade_index": 0,
	})
	await _frames(1)
	_ok(controller._active_blockers.size() == 1, "active blocker set did not shrink to 1, got %d" % controller._active_blockers.size())
	_ok(_lm.blockers_remaining == 1, "LevelManager blockers_remaining wrong, got %d" % _lm.blockers_remaining)

	# Clearing the same cell again must not double-count.
	controller._register_step_effects({
		"cleared": [Vector2i(2, 2)],
		"specials_created": [],
		"color_counts": {0: 1},
		"cascade_index": 0,
	})
	await _frames(1)
	_ok(_lm.blockers_remaining == 1, "an already-broken blocker was counted twice")

	# Clearing the last one wins a CLEAR_BLOCKERS level.
	controller._register_step_effects({
		"cleared": [Vector2i(2, 3)],
		"specials_created": [],
		"color_counts": {0: 1},
		"cascade_index": 0,
	})
	await _frames(1)
	_ok(_lm.blockers_remaining == 0, "final blocker was not cleared")
	_ok(controller._ended, "clearing every blocker did not end the level")
	_ok(controller._end_kind == "win", "clearing every blocker did not win")
	await _teardown(controller)

func _test_shuffle_on_dead_board() -> void:
	_begin("shuffle_on_dead_board")
	var controller: Node = await _make_controller()
	var board: Board = controller.board
	# Diagonal stripes of three colours: every diagonal is a single colour, so
	# there is no match anywhere and no swap that could create one. This is
	# exactly the stuck state that must trigger a reshuffle.
	for r in range(board.rows):
		for c in range(board.cols):
			board._set_gem(r, c, GemData.new((r + c) % 3))
	var had_move_before: bool = board.has_any_valid_move()
	controller._view.refresh_all_from_board()
	await _frames(1)

	await controller._settle()
	await _seconds(0.3)
	_ok(not had_move_before, "test setup failed: the dead board still had a move")
	_ok(board.has_any_valid_move(), "shuffle did not restore a playable board")
	_ok(board.find_matches().is_empty(), "shuffle left a match on the board")
	var mismatch: String = _views_match_board(controller)
	_ok(mismatch == "", "view/board mismatch after shuffle: " + mismatch)
	await _teardown(controller)

func _test_out_of_moves_loses() -> void:
	_begin("out_of_moves_loses")
	var controller: Node = await _make_controller()
	# A last move that matches nothing never reaches apply_step_result(), so the
	# loss has to be detected when the move chain settles.
	_lm.moves_remaining = 0
	await controller._settle()
	await _frames(2)
	_ok(controller._ended, "running out of moves did not end the level")
	_ok(controller._end_kind == "lose", "running out of moves did not register as a loss")
	# scenes/LevelFail.tscn now exists (built with the rest of the meta UI), so a
	# loss hands off to the real screen and the in-scene ResultFallback panel is
	# only used when that scene is missing. Either ending counts as "reached a
	# result screen"; what must never happen is the level just stopping.
	var result_scene: Node = current_scene
	var reached_fail_screen: bool = result_scene != null and result_scene != controller \
		and result_scene.get_script() != null \
		and str((result_scene.get_script() as Script).resource_path).ends_with("LevelFail.gd")
	_ok(controller.get_node_or_null("ResultFallback") != null or reached_fail_screen,
		"loss did not reach a result screen")
	if reached_fail_screen:
		current_scene = null
		root.remove_child(result_scene)
		result_scene.queue_free()
	await _teardown(controller)

## Drag-to-swap and tap-tap-to-swap are the only way the game is played, and
## neither can be eyeballed here, so both gestures are driven synthetically
## against a standalone view.
func _test_input_gestures() -> void:
	_begin("input_gestures")
	var board := Board.new(8, 8, 6, 99)
	board.fill_initial()
	var view := BoardView.new()
	root.add_child(view)
	view.setup(board)
	view.set_input_enabled(true)
	var received: Array = []
	view.swap_requested.connect(func(a: Vector2i, b: Vector2i) -> void: received.append([a, b]))
	var tapped: Array = []
	view.cell_tapped.connect(func(cell: Vector2i) -> void: tapped.append(cell))
	await _frames(1)

	var a := Vector2i(3, 3)
	var b := Vector2i(3, 4)
	var far := Vector2i(6, 1)

	# Tap-tap on two adjacent cells.
	_click(view, view.cell_center(a))
	_ok(received.is_empty(), "a single tap should select, not swap")
	_click(view, view.cell_center(b))
	_ok(received.size() == 1, "tap-tap on adjacent cells did not request a swap")
	if received.size() == 1:
		_ok(received[0][0] == a and received[0][1] == b, "tap-tap swapped the wrong cells")

	# Tapping the same cell twice deselects instead of swapping.
	received.clear()
	_click(view, view.cell_center(a))
	_click(view, view.cell_center(a))
	_ok(received.is_empty(), "tapping one cell twice requested a swap")

	# Tapping a distant cell just moves the selection.
	received.clear()
	_click(view, view.cell_center(a))
	_click(view, view.cell_center(far))
	_ok(received.is_empty(), "tapping a non-adjacent cell requested a swap")
	view.clear_selection()

	# Drag from a cell into its neighbour.
	received.clear()
	_press(view, view.cell_center(a))
	_move(view, view.cell_center(a) + Vector2(view.cell_size * 0.8, 0.0))
	_release(view, view.cell_center(a) + Vector2(view.cell_size * 0.8, 0.0))
	_ok(received.size() == 1, "a drag did not request a swap")
	if received.size() == 1:
		_ok(received[0][0] == a and received[0][1] == b, "drag swapped the wrong cells, got %s" % str(received[0]))

	# A diagonal drag must still resolve to one definite neighbour.
	received.clear()
	_press(view, view.cell_center(a))
	_move(view, view.cell_center(a) + Vector2(view.cell_size * 0.9, view.cell_size * 0.4))
	_release(view, view.cell_center(a) + Vector2(view.cell_size * 0.9, view.cell_size * 0.4))
	_ok(received.size() == 1, "a diagonal drag produced %d swaps, expected 1" % received.size())

	# A drag shorter than the threshold is a tap, not a swap.
	received.clear()
	view.clear_selection()
	_press(view, view.cell_center(a))
	_move(view, view.cell_center(a) + Vector2(view.cell_size * 0.1, 0.0))
	_release(view, view.cell_center(a) + Vector2(view.cell_size * 0.1, 0.0))
	_ok(received.is_empty(), "a tiny drag was treated as a swap")

	# Taps outside the grid must be ignored.
	received.clear()
	view.clear_selection()
	_click(view, Vector2(10, 40))
	_click(view, view.cell_center(a))
	_ok(received.is_empty(), "a tap outside the board produced a swap")

	# Hammer mode turns taps into single-cell strikes and disables swapping.
	received.clear()
	view.set_hammer_mode(true)
	_click(view, view.cell_center(a))
	_ok(tapped.size() == 1 and tapped[0] == a, "hammer mode did not report the tapped cell")
	_ok(received.is_empty(), "hammer mode still requested a swap")
	view.set_hammer_mode(false)

	# Nothing at all should fire while input is disabled.
	received.clear()
	tapped.clear()
	view.set_input_enabled(false)
	_click(view, view.cell_center(a))
	_click(view, view.cell_center(b))
	_ok(received.is_empty() and tapped.is_empty(), "input fired while disabled")

	root.remove_child(view)
	view.queue_free()
	await _frames(2)

func _press(view: BoardView, pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = pos
	view._unhandled_input(event)

func _release(view: BoardView, pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = pos
	view._unhandled_input(event)

func _move(view: BoardView, pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	view._unhandled_input(event)

func _click(view: BoardView, pos: Vector2) -> void:
	_press(view, pos)
	_release(view, pos)

func _test_win_awards_economy() -> void:
	_begin("win_awards_economy")
	var controller: Node = await _make_controller()
	var level_id: String = "level_%03d" % controller.level.level_number
	_econ.stars_by_level.erase(level_id)
	_econ.highest_unlocked_level = 1
	var coins_before: int = _econ.coins

	_lm.score = controller.level.objective_target
	controller._register_step_effects({
		"cleared": [Vector2i(0, 0)],
		"specials_created": [],
		"color_counts": {0: 1},
		"cascade_index": 0,
	})
	await _frames(1)

	_ok(controller._ended, "hitting the score target did not end the level")
	_ok(controller._end_kind == "win", "hitting the score target did not win")
	# Ownership of the payout sits with LevelCompleteScreen._ready() — see the
	# contract block at the top of scripts/ui/LevelComplete.gd. Crediting in the
	# controller *as well* paid every win out twice, so what's asserted here is
	# the boundary: the controller reports a complete result and touches nothing
	# persistent; the result screen is what writes to Economy (covered by
	# scripts/tests/run_ui_smoke.gd -> _test_level_complete_credits).
	_ok(_econ.coins == coins_before, "controller must not credit coins (LevelCompleteScreen does)")
	_ok(_econ.stars_for(level_id) == 0, "controller must not record stars (LevelCompleteScreen does)")
	_ok(_econ.highest_unlocked_level == 1, "controller must not unlock levels (LevelCompleteScreen does)")
	for key in ["level_number", "stars", "score", "coins_earned"]:
		_ok(controller._end_payload.has(key),
			"end payload is missing '%s', required by LevelCompleteScreen.pending_result" % key)

	# LevelComplete.tscn is built elsewhere; until it exists the fallback panel
	# must take over rather than leaving the player stranded.
	controller._go_to_result_scene("res://scenes/__does_not_exist__.tscn", controller._end_payload)
	await _frames(1)
	_ok(controller.get_node_or_null("ResultFallback") != null, "missing result scene did not fall back to an in-scene panel")
	_ok(current_scene != controller, "fallback should not have swapped the current scene")
	await _teardown(controller)

## The fallback path: with no result scene to hand off to, nothing downstream
## exists to pay the win out, so the controller has to do it itself.
func _test_win_fallback_credits_itself() -> void:
	_begin("win_fallback_credits_itself")
	var controller: Node = await _make_controller()
	var level_id: String = "level_%03d" % controller.level.level_number
	_econ.stars_by_level.erase(level_id)
	_econ.highest_unlocked_level = 1
	var coins_before: int = _econ.coins

	_lm.score = controller.level.objective_target
	controller._register_step_effects({
		"cleared": [Vector2i(0, 0)],
		"specials_created": [],
		"color_counts": {0: 1},
		"cascade_index": 0,
	})
	await _frames(1)
	_ok(controller._end_kind == "win", "test setup failed: the level did not win")

	controller._go_to_result_scene("res://scenes/__does_not_exist__.tscn", controller._end_payload)
	await _frames(1)
	_ok(controller._economy_credited, "fallback path did not credit the win")
	_ok(_econ.coins == coins_before + int(controller._end_payload["coins_earned"]),
		"fallback path credited %d coins, expected %d" % [_econ.coins - coins_before, int(controller._end_payload["coins_earned"])])
	_ok(_econ.stars_for(level_id) > 0, "fallback path did not record stars")
	_ok(_econ.highest_unlocked_level == controller.level.level_number + 1, "fallback path did not unlock the next level")

	# A retried handoff must not pay out twice.
	var coins_after: int = _econ.coins
	controller._credit_economy_once()
	_ok(_econ.coins == coins_after, "crediting was not idempotent")
	await _teardown(controller)

## The shipping path: LevelCompleteScreen declares `pending_result` and credits
## the payload in its own _ready(), so the win must be paid out exactly once
## across the two of them — not zero times, not twice.
func _test_win_handoff_credits_exactly_once() -> void:
	_begin("win_handoff_credits_exactly_once")
	var controller: Node = await _make_controller()
	var level_id: String = "level_%03d" % controller.level.level_number
	_econ.stars_by_level.erase(level_id)
	_econ.highest_unlocked_level = 1
	var coins_before: int = _econ.coins

	_lm.score = controller.level.objective_target
	controller._register_step_effects({
		"cleared": [Vector2i(0, 0)],
		"specials_created": [],
		"color_counts": {0: 1},
		"cascade_index": 0,
	})
	await _frames(1)
	var earned: int = int(controller._end_payload["coins_earned"])

	controller._go_to_result_scene("res://scenes/LevelComplete.tscn", controller._end_payload)
	await _frames(3)

	_ok(not controller._economy_credited, "controller credited a win the result screen owns")
	_ok(_econ.coins == coins_before + earned,
		"win paid out %d coins, expected exactly %d" % [_econ.coins - coins_before, earned])
	_ok(_econ.stars_for(level_id) > 0, "handoff did not record stars")
	_ok(_econ.highest_unlocked_level == controller.level.level_number + 1, "handoff did not unlock the next level")
	var landed: Node = current_scene
	_ok(landed != null and landed != controller, "win did not hand off to the complete screen")
	if landed != null and landed != controller:
		root.remove_child(landed)
		landed.queue_free()
		current_scene = null
	await _teardown(controller)

## Drives the real shipped level set through the gameplay scene. This is what
## catches a level whose grid does not fit the viewport, whose blockers sit off
## the board, or whose COLLECT_COLOR target is a colour the HUD cannot draw.
func _test_every_shipped_level_boots() -> void:
	_begin("every_shipped_level_boots")
	var checked := 0
	for level_number in range(1, 25):
		if not ResourceLoader.exists("res://levels/level_%03d.tres" % level_number):
			continue
		checked += 1
		var controller: Node = await _make_controller(level_number)
		var data: LevelData = controller.level
		var board: Board = controller.board

		_ok(data.level_number == level_number, "level %d loaded level_number %d" % [level_number, data.level_number])
		_ok(board.rows == data.rows and board.cols == data.cols,
			"level %d board is %dx%d, level data says %dx%d" % [level_number, board.rows, board.cols, data.rows, data.cols])
		_ok(_count_empty_cells(board) == 0, "level %d filled with holes" % level_number)
		_ok(board.has_any_valid_move(), "level %d opened with no legal move" % level_number)

		var rect: Rect2 = controller._view.board_rect()
		_ok(rect.position.x >= 0.0 and rect.end.x <= 720.0, "level %d board is wider than the screen: %s" % [level_number, str(rect)])
		_ok(rect.position.y >= 260.0 and rect.end.y <= 1040.0, "level %d board collides with the HUD: %s" % [level_number, str(rect)])

		# Blockers must all land on real cells, or the objective is unwinnable.
		_ok(controller._active_blockers.size() == data.blocker_cells.size(),
			"level %d registered %d of %d blockers (some were out of bounds)" % [
				level_number, controller._active_blockers.size(), data.blocker_cells.size()])
		if data.objective == LevelData.Objective.CLEAR_BLOCKERS:
			_ok(not data.blocker_cells.is_empty(), "level %d is CLEAR_BLOCKERS with no blockers" % level_number)

		# The HUD draws the objective colour as a gem, so it has to be a real one.
		if data.objective == LevelData.Objective.COLLECT_COLOR:
			_ok(data.objective_color >= 0 and data.objective_color < data.gem_type_count,
				"level %d collects colour %d, outside its %d-colour palette" % [
					level_number, data.objective_color, data.gem_type_count])

		await _teardown(controller)
	_ok(checked >= 20, "only %d shipped levels were found to test" % checked)

func _test_static_var_handoff() -> void:
	_begin("static_var_handoff")
	# GameplayController writes the result onto the target scene script's static
	# `pending_result` before the scene enters the tree. Verify that mechanism
	# against a stand-in script, since the real scene is authored elsewhere.
	var stub := GDScript.new()
	stub.source_code = "extends Node\nstatic var pending_result: Dictionary = {}\n"
	var err := stub.reload()
	_ok(err == OK, "stub script failed to compile")
	stub.set("pending_result", {"stars": 3, "score": 4242})
	var stored: Dictionary = stub.get("pending_result")
	_ok(stored.get("score", 0) == 4242, "static var handoff did not stick")
	await _frames(1)
