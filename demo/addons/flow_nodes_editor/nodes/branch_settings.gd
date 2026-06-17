@tool
class_name BranchNodeSettings
extends NodeSettings

@export_group("Branch")

## The static boolean selector that determines which output path (A or B) will be executed.
@export var branch_value: bool = true
## If enabled, decides the execution path based on a point/data attribute rather than the static branch value.
@export var use_attribute: bool = false
## The name of the attribute stream to read from when use_attribute is enabled.
@export var attribute_name: String = ""

func _init():
	super._init()
	resource_name = "Branch Settings"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "attribute_name", "port": 0 },
	]
