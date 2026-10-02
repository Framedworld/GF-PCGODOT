@tool
class_name CullPointsOutsideBoundsNodeSettings
extends NodeSettings

@export_group("Cull Points Outside Bounds")

## Test each point's bounds box (position + bounds_min/bounds_max, else
## +/- size / 2) for overlap with the cell instead of its position. A point
## that straddles a cell edge is then kept by every cell it overlaps.
@export var use_point_bounds : bool = false
## Grows the cell bounds on every side before the test (UE Bounds Expansion).
## Negative values shrink them.
@export var margin : float = 0.0

func _init():
	super._init()
	resource_name = "Cull Points Outside Bounds Settings"
