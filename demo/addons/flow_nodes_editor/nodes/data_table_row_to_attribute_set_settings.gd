@tool
extends NodeSettings

@export_group("Data Table Row To Attribute Set")

enum eSelectionMode {
	RowIndex,
	MatchAttribute,
}

## Selects this node behavior mode (RowIndex, MatchAttribute).
@export var selection_mode : eSelectionMode = eSelectionMode.RowIndex:
	set(value):
		value = clampi(value, 0, eSelectionMode.size() - 1)
		selection_mode = value
		notify_property_list_changed()

## Row index used to fetch a specific table row.
@export var row_index : int = 0
## Attribute name used to read/write key on point data.
@export var key_attribute : String = "name"
## Key value used to find a matching row when key-based lookup is selected.
@export var key_value : String = ""
## When enabled, also outputs all matches alongside generated points/data.
@export var include_all_matches : bool = false
## If enabled, text matching treats uppercase/lowercase as different values.
@export var case_sensitive : bool = false

func _init():
	super._init()
	resource_name = "Data Table Row To Attribute Set Settings"

func exposeParam(name : String) -> bool:
	if name == "row_index":
		return selection_mode == eSelectionMode.RowIndex
	if name == "key_attribute" or name == "key_value" or name == "include_all_matches" or name == "case_sensitive":
		return selection_mode == eSelectionMode.MatchAttribute
	return true
