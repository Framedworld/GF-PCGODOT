@tool
class_name ApplyScaleToBoundsNodeSettings
extends NodeSettings

@export_group("Apply Scale To Bounds")

## Reset the per-point scale (the `size` stream) to (1, 1, 1) after baking it
## into the bounds. Unreal always resets it; turn this off only to keep the
## scale for spawning while still writing the scaled bounds.
@export var reset_scale : bool = true

func _init():
	super._init()
	resource_name = "Apply Scale To Bounds Settings"
