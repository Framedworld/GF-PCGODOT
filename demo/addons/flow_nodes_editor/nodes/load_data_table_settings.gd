@tool
extends NodeSettings

@export_group("Load Data Table")

enum eDelimiter {
	## Column values are separated by a comma (,).
	Comma,
	## Column values are separated by a tab character.
	Tab,
	## Column values are separated by a semicolon (;).
	Semicolon,
	## Column values are separated by a vertical bar (|).
	Pipe,
}

## The file path to the delimited text file (such as CSV or TSV) to load.
@export_file("*.csv", "*.tsv", "*.txt") var table_path : String = ""
## The character delimiter used to separate column values.
@export var delimiter : eDelimiter = eDelimiter.Comma
## If enabled, treats the first row of the file as header labels.[br]
## If disabled, headers are automatically generated as 'column_0', 'column_1', etc.
## Spaces in headers are replaced with underscores, and duplicate headers are made unique.
@export var first_row_is_header : bool = true
## If enabled, removes leading and trailing whitespace from parsed cell values.
@export var trim_values : bool = true
## If enabled, automatically casts columns to Bool, Int, Float, or Vector3 if all column values match that type.[br]
## If disabled, all columns are registered as String streams.
@export var infer_column_types : bool = true
## If enabled, generates a sequential zero-based row index attribute stream.
@export var add_row_index : bool = true
## The name of the output Int stream to store the row index.
## Only used when 'add_row_index' is enabled.
@export var row_index_attribute : String = "row_index"
## If enabled, records the file path of the source delimited file as a metadata attribute stream.
@export var add_source_path : bool = false
## The name of the output String stream to store the source file path.
## Only used when 'add_source_path' is enabled.
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
