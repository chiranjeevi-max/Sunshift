class_name WishTrackerHUD
extends Control

## A row of soft sunlit pips, one per wish in the courtyard. A pip fills when its
## wish is satisfied and the halo around every pip warms with the board, so the
## player feels progress instead of reading it.

const VIEW_H: int = 270
const PIP_SPACING: float = 13.0
const PIP_RADIUS: float = 3.2
const FLAG_POLL: float = 0.35

const GOLD: Color = Color(1.0, 0.86, 0.55)
const BRASS: Color = Color(0.72, 0.58, 0.33)
const HALO: Color = Color(1.0, 0.72, 0.36)
const COLD: Color = Color(0.36, 0.40, 0.48)

var _total: int = 0
var _satisfied: int = 0
var _warmth: float = 0.0
var _phase: float = 0.0
var _sway: bool = true
var _contrast: bool = false
var _flag_timer: float = 0.0


func _ready() -> void:
  name = "WishTrackerHUD"
  mouse_filter = Control.MOUSE_FILTER_IGNORE
  position = Vector2(9.0, float(VIEW_H) - 25.0)
  size = Vector2(120.0, 16.0)
  EventBus.board_evaluated.connect(_on_board_evaluated)
  EventBus.level_loaded.connect(_on_level_loaded)
  _read_flags()
  _seed_from_state()
  set_process(true)


func _process(delta: float) -> void:
  _phase += delta
  _flag_timer -= delta
  if _flag_timer <= 0.0:
    _flag_timer = FLAG_POLL
    _read_flags()
  queue_redraw()


func _draw() -> void:
  if _total <= 0:
    return
  var sway: float = 1.0 if _sway else 0.0
  var first: Vector2 = Vector2(6.0, 8.0)
  var last: Vector2 = Vector2(6.0 + float(_total - 1) * PIP_SPACING, 8.0)
  if _total > 1:
    draw_line(first, last, Color(BRASS, 0.30), 1.0)
  for i: int in _total:
    var bob: float = sin(_phase * 1.6 + float(i) * 0.9) * 1.1 * sway
    var centre: Vector2 = Vector2(6.0 + float(i) * PIP_SPACING, 8.0 + bob)
    if i < _satisfied:
      var breathe: float = 0.5 + 0.5 * sin(_phase * 2.1 + float(i) * 1.7) * sway
      var strength: float = 0.35 + _warmth * 0.45 + breathe * 0.10
      draw_circle(centre, PIP_RADIUS + 5.0, Color(HALO, 0.09 * strength))
      draw_circle(centre, PIP_RADIUS + 2.0, Color(HALO, 0.16 * strength))
      draw_circle(centre, PIP_RADIUS, GOLD)
      draw_circle(centre - Vector2(0.0, 1.0), PIP_RADIUS * 0.55, Color(1.0, 0.95, 0.80))
    else:
      var inside: float = 0.80 if _contrast else 0.55
      var rim: float = 0.98 if _contrast else 0.70
      draw_circle(centre, PIP_RADIUS - 1.0, Color(COLD, inside))
      draw_arc(centre, PIP_RADIUS, 0.0, TAU, 12, Color(BRASS, rim), 1.0, true)


## Re-reads the comfort flags at once, so the owning HUD can push a change through.
func refresh_flags() -> void:
  _read_flags()
  queue_redraw()


## Rebuilds the row from the live level and last solve, if either exists.
func _seed_from_state() -> void:
  var level: LevelData = GameState.current_level
  var declared: int = 0
  if level != null:
    declared = level.wishes.size()
    _total = declared
  var result: LightSolver.SolveResult = GameState.last_result()
  if result != null:
    _total = maxi(result.total_wishes, declared)
    _satisfied = clampi(result.satisfied_count, 0, _total)
    _warmth = clampf(result.warmth_factor, 0.0, 1.0)
  _resize()


func _resize() -> void:
  size = Vector2(maxf(24.0, float(_total) * PIP_SPACING + 4.0), 16.0)
  queue_redraw()


func _read_flags() -> void:
  _sway = not SaveManager.get_accessibility_flag("reduced_sway", false)
  _contrast = SaveManager.get_accessibility_flag("high_contrast", false)


func _on_board_evaluated(warmth: float, satisfied: int, total: int) -> void:
  _total = maxi(total, 0)
  _satisfied = clampi(satisfied, 0, _total)
  _warmth = clampf(warmth, 0.0, 1.0)
  _resize()


func _on_level_loaded(_level_id: String, _act: int) -> void:
  _seed_from_state()
