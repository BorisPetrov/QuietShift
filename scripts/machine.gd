class_name Machine
extends StaticBody3D

## Узел станции: генератор, батарея, потребитель, переработчик.
## Узел либо исправен (все гнёзда заполнены), либо нет. Неисправный узел
## не наказывает игрока — он просто молчит и не даёт мощности.

enum Role { GENERATOR, BATTERY, LOAD, PROCESSOR }

signal event(text: String, tone: int)
signal ejected(part_kind: int, pos: Vector3, dir: Vector3)

var code := "УЗЛ-0"
var label := "узел"
var role: int = Role.LOAD
var rated_kw := 0.0          # выдача (генератор) или потребление (нагрузка)
var enabled := true          # тумблер оператора
var powered_frac := 0.0      # доля полученной мощности, 0..1

# генератор
var fuel := 0.0              # в ячейках
var fuel_max := 3.0
var burn_per_sec := 1.0 / 80.0
var load_frac := 0.0         # текущая загрузка генератора, 0..1

# батарея
var charge := 0.0            # кВт*мин
var charge_max := 8.0
var discharge_max := 10.0
var charge_rate := 6.0

# переработчик
var hopper := 0              # лома в бункере
var hopper_max := 6
var cycle := 0.0
var cycle_time := 6.0
var _out_cursor := 0

# ретранслятор (целевой потребитель)
var is_uplink := false

var slots: Array = []        # требуемые Part.Kind
var filled: Array = []       # bool
var slot_nodes: Array = []   # MeshInstance3D индикаторов
var lamps: Array = []        # Light3D, яркость зависит от powered_frac
var lamp_base: Array = []    # базовая энергия ламп
var tag: Label3D = null      # бирка с кодом узла
var spin: Node3D = null      # вращающаяся деталь (дышит, когда узел работает)
var spin_speed := 0.0

func repaired() -> bool:
	return not filled.has(false)

func online() -> bool:
	if not repaired() or not enabled:
		return false
	if role == Role.GENERATOR:
		return fuel > 0.0
	return true

## Что узлу нужно сейчас: список коротких требований для интерфейса.
func needs() -> Array:
	var out := []
	if not repaired():
		for i in slots.size():
			if not filled[i]:
				out.append(Part.label_of(slots[i]))
		return out
	match role:
		Role.GENERATOR:
			if fuel < fuel_max:
				out.append(Part.label_of(Part.Kind.CELL))
		Role.PROCESSOR:
			if hopper < hopper_max:
				out.append(Part.label_of(Part.Kind.SCRAP))
	return out

func accepts(kind: int) -> bool:
	if not repaired():
		for i in slots.size():
			if not filled[i] and slots[i] == kind:
				return true
		return false
	if role == Role.GENERATOR and kind == Part.Kind.CELL:
		return fuel < fuel_max
	if role == Role.PROCESSOR and kind == Part.Kind.SCRAP:
		return hopper < hopper_max
	return false

## Принять предмет. Возвращает true, если предмет израсходован.
func install(kind: int) -> bool:
	if not repaired():
		for i in slots.size():
			if not filled[i] and slots[i] == kind:
				filled[i] = true
				refresh_slots()
				if repaired():
					event.emit("%s: сборка завершена. Узел признан исправным — впервые за долгое время." % code, LogFeed.Tone.GOOD)
				else:
					event.emit("%s: %s установлена. Осталось гнёзд: %d." % [code, Part.label_of(kind), _empty_count()], LogFeed.Tone.PLAIN)
				return true
		return false
	if role == Role.GENERATOR and kind == Part.Kind.CELL and fuel < fuel_max:
		fuel = minf(fuel_max, fuel + 1.0)
		event.emit("%s: ячейка в приёмнике. Топливо %.0f/%.0f." % [code, fuel, fuel_max], LogFeed.Tone.PLAIN)
		return true
	if role == Role.PROCESSOR and kind == Part.Kind.SCRAP and hopper < hopper_max:
		hopper += 1
		event.emit("%s: лом принят. Происхождение лома не уточняется." % code, LogFeed.Tone.PLAIN)
		return true
	return false

func _empty_count() -> int:
	var n := 0
	for f in filled:
		if not f:
			n += 1
	return n

## Строка состояния для плотного интерфейса.
func status() -> String:
	if not repaired():
		return "СБОРКА %d/%d" % [slots.size() - _empty_count(), slots.size()]
	if not enabled:
		return "ОТКЛ"
	match role:
		Role.GENERATOR:
			if fuel <= 0.0:
				return "БЕЗ ТОПЛИВА"
			return "РАБОТА %d%%" % int(load_frac * 100.0)
		Role.BATTERY:
			return "ЗАРЯД %d%%" % int(charge / charge_max * 100.0)
		Role.PROCESSOR:
			if hopper <= 0:
				return "БУНКЕР ПУСТ"
			if powered_frac < 0.2:
				return "ЖДЁТ ТОКА"
			return "ЦИКЛ %d%%" % int(cycle / cycle_time * 100.0)
		_:
			if powered_frac < 0.6:
				return "ПРОСАДКА %d%%" % int(powered_frac * 100.0)
			return "ПИТАНИЕ ОК"

func tick(delta: float) -> void:
	_fade_tag()
	# лампы узла дышат вместе с сетью — свет в этой игре и есть индикатор
	var lit := 0.0
	if online():
		lit = powered_frac if role == Role.LOAD or role == Role.PROCESSOR else 1.0
	for i in lamps.size():
		var l: Light3D = lamps[i]
		var target: float = float(lamp_base[i]) * lit
		l.light_energy = lerpf(l.light_energy, target, 1.0 - exp(-6.0 * delta))
		# лёгкое мерцание при недостатке мощности — заметно, но не раздражает
		if lit > 0.05 and lit < 0.95:
			l.light_energy *= 1.0 + sin(Time.get_ticks_msec() * 0.019 + i) * 0.12 * (1.0 - lit)
	if spin != null:
		var s := 0.0
		if role == Role.GENERATOR and online():
			s = spin_speed * (0.35 + load_frac * 0.65)
		elif role == Role.PROCESSOR and online() and hopper > 0:
			s = spin_speed * powered_frac
		spin.rotate_y(s * delta)

	if role == Role.PROCESSOR and online() and hopper > 0 and powered_frac > 0.2:
		cycle += delta * powered_frac
		if cycle >= cycle_time:
			cycle = 0.0
			hopper -= 1
			var out := [Part.Kind.COIL, Part.Kind.PLATE, Part.Kind.CELL, Part.Kind.COIL, Part.Kind.CELL, Part.Kind.PLATE]
			var k: int = out[_out_cursor % out.size()]
			_out_cursor += 1
			var chute := global_position + global_transform.basis.z * 1.5 + Vector3.UP * 1.0
			ejected.emit(k, chute, global_transform.basis.z * 2.2 + Vector3.UP * 1.4)
			event.emit("%s: выдана %s. Гарантия — до конца смены." % [code, Part.label_of(k)], LogFeed.Tone.GOOD)

## Бирка не должна ни перекрывать кадр вблизи, ни висеть в тумане далеко.
func _fade_tag() -> void:
	if tag == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(global_position)
	var a: float = clampf(inverse_lerp(3.5, 6.5, d), 0.0, 1.0) * clampf(inverse_lerp(44.0, 32.0, d), 0.0, 1.0)
	tag.visible = a > 0.02
	tag.modulate.a = a
	tag.outline_modulate.a = a

func refresh_slots() -> void:
	for i in slot_nodes.size():
		if i >= filled.size():
			continue
		var mi: MeshInstance3D = slot_nodes[i]
		if filled[i]:
			mi.material_override = Palette.glow(Palette.AMBER, 2.0)
		else:
			mi.material_override = Palette.mat(Palette.AMBER_DIM, 0.7, 0.3)

func setup_slots(kinds: Array) -> void:
	slots = kinds.duplicate()
	filled = []
	for _k in slots:
		filled.append(false)
