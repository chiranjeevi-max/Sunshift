extends SceneTree

## Guards the properties that make this game pixel-perfect. Every one of these
## is a single project setting away from silently turning the whole game into
## mush, and none of them show up in any other test: a bilinear filter or a
## mip chain still passes every simulation, art and level check.
##
## Run: godot --headless --path . --script res://tests/test_pixel_perfect.gd

const BASE_W: int = 480
const BASE_H: int = 270

var _checks: int = 0
var _failed: int = 0


func _initialize() -> void:
	_test_viewport()
	_test_filtering()
	_test_snapping()
	_test_antialiasing()
	_test_text()
	_test_generated_textures()
	if _failed == 0:
		print("test_pixel_perfect: PASS (%d checks)" % _checks)
	else:
		printerr("test_pixel_perfect: FAIL (%d of %d checks)" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed += 1
		printerr("  FAIL %s" % label)


func _setting(path: String) -> Variant:
	return ProjectSettings.get_setting(path)


func _test_viewport() -> void:
	_check(int(_setting("display/window/size/viewport_width")) == BASE_W, "base width is %d" % BASE_W)
	_check(int(_setting("display/window/size/viewport_height")) == BASE_H, "base height is %d" % BASE_H)
	_check(str(_setting("display/window/stretch/mode")) == "viewport",
		"stretch mode is viewport (a crisp low-res buffer, not a scaled window)")
	# Integer scaling is the whole point: 1x, 2x, 3x, 4x with letterboxing,
	# never 1.7x with resampled pixels.
	_check(str(_setting("display/window/stretch/scale_mode")) == "integer",
		"stretch scale mode is integer")
	_check(str(_setting("display/window/stretch/aspect")) == "keep",
		"aspect is keep (never stretch the frame)")
	var override_w: int = int(_setting("display/window/size/window_width_override"))
	var override_h: int = int(_setting("display/window/size/window_height_override"))
	if override_w > 0 and override_h > 0:
		_check(override_w % BASE_W == 0 and override_h % BASE_H == 0,
			"window override %dx%d is a whole multiple of %dx%d" % [override_w, override_h, BASE_W, BASE_H])
		_check(override_w / BASE_W == override_h / BASE_H, "window override keeps the aspect ratio")


func _test_filtering() -> void:
	_check(int(_setting("rendering/textures/canvas_textures/default_texture_filter")) == 0,
		"default canvas texture filter is nearest")
	_check(not bool(_setting("rendering/textures/canvas_textures/default_texture_repeat")),
		"default canvas texture repeat is off")


func _test_snapping() -> void:
	_check(bool(_setting("rendering/2d/snap/snap_2d_transforms_to_pixel")),
		"2D transforms snap to the pixel grid")
	_check(bool(_setting("rendering/2d/snap/snap_2d_vertices_to_pixel")),
		"2D vertices snap to the pixel grid")


func _test_antialiasing() -> void:
	# No MSAA anywhere: 2D guidance is to leave it off and let the art be art.
	_check(int(_setting("rendering/anti_aliasing/quality/msaa_2d")) == 0, "MSAA 2D is disabled")
	_check(int(_setting("rendering/anti_aliasing/quality/msaa_3d")) == 0, "MSAA 3D is disabled")
	_check(int(_setting("rendering/anti_aliasing/quality/screen_space_aa")) == 0, "screen-space AA is disabled")
	_check(not bool(_setting("rendering/anti_aliasing/quality/use_taa")), "TAA is disabled")
	_check(not bool(_setting("rendering/anti_aliasing/quality/use_debanding")), "debanding is off")


func _test_text() -> void:
	# The default font is rendered into the low-res buffer, so any smoothing
	# here is baked into the pixels and scaled up with everything else.
	_check(int(_setting("gui/theme/default_font_antialiasing")) == 0, "font antialiasing is off")
	_check(int(_setting("gui/theme/default_font_subpixel_positioning")) == 0,
		"font subpixel positioning is off")
	_check(not bool(_setting("gui/theme/default_font_multichannel_signed_distance_field")),
		"MSDF font rendering is off")
	_check(not bool(_setting("gui/theme/default_font_generate_mipmaps")),
		"font mipmaps are off")


## Every texture in this game is synthesised at boot, so the import pipeline
## never runs on it. If a generator ever bakes mipmaps, this is the only place
## that would notice before players saw a shimmer.
func _test_generated_textures() -> void:
	var tileset_script: GDScript = load("res://src/art/TilesetGenerator.gd") as GDScript
	if tileset_script == null:
		_check(false, "TilesetGenerator loads")
	else:
		var canvas: Variant = tileset_script.call("build_canvas_texture", 0)
		var diffuse: Texture2D = (canvas as CanvasTexture).diffuse_texture if canvas is CanvasTexture else null
		_check(diffuse != null, "district 0 builds a diffuse texture")
		if diffuse != null:
			var img: Image = diffuse.get_image()
			_check(not img.has_mipmaps(), "tile atlas has no mip chain")
			_check(diffuse.get_width() % 4 == 0 and diffuse.get_height() % 4 == 0,
				"tile atlas is a multiple of 4 in both axes")

	var sprite_script: GDScript = load("res://src/art/CharacterSpriteGen.gd") as GDScript
	if sprite_script == null:
		_check(false, "CharacterSpriteGen loads")
	else:
		var frames: Variant = sprite_script.call("build_frames", "milo")
		if not (frames is SpriteFrames):
			_check(false, "Milo builds a SpriteFrames")
		else:
			var sheet: SpriteFrames = frames as SpriteFrames
			var probe: Texture2D = sheet.get_frame_texture("idle_down", 0)
			_check(probe != null, "Milo idle_down has a frame")
			if probe != null:
				_check(not probe.get_image().has_mipmaps(), "sprite sheet has no mip chain")
				_check(probe.get_width() % 16 == 0, "sprite frame width is a whole number of cells")
