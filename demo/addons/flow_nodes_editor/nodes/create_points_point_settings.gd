@tool
class_name FlowPointEntry
extends Resource

## One hand-authored point of the Create Points node. Lives next to the node's
## settings (the "_settings" suffix keeps it out of the node list).

## Point position (world space, or relative to the owner in Local space).
@export var position : Vector3 = Vector3.ZERO:
	set(value):
		position = value
		emit_changed()
## Point rotation as Euler angles in degrees (Godot Y-up: yaw is Y).
@export var rotation : Vector3 = Vector3.ZERO:
	set(value):
		rotation = value
		emit_changed()
## Point scale, written to the `size` stream.
@export var scale : Vector3 = Vector3.ONE:
	set(value):
		scale = value
		emit_changed()
## Local bounds min corner (bounds_min stream).
@export var bounds_min : Vector3 = Vector3( -0.5, -0.5, -0.5 ):
	set(value):
		bounds_min = value
		emit_changed()
## Local bounds max corner (bounds_max stream).
@export var bounds_max : Vector3 = Vector3( 0.5, 0.5, 0.5 ):
	set(value):
		bounds_max = value
		emit_changed()
## Density (0..1, clamped).
@export_range(0.0, 1.0) var density : float = 1.0:
	set(value):
		density = value
		emit_changed()
## Steepness of the bounds edge (0..1, clamped; 1 = hard box).
@export_range(0.0, 1.0) var steepness : float = 1.0:
	set(value):
		steepness = value
		emit_changed()
## Point seed. 0 derives it from the final world position and the node seed,
## like the samplers do; any other value is written as is.
@export var seed : int = 0:
	set(value):
		seed = value
		emit_changed()
## Extra attributes, name -> value (bool, int, float, String, Vector3, Color,
## Quaternion or Resource). Points that omit a name get the type's default.
@export var attributes : Dictionary = {}:
	set(value):
		attributes = value
		emit_changed()

func _init():
	resource_name = "Point"
