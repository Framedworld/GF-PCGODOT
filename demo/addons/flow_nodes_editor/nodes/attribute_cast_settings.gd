@tool
extends NodeSettings

const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

@export_group("Attribute Cast")

## The attribute to convert. Accepts every selector (@last, $Density, position.x, @data.name).
@export var input_attribute : String = "@last"
## The attribute to write. "@Source" (or empty) writes back to the input attribute, changing its type.
@export var output_attribute : String = "@Source"
## The type to convert to.
@export var output_type : FlowData.DataType = FlowData.DataType.Float
## How Float / Double values become Int / Int64. Truncate (toward zero) matches UE.
@export var float_to_int : Ops.eFloatToInt = Ops.eFloatToInt.Truncate
## What happens when an Int64 (or a converted real) does not fit in a 32-bit Int.
## Wrap keeps the low 32 bits (UE static_cast behaviour); Clamp saturates.
@export var int_overflow : Ops.eIntOverflow = Ops.eIntOverflow.Wrap
## Vector-like to scalar casts are refused by default (UE behaviour). First Component keeps x,
## Length uses the vector length.
@export var vector_to_scalar : Ops.eVectorToScalar = Ops.eVectorToScalar.Error

func _init():
	super._init()
	resource_name = "Attribute Cast"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [ { "prop": "input_attribute", "port": 0 } ]
