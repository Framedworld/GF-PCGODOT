extends RefCounted

## Shared helpers for the point and geometry node suites (WP4b). Drives a node
## script the way the evaluator does for one bulk: preExecute, set inputs,
## execute. Works whether FlowNodeBase is a Node or a RefCounted element.

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

## Instances `node_script` with `settings`, runs one bulk with `inputs` and
## returns the node. `ctx` defaults to a context with no owner (not a preview),
## so missing-input errors are reported.
static func run(node_script, settings, inputs : Array, ctx = null):
	var node = node_script.new()
	node.name = "under_test"
	node.settings = settings
	if ctx == null:
		ctx = make_ctx()
	node.preExecute(ctx)
	node.inputs = inputs
	node.execute(ctx)
	return node

## Runs one bulk like run(), disposes the node and returns
## { "err": String, "bulks": Array } so suites never leak node instances.
## result.bulks[bulk][port] is the emitted Data (see port()).
static func exec(node_script, settings, inputs : Array, ctx = null) -> Dictionary:
	var node = run(node_script, settings, inputs, ctx)
	var result := { "err": String(node.err), "bulks": node.generated_bulks.duplicate() }
	dispose(node)
	return result

## Data emitted on `port` of `bulk` in an exec() result, or null.
static func port(result : Dictionary, p : int = 0, bulk : int = 0):
	var bulks : Array = result.bulks
	if bulk >= bulks.size():
		return null
	var b : Array = bulks[bulk]
	if p >= b.size():
		return null
	return b[p]

## Runs another bulk on an already prepared node (multi-bulk tests).
static func run_bulk(node, inputs : Array, ctx) -> void:
	node.inputs = inputs
	node.execute(ctx)

static func make_ctx(owner : Node3D = null, seed : int = 0, params : Dictionary = {}):
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = owner
	ctx.seed = seed
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = params.duplicate()
	ctx.runtime_params["seed"] = seed
	return ctx

## Output Data of `port` in `bulk`, or null when the node did not emit it.
static func out(node, port : int = 0, bulk : int = 0):
	if bulk >= node.generated_bulks.size():
		return null
	var b : Array = node.generated_bulks[bulk]
	if port >= b.size():
		return null
	return b[port]

## Frees `node` when it is an Object that needs manual freeing.
static func dispose(node) -> void:
	if node == null or node is RefCounted:
		return
	if is_instance_valid(node):
		node.free()

## Point Data with position, rotation (zero), size (one) and any extra streams
## given as name -> packed container.
static func points(positions : Array, extra : Dictionary = {}):
	var d = FlowDataScript.Data.new()
	d.addCommonStreams(positions.size())
	var pos : PackedVector3Array = d.getContainerChecked("position", FlowDataScript.DataType.Vector)
	for i in range(positions.size()):
		pos[i] = positions[i]
	for key in extra:
		d.registerStream(key, extra[key])
	return d

## Reverses the point order of `data` (every stream), for reorder tests.
static func reversed(data):
	var idx := PackedInt32Array()
	for i in range(data.size() - 1, -1, -1):
		idx.append(i)
	return data.filter(idx)

## Sorted array of rounded positions, an order-independent fingerprint.
static func position_set(data) -> Array:
	var out := []
	if data == null:
		return out
	var pos = data.getVector3Container("position")
	for p in pos:
		out.append("%.3f,%.3f,%.3f" % [p.x, p.y, p.z])
	out.sort()
	return out
