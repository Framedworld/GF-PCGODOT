@tool
class_name FilterDataByAttributeNodeSettings
extends NodeSettings

@export_group("Filter Data By Attribute")

## The name of the attribute stream to filter the data containers by. Only containers containing this attribute are preserved.
@export var attribute_name: String = ""

func _init():
	super._init()
	resource_name = "Filter Data By Attribute Settings"
