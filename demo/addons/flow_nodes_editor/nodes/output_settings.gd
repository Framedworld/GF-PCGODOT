@tool
class_name OutputNodeSettings
extends NodeSettings

@export_group("Output")

## Human-readable name/key used by this node when creating or selecting entries.
@export var name : String = "out_val"
## Data type used when creating streams/attributes or interpreting values.
@export var data_type : FlowData.DataType = FlowData.DataType.Float

func _init():
	super._init()
	resource_name = "Output"
