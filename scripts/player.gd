class_name Player
extends Node3D

## Ремонтник. Тело собрано из твёрдых тел и целиком управляется силами:
##  * торс висит на пружинном регуляторе высоты бедра и держится прямо моментом;
##  * ступни — отдельные тела, которые ПД-регулятор ведёт по фазе шага,
##    поэтому они реально задевают камни и проваливаются в ямы;
##  * руки и голова — тоже тела, которые тянутся к своим целям (как моторы
##    активной ragdoll-модели), а не жёстко прикручены к торсу.
## Запечённых анимаций нет: поза каждый кадр — результат сил.
##
## Шарниры (PinJoint3D) здесь сознательно не используются: в Godot Physics
## они либо гасят качание почти до нуля, либо расходятся при малом damping.

const MASS := 62.0
const WALK := 3.9
const SPRINT := 1.65
const HIP_H := 1.10          # высота торса над грунтом
const FOOT_MASS := 2.2
const ARM_LEN := 0.62
const REACH := 3.4

# слои: 1 мир, 2 торс, 4 конечности, 8 предметы
const LAYER_TORSO := 2
const MASK_TORSO := 9
const LAYER_LIMB := 4
const MASK_LIMB := 1

var torso: RigidBody3D
var head: RigidBody3D
var arms: Array = []
var feet: Array = []
var leg_upper: Array = []
var leg_lower: Array = []
var lamp: SpotLight3D

var cam                      # CameraRig, без типа — чтобы не плодить циклы
var feed: LogFeed
var world: WorldBuilder

var carried: Part = null
var target: Node = null      # то, на что наведён курсор (Part или Machine)
var target_dist := 0.0
var grounded := false
var gait := 0.0
var speed_h := 0.0
var rcs := 1.0               # заряд стабилизатора, 0..1
var rcs_active := false
var _spawn := Vector3.ZERO
var _gravity := 7.4

func setup(w: WorldBuilder, spawn: Vector3) -> void:
	world = w
	_spawn = spawn
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 7.4)
	_build_torso(spawn)
	_build_head()
	_build_arms()
	_build_legs()

# ------------------------------------------------------------- сборка тела ---

func _build_torso(spawn: Vector3) -> void:
	torso = RigidBody3D.new()
	torso.name = "Torso"
	torso.mass = MASS
	torso.collision_layer = LAYER_TORSO
	torso.collision_mask = MASK_TORSO
	torso.can_sleep = false
	torso.angular_damp = 1.2
	torso.linear_damp = 0.05
	torso.position = spawn + Vector3(0, HIP_H, 0)
	add_child(torso)

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.5
	cs.shape = cap
	torso.add_child(cs)

	var suit := Palette.mat(Palette.METAL.darkened(0.1), 0.72, 0.4)
	var chest := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.54, 0.7, 0.34)
	chest.mesh = cm
	chest.material_override = suit
	chest.position = Vector3(0, 0.12, 0)
	torso.add_child(chest)

	var hips := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.46, 0.26, 0.3)
	hips.mesh = hm
	hips.material_override = suit
	hips.position = Vector3(0, -0.36, 0)
	torso.add_child(hips)

	var pack := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.38, 0.44, 0.2)
	pack.mesh = pm
	pack.material_override = Palette.mat(Palette.METAL.darkened(0.3), 0.85, 0.5)
	pack.position = Vector3(0, 0.1, 0.26)
	torso.add_child(pack)

	# единственное тёплое пятно на костюме: рабочая маркировка на груди
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.34, 0.06, 0.03)
	stripe.mesh = sm
	stripe.material_override = Palette.glow(Palette.AMBER, 0.9)
	stripe.position = Vector3(0, 0.08, -0.175)
	torso.add_child(stripe)

	var tab := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.06, 0.2, 0.03)
	tab.mesh = tm
	tab.material_override = Palette.glow(Palette.AMBER, 0.9)
	tab.position = Vector3(-0.2, -0.05, -0.175)
	torso.add_child(tab)

	# наплечный фонарь: висит на торсе, значит качается вместе с ним
	lamp = SpotLight3D.new()
	lamp.light_color = Palette.AMBER.lerp(Color.WHITE, 0.3)
	lamp.light_energy = 8.5
	lamp.spot_range = 30.0
	lamp.spot_angle = 38.0
	lamp.spot_attenuation = 0.9
	lamp.shadow_enabled = true
	lamp.light_volumetric_fog_energy = 1.6
	lamp.position = Vector3(0.26, 0.36, -0.12)
	torso.add_child(lamp)

func _limb(nm: String, mass: float, shape: Shape3D, mesh: Mesh, mat: Material, pos: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = nm
	b.mass = mass
	b.collision_layer = LAYER_LIMB
	b.collision_mask = MASK_LIMB
	b.can_sleep = false
	b.position = pos
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	b.add_child(mi)
	add_child(b)
	return b

func _build_head() -> void:
	var ss := SphereShape3D.new()
	ss.radius = 0.17
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.34
	head = _limb("Head", 4.5, ss, sm, Palette.mat(Palette.METAL_LIGHT.darkened(0.15), 0.6, 0.5),
		torso.position + Vector3(0, 0.6, 0))
	head.angular_damp = 2.0
	head.linear_damp = 0.3
	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.24, 0.11, 0.06)
	visor.mesh = vm
	visor.material_override = Palette.glow(Palette.SIGNAL, 1.8)
	visor.position = Vector3(0, 0.01, -0.15)
	head.add_child(visor)

func _build_arms() -> void:
	var mat := Palette.mat(Palette.METAL.darkened(0.05), 0.75, 0.4)
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var cap := CapsuleShape3D.new()
		cap.radius = 0.09
		cap.height = ARM_LEN
		var cm := CapsuleMesh.new()
		cm.radius = 0.09
		cm.height = ARM_LEN
		var a := _limb("Arm%d" % i, 3.2, cap, cm, mat,
			torso.position + Vector3(side * 0.33, 0.27 - ARM_LEN * 0.5, 0))
		a.angular_damp = 1.2
		a.linear_damp = 0.3
		arms.append(a)

func _build_legs() -> void:
	var boot_mat := Palette.mat(Palette.METAL.darkened(0.25), 0.9, 0.35)
	var leg_mat := Palette.mat(Palette.METAL.darkened(0.12), 0.8, 0.4)
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var ss := SphereShape3D.new()
		ss.radius = 0.16
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		sm.radial_segments = 10
		sm.rings = 5
		var f := _limb("Foot%d" % i, FOOT_MASS, ss, sm, boot_mat,
			torso.position + Vector3(side * 0.17, -HIP_H + 0.16, 0))
		f.angular_damp = 4.0
		f.linear_damp = 0.2
		f.continuous_cd = true
		feet.append(f)
		leg_upper.append(_leg_mesh(leg_mat, 0.1))
		leg_lower.append(_leg_mesh(leg_mat, 0.085))

func _leg_mesh(mat: Material, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 1.0
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	add_child(mi)
	return mi

# ---------------------------------------------------------------- движение ---

func _physics_process(delta: float) -> void:
	if torso == null or cam == null:
		return
	if torso.global_position.y < -40.0:
		_recover()
		return

	var vel := torso.linear_velocity
	speed_h = Vector2(vel.x, vel.z).length()
	_ground_check()
	_drive(vel)
	_upright()
	_gait(delta)
	_arms()
	_head_follow()
	_carry()
	_rcs(delta)
	_scan()
	_draw_legs()

func _ground_check() -> void:
	var from := torso.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (HIP_H + 1.1))
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	grounded = not hit.is_empty()
	if grounded:
		# пружина бедра: тело стоит, но продолжает быть телом — оно
		# проседает на спусках и подпрыгивает на кочках
		var dist: float = from.y - (hit["position"] as Vector3).y
		var err := HIP_H - dist
		var a := _gravity + clampf(err * 120.0 - torso.linear_velocity.y * 14.0, -6.0, 34.0)
		torso.apply_central_force(Vector3.UP * a * MASS)

func _drive(vel: Vector3) -> void:
	var input := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		input += cam.forward()
	if Input.is_action_pressed("move_back"):
		input -= cam.forward()
	if Input.is_action_pressed("move_left"):
		input -= cam.right()
	if Input.is_action_pressed("move_right"):
		input += cam.right()
	input.y = 0.0
	var wish := input.normalized()
	var speed := WALK * (SPRINT if Input.is_action_pressed("sprint") else 1.0)
	if carried != null:
		speed *= 1.0 - clampf(carried.mass / 90.0, 0.0, 0.42)   # груз чувствуется
	var want := wish * speed
	var flat := Vector3(vel.x, 0, vel.z)
	var authority := 9.0 if grounded else 1.8
	var f := (want - flat) * MASS * authority
	torso.apply_central_force(f.limit_length(MASS * 26.0))

	# разворот корпуса вслед за камерой
	var face: Vector3 = wish if wish.length() > 0.1 else cam.forward()
	var cur := -torso.global_transform.basis.z
	cur.y = 0.0
	cur = cur.normalized()
	if cur.length() > 0.01:
		var err := atan2(cur.cross(face).y, cur.dot(face))
		torso.apply_torque(Vector3.UP * (err * 300.0 - torso.angular_velocity.y * 75.0))

func _upright() -> void:
	var up := torso.global_transform.basis.y
	var axis := up.cross(Vector3.UP)
	var av := torso.angular_velocity
	var damp := Vector3(av.x, 0, av.z)
	torso.apply_torque(axis * 1500.0 - damp * 190.0)

func _gait(delta: float) -> void:
	gait += delta * (1.1 + speed_h * 2.3)
	var basis := torso.global_transform.basis
	var move_dir := Vector3(torso.linear_velocity.x, 0, torso.linear_velocity.z)
	if move_dir.length() < 0.3:
		move_dir = -basis.z
		move_dir.y = 0.0
	move_dir = move_dir.normalized()
	var stride := clampf(speed_h * 0.115, 0.0, 0.4)

	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var phase := gait + (0.0 if i == 0 else PI)
		var hip := torso.global_position + basis * Vector3(side * 0.17, -0.46, 0)
		var along := cos(phase) * stride
		var lift := maxf(0.0, sin(phase)) * (0.04 + stride * 0.6)
		var spot := hip + move_dir * along
		var gy := world.height_at(spot.x, spot.z) + 0.16 + lift
		var aim := Vector3(spot.x, gy, spot.z)

		var f: RigidBody3D = feet[i]
		var err := aim - f.global_position
		var force := (err * 560.0 - f.linear_velocity * 34.0) * FOOT_MASS
		force += Vector3.UP * FOOT_MASS * _gravity
		f.apply_central_force(force.limit_length(FOOT_MASS * 420.0))

## Руки: висят вдоль тела и качаются в противофазе шагу, а с грузом тянутся
## к нему. Это силы, а не кинематика: рука отстаёт на разгоне и цепляет мир.
func _arms() -> void:
	var basis := torso.global_transform.basis
	var carrying: bool = carried != null and is_instance_valid(carried)
	var hold := _hold_point()
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var a: RigidBody3D = arms[i]
		var anchor := torso.global_position + basis * Vector3(side * 0.33, 0.27, 0)
		var hand: Vector3
		if carrying:
			hand = hold + basis * Vector3(side * 0.19, 0.04, 0.0)
		else:
			var phase := gait + (PI if i == 0 else 0.0)   # противофаза одноимённой ноге
			var swing := sin(phase) * clampf(speed_h * 0.1, 0.0, 0.36)
			hand = anchor + (basis * Vector3(side * 0.12, -1.0, swing * 2.2)).normalized() * ARM_LEN

		var want := (anchor + hand) * 0.5
		var f := ((want - a.global_position) * 300.0 - a.linear_velocity * 24.0) * a.mass
		f += Vector3.UP * a.mass * _gravity
		a.apply_central_force(f.limit_length(a.mass * 300.0))

		var along := (hand - anchor).normalized()
		# коэффициенты рассчитаны по моменту инерции капсулы, а не по массе
		var tq := a.global_transform.basis.y.cross(-along) * 14.0 - a.angular_velocity * 2.0
		a.apply_torque(tq)

func _head_follow() -> void:
	var basis := torso.global_transform.basis
	var want := torso.global_position + basis * Vector3(0, 0.6, 0)
	var f := ((want - head.global_position) * 360.0 - head.linear_velocity * 28.0) * head.mass
	f += Vector3.UP * head.mass * _gravity
	head.apply_central_force(f.limit_length(head.mass * 300.0))
	var tq := head.global_transform.basis.z.cross(basis.z) * 7.5 - head.angular_velocity * 1.1
	head.apply_torque(tq)

## Ноги рисуются двухзвенной ИК между бедром и фактическим положением ступни:
## колено само сгибается, когда тело проседает.
func _draw_legs() -> void:
	var basis := torso.global_transform.basis
	var fwd := -basis.z
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var hip: Vector3 = torso.global_position + basis * Vector3(side * 0.17, -0.46, 0)
		var foot: Vector3 = (feet[i] as RigidBody3D).global_position
		var seg := 0.5
		var d := foot - hip
		var l := clampf(d.length(), 0.08, seg * 2.0 - 0.02)
		var mid := hip + d.normalized() * l * 0.5
		var out := sqrt(maxf(0.0, seg * seg - l * l * 0.25))
		var knee := mid + fwd * out
		_stretch(leg_upper[i], hip, knee)
		_stretch(leg_lower[i], knee, foot)

func _stretch(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := maxf(d.length(), 0.05)
	var y := d / l
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)

func _rcs(delta: float) -> void:
	rcs_active = false
	if Input.is_action_pressed("stabilize") and rcs > 0.02:
		rcs_active = true
		rcs = maxf(0.0, rcs - delta * 0.42)
		torso.apply_central_force(Vector3.UP * MASS * (_gravity + 6.5))
	else:
		# баллон дозаряжается сам, но рядом с работающим узлом — заметно быстрее
		var rate := 0.05
		if world != null:
			for m in world.machines:
				if m.online() and torso.global_position.distance_to(m.global_position) < 8.0:
					rate = 0.22
					break
		rcs = minf(1.0, rcs + delta * rate)

# --------------------------------------------------------------- работа рук ---

func _hold_point() -> Vector3:
	var basis := torso.global_transform.basis
	return torso.global_position + (-basis.z) * 0.85 + Vector3.UP * 0.02

func _carry() -> void:
	if carried == null:
		return
	if not is_instance_valid(carried):
		carried = null
		return
	var hold := _hold_point()
	var to := hold - carried.global_position
	if to.length() > 3.0:
		_say("Груз сорвался. Он лежит там, где лежал, — это единственное, в чём можно быть уверенным.", LogFeed.Tone.BAD)
		drop()
		return
	var f := (to * 78.0 - carried.linear_velocity * 12.0) * carried.mass
	f = f.limit_length(carried.mass * 150.0)
	carried.apply_central_force(f)
	# вращение груза гасит штатный angular_damp (см. grab_or_drop):
	# собственный момент, посчитанный по массе, расходился на лёгких деталях
	# отдача в тело: тяжёлая деталь реально тянет ремонтника вперёд
	torso.apply_central_force(-f * 0.2)

func _scan() -> void:
	target = null
	target_dist = 0.0
	var camera: Camera3D = cam.camera
	if camera == null:
		return
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 40.0)
	q.collision_mask = 9   # мир + предметы
	if carried != null and is_instance_valid(carried):
		q.exclude = [carried.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var col = hit["collider"]
	if col is Part or col is Machine:
		var d: float = torso.global_position.distance_to(hit["position"])
		if d <= REACH + (1.4 if col is Machine else 0.0):
			target = col
			target_dist = d

# ----------------------------------------------------------------- команды ---

func grab_or_drop() -> void:
	if carried != null:
		drop()
		return
	if target is Part:
		carried = target
		carried.gravity_scale = 0.3
		carried.angular_damp = 5.0
		_say("В руках: %s, %.0f кг." % [carried.label(), carried.mass], LogFeed.Tone.PLAIN)

func drop() -> void:
	if carried == null:
		return
	carried.gravity_scale = 1.0
	carried.angular_damp = 0.6
	carried = null

## E — поставить деталь в узел. Если детали нет, узел сообщает, чего ждёт.
func interact() -> bool:
	if not (target is Machine):
		if carried != null:
			drop()
			return true
		return false
	var m: Machine = target
	if carried == null:
		var need := m.needs()
		if need.is_empty():
			_say("%s: замечаний нет. Редкий случай." % m.code, LogFeed.Tone.PLAIN)
		else:
			_say("%s ждёт: %s." % [m.code, ", ".join(need)], LogFeed.Tone.PLAIN)
		return false
	if m.install(carried.kind):
		var used := carried
		carried = null
		used.queue_free()
		return true
	_say("%s: %s здесь не встанет." % [m.code, carried.label()], LogFeed.Tone.BAD)
	return false

func _recover() -> void:
	torso.linear_velocity = Vector3.ZERO
	torso.global_position = _spawn + Vector3(0, HIP_H + 0.4, 0)
	for i in 2:
		(feet[i] as RigidBody3D).global_position = torso.global_position + Vector3(0, -HIP_H + 0.16, 0)
	_say("Ремонтник извлечён из рельефа. Инвентарь на месте, достоинство — частично.", LogFeed.Tone.PLAIN)

func _say(text: String, tone: int) -> void:
	if feed != null:
		feed.push(text, tone)
