class_name CourtyardLevel
extends Node2D

## Builds an entire courtyard from `GameState.current_level`. Nothing here is
## hard-coded per level: tiles, props, neighbours and the player all come from
## the JSON, which is what lets 28 levels share one scene.

const CELL: int = 16
const VIEW_W: int = 480
const VIEW_H: int = 270
const SOLVE_BEAT: float = 0.8
const FRAME: float = 32.0
const GRADE_SHADER_PATH: String = "res://src/shaders/emotional_grade.gdshader"

var level: LevelData
var district: int = 0

var _ground: TileMapLayer
var _architecture: TileMapLayer
var _props_container: Node2D
var _neighbors_container: Node2D
var _player: Player
var _shadows: ShadowPainter
var _beams: BeamPainter
var _sky: Backdrop
var _sky_changed: bool = false
var _grade: ColorRect
var _hud: CanvasLayer
var _props: Dictionary[String, InteractiveProp] = {}
var _neighbors: Dictionary[String, NeighborNPC] = {}


func _ready() -> void:
  level = GameState.current_level
  if level == null:
    push_error("CourtyardLevel: no level loaded")
    return
  district = clampi(level.act - 1, 0, 3)
  _centre_level()
  _build_layers()
  _paint_tiles()
  _spawn_props()
  _spawn_neighbors()
  _spawn_player()
  _build_lights()
  _build_grade()
  _build_hud()
  _connect_bus()
  _refresh()


func _unhandled_input(event: InputEvent) -> void:
  if event.is_action_pressed("sun_shift_ccw"):
    GameState.shift_sun(1)
    _refresh()
  elif event.is_action_pressed("sun_shift_cw"):
    GameState.shift_sun(-1)
    _refresh()
  elif event.is_action_pressed("interact"):
    var prop: InteractiveProp = _player.nearest_prop() if _player != null else null
    if prop != null:
      EventBus.audio_cue.emit(prop.cue_name(), 1.0)
      GameState.interact_prop(prop.prop_id)
      _refresh()
  elif event.is_action_pressed("undo"):
    GameState.undo()
    _refresh()
  elif event.is_action_pressed("reset_level"):
    GameState.reset_level()
    _refresh()
  elif event.is_action_pressed("journal"):
    _toggle_journal()


func _centre_level() -> void:
  position = Vector2(
    float(VIEW_W - level.width * CELL) * 0.5,
    float(VIEW_H - level.height * CELL) * 0.5
  )


func _build_layers() -> void:
  var backdrop: Backdrop = Backdrop.new()
  backdrop.name = "SkyBackdrop"
  backdrop.position = -position
  backdrop.z_index = -100
  # The backdrop sits at the screen origin, so the frame has to be expressed in
  # its space: the level's own offset plus its size.
  backdrop.set_frame(Rect2(position, Vector2(level.width * CELL, level.height * CELL)))
  add_child(backdrop)
  _sky = backdrop
  _build_bounds()

  _ground = _new_tilemap("GroundLayer")
  add_child(_ground)

  _shadows = ShadowPainter.new()
  _shadows.name = "ShadowOverlay"
  add_child(_shadows)

  var y_sort: Node2D = Node2D.new()
  y_sort.name = "YSortWorld"
  y_sort.y_sort_enabled = true
  add_child(y_sort)

  _architecture = _new_tilemap("ArchitectureLayer")
  y_sort.add_child(_architecture)
  _architecture.y_sort_enabled = false

  _props_container = Node2D.new()
  _props_container.name = "PropsContainer"
  _props_container.y_sort_enabled = true
  y_sort.add_child(_props_container)

  _neighbors_container = Node2D.new()
  _neighbors_container.name = "NeighborsContainer"
  _neighbors_container.y_sort_enabled = true
  y_sort.add_child(_neighbors_container)

  _beams = BeamPainter.new()
  _beams.name = "LightBeamLayer"
  add_child(_beams)


func _new_tilemap(node_name: String) -> TileMapLayer:
  var layer: TileMapLayer = TileMapLayer.new()
  layer.name = node_name
  layer.tile_set = _tileset()
  layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  return layer


## Solid ground for the player, generated from the same predicate the solver
## walks with. Painting the tileset's own collision is not enough: void cells are
## never painted, so every hole and the whole outside of the courtyard used to be
## free floor and the player could walk off the level into the sky.
func _build_bounds() -> void:
  var body: StaticBody2D = StaticBody2D.new()
  body.name = "CourtyardBounds"
  body.collision_layer = 1
  body.collision_mask = 0
  add_child(body)
  for rect: Rect2 in _solid_rects():
    var shape: CollisionShape2D = CollisionShape2D.new()
    var box: RectangleShape2D = RectangleShape2D.new()
    box.size = rect.size
    shape.shape = box
    shape.position = rect.position + rect.size * 0.5
    body.add_child(shape)


## One rectangle per horizontal run of unwalkable cells, plus a frame just
## outside the courtyard so no border tile -- water included -- is a door out.
func _solid_rects() -> Array[Rect2]:
  var out: Array[Rect2] = []
  var state: SimState = GameState.current_state
  for y: int in level.height:
    var run_start: int = -1
    for x: int in level.width + 1:
      var solid: bool = x < level.width and not level.is_walkable(x, y, state)
      if solid and run_start < 0:
        run_start = x
      elif not solid and run_start >= 0:
        out.append(Rect2(run_start * CELL, y * CELL, (x - run_start) * CELL, CELL))
        run_start = -1
  var w: float = float(level.width * CELL)
  var h: float = float(level.height * CELL)
  out.append(Rect2(-FRAME, -FRAME, w + FRAME * 2.0, FRAME))
  out.append(Rect2(-FRAME, h, w + FRAME * 2.0, FRAME))
  out.append(Rect2(-FRAME, 0.0, FRAME, h))
  out.append(Rect2(w, 0.0, FRAME, h))
  return out


func _tileset() -> TileSet:
  var script: GDScript = load("res://src/art/TilesetGenerator.gd") as GDScript
  if script == null:
    return null
  var built: Variant = script.call("build_tileset", district)
  return built as TileSet


func _paint_tiles() -> void:
  for y: int in level.height:
    for x: int in level.width:
      var tile: LevelData.TileSpec = level.tile_at(x, y)
      if tile.type == GridTypes.TileType.VOID:
        continue
      var coords: Vector2i = _atlas_coords(tile)
      var target: TileMapLayer = _architecture if tile.elevation >= 1 else _ground
      if target == null or target.tile_set == null:
        continue
      target.set_cell(Vector2i(x, y), 0, coords)


func _atlas_coords(tile: LevelData.TileSpec) -> Vector2i:
  var generator: GDScript = load("res://src/art/TilesetGenerator.gd") as GDScript
  if tile.elevation == 0 and generator != null:
    if tile.type == GridTypes.TileType.WATER:
      return generator.get("WATER_ANIM_COORDS") as Vector2i
    if tile.type == GridTypes.TileType.PUDDLE:
      return generator.get("PUDDLE_ANIM_COORDS") as Vector2i
  if generator != null:
    var made: Variant = generator.call("atlas_coords", tile.type, tile.elevation)
    if made is Vector2i:
      return made as Vector2i
  return Vector2i(tile.type, tile.elevation)


func _spawn_props() -> void:
  for spec: LevelData.PropSpec in level.props:
    var prop: InteractiveProp = _make_prop(spec.type)
    prop.setup(spec)
    _props_container.add_child(prop)
    _props[spec.id] = prop


func _make_prop(prop_type: int) -> InteractiveProp:
  match prop_type:
    GridTypes.PropType.MIRROR:
      return BrassMirror.new()
    GridTypes.PropType.AWNING:
      return RailAwning.new()
    GridTypes.PropType.SHUTTER:
      return TeakShutter.new()
    GridTypes.PropType.PRISM:
      return CrystalPrism.new()
    GridTypes.PropType.STAINED_GLASS:
      return StainedGlass.new()
    GridTypes.PropType.LANTERN:
      return SunLantern.new()
    _:
      return InteractiveProp.new()


func _spawn_neighbors() -> void:
  for spec: LevelData.WishSpec in level.wishes:
    var npc: NeighborNPC = NeighborNPC.new()
    npc.setup(spec)
    _neighbors_container.add_child(npc)
    _neighbors[spec.id] = npc


func _spawn_player() -> void:
  _player = Player.new()
  _player.name = "Player"
  _player.place_at_cell(level.player_spawn)
  get_node("YSortWorld").add_child(_player)


func _build_lights() -> void:
  _beams.paint(GameState.last_result())


func _build_grade() -> void:
  var layer: CanvasLayer = CanvasLayer.new()
  layer.name = "EmotionalGradeLayer"
  layer.layer = 2
  add_child(layer)
  _grade = ColorRect.new()
  _grade.name = "Grade"
  _grade.size = Vector2(VIEW_W, VIEW_H)
  _grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
  var shader: Shader = load(GRADE_SHADER_PATH) as Shader
  if shader != null:
    var mat: ShaderMaterial = ShaderMaterial.new()
    mat.shader = shader
    _grade.material = mat
  layer.add_child(_grade)


func _build_hud() -> void:
  _hud = CanvasLayer.new()
  _hud.name = "HUDLayer"
  _hud.layer = 3
  add_child(_hud)
  var script: GDScript = load("res://src/ui/SunDialHUD.gd") as GDScript
  if script == null:
    return
  var hud_node: Variant = script.new()
  if hud_node is Node:
    var node: Node = hud_node as Node
    node.name = "SunDialHUD"
    _hud.add_child(node)


func _toggle_journal() -> void:
  var script: GDScript = load("res://src/ui/ShiftJournalUI.gd") as GDScript
  if script == null:
    return
  var existing: Node = _hud.get_node_or_null("ShiftJournalUI")
  if existing != null:
    existing.queue_free()
    return
  var created: Variant = script.new()
  if created is Node:
    var node: Node = created as Node
    node.name = "ShiftJournalUI"
    _hud.add_child(node)


func _connect_bus() -> void:
  EventBus.board_evaluated.connect(_on_board_evaluated)
  EventBus.undo_performed.connect(_on_undo)
  EventBus.level_reset.connect(_on_level_reset)


func _on_board_evaluated(_warmth: float, _satisfied: int, _total: int) -> void:
  _refresh()


func _on_undo() -> void:
  _refresh()


func _on_level_reset(_level_id: String) -> void:
  _refresh()


func _refresh() -> void:
  var result: LightSolver.SolveResult = GameState.last_result()
  var state: SimState = GameState.current_state
  if result == null or state == null:
    return
  _sync_props(state)
  _sync_neighbors(result)
  _sync_lanterns(result)
  _beams.paint(result)
  _shadows.paint(level, result, state.sun_angle)
  _sync_grade(result.warmth_factor)
  _sync_sky(result.warmth_factor)


func _sync_props(state: SimState) -> void:
  for prop_id: String in _props:
    var prop: InteractiveProp = _props[prop_id]
    var wanted: int = state.prop_states.get(prop_id, 0)
    prop.apply_state(wanted)


func _sync_neighbors(result: LightSolver.SolveResult) -> void:
  for wish_id: String in _neighbors:
    var npc: NeighborNPC = _neighbors[wish_id]
    npc.set_satisfied(bool(result.wish_states.get(wish_id, false)))


func _sync_lanterns(result: LightSolver.SolveResult) -> void:
  for prop_id: String in _props:
    var prop: InteractiveProp = _props[prop_id]
    if prop is SunLantern:
      (prop as SunLantern).set_glowing(bool(result.glowing_lanterns.get(prop_id, false)))


func _sync_grade(warmth: float) -> void:
  if _grade == null or _grade.material == null:
    return
  var mat: ShaderMaterial = _grade.material as ShaderMaterial
  mat.set_shader_parameter("warmth_factor", clampf(warmth, 0.0, 1.0))


## The sky warms with the level, so an unsolved courtyard sits in cool dusk and
## a solved one in the same golden hour the beams are casting.
func _sync_sky(warmth: float) -> void:
  if _sky == null:
    return
  var t: float = clampf(warmth, 0.0, 1.0)
  if t < 0.01 and not _sky_changed:
    return
  _sky_changed = true
  _sky.top_colour = Color(0.07, 0.09, 0.18).lerp(Color(0.16, 0.12, 0.22), t)
  _sky.bottom_colour = Color(0.19, 0.17, 0.29).lerp(Color(0.50, 0.31, 0.24), t)
  _sky.glow_strength = 0.55 + 0.85 * t
  _sky.queue_redraw()
