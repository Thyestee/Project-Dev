extends Node
# Sound effects synthesized at startup, so the game needs no audio files.

const RATE := 22050

var _players := {}


func _ready() -> void:
	_add("beep", _tone(1250.0, 0.07, 0.4, 25.0))
	_add("dig", _noise(0.1, 0.5, 1100.0, 35.0))
	_add("break", _noise(0.2, 0.65, 700.0, 16.0))
	_add("place", _noise(0.09, 0.55, 450.0, 40.0))
	_add("step", _noise(0.07, 0.3, 350.0, 55.0))
	_add("treasure", _chime([660.0, 830.0, 990.0, 1320.0]))


func play(sound: String, pitch := 1.0, volume_db := 0.0) -> void:
	var p: AudioStreamPlayer = _players[sound]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


func _add(sound: String, stream: AudioStreamWAV) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.max_polyphony = 4
	add_child(p)
	_players[sound] = p


static func _tone(freq: float, length: float, volume: float, decay: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(length * RATE))
	for i in samples.size():
		var t := float(i) / RATE
		samples[i] = sin(TAU * freq * t) * exp(-t * decay) * minf(1.0, t * 300.0)
	return _wav(samples, volume)


# Low-passed noise with a quick fade: thuds, scrapes and footsteps.
static func _noise(length: float, volume: float, cutoff: float, decay: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cutoff)
	var alpha := 1.0 - exp(-TAU * cutoff / RATE)
	var samples := PackedFloat32Array()
	samples.resize(int(length * RATE))
	var v := 0.0
	for i in samples.size():
		var t := float(i) / RATE
		v += (rng.randf_range(-1.0, 1.0) - v) * alpha
		samples[i] = v * exp(-t * decay) * minf(1.0, t * 500.0)
	return _wav(samples, volume)


static func _chime(notes: Array) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(1.4 * RATE))
	for n in notes.size():
		var start := n * 0.08
		var freq: float = notes[n]
		for i in range(int(start * RATE), samples.size()):
			var t := float(i) / RATE - start
			samples[i] += (sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t)) * exp(-t * 3.0) * minf(1.0, t * 200.0)
	return _wav(samples, 0.45)


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
