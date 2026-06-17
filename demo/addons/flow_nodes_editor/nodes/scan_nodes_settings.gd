@tool
class_name ScanNodesNodeSettings
extends NodeSettings

@export_group("Scan Nodes")

## Group name to scan for nodes.
@export var group_name : String
## Optional name text filter for nodes.
@export var filter_by_name : String
## Optional class type filter for nodes.
@export var filter_by_class_name : String
## If enabled, scans recursively through sub-nodes.
@export var recursive : bool = true
## If enabled, writes node metadata into custom streams.
@export var import_metadata : bool = false
## If enabled, writes node property values into custom streams.
@export var import_properties : Array[ StringName ]
## If enabled, calculates and sets point sizes from node bounds.
@export var size_to_bounds : bool = false

func _init():
	super._init()
	resource_name = "Scan Nodes Settings"
