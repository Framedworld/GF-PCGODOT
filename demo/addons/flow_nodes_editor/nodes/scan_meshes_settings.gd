@tool
class_name ScanMeshesNodeSettings
extends NodeSettings

@export_group("Scan Meshes")

## Group name to scan for meshes in the scene.
@export var group_name : String
## Metadata key string checked before scanning.
@export var required_meta_bool : StringName
## If enabled, scans recursively through scene hierarchies.
@export var recursive : bool = true

func _init():
	super._init()
	resource_name = "Scan Meshes Settings"
