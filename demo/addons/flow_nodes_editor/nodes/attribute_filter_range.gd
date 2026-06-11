@tool
extends FlowNodeBase

const AttributeFilterRangeNodeSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_filter_range_settings.gd")

func _init():
	meta_node = {
		"title" : "Attribute Filter Range",
		"settings" : AttributeFilterRangeNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Inside" }, { "label" : "Outside" }],
		"tooltip" : "Splits points by whether an attribute value falls inside a numeric range.\nEnable 'String Match Mode' to filter by comma-separated string values instead.",
	}

func _stream_value_as_float(stream, index : int) -> Array:
	var size = stream.container.size()
	if size <= 0:
		return [false, 0.0]
	var read_idx = index if size > 1 else 0
	if read_idx < 0 or read_idx >= size:
		return [false, 0.0]

	match stream.data_type:
		FlowData.DataType.Float:
			return [true, float(stream.container[read_idx])]
		FlowData.DataType.Int:
			return [true, float(stream.container[read_idx])]
		FlowData.DataType.Bool:
			return [true, 1.0 if stream.container[read_idx] != 0 else 0.0]
		FlowData.DataType.Vector:
			var v : Vector3 = stream.container[read_idx]
			return [true, v.length()]
		FlowData.DataType.Color:
			var c : Color = stream.container[read_idx]
			return [true, (c.r + c.g + c.b) / 3.0]
		FlowData.DataType.String:
			var s = String(stream.container[read_idx]).strip_edges()
			if s.is_valid_float():
				return [true, s.to_float()]
	return [false, 0.0]

func _passes_range(value : float, range_min : float, range_max : float) -> bool:
	var min_ok = value >= range_min if settings.inclusive_min else value > range_min
	if not min_ok:
		return false
	return value <= range_max if settings.inclusive_max else value < range_max

func execute(_ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = get_input(0)
	if in_data == null:
		setError("Input not found")
		return

	# Check point count before attribute lookup: an empty upstream (e.g. a filter that
	# matched nothing) legitimately has no streams yet, so skip the attribute check and
	# pass two empty outputs rather than spamming "Attribute not found" errors.
	var num_points = in_data.size()
	if num_points == 0:
		var empty = in_data.duplicate()
		set_output(0, empty)
		set_output(1, empty)
		return

	var attr_name = settings.attribute_name.strip_edges()
	if attr_name == "":
		setError("Attribute name can't be empty")
		return

	var stream = in_data.findStream(attr_name)
	if stream == null:
		setError("Attribute '%s' not found" % attr_name)
		return

	var stream_size = stream.container.size()
	if stream_size != num_points and stream_size != 1:
		setError("Attribute '%s' has %d values but input has %d points (expected %d or 1)" % [attr_name, stream_size, num_points, num_points])
		return

	# --- String match mode ---
	if settings.string_match_mode:
		var raw_values: String = settings.string_match_values
		var is_case_sensitive: bool = settings.case_sensitive
		var allowed: Dictionary = {}
		for token: String in raw_values.split(","):
			var clean: String = token.strip_edges()
			if clean != "":
				allowed[clean if is_case_sensitive else clean.to_lower()] = true

		if allowed.is_empty():
			setError("String match mode is on but no match values specified")
			return

		var inside := PackedInt32Array()
		var outside := PackedInt32Array()
		for i in range(num_points):
			var read_idx: int = i if stream_size > 1 else 0
			var val: String = str(stream.container[read_idx])
			var test_val: String = val if is_case_sensitive else val.to_lower()
			if allowed.has(test_val):
				inside.append(i)
			else:
				outside.append(i)

		set_output(0, in_data.filter(inside))
		set_output(1, in_data.filter(outside))
		return

	# --- Numeric range mode (original behaviour) ---
	var range_min = minf(settings.min_value, settings.max_value)
	var range_max = maxf(settings.min_value, settings.max_value)

	var inside := PackedInt32Array()
	var outside := PackedInt32Array()
	for i in range(num_points):
		var converted = _stream_value_as_float(stream, i)
		if not converted[0]:
			setError("Attribute '%s' must be Float/Int/Bool/Vector/Color/String(float-compatible)" % attr_name)
			return

		var value = float(converted[1])
		if settings.use_absolute_value:
			value = absf(value)

		if _passes_range(value, range_min, range_max):
			inside.append(i)
		else:
			outside.append(i)

	set_output(0, in_data.filter(inside))
	set_output(1, in_data.filter(outside))
