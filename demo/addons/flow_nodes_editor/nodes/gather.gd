@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Gather",
		"settings" : NodeSettings,
		"ins" : [{ "label": "In" }, { "label": "Dependency Only" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Collects every data wired into In onto one output pin, in wire order, without merging them\n" +
			"(each data keeps its own points, attributes and tags; Merge would concatenate them into one).\n" +
			"Dependency Only wires only order execution: their data is not forwarded.",
		"aliases" : ["Gather", "Collect"],
		"category" : "Utility",
	}

# Runs once per data on In (the evaluator iterates the bulks of pin 0) and
# forwards it unchanged, so the output carries the same entries in the same order.
func execute( _ctx : FlowData.EvaluationContext ):
	var in_data = get_optional_input( 0 )
	if in_data is FlowData.Data:
		set_output( 0, in_data )
