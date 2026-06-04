@tool
class_name FlowNodeBase
extends GraphNode

# This represent the base class for all nodes in the flow graph
# The actual nodes are implemented in the nodes subfolder

@export var settings: NodeSettings:
	set(new_value):
		if settings and settings.changed.is_connected(_on_settings_changed):
			settings.changed.disconnect(_on_settings_changed)
		settings = new_value
		if settings:
			settings.changed.connect(_on_settings_changed)

func _exit_tree():
	if settings and settings.changed.is_connected(_on_settings_changed):
		settings.changed.disconnect(_on_settings_changed)

func _on_settings_changed():
	dirty = true
	refreshFromSettings()
	var editor = getEditor()
	if editor:
		editor.queueRegen()

var rng : RandomNumberGenerator = RandomNumberGenerator.new()

# Common attributes ------------------------------
var num_connected_bulks : int = 0
var input_bulks : Array
var num_generated_bulks : int = 0
var generated_bulks : Array
var inputs = []

var args_ports_by_name = {}
var num_in_ports : int = 0
var num_out_ports : int = 0
var num_ports : int = 0			 # Max of (in,out)
var meta_node: Dictionary = {}

var node_template : String
var show_disconnected_inputs : bool = false

var dirty : bool = false

# Helper to create the UI
const connectors_row_prefab = preload( "res://addons/flow_nodes_editor/connectors_row.tscn" )
const connectors_options_prefab = preload( "res://addons/flow_nodes_editor/connectors_options.tscn" )

# Filled during runtime
var deps : Array[ Dictionary ]			# Array of graphEdit connections where I'm the target
var dependants : Array[ Dictionary ]	# Array of graphEdit connections where I'm the source
var eval_id : int = 0
var err : String

# Render
var draw_debug : NodeDrawDebug
var ui_scale = 1.0
var marker_radius : float = 9

var debug_row : int = -1

func _ready():
	ignore_invalid_connection_type = true
	checkDrawDebug()
	refreshInspectMark()
	refreshDebugMark()
	update_node_style()
	
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
		lines.append("%s: %d pts, %d streams" % [port_label, summary.points, summary.streams])
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
	for si in s.stream_info:
		parts.append("%s(%s)" % [si.name, si.type])
	return "%d pts — %s" % [s.points, ", ".join(parts)]

func preExecute( ctx : FlowData.EvaluationContext ):
	eval_id = ctx.eval_id
	setError("")
	if settings != null and "random_seed" in settings:
		rng.seed = settings.random_seed
	num_generated_bulks = 0
	num_connected_bulks = 0
	input_bulks = []
	generated_bulks = []
	
	for conn in deps:
		if conn.get("virtual_variable", false):
			continue
		# The number of bulkds in the pin 0 defines how many bulks we are going to generate
		if conn.to_port == 0:
			var node = ctx.gedit_nodes_by_name.get( conn.from_node )
			if node:
				num_connected_bulks += node.num_generated_bulks
	if num_connected_bulks == 0:
		num_connected_bulks = 1

func redrawUI():
	queue_redraw()

func refreshDebugMark():
	redrawUI()

func refreshInspectMark():
	redrawUI()
	
func onPropChanged( prop_name : String ):
	dirty = true

func get_deterministic_color() -> Color:
	var h_hash = node_template.hash()
	var hue = float(h_hash % 360) / 360.0
	# We want premium colors, so let's set saturation to around 0.5 and value/brightness to 0.75
	return Color.from_hsv(hue, 0.5, 0.75)

## Returns a hue value (0-1) based on the node's functional category.
## Matches Unreal PCG's visual language: generators=green, filters=red, etc.
func _get_category_hue() -> float:
	var t := node_template
	# Input/Output — warm orange
	if t.begins_with("input") or t.begins_with("output"):
		return 0.08
	# Filters — red/coral
	if t.begins_with("filter") or t == "attribute_filter_range" or t == "select" or t == "select_multi" or t == "select_points" or t == "self_pruning" or t == "partition" or t == "branch" or t == "switch":
		return 0.0
	# Generators/Sources — green
	if t.begins_with("grid") or t.begins_with("sample") or t.begins_with("points_from") or t.begins_with("point_from") or t.begins_with("scan") or t.begins_with("noise") or t.begins_with("load") or t.begins_with("create") or t.begins_with("dungeon"):
		return 0.33
	# Transforms — blue
	if t == "transform" or t == "transform_points" or t == "point_offsets" or t == "snap_to_grid" or t == "copy" or t == "copy_points" or t == "duplicate_point" or t.begins_with("spawn") or t == "apply_on_actor" or t == "relax" or t.begins_with("build_rotation"):
		return 0.58
	# Attributes — purple
	if t.begins_with("attribute") or t.begins_with("add_attribute") or t == "remove_attribute" or t.begins_with("add_tag") or t.begins_with("delete_tag") or t.begins_with("replace_tag") or t.begins_with("tags_mutate") or t == "random_color" or t.begins_with("data_table"):
		return 0.78
	# Math/Logic — pink
	if t == "math_op" or t == "expression" or t.begins_with("compose_vector") or t.begins_with("decompose_vector") or t.begins_with("make_vector") or t == "remap" or t.begins_with("density") or t.begins_with("distance") or t == "boolean" or t == "reduce" or t.begins_with("curve_remap"):
		return 0.91
	# Spatial/Physics — teal
	if t.begins_with("physics") or t.begins_with("ray_cast") or t.begins_with("navigation") or t.begins_with("clip") or t.begins_with("bounds") or t.begins_with("difference") or t.begins_with("intersection") or t == "union" or t.begins_with("polygon"):
		return 0.48
	# Merge/Combine — cyan
	if t == "merge" or t == "merge_points" or t == "combine_points" or t == "sequence_sample":
		return 0.53
	# Subgraph — bright cyan
	if t == "subgraph":
		return 0.53
	# BL project-specific — indigo
	if t.begins_with("bl_"):
		return 0.72
	# Debug/Utility — neutral
	if t == "debug" or t == "print_string" or t == "sanity_check" or t == "get_points_count" or t == "get_data_count" or t == "get_entries_count" or t == "get_loop_index" or t == "loop" or t == "mutate_seed":
		return 0.17
	# Fallback: hash-based
	return float(t.hash() % 360) / 360.0

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

	var cat_hue := _get_category_hue()

	var is_colored = false
	var editor = getEditor()
	if editor and "color_nodes" in editor and editor.color_nodes:
		is_colored = true

	var custom_node_color = null
	if has_method("_get_custom_node_color"):
		custom_node_color = call("_get_custom_node_color")

	if custom_node_color is Color:
		var color : Color = custom_node_color
		var sb_title = _make_tinted_graph_node_stylebox("titlebar", color.darkened(0.62))
		if sb_title:
			add_theme_stylebox_override("titlebar", sb_title)

		var sb_title_selected = _make_tinted_graph_node_stylebox("titlebar_selected", color.darkened(0.48))
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

func _gui_input(event: InputEvent) -> void:
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

func refreshFromSettings():
	refreshDebugMark()
	refreshInspectMark()
	refreshLocalizedText()
	modulate = Color( 0.7, 0.7, 0.7, 0.5 ) if settings.disabled else Color.WHITE
	
	update_node_style()
	
	if ( not settings.debug_enabled and draw_debug ) or settings.disabled:
		draw_debug.cleanup_multimesh_direct()
	
	if settings and "data_type" in settings and node_template != "add_attribute" and node_template != "attribute_random":
		var meta := getMeta()
		var outs = meta.get("outs", [])
		for idx in range(outs.size()):
			var out_data = outs[idx]
			if out_data:
				var data_type = out_data.get("data_type", FlowData.DataType.Invalid)
				if data_type == FlowData.DataType.Invalid:
					var color = getColorForFlowDataType(settings.data_type)
					if is_slot_enabled_right(idx):
						set_slot_color_right(idx, color)
						set_slot_type_right(idx, settings.data_type)
	
func setError( new_err : String ):
	if new_err:
		push_error( "Node.Err %s : %s" % [ name, new_err ])
		editor_state_changed.emit()
	err = new_err
	redrawUI()
		
func setActivity( amount : float ):
	if settings.disabled:
		return
	if not err:
		modulate = Color.WHITE + Color( amount, amount, amount, 0.0 )
	else:
		modulate = Color(1.0, 0.5, 0.5)



func setExecTime(usec: int):
	set_meta("exec_time_usec", usec)
	if is_inside_tree():
		queue_redraw()
		
func _on_draw() -> void:
	
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

	# Draw point count badges on output ports
	_draw_output_badges()

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

func _draw_output_badges():
	var output_summaries = get_meta("output_summaries", [])
	if output_summaries.is_empty():
		return
	var font = ThemeDB.fallback_font
	var font_size := int(10 * ui_scale)
	var badge_h := font_size + 4
	
	var port_controls = get_children().filter(func(c): return c is FlowConnectorRow)
	
	for port_idx in range(mini(output_summaries.size(), num_out_ports)):
		var summary = output_summaries[port_idx]
		if summary == null:
			continue
		var pts = summary.points
		var badge_text: String
		if pts >= 1000:
			badge_text = "%.*fk" % [1, pts / 1000.0]
		else:
			badge_text = "%d pts" % pts
		
		# Get the Y position of this output port using custom control filter (safer than get_output_port_position)
		var port_y := 0.0
		if port_idx < port_controls.size():
			var ctrl = port_controls[port_idx]
			port_y = ctrl.position.y + ctrl.size.y * 0.5
		else:
			continue # if control isn't in tree yet
			
		var text_width = font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var badge_w = text_width + 8
		
		# Draw badge background (pill shape)
		var badge_x = size.x - badge_w - 18 * ui_scale
		var badge_y = port_y - badge_h * 0.5
		var badge_sb = StyleBoxFlat.new()
		badge_sb.bg_color = Color(0.13, 0.72, 0.93, 0.2) # Subtle cyan
		badge_sb.set_corner_radius_all(int(badge_h * 0.5))
		draw_style_box(badge_sb, Rect2(badge_x, badge_y, badge_w, badge_h))
		
		# Draw badge text
		var text_y = badge_y + badge_h - 3
		draw_string(font, Vector2(badge_x + 4, text_y), badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.13, 0.72, 0.93, 0.85))

func getMeta() -> Dictionary:
	return meta_node
	
func getTitle() -> String:
	if settings:
		return settings.title
	return str(getMeta().get("title", ""))

func getLocalizedTitle() -> String:
	return _localized_node_text(getTitle())

func getTooltip() -> String:
	return _localized_node_text(str(getMeta().get("tooltip", "")))

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

func shuffleArray(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = arr[i]
		arr[i] = arr[j]
		arr[j] = temp

static func editorDisplayName(property_name: String) -> String:
	var parts = property_name.split("_")
	for i in parts.size():
		parts[i] = parts[i].capitalize()
	return " ".join(parts)

static func getColorForFlowDataType( data_type : FlowData.DataType ) -> Color:
	match( data_type ):
		FlowData.DataType.Bool:
			return Color("ef4444")
		FlowData.DataType.Int:
			return Color("c8c8c8")
		FlowData.DataType.Float:
			return Color("c8c8c8")
		FlowData.DataType.Vector:
			return Color("a855f7")
		FlowData.DataType.Color:
			return Color("eab308")
		FlowData.DataType.String:
			return Color("3b82f6")
		FlowData.DataType.Resource:
			return Color("22c55e")
		FlowData.DataType.NodeMesh:
			return Color("22c55e")
		FlowData.DataType.NodePath:
			return Color("14b8a6")
	return Color("22d3ee") # Default cyan flow color

static func getGdScriptTypeForFlowDataType( data_type : FlowData.DataType ) -> int:
	match( data_type ):
		FlowData.DataType.Bool:
			return TYPE_BOOL
		FlowData.DataType.Int:
			return TYPE_INT
		FlowData.DataType.Float:
			return TYPE_FLOAT
		FlowData.DataType.String:
			return TYPE_STRING
		FlowData.DataType.Vector:
			return TYPE_VECTOR3
		FlowData.DataType.Color:
			return TYPE_COLOR
	return TYPE_NIL
	
static func getFlowDataTypeFromGdScriptType( gd_type : int  ) -> FlowData.DataType:
	match( gd_type ):
		TYPE_BOOL:
			return FlowData.DataType.Bool
		TYPE_INT:
			return FlowData.DataType.Int
		TYPE_FLOAT: 
			return FlowData.DataType.Float
		TYPE_STRING:
			return FlowData.DataType.String 
		TYPE_VECTOR3:
			return FlowData.DataType.Vector
		TYPE_COLOR:
			return FlowData.DataType.Color
	return FlowData.DataType.Invalid

static func getFlowDataTypeFromObject( obj  ) -> FlowData.DataType:
	var data_type = getFlowDataTypeFromGdScriptType( typeof(obj) ) 
	if data_type != FlowData.DataType.Invalid:
		return data_type
	if obj is Resource:
		return FlowData.DataType.Resource
	return data_type

func exposedAsInputNode( prop ):
	if prop.name == "graph":
		return false
	return true

func getExposedParams():
	var meta := getMeta()
	if meta.get( "hide_inputs", false ):
		return []
	var trace = meta.get( "trace", false )
	var my_title : String = meta.title
	var props = settings.get_property_list()
	var inside_my_vars := false
	var params = []
	for prop in props:
		if trace:
			print( "Input.", prop.name)
		if prop.name == "node_settings.gd":
			break
		if prop.name == "HiddenFromThisPoint":
			break
		if prop.name == my_title:
			inside_my_vars = true
		if !(prop.usage & PROPERTY_USAGE_STORAGE) || !(prop.usage & PROPERTY_USAGE_EDITOR):
			continue
		if !inside_my_vars:
			continue
			
		var data = {
			"name" : prop.name,
			"label" : editorDisplayName( prop.name ),
			"type" : prop.type,
			"data_type" : getFlowDataTypeFromGdScriptType( prop.type ),
			"is_parameter" : true,
			"port" : -1,
		}
		
		if not exposedAsInputNode( data ):
			continue
		
		params.append( data )
	return params

func getEditor():
	var gedit = get_parent_control() as GraphEdit
	var flow_editor = gedit.get_parent_control().get_parent_control().get_parent_control() as Control if gedit else null
	return flow_editor

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
	
	args_ports_by_name = {}
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
				data_type = getFlowDataTypeFromGdScriptType( in_data.type )
			if data_type != FlowData.DataType.Invalid:
				var color = getColorForFlowDataType( data_type )	
				set_slot_color_left( idx, color )
				set_slot_type_left( idx, data_type )
				
			in_data.port = idx
			ctrl.setData( in_data )
			
			args_ports_by_name[ in_name ] = { "port" : idx, "connected" : connected_inputs_by_name.has( in_name ) }
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
					data_type = getFlowDataTypeFromGdScriptType( out_data.type )
				if data_type == FlowData.DataType.Invalid and settings and "data_type" in settings and node_template != "add_attribute" and node_template != "attribute_random":
					data_type = settings.data_type
				if data_type != FlowData.DataType.Invalid:
					var color = getColorForFlowDataType( data_type )	
					set_slot_color_right( idx, color )
					set_slot_type_right( idx, data_type )					
					
		else:
			lbl_out.text = ""
	
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
			var old_port = old_data.port
			var new_port = args_ports_by_name[ arg_name ].port
			for old_conn in old_data.conns:
				var from_node = old_conn[0]
				var from_port = old_conn[1]
				flow_editor.connect_nodes( from_node, from_port, name, new_port )
			flow_editor.queueSave()
		flow_editor.refreshSignalsInputArgs( self )
	
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
	
# This returns the current value of the input configuration taking into account potencial connections and overrides of the inputs
func getSettingValue( ctx : FlowData.EvaluationContext, in_name : String, default_value = null):
	var meta = getMeta()
	var trace = meta.get( "trace", false )
	
	var value = settings.get( in_name )
	if value == null:
		value = default_value
	if trace:
		print( "Searching the current value of input %s in %d inputs at node %s. ByName:%s vs %s.   Meta:%s" % [ in_name, inputs.size(), name, args_ports_by_name, inputs, meta ] )
	if args_ports_by_name.has( in_name ):
		var port = args_ports_by_name[ in_name ].port
		if port >= 0 and port < inputs.size():
			var input = inputs[ port ] as FlowData.Data
			if input:
				var in_streams = input.streams
				if trace:
					print( "Got the input for %s : %s" % [ in_name, in_streams.keys() ] )
				if in_streams and in_streams.size() == 1:
					var stream = in_streams.values()[0]
					var in_size = in_streams.size()
					if in_size == 0:
						setError( "Input %s has no data" % in_name)
					elif in_size > 1:
						setError( "Input %s has too many data (%d)" % [ in_name, in_size ])
					else:
						var new_value = stream.container[0]
						if trace:
							print( "  -> Using %s = %s" % [ in_name, new_value ])
						if typeof( new_value ) != typeof( value ):
							push_warning( "  Type of %s (%d) does not match the expected type (%d)" % [ in_name, typeof(new_value), typeof(value) ])
							
						return new_value
	return value

func newStream( size : int, new_name : String, init_value, data_type : FlowData.DataType ):
	var new_container = FlowData.Data.newContainerOfType( data_type )
	new_container.resize( size )
	if typeof(init_value) == TYPE_CALLABLE:
		var fn : Callable = init_value
		match data_type:
			FlowData.DataType.Bool:
				var typed_container : PackedByteArray = new_container
				for idx in size:
					typed_container[idx] = fn.call(idx)
			FlowData.DataType.Int:
				var typed_container : PackedInt32Array = new_container
				for idx in size:
					typed_container[idx] = fn.call(idx)
			FlowData.DataType.Float:
				var typed_container : PackedFloat32Array = new_container
				for idx in size:
					typed_container[idx] = fn.call(idx)
			FlowData.DataType.Vector:
				var typed_container : PackedVector3Array = new_container
				for idx in size:
					typed_container[idx] = fn.call(idx)
			FlowData.DataType.Color:
				var typed_container : PackedColorArray = new_container
				for idx in size:
					typed_container[idx] = fn.call(idx)
			FlowData.DataType.String:
				var typed_container : PackedStringArray = new_container
				for idx in size:
					typed_container[idx] = fn.call(idx)
			FlowData.DataType.Resource:
				var typed_container : Array = new_container
				for idx in size:
					typed_container[idx] = fn.call(idx)
			_:
				push_error( "newStream(%d) type not supported" % [ data_type ])
				return null
	else:
		new_container.fill( init_value )
	return { 
		"data_type" : data_type,
		"container" : new_container,
		"name" : new_name
	}
	
func newFloatStream( size : int, new_name : String, init_value ):
	return newStream( size, new_name, init_value, FlowData.DataType.Float )

func getSceneRootNode3d( current : Node3D ) -> Node3D:
	while current and current.get_parent_node_3d():
		current = current.get_parent_node_3d()
	return current

func findNodesMatchingFilters( ctx : FlowData.EvaluationContext, filter_by_class_name : String ) -> Array[ Node3D ]:

	var group_name = getSettingValue( ctx, "group_name" )
	
	var all_nodes : Array[Node] = []
	#var scene_root = ctx.owner.get_tree().root
	if group_name:
		all_nodes = ctx.owner.get_tree().get_nodes_in_group( group_name )
	elif ctx.owner:
		var root = getSceneRootNode3d( ctx.owner )
		all_nodes = root.get_children()
	
	if settings.trace:
		print( "all_nodes", all_nodes )
	
	# Filter to only include nodes in the current scene
	var scene_nodes : Array[ Node3D ] = []
	for node in all_nodes:
		var node3d := node as Node3D
		if node3d:
			if filter_by_class_name and not node3d.is_class( filter_by_class_name ):
				if settings.trace:
					print( "%s.%s discarted by class_name %s" % [ node3d.name, node3d.get_class(), filter_by_class_name ])
				continue
			scene_nodes.append(node3d)
	return scene_nodes

# --------------------------------------------------------------------------
func set_output( port_idx : int, data : FlowData.Data ):
	if port_idx == 0:
		num_generated_bulks += 1
		generated_bulks.append( [] )
	var bulk : Array = generated_bulks[ num_generated_bulks - 1]
	if port_idx >= bulk.size():
		bulk.resize( port_idx + 1 )
	#print( "Saving bulk %d, port %d with %s (%d entries)" % [ num_generated_bulks - 1, port_idx, data.streams.keys(), data.size() ] )
	bulk[ port_idx ] = data
	
func get_input( idx : int ):
	if idx >= inputs.size():
		push_error( "Input.%d does not exists in node %s" % [ idx, name ])
		return []
	return inputs[ idx ]

func get_optional_input( idx : int ):
	if idx >= inputs.size():
		return null
	return inputs[ idx ]

func get_bulk_input( bulk_idx : int, port_idx : int ):
	if bulk_idx < input_bulks.size() && port_idx < getMeta().ins.size():
		return input_bulks[ bulk_idx ][ port_idx ]
	return null
	
func get_bulk_output( bulk_idx : int, port_idx : int ):
	if bulk_idx >= generated_bulks.size():
		push_error( "Node %s has not generated bulk %d" % [ name, bulk_idx ])
		return FlowData.Data.new()
	if port_idx >= generated_bulks[ bulk_idx ].size():
		push_error( "Node %s bulk %d has not generated output %d" % [ name, bulk_idx, port_idx ])
		return FlowData.Data.new()
	return generated_bulks[ bulk_idx ][ port_idx ]

func execute( ctx ):
	pass

func _getInputForBulkInContext( ctx : FlowData.EvaluationContext, bulk_idx : int, port_idx : int ):
	var bulk_counter = 0
	#print( "_getInputForBulkInContext( %d, %d )" % [ bulk_idx, port_idx ] )
	for conn in deps:
		var to_port = conn.to_port
		if to_port != port_idx:
			continue
		var src_node = ctx.gedit_nodes_by_name.get( conn.from_node )
		if not src_node:
			continue
		#print( "  Found.src_node is %s. Has generated %d bulks. So far we have explored %d bulks" % [ src_node, src_node.generated_bulks.size(), bulk_counter ] )
		var from_port = conn.from_port
		for input_bulk_idx in range( src_node.generated_bulks.size() ):
			if bulk_counter == bulk_idx:
				return src_node.get_bulk_output( input_bulk_idx, from_port )
			bulk_counter += 1
	return null

func readAllInputsForBulk( ctx : FlowData.EvaluationContext, bulk_idx : int ):
	inputs = []
	var num_inputs : int = getMeta().ins.size()
	for port_idx in range( num_inputs ):
		inputs.append( _getInputForBulkInContext( ctx, bulk_idx, port_idx ))
	
	# Read the options inputs, assuming they only generate a single bulk
	var option_idx = num_inputs
	for conn in deps:
		if conn.to_port >= num_inputs:
			#print( "Checking conn %s" % conn )
			var config_input = _getInputForBulkInContext( ctx, 0, conn.to_port )
			#print( "  -> %s" % config_input.streams  )
			if conn.to_port >= inputs.size():
				inputs.resize( conn.to_port + 1 )
			inputs[ conn.to_port ] = config_input
			option_idx += 1
	input_bulks.append( inputs )

# Defines the behaviour of the node in it's disabled status
# The default behaviour is to pass all inputs as outputs	
func executedDisabled( ctx : FlowData.EvaluationContext ):
	for bulk_index in range( num_connected_bulks ):
		readAllInputsForBulk( ctx, bulk_index )
		if inputs.size() > 0:
			set_output( 0, inputs[0] )

func run( ctx : FlowData.EvaluationContext ):
	for bulk_index in range( num_connected_bulks ):
		readAllInputsForBulk( ctx, bulk_index )
		if settings.trace:
			print( "%s Inputs for bulk %d/%d are %s" % [ name, bulk_index, num_connected_bulks, inputs ])
		execute( ctx )
