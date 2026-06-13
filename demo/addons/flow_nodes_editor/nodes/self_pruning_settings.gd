@tool
class_name SelfPruningSettings
extends NodeSettings

@export_group("Self Pruning")

enum ePruneMode {
	BoundsOverlap,
	GridCell,
}

# How overlapped points are resolved in BoundsOverlap mode.
#  Binary   - legacy default: pruned points are hard-removed (today's behavior).
#  Minimum  - density := min(density, 1 - overlap_factor). Pruned points survive.
#  Multiply - density := density * (1 - overlap_factor).
#  Subtract - density := density - overlap_factor (clamped to 0).
# Non-Binary modes keep every point and attenuate the density of points that
# would have been pruned (overlap shaped by steepness when present), leaving
# culling to a downstream density_filter.
enum eDensityFunction {
	Binary,
	Minimum,
	Multiply,
	Subtract,
}

## Selects which processing mode this node uses (similar to UE PCG node modes).
@export var mode : ePruneMode = ePruneMode.BoundsOverlap:
	set(value):
		mode = value
		notify_property_list_changed()
		emit_changed()

@export var keep_self_intersections : bool = false
## How pruned points are resolved. Binary (default) hard-removes them (legacy).
## Minimum/Multiply/Subtract instead keep them with attenuated density.
@export var density_function : eDensityFunction = eDensityFunction.Binary:
	set(value):
		density_function = clampi(value, 0, eDensityFunction.size() - 1)
		emit_changed()
## Size of each grid cell used by this node.
@export var cell_size : float = 1.0:
	set(value):
		cell_size = value
		emit_changed()
@export var prefer_attribute : String:
	set(value):
		prefer_attribute = value
		emit_changed()
@export var prefer_value : String:
	set(value):
		prefer_value = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Self Pruning"

func exposeParam(name : String) -> bool:
	if mode == ePruneMode.BoundsOverlap:
		return name != "cell_size" and name != "prefer_attribute" and name != "prefer_value"
	# GridCell mode: density_function only applies to BoundsOverlap.
	return name != "keep_self_intersections" and name != "density_function"
