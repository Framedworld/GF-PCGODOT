@tool
extends NodeSettings

@export_group("Trig Op")

enum eOperation {
	## sin(A), A in radians.
	Sin,
	## cos(A), A in radians.
	Cos,
	## tan(A), A in radians.
	Tan,
	## asin(A) in radians (A clamped to [-1, 1]).
	Asin,
	## acos(A) in radians (A clamped to [-1, 1]).
	Acos,
	## atan(A) in radians.
	Atan,
	## atan2(A, B) in radians: A is y, B is x.
	Atan2,
	## A degrees to radians.
	DegToRad,
	## A radians to degrees.
	RadToDeg,
}

@export var operation : eOperation = eOperation.Sin:
	set(value):
		if operation != value:
			operation = value
			notify_property_list_changed()
## Operand A: a numeric attribute (Bool, Int, Int64, Float, Double) or a Vector2/Vector/Vector4 (per component).
@export var in_nameA : String = "@last"
## Operand B for Atan2 (x): an attribute read from In B when connected (and holding it), else from In A.
@export var in_nameB : String = "@last"
## Use constant_b instead of the In B attribute.
@export var use_constant_b : bool = false:
	set(value):
		if use_constant_b != value:
			use_constant_b = value
			notify_property_list_changed()
@export var constant_b : float = 1.0
## Attribute written with the result ("@Source" writes back to A).
@export var out_name : String = "trig"

func _init():
	super._init()
	resource_name = "Trig Op"

func exposeParam( name : String ) -> bool:
	match name:
		"in_nameB":
			return operation == eOperation.Atan2 and not use_constant_b
		"use_constant_b":
			return operation == eOperation.Atan2
		"constant_b":
			return operation == eOperation.Atan2 and use_constant_b
	return true

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [ { "prop": "in_nameA", "port": 0 }, { "prop": "in_nameB", "port": 0 } ]
