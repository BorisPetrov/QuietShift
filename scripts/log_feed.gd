class_name LogFeed
extends Node

## Журнал смены. Голос повествования — ироничный: сухая служебная форма,
## в которой регулярно проговаривается то, о чём отчёты обычно молчат.

const MAX_LINES := 40

var lines: Array = []   # [{ t: float, text: String, tone: int }]
var clock := 0.0

enum Tone { PLAIN, GOOD, BAD }

func _process(delta: float) -> void:
	clock += delta

func push(text: String, tone: int = Tone.PLAIN) -> void:
	lines.append({ "t": clock, "text": text, "tone": tone })
	if lines.size() > MAX_LINES:
		lines.remove_at(0)

func tail(n: int) -> Array:
	var from := maxi(0, lines.size() - n)
	return lines.slice(from, lines.size())

func stamp(t: float) -> String:
	var total := int(t)
	return "%02d:%02d" % [total / 60, total % 60]
