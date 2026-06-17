@tool
extends NodeSettings

@export_group("Attribute Set To Point")

## The attribute name from the source point to be used as position.
@export var position_attribute_name : String = "position":
	set(value):
		position_attribute_name = value.strip_edges()
		emit_changed()

## The attribute name from the source point to be used as rotation.
@export var rotation_attribute_name : String = "rotation":
	set(value):
		rotation_attribute_name = value.strip_edges()
		emit_changed()

## The attribute name from the source point to be used as size.
@export var size_attribute_name : String = "size":
	set(value):
		size_attribute_name = value.strip_edges()
		emit_changed()

## If enabled, uses fallback constant values if the specified attributes are missing from the input data.
@export var use_defaults_when_missing : bool = true:
	set(value):
		use_defaults_when_missing = value
		emit_changed()

## The fallback position used when the position attribute is missing.
@export var default_position : Vector3 = Vector3.ZERO:
	set(value):
		default_position = value
		emit_changed()

## The fallback rotation used when the rotation attribute is missing.
@export var default_rotation : Vector3 = Vector3.ZERO:
	set(value):
		default_rotation = value
		emit_changed()

## The fallback size/scale used when the size attribute is missing.
@export var default_size : Vector3 = Vector3.ONE:
	set(value):
		default_size = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Attribute Set To Point Settings"
