@tool
class_name SortNodeSettings
extends NodeSettings

@export_group("Sort")

## The attribute stream name to sort the points by.
@export var sort_by : String
## If enabled, sorts points in descending order. If disabled, sorts in ascending order.
@export var sort_descending : bool = false

func _init():
	super._init()
	resource_name = "Sort Settings"
