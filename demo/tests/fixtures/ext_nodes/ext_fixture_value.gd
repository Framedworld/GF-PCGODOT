@tool
extends FlowNodeBase

# Test fixture: a project-side node that lives outside the addon. Tests add this
# directory through the `flow_nodes/node_directories` project setting and check that
# the template resolves and evaluates. Emits one point-less stream "ext_value".

func _init():
	meta_node = {
		"title" : "Ext Fixture Value",
		"category" : "Utility",
		"settings" : NodeSettings,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Test fixture node loaded from a project node directory.",
	}

func execute( _ctx : FlowData.EvaluationContext ):
	var output := FlowData.Data.new()
	output.registerStream("ext_value", PackedFloat32Array([42.0]), FlowData.DataType.Float)
	set_output(0, output)
