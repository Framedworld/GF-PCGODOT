@tool
class_name NormalToDensityNodeSettings
extends NodeSettings

@export_group("Normal To Density")

enum eDensityMode {
	## Overwrites density with normal alignment match.
	Set,
	## Minimum selection filter.
	Minimum,
	## Maximum selection filter.
	Maximum,
	## Adds alignment match to density.
	Add,
	## Multiplies density by alignment match.
	Multiply,
}

## The target normal direction Vector3 to compare against.
@export var normal_to_compare : Vector3 = Vector3.UP:
	set(value):
		normal_to_compare = value
		emit_changed()

## Angular threshold offset from comparison vector.
@export var offset : float = 0.0:
	set(value):
		offset = value
		emit_changed()

## Multiplier strength applied to match result.
@export var strength : float = 1.0:
	set(value):
		strength = value
		emit_changed()

## Blend mode to apply matching result back to density attribute.
@export var density_mode : eDensityMode = eDensityMode.Set:
	set(value):
		density_mode = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Normal To Density Settings"
