@tool
extends NodeSettings

@export_group("Physics Overlap Query")

enum eShapeType {
	Sphere,
	Box,
}

## Selects this node behavior mode (Sphere, Box).
@export var shape_type : eShapeType = eShapeType.Sphere:
	set(value):
		value = clampi(value, 0, eShapeType.size() - 1)
		if shape_type != value:
			shape_type = value
			notify_property_list_changed()

## Radius used when sampling/querying neighbors around each point.
@export var radius : float = 1.0
## Half-size of the box shape used by overlap/sweep physics queries.
@export var half_extents : Vector3 = Vector3.ONE
## Toggles whether this node uses point size for shape instead of default behavior.
@export var use_point_size_for_shape : bool = false
## Attribute name used to read/write position on point data.
@export var position_attribute : String = "position"

@export_group("Collision")
## Physics collision mask used for overlap/raycast/sweep queries.
@export var collision_mask : int = 1
## Includes physics bodies in the query results.
@export var collide_with_bodies : bool = true
## Includes Area nodes in the query results.
@export var collide_with_areas : bool = false
## Upper bound used by this node for results.
@export var max_results : int = 8
## When enabled, removes nodes group from candidates considered by this node.
@export var exclude_nodes_group : String = ""

@export_group("Outputs")
## Output attribute name that stores hit produced by this node.
@export var out_hit_attribute : String = "overlap_hit"
## Output attribute name that stores count produced by this node.
@export var out_count_attribute : String = "overlap_count"
## Output attribute name that stores first collider produced by this node.
@export var out_first_collider_attribute : String = ""

func _init():
	super._init()
	resource_name = "Physics Overlap Query Settings"

func exposeParam(name : String) -> bool:
	if name == "radius":
		return shape_type == eShapeType.Sphere and not use_point_size_for_shape
	if name == "half_extents":
		return shape_type == eShapeType.Box and not use_point_size_for_shape
	return true
