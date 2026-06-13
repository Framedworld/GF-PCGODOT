@tool
extends NodeSettings

@export_group("Attribute Set To Point")

## Attribute name used for position in this node.
@export var position_attribute_name : String = "position":
	set(value):
		position_attribute_name = value.strip_edges()
		emit_changed()

## Attribute name used for rotation in this node.
@export var rotation_attribute_name : String = "rotation":
	set(value):
		rotation_attribute_name = value.strip_edges()
		emit_changed()

## Attribute name used for size in this node.
@export var size_attribute_name : String = "size":
	set(value):
		size_attribute_name = value.strip_edges()
		emit_changed()

## Toggles whether this node uses defaults when missing instead of default behavior.
@export var use_defaults_when_missing : bool = true:
	set(value):
		use_defaults_when_missing = value
		emit_changed()

## Fallback position used when the expected source attribute/data is missing.
@export var default_position : Vector3 = Vector3.ZERO:
	set(value):
		default_position = value
		emit_changed()

## Fallback rotation used when the expected source attribute/data is missing.
@export var default_rotation : Vector3 = Vector3.ZERO:
	set(value):
		default_rotation = value
		emit_changed()

## Fallback size used when the expected source attribute/data is missing.
@export var default_size : Vector3 = Vector3.ONE:
	set(value):
		default_size = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Attribute Set To Point Settings"
