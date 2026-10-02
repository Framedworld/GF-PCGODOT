@tool
class_name SurfaceSamplerNodeSettings
extends NodeSettings

@export_group("Surface Sampler")
## The number of points to sample across the surface area.
## Point inputs: points per input region. Surface data inputs: total points
## when shape_sampling is Count.
@export var num_points: int = 40
## Default scale size assigned to generated sample points.
@export var point_size: Vector3 = Vector3.ONE

# --- Surface data inputs (Data.shape). Point inputs ignore everything below,
# except use_bounding_shape. ---------------------------------------------------

enum eShapeSampling {
	## UE Surface Sampler: a world-anchored jittered grid of points_per_square_meter.
	PointsPerSquareMeter,
	## num_points random hits over the surface bounds.
	Count,
}

## Surface data inputs: grid density (UE) or a fixed count.
@export var shape_sampling : eShapeSampling = eShapeSampling.PointsPerSquareMeter
## Surface data inputs: candidate points per square meter on the XZ plane.
@export var points_per_square_meter : float = 0.1
## Surface data inputs: half extents of each point, written as its bounds.
@export var point_extents : Vector3 = Vector3.ONE
## Surface data inputs: 0 = regular grid, 1 = full jitter inside each cell.
@export_range(0.0, 1.0) var looseness : float = 1.0
## Surface data inputs: write the surface density (composites, soft volumes) to
## the points; off writes 1.0.
@export var apply_density_to_points : bool = true
## Surface data inputs: steepness written to the points (UE Point Steepness).
@export_range(0.0, 1.0) var point_steepness : float = 0.5
## Surface data inputs: keep candidates whose density is 0 (debugging).
@export var keep_zero_density_points : bool = false
## Surface data inputs: rotate points to the surface normal (Y up).
@export var align_to_normal : bool = false
## Adds a "Bounding Shape" input (UE parity): sampling is restricted to it
## (intersection). Accepts spatial data or points (their bounds boxes).
@export var use_bounding_shape : bool = false:
	set(value):
		use_bounding_shape = value
		emit_changed()
		notify_property_list_changed()
## Surface data inputs: safety cap on candidate cells.
@export var max_candidates : int = 4000000

func _init():
	super._init()
	resource_name = "Surface Sampler Settings"
