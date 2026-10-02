@tool
class_name ResetPointCenterNodeSettings
extends NodeSettings

@export_group("Reset Point Center")

## New pivot of each point, as a normalized location inside its bounds box:
## (0, 0, 0) is the bounds min corner, (1, 1, 1) the max corner and
## (0.5, 0.5, 0.5) the box center. The world box does not move.
@export var point_center_location : Vector3 = Vector3( 0.5, 0.5, 0.5 )

func _init():
	super._init()
	resource_name = "Reset Point Center Settings"
