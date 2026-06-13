@tool
class_name SpawnMeshesNodeSettings
extends NodeSettings

@export_group("Spawn Meshes")

## Default mesh to spawn when no mesh attribute/variant overrides it.
@export var mesh : Mesh = preload( "res://addons/flow_nodes_editor/resources/unit_cube.tres" )
## Attribute name used to read/write mesh on point data.
@export var mesh_attribute : String
## List of mesh candidates this node can choose from while spawning/assigning.
@export var mesh_variants : Array[Mesh] = []
## Relative selection weights used when randomly picking from mesh variant.
@export var mesh_variant_weights : Array[float] = []
## Attribute name used to read/write mesh selector on point data.
@export var mesh_selector_attribute : String = ""
## If enabled, randomly chooses from mesh_variants (or mesh_selector_attribute) instead of deterministic selection.
@export var randomize_mesh_variants : bool = false
## Attribute name used to read/write color on point data.
@export var color_attribute : String = "color"
## Toggles whether this node uses vertex colors instead of default behavior.
@export var use_vertex_colors : bool = true
## Scene/resource path used to resolve spawn parent.
@export var spawn_parent_path : String = ""
## When enabled, clears previous instances before writing new results.
@export var clear_previous_instances : bool = true

func _init():
	super._init()
	resource_name = "Spawn Meshes Settings"

func exposeParam(name : String) -> bool:
	if name == "mesh_variant_weights":
		return mesh_variants.size() > 0
	if name == "mesh_selector_attribute":
		return mesh_variants.size() > 0 and not randomize_mesh_variants
	return true
