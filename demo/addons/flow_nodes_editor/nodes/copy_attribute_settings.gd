@tool
extends NodeSettings

@export_group("Copy Attribute")

enum eMode {
	## Target point i gets source entry i. Counts must match, or the source has one entry (broadcast).
	ByIndex,
	## Target point gets the value of the first source entry whose match attribute equals its own.
	ByMatchAttribute,
	## Target point gets the value of the nearest source point (by position).
	NearestPoint,
}

@export var mode : eMode = eMode.ByIndex:
	set(value):
		if mode != value:
			mode = value
			notify_property_list_changed()
## Source attribute to copy.
@export var source_attribute : String = "@last"
## Target attribute to write; "@Source" (or empty) keeps the source name.
@export var target_attribute : String = "@Source"
## Copy every attribute of the source instead of source_attribute (point transform
## streams position, rotation, rotation_quat, size, bounds are skipped unless
## include_point_properties is on).
@export var copy_all_attributes : bool = false:
	set(value):
		if copy_all_attributes != value:
			copy_all_attributes = value
			notify_property_list_changed()
## With copy_all_attributes, also copy position, rotation, rotation_quat, size, bounds_min, bounds_max, steepness.
@export var include_point_properties : bool = false
## Key attribute on the source (ByMatchAttribute).
@export var match_attribute : String = "id"
## Key attribute on the target; "@Source" (or empty) uses match_attribute.
@export var target_match_attribute : String = "@Source"
## NearestPoint: sources farther than this are ignored (0 = no limit).
@export var max_distance : float = 0.0
## Optional Bool attribute set to true on target points that found a source.
@export var out_matched_attribute : String = ""

func _init():
	super._init()
	resource_name = "Copy Attribute"

func exposeParam( name : String ) -> bool:
	match name:
		"source_attribute", "target_attribute":
			return not copy_all_attributes
		"include_point_properties":
			return copy_all_attributes
		"match_attribute", "target_match_attribute":
			return mode == eMode.ByMatchAttribute
		"max_distance":
			return mode == eMode.NearestPoint
	return true

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [ { "prop": "source_attribute", "port": 1 }, { "prop": "match_attribute", "port": 1 } ]
