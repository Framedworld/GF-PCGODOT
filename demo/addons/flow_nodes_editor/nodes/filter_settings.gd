@tool
class_name FilterNodeSettings
extends NodeSettings

@export_group("Filter")

enum eCondition {
	Equal,
	NotEqual,
	Greater,
	GreaterOrEqual,
	Less,
	LessOrEqual,
	AlmostEqual,
	LogicalAND,
	LogicalOR,
	LogicalXOR,
	IsNull
}

## Name of the first input attribute to read from.
@export var in_nameA : String = "@last"
## Selects this node behavior mode (Equal, NotEqual, Greater, GreaterOrEqual, Less, LessOrEqual, AlmostEqual, LogicalAND, LogicalOR, LogicalXOR, IsNull).
@export var condition : eCondition = eCondition.Equal
## Name of the second input attribute to read from.
@export var in_nameB : String = "@last"
## Threshold used to decide when threshold passes/fails the condition.
@export var threshold : float = 0.1

func _init():
	super._init()
	resource_name = "Filter Settings"

func isLogicalOp() -> bool:
	return condition == eCondition.LogicalAND \
		|| condition == eCondition.LogicalOR  \
		|| condition == eCondition.LogicalXOR
