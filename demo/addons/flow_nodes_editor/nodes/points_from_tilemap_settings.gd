@tool
extends NodeSettings

@export_group("Points From TileMap")
## Scene tree path to target TileMap.
@export var tilemap_path : String = ""
## Group name to scan for TileMaps when path is empty.
@export var group_name : String = ""
## Optional source item ID filter for tile matching.
@export var source_id_filter : int = -1
## Optional alternative tile ID filter.
@export var alternative_id_filter : int = -1
## Height offset assigned to point output positions.
@export var height : float = 0.0
## Scale multiplier applied to output positions.
@export var position_scale : float = 1.0
## The width/length dimension of each tile cell.
@export var cell_size : Vector2 = Vector2(1.0, 1.0)
## The height dimension of each tile cell.
@export var cell_height : float = 1.0
## If enabled, outputs tile details to point streams.
@export var include_tile_ids : bool = true:
	set(value):
		if include_tile_ids != value:
			include_tile_ids = value
			notify_property_list_changed()
## If enabled, outputs TileMap layer reference.
@export var include_layer_ref : bool = false

## Output cell coordinate attribute stream.
@export var out_cell_attribute : String = "tile_cell":
	set(value):
		out_cell_attribute = value.strip_edges()
		emit_changed()
## Output source ID attribute stream.
@export var out_source_id_attribute : String = "tile_source_id":
	set(value):
		out_source_id_attribute = value.strip_edges()
		emit_changed()
## Output alternative ID attribute stream.
@export var out_alternative_id_attribute : String = "tile_alt_id":
	set(value):
		out_alternative_id_attribute = value.strip_edges()
		emit_changed()
## Output TileMap layer reference attribute stream.
@export var out_layer_attribute : String = "tile_layer":
	set(value):
		out_layer_attribute = value.strip_edges()
		emit_changed()

func _init():
	super._init()
	resource_name = "Points From TileMap Settings"

func exposeParam(name : String) -> bool:
	if name == "out_source_id_attribute" or name == "out_alternative_id_attribute":
		return include_tile_ids
	if name == "out_layer_attribute":
		return include_layer_ref
	return true
