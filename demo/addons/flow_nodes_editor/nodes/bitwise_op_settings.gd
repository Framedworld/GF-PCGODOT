@tool
extends NodeSettings

@export_group("Bitwise Op")

enum eOperation {
	## A & B
	And,
	## A | B
	Or,
	## A ^ B
	Xor,
	## ~A
	Not,
	## A << B
	ShiftLeft,
	## A >> B (arithmetic: the sign is kept)
	ShiftRight,
}

enum eOutputType {
	## Int64 when either operand is Int64, else Int (UE computes in 64 bits).
	SameAsInput,
	## 32-bit Int: the result keeps its low 32 bits.
	Int,
	## 64-bit Int64.
	Int64,
}

@export var operation : eOperation = eOperation.And:
	set(value):
		if operation != value:
			operation = value
			notify_property_list_changed()
## Operand A: a Bool, Int or Int64 attribute.
@export var in_nameA : String = "@last"
## Operand B: an attribute read from In B when connected (and holding it), else from In A.
@export var in_nameB : String = "@last"
## Use constant_b instead of the In B attribute.
@export var use_constant_b : bool = true:
	set(value):
		if use_constant_b != value:
			use_constant_b = value
			notify_property_list_changed()
@export var constant_b : int = 1
@export var output_type : eOutputType = eOutputType.SameAsInput
## Attribute written with the result ("@Source" writes back to A).
@export var out_name : String = "bitwise"

func _init():
	super._init()
	resource_name = "Bitwise Op"

func exposeParam( name : String ) -> bool:
	match name:
		"in_nameB":
			return operation != eOperation.Not and not use_constant_b
		"use_constant_b":
			return operation != eOperation.Not
		"constant_b":
			return operation != eOperation.Not and use_constant_b
	return true

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [ { "prop": "in_nameA", "port": 0 }, { "prop": "in_nameB", "port": 0 } ]
