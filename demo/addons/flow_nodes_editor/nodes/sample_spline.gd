@tool
extends FlowNodeBase

const min_interval := 0.1

func _init():
	meta_node = {
		"title" : "Sample Spline",
		"settings" : SampleSplineNodeSettings,
		"ins" : [{ "label": "Splines", "data_type": FlowData.DataType.NodePath }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Spline Sampler"],
		"category" : "Sampler",
		"tooltip" : "Samples points along Path3D curves (uniform or random), or fills the\nclosed XZ polygon of the curve (grid/random/Poisson).",
	}

func get_polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.size() == 0:
		return Rect2()

	var min_x := polygon[0].x
	var max_x := polygon[0].x
	var min_y := polygon[0].y
	var max_y := polygon[0].y

	for point in polygon:
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)

	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func points3d_to_polygon2d(points3d : PackedVector3Array) -> PackedVector2Array:
	var num_points := points3d.size()
	var polygon := PackedVector2Array()
	polygon.resize( num_points )
	for i in range(num_points):
		polygon[i] = Vector2( points3d[i].x, points3d[i].z )
	return polygon

func addDistanceAttribute( output : FlowData.Data, target_points : PackedVector3Array, attr_name : String ):
	var spos := output.getVector3Container( FlowData.AttrPosition )
	var sdists : PackedFloat32Array = output.addStream( attr_name, FlowData.DataType.Float )
	sdists.resize( output.size() )

	var time_start_kdtree := Time.get_ticks_usec()
	var kdtree := GDKdTree.new()
	kdtree.set_points( target_points )
	if settings.trace: print( "spline.kdtree: %f (%d)" % [ Time.get_ticks_usec() - time_start_kdtree, target_points.size() ])

	var time_start_distance := Time.get_ticks_usec()
	var nearest_indices := kdtree.find_nearest_indices( spos )
	for src_idx in range( nearest_indices.size() ):
		var nearest_idx := nearest_indices[src_idx]
		sdists[src_idx] = ( spos[src_idx] - target_points[nearest_idx] ).length()
	if settings.trace: print( "spline.dist: %f" % [ Time.get_ticks_usec() - time_start_distance ])

func randomFillCurveInXZ(poly2d : PackedVector2Array, bounds : Rect2, count : int, rng : RandomNumberGenerator) -> PackedVector2Array:
	var points := PackedVector2Array()
	if poly2d.size() < 3:
		return points
	var attempts: int = 0
	var max_attempts := count * 20
	while points.size() < count and attempts < max_attempts:
		attempts += 1
		var p := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		if Geometry2D.is_point_in_polygon(p, poly2d):
			points.append(p)
	return points

func poissonFillCurveInXZ(poly2d : PackedVector2Array, bounds : Rect2, min_dist : float, rng : RandomNumberGenerator) -> PackedVector2Array:
	var points := PackedVector2Array()
	if poly2d.size() < 3:
		return points

	var cell_size := min_dist / 1.41421356
	var grid_width := int(ceil(bounds.size.x / cell_size)) + 1
	var grid_height := int(ceil(bounds.size.y / cell_size)) + 1

	var grid = []
	grid.resize(grid_width)
	for x in range(grid_width):
		grid[x] = []
		grid[x].resize(grid_height)
		grid[x].fill(-1)

	var active_list : Array[int] = []
	var start_found := false
	var start_p : Vector2
	for attempt in range(100):
		var p := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		if Geometry2D.is_point_in_polygon(p, poly2d):
			start_p = p
			start_found = true
			break

	if not start_found:
		return points

	points.append(start_p)
	active_list.append(0)

	var gx := int((start_p.x - bounds.position.x) / cell_size)
	var gy := int((start_p.y - bounds.position.y) / cell_size)
	grid[gx][gy] = 0

	while active_list.size() > 0:
		var active_idx := rng.randi() % active_list.size()
		var point_idx := active_list[active_idx]
		var base_p := points[point_idx]
		var found_candidate := false

		for k in range(30):
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(min_dist, 2.0 * min_dist)
			var candidate := base_p + Vector2(cos(angle), sin(angle)) * dist

			if not bounds.has_point(candidate):
				continue

			if not Geometry2D.is_point_in_polygon(candidate, poly2d):
				continue

			var cgx := int((candidate.x - bounds.position.x) / cell_size)
			var cgy := int((candidate.y - bounds.position.y) / cell_size)

			var too_close := false
			for nx in range(max(0, cgx - 2), min(grid_width, cgx + 3)):
				for ny in range(max(0, cgy - 2), min(grid_height, cgy + 3)):
					var neighboring_idx: int = grid[nx][ny]
					if neighboring_idx != -1:
						var other_p := points[neighboring_idx]
						if (candidate - other_p).length_squared() < min_dist * min_dist:
							too_close = true
							break
				if too_close:
					break

			if not too_close:
				points.append(candidate)
				var new_idx := points.size() - 1
				active_list.append(new_idx)
				grid[cgx][cgy] = new_idx
				found_candidate = true
				break

		if not found_candidate:
			active_list.remove_at(active_idx)

	return points

func rasterizeCurveInXZ( curve : Curve3D, uniform_interval : float, base : int ) -> PackedVector2Array:
	var points := curve.tessellate(2, 5)
	var points_size := points.size()
	var new_size := base + points_size

	# This uses XZ coords of input points
	var poly2d := points3d_to_polygon2d( points )
	var bounds := get_polygon_bounds( poly2d )
	bounds.position -= Vector2( 0.1, 0.1 )
	bounds.end += Vector2( 0.1, 0.1 )

	var new_points := PackedVector2Array()
	var hits := PackedFloat32Array()

	var time_start_grid := Time.get_ticks_usec()
	var height := bounds.size.y
	var num_steps : int = round( height / uniform_interval )
	var py := bounds.position.y
	var dy := uniform_interval
	var dx := uniform_interval
	for y in range( num_steps ):

		var left := Vector2( bounds.position.x, py )
		var right  := Vector2( bounds.end.x, py )
		var p0 := poly2d[ points_size - 1 ]
		hits.clear()
		for segment_id in range( points_size ):
			var p1 := poly2d[ segment_id ]
			var hit = Geometry2D.segment_intersects_segment( p0, p1, left, right )
			if hit:
				hits.append( hit.x )
			p0 = p1

		var num_hits := hits.size()
		if num_hits > 0 && (num_hits % 2 == 0):
			hits.sort()
			for q0 in range( 0, num_hits, 2 ):
				var px0 := hits[q0]
				var px1 := hits[q0+1]
				px0 = round( px0 / dx ) * dx
				px1 = round( px1 / dx ) * dx
				var width := px1 - px0
				var idx := int( width / dx )
				for x in range( idx ):
					new_points.append( Vector2( px0, py ) )
					px0 += dx
				new_points.append( Vector2( px0, py ) )
		py += dy
	if settings.trace: print( "spline.grid: %f" % [ Time.get_ticks_usec() - time_start_grid ])
	return new_points

func execute( ctx : FlowData.EvaluationContext ):

	var trace := settings.trace

	var in_data : FlowData.Data = require_input(0, ctx, "Input 'Splines'")
	if in_data == null:
		return
	var path3d_nodes = in_data.getContainerChecked( "node", FlowData.DataType.NodePath )
	if path3d_nodes == null:
		setError( "Input are not splines")
		return
	#print( "path3d_nodes", path3d_nodes)

	var output := FlowData.Data.new()
	output.addCommonStreams( 0 )
	var spos := output.getVector3Container( FlowData.AttrPosition )
	var srot := output.getVector3Container( FlowData.AttrRotation )
	var ssize := output.getVector3Container( FlowData.AttrSize )

	# Clamp locally — execute() must not write back into settings
	var uniform_interval: float = getSettingValue( ctx, "uniform_interval" )
	if uniform_interval < min_interval:
		uniform_interval = min_interval

	var adjust_to_borders : bool = getSettingValue( ctx, "adjust_to_borders" )

	if getSettingValue( ctx, "fill_curve" ):
		for path_3d in path3d_nodes:
			var curve : Curve3D = path_3d.curve
			var base := spos.size()

			var new_points : PackedVector2Array
			var fill_mode: int = getSettingValue( ctx, "fill_mode" )
			if fill_mode == 1: # Random
				var fill_count: int = getSettingValue( ctx, "num_random_samples" )
				var rng := RandomNumberGenerator.new()
				rng.seed = settings.random_seed
				var poly2d := points3d_to_polygon2d(curve.tessellate(2, 5))
				var bounds := get_polygon_bounds(poly2d)
				new_points = randomFillCurveInXZ(poly2d, bounds, fill_count, rng)
			elif fill_mode == 2: # Poisson
				var rng := RandomNumberGenerator.new()
				rng.seed = settings.random_seed
				var poly2d := points3d_to_polygon2d(curve.tessellate(2, 5))
				var bounds := get_polygon_bounds(poly2d)
				new_points = poissonFillCurveInXZ(poly2d, bounds, uniform_interval, rng)
			else: # Grid (0)
				new_points = rasterizeCurveInXZ( curve, uniform_interval, base )

			for hit in new_points:
				var hit3d := (path_3d.transform as Transform3D) * Vector3( hit.x, 0.0, hit.y )
				spos.append( hit3d )
				srot.append( Vector3.ZERO )

			if settings.distance_attribute:
				# Use the curve's bake cache at our interval, then restore it —
				# the Curve3D belongs to the scene, not to this node.
				var prev_bake_interval := curve.bake_interval
				curve.bake_interval = uniform_interval * 2.0
				var border_points := curve.get_baked_points()
				curve.bake_interval = prev_bake_interval

				var path_transform: Transform3D = path_3d.transform
				for i in range( border_points.size() ):
					border_points[i] = path_transform * border_points[i]
				addDistanceAttribute( output, border_points, settings.distance_attribute )

	else:
		var sampling_mode: int = getSettingValue( ctx, "sampling_mode" )
		if sampling_mode == 1: # Random
			var num_random_samples: int = getSettingValue( ctx, "num_random_samples" )
			if num_random_samples > 0:
				var rng := RandomNumberGenerator.new()
				rng.seed = settings.random_seed
				for path_3d in path3d_nodes:
					var curve : Curve3D = path_3d.curve
					var curve_length := curve.get_baked_length()
					var base := spos.size()
					spos.resize( base + num_random_samples )
					srot.resize( base + num_random_samples )
					ssize.resize( base + num_random_samples )
					var sample_size := Vector3.ONE * uniform_interval
					for idx in range( num_random_samples ):
						var offset := rng.randf() * curve_length
						var t := curve.sample_baked_with_rotation( offset )
						spos[base + idx] = path_3d.transform * t.origin

						var b : Basis = path_3d.transform.basis * t.basis
						srot[base + idx] = FlowData.basisToEuler( b )
						ssize[base + idx] = sample_size
		else: # Uniform
			for path_3d in path3d_nodes:
				var curve : Curve3D = path_3d.curve
				# Bake at our interval and restore afterwards — the Curve3D is a
				# scene resource, not ours to mutate persistently.
				var prev_bake_interval := curve.bake_interval
				curve.bake_interval = uniform_interval
				var base := spos.size()
				var curve_length := curve.get_baked_length()
				var num_samples := curve.get_baked_points().size()
				var expected_length := num_samples * uniform_interval
				var num_samples_float : float = num_samples - 1
				#print( "  curve: Base:%d Length:%f vs %f Samples:%d" % [ base, curve_length, expected_length, num_samples ] )
				if not adjust_to_borders:
					num_samples_float = ( curve_length / uniform_interval )
					num_samples = int( num_samples_float ) + 1

				if num_samples <= 0:
					curve.bake_interval = prev_bake_interval
					continue

				if getSettingValue( ctx, "sample_segments_centers" ):
					if num_samples > 2:
						num_samples -= 1
						spos.resize( base + num_samples )
						srot.resize( base + num_samples )
						ssize.resize( base + num_samples )
						for idx in range( num_samples ):
							var offset0 := idx * curve_length / float(num_samples )
							var offset1 := ( idx + 1 ) * curve_length / float(num_samples )
							var t0 := curve.sample_baked_with_rotation( offset0 )
							var t1 := curve.sample_baked_with_rotation( offset1 )
							var p0 : Vector3 = path_3d.transform * t0.origin
							var p1 : Vector3 = path_3d.transform * t1.origin
							spos[base + idx] = ( p0 + p1 ) * 0.5
							var front := p1 - p0
							var b := Basis.looking_at( front )
							srot[base + idx] = FlowData.basisToEuler( b )
							ssize[base + idx] = Vector3( 1.0, 1.0, front.length() )
				else:
					spos.resize( base + num_samples )
					srot.resize( base + num_samples )
					ssize.resize( base + num_samples )
					var sample_size := Vector3.ONE * uniform_interval
					for idx in range( num_samples ):
						var offset := 0.0 if num_samples_float <= 0.0 else idx * curve_length / num_samples_float
						var t := curve.sample_baked_with_rotation( offset )
						spos[base + idx] = path_3d.transform * t.origin

						var b : Basis = path_3d.transform.basis * t.basis
						srot[base + idx] = FlowData.basisToEuler( b )
						ssize[base + idx] = sample_size

						#print( "%d : %s %s" % [ idx, spos[ base+idx], srot[ base+idx ] ])

				curve.bake_interval = prev_bake_interval

		uniform_interval = 1.0

	# All the samples have the same size
	if ssize.size() != spos.size():
		ssize.resize( spos.size() )
		var sample_size := Vector3.ONE * uniform_interval
		ssize.fill(sample_size)

	# Density + per-point seed streams (UE parity)
	var num_points := spos.size()
	var node_seed : int = settings.random_seed
	var sdensity := PackedFloat32Array()
	sdensity.resize( num_points )
	sdensity.fill( 1.0 )
	output.registerStream( FlowData.AttrDensity, sdensity, FlowData.DataType.Float )
	var sseed := PackedInt32Array()
	sseed.resize( num_points )
	for i in range( num_points ):
		sseed[i] = FlowData.point_seed( spos[i], node_seed )
	output.registerStream( FlowData.AttrSeed, sseed, FlowData.DataType.Int )

	set_output( 0, output )
