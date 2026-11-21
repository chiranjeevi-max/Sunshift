class_name CommandHistory
extends RefCounted

## Undo stack for the two player actions: sun shifts and prop interactions.
## Each command also snapshots lantern charge, because charge is part of the state
## that solve() reads back on the next turn.

enum Kind { SUN, PROP }


class Command extends RefCounted:
  var kind: int = Kind.SUN
  var key: String = ""
  var from_value: int = 0
  var to_value: int = 0
  var charge_before: Dictionary[String, int] = {}


var _commands: Array[Command] = []


func reset() -> void:
  _commands.clear()


func record_sun(from_angle: int, to_angle: int, charge_before: Dictionary[String, int]) -> void:
  var cmd := Command.new()
  cmd.kind = Kind.SUN
  cmd.from_value = from_angle
  cmd.to_value = to_angle
  cmd.charge_before = SimState.copy_int_dict(charge_before)
  _commands.append(cmd)


func record_prop(prop_id: String, from_state: int, to_state: int, charge_before: Dictionary[String, int]) -> void:
  var cmd := Command.new()
  cmd.kind = Kind.PROP
  cmd.key = prop_id
  cmd.from_value = from_state
  cmd.to_value = to_state
  cmd.charge_before = SimState.copy_int_dict(charge_before)
  _commands.append(cmd)


func can_undo() -> bool:
  return not _commands.is_empty()


func size() -> int:
  return _commands.size()


## Restores the previous state and pops the command. Returns false when empty.
func undo(state: SimState) -> bool:
  if state == null or _commands.is_empty():
    return false
  var cmd: Command = _commands.pop_back()
  if cmd.kind == Kind.SUN:
    state.sun_angle = posmod(cmd.from_value, 8)
  else:
    state.prop_states[cmd.key] = cmd.from_value
  state.lantern_charge = SimState.copy_int_dict(cmd.charge_before)
  return true
