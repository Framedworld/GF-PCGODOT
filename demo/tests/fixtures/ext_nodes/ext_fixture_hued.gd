@tool
extends FlowNodeBase

# Test fixture: a project-category node that pins its title colour with
# `meta_node.hue`, so every node of the category shares one colour.

func _init():
	meta_node = {
		"title" : "Ext Fixture Hued",
		"category" : "My Project",
		"hue" : 0.62,
		"settings" : NodeSettings,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Test fixture node with a project category hue.",
	}

func execute( _ctx : FlowData.EvaluationContext ):
	set_output(0, FlowData.Data.new())
