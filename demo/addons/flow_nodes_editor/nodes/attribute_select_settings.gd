@tool
extends NodeSettings

@export_group("Attribute Select")

enum eOperation {
	## The entry with the smallest value.
	Min,
	## The entry with the largest value.
	Max,
	## The entry at the middle of the sorted values (the lower middle for an even count).
	Median,
}

enum eAxis {
	## x of a vector (scalars use their value).
	X,
	## y of a vector.
	Y,
	## z of a vector.
	Z,
	## w of a 4-component vector.
	W,
	## Vector length.
	Length,
	## Dot product with custom_axis.
	CustomAxis,
}

@export var operation : eOperation = eOperation.Max
## Attribute to select on: numbers (Bool, Int, Int64, Float, Double), vectors (by axis) or Strings (lexicographic).
@export var input_attribute : String = "@last"
@export var axis : eAxis = eAxis.X
@export var custom_axis : Vector4 = Vector4(0, 1, 0, 0)
## Attribute of the single-entry output set holding the selected value ("@Source" keeps the input name).
@export var output_attribute : String = "@Source"
## Int attribute of the output set holding the selected entry's index (empty skips it).
@export var index_attribute : String = "selected_index"

func _init():
	super._init()
	resource_name = "Attribute Select"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [ { "prop": "input_attribute", "port": 0 } ]
