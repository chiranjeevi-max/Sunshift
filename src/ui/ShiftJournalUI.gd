class_name ShiftJournalUI
extends Control

## The keepsake book. A two-page spread of the 28 postcards: unlocked cards are
## painted at 1.5x and sweep in behind the wax seal, locked ones stay a dim blank
## card with only the seal pressed into it. J or Esc closes and time resumes.

const VIEW_W: int = 480
const VIEW_H: int = 270
## 160x104 art at 1.5x: 240x156, so two cards fill the 480 px spread exactly.
const CARD_W: float = 240.0
const CARD_H: float = 156.0
const CELL_W: float = 240.0
const CELL_H: float = 156.0
const CELL_INSET: float = 4.0
const GRID_TOP: float = 40.0
const GRID_HEIGHT: float = 198.0
const REVEAL_TIME: float = 0.5
const SHADER_PATH: String = "res://src/shaders/postcard_reveal.gdshader"

const CREAM: Color = Color(1.0, 0.94, 0.80)
const BRASS: Color = Color(0.72, 0.56, 0.29)
const BRASS_LIGHT: Color = Color(0.95, 0.80, 0.48)

const LEVEL_IDS: Array[String] = [
  "A1-01", "A1-02", "A1-03", "A1-04", "A1-05", "A1-06", "A1-QC",
  "A2-07", "A2-08", "A2-09", "A2-10", "A2-11", "A2-12", "A2-QC",
  "A3-13", "A3-14", "A3-15", "A3-16", "A3-17", "A3-18", "A3-QC",
  "A4-19", "A4-20", "A4-21", "A4-22", "A4-23", "A4-24", "A4-QC",
]

static var _locked_tex: Texture2D = null

var _shader: Shader = null
var _scroll: ScrollContainer = null
var _grid: GridContainer = null
var _overlay: Control = null
var _header: Label = null
var _footer: Label = null
var _materials: Array[ShaderMaterial] = []
var _elapsed: float = 0.0
var _animating: bool = true
var _closing: bool = false
var _large_text: bool = false
var _contrast: bool = false
var _kept: int = 0


func _ready() -> void:
  name = "ShiftJournalUI"
  set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  mouse_filter = Control.MOUSE_FILTER_STOP
  process_mode = Node.PROCESS_MODE_ALWAYS
  _large_text = SaveManager.get_accessibility_flag("large_text", false)
  _contrast = SaveManager.get_accessibility_flag("high_contrast", false)
  _shader = load(SHADER_PATH) as Shader
  _build_book()
  EventBus.level_loaded.connect(_on_level_loaded)
  get_tree().paused = true
  set_process(true)
  queue_redraw()


func _exit_tree() -> void:
  var tree: SceneTree = get_tree()
  if tree != null:
    tree.paused = false


func _process(delta: float) -> void:
  if not _animating:
    return
  _elapsed += delta
  var settled: bool = true
  for i: int in _materials.size():
    var delay: float = minf(float(i) * 0.02, 0.15)
    var local: float = clampf((_elapsed - delay) / REVEAL_TIME, 0.0, 1.0)
    _materials[i].set_shader_parameter("reveal", local)
    if local < 1.0:
      settled = false
  if settled:
    _animating = false
    set_process(false)


func _unhandled_input(event: InputEvent) -> void:
  if event.is_action_pressed("journal") or event.is_action_pressed("ui_cancel") \
      or event.is_action_pressed("pause"):
    _close()
    get_viewport().set_input_as_handled()
    return
  if event.is_action_pressed("ui_down"):
    _scroll_by(48.0)
    get_viewport().set_input_as_handled()
  elif event.is_action_pressed("ui_up"):
    _scroll_by(-48.0)
    get_viewport().set_input_as_handled()
  elif event.is_action_pressed("ui_page_down"):
    _scroll_by(GRID_HEIGHT)
    get_viewport().set_input_as_handled()
  elif event.is_action_pressed("ui_page_up"):
    _scroll_by(-GRID_HEIGHT)
    get_viewport().set_input_as_handled()


func _close() -> void:
  if _closing:
    return
  _closing = true
  queue_free()


func _scroll_by(amount: float) -> void:
  if _scroll == null:
    return
  var bar: VScrollBar = _scroll.get_v_scroll_bar()
  var span: float = maxf(bar.max_value - bar.page, 0.0)
  bar.value = clampf(bar.value + amount, 0.0, span)


func _on_level_loaded(_level_id: String, _act: int) -> void:
  _close()


# --- BUILD -------------------------------------------------------------------

func _build_book() -> void:
  _count_kept()
  _build_header()
  _build_scroll()
  _build_overlay()
  _build_footer()


func _count_kept() -> void:
  _kept = 0
  for level_id: String in LEVEL_IDS:
    if _is_unlocked(level_id):
      _kept += 1


func _build_header() -> void:
  var size_px: int = 22 if _large_text else 18
  _header = _make_label("Keepsake Journal", size_px, CREAM)
  _header.position = Vector2(0.0, 6.0)
  _header.size = Vector2(VIEW_W, 24.0)
  _header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  add_child(_header)


func _build_footer() -> void:
  var size_px: int = 17 if _large_text else 14
  var kept_text: String = "all %d kept" % LEVEL_IDS.size() if _kept >= LEVEL_IDS.size() \
    else "%d of %d kept" % [_kept, LEVEL_IDS.size()]
  _footer = _make_label("J or Esc to close   \u00B7   %s" % kept_text, size_px, Color(BRASS_LIGHT, 0.9))
  _footer.position = Vector2(0.0, 243.0)
  _footer.size = Vector2(VIEW_W, 20.0)
  _footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  add_child(_footer)


func _build_scroll() -> void:
  _scroll = ScrollContainer.new()
  _scroll.name = "PostcardScroll"
  _scroll.position = Vector2(0.0, GRID_TOP)
  _scroll.size = Vector2(VIEW_W, GRID_HEIGHT)
  _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  _scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
  _scroll.mouse_filter = Control.MOUSE_FILTER_PASS
  _scroll.follow_focus = true
  add_child(_scroll)

  _grid = GridContainer.new()
  _grid.name = "PostcardGrid"
  _grid.columns = 2
  _grid.custom_minimum_size = Vector2(VIEW_W, 0.0)
  _grid.add_theme_constant_override("h_separation", 0)
  _grid.add_theme_constant_override("v_separation", 6)
  _scroll.add_child(_grid)

  for index: int in LEVEL_IDS.size():
    var level_id: String = LEVEL_IDS[index]
    _grid.add_child(_build_cell(level_id))

  var bar: VScrollBar = _scroll.get_v_scroll_bar()
  bar.value_changed.connect(_on_scrolled)


func _build_overlay() -> void:
  _overlay = Control.new()
  _overlay.name = "BookOverlay"
  _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
  _overlay.position = Vector2.ZERO
  _overlay.size = Vector2(VIEW_W, VIEW_H)
  add_child(_overlay)
  _overlay.draw.connect(_draw_overlay.bind(_overlay))


func _build_cell(level_id: String) -> Control:
  var cell := Control.new()
  cell.name = "Card_%s" % level_id
  cell.custom_minimum_size = Vector2(CELL_W, CELL_H)
  cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

  var unlocked: bool = _is_unlocked(level_id)
  var card := TextureRect.new()
  card.name = "Art"
  card.position = Vector2(CELL_INSET, 0.0)
  card.size = Vector2(CARD_W, CARD_H)
  card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
  card.stretch_mode = TextureRect.STRETCH_SCALE
  card.mouse_filter = Control.MOUSE_FILTER_IGNORE
  if unlocked:
    card.texture = PostcardArtGen.build(level_id, _act_for(level_id), _who_for(level_id))
    if _shader != null:
      var material := ShaderMaterial.new()
      material.shader = _shader
      material.set_shader_parameter("reveal", 0.0)
      card.material = material
      _materials.append(material)
  else:
    card.texture = _locked_texture()
    card.modulate = Color(0.92, 0.90, 0.92, 1.0)
  cell.add_child(card)
  return cell


func _make_label(text: String, size_px: int, colour: Color) -> Label:
  var label := Label.new()
  label.text = text
  label.mouse_filter = Control.MOUSE_FILTER_IGNORE
  label.add_theme_font_override("font", ThemeDB.fallback_font)
  label.add_theme_font_size_override("font_size", size_px)
  label.add_theme_color_override("font_color", colour)
  label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
  label.add_theme_constant_override("shadow_offset_x", 1)
  label.add_theme_constant_override("shadow_offset_y", 1)
  return label


# --- DATA --------------------------------------------------------------------

func _is_unlocked(level_id: String) -> bool:
  if GameState.unlocked_postcards.has(level_id):
    return true
  return SaveManager.unlocked_postcards.has(level_id)


static func _act_for(level_id: String) -> int:
  if level_id.length() >= 2 and level_id.begins_with("A"):
    return clampi(level_id.substr(1, 1).to_int(), 1, 4)
  return 1


static func _who_for(level_id: String) -> String:
  match level_id:
    "A1-01":
      return "cat"
    "A1-02":
      return "baker"
    "A1-06":
      return "guitarist"
    "A2-07":
      return "nurse"
    "A3-16":
      return "hibiscus"
    "A4-19":
      return "commuter"
    _:
      return ""


## A blank card with the wax seal pressed into it: what a postcard looks like
## before the courtyard it belongs to has been warmed.
static func _locked_texture() -> Texture2D:
  if _locked_tex != null:
    return _locked_tex
  var img: Image = Image.create_empty(PostcardArtGen.W, PostcardArtGen.H, false, Image.FORMAT_RGBA8)
  img.fill(Color(0.20, 0.17, 0.18))
  img.fill_rect(Rect2i(3, 3, PostcardArtGen.W - 6, PostcardArtGen.H - 6), Color(0.34, 0.30, 0.29))
  img.fill_rect(Rect2i(6, 6, PostcardArtGen.W - 12, PostcardArtGen.H - 12), Color(0.40, 0.35, 0.33))
  img.fill_rect(Rect2i(14, 16, PostcardArtGen.W - 28, 1), Color(0.49, 0.43, 0.39))
  img.fill_rect(Rect2i(14, 20, PostcardArtGen.W - 46, 1), Color(0.46, 0.40, 0.37))

  var centre := Vector2i(PostcardArtGen.W / 2, PostcardArtGen.H - 30)
  var wax := Color(0.46, 0.25, 0.25)
  var rim := Color(0.28, 0.15, 0.16)
  for y in range(centre.y - 14, centre.y + 15):
    for x in range(centre.x - 14, centre.x + 15):
      var d: float = Vector2(float(x - centre.x), float(y - centre.y)).length()
      if d <= 10.5:
        img.set_pixel(x, y, wax)
      elif d <= 12.0:
        img.set_pixel(x, y, rim)
  for ray: int in 8:
    var angle: float = float(ray) * TAU / 8.0
    var px: int = centre.x + int(round(cos(angle) * 6.0))
    var py: int = centre.y + int(round(sin(angle) * 6.0))
    if px > 0 and px < PostcardArtGen.W - 1 and py > 0 and py < PostcardArtGen.H - 1:
      img.set_pixel(px, py, rim)
  _locked_tex = ImageTexture.create_from_image(img)
  return _locked_tex


# --- DRAW --------------------------------------------------------------------

func _draw() -> void:
  draw_rect(Rect2(0.0, 0.0, float(VIEW_W), float(VIEW_H)), Color(0.035, 0.030, 0.045, 0.96))
  draw_rect(Rect2(0.0, 30.0, float(VIEW_W), GRID_HEIGHT + 14.0), Color(0.11, 0.09, 0.08, 0.55))
  var rule: Color = Color(0.92, 0.76, 0.42, 0.9) if _contrast else Color(BRASS, 0.7)
  draw_line(Vector2(14.0, 31.0), Vector2(float(VIEW_W) - 14.0, 31.0), rule, 1.0)
  draw_line(Vector2(14.0, 239.0), Vector2(float(VIEW_W) - 14.0, 239.0), rule, 1.0)


func _draw_overlay(canvas: Control) -> void:
  canvas.draw_rect(Rect2(239.0, GRID_TOP, 2.0, GRID_HEIGHT), Color(0.03, 0.02, 0.03, 0.34))
  if _scroll == null:
    return
  var bar: VScrollBar = _scroll.get_v_scroll_bar()
  var span: float = bar.max_value - bar.page
  if span <= 0.0:
    return
  var track_top: float = GRID_TOP + 2.0
  var track_height: float = GRID_HEIGHT - 4.0
  var thumb_height: float = clampf(track_height * (bar.page / maxf(bar.max_value, 1.0)), 14.0, track_height)
  var ratio: float = clampf(float(bar.value) / span, 0.0, 1.0)
  var thumb_top: float = track_top + (track_height - thumb_height) * ratio
  canvas.draw_rect(Rect2(float(VIEW_W) - 3.0, track_top, 2.0, track_height),
    Color(BRASS, 0.22))
  canvas.draw_rect(Rect2(float(VIEW_W) - 3.0, thumb_top, 2.0, thumb_height),
    Color(BRASS_LIGHT, 0.8))


func _on_scrolled(_value: float) -> void:
  if _overlay != null:
    _overlay.queue_redraw()
