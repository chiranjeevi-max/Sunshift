# Checks canvas shader types and the uniforms used by gameplay and UI.
#
# Run: godot --headless --path . --script res://tests/test_shaders.gd
#
# Godot exits 0 even after a failed assertion, so this runner counts its own
# failures and quits with 1. Loading is not enough to compile a shader:
# get_shader_uniform_list() forces the engine's shader compiler to run, which is
# what turns a syntax or built-in mistake into a visible SHADER ERROR.
extends SceneTree

const SHADER_DIR: String = "res://src/shaders"

const SHADER_FILES: Array[String] = [
	"emotional_grade.gdshader",
	"sunbeam_volumetric.gdshader",
	"wind_sway.gdshader",
	"postcard_reveal.gdshader",
]

# file -> uniform names that are a public interface (gameplay/UI set these).
const REQUIRED_UNIFORMS: Dictionary = {
	"emotional_grade.gdshader": [
		"warmth_factor",
		"shadow_cool",
		"shadow_warm",
		"highlight_cool",
		"highlight_warm",
		"bloom_strength",
		"vignette_strength",
	],
	"sunbeam_volumetric.gdshader": [
		"beam_color",
		"beam_strength",
		"time_scale",
		"pixel_size",
		"feather",
	],
	"wind_sway.gdshader": [
		"sway_amount",
		"sway_speed",
		"anchor_y",
		"anchor_top",
		"pixel_size",
		"gust",
	],
	"postcard_reveal.gdshader": [
		"reveal",
		"seal_center",
		"grain_amount",
		"seal_color",
	],
}

# source_color uniforms are exposed as Color properties (TYPE_COLOR), not the
# underlying vec3/vec4, so that is what the interface check asserts.
const UNIFORM_TYPES: Dictionary = {
	"warmth_factor": TYPE_FLOAT,
	"shadow_cool": TYPE_VECTOR3,
	"shadow_warm": TYPE_VECTOR3,
	"highlight_cool": TYPE_VECTOR3,
	"highlight_warm": TYPE_VECTOR3,
	"bloom_strength": TYPE_FLOAT,
	"vignette_strength": TYPE_FLOAT,
	"beam_color": TYPE_COLOR,
	"beam_strength": TYPE_FLOAT,
	"time_scale": TYPE_FLOAT,
	"pixel_size": TYPE_FLOAT,
	"feather": TYPE_FLOAT,
	"sway_amount": TYPE_FLOAT,
	"sway_speed": TYPE_FLOAT,
	"anchor_y": TYPE_FLOAT,
	"anchor_top": TYPE_BOOL,
	"gust": TYPE_FLOAT,
	"reveal": TYPE_FLOAT,
	"seal_center": TYPE_VECTOR2,
	"grain_amount": TYPE_FLOAT,
	"seal_color": TYPE_COLOR,
}

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	for file: String in SHADER_FILES:
		_check_shader(file)
	_check_shaders_are_wired()
	if _failures == 0:
		print("test_shaders: PASS (%d checks over %d shaders)" % [_checks, SHADER_FILES.size()])
	else:
		printerr("test_shaders: FAIL (%d of %d checks)" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


## A shader that compiles is not a shader that ships. Three of these were once
## loaded by nothing but this test, so walk the ship source and demand a
## reference to each one from something that actually runs.
func _check_shaders_are_wired() -> void:
	var sources: String = _ship_source()
	_expect(sources.length() > 0, "ship source is readable")
	for file: String in SHADER_FILES:
		_expect(sources.contains(file), "%s is referenced by ship code" % file)


func _ship_source() -> String:
	var joined: String = ""
	for path: String in _gd_files("res://src"):
		var handle: FileAccess = FileAccess.open(path, FileAccess.READ)
		if handle == null:
			continue
		joined += handle.get_as_text()
		handle.close()
	return joined


func _gd_files(root: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			if dir.current_is_dir():
				for nested: String in _gd_files(root.path_join(entry)):
					found.append(nested)
			elif entry.ends_with(".gd"):
				found.append(root.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	return found


func _check_shader(file: String) -> void:
	var path: String = SHADER_DIR.path_join(file)
	_expect(ResourceLoader.exists(path), "%s exists at %s" % [file, path])
	if not ResourceLoader.exists(path):
		return

	var resource: Resource = load(path)
	var shader: Shader = resource as Shader
	_expect(shader != null, "%s loads as a Shader" % file)
	if shader == null:
		return

	var code: String = shader.get_code()
	_expect(code.contains("shader_type canvas_item;"),
			"%s declares shader_type canvas_item;" % file)

	# Build name -> type from the compiler's own table; this call also forces
	# the shader to compile, so a bad built-in shows up as SHADER ERROR here.
	var available: Dictionary = {}
	for entry: Dictionary in shader.get_shader_uniform_list():
		var uniform_name: String = String(entry.get("name", ""))
		var uniform_type: int = int(entry.get("type", TYPE_NIL))
		available[uniform_name] = uniform_type

	var required: Array = REQUIRED_UNIFORMS[file] as Array
	for uniform_name: String in required:
		var present: bool = available.has(uniform_name)
		_expect(present, "%s exposes uniform '%s'" % [file, uniform_name])
		if not present:
			continue
		var expected_type: int = int(UNIFORM_TYPES.get(uniform_name, TYPE_NIL))
		var actual_type: int = int(available[uniform_name])
		_expect(actual_type == expected_type,
				"%s uniform '%s' is type %d (got %d)" % [file, uniform_name, expected_type, actual_type])


func _expect(condition: bool, what: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("  FAILED: ", what)
	else:
		print("  ok: ", what)
