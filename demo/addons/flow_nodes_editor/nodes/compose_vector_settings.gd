@tool
class_name ComposeVectorNodeSettings
extends NodeSettings

@export_group("Compose Vector")
## Attribute name used to read/write x on point data.
@export var x_attribute: String = ""
## Attribute name used to read/write y on point data.
@export var y_attribute: String = ""
## Attribute name used to read/write z on point data.
@export var z_attribute: String = ""
## Fallback value used when the expected source attribute/data is missing.
@export var default_value: Vector3 = Vector3.ONE
## Output attribute name that stores  produced by this node.
@export var out_attribute: String = "size"

func _init():
	super._init()
	resource_name = "Compose Vector Settings"
