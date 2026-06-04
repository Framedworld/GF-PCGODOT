@tool
extends Resource
class_name FlowGraphResource

# This the resource to store a full flow graph

var _in_params_changed_queued := false

@export_category("Flow Graph Resource")

# Where we store the graph_nodes + custom settings as a dict
@export var data: Dictionary = {}:
	set(value):
		data = value
		_queue_in_params_changed()
	get:
		return data

# Visualization params
@export var view_zoom : float = 1.0
@export var view_offset : Vector2 = Vector2(0,0)

# To always generate unique name ids for each node
@export var new_name_counter : int = 0

@export var in_params : Array[GraphInputParameter] = []:
	set(value):
		in_params = value
		_watch_input_changes()
		_queue_in_params_changed()

@export var out_params : Array[GraphInputParameter] = []:
	set(value):
		out_params = value
		_watch_output_changes()
		_queue_in_params_changed()

signal in_params_changed

func _queue_in_params_changed() -> void:
	if _in_params_changed_queued:
		return
	_in_params_changed_queued = true
	call_deferred("_emit_in_params_changed")

func _emit_in_params_changed() -> void:
	_in_params_changed_queued = false
	in_params_changed.emit()

func _watch_input_changes():
	for param in in_params:
		if param is Resource and param.changed.is_connected(_on_input_changed):
			param.changed.disconnect(_on_input_changed)
	for param in in_params:
		if param is Resource:
			param.changed.connect(_on_input_changed, CONNECT_DEFERRED)

func _on_input_changed():
	emit_changed()

func _watch_output_changes():
	for param in out_params:
		if param is Resource and param.changed.is_connected(_on_output_changed):
			param.changed.disconnect(_on_output_changed)
	for param in out_params:
		if param is Resource:
			param.changed.connect(_on_output_changed, CONNECT_DEFERRED)

func _on_output_changed():
	emit_changed()

func findInParamByName( requested_name : String ):
	for candidate in in_params:
		if candidate and candidate.name == requested_name:
			return candidate
	return null
