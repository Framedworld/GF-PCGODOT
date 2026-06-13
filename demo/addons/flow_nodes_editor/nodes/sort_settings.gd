@tool
class_name SortNodeSettings
extends NodeSettings

@export_group("Sort")

## Attribute name used as the sort key.
@export var sort_by : String
## If enabled, sorts highest-to-lowest instead of ascending order.
@export var sort_descending : bool = false

func _init():
	super._init()
	resource_name = "Sort Settings"
