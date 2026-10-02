# bounds_from_mesh_test.gd
class_name BoundsFromMeshTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/bounds_from_mesh.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/bounds_from_mesh_settings.gd")

func _box(size : Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

func test_meta() -> void:
	var node = NodeScript.new()
	assert_array(node.meta_node.aliases).contains(["Bounds From Mesh"])
	H.dispose(node)

func test_settings_mesh_sets_bounds_for_every_point() -> void:
	var s = SettingsScript.new()
	s.mesh = _box(Vector3(2, 4, 6))
	var d = H.points([Vector3.ZERO, Vector3(5, 0, 0)])
	d.getVector3Container("size")[1] = Vector3(3, 3, 3)
	var r := H.exec(NodeScript, s, [d])
	assert_str(r.err).is_empty()
	var out = H.port(r, 0)
	for i in range(2):
		assert_vector(out.value_at("bounds_min", i)).is_equal(Vector3(-1, -2, -3))
		assert_vector(out.value_at("bounds_max", i)).is_equal(Vector3(1, 2, 3))
	assert_vector(out.value_at("size", 1)).is_equal(Vector3(3, 3, 3))

func test_per_point_mesh_attribute_with_fallback() -> void:
	var s = SettingsScript.new()
	s.mesh = _box(Vector3.ONE * 2)
	s.mesh_attribute = "mesh"
	var d = H.points([Vector3.ZERO, Vector3.ONE, Vector3(2, 0, 0)])
	var meshes : Array[Resource] = [_box(Vector3(4, 4, 4)), null, StandardMaterial3D.new()]
	d.registerStream("mesh", meshes, FlowDataScript.DataType.Resource)
	var out = H.port(H.exec(NodeScript, s, [d]), 0)
	assert_vector(out.value_at("bounds_max", 0)).is_equal(Vector3(2, 2, 2))
	assert_vector(out.value_at("bounds_max", 1)).is_equal(Vector3(1, 1, 1))
	assert_vector(out.value_at("bounds_max", 2)).is_equal(Vector3(1, 1, 1))

func test_points_without_mesh_keep_bounds() -> void:
	var s = SettingsScript.new()
	s.mesh_attribute = "mesh"
	var d = H.points([Vector3.ZERO])
	d.getVector3Container("size")[0] = Vector3(6, 6, 6)
	var meshes : Array[Resource] = [null]
	d.registerStream("mesh", meshes, FlowDataScript.DataType.Resource)
	var out = H.port(H.exec(NodeScript, s, [d]), 0)
	assert_vector(out.value_at("bounds_max", 0)).is_equal(Vector3(3, 3, 3))

func test_errors_and_empty() -> void:
	assert_str(H.exec(NodeScript, SettingsScript.new(), [H.points([Vector3.ZERO])]).err).contains("mesh")
	var s = SettingsScript.new()
	s.mesh_attribute = "nope"
	assert_str(H.exec(NodeScript, s, [H.points([Vector3.ZERO])]).err).contains("not found")
	var bad = SettingsScript.new()
	bad.mesh_attribute = "density"
	var d = H.points([Vector3.ZERO], {"density": PackedFloat32Array([1.0])})
	assert_str(H.exec(NodeScript, bad, [d]).err).contains("Resource")
	var ok = SettingsScript.new()
	ok.mesh = _box(Vector3.ONE)
	var r := H.exec(NodeScript, ok, [H.points([])])
	assert_str(r.err).is_empty()
	assert_int(H.port(r, 0).size()).is_equal(0)
	assert_str(H.exec(NodeScript, ok, [null]).err).contains("not connected")
