# setting_overrides_bindings_test.gd
# Per-instance overrides (FlowGraphNode3D.overrides / EvaluationContext.overrides)
# and $param bindings (NodeSettings.bindings), RUNTIME_API_P0 §4.
# Precedence, highest first: wired port > override > binding > saved value.
class_name SettingOverridesBindingsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TMP_DIR := "user://flow_overrides_bindings_test"
const SUB_GRAPH_PATH := TMP_DIR + "/ovr_sub.tres"
const ROUND_TRIP_PATH := TMP_DIR + "/ovr_round_trip.tres"

const FLOAT := FlowData.DataType.Float
const INT := FlowData.DataType.Int


func before() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))


func after() -> void:
	for path in [SUB_GRAPH_PATH, ROUND_TRIP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR))


# --- graph builders ---------------------------------------------------------

func _attr_node(node_name: String, value: float, extra: Dictionary = {}) -> Dictionary:
	var settings := { "name": "val", "data_type": FLOAT, "cte_float": value }
	settings.merge(extra, true)
	return { "name": node_name, "template": "add_attribute", "position": Vector2.ZERO, "settings": settings }


func _output_node(node_name: String, out_name: String) -> Dictionary:
	return { "name": node_name, "template": "output", "position": Vector2.ZERO, "settings": { "name": out_name } }


func _link(from_node: String, to_node: String, to_port: int = 0) -> Dictionary:
	return { "from_node": from_node, "from_port": 0, "to_node": to_node, "to_port": to_port }


func _graph(nodes: Array, links: Array) -> FlowGraphResource:
	var g := FlowGraphResource.new()
	g.data = {
		"type": "flow_graph_nodes",
		"version": 1,
		"min_pos": Vector2.ZERO,
		"nodes": nodes,
		"links": links,
		"frames": [],
	}
	return g


# dst (add_attribute "val", saved 1.0, cte_float bound to $k) -> output "result"
func _bound_graph(saved: float = 1.0, bindings: Dictionary = { "cte_float": "$k" }) -> FlowGraphResource:
	return _graph(
		[ _attr_node("dst", saved, { "bindings": bindings }), _output_node("out", "result") ],
		[ _link("dst", "out") ]
	)


func _sub_graph() -> FlowGraphResource:
	var sub := _graph([ _attr_node("dst", 1.0), _output_node("out", "result") ], [ _link("dst", "out") ])
	assert_int(ResourceSaver.save(sub, SUB_GRAPH_PATH)).is_equal(OK)
	return ResourceLoader.load(SUB_GRAPH_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)


# Parent with its own "dst" and `count` subgraph nodes whose graph also has a "dst".
func _parent_graph(sub: FlowGraphResource, count: int = 1) -> FlowGraphResource:
	var nodes := [ _attr_node("dst", 1.0), _output_node("out", "result") ]
	var links := [ _link("dst", "out") ]
	for i in range(count):
		var sg := "sg%d" % i
		var out := "sub_out%d" % i
		nodes.append({ "name": sg, "template": "subgraph", "position": Vector2.ZERO, "settings": { "graph": sub } })
		nodes.append(_output_node(out, "sub_result%d" % i))
		links.append(_link(sg, out))
	return _graph(nodes, links)


func _eval(graph: FlowGraphResource, inputs: Dictionary = {}, overrides: Dictionary = {}, params: Dictionary = {}, variables: Dictionary = {}) -> Dictionary:
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.overrides = overrides
	ctx.runtime_params = params
	ctx.variables = variables
	return FlowNodeIO.evaluate_graph(graph, inputs, ctx, {}, 0)


func _first(outputs: Dictionary, out_name: String, stream_name: String = "val"):
	var data = outputs.get(out_name, null)
	assert_object(data).override_failure_message("missing output '%s' in %s" % [out_name, outputs.keys()]).is_not_null()
	if data == null:
		return null
	var stream = data.findStream(stream_name)
	assert_object(stream).is_not_null()
	if stream == null or stream.container.size() == 0:
		return null
	return stream.container[0]


func _scalar(stream_name: String, value, data_type: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	var container = d.addStream(stream_name, data_type)
	container.resize(1)
	FlowDataScript.Data.writeValue(container, 0, value, data_type)
	return d


func _warnings_during(fn: Callable) -> PackedStringArray:
	var logger := GodotGdErrorMonitor.GdUnitLogger.new(true, false)
	fn.call()
	OS.remove_logger(logger)
	var messages := PackedStringArray()
	for entry in logger.entries():
		if entry._type == ErrorLogEntry.TYPE.PUSH_WARNING:
			messages.append(entry._message)
	return messages


func _count_containing(messages: PackedStringArray, needle: String) -> int:
	var n := 0
	for m in messages:
		if m.contains(needle):
			n += 1
	return n


# --- precedence ---------------------------------------------------------------

func test_missing_param_keeps_saved_value() -> void:
	var warnings := _warnings_during(func():
		assert_float(_first(_eval(_bound_graph()), "result")).is_equal(1.0))
	assert_int(_count_containing(warnings, "binding")).is_equal(0)


func test_binding_beats_saved_value() -> void:
	assert_float(_first(_eval(_bound_graph(), {}, {}, { "k": 2.5 }), "result")).is_equal(2.5)


func test_binding_param_name_without_dollar() -> void:
	var g := _bound_graph(1.0, { "cte_float": "k" })
	assert_float(_first(_eval(g, {}, {}, { "k": 4.0 }), "result")).is_equal(4.0)


func test_override_beats_binding() -> void:
	var outputs := _eval(_bound_graph(), {}, { "dst/cte_float": 9.0 }, { "k": 2.5 })
	assert_float(_first(outputs, "result")).is_equal(9.0)


func test_override_beats_saved_value_without_binding() -> void:
	var g := _graph([ _attr_node("dst", 1.0), _output_node("out", "result") ], [ _link("dst", "out") ])
	assert_float(_first(_eval(g, {}, { "dst/cte_float": 6.0 }), "result")).is_equal(6.0)


func test_binding_source_order_inputs_then_params_then_variables() -> void:
	var g := _bound_graph()
	var variables := { "k": _scalar("k", 3.0, FLOAT) }
	assert_float(_first(_eval(g, {}, {}, {}, variables), "result")).is_equal(3.0)
	assert_float(_first(_eval(g, {}, {}, { "k": 2.0 }, variables), "result")).is_equal(2.0)
	assert_float(_first(_eval(g, { "k": 4.0 }, {}, { "k": 2.0 }, variables), "result")).is_equal(4.0)


func test_binding_reads_first_element_of_input_data() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("k", PackedFloat32Array([5.0, 6.0]), FLOAT)
	d.registerStream("other", PackedFloat32Array([8.0, 9.0]), FLOAT)
	assert_float(_first(_eval(_bound_graph(), { "k": d }), "result")).is_equal(5.0)


func test_binding_reads_data_attr() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowData.DataType.Vector)
	d.data_attrs["k"] = { "value": 7.5, "data_type": FLOAT }
	assert_float(_first(_eval(_bound_graph(), {}, {}, { "k": d }), "result")).is_equal(7.5)


func test_wired_port_beats_override_and_binding() -> void:
	# src emits a one-element "v" stream wired into dst's cte_float parameter port
	# (port 1: add_attribute has one flow input, parameter ports follow it).
	var dst := _attr_node("dst", 1.0, { "bindings": { "cte_float": "$k" } })
	dst["args_port"] = { "cte_float": { "port": 1, "connected": true } }
	var g := _graph(
		[ { "name": "src", "template": "add_attribute", "position": Vector2.ZERO, "settings": { "name": "v", "data_type": FLOAT, "cte_float": 7.0 } },
		  dst, _output_node("out", "result") ],
		[ _link("src", "dst", 1), _link("dst", "out") ]
	)
	var outputs := _eval(g, {}, { "dst/cte_float": 9.0 }, { "k": 2.5 })
	assert_float(_first(outputs, "result")).is_equal(7.0)


func test_unconnected_saved_port_entry_does_not_shadow_setting() -> void:
	var dst := _attr_node("dst", 1.0)
	dst["args_port"] = { "cte_float": { "port": 1, "connected": false } }
	var g := _graph([ dst, _output_node("out", "result") ], [ _link("dst", "out") ])
	assert_float(_first(_eval(g, {}, { "dst/cte_float": 3.0 }), "result")).is_equal(3.0)


# --- subgraph scoping -----------------------------------------------------------

func test_prefixed_override_targets_only_that_subgraph() -> void:
	var sub := _sub_graph()
	assert_str(FlowNodeIO.graph_basename(sub)).is_equal("ovr_sub")
	var outputs := _eval(_parent_graph(sub), {}, { "ovr_sub:dst/cte_float": 5.0 })
	assert_float(_first(outputs, "result")).is_equal(1.0)
	assert_float(_first(outputs, "sub_result0")).is_equal(5.0)


func test_unprefixed_override_applies_inside_subgraphs() -> void:
	var outputs := _eval(_parent_graph(_sub_graph()), {}, { "dst/cte_float": 5.0 })
	assert_float(_first(outputs, "result")).is_equal(5.0)
	assert_float(_first(outputs, "sub_result0")).is_equal(5.0)


func test_prefixed_override_for_other_graph_does_not_apply() -> void:
	var outputs := _eval(_parent_graph(_sub_graph()), {}, { "some_other_graph:dst/cte_float": 5.0 })
	assert_float(_first(outputs, "result")).is_equal(1.0)
	assert_float(_first(outputs, "sub_result0")).is_equal(1.0)


# --- coercion and type errors ---------------------------------------------------

func test_numeric_coercion_int_to_float() -> void:
	var outputs := _eval(_bound_graph(), {}, { "dst/cte_float": 3 })
	var value = _first(outputs, "result")
	assert_int(typeof(value)).is_equal(TYPE_FLOAT)
	assert_float(value).is_equal(3.0)
	assert_float(_first(_eval(_bound_graph(), {}, {}, { "k": 4 }), "result")).is_equal(4.0)


func test_numeric_coercion_float_to_int() -> void:
	var g := _graph(
		[ { "name": "dst", "template": "add_attribute", "position": Vector2.ZERO,
			"settings": { "name": "val", "data_type": INT, "cte_int": 1, "bindings": { "cte_int": "$n" } } },
		  _output_node("out", "result") ],
		[ _link("dst", "out") ]
	)
	assert_int(_first(_eval(g, {}, {}, { "n": 2.9 }), "result")).is_equal(2)
	assert_int(_first(_eval(g, {}, {}, { "n": _scalar("n", 6.0, FLOAT) }), "result")).is_equal(6)
	assert_int(_first(_eval(g, {}, { "dst/cte_int": 8.0 }), "result")).is_equal(8)


func test_unassignable_binding_keeps_saved_value_and_warns() -> void:
	var outputs := {}
	var warnings := _warnings_during(func(): outputs.merge(_eval(_bound_graph(), {}, {}, { "k": "not a number" })))
	assert_float(_first(outputs, "result")).is_equal(1.0)
	assert_int(_count_containing(warnings, "binding '$k' cannot assign")).is_equal(1)


# --- unmatched override keys ------------------------------------------------------

func test_unmatched_override_key_warns_once_per_evaluation() -> void:
	# Two subgraph instances plus the parent: three graph levels, still one warning.
	var g := _parent_graph(_sub_graph(), 2)
	var overrides := {
		"nope/cte_float": 1.0,
		"dst/no_such_setting": 1.0,
		"dst/cte_float": 2.0,
		"ovr_sub:dst/cte_float": 3.0,
	}
	var outputs := {}
	var warnings := _warnings_during(func(): outputs.merge(_eval(g, {}, overrides)))
	assert_int(_count_containing(warnings, "override 'nope/cte_float' matched no node")).is_equal(1)
	assert_int(_count_containing(warnings, "override 'dst/no_such_setting' matched no node")).is_equal(1)
	assert_int(_count_containing(warnings, "override 'dst/cte_float' matched")).is_equal(0)
	assert_int(_count_containing(warnings, "override 'ovr_sub:dst/cte_float' matched")).is_equal(0)
	assert_float(_first(outputs, "result")).is_equal(2.0)
	assert_float(_first(outputs, "sub_result0")).is_equal(3.0)
	assert_float(_first(outputs, "sub_result1")).is_equal(3.0)
	# A second evaluation reports again (once per evaluation, not once per process).
	warnings = _warnings_during(func(): _eval(g, {}, overrides))
	assert_int(_count_containing(warnings, "override 'nope/cte_float' matched no node")).is_equal(1)


# --- serialisation ---------------------------------------------------------------

func test_bindings_round_trip_through_settings_dict() -> void:
	var settings := AddAttributeNodeSettings.new()
	settings.bindings = { "cte_float": "$k" }
	var dict := FlowNodeIO.resource_to_dict(settings)
	assert_dict(dict.get("bindings", {})).is_equal({ "cte_float": "$k" })
	var restored := AddAttributeNodeSettings.new()
	FlowNodeIO.dict_to_resource(dict, restored)
	assert_dict(restored.bindings).is_equal({ "cte_float": "$k" })
	# Unused bindings are not serialised, so existing graphs keep their exact shape.
	assert_bool(FlowNodeIO.resource_to_dict(AddAttributeNodeSettings.new()).has("bindings")).is_false()


func test_bindings_survive_graph_save_load() -> void:
	assert_int(ResourceSaver.save(_bound_graph(), ROUND_TRIP_PATH)).is_equal(OK)
	var loaded: FlowGraphResource = ResourceLoader.load(ROUND_TRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_object(loaded).is_not_null()
	var dst_settings: Dictionary = loaded.data.nodes[0].settings
	assert_dict(dst_settings.get("bindings", {})).is_equal({ "cte_float": "$k" })
	assert_float(_first(_eval(loaded), "result")).is_equal(1.0)
	assert_float(_first(_eval(loaded, {}, {}, { "k": 2.5 }), "result")).is_equal(2.5)


# --- editor path ---------------------------------------------------------------

func _editor_like_node(bindings: Dictionary) -> FlowNodeBase:
	var node: FlowNodeBase = load(FlowNodeRegistry.get_node_script_path("add_attribute")).new()
	node.name = "dst"
	node.node_template = "add_attribute"
	var settings := AddAttributeNodeSettings.new()
	settings.name = "val"
	settings.data_type = FLOAT
	settings.cte_float = 1.0
	settings.bindings = bindings
	node.settings = settings
	return node


func test_editor_path_applies_on_scratch_settings_without_emitting_changed() -> void:
	var node := _editor_like_node({ "cte_float": "$k" })
	# In the editor a FlowNodeWidget shows the element and watches its settings.
	var widget := FlowNodeWidget.new()
	widget.element = node
	var authored: Resource = node.settings
	var changed_count := [0]
	authored.changed.connect(func(): changed_count[0] += 1)
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.runtime_params = { "k": 2.5 }
	ctx.gedit_nodes_by_name = { "dst": node }

	var restored := FlowNodeIO.begin_scratch_setting_bindings(node, null, ctx, {})
	assert_object(restored).is_same(authored)
	assert_object(node.settings).is_not_same(authored)
	assert_float(node.settings.cte_float).is_equal(2.5)
	node.preExecute(ctx)
	node.run(ctx)
	FlowNodeIO.end_scratch_setting_bindings(node, restored)

	var out: FlowData.Data = node.generated_bulks[0][0]
	assert_float(out.findStream("val").container[0]).is_equal(2.5)
	assert_object(node.settings).is_same(authored)
	assert_float(authored.cte_float).is_equal(1.0)
	assert_dict(authored.bindings).is_equal({ "cte_float": "$k" })
	assert_int(changed_count[0]).is_equal(0)
	# The node's editor widget listens to the authored resource again after the swap back.
	assert_bool(authored.changed.is_connected(widget._on_settings_changed)).is_true()
	widget.free()


func test_editor_path_is_noop_without_overrides_or_resolvable_bindings() -> void:
	var node := _editor_like_node({})
	var authored: Resource = node.settings
	var ctx = FlowDataScript.EvaluationContext.new()
	assert_object(FlowNodeIO.begin_scratch_setting_bindings(node, null, ctx, {})).is_null()
	node.settings.bindings = { "cte_float": "$absent" }
	assert_object(FlowNodeIO.begin_scratch_setting_bindings(node, null, ctx, {})).is_null()
	assert_object(node.settings).is_same(authored)


func test_editor_uses_scratch_binding_helpers() -> void:
	# flow_editor.gd evaluates nodes itself (not through _build_evaluation_state);
	# guard that its per-node path keeps routing through the scratch helpers.
	var source := FileAccess.get_file_as_string("res://addons/flow_nodes_editor/flow_editor.gd")
	assert_str(source).contains("FlowNodeIO.begin_scratch_setting_bindings( node, current_resource, ctx, {} )")
	assert_str(source).contains("FlowNodeIO.end_scratch_setting_bindings( node, authored_settings )")


# --- graph input (in_params) default as the last binding source -----------------

func _declare_input(graph: FlowGraphResource, param_name: String, value: float) -> FlowGraphResource:
	var param := GraphInputParameter.new()
	param.name = param_name
	param.data_type = FLOAT
	param.cte_float = value
	var params: Array[GraphInputParameter] = [param]
	graph.in_params = params
	return graph


func test_binding_falls_back_to_graph_input_default() -> void:
	var g := _declare_input(_bound_graph(), "k", 3.25)
	var warnings := _warnings_during(func():
		assert_float(_first(_eval(g), "result")).is_equal(3.25))
	assert_int(_count_containing(warnings, "binding")).is_equal(0)


func test_graph_input_default_is_lowest_binding_source() -> void:
	var g := _declare_input(_bound_graph(), "k", 3.25)
	var variables := { "k": _scalar("k", 3.0, FLOAT) }
	assert_float(_first(_eval(g, {}, {}, {}, variables), "result")).is_equal(3.0)
	assert_float(_first(_eval(g, {}, {}, { "k": 2.0 }), "result")).is_equal(2.0)
	assert_float(_first(_eval(g, { "k": 4.0 }), "result")).is_equal(4.0)
	assert_float(_first(_eval(g, {}, { "dst/cte_float": 9.0 }), "result")).is_equal(9.0)


func test_graph_input_default_of_other_name_is_ignored() -> void:
	var g := _declare_input(_bound_graph(), "other", 3.25)
	assert_float(_first(_eval(g), "result")).is_equal(1.0)


func test_graph_input_default_single_sources_nodes_in_editor_path() -> void:
	# Dock previews feed no inputs; the declared input's default drives the knob.
	var g := _declare_input(FlowGraphResource.new(), "k", 6.5)
	var node := _editor_like_node({ "cte_float": "$k" })
	var ctx = FlowDataScript.EvaluationContext.new()
	var restored := FlowNodeIO.begin_scratch_setting_bindings(node, g, ctx, {})
	assert_object(restored).is_not_null()
	assert_float(node.settings.cte_float).is_equal(6.5)
	FlowNodeIO.end_scratch_setting_bindings(node, restored)
	assert_float(node.settings.cte_float).is_equal(1.0)



# --- Dictionary entries ("<dict_property>/<key>") and Expression args ----------
# An Expression node's parameters live in settings.args (a Dictionary). Bindings
# and overrides reach one entry with "args/<key>" (overrides: "node/args/<key>");
# on an Expression node a bare name that is an existing args key maps there too.

# dst (add_attribute "val" = 1.0) -> ex (expression "e" = val * theme) -> output
func _expression_graph(bindings: Dictionary = {}, args: Dictionary = { "theme": 1.0 }, expression: String = "val * theme") -> FlowGraphResource:
	var ex_settings := { "expression": expression, "out_name": "e", "args": args }
	if not bindings.is_empty():
		ex_settings["bindings"] = bindings
	return _graph(
		[ _attr_node("dst", 1.0),
		  { "name": "ex", "template": "expression", "position": Vector2.ZERO, "settings": ex_settings },
		  _output_node("out", "result") ],
		[ _link("dst", "ex"), _link("ex", "out") ]
	)


func test_expression_saved_arg_without_binding() -> void:
	assert_float(_first(_eval(_expression_graph()), "result", "e")).is_equal(1.0)


func test_binding_drives_expression_arg_from_graph_input() -> void:
	var g := _expression_graph({ "args/theme": "$theme" })
	assert_float(_first(_eval(g, { "theme": 3.0 }), "result", "e")).is_equal(3.0)
	# Absent parameter keeps the saved arg.
	assert_float(_first(_eval(g), "result", "e")).is_equal(1.0)


func test_binding_drives_expression_arg_from_runtime_param_by_bare_name() -> void:
	var g := _expression_graph({ "theme": "$theme" })
	assert_float(_first(_eval(g, {}, {}, { "theme": 2.5 }), "result", "e")).is_equal(2.5)


func test_expression_arg_binding_coerces_numeric() -> void:
	# The float arg takes an int parameter as float; an int arg takes a float as int.
	var value = _first(_eval(_expression_graph({ "args/theme": "$theme" }), {}, {}, { "theme": 4 }), "result", "e")
	assert_int(typeof(value)).is_equal(TYPE_FLOAT)
	assert_float(value).is_equal(4.0)
	var gi := _expression_graph({ "args/n": "$n" }, { "n": 1 }, "n + 0")
	value = _first(_eval(gi, {}, {}, { "n": 6.9 }), "result", "e")
	assert_int(typeof(value)).is_equal(TYPE_INT)
	assert_int(value).is_equal(6)


func test_expression_arg_unassignable_binding_warns_and_keeps_saved() -> void:
	var outputs := {}
	var warnings := _warnings_during(func():
		outputs.merge(_eval(_expression_graph({ "args/theme": "$theme" }), {}, {}, { "theme": "red" })))
	assert_float(_first(outputs, "result", "e")).is_equal(1.0)
	assert_int(_count_containing(warnings, "cannot assign String value red to setting 'args/theme'")).is_equal(1)


func test_override_on_expression_args_key() -> void:
	var overrides := { "ex/args/theme": 5.0 }
	var warnings := _warnings_during(func():
		assert_float(_first(_eval(_expression_graph(), {}, overrides), "result", "e")).is_equal(5.0))
	assert_int(_count_containing(warnings, "matched no node")).is_equal(0)
	# An override beats a binding on the same entry, whichever key form the binding uses.
	for binding_name in ["args/theme", "theme"]:
		var g := _expression_graph({ binding_name: "$theme" })
		assert_float(_first(_eval(g, {}, overrides, { "theme": 2.0 }), "result", "e")).is_equal(5.0)


func test_override_on_non_dictionary_property_path_still_unmatched() -> void:
	var warnings := _warnings_during(func(): _eval(_expression_graph(), {}, { "ex/out_name/x": 1.0 }))
	assert_int(_count_containing(warnings, "override 'ex/out_name/x' matched no node")).is_equal(1)


func test_dict_entry_binding_does_not_mutate_authored_args() -> void:
	var settings := ExpressionNodeSettings.new()
	var authored_args := { "theme": 1.0 }
	settings.args = authored_args
	settings.bindings = { "args/theme": "$theme" }
	var node := FlowNodeBase.new()
	node.name = "ex"
	node.settings = settings
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.runtime_params = { "theme": 7.0 }
	var scratch: Resource = settings.duplicate()
	assert_bool(FlowNodeIO.apply_setting_bindings(node, null, ctx, {}, scratch)).is_true()
	assert_float(scratch.args["theme"]).is_equal(7.0)
	assert_float(authored_args["theme"]).is_equal(1.0)
	assert_float(settings.args["theme"]).is_equal(1.0)


func test_unknown_binding_name_still_warns() -> void:
	# Non-expression node: a bare name that is no setting is still unknown.
	var g := _bound_graph(1.0, { "theme": "$k" })
	var warnings := _warnings_during(func(): _eval(g, {}, {}, { "k": 2.0 }))
	assert_int(_count_containing(warnings, "binds unknown setting 'theme'")).is_equal(1)
	# "<prop>/<key>" on a property that is not a Dictionary is unknown too.
	g = _bound_graph(1.0, { "cte_float/x": "$k" })
	warnings = _warnings_during(func(): _eval(g, {}, {}, { "k": 2.0 }))
	assert_int(_count_containing(warnings, "binds unknown setting 'cte_float/x'")).is_equal(1)
	# Expression node: a bare name that is not an args key stays unknown.
	g = _expression_graph({ "colour": "$k" })
	warnings = _warnings_during(func():
		assert_float(_first(_eval(g, {}, {}, { "k": 2.0 }), "result", "e")).is_equal(1.0))
	assert_int(_count_containing(warnings, "binds unknown setting 'colour'")).is_equal(1)


func test_expression_arg_bindings_round_trip_through_settings_dict() -> void:
	var settings := ExpressionNodeSettings.new()
	settings.args = { "theme": 1.0 }
	settings.bindings = { "args/theme": "$theme", "theme": "$other" }
	var dict := FlowNodeIO.resource_to_dict(settings)
	assert_dict(dict.get("bindings", {})).is_equal({ "args/theme": "$theme", "theme": "$other" })
	assert_dict(dict.get("args", {})).is_equal({ "theme": 1.0 })
	var restored := ExpressionNodeSettings.new()
	FlowNodeIO.dict_to_resource(dict, restored)
	assert_dict(restored.bindings).is_equal({ "args/theme": "$theme", "theme": "$other" })
	assert_dict(restored.args).is_equal({ "theme": 1.0 })
	# Unused bindings are still omitted from an Expression's dict.
	assert_bool(FlowNodeIO.resource_to_dict(ExpressionNodeSettings.new()).has("bindings")).is_false()
