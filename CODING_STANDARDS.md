# Sunshift Coding Standards

Use `./verify.sh` to check your changes.

## 1. Engine and language

- **Godot 4.7.2 stable**, Compatibility renderer, `480×270` viewport,
  integer scaling. Do not change `project.godot` rendering/display settings
  without recording the reason in a commit message and a code comment.
- **Strictly typed GDScript, always.** `untyped_declaration` is an **error** in
  `project.godot`. Every variable, parameter, return value and member carries a
  type. Use `:=` only when the right-hand side already has a static type.
- Never use Godot 3 APIs. `TileMap` → `TileMapLayer`. `yield` → `await`.
  `export` → `@export`. `setget` → `set`/`get`.
- `get()`/`max()`/`min()`/`abs()`/`clamp()` return Variant — annotate the
  receiving variable or use `maxi`/`maxf`/`absf`/`clampf`.

## 2. Simulation

`src/core/` is **pure**. It contains no `Node`, no `SceneTree`, no `Tween`, no
`Timer`, no `Input`, no rendering, and no RNG. It is `RefCounted`/`Resource` and
static functions only, so the identical code runs in gameplay and in the
headless BFS solver.

If a gameplay behaviour needs randomness or timing, it belongs in `src/world/`
or `src/ui/`, never in `src/core/`.

**Determinism:** given the same `LevelData` and the same `SimState`,
`LightSolver.solve()` must return byte-identical results. No floats in the
satisfaction test path that can differ between runs (use integer counting, then
one division at the end). No `Dictionary` iteration order dependence in logic
that affects outcomes.

## 3. Generated art and audio

Tile, character, prop, and postcard art comes from `src/art/`. `src/audio/`
synthesizes the score and sound effects. Keep generation deterministic.
Run `./tools/audit_art.sh` to check the art and write previews.

## 4. Scenes and resources

- Verify affected scenes and `res://` paths after changing resources.
- Keep `preload()` and `load()` paths valid.
- Prefer `%UniqueName` for deep node access over long `$A/B/C/D` chains.

## 5. Testing gates

`./verify.sh` runs, in order:

1. `--import` (fresh checkout has no `.godot/`)
2. compile check of every `.gd` file (catches parse errors, including
   untyped-declaration errors)
3. `tests/test_*.gd` unit tests
4. `tests/verify_levels.gd` to prove all 28 levels solvable
5. `tools/smoke_*.tscn` scene checks

Use an isolated Godot `user://` profile because the scene checks write save
data. Test runners count failures and return a nonzero exit code on failure.

Tests return `true` on their last line so a test that dies mid-way is counted as
a failure rather than silently skipped.

## 6. Interaction and feel

- **No punishment.** No timers, no move limits, no failure states, no buzzer
  sounds. A missed beam produces a gentle reaction, never a penalty.
- Every player-facing action must be reversible: `Z`/`Backspace` undo, `R`
  reset. `CommandHistory` must restore lantern charge state exactly.
- Interaction prompts use iconography plus a one-glyph key hint. No text walls.

## 7. Style

- Use `snake_case` for functions, variables, and signals, `PascalCase` for
  classes and nodes, and `CONSTANT_CASE` for constants.
- Match the surrounding indentation and use one statement per line.
- Use comments to explain decisions the code cannot show.
- No `TODO` without a matching issue in the tracker.

## 8. Commits

- Maintainers sign and sign off their commits with `git commit -S -s`.
- Conventional Commits prefix (`feat:`, `fix:`, `test:`, `docs:`, `chore:`,
  `refactor:`, `perf:`), optional scope (`feat(core):`).
- Subject in the imperative, lowercase, ≤ 72 characters, no trailing period.
- Body only when it explains *why* or a non-obvious constraint — never a
  restatement of the diff. One logical change per commit.
