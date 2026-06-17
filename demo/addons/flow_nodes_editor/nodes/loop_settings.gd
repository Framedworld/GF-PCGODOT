@tool
class_name LoopNodeSettings
extends NodeSettings

@export_group("Loop")

## The sub-graph resource to execute repeatedly in the loop.
@export var graph : FlowGraphResource:
	set(value):
		graph = value
		emit_changed()
## The input port name of the sub-graph that receives each loop item.
@export var item_input_name : String = "item":
	set(value):
		item_input_name = value
		emit_changed()
## The attribute name in which to write the collected loop outputs.
@export var output_attribute_name : String = "result":
	set(value):
		output_attribute_name = value
		emit_changed()

## The parameter name in the sub-graph used to pass back feedback values.
@export var feedback_param_name : String = "":
	set(value):
		feedback_param_name = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Loop"

