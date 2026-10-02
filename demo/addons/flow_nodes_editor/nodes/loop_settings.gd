@tool
class_name LoopNodeSettings
extends NodeSettings

@export_group("Loop")

## The sub-graph resource to execute repeatedly in the loop.
@export var graph : FlowGraphResource:
	set(value):
		graph = value
		emit_changed()
## The input port name of the sub-graph that receives each loop item.
@export var item_input_name : String = "item":
	set(value):
		item_input_name = value
		emit_changed()
## The attribute name in which to write the collected loop outputs.
@export var output_attribute_name : String = "result":
	set(value):
		output_attribute_name = value
		emit_changed()

## The parameter name in the sub-graph used to pass back feedback values.
@export var feedback_param_name : String = "":
	set(value):
		feedback_param_name = value
		emit_changed()

## How the input on the Stream pin is split into iterations.
enum IterationMode {
	## One iteration per point of each input entry (the historical behaviour).
	## iteration_key is the point index.
	Points,
	## One iteration per data entry (bulk) arriving on the Stream pin, all
	## entries of the pin together (Unreal's loop over a collection).
	## iteration_key is the entry index, or the entry's `key_attribute` value.
	Entries,
	## Points of each input entry grouped by the value of `partition_attribute`,
	## one iteration per distinct value, ordered by value. iteration_key is
	## the value.
	Partitions,
	## Consecutive runs of `chunk_size` points of each input entry (the last
	## chunk may be shorter). iteration_key is the chunk index.
	Chunks,
}

## How the iteration results reach the Out pin.
enum OutputMode {
	## Concatenate every iteration's result into one Data (the historical
	## behaviour).
	Merge,
	## One output entry (bulk) per iteration, so a downstream node runs once
	## per iteration.
	Collection,
}

## What a loop does when `graph_attribute` names no usable graph for an
## iteration.
enum GraphErrorPolicy {
	## Report the error and continue with the next iteration.
	SkipIteration,
	## Report the error and run no further iterations.
	Stop,
}

## How the Stream input is split into iterations.
@export var iteration_mode : IterationMode = IterationMode.Points:
	set(value):
		iteration_mode = value
		notify_property_list_changed()
		emit_changed()

## Partitions mode: the attribute whose distinct values define the iterations
## (a point stream, or a per-data attribute, which yields one partition).
@export var partition_attribute : String = "":
	set(value):
		partition_attribute = value
		emit_changed()

## Chunks mode: the number of points per iteration (at least 1).
@export_range(1, 1000000, 1, "or_greater") var chunk_size : int = 1:
	set(value):
		chunk_size = maxi(1, value)
		emit_changed()

## Entries mode: an optional attribute (point stream element 0 or per-data
## attribute) of each entry used as its iteration_key instead of the entry
## index, so per-entry seeds stay stable when entries are added or removed.
@export var key_attribute : String = "":
	set(value):
		key_attribute = value
		emit_changed()

## How the iteration results are emitted on the Out pin.
@export var output_mode : OutputMode = OutputMode.Merge:
	set(value):
		output_mode = value
		emit_changed()

## Dynamic subgraph: an attribute of each iteration's data (a String resource
## path or a FlowGraphResource) naming the graph to run for that iteration.
## Empty: always run `graph`. An empty path value falls back to `graph`.
@export var graph_attribute : String = "":
	set(value):
		graph_attribute = value
		emit_changed()

## Dynamic subgraph: what to do when an iteration's graph cannot be resolved.
@export var on_graph_error : GraphErrorPolicy = GraphErrorPolicy.SkipIteration:
	set(value):
		on_graph_error = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Loop"

func _validate_property(property : Dictionary) -> void:
	match property.name:
		"partition_attribute":
			if iteration_mode != IterationMode.Partitions:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"chunk_size":
			if iteration_mode != IterationMode.Chunks:
				property.usage &= ~PROPERTY_USAGE_EDITOR
		"key_attribute":
			if iteration_mode != IterationMode.Entries:
				property.usage &= ~PROPERTY_USAGE_EDITOR

# Attribute selectors read from the Stream pin (inspector dropdowns).
func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "partition_attribute", "port": 0 },
		{ "prop": "key_attribute", "port": 0 },
		{ "prop": "graph_attribute", "port": 0 },
	]

