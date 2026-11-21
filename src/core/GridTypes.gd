class_name GridTypes
extends RefCounted

## Pure grid vocabulary for Sunshift: enums, direction tables and string lookups.
## Part of src/core/, so it is RefCounted and static only — no engine state.

enum TileType { VOID, FLOOR, WALL, WATER, PUDDLE, STAIRS, RAILING }
enum PropType { MIRROR, AWNING, SHUTTER, PRISM, STAINED_GLASS, LANTERN }
enum WishType { WARM_SUN, SOFT_SHADE, SHARED_BEAM, ROSE_LIGHT, LANTERN_GLOW }
enum LightType { NONE, DIRECT_SUN, BEAM_AMBER, BEAM_ROSE, LANTERN_GLOW }

const MAX_BOUNCES: int = 16
const MAX_RAY_STEPS: int = 64

## Diameter in cells of the lantern's glow (a 3x3 Chebyshev neighbourhood).
const LANTERN_RADIUS: int = 3

## SUN_DIRS[angle] is the direction light travels; the sun itself sits opposite.
## 0:E 1:NE 2:N 3:NW 4:W 5:SW 6:S 7:SE — counter-clockwise on screen (y down).
const SUN_DIRS: Array[Vector2i] = [
  Vector2i(1, 0),
  Vector2i(1, -1),
  Vector2i(0, -1),
  Vector2i(-1, -1),
  Vector2i(-1, 0),
  Vector2i(-1, 1),
  Vector2i(0, 1),
  Vector2i(1, 1),
]

const TILE_NAMES: Array[String] = ["void", "floor", "wall", "water", "puddle", "stairs", "railing"]
const PROP_NAMES: Array[String] = ["mirror", "awning", "shutter", "prism", "stained_glass", "lantern"]
const WISH_NAMES: Array[String] = ["warm_sun", "soft_shade", "shared_beam", "rose_light", "lantern_glow"]


static func sun_dir(angle: int) -> Vector2i:
  return SUN_DIRS[posmod(angle, SUN_DIRS.size())]


## Reflection maps: "/" (0) is E->N N->E W->S S->W, "\" (1) is E->S S->E W->N N->W.
## Diagonal beams reflect across the same 45-degree axes, which keeps every map
## reversible: applying it twice returns the original direction.
static func mirror_reflect(mirror_state: int, dir: Vector2i) -> Vector2i:
  match mirror_state:
    0:
      return Vector2i(-dir.y, -dir.x)
    1:
      return Vector2i(dir.y, dir.x)
    _:
      return dir


static func rotate90(dir: Vector2i, cw: bool) -> Vector2i:
  if cw:
    return Vector2i(-dir.y, dir.x)
  return Vector2i(dir.y, -dir.x)


static func tile_from_string(s: String) -> int:
  return TILE_NAMES.find(_normalise(s))


static func prop_from_string(s: String) -> int:
  return PROP_NAMES.find(_normalise(s))


static func wish_from_string(s: String) -> int:
  return WISH_NAMES.find(_normalise(s))


static func tile_name(t: int) -> String:
  if t < 0 or t >= TILE_NAMES.size():
    return "unknown"
  return TILE_NAMES[t]


static func prop_name(p: int) -> String:
  if p < 0 or p >= PROP_NAMES.size():
    return "unknown"
  return PROP_NAMES[p]


static func wish_name(w: int) -> String:
  if w < 0 or w >= WISH_NAMES.size():
    return "unknown"
  return WISH_NAMES[w]


static func tile_blocks_light(t: int) -> bool:
  return t == TileType.VOID or t == TileType.WALL


static func tile_walkable(t: int) -> bool:
  return t == TileType.FLOOR or t == TileType.WATER or t == TileType.PUDDLE or t == TileType.STAIRS


## Mirrors, awnings and shutters flip between two states; everything else is static.
static func prop_state_count(p: int) -> int:
  if p == PropType.MIRROR or p == PropType.AWNING or p == PropType.SHUTTER:
    return 2
  return 1


static func prop_blocks_light(p: int, state: int) -> bool:
  if p == PropType.AWNING:
    return state == 1
  if p == PropType.SHUTTER:
    return state == 0
  return false


static func _normalise(s: String) -> String:
  return s.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
