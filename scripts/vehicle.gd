class_name Vehicle extends Node3D

# Nodes

@onready var sphere: RigidBody3D = $Sphere
@onready var collision_shape: CollisionShape3D = $Sphere/CollisionShape
@onready var raycast: RayCast3D = $Ground

const DRIVE_SPEED := 22.0
const STEER_RATE := 4.0
const COLLIDER_CLEARANCE := 0.06
const GROUND_PLANT := 0.15

var _collider_center := Vector3(0.0, 0.65, 0.0)
var _ride_drop := GROUND_PLANT

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
	_fit_collider(model)

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

func _fit_collider(model: Node) -> void:
	var aabb := _model_aabb(model)
	if aabb.size.x < 0.05 or aabb.size.y < 0.05 or aabb.size.z < 0.05:
		aabb = AABB(Vector3(-0.6, 0.1, -1.2), Vector3(1.2, 0.7, 2.4))
	# Body hull only — lift off the asphalt so wheels stay visual and the box does not rest on the road.
	if aabb.position.y < COLLIDER_CLEARANCE:
		var lift := COLLIDER_CLEARANCE - aabb.position.y
		aabb.position.y += lift
		aabb.size.y = maxf(aabb.size.y - lift, 0.2)
	_collider_center = aabb.get_center()
	var box := collision_shape.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		collision_shape.shape = box
	box.size = aabb.size
	collision_shape.position = Vector3.ZERO
	var full := _model_aabb(model, false)
	var floor_y := full.position.y if full.size.y > 0.05 else 0.0
	_ride_drop = GROUND_PLANT + floor_y

func _model_aabb(model: Node, skip_wheels: bool = true) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_gather_body_meshes(model, meshes, skip_wheels)
	var acc := AABB()
	var any := false
	if not model is Node3D:
		return acc
	var mroot := model as Node3D
	for mi in meshes:
		var xf := mroot.global_transform.affine_inverse() * mi.global_transform
		var local := xf * mi.mesh.get_aabb()
		if not any:
			acc = local
			any = true
		else:
			acc = acc.merge(local)
	return acc

func _gather_body_meshes(n: Node, meshes: Array[MeshInstance3D], skip_wheels: bool = true) -> void:
	if skip_wheels and String(n.name).to_lower().begins_with("wheel"):
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		meshes.append(n)
	for child in n.get_children():
		_gather_body_meshes(child, meshes, skip_wheels)

func set_frozen(frozen: bool) -> void:
	sphere.freeze = frozen
	if frozen:
		sphere.linear_velocity = Vector3.ZERO
		sphere.angular_velocity = Vector3.ZERO
		linear_speed = 0.0
		acceleration = 0.0
		angular_speed = 0.0
		input = Vector3.ZERO
		_silence_screech()
		if trail_left != null:
			trail_left.emitting = false
		if trail_right != null:
			trail_right.emitting = false

func reset_to(spawn: Transform3D) -> void:
	control_enabled = false
	linear_speed = 0.0
	acceleration = 0.0
	angular_speed = 0.0
	input = Vector3.ZERO
	calculated_lean = 0.0
	global_transform = spawn
	var origin := spawn.origin + spawn.basis * _collider_center
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
	vehicle_model.global_transform = Transform3D(Basis.IDENTITY, spawn.origin - Vector3(0.0, _ride_drop, 0.0))
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
		_sync_visual_to_body()
		return

	raycast.global_position = sphere.global_position
	raycast.force_raycast_update()
	_stick_to_ground()
	handle_input(delta)

	var direction := signf(linear_speed)
	if direction == 0.0:
		direction = signf(input.z) if absf(input.z) > 0.1 else 1.0

	# No yaw at rest; full steer in the mid range, then it tightens as speed climbs.
	var speed_abs := absf(linear_speed)
	var steering_grip := clampf(inverse_lerp(0.12, 0.4, speed_abs), 0.0, 1.0)
	var speed_steer := lerpf(1.0, 0.32, clampf(inverse_lerp(0.4, 1.0, speed_abs), 0.0, 1.0))

	var target_angular: float = -input.x * steering_grip * speed_steer * STEER_RATE * direction
	angular_speed = lerp(angular_speed, target_angular, delta * lerpf(5.0, 2.2, clampf(speed_abs, 0.0, 1.0)))

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
		linear_speed = lerp(linear_speed, target_speed, delta * 8.5)
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

	acceleration = lerpf(acceleration, linear_speed, delta * 1)

	_sync_body_yaw()
	_sync_visual_to_body()
	raycast.global_position = sphere.global_position

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

	# Drive the box along heading. A spinning collider climbs walls; linear motion does not.
	var fwd: Vector3 = vehicle_model.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.0001:
		fwd = fwd.normalized()
		var right := Vector3.UP.cross(fwd)
		var vel := sphere.linear_velocity
		var along := vel.dot(fwd)
		var lat := vel.dot(right)
		along = lerpf(along, linear_speed * DRIVE_SPEED, clampf(delta * 8.0, 0.0, 1.0))
		lat *= 1.0 - clampf(12.0 * delta, 0.0, 1.0)
		var vertical := 0.0 if raycast.is_colliding() else vel.y
		sphere.linear_velocity = fwd * along + right * lat + Vector3.UP * vertical
	sphere.angular_velocity = Vector3.ZERO

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
	if sphere.freeze or not control_enabled:
		_silence_screech()
		if trail_left != null:
			trail_left.emitting = false
		if trail_right != null:
			trail_right.emitting = false
		return

	var drift_intensity = abs(linear_speed - acceleration) + (abs(calculated_lean) * 2.0)
	var should_emit = drift_intensity > 0.25

	if trail_left != null: trail_left.emitting = should_emit
	if trail_right != null: trail_right.emitting = should_emit

	var target_volume = -80.0
	if should_emit:
		target_volume = remap(clamp(drift_intensity, 0.25, 2.0), 0.25, 2.0, -10.0, 0.0)
		if not screech_sound.playing:
			screech_sound.play()

	screech_sound.pitch_scale = lerp(screech_sound.pitch_scale, clamp(abs(linear_speed), 1.0, 3.0), 0.1)
	screech_sound.volume_db = lerp(screech_sound.volume_db, target_volume, 10.0 * get_physics_process_delta_time())
	if not should_emit and screech_sound.volume_db < -40.0:
		screech_sound.stop()

func _silence_screech() -> void:
	screech_sound.stop()
	screech_sound.volume_db = -80.0

func _heading_yaw() -> float:
	var fwd: Vector3 = vehicle_model.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return 0.0
	fwd = fwd.normalized()
	return atan2(fwd.x, fwd.z)

func _sync_body_yaw() -> void:
	var xform := sphere.global_transform
	xform.basis = Basis(Vector3.UP, _heading_yaw())
	sphere.global_transform = xform
	PhysicsServer3D.body_set_state(sphere.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)

func _sync_visual_to_body() -> void:
	var yaw_basis := Basis(Vector3.UP, _heading_yaw())
	vehicle_model.global_position = sphere.global_position - yaw_basis * _collider_center - Vector3(0.0, _ride_drop, 0.0)

func _stick_to_ground() -> void:
	if not raycast.is_colliding():
		return
	var desired_y := raycast.get_collision_point().y + _collider_center.y
	var xform := sphere.global_transform
	xform.origin.y = desired_y
	sphere.global_transform = xform
	PhysicsServer3D.body_set_state(sphere.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	var vel := sphere.linear_velocity
	if vel.y > 0.0:
		vel.y = 0.0
		sphere.linear_velocity = vel

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
