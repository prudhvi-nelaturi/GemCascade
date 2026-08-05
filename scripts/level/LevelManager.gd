extends Node

## Autoload singleton. Tracks the currently active level's runtime state
## (moves remaining, score, objective progress). Owns no Board/visuals — the
## Gameplay scene owns the Board instance and calls apply_step_result() with
## each cascade step's event Dictionary (see Board.resolve_all()).

signal objective_progress_changed
signal level_won(stars: int, score: int, coins_earned: int)
signal level_lost

const LEVELS_DIR := "res://levels/"

var current_level: LevelData
var moves_remaining: int
var score: int
var collected_of_color: int
var blockers_remaining: int
var _finished: bool

func load_level(level_number: int) -> LevelData:
	var path := "%slevel_%03d.tres" % [LEVELS_DIR, level_number]
	if not ResourceLoader.exists(path):
		push_warning("LevelManager: no level resource at %s" % path)
		return null
	current_level = load(path)
	moves_remaining = current_level.move_limit
	score = 0
	collected_of_color = 0
	blockers_remaining = current_level.blocker_cells.size()
	_finished = false
	return current_level

## Call once per player move (a successful swap), before resolving cascades.
func consume_move() -> void:
	moves_remaining = maxi(0, moves_remaining - 1)

## Call once per cascade step returned by Board.resolve_all() / detonate_combo().
## `cleared_blocker_count` is however many of this step's cleared cells were
## blocker cells still active — GameplayController computes that by intersecting
## step["cleared"] with the still-active blocker set (LevelManager doesn't see
## the board directly, so it can't compute this itself).
func apply_step_result(step: Dictionary, cleared_blocker_count: int = 0) -> void:
	if _finished:
		return
	var cleared_count: int = step["cleared"].size()
	var cascade_index: int = step.get("cascade_index", 0)
	# Later cascade tiers score higher per gem — rewards chain reactions, a core
	# match-3 dopamine lever.
	var multiplier := 1.0 + cascade_index * 0.5
	score += int(cleared_count * 60 * multiplier)

	if current_level.objective == LevelData.Objective.COLLECT_COLOR:
		var color_counts: Dictionary = step.get("color_counts", {})
		collected_of_color += color_counts.get(current_level.objective_color, 0)

	blockers_remaining = maxi(0, blockers_remaining - cleared_blocker_count)

	objective_progress_changed.emit()
	_check_end_conditions()

func _check_end_conditions() -> void:
	if _finished:
		return
	if _objective_met():
		_finish_win()
	elif moves_remaining <= 0:
		_finish_lose()

func _objective_met() -> bool:
	match current_level.objective:
		LevelData.Objective.SCORE:
			return score >= current_level.objective_target
		LevelData.Objective.COLLECT_COLOR:
			return collected_of_color >= current_level.objective_target
		LevelData.Objective.CLEAR_BLOCKERS:
			return blockers_remaining <= 0
	return false

func objective_progress_fraction() -> float:
	match current_level.objective:
		LevelData.Objective.SCORE:
			return clampf(float(score) / maxf(1.0, current_level.objective_target), 0.0, 1.0)
		LevelData.Objective.COLLECT_COLOR:
			return clampf(float(collected_of_color) / maxf(1.0, current_level.objective_target), 0.0, 1.0)
		LevelData.Objective.CLEAR_BLOCKERS:
			var total: float = maxf(1.0, current_level.blocker_cells.size())
			return clampf(1.0 - (float(blockers_remaining) / total), 0.0, 1.0)
	return 0.0

## Deliberately does NOT touch the Economy autoload here — keeps LevelManager
## testable in isolation (no autoload dependency) and keeps "what happens on
## win" as the integration layer's job. Whoever connects to level_won (the
## Gameplay controller / LevelComplete screen) is responsible for calling
## Economy.record_level_result(...) and Economy.unlock_next_level(...).
func _finish_win() -> void:
	_finished = true
	var stars := current_level.stars_for_score(score)
	var coins_earned := 20 + stars * 15
	level_won.emit(stars, score, coins_earned)

func _finish_lose() -> void:
	_finished = true
	level_lost.emit()

## Grants extra moves from a booster — called by GameplayController when the
## player uses the "extra moves" booster mid-level.
func grant_extra_moves(amount: int) -> void:
	moves_remaining += amount
	_finished = false
