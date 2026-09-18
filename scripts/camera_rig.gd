class_name CameraRig
extends Node3D

## Камера от третьего лица, через плечо. Позиция считается вручную:
## сглаженная точка опоры, смещение вбок для нуарной композиции и
## собственный луч против перекрытий — без узла-пружины, чтобы поведение
## кадра целиком читалось в одном файле.

const DIST := 4.3
const SIDE := 0.62
const HEAD_H := 1.52
const SENS := 0.0023
const MIN_DIST := 1.25

var camera: Camera3D
var follow                   # Player
var yaw := 0.0
var pitch := -0.14
var dist := DIST
var _pivot := Vector3.ZERO
var _shake := 0.0

func setup(p) -> void:
	follow = p
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 62.0
	camera.far = 320.0
	camera.near = 0.08
	add_child(camera)
	_pivot = p.torso.global_position + Vector3.UP * HEAD_H
	_place(0.001)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * SENS
		pitch = clampf(pitch - event.relative.y * SENS, -1.15, 0.6)

func _process(delta: float) -> void:
	if follow == null:
		return
	_place(delta)

func _place(delta: float) -> void:
	var aim: Vector3 = follow.torso.global_position + Vector3.UP * HEAD_H
	_pivot = _pivot.lerp(aim, 1.0 - exp(-13.0 * delta))
	# на бегу камера чуть отъезжает — движение читается без анимации бега
	var want_dist: float = DIST + clampf(follow.speed_h * 0.12, 0.0, 0.7)
	dist = lerpf(dist, want_dist, 1.0 - exp(-4.0 * delta))

	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var desired: Vector3 = _pivot + basis * Vector3(SIDE, 0.0, dist)

	var q := PhysicsRayQueryParameters3D.create(_pivot, desired)
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		# подтягиваемся вдоль штанги, а не к самой поверхности: иначе камера
		# уезжает боком и вжимается в корпус, когда игрок подходит вплотную
		var arm: Vector3 = desired - _pivot
		var full := arm.length()
		var free: float = _pivot.distance_to(hit["position"]) - 0.3
		desired = _pivot + arm / full * clampf(free, MIN_DIST, full)

	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.6)
		var t := Time.get_ticks_msec() * 0.001
		desired += Vector3(sin(t * 47.0), cos(t * 39.0), sin(t * 53.0)) * _shake * 0.06

	camera.global_transform = Transform3D(basis, desired)

func shake(amount: float) -> void:
	_shake = minf(1.0, _shake + amount)

func forward() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3.FORWARD

func right() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3.RIGHT
