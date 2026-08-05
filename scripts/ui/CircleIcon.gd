class_name CircleIcon
extends Control

## Procedurally drawn coin/crystal stand-in. Only used when the corresponding
## PNG in assets/ui/ hasn't been generated yet — keeps the HUD readable instead
## of showing a missing-texture box.

@export var fill_color: Color = UITheme.GOLD
@export var rim_color: Color = UITheme.GOLD.darkened(0.4)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5
	var c := size * 0.5
	draw_circle(c, r, rim_color)
	draw_circle(c, r * 0.82, fill_color)
	draw_circle(c - Vector2(r * 0.25, r * 0.3), r * 0.22, Color(1, 1, 1, 0.55))
