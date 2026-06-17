@tool
extends NodeSettings

@export_group("Attribute Filter Range")
## The name of the attribute stream to filter.
@export var attribute_name : String = "":
	set(value):
		attribute_name = value.strip_edges()
		emit_changed()

## The lower bound of the numeric range filter.
@export var min_value : float = 0.0:
	set(value):
		min_value = value
		emit_changed()

## The upper bound of the numeric range filter.
@export var max_value : float = 1.0:
	set(value):
		max_value = value
		emit_changed()

## If enabled, points with attribute values exactly equal to min_value will be kept.
@export var inclusive_min : bool = true:
	set(value):
		inclusive_min = value
		emit_changed()

## If enabled, points with attribute values exactly equal to max_value will be kept.
@export var inclusive_max : bool = true:
	set(value):
		inclusive_max = value
		emit_changed()

## If enabled, the filter logic is applied to the absolute value of the attribute.
@export var use_absolute_value : bool = false:
	set(value):
		use_absolute_value = value
		emit_changed()

@export_group("String Match")
## If enabled, performs string/pattern matching instead of numeric range filtering.
@export var string_match_mode : bool = false:
	set(value):
		string_match_mode = value
		emit_changed()

## The string values or patterns to match against, separated by commas.
@export var string_match_values : String = "":
	set(value):
		string_match_values = value
		emit_changed()

## If enabled, text comparisons will be case-sensitive.
@export var case_sensitive : bool = false:
	set(value):
		case_sensitive = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Attribute Filter Range Settings"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "attribute_name", "port": 0 },
	]
