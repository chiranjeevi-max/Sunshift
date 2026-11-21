class_name LevelValidator
extends RefCounted

## Static authoring checks: schema sanity, reachability and the BFS proof that a
## level falls inside its act's minimum-move budget.

const DEFAULT_STATE_CAP: int = 400000
const _DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const _SUN_STEPS: Array[int] = [1, 7]


static func validate(level: LevelData) -> Array[String]:
  var errors: Array[String] = []
  if level == null:
    errors.append("level is null")
    return errors
  if level.id.strip_edges().is_empty():
    errors.append("level id is empty")
  if level.act < 1 or level.act > 4:
    errors.append("act %d is outside 1..4" % level.act)
  if level.width < 3 or level.height < 3:
    errors.append("grid %dx%d is smaller than 3x3" % [level.width, level.height])
  if level.title.strip_edges().is_empty():
    errors.append("title is empty")
  if level.postcard_caption.strip_edges().is_empty():
    errors.append("postcard_caption is empty")
  if level.initial_sun_angle < 0 or level.initial_sun_angle > 7:
    errors.append("initial_sun_angle %d is outside 0..7" % level.initial_sun_angle)
  if not level.in_bounds(level.player_spawn.x, level.player_spawn.y):
    errors.append("player_spawn (%d,%d) is out of bounds" % [level.player_spawn.x, level.player_spawn.y])

  var initial := SimState.initial(level)
  if level.in_bounds(level.player_spawn.x, level.player_spawn.y) and not level.is_walkable(level.player_spawn.x, level.player_spawn.y, initial):
    errors.append("player_spawn (%d,%d) is not walkable" % [level.player_spawn.x, level.player_spawn.y])

  var seen_props: Dictionary[String, bool] = {}
  var prop_cells: Dictionary[Vector2i, String] = {}
  for prop: LevelData.PropSpec in level.props:
    if prop.id.strip_edges().is_empty():
      errors.append("prop with empty id")
    elif seen_props.has(prop.id):
      errors.append("duplicate prop id \"%s\"" % prop.id)
    seen_props[prop.id] = true
    if not level.in_bounds(prop.x, prop.y):
      errors.append("prop \"%s\" (%d,%d) is out of bounds" % [prop.id, prop.x, prop.y])
      continue
    var tile: LevelData.TileSpec = level.tile_at(prop.x, prop.y)
    if tile.type == GridTypes.TileType.VOID or tile.type == GridTypes.TileType.WALL:
      errors.append("prop \"%s\" sits on a %s tile" % [prop.id, GridTypes.tile_name(tile.type)])
    var cell := Vector2i(prop.x, prop.y)
    if prop_cells.has(cell):
      errors.append("props \"%s\" and \"%s\" overlap at (%d,%d)" % [prop_cells[cell], prop.id, prop.x, prop.y])
    else:
      prop_cells[cell] = prop.id
    var state_count: int = GridTypes.prop_state_count(prop.type)
    if prop.state < 0 or prop.state >= state_count:
      errors.append("prop \"%s\" state %d is outside 0..%d" % [prop.id, prop.state, state_count - 1])

  if level.wishes.is_empty():
    errors.append("level has no wishes")
  var seen_wishes: Dictionary[String, bool] = {}
  var wish_cells: Dictionary[Vector2i, String] = {}
  for wish: LevelData.WishSpec in level.wishes:
    if wish.id.strip_edges().is_empty():
      errors.append("wish with empty id")
    elif seen_wishes.has(wish.id):
      errors.append("duplicate wish id \"%s\"" % wish.id)
    seen_wishes[wish.id] = true
    if wish.who.strip_edges().is_empty():
      errors.append("wish \"%s\" has no sprite archetype in \"who\"" % wish.id)
    if not level.in_bounds(wish.x, wish.y):
      errors.append("wish \"%s\" (%d,%d) is out of bounds" % [wish.id, wish.x, wish.y])
      continue
    var tile: LevelData.TileSpec = level.tile_at(wish.x, wish.y)
    if tile.type == GridTypes.TileType.VOID:
      errors.append("wish \"%s\" stands on a void tile" % wish.id)
    var cell := Vector2i(wish.x, wish.y)
    if wish_cells.has(cell):
      errors.append("wishes \"%s\" and \"%s\" share cell (%d,%d)" % [wish_cells[cell], wish.id, wish.x, wish.y])
    else:
      wish_cells[cell] = wish.id
    if wish.need == GridTypes.WishType.SHARED_BEAM and wish.targets.is_empty():
      errors.append("wish \"%s\" needs a target for SHARED_BEAM" % wish.id)
    for target: Vector2i in wish.targets:
      if not level.in_bounds(target.x, target.y):
        errors.append("wish \"%s\" target (%d,%d) is out of bounds" % [wish.id, target.x, target.y])
      elif level.tile_at(target.x, target.y).type == GridTypes.TileType.VOID:
        errors.append("wish \"%s\" target (%d,%d) is void" % [wish.id, target.x, target.y])

  if level.width > 0 and level.height > 0:
    var result: LightSolver.SolveResult = solve_state(level, initial)
    if result.solved:
      errors.append("level is already solved in its initial state (warmth_factor == 1.0)")

  return errors


static func reachable_cells(level: LevelData, state: SimState, from: Vector2i) -> Dictionary:
  var out: Dictionary[Vector2i, bool] = {}
  if level == null or state == null:
    return out
  if not level.is_walkable(from.x, from.y, state):
    return out
  out[from] = true
  var frontier: Array[Vector2i] = [from]
  var head: int = 0
  while head < frontier.size():
    var cell: Vector2i = frontier[head]
    head += 1
    for dir: Vector2i in _DIRS:
      var next: Vector2i = cell + dir
      if out.has(next):
        continue
      if level.is_walkable(next.x, next.y, state):
        out[next] = true
        frontier.append(next)
  return out


static func all_props_reachable(level: LevelData, state: SimState) -> Array[String]:
  var missing: Array[String] = []
  if level == null or state == null:
    return missing
  var reach: Dictionary = reachable_cells(level, state, level.player_spawn)
  for prop: LevelData.PropSpec in level.props:
    var cell := Vector2i(prop.x, prop.y)
    var ok: bool = reach.has(cell)
    if not ok:
      for dir: Vector2i in _DIRS:
        if reach.has(cell + dir):
          ok = true
          break
    if not ok:
      missing.append(prop.id)
  return missing


## Minimum player actions to reach a solved state, or -1 if unreachable or capped.
static func bfs_min_moves(level: LevelData, state_cap: int = DEFAULT_STATE_CAP) -> int:
  if level == null:
    return -1
  var start := SimState.initial(level)
  var visited: Dictionary[String, bool] = {}
  visited[start.key()] = true
  var frontier: Array[SimState] = [start]
  var depths: Array[int] = [0]
  var head: int = 0
  var explored: int = 0
  while head < frontier.size():
    var current: SimState = frontier[head]
    var depth: int = depths[head]
    head += 1
    explored += 1
    if explored > state_cap:
      return -1
    var result: LightSolver.SolveResult = LightSolver.solve(level, current, false)
    if result.solved:
      return depth
    var charge: Dictionary[String, int] = result.next_lantern_charge
    for step: int in _SUN_STEPS:
      var sun_child := current.copy()
      sun_child.sun_angle = posmod(current.sun_angle + step, 8)
      sun_child.lantern_charge = SimState.copy_int_dict(charge)
      _enqueue(sun_child, depth, visited, frontier, depths)
    for prop: LevelData.PropSpec in level.props:
      var state_count: int = GridTypes.prop_state_count(prop.type)
      if state_count < 2:
        continue
      var from_state: int = current.prop_states.get(prop.id, prop.state)
      var to_state: int = posmod(from_state + 1, state_count)
      if to_state == from_state:
        continue
      var prop_child := current.copy()
      prop_child.prop_states[prop.id] = to_state
      prop_child.lantern_charge = SimState.copy_int_dict(charge)
      _enqueue(prop_child, depth, visited, frontier, depths)
  return -1


## The shortest line of moves that solves the level, as a list of
## `{"kind": "sun" | "prop", "step": int, "id": String}` entries. `bfs_min_moves`
## only reports the length, which is all the level gate needs; hints, the
## postcard pin and the capture tool need the moves themselves.
static func bfs_solution(level: LevelData, state_cap: int = DEFAULT_STATE_CAP) -> Array[Dictionary]:
  var moves: Array[Dictionary] = []
  if level == null:
    return moves
  var start := SimState.initial(level)
  var visited: Dictionary[String, bool] = {start.key(): true}
  var parents: Dictionary[String, String] = {}
  var parent_moves: Dictionary[String, Dictionary] = {}
  var frontier: Array[SimState] = [start]
  var depths: Array[int] = [0]
  var head: int = 0
  while head < frontier.size():
    var current: SimState = frontier[head]
    var depth: int = depths[head]
    head += 1
    if head > state_cap:
      return []
    var result: LightSolver.SolveResult = LightSolver.solve(level, current, false)
    if result.solved:
      return _walk_back(current.key(), parents, parent_moves)
    var charge: Dictionary[String, int] = result.next_lantern_charge
    for step: int in _SUN_STEPS:
      var sun_child := current.copy()
      sun_child.sun_angle = posmod(current.sun_angle + step, 8)
      sun_child.lantern_charge = SimState.copy_int_dict(charge)
      _visit(sun_child, current.key(), {"kind": "sun", "step": step, "id": ""},
          visited, parents, parent_moves, frontier, depths, depth)
    for prop: LevelData.PropSpec in level.props:
      var state_count: int = GridTypes.prop_state_count(prop.type)
      if state_count < 2:
        continue
      var from_state: int = current.prop_states.get(prop.id, prop.state)
      var to_state: int = posmod(from_state + 1, state_count)
      if to_state == from_state:
        continue
      var prop_child := current.copy()
      prop_child.prop_states[prop.id] = to_state
      prop_child.lantern_charge = SimState.copy_int_dict(charge)
      _visit(prop_child, current.key(), {"kind": "prop", "step": 0, "id": prop.id},
          visited, parents, parent_moves, frontier, depths, depth)
  return moves


static func _visit(child: SimState, parent_key: String, move: Dictionary,
    visited: Dictionary[String, bool], parents: Dictionary[String, String],
    parent_moves: Dictionary[String, Dictionary], frontier: Array[SimState],
    depths: Array[int], depth: int) -> void:
  var key: String = child.key()
  if visited.has(key):
    return
  visited[key] = true
  parents[key] = parent_key
  parent_moves[key] = move
  frontier.append(child)
  depths.append(depth + 1)


static func _walk_back(key: String, parents: Dictionary[String, String],
    parent_moves: Dictionary[String, Dictionary]) -> Array[Dictionary]:
  var reversed: Array[Dictionary] = []
  var cursor: String = key
  while parents.has(cursor):
    reversed.append(parent_moves[cursor])
    cursor = parents[cursor]
  reversed.reverse()
  return reversed


static func solve_state(level: LevelData, state: SimState) -> LightSolver.SolveResult:
  return LightSolver.solve(level, state)


static func _enqueue(child: SimState, depth: int, visited: Dictionary[String, bool], frontier: Array[SimState], depths: Array[int]) -> void:
  var key: String = child.key()
  if visited.has(key):
    return
  visited[key] = true
  frontier.append(child)
  depths.append(depth + 1)
