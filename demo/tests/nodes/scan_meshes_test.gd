# scan_meshes_test.gd
class_name ScanMeshesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const ScanMeshesNode = preload("res://addons/flow_nodes_editor/nodes/scan_meshes.gd")
const ScanMeshesSettings = preload("res://addons/flow_nodes_editor/nodes/scan_meshes_settings.gd")

# An owner parented under this (non-Node3D) suite is its own scene root, so the
# node scans exactly the descendants we attach to it — fully deterministic.
func _make_owner_with_meshes(mesh_count: int, group: String = "") -> FlowGraphNode3D:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	for i in range(mesh_count):
		var mi = MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		owner_node.add_child(mi)
		if group != "":
			mi.add_to_group(group)
	return owner_node

func _run(owner_node, settings) -> ScanMeshesNode:
	var node = ScanMeshesNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = owner_node
	node.preExecute(ctx)
	node.execute(ctx)
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func test_collects_mesh_instances() -> void:
	var owner_node = _make_owner_with_meshes(3)
	var s = ScanMeshesSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var node_stream = out.findStream("node")
	var mesh_stream = out.findStream("mesh")
	assert_int(node_stream.container.size()).is_equal(3)
	assert_int(mesh_stream.container.size()).is_equal(3)
	for m in mesh_stream.container:
		assert_object(m).is_instanceof(BoxMesh)
	owner_node.free()
	node.free()

func test_skips_mesh_instances_without_mesh() -> void:
	var owner_node = _make_owner_with_meshes(2)
	# Add a MeshInstance3D with no mesh and a plain Node3D — both must be ignored
	var empty_mi = MeshInstance3D.new()
	owner_node.add_child(empty_mi)
	owner_node.add_child(Node3D.new())
	var s = ScanMeshesSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	assert_int(_output(node).findStream("node").container.size()).is_equal(2)
	owner_node.free()
	node.free()

func test_group_filter() -> void:
	var owner_node = _make_owner_with_meshes(2, "scan_group")
	# Two more meshes NOT in the group
	for i in range(2):
		var mi = MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		owner_node.add_child(mi)
	var s = ScanMeshesSettings.new()
	s.group_name = "scan_group"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	assert_int(_output(node).findStream("node").container.size()).is_equal(2)
	owner_node.free()
	node.free()

func test_non_recursive_only_direct_children() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	# One direct child mesh, one nested mesh under an intermediate node
	var direct = MeshInstance3D.new()
	direct.mesh = BoxMesh.new()
	owner_node.add_child(direct)
	var mid = Node3D.new()
	owner_node.add_child(mid)
	var nested = MeshInstance3D.new()
	nested.mesh = BoxMesh.new()
	mid.add_child(nested)
	var s = ScanMeshesSettings.new()
	s.recursive = false
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	assert_int(_output(node).findStream("node").container.size()).is_equal(1)
	owner_node.free()
	node.free()

func test_null_owner_no_crash() -> void:
	var s = ScanMeshesSettings.new()
	var node = ScanMeshesNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = null
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	assert_int(_output(node).findStream("node").container.size()).is_equal(0)
	node.free()
