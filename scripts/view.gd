extends Node3D

enum Mode { ORBIT, CHASE }

@export_group("Properties")
@export var target: Vehicle

@onready var camera = $Camera

var mode: Mode = Mode.ORBIT
var orbit_angle: float = 0.0
var _rig_scale: float = 1.0

func _ready() -> void:
	# Compatibility + a full browser window reads tighter than the 1280x720 editor window.
	if OS.has_feature("web"):
		_rig_scale = 1.2
		camera.fov = 80.0
		camera.keep_aspect = Camera3D.KEEP_HEIGHT

func start_orbit() -> void:
	mode = Mode.ORBIT
	orbit_angle = 0.0
	_snap_orbit()

func start_chase() -> void:
	mode = Mode.CHASE

func _snap_orbit() -> void:
	if target == null:
		return
	var pos: Vector3 = target.get_vehicle_position()
	global_position = pos + Vector3(0.0, 5.6 * _rig_scale, 15.0 * _rig_scale)
	look_at(pos + Vector3.UP * 0.7, Vector3.UP)

func _physics_process(delta):
	if target == null:
		return

	var pos: Vector3 = target.get_vehicle_position()

	if mode == Mode.ORBIT:
		orbit_angle += delta * 0.45
		var radius := 15.0 * _rig_scale
		var orbit_pos := pos + Vector3(sin(orbit_angle) * radius, 5.6 * _rig_scale, cos(orbit_angle) * radius)
		global_position = global_position.lerp(orbit_pos, delta * 3.0)
		look_at(pos + Vector3.UP * 0.7, Vector3.UP)
		return

	# Model +Z is the drive direction; stay on the tail and look forward.
	var forward: Vector3 = target.vehicle_model.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()

	var speed_factor := clampf(abs(target.linear_speed), 0.0, 1.0)
	var distance := lerpf(13.0, 16.0, speed_factor) * _rig_scale
	var height := lerpf(5.0, 6.0, speed_factor) * _rig_scale

	var chase_pos := pos - forward * distance + Vector3.UP * height
	global_position = global_position.lerp(chase_pos, delta * 4.0)

	look_at(pos + Vector3.UP * 1.0, Vector3.UP)
