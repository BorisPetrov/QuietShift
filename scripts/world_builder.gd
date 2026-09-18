class_name WorldBuilder
extends Node3D

## Мир собирается кодом по фиксированному зерну: один и тот же участок
## каждый запуск, но параметры мира — числа, а не ручная расстановка.
## Это заготовка под открытый мир: та же функция сгенерирует любой участок.

const WORLD_SIZE := 220.0
const GRID := 96
const PLATEAU_R := 40.0

var rng := RandomNumberGenerator.new()
var _base := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var machines: Array = []
var salvage_parts: Array = []
var spawn_point := Vector3(0, 2, 12)

func build(power: PowerNet, world_seed: int) -> void:
	rng.seed = world_seed
	_base.seed = world_seed
	_base.frequency = 0.0075
	_base.fractal_octaves = 4
	_base.fractal_lacunarity = 2.1
	_ridge.seed = world_seed + 977
	_ridge.frequency = 0.031
	_ridge.fractal_octaves = 2

	_build_terrain()
	_build_bounds()
	_scatter_rocks()
	_build_wreck(Vector3(-62, 0, -74))
	_build_station(power)
	_build_salvage()
	spawn_point = Vector3(0, height_at(0, 12) + 1.4, 12)

## Высота грунта в точке. Ею пользуется и меш, и походка игрока.
func height_at(x: float, z: float) -> float:
	var h := _base.get_noise_2d(x, z) * 11.0
	h += _ridge.get_noise_2d(x, z) * 1.5
	var d := Vector2(x, z).length()
	var flat := smoothstep(0.0, 1.0, clampf(1.0 - d / PLATEAU_R, 0.0, 1.0))
	return lerpf(h, 0.0, flat * 0.94)

func _terrain_color(h: float, slope: float) -> Color:
	var c := Palette.GROUND_LOW.lerp(Palette.GROUND_HIGH, clampf(inverse_lerp(-7.0, 9.0, h), 0.0, 1.0))
	c = c.lerp(Palette.ROCK, clampf(slope * 1.6, 0.0, 0.75))
	# в низинах остался след старой химии: чуть ржавее, но всё ещё приглушённо
	if h < -2.0:
		c = c.lerp(Palette.RUST, 0.16)
	return c

func _build_terrain() -> void:
	var step := WORLD_SIZE / float(GRID)
	var half := WORLD_SIZE * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for gz in GRID:
		for gx in GRID:
			var x0 := -half + gx * step
			var z0 := -half + gz * step
			var x1 := x0 + step
			var z1 := z0 + step
			var p00 := Vector3(x0, height_at(x0, z0), z0)
			var p10 := Vector3(x1, height_at(x1, z0), z0)
			var p11 := Vector3(x1, height_at(x1, z1), z1)
			var p01 := Vector3(x0, height_at(x0, z1), z1)
			var slope: float = (absf(p10.y - p00.y) + absf(p01.y - p00.y)) / step
			for v in [p00, p11, p10, p00, p01, p11]:
				st.set_color(_terrain_color(v.y, slope))
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = Palette.vertex_mat()
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var tri := mesh.create_trimesh_shape()
	tri.backface_collision = true   # односторонний trimesh ловит только снизу
	cs.shape = tri
	body.add_child(cs)
	add_child(body)

func _build_bounds() -> void:
	# участок огорожен: за периметром работы нет, и заказчик это подчёркивает
	var half := WORLD_SIZE * 0.5 - 4.0
	for i in 4:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(WORLD_SIZE, 60.0, 2.0)
		cs.shape = bs
		body.add_child(cs)
		body.rotation.y = PI * 0.5 * i
		body.position = Vector3(0, 0, -half).rotated(Vector3.UP, body.rotation.y)
		add_child(body)

func _add_prop(mesh: Mesh, shape: Shape3D, xform: Transform3D, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	if shape != null:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	body.transform = xform
	add_child(body)
	return body

func _scatter_rocks() -> void:
	var rock_mat := Palette.mat(Palette.ROCK, 0.95, 0.05)
	for i in 150:
		var x := rng.randf_range(-100.0, 100.0)
		var z := rng.randf_range(-100.0, 100.0)
		if Vector2(x, z).length() < 22.0:
			continue
		var r := rng.randf_range(0.5, 2.6)
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 1.7
		sm.radial_segments = 8
		sm.rings = 5
		var ss := SphereShape3D.new()
		ss.radius = r * 0.9
		var t := Transform3D.IDENTITY
		t.basis = Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(
			Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.5, 1.0), rng.randf_range(0.8, 1.3)))
		t.origin = Vector3(x, height_at(x, z) - r * 0.4, z)
		_add_prop(sm, ss, t, rock_mat)

## Силуэт разбитого корабля на горизонте: задаёт масштаб и композицию кадра.
func _build_wreck(at: Vector3) -> void:
	var mat := Palette.mat(Palette.METAL.darkened(0.35), 0.9, 0.5)
	var ground := height_at(at.x, at.z)
	var hull := BoxMesh.new()
	hull.size = Vector3(11.0, 9.0, 34.0)
	var hs := BoxShape3D.new()
	hs.size = hull.size
	var basis := Basis(Vector3.UP, 0.7).rotated(Vector3.FORWARD, 0.22)
	_add_prop(hull, hs, Transform3D(basis, at + Vector3(0, ground + 3.0, 0)), mat)
	for i in 3:
		var rib := TorusMesh.new()
		rib.inner_radius = 6.0 + i * 0.6
		rib.outer_radius = 7.0 + i * 0.6
		var off := Vector3(0, 0, 15.0 + i * 5.0).rotated(Vector3.UP, 0.7)
		var rb := Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, 0.7)
		_add_prop(rib, null, Transform3D(rb, at + Vector3(0, ground + 4.0, 0) + off), mat)

# ---------------------------------------------------------------- станция ---

func _build_station(power: PowerNet) -> void:
	var gen := _make_generator(Vector3(-9, 0, -7))
	var bat := _make_battery(Vector3(-1, 0, -13))
	var proc := _make_processor(Vector3(8, 0, -6))
	var b1 := _make_beacon("М-1", Vector3(13, 0, 7))
	var b2 := _make_beacon("М-2", Vector3(-14, 0, 9))
	var b3 := _make_beacon("М-3", Vector3(1, 0, 19))
	var up := _make_uplink(Vector3(-2, 0, -22))
	for m in [gen, bat, proc, b1, b2, b3, up]:
		machines.append(m)
		power.register(m)
	# плиты основания: станция должна читаться как площадка, а не как набор коробок
	var pad_mat := Palette.mat(Palette.METAL.darkened(0.25), 0.95, 0.25)
	for i in 14:
		var a := rng.randf_range(0, TAU)
		var d := rng.randf_range(4.0, 20.0)
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(4.0, 8.0), 0.22, rng.randf_range(4.0, 8.0))
		var bs := BoxShape3D.new()
		bs.size = bm.size
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		var t := Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)), Vector3(p.x, height_at(p.x, p.z) + 0.05, p.z))
		_add_prop(bm, bs, t, pad_mat)

func _machine_base(code: String, label: String, pos: Vector3, body_size: Vector3) -> Machine:
	var m := Machine.new()
	m.code = code
	m.label = label
	m.name = code
	m.collision_layer = 1
	m.position = Vector3(pos.x, height_at(pos.x, pos.z), pos.z)
	m.rotation.y = atan2(-pos.x, -pos.z)   # лицом к центру площадки
	add_child(m)

	var plinth := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(body_size.x + 0.7, 0.3, body_size.z + 0.7)
	plinth.mesh = pm
	plinth.material_override = Palette.mat(Palette.METAL.darkened(0.3), 0.95, 0.3)
	plinth.position = Vector3(0, 0.15, 0)
	m.add_child(plinth)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = body_size
	mi.mesh = bm
	mi.material_override = Palette.mat(Palette.METAL, 0.78, 0.45)
	mi.position = Vector3(0, 0.3 + body_size.y * 0.5, 0)
	m.add_child(mi)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = body_size
	cs.shape = bs
	cs.position = mi.position
	m.add_child(cs)

	var tag := Label3D.new()
	tag.text = code + "  " + label
	tag.font_size = 36
	tag.pixel_size = 0.0026
	tag.modulate = Palette.TEXT
	tag.outline_modulate = Palette.VOID
	tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 0.45 + body_size.y + 0.45, 0)
	m.add_child(tag)
	m.tag = tag
	return m

func _add_slots(m: Machine, kinds: Array, at: Vector3) -> void:
	m.setup_slots(kinds)
	var n := kinds.size()
	for i in n:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.17, 0.17, 0.06)
		mi.mesh = bm
		mi.position = at + Vector3((i - (n - 1) * 0.5) * 0.26, 0, 0)
		m.add_child(mi)
		m.slot_nodes.append(mi)
	m.refresh_slots()

func _add_lamp(m: Machine, light: Light3D, energy: float, at: Vector3) -> void:
	light.light_color = Palette.AMBER
	light.light_energy = 0.0
	light.shadow_enabled = true
	light.position = at
	m.add_child(light)
	m.lamps.append(light)
	m.lamp_base.append(energy)

func _make_generator(pos: Vector3) -> Machine:
	var m := _machine_base("ГЕН-4", "генератор", pos, Vector3(2.6, 2.0, 2.0))
	m.role = Machine.Role.GENERATOR
	m.rated_kw = 14.0
	m.fuel = 0.0
	_add_slots(m, [Part.Kind.PLATE, Part.Kind.COIL], Vector3(0, 1.1, 1.02))

	var stack := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.24
	cm.bottom_radius = 0.3
	cm.height = 2.2
	stack.mesh = cm
	stack.material_override = Palette.mat(Palette.RUST, 0.95, 0.4)
	stack.position = Vector3(-0.9, 3.4, -0.7)
	m.add_child(stack)

	var rotor := Node3D.new()
	rotor.position = Vector3(0, 1.5, -1.05)
	m.add_child(rotor)
	var blades := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.62
	blades.mesh = tm
	blades.material_override = Palette.mat(Palette.METAL_LIGHT, 0.6, 0.8)
	blades.rotation.x = PI * 0.5
	rotor.add_child(blades)
	m.spin = rotor
	m.spin_speed = 9.0

	var l := OmniLight3D.new()
	l.omni_range = 11.0
	_add_lamp(m, l, 1.6, Vector3(0, 2.3, 1.2))
	return m

func _make_battery(pos: Vector3) -> Machine:
	var m := _machine_base("БНК-1", "батарейный блок", pos, Vector3(3.2, 1.3, 1.4))
	m.role = Machine.Role.BATTERY
	m.charge = 0.0
	_add_slots(m, [Part.Kind.PLATE, Part.Kind.PLATE], Vector3(0, 0.8, 0.72))
	for i in 4:
		var cellv := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.22
		cm.bottom_radius = 0.22
		cm.height = 0.9
		cellv.mesh = cm
		cellv.material_override = Palette.mat(Palette.METAL.darkened(0.15), 0.6, 0.7)
		cellv.position = Vector3(-1.2 + i * 0.8, 2.05, 0)
		m.add_child(cellv)
	var l := OmniLight3D.new()
	l.omni_range = 8.0
	l.light_color = Palette.SIGNAL
	_add_lamp(m, l, 0.9, Vector3(0, 1.7, 0.9))
	return m

func _make_processor(pos: Vector3) -> Machine:
	var m := _machine_base("П-2", "переработчик", pos, Vector3(2.4, 2.4, 2.4))
	m.role = Machine.Role.PROCESSOR
	m.rated_kw = 3.0
	_add_slots(m, [Part.Kind.COIL, Part.Kind.PLATE], Vector3(0, 1.3, 1.22))

	var drum := Node3D.new()
	drum.position = Vector3(0, 3.0, 0)
	m.add_child(drum)
	var dm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.05
	cm.bottom_radius = 1.05
	cm.height = 0.9
	dm.mesh = cm
	dm.material_override = Palette.mat(Palette.RUST.lerp(Palette.METAL, 0.5), 0.9, 0.5)
	drum.add_child(dm)
	var vane := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(2.3, 0.1, 0.18)
	vane.mesh = vm
	vane.material_override = Palette.mat(Palette.METAL_LIGHT, 0.6, 0.8)
	vane.position = Vector3(0, 0.5, 0)
	drum.add_child(vane)
	m.spin = drum
	m.spin_speed = 3.2

	# лоток выдачи: детали физически выпадают наружу, а не в меню
	var chute := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.1, 1.2)
	chute.mesh = bm
	chute.material_override = Palette.mat(Palette.METAL_LIGHT, 0.85, 0.5)
	chute.position = Vector3(0, 0.9, 1.5)
	chute.rotation.x = -0.25
	m.add_child(chute)

	var l := OmniLight3D.new()
	l.omni_range = 9.0
	_add_lamp(m, l, 1.3, Vector3(0, 2.0, 1.4))
	return m

func _make_beacon(code: String, pos: Vector3) -> Machine:
	var m := _machine_base(code, "маяк", pos, Vector3(1.0, 0.9, 1.0))
	m.role = Machine.Role.LOAD
	m.rated_kw = 2.0
	_add_slots(m, [Part.Kind.COIL], Vector3(0, 0.6, 0.53))

	var mast := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.14
	cm.height = 6.0
	mast.mesh = cm
	mast.material_override = Palette.mat(Palette.METAL, 0.9, 0.6)
	mast.position = Vector3(0, 4.2, 0)
	m.add_child(mast)

	var headm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.4, 0.7)
	headm.mesh = bm
	headm.material_override = Palette.glow(Palette.AMBER, 1.1)
	headm.position = Vector3(0, 7.3, 0)
	m.add_child(headm)

	# конус вниз: в тумане свет читается как объём, а не как пятно на земле
	var sl := SpotLight3D.new()
	sl.spot_range = 26.0
	sl.spot_angle = 32.0
	sl.spot_attenuation = 0.7
	sl.rotation.x = -PI * 0.5
	sl.light_volumetric_fog_energy = 3.0
	_add_lamp(m, sl, 9.0, Vector3(0, 7.1, 0))
	var ol := OmniLight3D.new()
	ol.omni_range = 18.0
	ol.light_volumetric_fog_energy = 2.0
	_add_lamp(m, ol, 1.6, Vector3(0, 7.2, 0))
	return m

func _make_uplink(pos: Vector3) -> Machine:
	var m := _machine_base("РТР-9", "ретранслятор", pos, Vector3(2.2, 1.6, 2.2))
	m.role = Machine.Role.LOAD
	m.rated_kw = 8.0
	m.is_uplink = true
	_add_slots(m, [Part.Kind.PLATE, Part.Kind.COIL, Part.Kind.COIL], Vector3(0, 0.95, 1.12))

	var mast := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.2
	cm.height = 5.0
	mast.mesh = cm
	mast.material_override = Palette.mat(Palette.METAL, 0.9, 0.6)
	mast.position = Vector3(0, 4.3, 0)
	m.add_child(mast)

	var dish_pivot := Node3D.new()
	dish_pivot.position = Vector3(0, 6.6, 0)
	dish_pivot.rotation = Vector3(-0.9, 0.4, 0)
	m.add_child(dish_pivot)
	var dish := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.0
	sm.height = 1.6
	sm.is_hemisphere = true
	dish.mesh = sm
	dish.material_override = Palette.mat(Palette.METAL_LIGHT.darkened(0.2), 0.7, 0.55)
	dish.rotation.x = PI
	dish_pivot.add_child(dish)
	var feed := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.06
	fm.bottom_radius = 0.06
	fm.height = 1.6
	feed.mesh = fm
	feed.material_override = Palette.glow(Palette.SIGNAL, 0.8)
	feed.position = Vector3(0, 0.8, 0)
	dish_pivot.add_child(feed)

	var l := OmniLight3D.new()
	l.omni_range = 12.0
	l.light_color = Palette.SIGNAL
	_add_lamp(m, l, 1.4, Vector3(0, 2.0, 1.3))
	return m

# ---------------------------------------------------------------- ресурсы ---

func _build_salvage() -> void:
	# «завалы»: холм из обломков, вокруг — лом, который можно унести
	for c in [Vector3(26, 0, 22), Vector3(-30, 0, -16), Vector3(34, 0, -28), Vector3(-22, 0, 32)]:
		_pile(c)
	# начальный запас годных деталей: смена начинается с работы,
	# а не с ожидания переработчика
	var seeds := [
		[Part.Kind.PLATE, Vector3(3, 0, 4)], [Part.Kind.PLATE, Vector3(-5, 0, 2)],
		[Part.Kind.PLATE, Vector3(11, 0, -12)], [Part.Kind.COIL, Vector3(-3, 0, 6)],
		[Part.Kind.COIL, Vector3(6, 0, 1)], [Part.Kind.COIL, Vector3(-9, 0, -14)],
		[Part.Kind.CELL, Vector3(-7, 0, -3)], [Part.Kind.CELL, Vector3(4, 0, -16)],
	]
	for s in seeds:
		var p: Vector3 = s[1]
		add_loose_part(int(s[0]), Vector3(p.x, height_at(p.x, p.z) + 0.6, p.z))

func _pile(center: Vector3) -> void:
	var mound_mat := Palette.mat(Palette.RUST.lerp(Palette.ROCK, 0.55), 0.95, 0.35)
	for i in 7:
		var p := center + Vector3(rng.randf_range(-2.6, 2.6), 0, rng.randf_range(-2.6, 2.6))
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(1.2, 2.8), rng.randf_range(0.5, 1.6), rng.randf_range(1.2, 2.8))
		var bs := BoxShape3D.new()
		bs.size = bm.size
		var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).rotated(Vector3.FORWARD, rng.randf_range(-0.2, 0.2))
		_add_prop(bm, bs, Transform3D(basis, Vector3(p.x, height_at(p.x, p.z) + bm.size.y * 0.3, p.z)), mound_mat)
	for i in 7:
		var q := center + Vector3(rng.randf_range(-4.5, 4.5), 0, rng.randf_range(-4.5, 4.5))
		add_loose_part(Part.Kind.SCRAP, Vector3(q.x, height_at(q.x, q.z) + 0.8, q.z))

func add_loose_part(kind: int, pos: Vector3) -> Part:
	var p := Part.spawn(kind, pos, rng)
	add_child(p)
	salvage_parts.append(p)
	return p
