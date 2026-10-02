@tool
extends NodeSettings

@export_group("Compare Op")

enum eOperation {
	## A == B (within Tolerance for real numbers and vector components).
	Equal,
	## A != B (outside Tolerance).
	NotEqual,
	## A > B
	Greater,
	## A >= B
	GreaterOrEqual,
	## A < B
	Less,
	## A <= B
	LessOrEqual,
}

enum eVectorMode {
	## The relation must hold for every component (UE behaviour for equality).
	AllComponents,
	## The relation must hold for at least one component.
	AnyComponent,
	## Compare the vector lengths.
	Length,
}

@export var operation : eOperation = eOperation.Equal
## First operand: any attribute selector.
@export var in_nameA : String = "@last"
## Second operand: an attribute read from In B when connected (and holding it), else from In A.
@export var in_nameB : String = "@last"
## Use the constant below instead of the In B attribute.
@export var use_constant_b : bool = false:
	set(value):
		if use_constant_b != value:
			use_constant_b = value
			notify_property_list_changed()
## Constant second operand, read as the type of A: a number, true/false, text,
## "x,y,z" components (one number broadcasts) or a literal such as Vector3(1, 2, 3).
@export var constant_b : String = "0"
## Equality tolerance for real numbers and vector components (UE default is 1e-4 style).
@export var tolerance : float = 0.0001
## How vector-like operands (Vector2, Vector, Vector4, Color, Quaternion) compare.
@export var vector_mode : eVectorMode = eVectorMode.AllComponents
## String comparisons are case-sensitive unless this is off.
@export var case_sensitive : bool = true
## Bool attribute written with the result.
@export var out_name : String = "compare"

func _init():
	super._init()
	resource_name = "Compare Op"

func exposeParam( name : String ) -> bool:
	if name == "constant_b":
		return use_constant_b
	if name == "in_nameB":
		return not use_constant_b
	return true

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [ { "prop": "in_nameA", "port": 0 }, { "prop": "in_nameB", "port": 0 } ]
