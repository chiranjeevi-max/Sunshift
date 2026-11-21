class_name NormalMapBaker
extends RefCounted
## Sobel height-to-normal baking for Sunshift's CanvasTexture atlases.
##
## Godot 2D normal maps use tangent space with X+ right, Y+ down and Z+ out of
## the screen, so a surface rising toward +X tilts its normal toward -X.

const FLAT: Color = Color(0.5, 0.5, 1.0, 1.0)


## Builds a tangent-space normal map from an image's luminance-as-height.
## Transparent pixels become flat normals so tile edges do not erupt.
static func from_height(img: Image, strength: float = 2.0) -> Image:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var out: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.5, 0.5, 1.0, 0.0))
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	for y in h:
		for x in w:
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.02:
				heights[y * w + x] = 0.0
			else:
				heights[y * w + x] = (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) * c.a
	var scale: float = maxf(0.01, strength)
	for y in h:
		for x in w:
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.02:
				out.set_pixel(x, y, Color(0.5, 0.5, 1.0, 1.0))
				continue
			var tl: float = _height_at(heights, w, h, x - 1, y - 1)
			var tc: float = _height_at(heights, w, h, x, y - 1)
			var tr: float = _height_at(heights, w, h, x + 1, y - 1)
			var ml: float = _height_at(heights, w, h, x - 1, y)
			var mr: float = _height_at(heights, w, h, x + 1, y)
			var bl: float = _height_at(heights, w, h, x - 1, y + 1)
			var bc: float = _height_at(heights, w, h, x, y + 1)
			var br: float = _height_at(heights, w, h, x + 1, y + 1)
			var dx: float = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl)
			var dy: float = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr)
			# Height rising toward +X / +Y tilts the normal the other way.
			var nx: float = -dx * scale * 0.125
			var ny: float = -dy * scale * 0.125
			var nz: float = 1.0
			var length: float = sqrt(nx * nx + ny * ny + nz * nz)
			if length <= 0.00001:
				out.set_pixel(x, y, Color(0.5, 0.5, 1.0, 1.0))
				continue
			nx /= length
			ny /= length
			nz /= length
			out.set_pixel(x, y, Color(nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5, 1.0))
	return out


static func height_from_diffuse(diffuse: Image) -> Image:
	var w: int = diffuse.get_width()
	var h: int = diffuse.get_height()
	var out: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c: Color = diffuse.get_pixel(x, y)
			var lum: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			out.set_pixel(x, y, Color(lum, lum, lum, c.a))
	return out


## Low-contrast specular map: saturated brass and wet stone read shinier than
## dry plaster, which is enough for the PointLight2D beams to catch an edge.
static func specular_from_diffuse(diffuse: Image) -> Image:
	var w: int = diffuse.get_width()
	var h: int = diffuse.get_height()
	var out: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c: Color = diffuse.get_pixel(x, y)
			if c.a <= 0.02:
				out.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var lum: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			var high: float = maxf(c.r, maxf(c.g, c.b))
			var low: float = minf(c.r, minf(c.g, c.b))
			var saturation: float = clampf(high - low, 0.0, 1.0)
			var strength: float = clampf(0.10 + lum * 0.30 + saturation * 0.22, 0.0, 0.72)
			var shininess: float = clampf(0.30 + saturation * 0.55 + lum * 0.15, 0.0, 0.95)
			out.set_pixel(x, y, Color(strength, strength, strength, shininess))
	return out


## Assembles the three maps Godot needs for lit 2D pixel art.
static func make_canvas_texture(diffuse: Image, normal_strength: float = 2.0) -> CanvasTexture:
	var texture := CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(diffuse)
	texture.normal_texture = ImageTexture.create_from_image(from_height(diffuse, normal_strength))
	texture.specular_texture = ImageTexture.create_from_image(specular_from_diffuse(diffuse))
	texture.specular_color = Color(1.0, 0.93, 0.80)
	texture.specular_shininess = 0.55
	return texture


static func _height_at(heights: PackedFloat32Array, w: int, h: int, x: int, y: int) -> float:
	var cx: int = clampi(x, 0, w - 1)
	var cy: int = clampi(y, 0, h - 1)
	return heights[cy * w + cx]
