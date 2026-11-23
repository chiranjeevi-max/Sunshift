extends Node

## Renders a scene to a PNG so it can be looked at. Headless has no renderer,
## so this must run with a real window.

var _out: String = "res://build/captures/hub.png"
var _scene: String = "res://src/world/OverworldHub.tscn"
var _level: String = ""
var _solve: bool = false
var _journal: bool = false
var _ui: String = ""
var _frames: int = 6


func _ready() -> void:
  for arg: String in OS.get_cmdline_user_args():
    if arg.begins_with("--out="):
      _out = arg.substr(6)
    elif arg.begins_with("--scene="):
      _scene = arg.substr(8)
    elif arg.begins_with("--level="):
      _level = arg.substr(8)
    elif arg == "--solve":
      _solve = true
    elif arg == "--journal":
      _journal = true
    elif arg.begins_with("--ui="):
      _ui = arg.substr(5)
  _capture.call_deferred()


## Opens a single overlay by script name, for looking at it on its own.
func _open_ui(script_name: String) -> void:
  var path: String = "res://src/ui/%s.gd" % script_name
  var script: GDScript = load(path) as GDScript
  if script == null:
    push_error("capture: no %s" % path)
    return
  var built: Variant = script.new()
  if not (built is Node):
    return
  var layer: CanvasLayer = CanvasLayer.new()
  layer.layer = 6
  add_child(layer)
  layer.add_child(built as Node)
  if (built as Node).has_method("open"):
    (built as Node).call("open")


## Opens the keepsake journal with a believable amount of progress behind it.
func _open_journal() -> void:
  for id: String in GameState.level_ids:
    if id <= "A2-QC":
      GameState.completed[id] = true
      GameState.unlocked_postcards.append(id)
  var script: GDScript = load("res://src/ui/ShiftJournalUI.gd") as GDScript
  if script == null:
    push_error("capture: no ShiftJournalUI")
    return
  var built: Variant = script.new()
  if built is Node:
    add_child(built as Node)


## Replays the shortest solution so the shot shows a solved courtyard rather
## than the puzzle at rest.
func _apply_solution() -> void:
  var level: LevelData = GameState.current_level
  if level == null:
    return
  var moves: Array[Dictionary] = LevelValidator.bfs_solution(level)
  print("capture: solution has %d moves" % moves.size())
  for move: Dictionary in moves:
    if str(move.get("kind", "")) == "sun":
      GameState.shift_sun(int(move.get("step", 0)))
    else:
      GameState.interact_prop(str(move.get("id", "")))
  print("capture: solved=%s warmth=%.2f" % [GameState.last_result().solved,
    GameState.last_result().warmth_factor])


func _capture() -> void:
  if not _level.is_empty():
    GameState.load_level(_level)
    if GameState.current_level == null:
      push_error("capture: cannot load level %s" % _level)
      get_tree().quit(1)
      return
  if _solve and not _level.is_empty():
    _apply_solution()
  var packed: PackedScene = load(_scene) as PackedScene
  if packed == null:
    push_error("capture: cannot load %s" % _scene)
    get_tree().quit(1)
    return
  add_child(packed.instantiate())
  if _journal:
    _open_journal()
  if not _ui.is_empty():
    _open_ui(_ui)
  for _i: int in _frames:
    await get_tree().process_frame
  await RenderingServer.frame_post_draw
  var image: Image = get_viewport().get_texture().get_image()
  DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
  var err: int = image.save_png(_out)
  print("capture: %s -> %s (%dx%d) err=%d" % [_scene, _out, image.get_width(), image.get_height(), err])
  get_tree().quit(0 if err == OK else 1)
