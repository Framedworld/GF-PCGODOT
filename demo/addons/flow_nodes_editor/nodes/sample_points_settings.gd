@tool
class_name SamplePointsNodeSettings
extends NodeSettings

@export_group("Sample Points")

enum eDistribution {
	UniformGrid,
	QuasiRandom2D,
	QuasiRandom3D,
	BlueNoise2D,
}

## Selects this node behavior mode (UniformGrid, QuasiRandom2D, QuasiRandom3D, BlueNoise2D).
@export var distribution : eDistribution = eDistribution.QuasiRandom2D:
	set(value):
		if distribution != value:
			distribution = value
			# This triggers the refresh of the property list in the property editor
			notify_property_list_changed()
			
# Uniform sampling
## Distance value used by this node for sampling distance.
@export var sampling_distance : float = 0.2
## Upper bound used by this node for x.
@export var max_x : int = 32
## Upper bound used by this node for y.
@export var max_y : int = 32
## Upper bound used by this node for z.
@export var max_z : int = 32
## Size parameter controlling new size factor during generation/transforms.
@export var new_size_factor : float = 1.0

# Non-Uniform sampling
## Phase offset used to shift periodic sampling patterns.
@export var phase : float = 0.0
## Overall size value used by this node for generated data.
@export var size : float = 1.0
## Output value/attribute key used for group id.
@export var out_group_id : String
## Number of groups/buckets created for grouped sampling operations.
@export var groups : Array[int] = [ 32 ]

## Number of samples/points this node tries to generate.
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
