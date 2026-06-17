@tool
class_name GridConnectPointsNodeSettings
extends NodeSettings

@export_group("Grid Connect Points")

enum eAxisOrder {
	## Walks along the X axis first, then along the Z axis.
	XThenZ,
	## Walks along the Z axis first, then along the X axis.
	ZThenX,
}

## The cell scale size (X, Y, Z) of the connection grid.
@export var cell_size : Vector3 = Vector3.ONE:
	set(value):
		cell_size = value
		emit_changed()
## Determines the walk order when connecting points on different axes.
@export var axis_order : eAxisOrder = eAxisOrder.XThenZ:
	set(value):
		axis_order = value
		emit_changed()
## If enabled, includes the original input points in the output connection point stream.
@export var include_input_points : bool = true:
	set(value):
		include_input_points = value
		emit_changed()
## If enabled, merges duplicate grid connections to avoid overlapping path segments.
@export var deduplicate_cells : bool = true:
	set(value):
		deduplicate_cells = value
		emit_changed()
## The output integer attribute stream name in which to write the connection path index.
@export var path_index_attribute : String = "path_index":
	set(value):
		path_index_attribute = value.strip_edges()
		emit_changed()

func _init():
	super._init()
	resource_name = "Grid Connect Points"
