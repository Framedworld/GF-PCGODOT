@tool
class_name GridSizeNodeSettings
extends NodeSettings

# Reserved context key the grid_size node still writes (deprecated: nothing
# reads it; hierarchical generation takes the levels from FlowCompiledGraph and
# exposes the current one as EvaluationContext.grid_size).
const CTX_KEY := "__grid_size__cell_size"

@export_group("Grid Size")

## A descriptive label for this grid size configuration.
@export var label: String = "Grid Size"

## Cell size of this hierarchy level in world units, snapped to a power of two.
## FlowWorld3D partitions the XZ plane into cells of this size for every node
## downstream of this marker. Read from the saved graph at compile time.
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
