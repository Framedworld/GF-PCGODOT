@tool
class_name SplitPointsNodeSettings
extends NodeSettings

enum eAxis {
	## Split across the point's local X axis.
	X,
	## Split across the point's local Y axis (Godot up; Unreal's Z).
	Y,
	## Split across the point's local Z axis.
	Z,
}

enum eMode {
	## Unreal behaviour: transforms are untouched, only bounds_min/bounds_max change,
	## so each half keeps the original pivot.
	KeepTransform,
	## Each half moves to the center of its own box and gets symmetric bounds.
	## Points without bounds streams stay in the size-as-extent model: the split
	## axis of `size` is scaled by the half's fraction and no bounds are written.
	Recenter,
}

@export_group("Split Points")

## Axis of the point's local bounds that is cut.
@export var split_axis : eAxis = eAxis.Y
## Where the cut happens along the axis, from 0 (bounds min) to 1 (bounds max).
@export_range(0.0, 1.0) var split_position : float = 0.5
## Optional numeric attribute giving a per-point split position (0..1, clamped).
## Overrides split_position when set; a missing attribute is an error.
@export var split_position_attribute : String = ""
## How transforms and bounds of the two halves are written.
@export var mode : eMode = eMode.KeepTransform
## Keep every input attribute on both halves. When off, only the point
## properties survive (position, rotation, rotation_quat, size, bounds, density,
## seed, steepness, normal).
@export var inherit_attributes : bool = true
## Optional Int attribute written on both outputs: 0 on the "Before Split"
## half, 1 on the "After Split" half. Empty disables it.
@export var side_attribute : String = ""
## Optional Float attribute holding the fraction of the original extent each
## half covers along the split axis. Empty disables it.
@export var fraction_attribute : String = ""

func _init():
	super._init()
	resource_name = "Split Points Settings"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "split_position_attribute", "port": 0 },
	]
