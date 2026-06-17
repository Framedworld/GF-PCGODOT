@tool
class_name SwitchNodeSettings
extends NodeSettings

@export_group("Switch")

## Selection index path to route.
@export var index: int = 0
## If enabled, reads index from point attribute stream.
@export var use_attribute: bool = false
## The attribute stream name to read routing index from.
@export var attribute_name: String = ""

func _init():
	super._init()
	resource_name = "Switch Settings"
