# point_offsets_test.gd
class_name PointOffsetsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PointOffsetsNode = preload("res://addons/flow_nodes_editor/nodes/point_offsets.gd")
const PointOffsetsSettings = preload("res://addons/flow_nodes_editor/nodes/point_offsets_settings.gd")

func _make_anchor_data(positions: PackedVector3Array, rotations: PackedVector3Array = PackedVector3Array(), sizes: PackedVector3Array = PackedVector3Array()) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	var rots := rotations
	if rots.size() == 0:
		rots.resize(positions.size())
	d.registerStream(FlowData.AttrRotation, rots, FlowDataScript.DataType.Vector)
	var szs := sizes
	if szs.size() == 0:
		szs.resize(positions.size())
		szs.fill(Vector3.ONE)
	d.registerStream(FlowData.AttrSize, szs, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> PointOffsetsNode:
	var node = PointOffsetsNode.new()
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

func test_basic_single_offset_world_space() -> void:
	var s = PointOffsetsSettings.new()
	var o: Array[Vector3] = [Vector3(1.0, 0.0, 0.0)]
	s.offsets = o
	var r: Array[Vector3] = [Vector3.ZERO]
	s.rotations = r
	var sz: Array[Vector3] = [Vector3.ONE]
	s.sizes = sz
	s.local_space = false
	s.combine_rotation = false
	s.parent_index_attribute = ""
	s.offset_index_attribute = ""
	s.label_attribute = ""

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0)])
	var anchors = _make_anchor_data(positions)

	var node = _run([anchors], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_float(pos_stream.container[0].x).is_equal_approx(1.0, 0.001)
	assert_float(pos_stream.container[1].x).is_equal_approx(6.0, 0.001)
	node.free()

func test_multiple_offsets_expand_count() -> void:
	var s = PointOffsetsSettings.new()
	var o: Array[Vector3] = [Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)]
	s.offsets = o
	var r: Array[Vector3] = [Vector3.ZERO]
	s.rotations = r
	var sz: Array[Vector3] = [Vector3.ONE]
	s.sizes = sz
	s.local_space = false
	s.combine_rotation = false
	s.parent_index_attribute = ""
	s.offset_index_attribute = ""
	s.label_attribute = ""

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0)])
	var anchors = _make_anchor_data(positions)

	var node = _run([anchors], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(6)
	node.free()

func test_local_space_applies_anchor_rotation() -> void:
	var s = PointOffsetsSettings.new()
	var o: Array[Vector3] = [Vector3(1.0, 0.0, 0.0)]
	s.offsets = o
	var r: Array[Vector3] = [Vector3.ZERO]
	s.rotations = r
	var sz: Array[Vector3] = [Vector3.ONE]
	s.sizes = sz
	s.local_space = true
	s.combine_rotation = false
	s.parent_index_attribute = ""
	s.offset_index_attribute = ""
	s.label_attribute = ""

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var rotations = PackedVector3Array([Vector3(0.0, 90.0, 0.0)])
	var anchors = _make_anchor_data(positions, rotations)

	var node = _run([anchors], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_float(pos_stream.container[0].x).is_equal_approx(0.0, 0.001)
	assert_float(pos_stream.container[0].z).is_equal_approx(-1.0, 0.001)
	node.free()

func test_parent_and_offset_index_attributes() -> void:
	var s = PointOffsetsSettings.new()
	var o: Array[Vector3] = [Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)]
	s.offsets = o
	var r: Array[Vector3] = [Vector3.ZERO]
	s.rotations = r
	var sz: Array[Vector3] = [Vector3.ONE]
	s.sizes = sz
	s.local_space = false
	s.combine_rotation = false
	s.parent_index_attribute = "parent_index"
	s.offset_index_attribute = "offset_index"
	s.label_attribute = ""

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0)])
	var anchors = _make_anchor_data(positions)

	var node = _run([anchors], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(4)

	var parent_stream = out.findStream("parent_index")
	assert_object(parent_stream).is_not_null()
	assert_int(parent_stream.container[0]).is_equal(0)
	assert_int(parent_stream.container[1]).is_equal(0)
	assert_int(parent_stream.container[2]).is_equal(1)
	assert_int(parent_stream.container[3]).is_equal(1)

	var offset_stream = out.findStream("offset_index")
	assert_object(offset_stream).is_not_null()
	assert_int(offset_stream.container[0]).is_equal(0)
	assert_int(offset_stream.container[1]).is_equal(1)
	assert_int(offset_stream.container[2]).is_equal(0)
	assert_int(offset_stream.container[3]).is_equal(1)
	node.free()

func test_label_attribute_generated() -> void:
	var s = PointOffsetsSettings.new()
	var o: Array[Vector3] = [Vector3.ZERO, Vector3(1.0, 0.0, 0.0)]
	s.offsets = o
	var r: Array[Vector3] = [Vector3.ZERO]
	s.rotations = r
	var sz: Array[Vector3] = [Vector3.ONE]
	s.sizes = sz
	s.local_space = false
	s.combine_rotation = false
	s.parent_index_attribute = ""
	s.offset_index_attribute = ""
	s.label_attribute = "offset_label"
	var lbl: Array[String] = ["base", "side"]
	s.labels = lbl

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var anchors = _make_anchor_data(positions)

	var node = _run([anchors], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var label_stream = out.findStream("offset_label")
	assert_object(label_stream).is_not_null()
	assert_str(label_stream.container[0]).is_equal("base")
	assert_str(label_stream.container[1]).is_equal("side")
	node.free()

func test_inherit_anchor_size_and_scale_offsets() -> void:
	var s = PointOffsetsSettings.new()
	var o: Array[Vector3] = [Vector3(1.0, 0.0, 0.0)]
	s.offsets = o
	var r: Array[Vector3] = [Vector3.ZERO]
	s.rotations = r
	var sz: Array[Vector3] = [Vector3(2.0, 2.0, 2.0)]
	s.sizes = sz
	s.local_space = false
	s.combine_rotation = false
	s.scale_offsets_by_anchor_size = true
	s.inherit_anchor_size = true
	s.parent_index_attribute = ""
	s.offset_index_attribute = ""
	s.label_attribute = ""

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var sizes = PackedVector3Array([Vector3(3.0, 3.0, 3.0)])
	var anchors = _make_anchor_data(positions, PackedVector3Array(), sizes)

	var node = _run([anchors], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_float(pos_stream.container[0].x).is_equal_approx(3.0, 0.001)
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_float(size_stream.container[0].x).is_equal_approx(6.0, 0.001)
	node.free()

func test_empty_input_returns_empty_output() -> void:
	var s = PointOffsetsSettings.new()
	var o: Array[Vector3] = [Vector3(1.0, 0.0, 0.0)]
	s.offsets = o
	s.parent_index_attribute = ""
	s.offset_index_attribute = ""
	s.label_attribute = ""

	var anchors = FlowDataScript.Data.new()

	var node = _run([anchors], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

func test_empty_offsets_list_returns_empty_output() -> void:
	var s = PointOffsetsSettings.new()
	var o: Array[Vector3] = []
	s.offsets = o
	s.parent_index_attribute = ""
	s.offset_index_attribute = ""
	s.label_attribute = ""

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var anchors = _make_anchor_data(positions)

	var node = _run([anchors], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

func test_missing_input_errors() -> void:
	var s = PointOffsetsSettings.new()
	var o: Array[Vector3] = [Vector3(1.0, 0.0, 0.0)]
	s.offsets = o
	s.parent_index_attribute = ""
	s.offset_index_attribute = ""
	s.label_attribute = ""

	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_extra_streams_copied_to_output() -> void:
	var s = PointOffsetsSettings.new()
	var o: Array[Vector3] = [Vector3.ZERO, Vector3(1.0, 0.0, 0.0)]
	s.offsets = o
	var r: Array[Vector3] = [Vector3.ZERO]
	s.rotations = r
	var sz: Array[Vector3] = [Vector3.ONE]
	s.sizes = sz
	s.local_space = false
	s.combine_rotation = false
	s.parent_index_attribute = ""
	s.offset_index_attribute = ""
	s.label_attribute = ""

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0)])
	var anchors = _make_anchor_data(positions)
	anchors.registerStream("density", PackedFloat32Array([0.5, 0.8]), FlowDataScript.DataType.Float)

	var node = _run([anchors], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(4)
	var density_stream = out.findStream("density")
	assert_object(density_stream).is_not_null()
	assert_int(density_stream.container.size()).is_equal(4)
	assert_float(density_stream.container[0]).is_equal_approx(0.5, 0.001)
	assert_float(density_stream.container[1]).is_equal_approx(0.5, 0.001)
	assert_float(density_stream.container[2]).is_equal_approx(0.8, 0.001)
	assert_float(density_stream.container[3]).is_equal_approx(0.8, 0.001)
	node.free()
