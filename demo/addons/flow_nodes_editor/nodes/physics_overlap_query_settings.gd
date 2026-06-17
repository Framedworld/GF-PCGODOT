@tool
extends NodeSettings

@export_group("Physics Overlap Query")

enum eShapeType {
	## Sphere collision shape query.
	Sphere,
	## Box collision shape query.
	Box,
}

## The collision shape type to use for the physics query.
@export var shape_type : eShapeType = eShapeType.Sphere:
	set(value):
		value = clampi(value, 0, eShapeType.size() - 1)
		if shape_type != value:
			shape_type = value
			notify_property_list_changed()

## Radius of the query sphere. Clamped to a minimum of 0.0001.
## Only used when 'shape_type' is Sphere and 'use_point_size_for_shape' is disabled.
@export var radius : float = 1.0
## Half-size dimensions of the query box. Clamped to a minimum size of 0.0001.
## Only used when 'shape_type' is Box and 'use_point_size_for_shape' is disabled.
@export var half_extents : Vector3 = Vector3.ONE
## If enabled, uses each point's size attribute as the shape's bounds instead of 'radius' or 'half_extents'.
## Spheres use the maximum scale component as diameter; boxes match the point's scale size directly.
@export var use_point_size_for_shape : bool = false
## The name of the input Vector stream representing the query positions.
@export var position_attribute : String = "position"

@export_group("Collision")
## The physics collision mask layers to query.
@export var collision_mask : int = 1
## If enabled, collides with PhysicsBody3D nodes.
@export var collide_with_bodies : bool = true
## If enabled, collides with Area3D nodes.
@export var collide_with_areas : bool = false
## The maximum number of overlapping colliders to return per point.
@export var max_results : int = 8
## Optional name of a scene group. CollisionObject3D nodes in this group are excluded from collision results.
@export var exclude_nodes_group : String = ""

@export_group("Outputs")
## The output attribute name (Bool) to store hit results (1 for overlap, 0 otherwise).
## If left blank or empty, this stream is not registered.
@export var out_hit_attribute : String = "overlap_hit"
## The output attribute name (Int) to store the count of overlapping colliders (capped at 'max_results').
## If left blank or empty, this stream is not registered.
@export var out_count_attribute : String = "overlap_count"
## The output attribute name (NodePath) to store a reference to the first collider node found.
## If left blank or empty, this stream is not registered.

func _init():
	super._init()
	resource_name = "Physics Overlap Query Settings"

func exposeParam(name : String) -> bool:
	if name == "radius":
		return shape_type == eShapeType.Sphere and not use_point_size_for_shape
	if name == "half_extents":
		return shape_type == eShapeType.Box and not use_point_size_for_shape
	return true
