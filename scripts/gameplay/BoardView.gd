class_name BoardView
extends Node2D

## Renders a Board and turns its step events into animation. Holds no rules:
## every question about legality, matching or refill colours is answered by the
## Board instance GameplayController hands it in setup().
##
## The view keeps its own mirror of the grid (`_views[r][c]` -> GemView) so it
## can animate the transition between two board states instead of snapping to
## the new one. The mirror is kept honest two ways: gravity is applied to it
## with the exact same column-compaction rule Board uses, and every phase ends
## with a reconcile pass against the Board that silently repairs any drift.
##
## Coordinates follow Board's convention throughout: Vector2i(row, column).

signal swap_requested(a: Vector2i, b: Vector2i)
signal cell_tapped(cell: Vector2i)

const NO_CELL := Vector2i(-1, -1)

const H_MARGIN := 26.0
const BOARD_TOP := 296.0
const BOARD_BOTTOM := 1012.0

# Animation timings. Tuned so a full cascade tier reads as clear -> fall ->
# pop rather than one mushy blur, while staying short enough that a long chain
# never feels like it has taken control away from the player.
const SWAP_TIME := 0.15
const REJECT_TIME := 0.20
const CLEAR_ANTICIPATE := 0.07
const CLEAR_VANISH := 0.14
const CASCADE_DELAY_STEP := 0.035
const CASCADE_DELAY_MAX := 0.16
const FALL_BASE := 0.17
const FALL_PER_CELL := 0.028
const FALL_MAX := 0.44
const COLUMN_STAGGER := 0.012
const POP_TIME := 0.26

const PARTICLE_POOL_SIZE := 48

var cell_size: float = 84.0
var board_origin: Vector2 = Vector2.ZERO

var _board: Board
var _rows: int = 0
var _cols: int = 0
var _views: Array = [] # Array[Array[GemView]]

var _input_enabled: bool = false
var _hammer_mode: bool = false
var _pointer_is_down: bool = false
var _press_cell: Vector2i = NO_CELL
var _press_pos: Vector2 = Vector2.ZERO
var _gesture_consumed: bool = false
var _selected: Vector2i = NO_CELL

var _selector: Sprite2D
var _gem_layer: Node2D
var _blocker_layer: Node2D
var _fx_layer: Node2D
var _blocker_nodes: Dictionary = {} # Vector2i -> Sprite2D
var _particles: Array = []
var _particle_index: int = 0

# ---------------------------------------------------------------------------
# Setup / layout
# ---------------------------------------------------------------------------

func _ready() -> void:
	if _gem_layer == null:
		_build_layers()

func _build_layers() -> void:
	_gem_layer = Node2D.new()
	_gem_layer.name = "Gems"
	add_child(_gem_layer)

	_blocker_layer = Node2D.new()
	_blocker_layer.name = "Blockers"
	_blocker_layer.z_index = 2
	add_child(_blocker_layer)

	_fx_layer = Node2D.new()
	_fx_layer.name = "Fx"
	_fx_layer.z_index = 6
	add_child(_fx_layer)

	_selector = Sprite2D.new()
	_selector.name = "Selector"
	_selector.texture = GemArt.wrapped_overlay()
	_selector.modulate = Color(1, 1, 1, 0.0)
	_selector.z_index = 3
	add_child(_selector)

## Binds this view to a board and builds a sprite for every cell. Safe to call
## again (rebuilds from scratch) if the level is restarted.
func setup(board: Board) -> void:
	if _gem_layer == null:
		_build_layers()
	_board = board
	_rows = board.rows
	_cols = board.cols
	_compute_layout()
	_build_particle_pool()
	_clear_all_views()
	_views = []
	for r in range(_rows):
		var row: Array = []
		row.resize(_cols)
		_views.append(row)
	for r in range(_rows):
		for c in range(_cols):
			var gem: GemData = _board.get_gem(r, c)
			if gem == null:
				continue
			_views[r][c] = _make_gem_view(Vector2i(r, c), gem.color, gem.special)
	_selected = NO_CELL
	_update_selector()

func _compute_layout() -> void:
	var viewport_width: float = 720.0
	var vp := get_viewport()
	if vp != null:
		viewport_width = vp.get_visible_rect().size.x
	var usable_width: float = viewport_width - H_MARGIN * 2.0
	var usable_height: float = BOARD_BOTTOM - BOARD_TOP
	cell_size = minf(usable_width / float(maxi(1, _cols)), usable_height / float(maxi(1, _rows)))
	var board_width: float = cell_size * _cols
	var board_height: float = cell_size * _rows
	board_origin = Vector2(
		(viewport_width - board_width) * 0.5,
		BOARD_TOP + (usable_height - board_height) * 0.5
	)

func board_rect() -> Rect2:
	return Rect2(board_origin, Vector2(cell_size * _cols, cell_size * _rows))

func cell_center(cell: Vector2i) -> Vector2:
	return board_origin + Vector2((cell.y + 0.5) * cell_size, (cell.x + 0.5) * cell_size)

func _cell_at(local_pos: Vector2) -> Vector2i:
	var rel: Vector2 = local_pos - board_origin
	if rel.x < 0.0 or rel.y < 0.0:
		return NO_CELL
	var c := int(rel.x / cell_size)
	var r := int(rel.y / cell_size)
	if r < 0 or r >= _rows or c < 0 or c >= _cols:
		return NO_CELL
	return Vector2i(r, c)

func _make_gem_view(cell: Vector2i, color: int, special: int) -> GemView:
	var gv := GemView.new()
	_gem_layer.add_child(gv)
	gv.set_cell_size(cell_size)
	gv.set_gem(color, special)
	gv.position = cell_center(cell)
	return gv

func _clear_all_views() -> void:
	if _gem_layer == null:
		return
	for child in _gem_layer.get_children():
		child.queue_free()

func _gem_at(cell: Vector2i) -> GemView:
	if cell.x < 0 or cell.x >= _rows or cell.y < 0 or cell.y >= _cols:
		return null
	return _views[cell.x][cell.y]

# ---------------------------------------------------------------------------
# Input — drag-to-swap and tap-tap-to-swap both work, so the same build feels
# right under a thumb and under a mouse without a control-scheme setting.
# ---------------------------------------------------------------------------

func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		_pointer_is_down = false
		_press_cell = NO_CELL
		_gesture_consumed = false

func set_hammer_mode(enabled: bool) -> void:
	_hammer_mode = enabled
	_selected = NO_CELL
	_update_selector()

func clear_selection() -> void:
	_selected = NO_CELL
	_update_selector()

func _unhandled_input(event: InputEvent) -> void:
	if not _input_enabled:
		return
	# Touch and mouse are funnelled into the same three handlers. Godot emulates
	# mouse from touch by default, so both can arrive for one physical press —
	# the `_pointer_is_down` latch makes the duplicate a no-op.
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_pointer_down(_to_local_point(t.position))
		else:
			_pointer_up(_to_local_point(t.position))
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_pointer_move(_to_local_point(d.position))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_pointer_down(_to_local_point(mb.position))
		else:
			_pointer_up(_to_local_point(mb.position))
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_pointer_move(_to_local_point(mm.position))

func _to_local_point(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos

func _pointer_down(local_pos: Vector2) -> void:
	if _pointer_is_down:
		return
	_pointer_is_down = true
	_gesture_consumed = false
	_press_pos = local_pos
	_press_cell = _cell_at(local_pos)

func _pointer_move(local_pos: Vector2) -> void:
	if not _pointer_is_down or _gesture_consumed or _press_cell == NO_CELL:
		return
	if _hammer_mode:
		return
	var delta: Vector2 = local_pos - _press_pos
	if delta.length() < cell_size * 0.35:
		return
	# Snap the drag to the dominant axis: a diagonal flick should still produce
	# a definite, predictable swap rather than nothing.
	var dir := Vector2i.ZERO
	if absf(delta.x) > absf(delta.y):
		dir = Vector2i(0, 1) if delta.x > 0.0 else Vector2i(0, -1)
	else:
		dir = Vector2i(1, 0) if delta.y > 0.0 else Vector2i(-1, 0)
	var target: Vector2i = _press_cell + dir
	if target.x < 0 or target.x >= _rows or target.y < 0 or target.y >= _cols:
		return
	_gesture_consumed = true
	_selected = NO_CELL
	_update_selector()
	swap_requested.emit(_press_cell, target)

func _pointer_up(local_pos: Vector2) -> void:
	if not _pointer_is_down:
		return
	_pointer_is_down = false
	if _gesture_consumed:
		_gesture_consumed = false
		return
	var cell: Vector2i = _cell_at(local_pos)
	if cell == NO_CELL or cell != _press_cell:
		return

	if _hammer_mode:
		cell_tapped.emit(cell)
		return

	if _selected == NO_CELL:
		_selected = cell
		_update_selector()
		return
	if _selected == cell:
		_selected = NO_CELL
		_update_selector()
		return
	var diff: Vector2i = _selected - cell
	if absi(diff.x) + absi(diff.y) == 1:
		var from: Vector2i = _selected
		_selected = NO_CELL
		_update_selector()
		swap_requested.emit(from, cell)
	else:
		_selected = cell
		_update_selector()

func _update_selector() -> void:
	if _selector == null:
		return
	if _selector.has_meta("pulse"):
		var existing: Variant = _selector.get_meta("pulse")
		if existing is Tween and (existing as Tween).is_valid():
			(existing as Tween).kill()
	if _selected == NO_CELL:
		_selector.modulate.a = 0.0
		return
	var tex := _selector.texture
	if tex != null:
		var s: float = (cell_size * 1.02) / maxf(1.0, float(tex.get_width()))
		_selector.scale = Vector2(s, s)
	_selector.position = cell_center(_selected)
	_selector.modulate = Color(1, 1, 1, 0.9)
	var pulse := create_tween().set_loops()
	pulse.tween_property(_selector, "scale", _selector.scale * 1.12, 0.35).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_selector, "scale", _selector.scale, 0.35).set_trans(Tween.TRANS_SINE)
	_selector.set_meta("pulse", pulse)

# ---------------------------------------------------------------------------
# Swap animations
# ---------------------------------------------------------------------------

## Plays an accepted swap. The Board has already been mutated by try_swap(), so
## this also swaps the view mirror to match.
func animate_swap(a: Vector2i, b: Vector2i) -> void:
	var gv_a: GemView = _gem_at(a)
	var gv_b: GemView = _gem_at(b)
	_views[a.x][a.y] = gv_b
	_views[b.x][b.y] = gv_a
	var tween := create_tween().set_parallel(true)
	if gv_a != null:
		gv_a.z_index = 1
		tween.tween_property(gv_a, "position", cell_center(b), SWAP_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if gv_b != null:
		tween.tween_property(gv_b, "position", cell_center(a), SWAP_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished
	if gv_a != null and is_instance_valid(gv_a):
		gv_a.z_index = 0

## Plays a rejected swap: the gems lunge at each other and snap back with a
## small overshoot, so an illegal move feels refused rather than dropped.
func animate_reject(a: Vector2i, b: Vector2i) -> void:
	var gv_a: GemView = _gem_at(a)
	var gv_b: GemView = _gem_at(b)
	var home_a: Vector2 = cell_center(a)
	var home_b: Vector2 = cell_center(b)
	var nudge: Vector2 = (home_b - home_a) * 0.32

	var tween := create_tween().set_parallel(true)
	if gv_a != null:
		gv_a.z_index = 1
		tween.tween_property(gv_a, "position", home_a + nudge, REJECT_TIME * 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if gv_b != null:
		tween.tween_property(gv_b, "position", home_b - nudge, REJECT_TIME * 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished

	var back := create_tween().set_parallel(true)
	if gv_a != null and is_instance_valid(gv_a):
		back.tween_property(gv_a, "position", home_a, REJECT_TIME * 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		back.tween_property(gv_a, "rotation", 0.0, REJECT_TIME * 0.55).from(0.18)
	if gv_b != null and is_instance_valid(gv_b):
		back.tween_property(gv_b, "position", home_b, REJECT_TIME * 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		back.tween_property(gv_b, "rotation", 0.0, REJECT_TIME * 0.55).from(-0.18)
	await back.finished
	if gv_a != null and is_instance_valid(gv_a):
		gv_a.z_index = 0

# ---------------------------------------------------------------------------
# Cascade step animations
# ---------------------------------------------------------------------------

## Phase 1 of a step: clear the matched cells and morph the cells that became
## special gems. Must be called after Board._process_groups() and *before*
## gravity, so the view still mirrors the pre-gravity grid.
func animate_clear_phase(step: Dictionary) -> void:
	var cleared: Array = step.get("cleared", [])
	var specials: Array = step.get("specials_created", [])
	var cascade_index: int = int(step.get("cascade_index", 0))
	var stagger: float = minf(cascade_index * CASCADE_DELAY_STEP, CASCADE_DELAY_MAX)

	var special_at := {}
	for s in specials:
		special_at[s["pos"]] = s

	for cell in cleared:
		if special_at.has(cell):
			continue
		var gv: GemView = _gem_at(cell)
		if gv == null:
			continue
		_views[cell.x][cell.y] = null
		_animate_vanish(gv, stagger, gv.tint_color())

	for pos in special_at.keys():
		var info: Dictionary = special_at[pos]
		var gv2: GemView = _gem_at(pos)
		if gv2 == null:
			gv2 = _make_gem_view(pos, int(info["color"]), int(info["type"]))
			_views[pos.x][pos.y] = gv2
		else:
			gv2.set_gem(int(info["color"]), int(info["type"]))
		_animate_special_birth(gv2, stagger)

	await _wait(stagger + CLEAR_ANTICIPATE + CLEAR_VANISH)

func _animate_vanish(gv: GemView, delay: float, tint: Color) -> void:
	gv.z_index = 4
	var tween := gv.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	# Anticipation beat before the pop: the gem swells, then snaps out of
	# existence as the particles fire.
	tween.tween_property(gv, "scale", Vector2(1.28, 1.28), CLEAR_ANTICIPATE) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_burst.bind(gv.position, tint))
	tween.set_parallel(true)
	tween.tween_property(gv, "scale", Vector2(0.05, 0.05), CLEAR_VANISH) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(gv, "modulate:a", 0.0, CLEAR_VANISH)
	tween.tween_property(gv, "rotation", randf_range(-1.2, 1.2), CLEAR_VANISH)
	tween.chain().tween_callback(gv.queue_free)

func _animate_special_birth(gv: GemView, delay: float) -> void:
	gv.z_index = 3
	gv.scale = Vector2(0.2, 0.2)
	var tween := gv.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(gv, "scale", Vector2(1.45, 1.45), POP_TIME * 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(gv, "scale", Vector2.ONE, POP_TIME * 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		if is_instance_valid(gv):
			gv.z_index = 0)

## Phase 2 of a step: gravity. Must be called after Board's gravity+refill has
## run, because the colours of the incoming gems are read straight off the
## board. The compaction rule here mirrors Board._apply_gravity_and_refill()
## exactly (per column, bottom-up, stable), so the mirror lands in the same
## arrangement the board already committed to.
func animate_gravity_phase() -> void:
	var longest: float = 0.0
	for c in range(_cols):
		var write_row: int = _rows - 1
		var column_delay: float = c * COLUMN_STAGGER
		for r in range(_rows - 1, -1, -1):
			var gv: GemView = _views[r][c]
			if gv == null:
				continue
			if write_row != r:
				_views[write_row][c] = gv
				_views[r][c] = null
				longest = maxf(longest, _animate_fall(gv, Vector2i(write_row, c), write_row - r, column_delay))
			write_row -= 1
		# Everything at or above write_row is a hole to be refilled from off-screen.
		var spawn_slot: int = 1
		for r2 in range(write_row, -1, -1):
			var gem: GemData = _board.get_gem(r2, c)
			if gem == null:
				continue
			var gv2: GemView = _make_gem_view(Vector2i(r2, c), gem.color, gem.special)
			gv2.position = cell_center(Vector2i(-spawn_slot, c))
			_views[r2][c] = gv2
			longest = maxf(longest, _animate_fall(gv2, Vector2i(r2, c), r2 + spawn_slot, column_delay))
			spawn_slot += 1

	await _wait(longest)
	_reconcile_with_board()

func _animate_fall(gv: GemView, target_cell: Vector2i, distance: int, delay: float) -> float:
	var travel: float = minf(FALL_BASE + FALL_PER_CELL * float(maxi(1, distance)), FALL_MAX)
	var tween := gv.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	# Accelerating fall, then a short squash-and-recover on landing so gems
	# arrive with weight instead of stopping dead.
	tween.tween_property(gv, "position", cell_center(target_cell), travel) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(gv, "scale", Vector2(1.16, 0.84), 0.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(gv, "scale", Vector2.ONE, 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return delay + travel + 0.16

## Repairs any divergence between the mirror and the board. Nothing should ever
## be found here — it exists so a mismatch degrades into a silently corrected
## frame rather than a board the player can no longer read.
func _reconcile_with_board() -> void:
	if _board == null:
		return
	for r in range(_rows):
		for c in range(_cols):
			var gem: GemData = _board.get_gem(r, c)
			var gv: GemView = _views[r][c]
			if gem == null:
				if gv != null:
					gv.queue_free()
					_views[r][c] = null
				continue
			if gv == null:
				_views[r][c] = _make_gem_view(Vector2i(r, c), gem.color, gem.special)
				continue
			if not gv.matches(gem.color, gem.special):
				gv.set_gem(gem.color, gem.special)
			gv.position = cell_center(Vector2i(r, c))

## Snaps every cell to the board with no animation (used after a shuffle).
func refresh_all_from_board() -> void:
	_clear_all_views()
	for r in range(_rows):
		for c in range(_cols):
			_views[r][c] = null
	for r in range(_rows):
		for c in range(_cols):
			var gem: GemData = _board.get_gem(r, c)
			if gem != null:
				_views[r][c] = _make_gem_view(Vector2i(r, c), gem.color, gem.special)

## Re-reads one cell, optionally with a pop (used when a booster injects a gem).
func refresh_cell(cell: Vector2i, pop: bool = false) -> void:
	var gem: GemData = _board.get_gem(cell.x, cell.y)
	if gem == null:
		return
	var gv: GemView = _gem_at(cell)
	if gv == null:
		gv = _make_gem_view(cell, gem.color, gem.special)
		_views[cell.x][cell.y] = gv
	else:
		gv.set_gem(gem.color, gem.special)
	if pop:
		_animate_special_birth(gv, 0.0)

# ---------------------------------------------------------------------------
# Shuffle
# ---------------------------------------------------------------------------

func animate_board_out() -> void:
	var tween := create_tween().set_parallel(true)
	for r in range(_rows):
		for c in range(_cols):
			var gv: GemView = _views[r][c]
			if gv == null:
				continue
			tween.tween_property(gv, "scale", Vector2(0.1, 0.1), 0.22) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tween.tween_property(gv, "rotation", randf_range(-2.0, 2.0), 0.22)
	await tween.finished

func animate_board_in() -> void:
	var tween := create_tween().set_parallel(true)
	for r in range(_rows):
		for c in range(_cols):
			var gv: GemView = _views[r][c]
			if gv == null:
				continue
			gv.scale = Vector2(0.1, 0.1)
			var delay: float = (r + c) * 0.014
			tween.tween_property(gv, "scale", Vector2.ONE, 0.28) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
	await tween.finished

# ---------------------------------------------------------------------------
# Blockers
# ---------------------------------------------------------------------------

func set_blockers(cells: Array) -> void:
	for node in _blocker_nodes.values():
		node.queue_free()
	_blocker_nodes.clear()
	for cell in cells:
		if cell.x < 0 or cell.x >= _rows or cell.y < 0 or cell.y >= _cols:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = GemArt.blocker_texture()
		var tex_w: float = maxf(1.0, float(sprite.texture.get_width()))
		var s: float = (cell_size * 0.98) / tex_w
		sprite.scale = Vector2(s, s)
		sprite.position = cell_center(cell)
		_blocker_layer.add_child(sprite)
		_blocker_nodes[cell] = sprite

func break_blockers(cells: Array) -> void:
	for cell in cells:
		if not _blocker_nodes.has(cell):
			continue
		var sprite: Sprite2D = _blocker_nodes[cell]
		_blocker_nodes.erase(cell)
		_burst(sprite.position, Color(0.75, 0.72, 0.88))
		var tween := sprite.create_tween().set_parallel(true)
		tween.tween_property(sprite, "scale", sprite.scale * 1.4, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "modulate:a", 0.0, 0.18)
		tween.tween_property(sprite, "rotation", randf_range(-0.5, 0.5), 0.18)
		tween.chain().tween_callback(sprite.queue_free)

# ---------------------------------------------------------------------------
# Particles
# ---------------------------------------------------------------------------

func _build_particle_pool() -> void:
	if not _particles.is_empty():
		return
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, -1, 0)
	material.spread = 180.0
	material.initial_velocity_min = 90.0
	material.initial_velocity_max = 300.0
	material.gravity = Vector3(0, 620, 0)
	material.damping_min = 20.0
	material.damping_max = 60.0
	material.scale_min = 0.35
	material.scale_max = 1.0
	material.angle_min = -180.0
	material.angle_max = 180.0
	material.angular_velocity_min = -220.0
	material.angular_velocity_max = 220.0

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	material.color_ramp = ramp

	var spark := GemArt.spark_texture()
	for i in range(PARTICLE_POOL_SIZE):
		var p := GPUParticles2D.new()
		p.process_material = material
		p.texture = spark
		p.amount = 14
		p.lifetime = 0.55
		p.one_shot = true
		p.explosiveness = 1.0
		p.local_coords = false
		p.emitting = false
		_fx_layer.add_child(p)
		_particles.append(p)

## Fires one pooled burst tinted to the gem that was destroyed. The pool wraps
## around rather than growing: an in-flight burst being recycled during an
## enormous cascade is invisible next to the new one firing in its place.
func _burst(pos: Vector2, tint: Color) -> void:
	if _particles.is_empty():
		return
	var p: GPUParticles2D = _particles[_particle_index]
	_particle_index = (_particle_index + 1) % _particles.size()
	p.position = pos
	p.modulate = Color(tint.r, tint.g, tint.b, 1.0)
	p.emitting = false
	p.restart()

# ---------------------------------------------------------------------------

func _wait(seconds: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(maxf(0.01, seconds)).timeout
