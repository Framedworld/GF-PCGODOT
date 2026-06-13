@tool
class_name TransformNodeSettings
extends NodeSettings

@export_group("Transform")

## Offset applied to offset min before writing final output values.
@export var offset_min := Vector3(0,0,0)
## Offset applied to offset max before writing final output values.
@export var offset_max := Vector3(0,0,0)
## Rotation value/attribute used when orienting generated instances or points.
@export var rotation_min := Vector3(0,0,0)
## Rotation value/attribute used when orienting generated instances or points.
@export var rotation_max := Vector3(0,0,0)
## Rotation value/attribute used when orienting generated instances or points.
@export var rotation_local_space := false
## Scale factor used to adjust scale min.
@export var scale_min := Vector3(1,1,1)
## Scale factor used to adjust scale max.
@export var scale_max := Vector3(1,1,1)
## Scale factor used to adjust uniform scale.
@export var uniform_scale := true

func _init():
	super._init()
	resource_name = "Transform Settings"
