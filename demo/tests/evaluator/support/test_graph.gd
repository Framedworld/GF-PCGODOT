extends RefCounted

## Small builder for FlowGraphResource objects in tests. Produces the same
## `data` dictionary shape the editor saves (StringName node/link names,
## "nodes"/"links"/"frames" keys), so FlowNodeIO.evaluate_graph sees exactly
## what it sees for a .tres graph.
##
##   var g = TestGraph.new() \
##       .node("grid", "grid", {"x": 2, "z": 1}) \
##       .node("out", "output", {"name": "result"}) \
##       .link("grid", 0, "out", 0) \
##       .build()

const PROBE_DIR := "res://tests/evaluator/probe_nodes"

# The probe scripts live in a .gdignore'd folder and are loaded lazily on
# purpose: loading any FlowNodeBase subclass as the FIRST addon script of a
# process fails to compile (node.gd -> ... -> flow_nodes_io.gd -> nodes/assets.gd
# extends FlowNodeBase while node.gd is still compiling). GdUnit's scanner
# loads every .gd under res://tests, so the probes must not be visible to it,
# and must only be loaded after the evaluator scripts are compiled.
static var _probe_script = null

## The test_probe script (static exec_log / live_instances helpers live on it).
static func probe():
	if _probe_script == null:
		_probe_script = load(PROBE_DIR + "/test_probe.gd")
	return _probe_script

var _nodes : Array = []
var _links : Array = []
var _in_params : Array[GraphInputParameter] = []
var _out_params : Array[GraphInputParameter] = []

func node(node_name: String, template: String, settings: Dictionary = {}):
	_nodes.append({
		"name": StringName(node_name),
		"template": template,
		"settings": settings.duplicate(),
		"position": Vector2.ZERO,
		"args_port": {},
		"show_disconnected_inputs": false,
	})
	return self

func link(from_node: String, from_port: int, to_node: String, to_port: int):
	_links.append({
		"from_node": StringName(from_node),
		"from_port": from_port,
		"to_node": StringName(to_node),
		"to_port": to_port,
		"keep_alive": false,
	})
	return self

func in_param(param_name: String, data_type: int = FlowData.DataType.Float, default_value = null):
	_in_params.append(make_param(param_name, data_type, default_value))
	return self

func out_param(param_name: String, data_type: int = FlowData.DataType.Float):
	_out_params.append(make_param(param_name, data_type, null))
	return self

func build() -> FlowGraphResource:
	var graph := FlowGraphResource.new()
	graph.in_params = _in_params
	graph.out_params = _out_params
	graph.data = {
		"type": "flow_graph_nodes",
		"version": 1,
		"min_pos": Vector2.ZERO,
		"nodes": _nodes,
		"links": _links,
		"frames": [],
	}
	return graph

static func make_param(param_name: String, data_type: int, default_value = null) -> GraphInputParameter:
	var p := GraphInputParameter.new()
	p.name = param_name
	p.data_type = data_type
	if default_value != null:
		match data_type:
			FlowData.DataType.Bool:
				p.cte_bool = bool(default_value)
			FlowData.DataType.Int:
				p.cte_int = int(default_value)
			FlowData.DataType.Float:
				p.cte_float = float(default_value)
			FlowData.DataType.Vector:
				p.cte_vector = default_value
			FlowData.DataType.String:
				p.cte_string = str(default_value)
			FlowData.DataType.Resource:
				p.cte_resource = default_value
	return p

# --- Evaluation helpers ------------------------------------------------------

## A root context equivalent to the one FlowGraphNode3D.execute() builds.
static func make_ctx(owner: FlowGraphNode3D = null) -> FlowData.EvaluationContext:
	var ctx := FlowData.EvaluationContext.new()
	ctx.owner = owner
	ctx.eval_id = 0
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = {}
	return ctx

static func register_probes() -> void:
	FlowNodeRegistry.register_node_directory(PROBE_DIR)
	probe().reset_probe_state()

static func unregister_probes() -> void:
	FlowNodeRegistry.unregister_node_directory(PROBE_DIR)
	probe().reset_probe_state()

# --- Data helpers --------------------------------------------------------------

static func float_data(stream_name: String, values: Array) -> FlowData.Data:
	var d := FlowData.Data.new()
	d.registerStream(stream_name, PackedFloat32Array(values), FlowData.DataType.Float)
	return d

static func points(positions: Array) -> FlowData.Data:
	var d := FlowData.Data.new()
	d.addCommonStreams(positions.size())
	var pos : PackedVector3Array = d.getContainerChecked(str(FlowData.AttrPosition), FlowData.DataType.Vector)
	for i in range(positions.size()):
		pos[i] = positions[i]
	return d

static func trail(data) -> PackedStringArray:
	if data is FlowData.Data:
		var s = data.findStream("trail")
		if s != null:
			return s.container
	return PackedStringArray()

static func stream_values(data, stream_name: String):
	if not (data is FlowData.Data):
		return null
	var s = data.findStream(stream_name)
	return s.container if s != null else null
