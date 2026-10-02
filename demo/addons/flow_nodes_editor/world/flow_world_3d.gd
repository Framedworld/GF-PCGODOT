@tool
class_name FlowWorld3D
extends Node3D

## Hierarchical and runtime generation of one graph over a world (Unreal's
## partitioned UPCGComponent, its grid of partition actors and the runtime
## generation scheduler).
##
## The graph is split into levels at compile time: nodes downstream of a
## grid_size marker run once per cell of that size, nodes with no marker
## upstream once for the whole world (the Unbounded level, level 0). Each
## generated cell is a FlowGraphNode3D child named FlowCell_L<level>_<x>_<z>
## (FlowCell_L0_0_0 for the Unbounded run) that evaluates only its level's
## nodes (FlowGraphNode3D.generate_cell). The outputs of coarser levels a cell
## consumes are handed in whole from the coarser cell that contains it, which is
## generated first and whose results are kept while it is generated. Spawners
## spawn into the cell component, so cleaning a cell up frees exactly its
## content.
##
## Generation modes:
##   Manual   nothing happens on its own; use generate_all(), generate_bounds(),
##            generate_cell(), cleanup_cell(), cleanup_all() (synchronous).
##   OnLoad   when the game starts, every cell of world_bounds is queued and
##            generated over the following frames within frame_budget_ms.
##   Runtime  every frame, cells within each level's generation radius of a
##            generation source are queued and generated time-sliced; cells
##            farther than radius * cleanup_radius_multiplier from every source
##            are cleaned up and their components pooled.
##
## Coordinates: world_bounds, cells and sources are in global space. Keep the
## FlowWorld3D at the identity transform (cells are children at identity, like
## the content of a FlowGraphNode3D).

enum GenerationMode { Manual, OnLoad, Runtime }
## Scheduler state of a cell. NONE: the world has no record of it.
enum CellState { NONE = -1, Queued = 0, Generating = 1, Generated = 2, CleaningUp = 3 }

## Group of the nodes that act as generation sources (see FlowGenerationSource).
const SOURCE_GROUP := &"flow_generation_source"
## The Unbounded level.
const UNBOUNDED := 0
## Generation radius of the Unbounded level when generation_radius has no
## entry for 0 (256 world units, measured to the world bounds footprint).
const DEFAULT_UNBOUNDED_RADIUS := 256.0

## A cell finished generating (its component emitted `generated`).
signal cell_generated(level : int, coord : Vector2i)
## A generated (or generating) cell was cleaned up.
signal cell_cleaned_up(level : int, coord : Vector2i)
## generate_all() / generate_bounds() finished, or the scheduler went idle after
## generating.
signal all_generated

@export var graph : FlowGraphResource
## Graph seed, passed unchanged to every cell (position-hashed randomness stays
## continuous across cell edges). 0 keeps every node's own random_seed.
@export var seed : int = 0
## Graph input values, as FlowGraphNode3D.args.
@export var args : Dictionary = {}
## Runtime parameters for every cell (EvaluationContext.runtime_params).
@export var params : Dictionary = {}
## Per-node setting overrides for every cell, as FlowGraphNode3D.overrides.
@export var overrides : Dictionary = {}
## The generated area, global space. Cells cover it on XZ; its Y range is the
## height of every cell.
@export var world_bounds : AABB = AABB(Vector3(-128.0, -64.0, -128.0), Vector3(256.0, 128.0, 256.0))
@export var generation_mode : GenerationMode = GenerationMode.Manual

@export_group("Runtime Generation")
## Generation radius per level: grid size (int) -> radius in world units, 0 for
## the Unbounded level (distance to world_bounds). A level without an entry
## uses its grid size (one cell); the Unbounded level
## uses DEFAULT_UNBOUNDED_RADIUS.
@export var generation_radius : Dictionary = {}
## A generated cell is cleaned up once every source is farther than
## generation radius * this (hysteresis against churn at the edge).
@export_range(1.0, 4.0, 0.01, "or_greater") var cleanup_radius_multiplier : float = 1.1
## Wall-clock budget per frame for the scheduler (element granularity: a single
## node is never interrupted, and at least one unit of work runs per frame).
@export var frame_budget_ms : float = 4.0
## Cells generating at the same time (their elements are interleaved).
@export_range(1, 64, 1, "or_greater") var max_concurrent_cells : int = 2
## Extra generation sources besides the members of SOURCE_GROUP.
@export var sources : Array[NodePath] = []
## Cleaned-up cell components kept for reuse instead of being freed.
@export_range(0, 1024, 1, "or_greater") var cell_pool_size : int = 32

@export_group("Execution")
## Synchronous cell generation runs independent pure nodes on worker threads
## (FlowGraphNode3D.threaded). The time-sliced scheduler keeps each cell's
## top level sequential, as generate_async does.
@export var threaded : bool = false
## Reuse the outputs of pure nodes across cells and regenerations
## (FlowGraphNode3D.output_cache).
@export var output_cache : bool = false

## Injectable clock for the scheduler budget: () -> int microseconds. Defaults
## to Time.get_ticks_usec.
var clock : Callable = Callable()
## Injectable source provider: () -> Array of Vector3, Node3D or
## { "position": Vector3, "radius_scale": float }. Defaults to the members of
## SOURCE_GROUP plus `sources`.
var source_provider : Callable = Callable()

## Statistics: cell components created and reused from the pool, elements
## stepped and cells started by the last tick().
var components_created : int = 0
var components_reused : int = 0
var last_tick_elements : int = 0
var last_tick_started : int = 0
var last_tick_cleaned : int = 0

class CellRecord:
	extends RefCounted
	var level : int = 0
	var coord : Vector2i = Vector2i.ZERO
	var key : Vector3i = Vector3i.ZERO
	var state : int = 0
	var component : FlowGraphNode3D = null
	var run : FlowCellRun = null
	var outputs : Dictionary = {}
	var captured : Dictionary = {}
	var variables : Dictionary = {}
	var errors : Array = []
	## Priority distance (XZ distance from the nearest source to the cell centre).
	var distance : float = 0.0
	## Requested through the manual API or OnLoad: never cleaned up by the
	## runtime scheduler.
	var manual : bool = false

var _cells : Dictionary = {}		# Vector3i key -> CellRecord
var _active : Array = []			# records in Generating, time-sliced
var _pool : Array = []				# pooled FlowGraphNode3D components (out of the tree)
var _rr : int = 0
var _was_busy : bool = false

# --- Inspector buttons ------------------------------------------------------------------

func _get_property_list() -> Array:
	return [
		{ "name": "generate_all_cells", "type": TYPE_CALLABLE, "hint": PROPERTY_HINT_TOOL_BUTTON, "hint_string": "Generate All", "usage": PROPERTY_USAGE_EDITOR },
		{ "name": "cleanup_all_cells", "type": TYPE_CALLABLE, "hint": PROPERTY_HINT_TOOL_BUTTON, "hint_string": "Cleanup All", "usage": PROPERTY_USAGE_EDITOR },
	]

func _get(property : StringName):
	match property:
		"generate_all_cells":
			return generate_all
		"cleanup_all_cells":
			return cleanup_all
	return null

# --- Lifecycle ----------------------------------------------------------------------------

func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint() or graph == null:
		return
	match generation_mode:
		GenerationMode.OnLoad:
			queue_all()
			set_process(true)
		GenerationMode.Runtime:
			set_process(true)

func _process(_delta : float) -> void:
	tick()
	if generation_mode != GenerationMode.Runtime and not is_busy():
		set_process(false)

func _notification(what : int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for record in _active:
			if record.run != null:
				record.run.cancel()
		_active.clear()
		for comp in _pool:
			if is_instance_valid(comp):
				comp.free()
		_pool.clear()

# --- Levels and cells ---------------------------------------------------------------------

## Levels of the graph, coarsest first: 0 (Unbounded) when some node has no
## grid_size marker upstream, then the grid sizes, largest first.
func get_levels() -> PackedInt32Array:
	var compiled := _compiled()
	return compiled.levels() if compiled != null else PackedInt32Array()

## Execution bounds of a cell (cell box intersected with world_bounds).
func get_cell_bounds(level : int, coord : Vector2i) -> AABB:
	return FlowWorldGrid.execution_bounds(coord, level, world_bounds)

## Cell of `level` that owns `world_pos` (half-open).
func get_cell_at(world_pos : Vector3, level : int) -> Vector2i:
	return FlowWorldGrid.coord_of(world_pos, level)

## Keys Vector3i(level, x, z) of the coarser cells (every coarser level of the
## graph, Unbounded included) that contain cell (level, coord), coarsest first.
func get_parent_cells(level : int, coord : Vector2i) -> Array[Vector3i]:
	var result : Array[Vector3i] = []
	for parent_level in get_levels():
		if FlowWorldGrid.is_coarser(parent_level, level):
			result.append(FlowWorldCell.key_of(parent_level, FlowWorldGrid.parent_coord(coord, level, parent_level)))
	return result

## CellState of a cell (CellState.NONE when the world has no record of it).
func get_cell_state(level : int, coord : Vector2i) -> int:
	var record : CellRecord = _cells.get(_key(level, coord))
	return record.state if record != null else CellState.NONE

## Outputs of a generated cell (output name -> FlowData.Data), {} otherwise.
func get_cell_outputs(level : int, coord : Vector2i) -> Dictionary:
	var record : CellRecord = _cells.get(_key(level, coord))
	return record.outputs if record != null else {}

## Node errors of the cell's last generation.
func get_cell_errors(level : int, coord : Vector2i) -> Array:
	var record : CellRecord = _cells.get(_key(level, coord))
	return record.errors if record != null else []

## The FlowGraphNode3D of a cell (null when it has none).
func get_cell_component(level : int, coord : Vector2i) -> FlowGraphNode3D:
	var record : CellRecord = _cells.get(_key(level, coord))
	return record.component if record != null else null

## Keys Vector3i(level, x, z) of every cell the world knows, optionally only
## those in `state`.
func get_cells(state : int = CellState.NONE) -> Array[Vector3i]:
	var result : Array[Vector3i] = []
	for key in _cells:
		if state == CellState.NONE or _cells[key].state == state:
			result.append(key)
	return result

## Pooled (cleaned up, reusable) cell components.
func get_pool_size() -> int:
	return _pool.size()

## True while cells are queued, generating or waiting for cleanup.
func is_busy() -> bool:
	for key in _cells:
		if _cells[key].state != CellState.Generated:
			return true
	return false

# --- Manual API (synchronous) --------------------------------------------------------------

## Generates every cell of world_bounds on every level, coarse levels first.
func generate_all() -> void:
	generate_bounds(world_bounds)

## Generates the cells of every level that overlap `aabb` (clipped to
## world_bounds), coarse levels first, then emits all_generated.
func generate_bounds(aabb : AABB) -> void:
	if graph == null:
		return
	for level in get_levels():
		if level == UNBOUNDED:
			if _overlaps_world(aabb):
				generate_cell(UNBOUNDED, Vector2i.ZERO)
			continue
		for coord in FlowWorldGrid.cells_in(aabb, level, world_bounds):
			generate_cell(level, coord)
	all_generated.emit()

## Generates one cell synchronously (its coarser cells first, when they are not
## generated yet) and returns its outputs. A generated cell is returned as is
## unless `force`. A cell the scheduler is generating is finished now.
func generate_cell(level : int, coord : Vector2i, force : bool = false) -> Dictionary:
	if graph == null:
		return {}
	if not get_levels().has(level):
		push_error("FlowWorld3D: the graph has no level %d (levels: %s)" % [level, get_levels()])
		return {}
	if level != UNBOUNDED:
		var bounds := get_cell_bounds(level, coord)
		if bounds.size.x <= 0.0 or bounds.size.z <= 0.0:
			push_error("FlowWorld3D: cell %s is outside world_bounds" % FlowWorldGrid.cell_name(level, coord))
			return {}
	else:
		coord = Vector2i.ZERO
	var record : CellRecord = _cells.get(_key(level, coord))
	if record != null:
		record.manual = true
		if record.state == CellState.CleaningUp:
			record.state = CellState.Generated
		if record.state == CellState.Generating:
			_active.erase(record)
			record.run.run()
			_complete(record)
		if record.state == CellState.Generated and not force:
			return record.outputs
	for parent_key in get_parent_cells(level, coord):
		generate_cell(parent_key.x, Vector2i(parent_key.y, parent_key.z))
	if record == null:
		record = _new_record(level, coord)
		record.manual = true
	_start(record, false)
	record.run.run()
	_complete(record)
	return record.outputs

## Cleans up one cell now: cancels its run, frees its spawned content and pools
## its component. Finer cells generated from it keep their content.
func cleanup_cell(level : int, coord : Vector2i) -> void:
	var record : CellRecord = _cells.get(_key(level, coord if level != UNBOUNDED else Vector2i.ZERO))
	if record != null:
		_cleanup(record)

## Cleans up every cell, finest level first, and clears the queue.
func cleanup_all() -> void:
	var records : Array = _cells.values()
	records.sort_custom(func(a, b): return FlowWorldGrid.is_coarser(b.level, a.level))
	for record in records:
		_cleanup(record)
	_active.clear()
	_was_busy = false

## Queues every cell of world_bounds for the scheduler (what OnLoad does).
func queue_all() -> void:
	queue_bounds(world_bounds)

## Queues the cells of every level overlapping `aabb` for the scheduler; tick()
## (every frame in OnLoad and Runtime mode) generates them.
func queue_bounds(aabb : AABB) -> void:
	var center := aabb.get_center()
	for level in get_levels():
		var coords : Array[Vector2i] = []
		if level != UNBOUNDED:
			coords = FlowWorldGrid.cells_in(aabb, level, world_bounds)
		elif _overlaps_world(aabb):
			coords.append(Vector2i.ZERO)
		for coord in coords:
			var key := _key(level, coord)
			var record : CellRecord = _cells.get(key)
			if record == null:
				record = _new_record(level, coord)
				record.distance = _center_distance(center, level, coord)
			elif record.state == CellState.CleaningUp:
				record.state = CellState.Generated
			record.manual = true

# --- Scheduler -------------------------------------------------------------------------------

## One scheduler frame: in Runtime mode, updates the wanted cells from the
## generation sources (queue new ones, clean up far ones); then cleans up,
## starts and steps cells until frame_budget_ms is spent on `clock`.
## Called from _process in OnLoad and Runtime mode; tests call it directly.
func tick() -> void:
	last_tick_elements = 0
	last_tick_started = 0
	last_tick_cleaned = 0
	if graph == null:
		return
	if generation_mode == GenerationMode.Runtime:
		_update_runtime_targets()
	# Work queued this frame counts, even when it also finishes this frame.
	_was_busy = _was_busy or is_busy()
	var start := _now()
	var budget_us := int(maxf(frame_budget_ms, 0.0) * 1000.0)
	var worked := false
	# 1. Pending cleanups, finest level first.
	var doomed : Array = []
	for key in _cells:
		if _cells[key].state == CellState.CleaningUp:
			doomed.append(_cells[key])
	doomed.sort_custom(func(a, b): return FlowWorldGrid.is_coarser(b.level, a.level))
	for record in doomed:
		if worked and _now() - start >= budget_us:
			break
		_cleanup(record)
		last_tick_cleaned += 1
		worked = true
	# 2. Start runnable cells and step the active ones, one element at a time.
	while true:
		if worked and _now() - start >= budget_us:
			break
		_fill_active()
		if _active.is_empty():
			break
		_rr = _rr % _active.size()
		var record : CellRecord = _active[_rr]
		var finished := record.run.step(0.0)
		last_tick_elements += 1
		worked = true
		if finished:
			_active.remove_at(_rr)
			_complete(record)
		else:
			_rr += 1
	var busy := is_busy()
	if _was_busy and not busy:
		all_generated.emit()
	_was_busy = busy

## The generation sources this frame: [{ "position": Vector3, "radius_scale": float }].
func get_generation_sources() -> Array:
	var raw : Array = source_provider.call() if source_provider.is_valid() else _collect_sources()
	var result : Array = []
	for entry in raw:
		if entry is Vector3:
			result.append({ "position": entry, "radius_scale": 1.0 })
		elif entry is Dictionary:
			result.append({ "position": entry.get("position", Vector3.ZERO), "radius_scale": float(entry.get("radius_scale", 1.0)) })
		elif entry is Node3D and is_instance_valid(entry):
			result.append(_source_entry(entry))
	return result

## Generation radius of a level (see generation_radius).
func get_generation_radius(level : int) -> float:
	if generation_radius.has(level):
		return float(generation_radius[level])
	if generation_radius.has(str(level)):
		return float(generation_radius[str(level)])
	return DEFAULT_UNBOUNDED_RADIUS if level == UNBOUNDED else float(level)

# --- Internals: records ----------------------------------------------------------------------

func _compiled() -> FlowCompiledGraph:
	return FlowCompiledGraph.for_graph(graph) if graph != null else null

static func _key(level : int, coord : Vector2i) -> Vector3i:
	return FlowWorldCell.key_of(level, coord)

func _new_record(level : int, coord : Vector2i) -> CellRecord:
	var record := CellRecord.new()
	record.level = level
	record.coord = coord
	record.key = _key(level, coord)
	record.state = CellState.Queued
	_cells[record.key] = record
	return record

func _overlaps_world(aabb : AABB) -> bool:
	return aabb.position.x < world_bounds.end.x and aabb.end.x > world_bounds.position.x \
		and aabb.position.z < world_bounds.end.z and aabb.end.z > world_bounds.position.z

func _center_distance(p : Vector3, level : int, coord : Vector2i) -> float:
	var c := get_cell_bounds(level, coord).get_center()
	return Vector2(p.x - c.x, p.z - c.z).length()

func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_usec()

# Starts the evaluation of `record` on a (pooled or new) component.
func _start(record : CellRecord, time_sliced : bool) -> void:
	var cell := FlowWorldCell.for_graph(graph, record.level, record.coord, world_bounds)
	var preseeded := {}
	var variables := {}
	var compiled := _compiled()
	for parent_key in get_parent_cells(record.level, record.coord):
		var parent : CellRecord = _cells.get(parent_key)
		if parent == null:
			continue
		for variable_name in parent.variables:
			variables[variable_name] = parent.variables[variable_name]
	for node_name in compiled.level_plan(record.level)["preseed"]:
		var src_level := compiled.level_of(node_name)
		var parent_key := _key(src_level, FlowWorldGrid.parent_coord(record.coord, record.level, src_level))
		var parent : CellRecord = _cells.get(parent_key)
		if parent != null and parent.captured.has(node_name):
			preseeded[node_name] = parent.captured[node_name]
	cell.variables = variables
	if record.component == null:
		record.component = _acquire_component(record)
	record.run = record.component.begin_cell(cell, preseeded, time_sliced)
	record.state = CellState.Generating

func _complete(record : CellRecord) -> void:
	var run := record.run
	record.run = null
	if run != null:
		record.outputs = run.outputs
		record.captured = run.captured
		record.variables = run.variables
		record.errors = run.errors
	record.state = CellState.Generated
	cell_generated.emit(record.level, record.coord)

func _cleanup(record : CellRecord) -> void:
	_active.erase(record)
	if record.run != null:
		record.run.cancel()
		record.run = null
	var had_content := record.component != null
	if record.component != null:
		_release_component(record.component)
		record.component = null
	_cells.erase(record.key)
	record.state = CellState.NONE
	if had_content:
		cell_cleaned_up.emit(record.level, record.coord)

func _acquire_component(record : CellRecord) -> FlowGraphNode3D:
	var comp : FlowGraphNode3D = null
	while comp == null and not _pool.is_empty():
		var pooled = _pool.pop_back()
		if is_instance_valid(pooled):
			comp = pooled
	if comp != null:
		components_reused += 1
	else:
		comp = FlowGraphNode3D.new()
		components_created += 1
	comp.generate_on_ready = false
	comp.transient_output = true
	comp.async_generation = false
	comp.graph = graph
	comp.seed = seed
	comp.args = args
	comp.params = params
	comp.overrides = overrides
	comp.threaded = threaded
	comp.output_cache = output_cache
	comp.name = FlowWorldGrid.cell_name(record.level, record.coord)
	comp.set_meta(&"flow_cell", record.key)
	comp.transform = Transform3D.IDENTITY
	if comp.get_parent() == null:
		add_child(comp)
	return comp

func _release_component(comp : FlowGraphNode3D) -> void:
	if not is_instance_valid(comp):
		return
	comp.cleanup()
	if comp.get_parent() != null:
		comp.get_parent().remove_child(comp)
	comp.remove_meta(&"flow_cell")
	if _pool.size() < cell_pool_size:
		_pool.append(comp)
	else:
		comp.free()

# Fills the active set with the best runnable queued cells: coarser levels
# first, then nearest, then key order. A queued cell whose coarser cell is
# missing queues that cell (it is then kept alive by its queued child).
func _fill_active() -> void:
	var limit := maxi(1, max_concurrent_cells)
	while _active.size() < limit:
		var best : CellRecord = null
		for key in _cells.keys():
			var record : CellRecord = _cells.get(key)
			if record == null or record.state != CellState.Queued:
				continue
			if not _parents_ready(record):
				continue
			if best == null or _before(record, best):
				best = record
		if best == null:
			return
		_start(best, true)
		_active.append(best)
		last_tick_started += 1

func _parents_ready(record : CellRecord) -> bool:
	var ready := true
	for parent_key in get_parent_cells(record.level, record.coord):
		var parent : CellRecord = _cells.get(parent_key)
		if parent == null:
			parent = _new_record(parent_key.x, Vector2i(parent_key.y, parent_key.z))
			parent.distance = record.distance
			parent.manual = record.manual
			ready = false
		elif parent.state == CellState.CleaningUp:
			parent.state = CellState.Generated
		elif parent.state != CellState.Generated:
			ready = false
	return ready

static func _before(a : CellRecord, b : CellRecord) -> bool:
	if a.level != b.level:
		return FlowWorldGrid.is_coarser(a.level, b.level)
	if a.distance != b.distance:
		return a.distance < b.distance
	if a.coord.y != b.coord.y:
		return a.coord.y < b.coord.y
	return a.coord.x < b.coord.x

# --- Internals: runtime targets ----------------------------------------------------------------

func _collect_sources() -> Array:
	var result : Array = []
	if not is_inside_tree():
		return result
	var seen := {}
	var candidates : Array = get_tree().get_nodes_in_group(SOURCE_GROUP)
	for path in sources:
		var node := get_node_or_null(path)
		if node != null:
			candidates.append(node)
	for node in candidates:
		if not (node is Node3D) or not node.is_inside_tree() or seen.has(node.get_instance_id()):
			continue
		seen[node.get_instance_id()] = true
		if node.get("enabled") == false:
			continue
		result.append(node)
	return result

static func _source_entry(node : Node3D) -> Dictionary:
	var scale = node.get("radius_scale")
	return { "position": node.global_position, "radius_scale": float(scale) if scale != null else 1.0 }

# Cells of `level` inside the world whose footprint is within `r` of `p`
# (distance <= r, so a cell exactly r away is included).
func _cells_near(p : Vector3, r : float, level : int) -> Array[Vector2i]:
	var result : Array[Vector2i] = []
	if level <= 0 or r < 0.0 or is_inf(r):
		return result if not is_inf(r) else FlowWorldGrid.cells_in(world_bounds, level, world_bounds)
	var x0 := maxi(int(ceil((p.x - r) / level)) - 1, int(floor(world_bounds.position.x / level)))
	var x1 := mini(int(floor((p.x + r) / level)), int(ceil(world_bounds.end.x / level)) - 1)
	var z0 := maxi(int(ceil((p.z - r) / level)) - 1, int(floor(world_bounds.position.z / level)))
	var z1 := mini(int(floor((p.z + r) / level)), int(ceil(world_bounds.end.z / level)) - 1)
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			var bounds := get_cell_bounds(level, Vector2i(cx, cz))
			if bounds.size.x <= 0.0 or bounds.size.z <= 0.0:
				continue
			if FlowWorldGrid.distance_to_footprint(p, bounds) <= r:
				result.append(Vector2i(cx, cz))
	return result

# Queues the cells the sources want, revives cells waiting for cleanup that are
# wanted again, and marks for cleanup the cells no source keeps (finest level
# first, so a cell still needed by a finer cell is kept).
func _update_runtime_targets() -> void:
	var srcs := get_generation_sources()
	var levels := get_levels()
	var wanted := {}	# key -> priority distance
	for level in levels:
		var base_radius := get_generation_radius(level)
		for src in srcs:
			var p : Vector3 = src.position
			var r : float = base_radius * float(src.radius_scale)
			if level == UNBOUNDED:
				if FlowWorldGrid.distance_to_footprint(p, world_bounds) <= r:
					var k0 := _key(UNBOUNDED, Vector2i.ZERO)
					wanted[k0] = minf(wanted.get(k0, INF), _center_distance(p, UNBOUNDED, Vector2i.ZERO))
				continue
			for coord in _cells_near(p, r, level):
				var k := _key(level, coord)
				wanted[k] = minf(wanted.get(k, INF), _center_distance(p, level, coord))
	for key in wanted:
		var record : CellRecord = _cells.get(key)
		if record == null:
			record = _new_record(key.x, Vector2i(key.y, key.z))
		elif record.state == CellState.CleaningUp:
			record.state = CellState.Generated
		record.distance = wanted[key]
	# Cleanup, finest level first.
	var pinned := {}
	var ordered_levels := Array(levels)
	ordered_levels.reverse()
	for level in ordered_levels:
		var cleanup_radius := get_generation_radius(level) * cleanup_radius_multiplier
		for key in _cells.keys():
			var record : CellRecord = _cells.get(key)
			if record == null or record.level != level or record.state == CellState.CleaningUp:
				continue
			var keep : bool = record.manual or wanted.has(key) or pinned.has(key)
			if not keep and record.state != CellState.Queued:
				var bounds := get_cell_bounds(record.level, record.coord) if level != UNBOUNDED else world_bounds
				for src in srcs:
					if FlowWorldGrid.distance_to_footprint(src.position, bounds) <= cleanup_radius * float(src.radius_scale):
						keep = true
						break
			if keep:
				for parent_key in get_parent_cells(record.level, record.coord):
					pinned[parent_key] = true
				continue
			if record.state == CellState.Queued:
				_cells.erase(key)
			else:
				if record.run != null:
					_active.erase(record)
					record.run.cancel()
					record.run = null
				record.state = CellState.CleaningUp
