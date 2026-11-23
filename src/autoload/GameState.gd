extends Node

## Autoload: owns the live level, the live SimState and the undo stack, and is the
## only place that mutates either. Every player action goes through here so the
## lantern charge commit and the history snapshot can never drift apart.

const LEVEL_DIR: String = "res://data/levels"

## Bootstrap only: used when res://data/levels cannot be scanned (export filters).
const BOOTSTRAP_LEVEL_IDS: Array[String] = ["A1-01", "A1-02", "A4-19"]

var current_level: LevelData = null
var current_state: SimState = null
var history: CommandHistory = CommandHistory.new()
var completed: Dictionary[String, bool] = {}
var unlocked_postcards: Array[String] = []
var current_act: int = 0
var level_ids: Array[String] = []

var _last_result: LightSolver.SolveResult = null
var _was_solved: bool = false


func _ready() -> void:
  level_ids = _scan_level_ids()
  _adopt_save()


func has_level() -> bool:
  return current_level != null and current_state != null


func is_completed(level_id: String) -> bool:
  return completed.get(level_id, false)


func load_level(level_id: String) -> void:
  var path: String = "%s/%s.json" % [LEVEL_DIR, level_id]
  var level: LevelData = LevelData.from_json(path)
  if level == null:
    push_error("GameState.load_level: cannot load %s" % path)
    return
  current_level = level
  current_state = SimState.initial(level)
  history.reset()
  current_act = level.act
  _was_solved = false
  EventBus.level_loaded.emit(level.id, level.act)
  evaluate()


func shift_sun(delta: int) -> void:
  if current_level == null or current_state == null:
    return
  var from_angle: int = current_state.sun_angle
  var to_angle: int = posmod(from_angle + delta, 8)
  if to_angle == from_angle:
    return
  var charge_before: Dictionary[String, int] = SimState.copy_int_dict(current_state.lantern_charge)
  var previous: LightSolver.SolveResult = _last_result
  if previous == null:
    previous = LightSolver.solve(current_level, current_state)
  history.record_sun(from_angle, to_angle, charge_before)
  current_state.sun_angle = to_angle
  commit_lantern_charge(previous)
  EventBus.sun_shifted.emit(to_angle)
  _emit_lantern_changes(charge_before)
  EventBus.audio_cue.emit("sun_shift", 1.0)
  evaluate()


func interact_prop(prop_id: String) -> void:
  if current_level == null or current_state == null:
    return
  var prop: LevelData.PropSpec = current_level.prop_by_id(prop_id)
  if prop == null:
    return
  var state_count: int = GridTypes.prop_state_count(prop.type)
  if state_count < 2:
    EventBus.audio_cue.emit("prop_static", 1.0)
    return
  var from_state: int = current_state.prop_states.get(prop.id, prop.state)
  var to_state: int = posmod(from_state + 1, state_count)
  var charge_before: Dictionary[String, int] = SimState.copy_int_dict(current_state.lantern_charge)
  var previous: LightSolver.SolveResult = _last_result
  if previous == null:
    previous = LightSolver.solve(current_level, current_state)
  history.record_prop(prop.id, from_state, to_state, charge_before)
  current_state.prop_states[prop.id] = to_state
  commit_lantern_charge(previous)
  EventBus.prop_shifted.emit(prop.id, to_state)
  _emit_lantern_changes(charge_before)
  EventBus.audio_cue.emit("prop_shift", 1.0)
  evaluate()


func undo() -> void:
  if current_level == null or current_state == null:
    return
  if not history.can_undo():
    EventBus.audio_cue.emit("undo_empty", 1.0)
    return
  var angle_before: int = current_state.sun_angle
  var charge_before: Dictionary[String, int] = SimState.copy_int_dict(current_state.lantern_charge)
  var props_before: Dictionary[String, int] = SimState.copy_int_dict(current_state.prop_states)
  if not history.undo(current_state):
    return
  EventBus.undo_performed.emit()
  if current_state.sun_angle != angle_before:
    EventBus.sun_shifted.emit(current_state.sun_angle)
  for prop: LevelData.PropSpec in current_level.props:
    var was: int = props_before.get(prop.id, prop.state)
    var now: int = current_state.prop_states.get(prop.id, prop.state)
    if was != now:
      EventBus.prop_shifted.emit(prop.id, now)
  _emit_lantern_changes(charge_before)
  EventBus.audio_cue.emit("undo", 1.0)
  evaluate()


func reset_level() -> void:
  if current_level == null:
    return
  current_state = SimState.initial(current_level)
  history.reset()
  _was_solved = false
  EventBus.level_reset.emit(current_level.id)
  evaluate()


## Writes the charge a solve computed for "the next turn" into the live state.
## solve() is a pure read, so the caller owns this step.
func commit_lantern_charge(result: LightSolver.SolveResult) -> void:
  if current_state == null or result == null:
    return
  for lantern_id: String in result.next_lantern_charge:
    current_state.lantern_charge[lantern_id] = result.next_lantern_charge[lantern_id]


func last_result() -> LightSolver.SolveResult:
  return _last_result


func evaluate() -> LightSolver.SolveResult:
  if current_level == null or current_state == null:
    _last_result = LightSolver.SolveResult.new()
    return _last_result
  var result: LightSolver.SolveResult = LightSolver.solve(current_level, current_state)
  _last_result = result
  EventBus.board_evaluated.emit(result.warmth_factor, result.satisfied_count, result.total_wishes)
  EventBus.warmth_changed.emit(result.warmth_factor)
  if result.solved and not _was_solved:
    _on_solved()
  _was_solved = result.solved
  return result


## Completion and postcards live in the save file. Pull them in once at boot so
## a returning player sees the promenade lit and the journal filled.
func _adopt_save() -> void:
  var save: Node = get_node_or_null("/root/SaveManager")
  if save == null:
    return
  var saved_completed: Variant = save.get("completed_levels")
  if saved_completed is Dictionary:
    for level_id: Variant in (saved_completed as Dictionary).keys():
      completed[str(level_id)] = true
  var saved_cards: Variant = save.get("unlocked_postcards")
  if saved_cards is Array:
    for card: Variant in saved_cards as Array:
      var id: String = str(card)
      if not id.is_empty() and not unlocked_postcards.has(id):
        unlocked_postcards.append(id)


func _on_solved() -> void:
  if current_level == null:
    return
  var level_id: String = current_level.id
  completed[level_id] = true
  EventBus.level_solved.emit(level_id, current_level.act)
  # A solved courtyard stamps its postcard. Without this the journal would stay
  # sealed forever, because nothing else ever unlocks one.
  if not unlocked_postcards.has(level_id):
    unlocked_postcards.append(level_id)
  var save: Node = get_node_or_null("/root/SaveManager")
  if save != null:
    if save.has_method("mark_completed"):
      save.call("mark_completed", level_id)
    if save.has_method("unlock_postcard"):
      save.call("unlock_postcard", level_id)


func _emit_lantern_changes(before: Dictionary[String, int]) -> void:
  if current_state == null:
    return
  var ids: Array[String] = []
  for lantern_id: String in current_state.lantern_charge:
    ids.append(lantern_id)
  ids.sort()
  for lantern_id: String in ids:
    var now: int = current_state.lantern_charge[lantern_id]
    var was: int = before.get(lantern_id, 0)
    if now != was:
      EventBus.lantern_charge_changed.emit(lantern_id, now)


func _scan_level_ids() -> Array[String]:
  var ids: Array[String] = []
  var dir: DirAccess = DirAccess.open(LEVEL_DIR)
  if dir != null:
    for file: String in dir.get_files():
      if file.get_extension().to_lower() != "json":
        continue
      ids.append(file.get_basename())
  # "A<act>-<nn>" sorts into act order lexicographically.
  ids.sort()
  if ids.is_empty():
    push_warning("GameState: no level files under %s, falling back to bootstrap ids" % LEVEL_DIR)
    for fallback: String in BOOTSTRAP_LEVEL_IDS:
      ids.append(fallback)
  return ids
