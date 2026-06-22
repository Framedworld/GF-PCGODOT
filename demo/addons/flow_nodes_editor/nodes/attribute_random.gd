@tool
extends FlowNodeBase

const AttributeRandomNodeSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_random_settings.gd")

func _init():
	meta_node = {
		"title" : "Attribute Random",
		"settings" : AttributeRandomNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Sets an attribute on points to random values or sequential indices.\nWhen the input carries a per-point seed stream, randomness is derived from it (UE $Seed parity).",
		"aliases" : ["Random Attribute"],
		"category" : "Metadata",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return

	if settings.attribute_name.strip_edges() == "":
		setError("Attribute name can't be empty")
		return

	var out_data : FlowData.Data = in_data.duplicate()
	var size = in_data.size()

	var seed_val : int = getSettingValue(ctx, "random_seed", 12345)
	var rng = RandomNumberGenerator.new()

	# Per-point seed consumption (UE $Seed parity): when the input has a seed
	# stream, each point's randomness comes from point_seed ^ node_seed so the
	# result is stable per point regardless of point order/count. Otherwise we
	# keep the legacy node-level reseeding behavior exactly.
	var point_seeds = in_data.getContainerChecked(FlowData.AttrSeed, FlowData.DataType.Int)
	if point_seeds != null and point_seeds.size() != size:
		point_seeds = null
	# When no seed stream exists, fall back to hashing the point position so the
	# result stays stable under reordering/count changes (UE parity) instead of
	# the old index-additive seed.
	var positions = in_data.getVector3Container(FlowData.AttrPosition)
	if positions != null and positions.size() != size and positions.size() != 1:
		positions = null

	var v_min = minf(settings.min_value, settings.max_value)
	var v_max = maxf(settings.min_value, settings.max_value)

	if settings.data_type == AttributeRandomNodeSettings.eType.Int:
		var container := PackedInt32Array()
		container.resize(size)
		for i in range(size):
			if settings.use_index_as_value:
				container[i] = i
			else:
				# Deterministic seed per point: prefer the point's own seed stream,
				# else hash its position; only fall back to index arithmetic if neither.
				rng.seed = FlowData.resolve_seed(point_seeds, positions, i, seed_val)
				container[i] = rng.randi_range(int(v_min), int(v_max))
		var err = out_data.registerStream(settings.attribute_name, container, FlowData.DataType.Int)
		if err:
			setError(err)
			return
	else:
		var container := PackedFloat32Array()
		container.resize(size)
		for i in range(size):
			if settings.use_index_as_value:
				container[i] = float(i)
			else:
				rng.seed = FlowData.resolve_seed(point_seeds, positions, i, seed_val)
				container[i] = rng.randf_range(v_min, v_max)
		var err = out_data.registerStream(settings.attribute_name, container, FlowData.DataType.Float)
		if err:
			setError(err)
			return

	set_output(0, out_data)
