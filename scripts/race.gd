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
const MAX_STORED := 40
const MAX_GHOSTS := 4
const GHOST_NEAR := 4.0
const GHOST_FAR := 28.0
const GHOST_TAIL := 3.0
const LAP_OPTIONS := [1, 2, 3, 5]

enum State { SELECTING, RACING, FINISHED }
enum TimeMode { TOTAL, AVERAGE, BEST }

@onready var vehicle: Vehicle = $Vehicle
@onready var view = $View
@onready var hud = $HUD
@onready var finish_gate: Area3D = $Finish
@onready var checkpoint_gate: Area3D = $Checkpoint

var state: State = State.SELECTING
var car_index: int = 0
var spawn_transform: Transform3D
var elapsed: float = 0.0
var lap_elapsed: float = 0.0
var timing: bool = false
var passed_checkpoint: bool = false
var lap_choice: int = 2
var lap_target: int = 3
var time_mode: TimeMode = TimeMode.AVERAGE
var current_lap: int = 1
var lap_times: Array[float] = []
var recent_times: Array = []
var _recording: Array[Transform3D] = []
var _ghost_runs: Array = []
var _ghosts: Array = []
var _ghost_root: Node3D
var _ghost_tail := 0.0
var _ghost_pending := false
var _prev_gate_pos := Vector3.ZERO
var _lap_lock := 0.0

func _ready() -> void:
	spawn_transform = vehicle.global_transform
	_ghost_root = Node3D.new()
	_ghost_root.name = "Ghosts"
	add_child(_ghost_root)
	_load_times()
	_enter_select()

func _process(delta: float) -> void:
	if state != State.RACING:
		return
	if not timing and absf(vehicle.linear_speed) > 0.08:
		timing = true
	if timing:
		elapsed += delta
		lap_elapsed += delta
		_refresh_race_hud()

func _physics_process(delta: float) -> void:
	if state == State.RACING:
		_poll_gates(delta)
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
	lap_elapsed = 0.0
	passed_checkpoint = false
	current_lap = 1
	lap_times.clear()
	_lap_lock = 0.0
	vehicle.control_enabled = false
	_commit_ghost()
	_clear_ghosts()
	_apply_car()
	vehicle.reset_to(spawn_transform)
	vehicle.set_frozen(true)
	view.start_orbit()
	hud.show_select(CARS[car_index]["name"], _times_for_menu(), lap_target, _mode_label())

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
	lap_elapsed = 0.0
	passed_checkpoint = false
	current_lap = 1
	lap_times.clear()
	vehicle.reset_to(spawn_transform)
	vehicle.set_frozen(false)
	vehicle.control_enabled = true
	_recording.clear()
	_ghost_tail = 0.0
	_ghost_pending = false
	_spawn_ghosts()
	view.start_chase()
	hud.show_race()
	_prev_gate_pos = vehicle.get_vehicle_position()
	_lap_lock = 0.0
	_refresh_race_hud()

func _on_finish_body_entered(_body: Node) -> void:
	_try_complete_lap()

func _on_checkpoint_body_entered(_body: Node) -> void:
	if state == State.RACING:
		passed_checkpoint = true

func _poll_gates(delta: float) -> void:
	if _lap_lock > 0.0:
		_lap_lock -= delta
	var pos := vehicle.get_vehicle_position()
	if _entered_gate(checkpoint_gate, _prev_gate_pos, pos) or _point_in_gate(checkpoint_gate, pos):
		passed_checkpoint = true
	if _entered_gate(finish_gate, _prev_gate_pos, pos):
		_try_complete_lap()
	_prev_gate_pos = pos

func _try_complete_lap() -> void:
	if state != State.RACING:
		return
	if not passed_checkpoint:
		return
	if _lap_lock > 0.0:
		return
	_complete_lap()

func _complete_lap() -> void:
	passed_checkpoint = false
	_lap_lock = 2.0
	lap_times.append(lap_elapsed)
	lap_elapsed = 0.0
	if lap_times.size() >= lap_target:
		_finish_race()
		return
	current_lap = lap_times.size() + 1
	_refresh_race_hud()

func _entered_gate(area: Area3D, prev: Vector3, curr: Vector3) -> bool:
	var was_inside := _point_in_gate(area, prev)
	if was_inside:
		return false
	return _point_in_gate(area, curr) or _segment_hits_gate(area, prev, curr)

func _gate_local(area: Area3D, world: Vector3) -> Vector3:
	var cs := area.get_child(0) as CollisionShape3D
	var xf := area.global_transform
	if cs != null:
		xf *= cs.transform
	return xf.affine_inverse() * world

func _gate_half(area: Area3D) -> Vector3:
	var cs := area.get_child(0) as CollisionShape3D
	if cs == null or not (cs.shape is BoxShape3D):
		return Vector3(8, 4, 8)
	return (cs.shape as BoxShape3D).size * 0.5

func _point_in_gate(area: Area3D, world: Vector3) -> bool:
	var local := _gate_local(area, world)
	var half := _gate_half(area)
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z

func _segment_hits_gate(area: Area3D, prev: Vector3, curr: Vector3) -> bool:
	var a := _gate_local(area, prev)
	var b := _gate_local(area, curr)
	var half := _gate_half(area)
	var dir := b - a
	var tmin := 0.0
	var tmax := 1.0
	for i in 3:
		var origin := a[i]
		var d := dir[i]
		var lo := -half[i]
		var hi := half[i]
		if absf(d) < 0.000001:
			if origin < lo or origin > hi:
				return false
			continue
		var t1 := (lo - origin) / d
		var t2 := (hi - origin) / d
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return false
	return true

func _finish_race() -> void:
	state = State.FINISHED
	timing = false
	vehicle.control_enabled = false
	var scored := _scored_time()
	recent_times.push_front({
		"time": scored,
		"car": CARS[car_index]["name"],
		"laps": lap_target,
		"mode": _mode_key(),
	})
	if recent_times.size() > MAX_STORED:
		recent_times.resize(MAX_STORED)
	_ghost_pending = true
	_ghost_tail = GHOST_TAIL
	_save_times()
	hud.show_result(scored, _result_caption(), _lap_breakdown())
	_refresh_race_hud()

func _commit_ghost() -> void:
	if not _ghost_pending:
		return
	_ghost_pending = false
	_ghost_tail = 0.0
	if _recording.is_empty():
		return
	_ghost_runs.append({
		"time": _scored_time(),
		"scene": CARS[car_index]["scene"],
		"laps": lap_target,
		"mode": _mode_key(),
		"frames": _recording.duplicate(),
	})
	var matching: Array = []
	var other: Array = []
	for run in _ghost_runs:
		if int(run.get("laps", 1)) == lap_target and String(run.get("mode", "total")) == _mode_key():
			matching.append(run)
		else:
			other.append(run)
	matching.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	if matching.size() > MAX_GHOSTS:
		matching.resize(MAX_GHOSTS)
	_ghost_runs = other + matching

func _clear_ghosts() -> void:
	for ghost in _ghosts:
		if is_instance_valid(ghost.node):
			ghost.node.queue_free()
	_ghosts.clear()

func _spawn_ghosts() -> void:
	_clear_ghosts()
	for run in _ghost_runs:
		if int(run.get("laps", 1)) != lap_target or String(run.get("mode", "total")) != _mode_key():
			continue
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
		var parts := line.split("|")
		if parts.size() < 2:
			continue
		var row := { "time": parts[0].to_float(), "car": parts[1], "laps": 1, "mode": "total" }
		if parts.size() >= 4:
			row["laps"] = parts[2].to_int()
			row["mode"] = parts[3]
		recent_times.append(row)

func _save_times() -> void:
	var file := FileAccess.open(TIMES_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save laps to %s" % TIMES_PATH)
		return
	for row in recent_times:
		file.store_line("%.3f|%s|%d|%s" % [
			float(row["time"]),
			String(row["car"]),
			int(row.get("laps", 1)),
			String(row.get("mode", "total")),
		])

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

func _on_hud_prev_laps() -> void:
	if state != State.SELECTING:
		return
	lap_choice = posmod(lap_choice - 1, LAP_OPTIONS.size())
	lap_target = int(LAP_OPTIONS[lap_choice])
	_refresh_select_options()

func _on_hud_next_laps() -> void:
	if state != State.SELECTING:
		return
	lap_choice = posmod(lap_choice + 1, LAP_OPTIONS.size())
	lap_target = int(LAP_OPTIONS[lap_choice])
	_refresh_select_options()

func _on_hud_prev_mode() -> void:
	if state != State.SELECTING:
		return
	time_mode = wrapi(int(time_mode) - 1, 0, 3) as TimeMode
	_refresh_select_options()

func _on_hud_next_mode() -> void:
	if state != State.SELECTING:
		return
	time_mode = wrapi(int(time_mode) + 1, 0, 3) as TimeMode
	_refresh_select_options()

func _refresh_select_options() -> void:
	hud.set_race_options(lap_target, _mode_label())
	hud.set_recent_times(_times_for_menu())

func _times_for_menu() -> Array:
	var out: Array = []
	for row in recent_times:
		if not (row is Dictionary):
			continue
		if int(row.get("laps", 1)) != lap_target:
			continue
		if String(row.get("mode", "total")) != _mode_key():
			continue
		out.append(row)
		if out.size() >= MAX_RECENT:
			break
	return out

func _mode_key() -> String:
	match time_mode:
		TimeMode.AVERAGE:
			return "avg"
		TimeMode.BEST:
			return "best"
		_:
			return "total"

func _mode_label() -> String:
	match time_mode:
		TimeMode.AVERAGE:
			return "AVERAGE"
		TimeMode.BEST:
			return "BEST"
		_:
			return "TOTAL"

func _result_caption() -> String:
	var laps := "%d LAP" % lap_target
	if lap_target != 1:
		laps += "S"
	return "%s · %s" % [laps, _mode_label()]

func _lap_breakdown() -> String:
	if lap_times.size() <= 1:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for i in lap_times.size():
		parts.append("%d %s" % [i + 1, hud.format_time(lap_times[i])])
	return "  ".join(parts)

func _scored_time() -> float:
	if lap_times.is_empty():
		return elapsed
	var total := 0.0
	var best := lap_times[0]
	for t in lap_times:
		total += t
		if t < best:
			best = t
	match time_mode:
		TimeMode.AVERAGE:
			return total / float(lap_times.size())
		TimeMode.BEST:
			return best
		_:
			return total

func _refresh_race_hud() -> void:
	var clock := elapsed if time_mode == TimeMode.TOTAL else lap_elapsed
	hud.set_time(clock)
	var info := "LAP %d/%d" % [current_lap, lap_target]
	if time_mode == TimeMode.BEST and not lap_times.is_empty():
		info += "   BEST %s" % hud.format_time(_best_lap())
	elif time_mode == TimeMode.AVERAGE and not lap_times.is_empty():
		info += "   AVG %s" % hud.format_time(_average_completed())
	hud.set_lap_info(info)

func _best_lap() -> float:
	var best := lap_times[0]
	for t in lap_times:
		if t < best:
			best = t
	return best

func _average_completed() -> float:
	var total := 0.0
	for t in lap_times:
		total += t
	return total / float(lap_times.size())
