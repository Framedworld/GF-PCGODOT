# surface_sampler_test.gd
class_name SurfaceSamplerTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SurfaceSamplerNode = preload("res://addons/flow_nodes_editor/nodes/surface_sampler.gd")
const SurfaceSamplerSettings = preload("res://addons/flow_nodes_editor/nodes/surface_sampler_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _run(inputs: Array, settings) -> SurfaceSamplerNode:
	var node = SurfaceSamplerNode.new()
	node.name = "test_surface_sampler"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: SurfaceSamplerNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

# Build a minimal TRS FlowData with one region.
func _make_trs_input(center: Vector3, size: Vector3, euler: Vector3) -> FlowData.Data:
	var d = FlowDataScript.Data.new()
	d.registerStream(FlowDataScript.AttrPosition, PackedVector3Array([center]), FlowDataScript.DataType.Vector)
	d.registerStream(FlowDataScript.AttrRotation, PackedVector3Array([euler]), FlowDataScript.DataType.Vector)
	d.registerStream(FlowDataScript.AttrSize, PackedVector3Array([size]), FlowDataScript.DataType.Vector)
	return d

# Build a "node" stream input carrying the given MeshInstance3D objects.
# Caller owns the MeshInstance3Ds and must free them.
func _make_node_stream_input(meshes: Array) -> FlowData.Data:
	var d = FlowDataScript.Data.new()
	var container = []
	for m in meshes:
		container.append(m)
	d.registerStream("node", container, FlowDataScript.DataType.String)
	return d

# ---------------------------------------------------------------------------
# Error-path tests
# ---------------------------------------------------------------------------

func test_null_input_sets_error() -> void:
	var s = SurfaceSamplerSettings.new()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_empty_input_returns_empty_output() -> void:
	var in_data = FlowDataScript.Data.new()
	var s = SurfaceSamplerSettings.new()
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

func test_input_with_no_trs_and_no_node_stream_sets_error() -> void:
	# Data has a stream, but it is neither a TRS bundle nor a "node" stream.
	var d = FlowDataScript.Data.new()
	d.registerStream("something_else", PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	var s = SurfaceSamplerSettings.new()
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_node_stream_with_no_valid_mesh_instances_sets_error() -> void:
	# A "node" stream whose entries are not MeshInstance3D with a mesh → error.
	var d = FlowDataScript.Data.new()
	d.registerStream("node", [Node3D.new()], FlowDataScript.DataType.String)
	var s = SurfaceSamplerSettings.new()
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

# ---------------------------------------------------------------------------
# TRS path: point count
# ---------------------------------------------------------------------------

func test_trs_point_count_equals_num_points() -> void:
	var s = SurfaceSamplerSettings.new()
	s.num_points = 7
	s.point_size = Vector3.ONE
	var in_data = _make_trs_input(Vector3.ZERO, Vector3(10.0, 10.0, 10.0), Vector3.ZERO)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(7)
	node.free()

func test_trs_two_regions_doubles_point_count() -> void:
	# Two input regions × num_points = 2 × num_points output points.
	var s = SurfaceSamplerSettings.new()
	s.num_points = 5
	s.point_size = Vector3.ONE
	var d = FlowDataScript.Data.new()
	d.registerStream(FlowDataScript.AttrPosition,
		PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)]),
		FlowDataScript.DataType.Vector)
	d.registerStream(FlowDataScript.AttrRotation,
		PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
		FlowDataScript.DataType.Vector)
	d.registerStream(FlowDataScript.AttrSize,
		PackedVector3Array([Vector3(2, 2, 2), Vector3(2, 2, 2)]),
		FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(10)
	node.free()

# ---------------------------------------------------------------------------
# TRS path: stream presence
# ---------------------------------------------------------------------------

func test_trs_output_has_position_rotation_size_streams() -> void:
	var s = SurfaceSamplerSettings.new()
	s.num_points = 3
	var in_data = _make_trs_input(Vector3.ZERO, Vector3(4.0, 4.0, 4.0), Vector3.ZERO)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrPosition)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrRotation)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrSize)).is_not_null()
	node.free()

func test_trs_output_has_density_and_seed_streams() -> void:
	var s = SurfaceSamplerSettings.new()
	s.num_points = 4
	var in_data = _make_trs_input(Vector3.ZERO, Vector3(4.0, 4.0, 4.0), Vector3.ZERO)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrDensity)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrSeed)).is_not_null()
	node.free()

# ---------------------------------------------------------------------------
# TRS path: density values are always 1.0
# ---------------------------------------------------------------------------

func test_trs_density_stream_all_ones() -> void:
	var s = SurfaceSamplerSettings.new()
	s.num_points = 5
	var in_data = _make_trs_input(Vector3.ZERO, Vector3(6.0, 6.0, 6.0), Vector3.ZERO)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var density_stream = out.findStream(FlowDataScript.AttrDensity)
	assert_object(density_stream).is_not_null()
	var density = density_stream.container
	assert_int(density.size()).is_equal(5)
	for i in range(density.size()):
		assert_float(density[i]).is_equal_approx(1.0, 0.001)
	node.free()

# ---------------------------------------------------------------------------
# TRS path: point_size is written to the size stream
# ---------------------------------------------------------------------------

func test_trs_point_size_written_to_size_stream() -> void:
	var s = SurfaceSamplerSettings.new()
	s.num_points = 3
	s.point_size = Vector3(2.0, 3.0, 4.0)
	var in_data = _make_trs_input(Vector3.ZERO, Vector3(10.0, 10.0, 10.0), Vector3.ZERO)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var size_stream = out.findStream(FlowDataScript.AttrSize)
	assert_object(size_stream).is_not_null()
	var sizes = size_stream.container
	assert_int(sizes.size()).is_equal(3)
	for i in range(sizes.size()):
		assert_bool(sizes[i].is_equal_approx(Vector3(2.0, 3.0, 4.0))).is_true()
	node.free()

# ---------------------------------------------------------------------------
# TRS path: rotation of region is propagated to output rotation stream
# ---------------------------------------------------------------------------

func test_trs_region_rotation_propagated() -> void:
	# All output rotation vectors for a region should equal its euler rotation.
	var region_euler = Vector3(0.1, 0.2, 0.3)
	var s = SurfaceSamplerSettings.new()
	s.num_points = 4
	var in_data = _make_trs_input(Vector3.ZERO, Vector3(4.0, 4.0, 4.0), region_euler)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	var rotations = rot_stream.container
	assert_int(rotations.size()).is_equal(4)
	for i in range(rotations.size()):
		assert_bool(rotations[i].is_equal_approx(region_euler)).is_true()
	node.free()

# ---------------------------------------------------------------------------
# TRS path: axis-aligned region — sampled points lie inside the AABB
# ---------------------------------------------------------------------------

func test_trs_points_inside_region_aabb() -> void:
	# Region centered at (10, 20, 30) with size (4, 6, 8), no rotation.
	# Every sampled position must lie within [center - size/2, center + size/2].
	var center = Vector3(10.0, 20.0, 30.0)
	var size = Vector3(4.0, 6.0, 8.0)
	var s = SurfaceSamplerSettings.new()
	s.num_points = 20
	s.random_seed = 42
	var in_data = _make_trs_input(center, size, Vector3.ZERO)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream(FlowDataScript.AttrPosition)
	assert_object(pos_stream).is_not_null()
	var positions = pos_stream.container
	assert_int(positions.size()).is_equal(20)
	var half = size * 0.5
	for i in range(positions.size()):
		var p = positions[i]
		var local = p - center
		assert_bool(local.x >= -half.x - 0.001 and local.x <= half.x + 0.001).is_true()
		assert_bool(local.y >= -half.y - 0.001 and local.y <= half.y + 0.001).is_true()
		assert_bool(local.z >= -half.z - 0.001 and local.z <= half.z + 0.001).is_true()
	node.free()

# ---------------------------------------------------------------------------
# TRS path: determinism — same seed produces identical results
# ---------------------------------------------------------------------------

func test_trs_same_seed_deterministic() -> void:
	var in_data = _make_trs_input(Vector3.ZERO, Vector3(10.0, 10.0, 10.0), Vector3.ZERO)
	var s1 = SurfaceSamplerSettings.new()
	s1.num_points = 8
	s1.random_seed = 99999
	var node1 = _run([in_data], s1)

	var in_data2 = _make_trs_input(Vector3.ZERO, Vector3(10.0, 10.0, 10.0), Vector3.ZERO)
	var s2 = SurfaceSamplerSettings.new()
	s2.num_points = 8
	s2.random_seed = 99999
	var node2 = _run([in_data2], s2)

	assert_str(node1.err).is_empty()
	assert_str(node2.err).is_empty()
	var pos1 = _output(node1).findStream(FlowDataScript.AttrPosition).container
	var pos2 = _output(node2).findStream(FlowDataScript.AttrPosition).container
	assert_int(pos1.size()).is_equal(pos2.size())
	for i in range(pos1.size()):
		assert_bool(pos1[i].is_equal_approx(pos2[i])).is_true()
	node1.free()
	node2.free()

# ---------------------------------------------------------------------------
# TRS path: different seeds produce different results
# ---------------------------------------------------------------------------

func test_trs_different_seeds_different_results() -> void:
	var in_data = _make_trs_input(Vector3.ZERO, Vector3(10.0, 10.0, 10.0), Vector3.ZERO)
	var s1 = SurfaceSamplerSettings.new()
	s1.num_points = 8
	s1.random_seed = 1

	var in_data2 = _make_trs_input(Vector3.ZERO, Vector3(10.0, 10.0, 10.0), Vector3.ZERO)
	var s2 = SurfaceSamplerSettings.new()
	s2.num_points = 8
	s2.random_seed = 999999

	var node1 = _run([in_data], s1)
	var node2 = _run([in_data2], s2)
	assert_str(node1.err).is_empty()
	assert_str(node2.err).is_empty()
	var pos1 = _output(node1).findStream(FlowDataScript.AttrPosition).container
	var pos2 = _output(node2).findStream(FlowDataScript.AttrPosition).container
	# At least one position must differ
	var any_differ = false
	for i in range(pos1.size()):
		if not pos1[i].is_equal_approx(pos2[i]):
			any_differ = true
			break
	assert_bool(any_differ).is_true()
	node1.free()
	node2.free()

# ---------------------------------------------------------------------------
# Node-stream path: MeshInstance3D objects supply regions via AABB
# ---------------------------------------------------------------------------

func test_node_stream_produces_correct_point_count() -> void:
	# One BoxMesh (1×1×1 default). With num_points=6 we expect 6 output points.
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var in_data = _make_node_stream_input([mi])
	var s = SurfaceSamplerSettings.new()
	s.num_points = 6
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(6)
	mi.free()
	node.free()

func test_node_stream_two_meshes_doubles_point_count() -> void:
	var mi1 = MeshInstance3D.new()
	mi1.mesh = BoxMesh.new()
	var mi2 = MeshInstance3D.new()
	mi2.mesh = BoxMesh.new()
	var in_data = _make_node_stream_input([mi1, mi2])
	var s = SurfaceSamplerSettings.new()
	s.num_points = 4
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(8)
	mi1.free()
	mi2.free()
	node.free()

func test_node_stream_skips_entry_without_mesh() -> void:
	# Entry without a mesh is skipped; only the one with a mesh generates points.
	var mi_valid = MeshInstance3D.new()
	mi_valid.mesh = BoxMesh.new()
	var mi_empty = MeshInstance3D.new()  # no mesh
	var in_data = _make_node_stream_input([mi_empty, mi_valid])
	var s = SurfaceSamplerSettings.new()
	s.num_points = 3
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	# Only the valid mesh contributes: 1 × 3 = 3
	assert_int(positions.size()).is_equal(3)
	mi_valid.free()
	mi_empty.free()
	node.free()

func test_node_stream_has_density_and_seed_streams() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var in_data = _make_node_stream_input([mi])
	var s = SurfaceSamplerSettings.new()
	s.num_points = 4
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out.findStream(FlowDataScript.AttrDensity)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrSeed)).is_not_null()
	mi.free()
	node.free()

func test_node_stream_points_inside_default_box_mesh_aabb() -> void:
	# BoxMesh default size = (1,1,1), centered at origin, identity global_transform.
	# AABB center = (0,0,0), size = (1,1,1). Points must lie in [-0.5, 0.5]^3.
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()  # default 1×1×1 box
	var in_data = _make_node_stream_input([mi])
	var s = SurfaceSamplerSettings.new()
	s.num_points = 20
	s.random_seed = 7
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(20)
	for i in range(positions.size()):
		var p = positions[i]
		assert_bool(p.x >= -0.5 - 0.001 and p.x <= 0.5 + 0.001).is_true()
		assert_bool(p.y >= -0.5 - 0.001 and p.y <= 0.5 + 0.001).is_true()
		assert_bool(p.z >= -0.5 - 0.001 and p.z <= 0.5 + 0.001).is_true()
	mi.free()
	node.free()

func test_node_stream_non_mesh_instance_entries_skipped() -> void:
	# A plain Node3D cast to MeshInstance3D returns null → must be skipped without error.
	# We simulate this by putting a non-MeshInstance3D in the container.
	# (Node3D cannot be cast to MeshInstance3D; the code does "var mi := obj as MeshInstance3D"
	#  which evaluates to null for non-MI objects — they are skipped silently.)
	var n3d = Node3D.new()
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var in_data = _make_node_stream_input([n3d, mi])
	var s = SurfaceSamplerSettings.new()
	s.num_points = 3
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	# Only the valid MeshInstance3D contributes: 1 × 3 = 3
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(3)
	n3d.free()
	mi.free()
	node.free()
