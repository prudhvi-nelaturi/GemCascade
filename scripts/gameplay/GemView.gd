class_name GemView
extends Node2D

## One gem sprite on the board: a base sprite plus an optional special-gem
## overlay. Owns no game logic — Board is the source of truth, BoardView tells
## this node what to look like and where to be.
##
## The node's own `scale`/`rotation`/`modulate` are reserved for animation, so
## the fit-to-cell scaling lives on the child sprites instead. That way a pop or
## squash tween can drive `scale` from 1.0 without fighting the layout.

const FILL_RATIO := 0.88 # gem diameter as a fraction of the cell

var gem_color: int = 0
var gem_special: int = GemTypes.Special.NONE

var _base: Sprite2D
var _overlay: Sprite2D
var _cell_size: float = 64.0

func _init() -> void:
	_base = Sprite2D.new()
	add_child(_base)
	_overlay = Sprite2D.new()
	_overlay.visible = false
	add_child(_overlay)

func set_cell_size(cell_size: float) -> void:
	_cell_size = cell_size
	_rescale()

func set_gem(color: int, special: int) -> void:
	gem_color = color
	gem_special = special

	if special == GemTypes.Special.COLOR_BOMB:
		# A colour bomb matches every colour, so it gets its own base art rather
		# than a tinted gem — no single colour would be honest here.
		_base.texture = GemArt.bomb_texture()
		_base.modulate = Color.WHITE
	else:
		_base.texture = GemArt.gem_texture(color)
		_base.modulate = Color.WHITE

	match special:
		GemTypes.Special.STRIPED_H:
			_overlay.texture = GemArt.stripe_overlay()
			_overlay.rotation = 0.0
			_overlay.visible = true
		GemTypes.Special.STRIPED_V:
			_overlay.texture = GemArt.stripe_overlay()
			_overlay.rotation = PI * 0.5
			_overlay.visible = true
		GemTypes.Special.WRAPPED:
			_overlay.texture = GemArt.wrapped_overlay()
			_overlay.rotation = 0.0
			_overlay.visible = true
		_:
			_overlay.visible = false
			_overlay.texture = null

	_rescale()

func matches(color: int, special: int) -> bool:
	return gem_color == color and gem_special == special

func tint_color() -> Color:
	if gem_special == GemTypes.Special.COLOR_BOMB:
		return Color(1, 1, 1)
	return GemArt.color_of(gem_color)

func _rescale() -> void:
	_apply_sprite_scale(_base)
	_apply_sprite_scale(_overlay)

func _apply_sprite_scale(sprite: Sprite2D) -> void:
	if sprite == null or sprite.texture == null:
		return
	var tex_size: float = maxf(1.0, float(sprite.texture.get_width()))
	var s: float = (_cell_size * FILL_RATIO) / tex_size
	sprite.scale = Vector2(s, s)
