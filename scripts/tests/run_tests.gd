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

	# --- board boundary / special-gem edge cases ---------------------------
	_run(test_try_swap_at_grid_corners)
	_run(test_striped_v_created_from_vertical_four)
	_run(test_striped_v_detonation_clears_column)
	_run(test_striped_h_detonation_on_top_row_stays_in_row)
	_run(test_wrapped_detonation_clipped_at_corner)
	_run(test_wrapped_detonation_clipped_at_edge)
	_run(test_detonation_cells_never_leave_the_grid)
	_run(test_wrapped_at_corner_resolves_in_bounds)
	_run(test_merge_runs_into_groups_t_shape)
	_run(test_t_shape_creates_wrapped_at_intersection)
	_run(test_match_of_exactly_three_creates_no_special)
	_run(test_shuffle_unsticks_a_deadlocked_board)
	_run(test_shuffle_preserves_colour_multiset)

	# --- level data / level manager ---------------------------------------
	_run(test_stars_for_score_exact_thresholds)
	_run(test_level_manager_clear_blockers_win)
	_run(test_level_manager_collect_color_accumulates)
	_run(test_level_manager_progress_fraction_clear_blockers)
	_run(test_grant_extra_moves_unfinishes_a_lost_level)

	# --- economy -----------------------------------------------------------
	_run(test_economy_buy_booster_rejects_insufficient_coins)
	_run(test_economy_consume_booster_rejects_empty_stock)
	_run(test_economy_record_level_result_never_downgrades_stars)
	_run(test_economy_save_load_round_trip)

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


# ---------------------------------------------------------------------------
# Board: boundary + special-gem edge cases
# ---------------------------------------------------------------------------

## Convenience: a step Dictionary shaped like the ones Board.resolve_all() emits.
func _step(cleared_count: int, color_counts: Dictionary = {}, cascade_index: int = 0) -> Dictionary:
	var cells: Array = []
	for i in range(cleared_count):
		cells.append(Vector2i(0, i))
	return {"cleared": cells, "specials_created": [], "color_counts": color_counts,
		"cascade_index": cascade_index}

func test_try_swap_at_grid_corners() -> void:
	# Top-left: swapping the corner gem itself must be accepted when it completes
	# a run. Corners are the only cells with two out-of-bounds neighbours, so the
	# adjacency maths gets exercised against the grid edge here.
	var top_left := _board_from_grid([
		[S, R, R],
		[R, T, A],
		[E, D, S],
	])
	_assert_true(top_left.try_swap(0, 0, 1, 0), "corner swap completing a row should be accepted")
	_assert_eq(top_left.get_gem(0, 0).color, R, "the corner cell should hold the moved gem")

	var bottom_right := _board_from_grid([
		[E, D, S],
		[A, T, R],
		[R, R, D],
	])
	_assert_true(bottom_right.try_swap(2, 2, 1, 2), "bottom-right corner swap completing a row should be accepted")
	_assert_eq(bottom_right.get_gem(2, 2).color, R, "the bottom-right cell should hold the moved gem")

	# A corner swap into thin air is still rejected rather than erroring.
	_assert_true(not top_left.try_swap(0, 0, -1, 0), "swapping a corner with an off-grid cell should be rejected")
	_assert_true(not top_left.try_swap(0, 0, 0, -1), "swapping a corner with an off-grid cell should be rejected")

func test_striped_v_created_from_vertical_four() -> void:
	var board := _board_from_grid([
		[R, S],
		[R, T],
		[R, A],
		[R, D],
	])
	var groups := board.find_matches()
	_assert_eq(groups.size(), 1, "a vertical run of 4 should be a single group")
	_assert_eq(groups[0]["cells"].size(), 4, "the group should hold 4 cells")
	_assert_eq(board._classify_special(groups[0]), GemTypes.Special.STRIPED_V,
		"a vertical match of exactly 4 should create a vertically striped gem")

func test_striped_v_detonation_clears_column() -> void:
	var board := Board.new(6, 4, 6, 31)
	board.fill_initial()
	var cells := board._detonation_cells(Vector2i(2, 1), GemTypes.Special.STRIPED_V)
	_assert_eq(cells.size(), 6, "a vertical striped detonation on a 6-row board should hit all 6 cells")
	var wrong_column := 0
	var rows_seen := {}
	for cell in cells:
		if cell.y != 1:
			wrong_column += 1
		rows_seen[cell.x] = true
	_assert_eq(wrong_column, 0, "every cell of a vertical detonation should sit in the gem's own column")
	_assert_eq(rows_seen.size(), 6, "a vertical detonation should touch each row exactly once")

func test_striped_h_detonation_on_top_row_stays_in_row() -> void:
	var board := Board.new(6, 4, 6, 32)
	board.fill_initial()
	var cells := board._detonation_cells(Vector2i(0, 2), GemTypes.Special.STRIPED_H)
	_assert_eq(cells.size(), 4, "a horizontal striped detonation on a 4-col board should hit all 4 cells")
	var wrong_row := 0
	for cell in cells:
		if cell.x != 0:
			wrong_row += 1
	_assert_eq(wrong_row, 0, "a striped detonation on row 0 should never reach above the grid")

func test_wrapped_detonation_clipped_at_corner() -> void:
	var board := Board.new(8, 8, 6, 33)
	board.fill_initial()
	var top_left := board._detonation_cells(Vector2i(0, 0), GemTypes.Special.WRAPPED)
	_assert_eq(top_left.size(), 4, "a wrapped gem in the top-left corner should only clear the 2x2 that exists")
	var bottom_right := board._detonation_cells(Vector2i(7, 7), GemTypes.Special.WRAPPED)
	_assert_eq(bottom_right.size(), 4, "a wrapped gem in the bottom-right corner should also clear only 4 cells")
	for cell in top_left + bottom_right:
		_assert_true(board.in_bounds(cell.x, cell.y),
			"corner wrapped detonation cell %s should be inside the grid" % str(cell))

func test_wrapped_detonation_clipped_at_edge() -> void:
	var board := Board.new(8, 8, 6, 34)
	board.fill_initial()
	_assert_eq(board._detonation_cells(Vector2i(0, 3), GemTypes.Special.WRAPPED).size(), 6,
		"a wrapped gem on the top edge should clear a clipped 2x3 = 6 cells")
	_assert_eq(board._detonation_cells(Vector2i(4, 7), GemTypes.Special.WRAPPED).size(), 6,
		"a wrapped gem on the right edge should clear a clipped 3x2 = 6 cells")

func test_detonation_cells_never_leave_the_grid() -> void:
	# Sweeps every border cell against every special type — the interior can't
	# clip, so testing it would only pad the count.
	var board := Board.new(5, 5, 6, 35)
	board.fill_initial()
	var specials := [GemTypes.Special.STRIPED_H, GemTypes.Special.STRIPED_V,
		GemTypes.Special.WRAPPED, GemTypes.Special.COLOR_BOMB]
	var checked := 0
	var escaped := 0
	for r in range(5):
		for c in range(5):
			if r > 0 and r < 4 and c > 0 and c < 4:
				continue
			for special in specials:
				for cell in board._detonation_cells(Vector2i(r, c), special):
					checked += 1
					if not board.in_bounds(cell.x, cell.y):
						escaped += 1
	_assert_true(checked > 0, "the border sweep should have produced cells to check")
	_assert_eq(escaped, 0, "no detonation from a border cell should fall outside the grid")

func test_wrapped_at_corner_resolves_in_bounds() -> void:
	# A wrapped gem parked in the corner gets swept up by the row-0 match, so its
	# 3x3 blast has to be clipped mid-resolve rather than at inspection time.
	var board := _board_from_grid([
		[R, R, R, S, T],
		[S, T, A, D, E],
		[E, D, S, T, A],
		[T, A, E, S, D],
		[D, S, T, A, E],
	])
	board._set_gem(0, 0, GemData.new(R, GemTypes.Special.WRAPPED))
	var steps := board.resolve_all()
	_assert_true(steps.size() >= 1, "the row-0 match should resolve in at least one step")
	var escaped := 0
	var cleared_first: int = steps[0]["cleared"].size()
	for step in steps:
		for cell in step["cleared"]:
			if not board.in_bounds(cell.x, cell.y):
				escaped += 1
	_assert_eq(escaped, 0, "a corner wrapped detonation should not report out-of-grid cells")
	_assert_true(cleared_first >= 4,
		"the corner wrapped blast should pull in its clipped neighbours, got %d cells" % cleared_first)
	for r in range(5):
		for c in range(5):
			_assert_true(board.get_gem(r, c) != null,
				"cell (%d,%d) should be refilled after a corner detonation" % [r, c])

func test_merge_runs_into_groups_t_shape() -> void:
	# T-shape: the vertical run meets the horizontal run at its MIDDLE cell,
	# unlike the L-shape case which meets at an endpoint.
	var board := _board_from_grid([
		[R, R, R],
		[S, R, T],
		[E, R, D],
	])
	var groups := board.find_matches()
	_assert_eq(groups.size(), 1, "a T-shape should merge its two runs into one group")
	_assert_eq(groups[0]["cells"].size(), 5, "a T-shape of two 3-runs shares one cell, so 5 unique cells")
	_assert_eq(groups[0]["runs"].size(), 2, "the merged group should remember both runs")

func test_t_shape_creates_wrapped_at_intersection() -> void:
	var board := _board_from_grid([
		[R, R, R],
		[S, R, T],
		[E, R, D],
	])
	var group: Dictionary = board.find_matches()[0]
	_assert_eq(board._classify_special(group), GemTypes.Special.WRAPPED,
		"a 5-cell T-shape should create a wrapped gem")
	_assert_eq(board._pick_special_position(group), Vector2i(0, 1),
		"the wrapped gem should spawn on the cell where the two runs cross")

func test_match_of_exactly_three_creates_no_special() -> void:
	var board := _board_from_grid([
		[R, R, R, S],
		[T, A, D, E],
		[E, D, S, T],
	])
	var groups := board.find_matches()
	_assert_eq(groups.size(), 1, "the board should hold exactly one match")
	_assert_eq(board._classify_special(groups[0]), GemTypes.Special.NONE,
		"a straight match of exactly 3 should not qualify for a special gem")
	var step := board._process_groups(groups, 0)
	_assert_true(step["specials_created"].is_empty(),
		"processing a plain 3-match should create no specials")
	_assert_eq(step["cleared"].size(), 3, "a plain 3-match should clear exactly its own 3 cells")

func test_shuffle_unsticks_a_deadlocked_board() -> void:
	# Found by brute force: no run of 3 exists and no adjacent swap can make one,
	# yet the colour multiset is rich enough that a re-deal can produce a legal
	# move (a board where every colour appears twice would be unfixable).
	var board := _board_from_grid([
		[E, D, T, A, E],
		[A, S, S, R, E],
		[D, A, D, R, R],
		[R, S, E, E, S],
		[T, T, D, E, D],
	])
	_assert_true(board.find_matches().is_empty(), "the fixture board should start with no matches")
	_assert_true(not board.has_any_valid_move(), "the fixture board should genuinely be deadlocked")

	board.shuffle()
	_assert_true(board.find_matches().is_empty(),
		"shuffling should not leave the board with a pre-existing match")
	_assert_true(board.has_any_valid_move(),
		"shuffling a deadlocked board should leave at least one legal move")
	for r in range(5):
		for c in range(5):
			_assert_true(board.get_gem(r, c) != null, "shuffle should leave cell (%d,%d) filled" % [r, c])

func test_shuffle_preserves_colour_multiset() -> void:
	var board := Board.new(6, 6, 5, 36)
	board.fill_initial()
	var before := {}
	for r in range(6):
		for c in range(6):
			var col: int = board.get_gem(r, c).color
			before[col] = before.get(col, 0) + 1
	board.shuffle()
	var after := {}
	for r in range(6):
		for c in range(6):
			var col: int = board.get_gem(r, c).color
			after[col] = after.get(col, 0) + 1
	_assert_eq(after.size(), before.size(), "shuffle should not introduce or drop a colour")
	for col in before:
		_assert_eq(after.get(col, 0), before[col],
			"shuffle should rearrange the same gems, colour %d count changed" % col)


# ---------------------------------------------------------------------------
# LevelData / LevelManager
# ---------------------------------------------------------------------------

func test_stars_for_score_exact_thresholds() -> void:
	# The interesting case is landing EXACTLY on a threshold: `>=` vs `>` here is
	# the difference between a player seeing 2 stars and 3 for the same score.
	var level := LevelData.new()
	level.star_thresholds = [1000, 3000, 6000]
	_assert_eq(level.stars_for_score(999), 0, "one point below the first threshold should be 0 stars")
	_assert_eq(level.stars_for_score(1000), 1, "exactly the first threshold should award the star")
	_assert_eq(level.stars_for_score(2999), 1, "one point below the second threshold should stay at 1")
	_assert_eq(level.stars_for_score(3000), 2, "exactly the second threshold should award 2 stars")
	_assert_eq(level.stars_for_score(5999), 2, "one point below the third threshold should stay at 2")
	_assert_eq(level.stars_for_score(6000), 3, "exactly the third threshold should award all 3 stars")
	_assert_eq(level.stars_for_score(0), 0, "a score of zero should award nothing")

func test_level_manager_clear_blockers_win() -> void:
	var level := LevelData.new()
	level.level_number = 997
	level.objective = LevelData.Objective.CLEAR_BLOCKERS
	level.objective_target = 0
	level.move_limit = 10
	level.star_thresholds = [100, 200, 300]
	var blockers: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 1)]
	level.blocker_cells = blockers

	var lm = _fresh_level_manager()
	lm.current_level = level
	lm.moves_remaining = level.move_limit
	lm.score = 0
	lm.collected_of_color = 0
	lm.blockers_remaining = blockers.size()
	lm._finished = false

	var received := []
	lm.level_won.connect(func(stars, score, coins): received.append([stars, score, coins]))

	lm.apply_step_result(_step(3), 1)
	_assert_eq(lm.blockers_remaining, 1, "clearing one blocker should leave one behind")
	_assert_true(received.is_empty(), "the level should not be won while a blocker remains")

	lm.apply_step_result(_step(3), 1)
	_assert_eq(lm.blockers_remaining, 0, "clearing the last blocker should leave none")
	_assert_true(not received.is_empty(), "clearing the last blocker should win the level")
	_assert_true(lm._finished, "winning should mark the level finished")

func test_level_manager_collect_color_accumulates() -> void:
	var level := LevelData.new()
	level.level_number = 996
	level.objective = LevelData.Objective.COLLECT_COLOR
	level.objective_color = R
	level.objective_target = 10
	level.move_limit = 20
	level.star_thresholds = [100, 200, 300]

	var lm = _fresh_level_manager()
	lm.current_level = level
	lm.moves_remaining = level.move_limit
	lm.score = 0
	lm.collected_of_color = 0
	lm.blockers_remaining = 0
	lm._finished = false

	var received := []
	lm.level_won.connect(func(stars, score, coins): received.append([stars, score, coins]))

	# Only the objective colour counts; the other colours in the same step must
	# not leak into the tally.
	lm.apply_step_result(_step(7, {R: 4, S: 3}))
	_assert_eq(lm.collected_of_color, 4, "the first step should bank only its ruby count")
	_assert_true(received.is_empty(), "4 of 10 collected should not win yet")

	lm.apply_step_result(_step(7, {R: 5, E: 2}, 1))
	_assert_eq(lm.collected_of_color, 9, "collected colours should accumulate across steps")
	_assert_true(received.is_empty(), "9 of 10 collected should still not win")

	lm.apply_step_result(_step(3, {S: 2, E: 1}))
	_assert_eq(lm.collected_of_color, 9, "a step with none of the objective colour should not move the tally")

	lm.apply_step_result(_step(3, {R: 1}))
	_assert_eq(lm.collected_of_color, 10, "reaching the target should be recorded exactly")
	_assert_true(not received.is_empty(), "hitting the collect-colour target should win the level")

func test_level_manager_progress_fraction_clear_blockers() -> void:
	var level := LevelData.new()
	level.objective = LevelData.Objective.CLEAR_BLOCKERS
	level.move_limit = 10
	var blockers: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)]
	level.blocker_cells = blockers

	var lm = _fresh_level_manager()
	lm.current_level = level
	lm.blockers_remaining = 4
	_assert_true(is_equal_approx(lm.objective_progress_fraction(), 0.0),
		"no blockers cleared should read as 0%% progress")
	lm.blockers_remaining = 1
	_assert_true(is_equal_approx(lm.objective_progress_fraction(), 0.75),
		"3 of 4 blockers cleared should read as 75%% progress")
	lm.blockers_remaining = 0
	_assert_true(is_equal_approx(lm.objective_progress_fraction(), 1.0),
		"all blockers cleared should read as 100%% progress")

func test_grant_extra_moves_unfinishes_a_lost_level() -> void:
	# The "extra moves" booster is offered AFTER the loss screen appears, so it
	# has to reopen a level that already emitted level_lost.
	var level := LevelData.new()
	level.level_number = 995
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

	var lost := []
	lm.level_lost.connect(func(): lost.append(true))

	lm.consume_move()
	lm.apply_step_result(_step(3))
	_assert_true(not lost.is_empty(), "running out of moves should lose the level first")
	_assert_true(lm._finished, "a lost level should be marked finished")
	var score_at_loss: int = lm.score

	lm.grant_extra_moves(5)
	_assert_eq(lm.moves_remaining, 5, "granting 5 moves to an exhausted level should leave 5")
	_assert_true(not lm._finished, "granting extra moves should un-finish the level")

	# ...and the level has to actually keep playing: apply_step_result() bails
	# early while _finished is set, so scoring resuming is the real proof.
	lm.apply_step_result(_step(3))
	_assert_true(lm.score > score_at_loss, "play should resume and score again after extra moves")
	_assert_true(not lm._finished, "the reopened level should not immediately re-lose with moves left")


# ---------------------------------------------------------------------------
# Economy
#
# Economy.gd extends Node but touches nothing scene-tree-specific outside
# _ready() (which only calls load_game(), and never runs for a bare .new()), so
# it can be exercised standalone exactly like LevelManager. The tests that hit
# save_game() back up and restore the real user://save.cfg so running the suite
# can't clobber a player's progress.
# ---------------------------------------------------------------------------

const _SAVE_PATH := "user://save.cfg"

func _fresh_economy():
	return load("res://scripts/economy/Economy.gd").new()

func _backup_user_save() -> PackedByteArray:
	if FileAccess.file_exists(_SAVE_PATH):
		return FileAccess.get_file_as_bytes(_SAVE_PATH)
	return PackedByteArray()

func _restore_user_save(data: PackedByteArray) -> void:
	if data.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_SAVE_PATH))
	else:
		var f := FileAccess.open(_SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(data)
		f.close()

func test_economy_buy_booster_rejects_insufficient_coins() -> void:
	var eco = _fresh_economy()
	eco.coins = 10
	eco.boosters = {}
	_assert_true(not eco.can_afford_booster(eco.BOOSTER_HAMMER), "10 coins should not afford a 75-coin hammer")
	_assert_true(not eco.buy_booster(eco.BOOSTER_HAMMER), "buying a booster you can't afford should fail")
	_assert_eq(eco.coins, 10, "a failed purchase must not deduct coins")
	_assert_eq(eco.booster_count(eco.BOOSTER_HAMMER), 0, "a failed purchase must not grant the booster")
	# An unknown id is treated as unaffordable rather than crashing or going free.
	_assert_true(not eco.buy_booster("not_a_real_booster"), "an unknown booster id should not be purchasable")
	_assert_eq(eco.coins, 10, "an unknown booster id must not deduct coins")
	eco.free()

func test_economy_consume_booster_rejects_empty_stock() -> void:
	var backup := _backup_user_save()
	var eco = _fresh_economy()
	eco.boosters = {}
	_assert_true(not eco.consume_booster(eco.BOOSTER_EXTRA_MOVES), "consuming with none in stock should fail")
	eco.boosters[eco.BOOSTER_EXTRA_MOVES] = 1
	_assert_true(eco.consume_booster(eco.BOOSTER_EXTRA_MOVES), "consuming the last booster should succeed")
	_assert_eq(eco.booster_count(eco.BOOSTER_EXTRA_MOVES), 0, "consuming should decrement the count to zero")
	_assert_true(not eco.consume_booster(eco.BOOSTER_EXTRA_MOVES), "consuming again at zero should fail")
	_assert_eq(eco.booster_count(eco.BOOSTER_EXTRA_MOVES), 0, "a failed consume must not push the count negative")
	eco.free()
	_restore_user_save(backup)

func test_economy_record_level_result_never_downgrades_stars() -> void:
	var backup := _backup_user_save()
	var eco = _fresh_economy()
	eco.coins = 0
	eco.stars_by_level = {}

	eco.record_level_result("level_001", 3, 50)
	_assert_eq(eco.stars_for("level_001"), 3, "a first clear should record its stars")
	_assert_eq(eco.coins, 50, "a clear should pay out its coins")

	eco.record_level_result("level_001", 1, 20)
	_assert_eq(eco.stars_for("level_001"), 3, "replaying a level worse must not downgrade the stored stars")
	_assert_eq(eco.coins, 70, "a worse replay should still pay its coins")

	eco.record_level_result("level_002", 1, 10)
	eco.record_level_result("level_002", 2, 10)
	_assert_eq(eco.stars_for("level_002"), 2, "a better replay should upgrade the stored stars")
	_assert_eq(eco.total_stars(), 5, "total stars should sum the best result per level")
	_assert_eq(eco.stars_for("level_999"), 0, "an unplayed level should report zero stars")
	eco.free()
	_restore_user_save(backup)

func test_economy_save_load_round_trip() -> void:
	var backup := _backup_user_save()
	var writer = _fresh_economy()
	writer.coins = 777
	writer.crystals = 12
	writer.boosters = {writer.BOOSTER_HAMMER: 3}
	writer.stars_by_level = {"level_002": 2}
	writer.highest_unlocked_level = 5
	writer.save_game()

	var reader = _fresh_economy()
	reader.load_game()
	_assert_eq(reader.coins, 777, "coins should survive a save/load round trip")
	_assert_eq(reader.crystals, 12, "crystals should survive a save/load round trip")
	_assert_eq(reader.booster_count(reader.BOOSTER_HAMMER), 3, "booster counts should survive a round trip")
	_assert_eq(reader.stars_for("level_002"), 2, "per-level stars should survive a round trip")
	_assert_eq(reader.highest_unlocked_level, 5, "unlock progress should survive a round trip")
	_assert_true(reader.is_level_unlocked(5), "the highest unlocked level should read as unlocked")
	_assert_true(not reader.is_level_unlocked(6), "the level beyond the highest should stay locked")

	# unlock_next_level only ever moves forward.
	reader.unlock_next_level(3)
	_assert_eq(reader.highest_unlocked_level, 5, "unlocking a lower level must not roll progress back")
	reader.unlock_next_level(6)
	_assert_eq(reader.highest_unlocked_level, 6, "unlocking the next level should advance progress")

	writer.free()
	reader.free()
	_restore_user_save(backup)
