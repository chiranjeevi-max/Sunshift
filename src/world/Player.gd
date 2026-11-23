class_name Player
extends CharacterBody2D

## Milo. Movement and proximity only: every action the player takes is routed
## through GameState, which owns the authoritative simulation state.

signal interact_requested(prop_id: String)

const CELL: int = 16
const SPEED: float = 72.0
const ACCEL_TIME: float = 0.08
const FRICTION_TIME: float = 0.06
const INTERACT_RADIUS: float = 22.0
const CHARACTER_SPRITES_PATH: String = "res://src/art/CharacterSpriteGen.gd"

var facing: String = "down"
var target: InteractiveProp = null

var _sprite: AnimatedSprite2D
var _last_target: InteractiveProp = null


func _ready() -> void:
  add_to_group("player")
  collision_layer = 2
  collision_mask = 1
  motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
  _build_collision()
  _build_sprite()


func _process(_delta: float) -> void:
  _scan_for_target()


func _physics_process(delta: float) -> void:
  var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
  var desired: Vector2 = input * SPEED
  var rate: float = (ACCEL_TIME if input != Vector2.ZERO else FRICTION_TIME)
  var weight: float = clampf(delta / maxf(rate, 0.001), 0.0, 1.0)
  velocity = velocity.lerp(desired, weight)
  if velocity.length() < 1.0 and input == Vector2.ZERO:
    velocity = Vector2.ZERO
  move_and_slide()
  _update_facing(input)
  _update_animation(input)


func place_at_cell(cell: Vector2i) -> void:
  position = Vector2(cell.x * CELL + CELL / 2, cell.y * CELL + CELL / 2)


func nearest_prop() -> InteractiveProp:
  return target


func _scan_for_target() -> void:
  var best: InteractiveProp = null
  var best_distance: float = INTERACT_RADIUS
  for node: Node in get_tree().get_nodes_in_group("interactable"):
    var prop: InteractiveProp = node as InteractiveProp
    if prop == null or not is_instance_valid(prop):
      continue
    var distance: float = position.distance_to(prop.position)
    if distance <= best_distance:
      best_distance = distance
      best = prop
  if best != _last_target:
    if _last_target != null and is_instance_valid(_last_target):
      _last_target.set_highlighted(false)
    if best != null:
      best.set_highlighted(true)
    _last_target = best
  target = best


func _update_facing(input: Vector2) -> void:
  if input == Vector2.ZERO:
    return
  if absf(input.x) >= absf(input.y):
    facing = "right" if input.x > 0.0 else "left"
  else:
    facing = "down" if input.y > 0.0 else "up"


func _update_animation(input: Vector2) -> void:
  if _sprite == null or _sprite.sprite_frames == null:
    return
  var moving: bool = input != Vector2.ZERO
  var anim: String = ("walk_" if moving else "idle_") + facing
  if _sprite.sprite_frames.has_animation(anim):
    if _sprite.animation != anim:
      _sprite.play(anim)
  elif _sprite.sprite_frames.has_animation("idle_down"):
    _sprite.play("idle_down")


func _build_sprite() -> void:
  _sprite = AnimatedSprite2D.new()
  _sprite.sprite_frames = _frames()
  _sprite.centered = true
  _sprite.offset = Vector2(0, -12)
  _sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  add_child(_sprite)
  if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation("idle_down"):
    _sprite.play("idle_down")


func _build_collision() -> void:
  var shape: CollisionShape2D = CollisionShape2D.new()
  var circle: CircleShape2D = CircleShape2D.new()
  circle.radius = 5.0
  shape.shape = circle
  shape.position = Vector2(0, 4)
  add_child(shape)


func _frames() -> SpriteFrames:
  var script: GDScript = load(CHARACTER_SPRITES_PATH) as GDScript
  if script != null:
    var built: Variant = script.call("build_frames", "milo")
    if built is SpriteFrames:
      return built as SpriteFrames
  return _fallback_frames()


func _fallback_frames() -> SpriteFrames:
  var frames: SpriteFrames = SpriteFrames.new()
  var img: Image = Image.create(CELL, CELL + 8, false, Image.FORMAT_RGBA8)
  img.fill(Color(0.36, 0.28, 0.42, 1.0))
  var tex: ImageTexture = ImageTexture.create_from_image(img)
  for anim: String in ["idle_down", "idle_up", "idle_left", "idle_right"]:
    frames.add_animation(anim)
    frames.add_frame(anim, tex)
  return frames
