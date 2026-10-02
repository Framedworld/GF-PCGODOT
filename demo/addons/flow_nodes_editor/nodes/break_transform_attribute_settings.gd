@tool
extends NodeSettings

@export_group("Break Transform Attribute")

## Transform attribute to decompose.
@export var in_name : String = "transform"
## Vector attribute receiving the translation (empty skips it).
@export var out_translation : String = "translation"
## Vector attribute receiving the rotation as Euler degrees (empty skips it).
## Use "rotation" to write the point rotation.
@export var out_rotation : String = "rotator"
## Quaternion attribute receiving the rotation (empty skips it).
@export var out_quaternion : String = ""
## Vector attribute receiving the scale (empty skips it).
@export var out_scale : String = "scale"

func _init():
	super._init()
	resource_name = "Break Transform Attribute"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [ { "prop": "in_name", "port": 0 } ]
