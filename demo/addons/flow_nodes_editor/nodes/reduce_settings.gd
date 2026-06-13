@tool
class_name ReduceNodeSettings
extends NodeSettings

@export_group("Reduce")

## Name of the input attribute to read from.
@export var in_name : String
## Output value/attribute key used for prefix.
@export var out_prefix : String

func _init():
	super._init()
	resource_name = "Reduce Settings"
