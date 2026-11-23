class_name PropSpriteGen
extends RefCounted
## Procedural prop sprites for Sunshift.
##
## Every prop is drawn on a 16x32 canvas whose foot point is the bottom-centre
## pixel (8, 31): the art sits above its tile, so the scene owns any offset.
## Light always comes from the top-right; every sprite gets a 1px sunlit rim on
## its upper/right edges and the local shadow tint on its lower/left edges.
## Alpha is binary and every colour comes from the district-0 ramp in
## `data/palettes.json` (via `PixelCanvas`), so one prop never exceeds 31 colours.

const CANVAS_W: int = 16
const CANVAS_H: int = 32
const FOOT: Vector2i = Vector2i(8, 31)
const TYPE_COUNT: int = 6

const MIRROR: int = 0
const AWNING: int = 1
const SHUTTER: int = 2
const PRISM: int = 3
const STAINED_GLASS: int = 4
const LANTERN: int = 5

const STATE_ANIM: String = "state_"
const GLOW_ANIM: String = "glow"
const MAX_STATES: int = 8

static var _texture_cache: Dictionary = {}
static var _frames_cache: Dictionary = {}
static var _atlas_cache: Dictionary = {}
static var _palette_cache: Dictionary = {}


## Number of meaningful visual states a prop type owns.
static func state_count(prop_type: int) -> int:
	var p: int = clampi(prop_type, 0, TYPE_COUNT - 1)
	if p == MIRROR or p == AWNING or p == SHUTTER:
		return 2
	return 1


## Cached single-frame texture for one prop state.
static func build_texture(prop_type: int, state: int) -> Texture2D:
	var p: int = clampi(prop_type, 0, TYPE_COUNT - 1)
	var s: int = clampi(state, 0, state_count(p) - 1)
	var key: int = p * 16 + s
	var cached: Variant = _texture_cache.get(key)
	if cached != null:
		return cached as Texture2D
	var tex: Texture2D = ImageTexture.create_from_image(render_image(p, s))
	_texture_cache[key] = tex
	return tex


## Cached SpriteFrames: one `state_N` animation per state, plus `glow` for the
## lantern. Frames are AtlasTexture regions of one 16x32-per-column strip.
static func build_frames(prop_type: int, states: int) -> SpriteFrames:
	var p: int = clampi(prop_type, 0, TYPE_COUNT - 1)
	var count: int = clampi(states, 1, MAX_STATES)
	var key: int = p * 16 + count
	var cached: Variant = _frames_cache.get(key)
	if cached != null:
		return cached as SpriteFrames

	var images: Array[Image] = []
	for s: int in count:
		images.append(render_image(p, clampi(s, 0, state_count(p) - 1)))
	var glow_frames: int = 2 if p == LANTERN else 0
	for g: int in glow_frames:
		images.append(render_glow(g))

	var columns: int = images.size()
	var atlas: Image = Image.create_empty(CANVAS_W * columns, CANVAS_H, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.0, 0.0, 0.0, 0.0))
	for i: int in columns:
		_stamp(atlas, images[i], i * CANVAS_W, 0)
	var atlas_texture: ImageTexture = ImageTexture.create_from_image(atlas)
	_atlas_cache[key] = atlas_texture

	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	for s: int in count:
		var anim: String = STATE_ANIM + str(s)
		frames.add_animation(anim)
		frames.set_animation_loop(anim, false)
		frames.add_frame(anim, _region(atlas_texture, s))

	if p == LANTERN:
		frames.add_animation(GLOW_ANIM)
		frames.set_animation_loop(GLOW_ANIM, true)
		frames.set_animation_speed(GLOW_ANIM, 3.0)
		for g: int in glow_frames:
			frames.add_frame(GLOW_ANIM, _region(atlas_texture, count + g))

	_frames_cache[key] = frames
	return frames


## Renders one prop state into a fresh 16x32 RGBA image (binary alpha).
static func render_image(prop_type: int, state: int) -> Image:
	var p: int = clampi(prop_type, 0, TYPE_COUNT - 1)
	var s: int = clampi(state, 0, state_count(p) - 1)
	var img: Image = Image.create_empty(CANVAS_W, CANVAS_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var pc: PixelCanvas = PixelCanvas.new()
	var pal: PixelCanvas.Palette = _palette()
	match p:
		MIRROR:
			_render_mirror(pc, img, pal, s)
		AWNING:
			_render_awning(pc, img, pal, s)
		SHUTTER:
			_render_shutter(pc, img, pal, s)
		PRISM:
			_render_prism(pc, img, pal)
		STAINED_GLASS:
			_render_stained_glass(pc, img, pal)
		LANTERN:
			_render_lantern(pc, img, pal, -1)
		_:
			_render_lantern(pc, img, pal, -1)
	return img


## One glow pulse frame for the lantern. `level` 0 = dim, 1 = bright.
static func render_glow(level: int) -> Image:
	var img: Image = Image.create_empty(CANVAS_W, CANVAS_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var pc: PixelCanvas = PixelCanvas.new()
	_render_lantern(pc, img, _palette(), clampi(level, 0, 1))
	return img


static func _palette() -> PixelCanvas.Palette:
	var cached: Variant = _palette_cache.get(0)
	if cached != null:
		return cached as PixelCanvas.Palette
	var source: PixelCanvas.Palette = PixelCanvas.load_palette(0)
	var warm: PixelCanvas.Palette = PixelCanvas.Palette.new()
	warm.district = source.district
	warm.display_name = source.display_name
	warm.act = source.act
	warm.base = source.ramp(0.85)
	warm.twilight = warm.base
	warm.golden = warm.base
	_palette_cache[0] = warm
	return warm


static func _region(atlas_texture: ImageTexture, column: int) -> AtlasTexture:
	var slice: AtlasTexture = AtlasTexture.new()
	slice.atlas = atlas_texture
	slice.region = Rect2(float(column * CANVAS_W), 0.0, float(CANVAS_W), float(CANVAS_H))
	return slice


static func _stamp(dst: Image, src: Image, ox: int, oy: int) -> void:
	for y: int in src.get_height():
		for x: int in src.get_width():
			var c: Color = src.get_pixel(x, y)
			if c.a <= 0.5:
				continue
			dst.set_pixel(ox + x, oy + y, Color(c.r, c.g, c.b, 1.0))


## Sets one pixel fully transparent (PixelCanvas.put always writes alpha 1).
static func _clear(img: Image, x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))


static func _alpha_mask(img: Image) -> PackedByteArray:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	for y: int in h:
		for x: int in w:
			if img.get_pixel(x, y).a > 0.5:
				mask[y * w + x] = 1
	return mask


## 1px sunlit rim on upper/right silhouette edges, shadow tint lower/left.
static func _rim(img: Image, mask: PackedByteArray, light: Color, dark: Color) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var pc: PixelCanvas = PixelCanvas.new()
	for y: int in h:
		for x: int in w:
			if mask[y * w + x] == 0:
				continue
			var open_up: bool = y == 0 or mask[(y - 1) * w + x] == 0
			var open_right: bool = x >= w - 1 or mask[y * w + x + 1] == 0
			var open_down: bool = y >= h - 1 or mask[(y + 1) * w + x] == 0
			var open_left: bool = x == 0 or mask[y * w + x - 1] == 0
			if open_up or open_right:
				pc.put(img, x, y, light)
			elif open_down or open_left:
				pc.put(img, x, y, dark)


## Sloped canopy row helper: draws one horizontal span of a canopy.
static func _span(pc: PixelCanvas, img: Image, y: int, x0: int, x1: int, colours: PackedColorArray) -> void:
	if x1 < x0 or colours.is_empty():
		return
	for x: int in range(x0, x1 + 1):
		var band: int = (x - x0) / 2
		pc.put(img, x, y, colours[band % colours.size()])


static func _render_mirror(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette, state: int) -> void:
	var wood_d: Color = pal.mat(PixelCanvas.MAT_WOOD, 0)
	var wood_m: Color = pal.mat(PixelCanvas.MAT_WOOD, 0)
	var wood_l: Color = pal.mat(PixelCanvas.MAT_WOOD, 4)
	var ink: Color = pal.darkest()
	var metal: PackedColorArray = PackedColorArray([
		pal.mat(PixelCanvas.MAT_METAL, 1),
		pal.mat(PixelCanvas.MAT_METAL, 3),
		pal.mat(PixelCanvas.MAT_METAL, 4),
	])
	var specular: Color = pal.color(PixelCanvas.CLOTH_LIGHT)

	pc.fill_rect(img, Rect2i(4, 28, 9, 4), wood_m)
	pc.hline(img, 4, 12, 28, wood_l)
	pc.hline(img, 4, 12, 31, wood_d)
	pc.vline(img, 7, 20, 28, wood_m)
	pc.vline(img, 8, 20, 28, wood_l)

	# Angled plate: state 0 leans "/" (E->N), state 1 leans "\" (E->S).
	var glass: Array[Vector2i] = []
	var frame: Array[Vector2i] = []
	for y: int in range(3, 28):
		for x: int in CANVAS_W:
			var dx: float = float(x - 8)
			var dy: float = float(y - 15)
			var d: float = (dx + dy) * 0.7071 if state == 0 else (dx - dy) * 0.7071
			var t: float = (dx - dy) * 0.7071 if state == 0 else (dx + dy) * 0.7071
			if absf(t) > 7.4:
				continue
			if absf(d) <= 3.3:
				glass.append(Vector2i(x, y))
			elif absf(d) <= 4.9:
				frame.append(Vector2i(x, y))
	for cell: Vector2i in frame:
		pc.put(img, cell.x, cell.y, wood_m)

	var lowest: float = 0.0
	var highest: float = 0.0
	var first: bool = true
	for cell: Vector2i in glass:
		var lit: float = float(cell.x) - float(cell.y)
		if first:
			lowest = lit
			highest = lit
			first = false
		lowest = minf(lowest, lit)
		highest = maxf(highest, lit)
	var span: float = maxf(1.0, highest - lowest)
	for cell: Vector2i in glass:
		var lit: float = float(cell.x) - float(cell.y)
		var ramp_t: float = clampf((lit - lowest) / span, 0.0, 1.0)
		var tone: int = clampi(roundi(ramp_t * float(metal.size() - 1)), 0, metal.size() - 1)
		pc.put(img, cell.x, cell.y, metal[tone])

	var mask: PackedByteArray = _alpha_mask(img)
	_rim(img, mask, wood_l, wood_d)

	for cell: Vector2i in glass:
		var lit: float = float(cell.x) - float(cell.y)
		var dx: float = float(cell.x - 8)
		var dy: float = float(cell.y - 15)
		var t: float = (dx - dy) * 0.7071 if state == 0 else (dx + dy) * 0.7071
		if lit > highest - 2.0 and absf(t) < 5.0:
			pc.put(img, cell.x, cell.y, specular)


static func _render_awning(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette, state: int) -> void:
	var iron: Color = pal.mat(PixelCanvas.MAT_METAL, 2)
	var iron_l: Color = pal.mat(PixelCanvas.MAT_METAL, 4)
	var iron_d: Color = pal.mat(PixelCanvas.MAT_METAL, 0)
	var cerulean: Color = pal.color(PixelCanvas.WATER_MID)
	var cerulean_d: Color = pal.color(PixelCanvas.WATER_DARK)
	var cerulean_l: Color = pal.color(PixelCanvas.WATER_LIGHT)
	var cream: Color = pal.color(PixelCanvas.CLOTH_MID)
	var cream_l: Color = pal.color(PixelCanvas.CLOTH_LIGHT)
	var ink: Color = pal.darkest()

	for x: int in [2, 13]:
		pc.vline(img, x, 11, 28, iron_d)
		pc.vline(img, x + 1, 11, 28, iron)
	pc.fill_rect(img, Rect2i(1, 28, 4, 3), iron)
	pc.fill_rect(img, Rect2i(11, 28, 4, 3), iron)
	pc.hline(img, 1, 4, 28, iron_l)
	pc.hline(img, 11, 14, 28, iron_l)
	pc.put(img, 1, 31, ink)
	pc.put(img, 14, 31, ink)
	pc.hline(img, 5, 10, 30, iron_d)
	pc.hline(img, 4, 11, 31, ink)

	pc.fill_rect(img, Rect2i(1, 9, 14, 2), iron)
	pc.hline(img, 1, 14, 9, iron_l)
	pc.hline(img, 1, 14, 10, iron_d)
	pc.put(img, 0, 8, iron_l)
	pc.put(img, 15, 8, iron_l)
	pc.put(img, 15, 9, iron)

	var bottom: int = 16 if state == 0 else 24
	var stripes: PackedColorArray = PackedColorArray([cerulean, cream])
	for y: int in range(11, bottom + 1):
		_span(pc, img, y, 1, 14, stripes)

	if state == 0:
		# Retracted: the hem folds up in tight rolls under the rail.
		for y: int in [13, 15, 16]:
			pc.hline(img, 1, 14, y, cerulean_d)
		pc.hline(img, 1, 14, 12, cream_l)
	else:
		# Extended: a deep valance with scallops and hanging tassels.
		for x: int in range(1, 15):
			if posmod(x - 1, 4) == 3:
				_clear(img, x, bottom)
			else:
				pc.put(img, x, bottom, cerulean_d if posmod(x - 1, 4) < 2 else cream_l)
		for x: int in [2, 6, 10, 14]:
			pc.put(img, x, bottom + 1, cream_l)
			pc.put(img, x, bottom + 2, cream)
		pc.hline(img, 1, 14, 12, cream_l)

	var mask: PackedByteArray = _alpha_mask(img)
	_rim(img, mask, cream_l, ink)
	# Re-assert the stripe rhythm after the rim pass so the awning still reads.
	for y: int in range(12, bottom):
		for x: int in range(2, 14):
			var band: int = ((x - 1) / 2) % 2
			pc.put(img, x, y, cerulean_l if band == 0 and y < 14 else (cerulean if band == 0 else cream))
	pc.vline(img, 13, 12, bottom - 1, cerulean_l)


static func _render_shutter(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette, state: int) -> void:
	var teak_d: Color = pal.mat(PixelCanvas.MAT_WOOD, 0)
	var teak_m: Color = pal.mat(PixelCanvas.MAT_WOOD, 2)
	var teak_l: Color = pal.mat(PixelCanvas.MAT_WOOD, 4)
	var iron: Color = pal.mat(PixelCanvas.MAT_METAL, 1)
	var ink: Color = pal.darkest()
	var sill: Color = pal.mat(PixelCanvas.MAT_STONE, 2)
	var sill_l: Color = pal.mat(PixelCanvas.MAT_STONE, 4)

	# Sill first, so both states stand on the same base.
	pc.fill_rect(img, Rect2i(2, 26, 12, 3), sill)
	pc.hline(img, 2, 13, 26, sill_l)
	pc.hline(img, 2, 13, 28, teak_d)
	pc.hline(img, 2, 13, 29, pal.mat(PixelCanvas.MAT_STONE, 0))
	pc.hline(img, 1, 14, 30, teak_d)
	pc.fill_rect(img, Rect2i(4, 30, 8, 2), pal.mat(PixelCanvas.MAT_STONE, 0))

	if state == 0:
		# Closed: full slatted teak panel across the opening.
		pc.fill_rect(img, Rect2i(3, 5, 10, 21), teak_m)
		for y: int in range(7, 25, 2):
			pc.hline(img, 4, 11, y, teak_d)
			pc.hline(img, 4, 11, y + 1, teak_l)
		pc.rect_outline(img, Rect2i(3, 5, 10, 21), teak_d)
		pc.vline(img, 12, 5, 25, teak_l)
		pc.hline(img, 3, 12, 5, teak_l)
		pc.fill_rect(img, Rect2i(3, 9, 2, 2), iron)
		pc.fill_rect(img, Rect2i(3, 19, 2, 2), iron)
	else:
		# Open: both leaves swing clear, showing the dark room behind.
		pc.fill_rect(img, Rect2i(5, 5, 6, 21), ink)
		for y: int in range(6, 25, 3):
			pc.hline(img, 5, 10, y, pal.mat(PixelCanvas.MAT_STONE, 0))
		for x: int in [1, 11]:
			pc.fill_rect(img, Rect2i(x, 5, 4, 21), teak_d)
			pc.vline(img, x + 3, 5, 25, teak_m)
			for y: int in range(7, 25, 2):
				pc.hline(img, x, x + 2, y, teak_l)
		pc.fill_rect(img, Rect2i(3, 10, 2, 2), iron)
		pc.fill_rect(img, Rect2i(9, 10, 2, 2), iron)
		pc.hline(img, 4, 11, 25, teak_l)

	var mask: PackedByteArray = _alpha_mask(img)
	_rim(img, mask, teak_l, ink)


static func _render_prism(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette) -> void:
	var brass_d: Color = pal.mat(PixelCanvas.MAT_METAL, 0)
	var brass: Color = pal.mat(PixelCanvas.MAT_METAL, 2)
	var brass_l: Color = pal.mat(PixelCanvas.MAT_METAL, 4)
	var ink: Color = pal.darkest()
	var glass: PackedColorArray = PackedColorArray([
		pal.mat(PixelCanvas.MAT_WATER, 1),
		pal.mat(PixelCanvas.MAT_WATER, 2),
		pal.mat(PixelCanvas.MAT_WATER, 3),
		pal.mat(PixelCanvas.MAT_WATER, 4),
	])
	var sparkle: Color = pal.color(PixelCanvas.CLOTH_LIGHT)

	for y: int in range(2, 7):
		pc.put(img, 8, y, brass if posmod(y, 2) == 0 else brass_l)
	pc.put(img, 7, 2, brass_d)
	pc.put(img, 9, 2, brass_d)
	for y: int in range(25, 31):
		pc.put(img, 8, y, brass if posmod(y, 2) == 0 else brass_l)
	pc.put(img, 8, 31, brass_d)

	# Faceted crystal: a rhombus with four quadrants reading as cut glass.
	var top: int = 6
	var mid: int = 15
	var bottom: int = 25
	for y: int in range(top, bottom + 1):
		var half: int = 0
		if y <= mid:
			half = roundi(6.0 * float(y - top) / float(mid - top))
		else:
			half = roundi(6.0 * float(bottom - y) / float(bottom - mid))
		for x: int in range(8 - half, 8 + half + 1):
			var tone: int = 0
			if x >= 8 and y <= mid:
				tone = 3
			elif x >= 8:
				tone = 2
			elif y <= mid:
				tone = 1
			else:
				tone = 0
			pc.put(img, x, y, glass[tone])

	for i: int in 4:
		pc.put(img, 8 - i, mid - i, pal.mat(PixelCanvas.MAT_WATER, 0))
		pc.put(img, 8 + i, mid - i, pal.mat(PixelCanvas.MAT_WATER, 0))
		pc.put(img, 8 - i, mid + i, pal.mat(PixelCanvas.MAT_WATER, 0))
		pc.put(img, 8 + i, mid + i, pal.mat(PixelCanvas.MAT_WATER, 0))
	pc.put(img, 10, 12, sparkle)
	pc.put(img, 11, 13, sparkle)
	pc.put(img, 9, 11, sparkle)

	var mask: PackedByteArray = _alpha_mask(img)
	_rim(img, mask, sparkle, ink)


static func _render_stained_glass(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette) -> void:
	var lead: Color = pal.mat(PixelCanvas.MAT_METAL, 0)
	var lead_l: Color = pal.mat(PixelCanvas.MAT_METAL, 2)
	var rose: Color = pal.mat(PixelCanvas.MAT_CLAY, 2)
	var rose_l: Color = pal.mat(PixelCanvas.MAT_CLAY, 4)
	var rose_d: Color = pal.mat(PixelCanvas.MAT_CLAY, 1)
	var gold: Color = pal.mat(PixelCanvas.MAT_METAL, 4)
	var gold_d: Color = pal.mat(PixelCanvas.MAT_METAL, 3)
	var stone: Color = pal.mat(PixelCanvas.MAT_STONE, 2)
	var stone_l: Color = pal.mat(PixelCanvas.MAT_STONE, 4)
	var ink: Color = pal.darkest()

	pc.fill_rect(img, Rect2i(2, 27, 12, 3), stone)
	pc.hline(img, 2, 13, 27, stone_l)
	pc.hline(img, 2, 13, 30, pal.mat(PixelCanvas.MAT_STONE, 0))
	pc.fill_rect(img, Rect2i(5, 30, 7, 2), pal.mat(PixelCanvas.MAT_STONE, 0))

	pc.fill_rect(img, Rect2i(2, 5, 12, 22), rose)
	for y: int in range(6, 26, 3):
		for x: int in range(3, 13, 3):
			pc.put(img, x, y, rose_l if posmod(x + y, 2) == 0 else gold_d)

	pc.disc(img, 8, 12, 4, lead)
	pc.disc(img, 8, 12, 3, gold)
	pc.disc(img, 8, 12, 1, rose_l)
	pc.put(img, 9, 10, pal.color(PixelCanvas.CLOTH_LIGHT))

	pc.hline(img, 2, 13, 18, lead)
	pc.vline(img, 8, 18, 26, lead)
	pc.fill_rect(img, Rect2i(3, 19, 5, 8), rose_d)
	pc.fill_rect(img, Rect2i(9, 19, 4, 8), rose)
	for y: int in range(20, 26, 2):
		pc.put(img, 4, y, gold)
		pc.put(img, 11, y, gold_d)

	# Lead came around the outside, lit from the top-right.
	pc.rect_outline(img, Rect2i(2, 5, 12, 22), lead)
	var mask: PackedByteArray = _alpha_mask(img)
	_rim(img, mask, pal.color(PixelCanvas.CLOTH_LIGHT), ink)
	pc.vline(img, 13, 6, 26, lead_l)


static func _render_lantern(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette, glow: int) -> void:
	var iron_d: Color = pal.darkest()
	var iron: Color = pal.mat(PixelCanvas.MAT_METAL, 1)
	var iron_l: Color = pal.mat(PixelCanvas.MAT_METAL, 3)
	var ink: Color = pal.darkest()
	var warm_outer: Color = pal.mat(PixelCanvas.MAT_CLAY, 4)
	var warm_mid: Color = pal.color(PixelCanvas.CLOTH_MID)
	var warm_core: Color = pal.color(PixelCanvas.CLOTH_LIGHT)

	# Body is drawn apart from the halo so the rim pass never touches the glow.
	var body: Image = Image.create_empty(CANVAS_W, CANVAS_H, false, Image.FORMAT_RGBA8)
	body.fill(Color(0.0, 0.0, 0.0, 0.0))

	pc.put(body, 8, 1, iron_d)
	pc.vline(body, 8, 2, 5, iron)
	pc.fill_rect(body, Rect2i(6, 6, 5, 2), iron)
	pc.hline(body, 6, 10, 6, iron_l)
	pc.hline(body, 5, 11, 8, iron)
	pc.hline(body, 6, 10, 9, iron_l)
	pc.hline(body, 4, 12, 10, iron_d)

	pc.ellipse_outline(body, 8, 18, 5, 7, iron)
	pc.vline(body, 3, 14, 22, iron_d)
	pc.vline(body, 12, 14, 22, iron_l)
	pc.hline(body, 3, 12, 18, iron_d)

	# Glass: warm core offset toward the top-right light.
	for y: int in range(12, 25):
		for x: int in range(3, 14):
			var dx: float = float(x - 8) / 5.0
			var dy: float = float(y - 18) / 7.0
			if dx * dx + dy * dy > 0.98:
				continue
			var lx: float = float(x - 9)
			var ly: float = float(y - 17)
			var core: float = sqrt(lx * lx + ly * ly)
			var tone: Color = warm_outer
			if core < 2.0:
				tone = warm_core
			elif core < 3.4:
				tone = warm_mid
			if float(x - y) < -10.0:
				tone = pal.mat(PixelCanvas.MAT_CLAY, 2)
			pc.put(body, x, y, tone)

	pc.put(body, 8, 20, pal.mat(PixelCanvas.MAT_CLAY, 0))
	pc.put(body, 8, 19, warm_core)
	pc.put(body, 9, 19, pal.color(PixelCanvas.CLOTH_MID))

	pc.fill_rect(body, Rect2i(5, 25, 7, 2), iron)
	pc.hline(body, 5, 11, 25, iron_l)
	pc.fill_rect(body, Rect2i(4, 27, 9, 3), iron_d)
	pc.hline(body, 4, 12, 27, iron)
	pc.hline(body, 3, 13, 30, iron_d)
	pc.hline(body, 4, 12, 29, iron)
	pc.put(body, 7, 31, iron)
	pc.put(body, 8, 31, iron_d)

	var mask: PackedByteArray = _alpha_mask(body)
	_rim(body, mask, iron_l, ink)

	if glow >= 0:
		var reach: float = 11.5 if glow == 1 else 8.0
		var ratio: float = 0.7 if glow == 1 else 0.22
		for y: int in CANVAS_H:
			for x: int in CANVAS_W:
				var hx: float = float(x - 8)
				var hy: float = float(y - 18)
				var dist: float = sqrt(hx * hx + hy * hy)
				if dist > reach or dist < 4.6:
					continue
				var falloff: float = 1.0 - (dist - 4.6) / maxf(1.0, reach - 4.6)
				if pc.bayer4(x, y) < ratio * falloff:
					pc.put(img, x, y, warm_mid if glow == 1 else warm_outer)
	_stamp(img, body, 0, 0)
	if glow >= 0:
		pc.put(img, 8, 19, warm_core)
