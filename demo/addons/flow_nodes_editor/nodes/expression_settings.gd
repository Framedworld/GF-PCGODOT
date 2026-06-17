@tool
class_name ExpressionNodeSettings
extends NodeSettings

@export_group("Expression")

## The mathematical/logical expression string to evaluate per point. Example: 'x + 2 * position.y'.
@export var expression : String
## The name of the attribute stream to write the expression evaluation result to.
@export var out_name : String = "expr"
## If enabled, exposes point attribute streams as array variables in the expression evaluator, allowing aggregate functions.
@export var expose_arrays : bool = false
## Optional key-value parameters exposed as static constants/arguments in the expression context.
@export var args : Dictionary = {}

func _init():
	super._init()
	resource_name = "Expression"
