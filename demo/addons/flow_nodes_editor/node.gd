@tool
class_name FlowNodeBase
extends RefCounted

## Runtime element of a flow graph node (Unreal's IPCGElement analogue).
##
## Every node script in nodes/ extends this class. An element holds the node's
## settings, its inputs and generated bulks for one evaluation, and the
## execute() logic. It is a RefCounted: evaluators create fresh elements per
## run and drop them afterwards (there is nothing to free()), and an element
## can run on a WorkerThreadPool thread when FlowNodeTraits says it is pure.
##
## The graph editor shows each element through a FlowNodeWidget (a GraphNode,
## executor/flow_node_widget.gd) that owns one element and hosts all UI: port
## rows, theming, tooltips, debug draw, error text, the execution-time badge,
## slot types and colours. The element never touches the scene tree or a
## Control; it talks to its widget only through the signals below and the
## optional UI hooks.
##
## Optional UI hooks. A node that builds UI implements any of these; the widget
## calls them, the runtime never does. `widget` is the FlowNodeWidget.
##
##   func widget_init(widget) -> void
##       After the widget (re)built its port rows (FlowNodeWidget.initFromScript).
##       Add extra controls (buttons, option menus) or restyle the rows here.
##   func widget_ready(widget) -> void
##       From the widget's _ready(): connect editor signals, set sizes and
##       mouse/selection flags.
##   func widget_gui_input(widget, event : InputEvent) -> bool
##       Before the widget's default input handling. Return true when the event
##       was consumed (the default click/selection handling is then skipped).
##   func widget_exit_tree(widget) -> void
##       From the widget's _exit_tree(): disconnect what widget_ready connected.
##   func widget_refresh(widget) -> void
##       At the end of every widget refresh (FlowNodeWidget.refreshFromSettings):
##       title, slot colours, option lists derived from the settings.
##   func widget_draw(widget) -> bool
##       From the widget's draw callback. Return true to replace the default
##       drawing (error text, inspect/debug markers, exec-time badge).
##   func widget_script() -> Script
##       A FlowNodeWidget subclass to use for this node instead of the default
##       widget (reroute uses it to draw its own ports).
##
## Compatibility shims: getEditor(), initFromScript(), setupDrawDebug(),
## redrawUI(), setActivity() and setExecTime() forward to the widget when one
## is bound and do nothing otherwise, so node code written for the old
## GraphNode base keeps working in the editor and is a no-op at runtime.

## The node's error text changed (setError). Empty string clears it.
signal error_changed(message : String)
## The node asks its widget to redraw (markers, error text).
signal redraw_requested
## The node asks its widget to rebuild the UI derived from its settings.
signal refresh_requested
## `settings` was replaced (e.g. the editor's scratch bindings copy).
signal settings_replaced(old_settings : NodeSettings, new_settings : NodeSettings)

## Node name in the graph (unique within one graph).
var name : StringName = &""

var settings : NodeSettings:
	set(new_value):
		var old_value := settings
		settings = new_value
		if _widget != null and old_value != new_value:
			settings_replaced.emit(old_value, new_value)

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

# Editor bookkeeping: set when the node's settings or inputs changed since it
# last ran in the editor dock. The runtime ignores it.
var dirty : bool = false

# Last value returned by computeSceneFingerprint(); compared on editor scene
# changes so only nodes whose scene inputs actually changed are re-evaluated.
var scene_fingerprint : int = 0
var has_scene_fingerprint : bool = false

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
# Error logs are shared by every element of an evaluation tree; threaded runs
# append from worker threads.
static var _error_log_mutex := Mutex.new()
# Threaded mode (FlowExecutor): an element running on a WorkerThreadPool thread
# queues its push_error text here instead of printing it, and the executor
# prints the queue on the main thread. Godot calls every Logger (including
# script loggers such as test harnesses) on the thread that raised the error,
# so routing node errors through the main thread keeps loggers single-threaded.
var _defer_error_push : bool = false
var _deferred_error_pushes : PackedStringArray = PackedStringArray()

# The FlowNodeWidget showing this element in the editor, or null (runtime).
# Plain Object reference: the widget owns the element, never the reverse.
var _widget : Object = null

## The widget showing this element, or null at runtime.
func get_widget():
	if _widget != null and is_instance_valid(_widget):
		return _widget
	return null

# --- Compatibility shims (forward to the widget when bound) --------------------

## The FlowEditor dock showing this node, or null (runtime / not in a dock).
func getEditor():
	var w = get_widget()
	return w.getEditor() if w != null else null

## Rebuilds the widget's port rows. No-op without a widget.
func initFromScript():
	var w = get_widget()
	if w != null:
		w.initFromScript()

## Refreshes debug draw and output summaries on the widget. No-op at runtime.
func setupDrawDebug():
	var w = get_widget()
	if w != null:
		w.setupDrawDebug()

func redrawUI():
	if _widget != null:
		redraw_requested.emit()

func refreshDebugMark():
	redrawUI()

func refreshInspectMark():
	redrawUI()

func setActivity( amount : float ):
	var w = get_widget()
	if w != null:
		w.setActivity( amount )

func setExecTime( usec : int ):
	var w = get_widget()
	if w != null:
		w.setExecTime( usec )

## Kept so node scripts that call super._ready() / super._exit_tree() /
## super._gui_input() still parse. Elements are not in the scene tree; these are
## never called by the engine. Use the widget_* hooks instead.
func _ready():
	pass

func _exit_tree():
	pass

func _gui_input( _event ) -> void:
	pass

func onPropChanged( prop_name : String ):
	dirty = true

## Called after settings were applied (evaluator) or edited (editor). The base
## asks the widget, when there is one, to refresh its UI; overrides that derive
## state from settings call super.refreshFromSettings().
func refreshFromSettings():
	if _widget != null:
		refresh_requested.emit()

func setError( new_err : String ):
	if new_err:
		if _defer_error_push:
			_deferred_error_pushes.append( "Node.Err %s : %s" % [ name, new_err ])
		else:
			push_error( "Node.Err %s : %s" % [ name, new_err ])
		# Runtime callers read these back (FlowNodeIO.last_errors).
		if _error_log is Array:
			_error_log_mutex.lock()
			_error_log.append( { "node": String( name ), "template": node_template, "message": new_err } )
			_error_log_mutex.unlock()
	var changed := new_err != err
	err = new_err
	if _widget != null and ( changed or new_err ):
		error_changed.emit( new_err )

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

## `flow_owner` meta value for a subtree spawned by this node. Prefer
## tagFlowContent(node, ctx), which also records the content on the component.
## A direct call cannot tell the component where the content goes, so that
## component's next cleanup() falls back to scanning its scene (see
## FlowGraphNode3D.note_untracked_content).
func flowOwnerMeta( ctx ) -> Dictionary:
	var comp = _flowComponentObject( ctx )
	if comp != null:
		comp.note_untracked_content()
	return _flowOwnerMetaValue( ctx )

## Stamps the `flow_owner` meta on spawned content `node` (a subtree root) and
## records it on the evaluation's component, so FlowGraphNode3D.cleanup() finds
## it through its spawn parent without scanning the scene. Every stock spawner
## tags its content through this.
func tagFlowContent( node : Node, ctx ) -> void:
	node.set_meta( "flow_owner", _flowOwnerMetaValue( ctx ) )
	var comp = _flowComponentObject( ctx )
	if comp != null:
		comp.note_spawned_content( node )

func _flowOwnerMetaValue( ctx ) -> Dictionary:
	return { "component" : flowComponentId( ctx ), "node" : String( name ) }

## The live component (an object with note_spawned_content) the evaluation
## spawns for, or null.
static func _flowComponentObject( ctx ) -> Object:
	var id := flowComponentId( ctx )
	if id == 0 or not is_instance_id_valid( id ):
		return null
	var comp = instance_from_id( id )
	if comp == null or not comp.has_method( "note_spawned_content" ):
		return null
	return comp

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

# --- Type mappings (ports, graph parameters, runtime values) -------------------
# Every FlowData.DataType value has a port colour. The GDScript-type mappings
# cover every type that has one Variant type of its own. Int64 and Double share
# TYPE_INT / TYPE_FLOAT with Int and Float, so a raw int or float maps to Int /
# Float; valueMatchesFlowDataType() accepts it for Int64 / Double. Resource,
# NodeMesh and NodePath have no GDScript type.

## Port (slot) colour of each data type. The historical colours are unchanged.
## The extended types: Vector2 / Vector4 / Quaternion next to Vector's purple,
## Transform orange, Int64 slate and Double lime (next to the numeric grey).
const FLOW_DATA_TYPE_COLORS := {
	FlowData.DataType.Bool: Color("ef4444"),
	FlowData.DataType.Int: Color("c8c8c8"),
	FlowData.DataType.Float: Color("c8c8c8"),
	FlowData.DataType.Vector: Color("a855f7"),
	FlowData.DataType.Color: Color("eab308"),
	FlowData.DataType.String: Color("3b82f6"),
	FlowData.DataType.Resource: Color("22c55e"),
	FlowData.DataType.NodeMesh: Color("22c55e"),
	FlowData.DataType.NodePath: Color("14b8a6"),
	FlowData.DataType.Quaternion: Color("f472b6"),
	FlowData.DataType.Vector2: Color("d8b4fe"),
	FlowData.DataType.Vector4: Color("7e22ce"),
	FlowData.DataType.Transform: Color("f97316"),
	FlowData.DataType.Int64: Color("94a3b8"),
	FlowData.DataType.Double: Color("a3e635"),
}

## Port colour of untyped flow ports (and of Invalid).
const FLOW_DEFAULT_PORT_COLOR := Color("22d3ee")

static func getColorForFlowDataType( data_type : FlowData.DataType ) -> Color:
	return FLOW_DATA_TYPE_COLORS.get( data_type, FLOW_DEFAULT_PORT_COLOR )

static func getGdScriptTypeForFlowDataType( data_type : FlowData.DataType ) -> int:
	match( data_type ):
		FlowData.DataType.Bool:
			return TYPE_BOOL
		FlowData.DataType.Int, FlowData.DataType.Int64:
			return TYPE_INT
		FlowData.DataType.Float, FlowData.DataType.Double:
			return TYPE_FLOAT
		FlowData.DataType.String:
			return TYPE_STRING
		FlowData.DataType.Vector:
			return TYPE_VECTOR3
		FlowData.DataType.Color:
			return TYPE_COLOR
		FlowData.DataType.Quaternion:
			return TYPE_QUATERNION
		FlowData.DataType.Vector2:
			return TYPE_VECTOR2
		FlowData.DataType.Vector4:
			return TYPE_VECTOR4
		FlowData.DataType.Transform:
			return TYPE_TRANSFORM3D
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
		TYPE_QUATERNION:
			return FlowData.DataType.Quaternion
		TYPE_VECTOR2:
			return FlowData.DataType.Vector2
		TYPE_VECTOR4:
			return FlowData.DataType.Vector4
		TYPE_TRANSFORM3D:
			return FlowData.DataType.Transform
	return FlowData.DataType.Invalid

## Data type of a runtime value: the GDScript-type mapping, plus Vector2i
## (stored as Vector2) and Resources. An int is Int and a float is Float; use
## valueMatchesFlowDataType() to accept them for Int64 / Double.
static func getFlowDataTypeFromObject( obj  ) -> FlowData.DataType:
	var data_type = getFlowDataTypeFromGdScriptType( typeof(obj) )
	if data_type != FlowData.DataType.Invalid:
		return data_type
	if typeof( obj ) == TYPE_VECTOR2I:
		return FlowData.DataType.Vector2
	if obj is Resource:
		return FlowData.DataType.Resource
	return data_type

## The mapping getFlowDataTypeFromObject() had before the extended attribute
## types. scan_nodes and get_property_from_object_path import scene metas and
## properties with it, so values of type Vector2, Vector4, Quaternion or
## Transform3D are still skipped there and their output does not change.
static func getLegacyFlowDataTypeFromObject( obj ) -> FlowData.DataType:
	match typeof( obj ):
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
	if obj is Resource:
		return FlowData.DataType.Resource
	return FlowData.DataType.Invalid

## True when a raw runtime value can feed a value of `data_type` as is: its
## own type (getFlowDataTypeFromObject), an int for Int64, a float for Double,
## a Vector4 for Quaternion. For Bool, Int, Float, String, Vector, Color and
## Resource this is exactly the old `getFlowDataTypeFromObject( value ) ==
## data_type` test.
static func valueMatchesFlowDataType( value, data_type : FlowData.DataType ) -> bool:
	var own := getFlowDataTypeFromObject( value )
	if own == data_type:
		return true
	match data_type:
		FlowData.DataType.Int64:
			return own == FlowData.DataType.Int
		FlowData.DataType.Double:
			return own == FlowData.DataType.Float
		FlowData.DataType.Quaternion:
			return own == FlowData.DataType.Vector4
	return false

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

## Types whose fill value newStream() writes through FlowData.Data.writeValue
## (the historical types keep their plain fill()).
const _NEW_STREAM_TYPED_FILL := [
	FlowData.DataType.Quaternion, FlowData.DataType.Vector2, FlowData.DataType.Vector4,
	FlowData.DataType.Transform,
]

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
			FlowData.DataType.Quaternion, FlowData.DataType.Vector2, FlowData.DataType.Vector4, FlowData.DataType.Transform, FlowData.DataType.Int64, FlowData.DataType.Double, FlowData.DataType.NodeMesh, FlowData.DataType.NodePath:
				# Typed writer: converts Quaternion to its Vector4 storage,
				# Vector2i to Vector2, Basis to Transform3D, and reports values
				# the container cannot hold.
				for idx in size:
					FlowData.Data.writeValue( new_container, idx, fn.call(idx), data_type )
			_:
				push_error( "newStream(%d) type not supported" % [ data_type ])
				return null
	elif _NEW_STREAM_TYPED_FILL.has( data_type ):
		# Same conversions for a fill value (a Quaternion fill into the
		# PackedVector4Array storage, for instance).
		if size > 0:
			FlowData.Data.writeValue( new_container, 0, init_value, data_type )
			new_container.fill( new_container[0] )
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
	"get_property_from_object_path", "get_spline_data", "get_surface_data", "get_volume_data",
	"sample_terrain_layers",	# WP6: layer_source = TerrainAdapter reads the terrain node
	"create_points",	# Local coordinate space reads the owner transform
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
