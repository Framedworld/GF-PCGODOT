@tool
extends FlowNodeBase

const SplitSplinesSettings = preload("res://addons/flow_nodes_editor/nodes/split_splines_settings.gd")

func _init():
	meta_node = {
		"title" : "Split Splines",
		"category" : "Spatial",
		"settings" : SplitSplinesSettings,
		"ins" : [{ "label" : "Splines", "data_type" : FlowData.DataType.NodePath }],
		"outs" : [{ "label" : "Segments" }],
		"tooltip" : "Converts Path3D splines into segment-center points with start/end metadata.",
	}

func execute(_ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = get_input(0)
	if in_data == null:
		setError("Splines input not found")
		return
	var stream = in_data.findStream(settings.spline_stream_attribute)
	if stream == null or stream.data_type != FlowData.DataType.NodePath:
		setError("Input must provide a Path3D node stream named '%s'" % settings.spline_stream_attribute)
		return

	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	var sizes := PackedVector3Array()
	var starts := PackedVector3Array()
	var ends := PackedVector3Array()
	var segment_indices := PackedInt32Array()
	var spline_indices := PackedInt32Array()
	var spline_refs : Array = []

	var interval = maxf(0.001, settings.uniform_interval)
	for spline_idx in range(stream.container.size()):
		var path := stream.container[spline_idx] as Path3D
		if path == null or path.curve == null:
			continue
		# Bake at our interval and restore — the Curve3D is a scene resource, not
		# ours to mutate persistently (sampling must be non-destructive).
		var prev_bake_interval := path.curve.bake_interval
		path.curve.bake_interval = interval
		var baked := path.curve.get_baked_points()
		path.curve.bake_interval = prev_bake_interval
		if baked.size() < 2:
			continue
		for seg_idx in range(baked.size() - 1):
			var p0 : Vector3 = path.global_transform * baked[seg_idx]
			var p1 : Vector3 = path.global_transform * baked[seg_idx + 1]
			var delta := p1 - p0
			if delta.length_squared() <= 0.0000001:
				continue
			var center := (p0 + p1) * 0.5
			var basis := Basis.looking_at(delta.normalized(), Vector3.UP)
			positions.append(center)
			rotations.append(FlowData.basisToEuler(basis))
			sizes.append(Vector3(settings.segment_size_xy.x, settings.segment_size_xy.y, delta.length()))
			starts.append(p0)
			ends.append(p1)
			segment_indices.append(seg_idx)
			spline_indices.append(spline_idx)
			if settings.include_spline_ref:
				spline_refs.append(path)

	var out := FlowData.Data.new()
	out.addCommonStreams(positions.size())
	var op := out.getVector3Container(FlowData.AttrPosition)
	var orot := out.getVector3Container(FlowData.AttrRotation)
	var osize := out.getVector3Container(FlowData.AttrSize)
	# UE parity: unit scale; the segment extent (cross-section x/y, segment length
	# in z) is recorded as bounds so spawned meshes aren't stretched. The opt-in
	# legacy bridge keeps size = extent (old size-as-scale) when requested.
	var legacy : bool = settings.legacy_scale_from_extent
	for i in range(positions.size()):
		op[i] = positions[i]
		orot[i] = rotations[i]
		osize[i] = sizes[i] if legacy else Vector3.ONE
	out.setSymmetricBounds(sizes)
	if settings.out_start_attribute.strip_edges() != "":
		out.registerStream(settings.out_start_attribute, starts, FlowData.DataType.Vector)
	if settings.out_end_attribute.strip_edges() != "":
		out.registerStream(settings.out_end_attribute, ends, FlowData.DataType.Vector)
	if settings.out_segment_index_attribute.strip_edges() != "":
		out.registerStream(settings.out_segment_index_attribute, segment_indices, FlowData.DataType.Int)
	if settings.out_spline_index_attribute.strip_edges() != "":
		out.registerStream(settings.out_spline_index_attribute, spline_indices, FlowData.DataType.Int)
	if settings.include_spline_ref and settings.out_spline_attribute.strip_edges() != "":
		out.registerStream(settings.out_spline_attribute, spline_refs, FlowData.DataType.NodePath)
	set_output(0, out)
