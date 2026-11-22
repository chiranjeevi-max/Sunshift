extends Node

## Autoload: golden-hour colour direction. Eases warmth towards the target the
## solver reports and hands out the district palettes the art layer paints with.

const PALETTE_PATH: String = "res://data/palettes.json"
const SMOOTH_RATE: float = 4.0

var warmth_factor: float = 0.0
var district: int = 0

var _target_warmth: float = 0.0
var _palettes: Array[PackedColorArray] = []
var _palettes_loaded: bool = false
var _fallback: PackedColorArray = PackedColorArray()


func _ready() -> void:
  EventBus.warmth_changed.connect(_on_warmth_changed)


func _process(delta: float) -> void:
  if is_equal_approx(warmth_factor, _target_warmth):
    return
  warmth_factor = move_toward(warmth_factor, _target_warmth, SMOOTH_RATE * delta)


func set_warmth(v: float) -> void:
  _target_warmth = clampf(v, 0.0, 1.0)


func palette_for(district_index: int) -> PackedColorArray:
  _load_palettes()
  if _palettes.is_empty():
    return _fallback_palette()
  return _palettes[posmod(district_index, _palettes.size())]


func _on_warmth_changed(value: float) -> void:
  set_warmth(value)


func _load_palettes() -> void:
  if _palettes_loaded:
    return
  _palettes_loaded = true
  if not FileAccess.file_exists(PALETTE_PATH):
    return
  var file: FileAccess = FileAccess.open(PALETTE_PATH, FileAccess.READ)
  if file == null:
    return
  var text: String = file.get_as_text()
  file.close()
  var parsed: Variant = JSON.parse_string(text)
  if not (parsed is Dictionary):
    return
  var districts_value: Variant = (parsed as Dictionary).get("districts", null)
  if not (districts_value is Array):
    return
  for entry: Variant in (districts_value as Array):
    if not (entry is Dictionary):
      continue
    var colors := _parse_colors((entry as Dictionary).get("colors", null))
    if colors.size() > 0:
      _palettes.append(colors)


func _parse_colors(value: Variant) -> PackedColorArray:
  var out := PackedColorArray()
  if not (value is Array):
    return out
  for item: Variant in (value as Array):
    if item is String:
      out.append(Color.from_string(String(item), Color.MAGENTA))
    elif item is Array:
      var channels: Array = item as Array
      if channels.size() < 3:
        continue
      var r: float = _channel(channels[0])
      var g: float = _channel(channels[1])
      var b: float = _channel(channels[2])
      var a: float = 1.0
      if channels.size() > 3:
        a = _channel(channels[3])
      out.append(Color(r, g, b, a))
  return out


func _channel(value: Variant) -> float:
  if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
    return 0.0
  var number: float = float(value)
  if number > 1.0:
    return clampf(number / 255.0, 0.0, 1.0)
  return clampf(number, 0.0, 1.0)


## 24 warm stone/clay/water/metal ramp steps: boot must never fail on missing data.
func _fallback_palette() -> PackedColorArray:
  if _fallback.size() > 0:
    return _fallback
  _fallback = PackedColorArray([
    Color("#2B2A33"), Color("#4A4358"), Color("#7C7489"),
    Color("#9A9182"), Color("#C4B7A2"), Color("#E6D8BC"),
    Color("#52303C"), Color("#8E4A38"), Color("#C9734B"),
    Color("#B0563F"), Color("#D98554"), Color("#F2B47C"),
    Color("#4B352C"), Color("#7A5B3F"), Color("#A8815A"),
    Color("#2B3A52"), Color("#41627C"), Color("#6E96A8"),
    Color("#3A4634"), Color("#6F7F4C"), Color("#A8B468"),
    Color("#4E3D24"), Color("#9A7A3E"), Color("#DDB75F"),
  ])
  return _fallback
