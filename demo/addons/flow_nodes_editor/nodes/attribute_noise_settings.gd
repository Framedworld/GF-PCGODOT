@tool
class_name AttributeNoiseNodeSettings
extends NodeSettings

@export_group("Attribute Noise")

enum eMode {
	Set,
	Minimum,
	Maximum,
	Add,
	Multiply,
}

## Attribute key this node reads or updates for target attribute.
@export var target_attribute : String = "density":
	set(value):
		target_attribute = value.strip_edges()
		emit_changed()

## Selects which processing mode this node uses (similar to UE PCG node modes).
@export var mode : eMode = eMode.Set:
	set(value):
		mode = value
		emit_changed()

## Lower clamp/range endpoint for sampled noise values.
@export var noise_min : float = 0.0:
	set(value):
		noise_min = value
		emit_changed()

## Upper clamp/range endpoint for sampled noise values.
@export var noise_max : float = 1.0:
	set(value):
		noise_max = value
		emit_changed()

## Inverts source values before applying noise blending.
@export var invert_source : bool = false:
	set(value):
		invert_source = value
		emit_changed()

## Clamps final output to the configured min/max range.
@export var clamp_result : bool = true:
	set(value):
		clamp_result = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Attribute Noise Settings"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "target_attribute", "port": 0 },
	]
