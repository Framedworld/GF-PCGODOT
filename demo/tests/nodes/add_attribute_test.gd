# add_attribute_test.gd
class_name AddAttributeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const AddAttributeNode = preload("res://addons/flow_nodes_editor/nodes/add_attribute.gd")
const AddAttributeSettings = preload("res://addons/flow_nodes_editor/nodes/add_attribute_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> AddAttributeNode:
	var node = AddAttributeNode.new()
	node.name = "test_add_attribute"
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

func test_add_float_attribute_no_input() -> void:
	var s = AddAttributeSettings.new()
	s.name = "density"
	s.data_type = FlowDataScript.DataType.Float
	s.cte_float = 3.14
	s.domain = AddAttributeSettings.eDomain.PerPoint
	var node = _run([null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0]).is_equal_approx(3.14, 0.001)

func test_add_float_attribute_with_input() -> void:
	var s = AddAttributeSettings.new()
	s.name = "weight"
	s.data_type = FlowDataScript.DataType.Float
	s.cte_float = 0.5
	s.domain = AddAttributeSettings.eDomain.PerPoint
	var in_data = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3(2,0,0)]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("weight")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	assert_float(stream.container[0]).is_equal_approx(0.5, 0.001)
	assert_float(stream.container[2]).is_equal_approx(0.5, 0.001)

func test_add_int_attribute() -> void:
	var s = AddAttributeSettings.new()
	s.name = "my_int"
	s.data_type = FlowDataScript.DataType.Int
	s.cte_int = 42
	s.domain = AddAttributeSettings.eDomain.PerPoint
	var in_data = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("my_int")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	assert_int(stream.container[0]).is_equal(42)
	assert_int(stream.container[1]).is_equal(42)

func test_add_vector_attribute() -> void:
	var s = AddAttributeSettings.new()
	s.name = "my_vec"
	s.data_type = FlowDataScript.DataType.Vector
	s.cte_vector = Vector3(1.0, 2.0, 3.0)
	s.domain = AddAttributeSettings.eDomain.PerPoint
	var in_data = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("my_vec")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	assert_bool(stream.container[0].is_equal_approx(Vector3(1.0, 2.0, 3.0))).is_true()

func test_add_color_attribute() -> void:
	var s = AddAttributeSettings.new()
	s.name = "tint"
	s.data_type = FlowDataScript.DataType.Color
	s.cte_color = Color(1.0, 0.0, 0.5, 1.0)
	s.domain = AddAttributeSettings.eDomain.PerPoint
	var in_data = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3(5,0,0)]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("tint")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	assert_bool(stream.container[0].is_equal_approx(Color(1.0, 0.0, 0.5, 1.0))).is_true()

func test_add_bool_attribute() -> void:
	var s = AddAttributeSettings.new()
	s.name = "active"
	s.data_type = FlowDataScript.DataType.Bool
	s.cte_bool = true
	s.domain = AddAttributeSettings.eDomain.PerPoint
	var in_data = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("active")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	assert_int(stream.container[0]).is_equal(1)

func test_per_data_domain_creates_single_entry() -> void:
	var s = AddAttributeSettings.new()
	s.name = "meta_val"
	s.data_type = FlowDataScript.DataType.Float
	s.cte_float = 99.0
	s.domain = AddAttributeSettings.eDomain.PerData
	var in_data = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3(2,0,0)]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var target_name = FlowDataScript.DataAttrPrefix + "meta_val"
	var stream = out.findStream(target_name)
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0]).is_equal_approx(99.0, 0.001)

func test_empty_attribute_name_produces_error() -> void:
	var s = AddAttributeSettings.new()
	s.name = ""
	s.data_type = FlowDataScript.DataType.Float
	s.cte_float = 1.0
	s.domain = AddAttributeSettings.eDomain.PerPoint
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_input_streams_are_preserved() -> void:
	var s = AddAttributeSettings.new()
	s.name = "extra"
	s.data_type = FlowDataScript.DataType.Int
	s.cte_int = 7
	s.domain = AddAttributeSettings.eDomain.PerPoint
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	in_data.registerStream("density", PackedFloat32Array([0.1, 0.9]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("position")).is_not_null()
	assert_object(out.findStream("density")).is_not_null()
	assert_object(out.findStream("extra")).is_not_null()

# ---------------------------------------------------------------------------
# Schema-row idiom: with nothing connected the node emits a 1-point Data that
# holds only the new attribute. Chaining Add Attribute nodes builds a one-row
# attribute set (a "schema row"). This is intentional; pin it.
# ---------------------------------------------------------------------------

func test_no_input_yields_single_row_schema_data() -> void:
	var s = AddAttributeSettings.new()
	s.name = "biome"
	s.data_type = FlowDataScript.DataType.String
	s.cte_string = "swamp"
	s.domain = AddAttributeSettings.eDomain.PerPoint
	var first = _run([null], s)
	var row = _output(first)
	assert_int(row.size()).is_equal(1)
	# Only the new attribute: no transform/common streams are invented.
	assert_array(row.streams.keys()).is_equal(["biome"])
	assert_array(Array(row.findStream("biome").container)).is_equal(["swamp"])

	# Chaining keeps it a single row with one more column.
	var s2 = AddAttributeSettings.new()
	s2.name = "tier"
	s2.data_type = FlowDataScript.DataType.Int
	s2.cte_int = 3
	s2.domain = AddAttributeSettings.eDomain.PerPoint
	var second = _run([row], s2)
	var chained = _output(second)
	assert_int(chained.size()).is_equal(1)
	assert_array(chained.streams.keys()).is_equal(["biome", "tier"])
	assert_array(Array(chained.findStream("tier").container)).is_equal([3])

func test_empty_input_stays_empty_not_schema_row() -> void:
	# Only a missing input produces the 1-row idiom; a connected but empty
	# input keeps zero points.
	var s = AddAttributeSettings.new()
	s.name = "tier"
	s.data_type = FlowDataScript.DataType.Int
	s.cte_int = 3
	s.domain = AddAttributeSettings.eDomain.PerPoint
	var empty := FlowDataScript.Data.new()
	empty.registerStream(FlowData.AttrPosition, PackedVector3Array(), FlowDataScript.DataType.Vector)
	var node = _run([empty], s)
	var out = _output(node)
	assert_int(out.size()).is_equal(0)
	assert_int(out.findStream("tier").container.size()).is_equal(0)
