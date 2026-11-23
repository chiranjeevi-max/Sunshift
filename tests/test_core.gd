extends SceneTree

## Unit tests for the puzzle simulation and level validation.
##
## Godot exits 0 even after a script error, so this runner counts its own
## failures, and every test returns `true` on its last line: a test that dies on
## a runtime error returns null and the driver counts `call(t) != true` as a
## failure.
##
## Run: godot --headless --path . --script res://tests/test_core.gd

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var tests: Array[String] = [
		"test_sun_dir_all_angles",
		"test_mirror_reflect",
		"test_elevation_shadow",
		"test_awning_and_shutter",
		"test_prism_split",
		"test_stained_glass",
		"test_puddle_odd_angles_only",
		"test_lantern_charge_cycle",
		"test_wish_types",
		"test_warmth_factor",
		"test_command_history_undo",
		"test_level_data_rejects",
		"test_solve_determinism",
		"test_sim_state_key",
		"test_postcards_cover_every_level",
		"test_bfs_solution_replays",
	]
	var failed: int = 0
	for name: String in tests:
		var outcome: Variant = call(name)
		if outcome != true:
			failed += 1
			printerr("  FAILED test: %s" % name)
	if failed == 0:
		print("test_core: PASS (%d tests, %d checks)" % [tests.size(), _checks])
	else:
		printerr("test_core: FAIL (%d of %d tests, %d checks)" % [failed, tests.size(), _checks])
	quit(1 if failed > 0 else 0)


func test_sun_dir_all_angles() -> bool:
	var ok: bool = true
	var expected: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	]
	var names: Array[String] = ["E", "NE", "N", "NW", "W", "SW", "S", "SE"]
	for angle: int in 8:
		var actual: Vector2i = GridTypes.sun_dir(angle)
		ok = _check(actual == expected[angle],
				"sun_dir(%d) is %s %s (got %s)" % [angle, names[angle], expected[angle], actual]) and ok
	return ok


func test_mirror_reflect() -> bool:
	var ok: bool = true
	var e: Vector2i = Vector2i(1, 0)
	var n: Vector2i = Vector2i(0, -1)
	var w: Vector2i = Vector2i(-1, 0)
	var s: Vector2i = Vector2i(0, 1)
	var dirs: Array[Vector2i] = [e, n, w, s]
	# "/" (0): E->N N->E W->S S->W
	var slash_out: Array[Vector2i] = [n, e, s, w]
	# "\" (1): E->S N->W W->N S->E
	var backslash_out: Array[Vector2i] = [s, w, n, e]
	for i: int in dirs.size():
		var d: Vector2i = dirs[i]
		ok = _check(GridTypes.mirror_reflect(0, d) == slash_out[i],
				"mirror 0 maps %s to %s" % [d, slash_out[i]]) and ok
		ok = _check(GridTypes.mirror_reflect(1, d) == backslash_out[i],
				"mirror 1 maps %s to %s" % [d, backslash_out[i]]) and ok
	for mirror_state: int in 2:
		for d: Vector2i in dirs:
			var out_dir: Vector2i = GridTypes.mirror_reflect(mirror_state, d)
			ok = _check(GridTypes.mirror_reflect(mirror_state, -out_dir) == -d,
					"mirror %d retraces a beam entering from %s" % [mirror_state, -out_dir]) and ok
	return ok


func test_elevation_shadow() -> bool:
	var ok: bool = true
	var tiles: Array = [
		_tile(2, 0, "wall", 2),
		_tile(2, 1, "wall", 2),
		_tile(2, 2, "wall", 2),
		_tile(3, 1, "floor", 1),
		_tile(3, 2, "floor", 2),
	]
	var level: LevelData = _level(5, 3, 0, tiles)
	ok = _check(level != null, "elevation fixture parses") and ok
	if level == null:
		return ok
	var result: LightSolver.SolveResult = LightSolver.solve(level, SimState.initial(level))
	ok = _check(result.light_at(3, 0) == GridTypes.LightType.NONE,
			"a level-2 parapet shades a level-0 cell") and ok
	ok = _check(result.light_at(3, 1) == GridTypes.LightType.NONE,
			"a level-2 parapet shades a level-1 cell") and ok
	ok = _check(result.light_at(3, 2) == GridTypes.LightType.DIRECT_SUN,
			"a level-2 cell is not shaded by a level-2 parapet") and ok
	return ok


func test_awning_and_shutter() -> bool:
	var ok: bool = true
	ok = _check(not GridTypes.prop_blocks_light(GridTypes.PropType.AWNING, 0),
			"retracted awning does not block light") and ok
	ok = _check(GridTypes.prop_blocks_light(GridTypes.PropType.AWNING, 1),
			"extended awning blocks light") and ok
	ok = _check(GridTypes.prop_blocks_light(GridTypes.PropType.SHUTTER, 0),
			"closed shutter blocks light") and ok
	ok = _check(not GridTypes.prop_blocks_light(GridTypes.PropType.SHUTTER, 1),
			"open shutter does not block light") and ok

	var tiles: Array = [_tile(2, 0, "floor", 1), _tile(2, 1, "floor", 1)]
	var props: Array = [
		_prop("awn", "awning", 2, 0, 1, 0),
		_prop("sht", "shutter", 2, 1, 1, 1),
	]
	var level: LevelData = _level(5, 3, 0, tiles, props)
	ok = _check(level != null, "awning/shutter fixture parses") and ok
	if level == null:
		return ok
	var state: SimState = SimState.initial(level)
	var open_result: LightSolver.SolveResult = LightSolver.solve(level, state)
	ok = _check(open_result.light_at(3, 0) == GridTypes.LightType.DIRECT_SUN,
			"retracted awning lets sunlight through") and ok
	ok = _check(open_result.light_at(3, 1) == GridTypes.LightType.DIRECT_SUN,
			"open shutter lets sunlight through") and ok

	state.prop_states["awn"] = 1
	state.prop_states["sht"] = 0
	var closed_result: LightSolver.SolveResult = LightSolver.solve(level, state)
	ok = _check(closed_result.light_at(3, 0) == GridTypes.LightType.NONE,
			"extended awning shades the cell behind it") and ok
	ok = _check(closed_result.light_at(3, 1) == GridTypes.LightType.NONE,
			"closed shutter shades the cell behind it") and ok
	return ok


func test_prism_split() -> bool:
	var ok: bool = true
	var props: Array = [
		_prop("mir", "mirror", 1, 2, 0, 0),
		_prop("pri", "prism", 1, 1, 0, 0),
	]
	var level: LevelData = _level(6, 4, 0, [], props)
	ok = _check(level != null, "prism fixture parses") and ok
	if level == null:
		return ok
	var result: LightSolver.SolveResult = LightSolver.solve(level, SimState.initial(level))
	ok = _check(result.light_at(2, 1) == GridTypes.LightType.BEAM_AMBER,
			"prism emits one ray east") and ok
	ok = _check(result.light_at(0, 1) == GridTypes.LightType.BEAM_AMBER,
			"prism emits one ray west") and ok
	ok = _check(result.light_at(1, 0) == GridTypes.LightType.DIRECT_SUN,
			"the original ray stops at the prism") and ok
	return ok


func test_stained_glass() -> bool:
	var ok: bool = true
	var props: Array = [
		_prop("mir", "mirror", 1, 2, 0, 0),
		_prop("glass", "stained_glass", 1, 1, 0, 0),
	]
	var level: LevelData = _level(6, 4, 0, [], props)
	ok = _check(level != null, "stained glass fixture parses") and ok
	if level == null:
		return ok
	var result: LightSolver.SolveResult = LightSolver.solve(level, SimState.initial(level))
	ok = _check(result.light_at(1, 1) != GridTypes.LightType.NONE,
			"the beam reaches the stained glass") and ok
	ok = _check(result.light_at(1, 0) == GridTypes.LightType.BEAM_ROSE,
			"stained glass converts AMBER to ROSE and keeps going") and ok
	return ok


func test_puddle_odd_angles_only() -> bool:
	var ok: bool = true
	var tiles: Array = [_tile(2, 2, "puddle", 0)]
	var level: LevelData = _level(5, 5, 0, tiles)
	ok = _check(level != null, "puddle fixture parses") and ok
	if level == null:
		return ok

	var even_state: SimState = SimState.initial(level)
	var even_result: LightSolver.SolveResult = LightSolver.solve(level, even_state)
	ok = _check(even_result.light_at(2, 2) == GridTypes.LightType.DIRECT_SUN,
			"the puddle is sunlit at angle 0") and ok
	ok = _check(_count_light(even_result, GridTypes.LightType.BEAM_AMBER) == 0,
			"an even sun angle emits no puddle beam") and ok

	var odd_state: SimState = SimState.initial(level)
	odd_state.sun_angle = 1
	var odd_result: LightSolver.SolveResult = LightSolver.solve(level, odd_state)
	ok = _check(odd_result.light_at(3, 1) == GridTypes.LightType.BEAM_AMBER,
			"an odd sun angle emits a puddle beam (first step)") and ok
	ok = _check(odd_result.light_at(4, 0) == GridTypes.LightType.BEAM_AMBER,
			"an odd sun angle emits a puddle beam (second step)") and ok
	ok = _check(_count_light(odd_result, GridTypes.LightType.BEAM_AMBER) == 2,
			"the puddle beam is exactly two cells long") and ok
	return ok


func test_lantern_charge_cycle() -> bool:
	var ok: bool = true
	var tiles: Array = [_tile(3, 1, "wall", 2)]
	var props: Array = [_prop("lan", "lantern", 2, 1, 1, 0)]
	var level: LevelData = _level(5, 3, 0, tiles, props)
	ok = _check(level != null, "lantern fixture parses") and ok
	if level == null:
		return ok

	var state_t0: SimState = SimState.initial(level)
	var key_before: String = state_t0.key()
	var t0: LightSolver.SolveResult = LightSolver.solve(level, state_t0)
	ok = _check(t0.light_at(2, 1) == GridTypes.LightType.LANTERN_GLOW,
			"a sunlit lantern glows on the same turn") and ok
	ok = _check(t0.next_lantern_charge.get("lan", -1) == 1,
			"a sunlit lantern charges for the next turn") and ok
	ok = _check(state_t0.key() == key_before,
			"solve() does not mutate the passed state") and ok
	ok = _check(state_t0.lantern_charge.get("lan", -1) == 0,
			"solve() leaves the passed lantern_charge alone") and ok

	var state_t1: SimState = state_t0.copy()
	state_t1.sun_angle = 4
	state_t1.lantern_charge = t0.next_lantern_charge
	var t1: LightSolver.SolveResult = LightSolver.solve(level, state_t1)
	ok = _check(t1.light_at(2, 1) == GridTypes.LightType.LANTERN_GLOW,
			"a charged lantern keeps glowing the turn after it was lit") and ok
	ok = _check(t1.next_lantern_charge.get("lan", -1) == 0,
			"an unlit lantern discharges for the next turn") and ok

	var state_t2: SimState = state_t1.copy()
	state_t2.lantern_charge = t1.next_lantern_charge
	var t2: LightSolver.SolveResult = LightSolver.solve(level, state_t2)
	ok = _check(t2.light_at(2, 1) == GridTypes.LightType.NONE,
			"the lantern stops glowing on the third turn unless relit") and ok
	ok = _check(_count_light(t2, GridTypes.LightType.LANTERN_GLOW) == 0,
			"no lantern glow is painted on the third turn") and ok
	ok = _check(t2.next_lantern_charge.get("lan", -1) == 0,
			"the discharged lantern stays uncharged") and ok
	return ok


func test_wish_types() -> bool:
	var ok: bool = true

	var warm_level: LevelData = _level(6, 4, 0, [_tile(2, 1, "wall", 2)], [],
			[_wish("w", 3, 1, "WARM_SUN")])
	var warm: Array[LightSolver.SolveResult] = _solve_at_0_and_4(warm_level)
	ok = _check(warm[0].wish_states.get("w", true) == false,
			"WARM_SUN is unmet in shade") and ok
	ok = _check(warm[1].wish_states.get("w", false) == true,
			"WARM_SUN is met by direct sun") and ok
	ok = _check(warm[1].satisfied_count == 1, "WARM_SUN counts one wish") and ok

	var shade_level: LevelData = _level(6, 4, 0, [_tile(2, 1, "wall", 2)], [],
			[_wish("w", 3, 1, "SOFT_SHADE")])
	var shade: Array[LightSolver.SolveResult] = _solve_at_0_and_4(shade_level)
	ok = _check(shade[0].wish_states.get("w", false) == true,
			"SOFT_SHADE is met by a shaded cell") and ok
	ok = _check(shade[1].wish_states.get("w", true) == false,
			"SOFT_SHADE is unmet by a sunlit cell") and ok

	var shared_props: Array = [
		_prop("mir", "mirror", 1, 2, 0, 0),
		_prop("pri", "prism", 1, 1, 0, 0),
	]
	var shared_level: LevelData = _level(6, 4, 0, [], shared_props,
			[_wish("w", 2, 1, "SHARED_BEAM", [[0, 1]])])
	var shared: Array[LightSolver.SolveResult] = _solve_at_0_and_4(shared_level)
	ok = _check(shared[0].wish_states.get("w", false) == true,
			"SHARED_BEAM is met when both cells hold a beam") and ok
	ok = _check(shared[1].wish_states.get("w", true) == false,
			"SHARED_BEAM is unmet without beams") and ok

	var rose_props: Array = [
		_prop("mir", "mirror", 1, 2, 0, 0),
		_prop("glass", "stained_glass", 1, 1, 0, 0),
	]
	var rose_level: LevelData = _level(6, 4, 0, [], rose_props,
			[_wish("w", 1, 0, "ROSE_LIGHT")])
	var rose: Array[LightSolver.SolveResult] = _solve_at_0_and_4(rose_level)
	ok = _check(rose[0].wish_states.get("w", false) == true,
			"ROSE_LIGHT is met by a rose beam") and ok
	ok = _check(rose[1].wish_states.get("w", true) == false,
			"ROSE_LIGHT is unmet without a rose beam") and ok

	var lantern_props: Array = [_prop("lan", "lantern", 2, 1, 1, 0)]
	var lantern_level: LevelData = _level(6, 4, 0, [_tile(3, 1, "wall", 2)], lantern_props,
			[_wish("w", 2, 1, "LANTERN_GLOW")])
	var lantern: Array[LightSolver.SolveResult] = _solve_at_0_and_4(lantern_level)
	ok = _check(lantern[0].wish_states.get("w", false) == true,
			"LANTERN_GLOW is met by a glowing lantern") and ok
	ok = _check(lantern[1].wish_states.get("w", true) == false,
			"LANTERN_GLOW is unmet by an unlit lantern") and ok
	return ok


func test_warmth_factor() -> bool:
	var ok: bool = true
	var partial_wishes: Array = [
		_wish("w1", 1, 1, "WARM_SUN"),
		_wish("w2", 2, 1, "WARM_SUN"),
		_wish("w3", 3, 1, "WARM_SUN"),
		_wish("w4", 1, 2, "SOFT_SHADE"),
	]
	var partial_level: LevelData = _level(5, 4, 0, [], [], partial_wishes)
	ok = _check(partial_level != null, "warmth fixture parses") and ok
	if partial_level == null:
		return ok
	var partial: LightSolver.SolveResult = LightSolver.solve(partial_level, SimState.initial(partial_level))
	ok = _check(partial.total_wishes == 4, "four wishes are counted") and ok
	ok = _check(partial.satisfied_count == 3, "three of four wishes are satisfied") and ok
	ok = _check(partial.warmth_factor == 0.75,
			"warmth_factor is exactly 0.75 (got %s)" % str(partial.warmth_factor)) and ok
	ok = _check(not partial.solved, "three of four wishes is not solved") and ok

	var full_wishes: Array = [
		_wish("w1", 1, 1, "WARM_SUN"),
		_wish("w2", 2, 1, "WARM_SUN"),
		_wish("w3", 3, 1, "WARM_SUN"),
		_wish("w4", 1, 2, "WARM_SUN"),
	]
	var full_level: LevelData = _level(5, 4, 0, [], [], full_wishes)
	var full: LightSolver.SolveResult = LightSolver.solve(full_level, SimState.initial(full_level))
	ok = _check(full.satisfied_count == 4, "four of four wishes are satisfied") and ok
	ok = _check(full.warmth_factor == 1.0,
			"warmth_factor is exactly 1.0 (got %s)" % str(full.warmth_factor)) and ok
	ok = _check(full.solved, "four of four wishes is solved") and ok
	return ok


func test_command_history_undo() -> bool:
	var ok: bool = true
	var state: SimState = SimState.new()
	state.sun_angle = 2
	state.prop_states["mir"] = 0
	state.lantern_charge["lan"] = 1
	var history: CommandHistory = CommandHistory.new()
	ok = _check(not history.can_undo(), "a fresh history cannot undo") and ok

	history.record_sun(2, 3, state.lantern_charge)
	state.sun_angle = 3
	state.lantern_charge["lan"] = 0
	ok = _check(history.undo(state), "undo returns true after a sun shift") and ok
	ok = _check(state.sun_angle == 2, "undo restores the sun angle") and ok
	ok = _check(state.lantern_charge.get("lan", -1) == 1,
			"sun undo restores the lantern charge") and ok

	history.record_prop("mir", 0, 1, state.lantern_charge)
	state.prop_states["mir"] = 1
	state.lantern_charge["lan"] = 0
	ok = _check(history.undo(state), "undo returns true after a prop interaction") and ok
	ok = _check(state.prop_states.get("mir", -1) == 0, "undo restores the prop state") and ok
	ok = _check(state.sun_angle == 2, "a prop undo leaves the sun angle alone") and ok
	ok = _check(state.lantern_charge.get("lan", -1) == 1,
			"prop undo restores the lantern charge") and ok
	ok = _check(not history.can_undo(), "the history is empty after both undos") and ok
	ok = _check(not history.undo(state), "undo returns false on an empty history") and ok
	return ok


func test_level_data_rejects() -> bool:
	var ok: bool = true
	ok = _check(_level(5, 4, 0) != null, "the valid base fixture parses") and ok

	var out_of_bounds: Dictionary = _raw(5, 4, 0)
	out_of_bounds["tiles"] = [_tile(9, 0, "wall")]
	ok = _check(LevelData.from_dict(out_of_bounds, "<test 1>") == null,
			"from_dict rejects an out-of-bounds tile") and ok

	var unknown_type: Dictionary = _raw(5, 4, 0)
	unknown_type["tiles"] = [_tile(1, 1, "lava")]
	ok = _check(LevelData.from_dict(unknown_type, "<test 2>") == null,
			"from_dict rejects an unknown tile type") and ok

	var missing_field: Dictionary = _raw(5, 4, 0)
	missing_field.erase("act")
	ok = _check(LevelData.from_dict(missing_field, "<test 3>") == null,
			"from_dict rejects a missing required field") and ok

	# Parsing checks bounds. The level validator also checks walkability.
	var spawn_on_wall: Dictionary = _raw(5, 4, 0)
	spawn_on_wall["player_spawn"] = [1, 1]
	spawn_on_wall["tiles"] = [_tile(1, 1, "wall")]
	spawn_on_wall["wishes"] = [_wish("w", 2, 2, "WARM_SUN")]
	var wall_spawn_level: LevelData = LevelData.from_dict(spawn_on_wall, "<test 4>")
	ok = _check(wall_spawn_level != null, "a spawn-on-wall level parses as data") and ok
	if wall_spawn_level != null:
		var problems: Array[String] = LevelValidator.validate(wall_spawn_level)
		var reported: bool = false
		for problem: String in problems:
			if problem.contains("player_spawn") and problem.contains("not walkable"):
				reported = true
		ok = _check(reported, "validate() rejects a spawn on a wall") and ok
	return ok


func test_solve_determinism() -> bool:
	var ok: bool = true
	var tiles: Array = [_tile(0, 0, "wall", 2), _tile(5, 0, "puddle", 0)]
	var props: Array = [
		_prop("mir", "mirror", 1, 2, 0, 0),
		_prop("pri", "prism", 1, 1, 0, 0),
		_prop("glass", "stained_glass", 3, 1, 0, 0),
		_prop("lan", "lantern", 4, 2, 0, 0),
	]
	var level: LevelData = _level(7, 5, 1, tiles, props, [_wish("w", 3, 1, "ROSE_LIGHT")])
	ok = _check(level != null, "determinism fixture parses") and ok
	if level == null:
		return ok
	var state: SimState = SimState.initial(level)
	var first: LightSolver.SolveResult = LightSolver.solve(level, state)
	var second: LightSolver.SolveResult = LightSolver.solve(level, state)
	ok = _check(first.light.size() == second.light.size(),
			"both solves allocate the same light array") and ok
	var mismatches: int = 0
	var count: int = mini(first.light.size(), second.light.size())
	for i: int in count:
		if first.light[i] != second.light[i]:
			mismatches += 1
	ok = _check(mismatches == 0, "two solves of the same state give identical light") and ok
	ok = _check(first.beams.size() == second.beams.size(),
			"two solves produce the same beam count") and ok
	ok = _check(first.satisfied_count == second.satisfied_count,
			"two solves agree on the satisfied count") and ok
	return ok


func test_sim_state_key() -> bool:
	var ok: bool = true
	var props: Array = [
		_prop("mir", "mirror", 1, 1, 0, 0),
		_prop("lan", "lantern", 2, 1, 0, 0),
	]
	var level: LevelData = _level(5, 3, 2, [], props)
	ok = _check(level != null, "key fixture parses") and ok
	if level == null:
		return ok

	var a: SimState = SimState.initial(level)
	var b: SimState = SimState.initial(level)
	ok = _check(a.key() == b.key(), "the same state has a stable key") and ok

	var sun_changed: SimState = a.copy()
	sun_changed.sun_angle = 5
	ok = _check(sun_changed.key() != a.key(), "changing the sun angle changes the key") and ok

	var prop_changed: SimState = a.copy()
	prop_changed.prop_states["mir"] = 1
	ok = _check(prop_changed.key() != a.key(), "changing a prop state changes the key") and ok

	var charge_changed: SimState = a.copy()
	charge_changed.lantern_charge["lan"] = 1
	ok = _check(charge_changed.key() != a.key(), "changing a lantern charge changes the key") and ok

	var reordered: SimState = SimState.new()
	reordered.sun_angle = a.sun_angle
	reordered.lantern_charge["lan"] = 0
	reordered.prop_states["lan"] = 0
	reordered.prop_states["mir"] = 0
	ok = _check(reordered.key() == a.key(), "the key ignores dictionary insertion order") and ok
	return ok


## Every level the game ships must have a card, and every card must name an
## archetype the sprite generator can actually draw. A missing caption is
## silent in the journal, so it has to be caught here.
func test_postcards_cover_every_level() -> bool:
	var cards: Array[Dictionary] = PostcardLibrary.all()
	_check(cards.size() == 28, "28 postcards (%d)" % cards.size())
	var archetypes: PackedStringArray = CharacterSpriteGen.archetype_names()
	var seen: Dictionary[String, bool] = {}
	for entry: Dictionary in cards:
		var id: String = str(entry.get("id", ""))
		_check(not seen.has(id), "card id unique (%s)" % id)
		seen[id] = true
		_check(not str(entry.get("title", "")).is_empty(), "%s has a title" % id)
		_check(str(entry.get("caption", "")).length() >= 24, "%s caption is a sentence" % id)
		_check(archetypes.has(str(entry.get("who", ""))), "%s who is drawable (%s)" % [id, entry.get("who")])
		_check(int(entry.get("act", 0)) in [1, 2, 3, 4], "%s act in range" % id)
		_check(str(id).begins_with("A%d" % int(entry.get("act", 0))), "%s id matches act" % id)
	_check(PostcardLibrary.title_for("A1-01") == "Ginger on Cold Stone", "lookup by id")
	_check(PostcardLibrary.for_level("A9-99").is_empty(), "unknown id is empty")
	return true


## The move list has to be as long as the depth it was found at, and replaying
## it has to actually solve the level. Both halves matter: a hint that is one
## move short is worse than no hint.
func test_bfs_solution_replays() -> bool:
	for level_path: String in ["res://data/levels/A1-01.json", "res://data/levels/A1-02.json"]:
		var level: LevelData = LevelData.from_json(level_path)
		if level == null:
			_check(false, "%s loads" % level_path)
			continue
		var depth: int = LevelValidator.bfs_min_moves(level)
		var moves: Array[Dictionary] = LevelValidator.bfs_solution(level)
		_check(moves.size() == depth, "%s solution length %d == depth %d" % [level.id, moves.size(), depth])
		var state: SimState = SimState.initial(level)
		for move: Dictionary in moves:
			if str(move.get("kind", "")) == "sun":
				state.sun_angle = posmod(state.sun_angle + int(move.get("step", 0)), 8)
			else:
				var prop_id: String = str(move.get("id", ""))
				var prop: LevelData.PropSpec = level.prop_by_id(prop_id)
				if prop == null:
					continue
				var count: int = GridTypes.prop_state_count(prop.type)
				state.prop_states[prop_id] = posmod(state.prop_states.get(prop_id, prop.state) + 1, count)
			state.lantern_charge = SimState.copy_int_dict(LightSolver.solve(level, state, false).next_lantern_charge)
		_check(LightSolver.solve(level, state, false).solved, "%s replay solves" % level.id)
	_check(LevelValidator.bfs_solution(null).is_empty(), "null level has no solution")
	return true


func _check(condition: bool, what: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("    FAILED: %s" % what)
	return condition


func _raw(width: int, height: int, sun: int) -> Dictionary:
	return {
		"id": "TEST",
		"act": 1,
		"grid_size": [width, height],
		"initial_sun_angle": sun,
		"player_spawn": [0, 0],
	}


func _level(width: int, height: int, sun: int, tiles: Array = [], props: Array = [], wishes: Array = []) -> LevelData:
	var d: Dictionary = _raw(width, height, sun)
	d["title"] = "Test"
	d["postcard_caption"] = "Test."
	d["tiles"] = tiles
	d["props"] = props
	d["wishes"] = wishes
	return LevelData.from_dict(d, "<fixture>")


func _tile(x: int, y: int, tile_type: String, elevation: int = 0) -> Dictionary:
	return {"x": x, "y": y, "type": tile_type, "elevation": elevation}


func _prop(id: String, prop_type: String, x: int, y: int, elevation: int = 0, state: int = 0) -> Dictionary:
	return {"id": id, "type": prop_type, "x": x, "y": y, "elevation": elevation, "state": state}


func _wish(id: String, x: int, y: int, need: String, targets: Array = []) -> Dictionary:
	return {"id": id, "who": "neighbor", "x": x, "y": y, "elevation": 0, "need": need, "targets": targets}


## Solves the level once at its initial angle and once at angle 4 (sun from the west).
func _solve_at_0_and_4(level: LevelData) -> Array[LightSolver.SolveResult]:
	var out: Array[LightSolver.SolveResult] = []
	var state: SimState = SimState.initial(level)
	out.append(LightSolver.solve(level, state))
	state.sun_angle = 4
	out.append(LightSolver.solve(level, state))
	return out


func _count_light(result: LightSolver.SolveResult, value: int) -> int:
	var total: int = 0
	for cell: int in result.light:
		if cell == value:
			total += 1
	return total
