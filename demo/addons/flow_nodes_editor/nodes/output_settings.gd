@tool
class_name OutputNodeSettings
extends NodeSettings

@export_group("Output")

## The name of the output port/resource parameter.
@export var name : String = "out_val"
## The data type expected for this output.
@export var data_type : FlowData.DataType = FlowData.DataType.Float

func _init():
	super._init()
	resource_name = "Output"
