@tool
extends NodeSettings

@export_group("Points From GridMap")
## The Scene tree path to target GridMap.
@export var gridmap_path : String = ""
## Group name to scan for GridMaps when path is empty.
@export var group_name : String = ""
## Optional comma-separated grid item IDs to filter.
@export var item_id_filter : int = -1
## Vertical offset offset applied to generated points.
@export var y_offset : float = 0.0
## If enabled, writes block item IDs to point streams.
@export var include_item_id : bool = true:
	set(value):
		if include_item_id != value:
			include_item_id = value
			notify_property_list_changed()
## If enabled, writes GridMap node references to point streams.
@export var include_gridmap_ref : bool = false

## Output attribute stream storing grid cell coordinates (Vector3i).
@export var out_cell_attribute : String = "grid_cell":
	set(value):
		out_cell_attribute = value.strip_edges()
		emit_changed()
## Output attribute stream storing item IDs (Int).
@export var out_item_id_attribute : String = "grid_item_id":
	set(value):
		out_item_id_attribute = value.strip_edges()
		emit_changed()
## Output attribute stream storing GridMap reference.
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
