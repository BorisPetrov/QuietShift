class_name SoundDesk
extends Node

## Звук синтезируется на месте, без файлов: низкий электронный гул станции
## (табличный, бесшовно замкнутый) плюс живой шумовой слой и короткие
## служебные сигналы. Палитра звука такая же приглушённая, как палитра света.

const SR := 16000.0
const LOOP := 6.0            # секунды; все частоты кратны 1/LOOP — стыка не слышно

var player: AudioStreamPlayer
var pb: AudioStreamGeneratorPlayback
var table: PackedFloat32Array
var cursor := 0
var muted := false

var _rng := RandomNumberGenerator.new()
var _noise_lp := 0.0
var _events: Array = []      # [{f, t, dur, amp, harsh}]
var _drive := 0.0            # «подъём» гула при работающей сети, 0..1

func _ready() -> void:
	_build_table()
	player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SR
	gen.buffer_length = 0.2
	player.stream = gen
	player.volume_db = -13.0
	add_child(player)
	player.play()
	pb = player.get_stream_playback() as AudioStreamGeneratorPlayback

func _exit_tree() -> void:
	# поток останавливаем и отпускаем до разрушения аудиосервера
	if player != null and player.playing:
		player.stop()
	pb = null

func _build_table() -> void:
	var n := int(SR * LOOP)
	table = PackedFloat32Array()
	table.resize(n)
	for i in n:
		var t := float(i) / SR
		var swell := 0.5 + 0.5 * sin(TAU * t / LOOP)
		var v := sin(TAU * 55.0 * t) * 0.5
		v += sin(TAU * 82.5 * t + sin(TAU * 0.3333333 * t) * 1.2) * 0.26
		v += sin(TAU * 110.5 * t) * 0.15 * swell
		v += sin(TAU * 27.5 * t) * 0.2
		# служебный пульс: станция всё ещё считает себя живой
		var ph := fmod(t, 2.0)
		if ph < 0.4:
			v += sin(TAU * 220.5 * ph) * exp(-ph * 8.0) * 0.07
		table[i] = v * 0.34

func _process(_delta: float) -> void:
	if pb == null:
		return
	var n := pb.get_frames_available()
	var size := table.size()
	for i in n:
		var tone: float = table[cursor]
		cursor = (cursor + 1) % size
		_noise_lp = lerpf(_noise_lp, _rng.randf_range(-1.0, 1.0), 0.035)
		var s: float = tone * (0.7 + _drive * 0.5) + _noise_lp * 0.30
		s += _events_sample()
		var right := s * 0.94 + _noise_lp * 0.05
		pb.push_frame(Vector2(clampf(s, -1.0, 1.0), clampf(right, -1.0, 1.0)))

func _events_sample() -> float:
	if _events.is_empty():
		return 0.0
	var out := 0.0
	var dt := 1.0 / SR
	var i := _events.size() - 1
	while i >= 0:
		var e: Dictionary = _events[i]
		var t: float = e["t"]
		if t >= e["dur"]:
			_events.remove_at(i)
		else:
			var env: float = exp(-t / (float(e["dur"]) * 0.32))
			var w: float = sin(TAU * float(e["f"]) * t)
			if e["harsh"]:
				w = signf(w) * 0.55 + w * 0.45
			out += w * env * float(e["amp"])
			e["t"] = t + dt
		i -= 1
	return out * 0.5

func set_drive(v: float) -> void:
	_drive = clampf(v, 0.0, 1.0)

func blip(freq: float, dur := 0.12, amp := 0.35, harsh := false) -> void:
	if muted:
		return
	_events.append({ "f": freq, "t": 0.0, "dur": dur, "amp": amp, "harsh": harsh })

func pickup() -> void:
	blip(300.0, 0.09, 0.26)

func seated() -> void:
	blip(392.0, 0.1, 0.3)
	blip(588.0, 0.2, 0.22)

func eject() -> void:
	blip(523.0, 0.12, 0.24)
	blip(349.0, 0.16, 0.18)

func brownout(active: bool) -> void:
	if active:
		blip(98.0, 0.55, 0.4, true)
	else:
		blip(174.0, 0.25, 0.22)

func fanfare() -> void:
	blip(174.5, 0.5, 0.3)
	blip(261.5, 0.7, 0.26)
	blip(349.0, 0.9, 0.2)

func toggle_mute() -> void:
	muted = not muted
	player.volume_db = -80.0 if muted else -13.0
