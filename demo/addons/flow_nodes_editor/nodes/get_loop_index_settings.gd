@tool
extends NodeSettings

@export_group("Get Loop Index")

## What the index counts.
enum eSource {
	## A sequential index per incoming point (start_index..start_index+N-1).
	## The historical behaviour, closer to Unreal's $Index.
	Points,
	## The iteration index of the enclosing Loop (Unreal's Get Loop Index), in
	## every loop iteration mode, plus start_index. Written to every incoming
	## point, or as a one-value Data when In is not connected.
	LoopIteration,
}

## The name of the output integer attribute stream in which to write the sequential indices.
@export var out_name : String = "loop_index":
	set(value):
		out_name = value.strip_edges()
		emit_changed()

## The starting index value for the enumeration sequence.
@export var start_index : int = 0:
	set(value):
		start_index = value
		emit_changed()

## What the index counts: points of the input (default), or the enclosing
## loop iteration.
@export var source : eSource = eSource.Points:
	set(value):
		source = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Get Loop Index Settings"
