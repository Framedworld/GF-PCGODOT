@tool
class_name DuplicatePointNodeSettings
extends NodeSettings

@export_group("Duplicate Point")

## Number of duplicate/processing iterations to run.
@export var iterations: int = 1
## Offset applied to offset before writing final output values.
@export var offset: Vector3 = Vector3(0, 1, 0)
## Offset applied to offset relative before writing final output values.
@export var offset_relative: bool = true

func _init():
	super._init()
	resource_name = "Duplicate Point Settings"
