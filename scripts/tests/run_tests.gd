extends SceneTree

## Headless test runner for pure-logic scripts (Board.gd, LevelData.gd). No
## external test framework — same reasoning as GlassRush's plain-JUnit choice,
## just without even JUnit since this isn't a JVM: a hand-rolled assert runner
## is simplest for a project this size. Run with:
##   godot --headless --script res://scripts/tests/run_tests.gd

var _pass := 0
var _fail := 0
var _current_test := ""

func _initialize() -> void:
	print("=== GemCascade test suite ===")
	_run(test_fill_initial_has_no_matches)
	_run(test_fill_initial_fills_every_cell)
	_run(test_try_swap_rejects_non_adjacent)
	_run(test_try_swap_rejects_no_match)
	_run(test_try_swap_accepts_valid_match)
	_run(test_find_matches_horizontal_run)
	_run(test_find_matches_vertical_run)
	_run(test_find_matches_ignores_short_runs)
	_run(test_resolve_all_clears_and_refills)
	_run(test_resolve_all_cascades_multiple_steps)
	_run(test_special_striped_from_match_four)
	_run(test_special_color_bomb_from_match_five_line)
	_run(test_special_wrapped_from_l_shape)
	_run(test_striped_detonation_clears_row)
	_run(test_wrapped_detonation_clears_3x3)
	_run(test_color_bomb_detonation_clears_color)
	_run(test_combo_two_color_bombs_clears_board)
	_run(test_no_empty_cells_after_resolve)
	_run(test_level_data_stars_for_score)
	_run(test_level_manager_score_objective_win)
	_run(test_level_manager_moves_exhausted_lose)

	print("\n=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _run(test_fn: Callable) -> void:
	_current_test = test_fn.get_method()
	var ok := true
	var err := ""
	# GDScript has no try/catch; assert_true below records failures directly
	# instead of throwing, so a failing assertion doesn't abort the whole run.
	test_fn.call()

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("FAIL [%s] %s" % [_current_test, message])

func _assert_eq(actual, expected, message: String) -> void:
	_assert_true(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Builds a board from a literal grid of color ints (row-major), bypassing
## fill_initial()'s no-match guarantee so tests can set up exact scenarios.
func _board_from_grid(rows: Array) -> Board:
	var r_count: int = rows.size()
	var c_count: int = rows[0].size()
	var board := Board.new(r_count, c_count, 6, 12345)
	for r in range(r_count):
		for c in range(c_count):
			board._set_gem(r, c, GemData.new(rows[r][c]))
	return board

const R := GemTypes.GemColor.RUBY
const S := GemTypes.GemColor.SAPPHIRE
const E := GemTypes.GemColor.EMERALD
const T := GemTypes.GemColor.TOPAZ
const A := GemTypes.GemColor.AMETHYST
const D := GemTypes.GemColor.DIAMOND


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_fill_initial_has_no_matches() -> void:
	var board := Board.new(8, 8, 6, 1)
	board.fill_initial()
	_assert_true(board.find_matches().is_empty(), "freshly filled board should have no matches")

func test_fill_initial_fills_every_cell() -> void:
	var board := Board.new(8, 8, 6, 2)
	board.fill_initial()
	for r in range(8):
		for c in range(8):
			_assert_true(board.get_gem(r, c) != null, "cell (%d,%d) should be filled" % [r, c])

func test_try_swap_rejects_non_adjacent() -> void:
	var board := _board_from_grid([
		[R, S, E],
		[T, A, D],
		[R, S, E],
	])
	var result := board.try_swap(0, 0, 2, 2)
	_assert_true(not result, "non-adjacent swap should be rejected")

func test_try_swap_rejects_no_match() -> void:
	var board := _board_from_grid([
		[R, S, E],
		[T, A, D],
		[R, S, E],
	])
	var result := board.try_swap(0, 0, 0, 1)
	_assert_true(not result, "swap that forms no match should be rejected and reverted")
	_assert_eq(board.get_gem(0, 0).color, R, "grid should be reverted after rejected swap")

func test_try_swap_accepts_valid_match() -> void:
	var board := _board_from_grid([
		[R, R, S],
		[S, T, T],
		[E, A, D],
	])
	# swap (0,2)S with (1,2)T -> row0 becomes R,R,T (no match); try a real one:
	var board2 := _board_from_grid([
		[R, R, S],
		[S, T, R],
		[E, A, D],
	])
	var result := board2.try_swap(1, 2, 0, 2) # brings R into row 0 -> R,R,R
	_assert_true(result, "swap that completes a match should be accepted")
	_assert_eq(board2.get_gem(0, 2).color, R, "swapped cell should now hold the moved gem")

func test_find_matches_horizontal_run() -> void:
	var board := _board_from_grid([
		[R, R, R, S],
		[T, A, D, E],
	])
	var matches := board.find_matches()
	_assert_eq(matches.size(), 1, "one horizontal run of 3 should be one match group")
	_assert_eq(matches[0]["cells"].size(), 3, "match group should contain 3 cells")

func test_find_matches_vertical_run() -> void:
	var board := _board_from_grid([
		[R, T],
		[R, A],
		[R, D],
	])
	var matches := board.find_matches()
	_assert_eq(matches.size(), 1, "one vertical run of 3 should be one match group")

func test_find_matches_ignores_short_runs() -> void:
	var board := _board_from_grid([
		[R, R, S],
		[T, A, D],
	])
	_assert_true(board.find_matches().is_empty(), "a run of 2 should not count as a match")

func test_resolve_all_clears_and_refills() -> void:
	var board := _board_from_grid([
		[R, R, R],
		[S, T, A],
		[E, D, S],
	])
	var steps := board.resolve_all()
	_assert_true(steps.size() >= 1, "resolving a board with a match should produce at least one step")
	for c in range(3):
		_assert_true(board.get_gem(0, c) != null, "top row should be refilled after resolve")

func test_resolve_all_cascades_multiple_steps() -> void:
	# Column 0: rows 2-4 (R,R,R) match and clear first. Gravity then drops the
	# two D's from rows 0-1 down to meet the untouched D at row 5, forming a
	# SECOND match entirely from pre-placed (non-random-refill) gems — this is
	# deterministic regardless of what the RNG refills rows 0-2 with afterward.
	# Columns 1/2 use non-repeating colors so they never match and can't
	# interfere.
	var board := _board_from_grid([
		[D, S, E],
		[D, T, A],
		[R, S, E],
		[R, T, A],
		[R, S, E],
		[D, T, A],
	])
	var steps := board.resolve_all()
	_assert_true(steps.size() >= 2, "a board with a follow-up cascade should resolve in 2+ steps, got %d" % steps.size())

func test_special_striped_from_match_four() -> void:
	var board := _board_from_grid([
		[R, R, R, R, S],
		[T, A, D, E, S],
	])
	var steps := board.resolve_all()
	var found_striped := false
	for step in steps:
		for special in step["specials_created"]:
			if special["type"] == GemTypes.Special.STRIPED_H:
				found_striped = true
	_assert_true(found_striped, "a match of exactly 4 in a row should create a striped gem")

func test_special_color_bomb_from_match_five_line() -> void:
	var board := _board_from_grid([
		[R, R, R, R, R],
		[T, A, D, E, S],
	])
	var steps := board.resolve_all()
	var found_bomb := false
	for step in steps:
		for special in step["specials_created"]:
			if special["type"] == GemTypes.Special.COLOR_BOMB:
				found_bomb = true
	_assert_true(found_bomb, "a straight match of 5 should create a color bomb")

func test_special_wrapped_from_l_shape() -> void:
	# horizontal 3 at row0 cols0-2, vertical 3 at col0 rows0-2, sharing (0,0) -> 5 unique cells, L-shape
	var board := _board_from_grid([
		[R, R, R],
		[R, S, T],
		[R, A, D],
	])
	var steps := board.resolve_all()
	var found_wrapped := false
	for step in steps:
		for special in step["specials_created"]:
			if special["type"] == GemTypes.Special.WRAPPED:
				found_wrapped = true
	_assert_true(found_wrapped, "an L-shaped 5-cell match should create a wrapped gem")

func test_striped_detonation_clears_row() -> void:
	var board := Board.new(4, 4, 6, 5)
	board.fill_initial()
	board._set_gem(1, 1, GemData.new(R, GemTypes.Special.STRIPED_H))
	var cells := board._detonation_cells(Vector2i(1, 1), GemTypes.Special.STRIPED_H)
	_assert_eq(cells.size(), 4, "horizontal striped detonation on a 4-col board should hit all 4 cells")

func test_wrapped_detonation_clears_3x3() -> void:
	var board := Board.new(8, 8, 6, 6)
	board.fill_initial()
	var cells := board._detonation_cells(Vector2i(4, 4), GemTypes.Special.WRAPPED)
	_assert_eq(cells.size(), 9, "wrapped detonation away from edges should hit a full 3x3 = 9 cells")

func test_color_bomb_detonation_clears_color() -> void:
	var board := _board_from_grid([
		[R, S, R],
		[S, R, S],
		[R, S, R],
	])
	var cells := board._detonation_cells(Vector2i(1, 1), GemTypes.Special.COLOR_BOMB)
	_assert_eq(cells.size(), 5, "color bomb should clear every gem matching its own color (5 R's here)")

func test_combo_two_color_bombs_clears_board() -> void:
	var board := Board.new(5, 5, 6, 7)
	board.fill_initial()
	board._set_gem(2, 2, GemData.new(R, GemTypes.Special.COLOR_BOMB))
	board._set_gem(2, 3, GemData.new(S, GemTypes.Special.COLOR_BOMB))
	var result := board.detonate_combo(2, 2, 2, 3)
	_assert_eq(result["cleared"].size(), 25, "combining two color bombs should clear the entire 5x5 board")

func test_no_empty_cells_after_resolve() -> void:
	var board := Board.new(8, 8, 4, 9) # fewer colors -> more matches, stresses cascades
	board.fill_initial()
	# force some matches by scrambling without the no-match guarantee
	for i in range(10):
		board._set_gem(i % 8, (i * 3) % 8, GemData.new(R))
	board.resolve_all()
	for r in range(8):
		for c in range(8):
			_assert_true(board.get_gem(r, c) != null, "no cell should be empty after resolve_all (%d,%d)" % [r, c])

func test_level_data_stars_for_score() -> void:
	var level := LevelData.new()
	level.star_thresholds = [1000, 3000, 6000]
	_assert_eq(level.stars_for_score(500), 0, "below first threshold should be 0 stars")
	_assert_eq(level.stars_for_score(1500), 1, "above first threshold should be 1 star")
	_assert_eq(level.stars_for_score(3500), 2, "above second threshold should be 2 stars")
	_assert_eq(level.stars_for_score(7000), 3, "above third threshold should be 3 stars")

## Instantiated directly (not via the autoload global) so this test has no
## dependency on the project's autoload bootstrap — LevelManager.gd is written
## to be usable as a plain object, only relying on Node for signals.
func _fresh_level_manager():
	var script := load("res://scripts/level/LevelManager.gd")
	return script.new()

func test_level_manager_score_objective_win() -> void:
	var level := LevelData.new()
	level.level_number = 999
	level.objective = LevelData.Objective.SCORE
	level.objective_target = 100
	level.move_limit = 10
	level.star_thresholds = [50, 100, 150]

	var lm = _fresh_level_manager()
	lm.current_level = level
	lm.moves_remaining = level.move_limit
	lm.score = 0
	lm.collected_of_color = 0
	lm.blockers_remaining = 0
	lm._finished = false

	# Using an Array as the "was the signal received" flag rather than a plain
	# bool: GDScript lambdas capture local variables in a way that makes
	# reassigning a captured bool inside the closure NOT visible to the
	# enclosing scope, but mutating a shared reference type (Array) works
	# reliably either way.
	var received := []
	var win_handler := func(stars, score, coins): received.append([stars, score, coins])
	lm.level_won.connect(win_handler)
	lm.apply_step_result({"cleared": [Vector2i(0,0), Vector2i(0,1), Vector2i(0,2)], "specials_created": [], "color_counts": {}, "cascade_index": 0})
	_assert_true(not received.is_empty(), "reaching the score objective should emit level_won")

func test_level_manager_moves_exhausted_lose() -> void:
	var level := LevelData.new()
	level.level_number = 998
	level.objective = LevelData.Objective.SCORE
	level.objective_target = 999999
	level.move_limit = 1
	level.star_thresholds = [1, 2, 3]

	var lm = _fresh_level_manager()
	lm.current_level = level
	lm.moves_remaining = level.move_limit
	lm.score = 0
	lm.collected_of_color = 0
	lm.blockers_remaining = 0
	lm._finished = false

	var received := []
	var lose_handler := func(): received.append(true)
	lm.level_lost.connect(lose_handler)
	lm.consume_move()
	lm.apply_step_result({"cleared": [Vector2i(0,0)], "specials_created": [], "color_counts": {}, "cascade_index": 0})
	_assert_true(not received.is_empty(), "running out of moves without meeting the objective should emit level_lost")
