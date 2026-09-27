# sample_mesh_test.gd
class_name SampleMeshTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SampleMeshNode = preload("res://addons/flow_nodes_editor/nodes/sample_mesh.gd")
const SampleMeshSettings = preload("res://addons/flow_nodes_editor/nodes/sample_mesh_settings.gd")

func _run_sample_mesh(mi: MeshInstance3D, mode: int, custom_settings_cb: Callable = Callable()) -> SampleMeshNode:
	var node = SampleMeshNode.new()
	node.name = "sample_mesh_test_node"
	node.settings = SampleMeshSettings.new()
	node.settings.mode = mode
	
	if custom_settings_cb.is_valid():
		custom_settings_cb.call(node.settings)
	
	var in_data := FlowDataScript.Data.new()
	var nodes: Array[Node] = [mi]
	in_data.registerStream("node", nodes, FlowDataScript.DataType.NodeMesh)
	
	node.inputs = []
	node.inputs.resize(1)
	node.inputs[0] = in_data
	
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy_owner = FlowGraphNode3D.new()
	ctx.owner = dummy_owner
	
	node.preExecute(ctx)
	node.execute(ctx)
	
	dummy_owner.free()
	return node

func _get_output_data(node: SampleMeshNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_one_per_vertex() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)
	
	var node = _run_sample_mesh(mi, SampleMeshSettings.eMode.OnePerVertex)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	# Deduplicated BoxMesh vertices should be exactly 8 points (corners of cube)
	assert_int(positions.size()).is_equal(8)
	
	# Verify other streams exist
	assert_object(out.findStream(FlowDataScript.AttrNormal)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrRotation)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrSize)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrDensity)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrSeed)).is_not_null()
	
	node.free()
	remove_child(mi)
	mi.free()

func test_face_centers() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)
	
	var node = _run_sample_mesh(mi, SampleMeshSettings.eMode.FaceCenters)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	# 6 faces of BoxMesh * 2 triangles per face = 12 face center points
	assert_int(positions.size()).is_equal(12)
	
	node.free()
	remove_child(mi)
	mi.free()

func test_use_num_samples() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)
	
	var node = _run_sample_mesh(mi, SampleMeshSettings.eMode.UseNumSamples, func(s):
		s.num_samples = 15
	)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(15)
	
	node.free()
	remove_child(mi)
	mi.free()

func test_use_density() -> void:
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1, 1, 1) # Total area is 6.0
	mi.mesh = box
	add_child(mi)
	
	# Total points = round(total_area * density) = round(6.0 * 2.5) = 15
	var node = _run_sample_mesh(mi, SampleMeshSettings.eMode.UseDensity, func(s):
		s.density = 2.5
	)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(15)
	
	node.free()
	remove_child(mi)
	mi.free()

func test_discard_hard_edges() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)
	
	# Sample with discard_hard_edges = true
	# Box corners and edges are hard edges, so they should filter out points close to them
	var node = _run_sample_mesh(mi, SampleMeshSettings.eMode.UseNumSamples, func(s):
		s.num_samples = 50
		s.discard_hard_edges = true
		s.hard_edge_distance_threshold = 0.4
	)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	# With 50 initial samples, some should be discarded since the threshold is 0.4 on a 1x1x1 cube
	assert_bool(positions.size() < 50).is_true()
	
	node.free()
	remove_child(mi)
	mi.free()

# ---------------------------------------------------------------------------
# Face-normal orientation. Godot front faces are wound clockwise, so the face
# normal must be (c - a) x (b - a); the counter-clockwise formula points into
# the mesh (a table top would read as facing down, its underside as up).
# ---------------------------------------------------------------------------

## Rotation is built with the normal on the basis Z axis (basisFromNormal).
func _rotation_normal_axis(euler_deg: Vector3) -> Vector3:
	return FlowDataScript.eulerToBasis(euler_deg).z

func test_plane_mesh_area_weighted_normals_face_up() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = PlaneMesh.new() # faces +Y
	add_child(mi)
	var node = _run_sample_mesh(mi, SampleMeshSettings.eMode.UseNumSamples, func(s):
		s.num_samples = 16
	)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var normals = out.findStream(FlowDataScript.AttrNormal).container
	var rots = out.getVector3Container(FlowDataScript.AttrRotation)
	assert_int(normals.size()).is_equal(16)
	for i in range(normals.size()):
		assert_float(normals[i].y).is_greater(0.99)
		assert_float(_rotation_normal_axis(rots[i]).y).is_greater(0.99)
	node.free()
	remove_child(mi)
	mi.free()

func test_plane_mesh_face_center_normals_face_up() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = PlaneMesh.new()
	add_child(mi)
	var node = _run_sample_mesh(mi, SampleMeshSettings.eMode.FaceCenters)
	var out = _get_output_data(node)
	var normals = out.findStream(FlowDataScript.AttrNormal).container
	var rots = out.getVector3Container(FlowDataScript.AttrRotation)
	assert_int(normals.size()).is_equal(2)
	for i in range(normals.size()):
		assert_float(normals[i].y).is_greater(0.99)
		assert_float(_rotation_normal_axis(rots[i]).y).is_greater(0.99)
	node.free()
	remove_child(mi)
	mi.free()

func test_box_mesh_normals_point_outward() -> void:
	# Every sampled face normal on a centred box points away from its centre,
	# so top-face samples (y == +0.5) report normal.y > 0.
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)
	for mode in [SampleMeshSettings.eMode.UseNumSamples, SampleMeshSettings.eMode.FaceCenters]:
		var node = _run_sample_mesh(mi, mode, func(s):
			s.num_samples = 60
		)
		var out = _get_output_data(node)
		var positions = out.getVector3Container(FlowDataScript.AttrPosition)
		var normals = out.findStream(FlowDataScript.AttrNormal).container
		var top_count := 0
		for i in range(positions.size()):
			assert_float(normals[i].dot(positions[i])).is_greater(0.0)
			if is_equal_approx(positions[i].y, 0.5):
				top_count += 1
				assert_float(normals[i].y).is_greater(0.99)
		assert_int(top_count).is_greater(0)
		node.free()
	remove_child(mi)
	mi.free()

func test_hard_edges_coplanar_triangles_are_not_hard() -> void:
	# get_hard_edges compares face normals of adjacent triangles; the shared
	# diagonal of a flat quad must not be classified as hard with either
	# winding, and the top face's normal sign must be outward-consistent.
	var mi = MeshInstance3D.new()
	mi.mesh = PlaneMesh.new()
	add_child(mi)
	var edges = SampleMeshNode.get_hard_edges(mi, 45.0)
	# 4 boundary edges only; the diagonal is shared by two coplanar triangles.
	assert_int(edges.size()).is_equal(4)
	remove_child(mi)
	mi.free()

# ---------------------------------------------------------------------------
# Non-indexed surfaces. A surface built without an index buffer reports null at
# Mesh.ARRAY_INDEX; every sampling path must fall back to the implicit
# 0..N-1 triangle list instead of failing the typed PackedInt32Array assign.
# ---------------------------------------------------------------------------

## Unit quad on the XZ plane (facing +Y), two triangles, NO index buffer.
func _non_indexed_quad_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1),
		Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
	])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrs := []
	arrs.resize(Mesh.ARRAY_MAX)
	arrs[Mesh.ARRAY_VERTEX] = verts
	arrs[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
	return mesh

func test_non_indexed_surface_reports_null_index_buffer() -> void:
	# Guards the premise of the tests below.
	var mesh := _non_indexed_quad_mesh()
	assert_that(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]).is_null()

func test_non_indexed_surface_samples_in_every_mode() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = _non_indexed_quad_mesh()
	add_child(mi)
	var cases := [
		[SampleMeshSettings.eMode.OnePerVertex, 4],  # 6 verts, 4 unique
		[SampleMeshSettings.eMode.FaceCenters, 2],
		[SampleMeshSettings.eMode.UseNumSamples, 10],
		[SampleMeshSettings.eMode.UseDensity, 5],    # area 1.0 * density 5
	]
	for c in cases:
		var node = _run_sample_mesh(mi, c[0], func(s):
			s.num_samples = 10
			s.density = 5.0
		)
		assert_str(node.err).is_empty()
		var out = _get_output_data(node)
		assert_object(out).override_failure_message("mode %d produced no output" % c[0]).is_not_null()
		if out != null:
			var positions = out.getVector3Container(FlowDataScript.AttrPosition)
			assert_int(positions.size()).override_failure_message(
				"mode %d: expected %d points, got %d" % [c[0], c[1], positions.size()]).is_equal(c[1])
			var normals = out.findStream(FlowDataScript.AttrNormal).container
			for i in range(normals.size()):
				assert_float(normals[i].y).is_greater(0.99)
		node.free()
	remove_child(mi)
	mi.free()

func test_non_indexed_surface_hard_edges() -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = _non_indexed_quad_mesh()
	add_child(mi)
	# 4 boundary edges; the shared diagonal is coplanar.
	assert_int(SampleMeshNode.get_hard_edges(mi, 45.0).size()).is_equal(4)
	var node = _run_sample_mesh(mi, SampleMeshSettings.eMode.UseNumSamples, func(s):
		s.num_samples = 40
		s.discard_hard_edges = true
		s.hard_edge_distance_threshold = 0.1
	)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	if out != null:
		var positions = out.getVector3Container(FlowDataScript.AttrPosition)
		assert_int(positions.size()).is_greater(0)
		assert_int(positions.size()).is_less(40)
	node.free()
	remove_child(mi)
	mi.free()
