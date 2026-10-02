@tool
class_name FilterDataByIndexNodeSettings
extends NodeSettings

enum eMode {
	## Select whole data entries (the bulks on the input pin) by their index,
	## like Unreal's Filter Data By Index.
	DataEntries,
	## Select points inside each data entry by their index.
	Points,
}

@export_group("Filter Data By Index")

## What the indices address.
@export var mode : eMode = eMode.DataEntries
## Comma-separated indices and ranges. "3" is one index, "2:5" is 2, 3 and 4
## (end excluded), ":3" and "5:" are open ranges, and negative values count
## from the end ("-1" is the last entry, "-2:" the last two). Indices outside
## the input are ignored.
@export var selected_indices : String = "0"
## Swap the outputs: the selected entries go to "Outside Filter".
@export var invert : bool = false

func _init():
	super._init()
	resource_name = "Filter Data By Index Settings"
