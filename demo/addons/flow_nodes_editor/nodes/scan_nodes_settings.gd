@tool
class_name ScanNodesNodeSettings
extends NodeSettings

@export_group("Scan Nodes")

## Group name used to find or filter scene nodes.
@export var group_name : String
## Filter by node name; supports * and ? wildcards (case-insensitive)
@export var filter_by_name : String
## Optional class-name substring filter when scanning scene nodes.
@export var filter_by_class_name : String
## Scan the whole scene tree; when false only direct children of the scene root are inspected
@export var recursive : bool = true
## When enabled, imports metadata from the scanned source.
@export var import_metadata : bool = false
## When enabled, imports properties from the scanned source.
@export var import_properties : Array[ StringName ]
## Size parameter controlling size to bounds during generation/transforms.
@export var size_to_bounds : bool = false

func _init():
	super._init()
	resource_name = "Scan Nodes Settings"
