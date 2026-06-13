@tool
class_name DecomposeVectorNodeSettings
extends NodeSettings

@export_group("Decompose Vector")
## Input attribute name this node reads for .
@export var in_attribute: String = "position"
## Attribute name used to read/write x on point data.
@export var x_attribute: String = "x"
## Attribute name used to read/write y on point data.
@export var y_attribute: String = "y"
## Attribute name used to read/write z on point data.
@export var z_attribute: String = "z"

func _init():
	super._init()
	resource_name = "Decompose Vector Settings"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "in_attribute", "port": 0 },
	]
