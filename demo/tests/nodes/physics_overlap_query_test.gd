# physics_overlap_query_test.gd
class_name PhysicsOverlapQueryTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PhysicsOverlapQueryNode = preload("res://addons/flow_nodes_editor/nodes/physics_overlap_query.gd")
const PhysicsOverlapQuerySettings = preload("res://addons/flow_nodes_editor/nodes/physics_overlap_query_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_pos_data(positions: PackedVector3Array) -> FlowData.Data:
	var d = FlowDataScript.Data.new()
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	return d

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func _default_settings() -> PhysicsOverlapQuerySettings:
	var s = PhysicsOverlapQuerySettings.new()
	s.position_attribute = "position"
	s.shape_type = PhysicsOverlapQuerySettings.eShapeType.Sphere
	s.radius = 2.0
	s.use_point_size_for_shape = false
	s.collision_mask = 1
	s.collide_with_bodies = true
	s.collide_with_areas = false
	s.max_results = 8
	s.exclude_nodes_group = ""
	s.out_hit_attribute = "overlap_hit"
	s.out_count_attribute = "overlap_count"
	return s

# Adds a 20x1x20 static box floor (top face at y=0.5) as a child of owner_node
# so a sphere at y=0 will overlap it.
func _add_floor(owner_node: Node3D) -> StaticBody3D:
	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	col.shape = box
	# Centre of the box is at y=0, so top face is at y=0.5
	body.position = Vector3(0, 0, 0)
	body.add_child(col)
	owner_node.add_child(body)
	return body

# Build owner + floor, await two physics frames, run node, return it. Caller frees.
func _run_with_floor(in_data, settings) -> PhysicsOverlapQueryNode:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	_add_floor(owner_node)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var node = PhysicsOverlapQueryNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = owner_node
	node.preExecute(ctx)
	node.execute(ctx)

	owner_node.free()
	return node

# Synchronous helper for error-path tests that don't need a physics scene.
func _run_no_scene(inputs: Array, settings) -> PhysicsOverlapQueryNode:
	var node = PhysicsOverlapQueryNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

# ---------------------------------------------------------------------------
# Error-path tests (synchronous, no physics scene needed)
# ---------------------------------------------------------------------------

func test_null_input_sets_error() -> void:
	var s = _default_settings()
	var node = _run_no_scene([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_no_scene_root_sets_error() -> void:
	var s = _default_settings()
	var d = _make_pos_data(PackedVector3Array([Vector3.ZERO]))
	var node = PhysicsOverlapQueryNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = [d]
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = null
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_not_empty()
	node.free()

func test_non_node3d_owner_sets_error() -> void:
	# ctx.owner is typed FlowGraphNode3D (a Node3D); assigning a plain Node is invalid.
	# Leave owner as null so the node hits the "No scene root" error path instead.
	var s = _default_settings()
	var d = _make_pos_data(PackedVector3Array([Vector3.ZERO]))
	var node = PhysicsOverlapQueryNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = [d]
	var ctx = FlowDataScript.EvaluationContext.new()
	# ctx.owner typed as FlowGraphNode3D — cannot assign plain Node; leave null to trigger error
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_position_stream_sets_error() -> void:
	var s = _default_settings()
	s.position_attribute = "position"
	var d = FlowDataScript.Data.new()
	d.registerStream("other", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run_no_scene([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_wrong_stream_type_sets_error() -> void:
	# Register "position" as Float instead of Vector — should fail type check.
	var s = _default_settings()
	s.position_attribute = "position"
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run_no_scene([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_position_size_mismatch_sets_error() -> void:
	# in_data has 3 elements but the position stream has 2 — mismatch (not 1 either).
	var s = _default_settings()
	var d = FlowDataScript.Data.new()
	# Register a dummy int stream to make in_data.size() == 3
	d.registerStream("dummy_int", PackedInt32Array([0, 1, 2]), FlowDataScript.DataType.Int)
	# Then register position with 2 entries (not 3, not 1)
	d.registerStream("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	var node = _run_no_scene([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

# ---------------------------------------------------------------------------
# Empty input passthrough (synchronous with a valid Node3D owner in tree)
# ---------------------------------------------------------------------------

func test_empty_input_passthrough() -> void:
	# in_data has 0 points → node should duplicate and emit it with no error.
	var s = _default_settings()
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array(), FlowDataScript.DataType.Vector)

	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var node = PhysicsOverlapQueryNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = [d]
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = owner_node
	node.preExecute(ctx)
	node.execute(ctx)

	owner_node.free()

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

# ---------------------------------------------------------------------------
# Physics-sim tests (require two physics frames)
# ---------------------------------------------------------------------------

func test_sphere_hits_floor() -> void:
	# A sphere of radius 2.0 centred at y=0 sits inside the floor box (top at y=0.5).
	var s = _default_settings()
	s.shape_type = PhysicsOverlapQuerySettings.eShapeType.Sphere
	s.radius = 2.0
	var in_data = _make_pos_data(PackedVector3Array([Vector3(0, 0, 0)]))
	var node = await _run_with_floor(in_data, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var hit_stream = out.findStream("overlap_hit")
	assert_object(hit_stream).is_not_null()
	assert_int(int(hit_stream.container[0])).is_equal(1)

	var count_stream = out.findStream("overlap_count")
	assert_object(count_stream).is_not_null()
	assert_int(count_stream.container[0]).is_greater_equal(1)

	node.free()

func test_sphere_misses_far_away() -> void:
	# A sphere far from the floor should produce hit=0, count=0.
	var s = _default_settings()
	s.shape_type = PhysicsOverlapQuerySettings.eShapeType.Sphere
	s.radius = 0.1
	var in_data = _make_pos_data(PackedVector3Array([Vector3(0, 500, 0)]))
	var node = await _run_with_floor(in_data, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var hit_stream = out.findStream("overlap_hit")
	assert_object(hit_stream).is_not_null()
	assert_int(int(hit_stream.container[0])).is_equal(0)

	var count_stream = out.findStream("overlap_count")
	assert_object(count_stream).is_not_null()
	assert_int(count_stream.container[0]).is_equal(0)

	node.free()

func test_box_shape_hits_floor() -> void:
	# Box half-extents (1,1,1) → full size 2x2x2 centred at origin overlaps the floor.
	var s = _default_settings()
	s.shape_type = PhysicsOverlapQuerySettings.eShapeType.Box
	s.half_extents = Vector3(1, 1, 1)
	var in_data = _make_pos_data(PackedVector3Array([Vector3(0, 0, 0)]))
	var node = await _run_with_floor(in_data, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var hit_stream = out.findStream("overlap_hit")
	assert_object(hit_stream).is_not_null()
	assert_int(int(hit_stream.container[0])).is_equal(1)

	node.free()

func test_multi_point_mixed_hits() -> void:
	# Two points: one overlapping (y=0), one far away (y=500). Expect [1,0] hits.
	var s = _default_settings()
	s.radius = 2.0
	var in_data = _make_pos_data(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 500, 0)]))
	var node = await _run_with_floor(in_data, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)

	var hit_stream = out.findStream("overlap_hit")
	assert_object(hit_stream).is_not_null()
	assert_int(int(hit_stream.container[0])).is_equal(1)
	assert_int(int(hit_stream.container[1])).is_equal(0)

	var count_stream = out.findStream("overlap_count")
	assert_object(count_stream).is_not_null()
	assert_int(count_stream.container[0]).is_greater_equal(1)
	assert_int(count_stream.container[1]).is_equal(0)

	node.free()

func test_broadcast_single_position() -> void:
	# position stream has 1 entry but in_data has 2 points (via another stream).
	# The node broadcasts pos[0] across all points. This should succeed, not error.
	var s = _default_settings()
	s.radius = 2.0
	var d = FlowDataScript.Data.new()
	# Two-element dummy stream makes in_data.size() == 2
	d.registerStream("dummy_int", PackedInt32Array([0, 1]), FlowDataScript.DataType.Int)
	# Single position entry → broadcast
	d.registerStream("position", PackedVector3Array([Vector3(0, 0, 0)]), FlowDataScript.DataType.Vector)

	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	_add_floor(owner_node)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var node = PhysicsOverlapQueryNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = [d]
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = owner_node
	node.preExecute(ctx)
	node.execute(ctx)

	owner_node.free()

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)

	# Both points broadcast to (0,0,0) which overlaps the floor → both should hit.
	var hit_stream = out.findStream("overlap_hit")
	assert_object(hit_stream).is_not_null()
	assert_int(int(hit_stream.container[0])).is_equal(1)
	assert_int(int(hit_stream.container[1])).is_equal(1)

	node.free()

func test_blank_output_attribute_suppresses_stream() -> void:
	# When out_hit_attribute and out_count_attribute are blank, those streams must
	# not appear in the output data.
	var s = _default_settings()
	s.radius = 2.0
	s.out_hit_attribute = ""
	s.out_count_attribute = ""
	var in_data = _make_pos_data(PackedVector3Array([Vector3(0, 0, 0)]))
	var node = await _run_with_floor(in_data, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("overlap_hit")).is_null()
	assert_object(out.findStream("overlap_count")).is_null()

	node.free()

func test_output_preserves_input_streams() -> void:
	# The output data is a duplicate of in_data, so existing streams must survive.
	var s = _default_settings()
	s.radius = 2.0
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3(0, 0, 0)]), FlowDataScript.DataType.Vector)
	d.registerStream("my_color", PackedColorArray([Color.RED]), FlowDataScript.DataType.Color)
	var node = await _run_with_floor(d, s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var color_stream = out.findStream("my_color")
	assert_object(color_stream).is_not_null()

	node.free()
