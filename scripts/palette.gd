class_name Palette
extends RefCounted

## Единственный источник цвета в проекте. Нуар, приглушённая палитра:
## холодные серо-синие тона, один тёплый акцент (амбер) и один сигнальный
## (бледная бирюза). Всё остальное — производные.

const VOID := Color("0a0d10")          # пустота, фон, тени
const FOG := Color("161d22")           # туман, воздух
const GROUND_LOW := Color("1b2328")    # низины грунта
const GROUND_HIGH := Color("2c353b")   # гребни грунта
const ROCK := Color("222a30")          # камень
const RUST := Color("6b4234")          # ржавчина, старое железо
const METAL := Color("39444b")         # корпуса
const METAL_LIGHT := Color("5c6a73")   # кромки, поручни
const AMBER := Color("c9872e")         # рабочий свет, «включено»
const AMBER_DIM := Color("6d4a1c")     # выключенный индикатор
const SIGNAL := Color("6f9a94")        # данные, визор, заряд
const TEXT := Color("9fb0b8")
const TEXT_DIM := Color("5c6a73")
const ALERT := Color("b4503c")
const OK := Color("7f9e7a")

## Материал общего назначения.
static func mat(albedo: Color, roughness := 0.82, metallic := 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	m.metallic = metallic
	m.metallic_specular = 0.4
	return m

## Светящийся материал для индикаторов и ламп.
static func glow(albedo: Color, energy := 1.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = 0.5
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = albedo
	m.emission_energy_multiplier = energy
	return m

## Материал с цветом из вершин (грунт).
static func vertex_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.metallic = 0.0
	return m
