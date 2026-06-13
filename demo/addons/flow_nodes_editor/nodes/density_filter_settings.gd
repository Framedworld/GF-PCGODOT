@tool
class_name DensityFilterNodeSettings
extends "res://addons/flow_nodes_editor/nodes/attribute_filter_range_settings.gd"

# Density Filter is Attribute Filter Range hardwired to the density stream.
# The range comes from lower_bound/upper_bound (kept in sync with the parent's
# min_value/max_value); the parent's own knobs are hidden from the inspector.

const _hidden_parent_props : Array[String] = [
	"attribute_name", "min_value", "max_value",
	"inclusive_min", "inclusive_max", "use_absolute_value",
	"string_match_mode", "string_match_values", "case_sensitive",
]

@export_group("Density Filter")
## Minimum allowed value for density; points below this threshold are filtered out (unless inverted).
@export var lower_bound : float = 0.5:
	set(value):
		lower_bound = value
		min_value = value
		emit_changed()

## Maximum allowed value for density; points above this threshold are filtered out (unless inverted).
@export var upper_bound : float = 1.0:
	set(value):
		upper_bound = value
		max_value = value
		emit_changed()

## Inverts the range test so points outside [lower_bound, upper_bound] are kept instead.
@export var invert_filter : bool = false:
	set(value):
		invert_filter = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Density Filter Settings"
	attribute_name = FlowData.AttrDensity
	min_value = lower_bound
	max_value = upper_bound

func _validate_property(property : Dictionary) -> void:
	if property.name in _hidden_parent_props:
		property.usage &= ~PROPERTY_USAGE_EDITOR

# The filtered attribute is hardwired to density — no selector dropdown.
func _get_attribute_selector_props() -> Array[Dictionary]:
	return []
