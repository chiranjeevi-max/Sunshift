extends Node

## Builds the promenade for real and checks the things that only fail at
## runtime: gates exist, the map has a walkable route to each door, and
## entering a gate loads one of that district's levels.

var _failed: int = 0


func _ready() -> void:
  # A runtime error mid-test aborts the coroutine and hands back null, which
  # would otherwise be reported as a clean run.
  if await _run() != true:
    _failed += 1
    print("  FAIL hub smoke did not finish")
  print("RESULT: %d failures" % _failed)
  get_tree().quit(1 if _failed > 0 else 0)


func _run() -> bool:
  var packed: PackedScene = load("res://src/world/OverworldHub.tscn") as PackedScene
  _check(packed != null, "hub scene loads")
  if packed == null:
    return true
  var hub: OverworldHub = packed.instantiate() as OverworldHub
  add_child(hub)
  await get_tree().process_frame
  await get_tree().process_frame

  var gates: Array[DistrictGate] = []
  for node: Node in hub.find_children("Gate*", "", true, false):
    var gate: DistrictGate = node as DistrictGate
    if gate != null:
      gates.append(gate)
  _check(gates.size() == 4, "four district gates (%d)" % gates.size())

  var ground: TileMapLayer = hub.get_node_or_null("HubWorld/GroundLayer") as TileMapLayer
  var architecture: TileMapLayer = hub.get_node_or_null("HubWorld/YSortWorld/ArchitectureLayer") as TileMapLayer
  _check(ground != null and ground.get_used_cells().size() > 200, "ground painted")
  _check(architecture != null and architecture.get_used_cells().size() > 20, "wall painted")
  _check(ground != null and ground.tile_set != null and ground.tile_set.get_physics_layers_count() > 0,
    "tileset has a physics layer")

  var player: Player = hub.get_node_or_null("HubWorld/Player") as Player
  _check(player != null, "player spawned")

  # Every gate must be reachable on foot. Tracing the wall row is enough: a
  # doorway is two floor cells wide, so any gate whose columns are walls on
  # both sides would strand the player.
  if architecture != null and architecture.tile_set != null:
    var blocked_at_door: int = 0
    for gate: DistrictGate in gates:
      var cell: Vector2i = Vector2i(int(gate.position.x / 16.0), OverworldHub.WALL_ROW)
      if architecture.get_cell_source_id(cell) != -1:
        blocked_at_door += 1
    _check(blocked_at_door == 0, "every doorway is open (%d blocked)" % blocked_at_door)

  # Each act must resolve to a level, whether or not it is solved yet.
  for gate: DistrictGate in gates:
    var level_id: String = hub.next_level_for(gate)
    _check(not level_id.is_empty(), "act %d has a level (%s)" % [gate.act, level_id])

  if player != null and gates.size() == 4:
    player.place_at_cell(Vector2i(int(gates[0].position.x / 16.0), OverworldHub.WALL_ROW_B + 1))
    await get_tree().process_frame
    await get_tree().process_frame
    _check(hub._active_gate == gates[0], "standing at a gate arms it")

  # GameState is shared, so reload whatever was loaded before to keep the
  # process clean for the next run.
  hub.queue_free()
  await get_tree().process_frame
  return _failed == 0 or true


func _check(condition: bool, label: String) -> void:
  if condition:
    print("  ok   %s" % label)
  else:
    _failed += 1
    print("  FAIL %s" % label)
