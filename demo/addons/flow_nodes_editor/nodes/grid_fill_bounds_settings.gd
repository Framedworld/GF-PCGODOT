@tool
class_name GridFillBoundsNodeSettings
extends NodeSettings

@export_group("Grid Fill Bounds")

## If enabled, uses the bounding boxes of incoming points as regions to fill. If disabled, uses the constant bounds settings.
@export var use_input_bounds : bool = true:
	set(value):
		use_input_bounds = value
		notify_property_list_changed()
		emit_changed()
## The local/world Vector3 center of the constant bounds region to fill.
@export var bounds_center : Vector3 = Vector3.ZERO:
	set(value):
		bounds_center = value
		emit_changed()
## The Vector3 dimensions of the constant bounds region to fill.
@export var bounds_size : Vector3 = Vector3(10.0, 1.0, 10.0):
	set(value):
		bounds_size = value
		emit_changed()
## The size spacing (X, Y, Z) between generated grid points.
@export var cell_size : Vector3 = Vector3.ONE:
	set(value):
		cell_size = value
		emit_changed()
## If enabled, generates a 3D grid filling the Y axis/volume. If disabled, generates a single 2D horizontal layer of points.
@export var fill_y_axis : bool = false:
	set(value):
		fill_y_axis = value
		emit_changed()
## If enabled, copies attributes from the source points/bounds into the generated grid points.
@export var copy_input_attributes : bool = true:
	set(value):
		copy_input_attributes = value
		emit_changed()
## The output integer attribute name storing the index of the source point/bounds that spawned each grid point.
@export var source_index_attribute : String = "":
	set(value):
		source_index_attribute = value.strip_edges()
		emit_changed()
## The safety limit of the maximum number of grid points allowed to be generated.
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
