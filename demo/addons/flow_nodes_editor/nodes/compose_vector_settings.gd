@tool
class_name ComposeVectorNodeSettings
extends NodeSettings

@export_group("Compose Vector")
## The attribute stream name to read the Vector's X component from.
@export var x_attribute: String = ""
## The attribute stream name to read the Vector's Y component from.
@export var y_attribute: String = ""
## The attribute stream name to read the Vector's Z component from.
@export var z_attribute: String = ""
## The fallback Vector3 value to use for components whose attributes are missing or unspecified.
@export var default_value: Vector3 = Vector3.ONE
## The name of the output Vector3 attribute stream to write to.
@export var out_attribute: String = "size"

enum eOutputType {
	## Vector3 (historical behaviour).
	Vector,
	## Vector2 from X and Y.
	Vector2,
	## Vector4 from X, Y, Z and W.
	Vector4,
}

## Output type: Vector (3 components, the default), Vector2 (x, y) or Vector4 (x, y, z, w).
@export var output_type : eOutputType = eOutputType.Vector
## The attribute stream name to read the W component from (Vector4 output only).
@export var w_attribute: String = ""
## The fallback W component (Vector4 output only).
@export var default_w: float = 0.0

func _init():
	super._init()
	resource_name = "Compose Vector Settings"
