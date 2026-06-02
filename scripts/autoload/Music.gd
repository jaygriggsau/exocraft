extends Node
## Procedural 16-bit atmospheric music. Synthesised live with an
## AudioStreamGenerator (no audio files) — a slow chord pad, a triangle bass and
## a soft square arpeggio, run through a reverb + low-pass bus. The chord
## progression shifts between a brighter "day" set and a moodier "night" set.

const SR := 22050.0
const CHORD_LEN := 6.0     ## seconds per chord
const ARP_LEN := 0.5       ## seconds per arpeggio note

# chord = semitone offsets from the root; built into 4 voices
const ROOT := 220.0        ## A3
const DAY := [[0, 3, 7, 12], [-4, 0, 3, 8], [3, 7, 10, 15], [-2, 2, 5, 10]]   # Am F C G
const NIGHT := [[0, 3, 7, 12], [5, 8, 12, 17], [-4, 0, 3, 8], [7, 10, 14, 19]] # Am Dm F Em

var _player: AudioStreamPlayer
var _playback                 # AudioStreamGeneratorPlayback (untyped: getter returns base)
var _enabled := true

var _time := 0.0
var _prog := DAY
var _ci := -1
var _chord: Array = []      # current chord frequencies (4)
var _pad_phase := [0.0, 0.0, 0.0, 0.0]
var _bass_phase := 0.0
var _arp_phase := 0.0
var _arp_step := -1
var _arp_freq := 220.0
var _arp_t0 := 0.0

func _ready() -> void:
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Music")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 4200.0
	AudioServer.add_bus_effect(bus, lp)
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.85
	rv.damping = 0.4
	rv.wet = 0.35
	AudioServer.add_bus_effect(bus, rv)
	AudioServer.set_bus_volume_db(bus, -9.0)

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SR
	gen.buffer_length = 0.25
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.bus = "Music"
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	_set_chord(0)

func _process(_dt: float) -> void:
	if _playback == null:
		return
	var frames: int = _playback.get_frames_available()
	if frames <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		var v := _render()
		buf[i] = Vector2(v, v)
	_playback.push_buffer(buf)

# render one mono sample, advancing all oscillators
func _render() -> float:
	_time += 1.0 / SR

	var ci := int(_time / CHORD_LEN)
	if ci != _ci:
		_ci = ci
		_prog = NIGHT if _is_night() else DAY
		_set_chord(ci)

	var step := int(_time / ARP_LEN)
	if step != _arp_step:
		_arp_step = step
		_arp_freq = _chord[step % _chord.size()] * 2.0
		_arp_t0 = _time

	var vib := 1.0 + sin(TAU * 0.2 * _time) * 0.004
	var s := 0.0
	for v in 4:
		_pad_phase[v] = fposmod(_pad_phase[v] + TAU * _chord[v] * vib / SR, TAU)
		s += sin(_pad_phase[v]) * 0.075
	_bass_phase = fposmod(_bass_phase + TAU * (_chord[0] * 0.5) / SR, TAU)
	s += _tri(_bass_phase) * 0.11
	_arp_phase = fposmod(_arp_phase + TAU * _arp_freq / SR, TAU)
	var aenv := exp(-(_time - _arp_t0) / 0.18) * (0.06 if _is_night() else 0.10)
	s += _sqr(_arp_phase) * aenv
	return clampf(s, -0.95, 0.95) * (1.0 if _enabled else 0.0)

func _set_chord(ci: int) -> void:
	var c: Array = _prog[ci % _prog.size()]
	_chord = []
	for semi in c:
		_chord.append(ROOT * pow(2.0, float(semi) / 12.0))

func _is_night() -> bool:
	return Game.time_of_day < 0.24 or Game.time_of_day >= 0.76

func _tri(ph: float) -> float:
	var x := ph / TAU
	return 4.0 * absf(x - 0.5) - 1.0

func _sqr(ph: float) -> float:
	return 1.0 if sin(ph) >= 0.0 else -1.0

func toggle() -> void:
	_enabled = not _enabled

func is_enabled() -> bool:
	return _enabled
