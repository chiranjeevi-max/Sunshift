class_name TilesetGenerator
extends RefCounted
## Procedural district tile atlas + runtime TileSet.
##
## Atlas layout (16x16 cells, 8 columns x 5 rows):
##   row 0..2 : the seven TileTypes at elevation 0, 1, 2 (col 7 = material variant)
##   row 3    : water animation frames 0..3 (cols 0..3), puddle frames 0..3 (cols 4..7)
##   row 4    : decorative variants (cracked cobble, wet oxide, planks, moss slab,
##              roof tiles, drain grate, gutter, planter)
##
## Tile ids mirror GridTypes.TileType exactly and are repeated here so the art
## layer compiles even before src/core/ exists.

const CELL: int = 16
const ATLAS_COLS: int = 8
const ATLAS_ROWS: int = 5

const VOID: int = 0
const FLOOR: int = 1
const WALL: int = 2
const WATER: int = 3
const PUDDLE: int = 4
const STAIRS: int = 5
const RAILING: int = 6
const TILE_TYPE_COUNT: int = 7

const WATER_ANIM_COORDS: Vector2i = Vector2i(0, 3)
const PUDDLE_ANIM_COORDS: Vector2i = Vector2i(4, 3)
const WATER_ANIM_FRAMES: int = 4
const PUDDLE_ANIM_FRAMES: int = 4

const COBBLE_ROWS: Array[Vector2i] = [
	Vector2i(1, 4), Vector2i(5, 8), Vector2i(9, 12), Vector2i(13, 15),
]
const EXTRA_COORDS: Array[Vector2i] = [
	Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4),
	Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4),
]

static var _atlas_cache: Dictionary = {}
static var _tileset_cache: Dictionary = {}
static var _canvas_cache: Dictionary = {}


## Atlas cell for a tile type at an elevation (elevation clamped to 0..2).
static func atlas_coords(tile_type: int, elevation: int) -> Vector2i:
	return Vector2i(clampi(tile_type, 0, TILE_TYPE_COUNT - 1), clampi(elevation, 0, 2))


static func clear_cache() -> void:
	_atlas_cache.clear()
	_tileset_cache.clear()
	_canvas_cache.clear()


static func build_atlas(district: int) -> Image:
	var key: int = clampi(district, 0, 3)
	var cached: Variant = _atlas_cache.get(key)
	if cached != null:
		return cached as Image
	var img: Image = _compose_atlas(key)
	_atlas_cache[key] = img
	return img


static func build_canvas_texture(district: int) -> CanvasTexture:
	var key: int = clampi(district, 0, 3)
	var cached: Variant = _canvas_cache.get(key)
	if cached != null:
		return cached as CanvasTexture
	var texture: CanvasTexture = NormalMapBaker.make_canvas_texture(build_atlas(key), 2.4)
	_canvas_cache[key] = texture
	return texture


static func build_tileset(district: int) -> TileSet:
	var key: int = clampi(district, 0, 3)
	var cached: Variant = _tileset_cache.get(key)
	if cached != null:
		return cached as TileSet
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(CELL, CELL)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)
	tile_set.set_physics_layer_collision_mask(0, 1)
	# Deliberately no navigation layers: Sunshift has no navmesh.

	var atlas := TileSetAtlasSource.new()
	atlas.texture = build_canvas_texture(key)
	atlas.texture_region_size = Vector2i(CELL, CELL)
	tile_set.add_source(atlas, 0)

	for elevation in 3:
		for tile_type in TILE_TYPE_COUNT:
			atlas.create_tile(atlas_coords(tile_type, elevation))
	atlas.create_tile(Vector2i(7, 0))
	atlas.create_tile(Vector2i(7, 1))
	atlas.create_tile(Vector2i(7, 2))
	for coords: Vector2i in EXTRA_COORDS:
		atlas.create_tile(coords)

	atlas.create_tile(WATER_ANIM_COORDS)
	atlas.set_tile_animation_columns(WATER_ANIM_COORDS, WATER_ANIM_FRAMES)
	atlas.set_tile_animation_frames_count(WATER_ANIM_COORDS, WATER_ANIM_FRAMES)
	atlas.set_tile_animation_speed(WATER_ANIM_COORDS, 5.0)
	for frame in WATER_ANIM_FRAMES:
		atlas.set_tile_animation_frame_duration(WATER_ANIM_COORDS, frame, 1.0)

	atlas.create_tile(PUDDLE_ANIM_COORDS)
	atlas.set_tile_animation_columns(PUDDLE_ANIM_COORDS, PUDDLE_ANIM_FRAMES)
	atlas.set_tile_animation_frames_count(PUDDLE_ANIM_COORDS, PUDDLE_ANIM_FRAMES)
	atlas.set_tile_animation_speed(PUDDLE_ANIM_COORDS, 3.0)
	for frame in PUDDLE_ANIM_FRAMES:
		atlas.set_tile_animation_frame_duration(PUDDLE_ANIM_COORDS, frame, 1.0)

	for elevation in 3:
		for solid_type: int in [VOID, WALL, RAILING]:
			var data: TileData = atlas.get_tile_data(atlas_coords(solid_type, elevation), 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, PackedVector2Array([
				Vector2(-CELL * 0.5, -CELL * 0.5),
				Vector2(CELL * 0.5, -CELL * 0.5),
				Vector2(CELL * 0.5, CELL * 0.5),
				Vector2(-CELL * 0.5, CELL * 0.5),
			]))

	_tileset_cache[key] = tile_set
	return tile_set


static func _compose_atlas(district: int) -> Image:
	var img: Image = Image.create_empty(ATLAS_COLS * CELL, ATLAS_ROWS * CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var palette: PixelCanvas.Palette = PixelCanvas.load_palette(district)
	var seed: int = 9100 + district * 977
	for elevation in 3:
		for tile_type in TILE_TYPE_COUNT:
			_draw_cell(img, palette, district, tile_type, elevation, 0, seed + elevation * 31 + tile_type * 7)
		# One material variant per elevation row.
		_draw_material_variant(img, palette, district, elevation, Vector2i(7, elevation), seed + 400 + elevation * 11)
	for frame in WATER_ANIM_FRAMES:
		_draw_water(img, _cell(WATER_ANIM_COORDS + Vector2i(frame, 0)), palette, district, frame, seed + 21)
	for frame in PUDDLE_ANIM_FRAMES:
		_draw_puddle(img, _cell(PUDDLE_ANIM_COORDS + Vector2i(frame, 0)), palette, district, frame, seed + 55)
	_draw_extra(img, palette, district, seed)
	return img


static func _cell(coords: Vector2i) -> Rect2i:
	return Rect2i(coords.x * CELL, coords.y * CELL, CELL, CELL)


static func _draw_cell(img: Image, palette: PixelCanvas.Palette, district: int, tile_type: int, elevation: int, phase: int, seed: int) -> void:
	var rect: Rect2i = _cell(atlas_coords(tile_type, elevation))
	match tile_type:
		VOID:
			_draw_void(img, rect, palette, seed)
		FLOOR:
			_draw_floor(img, rect, palette, district, elevation, seed)
		WALL:
			_draw_wall(img, rect, palette, district, elevation, seed)
		WATER:
			_draw_water(img, rect, palette, district, phase, seed)
		PUDDLE:
			_draw_puddle(img, rect, palette, district, phase, seed)
		STAIRS:
			_draw_stairs(img, rect, palette, district, elevation, seed)
		RAILING:
			_draw_railing(img, rect, palette, district, elevation, seed)
	_apply_elevation(img, rect, palette, elevation)


static func _draw_material_variant(img: Image, palette: PixelCanvas.Palette, district: int, elevation: int, coords: Vector2i, seed: int) -> void:
	var rect: Rect2i = _cell(coords)
	match elevation:
		0:
			_draw_floor(img, rect, palette, district, 0, seed)
		1:
			_draw_floor(img, rect, palette, district, 2, seed)
		_:
			_draw_wall(img, rect, palette, district, 2, seed)
	if elevation == 1:
		_apply_elevation(img, rect, palette, 1)
	elif elevation == 2:
		_apply_elevation(img, rect, palette, 2)


# --- materials -------------------------------------------------------------

static func _draw_floor(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, district: int, elevation: int, seed: int) -> void:
	var style: String = _floor_style(district, elevation)
	match style:
		"cobble":
			_draw_cobble(img, rect, palette, district, seed)
		"flagstone":
			_draw_flagstone(img, rect, palette, district, seed)
		"oxide":
			_draw_oxide(img, rect, palette, seed)
		"planks":
			_draw_planks(img, rect, palette, seed)
		"roof":
			_draw_roof_tiles(img, rect, palette, seed)
		_:
			_draw_cobble(img, rect, palette, district, seed)


static func _floor_style(district: int, elevation: int) -> String:
	# Act I: cobbled alleys -> red-oxide sills -> terracotta roof terraces.
	# Act II: wet cobbles -> oxide verandas -> teak decks.
	# Act III: mossy flagstones -> granite sills -> teak bridge decks.
	# Act IV: worn cobbles -> boardwalk -> granite roof terrace.
	var table: Array[Array] = [
		["cobble", "oxide", "roof"],
		["cobble", "oxide", "planks"],
		["flagstone", "flagstone", "planks"],
		["cobble", "planks", "flagstone"],
	]
	var row: Array = table[clampi(district, 0, 3)]
	return String(row[clampi(elevation, 0, 2)])


static func _draw_cobble(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, district: int, seed: int) -> void:
	var pc := PixelCanvas.new()
	var mortar: Color = palette.shade(palette.color(PixelCanvas.STONE_MID), 0.45)
	pc.fill_rect(img, rect, mortar)
	var tones: Array[Color] = [
		palette.color(PixelCanvas.STONE_MID),
		palette.mix(palette.color(PixelCanvas.STONE_MID), palette.color(PixelCanvas.STONE_LIGHT), 0.35),
		palette.mix(palette.color(PixelCanvas.STONE_MID), palette.color(PixelCanvas.STONE_DARK), 0.30),
		palette.mix(palette.color(PixelCanvas.STONE_MID), palette.color(PixelCanvas.CLAY_MID), 0.25),
	]
	for row_index in COBBLE_ROWS.size():
		var span: Vector2i = COBBLE_ROWS[row_index]
		var shift: int = 0 if row_index % 2 == 0 else 2
		var cursor: int = -1 + shift
		while cursor < CELL:
			var width: int = 3 + int(pc.grain(cursor, row_index, seed) * 2.0)
			var stone := Rect2i(rect.position.x + cursor + 1, rect.position.y + span.x, width, span.y - span.x + 1)
			var tone_index: int = int(pc.grain(cursor * 5 + row_index, row_index * 3, seed + 17) * 4.0) % 4
			var tone: Color = tones[tone_index]
			pc.fill_rect(img, stone, tone)
			pc.hline(img, stone.position.x, stone.end.x - 1, stone.position.y, palette.tint(tone, 0.25))
			pc.vline(img, stone.position.x, stone.position.y, stone.end.y - 1, palette.tint(tone, 0.10))
			pc.hline(img, stone.position.x, stone.end.x - 1, stone.end.y - 1, palette.shade(tone, 0.35))
			pc.vline(img, stone.end.x - 1, stone.position.y, stone.end.y - 1, palette.shade(tone, 0.25))
			cursor += width + 1
	if district == 2 or district == 3:
		var moss: Color = palette.color(PixelCanvas.MOSS_MID)
		pc.put(img, rect.position.x + 3, rect.position.y + 5, moss)
		pc.put(img, rect.position.x + 12, rect.position.y + 11, palette.color(PixelCanvas.MOSS_DARK))
		pc.put(img, rect.position.x + 4, rect.position.y + 12, palette.color(PixelCanvas.MOSS_MID))


static func _draw_flagstone(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, district: int, seed: int) -> void:
	var pc := PixelCanvas.new()
	var joint: Color = palette.shade(palette.color(PixelCanvas.STONE_MID), 0.50)
	pc.fill_rect(img, rect, joint)
	var slabs: Array[Rect2i] = [
		Rect2i(1, 1, 6, 6), Rect2i(8, 1, 7, 5),
		Rect2i(1, 8, 4, 7), Rect2i(6, 7, 4, 8), Rect2i(11, 7, 4, 8),
	]
	for slab: Rect2i in slabs:
		var tone: Color = palette.mix(palette.color(PixelCanvas.STONE_MID), palette.color(PixelCanvas.STONE_LIGHT), 0.20)
		if int(pc.grain(slab.position.x, slab.position.y, seed) * 3.0) % 3 == 0:
			tone = palette.mix(palette.color(PixelCanvas.STONE_MID), palette.color(PixelCanvas.STONE_DARK), 0.20)
		var absolute := Rect2i(rect.position + slab.position, slab.size)
		pc.fill_rect(img, absolute, tone)
		pc.hline(img, absolute.position.x, absolute.end.x - 1, absolute.position.y, palette.tint(tone, 0.30))
		pc.vline(img, absolute.position.x, absolute.position.y, absolute.end.y - 1, palette.tint(tone, 0.15))
		pc.hline(img, absolute.position.x, absolute.end.x - 1, absolute.end.y - 1, palette.shade(tone, 0.30))
		pc.vline(img, absolute.end.x - 1, absolute.position.y, absolute.end.y - 1, palette.shade(tone, 0.25))
	var moss: Color = palette.color(PixelCanvas.MOSS_MID)
	var moss_dark: Color = palette.color(PixelCanvas.MOSS_DARK)
	for i in 4:
		var mx: int = rect.position.x + int(pc.grain(i * 7, 3, seed + 41) * 14.0) + 1
		var my: int = rect.position.y + int(pc.grain(i * 5, 9, seed + 43) * 14.0) + 1
		pc.put(img, mx, my, moss if i % 2 == 0 else moss_dark)
	if district == 2:
		pc.hline(img, rect.position.x + 6, rect.position.x + 8, rect.position.y + 6, moss_dark)


static func _draw_oxide(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, seed: int) -> void:
	var pc := PixelCanvas.new()
	var grout: Color = palette.shade(palette.color(PixelCanvas.CLAY_DARK), 0.25)
	pc.fill_rect(img, rect, grout)
	for ty in 2:
		for tx in 2:
			var tile := Rect2i(rect.position.x + 1 + tx * 8, rect.position.y + 1 + ty * 8, 7, 7)
			var base: Color = palette.color(PixelCanvas.CLAY_MID)
			var variant: int = int(pc.grain(tx * 3, ty * 5, seed) * 3.0) % 3
			if variant == 1:
				base = palette.mix(base, palette.color(PixelCanvas.CLAY_LIGHT), 0.20)
			elif variant == 2:
				base = palette.mix(base, palette.color(PixelCanvas.CLAY_DARK), 0.20)
			pc.fill_rect(img, tile, base)
			pc.hline(img, tile.position.x, tile.end.x - 1, tile.position.y, palette.warm(base, 0.25))
			pc.vline(img, tile.position.x, tile.position.y, tile.end.y - 1, palette.tint(base, 0.20))
			pc.hline(img, tile.position.x, tile.end.x - 1, tile.end.y - 1, palette.shade(base, 0.30))
			pc.vline(img, tile.end.x - 1, tile.position.y, tile.end.y - 1, palette.shade(base, 0.25))
			# wet sheen: two dither pixels catching the sky
			pc.put(img, tile.position.x + 1, tile.position.y + 1, palette.warm(palette.color(PixelCanvas.CLAY_LIGHT), 0.30))
			if variant != 2:
				pc.put(img, tile.position.x + 5, tile.position.y + 2, palette.tint(base, 0.35))
	# one hairline crack through the grout
	pc.put(img, rect.position.x + 9, rect.position.y + 6, palette.color(PixelCanvas.CLAY_DARK))
	pc.put(img, rect.position.x + 10, rect.position.y + 7, palette.color(PixelCanvas.CLAY_DARK))


static func _draw_planks(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, seed: int) -> void:
	var pc := PixelCanvas.new()
	var seam: Color = palette.shade(palette.color(PixelCanvas.WOOD_DARK), 0.30)
	pc.fill_rect(img, rect, seam)
	var plank_height: int = 4
	for plank in 4:
		var y: int = rect.position.y + plank * plank_height
		var base: Color = palette.color(PixelCanvas.WOOD_MID)
		var variant: int = int(pc.grain(plank * 7, plank * 3, seed) * 3.0) % 3
		if variant == 1:
			base = palette.mix(base, palette.color(PixelCanvas.WOOD_LIGHT), 0.25)
		elif variant == 2:
			base = palette.mix(base, palette.color(PixelCanvas.WOOD_DARK), 0.20)
		var body := Rect2i(rect.position.x, y, CELL, plank_height - 1)
		pc.fill_rect(img, body, base)
		pc.hline(img, body.position.x, body.end.x - 1, body.position.y, palette.tint(base, 0.20))
		pc.hline(img, body.position.x, body.end.x - 1, body.end.y - 1, palette.shade(base, 0.25))
		# grain dashes
		for dash in 3:
			var dx: int = rect.position.x + int(pc.grain(plank * 9 + dash, dash, seed + 7) * 12.0) + 1
			var shade: Color = palette.shade(base, 0.25) if dash % 2 == 0 else palette.tint(base, 0.15)
			pc.hline(img, dx, mini(dx + 2, rect.end.x - 1), y + 1 + dash % 3, shade)
		if int(pc.grain(plank, 11, seed + 13) * 5.0) % 5 == 0:
			pc.put(img, rect.position.x + 11, y + 2, palette.color(PixelCanvas.WOOD_DARK))
			pc.put(img, rect.position.x + 12, y + 1, palette.color(PixelCanvas.WOOD_DARK))
	# board ends
	pc.vline(img, rect.position.x + 5, rect.position.y, rect.end.y - 1, seam)
	pc.vline(img, rect.position.x + 12, rect.position.y, rect.end.y - 1, seam)


static func _draw_roof_tiles(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, seed: int) -> void:
	var pc := PixelCanvas.new()
	var base: Color = palette.color(PixelCanvas.CLAY_MID)
	pc.fill_rect(img, rect, base)
	for y in CELL:
		for x in CELL:
			var rib: int = x % 3
			var course: int = y % 5
			var c: Color = base
			if rib == 0:
				c = palette.tint(base, 0.30)
			elif rib == 2:
				c = palette.shade(base, 0.30)
			if course == 0:
				c = palette.shade(c, 0.35)
			elif course == 1:
				c = palette.tint(c, 0.15)
			pc.put(img, rect.position.x + x, rect.position.y + y, c)
	# sun-lit left slopes and a couple of chipped tiles
	for k in 3:
		var cx: int = rect.position.x + int(pc.grain(k, 4, seed) * 13.0) + 1
		var cy: int = rect.position.y + int(pc.grain(k, 8, seed + 3) * 13.0) + 1
		pc.put(img, cx, cy, palette.warm(base, 0.35))


static func _draw_wall(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, district: int, elevation: int, seed: int) -> void:
	var pc := PixelCanvas.new()
	if district == 2:
		_draw_granite_blocks(img, rect, palette, seed)
	elif district == 1:
		_draw_timber_wall(img, rect, palette, seed)
	elif district == 3:
		_draw_harbour_wall(img, rect, palette, seed)
	else:
		_draw_plaster(img, rect, palette, seed)
	if elevation >= 2:
		# Terracotta coping: the wall reads as a parapet from above.
		var cap := Rect2i(rect.position.x, rect.position.y, CELL, 5)
		var saved := Rect2i(rect.position.x, rect.position.y + 5, CELL, CELL - 5)
		_draw_roof_tiles(img, cap, palette, seed + 91)
		pc.hline(img, saved.position.x, saved.end.x - 1, saved.position.y - 1, palette.shade(palette.color(PixelCanvas.CLAY_DARK), 0.25))
	# bottom shade anchors the wall to the ground
	pc.hline(img, rect.position.x, rect.end.x - 1, rect.end.y - 1, palette.shade(palette.color(PixelCanvas.STONE_DARK), 0.20))
	pc.hline(img, rect.position.x, rect.end.x - 1, rect.end.y - 2, palette.shade(palette.color(PixelCanvas.STONE_MID), 0.45))


static func _draw_plaster(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, seed: int) -> void:
	var pc := PixelCanvas.new()
	var plaster: Color = palette.mix(palette.color(PixelCanvas.STONE_LIGHT), palette.color(PixelCanvas.CLOTH_MID), 0.35)
	pc.fill_rect(img, rect, plaster)
	for y in CELL:
		for x in CELL:
			var n: float = pc.grain(x * 3, y * 5, seed)
			if n > 0.78:
				pc.put(img, rect.position.x + x, rect.position.y + y, palette.mix(plaster, palette.color(PixelCanvas.STONE_MID), 0.30))
			elif n < 0.14:
				pc.put(img, rect.position.x + x, rect.position.y + y, palette.tint(plaster, 0.25))
	var plinth: Color = palette.color(PixelCanvas.STONE_MID)
	pc.fill_rect(img, Rect2i(rect.position.x, rect.end.y - 3, CELL, 3), plinth)
	pc.hline(img, rect.position.x, rect.end.x - 1, rect.end.y - 4, palette.shade(plinth, 0.30))
	pc.hline(img, rect.position.x, rect.end.x - 1, rect.end.y - 3, palette.tint(plinth, 0.20))
	# a single weathered brick showing through
	pc.fill_rect(img, Rect2i(rect.position.x + 10, rect.position.y + 6, 3, 2), palette.color(PixelCanvas.CLAY_MID))
	pc.put(img, rect.position.x + 10, rect.position.y + 6, palette.tint(palette.color(PixelCanvas.CLAY_MID), 0.25))


static func _draw_timber_wall(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, seed: int) -> void:
	var pc := PixelCanvas.new()
	var plaster: Color = palette.mix(palette.color(PixelCanvas.STONE_LIGHT), palette.color(PixelCanvas.CLOTH_MID), 0.30)
	pc.fill_rect(img, rect, plaster)
	for y in CELL:
		for x in CELL:
			if pc.grain(x * 7, y * 3, seed) > 0.82:
				pc.put(img, rect.position.x + x, rect.position.y + y, palette.mix(plaster, palette.color(PixelCanvas.STONE_MID), 0.30))
	# teak frame: two posts and a lintel
	var beam: Color = palette.color(PixelCanvas.WOOD_MID)
	pc.fill_rect(img, Rect2i(rect.position.x + 1, rect.position.y, 2, CELL), beam)
	pc.fill_rect(img, Rect2i(rect.position.x + 13, rect.position.y, 2, CELL), palette.shade(beam, 0.20))
	pc.hline(img, rect.position.x, rect.end.x - 1, rect.position.y + 3, palette.tint(beam, 0.25))
	pc.hline(img, rect.position.x, rect.end.x - 1, rect.position.y + 4, palette.shade(beam, 0.35))
	pc.vline(img, rect.position.x + 1, rect.position.y, rect.end.y - 1, palette.tint(beam, 0.20))
	pc.vline(img, rect.position.x + 2, rect.position.y, rect.end.y - 1, palette.shade(beam, 0.30))
	# rain streak
	pc.vline(img, rect.position.x + 8, rect.position.y + 5, rect.position.y + 10, palette.shade(plaster, 0.25))
	pc.put(img, rect.position.x + 11, rect.position.y + 8, palette.color(PixelCanvas.MOSS_DARK))


static func _draw_granite_blocks(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, seed: int) -> void:
	var pc := PixelCanvas.new()
	var mortar: Color = palette.shade(palette.color(PixelCanvas.STONE_DARK), 0.15)
	pc.fill_rect(img, rect, mortar)
	var course_height: int = 4
	for course in 4:
		var y: int = rect.position.y + course * course_height
		var offset: int = 0 if course % 2 == 0 else 3
		var x: int = -offset
		while x < CELL:
			var width: int = 5 + int(pc.grain(x, course, seed) * 3.0)
			var block := Rect2i(rect.position.x + x + 1, y + 1, width - 1, course_height - 1)
			var tone: Color = palette.mix(palette.color(PixelCanvas.STONE_MID), palette.color(PixelCanvas.STONE_LIGHT), 0.15)
			if int(pc.grain(x * 3, course * 5, seed + 5) * 3.0) % 3 == 0:
				tone = palette.mix(tone, palette.color(PixelCanvas.STONE_DARK), 0.20)
			pc.fill_rect(img, block, tone)
			pc.hline(img, block.position.x, block.end.x - 1, block.position.y, palette.tint(tone, 0.30))
			pc.hline(img, block.position.x, block.end.x - 1, block.end.y - 1, palette.shade(tone, 0.30))
			pc.put(img, block.position.x + 1, block.position.y + 1, palette.tint(tone, 0.35))
			x += width
	var moss: Color = palette.color(PixelCanvas.MOSS_MID)
	pc.put(img, rect.position.x + 4, rect.position.y + 9, moss)
	pc.put(img, rect.position.x + 5, rect.position.y + 9, palette.color(PixelCanvas.MOSS_DARK))
	pc.put(img, rect.position.x + 11, rect.position.y + 13, moss)


static func _draw_harbour_wall(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, seed: int) -> void:
	var pc := PixelCanvas.new()
	_draw_granite_blocks(img, rect, palette, seed)
	# salt bloom and a painted coral band, both very Act IV.
	var band: Color = palette.shade(palette.color(PixelCanvas.CLAY_MID), 0.25)
	pc.fill_rect(img, Rect2i(rect.position.x, rect.position.y + 6, CELL, 2), band)
	pc.hline(img, rect.position.x, rect.end.x - 1, rect.position.y + 6, palette.tint(band, 0.25))
	for i in 3:
		var x: int = rect.position.x + int(pc.grain(i * 11, 2, seed) * 14.0) + 1
		var y: int = rect.position.y + int(pc.grain(i * 13, 7, seed + 2) * 12.0) + 1
		pc.put(img, x, y, palette.mix(palette.color(PixelCanvas.STONE_LIGHT), palette.color(PixelCanvas.CLOTH_MID), 0.30))


static func _draw_water(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, district: int, phase: int, seed: int) -> void:
	var pc := PixelCanvas.new()
	var deep: Color = palette.color(PixelCanvas.WATER_DARK)
	var mid: Color = palette.color(PixelCanvas.WATER_MID)
	var light: Color = palette.color(PixelCanvas.WATER_LIGHT)
	var step: int = 1 + district % 2
	for y in CELL:
		for x in CELL:
			var t: float = float(y) / float(CELL - 1)
			var dither: float = pc.bayer4(x + phase * step, y)
			var c: Color = deep
			if dither < t * 1.15:
				c = mid
			if t > 0.78 and dither < (t - 0.78) * 2.2:
				c = palette.mix(mid, light, 0.20)
			pc.put(img, rect.position.x + x, rect.position.y + y, c)
	# drifting highlight dashes, shifted by the animation phase
	for band in 4:
		var wy: int = posmod(phase * 2 + band * 4 + district, CELL)
		for x in CELL:
			if pc.grain(x * 3 + phase, wy + band, seed) > 0.62:
				pc.put(img, rect.position.x + x, rect.position.y + wy, light)
	# sun reflection column
	for y in CELL:
		if pc.grain(y, phase, seed + 4) > 0.45:
			pc.put(img, rect.position.x + 5 + posmod(y + phase, 3) - 1, rect.position.y + y, palette.mix(mid, light, 0.45))
	# two sparkles
	pc.put(img, rect.position.x + 2 + posmod(phase, 5), rect.position.y + 3, light)
	pc.put(img, rect.position.x + 11 - posmod(phase, 4), rect.position.y + 11, light)


static func _draw_puddle(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, district: int, phase: int, seed: int) -> void:
	var pc := PixelCanvas.new()
	_draw_floor(img, rect, palette, district, 0, seed)
	var deep: Color = palette.color(PixelCanvas.WATER_DARK)
	var mid: Color = palette.color(PixelCanvas.WATER_MID)
	var light: Color = palette.color(PixelCanvas.WATER_LIGHT)
	var cx: int = rect.position.x + 8
	var cy: int = rect.position.y + 10
	var rx: int = 5
	var ry: int = 3
	for y in range(-ry, ry + 1):
		for x in range(-rx, rx + 1):
			var dx: float = float(x) / float(rx)
			var dy: float = float(y) / float(ry)
			var wobble: float = (pc.grain(x + 8, y + 8, seed) - 0.5) * 0.30
			if dx * dx + dy * dy <= 0.95 + wobble:
				var c: Color = deep if dy > 0.0 else mid
				pc.put(img, cx + x, cy + y, c)
	# sky rim along the top edge of the puddle
	for x in range(-rx + 1, rx):
		var threshold: float = 1.0 - float(absf(float(x))) / float(rx)
		if threshold > 0.35:
			pc.put(img, cx + x, cy - ry + 1, light)
	# expanding ripple ring
	var ring: int = 1 + phase
	for a in 16:
		var angle: float = TAU * float(a) / 16.0
		var px: int = cx + roundi(cos(angle) * float(ring + 1) * 0.75)
		var py: int = cy + roundi(sin(angle) * float(ring) * 0.55)
		if pc.bayer4(px, py) < 0.55:
			pc.put(img, px, py, palette.mix(mid, light, 0.50))
	# wet lip under the far edge
	pc.put(img, cx - 3, cy + ry, palette.shade(deep, 0.20))
	pc.put(img, cx + 2, cy + ry, palette.shade(deep, 0.20))


static func _draw_stairs(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, district: int, elevation: int, seed: int) -> void:
	var pc := PixelCanvas.new()
	var style: String = _floor_style(district, 0)
	var base: Color = palette.color(PixelCanvas.STONE_MID)
	if style == "planks":
		base = palette.color(PixelCanvas.WOOD_MID)
	elif style == "oxide":
		base = palette.color(PixelCanvas.CLAY_MID)
	pc.fill_rect(img, rect, palette.shade(base, 0.35))
	var steps: int = 3 + elevation
	var step_height: int = int(floor(float(CELL - 1) / float(steps)))
	for step in steps:
		var y: int = rect.position.y + step * step_height
		var tread := Rect2i(rect.position.x + 1, y, CELL - 2, maxi(1, step_height - 1))
		pc.fill_rect(img, tread, base)
		pc.hline(img, tread.position.x, tread.end.x - 1, tread.position.y, palette.tint(base, 0.30))
		pc.hline(img, tread.position.x, tread.end.x - 1, tread.end.y - 1, palette.shade(base, 0.40))
		pc.put(img, tread.position.x, tread.end.y - 1, palette.shade(base, 0.30))
		pc.put(img, tread.end.x - 1, tread.end.y - 1, palette.shade(base, 0.30))
	# stringers keep the steps from floating
	pc.vline(img, rect.position.x, rect.position.y + 2, rect.end.y - 1, palette.shade(base, 0.45))
	pc.vline(img, rect.end.x - 1, rect.position.y + 2, rect.end.y - 1, palette.shade(base, 0.50))
	if elevation > 0:
		pc.put(img, rect.position.x + 3, rect.position.y + 5, palette.color(PixelCanvas.MOSS_DARK))


static func _draw_railing(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, district: int, elevation: int, seed: int) -> void:
	var pc := PixelCanvas.new()
	_draw_floor(img, rect, palette, district, mini(elevation, 1), seed)
	var wood_rail: bool = district == 1
	var post: Color = palette.color(PixelCanvas.WOOD_MID) if wood_rail else palette.color(PixelCanvas.METAL_MID)
	var post_dark: Color = palette.color(PixelCanvas.WOOD_DARK) if wood_rail else palette.color(PixelCanvas.METAL_DARK)
	var post_light: Color = palette.color(PixelCanvas.WOOD_LIGHT) if wood_rail else palette.color(PixelCanvas.METAL_LIGHT)
	# posts
	for px: int in [2, 12]:
		var x: int = rect.position.x + px
		pc.fill_rect(img, Rect2i(x, rect.position.y + 2, 2, CELL - 3), post)
		pc.vline(img, x, rect.position.y + 2, rect.end.y - 2, post_light)
		pc.vline(img, x + 1, rect.position.y + 3, rect.end.y - 2, post_dark)
	# rails
	pc.hline(img, rect.position.x + 1, rect.end.x - 2, rect.position.y + 3, post)
	pc.hline(img, rect.position.x + 1, rect.end.x - 2, rect.position.y + 4, post_dark)
	pc.hline(img, rect.position.x + 1, rect.end.x - 2, rect.position.y + 4, post_dark)
	pc.hline(img, rect.position.x + 1, rect.end.x - 2, rect.position.y + 9, post)
	pc.hline(img, rect.position.x + 1, rect.end.x - 2, rect.position.y + 10, post_dark)
	pc.hline(img, rect.position.x + 1, rect.end.x - 2, rect.position.y + 3, post_light)
	# balusters / ironwork
	for x in range(rect.position.x + 4, rect.end.x - 2, 3):
		pc.vline(img, x, rect.position.y + 5, rect.position.y + 8, post_dark)
		if wood_rail:
			pc.put(img, x, rect.position.y + 5, post_light)
	# hanging vine for the mossy districts
	if district >= 2:
		pc.vline(img, rect.position.x + 7, rect.position.y + 11, rect.position.y + 14, palette.color(PixelCanvas.MOSS_MID))
		pc.put(img, rect.position.x + 8, rect.position.y + 13, palette.color(PixelCanvas.MOSS_DARK))


static func _draw_void(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, seed: int) -> void:
	var pc := PixelCanvas.new()
	var deep: Color = palette.mix(palette.color(PixelCanvas.STONE_DARK), palette.color(PixelCanvas.WOOD_DARK), 0.35)
	var deeper: Color = palette.mix(palette.color(PixelCanvas.STONE_DARK), palette.color(PixelCanvas.WOOD_DARK), 0.60)
	for y in CELL:
		for x in CELL:
			var hatch: bool = posmod(x + y, 4) == 0
			var c: Color = deeper if hatch else deep
			if pc.grain(x, y, seed) > 0.88:
				c = palette.mix(deep, palette.color(PixelCanvas.STONE_MID), 0.15)
			pc.put(img, rect.position.x + x, rect.position.y + y, c)
	pc.hline(img, rect.position.x, rect.end.x - 1, rect.end.y - 1, deeper)
	pc.vline(img, rect.end.x - 1, rect.position.y, rect.end.y - 1, deeper)


static func _draw_extra(img: Image, palette: PixelCanvas.Palette, district: int, seed: int) -> void:
	var pc := PixelCanvas.new()
	# 0: cracked cobble
	var cracked: Rect2i = _cell(EXTRA_COORDS[0])
	_draw_cobble(img, cracked, palette, district, seed + 3)
	pc.put(img, cracked.position.x + 7, cracked.position.y + 3, palette.color(PixelCanvas.STONE_DARK))
	pc.put(img, cracked.position.x + 8, cracked.position.y + 4, palette.color(PixelCanvas.STONE_DARK))
	pc.put(img, cracked.position.x + 8, cracked.position.y + 5, palette.color(PixelCanvas.STONE_DARK))
	pc.put(img, cracked.position.x + 9, cracked.position.y + 6, palette.color(PixelCanvas.STONE_DARK))
	# 1: wet red-oxide
	var oxide: Rect2i = _cell(EXTRA_COORDS[1])
	_draw_oxide(img, oxide, palette, seed + 9)
	pc.put(img, oxide.position.x + 3, oxide.position.y + 11, palette.color(PixelCanvas.CLAY_LIGHT))
	pc.put(img, oxide.position.x + 4, oxide.position.y + 12, palette.color(PixelCanvas.CLAY_LIGHT))
	# 2: teak deck
	var deck: Rect2i = _cell(EXTRA_COORDS[2])
	_draw_planks(img, deck, palette, seed + 15)
	# 3: mossy slab
	var slab: Rect2i = _cell(EXTRA_COORDS[3])
	_draw_flagstone(img, slab, palette, district, seed + 21)
	pc.put(img, slab.position.x + 2, slab.position.y + 2, palette.color(PixelCanvas.MOSS_MID))
	pc.put(img, slab.position.x + 3, slab.position.y + 2, palette.color(PixelCanvas.MOSS_DARK))
	# 4: roof tiles
	var roof: Rect2i = _cell(EXTRA_COORDS[4])
	_draw_roof_tiles(img, roof, palette, seed + 27)
	# 5: brass drain grate
	var grate: Rect2i = _cell(EXTRA_COORDS[5])
	_draw_cobble(img, grate, palette, district, seed + 33)
	var brass: Color = palette.color(PixelCanvas.METAL_MID)
	pc.fill_rect(img, Rect2i(grate.position.x + 2, grate.position.y + 2, 12, 12), palette.color(PixelCanvas.METAL_DARK))
	for bar in 4:
		pc.vline(img, grate.position.x + 3 + bar * 3, grate.position.y + 3, grate.position.y + 12, brass)
		pc.vline(img, grate.position.x + 3 + bar * 3, grate.position.y + 3, grate.position.y + 12, brass)
	pc.hline(img, grate.position.x + 2, grate.end.x - 3, grate.position.y + 2, palette.color(PixelCanvas.METAL_LIGHT))
	pc.hline(img, grate.position.x + 2, grate.end.x - 3, grate.position.y + 13, palette.color(PixelCanvas.METAL_DARK))
	# 6: gutter channel
	var gutter: Rect2i = _cell(EXTRA_COORDS[6])
	_draw_cobble(img, gutter, palette, district, seed + 39)
	var channel := Rect2i(gutter.position.x + 2, gutter.position.y + 2, 12, 12)
	pc.fill_rect(img, channel, palette.color(PixelCanvas.WATER_DARK))
	for x in range(channel.position.x, channel.end.x):
		if pc.grain(x, 2, seed) > 0.5:
			pc.put(img, x, channel.position.y + 3, palette.color(PixelCanvas.WATER_MID))
			pc.put(img, x, channel.position.y + 9, palette.color(PixelCanvas.WATER_LIGHT))
	pc.rect_outline(img, channel, palette.color(PixelCanvas.STONE_DARK))
	# 7: planter bed
	var planter: Rect2i = _cell(EXTRA_COORDS[7])
	_draw_cobble(img, planter, palette, district, seed + 45)
	var box := Rect2i(planter.position.x + 1, planter.position.y + 6, 14, 8)
	pc.fill_rect(img, box, palette.color(PixelCanvas.WOOD_MID))
	pc.hline(img, box.position.x, box.end.x - 1, box.position.y, palette.color(PixelCanvas.WOOD_LIGHT))
	pc.hline(img, box.position.x, box.end.x - 1, box.end.y - 1, palette.color(PixelCanvas.WOOD_DARK))
	pc.fill_rect(img, Rect2i(box.position.x + 2, box.position.y + 2, 10, 4), palette.color(PixelCanvas.MOSS_MID))
	for i in 4:
		pc.put(img, box.position.x + 3 + i * 3, box.position.y + 2 + (i % 2), palette.color(PixelCanvas.CLAY_LIGHT))
	pc.put(img, box.position.x + 5, box.position.y + 4, palette.color(PixelCanvas.MOSS_DARK))


static func _apply_elevation(img: Image, rect: Rect2i, palette: PixelCanvas.Palette, elevation: int) -> void:
	var pc := PixelCanvas.new()
	var light: Color = palette.tint(palette.color(PixelCanvas.CLOTH_LIGHT), 0.25)
	var dark: Color = palette.shade(palette.color(PixelCanvas.STONE_DARK), 0.10)
	if elevation <= 0:
		# Ground tiles draw no border at all: a per-tile bevel tiles into a
		# visible grid, so the surface has to read as continuous across cells.
		return
	var riser: int = elevation * 2
	for y in range(rect.end.y - riser, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, palette.shade(c, 0.35))
	# A single riser highlight reads as height. No left/right rules and no top
	# rule, because those are what turn a terrace into a checkerboard.
	pc.hline(img, rect.position.x, rect.end.x - 1, rect.end.y - riser - 1, light)
