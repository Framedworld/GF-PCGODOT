@tool
class_name TransformNodeSettings
extends NodeSettings

@export_group("Transform")

## Minimum random translation offset Vector3.
@export var offset_min := Vector3(0,0,0)
## Maximum random translation offset Vector3.
@export var offset_max := Vector3(0,0,0)
## Minimum random Euler rotation offset Vector3.
@export var rotation_min := Vector3(0,0,0)
## Maximum random Euler rotation offset Vector3.
@export var rotation_max := Vector3(0,0,0)
## If enabled, rotation is applied in local point space. If disabled, in world space.
@export var rotation_local_space := false
## Minimum random scale/size multiplier Vector3.
@export var scale_min := Vector3(1,1,1)
## Maximum random scale/size multiplier Vector3.
@export var scale_max := Vector3(1,1,1)
## If enabled, applies scale multiplier uniformly across X, Y, and Z.
@export var uniform_scale := true

func _init():
	super._init()
	resource_name = "Transform Settings"
