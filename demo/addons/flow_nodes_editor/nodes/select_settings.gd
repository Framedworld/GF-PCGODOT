@tool
class_name SelectNodeSettings
extends NodeSettings

@export_group("Select")

## If enabled, routes input B; otherwise routes input A.
@export var select_b: bool = false
## Toggles whether this node uses attribute instead of default behavior.
@export var use_attribute: bool = false
## Name of the attribute this node reads from or writes to.
@export var attribute_name: String = ""

func _init():
	super._init()
	resource_name = "Select Settings"
