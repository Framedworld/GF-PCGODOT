@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Bounds Modifier",
		"settings" : BoundsModifierNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Modifies the size/bounds property on points in the provided point data.\nOnly the per-axis extent |max - min| is applied — the bounds center is ignored\n(point positions are unchanged, unlike UE which preserves min/max relative to the point).",
		"aliases" : ["Bounds Modifier"],
		"category" : "Spatial",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return

	var out_data : FlowData.Data = in_data.duplicate()

	var mode = settings.mode
	var b_min = settings.bounds_min
	var b_max = settings.bounds_max
	var output_mode = settings.output_mode if "output_mode" in settings else BoundsModifierNodeSettings.eOutput.SymmetricSize

	if output_mode == BoundsModifierNodeSettings.eOutput.PerPointBounds:
		_write_per_point_bounds(out_data, ctx, mode, b_min, b_max)
		return

	# Legacy default: collapse |max-min| into the symmetric `size` stream.
	if not out_data.hasStream(FlowData.AttrSize):
		if Engine.is_editor_hint() and ctx.owner == null:
			set_output(0, FlowData.Data.new())
			return
		setError("Input must provide a size stream")
		return
	var ssizes = out_data.cloneStream(FlowData.AttrSize)
	if ssizes == null:
		if Engine.is_editor_hint() and ctx.owner == null:
			set_output(0, FlowData.Data.new())
			return
		setError("Input must provide a size stream")
		return

	var size_val = (b_max - b_min).abs()

	for i in ssizes.size():
		if mode == BoundsModifierNodeSettings.eMode.Set:
			ssizes[i] = size_val
		elif mode == BoundsModifierNodeSettings.eMode.Add:
			ssizes[i] += size_val
		elif mode == BoundsModifierNodeSettings.eMode.Multiply:
			ssizes[i] = ssizes[i] * size_val

	var err = out_data.registerStream(FlowData.AttrSize, ssizes, FlowData.DataType.Vector)
	if err:
		setError(err)
		return
	set_output(0, out_data)

# Writes asymmetric per-point `bounds_min`/`bounds_max` streams. Existing bounds
# (resolved from explicit bounds streams, or symmetrically from `size`) provide
# the base for Add/Multiply; Set replaces them outright. `size` is left untouched.
func _write_per_point_bounds(out_data : FlowData.Data, ctx : FlowData.EvaluationContext, mode : int, b_min : Vector3, b_max : Vector3) -> void:
	var n := out_data.size()
	if n == 0:
		if Engine.is_editor_hint() and ctx.owner == null:
			set_output(0, FlowData.Data.new())
			return
		set_output(0, out_data)
		return

	var bounds := out_data.getEffectiveBounds()
	var base_min : PackedVector3Array = bounds.min
	var base_max : PackedVector3Array = bounds.max

	var new_min := PackedVector3Array()
	var new_max := PackedVector3Array()
	new_min.resize(n)
	new_max.resize(n)

	for i in range(n):
		if mode == BoundsModifierNodeSettings.eMode.Set:
			new_min[i] = b_min
			new_max[i] = b_max
		elif mode == BoundsModifierNodeSettings.eMode.Add:
			new_min[i] = base_min[i] + b_min
			new_max[i] = base_max[i] + b_max
		elif mode == BoundsModifierNodeSettings.eMode.Multiply:
			new_min[i] = base_min[i] * b_min
			new_max[i] = base_max[i] * b_max

	var err = out_data.registerStream(FlowData.AttrBoundsMin, new_min, FlowData.DataType.Vector)
	if err:
		setError(err)
		return
	err = out_data.registerStream(FlowData.AttrBoundsMax, new_max, FlowData.DataType.Vector)
	if err:
		setError(err)
		return
	set_output(0, out_data)
