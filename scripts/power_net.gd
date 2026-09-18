class_name PowerNet
extends Node

## Сеть станции считается непрерывно, в реальном времени: генератор жжёт
## топливо, батарея сглаживает пики, потребители получают долю от того, что
## есть. Дефицит — это не проигрыш, а просадка: свет тускнеет, переработчик
## замедляется, канал рвётся. Всё это отыгрывается обратно, как только
## оператор что-нибудь выключит или принесёт ячейку.

signal brownout_changed(active: bool)

var machines: Array = []
var battery: Machine = null

var supply := 0.0        # доступно от генераторов, кВт
var demand := 0.0        # запрошено потребителями, кВт
var served := 0.0        # фактически выдано, кВт
var from_battery := 0.0  # из батареи, кВт
var to_battery := 0.0    # в батарею, кВт
var frac := 1.0          # доля покрытия спроса
var brownout := false

func register(m: Machine) -> void:
	machines.append(m)
	if m.role == Machine.Role.BATTERY:
		battery = m

func toggleable() -> Array:
	var out := []
	for m in machines:
		if m.role != Machine.Role.BATTERY:
			out.append(m)
	return out

func _process(delta: float) -> void:
	tick(delta)
	for m in machines:
		m.tick(delta)

func tick(delta: float) -> void:
	supply = 0.0
	demand = 0.0
	from_battery = 0.0
	to_battery = 0.0

	var gens: Array = []
	for m in machines:
		match m.role:
			Machine.Role.GENERATOR:
				if m.online():
					supply += m.rated_kw
					gens.append(m)
				else:
					m.load_frac = 0.0
			Machine.Role.BATTERY:
				pass
			_:
				if m.online():
					demand += m.rated_kw

	var bat_ok: bool = battery != null and battery.repaired() and battery.enabled

	if demand <= supply:
		served = demand
		frac = 1.0
		if bat_ok and battery.charge < battery.charge_max:
			to_battery = minf(supply - demand, battery.charge_rate)
			battery.charge = minf(battery.charge_max, battery.charge + to_battery * delta / 60.0)
	else:
		if bat_ok and battery.charge > 0.0:
			from_battery = minf(demand - supply, battery.discharge_max)
			battery.charge = maxf(0.0, battery.charge - from_battery * delta / 60.0)
		served = supply + from_battery
		frac = served / maxf(demand, 0.001)

	# загрузка генераторов и расход топлива
	var gen_load: float = served - from_battery + to_battery
	for m in gens:
		m.load_frac = clampf(gen_load / maxf(supply, 0.001), 0.0, 1.0)
		var had_fuel: bool = m.fuel > 0.0
		m.fuel = maxf(0.0, m.fuel - m.burn_per_sec * m.load_frac * delta)
		if m.fuel <= 0.0 and had_fuel:
			m.event.emit("%s: топливо кончилось. Сеть переходит на батарею и надежду." % m.code, LogFeed.Tone.BAD)

	# доля мощности каждому потребителю
	for m in machines:
		if m.role == Machine.Role.GENERATOR or m.role == Machine.Role.BATTERY:
			m.powered_frac = 1.0 if m.online() else 0.0
		else:
			m.powered_frac = frac if m.online() else 0.0

	var now: bool = demand > 0.0 and frac < 0.98
	if now != brownout:
		brownout = now
		brownout_changed.emit(brownout)

## Сколько минут батарея продержит текущий дефицит (для интерфейса).
func battery_minutes() -> float:
	if battery == null or not battery.repaired():
		return 0.0
	if from_battery <= 0.01:
		return 999.0
	return battery.charge / from_battery
