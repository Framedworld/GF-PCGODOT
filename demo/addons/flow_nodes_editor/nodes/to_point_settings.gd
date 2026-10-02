@tool
extends NodeSettings

@export_group("To Point")

## Splines: distance between samples along the curve.
@export var spline_interval : float = 1.0
## Surfaces: candidate density on the XZ plane (UE Points Per Squared Meter).
@export var points_per_square_meter : float = 0.1
## Surfaces: half extents of each point, written as its bounds.
@export var point_extents : Vector3 = Vector3.ONE
## Surfaces: 0 = regular grid, 1 = full jitter inside each cell.
@export_range( 0.0, 1.0 ) var looseness : float = 1.0
## Surfaces: steepness written to the output points (UE Point Steepness).
@export_range( 0.0, 1.0 ) var point_steepness : float = 0.5
## Volumes: size of the voxel grid (one candidate per voxel centre).
@export var voxel_size : Vector3 = Vector3.ONE
## Write the shape's density at each point (off: density 1).
@export var apply_density : bool = true
## Keep candidates whose density is 0 (debugging).
@export var keep_zero_density : bool = false
## Safety cap on candidate cells / voxels.
@export var max_candidates : int = 4000000

func _init():
	super._init()
	resource_name = "To Point Settings"
