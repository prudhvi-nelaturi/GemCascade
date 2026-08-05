class_name GemTypes
extends RefCounted

## Shared constants for gem colors and special-gem kinds. No instances of this
## class are ever created — it's just a namespace for the enums other board
## scripts reference (GDScript has no static-only class, so RefCounted + consts).

enum GemColor { RUBY, SAPPHIRE, EMERALD, TOPAZ, AMETHYST, DIAMOND }
const COLOR_COUNT := 6

enum Special { NONE, STRIPED_H, STRIPED_V, WRAPPED, COLOR_BOMB }
