@tool
extends FlowNodeBase

## Test-only node used by the evaluator suites (registered through
## FlowNodeRegistry.register_node_directory for the duration of a test).
##
## - Records its execution order and what it saw on its inputs in a static log.
## - Emits a "trail" String stream: the trails of input A then input B, followed
##   by its own name, so a consumer can prove which upstream data it received.
## - Tracks every instance (weakref + live counter) so tests can assert that
##   evaluate_graph frees the node instances it created.

static var exec_log : Array = []
static var instances : Array = []
static var live_count : int = 0

static func reset_probe_state() -> void:
	exec_log.clear()
	instances.clear()

static func executed_names() -> Array:
	var names := []
	for entry in exec_log:
		names.append(entry.name)
	return names

static func live_instances() -> Array:
	var alive := []
	for ref in instances:
		var obj = ref.get_ref()
		if obj != null and is_instance_valid(obj):
			alive.append(obj)
	return alive

func _init():
	meta_node = {
		"title" : "Test Probe",
		"ins" : [{ "label" : "A" }, { "label" : "B" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Test-only probe node",
	}
	live_count += 1
	instances.append(weakref(self))

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		live_count -= 1

func _trail_of(data) -> PackedStringArray:
	if data is FlowData.Data:
		var stream = data.findStream("trail")
		if stream != null and stream.data_type == FlowData.DataType.String:
			return stream.container
	return PackedStringArray()

func execute(ctx: FlowData.EvaluationContext):
	var in_a = get_optional_input(0)
	var in_b = get_optional_input(1)
	exec_log.append({
		"name": str(name),
		"a_size": in_a.size() if in_a is FlowData.Data else -1,
		"b_size": in_b.size() if in_b is FlowData.Data else -1,
		"a_data": in_a,
		"b_data": in_b,
		"a_trail": _trail_of(in_a),
		"b_trail": _trail_of(in_b),
		"depth": int(ctx.get_meta("flow_eval_depth", -1)),
	})
	var trail := PackedStringArray()
	trail.append_array(_trail_of(in_a))
	trail.append_array(_trail_of(in_b))
	trail.append(str(name))
	var out := FlowData.Data.new()
	out.registerStream("trail", trail, FlowData.DataType.String)
	set_output(0, out)
