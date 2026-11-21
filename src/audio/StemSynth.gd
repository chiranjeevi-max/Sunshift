class_name StemSynth
extends RefCounted
## Sample-locked five-stem adaptive soundtrack for Sunshift, baked per district.
##
## All stems share a mix rate and frame count to keep their loops in sync.
## At 22050 Hz, each district uses less memory and still covers the score's
## upper frequencies.
##
## Deterministic: one fixed seed per (district, stem), no wall clock, no
## Dictionary iteration in anything that shapes a sample.

const STEM_COUNT: int = 5
const DISTRICT_COUNT: int = 4
const VERBOSE: bool = false

const SAMPLE_RATE: int = 22050
const BPM: float = 72.0
const BEATS_PER_BAR: int = 4
const BAR_COUNT: int = 16

## 60 / 72 s per beat × 22050 Hz = 18375 samples exactly, so every bar boundary
## lands on an integer frame and the 16-bar loop is exactly 1176000 frames.
const SAMPLES_PER_BEAT: int = 18375
const SAMPLES_PER_BAR: int = SAMPLES_PER_BEAT * BEATS_PER_BAR
const FRAMES: int = SAMPLES_PER_BAR * BAR_COUNT

const SIN_SIZE: int = 2048
const SIN_MASK: int = SIN_SIZE - 1
const SEAM: int = 256

## Fmaj7 · G6 · Em7 · Am9, one bar each, cycling four times across the 16 bars.
## Top voice walks E4-E4-D4-G4 and bar 16 adds the 9th (B4) to fall back into
## Fmaj7's C on the downbeat, so the loop point is a real cadence.
const CHOLD: Array = [
	[53, 57, 60, 64],
	[55, 59, 62, 64],
	[52, 55, 59, 62],
	[57, 60, 64, 67],
]
const CHORD_ROOTS: Array = [53, 55, 52, 57]
const PEAK_TARGETS: Array = [0.30, 0.62, 0.42, 0.50, 0.55]

static var _cache: Dictionary = {}
static var _felt_tab: PackedFloat32Array = PackedFloat32Array()


## Five stems for one act, cached. Districts 0-3 map to Acts I-IV.
static func build(district: int) -> Array[AudioStreamWAV]:
	var d: int = clampi(district, 0, DISTRICT_COUNT - 1)
	var cached: Variant = _cache.get(d)
	if cached != null:
		return cached as Array[AudioStreamWAV]
	var t0: int = Time.get_ticks_usec()
	var stems: Array[AudioStreamWAV] = []
	for stem in STEM_COUNT:
		stems.append(_bake(d, stem))
	_cache[d] = stems
	if VERBOSE:
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		print("StemSynth: district %d baked in %.1f ms" % [d, ms])
	return stems


## Every district's five stems, index = district.
static func build_all() -> Array:
	var t0: int = Time.get_ticks_usec()
	var all_stems: Array = []
	for d in DISTRICT_COUNT:
		all_stems.append(build(d))
	if VERBOSE:
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		print("StemSynth: all %d districts baked in %.1f ms" % [DISTRICT_COUNT, ms])
	return all_stems


## Mix rate of one stem. Uniform by design — see the class comment.
static func stem_sample_rate(stem: int) -> int:
	if stem < 0 or stem >= STEM_COUNT:
		push_error("StemSynth: stem %d out of range" % stem)
	return SAMPLE_RATE


static func _bake(district: int, stem: int) -> AudioStreamWAV:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(FRAMES)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed_for(district, stem)
	var t0: int = Time.get_ticks_usec()
	match stem:
		0:
			_ambience(buf, district, rng)
		1:
			_felt_piano(buf, rng)
		2:
			_kalimba(buf, rng)
		3:
			_pad(buf)
		_:
			_chime(buf, rng)
	_seal(buf)
	var t1: int = Time.get_ticks_usec()
	var wav: AudioStreamWAV = _to_wav(buf, float(PEAK_TARGETS[stem]))
	if VERBOSE:
		var t2: int = Time.get_ticks_usec()
		print("  stem %d: render %.1f ms + encode %.1f ms" % [stem, float(t1 - t0) / 1000.0, float(t2 - t1) / 1000.0])
	return wav


static func _seed_for(district: int, stem: int) -> int:
	return 0x5A17C0DE + district * 7919 + stem * 104729


# --- stem 0: district ambience ------------------------------------------------

static func _ambience(buf: PackedFloat32Array, district: int, rng: RandomNumberGenerator) -> void:
	# Paul Kellet's three-pole pink approximation over a one-pole low-pass: a
	# breathy coastal bed rather than white hiss. Baked at 11 kHz and
	# interpolated: the bed has nothing above ~600 Hz to lose.
	var half: int = FRAMES / 2
	var low: PackedFloat32Array = PackedFloat32Array()
	low.resize(half)
	var b0: float = 0.0
	var b1: float = 0.0
	var lp: float = 0.0
	var breath: float = 0.70
	var period: float = float(half / 4)
	# A multiply-with-carry LCG: two ops per frame instead of an RNG call, still
	# seeded from the district's generator so the bed stays reproducible.
	var state: int = rng.randi() | 1
	for i in half:
		state = state * 1103515245 + 12345
		var w: float = float((state >> 16) & 0x7FFF) * 0.0000610 - 1.0
		b0 = 0.99765 * b0 + w * 0.0990460
		b1 = 0.96300 * b1 + w * 0.2965164
		lp += ((b0 + b1 + w * 0.1848) * 0.22 - lp) * 0.16
		if (i & 127) == 0:
			breath += (0.70 + 0.30 * sin(TAU * float(i) / period) - breath) * 0.0025
		low[i] = lp * breath
	var prev: float = low[half - 1]
	for k in half:
		var v: float = low[k]
		buf[k * 2] = v * 0.72 + prev * 0.28
		buf[k * 2 + 1] = v
		prev = v
	match district:
		0:
			_amb_coast(buf, rng)
		1:
			_amb_rain(buf, rng)
		2:
			_amb_canal(buf, rng)
		_:
			_amb_dusk(buf, rng)


static func _amb_coast(buf: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	for k in 3:
		var at: float = rng.randf_range(4.0 + float(k) * 17.0, 13.0 + float(k) * 17.0)
		_seagull(buf, int(at * float(SAMPLE_RATE)), rng.randf_range(0.92, 1.12), rng.randf_range(0.05, 0.09))
	_stairs(buf, int(rng.randf_range(17.0, 21.0) * float(SAMPLE_RATE)), rng)
	_stairs(buf, int(rng.randf_range(43.0, 48.0) * float(SAMPLE_RATE)), rng)


static func _seagull(buf: PackedFloat32Array, start: int, pitch: float, gain: float) -> void:
	# Two falling "kee-ow" syllables with a rasp of noise on the glide.
	var n: int = int(1.1 * float(SAMPLE_RATE))
	var ph: float = 0.0
	var amp: float = 0.0
	for k in n:
		var t: float = float(k) / float(SAMPLE_RATE)
		var syl: float = 1.0 if (t < 0.28 or (t > 0.46 and t < 0.92)) else 0.0
		var glide: float = 1.0 - 0.42 * fmod(t, 0.46) / 0.46
		var f: float = 1180.0 * pitch * glide
		ph += f / float(SAMPLE_RATE)
		if ph >= 1.0:
			ph -= 1.0
		var env: float = sin(PI * fmod(t, 0.46) / 0.46)
		amp = env * syl
		var v: float = (sin(TAU * ph) + 0.35 * sin(TAU * ph * 2.0)) * amp * gain
		_add(buf, start + k, v)


static func _stairs(buf: PackedFloat32Array, start: int, rng: RandomNumberGenerator) -> void:
	var steps: int = 5
	var at: int = 0
	for s in steps:
		var thud: float = rng.randf_range(0.7, 1.0) * 0.055
		var n: int = int(0.16 * float(SAMPLE_RATE))
		var ph: float = 0.0
		var lp: float = 0.0
		for k in n:
			var t: float = float(k) / float(SAMPLE_RATE)
			ph += (78.0 + 26.0 * float(s)) / float(SAMPLE_RATE)
			if ph >= 1.0:
				ph -= 1.0
			var noise: float = rng.randf() * 2.0 - 1.0
			lp += (noise - lp) * 0.22
			var env: float = exp(-t / 0.045)
			var v: float = (sin(TAU * ph) * 0.8 + lp) * env * thud
			_add(buf, start + at + k, v)
		at += int(rng.randf_range(0.34, 0.52) * float(SAMPLE_RATE))


static func _amb_rain(buf: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	for k in 14:
		var at: float = rng.randf_range(0.5, 52.0)
		_drip(buf, int(at * float(SAMPLE_RATE)), rng.randf_range(0.05, 0.12), rng.randf_range(760.0, 1650.0))
	# A gutter still trickling under the veranda.
	var n: int = int(3.2 * float(SAMPLE_RATE))
	var start: int = int(rng.randf_range(24.0, 30.0) * float(SAMPLE_RATE))
	var lp: float = 0.0
	for k in n:
		var noise: float = rng.randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.05
		var env: float = sin(PI * float(k) / float(n))
		_add(buf, start + k, lp * env * 0.05)


static func _drip(buf: PackedFloat32Array, start: int, gain: float, hz: float) -> void:
	var n: int = int(0.09 * float(SAMPLE_RATE))
	var ph: float = 0.0
	for k in n:
		var t: float = float(k) / float(SAMPLE_RATE)
		ph += (hz * (1.0 + 1.5 * t / 0.09)) / float(SAMPLE_RATE)
		if ph >= 1.0:
			ph -= 1.0
		var env: float = exp(-t / 0.014)
		_add(buf, start + k, sin(TAU * ph) * env * gain)


static func _amb_canal(buf: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	for k in 11:
		var at: float = rng.randf_range(0.5, 52.0)
		_lap(buf, int(at * float(SAMPLE_RATE)), rng.randf_range(0.05, 0.10), rng.randf_range(0.7, 1.3), rng)


static func _lap(buf: PackedFloat32Array, start: int, gain: float, rate: float, rng: RandomNumberGenerator) -> void:
	var n: int = int(1.4 * float(SAMPLE_RATE))
	var lp: float = 0.0
	var ph: float = 0.0
	for k in n:
		var t: float = float(k) / float(SAMPLE_RATE)
		var noise: float = rng.randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.045
		ph += 190.0 * rate / float(SAMPLE_RATE)
		if ph >= 1.0:
			ph -= 1.0
		var env: float = sin(PI * t / 1.4)
		var v: float = (lp * 4.0 + sin(TAU * ph) * 0.25) * env * env * gain
		_add(buf, start + k, v)


static func _amb_dusk(buf: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	_tram_bell(buf, int(rng.randf_range(9.0, 13.0) * float(SAMPLE_RATE)), rng.randf_range(0.7, 0.9))
	_tram_bell(buf, int(rng.randf_range(33.0, 39.0) * float(SAMPLE_RATE)), rng.randf_range(0.5, 0.8))
	for k in 3:
		var at: float = 6.0 + float(k) * 15.0 + rng.randf_range(0.0, 4.0)
		_cricket(buf, int(at * float(SAMPLE_RATE)), rng.randf_range(0.3, 0.5), rng)


static func _tram_bell(buf: PackedFloat32Array, start: int, gain: float) -> void:
	var partials: Array = [1.0, 2.03, 2.76, 4.07, 5.41]
	var amps: Array = [1.0, 0.55, 0.38, 0.20, 0.12]
	var n: int = int(2.6 * float(SAMPLE_RATE))
	for p in partials.size():
		var inc: float = 612.0 * float(partials[p]) / float(SAMPLE_RATE)
		var amp: float = float(amps[p])
		var decay: float = exp(-1.0 / ((1.5 / (1.0 + float(p) * 0.7)) * float(SAMPLE_RATE)))
		var ph: float = 0.0
		for k in n:
			ph += inc
			if ph >= 1.0:
				ph -= 1.0
			var idx: int = start + k
			if idx >= FRAMES:
				idx -= FRAMES
			buf[idx] += sin(TAU * ph) * amp * gain * 0.06
			amp *= decay


static func _cricket(buf: PackedFloat32Array, start: int, gain: float, rng: RandomNumberGenerator) -> void:
	var pulses: int = 6
	var at: int = 0
	var ph: float = 0.0
	var hz: float = rng.randf_range(4200.0, 4900.0)
	for p in pulses:
		var n: int = int(0.028 * float(SAMPLE_RATE))
		for k in n:
			var t: float = float(k) / float(SAMPLE_RATE)
			ph += hz / float(SAMPLE_RATE)
			if ph >= 1.0:
				ph -= 1.0
			var env: float = sin(PI * t / 0.028)
			_add(buf, start + at + k, sin(TAU * ph) * env * env * gain * 0.035)
		at += int(0.052 * float(SAMPLE_RATE))


# --- stem 1: felt electric piano ----------------------------------------------

static func _felt_piano(buf: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	for bar in BAR_COUNT:
		var ci: int = bar % 4
		var start: int = bar * SAMPLES_PER_BAR
		var vel: float = rng.randf_range(0.86, 1.0)
		_stab(buf, start, ci, vel, 1.25)
		if bar % 4 == 2:
			_stab(buf, start + SAMPLES_PER_BEAT * 2 + SAMPLES_PER_BEAT / 2, ci, vel * 0.34, 0.7)
	# Leading tone: bar 16 lifts B4 so the seam resolves up to C on the downbeat.
	_ep_note(buf, 15 * SAMPLES_PER_BAR + SAMPLES_PER_BEAT * 3, _hz(71), 1.1, 0.30)
	_ep_note(buf, 15 * SAMPLES_PER_BAR + SAMPLES_PER_BEAT * 3, _hz(52), 1.3, 0.26)


static func _stab(buf: PackedFloat32Array, start: int, ci: int, gain: float, dur: float) -> void:
	var roll: int = int(0.013 * float(SAMPLE_RATE))
	for v in 4:
		var midi: int = int(CHOLD[ci][v])
		_ep_note(buf, start + v * roll, _hz(midi), dur, gain * (0.92 - 0.07 * float(v)))


static func _ep_note(buf: PackedFloat32Array, start: int, hz: float, dur: float, gain: float) -> void:
	var tab: PackedFloat32Array = _felt()
	var inc: float = hz * float(SIN_SIZE) / float(SAMPLE_RATE)
	var n: int = int(dur * float(SAMPLE_RATE))
	var decay: float = exp(-1.0 / (0.62 * float(SAMPLE_RATE)))
	var att_inc: float = 1.0 / (0.008 * float(SAMPLE_RATE))
	var ph: float = 0.0
	var amp: float = gain
	var att: float = 0.0
	# The 8 ms felt attack is its own tiny loop so the body pays for no envelope.
	var ramp: int = mini(n, int(0.008 * float(SAMPLE_RATE)))
	for k in ramp:
		ph += inc
		if ph >= float(SIN_SIZE):
			ph -= float(SIN_SIZE)
		att += att_inc
		var idx: int = start + k
		if idx >= FRAMES:
			idx -= FRAMES
		buf[idx] += tab[int(ph) & SIN_MASK] * amp * att
		amp *= decay
	for k in range(ramp, n):
		ph += inc
		if ph >= float(SIN_SIZE):
			ph -= float(SIN_SIZE)
		var idx: int = start + k
		if idx >= FRAMES:
			idx -= FRAMES
		buf[idx] += tab[int(ph) & SIN_MASK] * amp
		amp *= decay


static func _felt() -> PackedFloat32Array:
	if _felt_tab.is_empty():
		var tab: PackedFloat32Array = PackedFloat32Array()
		tab.resize(SIN_SIZE + 1)
		for i in SIN_SIZE + 1:
			var ph: float = TAU * float(i) / float(SIN_SIZE)
			# Fundamental plus soft 2nd/3rd: one table read per sample, harmonics
			# implicit because they are integer multiples of the same phase.
			tab[i] = sin(ph) + 0.30 * sin(2.0 * ph) + 0.13 * sin(3.0 * ph)
		_felt_tab = tab
	return _felt_tab


# --- stem 2: kalimba arpeggio -------------------------------------------------

static func _kalimba(buf: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var offsets: Array = [0.5, 1.25, 2.5, 3.25]
	for bar in BAR_COUNT:
		var ci: int = bar % 4
		for j in offsets.size():
			var beat: float = float(bar * BEATS_PER_BAR) + float(offsets[j])
			beat += rng.randf_range(-0.03, 0.03)
			var at: int = int(beat * float(SAMPLES_PER_BEAT))
			var tone: int = int(CHOLD[ci][(bar + j * 2) % 4]) + 12
			if (bar + j) % 3 == 0:
				tone += 7
			var gain: float = rng.randf_range(0.10, 0.19)
			_pluck(buf, at, _hz(tone), gain, rng)


static func _pluck(buf: PackedFloat32Array, start: int, hz: float, gain: float, rng: RandomNumberGenerator) -> void:
	var size: int = maxi(2, int(float(SAMPLE_RATE) / hz))
	var line: PackedFloat32Array = PackedFloat32Array()
	line.resize(size)
	for i in size:
		line[i] = rng.randf() * 2.0 - 1.0
	var n: int = int(0.55 * float(SAMPLE_RATE))
	var pos: int = 0
	var prev: float = 0.0
	var amp: float = gain
	var damp: float = 0.9955
	var ramp: int = mini(n, 64)
	for k in n:
		var cur: float = line[pos]
		var avg: float = 0.5 * (cur + prev) * damp
		line[pos] = avg
		prev = cur
		pos += 1
		if pos >= size:
			pos = 0
		var idx: int = start + k
		if idx >= FRAMES:
			idx -= FRAMES
		if k < ramp:
			buf[idx] += cur * amp * (float(k) / float(ramp))
		else:
			buf[idx] += cur * amp
		amp *= 0.99965


# --- stem 3: warm cello/pad swell ---------------------------------------------

static func _pad(buf: PackedFloat32Array) -> void:
	var half: int = FRAMES / 2
	var half_bar: int = SAMPLES_PER_BAR / 2
	var low: PackedFloat32Array = PackedFloat32Array()
	low.resize(half)
	var ph_a: float = 0.0
	var ph_b: float = 0.0
	var lp: float = 0.0
	var breath: float = 0.72
	for bar in BAR_COUNT:
		var root_hz: float = _hz(int(CHORD_ROOTS[bar % 4]))
		# Two detuned triangles; only the increment changes at a bar line, so the
		# phase stays continuous and the swell glides into the next root silently.
		var ia: float = root_hz * 0.9975 / 11025.0
		var ib: float = root_hz * 1.0025 / 11025.0
		var goal: float = 0.62 + 0.38 * sin(TAU * float(bar) / float(BAR_COUNT / 4))
		var step: float = (goal - breath) / float(half_bar)
		var s0: int = bar * half_bar
		for i in range(s0, s0 + half_bar):
			ph_a += ia
			if ph_a >= 1.0:
				ph_a -= 1.0
			ph_b += ib
			if ph_b >= 1.0:
				ph_b -= 1.0
			var mix: float = 1.0 - 2.0 * (absf(ph_a - 0.5) + absf(ph_b - 0.5))
			lp += (mix - lp) * 0.05
			breath += step
			low[i] = lp * breath * 0.62
	var prev: float = low[half - 1]
	for k in half:
		var v: float = low[k]
		buf[k * 2] = v * 0.72 + prev * 0.28
		buf[k * 2 + 1] = v
		prev = v


# --- stem 4: harmonic resolution ----------------------------------------------

static func _chime(buf: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var b12: int = 12 * SAMPLES_PER_BAR
	var b13: int = 13 * SAMPLES_PER_BAR
	var b14: int = 14 * SAMPLES_PER_BAR
	var b15: int = 15 * SAMPLES_PER_BAR
	_bell(buf, b12, _hz(69), 0.26, 3.8)
	var shimmer: int = int(rng.randf_range(0.0, 0.5) * float(SAMPLE_RATE))
	_bell(buf, b14 + shimmer, _hz(88), 0.07, 2.5)
	# The cadence: struck a bar before the seam, its tail wraps and decays across
	# the downbeat, so the loop restarts under a sounding chord instead of silence.
	_bell(buf, b15, _hz(65), 0.26, 4.4)
	_bell(buf, b15 + SAMPLES_PER_BEAT, _hz(72), 0.20, 4.0)
	_bell(buf, b15 + SAMPLES_PER_BEAT * 2, _hz(76), 0.17, 4.0)
	_bell(buf, b15 + SAMPLES_PER_BEAT * 3, _hz(84), 0.22, 4.4)


static func _bell(buf: PackedFloat32Array, start: int, hz: float, gain: float, dur: float) -> void:
	var n: int = int(dur * float(SAMPLE_RATE))
	var ph1: float = 0.0
	var ph2: float = 0.0
	var i1: float = hz / float(SAMPLE_RATE)
	var i2: float = hz * 2.76 / float(SAMPLE_RATE)
	var a1: float = gain
	var a2: float = gain * 0.32
	var d1: float = exp(-1.0 / (0.85 * float(SAMPLE_RATE)))
	var d2: float = exp(-1.0 / (0.42 * float(SAMPLE_RATE)))
	var ramp: int = mini(n, int(0.025 * float(SAMPLE_RATE)))
	var att_inc: float = 1.0 / float(ramp)
	for k in n:
		ph1 += i1
		if ph1 >= 1.0:
			ph1 -= 1.0
		ph2 += i2
		if ph2 >= 1.0:
			ph2 -= 1.0
		var v: float = sin(TAU * ph1) * a1 + sin(TAU * ph2) * a2
		if k < ramp:
			v *= float(k) * att_inc
		a1 *= d1
		a2 *= d2
		var idx: int = start + k
		if idx >= FRAMES:
			idx -= FRAMES
		buf[idx] += v


# --- shared helpers -----------------------------------------------------------

static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)


## Writes to a wrapped frame so tails started before the seam continue after it.
static func _add(buf: PackedFloat32Array, index: int, value: float) -> void:
	var i: int = index % FRAMES
	if i < 0:
		i += FRAMES
	buf[i] += value


## The forward loop has no step at the seam: ramp the last frames onto buf[0].
static func _seal(buf: PackedFloat32Array) -> void:
	var delta: float = buf[0] - buf[FRAMES - 1]
	if absf(delta) < 0.000001:
		return
	for j in SEAM:
		var w: float = float(j + 1) / float(SEAM)
		buf[FRAMES - SEAM + j] += delta * w


static func _to_wav(buf: PackedFloat32Array, peak_target: float) -> AudioStreamWAV:
	# Peak on every second frame plus a 25% margin: everything here is smooth at
	# 22 kHz, so the stride cannot miss the true peak by more than that.
	var peak: float = 0.0
	for i in range(0, FRAMES, 2):
		var a: float = absf(buf[i])
		if a > peak:
			peak = a
	peak *= 1.25
	var scale: float = 0.0
	if peak > 0.000001:
		scale = peak_target / peak
	var k: float = scale * 32700.0
	var data: PackedByteArray = PackedByteArray()
	data.resize(FRAMES * 2)
	for i in FRAMES:
		data.encode_s16(i * 2, int(buf[i] * k))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = FRAMES
	wav.data = data
	return wav
