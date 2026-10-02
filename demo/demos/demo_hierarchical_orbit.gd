extends Node3D

## Hierarchical generation demo: turns its children (the generation source and
## its marker) around the origin, so FlowWorld3D streams cells in ahead of the
## source and cleans them up behind it.
##
## The FlowGenerationSource children are switched on after `start_delay_frames`
## frames: the scene first shows the bare ground, then content streams in.
## (This also keeps the scene's fingerprint in the seed-zero test, which looks
## at it after two frames, independent of frame timing.)

## Degrees per second.
@export var speed_deg : float = 10.0
## Frames to wait before the generation sources are enabled.
@export var start_delay_frames : int = 30

var _frames : int = 0

func _ready() -> void:
	_set_sources_enabled(start_delay_frames <= 0)

func _process(delta : float) -> void:
	if _frames < start_delay_frames:
		_frames += 1
		if _frames >= start_delay_frames:
			_set_sources_enabled(true)
	rotate_y(deg_to_rad(speed_deg) * delta)

func _set_sources_enabled(on : bool) -> void:
	for child in get_children():
		if child is FlowGenerationSource:
			child.enabled = on
