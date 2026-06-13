@tool
extends NodeSettings

@export_group("Points From Imported Scene")

## Scene/resource path used to resolve asset.
@export_file("*.tscn", "*.scn", "*.glb", "*.gltf", "*.obj", "*.fbx", "*.abc", "*.mesh", "*.res", "*.tres") var asset_path : String = ""
## Toggles whether this node uses mesh bounds instead of default behavior.
@export var use_mesh_bounds : bool = true
## Size parameter controlling fallback size during generation/transforms.
@export var fallback_size : Vector3 = Vector3.ONE
## When enabled, also outputs mesh resource alongside generated points/data.
@export var include_mesh_resource : bool = true
## Attribute name used to read/write mesh on point data.
@export var mesh_attribute : String = "mesh"
## When enabled, also outputs source name alongside generated points/data.
@export var include_source_name : bool = true
## Attribute name used to read/write source name on point data.
@export var source_name_attribute : String = "source_node_name"
## Scene/resource path used to resolve include source.
@export var include_source_path : bool = true
## Attribute name used to read/write source path on point data.
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
