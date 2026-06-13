@tool
class_name RayCastNodeSettings
extends NodeSettings

@export_group("RayCast")

enum eDirectionMode {
	Constant,
	FromAttribute,
}

## Ray direction vector before optional normalization.
@export var dir : Vector3 = Vector3.DOWN
## Upper bound used by this node for distance.
@export var max_distance : float = 1e3
## Selects this node behavior mode (Constant, FromAttribute).
@export var direction_mode : eDirectionMode = eDirectionMode.Constant:
	set(value):
		value = clampi(value, 0, eDirectionMode.size() - 1)
		if direction_mode != value:
			direction_mode = value
			notify_property_list_changed()
## Attribute name used to read/write direction on point data.
@export var direction_attribute : String = "direction":
	set(value):
		direction_attribute = value.strip_edges()
		emit_changed()
## Attribute name used to read/write distance on point data.
@export var distance_attribute : String = "":
	set(value):
		distance_attribute = value.strip_edges()
		emit_changed()
## Normalizes ray direction so ray length is controlled only by distance settings.
@export var normalize_direction : bool = true

## Attribute name that provides ray origin positions for each input point.
@export var from_attribute : String = "position"

@export_group("Collision")
## Physics collision mask used for overlap/raycast/sweep queries.
@export var collision_mask : int = 1
## Includes physics bodies in the query results.
@export var collide_with_bodies : bool = true
## Includes Area nodes in the query results.
@export var collide_with_areas : bool = false
## Allows hits when the ray starts inside a collider volume.
@export var hit_from_inside : bool = false
## When enabled, removes nodes group from candidates considered by this node.
@export var exclude_nodes_group : String = ""

@export_group("Outputs")
## Output attribute name that stores result produced by this node.
@export var out_result_attribute : String = "hit"
## Output attribute name that stores position produced by this node.
@export var out_position_attribute : String = "position"
## Output attribute name that stores rotation produced by this node.
@export var out_rotation_attribute : String = "rotation"
## Output attribute name that stores normal produced by this node.
@export var out_normal_attribute : String = ""
## Output attribute name that stores distance produced by this node.
@export var out_distance_attribute : String = ""
## Output attribute name that stores collider produced by this node.
@export var out_collider_attribute : String = ""

func _init():
	super._init()
	resource_name = "RayCast Settings"

func exposeParam(name : String) -> bool:
	if name == "direction_attribute":
		return direction_mode == eDirectionMode.FromAttribute
	return true
