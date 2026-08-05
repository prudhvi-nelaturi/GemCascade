extends SceneTree

## Headless smoke test for the meta UI scenes (MainMenu, LevelMap, Shop,
## Settings, LevelComplete, LevelFail). run_tests.gd covers pure board/level
## logic; this one covers "does the screen build, animate and honour its
## contracts without erroring", which is the only kind of UI verification
## available without a display.
##
##   godot --headless --script res://scripts/tests/run_ui_smoke.gd
##
## NOTE: autoload singletons (Economy, ...) exist at runtime here, but they are
## NOT registered as compiler globals while this script itself is being
## compiled. So this file must not name LevelMapScreen / LevelCompleteScreen
## directly — doing so drags those scripts into the too-early compile pass and
## they fail with "Identifier not found: Economy". Their static vars are read
## and written through the script resource instead (script.get/set), which is
## equivalent. The same limitation is why `--check-only` cannot verify any
## script that touches an autoload.

const LEVEL_MAP_SCRIPT := "res://scripts/ui/LevelMap.gd"
const LEVEL_COMPLETE_SCRIPT := "res://scripts/ui/LevelComplete.gd"

const SCENES := [
	"res://scenes/MainMenu.tscn",
	"res://scenes/LevelMap.tscn",
	"res://scenes/Shop.tscn",
	"res://scenes/Settings.tscn",
	"res://scenes/LevelFail.tscn",
]

var _pass := 0
var _fail := 0
var _saved: Dictionary = {}


func _initialize() -> void:
	print("=== GemCascade UI smoke test ===")
	_snapshot_economy()

	for path in SCENES:
		await _test_scene_builds(path)

	await _test_level_map_nodes()
	await _test_level_complete_credits()
	await _test_level_complete_demo_mode()
	await _test_settings_persistence()
	await _test_shop_purchase_flow()
	_test_scene_paths_exist()
	_test_gameplay_handoff()

	_restore_economy()
	print("\n=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# --- helpers -----------------------------------------------------------------

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: %s" % message)


func _snapshot_economy() -> void:
	var economy := root.get_node_or_null("Economy")
	if economy == null:
		return
	_saved = {
		"coins": economy.coins,
		"crystals": economy.crystals,
		"boosters": economy.boosters.duplicate(),
		"stars": economy.stars_by_level.duplicate(),
		"highest": economy.highest_unlocked_level,
	}


## The smoke test writes through the real save file, so put it back exactly as
## it was — a test run must not cost the player their progress.
func _restore_economy() -> void:
	var economy := root.get_node_or_null("Economy")
	if economy == null or _saved.is_empty():
		return
	economy.coins = _saved["coins"]
	economy.crystals = _saved["crystals"]
	economy.boosters = _saved["boosters"]
	economy.stars_by_level = _saved["stars"]
	economy.highest_unlocked_level = _saved["highest"]
	economy.save_game()


func _open(path: String) -> Node:
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var inst := packed.instantiate()
	root.add_child(inst)
	return inst


func _settle(frames: int = 8) -> void:
	for i in frames:
		await process_frame


func _count_nodes(node: Node, type_name: String) -> int:
	var count := 0
	if node.is_class(type_name):
		count += 1
	for child in node.get_children():
		count += await _count_nodes(child, type_name)
	return count


# --- tests -------------------------------------------------------------------

func _test_scene_builds(path: String) -> void:
	var inst := _open(path)
	_assert(inst != null, "%s failed to instantiate" % path)
	if inst == null:
		return
	await _settle(10)
	_assert(inst.get_child_count() > 0, "%s built no children" % path)
	inst.queue_free()
	await _settle(2)


func _test_level_map_nodes() -> void:
	var economy := root.get_node_or_null("Economy")
	if economy != null:
		economy.highest_unlocked_level = 3
	var map_script: GDScript = load(LEVEL_MAP_SCRIPT)
	map_script.set("focus_level_number", 3)

	var inst := _open("res://scenes/LevelMap.tscn")
	_assert(inst != null, "LevelMap failed to instantiate")
	if inst == null:
		return
	await _settle(12)

	var buttons := await _count_nodes(inst, "Button")
	# 24 level nodes + back + shop-less currency bar buttons.
	_assert(buttons >= 24, "LevelMap should build at least 24 level buttons, found %d" % buttons)
	_assert(int(map_script.get("focus_level_number")) == 0, "LevelMap should consume focus_level_number")
	inst.queue_free()
	await _settle(2)


func _test_level_complete_credits() -> void:
	var economy := root.get_node_or_null("Economy")
	if economy == null:
		_assert(false, "Economy autoload missing")
		return
	economy.stars_by_level = {}
	economy.highest_unlocked_level = 1
	var coins_before: int = economy.coins

	var complete_script: GDScript = load(LEVEL_COMPLETE_SCRIPT)
	complete_script.set("pending_result", {
		"level_number": 1,
		"stars": 2,
		"score": 4210,
		"coins_earned": 50,
	})
	var inst := _open("res://scenes/LevelComplete.tscn")
	_assert(inst != null, "LevelComplete failed to instantiate")
	if inst == null:
		return

	_assert((complete_script.get("pending_result") as Dictionary).is_empty(),
		"LevelComplete should consume pending_result immediately (no double-credit on reload)")
	_assert(economy.stars_for("level_001") == 2, "LevelComplete should record 2 stars for level_001")
	_assert(economy.highest_unlocked_level == 2, "LevelComplete should unlock level 2")
	_assert(economy.coins == coins_before + 50, "LevelComplete should credit 50 coins")

	# Let the whole star-reveal sequence run so tween/particle callbacks are
	# exercised rather than just the initial layout.
	await _settle(4)
	await create_timer(3.2).timeout
	_assert(is_instance_valid(inst), "LevelComplete freed itself during the celebration")
	inst.queue_free()
	await _settle(2)


func _test_level_complete_demo_mode() -> void:
	var economy := root.get_node_or_null("Economy")
	var stars_before: Dictionary = economy.stars_by_level.duplicate() if economy != null else {}
	var complete_script: GDScript = load(LEVEL_COMPLETE_SCRIPT)
	complete_script.set("pending_result", {})
	var inst := _open("res://scenes/LevelComplete.tscn")
	await _settle(6)
	if economy != null:
		_assert(economy.stars_by_level == stars_before,
			"LevelComplete with no pending_result must not credit anything")
	if inst != null:
		inst.queue_free()
	await _settle(2)


func _test_settings_persistence() -> void:
	var original := GameSettings.sound_enabled
	GameSettings.set_sound(not original)
	GameSettings.sound_enabled = original # force a reload from disk
	GameSettings.load_settings()
	_assert(GameSettings.sound_enabled == (not original), "GameSettings should persist the sound flag")
	GameSettings.set_sound(original)
	_assert(GameSettings.sound_enabled == original, "GameSettings should restore the sound flag")


## The shop's one real transaction path: press BUY and confirm the Economy
## actually moved, and that an unaffordable booster is disabled rather than
## silently failing.
func _test_shop_purchase_flow() -> void:
	var economy := root.get_node_or_null("Economy")
	if economy == null:
		return
	economy.coins = 500
	economy.boosters = {}

	var inst := _open("res://scenes/Shop.tscn")
	if inst == null:
		_assert(false, "Shop failed to instantiate")
		return
	await _settle(10)

	var buy := _find_button(inst, "BUY")
	_assert(buy != null, "Shop should show an enabled BUY button with 500 coins")
	if buy != null:
		buy.emit_signal("pressed")
		await _settle(4)
		_assert(economy.coins == 450, "Buying extra_moves should cost 50 coins (coins=%d)" % economy.coins)
		_assert(int(economy.booster_count("extra_moves")) == 1, "Buying should grant 1 extra_moves booster")

	economy.coins = 0
	economy.currency_changed.emit()
	await _settle(4)
	var still_enabled := _find_button(inst, "BUY")
	_assert(still_enabled == null, "With 0 coins every BUY button should be disabled")

	inst.queue_free()
	await _settle(2)


## Guards against a typo in a navigation path silently dead-ending a button.
func _test_scene_paths_exist() -> void:
	for path in [UITheme.SCENE_MAIN_MENU, UITheme.SCENE_LEVEL_MAP, UITheme.SCENE_SHOP,
			UITheme.SCENE_SETTINGS, UITheme.SCENE_LEVEL_COMPLETE, UITheme.SCENE_LEVEL_FAIL]:
		_assert(ResourceLoader.exists(path), "navigation target missing: %s" % path)


func _find_button(node: Node, text: String) -> Button:
	if node is Button:
		var b := node as Button
		if b.text == text and not b.disabled:
			return b
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


## The seam between the meta UI and the gameplay screen: SceneRouter has to find
## GameplayController at runtime and write its `pending_level_number` static.
## This is the assertion that catches the two agents drifting apart.
func _test_gameplay_handoff() -> void:
	var gameplay_script: GDScript = SceneRouter._find_gameplay_script()
	_assert(gameplay_script != null, "SceneRouter could not locate GameplayController")
	if gameplay_script == null:
		return
	var restore: int = int(gameplay_script.get(SceneRouter.PENDING_LEVEL_PROPERTY))
	gameplay_script.set(SceneRouter.PENDING_LEVEL_PROPERTY, 7)
	_assert(int(gameplay_script.get(SceneRouter.PENDING_LEVEL_PROPERTY)) == 7,
		"GameplayController.pending_level_number is not writable through the script object")
	gameplay_script.set(SceneRouter.PENDING_LEVEL_PROPERTY, restore)
	_assert(ResourceLoader.exists(UITheme.SCENE_GAMEPLAY),
		"Gameplay.tscn missing — level taps would dead-end")
	_assert(SceneRouter.level_exists(1) and SceneRouter.level_id(3) == "level_003",
		"level resource lookup helpers are wrong")
