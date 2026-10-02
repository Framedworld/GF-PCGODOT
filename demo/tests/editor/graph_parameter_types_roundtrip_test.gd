# graph_parameter_types_roundtrip_test.gd
# WP7: a graph parameter of each extended type (Vector2, Vector4, Quaternion,
# Transform, Int64, Double, plus Color) is saved to a .tres, reloaded, and fed
# through a FlowGraphNode3D component, by its default value and by a raw
# runtime value in `args`. The editor dock previews the same values.
class_name GraphParameterTypesRoundtripTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SAVE_PATH := "user://wp7_graph_parameter_types_roundtrip.tres"

## name -> [type, default value, runtime value]
static func cases() -> Dictionary:
	return {
		"p_vector2": [FlowData.DataType.Vector2, Vector2(1.5, -2.0), Vector2(3, 4)],
		"p_vector4": [FlowData.DataType.Vector4, Vector4(1, 2, 3, 4), Vector4(-1, 0, 1, 2)],
		"p_quat": [FlowData.DataType.Quaternion, Quaternion(Vector3.UP, 0.75), Quaternion(Vector3.RIGHT, 0.25)],
		"p_transform": [FlowData.DataType.Transform, Transform3D(Basis(Vector3.UP, 0.5).scaled(Vector3(1, 2, 3)), Vector3(4, 5, 6)), Transform3D(Basis.IDENTITY, Vector3(-1, -2, -3))],
		"p_int64": [FlowData.DataType.Int64, (1 << 40) + 3, -(1 << 41)],
		"p_double": [FlowData.DataType.Double, 0.1 + 1e-12, 1.0 / 3.0],
		"p_color": [FlowData.DataType.Color, Color(0.25, 0.5, 0.75, 1.0), Color(1, 0, 0, 0.5)],
	}

static func _build_graph() -> FlowGraphResource:
	var graph := FlowGraphResource.new()
	var params : Array[GraphInputParameter] = []
	var nodes := []
	var links := []
	var c := cases()
	for name in c:
		var p := GraphInputParameter.new()
		p.name = name
		p.data_type = c[name][0]
		p.set(GraphInputParameter.value_property_name(p.data_type), c[name][1])
		params.append(p)
		nodes.append({ "name": StringName("in_" + name), "template": "input", "settings": { "name": name, "data_type": p.data_type }, "position": Vector2.ZERO, "args_port": {}, "show_disconnected_inputs": false })
		nodes.append({ "name": StringName("out_" + name), "template": "output", "settings": { "name": name }, "position": Vector2(300, 0), "args_port": {}, "show_disconnected_inputs": false })
		links.append({ "from_node": StringName("in_" + name), "from_port": 0, "to_node": StringName("out_" + name), "to_port": 0, "keep_alive": false })
	graph.in_params = params
	graph.data = { "type": "flow_graph_nodes", "version": 1, "min_pos": Vector2.ZERO, "nodes": nodes, "links": links, "frames": [] }
	return graph

static func _stored(value, t: int):
	# What a stream of type t holds for `value`.
	if t == FlowData.DataType.Quaternion:
		return FlowData.quatToVec4(value)
	return value

func _assert_value(actual, expected, t: int, what: String) -> void:
	match t:
		FlowData.DataType.Quaternion, FlowData.DataType.Vector4, FlowData.DataType.Vector2, FlowData.DataType.Color:
			assert_bool(actual.is_equal_approx(expected)).override_failure_message("%s: %s != %s" % [what, actual, expected]).is_true()
		FlowData.DataType.Transform:
			assert_bool((actual as Transform3D).is_equal_approx(expected)).override_failure_message("%s: %s != %s" % [what, actual, expected]).is_true()
		FlowData.DataType.Double:
			# Godot writes doubles with 17 significant digits but its text
			# parser may land one ulp away; far below single precision.
			assert_bool(absf(float(actual) - float(expected)) <= 1e-15).override_failure_message("%s: %.17f != %.17f" % [what, actual, expected]).is_true()
		_:
			assert_that(actual).override_failure_message("%s: %s != %s" % [what, actual, expected]).is_equal(expected)

func _saved_and_reloaded() -> FlowGraphResource:
	var err := ResourceSaver.save(_build_graph(), SAVE_PATH)
	assert_int(err).is_equal(OK)
	var loaded = ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_object(loaded).is_not_null()
	return loaded

func after() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func test_parameters_survive_a_save_and_reload() -> void:
	var graph := _saved_and_reloaded()
	var c := cases()
	assert_int(graph.in_params.size()).is_equal(c.size())
	for p in graph.in_params:
		assert_int(p.data_type).is_equal(c[p.name][0])
		_assert_value(p.get_default_value(), c[p.name][1], p.data_type, "default of " + p.name)
	# Double keeps (nearly) double precision through the text format: a 32-bit
	# float would be off by about 1e-9 here. Int64 is exact.
	var reloaded_double : float = graph.findInParamByName("p_double").get_default_value()
	assert_bool(absf(reloaded_double - (0.1 + 1e-12)) <= 1e-15).is_true()
	var as_float32 : float = PackedFloat32Array([0.1 + 1e-12])[0]
	assert_bool(absf(as_float32 - (0.1 + 1e-12)) > 1e-10).is_true()
	assert_int(graph.findInParamByName("p_int64").get_default_value()).is_equal((1 << 40) + 3)


func test_component_feeds_defaults_through_the_graph() -> void:
	var host := FlowGraphNode3D.new()
	host.generate_on_ready = false
	add_child(host)
	host.graph = _saved_and_reloaded()
	var outputs : Dictionary = host.generate()
	var c := cases()
	for name in c:
		var t : int = c[name][0]
		var d : FlowData.Data = outputs.get(name)
		assert_object(d).override_failure_message("no output %s" % name).is_not_null()
		var s = d.findStream(name)
		assert_int(s.data_type).override_failure_message("type of " + name).is_equal(t)
		_assert_value(s.container[0], _stored(c[name][1], t), t, name)
	remove_child(host)
	host.free()


func test_component_feeds_raw_runtime_values_through_the_graph() -> void:
	var host := FlowGraphNode3D.new()
	host.generate_on_ready = false
	add_child(host)
	host.graph = _saved_and_reloaded()
	var c := cases()
	var args := {}
	for name in c:
		args[name] = c[name][2]
	host.args = args
	# The inspector's Refresh Inputs keeps args whose raw value feeds the type
	# (an int for Int64, a float for Double).
	host.refreshInputs()
	for name in c:
		_assert_value(host.args[name], c[name][2], c[name][0], "arg " + name)
	var outputs : Dictionary = host.generate()
	for name in c:
		var t : int = c[name][0]
		var s = outputs[name].findStream(name)
		assert_int(s.data_type).override_failure_message("type of " + name).is_equal(t)
		_assert_value(s.container[0], _stored(c[name][2], t), t, name)
	remove_child(host)
	host.free()


## The dock's evaluation path (input.gd reads the owner's args) shows the
## same values as the component.
func test_editor_dock_previews_component_args() -> void:
	var editor : Control = load("res://addons/flow_nodes_editor/flow_editor.tscn").instantiate()
	add_child(editor)
	editor.set_process(false)
	await get_tree().process_frame
	var host := FlowGraphNode3D.new()
	host.generate_on_ready = false
	add_child(host)
	var graph := _saved_and_reloaded()
	host.graph = graph
	var c := cases()
	var args := {}
	for name in c:
		args[name] = c[name][2]
	host.args = args
	editor.clear_graph()
	editor.current_resource = graph
	editor.resource_owner = host
	editor.scanAvailableNodesIfNeeded()
	FlowNodeIO.loadFromResource(editor)
	editor.ctx.graph = graph
	editor.ctx.owner = host
	editor.ctx.gedit_nodes_by_name = editor.gedit_nodes_by_name
	editor.markAllNodesAsDirty()
	editor.evalGraph()
	for name in c:
		var t : int = c[name][0]
		var widget = editor.gedit_nodes_by_name[StringName("in_" + name)]
		var d : FlowData.Data = widget.get_bulk_output(0, 0)
		assert_object(d).override_failure_message("no dock output for %s" % name).is_not_null()
		var s = d.findStream(name)
		assert_int(s.data_type).is_equal(t)
		_assert_value(s.container[0], _stored(c[name][2], t), t, "dock " + name)
	editor.clear_graph()
	remove_child(editor)
	editor.free()
	remove_child(host)
	host.free()
	await get_tree().process_frame
