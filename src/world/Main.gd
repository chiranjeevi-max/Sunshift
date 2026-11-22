class_name Main
extends Node

## Thin host: owns the current screen and the fade. All game logic lives in the
## screens themselves and in GameState.

const TITLE_SCENE: String = "res://src/ui/TitleScreen.tscn"
const HUB_SCENE: String = "res://src/world/OverworldHub.tscn"
const COURTYARD_SCENE: String = "res://src/world/CourtyardLevel.tscn"
const POST_SOLVE_BEAT: float = 0.9

var _host: Node
var _fade: ColorRect
var _current: Node
var _advancing: bool = false


func _ready() -> void:
  _host = Node.new()
  _host.name = "SceneHost"
  add_child(_host)

  var fade_layer := CanvasLayer.new()
  fade_layer.name = "FadeLayer"
  fade_layer.layer = 90
  add_child(fade_layer)
  _fade = ColorRect.new()
  _fade.name = "Fade"
  _fade.color = Color(0.04, 0.05, 0.09, 0.0)
  _fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
  _fade.set_anchors_preset(Control.PRESET_FULL_RECT)
  fade_layer.add_child(_fade)

  EventBus.level_solved.connect(_on_level_solved)
  EventBus.level_loaded.connect(_on_level_loaded)

  if ResourceLoader.exists(TITLE_SCENE):
    show_scene(TITLE_SCENE)
  else:
    start_first_level()


func show_scene(path: String) -> void:
  if _current != null and is_instance_valid(_current):
    _current.queue_free()
  _current = null
  var packed: PackedScene = load(path) as PackedScene
  if packed == null:
    push_error("Main: cannot load scene %s" % path)
    return
  _current = packed.instantiate()
  _host.add_child(_current)


## Title hands off to the promenade, not to a courtyard: the hub is where the
## player learns the four districts exist.
func start_first_level() -> void:
  if GameState.level_ids.is_empty():
    push_error("Main: no levels found")
    return
  if ResourceLoader.exists(HUB_SCENE):
    show_scene(HUB_SCENE)
    return
  GameState.load_level(GameState.level_ids[0])
  show_scene(COURTYARD_SCENE)


func show_hub() -> void:
  if ResourceLoader.exists(HUB_SCENE):
    show_scene(HUB_SCENE)


func play_level(level_id: String) -> void:
  GameState.load_level(level_id)
  show_scene(COURTYARD_SCENE)


func next_level_id(after_id: String) -> String:
  var index: int = GameState.level_ids.find(after_id)
  if index == -1 or index + 1 >= GameState.level_ids.size():
    return ""
  return GameState.level_ids[index + 1]


func _on_level_loaded(_level_id: String, _act: int) -> void:
  _advancing = false


func _on_level_solved(level_id: String, _act: int) -> void:
  if _advancing:
    return
  _advancing = true
  await get_tree().create_timer(POST_SOLVE_BEAT).timeout
  if not is_inside_tree():
    return
  if not (_current is CourtyardLevel):
    return
  var following: String = next_level_id(level_id)
  # Finishing a level always used to jump straight to the next one. Now a
  # courtyard hands back to the promenade when the next level is in a different
  # district, so the walk between places survives and the acts stay distinct.
  if following.is_empty() or _act_of(following) != _act_of(level_id):
    show_hub()
    return
  play_level(following)


func _act_of(level_id: String) -> int:
  var digits: String = level_id.substr(1, 1)
  return int(digits) if digits.is_valid_int() else 0
