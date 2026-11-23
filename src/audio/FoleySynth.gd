class_name FoleySynth
extends RefCounted
## Procedural sound effects.
##
## Every cue is synthesised once into 16-bit mono PCM at 44.1 kHz and pooled in
## an [AudioStreamRandomizer] so repeated interactions never sound mechanical.
## Pure static synthesis: no nodes, no scene access, no committed binaries.
## Rendering is seeded from the cue name plus the variation index, so two runs
## of [method build_all] produce byte-identical buffers.

const SAMPLE_RATE: int = 44100
const INV_SAMPLE_RATE: float = 1.0 / 44100.0
const FADE_IN_SECONDS: float = 0.0015
const FADE_OUT_SECONDS: float = 0.012
## AudioStreamRandomizer.random_pitch is a symmetric multiplier >= 1.0,
## so 1.06 plays each take somewhere in 0.94x..1.06x.
const PITCH_JITTER: float = 1.06
const VOLUME_JITTER_DB: float = 1.0

const CUE_NAMES: Array[String] = [
	"footstep_stone",
	"footstep_wood",
	"mirror_click",
	"awning_slide",
	"prism_chime",
	"cat_purr",
	"postcard_stamp",
	"lantern_charge",
	"sun_shift",
	"wish_satisfied",
	"level_solved",
	"ui_hover",
	"ui_select",
	"undo",
]
## Long cues ship three takes instead of four to keep boot synthesis short.
const CUE_VARIATION_COUNT: Dictionary = {
	"prism_chime": 3,
	"cat_purr": 3,
	"lantern_charge": 3,
	"level_solved": 3,
}
const DEFAULT_VARIATION_COUNT: int = 4

static var _cache: Dictionary = {}


static func cue_names() -> PackedStringArray:
	return PackedStringArray(CUE_NAMES)


static func build(cue: String) -> AudioStreamRandomizer:
	if _cache.has(cue):
		return _cache[cue] as AudioStreamRandomizer
	if not CUE_NAMES.has(cue):
		push_error("FoleySynth: unknown cue '%s'" % cue)
		return null
	var randomizer: AudioStreamRandomizer = AudioStreamRandomizer.new()
	randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	randomizer.random_pitch = PITCH_JITTER
	randomizer.random_volume_offset_db = VOLUME_JITTER_DB
	var count: int = variation_count(cue)
	for index: int in count:
		randomizer.add_stream(index, _render_variation(cue, index), 1.0)
	_cache[cue] = randomizer
	return randomizer


static func build_all() -> Dictionary:
	var bank: Dictionary = {}
	for cue: String in CUE_NAMES:
		bank[cue] = build(cue)
	return bank


static func variation_count(cue: String) -> int:
	if CUE_VARIATION_COUNT.has(cue):
		return CUE_VARIATION_COUNT[cue] as int
	return DEFAULT_VARIATION_COUNT


static func _render_variation(cue: String, index: int) -> AudioStreamWAV:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed_for(cue, index)
	var buf: PackedFloat32Array = PackedFloat32Array()
	match cue:
		"footstep_stone":
			buf = _footstep(rng, false)
		"footstep_wood":
			buf = _footstep(rng, true)
		"mirror_click":
			buf = _mirror_click(rng)
		"awning_slide":
			buf = _awning_slide(rng)
		"prism_chime":
			buf = _prism_chime(rng)
		"cat_purr":
			buf = _cat_purr(rng)
		"postcard_stamp":
			buf = _postcard_stamp(rng)
		"lantern_charge":
			buf = _lantern_charge(rng)
		"sun_shift":
			buf = _sun_shift(rng)
		"wish_satisfied":
			buf = _wish_satisfied(rng)
		"level_solved":
			buf = _level_solved(rng)
		"ui_hover":
			buf = _ui_hover(rng)
		"ui_select":
			buf = _ui_select(rng)
		"undo":
			buf = _undo(rng)
		_:
			return null
	return _to_wav(buf, _target_peak(cue))


static func _seed_for(cue: String, index: int) -> int:
	var base: int = int(hash(cue)) & 0x7FFFFFFF
	return (base * 1103515245 + index * 12345 + 987654321) & 0x7FFFFFFF


static func _target_peak(cue: String) -> float:
	match cue:
		"ui_hover":
			return 0.36
		"ui_select", "undo":
			return 0.50
		"cat_purr", "sun_shift":
			return 0.55
		"awning_slide", "prism_chime", "lantern_charge", "wish_satisfied", "level_solved":
			return 0.62
		"mirror_click", "postcard_stamp", "footstep_stone", "footstep_wood":
			return 0.74
		_:
			return 0.70


static func _footstep(rng: RandomNumberGenerator, wood: bool) -> PackedFloat32Array:
	var dur: float = rng.randf_range(0.15, 0.17)
	var buf: PackedFloat32Array = _buffer(dur)
	var count: int = buf.size()
	var noise: PackedFloat32Array = _noise_buffer(rng, count)
	var centre: float = rng.randf_range(2650.0, 3200.0) if wood else rng.randf_range(1450.0, 1900.0)
	_svf_bandpass(noise, centre, 1.4)
	var click_step: float = _decay_step(rng.randf_range(0.020, 0.026) if wood else rng.randf_range(0.028, 0.034))
	var body_f: float = rng.randf_range(198.0, 224.0) if wood else rng.randf_range(96.0, 116.0)
	var body_step: float = _decay_step(rng.randf_range(0.030, 0.038) if wood else rng.randf_range(0.042, 0.052))
	var bend: float = rng.randf_range(0.22, 0.34)
	var partial: float = 2.31 if wood else 2.0
	var partial_gain: float = 0.26 if wood else 0.16
	var click_gain: float = 1.55 if wood else 1.85
	var body_gain: float = 0.48
	var grit: PackedFloat32Array = _noise_buffer(rng, count)
	_onepole_highpass(grit, rng.randf_range(3600.0, 4800.0))
	var grit_step: float = _decay_step(rng.randf_range(0.007, 0.010))
	var click_env: float = 0.0
	var body_env: float = 0.0
	var grit_env: float = 0.0
	var phase: float = 0.0
	for i: int in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		click_env = 1.0 if i == 0 else click_env * click_step
		body_env = 1.0 if i == 0 else body_env * body_step
		grit_env = 1.0 if i == 0 else grit_env * grit_step
		var attack: float = minf(t * 700.0, 1.0)
		var glide: float = 1.0 - bend * minf(t * 7.0, 1.0)
		phase += TAU * body_f * glide * INV_SAMPLE_RATE
		var body: float = sin(phase) * body_env * attack * body_gain
		var hollow: float = sin(phase * partial + 0.4) * body_env * body_env * attack * partial_gain
		var click: float = noise[i] * click_env * attack * click_gain
		var grit_amt: float = grit[i] * grit_env * attack * (0.45 if wood else 0.55)
		buf[i] = body + hollow + click + grit_amt
	return buf


static func _mirror_click(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 0.30
	var buf: PackedFloat32Array = _buffer(dur)
	var count: int = buf.size()
	var carrier: float = rng.randf_range(2200.0, 2600.0)
	var modulator: float = carrier * rng.randf_range(3.2, 3.6)
	var index_step: float = _decay_step(0.030)
	var ping_step: float = _decay_step(rng.randf_range(0.050, 0.062))
	var ring_step: float = _decay_step(0.032)
	var thud_step: float = _decay_step(rng.randf_range(0.045, 0.060))
	var noise: PackedFloat32Array = _noise_buffer(rng, count)
	_svf_bandpass(noise, rng.randf_range(380.0, 520.0), 0.9)
	var index: float = 3.6
	var ping_env: float = 0.0
	var ring_env: float = 0.0
	var thud_env: float = 0.0
	var ping_phase: float = 0.0
	var ring_phase: float = 0.0
	var thud_phase: float = 0.0
	var ping_inc: float = TAU * carrier * INV_SAMPLE_RATE
	var ring_inc: float = TAU * carrier * 1.47 * INV_SAMPLE_RATE
	var thud_inc: float = TAU * 132.0 * INV_SAMPLE_RATE
	for i: int in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		var attack: float = minf(t * 900.0, 1.0)
		index *= index_step
		ping_env = 1.0 if i == 0 else ping_env * ping_step
		ring_env = 1.0 if i == 0 else ring_env * ring_step
		thud_env = 1.0 if i == 0 else thud_env * thud_step
		ping_phase += ping_inc
		ring_phase += ring_inc
		thud_phase += thud_inc
		var ping: float = sin(ping_phase + index * sin(TAU * modulator * t)) * ping_env * attack * 0.62
		var ring: float = sin(ring_phase) * ring_env * attack * 0.24
		var thud: float = sin(thud_phase) * thud_env * attack * 0.42
		var damped: float = noise[i] * thud_env * attack * 0.40
		buf[i] = ping + ring + thud + damped
	return buf


static func _awning_slide(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = rng.randf_range(0.40, 0.46)
	var buf: PackedFloat32Array = _buffer(dur)
	var count: int = buf.size()
	var cloth: PackedFloat32Array = _noise_buffer(rng, count)
	_sweep_lowpass(cloth, rng.randf_range(260.0, 320.0), rng.randf_range(1300.0, 1700.0), rng.randf_range(420.0, 560.0))
	var air: PackedFloat32Array = _noise_buffer(rng, count)
	_svf_bandpass(air, rng.randf_range(2200.0, 2800.0), 0.7)
	var flutter: float = rng.randf_range(6.0, 8.5)
	var inv_count: float = 1.0 / float(count)
	for i: int in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		var u: float = float(i) * inv_count
		var env: float = pow(sin(PI * u), 1.3)
		var flap: float = 0.86 + 0.14 * sin(TAU * flutter * t + 0.7)
		buf[i] = (cloth[i] * 1.7 + air[i] * 0.30) * env * flap
	return buf


static func _prism_chime(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 0.95
	var buf: PackedFloat32Array = _buffer(dur)
	var count: int = buf.size()
	var base: float = rng.randf_range(1720.0, 1860.0)
	var detune: float = base * 1.0015
	var inc_a: float = TAU * base * INV_SAMPLE_RATE
	var inc_b: float = TAU * detune * INV_SAMPLE_RATE
	var inc_2: float = TAU * base * 2.01 * INV_SAMPLE_RATE
	var inc_3: float = TAU * base * 2.98 * INV_SAMPLE_RATE
	var inc_4: float = TAU * base * 4.20 * INV_SAMPLE_RATE
	var step_a: float = _decay_step(0.36)
	var step_2: float = _decay_step(0.26)
	var step_3: float = _decay_step(0.18)
	var step_4: float = _decay_step(0.12)
	var env_a: float = 0.0
	var env_2: float = 0.0
	var env_3: float = 0.0
	var env_4: float = 0.0
	var theta: float = 0.0
	var theta_b: float = 0.0
	var theta_2: float = 0.0
	var theta_3: float = 0.0
	var theta_4: float = 0.0
	for i: int in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		var attack: float = minf(t * 180.0, 1.0)
		env_a = 1.0 if i == 0 else env_a * step_a
		env_2 = 1.0 if i == 0 else env_2 * step_2
		env_3 = 1.0 if i == 0 else env_3 * step_3
		env_4 = 1.0 if i == 0 else env_4 * step_4
		theta += inc_a
		theta_b += inc_b
		theta_2 += inc_2
		theta_3 += inc_3
		theta_4 += inc_4
		var shimmer: float = 1.0 + 0.08 * sin(TAU * 6.5 * t)
		var body: float = (sin(theta) * 0.50 + sin(theta_b) * 0.18) * env_a
		var upper: float = sin(theta_2) * env_2 * 0.24 + sin(theta_3) * env_3 * 0.13 + sin(theta_4) * env_4 * 0.06
		buf[i] = (body + upper) * attack * shimmer
	return buf


static func _cat_purr(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 1.25
	var buf: PackedFloat32Array = _buffer(dur)
	var count: int = buf.size()
	var hum: float = rng.randf_range(74.0, 82.0)
	var rate: float = rng.randf_range(25.0, 27.5)
	var inc_1: float = TAU * hum * INV_SAMPLE_RATE
	var inc_2: float = TAU * hum * 1.5 * INV_SAMPLE_RATE
	var inc_3: float = TAU * hum * 2.0 * INV_SAMPLE_RATE
	var inc_4: float = TAU * hum * 3.0 * INV_SAMPLE_RATE
	var breach: PackedFloat32Array = _noise_buffer(rng, count)
	_onepole_lowpass(breach, 220.0)
	var inv_count: float = 1.0 / float(count)
	var ph_1: float = 0.0
	var ph_2: float = 0.0
	var ph_3: float = 0.0
	var ph_4: float = 0.0
	for i: int in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		var u: float = float(i) * inv_count
		var fade: float = minf(t * 12.0, 1.0) * minf((1.0 - u) * 6.0, 1.0)
		var am: float = 0.42 + 0.58 * pow(0.5 + 0.5 * sin(TAU * rate * t), 1.5)
		ph_1 += inc_1
		ph_2 += inc_2
		ph_3 += inc_3
		ph_4 += inc_4
		var carrier: float = sin(ph_1) * 0.50 + sin(ph_2) * 0.26 + sin(ph_3) * 0.14 + sin(ph_4) * 0.06
		buf[i] = (carrier * am + breach[i] * 0.09) * fade
	return buf


static func _postcard_stamp(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 0.38
	var buf: PackedFloat32Array = _buffer(dur)
	var count: int = buf.size()
	var thump_f: float = rng.randf_range(70.0, 84.0)
	var thump_step: float = _decay_step(rng.randf_range(0.045, 0.060))
	var skin: PackedFloat32Array = _noise_buffer(rng, count)
	_svf_bandpass(skin, rng.randf_range(180.0, 260.0), 0.8)
	var rustle: PackedFloat32Array = _noise_buffer(rng, count)
	_onepole_highpass(rustle, rng.randf_range(1600.0, 2200.0))
	var grain_rate: float = rng.randf_range(30.0, 42.0)
	var thump_env: float = 0.0
	var phase: float = 0.0
	for i: int in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		thump_env = 1.0 if i == 0 else thump_env * thump_step
		var attack: float = minf(t * 900.0, 1.0)
		var glide: float = 1.0 - 0.28 * minf(t * 9.0, 1.0)
		phase += TAU * thump_f * glide * INV_SAMPLE_RATE
		var thump: float = sin(phase) * thump_env * attack * 0.72
		var leather: float = skin[i] * thump_env * attack * 0.34
		var ru: float = clampf((t - 0.045) / 0.24, 0.0, 1.0)
		var rustle_env: float = pow(sin(PI * ru), 0.8) if ru > 0.0 and ru < 1.0 else 0.0
		var grain: float = pow(absf(sin(TAU * grain_rate * t + 2.1 * sin(TAU * 7.3 * t))), 3.0)
		var paper: float = rustle[i] * rustle_env * (0.22 + 0.78 * grain) * 0.52
		buf[i] = thump + leather + paper
	return buf


static func _lantern_charge(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 1.05
	var buf: PackedFloat32Array = _buffer(dur)
	var count: int = buf.size()
	var f_low: float = rng.randf_range(320.0, 360.0)
	var f_high: float = f_low * rng.randf_range(1.90, 2.15)
	var inv_count: float = 1.0 / float(count)
	var glide: float = pow(f_high / f_low, inv_count)
	var inc_1: float = TAU * f_low * INV_SAMPLE_RATE
	var inc_2: float = inc_1 * 2.0
	var inc_3: float = inc_1 * 3.0
	var inc_4: float = inc_1 * 4.02
	var swell: PackedFloat32Array = _noise_buffer(rng, count)
	var low_air: PackedFloat32Array = swell.duplicate()
	_onepole_lowpass(swell, 900.0)
	_onepole_highpass(low_air, 3000.0)
	var ph_1: float = 0.0
	var ph_2: float = 0.0
	var ph_3: float = 0.0
	var ph_4: float = 0.0
	var scale: float = 1.0
	for i: int in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		var u: float = float(i) * inv_count
		var env: float = pow(u, 1.6) * minf((1.0 - u) * 8.3, 1.0)
		var tremolo: float = 1.0 + 0.06 * sin(TAU * 9.0 * t)
		ph_1 += inc_1 * scale
		ph_2 += inc_2 * scale
		ph_3 += inc_3 * scale
		ph_4 += inc_4 * scale
		scale *= glide
		var glass: float = sin(ph_1) * 0.42 + sin(ph_2) * 0.22 + sin(ph_3) * 0.12 + sin(ph_4) * 0.06
		var air: float = swell[i] * (1.0 - u) * 0.35 + low_air[i] * u * 0.30
		buf[i] = (glass + air) * env * tremolo
	return buf


static func _sun_shift(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 0.35
	var buf: PackedFloat32Array = _buffer(dur)
	var count: int = buf.size()
	var air: PackedFloat32Array = _noise_buffer(rng, count)
	_sweep_lowpass(air, rng.randf_range(320.0, 420.0), rng.randf_range(2000.0, 2500.0), rng.randf_range(700.0, 900.0))
	var hiss: PackedFloat32Array = _noise_buffer(rng, count)
	_onepole_highpass(hiss, 3500.0)
	var start_f: float = rng.randf_range(210.0, 230.0)
	var end_f: float = start_f * rng.randf_range(1.45, 1.55)
	var inc: float = TAU * start_f * INV_SAMPLE_RATE
	var glide: float = pow(end_f / start_f, 1.0 / float(count))
	var inv_count: float = 1.0 / float(count)
	var phase: float = 0.0
	var scale: float = 1.0
	for i: int in count:
		var u: float = float(i) * inv_count
		var env: float = pow(sin(PI * u), 1.4)
		phase += inc * scale
		scale *= glide
		var tone: float = sin(phase) * 0.16
		var breath: float = air[i] * 2.0 + hiss[i] * 0.22
		buf[i] = (breath + tone) * env
	return buf


static func _wish_satisfied(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 0.65
	var buf: PackedFloat32Array = _buffer(dur)
	var root: float = rng.randf_range(519.0, 527.0)
	_add_bell(buf, 0.0, root, 0.55, 0.22, 1.0)
	_add_bell(buf, 0.155, root * 1.4983, 0.50, 0.26, 1.15)
	_add_bell(buf, 0.30, root * 2.0, 0.16, 0.20, 1.3)
	return buf


static func _level_solved(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 1.25
	var buf: PackedFloat32Array = _buffer(dur)
	var root: float = rng.randf_range(519.0, 525.0)
	_add_bell(buf, 0.00, root, 0.46, 0.30, 1.0)
	_add_bell(buf, 0.14, root * 1.2599, 0.42, 0.30, 1.05)
	_add_bell(buf, 0.28, root * 1.4983, 0.40, 0.32, 1.1)
	_add_bell(buf, 0.46, root * 2.2449, 0.44, 0.50, 1.35)
	_add_bell(buf, 0.62, root * 3.0, 0.10, 0.34, 1.4)
	return buf


static func _ui_hover(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 0.05
	var buf: PackedFloat32Array = _buffer(dur)
	var count: int = buf.size()
	var tick: PackedFloat32Array = _noise_buffer(rng, count)
	_onepole_highpass(tick, rng.randf_range(3600.0, 4400.0))
	var freq: float = rng.randf_range(2300.0, 2700.0)
	var step: float = _decay_step(0.008)
	var env: float = 0.0
	var phase: float = 0.0
	var inc: float = TAU * freq * INV_SAMPLE_RATE
	for i: int in count:
		env = 1.0 if i == 0 else env * step
		phase += inc
		buf[i] = (tick[i] * 0.75 + sin(phase) * 0.30) * env
	return buf


static func _ui_select(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 0.10
	var buf: PackedFloat32Array = _buffer(dur)
	var count: int = buf.size()
	var click: PackedFloat32Array = _noise_buffer(rng, count)
	_svf_bandpass(click, rng.randf_range(1100.0, 1400.0), 1.2)
	var freq: float = rng.randf_range(600.0, 660.0)
	var noise_step: float = _decay_step(0.011)
	var tone_step: float = _decay_step(0.026)
	var noise_env: float = 0.0
	var tone_env: float = 0.0
	var phase: float = 0.0
	var inc: float = TAU * freq * INV_SAMPLE_RATE
	for i: int in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		var attack: float = minf(t * 1200.0, 1.0)
		noise_env = 1.0 if i == 0 else noise_env * noise_step
		tone_env = 1.0 if i == 0 else tone_env * tone_step
		var glide: float = 1.0 - 0.22 * minf(t * 60.0, 1.0)
		phase += inc * glide
		buf[i] = click[i] * noise_env * attack * 0.55 + sin(phase) * tone_env * attack * 0.45
	return buf


static func _undo(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 0.20
	var buf: PackedFloat32Array = _buffer(dur)
	var count: int = buf.size()
	var tick: PackedFloat32Array = _noise_buffer(rng, count)
	_onepole_highpass(tick, rng.randf_range(2300.0, 2800.0))
	var freq: float = rng.randf_range(880.0, 960.0)
	var rise: float = _decay_step(0.075)
	var inv_count: float = 1.0 / float(count)
	var env: float = 0.0
	var phase: float = 0.0
	var inc: float = TAU * freq * INV_SAMPLE_RATE
	var glide: float = pow(0.45, inv_count)
	var scale: float = 1.0
	for i: int in count:
		var u: float = float(i) * inv_count
		env = 0.02 if i == 0 else env * rise
		var tail: float = 1.0 - pow(u, 6.0)
		phase += inc * scale
		scale *= glide
		var tone: float = sin(phase) * 0.55
		var tick_amt: float = tick[i] * 0.9 * tail
		buf[i] = (tone + tick_amt) * env * tail
	return buf


static func _add_bell(buf: PackedFloat32Array, start_sec: float, freq: float, amp: float,
		tau: float, brightness: float) -> void:
	var count: int = buf.size()
	var start: int = int(start_sec * float(SAMPLE_RATE))
	if start < 0 or start >= count:
		return
	var step: float = _decay_step(tau)
	var inc_1: float = TAU * freq * INV_SAMPLE_RATE
	var inc_2: float = inc_1 * 2.0
	var inc_3: float = inc_1 * 3.0
	var weight_2: float = 0.22 * brightness
	var weight_3: float = 0.07 * brightness
	var env: float = 0.0
	var ph_1: float = 0.0
	var ph_2: float = 0.0
	var ph_3: float = 0.0
	for i: int in range(start, count):
		var t: float = float(i - start) * INV_SAMPLE_RATE
		var attack: float = minf(t * 90.0, 1.0)
		env = 1.0 if i == start else env * step
		ph_1 += inc_1
		ph_2 += inc_2
		ph_3 += inc_3
		var sample: float = (sin(ph_1) + weight_2 * sin(ph_2) + weight_3 * sin(ph_3)) * env * attack * amp
		buf[i] += sample


static func _buffer(seconds: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(maxi(int(round(seconds * float(SAMPLE_RATE))), 8))
	return buf


static func _noise_buffer(rng: RandomNumberGenerator, count: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(count)
	for i: int in count:
		buf[i] = rng.randf_range(-1.0, 1.0)
	return buf


static func _decay_step(tau_seconds: float) -> float:
	return exp(-1.0 / (maxf(tau_seconds, 0.0001) * float(SAMPLE_RATE)))


static func _svf_bandpass(buf: PackedFloat32Array, freq: float, q: float) -> void:
	var f: float = 2.0 * sin(PI * clampf(freq * INV_SAMPLE_RATE, 0.0005, 0.45))
	var damp: float = clampf(1.0 / q, 0.2, 2.0)
	var low: float = 0.0
	var band: float = 0.0
	for i: int in buf.size():
		var high: float = buf[i] - low - damp * band
		band += f * high
		low += f * band
		buf[i] = band


static func _onepole_lowpass(buf: PackedFloat32Array, cutoff: float) -> void:
	var a: float = 1.0 - exp(-TAU * cutoff * INV_SAMPLE_RATE)
	var y: float = 0.0
	for i: int in buf.size():
		y += a * (buf[i] - y)
		buf[i] = y


static func _onepole_highpass(buf: PackedFloat32Array, cutoff: float) -> void:
	var a: float = 1.0 - exp(-TAU * cutoff * INV_SAMPLE_RATE)
	var y: float = 0.0
	for i: int in buf.size():
		y += a * (buf[i] - y)
		buf[i] = buf[i] - y


## Sweeps a one-pole low-pass down-up: c0 at the start, c1 at the midpoint, c2 at the end.
static func _sweep_lowpass(buf: PackedFloat32Array, c0: float, c1: float, c2: float) -> void:
	var count: int = buf.size()
	var inv_count: float = 1.0 / float(maxi(count, 1))
	var a: float = 0.0
	var y: float = 0.0
	for i: int in count:
		if (i & 15) == 0:
			var u: float = float(i) * inv_count
			var cutoff: float = lerpf(c0, c1, u * 2.0) if u < 0.5 else lerpf(c1, c2, (u - 0.5) * 2.0)
			a = 1.0 - exp(-TAU * cutoff * INV_SAMPLE_RATE)
		y += a * (buf[i] - y)
		buf[i] = y


static func _to_wav(buf: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	var count: int = buf.size()
	var total: float = 0.0
	for i: int in count:
		total += buf[i]
	var dc: float = total / float(maxi(count, 1))
	var loudest: float = 0.0
	for i: int in count:
		buf[i] -= dc
		loudest = maxf(loudest, absf(buf[i]))
	var gain: float = peak / loudest if loudest > 0.000001 else 0.0
	var fade_in: int = mini(int(FADE_IN_SECONDS * float(SAMPLE_RATE)), count / 4)
	var fade_out: int = mini(int(FADE_OUT_SECONDS * float(SAMPLE_RATE)), count / 4)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	for i: int in count:
		var envelope: float = gain
		if i < fade_in:
			envelope *= float(i) / float(fade_in)
		elif i >= count - fade_out:
			envelope *= float(count - 1 - i) / float(fade_out)
		var value: int = roundi(clampf(buf[i] * envelope, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, value)
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = bytes
	return wav
