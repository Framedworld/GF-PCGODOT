@tool
class_name FilterNodeSettings
extends NodeSettings

@export_group("Filter")

enum eCondition {
	## Checks if Operand A is equal to Operand B.
	Equal,
	## Checks if Operand A is not equal to Operand B.
	NotEqual,
	## Checks if Operand A is strictly greater than Operand B.
	Greater,
	## Checks if Operand A is greater than or equal to Operand B.
	GreaterOrEqual,
	## Checks if Operand A is strictly less than Operand B.
	Less,
	## Checks if Operand A is less than or equal to Operand B.
	LessOrEqual,
	## Checks if Operand A is within a threshold distance from Operand B.
	AlmostEqual,
	## Logical AND combination.
	LogicalAND,
	## Logical OR combination.
	LogicalOR,
	## Logical XOR combination.
	LogicalXOR,
	## Checks if Operand A is null.
	IsNull,
}

## The name of the first attribute stream to compare.
@export var in_nameA : String = "@last"
## The comparison operator to evaluate between Operand A and Operand B.
@export var condition : eCondition = eCondition.Equal
## The name of the second attribute stream to compare, or a constant value (e.g. '0.5', 'true').
@export var in_nameB : String = "@last"
## The maximum allowed difference for AlmostEqual comparison.
@export var threshold : float = 0.1

func _init():
	super._init()
	resource_name = "Filter Settings"

func isLogicalOp() -> bool:
	return condition == eCondition.LogicalAND \
		|| condition == eCondition.LogicalOR  \
		|| condition == eCondition.LogicalXOR
