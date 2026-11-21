class_name LightSolver
extends RefCounted

## Deterministic four-pass light solver: sun shadows, beams, lanterns, wishes.
## Pure and static — the same code runs in gameplay and in the headless BFS.

class BeamSegment extends RefCounted:
  var from: Vector2i = Vector2i.ZERO
  var to: Vector2i = Vector2i.ZERO
  var wavelength: int = GridTypes.LightType.BEAM_AMBER

  func _init(p_from: Vector2i, p_to: Vector2i, p_wavelength: int) -> void:
    from = p_from
    to = p_to
    wavelength = p_wavelength


class SolveResult extends RefCounted:
  var light: PackedInt32Array = PackedInt32Array()
  var wish_states: Dictionary[String, bool] = {}
  var satisfied_count: int = 0
  var total_wishes: int = 0
  var warmth_factor: float = 0.0
  var solved: bool = false
  var beams: Array[BeamSegment] = []
  var next_lantern_charge: Dictionary[String, int] = {}
  var lit_by_beam: Dictionary[String, bool] = {}
  var glowing_lanterns: Dictionary[String, bool] = {}
  var width: int = 0
  var height: int = 0

  func light_at(x: int, y: int) -> int:
    if x < 0 or y < 0 or x >= width or y >= height:
      return GridTypes.LightType.NONE
    var idx: int = y * width + x
    if idx < 0 or idx >= light.size():
      return GridTypes.LightType.NONE
    return light[idx]


class _Ray extends RefCounted:
  var origin: Vector2i = Vector2i.ZERO
  var dir: Vector2i = Vector2i.ZERO
  var wavelength: int = GridTypes.LightType.BEAM_AMBER
  var bounces: int = 0
  var max_steps: int = GridTypes.MAX_RAY_STEPS

  func _init(p_origin: Vector2i, p_dir: Vector2i, p_wavelength: int, p_bounces: int, p_max_steps: int) -> void:
    origin = p_origin
    dir = p_dir
    wavelength = p_wavelength
    bounces = p_bounces
    max_steps = p_max_steps


static func solve(level: LevelData, state: SimState, collect_beams: bool = true) -> SolveResult:
  var result := SolveResult.new()
  if level == null or state == null:
    return result
  var w: int = level.width
  var h: int = level.height
  result.width = w
  result.height = h
  if w <= 0 or h <= 0:
    return result
  var light := PackedInt32Array()
  light.resize(w * h)
  light.fill(GridTypes.LightType.NONE)

  _pass_sun(level, state, light)
  _pass_beams(level, state, light, result, collect_beams)
  _pass_lanterns(level, state, light, result)
  _pass_wishes(level, state, light, result)

  result.light = light
  return result


static func _pass_sun(level: LevelData, state: SimState, light: PackedInt32Array) -> void:
  var w: int = level.width
  var h: int = level.height
  var sun: Vector2i = GridTypes.sun_dir(state.sun_angle)
  var reach: int = maxi(w, h)
  for y: int in h:
    for x: int in w:
      var idx: int = y * w + x
      if level.blocks_light_at(x, y, state):
        light[idx] = GridTypes.LightType.NONE
        continue
      var elevation: int = level.height_at(x, y)
      var shaded: bool = false
      var qx: int = x - sun.x
      var qy: int = y - sun.y
      var steps: int = 0
      while steps < reach:
        if not level.in_bounds(qx, qy):
          break
        if level.height_at(qx, qy) > elevation and level.blocks_light_at(qx, qy, state):
          shaded = true
          break
        qx -= sun.x
        qy -= sun.y
        steps += 1
      light[idx] = GridTypes.LightType.NONE if shaded else GridTypes.LightType.DIRECT_SUN


static func _pass_beams(level: LevelData, state: SimState, light: PackedInt32Array, result: SolveResult, collect: bool) -> void:
  var w: int = level.width
  var sun: Vector2i = GridTypes.sun_dir(state.sun_angle)
  var queue: Array[_Ray] = []
  var visited: Dictionary[String, bool] = {}

  for prop: LevelData.PropSpec in level.props:
    if prop.type != GridTypes.PropType.MIRROR:
      continue
    if light[prop.y * w + prop.x] != GridTypes.LightType.DIRECT_SUN:
      continue
    var outgoing: Vector2i = GridTypes.mirror_reflect(level.prop_state(prop, state), sun)
    if outgoing != sun:
      queue.append(_Ray.new(Vector2i(prop.x, prop.y), outgoing, GridTypes.LightType.BEAM_AMBER, 1, GridTypes.MAX_RAY_STEPS))

  # Golden-hour puddles toss a short shimmer beam; only the odd (diagonal) angles.
  if posmod(state.sun_angle, 8) % 2 == 1:
    for y: int in level.height:
      for x: int in level.width:
        var tile: LevelData.TileSpec = level.tile_at(x, y)
        if tile == null:
          continue
        if tile.type != GridTypes.TileType.PUDDLE and tile.type != GridTypes.TileType.WATER:
          continue
        if light[y * w + x] != GridTypes.LightType.DIRECT_SUN:
          continue
        queue.append(_Ray.new(Vector2i(x, y), sun, GridTypes.LightType.BEAM_AMBER, 0, 2))

  var head: int = 0
  while head < queue.size():
    var ray: _Ray = queue[head]
    head += 1
    _trace(level, state, light, result, ray, queue, visited, collect)


static func _trace(level: LevelData, state: SimState, light: PackedInt32Array, result: SolveResult, ray: _Ray, queue: Array[_Ray], visited: Dictionary[String, bool], collect: bool) -> void:
  var w: int = level.width
  var dir: Vector2i = ray.dir
  var wavelength: int = ray.wavelength
  var bounces: int = ray.bounces
  var pos: Vector2i = ray.origin
  var seg_start: Vector2i = ray.origin
  var seg_end: Vector2i = ray.origin
  var seg_dir: Vector2i = Vector2i.ZERO
  var seg_wavelength: int = GridTypes.LightType.NONE
  var seg_open: bool = false
  var steps: int = 0

  while steps < ray.max_steps:
    steps += 1
    pos += dir
    if not level.in_bounds(pos.x, pos.y):
      break
    if level.blocks_light_at(pos.x, pos.y, state):
      break
    var guard: String = "%d,%d,%d,%d,%d" % [pos.x, pos.y, dir.x, dir.y, wavelength]
    if visited.has(guard):
      break
    visited[guard] = true

    var idx: int = pos.y * w + pos.x
    if light[idx] < wavelength:
      light[idx] = wavelength

    if seg_open and dir == seg_dir and wavelength == seg_wavelength:
      seg_end = pos
    else:
      if seg_open:
        _push_segment(result, collect, seg_start, seg_end, seg_wavelength)
      seg_start = pos
      seg_end = pos
      seg_open = true
    seg_dir = dir
    seg_wavelength = wavelength

    var prop: LevelData.PropSpec = level.prop_at(pos.x, pos.y)
    if prop == null:
      continue

    match prop.type:
      GridTypes.PropType.MIRROR:
        var reflected: Vector2i = GridTypes.mirror_reflect(level.prop_state(prop, state), dir)
        if reflected != dir:
          bounces += 1
          if bounces > GridTypes.MAX_BOUNCES:
            break
          dir = reflected
      GridTypes.PropType.PRISM:
        var next_bounces: int = bounces + 1
        if next_bounces <= GridTypes.MAX_BOUNCES:
          queue.append(_Ray.new(pos, GridTypes.rotate90(dir, true), wavelength, next_bounces, GridTypes.MAX_RAY_STEPS))
          queue.append(_Ray.new(pos, GridTypes.rotate90(dir, false), wavelength, next_bounces, GridTypes.MAX_RAY_STEPS))
        break
      GridTypes.PropType.STAINED_GLASS:
        wavelength = GridTypes.LightType.BEAM_ROSE
      GridTypes.PropType.LANTERN:
        result.lit_by_beam[prop.id] = true
      _:
        pass

  if seg_open:
    _push_segment(result, collect, seg_start, seg_end, seg_wavelength)


static func _push_segment(result: SolveResult, collect: bool, from_cell: Vector2i, to_cell: Vector2i, wavelength: int) -> void:
  if not collect:
    return
  result.beams.append(BeamSegment.new(from_cell, to_cell, wavelength))


static func _pass_lanterns(level: LevelData, state: SimState, light: PackedInt32Array, result: SolveResult) -> void:
  var w: int = level.width
  var h: int = level.height
  var radius: int = GridTypes.LANTERN_RADIUS / 2
  for prop: LevelData.PropSpec in level.props:
    if prop.type != GridTypes.PropType.LANTERN:
      continue
    var lit_now: bool = light[prop.y * w + prop.x] == GridTypes.LightType.DIRECT_SUN
    if result.lit_by_beam.get(prop.id, false):
      lit_now = true
    var previous: int = state.lantern_charge.get(prop.id, 0)
    result.next_lantern_charge[prop.id] = 1 if lit_now else 0
    var glows: bool = lit_now or previous == 1
    result.glowing_lanterns[prop.id] = glows
    if not glows:
      continue
    for dy: int in range(-radius, radius + 1):
      for dx: int in range(-radius, radius + 1):
        var px: int = prop.x + dx
        var py: int = prop.y + dy
        if not level.in_bounds(px, py):
          continue
        var tile: LevelData.TileSpec = level.tile_at(px, py)
        if tile.type == GridTypes.TileType.VOID:
          continue
        light[py * w + px] = GridTypes.LightType.LANTERN_GLOW


static func _pass_wishes(level: LevelData, state: SimState, light: PackedInt32Array, result: SolveResult) -> void:
  var w: int = level.width
  var h: int = level.height
  result.total_wishes = level.wishes.size()
  for wish: LevelData.WishSpec in level.wishes:
    var here: int = _light_at(light, w, h, wish.x, wish.y)
    var met: bool = false
    match wish.need:
      GridTypes.WishType.WARM_SUN:
        met = here == GridTypes.LightType.DIRECT_SUN or here == GridTypes.LightType.BEAM_AMBER or here == GridTypes.LightType.BEAM_ROSE or here == GridTypes.LightType.LANTERN_GLOW
      GridTypes.WishType.SOFT_SHADE:
        met = here == GridTypes.LightType.NONE and not level.blocks_light_at(wish.x, wish.y, state)
      GridTypes.WishType.SHARED_BEAM:
        met = _is_beam(here) and wish.targets.size() > 0 and _is_beam(_light_at(light, w, h, wish.targets[0].x, wish.targets[0].y))
      GridTypes.WishType.ROSE_LIGHT:
        met = here == GridTypes.LightType.BEAM_ROSE
      GridTypes.WishType.LANTERN_GLOW:
        met = here == GridTypes.LightType.LANTERN_GLOW
    result.wish_states[wish.id] = met
    if met:
      result.satisfied_count += 1
  if result.total_wishes == 0:
    result.warmth_factor = 0.0
  else:
    result.warmth_factor = float(result.satisfied_count) / float(result.total_wishes)
  result.solved = result.satisfied_count == result.total_wishes


static func _is_beam(light_type: int) -> bool:
  return light_type == GridTypes.LightType.BEAM_AMBER or light_type == GridTypes.LightType.BEAM_ROSE


static func _light_at(light: PackedInt32Array, w: int, h: int, x: int, y: int) -> int:
  if x < 0 or y < 0 or x >= w or y >= h:
    return GridTypes.LightType.NONE
  return light[y * w + x]
