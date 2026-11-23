class_name CharacterSpriteGen
extends RefCounted
## Deterministic 16x24 character/object sprite frames, built from modular layers.
##
## Every sprite is authored on a 16-wide, 24-tall grid with the feet on row 23
## and the body centred on x = 7.5. Sprites are therefore bottom-centre anchored:
## a centred Sprite2D wants `offset = Vector2(0, -12)`.
##
## Authoring happens in a *tag buffer* (material + level per pixel), never in
## colour. A single shading pass then lights every pixel from the same rule —
## open sky above/right means one step lighter, open ground below/left one step
## darker — so the whole cast shares one top-right light source. Colours are
## materialised last from `PixelCanvas`'s district ramps, outlined, and clamped
## to a 15-colour budget. Alpha is always 0 or 255.

const FRAME_W: int = 16
const FRAME_H: int = 24
const PIXEL_COUNT: int = FRAME_W * FRAME_H
const MAX_COLORS: int = 15

const TAG_RAW_BASE: int = 100
const LEVEL_BASE: int = 2

const DIR_DOWN: int = 0
const DIR_UP: int = 1
const DIR_LEFT: int = 2
const DIR_RIGHT: int = 3

const EMOTE_NONE: int = 0
const EMOTE_HAPPY: int = 1
const EMOTE_TENSE: int = 2

const HAIR_SHORT: int = 0
const HAIR_LONG: int = 1
const HAIR_FULL: int = 2
const HAIR_BALD: int = 3
const HAIR_BUN: int = 4
const HAIR_PONY: int = 5
const HAIR_SWEEP: int = 6

const HAT_NONE: int = 0
const HAT_CAP: int = 1
const HAT_CHEF: int = 2
const HAT_WIDE: int = 3
const HAT_BEANIE: int = 4
const HAT_BERET: int = 5
const HAT_TALL: int = 6
const HAT_HEADSCARF: int = 7

const SCARF_NONE: int = 0
const SCARF_SHORT: int = 1
const SCARF_LONG: int = 2
const SCARF_SHAWL: int = 3

const PROP_NONE: int = 0
const PROP_ROLLING_PIN: int = 1
const PROP_GUITAR: int = 2
const PROP_WRENCH: int = 3
const PROP_LETTER: int = 4
const PROP_BRUSH: int = 5
const PROP_BOOK: int = 6
const PROP_LANTERN: int = 7
const PROP_BASKET: int = 8
const PROP_BAG: int = 9
const PROP_CANE: int = 10
const PROP_SCROLL: int = 11
const PROP_ROPE: int = 12
const PROP_SATCHEL: int = 13
const PROP_FLUTE: int = 14
const PROP_BUNDLE: int = 15

static var _cache: Dictionary = {}
static var _names: PackedStringArray = PackedStringArray()

var _pc: PixelCanvas = PixelCanvas.new()
var _pal: PixelCanvas.Palette = null
var _tags: PackedByteArray = PackedByteArray()
var _raw: Array[Color] = []


## All archetype keys this generator understands.
static func archetype_names() -> PackedStringArray:
	if _names.is_empty():
		_names = PackedStringArray([
			"milo", "cat", "baker", "nurse", "guitarist", "child", "mother",
			"mechanic", "postman", "elder_woman", "elder_man", "artist",
			"musician", "florist", "bookbinder", "lantern_maker", "commuter",
			"student", "astronomer", "harbor_keeper", "hibiscus", "marigold",
			"sourdough", "pigeon", "pup", "tea_set", "shrine_lamp", "camelia",
		])
	return _names


static func clear_cache() -> void:
	_cache.clear()


## Deterministic and cached: the same `who` always yields the same frames.
static func build_frames(who: String) -> SpriteFrames:
	var key: String = who.strip_edges().to_lower()
	if _cache.has(key):
		return _cache[key] as SpriteFrames
	var gen: CharacterSpriteGen = CharacterSpriteGen.new()
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation(&"default")
	if _is_human(key) or not _is_object(key):
		gen._build_human(frames, key)
	elif key == "cat":
		gen._build_creature(frames, key, 0)
	elif key == "pup":
		gen._build_creature(frames, key, 1)
	elif key == "pigeon":
		gen._build_creature(frames, key, 2)
	elif key == "sourdough":
		gen._build_object(frames, key, 0)
	elif key == "tea_set":
		gen._build_object(frames, key, 1)
	elif key == "shrine_lamp":
		gen._build_object(frames, key, 2)
	else:
		gen._build_bloom(frames, key)
	_cache[key] = frames
	return frames


static func _is_object(who: String) -> bool:
	match who:
		"cat", "pup", "pigeon", "sourdough", "tea_set", "shrine_lamp", \
		"hibiscus", "marigold", "camelia":
			return true
	return false


static func _is_human(who: String) -> bool:
	match who:
		"milo", "baker", "nurse", "guitarist", "child", "mother", "mechanic", \
		"postman", "elder_woman", "elder_man", "artist", "musician", "florist", \
		"bookbinder", "lantern_maker", "commuter", "student", "astronomer", \
		"harbor_keeper":
			return true
	return false


func _add(frames: SpriteFrames, anim: String, img: Image) -> void:
	if not frames.has_animation(anim):
		frames.add_animation(anim)
		frames.set_animation_loop(anim, true)
		match anim:
			"walk_down", "walk_up", "walk_left", "walk_right":
				frames.set_animation_speed(anim, 8.0)
			"idle_down", "idle_up", "idle_left", "idle_right":
				frames.set_animation_speed(anim, 2.5)
			"default":
				frames.set_animation_speed(anim, 2.0)
			_:
				frames.set_animation_speed(anim, 4.0)
	frames.add_frame(anim, ImageTexture.create_from_image(img))


func _build_human(frames: SpriteFrames, who: String) -> void:
	var fig: Figure = _figure(who)
	var dirs: Array[int] = [DIR_DOWN, DIR_UP, DIR_LEFT, DIR_RIGHT]
	var names: Array[String] = ["down", "up", "left", "right"]
	for i: int in dirs.size():
		var dir: int = dirs[i]
		_add(frames, "idle_%s" % names[i], _render_human(fig, dir, 0, 0, EMOTE_NONE))
		_add(frames, "idle_%s" % names[i], _render_human(fig, dir, 1, 0, EMOTE_NONE))
	if who == "milo":
		for i: int in dirs.size():
			var dir: int = dirs[i]
			var strides: Array[int] = [-1, 0, 1, 0]
			var bobs: Array[int] = [0, 1, 0, 1]
			for f: int in 4:
				_add(frames, "walk_%s" % names[i], _render_human(fig, dir, bobs[f], strides[f], EMOTE_NONE))
	_add(frames, "emote_happy", _render_human(fig, DIR_DOWN, 0, 0, EMOTE_HAPPY))
	_add(frames, "emote_happy", _render_human(fig, DIR_DOWN, 1, 0, EMOTE_HAPPY))
	_add(frames, "emote_tense", _render_human(fig, DIR_DOWN, 0, 0, EMOTE_TENSE))
	_add(frames, "emote_tense", _render_human(fig, DIR_DOWN, 0, -1, EMOTE_TENSE))


func _build_creature(frames: SpriteFrames, who: String, kind: int) -> void:
	_add(frames, "default", _render_creature(who, kind, 0, EMOTE_NONE))
	_add(frames, "default", _render_creature(who, kind, 1, EMOTE_NONE))
	_add(frames, "emote_happy", _render_creature(who, kind, 0, EMOTE_HAPPY))
	_add(frames, "emote_happy", _render_creature(who, kind, 1, EMOTE_HAPPY))


func _build_object(frames: SpriteFrames, who: String, kind: int) -> void:
	_add(frames, "default", _render_object(who, kind, 0, false))
	_add(frames, "default", _render_object(who, kind, 1, false))
	_add(frames, "emote_happy", _render_object(who, kind, 0, true))
	_add(frames, "emote_happy", _render_object(who, kind, 1, true))


func _build_bloom(frames: SpriteFrames, who: String) -> void:
	var kind: int = 0
	if who == "marigold":
		kind = 1
	elif who == "camelia":
		kind = 2
	_add(frames, "default", _render_bloom(kind, 0, false))
	_add(frames, "default", _render_bloom(kind, 1, false))
	_add(frames, "emote_happy", _render_bloom(kind, 0, true))
	_add(frames, "emote_happy", _render_bloom(kind, 1, true))


func _figure(who: String) -> Figure:
	var f: Figure = Figure.new()
	match who:
		"milo":
			f.district = 0
			f.coat = PixelCanvas.MAT_WATER
			f.accent = PixelCanvas.MAT_CLAY
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 6
			f.head_h = 7
			f.shoulder_w = 8
			f.hip_w = 7
			f.hem_y = 18
			f.scarf = SCARF_LONG
			f.boot = true
			f.hair_style = HAIR_SHORT
		"baker":
			f.district = 0
			f.coat = PixelCanvas.MAT_CLOTH
			f.accent = PixelCanvas.MAT_CLAY
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 7
			f.head_h = 7
			f.shoulder_w = 11
			f.hip_w = 10
			f.hem_y = 19
			f.apron = 2
			f.hat = HAT_CHEF
			f.hair_style = HAIR_BUN
			f.prop = PROP_ROLLING_PIN
		"nurse":
			f.district = 1
			f.coat = PixelCanvas.MAT_MOSS
			f.accent = PixelCanvas.MAT_CLOTH
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 6
			f.head_h = 7
			f.shoulder_w = 8
			f.hip_w = 8
			f.hem_y = 19
			f.hat = HAT_CAP
			f.hair_style = HAIR_BUN
			f.prop = PROP_SATCHEL
		"guitarist":
			f.district = 2
			f.coat = PixelCanvas.MAT_CLAY
			f.accent = PixelCanvas.MAT_WOOD
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 6
			f.head_h = 7
			f.shoulder_w = 8
			f.hip_w = 7
			f.hem_y = 19
			f.hair_style = HAIR_LONG
			f.scarf = SCARF_SHORT
			f.prop = PROP_GUITAR
		"child":
			f.district = 0
			f.coat = PixelCanvas.MAT_MOSS
			f.accent = PixelCanvas.MAT_CLAY
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 7
			f.head_h = 8
			f.head_y = 3
			f.shoulder_w = 7
			f.hip_w = 6
			f.hem_y = 16
			f.leg_w = 2
			f.hat = HAT_CAP
			f.hair_style = HAIR_SHORT
			f.prop = PROP_LETTER
		"mother":
			f.district = 1
			f.coat = PixelCanvas.MAT_CLOTH
			f.accent = PixelCanvas.MAT_CLAY
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 6
			f.head_h = 7
			f.shoulder_w = 8
			f.hip_w = 10
			f.hem_y = 20
			f.skirt = true
			f.hair_style = HAIR_BUN
			f.scarf = SCARF_SHAWL
			f.prop = PROP_BUNDLE
		"mechanic":
			f.district = 3
			f.coat = PixelCanvas.MAT_METAL
			f.accent = PixelCanvas.MAT_CLAY
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 6
			f.head_h = 6
			f.shoulder_w = 10
			f.hip_w = 9
			f.hem_y = 18
			f.apron = 1
			f.hat = HAT_BEANIE
			f.hair_style = HAIR_SHORT
			f.prop = PROP_WRENCH
		"postman":
			f.district = 1
			f.coat = PixelCanvas.MAT_WATER
			f.accent = PixelCanvas.MAT_CLAY
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 6
			f.head_h = 7
			f.shoulder_w = 9
			f.hip_w = 8
			f.hem_y = 18
			f.hat = HAT_CAP
			f.hair_style = HAIR_SHORT
			f.prop = PROP_LETTER
			f.boot = true
		"elder_woman":
			f.district = 0
			f.coat = PixelCanvas.MAT_MOSS
			f.accent = PixelCanvas.MAT_CLAY
			f.hair = PixelCanvas.MAT_STONE
			f.head_w = 6
			f.head_h = 6
			f.shoulder_w = 8
			f.hip_w = 9
			f.hem_y = 20
			f.skirt = true
			f.hunch = 1
			f.hair_style = HAIR_BUN
			f.scarf = SCARF_SHAWL
			f.hat = HAT_HEADSCARF
			f.prop = PROP_CANE
		"elder_man":
			f.district = 2
			f.coat = PixelCanvas.MAT_STONE
			f.accent = PixelCanvas.MAT_WOOD
			f.hair = PixelCanvas.MAT_STONE
			f.head_w = 6
			f.head_h = 6
			f.shoulder_w = 8
			f.hip_w = 7
			f.hem_y = 19
			f.hunch = 2
			f.hair_style = HAIR_BALD
			f.beard = 1
			f.prop = PROP_CANE
		"artist":
			f.district = 2
			f.coat = PixelCanvas.MAT_CLAY
			f.accent = PixelCanvas.MAT_MOSS
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 6
			f.head_h = 7
			f.shoulder_w = 8
			f.hip_w = 7
			f.hem_y = 19
			f.hat = HAT_BERET
			f.hair_style = HAIR_FULL
			f.apron = 1
			f.scarf = SCARF_SHORT
			f.prop = PROP_BRUSH
		"musician":
			f.district = 3
			f.coat = PixelCanvas.MAT_CLOTH
			f.accent = PixelCanvas.MAT_WOOD
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 6
			f.head_h = 7
			f.shoulder_w = 8
			f.hip_w = 7
			f.hem_y = 19
			f.hair_style = HAIR_FULL
			f.prop = PROP_FLUTE
		"florist":
			f.district = 1
			f.coat = PixelCanvas.MAT_MOSS
			f.accent = PixelCanvas.MAT_CLAY
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 6
			f.head_h = 7
			f.shoulder_w = 8
			f.hip_w = 8
			f.hem_y = 19
			f.hat = HAT_WIDE
			f.hair_style = HAIR_PONY
			f.apron = 1
			f.prop = PROP_BASKET
		"bookbinder":
			f.district = 2
			f.coat = PixelCanvas.MAT_WOOD
			f.accent = PixelCanvas.MAT_CLAY
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 7
			f.head_h = 7
			f.shoulder_w = 9
			f.hip_w = 8
			f.hem_y = 19
			f.apron = 1
			f.hair_style = HAIR_SWEEP
			f.prop = PROP_BOOK
		"lantern_maker":
			f.district = 1
			f.coat = PixelCanvas.MAT_METAL
			f.accent = PixelCanvas.MAT_CLAY
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 6
			f.head_h = 7
			f.shoulder_w = 9
			f.hip_w = 8
			f.hem_y = 18
			f.hair_style = HAIR_SHORT
			f.hat = HAT_BEANIE
			f.boot = true
			f.prop = PROP_LANTERN
		"commuter":
			f.district = 3
			f.coat = PixelCanvas.MAT_STONE
			f.accent = PixelCanvas.MAT_WATER
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 6
			f.head_h = 7
			f.shoulder_w = 9
			f.hip_w = 8
			f.hem_y = 19
			f.hair_style = HAIR_SWEEP
			f.prop = PROP_BAG
		"student":
			f.district = 0
			f.coat = PixelCanvas.MAT_WATER
			f.accent = PixelCanvas.MAT_CLAY
			f.hair = PixelCanvas.MAT_WOOD
			f.head_w = 6
			f.head_h = 7
			f.shoulder_w = 8
			f.hip_w = 7
			f.hem_y = 18
			f.hair_style = HAIR_SHORT
			f.prop = PROP_SATCHEL
		"astronomer":
			f.district = 3
			f.coat = PixelCanvas.MAT_WATER
			f.accent = PixelCanvas.MAT_METAL
			f.hair = PixelCanvas.MAT_STONE
			f.head_w = 6
			f.head_h = 7
			f.shoulder_w = 9
			f.hip_w = 8
			f.hem_y = 20
			f.skirt = true
			f.hat = HAT_TALL
			f.hair_style = HAIR_SWEEP
			f.scarf = SCARF_SHORT
			f.prop = PROP_SCROLL
		"harbor_keeper":
			f.district = 1
			f.coat = PixelCanvas.MAT_WOOD
			f.accent = PixelCanvas.MAT_WATER
			f.hair = PixelCanvas.MAT_STONE
			f.head_w = 6
			f.head_h = 6
			f.shoulder_w = 10
			f.hip_w = 9
			f.hem_y = 18
			f.hunch = 1
			f.hat = HAT_BEANIE
			f.prop = PROP_ROPE
		_:
			f.district = PixelCanvas.seeded_from(who) % 4
			f.coat = PixelCanvas.MAT_CLOTH
			f.accent = PixelCanvas.MAT_CLAY
			f.hair = PixelCanvas.MAT_WOOD
			f.hem_y = 18
			f.hair_style = HAIR_SHORT
			f.boot = true
	return f


func _begin(district: int) -> void:
	_pal = PixelCanvas.load_palette(district)
	if _tags.size() != PIXEL_COUNT:
		_tags.resize(PIXEL_COUNT)
	_tags.fill(0)
	_raw.clear()


func _tag_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= FRAME_W or y >= FRAME_H:
		return 0
	return _tags[y * FRAME_W + x]


func _px(x: int, y: int, mat: int, level: int) -> void:
	if x < 0 or y < 0 or x >= FRAME_W or y >= FRAME_H:
		return
	var clamped: int = clampi(level, 0, 4)
	_tags[y * FRAME_W + x] = ((clampi(mat, 0, 7) << 3) | clamped) + 1


func _raw_px(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= FRAME_W or y >= FRAME_H:
		return
	_tags[y * FRAME_W + x] = TAG_RAW_BASE + _raw.size()
	_raw.append(c)


func _hline(x0: int, x1: int, y: int, mat: int, level: int) -> void:
	for x: int in range(mini(x0, x1), maxi(x0, x1) + 1):
		_px(x, y, mat, level)


func _vline(x: int, y0: int, y1: int, mat: int, level: int) -> void:
	for y: int in range(mini(y0, y1), maxi(y0, y1) + 1):
		_px(x, y, mat, level)


func _rect(x0: int, y0: int, x1: int, y1: int, mat: int, level: int) -> void:
	for y: int in range(mini(y0, y1), maxi(y0, y1) + 1):
		_hline(x0, x1, y, mat, level)


func _ell(cx: int, cy: int, rx: int, ry: int, mat: int, level: int) -> void:
	if rx < 0 or ry < 0:
		return
	var rxf: float = float(maxi(1, rx))
	var ryf: float = float(maxi(1, ry))
	for y: int in range(cy - ry, cy + ry + 1):
		for x: int in range(cx - rx, cx + rx + 1):
			var dx: float = float(x - cx) / rxf
			var dy: float = float(y - cy) / ryf
			if dx * dx + dy * dy <= 1.02:
				_px(x, y, mat, level)


## Leftmost/rightmost pixel of a `w`-wide centred column, on the 16px grid.
func _span_of(w: int) -> Vector2i:
	var x0: int = (FRAME_W - clampi(w, 1, FRAME_W)) >> 1
	return Vector2i(x0, x0 + clampi(w, 1, FRAME_W) - 1)


## One lighting rule for the entire cast: top-right lit, bottom-left shaded.
func _shade() -> void:
	var src: PackedByteArray = _tags.duplicate()
	for y: int in FRAME_H:
		for x: int in FRAME_W:
			var tag: int = src[y * FRAME_W + x]
			if tag == 0 or tag >= TAG_RAW_BASE:
				continue
			var value: int = tag - 1
			var mat: int = value >> 3
			var level: int = value & 7
			var lit: bool = _empty_in(src, x + 1, y) or _empty_in(src, x, y - 1)
			var dark: bool = _empty_in(src, x - 1, y) or _empty_in(src, x, y + 1)
			if lit and not dark:
				_px(x, y, mat, level + 1)
			elif dark and not lit:
				_px(x, y, mat, level - 1)


func _empty_in(src: PackedByteArray, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= FRAME_W or y >= FRAME_H:
		return true
	return src[y * FRAME_W + x] == 0


func _materialize() -> Image:
	var img: Image = Image.create(FRAME_W, FRAME_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y: int in FRAME_H:
		for x: int in FRAME_W:
			var tag: int = _tags[y * FRAME_W + x]
			if tag == 0:
				continue
			if tag >= TAG_RAW_BASE:
				_pc.put(img, x, y, _raw[tag - TAG_RAW_BASE])
			else:
				var value: int = tag - 1
				_pc.put(img, x, y, _pal.mat(value >> 3, value & 7))
	_pc.outline_sprite(img, _pal.darkest())
	_limit_colors(img)
	return img


## Keeps a frame inside the 15-colour budget by folding overflow tones onto the
## nearest tone that already earned its place.
func _limit_colors(img: Image) -> void:
	var order: PackedColorArray = PackedColorArray()
	var seen: Dictionary = {}
	for y: int in FRAME_H:
		for x: int in FRAME_W:
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var key: int = PixelCanvas.color_key(c)
			if not seen.has(key):
				seen[key] = order.size()
				order.append(c)
	if order.size() <= MAX_COLORS:
		return
	var kept: PackedColorArray = PackedColorArray()
	for i: int in MAX_COLORS:
		kept.append(order[i])
	for y: int in FRAME_H:
		for x: int in FRAME_W:
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var index: int = int(seen.get(PixelCanvas.color_key(c), 0))
			if index < MAX_COLORS:
				continue
			var mapped: Color = PixelCanvas.nearest_in(kept, c)
			img.set_pixel(x, y, Color(mapped.r, mapped.g, mapped.b, 1.0))


func _render_human(fig: Figure, dir: int, bob: int, stride: int, emote: int) -> Image:
	_begin(fig.district)
	var side: bool = dir == DIR_LEFT or dir == DIR_RIGHT
	var face_dir: int = 0
	if dir == DIR_LEFT:
		face_dir = -1
	elif dir == DIR_RIGHT:
		face_dir = 1
	var head_y: int = fig.head_y + bob
	var top: int = head_y + fig.head_h + 1 - fig.hunch
	if emote == EMOTE_HAPPY:
		head_y -= 1
		top -= 1
	_draw_legs(fig, side, face_dir, stride)
	_draw_body(fig, top, side, face_dir, dir)
	_draw_arms(fig, top, side, face_dir, emote)
	_draw_head(fig, head_y, side, face_dir)
	_draw_hair(fig, head_y, top, side, face_dir, dir)
	_draw_hat(fig, head_y, side, face_dir)
	_draw_face(fig, head_y, side, face_dir, dir, emote)
	_draw_scarf(fig, top, side, face_dir)
	_draw_prop(fig, top, side, face_dir, dir)
	_shade()
	return _materialize()


func _draw_legs(fig: Figure, side: bool, face_dir: int, stride: int) -> void:
	var leg_top: int = fig.hem_y + 1
	var left_x: int = 7 - fig.leg_gap - fig.leg_w + 1
	var right_x: int = 8 + fig.leg_gap
	var left_lift: bool = stride < 0
	var right_lift: bool = stride > 0
	for leg: int in 2:
		var x0: int = left_x if leg == 0 else right_x
		var mat_level: int = 2 if leg == 0 else 1
		var lift: bool = left_lift if leg == 0 else right_lift
		var shoe_row: int = 22 if lift else 22
		var bottom: int = 21 if not lift else 20
		_vline(x0, leg_top, bottom, fig.coat, mat_level)
		_vline(x0 + 1, leg_top, bottom, fig.coat, mat_level)
		var shoe_w: int = fig.leg_w + 1
		var toe: int = 1 if side else 0
		var sx0: int = x0 - (1 if face_dir < 0 else 0)
		var sx1: int = sx0 + shoe_w - 1 + toe
		_rect(sx0, shoe_row, sx1, 23, fig.accent, 0)
		if lift:
			_px(x0, 22, fig.accent, 0)
			_px(x0 + 1, 22, fig.accent, 0)


func _draw_body(fig: Figure, top: int, side: bool, face_dir: int, dir: int) -> void:
	var hem: int = fig.hem_y
	var rows: int = maxi(1, hem - top)
	var wide: int = fig.shoulder_w - (2 if side else 0)
	var narrow: int = fig.hip_w - (2 if side else 0)
	for y: int in range(top, hem + 1):
		var t: float = float(y - top) / float(rows)
		var w: int = roundi(lerpf(float(wide), float(narrow), t))
		var span: Vector2i = _span_of(w)
		_hline(span.x, span.y, y, fig.coat, LEVEL_BASE)
	var span_top: Vector2i = _span_of(wide)
	# Collar and lapel: the only coat detail that reads at this size.
	if fig.collar:
		_hline(span_top.x + 1, span_top.y - 1, top, fig.coat, 3)
	if side:
		_vline(span_top.x if face_dir > 0 else span_top.y, top + 1, hem, fig.coat, 1)
	else:
		_vline(8, top + 1, hem, fig.coat, 1)
		if fig.apron == 0:
			_px(7, top + 3, fig.accent, 1)
			_px(7, top + 5, fig.accent, 1)
	if fig.apron > 0:
		var half: int = 3 if fig.apron == 2 else 2
		var apron_top: int = top + 2
		_rect(8 - half - 1, apron_top, 7 + half, hem, fig.accent, 2)
		_vline(8 - half - 1, top + 1, apron_top, fig.accent, 2)
		_vline(7 + half, top + 1, apron_top, fig.accent, 2)
	# Hem shadow keeps the garment from melting into the legs.
	_hline(_span_of(narrow).x, _span_of(narrow).y, hem, fig.coat, 1)
	if dir == DIR_UP:
		_vline(8, top + 1, hem - 1, fig.coat, 1)


func _draw_arms(fig: Figure, top: int, side: bool, face_dir: int, emote: int) -> void:
	var hem: int = fig.hem_y
	if emote == EMOTE_HAPPY:
		var span: Vector2i = _span_of(fig.shoulder_w)
		if side:
			var hx: int = 8 + face_dir * 3
			_vline(hx, top - 1, top + 2, fig.coat, 2)
			_px(hx + face_dir, top - 2, fig.skin, 2)
		else:
			_vline(span.x - 1, top - 1, top + 2, fig.coat, 2)
			_vline(span.y + 1, top - 1, top + 2, fig.coat, 2)
			_px(span.x - 1, top - 2, fig.skin, 2)
			_px(span.y + 1, top - 2, fig.skin, 2)
		return
	if emote == EMOTE_TENSE:
		var wide: int = 4
		_hline(8 - wide, 7 + wide, top + 2, fig.coat, 2)
		_px(8 - wide - 1, top + 2, fig.skin, 2)
		_px(8 + wide, top + 2, fig.skin, 2)
		return
	if side:
		var x: int = 8 + face_dir * 2
		_vline(x, top + 1, hem - 2, fig.coat, 2)
		_px(x, hem - 1, fig.skin, 2)
		return
	var span: Vector2i = _span_of(fig.shoulder_w)
	_vline(span.x - 1, top + 1, hem - 2, fig.coat, 2)
	_vline(span.y + 1, top + 1, hem - 2, fig.coat, 2)
	_px(span.x - 1, hem - 1, fig.skin, 2)
	_px(span.y + 1, hem - 1, fig.skin, 2)


func _draw_head(fig: Figure, head_y: int, side: bool, face_dir: int) -> void:
	var span: Vector2i = _span_of(fig.head_w)
	for i: int in fig.head_h:
		var inset: int = 0
		if i == 0 or i == fig.head_h - 1:
			inset = 1
		_hline(span.x + inset, span.y - inset, head_y + i, fig.skin, 2)
	var neck_row: int = head_y + fig.head_h
	_hline(6, 9, neck_row, fig.skin, 2)
	if fig.head_w <= 6:
		_px(6, neck_row, 0, 0)
		_px(9, neck_row, 0, 0)
	if side:
		_px(span.x if face_dir > 0 else span.y, neck_row - 1, fig.skin, 2)
	if fig.beard > 0:
		var jaw: int = head_y + fig.head_h - 2
		_hline(span.x + 1, span.y - 1, jaw, fig.hair, 2)
		_hline(span.x + 2, span.y - 2, jaw + 1, fig.hair, 2)


func _draw_hair(fig: Figure, head_y: int, top: int, side: bool, face_dir: int, dir: int) -> void:
	var span: Vector2i = _span_of(fig.head_w)
	var style: int = fig.hair_style
	if style == HAIR_BALD:
		_vline(span.x, head_y + 2, head_y + 4, fig.hair, 2)
		_vline(span.y, head_y + 2, head_y + 4, fig.hair, 2)
		return
	var rows: int = 3
	if style == HAIR_FULL:
		rows = 4
	var outer: Vector2i = Vector2i(span.x - 1, span.y + 1) if style == HAIR_FULL else span
	for i: int in rows:
		if dir == DIR_UP:
			_hline(outer.x, outer.y, head_y + i, fig.hair, 2)
		elif i < rows - 1:
			_hline(outer.x, outer.y, head_y + i, fig.hair, 2)
		else:
			_hline(outer.x, outer.x + 1, head_y + i, fig.hair, 2)
			_hline(outer.y - 1, outer.y, head_y + i, fig.hair, 2)
	if style == HAIR_SWEEP and dir != DIR_UP:
		_hline(span.x, span.x + 3, head_y + rows - 1, fig.hair, 2)
	if style == HAIR_BUN:
		_ell(8, head_y - 2, 2, 1, fig.hair, 2)
	if style == HAIR_PONY:
		var back: int = 8 - face_dir * 3 if side else 8
		_vline(back, head_y + 2, top + 1, fig.hair, 2)
	if style == HAIR_LONG or style == HAIR_FULL:
		if dir == DIR_UP:
			_hline(outer.x, outer.y, head_y + rows, fig.hair, 2)
			_rect(outer.x, head_y + rows, outer.y, top, fig.hair, 2)
		else:
			_vline(span.x - 1, head_y + 2, top - 1, fig.hair, 2)
			_vline(span.y + 1, head_y + 2, top - 1, fig.hair, 2)
	if side:
		var back_x: int = span.x if face_dir > 0 else span.y
		_vline(back_x, head_y + 2, head_y + 4, fig.hair, 2)


func _draw_hat(fig: Figure, head_y: int, side: bool, face_dir: int) -> void:
	if fig.hat == HAT_NONE:
		return
	var span: Vector2i = _span_of(fig.head_w)
	match fig.hat:
		HAT_CAP:
			_hline(span.x - 1, span.y + 1, head_y + 1, fig.accent, 2)
			_hline(span.x, span.y, head_y, fig.accent, 2)
			_hline(span.x, span.y, head_y - 1, fig.accent, 2)
			if side:
				var peak: int = span.y + 2 if face_dir > 0 else span.x - 2
				_px(peak, head_y + 1, fig.accent, 1)
		HAT_CHEF:
			_hline(span.x, span.y, head_y + 1, fig.accent, 2)
			_hline(span.x, span.y, head_y, fig.accent, 2)
			_hline(span.x - 1, span.y + 1, head_y - 1, fig.accent, 2)
			_hline(span.x - 1, span.y + 1, head_y - 2, fig.accent, 2)
			_hline(span.x, span.y, head_y - 3, fig.accent, 2)
		HAT_WIDE:
			_hline(span.x - 2, span.y + 2, head_y + 1, fig.accent, 1)
			_hline(span.x - 1, span.y + 1, head_y, fig.accent, 2)
			_hline(span.x, span.y, head_y - 1, fig.accent, 2)
		HAT_BEANIE:
			_hline(span.x, span.y, head_y + 2, fig.accent, 1)
			_hline(span.x, span.y, head_y + 1, fig.accent, 2)
			_hline(span.x, span.y, head_y, fig.accent, 2)
			_hline(span.x + 1, span.y - 1, head_y - 1, fig.accent, 2)
		HAT_BERET:
			_hline(span.x - 1, span.y + 1, head_y + 1, fig.accent, 2)
			_hline(span.x, span.y, head_y, fig.accent, 2)
			_px(span.x + 1, head_y - 1, fig.accent, 2)
		HAT_TALL:
			_hline(span.x - 1, span.y + 1, head_y + 1, fig.hair, 1)
			_rect(span.x, head_y - 3, span.y, head_y, fig.hair, 1)
		HAT_HEADSCARF:
			_hline(span.x - 1, span.y + 1, head_y + 1, fig.accent, 2)
			_hline(span.x - 1, span.y + 1, head_y, fig.accent, 2)
			_hline(span.x, span.y, head_y - 1, fig.accent, 2)
			_vline(span.x - 1, head_y + 2, head_y + 4, fig.accent, 2)
			_vline(span.y + 1, head_y + 2, head_y + 4, fig.accent, 2)
			if side:
				var tail: int = span.x - 2 if face_dir > 0 else span.y + 2
				_vline(tail, head_y + 2, head_y + 5, fig.accent, 2)


func _draw_face(fig: Figure, head_y: int, side: bool, face_dir: int, dir: int, emote: int) -> void:
	if dir == DIR_UP:
		return
	var span: Vector2i = _span_of(fig.head_w)
	var eye_y: int = head_y + fig.head_h - 4
	var ink: Color = _pal.darkest()
	if side:
		var ex: int = 8 + face_dir
		_raw_px(ex, eye_y, ink)
		var nose_x: int = (span.y + 1) if face_dir > 0 else (span.x - 1)
		_px(nose_x, eye_y + 1, fig.skin, 3)
		if emote == EMOTE_TENSE:
			_px(ex, eye_y - 1, fig.hair, 1)
		elif emote == EMOTE_HAPPY:
			_raw_px(ex, eye_y - 1, ink)
		return
	var left_eye: int = span.x + 1
	var right_eye: int = span.y - 1
	_raw_px(left_eye, eye_y, ink)
	_raw_px(right_eye, eye_y, ink)
	var mouth_y: int = eye_y + 2
	match emote:
		EMOTE_HAPPY:
			_raw_px(left_eye, eye_y - 1, ink)
			_raw_px(right_eye, eye_y - 1, ink)
			_hline(6, 9, mouth_y, fig.skin, 1)
			_px(5, mouth_y - 1, fig.skin, 1)
			_px(10, mouth_y - 1, fig.skin, 1)
			if fig.head_y > 2:
				_raw_px(span.x - 1, head_y - 1, _pal.mat(fig.skin, 3))
				_raw_px(span.y + 2, head_y + 2, _pal.mat(fig.skin, 3))
		EMOTE_TENSE:
			_hline(left_eye - 1, left_eye + 1, eye_y - 1, fig.hair, 1)
			_hline(right_eye - 1, right_eye + 1, eye_y - 1, fig.hair, 1)
			_hline(7, 8, mouth_y, fig.skin, 1)
		_:
			_px(7, mouth_y, fig.skin, 1)


func _draw_scarf(fig: Figure, top: int, side: bool, face_dir: int) -> void:
	if fig.scarf == SCARF_NONE:
		return
	match fig.scarf:
		SCARF_SHORT:
			_hline(5, 10, top, fig.accent, 3)
			_hline(5, 10, top + 1, fig.accent, 2)
		SCARF_LONG:
			_hline(5, 10, top, fig.accent, 3)
			_hline(5, 10, top + 1, fig.accent, 2)
			var tail_x: int = 4 if not side or face_dir > 0 else 10
			_vline(tail_x, top + 2, top + 4, fig.accent, 2)
			_px(tail_x, top + 5, fig.accent, 3)
		SCARF_SHAWL:
			_hline(4, 11, top, fig.accent, 2)
			_hline(4, 11, top + 1, fig.accent, 2)
			_vline(4, top + 2, fig.hem_y - 3, fig.accent, 2)
			_vline(11, top + 2, fig.hem_y - 3, fig.accent, 2)


func _draw_prop(fig: Figure, top: int, side: bool, face_dir: int, dir: int) -> void:
	if fig.prop == PROP_NONE:
		return
	var hem: int = fig.hem_y
	var chest: int = top + 2
	var side_x: int = 11 if not side else (10 + face_dir)
	match fig.prop:
		PROP_ROLLING_PIN:
			_vline(side_x + 1, hem - 5, hem, fig.hair, 3)
			_px(side_x + 1, hem - 6, fig.hair, 2)
			_px(side_x + 1, hem + 1, fig.hair, 2)
		PROP_GUITAR:
			_ell(5, hem - 3, 3, 2, fig.accent, 2)
			_ell(5, hem - 3, 1, 1, fig.accent, 1)
			_vline(7, hem - 5, top - 1, fig.accent, 3)
			_hline(6, 8, top - 2, fig.accent, 2)
		PROP_WRENCH:
			_vline(side_x, chest + 2, hem - 1, fig.accent, 3)
			_px(side_x - 1, chest + 1, fig.accent, 2)
			_px(side_x + 1, chest + 1, fig.accent, 2)
			_px(side_x, chest, fig.accent, 2)
		PROP_LETTER:
			_rect(6, chest + 2, 9, chest + 3, fig.accent, 3)
			_hline(6, 9, chest + 2, fig.accent, 1)
		PROP_BRUSH:
			_vline(side_x, top + 1, chest, fig.hair, 1)
			_px(side_x, top, fig.accent, 3)
			_px(side_x - 1, top + 1, fig.accent, 2)
		PROP_BOOK:
			_rect(5, chest + 3, 9, chest + 4, fig.accent, 2)
			_hline(5, 9, chest + 3, fig.accent, 3)
			_vline(5, chest + 3, chest + 4, fig.accent, 1)
		PROP_LANTERN:
			_vline(side_x, chest, chest + 1, fig.hair, 1)
			_rect(side_x - 1, chest + 2, side_x + 1, chest + 4, fig.accent, 2)
			_px(side_x, chest + 3, fig.accent, 4)
			_px(side_x, chest + 5, fig.hair, 1)
		PROP_BASKET:
			_rect(2, hem - 4, 6, hem - 1, fig.hair, 2)
			_hline(2, 6, hem - 4, fig.hair, 3)
			_px(3, hem - 5, fig.accent, 3)
			_px(5, hem - 5, fig.accent, 2)
			_hline(2, 6, hem, fig.hair, 1)
		PROP_BAG:
			_rect(side_x - 2, hem - 4, side_x, hem - 2, fig.accent, 1)
			_hline(side_x - 2, side_x, hem - 4, fig.accent, 2)
			_px(side_x - 1, hem - 5, fig.accent, 2)
		PROP_CANE:
			_vline(side_x, chest + 2, 23, fig.hair, 2)
			_px(side_x - 1, chest + 1, fig.hair, 2)
			_px(side_x, chest + 1, fig.hair, 3)
		PROP_SCROLL:
			_rect(5, chest + 2, 10, chest + 3, fig.accent, 3)
			_hline(5, 10, chest + 2, fig.accent, 1)
			_px(4, chest + 2, fig.accent, 2)
		PROP_ROPE:
			_ell(4, hem - 3, 2, 1, fig.hair, 2)
			_ell(4, hem - 1, 2, 1, fig.hair, 2)
			_px(6, hem - 2, fig.hair, 1)
		PROP_SATCHEL:
			_rect(side_x - 2, hem - 4, side_x, hem - 1, fig.accent, 2)
			_px(side_x - 1, hem - 5, fig.accent, 1)
			_vline(side_x - 2, top + 1, hem - 5, fig.accent, 1)
		PROP_FLUTE:
			_hline(4, 11, chest + 4, fig.hair, 3)
			_hline(4, 11, chest + 5, fig.hair, 2)
			_px(9, chest + 4, fig.hair, 1)
		PROP_BUNDLE:
			_ell(6, chest + 4, 2, 2, fig.accent, 2)
			_hline(4, 8, chest + 3, fig.accent, 3)
			_px(8, chest + 6, fig.accent, 1)


func _render_creature(who: String, kind: int, phase: int, emote: int) -> Image:
	match kind:
		0:
			_begin(0)
			_cat(phase, emote)
		1:
			_begin(1)
			_pup(phase, emote)
		_:
			_begin(3)
			_pigeon(phase, emote)
	_shade()
	return _materialize()


## Curled tabby: heavy seated haunch, big round head, upright flicking tail.
func _cat(phase: int, emote: int) -> void:
	var fur: int = PixelCanvas.MAT_CLAY
	var stripe: int = PixelCanvas.MAT_WOOD
	var cream: int = PixelCanvas.MAT_CLOTH
	var bob: int = 1 if emote == EMOTE_HAPPY else 0
	_ell(8, 18, 5, 4, fur, 2)
	_rect(4, 21, 11, 22, fur, 2)
	_rect(4, 23, 5, 23, fur, 1)
	_rect(10, 23, 11, 23, fur, 1)
	_ell(8, 19, 3, 3, cream, 2)
	_vline(6, 20, 22, fur, 2)
	_vline(10, 20, 22, fur, 1)
	_hline(5, 11, 15, stripe, 1)
	_hline(4, 11, 17, stripe, 1)
	_hline(5, 10, 20, stripe, 1)
	var tail_x: int = 13 if phase == 0 else 14
	_vline(tail_x, 11, 20, fur, 2)
	_px(tail_x - 1, 21, fur, 1)
	_px(tail_x, 10, fur, 3)
	_px(tail_x + 1, 9, fur, 2)
	_px(tail_x if phase == 1 else tail_x + 1, 8, fur, 3 if phase == 1 else 1)
	var head_y: int = 9 - bob
	_ell(8, head_y, 4, 3, fur, 2)
	_rect(5, head_y - 5, 6, head_y - 2, fur, 2)
	_rect(9, head_y - 5, 10, head_y - 2, fur, 1)
	_px(5, head_y - 4, cream, 3)
	_px(10, head_y - 4, cream, 2)
	_hline(6, 10, head_y - 1, stripe, 1)
	_hline(7, 9, head_y + 2, cream, 3)
	_face_cat(head_y, emote)


func _face_cat(head_y: int, emote: int) -> void:
	if emote == EMOTE_HAPPY:
		_raw_px(7, head_y - 1, _pal.darkest())
		_raw_px(9, head_y - 1, _pal.darkest())
		_raw_px(7, head_y - 2, _pal.darkest())
		_raw_px(9, head_y - 2, _pal.darkest())
		_raw_px(8, head_y + 1, _pal.mat(PixelCanvas.MAT_SKIN, 3))
	else:
		_raw_px(7, head_y, _pal.darkest())
		_raw_px(9, head_y, _pal.darkest())
		_px(8, head_y + 1, PixelCanvas.MAT_SKIN, 3)


## Round-eared pup: oversized head, floppy ear, collar tag, wagging tail.
func _pup(phase: int, emote: int) -> void:
	var fur: int = PixelCanvas.MAT_WOOD
	var ear: int = PixelCanvas.MAT_CLAY
	var cream: int = PixelCanvas.MAT_CLOTH
	var bob: int = 1 if emote == EMOTE_HAPPY else 0
	_ell(8, 18, 4, 4, fur, 2)
	_ell(8, 19, 2, 2, cream, 3)
	_vline(6, 20, 23, fur, 2)
	_vline(10, 20, 23, fur, 1)
	_hline(5, 7, 23, fur, 2)
	_hline(9, 11, 23, fur, 1)
	_vline(12, 13, 16, fur, 2)
	_px(13, 12 if phase == 0 else 14, fur, 3)
	var head_y: int = 11 - bob
	_ell(8, head_y, 3, 3, fur, 2)
	_rect(4, head_y - 1, 5, head_y + 3, ear, 1)
	_rect(10, head_y - 2, 11, head_y + 1, ear, 2)
	_rect(7, head_y + 2, 9, head_y + 3, cream, 3)
	_hline(5, 11, head_y + 4, ear, 1)
	_px(9, head_y + 4, ear, 0)
	_raw_px(8, head_y + 2, _pal.darkest())
	_raw_px(7, head_y, _pal.darkest())
	_raw_px(9, head_y, _pal.darkest())
	if emote == EMOTE_HAPPY:
		_raw_px(7, head_y - 1, _pal.darkest())
		_raw_px(9, head_y - 1, _pal.darkest())
		_px(8, head_y + 3, cream, 2)


## Perched pigeon: plump chest, swept tail, iridescent neck, two-toed feet.
func _pigeon(phase: int, emote: int) -> void:
	var body: int = PixelCanvas.MAT_STONE
	var sheen: int = PixelCanvas.MAT_WATER
	var beak: int = PixelCanvas.MAT_CLAY
	var bob: int = 1 if emote == EMOTE_HAPPY else 0
	_ell(8, 17, 4, 3, body, 2)
	_ell(7, 17, 3, 2, sheen, 1)
	_hline(5, 8, 15, sheen, 2)
	_px(3, 18, body, 1)
	_px(2, 19, body, 1)
	_px(3, 19, body, 1)
	_px(2, 20, body, 1)
	_px(3, 20, body, 2)
	_px(1, 21, body, 1)
	_px(2, 21, body, 2)
	_vline(7, 20, 22, beak, 1)
	_vline(9, 20, 22, beak, 1)
	_hline(6, 8, 23, beak, 2)
	_hline(8, 10, 23, beak, 1)
	var head_y: int = 10 - bob
	_ell(9, head_y, 2, 2, body, 2)
	_hline(9, 10, head_y + 1, sheen, 3)
	_px(11, head_y, beak, 2)
	_px(12, head_y, beak, 3)
	_raw_px(10, head_y - 1, _pal.darkest())
	if phase == 1:
		_px(1, 22, body, 1)
		_px(12, head_y + 1, beak, 1)
	if emote == EMOTE_HAPPY:
		_raw_px(10, head_y - 2, _pal.darkest())
		_px(12, head_y - 1, beak, 4)


func _render_object(who: String, kind: int, phase: int, happy: bool) -> Image:
	match kind:
		0:
			_begin(0)
			_boule(phase, happy)
		1:
			_begin(1)
			_tea_set(phase, happy)
		_:
			_begin(3)
			_shrine_lamp(phase, happy)
	_shade()
	return _materialize()


## Domed boule, flat bake line, cross score and flour dust.
func _boule(phase: int, happy: bool) -> void:
	var crust: int = PixelCanvas.MAT_CLAY
	var flour: int = PixelCanvas.MAT_CLOTH
	var lift: int = 1 if happy else 0
	var rise: int = 1 if phase == 1 else 0
	_ell(8, 16 - lift, 6, 5 + rise, crust, 2)
	_rect(3, 21, 12, 21, crust, 1)
	_hline(2, 13, 22, crust, 1)
	_hline(3, 12, 20, crust, 3)
	_vline(8, 12 - lift, 18, flour, 3)
	_hline(4, 11, 15 - lift, flour, 3)
	_px(8, 16 - lift, crust, 1)
	_px(4, 18, flour, 4)
	_px(11, 13, flour, 4)
	_px(6, 19, flour, 4)
	if happy:
		_px(3, 12, flour, 4)
		_px(13, 17, flour, 4)
		_px(8, 9, flour, 3)


## Lacquered tray with two cups; steam only on the second frame.
func _tea_set(phase: int, happy: bool) -> void:
	var wood: int = PixelCanvas.MAT_WOOD
	var ceramic: int = PixelCanvas.MAT_CLOTH
	var tea: int = PixelCanvas.MAT_MOSS
	_rect(2, 22, 13, 23, wood, 0)
	_rect(1, 19, 14, 20, wood, 2)
	_hline(0, 15, 21, wood, 1)
	_hline(2, 13, 22, wood, 1)
	_hline(1, 14, 19, wood, 3)
	_px(0, 19, wood, 1)
	_px(15, 19, wood, 1)
	for cup: int in 2:
		var x0: int = 3 + cup * 5
		_rect(x0, 14, x0 + 3, 18, ceramic, 2)
		_hline(x0, x0 + 3, 14, ceramic, 3)
		_px(x0 + 4, 16, ceramic, 2)
		_px(x0 + 4, 17, ceramic, 1)
		_hline(x0 + 1, x0 + 2, 15, tea, 2)
		_hline(x0 - 1, x0 + 4, 19, ceramic, 1)
	var steam_y: int = 12 if phase == 1 or happy else 13
	_px(5, steam_y, ceramic, 3)
	_px(4, steam_y - 1, ceramic, 3)
	_px(10, steam_y - 1, ceramic, 3)
	if happy:
		_px(7, 10, ceramic, 4)
		_px(12, 11, ceramic, 4)


## Small oil lamp: stepped base, wide bowl, side spout, handle and flame.
func _shrine_lamp(phase: int, happy: bool) -> void:
	var metal: int = PixelCanvas.MAT_METAL
	var flame: int = PixelCanvas.MAT_CLAY
	var oil: int = PixelCanvas.MAT_WATER
	_rect(4, 22, 11, 23, metal, 1)
	_rect(5, 21, 10, 21, metal, 2)
	_ell(8, 18, 4, 2, metal, 2)
	_hline(4, 11, 16, metal, 3)
	_hline(6, 9, 19, oil, 1)
	_px(12, 17, metal, 2)
	_px(13, 16, metal, 2)
	_px(13, 15, metal, 3)
	_px(3, 16, metal, 1)
	_px(2, 17, metal, 1)
	_px(3, 18, metal, 1)
	var tip: int = 13 if phase == 1 else 14
	_vline(8, tip + 1, 15, flame, 2)
	_px(8, tip, flame, 3)
	_px(7, 15, flame, 1)
	if happy:
		_px(8, tip - 1, flame, 4)
		_px(6, tip + 1, flame, 3)
		_px(10, tip + 2, flame, 3)


func _render_bloom(kind: int, phase: int, happy: bool) -> Image:
	match kind:
		0:
			_begin(1)
			_hibiscus(phase, happy)
		1:
			_begin(0)
			_marigold(phase, happy)
		_:
			_begin(2)
			_camelia(phase, happy)
	_shade()
	return _materialize()


func _bloom_base(sway: int) -> void:
	var clay: int = PixelCanvas.MAT_CLAY
	var leaf: int = PixelCanvas.MAT_MOSS
	var soil: int = PixelCanvas.MAT_WOOD
	_rect(4, 20, 11, 21, clay, 2)
	_rect(5, 22, 10, 23, clay, 1)
	_hline(4, 11, 20, clay, 3)
	_hline(5, 10, 21, soil, 1)
	_vline(8, 12, 20, leaf, 2)
	_hline(8 + sway, 8 + sway, 12, leaf, 2)
	_ell(5, 16, 2, 1, leaf, 2)
	_px(4, 15, leaf, 3)
	_ell(11, 14, 2, 1, leaf, 2)
	_px(12, 13, leaf, 3)
	_vline(8 + sway, 9, 12, leaf, 2)


func _hibiscus(phase: int, happy: bool) -> void:
	var bloom: int = PixelCanvas.MAT_CLAY
	var sway: int = 1 if phase == 1 else 0
	_bloom_base(sway)
	var cx: int = 8 + sway
	_ell(cx, 7, 4, 3, bloom, 2)
	_ell(cx, 7, 2, 2, bloom, 3)
	_px(cx, 7, bloom, 1)
	_px(cx - 3, 6, bloom, 1)
	_px(cx + 3, 6, bloom, 1)
	_px(cx - 2, 9, bloom, 1)
	_px(cx + 2, 9, bloom, 1)
	_vline(cx + 1, 4, 6, bloom, 3)
	_px(cx + 2, 3, bloom, 4)
	_px(cx + 3, 3, bloom, 3)
	if happy:
		_ell(cx, 7, 5, 4, bloom, 2)
		_ell(cx, 7, 2, 2, bloom, 4)
		_px(cx + 3, 4, bloom, 4)
		_px(cx - 4, 8, bloom, 3)


func _marigold(phase: int, happy: bool) -> void:
	var bloom: int = PixelCanvas.MAT_CLAY
	var sway: int = 1 if phase == 1 else 0
	_bloom_base(sway)
	var cx: int = 8 + sway
	_ell(cx, 7, 3, 3, bloom, 2)
	_ell(cx, 7, 2, 2, bloom, 3)
	_px(cx - 2, 5, bloom, 1)
	_px(cx + 2, 8, bloom, 1)
	_px(cx + 1, 4, bloom, 1)
	_px(cx - 1, 9, bloom, 1)
	_px(cx, 6, bloom, 4)
	if happy:
		_ell(cx, 7, 4, 4, bloom, 2)
		_ell(cx, 7, 2, 2, bloom, 4)
		_px(cx + 3, 4, bloom, 4)
		_px(cx - 3, 10, bloom, 3)


func _camelia(phase: int, happy: bool) -> void:
	var bloom: int = PixelCanvas.MAT_CLOTH
	var sway: int = 1 if phase == 1 else 0
	_bloom_base(sway)
	var cx: int = 8 + sway
	_ell(cx, 7, 3, 3, bloom, 2)
	_ell(cx, 7, 1, 1, bloom, 3)
	_px(cx, 7, PixelCanvas.MAT_CLAY, 2)
	_px(cx - 3, 5, bloom, 3)
	_px(cx + 3, 5, bloom, 3)
	_px(cx - 3, 9, bloom, 1)
	_px(cx + 3, 9, bloom, 1)
	_px(cx - 1, 3, bloom, 2)
	_px(cx + 1, 3, bloom, 2)
	_px(cx, 4, bloom, 3)
	if happy:
		_ell(cx, 7, 4, 4, bloom, 2)
		_ell(cx, 7, 1, 1, bloom, 4)
		_px(cx + 3, 3, bloom, 4)
		_px(cx - 4, 6, bloom, 3)


## Body-plan knobs. One archetype = one Figure; silhouettes differ by
## proportion (head size, shoulder width, hem height, leg weight) before colour.
class Figure:
	var skin: int = PixelCanvas.MAT_SKIN
	var coat: int = PixelCanvas.MAT_CLOTH
	var accent: int = PixelCanvas.MAT_CLAY
	var hair: int = PixelCanvas.MAT_WOOD
	var district: int = 0

	var head_w: int = 6
	var head_h: int = 7
	var head_y: int = 2
	var shoulder_w: int = 9
	var hip_w: int = 7
	var hem_y: int = 18
	var leg_w: int = 2
	var leg_gap: int = 1
	var boot: bool = false
	var skirt: bool = false
	var apron: int = 0
	var hair_style: int = HAIR_SHORT
	var hat: int = HAT_NONE
	var scarf: int = SCARF_NONE
	var prop: int = PROP_NONE
	var beard: int = 0
	var hunch: int = 0
	var collar: bool = true
