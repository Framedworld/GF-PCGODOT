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
		var src_container = stream.container
		var src_size : int = src_container.size()
		if src_size > 0:
			var dst_idx : int = 0
			for src_idx : int in range(in_data.size()):
				# Honor broadcast (size-1) streams instead of indexing out of bounds
				# (FlowData.bcast_idx, inlined).
				var value = src_container[src_idx if src_size > 1 else 0]
				for offset_idx : int in range(offsets_count):
					out_container[dst_idx] = value
					dst_idx += 1
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

	# Everything that depends only on the offset index is resolved once, and
	# the settings are read once (a settings read or _setting_vec call per
	# output point cost more than the point itself). FlowData.eulerToBasis and
	# basisToEuler are inlined (the same engine calls, bit-identical).
	var scale_offsets : bool = settings.scale_offsets_by_anchor_size
	var local_space : bool = settings.local_space
	var combine_rotation : bool = settings.combine_rotation
	var inherit_anchor_size : bool = settings.inherit_anchor_size
	var offset_values := PackedVector3Array()
	var rotation_values := PackedVector3Array()
	var rotation_bases : Array[Basis] = []
	var size_values := PackedVector3Array()
	var label_values := PackedStringArray()
	for offset_idx : int in range(offsets_count):
		offset_values.append(_setting_vec(settings.offsets, offset_idx, Vector3.ZERO))
		var local_rot := _setting_vec(settings.rotations, offset_idx, Vector3.ZERO)
		rotation_values.append(local_rot)
		rotation_bases.append(Basis.from_euler(Vector3(deg_to_rad(local_rot.x), deg_to_rad(local_rot.y), deg_to_rad(local_rot.z))))
		size_values.append(_setting_vec(settings.sizes, offset_idx, Vector3.ONE))
		if offset_labels.size() > 0:
			label_values.append(settings.labels[offset_idx] if offset_idx < settings.labels.size() else str(offset_idx))
	var write_parent : bool = parent_indices.size() > 0
	var write_offset : bool = offset_indices.size() > 0
	var write_label : bool = offset_labels.size() > 0

	var anchor_eulers : PackedVector3Array = transforms.eulers
	var anchor_positions : PackedVector3Array = transforms.positions
	var anchor_sizes : PackedVector3Array = transforms.sizes
	var dst_idx : int = 0
	for src_idx : int in range(in_data.size()):
		var anchor_euler : Vector3 = anchor_eulers[src_idx]
		var anchor_basis := Basis.from_euler(Vector3(deg_to_rad(anchor_euler.x), deg_to_rad(anchor_euler.y), deg_to_rad(anchor_euler.z)))
		var anchor_pos : Vector3 = anchor_positions[src_idx]
		var anchor_size : Vector3 = anchor_sizes[src_idx]
		for offset_idx : int in range(offsets_count):
			var offset : Vector3 = offset_values[offset_idx]
			if scale_offsets:
				offset *= anchor_size
			out_positions[dst_idx] = anchor_pos + (anchor_basis * offset if local_space else offset)

			if combine_rotation:
				var e : Vector3 = (anchor_basis * rotation_bases[offset_idx]).get_euler()
				out_rotations[dst_idx] = Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))
			else:
				out_rotations[dst_idx] = anchor_euler + rotation_values[offset_idx]

			var local_size : Vector3 = size_values[offset_idx]
			out_sizes[dst_idx] = anchor_size * local_size if inherit_anchor_size else local_size

			if write_parent:
				parent_indices[dst_idx] = src_idx
			if write_offset:
				offset_indices[dst_idx] = offset_idx
			if write_label:
				offset_labels[dst_idx] = label_values[offset_idx]
			dst_idx += 1

	if parent_indices.size() > 0:
		out_data.registerStream(settings.parent_index_attribute, parent_indices, FlowData.DataType.Int)
	if offset_indices.size() > 0:
		out_data.registerStream(settings.offset_index_attribute, offset_indices, FlowData.DataType.Int)
	if offset_labels.size() > 0:
		out_data.registerStream(settings.label_attribute, offset_labels, FlowData.DataType.String)

	set_output(0, out_data)
