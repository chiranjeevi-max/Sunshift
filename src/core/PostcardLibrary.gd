class_name PostcardLibrary
extends RefCounted

## The keepsake journal's copy. Twenty-eight lines, one per courtyard, keyed by
## the same level ids the rest of the game uses, so a solved level always has a
## card and a card always has a level.

const PATH: String = "res://data/postcards.json"

static var _entries: Array[Dictionary] = []
static var _by_id: Dictionary[String, Dictionary] = {}
static var _loaded: bool = false


static func _load() -> void:
  if _loaded:
    return
  _loaded = true
  var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
  if file == null:
    push_error("PostcardLibrary: cannot open %s" % PATH)
    return
  var parsed: Variant = JSON.parse_string(file.get_as_text())
  file.close()
  if not (parsed is Dictionary):
    push_error("PostcardLibrary: %s is not a JSON object" % PATH)
    return
  var cards: Array = (parsed as Dictionary).get("postcards", []) as Array
  for raw: Variant in cards:
    if not (raw is Dictionary):
      continue
    var entry: Dictionary = raw as Dictionary
    var id: String = str(entry.get("id", ""))
    if id.is_empty():
      continue
    _entries.append(entry)
    _by_id[id] = entry


static func all() -> Array[Dictionary]:
  _load()
  return _entries.duplicate()


static func count() -> int:
  _load()
  return _entries.size()


static func for_level(level_id: String) -> Dictionary:
  _load()
  return _by_id.get(level_id, {})


static func title_for(level_id: String) -> String:
  return str(for_level(level_id).get("title", ""))


static func caption_for(level_id: String) -> String:
  return str(for_level(level_id).get("caption", ""))


static func who_for(level_id: String) -> String:
  return str(for_level(level_id).get("who", "elder_woman"))


static func act_for(level_id: String) -> int:
  return int(for_level(level_id).get("act", 1))


## Cards unlock in order, so the journal can show the unread ones as sealed.
static func unlocked_prefix(completed: Dictionary[String, bool]) -> int:
  _load()
  var run: int = 0
  for entry: Dictionary in _entries:
    if not completed.get(str(entry.get("id", "")), false):
      break
    run += 1
  return run
