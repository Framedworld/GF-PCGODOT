@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Sample Mesh",
		"settings" : SampleMeshNodeSettings,
		"ins" : [{ "label": "Meshes", "data_type": FlowData.DataType.NodeMesh }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Mesh Sampler"],
		"category" : "Sampler",
		"tooltip" : "Samples points on mesh surfaces: random area-weighted, one per vertex,\nor one per triangle center. Writes density, seed and normal streams.",
	}
	
## Index buffer of a surface. A surface saved without an index buffer returns
## null at ARRAY_INDEX (assigning that to a typed PackedInt32Array is a runtime
## error), so read it untyped and fall back to an empty array; callers then
## synthesize 0..N-1 for the non-indexed triangle list.
static func _surface_indices(arrs: Array) -> PackedInt32Array:
	var raw = arrs[Mesh.ARRAY_INDEX] if arrs.size() > Mesh.ARRAY_INDEX else null
	if raw == null:
		return PackedInt32Array()
	return raw

## Uniform surface sampling on a MeshInstance3D
## - If `n` > 0, returns exactly n points.
## - Else if `density` > 0, returns round(total_area * density) points.
## Returns: { points: PackedVector3Array, normals: PackedVector3Array }
static func sampleMeshSurface(mi: MeshInstance3D, n: int = -1, density: float = -1.0, seed: int = 0) -> Dictionary:
	var mesh := mi.mesh
	assert(mesh != null)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var gt := mi.global_transform

	# Precompute triangles (in world space) and weights (areas)
	var tris := []            # array of [a,b,c] (Vector3s)
	var tri_normals := []     # per-triangle unit normals
	var tri_areas := PackedFloat32Array()
	var total_area := 0.0

	for s in mesh.get_surface_count():
		var arrs := mesh.surface_get_arrays(s)
		var vtx : PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var idx : PackedInt32Array = _surface_indices(arrs)

		# If the surface is non-indexed, synthesize indices 0..N-1 (already triangles in Godot)
		if idx.is_empty():
			idx = PackedInt32Array()
			idx.resize(vtx.size())
			for i in range(vtx.size()):
				idx[i] = i

		# Walk triangles
		for i in range(0, idx.size(), 3):
			var a := gt * vtx[idx[i + 0]]
			var b := gt * vtx[idx[i + 1]]
			var c := gt * vtx[idx[i + 2]]

			var area := 0.5 * ((b - a).cross(c - a)).length()
			if area <= 0.0:
				continue

			tris.append([a, b, c])
			tri_areas.push_back(area)
			total_area += area

			# Per-triangle normal (world space)
			# Godot front faces are wound clockwise: (c - a) x (b - a) points out of
			# the surface; (b - a) x (c - a) would point into it.
			tri_normals.append(((c - a).cross(b - a)).normalized())

	if tris.is_empty() or total_area <= 0.0:
		return { "points": PackedVector3Array(), "normals": PackedVector3Array() }

	# Decide sample count
	if n <= 0 and density > 0.0:
		n = int(round(total_area * density))
	if n <= 0:
		return { "points": PackedVector3Array(), "normals": PackedVector3Array() }

	# Cumulative distribution over triangle areas
	var cdf := PackedFloat32Array()
	cdf.resize(tri_areas.size())
	var run := 0.0
	for i in range(tri_areas.size()):
		run += tri_areas[i]
		cdf[i] = run

	# Helper: binary search CDF
	var pick_triangle = func(t: float) -> int:
		var lo := 0
		var hi := cdf.size() - 1
		while lo < hi:
			var mid := (lo + hi) >> 1
			if t <= cdf[mid]:
				hi = mid
			else:
				lo = mid + 1
		return lo

	# Sample points (barycentric: sqrt trick for uniform)
	var out_pts := PackedVector3Array()
	var out_nrm := PackedVector3Array()
	out_pts.resize(n)
	out_nrm.resize(n)

	for k in range(n):
		var r := rng.randf() * total_area
		var ti := pick_triangle.call(r)
		var tri = tris[ti]
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]

		# Uniform barycentric sampling
		var u := sqrt(rng.randf())
		var v := rng.randf()
		var w0 := 1.0 - u
		var w1 := u * (1.0 - v)
		var w2 := u * v

		var p := a * w0 + b * w1 + c * w2

		out_pts[k] = p
		out_nrm[k] = tri_normals[ti]  # (fast) per-triangle normal

	return { "points": out_pts, "normals": out_nrm }

## One point per (deduplicated) vertex, with world-space vertex normals.
## Vertices shared between surfaces/triangles are emitted once (quantized at *1000).
## Returns: { points: PackedVector3Array, normals: PackedVector3Array }
static func meshVertexPoints(mi: MeshInstance3D) -> Dictionary:
	var mesh := mi.mesh
	assert(mesh != null)

	var gt := mi.global_transform
	# Inverse-transpose keeps normals correct under non-uniform scale
	var normal_basis := gt.basis.inverse().transposed()

	var out_pts := PackedVector3Array()
	var out_nrm := PackedVector3Array()
	var seen := {}

	for s in mesh.get_surface_count():
		var arrs := mesh.surface_get_arrays(s)
		var vtx : PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var nrm_raw = arrs[Mesh.ARRAY_NORMAL]
		var nrm : PackedVector3Array = nrm_raw if nrm_raw != null else PackedVector3Array()

		for i in range(vtx.size()):
			var v := vtx[i]
			var key := Vector3i(int(round(v.x * 1000.0)), int(round(v.y * 1000.0)), int(round(v.z * 1000.0)))
			if seen.has(key):
				continue
			seen[key] = true
			out_pts.append(gt * v)
			var n := Vector3.UP
			if i < nrm.size():
				n = (normal_basis * nrm[i]).normalized()
			out_nrm.append(n)

	return { "points": out_pts, "normals": out_nrm }

## One point per triangle, placed at the triangle centroid with the face normal.
## Returns: { points: PackedVector3Array, normals: PackedVector3Array }
static func meshFaceCenterPoints(mi: MeshInstance3D) -> Dictionary:
	var mesh := mi.mesh
	assert(mesh != null)

	var gt := mi.global_transform
	var out_pts := PackedVector3Array()
	var out_nrm := PackedVector3Array()

	for s in mesh.get_surface_count():
		var arrs := mesh.surface_get_arrays(s)
		var vtx : PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var idx : PackedInt32Array = _surface_indices(arrs)

		if idx.is_empty():
			idx = PackedInt32Array()
			idx.resize(vtx.size())
			for i in range(vtx.size()):
				idx[i] = i

		for i in range(0, idx.size(), 3):
			var a := gt * vtx[idx[i + 0]]
			var b := gt * vtx[idx[i + 1]]
			var c := gt * vtx[idx[i + 2]]
			# Clockwise front faces: outward normal is (c - a) x (b - a).
			var face_n := (c - a).cross(b - a)
			if face_n.length_squared() <= 0.0:
				continue # degenerate triangle
			out_pts.append((a + b + c) / 3.0)
			out_nrm.append(face_n.normalized())

	return { "points": out_pts, "normals": out_nrm }

static func distance_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab = b - a
	var ap = p - a
	var l2 = ab.length_squared()
	if l2 == 0.0:
		return (p - a).length()
	var t = ap.dot(ab) / l2
	t = clamp(t, 0.0, 1.0)
	var closest_point = a + ab * t
	return (p - closest_point).length()

static func get_hard_edges(mi: MeshInstance3D, angle_threshold_deg: float) -> Array:
	var mesh := mi.mesh
	if not mesh:
		return []
		
	var gt := mi.global_transform
	var edge_map := {}
	
	for s in mesh.get_surface_count():
		var arrs := mesh.surface_get_arrays(s)
		var vtx : PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var idx : PackedInt32Array = _surface_indices(arrs)
		
		if idx.is_empty():
			idx = PackedInt32Array()
			idx.resize(vtx.size())
			for i in range(vtx.size()):
				idx[i] = i
				
		for i in range(0, idx.size(), 3):
			var a := gt * vtx[idx[i + 0]]
			var b := gt * vtx[idx[i + 1]]
			var c := gt * vtx[idx[i + 2]]
			
			# Clockwise front faces: outward normal is (c - a) x (b - a).
			var normal = (c - a).cross(b - a).normalized()
			
			var edges = [
				[a, b],
				[b, c],
				[c, a]
			]
			
			for edge in edges:
				var v0 = edge[0]
				var v1 = edge[1]
				
				# unique rounded key for vertex coordinates
				var k0 = Vector3i(int(round(v0.x * 1000.0)), int(round(v0.y * 1000.0)), int(round(v0.z * 1000.0)))
				var k1 = Vector3i(int(round(v1.x * 1000.0)), int(round(v1.y * 1000.0)), int(round(v1.z * 1000.0)))
				
				var key
				var actual_vertices
				if k0 < k1:
					key = [k0, k1]
					actual_vertices = [v0, v1]
				else:
					key = [k1, k0]
					actual_vertices = [v1, v0]
					
				if not edge_map.has(key):
					edge_map[key] = {
						"vertices": actual_vertices,
						"normals": [],
					}
				edge_map[key].normals.append(normal)
				
	var hard_edges = []
	var angle_threshold_rad = deg_to_rad(angle_threshold_deg)
	
	for key in edge_map:
		var edge_data = edge_map[key]
		var normals = edge_data.normals
		var is_hard = false
		
		if normals.size() == 1:
			is_hard = true # Boundary edge
		elif normals.size() == 2:
			var dot = normals[0].dot(normals[1])
			var angle = acos(clamp(dot, -1.0, 1.0))
			if angle >= angle_threshold_rad:
				is_hard = true
		else:
			is_hard = true # Non-manifold edge
			
		if is_hard:
			hard_edges.append(edge_data.vertices)
			
	return hard_edges

## Build a stable orthonormal Basis from a surface normal.
## - `normal` is the axis you want to align (default aligns to +Z).
## - `up` is your preferred up; a safe fallback is chosen if nearly parallel.
## - `axis` can be "z" (default), "y", or "x" for which axis the normal should align to.
static func basis_from_normal(normal: Vector3, up: Vector3 = Vector3.UP, axis: String = "z") -> Basis:
	var n := normal.normalized()
	if n.length() == 0.0 or not n.is_finite():
		return Basis.IDENTITY

	# Pick a safe up if nearly parallel to n
	var safe_up := up
	if abs(n.dot(safe_up)) > 0.999: # ~parallel
		# pick the axis least aligned with n
		safe_up = Vector3.UP if (abs(n.y) < 0.9) else Vector3.RIGHT

	# Build tangent/bitangent
	var t := safe_up.cross(n).normalized()    # tangent
	var b := n.cross(t)                       # bitangent; already unit-length if t,n are

	var basis: Basis
	match axis:
		"x":
			basis = Basis(n, t, b)            # X=n, Y=t, Z=b
		"y":
			basis = Basis(t, n, b)            # X=t, Y=n, Z=b
		_:
			basis = Basis(t, b, n)            # X=t, Y=b, Z=n (default: Z=n)

	return basis.orthonormalized()

func execute( ctx : FlowData.EvaluationContext ):

	var in_data : FlowData.Data = require_input(0, ctx, "Input 'Meshes'")
	if in_data == null:
		return
	var nodes = in_data.getContainerChecked( "node", FlowData.DataType.NodeMesh )
	if nodes == null:
		setError( "Input are not meshes")
		return

	var output := FlowData.Data.new()
	output.addCommonStreams( 0 )
	var spos := output.getVector3Container( FlowData.AttrPosition )
	var srot := output.getVector3Container( FlowData.AttrRotation )
	var snormals := PackedVector3Array()

	var num_samples = getSettingValue(ctx, "num_samples" )
	var density = getSettingValue(ctx, "density")
	var point_size = getSettingValue(ctx, "point_size")

	var discard_hard_edges = getSettingValue(ctx, "discard_hard_edges")
	var hard_edge_angle = getSettingValue(ctx, "hard_edge_angle_threshold")
	var hard_edge_dist = getSettingValue(ctx, "hard_edge_distance_threshold")

	if settings.mode == SampleMeshNodeSettings.eMode.UseDensity:
		num_samples = -1
	elif settings.mode == SampleMeshNodeSettings.eMode.UseNumSamples:
		density = -1.0

	var node_seed : int = effective_seed()
	var node_idx : int = -1
	for node in nodes:
		node_idx += 1
		var mesh : Mesh = node.mesh
		if mesh == null:
			continue
		var ans : Dictionary
		match settings.mode:
			SampleMeshNodeSettings.eMode.OnePerVertex:
				ans = meshVertexPoints( node )
			SampleMeshNodeSettings.eMode.FaceCenters:
				ans = meshFaceCenterPoints( node )
			_:
				# Decorrelate meshes: each mesh gets its own derived seed
				var mesh_seed : int = hash([ node_seed, node_idx ]) & 0x7fffffff
				ans = sampleMeshSurface( node, num_samples, density, mesh_seed )
		var points : PackedVector3Array = ans.points
		var normals : PackedVector3Array = ans.normals

		# Discard points close to hard edges
		if discard_hard_edges:
			var hard_edges = get_hard_edges(node, hard_edge_angle)
			if not hard_edges.is_empty():
				var filtered_pts := PackedVector3Array()
				var filtered_nrms := PackedVector3Array()
				for i in range(points.size()):
					var p = points[i]
					var too_close = false
					for edge in hard_edges:
						var dist = distance_to_segment(p, edge[0], edge[1])
						if dist < hard_edge_dist:
							too_close = true
							break
					if not too_close:
						filtered_pts.append(p)
						filtered_nrms.append(normals[i])
				points = filtered_pts
				normals = filtered_nrms

		var num_points := points.size()
		var base := spos.size()
		spos.resize( base + num_points )
		srot.resize( base + num_points )
		snormals.resize( base + num_points )
		for idx in range( num_points ):
			spos[base + idx] = points[idx]
			var n := normals[idx]
			srot[base + idx] = FlowData.basisToEuler( FlowData.basisFromNormal( n ) )
			snormals[base + idx] = n

	# All the samples have the same size
	var ssize := output.getVector3Container( FlowData.AttrSize )
	ssize.resize( spos.size() )
	var sample_size = Vector3.ONE * point_size
	ssize.fill(sample_size)

	# Density + per-point seed + surface normal streams (UE parity)
	var total := spos.size()
	var sdensity := PackedFloat32Array()
	sdensity.resize( total )
	sdensity.fill( 1.0 )
	output.registerStream( FlowData.AttrDensity, sdensity, FlowData.DataType.Float )
	var sseed := PackedInt32Array()
	sseed.resize( total )
	for i in range( total ):
		sseed[i] = FlowData.point_seed( spos[i], node_seed )
	output.registerStream( FlowData.AttrSeed, sseed, FlowData.DataType.Int )
	output.registerStream( FlowData.AttrNormal, snormals, FlowData.DataType.Vector )

	set_output( 0, output )
