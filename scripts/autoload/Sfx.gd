extends Node
## Procedural sound effects. Short blips synthesised into AudioStreamWAV clips at
## startup (no audio files) and played through a pooled set of players on an
## "SFX" bus. Game code calls Sfx.play("mine"), Sfx.play("craft"), etc.

const SR := 22050
const POOL := 8

var _sounds := {}
var _players := []
var _next := 0

func _ready() -> void:
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "SFX")

	# name -> [f0, f1, duration, wave("sq"/"sin"), decay, noise]
	_sounds["mine"] = _make(420, 180, 0.07, "sq", 40.0, 0.4)
	_sounds["shoot"] = _make(900, 280, 0.12, "sq", 22.0, 0.1)
	_sounds["craft"] = _make(520, 880, 0.16, "sin", 10.0, 0.0)
	_sounds["deploy"] = _make(200, 760, 0.24, "sin", 7.0, 0.05)
	_sounds["hit"] = _make(150, 90, 0.14, "sq", 26.0, 0.3)
	_sounds["pickup"] = _make(640, 1040, 0.08, "sin", 16.0, 0.0)
	_sounds["gunshot"] = _make(320, 70, 0.09, "sq", 34.0, 0.7)    # sharp ballistic crack
	_sounds["slash"] = _make(1300, 360, 0.13, "sin", 16.0, 0.18)  # energy-blade whoosh

	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)

func play(name: String, pitch := 1.0) -> void:
	var s = _sounds.get(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.pitch_scale = pitch
	p.play()

func _make(f0: float, f1: float, dur: float, wave: String, decay: float, noise: float) -> AudioStreamWAV:
	var n := int(dur * SR)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 * 13 + f1)
	for i in n:
		var t := float(i) / SR
		var u := float(i) / float(n)
		var f := lerpf(f0, f1, u)
		var env := exp(-t * decay)
		var ph := TAU * f * t
		var osc := (1.0 if sin(ph) >= 0.0 else -1.0) if wave == "sq" else sin(ph)
		var s := (osc * (1.0 - noise) + rng.randf_range(-1.0, 1.0) * noise) * env * 0.5
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = bytes
	return wav
