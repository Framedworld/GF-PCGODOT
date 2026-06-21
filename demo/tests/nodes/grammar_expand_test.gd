# grammar_expand_test.gd
class_name GrammarExpandTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const GrammarExpandNode = preload("res://addons/flow_nodes_editor/nodes/grammar_expand.gd")
const GrammarExpandSettings = preload("res://addons/flow_nodes_editor/nodes/grammar_expand_settings.gd")
const GrammarModuleResource = preload("res://addons/flow_nodes_editor/grammar_module_resource.gd")

func _make_span_data(positions: PackedVector3Array, rotations: PackedVector3Array, sizes: PackedVector3Array, lengths: PackedFloat32Array = PackedFloat32Array()) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	var n := positions.size()
	d.addCommonStreams(n)
	var spos = d.getVector3Container(FlowDataScript.AttrPosition)
	var srot = d.getVector3Container(FlowDataScript.AttrRotation)
	var ssize = d.getVector3Container(FlowDataScript.AttrSize)
	for i in range(n):
		spos[i] = positions[i]
		srot[i] = rotations[i]
		ssize[i] = sizes[i]
	if lengths.size() > 0:
		d.registerStream("length", lengths, FlowDataScript.DataType.Float)
	return d

func _make_single_span(length: float) -> FlowData.Data:
	var pos := PackedVector3Array([Vector3(0, 0, 0)])
	var rot := PackedVector3Array([Vector3.ZERO])
	var sz := PackedVector3Array([Vector3(1.0, 1.0, length)])
	return _make_span_data(pos, rot, sz)

func _make_settings_with_modules(grammar: String, module_defs: Array, fit_mode: int = GrammarExpandSettings.eFitMode.STRETCH) -> GrammarExpandSettings:
	var s := GrammarExpandSettings.new()
	s.grammar = grammar
	s.fit_mode = fit_mode
	s.out_symbol_attribute = "symbol"
	s.out_module_index_attribute = "module_index"
	s.out_mesh_attribute = "mesh"
	s.length_attribute = "length"
	s.modules.clear()
	for m in module_defs:
		var entry = GrammarModuleResource.new()
		entry.symbol = m.get("symbol", "")
		entry.size = m.get("size", 1.0)
		entry.weight = m.get("weight", 1.0)
		entry.mesh = m.get("mesh", null)
		s.modules.append(entry)
	return s

func _run(inputs: Array, settings) -> GrammarExpandNode:
	var node = GrammarExpandNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func test_missing_input_sets_error() -> void:
	var s := _make_settings_with_modules("A*", [{"symbol": "A", "size": 1.0, "weight": 1.0, "mesh": null}])
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_input_without_required_streams_sets_error() -> void:
	var s := _make_settings_with_modules("A*", [{"symbol": "A", "size": 1.0, "weight": 1.0, "mesh": null}])
	var d := FlowDataScript.Data.new()
	d.registerStream("random", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_empty_module_table_sets_error() -> void:
	var s := GrammarExpandSettings.new()
	s.grammar = "A*"
	s.modules = []
	var node = _run([_make_single_span(10.0)], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_empty_grammar_sets_error() -> void:
	var s := _make_settings_with_modules("", [{"symbol": "A", "size": 1.0, "weight": 1.0, "mesh": null}])
	var node = _run([_make_single_span(10.0)], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_invalid_grammar_sets_error() -> void:
	var s := _make_settings_with_modules("{ unclosed", [{"symbol": "A", "size": 1.0, "weight": 1.0, "mesh": null}])
	var node = _run([_make_single_span(10.0)], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_simple_sequence_stretch_fit() -> void:
	var modules := [
		{"symbol": "A", "size": 2.0, "weight": 1.0, "mesh": null},
		{"symbol": "B", "size": 3.0, "weight": 1.0, "mesh": null},
	]
	var s := _make_settings_with_modules("A B", modules, GrammarExpandSettings.eFitMode.STRETCH)
	var node = _run([_make_single_span(10.0)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)
	var sym_stream = out.findStream("symbol")
	assert_object(sym_stream).is_not_null()
	assert_str(sym_stream.container[0]).is_equal("A")
	assert_str(sym_stream.container[1]).is_equal("B")
	var idx_stream = out.findStream("module_index")
	assert_object(idx_stream).is_not_null()
	assert_int(int(idx_stream.container[0])).is_equal(0)
	assert_int(int(idx_stream.container[1])).is_equal(1)
	node.free()

func test_fill_repeat_produces_tiling_modules() -> void:
	var modules := [
		{"symbol": "A", "size": 2.0, "weight": 1.0, "mesh": null},
	]
	var s := _make_settings_with_modules("A*", modules, GrammarExpandSettings.eFitMode.STRETCH)
	var node = _run([_make_single_span(10.0)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(5)
	var sym_stream = out.findStream("symbol")
	assert_object(sym_stream).is_not_null()
	for i in range(5):
		assert_str(sym_stream.container[i]).is_equal("A")
	node.free()

func test_repeat_n_times() -> void:
	var modules := [
		{"symbol": "A", "size": 1.0, "weight": 1.0, "mesh": null},
	]
	var s := _make_settings_with_modules("A:3", modules, GrammarExpandSettings.eFitMode.STRETCH)
	var node = _run([_make_single_span(6.0)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)
	node.free()

func test_clip_fit_mode_drops_overrunning_modules() -> void:
	var modules := [
		{"symbol": "A", "size": 3.0, "weight": 1.0, "mesh": null},
	]
	var s := _make_settings_with_modules("A A A A A", modules, GrammarExpandSettings.eFitMode.CLIP)
	var node = _run([_make_single_span(10.0)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# 3 modules of size 3 = 9 <= 10; 4th module at cursor=9, 9+3=12 > 10 => dropped
	assert_int(out.size()).is_equal(3)
	node.free()

func test_stretch_fit_positions_modules_along_span() -> void:
	# With zero rotation: basis = identity, basis.z = (0,0,1), axis = -basis.z = (0,0,-1)
	# span_start = (0,0,0) - (0,0,-1)*2 = (0,0,2)
	# A (fitted_len=2): center = (0,0,2) + (0,0,-1)*(0+1) = (0,0,1)
	# B (fitted_len=2): center = (0,0,2) + (0,0,-1)*(2+1) = (0,0,-1)
	# So spos[0].z = 1.0, spos[1].z = -1.0; spos[0].z > spos[1].z
	var modules := [
		{"symbol": "A", "size": 1.0, "weight": 1.0, "mesh": null},
		{"symbol": "B", "size": 1.0, "weight": 1.0, "mesh": null},
	]
	var s := _make_settings_with_modules("A B", modules, GrammarExpandSettings.eFitMode.STRETCH)
	var node = _run([_make_single_span(4.0)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)
	var spos = out.getVector3Container(FlowDataScript.AttrPosition)
	# modules laid out in decreasing Z (axis faces -Z with zero rotation)
	assert_float(spos[0].z).is_greater(spos[1].z)
	var ssize = out.getVector3Container(FlowDataScript.AttrSize)
	assert_float(ssize[0].z).is_equal_approx(2.0, 0.001)
	assert_float(ssize[1].z).is_equal_approx(2.0, 0.001)
	node.free()

func test_output_has_density_and_seed_streams() -> void:
	var modules := [
		{"symbol": "A", "size": 1.0, "weight": 1.0, "mesh": null},
	]
	var s := _make_settings_with_modules("A:2", modules, GrammarExpandSettings.eFitMode.STRETCH)
	var node = _run([_make_single_span(4.0)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var density_stream = out.findStream(FlowDataScript.AttrDensity)
	assert_object(density_stream).is_not_null()
	assert_int(density_stream.container.size()).is_equal(2)
	assert_float(float(density_stream.container[0])).is_equal_approx(1.0, 0.001)
	var seed_stream = out.findStream(FlowDataScript.AttrSeed)
	assert_object(seed_stream).is_not_null()
	assert_int(seed_stream.container.size()).is_equal(2)
	node.free()

func test_multiple_spans_each_expanded() -> void:
	var modules := [
		{"symbol": "A", "size": 1.0, "weight": 1.0, "mesh": null},
	]
	var s := _make_settings_with_modules("A:2", modules, GrammarExpandSettings.eFitMode.STRETCH)
	var pos := PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
	var rot := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var sz := PackedVector3Array([Vector3(1, 1, 4.0), Vector3(1, 1, 4.0)])
	var span_data = _make_span_data(pos, rot, sz)
	var node = _run([span_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(4)
	node.free()

func test_length_attribute_overrides_size_z() -> void:
	var modules := [
		{"symbol": "A", "size": 1.0, "weight": 1.0, "mesh": null},
	]
	var s := _make_settings_with_modules("A*", modules, GrammarExpandSettings.eFitMode.STRETCH)
	var pos := PackedVector3Array([Vector3(0, 0, 0)])
	var rot := PackedVector3Array([Vector3.ZERO])
	var sz := PackedVector3Array([Vector3(1, 1, 2.0)])
	var lengths := PackedFloat32Array([5.0])
	var span_data = _make_span_data(pos, rot, sz, lengths)
	var node = _run([span_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(5)
	node.free()

func test_cross_section_size_in_output() -> void:
	var modules := [
		{"symbol": "A", "size": 1.0, "weight": 1.0, "mesh": null},
	]
	var s := _make_settings_with_modules("A:1", modules, GrammarExpandSettings.eFitMode.STRETCH)
	s.cross_section_size = Vector2(3.0, 4.0)
	var node = _run([_make_single_span(5.0)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var ssize = out.getVector3Container(FlowDataScript.AttrSize)
	assert_float(ssize[0].x).is_equal_approx(3.0, 0.001)
	assert_float(ssize[0].y).is_equal_approx(4.0, 0.001)
	node.free()

func test_tuple_grammar_expands_symbol() -> void:
	var modules := [
		{"symbol": "Post", "size": 1.0, "weight": 1.0, "mesh": null},
		{"symbol": "Panel", "size": 2.0, "weight": 1.0, "mesh": null},
	]
	var s := _make_settings_with_modules("[Post,P] [Panel,P]", modules, GrammarExpandSettings.eFitMode.STRETCH)
	var node = _run([_make_single_span(9.0)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)
	var sym_stream = out.findStream("symbol")
	assert_object(sym_stream).is_not_null()
	assert_str(sym_stream.container[0]).is_equal("Post")
	assert_str(sym_stream.container[1]).is_equal("Panel")
	node.free()

func test_zero_length_span_skipped() -> void:
	var modules := [
		{"symbol": "A", "size": 1.0, "weight": 1.0, "mesh": null},
	]
	var s := _make_settings_with_modules("A*", modules, GrammarExpandSettings.eFitMode.STRETCH)
	var pos := PackedVector3Array([Vector3(0, 0, 0)])
	var rot := PackedVector3Array([Vector3.ZERO])
	var sz := PackedVector3Array([Vector3(1, 1, 0.0)])
	var span_data = _make_span_data(pos, rot, sz)
	var node = _run([span_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()
