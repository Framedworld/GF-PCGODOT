@tool
class_name SelectMultiNodeSettings
extends NodeSettings

@export_group("Select Multi")

## Static integer index option to select.
@export var index: int = 0
## If enabled, chooses index value from point attribute stream.
@export var use_attribute: bool = false
## The attribute stream name to retrieve indices from.
@export var attribute_name: String = ""

func _init():
	super._init()
	resource_name = "Select Multi Settings"
