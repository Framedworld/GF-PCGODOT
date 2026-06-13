@tool
extends NodeSettings

@export_group("Attribute Filter Range")
## Name of the attribute this node reads from or writes to.
@export var attribute_name : String = "":
	set(value):
		attribute_name = value.strip_edges()
		emit_changed()

## Lower bound used by this node for value.
@export var min_value : float = 0.0:
	set(value):
		min_value = value
		emit_changed()

## Upper bound used by this node for value.
@export var max_value : float = 1.0:
	set(value):
		max_value = value
		emit_changed()

## If enabled, values equal to min_value are considered inside the range.
@export var inclusive_min : bool = true:
	set(value):
		inclusive_min = value
		emit_changed()

## If enabled, values equal to max_value are considered inside the range.
@export var inclusive_max : bool = true:
	set(value):
		inclusive_max = value
		emit_changed()

## Toggles whether this node uses absolute value instead of default behavior.
@export var use_absolute_value : bool = false:
	set(value):
		use_absolute_value = value
		emit_changed()

@export_group("String Match")
## String comparison mode used for text filtering (exact/contains/pattern).
@export var string_match_mode : bool = false:
	set(value):
		string_match_mode = value
		emit_changed()

## Accepted string values/patterns used by string-based filters.
@export var string_match_values : String = "":
	set(value):
		string_match_values = value
		emit_changed()

## If enabled, text matching treats uppercase/lowercase as different values.
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
