@tool
extends NodeSettings

@export_group("Boolean")

enum eOperation {
	And,
	Not,
	Or,
	Xor,
	Imply,
	Nand,
	Nimply,
	Nor,
	Xnor,
}

## The boolean operation to perform.
@export var operation : eOperation = eOperation.And:
	set(value):
		value = clampi(value, 0, eOperation.size() - 1)
		if operation != value:
			operation = value
			notify_property_list_changed()

## Name of the first input attribute to read from.
@export var in_nameA : String = "@last":
	set(value):
		in_nameA = value.strip_edges()
		emit_changed()
## Name of the second input attribute to read from.
@export var in_nameB : String = "@last":
	set(value):
		in_nameB = value.strip_edges()
		emit_changed()
## Toggles whether this node uses constant b instead of default behavior.
@export var use_constant_b : bool = false:
	set(value):
		if use_constant_b != value:
			use_constant_b = value
			notify_property_list_changed()
## If enabled, evaluates Operand A against a constant value instead of another attribute stream.
@export var constant_b : bool = false:
	set(value):
		constant_b = value
		emit_changed()
## The name of the output boolean stream to write the results into.
@export var out_name : String = "bool_out":
	set(value):
		out_name = value.strip_edges()
		emit_changed()

func _init():
	super._init()
	resource_name = "Boolean Settings"

func isSingleArgument() -> bool:
	return operation == eOperation.Not

func exposeParam(name : String) -> bool:
	if name == "in_nameB" or name == "use_constant_b":
		return not isSingleArgument()
	if name == "constant_b":
		return not isSingleArgument() and use_constant_b
	return true
