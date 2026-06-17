@tool
class_name SamplePointsNodeSettings
extends NodeSettings

@export_group("Sample Points")

enum eDistribution {
	## Generates points on a regular grid pattern.
	UniformGrid,
	## Generates points using a stable 2D Halton sequence.
	QuasiRandom2D,
	## Generates points using a stable 3D Halton sequence.
	QuasiRandom3D,
	## Generates points using a 2D blue noise distribution.
	BlueNoise2D,
}

## The point distribution algorithm used to subdivide each input point.
@export var distribution : eDistribution = eDistribution.QuasiRandom2D:
	set(value):
		if distribution != value:
			distribution = value
			# This triggers the refresh of the property list in the property editor
			notify_property_list_changed()

# Uniform sampling
## The spacing distance (in world units) between adjacent points in the uniform grid.
## Used in 'UniformGrid' mode to compute the grid resolution along each axis.
@export var sampling_distance : float = 0.2
## The maximum number of points to generate along the X axis for the uniform grid.
@export var max_x : int = 32
## The maximum number of points to generate along the Y axis for the uniform grid.
@export var max_y : int = 32
## The maximum number of points to generate along the Z axis for the uniform grid.
@export var max_z : int = 32
## Scale multiplier applied to the size of the generated grid points in 'UniformGrid' mode.
## The output size is calculated as: Vector3.ONE * sampling_distance * new_size_factor.
@export var new_size_factor : float = 1.0

# Non-Uniform sampling
## The offset phase or seed value (typically between 0.0 and 1.0) used as a base offset
## for the quasi-random sequence.
@export var phase : float = 0.0
## The base scale/size assigned to the sample points in quasi-random and blue noise modes.
## In QuasiRandom mode, sets a uniform scale (Vector3.ONE * size). In BlueNoise2D mode,
## scales the output relative to the input point's size.
@export var size : float = 1.0
## The name of the custom integer attribute stream to store group IDs.
## If left blank, group IDs are not saved. Only used in QuasiRandom modes.
@export var out_group_id : String
## An array of integers defining the number of points to generate for each group/class.
## The total points generated per input point is the sum of these values. Only used in QuasiRandom modes.
@export var groups : Array[int] = [ 32 ]

## The target number of points to generate when using the 'BlueNoise2D' distribution.
## Note: Some points might be skipped if they lie outside the bounds of the input point size.
@export var num_samples : int = 64

func _init():
	super._init()
	resource_name = "Sample Points Settings"

func isUniformGridParam( name : String ) -> bool:
	return name.begins_with( "max_" ) or name == "sampling_distance" or name == "new_size_factor"

func isQuasiRandomParam( name : String ) -> bool:
	return name == "phase" or name == "size" or name == "out_group_id" or name == "groups"

func isBlueNoiseParam( name : String ) -> bool:
	return name == "num_samples" or name == "size"

# This control if the param is visible in the property inspector
func exposeParam( name : String ) -> bool:
	# This must return true except for the specific parameters that depend on the enum
	if distribution == eDistribution.UniformGrid:
		return not isQuasiRandomParam( name )
	if distribution == eDistribution.BlueNoise2D:
		return isBlueNoiseParam( name ) or (not isQuasiRandomParam( name ) and not isUniformGridParam( name ))
	return not isUniformGridParam( name )
