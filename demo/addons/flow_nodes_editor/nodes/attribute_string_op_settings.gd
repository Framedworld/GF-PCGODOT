@tool
extends NodeSettings

@export_group("Attribute String Op")

enum eOperation {
	## A + B (String).
	Append,
	## B + A (String).
	Prepend,
	## A with every occurrence of B replaced by C (String).
	Replace,
	## A in upper case (String).
	ToUpper,
	## A in lower case (String).
	ToLower,
	## A contains B (Bool).
	Contains,
	## A starts with B (Bool).
	StartsWith,
	## A ends with B (Bool).
	EndsWith,
	## The Format pattern with {0} = A, {1} = B, {2} = C, {index} = point index and {name} = the value of attribute name (String).
	Format,
	## Number of characters of A (Int).
	Length,
	## A without leading and trailing whitespace (String).
	Trim,
	## C characters of A starting at character B (B and C are integers; C < 0 means to the end) (String).
	Substring,
}

@export var operation : eOperation = eOperation.Append:
	set(value):
		if operation != value:
			operation = value
			notify_property_list_changed()
## Operand A. Non-String attributes are converted to text first (numbers, vectors, true/false).
@export var in_nameA : String = "@last"
## Operand B attribute (read from In B when connected and holding it, else In A); empty uses constant_b.
@export var in_nameB : String = ""
@export var constant_b : String = ""
## Operand C attribute; empty uses constant_c.
@export var in_nameC : String = ""
@export var constant_c : String = ""
## Pattern for Format.
@export var format_pattern : String = "{0}_{1}"
## Contains / StartsWith / EndsWith / Replace match case unless this is off.
@export var case_sensitive : bool = true
## Attribute written with the result ("@Source" writes back to A).
@export var out_name : String = "string_op"

func _init():
	super._init()
	resource_name = "Attribute String Op"

func usesB() -> bool:
	return operation in [ eOperation.Append, eOperation.Prepend, eOperation.Replace, eOperation.Contains,
		eOperation.StartsWith, eOperation.EndsWith, eOperation.Format, eOperation.Substring ]

func usesC() -> bool:
	return operation in [ eOperation.Replace, eOperation.Format, eOperation.Substring ]

func exposeParam( name : String ) -> bool:
	match name:
		"in_nameB", "constant_b":
			return usesB()
		"in_nameC", "constant_c":
			return usesC()
		"format_pattern":
			return operation == eOperation.Format
		"case_sensitive":
			return operation in [ eOperation.Replace, eOperation.Contains, eOperation.StartsWith, eOperation.EndsWith ]
	return true

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [ { "prop": "in_nameA", "port": 0 }, { "prop": "in_nameB", "port": 0 }, { "prop": "in_nameC", "port": 0 } ]
