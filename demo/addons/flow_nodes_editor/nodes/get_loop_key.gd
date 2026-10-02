@tool
extends FlowNodeBase

## Get Loop Key: the key of the enclosing Loop iteration. In Points mode that
## is the point index, in Entries mode the entry index (or the entry's
## key_attribute value), in Partitions mode the partition value and in Chunks
## mode the chunk index (docs/_round2/WP8.md). The attribute type follows the
## key: Int for indices, the partition attribute's type for partitions.

const GetLoopKeyNodeSettings = preload("res://addons/flow_nodes_editor/nodes/get_loop_key_settings.gd")
const GetLoopIndexNode = preload("res://addons/flow_nodes_editor/nodes/get_loop_index.gd")

## Runtime parameter a Loop gives each iteration (nodes/loop.gd PARAM_KEY).
const ITERATION_KEY_PARAM := "iteration_key"
## Declared type of that key (nodes/loop.gd PARAM_KEY_TYPE), present for a
## partition over an attribute whose type the Variant cannot tell (Int64, Double).
const ITERATION_KEY_TYPE_PARAM := "iteration_key_type"

func _init():
	meta_node = {
		"title" : "Get Loop Key",
		"settings" : GetLoopKeyNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"category" : "Utility",
		"tooltip" : "Writes the enclosing Loop iteration's key: the point, entry or chunk index, or the partition value. Written to every incoming point, or as a one-value Data when In is not connected.",
	}

func execute(ctx : FlowData.EvaluationContext):
	var out_name = settings.out_name.strip_edges()
	if out_name == "":
		setError("Output name can't be empty")
		return
	var params : Dictionary = ctx.runtime_params if ctx != null and ctx.runtime_params else {}
	var value = -1
	if params.has(ITERATION_KEY_PARAM):
		value = params[ITERATION_KEY_PARAM]
	elif not is_ownerless_preview(ctx):
		setError(GetLoopIndexNode.NOT_IN_LOOP_ERROR % ITERATION_KEY_PARAM)
	var data_type := FlowData.Data._inferValueType(value)
	# An Int64 partition key arrives as a plain int and a Double as a float:
	# inferring from the Variant would store them as Int and Float.
	if params.has(ITERATION_KEY_TYPE_PARAM):
		var declared : int = int(params[ITERATION_KEY_TYPE_PARAM])
		if declared == FlowData.DataType.Int64 and typeof(value) == TYPE_INT:
			data_type = FlowData.DataType.Int64
		elif declared == FlowData.DataType.Double and typeof(value) == TYPE_FLOAT:
			data_type = FlowData.DataType.Double
	if data_type == FlowData.DataType.Invalid:
		setError("Loop key of type %s cannot be stored in an attribute" % type_string(typeof(value)))
		return
	var out_data = GetLoopIndexNode.write_loop_value(get_optional_input(0), out_name, value, data_type)
	if out_data is String:
		setError(out_data)
		return
	set_output(0, out_data)
