# r5_point_nodes_review_test.gd
# Adversarial review (WP13-R5) of the WP4b point nodes and the attribute
# casts: index syntax edges, reorder determinism, degenerate hulls, unknown
# quality levels, numeric cast limits and merge promotion order.
class_name R5PointNodesReviewTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const AH = preload("res://tests/attributes/support/node_harness.gd")
const FilterByIndex = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_index.gd")
const Sampler = preload("res://addons/flow_nodes_editor/nodes/weighted_point_sampler.gd")
const Hull = preload("res://addons/flow_nodes_editor/nodes/find_convex_hull_2d.gd")
const Discard = preload("res://addons/flow_nodes_editor/nodes/discard_points_on_irregular_surface.gd")
const QualityBranch = preload("res://addons/flow_nodes_editor/nodes/runtime_quality_branch.gd")
const CreatePoints = preload("res://addons/flow_nodes_editor/nodes/create_points.gd")
const CastNode = preload("res://addons/flow_nodes_editor/nodes/attribute_cast.gd")
const CastSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_cast_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")
const MergeAttrs = preload("res://addons/flow_nodes_editor/nodes/merge_attributes.gd")
const MergeAttrsSettings = preload("res://addons/flow_nodes_editor/nodes/merge_attributes_settings.gd")
const BitwiseNode = preload("res://addons/flow_nodes_editor/nodes/bitwise_op.gd")
const BitwiseSettings = preload("res://addons/flow_nodes_editor/nodes/bitwise_op_settings.gd")

var D = FlowDataScript.DataType

# --- filter_data_by_index ------------------------------------------------------------

func _idx(spec: String, count: int) -> Array:
	var r : Dictionary = FilterByIndex.parse_indices(spec, count)
	return [Array(r.indices), r.error != ""]

func test_index_syntax_edges() -> void:
	assert_array(_idx("", 5)).is_equal([[], false])
	assert_array(_idx("  ,  ", 5)).is_equal([[], false])
	assert_array(_idx("1:1", 5)).is_equal([[], false])
	assert_array(_idx("5:2", 5)).is_equal([[], false])
	assert_array(_idx("7, -9", 5)).is_equal([[], false])
	assert_array(_idx("-1", 5)).is_equal([[4], false])
	assert_array(_idx("-2:", 5)).is_equal([[3, 4], false])
	assert_array(_idx("-99:2", 5)).is_equal([[0, 1], false])
	assert_array(_idx(":", 3)).is_equal([[0, 1, 2], false])
	assert_array(_idx("3:99", 5)).is_equal([[3, 4], false])
	assert_array(_idx(" 2 , 0 ,2", 5)).is_equal([[0, 2], false])
	assert_bool(_idx("1:2:3", 5)[1]).is_true()
	assert_bool(_idx("a", 5)[1]).is_true()
	assert_bool(_idx("1.5", 5)[1]).is_true()
	assert_bool(_idx(":x", 5)[1]).is_true()
	assert_array(_idx("0", 0)).is_equal([[], false])

# --- weighted_point_sampler -------------------------------------------------------------

func _cloud(n: int) -> FlowData.Data:
	var positions := []
	var weights := PackedFloat32Array()
	for i in range(n):
		positions.append(Vector3(i * 1.5, 0, (i * 7) % 5))
		weights.append(float((i * 3) % 4))
	return H.points(positions, {"w": weights})

func _sampler(with_replacement: bool) -> Object:
	var s = WeightedPointSamplerNodeSettings.new()
	s.count = 5
	s.weight_attribute = "w"
	s.with_replacement = with_replacement
	return s

func test_sampler_is_reorder_invariant() -> void:
	for with_replacement in [false, true]:
		var d = _cloud(12)
		var a = H.port(H.exec(Sampler, _sampler(with_replacement), [d], H.make_ctx(null, 77)))
		var b = H.port(H.exec(Sampler, _sampler(with_replacement), [H.reversed(d)], H.make_ctx(null, 77)))
		assert_array(H.position_set(b)).is_equal(H.position_set(a))
		assert_int(a.size()).is_equal(5)

func test_sampler_never_picks_zero_or_nan_weight() -> void:
	var d = H.points([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)],
		{"w": PackedFloat32Array([0.0, sqrt(-1.0), 1.0])})
	var s = _sampler(true)
	var out = H.port(H.exec(Sampler, s, [d]))
	assert_array(H.position_set(out)).is_equal(["2.000,0.000,0.000", "2.000,0.000,0.000", "2.000,0.000,0.000", "2.000,0.000,0.000", "2.000,0.000,0.000"])

# --- find_convex_hull_2d ----------------------------------------------------------------

func _hull(positions: Array, collinear := false) -> Array:
	var s = FindConvexHull2DNodeSettings.new()
	s.include_collinear = collinear
	return H.position_set(H.port(H.exec(Hull, s, [H.points(positions)])))

func test_hull_degenerate_inputs() -> void:
	assert_array(_hull([Vector3(1, 0, 1)])).is_equal(["1.000,0.000,1.000"])
	assert_array(_hull([Vector3(1, 5, 1), Vector3(1, 2, 1)])).is_equal(["1.000,2.000,1.000"])
	# Collinear: only the end points, or every point with include_collinear.
	var line := [Vector3(0, 0, 0), Vector3(2, 0, 2), Vector3(1, 0, 1), Vector3(3, 0, 3)]
	assert_array(_hull(line)).is_equal(["0.000,0.000,0.000", "3.000,0.000,3.000"])
	assert_int(_hull(line, true).size()).is_equal(4)

func test_hull_square_with_edge_and_inner_points() -> void:
	var pts := [Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 2), Vector3(0, 0, 2),
		Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(2, 0, 1), Vector3(1, 0, 2)]
	assert_int(_hull(pts).size()).is_equal(4)
	assert_int(_hull(pts, true).size()).is_equal(8)

func test_hull_far_from_origin() -> void:
	var o := Vector3(100000, 0, -100000)
	var pts := [o, o + Vector3(8, 0, 0), o + Vector3(8, 0, 8), o + Vector3(0, 0, 8), o + Vector3(4, 0, 4)]
	assert_int(_hull(pts).size()).is_equal(4)

# --- discard_points_on_irregular_surface -------------------------------------------------

func test_discard_is_reorder_invariant() -> void:
	var positions := []
	for x in range(5):
		for z in range(5):
			positions.append(Vector3(x, 0.3 if (x == 2 and z == 2) else 0.0, z))
	var d = H.points(positions)
	var sizes : PackedVector3Array = d.getContainerChecked("size", D.Vector)
	for i in range(sizes.size()):
		sizes[i] = Vector3(3, 1, 3)
	var s = DiscardPointsOnIrregularSurfaceNodeSettings.new()
	s.max_height_deviation = 0.05
	var a = H.exec(Discard, s, [d])
	var b = H.exec(Discard, s, [H.reversed(d)])
	assert_str(a.err).is_empty()
	assert_array(H.position_set(H.port(b, 0))).is_equal(H.position_set(H.port(a, 0)))
	assert_array(H.position_set(H.port(b, 1))).is_equal(H.position_set(H.port(a, 1)))

# --- runtime quality ---------------------------------------------------------------------

func test_unknown_quality_name_falls_back_to_the_project_setting() -> void:
	assert_int(QualityBranch.parse_level("Ultra")).is_equal(-1)
	assert_int(QualityBranch.parse_level("epic")).is_equal(3)
	assert_int(QualityBranch.parse_level(" HIGH ")).is_equal(2)
	assert_int(QualityBranch.parse_level(-3)).is_equal(0)
	assert_int(QualityBranch.parse_level(99)).is_equal(4)
	assert_int(QualityBranch.parse_level(sqrt(-1.0))).is_between(0, 4)
	var ctx = H.make_ctx(null, 0, {"quality": "Ultra"})
	var setting : int = ProjectSettings.get_setting("flow_nodes/quality_level", 0)
	assert_int(QualityBranch.quality_level(ctx)).is_equal(clampi(setting, 0, 4))

# --- create_points -----------------------------------------------------------------------

func test_create_points_local_without_owner_is_world_space() -> void:
	var e := FlowPointEntry.new()
	e.position = Vector3(1, 2, 3)
	e.rotation = Vector3(0, 45, 0)
	var s = CreatePointsNodeSettings.new()
	var entries : Array[FlowPointEntry] = [e]
	s.points = entries
	s.coordinate_space = CreatePointsNodeSettings.eCoordinateSpace.Local
	var r = H.exec(CreatePoints, s, [])
	assert_str(r.err).is_empty()
	var out = H.port(r)
	assert_vector(out.getVector3Container("position")[0]).is_equal(Vector3(1, 2, 3))
	assert_vector(out.getVector3Container("rotation")[0]).is_equal(Vector3(0, 45, 0))

# --- attribute_cast numeric limits ---------------------------------------------------------

func _cast(value, from_type: int, to_type: int, options := {}) -> Dictionary:
	return Ops.cast_value(value, from_type, to_type, options)

func test_cast_numeric_limits() -> void:
	var int64_max : int = 0x7fffffffffffffff
	var int64_min : int = -int64_max - 1
	assert_int(_cast(sqrt(-1.0), D.Double, D.Int64).value).is_equal(0)
	assert_int(_cast(INF, D.Double, D.Int64).value).is_equal(int64_max)
	assert_int(_cast(-INF, D.Double, D.Int64).value).is_equal(int64_min)
	assert_int(_cast(1e30, D.Double, D.Int64).value).is_equal(int64_max)
	assert_int(_cast(-2.7, D.Double, D.Int).value).is_equal(-2)
	assert_int(_cast(-2.5, D.Double, D.Int, {"float_to_int": Ops.eFloatToInt.Round}).value).is_equal(-3)
	assert_int(_cast(3000000000.0, D.Double, D.Int).value).is_equal(3000000000 - 4294967296)
	assert_int(_cast(3000000000.0, D.Double, D.Int, {"int_overflow": Ops.eIntOverflow.Clamp}).value).is_equal(2147483647)
	assert_int(_cast(-3000000000, D.Int64, D.Int, {"int_overflow": Ops.eIntOverflow.Clamp}).value).is_equal(-2147483648)
	assert_int(_cast(int64_min, D.Int64, D.Int).value).is_equal(0)
	assert_bool(_cast(sqrt(-1.0), D.Double, D.Bool).value).is_true()
	assert_int(_cast(" 42 ", D.String, D.Int).value).is_equal(42)
	assert_bool(_cast("4x", D.String, D.Int).ok).is_false()

func test_cast_node_retypes_in_place_and_keeps_other_streams() -> void:
	var d = AH.data({
		"id": [PackedInt32Array([1, 2, 3]), D.Int],
		"v": [PackedFloat64Array([1.9, -1.9, 2.5]), D.Double],
	})
	var s = CastSettings.new()
	s.input_attribute = "v"
	s.output_type = D.Int64
	var r = AH.exec(CastNode, s, [d])
	assert_str(r.err).is_empty()
	assert_int(AH.dtype(r.out, "v")).is_equal(D.Int64)
	assert_array(AH.values(r.out, "v")).is_equal([1, -1, 2])
	# The input Data is not modified.
	assert_int(AH.dtype(d, "v")).is_equal(D.Double)

# --- bitwise -------------------------------------------------------------------------------

func test_bitwise_shifts_and_negatives() -> void:
	var d = AH.data({"a": [PackedInt64Array([-8, 1, -1]), D.Int64]})
	var s = BitwiseSettings.new()
	s.in_nameA = "a"
	s.operation = BitwiseSettings.eOperation.ShiftRight
	s.constant_b = 1
	var r = AH.exec(BitwiseNode, s, [d])
	assert_array(AH.values(r.out, "bitwise")).is_equal([-4, 0, -1])
	s.operation = BitwiseSettings.eOperation.ShiftLeft
	s.constant_b = 63
	r = AH.exec(BitwiseNode, s, [d])
	var int64_min : int = -0x7fffffffffffffff - 1
	assert_array(AH.values(r.out, "bitwise")).is_equal([0, int64_min, int64_min])
	s.constant_b = 200
	r = AH.exec(BitwiseNode, s, [d])
	assert_array(AH.values(r.out, "bitwise")).is_equal([0, int64_min, int64_min])

# --- merge_attributes promotion order -------------------------------------------------------

func test_merge_promotion_is_order_independent() -> void:
	var a = AH.data({"x": [PackedInt64Array([1 << 40]), D.Int64]})
	var b = AH.data({"x": [PackedFloat32Array([0.5]), D.Float]})
	var c = AH.data({"x": [PackedInt32Array([3]), D.Int]})
	var r1 : Dictionary = MergeAttrs.merge_entries([a, b, c], MergeAttrsSettings.eMode.Append, true)
	var r2 : Dictionary = MergeAttrs.merge_entries([c, b, a], MergeAttrsSettings.eMode.Append, true)
	assert_bool(r1.ok).is_true()
	assert_int(AH.dtype(r1.data, "x")).is_equal(D.Double)
	assert_int(AH.dtype(r2.data, "x")).is_equal(D.Double)
	assert_array(AH.values(r1.data, "x")).is_equal([float(1 << 40), 0.5, 3.0])
	assert_array(AH.values(r2.data, "x")).is_equal([3.0, 0.5, float(1 << 40)])

func test_merge_by_index_broadcasts_single_entries() -> void:
	var a = AH.data({"x": [PackedInt32Array([1, 2, 3]), D.Int]})
	var b = AH.data({"y": [PackedStringArray(["k"]), D.String]})
	var r : Dictionary = MergeAttrs.merge_entries([a, b], MergeAttrsSettings.eMode.ByIndex, true)
	assert_bool(r.ok).is_true()
	assert_array(AH.values(r.data, "y")).is_equal(["k", "k", "k"])
