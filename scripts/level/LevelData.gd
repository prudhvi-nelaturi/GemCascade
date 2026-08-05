class_name LevelData
extends Resource

## One level's design data — saved as levels/level_XXX.tres. This is the level
## design surface: content gets authored by editing these resource files, not
## by writing code, same "config is data, not logic" philosophy as the rest of
## the portfolio.

enum Objective { SCORE, COLLECT_COLOR, CLEAR_BLOCKERS }

@export var level_number: int = 1
@export var episode: String = "candy_forest" # candy_forest | crystal_caves | sunset_beach
@export var rows: int = 8
@export var cols: int = 8
@export var gem_type_count: int = 6
@export var move_limit: int = 20

@export var objective: Objective = Objective.SCORE
@export var objective_target: int = 5000
@export var objective_color: int = -1 # GemTypes.GemColor, only used for COLLECT_COLOR

## Cells with a blocker layer, used when objective == CLEAR_BLOCKERS. A blocker
## is cleared by an EXACT-CELL match — i.e. one of that step's cleared cells is
## the blocker's own cell (not merely adjacent). This matches
## LevelManager.apply_step_result()'s cleared_blocker_count contract precisely:
## GameplayController computes it as the intersection of step["cleared"] with
## the still-active blocker set. All authored levels are calibrated for this
## exact-cell rule — do not switch to an adjacency rule without rebalancing
## every CLEAR_BLOCKERS level's blocker_cells/move_limit (adjacency clears
## blockers ~5x faster and would make them trivially easy as authored).
@export var blocker_cells: Array[Vector2i] = []

## Score needed for 1/2/3 stars, ascending.
@export var star_thresholds: Array[int] = [1000, 3000, 6000]

func stars_for_score(score: int) -> int:
	var stars := 0
	for threshold in star_thresholds:
		if score >= threshold:
			stars += 1
	return stars
