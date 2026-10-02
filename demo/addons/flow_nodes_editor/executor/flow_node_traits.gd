@tool
class_name FlowNodeTraits
extends RefCounted

## Execution traits of node templates, used by FlowExecutor (threaded mode) and
## FlowOutputCache. Derived from a central table and from existing meta flags,
## so no node script has to declare anything:
##
##   main_thread  The element touches the scene tree, physics, rendering or
##                files of the scene, spawns nodes, reads or writes the
##                evaluation context's mutable state (variables, runtime
##                params), runs a nested graph, or prints. It always runs on the
##                main thread, in the sequential order relative to every other
##                main-thread element of the same graph.
##   cacheable    The element's outputs are a pure function of its settings
##                (after overrides and bindings), the effective seed and the
##                content of its inputs, without side effects. Only these
##                elements are stored in FlowOutputCache.
##
## Resolution, first match wins:
##   1. meta_node["main_thread"] (bool) and/or meta_node["pure"] (bool) on the
##      node script. "pure": true means cacheable and, unless "main_thread" is
##      also given, safe off the main thread; "pure": false means neither
##      cacheable nor (unless "main_thread": false) threadable.
##   2. TABLE below (every stock template).
##   3. meta flags: scans_scene, queries_physics or is_final -> main thread,
##      not cacheable.
##   4. Anything else (third-party templates): main thread, not cacheable.
## When a meta_node flag gives a different result than the template's TABLE
## row, resolve() still lets the meta win but prints a warning, once per
## template, so the override is not silent (override_warnings() lists them).

## template -> [main_thread, cacheable]
const TABLE := {
	# Scene, physics, rendering, files of the scene, spawning: main thread.
	"apply_on_actor": [true, false],
	"clip_paths": [true, false],               # reads Path3D nodes
	"clip_points_by_polygon": [true, false],   # reads Path3D / scene polygons
	"compute_kernel": [true, false],           # RenderingDevice
	"create_spline": [true, false],            # adds Path3D nodes to the scene
	"create_surface_from_spline": [true, false],
	"debug": [true, false],                    # debug draw side effect
	"load_alembic_file": [true, false],        # instantiates imported scenes
	"mesh_sampler": [true, false],             # Mesh surface arrays (RenderingServer)
	"navigation_region_sampler": [true, false],
	"physics_overlap_query": [true, false],
	"physics_shape_sweep": [true, false],
	"point_from_mesh": [true, false],
	"point_from_player_pawn": [true, false],
	"points_from_gridmap": [true, false],
	"points_from_imported_scene": [true, false],
	"points_from_scene": [true, false],
	"points_from_tilemap": [true, false],
	"polygon_operation": [true, false],
	"projection": [true, false],
	"ray_cast": [true, false],
	"sample_mesh": [true, false],
	"sample_spline": [true, false],            # reads Path3D nodes
	"sample_terrain_layers": [true, false],    # texture images
	"scan_meshes": [true, false],
	"scan_nodes": [true, false],
	"scan_splines": [true, false],
	"spawn_meshes": [true, false],
	"spawn_nodes": [true, false],
	"spawn_scenes": [true, false],
	"split_splines": [true, false],
	"subdivide_segment": [true, false],
	"surface_sampler": [true, false],          # reads MeshInstance3D nodes
	"texture_sampler": [true, false],
	# Evaluation-context state, nested graphs, console output: main thread.
	"get_variable": [true, false],
	"set_variable": [true, false],
	"grid_size": [true, false],                # writes ctx.variables
	"input": [true, false],                    # reads owner args / debug inputs
	"loop": [true, false],
	"subgraph": [true, false],
	"get_loop_index": [true, false],          # LoopIteration source reads ctx.runtime_params
	"get_loop_key": [true, false],            # reads ctx.runtime_params
	"print_string": [true, false],
	# Thread-safe but not a pure function of settings and inputs.
	"load_data_table": [false, false],         # file content can change
	"load_pcg_data_asset": [false, false],     # file content can change (cache has a Mutex)
	"output": [false, false],                  # graph boundary; nothing to gain
	"reroute": [false, false],
	# Pure: threadable and cacheable.
	"add_attribute": [false, true],
	"add_tags": [false, true],
	"assets": [false, true],
	"attribute_filter_range": [false, true],
	"attribute_noise": [false, true],
	"attribute_random": [false, true],
	"attribute_rename": [false, true],
	"attribute_set_to_point": [false, true],
	"boolean": [false, true],
	"bounds_modifier": [false, true],
	"branch": [false, true],
	"build_rotation_from_up": [false, true],
	"combine_points": [false, true],
	"compose_vector": [false, true],
	"copy": [false, true],
	"copy_points": [false, true],
	"create_surface_from_polygon": [false, true],
	"curve_remap_density": [false, true],
	"data_table_row_to_attribute_set": [false, true],
	"decompose_vector": [false, true],
	"delete_tags": [false, true],
	"density_filter": [false, true],
	"density_remap": [false, true],
	"difference": [false, true],
	"distance": [false, true],
	"distance_to_density": [false, true],
	"dungeon_connect_rooms": [false, true],
	"dungeon_expand_rooms": [false, true],
	"dungeon_generator": [false, true],
	"dungeon_room_candidates": [false, true],
	"dungeon_walls_and_doors": [false, true],
	"duplicate_point": [false, true],
	"expression": [false, true],
	"filter": [false, true],
	"filter_data_by_attribute": [false, true],
	"filter_data_by_tag": [false, true],
	"filter_data_by_type": [false, true],
	"get_data_count": [false, true],
	"get_entries_count": [false, true],
	"get_points_count": [false, true],
	"grammar_expand": [false, true],
	"grid": [false, true],
	"grid_boundary": [false, true],
	"grid_connect_points": [false, true],
	"grid_fill_bounds": [false, true],
	"intersection": [false, true],
	"make_bounds": [false, true],
	"make_vector": [false, true],
	"match_and_set": [false, true],
	"math_op": [false, true],
	"merge": [false, true],
	"merge_points": [false, true],
	"mutate_seed": [false, true],
	"noise": [false, true],
	"normal_to_density": [false, true],
	"partition": [false, true],
	"point_filter_range": [false, true],
	"point_neighborhood": [false, true],
	"point_offsets": [false, true],
	"point_to_attribute_set": [false, true],
	"random_color": [false, true],
	"reduce": [false, true],
	"relax": [false, true],
	"remap": [false, true],
	"remove_attribute": [false, true],
	"replace_tags": [false, true],
	"rotator_op": [false, true],
	"sample_points": [false, true],            # blue-noise table init has a Mutex
	"sanity_check": [false, true],
	"select": [false, true],
	"select_multi": [false, true],
	"select_points": [false, true],
	"self_pruning": [false, true],
	"sequence_sample": [false, true],
	"size": [false, true],
	"snap_to_grid": [false, true],
	"sort": [false, true],
	"substract": [false, true],
	"switch": [false, true],
	"tags_mutate": [false, true],
	"transform": [false, true],
	"transform_points": [false, true],
	"union": [false, true],
	"volume_sampler": [false, true],

	# Round 2 additions. Main thread: scene tree, owner, runtime params or mesh resources.
	"create_points": [true, false],   # owner-relative placement
	"create_target_node": [true, false],   # creates scene nodes
	"get_property_from_object_path": [true, false],   # reads scene nodes and resources
	"get_spline_data": [true, false],   # reads Path3D nodes
	"get_surface_data": [true, false],   # reads MeshInstance3D nodes and shapes
	"get_volume_data": [true, false],   # reads collision and CSG nodes
	"spawn_spline_mesh": [true, false],   # spawns scene nodes
	"bounds_from_mesh": [true, false],   # Mesh AABB (RenderingServer)
	"runtime_quality_branch": [true, false],   # reads runtime_params
	"runtime_quality_select": [true, false],   # reads runtime_params
	# Thread-safe but not a pure function of settings and inputs (depends on bulk position).
	"filter_data_by_index": [false, false],
	# WP5 hierarchical generation: read the cell bounds from the context (not
	# part of the FlowOutputCache key), so not cacheable; read-only, threadable.
	"get_execution_bounds": [false, false],
	"cull_points_outside_bounds": [false, false],
	# Round 2 additions. Pure: threadable and cacheable.
	"apply_scale_to_bounds": [false, true],
	"attribute_cast": [false, true],
	"attribute_remove_duplicates": [false, true],
	"attribute_select": [false, true],
	"attribute_string_op": [false, true],
	"bitwise_op": [false, true],
	"break_transform_attribute": [false, true],
	"compare_op": [false, true],
	"copy_attribute": [false, true],
	"discard_points_on_irregular_surface": [false, true],
	"find_convex_hull_2d": [false, true],
	"gather": [false, true],
	"get_attribute_from_point_index": [false, true],
	"get_bounds": [false, true],
	"make_transform_attribute": [false, true],
	"merge_attributes": [false, true],
	"reset_point_center": [false, true],
	"split_points": [false, true],
	"to_point": [false, true],
	"transform_op": [false, true],
	"trig_op": [false, true],
	"vector_op": [false, true],
	"weighted_point_sampler": [false, true],
}

## Threadable stock templates that print errors or warnings outside setError
## on some inputs (a FlowData helper's push_error such as cloneStream,
## findStream or translateStreamName, or a push_warning), as recorded by the
## node conformance harness on its fixtures (docs/_round2/WP9.md). Godot calls
## every script Logger on the thread that raises the message, so threaded mode
## runs these elements one at a time on the calling thread instead of in a
## concurrent pool batch (FlowExecutor.split_batch). A third-party node can ask
## for the same with meta_node["logs"] = true.
const LOGGING_TEMPLATES := {
	"relax": true,                # cloneStream on input without position
	"snap_to_grid": true,         # cloneStream on input without position
	"point_filter_range": true,   # findStream on an attribute set
	"mutate_seed": true,          # warning on input without seed
	"boolean": true,              # translateStreamName (@last on Data without streams)
	"filter": true,               # translateStreamName (@last on Data without streams)
	"partition": true,            # translateStreamName (@last on Data without streams)
}

static var _cache : Dictionary = {}
static var _mutex := Mutex.new()
## template -> warning text, for templates whose meta_node contradicted their
## TABLE row (each is warned about once).
static var _override_warnings : Dictionary = {}

## Traits of `template` whose node script declares `meta` (its meta_node), as
## { "main_thread": bool, "cacheable": bool }. Dynamic input_<name> / output_<name>
## templates resolve like input / output.
static func resolve(template : String, meta : Dictionary = {}) -> Dictionary:
	var base := _base_template(template)
	var result := { "main_thread": true, "cacheable": false }
	var row = TABLE.get(base, null)
	if row != null:
		result.main_thread = bool(row[0])
		result.cacheable = bool(row[1])
	elif meta.get("scans_scene", false) or meta.get("queries_physics", false) or meta.get("is_final", false):
		result.main_thread = true
		result.cacheable = false
	if meta.has("pure"):
		var pure := bool(meta["pure"])
		result.cacheable = pure
		result.main_thread = not pure
	if meta.has("main_thread"):
		result.main_thread = bool(meta["main_thread"])
	if row != null and (result.main_thread != bool(row[0]) or result.cacheable != bool(row[1])):
		_warn_override(base, row, result, meta)
	return result

static func _warn_override(template : String, row : Array, result : Dictionary, meta : Dictionary) -> void:
	_mutex.lock()
	var first := not _override_warnings.has(template)
	var text := ""
	if first:
		var flags := []
		for key in ["main_thread", "pure"]:
			if meta.has(key):
				flags.append("%s=%s" % [key, meta[key]])
		text = "FlowNodeTraits: meta_node of '%s' (%s) overrides its traits table row [main_thread=%s, cacheable=%s]; effective [main_thread=%s, cacheable=%s]" % [
			template, ", ".join(PackedStringArray(flags)), row[0], row[1], result.main_thread, result.cacheable ]
		_override_warnings[template] = text
	_mutex.unlock()
	if first:
		push_warning(text)

## Templates whose meta_node contradicted their TABLE row so far, as
## template -> warning text.
static func override_warnings() -> Dictionary:
	_mutex.lock()
	var copy := _override_warnings.duplicate()
	_mutex.unlock()
	return copy

## Forgets which templates were warned about, so they warn again.
static func clear_override_warnings() -> void:
	_mutex.lock()
	_override_warnings.clear()
	_mutex.unlock()

## Traits of a node element (cached per template and script).
static func for_element(element : FlowNodeBase) -> Dictionary:
	var script = element.get_script()
	var key := [element.node_template, script.get_instance_id() if script != null else 0]
	_mutex.lock()
	var cached = _cache.get(key, null)
	_mutex.unlock()
	if cached != null:
		return cached
	var result := resolve(element.node_template, element.meta_node)
	_mutex.lock()
	_cache[key] = result
	_mutex.unlock()
	return result

static func main_thread(element : FlowNodeBase) -> bool:
	return for_element(element).main_thread

static func cacheable(element : FlowNodeBase) -> bool:
	return for_element(element).cacheable

## True when the element is known to print errors or warnings outside setError
## (LOGGING_TEMPLATES, or meta_node["logs"]). Threaded mode never runs two of
## them at once.
static func logs_outside_set_error(element : FlowNodeBase) -> bool:
	if element.meta_node.has("logs"):
		return bool(element.meta_node["logs"])
	return LOGGING_TEMPLATES.has(_base_template(element.node_template))

## Forgets cached per-template traits (after a node script reload).
static func clear_cache() -> void:
	_mutex.lock()
	_cache.clear()
	_mutex.unlock()

static func _base_template(template : String) -> String:
	if template.begins_with("input_"):
		return "input"
	if template.begins_with("output_"):
		return "output"
	return template
