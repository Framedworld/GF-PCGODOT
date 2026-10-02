@tool
class_name FlowNodeWidget
extends GraphNode

## Editor widget of one flow graph node (the UPCGNode editor side).
##
## Owns one runtime element (`element`, a FlowNodeBase) and hosts all of the
## node's UI: port rows, theming, tooltips, debug draw, error text, the
## execution-time badge, slot types and colours. The members the graph editor
## has always used on nodes (settings, node_template, deps, dependants, dirty,
## generated_bulks, inputs, err, args_ports_by_name, show_disconnected_inputs,
## eval_id, scene_fingerprint, ...) and the element methods it calls are
## exposed here by delegation, so editor code reads the same as before. Any
## other element member is reachable through _get/_set as well, or directly as
## `widget.element.<member>`.
##
## Nodes that build UI implement the optional widget_* hooks documented at the
## top of node.gd; this class calls them.

const connectors_row_prefab = preload( "res://addons/flow_nodes_editor/connectors_row.tscn" )
const connectors_options_prefab = preload( "res://addons/flow_nodes_editor/connectors_options.tscn" )

## The runtime element shown by this widget.
var element : FlowNodeBase:
	set(new_value):
		_bind_element(new_value)
	get:
		return _element

var _element : FlowNodeBase = null
# Settings resource whose `changed` signal is connected to this widget.
var _watched_settings : NodeSettings = null

# Render
var draw_debug : NodeDrawDebug
var ui_scale = 1.0
var marker_radius : float = 9

var _no_conns : Array[Dictionary] = []

## Row of the inspected output highlighted by the debug draw (-1 = none).
var debug_row : int = -1

# Port layout the rows were last built from (port_signature()), or null before
# the first initFromScript(). refresh_ui() rebuilds the rows when the element's
# metadata no longer matches it (a mode setting such as use_bounding_shape or
# projection_mode changed the inputs), whatever path changed the setting.
var _built_port_signature = null
# Flow input and output counts of the last build (-1 before the first one).
var _built_num_flow_ins : int = -1
var _built_num_outs : int = -1

# --- Delegated element state ------------------------------------------------------

var settings : NodeSettings:
	get: return _element.settings if _element else null
	set(v):
		if _element:
			_element.settings = v
var node_template : String:
	get: return _element.node_template if _element else ""
	set(v):
		if _element:
			_element.node_template = v
var meta_node : Dictionary:
	get: return _element.meta_node if _element else {}
	set(v):
		if _element:
			_element.meta_node = v
var deps : Array[Dictionary]:
	get: return _element.deps if _element else _no_conns
	set(v):
		if _element:
			_element.deps = v
var dependants : Array[Dictionary]:
	get: return _element.dependants if _element else _no_conns
	set(v):
		if _element:
			_element.dependants = v
var dirty : bool:
	get: return _element.dirty if _element else false
	set(v):
		if _element:
			_element.dirty = v
var generated_bulks : Array:
	get: return _element.generated_bulks if _element else []
	set(v):
		if _element:
			_element.generated_bulks = v
var num_generated_bulks : int:
	get: return _element.num_generated_bulks if _element else 0
	set(v):
		if _element:
			_element.num_generated_bulks = v
var input_bulks : Array:
	get: return _element.input_bulks if _element else []
	set(v):
		if _element:
			_element.input_bulks = v
var num_connected_bulks : int:
	get: return _element.num_connected_bulks if _element else 0
	set(v):
		if _element:
			_element.num_connected_bulks = v
var inputs:
	get: return _element.inputs if _element else []
	set(v):
		if _element:
			_element.inputs = v
var err : String:
	get: return _element.err if _element else ""
	set(v):
		if _element:
			_element.err = v
var args_ports_by_name:
	get: return _element.args_ports_by_name if _element else {}
	set(v):
		if _element:
			_element.args_ports_by_name = v
var show_disconnected_inputs : bool:
	get: return _element.show_disconnected_inputs if _element else false
	set(v):
		if _element:
			_element.show_disconnected_inputs = v
var eval_id : int:
	get: return _element.eval_id if _element else 0
	set(v):
		if _element:
			_element.eval_id = v
var scene_fingerprint : int:
	get: return _element.scene_fingerprint if _element else 0
	set(v):
		if _element:
			_element.scene_fingerprint = v
var has_scene_fingerprint : bool:
	get: return _element.has_scene_fingerprint if _element else false
	set(v):
		if _element:
			_element.has_scene_fingerprint = v
var num_in_ports : int:
	get: return _element.num_in_ports if _element else 0
	set(v):
		if _element:
			_element.num_in_ports = v
var num_out_ports : int:
	get: return _element.num_out_ports if _element else 0
	set(v):
		if _element:
			_element.num_out_ports = v
var num_ports : int:
	get: return _element.num_ports if _element else 0
	set(v):
		if _element:
			_element.num_ports = v
var rng : RandomNumberGenerator:
	get: return _element.rng if _element else null
var graph_seed : int:
	get: return _element.graph_seed if _element else 0

# Any other element member (node-specific vars) reads and writes through.
func _get(property: StringName):
	if _element != null and property in _element:
		return _element.get(property)
	return null

func _set(property: StringName, value) -> bool:
	if _element != null and property in _element:
		_element.set(property, value)
		return true
	return false

# --- Delegated element methods ---------------------------------------------------

func getMeta() -> Dictionary:
	return _element.getMeta() if _element else {}

func getTitle() -> String:
	return _element.getTitle() if _element else title

func getLocalizedTitle() -> String:
	return _element.getLocalizedTitle() if _element else title

func getTooltip() -> String:
	return _element.getTooltip() if _element else ""

func getExposedParams():
	return _element.getExposedParams()

func exposedAsInputNode( prop ):
	return _element.exposedAsInputNode( prop )

func onPropChanged( prop_name : String ):
	_element.onPropChanged( prop_name )

func preExecute( ctx ):
	_element.preExecute( ctx )

func run( ctx ):
	_element.run( ctx )

func execute( ctx ):
	_element.execute( ctx )

func executedDisabled( ctx ):
	_element.executedDisabled( ctx )

func setError( new_err : String ):
	_element.setError( new_err )

func computeSceneFingerprint( ctx ) -> Variant:
	return _element.computeSceneFingerprint( ctx )

func get_bulk_output( bulk_idx : int, port_idx : int ):
	return _element.get_bulk_output( bulk_idx, port_idx )

func get_bulk_input( bulk_idx : int, port_idx : int ):
	return _element.get_bulk_input( bulk_idx, port_idx )

func get_optional_input( idx : int ):
	return _element.get_optional_input( idx )

func get_input( idx : int ):
	return _element.get_input( idx )

func set_output( port_idx : int, data ):
	_element.set_output( port_idx, data )

func getSettingValue( ctx, in_name : String, default_value = null ):
	return _element.getSettingValue( ctx, in_name, default_value )

func effective_seed() -> int:
	return _element.effective_seed()

func get_deterministic_color() -> Color:
	return _element.get_deterministic_color()

func _get_category_hue() -> float:
	return _element._get_category_hue()

func _get_meta_node_color():
	return _element._get_meta_node_color()

## True when the element (or this widget) implements `method`.
func element_has_method( method : StringName ) -> bool:
	return has_method( method ) or ( _element != null and _element.has_method( method ) )

# --- Element binding --------------------------------------------------------------

func _init():
	ignore_invalid_connection_type = true
	if not draw.is_connected( _on_draw ):
		draw.connect( _on_draw )
	if not renamed.is_connected( _sync_element_name ):
		renamed.connect( _sync_element_name )

func _bind_element( new_element : FlowNodeBase ) -> void:
	if _element == new_element:
		return
	if _element != null:
		_disconnect_element_signals( _element )
		_element._widget = null
	_watch_settings( null )
	_element = new_element
	if _element == null:
		return
	_element._widget = self
	if String( name ) != "":
		_element.name = name
	_element.error_changed.connect( _on_element_error_changed )
	_element.redraw_requested.connect( _on_element_redraw_requested )
	_element.refresh_requested.connect( _on_element_refresh_requested )
	_element.settings_replaced.connect( _on_element_settings_replaced )
	_watch_settings( _element.settings )

func _disconnect_element_signals( e : FlowNodeBase ) -> void:
	if e.error_changed.is_connected( _on_element_error_changed ):
		e.error_changed.disconnect( _on_element_error_changed )
	if e.redraw_requested.is_connected( _on_element_redraw_requested ):
		e.redraw_requested.disconnect( _on_element_redraw_requested )
	if e.refresh_requested.is_connected( _on_element_refresh_requested ):
		e.refresh_requested.disconnect( _on_element_refresh_requested )
	if e.settings_replaced.is_connected( _on_element_settings_replaced ):
		e.settings_replaced.disconnect( _on_element_settings_replaced )

func _watch_settings( new_settings : NodeSettings ) -> void:
	if _watched_settings != null and _watched_settings.changed.is_connected( _on_settings_changed ):
		_watched_settings.changed.disconnect( _on_settings_changed )
	_watched_settings = new_settings
	if _watched_settings != null:
		_watched_settings.changed.connect( _on_settings_changed )

## Keeps element.name equal to this widget's name (GraphEdit addresses nodes,
## connections and ctx.gedit_nodes_by_name by it).
func _sync_element_name() -> void:
	if _element != null and _element.name != name:
		_element.name = name

func _notification( what : int ) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_ENTER_TREE:
		_sync_element_name()

## Replaces the element by a fresh instance of `script` (hot reload of a node
## script), keeping the node's identity, settings and port bookkeeping.
func rebind_script( script : Script ) -> void:
	var old := _element
	var fresh = script.new()
	var new_element := fresh as FlowNodeBase
	if new_element == null:
		push_error( "FlowNodeWidget: %s is not a FlowNodeBase script" % script.resource_path )
		return
	if old != null:
		new_element.name = old.name
		new_element.node_template = old.node_template
		new_element.settings = old.settings
		new_element.args_ports_by_name = old.args_ports_by_name
		new_element.show_disconnected_inputs = old.show_disconnected_inputs
		new_element.dirty = true
	element = new_element

func _on_element_error_changed( message : String ) -> void:
	if message:
		editor_state_changed.emit()
	queue_redraw()

func _on_element_redraw_requested() -> void:
	queue_redraw()

func _on_element_refresh_requested() -> void:
	refresh_ui()

func _on_element_settings_replaced( _old_settings : NodeSettings, new_settings : NodeSettings ) -> void:
	_watch_settings( new_settings )

func _on_settings_changed():
	if _element:
		_element.dirty = true
	refreshFromSettings()
	var editor = getEditor()
	if editor:
		editor.queueRegen()

# --- Scene tree lifecycle ------------------------------------------------------------

func _ready():
	ignore_invalid_connection_type = true
	checkDrawDebug()
	refreshInspectMark()
	refreshDebugMark()
	update_node_style()
	if _element != null and _element.has_method( "widget_ready" ):
		_element.widget_ready( self )

func _exit_tree():
	if _element != null and _element.has_method( "widget_exit_tree" ):
		_element.widget_exit_tree( self )

func _gui_input(event: InputEvent) -> void:
	if _element != null and _element.has_method( "widget_gui_input" ):
		if _element.widget_gui_input( self, event ):
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var editor = getEditor()
			if editor and editor.has_method("prepare_graph_for_interaction"):
				editor.prepare_graph_for_interaction()
			elif editor and editor.has_method("repair_graph_integrity"):
				editor.repair_graph_integrity()
			var gedit = get_parent() as GraphEdit
			if gedit:
				var additive := Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)
				if additive:
					selected = true
				elif not selected:
					for child in gedit.get_children():
						if child is GraphNode and child != self:
							child.selected = false
					selected = true
				# Already selected without modifier: keep multi-selection for group drag.
			if node_template == "set_variable" or node_template == "get_variable":
				if editor:
					if node_template == "set_variable" and editor.has_method("flash_linked_get_variable_nodes"):
						editor.flash_linked_get_variable_nodes(self)
					elif node_template == "get_variable" and editor.has_method("flash_linked_set_variable_nodes"):
						editor.flash_linked_set_variable_nodes(self)
			if event.double_click:
				if node_template == "subgraph" and settings and "graph" in settings and settings.graph:
					if editor:
						editor.setResourceToEdit(settings.graph, null)

func getEditor():
	var gedit = get_parent_control() as GraphEdit
	var flow_editor = gedit.get_parent_control().get_parent_control().get_parent_control() as Control if gedit else null
	return flow_editor

# --- Debug draw and output summaries ----------------------------------------------------

func checkDrawDebug():
	if not is_instance_valid(draw_debug) or draw_debug.get_parent() != self:
		draw_debug = NodeDrawDebug.new()
		draw_debug.node = self
		add_child(draw_debug)
		# if the helper gets freed, clear our reference
		draw_debug.tree_exited.connect(func(): draw_debug = null)

func setupDrawDebug():
	checkDrawDebug()
	draw_debug.setupDraw()
	_cache_output_summaries()

func _cache_output_summaries():
	var output_summaries = []
	var meta := getMeta()
	var outs = meta.get("outs", [])
	for bulk_idx in range(generated_bulks.size()):
		var bulk = generated_bulks[bulk_idx]
		for port_idx in range(outs.size()):
			if port_idx >= bulk.size() or bulk[port_idx] == null:
				continue
			var out_data = bulk[port_idx] as FlowData.Data
			if out_data == null:
				continue
			var info := []
			for sname in out_data.streams.keys():
				var stream = out_data.streams[sname]
				var type_str = FlowData.DataType.keys()[stream.data_type] if stream.data_type < FlowData.DataType.size() else "?"
				info.append({"name": str(sname), "type": type_str, "count": stream.container.size()})
			while output_summaries.size() <= port_idx:
				output_summaries.append(null)
			output_summaries[port_idx] = {
				"points": out_data.size(),
				"streams": out_data.numFields(),
				"stream_info": info,
				"shape": shape_summary( out_data ),
			}
	set_meta("output_summaries", output_summaries)
	# Update tooltip with stream summary
	_update_data_tooltip()
	redrawUI()

func _update_data_tooltip():
	var output_summaries = get_meta("output_summaries", [])
	if output_summaries.is_empty():
		return
	var lines := []
	var meta := getMeta()
	var outs = meta.get("outs", [])
	for port_idx in range(mini(output_summaries.size(), outs.size())):
		var summary = output_summaries[port_idx]
		if summary == null:
			continue
		var port_label = _localized_node_text(str(outs[port_idx].get("label", "Out %d" % port_idx)))
		var shape_text : String = summary.get("shape", "")
		lines.append("%s: %d pts, %d streams%s" % [port_label, summary.points, summary.streams, ( ", " + shape_text ) if shape_text else ""])
		for si in summary.stream_info:
			lines.append("  · %s (%s)" % [si.name, si.type])
	if lines.size() > 0:
		tooltip_text = "\n".join(lines)

## Returns a formatted string summary of this node's primary output, for status bar display.
func get_data_summary() -> String:
	var output_summaries = get_meta("output_summaries", [])
	if output_summaries.is_empty() or output_summaries[0] == null:
		return ""
	var s = output_summaries[0]
	var parts := PackedStringArray()
	var shape_text : String = s.get("shape", "")
	if shape_text:
		parts.append(shape_text)
	for si in s.stream_info:
		parts.append("%s(%s)" % [si.name, si.type])
	return "%d pts — %s" % [s.points, ", ".join(parts)]

## "shape <class> (<kind>)" for a Data carrying a spatial shape, else "".
static func shape_summary( data : FlowData.Data ) -> String:
	if data == null or data.shape == null:
		return ""
	return "shape %s (%s)" % [ FlowDataTableModel.shape_class_name( data.shape ), FlowDataTableModel.kind_name( data.shape.get_kind() ) ]

func redrawUI():
	queue_redraw()

func refreshDebugMark():
	redrawUI()

func refreshInspectMark():
	redrawUI()

func setActivity( amount : float ):
	if settings == null or settings.disabled:
		return
	if not err:
		modulate = Color.WHITE + Color( amount, amount, amount, 0.0 )
	else:
		modulate = Color(1.0, 0.5, 0.5)

func setExecTime(usec: int):
	set_meta("exec_time_usec", usec)
	if is_inside_tree():
		queue_redraw()

# --- Theming ----------------------------------------------------------------------------

func _clear_graph_node_stylebox_overrides():
	remove_theme_stylebox_override("panel")
	remove_theme_stylebox_override("panel_selected")
	remove_theme_stylebox_override("titlebar")
	remove_theme_stylebox_override("titlebar_selected")

func _make_tinted_graph_node_stylebox(style_name: String, bg_color: Color):
	if not has_theme_stylebox(style_name):
		return null

	var style = get_theme_stylebox(style_name).duplicate()
	if style is StyleBoxFlat:
		style.bg_color = bg_color
		return style
	return null

func update_node_style():
	if node_template == "reroute":
		custom_minimum_size = Vector2(42, 24)
		size = custom_minimum_size
		var empty_sb = StyleBoxEmpty.new()
		empty_sb.content_margin_left = 0
		empty_sb.content_margin_right = 0
		empty_sb.content_margin_top = 0
		empty_sb.content_margin_bottom = 0
		add_theme_stylebox_override("panel", empty_sb)
		add_theme_stylebox_override("panel_selected", empty_sb)
		add_theme_stylebox_override("titlebar", empty_sb)
		add_theme_stylebox_override("titlebar_selected", empty_sb)
		return

	_clear_graph_node_stylebox_overrides()

	var cat_hue : float = _element._get_category_hue() if _element else 0.0

	var is_colored = false
	var editor = getEditor()
	if editor and "color_nodes" in editor and editor.color_nodes:
		is_colored = true

	var custom_node_color = null
	if _element != null and _element.has_method("_get_custom_node_color"):
		custom_node_color = _element.call("_get_custom_node_color")

	var meta_color = _element._get_meta_node_color() if _element else null

	if custom_node_color is Color:
		var color : Color = custom_node_color
		var sb_title = _make_tinted_graph_node_stylebox("titlebar", color.darkened(0.62))
		if sb_title:
			add_theme_stylebox_override("titlebar", sb_title)

		var sb_title_selected = _make_tinted_graph_node_stylebox("titlebar_selected", color.darkened(0.48))
		if sb_title_selected:
			add_theme_stylebox_override("titlebar_selected", sb_title_selected)
	elif is_colored and meta_color is Color:
		# Project category colour from meta_node.color, tinted like custom colours.
		var sb_title = _make_tinted_graph_node_stylebox("titlebar", meta_color.darkened(0.62))
		if sb_title:
			add_theme_stylebox_override("titlebar", sb_title)

		var sb_title_selected = _make_tinted_graph_node_stylebox("titlebar_selected", meta_color.darkened(0.48))
		if sb_title_selected:
			add_theme_stylebox_override("titlebar_selected", sb_title_selected)
	elif is_colored:
		var sb_title = _make_tinted_graph_node_stylebox("titlebar", Color.from_hsv(cat_hue, 0.35, 0.24, 1.0))
		if sb_title:
			add_theme_stylebox_override("titlebar", sb_title)

		var sb_title_selected = _make_tinted_graph_node_stylebox("titlebar_selected", Color.from_hsv(cat_hue, 0.4, 0.30, 1.0))
		if sb_title_selected:
			add_theme_stylebox_override("titlebar_selected", sb_title_selected)

	# Title text color overrides
	add_theme_color_override("title_color", Color("cdd0dc")) # Figma title color
	add_theme_color_override("title_selected_color", Color("ffffff"))

	var title_font = null
	if has_theme_font("bold", "EditorFonts"):
		title_font = get_theme_font("bold", "EditorFonts")
	elif has_theme_font("main", "EditorFonts"):
		title_font = get_theme_font("main", "EditorFonts")
	if title_font:
		add_theme_font_override("title_font", title_font)
	add_theme_font_size_override("title_font_size", 12)

	custom_minimum_size.x = 210
	add_theme_constant_override("separation", 4)

	self_modulate = Color.WHITE

# --- Refresh ----------------------------------------------------------------------------

## Editor entry point after settings changed. Runs the element's
## refreshFromSettings() (and any override in the node script), whose base
## implementation asks this widget to refresh_ui().
func refreshFromSettings():
	if _element != null:
		_element.refreshFromSettings()
	else:
		refresh_ui()

## Rebuilds the UI state derived from the settings, then calls the element's
## widget_refresh hook.
func refresh_ui():
	if settings == null:
		return
	refreshDebugMark()
	refreshInspectMark()
	refreshLocalizedText()
	modulate = Color( 0.7, 0.7, 0.7, 0.5 ) if settings.disabled else Color.WHITE

	update_node_style()

	if draw_debug and ( not settings.debug_enabled or settings.disabled ):
		draw_debug.cleanup_multimesh_direct()
		draw_debug.cleanup_lines_direct()

	if settings and "data_type" in settings and node_template != "add_attribute" and node_template != "attribute_random":
		var meta := getMeta()
		var outs = meta.get("outs", [])
		for idx in range(outs.size()):
			var out_data = outs[idx]
			if out_data:
				var data_type = out_data.get("data_type", FlowData.DataType.Invalid)
				if data_type == FlowData.DataType.Invalid:
					var color = FlowNodeBase.getColorForFlowDataType(settings.data_type)
					if is_slot_enabled_right(idx):
						set_slot_color_right(idx, color)
						set_slot_type_right(idx, settings.data_type)

	if _built_port_signature != null and port_signature() != _built_port_signature:
		initFromScript()

	if _element != null and _element.has_method( "widget_refresh" ):
		_element.widget_refresh( self )

## What the port rows are built from: the element's flow inputs and outputs
## (label and data type) and its exposed parameter names. Two equal signatures
## build the same rows; a different one means a mode setting changed the ports.
func port_signature() -> Array:
	if _element == null or settings == null:
		return []
	var meta := getMeta()
	var ins := []
	for in_data in meta.get( "ins", [] ):
		ins.append( [ str( in_data.get( "label", "" ) ), int( in_data.get( "data_type", FlowData.DataType.Invalid ) ), str( in_data.get( "name", "" ) ) ] if in_data is Dictionary else null )
	var outs := []
	for out_data in meta.get( "outs", [] ):
		outs.append( [ str( out_data.get( "label", "" ) ), int( out_data.get( "data_type", FlowData.DataType.Invalid ) ) ] if out_data is Dictionary else null )
	var params := []
	for param in getExposedParams():
		params.append( [ str( param.name ), int( param.get( "data_type", FlowData.DataType.Invalid ) ) ] )
	return [ ins, outs, params, show_disconnected_inputs ]

func refreshLocalizedText() -> void:
	title = getLocalizedTitle()
	if get_meta("output_summaries", []).is_empty():
		tooltip_text = getTooltip()
	else:
		_update_data_tooltip()
	_refresh_connector_labels()

func _refresh_connector_labels() -> void:
	var meta := getMeta()
	var outs = meta.get("outs", [])
	var row_index := 0
	for child in get_children():
		var row := child as FlowConnectorRow
		if row == null:
			continue
		if row_index < num_in_ports and not row.data.is_empty():
			row.getInLabel().text = _localized_node_text(str(row.data.get("label", "")))
		elif row_index >= num_in_ports:
			row.getInLabel().text = ""
		if row_index < outs.size() and outs[row_index]:
			row.getOutLabel().text = _localized_node_text(str(outs[row_index].get("label", "")))
		else:
			row.getOutLabel().text = ""
		row_index += 1

func _localized_node_text(text: String) -> String:
	if text.is_empty():
		return text
	return FlowI18n.tn(text)

# --- Drawing -------------------------------------------------------------------------------

func _on_draw() -> void:
	if _element != null and _element.has_method( "widget_draw" ):
		if _element.widget_draw( self ):
			return

	if not settings:
		return

	if err:
		var sz = 16 * ui_scale
		draw_string( ThemeDB.fallback_font, Vector2(0,size.y + sz), err, HORIZONTAL_ALIGNMENT_LEFT, -1, sz )

	if settings.inspect_enabled:
		var clr : Color = Color.YELLOW / self_modulate
		draw_circle( Vector2(0,0), marker_radius * ui_scale, clr )
	if settings.debug_enabled:
		var clr : Color = Color.CYAN / self_modulate
		draw_circle( Vector2(size.x,0), marker_radius * ui_scale, clr )

	# Draw bottom decoration handle (Figma node style)
	var handle_w = 22.0 * ui_scale
	var handle_h = 3.0 * ui_scale
	var handle_x = (size.x - handle_w) / 2.0
	var handle_y = size.y - handle_h
	var handle_sb = StyleBoxFlat.new()
	handle_sb.bg_color = Color(1.0, 1.0, 1.0, 0.07)
	handle_sb.corner_radius_top_left = 2
	handle_sb.corner_radius_top_right = 2
	draw_style_box(handle_sb, Rect2(handle_x, handle_y, handle_w, handle_h))

	# Draw execution time badge (top-right, near titlebar)
	var exec_time_usec = get_meta("exec_time_usec", 0)
	if exec_time_usec > 100:
		var time_font = ThemeDB.fallback_font
		var time_font_size := int(9 * ui_scale)
		var time_text: String
		var time_color: Color
		if exec_time_usec >= 10000:  # > 10ms — warning
			time_text = "%.1f ms" % (exec_time_usec / 1000.0)
			time_color = Color(1.0, 0.6, 0.2, 0.9)  # Warm orange
		elif exec_time_usec >= 1000:  # 1-10ms
			time_text = "%.1f ms" % (exec_time_usec / 1000.0)
			time_color = Color(1, 1, 1, 0.4)
		else:
			time_text = "%d µs" % exec_time_usec
			time_color = Color(1, 1, 1, 0.25)
		var tw = time_font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, time_font_size).x
		var tx = size.x - tw - 8 * ui_scale
		var ty = 12.0 * ui_scale
		draw_string(time_font, Vector2(tx, ty), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, time_font_size, time_color)

# --- Ports ----------------------------------------------------------------------------------

## (Re)builds the port rows from the element's metadata and exposed parameters,
## keeping existing wires on parameter ports, then calls the element's
## widget_init hook.
func initFromScript():
	var meta := getMeta()
	var trace = meta.get( "trace", false )

	var ins = meta.get( "ins", [] )
	var outs = meta.get( "outs", [] )
	var num_ins = ins.size()
	var num_outs = outs.size()

	var exposed_params = getExposedParams()
	var has_exposed_params = exposed_params.size() > 0

	# Access to my parent container editor
	# We need to remember which nodes were connected as we might be expanded/contracting the list and want to
	# maintain the same connected entries
	var flow_editor = getEditor()
	var connected_inputs_by_name = {}
	if flow_editor:
		for arg_name in args_ports_by_name:
			var arg_port = args_ports_by_name[ arg_name ].port
			var curr_connections = flow_editor.get_connected_sources( name, arg_port )
			#print( "Checking if %s is connected at port %d -> %d conns" % [ arg_name, arg_port, curr_connections.size() ] )
			if not curr_connections.is_empty():
				connected_inputs_by_name[ arg_name ] = { "port" : arg_port, "conns" : curr_connections.duplicate() }
				for old_conn in curr_connections:
					var from_node = old_conn[0]
					var from_port = old_conn[1]
					flow_editor.disconnect_nodes( from_node, from_port, name, arg_port )

		if not show_disconnected_inputs:
			exposed_params = exposed_params.filter( func( data ):
				return args_ports_by_name.has( data.name ) and args_ports_by_name[ data.name ].connected
			)
	else:
		# When we just instantiate the node
		exposed_params = []

	if trace:
		print( "flow_editor: %s" % flow_editor)
		print( "show_disconnected_inputs: %s" % show_disconnected_inputs)
		print( "all_exposed_params: %s" % exposed_params.size())
		print( "exposed_params: %s" % exposed_params.size())
		print( "args_ports_by_name: %s" % args_ports_by_name)

	# Links to flow inputs or outputs that this build removes (a mode setting
	# turned off an optional input, say) would otherwise stay attached to
	# whatever port takes that index next. Parameter links were detached above
	# and are reattached by name below.
	if flow_editor:
		_drop_links_to_removed_ports( flow_editor, num_ins, num_outs )

	# Total inputs are flow in streams + exposed parameters of the node
	var num_inputs = num_ins + exposed_params.size()
	num_ports = max( num_inputs, num_outs )
	num_in_ports = num_inputs
	num_out_ports = num_outs

	# Delete current children
	clear_all_slots()
	for child in get_children():
		if child == draw_debug:
			continue
		child.queue_free()
		remove_child( child )

	var new_args_ports_by_name = {}
	for idx in range( 0, num_ports ):
		var ctrl = connectors_row_prefab.instantiate() as FlowConnectorRow
		add_child( ctrl )
		# Figma: PORT_ROW = 26px height
		ctrl.custom_minimum_size.y = 26

		var lbl_in = ctrl.getInLabel()
		var lbl_out = ctrl.getOutLabel()

		# Figma label typography & color overrides
		lbl_in.add_theme_color_override("font_color", Color("8b90a8"))
		lbl_in.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		lbl_out.add_theme_color_override("font_color", Color("8b90a8"))
		lbl_out.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		# Is there an input active
		if idx < num_inputs:
			var in_data

			# Decide if it's a flow input, or just a param input
			if idx < num_ins:
				in_data = ins[idx]
			else:
				in_data = exposed_params[ idx - num_ins ]
			lbl_in.text = _localized_node_text(str(in_data.get("label", "")))

			var in_name = in_data.get( "name", in_data.label )

			set_slot_enabled_left( idx, true )

			# Change color
			var data_type = in_data.get( "data_type", FlowData.DataType.Invalid )
			if data_type == FlowData.DataType.Invalid and in_data.has( "type"):
				data_type = FlowNodeBase.getFlowDataTypeFromGdScriptType( in_data.type )
			if data_type != FlowData.DataType.Invalid:
				var color = FlowNodeBase.getColorForFlowDataType( data_type )
				set_slot_color_left( idx, color )
				set_slot_type_left( idx, data_type )

			in_data.port = idx
			ctrl.setData( in_data )

			new_args_ports_by_name[ in_name ] = { "port" : idx, "connected" : connected_inputs_by_name.has( in_name ) }
			if trace:
				print( "%s : Assigning slot %d for input %s" % [ name, idx, in_name ])
		else:
			lbl_in.text = ""

		if idx < num_outs:
			var out_data = outs[idx]
			if out_data:
				lbl_out.text = _localized_node_text(str(out_data.get("label", "")))
				set_slot_enabled_right( idx, true )

				# Change color
				var data_type = out_data.get( "data_type", FlowData.DataType.Invalid )
				if data_type == FlowData.DataType.Invalid and out_data.has( "type"):
					data_type = FlowNodeBase.getFlowDataTypeFromGdScriptType( out_data.type )
				if data_type == FlowData.DataType.Invalid and settings and "data_type" in settings and node_template != "add_attribute" and node_template != "attribute_random":
					data_type = settings.data_type
				if data_type != FlowData.DataType.Invalid:
					var color = FlowNodeBase.getColorForFlowDataType( data_type )
					set_slot_color_right( idx, color )
					set_slot_type_right( idx, data_type )

		else:
			lbl_out.text = ""
	args_ports_by_name = new_args_ports_by_name

	# Add a button to show/hide all props and maybe more options in the future
	if has_exposed_params:
		var ctrl = connectors_options_prefab.instantiate() as FlowConnectorOptions
		ctrl.setShowDisconnectedInputs( show_disconnected_inputs )
		ctrl.expand_toggled.connect( nodeOptionsChanged )
		add_child( ctrl )

	# Force a readjust of the node in the flow editor
	size = get_combined_minimum_size()

	if trace:
		for arg_name in args_ports_by_name.keys():
			print( "  %s : %s" % [ arg_name, args_ports_by_name[ arg_name ] ] )

	if flow_editor:
		# Reconnect nodes
		for arg_name in connected_inputs_by_name.keys():
			var old_data = connected_inputs_by_name[ arg_name ]
			if not args_ports_by_name.has( arg_name ):
				# The input is gone (a mode setting removed it): its links
				# stay disconnected instead of landing on another port.
				flow_editor.queueSave()
				continue
			var new_port = args_ports_by_name[ arg_name ].port
			for old_conn in old_data.conns:
				var from_node = old_conn[0]
				var from_port = old_conn[1]
				flow_editor.connect_nodes( from_node, from_port, name, new_port )
			flow_editor.queueSave()
		flow_editor.refreshSignalsInputArgs( self )

	_built_port_signature = port_signature()
	_built_num_flow_ins = num_ins
	_built_num_outs = num_outs

	if _element != null and _element.has_method( "widget_init" ):
		_element.widget_init( self )

## Disconnects links into flow inputs [num_ins, previous count) and out of
## outputs [num_outs, previous count). Only runs after a first build.
func _drop_links_to_removed_ports( flow_editor, num_ins : int, num_outs : int ) -> void:
	var dropped := false
	if _built_num_flow_ins > num_ins:
		for port in range( num_ins, _built_num_flow_ins ):
			for conn in flow_editor.get_connected_sources( name, port ).duplicate():
				flow_editor.disconnect_nodes( conn[0], conn[1], name, port )
				dropped = true
	if _built_num_outs > num_outs and "gedit" in flow_editor and flow_editor.gedit != null:
		for conn in flow_editor.gedit.get_connection_list():
			if conn.from_node == name and conn.from_port >= num_outs:
				flow_editor.disconnect_nodes( conn.from_node, conn.from_port, conn.to_node, conn.to_port )
				dropped = true
	if dropped and flow_editor.has_method( "queueSave" ):
		flow_editor.queueSave()

func refreshConnectionFlags( ):
	var editor = getEditor()
	if editor:
		for arg_name in args_ports_by_name:
			args_ports_by_name[ arg_name ].connected = editor.is_node_port_connected( name, args_ports_by_name[ arg_name ].port )

func nodeOptionsChanged( expanded : bool ):
	if show_disconnected_inputs == expanded:
		return
	show_disconnected_inputs = expanded
	refreshConnectionFlags( )
	initFromScript()
	setupDrawDebug()
