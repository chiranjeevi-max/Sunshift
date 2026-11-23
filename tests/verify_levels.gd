extends SceneTree

## Authoring gate for every shipped courtyard: schema/reachability problems,
## a non-trivial initial state, the BFS proof that the level is solvable inside
## its act's depth budget, and that no prop is stranded behind a wall.
##
## Godot exits 0 even after a script error, so this runner counts its own
## failures and quits with 1.
##
## Run: godot --headless --path . --script res://tests/verify_levels.gd

const LEVEL_DIR: String = "res://data/levels"

## Act -> minimum player actions (index 0 is unused).
const BUDGET_MIN: Array[int] = [0, 1, 2, 3, 3]
## Act -> maximum player actions before the quiet-corner allowance (index 0 unused).
const BUDGET_MAX: Array[int] = [0, 4, 5, 6, 7]

## Quiet-corner levels are permitted one extra move on top of the act budget.
const QUIET_CORNER_ALLOWANCE: int = 1


func _initialize() -> void:
	var files: PackedStringArray = _level_files()
	if files.is_empty():
		printerr("verify_levels: no level files found under %s" % LEVEL_DIR)
		quit(1)
		return
	var failed: int = 0
	for path: String in files:
		if not _verify(path):
			failed += 1
	if failed == 0:
		print("verify_levels: PASS (%d levels)" % files.size())
	else:
		printerr("verify_levels: FAIL (%d of %d levels)" % [failed, files.size()])
	quit(1 if failed > 0 else 0)


func _level_files() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(LEVEL_DIR)
	if dir == null:
		return out
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for name: String in names:
		var file_name: String = name.trim_suffix(".remap")
		if file_name.ends_with(".json"):
			var path: String = LEVEL_DIR.path_join(file_name)
			if not out.has(path):
				out.append(path)
	return out


func _verify(path: String) -> bool:
	var file_name: String = path.get_file().get_basename()
	var level: LevelData = LevelData.from_json(path)
	if level == null:
		print("FAIL %s depth=-1 could not be parsed" % file_name)
		return false

	var reasons: PackedStringArray = PackedStringArray()

	for problem: String in LevelValidator.validate(level):
		reasons.append(problem)

	var initial: SimState = SimState.initial(level)
	var initial_result: LightSolver.SolveResult = LightSolver.solve(level, initial)
	if initial_result.warmth_factor >= 1.0:
		reasons.append("already solved in the initial state (warmth_factor=%.2f)" % initial_result.warmth_factor)

	var depth: int = LevelValidator.bfs_min_moves(level)
	if depth < 0:
		reasons.append("bfs_min_moves=-1 (unsolvable or state-capped)")
	else:
		if level.act < 1 or level.act > 4:
			reasons.append("act %d is outside 1..4" % level.act)
		else:
			var lowest: int = BUDGET_MIN[level.act]
			var highest: int = BUDGET_MAX[level.act]
			if _is_quiet_corner(level):
				highest += QUIET_CORNER_ALLOWANCE
			if depth < lowest or depth > highest:
				reasons.append("depth %d is outside the act %d budget %d..%d" % [depth, level.act, lowest, highest])

	var unreachable: Array[String] = LevelValidator.all_props_reachable(level, initial)
	if not unreachable.is_empty():
		reasons.append("unreachable props: %s" % ", ".join(unreachable))

	# A level with no journal card would solve into a blank page.
	if PostcardLibrary.for_level(file_name).is_empty():
		reasons.append("no postcard entry for %s" % file_name)
	if level.act != PostcardLibrary.act_for(file_name) and not PostcardLibrary.for_level(file_name).is_empty():
		reasons.append("postcard act %d != level act %d" % [PostcardLibrary.act_for(file_name), level.act])

	if reasons.is_empty():
		print("PASS %s depth=%d wishes=%d" % [file_name, depth, initial_result.total_wishes])
		return true
	print("FAIL %s depth=%d %s" % [file_name, depth, " | ".join(reasons)])
	return false


## The `-QC` suffix is the marker, not the prose: a title is copy and can be
## rewritten at any time, while the id is what the hub and the journal index by.
func _is_quiet_corner(level: LevelData) -> bool:
	return level.id.ends_with("-QC")
