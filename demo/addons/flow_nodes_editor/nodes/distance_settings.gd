@tool
class_name DistanceNodeSettings
extends NodeSettings

@export_group("Distance")

## Upper bound used by this node for distance.
@export var max_distance : float = 0.0

var HiddenFromThisPoint := true
## Name of the output attribute this node writes.
@export var out_name : String = "distance"
## Name of the first input attribute to read from.
@export var in_nameA : String = FlowData.AttrPosition
## Name of the second input attribute to read from.
@export var in_nameB : String = FlowData.AttrPosition

func _init():
	super._init()
	resource_name = "Distance Settings"
