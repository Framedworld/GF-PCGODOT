extends SceneTree

## Exact output fingerprint of every golden graph (docs/_round2/WP13-P1.md).
## A script, not a test. Run from demo/ with
##
##   godot --headless --path . -s res://tests/perf/exact_fingerprint.gd > fp.txt
##
## The golden suite (tests/golden) rounds float containers to 1/1000 before
## hashing, so a last-bit float change passes it. Performance work must not
## change a single bit, so this script evaluates the same graphs the golden
## suite discovers (same owners, same inputs) and prints, per graph and per
## node, a SHA-256 over the raw bytes of every container of every bulk and
## port, the stream names, order and types, tags, data attributes and kind,
## plus every node error and every warning or error message logged during the
## evaluation. Run it before and after a change and diff the two files; any
## difference means the change is not output-identical.
##
## FLOW_FP_FILTER: optional substring; only graph paths containing it run.

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const GoldenTest = preload("res://tests/golden/golden_graphs_test.gd")

class CaptureLogger extends Logger:
	var messages : PackedStringArray = PackedStringArray()
	var _mutex := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		messages.append("E%d %s %s" % [error_type, code, rationale])
		_mutex.unlock()
	func _log_message(message: String, error: bool) -> void:
		if error:
			_mutex.lock()
			messages.append("M " + message)
			_mutex.unlock()

var _frames := 0
var _logger := CaptureLogger.new()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_run()
	return true


func _run() -> void:
	var filter := OS.get_environment("FLOW_FP_FILTER")
	OS.add_logger(_logger)
	var count := 0
	for path in GoldenTest.discover_files():
		if filter != "" and not path.contains(filter):
			continue
		var ext : String = path.get_extension()
		if ext == "tscn" or ext == "scn":
			count += _evaluate_scene(path)
		else:
			var res = ResourceLoader.load(path)
			if res is FlowGraphResource:
				var owner := FlowGraphNode3D.new()
				owner.name = "GoldenOwner"
				root.add_child(owner)
				_evaluate(path, res, owner, {})
				root.remove_child(owner)
				owner.free()
				count += 1
	OS.remove_logger(_logger)
	print("exact_fingerprint: %d graphs" % count)


func _evaluate_scene(path: String) -> int:
	var packed = ResourceLoader.load(path)
	if not (packed is PackedScene):
		return 0
	var scene_root : Node = packed.instantiate()
	var flow_nodes := []
	if scene_root is FlowGraphNode3D:
		flow_nodes.append(scene_root)
	for n in scene_root.find_children("*", "", true, false):
		if n is FlowGraphNode3D:
			flow_nodes.append(n)
	if flow_nodes.is_empty():
		scene_root.free()
		return 0
	var graphs := {}
	for fn in flow_nodes:
		graphs[fn] = fn.graph
		fn.graph = null
	root.add_child(scene_root)
	var count := 0
	for fn in flow_nodes:
		var graph : FlowGraphResource = graphs[fn]
		fn.graph = graph
		if graph == null:
			continue
		_evaluate("%s::%s" % [path, str(scene_root.get_path_to(fn))], graph, fn, fn.args if fn.args != null else {})
		count += 1
	root.remove_child(scene_root)
	scene_root.free()
	return count


func _evaluate(key: String, graph: FlowGraphResource, owner: FlowGraphNode3D, inputs: Dictionary) -> void:
	var ctx := FlowData.EvaluationContext.new()
	ctx.owner = owner
	ctx.eval_id = 0
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = {}
	_logger.messages.clear()
	var executor := FlowExecutor.new()
	if not executor.begin(graph, inputs, ctx, {}, 0):
		print("%s: begin failed" % key)
		return
	var node_list : Array = executor.state["node_list"].duplicate()
	for node in executor.state["ordered_nodes"]:
		executor._run_element(node)
	var lines := PackedStringArray()
	for node in node_list:
		var parts := [str(node.err)]
		for bulk in node.generated_bulks:
			for data in bulk:
				parts.append(_data_bytes(data))
		lines.append("  %s: %s" % [str(node.name), _sha(parts)])
	var outputs := executor.finalize()
	var out_keys := outputs.keys()
	out_keys.sort()
	for out_key in out_keys:
		lines.append("  output %s: %s" % [str(out_key), _sha([_data_bytes(outputs[out_key])])])
	lines.append("  log: %s (%d messages)" % [_sha([var_to_bytes(_logger.messages)]), _logger.messages.size()])
	print(key)
	print("\n".join(lines))


func _data_bytes(data) -> PackedByteArray:
	if not (data is FlowData.Data):
		return var_to_bytes(str(data))
	var out := PackedByteArray()
	for stream_name in data.streams:
		var stream : Dictionary = data.streams[stream_name]
		out.append_array(var_to_bytes([str(stream_name), str(stream.get("name", "")), int(stream.data_type)]))
		var container = stream.container
		if container is Array:
			var tokens := PackedStringArray()
			for v in container:
				tokens.append(FlowNodeIO._snapshot_value_token(v) if v is Object else var_to_str(v))
			out.append_array(var_to_bytes(tokens))
		else:
			out.append_array(var_to_bytes(container))
	var attrs := PackedStringArray()
	for attr_name in data.data_attrs:
		var rec = data.data_attrs[attr_name]
		var value = rec.get("value", null) if rec is Dictionary else rec
		attrs.append("%s=%s" % [attr_name, FlowNodeIO._snapshot_value_token(value) if value is Object else var_to_str(value)])
	out.append_array(var_to_bytes([data.last_added_stream_name, data.tags, int(data.kind), attrs, data.shape.content_hash() if data.shape != null else 0]))
	return out


func _sha(parts : Array) -> String:
	var hctx := HashingContext.new()
	hctx.start(HashingContext.HASH_SHA256)
	for p in parts:
		var bytes : PackedByteArray = p if p is PackedByteArray else var_to_bytes(p)
		if bytes.size() > 0:
			hctx.update(bytes)
	return hctx.finish().hex_encode().substr(0, 16)
