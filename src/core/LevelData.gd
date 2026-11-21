class_name LevelData
extends RefCounted

## One courtyard, parsed from JSON (data/levels/*.json) into flat O(1) lookup tables.
## Pure data: no nodes, no globals, no randomness.

class TileSpec extends RefCounted:
  var x: int = 0
  var y: int = 0
  var type: int = GridTypes.TileType.FLOOR
  var elevation: int = 0


class PropSpec extends RefCounted:
  var id: String = ""
  var type: int = GridTypes.PropType.MIRROR
  var x: int = 0
  var y: int = 0
  var elevation: int = 0
  var state: int = 0


class WishSpec extends RefCounted:
  var id: String = ""
  var who: String = ""
  var x: int = 0
  var y: int = 0
  var elevation: int = 0
  var need: int = GridTypes.WishType.WARM_SUN
  var targets: Array[Vector2i] = []


var id: String = ""
var act: int = 1
var title: String = ""
var subtitle: String = ""
var postcard_caption: String = ""
var width: int = 0
var height: int = 0
var initial_sun_angle: int = 0
var player_spawn: Vector2i = Vector2i.ZERO
var tiles: Array[TileSpec] = []
var props: Array[PropSpec] = []
var wishes: Array[WishSpec] = []

var _tiles: Array[TileSpec] = []
var _props_at: Dictionary[Vector2i, PropSpec] = {}
var _props_by_id: Dictionary[String, PropSpec] = {}

const _INVALID_CELL: Vector2i = Vector2i(-999999, -999999)


## Returns null and prints one clear line on any schema violation.
static func from_dict(d: Dictionary, source: String) -> LevelData:
  var id_value: Variant = d.get("id", null)
  if not (id_value is String) or String(id_value).strip_edges().is_empty():
    return _reject(source, "missing or empty \"id\"")
  var level := LevelData.new()
  level.id = String(id_value)
  var act_value: Variant = d.get("act", null)
  if not _is_number(act_value):
    return _reject(source, "missing numeric \"act\"")
  level.act = int(act_value)
  level.title = _string_field(d, "title", "")
  level.subtitle = _string_field(d, "subtitle", "")
  level.postcard_caption = _string_field(d, "postcard_caption", "")
  var size_value: Variant = d.get("grid_size", null)
  if not (size_value is Array):
    return _reject(source, "missing \"grid_size\" as [width, height]")
  var size_arr: Array = size_value as Array
  if size_arr.size() != 2 or not _is_number(size_arr[0]) or not _is_number(size_arr[1]):
    return _reject(source, "\"grid_size\" must be [width, height]")
  level.width = int(size_arr[0])
  level.height = int(size_arr[1])
  if level.width < 1 or level.height < 1 or level.width > 64 or level.height > 64:
    return _reject(source, "\"grid_size\" must be between 1 and 64 cells per side")
  var sun_value: Variant = d.get("initial_sun_angle", null)
  if not _is_number(sun_value):
    return _reject(source, "missing numeric \"initial_sun_angle\"")
  if int(sun_value) < 0 or int(sun_value) > 7:
    return _reject(source, "\"initial_sun_angle\" must be 0..7")
  level.initial_sun_angle = int(sun_value)
  var spawn := _vec2(d.get("player_spawn", null))
  if spawn == _INVALID_CELL:
    return _reject(source, "\"player_spawn\" must be [x, y]")
  if not level.in_bounds(spawn.x, spawn.y):
    return _reject(source, "\"player_spawn\" (%d,%d) is out of bounds" % [spawn.x, spawn.y])
  level.player_spawn = spawn

  level._allocate_tiles()
  var tiles_value: Variant = d.get("tiles", [])
  if not (tiles_value is Array):
    return _reject(source, "\"tiles\" must be an array")
  for entry_value: Variant in (tiles_value as Array):
    if not (entry_value is Dictionary):
      return _reject(source, "every tiles[] entry must be an object")
    var entry: Dictionary = entry_value as Dictionary
    var tx_value: Variant = entry.get("x", null)
    var ty_value: Variant = entry.get("y", null)
    if not _is_number(tx_value) or not _is_number(ty_value):
      return _reject(source, "tile entry is missing numeric \"x\"/\"y\"")
    var tx: int = int(tx_value)
    var ty: int = int(ty_value)
    if not level.in_bounds(tx, ty):
      return _reject(source, "tile (%d,%d) is out of bounds" % [tx, ty])
    var type_value: Variant = entry.get("type", null)
    if not (type_value is String):
      return _reject(source, "tile (%d,%d) is missing string \"type\"" % [tx, ty])
    var type_id: int = GridTypes.tile_from_string(String(type_value))
    if type_id < 0:
      return _reject(source, "tile (%d,%d) has unknown type \"%s\"" % [tx, ty, String(type_value)])
    var elevation: int = 0
    var elev_value: Variant = entry.get("elevation", 0)
    if not _is_number(elev_value):
      return _reject(source, "tile (%d,%d) has non-numeric \"elevation\"" % [tx, ty])
    elevation = int(elev_value)
    if elevation < 0 or elevation > 2:
      return _reject(source, "tile (%d,%d) elevation must be 0..2" % [tx, ty])
    var tile: TileSpec = level._tiles[ty * level.width + tx]
    tile.type = type_id
    tile.elevation = elevation

  var props_value: Variant = d.get("props", [])
  if not (props_value is Array):
    return _reject(source, "\"props\" must be an array")
  for entry_value: Variant in (props_value as Array):
    if not (entry_value is Dictionary):
      return _reject(source, "every props[] entry must be an object")
    var entry: Dictionary = entry_value as Dictionary
    var prop_id_value: Variant = entry.get("id", null)
    if not (prop_id_value is String) or String(prop_id_value).strip_edges().is_empty():
      return _reject(source, "prop entry is missing string \"id\"")
    var prop := PropSpec.new()
    prop.id = String(prop_id_value)
    if level._props_by_id.has(prop.id):
      return _reject(source, "duplicate prop id \"%s\"" % prop.id)
    var prop_type_value: Variant = entry.get("type", null)
    if not (prop_type_value is String):
      return _reject(source, "prop \"%s\" is missing string \"type\"" % prop.id)
    prop.type = GridTypes.prop_from_string(String(prop_type_value))
    if prop.type < 0:
      return _reject(source, "prop \"%s\" has unknown type \"%s\"" % [prop.id, String(prop_type_value)])
    var px_value: Variant = entry.get("x", null)
    var py_value: Variant = entry.get("y", null)
    if not _is_number(px_value) or not _is_number(py_value):
      return _reject(source, "prop \"%s\" is missing numeric \"x\"/\"y\"" % prop.id)
    prop.x = int(px_value)
    prop.y = int(py_value)
    if not level.in_bounds(prop.x, prop.y):
      return _reject(source, "prop \"%s\" (%d,%d) is out of bounds" % [prop.id, prop.x, prop.y])
    var prop_elev_value: Variant = entry.get("elevation", 0)
    if not _is_number(prop_elev_value):
      return _reject(source, "prop \"%s\" has non-numeric \"elevation\"" % prop.id)
    prop.elevation = int(prop_elev_value)
    if prop.elevation < 0 or prop.elevation > 2:
      return _reject(source, "prop \"%s\" elevation must be 0..2" % prop.id)
    var prop_state_value: Variant = entry.get("state", 0)
    if not _is_number(prop_state_value):
      return _reject(source, "prop \"%s\" has non-numeric \"state\"" % prop.id)
    prop.state = int(prop_state_value)
    if prop.state < 0 or prop.state >= GridTypes.prop_state_count(prop.type):
      return _reject(source, "prop \"%s\" state %d is outside 0..%d" % [prop.id, prop.state, GridTypes.prop_state_count(prop.type) - 1])
    level.props.append(prop)
    level._props_by_id[prop.id] = prop
    level._props_at[Vector2i(prop.x, prop.y)] = prop

  var wishes_value: Variant = d.get("wishes", [])
  if not (wishes_value is Array):
    return _reject(source, "\"wishes\" must be an array")
  for entry_value: Variant in (wishes_value as Array):
    if not (entry_value is Dictionary):
      return _reject(source, "every wishes[] entry must be an object")
    var entry: Dictionary = entry_value as Dictionary
    var wish_id_value: Variant = entry.get("id", null)
    if not (wish_id_value is String) or String(wish_id_value).strip_edges().is_empty():
      return _reject(source, "wish entry is missing string \"id\"")
    var wish := WishSpec.new()
    wish.id = String(wish_id_value)
    for other: WishSpec in level.wishes:
      if other.id == wish.id:
        return _reject(source, "duplicate wish id \"%s\"" % wish.id)
    wish.who = _string_field(entry, "who", "neighbor")
    var wx_value: Variant = entry.get("x", null)
    var wy_value: Variant = entry.get("y", null)
    if not _is_number(wx_value) or not _is_number(wy_value):
      return _reject(source, "wish \"%s\" is missing numeric \"x\"/\"y\"" % wish.id)
    wish.x = int(wx_value)
    wish.y = int(wy_value)
    if not level.in_bounds(wish.x, wish.y):
      return _reject(source, "wish \"%s\" (%d,%d) is out of bounds" % [wish.id, wish.x, wish.y])
    var wish_elev_value: Variant = entry.get("elevation", 0)
    if not _is_number(wish_elev_value):
      return _reject(source, "wish \"%s\" has non-numeric \"elevation\"" % wish.id)
    wish.elevation = int(wish_elev_value)
    if wish.elevation < 0 or wish.elevation > 2:
      return _reject(source, "wish \"%s\" elevation must be 0..2" % wish.id)
    var need_value: Variant = entry.get("need", null)
    if not (need_value is String):
      return _reject(source, "wish \"%s\" is missing string \"need\"" % wish.id)
    wish.need = GridTypes.wish_from_string(String(need_value))
    if wish.need < 0:
      return _reject(source, "wish \"%s\" has unknown need \"%s\"" % [wish.id, String(need_value)])
    var targets_value: Variant = entry.get("targets", [])
    if not (targets_value is Array):
      return _reject(source, "wish \"%s\" has non-array \"targets\"" % wish.id)
    for target_value: Variant in (targets_value as Array):
      var target := _vec2(target_value)
      if target == _INVALID_CELL:
        return _reject(source, "wish \"%s\" has a malformed target" % wish.id)
      if not level.in_bounds(target.x, target.y):
        return _reject(source, "wish \"%s\" target (%d,%d) is out of bounds" % [wish.id, target.x, target.y])
      wish.targets.append(target)
    if wish.need == GridTypes.WishType.SHARED_BEAM and wish.targets.is_empty():
      return _reject(source, "wish \"%s\" needs \"targets\" for SHARED_BEAM" % wish.id)
    level.wishes.append(wish)

  return level


static func from_json(path: String) -> LevelData:
  if not FileAccess.file_exists(path):
    return _reject(path, "file not found")
  var file: FileAccess = FileAccess.open(path, FileAccess.READ)
  if file == null:
    return _reject(path, "cannot be opened for reading")
  var text: String = file.get_as_text()
  file.close()
  var parsed: Variant = JSON.parse_string(text)
  if not (parsed is Dictionary):
    return _reject(path, "top level is not a JSON object")
  return from_dict(parsed as Dictionary, path)


func in_bounds(x: int, y: int) -> bool:
  return x >= 0 and y >= 0 and x < width and y < height


func tile_at(x: int, y: int) -> TileSpec:
  if not in_bounds(x, y):
    return null
  return _tiles[y * width + x]


func prop_at(x: int, y: int) -> PropSpec:
  return _props_at.get(Vector2i(x, y), null)


func prop_by_id(prop_id: String) -> PropSpec:
  return _props_by_id.get(prop_id, null)


func height_at(x: int, y: int) -> int:
  if not in_bounds(x, y):
    return 0
  return _tiles[y * width + x].elevation


## State of a prop in this simulation state, falling back to the level's initial state.
func prop_state(prop: PropSpec, state: SimState) -> int:
  if prop == null:
    return 0
  if state == null:
    return prop.state
  var value: int = state.prop_states.get(prop.id, prop.state)
  return value


func blocks_light_at(x: int, y: int, state: SimState) -> bool:
  if not in_bounds(x, y):
    return true
  var tile: TileSpec = _tiles[y * width + x]
  if GridTypes.tile_blocks_light(tile.type):
    return true
  var prop: PropSpec = prop_at(x, y)
  if prop == null:
    return false
  return GridTypes.prop_blocks_light(prop.type, prop_state(prop, state))


func is_walkable(x: int, y: int, state: SimState) -> bool:
  if not in_bounds(x, y):
    return false
  var tile: TileSpec = _tiles[y * width + x]
  if not GridTypes.tile_walkable(tile.type):
    return false
  var prop: PropSpec = prop_at(x, y)
  if prop == null:
    return true
  return prop.type == GridTypes.PropType.AWNING


func _allocate_tiles() -> void:
  _tiles.clear()
  _tiles.resize(width * height)
  for y: int in height:
    for x: int in width:
      var tile := TileSpec.new()
      tile.x = x
      tile.y = y
      tile.type = GridTypes.TileType.FLOOR
      tile.elevation = 0
      _tiles[y * width + x] = tile


static func _reject(source: String, message: String) -> LevelData:
  print("[LevelData] %s: %s" % [source, message])
  return null


static func _is_number(value: Variant) -> bool:
  return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _string_field(d: Dictionary, key: String, fallback: String) -> String:
  var value: Variant = d.get(key, fallback)
  if value is String:
    return String(value)
  return fallback


static func _vec2(value: Variant) -> Vector2i:
  if not (value is Array):
    return _INVALID_CELL
  var arr: Array = value as Array
  if arr.size() != 2 or not _is_number(arr[0]) or not _is_number(arr[1]):
    return _INVALID_CELL
  return Vector2i(int(arr[0]), int(arr[1]))
