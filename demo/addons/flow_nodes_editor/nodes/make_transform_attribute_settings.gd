@tool
extends NodeSettings

@export_group("Make Transform Attribute")

## Vector attribute for the translation; empty uses default_translation.
@export var translation_attribute : String = "position"
## Rotation attribute: a Vector (Euler degrees, the point rotation model) or a
## Quaternion / Vector4 (x, y, z, w). Empty uses default_rotation.
@export var rotation_attribute : String = "rotation"
## Vector attribute for the scale; empty uses default_scale.
@export var scale_attribute : String = "size"
@export var default_translation : Vector3 = Vector3.ZERO
## Euler degrees.
@export var default_rotation : Vector3 = Vector3.ZERO
@export var default_scale : Vector3 = Vector3.ONE
## Transform attribute written with the result.
@export var out_name : String = "transform"

func _init():
	super._init()
	resource_name = "Make Transform Attribute"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "translation_attribute", "port": 0 },
		{ "prop": "rotation_attribute", "port": 0 },
		{ "prop": "scale_attribute", "port": 0 },
	]
