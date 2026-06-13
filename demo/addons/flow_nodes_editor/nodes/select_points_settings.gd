@tool
class_name SelectPointsNodeSettings
extends NodeSettings

@export_group("Select Points")

## Selection ratio (0..1) that determines what fraction of points is kept.
@export_range(0.0, 1.0) var ratio : float = 0.2
## Attribute used as sampling weight when selecting points.
@export var weight_name : String

func _init():
	super._init()
	resource_name = "Select Points Settings"
