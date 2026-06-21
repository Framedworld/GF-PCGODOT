# projection_test.gd
class_name ProjectionTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const ProjectionNode = preload("res://addons/flow_nodes_editor/nodes/projection.gd")
const ProjectionSettings = preload("res://addons/flow_nodes_editor/nodes/projection_settings.gd")

func _make_pos_data(positions: PackedVector3Array) -> FlowData.Data:
	var d = FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _make_settings(dir := Vector3(0, -1, 0), align := true, discard := false) -> ProjectionSettings:
	var s = ProjectionSettings.new()
	s.direction = dir
	s.align_to_normal = align
	s.discard_misses = discard
	s.collision_mask = 1
	s.ray_length = 1000.0
	return s

# Builds a live scene with a 20x1x20 static floor (top face at y=0.5),
# awaits two physics frames so the body registers, runs the node, returns it.
# The caller is responsible for calling node.free().
func _run_against_floor(in_data, settings) -> ProjectionNode:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)

	var floor_body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	col.shape = box
	floor_body.add_child(col)
	owner_node.add_child(floor_body)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var node = ProjectionNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = owner_node
	node.preExecute(ctx)
	node.execute(ctx)

	owner_node.free()
	return node

# Runs without any physics scene (no World3D) — used for error-path tests.
func _run_no_scene(inputs: Array, settings) -> ProjectionNode:
	var node = ProjectionNode.new()
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

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

# ---------------------------------------------------------------------------
# Error-path tests (no physics scene needed)
# ---------------------------------------------------------------------------

func test_null_input_sets_error() -> void:
	var s = _make_settings()
	var node = _run_no_scene([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_no_world_sets_error() -> void:
	# FlowGraphNode3D not added to the tree has no World3D.
	var s = _make_settings()
	var positions = PackedVector3Array([Vector3(0, 10, 0)])
	var in_data = _make_pos_data(positions)
	var node = _run_no_scene([in_data], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_position_stream_sets_error() -> void:
	# Input data has no position stream — node should error.
	var s = _make_settings()
	var d = FlowDataScript.Data.new()
	d.registerStream("color", PackedFloat32Array([1.0, 0.0, 0.0, 1.0]), FlowDataScript.DataType.Float)
	# Run against a live floor so World3D is valid and the error comes from the
	# missing stream check (not the missing world check).
	var node = await _run_against_floor(d, s)
	assert_str(node.err).is_not_empty()
	node.free()

# ---------------------------------------------------------------------------
# Physics-sim tests — require a live StaticBody3D in the scene
# ---------------------------------------------------------------------------

# A point 5 units above the floor should land on the floor's top face (y ≈ 0.5).
func test_hit_snaps_position_to_floor() -> void:
	var s = _make_settings(Vector3(0, -1, 0), false, false)
	var in_data = _make_pos_data(PackedVector3Array([Vector3(0, 5, 0)]))
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	# Hit position should be near the top face of the box (y = 0.5)
	assert_float(pos_stream.container[0].y).is_equal_approx(0.5, 0.05)
	node.free()

# The hit normal for a flat horizontal floor should point straight up.
func test_hit_writes_normal_stream() -> void:
	var s = _make_settings(Vector3(0, -1, 0), false, false)
	var in_data = _make_pos_data(PackedVector3Array([Vector3(0, 5, 0)]))
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var nrm_stream = out.findStream(FlowData.AttrNormal)
	assert_object(nrm_stream).is_not_null()
	var n = nrm_stream.container[0]
	# Normal of a flat floor hit from above is (0, 1, 0)
	assert_float(n.y).is_equal_approx(1.0, 0.05)
	assert_float(n.x).is_equal_approx(0.0, 0.05)
	assert_float(n.z).is_equal_approx(0.0, 0.05)
	node.free()

# A point outside the 20x20 floor footprint misses; position should be unchanged.
func test_miss_preserves_original_position() -> void:
	var s = _make_settings(Vector3(0, -1, 0), false, false)
	var original_pos = Vector3(1000, 5, 0)
	var in_data = _make_pos_data(PackedVector3Array([original_pos]))
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	# Miss: output position equals input position unchanged
	assert_float(pos_stream.container[0].x).is_equal_approx(original_pos.x, 0.01)
	assert_float(pos_stream.container[0].y).is_equal_approx(original_pos.y, 0.01)
	node.free()

# discard_misses=true: points that miss are removed from the output.
func test_discard_misses_removes_miss_points() -> void:
	var s = _make_settings(Vector3(0, -1, 0), false, true)
	# Two points: one hits the floor, one misses (far outside footprint)
	var positions = PackedVector3Array([Vector3(0, 5, 0), Vector3(1000, 5, 0)])
	var in_data = _make_pos_data(positions)
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# Only the hitting point should remain
	assert_int(out.size()).is_equal(1)
	node.free()

# discard_misses=false: both hit and miss points appear in output.
func test_keep_misses_preserves_all_points() -> void:
	var s = _make_settings(Vector3(0, -1, 0), false, false)
	var positions = PackedVector3Array([Vector3(0, 5, 0), Vector3(1000, 5, 0)])
	var in_data = _make_pos_data(positions)
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_int(out.size()).is_equal(2)
	node.free()

# align_to_normal=true: rotation stream should reflect the hit normal.
# For a flat floor the Y-axis of the aligned basis points up, meaning the
# rotation Euler's pitch and roll should both be near zero.
func test_align_to_normal_sets_rotation() -> void:
	var s = _make_settings(Vector3(0, -1, 0), true, false)
	var in_data = _make_pos_data(PackedVector3Array([Vector3(0, 5, 0)]))
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var rot_stream = out.findStream(FlowData.AttrRotation)
	assert_object(rot_stream).is_not_null()
	# Rotation stream exists and has one entry
	assert_int(rot_stream.container.size()).is_equal(1)
	node.free()

# Empty input (zero points) should produce no error and an empty output.
func test_empty_input_produces_no_error() -> void:
	var s = _make_settings()
	var in_data = _make_pos_data(PackedVector3Array())
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

# Output size matches input size when discard_misses is off, regardless of hits.
func test_output_size_matches_input_size_no_discard() -> void:
	var s = _make_settings(Vector3(0, -1, 0), false, false)
	var positions = PackedVector3Array([
		Vector3(0, 5, 0),      # hit
		Vector3(2, 5, 0),      # hit
		Vector3(1000, 5, 0),   # miss
	])
	var in_data = _make_pos_data(positions)
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	assert_int(_output(node).size()).is_equal(3)
	node.free()
