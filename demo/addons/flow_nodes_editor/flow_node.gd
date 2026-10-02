@tool
extends Node3D
class_name FlowGraphNode3D

# This is the Node3d the user will instantiate in his final 3D scenes to trigger
# the generation of pcg
# It technically should not need to be a Node3D, as the transform is not really used
# but I'm currently generating the spawned nodes as child of this nodes
#
# Runtime API (docs/RUNTIME_API_P0.md §1), UE UPCGComponent analogue:
#   generate(inputs, extra_params) -> Dictionary   synchronous, returns outputs
#   generate_async(inputs, extra_params)           time-sliced across frames
#   cleanup()                                      frees this component's spawned nodes
#   regenerate(inputs, extra_params)               cleanup() + generate()
#   signal generated(outputs), signal cleaned_up, var last_outputs
#
# Hierarchical generation (WP5, additive): FlowWorld3D creates one
# FlowGraphNode3D per generated cell and runs it with
#   generate_cell(cell, preseeded) -> Dictionary   one FlowWorldCell, synchronous
#   begin_cell(cell, preseeded, time_sliced) -> FlowCellRun
# Spawners use the cell component as ctx.owner, so cleanup(), flow_owner
# ownership and transient_output work per cell exactly as for generate().

const FlowNodeIOClass = preload("res://addons/flow_nodes_editor/flow_nodes_io.gd")

@export var graph : FlowGraphResource :
	set(new_value):
		_graph = new_value
		graph_node_changed.emit( self, "graph_resource" )

	get:
		return _graph

var _graph : FlowGraphResource = FlowGraphResource.new()
signal graph_node_changed( graph_node : FlowGraphNode3D, prop_name : String )

## Emitted after every synchronous or asynchronous generation with the graph
## outputs (output name -> FlowData.Data).
signal generated( outputs : Dictionary )
## Emitted by cleanup() once this component's spawned nodes are freed.
signal cleaned_up

## Custom inputs values for this instantiation
@export var args : Dictionary = {}

## Graph seed. 0 keeps the legacy behaviour (every node uses its own
## random_seed). Any other value decorrelates every random node of the graph,
## including nested subgraphs and loops, so two components running the same
## graph with different seeds produce different results.
@export var seed : int = 0

## Baseline runtime parameters (EvaluationContext.runtime_params) for every
## generation; generate(..., extra_params) entries win over these.
@export var params : Dictionary = {}

## Per-instance node setting overrides: "<node_name>/<property>" -> value, optionally
## prefixed with a graph basename ("my_subgraph:<node_name>/<property>") to target a
## node inside that subgraph only. "<node_name>/<dict_property>/<key>" targets one entry
## of a Dictionary setting (e.g. "expr/args/theme"). Beats $param bindings; a wired
## port still wins.
@export var overrides : Dictionary = {}

## Generate automatically when the node enters the running game (never in the
## editor). Disable to drive generation from code with generate().
@export var generate_on_ready : bool = true

## Spawned nodes get no owner, so they are never saved into the scene file.
@export var transient_output : bool = false

# --- Async / time-sliced generation (PARITY_ROADMAP async stage 2, opt-in) ---
## When false, execute() runs a single synchronous evaluate_graph()
## exactly as before — byte-for-byte the historical behavior. When true, the
## evaluation is built once and its node-execution phase is spread across frames
## from _process(), spending at most `frame_budget_ms` per frame. Topo sort,
## cycle detection, variable/runtime-param publishing and node-instance freeing
## are identical on both paths (the async path drives the very same evaluator
## helpers). This is the prerequisite hook for HiGen proximity scheduling.
@export var async_generation : bool = false
## Per-frame wall-clock budget for the async path, in milliseconds. Ignored when
## async_generation is false.
@export var frame_budget_ms : float = 4.0

## Run independent pure nodes on WorkerThreadPool threads during synchronous
## generate() (FlowExecutor THREADED mode). Nodes that touch the scene, physics,
## rendering, spawn, or use graph variables stay on the main thread, in order.
## Output is identical to the sequential run. Off by default. With
## async_generation the top-level graph stays time-sliced (node by node); nested
## subgraph and loop evaluations still honour this flag.
## Warning: errors a node prints outside its own error report (helper or engine
## errors) are raised on worker threads, and Godot calls script Loggers
## (OS.add_logger) on the raising thread. A Logger that is not thread-safe can
## crash the process; keep this off when you register one. Nodes known to log
## that way run one at a time.
@export var threaded : bool = false
## Reuse the outputs of pure nodes whose settings, seed and input content did
## not change since an earlier run (FlowOutputCache, shared process-wide,
## bounded, LRU). Output is identical to running them. Off by default. Call
## FlowOutputCache.clear() after editing a resource a node setting references
## in place (a Curve, a Mesh).
@export var output_cache : bool = false

## Outputs of the most recent generation (output name -> FlowData.Data).
var last_outputs : Dictionary = {}

## Node errors raised during the most recent generation, nested subgraph and
## loop evaluations included: [{ "node", "template", "message" }, ...]. Set
## before `generated` is emitted, so a handler can read it. Empty on success.
var last_errors : Array = []
# Error log of the async evaluation in flight.
var _async_errors : Array = []

# Active resumable evaluation while async generation is in flight (null otherwise).
var _async_eval = null
# True while a synchronous generate() is running.
var _generating_sync : bool = false

## The FlowWorldCell of the most recent generate_cell()/begin_cell() (null for
## a component that never generated a cell).
var last_cell : FlowWorldCell = null
# Cell run in flight (begin_cell), null otherwise.
var _cell_run : FlowCellRun = null

## Nodes visited by the last cleanup() (tests and benchmarks).
var last_cleanup_visits : int = 0
# Instance ids of content spawned for this component since the last cleanup()
# (see note_spawned_content).
var _spawned_content : Dictionary = {}
var _spawned_content_compact_at : int = 1024
# True when content was stamped without a record (see note_untracked_content).
var _untracked_content : bool = false

# You can also use get_property_list() for more control
func _get_property_list():
	return [
		{
			"name": "refresh_inputs",
			"type": TYPE_CALLABLE,
			"hint": PROPERTY_HINT_TOOL_BUTTON | PROPERTY_USAGE_EDITOR,
			"hint_string": "Refresh Inputs"
		}
	]

func _get(property: StringName):
	match property:
		"refresh_inputs":
			return refreshInputs
	return null

func refreshInputs():
	print( "RefreshInputs %s" % graph )
	if args == null:
		args = {}
	var changed := false
	if graph:
		print( "Checking in_params:", graph.in_params )
		for in_param in graph.in_params:
			if in_param == null:
				continue
			var param_name = in_param.name
			print( "  in_param. Name:'%s' Type:%s" % [ param_name, in_param.data_type ] )
			if not args.has( param_name ):
				args[ param_name ] = in_param.get_default_value()
				print( "  not found. Assigning default value" )
				changed = true

			else:
				var curr_val = args[ param_name ]
				if not FlowNodeBase.valueMatchesFlowDataType( curr_val, in_param.data_type ):
					print( "  found but wrong type. Assigning default value %s" % [ curr_val ] )
					changed = true
					args[ param_name ] = in_param.get_default_value()
				else:
					print( "  found and type matches. Do nothing" )
					pass

		var keys_to_delete = []
		print( "Args:", args)
		for arg_name in args.keys():
			var input = graph.findInParamByName( arg_name )
			if input == null:
				keys_to_delete.append( arg_name )
				changed = true
		for arg_name in keys_to_delete:
			args.erase( arg_name )

	else:
		#print( "Clearing current args. graph is null" )
		if args:
			args.clear()
			changed = true

	if changed:
		notify_property_list_changed()

func _ready():
	# Processing is enabled only while an async evaluation is in flight (see
	# generate_async()/_process). Disable it by default so the per-frame driver
	# never spins in the editor or before generation starts.
	set_process(false)
	if generate_on_ready and not Engine.is_editor_hint() and graph:
		execute()

## Kept for compatibility: generate() with default arguments, ignoring the
## returned outputs (generate_async() when async_generation is set, as before).
## Unlike generate(), an explicit execute() without a graph warns.
func execute() -> void:
	if not graph:
		push_warning("FlowGraphNode3D: no graph resource assigned")
		return
	if async_generation:
		generate_async()
	else:
		generate()

func _merged_inputs( inputs : Dictionary ) -> Dictionary:
	var base : Dictionary = args if args != null else {}
	return base.merged( inputs, true ) if inputs else base.duplicate()

func _make_context( extra_params : Dictionary ) -> FlowData.EvaluationContext:
	var base : Dictionary = params if params != null else {}
	var merged_params : Dictionary = base.merged( extra_params, true ) if extra_params else base
	return FlowNodeIOClass.make_context( self, seed, merged_params )

## Evaluate the graph synchronously and return its outputs (output name ->
## FlowData.Data). `inputs` are merged over `args` (graph input values);
## `extra_params` over `params` (runtime parameters). Stores last_outputs and
## emits `generated`. Does not clean up earlier output; see regenerate().
func generate( inputs : Dictionary = {}, extra_params : Dictionary = {} ) -> Dictionary:
	# A graph-less host is legal (e.g. assigned later from code): stay silent.
	if not graph:
		return {}
	# A synchronous run supersedes an in-flight async one; finish it first so
	# its node instances are freed.
	_finish_async_now( false )
	_cancel_cell_run()
	var ctx := _make_context( extra_params )
	_generating_sync = true
	# Root evaluation starts the recursion guard at depth 0; nested
	# subgraph/loop nodes call evaluate_graph with depth + 1.
	var result : Dictionary = FlowNodeIOClass.evaluate_collecting_errors( graph, _merged_inputs( inputs ), ctx )
	var outputs : Dictionary = result.outputs
	_generating_sync = false
	_on_generation_finished( outputs, result.errors )
	return outputs

## Time-sliced generation: the node-execution phase is spread across frames
## from _process(), at most `frame_budget_ms` per frame. On completion stores
## last_outputs and emits `generated`.
func generate_async( inputs : Dictionary = {}, extra_params : Dictionary = {} ) -> void:
	if not graph:
		return
	# If a previous async run is still in flight, the new run supersedes it;
	# flush it so its node instances are freed (no `generated` for it).
	_finish_async_now( false )
	_cancel_cell_run()
	var ctx := _make_context( extra_params )
	var input_map := _merged_inputs( inputs )
	_async_errors = FlowNodeIOClass.start_error_log( ctx )
	_async_eval = FlowNodeIOClass.begin_evaluation( graph, input_map, ctx, {}, 0 )
	# begin_evaluation returns null only on the recursion guard (depth 0 here),
	# but stay defensive: fall back to synchronous so generation still happens.
	if _async_eval == null:
		var result : Dictionary = FlowNodeIOClass.evaluate_collecting_errors( graph, input_map, ctx )
		_on_generation_finished( result.outputs, result.errors )
		return
	set_process(true)

## Evaluates one cell of hierarchical generation synchronously and returns its
## outputs. Only the nodes of the cell's level run (cell.run_nodes); nodes of
## coarser levels whose outputs they consume are taken from `preseeded` (node
## name -> generated bulks, Array of Array of FlowData.Data) and not run. The
## context carries the cell bounds, grid size, coordinate and hierarchy level
## (EvaluationContext.bounds / has_bounds / grid_size / cell_coord /
## hierarchy_level) and the graph variables of the coarser cells. Runs threaded
## when `threaded` is set and through FlowOutputCache when `output_cache` is
## set, exactly like generate(). Stores last_outputs, last_errors and last_cell
## and emits `generated`. Does not clean up earlier output.
func generate_cell( cell : FlowWorldCell, preseeded : Dictionary = {} ) -> Dictionary:
	var run := begin_cell( cell, preseeded, false )
	if run == null:
		return {}
	return run.run()

## Starts a cell evaluation and returns its FlowCellRun without running any
## node. With `time_sliced` the caller drives it with run.step(budget_ms) (one
## element per step(0)); otherwise run.run() executes it (threaded when
## `threaded` is set). A cell run in flight on this component is cancelled
## first. Returns null without a graph.
func begin_cell( cell : FlowWorldCell, preseeded : Dictionary = {}, time_sliced : bool = false ) -> FlowCellRun:
	if not graph or cell == null:
		return null
	_finish_async_now( false )
	_cancel_cell_run()
	var ctx := _make_context( {} )
	cell.apply_to_context( ctx )
	var error_log := FlowNodeIOClass.start_error_log( ctx )
	var executor := FlowExecutor.new()
	if time_sliced:
		executor.mode = FlowExecutor.Mode.TIME_SLICED
	elif ctx.get_meta( FlowExecutor.THREADED_META, false ):
		executor.mode = FlowExecutor.Mode.THREADED
	executor.node_filter = cell.node_filter()
	executor.preseeded = preseeded
	executor.capture_nodes = cell.capture_nodes
	last_cell = cell
	var started := executor.begin( graph, _merged_inputs( {} ), ctx, {}, 0 )
	var run := FlowCellRun.new( self, cell, executor if started else null, ctx, error_log )
	_cell_run = run
	return run

## True while a cell evaluation started by begin_cell() is unfinished.
func is_generating_cell() -> bool:
	return _cell_run != null and not _cell_run.is_done()

func _cancel_cell_run() -> void:
	if _cell_run != null and not _cell_run.is_done():
		_cell_run.cancel()
	_cell_run = null

# FlowCellRun callback: a finished run publishes like generate() does.
func _on_cell_run_finished( run : FlowCellRun, completed : bool ) -> void:
	if run == _cell_run:
		_cell_run = null
	if completed:
		_on_generation_finished( run.outputs, run.errors )

## Free every spawned node this component owns (flow_owner meta naming this
## component, or content saved by an earlier session under this node) and emit
## `cleaned_up`. Safe to call when nothing was generated.
func cleanup() -> void:
	_finish_async_now( false )
	_cancel_cell_run()
	var my_id := get_instance_id()
	var doomed : Array[Node] = []
	var seen := {}
	last_cleanup_visits = 0
	# The own subtree: content that names this component, legacy String metas
	# and stale component ids (docs/RUNTIME_API_P0.md §5).
	_collect_owned( self, my_id, true, doomed, seen )
	if _untracked_content:
		# Content stamped through flowOwnerMeta() alone (a third-party
		# spawner): its spawn parent is unknown, so scan the scene as before.
		var scan_root : Node = owner if owner != null else get_parent()
		if scan_root != null:
			_collect_owned( scan_root, my_id, false, doomed, seen )
	else:
		# Spawners may target a spawn_parent_path or a target node outside this
		# node: look only under the parents of the content this component
		# recorded (tagFlowContent), not through the whole scene.
		for parent in _external_spawn_parents():
			_collect_owned_children( parent, my_id, doomed, seen )
	_spawned_content.clear()
	_untracked_content = false
	for node in doomed:
		if not is_instance_valid( node ):
			continue
		var parent := node.get_parent()
		if parent:
			parent.remove_child( node )
		node.queue_free()
	cleaned_up.emit()

## Records spawned content of this component (called by
## FlowNodeBase.tagFlowContent), so cleanup() can find content spawned outside
## this node's subtree through its parent. Released by cleanup().
func note_spawned_content( node : Node ) -> void:
	if node == null:
		return
	_spawned_content[ node.get_instance_id() ] = true
	if _spawned_content.size() >= _spawned_content_compact_at:
		for id in _spawned_content.keys():
			if not is_instance_id_valid( id ):
				_spawned_content.erase( id )
		_spawned_content_compact_at = maxi( 1024, _spawned_content.size() * 2 )

## Content was stamped for this component without a record (flowOwnerMeta()
## called directly): the next cleanup() scans the scene for it.
func note_untracked_content() -> void:
	_untracked_content = true

## Number of content records cleanup() will look through (tests, diagnostics).
func recorded_content_count() -> int:
	return _spawned_content.size()

# Distinct parents of the recorded content that lie outside this node's subtree.
func _external_spawn_parents() -> Array:
	var parents := {}
	for id in _spawned_content:
		if not is_instance_id_valid( id ):
			continue
		var node := instance_from_id( id ) as Node
		if node == null:
			continue
		var parent := node.get_parent()
		if parent == null or parent == self or is_ancestor_of( parent ) or parents.has( parent ):
			continue
		parents[ parent ] = true
	return parents.keys()

# Direct children of `parent` that belong to component `my_id` (content roots sit
# directly under their spawn parent).
func _collect_owned_children( parent : Node, my_id : int, doomed : Array[Node], seen : Dictionary ) -> void:
	for child in parent.get_children():
		last_cleanup_visits += 1
		if child == self or seen.has( child ) or not child.has_meta( "flow_owner" ):
			continue
		var meta = child.get_meta( "flow_owner" )
		if meta is Dictionary and int( meta.get( "component", 0 ) ) == my_id:
			seen[ child ] = true
			doomed.append( child )

## cleanup() followed by generate(); returns the new outputs.
func regenerate( inputs : Dictionary = {}, extra_params : Dictionary = {} ) -> Dictionary:
	cleanup()
	return generate( inputs, extra_params )

## True while a generate() call or an async generation is in progress.
func is_generating() -> bool:
	return _generating_sync or ( _async_eval != null and not _async_eval.is_done() ) or is_generating_cell()

# Collects spawned subtree roots under `node` that belong to component `my_id`.
# Inside this component's own subtree (`own_subtree`), legacy String metas and
# metas naming a component that no longer exists (content saved into the scene
# by an earlier session) also belong to it.
func _collect_owned( node : Node, my_id : int, own_subtree : bool, doomed : Array[Node], seen : Dictionary ) -> void:
	for child in node.get_children():
		last_cleanup_visits += 1
		if not own_subtree and child == self:
			continue
		if child.has_meta( "flow_owner" ):
			var meta = child.get_meta( "flow_owner" )
			var mine := false
			if meta is Dictionary:
				var comp := int( meta.get( "component", 0 ) )
				mine = comp == my_id or ( own_subtree and FlowNodeBase.isStaleFlowComponent( comp ) )
			else:
				mine = own_subtree
			if mine:
				if not seen.has( child ):
					seen[ child ] = true
					doomed.append( child )
				continue
		_collect_owned( child, my_id, own_subtree, doomed, seen )

func _on_generation_finished( outputs : Dictionary, errors : Array = [] ) -> void:
	last_outputs = outputs if outputs != null else {}
	last_errors = errors.duplicate() if errors != null else []
	generated.emit( last_outputs )

# Run an in-flight async evaluation to completion now.
func _finish_async_now( emit_generated : bool ) -> void:
	if _async_eval == null:
		return
	var evaluation = _async_eval
	_async_eval = null
	set_process(false)
	if not evaluation.is_done():
		evaluation.run_to_completion()
	if emit_generated:
		_on_generation_finished( evaluation.outputs, _async_errors )

func _process(_delta: float) -> void:
	if _async_eval == null:
		set_process(false)
		return
	if _async_eval.step(frame_budget_ms):
		# Finished this frame: outputs collected, instances freed inside the
		# evaluator. Stop processing until the next generation.
		var evaluation = _async_eval
		_async_eval = null
		set_process(false)
		_on_generation_finished( evaluation.outputs, _async_errors )

func _exit_tree() -> void:
	# Ensure an in-flight async evaluation is finalized (instances freed) if the
	# host leaves the tree mid-generation.
	_finish_async_now( true )
