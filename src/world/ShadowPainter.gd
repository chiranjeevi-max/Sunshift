class_name ShadowPainter
extends Node2D

## Draws the twilight shadow map from a solve result. One soft quad per shaded
## open cell, plus a directional smear opposite the sun for high blockers.

const CELL: int = 16

var _level: LevelData
var _result: LightSolver.SolveResult
var _sun: Vector2i = Vector2i(1, 0)


func _draw() -> void:
  if _level == null or _result == null:
    return
  var sun: Vector2i = _sun
  for y: int in _level.height:
    for x: int in _level.width:
      if _result.light_at(x, y) != GridTypes.LightType.NONE:
        continue
      var tile: LevelData.TileSpec = _level.tile_at(x, y)
      if tile.type == GridTypes.TileType.VOID or tile.type == GridTypes.TileType.WALL:
        continue
      var origin: Vector2 = Vector2(x * CELL, y * CELL)
      draw_rect(Rect2(origin, Vector2(CELL, CELL)), Color(0.06, 0.07, 0.14, 0.36))
      if tile.elevation >= 1:
        var smear: Vector2 = Vector2(-sun.x, -sun.y) * CELL
        draw_rect(Rect2(origin + smear, Vector2(CELL, CELL)), Color(0.06, 0.07, 0.14, 0.16))


func paint(level: LevelData, solve: LightSolver.SolveResult, sun_angle: int) -> void:
  _level = level
  _result = solve
  _sun = GridTypes.sun_dir(sun_angle)
  queue_redraw()
