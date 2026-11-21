class_name PostcardArtGen
extends RefCounted
## Procedural 160x104 gouache-pixel keepsake postcards.
##
## One deterministic illustration per level id: a dithered golden-hour sky, the
## act's district skyline silhouette, a foreground neighbour enjoying the solved
## light, and a stamped brass sun wax seal. Broad colour regions with ordered
## dithering only in the sky gradient; alpha is fully opaque, every colour comes
## from the act's warm ramp (24 ramps + 23 exact midpoints = 47 colours max).

const W: int = 160
const H: int = 104
const HORIZON: int = 63
const GROUND_TOP: int = 92

static var _cache: Dictionary = {}


## Cached postcard texture. Deterministic per `level_id` (act/who only refine it).
static func build(level_id: String, act: int, who: String) -> Texture2D:
	var key: String = "%s|%d|%s" % [level_id, clampi(act, 1, 4), who]
	var cached: Variant = _cache.get(key)
	if cached != null:
		return cached as Texture2D
	var tex: Texture2D = ImageTexture.create_from_image(render(level_id, act, who))
	_cache[key] = tex
	return tex


## Renders the postcard into a fresh opaque RGBA image.
static func render(level_id: String, act: int, who: String) -> Image:
	var a: int = clampi(act, 1, 4)
	var pal: PixelCanvas.Palette = _warm_palette(a)
	var seed_value: int = PixelCanvas.seeded_from(level_id)
	var pc := PixelCanvas.new()
	var img: Image = Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(pal.mat(PixelCanvas.MAT_CLAY, 3))
	_draw_sky(pc, img, pal, a, seed_value)
	_draw_skyline(pc, img, pal, a, seed_value)
	_draw_foreground(pc, img, pal, seed_value)
	_draw_figure(pc, img, pal, who, seed_value)
	_draw_seal(pc, img, pal, seed_value)
	_draw_border(pc, img, pal)
	return img


static func _warm_palette(act: int) -> PixelCanvas.Palette:
	var source: PixelCanvas.Palette = PixelCanvas.load_palette(act - 1)
	var warmth: float = clampf(0.98 - float(act - 1) * 0.07, 0.0, 1.0)
	var warm := PixelCanvas.Palette.new()
	warm.district = source.district
	warm.display_name = source.display_name
	warm.act = act
	warm.base = source.ramp(warmth)
	warm.twilight = warm.base
	warm.golden = warm.base
	return warm


# --- SKY ---------------------------------------------------------------------

static func _draw_sky(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette, act: int, seed_value: int) -> void:
	var top: Color = pal.mat(PixelCanvas.MAT_WATER, 0) if act >= 3 else pal.mat(PixelCanvas.MAT_STONE, 0)
	var stops := PackedColorArray([
		top,
		pal.mat(PixelCanvas.MAT_STONE, 1),
		pal.mat(PixelCanvas.MAT_CLAY, 3),
		pal.mat(PixelCanvas.MAT_CLAY, 4),
		pal.mat(PixelCanvas.MAT_METAL, 4),
	])
	pc.dither_gradient(img, stops[0], stops[4], Rect2i(0, 0, W, HORIZON + 1), seed_value, stops)

	# Three wide gouache cloud bars, dithered only where they meet the sky.
	for i in 3:
		var y: int = 10 + i * 11 + (seed_value >> (i + 2)) % 5
		var x0: int = 8 + (seed_value >> (i + 5)) % 34
		var length: int = 44 + (seed_value >> (i + 8)) % 46
		pc.dither_fill(img, Rect2i(x0, y, length, 2), pal.mat(PixelCanvas.MAT_CLAY, 4),
			pal.mat(PixelCanvas.MAT_CLAY, 3), seed_value + i * 17, 0.4)

	# Sun disc with a dithered halo, sunward of the district.
	var sun_x: int = 104 + (seed_value >> 3) % 40
	var sun_y: int = 20 + (seed_value >> 9) % 16
	var radius: int = 8 + (seed_value >> 13) % 4
	for y in range(sun_y - radius - 9, sun_y + radius + 10):
		for x in range(sun_x - radius - 9, sun_x + radius + 10):
			var dx: float = float(x - sun_x)
			var dy: float = float(y - sun_y)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= float(radius):
				continue
			if dist > float(radius + 9):
				continue
			var falloff: float = 1.0 - (dist - float(radius)) / 9.0
			if pc.bayer4(x, y) < 0.55 * falloff:
				pc.put(img, x, y, pal.mat(PixelCanvas.MAT_METAL, 4))
	pc.disc(img, sun_x, sun_y, radius, pal.mat(PixelCanvas.MAT_METAL, 4))
	pc.disc(img, sun_x - 1, sun_y - 1, radius - 2, pal.color(PixelCanvas.CLOTH_LIGHT))

	# Warm haze band hugging the horizon.
	pc.dither_fill(img, Rect2i(0, HORIZON - 7, W, 8), pal.mat(PixelCanvas.MAT_CLAY, 4),
		pal.mat(PixelCanvas.MAT_METAL, 4), seed_value + 3, 0.35)


# --- SKYLINE -----------------------------------------------------------------

static func _draw_skyline(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette, act: int, seed_value: int) -> void:
	# A postcard skyline is a silhouette, not a lit facade: it has to sit well
	# under the horizon glow or the whole card reads flat.
	var ridge: Color = pal.shade(pal.mat(PixelCanvas.MAT_STONE, 1), 0.62)
	var ridge_d: Color = pal.shade(pal.mat(PixelCanvas.MAT_STONE, 0), 0.55)
	var warm: Color = pal.mat(PixelCanvas.MAT_METAL, 3)
	match act:
		1:
			_skyline_steps(pc, img, pal, ridge, ridge_d, warm, seed_value)
		2:
			_skyline_verandas(pc, img, pal, ridge, ridge_d, warm, seed_value)
		3:
			_skyline_canals(pc, img, pal, ridge, ridge_d, warm, seed_value)
		_:
			_skyline_harbour(pc, img, pal, ridge, ridge_d, warm, seed_value)


## Act I: terraced limestone steps and stair flights.
static func _skyline_steps(pc: PixelCanvas, img: Image, _pal: PixelCanvas.Palette,
		ridge: Color, ridge_d: Color, warm: Color, seed_value: int) -> void:
	var jitter: int = (seed_value >> 4) % 5
	# Terrace blocks, not towers: each mass steps back as it rises, which is what
	# separates a limestone hillside from a skyline of office slabs.
	var masses := [
		Vector3i(2, 68, 30), Vector3i(24, 56, 22), Vector3i(40, 62, 24),
		Vector3i(58, 48, 26), Vector3i(82, 58, 30),
	]
	for mass_index: int in masses.size():
		var mass: Vector3i = masses[mass_index]
		var x: int = mass.x + jitter
		var top: int = mass.y + (seed_value >> (mass_index + 6)) % 5
		var tiers: int = 2 + ((seed_value >> mass_index) & 1)
		for tier: int in tiers:
			var inset: int = tier * 3
			var tw: int = mass.z - inset * 2
			if tw < 5:
				break
			var tier_top: int = top - tier * (7 + (seed_value >> (tier + 3)) % 4)
			pc.fill_rect(img, Rect2i(x + inset, tier_top, tw, 86 - tier_top), ridge)
			pc.hline(img, x + inset, x + inset + tw - 1, tier_top, warm)
			pc.vline(img, x + inset + tw - 1, tier_top, 85, ridge_d)
			pc.vline(img, x + inset, tier_top, 85, ridge)
		# Windows lit by the same low sun as everything else, and only a few of
		# them: a grid of windows is what made this read as a city block.
		var window_row: int = 0
		for wy: int in range(top + 4, 82, 9):
			window_row += 1
			for wx: int in range(x + 3, x + mass.z - 4, 6):
				if ((wx * 7 + wy * 13 + seed_value) % 5) > 1:
					continue
				pc.fill_rect(img, Rect2i(wx, wy, 2, 3), warm)
	# Stair flight descending to the right.
	for step in 7:
		var sx: int = 104 + step * 5
		var sy: int = 48 + step * 5
		pc.fill_rect(img, Rect2i(sx, sy, 5, 86 - sy), ridge)
		pc.hline(img, sx, sx + 4, sy, warm)
	# A low dome caps the tallest terrace.
	pc.ellipse(img, 132, 58, 12, 9, ridge)
	pc.hline(img, 122, 142, 49, warm)
	pc.vline(img, 120, 58, 85, ridge_d)


## Act II: pitched veranda roofs with eaves, columns and balusters.
static func _skyline_verandas(pc: PixelCanvas, img: Image, _pal: PixelCanvas.Palette,
		ridge: Color, ridge_d: Color, warm: Color, seed_value: int) -> void:
	var houses := [Vector2i(4, 30), Vector2i(38, 34), Vector2i(76, 28), Vector2i(110, 40)]
	for i in houses.size():
		var origin: Vector2i = houses[i]
		var cx: int = origin.x + origin.y / 2 + (seed_value >> (i + 2)) % 4
		var half: int = origin.y / 2
		var base_y: int = 54 + (seed_value >> (i + 5)) % 15
		# Body, then the gable drawn row by row.
		pc.fill_rect(img, Rect2i(cx - half + 2, base_y, half * 2 - 4, 88 - base_y), ridge)
		for row in 14:
			var inset: int = row / 2
			var y: int = base_y - 1 - row
			pc.hline(img, cx - half + inset, cx + half - inset, y, ridge)
			pc.put(img, cx + half - inset, y, ridge_d)
		pc.hline(img, cx - half, cx + half, base_y - 15, warm)
		pc.hline(img, cx - half, cx + half, base_y, warm)
		# Veranda columns and balusters.
		for c in 3:
			var vx: int = cx - half + 3 + c * (half - 3)
			pc.vline(img, vx, base_y + 1, 87, ridge_d)
		for b in range(cx - half + 3, cx + half - 2, 3):
			pc.put(img, b, 84, ridge_d)
		pc.hline(img, cx - half + 2, cx + half - 3, 84, ridge_d)
		# Chimney silhouette.
		if i == 1:
			pc.fill_rect(img, Rect2i(cx + half - 6, base_y - 24, 3, 8), ridge_d)
			pc.put(img, cx + half - 6, base_y - 25, ridge_d)


## Act III: canal bridges arching over a lit water band.
static func _skyline_canals(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette,
		ridge: Color, ridge_d: Color, warm: Color, seed_value: int) -> void:
	var water_y: int = 79
	# Canal water under an amber sky goes slate, not emerald: keep the hue the
	# district uses but pull it down towards the shadows it is reflecting.
	var canal: Color = pal.shade(pal.mat(PixelCanvas.MAT_WATER, 2), 0.28)
	pc.fill_rect(img, Rect2i(0, water_y, W, H - water_y), canal)
	for row in range(water_y + 2, H, 4):
		var offset: int = (row / 4) % 9
		for x in range(offset, W, 13):
			pc.hline(img, x, x + 4, row, pal.mat(PixelCanvas.MAT_WATER, 3))
	# Low canal houses on both banks.
	pc.fill_rect(img, Rect2i(0, 58, 44, water_y - 58 + 4), ridge)
	pc.fill_rect(img, Rect2i(112, 54, 48, water_y - 54 + 4), ridge)
	pc.hline(img, 0, 43, 58, warm)
	pc.hline(img, 112, 159, 54, warm)
	for x in range(4, 40, 8):
		pc.fill_rect(img, Rect2i(x, 64, 3, 4), warm)
	for x in range(118, 156, 8):
		pc.fill_rect(img, Rect2i(x, 60, 3, 4), warm)
	# Two arched bridges; the opening lets the water band read through.
	_arch_bridge(pc, img, 50, 8, 61, ridge, ridge_d, warm)
	_arch_bridge(pc, img, 92, 6, 65, ridge_d, ridge_d, warm)
	for row in range(water_y + 3, H, 5):
		for x in range(44, 100, 7):
			pc.put(img, x + (row % 3), row, pal.mat(PixelCanvas.MAT_WATER, 3))


static func _arch_bridge(pc: PixelCanvas, img: Image, cx: int, deck_y: int, radius: int,
		body: Color, shade: Color, warm: Color) -> void:
	var water: int = 84
	for x in range(cx - radius, cx + radius + 1):
		var dx: float = float(x - cx)
		var arch_top: float = float(water) - sqrt(maxf(0.0, float(radius * radius) - dx * dx)) * 0.85
		pc.fill_rect(img, Rect2i(x, deck_y + 5, 1, maxi(0, int(arch_top) - deck_y - 5)), body)
		pc.put(img, x, int(arch_top) - 1, shade)
	pc.hline(img, cx - radius, cx + radius, deck_y, warm)
	pc.hline(img, cx - radius, cx + radius, deck_y + 4, shade)
	# Balustrade posts along the deck.
	for x in range(cx - radius + 2, cx + radius, 5):
		pc.vline(img, x, deck_y - 3, deck_y - 1, shade)


## Act IV: harbour cranes and a striped lighthouse.
static func _skyline_harbour(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette,
		ridge: Color, ridge_d: Color, warm: Color, seed_value: int) -> void:
	var water_y: int = 80
	pc.fill_rect(img, Rect2i(0, water_y, W, H - water_y), pal.mat(PixelCanvas.MAT_WATER, 2))
	for row in range(water_y + 2, H, 3):
		for x in range((row * 3) % 11, W, 15):
			pc.hline(img, x, x + 5, row, pal.mat(PixelCanvas.MAT_WATER, 3))
	# Low quay wall and warehouses.
	pc.fill_rect(img, Rect2i(0, 68, W, water_y - 68 + 2), ridge_d)
	pc.hline(img, 0, W - 1, 68, warm)
	for x in range(6, 92, 12):
		pc.fill_rect(img, Rect2i(x, 58, 8, 11), ridge)
		pc.hline(img, x, x + 7, 58, warm)
	# Three cranes: mast, jib and hook cable.
	for i in 3:
		var mx: int = 18 + i * 30 + (seed_value >> (i + 3)) % 5
		var mast_top: int = 24 + i * 4
		pc.vline(img, mx, mast_top, 67, ridge_d)
		pc.vline(img, mx + 1, mast_top, 67, ridge)
		for j in 10:
			pc.put(img, mx - j, mast_top + 4 + j / 2, ridge)
		pc.hline(img, mx - 12, mx + 8, mast_top + 4, ridge)
		pc.vline(img, mx + 8, mast_top + 5, mast_top + 12, ridge)
		pc.fill_rect(img, Rect2i(mx + 7, mast_top + 13, 3, 2), ridge_d)
		pc.vline(img, mx + 9, mast_top + 5, mast_top + 11, warm)
	# Lighthouse with a lit lamp room.
	var lx: int = 104
	for row in 24:
		var inset: int = row / 6
		pc.hline(img, lx - 5 + inset, lx + 5 - inset, 66 - row, ridge)
	pc.fill_rect(img, Rect2i(lx - 6, 66, 13, 4), ridge_d)
	for band in 3:
		pc.hline(img, lx - 4 + band, lx + 4 - band, 40 + band * 5, ridge_d)
	pc.fill_rect(img, Rect2i(lx - 4, 34, 9, 5), ridge_d)
	pc.disc(img, lx, 36, 3, pal.color(PixelCanvas.CLOTH_LIGHT))
	for k in 9:
		var ly: int = 32 + k
		pc.hline(img, lx - 10 - k, lx - 5, ly, warm)
		pc.hline(img, lx + 5, lx + 10 + k, ly, warm)
	pc.fill_rect(img, Rect2i(lx - 2, 28, 5, 5), ridge_d)
	pc.put(img, lx, 28, ridge)


# --- FOREGROUND --------------------------------------------------------------

static func _draw_foreground(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette, seed_value: int) -> void:
	var fg: Color = pal.mat(PixelCanvas.MAT_STONE, 0)
	var fg_l: Color = pal.mat(PixelCanvas.MAT_STONE, 1)
	pc.fill_rect(img, Rect2i(0, GROUND_TOP, W, H - GROUND_TOP), fg)
	pc.hline(img, 0, W - 1, GROUND_TOP, fg_l)
	# Dappled sun pools on the paving, ordered dither rather than speckle.
	for i in 3:
		var px: int = 12 + i * 48 + (seed_value >> (i + 4)) % 14
		pc.dither_fill(img, Rect2i(px, GROUND_TOP + 5 + i % 2, 30, 4),
			pal.mat(PixelCanvas.MAT_METAL, 3), fg, seed_value + i * 29, 0.3)
	# A few paving joints, never a grid.
	for x in range(4, W, 17):
		pc.vline(img, x + (seed_value >> (x % 5)) % 5, GROUND_TOP + 3, GROUND_TOP + 8, pal.mat(PixelCanvas.MAT_STONE, 1))


static func _draw_figure(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette, who: String, seed_value: int) -> void:
	var key: String = who.strip_edges().to_lower()
	var base_x: int = 46 + (seed_value >> 7) % 34
	var base_y: int = GROUND_TOP + 9
	var rim: Color = pal.mat(PixelCanvas.MAT_CLAY, 4)
	var body: Color = pal.darkest()
	# Offset silhouette: the shifted warm layer leaves a 1px sunlit rim on the
	# top-right of the figure, matching every other asset in the game.
	for pass_index in 2:
		var offset := Vector2i(1, -1) if pass_index == 0 else Vector2i.ZERO
		var colour: Color = rim if pass_index == 0 else body
		_figure_shape(pc, img, key, base_x + offset.x, base_y + offset.y, colour)
	# Warm pool of light at their feet.
	pc.dither_fill(img, Rect2i(base_x - 10, base_y, 22, 3), pal.mat(PixelCanvas.MAT_METAL, 3),
		pal.mat(PixelCanvas.MAT_STONE, 0), seed_value + 41, 0.4)


static func _figure_shape(pc: PixelCanvas, img: Image, who: String, x: int, y: int, c: Color) -> void:
	match who:
		"cat":
			pc.ellipse(img, x, y - 6, 9, 6, c)
			pc.disc(img, x + 5, y - 12, 4, c)
			pc.put(img, x + 3, y - 16, c)
			pc.put(img, x + 4, y - 16, c)
			pc.put(img, x + 6, y - 16, c)
			pc.put(img, x + 7, y - 16, c)
			pc.vline(img, x - 8, y - 7, y - 2, c)
			pc.put(img, x - 9, y - 2, c)
			pc.put(img, x - 10, y - 4, c)
		"baker":
			_standing(pc, img, x, y, c, 12)
			pc.disc(img, x, y - 22, 3, c)
			pc.fill_rect(img, Rect2i(x - 3, y - 26, 7, 2), c)
			pc.hline(img, x + 2, x + 10, y - 15, c)
			pc.fill_rect(img, Rect2i(x + 7, y - 18, 6, 3), c)
		"nurse":
			_standing(pc, img, x, y, c, 11)
			pc.disc(img, x, y - 21, 3, c)
			pc.fill_rect(img, Rect2i(x - 3, y - 25, 7, 2), c)
			pc.vline(img, x - 6, y - 15, y - 5, c)
			pc.fill_rect(img, Rect2i(x - 9, y - 12, 4, 5), c)
		"guitarist":
			_standing(pc, img, x, y, c, 11)
			pc.disc(img, x, y - 21, 3, c)
			pc.ellipse(img, x + 2, y - 8, 6, 4, c)
			pc.vline(img, x + 6, y - 11, y - 17, c)
			pc.put(img, x + 7, y - 18, c)
		"commuter":
			_standing(pc, img, x, y, c, 12)
			pc.disc(img, x, y - 22, 3, c)
			pc.fill_rect(img, Rect2i(x - 4, y - 25, 8, 2), c)
			pc.fill_rect(img, Rect2i(x + 4, y - 14, 4, 5), c)
			pc.put(img, x + 8, y - 13, c)
		"hibiscus":
			pc.fill_rect(img, Rect2i(x - 5, y - 7, 11, 7), c)
			pc.hline(img, x - 6, x + 6, y - 7, c)
			pc.vline(img, x, y - 19, y - 8, c)
			pc.ellipse(img, x - 4, y - 13, 4, 2, c)
			pc.ellipse(img, x + 4, y - 16, 4, 2, c)
			pc.disc(img, x, y - 21, 4, c)
			pc.put(img, x, y - 18, c)
		_:
			_standing(pc, img, x, y, c, 12)
			pc.disc(img, x, y - 22, 3, c)
			pc.fill_rect(img, Rect2i(x - 4, y - 25, 8, 2), c)


static func _standing(pc: PixelCanvas, img: Image, x: int, y: int, c: Color, height: int) -> void:
	pc.vline(img, x - 2, y - 10, y, c)
	pc.vline(img, x + 2, y - 10, y, c)
	pc.fill_rect(img, Rect2i(x - 5, y - height - 10, 11, height - 1), c)
	pc.vline(img, x - 6, y - height - 8, y - 11, c)
	pc.vline(img, x + 6, y - height - 8, y - 11, c)


# --- SEAL & BORDER -----------------------------------------------------------

static func _draw_seal(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette, seed_value: int) -> void:
	var cx: int = 136 if (seed_value & 1) == 0 else 22
	var cy: int = 82
	var brass_d: Color = pal.mat(PixelCanvas.MAT_METAL, 1)
	var brass: Color = pal.mat(PixelCanvas.MAT_METAL, 3)
	var brass_l: Color = pal.mat(PixelCanvas.MAT_METAL, 4)
	var ink: Color = pal.mat(PixelCanvas.MAT_METAL, 0)
	for y in range(cy - 14, cy + 15):
		for x in range(cx - 14, cx + 15):
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			var dist: float = sqrt(dx * dx + dy * dy)
			var angle: float = atan2(dy, dx)
			var wobble: float = 1.0 + 0.09 * sin(angle * 8.0 + float(seed_value % 32) * 0.2)
			if dist > 12.5 * wobble:
				continue
			if dist > 10.6 * wobble:
				pc.put(img, x, y, brass_l if float(x - y) > float(cx - cy) else ink)
			elif dist > 9.4:
				pc.put(img, x, y, brass_d)
			elif dist > 8.6:
				pc.put(img, x, y, brass_l if float(x - y) > float(cx - cy) else brass)
			else:
				pc.put(img, x, y, brass)
	# Sun face: eight rays around a stamped core.
	for ray in 8:
		var angle: float = float(ray) * TAU / 8.0 + 0.2
		for step in 5:
			var r: float = 3.0 + float(step)
			var rx: int = cx + roundi(cos(angle) * r)
			var ry: int = cy + roundi(sin(angle) * r)
			pc.put(img, rx, ry, brass_l if step > 2 else brass_d)
	pc.disc(img, cx, cy, 3, brass_l)
	pc.put(img, cx - 1, cy - 1, pal.color(PixelCanvas.CLOTH_LIGHT))
	pc.put(img, cx + 1, cy + 1, brass_d)


static func _draw_border(pc: PixelCanvas, img: Image, pal: PixelCanvas.Palette) -> void:
	var cream: Color = pal.color(PixelCanvas.CLOTH_LIGHT)
	var edge: Color = pal.mat(PixelCanvas.MAT_CLAY, 2)
	pc.rect_outline(img, Rect2i(0, 0, W, H), cream)
	pc.rect_outline(img, Rect2i(2, 2, W - 4, H - 4), edge)
	pc.rect_outline(img, Rect2i(3, 3, W - 6, H - 6), cream)
