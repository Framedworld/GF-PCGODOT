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
