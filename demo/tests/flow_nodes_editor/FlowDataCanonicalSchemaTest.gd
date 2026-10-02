# FlowDataCanonicalSchemaTest.gd
# Data.registerStream refuses a canonical attribute (position, rotation, size,
# rotation_quat, density, seed, normal, bounds_min, bounds_max, steepness)
# registered with any type but its canonical one.
class_name FlowDataCanonicalSchemaTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

const T := FlowData.DataType


func _canonical_containers() -> Dictionary:
	return {
		"position": [PackedVector3Array([Vector3.ONE]), T.Vector],
		"rotation": [PackedVector3Array([Vector3(0, 90, 0)]), T.Vector],
		"size": [PackedVector3Array([Vector3.ONE]), T.Vector],
		"rotation_quat": [PackedVector4Array([Vector4(0, 0, 0, 1)]), T.Quaternion],
		"density": [PackedFloat32Array([0.5]), T.Float],
		"seed": [PackedInt32Array([7]), T.Int],
		"normal": [PackedVector3Array([Vector3.UP]), T.Vector],
		"bounds_min": [PackedVector3Array([-Vector3.ONE]), T.Vector],
		"bounds_max": [PackedVector3Array([Vector3.ONE]), T.Vector],
		"steepness": [PackedFloat32Array([1.0]), T.Float],
	}


func test_table_covers_every_canonical_attribute() -> void:
	var expected := {}
	for attr_name in _canonical_containers():
		expected[StringName(attr_name)] = _canonical_containers()[attr_name][1]
	assert_dict(FlowData.CANONICAL_ATTRIBUTE_TYPES).is_equal(expected)


func test_canonical_types_register() -> void:
	var d := FlowDataScript.Data.new()
	var entries := _canonical_containers()
	for attr_name in entries:
		assert_object(d.registerStream(attr_name, entries[attr_name][0], entries[attr_name][1])).is_null()
		assert_int(d.streams[attr_name].data_type).is_equal(entries[attr_name][1])


func test_canonical_types_register_when_inferred() -> void:
	var d := FlowDataScript.Data.new()
	var entries := _canonical_containers()
	for attr_name in entries:
		assert_object(d.registerStream(attr_name, entries[attr_name][0])).is_null()
		assert_int(d.streams[attr_name].data_type).is_equal(entries[attr_name][1])


func test_float_rotation_is_refused_and_keeps_the_existing_stream() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("rotation", PackedVector3Array([Vector3(0, 45, 0)]), T.Vector)
	var result = d.registerStream("rotation", PackedFloat32Array([180.0]), T.Float)
	assert_str(result).contains("'rotation'")
	assert_str(result).contains("must be Vector, not Float")
	assert_int(d.streams["rotation"].data_type).is_equal(T.Vector)
	assert_array(Array(d.streams["rotation"].container)).is_equal([Vector3(0, 45, 0)])


func test_wrong_types_are_refused_for_every_canonical_attribute() -> void:
	var wrong := {
		"position": PackedFloat32Array([1.0]),
		"rotation": PackedVector4Array([Vector4(0, 0, 0, 1)]),		# a quaternion is rotation_quat
		"size": PackedFloat32Array([1.0]),
		"rotation_quat": PackedVector3Array([Vector3.ZERO]),		# Euler belongs in rotation
		"density": PackedInt32Array([1]),
		"seed": PackedFloat32Array([3.0]),
		"normal": PackedFloat32Array([1.0]),
		"bounds_min": PackedColorArray([Color.RED]),
		"bounds_max": PackedStringArray(["x"]),
		"steepness": PackedByteArray([1]),
	}
	for attr_name in wrong:
		var d := FlowDataScript.Data.new()
		var result = d.registerStream(attr_name, wrong[attr_name])
		assert_str(str(result)).override_failure_message("'%s' accepted a wrong type" % attr_name).contains("registration refused")
		assert_bool(d.streams.has(attr_name)).is_false()


func test_explicit_wrong_type_on_right_container_is_refused() -> void:
	var d := FlowDataScript.Data.new()
	assert_str(str(d.registerStream("seed", PackedInt32Array([1]), T.Float))).contains("must be Int")
	assert_bool(d.streams.has("seed")).is_false()


func test_non_canonical_names_keep_overwrite_with_warning() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("my_attr", PackedFloat32Array([1.0]), T.Float)
	assert_object(d.registerStream("my_attr", PackedInt32Array([2]), T.Int)).is_null()
	assert_int(d.streams["my_attr"].data_type).is_equal(T.Int)


func test_sub_stream_and_data_attr_writes_are_unaffected() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), T.Vector)
	assert_object(d.registerStream("position.y", PackedFloat32Array([5.0, 6.0]), T.Float)).is_null()
	assert_array(Array(d.streams["position"].container)).is_equal([Vector3(0, 5, 0), Vector3(1, 6, 1)])
	assert_object(d.registerStream("@data.density", PackedInt32Array([3]), T.Int)).is_null()
	assert_int(d.get_data_attr("density")).is_equal(3)


func test_scalar_and_runtime_inputs_take_the_canonical_numeric_type() -> void:
	var density := FlowDataScript.Data.scalar("density", 1)
	assert_int(density.streams["density"].data_type).is_equal(T.Float)
	assert_float(density.first("density")).is_equal(1.0)
	var seed_data := FlowDataScript.Data.scalar("seed", 5.0)
	assert_int(seed_data.streams["seed"].data_type).is_equal(T.Int)
	assert_int(seed_data.first("seed")).is_equal(5)
	var wrapped = FlowNodeIO._coerce_input_data(2, "density")
	assert_int(wrapped.streams["density"].data_type).is_equal(T.Float)


func test_output_named_like_a_canonical_attribute_skips_mistyped_alias() -> void:
	# An output port named "density" fed Data whose main stream is a String: the
	# Data is still exposed, without a mistyped "density" alias.
	var src := FlowDataScript.Data.new()
	src.registerStream("label", PackedStringArray(["a", "b"]), T.String)
	var graph: FlowGraphResource = TestGraph.new() \
		.in_param("pts", T.String) \
		.node("in_pts", "input_pts", {"name": "pts", "data_type": T.String}) \
		.node("out", "output", {"name": "density"}) \
		.link("in_pts", 0, "out", 0) \
		.build()
	var outputs := FlowNodeIO.evaluate(graph, {"pts": src})
	var out: FlowData.Data = outputs["density"]
	assert_bool(out.streams.has("label")).is_true()
	assert_bool(out.streams.has("density")).is_false()
	assert_array(FlowNodeIO.last_errors).is_empty()
