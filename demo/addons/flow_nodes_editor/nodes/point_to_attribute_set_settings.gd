@tool
extends NodeSettings

@export_group("Point To Attribute Set")

## If enabled, deletes canonical transform streams (position/rotation/size) from point container.
@export var drop_point_transform_streams : bool = true:
	set(value):
		if drop_point_transform_streams != value:
			drop_point_transform_streams = value
			notify_property_list_changed()

## If enabled, stores transform properties in custom attribute streams before dropping.
@export var preserve_transforms_as_attributes : bool = true:
	set(value):
		if preserve_transforms_as_attributes != value:
			preserve_transforms_as_attributes = value
			notify_property_list_changed()

## Output custom attribute name for preserved position.
@export var out_position_attribute_name : String = "point_position":
	set(value):
		out_position_attribute_name = value.strip_edges()
		emit_changed()

## Output custom attribute name for preserved rotation.
@export var out_rotation_attribute_name : String = "point_rotation":
	set(value):
		out_rotation_attribute_name = value.strip_edges()
		emit_changed()

## Output custom attribute name for preserved size.
@export var out_size_attribute_name : String = "point_size":
	set(value):
		out_size_attribute_name = value.strip_edges()
		emit_changed()

func _init():
	super._init()
	resource_name = "Point To Attribute Set Settings"

func exposeParam(name : String) -> bool:
	if name == "preserve_transforms_as_attributes":
		return drop_point_transform_streams
	if name == "out_position_attribute_name" or name == "out_rotation_attribute_name" or name == "out_size_attribute_name":
		return drop_point_transform_streams and preserve_transforms_as_attributes
	return true
