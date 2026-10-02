# apply_scale_to_bounds_test.gd
class_name ApplyScaleToBoundsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/apply_scale_to_bounds.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/apply_scale_to_bounds_settings.gd")

func _exec(data, settings = null) -> Dictionary:
	if settings == null:
		settings = SettingsScript.new()
	return H.exec(NodeScript, settings, [data])

func _out(data, settings = null):
	var r := _exec(data, settings)
	assert_str(r.err).is_empty()
	return H.port(r)

func test_meta_declares_unreal_alias() -> void:
	var node = NodeScript.new()
	assert_str(node.meta_node.title).is_equal("Apply Scale To Bounds")
	assert_array(node.meta_node.aliases).contains(["Apply Scale To Bounds"])
	H.dispose(node)

func test_implicit_bounds_keep_world_box_and_reset_scale() -> void:
	var d = H.points([Vector3(1, 2, 3)])
	d.getVector3Container("size")[0] = Vector3(2, 4, 6)
	var before = BoundsOverlapUtil.world_aabbs(d, d.getVector3Container("position"))
	var out = _out(d)
	assert_vector(out.getVector3Container("size")[0]).is_equal(Vector3.ONE)
	assert_vector(out.getVector3Container("bounds_min")[0]).is_equal(Vector3(-1, -2, -3))
	assert_vector(out.getVector3Container("bounds_max")[0]).is_equal(Vector3(1, 2, 3))
	var after = BoundsOverlapUtil.world_aabbs(out, out.getVector3Container("position"))
	assert_vector(after.min[0]).is_equal(before.min[0])
	assert_vector(after.max[0]).is_equal(before.max[0])

func test_asymmetric_bounds_are_scaled_not_recentered() -> void:
	var d = H.points([Vector3.ZERO])
	d.getVector3Container("size")[0] = Vector3(2, 3, 1)
	d.registerStream("bounds_min", PackedVector3Array([Vector3(0, -1, -2)]), FlowDataScript.DataType.Vector)
	d.registerStream("bounds_max", PackedVector3Array([Vector3(4, 1, 1)]), FlowDataScript.DataType.Vector)
	var out = _out(d)
	assert_vector(out.getVector3Container("bounds_min")[0]).is_equal(Vector3(0, -3, -2))
	assert_vector(out.getVector3Container("bounds_max")[0]).is_equal(Vector3(8, 3, 1))
	assert_vector(out.getVector3Container("size")[0]).is_equal(Vector3.ONE)
	assert_vector(out.getVector3Container("position")[0]).is_equal(Vector3.ZERO)

func test_negative_scale_swaps_min_and_max() -> void:
	var d = H.points([Vector3.ZERO])
	d.getVector3Container("size")[0] = Vector3(-2, 1, 1)
	d.registerStream("bounds_min", PackedVector3Array([Vector3(-1, -1, -1)]), FlowDataScript.DataType.Vector)
	d.registerStream("bounds_max", PackedVector3Array([Vector3(3, 1, 1)]), FlowDataScript.DataType.Vector)
	var out = _out(d)
	assert_vector(out.getVector3Container("bounds_min")[0]).is_equal(Vector3(-6, -1, -1))
	assert_vector(out.getVector3Container("bounds_max")[0]).is_equal(Vector3(2, 1, 1))

func test_broadcast_bounds_and_size() -> void:
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3.ZERO, Vector3(5, 0, 0), Vector3(9, 0, 0)]), FlowDataScript.DataType.Vector)
	d.registerStream("size", PackedVector3Array([Vector3(2, 2, 2)]), FlowDataScript.DataType.Vector)
	d.registerStream("bounds_min", PackedVector3Array([Vector3(-1, 0, -1)]), FlowDataScript.DataType.Vector)
	d.registerStream("bounds_max", PackedVector3Array([Vector3(1, 2, 1)]), FlowDataScript.DataType.Vector)
	var out = _out(d)
	var bmin = out.getVector3Container("bounds_min")
	var bmax = out.getVector3Container("bounds_max")
	assert_int(bmin.size()).is_equal(3)
	for i in range(3):
		assert_vector(bmin[i]).is_equal(Vector3(-2, 0, -2))
		assert_vector(bmax[i]).is_equal(Vector3(2, 4, 2))
	# A broadcast scale stays broadcast (one element), reset to one.
	assert_int(out.getVector3Container("size").size()).is_equal(1)
	assert_vector(out.getVector3Container("size")[0]).is_equal(Vector3.ONE)

func test_reset_scale_off_keeps_size() -> void:
	var d = H.points([Vector3.ZERO])
	d.getVector3Container("size")[0] = Vector3(2, 2, 2)
	var s = SettingsScript.new()
	s.reset_scale = false
	var out = _out(d, s)
	assert_vector(out.getVector3Container("size")[0]).is_equal(Vector3(2, 2, 2))
	assert_vector(out.getVector3Container("bounds_max")[0]).is_equal(Vector3(1, 1, 1))

func test_missing_size_counts_as_unit_scale() -> void:
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	var out = _out(d)
	assert_bool(out.hasStream("size")).is_false()
	assert_vector(out.getVector3Container("bounds_min")[1]).is_equal(Vector3(-0.5, -0.5, -0.5))

func test_empty_input_passes_through_with_bounds_schema() -> void:
	var out = _out(H.points([]))
	assert_int(out.size()).is_equal(0)
	assert_bool(out.hasStream("bounds_min")).is_true()

func test_missing_input_reports_error() -> void:
	var r := _exec(null)
	assert_str(r.err).contains("not connected")

func test_does_not_mutate_input() -> void:
	var d = H.points([Vector3.ZERO])
	d.getVector3Container("size")[0] = Vector3(3, 3, 3)
	_out(d)
	assert_vector(d.getVector3Container("size")[0]).is_equal(Vector3(3, 3, 3))
	assert_bool(d.hasStream("bounds_min")).is_false()

func test_reorder_is_pointwise() -> void:
	var d = H.points([Vector3.ZERO, Vector3(1, 0, 0)])
	d.getVector3Container("size")[0] = Vector3(2, 2, 2)
	d.getVector3Container("size")[1] = Vector3(4, 4, 4)
	var a = _out(d)
	var b = _out(H.reversed(d))
	assert_vector(a.getVector3Container("bounds_max")[0]).is_equal(b.getVector3Container("bounds_max")[1])
	assert_vector(a.getVector3Container("bounds_max")[1]).is_equal(b.getVector3Container("bounds_max")[0])
