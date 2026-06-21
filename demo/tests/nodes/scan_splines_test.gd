# scan_splines_test.gd
class_name ScanSplinesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const ScanSplinesNode = preload("res://addons/flow_nodes_editor/nodes/scan_splines.gd")
const ScanSplinesSettings = preload("res://addons/flow_nodes_editor/nodes/scan_splines_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_path3d(with_curve: bool) -> Path3D:
	var p = Path3D.new()
	if with_curve:
		var c = Curve3D.new()
		c.add_point(Vector3.ZERO)
		c.add_point(Vector3(0, 0, 1))
		p.curve = c
	return p

# Creates a FlowGraphNode3D owner added to this suite (owns the scene root)
# and populates it with the requested number of Path3D children, each with a
# real Curve3D so they pass the execute() curve-null filter.
func _make_owner_with_splines(count: int, group: String = "") -> FlowGraphNode3D:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	for i in range(count):
		var p = _make_path3d(true)
		owner_node.add_child(p)
		if group != "":
			p.add_to_group(group)
	return owner_node

func _run(owner_node, settings) -> ScanSplinesNode:
	var node = ScanSplinesNode.new()
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

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_null_owner_returns_empty_streams() -> void:
	var s = ScanSplinesSettings.new()
	var node = ScanSplinesNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = null
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var node_stream = out.findStream("node")
	assert_int(node_stream.container.size()).is_equal(0)
	node.free()

func test_collects_path3d_nodes_with_curves() -> void:
	var owner_node = _make_owner_with_splines(3)
	var s = ScanSplinesSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var node_stream = out.findStream("node")
	var curve_stream = out.findStream("curve")
	assert_int(node_stream.container.size()).is_equal(3)
	assert_int(curve_stream.container.size()).is_equal(3)
	for cv in curve_stream.container:
		assert_object(cv).is_instanceof(Curve3D)
	owner_node.free()
	node.free()

func test_node_and_curve_streams_stay_aligned() -> void:
	# node[i] must match curve[i] (same Path3D)
	var owner_node = _make_owner_with_splines(2)
	var s = ScanSplinesSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var node_stream = out.findStream("node")
	var curve_stream = out.findStream("curve")
	assert_int(node_stream.container.size()).is_equal(curve_stream.container.size())
	for i in range(node_stream.container.size()):
		var path_node = node_stream.container[i]
		var curve = curve_stream.container[i]
		assert_object(path_node).is_instanceof(Path3D)
		assert_object(curve).is_equal(path_node.curve)
	owner_node.free()
	node.free()

func test_skips_path3d_without_curve() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	# Two Path3D with curves, one without
	var p_with = _make_path3d(true)
	owner_node.add_child(p_with)
	var p_without = _make_path3d(false)
	owner_node.add_child(p_without)
	var p_with2 = _make_path3d(true)
	owner_node.add_child(p_with2)
	var s = ScanSplinesSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	# Only the two with curves should appear
	assert_int(out.findStream("node").container.size()).is_equal(2)
	assert_int(out.findStream("curve").container.size()).is_equal(2)
	owner_node.free()
	node.free()

func test_ignores_non_path3d_nodes() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	# A Path3D with a curve
	owner_node.add_child(_make_path3d(true))
	# Non-Path3D nodes that must be ignored
	owner_node.add_child(Node3D.new())
	owner_node.add_child(MeshInstance3D.new())
	var s = ScanSplinesSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	assert_int(_output(node).findStream("node").container.size()).is_equal(1)
	owner_node.free()
	node.free()

func test_group_filter_collects_only_grouped_nodes() -> void:
	var owner_node = _make_owner_with_splines(2, "spline_group")
	# Two more Path3D with curves NOT in the group
	owner_node.add_child(_make_path3d(true))
	owner_node.add_child(_make_path3d(true))
	var s = ScanSplinesSettings.new()
	s.group_name = "spline_group"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	assert_int(_output(node).findStream("node").container.size()).is_equal(2)
	owner_node.free()
	node.free()

func test_non_recursive_only_direct_children() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	# One direct child Path3D with a curve
	owner_node.add_child(_make_path3d(true))
	# A nested Path3D under an intermediate Node3D — must NOT be collected
	var mid = Node3D.new()
	owner_node.add_child(mid)
	mid.add_child(_make_path3d(true))
	var s = ScanSplinesSettings.new()
	s.recursive = false
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	assert_int(_output(node).findStream("node").container.size()).is_equal(1)
	owner_node.free()
	node.free()

func test_recursive_collects_nested_nodes() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	# Direct child
	owner_node.add_child(_make_path3d(true))
	# Nested under intermediate
	var mid = Node3D.new()
	owner_node.add_child(mid)
	mid.add_child(_make_path3d(true))
	var s = ScanSplinesSettings.new()
	s.recursive = true
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	assert_int(_output(node).findStream("node").container.size()).is_equal(2)
	owner_node.free()
	node.free()

func test_required_meta_bool_filters_nodes() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	# Path3D with the meta flag set to true
	var p_tagged = _make_path3d(true)
	p_tagged.set_meta("pcg_spline", true)
	owner_node.add_child(p_tagged)
	# Path3D without the meta flag — must be excluded
	owner_node.add_child(_make_path3d(true))
	var s = ScanSplinesSettings.new()
	s.required_meta_bool = &"pcg_spline"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	assert_int(_output(node).findStream("node").container.size()).is_equal(1)
	owner_node.free()
	node.free()

func test_required_meta_bool_false_excludes_node() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	# Path3D with meta set to false — must be excluded
	var p_false = _make_path3d(true)
	p_false.set_meta("pcg_spline", false)
	owner_node.add_child(p_false)
	var s = ScanSplinesSettings.new()
	s.required_meta_bool = &"pcg_spline"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	assert_int(_output(node).findStream("node").container.size()).is_equal(0)
	owner_node.free()
	node.free()

func test_empty_scene_produces_empty_output() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var s = ScanSplinesSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.findStream("node").container.size()).is_equal(0)
	assert_int(out.findStream("curve").container.size()).is_equal(0)
	owner_node.free()
	node.free()
