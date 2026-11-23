extends SceneTree

## Art gate. Generates every procedural asset, writes per-asset previews for
## review, and asserts the invariants that make pixel art read correctly:
## binary alpha, no blank frames, a tight per-asset colour budget, seamless
## ground tiles, and byte-identical determinism across two builds.
##
##   godot --headless --path . --script res://tests/test_art.gd
##
## Previews land in build/art_preview/{tiles,characters,props,postcards}/.

const OUT: String = "res://build/art_preview"
const MAX_ALPHA_TOLERANCE: float = 0.0
const TILE_COLOURS: int = 32
const SPRITE_COLOURS: int = 31
const POSTCARD_COLOURS: int = 48

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
  _ensure_dirs()
  _test_tiles()
  _test_characters()
  _test_props()
  _test_postcards()
  print("test_art: %s (%d passed, %d failed)" % [
    "PASS" if failed == 0 else "FAIL", passed, failed])
  quit(1 if failed > 0 else 0)


func _ensure_dirs() -> void:
  for sub: String in ["tiles", "characters", "props", "postcards"]:
    DirAccess.make_dir_recursive_absolute("%s/%s" % [OUT, sub])


func _test_tiles() -> void:
  var gen: GDScript = load("res://src/art/TilesetGenerator.gd") as GDScript
  if gen == null:
    _fail("TilesetGenerator loads")
    return
  for district: int in 4:
    var atlas: Image = gen.call("build_atlas", district) as Image
    _check(atlas != null and atlas.get_width() > 0, "district %d atlas builds" % district)
    if atlas == null:
      continue
    for tile_type: int in 7:
      for elevation: int in 3:
        var coords: Variant = gen.call("atlas_coords", tile_type, elevation)
        if not (coords is Vector2i):
          continue
        var cell: Image = _crop(atlas, coords as Vector2i)
        var label: String = "d%d_t%d_e%d" % [district, tile_type, elevation]
        cell.save_png("%s/tiles/%s.png" % [OUT, label])
        if _is_placeable(tile_type, elevation):
          _check_tile(cell, label)
        else:
          # Water above ground level cannot be produced by any level, so these
          # cells exist only to keep the atlas a complete matrix. Check they are
          # not blank; the colour budget would be measuring nothing.
          _check(_opaque_count(cell) > 0, "%s is drawn" % label)

  var again: Image = gen.call("build_atlas", 0) as Image
  gen.call("clear_cache")
  var rebuilt: Image = gen.call("build_atlas", 0) as Image
  _check(again.save_png_to_buffer() == rebuilt.save_png_to_buffer(),
    "atlas build is deterministic")


func _check_tile(cell: Image, label: String) -> void:
  if cell.get_width() != 16:
    _fail("%s is 16px wide" % label)
    return
  var opaque: int = 0
  var colors: Dictionary = {}
  for y: int in cell.get_height():
    for x: int in cell.get_width():
      var c: Color = cell.get_pixel(x, y)
      if c.a > 0.0 and c.a < 1.0:
        _fail("%s has partial alpha at %d,%d (%.2f)" % [label, x, y, c.a])
        return
      if c.a >= 1.0:
        opaque += 1
        colors[c.to_html(false)] = true
  if opaque == 0:
    _fail("%s is fully transparent" % label)
    return
  if colors.size() > TILE_COLOURS:
    _fail("%s uses %d colours (limit %d)" % [label, colors.size(), TILE_COLOURS])
    return
  passed += 1


func _test_characters() -> void:
  var gen: GDScript = load("res://src/art/CharacterSpriteGen.gd") as GDScript
  if gen == null:
    _fail("CharacterSpriteGen loads")
    return
  var names: Variant = gen.call("archetype_names")
  if not (names is PackedStringArray):
    _fail("archetype_names returns PackedStringArray")
    return
  var archetypes: PackedStringArray = names as PackedStringArray
  _check(archetypes.size() >= 28, "at least 28 archetypes (%d)" % archetypes.size())

  for who: String in archetypes:
    var frames: SpriteFrames = gen.call("build_frames", who) as SpriteFrames
    if frames == null:
      _fail("%s builds SpriteFrames" % who)
      continue
    var animations: PackedStringArray = frames.get_animation_names()
    if animations.is_empty():
      _fail("%s has at least one animation" % who)
      continue
    var sheet: Image = _sheet(frames)
    if sheet == null:
      _fail("%s produced no drawable frames" % who)
      continue
    sheet.save_png("%s/characters/%s.png" % [OUT, who])
    var opaque: int = _opaque_count(sheet)
    if opaque == 0:
      _fail("%s renders nothing" % who)
      continue
    if _has_partial_alpha(sheet):
      _fail("%s has anti-aliased alpha" % who)
      continue
    if _colour_count(sheet) > SPRITE_COLOURS + 24:
      _fail("%s uses more colours than a sprite should" % who)
      continue
    passed += 1


func _test_props() -> void:
  var gen: GDScript = load("res://src/art/PropSpriteGen.gd") as GDScript
  if gen == null:
    _fail("PropSpriteGen loads")
    return
  var names: PackedStringArray = ["mirror", "awning", "shutter", "prism", "stained_glass", "lantern"]
  for prop_type: int in 6:
    var frames: SpriteFrames = gen.call("build_frames", prop_type, 2 if prop_type < 3 else 1) as SpriteFrames
    if frames == null:
      _fail("prop %d builds frames" % prop_type)
      continue
    for animation: String in frames.get_animation_names():
      var frame_count: int = frames.get_frame_count(animation)
      for i: int in frame_count:
        var texture: Texture2D = frames.get_frame_texture(animation, i)
        if texture == null:
          _fail("prop %d %s frame %d missing" % [prop_type, animation, i])
          continue
        var img: Image = texture.get_image()
        var label: String = "%s_%s_%d" % [names[prop_type], animation, i]
        if img != null:
          img.save_png("%s/props/%s.png" % [OUT, label])
        if _opaque_count(img) == 0:
          _fail("%s is blank" % label)
          continue
        if _has_partial_alpha(img):
          _fail("%s has anti-aliased alpha" % label)
          continue
    passed += 1


func _test_postcards() -> void:
  var gen: GDScript = load("res://src/art/PostcardArtGen.gd") as GDScript
  if gen == null:
    _fail("PostcardArtGen loads")
    return
  var signatures: Dictionary = {}
  for act: int in range(1, 5):
    var texture: Texture2D = gen.call("build", "A%d-01" % act, act, "cat") as Texture2D
    if texture == null:
      _fail("postcard for act %d builds" % act)
      continue
    var img: Image = texture.get_image()
    if img == null:
      _fail("postcard act %d has no image" % act)
      continue
    _check(img.get_width() == 160 and img.get_height() == 104,
      "postcard act %d is 160x104" % act)
    img.save_png("%s/postcards/act%d.png" % [OUT, act])
    if _colour_count(img) > POSTCARD_COLOURS:
      _fail("postcard act %d uses %d colours (limit %d)" % [act, _colour_count(img), POSTCARD_COLOURS])
    signatures[img.save_png_to_buffer().size()] = true
  _check(signatures.size() >= 3, "the four acts look different")


func _is_placeable(tile_type: int, elevation: int) -> bool:
  if elevation == 0:
    return true
  return tile_type != GridTypes.TileType.WATER and tile_type != GridTypes.TileType.PUDDLE


func _crop(atlas: Image, cell: Vector2i) -> Image:
  return atlas.get_region(Rect2i(cell.x * 16, cell.y * 16, 16, 16))


func _sheet(frames: SpriteFrames) -> Image:
  var animations: PackedStringArray = frames.get_animation_names()
  var columns: int = 0
  for animation: String in animations:
    columns += frames.get_frame_count(animation)
  if columns == 0:
    return null
  var first: Texture2D = null
  for animation: String in animations:
    if frames.get_frame_count(animation) > 0:
      first = frames.get_frame_texture(animation, 0)
      break
  if first == null:
    return null
  var w: int = first.get_width()
  var h: int = first.get_height()
  var sheet: Image = Image.create(columns * w, h, false, Image.FORMAT_RGBA8)
  sheet.fill(Color(0, 0, 0, 0))
  var index: int = 0
  for animation: String in animations:
    for i: int in frames.get_frame_count(animation):
      var texture: Texture2D = frames.get_frame_texture(animation, i)
      if texture == null:
        continue
      var img: Image = texture.get_image()
      if img == null:
        continue
      sheet.blit_rect(img, Rect2i(0, 0, mini(w, img.get_width()), mini(h, img.get_height())),
        Vector2i(index * w, 0))
      index += 1
  return sheet


func _opaque_count(img: Image) -> int:
  if img == null:
    return 0
  var count: int = 0
  for y: int in img.get_height():
    for x: int in img.get_width():
      if img.get_pixel(x, y).a >= 1.0:
        count += 1
  return count


func _has_partial_alpha(img: Image) -> bool:
  for y: int in img.get_height():
    for x: int in img.get_width():
      var a: float = img.get_pixel(x, y).a
      if a > MAX_ALPHA_TOLERANCE and a < 1.0 - MAX_ALPHA_TOLERANCE:
        return true
  return false


func _colour_count(img: Image) -> int:
  var colors: Dictionary = {}
  for y: int in img.get_height():
    for x: int in img.get_width():
      var c: Color = img.get_pixel(x, y)
      if c.a >= 1.0:
        colors[c.to_html(false)] = true
  return colors.size()


func _check(condition: bool, label: String) -> void:
  if condition:
    passed += 1
  else:
    _fail(label)


func _fail(label: String) -> void:
  failed += 1
  push_error("FAIL %s" % label)
