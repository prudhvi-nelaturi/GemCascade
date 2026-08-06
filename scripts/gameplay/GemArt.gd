class_name GemArt
extends RefCounted

## Texture + palette lookup for everything the gameplay layer draws.
##
## Every texture is loaded from its authored path first (the art pipeline writes
## the PNGs listed below). If a file is missing or hasn't been imported yet, a
## procedurally generated stand-in is produced instead so the gameplay scene is
## always runnable — art and gameplay are built in parallel and neither should
## be able to block the other. Generated textures are cached per key, so the
## per-pixel work happens at most once per run.

const GEM_TEXTURE_PATH := "res://assets/gems/gem_%d.png"
const STRIPE_OVERLAY_PATH := "res://assets/gems/gem_stripe_overlay.png"
const WRAPPED_OVERLAY_PATH := "res://assets/gems/gem_wrapped_overlay.png"
const BOMB_TEXTURE_PATH := "res://assets/gems/gem_bomb.png"
const SPARK_TEXTURE_PATH := "res://assets/particles/spark.png"

const TEX_SIZE := 128

## Indexed by GemTypes.GemColor. Also drives particle tint, HUD objective chips
## and the combo popup, so every colour cue in the game agrees.
const COLORS := [
	Color(1.00, 0.23, 0.36), # RUBY
	Color(0.18, 0.48, 1.00), # SAPPHIRE
	Color(0.14, 0.82, 0.55), # EMERALD
	Color(1.00, 0.77, 0.19), # TOPAZ
	Color(0.71, 0.29, 1.00), # AMETHYST
	Color(0.44, 0.91, 0.96), # DIAMOND
]

static var _cache: Dictionary = {}

static func color_of(color_index: int) -> Color:
	if color_index < 0 or color_index >= COLORS.size():
		return Color(0.9, 0.93, 1.0)
	return COLORS[color_index]

static func gem_texture(color_index: int) -> Texture2D:
	var key := "gem_%d" % color_index
	if _cache.has(key):
		return _cache[key]
	var tex := _try_load(GEM_TEXTURE_PATH % color_index)
	if tex == null:
		tex = _generate_gem(color_of(color_index))
	_cache[key] = tex
	return tex

static func stripe_overlay() -> Texture2D:
	if _cache.has("stripe"):
		return _cache["stripe"]
	var tex := _try_load(STRIPE_OVERLAY_PATH)
	if tex == null:
		tex = _generate_stripe()
	_cache["stripe"] = tex
	return tex

static func wrapped_overlay() -> Texture2D:
	if _cache.has("wrapped"):
		return _cache["wrapped"]
	var tex := _try_load(WRAPPED_OVERLAY_PATH)
	if tex == null:
		tex = _generate_wrapped()
	_cache["wrapped"] = tex
	return tex

static func bomb_texture() -> Texture2D:
	if _cache.has("bomb"):
		return _cache["bomb"]
	var tex := _try_load(BOMB_TEXTURE_PATH)
	if tex == null:
		tex = _generate_bomb()
	_cache["bomb"] = tex
	return tex

static func spark_texture() -> Texture2D:
	if _cache.has("spark"):
		return _cache["spark"]
	var tex := _try_load(SPARK_TEXTURE_PATH)
	if tex == null:
		tex = _generate_spark()
	_cache["spark"] = tex
	return tex

static func blocker_texture() -> Texture2D:
	if _cache.has("blocker"):
		return _cache["blocker"]
	var tex := _generate_blocker()
	_cache["blocker"] = tex
	return tex

static func _try_load(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path)
	if res is Texture2D:
		return res
	return null

# ---------------------------------------------------------------------------
# Procedural stand-ins
# ---------------------------------------------------------------------------

## Rounded-square "gem" with a radial falloff, a darker rim and a soft specular
## blob in the upper-left, which is enough shape language to read as a distinct
## faceted piece at cell size even without authored art.
static func _generate_gem(base: Color) -> Texture2D:
	var size := TEX_SIZE
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var half := size * 0.5
	var radius := half - 6.0
	var highlight_center := Vector2(size * 0.34, size * 0.30)
	var highlight_radius := size * 0.22
	for y in range(size):
		for x in range(size):
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p - Vector2(half, half)
			# Superellipse (squircle) distance: reads as a rounded gem, not a ball.
			var n := pow(absf(d.x) / radius, 3.2) + pow(absf(d.y) / radius, 3.2)
			if n > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var edge := clampf((1.0 - n) * 4.0, 0.0, 1.0) # 0 at rim, 1 inside
			var shade := clampf(1.0 - (p.y / size) * 0.55 + (1.0 - p.x / size) * 0.18, 0.0, 1.4)
			var col := base * shade
			col = col.lerp(base.darkened(0.55), 1.0 - edge)
			var hd := p.distance_to(highlight_center)
			if hd < highlight_radius:
				var h := pow(1.0 - hd / highlight_radius, 2.0) * 0.75
				col = col.lerp(Color(1, 1, 1), h)
			col.a = clampf(edge * 3.0, 0.0, 1.0)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## Horizontal light bands, drawn white so the sprite can be tinted per gem and
## rotated 90 degrees for the vertical striped variant.
static func _generate_stripe() -> Texture2D:
	var size := TEX_SIZE
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		var band := absf(sin(float(y) / size * PI * 5.0))
		var a := 0.0
		if band > 0.65:
			a = (band - 0.65) / 0.35 * 0.85
		for x in range(size):
			var fade := 1.0 - clampf(absf(x - size * 0.5) / (size * 0.5), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * clampf(fade * 1.8, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

## Bright double outline — reads as "wrapped in energy" on top of the base gem.
static func _generate_wrapped() -> Texture2D:
	var size := TEX_SIZE
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var half := size * 0.5
	for y in range(size):
		for x in range(size):
			var p := Vector2(x + 0.5, y + 0.5)
			var d := (p - Vector2(half, half)).abs()
			var ring := maxf(d.x, d.y)
			var a := 0.0
			if ring > half - 10.0 and ring < half - 3.0:
				a = 0.9
			elif ring > half - 26.0 and ring < half - 20.0:
				a = 0.5
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

## Dark orb speckled with the full gem palette — the "any colour" colour bomb.
static func _generate_bomb() -> Texture2D:
	var size := TEX_SIZE
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var half := size * 0.5
	var radius := half - 5.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260805
	for y in range(size):
		for x in range(size):
			var p := Vector2(x + 0.5, y + 0.5)
			var dist := p.distance_to(Vector2(half, half))
			if dist > radius:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var t := dist / radius
			var col := Color(0.10, 0.08, 0.18).lerp(Color(0.02, 0.01, 0.06), t)
			# Palette speckles, angularly banded so it looks like a disco ball.
			var ang := (p - Vector2(half, half)).angle()
			var band := int(((ang + PI) / TAU) * 12.0) % COLORS.size()
			var speck := sin(dist * 0.55) * cos(ang * 6.0)
			if speck > 0.55 and t < 0.92:
				col = col.lerp(COLORS[band], 0.85)
			var hd := p.distance_to(Vector2(size * 0.35, size * 0.30))
			if hd < size * 0.16:
				col = col.lerp(Color(1, 1, 1), pow(1.0 - hd / (size * 0.16), 2.0) * 0.6)
			col.a = clampf((radius - dist) * 0.5, 0.0, 1.0)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## Soft round dot for the burst particles (tinted per gem via node modulate).
static func _generate_spark() -> Texture2D:
	var size := 32
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var half := size * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(half, half))
			var a := clampf(1.0 - d / half, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, pow(a, 1.6)))
	return ImageTexture.create_from_image(img)

## Semi-transparent cracked slab drawn over a cell for CLEAR_BLOCKERS levels.
static func _generate_blocker() -> Texture2D:
	var size := TEX_SIZE
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var edge := minf(minf(float(x), float(y)), minf(float(size - 1 - x), float(size - 1 - y)))
			if edge < 3.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var col := Color(0.16, 0.14, 0.22, 0.82)
			if edge < 9.0:
				col = Color(0.45, 0.42, 0.58, 0.9)
			# Two crack lines so a broken blocker reads at a glance.
			var c1 := absf((x - y) - 6.0)
			var c2 := absf((x + y) - float(size) - 10.0)
			if c1 < 2.5 or c2 < 2.5:
				col = Color(0.72, 0.70, 0.85, 0.85)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
