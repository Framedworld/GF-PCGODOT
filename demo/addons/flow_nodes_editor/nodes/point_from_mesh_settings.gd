@tool
extends "res://addons/flow_nodes_editor/node_settings.gd"

@export_group("Point From Mesh")
## Input attribute name containing source mesh nodes.
@export var source_stream_name : String = "node":
	set(value):
		source_stream_name = value.strip_edges()
		emit_changed()
## If enabled, registers mesh resource references to streams.
@export var include_mesh_attribute : bool = true:
	set(value):
		if include_mesh_attribute != value:
			include_mesh_attribute = value
			notify_property_list_changed()
## Name of the output mesh resource stream.
@export var mesh_attribute_name : String = "mesh":
	set(value):
		mesh_attribute_name = value.strip_edges()
		emit_changed()
## If enabled, adjusts point bounds/size using world scale.
@export var use_world_scale_for_bounds : bool = true:
	set(value):
		use_world_scale_for_bounds = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Point From Mesh Settings"

func exposeParam(name : String) -> bool:
	if name == "mesh_attribute_name":
		return include_mesh_attribute
	return true
