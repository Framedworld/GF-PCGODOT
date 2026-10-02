@tool
extends "res://addons/flow_nodes_editor/nodes/sample_points_settings.gd"

# Spatial data inputs (Data.shape) only; point inputs keep the Sample Points
# settings above. No export group: these stay out of the parameter ports.
## Voxel grid spacing for spatial data inputs (UE Voxel Size).
@export var voxel_size : Vector3 = Vector3.ONE
## Write the shape's density to the samples (off: 1.0).
@export var apply_density_to_points : bool = true
## Safety cap on the number of voxels tested.
@export var max_candidates : int = 4000000

func _init():
	super._init()
	resource_name = "Volume Sampler Settings"
	distribution = SamplePointsNodeSettings.eDistribution.UniformGrid
