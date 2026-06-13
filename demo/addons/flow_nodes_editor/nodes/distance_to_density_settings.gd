@tool
class_name DistanceToDensityNodeSettings
extends NodeSettings

@export_group("Distance to Density")

## World/local reference position from which distances are measured.
@export var reference_position: Vector3 = Vector3.ZERO
## Lower bound used by this node for distance.
@export var min_distance: float = 0.0
## Upper bound used by this node for distance.
@export var max_distance: float = 10.0
## Lower bound used by this node for density.
@export var min_density: float = 0.0
## Upper bound used by this node for density.
@export var max_density: float = 1.0
## Inverts the computed normalized output mapping.
@export var invert: bool = false

func _init():
	super._init()
	resource_name = "Distance to Density Settings"
