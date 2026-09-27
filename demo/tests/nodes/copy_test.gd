# copy_test.gd
class_name CopyTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const CopyNode = preload("res://addons/flow_nodes_editor/nodes/copy.gd")
const CopySettings = preload("res://addons/flow_nodes_editor/nodes/copy_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _make_point_data(positions: PackedVector3Array, rotations: PackedVector3Array, sizes: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrRotation, rotations, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> CopyNode:
	var node = CopyNode.new()
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

func test_linear_copy_basic_float() -> void:
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.LinearCopies
	s.num_copies = 3

	var src = _make_data("value", PackedFloat32Array([10.0, 20.0]), FlowDataScript.DataType.Float)
	var node = _run([src, null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("value")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(6)
	assert_float(stream.container[0]).is_equal(10.0)
	assert_float(stream.container[1]).is_equal(20.0)
	assert_float(stream.container[2]).is_equal(10.0)
	assert_float(stream.container[3]).is_equal(20.0)
	node.free()

func test_linear_copy_num_copies_zero_returns_empty() -> void:
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.LinearCopies
	s.num_copies = 0

	var src = _make_data("value", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([src, null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

func test_linear_copy_with_translation_offsets() -> void:
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.LinearCopies
	s.num_copies = 2
	s.translation = Vector3(10.0, 0.0, 0.0)
	s.rotation = Vector3.ZERO

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var rotations = PackedVector3Array([Vector3.ZERO])
	var sizes = PackedVector3Array([Vector3.ONE])
	var src = _make_point_data(positions, rotations, sizes)

	var node = _run([src, null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)

	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	var pos_container: PackedVector3Array = pos_stream.container
	assert_float(pos_container[0].x).is_equal(0.0)
	assert_float(pos_container[1].x).is_equal_approx(10.0, 0.001)
	node.free()

func test_linear_copy_generates_copy_id() -> void:
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.LinearCopies
	s.num_copies = 3
	s.generate_copy_id = "copy_id"

	var src = _make_data("value", PackedFloat32Array([5.0]), FlowDataScript.DataType.Float)
	var node = _run([src, null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var id_stream = out.findStream("copy_id")
	assert_object(id_stream).is_not_null()
	assert_int(id_stream.container.size()).is_equal(3)
	assert_int(id_stream.container[0]).is_equal(0)
	assert_int(id_stream.container[1]).is_equal(1)
	assert_int(id_stream.container[2]).is_equal(2)
	node.free()

func test_missing_source_input_sets_error() -> void:
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.LinearCopies
	s.num_copies = 2

	var node = _run([null, null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_source_to_targets_basic_cycle() -> void:
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.SourceToTargets
	s.source_selection = CopySettings.eSourceSelection.Cycle
	s.combine_source_with_target_transform = false
	s.inherit_target_scale = false

	var src_positions = PackedVector3Array([Vector3(1.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)])
	var src_rotations = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var src_sizes = PackedVector3Array([Vector3.ONE, Vector3.ONE])
	var src = _make_point_data(src_positions, src_rotations, src_sizes)
	src.registerStream("label", PackedFloat32Array([10.0, 20.0]), FlowDataScript.DataType.Float)

	var tgt_positions = PackedVector3Array([Vector3(5.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), Vector3(7.0, 0.0, 0.0)])
	var tgt_rotations = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var tgt_sizes = PackedVector3Array([Vector3.ONE, Vector3.ONE, Vector3.ONE])
	var tgt = _make_point_data(tgt_positions, tgt_rotations, tgt_sizes)

	var node = _run([src, tgt], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)
	node.free()

func test_source_to_targets_missing_targets_sets_error() -> void:
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.SourceToTargets

	var positions = PackedVector3Array([Vector3.ZERO])
	var rotations = PackedVector3Array([Vector3.ZERO])
	var sizes = PackedVector3Array([Vector3.ONE])
	var src = _make_point_data(positions, rotations, sizes)

	var node = _run([src, null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_source_to_targets_writes_copy_id_and_target_index() -> void:
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.SourceToTargets
	s.source_selection = CopySettings.eSourceSelection.Cycle
	s.combine_source_with_target_transform = false
	s.inherit_target_scale = false
	s.generate_copy_id = "src_idx"
	s.write_target_index_attribute = "tgt_idx"

	var src_positions = PackedVector3Array([Vector3(1.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)])
	var src_rotations = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var src_sizes = PackedVector3Array([Vector3.ONE, Vector3.ONE])
	var src = _make_point_data(src_positions, src_rotations, src_sizes)

	var tgt_positions = PackedVector3Array([Vector3(5.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0)])
	var tgt_rotations = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var tgt_sizes = PackedVector3Array([Vector3.ONE, Vector3.ONE])
	var tgt = _make_point_data(tgt_positions, tgt_rotations, tgt_sizes)

	var node = _run([src, tgt], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var src_id_stream = out.findStream("src_idx")
	assert_object(src_id_stream).is_not_null()
	assert_int(src_id_stream.container.size()).is_equal(2)
	assert_int(src_id_stream.container[0]).is_equal(0)
	assert_int(src_id_stream.container[1]).is_equal(1)

	var tgt_id_stream = out.findStream("tgt_idx")
	assert_object(tgt_id_stream).is_not_null()
	assert_int(tgt_id_stream.container.size()).is_equal(2)
	assert_int(tgt_id_stream.container[0]).is_equal(0)
	assert_int(tgt_id_stream.container[1]).is_equal(1)
	node.free()

# ---------------------------------------------------------------------------
# SourceToTargets attribute inheritance (UE Copy Points parity)
# ---------------------------------------------------------------------------

## Source: 2 points carrying `kind` (String) and `shared` (Float).
func _inherit_source() -> FlowData.Data:
	var d = _make_point_data(
		PackedVector3Array([Vector3(0, 1, 0), Vector3(0, 2, 0)]),
		PackedVector3Array([Vector3.ZERO, Vector3(0, 90, 0)]),
		PackedVector3Array([Vector3.ONE, Vector3(2, 2, 2)]))
	d.registerStream("kind", PackedStringArray(["chair", "table"]), FlowDataScript.DataType.String)
	d.registerStream("shared", PackedFloat32Array([0.5, 1.5]), FlowDataScript.DataType.Float)
	return d

## Targets: 3 points carrying `shared` (Int — collides with the source's Float),
## `room` (Int), a broadcast `zone` (String) and a rotation_quat that must never
## be inherited (it would override the recomputed rotation downstream).
func _inherit_targets() -> FlowData.Data:
	var d = _make_point_data(
		PackedVector3Array([Vector3(10, 0, 0), Vector3(20, 0, 0), Vector3(30, 0, 0)]),
		PackedVector3Array([Vector3.ZERO, Vector3(0, 45, 0), Vector3.ZERO]),
		PackedVector3Array([Vector3.ONE, Vector3.ONE, Vector3(3, 3, 3)]))
	d.registerStream("shared", PackedInt32Array([7, 8, 9]), FlowDataScript.DataType.Int)
	d.registerStream("room", PackedInt32Array([100, 200, 300]), FlowDataScript.DataType.Int)
	d.registerStream("zone", PackedStringArray(["crypt"]), FlowDataScript.DataType.String)
	d.registerStream(FlowData.AttrRotationQuat, PackedVector4Array([Vector4(0, 0, 0, 1), Vector4(0, 0, 0, 1), Vector4(0, 0, 0, 1)]), FlowDataScript.DataType.Quaternion)
	return d

func _run_inheritance(mode: int, set_mode := true) -> CopyNode:
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.SourceToTargets
	if set_mode:
		s.attribute_inheritance = mode
	return _run([_inherit_source(), _inherit_targets()], s)

func _assert_transforms_unchanged(out: FlowData.Data) -> void:
	# Cycle picks source 0,1,0; combine_source_with_target_transform = true.
	var ref_node = _run_inheritance(0, false)
	var ref = _output(ref_node)
	for stream_name in [FlowData.AttrPosition, FlowData.AttrRotation, FlowData.AttrSize]:
		assert_array(Array(out.findStream(stream_name).container)) \
			.is_equal(Array(ref.findStream(stream_name).container))
	assert_bool(out.hasStream(FlowData.AttrRotationQuat)).is_false()
	ref_node.free()

func test_attribute_inheritance_default_is_source_only() -> void:
	var s = CopySettings.new()
	assert_int(s.attribute_inheritance).is_equal(CopySettings.eAttributeInheritance.SourceOnly)
	var node = _run_inheritance(0, false)
	var out = _output(node)
	# Exactly today's streams: the source's, nothing from the targets.
	assert_array(out.streams.keys()).is_equal(["position", "rotation", "size", "kind", "shared"])
	assert_array(Array(out.findStream("kind").container)).is_equal(["chair", "table", "chair"])
	assert_array(Array(out.findStream("position").container)).is_equal(
		[Vector3(10, 1, 0), Vector3(20, 2, 0), Vector3(30, 3, 0)]) # target 2 has size 3
	node.free()

func test_attribute_inheritance_source_only() -> void:
	var node = _run_inheritance(CopySettings.eAttributeInheritance.SourceOnly)
	var out = _output(node)
	assert_bool(out.hasStream("room")).is_false()
	assert_bool(out.hasStream("zone")).is_false()
	assert_int(out.findStream("shared").data_type).is_equal(FlowDataScript.DataType.Float)
	_assert_transforms_unchanged(out)
	node.free()

func test_attribute_inheritance_source_first() -> void:
	var node = _run_inheritance(CopySettings.eAttributeInheritance.SourceFirst)
	var out = _output(node)
	assert_str(node.err).is_empty()
	# Source wins the `shared` collision.
	var shared = out.findStream("shared")
	assert_int(shared.data_type).is_equal(FlowDataScript.DataType.Float)
	assert_array(Array(shared.container)).is_equal([0.5, 1.5, 0.5])
	assert_array(Array(out.findStream("kind").container)).is_equal(["chair", "table", "chair"])
	# Target-only attributes follow the target rows; broadcast stays broadcast.
	assert_array(Array(out.findStream("room").container)).is_equal([100, 200, 300])
	assert_array(Array(out.findStream("zone").container)).is_equal(["crypt"])
	_assert_transforms_unchanged(out)
	node.free()

func test_attribute_inheritance_target_first() -> void:
	var holder := {}
	# Retyping `shared` to the target's Int is intended: no conflict warning.
	await assert_error(func(): holder.node = _run_inheritance(CopySettings.eAttributeInheritance.TargetFirst)).is_success()
	var node = holder.node
	var out = _output(node)
	var shared = out.findStream("shared")
	assert_int(shared.data_type).is_equal(FlowDataScript.DataType.Int)
	assert_array(Array(shared.container)).is_equal([7, 8, 9])
	assert_array(Array(out.findStream("kind").container)).is_equal(["chair", "table", "chair"])
	assert_array(Array(out.findStream("room").container)).is_equal([100, 200, 300])
	_assert_transforms_unchanged(out)
	node.free()

func test_attribute_inheritance_target_only() -> void:
	var node = _run_inheritance(CopySettings.eAttributeInheritance.TargetOnly)
	var out = _output(node)
	assert_bool(out.hasStream("kind")).is_false()
	assert_array(Array(out.findStream("shared").container)).is_equal([7, 8, 9])
	assert_array(Array(out.findStream("room").container)).is_equal([100, 200, 300])
	assert_array(Array(out.findStream("zone").container)).is_equal(["crypt"])
	_assert_transforms_unchanged(out)
	node.free()

func test_attribute_inheritance_copy_id_and_target_index_still_written() -> void:
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.SourceToTargets
	s.attribute_inheritance = CopySettings.eAttributeInheritance.TargetOnly
	s.generate_copy_id = "copy_id"
	s.write_target_index_attribute = "target_index"
	var node = _run([_inherit_source(), _inherit_targets()], s)
	var out = _output(node)
	assert_array(Array(out.findStream("copy_id").container)).is_equal([0, 1, 0])
	assert_array(Array(out.findStream("target_index").container)).is_equal([0, 1, 2])
	node.free()
