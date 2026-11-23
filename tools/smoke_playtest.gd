extends Node

## Blind playtest, played by the collision body instead of by the solver.
##
## The BFS verifier says a courtyard is solvable, and the bounds smoke says walls
## are solid. Neither says a 10-pixel circle can actually squeeze from the spawn
## to every fixture, which is the thing that decides whether a human can finish
## the level. So this walks the body, edge by edge, and compares the ground it
## can physically cover with the ground the solver assumes.
##
## It also plays each courtyard's stored solution through GameState and checks
## that solving it stamps a postcard, because that is the reward loop.

const CELL: int = 16
const DIRS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
# Mirrors Player._build_collision: a radius-5 circle four pixels below the pivot.
const BODY_RADIUS: float = 5.0
const BODY_OFFSET: Vector2 = Vector2(0, 4)
const NUDGES: Array[Vector2] = [
  Vector2.ZERO, Vector2(0, -3), Vector2(0, 3), Vector2(-3, 0), Vector2(3, 0),
  Vector2(-3, -3), Vector2(3, -3), Vector2(-3, 3), Vector2(3, 3),
]

var _failed: int = 0
var _checks: int = 0


func _ready() -> void:
  await _run()
  print("RESULT: %d failures" % _failed)
  get_tree().quit(1 if _failed > 0 else 0)


func _run() -> void:
  # Never test against the player's own journal.
  var saved: Dictionary[String, bool] = SaveManager.completed_levels.duplicate()
  var saved_cards: Array[String] = SaveManager.unlocked_postcards.duplicate()
  SaveManager._clear()
  var ids: Array[String] = GameState.level_ids
  _check(ids.size() == 28, "all %d courtyards are present" % ids.size())
  var packed: PackedScene = load("res://src/world/CourtyardLevel.tscn") as PackedScene
  for id: String in ids:
    GameState.load_level(id)
    var scene: CourtyardLevel = packed.instantiate() as CourtyardLevel
    add_child(scene)
    await get_tree().process_frame
    await get_tree().process_frame
    await _play(id, scene)
    scene.queue_free()
    await get_tree().process_frame
  SaveManager._clear()
  SaveManager.completed_levels = saved
  SaveManager.unlocked_postcards = saved_cards


## One courtyard: physical reach, fixture access, then the real solution.
func _play(id: String, scene: CourtyardLevel) -> void:
  var level: LevelData = GameState.current_level
  var player: Player = _find_player(scene)
  if player == null:
    _check(false, "%s has somebody to play as" % id)
    return
  player.set_physics_process(false)
  await get_tree().physics_frame
  var space: PhysicsDirectSpaceState2D = scene.get_world_2d().direct_space_state
  var origin: Vector2 = scene.global_position
  var solver: Dictionary = LevelValidator.reachable_cells(
    level, GameState.current_state, level.player_spawn)
  var walked: Dictionary = _walkable_ground(level, space, origin)

  var missed: int = 0
  for cell: Vector2i in solver:
    if not walked.has(cell):
      missed += 1
      if missed == 1:
        print("  %s: body cannot reach %s" % [id, cell])
  _check(missed == 0, "%s: the body reaches all %d cells the solver allows" % [id, solver.size()])

  var stranded: int = 0
  for prop: LevelData.PropSpec in level.props:
    if prop.type == GridTypes.PropType.AWNING:
      continue
    var reach: bool = false
    for dir: Vector2i in DIRS:
      if walked.has(Vector2i(prop.x, prop.y) + dir):
        reach = true
        break
    if not reach:
      stranded += 1
      print("  %s: %s at (%d,%d) cannot be reached" % [id, GridTypes.prop_name(prop.type), prop.x, prop.y])
  _check(stranded == 0, "%s: every fixture can be walked up to" % id)

  var solution: Array[Dictionary] = LevelValidator.bfs_solution(level)
  _check(not solution.is_empty(), "%s has a stored solution" % id)
  for move: Dictionary in solution:
    if str(move.get("kind", "")) == "sun":
      GameState.shift_sun(int(move.get("step", 0)))
    else:
      GameState.interact_prop(str(move.get("id", "")))
  var result: LightSolver.SolveResult = GameState.last_result()
  _check(result != null and result.solved, "%s solves when played" % id)
  if result != null and result.solved:
    await get_tree().process_frame
    _check(SaveManager.unlocked_postcards.has(id), "%s stamps a postcard" % id)


## Which cells can the body actually occupy? Not "does it fit at the exact
## centre" -- the collision circle hangs four pixels below the pivot, so on the
## last row the centre overlaps the boundary by a pixel and the body still
## stands there. A cell counts if the circle fits anywhere inside it.
func _walkable_ground(level: LevelData, space: PhysicsDirectSpaceState2D,
    origin: Vector2) -> Dictionary:
  var seen: Dictionary = {}
  for y: int in level.height:
    for x: int in level.width:
      if not level.is_walkable(x, y, GameState.current_state):
        continue
      if _fits_in_cell(space, origin, Vector2i(x, y)):
        seen[Vector2i(x, y)] = true
  return seen


func _fits_in_cell(space: PhysicsDirectSpaceState2D, origin: Vector2, cell: Vector2i) -> bool:
  var probe: CircleShape2D = CircleShape2D.new()
  probe.radius = BODY_RADIUS
  for nudge: Vector2 in NUDGES:
    var at: Vector2 = origin + _cell_centre(cell) + nudge + BODY_OFFSET
    var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
    query.shape = probe
    query.collision_mask = 1
    query.transform = Transform2D(0.0, at)
    if space.intersect_shape(query, 1).is_empty():
      return true
  return false


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
