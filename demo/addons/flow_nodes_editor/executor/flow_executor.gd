@tool
class_name FlowExecutor
extends RefCounted

## Runs one evaluation of a graph (Unreal's FPCGGraphExecutor). One
## implementation, three modes:
##
##   SYNCHRONOUS   every node in the sequential execution order, in one call.
##   TIME_SLICED   the same order spread over step(budget_ms) calls (node
##                 granularity), what FlowNodeIO.GraphEvaluation always did.
##   THREADED      independent ready elements that FlowNodeTraits marks as not
##                 main-thread run on WorkerThreadPool; main-thread elements run
##                 on the calling (main) thread in the sequential order relative
##                 to each other, never while pool tasks run, so variables,
##                 spawns and scene reads see exactly the sequential state.
##                 Results, including the order of FlowNodeIO.last_errors, are
##                 identical to SYNCHRONOUS.
##                 Logging hazard: errors that do not go through setError (a
##                 FlowData helper's push_error, push_warning, engine errors)
##                 reach every script Logger on the pool thread that raised
##                 them, possibly from several threads at once. A Logger that
##                 is not thread-safe can then corrupt memory. Elements known
##                 to log that way (FlowNodeTraits.logs_outside_set_error) are
##                 therefore run one at a time on the calling thread, never in a
##                 concurrent batch (split_batch); others can still log
##                 concurrently in unforeseen cases.
##
## The evaluation itself has three phases:
##   1. build_state(): fresh elements from the graph's FlowCompiledGraph,
##      overrides and $param bindings, the child EvaluationContext, the graph
##      input feed;
##   2. execution of the ordered elements (the mode decides how);
##   3. finalize_state(): output collection, variable and runtime-param
##      publishing, release of the elements.
## FlowNodeIO.evaluate_graph / begin_evaluation / evaluate_graph_snapshot and
## GraphEvaluation are thin wrappers over this class.
##
## Options on an EvaluationContext (set by FlowNodeIO.make_context from a
## FlowGraphNode3D's `threaded` / `output_cache`, inherited by nested
## subgraph and loop evaluations):
##   ctx.set_meta(FlowExecutor.THREADED_META, true)      threaded mode for
##                                                       synchronous runs
##   ctx.set_meta(FlowExecutor.OUTPUT_CACHE_META, true)  FlowOutputCache on
##
## Extension points (wave B):
##   node_filter : Callable(element) -> bool   false skips the element (it
##                                             produces nothing)
##   preseeded   : Dictionary                  node name -> generated bulks
##                                             (Array of Array of Data); the
##                                             element is not run and its
##                                             outputs are these bulks.
##   capture_nodes : Array                     node names whose generated bulks
##                                             finalize() keeps in `captured`
##                                             (name -> bulks) before the
##                                             elements are released; used by
##                                             hierarchical generation (WP5).

enum Mode { SYNCHRONOUS, TIME_SLICED, THREADED }

const THREADED_META := &"flow_threaded"
const OUTPUT_CACHE_META := &"flow_output_cache"
## Deepest nested evaluation begin() accepts (subgraphs and loops add one level).
const MAX_EVAL_DEPTH := 20

## Execution mode for run(). evaluate() picks THREADED when the parent context
## asks for it.
var mode : int = Mode.SYNCHRONOUS
## Optional element filter: returns false for elements that must not run.
var node_filter : Callable = Callable()
## Node name -> prepared generated bulks; those elements are not run.
var preseeded : Dictionary = {}
## Node names whose generated bulks finalize() copies into `captured`.
var capture_nodes : Array = []
## Node name -> generated bulks (Array of Array of Data) of `capture_nodes`,
## filled by finalize(). The bulk arrays are copies; the Data are shared.
var captured : Dictionary = {}

## The evaluation state (see build_state); empty before begin().
var state : Dictionary = {}
## Graph outputs, set once the evaluation finalized.
var outputs : Dictionary = {}

var _index : int = 0
var _node_count : int = 0
var _finalized : bool = false

## Elements run on WorkerThreadPool threads since startup (threaded mode
## statistics for tests and benchmarks).
static var pooled_element_count : int = 0
## Ready pure elements that threaded mode ran one at a time on the calling
## thread because they are known to log outside setError (see split_batch).
static var serialized_element_count : int = 0
static var _stats_mutex := Mutex.new()

# --- Instance API --------------------------------------------------------------------

## Builds the evaluation (phase 1). Returns false on the recursion-guard trip
## (depth > 20), like evaluate_graph's {} early return.
func begin(graph : FlowGraphResource, input_data_map : Dictionary, parent_ctx : FlowData.EvaluationContext, runtime_params : Dictionary = {}, depth : int = 0) -> bool:
	if depth > MAX_EVAL_DEPTH:
		push_error("PCG graph evaluation exceeded maximum recursion depth (%d). Check for circular subgraph references." % MAX_EVAL_DEPTH)
		return false
	state = build_state(graph, input_data_map, parent_ctx, runtime_params, depth)
	if state.is_empty():
		return false
	_index = 0
	_node_count = state["ordered_nodes"].size()
	_finalized = false
	return true

## Total elements in the ordered execution list.
func node_count() -> int:
	return _node_count

## Elements executed so far (time-sliced mode).
func progress() -> int:
	return _index

## True once every element ran and the outputs were collected.
func is_done() -> bool:
	return _finalized

## Runs elements in order until `budget_ms` of wall-clock time is spent, then
## returns so the host can yield the frame. Always runs at least one element.
## Finalizes after the last one. Returns true when the evaluation is finished.
func step(budget_ms : float = 4.0) -> bool:
	if _finalized:
		return true
	var start_us := Time.get_ticks_usec()
	var budget_us := int(maxf(budget_ms, 0.0) * 1000.0)
	var ordered : Array = state["ordered_nodes"]
	while _index < _node_count:
		_run_element(ordered[_index])
		_index += 1
		# Node-level granularity: the budget is only checked between elements.
		if Time.get_ticks_usec() - start_us >= budget_us:
			break
	if _index >= _node_count:
		finalize()
		return true
	return false

## Runs every remaining element in `mode` and finalizes. Returns the outputs.
func run() -> Dictionary:
	if _finalized:
		return outputs
	if mode == Mode.THREADED and _index == 0:
		_run_threaded()
		_index = _node_count
	else:
		var ordered : Array = state["ordered_nodes"]
		while _index < _node_count:
			_run_element(ordered[_index])
			_index += 1
	return finalize()

## Phase 3, exactly once. Returns the outputs.
func finalize() -> Dictionary:
	if not _finalized:
		if not capture_nodes.is_empty():
			_capture(state.get("instances", {}))
		outputs = finalize_state(state)
		_finalized = true
	return outputs

func _capture(instances : Dictionary) -> void:
	for node_name in capture_nodes:
		var node = instances.get(node_name)
		if node == null or node.generated_bulks.is_empty():
			continue
		var bulks : Array = []
		for bulk in node.generated_bulks:
			bulks.append(bulk.duplicate() if bulk is Array else [bulk])
		captured[node_name] = bulks

## Synchronous evaluation in the mode the parent context asks for (threaded
## when it carries THREADED_META). Returns the graph outputs, {} on the
## recursion-guard trip.
static func evaluate(graph : FlowGraphResource, input_data_map : Dictionary, parent_ctx : FlowData.EvaluationContext, runtime_params : Dictionary = {}, depth : int = 0) -> Dictionary:
	var executor := FlowExecutor.new()
	if parent_ctx != null and parent_ctx.get_meta(THREADED_META, false):
		executor.mode = Mode.THREADED
	if not executor.begin(graph, input_data_map, parent_ctx, runtime_params, depth):
		return {}
	return executor.run()

# One element with the extension points applied.
func _run_element(node : FlowNodeBase, error_log_override = null) -> void:
	if not preseeded.is_empty() and preseeded.has(node.name):
		_apply_preseeded(node, preseeded[node.name])
		return
	if node_filter.is_valid() and not node_filter.call(node):
		return
	execute_node(node, state["instances"], state["graph"], state["ctx"], error_log_override)

static func _apply_preseeded(node : FlowNodeBase, bulks) -> void:
	node.generated_bulks = []
	if bulks is Array:
		for bulk in bulks:
			node.generated_bulks.append(bulk.duplicate() if bulk is Array else [bulk])
	node.num_generated_bulks = node.generated_bulks.size()

# --- Threaded mode -------------------------------------------------------------------

func _run_threaded() -> void:
	var ordered : Array = state["ordered_nodes"]
	var ctx : FlowData.EvaluationContext = state["ctx"]
	var n := ordered.size()
	var position_by_name := {}
	for i in range(n):
		position_by_name[ordered[i].name] = i
	# Dependencies among the executed elements (virtual variable ones included).
	var dep_positions : Array = []
	var main_thread := PackedByteArray()
	main_thread.resize(n)
	var main_order := PackedInt32Array()
	for i in range(n):
		var node : FlowNodeBase = ordered[i]
		var positions := PackedInt32Array()
		for conn in node.deps:
			var j : int = position_by_name.get(conn.from_node, -1)
			if j >= 0 and j != i:
				positions.append(j)
		dep_positions.append(positions)
		var on_main := FlowNodeTraits.main_thread(node) or preseeded.has(node.name)
		main_thread[i] = 1 if on_main else 0
		if on_main:
			main_order.append(i)
	var done := PackedByteArray()
	done.resize(n)
	var started := PackedByteArray()
	started.resize(n)
	# Errors are buffered per element and flushed in the sequential order at
	# the end, so last_errors matches a sequential run exactly.
	var buffers : Array = []
	for i in range(n):
		buffers.append([])
	var has_log := ctx.has_meta(FlowNodeBase.ERROR_LOG_META)
	var real_log = ctx.get_meta(FlowNodeBase.ERROR_LOG_META) if has_log else null

	var remaining := n
	var main_ptr := 0
	while remaining > 0:
		var progressed := false
		# 1. Main-thread elements, in sequential order, while the pool is idle.
		while main_ptr < main_order.size() and _deps_done(main_order[main_ptr], dep_positions, done):
			var i : int = main_order[main_ptr]
			started[i] = 1
			if has_log:
				ctx.set_meta(FlowNodeBase.ERROR_LOG_META, buffers[i])
			_run_element(ordered[i], buffers[i])
			if has_log:
				ctx.set_meta(FlowNodeBase.ERROR_LOG_META, real_log)
			done[i] = 1
			remaining -= 1
			main_ptr += 1
			progressed = true
		# 2. Every ready pure element, concurrently.
		var batch := PackedInt32Array()
		for i in range(n):
			if main_thread[i] == 0 and started[i] == 0 and _deps_done(i, dep_positions, done):
				batch.append(i)
		# Elements known to log outside setError run one at a time here, on
		# the calling thread, before the concurrent batch (see split_batch).
		var split := split_batch(ordered, batch)
		var pooled : PackedInt32Array = split.pooled
		if pooled.size() > 1:
			for i in split.serial:
				started[i] = 1
				_run_element(ordered[i], buffers[i])
			_stats_mutex.lock()
			serialized_element_count += split.serial.size()
			_stats_mutex.unlock()
		else:
			# No concurrency anyway: run the whole batch in order.
			pooled = PackedInt32Array()
			for i in batch:
				started[i] = 1
				_run_element(ordered[i], buffers[i])
		if pooled.size() > 1:
			for i in pooled:
				started[i] = 1
				_prewarm_shared_resources(ordered[i])
				ordered[i]._defer_error_push = true
			var task_id := WorkerThreadPool.add_group_task(_pool_task.bind(pooled, buffers), pooled.size(), -1, true, "FlowExecutor")
			WorkerThreadPool.wait_for_group_task_completion(task_id)
			# Print the pool elements' errors on the main thread, in order.
			for i in pooled:
				var element : FlowNodeBase = ordered[i]
				element._defer_error_push = false
				for message in element._deferred_error_pushes:
					push_error(message)
				element._deferred_error_pushes.clear()
		for i in batch:
			done[i] = 1
			remaining -= 1
			progressed = true
		if not progressed:
			# A dependency that can never complete (a cycle the sequential order
			# tolerated): finish the rest sequentially.
			for i in range(n):
				if done[i] == 0:
					if has_log:
						ctx.set_meta(FlowNodeBase.ERROR_LOG_META, buffers[i])
					_run_element(ordered[i], buffers[i])
					if has_log:
						ctx.set_meta(FlowNodeBase.ERROR_LOG_META, real_log)
					done[i] = 1
					remaining -= 1
			break
	if real_log is Array:
		for buffer in buffers:
			real_log.append_array(buffer)

func _pool_task(k : int, batch : PackedInt32Array, buffers : Array) -> void:
	var i : int = batch[k]
	_run_element(state["ordered_nodes"][i], buffers[i])
	_stats_mutex.lock()
	pooled_element_count += 1
	_stats_mutex.unlock()

## Splits a batch of ready threadable elements (positions in `ordered`) into
## the ones that may run concurrently on the pool and the ones known to print
## errors outside setError (FlowNodeTraits.logs_outside_set_error), which run
## one at a time on the calling thread. Both keep the batch order.
## Returns { "serial": PackedInt32Array, "pooled": PackedInt32Array }.
static func split_batch(ordered : Array, batch : PackedInt32Array) -> Dictionary:
	var serial := PackedInt32Array()
	var pooled := PackedInt32Array()
	for i in batch:
		if FlowNodeTraits.logs_outside_set_error(ordered[i]):
			serial.append(i)
		else:
			pooled.append(i)
	return { "serial": serial, "pooled": pooled }

static func _deps_done(i : int, dep_positions : Array, done : PackedByteArray) -> bool:
	for j in dep_positions[i]:
		if done[j] == 0:
			return false
	return true

## Resources shared between elements build lazy caches on first use (a Curve's
## baked samples, a Gradient's sorted points). Building them concurrently is a
## data race, so threaded mode builds them on the main thread first.
static func _prewarm_shared_resources(node : FlowNodeBase) -> void:
	var settings := node.settings
	if settings == null:
		return
	for prop_name in _resource_props_of(settings):
		var value = settings.get(prop_name)
		if value is Array:
			for item in value:
				_prewarm_resource(item)
		else:
			_prewarm_resource(value)

static var _resource_props : Dictionary = {}   # settings script id -> PackedStringArray

# Stored Object and Array properties of a settings class (cached per script).
static func _resource_props_of(settings : Resource) -> PackedStringArray:
	var script = settings.get_script()
	var key : int = script.get_instance_id() if script != null else 0
	var props = _resource_props.get(key, null)
	if props == null:
		props = PackedStringArray()
		for prop in settings.get_property_list():
			if (prop.usage & PROPERTY_USAGE_STORAGE) == 0:
				continue
			if prop.type == TYPE_OBJECT or prop.type == TYPE_ARRAY:
				props.append(prop.name)
		_resource_props[key] = props
	return props

static func _prewarm_resource(value) -> void:
	if value is Curve:
		value.bake()
	elif value is Curve2D or value is Curve3D:
		value.get_baked_length()
	elif value is Gradient:
		value.sample(0.0)

# --- Phase 1: build ----------------------------------------------------------------------

## Instances fresh elements from the graph's FlowCompiledGraph, applies
## overrides and bindings, builds the child context and feeds the graph inputs.
## Returns the state Dictionary ("graph", "parent_ctx", "instances",
## "node_list", "ordered_nodes", "ctx", "local_params", "owns_override_hits",
## "compiled").
static func build_state(graph : FlowGraphResource, input_data_map : Dictionary, parent_ctx : FlowData.EvaluationContext, runtime_params : Dictionary, depth : int) -> Dictionary:
	var compiled := FlowCompiledGraph.for_graph(graph)
	for message in compiled.errors:
		push_error(message)
	var instances := {}
	var node_list := []
	var node_descs := []
	# Overrides / $param bindings (RUNTIME_API_P0 §4). The scope context is built
	# lazily, only when a node actually has something to apply.
	var owns_override_hits := not parent_ctx.has_meta(FlowNodeIO.OVERRIDE_HITS_META)
	var override_hits : Dictionary = parent_ctx.get_meta(FlowNodeIO.OVERRIDE_HITS_META, {})
	var binding_scope : FlowData.EvaluationContext = null
	# True when this run's settings differ from the saved ones in a way the
	# execution order depends on; the run then orders itself.
	var order_changed := false
	var use_cache : bool = parent_ctx.get_meta(OUTPUT_CACHE_META, false)
	for desc in compiled.nodes:
		var raw_instance = desc.node_script.new()
		var instance := raw_instance as FlowNodeBase
		if instance == null:
			push_error("Node script is not a FlowNodeBase: %s" % desc.script_path)
			if raw_instance is Object and not (raw_instance is RefCounted):
				raw_instance.free()
			continue
		instance.name = desc.name
		instance.node_template = desc.template
		if desc.settings_prototype == null:
			desc.prepare(instance)
		instance.settings = desc.new_settings()
		var settings_bound := false
		if FlowNodeIO.has_setting_bindings(instance.settings, parent_ctx):
			if use_cache and desc.cacheable and desc.settings_key == null:
				desc.settings_key = FlowOutputCache.settings_values(instance.settings)
			if binding_scope == null:
				binding_scope = FlowNodeIO._binding_scope_context(graph, parent_ctx, runtime_params, override_hits)
			if FlowNodeIO.apply_setting_bindings(instance, graph, binding_scope, input_data_map):
				settings_bound = true
				if FlowCompiledGraph.order_signature_of(instance.settings) != desc.order_signature:
					order_changed = true
		if use_cache and desc.cacheable and not settings_bound:
			if desc.settings_key == null:
				desc.settings_key = FlowOutputCache.settings_values(instance.settings)
			instance.set_meta(FlowOutputCache.SETTINGS_KEY_META, desc.settings_key)
		instance.refreshFromSettings()
		_restore_wired_param_ports(instance, desc.saved_args_port)
		instances[desc.name] = instance
		node_list.append(instance)
		node_descs.append(desc)

	var ordered_nodes : Array = []
	if compiled.ordered and not order_changed:
		for i in range(node_list.size()):
			node_list[i].deps = node_descs[i].deps.duplicate()
			node_list[i].dependants = node_descs[i].dependants.duplicate()
		var element_by_index := {}
		for i in range(node_list.size()):
			element_by_index[node_descs[i].index] = node_list[i]
		for index in compiled.execution_order:
			ordered_nodes.append(element_by_index[index])
	else:
		# Connections (deps and dependants), virtual variable dependencies and
		# the shared execution order, on this run's elements.
		for conn in compiled.links:
			var src_node = instances.get(conn.from_node)
			var dst_node = instances.get(conn.to_node)
			if src_node and dst_node:
				src_node.dependants.append(conn)
				dst_node.deps.append(conn)
		FlowNodeIO._add_virtual_variable_dependencies(node_list)
		ordered_nodes = FlowNodeIO.build_execution_order(node_list, instances)
		if not order_changed:
			compiled.store_order(node_descs, node_list, ordered_nodes)


	# Construct EvaluationContext for subgraph
	var ctx := FlowData.EvaluationContext.new()
	ctx.graph = graph
	# parent_ctx.owner may be null (owner-less evaluation); owner-dependent
	# nodes report it themselves.
	ctx.owner = parent_ctx.owner
	# Copied verbatim: only make_context()/the editor assign the counter, so
	# legacy callers that hand-build a context (some store a seed in eval_id)
	# stay byte-identical.
	ctx.eval_id = parent_ctx.eval_id
	# Seed, component identity and per-instance overrides flow into nested
	# subgraph/loop evaluations unchanged (loop derives per-iteration seeds by
	# setting parent_ctx.seed around its call).
	ctx.seed = parent_ctx.seed
	ctx.component_id = parent_ctx.component_id
	ctx.overrides = parent_ctx.overrides
	ctx.preview = parent_ctx.preview
	# Hierarchical generation (WP5): cell bounds and level reach nested graphs.
	ctx.bounds = parent_ctx.bounds
	ctx.has_bounds = parent_ctx.has_bounds
	ctx.grid_size = parent_ctx.grid_size
	ctx.cell_coord = parent_ctx.cell_coord
	ctx.hierarchy_level = parent_ctx.hierarchy_level
	ctx.gedit_nodes_by_name = instances
	ctx.runtime_params = parent_ctx.runtime_params.duplicate(true) if parent_ctx.runtime_params else {}
	for key in runtime_params.keys():
		ctx.runtime_params[key] = runtime_params[key]
	ctx.runtime_params["seed"] = ctx.seed
	ctx.runtime_params["__eval_depth"] = depth
	ctx.set_meta("flow_eval_depth", depth)
	ctx.set_meta(FlowNodeIO.OVERRIDE_HITS_META, override_hits)
	# Executor options reach nested subgraph/loop evaluations.
	for option in [THREADED_META, OUTPUT_CACHE_META]:
		if parent_ctx.has_meta(option):
			ctx.set_meta(option, parent_ctx.get_meta(option))
	# One spawn session per top-level evaluation, shared by nested ones
	# (FlowNodeBase.SPAWN_SESSION_META).
	var spawn_session = parent_ctx.get_meta(FlowNodeBase.SPAWN_SESSION_META) if parent_ctx.has_meta(FlowNodeBase.SPAWN_SESSION_META) else {}
	ctx.set_meta(FlowNodeBase.SPAWN_SESSION_META, spawn_session)
	if use_cache:
		ctx.set_meta(FlowOutputCache.FINGERPRINT_MEMO_META, {})
	# Nested evaluations share the root's error log. A custom node that builds its
	# own context still reports into the synchronous evaluation around it.
	var error_log = parent_ctx.get_meta(FlowNodeBase.ERROR_LOG_META) if parent_ctx.has_meta(FlowNodeBase.ERROR_LOG_META) else FlowNodeIO._sync_error_log
	if error_log is Array:
		ctx.set_meta(FlowNodeBase.ERROR_LOG_META, error_log)
	FlowNodeIO._inherit_flow_variables(ctx, parent_ctx)
	FlowVariableEval._mirror_variables_to_runtime(ctx)

	_feed_graph_inputs(graph, ordered_nodes, input_data_map)

	return {
		"graph": graph,
		"parent_ctx": parent_ctx,
		"instances": instances,
		"node_list": node_list,
		"ordered_nodes": ordered_nodes,
		"ctx": ctx,
		# Local overrides passed into THIS subgraph invocation. Carried so
		# finalize can tell _publish_runtime_params which keys are local (must
		# not leak to the parent) vs. genuinely produced downstream.
		"local_params": runtime_params,
		# The outermost evaluation owns the override hit set and reports unmatched
		# override keys once, after every nested subgraph/loop evaluation has run.
		"owns_override_hits": owns_override_hits,
		"compiled": compiled,
	}

# Runtime counterpart of the editor's args_port bookkeeping: remember which
# parameter ports are actually wired so getSettingValue can read them. Only
# connected ports past the flow inputs are restored (stale unconnected entries
# are ignored, matching what the editor rebuilds in initFromScript).
static func _restore_wired_param_ports(instance : FlowNodeBase, saved_ports : Dictionary) -> void:
	if saved_ports.is_empty():
		return
	var num_flow_ins : int = instance.getMeta().get("ins", []).size()
	for arg_name in saved_ports:
		var entry = saved_ports[arg_name]
		if not (entry is Dictionary) or not entry.get("connected", false):
			continue
		var port := int(entry.get("port", -1))
		if port < num_flow_ins:
			continue
		instance.args_ports_by_name[arg_name] = { "port": port, "connected": true }

# Declared type of the graph input parameter `param_name` (Invalid when the
# graph does not declare it). Lets a raw int feed an Int64 parameter as Int64.
static func _in_param_type(graph : FlowGraphResource, param_name : String) -> int:
	for param in graph.in_params:
		if param and param.name == param_name:
			return param.data_type
	return FlowData.DataType.Invalid

# Feeds the graph inputs from input_data_map into the input nodes' outputs.
static func _feed_graph_inputs(graph : FlowGraphResource, ordered_nodes : Array, input_data_map : Dictionary) -> void:
	for node in ordered_nodes:
		var is_specific_input = false
		var specific_input_name = ""
		if node.node_template == "input":
			if node.settings and node.settings.name != "" and node.settings.name != "in_val":
				for param in graph.in_params:
					if param and param.name == node.settings.name:
						is_specific_input = true
						specific_input_name = param.name
						break
		elif node.node_template.begins_with("input_"):
			is_specific_input = true
			specific_input_name = node.settings.name
		else:
			continue

		if is_specific_input:
			var val = FlowNodeIO._coerce_input_data(input_data_map.get(specific_input_name, null), specific_input_name, _in_param_type(graph, specific_input_name))
			if val:
				# Create a new Data object to rename/register the stream under the input's name
				var target_data := FlowData.Data.new()
				for stream_name in val.streams:
					var stream = val.streams[stream_name]
					target_data.registerStream(stream_name, stream.container, stream.data_type)

				# Ensure that the main stream is registered under input_name
				if val.streams.size() > 0 and not target_data.hasStream(specific_input_name):
					var main_stream_name = val.last_added_stream_name
					if main_stream_name == "" or not val.hasStream(main_stream_name):
						main_stream_name = val.streams.keys()[val.streams.size() - 1]
					var main_stream = val.streams[main_stream_name]
					# A canonical attribute name (density, seed, ...) only aliases a
					# main stream of that attribute's type.
					if FlowData.canonical_type_error(specific_input_name, main_stream.data_type) == "":
						target_data.registerStream(specific_input_name, main_stream.container, main_stream.data_type)
				# Carry per-data domain attributes, tags, kind and shape across the subgraph boundary.
				target_data.copy_meta_from(val)
				node.set_output(0, target_data)
		elif node.node_template == "input":
			# Generic multi-port inputs node
			for i in range(graph.in_params.size()):
				var param = graph.in_params[i]
				if param:
					var val = FlowNodeIO._coerce_input_data(input_data_map.get(param.name, null), param.name, param.data_type)
					var target_data := FlowData.Data.new()
					if val:
						for stream_name in val.streams:
							var stream = val.streams[stream_name]
							target_data.registerStream(stream_name, stream.container, stream.data_type)
						if val.streams.size() > 0 and not target_data.hasStream(param.name):
							var main_stream_name = val.last_added_stream_name
							if main_stream_name == "" or not val.hasStream(main_stream_name):
								main_stream_name = val.streams.keys()[val.streams.size() - 1]
							var main_stream = val.streams[main_stream_name]
							if FlowData.canonical_type_error(param.name, main_stream.data_type) == "":
								target_data.registerStream(param.name, main_stream.container, main_stream.data_type)
						target_data.copy_meta_from(val)
					else:
						var new_value = param.get_default_value()
						var container = target_data.addStream(param.name, param.data_type)
						if container != null:
							container.resize(1)
							FlowData.Data.writeValue(container, 0, new_value, param.data_type)
					node.set_output(i, target_data)

# --- Phase 2: one element ---------------------------------------------------------------

## Runs one element of an evaluation built by build_state: wires its inputs
## from its sources' last bulk, then execute_element(). With the context's
## OUTPUT_CACHE_META set, cacheable elements go through FlowOutputCache.
## `error_log_override` (threaded mode) receives the element's errors instead
## of the context's log.
static func execute_node(node : FlowNodeBase, instances : Dictionary, graph : FlowGraphResource, ctx : FlowData.EvaluationContext, error_log_override = null) -> void:
	if (node.node_template.begins_with("input_") or node.node_template == "input") and node.generated_bulks.size() > 0:
		return

	node.inputs.clear()
	var num_ins = node.getMeta().get("ins", []).size()
	if node.node_template == "output":
		if "out_params" in graph and graph.out_params.size() > 0:
			num_ins = graph.out_params.size()
		else:
			num_ins = max(num_ins, 1)
	node.inputs.resize(num_ins)
	for conn in node.deps:
		if conn.get("virtual_variable", false):
			continue
		var src = instances.get(conn.from_node)
		if src and src.generated_bulks.size() > 0:
			var src_bulk = src.generated_bulks[src.generated_bulks.size() - 1]
			if conn.from_port < src_bulk.size():
				# Links into exposed setting ports (to_port >= meta ins) are legal;
				# grow the input array instead of failing the whole evaluation.
				if conn.to_port >= node.inputs.size():
					node.inputs.resize(conn.to_port + 1)
				node.inputs[conn.to_port] = src_bulk[conn.from_port]

	execute_element(node, ctx, instances, error_log_override)

## preExecute, then the disabled pass-through, the variable fast path or run(),
## then the (editor-only) debug draw refresh. Shared by the runtime evaluator
## and the editor dock. Uses FlowOutputCache when the context asks for it and
## the element is cacheable.
static func execute_element(node : FlowNodeBase, ctx : FlowData.EvaluationContext, instances : Dictionary, error_log_override = null) -> void:
	node.preExecute(ctx)
	if error_log_override != null:
		node._error_log = error_log_override
	if node.settings != null and node.settings.disabled:
		node.executedDisabled(ctx)
	elif not FlowVariableEval.try_fast_execute(node, ctx, instances):
		if ctx.has_meta(OUTPUT_CACHE_META) and ctx.get_meta(OUTPUT_CACHE_META) and FlowNodeTraits.cacheable(node):
			FlowOutputCache.run_cached(node, ctx, instances)
		else:
			node.run(ctx)
	if FlowVariableEval.should_refresh_debug_draw(node):
		node.setupDrawDebug()

# --- Phase 3: finalize --------------------------------------------------------------------

## Collects the graph outputs, publishes variables and runtime params to the
## parent context, reports unmatched overrides (outermost evaluation) and
## releases the elements. Returns the outputs.
static func finalize_state(state : Dictionary) -> Dictionary:
	var graph : FlowGraphResource = state["graph"]
	var node_list : Array = state["node_list"]
	var ctx : FlowData.EvaluationContext = state["ctx"]
	var parent_ctx : FlowData.EvaluationContext = state["parent_ctx"]
	var local_params : Dictionary = state.get("local_params", {})

	# Collect output data
	var outputs := {}
	for node in node_list:
		var is_specific_output = false
		var specific_output_name = ""
		if node.node_template == "output":
			if node.settings and node.settings.name != "" and node.settings.name != "out_val":
				if "out_params" in graph:
					for param in graph.out_params:
						if param and param.name == node.settings.name:
							is_specific_output = true
							specific_output_name = param.name
							break
		elif node.node_template.begins_with("output_"):
			is_specific_output = true
			specific_output_name = node.settings.name
		else:
			continue

		if is_specific_output:
			if node.generated_bulks.size() > 0:
				var bulk = node.generated_bulks[node.generated_bulks.size() - 1]
				if bulk.size() > 0:
					outputs[specific_output_name] = bulk[0]
			elif node.inputs.size() > 0 and node.inputs[0] != null:
				outputs[specific_output_name] = node.inputs[0]
		elif node.node_template == "output":
			# Generic multi-port outputs node
			if "out_params" in graph and graph.out_params.size() > 0:
				for i in range(graph.out_params.size()):
					var param = graph.out_params[i]
					if not param:
						continue
					if node.inputs.size() > i and node.inputs[i] != null:
						outputs[param.name] = node.inputs[i]
			else:
				var out_name = node.settings.name
				if node.generated_bulks.size() > 0:
					var bulk = node.generated_bulks[node.generated_bulks.size() - 1]
					if bulk.size() > 0:
						outputs[out_name] = bulk[0]
				elif node.inputs.size() > 0 and node.inputs[0] != null:
					outputs[out_name] = node.inputs[0]
	FlowNodeIO._publish_flow_variables(ctx, parent_ctx)
	FlowNodeIO._publish_runtime_params(ctx, parent_ctx, local_params)
	if state.get("owns_override_hits", false):
		FlowNodeIO._warn_unmatched_overrides(ctx.overrides, ctx.get_meta(FlowNodeIO.OVERRIDE_HITS_META, {}))

	# Outputs are collected (FlowData.Data is RefCounted, so the references in
	# `outputs` keep the data alive). Drop every reference this evaluation holds
	# to its elements so they are released with the caller's state.
	ctx.gedit_nodes_by_name = {}
	state["instances"].clear()
	state["node_list"].clear()
	state["ordered_nodes"].clear()
	return outputs
