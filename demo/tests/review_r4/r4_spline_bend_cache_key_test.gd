# r4_spline_bend_cache_key_test.gd
# Review R4: FlowSplineBend.bent_mesh_cached keyed its cache by a 32-bit
# hash() of the key fields, so two different segments whose key arrays hashed
# alike shared one cache slot and the second segment got the FIRST segment's
# bent mesh (wrong geometry, silently). The key must compare the fields.
class_name R4SplineBendCacheKeyTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

func before_test() -> void:
	FlowSplineBend.clear_cache()

func after_test() -> void:
	FlowSplineBend.clear_cache()

func _curve() -> Curve3D:
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO)
	c.add_point(Vector3(0, 0, 400))
	return c

## Two segment start offsets whose old 32-bit cache keys are equal (birthday
## search over a fixed sequence, so deterministic), or [] when none was found.
func _colliding_offsets(mesh : Mesh, curve : Curve3D) -> Array:
	var o := FlowSplineBend.default_options()
	var mk := FlowSplineBend.mesh_key(mesh)
	var ch := FlowSplineBend.curve_hash(curve)
	var seen := {}
	for i in range(400000):
		var from := float(i) * 0.0009765625
		var key := hash([mk, ch, from, from + 1.0,
			int(o.forward_axis), int(o.tangent_mode), int(o.up_mode), o.scale_start, o.scale_end])
		if seen.has(key):
			return [seen[key], from]
		seen[key] = from
	return []

func test_segments_with_equal_key_hashes_get_their_own_mesh() -> void:
	var mesh := BoxMesh.new()
	# A saved-looking path makes the key independent of the instance id.
	mesh.resource_path = "res://tests/review_r4/r4_virtual_box.tres"
	var curve := _curve()
	var pair := _colliding_offsets(mesh, curve)
	if pair.is_empty():
		push_warning("no 32-bit key collision found in the search range; nothing to check")
		return
	var a : float = pair[0]
	var b : float = pair[1]
	assert_float(a).is_not_equal(b)
	var mesh_a := FlowSplineBend.bent_mesh_cached(mesh, curve, a, a + 1.0)
	var mesh_b := FlowSplineBend.bent_mesh_cached(mesh, curve, b, b + 1.0)
	assert_object(mesh_b).is_not_same(mesh_a)
	var expected := FlowSplineBend.bend_mesh(mesh, curve, b, b + 1.0)
	assert_object(mesh_b.get_aabb()).is_equal(expected.get_aabb())
	# Both stay cached under their own keys.
	assert_object(FlowSplineBend.bent_mesh_cached(mesh, curve, a, a + 1.0)).is_same(mesh_a)
	assert_object(FlowSplineBend.bent_mesh_cached(mesh, curve, b, b + 1.0)).is_same(mesh_b)
	assert_int(FlowSplineBend.cache_size()).is_equal(2)
