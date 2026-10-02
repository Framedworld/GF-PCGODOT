@tool
extends FlowNodeBase

## Spawn Spline Mesh (Unreal's Spawn Spline Mesh / spline mesh component).
## Godot has no spline-mesh component, so each segment becomes a MeshInstance3D
## whose mesh is the source mesh bent along the segment (FlowSplineBend), cached
## by mesh, curve content, segment offsets and bend options.
##
## Input: splines. Today a NodePath stream of Path3D nodes (`spline_attribute`,
## "node" by default, as scan_splines and create_spline emit). Spline SHAPES are
## accepted through the segment extraction hook (`extract_segments`): a Data
## whose `shape` reports Kind.Spline and exposes a Curve3D (`get_curve()` or a
## `curve` property) plus optionally a Transform3D (`get_transform()` or a
## `transform` property) is used as well, without depending on the shape classes.
##
## Output: the input, passed through.

func _init():
	meta_node = {
		"title" : "Spawn Spline Mesh",
		"settings" : SpawnSplineMeshSettings,
		"aliases" : ["Spline Mesh Spawner", "Spawn Spline Mesh"],
		"category" : "Spawner",
		"ins" : [{ "label" : "Splines", "data_type" : FlowData.DataType.NodePath }],
		"outs" : [{ "label" : "Out" }],
		"is_final" : true,
		"main_thread" : true,
		"tooltip" : "Deforms a mesh along each segment of the input splines (Path3D nodes or spline shapes).\nOne MeshInstance3D per segment, with a bent ArrayMesh cached per mesh and segment.\nSettings: forward axis, tangent and up handling, scale along/across, per-segment mesh entries.",
	}

func removeInstancedSegments( parent : Node, ctx : FlowData.EvaluationContext = null ) -> void:
	removeOwnFlowContent( parent, ctx, func( child ): return child is MeshInstance3D )

# --- Segment extraction hook ---------------------------------------------------------

## The splines carried by `in_data`: Array of { curve : Curve3D, transform :
## Transform3D (curve space -> world), source : Object }. Sources: a spline shape
## on `in_data.shape` (duck-typed, see the file header) and the Path3D nodes of the
## `spline_attribute` stream. Returns null after setError when neither exists.
func extract_splines( in_data : FlowData.Data ) -> Variant:
	var splines : Array = splines_from_shape( in_data.shape )
	var attr : String = settings.spline_attribute.strip_edges()
	var container = in_data.container( attr ) if attr != "" else null
	if container == null:
		if splines.is_empty():
			setError( "Input has no '%s' stream of Path3D nodes and no spline shape" % attr )
			return null
		return splines
	var stream = in_data.findStream( attr )
	if stream.data_type != FlowData.DataType.NodePath and stream.data_type != FlowData.DataType.NodeMesh:
		setError( "'%s' stream must hold Path3D nodes (NodePath type)" % attr )
		return null
	for entry in container:
		if typeof( entry ) != TYPE_OBJECT or not is_instance_valid( entry ):
			continue
		var path := entry as Path3D
		if path == null or path.curve == null:
			continue
		var xf : Transform3D = path.global_transform if path.is_inside_tree() else path.transform
		splines.append( { "curve": path.curve, "transform": xf, "source": path } )
	return splines

## Spline shape adapter (duck-typed, so this node does not depend on the shape
## classes): an object whose get_kind() is Kind.Spline (or that has no get_kind)
## and that exposes a Curve3D through get_curve() or a `curve` property, plus an
## optional Transform3D through get_transform() or a `transform` property.
## Composite shapes (an object with `op`, `a` and `b`, such as the union that
## get_spline_data's Merged output carries) are walked depth first, `a` before
## `b`, so a merged union yields its splines in merge (Path3D) order:
##   Union, Intersection  the spline parts of both operands;
##   Difference           the spline parts of `a` only (`b` is subtracted).
## The set operation itself does not clip the spawned meshes: every spline part
## is spawned whole. Non-spline parts are skipped.
## Returns [] or [{ curve, transform, source }, ...].
static func splines_from_shape( shape ) -> Array:
	if shape == null or typeof( shape ) != TYPE_OBJECT or not is_instance_valid( shape ):
		return []
	if _is_composite( shape ):
		var out : Array = splines_from_shape( shape.get( "a" ) )
		if int( shape.get( "op" ) ) != FlowSpatial.Op.Difference:
			out.append_array( splines_from_shape( shape.get( "b" ) ) )
		return out
	if shape.has_method( "get_kind" ) and int( shape.get_kind() ) != FlowData.Kind.Spline:
		return []
	var curve = null
	if shape.has_method( "get_curve" ):
		curve = shape.get_curve()
	elif "curve" in shape:
		curve = shape.get( "curve" )
	if not ( curve is Curve3D ):
		return []
	var xf := Transform3D.IDENTITY
	if shape.has_method( "get_transform" ):
		xf = shape.get_transform()
	elif "transform" in shape and shape.get( "transform" ) is Transform3D:
		xf = shape.get( "transform" )
	return [ { "curve": curve, "transform": xf, "source": shape } ]

static func _is_composite( shape ) -> bool:
	return "op" in shape and "a" in shape and "b" in shape \
		and typeof( shape.get( "a" ) ) == TYPE_OBJECT and typeof( shape.get( "b" ) ) == TYPE_OBJECT

## Cuts one spline into segments: Array of { curve, from_offset, to_offset,
## transform }. ControlPoints: one segment per pair of consecutive control points
## (plus the closing one on a closed curve). TileMesh: round(length / tile_length)
## equal segments (at least one). Pure.
static func segments_for_spline( curve : Curve3D, transform : Transform3D, segmentation : int, tile_length : float ) -> Array:
	var out : Array = []
	if curve == null or curve.point_count < 2:
		return out
	var total := curve.get_baked_length()
	if total <= 1e-6:
		return out
	if segmentation == SpawnSplineMeshSettings.eSegmentation.TileMesh:
		var count := maxi( 1, roundi( total / maxf( tile_length, 1e-6 ) ) )
		var step := total / float( count )
		for i in range( count ):
			out.append( { "curve": curve, "from_offset": step * i, "to_offset": step * ( i + 1 ) if i < count - 1 else total, "transform": transform } )
		return out
	var offsets := PackedFloat32Array()
	for i in range( curve.point_count ):
		offsets.append( curve.get_closest_offset( curve.get_point_position( i ) ) )
	offsets[0] = 0.0
	if curve.get( "closed" ) == true:
		offsets.append( total )
	else:
		offsets[ offsets.size() - 1 ] = total
	var prev := offsets[0]
	for i in range( 1, offsets.size() ):
		var to := offsets[i]
		if to - prev > 1e-4:
			out.append( { "curve": curve, "from_offset": prev, "to_offset": to, "transform": transform } )
			prev = to
	return out

## THE segment extraction hook: every segment of every spline in `in_data`, as
## Array of { curve : Curve3D, from_offset : float, to_offset : float,
## transform : Transform3D, spline_index : int, segment_index : int }, or null
## after setError. A spline shape type only has to satisfy extract_splines (or
## this function can grow a branch for it); the bending and spawning code below
## only ever sees these dictionaries.
func extract_segments( in_data : FlowData.Data, tile_length : float ) -> Variant:
	var splines = extract_splines( in_data )
	if splines == null:
		return null
	var segments : Array = []
	for s in range( splines.size() ):
		var spline : Dictionary = splines[s]
		var cut := segments_for_spline( spline.curve, spline.transform, settings.segmentation, tile_length )
		for k in range( cut.size() ):
			var seg : Dictionary = cut[k]
			seg["spline_index"] = s
			seg["segment_index"] = k
			segments.append( seg )
	return segments

# --- Execution -------------------------------------------------------------------------

func _entries() -> Array:
	var out : Array = []
	for e in settings.mesh_entries:
		if e != null and e.mesh != null:
			out.append( e )
	if out.is_empty() and settings.mesh != null:
		var fallback := FlowMeshSpawnEntry.new()
		fallback.mesh = settings.mesh
		out.append( fallback )
	return out

func _pick_entry( entries : Array, seg : Dictionary, ordinal : int, rng : RandomNumberGenerator ) -> int:
	if entries.size() == 1:
		return 0
	if settings.segment_selection == SpawnSplineMeshSettings.eSegmentSelection.Weighted:
		var total := 0.0
		for e in entries:
			total += maxf( 0.0, e.weight )
		rng.seed = hash( [ effective_seed(), int( seg.spline_index ), int( seg.segment_index ) ] ) & 0x7fffffff
		var r := rng.randf()
		if total <= 0.0:
			return mini( int( r * entries.size() ), entries.size() - 1 )
		var t := r * total
		var accum := 0.0
		for i in range( entries.size() ):
			var w := maxf( 0.0, entries[i].weight )
			accum += w
			if t <= accum and w > 0.0:
				return i
		return entries.size() - 1
	return ordinal % entries.size()

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Splines" )
	if in_data == null:
		return
	if handleMissingOwner( ctx ):
		return
	var root : Node3D = ctx.owner
	if root == null or not is_instance_valid( root ):
		set_output( 0, in_data )
		return
	if root.get_tree() == null:
		setError( "Invalid current scene" )
		return
	var entries := _entries()
	if entries.is_empty():
		setError( "No mesh source configured. Provide mesh or mesh_entries." )
		return
	var ref_mesh : Mesh = entries[0].mesh
	var along := FlowSplineBend.forward_range( ref_mesh.get_aabb(), settings.forward_axis )
	var tile_length := maxf( along.y - along.x, 1e-3 ) * maxf( settings.scale_along, 1e-3 )
	var segments = extract_segments( in_data, tile_length )
	if segments == null:
		return

	var parent : Node3D = FlowSpawnUtil.resolve_path_parent( self, root, settings.spawn_parent_path )
	if settings.spawn_parent_attribute.strip_edges() != "":
		parent = FlowSpawnUtil.resolve_single_parent( self, in_data, settings.spawn_parent_attribute, root, parent )
	var scene_owner := FlowSpawnUtil.scene_owner_for( root )

	var clear_parents : Array = FlowSpawnUtil.unique_parents( previousContentParents( ctx ), parent )
	var pool : FlowSpawnPool = null
	if settings.clear_previous_instances:
		if settings.reuse_instances:
			pool = FlowSpawnPool.collect( self, clear_parents, ctx, func( child ): return child is MeshInstance3D )
		else:
			for p in clear_parents:
				removeInstancedSegments( p, ctx )

	var options := {
		"forward_axis": settings.forward_axis,
		"tangent_mode": settings.tangent_mode,
		"up_mode": settings.up_mode,
		"scale_start": settings.scale_across_start,
		"scale_end": settings.scale_across_end,
	}
	var to_parent := Transform3D.IDENTITY
	if parent.is_inside_tree():
		to_parent = parent.global_transform.affine_inverse()
	var rng := RandomNumberGenerator.new()
	var shapes := {}
	for k in range( segments.size() ):
		var seg : Dictionary = segments[k]
		var entry = entries[ _pick_entry( entries, seg, k, rng ) ]
		var bent := FlowSplineBend.bent_mesh_cached( entry.mesh, seg.curve, seg.from_offset, seg.to_offset, options )

		var pool_key := ""
		var mi : MeshInstance3D = null
		if pool != null:
			pool_key = "spline|" + FlowSpawnUtil.group_pool_key( FlowSpawnUtil.entry_group_key( entry ) )
			mi = pool.take( pool_key, parent ) as MeshInstance3D
		var reused := mi != null
		if not reused:
			mi = MeshInstance3D.new()
		FlowSpawnUtil.set_spawned_name( mi, "SplineMesh_%04d" % k )
		mi.mesh = bent
		mi.transform = to_parent * seg.transform
		mi.material_override = null
		FlowSpawnUtil.apply_render_settings( mi, entry )
		mi.set_meta( "spline_segment", { "spline": seg.spline_index, "segment": seg.segment_index, "from": seg.from_offset, "to": seg.to_offset } )
		if reused:
			FlowSpawnUtil.clear_collision( mi )
			FlowSpawnUtil.claim_spawned( self, mi, scene_owner, ctx )
		else:
			tagFlowContent( mi, ctx )
			FlowSpawnUtil.add_spawned_child( parent, mi )
			assignSpawnOwner( mi, scene_owner, ctx )
			if pool != null:
				FlowSpawnPool.tag( mi, pool_key )
		if entry.has_collision():
			var shape_key := [ bent, int( entry.collision_mode ) ]
			if not shapes.has( shape_key ):
				shapes[shape_key] = FlowSpawnUtil.build_collision_shape( bent, entry.collision_mode )
			var one : Array[Transform3D] = [ Transform3D.IDENTITY ]
			FlowSpawnUtil.build_collision( self, mi, entry, shapes[shape_key], one, scene_owner, ctx )
	if pool != null:
		pool.release_unused()

	if Engine.is_editor_hint():
		editor_mark_scene_unsaved()
	set_output( 0, in_data )
