@tool
extends FlowNodeBase

const BooleanNodeSettings = preload("res://addons/flow_nodes_editor/nodes/boolean_settings.gd")

func _init():
	meta_node = {
		"title" : "Boolean",
		"settings" : BooleanNodeSettings,
		"ins" : [{ "label": "In A", "multiple_connections" : false }, { "label": "In B", "multiple_connections" : false }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Applies boolean logic between streams and writes the result as a bool stream.\nOperand B resolves in order: constant, stream in Input B, stream in Input A, bool literal.",
		"aliases" : ["Boolean Op"],
		"category" : "Metadata",
	}

func getTitle() -> String:
	var op_idx = clampi(settings.operation, 0, BooleanNodeSettings.eOperation.keys().size() - 1)
	return "Boolean (%s)" % BooleanNodeSettings.eOperation.keys()[op_idx]

func _is_editor_missing_input_context(ctx : FlowData.EvaluationContext) -> bool:
	return is_ownerless_preview(ctx)

func _emit_empty_output() -> void:
	set_output(0, FlowData.Data.new())

func _to_bool(value) -> bool:
	match typeof(value):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return value
		TYPE_INT:
			return value != 0
		TYPE_FLOAT:
			return not is_zero_approx(value)
		TYPE_STRING:
			var s = String(value).strip_edges().to_lower()
			if s in ["true", "1", "yes", "on"]:
				return true
			if s in ["false", "0", "no", "off", ""]:
				return false
			return true
		TYPE_VECTOR2:
			return value.length_squared() > 0.0
		TYPE_VECTOR3:
			return value.length_squared() > 0.0
		TYPE_VECTOR4:
			return value.length_squared() > 0.0
		TYPE_COLOR:
			return not (is_zero_approx(value.r) and is_zero_approx(value.g) and is_zero_approx(value.b) and is_zero_approx(value.a))
		TYPE_OBJECT:
			return is_instance_valid(value)
	return false

func _try_parse_bool_literal(text: String, out_value: Array) -> bool:
	var s = text.strip_edges().to_lower()
	if s in ["true", "1", "yes", "on"]:
		out_value[0] = true
		return true
	if s in ["false", "0", "no", "off"]:
		out_value[0] = false
		return true
	if s == "":
		out_value[0] = false
		return true
	return false

func _apply_binary(op : BooleanNodeSettings.eOperation, a : bool, b : bool) -> bool:
	match op:
		BooleanNodeSettings.eOperation.And:
			return a and b
		BooleanNodeSettings.eOperation.Or:
			return a or b
		BooleanNodeSettings.eOperation.Xor:
			return a != b
		BooleanNodeSettings.eOperation.Imply:
			return (not a) or b
		BooleanNodeSettings.eOperation.Nand:
			return not (a and b)
		BooleanNodeSettings.eOperation.Nimply:
			return a and (not b)
		BooleanNodeSettings.eOperation.Nor:
			return not (a or b)
		BooleanNodeSettings.eOperation.Xnor:
			return a == b
	return false

func execute(ctx : FlowData.EvaluationContext):
	if not settings.out_name:
		setError("Output name can't be empty")
		return

	var in_dataA : FlowData.Data = require_input(0, ctx, "Input A")
	if in_dataA == null:
		return
	var sA = in_dataA.findStream(settings.in_nameA)
	if sA == null:
		if _is_editor_missing_input_context(ctx):
			_emit_empty_output()
			return
		setError("Input A %s not found" % settings.in_nameA)
		return

	var num_elems : int = in_dataA.size()
	var size_a : int = sA.container.size()
	if size_a != num_elems and size_a != 1:
		if _is_editor_missing_input_context(ctx):
			_emit_empty_output()
			return
		setError("Input A stream size mismatch (%d vs data size %d)" % [size_a, num_elems])
		return
	var broadcast_a = size_a == 1 and num_elems > 0
	var out_values := PackedByteArray()
	out_values.resize(num_elems)

	var op = clampi(settings.operation, 0, BooleanNodeSettings.eOperation.keys().size() - 1)
	var unary = settings.isSingleArgument()
	var b_values := PackedByteArray()

	if not unary:
		b_values.resize(num_elems)
		if settings.use_constant_b:
			b_values.fill(1 if settings.constant_b else 0)
		else:
			var source_b = null
			var in_dataB : FlowData.Data = get_optional_input(1)
			if in_dataB:
				source_b = in_dataB.findStream(settings.in_nameB)
			if source_b == null:
				# Fall back to A's data so a single-input graph can combine two
				# of its own streams (and the default "@last" resolves sensibly)
				source_b = in_dataA.findStream(settings.in_nameB)

			if source_b == null:
				var parsed = [false]
				if _try_parse_bool_literal(settings.in_nameB, parsed):
					b_values.fill(1 if parsed[0] else 0)
				else:
					if _is_editor_missing_input_context(ctx):
						_emit_empty_output()
						return
					setError("Input B %s not found, and can't be interpreted as a bool literal" % settings.in_nameB)
					return
			else:
				var src_size : int = source_b.container.size()
				if src_size != num_elems and src_size != 1:
					if _is_editor_missing_input_context(ctx):
						_emit_empty_output()
						return
					setError("Input sizes from A and B don't match (%d vs %d)" % [num_elems, src_size])
					return

				if src_size == 1 and num_elems > 0:
					var bv = _to_bool(source_b.container[0])
					b_values.fill(1 if bv else 0)
				else:
					for i in range(num_elems):
						var bv = _to_bool(source_b.container[i])
						b_values[i] = 1 if bv else 0

	for i in range(num_elems):
		var av = _to_bool(sA.container[0]) if broadcast_a else _to_bool(sA.container[i])
		var out_bool : bool
		if unary:
			out_bool = not av
		else:
			var bv = b_values[i] != 0
			out_bool = _apply_binary(op, av, bv)
		out_values[i] = 1 if out_bool else 0

	var out_data : FlowData.Data = in_dataA.duplicate()
	var err = out_data.registerStream(settings.out_name, out_values, FlowData.DataType.Bool)
	if err:
		setError(err)
		return

	set_output(0, out_data)
