@tool
class_name SwitchNodeSettings
extends NodeSettings

@export_group("Switch")

## Index used to pick/select an item from a sequence or collection.
@export var index: int = 0
## Toggles whether this node uses attribute instead of default behavior.
@export var use_attribute: bool = false
## Name of the attribute this node reads from or writes to.
@export var attribute_name: String = ""

func _init():
	super._init()
	resource_name = "Switch Settings"
