@tool
class_name BuildRotationFromUpNodeSettings
extends NodeSettings

@export_group("Build Rotation From Up Vector")

## The attribute name on point data representing the target normal/up vector.
@export var up_vector_attribute: String = "normal"
## The fallback up vector to use if the specified attribute is missing.
@export var up_vector_constant: Vector3 = Vector3.UP
## If enabled, always uses the constant up vector instead of checking for an attribute.
@export var use_constant: bool = false
## The coordinate axis (x, y, or z) that should align to the target up vector.
@export var axis: String = "z"

func _init():
	super._init()
	resource_name = "Build Rotation From Up Vector Settings"
