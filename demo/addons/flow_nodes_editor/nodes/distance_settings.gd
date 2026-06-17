@tool
class_name DistanceNodeSettings
extends NodeSettings

@export_group("Distance")

## The maximum distance threshold for matching or measuring between points. If set to 0.0, no distance limit is enforced.
@export var max_distance : float = 0.0

var HiddenFromThisPoint := true
## The name of the float attribute stream in which to write the computed distance.
@export var out_name : String = "distance"
## The vector attribute stream name on Input A to measure distance from (defaults to 'position').
@export var in_nameA : String = FlowData.AttrPosition
## The vector attribute stream name on Input B to measure distance to (defaults to 'position').
@export var in_nameB : String = FlowData.AttrPosition

func _init():
	super._init()
	resource_name = "Distance Settings"
