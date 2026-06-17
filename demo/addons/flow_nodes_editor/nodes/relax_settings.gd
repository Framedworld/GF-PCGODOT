@tool
class_name RelaxNodeSettings
extends NodeSettings

@export_group("Relax")

## Number of relaxing iterations to execute.
@export var num_iterations := 10
## relaxing strength multiplier applied per pass.
@export var strength := 0.5
## Minimum spacing distance enforced between points.
@export var padding := 0.0

func _init():
	super._init()
	resource_name = "Relax Settings"
