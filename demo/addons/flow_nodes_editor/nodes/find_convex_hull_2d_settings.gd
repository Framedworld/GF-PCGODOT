@tool
class_name FindConvexHull2DNodeSettings
extends NodeSettings

@export_group("Find Convex Hull 2D")

## Int attribute receiving each hull point's position along the hull
## (0, 1, 2, ... counter-clockwise in the X/Z plane), ready to drive a closed
## spline. Empty disables it.
@export var order_attribute : String = "hull_index"
## Keep points that lie exactly on a hull edge (collinear with its ends).
## Off keeps only the corners, like Unreal.
@export var include_collinear : bool = false
## Append the first hull point again at the end, closing the loop for
## consumers that expect an explicitly closed polyline. Its order value is
## the hull point count.
@export var repeat_first_point : bool = false

func _init():
	super._init()
	resource_name = "Find Convex Hull 2D Settings"
