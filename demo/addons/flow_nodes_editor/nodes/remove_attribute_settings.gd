@tool
class_name RemoveAttributeNodeSettings
extends NodeSettings

@export_group("Remove Attribute")

## Array of attribute names to target for deletion.
@export var names : Array[String] = []
## If enabled, keeps targeted attributes and deletes all others instead.
@export var keep_selected_attributes : bool = false

func _init():
	super._init()
	resource_name = "Remove Attribute Settings"
