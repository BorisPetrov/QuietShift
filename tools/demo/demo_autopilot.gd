extends Node

## Автопилот для записи демо. Ведёт ремонтника по игровому циклу штатными
## действиями: жмёт «вперёд», поворачивает камеру, берёт, ставит, щёлкает
## тумблерами. Физика, сеть и интерфейс работают как в обычной игре.
##
## Сценарий — массив шагов в PLAN. Время шага задаётся в секундах.
##   look  {yaw, sec}       — плавно повернуть камеру по горизонтали
##   pitch {to, sec}        — плавно наклонить камеру
##   wait  {sec}            — пауза
##   goto  {what, stop}     — дойти до цели и остановиться на расстоянии stop, м
##   aim   {what, sec}      — навести прицел на цель
##   grab / use             — ЛКМ / E
##   toggle {idx}           — тумблер узла (0 = клавиша «1»)
##   fill                   — закрыть все оставшиеся гнёзда без переноски,
##                            чтобы показать сеть под полной нагрузкой (читерство)
##   quit                   — завершить запись
## what: "coil" / "plate" / "cell" (ближайшая деталь) или код узла ("ГЕН-4").
##
## Запись: см. раздел «Запись демо» в README.md.

const GOTO_TIMEOUT := 15.0   # с: застрял в пути — идём к следующему шагу

const PLAN := [
	{"op": "look", "yaw": -0.5, "sec": 0.9},
	{"op": "look", "yaw": 0.35, "sec": 0.9},
	{"op": "goto", "what": "coil", "stop": 2.1},
	{"op": "aim", "what": "coil", "sec": 0.5},
	{"op": "grab"},
	{"op": "wait", "sec": 0.5},
	{"op": "goto", "what": "ГЕН-4", "stop": 3.2},
	{"op": "aim", "what": "ГЕН-4", "sec": 0.5},
	{"op": "use"},
	{"op": "wait", "sec": 0.6},
	{"op": "goto", "what": "plate", "stop": 2.1},
	{"op": "aim", "what": "plate", "sec": 0.5},
	{"op": "grab"},
	{"op": "goto", "what": "ГЕН-4", "stop": 3.2},
	{"op": "aim", "what": "ГЕН-4", "sec": 0.5},
	{"op": "use"},
	{"op": "wait", "sec": 0.7},
	{"op": "goto", "what": "cell", "stop": 2.1},
	{"op": "aim", "what": "cell", "sec": 0.5},
	{"op": "grab"},
	{"op": "goto", "what": "ГЕН-4", "stop": 3.2},
	{"op": "aim", "what": "ГЕН-4", "sec": 0.5},
	{"op": "use"},
	{"op": "wait", "sec": 1.0},
	# катушку — в маяк М-2, чтобы конус света зажёгся в кадре
	{"op": "goto", "what": "coil", "stop": 2.1},
	{"op": "aim", "what": "coil", "sec": 0.5},
	{"op": "grab"},
	{"op": "goto", "what": "М-2", "stop": 3.0},
	{"op": "aim", "what": "М-2", "sec": 0.5},
	{"op": "use"},
	{"op": "wait", "sec": 0.7},
	{"op": "pitch", "to": 0.35, "sec": 0.9},
	{"op": "wait", "sec": 0.6},
	{"op": "pitch", "to": -0.12, "sec": 0.6},
	# остальные узлы разом: сеть под полной нагрузкой уходит в просадку
	{"op": "fill"},
	{"op": "goto", "what": "РТР-9", "stop": 5.0},
	{"op": "aim", "what": "РТР-9", "sec": 0.7},
	{"op": "wait", "sec": 1.3},
	{"op": "toggle", "idx": 1},   # снять П-2
	{"op": "wait", "sec": 0.9},
	{"op": "toggle", "idx": 4},   # снять М-3 — сеть выравнивается
	{"op": "wait", "sec": 2.0},
	{"op": "look", "yaw": 1.6, "sec": 2.0},
	{"op": "wait", "sec": 1.3},
	{"op": "quit"},
]

var game
var player
var step := 0
var elapsed := 0.0          # секунд на текущем шаге

func _physics_process(delta: float) -> void:
	game = get_tree().current_scene
	if game == null or game.player == null or step >= PLAN.size():
		return
	player = game.player
	elapsed += delta
	var s: Dictionary = PLAN[step]
	var rig = game.camera_rig

	match String(s["op"]):
		"look":
			rig.yaw = lerpf(rig.yaw, float(s["yaw"]), 0.04)
			_next_after(s)
		"pitch":
			rig.pitch = lerpf(rig.pitch, float(s["to"]), 0.06)
			_next_after(s)
		"wait":
			_next_after(s)
		"goto":
			var n := _target(String(s["what"]))
			if n == null:
				_next()
				return
			var flat: Vector3 = n.global_position - player.torso.global_position
			flat.y = 0.0
			if flat.length() <= float(s["stop"]) or elapsed > GOTO_TIMEOUT:
				_next()
				return
			var dir: Vector3 = n.global_position - rig.camera.global_position
			rig.yaw = lerp_angle(rig.yaw, atan2(-dir.x, -dir.z), 0.12)
			rig.pitch = lerpf(rig.pitch, -0.12, 0.08)
			_walk(true)
		"aim":
			var t := _target(String(s["what"]))
			if t == null:
				_next()
				return
			_aim(t.global_position + (Vector3(0, 1.2, 0) if t is Machine else Vector3.ZERO))
			_next_after(s)
		"grab":
			player.grab_or_drop()
			_next()
		"use":
			player.interact()
			_next()
		"toggle":
			game.toggle_machine(int(s["idx"]))
			_next()
		"fill":
			for m in game.power.machines:
				for k in m.slots:
					m.install(k)
				if m.role == Machine.Role.PROCESSOR:
					for i in 4:
						m.install(Part.Kind.SCRAP)
				if m.role == Machine.Role.GENERATOR:
					m.install(Part.Kind.CELL)
			_next()
		"quit":
			get_tree().quit()

func _next_after(s: Dictionary) -> void:
	if elapsed >= float(s["sec"]):
		_next()

func _next() -> void:
	step += 1
	elapsed = 0.0
	_walk(false)

func _walk(on: bool) -> void:
	if on != Input.is_action_pressed("move_forward"):
		if on:
			Input.action_press("move_forward")
		else:
			Input.action_release("move_forward")

## Навести камеру так, чтобы точка оказалась под прицелом. Сходится за
## несколько кадров: камера сдвигается вслед за своим же поворотом.
func _aim(p: Vector3) -> void:
	var rig = game.camera_rig
	var d: Vector3 = p - rig.camera.global_position
	rig.yaw = atan2(-d.x, -d.z)
	rig.pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.0, 0.5)

func _target(what: String) -> Node3D:
	match what:
		"coil": return _nearest_part(Part.Kind.COIL)
		"plate": return _nearest_part(Part.Kind.PLATE)
		"cell": return _nearest_part(Part.Kind.CELL)
	for m in game.power.machines:
		if m.code == what:
			return m
	return null

func _nearest_part(kind: int) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in game.world.salvage_parts:
		if is_instance_valid(p) and p.kind == kind and p != player.carried:
			var d: float = p.global_position.distance_to(player.torso.global_position)
			if d < best_d:
				best_d = d
				best = p
	return best
