class_name Backdrop
extends Node2D

## The air behind a courtyard. Levels are as small as 12x10 cells on a 480x270
## screen, so without this a courtyard reads as a floor tile dropped into space.
## It is drawn once and never redrawn: nothing here animates, and the light
## belongs to the beams, not to the sky.

const VIEW_W: int = 480
const VIEW_H: int = 270
const EDGE_BANDS: int = 48
const GLOW_STEPS: int = 26

var top_colour: Color = Color(0.07, 0.09, 0.18)
var bottom_colour: Color = Color(0.19, 0.17, 0.29)
var warm_colour: Color = Color(0.46, 0.31, 0.24)
var glow: Rect2 = Rect2()
var glow_strength: float = 0.9


func _draw() -> void:
  for y: int in VIEW_H:
    var t: float = float(y) / float(VIEW_H - 1)
    draw_rect(Rect2(0, y, VIEW_W, 1), top_colour.lerp(bottom_colour, t * t))
  _draw_glow()
  _draw_vignette()


func set_frame(level_rect: Rect2) -> void:
  glow = level_rect
  queue_redraw()


## A dusk halo around the courtyard: it makes the island feel lit from inside
## instead of cut out of the picture.
func _draw_glow() -> void:
  if glow.size.x <= 0.0 or glow.size.y <= 0.0:
    return
  var centre: Vector2 = glow.get_center()
  for step: int in GLOW_STEPS:
    var t: float = float(step) / float(GLOW_STEPS)
    var grow: Vector2 = glow.size * (0.10 + t * 0.9)
    var alpha: float = glow_strength * (1.0 - t) * (1.0 - t) * 0.11
    draw_rect(
      Rect2(centre - grow * 0.5, grow),
      Color(warm_colour.r, warm_colour.g, warm_colour.b, alpha)
    )


func _draw_vignette() -> void:
  var shade: Color = Color(0.02, 0.02, 0.05)
  for i: int in EDGE_BANDS:
    var t: float = 1.0 - float(i) / float(EDGE_BANDS)
    var alpha: float = 0.42 * t * t
    var c: Color = Color(shade.r, shade.g, shade.b, alpha)
    draw_rect(Rect2(0, i, VIEW_W, 1), c)
    draw_rect(Rect2(0, VIEW_H - 1 - i, VIEW_W, 1), c)
    draw_rect(Rect2(i, 0, 1, VIEW_H), c)
    draw_rect(Rect2(VIEW_W - 1 - i, 0, 1, VIEW_H), c)
