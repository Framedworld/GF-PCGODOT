@tool
class_name BoundsFromMeshNodeSettings
extends NodeSettings

@export_group("Bounds From Mesh")

## Mesh whose local AABB becomes every point's bounds.
@export var mesh : Mesh
## Optional Resource attribute holding a Mesh per point (e.g. written by
## match_and_set or assets). When set it is used instead of `mesh`; points
## whose value is not a Mesh fall back to `mesh`, then keep their bounds.
@export var mesh_attribute : String = ""

func _init():
	super._init()
	resource_name = "Bounds From Mesh Settings"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "mesh_attribute", "port": 0 },
	]
