class_name OverworldHub
extends Node2D

## The coastal tram promenade that links the four districts. It is built in
## code from one small map so there is no scene to hand-edit: the gates read
## their state from GameState and the only thing you can do here is walk into a
## district you have not finished yet.

const CELL: int = 16
const VIEW_W: int = 480
const VIEW_H: int = 270
const COLS: int = 28
const ROWS: int = 16
const GATE_REACH: float = 30.0
const FRAME: float = 32.0
const COURTYARD_SCENE: String = "res://src/world/CourtyardLevel.tscn"

const HUB_DISTRICT: int = 2

## x of the left cell of each gate's doorway, and the motif drawn inside it.
const GATE_COLUMNS: Array[int] = [2, 8, 14, 20]
const GATE_MOTIFS: Array[int] = [
  DistrictGate.MOTIF_STAIRS,
  DistrictGate.MOTIF_VERANDA,
  DistrictGate.MOTIF_CANAL,
  DistrictGate.MOTIF_TRAM,
]

const FIRST_WALL_ROW: int = 4
const LAST_WALL_ROW: int = 6
const WALL_ROW: int = FIRST_WALL_ROW
const WALL_ROW_B: int = LAST_WALL_ROW
## Where the doorway meets the promenade, so gates sit inside the wall instead
## of standing on top of a garden ledge.
const GATE_BASE_Y: int = (LAST_WALL_ROW + 1) * CELL
const SPAWN_COL: int = 4
const SPAWN_ROW: int = 9

var _world: Node2D
var _ground: TileMapLayer
var _architecture: TileMapLayer
var _wall_shade: Node2D
var _gates: Array[DistrictGate] = []
var _player: Player
var _prompt: Node2D
var _active_gate: DistrictGate = null
var _entering: bool = false


func _ready() -> void:
  _build_backdrop()
  _build_world()
  _paint_map()
  _build_bounds()
  _build_gates()
  _build_player()
  _build_prompt()
  _refresh()
  _wall_shade.queue_redraw()
  EventBus.level_solved.connect(_on_level_solved)


func _unhandled_input(event: InputEvent) -> void:
  if _entering:
    return
  if event.is_action_pressed("interact") and _active_gate != null:
    _enter(_active_gate)
  elif event.is_action_pressed("journal"):
    _toggle_journal()


func _process(_delta: float) -> void:
  _scan_gates()


func _build_backdrop() -> void:
  var sky := ColorRect.new()
  sky.name = "SkyBackdrop"
  sky.position = Vector2.ZERO
  sky.size = Vector2(VIEW_W, VIEW_H)
  sky.color = Color(0.11, 0.13, 0.21)
  sky.z_index = -100
  add_child(sky)


func _build_world() -> void:
  _world = Node2D.new()
  _world.name = "HubWorld"
  _world.position = Vector2(
    float(VIEW_W - COLS * CELL) * 0.5,
    float(VIEW_H - ROWS * CELL) * 0.5
  )
  add_child(_world)

  var tileset := _build_tileset()
  _ground = _new_layer("GroundLayer", tileset)
  _world.add_child(_ground)

  var y_sort := Node2D.new()
  y_sort.name = "YSortWorld"
  y_sort.y_sort_enabled = true
  _world.add_child(y_sort)

  _architecture = _new_layer("ArchitectureLayer", tileset)
  _architecture.y_sort_enabled = false
  y_sort.add_child(_architecture)

  _wall_shade = Node2D.new()
  _wall_shade.name = "WallShade"
  y_sort.add_child(_wall_shade)
  _wall_shade.draw.connect(_draw_wall_shade)


func _build_tileset() -> TileSet:
  var script: GDScript = load("res://src/art/TilesetGenerator.gd") as GDScript
  if script == null:
    return null
  return script.call("build_tileset", HUB_DISTRICT) as TileSet


func _new_layer(node_name: String, tileset: TileSet) -> TileMapLayer:
  var layer := TileMapLayer.new()
  layer.name = node_name
  layer.tile_set = tileset
  layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  return layer


## The promenade floor for the player. Painted tiles cover only walls and
## railings, so without this the tram line and the sea are both open ground and
## Milo walks off the map behind the window.
func _build_bounds() -> void:
  var body := StaticBody2D.new()
  body.name = "HubBounds"
  body.collision_layer = 1
  body.collision_mask = 0
  _world.add_child(body)
  for rect: Rect2 in _solid_rects():
    var shape := CollisionShape2D.new()
    var box := RectangleShape2D.new()
    box.size = rect.size
    shape.shape = box
    shape.position = rect.position + rect.size * 0.5
    body.add_child(shape)


## Water is walkable tile art for the puzzles, but a canal you can stroll across
## is not a promenade: here everything except the floor blocks.
func _solid_rects() -> Array[Rect2]:
  var out: Array[Rect2] = []
  for y: int in ROWS:
    var run_start: int = -1
    for x: int in COLS + 1:
      var solid: bool = x < COLS and not _is_open(x, y)
      if solid and run_start < 0:
        run_start = x
      elif not solid and run_start >= 0:
        out.append(Rect2(run_start * CELL, y * CELL, (x - run_start) * CELL, CELL))
        run_start = -1
  # The floor runs to the last column, so the edge of the map is open ground.
  # Frame it, or Milo walks out of the promenade into the sky.
  var w: float = float(COLS * CELL)
  var h: float = float(ROWS * CELL)
  out.append(Rect2(-FRAME, -FRAME, w + FRAME * 2.0, FRAME))
  out.append(Rect2(-FRAME, h, w + FRAME * 2.0, FRAME))
  out.append(Rect2(-FRAME, 0.0, FRAME, h))
  out.append(Rect2(w, 0.0, FRAME, h))
  return out


func _is_open(x: int, y: int) -> bool:
  var tile: int = _tile_at(x, y)
  if tile == GridTypes.TileType.WATER:
    return false
  return GridTypes.tile_walkable(tile)


## Sea at both ends, a wall you can only pass through at a gate, and a tram
## track along the bottom where the line actually runs.
func _paint_map() -> void:
  for y: int in ROWS:
    for x: int in COLS:
      var tile: int = _tile_at(x, y)
      if tile == GridTypes.TileType.VOID:
        continue
      # Walls sit one level up so they cast the riser that makes them read as
      # a face rather than as wallpaper.
      var elevation: int = 1 if tile == GridTypes.TileType.WALL else 0
      var target: TileMapLayer = _ground
      if tile == GridTypes.TileType.WALL:
        target = _architecture
      var coords: Vector2i = Vector2i(tile, elevation)
      if target != null and target.tile_set != null:
        target.set_cell(Vector2i(x, y), 0, coords)


func _tile_at(x: int, y: int) -> int:
  if y <= 1:
    return GridTypes.TileType.WATER
  if y == 2:
    return GridTypes.TileType.RAILING
  if y >= FIRST_WALL_ROW and y <= LAST_WALL_ROW:
    return GridTypes.TileType.FLOOR if _is_doorway(x) else GridTypes.TileType.WALL
  if y >= 13:
    return GridTypes.TileType.WATER
  if y == 12:
    return GridTypes.TileType.RAILING
  return GridTypes.TileType.FLOOR


## A short falloff under the wall so it sits on the promenade instead of
## floating on it. Six pixels of alpha does more than any amount of extra
## brick detail at this scale.
func _draw_wall_shade() -> void:
  var top: float = float((LAST_WALL_ROW + 1) * CELL)
  for i: int in 8:
    var alpha: float = 0.40 * (1.0 - float(i) / 8.0)
    _wall_shade.draw_rect(
      Rect2(0.0, top + float(i), float(COLS * CELL), 1.0),
      Color(0.03, 0.04, 0.08, alpha)
    )


func _is_doorway(x: int) -> bool:
  for column: int in GATE_COLUMNS:
    if x == column or x == column + 1:
      return true
  return false


func _build_gates() -> void:
  for index: int in GATE_COLUMNS.size():
    var gate := DistrictGate.new()
    gate.name = "Gate%d" % index
    gate.configure(index, GATE_MOTIFS[index])
    gate.position = Vector2(
      float(GATE_COLUMNS[index] * CELL),
      float(GATE_BASE_Y - DistrictGate.H)
    )
    gate.y_sort_enabled = false
    _world.add_child(gate)
    _gates.append(gate)


func _build_player() -> void:
  _player = Player.new()
  _player.name = "Player"
  _world.add_child(_player)
  _player.place_at_cell(Vector2i(SPAWN_COL, SPAWN_ROW))


func _build_prompt() -> void:
  _prompt = Node2D.new()
  _prompt.name = "InteractPrompt"
  _prompt.visible = false
  _prompt.z_index = 40
  _prompt.draw.connect(_draw_prompt)
  add_child(_prompt)


func _draw_prompt() -> void:
  if _active_gate == null or _player == null:
    return
  if _player == null:
    return
  # The pip belongs over Milo, not over the door: it is a thing he can do.
  var at: Vector2 = _world.position + _player.position + Vector2(-4, -34)
  var bob: float = sin(float(Time.get_ticks_msec()) * 0.006) * 1.5
  _prompt.draw_rect(Rect2(at + Vector2(0, bob), Vector2(8, 8)), Color(0.98, 0.84, 0.48))
  _prompt.draw_rect(Rect2(at + Vector2(2, bob + 2.0), Vector2(4, 4)), Color(0.24, 0.16, 0.10))


func _scan_gates() -> void:
  var best: DistrictGate = null
  var best_distance: float = GATE_REACH
  if _player != null:
    for gate: DistrictGate in _gates:
      var distance: float = _player.position.distance_to(_gate_reach_point(gate))
      if distance <= best_distance:
        best_distance = distance
        best = gate
  if best == _active_gate:
    if best != null and _prompt.visible:
      _prompt.queue_redraw()
    return
  if _active_gate != null and is_instance_valid(_active_gate):
    _active_gate.set_reachable(false)
  _active_gate = best
  if _active_gate != null:
    _active_gate.set_reachable(true)
  _prompt.visible = _active_gate != null
  if _prompt.visible:
    _prompt.queue_redraw()


## Where the player has to stand for each door, so a test can prove that adding
## ground collision did not seal a gate.
func _gate_reach_points() -> Array[Vector2]:
  var out: Array[Vector2] = []
  for gate: DistrictGate in _gates:
    out.append(_gate_reach_point(gate))
  return out


## The patch of promenade directly in front of a door, which is the only place
## the door answers.
func _gate_reach_point(gate: DistrictGate) -> Vector2:
  return gate.position + Vector2(DistrictGate.W * 0.5, DistrictGate.H + 8.0)


func _refresh() -> void:
  for index: int in _gates.size():
    var act: int = index + 1
    _gates[index].set_lit(_solved_in_act(act) > 0)
  _apply_palette()


func _apply_palette() -> void:
  # The hub takes the sea's dusk grade but stays a touch cooler than any
  # district, so stepping through a gate feels like the sun coming up.
  var sky := get_node_or_null("SkyBackdrop") as ColorRect
  if sky == null:
    return
  var palette := PixelCanvas.load_palette(HUB_DISTRICT)
  var top: Color = palette.twilight[0] if not palette.twilight.is_empty() else sky.color
  sky.color = Color(top.r * 0.55, top.g * 0.60, top.b * 0.85)


func _level_ids_in_act(act: int) -> Array[String]:
  var prefix: String = "A%d-" % act
  var out: Array[String] = []
  for id: String in GameState.level_ids:
    if id.begins_with(prefix):
      out.append(id)
  return out


func _solved_in_act(act: int) -> int:
  var count: int = 0
  for id: String in _level_ids_in_act(act):
    if GameState.is_completed(id):
      count += 1
  return count


## The next courtyard you have not solved, staying inside its district so the
## acts are still experienced in order.
func next_level_for(gate: DistrictGate) -> String:
  for id: String in _level_ids_in_act(gate.act):
    if not GameState.is_completed(id):
      return id
  var ids: Array[String] = _level_ids_in_act(gate.act)
  return ids[0] if not ids.is_empty() else ""


func _enter(gate: DistrictGate) -> void:
  var level_id: String = next_level_for(gate)
  if level_id.is_empty():
    return
  _entering = true
  EventBus.audio_cue.emit("door_open", 1.0)
  var main: Main = _find_main()
  if main == null:
    _entering = false
    return
  main.play_level(level_id)


func _on_level_solved(_level_id: String, _act: int) -> void:
  _refresh()


## The journal is a Control, so it needs a CanvasLayer of its own: dropping it
## straight into the hub would put it under the world transform.
func _toggle_journal() -> void:
  var existing: Node = get_node_or_null("JournalLayer")
  if existing != null and is_instance_valid(existing):
    existing.queue_free()
    return
  var script: GDScript = load("res://src/ui/ShiftJournalUI.gd") as GDScript
  if script == null:
    return
  var built: Variant = script.new()
  if not (built is Node):
    return
  var layer := CanvasLayer.new()
  layer.name = "JournalLayer"
  layer.layer = 5
  add_child(layer)
  layer.add_child(built as Node)


func _find_main() -> Main:
  var node: Node = get_parent()
  while node != null:
    var main := node as Main
    if main != null:
      return main
    node = node.get_parent()
  return null
