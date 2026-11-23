class_name SunDialHUD
extends Control

## Displays the current sun angle, wish progress, and the interaction prompt.

const VIEW_W: int = 480
const VIEW_H: int = 270
const ARC_CENTRE: Vector2 = Vector2(240.0, 250.0)
const ARC_RADIUS: float = 242.0
const ARC_HALF_SPAN: float = 0.5235988
const TICKS: int = 8
const PROMPT_CENTRE: Vector2 = Vector2(240.0, 244.0)
const PROMPT_WIDE: Vector2 = Vector2(26.0, 12.0)
const WISH_SCRIPT: String = "res://src/ui/WishTrackerHUD.gd"
const PAUSE_SCRIPT: String = "res://src/ui/PauseAccessibilityMenu.gd"

const BRASS_DARK: Color = Color(0.28, 0.20, 0.10)
const BRASS: Color = Color(0.72, 0.56, 0.29)
const BRASS_LIGHT: Color = Color(0.95, 0.80, 0.48)
const CREAM: Color = Color(1.0, 0.94, 0.76)

var _target_angle: int = 2
var _shown_angle: float = 2.0
var _prompt_wanted: bool = false
var _prompt_alpha: float = 0.0
var _prompt_phase: float = 0.0
var _poll_timer: float = 0.0
var _flag_timer: float = 0.0
var _sway: bool = true
var _contrast: bool = false
var _wishes: Control = null
var _pause_menu: Control = null


func _ready() -> void:
  name = "SunDialHUD"
  mouse_filter = Control.MOUSE_FILTER_IGNORE
  set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  EventBus.sun_shifted.connect(_on_sun_shifted)
  EventBus.level_loaded.connect(_on_level_loaded)
  _read_flags()
  _seed_from_state()
  _build_wish_tracker()
  _build_pause_menu()
  set_process(true)


func _process(delta: float) -> void:
  _prompt_phase += delta
  _flag_timer -= delta
  if _flag_timer <= 0.0:
    _flag_timer = 0.35
    _read_flags()
  if _sway:
    _shown_angle = lerpf(_shown_angle, float(_target_angle), 1.0 - exp(-16.0 * delta))
  else:
    _shown_angle = float(_target_angle)
  _poll_timer -= delta
  if _poll_timer <= 0.0:
    _poll_timer = 0.1
    set_prompt(_player_has_target())
  var wanted: float = 1.0 if _prompt_wanted else 0.0
  if _sway:
    _prompt_alpha = move_toward(_prompt_alpha, wanted, delta * 6.0)
  else:
    _prompt_alpha = wanted
  queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
  if not event.is_action_pressed("pause"):
    return
  if _journal_open():
    return
  if _pause_menu != null and _pause_menu.has_method("open"):
    _pause_menu.call("open")
    get_viewport().set_input_as_handled()


func _draw() -> void:
  _draw_dial()
  _draw_prompt()


## Shows or hides the one-glyph interact hint. Polled from the player each 100 ms
## so the HUD never needs a wiring change in the level.
func set_prompt(visible: bool) -> void:
  if visible == _prompt_wanted:
    return
  _prompt_wanted = visible
  queue_redraw()


func _journal_open() -> bool:
  var layer: Node = get_parent()
  if layer == null:
    return false
  return layer.get_node_or_null("ShiftJournalUI") != null


func _player_has_target() -> bool:
  var player: Node = get_tree().get_first_node_in_group("player")
  if player == null or not player.has_method("nearest_prop"):
    return false
  return player.call("nearest_prop") != null


func _read_flags() -> void:
  _sway = not SaveManager.get_accessibility_flag("reduced_sway", false)
  _contrast = SaveManager.get_accessibility_flag("high_contrast", false)
  if _wishes != null and _wishes.has_method("refresh_flags"):
    _wishes.call("refresh_flags")


func _seed_from_state() -> void:
  var state: SimState = GameState.current_state
  if state == null:
    return
  _target_angle = posmod(state.sun_angle, TICKS)
  _shown_angle = float(_target_angle)
  queue_redraw()


func _build_wish_tracker() -> void:
  var script: GDScript = load(WISH_SCRIPT) as GDScript
  if script == null:
    return
  var created: Variant = script.new()
  if created is Control:
    _wishes = created as Control
    _wishes.name = "WishTrackerHUD"
    add_child(_wishes)


func _build_pause_menu() -> void:
  var script: GDScript = load(PAUSE_SCRIPT) as GDScript
  if script == null:
    return
  var created: Variant = script.new()
  if created is Control:
    _pause_menu = created as Control
    _pause_menu.name = "PauseAccessibilityMenu"
    add_child(_pause_menu)


func _on_sun_shifted(angle: int) -> void:
  _target_angle = posmod(angle, TICKS)
  queue_redraw()


func _on_level_loaded(_level_id: String, _act: int) -> void:
  _seed_from_state()


func _tick_angle(index: float) -> float:
  var t: float = clampf(index / float(TICKS - 1), 0.0, 1.0)
  return -PI * 0.5 - ARC_HALF_SPAN + ARC_HALF_SPAN * 2.0 * t


func _arc_point(angle: float, radius: float) -> Vector2:
  return ARC_CENTRE + Vector2(cos(angle), sin(angle)) * radius


func _draw_dial() -> void:
  var start: float = -PI * 0.5 - ARC_HALF_SPAN
  var end: float = -PI * 0.5 + ARC_HALF_SPAN
  var plinth: float = 0.34 if _contrast else 0.22
  draw_rect(Rect2(0.0, 0.0, float(VIEW_W), 26.0), Color(0.05, 0.04, 0.08, plinth))
  for ring: int in 3:
    draw_arc(ARC_CENTRE, ARC_RADIUS + float(ring) * 3.0, start, end, 64,
      Color(0.05, 0.04, 0.08, plinth * 0.22), 3.0, true)
  draw_arc(ARC_CENTRE, ARC_RADIUS, start, end, 64, BRASS_DARK, 3.0, true)
  # A 1.5px pen rasterises as one pixel on some segments and two on others,
  # which reads as a wobbling horizon. One pixel is the honest width.
  draw_arc(ARC_CENTRE, ARC_RADIUS, start, end, 64, BRASS, 1.0, true)

  var tick_colour: Color = Color(1.0, 0.90, 0.62, 0.95) if _contrast else Color(BRASS, 0.85)
  for i: int in TICKS:
    var a: float = _tick_angle(float(i))
    draw_line(_arc_point(a, ARC_RADIUS - 5.0), _arc_point(a, ARC_RADIUS + 2.5),
      tick_colour, 1.0, true)

  var notch: float = _tick_angle(_shown_angle)
  var seat: Vector2 = _arc_point(notch, ARC_RADIUS)
  draw_circle(seat, 6.0, Color(CREAM, 0.10))
  draw_circle(seat, 3.0, Color(CREAM, 0.26))
  draw_line(_arc_point(notch, ARC_RADIUS - 8.0), _arc_point(notch, ARC_RADIUS + 5.0),
    CREAM, 2.0, true)
  draw_circle(seat, 2.0, Color(1.0, 0.98, 0.90))


## Draws the Space keycap at viewport resolution to keep its edges crisp.
func _draw_prompt() -> void:
  if _prompt_alpha <= 0.02:
    return
  var bob: float = roundf(sin(_prompt_phase * 2.4) * 1.3) if _sway else 0.0
  var centre: Vector2 = (PROMPT_CENTRE + Vector2(0.0, bob)).round()
  var plate: Rect2 = Rect2(centre - (PROMPT_WIDE * 0.5).floor(), PROMPT_WIDE)
  var backing: float = 0.92 if _contrast else 0.78
  draw_rect(plate.grow(1.0), Color(BRASS_DARK, backing * _prompt_alpha))
  draw_rect(plate, Color(0.11, 0.08, 0.06, backing * _prompt_alpha))
  draw_rect(plate, Color(BRASS_LIGHT, 0.75 * _prompt_alpha), false, 1.0)
  var bar: Rect2 = Rect2(plate.position + Vector2(4.0, 6.0), Vector2(plate.size.x - 8.0, 2.0))
  draw_rect(bar, Color(CREAM, _prompt_alpha))
  draw_rect(Rect2(bar.position + Vector2(0.0, 1.0), bar.size), Color(BRASS, 0.45 * _prompt_alpha))
