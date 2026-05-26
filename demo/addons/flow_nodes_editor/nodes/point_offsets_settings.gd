@tool
extends NodeSettings

@export_group("Point Offsets")

@export var offsets : Array[Vector3] = [Vector3.ZERO]
@export var rotations : Array[Vector3] = [Vector3.ZERO]
@export var sizes : Array[Vector3] = [Vector3.ONE]
@export var local_space : bool = true
@export var combine_rotation : bool = true
@export var scale_offsets_by_anchor_size : bool = false
@export var inherit_anchor_size : bool = false
@export var parent_index_attribute : String = "parent_index"
@export var offset_index_attribute : String = "offset_index"
@export var label_attribute : String = "offset_label"
@export var labels : Array[String] = []

func _init():
	super._init()
	resource_name = "Point Offsets Settings"
