# mesh_sampler_test.gd
class_name MeshSamplerTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const MeshSamplerNode = preload("res://addons/flow_nodes_editor/nodes/mesh_sampler.gd")
const SampleMeshSettings = preload("res://addons/flow_nodes_editor/nodes/sample_mesh_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a node-mesh input from one MeshInstance3D.
func _make_mesh_input(mi: MeshInstance3D) -> FlowData.Data:
	var d = FlowDataScript.Data.new()
	var nodes: Array[Node] = [mi]
	d.registerStream("node", nodes, FlowDataScript.DataType.NodeMesh)
	return d

## Run the MeshSamplerNode and return it (caller must free).
## mi must already be parented somewhere so global_transform is valid.
func _run(mi: MeshInstance3D, settings) -> MeshSamplerNode:
	var node = MeshSamplerNode.new()
	node.name = "test_node"
	node.settings = settings
	var in_data = _make_mesh_input(mi)
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

## Extract the first output Data block.
func _output(node: MeshSamplerNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

# ---------------------------------------------------------------------------
# Error-path tests
# ---------------------------------------------------------------------------

## Null input (no mesh port connected) must set an error.
func test_null_input_sets_error() -> void:
	var s = SampleMeshSettings.new()
	var node = MeshSamplerNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = [null]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	assert_str(node.err).is_not_empty()
	node.free()

## UseNumSamples mode with null input also errors.
func test_use_num_samples_null_input_sets_error() -> void:
	var s = SampleMeshSettings.new()
	s.mode = SampleMeshSettings.eMode.UseNumSamples
	s.num_samples = 10
	var node = MeshSamplerNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = [null]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	assert_str(node.err).is_not_empty()
	node.free()

## OnePerVertex mode with null input errors.
func test_one_per_vertex_null_input_sets_error() -> void:
	var s = SampleMeshSettings.new()
	s.mode = SampleMeshSettings.eMode.OnePerVertex
	var node = MeshSamplerNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = [null]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	assert_str(node.err).is_not_empty()
	node.free()

# ---------------------------------------------------------------------------
# OnePerVertex — BoxMesh has exactly 8 unique corners
# ---------------------------------------------------------------------------
func test_one_per_vertex_produces_8_points_for_box() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)

	var s = SampleMeshSettings.new()
	s.mode = SampleMeshSettings.eMode.OnePerVertex
	var node = _run(mi, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	# Deduplicated BoxMesh has exactly 8 unique corner vertices.
	assert_int(positions.size()).is_equal(8)

	# All mandatory streams must be present.
	assert_object(out.findStream(FlowDataScript.AttrNormal)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrRotation)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrSize)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrDensity)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrSeed)).is_not_null()

	node.free()
	remove_child(mi)
	mi.free()

# ---------------------------------------------------------------------------
# FaceCenters — BoxMesh has 6 faces × 2 triangles = 12 face center points
# ---------------------------------------------------------------------------
func test_face_centers_produces_12_points_for_box() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)

	var s = SampleMeshSettings.new()
	s.mode = SampleMeshSettings.eMode.FaceCenters
	var node = _run(mi, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(12)

	# Face-center normals must all be unit-length (within tolerance).
	var normals = out.getVector3Container(FlowDataScript.AttrNormal)
	assert_int(normals.size()).is_equal(12)
	for i in range(normals.size()):
		var n: Vector3 = normals[i]
		assert_float(n.length()).is_equal_approx(1.0, 0.001)

	node.free()
	remove_child(mi)
	mi.free()

# ---------------------------------------------------------------------------
# UseNumSamples — must produce exactly the requested count
# ---------------------------------------------------------------------------
func test_use_num_samples_exact_count() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)

	var s = SampleMeshSettings.new()
	s.mode = SampleMeshSettings.eMode.UseNumSamples
	s.num_samples = 20
	var node = _run(mi, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(20)

	# All positional stream sizes must match.
	var normals = out.getVector3Container(FlowDataScript.AttrNormal)
	var rotations = out.getVector3Container(FlowDataScript.AttrRotation)
	assert_int(normals.size()).is_equal(20)
	assert_int(rotations.size()).is_equal(20)

	node.free()
	remove_child(mi)
	mi.free()

# ---------------------------------------------------------------------------
# UseDensity — total points = round(area * density)
# A 1×1×1 BoxMesh has surface area = 6.0; density=2.5 → round(15.0) = 15
# ---------------------------------------------------------------------------
func test_use_density_correct_point_count() -> void:
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	mi.mesh = box
	add_child(mi)

	var s = SampleMeshSettings.new()
	s.mode = SampleMeshSettings.eMode.UseDensity
	s.density = 2.5
	var node = _run(mi, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	# round(6.0 * 2.5) = 15
	assert_int(positions.size()).is_equal(15)

	node.free()
	remove_child(mi)
	mi.free()

# ---------------------------------------------------------------------------
# Density stream is always filled with 1.0
# ---------------------------------------------------------------------------
func test_density_stream_is_filled_with_ones() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)

	var s = SampleMeshSettings.new()
	s.mode = SampleMeshSettings.eMode.UseNumSamples
	s.num_samples = 5
	var node = _run(mi, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var density_stream = out.findStream(FlowDataScript.AttrDensity)
	assert_object(density_stream).is_not_null()
	var dc = density_stream.container
	assert_int(dc.size()).is_equal(5)
	for i in range(dc.size()):
		assert_float(float(dc[i])).is_equal_approx(1.0, 0.0001)

	node.free()
	remove_child(mi)
	mi.free()

# ---------------------------------------------------------------------------
# Size stream matches point_size setting
# ---------------------------------------------------------------------------
func test_size_stream_matches_point_size_setting() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)

	var s = SampleMeshSettings.new()
	s.mode = SampleMeshSettings.eMode.UseNumSamples
	s.num_samples = 4
	s.point_size = 3.0
	var node = _run(mi, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var size_stream = out.findStream(FlowDataScript.AttrSize)
	assert_object(size_stream).is_not_null()
	var sc = size_stream.container
	assert_int(sc.size()).is_equal(4)
	var expected_size = Vector3.ONE * 3.0
	for i in range(sc.size()):
		var v: Vector3 = sc[i]
		assert_bool(v.is_equal_approx(expected_size)).is_true()

	node.free()
	remove_child(mi)
	mi.free()

# ---------------------------------------------------------------------------
# discard_hard_edges removes some points from a box (all edges are hard)
# with a generous threshold against 50 UseNumSamples points
# ---------------------------------------------------------------------------
func test_discard_hard_edges_reduces_count() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)

	var s = SampleMeshSettings.new()
	s.mode = SampleMeshSettings.eMode.UseNumSamples
	s.num_samples = 50
	s.discard_hard_edges = true
	s.hard_edge_distance_threshold = 0.4
	var node = _run(mi, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	# Points near the hard edges of the box are discarded — fewer than 50.
	assert_bool(positions.size() < 50).is_true()

	node.free()
	remove_child(mi)
	mi.free()

# ---------------------------------------------------------------------------
# All output stream lengths are mutually consistent
# ---------------------------------------------------------------------------
func test_all_stream_lengths_consistent() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)

	var s = SampleMeshSettings.new()
	s.mode = SampleMeshSettings.eMode.UseNumSamples
	s.num_samples = 10
	var node = _run(mi, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	var rotations = out.getVector3Container(FlowDataScript.AttrRotation)
	var sizes = out.getVector3Container(FlowDataScript.AttrSize)
	var normals_stream = out.findStream(FlowDataScript.AttrNormal)
	var density_stream = out.findStream(FlowDataScript.AttrDensity)
	var seed_stream = out.findStream(FlowDataScript.AttrSeed)

	var n = positions.size()
	assert_int(rotations.size()).is_equal(n)
	assert_int(sizes.size()).is_equal(n)
	assert_int(normals_stream.container.size()).is_equal(n)
	assert_int(density_stream.container.size()).is_equal(n)
	assert_int(seed_stream.container.size()).is_equal(n)

	node.free()
	remove_child(mi)
	mi.free()
