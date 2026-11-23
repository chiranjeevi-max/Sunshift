extends Node

## Single-level authoring check. Prints everything needed to iterate on one file:
## schema problems, initial warmth, BFS depth against the act budget, and any
## prop the player cannot walk to. Exits non-zero on failure.
##
##   godot --headless --path . res://tools/check_level.tscn -- A1-03

const BUDGET: Dictionary = {1: [1, 4], 2: [2, 5], 3: [3, 6], 4: [3, 7]}


func _ready() -> void:
  var args: PackedStringArray = OS.get_cmdline_user_args()
  if args.is_empty():
    print("usage: check_level.tscn -- <level_id>")
    get_tree().quit(2)
    return
  var level_id: String = args[0]
  var path: String = "res://data/levels/%s.json" % level_id
  if not FileAccess.file_exists(path):
    print("FAIL %s: no such file %s" % [level_id, path])
    get_tree().quit(1)
    return

  var level: LevelData = LevelData.from_json(path)
  if level == null:
    print("FAIL %s: schema rejected (see error above)" % level_id)
    get_tree().quit(1)
    return

  var problems: Array[String] = LevelValidator.validate(level)
  var failed: bool = false
  print("level   %s  act %d  %dx%d" % [level.id, level.act, level.width, level.height])
  print("props   %d   wishes %d" % [level.props.size(), level.wishes.size()])
  print("sun     start %d" % level.initial_sun_angle)

  for problem: String in problems:
    print("PROBLEM %s" % problem)
    failed = true

  var initial: SimState = SimState.initial(level)
  var solved_at_start: LightSolver.SolveResult = LightSolver.solve(level, initial, false)
  print("initial warmth %.2f (%d/%d)" % [
    solved_at_start.warmth_factor, solved_at_start.satisfied_count, solved_at_start.total_wishes])
  if solved_at_start.solved:
    print("PROBLEM already solved in its initial state")
    failed = true

  var depth: int = LevelValidator.bfs_min_moves(level)
  var budget: Array = BUDGET.get(clampi(level.act, 1, 4), [1, 7])
  if level.id.ends_with("-QC"):
    budget = [budget[0], int(budget[1]) + 1]
  print("depth   %d  budget %d-%d" % [depth, budget[0], budget[1]])
  if depth < 0:
    print("PROBLEM unsolvable (BFS exhausted the state space)")
    failed = true
  elif depth < budget[0] or depth > budget[1]:
    print("PROBLEM depth %d outside the act budget %d-%d" % [depth, budget[0], budget[1]])
    failed = true

  var unreachable: Array[String] = LevelValidator.all_props_reachable(level, initial)
  for prop_id: String in unreachable:
    print("PROBLEM prop %s has no reachable adjacent tile" % prop_id)
    failed = true

  print("RESULT  %s" % ("FAIL" if failed else "PASS"))
  get_tree().quit(1 if failed else 0)
