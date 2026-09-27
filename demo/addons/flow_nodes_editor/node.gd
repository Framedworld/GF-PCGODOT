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
# Graph seed (EvaluationContext.seed) of the evaluation this node last ran in.
# 0 = legacy: every node uses its own settings.random_seed unchanged.
var graph_seed : int = 0

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

# Last value returned by computeSceneFingerprint(); compared on editor scene
# changes so only nodes whose scene inputs actually changed are re-evaluated.
var scene_fingerprint : int = 0
var has_scene_fingerprint : bool = false

# Helper to create the UI
const connectors_row_prefab = preload( "res://addons/flow_nodes_editor/connectors_row.tscn" )
const connectors_options_prefab = preload( "res://addons/flow_nodes_editor/connectors_options.tscn" )

# Filled during runtime
var deps : Array[ Dictionary ]			# Array of graphEdit connections where I'm the target
var dependants : Array[ Dictionary ]	# Array of graphEdit connections where I'm the source
var eval_id : int = 0
var err : String

## EvaluationContext meta holding the Array that collects setError() calls for
## runtime callers (FlowNodeIO.last_errors, FlowGraphNode3D.last_errors). Set by
## FlowNodeIO.evaluate() / FlowGraphNode3D.generate(), shared by nested
## subgraph and loop evaluations. Editor contexts never carry it.
const ERROR_LOG_META := &"flow_error_log"
# The evaluation's error log while this node runs (null outside such evaluations).
var _error_log = null

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

## The one seed formula of the runtime API (docs/RUNTIME_API_P0.md §2):
## hash([graph_seed, node_seed]) & 0x7fffffff. With graph_seed == 0 the node
## seed is returned unchanged, so graphs run without a seed keep their
## historical output bit for bit. preExecute (per node) and loop (per
## iteration, with the iteration index as node_seed) both use it; hosts that
## cross-check seeds should call it rather than copy the formula.
# Editor access without naming editor-only classes. Exported builds do not have
# EditorInterface at all, and a script that merely names it fails to PARSE there
# (even inside an `if Engine.is_editor_hint()` block), so runtime-reachable
# scripts reach it through Engine's singleton table instead.

## The EditorInterface singleton while running inside the editor, else null.
static func editor_interface() -> Object:
	if Engine.is_editor_hint() and Engine.has_singleton( &"EditorInterface" ):
		return Engine.get_singleton( &"EditorInterface" )
	return null

## Root of the scene open in the editor; null outside the editor.
static func editor_edited_scene_root() -> Node:
	var ei := editor_interface()
	if ei == null:
		return null
	return ei.call( "get_edited_scene_root" ) as Node

## Marks the scene open in the editor as unsaved; no-op outside the editor.
static func editor_mark_scene_unsaved() -> void:
	var ei := editor_interface()
	if ei != null:
		ei.call( "mark_scene_as_unsaved" )

static func derive_seed( in_graph_seed : int, node_seed : int ) -> int:
	if in_graph_seed == 0:
		return node_seed
	return int( hash( [ in_graph_seed, node_seed ] ) & 0x7fffffff )

## Seed a node must use for its randomness in the current evaluation: the
## node's settings.random_seed decorrelated by the graph seed. Nodes build local
## RNGs and call FlowData.point_seed/resolve_seed with this, never with
## settings.random_seed directly. Returns 0 for nodes without random_seed. A
## seed obtained another way (e.g. a wired random_seed port read through
## getSettingValue) goes through derive_seed(graph_seed, value) instead.
func effective_seed() -> int:
	if settings == null or not ( "random_seed" in settings ):
		return 0
	return derive_seed( graph_seed, settings.random_seed )

const OWNER_REQUIRED_ERROR := "%s needs an owner node; generate through a FlowGraphNode3D or pass owner to FlowNodeIO.evaluate"

## True for the editor dock's preview of a graph that has no owner node
## (EvaluationContext.preview set by the editor, owner null). Nodes then emit
## empty Data instead of reporting missing inputs, so a half-wired graph does
## not spam errors while it is being edited. Every other evaluation, including
## @tool scripts that call FlowNodeIO.evaluate() without an owner, is not a
## preview and reports real errors.
static func is_ownerless_preview( ctx ) -> bool:
	return ctx != null and ctx.preview and ctx.owner == null

## Owner-less runtime guard (docs/RUNTIME_API_P0.md §3) for nodes that need a
## scene (spawners, scene scanners, apply_on_actor, physics/ray queries).
## When the evaluation has no owner outside the editor, reports the documented
## error, passes input 0 through to output 0 (an empty Data when unconnected)
## and returns true: the caller must return. Editor previews without an owner
## return false and keep the node's own editor handling.
func handleMissingOwner( ctx ) -> bool:
	if not reportMissingOwner( ctx ):
		return false
	var in_data = inputs[0] if inputs.size() > 0 else null
	set_output( 0, in_data if in_data is FlowData.Data else FlowData.Data.new() )
	return true

## Reports the documented owner-less error and returns true when the evaluation
## has no owner and is not an editor preview; emits nothing. Source nodes (scene
## scanners) use it directly and keep producing their empty-schema output.
func reportMissingOwner( ctx ) -> bool:
	if ctx != null and ctx.owner != null and is_instance_valid( ctx.owner ):
		return false
	if is_ownerless_preview( ctx ):
		return false
	var label := str( meta_node.get( "title", "" ) )
	if label == "":
		label = node_template if node_template != "" else String( name )
	setError( OWNER_REQUIRED_ERROR % label )
	return true

# --- Generated-content ownership (docs/RUNTIME_API_P0.md §5) -----------------

## Component id to stamp on spawned content: ctx.component_id, or the owner's
## instance id for contexts built by hand (editor, legacy callers).
static func flowComponentId( ctx ) -> int:
	if ctx == null:
		return 0
	if ctx.component_id != 0:
		return ctx.component_id
	if ctx.owner != null and is_instance_valid( ctx.owner ):
		return ctx.owner.get_instance_id()
	return 0

## `flow_owner` meta value for a subtree spawned by this node.
func flowOwnerMeta( ctx ) -> Dictionary:
	return { "component" : flowComponentId( ctx ), "node" : String( name ) }

## A component id that no longer names a live object: content saved into a
## scene by an earlier session (instance ids do not survive reloads).
static func isStaleFlowComponent( component_id : int ) -> bool:
	return component_id == 0 or not is_instance_id_valid( component_id )

## True when `meta` (a `flow_owner` value) marks content spawned by this node
## for the evaluation's component. Accepts the legacy String form (node name
## only) and stale component ids, so content saved by older versions or earlier
## sessions is still cleared.
func isOwnFlowContent( meta, ctx ) -> bool:
	if meta is String or meta is StringName:
		return String( meta ) == String( name )
	if meta is Dictionary:
		if String( meta.get( "node", "" ) ) != String( name ):
			return false
		var comp := int( meta.get( "component", 0 ) )
		return comp == flowComponentId( ctx ) or isStaleFlowComponent( comp )
	return false

## Remove the content this node spawned under `parent` for the evaluation's
## component (see isOwnFlowContent), optionally narrowed by `filter`. Nodes are
## detached immediately, so the fresh spawn keeps its names, and freed at the
## end of the frame.
func removeOwnFlowContent( parent : Node, ctx, filter : Callable = Callable() ) -> void:
	var doomed : Array[Node] = []
	for child in parent.get_children():
		if not child.has_meta( "flow_owner" ):
			continue
		if not isOwnFlowContent( child.get_meta( "flow_owner" ), ctx ):
			continue
		if filter.is_valid() and not filter.call( child ):
			continue
		doomed.append( child )
	for node in doomed:
		parent.remove_child( node )
		node.queue_free()

## Assign the scene owner of a freshly spawned node, unless the component asked
## for transient output (then it stays unowned and is never saved).
static func assignSpawnOwner( spawned : Node, scene_owner : Node, ctx ) -> void:
	# ctx.owner may be a plain Node3D host without the transient_output export.
	if ctx != null and ctx.owner != null and is_instance_valid( ctx.owner ) and ctx.owner.get( "transient_output" ) == true:
		return
	# Only an ancestor can own a node; anything else is an engine error and
	# leaves the node unowned anyway.
	if scene_owner != null and scene_owner.is_ancestor_of( spawned ):
		spawned.owner = scene_owner

func preExecute( ctx : FlowData.EvaluationContext ):
	eval_id = ctx.eval_id
	graph_seed = ctx.seed
	# get_meta with a null default still errors on a missing key: check first.
	_error_log = ctx.get_meta( ERROR_LOG_META ) if ctx != null and ctx.has_meta( ERROR_LOG_META ) else null
	setError("")
	if settings != null and "random_seed" in settings:
		rng.seed = effective_seed()
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

## Hue (0-1) per node category, matching Unreal PCG's visual language
## (generators/samplers green, filters red, ...). Keys are normalised category names
## (lower case, no spaces/underscores/dashes, trailing "s" dropped), so "Control Flow",
## "control_flow" and "ControlFlow" all match.
const CATEGORY_HUES := {
	"sampler": 0.33, "generator": 0.33,
	"spatial": 0.48,
	"filter": 0.0,
	"density": 0.91, "math": 0.91,
	"metadata": 0.78, "attribute": 0.78,
	"spawner": 0.58, "transform": 0.58,
	"controlflow": 0.17, "utility": 0.17, "debug": 0.17,
	"input": 0.08, "output": 0.08,
}

static func normalize_category(category: String) -> String:
	var key := category.strip_edges().to_lower()
	for separator in [" ", "_", "-"]:
		key = key.replace(separator, "")
	if key.length() > 1 and key.ends_with("s"):
		key = key.trim_suffix("s")
	return key

## Optional project colour for the node's category: `meta_node.color` (a Color).
## Returns null when the node does not declare one. Give every node of a project
## category the same `color` (or `hue`) so the category reads as one colour.
func _get_meta_node_color():
	var color = getMeta().get("color", null)
	if color is Color:
		return color
	return null

## Returns a hue value (0-1) for the node's title bar, first match wins:
## `meta_node.color` (its hue), `meta_node.hue` (a float, clamped to 0..1),
## the `category` metadata (see CATEGORY_HUES), then a stable hash of the
## template name for nodes without a known category.
func _get_category_hue() -> float:
	var meta := getMeta()
	var meta_color = _get_meta_node_color()
	if meta_color is Color:
		return meta_color.h
	var meta_hue = meta.get("hue", null)
	if typeof(meta_hue) == TYPE_FLOAT or typeof(meta_hue) == TYPE_INT:
		return clampf(float(meta_hue), 0.0, 1.0)
	var category := String(meta.get("category", ""))
	var key := normalize_category(category)
	if CATEGORY_HUES.has(key):
		return CATEGORY_HUES[key]
	return float(node_template.hash() % 360) / 360.0

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
	elif is_colored and _get_meta_node_color() is Color:
		# Project category colour from meta_node.color, tinted like custom colours.
		var meta_color : Color = _get_meta_node_color()
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

	if draw_debug and ( not settings.debug_enabled or settings.disabled ):
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
		# Runtime callers read these back (FlowNodeIO.last_errors).
		if _error_log is Array:
			_error_log.append( { "node": String( name ), "template": node_template, "message": new_err } )
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
					var num_elems = stream.container.size()
					if num_elems == 0:
						# Empty container: nothing to read, fall back to the
						# settings/default value
						if trace:
							print( "  -> Input %s has an empty container, keeping %s" % [ in_name, value ])
					else:
						# One element is the normal parameter case; with more
						# than one element we keep reading the first (broadcast)
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

# --- Scene fingerprints --------------------------------------------------
# When the edited scene changes (any undo/redo history entry: moving a light,
# a camera, an unrelated node...) the editor asks every graph node for a
# fingerprint of the scene data it reads. Only nodes whose fingerprint changed
# are marked dirty, so edits that do not affect the graph never trigger a
# regen. Return values of computeSceneFingerprint():
#   SCENE_INDEPENDENT - node never reads the scene, scene edits can be ignored
#   null              - node reads the scene but cannot cheaply summarize it,
#                       assume it changed (conservative full re-eval)
#   int               - hash of the scene data the node depends on

const SCENE_INDEPENDENT := &"scene_independent"

# Node templates whose output reads live scene state. Used to decide whether a
# nested graph (subgraph/loop) must re-run after a scene edit. Keep in sync
# with the scans_scene / queries_physics meta flags in the node scripts.
const SCENE_DEPENDENT_TEMPLATES := [
	"scan_meshes", "scan_splines", "scan_nodes", "points_from_scene",
	"points_from_gridmap", "points_from_tilemap", "point_from_player_pawn",
	"navigation_region_sampler", "ray_cast", "physics_overlap_query",
	"physics_shape_sweep", "projection", "subgraph", "loop",
]

func computeSceneFingerprint( ctx : FlowData.EvaluationContext ) -> Variant:
	var meta := getMeta()
	if meta.get( "queries_physics", false ):
		return physicsSceneFingerprint( ctx )
	if meta.get( "scans_scene", false ):
		return null
	return SCENE_INDEPENDENT

# Nodes spawned by a flow graph carry the "flow_owner" meta on their subtree
# root. They are removed before every evaluation, so fingerprints must skip
# them or the spawn/compare cycle would report a phantom scene change.
func isGeneratedSceneNode( node : Node ) -> bool:
	var current := node
	while current:
		if current.has_meta( "flow_owner" ):
			return true
		current = current.get_parent()
	return false

func filterOutGeneratedNodes( nodes : Array ) -> Array:
	return nodes.filter( func( n ): return n != null and not isGeneratedSceneNode( n ) )

func hashSceneNodesForFingerprint( ctx : FlowData.EvaluationContext, nodes : Array, extra : Array = [] ) -> int:
	var items := []
	# Generated output is parented under the graph owner, so the owner's own
	# transform is an implicit input of every scene-dependent node.
	if ctx and ctx.owner and is_instance_valid( ctx.owner ):
		items.append( ctx.owner.global_transform )
	for node in nodes:
		if node == null or not is_instance_valid( node ) or not node.is_inside_tree():
			continue
		items.append( String( node.get_path() ) )
		items.append( node.get( "global_transform" ) )
		items.append( node.get( "visible" ) )
	items.append_array( extra )
	return items.hash()

# Summary of everything the editor-world physics queries can hit. Colliders,
# shapes, gridmaps and CSG transforms are included; lights/cameras are not,
# so moving those never re-triggers raycast/overlap/sweep nodes.
func physicsSceneFingerprint( ctx : FlowData.EvaluationContext ) -> Variant:
	if ctx == null or ctx.owner == null or not is_instance_valid( ctx.owner ):
		return null
	var root := getSceneRootNode3d( ctx.owner )
	if root == null:
		return null
	var items := []
	items.append( ctx.owner.global_transform )
	_appendPhysicsFingerprintItems( root, items )
	return items.hash()

func _appendPhysicsFingerprintItems( node : Node, items : Array ) -> void:
	if node.has_meta( "flow_owner" ):
		return
	if node is CollisionObject3D:
		items.append( String( node.get_path() ) )
		items.append( node.global_transform )
		items.append( node.collision_layer )
		items.append( node.visible )
	elif node is CollisionShape3D:
		items.append( node.transform )
		items.append( node.disabled )
		var shape : Shape3D = node.shape
		if shape:
			items.append( shape.get_instance_id() )
			# Cover in-place edits of the common primitive shapes
			for prop in [ "size", "radius", "height" ]:
				var value = shape.get( prop )
				if value != null:
					items.append( value )
	elif node is CollisionPolygon3D:
		items.append( node.transform )
		items.append( node.disabled )
		items.append( node.polygon )
		items.append( node.depth )
	elif node.is_class( "GridMap" ):
		items.append( String( node.get_path() ) )
		items.append( node.get( "global_transform" ) )
		items.append( node.get( "cell_size" ) )
		items.append( node.call( "get_used_cells" ) )
	elif node.is_class( "CSGShape3D" ):
		items.append( String( node.get_path() ) )
		items.append( node.get( "global_transform" ) )
		items.append( node.get( "use_collision" ) )
	for child in node.get_children():
		_appendPhysicsFingerprintItems( child, items )

# Fingerprint helper for nodes that evaluate a nested graph resource: scene
# edits only matter when the nested graph itself contains scene-reading nodes.
func nestedGraphSceneFingerprint( graph_resource ) -> Variant:
	if graph_resource == null:
		return SCENE_INDEPENDENT
	var data = graph_resource.get( "data" )
	if data == null or not data.has( "nodes" ):
		return SCENE_INDEPENDENT
	for n_data in data["nodes"]:
		if n_data.get( "template", "" ) in SCENE_DEPENDENT_TEMPLATES:
			return null
	return SCENE_INDEPENDENT

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

## Input guard (PARITY_PLAN #4): returns the FlowData.Data connected at `port`,
## or null after handling the error path. Handles every failure shape an input
## read can produce: null (not connected), [] (out-of-range port) and any other
## non-Data value. In an owner-less editor preview (is_ownerless_preview: the
## editor set ctx.preview and there is no owner) it emits an empty Data on
## output 0 and stays silent so disconnected graphs don't spam errors;
## otherwise it reports "<error_label> not connected".
func require_input( port : int, ctx, error_label := "Input" ) -> FlowData.Data:
	var raw = inputs[ port ] if port >= 0 and port < inputs.size() else null
	if raw is FlowData.Data:
		return raw
	if is_ownerless_preview( ctx ):
		set_output( 0, FlowData.Data.new() )
		return null
	setError( "%s not connected" % error_label )
	return null

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
