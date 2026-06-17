@tool
extends NodeSettings

@export_group("Physics Shape Sweep")

enum eShapeType {
	## Sphere sweep collision shape.
	Sphere,
	## Box sweep collision shape.
	Box,
}

enum eDirectionMode {
	## Sweep along a constant direction vector.
	Constant,
	## Sweep along the vector direction read from a point attribute.
	FromAttribute,
}

## The sweep collision shape type to use for the physics query.
@export var shape_type : eShapeType = eShapeType.Sphere:
	set(value):
		value = clampi(value, 0, eShapeType.size() - 1)
		shape_type = value
		notify_property_list_changed()

## Radius of the sweep sphere. Clamped to a minimum of 0.0001.
## Only used when 'shape_type' is Sphere and 'use_point_size_for_shape' is disabled.
@export var radius : float = 0.5
## Half-size dimensions of the sweep box. Clamped to a minimum size of 0.0001.
## Only used when 'shape_type' is Box and 'use_point_size_for_shape' is disabled.
@export var half_extents : Vector3 = Vector3.ONE
## If enabled, uses each point's size attribute as the shape's bounds instead of 'radius' or 'half_extents'.
## Spheres use the maximum scale component as diameter; boxes match the point's scale size directly.
@export var use_point_size_for_shape : bool = false
## The name of the input Vector stream representing the query starting positions.
@export var position_attribute : String = "position"
## How the sweep direction vector is sourced.
@export var direction_mode : eDirectionMode = eDirectionMode.Constant:
	set(value):
		value = clampi(value, 0, eDirectionMode.size() - 1)
		direction_mode = value
		notify_property_list_changed()
## The constant sweep direction vector. Only used when 'direction_mode' is Constant.
@export var direction : Vector3 = Vector3.FORWARD
## The name of the input Vector stream containing the sweep direction vector.
## Only used when 'direction_mode' is FromAttribute.
@export var direction_attribute : String = "direction"
## The constant sweep distance. Only used when 'distance_attribute' is empty.
@export var distance : float = 10.0
## The name of the input Float or Int stream containing the sweep distance.
## If left blank or empty, the constant 'distance' is used instead.
@export var distance_attribute : String = ""

@export_group("Collision")
## The physics collision mask layers to query.
@export var collision_mask : int = 1
## If enabled, collides with PhysicsBody3D nodes.
@export var collide_with_bodies : bool = true
## If enabled, collides with Area3D nodes.
@export var collide_with_areas : bool = false
## Optional name of a scene group. CollisionObject3D nodes in this group are excluded from collision results.
@export var exclude_nodes_group : String = ""

@export_group("Outputs")
## The output attribute name (Bool) to store hit results (1 for hit, 0 otherwise).
## If left blank or empty, this stream is not registered.
@export var out_hit_attribute : String = "sweep_hit"
## The output attribute name (Vector3) to store the final position of the swept shape (position at impact, or end of sweep).
## If left blank or empty, this stream is not registered.
@export var out_position_attribute : String = "position"
## The output attribute name (Float) to store the safe fraction of the sweep (from 0.0 to 1.0, where 1.0 means no collision).
## If left blank or empty, this stream is not registered.
@export var out_safe_fraction_attribute : String = "sweep_safe_fraction"
## The output attribute name (Float) to store the unsafe fraction of the sweep (from 0.0 to 1.0, where less than 1.0 means collision).
## If left blank or empty, this stream is not registered.
@export var out_unsafe_fraction_attribute : String = "sweep_unsafe_fraction"
## The output attribute name (NodePath) to store a reference to the collider node hit.
## If left blank or empty, this stream is not registered.
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
