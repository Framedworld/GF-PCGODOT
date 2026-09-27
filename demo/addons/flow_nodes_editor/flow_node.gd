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
## node inside that subgraph only. Beats $param bindings; a wired port still wins.
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
				if in_param.data_type != FlowNodeBase.getFlowDataTypeFromObject( curr_val ):
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

## Free every spawned node this component owns (flow_owner meta naming this
## component, or content saved by an earlier session under this node) and emit
## `cleaned_up`. Safe to call when nothing was generated.
func cleanup() -> void:
	_finish_async_now( false )
	var my_id := get_instance_id()
	var doomed : Array[Node] = []
	_collect_owned( self, my_id, true, doomed )
	# Spawners may target a spawn_parent_path outside this node; claim content
	# that names this component anywhere else in the same scene.
	var scan_root : Node = owner if owner != null else get_parent()
	if scan_root != null:
		_collect_owned( scan_root, my_id, false, doomed )
	for node in doomed:
		if not is_instance_valid( node ):
			continue
		var parent := node.get_parent()
		if parent:
			parent.remove_child( node )
		node.queue_free()
	cleaned_up.emit()

## cleanup() followed by generate(); returns the new outputs.
func regenerate( inputs : Dictionary = {}, extra_params : Dictionary = {} ) -> Dictionary:
	cleanup()
	return generate( inputs, extra_params )

## True while a generate() call or an async generation is in progress.
func is_generating() -> bool:
	return _generating_sync or ( _async_eval != null and not _async_eval.is_done() )

# Collects spawned subtree roots under `node` that belong to component `my_id`.
# Inside this component's own subtree (`own_subtree`), legacy String metas and
# metas naming a component that no longer exists (content saved into the scene
# by an earlier session) also belong to it.
func _collect_owned( node : Node, my_id : int, own_subtree : bool, doomed : Array[Node] ) -> void:
	for child in node.get_children():
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
				if not doomed.has( child ):
					doomed.append( child )
				continue
		_collect_owned( child, my_id, own_subtree, doomed )

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
