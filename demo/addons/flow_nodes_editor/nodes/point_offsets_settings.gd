@tool
extends NodeSettings

@export_group("Point Offsets")

## Offset applied to offsets before writing final output values.
@export var offsets : Array[Vector3] = [Vector3.ZERO]
## Rotation value/attribute used when orienting generated instances or points.
@export var rotations : Array[Vector3] = [Vector3.ZERO]
## Size parameter controlling sizes during generation/transforms.
@export var sizes : Array[Vector3] = [Vector3.ONE]
## Applies offsets/rotations/sizes in local space instead of world space.
@export var local_space : bool = true
## Rotation value/attribute used when orienting generated instances or points.
@export var combine_rotation : bool = true
## Offset applied to scale offsets by anchor size before writing final output values.
@export var scale_offsets_by_anchor_size : bool = false
## Size parameter controlling inherit anchor size during generation/transforms.
@export var inherit_anchor_size : bool = false
## Attribute name used to read/write parent index on point data.
@export var parent_index_attribute : String = "parent_index"
## Attribute name used to read/write offset index on point data.
@export var offset_index_attribute : String = "offset_index"
## Attribute name used to read/write label on point data.
@export var label_attribute : String = "offset_label"
## List of label tokens used to pick indexed offset/rotation/size presets.
@export var labels : Array[String] = []

func _init():
	super._init()
	resource_name = "Point Offsets Settings"
