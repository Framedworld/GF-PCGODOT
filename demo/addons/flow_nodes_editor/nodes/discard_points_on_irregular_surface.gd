@tool
extends FlowNodeBase

# UE PCG parity: Discard Points On Irregular Surface.
#
# Unreal probes the surface under each point's footprint. Here the surface is
# the input point cloud itself: a point's neighbourhood is every input point
# whose position falls inside the point's X/Z footprint (its bounds, scaled by
# footprint_scale, as an axis-aligned box around the position like every other
# bounds consumer of the addon; any height). The point is discarded when the
# neighbourhood's height irregularity or normal spread exceeds the thresholds.
#
# Neighbour queries use the native GDRTree (the radius-query primitive the
# existing nodes use; GDKdTree only answers nearest-neighbour queries) when it
# is loaded, else a GDScript uniform grid. The exact footprint test and every
# sum run in a canonical position order, so both backends and any input order
# give identical results.

const SplitPoints = preload("res://addons/flow_nodes_editor/nodes/split_points.gd")

## Below this point count Auto uses the GDScript grid.
const NATIVE_MIN_POINTS := 64

func _init():
	meta_node = {
		"title" : "Discard Points On Irregular Surface",
		"settings" : DiscardPointsOnIrregularSurfaceNodeSettings,
		"aliases" : ["Discard Points On Irregular Surface", "Discard Points on Irregular Surface", "Irregular Surface Filter", "Flatness Filter", "Slope Roughness Filter"],
		"category" : "Filter",
		"pure" : true,
		"main_thread" : false,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Kept" }, { "label" : "Discarded" }],
		"tooltip" : "Discards points whose surroundings are not flat: the neighbourhood is every input point inside the point's\nX/Z bounds footprint (times footprint_scale). A point is discarded when the neighbourhood height metric\n(std-dev, plane-fit residual or max deviation) exceeds max_height_deviation, or a neighbour's normal\ndiffers by more than max_normal_angle degrees. Normals come from the normal attribute, else the rotation's up vector.\nPoints with fewer than min_neighbors neighbours are kept unless keep_isolated is off.",
	}

# --- canonical order ------------------------------------------------------

var _sort_pos : PackedVector3Array
var _sort_seed = null

func _less( a : int, b : int ) -> bool:
	var pa : Vector3 = _sort_pos[a]
	var pb : Vector3 = _sort_pos[b]
	if pa.x != pb.x:
		return pa.x < pb.x
	if pa.z != pb.z:
		return pa.z < pb.z
	if pa.y != pb.y:
		return pa.y < pb.y
	if _sort_seed != null:
		var sa : int = _sort_seed[a]
		var sb : int = _sort_seed[b]
		if sa != sb:
			return sa < sb
	return a < b

## rank[i] = position of point i in the canonical (x, z, y, seed) order.
func _canonical_rank( positions : PackedVector3Array, seeds ) -> PackedInt32Array:
	var n := positions.size()
	_sort_pos = positions
	_sort_seed = seeds if seeds != null and seeds.size() == n else null
	var order : Array = range( n )
	order.sort_custom( _less )
	_sort_pos = PackedVector3Array()
	_sort_seed = null
	var rank := PackedInt32Array()
	rank.resize( n )
	for r in range( n ):
		rank[ order[r] ] = r
	return rank

# --- neighbour search -----------------------------------------------------

static func native_available() -> bool:
	return ClassDB.class_exists( "GDRTree" )

## Candidate neighbours per point (superset of the footprint test), native.
static func _candidates_native( positions : PackedVector3Array, fp_min : PackedVector2Array, fp_max : PackedVector2Array ) -> Array:
	var n := positions.size()
	var tree = ClassDB.instantiate( "GDRTree" )
	var zero_sizes := PackedVector3Array()
	zero_sizes.resize( n )
	tree.add( positions, zero_sizes )
	var y_min := INF
	var y_max := -INF
	for p in positions:
		y_min = minf( y_min, p.y )
		y_max = maxf( y_max, p.y )
	var y_mid := ( y_min + y_max ) * 0.5
	var y_size := ( y_max - y_min ) + 2.0
	var center := PackedVector3Array()
	var size := PackedVector3Array()
	center.resize( 1 )
	size.resize( 1 )
	var result : Array = []
	result.resize( n )
	for i in range( n ):
		var lo : Vector2 = fp_min[i]
		var hi : Vector2 = fp_max[i]
		# Slightly enlarged box: the exact (inclusive) test runs afterwards.
		var pad := 1e-3 + ( hi - lo ).length() * 1e-6
		center[0] = Vector3( ( lo.x + hi.x ) * 0.5, y_mid, ( lo.y + hi.y ) * 0.5 )
		size[0] = Vector3( hi.x - lo.x + 2.0 * pad, y_size, hi.y - lo.y + 2.0 * pad )
		var hit : Dictionary = tree.overlaps( center, size, true )
		result[i] = hit.get( "idxs_overlapped", PackedInt32Array() )
	return result

## Candidate neighbours per point (superset of the footprint test), GDScript grid.
static func _candidates_grid( positions : PackedVector3Array, fp_min : PackedVector2Array, fp_max : PackedVector2Array ) -> Array:
	var n := positions.size()
	var mean_extent := 0.0
	for i in range( n ):
		var ext : Vector2 = fp_max[i] - fp_min[i]
		mean_extent += maxf( ext.x, ext.y )
	var cell := maxf( mean_extent / float( maxi( n, 1 ) ), 1e-4 )
	var grid := {}
	for j in range( n ):
		var key := Vector2i( floori( positions[j].x / cell ), floori( positions[j].z / cell ) )
		if not grid.has( key ):
			grid[key] = PackedInt32Array()
		grid[key].append( j )
	var all_idx := PackedInt32Array()
	all_idx.resize( n )
	for j in range( n ):
		all_idx[j] = j
	var result : Array = []
	result.resize( n )
	for i in range( n ):
		var c0 := Vector2i( floori( fp_min[i].x / cell ), floori( fp_min[i].y / cell ) )
		var c1 := Vector2i( floori( fp_max[i].x / cell ), floori( fp_max[i].y / cell ) )
		var cells : int = ( c1.x - c0.x + 1 ) * ( c1.y - c0.y + 1 )
		if cells > n:
			result[i] = all_idx
			continue
		var found := PackedInt32Array()
		for cx in range( c0.x, c1.x + 1 ):
			for cz in range( c0.y, c1.y + 1 ):
				var bucket = grid.get( Vector2i( cx, cz ), null )
				if bucket != null:
					found.append_array( bucket )
		result[i] = found
	return result

# --- metrics --------------------------------------------------------------

static func _std_dev( heights : PackedFloat64Array ) -> float:
	var k := heights.size()
	if k == 0:
		return 0.0
	var mean := 0.0
	for h in heights:
		mean += h
	mean /= float( k )
	var acc := 0.0
	for h in heights:
		acc += ( h - mean ) * ( h - mean )
	return sqrt( acc / float( k ) )

## RMS residual of the least-squares plane y = a*x + b*z + c through `pts`;
## -1 when the X/Z spread is degenerate (collinear or a single point).
static func _plane_residual( pts : PackedVector3Array ) -> float:
	var k := pts.size()
	if k < 3:
		return -1.0
	var mx := 0.0
	var my := 0.0
	var mz := 0.0
	for p in pts:
		mx += p.x
		my += p.y
		mz += p.z
	mx /= float( k )
	my /= float( k )
	mz /= float( k )
	var sxx := 0.0
	var sxz := 0.0
	var szz := 0.0
	var sxy := 0.0
	var szy := 0.0
	for p in pts:
		var dx : float = p.x - mx
		var dy : float = p.y - my
		var dz : float = p.z - mz
		sxx += dx * dx
		sxz += dx * dz
		szz += dz * dz
		sxy += dx * dy
		szy += dz * dy
	var det := sxx * szz - sxz * sxz
	var scale := maxf( sxx * szz, 1e-12 )
	if absf( det ) <= scale * 1e-9:
		return -1.0
	var a := ( sxy * szz - szy * sxz ) / det
	var b := ( szy * sxx - sxy * sxz ) / det
	var acc := 0.0
	for p in pts:
		var r : float = ( p.y - my ) - a * ( p.x - mx ) - b * ( p.z - mz )
		acc += r * r
	return sqrt( acc / float( k ) )

func _normals( in_data : FlowData.Data, n : int ) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize( n )
	var attr : String = String( settings.normal_attribute ).strip_edges()
	var stream = in_data.findStream( attr ) if attr != "" and in_data.streams.has( attr ) else null
	if stream != null and stream.data_type == FlowData.DataType.Vector and stream.container.size() > 0:
		var c : PackedVector3Array = stream.container
		for i in range( n ):
			var v : Vector3 = c[ FlowData.bcast_idx( c.size(), i ) ]
			out[i] = v.normalized() if v.length_squared() > 0.0 else Vector3.UP
		return out
	for i in range( n ):
		out[i] = SplitPoints.rotation_basis_at( in_data, i ).y.normalized()
	return out

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		if num_generated_bulks > 0 and generated_bulks[num_generated_bulks - 1].size() == 1:
			set_output( 1, FlowData.Data.new() )
		return

	var n := in_data.size()
	var positions : PackedVector3Array = in_data.getVector3Container( FlowData.AttrPosition )
	if n > 0 and positions.size() != n:
		setError( "Input must provide a position stream with one value per point (got %d for %d points)" % [ positions.size(), n ] )
		return

	var fs : float = maxf( 0.0, float( getSettingValue( ctx, "footprint_scale", settings.footprint_scale ) ) )
	var min_ext : float = maxf( 0.0, float( settings.min_footprint_extent ) )
	var max_h : float = float( getSettingValue( ctx, "max_height_deviation", settings.max_height_deviation ) )
	var max_a : float = float( getSettingValue( ctx, "max_normal_angle", settings.max_normal_angle ) )
	var min_nb : int = maxi( 0, int( settings.min_neighbors ) )
	var metric : int = int( settings.height_metric )

	# X/Z footprint per point (world space, axis aligned).
	var eff := in_data.getEffectiveBounds()
	var fp_min := PackedVector2Array()
	var fp_max := PackedVector2Array()
	fp_min.resize( n )
	fp_max.resize( n )
	for i in range( n ):
		var p : Vector3 = positions[i]
		var a : Vector3 = eff.min[i] * fs
		var b : Vector3 = eff.max[i] * fs
		var lo := Vector2( p.x + minf( a.x, b.x ), p.z + minf( a.z, b.z ) )
		var hi := Vector2( p.x + maxf( a.x, b.x ), p.z + maxf( a.z, b.z ) )
		for axis in range( 2 ):
			var w : float = hi[axis] - lo[axis]
			if w < min_ext:
				var mid : float = ( hi[axis] + lo[axis] ) * 0.5
				lo[axis] = mid - min_ext * 0.5
				hi[axis] = mid + min_ext * 0.5
		fp_min[i] = lo
		fp_max[i] = hi

	var use_native := false
	match int( settings.neighbor_search ):
		DiscardPointsOnIrregularSurfaceNodeSettings.eNeighborSearch.Auto:
			use_native = native_available() and n >= NATIVE_MIN_POINTS
		DiscardPointsOnIrregularSurfaceNodeSettings.eNeighborSearch.Native:
			use_native = native_available()
	var candidates : Array = []
	if n > 0:
		candidates = _candidates_native( positions, fp_min, fp_max ) if use_native else _candidates_grid( positions, fp_min, fp_max )

	var seeds = in_data.getContainerChecked( FlowData.AttrSeed, FlowData.DataType.Int )
	var rank := _canonical_rank( positions, seeds )
	var normals := _normals( in_data, n ) if max_a >= 0.0 or String( settings.normal_metric_attribute ).strip_edges() != "" else PackedVector3Array()

	var kept := PackedInt32Array()
	var discarded := PackedInt32Array()
	var h_metric := PackedFloat32Array()
	var a_metric := PackedFloat32Array()
	var nb_count := PackedInt32Array()
	h_metric.resize( n )
	a_metric.resize( n )
	nb_count.resize( n )

	for i in range( n ):
		var lo : Vector2 = fp_min[i]
		var hi : Vector2 = fp_max[i]
		var by_rank := {}
		for j in candidates[i]:
			if j == i:
				continue
			var q : Vector3 = positions[j]
			if q.x < lo.x or q.x > hi.x or q.z < lo.y or q.z > hi.y:
				continue
			by_rank[ rank[j] ] = j
		var others : Array = by_rank.keys()
		others.sort()
		nb_count[i] = others.size()
		if others.size() < min_nb:
			if settings.keep_isolated:
				kept.append( i )
			else:
				discarded.append( i )
			continue
		# Neighbourhood = the point and its neighbours, in canonical order.
		var hood := PackedInt32Array()
		var inserted := false
		for r in others:
			if not inserted and rank[i] < r:
				hood.append( i )
				inserted = true
			hood.append( by_rank[r] )
		if not inserted:
			hood.append( i )

		var h_value := 0.0
		if metric == DiscardPointsOnIrregularSurfaceNodeSettings.eHeightMetric.MaxDeviation:
			for j in hood:
				h_value = maxf( h_value, absf( positions[j].y - positions[i].y ) )
		else:
			var pts := PackedVector3Array()
			var heights := PackedFloat64Array()
			for j in hood:
				pts.append( positions[j] )
				heights.append( positions[j].y )
			h_value = -1.0
			if metric == DiscardPointsOnIrregularSurfaceNodeSettings.eHeightMetric.PlaneResidual:
				h_value = _plane_residual( pts )
			if h_value < 0.0:
				h_value = _std_dev( heights )
		h_metric[i] = h_value

		var a_value := 0.0
		if normals.size() == n:
			for j in hood:
				var d := clampf( normals[i].dot( normals[j] ), -1.0, 1.0 )
				a_value = maxf( a_value, rad_to_deg( acos( d ) ) )
		a_metric[i] = a_value

		var irregular := ( max_h >= 0.0 and h_value > max_h ) or ( max_a >= 0.0 and a_value > max_a )
		if irregular:
			discarded.append( i )
		else:
			kept.append( i )

	var out_kept : FlowData.Data = in_data.filter( kept )
	var out_discarded : FlowData.Data = in_data.filter( discarded )
	var extra := [
		[ String( settings.height_metric_attribute ).strip_edges(), h_metric, FlowData.DataType.Float ],
		[ String( settings.normal_metric_attribute ).strip_edges(), a_metric, FlowData.DataType.Float ],
		[ String( settings.neighbor_count_attribute ).strip_edges(), nb_count, FlowData.DataType.Int ],
	]
	for entry in extra:
		if entry[0] == "":
			continue
		var full = entry[1]
		for pair in [ [ out_kept, kept ], [ out_discarded, discarded ] ]:
			var target : FlowData.Data = pair[0]
			var idx : PackedInt32Array = pair[1]
			var sub = FlowData.Data.newContainerOfType( entry[2] )
			sub.resize( idx.size() )
			for k in range( idx.size() ):
				sub[k] = full[ idx[k] ]
			var err = target.registerStream( entry[0], sub, entry[2] )
			if err:
				setError( err )
				return

	set_output( 0, out_kept )
	set_output( 1, out_discarded )
