@tool
class_name DuplicatePointNodeSettings
extends NodeSettings

@export_group("Duplicate Point")

## The number of duplicate copies to create per input point.
@export var iterations: int = 1
## The offset vector applied to each duplicate iteration.
@export var offset: Vector3 = Vector3(0, 1, 0)
## If enabled, the offset vector is applied relative to the parent point's rotation/scale. If disabled, offset is in world space.
@export var offset_relative: bool = true

func _init():
	super._init()
	resource_name = "Duplicate Point Settings"
