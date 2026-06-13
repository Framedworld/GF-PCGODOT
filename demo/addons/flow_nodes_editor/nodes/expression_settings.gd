@tool
class_name ExpressionNodeSettings
extends NodeSettings

@export_group("Expression")

## Expression string evaluated per element to produce outputs.
@export var expression : String
## Name of the output attribute this node writes.
@export var out_name : String = "expr"
## If enabled, exposes array values as script parameters in the expression context.
@export var expose_arrays : bool = false
## Comma-separated argument names exposed to the expression evaluator.
@export var args : Dictionary = {}

func _init():
	super._init()
	resource_name = "Expression"
