extends Node

var _failed: int = 0


func _ready() -> void:
  await _run()
  print("RESULT: %d failures" % _failed)
  get_tree().quit(1 if _failed > 0 else 0)


func _run() -> void:
  var ids: Array[String] = GameState.level_ids
  _check(not ids.is_empty(), "levels discovered (%d)" % ids.size())
  if ids.is_empty():
    return
  GameState.load_level(ids[0])
  if GameState.current_level == null:
    _check(false, "level %s loaded" % ids[0])
    return
  var packed: PackedScene = load("res://src/world/CourtyardLevel.tscn") as PackedScene
  var scene: Node = packed.instantiate()
  add_child(scene)
  await get_tree().process_frame
  await get_tree().process_frame
  var level: LevelData = GameState.current_level
  var props: int = get_tree().get_nodes_in_group("interactable").size()
  var players: int = get_tree().get_nodes_in_group("player").size()
  var neighbors: int = get_tree().get_nodes_in_group("neighbor").size()
  _check(props == level.props.size(), "all props spawned")
  _check(players == 1, "exactly one player")
  _check(neighbors == level.wishes.size(), "all neighbours spawned")
  for node_name: String in ["SkyBackdrop", "GroundLayer", "ShadowOverlay", "YSortWorld", "LightBeamLayer", "EmotionalGradeLayer", "HUDLayer"]:
    _check(scene.get_node_or_null(node_name) != null, "node %s exists" % node_name)
  var start: float = GameState.last_result().warmth_factor
  _check(start < 1.0, "level is not already solved")
  GameState.shift_sun(1)
  await get_tree().process_frame
  _check(GameState.current_state.sun_angle == (level.initial_sun_angle + 1) % 8, "sun angle advanced")
  for prop: LevelData.PropSpec in level.props:
    GameState.interact_prop(prop.id)
    await get_tree().process_frame
  var history_before: int = GameState.history.size()
  GameState.undo()
  await get_tree().process_frame
  _check(GameState.history.size() == history_before - 1, "undo popped one command")
  GameState.reset_level()
  await get_tree().process_frame
  _check(is_equal_approx(GameState.last_result().warmth_factor, start), "reset restores initial warmth")
  scene.queue_free()
  await get_tree().process_frame


func _check(condition: bool, label: String) -> void:
  if condition:
    print("  ok   %s" % label)
  else:
    _failed += 1
    print("  FAIL %s" % label)
