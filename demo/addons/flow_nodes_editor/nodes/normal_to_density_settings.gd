@tool
class_name NormalToDensityNodeSettings
extends NodeSettings

@export_group("Normal To Density")

enum eDensityMode {
	Set,
	Minimum,
	Maximum,
	Add,
	Multiply,
}

## Reference normal used to evaluate alignment against surface normals.
@export var normal_to_compare : Vector3 = Vector3.UP:
	set(value):
		normal_to_compare = value
		emit_changed()

## Offset applied to offset before writing final output values.
@export var offset : float = 0.0:
	set(value):
		offset = value
		emit_changed()

## Strength/intensity of the effect applied by this node.
@export var strength : float = 1.0:
	set(value):
		strength = value
		emit_changed()

## Selects this node behavior mode (Set, Minimum, Maximum, Add, Multiply).
@export var density_mode : eDensityMode = eDensityMode.Set:
	set(value):
		density_mode = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Normal To Density Settings"
