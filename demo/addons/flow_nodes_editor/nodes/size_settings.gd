@tool
class_name SizeNodeSettings
extends NodeSettings

@export_group("Size")

## Name of output vector attribute stream.
@export var out_name : String = "count"

func _init():
	super._init()
	resource_name = "Size Settings"
