@tool
extends NodeSettings

@export_group("Load Data Table")

enum eDelimiter {
	Comma,
	Tab,
	Semicolon,
	Pipe,
}

## Scene/resource path used to resolve table.
@export_file("*.csv", "*.tsv", "*.txt") var table_path : String = ""
## Selects this node behavior mode (Comma, Tab, Semicolon, Pipe).
@export var delimiter : eDelimiter = eDelimiter.Comma
## Treats the first CSV row as column names instead of data.
@export var first_row_is_header : bool = true
## Trims leading/trailing whitespace from imported table cells.
@export var trim_values : bool = true
## Attempts to auto-detect value types per column during import.
@export var infer_column_types : bool = true
## When enabled, appends row index to the output data.
@export var add_row_index : bool = true
## Attribute name used to read/write row index on point data.
@export var row_index_attribute : String = "row_index"
## Scene/resource path used to resolve add source.
@export var add_source_path : bool = false
## Attribute name used to read/write source path on point data.
@export var source_path_attribute : String = "source_path"

func _init():
	super._init()
	resource_name = "Load Data Table Settings"

func exposeParam(name : String) -> bool:
	if name == "row_index_attribute":
		return add_row_index
	if name == "source_path_attribute":
		return add_source_path
	return true
