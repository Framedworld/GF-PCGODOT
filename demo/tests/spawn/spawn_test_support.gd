extends RefCounted

## Shared helpers for the WP3 spawner suites (not a suite itself).
## A spawner element is run directly: inputs set, preExecute, execute, with a
## live FlowGraphNode3D owner, exactly like tests/nodes/spawn_*_test.gd.

const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

static func points(n : int, spacing := 1.0) -> FlowData.Data:
	var positions := []
	for i in range(n):
		positions.append(Vector3(i * spacing, 0, i * 2 * spacing))
	return TestGraph.points(positions)

static func run(node, input, owner, extra_inputs : Array = []) -> FlowData.EvaluationContext:
	node.inputs = [input] + extra_inputs
	var ctx = TestGraph.make_ctx(owner)
	node.preExecute(ctx)
	node.execute(ctx)
	return ctx

static func out(node):
	if node.generated_bulks.is_empty():
		return null
	return node.generated_bulks[0][0]

static func spawned(parent : Node, cls = null) -> Array:
	var result := []
	for child in parent.get_children():
		if not child.has_meta("flow_owner") or child.is_queued_for_deletion():
			continue
		if cls != null and not is_instance_of(child, cls):
			continue
		result.append(child)
	return result

static func ids(nodes : Array) -> Array:
	return nodes.map(func(n): return n.get_instance_id())

## The headless (dummy) RenderingServer does not store MultiMesh instance data,
## so per-instance transforms, colours and custom data can only be read back
## with a real renderer. Suites assert structure always and values when this
## returns true.
static func multimesh_readback_supported() -> bool:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)))
	return mm.get_instance_transform(0).origin == Vector3(1, 2, 3)

static func entry(mesh : Mesh, weight := 1.0) -> FlowMeshSpawnEntry:
	var e := FlowMeshSpawnEntry.new()
	e.mesh = mesh
	e.weight = weight
	return e
