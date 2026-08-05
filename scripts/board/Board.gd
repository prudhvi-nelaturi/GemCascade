class_name Board
extends RefCounted

## Pure grid logic: no scene tree, no rendering, no input handling. Mirrors the
## "logic separate from rendering" split used in the other portfolio games
## (GlassRush's GameEngine.java). BoardView.gd (Node2D) drives this and turns
## the returned step events into tweened animations/particles.
##
## A "step" is one resolve iteration: find matches -> clear + create specials
## -> detonate any specials caught in the clear -> gravity + refill. resolve_all()
## loops steps until the board is stable, returning one event per step so the
## caller can animate/score each cascade tier separately (bigger combo = bigger juice).

var rows: int
var cols: int
var gem_type_count: int
var grid: Array # Array[Array[GemData]], grid[row][col], null = empty cell

var _rng := RandomNumberGenerator.new()

func _init(p_rows: int = 8, p_cols: int = 8, p_gem_type_count: int = 6, seed_value: int = -1) -> void:
	rows = p_rows
	cols = p_cols
	gem_type_count = clampi(p_gem_type_count, 3, GemTypes.COLOR_COUNT)
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_alloc_empty_grid()

func _alloc_empty_grid() -> void:
	grid = []
	for r in range(rows):
		var row_arr: Array = []
		row_arr.resize(cols)
		grid.append(row_arr)

func in_bounds(r: int, c: int) -> bool:
	return r >= 0 and r < rows and c >= 0 and c < cols

func get_gem(r: int, c: int) -> GemData:
	if not in_bounds(r, c):
		return null
	return grid[r][c]

func _set_gem(r: int, c: int, gem: GemData) -> void:
	grid[r][c] = gem

func _random_color() -> int:
	return _rng.randi_range(0, gem_type_count - 1)

## Fills the board with no pre-existing matches, retrying a bounded number of
## times so there's at least one legal move available at the start.
func fill_initial() -> void:
	var attempts := 0
	while attempts < 50:
		_fill_no_matches()
		if has_any_valid_move():
			return
		attempts += 1
	# Extremely unlikely fallback: accept whatever we have, a shuffle can be
	# triggered later by the caller if truly stuck.

func _fill_no_matches() -> void:
	for r in range(rows):
		for c in range(cols):
			var forbidden: Array = []
			# avoid completing a horizontal run of 3
			if c >= 2:
				var a: GemData = grid[r][c - 1]
				var b: GemData = grid[r][c - 2]
				if a != null and b != null and a.color == b.color:
					forbidden.append(a.color)
			# avoid completing a vertical run of 3
			if r >= 2:
				var a2: GemData = grid[r - 1][c]
				var b2: GemData = grid[r - 2][c]
				if a2 != null and b2 != null and a2.color == b2.color:
					forbidden.append(a2.color)
			var color := _random_color()
			var guard := 0
			while forbidden.has(color) and guard < 20:
				color = _random_color()
				guard += 1
			_set_gem(r, c, GemData.new(color))

## True if any adjacent swap on the board would create a match. Used to detect
## a stuck board (needs a reshuffle) both at fill time and after cascades.
func has_any_valid_move() -> bool:
	for r in range(rows):
		for c in range(cols):
			if c + 1 < cols and _would_swap_match(r, c, r, c + 1):
				return true
			if r + 1 < rows and _would_swap_match(r, c, r + 1, c):
				return true
	return false

func _would_swap_match(r1: int, c1: int, r2: int, c2: int) -> bool:
	_swap_cells(r1, c1, r2, c2)
	var matched := not find_matches().is_empty()
	_swap_cells(r1, c1, r2, c2) # swap back
	return matched

func _swap_cells(r1: int, c1: int, r2: int, c2: int) -> void:
	var tmp: GemData = grid[r1][c1]
	grid[r1][c1] = grid[r2][c2]
	grid[r2][c2] = tmp

## Re-scrambles the board in place (used when has_any_valid_move() is false).
func shuffle() -> void:
	var colors: Array = []
	for r in range(rows):
		for c in range(cols):
			var g: GemData = grid[r][c]
			if g != null:
				colors.append(g.color)
	var attempts := 0
	while attempts < 50:
		colors.shuffle()
		var i := 0
		for r in range(rows):
			for c in range(cols):
				_set_gem(r, c, GemData.new(colors[i]))
				i += 1
		if find_matches().is_empty() and has_any_valid_move():
			return
		attempts += 1

## Returns true and performs the swap if it is adjacent and creates a match (or
## involves a special gem, which always "matches" via detonation). Returns false
## and leaves the grid untouched otherwise (caller should shake-back visually).
func try_swap(r1: int, c1: int, r2: int, c2: int) -> bool:
	if not in_bounds(r1, c1) or not in_bounds(r2, c2):
		return false
	var adjacent := (absi(r1 - r2) + absi(c1 - c2)) == 1
	if not adjacent:
		return false

	var gem1: GemData = grid[r1][c1]
	var gem2: GemData = grid[r2][c2]
	if gem1 == null or gem2 == null:
		return false

	# Swapping two specials (or a color bomb with anything) always triggers —
	# this is the genre's favourite "combo the specials" dopamine moment.
	if gem1.is_special() or gem2.is_special():
		_swap_cells(r1, c1, r2, c2)
		return true

	_swap_cells(r1, c1, r2, c2)
	if find_matches().is_empty():
		_swap_cells(r1, c1, r2, c2) # revert
		return false
	return true

## One match = a maximal same-color run (horizontal or vertical, length >= 3).
## Returned as an Array of Dictionaries: {"color": int, "cells": Array[Vector2i], "orientation": "H"/"V"}
func find_matches() -> Array:
	var runs: Array = []

	for r in range(rows):
		var run_start := 0
		var c := 1
		while c <= cols:
			var same := c < cols and _same_color(r, c - 1, r, c)
			if not same:
				var length := c - run_start
				if length >= 3:
					var cells: Array = []
					for cc in range(run_start, c):
						cells.append(Vector2i(r, cc))
					runs.append({"color": grid[r][run_start].color, "cells": cells, "orientation": "H"})
				run_start = c
			c += 1

	for c in range(cols):
		var run_start := 0
		var r := 1
		while r <= rows:
			var same := r < rows and _same_color(r - 1, c, r, c)
			if not same:
				var length := r - run_start
				if length >= 3:
					var cells: Array = []
					for rr in range(run_start, r):
						cells.append(Vector2i(rr, c))
					runs.append({"color": grid[run_start][c].color, "cells": cells, "orientation": "V"})
				run_start = r
			r += 1

	return _merge_runs_into_groups(runs)

func _same_color(r1: int, c1: int, r2: int, c2: int) -> bool:
	var a: GemData = grid[r1][c1]
	var b: GemData = grid[r2][c2]
	return a != null and b != null and a.color == b.color

## Merges overlapping same-color runs into groups (an L/T shape is a horizontal
## run + vertical run sharing a cell) so special-gem shape detection sees the
## whole connected match, not two separate 3-runs.
func _merge_runs_into_groups(runs: Array) -> Array:
	var groups: Array = [] # each: {"color", "cell_set": Dictionary[Vector2i,true], "runs": Array}
	for run in runs:
		var merged_into: Array = []
		for g in groups:
			if g["color"] != run["color"]:
				continue
			for cell in run["cells"]:
				if g["cell_set"].has(cell):
					merged_into.append(g)
					break
		if merged_into.is_empty():
			var cell_set := {}
			for cell in run["cells"]:
				cell_set[cell] = true
			groups.append({"color": run["color"], "cell_set": cell_set, "runs": [run]})
		else:
			var target = merged_into[0]
			for cell in run["cells"]:
				target["cell_set"][cell] = true
			target["runs"].append(run)
			# fold any other groups this run also bridged into the target
			for other in merged_into.slice(1):
				if other == target:
					continue
				for cell in other["cell_set"]:
					target["cell_set"][cell] = true
				target["runs"].append_array(other["runs"])
				groups.erase(other)

	var result: Array = []
	for g in groups:
		result.append({
			"color": g["color"],
			"cells": g["cell_set"].keys(),
			"runs": g["runs"],
		})
	return result

## Runs the full resolve loop (matches -> specials -> detonations -> gravity ->
## refill, repeated until stable). Returns an Array of step Dictionaries:
##   {"cleared": Array[Vector2i], "specials_created": Array[{"pos","type"}],
##    "color_counts": Dictionary[int,int], "cascade_index": int}
func resolve_all() -> Array:
	var steps: Array = []
	var cascade_index := 0
	while true:
		var groups := find_matches()
		if groups.is_empty():
			break
		steps.append(_process_groups(groups, cascade_index))
		_apply_gravity_and_refill()
		cascade_index += 1
	return steps

func _process_groups(groups: Array, cascade_index: int) -> Dictionary:
	var to_clear := {} # Vector2i -> true
	var specials_created: Array = []
	var color_counts := {}

	for group in groups:
		var cells: Array = group["cells"]
		for cell in cells:
			to_clear[cell] = true
		var special_type := _classify_special(group)
		if special_type != GemTypes.Special.NONE:
			var pos: Vector2i = _pick_special_position(group)
			specials_created.append({"pos": pos, "type": special_type, "color": group["color"]})

	# Detonate any special gems whose cell got swept into this clear — chain
	# reaction. Iterate until no new specials get pulled in.
	var detonated := {}
	var frontier: Array = to_clear.keys()
	while not frontier.is_empty():
		var next_frontier: Array = []
		for cell in frontier:
			var gem: GemData = get_gem(cell.x, cell.y)
			if gem == null or not gem.is_special() or detonated.has(cell):
				continue
			detonated[cell] = true
			for extra in _detonation_cells(cell, gem.special):
				if not to_clear.has(extra):
					to_clear[extra] = true
					next_frontier.append(extra)
		frontier = next_frontier

	# Tally colors for objective tracking, then actually clear the cells —
	# except the ones we're about to turn into a newly created special.
	var special_positions := {}
	for s in specials_created:
		special_positions[s["pos"]] = s["type"]

	for cell in to_clear.keys():
		var gem: GemData = get_gem(cell.x, cell.y)
		if gem != null:
			color_counts[gem.color] = color_counts.get(gem.color, 0) + 1

	for cell in to_clear.keys():
		if special_positions.has(cell):
			var g: GemData = get_gem(cell.x, cell.y)
			var color: int = g.color if g != null else groups[0]["color"]
			_set_gem(cell.x, cell.y, GemData.new(color, special_positions[cell]))
		else:
			_set_gem(cell.x, cell.y, null)

	return {
		"cleared": to_clear.keys(),
		"specials_created": specials_created,
		"color_counts": color_counts,
		"cascade_index": cascade_index,
	}

func _classify_special(group: Dictionary) -> int:
	var cell_count: int = group["cells"].size()
	var runs: Array = group["runs"]
	if runs.size() == 1:
		if cell_count == 4:
			return GemTypes.Special.STRIPED_H if runs[0]["orientation"] == "H" else GemTypes.Special.STRIPED_V
		if cell_count >= 5:
			return GemTypes.Special.COLOR_BOMB
		return GemTypes.Special.NONE
	# Multiple intersecting runs (L/T shape) -> wrapped, for any size >= 5.
	if cell_count >= 5:
		return GemTypes.Special.WRAPPED
	return GemTypes.Special.NONE

func _pick_special_position(group: Dictionary) -> Vector2i:
	var runs: Array = group["runs"]
	if runs.size() > 1:
		# Intersection cell of the runs (appears in more than one run's cell list).
		var counts := {}
		for run in runs:
			for cell in run["cells"]:
				counts[cell] = counts.get(cell, 0) + 1
		for cell in counts:
			if counts[cell] > 1:
				return cell
	var cells: Array = group["cells"]
	return cells[cells.size() / 2]

## Cells a detonating special gem additionally clears, beyond its own cell.
func _detonation_cells(pos: Vector2i, special: int) -> Array:
	var result: Array = []
	match special:
		GemTypes.Special.STRIPED_H:
			for c in range(cols):
				result.append(Vector2i(pos.x, c))
		GemTypes.Special.STRIPED_V:
			for r in range(rows):
				result.append(Vector2i(r, pos.y))
		GemTypes.Special.WRAPPED:
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					var cell := Vector2i(pos.x + dr, pos.y + dc)
					if in_bounds(cell.x, cell.y):
						result.append(cell)
		GemTypes.Special.COLOR_BOMB:
			var gem: GemData = get_gem(pos.x, pos.y)
			var target_color := gem.color if gem != null else -1
			for r in range(rows):
				for c in range(cols):
					var g: GemData = grid[r][c]
					if g != null and g.color == target_color:
						result.append(Vector2i(r, c))
	return result

## Explicit combo when the player swaps two special gems together — resolve_all()
## alone won't detect this (no color match forms), so GameplayController calls
## this right after a successful try_swap() when both swapped cells were special.
func detonate_combo(r1: int, c1: int, r2: int, c2: int) -> Dictionary:
	var gem1: GemData = get_gem(r1, c1)
	var gem2: GemData = get_gem(r2, c2)
	var to_clear := {}
	if gem1 != null and gem1.color >= 0 and gem2 != null and gem2.special == GemTypes.Special.COLOR_BOMB and gem1.special == GemTypes.Special.COLOR_BOMB:
		# two color bombs: clear the entire board
		for r in range(rows):
			for c in range(cols):
				to_clear[Vector2i(r, c)] = true
	elif gem1 != null and gem2 != null and (gem1.special == GemTypes.Special.COLOR_BOMB or gem2.special == GemTypes.Special.COLOR_BOMB):
		# color bomb + anything: clear every gem matching the OTHER gem's color
		var bomb_pos := Vector2i(r1, c1) if gem1.special == GemTypes.Special.COLOR_BOMB else Vector2i(r2, c2)
		var other_gem: GemData = gem2 if bomb_pos == Vector2i(r1, c1) else gem1
		var target_color := other_gem.color
		for r in range(rows):
			for c in range(cols):
				var g: GemData = grid[r][c]
				if g != null and g.color == target_color:
					to_clear[Vector2i(r, c)] = true
		to_clear[bomb_pos] = true
	else:
		# striped/wrapped combos: union of both detonation areas, seeded at both cells
		to_clear[Vector2i(r1, c1)] = true
		to_clear[Vector2i(r2, c2)] = true
		if gem1 != null:
			for cell in _detonation_cells(Vector2i(r1, c1), gem1.special):
				to_clear[cell] = true
		if gem2 != null:
			for cell in _detonation_cells(Vector2i(r2, c2), gem2.special):
				to_clear[cell] = true
		# a striped+striped or striped+wrapped combo additionally sweeps a
		# cross/thick-band centered on both cells for extra impact
		if gem1 != null and gem2 != null and gem1.is_special() and gem2.is_special():
			for cell in _detonation_cells(Vector2i(r2, c2), gem1.special):
				to_clear[cell] = true
			for cell in _detonation_cells(Vector2i(r1, c1), gem2.special):
				to_clear[cell] = true

	var color_counts := {}
	for cell in to_clear.keys():
		var g: GemData = get_gem(cell.x, cell.y)
		if g != null:
			color_counts[g.color] = color_counts.get(g.color, 0) + 1
			_set_gem(cell.x, cell.y, null)

	return {"cleared": to_clear.keys(), "specials_created": [], "color_counts": color_counts, "cascade_index": 0}

func _apply_gravity_and_refill() -> void:
	for c in range(cols):
		var write_row := rows - 1
		for r in range(rows - 1, -1, -1):
			if grid[r][c] != null:
				if write_row != r:
					grid[write_row][c] = grid[r][c]
					grid[r][c] = null
				write_row -= 1
		for r in range(write_row, -1, -1):
			grid[r][c] = GemData.new(_random_color())
