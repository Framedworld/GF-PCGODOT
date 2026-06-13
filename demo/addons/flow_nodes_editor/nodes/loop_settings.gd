@tool
class_name LoopNodeSettings
extends NodeSettings

@export_group("Loop")

## PCG graph resource this subgraph node executes.
@export var graph : FlowGraphResource:
	set(value):
		graph = value
		emit_changed()
## Input pin/parameter name used for the current loop item in subgraph execution.
@export var item_input_name : String = "item":
	set(value):
		item_input_name = value
		emit_changed()
## Attribute name used for output in this node.
@export var output_attribute_name : String = "result":
	set(value):
		output_attribute_name = value
		emit_changed()

## Parameter name used to feed previous-iteration data back into the next loop step.
@export var feedback_param_name : String = "":
	set(value):
		feedback_param_name = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Loop"

