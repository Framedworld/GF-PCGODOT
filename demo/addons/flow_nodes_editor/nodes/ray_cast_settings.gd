@tool
class_name RayCastNodeSettings
extends NodeSettings

@export_group("RayCast")

enum eDirectionMode {
	## Sweep along a constant direction vector.
	Constant,
	## Sweep along the vector direction read from a point attribute.
	FromAttribute,
}

## The constant raycast direction Vector3.
@export var dir : Vector3 = Vector3.DOWN
## The maximum distance raycasts will travel.
@export var max_distance : float = 1e3
## Raycast direction source: Constant or FromAttribute.
@export var direction_mode : eDirectionMode = eDirectionMode.Constant:
	set(value):
		value = clampi(value, 0, eDirectionMode.size() - 1)
		if direction_mode != value:
			direction_mode = value
			notify_property_list_changed()
## Direction attribute stream name.
@export var direction_attribute : String = "direction":
	set(value):
		direction_attribute = value.strip_edges()
		emit_changed()
## Distance attribute stream name.
@export var distance_attribute : String = "":
	set(value):
		distance_attribute = value.strip_edges()
		emit_changed()
## If enabled, normalizes direction vector before casting.
@export var normalize_direction : bool = true

## Position offset attribute name to start raycast from.
@export var from_attribute : String = "position"

@export_group("Collision")
## Physics collision layers checked.
@export var collision_mask : int = 1
## If enabled, collides with PhysicsBody3D.
@export var collide_with_bodies : bool = true
## If enabled, collides with Area3D.
@export var collide_with_areas : bool = false
## If enabled, detects overlaps starting inside collision shapes.
@export var hit_from_inside : bool = false
## Optional group name to exclude from collision.
@export var exclude_nodes_group : String = ""

@export_group("Outputs")
## Output hit boolean attribute stream name.
@export var out_result_attribute : String = "hit"
## Output hit position attribute stream name.
@export var out_position_attribute : String = "position"
## Output hit normal rotation attribute stream name.
@export var out_rotation_attribute : String = "rotation"
## Output hit normal vector attribute stream name.
@export var out_normal_attribute : String = ""
## Output hit distance attribute stream name.
@export var out_distance_attribute : String = ""
## Output hit collider reference attribute stream name.
@export var out_collider_attribute : String = ""

func _init():
	super._init()
	resource_name = "RayCast Settings"

func exposeParam(name : String) -> bool:
	if name == "direction_attribute":
		return direction_mode == eDirectionMode.FromAttribute
	return true
