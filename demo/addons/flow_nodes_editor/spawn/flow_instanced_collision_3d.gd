@tool
class_name FlowInstancedCollision3D
extends StaticBody3D

## Shared collision body for one MultiMesh of a spawner: ONE node, with one
## shape owner per instance, all sharing the same Shape3D resource. Godot shape
## owners are not serialised, so the body keeps `shape` and
## `instance_transforms` as exported properties and rebuilds its shape owners
## whenever either changes (including when a saved scene is loaded), which keeps
## content baked into a scene by the editor colliding at runtime.
##
## A physics query that hits this body reports a shape index; the instance is
## `shape_owner_index(shape_find_owner(shape_idx))`, which equals the MultiMesh
## instance index.

## Shape shared by every instance.
@export var shape : Shape3D:
	set(value):
		shape = value
		_rebuild()

## One transform per instance, in this body's space (shape offsets included).
@export var instance_transforms : Array[Transform3D] = []:
	set(value):
		instance_transforms = value
		_rebuild()

## Owner id of the shape owner created for each instance, in instance order.
var _owner_ids : PackedInt32Array = PackedInt32Array()

## Number of instances that currently have a shape owner.
func instance_shape_count() -> int:
	return _owner_ids.size()

## Instance index of shape owner `owner_id` (as returned by shape_find_owner), or -1.
func shape_owner_index( owner_id : int ) -> int:
	return _owner_ids.find( owner_id )

## Replace shape and transforms in one rebuild.
func setup( new_shape : Shape3D, transforms : Array[Transform3D] ) -> void:
	shape = null
	instance_transforms = transforms
	shape = new_shape

func _rebuild() -> void:
	for owner_id in get_shape_owners():
		remove_shape_owner( owner_id )
	_owner_ids = PackedInt32Array()
	if shape == null:
		return
	_owner_ids.resize( instance_transforms.size() )
	for i in range( instance_transforms.size() ):
		var owner_id := create_shape_owner( self )
		shape_owner_add_shape( owner_id, shape )
		shape_owner_set_transform( owner_id, instance_transforms[i] )
		_owner_ids[i] = owner_id
