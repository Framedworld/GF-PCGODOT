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

@export_subgroup("Mesh Entries")
## Mesh spawn descriptors (Unreal's Static Mesh Spawner entries): mesh, weight,
## material, shadows, visibility range, layers, GI, custom data and collision.
## When non-empty they are the mesh source and mesh, mesh_attribute and
## mesh_variants are ignored; when empty the node behaves exactly as before.
@export var mesh_entries : Array[FlowMeshSpawnEntry] = []
## How each point picks its entry: weighted random (per-point seed), entry index
## from an attribute, entry name from an attribute, or cycling by point index.
@export var entry_selection : FlowSpawnUtil.eEntrySelection = FlowSpawnUtil.eEntrySelection.Weighted
## Attribute read by the Attribute Index / Attribute Name selections.
@export var entry_attribute : String = ""

@export_subgroup("Placement")
## Attribute holding the spawn parent per point (or per data, e.g. "@data.target"
## from Create Target Node): a Node3D reference, or a NodePath/String relative to
## the owner. Empty: spawn_parent_path is used.
@export var spawn_parent_attribute : String = ""
## Reuse this node's MultiMeshInstance3Ds from the previous generation (same
## component, same mesh, material and render settings) instead of freeing and
## recreating them. Needs clear_previous_instances. Off by default.
@export var reuse_instances : bool = false

func _init():
	super._init()
	resource_name = "Spawn Meshes Settings"

func exposeParam(name : String) -> bool:
	if name == "mesh_variant_weights":
		return mesh_variants.size() > 0
	if name == "mesh_selector_attribute":
		return mesh_variants.size() > 0 and not randomize_mesh_variants
	if name == "entry_selection":
		return mesh_entries.size() > 0
	if name == "entry_attribute":
		return mesh_entries.size() > 0 and ( entry_selection == FlowSpawnUtil.eEntrySelection.AttributeIndex or entry_selection == FlowSpawnUtil.eEntrySelection.AttributeName )
	return true

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "entry_attribute", "port": 0 },
		{ "prop": "spawn_parent_attribute", "port": 0 },
	]
