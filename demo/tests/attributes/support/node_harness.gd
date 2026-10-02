extends RefCounted

## Runs one node element outside a graph: settings + inputs -> execute -> outputs.
## Works whether FlowNodeBase is a Node (freed here) or a RefCounted element.

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

static func run(node_script, settings, inputs: Array):
	var node = node_script.new()
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	node.preExecute(ctx)
	node.execute(ctx)
	return node

## Output `port` of bulk `bulk`, or null.
static func output(node, port: int = 0, bulk: int = 0):
	if bulk >= node.generated_bulks.size():
		return null
	var b : Array = node.generated_bulks[bulk]
	if port >= b.size():
		return null
	return b[port]

## Runs and returns { err, out (port 0), node_outputs (all bulks) }, disposing the node.
static func exec(node_script, settings, inputs: Array) -> Dictionary:
	var node = run(node_script, settings, inputs)
	var result := {
		"err": String(node.err),
		"out": output(node, 0),
		"out1": output(node, 1),
		"bulks": node.generated_bulks.duplicate(),
	}
	dispose(node)
	return result

static func dispose(node) -> void:
	if node is Node and is_instance_valid(node):
		node.free()

static func data(streams: Dictionary) -> FlowData.Data:
	# streams: name -> [container, DataType]
	var d = FlowDataScript.Data.new()
	for stream_name in streams:
		var spec : Array = streams[stream_name]
		var err = d.registerStream(stream_name, spec[0], spec[1])
		assert(err == null, "harness registerStream %s: %s" % [stream_name, err])
	return d

static func values(d, stream_name: String) -> Array:
	if d == null:
		return []
	var s = d.findStream(stream_name)
	if s == null:
		return []
	var out := []
	for v in s.container:
		out.append(v)
	return out

static func dtype(d, stream_name: String) -> int:
	if d == null:
		return -1
	var s = d.findStream(stream_name)
	return -1 if s == null else s.data_type
