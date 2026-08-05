class_name UITheme
extends RefCounted

## Shared look-and-feel for every meta UI screen (MainMenu, LevelMap, Shop,
## Settings, LevelComplete, LevelFail). No instances are ever created — this is
## a namespace of static factory/animation helpers, same RefCounted-as-namespace
## trick GemTypes.gd uses.
##
## DESIGN NOTE — why StyleBoxFlat instead of the ui/panel_rounded.png and
## ui/button_primary.png assets: every panel and button in this game is a
## different saturated colour (per episode, per booster, per state), and a
## single tinted 9-patch can't carry that without washing every card into the
## same hue. StyleBoxFlat gives per-widget colour, a chunky bottom "candy lip"
## border, and real corner radii at zero import cost, and it can never show a
## magenta missing-texture box. The generated PNGs are still used where they're
## genuinely pictorial: episode backgrounds, stars, coin/crystal icons, gems.

# --- Palette -----------------------------------------------------------------
const BG_TOP := Color("2a1655")
const BG_BOTTOM := Color("140b2c")
const INK := Color("ffffff")
const INK_DIM := Color("b9a9e8")
const OUTLINE := Color("1a0f33")

const PINK := Color("ff4d9d")
const PURPLE := Color("a855f7")
const CYAN := Color("22d3ee")
const LIME := Color("a3e635")
const GOLD := Color("ffc83d")
const ORANGE := Color("ff8a3d")
const RED := Color("ff5a5f")
const GREEN := Color("22c55e")
const SLATE := Color("4a4066")

const EPISODES: Array[String] = ["candy_forest", "crystal_caves", "sunset_beach"]
const EPISODE_TITLES := {
	"candy_forest": "Candy Forest",
	"crystal_caves": "Crystal Caves",
	"sunset_beach": "Sunset Beach",
}
## [bright accent, deep backdrop] per episode — drives buttons, headers and the
## gradient fallback used when the background PNG hasn't been generated yet.
const EPISODE_COLORS := {
	"candy_forest": [Color("ff6fb5"), Color("2d1b4e")],
	"crystal_caves": [Color("3fc4f5"), Color("162a52")],
	"sunset_beach": [Color("ff9d43"), Color("46203f")],
}

const LEVELS_PER_EPISODE := 8
const MAX_LEVEL := 24

# --- Scene paths (single source of truth for navigation) ---------------------
const SCENE_MAIN_MENU := "res://scenes/MainMenu.tscn"
const SCENE_LEVEL_MAP := "res://scenes/LevelMap.tscn"
const SCENE_SHOP := "res://scenes/Shop.tscn"
const SCENE_SETTINGS := "res://scenes/Settings.tscn"
const SCENE_GAMEPLAY := "res://scenes/Gameplay.tscn"
const SCENE_LEVEL_COMPLETE := "res://scenes/LevelComplete.tscn"
const SCENE_LEVEL_FAIL := "res://scenes/LevelFail.tscn"


# --- Asset loading -----------------------------------------------------------

## Art is authored in parallel by another agent, so every texture load has to
## survive the file not existing yet. Always load(), never preload().
static func texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func gradient_texture(top: Color, bottom: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, top)
	grad.set_color(1, bottom)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 8
	tex.height = 256
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	return tex


static func episode_of_level(level_number: int) -> String:
	var idx := clampi((level_number - 1) / LEVELS_PER_EPISODE, 0, EPISODES.size() - 1)
	return EPISODES[idx]


static func episode_accent(episode: String) -> Color:
	return EPISODE_COLORS.get(episode, [PINK, BG_BOTTOM])[0]


static func episode_backdrop(episode: String) -> Color:
	return EPISODE_COLORS.get(episode, [PINK, BG_BOTTOM])[1]


# --- Backgrounds -------------------------------------------------------------

## Full-rect background layer: the episode PNG when it exists, otherwise a
## vertical gradient in the same colour family so the screen never looks broken.
static func make_background(episode: String = "") -> Control:
	var rect := TextureRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex: Texture2D = null
	if episode != "":
		tex = texture("res://assets/backgrounds/%s.png" % episode)
	if tex != null:
		rect.texture = tex
	elif episode != "":
		rect.texture = gradient_texture(episode_accent(episode).darkened(0.35), episode_backdrop(episode))
	else:
		rect.texture = gradient_texture(BG_TOP, BG_BOTTOM)
	return rect


## Darkening scrim so white text stays readable over whatever the art agent
## produces.
static func make_scrim(alpha: float = 0.45, tint: Color = Color("120a26")) -> ColorRect:
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.color = Color(tint.r, tint.g, tint.b, alpha)
	return scrim


# --- Style boxes -------------------------------------------------------------

static func panel_style(bg: Color, radius: int = 28, border_color: Color = Color(0, 0, 0, 0), border_width: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(20)
	if border_width > 0:
		sb.set_border_width_all(border_width)
		sb.border_color = border_color
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	return sb


static func button_style(base: Color, radius: int = 24, lip: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = base
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14 + lip
	# Chunky darker "lip" along the bottom reads as a physical candy button.
	sb.border_width_bottom = lip
	sb.border_color = base.darkened(0.35)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	return sb


# --- Widgets -----------------------------------------------------------------

## The standard chunky candy button. `base` drives every state colour.
static func make_button(text: String, base: Color = PINK, font_size: int = 34) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	b.add_theme_color_override("font_outline_color", base.darkened(0.6))
	b.add_theme_constant_override("outline_size", 6)

	b.add_theme_stylebox_override("normal", button_style(base))
	b.add_theme_stylebox_override("hover", button_style(base.lightened(0.12)))
	b.add_theme_stylebox_override("focus", button_style(base))

	# Pressed state loses the lip and gains top padding, so the label physically
	# sinks into the button.
	var pressed := button_style(base.darkened(0.18), 24, 0)
	pressed.content_margin_top = 20
	pressed.content_margin_bottom = 14
	b.add_theme_stylebox_override("pressed", pressed)

	var disabled := button_style(SLATE.darkened(0.25))
	disabled.shadow_size = 0
	b.add_theme_stylebox_override("disabled", disabled)

	add_press_feedback(b)
	return b


## Small ghost/secondary button (back arrows, toggles, minor actions).
static func make_ghost_button(text: String, tint: Color = INK_DIM, font_size: int = 26) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", tint)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.10)
	sb.set_corner_radius_all(20)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.22)
	b.add_theme_stylebox_override("normal", sb)

	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.20)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", sb)

	add_press_feedback(b)
	return b


static func make_label(text: String, font_size: int = 30, color: Color = INK, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", OUTLINE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Coin / crystal icon: the generated PNG when present, otherwise a coloured
## circle drawn by CircleIcon so the HUD is never blank.
static func make_currency_icon(kind: String, px: int = 40) -> Control:
	var path := "res://assets/ui/%s_icon.png" % kind
	var tex := texture(path)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(px, px)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var icon := CircleIcon.new()
	icon.custom_minimum_size = Vector2(px, px)
	icon.fill_color = GOLD if kind == "coin" else CYAN
	icon.rim_color = (GOLD if kind == "coin" else CYAN).darkened(0.4)
	return icon


## Particle sprites are generated in code so the celebration effects never
## depend on an art file existing (and never render as a magenta box).
static func dot_texture(px: int = 12) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var c := (px - 1) * 0.5
	for y in px:
		for x in px:
			var d := Vector2(float(x) - c, float(y) - c).length()
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func square_texture(px: int = 8) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)


## Rainbow ramp used for confetti / star bursts: CPUParticles2D samples
## color_initial_ramp at random per particle, so one emitter gives many colours.
## (CPUParticles2D takes a Gradient here, not a GradientTexture1D.)
static func party_ramp() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([PINK, GOLD, LIME, CYAN, PURPLE, ORANGE])
	return g


static func make_spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# --- Animation ---------------------------------------------------------------

## Scale-down-on-press feedback. Keeps pivot centred through container relayouts.
static func add_press_feedback(c: Control) -> void:
	c.resized.connect(func() -> void: c.pivot_offset = c.size * 0.5)
	c.pivot_offset = c.size * 0.5
	if c is BaseButton:
		var b := c as BaseButton
		b.button_down.connect(func() -> void: _tween_scale(c, Vector2(0.93, 0.93), 0.08))
		b.button_up.connect(func() -> void: _tween_scale(c, Vector2.ONE, 0.18))
		b.mouse_exited.connect(func() -> void: _tween_scale(c, Vector2.ONE, 0.18))


static func _tween_scale(c: Control, to: Vector2, time: float) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	var tw := c.create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", to, time)


## Slide + fade a node in from below. Used to stagger a screen's content in
## rather than hard-cutting the whole layout on at once.
static func slide_in(c: Control, delay: float = 0.0, distance: float = 40.0, time: float = 0.35) -> void:
	if not is_instance_valid(c):
		return
	c.modulate.a = 0.0
	var target := c.position
	c.position = target + Vector2(0, distance)
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, time).set_delay(delay)
	tw.tween_property(c, "position", target, time).set_delay(delay)


## Overshooting scale-in ("pop"). The workhorse of the LevelComplete reveal.
static func pop_in(c: Control, delay: float = 0.0, from_scale: float = 0.4, time: float = 0.42) -> void:
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(from_scale, from_scale)
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, time * 0.5).set_delay(delay)
	tw.tween_property(c, "scale", Vector2.ONE, time)\
		.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Continuous idle "breathing" pulse — used on the PLAY button and the current
## level node so the eye is pulled to the primary action.
static func pulse(c: Control, amount: float = 0.05, period: float = 1.2) -> void:
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), period * 0.5)
	tw.tween_property(c, "scale", Vector2.ONE, period * 0.5)


static func shake(c: Control, strength: float = 14.0, time: float = 0.4) -> void:
	if not is_instance_valid(c):
		return
	var origin := c.position
	var tw := c.create_tween()
	var steps := 6
	for i in steps:
		var dir := 1.0 if i % 2 == 0 else -1.0
		var falloff := strength * (1.0 - float(i) / float(steps))
		tw.tween_property(c, "position", origin + Vector2(dir * falloff, 0), time / steps)
	tw.tween_property(c, "position", origin, time / steps)


## Transient bottom-of-screen message. Used for the "not available yet" cases
## (unbuilt level, stubbed IAP) so a tap always produces visible feedback
## instead of feeling broken.
static func toast(from: Node, text: String, duration: float = 2.0) -> void:
	if not is_instance_valid(from) or not from.is_inside_tree():
		return
	var layer := CanvasLayer.new()
	layer.layer = 120
	from.get_tree().root.add_child(layer)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style(Color(0.07, 0.04, 0.14, 0.94), 22, PINK, 2))
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position = Vector2(360, 1120)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)

	var label := make_label(text, 24, INK, 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(520, 0)
	panel.add_child(label)

	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_interval(duration)
	tw.tween_property(panel, "modulate:a", 0.0, 0.3)
	tw.tween_callback(layer.queue_free)


# --- Navigation --------------------------------------------------------------

## Fade to black, swap scenes, fade back in. The overlay is parented to the
## SceneTree root (not the current scene) so it survives change_scene_to_file.
static func go_to_scene(from: Node, scene_path: String, duration: float = 0.16) -> bool:
	if not is_instance_valid(from) or not from.is_inside_tree():
		return false
	var tree := from.get_tree()
	if not ResourceLoader.exists(scene_path):
		push_warning("UITheme.go_to_scene: missing scene %s (not built yet?)" % scene_path)
		return false

	var layer := CanvasLayer.new()
	layer.layer = 128
	var fade := ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0.04, 0.02, 0.09, 0.0)
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(fade)
	tree.root.add_child(layer)

	var tw := fade.create_tween()
	tw.tween_property(fade, "color:a", 1.0, duration)
	tw.tween_callback(func() -> void: tree.change_scene_to_file(scene_path))
	tw.tween_interval(0.05)
	tw.tween_property(fade, "color:a", 0.0, duration)
	tw.tween_callback(layer.queue_free)
	return true
