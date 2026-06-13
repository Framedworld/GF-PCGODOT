@tool
extends NodeSettings

@export_group("Points From GridMap")
## Scene/resource path used to resolve gridmap.
@export var gridmap_path : String = ""
## Group name used to find or filter scene nodes.
@export var group_name : String = ""
## Optional filter for item id; only matching values are processed.
@export var item_id_filter : int = -1
## Offset applied to y offset before writing final output values.
@export var y_offset : float = 0.0
## When enabled, also outputs item id alongside generated points/data.
@export var include_item_id : bool = true:
	set(value):
		if include_item_id != value:
			include_item_id = value
			notify_property_list_changed()
## When enabled, also outputs gridmap ref alongside generated points/data.
@export var include_gridmap_ref : bool = false

## Output attribute name that stores cell produced by this node.
@export var out_cell_attribute : String = "grid_cell":
	set(value):
		out_cell_attribute = value.strip_edges()
		emit_changed()
## Output attribute name that stores item id produced by this node.
@export var out_item_id_attribute : String = "grid_item_id":
	set(value):
		out_item_id_attribute = value.strip_edges()
		emit_changed()
## Output attribute name that stores gridmap produced by this node.
@export var out_gridmap_attribute : String = "gridmap_node":
	set(value):
		out_gridmap_attribute = value.strip_edges()
		emit_changed()

func _init():
	super._init()
	resource_name = "Points From GridMap Settings"

func exposeParam(name : String) -> bool:
	if name == "out_item_id_attribute":
		return include_item_id
	if name == "out_gridmap_attribute":
		return include_gridmap_ref
	return true
