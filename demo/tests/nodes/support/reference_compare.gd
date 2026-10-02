extends RefCounted

## Helpers for the WP13-P1 parity suites that run an optimized node script and
## its pre-optimization copy (tests/nodes/support/*_reference.gd) on the same
## input and require byte-identical results.

const H = preload("res://tests/nodes/support/point_node_harness.gd")

## Every error and warning logged while it is installed (script errors too).
class CaptureLogger extends Logger:
	var messages : Array = []
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		messages.append("%d:%s:%s" % [error_type, code, rationale])
	func _log_message(_message: String, _error: bool) -> void:
		pass

## Raw bytes of a Data: stream keys, names, types and containers in order,
## last_added_stream_name, tags, kind and data attributes.
static func data_bytes(data) -> PackedByteArray:
	if not (data is FlowData.Data):
		return var_to_bytes(str(data))
	var out := PackedByteArray()
	for key in data.streams:
		var stream : Dictionary = data.streams[key]
		out.append_array(var_to_bytes([str(key), str(stream.get("name")), int(stream.get("data_type", -1))]))
		var container = stream.get("container")
		if container is Array:
			out.append_array(var_to_bytes(var_to_str(container)))
		else:
			out.append_array(var_to_bytes(container))
	out.append_array(var_to_bytes([data.last_added_stream_name, data.tags, int(data.kind), var_to_str(data.data_attrs)]))
	return out

## Runs `script` once (point_node_harness exec) and returns
## [error text, bulk count, bytes of every emitted Data..., logged messages].
## Script errors it raised are cleared from GdUnit's monitor.
static func exec_logged(script, settings, inputs : Array) -> Array:
	var logger := CaptureLogger.new()
	OS.add_logger(logger)
	var r := H.exec(script, settings, inputs)
	OS.remove_logger(logger)
	var parts := [r.err, r.bulks.size()]
	for bulk in r.bulks:
		for data in bulk:
			parts.append(data_bytes(data))
	parts.append(logger.messages)
	clear_gdunit_script_errors()
	return parts

## Script errors raised by a node under test are compared through the logged
## messages (both implementations must raise the same ones); drop them from
## GdUnit's monitor so they do not fail the test on their own.
static func clear_gdunit_script_errors() -> void:
	var ctx = GdUnitThreadManager.get_current_context()
	if ctx == null:
		return
	var exec_ctx = ctx.get_execution_context()
	if exec_ctx != null and exec_ctx.error_monitor != null:
		exec_ctx.error_monitor.clear_logs()
