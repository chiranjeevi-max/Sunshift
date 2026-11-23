class_name DistrictGate
extends Node2D

## One district doorway on the tram promenade. It owns no logic: the hub tells
## it which district it serves and whether that district is finished, and the
## gate just draws itself in that district's own palette so the four of them
## read as four different places before you have walked through any of them.

const W: int = 32
const H: int = 40

const MOTIF_STAIRS: int = 0
const MOTIF_VERANDA: int = 1
const MOTIF_CANAL: int = 2
const MOTIF_TRAM: int = 3

var district: int = 0
var act: int = 1
var motif: int = MOTIF_STAIRS
var lit: bool = false
var reachable: bool = false

var _palette: PixelCanvas.Palette
var _pulse: float = 0.0
var _glow: Node2D


func _process(delta: float) -> void:
  # Only the lamp breathes, and only while you can actually use the door.
  var want: bool = reachable
  if want != lit:
    _pulse = move_toward(_pulse, 1.0 if want else 0.0, delta * 4.0)
    queue_redraw()


func _draw() -> void:
  var stone: Color = _role("STONE_MID", Color(0.45, 0.42, 0.40))
  var stone_light: Color = _role("STONE_LIGHT", stone.lightened(0.2))
  var stone_dark: Color = _role("STONE_DARK", stone.darkened(0.35))
  var wood: Color = _role("WOOD_MID", Color(0.40, 0.26, 0.18))
  var wood_dark: Color = _role("WOOD_DARK", wood.darkened(0.3))
  var accent: Color = _role("ACCENT_LIGHT", Color(0.85, 0.62, 0.30))

  # Jambs and lintel: the door is a hole in the back wall, so it needs depth
  # rather than a border drawn around the outside.
  draw_rect(Rect2(0, 8, W, H - 8), stone_dark)
  draw_rect(Rect2(3, 12, W - 6, H - 12), stone)
  draw_rect(Rect2(6, 16, W - 12, H - 16), Color(0.05, 0.05, 0.08))

  # Vault: three stepped courses so the arch reads at 32 px wide.
  draw_rect(Rect2(0, 4, W, 6), stone_light)
  draw_rect(Rect2(3, 0, W - 6, 6), stone)
  draw_rect(Rect2(3, 0, W - 6, 2), stone_light)

  draw_rect(Rect2(0, 8, 3, H - 8), stone_light)
  draw_rect(Rect2(W - 3, 8, 3, H - 8), stone_dark)

  _draw_motif(wood, wood_dark, accent, stone_light)

  # Lamp above the arch. Unlit lamps stay visible but cold, so the promenade
  # shows you where you have not been yet.
  var lamp: Rect2 = Rect2(W * 0.5 - 4, -14, 8, 10)
  var lamp_colour: Color = accent if lit else Color(0.28, 0.28, 0.32)
  if _pulse > 0.0:
    lamp_colour = lamp_colour.lerp(accent.lightened(0.35), _pulse)
  # Iron bracket on one side, then the glass, then the cap. No mast: a mast
  # 14 px above the arch turns the lamp into a digit at this size.
  draw_rect(Rect2(lamp.position.x - 3, lamp.position.y + 2, 3, 2), stone_dark)
  draw_rect(lamp, lamp_colour)
  draw_rect(Rect2(lamp.position.x - 1, lamp.position.y - 2, lamp.size.x + 2, 2), stone_dark)
  draw_rect(Rect2(lamp.position.x, lamp.end.y, lamp.size.x, 1), stone_dark)
  if lit or _pulse > 0.0:
    var halo: float = (2.0 + _pulse * 4.0)
    var glow: Color = Color(accent.r, accent.g, accent.b, 0.10 + _pulse * 0.22)
    draw_rect(Rect2(lamp.position.x - halo, lamp.position.y - halo,
      lamp.size.x + halo * 2.0, lamp.size.y + halo * 2.0), glow)


func configure(p_district: int, p_motif: int) -> void:
  district = clampi(p_district, 0, 3)
  act = district + 1
  motif = clampi(p_motif, 0, 3)
  _palette = PixelCanvas.load_palette(district)


func set_lit(value: bool) -> void:
  if lit == value:
    return
  lit = value
  queue_redraw()


func set_reachable(value: bool) -> void:
  if reachable == value:
    return
  reachable = value
  queue_redraw()


func _role(role_name: String, fallback: Color) -> Color:
  if _palette == null:
    return fallback
  var c: Color = _palette.named(role_name)
  return c if c.a > 0.0 else fallback


func _draw_motif(wood: Color, wood_dark: Color, accent: Color, stone_light: Color) -> void:
  match motif:
    MOTIF_STAIRS:
      # Sun-bleached Mediterranean steps climbing out of the doorway.
      for step: int in 5:
        var w: int = 6 + step * 3
        var y: int = H - 6 - step * 5
        draw_rect(Rect2(16 - w * 0.5, y, w, 5), stone_light if step % 2 == 0 else Color(0.62, 0.56, 0.50))
        draw_rect(Rect2(16 - w * 0.5, y + 4, w, 1), Color(0.30, 0.26, 0.24))
    MOTIF_VERANDA:
      # Monsoon-washed veranda: two posts, a rail and a hanging cloth.
      draw_rect(Rect2(8, 20, 2, H - 20), wood)
      draw_rect(Rect2(22, 20, 2, H - 20), wood)
      draw_rect(Rect2(7, 26, 18, 2), wood_dark)
      draw_rect(Rect2(12, 20, 8, 12), accent)
      draw_rect(Rect2(12, 30, 8, 2), accent.darkened(0.3))
    MOTIF_CANAL:
      # Stone canal arch with water behind it.
      draw_rect(Rect2(8, 24, 16, H - 24), Color(0.16, 0.30, 0.34))
      draw_rect(Rect2(10, 28, 12, 3), Color(0.30, 0.52, 0.55))
      draw_rect(Rect2(11, 34, 10, 2), Color(0.26, 0.46, 0.50))
      draw_rect(Rect2(7, 22, 18, 3), stone_light)
    MOTIF_TRAM:
      # Coastal tram stop: a pole, a plate and a hanging bell.
      draw_rect(Rect2(15, 16, 2, H - 16), wood_dark)
      draw_rect(Rect2(9, 16, 14, 7), accent)
      draw_rect(Rect2(9, 21, 14, 2), accent.darkened(0.35))
      draw_rect(Rect2(19, 23, 5, 5), Color(0.80, 0.74, 0.52))
    _:
      draw_rect(Rect2(10, H - 16, 12, 16), wood)
