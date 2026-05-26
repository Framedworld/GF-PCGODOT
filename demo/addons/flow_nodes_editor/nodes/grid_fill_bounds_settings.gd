@tool
class_name GridFillBoundsNodeSettings
extends NodeSettings

@export_group("Grid Fill Bounds")

@export var use_input_bounds : bool = true:
	set(value):
		use_input_bounds = value
		notify_property_list_changed()
		emit_changed()
@export var bounds_center : Vector3 = Vector3.ZERO:
	set(value):
		bounds_center = value
		emit_changed()
@export var bounds_size : Vector3 = Vector3(10.0, 1.0, 10.0):
	set(value):
		bounds_size = value
		emit_changed()
@export var cell_size : Vector3 = Vector3.ONE:
	set(value):
		cell_size = value
		emit_changed()
@export var fill_y_axis : bool = false:
	set(value):
		fill_y_axis = value
		emit_changed()
@export var copy_input_attributes : bool = true:
	set(value):
		copy_input_attributes = value
		emit_changed()
@export var source_index_attribute : String = "":
	set(value):
		source_index_attribute = value.strip_edges()
		emit_changed()
@export var max_points : int = 100000:
	set(value):
		max_points = maxi(1, value)
		emit_changed()

func _init():
	super._init()
	resource_name = "Grid Fill Bounds"

func exposeParam(name : String) -> bool:
	if use_input_bounds:
		return name != "bounds_center" and name != "bounds_size"
	return true
