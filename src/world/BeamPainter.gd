class_name BeamPainter
extends Node2D

## Additive light shafts. Each solver beam segment becomes one quad carrying the
## volumetric shader, so the shaft's slats and dust motes stay locked to the
## 480x270 lattice instead of smearing along a plain line.

const CELL: int = 16
const SHADER_PATH: String = "res://src/shaders/sunbeam_volumetric.gdshader"
const AMBER: Color = Color(1.0, 0.83, 0.5)
const ROSE: Color = Color(1.0, 0.66, 0.72)
const BEAM_WIDTH: float = 7.0

var _result: LightSolver.SolveResult
var _shader: Shader
var _pool: Array[MeshInstance2D] = []


func _ready() -> void:
  _shader = load(SHADER_PATH) as Shader


func paint(solve: LightSolver.SolveResult) -> void:
  _result = solve
  _rebuild()


func _rebuild() -> void:
  if _shader == null:
    return
  if _result == null:
    _hide_from(0)
    return
  var beams: Array[LightSolver.BeamSegment] = _result.beams
  for i: int in beams.size():
    _place(_quad(i), beams[i])
  _hide_from(beams.size())


func _hide_from(first: int) -> void:
  for i: int in range(first, _pool.size()):
    _pool[i].visible = false


func _quad(index: int) -> MeshInstance2D:
  while _pool.size() <= index:
    var quad: MeshInstance2D = MeshInstance2D.new()
    quad.name = "Beam%d" % _pool.size()
    var mat: ShaderMaterial = ShaderMaterial.new()
    mat.shader = _shader
    quad.material = mat
    add_child(quad)
    _pool.append(quad)
  return _pool[index]


func _place(quad: MeshInstance2D, segment: LightSolver.BeamSegment) -> void:
  var from: Vector2 = _centre(segment.from)
  var to: Vector2 = _centre(segment.to)
  var axis: Vector2 = (to - from).normalized()
  if axis == Vector2.ZERO:
    axis = Vector2.RIGHT
  var side: Vector2 = Vector2(-axis.y, axis.x) * (BEAM_WIDTH * 0.5)
  # A mesh, not a Polygon2D: Polygon2D discards its uv array, which flattens the
  # shaft's cross-section and fades the whole quad out.
  var arrays: Array = []
  arrays.resize(Mesh.ARRAY_MAX)
  arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
    Vector3(from.x - side.x, from.y - side.y, 0.0),
    Vector3(from.x + side.x, from.y + side.y, 0.0),
    Vector3(to.x + side.x, to.y + side.y, 0.0),
    Vector3(to.x - side.x, to.y - side.y, 0.0),
  ])
  arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
    Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
  ])
  arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
  var mesh: ArrayMesh = ArrayMesh.new()
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
  quad.mesh = mesh
  quad.visible = true
  var mat: ShaderMaterial = quad.material as ShaderMaterial
  if mat != null:
    mat.set_shader_parameter("beam_color", ROSE if segment.wavelength == GridTypes.LightType.BEAM_ROSE else AMBER)


func _centre(cell: Vector2i) -> Vector2:
  return Vector2(cell.x * CELL + CELL / 2, cell.y * CELL + CELL / 2)
