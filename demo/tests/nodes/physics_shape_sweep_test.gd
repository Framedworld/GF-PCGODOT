# physics_shape_sweep_test.gd
class_name PhysicsShapeSweepTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PhysicsShapeSweepNode = preload("res://addons/flow_nodes_editor/nodes/physics_shape_sweep.gd")
const PhysicsShapeSweepSettings = preload("res://addons/flow_nodes_editor/nodes/physics_shape_sweep_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _default_settings() -> PhysicsShapeSweepSettings:
	var s = PhysicsShapeSweepSettings.new()
	s.shape_type = PhysicsShapeSweepSettings.eShapeType.Sphere
	s.radius = 0.25
	s.position_attribute = "position"
	s.direction_mode = PhysicsShapeSweepSettings.eDirectionMode.Constant
	s.direction = Vector3.DOWN
	s.distance = 20.0
	s.distance_attribute = ""
	s.out_hit_attribute = "sweep_hit"
	s.out_position_attribute = "sweep_pos"
	s.out_safe_fraction_attribute = "safe_frac"
	s.out_unsafe_fraction_attribute = "unsafe_frac"
	s.out_collider_attribute = ""
	return s

# Build a floor body, await physics, run the node against it.
# The floor is a 20x1x20 box with its top face at y = 0.5.
# Caller must free the returned node; owner_node is freed inside.
func _run_against_floor(in_data, settings) -> PhysicsShapeSweepNode:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)

	var floor_body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	col.shape = box
	floor_body.add_child(col)
	owner_node.add_child(floor_body)

	# Physics bodies only become queryable after the server ticks.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var node = PhysicsShapeSweepNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = owner_node
	node.preExecute(ctx)
	node.execute(ctx)

	owner_node.free()
	return node

# Run without any scene tree (owner is a detached FlowGraphNode3D).
func _run_no_scene(inputs: Array, settings) -> PhysicsShapeSweepNode:
	var node = PhysicsShapeSweepNode.new()
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

func _make_positions(pts: PackedVector3Array) -> FlowData.Data:
	var d = FlowDataScript.Data.new()
	d.registerStream("position", pts, FlowDataScript.DataType.Vector)
	return d

# ---------------------------------------------------------------------------
# Error-path tests (no physics world needed)
# ---------------------------------------------------------------------------

func test_null_input_sets_error() -> void:
	var s = _default_settings()
	var node = _run_no_scene([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_no_scene_root_sets_error() -> void:
	# A detached owner has no get_tree(), so _scene_root() returns null -> error.
	var s = _default_settings()
	var in_data = _make_positions(PackedVector3Array([Vector3(0, 5, 0)]))
	var node = _run_no_scene([in_data], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_position_stream_sets_error() -> void:
	# Input data has no "position" stream -> execute must set an error.
	var s = _default_settings()
	var d = FlowDataScript.Data.new()
	d.registerStream("color", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = await _run_against_floor(d, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_from_attribute_mode_missing_direction_attribute_sets_error() -> void:
	# direction_mode = FromAttribute, but the data has no "direction" stream.
	var s = _default_settings()
	s.direction_mode = PhysicsShapeSweepSettings.eDirectionMode.FromAttribute
	s.direction_attribute = "direction"
	var in_data = _make_positions(PackedVector3Array([Vector3(0, 5, 0)]))
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_from_attribute_mode_blank_direction_attribute_sets_error() -> void:
	# direction_mode = FromAttribute, direction_attribute is blank -> error.
	var s = _default_settings()
	s.direction_mode = PhysicsShapeSweepSettings.eDirectionMode.FromAttribute
	s.direction_attribute = ""
	var in_data = _make_positions(PackedVector3Array([Vector3(0, 5, 0)]))
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_wrong_type_direction_attribute_sets_error() -> void:
	# direction attribute exists but is Float, not Vector -> error.
	var s = _default_settings()
	s.direction_mode = PhysicsShapeSweepSettings.eDirectionMode.FromAttribute
	s.direction_attribute = "dir"
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3(0, 5, 0)]), FlowDataScript.DataType.Vector)
	d.registerStream("dir", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = await _run_against_floor(d, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_distance_attribute_wrong_type_sets_error() -> void:
	# distance_attribute must be Float or Int; String is not -> error.
	var s = _default_settings()
	s.distance_attribute = "dist_str"
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3(0, 5, 0)]), FlowDataScript.DataType.Vector)
	d.registerStream("dist_str", PackedStringArray(["bad"]), FlowDataScript.DataType.String)
	var node = await _run_against_floor(d, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_distance_attribute_missing_sets_error() -> void:
	# distance_attribute is named but the stream doesn't exist in the data.
	var s = _default_settings()
	s.distance_attribute = "dist"
	var in_data = _make_positions(PackedVector3Array([Vector3(0, 5, 0)]))
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_not_empty()
	node.free()

# ---------------------------------------------------------------------------
# Empty-input pass-through
# ---------------------------------------------------------------------------

func test_empty_input_passes_through() -> void:
	# size() == 0 -> node should duplicate and set output without error.
	var s = _default_settings()
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array(), FlowDataScript.DataType.Vector)
	var node = await _run_against_floor(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	node.free()

# ---------------------------------------------------------------------------
# Physics-SIM: sphere sweep hits a floor
# ---------------------------------------------------------------------------

func test_sphere_sweep_hits_floor() -> void:
	# Point at y=5, sweeping DOWN 20 units. Floor top face is at y=0.5.
	# Expected: hit=1, unsafe_frac < 1.0, safe_frac >= 0.0.
	var s = _default_settings()
	var in_data = _make_positions(PackedVector3Array([Vector3(0, 5, 0)]))
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var hit = out.findStream("sweep_hit")
	assert_object(hit).is_not_null()
	assert_int(hit.container[0]).is_equal(1)

	var unsafe = out.findStream("unsafe_frac")
	assert_object(unsafe).is_not_null()
	assert_bool(unsafe.container[0] < 1.0).is_true()

	var safe = out.findStream("safe_frac")
	assert_object(safe).is_not_null()
	assert_bool(safe.container[0] >= 0.0).is_true()
	assert_bool(safe.container[0] <= 1.0).is_true()

	node.free()

func test_sphere_sweep_misses_returns_no_hit() -> void:
	# Point far outside the 20x20 floor footprint -> no collision.
	var s = _default_settings()
	var in_data = _make_positions(PackedVector3Array([Vector3(1000, 5, 0)]))
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var hit = out.findStream("sweep_hit")
	assert_object(hit).is_not_null()
	assert_int(hit.container[0]).is_equal(0)

	# On a miss, unsafe_frac should be 1.0 (no collision).
	var unsafe = out.findStream("unsafe_frac")
	assert_object(unsafe).is_not_null()
	assert_float(unsafe.container[0]).is_equal_approx(1.0, 0.01)

	node.free()

func test_swept_position_lands_on_floor_surface() -> void:
	# Sphere radius 0.25 sweeping DOWN from y=5. Floor top face at y=0.5.
	# The shape stops when its surface first touches the floor, so the center
	# lands near y = 0.5 + 0.25 = 0.75. Allow tolerance for physics precision.
	var s = _default_settings()
	s.radius = 0.25
	var in_data = _make_positions(PackedVector3Array([Vector3(0, 5, 0)]))
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var sweep_pos = out.findStream("sweep_pos")
	assert_object(sweep_pos).is_not_null()
	# y should be above the floor surface (center of sphere cannot go below top of floor + radius)
	assert_bool(sweep_pos.container[0].y >= 0.4).is_true()
	# y should be well below the start (5.0) — the sweep definitely moved.
	assert_bool(sweep_pos.container[0].y < 4.9).is_true()

	node.free()

# ---------------------------------------------------------------------------
# Physics-SIM: box shape
# ---------------------------------------------------------------------------

func test_box_sweep_hits_floor() -> void:
	var s = _default_settings()
	s.shape_type = PhysicsShapeSweepSettings.eShapeType.Box
	s.half_extents = Vector3(0.25, 0.25, 0.25)
	s.use_point_size_for_shape = false
	var in_data = _make_positions(PackedVector3Array([Vector3(0, 5, 0)]))
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var hit = out.findStream("sweep_hit")
	assert_object(hit).is_not_null()
	assert_int(hit.container[0]).is_equal(1)

	node.free()

# ---------------------------------------------------------------------------
# Physics-SIM: FromAttribute direction
# ---------------------------------------------------------------------------

func test_from_attribute_direction_hits_floor() -> void:
	# Provide a direction attribute pointing DOWN — should still hit the floor.
	var s = _default_settings()
	s.direction_mode = PhysicsShapeSweepSettings.eDirectionMode.FromAttribute
	s.direction_attribute = "dir"
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3(0, 5, 0)]), FlowDataScript.DataType.Vector)
	d.registerStream("dir", PackedVector3Array([Vector3.DOWN]), FlowDataScript.DataType.Vector)
	var node = await _run_against_floor(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var hit = out.findStream("sweep_hit")
	assert_object(hit).is_not_null()
	assert_int(hit.container[0]).is_equal(1)

	node.free()

func test_from_attribute_direction_broadcast_single_value() -> void:
	# A single direction value broadcast across multiple points.
	var s = _default_settings()
	s.direction_mode = PhysicsShapeSweepSettings.eDirectionMode.FromAttribute
	s.direction_attribute = "dir"
	s.out_hit_attribute = "sweep_hit"
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([
		Vector3(0, 5, 0),
		Vector3(1, 5, 0),
	]), FlowDataScript.DataType.Vector)
	# Single direction value -> broadcasts to both points.
	d.registerStream("dir", PackedVector3Array([Vector3.DOWN]), FlowDataScript.DataType.Vector)
	var node = await _run_against_floor(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)

	var hit = out.findStream("sweep_hit")
	assert_object(hit).is_not_null()
	assert_int(hit.container[0]).is_equal(1)
	assert_int(hit.container[1]).is_equal(1)

	node.free()

# ---------------------------------------------------------------------------
# Physics-SIM: distance attribute
# ---------------------------------------------------------------------------

func test_distance_attribute_float_accepted() -> void:
	# distance_attribute with a Float stream should be accepted (no error).
	var s = _default_settings()
	s.distance_attribute = "dist"
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3(0, 5, 0)]), FlowDataScript.DataType.Vector)
	d.registerStream("dist", PackedFloat32Array([20.0]), FlowDataScript.DataType.Float)
	var node = await _run_against_floor(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	node.free()

func test_distance_attribute_zero_no_hit() -> void:
	# Distance = 0 means no motion -> sweep should not hit anything.
	var s = _default_settings()
	s.distance_attribute = "dist"
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3(0, 5, 0)]), FlowDataScript.DataType.Vector)
	d.registerStream("dist", PackedFloat32Array([0.0]), FlowDataScript.DataType.Float)
	var node = await _run_against_floor(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# With zero distance, no motion -> no hit expected.
	var hit = out.findStream("sweep_hit")
	assert_object(hit).is_not_null()
	assert_int(hit.container[0]).is_equal(0)
	node.free()

# ---------------------------------------------------------------------------
# Physics-SIM: multi-point sweep
# ---------------------------------------------------------------------------

func test_multi_point_sweep_output_size_matches_input() -> void:
	# All three points are above the floor and sweeping down — all should hit.
	var s = _default_settings()
	var pts = PackedVector3Array([
		Vector3(-3, 5, 0),
		Vector3(0, 5, 0),
		Vector3(3, 5, 0),
	])
	var in_data = _make_positions(pts)
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)

	var hit = out.findStream("sweep_hit")
	assert_object(hit).is_not_null()
	assert_int(hit.container.size()).is_equal(3)

	node.free()

# ---------------------------------------------------------------------------
# Output stream registration: blank attribute names suppress streams
# ---------------------------------------------------------------------------

func test_blank_out_attributes_suppressed() -> void:
	# When all output attribute names are blank, no streams are registered
	# (beyond whatever was already in the duplicated input).
	var s = _default_settings()
	s.out_hit_attribute = ""
	s.out_position_attribute = ""
	s.out_safe_fraction_attribute = ""
	s.out_unsafe_fraction_attribute = ""
	s.out_collider_attribute = ""
	var in_data = _make_positions(PackedVector3Array([Vector3(0, 5, 0)]))
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# The hit stream must NOT be present.
	assert_object(out.findStream("sweep_hit")).is_null()
	node.free()
