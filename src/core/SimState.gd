class_name SimState
extends RefCounted

## The only values that may change during a level. Everything else is level data.

var sun_angle: int = 0
var prop_states: Dictionary[String, int] = {}
var lantern_charge: Dictionary[String, int] = {}


static func initial(level: LevelData) -> SimState:
  var out: SimState = SimState.new()
  if level == null:
    return out
  out.sun_angle = level.initial_sun_angle
  for prop: LevelData.PropSpec in level.props:
    out.prop_states[prop.id] = prop.state
    if prop.type == GridTypes.PropType.LANTERN:
      out.lantern_charge[prop.id] = 0
  return out


static func copy_int_dict(src: Dictionary[String, int]) -> Dictionary[String, int]:
  var out: Dictionary[String, int] = {}
  for key: String in src:
    out[key] = src[key]
  return out


static func _join(src: Dictionary[String, int]) -> String:
  var ids: Array[String] = []
  for key: String in src:
    ids.append(key)
  ids.sort()
  var parts: PackedStringArray = PackedStringArray()
  for key: String in ids:
    parts.append("%s,%d" % [key, src[key]])
  return ";".join(parts)


func copy() -> SimState:
  var out: SimState = SimState.new()
  out.sun_angle = sun_angle
  out.prop_states = copy_int_dict(prop_states)
  out.lantern_charge = copy_int_dict(lantern_charge)
  return out


## Stable canonical key for the BFS: "sun|id,state;...|id,charge;..." with ids sorted,
## so dictionary insertion order can never change the search.
func key() -> String:
  return "%d|%s|%s" % [sun_angle, _join(prop_states), _join(lantern_charge)]
