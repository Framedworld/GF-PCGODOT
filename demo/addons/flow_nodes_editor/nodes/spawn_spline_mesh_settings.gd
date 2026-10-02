@tool
class_name SpawnSplineMeshSettings
extends NodeSettings

enum eSegmentation {
	## One mesh per curve segment between consecutive control points (Unreal's
	## spline mesh per spline segment). The mesh stretches to the segment length.
	ControlPoints,
	## The mesh is repeated along the whole spline: as many copies as fit
	## (rounded, at least one) of the reference mesh length x scale_along, each
	## stretched slightly so the copies meet exactly.
	TileMesh,
}

enum eSegmentSelection {
	## Segment index modulo the number of entries.
	Cycle,
	## Weighted random per segment (entry weights), seeded from the node seed,
	## the spline index and the segment index.
	Weighted,
}

@export_group("Spawn Spline Mesh")

## Mesh bent along each segment when mesh_entries is empty.
@export var mesh : Mesh = preload( "res://addons/flow_nodes_editor/resources/unit_cube.tres" )
## Mesh descriptors chosen per segment (material, shadows, visibility range,
## layers, GI and collision from the entry; custom data does not apply).
@export var mesh_entries : Array[FlowMeshSpawnEntry] = []
## How each segment picks its entry.
@export var segment_selection : eSegmentSelection = eSegmentSelection.Cycle
## Mesh axis that runs along the spline.
@export var forward_axis : FlowSplineBend.eAxis = FlowSplineBend.eAxis.Z
## How segments are cut from the spline.
@export var segmentation : eSegmentation = eSegmentation.ControlPoints
## TileMesh only: tile length as a multiple of the mesh length on forward_axis.
@export_range(0.01, 100.0, 0.01, "or_greater") var scale_along : float = 1.0
## Cross-section scale (side, up) at the start of each segment.
@export var scale_across_start : Vector2 = Vector2.ONE
## Cross-section scale (side, up) at the end of each segment.
@export var scale_across_end : Vector2 = Vector2.ONE
## Curve: follow the curve's tangents. Linear: straight chord per segment.
@export var tangent_mode : FlowSplineBend.eTangentMode = FlowSplineBend.eTangentMode.Curve
## Up vector of the cross-section: the curve's up vectors (tilt) or world up.
@export var up_mode : FlowSplineBend.eUpMode = FlowSplineBend.eUpMode.CurveUp
## Stream holding the Path3D nodes (scan_splines / create_spline output).
@export var spline_attribute : String = "node"
## Scene tree path under which the segment meshes are grouped.
@export var spawn_parent_path : String = ""
## Per-data attribute holding the spawn parent (e.g. "@data.target" from Create
## Target Node). Empty: spawn_parent_path is used.
@export var spawn_parent_attribute : String = ""
## If enabled, deletes previously spawned segment meshes before evaluation.
@export var clear_previous_instances : bool = true
## Reuse this node's segment MeshInstance3Ds from the previous generation
## instead of freeing and recreating them. Off by default.
@export var reuse_instances : bool = false

func _init():
	super._init()
	resource_name = "Spawn Spline Mesh Settings"

func exposeParam(name : String) -> bool:
	if name == "segment_selection":
		return mesh_entries.size() > 0
	if name == "scale_along":
		return segmentation == eSegmentation.TileMesh
	return true
