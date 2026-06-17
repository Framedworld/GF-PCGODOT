@tool
extends NodeSettings

@export_group("Split Splines")

## Attribute stream name containing Path3D spline references.
@export var spline_stream_attribute : String = "node"
## Walk distance spacing between generated split points.
@export var uniform_interval : float = 1.0
## Size dimensions (X, Y) assigned to split points.
@export var segment_size_xy : Vector2 = Vector2.ONE
## Output integer attribute stream name storing split segment index.
@export var out_segment_index_attribute : String = "segment_index"
## Output integer attribute stream name storing source spline index.
@export var out_spline_index_attribute : String = "spline_index"
## Output boolean attribute stream name flagging start points of splines.
@export var out_start_attribute : String = "segment_start"
## Output boolean attribute stream name flagging end points of splines.
@export var out_end_attribute : String = "segment_end"
## If enabled, outputs references back to source spline nodes.
@export var include_spline_ref : bool = true
## Output attribute stream name storing spline references.
@export var out_spline_attribute : String = "node"

func _init():
	super._init()
	resource_name = "Split Splines Settings"

func exposeParam(name : String) -> bool:
	if name == "out_spline_attribute":
		return include_spline_ref
	return true
