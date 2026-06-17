@tool
class_name DecomposeVectorNodeSettings
extends NodeSettings

@export_group("Decompose Vector")
## The name of the Vector3 attribute stream to decompose.
@export var in_attribute: String = "position"
## The name of the float attribute stream to store the X component in.
@export var x_attribute: String = "x"
## The name of the float attribute stream to store the Y component in.
@export var y_attribute: String = "y"
## The name of the float attribute stream to store the Z component in.
@export var z_attribute: String = "z"

func _init():
	super._init()
	resource_name = "Decompose Vector Settings"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "in_attribute", "port": 0 },
	]
