class_name PauseAccessibilityMenu
extends Control

## The only modal that owns the clock: opening it pauses the tree, closing it
## restores time. Sound levels and the three comfort flags are written straight
## through SaveManager, which is also what the HUD and the journal read back.

const VIEW_W: int = 480
const VIEW_H: int = 270

const CREAM: Color = Color(1.0, 0.94, 0.80)
const BRASS: Color = Color(0.72, 0.56, 0.29)
const BRASS_LIGHT: Color = Color(0.95, 0.80, 0.48)
const PAPER: Color = Color(0.11, 0.09, 0.10)

const AUDIO_BUSES: Array[String] = ["Music", "Ambience", "SFX"]
const AUDIO_LABELS: Array[String] = ["Music", "Ambience", "Effects"]
const FLAG_KEYS: Array[String] = ["high_contrast", "reduced_sway", "large_text"]
const FLAG_LABELS: Array[String] = ["High contrast", "Reduced sway", "Large text"]

var _panel: PanelContainer = null
var _column: VBoxContainer = null
var _margin: MarginContainer = null
var _veil: ColorRect = null
var _hint: Label = null
var _sliders: Dictionary[String, HSlider] = {}
var _checks: Dictionary[String, CheckButton] = {}
var _labels: Array[Label] = []
var _contrast: bool = false
var _large_text: bool = false


func _ready() -> void:
  name = "PauseAccessibilityMenu"
  set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  mouse_filter = Control.MOUSE_FILTER_STOP
  process_mode = Node.PROCESS_MODE_ALWAYS
  _build()
  _refresh_controls()
  _apply_flags()
  visible = false
  set_process(false)


func _unhandled_input(event: InputEvent) -> void:
  if not visible:
    return
  if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
    close()
    get_viewport().set_input_as_handled()


func _exit_tree() -> void:
  var tree: SceneTree = get_tree()
  if tree != null:
    tree.paused = false


func is_open() -> bool:
  return visible


func open() -> void:
  if visible:
    return
  _refresh_controls()
  _apply_flags()
  visible = true
  var tree: SceneTree = get_tree()
  if tree != null:
    tree.paused = true


func close() -> void:
  if not visible:
    return
  visible = false
  var tree: SceneTree = get_tree()
  if tree != null:
    tree.paused = false


func toggle() -> void:
  if visible:
    close()
  else:
    open()


func _build() -> void:
  _veil = ColorRect.new()
  _veil.name = "Veil"
  _veil.position = Vector2.ZERO
  _veil.size = Vector2(VIEW_W, VIEW_H)
  _veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
  _veil.color = Color(0.04, 0.03, 0.05, 0.80)
  add_child(_veil)

  _panel = PanelContainer.new()
  _panel.name = "Panel"
  _panel.mouse_filter = Control.MOUSE_FILTER_STOP
  add_child(_panel)

  _margin = MarginContainer.new()
  _margin.add_theme_constant_override("margin_left", 12)
  _margin.add_theme_constant_override("margin_right", 12)
  _margin.add_theme_constant_override("margin_top", 8)
  _margin.add_theme_constant_override("margin_bottom", 8)
  _panel.add_child(_margin)

  _column = VBoxContainer.new()
  _column.add_theme_constant_override("separation", 6)
  _margin.add_child(_column)

  _column.add_child(_make_label("The sun waits", 17))

  var split: HBoxContainer = HBoxContainer.new()
  split.add_theme_constant_override("separation", 12)
  _column.add_child(split)

  var sound: VBoxContainer = VBoxContainer.new()
  sound.add_theme_constant_override("separation", 3)
  sound.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  split.add_child(sound)
  sound.add_child(_make_label("Sound", 15, Color(BRASS_LIGHT, 0.9)))
  for i: int in AUDIO_BUSES.size():
    sound.add_child(_build_slider_row(AUDIO_BUSES[i], AUDIO_LABELS[i]))

  var comfort: VBoxContainer = VBoxContainer.new()
  comfort.add_theme_constant_override("separation", 1)
  comfort.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  split.add_child(comfort)
  comfort.add_child(_make_label("Comfort", 15, Color(BRASS_LIGHT, 0.9)))
  for i: int in FLAG_KEYS.size():
    comfort.add_child(_build_toggle(FLAG_KEYS[i], FLAG_LABELS[i]))

  var buttons: HBoxContainer = HBoxContainer.new()
  buttons.add_theme_constant_override("separation", 6)
  _column.add_child(buttons)
  buttons.add_child(_build_button("Resume", _on_resume_pressed))
  buttons.add_child(_build_button("Reset courtyard", _on_reset_pressed))
  buttons.add_child(_build_button("Quit", _on_quit_pressed))

  _hint = _make_label("Esc always closes this menu", 14, Color(BRASS_LIGHT, 0.8))
  _hint.position = Vector2(0.0, float(VIEW_H) - 22.0)
  _hint.size = Vector2(VIEW_W, 18.0)
  _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  add_child(_hint)
  _fit_panel.call_deferred()


func _build_slider_row(bus: String, label_text: String) -> HBoxContainer:
  var row: HBoxContainer = HBoxContainer.new()
  row.add_theme_constant_override("separation", 6)
  var label: Label = _make_label(label_text, 14)
  label.custom_minimum_size = Vector2(74.0, 0.0)
  row.add_child(label)

  var slider: HSlider = HSlider.new()
  slider.min_value = 0.0
  slider.max_value = 1.0
  slider.step = 0.05
  slider.custom_minimum_size = Vector2(96.0, 18.0)
  slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
  slider.value = SaveManager.get_audio_volume(bus, 1.0)
  slider.value_changed.connect(_on_audio_changed.bind(bus))
  row.add_child(slider)
  _sliders[bus] = slider
  return row


func _build_toggle(key: String, label_text: String) -> CheckButton:
  var check: CheckButton = CheckButton.new()
  check.text = label_text
  check.custom_minimum_size = Vector2(0.0, 20.0)
  check.add_theme_font_override("font", ThemeDB.fallback_font)
  check.add_theme_font_size_override("font_size", 14)
  check.add_theme_color_override("font_color", CREAM)
  check.button_pressed = SaveManager.get_accessibility_flag(key, false)
  check.toggled.connect(_on_flag_toggled.bind(key))
  _checks[key] = check
  return check


func _build_button(text: String, action: Callable) -> Button:
  var button: Button = Button.new()
  button.text = text
  button.custom_minimum_size = Vector2(0.0, 22.0)
  button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  button.add_theme_font_override("font", ThemeDB.fallback_font)
  button.add_theme_font_size_override("font_size", 14)
  button.add_theme_color_override("font_color", CREAM)
  button.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.86))
  button.add_theme_color_override("font_pressed_color", Color(1.0, 0.90, 0.66))
  button.add_theme_stylebox_override("normal", _button_box(Color(0.17, 0.13, 0.12, 0.95), Color(BRASS, 0.55)))
  button.add_theme_stylebox_override("hover", _button_box(Color(0.25, 0.19, 0.15, 0.98), Color(BRASS_LIGHT, 0.9)))
  button.add_theme_stylebox_override("pressed", _button_box(Color(0.32, 0.24, 0.16, 1.0), Color(BRASS_LIGHT, 1.0)))
  button.add_theme_stylebox_override("focus", _button_box(Color(0.0, 0.0, 0.0, 0.0), Color(BRASS_LIGHT, 0.55)))
  button.pressed.connect(action)
  return button


func _button_box(fill: Color, edge: Color) -> StyleBoxFlat:
  var box: StyleBoxFlat = StyleBoxFlat.new()
  box.bg_color = fill
  box.border_color = edge
  box.set_border_width_all(1)
  box.set_corner_radius_all(2)
  box.set_content_margin_all(2.0)
  return box


func _make_label(text: String, size_px: int, colour: Color = CREAM) -> Label:
  var label: Label = Label.new()
  label.text = text
  label.mouse_filter = Control.MOUSE_FILTER_IGNORE
  label.add_theme_font_override("font", ThemeDB.fallback_font)
  label.add_theme_font_size_override("font_size", size_px)
  label.add_theme_color_override("font_color", colour)
  label.set_meta("base_size", size_px)
  _labels.append(label)
  return label


func _fit_panel() -> void:
  if _panel == null:
    return
  _style_panel()
  var wanted: Vector2 = _panel.get_combined_minimum_size()
  _panel.size = wanted
  _panel.position = ((Vector2(float(VIEW_W), float(VIEW_H)) - wanted) * 0.5).floor()


func _style_panel() -> void:
  var style: StyleBoxFlat = StyleBoxFlat.new()
  style.bg_color = Color(PAPER, 0.98 if _contrast else 0.94)
  style.border_color = Color(BRASS_LIGHT, 0.95) if _contrast else Color(BRASS, 0.7)
  style.set_border_width_all(2 if _contrast else 1)
  style.set_corner_radius_all(2)
  _panel.add_theme_stylebox_override("panel", style)


func _refresh_controls() -> void:
  for bus: String in _sliders:
    _sliders[bus].set_value_no_signal(SaveManager.get_audio_volume(bus, 1.0))
  for key: String in _checks:
    _checks[key].set_pressed_no_signal(SaveManager.get_accessibility_flag(key, false))


func _on_audio_changed(value: float, bus: String) -> void:
  SaveManager.set_audio_volume(bus, value)


func _on_flag_toggled(pressed: bool, key: String) -> void:
  SaveManager.set_accessibility_flag(key, pressed)
  _apply_flags()


func _apply_flags() -> void:
  _contrast = SaveManager.get_accessibility_flag("high_contrast", false)
  _large_text = SaveManager.get_accessibility_flag("large_text", false)
  _veil.color = Color(0.02, 0.02, 0.03, 0.90) if _contrast else Color(0.04, 0.03, 0.05, 0.80)
  var bump: int = 4 if _large_text else 0
  for label: Label in _labels:
    var base: int = int(label.get_meta("base_size", 14))
    label.add_theme_font_size_override("font_size", base + bump)
    if _contrast:
      label.add_theme_color_override("font_color", CREAM)
  for key: String in _checks:
    _checks[key].add_theme_font_size_override("font_size", 14 + bump)
  if _column != null:
    _column.add_theme_constant_override("separation", 3 if _large_text else 6)
  if _margin != null:
    var vertical: int = 4 if _large_text else 8
    _margin.add_theme_constant_override("margin_top", vertical)
    _margin.add_theme_constant_override("margin_bottom", vertical)
  if _hint != null:
    _hint.position.y = float(VIEW_H) - (26.0 if _large_text else 22.0)
  _fit_panel.call_deferred()


func _on_resume_pressed() -> void:
  close()


func _on_reset_pressed() -> void:
  GameState.reset_level()
  close()


func _on_quit_pressed() -> void:
  var tree: SceneTree = get_tree()
  if tree != null:
    tree.quit()
