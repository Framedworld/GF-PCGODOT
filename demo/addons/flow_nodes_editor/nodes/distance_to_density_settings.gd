@tool
class_name DistanceToDensityNodeSettings
extends NodeSettings

@export_group("Distance to Density")

## The reference Vector3 position in local/world space from which point distances are measured.
@export var reference_position: Vector3 = Vector3.ZERO
## The minimum distance threshold. Points closer than this will have the min_density value.
@export var min_distance: float = 0.0
## The maximum distance threshold. Points farther than this will have the max_density value.
@export var max_distance: float = 10.0
## The density value assigned to points at or closer than min_distance.
@export var min_density: float = 0.0
## The density value assigned to points at or farther than max_distance.
@export var max_density: float = 1.0
## If enabled, inverts the density mapping calculation (points closer get higher density, farther get lower).
@export var invert: bool = false

func _init():
	super._init()
	resource_name = "Distance to Density Settings"
