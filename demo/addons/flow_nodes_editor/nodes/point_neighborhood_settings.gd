@tool
extends NodeSettings

@export_group("Point Neighborhood")
## Distance value used by this node for search distance.
@export var search_distance : float = 300.0:
	set(value):
		search_distance = maxf(0.0, value)
		emit_changed()
## When enabled, also outputs self alongside generated points/data.
@export var include_self : bool = false:
	set(value):
		include_self = value
		emit_changed()

@export_group("Neighborhood Source Attributes")
## Attribute name used to read/write density on point data.
@export var density_attribute : String = "density":
	set(value):
		density_attribute = value.strip_edges()
		emit_changed()
## Attribute name used to read/write color on point data.
@export var color_attribute : String = "color":
	set(value):
		color_attribute = value.strip_edges()
		emit_changed()

@export_group("Outputs")
## When enabled, computes and writes neighbor count to output attributes.
@export var write_neighbor_count : bool = true:
	set(value):
		write_neighbor_count = value
		emit_changed()
## Output value/attribute key used for neighbor count.
@export var out_neighbor_count : String = "neighbor_count":
	set(value):
		out_neighbor_count = value.strip_edges()
		emit_changed()

## When enabled, computes and writes distance to center to output attributes.
@export var write_distance_to_center : bool = true:
	set(value):
		write_distance_to_center = value
		emit_changed()
## Output value/attribute key used for distance to center.
@export var out_distance_to_center : String = "neighbor_distance_to_center":
	set(value):
		out_distance_to_center = value.strip_edges()
		emit_changed()

## When enabled, computes and writes average center to output attributes.
@export var write_average_center : bool = true:
	set(value):
		write_average_center = value
		emit_changed()
## Output value/attribute key used for average center.
@export var out_average_center : String = "neighbor_average_center":
	set(value):
		out_average_center = value.strip_edges()
		emit_changed()

## When enabled, computes and writes average density to output attributes.
@export var write_average_density : bool = true:
	set(value):
		write_average_density = value
		emit_changed()
## Output value/attribute key used for average density.
@export var out_average_density : String = "neighbor_average_density":
	set(value):
		out_average_density = value.strip_edges()
		emit_changed()

## When enabled, computes and writes average color to output attributes.
@export var write_average_color : bool = true:
	set(value):
		write_average_color = value
		emit_changed()
## Output value/attribute key used for average color.
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
