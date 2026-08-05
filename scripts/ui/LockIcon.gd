class_name LockIcon
extends Control

## Padlock drawn procedurally (no art dependency) for locked level nodes on the
## LevelMap. A greyed-out number alone doesn't read as "locked" on mobile;
## the padlock does.

const BODY := Color("cfc4e8")
const SHADOW := Color("2a2140")

func _init(px: float = 36.0) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var w: float = minf(size.x, size.y)
	var body_w := w * 0.72
	var body_h := w * 0.52
	var body_rect := Rect2(
		Vector2((size.x - body_w) * 0.5, size.y * 0.5 - body_h * 0.12),
		Vector2(body_w, body_h))

	var shackle_center := Vector2(size.x * 0.5, body_rect.position.y)
	var shackle_r := body_w * 0.30
	draw_arc(shackle_center, shackle_r, PI, TAU, 20, SHADOW, w * 0.14, true)
	draw_arc(shackle_center, shackle_r, PI, TAU, 20, BODY, w * 0.10, true)

	draw_rect(body_rect.grow(2.0), SHADOW, true)
	draw_rect(body_rect, BODY, true)
	draw_circle(body_rect.get_center(), w * 0.08, SHADOW)
