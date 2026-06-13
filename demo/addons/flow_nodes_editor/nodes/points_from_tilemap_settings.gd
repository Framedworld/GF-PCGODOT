@tool
extends NodeSettings

@export_group("Points From TileMap")
## Scene/resource path used to resolve tilemap.
@export var tilemap_path : String = ""
## Group name used to find or filter scene nodes.
@export var group_name : String = ""
## Optional filter for source id; only matching values are processed.
@export var source_id_filter : int = -1
## Optional filter for alternative id; only matching values are processed.
@export var alternative_id_filter : int = -1
## Height value used when generating points/rooms in 3D space.
@export var height : float = 0.0
## TileMap positions are in 2D pixels; this scale converts them to world units
## (e.g. 1/64 for 64px tiles mapping to 1m cells) so positions match cell_size.
@export var position_scale : float = 1.0
## Size of each grid cell used by this node.
@export var cell_size : Vector2 = Vector2(1.0, 1.0)
## Vertical spacing between generated tile/grid levels.
@export var cell_height : float = 1.0
## When enabled, also outputs tile ids alongside generated points/data.
@export var include_tile_ids : bool = true:
	set(value):
		if include_tile_ids != value:
			include_tile_ids = value
			notify_property_list_changed()
## When enabled, also outputs layer ref alongside generated points/data.
@export var include_layer_ref : bool = false

## Output attribute name that stores cell produced by this node.
@export var out_cell_attribute : String = "tile_cell":
	set(value):
		out_cell_attribute = value.strip_edges()
		emit_changed()
## Output attribute name that stores source id produced by this node.
@export var out_source_id_attribute : String = "tile_source_id":
	set(value):
		out_source_id_attribute = value.strip_edges()
		emit_changed()
## Output attribute name that stores alternative id produced by this node.
@export var out_alternative_id_attribute : String = "tile_alt_id":
	set(value):
		out_alternative_id_attribute = value.strip_edges()
		emit_changed()
## Output attribute name that stores layer produced by this node.
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
