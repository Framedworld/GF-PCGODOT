@tool
class_name GraphInputParameter
extends Resource

# An graph input with has a type and a constant value

@export var name : String = "arg_name"
@export var data_type : FlowData.DataType = FlowData.DataType.Float:
	set(new_value):
		data_type = new_value
		emit_changed()
		notify_property_list_changed()

# Default value when type is a bool
@export var cte_bool: bool = false
@export var cte_int: int = 0
@export var cte_float : float = 0.0
@export var cte_vector : Vector3 = Vector3.ZERO
@export var cte_resource : Resource
@export var cte_string : String = ""
# Extended types. Each property is named "cte_" + the lowercase DataType key,
# which is how the inspector plugin shows only the one matching data_type.
# Default values are not written to .tres files, so graphs saved before these
# properties existed load unchanged.
@export var cte_color : Color = Color.WHITE
@export var cte_quaternion : Quaternion = Quaternion.IDENTITY
@export var cte_vector2 : Vector2 = Vector2.ZERO
@export var cte_vector4 : Vector4 = Vector4.ZERO
@export var cte_transform : Transform3D = Transform3D.IDENTITY
## 64-bit integer (GDScript ints are 64-bit; stored in a PackedInt64Array).
@export var cte_int64 : int = 0
## Double precision real (GDScript floats are 64-bit; stored in a PackedFloat64Array).
@export var cte_double : float = 0.0

## Name of the property that holds the default value of `type`, or "" when the
## type has no constant (NodeMesh, NodePath, Invalid).
static func value_property_name( type : int ) -> String:
	match type:
		FlowData.DataType.Bool:
			return "cte_bool"
		FlowData.DataType.Int:
			return "cte_int"
		FlowData.DataType.Float:
			return "cte_float"
		FlowData.DataType.Vector:
			return "cte_vector"
		FlowData.DataType.Resource:
			return "cte_resource"
		FlowData.DataType.String:
			return "cte_string"
		FlowData.DataType.Color:
			return "cte_color"
		FlowData.DataType.Quaternion:
			return "cte_quaternion"
		FlowData.DataType.Vector2:
			return "cte_vector2"
		FlowData.DataType.Vector4:
			return "cte_vector4"
		FlowData.DataType.Transform:
			return "cte_transform"
		FlowData.DataType.Int64:
			return "cte_int64"
		FlowData.DataType.Double:
			return "cte_double"
	return ""

func get_default_value():
	var property := value_property_name( data_type )
	if property.is_empty():
		return null
	return get( property )
