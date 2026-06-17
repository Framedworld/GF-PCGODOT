@tool
class_name ProjectionNodeSettings
extends NodeSettings

@export_group("Projection")

## The projection raycast direction Vector3.
@export var direction : Vector3 = Vector3(0, -1, 0):
	set(value):
		direction = value
		emit_changed()

## Physics collision layers checked during projection.
@export_flags_3d_physics var collision_mask : int = 1:
	set(value):
		collision_mask = value
		emit_changed()

## If enabled, aligns projected points to hit normals.
@export var align_to_normal : bool = true:
	set(value):
		align_to_normal = value
		emit_changed()

## If enabled, clips points that do not hit any projection target.
@export var discard_misses : bool = false:
	set(value):
		discard_misses = value
		emit_changed()

## The maximum distance projection raycasts will travel.
@export var ray_length : float = 1000.0:
	set(value):
		ray_length = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Projection Settings"
