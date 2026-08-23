extends Node3D

const CARS := [
	{ "name": "Truck", "scene": "res://models/vehicle-truck-yellow.glb" },
	{ "name": "Motorcycle", "scene": "res://models/vehicle-motorcycle.glb" },
	{ "name": "Racer", "scene": "res://models/cars/race.glb" },
	{ "name": "Future", "scene": "res://models/cars/race-future.glb" },
	{ "name": "Hatchback", "scene": "res://models/cars/hatchback-sports.glb" },
	{ "name": "Sports", "scene": "res://models/cars/sedan-sports.glb" },
	{ "name": "Taxi", "scene": "res://models/cars/taxi.glb" },
	{ "name": "Police", "scene": "res://models/cars/police.glb" },
	{ "name": "SUV", "scene": "res://models/cars/suv.glb" },
]

const TIMES_PATH := "user://laps.txt"
const MAX_RECENT := 5
const MAX_GHOSTS := 4
const GHOST_NEAR := 4.0
const GHOST_FAR := 28.0
const GHOST_TAIL := 3.0

enum State { SELECTING, RACING, FINISHED }

@onready var vehicle: Vehicle = $Vehicle
@onready var view = $View
@onready var hud = $HUD

var state: State = State.SELECTING
var car_index: int = 0
var spawn_transform: Transform3D
var elapsed: float = 0.0
var timing: bool = false
var passed_checkpoint: bool = false
var recent_times: Array = []
var _recording: Array[Transform3D] = []
var _ghost_runs: Array = []
var _ghosts: Array = []
var _ghost_root: Node3D
var _ghost_tail := 0.0
var _ghost_pending := false

func _ready() -> void:
	spawn_transform = vehicle.global_transform
	_ghost_root = Node3D.new()
	_ghost_root.name = "Ghosts"
	add_child(_ghost_root)
	_apply_web_look()
	_load_times()
	_enter_select()

func _apply_web_look() -> void:
	if not OS.has_feature("web"):
		return
	# Compatibility has no SSAO/SSIL, and glow blows out the solid sky.
	var world := $Environment as WorldEnvironment
	var env: Environment = world.environment.duplicate()
	env.glow_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.tonemap_exposure = 0.58
	env.background_energy_multiplier = 0.7
	env.background_color = Color(0.46, 0.56, 0.78)
	env.ambient_light_color = Color(0.38, 0.46, 0.56)
	env.ambient_light_energy = 0.55
	world.environment = env
	$Sun.light_energy = 0.62

func _process(delta: float) -> void:
	if state != State.RACING:
		return
	if not timing and absf(vehicle.linear_speed) > 0.08:
		timing = true
	if timing:
		elapsed += delta
		hud.set_time(elapsed)

func _physics_process(delta: float) -> void:
	if state == State.RACING and timing:
		_recording.append(vehicle.vehicle_model.global_transform)
	elif state == State.FINISHED and _ghost_tail > 0.0:
		_ghost_tail -= delta
		_recording.append(vehicle.vehicle_model.global_transform)
		if _ghost_tail <= 0.0:
			_commit_ghost()
	if state == State.RACING or state == State.FINISHED:
		_tick_ghosts()

func _enter_select() -> void:
	state = State.SELECTING
	timing = false
	elapsed = 0.0
	passed_checkpoint = false
	vehicle.control_enabled = false
	_commit_ghost()
	_clear_ghosts()
	_apply_car()
	vehicle.reset_to(spawn_transform)
	vehicle.set_frozen(true)
	view.start_orbit()
	hud.show_select(CARS[car_index]["name"], recent_times)

func _cycle_car(step: int) -> void:
	car_index = posmod(car_index + step, CARS.size())
	_apply_car()
	hud.set_car_name(CARS[car_index]["name"])

func _apply_car() -> void:
	var packed: PackedScene = load(CARS[car_index]["scene"])
	vehicle.apply_model(packed)
	vehicle.reset_to(spawn_transform)
	vehicle.set_frozen(true)

func _start_race() -> void:
	if state != State.SELECTING:
		return
	state = State.RACING
	timing = false
	elapsed = 0.0
	passed_checkpoint = false
	vehicle.reset_to(spawn_transform)
	vehicle.set_frozen(false)
	vehicle.control_enabled = true
	_recording.clear()
	_ghost_tail = 0.0
	_ghost_pending = false
	_spawn_ghosts()
	view.start_chase()
	hud.show_race()

func _on_finish_body_entered(_body: Node) -> void:
	if state != State.RACING:
		return
	if passed_checkpoint:
		_finish_lap()

func _on_checkpoint_body_entered(_body: Node) -> void:
	if state == State.RACING:
		passed_checkpoint = true

func _finish_lap() -> void:
	state = State.FINISHED
	timing = false
	vehicle.control_enabled = false
	recent_times.push_front({ "time": elapsed, "car": CARS[car_index]["name"] })
	if recent_times.size() > MAX_RECENT:
		recent_times.resize(MAX_RECENT)
	_ghost_pending = true
	_ghost_tail = GHOST_TAIL
	_save_times()
	hud.show_result(elapsed)

func _commit_ghost() -> void:
	if not _ghost_pending:
		return
	_ghost_pending = false
	_ghost_tail = 0.0
	if _recording.is_empty():
		return
	_ghost_runs.append({
		"time": elapsed,
		"scene": CARS[car_index]["scene"],
		"frames": _recording.duplicate(),
	})
	_ghost_runs.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	if _ghost_runs.size() > MAX_GHOSTS:
		_ghost_runs.resize(MAX_GHOSTS)

func _clear_ghosts() -> void:
	for ghost in _ghosts:
		if is_instance_valid(ghost.node):
			ghost.node.queue_free()
	_ghosts.clear()

func _spawn_ghosts() -> void:
	_clear_ghosts()
	for run in _ghost_runs:
		var packed: PackedScene = load(String(run["scene"]))
		if packed == null:
			continue
		var node: Node3D = packed.instantiate()
		_ghost_root.add_child(node)
		var meshes: Array[MeshInstance3D] = []
		_prepare_ghost(node, meshes)
		_ghosts.append({ "node": node, "frames": run["frames"], "index": 0, "meshes": meshes })
		node.global_transform = vehicle.vehicle_model.global_transform

func _prepare_ghost(n: Node, meshes: Array[MeshInstance3D]) -> void:
	if n is CollisionObject3D:
		(n as CollisionObject3D).collision_layer = 0
		(n as CollisionObject3D).collision_mask = 0
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var mat: Material = mi.get_active_material(i)
				if mat == null:
					mat = mesh.surface_get_material(i)
				if mat is BaseMaterial3D:
					var dup := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					dup.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					var c := dup.albedo_color
					c.a = 0.35
					dup.albedo_color = c
					mi.set_surface_override_material(i, dup)
		meshes.append(mi)
	for child in n.get_children():
		_prepare_ghost(child, meshes)

func _tick_ghosts() -> void:
	# Recordings start at launch, so hold ghosts on the grid until the player moves.
	var playing := timing or state == State.FINISHED
	var you := vehicle.get_vehicle_position()
	for ghost in _ghosts:
		var frames: Array = ghost["frames"]
		var index: int = ghost["index"]
		if not playing:
			continue
		if index < frames.size():
			(ghost["node"] as Node3D).global_transform = frames[index]
			ghost["index"] = index + 1
		var dist := (ghost["node"] as Node3D).global_position.distance_to(you)
		var alpha := clampf(remap(dist, GHOST_NEAR, GHOST_FAR, 0.04, 0.42), 0.04, 0.42)
		for mi in ghost["meshes"]:
			if not is_instance_valid(mi):
				continue
			var mesh: Mesh = mi.mesh
			if mesh == null:
				continue
			for i in mesh.get_surface_count():
				var mat: Material = mi.get_surface_override_material(i)
				if mat is BaseMaterial3D:
					var c := (mat as BaseMaterial3D).albedo_color
					c.a = alpha
					(mat as BaseMaterial3D).albedo_color = c

func _load_times() -> void:
	recent_times.clear()
	if not FileAccess.file_exists(TIMES_PATH):
		return
	var file := FileAccess.open(TIMES_PATH, FileAccess.READ)
	if file == null:
		return
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parts := line.split("|", false, 1)
		if parts.size() != 2:
			continue
		recent_times.append({ "time": parts[0].to_float(), "car": parts[1] })

func _save_times() -> void:
	var file := FileAccess.open(TIMES_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save laps to %s" % TIMES_PATH)
		return
	for row in recent_times:
		file.store_line("%.3f|%s" % [float(row["time"]), String(row["car"])])

func _on_hud_start_pressed() -> void:
	_start_race()

func _on_hud_next_car() -> void:
	if state == State.SELECTING:
		_cycle_car(1)

func _on_hud_prev_car() -> void:
	if state == State.SELECTING:
		_cycle_car(-1)

func _on_hud_restart_pressed() -> void:
	_enter_select()
