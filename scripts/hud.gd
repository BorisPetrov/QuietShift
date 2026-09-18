extends Control

## Плотный интерфейс: сеть станции, груз, цель, журнал и обзорный экран
## видны одновременно. Всё рисуется вручную в одном _draw — служебная
## панель ремонтника, а не игровое меню.

var game                     # Game, без типа: HUD и Game ссылаются друг на друга
var font: Font
var mono_gap := 18.0

func _ready() -> void:
	font = ThemeDB.fallback_font
	set_process(true)

func bind(g) -> void:
	game = g

func _process(_delta: float) -> void:
	queue_redraw()

# --------------------------------------------------------------- рисование ---

func _t(pos: Vector2, text: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos, text, align, width, size, col)

func _panel(r: Rect2, title: String) -> void:
	draw_rect(r, Color(Palette.VOID, 0.74), true)
	draw_rect(r, Color(Palette.METAL, 0.9), false, 1.0)
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 15)), Color(Palette.METAL, 0.45), true)
	_t(r.position + Vector2(7, 12), title, 11, Palette.TEXT_DIM)

func _bar(r: Rect2, v: float, col: Color) -> void:
	draw_rect(r, Color(Palette.METAL, 0.35), true)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(v, 0.0, 1.0), r.size.y)), col, true)
	draw_rect(r, Color(Palette.METAL_LIGHT, 0.45), false, 1.0)

func _draw() -> void:
	if game == null or font == null:
		return
	_draw_topbar()
	_draw_network()
	_draw_balance()
	_draw_right()
	_draw_log()
	_draw_radar()
	_draw_reticle()
	_draw_hints()
	if game.contract_closed:
		_draw_closed()

func _draw_topbar() -> void:
	var r := Rect2(0, 0, size.x, 30)
	draw_rect(r, Color(Palette.VOID, 0.86), true)
	draw_line(Vector2(0, 30), Vector2(size.x, 30), Color(Palette.METAL, 0.9), 1.0)
	_t(Vector2(14, 20), "КОНТРАКТ 4417-Б · УЗЛОВАЯ СТАНЦИЯ «ТИШИНА-9» · ПЛАНЕТА KE-9", 12, Palette.TEXT)
	var p: PowerNet = game.power
	var net := "СЕТЬ  %5.1f / %4.1f кВт" % [p.served, p.demand]
	_t(Vector2(size.x - 330, 20), net, 12, Palette.ALERT if p.brownout else Palette.TEXT)
	_t(Vector2(size.x - 120, 20), "СМЕНА " + game.feed.stamp(game.elapsed), 12, Palette.TEXT_DIM)
	if p.brownout:
		var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		_t(Vector2(size.x * 0.5 - 60, 20), "ПРОСАДКА СЕТИ", 12, Color(Palette.ALERT, 0.35 + flash * 0.65))

func _draw_network() -> void:
	var p: PowerNet = game.power
	var rows: Array = p.machines
	var h := 24.0 * rows.size() + 26.0
	var r := Rect2(14, 42, 330, h)
	_panel(r, "СЕТЬ СТАНЦИИ")
	var y := r.position.y + 30.0
	var idx := 0
	for m in rows:
		var key := ""
		if m.role != Machine.Role.BATTERY:
			idx += 1
			key = str(idx)
		var col := Palette.TEXT
		if not m.repaired():
			col = Palette.TEXT_DIM
		elif not m.enabled:
			col = Palette.TEXT_DIM
		elif m.role == Machine.Role.GENERATOR and m.fuel <= 0.0:
			col = Palette.ALERT
		elif m.role != Machine.Role.GENERATOR and m.role != Machine.Role.BATTERY and m.powered_frac < 0.98:
			col = Palette.ALERT
		elif m.repaired():
			col = Palette.OK if m.role != Machine.Role.LOAD else Palette.TEXT

		# клавиша тумблера
		if key != "":
			var kr := Rect2(r.position.x + 7, y - 11, 14, 14)
			draw_rect(kr, Color(Palette.METAL, 0.8 if m.enabled and m.repaired() else 0.3), true)
			draw_rect(kr, Color(Palette.METAL_LIGHT, 0.5), false, 1.0)
			_t(kr.position + Vector2(4, 11), key, 10, Palette.TEXT)
		_t(Vector2(r.position.x + 28, y), m.code, 12, col)
		_t(Vector2(r.position.x + 92, y), m.status(), 11, col)

		var kw := ""
		match m.role:
			Machine.Role.GENERATOR:
				kw = "+%4.1f" % (m.rated_kw * m.load_frac if m.online() else 0.0)
			Machine.Role.BATTERY:
				var flow: float = p.to_battery - p.from_battery
				kw = "%+5.1f" % flow
			_:
				kw = "-%4.1f" % (m.rated_kw * m.powered_frac)
		_t(Vector2(r.position.x + 196, y), kw, 12, col)

		# мини-шкала: топливо / заряд / цикл / питание
		var v := 0.0
		var bc := Palette.AMBER
		match m.role:
			Machine.Role.GENERATOR:
				v = m.fuel / m.fuel_max
				bc = Palette.AMBER if v > 0.2 else Palette.ALERT
			Machine.Role.BATTERY:
				v = m.charge / m.charge_max
				bc = Palette.SIGNAL
			Machine.Role.PROCESSOR:
				v = float(m.hopper) / float(m.hopper_max)
				bc = Palette.RUST.lerp(Palette.AMBER, 0.5)
			_:
				v = m.powered_frac
				bc = Palette.AMBER if v > 0.9 else Palette.ALERT
		if not m.repaired():
			var done := 0
			for f in m.filled:
				if f:
					done += 1
			v = float(done) / float(maxi(m.slots.size(), 1))
			bc = Palette.TEXT_DIM
		_bar(Rect2(r.position.x + 244, y - 9, 78, 10), v, bc)
		y += 24.0

func _draw_balance() -> void:
	var p: PowerNet = game.power
	var top := 42.0 + 24.0 * p.machines.size() + 26.0 + 8.0
	var r := Rect2(14, top, 330, 96)
	_panel(r, "БАЛАНС МОЩНОСТИ")
	var x := r.position.x + 10
	var y := r.position.y + 32
	_t(Vector2(x, y), "ВЫДАЧА", 11, Palette.TEXT_DIM)
	_bar(Rect2(x + 74, y - 9, 150, 10), p.supply / 14.0, Palette.AMBER)
	_t(Vector2(x + 234, y), "%5.1f кВт" % p.supply, 11, Palette.TEXT)
	y += 20
	_t(Vector2(x, y), "СПРОС", 11, Palette.TEXT_DIM)
	_bar(Rect2(x + 74, y - 9, 150, 10), p.demand / 20.0, Palette.ALERT if p.brownout else Palette.TEXT_DIM)
	_t(Vector2(x + 234, y), "%5.1f кВт" % p.demand, 11, Palette.TEXT)
	y += 20
	var bat: Machine = p.battery
	_t(Vector2(x, y), "БАТАРЕЯ", 11, Palette.TEXT_DIM)
	if bat != null and bat.repaired():
		_bar(Rect2(x + 74, y - 9, 150, 10), bat.charge / bat.charge_max, Palette.SIGNAL)
		var minutes := p.battery_minutes()
		var tail := "%4.1f кВт·мин" % bat.charge
		if minutes < 900.0:
			tail = "хватит ~%0.1f мин" % minutes
		_t(Vector2(x + 234, y), tail, 11, Palette.TEXT)
	else:
		_bar(Rect2(x + 74, y - 9, 150, 10), 0.0, Palette.SIGNAL)
		_t(Vector2(x + 234, y), "не собрана", 11, Palette.TEXT_DIM)

func _draw_right() -> void:
	var w := 262.0
	var r := Rect2(size.x - w - 14, 42, w, 108)
	_panel(r, "ГРУЗ И ЦЕЛЬ")
	var pl: Player = game.player
	var x := r.position.x + 10
	var y := r.position.y + 32
	if pl.carried != null and is_instance_valid(pl.carried):
		_t(Vector2(x, y), "В РУКАХ", 11, Palette.TEXT_DIM)
		_t(Vector2(x + 76, y), "%s · %.0f кг" % [pl.carried.label(), pl.carried.mass], 12, Part.tint_of(pl.carried.kind))
	else:
		_t(Vector2(x, y), "В РУКАХ", 11, Palette.TEXT_DIM)
		_t(Vector2(x + 76, y), "пусто", 12, Palette.TEXT_DIM)
	y += 22
	_t(Vector2(x, y), "ЦЕЛЬ", 11, Palette.TEXT_DIM)
	if pl.target is Machine:
		var m: Machine = pl.target
		_t(Vector2(x + 76, y), "%s · %s" % [m.code, m.label], 12, Palette.TEXT)
		y += 18
		var need: Array = m.needs()
		if need.is_empty():
			_t(Vector2(x + 10, y), "требований нет", 11, Palette.OK)
		else:
			_t(Vector2(x + 10, y), "нужно: " + ", ".join(need), 11, Palette.AMBER)
	elif pl.target is Part:
		var pt: Part = pl.target
		_t(Vector2(x + 76, y), "%s · %.0f кг" % [pt.label(), pt.mass], 12, Part.tint_of(pt.kind))
	else:
		_t(Vector2(x + 76, y), "—", 12, Palette.TEXT_DIM)
	y = r.position.y + 94
	_t(Vector2(x, y), "СТАБИЛИЗАТОР", 11, Palette.TEXT_DIM)
	_bar(Rect2(x + 106, y - 9, 130, 10), pl.rcs, Palette.SIGNAL if not pl.rcs_active else Palette.AMBER)

	# задача смены
	var r2 := Rect2(r.position.x, r.position.y + r.size.y + 8, w, 74)
	_panel(r2, "ЗАДАНИЕ")
	var x2 := r2.position.x + 10
	var y2 := r2.position.y + 30
	_t(Vector2(x2, y2), "удержать канал РТР-9", 11, Palette.TEXT)
	y2 += 18
	_bar(Rect2(x2, y2 - 9, 160, 10), game.uplink_uptime / game.uplink_goal, Palette.SIGNAL)
	_t(Vector2(x2 + 170, y2), "%d / %d с" % [int(game.uplink_uptime), int(game.uplink_goal)], 11, Palette.TEXT)
	y2 += 18
	_t(Vector2(x2, y2), "узлов собрано: %d / %d" % [game.repaired_count(), game.power.machines.size()], 11, Palette.TEXT_DIM)

func _draw_log() -> void:
	var r := Rect2(14, size.y - 148, 566, 100)
	_panel(r, "ЖУРНАЛ СМЕНЫ")
	var lines: Array = game.feed.tail(5)
	var y := r.position.y + 32
	for i in lines.size():
		var e: Dictionary = lines[i]
		var fade := 1.0 if i == lines.size() - 1 else 0.72
		var col := Palette.TEXT
		match int(e["tone"]):
			LogFeed.Tone.GOOD: col = Palette.OK
			LogFeed.Tone.BAD: col = Palette.ALERT
		_t(Vector2(r.position.x + 8, y), game.feed.stamp(e["t"]), 10, Color(Palette.TEXT_DIM, fade))
		_t(Vector2(r.position.x + 46, y), str(e["text"]), 11, Color(col, fade), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56)
		y += 14

func _draw_radar() -> void:
	var rad := 84.0
	var c := Vector2(size.x - rad - 22, size.y - rad - 26)
	draw_circle(c, rad, Color(Palette.VOID, 0.9))
	draw_arc(c, rad, 0, TAU, 48, Color(Palette.METAL, 0.9), 1.0)
	draw_arc(c, rad * 0.5, 0, TAU, 32, Color(Palette.METAL, 0.45), 1.0)
	draw_line(c - Vector2(rad, 0), c + Vector2(rad, 0), Color(Palette.METAL, 0.3), 1.0)
	draw_line(c - Vector2(0, rad), c + Vector2(0, rad), Color(Palette.METAL, 0.3), 1.0)
	_t(c + Vector2(-rad, -rad - 6), "ОБЗОР  %d м" % int(game.radar_range), 10, Palette.TEXT_DIM)

	var pl: Player = game.player
	var origin := pl.torso.global_position
	var yaw: float = game.camera_rig.yaw
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var rgt := Vector2(cos(yaw), -sin(yaw))
	var k: float = rad / game.radar_range

	for m in game.power.machines:
		var rel: Vector3 = m.global_position - origin
		var v := Vector2(rel.x, rel.z)
		var p: Vector2 = c + Vector2(v.dot(rgt), -v.dot(fwd)) * k
		if p.distance_to(c) > rad - 3.0:
			p = c + (p - c).normalized() * (rad - 3.0)
		var col: Color = Palette.AMBER if m.online() else (Palette.TEXT_DIM if m.repaired() else Palette.RUST)
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), col, true)

	for part in game.world.salvage_parts:
		if not is_instance_valid(part):
			continue
		var rel2: Vector3 = part.global_position - origin
		var v2 := Vector2(rel2.x, rel2.z)
		if v2.length() > game.radar_range:
			continue
		var p2: Vector2 = c + Vector2(v2.dot(rgt), -v2.dot(fwd)) * k
		draw_rect(Rect2(p2 - Vector2(1.5, 1.5), Vector2(3, 3)), Color(Part.tint_of(part.kind), 0.85), true)

	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(-4, 5), c + Vector2(4, 5)]), Palette.SIGNAL)

func _draw_reticle() -> void:
	var c := size * 0.5
	var pl: Player = game.player
	var hot: bool = pl.target != null
	var col: Color = Palette.AMBER if hot else Color(Palette.TEXT_DIM, 0.6)
	draw_line(c - Vector2(7, 0), c - Vector2(2, 0), col, 1.0)
	draw_line(c + Vector2(2, 0), c + Vector2(7, 0), col, 1.0)
	draw_line(c - Vector2(0, 7), c - Vector2(0, 2), col, 1.0)
	draw_line(c + Vector2(0, 2), c + Vector2(0, 7), col, 1.0)
	if not hot:
		return
	var prompt := ""
	if pl.target is Part:
		if pl.carried == null:
			prompt = "ЛКМ — взять: %s" % (pl.target as Part).label()
		else:
			prompt = "ЛКМ — положить"
	elif pl.target is Machine:
		var m: Machine = pl.target
		if pl.carried != null and m.accepts(pl.carried.kind):
			prompt = "E — установить: %s" % pl.carried.label()
		elif pl.carried != null:
			prompt = "%s: %s не подходит" % [m.code, pl.carried.label()]
		else:
			var need: Array = m.needs()
			prompt = "%s · %s" % [m.code, "готов" if need.is_empty() else "нужно: " + ", ".join(need)]
	var w := font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_rect(Rect2(c.x - w * 0.5 - 8, c.y + 22, w + 16, 20), Color(Palette.VOID, 0.7), true)
	_t(Vector2(c.x - w * 0.5, c.y + 36), prompt, 12, Palette.TEXT)

func _draw_hints() -> void:
	var hints := "WASD движение · SHIFT бег · ПРОБЕЛ стабилизатор · ЛКМ взять/положить · E установить · 1…6 тумблеры узлов · TAB обзор · M звук · ESC курсор"
	var w := font.get_string_size(hints, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	_t(Vector2((size.x - w) * 0.5, size.y - 14), hints, 11, Color(Palette.TEXT_DIM, 0.85))

func _draw_closed() -> void:
	var r := Rect2(size.x * 0.5 - 250, size.y * 0.5 - 70, 500, 104)
	draw_rect(r, Color(Palette.VOID, 0.9), true)
	draw_rect(r, Palette.AMBER, false, 1.0)
	_t(Vector2(r.position.x + 20, r.position.y + 36), "КАНАЛ УСТОЙЧИВ. НАРЯД ЗАКРЫТ.", 18, Palette.AMBER)
	_t(Vector2(r.position.x + 20, r.position.y + 62), "Станция передаёт данные. Смена продолжается: узлов, которые ещё", 12, Palette.TEXT)
	_t(Vector2(r.position.x + 20, r.position.y + 80), "можно собрать, на этом участке достаточно.", 12, Palette.TEXT)
