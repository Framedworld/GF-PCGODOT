@tool
extends NodeSettings

@export_group("Load PCG Data Asset")

enum eAssetFormat {
	## Automatically determines the format based on the file extension.
	Auto,
	## Parses the asset from a JSON data format.
	Json,
	## Loads the asset as a Godot native Resource.
	Resource,
}

## The file path to the PCG data asset to load.
@export_file("*.json", "*.tres", "*.res") var asset_path : String = ""
## The file format of the asset to load.
@export var asset_format : eAssetFormat = eAssetFormat.Auto
## The property name in the asset containing table/row data.
@export var rows_property_name : String = "rows"
## The property name in the asset containing stream definitions.
@export var streams_property_name : String = "streams"
## If enabled, records the source asset file path as an attribute.
@export var add_source_path : bool = true
## The attribute name in which to store the source file path.
@export var source_path_attribute : String = "source_path"

func _init():
	super._init()
	resource_name = "Load PCG Data Asset Settings"

func exposeParam(name : String) -> bool:
	if name == "source_path_attribute":
		return add_source_path
	return true
