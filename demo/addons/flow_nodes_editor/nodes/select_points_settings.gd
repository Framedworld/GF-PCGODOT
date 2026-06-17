@tool
class_name SelectPointsNodeSettings
extends NodeSettings

@export_group("Select Points")

## Probability ratio (0.0 to 1.0) of selecting each point.
@export_range(0.0, 1.0) var ratio : float = 0.2
## Optional attribute stream name used to scale selection weight probability.
@export var weight_name : String

func _init():
	super._init()
	resource_name = "Select Points Settings"
