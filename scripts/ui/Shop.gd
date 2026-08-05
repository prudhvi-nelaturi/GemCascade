class_name ShopScreen
extends Control

## Booster shop. Coins are spendable for real (Economy.buy_booster); crystals
## are display-only in v1 — BillingManager is a stub that always fails, so the
## crystal packs are labelled COMING SOON rather than pretending to sell
## anything.
##
## The booster table is built at runtime rather than as a `const`, because the
## booster ids live on the Economy autoload and an autoload's members aren't
## compile-time constants.

const CRYSTAL_PACKS := [
	{"sku": "crystals_small", "amount": 50, "price": "$0.99"},
	{"sku": "crystals_medium", "amount": 300, "price": "$4.99"},
	{"sku": "crystals_large", "amount": 800, "price": "$9.99"},
]

var _boosters: Array[Dictionary] = []
var _rows: Dictionary = {} # booster_id -> {"card": Control, "owned": Label, "buy": Button}

func _ready() -> void:
	GameSettings.apply()
	_boosters = [
		{
			"id": Economy.BOOSTER_EXTRA_MOVES,
			"name": "+5 EXTRA MOVES",
			"desc": "Out of moves? Keep the cascade going.",
			"symbol": "+5",
			"color": UITheme.GREEN,
		},
		{
			"id": Economy.BOOSTER_HAMMER,
			"name": "GEM HAMMER",
			"desc": "Smash any single gem straight off the board.",
			"symbol": "HIT",
			"color": UITheme.ORANGE,
		},
		{
			"id": Economy.BOOSTER_COLOR_BOMB_START,
			"name": "COLOR BOMB START",
			"desc": "Begin the level with a color bomb already in play.",
			"symbol": "BOOM",
			"color": UITheme.PURPLE,
		},
	]

	add_child(UITheme.make_background("crystal_caves"))
	add_child(UITheme.make_scrim(0.66))

	var root_box := VBoxContainer.new()
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 0)
	add_child(root_box)

	root_box.add_child(_build_top_bar())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_box.add_child(scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 30)
	pad.add_theme_constant_override("margin_right", 30)
	pad.add_theme_constant_override("margin_top", 24)
	pad.add_theme_constant_override("margin_bottom", 40)
	scroll.add_child(pad)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 20)
	pad.add_child(column)

	column.add_child(_section_title("BOOSTERS", UITheme.GOLD))
	var delay := 0.05
	for i in _boosters.size():
		var card := _build_booster_card(i)
		column.add_child(card)
		UITheme.slide_in(card, delay, 30.0, 0.32)
		delay += 0.07

	column.add_child(UITheme.make_spacer(16))
	column.add_child(_section_title("CRYSTALS", UITheme.CYAN))
	var crystals_card := _build_crystal_card()
	column.add_child(crystals_card)
	UITheme.slide_in(crystals_card, delay, 30.0, 0.32)

	if Economy != null:
		Economy.currency_changed.connect(_refresh_all)
	_refresh_all()


func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	var sb := UITheme.panel_style(Color(0.06, 0.03, 0.13, 0.92), 0)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	bar.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

	var back := UITheme.make_ghost_button("BACK", UITheme.INK, 24)
	back.pressed.connect(_go_back)
	row.add_child(back)

	row.add_child(UITheme.make_label("SHOP", 34, UITheme.INK, 6))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	row.add_child(CurrencyBar.new(false))
	return bar


func _go_back() -> void:
	UITheme.go_to_scene(self, UITheme.SCENE_MAIN_MENU)


func _section_title(text: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := UITheme.make_label(text, 28, color, 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(label)

	var line := Panel.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.custom_minimum_size = Vector2(0, 3)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.35)
	sb.set_corner_radius_all(2)
	line.add_theme_stylebox_override("panel", sb)
	row.add_child(line)
	return row


# --- Booster cards -----------------------------------------------------------

func _build_booster_card(index: int) -> Control:
	var info: Dictionary = _boosters[index]
	var booster_id: String = info["id"]
	var accent: Color = info["color"]

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0.10, 0.06, 0.20, 0.92), 28, accent, 3))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)

	# Icon tile: a gem sprite when the art exists, otherwise a lettered chip.
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(104, 104)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tile_sb := UITheme.panel_style(accent.darkened(0.15), 24, accent.lightened(0.3), 2)
	tile_sb.set_content_margin_all(10)
	tile.add_theme_stylebox_override("panel", tile_sb)
	var gem_tex := UITheme.texture("res://assets/gems/gem_%d.png" % index)
	if gem_tex != null:
		var tr := TextureRect.new()
		tr.texture = gem_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tile.add_child(tr)
	else:
		tile.add_child(UITheme.make_label(info["symbol"], 30, UITheme.INK, 5))
	row.add_child(tile)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 4)
	row.add_child(text_col)

	var name_label := UITheme.make_label(info["name"], 28, UITheme.INK, 5)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_col.add_child(name_label)

	var desc := UITheme.make_label(info["desc"], 19, UITheme.INK_DIM, 0)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(230, 0)
	text_col.add_child(desc)

	var owned := UITheme.make_label("", 22, accent.lightened(0.25), 3)
	owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_col.add_child(owned)

	var buy_col := VBoxContainer.new()
	buy_col.alignment = BoxContainer.ALIGNMENT_CENTER
	buy_col.add_theme_constant_override("separation", 6)
	row.add_child(buy_col)

	var cost: int = Economy.BOOSTER_COSTS.get(booster_id, 0)
	var price_row := HBoxContainer.new()
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.add_theme_constant_override("separation", 6)
	price_row.add_child(UITheme.make_currency_icon("coin", 26))
	price_row.add_child(UITheme.make_label(str(cost), 24, UITheme.GOLD, 4))
	buy_col.add_child(price_row)

	var buy := UITheme.make_button("BUY", accent, 26)
	buy.custom_minimum_size = Vector2(132, 64)
	buy.pressed.connect(_on_buy_pressed.bind(booster_id))
	buy_col.add_child(buy)

	_rows[booster_id] = {"card": card, "owned": owned, "buy": buy}
	return card


func _on_buy_pressed(booster_id: String) -> void:
	if Economy == null:
		return
	var row: Dictionary = _rows.get(booster_id, {})
	if not Economy.buy_booster(booster_id):
		UITheme.toast(self, "Not enough coins — win levels to earn more!")
		if row.has("card"):
			UITheme.shake(row["card"], 12.0, 0.35)
		return
	if row.has("card"):
		var card: Control = row["card"]
		card.pivot_offset = card.size * 0.5
		var tw := card.create_tween()
		tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "scale", Vector2(1.03, 1.03), 0.10)
		tw.tween_property(card, "scale", Vector2.ONE, 0.20)
	UITheme.toast(self, "Purchased! It'll be waiting in your next level.", 1.6)


func _refresh_all() -> void:
	if Economy == null:
		return
	for booster_id in _rows.keys():
		var row: Dictionary = _rows[booster_id]
		var owned_label: Label = row["owned"]
		var buy: Button = row["buy"]
		owned_label.text = "Owned: %d" % int(Economy.booster_count(booster_id))
		var affordable: bool = Economy.can_afford_booster(booster_id)
		buy.disabled = not affordable
		buy.text = "BUY" if affordable else "TOO FEW"
		buy.add_theme_font_size_override("font_size", 26 if affordable else 20)


# --- Crystals (stubbed IAP) --------------------------------------------------

func _build_crystal_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0.07, 0.12, 0.22, 0.92), 28, UITheme.CYAN, 3))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UITheme.make_currency_icon("crystal", 40))
	var head_label := UITheme.make_label("GET MORE CRYSTALS", 26, UITheme.INK, 5)
	head_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(head_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	var badge := PanelContainer.new()
	var badge_sb := UITheme.panel_style(UITheme.GOLD, 16)
	badge_sb.content_margin_left = 12
	badge_sb.content_margin_right = 12
	badge_sb.content_margin_top = 4
	badge_sb.content_margin_bottom = 4
	badge.add_theme_stylebox_override("panel", badge_sb)
	badge.add_child(UITheme.make_label("COMING SOON", 18, UITheme.OUTLINE, 0))
	head.add_child(badge)
	column.add_child(head)

	var blurb := UITheme.make_label(
		"Crystal packs aren't available yet — in-app purchases arrive in a later update. Nothing here can charge you.",
		19, UITheme.INK_DIM, 0)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(blurb)

	var packs := HBoxContainer.new()
	packs.add_theme_constant_override("separation", 12)
	column.add_child(packs)
	for pack in CRYSTAL_PACKS:
		var pack_col := VBoxContainer.new()
		pack_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pack_col.alignment = BoxContainer.ALIGNMENT_CENTER
		pack_col.add_theme_constant_override("separation", 6)
		pack_col.add_child(UITheme.make_currency_icon("crystal", 34))
		pack_col.add_child(UITheme.make_label("%d" % int(pack["amount"]), 24, UITheme.CYAN, 4))
		var b := UITheme.make_button(str(pack["price"]), UITheme.SLATE, 22)
		b.custom_minimum_size = Vector2(0, 58)
		b.pressed.connect(_on_crystal_pack_pressed.bind(str(pack["sku"])))
		pack_col.add_child(b)
		packs.add_child(pack_col)
	return card


## Real hook into the v1 BillingManager stub: it always invokes the failure
## callback, which is exactly the "coming soon" path the UI advertises. When a
## real Play Billing implementation lands, only _on_purchase_ok has to change.
func _on_crystal_pack_pressed(sku: String) -> void:
	BillingManager.purchase(sku, _on_purchase_ok, _on_purchase_unavailable)


func _on_purchase_ok() -> void:
	UITheme.toast(self, "Purchase complete!")


func _on_purchase_unavailable() -> void:
	UITheme.toast(self, "Crystal packs aren't available yet — coming in a future update.")


## Android hardware back button — mirrors the on-screen BACK button.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()
