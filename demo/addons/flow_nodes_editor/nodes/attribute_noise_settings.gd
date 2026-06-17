@tool
class_name AttributeNoiseNodeSettings
extends NodeSettings

@export_group("Attribute Noise")

enum eMode {
	## Directly overwrites the target attribute with the generated noise value.
	Set,
	## Applies a minimum selection filter between the existing value and the noise value.
	Minimum,
	## Applies a maximum selection filter between the existing value and the noise value.
	Maximum,
	## Adds the generated noise value to the existing attribute value.
	Add,
	## Multiplies the existing attribute value by the generated noise value.
	Multiply,
}

## The name of the attribute to modify or create.
@export var target_attribute : String = "density":
	set(value):
		target_attribute = value.strip_edges()
		emit_changed()

## The mathematical operation used to combine the noise value with the existing attribute.
@export var mode : eMode = eMode.Set:
	set(value):
		mode = value
		emit_changed()

## The minimum value of the random noise range.
@export var noise_min : float = 0.0:
	set(value):
		noise_min = value
		emit_changed()

## The maximum value of the random noise range.
@export var noise_max : float = 1.0:
	set(value):
		noise_max = value
		emit_changed()

## If enabled, inverts the source attribute value (1.0 - value) before applying the noise blend.
@export var invert_source : bool = false:
	set(value):
		invert_source = value
		emit_changed()

## If enabled, clamps the final output value to the [0.0, 1.0] range.
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
