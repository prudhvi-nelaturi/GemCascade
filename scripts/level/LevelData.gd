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
## is cleared when a match happens on/adjacent to its cell (handled in
## GameplayController, since it needs Board's per-step "cleared" cells).
@export var blocker_cells: Array[Vector2i] = []

## Score needed for 1/2/3 stars, ascending.
@export var star_thresholds: Array[int] = [1000, 3000, 6000]

func stars_for_score(score: int) -> int:
	var stars := 0
	for threshold in star_thresholds:
		if score >= threshold:
			stars += 1
	return stars
