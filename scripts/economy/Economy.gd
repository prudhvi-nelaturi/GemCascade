extends Node

## Autoload singleton (see project.godot [autoload]). Soft currency (Coins,
## earned per level) and hard currency (Crystals, reserved for future IAP —
## none purchasable in v1, same stub-and-flag approach as AdManager/BillingManager).
## Persisted via Godot's ConfigFile to user://save.cfg — no backend, no accounts,
## same $0-hosting philosophy as the rest of the portfolio.

signal currency_changed

const SAVE_PATH := "user://save.cfg"

const BOOSTER_EXTRA_MOVES := "extra_moves"
const BOOSTER_HAMMER := "hammer"
const BOOSTER_COLOR_BOMB_START := "color_bomb_start"

const BOOSTER_COSTS := {
	BOOSTER_EXTRA_MOVES: 50,
	BOOSTER_HAMMER: 75,
	BOOSTER_COLOR_BOMB_START: 120,
}

var coins: int = 100
var crystals: int = 0
var boosters: Dictionary = {} # booster_id -> count
var stars_by_level: Dictionary = {} # level_id (String) -> stars (int, 0-3)
var highest_unlocked_level: int = 1

func _ready() -> void:
	load_game()

func add_coins(amount: int) -> void:
	coins = maxi(0, coins + amount)
	currency_changed.emit()
	save_game()

func add_crystals(amount: int) -> void:
	crystals = maxi(0, crystals + amount)
	currency_changed.emit()
	save_game()

func can_afford_booster(booster_id: String) -> bool:
	return coins >= BOOSTER_COSTS.get(booster_id, 999999)

func buy_booster(booster_id: String) -> bool:
	var cost: int = BOOSTER_COSTS.get(booster_id, -1)
	if cost < 0 or coins < cost:
		return false
	coins -= cost
	boosters[booster_id] = boosters.get(booster_id, 0) + 1
	currency_changed.emit()
	save_game()
	return true

func consume_booster(booster_id: String) -> bool:
	var have: int = boosters.get(booster_id, 0)
	if have <= 0:
		return false
	boosters[booster_id] = have - 1
	save_game()
	return true

func booster_count(booster_id: String) -> int:
	return boosters.get(booster_id, 0)

func record_level_result(level_id: String, stars: int, coins_earned: int) -> void:
	var prev: int = stars_by_level.get(level_id, 0)
	if stars > prev:
		stars_by_level[level_id] = stars
	add_coins(coins_earned)
	save_game()

func unlock_next_level(level_number: int) -> void:
	if level_number > highest_unlocked_level:
		highest_unlocked_level = level_number
		save_game()

func is_level_unlocked(level_number: int) -> bool:
	return level_number <= highest_unlocked_level

func stars_for(level_id: String) -> int:
	return stars_by_level.get(level_id, 0)

func total_stars() -> int:
	var total := 0
	for v in stars_by_level.values():
		total += v
	return total

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("economy", "coins", coins)
	cfg.set_value("economy", "crystals", crystals)
	cfg.set_value("economy", "boosters", boosters)
	cfg.set_value("progress", "stars_by_level", stars_by_level)
	cfg.set_value("progress", "highest_unlocked_level", highest_unlocked_level)
	cfg.save(SAVE_PATH)

func load_game() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return # first launch, defaults above stand
	coins = cfg.get_value("economy", "coins", coins)
	crystals = cfg.get_value("economy", "crystals", crystals)
	boosters = cfg.get_value("economy", "boosters", boosters)
	stars_by_level = cfg.get_value("progress", "stars_by_level", stars_by_level)
	highest_unlocked_level = cfg.get_value("progress", "highest_unlocked_level", highest_unlocked_level)

func reset_all() -> void:
	coins = 100
	crystals = 0
	boosters = {}
	stars_by_level = {}
	highest_unlocked_level = 1
	save_game()
	currency_changed.emit()
