@tool
class_name ComposeVectorNodeSettings
extends NodeSettings

@export_group("Compose Vector")
## The attribute stream name to read the Vector's X component from.
@export var x_attribute: String = ""
## The attribute stream name to read the Vector's Y component from.
@export var y_attribute: String = ""
## The attribute stream name to read the Vector's Z component from.
@export var z_attribute: String = ""
## The fallback Vector3 value to use for components whose attributes are missing or unspecified.
@export var default_value: Vector3 = Vector3.ONE
## The name of the output Vector3 attribute stream to write to.
@export var out_attribute: String = "size"

func _init():
	super._init()
	resource_name = "Compose Vector Settings"
