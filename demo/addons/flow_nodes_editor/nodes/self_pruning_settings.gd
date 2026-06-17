@tool
class_name SelfPruningSettings
extends NodeSettings

@export_group("Self Pruning")

enum ePruneMode {
	## Prunes points based on bounding box overlaps.
	BoundsOverlap,
	## Prunes points that fall in the same grid cell coordinates.
	GridCell,
}

enum eDensityFunction {
	## Applies a hard binary overlap culling.
	Binary,
	## Applies a minimum-based density attenuation.
	Minimum,
	## Multiplies overlapping densities.
	Multiply,
	## Subtracts overlapping densities.
	Subtract,
}

## Pruning algorithm to use.
@export var mode : ePruneMode = ePruneMode.BoundsOverlap:
	set(value):
		mode = value
		notify_property_list_changed()
		emit_changed()

## If enabled, retains points that overlap with points from their own source group.
@export var keep_self_intersections : bool = false
## Operation to resolve overlapping point densities.
@export var density_function : eDensityFunction = eDensityFunction.Binary:
	set(value):
		density_function = clampi(value, 0, eDensityFunction.size() - 1)
		emit_changed()
## Grid cell dimensions used for collision/overlap mapping.
@export var cell_size : float = 1.0:
	set(value):
		cell_size = value
		emit_changed()
## Name of the attribute stream used to decide priority (e.g. 'density' or 'seed').
@export var prefer_attribute : String:
	set(value):
		prefer_attribute = value
		emit_changed()
## Priority comparison behavior to select which point to keep.
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
