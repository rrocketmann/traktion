class_name Vehicle extends Node3D

# Nodes

@onready var sphere: RigidBody3D = $Sphere
@onready var raycast: RayCast3D = $Ground

# Vehicle elements

@onready var vehicle_model = $Container
@onready var vehicle_body = get_node_or_null("Container/Model/body")

# (Optional) wheels — rebound whenever the car model is swapped.

@onready var wheel_fl = get_node_or_null("Container/Model/wheel-front-left")
@onready var wheel_fr = get_node_or_null("Container/Model/wheel-front-right")
@onready var wheel_bl = get_node_or_null("Container/Model/wheel-back-left")
@onready var wheel_br = get_node_or_null("Container/Model/wheel-back-right")

var wheels: Array[Node3D] = []
var _wheel_rest: Dictionary = {}
var _body_rest: Transform3D = Transform3D.IDENTITY

# Effects

@onready var trail_left = get_node_or_null("Container/TrailLeft")
@onready var trail_right = get_node_or_null("Container/TrailRight")

# Sounds

@onready var screech_sound: AudioStreamPlayer3D = $Container/ScreechSound
@onready var engine_sound: AudioStreamPlayer3D = $Container/EngineSound
@onready var impact_sound: AudioStreamPlayer3D = $Container/ImpactSound

var input: Vector3
var normal: Vector3

var acceleration: float
var angular_speed: float
var linear_speed: float

var colliding: bool

var linear_velocity: Vector3
var prev_position: Vector3

var calculated_lean: float

var control_enabled: bool = false

# Public Functions

func _ready() -> void:
	_bind_model_parts($Container.get_node_or_null("Model"))
	set_frozen(true)

func get_vehicle_position() -> Vector3: return vehicle_model.global_position

func apply_model(packed: PackedScene) -> void:
	if packed == null:
		return
	var old_model = $Container.get_node_or_null("Model")
	var old_transform := Transform3D.IDENTITY
	if old_model != null:
		old_transform = old_model.transform
		old_model.free()

	var model = packed.instantiate()
	model.name = "Model"
	$Container.add_child(model)
	$Container.move_child(model, 0)
	model.transform = old_transform
	_bind_model_parts(model)

func _bind_model_parts(model: Node) -> void:
	wheels.clear()
	_wheel_rest.clear()
	vehicle_body = null
	wheel_fl = null
	wheel_fr = null
	wheel_bl = null
	wheel_br = null
	if model == null:
		return
	_scan_model(model)
	if vehicle_body != null:
		_body_rest = vehicle_body.transform

func _scan_model(n: Node) -> void:
	if n is MeshInstance3D:
		_use_nearest_colors(n)
	var key := String(n.name).to_lower()
	if key == "body" and n is Node3D and vehicle_body == null:
		vehicle_body = n
	if key.begins_with("wheel") and n is Node3D:
		var wheel := n as Node3D
		wheels.append(wheel)
		_wheel_rest[wheel] = wheel.transform
		if key.contains("front") and key.contains("left"):
			wheel_fl = wheel
		elif key.contains("front") and key.contains("right"):
			wheel_fr = wheel
		elif key == "wheel-front" and wheel_fl == null:
			wheel_fl = wheel
		elif key.contains("back") and key.contains("left"):
			wheel_bl = wheel
		elif key.contains("back") and key.contains("right"):
			wheel_br = wheel
		elif key == "wheel-back" and wheel_bl == null:
			wheel_bl = wheel
	for child in n.get_children():
		_scan_model(child)

func _use_nearest_colors(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var mat := mi.get_active_material(i)
		if mat == null:
			mat = mesh.surface_get_material(i)
		if mat is BaseMaterial3D:
			var dup := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			dup.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mi.set_surface_override_material(i, dup)

func set_frozen(frozen: bool) -> void:
	sphere.freeze = frozen
	if frozen:
		sphere.linear_velocity = Vector3.ZERO
		sphere.angular_velocity = Vector3.ZERO
		linear_speed = 0.0
		acceleration = 0.0
		angular_speed = 0.0
		input = Vector3.ZERO

func reset_to(spawn: Transform3D) -> void:
	control_enabled = false
	linear_speed = 0.0
	acceleration = 0.0
	angular_speed = 0.0
	input = Vector3.ZERO
	calculated_lean = 0.0
	global_transform = spawn
	var origin := spawn.origin + Vector3(0.0, 0.5, 0.0)
	var xform := Transform3D(Basis.IDENTITY, origin)
	sphere.freeze = true
	sphere.sleeping = true
	sphere.global_transform = xform
	sphere.linear_velocity = Vector3.ZERO
	sphere.angular_velocity = Vector3.ZERO
	var rid := sphere.get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, true)
	vehicle_model.global_transform = Transform3D(Basis.IDENTITY, spawn.origin)
	raycast.global_position = origin
	if vehicle_body != null:
		vehicle_body.transform = _body_rest
	for wheel in wheels:
		if _wheel_rest.has(wheel):
			wheel.transform = _wheel_rest[wheel]
	prev_position = vehicle_model.position


# Functions

func _physics_process(delta):

	if sphere.freeze:
		vehicle_model.global_transform = Transform3D(Basis.IDENTITY, sphere.global_position - Vector3(0.0, 0.65, 0.0))
		return

	handle_input(delta)

	var direction = sign(linear_speed)
	if direction == 0: direction = sign(input.z) if abs(input.z) > 0.1 else 1

	# No yaw at rest; grip ramps in after a little speed (linear_speed is ~0..1).
	var steering_grip = clampf(inverse_lerp(0.12, 0.5, abs(linear_speed)), 0.0, 1.0)

	var target_angular = -input.x * steering_grip * 4 * direction
	angular_speed = lerp(angular_speed, target_angular, delta * 4)

	vehicle_model.rotate_y(angular_speed * delta)

	# Ground alignment

	if raycast.is_colliding():
		if !colliding:
			if vehicle_body != null: vehicle_body.position = _body_rest.origin + Vector3(0, 0.1, 0) # Bounce
			input.z = 0

		normal = raycast.get_collision_normal()

		# Orient model to colliding normal

		if normal.dot(vehicle_model.global_basis.y) > 0.5:
			var xform = align_with_y(vehicle_model.global_transform, normal)
			vehicle_model.global_transform = vehicle_model.global_transform.interpolate_with(xform, 0.2).orthonormalized()

	colliding = raycast.is_colliding()

	var target_speed = input.z
	var turn := absf(input.x)

	if target_speed > 0.1:
		target_speed *= lerpf(1.0, 0.78, turn)
		linear_speed = lerp(linear_speed, target_speed, delta * 7.5)
	elif target_speed < -0.1:
		if linear_speed > 0.01:
			linear_speed = lerp(linear_speed, 0.0, delta * 8)
		else:
			linear_speed = lerp(linear_speed, target_speed / 2.0, delta * 2)
	else:
		# Coast with light rolling resistance; reverse/back is the brake.
		linear_speed = lerp(linear_speed, 0.0, delta * 0.2)

	if turn > 0.05 and absf(linear_speed) > 0.05:
		linear_speed -= linear_speed * turn * delta * 0.9

	acceleration = lerpf(acceleration, linear_speed + (abs(sphere.angular_velocity.length() * linear_speed) / 100), delta * 1)

	# Match vehicle model to physics sphere

	vehicle_model.position = sphere.position - Vector3(0, 0.65, 0)
	raycast.position = sphere.position

	# Calculate vehicle model linear velocity

	linear_velocity = (vehicle_model.position - prev_position) / delta
	prev_position = vehicle_model.position

	# Visual and audio effects

	effect_engine(delta)
	effect_body(delta)
	effect_wheels(delta)
	effect_trails()

# Handle input when vehicle is colliding with ground

func handle_input(delta):

	if control_enabled and raycast.is_colliding():
		input.x = Input.get_axis("left", "right")
		input.z = Input.get_axis("back", "forward")
	else:
		input.x = 0.0
		if not control_enabled:
			input.z = 0.0

	sphere.angular_velocity += vehicle_model.get_global_transform().basis.x * (linear_speed * 165) * delta

	# Asphalt grip: kill sideways slide so the sphere follows the car heading.
	var fwd: Vector3 = vehicle_model.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.0001:
		fwd = fwd.normalized()
		var right := Vector3.UP.cross(fwd)
		var vel := sphere.linear_velocity
		var lat := vel.dot(right)
		sphere.linear_velocity -= right * lat * clampf(12.0 * delta, 0.0, 1.0)

func effect_body(delta):
	
	calculated_lean = lerp_angle(calculated_lean, -input.x / 5 * linear_speed, delta * 5)
	
	# Slightly tilt (and move) body based on acceleration and steering
	
	if vehicle_body != null:
		
		vehicle_body.rotation.x = lerp_angle(vehicle_body.rotation.x, _body_rest.basis.get_euler().x - (linear_speed - acceleration) / 6, delta * 10)
		vehicle_body.rotation.z = _body_rest.basis.get_euler().z + calculated_lean
		
		vehicle_body.position = vehicle_body.position.lerp(_body_rest.origin, delta * 5)
	
func effect_wheels(delta):

	for wheel in wheels:
		wheel.rotation.x += acceleration
		var rest: Transform3D = _wheel_rest[wheel] if _wheel_rest.has(wheel) else wheel.transform
		var rest_y := rest.basis.get_euler().y
		var is_front := String(wheel.name).to_lower().contains("front")
		var steer := -input.x / 1.5 if is_front else 0.0
		wheel.rotation.y = lerp_angle(wheel.rotation.y, rest_y + steer, delta * 10)

# Engine sounds

func effect_engine(delta):

	var speed_factor = clamp(abs(linear_speed), 0.0, 1.0)
	var throttle_factor = clamp(abs(input.z), 0.0, 1.0)

	var target_volume = remap(speed_factor + (throttle_factor * 0.5), 0.0, 1.5, -15.0, -5.0)
	engine_sound.volume_db = lerp(engine_sound.volume_db, target_volume, delta * 5.0)

	var target_pitch = remap(speed_factor, 0.0, 1.0, 0.5, 3)
	if throttle_factor > 0.1: target_pitch += 0.2

	engine_sound.pitch_scale = lerp(engine_sound.pitch_scale, target_pitch, delta * 2.0)

# Show trails (and play skid sound)

func effect_trails():

	var drift_intensity = abs(linear_speed - acceleration) + (abs(calculated_lean) * 2.0)
	var should_emit = drift_intensity > 0.25

	if trail_left != null: trail_left.emitting = should_emit
	if trail_right != null: trail_right.emitting = should_emit

	var target_volume = -80.0
	if should_emit: target_volume = remap(clamp(drift_intensity, 0.25, 2.0), 0.25, 2.0, -10.0, 0.0)

	screech_sound.pitch_scale = lerp(screech_sound.pitch_scale, clamp(abs(linear_speed), 1.0, 3.0), 0.1)
	screech_sound.volume_db = lerp(screech_sound.volume_db, target_volume, 10.0 * get_physics_process_delta_time())

# Align vehicle with normal

func align_with_y(xform, new_y):

	xform.basis.y = new_y
	xform.basis.x = -xform.basis.z.cross(new_y)
	xform.basis = xform.basis.orthonormalized()
	return xform

# Detect collisions and play impact sound

func _on_sphere_body_entered(_body: Node) -> void:
	
	if vehicle_body == null: return
	
	if not impact_sound.playing:
		var impact_velocity := absf(linear_velocity.dot(vehicle_body.global_basis.z))
		impact_sound.volume_db = clampf(remap(impact_velocity, 0.0, 6.0, -20.0, 0.0), -20.0, 0.0)
		impact_sound.play()
