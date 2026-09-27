@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Copy",
		"settings" : CopyNodeSettings,
		"ins" : [{ "label": "Source" }, { "label": "Targets" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" :"Copies points using linear repeat offsets or source-to-target placement mode.\nSourceToTargets: 'Attribute Inheritance' picks which input's attributes the copies carry\n(SourceOnly by default; SourceFirst / TargetFirst merge both, the named side winning collisions; TargetOnly).\nTransforms are always composed from source and target regardless of that setting.",
		"category" : "Spatial",
	}

func _linear_copy(ctx : FlowData.EvaluationContext, in_data : FlowData.Data) -> FlowData.Data:
	var out_data := FlowData.Data.new()
	var trace := settings.trace
	var num_copies : int = getSettingValue(ctx, "num_copies")
	if trace:
		print("Copy.num_copies %d" % [num_copies])
	if num_copies <= 0:
		return FlowData.Data.new()

	# First create all the containers with the correct type. Pass the data_type
	# explicitly: Resource/Node streams use plain Array containers that fail
	# registerStream's type inference (used to error + crash on the next loop).
	for stream_name in in_data.streams:
		var istream = in_data.streams[stream_name]
		var container = out_data.newContainerOfType(istream.data_type)
		if container == null:
			setError("Failed to allocate stream '%s'" % stream_name)
			return null
		var err = out_data.registerStream(stream_name, container, istream.data_type)
		if err:
			setError(err)
			return null

	# Then duplicate the data N times
	for stream_name in in_data.streams:
		var ocontainer = out_data.streams[stream_name].container
		var icontainer = in_data.streams[stream_name].container
		for _n in range(num_copies):
			ocontainer.append_array(icontainer)

	# Transform data of each copy
	var isize := in_data.size()
	var in_trs := in_data.getTransformsStream()
	if in_trs:
		var step3d : Transform3D = Transform3D.IDENTITY
		var step_translation = getSettingValue(ctx, "translation")
		var step_rotation = getSettingValue(ctx, "rotation")
		step3d.origin = step_translation
		step3d.basis = FlowData.eulerToBasis(step_rotation)

		var spos := out_data.getVector3Container(FlowData.AttrPosition)
		var srot := out_data.getVector3Container(FlowData.AttrRotation)

		var acc_transforms : Array[Transform3D]
		var delta : Transform3D = Transform3D.IDENTITY
		for _j in range(num_copies):
			acc_transforms.push_back(delta)
			delta = delta * step3d

		for j in range(isize):
			var itrans := in_trs.atIndex(j)
			for n in range(num_copies):
				var base := n * isize
				var otrans : Transform3D = itrans * acc_transforms[n]
				spos[base + j] = otrans.origin
				srot[base + j] = FlowData.basisToEuler(otrans.basis)

	if settings.generate_copy_id.strip_edges() != "":
		var container = PackedInt32Array()
		container.resize(num_copies * isize)
		for n in range(num_copies):
			var base := n * isize
			for j in range(isize):
				container[base + j] = n
		out_data.registerStream(settings.generate_copy_id, container)

	return out_data

func _pick_source_index(target_idx : int, source_size : int, point_seed : int = 0, use_point_seed : bool = false) -> int:
	if source_size <= 0:
		return 0
	if settings.source_selection == CopyNodeSettings.eSourceSelection.RandomDeterministic:
		var local_rng := RandomNumberGenerator.new()
		# Per-point seed consumption (UE $Seed parity): prefer the target point's
		# own seed when its data carries a seed stream; legacy spacing otherwise.
		if use_point_seed:
			local_rng.seed = point_seed ^ effective_seed()
		else:
			local_rng.seed = effective_seed() + target_idx * 7919
		return local_rng.randi_range(0, source_size - 1)
	return target_idx % source_size

## Streams describing the point transform/extent. They are always produced by
## the transform composition below (from the source pick + target), never by
## attribute inheritance: a target rotation_quat, for instance, would otherwise
## win over the recomputed Euler rotation downstream.
const TRANSFORM_STREAMS := [
	FlowData.AttrPosition, FlowData.AttrRotation, FlowData.AttrRotationQuat,
	FlowData.AttrSize, FlowData.AttrBoundsMin, FlowData.AttrBoundsMax,
]

## Applies UE-style attribute inheritance to `out_data` (the source points already
## picked per target, so row i corresponds to target point i).
func _apply_attribute_inheritance(out_data : FlowData.Data, targets_data : FlowData.Data, mode : int) -> void:
	if mode == CopyNodeSettings.eAttributeInheritance.SourceOnly:
		return
	if mode == CopyNodeSettings.eAttributeInheritance.TargetOnly:
		for stream_name in out_data.streams.keys():
			if not TRANSFORM_STREAMS.has(StringName(stream_name)):
				out_data.streams.erase(stream_name)
		out_data.data_attrs = {}
	var target_wins : bool = mode != CopyNodeSettings.eAttributeInheritance.SourceFirst
	for stream_name in targets_data.streams:
		if TRANSFORM_STREAMS.has(StringName(stream_name)):
			continue
		var exists : bool = out_data.streams.has(stream_name)
		if exists and not target_wins:
			continue
		var tstream = targets_data.streams[stream_name]
		# Target rows map 1:1 onto output rows; broadcast (length-1) stays broadcast.
		var container = tstream.container.duplicate()
		if exists:
			# Replace in place: keeps the stream's position and avoids the
			# "Stream name conflict" warning when the types differ on purpose.
			out_data.streams[stream_name] = {
				"container" : container,
				"name" : stream_name,
				"data_type" : tstream.data_type,
			}
		else:
			out_data.registerStream(stream_name, container, tstream.data_type)
	for attr_name in targets_data.data_attrs:
		if out_data.data_attrs.has(attr_name) and not target_wins:
			continue
		out_data.data_attrs[attr_name] = targets_data.data_attrs[attr_name].duplicate(true)

func _source_to_targets_copy(source_data : FlowData.Data, targets_data : FlowData.Data) -> FlowData.Data:
	var source_size = source_data.size()
	var target_size = targets_data.size()
	if source_size == 0 or target_size == 0:
		return FlowData.Data.new()

	var target_seeds = targets_data.getContainerChecked(FlowData.AttrSeed, FlowData.DataType.Int)
	if target_seeds != null and target_seeds.size() != target_size:
		target_seeds = null

	var selected_source := PackedInt32Array()
	selected_source.resize(target_size)
	for i in range(target_size):
		selected_source[i] = _pick_source_index(i, source_size, target_seeds[i] if target_seeds != null else 0, target_seeds != null)

	var out_data = source_data.filter(selected_source)
	_apply_attribute_inheritance(out_data, targets_data, settings.attribute_inheritance)
	var source_trs = source_data.getTransformsStream()
	var target_trs = targets_data.getTransformsStream()
	if source_trs == null or target_trs == null:
		push_warning("Copy: SourceToTargets needs %s/%s/%s on both inputs — copies keep their source transforms" % [FlowData.AttrPosition, FlowData.AttrRotation, FlowData.AttrSize])
	if source_trs and target_trs:
		var out_pos = out_data.getVector3Container(FlowData.AttrPosition)
		var out_rot = out_data.getVector3Container(FlowData.AttrRotation)
		var out_size = out_data.getVector3Container(FlowData.AttrSize)

		for i in range(target_size):
			var src_idx = selected_source[i]
			var src_tr = source_trs.atIndex(src_idx)
			var tgt_tr = target_trs.atIndex(i)

			var final_tr : Transform3D
			if settings.combine_source_with_target_transform:
				final_tr = tgt_tr * src_tr
			else:
				final_tr = tgt_tr

			out_pos[i] = final_tr.origin
			out_rot[i] = FlowData.basisToEuler(final_tr.basis)
			if settings.inherit_target_scale:
				out_size[i] = target_trs.sizes[i]

	if settings.generate_copy_id.strip_edges() != "":
		var copy_ids := PackedInt32Array()
		copy_ids.resize(target_size)
		for i in range(target_size):
			copy_ids[i] = selected_source[i]
		out_data.registerStream(settings.generate_copy_id, copy_ids, FlowData.DataType.Int)

	if settings.write_target_index_attribute.strip_edges() != "":
		var target_ids := PackedInt32Array()
		target_ids.resize(target_size)
		for i in range(target_size):
			target_ids[i] = i
		out_data.registerStream(settings.write_target_index_attribute, target_ids, FlowData.DataType.Int)

	return out_data

func execute(ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, ctx, "Source input")
	if in_data == null:
		return

	if settings.mode == CopyNodeSettings.eMode.SourceToTargets:
		var targets_data : FlowData.Data = get_optional_input(1)
		if targets_data == null:
			if Engine.is_editor_hint() and ctx.owner == null:
				set_output(0, FlowData.Data.new())
				return
			setError("Targets input is required for SourceToTargets mode")
			return
		set_output(0, _source_to_targets_copy(in_data, targets_data))
		return

	var copied = _linear_copy(ctx, in_data)
	if copied == null:
		return
	set_output(0, copied)
