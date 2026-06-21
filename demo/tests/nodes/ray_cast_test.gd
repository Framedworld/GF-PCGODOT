# ray_cast_test.gd
class_name RayCastTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const RayCastNode = preload("res://addons/flow_nodes_editor/nodes/ray_cast.gd")
const RayCastSettings = preload("res://addons/flow_nodes_editor/nodes/ray_cast_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d = FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

# Builds a live owner with a 20x1x20 static floor centered at origin (top face at
# y=0.5), lets physics register it, runs the node, then returns it. Caller frees.
func _run_against_floor(in_data, settings) -> RayCastNode:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var floor_body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	col.shape = box
	floor_body.add_child(col)
	owner_node.add_child(floor_body)

	# Physics bodies only become queryable after the physics server ticks.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var node = RayCastNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = owner_node
	node.preExecute(ctx)
	node.execute(ctx)

	owner_node.free()
	return node

func _run_no_scene(inputs: Array, settings) -> RayCastNode:
	var node = RayCastNode.new()
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

func _settings() -> RayCastSettings:
	var s = RayCastSettings.new()
	s.dir = Vector3.DOWN
	s.max_distance = 100.0
	s.from_attribute = "position"
	s.out_result_attribute = "hit"
	s.out_position_attribute = "position"
	s.out_distance_attribute = "dist"
	return s

func test_ray_hits_floor() -> void:
	var s = _settings()
	var in_data = _make_data("position", PackedVector3Array([Vector3(0, 5, 0)]), FlowDataScript.DataType.Vector)
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var hit = out.findStream("hit")
	assert_object(hit).is_not_null()
	assert_int(hit.container[0]).is_equal(1)
	var pos = out.findStream("position")
	# Top of the 20x1x20 box centered at origin is y = 0.5
	assert_float(pos.container[0].y).is_equal_approx(0.5, 0.05)
	var dist = out.findStream("dist")
	assert_float(dist.container[0]).is_equal_approx(4.5, 0.05)
	node.free()

func test_ray_misses_returns_zero_hit() -> void:
	var s = _settings()
	# Point far outside the 20x20 floor footprint, casting down into empty space
	var in_data = _make_data("position", PackedVector3Array([Vector3(1000, 5, 0)]), FlowDataScript.DataType.Vector)
	var node = await _run_against_floor(in_data, s)
	assert_str(node.err).is_empty()
	var hit = _output(node).findStream("hit")
	assert_int(hit.container[0]).is_equal(0)
	node.free()

func test_null_input_sets_error() -> void:
	var s = _settings()
	var node = _run_no_scene([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_position_stream_sets_error() -> void:
	var s = _settings()
	var d = _make_data("color", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = await _run_against_floor(d, s)
	assert_str(node.err).is_not_empty()
	node.free()
