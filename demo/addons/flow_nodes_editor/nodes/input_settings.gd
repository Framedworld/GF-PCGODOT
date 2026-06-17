@tool
class_name InputNodeSettings
extends NodeSettings

@export_group("Input")

## The name of the input port/resource parameter.
@export var name : String = "in_val"
## The data type expected for this input.
@export var data_type : FlowData.DataType = FlowData.DataType.Float

func _init():
	super._init()
	resource_name = "Input"
