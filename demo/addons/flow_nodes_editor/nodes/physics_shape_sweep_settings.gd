@tool
extends NodeSettings

@export_group("Physics Shape Sweep")

enum eShapeType {
	Sphere,
	Box,
}

enum eDirectionMode {
	Constant,
	FromAttribute,
}

## Selects this node behavior mode (Sphere, Box).
@export var shape_type : eShapeType = eShapeType.Sphere:
	set(value):
		value = clampi(value, 0, eShapeType.size() - 1)
		shape_type = value
		notify_property_list_changed()

## Radius used when sampling/querying neighbors around each point.
@export var radius : float = 0.5
## Half-size of the box shape used by overlap/sweep physics queries.
@export var half_extents : Vector3 = Vector3.ONE
## Toggles whether this node uses point size for shape instead of default behavior.
@export var use_point_size_for_shape : bool = false
## Attribute name used to read/write position on point data.
@export var position_attribute : String = "position"
## Selects this node behavior mode (Constant, FromAttribute).
@export var direction_mode : eDirectionMode = eDirectionMode.Constant:
	set(value):
		value = clampi(value, 0, eDirectionMode.size() - 1)
		direction_mode = value
		notify_property_list_changed()
## Direction vector used for casts, projections, or sweeps.
@export var direction : Vector3 = Vector3.FORWARD
## Attribute name used to read/write direction on point data.
@export var direction_attribute : String = "direction"
## Distance value used by this node for distance.
@export var distance : float = 10.0
## Attribute name used to read/write distance on point data.
@export var distance_attribute : String = ""

@export_group("Collision")
## Physics collision mask used for overlap/raycast/sweep queries.
@export var collision_mask : int = 1
## Includes physics bodies in the query results.
@export var collide_with_bodies : bool = true
## Includes Area nodes in the query results.
@export var collide_with_areas : bool = false
## When enabled, removes nodes group from candidates considered by this node.
@export var exclude_nodes_group : String = ""

@export_group("Outputs")
## Output attribute name that stores hit produced by this node.
@export var out_hit_attribute : String = "sweep_hit"
## Output attribute name that stores position produced by this node.
@export var out_position_attribute : String = "position"
## Output attribute name that stores safe fraction produced by this node.
@export var out_safe_fraction_attribute : String = "sweep_safe_fraction"
## Output attribute name that stores unsafe fraction produced by this node.
@export var out_unsafe_fraction_attribute : String = "sweep_unsafe_fraction"
## Output attribute name that stores collider produced by this node.
@export var out_collider_attribute : String = ""

func _init():
	super._init()
	resource_name = "Physics Shape Sweep Settings"

func exposeParam(name : String) -> bool:
	if name == "radius":
		return shape_type == eShapeType.Sphere and not use_point_size_for_shape
	if name == "half_extents":
		return shape_type == eShapeType.Box and not use_point_size_for_shape
	if name == "direction_attribute":
		return direction_mode == eDirectionMode.FromAttribute
	return true
