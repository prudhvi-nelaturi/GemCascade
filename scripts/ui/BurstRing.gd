class_name BurstRing
extends Control

## Expanding shockwave ring drawn behind a star as it lands. Cheap, procedural,
## and it does more for the "that landed" feeling than the particles alone.

@export var ring_color: Color = UITheme.GOLD

var progress: float = 0.0:
	set(value):
		progress = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if progress <= 0.0 or progress >= 1.0:
		return
	var center := size * 0.5
	var max_r: float = minf(size.x, size.y) * 0.9
	var r: float = lerpf(max_r * 0.15, max_r, progress)
	var alpha: float = (1.0 - progress) * 0.9
	var col := Color(ring_color.r, ring_color.g, ring_color.b, alpha)
	draw_arc(center, r, 0.0, TAU, 48, col, maxf(2.0, 10.0 * (1.0 - progress)), true)

## Fire-and-forget: plays the expansion once.
func play(duration: float = 0.45) -> void:
	progress = 0.0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "progress", 1.0, duration)
