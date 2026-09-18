class_name Part
extends RigidBody3D

## Физический предмет. Всё, что игрок носит, — настоящее твёрдое тело:
## оно качается в руках, стучит по корпусам, скатывается по склону
## и никогда не исчезает в абстрактном инвентаре.

enum Kind { COIL, PLATE, CELL, SCRAP }

const LAYER_PART := 8      # слой 4
const MASK_PART := 11      # мир(1) + торс игрока(2) + другие предметы(8)

var kind: int = Kind.SCRAP

static func label_of(k: int) -> String:
	match k:
		Kind.COIL: return "КАТУШКА"
		Kind.PLATE: return "ПЛАСТИНА"
		Kind.CELL: return "ЯЧЕЙКА"
		_: return "ЛОМ"

static func code_of(k: int) -> String:
	match k:
		Kind.COIL: return "КТШ"
		Kind.PLATE: return "ПЛТ"
		Kind.CELL: return "ЯЧК"
		_: return "ЛОМ"

static func tint_of(k: int) -> Color:
	match k:
		Kind.COIL: return Palette.AMBER
		Kind.PLATE: return Palette.METAL_LIGHT
		Kind.CELL: return Palette.SIGNAL
		_: return Palette.RUST

## Сборка предмета целиком из кода: меш-плейсхолдер в палитре + коллайдер.
static func spawn(k: int, pos: Vector3, rng: RandomNumberGenerator = null) -> Part:
	var p := Part.new()
	p.kind = k
	p.collision_layer = LAYER_PART
	p.collision_mask = MASK_PART
	p.continuous_cd = true
	p.angular_damp = 0.6
	p.linear_damp = 0.05
	p.name = "Part_" + code_of(k)

	var mi := MeshInstance3D.new()
	var body_mat := Palette.mat(Palette.METAL, 0.62, 0.55)
	var shape := CollisionShape3D.new()

	match k:
		Kind.COIL:
			var t := TorusMesh.new()
			t.inner_radius = 0.10
			t.outer_radius = 0.19
			mi.mesh = t
			mi.material_override = Palette.mat(Palette.RUST, 0.55, 0.7)
			var cs := CylinderShape3D.new()
			cs.radius = 0.19
			cs.height = 0.2
			shape.shape = cs
			p.mass = 14.0
			var core := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.055
			cm.bottom_radius = 0.055
			cm.height = 0.22
			core.mesh = cm
			core.material_override = Palette.glow(Palette.AMBER_DIM, 0.6)
			p.add_child(core)
		Kind.PLATE:
			var b := BoxMesh.new()
			b.size = Vector3(0.52, 0.07, 0.36)
			mi.mesh = b
			mi.material_override = body_mat
			var bs := BoxShape3D.new()
			bs.size = b.size
			shape.shape = bs
			p.mass = 22.0
		Kind.CELL:
			var c := CylinderMesh.new()
			c.top_radius = 0.10
			c.bottom_radius = 0.10
			c.height = 0.38
			mi.mesh = c
			mi.material_override = Palette.mat(Palette.METAL, 0.5, 0.7)
			var ccs := CylinderShape3D.new()
			ccs.radius = 0.10
			ccs.height = 0.38
			shape.shape = ccs
			p.mass = 9.0
			var band := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 0.105
			bm.bottom_radius = 0.105
			bm.height = 0.07
			band.mesh = bm
			band.material_override = Palette.glow(Palette.SIGNAL, 1.4)
			band.position = Vector3(0, 0.08, 0)
			p.add_child(band)
		_:
			var s := BoxMesh.new()
			var r := rng if rng != null else RandomNumberGenerator.new()
			s.size = Vector3(r.randf_range(0.28, 0.5), r.randf_range(0.14, 0.26), r.randf_range(0.22, 0.42))
			mi.mesh = s
			mi.material_override = Palette.mat(Palette.RUST.lerp(Palette.METAL, 0.45), 0.9, 0.35)
			var ss := BoxShape3D.new()
			ss.size = s.size
			shape.shape = ss
			p.mass = 18.0

	p.add_child(mi)
	p.add_child(shape)
	p.position = pos
	if rng != null:
		p.rotation = Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))
	return p

func label() -> String:
	return label_of(kind)
