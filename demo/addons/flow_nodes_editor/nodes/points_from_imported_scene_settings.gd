@tool
extends NodeSettings

@export_group("Points From Imported Scene")

## File path to target scene asset.
@export_file("*.tscn", "*.scn", "*.glb", "*.gltf", "*.obj", "*.fbx", "*.abc", "*.mesh", "*.res", "*.tres") var asset_path : String = ""
## If enabled, sets point size/bounds from scene mesh sizes.
@export var use_mesh_bounds : bool = true
## Fallback point size used when bounds are unavailable.
@export var fallback_size : Vector3 = Vector3.ONE
## If enabled, outputs mesh resource paths in attribute stream.
@export var include_mesh_resource : bool = true
## Output attribute stream name storing mesh resource.
@export var mesh_attribute : String = "mesh"
## If enabled, records name of source node.
@export var include_source_name : bool = true
## Output attribute stream name storing source node name.
@export var source_name_attribute : String = "source_node_name"
## If enabled, records path of source scene.
@export var include_source_path : bool = true
## Output attribute stream name storing source scene path.
@export var source_path_attribute : String = "source_path"

func _init():
	super._init()
	resource_name = "Points From Imported Scene Settings"

func exposeParam(name : String) -> bool:
	if name == "mesh_attribute":
		return include_mesh_resource
	if name == "source_name_attribute":
		return include_source_name
	if name == "source_path_attribute":
		return include_source_path
	return true
