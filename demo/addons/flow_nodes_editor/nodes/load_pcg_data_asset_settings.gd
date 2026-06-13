@tool
extends NodeSettings

@export_group("Load PCG Data Asset")

enum eAssetFormat {
	Auto,
	Json,
	Resource,
}

## Scene/resource path used to resolve asset.
@export_file("*.json", "*.tres", "*.res") var asset_path : String = ""
## Selects this node behavior mode (Auto, Json, Resource).
@export var asset_format : eAssetFormat = eAssetFormat.Auto
## Property name used to read row data from the loaded PCG asset.
@export var rows_property_name : String = "rows"
## Property name used to read stream metadata from the loaded PCG asset.
@export var streams_property_name : String = "streams"
## Scene/resource path used to resolve add source.
@export var add_source_path : bool = true
## Attribute name used to read/write source path on point data.
@export var source_path_attribute : String = "source_path"

func _init():
	super._init()
	resource_name = "Load PCG Data Asset Settings"

func exposeParam(name : String) -> bool:
	if name == "source_path_attribute":
		return add_source_path
	return true
