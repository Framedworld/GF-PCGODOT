@tool
class_name SpawnMeshesNodeSettings
extends NodeSettings

@export_group("Spawn Meshes")

## Mesh resource to spawn at point positions.
@export var mesh : Mesh = preload( "res://addons/flow_nodes_editor/resources/unit_cube.tres" )
## Input attribute name specifying custom meshes per point.
@export var mesh_attribute : String
## Array of variant Mesh resources.
@export var mesh_variants : Array[Mesh] = []
## Selection weights assigned to variant meshes.
@export var mesh_variant_weights : Array[float] = []
## Custom mesh variant index selector attribute name.
@export var mesh_selector_attribute : String = ""
## If enabled, picks variants randomly per point using stable seeds.
@export var randomize_mesh_variants : bool = false
## Color attribute stream name to assign as mesh vertex colors.
@export var color_attribute : String = "color"
## If enabled, writes point color values directly to mesh vertex data.
@export var use_vertex_colors : bool = true
## Scene tree path under which spawned meshes are grouped.
@export var spawn_parent_path : String = ""
## If enabled, deletes previously spawned mesh instances before evaluation.
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
