extends Node3D

## Точка сборки среза: свет и воздух, мир, сеть, ремонтник, камера, звук.
## Ввод регистрируется здесь же — проект открывается в любой сборке Godot 4
## без ручной настройки InputMap.

const WORLD_SEED := 20260917

var power: PowerNet
var world: WorldBuilder
var player: Player
var camera_rig: CameraRig
var sound: SoundDesk
var feed: LogFeed
var hud

var elapsed := 0.0
var uplink_uptime := 0.0
var uplink_goal := 90.0
var contract_closed := false
var radar_range := 70.0
var _radar_steps := [40.0, 70.0, 130.0]
var _radar_i := 1
var _flags := {}

func _ready() -> void:
	_setup_input()

	feed = LogFeed.new()
	feed.name = "LogFeed"
	add_child(feed)

	_build_sky()

	power = PowerNet.new()
	power.name = "PowerNet"
	add_child(power)
	power.brownout_changed.connect(_on_brownout)

	world = WorldBuilder.new()
	world.name = "World"
	add_child(world)
	world.build(power, WORLD_SEED)
	for m in world.machines:
		m.event.connect(_on_machine_event)
		m.ejected.connect(_on_machine_ejected)

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.feed = feed
	player.setup(world, world.spawn_point)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.setup(player)
	player.cam = camera_rig

	sound = SoundDesk.new()
	sound.name = "SoundDesk"
	add_child(sound)

	hud = get_node("UI/Hud")
	hud.bind(self)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_brief()

# ------------------------------------------------------------------- ввод ---

func _setup_input() -> void:
	_action("move_forward", [KEY_W, KEY_UP])
	_action("move_back", [KEY_S, KEY_DOWN])
	_action("move_left", [KEY_A, KEY_LEFT])
	_action("move_right", [KEY_D, KEY_RIGHT])
	_action("sprint", [KEY_SHIFT])
	_action("stabilize", [KEY_SPACE])
	_action("interact", [KEY_E])
	_action("grab", [KEY_F], MOUSE_BUTTON_LEFT)
	_action("radar", [KEY_TAB])
	_action("mute", [KEY_M])

func _action(action: String, keys: Array, mouse := -1) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	if mouse >= 0:
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse
		InputMap.action_add_event(action, mb)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)
			return
		var idx: int = event.physical_keycode - KEY_1
		if idx >= 0 and idx < 9:
			toggle_machine(idx)
			return
	if event.is_action_pressed("grab"):
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return
		var had := player.carried != null
		player.grab_or_drop()
		if not had and player.carried != null:
			sound.pickup()
	elif event.is_action_pressed("interact"):
		player.interact()
	elif event.is_action_pressed("radar"):
		_radar_i = (_radar_i + 1) % _radar_steps.size()
		radar_range = _radar_steps[_radar_i]
	elif event.is_action_pressed("mute"):
		sound.toggle_mute()

## Тумблер узла по номеру в сети (клавиши 1…6). Открыт и для автопилота демо.
func toggle_machine(idx: int) -> void:
	var list: Array = power.toggleable()
	if idx >= list.size():
		return
	var m: Machine = list[idx]
	if not m.repaired():
		feed.push("%s: тумблер есть, узла ещё нет." % m.code, LogFeed.Tone.PLAIN)
		return
	m.enabled = not m.enabled
	feed.push("%s: %s." % [m.code, "включён" if m.enabled else "отключён оператором"], LogFeed.Tone.PLAIN)
	sound.blip(196.0 if m.enabled else 147.0, 0.09, 0.22)

# ------------------------------------------------------------------- цикл ---

func _process(delta: float) -> void:
	elapsed += delta
	var up := _uplink()
	if up != null and up.online() and up.powered_frac > 0.95:
		uplink_uptime = minf(uplink_goal, uplink_uptime + delta)
		if uplink_uptime >= uplink_goal and not contract_closed:
			_close_contract()
	else:
		# прощающая механика: накопленное время утекает медленно
		uplink_uptime = maxf(0.0, uplink_uptime - delta * 0.15)
	sound.set_drive(clampf(power.served / 14.0, 0.0, 1.0))
	_commentary()

func repaired_count() -> int:
	var n := 0
	for m in power.machines:
		if m.repaired():
			n += 1
	return n

func _uplink() -> Machine:
	for m in power.machines:
		if m.is_uplink:
			return m
	return null

func _generator() -> Machine:
	for m in power.machines:
		if m.role == Machine.Role.GENERATOR:
			return m
	return null

# --------------------------------------------------------- свет и воздух ---

func _build_sky() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.VOID
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.FOG.lerp(Palette.METAL_LIGHT, 0.55)
	env.ambient_light_energy = 1.15

	# туман — главный инструмент кадра: он же и ограничитель видимости,
	# и причина, по которой свет маяков имеет смысл
	env.fog_enabled = true
	env.fog_light_color = Palette.GROUND_HIGH.lerp(Palette.METAL_LIGHT, 0.4)
	env.fog_light_energy = 1.5
	env.fog_density = 0.022
	env.fog_aerial_perspective = 0.25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.024
	env.volumetric_fog_albedo = Palette.METAL.lerp(Color.WHITE, 0.15)
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.8

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.85
	env.ssao_enabled = true
	env.ssao_intensity = 1.7
	env.ssao_radius = 1.1

	# приглушённая палитра закрепляется на уровне кадра, а не только материалов
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.62
	env.adjustment_contrast = 1.12
	env.adjustment_brightness = 0.99

	we.environment = env
	add_child(we)

	var dl := DirectionalLight3D.new()
	dl.name = "Sun"
	dl.light_color = Color("5c6d78")
	dl.light_energy = 0.9
	dl.shadow_enabled = true
	dl.directional_shadow_max_distance = 140.0
	dl.light_angular_distance = 1.4
	dl.rotation = Vector3(deg_to_rad(-22.0), deg_to_rad(126.0), 0.0)
	add_child(dl)

# --------------------------------------------------------------- сигналы ---

func _on_machine_event(text: String, tone: int) -> void:
	feed.push(text, tone)
	if tone == LogFeed.Tone.GOOD:
		sound.seated()
	elif tone == LogFeed.Tone.BAD:
		sound.blip(110.0, 0.3, 0.3, true)

func _on_machine_ejected(kind: int, pos: Vector3, dir: Vector3) -> void:
	var p := world.add_loose_part(kind, pos)
	p.apply_central_impulse(dir * p.mass * 0.5)
	sound.eject()

func _on_brownout(active: bool) -> void:
	sound.brownout(active)
	if active:
		camera_rig.shake(0.55)
		feed.push("Просадка сети: спрос выше выдачи. Свет тускнеет — атмосферно, но не по регламенту.", LogFeed.Tone.BAD)
	else:
		feed.push("Сеть выровнялась. Никто, кроме журнала, этого не заметил.", LogFeed.Tone.GOOD)

func _close_contract() -> void:
	contract_closed = true
	sound.fanfare()
	feed.push("Канал держится %d секунд. Наряд 4417-Б закрыт." % int(uplink_goal), LogFeed.Tone.GOOD)
	feed.push("Где-то в четырёхстах световых годах в таблице появилась галочка. Премия не предусмотрена.", LogFeed.Tone.PLAIN)

# ------------------------------------------------ голос смены (ироничный) ---

func _brief() -> void:
	feed.push("Смена начата. Объект: станция «Тишина-9», по акту — «незначительные замечания».")
	feed.push("Замечание первое: половины станции на месте нет.")
	feed.push("Задание: собрать узлы, поднять сеть, удержать канал ретранслятора %d секунд." % int(uplink_goal))

func _once(key: String) -> bool:
	if _flags.has(key):
		return false
	_flags[key] = true
	return true

func _commentary() -> void:
	var gen := _generator()
	if power.supply > 0.0 and _once("first_power"):
		feed.push("ГЕН-4 вышел на обороты. Станция вспомнила, что такое ток.", LogFeed.Tone.GOOD)
	if gen.repaired() and gen.fuel <= 0.0 and _once("dry"):
		feed.push("ГЕН-4 просит ячейку, ячейки делает П-2, а П-2 просит ток. Цикл, знакомый любому подрядчику.", LogFeed.Tone.PLAIN)
	if power.battery != null and power.battery.repaired() and _once("bat"):
		feed.push("БНК-1 в строю: пики сети теперь сглаживаются, а не обсуждаются.", LogFeed.Tone.GOOD)
	var beacons := 0
	for m in power.machines:
		if m.label == "маяк" and m.online() and m.powered_frac > 0.9:
			beacons += 1
	if beacons >= 3 and _once("beacons"):
		feed.push("Все три маяка горят. Туман по-прежнему на месте, но теперь он хотя бы освещён.", LogFeed.Tone.GOOD)
	if uplink_uptime > 1.0 and _once("uplink_on"):
		feed.push("РТР-9 поймал канал. Осталось не мешать ему %d секунд." % int(uplink_goal), LogFeed.Tone.PLAIN)
