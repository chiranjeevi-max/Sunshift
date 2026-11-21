class_name PixelCanvas
extends RefCounted
## Pure, node-free pixel-art primitives shared by every generator in `src/art/`.
##
## Every pixel Sunshift ever draws is produced through these helpers from the
## curated ramps in `data/palettes.json`. Nothing here uses `RandomNumberGenerator`,
## `Time` or dictionary iteration: the same arguments always produce the same bytes.

const PALETTE_PATH: String = "res://data/palettes.json"

# Eight material triads per district. Index = material * 3 + (0 dark, 1 mid, 2 light).
const MAT_STONE: int = 0
const MAT_CLAY: int = 1
const MAT_WOOD: int = 2
const MAT_WATER: int = 3
const MAT_MOSS: int = 4
const MAT_METAL: int = 5
const MAT_CLOTH: int = 6
const MAT_SKIN: int = 7
const MATERIAL_COUNT: int = 8

const STONE_DARK: int = 0
const STONE_MID: int = 1
const STONE_LIGHT: int = 2
const CLAY_DARK: int = 3
const CLAY_MID: int = 4
const CLAY_LIGHT: int = 5
const WOOD_DARK: int = 6
const WOOD_MID: int = 7
const WOOD_LIGHT: int = 8
const WATER_DARK: int = 9
const WATER_MID: int = 10
const WATER_LIGHT: int = 11
const MOSS_DARK: int = 12
const MOSS_MID: int = 13
const MOSS_LIGHT: int = 14
const METAL_DARK: int = 15
const METAL_MID: int = 16
const METAL_LIGHT: int = 17
const CLOTH_DARK: int = 18
const CLOTH_MID: int = 19
const CLOTH_LIGHT: int = 20
const SKIN_DARK: int = 21
const SKIN_MID: int = 22
const SKIN_LIGHT: int = 23

const ROLE_NAMES: Array[String] = [
	"stone_dark", "stone_mid", "stone_light",
	"clay_dark", "clay_mid", "clay_light",
	"wood_dark", "wood_mid", "wood_light",
	"water_dark", "water_mid", "water_light",
	"moss_dark", "moss_mid", "moss_light",
	"metal_dark", "metal_mid", "metal_light",
	"cloth_dark", "cloth_mid", "cloth_light",
	"skin_dark", "skin_mid", "skin_light",
]

# 4x4 Bayer matrix, row-major, values 0..15.
const BAYER4: Array[int] = [
	0, 8, 2, 10,
	12, 4, 14, 6,
	3, 11, 1, 9,
	15, 7, 13, 5,
]

static var _palette_doc: Dictionary = {}
static var _palette_cache: Dictionary = {}


## A district's curated 24-colour ramp set, plus its twilight/golden lerp targets.
class Palette:
	var district: int = 0
	var display_name: String = ""
	var act: int = 1
	var base: PackedColorArray = PackedColorArray()
	var twilight: PackedColorArray = PackedColorArray()
	var golden: PackedColorArray = PackedColorArray()

	func color(role: int) -> Color:
		if base.is_empty():
			return Color.MAGENTA
		return base[clampi(role, 0, base.size() - 1)]

	func named(role_name: String) -> Color:
		var index: int = ROLE_NAMES.find(role_name)
		return color(index)

	## Five-step material ramp: 0 dark, 1 dark/mid, 2 mid, 3 mid/light, 4 light.
	## Levels 1 and 3 are exact midpoints of adjacent palette entries.
	func mat(material: int, level: int) -> Color:
		var start: int = clampi(material, 0, MATERIAL_COUNT - 1) * 3
		var dark: Color = color(start)
		var mid_tone: Color = color(start + 1)
		var light: Color = color(start + 2)
		match clampi(level, 0, 4):
			0:
				return dark
			1:
				return dark.lerp(mid_tone, 0.5)
			2:
				return mid_tone
			3:
				return mid_tone.lerp(light, 0.5)
			_:
				return light

	func ramp5(material: int) -> PackedColorArray:
		var out := PackedColorArray()
		for level in 5:
			out.append(mat(material, level))
		return out

	## Exact midpoint of two adjacent palette entries — the only sanctioned blend.
	func mid(role_a: int, role_b: int) -> Color:
		var a: int = clampi(role_a, 0, 23)
		var b: int = clampi(role_b, 0, 23)
		if absi(a - b) != 1:
			return color(a)
		return color(mini(a, b)).lerp(color(maxi(a, b)), 0.5)

	## Darkest palette entry — the ink colour. Indigo-leaning, never pure black.
	func darkest() -> Color:
		var best: Color = color(0)
		var best_lum: float = 10.0
		for entry: Color in base:
			var lum: float = entry.r * 0.299 + entry.g * 0.587 + entry.b * 0.114
			if lum < best_lum:
				best_lum = lum
				best = entry
		return best

	## Lightest palette entry — warm, never pure white.
	func lightest() -> Color:
		var best: Color = color(0)
		var best_lum: float = -1.0
		for entry: Color in base:
			var lum: float = entry.r * 0.299 + entry.g * 0.587 + entry.b * 0.114
			if lum > best_lum:
				best_lum = lum
				best = entry
		return best

	## Lighten toward the palette's warmest entry.
	func tint(source: Color, amount: float) -> Color:
		return source.lerp(lightest(), clampf(amount, 0.0, 1.0))

	## Darken toward the palette's ink colour.
	func shade(source: Color, amount: float) -> Color:
		return source.lerp(darkest(), clampf(amount, 0.0, 1.0))

	## Free two-colour blend, for gradients rather than shading ramps.
	func mix(a: Color, b: Color, t: float) -> Color:
		return a.lerp(b, clampf(t, 0.0, 1.0))

	## Push toward honey-amber — the colour of a sunlit face at golden hour.
	func warm(source: Color, amount: float) -> Color:
		var t: float = clampf(amount, 0.0, 1.0)
		return source.lerp(Color(1.0, 0.82, 0.50, source.a), t * 0.35)

	## The complete legal colour set: 24 entries + 23 exact adjacent midpoints.
	func allowed_colors() -> PackedColorArray:
		var out := PackedColorArray()
		out.append_array(base)
		for i in base.size() - 1:
			out.append(base[i].lerp(base[i + 1], 0.5))
		return out

	## 24 colours for a given warmth: 0 = twilight, 0.5 = base, 1 = golden.
	func ramp(warmth: float) -> PackedColorArray:
		var out := PackedColorArray()
		out.resize(base.size())
		var w: float = clampf(warmth, 0.0, 1.0)
		for i in base.size():
			if w < 0.5:
				out[i] = twilight[i].lerp(base[i], w * 2.0)
			else:
				out[i] = base[i].lerp(golden[i], (w - 0.5) * 2.0)
		return out


static func _load_document() -> Dictionary:
	if not _palette_doc.is_empty():
		return _palette_doc
	var file := FileAccess.open(PALETTE_PATH, FileAccess.READ)
	if file == null:
		push_error("PixelCanvas: cannot open %s" % PALETTE_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("PixelCanvas: %s is not a JSON object" % PALETTE_PATH)
		return {}
	var doc: Dictionary = parsed
	_palette_doc = doc
	return _palette_doc


static func district_count() -> int:
	var districts: Array = _load_document().get("districts", []) as Array
	return districts.size()


static func district_names() -> PackedStringArray:
	var out := PackedStringArray()
	var districts: Array = _load_document().get("districts", []) as Array
	for entry: Variant in districts:
		var d: Dictionary = entry
		out.append(String(d.get("name", "District")))
	return out


## Loads (and caches) a district palette. `district` is clamped to a valid id.
static func load_palette(district: int) -> Palette:
	var districts: Array = _load_document().get("districts", []) as Array
	if districts.is_empty():
		var fallback := Palette.new()
		fallback.base = _emergency_ramp()
		fallback.twilight = fallback.base
		fallback.golden = fallback.base
		return fallback
	var index: int = clampi(district, 0, districts.size() - 1)
	var cached: Variant = _palette_cache.get(index)
	if cached != null:
		return cached as Palette
	var entry: Dictionary = districts[index]
	var palette := Palette.new()
	palette.district = int(entry.get("id", index))
	palette.display_name = String(entry.get("name", "District %d" % index))
	palette.act = int(entry.get("act", index + 1))
	palette.base = _colour_array(entry.get("colors", []))
	palette.twilight = _colour_array(entry.get("twilight", entry.get("colors", [])))
	palette.golden = _colour_array(entry.get("golden", entry.get("colors", [])))
	if palette.twilight.size() != palette.base.size():
		palette.twilight = palette.base.duplicate()
	if palette.golden.size() != palette.base.size():
		palette.golden = palette.base.duplicate()
	_palette_cache[index] = palette
	return palette


static func _colour_array(raw: Variant) -> PackedColorArray:
	var out := PackedColorArray()
	if typeof(raw) != TYPE_ARRAY:
		return out
	var list: Array = raw
	for value: Variant in list:
		out.append(Color(String(value)))
	return out


static func _emergency_ramp() -> PackedColorArray:
	# Should never ship, but keeps the art pipeline alive if the JSON is missing.
	var out := PackedColorArray()
	for i in 24:
		var value: float = 0.12 + float(i % 3) * 0.28
		out.append(Color(value, value * 0.92, value * 1.06))
	return out


## Stable, process-independent hash so one level id always yields one artwork.
static func seeded_from(text: String) -> int:
	var h: int = 5381
	for i in text.length():
		h = ((h << 5) + h) ^ text.unicode_at(i)
	return h & 0x7FFFFFFFFFFFFFFF


## Deterministic value noise in [0, 1]. Used for grain, plaster and sky fields.
func noise_at(x: int, y: int, seed: int) -> float:
	return fbm(float(x), float(y), seed, 1, 1.0)


## Fractal value noise in [0, 1]. `scale` is cells per sample unit.
func fbm(x: float, y: float, seed: int, octaves: int = 3, scale: float = 8.0) -> float:
	var total: float = 0.0
	var amplitude: float = 0.5
	var frequency: float = 1.0
	var norm: float = 0.0
	for octave in maxi(1, octaves):
		total += _value_noise(x * scale * frequency, y * scale * frequency, seed + octave * 101) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.0
	if norm <= 0.0:
		return 0.0
	return clampf(total / norm, 0.0, 1.0)


## Uninterpolated white noise in [0, 1] — crisp pixel grain rather than blur.
func grain(x: int, y: int, seed: int) -> float:
	return _unit(_hash2(x, y, seed))


## 4x4 ordered dither threshold in [0, 1).
func bayer4(x: int, y: int) -> float:
	var ix: int = posmod(x, 4)
	var iy: int = posmod(y, 4)
	return (float(BAYER4[iy * 4 + ix]) + 0.5) / 16.0


## Ordered-dither vertical gradient over `rect`. Pass a ramp of palette colours
## (e.g. `Palette.ramp5()`) to stay strictly on-palette. With no ramp it dithers
## between `from` and `to` only — never a blended third colour.
func dither_gradient(img: Image, from: Color, to: Color, rect: Rect2i, seed: int, ramp: PackedColorArray = PackedColorArray()) -> void:
	var stops: PackedColorArray = ramp
	if stops.is_empty():
		stops = PackedColorArray([from, to])
	var height: int = maxi(1, rect.size.y - 1)
	for y in range(rect.position.y, rect.end.y):
		var t: float = float(y - rect.position.y) / float(height)
		for x in range(rect.position.x, rect.end.x):
			var jitter: float = (bayer4(x + seed, y) - 0.5) * 0.55
			var shifted: float = clampf(t + jitter / float(maxi(2, rect.size.y)), 0.0, 1.0)
			var index: int = clampi(roundi(shifted * float(stops.size() - 1)), 0, stops.size() - 1)
			put(img, x, y, stops[index])


## Writes one fully opaque pixel when inside bounds. Alpha is always binary.
func put(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))


func fill_rect(img: Image, rect: Rect2i, c: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			put(img, x, y, c)


func hline(img: Image, x0: int, x1: int, y: int, c: Color) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		put(img, x, y, c)


func vline(img: Image, x: int, y0: int, y1: int, c: Color) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		put(img, x, y, c)


func rect_outline(img: Image, rect: Rect2i, c: Color) -> void:
	hline(img, rect.position.x, rect.end.x - 1, rect.position.y, c)
	hline(img, rect.position.x, rect.end.x - 1, rect.end.y - 1, c)
	vline(img, rect.position.x, rect.position.y, rect.end.y - 1, c)
	vline(img, rect.end.x - 1, rect.position.y, rect.end.y - 1, c)


func disc(img: Image, cx: int, cy: int, radius: int, c: Color) -> void:
	ellipse(img, cx, cy, radius, radius, c)


func ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	if rx < 0 or ry < 0:
		return
	var rx_f: float = float(maxi(1, rx))
	var ry_f: float = float(maxi(1, ry))
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var dx: float = float(x - cx) / rx_f
			var dy: float = float(y - cy) / ry_f
			if dx * dx + dy * dy <= 1.02:
				put(img, x, y, c)


func ellipse_outline(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	var rx_f: float = float(maxi(1, rx))
	var ry_f: float = float(maxi(1, ry))
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var dx: float = float(x - cx) / rx_f
			var dy: float = float(y - cy) / ry_f
			var outer: bool = dx * dx + dy * dy <= 1.04
			var inner: bool = dx * dx + dy * dy < 0.62
			if outer and not inner:
				put(img, x, y, c)


## Fills `rect` with `a` where the Bayer threshold is below `ratio`, else `b`.
func dither_fill(img: Image, rect: Rect2i, a: Color, b: Color, seed: int, ratio: float = 0.5) -> void:
	var cut: float = clampf(ratio, 0.0, 1.0)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			put(img, x, y, a if bayer4(x + seed, y + seed) < cut else b)


## 1px top/left highlight and bottom/right shade — the reading cue that keeps a
## flat 16x16 grid legible as 3/4 architecture.
func bevel_rect(img: Image, rect: Rect2i, light: Color, dark: Color) -> void:
	if rect.size.x < 2 or rect.size.y < 2:
		return
	hline(img, rect.position.x, rect.end.x - 1, rect.position.y, light)
	vline(img, rect.position.x, rect.position.y, rect.end.y - 1, light)
	hline(img, rect.position.x, rect.end.x - 1, rect.end.y - 1, dark)
	vline(img, rect.end.x - 1, rect.position.y, rect.end.y - 1, dark)


## Adds a 1px outline outside the opaque silhouette, tinted to the local shadow
## hue (never pure black). Only orthogonal neighbours count, so the outline can
## never create a diagonally isolated orphan pixel.
func outline_sprite(img: Image, tint: Color) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				mask[y * w + x] = 1
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				continue
			var touching: bool = false
			if x > 0 and mask[y * w + x - 1] == 1:
				touching = true
			elif x < w - 1 and mask[y * w + x + 1] == 1:
				touching = true
			elif y > 0 and mask[(y - 1) * w + x] == 1:
				touching = true
			elif y < h - 1 and mask[(y + 1) * w + x] == 1:
				touching = true
			if touching:
				put(img, x, y, tint)


## Copies the opaque pixels of `src` onto `dst` at `pos`. No alpha blending.
func stamp(dst: Image, src: Image, pos: Vector2i) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var c: Color = src.get_pixel(x, y)
			if c.a <= 0.5:
				continue
			put(dst, pos.x + x, pos.y + y, c)


## Nearest-neighbour scale — keeps pixel art on the grid.
func scaled(src: Image, factor: int) -> Image:
	if factor <= 1:
		return src.duplicate() as Image
	var out: Image = src.duplicate() as Image
	out.resize(src.get_width() * factor, src.get_height() * factor, Image.INTERPOLATE_NEAREST)
	return out


func extract(img: Image, rect: Rect2i) -> Image:
	var region: Image = img.get_region(rect)
	return region


## Returns the palette entry closest to `c` (used to keep dither output on-ramp).
static func nearest_in(palette: PackedColorArray, c: Color) -> Color:
	var best: Color = c
	var best_distance: float = 1e20
	for entry: Color in palette:
		var dr: float = entry.r - c.r
		var dg: float = entry.g - c.g
		var db: float = entry.b - c.b
		var d: float = dr * dr + dg * dg + db * db
		if d < best_distance:
			best_distance = d
			best = entry
	return best


## Packs a colour into a 24-bit RGB key (alpha ignored).
static func color_key(c: Color) -> int:
	var r: int = clampi(roundi(c.r * 255.0), 0, 255)
	var g: int = clampi(roundi(c.g * 255.0), 0, 255)
	var b: int = clampi(roundi(c.b * 255.0), 0, 255)
	return (r << 16) | (g << 8) | b


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))


func _value_noise(fx: float, fy: float, seed: int) -> float:
	var x0: int = floori(fx)
	var y0: int = floori(fy)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	var sx: float = tx * tx * (3.0 - 2.0 * tx)
	var sy: float = ty * ty * (3.0 - 2.0 * ty)
	var v00: float = _unit(_hash2(x0, y0, seed))
	var v10: float = _unit(_hash2(x0 + 1, y0, seed))
	var v01: float = _unit(_hash2(x0, y0 + 1, seed))
	var v11: float = _unit(_hash2(x0 + 1, y0 + 1, seed))
	var top: float = v00 + (v10 - v00) * sx
	var bottom: float = v01 + (v11 - v01) * sx
	return top + (bottom - top) * sy


static func _hash2(x: int, y: int, seed: int) -> int:
	var h: int = x * 374761393 + y * 668265263 + seed * 1442695041
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h


static func _unit(h: int) -> float:
	return float(h & 0xFFFF) / 65535.0
