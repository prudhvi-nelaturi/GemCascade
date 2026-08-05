class_name CurrencyBar
extends PanelContainer

## Live coin/crystal readout, shared by MainMenu, LevelMap and Shop. Redraws
## itself from the Economy autoload's `currency_changed` signal and punches the
## changed value so a purchase or reward is felt, not just displayed.

var _coin_label: Label
var _crystal_label: Label
var _coins_shown: int = -1
var _crystals_shown: int = -1
var show_shop_button: bool = true

func _init(with_shop_button: bool = true) -> void:
	show_shop_button = with_shop_button

func _ready() -> void:
	var sb := UITheme.panel_style(Color(0.09, 0.05, 0.18, 0.75), 26, Color(1, 1, 1, 0.18), 2)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	row.add_child(UITheme.make_currency_icon("coin", 36))
	_coin_label = UITheme.make_label("0", 28, UITheme.GOLD, 4)
	_coin_label.custom_minimum_size = Vector2(74, 0)
	_coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(_coin_label)

	var sep := VSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.25)
	row.add_child(sep)

	row.add_child(UITheme.make_currency_icon("crystal", 36))
	_crystal_label = UITheme.make_label("0", 28, UITheme.CYAN, 4)
	_crystal_label.custom_minimum_size = Vector2(56, 0)
	_crystal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(_crystal_label)

	if show_shop_button:
		var plus := UITheme.make_button("+", UITheme.GREEN, 26)
		plus.custom_minimum_size = Vector2(46, 0)
		plus.pressed.connect(func() -> void: UITheme.go_to_scene(self, UITheme.SCENE_SHOP))
		row.add_child(plus)

	if Economy != null and not Economy.currency_changed.is_connected(_refresh):
		Economy.currency_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if Economy == null:
		return
	_apply(_coin_label, Economy.coins, _coins_shown)
	_apply(_crystal_label, Economy.crystals, _crystals_shown)
	_coins_shown = Economy.coins
	_crystals_shown = Economy.crystals

func _apply(label: Label, value: int, previous: int) -> void:
	if label == null:
		return
	label.text = str(value)
	if previous >= 0 and previous != value:
		label.pivot_offset = label.size * 0.5
		var tw := label.create_tween()
		tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(label, "scale", Vector2(1.35, 1.35), 0.12)
		tw.tween_property(label, "scale", Vector2.ONE, 0.22)
