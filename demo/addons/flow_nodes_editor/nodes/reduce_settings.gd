@tool
class_name ReduceNodeSettings
extends NodeSettings

@export_group("Reduce")

## Input attribute stream name to evaluate and reduce.
@export var in_name : String
## Prefix message added to print output.
@export var out_prefix : String

func _init():
	super._init()
	resource_name = "Reduce Settings"
