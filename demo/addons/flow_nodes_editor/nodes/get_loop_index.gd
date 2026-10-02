@tool
extends FlowNodeBase

const GetLoopIndexNodeSettings = preload("res://addons/flow_nodes_editor/nodes/get_loop_index_settings.gd")

## Runtime parameter a Loop gives each iteration (nodes/loop.gd PARAM_INDEX).
const ITERATION_INDEX_PARAM := "iteration_index"
const NOT_IN_LOOP_ERROR := "Not inside a Loop iteration (no '%s' runtime parameter)"

func _init():
	meta_node = {
		"title" : "Get Loop Index",
		"settings" : GetLoopIndexNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Get Loop Index"],
		"category" : "Utility",
		"tooltip" : "Source Points (default): writes a sequential index attribute for each incoming point (start_index..start_index+N-1), closer to UE's $Index.\nSource Loop Iteration: writes the enclosing Loop's iteration index (UE's Get Loop Index), in every loop iteration mode.",
	}

func execute(ctx : FlowData.EvaluationContext):
	if settings.source == GetLoopIndexNodeSettings.eSource.LoopIteration:
		_execute_loop_iteration(ctx)
		return

	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return

	var out_name = settings.out_name.strip_edges()
	if out_name == "":
		setError("Output name can't be empty")
		return

	var num_points = in_data.size()
	var out_indices := PackedInt32Array()
	out_indices.resize(num_points)
	for i in range(num_points):
		out_indices[i] = settings.start_index + i

	var out_data = in_data.duplicate()
	var err = out_data.registerStream(out_name, out_indices, FlowData.DataType.Int)
	if err:
		setError(err)
		return

	set_output(0, out_data)

func _execute_loop_iteration(ctx : FlowData.EvaluationContext) -> void:
	var out_name = settings.out_name.strip_edges()
	if out_name == "":
		setError("Output name can't be empty")
		return
	var value := -1
	var params : Dictionary = ctx.runtime_params if ctx != null and ctx.runtime_params else {}
	if params.has(ITERATION_INDEX_PARAM):
		value = int(params[ITERATION_INDEX_PARAM]) + settings.start_index
	elif not is_ownerless_preview(ctx):
		setError(NOT_IN_LOOP_ERROR % ITERATION_INDEX_PARAM)
	var out_data = write_loop_value(get_optional_input(0), out_name, value, FlowData.DataType.Int)
	if out_data is String:
		setError(out_data)
		return
	set_output(0, out_data)

## `in_data` (duplicated) with stream `out_name` holding `value` for every
## point, or a one-value Data when `in_data` is not a Data. Returns the Data,
## or an error String.
static func write_loop_value(in_data, out_name : String, value, data_type : int):
	if not (in_data is FlowData.Data):
		return FlowData.Data.scalar(out_name, value, data_type)
	var out_data : FlowData.Data = in_data.duplicate()
	var container = FlowData.Data.newContainerOfType(data_type)
	if container == null:
		return "Unsupported loop value type for %s" % out_name
	container.resize(out_data.size())
	for i in range(out_data.size()):
		FlowData.Data.writeValue(container, i, value, data_type)
	var err = out_data.registerStream(out_name, container, data_type)
	if err:
		return err
	return out_data
