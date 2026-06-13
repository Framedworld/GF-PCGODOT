@tool
extends NodeSettings

@export_group("Split Splines")

## Attribute name used to read/write spline stream on point data.
@export var spline_stream_attribute : String = "node"
## Distance between generated samples along the spline when using uniform/grid spacing modes.
@export var uniform_interval : float = 1.0
## Size parameter controlling segment size xy during generation/transforms.
@export var segment_size_xy : Vector2 = Vector2.ONE
## Output attribute name that stores segment index produced by this node.
@export var out_segment_index_attribute : String = "segment_index"
## Output attribute name that stores spline index produced by this node.
@export var out_spline_index_attribute : String = "spline_index"
## Output attribute name that stores start produced by this node.
@export var out_start_attribute : String = "segment_start"
## Output attribute name that stores end produced by this node.
@export var out_end_attribute : String = "segment_end"
## When enabled, also outputs spline ref alongside generated points/data.
@export var include_spline_ref : bool = true
## Output attribute name that stores spline produced by this node.
@export var out_spline_attribute : String = "node"

func _init():
	super._init()
	resource_name = "Split Splines Settings"

func exposeParam(name : String) -> bool:
	if name == "out_spline_attribute":
		return include_spline_ref
	return true
