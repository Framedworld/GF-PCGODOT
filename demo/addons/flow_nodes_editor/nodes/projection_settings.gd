@tool
class_name ProjectionNodeSettings
extends NodeSettings

@export_group("Projection")

## Direction vector used for casts, projections, or sweeps.
@export var direction : Vector3 = Vector3(0, -1, 0):
	set(value):
		direction = value
		emit_changed()

## Physics collision mask used for overlap/raycast/sweep queries.
@export_flags_3d_physics var collision_mask : int = 1:
	set(value):
		collision_mask = value
		emit_changed()

## If enabled, aligns output rotation to the hit/projected surface normal.
@export var align_to_normal : bool = true:
	set(value):
		align_to_normal = value
		emit_changed()

## When enabled, rejects misses from the generated/processed output.
@export var discard_misses : bool = false:
	set(value):
		discard_misses = value
		emit_changed()

## Maximum projection/cast distance.
@export var ray_length : float = 1000.0:
	set(value):
		ray_length = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Projection Settings"
