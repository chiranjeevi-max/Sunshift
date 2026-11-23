extends Node

## Drives the real Main through the first five minutes: title, promenade, a
## gate, a courtyard, a solved courtyard, and back out. Everything here uses the
## same entry points the player's input does, so a broken wire shows up as a
## failure rather than as a scene that quietly stays blank.

const MAIN_SCENE: String = "res://src/world/Main.tscn"

var _failed: int = 0


func _ready() -> void:
  if await _run() != true:
    _failed += 1
    print("  FAIL flow smoke did not finish")
  print("RESULT: %d failures" % _failed)
  get_tree().quit(1 if _failed > 0 else 0)


func _run() -> bool:
  # Tests must not inherit a save, or the run proves a different first level on
  # every machine and quietly leaves the player's progress deleted.
  var save_path: String = SaveManager.SAVE_PATH
  var had_save: bool = FileAccess.file_exists(save_path)
  var backup: PackedByteArray = PackedByteArray()
  if had_save:
    var existing: FileAccess = FileAccess.open(save_path, FileAccess.READ)
    if existing != null:
      backup = existing.get_buffer(existing.get_length())
      existing.close()
  SaveManager.reset()
  GameState.completed.clear()
  GameState.unlocked_postcards.clear()

  var packed: PackedScene = load(MAIN_SCENE) as PackedScene
  _check(packed != null, "Main scene loads")
  if packed == null:
    return true
  var main: Main = packed.instantiate() as Main
  add_child(main)
  await _frames(3)

  _check(_screen(main) is TitleScreen, "title screen is first")
  main.start_first_level()
  await _frames(4)
  _check(_screen(main) is OverworldHub, "title leads to the promenade")

  var hub: OverworldHub = _screen(main) as OverworldHub
  if hub == null:
    return true
  var gate: DistrictGate = _first_gate(hub)
  _check(gate != null, "the promenade has a gate")
  if gate == null:
    return true

  # The hub is freed when the screen changes, so read the gate's district now.
  var district_act: int = gate.act
  hub._enter(gate)
  await _frames(4)
  _check(_screen(main) is CourtyardLevel, "a gate leads to a courtyard")
  var courtyard: CourtyardLevel = _screen(main) as CourtyardLevel
  if courtyard == null:
    return true
  _check(GameState.current_level != null and GameState.current_level.act == district_act,
    "the courtyard belongs to the district you entered")

  await _drive_input(courtyard)

  # Solve it the way a player would: real commands through GameState.
  var level: LevelData = GameState.current_level
  var moves: Array[Dictionary] = LevelValidator.bfs_solution(level)
  for move: Dictionary in moves:
    if str(move.get("kind", "")) == "sun":
      GameState.shift_sun(int(move.get("step", 0)))
    else:
      GameState.interact_prop(str(move.get("id", "")))
  _check(GameState.last_result().solved, "%s reports solved" % level.id)
  _check(GameState.is_completed(level.id), "the level is recorded complete")
  _check(GameState.unlocked_postcards.has(level.id), "its postcard is unlocked")

  # Main waits out its breathing beat, then moves on by itself.
  await _wait(1.4)
  _check(not (_screen(main) is CourtyardLevel) or GameState.current_level != level,
    "the game leaves a solved courtyard on its own")

  await _touch_a_fixture(main)

  _check(level.id == "A1-01", "a fresh save starts at the first courtyard")
  _check(PostcardLibrary.for_level(level.id).size() > 0, "the level has journal copy")

  if had_save:
    SaveManager.reset()
    var restored: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
    if restored != null:
      restored.store_buffer(backup)
      restored.close()
  return true


## Everything below goes through the input pipeline, not through GameState. The
## flow test above proves the game advances; this proves the controls a player
## actually presses are the ones wired to the actions.
func _drive_input(courtyard: CourtyardLevel) -> void:
  var player: Player = _find_player(courtyard)
  _check(player != null, "the courtyard has somebody to control")
  if player == null:
    return

  var start: Vector2 = player.position
  await _hold("move_right", 20)
  var rightmost: float = player.position.x
  _check(rightmost > start.x + 4.0, "walking right moves the player")
  await _hold("move_left", 20)
  _check(player.position.x < rightmost - 4.0, "walking left moves the player back")

  await _press("journal")
  _check(get_tree().paused, "the journal stops the clock")
  _check(courtyard.get_node_or_null("HUDLayer/ShiftJournalUI") != null, "the journal opens")
  await _press("journal")
  _check(not get_tree().paused, "closing the journal restarts the clock")
  _check(courtyard.get_node_or_null("HUDLayer/ShiftJournalUI") == null, "the journal closes")

  await _press("pause")
  _check(get_tree().paused, "the pause menu stops the clock")
  await _press("pause")
  _check(not get_tree().paused, "closing the pause menu restarts the clock")

  GameState.reset_level()
  await _frames(2)


## The opening courtyard is a bare room with one wish, so the interact press is
## proved in the first courtyard that actually carries a fixture.
func _touch_a_fixture(main: Main) -> void:
  for id: String in GameState.level_ids:
    GameState.load_level(id)
    if GameState.current_level.props.is_empty():
      continue
    main.play_level(id)
    await _frames(4)
    var scene: CourtyardLevel = _screen(main) as CourtyardLevel
    if scene == null:
      continue
    var prop: LevelData.PropSpec = _reachable_prop(GameState.current_level, _find_player(scene))
    if prop == null:
      continue
    var before: int = int(GameState.current_state.prop_states.get(prop.id, 0))
    await _press("interact")
    var after: int = int(GameState.current_state.prop_states.get(prop.id, 0))
    _check(after != before, "pressing interact turns the %s" % GridTypes.prop_name(prop.type))
    await _press("undo")
    _check(int(GameState.current_state.prop_states.get(prop.id, 0)) == before,
      "undo puts the fixture back")
    return
  _check(false, "a fixture can be reached and touched")


## Park the player beside the first fixture that will answer, so the interact
## press has something in range.
func _reachable_prop(level: LevelData, player: Player) -> LevelData.PropSpec:
  for prop: LevelData.PropSpec in level.props:
    for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
      var cell: Vector2i = Vector2i(prop.x, prop.y) + dir
      if level.is_walkable(cell.x, cell.y, GameState.current_state):
        player.position = Vector2(cell.x * 16 + 8, cell.y * 16 + 8)
        return prop
  return null


func _hold(action: String, frames: int) -> void:
  _send(action, true)
  # The player's movement runs on the physics clock.
  for _frame: int in frames:
    await get_tree().physics_frame
  _send(action, false)
  await _frames(2)


func _press(action: String) -> void:
  _send(action, true)
  await _frames(2)
  _send(action, false)
  await _frames(2)


func _send(action: String, pressed: bool) -> void:
  var event: InputEventAction = InputEventAction.new()
  event.action = action
  event.pressed = pressed
  Input.parse_input_event(event)


func _find_player(scene: Node) -> Player:
  for node: Node in scene.get_children():
    if node is Player:
      return node as Player
    var found: Player = _find_player(node)
    if found != null:
      return found
  return null


func _screen(main: Main) -> Node:
  var host: Node = main.get_node_or_null("SceneHost")
  if host == null:
    return null
  for child: Node in host.get_children():
    if not child.is_queued_for_deletion():
      return child
  return null


func _first_gate(hub: OverworldHub) -> DistrictGate:
  for node: Node in hub.find_children("Gate*", "", true, false):
    var gate: DistrictGate = node as DistrictGate
    if gate != null:
      return gate
  return null


func _frames(count: int) -> void:
  for _i: int in count:
    await get_tree().process_frame


func _wait(seconds: float) -> void:
  await get_tree().create_timer(seconds).timeout


func _check(condition: bool, label: String) -> void:
  if condition:
    print("  ok   %s" % label)
  else:
    _failed += 1
    print("  FAIL %s" % label)
