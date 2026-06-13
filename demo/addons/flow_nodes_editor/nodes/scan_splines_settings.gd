@tool
class_name ScanSplinesNodeSettings
extends NodeSettings

@export_group("Scan Splines")

## Group name used to find or filter scene nodes.
@export var group_name : String
## Only include nodes that have this boolean metadata entry set to true
@export var required_meta_bool : StringName
## Scan the whole scene tree; when false only direct children of the scene root are inspected
@export var recursive : bool = true

func _init():
	super._init()
	resource_name = "Scan Splines Settings"
