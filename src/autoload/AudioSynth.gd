extends Node

## Bakes sound effects at boot and caches the score for each district on demand.
##
## Synthesis is deliberately sample-based: AudioStreamGenerator filled per frame
## stutters on WebAssembly, so every stem is a pre-rendered looping
## AudioStreamWAV and all five share one length per district to stay locked.

const CROSSFADE_TIME: float = 1.2
const STEM_AMBIENCE: int = 0
const STEM_PIANO: int = 1
const STEM_KALIMBA: int = 2
const STEM_PAD: int = 3
const STEM_RESOLVE: int = 4
const STEM_COUNT: int = 5
const SILENT_DB: float = -60.0
const STEM_SYNTH_PATH: String = "res://src/audio/StemSynth.gd"
const FOLEY_SYNTH_PATH: String = "res://src/audio/FoleySynth.gd"
const CUE_PLAYERS: int = 6

var _music_by_district: Dictionary[int, AudioStreamSynchronized] = {}
var _foley: Dictionary[String, AudioStreamRandomizer] = {}
var _music_player: AudioStreamPlayer
var _cue_players: Array[AudioStreamPlayer] = []
var _cue_index: int = 0
var _district: int = -1
var _warmth: float = 0.0
var _target_warmth: float = 0.0
var _baked: bool = false


func _ready() -> void:
  _music_player = AudioStreamPlayer.new()
  _music_player.name = "MusicPlayer"
  _music_player.bus = "Music"
  add_child(_music_player)
  for i: int in CUE_PLAYERS:
    var player: AudioStreamPlayer = AudioStreamPlayer.new()
    player.name = "Cue%d" % i
    player.bus = "SFX"
    add_child(player)
    _cue_players.append(player)
  _bake()
  _connect_bus()


func _process(delta: float) -> void:
  if is_equal_approx(_warmth, _target_warmth):
    return
  var step: float = delta / CROSSFADE_TIME
  _warmth = move_toward(_warmth, _target_warmth, step)
  _apply_stem_volumes()


func is_ready() -> bool:
  return _baked


func get_music_stream(district: int) -> AudioStreamSynchronized:
  return _music_for(district)


func get_foley(cue: String) -> AudioStreamRandomizer:
  return _foley.get(cue)


func get_cue_names() -> PackedStringArray:
  var names: PackedStringArray = PackedStringArray()
  for cue: String in _foley:
    names.append(cue)
  names.sort()
  return names


func play_district(district: int) -> void:
  var stream: AudioStreamSynchronized = get_music_stream(district)
  if stream == null:
    return
  if _district == district and _music_player.playing:
    return
  _district = district
  _music_player.stream = stream
  _music_player.play()
  _apply_stem_volumes()


func play_cue(cue: String, pitch: float = 1.0) -> void:
  var pool: AudioStreamRandomizer = get_foley(cue)
  if pool == null or _cue_players.is_empty():
    return
  var player: AudioStreamPlayer = _cue_players[_cue_index]
  _cue_index = (_cue_index + 1) % _cue_players.size()
  player.stream = pool
  player.pitch_scale = clampf(pitch, 0.25, 4.0)
  player.play()


func set_warmth(warmth: float) -> void:
  _target_warmth = clampf(warmth, 0.0, 1.0)


func current_warmth() -> float:
  return _warmth


func _apply_stem_volumes() -> void:
  var stream: AudioStreamSynchronized = _music_player.stream
  if stream == null:
    return
  stream.set_sync_stream_volume(STEM_AMBIENCE, 0.0)
  stream.set_sync_stream_volume(STEM_PIANO, 0.0)
  stream.set_sync_stream_volume(STEM_KALIMBA, _fade_in(_warmth, 0.33))
  stream.set_sync_stream_volume(STEM_PAD, _fade_in(_warmth, 0.66))
  stream.set_sync_stream_volume(STEM_RESOLVE, 0.0 if _warmth >= 0.999 else SILENT_DB)


func _fade_in(warmth: float, threshold: float) -> float:
  if warmth <= threshold:
    return SILENT_DB
  var t: float = (warmth - threshold) / maxf(1.0 - threshold, 0.001)
  return lerpf(SILENT_DB, 0.0, clampf(t, 0.0, 1.0))


func _bake() -> void:
  var foley_synth: GDScript = load(FOLEY_SYNTH_PATH) as GDScript
  if foley_synth != null:
    var built: Variant = foley_synth.call("build_all")
    if built is Dictionary:
      for cue: String in built as Dictionary:
        var pool: Variant = (built as Dictionary)[cue]
        if pool is AudioStreamRandomizer:
          _foley[cue] = pool as AudioStreamRandomizer
  _baked = true


func _music_for(district: int) -> AudioStreamSynchronized:
  var key: int = clampi(district, 0, 3)
  var cached: AudioStreamSynchronized = _music_by_district.get(key)
  if cached != null:
    return cached
  var synth: GDScript = load(STEM_SYNTH_PATH) as GDScript
  if synth == null:
    return null
  var stems: Variant = synth.call("build", key)
  if not (stems is Array) or (stems as Array).is_empty():
    return null
  var synced: AudioStreamSynchronized = _wrap_synchronized(stems as Array)
  _music_by_district[key] = synced
  return synced


func _wrap_synchronized(stems: Array) -> AudioStreamSynchronized:
  var synced: AudioStreamSynchronized = AudioStreamSynchronized.new()
  synced.set_stream_count(STEM_COUNT)
  for i: int in mini(stems.size(), STEM_COUNT):
    var stream: Variant = stems[i]
    if stream is AudioStreamWAV:
      synced.set_sync_stream(i, stream as AudioStreamWAV)
  return synced


func _connect_bus() -> void:
  var bus: Node = get_node_or_null("/root/EventBus")
  if bus == null:
    return
  if bus.has_signal("audio_cue"):
    bus.connect("audio_cue", _on_audio_cue)
  if bus.has_signal("level_loaded"):
    bus.connect("level_loaded", _on_level_loaded)
  if bus.has_signal("warmth_changed"):
    bus.connect("warmth_changed", _on_warmth_changed)


func _on_audio_cue(cue: String, pitch: float) -> void:
  play_cue(cue, pitch)


func _on_level_loaded(_level_id: String, act: int) -> void:
  play_district(clampi(act - 1, 0, 3))
  set_warmth(0.0)
  _warmth = 0.0
  _apply_stem_volumes()


func _on_warmth_changed(warmth: float) -> void:
  set_warmth(warmth)
