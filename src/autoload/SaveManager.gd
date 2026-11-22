extends Node

## Autoload: user://sunshift_save.json, written defensively. A missing, unreadable
## or corrupt file must never block boot — it just means "fresh save".

const SAVE_FILE_NAME: String = "sunshift_save.json"
const SAVE_PATH: String = "user://sunshift_save.json"
const SAVE_VERSION: int = 1

var completed_levels: Dictionary[String, bool] = {}
var unlocked_postcards: Array[String] = []
var current_district: int = 0
var audio_volumes: Dictionary[String, float] = {}
var accessibility_flags: Dictionary[String, bool] = {}


func _init() -> void:
  load_save()


func save() -> void:
  var data: Dictionary = {
    "version": SAVE_VERSION,
    "completed_levels": completed_levels,
    "unlocked_postcards": unlocked_postcards,
    "current_district": current_district,
    "audio_volumes": audio_volumes,
    "accessibility_flags": accessibility_flags,
  }
  var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
  if file == null:
    push_warning("SaveManager: cannot write %s (error %d)" % [SAVE_PATH, FileAccess.get_open_error()])
    return
  file.store_string(JSON.stringify(data, "  "))
  file.close()


## Reads the save, silently keeping defaults on any corruption. Never throws.
func load_save() -> void:
  _clear()
  if not FileAccess.file_exists(SAVE_PATH):
    return
  var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
  if file == null:
    push_warning("SaveManager: cannot read %s (error %d)" % [SAVE_PATH, FileAccess.get_open_error()])
    return
  var text: String = file.get_as_text()
  file.close()
  var parsed: Variant = JSON.parse_string(text)
  if not (parsed is Dictionary):
    push_warning("SaveManager: %s is not valid JSON, starting fresh" % SAVE_PATH)
    return
  var data: Dictionary = parsed as Dictionary

  var completed_value: Variant = data.get("completed_levels", {})
  if completed_value is Dictionary:
    for key: Variant in (completed_value as Dictionary):
      if key is String:
        completed_levels[String(key)] = bool((completed_value as Dictionary)[key])

  var postcards_value: Variant = data.get("unlocked_postcards", [])
  if postcards_value is Array:
    for item: Variant in (postcards_value as Array):
      if item is String and not unlocked_postcards.has(String(item)):
        unlocked_postcards.append(String(item))

  var district_value: Variant = data.get("current_district", 0)
  if _is_number(district_value):
    current_district = int(district_value)

  var volumes_value: Variant = data.get("audio_volumes", {})
  if volumes_value is Dictionary:
    for key: Variant in (volumes_value as Dictionary):
      if key is String and _is_number((volumes_value as Dictionary)[key]):
        audio_volumes[String(key)] = clampf(float((volumes_value as Dictionary)[key]), 0.0, 1.0)

  var flags_value: Variant = data.get("accessibility_flags", {})
  if flags_value is Dictionary:
    for key: Variant in (flags_value as Dictionary):
      if key is String:
        accessibility_flags[String(key)] = bool((flags_value as Dictionary)[key])


func reset() -> void:
  _clear()
  if not FileAccess.file_exists(SAVE_PATH):
    return
  var dir: DirAccess = DirAccess.open("user://")
  if dir == null:
    return
  var err: Error = dir.remove(SAVE_FILE_NAME)
  if err != OK:
    push_warning("SaveManager: cannot delete %s (error %d)" % [SAVE_PATH, err])


func is_completed(level_id: String) -> bool:
  return completed_levels.get(level_id, false)


func mark_completed(level_id: String) -> void:
  if level_id.is_empty() or completed_levels.get(level_id, false):
    return
  completed_levels[level_id] = true
  save()


func unlock_postcard(postcard_id: String) -> void:
  if postcard_id.is_empty() or unlocked_postcards.has(postcard_id):
    return
  unlocked_postcards.append(postcard_id)
  save()


func set_audio_volume(bus: String, v: float) -> void:
  var value: float = clampf(v, 0.0, 1.0)
  audio_volumes[bus] = value
  var index: int = AudioServer.get_bus_index(bus)
  if index >= 0:
    AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
    AudioServer.set_bus_mute(index, value <= 0.0)
  save()


func set_accessibility_flag(key: String, v: bool) -> void:
  if key.is_empty():
    return
  accessibility_flags[key] = v
  save()


func get_accessibility_flag(key: String, fallback: bool = false) -> bool:
  return accessibility_flags.get(key, fallback)


func get_audio_volume(bus: String, fallback: float = 1.0) -> float:
  return audio_volumes.get(bus, fallback)


func _clear() -> void:
  completed_levels.clear()
  unlocked_postcards.clear()
  current_district = 0
  audio_volumes.clear()
  accessibility_flags.clear()


func _is_number(value: Variant) -> bool:
  return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
