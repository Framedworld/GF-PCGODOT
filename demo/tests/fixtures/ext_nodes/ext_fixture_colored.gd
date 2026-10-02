@tool
extends FlowNodeBase

# Test fixture: a project-category node that pins its title colour with
# `meta_node.color`.

func _init():
	meta_node = {
		"title" : "Ext Fixture Colored",
		"category" : "My Project",
		"color" : Color(0.9, 0.3, 0.1),
		"settings" : NodeSettings,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Test fixture node with a project category colour.",
	}

func execute( _ctx : FlowData.EvaluationContext ):
	set_output(0, FlowData.Data.new())
