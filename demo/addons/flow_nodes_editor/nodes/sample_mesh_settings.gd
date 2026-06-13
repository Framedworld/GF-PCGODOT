@tool
class_name SampleMeshNodeSettings
extends NodeSettings

@export_group("Sample Mesh")

enum eMode {
	UseDensity,
	UseNumSamples,
	OnePerVertex,
	FaceCenters,
}

## Selects which processing mode this node uses (similar to UE PCG node modes).
@export var mode : eMode = eMode.UseDensity
## Density value used to control point generation/filtering probability.
@export var density : float = 0.5
## Number of samples/points this node tries to generate.
@export var num_samples : int = 100
## Size assigned to generated points (point extents/scale hint).
@export var point_size : float = 1.0

@export_group("Hard Edges")
## When enabled, rejects hard edges from the generated/processed output.
@export var discard_hard_edges : bool = false:
	set( new_value ):
		discard_hard_edges = new_value
		notify_property_list_changed()
## Angle threshold/offset controlling hard edge angle threshold.
@export var hard_edge_angle_threshold : float = 45.0
## Distance value used by this node for hard edge distance threshold.
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
