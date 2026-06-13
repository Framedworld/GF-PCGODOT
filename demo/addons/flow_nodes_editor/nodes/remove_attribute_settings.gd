@tool
class_name RemoveAttributeNodeSettings
extends NodeSettings

@export_group("Remove Attribute")

## List of attribute names to remove from each point/entry.
@export var names : Array[String] = []
## When enabled, preserves selected attributes instead of discarding/replacing it.
@export var keep_selected_attributes : bool = false

func _init():
	super._init()
	resource_name = "Remove Attribute Settings"
