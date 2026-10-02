@tool
class_name GetPropertyFromObjectPathNodeSettings
extends NodeSettings

@export_group("Get Property From Object Path")

## Objects to read, one output row each, in order. Node paths are resolved
## from the owner node (relative "Child/Sub", "../Sibling", "%UniqueName",
## absolute "/root/..."), then from the owner's scene root. Paths starting with
## res://, uid:// or user:// are loaded as resources and need no owner.
@export var object_paths : PackedStringArray = PackedStringArray()
## Properties to read, with the same syntax as Scan Nodes' import_properties:
## "visible", "mesh:size", "material[0]:albedo_color". The attribute is named
## after the last path segment ("size", "albedo_color").
@export var property_paths : Array[ StringName ] = []
## String attribute receiving each row's object path. Empty disables it.
@export var path_attribute : String = "object_path"

func _init():
	super._init()
	resource_name = "Get Property From Object Path Settings"
