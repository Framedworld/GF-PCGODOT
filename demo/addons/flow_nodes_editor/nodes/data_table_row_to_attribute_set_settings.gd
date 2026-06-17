@tool
extends NodeSettings

@export_group("Data Table Row To Attribute Set")

enum eSelectionMode {
	## Selects table rows using a direct numeric index.
	RowIndex,
	## Selects table rows by matching a point attribute to a table key value.
	MatchAttribute,
}

## Determines how a row is selected from the data table.
@export var selection_mode : eSelectionMode = eSelectionMode.RowIndex:
	set(value):
		value = clampi(value, 0, eSelectionMode.size() - 1)
		selection_mode = value
		notify_property_list_changed()

## The 0-based index of the table row to retrieve.
@export var row_index : int = 0
## The name of the attribute stream on the input point data to compare against the table keys.
@export var key_attribute : String = "name"
## The key string value to look up and match in the data table.
@export var key_value : String = ""
## If enabled, retrieves and merges all matching rows. If disabled, retrieves only the first matching row.
@export var include_all_matches : bool = false
## If enabled, performs case-sensitive key matching comparisons.
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
