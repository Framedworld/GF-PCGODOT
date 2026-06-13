@tool
class_name GridFillBoundsNodeSettings
extends NodeSettings

@export_group("Grid Fill Bounds")

## Toggles whether this node uses input bounds instead of default behavior.
@export var use_input_bounds : bool = true:
	set(value):
		use_input_bounds = value
		notify_property_list_changed()
		emit_changed()
## Center point of the bounds region used for fill/sampling.
@export var bounds_center : Vector3 = Vector3.ZERO:
	set(value):
		bounds_center = value
		emit_changed()
## Size parameter controlling bounds size during generation/transforms.
@export var bounds_size : Vector3 = Vector3(10.0, 1.0, 10.0):
	set(value):
		bounds_size = value
		emit_changed()
## Size of each grid cell used by this node.
@export var cell_size : Vector3 = Vector3.ONE:
	set(value):
		cell_size = value
		emit_changed()
## If enabled, fills bounds volume across Y instead of a single horizontal layer.
@export var fill_y_axis : bool = false:
	set(value):
		fill_y_axis = value
		emit_changed()
## When enabled, copies input attributes from source data into the output.
@export var copy_input_attributes : bool = true:
	set(value):
		copy_input_attributes = value
		emit_changed()
## Attribute name used to read/write source index on point data.
@export var source_index_attribute : String = "":
	set(value):
		source_index_attribute = value.strip_edges()
		emit_changed()
## Upper bound used by this node for points.
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
