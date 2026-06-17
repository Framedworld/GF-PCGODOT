@tool
class_name MathOpNodeSettings
extends NodeSettings

@export_group("Math Op")

enum eOperation {
	## Adds Operand A to Operand B.
	Add,
	## Subtracts Operand B from Operand A.
	Substract,
	## Multiplies Operand A by Operand B.
	Multiply,
	## Divides Operand A by Operand B.
	Divide,
	Negate,
	# 4
	## Computes the absolute value of Operand A.
	Absolute,
	## Clamps Operand A to the [0.0, 1.0] range.
	Saturate,
	## Floors Operand A to the nearest integer float.
	Floor,
	## Floors Operand A and casts the result to an integer.
	FloorAsInt,
	## Computes Operand A modulo Operand B.
	Modulo,
	## Computes integer modulo A % B.
	ModuloInt,
	## Extracts the fractional part of Operand A.
	Frac,
	## Returns the maximum of Operand A and Operand B.
	Max,
	## Returns the minimum of Operand A and Operand B.
	Min,
	## Computes 1.0 minus Operand A.
	OneMinus,
	## Computes Operand A raised to the power of Operand B.
	Pow,
	## Rounds Operand A to the nearest integer value.
	Round,
	## Returns the sign of Operand A (-1, 0, or 1).
	Sign,
	## Computes the square root of Operand A.
	Sqrt,
}

## The mathematical operation to perform.
@export var operation : eOperation = eOperation.Add:
	set(value):
		if operation != value:
			operation = value
			# This triggers the refresh of the property list in the property editor
			notify_property_list_changed()

## The first input attribute stream or value.
@export var in_nameA : String = "@last"
## The second input attribute stream or value.
@export var in_nameB : String = "@last"
## The output attribute stream name in which to store the math result.
@export var out_name : String

func _init():
	super._init()
	resource_name = "Math Op"

func isSingleArgument( ) -> bool:
	return operation == eOperation.Absolute or \
	   operation == eOperation.Floor or \
	   operation == eOperation.FloorAsInt or \
	   operation == eOperation.Negate or \
	   operation == eOperation.Saturate or \
	   operation == eOperation.OneMinus or \
	   operation == eOperation.Sign or \
	   operation == eOperation.Sqrt or \
	   operation == eOperation.Frac or \
	   operation == eOperation.Round or \
	   false

func exposeParam( name : String ) -> bool:
	if name == "in_nameB":
		return not isSingleArgument()
	return true
