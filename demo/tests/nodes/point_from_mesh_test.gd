# point_from_mesh_test.gd
class_name PointFromMeshTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PointFromMeshNode = preload("res://addons/flow_nodes_editor/nodes/point_from_mesh.gd")
const PointFromMeshSettings = preload("res://addons/flow_nodes_editor/nodes/point_from_mesh_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Build a FlowData.Data containing a NodeMesh stream from the given nodes.
func _make_node_mesh_data(nodes: Array, stream_name: String = "node") -> FlowData.Data:
	var d := FlowData.Data.new()
	d.registerStream(stream_name, nodes, FlowData.DataType.NodeMesh)
	return d

# Run the node with inputs[0] = in_data, return the node (caller must free).
func _run(in_data, settings) -> PointFromMeshNode:
	var node = PointFromMeshNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

# Extract the first output Data (or null).
func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

# Create a MeshInstance3D with a BoxMesh of given size (default 1,1,1).
# Caller is responsible for freeing if not parented.
func _box_mesh_instance(size: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	return mi

# ---------------------------------------------------------------------------
# Error-path tests
# ---------------------------------------------------------------------------

func test_null_input_sets_error() -> void:
	var s = PointFromMeshSettings.new()
	var node = _run(null, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_node_mesh_stream_sets_error() -> void:
	# Input data has no NodeMesh stream at all
	var s = PointFromMeshSettings.new()
	s.source_stream_name = "node"
	var d := FlowData.Data.new()
	d.registerStream("positions", PackedVector3Array([Vector3.ZERO]), FlowData.DataType.Vector)
	var node = _run(d, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_custom_stream_name_falls_back_to_node_stream_or_errors() -> void:
	# A non-existent custom stream name with no "node" fallback -> error
	var s = PointFromMeshSettings.new()
	s.source_stream_name = "nonexistent_stream"
	# Register a NodeMesh stream under a different name than "node"
	var mi = _box_mesh_instance()
	add_child(mi)
	var d := FlowData.Data.new()
	var arr: Array = [mi]
	d.registerStream("other", arr, FlowData.DataType.NodeMesh)
	var node = _run(d, s)
	# source_stream_name = "nonexistent_stream" -> not found; fallback to "node" -> also not found -> error
	assert_str(node.err).is_not_empty()
	mi.free()
	node.free()

func test_all_non_mesh_instance_nodes_emits_empty_output_no_error() -> void:
	# Nodes that are not MeshInstance3D should be skipped; output is empty but no hard error
	var s = PointFromMeshSettings.new()
	var plain = Node3D.new()
	add_child(plain)
	var arr: Array = [plain]
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	# node stream only added when out_nodes.size() > 0; output still has position/rotation/size streams
	assert_object(out).is_not_null()
	var node_stream = out.findStream("node")
	# no nodes were emitted so the stream should not exist
	assert_object(node_stream).is_null()
	plain.free()
	node.free()

func test_mesh_instance_without_mesh_is_skipped() -> void:
	# MeshInstance3D with no mesh assigned should be skipped (num_skipped incremented)
	var s = PointFromMeshSettings.new()
	var mi = MeshInstance3D.new()  # no mesh
	add_child(mi)
	var arr: Array = [mi]
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var node_stream = out.findStream("node")
	assert_object(node_stream).is_null()
	mi.free()
	node.free()

# ---------------------------------------------------------------------------
# Core value tests
# ---------------------------------------------------------------------------

func test_single_box_mesh_produces_one_point() -> void:
	var s = PointFromMeshSettings.new()
	var mi = _box_mesh_instance()
	add_child(mi)
	var arr: Array = [mi]
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)
	mi.free()
	node.free()

func test_multiple_box_meshes_produce_correct_count() -> void:
	# Three mesh instances -> three output points
	var s = PointFromMeshSettings.new()
	var arr: Array = []
	var mis: Array = []
	for i in range(3):
		var mi = _box_mesh_instance()
		add_child(mi)
		arr.append(mi)
		mis.append(mi)
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream("position")
	assert_int(pos_stream.container.size()).is_equal(3)
	var node_stream = out.findStream("node")
	assert_int(node_stream.container.size()).is_equal(3)
	for mi in mis:
		mi.free()
	node.free()

func test_position_is_mesh_aabb_center_at_identity_transform() -> void:
	# BoxMesh default size=(1,1,1): aabb.position=(-0.5,-0.5,-0.5), aabb.size=(1,1,1)
	# center_local = aabb.position + aabb.size*0.5 = (0,0,0)
	# global_transform = Identity (node not in scene tree)
	# expected position = Identity * (0,0,0) = (0,0,0)
	var s = PointFromMeshSettings.new()
	var mi = _box_mesh_instance(Vector3.ONE)
	add_child(mi)
	var arr: Array = [mi]
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream("position")
	var pos_container : PackedVector3Array = pos_stream.container
	var expected_pos := Vector3.ZERO
	assert_bool(pos_container[0].is_equal_approx(expected_pos)).is_true()
	mi.free()
	node.free()

func test_size_equals_aabb_size_with_identity_scale() -> void:
	# BoxMesh size=(2,3,4) -> aabb.size=(2,3,4)
	# Identity basis scale = (1,1,1) -> world_size = (2,3,4) * (1,1,1) = (2,3,4)
	var s = PointFromMeshSettings.new()
	s.use_world_scale_for_bounds = true
	var box_size := Vector3(2.0, 3.0, 4.0)
	var mi = _box_mesh_instance(box_size)
	add_child(mi)
	var arr: Array = [mi]
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var size_stream = out.findStream("size")
	assert_object(size_stream).is_not_null()
	var size_container : PackedVector3Array = size_stream.container
	var expected_size := Vector3(2.0, 3.0, 4.0)
	assert_bool(size_container[0].is_equal_approx(expected_size)).is_true()
	mi.free()
	node.free()

func test_size_without_world_scale() -> void:
	# use_world_scale_for_bounds = false -> world_size = aabb.size directly
	var s = PointFromMeshSettings.new()
	s.use_world_scale_for_bounds = false
	var box_size := Vector3(2.0, 3.0, 4.0)
	var mi = _box_mesh_instance(box_size)
	add_child(mi)
	var arr: Array = [mi]
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var size_stream = out.findStream("size")
	var size_container : PackedVector3Array = size_stream.container
	var expected_size := Vector3(2.0, 3.0, 4.0)
	assert_bool(size_container[0].is_equal_approx(expected_size)).is_true()
	mi.free()
	node.free()

func test_rotation_is_zero_for_identity_transform() -> void:
	# basisToEuler(Basis.IDENTITY) = Vector3(0,0,0) in degrees
	var s = PointFromMeshSettings.new()
	var mi = _box_mesh_instance()
	add_child(mi)
	var arr: Array = [mi]
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var rot_stream = out.findStream("rotation")
	assert_object(rot_stream).is_not_null()
	var rot_container : PackedVector3Array = rot_stream.container
	assert_bool(rot_container[0].is_equal_approx(Vector3.ZERO)).is_true()
	mi.free()
	node.free()

func test_node_stream_contains_original_mesh_instances() -> void:
	# The "node" output stream should contain the actual MeshInstance3D references
	var s = PointFromMeshSettings.new()
	var mi = _box_mesh_instance()
	add_child(mi)
	var arr: Array = [mi]
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var node_stream = out.findStream("node")
	assert_object(node_stream).is_not_null()
	assert_int(node_stream.container.size()).is_equal(1)
	assert_object(node_stream.container[0]).is_equal(mi)
	mi.free()
	node.free()

# ---------------------------------------------------------------------------
# Mesh attribute stream tests
# ---------------------------------------------------------------------------

func test_mesh_attribute_stream_registered_when_enabled() -> void:
	# include_mesh_attribute=true, mesh_attribute_name="mesh" -> output has "mesh" Resource stream
	var s = PointFromMeshSettings.new()
	s.include_mesh_attribute = true
	s.mesh_attribute_name = "mesh"
	var mi = _box_mesh_instance()
	add_child(mi)
	var arr: Array = [mi]
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var mesh_stream = out.findStream("mesh")
	assert_object(mesh_stream).is_not_null()
	assert_int(mesh_stream.container.size()).is_equal(1)
	assert_object(mesh_stream.container[0]).is_instanceof(BoxMesh)
	mi.free()
	node.free()

func test_mesh_attribute_stream_not_registered_when_disabled() -> void:
	# include_mesh_attribute=false -> no "mesh" stream in output
	var s = PointFromMeshSettings.new()
	s.include_mesh_attribute = false
	s.mesh_attribute_name = "mesh"
	var mi = _box_mesh_instance()
	add_child(mi)
	var arr: Array = [mi]
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var mesh_stream = out.findStream("mesh")
	assert_object(mesh_stream).is_null()
	mi.free()
	node.free()

func test_mesh_attribute_stream_not_registered_when_name_empty() -> void:
	# include_mesh_attribute=true but mesh_attribute_name="" -> no stream registered
	var s = PointFromMeshSettings.new()
	s.include_mesh_attribute = true
	s.mesh_attribute_name = ""
	var mi = _box_mesh_instance()
	add_child(mi)
	var arr: Array = [mi]
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	# No mesh attribute stream should be added (condition: mesh_attribute_name != "")
	var mesh_stream = out.findStream("mesh")
	assert_object(mesh_stream).is_null()
	mi.free()
	node.free()

# ---------------------------------------------------------------------------
# Custom source stream name tests
# ---------------------------------------------------------------------------

func test_custom_source_stream_name_is_used() -> void:
	# source_stream_name = "meshes" -> reads from "meshes" stream in input data
	var s = PointFromMeshSettings.new()
	s.source_stream_name = "meshes"
	var mi = _box_mesh_instance()
	add_child(mi)
	var arr: Array = [mi]
	var d = _make_node_mesh_data(arr, "meshes")
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream("position")
	assert_int(pos_stream.container.size()).is_equal(1)
	mi.free()
	node.free()

func test_blank_source_stream_name_defaults_to_node() -> void:
	# source_stream_name = "" -> stripped to "" -> defaults to "node"
	var s = PointFromMeshSettings.new()
	s.source_stream_name = "   "
	var mi = _box_mesh_instance()
	add_child(mi)
	var arr: Array = [mi]
	var d = _make_node_mesh_data(arr, "node")
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream("position")
	assert_int(pos_stream.container.size()).is_equal(1)
	mi.free()
	node.free()

func test_custom_stream_name_fallback_to_node_stream() -> void:
	# source_stream_name = "custom" not found, but "node" exists -> falls back to "node"
	var s = PointFromMeshSettings.new()
	s.source_stream_name = "custom"
	var mi = _box_mesh_instance()
	add_child(mi)
	var arr: Array = [mi]
	# Register under "node" only — the fallback path should find it
	var d = _make_node_mesh_data(arr, "node")
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream("position")
	assert_int(pos_stream.container.size()).is_equal(1)
	mi.free()
	node.free()

# ---------------------------------------------------------------------------
# Mixed valid/invalid node tests
# ---------------------------------------------------------------------------

func test_mixed_valid_and_skipped_nodes_only_valid_emitted() -> void:
	# 2 valid MeshInstance3D + 1 plain Node3D + 1 MeshInstance3D with no mesh
	var s = PointFromMeshSettings.new()
	var mi1 = _box_mesh_instance()
	var mi2 = _box_mesh_instance()
	var plain = Node3D.new()
	var empty_mi = MeshInstance3D.new()  # no mesh
	add_child(mi1)
	add_child(mi2)
	add_child(plain)
	add_child(empty_mi)
	var arr: Array = [mi1, plain, empty_mi, mi2]
	var d = _make_node_mesh_data(arr)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var node_stream = out.findStream("node")
	assert_object(node_stream).is_not_null()
	# Only mi1 and mi2 are valid
	assert_int(node_stream.container.size()).is_equal(2)
	mi1.free()
	mi2.free()
	plain.free()
	empty_mi.free()
	node.free()
