@tool
class_name BuildRotationFromUpNodeSettings
extends NodeSettings

@export_group("Build Rotation From Up Vector")

## Attribute name used to read/write up vector on point data.
@export var up_vector_attribute: String = "normal"
## Fallback up vector used when no up-vector attribute is provided.
@export var up_vector_constant: Vector3 = Vector3.UP
## Toggles whether this node uses constant instead of default behavior.
@export var use_constant: bool = false
## Axis used as forward/reference when building rotation from up vectors.
@export var axis: String = "z"

func _init():
	super._init()
	resource_name = "Build Rotation From Up Vector Settings"
