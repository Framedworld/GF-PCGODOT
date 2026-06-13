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

## How the input span is supplied.
@export var input_mode : eInputMode = eInputMode.SPLINES

## Attribute name of the Path3D NodePath stream (SPLINES mode).
@export var spline_stream_attribute : String = "node"

## Distance between baked points along each spline (SPLINES mode). Each baked
## segment between consecutive baked points is treated as one span to subdivide.
@export var bake_interval : float = 4.0

## When true (SPLINES mode), the whole spline is treated as a single span instead
## of subdividing each baked segment independently. Recommended for grammar fences.
@export var whole_spline_as_span : bool = true

## Attribute name of the segment start Vector stream (SEGMENTS mode).
@export var segment_start_attribute : String = "segment_start"

## Attribute name of the segment end Vector stream (SEGMENTS mode).
@export var segment_end_attribute : String = "segment_end"

## How each span is divided.
@export var subdivide_mode : eSubdivideMode = eSubdivideMode.MODULE_LENGTHS

## List of module lengths cycled along the span (MODULE_LENGTHS mode). Must
## contain at least one positive value.
@export var module_lengths : PackedFloat32Array = PackedFloat32Array([4.0])

## Number of equal sub-segments per span (TARGET_COUNT mode).
@export var target_count : int = 4

## How leftover length is handled when the modules do not exactly fill the span.
@export var fit_mode : eFitMode = eFitMode.STRETCH

## Cross-section size written into size.x / size.y of each emitted point. The
## segment length is written into size.z (the long axis points down the span).
@export var cross_section_size : Vector2 = Vector2.ONE

@export_group("Output Attributes")

## Output attribute name for each sub-segment length (Float).
@export var out_length_attribute : String = "length"

## Output attribute name for each sub-segment index within its span (Int).
@export var out_segment_index_attribute : String = "segment_index"

## Output attribute name for the normalized start position along the span (Float, 0..1).
@export var out_t_start_attribute : String = "t_start"

## Output attribute name for the normalized end position along the span (Float, 0..1).
@export var out_t_end_attribute : String = "t_end"

func _init():
	super._init()
	resource_name = "Subdivide Segment Settings"
