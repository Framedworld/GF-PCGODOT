@tool
extends FlowNodeBase

const BoundsOverlap = preload("res://addons/flow_nodes_editor/bounds_overlap_util.gd")

func _init():
	meta_node = {
		"title" : "Self Pruning",
		"settings" : SelfPruningSettings,
		"aliases" : ["Self Pruning"],
		"category" : "Filter",
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Rejects points that overlap previous points, or removes duplicate grid-cell points.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_dataA: FlowData.Data = require_input( 0, ctx )

	if in_dataA == null:
		return

	if settings.mode == SelfPruningSettings.ePruneMode.GridCell:
		_grid_cell_prune(in_dataA)
		return

	var posA = in_dataA.getVector3Container( FlowData.AttrPosition )
	if posA.is_empty():
		set_output( 0, FlowData.Data.new() )
		return
	var szA = in_dataA.getVector3Container( FlowData.AttrSize )
	if szA.size() != posA.size():
		if szA.size() == 1:
			# Broadcast the single size to every point
			var bsize : Vector3 = szA[0]
			szA = PackedVector3Array()
			szA.resize( posA.size() )
			szA.fill( bsize )
		elif szA.is_empty():
			szA = PackedVector3Array()
			szA.resize( posA.size() )
			szA.fill( Vector3.ONE )
		else:
			setError( "Input must provide %s with one entry per point (got %d, expected %d or 1)" % [ FlowData.AttrSize, szA.size(), posA.size() ] )
			return

	# Resolve effective per-point bounds (bounds_min/bounds_max when present,
	# else symmetric `size`). When no bounds streams exist, prune_centers == posA
	# and prune_sizes == szA, so the native broadphase inputs are byte-for-byte
	# identical to before. When bounds streams ARE present, self_pruning reads
	# them (UE parity) by feeding the equivalent center-offset + extent to the
	# unchanged native RTree.
	var prune_centers := posA
	var prune_sizes := szA
	var has_bounds : bool = in_dataA.hasStream(FlowData.AttrBoundsMin) and in_dataA.hasStream(FlowData.AttrBoundsMax)
	if has_bounds:
		var local := in_dataA.getEffectiveBounds()
		var lmin : PackedVector3Array = local.min
		var lmax : PackedVector3Array = local.max
		prune_centers = PackedVector3Array()
		prune_sizes = PackedVector3Array()
		prune_centers.resize(posA.size())
		prune_sizes.resize(posA.size())
		for i in range(posA.size()):
			var li : int = i if i < lmin.size() else 0
			prune_centers[i] = posA[i] + (lmin[li] + lmax[li]) * 0.5
			prune_sizes[i] = (lmax[li] - lmin[li]).abs()

	var tA = GDRTree.new()
	# Note: idxs_overlapped is the KEEP list returned by the native self_prune
	var result = tA.self_prune( prune_centers, prune_sizes, settings.keep_self_intersections )

	var density_function = settings.density_function if "density_function" in settings else SelfPruningSettings.eDensityFunction.Binary

	if density_function != SelfPruningSettings.eDensityFunction.Binary:
		set_output( 0, _attenuate_self_prune(in_dataA, posA, result.idxs_overlapped, density_function) )
		return

	var out_data : FlowData.Data = in_dataA.filter( result.idxs_overlapped )

	set_output( 0, out_data )

# Density-aware self-prune resolution (non-Binary). KEEPS every point; the points
# that would have been pruned have their density attenuated by their overlap with
# the kept (survivor) set, shaped by steepness. Culling is left to a downstream
# density_filter.
func _attenuate_self_prune(in_data : FlowData.Data, positions : PackedVector3Array, keep_indices : PackedInt32Array, density_function : int) -> FlowData.Data:
	var out_data : FlowData.Data = in_data.duplicate()
	var n := out_data.size()
	if n == 0:
		return out_data

	# Mark survivors; the complement is the pruned set we attenuate.
	var is_kept := {}
	for k in keep_indices:
		is_kept[int(k)] = true

	var boxes := BoundsOverlap.world_aabbs(out_data, positions)
	var bmin : PackedVector3Array = boxes.min
	var bmax : PackedVector3Array = boxes.max
	var steepness := out_data.getEffectiveSteepness()

	var densities : PackedFloat32Array
	var dsrc = out_data.getContainerChecked(FlowData.AttrDensity, FlowData.DataType.Float)
	if dsrc != null and dsrc.size() == n:
		densities = PackedFloat32Array(dsrc)
	else:
		densities = PackedFloat32Array()
		densities.resize(n)
		if dsrc != null and dsrc.size() == 1:
			densities.fill(dsrc[0])
		else:
			densities.fill(1.0)

	var fn_min : int = SelfPruningSettings.eDensityFunction.Minimum
	var fn_mul : int = SelfPruningSettings.eDensityFunction.Multiply
	var fn_sub : int = SelfPruningSettings.eDensityFunction.Subtract

	for idx in range(n):
		if is_kept.has(idx):
			continue
		var amin : Vector3 = bmin[idx]
		var amax : Vector3 = bmax[idx]
		# Strongest interpenetration against any survivor box.
		var best_ratio : float = 0.0
		for k in keep_indices:
			var ki : int = int(k)
			var r : float = BoundsOverlap.penetration_ratio(amin, amax, bmin[ki], bmax[ki])
			if r > best_ratio:
				best_ratio = r
				if best_ratio >= 1.0:
					break
		if best_ratio <= 0.0:
			continue
		var factor : float = BoundsOverlap.shape_factor(best_ratio, steepness[idx])
		densities[idx] = BoundsOverlap.fold_density(densities[idx], factor, density_function, fn_min, fn_mul, fn_sub)

	var err = out_data.registerStream(FlowData.AttrDensity, densities, FlowData.DataType.Float)
	if err:
		setError(err)
		return out_data
	return out_data

func _grid_cell_prune(in_data: FlowData.Data):
	var cell_size : float = settings.cell_size
	if cell_size <= 0.0:
		setError("Cell size must be greater than zero")
		return

	var positions = in_data.getVector3Container( FlowData.AttrPosition )
	if positions.is_empty():
		set_output(0, FlowData.Data.new())
		return

	var prefer_stream = null
	if settings.prefer_attribute != "":
		prefer_stream = in_data.findStream(settings.prefer_attribute)
		if prefer_stream == null:
			setError("Prefer attribute '%s' not found" % settings.prefer_attribute)
			return

	var cell_to_slot := {}
	var keep_indices := PackedInt32Array()

	for idx in range(in_data.size()):
		var pos = positions[idx]
		var key := Vector3i(
			int(round(pos.x / cell_size)),
			int(round(pos.y / cell_size)),
			int(round(pos.z / cell_size))
		)

		if not cell_to_slot.has(key):
			cell_to_slot[key] = keep_indices.size()
			keep_indices.append(idx)
			continue

		if prefer_stream != null and settings.prefer_value != "":
			var slot : int = cell_to_slot[key]
			var kept_idx : int = keep_indices[slot]
			var kept_is_preferred : bool = str(prefer_stream.container[kept_idx]) == settings.prefer_value
			var incoming_is_preferred : bool = str(prefer_stream.container[idx]) == settings.prefer_value
			if incoming_is_preferred and not kept_is_preferred:
				keep_indices[slot] = idx

	set_output( 0, in_data.filter( keep_indices ) )
