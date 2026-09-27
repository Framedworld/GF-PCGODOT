@tool
extends FlowNodeBase

const PointOffsetsNodeSettings = preload("res://addons/flow_nodes_editor/nodes/point_offsets_settings.gd")

func _init():
	meta_node = {
		"title" : "Point Offsets",
		"settings" : PointOffsetsNodeSettings,
		"ins" : [{ "label": "Anchors" }],
		"outs" : [{ "label" : "Points" }],
		"tooltip" : "Creates child points around each input point using local or world offsets. Useful for sockets, tabletop dressing, seating layouts, and repeated prop clusters.\nRotations/sizes/labels shorter than the offsets list clamp to their last entry.\nWrites three bookkeeping columns by default: parent_index (Int, index of the anchor point),\noffset_index (Int, index into the offsets list) and offset_label (String, the offset's label or its index).\nClear an attribute name to skip writing that column.",
		"aliases" : ["children", "sockets", "local offsets", "scatter children"],
		"category" : "Spatial",
	}

func _copy_streams(in_data : FlowData.Data, out_count : int, offsets_count : int) -> FlowData.Data:
	var out_data := FlowData.Data.new()
	for stream_name in in_data.streams:
		var stream = in_data.streams[stream_name]
		var out_container = FlowData.Data.newContainerOfType(stream.data_type)
		out_container.resize(out_count)
		var src_size : int = stream.container.size()
		if src_size > 0:
			for src_idx : int in range(in_data.size()):
				# Honor broadcast (size-1) streams instead of indexing out of bounds.
				var read_idx : int = FlowData.bcast_idx(src_size, src_idx)
				for offset_idx : int in range(offsets_count):
					out_container[src_idx * offsets_count + offset_idx] = stream.container[read_idx]
		out_data.registerStream(stream.name, out_container, stream.data_type)
	out_data.tags = in_data.tags.duplicate()
	return out_data

func _setting_vec(values : Array[Vector3], idx : int, fallback : Vector3) -> Vector3:
	if values.is_empty():
		return fallback
	if idx < values.size():
		return values[idx]
	return values[values.size() - 1]

func execute(ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, ctx, "Anchors input")
	if in_data == null:
		return

	if in_data.size() == 0:
		set_output(0, FlowData.Data.new())
		return

	var transforms := in_data.getTransformsStream()
	if transforms == null:
		if is_ownerless_preview(ctx):
			set_output(0, FlowData.Data.new())
			return
		setError("Anchors must provide position, rotation, and size streams")
		return

	var offsets_count : int = settings.offsets.size()
	if offsets_count == 0:
		set_output(0, FlowData.Data.new())
		return

	var out_count : int = in_data.size() * offsets_count
	var out_data := _copy_streams(in_data, out_count, offsets_count)
	var out_positions : PackedVector3Array = out_data.cloneStream(FlowData.AttrPosition)
	var out_rotations : PackedVector3Array = out_data.cloneStream(FlowData.AttrRotation)
	var out_sizes : PackedVector3Array = out_data.cloneStream(FlowData.AttrSize)

	var parent_indices := PackedInt32Array()
	var offset_indices := PackedInt32Array()
	var offset_labels := PackedStringArray()
	if settings.parent_index_attribute.strip_edges() != "":
		parent_indices.resize(out_count)
	if settings.offset_index_attribute.strip_edges() != "":
		offset_indices.resize(out_count)
	if settings.label_attribute.strip_edges() != "":
		offset_labels.resize(out_count)

	for src_idx : int in range(in_data.size()):
		var anchor_basis := FlowData.eulerToBasis(transforms.eulers[src_idx])
		var anchor_pos := transforms.positions[src_idx]
		var anchor_size := transforms.sizes[src_idx]
		for offset_idx : int in range(offsets_count):
			var dst_idx : int = src_idx * offsets_count + offset_idx
			var offset := _setting_vec(settings.offsets, offset_idx, Vector3.ZERO)
			if settings.scale_offsets_by_anchor_size:
				offset *= anchor_size
			out_positions[dst_idx] = anchor_pos + (anchor_basis * offset if settings.local_space else offset)

			var local_rot := _setting_vec(settings.rotations, offset_idx, Vector3.ZERO)
			if settings.combine_rotation:
				out_rotations[dst_idx] = FlowData.basisToEuler(anchor_basis * FlowData.eulerToBasis(local_rot))
			else:
				out_rotations[dst_idx] = transforms.eulers[src_idx] + local_rot

			var local_size := _setting_vec(settings.sizes, offset_idx, Vector3.ONE)
			out_sizes[dst_idx] = anchor_size * local_size if settings.inherit_anchor_size else local_size

			if parent_indices.size() > 0:
				parent_indices[dst_idx] = src_idx
			if offset_indices.size() > 0:
				offset_indices[dst_idx] = offset_idx
			if offset_labels.size() > 0:
				offset_labels[dst_idx] = settings.labels[offset_idx] if offset_idx < settings.labels.size() else str(offset_idx)

	if parent_indices.size() > 0:
		out_data.registerStream(settings.parent_index_attribute, parent_indices, FlowData.DataType.Int)
	if offset_indices.size() > 0:
		out_data.registerStream(settings.offset_index_attribute, offset_indices, FlowData.DataType.Int)
	if offset_labels.size() > 0:
		out_data.registerStream(settings.label_attribute, offset_labels, FlowData.DataType.String)

	set_output(0, out_data)
