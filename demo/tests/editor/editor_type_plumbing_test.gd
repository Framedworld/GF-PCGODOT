# editor_type_plumbing_test.gd
# WP7 requirement 1: the type mappings in node.gd (port colours, GDScript
# types both ways, runtime values, newStream), graph parameter types
# (GraphInputParameter, FlowGraphParametersEditor), _coerce_input_data for raw
# Vector2 / Transform3D (and the other extended values), and the slot types and
# colours widgets set from them. Covers every FlowData.DataType value.
class_name EditorTypePlumbingTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

const EXTENDED := [
	FlowData.DataType.Quaternion, FlowData.DataType.Vector2, FlowData.DataType.Vector4,
	FlowData.DataType.Transform, FlowData.DataType.Int64, FlowData.DataType.Double,
]

## One sample value per DataType (index: DataType value).
static func sample_value(t: int):
	match t:
		FlowData.DataType.Bool: return true
		FlowData.DataType.Int: return 7
		FlowData.DataType.Float: return 0.5
		FlowData.DataType.Vector: return Vector3(1, 2, 3)
		FlowData.DataType.String: return "abc"
		FlowData.DataType.Resource: return Curve.new()
		FlowData.DataType.NodeMesh: return null
		FlowData.DataType.NodePath: return null
		FlowData.DataType.Color: return Color(0.1, 0.2, 0.3, 0.4)
		FlowData.DataType.Quaternion: return Quaternion(Vector3.UP, 0.5)
		FlowData.DataType.Vector2: return Vector2(4, 5)
		FlowData.DataType.Vector4: return Vector4(1, 2, 3, 4)
		FlowData.DataType.Transform: return Transform3D(Basis(Vector3.UP, 0.25), Vector3(1, 2, 3))
		FlowData.DataType.Int64: return 1 << 40
		FlowData.DataType.Double: return 0.1 + 1e-12
	return null

static func all_types() -> Array:
	var out := []
	for key in FlowData.DataType.keys():
		var t : int = FlowData.DataType[key]
		if t != FlowData.DataType.Invalid:
			out.append(t)
	return out


# --- Port colours --------------------------------------------------------------------

func test_every_data_type_has_a_port_colour() -> void:
	for t in all_types():
		assert_bool(FlowNodeBase.FLOW_DATA_TYPE_COLORS.has(t)).override_failure_message("no colour for %s" % FlowData.DataType.keys()[t]).is_true()
		assert_that(FlowNodeBase.getColorForFlowDataType(t)).is_equal(FlowNodeBase.FLOW_DATA_TYPE_COLORS[t])
	assert_that(FlowNodeBase.getColorForFlowDataType(FlowData.DataType.Invalid)).is_equal(FlowNodeBase.FLOW_DEFAULT_PORT_COLOR)


func test_historical_port_colours_are_unchanged() -> void:
	var expected := {
		FlowData.DataType.Bool: Color("ef4444"), FlowData.DataType.Int: Color("c8c8c8"),
		FlowData.DataType.Float: Color("c8c8c8"), FlowData.DataType.Vector: Color("a855f7"),
		FlowData.DataType.Color: Color("eab308"), FlowData.DataType.String: Color("3b82f6"),
		FlowData.DataType.Resource: Color("22c55e"), FlowData.DataType.NodeMesh: Color("22c55e"),
		FlowData.DataType.NodePath: Color("14b8a6"),
	}
	for t in expected:
		assert_that(FlowNodeBase.getColorForFlowDataType(t)).is_equal(expected[t])
	assert_that(FlowNodeBase.FLOW_DEFAULT_PORT_COLOR).is_equal(Color("22d3ee"))


func test_extended_types_have_distinct_colours() -> void:
	var seen := {}
	for t in all_types():
		var c : Color = FlowNodeBase.getColorForFlowDataType(t)
		if EXTENDED.has(t):
			assert_bool(c == FlowNodeBase.FLOW_DEFAULT_PORT_COLOR).override_failure_message("%s uses the default colour" % FlowData.DataType.keys()[t]).is_false()
			assert_bool(seen.has(c)).override_failure_message("%s shares a colour with %s" % [FlowData.DataType.keys()[t], seen.get(c, "")]).is_false()
		seen[c] = FlowData.DataType.keys()[t]


# --- GDScript types ------------------------------------------------------------------

func test_gdscript_type_mappings_round_trip() -> void:
	var pairs := {
		FlowData.DataType.Bool: TYPE_BOOL, FlowData.DataType.Int: TYPE_INT,
		FlowData.DataType.Float: TYPE_FLOAT, FlowData.DataType.String: TYPE_STRING,
		FlowData.DataType.Vector: TYPE_VECTOR3, FlowData.DataType.Color: TYPE_COLOR,
		FlowData.DataType.Quaternion: TYPE_QUATERNION, FlowData.DataType.Vector2: TYPE_VECTOR2,
		FlowData.DataType.Vector4: TYPE_VECTOR4, FlowData.DataType.Transform: TYPE_TRANSFORM3D,
	}
	for t in pairs:
		assert_int(FlowNodeBase.getGdScriptTypeForFlowDataType(t)).is_equal(pairs[t])
		assert_int(FlowNodeBase.getFlowDataTypeFromGdScriptType(pairs[t])).is_equal(t)
	# Int64 / Double share the Variant type of Int / Float.
	assert_int(FlowNodeBase.getGdScriptTypeForFlowDataType(FlowData.DataType.Int64)).is_equal(TYPE_INT)
	assert_int(FlowNodeBase.getGdScriptTypeForFlowDataType(FlowData.DataType.Double)).is_equal(TYPE_FLOAT)
	assert_int(FlowNodeBase.getFlowDataTypeFromGdScriptType(TYPE_INT)).is_equal(FlowData.DataType.Int)
	assert_int(FlowNodeBase.getFlowDataTypeFromGdScriptType(TYPE_FLOAT)).is_equal(FlowData.DataType.Float)
	assert_int(FlowNodeBase.getGdScriptTypeForFlowDataType(FlowData.DataType.Resource)).is_equal(TYPE_NIL)
	assert_int(FlowNodeBase.getFlowDataTypeFromGdScriptType(TYPE_DICTIONARY)).is_equal(FlowData.DataType.Invalid)


func test_flow_data_type_from_runtime_values() -> void:
	for t in all_types():
		var v = sample_value(t)
		if v == null:
			continue
		var expected : int = t
		if t == FlowData.DataType.Int64:
			expected = FlowData.DataType.Int
		elif t == FlowData.DataType.Double:
			expected = FlowData.DataType.Float
		assert_int(FlowNodeBase.getFlowDataTypeFromObject(v)).override_failure_message("value of %s" % FlowData.DataType.keys()[t]).is_equal(expected)
	assert_int(FlowNodeBase.getFlowDataTypeFromObject(Vector2i(1, 2))).is_equal(FlowData.DataType.Vector2)
	assert_int(FlowNodeBase.getFlowDataTypeFromObject({})).is_equal(FlowData.DataType.Invalid)


func test_value_matches_flow_data_type() -> void:
	for t in all_types():
		var v = sample_value(t)
		if v == null:
			continue
		assert_bool(FlowNodeBase.valueMatchesFlowDataType(v, t)).override_failure_message("sample of %s" % FlowData.DataType.keys()[t]).is_true()
	assert_bool(FlowNodeBase.valueMatchesFlowDataType(Vector4(0, 0, 0, 1), FlowData.DataType.Quaternion)).is_true()
	# Historical strictness kept: an int does not match Float, a float not Int.
	assert_bool(FlowNodeBase.valueMatchesFlowDataType(3, FlowData.DataType.Float)).is_false()
	assert_bool(FlowNodeBase.valueMatchesFlowDataType(3.0, FlowData.DataType.Int)).is_false()
	assert_bool(FlowNodeBase.valueMatchesFlowDataType(3.0, FlowData.DataType.Int64)).is_false()
	assert_bool(FlowNodeBase.valueMatchesFlowDataType(Vector3.ONE, FlowData.DataType.Vector2)).is_false()


func test_legacy_mapping_skips_extended_values() -> void:
	# scan_nodes / get_property_from_object_path import with this mapping, so
	# their output for scenes with Vector2 / Transform3D metas does not change.
	for t in EXTENDED:
		var v = sample_value(t)
		var expected := FlowData.DataType.Invalid
		if t == FlowData.DataType.Int64:
			expected = FlowData.DataType.Int
		elif t == FlowData.DataType.Double:
			expected = FlowData.DataType.Float
		assert_int(FlowNodeBase.getLegacyFlowDataTypeFromObject(v)).is_equal(expected)
	assert_int(FlowNodeBase.getLegacyFlowDataTypeFromObject(Color.RED)).is_equal(FlowData.DataType.Color)
	assert_int(FlowNodeBase.getLegacyFlowDataTypeFromObject(Curve.new())).is_equal(FlowData.DataType.Resource)


# --- newStream -----------------------------------------------------------------------

func _element() -> FlowNodeBase:
	var element : FlowNodeBase = load(FlowNodeRegistry.get_node_script_path("add_attribute")).new()
	element.settings = element.getMeta().settings.new()
	return element


func test_new_stream_callable_and_fill_for_every_type() -> void:
	var element := _element()
	for t in all_types():
		if t == FlowData.DataType.NodeMesh or t == FlowData.DataType.NodePath:
			continue
		var v = sample_value(t)
		# The historical Bool branch stores the callable's result as is, so
		# Bool callables return 0 / 1 (unchanged behaviour).
		var produced = 1 if t == FlowData.DataType.Bool else v
		var by_callable = element.newStream(3, "s", func(_i): return produced, t)
		assert_object(by_callable).override_failure_message("callable %s" % FlowData.DataType.keys()[t]).is_not_null()
		var by_fill = element.newStream(3, "s", v, t)
		for stream in [by_callable, by_fill]:
			assert_int(stream.container.size()).is_equal(3)
			assert_bool(FlowData.Data.containerMatchesType(stream.container, t)).override_failure_message("container of %s" % FlowData.DataType.keys()[t]).is_true()
			var stored = stream.container[2]
			match t:
				FlowData.DataType.Bool:
					assert_int(stored).is_equal(1)
				FlowData.DataType.Quaternion:
					assert_bool(FlowData.vec4ToQuat(stored).is_equal_approx(v)).is_true()
				FlowData.DataType.Float:
					assert_float(stored).is_equal_approx(v, 1e-6)
				FlowData.DataType.Double:
					assert_float(stored).is_equal(v)
				_:
					assert_that(stored).is_equal(v)


func test_new_stream_converts_quaternion_and_vector2i() -> void:
	var element := _element()
	var q = element.newStream(2, "q", Quaternion.IDENTITY, FlowData.DataType.Quaternion)
	assert_that(q.container[1]).is_equal(Vector4(0, 0, 0, 1))
	var v2 = element.newStream(2, "v", func(i): return Vector2i(i, i), FlowData.DataType.Vector2)
	assert_that(v2.container[1]).is_equal(Vector2(1, 1))


# --- _coerce_input_data ----------------------------------------------------------------

func test_coerce_accepts_raw_vector2_and_transform3d() -> void:
	var cases := [
		[Vector2(1, 2), FlowData.DataType.Vector2, Vector2(1, 2)],
		[Vector2i(3, 4), FlowData.DataType.Vector2, Vector2(3, 4)],
		[Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)), FlowData.DataType.Transform, Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))],
		[Vector4(1, 2, 3, 4), FlowData.DataType.Vector4, Vector4(1, 2, 3, 4)],
		[Quaternion.IDENTITY, FlowData.DataType.Quaternion, Vector4(0, 0, 0, 1)],
	]
	for c in cases:
		var d = FlowNodeIO._coerce_input_data(c[0], "x")
		assert_object(d).override_failure_message("raw %s" % type_string(typeof(c[0]))).is_not_null()
		var s = d.findStream("x")
		assert_int(s.data_type).is_equal(c[1])
		assert_that(s.container[0]).is_equal(c[2])


func test_coerce_uses_the_parameter_type_when_the_value_feeds_it() -> void:
	var d = FlowNodeIO._coerce_input_data(1 << 40, "x", FlowData.DataType.Int64)
	assert_int(d.findStream("x").data_type).is_equal(FlowData.DataType.Int64)
	assert_int(d.findStream("x").container[0]).is_equal(1 << 40)
	d = FlowNodeIO._coerce_input_data(0.1 + 1e-12, "x", FlowData.DataType.Double)
	assert_int(d.findStream("x").data_type).is_equal(FlowData.DataType.Double)
	assert_float(d.findStream("x").container[0]).is_equal(0.1 + 1e-12)
	d = FlowNodeIO._coerce_input_data(Vector4(0, 0, 0, 1), "x", FlowData.DataType.Quaternion)
	assert_int(d.findStream("x").data_type).is_equal(FlowData.DataType.Quaternion)
	# Unchanged: an int fed into a Float parameter arrives as Int.
	d = FlowNodeIO._coerce_input_data(3, "x", FlowData.DataType.Float)
	assert_int(d.findStream("x").data_type).is_equal(FlowData.DataType.Int)


# --- Graph parameter types ----------------------------------------------------------------

func test_graph_parameter_has_a_value_property_for_every_editor_type() -> void:
	for t in FlowGraphParametersEditor.PARAMETER_TYPES:
		var prop := GraphInputParameter.value_property_name(t)
		assert_str(prop).override_failure_message("no constant for %s" % FlowData.DataType.keys()[t]).is_not_empty()
		# The inspector plugin shows the property named after the type key.
		assert_str(prop).is_equal("cte_" + FlowData.DataType.keys()[t].to_lower())
		var p := GraphInputParameter.new()
		assert_bool(prop in p).is_true()
		p.data_type = t
		var v = sample_value(t)
		p.set(prop, v)
		if t == FlowData.DataType.Resource:
			assert_object(p.get_default_value()).is_same(v)
		else:
			assert_that(p.get_default_value()).is_equal(v)
	for t in EXTENDED:
		assert_bool(FlowGraphParametersEditor.PARAMETER_TYPES.has(t)).override_failure_message("%s not offered" % FlowData.DataType.keys()[t]).is_true()
	assert_str(GraphInputParameter.value_property_name(FlowData.DataType.NodeMesh)).is_empty()
	assert_str(GraphInputParameter.value_property_name(FlowData.DataType.Invalid)).is_empty()


func test_graph_parameters_editor_type_helpers() -> void:
	var editor := FlowGraphParametersEditor.new()
	var colours := {}
	for t in FlowGraphParametersEditor.PARAMETER_TYPES:
		assert_str(editor._value_property_name(t)).is_equal(GraphInputParameter.value_property_name(t))
		assert_str(editor._type_label(t)).is_not_empty()
		var c : Color = editor._ue_type_color(t)
		assert_bool(c == Color("7a8494")).override_failure_message("%s has the fallback colour" % FlowData.DataType.keys()[t]).is_false()
		assert_bool(colours.has(c)).override_failure_message("%s shares a colour" % FlowData.DataType.keys()[t]).is_false()
		colours[c] = true
	for t in [FlowData.DataType.Vector, FlowData.DataType.Vector4, FlowData.DataType.Quaternion, FlowData.DataType.Transform]:
		assert_bool(FlowGraphParametersEditor.is_wide_value_type(t)).is_true()
	for t in [FlowData.DataType.Float, FlowData.DataType.Vector2, FlowData.DataType.Int64]:
		assert_bool(FlowGraphParametersEditor.is_wide_value_type(t)).is_false()
	editor.free()


# --- Widget slots ---------------------------------------------------------------------------

## add_attribute exposes its cte_<type> constant as a parameter port; the
## widget types and colours that port from the settings property type.
func test_widget_slots_for_exposed_parameters_of_every_type() -> void:
	var editor : Control = load("res://addons/flow_nodes_editor/flow_editor.tscn").instantiate()
	add_child(editor)
	editor.set_process(false)
	editor.clear_graph()
	editor.current_resource = FlowGraphResource.new()
	editor.scanAvailableNodesIfNeeded()
	var widget : FlowNodeWidget = editor.addNodeFromTemplate("add_attribute", "attr")
	widget.show_disconnected_inputs = true
	for t in [FlowData.DataType.Float, FlowData.DataType.Vector] + EXTENDED:
		widget.settings.data_type = t
		widget.onPropChanged("data_type")
		widget.initFromScript()
		var expected_type : int = t
		if t == FlowData.DataType.Int64:
			expected_type = FlowData.DataType.Int
		elif t == FlowData.DataType.Double:
			expected_type = FlowData.DataType.Float
		# Port 0 is the flow input, port 1 the cte_<type> parameter.
		assert_bool(widget.is_slot_enabled_left(1)).override_failure_message("no parameter port for %s" % FlowData.DataType.keys()[t]).is_true()
		assert_int(widget.get_slot_type_left(1)).override_failure_message("slot type for %s" % FlowData.DataType.keys()[t]).is_equal(expected_type)
		assert_that(widget.get_slot_color_left(1)).is_equal(FlowNodeBase.getColorForFlowDataType(expected_type))
	editor.clear_graph()
	remove_child(editor)
	editor.free()
	await get_tree().process_frame


## Hand-drawn wires between typed ports (FlowEditor.canConnect): Int64 and
## Double graph inputs feed int / float setting ports; other types still only
## match themselves.
func test_typed_ports_connect_by_type_family() -> void:
	assert_int(FlowEditor.connection_type_family(FlowData.DataType.Int64)).is_equal(FlowData.DataType.Int)
	assert_int(FlowEditor.connection_type_family(FlowData.DataType.Double)).is_equal(FlowData.DataType.Float)
	for t in [FlowData.DataType.Vector2, FlowData.DataType.Vector4, FlowData.DataType.Quaternion, FlowData.DataType.Transform, FlowData.DataType.Vector]:
		assert_int(FlowEditor.connection_type_family(t)).is_equal(t)
	var editor : Control = load("res://addons/flow_nodes_editor/flow_editor.tscn").instantiate()
	add_child(editor)
	editor.set_process(false)
	editor.clear_graph()
	editor.current_resource = FlowGraphResource.new()
	editor.scanAvailableNodesIfNeeded()
	var attr : FlowNodeWidget = editor.addNodeFromTemplate("add_attribute", "attr")
	attr.show_disconnected_inputs = true
	attr.settings.data_type = FlowData.DataType.Int
	attr.initFromScript()
	assert_int(attr.get_input_port_type(1)).is_equal(FlowData.DataType.Int)
	var cases := {
		FlowData.DataType.Int64: true,
		FlowData.DataType.Int: true,
		FlowData.DataType.Double: false,
		FlowData.DataType.Vector2: false,
	}
	var index := 0
	for t in cases:
		index += 1
		var src : FlowNodeWidget = editor.addNodeFromTemplate("input", "in_%d" % index)
		src.settings.name = "p_%d" % index
		src.settings.data_type = t
		src.initFromScript()
		assert_int(src.get_output_port_type(0)).is_equal(t)
		assert_bool(editor.canConnect(src, 0, attr, 1)).override_failure_message("%s into an Int port" % FlowData.DataType.keys()[t]).is_equal(cases[t])
	editor.clear_graph()
	remove_child(editor)
	editor.free()
	await get_tree().process_frame
