@tool
class_name BranchNodeSettings
extends NodeSettings

@export_group("Branch")

## Boolean branch selector that decides whether A or B output path executes.
@export var branch_value: bool = true
## Toggles whether this node uses attribute instead of default behavior.
@export var use_attribute: bool = false
## Name of the attribute this node reads from or writes to.
@export var attribute_name: String = ""

func _init():
	super._init()
	resource_name = "Branch Settings"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "attribute_name", "port": 0 },
	]
