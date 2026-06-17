@tool
extends NodeSettings

# Settings for the Subdivide Segment node.
#
# Splits each input segment/spline span into sub-segments either by a list of
# module lengths (cycled along the span) or by a target sub-segment count, with
# a fit mode controlling how leftover length is handled.

enum eInputMode {
	## Read Path3D splines from a NodePath stream and split each baked segment span.
	SPLINES,
	## Read explicit two-point segments from start/end Vector streams on the input points.
	SEGMENTS,
}

enum eSubdivideMode {
	## Cycle through `module_lengths` along the span.
	MODULE_LENGTHS,
	## Produce exactly `target_count` equal sub-segments.
	TARGET_COUNT,
}

enum eFitMode {
	## Scale each sub-segment so the modules exactly fill the span (lengths used as ratios).
	STRETCH,
	## Keep module lengths as-is; drop the final partial sub-segment that overruns the span.
	CLIP,
	## Keep module lengths as-is; keep the final partial sub-segment (it carries its real, shorter length).
	PAD_ENDS,
}

@export_group("Subdivide Segment")

## How the input span is supplied:
@export var input_mode : eInputMode = eInputMode.SPLINES

## The name of the input NodePath stream containing Path3D spline references.
## Only used when 'input_mode' is set to SPLINES.
@export var spline_stream_attribute : String = "node"

## The distance interval (in meters/units) used to bake the Path3D spline's curve.
## A lower interval increases subdivision resolution. Clamped to a minimum of 0.001.
## Only used when 'input_mode' is set to SPLINES.
@export var bake_interval : float = 4.0

## When true, the entire spline is treated as a single span from the first baked point to the last.
## When false, each interval between consecutive baked points is treated as a separate span to subdivide.
## Only used when 'input_mode' is set to SPLINES. Recommended for grammar fences.
@export var whole_spline_as_span : bool = true

## The name of the input Vector stream containing segment start positions.
## Only used when 'input_mode' is set to SEGMENTS.
@export var segment_start_attribute : String = "segment_start"

## The name of the input Vector stream containing segment end positions.
## Only used when 'input_mode' is set to SEGMENTS.
@export var segment_end_attribute : String = "segment_end"

## How each span is divided into sub-segments:
@export var subdivide_mode : eSubdivideMode = eSubdivideMode.MODULE_LENGTHS

## A list of module lengths to cycle through along each span. Only positive values are used.
## There must be at least one positive value in the array.
## Only used when 'subdivide_mode' is set to MODULE_LENGTHS.
@export var module_lengths : PackedFloat32Array = PackedFloat32Array([4.0])

## The number of equal-length sub-segments to produce per span. Clamped to a minimum of 1.
## Only used when 'subdivide_mode' is set to TARGET_COUNT.
@export var target_count : int = 4

## How leftover length is handled when the modules do not exactly fill the span length:
@export var fit_mode : eFitMode = eFitMode.STRETCH

## The cross-section dimensions (X and Y) written into size.x and size.y of each emitted point.
## The generated sub-segment length is written into the z component (representing the long axis).
@export var cross_section_size : Vector2 = Vector2.ONE

@export_group("Output Attributes")

## The output attribute name (Float) to store each sub-segment's length.
## If left blank or empty, this stream is not registered.
@export var out_length_attribute : String = "length"

## The output attribute name (Int) to store the zero-based sub-segment index within its parent span.
## If left blank or empty, this stream is not registered.
@export var out_segment_index_attribute : String = "segment_index"

## The output attribute name (Float) to store the normalized start ratio (0.0 to 1.0) along the span.
## If left blank or empty, this stream is not registered.
@export var out_t_start_attribute : String = "t_start"

## The output attribute name (Float) to store the normalized end ratio (0.0 to 1.0) along the span.
## If left blank or empty, this stream is not registered.
@export var out_t_end_attribute : String = "t_end"

func _init():
	super._init()
	resource_name = "Subdivide Segment Settings"
