@tool
extends FlowNodeBase

const AttributeFilterRangeNodeSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_filter_range_settings.gd")

func _init():
	meta_node = {
		"title" : "Attribute Filter Range",
		"settings" : AttributeFilterRangeNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Inside" }, { "label" : "Outside" }],
		"tooltip" : "Splits points by whether an attribute value falls inside a numeric range.\nEnable 'String Match Mode' to filter by comma-separated string values instead.\nCoercions: Vector filters by length(), Color by mean of r/g/b (alpha ignored),\nBool as 0/1 and float-parseable Strings by their numeric value.",
		"aliases" : ["Attribute Filter"],
		"category" : "Filter",
	}

func _stream_value_as_float(stream, index : int) -> Array:
	var size = stream.container.size()
	if size <= 0:
		return [false, 0.0]
	var read_idx = FlowData.bcast_idx(size, index)
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
	var in_data : FlowData.Data = require_input(0, _ctx)
	if in_data == null:
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
			var read_idx: int = FlowData.bcast_idx(stream_size, i)
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
	# Reject non-coercible stream types upfront; per-point failures (e.g. a single
	# non-parseable String) route that point to Outside instead of aborting the node.
	if stream.data_type not in [FlowData.DataType.Float, FlowData.DataType.Int, FlowData.DataType.Bool, FlowData.DataType.Vector, FlowData.DataType.Color, FlowData.DataType.String]:
		setError("Attribute '%s' must be Float/Int/Bool/Vector/Color/String(float-compatible)" % attr_name)
		return

	var range_min : float = minf(settings.min_value, settings.max_value)
	var range_max : float = maxf(settings.min_value, settings.max_value)
	var inclusive_min : bool = settings.inclusive_min
	var inclusive_max : bool = settings.inclusive_max
	var use_absolute_value : bool = settings.use_absolute_value

	# Every point's value as a float (the coercions of _stream_value_as_float),
	# converted once with a typed loop per stream type. `valid` is only needed
	# for String streams, where a non-parseable value goes to Outside.
	var values := PackedFloat64Array()
	values.resize(num_points)
	var valid := PackedByteArray()
	var broadcast : bool = stream_size == 1
	match stream.data_type:
		FlowData.DataType.Float:
			var c : PackedFloat32Array = stream.container
			for i in range(num_points):
				values[i] = c[0 if broadcast else i]
		FlowData.DataType.Int:
			var c : PackedInt32Array = stream.container
			for i in range(num_points):
				values[i] = float(c[0 if broadcast else i])
		FlowData.DataType.Bool:
			var c : PackedByteArray = stream.container
			for i in range(num_points):
				values[i] = 1.0 if c[0 if broadcast else i] != 0 else 0.0
		FlowData.DataType.Vector:
			var c : PackedVector3Array = stream.container
			for i in range(num_points):
				var v : Vector3 = c[0 if broadcast else i]
				values[i] = v.length()
		FlowData.DataType.Color:
			var c : PackedColorArray = stream.container
			for i in range(num_points):
				var col : Color = c[0 if broadcast else i]
				values[i] = (col.r + col.g + col.b) / 3.0
		_:
			valid.resize(num_points)
			for i in range(num_points):
				var converted = _stream_value_as_float(stream, i)
				valid[i] = 1 if converted[0] else 0
				values[i] = float(converted[1])

	var check_valid : bool = not valid.is_empty()
	var inside := PackedInt32Array()
	var outside := PackedInt32Array()
	for i in range(num_points):
		if check_valid and valid[i] == 0:
			# Non-parseable String value: it can never be inside a numeric range
			outside.append(i)
			continue

		var value : float = values[i]
		if use_absolute_value:
			value = absf(value)

		# Same test as _passes_range, with the settings read once.
		var passes : bool
		if inclusive_min:
			passes = value >= range_min
		else:
			passes = value > range_min
		if passes:
			if inclusive_max:
				passes = value <= range_max
			else:
				passes = value < range_max
		if passes:
			inside.append(i)
		else:
			outside.append(i)

	set_output(0, in_data.filter(inside))
	set_output(1, in_data.filter(outside))
