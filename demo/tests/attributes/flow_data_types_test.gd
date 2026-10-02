# flow_data_types_test.gd
# Walks EVERY FlowData.DataType value through the Data container API:
# newContainerOfType, writeValue, registerStream, filter (filteredStream),
# cloneStream, duplicate, merge-like append, emptyLike, per-data attributes
# and content_hash. A DataType added without a sample here fails
# test_every_data_type_has_a_sample, so the walk cannot silently skip a type.
class_name FlowDataTypesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

var _nodes : Array = []

func after_test() -> void:
	_free_nodes()

# Called at the end of every test that builds samples, so the Node3D values
# are gone before GdUnit's per-test orphan check.
func _free_nodes() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()

func _node(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	_nodes.append(n)
	return n

## Three distinct values per type, plus the container class newContainerOfType
## must return and the type _inferContainerType must report.
func _samples() -> Dictionary:
	var D = FlowDataScript.DataType
	var r1 := Resource.new()
	var r2 := Resource.new()
	var r3 := Resource.new()
	return {
		D.Bool: { "values": [true, false, true], "infer": D.Bool },
		D.Int: { "values": [1, -2, 3], "infer": D.Int },
		D.Float: { "values": [0.5, -1.25, 3.0], "infer": D.Float },
		D.Vector: { "values": [Vector3(1, 2, 3), Vector3(-1, 0, 4), Vector3(7, 8, 9)], "infer": D.Vector },
		D.String: { "values": ["a", "bb", "ccc"], "infer": D.String },
		D.Resource: { "values": [r1, r2, r3], "infer": D.Invalid },
		D.NodeMesh: { "values": [_node("m1"), _node("m2"), _node("m3")], "infer": D.Invalid },
		D.NodePath: { "values": [_node("p1"), _node("p2"), _node("p3")], "infer": D.Invalid },
		D.Color: { "values": [Color(1, 0, 0, 1), Color(0, 1, 0, 0.5), Color(0, 0, 1, 0.25)], "infer": D.Color },
		D.Quaternion: { "values": [Quaternion.IDENTITY, Quaternion(Vector3.UP, 0.5), Quaternion(Vector3.RIGHT, 1.0)], "infer": D.Quaternion },
		D.Vector2: { "values": [Vector2(1, 2), Vector2(-3, 4), Vector2(5, -6)], "infer": D.Vector2 },
		D.Vector4: { "values": [Vector4(1, 2, 3, 4), Vector4(-1, 0, 0, 1), Vector4(9, 8, 7, 6)], "infer": D.Quaternion },
		D.Transform: { "values": [Transform3D.IDENTITY, Transform3D(Basis(Vector3.UP, 0.3), Vector3(1, 2, 3)), Transform3D(Basis.from_scale(Vector3(2, 2, 2)), Vector3(-4, 0, 1))], "infer": D.Transform },
		D.Int64: { "values": [1 << 40, -(1 << 50) - 7, 3], "infer": D.Int64 },
		D.Double: { "values": [0.1 + 1e-12, -123456789.123456789, 1e300], "infer": D.Double },
	}

func _all_types() -> Array:
	var out := []
	for v in FlowDataScript.DataType.values():
		if v != FlowDataScript.DataType.Invalid:
			out.append(v)
	return out

func _label(t: int) -> String:
	return String(FlowDataScript.DataType.find_key(t))

func _stored(value, t: int):
	# What reading the container back gives for `value` written as `t`.
	if t == FlowDataScript.DataType.Bool:
		return 1 if value else 0
	if t == FlowDataScript.DataType.Quaternion:
		return FlowDataScript.quatToVec4(value)
	return value

func _filled(t: int, values: Array):
	var c = FlowDataScript.Data.newContainerOfType(t)
	c.resize(values.size())
	for i in range(values.size()):
		FlowDataScript.Data.writeValue(c, i, values[i], t)
	return c

func _assert_container(container, t: int, expected: Array, context: String) -> void:
	assert_bool(FlowDataScript.Data.containerMatchesType(container, t)).override_failure_message(
		"%s: container %s does not match %s" % [context, type_string(typeof(container)), _label(t)]).is_true()
	assert_int(container.size()).override_failure_message("%s: size" % context).is_equal(expected.size())
	for i in range(expected.size()):
		assert_bool(container[i] == _stored(expected[i], t)).override_failure_message(
			"%s: element %d of %s is %s, expected %s" % [context, i, _label(t), str(container[i]), str(expected[i])]).is_true()


func test_enum_values_are_stable() -> void:
	var D = FlowDataScript.DataType
	assert_int(D.Quaternion).is_equal(9)
	assert_int(D.Vector2).is_equal(10)
	assert_int(D.Vector4).is_equal(11)
	assert_int(D.Transform).is_equal(12)
	assert_int(D.Int64).is_equal(13)
	assert_int(D.Double).is_equal(14)
	assert_int(D.Invalid).is_equal(999)
	# keys()[value] is used by add_attribute's title/exposure: it must stay aligned.
	for t in _all_types():
		assert_str(D.keys()[t]).is_equal(_label(t))

func test_every_data_type_has_a_sample() -> void:
	var samples := _samples()
	for t in _all_types():
		assert_bool(samples.has(t)).override_failure_message("DataType %s has no sample in this walk" % _label(t)).is_true()
	_free_nodes()

func test_new_container_write_and_infer() -> void:
	var samples := _samples()
	for t in _all_types():
		var values : Array = samples[t].values
		var c = _filled(t, values)
		assert_object(c).override_failure_message("newContainerOfType(%s)" % _label(t)).is_not_null()
		_assert_container(c, t, values, "write")
		assert_int(FlowDataScript.Data._inferContainerType(FlowDataScript.Data.newContainerOfType(t))).override_failure_message(
			"infer %s" % _label(t)).is_equal(samples[t].infer)
	_free_nodes()

func test_register_filter_clone_duplicate_empty_like() -> void:
	var samples := _samples()
	for t in _all_types():
		var values : Array = samples[t].values
		var d := FlowDataScript.Data.new()
		var err = d.registerStream("attr", _filled(t, values), t)
		assert_that(err).override_failure_message("register %s: %s" % [_label(t), str(err)]).is_null()
		assert_int(d.findStream("attr").data_type).is_equal(t)

		# filter (filteredStream): reorder and drop
		var f := d.filter(PackedInt32Array([2, 0]))
		assert_int(f.findStream("attr").data_type).is_equal(t)
		_assert_container(f.findStream("attr").container, t, [values[2], values[0]], "filter " + _label(t))

		# filter keeps a broadcast (length-1) stream as is
		var b := FlowDataScript.Data.new()
		b.registerStream("many", _filled(FlowDataScript.DataType.Int, [1, 2, 3]), FlowDataScript.DataType.Int)
		b.registerStream("one", _filled(t, [values[1]]), t)
		_assert_container(b.filter(PackedInt32Array([0, 2])).findStream("one").container, t, [values[1]], "broadcast " + _label(t))

		# duplicate: equal content, independent storage
		var dup := d.duplicate()
		_assert_container(dup.findStream("attr").container, t, values, "duplicate " + _label(t))
		assert_int(dup.content_hash()).override_failure_message("duplicate hash %s" % _label(t)).is_equal(d.content_hash())
		FlowDataScript.Data.writeValue(dup.findStream("attr").container, 0, values[1], t)
		_assert_container(d.findStream("attr").container, t, values, "duplicate independence " + _label(t))
		assert_int(dup.content_hash()).override_failure_message("hash must change %s" % _label(t)).is_not_equal(d.content_hash())

		# cloneStream: a fresh container of the same type replaces the stream's
		var original = d.findStream("attr").container
		var cloned = d.cloneStream("attr")
		_assert_container(cloned, t, values, "clone " + _label(t))
		FlowDataScript.Data.writeValue(cloned, 0, values[1], t)
		_assert_container(original, t, values, "clone independence " + _label(t))

		# emptyLike: same schema, no rows
		var e := d.emptyLike()
		assert_int(e.findStream("attr").data_type).is_equal(t)
		_assert_container(e.findStream("attr").container, t, [], "emptyLike " + _label(t))
	_free_nodes()

func test_merge_like_append() -> void:
	# What merge / merge_attributes do: a fresh container of the stream's type
	# sized to the offset, then append_array of each input's container.
	var samples := _samples()
	for t in _all_types():
		var values : Array = samples[t].values
		var a = _filled(t, values)
		var b = _filled(t, [values[2]])
		var out = FlowDataScript.Data.newContainerOfType(t)
		out.append_array(a)
		out.append_array(b)
		_assert_container(out, t, values + [values[2]], "append " + _label(t))
		var d := FlowDataScript.Data.new()
		assert_that(d.registerStream("merged", out, t)).is_null()
	_free_nodes()

func test_per_data_attribute_round_trip() -> void:
	var samples := _samples()
	for t in _all_types():
		var value = samples[t].values[1]
		var d := FlowDataScript.Data.new()
		d.set_data_attr("v", value, t)
		var s = d.findStream("@data.v")
		assert_object(s).override_failure_message("@data %s" % _label(t)).is_not_null()
		assert_int(s.data_type).is_equal(t)
		_assert_container(s.container, t, [value], "@data " + _label(t))
	_free_nodes()

func test_extended_types_refuse_mismatched_containers() -> void:
	var D = FlowDataScript.DataType
	var cases := [
		[D.Vector2, PackedVector3Array([Vector3.ONE])],
		[D.Vector4, PackedColorArray([Color.RED])],
		[D.Transform, PackedFloat32Array([1.0])],
		[D.Transform, [1, 2]],
		[D.Int64, PackedInt32Array([1])],
		[D.Double, PackedFloat32Array([1.0])],
		# a new container type declared as an old type is refused too
		[D.Float, PackedFloat64Array([1.0])],
		[D.Int, PackedInt64Array([1])],
		[D.Vector, PackedVector2Array([Vector2.ONE])],
	]
	for c in cases:
		var d := FlowDataScript.Data.new()
		var err = d.registerStream("bad", c[1], c[0])
		assert_that(err).override_failure_message("%s with %s must be refused" % [_label(c[0]), type_string(typeof(c[1]))]).is_not_null()
		assert_bool(d.hasStream("bad")).is_false()

func test_vector4_must_be_explicit() -> void:
	var D = FlowDataScript.DataType
	var d := FlowDataScript.Data.new()
	d.registerStream("q", PackedVector4Array([Vector4(0, 0, 0, 1)]))
	assert_int(d.findStream("q").data_type).is_equal(D.Quaternion)
	d.registerStream("v4", PackedVector4Array([Vector4(1, 2, 3, 4)]), D.Vector4)
	assert_int(d.findStream("v4").data_type).is_equal(D.Vector4)

func test_untyped_transform_array_is_accepted_when_all_elements_are_transforms() -> void:
	var d := FlowDataScript.Data.new()
	assert_that(d.registerStream("xf", [Transform3D.IDENTITY], FlowDataScript.DataType.Transform)).is_null()

func test_precision_is_kept() -> void:
	var D = FlowDataScript.DataType
	var d := FlowDataScript.Data.new()
	d.registerStream("big", PackedInt64Array([1 << 40]), D.Int64)
	d.registerStream("dbl", PackedFloat64Array([0.1 + 1e-12]), D.Double)
	assert_int(d.first("big")).is_equal(1 << 40)
	assert_bool(d.first("dbl") == 0.1 + 1e-12).is_true()

func test_scalar_and_value_inference_for_new_types() -> void:
	var D = FlowDataScript.DataType
	assert_int(FlowDataScript.Data.scalar("uv", Vector2(1, 2)).findStream("uv").data_type).is_equal(D.Vector2)
	assert_int(FlowDataScript.Data.scalar("xf", Transform3D.IDENTITY).findStream("xf").data_type).is_equal(D.Transform)
	assert_int(FlowDataScript.Data.scalar("d", 1.5, D.Double).findStream("d").data_type).is_equal(D.Double)
	# Vector4 values still infer as Quaternion (unchanged).
	assert_int(FlowDataScript.Data.scalar("q", Vector4(0, 0, 0, 1)).findStream("q").data_type).is_equal(D.Quaternion)
	# Canonical numeric names accept the wide numeric types through scalar().
	assert_int(FlowDataScript.canonical_numeric_type("density", D.Double)).is_equal(D.Float)
	assert_int(FlowDataScript.canonical_numeric_type("seed", D.Int64)).is_equal(D.Int)

func test_component_access_on_vector2_and_vector4() -> void:
	var D = FlowDataScript.DataType
	var d := FlowDataScript.Data.new()
	d.registerStream("uv", PackedVector2Array([Vector2(1, 2), Vector2(3, 4)]), D.Vector2)
	d.registerStream("v4", PackedVector4Array([Vector4(1, 2, 3, 4), Vector4(5, 6, 7, 8)]), D.Vector4)
	assert_array(Array(d.findStream("uv.y").container)).is_equal([2.0, 4.0])
	assert_array(Array(d.findStream("v4.w").container)).is_equal([4.0, 8.0])
	assert_array(Array(d.findStream("v4.a").container)).is_equal([4.0, 8.0])
	assert_object(d.container("uv.z")).is_null()
	assert_that(d.registerStream("uv.x", PackedFloat32Array([9, 10]))).is_null()
	assert_array(Array(d.findStream("uv").container)).is_equal([Vector2(9, 2), Vector2(10, 4)])
	assert_that(d.registerStream("v4.w", PackedFloat32Array([0, 0]))).is_null()
	assert_float(d.findStream("v4").container[1].w).is_equal(0.0)
