@tool
class_name NodeSettings
extends Resource

# Base class for the settings of all nodes
# Each concrete node implmenets it's own NodeSettings derived class with the
# arguments that can be tweaked

enum eDebugMode {
	## Sized according to the point's local scale.
	EXTENDS,
	## Sized using a fixed absolute scale defined by debug_scale.
	ABSOLUTE,
}

@export_group("Common Settings")
## The random seed used to ensure deterministic behavior for nodes that generate random or pseudo-random data.
@export var random_seed: int = 12345

## If enabled, allows inspection of this node's output data within the editor.
@export var inspect_enabled: bool = false

## If enabled, debug visualizer instances (e.g. 3D boxes) are drawn in the editor viewport for this node.
@export var debug_enabled: bool = false
## The method used to determine the scale of debug visualizer instances.
@export var debug_mode : eDebugMode = eDebugMode.EXTENDS
## The absolute scale factor applied to debug visualizer instances when debug_mode is set to ABSOLUTE.
@export var debug_scale : float = 1.0
## The index of the execution bulk (or execution pass) to display debug visuals for.
@export var debug_bulk: int = 0
## The index of the output port/stream array within the selected debug_bulk to display debug visuals for.
@export var debug_output: int = 0

## The base color used to render debug visualizer instances. If an attribute modulation stream is active,
## its alpha channel is used to modulate the resulting grayscale color opacity.
@export var debug_color : Color = Color.WHITE
## The name of a specific attribute stream (e.g., "density", "weight", "noise") used to modulate the debug color.
## If left blank, the visualizer automatically falls back to modulating by the last added stream or predefined defaults.
@export var debug_modulate_by : String

# Add any other common properties here
## A descriptive custom title for this node in the flow editor graph.
@export var title: String = ""
## If true, this node is bypassed during execution, and debug drawing is disabled.
@export var disabled: bool = false
## If enabled, prints performance timing logs (in microseconds) for the debug drawing loop to the console.
@export var trace: bool = false

func _init():
	# Set default values when resource is created
	resource_name = "Node Settings"
	# Stable default seed: UE PCG graphs are deterministic by default, so a
	# fresh node must produce the same result every time. Per-point seeds
	# (FlowData.point_seed) decorrelate nodes that share this default.
	# Seeds stored in saved .tres files are unaffected.
	random_seed = 12345

func exposeParam( name : String ) -> bool:
	return true

## Override in subclasses to declare which String properties are attribute selectors.
## Each entry: { "prop": "property_name", "port": input_port_index }
## The inspector will render these as dropdowns populated from the input data's stream names.
func _get_attribute_selector_props() -> Array[Dictionary]:
	return []
