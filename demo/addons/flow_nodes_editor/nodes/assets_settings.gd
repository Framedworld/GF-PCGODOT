@tool
class_name AssetsNodeSettings
extends NodeSettings

@export_group("Assets")

## List of Flow assets/data resources this node outputs.
@export var assets : Array[ FlowUserResourceData ] = []

func _init():
	super._init()
	resource_name = "Assets Settings"
