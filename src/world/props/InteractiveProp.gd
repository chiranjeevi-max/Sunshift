class_name InteractiveProp
extends Node2D

## One fixture in the courtyard. The authoritative state lives in `SimState`;
## this node mirrors it visually and never decides gameplay outcomes itself.
##
## Art is resolved through `load()` rather than a direct `PropSpriteGen`
## reference so the world layer stays compilable even if a generator is missing.

const CELL: int = 16
const PROP_SPRITES_PATH: String = "res://src/art/PropSpriteGen.gd"
const SWAY_SHADER_PATH: String = "res://src/shaders/wind_sway.gdshader"

var prop_id: String = ""
var prop_type: int = GridTypes.PropType.MIRROR
var state: int = 0
var tile_cell: Vector2i = Vector2i.ZERO

var _sprite: AnimatedSprite2D
var _highlighted: bool = false


func setup(spec: LevelData.PropSpec) -> void:
  prop_id = spec.id
  prop_type = spec.type
  state = spec.state
  tile_cell = Vector2i(spec.x, spec.y)
  position = Vector2(spec.x * CELL + CELL / 2, spec.y * CELL + CELL / 2)
  add_to_group("interactable")
  _build_visual()


func apply_state(new_state: int) -> void:
  if new_state == state:
    return
  state = new_state
  _play_state_animation()


func set_highlighted(on: bool) -> void:
  if on == _highlighted:
    return
  _highlighted = on
  if _sprite != null:
    _sprite.modulate = Color(1.35, 1.22, 0.92) if on else Color.WHITE


func state_count() -> int:
  return GridTypes.prop_state_count(prop_type)


func cue_name() -> String:
  return "ui_select"


func foot_position() -> Vector2:
  return position + Vector2(0, CELL / 2)


func _build_visual() -> void:
  _sprite = AnimatedSprite2D.new()
  _sprite.sprite_frames = _frames()
  _sprite.centered = true
  _sprite.offset = Vector2(0, -CELL)
  _sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  add_child(_sprite)
  _apply_sway()
  _play_state_animation()
  _build_collision()


## The solver treats every fixture except an awning as unwalkable ground. Without
## this the player strolls straight through the brass mirror the puzzle is built
## around.
func _build_collision() -> void:
  if prop_type == GridTypes.PropType.AWNING:
    return
  var body := StaticBody2D.new()
  body.name = "Solid"
  body.collision_layer = 1
  body.collision_mask = 0
  var shape := CollisionShape2D.new()
  var box := RectangleShape2D.new()
  box.size = Vector2(CELL, CELL)
  shape.shape = box
  body.add_child(shape)
  add_child(body)


## Cloth and hanging fixtures flex on the wind; rigid ones stay welded to the
## grid. The shader only displaces vertices, so modulate and the sprite's normal
## appearance survive untouched.
func _apply_sway() -> void:
  if _sprite == null:
    return
  if prop_type != GridTypes.PropType.AWNING and prop_type != GridTypes.PropType.LANTERN:
    return
  var shader: Shader = load(SWAY_SHADER_PATH) as Shader
  if shader == null:
    return
  var mat := ShaderMaterial.new()
  mat.shader = shader
  mat.set_shader_parameter("anchor_top", true)
  mat.set_shader_parameter("anchor_y", 0.18)
  mat.set_shader_parameter("sway_amount", 1.6)
  mat.set_shader_parameter("sway_speed", 0.9)
  _sprite.material = mat


func _play_state_animation() -> void:
  if _sprite == null or _sprite.sprite_frames == null:
    return
  var anim: String = "state_%d" % state
  if _sprite.sprite_frames.has_animation(anim):
    _sprite.play(anim)
  elif _sprite.sprite_frames.has_animation("default"):
    _sprite.play("default")


func _frames() -> SpriteFrames:
  var script: GDScript = load(PROP_SPRITES_PATH) as GDScript
  if script != null:
    var built: Variant = script.call("build_frames", prop_type, state_count())
    if built is SpriteFrames:
      return built as SpriteFrames
  return _fallback_frames()


func _fallback_frames() -> SpriteFrames:
  var frames := SpriteFrames.new()
  var img: Image = Image.create(CELL, CELL * 2, false, Image.FORMAT_RGBA8)
  img.fill(Color(0.72, 0.55, 0.25, 1.0))
  var tex: ImageTexture = ImageTexture.create_from_image(img)
  for i: int in state_count():
    var anim: String = "state_%d" % i
    frames.add_animation(anim)
    frames.add_frame(anim, tex)
  return frames
