@tool
extends NodeSettings

@export_group("Merge Attributes")

enum eMode {
	## Concatenate the entries of every input (row append), with the union of their attributes.
	Append,
	## Join the attributes of every input side by side, entry by entry (column merge). Every input
	## must have the same entry count, or one entry (broadcast). A later input wins on a name clash.
	ByIndex,
}

@export var mode : eMode = eMode.Append
## Append: when two inputs give one attribute different numeric types, promote to the wider type
## (Bool < Int < Int64, Float < Double, Int64 + Float = Double) instead of failing.
@export var promote_numeric_types : bool = true

func _init():
	super._init()
	resource_name = "Merge Attributes"
