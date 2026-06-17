@tool
class_name SampleSplineNodeSettings
extends NodeSettings

@export_group("Sample Spline")

enum eSamplingMode {
	## Distributes points at regular intervals along the spline's length.
	Uniform = 0,
	## Places a specified number of points at random locations along the spline.
	Random = 1,
}

enum eFillMode {
	## Generates points on a regular grid pattern with spacing defined by [member uniform_interval].
	Grid = 0,
	## Places a specified number of points ([member num_random_samples]) at random locations within the boundary.
	Random = 1,
	## Distributes points randomly but evenly, maintaining a minimum distance defined by [member uniform_interval] between them.
	Poisson = 2,
}

## Chooses the edge sampling strategy along the spline path when [member fill_curve] is disabled.
@export var sampling_mode : eSamplingMode = eSamplingMode.Uniform:
	set( new_value ):
		sampling_mode = new_value
		notify_property_list_changed()

## The distance or spacing interval used for point generation (minimum allowed value is 0.1).[br]
## - When sampling uniformly along the spline path, this is the distance between adjacent points.[br]
## - When filling the curve area in Grid mode, this is the spacing between grid points.[br]
## - When filling the curve area in Poisson mode, this defines the minimum allowed distance between any two generated points.
@export var uniform_interval : float = 0.2
## If enabled, treats the spline as a closed loop and fills the enclosed 2D area (projected on the XZ plane) with points.[br]
## If disabled, samples points only along the path of the spline itself.
@export var fill_curve : bool = false:
	set( new_value ):
		fill_curve = new_value
		notify_property_list_changed()

## Chooses the pattern used to generate interior points inside the spline area when [member fill_curve] is enabled.
@export var fill_mode : eFillMode = eFillMode.Grid:
	set( new_value ):
		fill_mode = new_value
		notify_property_list_changed()

## Only applies when sampling uniformly along the spline path (i.e. [member fill_curve] is disabled and [member sampling_mode] is Uniform).[br]
## If enabled, uses Godot's built-in baked points, ensuring samples align exactly with the curve's start and end points.[br]
## If disabled, samples are strictly spaced by [member uniform_interval] along the length, which may not align with the endpoints.
@export var adjust_to_borders : bool = true
## Only applies when sampling uniformly along the spline path.[br]
## If enabled, places exactly one point at the midpoint of each baked curve segment rather than at segment endpoints.[br]
## The generated points are oriented to look along the segment direction, and their Z-scale is adjusted to match the segment's length.
@export var sample_segments_centers : bool = false
## Only applies when [member fill_curve] is enabled.[br]
## If set to a non-empty name, calculates the shortest distance from each generated interior point to the spline boundary[br]
## using a KDTree lookup, and stores the distance value in a float attribute stream with this name.
@export var distance_attribute : String = "distance"
## The number of points to generate when random sampling is active.[br]
## Used when [member sampling_mode] is Random (points along path) or when [member fill_curve] is enabled and [member fill_mode] is Random (points inside area).
@export var num_random_samples : int = 10

func _init():
	super._init()
	resource_name = "Sample Spline Settings"

func exposeParam( name : String ) -> bool:
	if name == "num_random_samples":
		return sampling_mode == eSamplingMode.Random or (fill_curve and fill_mode == eFillMode.Random)
	if name == "fill_mode":
		return fill_curve
	if name == "sample_segments_centers":
		return not fill_curve
	if name == "uniform_interval":
		return sampling_mode == eSamplingMode.Uniform or (fill_curve and fill_mode != eFillMode.Random)
	return true
