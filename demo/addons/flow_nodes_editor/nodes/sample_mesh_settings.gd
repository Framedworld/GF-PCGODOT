@tool
class_name SampleMeshNodeSettings
extends NodeSettings

@export_group("Sample Mesh")

enum eMode {
	## Distributes points randomly based on mesh surface density.
	UseDensity,
	## Distributes a specific count of points randomly.
	UseNumSamples,
	## Emits exactly one point at each vertex.
	OnePerVertex,
	## Emits exactly one point at each face center.
	FaceCenters,
}

## Selects the sampling method used to generate points on the input meshes:
@export var mode : eMode = eMode.UseDensity
## The density of points per unit of surface area in world space.
## Total number of points generated is: round(total_surface_area * density).
## Only used when 'mode' is set to 'UseDensity'.
@export var density : float = 0.5
## The exact number of points to generate/sample across the mesh surface.
## Points are distributed uniformly using area-weighted random barycentric sampling.
## Only used when 'mode' is set to 'UseNumSamples'.
@export var num_samples : int = 100
## The size scale assigned to each generated point.
## Sets a uniform scale (Vector3.ONE * point_size) for the output points.
@export var point_size : float = 1.0

@export_group("Hard Edges")
## If enabled, filters out generated points that are within a certain distance from 'hard edges'.
## Hard edges include boundary edges, non-manifold edges, and edges where the angle between
## adjacent face normals meets or exceeds 'hard_edge_angle_threshold'.
@export var discard_hard_edges : bool = false:
	set( new_value ):
		discard_hard_edges = new_value
		notify_property_list_changed()
## The threshold angle (in degrees) between adjacent face normals to classify an edge as a hard edge.
@export var hard_edge_angle_threshold : float = 45.0
## The minimum distance (in world units) a generated point must keep from any hard edge.
## Points closer than this threshold are discarded.
@export var hard_edge_distance_threshold : float = 0.1

func _init():
	super._init()
	resource_name = "Sample Mesh Settings"

func exposeParam( name : String ) -> bool:
	if name == "hard_edge_angle_threshold" or name == "hard_edge_distance_threshold":
		return discard_hard_edges
	if name == "density":
		return mode == eMode.UseDensity
	if name == "num_samples":
		return mode == eMode.UseNumSamples
	return true
