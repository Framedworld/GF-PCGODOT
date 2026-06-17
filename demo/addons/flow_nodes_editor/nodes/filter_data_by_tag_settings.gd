@tool
class_name FilterDataByTagNodeSettings
extends NodeSettings

@export_group("Filter Data By Tag")

## A comma-separated list of tags to filter the data containers by. Preserves containers matching any of the specified tags.
@export var tags: String = ""

func _init():
	super._init()
	resource_name = "Filter Data By Tag Settings"
