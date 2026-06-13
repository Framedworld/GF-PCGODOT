@tool
extends Node3D
class_name FlowGraphNode3D

# This is the Node3d the user will instantiate in his final 3D scenes to trigger
# the generation of pcg
# It technically should not need to be a Node3D, as the transform is not really used
# but I'm currently generating the spawned nodes as child of this nodes

const FlowNodeIOClass = preload("res://addons/flow_nodes_editor/flow_nodes_io.gd")

@export var graph : FlowGraphResource :
	set(new_value):
		_graph = new_value
		graph_node_changed.emit( self, "graph_resource" )

	get:
		return _graph

var _graph : FlowGraphResource = FlowGraphResource.new()
signal graph_node_changed( graph_node : FlowGraphNode3D, prop_name : String )

# custom inputs values for this instantiation
@export var args : Dictionary = {}

# --- Async / time-sliced generation (PARITY_ROADMAP async stage 2, opt-in) ---
# When false (the default), execute() runs a single synchronous evaluate_graph()
# exactly as before — byte-for-byte the historical behavior. When true, the
# evaluation is built once and its node-execution phase is spread across frames
# from _process(), spending at most `frame_budget_ms` per frame. Topo sort,
# cycle detection, variable/runtime-param publishing and node-instance freeing
# are identical on both paths (the async path drives the very same evaluator
# helpers). This is the prerequisite hook for HiGen proximity scheduling.
@export var async_generation : bool = false
# Per-frame wall-clock budget for the async path, in milliseconds. Ignored when
# async_generation is false.
@export var frame_budget_ms : float = 4.0

# Active resumable evaluation while async generation is in flight (null otherwise).
var _async_eval = null

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
	# execute()/_process). Disable it by default so the per-frame driver never
	# spins in the editor or before generation starts.
	set_process(false)
	if not Engine.is_editor_hint():
		execute()

func execute() -> void:
	if not graph:
		push_warning("FlowGraphNode3D: no graph resource assigned")
		return
	var ctx = load("res://addons/flow_nodes_editor/flow_data.gd").EvaluationContext.new()
	ctx.owner = self
	ctx.eval_id = 0
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = {}
	# Root evaluation starts the recursion guard at depth 0; nested
	# subgraph/loop nodes call evaluate_graph with depth + 1.
	if async_generation:
		# Build the resumable evaluation now; _process() drives it across frames.
		# If a previous async run was still in flight, drop it (the new run
		# supersedes it) — its instances are freed when finalize never runs only
		# if we explicitly complete it, so flush it first to avoid a node leak.
		if _async_eval != null and not _async_eval.is_done():
			_async_eval.run_to_completion()
		_async_eval = FlowNodeIOClass.begin_evaluation(graph, args if args != null else {}, ctx, {}, 0)
		# begin_evaluation returns null only on the recursion guard (depth 0 here),
		# but stay defensive: fall back to synchronous so generation still happens.
		if _async_eval == null:
			FlowNodeIOClass.evaluate_graph(graph, args if args != null else {}, ctx, {}, 0)
			return
		set_process(true)
	else:
		# Default path: unchanged single synchronous evaluation.
		FlowNodeIOClass.evaluate_graph(graph, args if args != null else {}, ctx, {}, 0)

func _process(_delta: float) -> void:
	if _async_eval == null:
		set_process(false)
		return
	if _async_eval.step(frame_budget_ms):
		# Finished this frame: outputs collected, instances freed inside the
		# evaluator. Stop processing until the next execute().
		_async_eval = null
		set_process(false)

func _exit_tree() -> void:
	# Ensure an in-flight async evaluation is finalized (instances freed) if the
	# host leaves the tree mid-generation.
	if _async_eval != null and not _async_eval.is_done():
		_async_eval.run_to_completion()
	_async_eval = null
