@tool
extends FlowNodeBase

# UE PCG parity: Find Convex Hull 2D. One hull per input Data, computed on the
# points projected to the X/Z plane (Godot is Y-up) with Andrew's monotone
# chain. Output points are the hull points, in hull order: counter-clockwise
# in the X/Z plane (positive shoelace area on (x, z)), starting at the point
# with the smallest x (then smallest z). The order depends only on positions,
# so it is stable under input reordering.

func _init():
	meta_node = {
		"title" : "Find Convex Hull 2D",
		"settings" : FindConvexHull2DNodeSettings,
		"aliases" : ["Find Convex Hull 2D", "Convex Hull", "Convex Hull 2D", "Hull"],
		"category" : "Spatial",
		"pure" : true,
		"main_thread" : false,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Keeps the points on the 2D convex hull of each input (positions projected to X/Z), in hull order:\ncounter-clockwise in the X/Z plane, starting at the smallest x. Every attribute is kept.\n'order_attribute' writes the hull index so the result can feed a closed spline.\nFewer than three distinct X/Z positions give the distinct points (a degenerate hull).",
	}

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

static func _cross( o : Vector3, a : Vector3, b : Vector3 ) -> float:
	return ( a.x - o.x ) * ( b.z - o.z ) - ( a.z - o.z ) * ( b.x - o.x )

## Monotone chain over `sorted_idx` (sorted by x then z, no duplicate x/z).
## `strict` drops collinear edge points.
static func _chain( positions : PackedVector3Array, sorted_idx : Array, strict : bool ) -> Array:
	var n := sorted_idx.size()
	var lower : Array = []
	for idx in sorted_idx:
		while lower.size() >= 2:
			var c := _cross( positions[ lower[-2] ], positions[ lower[-1] ], positions[ idx ] )
			if c < 0.0 or ( strict and c == 0.0 ):
				lower.pop_back()
			else:
				break
		lower.append( idx )
	var upper : Array = []
	for k in range( n - 1, -1, -1 ):
		var idx = sorted_idx[k]
		while upper.size() >= 2:
			var c := _cross( positions[ upper[-2] ], positions[ upper[-1] ], positions[ idx ] )
			if c < 0.0 or ( strict and c == 0.0 ):
				upper.pop_back()
			else:
				break
		upper.append( idx )
	lower.pop_back()
	upper.pop_back()
	return lower + upper

## Hull point indices of `positions`, in hull order. `seeds` (optional Int
## container, one per point) only breaks ties between identical positions.
func compute_hull( positions : PackedVector3Array, seeds, include_collinear : bool ) -> PackedInt32Array:
	var n := positions.size()
	var result := PackedInt32Array()
	if n == 0:
		return result
	_sort_pos = positions
	_sort_seed = seeds if seeds != null and seeds.size() == n else null
	var order : Array = range( n )
	order.sort_custom( _less )
	# One representative per distinct (x, z): the first in sort order.
	var unique : Array = []
	for idx in order:
		if unique.is_empty():
			unique.append( idx )
			continue
		var last : Vector3 = positions[ unique[-1] ]
		var p : Vector3 = positions[ idx ]
		if p.x == last.x and p.z == last.z:
			continue
		unique.append( idx )
	_sort_pos = PackedVector3Array()
	_sort_seed = null
	if unique.size() <= 2:
		return PackedInt32Array( unique )
	var hull : Array = _chain( positions, unique, true )
	if hull.size() <= 2:
		# Every point is collinear: the "hull" is a segment.
		return PackedInt32Array( unique if include_collinear else [ unique[0], unique[-1] ] )
	if include_collinear:
		hull = _chain( positions, unique, false )
	return PackedInt32Array( hull )

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return

	var n := in_data.size()
	var positions : PackedVector3Array = in_data.getVector3Container( FlowData.AttrPosition )
	if n > 0 and positions.size() != n:
		setError( "Input must provide a position stream with one value per point (got %d for %d points)" % [ positions.size(), n ] )
		return

	var seeds = in_data.getContainerChecked( FlowData.AttrSeed, FlowData.DataType.Int )
	var hull := compute_hull( positions, seeds, settings.include_collinear )
	var hull_count := hull.size()
	if settings.repeat_first_point and hull_count > 0:
		hull.append( hull[0] )

	var out_data : FlowData.Data = in_data.filter( hull )
	var order_attr : String = String( settings.order_attribute ).strip_edges()
	if order_attr != "":
		var order := PackedInt32Array()
		order.resize( hull.size() )
		for i in range( hull.size() ):
			order[i] = i
		var err = out_data.registerStream( order_attr, order, FlowData.DataType.Int )
		if err:
			setError( err )
			return
	set_output( 0, out_data )
