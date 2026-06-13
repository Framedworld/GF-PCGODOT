@tool
class_name RelaxNodeSettings
extends NodeSettings

@export_group("Relax")

## Number of relaxation iterations to run.
@export var num_iterations := 10
## Strength/intensity of the effect applied by this node.
@export var strength := 0.5
## Padding distance kept from borders while relaxing points.
@export var padding := 0.0

func _init():
	super._init()
	resource_name = "Relax Settings"
