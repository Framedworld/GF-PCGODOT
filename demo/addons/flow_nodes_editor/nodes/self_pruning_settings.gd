@tool
class_name SelfPruningSettings
extends NodeSettings

@export_group("Self Pruning")

enum ePruneMode {
	BoundsOverlap,
	GridCell,
}

## Selects which processing mode this node uses (similar to UE PCG node modes).
@export var mode : ePruneMode = ePruneMode.BoundsOverlap:
	set(value):
		mode = value
		notify_property_list_changed()
		emit_changed()

## When enabled, preserves self intersections instead of discarding/replacing it.
@export var keep_self_intersections : bool = false
## Size of each grid cell used by this node.
@export var cell_size : float = 1.0:
	set(value):
		cell_size = value
		emit_changed()
## Attribute name used to read/write prefer on point data.
@export var prefer_attribute : String:
	set(value):
		prefer_attribute = value
		emit_changed()
## Preferred attribute value used as a tie-breaker during pruning.
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
	return name != "keep_self_intersections"
