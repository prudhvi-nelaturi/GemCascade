class_name StarIcon
extends Control

## A single progress star. Uses assets/ui/star_filled.png / star_empty.png when
## the art agent has generated them, and falls back to a procedurally drawn
## 5-point star otherwise — so LevelMap and LevelComplete look correct either
## way, including in headless tests where no art exists at all.

const TEX_FILLED := "res://assets/ui/star_filled.png"
const TEX_EMPTY := "res://assets/ui/star_empty.png"

const FILL_ON := Color("ffd447")
const RIM_ON := Color("ff9f1c")
const FILL_OFF := Color(1, 1, 1, 0.13)
const RIM_OFF := Color(1, 1, 1, 0.28)

var filled: bool = false:
	set(value):
		filled = value
		queue_redraw()

var _tex_filled: Texture2D
var _tex_empty: Texture2D

func _init(is_filled: bool = false, px: float = 48.0) -> void:
	filled = is_filled
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_tex_filled = UITheme.texture(TEX_FILLED)
	_tex_empty = UITheme.texture(TEX_EMPTY)
	resized.connect(func() -> void:
		pivot_offset = size * 0.5
		queue_redraw())
	pivot_offset = size * 0.5
	queue_redraw()

func _draw() -> void:
	var tex: Texture2D = _tex_filled if filled else _tex_empty
	if tex != null:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
		return

	var center := size * 0.5
	var outer: float = minf(size.x, size.y) * 0.5
	var pts := _star_points(center, outer, outer * 0.46)
	var fill := FILL_ON if filled else FILL_OFF
	var rim := RIM_ON if filled else RIM_OFF

	# draw_colored_polygon needs convex input to be reliable, so triangulate the
	# concave star shape first and draw each triangle.
	var indices := Geometry2D.triangulate_polygon(pts)
	var i := 0
	while i + 2 < indices.size():
		var tri := PackedVector2Array([pts[indices[i]], pts[indices[i + 1]], pts[indices[i + 2]]])
		draw_colored_polygon(tri, fill)
		i += 3

	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, rim, maxf(2.0, outer * 0.09), true)

static func _star_points(center: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var r: float = outer if i % 2 == 0 else inner
		var a: float = -PI * 0.5 + float(i) * PI / 5.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts
