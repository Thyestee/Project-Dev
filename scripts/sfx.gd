extends Node
# Sound effects synthesized at startup, so the game needs no audio files. play() is for your
# own sounds; play_at() places a sound out in the world. The pickaxe has a sound for every kind
# of surface it can land on ("pick_" + Blocks.SOUND).

const RATE := 22050

var _streams := {}
var _players := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0


func _ready() -> void:
	# The pickaxe: dull in soft ground, crunchy in sand and gravel, sharp in rock, ringing off
	# ore and metal, chiming off gems.
	_add("pick_soft", _mix([_noise(0.16, 1.0, 380.0, 24.0), _tone(80.0, 0.16, 0.9, 26.0), _grains(0.12, 0.35, 900.0, 2200.0, 6, 11)], 0.75))
	_add("pick_sand", _mix([_grains(0.2, 1.0, 2200.0, 6000.0, 40, 12), _noise(0.14, 0.55, 2800.0, 28.0), _tone(120.0, 0.08, 0.35, 45.0)], 0.6))
	_add("pick_gravel", _mix([_grains(0.24, 1.0, 700.0, 3000.0, 26, 13), _noise(0.12, 0.5, 900.0, 30.0), _tone(100.0, 0.1, 0.5, 35.0)], 0.72))
	_add("pick_coal", _mix([_grains(0.18, 0.9, 900.0, 3500.0, 16, 14), _noise(0.1, 0.8, 1300.0, 40.0), _tone(160.0, 0.1, 0.45, 40.0)], 0.7))
	_add("pick_stone", _mix([_noise(0.12, 1.0, 2400.0, 42.0), _tone(310.0, 0.14, 0.7, 30.0), _tone(1250.0, 0.06, 0.3, 70.0), _grains(0.16, 0.35, 1200.0, 3500.0, 8, 15)], 0.75))
	_add("pick_slate", _mix([_noise(0.1, 0.9, 3200.0, 55.0), _tone(520.0, 0.16, 0.6, 26.0), _tone(1580.0, 0.12, 0.35, 34.0)], 0.7))
	_add("pick_hard", _mix([_noise(0.06, 0.8, 3000.0, 75.0), _ring([760.0, 1140.0, 1710.0], 0.4, 1.0, 15.0), _tone(190.0, 0.12, 0.5, 30.0)], 0.65))
	_add("pick_ore", _mix([_noise(0.1, 0.9, 2200.0, 48.0), _tone(330.0, 0.12, 0.5, 30.0), _ring([1480.0, 2220.0], 0.45, 0.75, 10.0)], 0.7))
	_add("pick_gem", _mix([_noise(0.05, 0.6, 4000.0, 80.0), _ring([2640.0, 3960.0, 5280.0], 0.55, 1.0, 8.0)], 0.55))
	_add("pick_bedrock", _mix([_tone(105.0, 0.25, 1.0, 16.0), _noise(0.12, 0.7, 520.0, 28.0), _ring([880.0, 1320.0], 0.25, 0.35, 20.0)], 0.8))
	_add("pick_treasure", _mix([_ring([1900.0, 2850.0, 3800.0], 0.5, 1.0, 8.0), _noise(0.04, 0.5, 3500.0, 90.0)], 0.5))
	_add("pick_wood", _mix([_tone(230.0, 0.16, 1.0, 26.0), _tone(470.0, 0.12, 0.5, 34.0), _noise(0.08, 0.6, 1100.0, 45.0)], 0.7))
	_add("pick_brick", _mix([_noise(0.12, 1.0, 1500.0, 38.0), _tone(200.0, 0.12, 0.7, 30.0), _grains(0.15, 0.4, 900.0, 2600.0, 9, 16)], 0.75))
	_add("pick_metal", _mix([_ring([820.0, 1230.0, 1890.0], 0.6, 1.0, 7.0), _noise(0.05, 0.6, 3000.0, 60.0)], 0.5))
	_add("pick_glass", _mix([_ring([2300.0, 3450.0], 0.3, 1.0, 13.0), _noise(0.03, 0.5, 5000.0, 100.0)], 0.45))
	_add("pick_cloth", _mix([_noise(0.12, 1.0, 420.0, 30.0), _noise(0.08, 0.35, 2000.0, 50.0)], 0.5))
	_add("pick_bone", _mix([_noise(0.09, 1.0, 2600.0, 45.0), _tone(620.0, 0.09, 0.6, 40.0)], 0.6))
	# A soft ring when you dig close to buried treasure.
	_add("ring", _ring([1320.0, 1985.0, 2650.0], 1.3, 0.55, 2.6))
	_add("break", _noise(0.2, 0.65, 700.0, 16.0))
	_add("place", _noise(0.09, 0.55, 450.0, 40.0))
	_add("step", _noise(0.07, 0.3, 350.0, 55.0))
	_add("treasure", _chime([660.0, 830.0, 990.0, 1320.0], 0.45))
	_add("clink", _tone(1900.0, 0.14, 0.35, 28.0))
	_add("buy", _chime([990.0, 1480.0], 0.45))
	_add("swing", _whoosh(0.22, 0.5))
	_add("hit_bone", _mix([_noise(0.09, 1.0, 2600.0, 45.0), _tone(620.0, 0.09, 0.6, 40.0)], 0.6))
	_add("hit_stone", _mix([_noise(0.16, 1.0, 480.0, 20.0), _tone(140.0, 0.16, 0.6, 22.0)], 0.7))
	_add("hit_metal", _mix([_tone(820.0, 0.5, 0.6, 8.0), _tone(1230.0, 0.5, 0.4, 10.0), _noise(0.05, 0.6, 3000.0, 60.0)], 0.5))
	_add("hit_soft", _mix([_noise(0.12, 1.0, 700.0, 25.0), _tone(180.0, 0.12, 0.6, 25.0)], 0.6))
	_add("block", _mix([_tone(520.0, 0.35, 0.6, 14.0), _tone(780.0, 0.35, 0.4, 16.0), _noise(0.06, 0.7, 2500.0, 50.0)], 0.55))
	_add("hollow", _mix([_tone(150.0, 0.35, 1.0, 9.0), _tone(225.0, 0.3, 0.5, 11.0), _noise(0.08, 0.6, 600.0, 30.0)], 0.7))
	_add("spikes", _mix([_noise(0.18, 1.0, 3500.0, 25.0), _ring([900.0, 1350.0], 0.25, 0.6, 18.0)], 0.65))
	_add("trap", _mix([_tone(700.0, 0.06, 0.8, 70.0), _noise(0.05, 0.6, 2500.0, 90.0)], 0.5))
	_add("twang", _mix([_tone(220.0, 0.25, 0.6, 18.0), _tone(440.0, 0.2, 0.3, 24.0), _noise(0.03, 0.6, 3000.0, 80.0)], 0.55))
	_add("thunk", _mix([_noise(0.07, 1.0, 900.0, 50.0), _tone(300.0, 0.07, 0.5, 45.0)], 0.6))
	_add("fuse", _noise(0.25, 0.25, 7000.0, 4.0))
	_add("boom", _mix([_noise(1.6, 1.0, 320.0, 3.0), _tone(55.0, 1.2, 0.8, 3.5)], 0.9))
	_add("hurt", _mix([_slide(170.0, 105.0, 0.22, 0.8), _noise(0.12, 0.5, 600.0, 25.0)], 0.6))
	_add("crumble", _crackle(0.7, 0.6))
	_add("alert", _mix([_tone(110.0, 0.5, 0.6, 3.0), _tone(166.0, 0.5, 0.4, 3.5)], 0.45))
	_add("hiss", _noise(0.35, 0.4, 4500.0, 7.0))
	_add("slam", _mix([_noise(0.5, 1.0, 260.0, 8.0), _tone(60.0, 0.5, 0.8, 7.0)], 0.85))
	_add("chest", _chime([880.0, 1100.0, 1320.0, 1760.0], 0.4))
	_add("anvil", _mix([_tone(1100.0, 0.8, 0.6, 6.0), _tone(1650.0, 0.8, 0.4, 7.0), _tone(2470.0, 0.6, 0.25, 9.0)], 0.5))
	_add("level", _noise(0.3, 0.5, 1800.0, 9.0))
	_add("sleep", _chime([520.0, 660.0, 780.0], 0.35))
	_add("vault", _mix([_noise(1.4, 1.0, 120.0, 2.0), _tone(70.0, 1.4, 0.6, 2.0)], 0.8))
	_add("pickup", _chime([1500.0, 2000.0], 0.3))
	_add("coin", _mix([_tone(2000.0, 0.2, 0.5, 20.0), _tone(2600.0, 0.2, 0.4, 24.0)], 0.4))
	_add("zap", _mix([_noise(0.45, 1.0, 5000.0, 9.0), _noise(0.6, 0.8, 200.0, 5.0)], 0.75))
	for n in 12:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 5.0
		p.max_distance = 45.0
		add_child(p)
		_pool.append(p)


func play(sound: String, pitch := 1.0, volume_db := 0.0) -> void:
	var p: AudioStreamPlayer = _players[sound]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


func play_at(sound: String, pos: Vector3, pitch := 1.0, volume_db := 0.0) -> void:
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[sound]
	p.global_position = pos
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


func _add(sound: String, stream: AudioStreamWAV) -> void:
	_streams[sound] = stream
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.max_polyphony = 4
	add_child(p)
	_players[sound] = p


static func _tone(freq: float, length: float, volume: float, decay: float) -> AudioStreamWAV:
	return _wav(_tone_samples(freq, length, decay), volume)


static func _tone_samples(freq: float, length: float, decay: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(length * RATE))
	for i in samples.size():
		var t := float(i) / RATE
		samples[i] = sin(TAU * freq * t) * exp(-t * decay) * minf(1.0, t * 300.0)
	return samples


# Low-passed noise with a quick fade: thuds, scrapes and footsteps.
static func _noise(length: float, volume: float, cutoff: float, decay: float) -> AudioStreamWAV:
	return _wav(_noise_samples(length, cutoff, decay), volume)


static func _noise_samples(length: float, cutoff: float, decay: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cutoff * 7.0 + length * 1000.0)
	var alpha := 1.0 - exp(-TAU * cutoff / RATE)
	var samples := PackedFloat32Array()
	samples.resize(int(length * RATE))
	var v := 0.0
	for i in samples.size():
		var t := float(i) / RATE
		v += (rng.randf_range(-1.0, 1.0) - v) * alpha
		samples[i] = v * exp(-t * decay) * minf(1.0, t * 500.0)
	return samples


# Noise whose brightness swells and fades: a blade cutting the air.
static func _whoosh(length: float, volume: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var samples := PackedFloat32Array()
	samples.resize(int(length * RATE))
	var v := 0.0
	for i in samples.size():
		var t := float(i) / RATE
		var k := sin(PI * t / length)
		var alpha := 1.0 - exp(-TAU * (300.0 + 2200.0 * k) / RATE)
		v += (rng.randf_range(-1.0, 1.0) - v) * alpha
		samples[i] = v * k * k
	return _wav(samples, volume)


# A tone gliding from one pitch to another: a creaking bowstring, a grunt.
static func _slide(from: float, to: float, length: float, volume: float) -> AudioStreamWAV:
	return _wav(_slide_samples(from, to, length), volume)


static func _slide_samples(from: float, to: float, length: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(length * RATE))
	var phase := 0.0
	for i in samples.size():
		var t := float(i) / RATE
		phase += TAU * lerpf(from, to, t / length) / RATE
		samples[i] = (sin(phase) + 0.4 * sin(phase * 2.0)) * sin(PI * t / length)
	return samples


# Partials that ring on and fade, the higher ones sooner: metal, crystal, glass.
static func _ring(freqs: Array, length: float, volume: float, decay: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(length * RATE))
	for k in freqs.size():
		var freq: float = freqs[k]
		var fade := decay * (1.0 + 0.5 * k)
		var amp := 1.0 / (1.0 + 0.6 * k)
		for i in samples.size():
			var t := float(i) / RATE
			samples[i] += sin(TAU * freq * t) * amp * exp(-t * fade) * minf(1.0, t * 800.0)
	return _wav(samples, volume)


# Lots of tiny clicks close together, most of them early: sand and gravel shifting, coal
# crumbling. `lo` and `hi` bound how bright each click is.
static func _grains(length: float, volume: float, lo: float, hi: float, count: int, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var samples := PackedFloat32Array()
	samples.resize(int(length * RATE))
	for n in count:
		var start := int(rng.randf() * rng.randf() * length * 0.85 * RATE)
		var alpha := 1.0 - exp(-TAU * rng.randf_range(lo, hi) / RATE)
		var amp := rng.randf_range(0.25, 1.0) * (1.0 - float(start) / samples.size())
		var v := 0.0
		for i in range(start, mini(start + int(0.025 * RATE), samples.size())):
			var t := float(i - start) / RATE
			v += (rng.randf_range(-1.0, 1.0) - v) * alpha
			samples[i] += v * amp * exp(-t * 140.0)
	return _wav(samples, volume)


# Lots of little clicks and thuds: bones and stones falling apart.
static func _crackle(length: float, volume: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var samples := PackedFloat32Array()
	samples.resize(int(length * RATE))
	for n in 26:
		var start := int(rng.randf() * rng.randf() * length * 0.8 * RATE)
		var cutoff := rng.randf_range(400.0, 2500.0)
		var alpha := 1.0 - exp(-TAU * cutoff / RATE)
		var v := 0.0
		var amp := rng.randf_range(0.3, 1.0)
		for i in range(start, mini(start + int(0.06 * RATE), samples.size())):
			var t := float(i - start) / RATE
			v += (rng.randf_range(-1.0, 1.0) - v) * alpha
			samples[i] += v * amp * exp(-t * 60.0)
	return _wav(samples, volume)


static func _chime(notes: Array, volume: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(1.4 * RATE))
	for n in notes.size():
		var start := n * 0.08
		var freq: float = notes[n]
		for i in range(int(start * RATE), samples.size()):
			var t := float(i) / RATE - start
			samples[i] += (sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t)) * exp(-t * 3.0) * minf(1.0, t * 200.0)
	return _wav(samples, volume)


# Layers several sounds that were made separately.
static func _mix(parts: Array, volume: float) -> AudioStreamWAV:
	var length := 0
	var decoded: Array[PackedFloat32Array] = []
	for w: AudioStreamWAV in parts:
		var data := w.data
		var s := PackedFloat32Array()
		s.resize(data.size() / 2)
		for i in s.size():
			s[i] = data.decode_s16(i * 2) / 32767.0
		decoded.append(s)
		length = maxi(length, s.size())
	var out := PackedFloat32Array()
	out.resize(length)
	for s in decoded:
		for i in s.size():
			out[i] += s[i]
	return _wav(out, volume)


# Scales the samples so the loudest one reaches `volume`, then packs them as 16-bit PCM.
static func _wav(samples: PackedFloat32Array, volume: float) -> AudioStreamWAV:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * volume, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
