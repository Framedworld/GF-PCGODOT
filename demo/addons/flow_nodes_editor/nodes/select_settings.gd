@tool
class_name SelectNodeSettings
extends NodeSettings

@export_group("Select")

## If enabled, outputs path B instead of path A.
@export var select_b: bool = false
## If enabled, reads path selection flag from point attribute.
@export var use_attribute: bool = false
## The boolean attribute stream name to read selection from.
@export var attribute_name: String = ""

func _init():
	super._init()
	resource_name = "Select Settings"
