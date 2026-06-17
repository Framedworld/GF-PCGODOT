@tool
extends NodeSettings

@export_group("Point Offsets")

## Array of Vector3 offset offsets to apply.
@export var offsets : Array[Vector3] = [Vector3.ZERO]
## Array of Vector3 rotation offsets to apply.
@export var rotations : Array[Vector3] = [Vector3.ZERO]
## Array of Vector3 scale/size offsets to apply.
@export var sizes : Array[Vector3] = [Vector3.ONE]
## If enabled, offsets are applied relative to local coordinates. If disabled, offset is in world coordinates.
@export var local_space : bool = true
## If enabled, combines rotation offsets instead of overwriting.
@export var combine_rotation : bool = true
## If enabled, offsets are scaled by the parent/anchor scale size.
@export var scale_offsets_by_anchor_size : bool = false
## If enabled, generated points inherit anchor size.
@export var inherit_anchor_size : bool = false
## Attribute stream name storing parent point index.
@export var parent_index_attribute : String = "parent_index"
## Attribute stream name storing offset pattern index.
@export var offset_index_attribute : String = "offset_index"
## Attribute stream name storing text label.
@export var label_attribute : String = "offset_label"
## Array of text labels assigned to offset points.
@export var labels : Array[String] = []

func _init():
	super._init()
	resource_name = "Point Offsets Settings"
