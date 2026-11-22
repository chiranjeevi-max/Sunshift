class_name TitleScreen
extends Control

## Live title: a golden-hour sky, the wordmark, and one line of invitation.
## Any key starts the first courtyard.

const VIEW_W: int = 480
const VIEW_H: int = 270
const SUN_RADIUS: float = 26.0

var _sun_phase: float = 0.0
var _started: bool = false


func _ready() -> void:
  set_anchors_preset(Control.PRESET_FULL_RECT)
  mouse_filter = Control.MOUSE_FILTER_IGNORE
  set_process(true)


func _process(delta: float) -> void:
  _sun_phase += delta * 0.25
  queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
  if _started:
    return
  var key := event as InputEventKey
  var button := event as InputEventMouseButton
  if (key != null and key.pressed and not key.echo) or (button != null and button.pressed):
    _started = true
    var main := _find_main()
    if main != null:
      main.start_first_level()


func _draw() -> void:
  var sky_top := Color(0.16, 0.14, 0.28)
  var sky_low := Color(0.55, 0.33, 0.26)
  draw_rect(Rect2(Vector2.ZERO, Vector2(VIEW_W, VIEW_H)), sky_top)
  var band_height: float = VIEW_H * 0.62 / 18.0
  for band: int in 18:
    var t: float = float(band) / 17.0
    draw_rect(Rect2(0, float(band) * band_height, VIEW_W, band_height + 1.0),
      sky_top.lerp(sky_low, t * t))
  draw_rect(Rect2(0, VIEW_H * 0.62, VIEW_W, VIEW_H * 0.38), Color(0.13, 0.12, 0.18))

  var sun_y: float = VIEW_H * 0.50 + sin(_sun_phase) * 3.0
  var centre := Vector2(VIEW_W * 0.72, sun_y)
  draw_circle(centre + Vector2(0, 14), roundf(SUN_RADIUS * 1.9), Color(1.0, 0.72, 0.42, 0.08))
  draw_circle(centre + Vector2(0, 8), roundf(SUN_RADIUS * 1.35), Color(1.0, 0.76, 0.46, 0.14))
  draw_circle(centre, roundf(SUN_RADIUS), Color(1.0, 0.86, 0.60, 0.95))
  draw_circle(centre, roundf(SUN_RADIUS * 0.72), Color(1.0, 0.93, 0.74, 1.0))

  var skyline: PackedVector2Array = PackedVector2Array([
    Vector2(0, VIEW_H * 0.62), Vector2(0, VIEW_H * 0.55),
    Vector2(46, VIEW_H * 0.55), Vector2(46, VIEW_H * 0.48),
    Vector2(78, VIEW_H * 0.48), Vector2(78, VIEW_H * 0.58),
    Vector2(122, VIEW_H * 0.58), Vector2(122, VIEW_H * 0.43),
    Vector2(150, VIEW_H * 0.43), Vector2(150, VIEW_H * 0.60),
    Vector2(206, VIEW_H * 0.60), Vector2(206, VIEW_H * 0.50),
    Vector2(268, VIEW_H * 0.50), Vector2(268, VIEW_H * 0.61),
    Vector2(330, VIEW_H * 0.61), Vector2(330, VIEW_H * 0.46),
    Vector2(372, VIEW_H * 0.46), Vector2(372, VIEW_H * 0.57),
    Vector2(430, VIEW_H * 0.57), Vector2(430, VIEW_H * 0.63),
    Vector2(VIEW_W, VIEW_H * 0.63), Vector2(VIEW_W, VIEW_H),
    Vector2(0, VIEW_H),
  ])
  draw_colored_polygon(skyline, Color(0.10, 0.09, 0.15))

  var font: Font = ThemeDB.fallback_font
  draw_string(font, Vector2(40, 96), "SUNSHIFT", HORIZONTAL_ALIGNMENT_LEFT, -1, 40,
    Color(1.0, 0.93, 0.80))
  draw_string(font, Vector2(42, 122), "the last hour of daylight", HORIZONTAL_ALIGNMENT_LEFT,
    -1, 12, Color(1.0, 0.82, 0.62))
  if fmod(_sun_phase * 2.0, 2.0) < 1.4:
    draw_string(font, Vector2(42, VIEW_H - 42), "press any key", HORIZONTAL_ALIGNMENT_LEFT,
      -1, 12, Color(0.95, 0.90, 0.82))


func _find_main() -> Main:
  var node: Node = get_parent()
  while node != null:
    if node is Main:
      return node as Main
    node = node.get_parent()
  return null
