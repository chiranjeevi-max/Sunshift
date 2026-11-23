extends Node

## Pushes the player into every border, hole and fixture in every courtyard and
## in the hub, then reports anywhere the body ends up standing on something the
## simulation says is not walkable.
##
## The BFS verifier proves a courtyard is *solvable*; it never touches physics.
## These two can drift apart silently, which is exactly what happened: walls had
## collision from the day they were painted, but the void cells around the floor
## were skipped and had none, so the player could stroll off the level.

const CELL: int = 16
const SPEED: float = 72.0
const SWEEP_STEPS: int = 220
const PROP_STEPS: int = 90
const DIRECTIONS: int = 16

var _failed: int = 0
var _checks: int = 0


func _ready() -> void:
  await _run()
  print("RESULT: %d failures" % _failed)
  get_tree().quit(1 if _failed > 0 else 0)


func _run() -> void:
  var ids: Array[String] = GameState.level_ids
  _check(not ids.is_empty(), "levels discovered (%d)" % ids.size())
  if ids.is_empty():
    return
  var packed: PackedScene = load("res://src/world/CourtyardLevel.tscn") as PackedScene
  for id: String in ids:
    GameState.load_level(id)
    var scene: CourtyardLevel = packed.instantiate() as CourtyardLevel
    add_child(scene)
    await get_tree().process_frame
    await get_tree().process_frame
    await _walk_courtyard(id, scene)
    scene.queue_free()
    await get_tree().process_frame
  await _walk_hub()


## Eight outward sweeps from the spawn, then every prop pushed against from each
## side it can be approached from.
func _walk_courtyard(id: String, scene: CourtyardLevel) -> void:
  var level: LevelData = GameState.current_level
  var player: Player = _find_player(scene)
  if player == null:
    _check(false, "%s spawned a player" % id)
    return
  player.set_physics_process(false)
  var area: Rect2 = Rect2(Vector2.ZERO, Vector2(level.width * CELL, level.height * CELL))
  var spawn: Vector2 = _cell_centre(level.player_spawn)
  var escapes: int = 0
  for i: int in DIRECTIONS:
    var heading: Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / float(DIRECTIONS))
    escapes += _sweep(player, level, spawn, heading, SWEEP_STEPS, area, id)
  _check(escapes == 0, "%s: %d of %d sweeps stayed on the floor" % [id, DIRECTIONS - escapes, DIRECTIONS])

  var walls: int = 0
  var wall_checks: int = 0
  for prop: LevelData.PropSpec in level.props:
    # An awning is a canopy you walk under, and the solver says so.
    if prop.type == GridTypes.PropType.AWNING:
      continue
    var cell: Vector2i = Vector2i(prop.x, prop.y)
    for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
      var from: Vector2i = cell - dir
      if not level.is_walkable(from.x, from.y, GameState.current_state):
        continue
      wall_checks += 1
      player.position = _cell_centre(from)
      player.velocity = Vector2.ZERO
      var entered: bool = false
      for _step: int in PROP_STEPS:
        player.velocity = Vector2(float(dir.x), float(dir.y)) * SPEED
        player.move_and_slide()
        if _cell_of(_collision_centre(player)) == cell:
          entered = true
          break
      if entered:
        walls += 1
        print("  %s: walked into the %s at %s" % [id, GridTypes.prop_name(prop.type), cell])
  _check(walls == 0, "%s: %d of %d fixtures are solid" % [id, wall_checks - walls, wall_checks])
  await _check_every_cell(id, scene, level)


## The strong invariant: the physics server must agree with the solver, cell by
## cell. If these two ever disagree the player can walk where the puzzle says
## there is a wall, or be stopped where the puzzle says there is a path.
func _check_every_cell(id: String, scene: CourtyardLevel, level: LevelData) -> void:
  await get_tree().physics_frame
  var space: PhysicsDirectSpaceState2D = scene.get_world_2d().direct_space_state
  var origin: Vector2 = scene.global_position
  var wrong: int = 0
  var first: String = ""
  for y: int in level.height:
    for x: int in level.width:
      var want_solid: bool = not level.is_walkable(x, y, GameState.current_state)
      var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
      query.position = origin + _cell_centre(Vector2i(x, y))
      query.collision_mask = 1
      var solid: bool = not space.intersect_point(query, 4).is_empty()
      if solid != want_solid:
        wrong += 1
        if first.is_empty():
          first = "%s expected %s" % [_cell_centre(Vector2i(x, y)), "solid" if want_solid else "open"]
  _check(wrong == 0, "%s: collision matches the solver in all %d cells%s" % [
    id, level.width * level.height, "" if wrong == 0 else " (first: %s, %d wrong)" % [first, wrong]])


func _sweep(player: Player, level: LevelData, from: Vector2, heading: Vector2,
    steps: int, area: Rect2, id: String) -> int:
  player.position = from
  player.velocity = Vector2.ZERO
  for _step: int in steps:
    player.velocity = heading * SPEED
    player.move_and_slide()
  var at: Vector2 = _collision_centre(player)
  if not area.has_point(at):
    print("  %s: left the courtyard heading %s to %s" % [id, heading.round(), at.round()])
    return 1
  if not _standable(level, at):
    print("  %s: stood on nothing heading %s at cell %s" % [id, heading.round(), _cell_of(at)])
    return 1
  return 0


func _walk_hub() -> void:
  var packed: PackedScene = load("res://src/world/OverworldHub.tscn") as PackedScene
  if packed == null:
    _check(false, "hub scene loads")
    return
  var scene: OverworldHub = packed.instantiate() as OverworldHub
  add_child(scene)
  await get_tree().process_frame
  await get_tree().process_frame
  var player: Player = _find_player(scene)
  if player == null:
    _check(false, "hub spawned a player")
    scene.queue_free()
    return
  player.set_physics_process(false)
  var area: Rect2 = Rect2(
    Vector2.ZERO,
    Vector2(OverworldHub.COLS * CELL, OverworldHub.ROWS * CELL)
  )
  var escapes: int = 0
  for i: int in DIRECTIONS:
    var heading: Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / float(DIRECTIONS))
    player.position = _cell_centre(Vector2i(OverworldHub.SPAWN_COL, OverworldHub.SPAWN_ROW))
    player.velocity = Vector2.ZERO
    for _step: int in SWEEP_STEPS * 2:
      player.velocity = heading * SPEED
      player.move_and_slide()
    var at: Vector2 = _collision_centre(player)
    var cell: Vector2i = _cell_of(at)
    var open: bool = scene._is_open(cell.x, cell.y)
    if not area.has_point(at) or not open:
      escapes += 1
      print("  hub: ended off the promenade heading %s at cell %s" % [heading.round(), cell])
  _check(escapes == 0, "hub: %d of %d sweeps stayed on the promenade" % [DIRECTIONS - escapes, DIRECTIONS])
  # Solid ground is worthless if it also seals the doors.
  var blocked: int = 0
  var gates: Array[Vector2] = scene._gate_reach_points()
  _check(not gates.is_empty(), "hub exposes its gate approach points")
  for point: Vector2 in gates:
    var cell: Vector2i = _cell_of(point)
    if not scene._is_open(cell.x, cell.y):
      blocked += 1
      print("  hub: gate approach at cell %s is solid" % cell)
  _check(blocked == 0, "hub: all %d gate approaches are reachable" % gates.size())
  scene.queue_free()
  await get_tree().process_frame


func _standable(level: LevelData, at: Vector2) -> bool:
  var cell: Vector2i = _cell_of(at)
  return level.is_walkable(cell.x, cell.y, GameState.current_state)


func _find_player(scene: Node) -> Player:
  for node: Node in scene.get_children():
    if node is Player:
      return node as Player
    var found: Player = _find_player(node)
    if found != null:
      return found
  return null


func _collision_centre(player: Player) -> Vector2:
  for child: Node in player.get_children():
    var shape: CollisionShape2D = child as CollisionShape2D
    if shape != null:
      return player.position + shape.position
  return player.position


func _cell_centre(cell: Vector2i) -> Vector2:
  return Vector2(cell.x * CELL + CELL / 2, cell.y * CELL + CELL / 2)


func _cell_of(at: Vector2) -> Vector2i:
  return Vector2i(floori(at.x / float(CELL)), floori(at.y / float(CELL)))


func _check(condition: bool, label: String) -> void:
  _checks += 1
  if condition:
    print("  ok   %s" % label)
  else:
    _failed += 1
    print("  FAIL %s" % label)
