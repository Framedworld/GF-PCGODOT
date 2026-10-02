@tool
class_name GetExecutionBoundsNodeSettings
extends NodeSettings

@export_group("Get Execution Bounds")

enum eOutputMode {
	## A box volume shape (FlowBoxVolume, zero points): spatial data for the
	## set operations, the samplers and To Point.
	Shape,
	## One bounds point at the box centre with bounds_min/bounds_max.
	Points,
}

## Box volume shape (default) or one bounds point.
@export var output_mode : eOutputMode = eOutputMode.Shape:
	set(value):
		output_mode = value
		emit_changed()
## Steepness of the box volume in Shape mode (1 = hard edge).
@export_range(0.0, 1.0) var steepness : float = 1.0
## Bounds used outside hierarchical generation (a plain FlowGraphNode3D, the
## editor preview), where there is no cell. World space.
@export var fallback_bounds : AABB = AABB(Vector3(-50.0, -50.0, -50.0), Vector3(100.0, 100.0, 100.0))

func _init():
	super._init()
	resource_name = "Get Execution Bounds Settings"

func exposeParam(name : String) -> bool:
	if name == "steepness":
		return output_mode == eOutputMode.Shape
	return true
