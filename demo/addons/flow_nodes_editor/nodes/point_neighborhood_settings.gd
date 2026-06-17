@tool
extends NodeSettings

@export_group("Point Neighborhood")
## The radius distance to check for neighbors.
@export var search_distance : float = 300.0:
	set(value):
		search_distance = maxf(0.0, value)
		emit_changed()
## If enabled, includes self in neighbor calculations.
@export var include_self : bool = false:
	set(value):
		include_self = value
		emit_changed()

@export_group("Neighborhood Source Attributes")
## Input density attribute stream name.
@export var density_attribute : String = "density":
	set(value):
		density_attribute = value.strip_edges()
		emit_changed()
## Input color attribute stream name.
@export var color_attribute : String = "color":
	set(value):
		color_attribute = value.strip_edges()
		emit_changed()

@export_group("Outputs")
## If enabled, writes neighbor count to stream.
@export var write_neighbor_count : bool = true:
	set(value):
		write_neighbor_count = value
		emit_changed()
## Output neighbor count attribute stream name.
@export var out_neighbor_count : String = "neighbor_count":
	set(value):
		out_neighbor_count = value.strip_edges()
		emit_changed()

## If enabled, writes distance to centroid.
@export var write_distance_to_center : bool = true:
	set(value):
		write_distance_to_center = value
		emit_changed()
## Output centroid distance attribute stream name.
@export var out_distance_to_center : String = "neighbor_distance_to_center":
	set(value):
		out_distance_to_center = value.strip_edges()
		emit_changed()

## If enabled, writes average centroid position.
@export var write_average_center : bool = true:
	set(value):
		write_average_center = value
		emit_changed()
## Output average centroid attribute stream name.
@export var out_average_center : String = "neighbor_average_center":
	set(value):
		out_average_center = value.strip_edges()
		emit_changed()

## If enabled, writes average neighbor density.
@export var write_average_density : bool = true:
	set(value):
		write_average_density = value
		emit_changed()
## Output average density attribute stream name.
@export var out_average_density : String = "neighbor_average_density":
	set(value):
		out_average_density = value.strip_edges()
		emit_changed()

## If enabled, writes average neighbor color.
@export var write_average_color : bool = true:
	set(value):
		write_average_color = value
		emit_changed()
## Output average color attribute stream name.
@export var out_average_color : String = "neighbor_average_color":
	set(value):
		out_average_color = value.strip_edges()
		emit_changed()

func _init():
	super._init()
	resource_name = "Point Neighborhood Settings"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "density_attribute", "port": 0 },
		{ "prop": "color_attribute", "port": 0 },
	]
