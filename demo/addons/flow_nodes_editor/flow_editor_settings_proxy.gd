@tool
extends Resource
class_name FlowEditorSettingsProxy

const SETTINGS: Array[Dictionary] = [
	{"property": "auto_generate", "label": "Auto Generate"},
	{"property": "color_nodes", "label": "Color Nodes"},
	{"property": "native_graph_grid", "label": "Native GraphEdit Grid"},
	{"property": "node_translation", "label": "Node Language"},
	{"property": "hide_inspector_title", "label": "Hide Title"},
	{"property": "hide_resource_builtin_rows", "label": "Hide Resource Built-in Rows"},
	{"property": "track_external_edits", "label": "Track External Edits"},
]

var editor: Object
var _syncing := false

@export var auto_generate := true:
	set(value):
		auto_generate = value
		_call_editor_toggle(&"_on_auto_regen_toggled", value)
@export var color_nodes := true:
	set(value):
		color_nodes = value
		_call_editor_toggle(&"_on_color_nodes_toggled", value)
@export var native_graph_grid := false:
	set(value):
		native_graph_grid = value
		_call_editor_toggle(&"_on_native_graph_grid_toggled", value)
@export var node_translation := true:
	set(value):
		node_translation = value
		_call_editor_toggle(&"_on_node_translation_toggled", value)
		notify_property_list_changed()
@export var hide_inspector_title := false:
	set(value):
		hide_inspector_title = value
		_call_editor_toggle(&"_on_hide_inspector_title_toggled", value)
@export var hide_resource_builtin_rows := true:
	set(value):
		hide_resource_builtin_rows = value
		_call_editor_toggle(&"_on_hide_resource_builtin_rows_toggled", value)
@export var track_external_edits := true:
	set(value):
		track_external_edits = value
		_call_editor_toggle(&"_on_track_external_edits_toggled", value)

func _init() -> void:
	resource_name = "Flow Editor"

func sync_from_editor(flow_editor: Object) -> void:
	editor = flow_editor
	_syncing = true
	auto_generate = bool(flow_editor.auto_regen)
	color_nodes = bool(flow_editor.color_nodes)
	native_graph_grid = bool(flow_editor.use_native_graph_grid)
	node_translation = FlowI18n.is_node_translation_enabled()
	hide_inspector_title = bool(flow_editor.hide_inspector_title)
	hide_resource_builtin_rows = bool(flow_editor.hide_resource_builtin_rows)
	track_external_edits = bool(flow_editor.track_external_edits)
	_syncing = false

func is_flow_editor_settings_proxy() -> bool:
	return true

func has_flow_editor_setting_property(property_name: String) -> bool:
	for setting in SETTINGS:
		if property_name == str(setting.property):
			return true
	return false

func get_flow_editor_setting_label(property_name: String) -> String:
	for setting in SETTINGS:
		if property_name == str(setting.property):
			return FlowI18n.t(str(setting.label))
	return FlowI18n.t(property_name.capitalize())

func _call_editor_toggle(method_name: StringName, value: bool) -> void:
	if _syncing or editor == null or not is_instance_valid(editor):
		return
	if editor.has_method(method_name):
		editor.call(method_name, value)
