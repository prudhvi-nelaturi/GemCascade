class_name GemData
extends RefCounted

## One board cell's contents. `null` in the grid array means "empty" (mid-cascade,
## before gravity/refill runs) — this class is only ever a populated cell.

var color: int
var special: int = GemTypes.Special.NONE

func _init(p_color: int, p_special: int = GemTypes.Special.NONE) -> void:
	color = p_color
	special = p_special

func is_special() -> bool:
	return special != GemTypes.Special.NONE

func duplicate_gem() -> GemData:
	return GemData.new(color, special)
