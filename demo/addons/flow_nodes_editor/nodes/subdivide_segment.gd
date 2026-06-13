@tool
extends FlowNodeBase

# Subdivide Segment (UE PCG parity: Subdivide Segment / Subdivide Spline).
#
# Slices each input span into sized sub-segments and emits one point per
# sub-segment at its center, oriented along the span (long axis = local Z /
# size.z). Each point carries `length`, `segment_index`, `t_start`, `t_end`
# (attribute names configurable). The geometric substrate for grammar_expand.

const SubdivideSegmentSettings = preload("res://addons/flow_nodes_editor/nodes/subdivide_segment_settings.gd")

func _init():
	meta_node = {
		"title" : "Subdivide Segment",
		"settings" : SubdivideSegmentSettings,
		"ins" : [{ "label" : "In", "data_type" : FlowData.DataType.NodePath }],
		"outs" : [{ "label" : "Segments" }],
		"aliases" : ["Subdivide Segment", "Subdivide Spline"],
		"category" : "Sampler",
		"tooltip" : "Slices spline or two-point spans into sized sub-segments, emitting one\noriented point per sub-segment with length/segment_index/t_start/t_end.",
	}

# A span is { "start": Vector3, "end": Vector3 } in world space.
func _collect_spans(in_data : FlowData.Data) -> Array:
	var spans : Array = []
	var mode : int = settings.input_mode
	if mode == SubdivideSegmentSettings.eInputMode.SPLINES:
		var stream = in_data.findStream(settings.spline_stream_attribute)
		if stream == null or stream.data_type != FlowData.DataType.NodePath:
			setError("SPLINES mode requires a Path3D node stream named '%s'" % settings.spline_stream_attribute)
			return []
		var interval : float = maxf(0.001, settings.bake_interval)
		for path in stream.container:
			var p := path as Path3D
			if p == null or p.curve == null:
				continue
			var prev_interval : float = p.curve.bake_interval
			p.curve.bake_interval = interval
			var baked := p.curve.get_baked_points()
			p.curve.bake_interval = prev_interval
			if baked.size() < 2:
				continue
			if settings.whole_spline_as_span:
				var a : Vector3 = p.global_transform * baked[0]
				var b : Vector3 = p.global_transform * baked[baked.size() - 1]
				if (b - a).length_squared() > 0.0000001:
					spans.append({ "start": a, "end": b })
			else:
				for i in range(baked.size() - 1):
					var s : Vector3 = p.global_transform * baked[i]
					var e : Vector3 = p.global_transform * baked[i + 1]
					if (e - s).length_squared() > 0.0000001:
						spans.append({ "start": s, "end": e })
	else:
		var start_stream = in_data.findStream(settings.segment_start_attribute)
		var end_stream = in_data.findStream(settings.segment_end_attribute)
		if start_stream == null or end_stream == null:
			setError("SEGMENTS mode requires Vector streams '%s' and '%s'" % [settings.segment_start_attribute, settings.segment_end_attribute])
			return []
		if start_stream.data_type != FlowData.DataType.Vector or end_stream.data_type != FlowData.DataType.Vector:
			setError("Segment start/end attributes must be Vector streams")
			return []
		var count : int = mini(start_stream.container.size(), end_stream.container.size())
		for i in range(count):
			var s : Vector3 = start_stream.container[i]
			var e : Vector3 = end_stream.container[i]
			if (e - s).length_squared() > 0.0000001:
				spans.append({ "start": s, "end": e })
	return spans

# Returns an Array of sub-segment lengths (in world units) that tile the span.
func _subdivide_lengths(span_length : float) -> Array:
	var out : Array = []
	if span_length <= 0.0:
		return out

	if settings.subdivide_mode == SubdivideSegmentSettings.eSubdivideMode.TARGET_COUNT:
		var n : int = maxi(1, settings.target_count)
		var seg : float = span_length / float(n)
		for i in range(n):
			out.append(seg)
		return out

	# MODULE_LENGTHS
	var modules : Array = []
	for m in settings.module_lengths:
		if m > 0.0:
			modules.append(float(m))
	if modules.is_empty():
		setError("module_lengths must contain at least one positive value")
		return out

	match settings.fit_mode:
		SubdivideSegmentSettings.eFitMode.STRETCH:
			# Treat module_lengths as a repeating ratio pattern scaled to fill the span.
			var pattern_sum : float = 0.0
			for m in modules:
				pattern_sum += m
			# Number of whole pattern repetitions that best fit, at least one.
			var reps : int = maxi(1, int(round(span_length / pattern_sum)))
			var raw : Array = []
			var total : float = 0.0
			for r in range(reps):
				for m in modules:
					raw.append(m)
					total += m
			var scale : float = span_length / total if total > 0.0 else 1.0
			for v in raw:
				out.append(v * scale)
		SubdivideSegmentSettings.eFitMode.CLIP:
			var consumed : float = 0.0
			var idx : int = 0
			while consumed + modules[idx % modules.size()] <= span_length + 0.000001:
				var l : float = modules[idx % modules.size()]
				out.append(l)
				consumed += l
				idx += 1
				if idx > 100000:
					break
			# Drop the final partial overrun (already excluded by the loop).
		SubdivideSegmentSettings.eFitMode.PAD_ENDS:
			var consumed2 : float = 0.0
			var idx2 : int = 0
			while consumed2 < span_length - 0.000001:
				var l2 : float = modules[idx2 % modules.size()]
				var remaining : float = span_length - consumed2
				if l2 > remaining:
					l2 = remaining
				out.append(l2)
				consumed2 += l2
				idx2 += 1
				if idx2 > 100000:
					break
	return out

func execute(ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return

	var spans := _collect_spans(in_data)
	if err:
		return

	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	var sizes := PackedVector3Array()
	var lengths := PackedFloat32Array()
	var seg_indices := PackedInt32Array()
	var t_starts := PackedFloat32Array()
	var t_ends := PackedFloat32Array()

	for span in spans:
		var a : Vector3 = span.start
		var b : Vector3 = span.end
		var dir : Vector3 = b - a
		var span_len : float = dir.length()
		if span_len <= 0.0000001:
			continue
		var ndir : Vector3 = dir / span_len
		# Choose an up vector that is not colinear with the span direction so
		# Basis.looking_at stays well-defined for vertical spans.
		var up_ref : Vector3 = Vector3.UP
		if absf(ndir.dot(Vector3.UP)) > 0.999:
			up_ref = Vector3.FORWARD
		var basis : Basis = Basis.looking_at(ndir, up_ref)

		var seg_lengths := _subdivide_lengths(span_len)
		if err:
			return
		var cursor : float = 0.0
		var seg_idx : int = 0
		for seg_len in seg_lengths:
			var l : float = float(seg_len)
			if l <= 0.0:
				continue
			var d_start : float = cursor
			var d_end : float = cursor + l
			var center : Vector3 = a + ndir * (d_start + l * 0.5)
			positions.append(center)
			rotations.append(FlowData.basisToEuler(basis))
			sizes.append(Vector3(settings.cross_section_size.x, settings.cross_section_size.y, l))
			lengths.append(l)
			seg_indices.append(seg_idx)
			t_starts.append(d_start / span_len)
			t_ends.append(minf(d_end / span_len, 1.0))
			cursor = d_end
			seg_idx += 1

	var num_points := positions.size()
	var out := FlowData.Data.new()
	out.addCommonStreams(num_points)
	var op := out.getVector3Container(FlowData.AttrPosition)
	var orot := out.getVector3Container(FlowData.AttrRotation)
	var osize := out.getVector3Container(FlowData.AttrSize)
	for i in range(num_points):
		op[i] = positions[i]
		orot[i] = rotations[i]
		osize[i] = sizes[i]

	if settings.out_length_attribute.strip_edges() != "":
		out.registerStream(settings.out_length_attribute, lengths, FlowData.DataType.Float)
	if settings.out_segment_index_attribute.strip_edges() != "":
		out.registerStream(settings.out_segment_index_attribute, seg_indices, FlowData.DataType.Int)
	if settings.out_t_start_attribute.strip_edges() != "":
		out.registerStream(settings.out_t_start_attribute, t_starts, FlowData.DataType.Float)
	if settings.out_t_end_attribute.strip_edges() != "":
		out.registerStream(settings.out_t_end_attribute, t_ends, FlowData.DataType.Float)

	# Density + per-point seed (sampler convention / UE parity).
	var node_seed : int = settings.random_seed
	var sdensity := PackedFloat32Array()
	sdensity.resize(num_points)
	sdensity.fill(1.0)
	out.registerStream(FlowData.AttrDensity, sdensity, FlowData.DataType.Float)
	var sseed := PackedInt32Array()
	sseed.resize(num_points)
	for i in range(num_points):
		sseed[i] = FlowData.point_seed(op[i], node_seed)
	out.registerStream(FlowData.AttrSeed, sseed, FlowData.DataType.Int)

	set_output(0, out)
