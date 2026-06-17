@tool
class_name AddAttributeNodeSettings
extends NodeSettings

@export_group("Add Attribute")

## Attribute domain (UE @Data / @Points parity).
## PerPoint: creates a per-point stream (broadcast-filled, historical behavior).
## PerData: writes a single per-data attribute into Data.data_attrs, addressable
## downstream via the "@data.<name>" selector.
enum eDomain {
	## Creates a per-point stream of values matching the input point count.
	PerPoint,
	## Writes a single per-data metadata value under the Data container's `data_attrs`.
	PerData,
}

## Human-readable name/key used by this node when creating or selecting entries.
@export var name : String = "new_attr"
## Determines whether the attribute is created as a per-point stream or a single per-data value.
@export var domain : eDomain = eDomain.PerPoint
## Data type used when creating streams/attributes or interpreting values.
@export var data_type : FlowData.DataType = FlowData.DataType.Float:
	set(new_value):
		data_type = new_value
		notify_property_list_changed()

## Constant bool value used when the selected math/expression mode requires it.
@export var cte_bool: bool = false
## Constant int value used when the selected math/expression mode requires it.
@export var cte_int : int = 0
## Constant floatl value used when the selected math/expression mode requires it.
@export var cte_float : float = 0.0
## Constant vector value used when the selected math/expression mode requires it.
@export var cte_vector : Vector3 = Vector3.ZERO
## Constant color value used when the selected math/expression mode requires it.
@export var cte_color : Color = Color.WHITE
## Constant resource value used when the selected math/expression mode requires it.
@export var cte_resource : Resource
## Constant string value used when the selected math/expression mode requires it.
@export var cte_string : String = ""

func _init():
	super._init()
	resource_name = "Add Attribute"

func exposeParam( name : String ):
	var name_lc = FlowData.DataType.keys()[ data_type ].to_lower()
	if name.begins_with( "cte_" ):
		return name == "cte_" + name_lc
	return true
