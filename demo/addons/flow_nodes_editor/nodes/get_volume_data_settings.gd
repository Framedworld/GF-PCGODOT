@tool
extends NodeSettings

@export_group("Get Volume Data")

enum eOutputMode {
	## One Data per collected volume.
	PerVolume,
	## A single Data whose shape is the union of every volume.
	Merged,
}

enum eMeshVolume {
	## The mesh's oriented bounding box.
	Bounds,
	## The closed mesh itself (inside test by ray parity).
	ClosedMesh,
}

## Group name to collect from. Group members that are Area3D / bodies contribute
## their CollisionShape3D children. Empty scans the whole scene.
@export var group_name : String
## Metadata key that must be true on a node for it to be collected.
@export var required_meta_bool : StringName
## Also collect descendants of the group members (or of the scene root).
@export var recursive : bool = true
## Collect CollisionShape3D nodes (Box, Sphere, Capsule, Cylinder, Concave; Convex as its box).
@export var include_collision_shapes : bool = true
## Collect CSG nodes (CSGBox3D, CSGSphere3D exactly; other CSG roots from their mesh).
@export var include_csg : bool = true
## Collect MeshInstance3D nodes.
@export var include_meshes : bool = false
## How a MeshInstance3D becomes a volume.
@export var mesh_volume : eMeshVolume = eMeshVolume.Bounds
## One Data per volume, or one merged Data.
@export var output_mode : eOutputMode = eOutputMode.Merged
## Hardness of box / sphere edges (UE Steepness): 1 = hard, lower = density
## ramps down towards the boundary.
@export_range( 0.0, 1.0 ) var steepness : float = 1.0

func _init():
	super._init()
	resource_name = "Get Volume Data Settings"

func exposeParam( name : String ) -> bool:
	if name == "mesh_volume":
		return include_meshes
	return true
