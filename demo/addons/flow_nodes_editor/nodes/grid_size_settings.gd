@tool
class_name GridSizeNodeSettings
extends NodeSettings

# Reserved context key written by the grid_size node.
# Downstream nodes or a future partition scheduler can read this via:
#   ctx.variables.get(GridSizeNodeSettings.CTX_KEY, 0.0)
const CTX_KEY := "__grid_size__cell_size"

@export_group("Grid Size")

## Label shown in the node title and used to identify this partition tier
## when multiple grid_size nodes are stacked (coarse then fine).
@export var label: String = "Grid Size"

## Cell size in world units. Must be a power of two (e.g. 8, 16, 32, 64, 128).
## The value is clamped to the nearest valid power-of-two on assignment.
## This annotation is currently inert — it is recorded on the evaluation
## context for a future FlowGraphNode3D partition mode to consume.
@export var cell_size: float = 64.0 :
	set(v):
		cell_size = _snap_to_power_of_two(v)

func _init():
	super._init()
	resource_name = "Grid Size Settings"

## Returns the nearest power-of-two >= 1 to the given value.
## Values <= 0 are clamped to 1 (which is 2^0).
static func _snap_to_power_of_two(v: float) -> float:
	if v <= 1.0:
		return 1.0
	# Round to the nearest power of two (not always the ceiling):
	# find the exponent such that 2^exp is closest to v.
	var exp_floor := int(floor(log(v) / log(2.0)))
	var lower := pow(2.0, exp_floor)
	var upper := pow(2.0, exp_floor + 1)
	if (v - lower) < (upper - v):
		return lower
	return upper
