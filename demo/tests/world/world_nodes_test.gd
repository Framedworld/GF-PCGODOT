# world_nodes_test.gd
# WP5: get_execution_bounds and cull_points_outside_bounds, inside and outside
# world generation, plus their traits rows.
class_name WorldNodesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const BoundsNode = preload("res://addons/flow_nodes_editor/nodes/get_execution_bounds.gd")
const BoundsSettings = preload("res://addons/flow_nodes_editor/nodes/get_execution_bounds_settings.gd")
const CullNode = preload("res://addons/flow_nodes_editor/nodes/cull_points_outside_bounds.gd")
const CullSettings = preload("res://addons/flow_nodes_editor/nodes/cull_points_outside_bounds_settings.gd")

const CELL := AABB(Vector3(0, -5, 0), Vector3(10, 10, 10))

func _cell_ctx(bounds : AABB = CELL) -> FlowData.EvaluationContext:
	var ctx := FlowNodeIO.make_context()
	ctx.bounds = bounds
	ctx.has_bounds = true
	ctx.grid_size = 16.0
	ctx.cell_coord = Vector2i(3, -2)
	ctx.hierarchy_level = 2
	return ctx

func _run(node : FlowNodeBase, ctx : FlowData.EvaluationContext, inputs : Array = []) -> FlowData.Data:
	node.preExecute(ctx)
	node.inputs = inputs
	node.execute(ctx)
	if node.generated_bulks.is_empty():
		return null
	return node.generated_bulks[0][0]

func _bounds_node(mode : int = 0) -> FlowNodeBase:
	var node : FlowNodeBase = BoundsNode.new()
	node.name = &"bounds"
	node.node_template = "get_execution_bounds"
	node.settings = BoundsSettings.new()
	node.settings.output_mode = mode
	return node

func _cull_node(use_point_bounds := false, margin := 0.0) -> FlowNodeBase:
	var node : FlowNodeBase = CullNode.new()
	node.name = &"cull"
	node.node_template = "cull_points_outside_bounds"
	node.settings = CullSettings.new()
	node.settings.use_point_bounds = use_point_bounds
	node.settings.margin = margin
	return node

func _points(positions : Array) -> FlowData.Data:
	var d := FlowData.Data.new()
	d.addCommonStreams(positions.size())
	var pos := d.getVector3Container(FlowData.AttrPosition)
	for i in range(positions.size()):
		pos[i] = positions[i]
	var ids := PackedInt32Array()
	for i in range(positions.size()):
		ids.append(i)
	d.registerStream("id", ids, FlowData.DataType.Int)
	return d

func _ids(data : FlowData.Data) -> Array:
	return Array(data.findStream("id").container)

# --- get_execution_bounds --------------------------------------------------------

func test_bounds_shape_inside_a_cell() -> void:
	var out := _run(_bounds_node(0), _cell_ctx())
	assert_bool(out.has_shape()).is_true()
	assert_int(out.size()).is_equal(0)
	assert_that(out.shape.get_bounds()).is_equal(CELL)
	assert_int(out.kind).is_equal(FlowData.Kind.Volume)
	assert_that(out.get_data_attr("bounds_min")).is_equal(CELL.position)
	assert_that(out.get_data_attr("bounds_max")).is_equal(CELL.end)
	assert_float(out.get_data_attr("grid_size")).is_equal(16.0)
	assert_int(out.get_data_attr("cell_x")).is_equal(3)
	assert_int(out.get_data_attr("cell_z")).is_equal(-2)
	assert_int(out.get_data_attr("hierarchy_level")).is_equal(2)
	assert_bool(out.get_data_attr("has_bounds")).is_true()

func test_bounds_points_mode() -> void:
	var out := _run(_bounds_node(1), _cell_ctx())
	assert_bool(out.has_shape()).is_false()
	assert_int(out.size()).is_equal(1)
	assert_that(out.getVector3Container(FlowData.AttrPosition)[0]).is_equal(CELL.get_center())
	assert_that(out.getVector3Container(FlowData.AttrSize)[0]).is_equal(CELL.size)
	var eb := out.getEffectiveBounds()
	assert_that(eb.min[0]).is_equal(-CELL.size * 0.5)
	assert_that(eb.max[0]).is_equal(CELL.size * 0.5)

func test_bounds_fallback_outside_world_generation() -> void:
	var node := _bounds_node(0)
	var fallback := AABB(Vector3(1, 2, 3), Vector3(4, 5, 6))
	node.settings.fallback_bounds = fallback
	var out := _run(node, FlowNodeIO.make_context())
	assert_that(out.shape.get_bounds()).is_equal(fallback)
	assert_bool(out.get_data_attr("has_bounds")).is_false()
	assert_float(out.get_data_attr("grid_size")).is_equal(0.0)

func test_bounds_runs_once_whatever_the_dependency_carries() -> void:
	var b = preload("res://tests/evaluator/support/test_graph.gd").new()
	b.node("marker", "grid_size", {"cell_size": 8.0}).node("bounds", "get_execution_bounds").node("out", "output", {"name": "r"})
	b.link("marker", 0, "bounds", 0).link("bounds", 0, "out", 0)
	var outputs := FlowNodeIO.evaluate(b.build())
	assert_bool(outputs["r"].has_shape()).is_true()
	assert_array(FlowNodeIO.last_errors).is_empty()

# --- cull_points_outside_bounds --------------------------------------------------------

func test_cull_is_a_pass_through_outside_world_generation() -> void:
	var data := _points([Vector3(-50, 0, 0), Vector3(5, 0, 5), Vector3(500, 0, 0)])
	var out := _run(_cull_node(), FlowNodeIO.make_context(), [data])
	assert_object(out).is_same(data)

func test_cull_keeps_points_inside_half_open() -> void:
	var data := _points([
		Vector3(0, 0, 0),		# 0 min corner: kept
		Vector3(10, 0, 5),		# 1 max x edge: culled
		Vector3(5, 0, 10),		# 2 max z edge: culled
		Vector3(9.999, 5, 9.999),	# 3 inside, top Y edge: kept
		Vector3(5, 5.5, 5),		# 4 above: culled
		Vector3(-0.001, 0, 5),	# 5 just outside min: culled
		Vector3(3, -5, 7),		# 6 bottom Y edge: kept
	])
	var out := _run(_cull_node(), _cell_ctx(), [data])
	assert_array(_ids(out)).is_equal([0, 3, 6])
	assert_int(data.size()).is_equal(7)	# input untouched

func test_cull_neighbour_cells_partition_the_points() -> void:
	var data := _points([Vector3(10, 0, 5), Vector3(0, 0, 0), Vector3(20, 0, 9.99), Vector3(15, 0, 10)])
	var left := _run(_cull_node(), _cell_ctx(AABB(Vector3(0, -5, 0), Vector3(10, 10, 10))), [data])
	var right := _run(_cull_node(), _cell_ctx(AABB(Vector3(10, -5, 0), Vector3(10, 10, 10))), [data])
	assert_array(_ids(left)).is_equal([1])
	assert_array(_ids(right)).is_equal([0])

func test_cull_margin() -> void:
	var data := _points([Vector3(-1.5, 0, 5), Vector3(11.5, 0, 5), Vector3(5, 0, 5), Vector3(1.5, 0, 5)])
	assert_array(_ids(_run(_cull_node(false, 2.0), _cell_ctx(), [data]))).is_equal([0, 1, 2, 3])
	assert_array(_ids(_run(_cull_node(false, -2.0), _cell_ctx(), [data]))).is_equal([2])

func test_cull_with_point_bounds_keeps_straddling_points() -> void:
	var data := _points([Vector3(-0.4, 0, 5), Vector3(10.4, 0, 5), Vector3(-0.6, 0, 5), Vector3(5, 0, 5)])
	# Unit size: half extent 0.5.
	assert_array(_ids(_run(_cull_node(true), _cell_ctx(), [data]))).is_equal([0, 1, 3])
	# Explicit bounds streams win over size.
	var wide := data.duplicate()
	wide.setSymmetricBounds(PackedVector3Array([Vector3(2, 2, 2), Vector3(2, 2, 2), Vector3(2, 2, 2), Vector3(2, 2, 2)]))
	assert_array(_ids(_run(_cull_node(true), _cell_ctx(), [wide]))).is_equal([0, 1, 2, 3])

func test_cull_passes_shape_only_data_and_empty_points() -> void:
	var shaped := FlowData.Data.from_shape(FlowBoxVolume.from_aabb(AABB(Vector3(100, 0, 100), Vector3(1, 1, 1))))
	assert_object(_run(_cull_node(), _cell_ctx(), [shaped])).is_same(shaped)
	var empty := FlowData.Data.new()
	assert_object(_run(_cull_node(), _cell_ctx(), [empty])).is_same(empty)

func test_cull_reports_a_missing_input() -> void:
	var node := _cull_node()
	_run(node, _cell_ctx(), [null])
	assert_str(node.err).contains("not connected")

func test_traits_rows() -> void:
	assert_array(FlowNodeTraits.TABLE["get_execution_bounds"]).is_equal([false, false])
	assert_array(FlowNodeTraits.TABLE["cull_points_outside_bounds"]).is_equal([false, false])
	assert_array(FlowNodeTraits.TABLE["grid_size"]).is_equal([true, false])
