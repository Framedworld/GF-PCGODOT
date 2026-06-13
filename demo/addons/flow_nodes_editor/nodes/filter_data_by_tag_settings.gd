@tool
class_name FilterDataByTagNodeSettings
extends NodeSettings

@export_group("Filter Data By Tag")

## Tag list used for filtering or mutation, depending on node mode.
@export var tags: String = ""

func _init():
	super._init()
	resource_name = "Filter Data By Tag Settings"
