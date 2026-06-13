@tool
class_name SampleSplineNodeSettings
extends NodeSettings

@export_group("Sample Spline")

enum eSamplingMode {
	Uniform = 0,
	Random = 1,
}

enum eFillMode {
	Grid = 0,
	Random = 1,
	Poisson = 2,
}

## Chooses edge sampling strategy along the spline (Uniform, Random).
@export var sampling_mode : eSamplingMode = eSamplingMode.Uniform:
	set( new_value ):
		sampling_mode = new_value
		notify_property_list_changed()

## Distance between generated samples along the spline when using uniform/grid spacing modes.
@export var uniform_interval : float = 0.2
## If enabled, fills the area enclosed by the spline; if disabled, only samples along the spline path itself.
@export var fill_curve : bool = false:
	set( new_value ):
		fill_curve = new_value
		notify_property_list_changed()
		
## Chooses how interior points are generated inside the spline area (Grid, Random, Poisson).
@export var fill_mode : eFillMode = eFillMode.Grid:
	set( new_value ):
		fill_mode = new_value
		notify_property_list_changed()

## Snaps/adjusts generated border samples so fill/sampling aligns to the spline boundary extents.
@export var adjust_to_borders : bool = true
## When enabled, samples one point at each spline segment center instead of using interval-based stepping along the curve.
@export var sample_segments_centers : bool = false
## Attribute name used to read/write distance on point data.
@export var distance_attribute : String = "distance"
## Number of points to generate when random sampling is selected.
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
