class_name NeighborNPC
extends Node2D

## A neighbour (or cat, or sourdough, or marigold) with a wish. The bubble shows
## what they need with an icon only — the game never prints a text wall at them.

const CELL: int = 16
const CHARACTER_SPRITES_PATH: String = "res://src/art/CharacterSpriteGen.gd"
const ICON_SIZE: int = 11
const BUBBLE_HEIGHT: float = 26.0

var wish_id: String = ""
var who: String = ""
var need: int = GridTypes.WishType.WARM_SUN
var satisfied: bool = false

var _sprite: AnimatedSprite2D
var _bubble: Sprite2D
var _bob_phase: float = 0.0

static var _icon_cache: Dictionary[int, ImageTexture] = {}


func setup(spec: LevelData.WishSpec) -> void:
  wish_id = spec.id
  who = spec.who
  need = spec.need
  position = Vector2(spec.x * CELL + CELL / 2, spec.y * CELL + CELL / 2)
  add_to_group("neighbor")
  _build()


func set_satisfied(on: bool) -> void:
  if on == satisfied:
    return
  satisfied = on
  if _bubble != null:
    _bubble.visible = not on
  if on and _sprite != null and _sprite.sprite_frames != null \
      and _sprite.sprite_frames.has_animation("emote_happy"):
    _sprite.play("emote_happy")
  elif _sprite != null and _sprite.sprite_frames != null \
      and _sprite.sprite_frames.has_animation("idle_down"):
    _sprite.play("idle_down")


func _process(delta: float) -> void:
  if _bubble == null or not _bubble.visible:
    return
  _bob_phase += delta * 2.2
  # The icon bobs by whole pixels. A fractional bob puts the 16px icon on half
  # rows every other frame, and it shimmers against the tile grid.
  _bubble.position = Vector2(0, float(-BUBBLE_HEIGHT) + roundf(sin(_bob_phase)))


func _build() -> void:
  _sprite = AnimatedSprite2D.new()
  _sprite.sprite_frames = _frames()
  _sprite.centered = true
  _sprite.offset = Vector2(0, -12)
  _sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  add_child(_sprite)
  if _sprite.sprite_frames != null:
    if _sprite.sprite_frames.has_animation("idle_down"):
      _sprite.play("idle_down")
    elif _sprite.sprite_frames.has_animation("default"):
      _sprite.play("default")

  _bubble = Sprite2D.new()
  _bubble.texture = _icon_for(need)
  _bubble.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
  _bubble.position = Vector2(0, -BUBBLE_HEIGHT)
  add_child(_bubble)


func _frames() -> SpriteFrames:
  var script: GDScript = load(CHARACTER_SPRITES_PATH) as GDScript
  if script != null:
    var built: Variant = script.call("build_frames", who)
    if built is SpriteFrames:
      return built as SpriteFrames
  return _fallback_frames()


func _fallback_frames() -> SpriteFrames:
  var frames := SpriteFrames.new()
  var img: Image = Image.create(CELL, CELL + 8, false, Image.FORMAT_RGBA8)
  img.fill(Color(0.42, 0.36, 0.30, 1.0))
  var tex: ImageTexture = ImageTexture.create_from_image(img)
  for anim: String in ["idle_down", "default"]:
    frames.add_animation(anim)
    frames.add_frame(anim, tex)
  return frames


static func _icon_for(need_type: int) -> ImageTexture:
  var cached: Variant = _icon_cache.get(need_type)
  if cached != null:
    return cached as ImageTexture
  var img: Image = Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
  img.fill(Color(0, 0, 0, 0))
  var ink: Color = Color(1.0, 0.82, 0.5, 1.0)
  var cool: Color = Color(0.63, 0.74, 0.88, 1.0)
  var mid: int = ICON_SIZE / 2
  match need_type:
    GridTypes.WishType.WARM_SUN:
      _disc(img, mid, mid, 2, ink)
      for d: Vector2i in [Vector2i(0, -4), Vector2i(0, 4), Vector2i(-4, 0), Vector2i(4, 0)]:
        img.set_pixelv(Vector2i(mid, mid) + d, ink)
    GridTypes.WishType.SOFT_SHADE:
      _disc(img, mid, mid, 3, cool)
      _disc(img, mid + 2, mid - 2, 3, Color(0, 0, 0, 0))
    GridTypes.WishType.SHARED_BEAM:
      _disc(img, mid - 3, mid, 1, ink)
      _disc(img, mid + 3, mid, 1, ink)
      img.set_pixel(mid - 1, mid, ink)
      img.set_pixel(mid, mid, ink)
      img.set_pixel(mid + 1, mid, ink)
    GridTypes.WishType.ROSE_LIGHT:
      _disc(img, mid, mid, 2, Color(1.0, 0.68, 0.72, 1.0))
      img.set_pixel(mid, mid - 3, Color(1.0, 0.68, 0.72, 1.0))
      img.set_pixel(mid, mid + 3, Color(1.0, 0.68, 0.72, 1.0))
      img.set_pixel(mid - 3, mid, Color(1.0, 0.68, 0.72, 1.0))
      img.set_pixel(mid + 3, mid, Color(1.0, 0.68, 0.72, 1.0))
    GridTypes.WishType.LANTERN_GLOW:
      _disc(img, mid, mid + 1, 2, ink)
      img.set_pixel(mid, mid - 2, ink)
      img.set_pixel(mid - 1, mid - 3, Color(1.0, 0.9, 0.6, 0.8))
      img.set_pixel(mid + 1, mid - 3, Color(1.0, 0.9, 0.6, 0.8))
    _:
      _disc(img, mid, mid, 2, ink)
  var texture: ImageTexture = ImageTexture.create_from_image(img)
  _icon_cache[need_type] = texture
  return texture


static func _disc(img: Image, cx: int, cy: int, radius: int, color: Color) -> void:
  for y: int in range(cy - radius, cy + radius + 1):
    for x: int in range(cx - radius, cx + radius + 1):
      if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
        continue
      var dx: int = x - cx
      var dy: int = y - cy
      if dx * dx + dy * dy <= radius * radius + 1:
        img.set_pixel(x, y, color)
